#!/usr/bin/env python3
# Construye portal-a08-crear-bloqueo__TEST a partir del molde de seguridad validado de
# A07 v2. A08: una sola escritura atomica (crear_bloqueo), sin pago/confirmacion/recheck.
# id_cabana OBLIGATORIO (bloqueo total NO se expone - decision 8D). 10 nodos.
import json, copy, uuid, os

SRC = '/home/claude/a07_2/portal-a07-crear-reserva__TEST__TEMPLATE_v2.json'
OUT = '/home/claude/a08/portal-a08-crear-bloqueo__TEST__TEMPLATE.json'

wf = json.load(open(SRC))
byname = {n['name']: n for n in wf['nodes']}

VALIDAR_A08 = r'''// portal-a08-crear-bloqueo__TEST -- validar_firma_ts_rol (ESCRITURA / A08).
// Molde a05 (HMAC sobre buffer crudo, timing-safe, ventana ts, raw body binario con
// fallback, assert por prefijo __PEGAR_). A08:
//   - EXPECTED_ACTION = 'bloqueo.crear_manual'.
//   - actor (sobre firmado) contra enum de personas.
//   - payload REJECT-UNKNOWN + validacion ESTRICTA. id_cabana OBLIGATORIO (safe int > 0;
//     bloqueo total NO se expone en el portal, decision 8D). fechas YMD reales con
//     hasta > desde; motivo en enum; descripcion opcional.
const crypto = require('crypto');

const SECRET = (typeof $vars !== 'undefined' && $vars && $vars.VITA_HMAC_SECRET)
  ? $vars.VITA_HMAC_SECRET
  : '__PEGAR_SECRETO_O_USAR_VARIABLE__';
if (!SECRET || SECRET.startsWith('__PEGAR_')) {
  throw new Error('VITA_HMAC_SECRET no configurado (assert por prefijo, L-C-10).');
}

const ENUM_ACTOR  = ['vicky','franco','rodrigo','remo'];
const ROLES_OK    = ['vicky','socio'];
const ENUM_MOTIVO = ['mantenimiento','uso_propio','tormenta','overbooking','otro'];
const EXPECTED_ACTION = 'bloqueo.crear_manual';
const MAXLEN = 1000;

function rej(motivo, body) {
  body = body || {};
  return [{ json: { ok_firma:false, motivo, ambiente_esperado: body.ambiente_esperado ?? null,
    rol: body.rol ?? null, action: body.action ?? null, ts: (typeof body.ts!=='undefined'?body.ts:null),
    actor: body.actor ?? null, payload: null } }];
}

const item = $input.first();
const wh = item.json;

// 1) Raw body Buffer exacto (binario 'data' prioridad; fallback rawBody, L-C-05).
let buf = null;
try { if (item.binary && item.binary.data) buf = await this.helpers.getBinaryDataBuffer(0, 'data'); } catch (e) { buf = null; }
if (!buf) {
  const rawField = wh.rawBody;
  if (Buffer.isBuffer(rawField)) buf = rawField;
  else if (rawField && rawField.type === 'Buffer' && Array.isArray(rawField.data)) buf = Buffer.from(rawField.data);
  else if (typeof rawField === 'string') buf = Buffer.from(rawField, 'utf8');
}
if (!buf) return rej('raw_body_ausente', {});

// 2-4) Firma HMAC recomputada sobre los mismos bytes, comparacion timing-safe.
const headers = wh.headers || {};
const sigHeader = headers['x-vita-signature'] || headers['X-Vita-Signature'] || '';
const expected = 'sha256=' + crypto.createHmac('sha256', SECRET).update(buf).digest('hex');
let firmaOk = false;
try { const a = Buffer.from(sigHeader); const b = Buffer.from(expected); firmaOk = a.length === b.length && crypto.timingSafeEqual(a, b); } catch (e) { firmaOk = false; }
if (!firmaOk) return rej('firma_invalida', {});

// 5) Parseo (firma ya validada).
let body;
try { body = JSON.parse(buf.toString('utf8')); } catch (e) { return rej('payload_invalido', {}); }

// 6) Ventana ts +-300s.
const ts = Number(body.ts);
if (!Number.isFinite(ts) || Math.abs(Date.now() - ts) > 300000) return rej('ts_fuera_de_ventana', body);

// 7) Rol allowlist (D-C-39).
if (!ROLES_OK.includes(body.rol)) return rej('rol_no_permitido', body);
// 8) Action binding (D-C-41).
if (body.action !== EXPECTED_ACTION) return rej('accion_desconocida', body);
// 9) actor (sobre firmado; persona, no rol).
if (typeof body.actor !== 'string' || !ENUM_ACTOR.includes(body.actor)) return rej('payload_invalido', body);

// 10) Payload de negocio: REJECT-UNKNOWN + tipos estrictos.
const p = body.payload;
if (!p || typeof p !== 'object' || Array.isArray(p)) return rej('payload_invalido', body);

const PERMITIDAS = ['id_cabana','fecha_desde','fecha_hasta','motivo','descripcion'];
for (const k of Object.keys(p)) { if (!PERMITIDAS.includes(k)) return rej('payload_invalido', body); }

const isStr = (v) => typeof v === 'string';
const okLen = (v) => v.length <= MAXLEN;
// Fecha YYYY-MM-DD REAL: round-trip UTC (2027-02-30 -> rollover -> rechazado).
const isYMD = (s) => {
  if (!isStr(s) || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const Y = +s.slice(0,4), M = +s.slice(5,7), D = +s.slice(8,10);
  if (M < 1 || M > 12 || D < 1 || D > 31) return false;
  const dt = new Date(Date.UTC(Y, M - 1, D));
  return dt.getUTCFullYear() === Y && dt.getUTCMonth() === M - 1 && dt.getUTCDate() === D;
};

// id_cabana OBLIGATORIO (bloqueo total no se expone en el portal, 8D). safe int > 0.
if (typeof p.id_cabana !== 'number' || !Number.isSafeInteger(p.id_cabana) || p.id_cabana <= 0) return rej('payload_invalido', body);
if (!isYMD(p.fecha_desde) || !isYMD(p.fecha_hasta)) return rej('payload_invalido', body);
if (!(p.fecha_hasta > p.fecha_desde)) return rej('payload_invalido', body);
if (!ENUM_MOTIVO.includes(p.motivo)) return rej('payload_invalido', body);
if (p.descripcion != null && (!isStr(p.descripcion) || !okLen(p.descripcion))) return rej('payload_invalido', body);

const payloadWL = {
  id_cabana: p.id_cabana, fecha_desde: p.fecha_desde, fecha_hasta: p.fecha_hasta,
  motivo: p.motivo, descripcion: (p.descripcion != null ? p.descripcion : null)
};
return [{ json: { ok_firma:true, motivo:null, ambiente_esperado: body.ambiente_esperado ?? null,
  rol: body.rol, action: body.action, ts, actor: body.actor, payload: payloadWL } }];
'''

