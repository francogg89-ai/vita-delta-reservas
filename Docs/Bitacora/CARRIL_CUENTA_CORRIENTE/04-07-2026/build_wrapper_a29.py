#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Construye portal-a29-retiro__TEMPLATE.json mutando el molde A11 (misma topologia de
# nodos/settings). Cambia: name, webhook path, los 4 code nodes, el nodo PG (query+nombre)
# y el router (nombre), y reconstruye connections con los nombres finales.
import json, io

SRC = "/home/claude/vdr/Workflows/n8n/Supabase/portal-a11-cargar-gasto-interno__TEMPLATE.json"
DST = "portal-a29-retiro__TEMPLATE.json"
PATH = "portal-a29-retiro__TEST"

with io.open(SRC, "r", encoding="utf-8") as f:
    wf = json.load(f)

# ---- Codigo: validar_firma_ts_rol (A29) ----
CODE_VALIDAR = r"""// portal-a29-retiro__TEST - validar_firma_ts_rol (ESCRITURA / A29) v1.
// Molde a11 (HMAC sobre buffer crudo, timing-safe, ventana ts, raw body binario con fallback,
// assert por prefijo __PEGAR_). A29 (D-C-56 / SB1):
//   - EXPECTED_ACTION = 'cuenta_corriente.retirar'.
//   - ROLES_OK = ['socio'] (vicky/jenny rebotan; el gateway ya los filtra, esto es 2da defensa).
//   - nonce DERIVADO de la firma ESPERADA recomputada y normalizada (D-C-56): nonce = expectedHex.toLowerCase().
//   - id_socio + user_id vienen del SOBRE (inyectados por el gateway, injectSocioIdentity), NO del payload:
//     id_socio entero positivo; user_id uuid. Se validan aca (2da defensa) y se pasan a Code: derivar.
//   - idempotency_key estricta ^[A-Za-z0-9_-]{8,64}$.
//   - payload de negocio REJECT-UNKNOWN {monto, medio_pago, comentario}: monto STRING ^[0-9]{1,12}(\.[0-9]{1,2})?$
//     y > 0 (D-A29-1); medio_pago {efectivo, transferencia_bancaria}; comentario opcional trim -> null (ajuste 3).
//     La coherencia de saldo (retiro <= saldo vivo) la valida portal_registrar_retiro (SB1).
const crypto = require('crypto');

const SECRET = (typeof $vars !== 'undefined' && $vars && $vars.VITA_HMAC_SECRET)
  ? $vars.VITA_HMAC_SECRET
  : '__PEGAR_SECRETO_O_USAR_VARIABLE__';
if (!SECRET || SECRET.startsWith('__PEGAR_')) {
  throw new Error('VITA_HMAC_SECRET no configurado (assert por prefijo, L-C-10).');
}

const ROLES_OK        = ['socio'];
const ENUM_ACTOR      = ['franco','rodrigo','remo'];
const MEDIOS_OK       = ['efectivo','transferencia_bancaria'];
const EXPECTED_ACTION = 'cuenta_corriente.retirar';
const IDEM_RE         = /^[A-Za-z0-9_-]{8,64}$/;
const MONTO_RE        = /^[0-9]{1,12}(\.[0-9]{1,2})?$/;
const UUID_RE         = /^[0-9a-fA-F-]{36}$/;
const MAXLEN          = 1000;

function rej(motivo, body) {
  body = body || {};
  return [{ json: { ok_firma:false, motivo, ambiente_esperado: body.ambiente_esperado ?? null,
    rol: body.rol ?? null, action: body.action ?? null, ts: (typeof body.ts!=='undefined'?body.ts:null),
    actor: body.actor ?? null, idempotency_key: body.idempotency_key ?? null,
    id_socio: null, user_id: null, nonce: null, payload: null } }];
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

// 2) Firma HMAC recomputada sobre los mismos bytes (hex en minuscula).
const headers = wh.headers || {};
const sigHeader = headers['x-vita-signature'] || headers['X-Vita-Signature'] || '';
const expectedHex = crypto.createHmac('sha256', SECRET).update(buf).digest('hex');
const expected = 'sha256=' + expectedHex;
let firmaOk = false;
try { const a = Buffer.from(sigHeader); const b = Buffer.from(expected); firmaOk = a.length === b.length && crypto.timingSafeEqual(a, b); } catch (e) { firmaOk = false; }
if (!firmaOk) return rej('firma_invalida', {});

// 3) nonce = firma ESPERADA calculada y normalizada (D-C-56).
const nonce = expectedHex.toLowerCase();

// 4) Parseo (firma ya validada).
let body;
try { body = JSON.parse(buf.toString('utf8')); } catch (e) { return rej('payload_invalido', {}); }

// 5) Ventana ts +-300s.
const ts = Number(body.ts);
if (!Number.isFinite(ts) || Math.abs(Date.now() - ts) > 300000) return rej('ts_fuera_de_ventana', body);

// 6) Rol allowlist (D-C-39).
if (!ROLES_OK.includes(body.rol)) return rej('rol_no_permitido', body);
// 7) Action binding (D-C-41).
if (body.action !== EXPECTED_ACTION) return rej('accion_desconocida', body);
// 8) actor (sobre firmado; persona socio).
if (typeof body.actor !== 'string' || !ENUM_ACTOR.includes(body.actor)) return rej('payload_invalido', body);
// 9) idempotency_key formato estricto.
if (typeof body.idempotency_key !== 'string' || !IDEM_RE.test(body.idempotency_key)) return rej('payload_invalido', body);

// 10) id_socio + user_id INYECTADOS por el gateway (sobre firmado), 2da defensa. NO vienen del payload.
const idSocioRaw = body.id_socio;
let idSocio = null;
if (typeof idSocioRaw === 'number' && Number.isSafeInteger(idSocioRaw) && idSocioRaw > 0) idSocio = idSocioRaw;
else if (typeof idSocioRaw === 'string' && /^[0-9]{1,18}$/.test(idSocioRaw) && Number(idSocioRaw) > 0) idSocio = Number(idSocioRaw);
if (idSocio === null) return rej('payload_invalido', body);
const userId = (typeof body.user_id === 'string' && UUID_RE.test(body.user_id)) ? body.user_id : null;
if (userId === null) return rej('payload_invalido', body);

// 11) Payload de negocio: REJECT-UNKNOWN {monto, medio_pago, comentario}.
const p = body.payload;
if (!p || typeof p !== 'object' || Array.isArray(p)) return rej('payload_invalido', body);
const PERMITIDAS = ['monto','medio_pago','comentario'];
for (const k of Object.keys(p)) { if (!PERMITIDAS.includes(k)) return rej('payload_invalido', body); }

// monto STRING (D-A29-1): <=12 enteros, <=2 decimales, > 0. Espejo textual de portal_registrar_retiro.
if (typeof p.monto !== 'string' || !MONTO_RE.test(p.monto) || !(Number(p.monto) > 0)) return rej('payload_invalido', body);
if (typeof p.medio_pago !== 'string' || !MEDIOS_OK.includes(p.medio_pago)) return rej('payload_invalido', body);
if (p.comentario != null && (typeof p.comentario !== 'string' || p.comentario.length > MAXLEN)) return rej('payload_invalido', body);

// comentario: trim + '' -> null (ajuste 3).
const comentarioTrim = (p.comentario != null ? p.comentario.trim() : '');
const payloadWL = {
  monto: p.monto,
  medio_pago: p.medio_pago,
  comentario: (comentarioTrim !== '' ? comentarioTrim : null)
};

return [{ json: { ok_firma:true, motivo:null, ambiente_esperado: body.ambiente_esperado ?? null,
  rol: body.rol, action: body.action, ts, actor: body.actor,
  idempotency_key: body.idempotency_key, id_socio: idSocio, user_id: userId, nonce, payload: payloadWL } }];
"""

