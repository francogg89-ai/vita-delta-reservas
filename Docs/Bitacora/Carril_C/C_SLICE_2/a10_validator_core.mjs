// a10_validator_core.mjs
// Logica PURA del validar_firma_ts_rol de A10 (wrapper portal-a10-registrar-saldo__TEST).
// Esta funcion es el ESPEJO EXACTO de la logica embebida en el Code node de n8n.
// El Code node adapta $input (binary + headers) y llama a esta misma logica inline.
// Se testea aca en Node para validar reject-unknown, firma, ts, monto, idempotency_key,
// actor coherente, etc., ANTES de importar a n8n.
//
// Contrato de salida:
//   OK   -> { auth_ok:true, action, rol, actor, ambiente_esperado, ts, nonce, payload:{...} }
//   FAIL -> { auth_ok:false, error:'<codigo allowlist>', message:'<curado>' }
// Todos los codigos de error pertenecen a la allowlist del gateway (D-C-18).

import crypto from 'node:crypto';

export const EXPECTED_ACTION = 'cobranza.registrar_saldo';
export const ROLES_OK = ['vicky', 'socio'];
export const ENUM_ACTOR = ['vicky', 'franco', 'rodrigo', 'remo'];
export const ENUM_MEDIO_A10 = ['efectivo', 'transferencia_bancaria', 'transferencia_mp', 'cripto'];
export const MONTO_MAX = 9999999999.99; // tope NUMERIC(12,2)
export const TS_WINDOW_MS = 300000;     // +-300s
export const MAXLEN = 1000;
export const ENVELOPE_KEYS = ['action', 'payload', 'rol', 'ambiente_esperado', 'ts', 'nonce', 'actor'];
export const PAYLOAD_KEYS = ['id_reserva', 'monto', 'medio_pago', 'idempotency_key', 'notas'];

export function actorCoherente(rol, nombre) {
  if (rol === 'vicky') return nombre === 'vicky';
  if (rol === 'socio') return nombre === 'franco' || nombre === 'rodrigo' || nombre === 'remo';
  return false;
}

const fail = (error, message) => ({ auth_ok: false, error, message });