DERIVAR_A08 = r'''// portal-a08-crear-bloqueo__TEST -- Code: derivar. source_event PII-free determinístico
// (sin idem: A08 no es idempotente; el guard de solapamiento evita duplicados). crypto SHA-256.
const crypto = require('crypto');
const sha256hex = (s) => crypto.createHash('sha256').update(String(s), 'utf8').digest('hex');

const V = $('validar_firma_ts_rol').first().json;
const p = V.payload;
const actor = V.actor;

const ORDEN = ['id_cabana','fecha_desde','fecha_hasta','motivo','descripcion'];
const negocio = {
  id_cabana: p.id_cabana, fecha_desde: p.fecha_desde, fecha_hasta: p.fecha_hasta,
  motivo: p.motivo, descripcion: (p.descripcion != null ? p.descripcion : null)
};
const canon = JSON.stringify(ORDEN.map((k) => [k, negocio[k]]));
const hash12 = sha256hex(canon).slice(0, 12);
const source_event = `portal_test_a08_cab${p.id_cabana}_${p.fecha_desde}_${p.fecha_hasta}_${hash12}`;

const payload1Obj = {
  id_cabana: p.id_cabana, fecha_desde: p.fecha_desde, fecha_hasta: p.fecha_hasta,
  motivo: p.motivo, creado_por: actor, source_event: source_event
};
if (p.descripcion != null) payload1Obj.descripcion = p.descripcion;

return [{ json: { source_event, actor, payload1: JSON.stringify(payload1Obj) } }];
'''

