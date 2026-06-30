#!/usr/bin/env python3
# build_a26_wrapper.py
# Carril C / Portal Operativo Interno - Bloque A (A26 disponibilidad.cabana). OPCION B.
# Construye portal-a26-disponibilidad__TEST a partir del MOLDE DE SEGURIDAD validado de
# A05: esqueleto webhook rawBody -> validar_firma_ts_rol (HMAC sobre buffer crudo) ->
# leer_ambiente -> verificar_acceso -> IF acceso -> PG: disponibilidad -> render -> respond.
# 8 nodos (1 sola query PG). El flag alwaysOutputData=true + onError=continueRegularOutput
# en el PG permiten que el render corra siempre y distinga error_interno.
#
# A26 (LECTURA, read-only): sin injectActor, sin isWrite, sin consumo de secuencias.
#   - EXPECTED_ACTION = 'disponibilidad.cabana'. Roles vicky/socio (D-C-39).
#   - payload REJECT-UNKNOWN: id_cabana OBLIGATORIO (safe int > 0), fecha_desde/fecha_hasta
#     YMD reales con hasta > desde, span (hasta - desde) <= 366 dias (cota tecnica Bloque 0).
#   - COMPUERTA SQL (no n8n): una sola query con CTE `valida` (cabana activa) + CROSS JOIN
#     LATERAL que toma id_cabana DESDE `valida`. Si la cabana no existe/esta inactiva,
#     `valida` tiene 0 filas y el Function Scan de obtener_disponibilidad_rango queda
#     "never executed" -> la funcion canonica NO se invoca (demostrado por EXPLAIN ANALYZE).
#     Marcador explicito `cabana_existe` => render mapea no_encontrado (NUNCA ok:true/dias:[]).
#   - reusa la funcion canonica obtener_disponibilidad_rango(p_fecha_desde, p_fecha_hasta,
#     p_id_cabana) en ESE orden con casts ::date/::date/::bigint. NO toca el schema/canonico.
#
# Salida: portal-a26-disponibilidad__TEST.json (TEMPLATE sanitizado, secreto __PEGAR_, cred
# placeholder). 100% TEST. No toca OPS, gateway, frontend, DDL ni 6B_SCHEMA_SQL.md.
import json, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else 'portal-a26-disponibilidad__TEST.json'

