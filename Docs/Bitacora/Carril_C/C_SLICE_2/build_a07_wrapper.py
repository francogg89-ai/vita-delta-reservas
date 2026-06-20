#!/usr/bin/env python3
# ============================================================================
# A07.2 v2 — Builder del wrapper `portal-a07-crear-reserva__TEST` (con fixes).
# Carril C / Portal Operativo Interno — Slice 2 / A07.
#
# Cambios v2 (bloqueantes de Franco):
#   B1. PG-2 le pasa id_pre_reserva a registrar_pago. router1_crear arma
#       payload2 = {...payload2_base, id_pre_reserva: id_pre} (clave EXACTA del
#       payload de registrar_pago, verificada en 6B_SCHEMA_SQL.md L4580). PG-2
#       llama registrar_pago((SELECT payload2 FROM args)) sin merge SQL.
#   B2. Contrato de exito uniforme {ok:true, data:{...}}. Todos los routers de
#       exito (router0/3/4) devuelven data:{id_reserva,id_pre_reserva,id_huesped,
#       idempotent_match}. Errores siguen {ok:false, error:{...}}.
#   B3. Validacion estricta: fecha YYYY-MM-DD real (rechaza 2027-02-30 via
#       round-trip UTC), hora 00:00:00-23:59:59, telefono con >=6 digitos reales
#       si no hay email, email con regex. null/undefined = ausente.
#   B4. (artefacto aparte) dry-parse SQL no destructivo de las 5 queries.
#
# Mantiene v1: EXPECTED_ACTION reserva.crear_manual, ajuste 2 (pago estricto),
# ajuste 3 (PG-4 recheck), huella del molde, active:false, HMAC placeholder.
# NO ejecuta nada. Solo emite el __TEMPLATE_v2.json.
# ============================================================================
import json, uuid, hashlib, sys, os, re

MOLDE_PATH = "/tmp/a05.json"
OUT_PATH   = "/home/claude/a07_2/portal-a07-crear-reserva__TEST__TEMPLATE_v2.json"

with open(MOLDE_PATH, "rb") as f:
    MOLDE_SHA256 = hashlib.sha256(f.read()).hexdigest()
MOLDE_NAME = "portal-a05-detalle__TEMPLATE.json"
MOLDE_REPO = "francogg89-ai/vita-delta-reservas @ main : Workflows/n8n/Supabase/"

PLACEHOLDER_HMAC = "__PEGAR_SECRETO_O_USAR_VARIABLE__"
CRED = {"postgres": {"id": "REEMPLAZAR_POR_CRED_TEST", "name": "vita_supabase_test (reemplazar al importar)"}}

def nid(): return str(uuid.uuid4())