ROUTER_A08 = r'''// router_bloqueo -- lee crear_bloqueo (columna 'resultado', L-8D-01). Mapea a envelope final.
// Terminal: no hay pasos siguientes (escritura atomica). conflicto_* y bloqueo_solapado ->
// conflicto; los 4 de datos -> payload_invalido; otro -> error_interno.
const res = $json.resultado;
function mapErr(e) {
  const conflicto  = ['conflicto_con_reserva','conflicto_con_prereserva','bloqueo_solapado'];
  const payloadInv = ['payload_invalido','fechas_invalidas','motivo_invalido','cabana_no_existe'];
  if (conflicto.includes(e))  return { ok:false, error: { code:'conflicto', message:'conflicto con reserva, prereserva o bloqueo en el rango', detail:null } };
  if (payloadInv.includes(e)) return { ok:false, error: { code:'payload_invalido', message:'datos de bloqueo rechazados: '+e, detail:null } };
  return { ok:false, error: { code:'error_interno', message:'no se pudo crear el bloqueo', detail:null } };
}
if (!res || res.ok !== true) return [{ json: mapErr(res ? res.error : null) }];
return [{ json: { ok:true, data: { id_bloqueo: res.id_bloqueo, id_cabana: res.id_cabana, tipo_bloqueo: res.tipo_bloqueo } } }];
'''

def clone(name): return copy.deepcopy(byname[name])

nodes = []
wh = clone('Webhook'); wh['parameters']['path'] = 'portal-a08-crear-bloqueo__TEST'; nodes.append(wh)
val = clone('validar_firma_ts_rol'); val['parameters']['jsCode'] = VALIDAR_A08; nodes.append(val)
nodes.append(clone('leer_ambiente'))
nodes.append(clone('verificar_acceso'))
nodes.append(clone('IF acceso'))
der = clone('Code: derivar'); der['parameters']['jsCode'] = DERIVAR_A08; nodes.append(der)
pg = clone('PG-1 crear_prereserva'); pg['name'] = 'PG crear_bloqueo'
pg['parameters']['query'] = 'SELECT crear_bloqueo($1::jsonb) AS resultado;'
pg['parameters']['options'] = {'queryReplacement': "={{ $('Code: derivar').first().json.payload1 }}"}
nodes.append(pg)
rt = clone('router1_crear'); rt['name'] = 'router_bloqueo'; rt['parameters']['jsCode'] = ROUTER_A08; nodes.append(rt)
nodes.append(clone('Code: render'))
nodes.append(clone('Respond'))

# Posiciones en linea + ids unicos
x = 0
for n in nodes:
    n['position'] = [x, 300]; n['id'] = str(uuid.uuid4()); x += 220

conns = {
  'Webhook': {'main': [[{'node':'validar_firma_ts_rol','type':'main','index':0}]]},
  'validar_firma_ts_rol': {'main': [[{'node':'leer_ambiente','type':'main','index':0}]]},
  'leer_ambiente': {'main': [[{'node':'verificar_acceso','type':'main','index':0}]]},
  'verificar_acceso': {'main': [[{'node':'IF acceso','type':'main','index':0}]]},
  'IF acceso': {'main': [[{'node':'Code: derivar','type':'main','index':0}], [{'node':'Code: render','type':'main','index':0}]]},
  'Code: derivar': {'main': [[{'node':'PG crear_bloqueo','type':'main','index':0}]]},
  'PG crear_bloqueo': {'main': [[{'node':'router_bloqueo','type':'main','index':0}]]},
  'router_bloqueo': {'main': [[{'node':'Code: render','type':'main','index':0}]]},
  'Code: render': {'main': [[{'node':'Respond','type':'main','index':0}]]},
}

wf08 = copy.deepcopy(wf)
wf08['name'] = 'portal-a08-crear-bloqueo__TEST'
wf08['nodes'] = nodes
wf08['connections'] = conns
wf08['active'] = False
wf08.pop('pinData', None)

json.dump(wf08, open(OUT,'w'), indent=2, ensure_ascii=False)

# ---- Asserts ----
names = [n['name'] for n in nodes]
assert len(nodes) == 10, f'esperaba 10 nodos, hay {len(nodes)}'
assert names.count('Code: derivar') == 1 and names.count('PG crear_bloqueo') == 1 and names.count('router_bloqueo') == 1
assert "bloqueo.crear_manual" in val['parameters']['jsCode']
assert "id_cabana OBLIGATORIO" in val['parameters']['jsCode']
assert "crear_bloqueo($1::jsonb)" in pg['parameters']['query']
assert "portal_test_a08_cab" in der['parameters']['jsCode']
assert wf08['active'] is False
# Todos los nodos referenciados en conns existen
refs = set()
for src, c in conns.items():
    refs.add(src)
    for arr in c['main']:
        for link in arr: refs.add(link['node'])
for r in refs:
    assert r in names, f'conexion referencia nodo inexistente: {r}'
print('OK: A08 template generado con', len(nodes), 'nodos')
print('nodos:', names)
print('archivo:', OUT)
