const crypto = require('crypto');

// Secreto (L-C-10): $vars.VITA_HMAC_SECRET si existe; si no, placeholder pegado a mano (Modo B).
// Mismo patron que A05/A06/A12. Assert duro POR PREFIJO sobrevive al find-replace del placeholder.
const SECRET = (typeof $vars !== 'undefined' && $vars && $vars.VITA_HMAC_SECRET)
  ? $vars.VITA_HMAC_SECRET
  : '__PEGAR_SECRETO_O_USAR_VARIABLE__';
if (!SECRET || SECRET.startsWith('__PEGAR_')) {
  throw new Error('VITA_HMAC_SECRET no configurado; abortando (assert duro por prefijo).');
}

const EXPECTED_ACTION = 'cobranza.registrar_saldo';
const ROLES_OK = ['vicky', 'socio'];
const ENUM_ACTOR = ['vicky', 'franco', 'rodrigo', 'remo'];
const ENUM_MEDIO_A10 = ['efectivo', 'transferencia_bancaria', 'transferencia_mp', 'cripto'];
const MONTO_MAX = 9999999999.99;
const TS_WINDOW_MS = 300000;
const MAXLEN = 1000;
const ENVELOPE_KEYS = ['action', 'payload', 'rol', 'ambiente_esperado', 'ts', 'nonce', 'actor'];
const PAYLOAD_KEYS = ['id_reserva', 'monto', 'medio_pago', 'idempotency_key', 'notas'];

function actorCoherente(rol, nombre) {
  if (rol === 'vicky') return nombre === 'vicky';
  if (rol === 'socio') return nombre === 'franco' || nombre === 'rodrigo' || nombre === 'remo';
  return false;
}
const fail = (error, message) => [{ json: { __auth_ok: false, error: error, message: message } }];

// Raw body como Buffer EXACTO. PATRON A12 (probado 8/8 en este n8n): binario 'data' via
// getBinaryDataBuffer; fallback wh.rawBody incl. forma serializada {type:'Buffer',data:[...]}
// (L-C-05). Webhook typeVersion 2.1 (igual que A12) para que el raw aterrice.
const item = $input.first();
const wh = item.json;

let raw = null;
let via = 'none';
const diag = { rawread: 'v5' };
try {
  if (item.binary && item.binary.data) {
    raw = await this.helpers.getBinaryDataBuffer(0, 'data');
    if (raw && raw.length) via = 'getBinaryDataBuffer';
  }
} catch (e) { diag.getBinErr = String((e && e.message) || e); raw = null; }
if (!raw || !raw.length) {
  const rawField = wh.rawBody;
  if (Buffer.isBuffer(rawField)) { raw = rawField; via = 'rawBody.buffer'; }
  else if (rawField && rawField.type === 'Buffer' && Array.isArray(rawField.data)) { raw = Buffer.from(rawField.data); via = 'rawBody.serialized'; }
  else if (typeof rawField === 'string') { raw = Buffer.from(rawField, 'utf8'); via = 'rawBody.string'; }
}
if (!raw || raw.length === 0) {
  diag.via = via;
  diag.binary = !!(item && item.binary);
  const bd = (item && item.binary && item.binary.data) ? item.binary.data : null;
  diag.binaryDataKeys = bd ? Object.keys(bd) : [];
  diag.binDataType = bd ? typeof bd.data : 'no-bd';
  diag.binDataLen = (bd && typeof bd.data === 'string') ? bd.data.length : null;
  diag.binHasId = !!(bd && bd.id);
  diag.rawBodyType = typeof wh.rawBody;
  diag.contentLength = (wh.headers && (wh.headers['content-length'] || wh.headers['Content-Length'])) || null;
  return fail('raw_body_ausente', 'raw body ausente | diag ' + JSON.stringify(diag));
}