# ===========================================================================
JS_VALIDAR = r'''// portal-a07-crear-reserva__TEST — validar_firma_ts_rol (ESCRITURA / A07) v2.
// Clonado del molde a05 (HMAC sobre buffer crudo, timing-safe, ventana ts, raw body
// binario con fallback, assert por prefijo __PEGAR_). A07:
//   - EXPECTED_ACTION = 'reserva.crear_manual'.
//   - actor (sobre firmado) contra enum de personas.
//   - payload de negocio REJECT-UNKNOWN + validacion ESTRICTA (fecha real, hora en rango,
//     contacto con digitos reales / email valido). null/undefined = ausente.
const crypto = require('crypto');

const SECRET = (typeof $vars !== 'undefined' && $vars && $vars.VITA_HMAC_SECRET)
  ? $vars.VITA_HMAC_SECRET
  : '__PEGAR_SECRETO_O_USAR_VARIABLE__';
if (!SECRET || SECRET.startsWith('__PEGAR_')) {
  throw new Error('VITA_HMAC_SECRET no configurado (assert por prefijo, L-C-10).');
}

const ENUM_PAGO  = ['transferencia_bancaria','transferencia_mp','mp_link','cripto','efectivo'];
const ENUM_ACTOR = ['vicky','franco','rodrigo','remo'];
const ROLES_OK   = ['vicky','socio'];
const EXPECTED_ACTION = 'reserva.crear_manual';
const MAXLEN = 1000;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

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

const PERMITIDAS = ['id_cabana','fecha_in','fecha_out','personas','monto_total','monto_sena',
  'canal_pago_esperado','medio_pago','huesped','mascotas','detalle_mascotas','ninos','notas',
  'notas_reserva','hora_checkin_solicitada','hora_checkout_solicitada'];
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
// Hora HH:MM[:SS] en rango 00:00:00-23:59:59 (99:99 rechazado).
const isHMS = (s) => {
  if (!isStr(s) || !/^\d{2}:\d{2}(:\d{2})?$/.test(s)) return false;
  const h = +s.slice(0,2), m = +s.slice(3,5), sec = s.length > 5 ? +s.slice(6,8) : 0;
  return h >= 0 && h <= 23 && m >= 0 && m <= 59 && sec >= 0 && sec <= 59;
};

if (typeof p.id_cabana !== 'number' || !Number.isSafeInteger(p.id_cabana) || p.id_cabana <= 0) return rej('payload_invalido', body);
if (!isYMD(p.fecha_in) || !isYMD(p.fecha_out)) return rej('payload_invalido', body);
if (!(p.fecha_out > p.fecha_in)) return rej('payload_invalido', body);
if (typeof p.personas !== 'number' || !Number.isSafeInteger(p.personas) || p.personas < 1) return rej('payload_invalido', body);
if (typeof p.monto_total !== 'number' || !Number.isFinite(p.monto_total) || p.monto_total <= 0) return rej('payload_invalido', body);
if (typeof p.monto_sena !== 'number' || !Number.isFinite(p.monto_sena) || p.monto_sena < 0 || p.monto_sena > p.monto_total) return rej('payload_invalido', body);
if (!ENUM_PAGO.includes(p.canal_pago_esperado)) return rej('payload_invalido', body);
if (!ENUM_PAGO.includes(p.medio_pago)) return rej('payload_invalido', body);

// huesped REJECT-UNKNOWN + contacto estricto.
const h = p.huesped;
if (!h || typeof h !== 'object' || Array.isArray(h)) return rej('payload_invalido', body);
const H_PERM = ['nombre','telefono','email'];
for (const k of Object.keys(h)) { if (!H_PERM.includes(k)) return rej('payload_invalido', body); }
if (!isStr(h.nombre) || h.nombre.trim() === '' || !okLen(h.nombre)) return rej('payload_invalido', body);

let telVal = null, emaVal = null;
if (h.telefono !== undefined && h.telefono !== null) {
  if (!isStr(h.telefono) || !okLen(h.telefono)) return rej('payload_invalido', body);
  const t = h.telefono.trim();
  if (t !== '') {
    if (t.replace(/\D/g, '').length < 6) return rej('payload_invalido', body); // 'abc' -> 0 digitos -> rechazado
    telVal = t;
  }
}
if (h.email !== undefined && h.email !== null) {
  if (!isStr(h.email) || !okLen(h.email)) return rej('payload_invalido', body);
  const e = h.email.trim();
  if (e !== '') {
    if (!EMAIL_RE.test(e)) return rej('payload_invalido', body);
    emaVal = e;
  }
}
if (telVal === null && emaVal === null) return rej('payload_invalido', body);

// opcionales cosmeticos (null/undefined = ausente; no entran al idem).
for (const k of ['detalle_mascotas','ninos','notas','notas_reserva']) {
  if (p[k] != null && (!isStr(p[k]) || !okLen(p[k]))) return rej('payload_invalido', body);
}
if (p.mascotas != null && typeof p.mascotas !== 'boolean') return rej('payload_invalido', body);
if (p.hora_checkin_solicitada != null && !isHMS(p.hora_checkin_solicitada)) return rej('payload_invalido', body);
if (p.hora_checkout_solicitada != null && !isHMS(p.hora_checkout_solicitada)) return rej('payload_invalido', body);

const payloadWL = {
  id_cabana: p.id_cabana, fecha_in: p.fecha_in, fecha_out: p.fecha_out, personas: p.personas,
  monto_total: p.monto_total, monto_sena: p.monto_sena,
  canal_pago_esperado: p.canal_pago_esperado, medio_pago: p.medio_pago,
  mascotas: (p.mascotas === true),
  detalle_mascotas: (p.detalle_mascotas != null ? p.detalle_mascotas : null),
  ninos: (p.ninos != null ? p.ninos : null),
  notas: (p.notas != null ? p.notas : null),
  notas_reserva: (p.notas_reserva != null ? p.notas_reserva : null),
  hora_checkin_solicitada: (p.hora_checkin_solicitada != null ? p.hora_checkin_solicitada : null),
  hora_checkout_solicitada: (p.hora_checkout_solicitada != null ? p.hora_checkout_solicitada : null),
  huesped: { nombre: h.nombre.trim(), telefono: telVal, email: emaVal }
};

return [{ json: { ok_firma:true, motivo:null, ambiente_esperado: body.ambiente_esperado ?? null,
  rol: body.rol, action: body.action, ts, actor: body.actor, payload: payloadWL } }];
'''