# ----------------------------------------------------------------------------
# Nodo 1: validar_firma_ts_rol (HMAC + ts + rol + action binding + payload A26)
# ----------------------------------------------------------------------------
VALIDAR = r'''// portal-a26-disponibilidad -- validar_firma_ts_rol (LECTURA / A26).
// Molde a05/a08: HMAC-SHA256 sobre los bytes EXACTOS del raw body (D-C-29), comparacion
// timing-safe, ventana ts +-300s, raw body binario con fallback rawBody (L-C-05), secreto
// por $vars con assert por prefijo __PEGAR_ (Modo B, L-C-10). A26:
//   - EXPECTED_ACTION = 'disponibilidad.cabana'. Roles vicky/socio (D-C-39, 2da defensa).
//   - payload REJECT-UNKNOWN: id_cabana OBLIGATORIO (safe int > 0; bloqueo total NO se expone),
//     fecha_desde/fecha_hasta YMD reales con hasta > desde, span <= 366 dias.
//   - NO resuelve "no fechas pasadas" (guard UX en el frontend) ni existencia de cabana
//     (eso es el pre-check SQL). Sin actor (lectura).
const crypto = require('crypto');

const SECRET = (typeof $vars !== 'undefined' && $vars && $vars.VITA_HMAC_SECRET)
  ? $vars.VITA_HMAC_SECRET
  : '__PEGAR_SECRETO_O_USAR_VARIABLE__';
if (!SECRET || SECRET.startsWith('__PEGAR_')) {
  throw new Error('VITA_HMAC_SECRET no configurado (assert por prefijo, L-C-10).');
}

const ROLES_OK = ['vicky', 'socio'];
const EXPECTED_ACTION = 'disponibilidad.cabana';
const SPAN_MAX_DIAS = 366;

function rej(motivo, body) {
  body = body || {};
  return [{ json: { ok_firma: false, motivo,
    ambiente_esperado: body.ambiente_esperado ?? null, rol: body.rol ?? null,
    action: body.action ?? null, ts: (typeof body.ts !== 'undefined' ? body.ts : null),
    payload_norm: null } }];
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

// 2-4) HMAC recomputado sobre los mismos bytes, comparacion timing-safe.
const headers = wh.headers || {};
const sigHeader = headers['x-vita-signature'] || headers['X-Vita-Signature'] || '';
const expected = 'sha256=' + crypto.createHmac('sha256', SECRET).update(buf).digest('hex');
let firmaOk = false;
try { const a = Buffer.from(sigHeader); const b = Buffer.from(expected); firmaOk = a.length === b.length && crypto.timingSafeEqual(a, b); } catch (e) { firmaOk = false; }
if (!firmaOk) return rej('firma_invalida', {});

// 5) Parseo (firma ya validada sobre bytes crudos).
let body;
try { body = JSON.parse(buf.toString('utf8')); } catch (e) { return rej('payload_invalido', {}); }

// 6) Ventana de ts (anti-replay liviano, D-C-29): |now - ts| <= 300s.
const ts = Number(body.ts);
if (!Number.isFinite(ts) || Math.abs(Date.now() - ts) > 300000) return rej('ts_fuera_de_ventana', body);

// 7) Allowlist de rol del wrapper (D-C-39). A26 = vicky/socio (sin jenny, D-C-03).
if (!ROLES_OK.includes(body.rol)) return rej('rol_no_permitido', body);
// 8) Action binding (D-C-41).
if (body.action !== EXPECTED_ACTION) return rej('accion_desconocida', body);

// 9) Payload de negocio: REJECT-UNKNOWN + tipos estrictos.
const p = body.payload;
if (!p || typeof p !== 'object' || Array.isArray(p)) return rej('payload_invalido', body);
const PERMITIDAS = ['id_cabana', 'fecha_desde', 'fecha_hasta'];
for (const k of Object.keys(p)) { if (!PERMITIDAS.includes(k)) return rej('payload_invalido', body); }

// id_cabana: entero positivo seguro OBLIGATORIO (bloqueo total NO se expone en el portal).
if (typeof p.id_cabana !== 'number' || !Number.isSafeInteger(p.id_cabana) || p.id_cabana <= 0) return rej('payload_invalido', body);

// fechas: YMD reales (round-trip UTC rechaza 2027-02-30, etc.).
function isYMD(s) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const Y = +s.slice(0, 4), M = +s.slice(5, 7), D = +s.slice(8, 10);
  if (M < 1 || M > 12 || D < 1 || D > 31) return false;
  const dt = new Date(Date.UTC(Y, M - 1, D));
  return dt.getUTCFullYear() === Y && dt.getUTCMonth() === M - 1 && dt.getUTCDate() === D;
}
if (!isYMD(p.fecha_desde) || !isYMD(p.fecha_hasta)) return rej('payload_invalido', body);

// fecha_hasta > fecha_desde (exclusive); comparacion lexicografica == cronologica para YMD.
if (!(p.fecha_desde < p.fecha_hasta)) return rej('payload_invalido', body);

// span (hasta - desde) en dias <= 366 (cota tecnica del Bloque 0; NO limita futuro a 120).
const MS_DIA = 86400000;
const desdeMs = Date.UTC(+p.fecha_desde.slice(0, 4), +p.fecha_desde.slice(5, 7) - 1, +p.fecha_desde.slice(8, 10));
const hastaMs = Date.UTC(+p.fecha_hasta.slice(0, 4), +p.fecha_hasta.slice(5, 7) - 1, +p.fecha_hasta.slice(8, 10));
const span = Math.round((hastaMs - desdeMs) / MS_DIA);
if (span > SPAN_MAX_DIAS) return rej('payload_invalido', body);

const payload_norm = { id_cabana: p.id_cabana, fecha_desde: p.fecha_desde, fecha_hasta: p.fecha_hasta };

return [{ json: { ok_firma: true, motivo: null,
  ambiente_esperado: body.ambiente_esperado ?? null, rol: body.rol ?? null,
  action: body.action ?? null, ts, payload_norm } }];
'''