# ---- Codigo: verificar_acceso (A29) ----
CODE_VERIFICAR = r"""// portal-a29-retiro__TEST - verificar_acceso (ambiente + envelope de rechazo).
const v = $('validar_firma_ts_rol').first().json;
const ambItem = $('leer_ambiente').first();
const real = (ambItem && ambItem.json) ? (ambItem.json.valor ?? null) : null;
function envErr(code, message, detail) { return [{ json: { ok:false, error: { code, message, detail: detail ?? null } } }]; }
if (!v.ok_firma) {
  const msgs = {
    firma_invalida: 'firma HMAC invalida o ausente',
    ts_fuera_de_ventana: 'timestamp fuera de la ventana permitida (300s)',
    payload_invalido: 'payload invalido (monto/medio_pago/comentario, actor, identidad o idempotency_key)',
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
"""

# ---- Codigo: Code: derivar (A29) ----
CODE_DERIVAR = r"""// portal-a29-retiro__TEST - Code: derivar.
// Arma el jsonb para portal_registrar_retiro (SB1): negocio (monto/medio_pago/comentario del payload
// whitelisteado) + control server-side. id_socio/user_id salen del SOBRE (inyectados por el gateway),
// NUNCA del payload. source_event y creado_por NO se mandan: los deriva la funcion ('portal_a29_'||key ;
// creado_por = actor). request_ts = ts del sobre (opcional; la funcion estampa fecha=hoy AR internamente).
const v = $('validar_firma_ts_rol').first().json;
const idem = v.idempotency_key;
const fnPayload = {
  monto: v.payload.monto,
  medio_pago: v.payload.medio_pago,
  comentario: v.payload.comentario,
  id_socio: v.id_socio,
  user_id: v.user_id,
  actor: v.actor,
  rol: v.rol,
  nonce: v.nonce,
  idempotency_key: idem,
  request_ts: v.ts
};
const payload1 = JSON.stringify(fnPayload);
return [{ json: { payload1, idem, sev: 'portal_a29_' + idem } }];
"""