JS_VERIFICAR = r'''// portal-a07-crear-reserva__TEST — verificar_acceso (ambiente + envelope de rechazo).
const v = $('validar_firma_ts_rol').first().json;
const ambItem = $('leer_ambiente').first();
const real = (ambItem && ambItem.json) ? (ambItem.json.valor ?? null) : null;
function envErr(code, message, detail) { return [{ json: { ok:false, error: { code, message, detail: detail ?? null } } }]; }
if (!v.ok_firma) {
  const msgs = {
    firma_invalida: 'firma HMAC invalida o ausente',
    ts_fuera_de_ventana: 'timestamp fuera de la ventana permitida (300s)',
    payload_invalido: 'payload invalido (campos de negocio, huesped o actor)',
    raw_body_ausente: 'no llego el raw body (activa Raw Body en el Webhook)',
    rol_no_permitido: 'rol no habilitado para esta accion',
    accion_desconocida: 'accion no corresponde a este endpoint'
  };
  return envErr(v.motivo, msgs[v.motivo] || 'rechazado', null);
}
if (v.ambiente_esperado !== real) {
  return envErr('ambiente_incorrecto', 'el sobre no corresponde a este entorno', { esperado: v.ambiente_esperado, real });
}
return [{ json: { ok:true } }];
'''

JS_DERIVAR = r'''// portal-a07-crear-reserva__TEST — Code: derivar.
// Deriva idem/sev (PII-free) y arma payloads SQL. SHA-256 require('crypto') (A07.1).
const crypto = require('crypto');
const sha256hex = (s) => crypto.createHash('sha256').update(String(s), 'utf8').digest('hex');

const V = $('validar_firma_ts_rol').first().json;
const p = V.payload;
const actor = V.actor;

const tel = (p.huesped.telefono && String(p.huesped.telefono).trim() !== '') ? String(p.huesped.telefono).replace(/\D/g,'') : null;
const contacto_norm = tel ? tel : ('email_' + String(p.huesped.email).trim().toLowerCase());
const contact_hash = sha256hex(contacto_norm);

const ORDEN = ['id_cabana','fecha_in','fecha_out','personas','monto_total','monto_sena',
  'canal_pago_esperado','medio_pago','hora_checkin_solicitada','hora_checkout_solicitada','mascotas','ninos'];
const negocio = {
  id_cabana: p.id_cabana, fecha_in: p.fecha_in, fecha_out: p.fecha_out, personas: p.personas,
  monto_total: Number(p.monto_total).toFixed(2), monto_sena: Number(p.monto_sena).toFixed(2),
  canal_pago_esperado: p.canal_pago_esperado, medio_pago: p.medio_pago,
  hora_checkin_solicitada: p.hora_checkin_solicitada, hora_checkout_solicitada: p.hora_checkout_solicitada,
  mascotas: p.mascotas, ninos: p.ninos
};
const canon = JSON.stringify(ORDEN.map((k) => [k, negocio[k]]));
const payload_hash12 = sha256hex(canon).slice(0, 12);

const idem = `portal_test_a07_${p.id_cabana}_${p.fecha_in}_${p.fecha_out}_${contact_hash}_${payload_hash12}`;
const sev = idem;

const huesped = { nombre: p.huesped.nombre };
if (p.huesped.telefono) huesped.telefono = p.huesped.telefono;
if (p.huesped.email) huesped.email = p.huesped.email;
const payload1Obj = {
  id_cabana: p.id_cabana, fecha_in: p.fecha_in, fecha_out: p.fecha_out, personas: p.personas,
  canal_origen: 'manual', canal_pago_esperado: p.canal_pago_esperado,
  monto_total: p.monto_total, monto_sena: p.monto_sena,
  source_event: sev, idempotency_key: idem, huesped: huesped,
  mascotas: p.mascotas
};
if (p.detalle_mascotas !== null) payload1Obj.detalle_mascotas = p.detalle_mascotas;
if (p.ninos !== null) payload1Obj.ninos = p.ninos;
if (p.notas !== null) payload1Obj.notas = p.notas;
if (p.notas_reserva !== null) payload1Obj.notas_reserva = p.notas_reserva;
if (p.hora_checkin_solicitada !== null) payload1Obj.hora_checkin_solicitada = p.hora_checkin_solicitada;
if (p.hora_checkout_solicitada !== null) payload1Obj.hora_checkout_solicitada = p.hora_checkout_solicitada;

// payload2_base (sin id_pre_reserva; router1 lo agrega). Seña confirmada (D-C-56).
const payload2_base = {
  tipo: 'sena', medio_pago: p.medio_pago,
  monto_esperado: p.monto_sena, monto_recibido: p.monto_sena,
  estado_inicial: 'confirmado', validado_por: actor, source_event: sev
};
// payload3_base (sin id_pre_reserva; router2 lo agrega).
const payload3_base = {
  source_event: sev, created_by: actor, encargado_semana: null, permitir_pago_en_revision: false
};

return [{ json: {
  idem, sev, contact_hash, payload_hash12, actor,
  payload1: JSON.stringify(payload1Obj),
  payload2_base, payload3_base
} }];
'''