# ----------------------------------------------------------------------------
# Nodo 4: verificar_acceso (ambiente + envelope de rechazo). Identico a A05 con
# el mensaje de payload_invalido adaptado a A26.
# ----------------------------------------------------------------------------
VERIFICAR = r'''// portal-a26-disponibilidad -- verificar_acceso. Compara ambiente (anti-OPS, D-C-35) y
// arma el envelope de rechazo (D-C-18). En exito marca {ok:true} para habilitar el IF; el
// envelope final de exito lo arma el render.
const v = $('validar_firma_ts_rol').first().json;
const ambItem = $('leer_ambiente').first();
const real = (ambItem && ambItem.json) ? (ambItem.json.valor ?? null) : null;

function envErr(code, message, detail) {
  return [{ json: { ok: false, error: { code, message, detail: detail ?? null } } }];
}

if (!v.ok_firma) {
  const msgs = {
    firma_invalida: 'firma HMAC invalida o ausente',
    ts_fuera_de_ventana: 'timestamp fuera de la ventana permitida (300s)',
    payload_invalido: 'payload invalido (id_cabana entero positivo; fecha_desde/fecha_hasta YMD con hasta>desde; span <= 366)',
    raw_body_ausente: 'no llego el raw body (activa Raw Body en el Webhook)',
    rol_no_permitido: 'rol no habilitado para esta accion',
    accion_desconocida: 'accion no corresponde a este endpoint'
  };
  return envErr(v.motivo, msgs[v.motivo] || 'rechazado', null);
}

if (v.ambiente_esperado !== real) {
  return envErr('ambiente_incorrecto', 'el sobre no corresponde a este entorno', { esperado: v.ambiente_esperado, real });
}

return [{ json: { ok: true } }];
'''

# ----------------------------------------------------------------------------
# Nodo 8: render envelope (no_encontrado por pre-check / ok:true con data.dias)
# ----------------------------------------------------------------------------
RENDER = r'''// ===== portal-a26-disponibilidad -- render JSON (disponibilidad por cabana) =====
// Read-only. La query UNICA con compuerta ya garantiza que la funcion canonica NO se
// evaluo si la cabana no existe/inactiva (CTE valida vacio -> Function Scan never executed).
// La query SIEMPRE devuelve >= 1 fila gracias al marcador explicito `cabana_existe`
// (existe LEFT JOIN disp): cabana invalida/inactiva => 1 fila {cabana_existe:false, fecha:null}
// => no_encontrado (NUNCA ok:true con dias:[]). Cabana activa => 1 fila por NOCHE de
// [fecha_desde, fecha_hasta) (la funcion no incluye la fila de fecha_hasta), todas con
// cabana_existe:true. Falla de lectura (DB/n8n) => error_interno limpio (D-C-18).
function safeAll(nodeName, keyField) {
  try {
    const items = $(nodeName).all();
    const failed = items.some(it => it && it.json && (it.json.error || it.error));
    if (failed) return { ok: false, rows: [] };
    const rows = items.map(it => it.json).filter(j => j && j[keyField] !== undefined && j[keyField] !== null);
    return { ok: true, rows };
  } catch (e) { return { ok: false, rows: [] }; }
}
function ymd(v) { if (v === null || v === undefined) return null; return String(v).slice(0, 10); }
function esTrue(v) { return v === true || v === 't' || v === 'true' || v === 1; }

const r = safeAll('PG: disponibilidad', 'cabana_existe');

if (!r.ok) {
  return [{ json: { ok: false, error: { code: 'error_interno', message: 'no se pudo cargar la disponibilidad', detail: null } } }];
}
// La query siempre trae el marcador; si no vino ninguna fila, es anomalia de lectura.
if (r.rows.length === 0) {
  return [{ json: { ok: false, error: { code: 'error_interno', message: 'sin marcador de cabana', detail: null } } }];
}

// Marcador explicito: cabana inexistente/inactiva => no_encontrado. La funcion NO se evaluo.
if (!esTrue(r.rows[0].cabana_existe)) {
  return [{ json: { ok: false, error: { code: 'no_encontrado', message: 'cabana inexistente o inactiva', detail: null } } }];
}

// Cabana activa: dias = filas con fecha no nula (descarta el padding del LEFT JOIN).
const dias = r.rows
  .filter(x => x.fecha !== null && x.fecha !== undefined)
  .map(x => ({
    fecha: ymd(x.fecha),
    estado: x.estado,
    id_cabana: (x.id_cabana !== undefined && x.id_cabana !== null) ? Number(x.id_cabana) : null,
    hora_checkin_base: x.hora_checkin_base ?? null,
    hora_checkout_base: x.hora_checkout_base ?? null
  }));

return [{ json: { ok: true, data: { dias } } }];
'''