# ---- Codigo: router_retiro (A29) ----
CODE_ROUTER = r"""// portal-a29-retiro__TEST - router_retiro.
// portal_registrar_retiro ya devuelve el contrato final {ok,data|error} con codigos de la allowlist
// (ok idempotente/nuevo; saldo_insuficiente; conflicto nonce_replay/payload_mismatch/actor_mismatch;
// payload_invalido; rol_no_permitido; error_interno). Solo agregamos estado_incierto si el nodo PG no
// devolvio el contrato (fallo de dispatch; L-8D-01).
const res = $json.resultado;
const D = $('Code: derivar').first().json;
if (!res || typeof res !== 'object') {
  return [{ json: { ok:false, error: { code:'estado_incierto',
    message:'estado incierto al registrar el retiro; verificar antes de reintentar con la misma idempotency_key',
    detail: { idempotency_key: D.idem, source_event: D.sev } } } }];
}
return [{ json: res }];
"""

# ---- Mutacion ----
wf["name"] = "portal-a29-retiro__TEST"
wf["pinData"] = {}          # template limpio
wf["active"] = False

RENAME = {"PG cargar_gasto": "PG registrar_retiro", "router_cargar": "router_retiro"}

for n in wf.get("nodes", []):
    nm = n.get("name")
    if nm == "Webhook":
        n["parameters"]["path"] = PATH
    elif nm == "validar_firma_ts_rol":
        n["parameters"]["jsCode"] = CODE_VALIDAR
    elif nm == "verificar_acceso":
        n["parameters"]["jsCode"] = CODE_VERIFICAR
    elif nm == "Code: derivar":
        n["parameters"]["jsCode"] = CODE_DERIVAR
    elif nm == "PG cargar_gasto":
        n["name"] = RENAME[nm]
        n["parameters"]["query"] = "SELECT portal_registrar_retiro($1::jsonb) AS resultado;"
        # queryReplacement ya apunta a $('Code: derivar') -> se mantiene
    elif nm == "router_cargar":
        n["name"] = RENAME[nm]
        n["parameters"]["jsCode"] = CODE_ROUTER

# ---- Reconstruir connections con los nombres finales ----
def rn(name): return RENAME.get(name, name)
new_conn = {}
for src, val in wf.get("connections", {}).items():
    outs = []
    for branch in val.get("main", []):
        nb = [{"node": rn(t["node"]), "type": t.get("type","main"), "index": t.get("index",0)} for t in branch]
        outs.append(nb)
    new_conn[rn(src)] = {"main": outs}
wf["connections"] = new_conn

with io.open(DST, "w", encoding="utf-8") as f:
    json.dump(wf, f, ensure_ascii=False, indent=1)
    f.write("\n")

# ---- Reporte ----
print("escrito:", DST)
print("nodos:")
for n in wf["nodes"]:
    print("  -", repr(n["name"]), "|", n["type"])
print("webhook path:", [n["parameters"].get("path") for n in wf["nodes"] if n["name"]=="Webhook"][0])
print("PG query:", [n["parameters"].get("query") for n in wf["nodes"] if n["name"]=="PG registrar_retiro"][0])
print("connections keys:", list(wf["connections"].keys()))