JS_ROUTER0 = r'''// router0_precheck — lee PG-0. 0 -> seguir; 1 -> idempotent_match; >1 -> incierto.
const r = $json; const D = $('Code: derivar').first().json;
const incierto = (paso, ids) => [{ json: { continuar:false, envelope: { ok:false, error: {
  code:'estado_incierto', message:'estado inconsistente; verificar antes de reintentar',
  detail: { paso, ids_creados: ids||{}, source_event: D.sev, idempotency_key: D.idem } } } } }];
if (r.n > 1) return incierto('prereserva', {});
if (r.n === 1) return [{ json: { continuar:false, envelope: { ok:true, data: {
  id_reserva: r.id_reserva, id_pre_reserva: r.id_pre_reserva, id_huesped: r.id_huesped, idempotent_match: true } } } }];
return [{ json: { continuar:true } }];
'''

JS_ROUTER1 = r'''// router1_crear — lee PG-1. Mapea error o arma pg2_args (con payload2 que INCLUYE id_pre_reserva).
const res = $json.resultado; const D = $('Code: derivar').first().json;
function mapErr(e) {
  const conflicto = ['no_disponible'];
  const payloadInv = ['cabana_no_existe','cabana_inactiva','excede_capacidad','fechas_invalidas',
    'precio_requerido','huesped_nombre_requerido','huesped_contacto_requerido','hora_fuera_de_rango','payload_invalido'];
  if (conflicto.includes(e)) return { ok:false, error: { code:'conflicto', message:'sin disponibilidad en el rango', detail:null } };
  if (payloadInv.includes(e)) return { ok:false, error: { code:'payload_invalido', message:'datos de reserva rechazados: '+e, detail:null } };
  if (e === 'unique_violation_inesperado') return { ok:false, error: { code:'estado_incierto', message:'estado incierto al crear; verificar antes de reintentar', detail:{ paso:'prereserva', ids_creados:{}, source_event:D.sev, idempotency_key:D.idem } } };
  return { ok:false, error: { code:'error_interno', message:'no se pudo crear la prereserva', detail:null } };
}
if (!res || res.ok !== true) return [{ json: { continuar:false, envelope: mapErr(res ? res.error : null) } }];
const id_pre = res.id_pre_reserva;
// payload2 = base + id_pre_reserva (clave EXACTA del payload de registrar_pago, 6B L4580).
const payload2 = Object.assign({}, D.payload2_base, { id_pre_reserva: id_pre });
const pg2_args = JSON.stringify({ idem: D.idem, id_pre, sev: D.sev, payload2 });
return [{ json: { continuar:true, id_pre, pg2_args } }];
'''

JS_ROUTER2 = r'''// router2_pago — lee PG-2 (lock+precheck seña+registro condicional). Ajuste 2:
// seguir SOLO si registrado ok===true && estado==='confirmado' && sin warning, o si ya habia
// exactamente 1 seña confirmada. Caso contrario -> estado_incierto.
const r = $json; const D = $('Code: derivar').first().json;
const id_pre = $('router1_crear').first().json.id_pre;
const incierto = () => [{ json: { continuar:false, envelope: { ok:false, error: {
  code:'estado_incierto', message:'estado de pago incierto; verificar antes de reintentar',
  detail: { paso:'pago', ids_creados: { id_pre_reserva: id_pre }, source_event: D.sev, idempotency_key: D.idem } } } } }];
let proceed = false;
if (r.n === 0) {
  const rr = r.resultado_registro;
  proceed = !!(rr && rr.ok === true && rr.estado === 'confirmado' && !rr.warning);
} else if (r.n === 1 && r.n_conf === 1) {
  proceed = true;
} else {
  proceed = false; // n=1 & n_conf=0 ; n>1
}
if (!proceed) return incierto();
const payload3 = JSON.stringify(Object.assign({ id_pre_reserva: id_pre }, D.payload3_base));
return [{ json: { continuar:true, payload3 } }];
'''