# ----------------------------------------------------------------------------
# Query SQL UNICA con COMPUERTA (Opcion B). El CTE `valida` tiene 0 filas si la
# cabana no existe / esta inactiva. La funcion se invoca por CROSS JOIN LATERAL
# sobre `valida` y toma id_cabana DESDE `valida` (v.id_cabana) -> con 0 filas el
# Function Scan queda "never executed" (demostrado por EXPLAIN ANALYZE): la funcion
# canonica NO se evalua para cabana invalida/inactiva. `existe` es el marcador
# EXPLICITO que el render mapea a no_encontrado.
# Patron de parametro $1::jsonb (probado A25/A13); orden y casts D-Bloque0:
#   obtener_disponibilidad_rango(fecha_desde::date, fecha_hasta::date, id_cabana::bigint).
# NO toca SQL canonico ni crea funciones (el CTE es inline en el wrapper).
# ----------------------------------------------------------------------------
SQL_DISPONIBILIDAD = (
    "WITH valida AS (\n"
    "  SELECT c.id_cabana\n"
    "  FROM cabanas c\n"
    "  WHERE c.id_cabana = (($1::jsonb)->>'id_cabana')::bigint\n"
    "    AND c.activa = TRUE\n"
    "),\n"
    "existe AS (\n"
    "  SELECT EXISTS(SELECT 1 FROM valida) AS cabana_existe\n"
    "),\n"
    "disp AS (\n"
    "  SELECT f.fecha, f.estado, f.id_cabana, f.hora_checkin_base, f.hora_checkout_base\n"
    "  FROM valida v\n"
    "  CROSS JOIN LATERAL obtener_disponibilidad_rango(\n"
    "    (($1::jsonb)->>'fecha_desde')::date,\n"
    "    (($1::jsonb)->>'fecha_hasta')::date,\n"
    "    v.id_cabana\n"
    "  ) AS f\n"
    ")\n"
    "SELECT e.cabana_existe, d.fecha, d.estado, d.id_cabana, d.hora_checkin_base, d.hora_checkout_base\n"
    "FROM existe e\n"
    "LEFT JOIN disp d ON TRUE\n"
    "ORDER BY d.fecha NULLS LAST;"
)

QREPL = "={{ JSON.stringify($('validar_firma_ts_rol').first().json.payload_norm) }}"
CRED = {"postgres": {"id": "REEMPLAZAR_POR_CRED_TEST", "name": "vita_supabase_test (reemplazar al importar)"}}