// Firma: HMAC-SHA256 sobre los MISMOS bytes; compara el header completo timing-safe (patron A12).
const headers = wh.headers || {};
const sigHeader = headers['x-vita-signature'] || headers['X-Vita-Signature'] || '';
const expected = 'sha256=' + crypto.createHmac('sha256', SECRET).update(raw).digest('hex');
let firmaOk = false;
try {
  const a = Buffer.from(String(sigHeader || ''));
  const b = Buffer.from(expected);
  firmaOk = a.length === b.length && crypto.timingSafeEqual(a, b);
} catch (e) { firmaOk = false; }
if (!firmaOk) return fail('firma_invalida', 'firma invalida');

let env;
try { env = JSON.parse(raw.toString('utf8')); } catch (e) { return fail('payload_invalido', 'sobre no es JSON'); }
if (typeof env !== 'object' || env === null || Array.isArray(env)) return fail('payload_invalido', 'sobre invalido');
for (const k of Object.keys(env)) if (!ENVELOPE_KEYS.includes(k)) return fail('payload_invalido', 'clave de sobre no permitida: ' + k);

if (typeof env.ts !== 'number' || !Number.isFinite(env.ts)) return fail('payload_invalido', 'ts invalido');
if (Math.abs(Date.now() - env.ts) > TS_WINDOW_MS) return fail('ts_fuera_de_ventana', 'ts fuera de ventana');
if (env.action !== EXPECTED_ACTION) return fail('payload_invalido', 'action no coincide con el endpoint');
if (!ROLES_OK.includes(env.rol)) return fail('rol_no_permitido', 'rol no habilitado');
if (typeof env.actor !== 'string' || !ENUM_ACTOR.includes(env.actor)) return fail('payload_invalido', 'actor invalido');
if (!actorCoherente(env.rol, env.actor)) return fail('rol_no_permitido', 'actor incoherente con rol');
if (typeof env.ambiente_esperado !== 'string' || env.ambiente_esperado.length === 0) return fail('payload_invalido', 'ambiente_esperado invalido');
if (typeof env.nonce !== 'string' || env.nonce.length === 0) return fail('payload_invalido', 'nonce invalido');

const p = env.payload;
if (typeof p !== 'object' || p === null || Array.isArray(p)) return fail('payload_invalido', 'payload invalido');
for (const k of Object.keys(p)) if (!PAYLOAD_KEYS.includes(k)) return fail('payload_invalido', 'clave de payload no permitida: ' + k);
if (typeof p.id_reserva !== 'number' || !Number.isSafeInteger(p.id_reserva) || p.id_reserva <= 0) return fail('payload_invalido', 'id_reserva debe ser entero positivo');
const monto = p.monto;
if (typeof monto !== 'number' || !Number.isFinite(monto) || monto <= 0) return fail('payload_invalido', 'monto debe ser numero positivo finito');
const cents = Math.round(monto * 100);
if (Math.abs(monto * 100 - cents) > 1e-6) return fail('payload_invalido', 'monto admite maximo 2 decimales');
if (cents <= 0 || monto > MONTO_MAX) return fail('payload_invalido', 'monto fuera de rango');
if (!ENUM_MEDIO_A10.includes(p.medio_pago)) return fail('payload_invalido', 'medio_pago invalido');
const key = p.idempotency_key;
if (typeof key !== 'string' || key.length < 8 || key.length > 64 || !/^[A-Za-z0-9_-]+$/.test(key)) return fail('payload_invalido', 'idempotency_key invalida');
if (p.notas !== undefined && p.notas !== null && (typeof p.notas !== 'string' || p.notas.length > MAXLEN)) return fail('payload_invalido', 'notas invalida');

return [{ json: {
  __auth_ok: true,
  action: env.action, rol: env.rol, actor: env.actor,
  ambiente_esperado: env.ambiente_esperado, ts: env.ts, nonce: env.nonce,
  payload: { id_reserva: p.id_reserva, monto: monto, medio_pago: p.medio_pago, idempotency_key: key, notas: (p.notas != null ? p.notas : null) }
}}];