JS_ROUTER3 = r'''// router3_confirmar — lee PG-3. Exito {ok:true,data}; conflicto; ajuste 3:
// estado_invalido + estado_actual='convertida' -> recheck (PG-4); resto -> estado_incierto.
const res = $json.resultado; const D = $('Code: derivar').first().json;
const id_pre = $('router1_crear').first().json.id_pre;
if (res && res.ok === true) return [{ json: { recheck:false, envelope: { ok:true, data: {
  id_reserva: res.id_reserva, id_pre_reserva: res.id_pre_reserva, id_huesped: res.id_huesped, idempotent_match: false } } } }];
const e = res ? res.error : null;
if (e === 'estado_invalido' && res && res.estado_actual === 'convertida') return [{ json: { recheck:true } }];
if (e === 'conflicto_al_confirmar' || e === 'no_disponible') return [{ json: { recheck:false, envelope: {
  ok:false, error: { code:'conflicto', message:'conflicto de disponibilidad al confirmar', detail:null } } } }];
return [{ json: { recheck:false, envelope: { ok:false, error: {
  code:'estado_incierto', message:'estado incierto al confirmar; verificar antes de reintentar',
  detail: { paso:'confirmacion', ids_creados: { id_pre_reserva: id_pre }, source_event: D.sev, idempotency_key: D.idem } } } } }];
'''

JS_ROUTER4 = r'''// router4_recheck — lee PG-4. Ajuste 3: 1 reserva -> ok idempotent_match; 0 o >1 -> incierto.
const r = $json; const D = $('Code: derivar').first().json;
if (r.n === 1) return [{ json: { envelope: { ok:true, data: {
  id_reserva: r.id_reserva, id_pre_reserva: r.id_pre_reserva, id_huesped: r.id_huesped, idempotent_match: true } } } }];
return [{ json: { envelope: { ok:false, error: {
  code:'estado_incierto', message:'recheck post-confirmacion inconsistente; verificar manualmente',
  detail: { paso:'confirmacion', ids_creados: {}, source_event: D.sev, idempotency_key: D.idem } } } } }];
'''

JS_RENDER = r'''// portal-a07-crear-reserva__TEST — Code: render. Punto unico de salida.
// Extrae el envelope de los routers; o pasa el rechazo de verificar_acceso ($json {ok:false,error}).
// El gateway re-enmascarara/re-sanitizara codigos de infra/estado_incierto (D-C-55).
const e = ($json && $json.envelope) ? $json.envelope : $json;
return [{ json: e }];
'''

# ===========================================================================
SQL_PG0 = (
"WITH hit AS (\n"
"  SELECT r.id_reserva, r.id_pre_reserva, r.id_huesped\n"
"  FROM reservas r\n"
"  JOIN pre_reservas pr ON pr.id_pre_reserva = r.id_pre_reserva\n"
"  WHERE pr.idempotency_key = $1\n"
")\n"
"SELECT (SELECT count(*) FROM hit)::int                               AS n,\n"
"       (SELECT id_reserva     FROM hit ORDER BY id_reserva LIMIT 1)  AS id_reserva,\n"
"       (SELECT id_pre_reserva FROM hit ORDER BY id_reserva LIMIT 1)  AS id_pre_reserva,\n"
"       (SELECT id_huesped     FROM hit ORDER BY id_reserva LIMIT 1)  AS id_huesped;"
)
SQL_PG1 = "SELECT crear_prereserva($1::jsonb) AS resultado;"
SQL_PG2 = (
"WITH args AS (\n"
"  SELECT ($1::jsonb)->>'idem'             AS idem,\n"
"         (($1::jsonb)->>'id_pre')::bigint AS id_pre,\n"
"         ($1::jsonb)->>'sev'              AS sev,\n"
"         ($1::jsonb)->'payload2'          AS payload2\n"
"),\n"
"lk AS MATERIALIZED (\n"
"  SELECT pg_advisory_xact_lock(hashtextextended((SELECT idem FROM args), 0::bigint))\n"
"),\n"
"ex AS (\n"
"  SELECT count(p.id_pago)::int                                              AS n,\n"
"         count(p.id_pago) FILTER (WHERE p.estado='confirmado')::int         AS n_conf,\n"
"         (array_agg(p.id_pago ORDER BY p.id_pago)\n"
"            FILTER (WHERE p.estado='confirmado'))[1]                        AS id_pago_conf\n"
"  FROM lk\n"
"  CROSS JOIN args a\n"
"  LEFT JOIN pagos p\n"
"    ON p.id_prereserva = a.id_pre AND p.tipo='sena' AND p.source_event = a.sev\n"
")\n"
"SELECT ex.n, ex.n_conf, ex.id_pago_conf,\n"
"       CASE WHEN ex.n = 0 THEN registrar_pago((SELECT payload2 FROM args)) ELSE NULL END AS resultado_registro\n"
"FROM ex;"
)
SQL_PG3 = "SELECT confirmar_reserva($1::jsonb) AS resultado;"
SQL_PG4 = SQL_PG0