# ----------------------------------------------------------------------------
# Ensamblado del workflow (topologia y flags identicos a A05)
# ----------------------------------------------------------------------------
nodes = [
    {"parameters": {"httpMethod": "POST", "path": "portal-a26-disponibilidad",
                    "responseMode": "responseNode", "options": {"rawBody": True}},
     "id": "a26e0001-ac11-4f0e-8ab0-d34ce113a064", "name": "Webhook",
     "type": "n8n-nodes-base.webhook", "typeVersion": 2.1, "position": [0, 0]},

    {"parameters": {"jsCode": VALIDAR},
     "id": "a26e0002-26b3-4b31-8cb0-e72aa826e7f6", "name": "validar_firma_ts_rol",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [220, 0]},

    {"parameters": {"operation": "executeQuery",
                    "query": "SELECT valor FROM configuracion_general WHERE clave = 'ambiente'",
                    "options": {}},
     "credentials": CRED, "alwaysOutputData": True, "onError": "continueRegularOutput",
     "id": "a26e0003-982f-4e66-8362-88752ff5227a", "name": "leer_ambiente",
     "type": "n8n-nodes-base.postgres", "typeVersion": 2.6, "position": [440, 0]},

    {"parameters": {"jsCode": VERIFICAR},
     "id": "a26e0004-d1e9-424c-96e0-dc460a735a6e", "name": "verificar_acceso",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [660, 0]},

    {"parameters": {"conditions": {"options": {"caseSensitive": True, "leftValue": "",
                    "typeValidation": "loose", "version": 2},
                    "conditions": [{"id": "a26cond-0ab4-414f-b120-141c8f082aec",
                    "leftValue": "={{ $json.ok }}", "rightValue": True,
                    "operator": {"type": "boolean", "operation": "true", "singleValue": True}}],
                    "combinator": "and"}, "options": {}},
     "id": "a26e0005-46d8-476f-b6a3-4e0da84da6b1", "name": "IF acceso",
     "type": "n8n-nodes-base.if", "typeVersion": 2.2, "position": [880, 0]},

    {"parameters": {"operation": "executeQuery", "query": SQL_DISPONIBILIDAD,
                    "options": {"queryReplacement": QREPL}},
     "credentials": CRED, "alwaysOutputData": True, "executeOnce": True,
     "onError": "continueRegularOutput",
     "id": "a26e0007-ea7d-4aec-8501-12876fbbfaaf", "name": "PG: disponibilidad",
     "type": "n8n-nodes-base.postgres", "typeVersion": 2.6, "position": [1100, -150]},

    {"parameters": {"jsCode": RENDER},
     "id": "a26e0008-a1b7-41a8-981f-af6a1669ac18", "name": "Code: render envelope",
     "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [1540, -150]},

    {"parameters": {"respondWith": "firstIncomingItem", "options": {"responseCode": 200}},
     "id": "a26e0009-3ae3-4092-8665-8a38141773c5", "name": "Respond",
     "type": "n8n-nodes-base.respondToWebhook", "typeVersion": 1.5, "position": [1760, 0]},
]

connections = {
    "Webhook": {"main": [[{"node": "validar_firma_ts_rol", "type": "main", "index": 0}]]},
    "validar_firma_ts_rol": {"main": [[{"node": "leer_ambiente", "type": "main", "index": 0}]]},
    "leer_ambiente": {"main": [[{"node": "verificar_acceso", "type": "main", "index": 0}]]},
    "verificar_acceso": {"main": [[{"node": "IF acceso", "type": "main", "index": 0}]]},
    "IF acceso": {"main": [
        [{"node": "PG: disponibilidad", "type": "main", "index": 0}],
        [{"node": "Respond", "type": "main", "index": 0}],
    ]},
    "PG: disponibilidad": {"main": [[{"node": "Code: render envelope", "type": "main", "index": 0}]]},
    "Code: render envelope": {"main": [[{"node": "Respond", "type": "main", "index": 0}]]},
}

wf = {
    "name": "portal-a26-disponibilidad__TEST",
    "nodes": nodes,
    "pinData": {},
    "connections": connections,
    "active": False,
    "settings": {"executionOrder": "v1", "binaryMode": "separate"},
    "tags": [],
}

with open(OUT, 'w', encoding='utf-8') as f:
    json.dump(wf, f, ensure_ascii=False, indent=2)

print("OK ->", OUT)
print("nodes:", len(wf["nodes"]), "| connections:", len(wf["connections"]))