// raw: Buffer con los bytes crudos del body. sigHeader: string 'sha256=<hex>'.
// secret: string. nowMs: epoch ms (inyectable para test).
export function coreValidate(raw, sigHeader, secret, nowMs) {
  // 0. Modo B: assert por prefijo (en el Code node real el placeholder se reemplaza).
  if (typeof secret !== 'string' || secret.length === 0 || secret.startsWith('__PEGAR_')) {
    // En el Code node esto es throw (error de config), no un envelope; aca lo marcamos.
    return fail('config', 'secreto HMAC sin reemplazar');
  }

  // 1. Raw body presente.
  if (!Buffer.isBuffer(raw) || raw.length === 0) return fail('raw_body_ausente', 'raw body ausente');

  // 2. Firma: HMAC-SHA256 timing-safe sobre los bytes crudos.
  const expected = crypto.createHmac('sha256', secret).update(raw).digest(); // Buffer
  const m = /^sha256=([0-9a-fA-F]+)$/.exec(String(sigHeader || ''));
  if (!m) return fail('firma_invalida', 'firma ausente o con formato invalido');
  let provided;
  try { provided = Buffer.from(m[1], 'hex'); } catch { return fail('firma_invalida', 'firma invalida'); }
  if (provided.length !== expected.length || !crypto.timingSafeEqual(provided, expected)) {
    return fail('firma_invalida', 'firma invalida');
  }

  // 3. Parse del sobre desde los bytes crudos (fidelidad con la firma).
  let env;
  try { env = JSON.parse(raw.toString('utf8')); } catch { return fail('payload_invalido', 'sobre no es JSON'); }
  if (typeof env !== 'object' || env === null || Array.isArray(env)) return fail('payload_invalido', 'sobre invalido');

  // 4. Envelope reject-unknown.
  for (const k of Object.keys(env)) {
    if (!ENVELOPE_KEYS.includes(k)) return fail('payload_invalido', 'clave de sobre no permitida: ' + k);
  }

  // 5. ts.
  if (typeof env.ts !== 'number' || !Number.isFinite(env.ts)) return fail('payload_invalido', 'ts invalido');
  if (Math.abs(nowMs - env.ts) > TS_WINDOW_MS) return fail('ts_fuera_de_ventana', 'ts fuera de ventana');

  // 6. action binding (D-C-41).
  if (env.action !== EXPECTED_ACTION) return fail('payload_invalido', 'action no coincide con el endpoint');

  // 7. rol.
  if (!ROLES_OK.includes(env.rol)) return fail('rol_no_permitido', 'rol no habilitado');

  // 8. actor (server-side; aca llega en el sobre). enum + coherencia.
  if (typeof env.actor !== 'string' || !ENUM_ACTOR.includes(env.actor)) return fail('payload_invalido', 'actor invalido');
  if (!actorCoherente(env.rol, env.actor)) return fail('rol_no_permitido', 'actor incoherente con rol');

  // 9. ambiente_esperado + nonce presentes (el match real de ambiente es en verificar_acceso).
  if (typeof env.ambiente_esperado !== 'string' || env.ambiente_esperado.length === 0) return fail('payload_invalido', 'ambiente_esperado invalido');
  if (typeof env.nonce !== 'string' || env.nonce.length === 0) return fail('payload_invalido', 'nonce invalido');

  // 10. payload reject-unknown + tipos estrictos.
  const p = env.payload;
  if (typeof p !== 'object' || p === null || Array.isArray(p)) return fail('payload_invalido', 'payload invalido');
  for (const k of Object.keys(p)) {
    if (!PAYLOAD_KEYS.includes(k)) return fail('payload_invalido', 'clave de payload no permitida: ' + k);
  }

  // id_reserva: entero positivo estricto.
  if (typeof p.id_reserva !== 'number' || !Number.isSafeInteger(p.id_reserva) || p.id_reserva <= 0) {
    return fail('payload_invalido', 'id_reserva debe ser entero positivo');
  }

  // monto: number real, finito, >0, max 2 decimales, dentro de NUMERIC(12,2).
  const monto = p.monto;
  if (typeof monto !== 'number' || !Number.isFinite(monto) || monto <= 0) {
    return fail('payload_invalido', 'monto debe ser numero positivo finito');
  }
  const cents = Math.round(monto * 100);
  if (Math.abs(monto * 100 - cents) > 1e-6) return fail('payload_invalido', 'monto admite maximo 2 decimales');
  if (cents <= 0 || monto > MONTO_MAX) return fail('payload_invalido', 'monto fuera de rango');

  // medio_pago: enum A10 (sin mp_link).
  if (!ENUM_MEDIO_A10.includes(p.medio_pago)) return fail('payload_invalido', 'medio_pago invalido');

  // idempotency_key: string, 8-64, charset acotado.
  const key = p.idempotency_key;
  if (typeof key !== 'string' || key.length < 8 || key.length > 64 || !/^[A-Za-z0-9_-]+$/.test(key)) {
    return fail('payload_invalido', 'idempotency_key invalida');
  }

  // notas: opcional.
  if (p.notas !== undefined && p.notas !== null && (typeof p.notas !== 'string' || p.notas.length > MAXLEN)) {
    return fail('payload_invalido', 'notas invalida');
  }

  return {
    auth_ok: true,
    action: env.action,
    rol: env.rol,
    actor: env.actor,
    ambiente_esperado: env.ambiente_esperado,
    ts: env.ts,
    nonce: env.nonce,
    payload: {
      id_reserva: p.id_reserva,
      monto: monto,
      medio_pago: p.medio_pago,
      idempotency_key: key,
      notas: (p.notas !== undefined && p.notas !== null) ? p.notas : null,
    },
  };
}

// Derivacion server-side de source_event (espejo del Code node 'derivar').
export function deriveSourceEvent(id_reserva, idempotency_key) {
  const canon = String(id_reserva) + '|' + idempotency_key;
  const h = crypto.createHash('sha256').update(canon, 'utf8').digest('hex').slice(0, 12);
  return 'portal_test_a10_res' + id_reserva + '_' + h;
}