# ===========================================================================
def code_node(name, js, pos):
    return {"parameters": {"jsCode": js}, "id": nid(), "name": name,
            "type": "n8n-nodes-base.code", "typeVersion": 2, "position": pos}
def pg_node(name, query, qrepl, pos):
    return {"parameters": {"operation": "executeQuery", "query": query,
            "options": {"queryReplacement": qrepl}}, "id": nid(), "name": name,
            "type": "n8n-nodes-base.postgres", "typeVersion": 2.6, "position": pos,
            "credentials": CRED, "onError": "continueRegularOutput", "alwaysOutputData": True}
def if_node(name, expr_field, pos):
    return {"parameters": {"conditions": {"options": {"caseSensitive": True, "leftValue": "",
              "typeValidation": "loose", "version": 2},
            "conditions": [{"id": nid(), "leftValue": expr_field, "rightValue": True,
              "operator": {"type": "boolean", "operation": "true", "singleValue": True}}],
            "combinator": "and"}, "options": {}}, "id": nid(), "name": name,
            "type": "n8n-nodes-base.if", "typeVersion": 2.2, "position": pos}

X = lambda c: c*240
def Y(r): return r*170

webhook = {"parameters": {"httpMethod": "POST", "path": "portal-a07-crear-reserva__TEST",
           "responseMode": "responseNode", "options": {"rawBody": True}},
           "id": nid(), "name": "Webhook", "type": "n8n-nodes-base.webhook",
           "typeVersion": 2.1, "position": [X(0), Y(0)],
           "notes": ("A07.2 v2 wrapper (ESCRITURA). Molde base: %s (sha256=%s) en %s. "
                     "active:false, HMAC placeholder (Modo B). No gateway." % (MOLDE_NAME, MOLDE_SHA256, MOLDE_REPO))}
leer_ambiente = {"parameters": {"operation": "executeQuery",
                 "query": "SELECT valor FROM configuracion_general WHERE clave = 'ambiente'",
                 "options": {}}, "id": nid(), "name": "leer_ambiente",
                 "type": "n8n-nodes-base.postgres", "typeVersion": 2.6, "position": [X(2), Y(0)], "credentials": CRED}
validar   = code_node("validar_firma_ts_rol", JS_VALIDAR, [X(1), Y(0)])
verificar = code_node("verificar_acceso", JS_VERIFICAR, [X(3), Y(0)])
if_acceso = if_node("IF acceso", "={{ $json.ok }}", [X(4), Y(0)])
derivar   = code_node("Code: derivar", JS_DERIVAR, [X(5), Y(0)])
pg0 = pg_node("PG-0 precheck_reserva", SQL_PG0, "={{ $('Code: derivar').first().json.idem }}", [X(6), Y(0)])
r0  = code_node("router0_precheck", JS_ROUTER0, [X(7), Y(0)])
if0 = if_node("IF0 seguir", "={{ $json.continuar }}", [X(8), Y(0)])
pg1 = pg_node("PG-1 crear_prereserva", SQL_PG1, "={{ $('Code: derivar').first().json.payload1 }}", [X(9), Y(0)])
r1  = code_node("router1_crear", JS_ROUTER1, [X(10), Y(0)])
if1 = if_node("IF1 seguir", "={{ $json.continuar }}", [X(11), Y(0)])
pg2 = pg_node("PG-2 lock_precheck_pago", SQL_PG2, "={{ $('router1_crear').first().json.pg2_args }}", [X(12), Y(0)])
r2  = code_node("router2_pago", JS_ROUTER2, [X(13), Y(0)])
if2 = if_node("IF2 seguir", "={{ $json.continuar }}", [X(14), Y(0)])
pg3 = pg_node("PG-3 confirmar_reserva", SQL_PG3, "={{ $('router2_pago').first().json.payload3 }}", [X(15), Y(0)])
r3  = code_node("router3_confirmar", JS_ROUTER3, [X(16), Y(0)])
if3 = if_node("IF3 recheck", "={{ $json.recheck }}", [X(17), Y(0)])
pg4 = pg_node("PG-4 recheck_reserva_post_confirmar", SQL_PG4, "={{ $('Code: derivar').first().json.idem }}", [X(18), Y(1)])
r4  = code_node("router4_recheck", JS_ROUTER4, [X(19), Y(1)])
render  = code_node("Code: render", JS_RENDER, [X(18), Y(-1)])
respond = {"parameters": {"respondWith": "firstIncomingItem", "options": {"responseCode": 200}},
           "id": nid(), "name": "Respond", "type": "n8n-nodes-base.respondToWebhook",
           "typeVersion": 1.5, "position": [X(20), Y(0)]}

nodes = [webhook, validar, leer_ambiente, verificar, if_acceso, derivar,
         pg0, r0, if0, pg1, r1, if1, pg2, r2, if2, pg3, r3, if3, pg4, r4, render, respond]

def main(*t): return {"main": [[{"node": x, "type": "main", "index": 0} for x in t]]}
def main2(tt, ff): return {"main": [[{"node": x, "type": "main", "index": 0} for x in tt],
                                     [{"node": x, "type": "main", "index": 0} for x in ff]]}
connections = {
    "Webhook": main("validar_firma_ts_rol"),
    "validar_firma_ts_rol": main("leer_ambiente"),
    "leer_ambiente": main("verificar_acceso"),
    "verificar_acceso": main("IF acceso"),
    "IF acceso": main2(["Code: derivar"], ["Code: render"]),
    "Code: derivar": main("PG-0 precheck_reserva"),
    "PG-0 precheck_reserva": main("router0_precheck"),
    "router0_precheck": main("IF0 seguir"),
    "IF0 seguir": main2(["PG-1 crear_prereserva"], ["Code: render"]),
    "PG-1 crear_prereserva": main("router1_crear"),
    "router1_crear": main("IF1 seguir"),
    "IF1 seguir": main2(["PG-2 lock_precheck_pago"], ["Code: render"]),
    "PG-2 lock_precheck_pago": main("router2_pago"),
    "router2_pago": main("IF2 seguir"),
    "IF2 seguir": main2(["PG-3 confirmar_reserva"], ["Code: render"]),
    "PG-3 confirmar_reserva": main("router3_confirmar"),
    "router3_confirmar": main("IF3 recheck"),
    "IF3 recheck": main2(["PG-4 recheck_reserva_post_confirmar"], ["Code: render"]),
    "PG-4 recheck_reserva_post_confirmar": main("router4_recheck"),
    "router4_recheck": main("Code: render"),
    "Code: render": main("Respond"),
}
workflow = {"name": "portal-a07-crear-reserva__TEST", "nodes": nodes, "pinData": {},
            "connections": connections, "active": False,
            "settings": {"executionOrder": "v1", "binaryMode": "separate"}, "tags": []}

# ===========================================================================
# ASSERTS
# ===========================================================================
errors = []
blob = json.dumps(workflow)
jc = {n["name"]: n["parameters"]["jsCode"] for n in nodes if n["type"] == "n8n-nodes-base.code"}

if workflow["active"] is not False: errors.append("active no es False")
if PLACEHOLDER_HMAC not in blob: errors.append("falta placeholder HMAC")
if "startsWith('__PEGAR_')" not in blob: errors.append("falta assert por prefijo")
if "reserva.crear_manual" not in blob: errors.append("falta EXPECTED_ACTION")
if re.search(r"EXPECTED_ACTION\s*=\s*'reserva\.crear'", blob): errors.append("EXPECTED_ACTION viejo presente")
if webhook["parameters"]["path"] != "portal-a07-crear-reserva__TEST": errors.append("path incorrecto")
if MOLDE_SHA256 not in blob: errors.append("falta huella molde")
pg_nodes = [n for n in nodes if n["type"] == "n8n-nodes-base.postgres"]
if len(pg_nodes) != 6: errors.append("se esperaban 6 PG, hay %d" % len(pg_nodes))
for n in pg_nodes:
    if n.get("credentials", {}).get("postgres", {}).get("id") != "REEMPLAZAR_POR_CRED_TEST":
        errors.append("PG sin cred placeholder: %s" % n["name"])
if webhook["parameters"]["options"].get("rawBody") is not True: errors.append("rawBody no ON")
if "hashtextextended" not in blob: errors.append("PG-2 sin hashtextextended")
if re.search(r"\bhashtext\(", blob): errors.append("hashtext( en vez de hashtextextended")
# B1: router1 arma payload2 con id_pre_reserva; PG-2 lo pasa a registrar_pago
if "id_pre_reserva: id_pre" not in jc["router1_crear"]: errors.append("B1: router1 no inyecta id_pre_reserva en payload2")
if "registrar_pago((SELECT payload2 FROM args))" not in SQL_PG2: errors.append("B1: PG-2 no llama registrar_pago(payload2)")
# B2: exitos con data
for rn in ["router0_precheck", "router3_confirmar", "router4_recheck"]:
    if "ok:true,data:{" not in jc[rn].replace(" ", ""):
        errors.append("B2: %s no usa contrato {ok:true,data}" % rn)
# B3: validacion estricta
if "getUTCDate()" not in jc["validar_firma_ts_rol"]: errors.append("B3: falta validacion de fecha real (getUTCDate)")
if "h <= 23" not in jc["validar_firma_ts_rol"]: errors.append("B3: falta rango de hora")
if "replace(/\\D/g, '').length < 6" not in jc["validar_firma_ts_rol"]: errors.append("B3: falta telefono >=6 digitos")
if "EMAIL_RE.test" not in jc["validar_firma_ts_rol"]: errors.append("B3: falta validacion de email")
# ajuste 2 y 3
if "rr.estado === 'confirmado'" not in blob or "!rr.warning" not in blob: errors.append("falta gate de pago (ajuste 2)")
if "estado_actual === 'convertida'" not in blob: errors.append("falta rama convertida (ajuste 3)")
if not any(n["name"].startswith("PG-4") for n in nodes): errors.append("falta PG-4 (ajuste 3)")
# referencias y grafo
node_names = {n["name"] for n in nodes}
for n in pg_nodes:
    for ref in re.findall(r"\$\('([^']+)'\)", n["parameters"]["options"].get("queryReplacement", "")):
        if ref not in node_names: errors.append("queryReplacement ref inexistente: %s" % ref)
conn_targets = set()
for src, c in connections.items():
    if src not in node_names: errors.append("conn source inexistente: %s" % src)
    for out in c["main"]:
        for t in out:
            conn_targets.add(t["node"])
            if t["node"] not in node_names: errors.append("conn target inexistente: %s" % t["node"])
for n in nodes:
    if n["name"] != "Webhook" and n["name"] not in conn_targets: errors.append("nodo huerfano: %s" % n["name"])
if len([n["id"] for n in nodes]) != len({n["id"] for n in nodes}): errors.append("IDs duplicados")
try: json.loads(blob)
except Exception as e: errors.append("no serializa: %s" % e)

print("=" * 60)
print("ASSERTS A07.2 v2 wrapper")
print("=" * 60)
print("nodos: %d | postgres: %d | code: %d | if: %d" % (len(nodes), len(pg_nodes),
    len([n for n in nodes if n['type']=='n8n-nodes-base.code']),
    len([n for n in nodes if n['type']=='n8n-nodes-base.if'])))
print("molde sha256: %s" % MOLDE_SHA256)
print("fixes: B1 id_pre_reserva | B2 {ok,data} | B3 validacion estricta")
if errors:
    print("\nFALLARON %d ASSERTS:" % len(errors))
    for e in errors: print("  [X] %s" % e)
    sys.exit(1)
print("\nTODOS LOS ASSERTS OK")
os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
with open(OUT_PATH, "w", encoding="utf-8") as f:
    json.dump(workflow, f, ensure_ascii=False, indent=2)
print("Escrito: %s (%d bytes)" % (OUT_PATH, os.path.getsize(OUT_PATH)))
