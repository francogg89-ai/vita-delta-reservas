// test_a10_validator.mjs
// Test de logica del validar_firma_ts_rol de A10. Firma sobres EXACTAMENTE como
// buildSignedEnvelope del gateway (HMAC-SHA256 hex sobre JSON.stringify(envelope))
// y verifica la matriz de seguridad + casos felices. Corre en Node, sin n8n.

import crypto from 'node:crypto';
import { coreValidate, deriveSourceEvent } from './a10_validator_core.mjs';

const SECRET = 'test-secret-solo-para-este-harness-no-es-el-real';
const NOW = 1_750_000_000_000; // epoch ms fijo para reproducibilidad

// Firma como el gateway: body = JSON.stringify(envelope); header = 'sha256=' + hmacHex(body)
function sign(envelope, secret = SECRET) {
  const body = JSON.stringify(envelope);
  const hex = crypto.createHmac('sha256', secret).update(Buffer.from(body, 'utf8')).digest('hex');
  return { raw: Buffer.from(body, 'utf8'), sig: 'sha256=' + hex };
}

function baseEnvelope(overrides = {}, payloadOverrides = {}) {
  const env = {
    action: 'cobranza.registrar_saldo',
    payload: {
      id_reserva: 101,
      monto: 50000,
      medio_pago: 'transferencia_mp',
      idempotency_key: 'a1b2c3d4e5f6',
      notas: 'pago saldo test',
      ...payloadOverrides,
    },
    rol: 'vicky',
    ambiente_esperado: 'test',
    ts: NOW,
    nonce: '11111111-1111-1111-1111-111111111111',
    actor: 'vicky',
    ...overrides,
  };
  return env;
}

let passed = 0, failed = 0;
const fails = [];

// expectAuthOk: true => esperamos auth_ok:true. Si no, esperamos auth_ok:false con error===expectError.
function run(name, { env, mutateRaw, sig, secret, now = NOW, expectAuthOk, expectError }) {
  let raw, sigHeader;
  if (env !== undefined) {
    const s = sign(env, secret);
    raw = s.raw; sigHeader = s.sig;
  }
  if (sig !== undefined) sigHeader = sig;
  if (mutateRaw) raw = mutateRaw(raw);
  const res = coreValidate(raw, sigHeader, secret ?? SECRET, now);
  let ok;
  if (expectAuthOk) {
    ok = res.auth_ok === true;
  } else {
    ok = res.auth_ok === false && res.error === expectError;
  }
  if (ok) { passed++; }
  else { failed++; fails.push({ name, expectAuthOk, expectError, got: res.auth_ok ? 'auth_ok' : res.error, msg: res.message }); }
  const tag = ok ? 'PASS' : 'FAIL';
  console.log(`${tag}  ${name}` + (ok ? '' : `  (esperado ${expectAuthOk ? 'auth_ok' : expectError}, obtuve ${res.auth_ok ? 'auth_ok' : res.error})`));
}

console.log('=== A10 validar_firma_ts_rol - matriz de seguridad ===\n');

// ---- Casos felices ----
run('FELIZ vicky/transferencia_mp', { env: baseEnvelope(), expectAuthOk: true });
run('FELIZ socio=franco/efectivo', { env: baseEnvelope({ rol: 'socio', actor: 'franco' }, { medio_pago: 'efectivo' }), expectAuthOk: true });
run('FELIZ socio=remo/cripto', { env: baseEnvelope({ rol: 'socio', actor: 'remo' }, { medio_pago: 'cripto' }), expectAuthOk: true });
run('FELIZ socio=rodrigo/transferencia_bancaria', { env: baseEnvelope({ rol: 'socio', actor: 'rodrigo' }, { medio_pago: 'transferencia_bancaria' }), expectAuthOk: true });
run('FELIZ notas null', { env: baseEnvelope({}, { notas: null }), expectAuthOk: true });
run('FELIZ monto con 2 decimales (12345.67)', { env: baseEnvelope({}, { monto: 12345.67 }), expectAuthOk: true });
run('FELIZ monto tope NUMERIC(12,2)', { env: baseEnvelope({}, { monto: 9999999999.99 }), expectAuthOk: true });

// ---- Firma / raw body ----
run('FIRMA mala (otro secreto)', { env: baseEnvelope(), sig: sign(baseEnvelope(), 'otro-secreto').sig, expectAuthOk: false, expectError: 'firma_invalida' });
run('FIRMA ausente', { env: baseEnvelope(), sig: '', expectAuthOk: false, expectError: 'firma_invalida' });
run('FIRMA formato invalido', { env: baseEnvelope(), sig: 'md5=zzz', expectAuthOk: false, expectError: 'firma_invalida' });
run('FIRMA body alterado tras firmar', { env: baseEnvelope(), mutateRaw: (b) => Buffer.concat([b, Buffer.from(' ')]), expectAuthOk: false, expectError: 'firma_invalida' });
run('RAW body vacio', { env: baseEnvelope(), mutateRaw: () => Buffer.alloc(0), expectAuthOk: false, expectError: 'raw_body_ausente' });

// ---- ts ----
run('TS viejo (>300s)', { env: baseEnvelope({ ts: NOW - 300001 }), expectAuthOk: false, expectError: 'ts_fuera_de_ventana' });
run('TS futuro (>300s)', { env: baseEnvelope({ ts: NOW + 300001 }), expectAuthOk: false, expectError: 'ts_fuera_de_ventana' });
run('TS borde -300s OK', { env: baseEnvelope({ ts: NOW - 300000 }), expectAuthOk: true });
run('TS no numerico', { env: baseEnvelope({ ts: '123' }), expectAuthOk: false, expectError: 'payload_invalido' });

// ---- action binding ----
run('ACTION distinta', { env: baseEnvelope({ action: 'reserva.crear_manual' }), expectAuthOk: false, expectError: 'payload_invalido' });

// ---- rol ----
run('ROL jenny', { env: baseEnvelope({ rol: 'jenny', actor: 'vicky' }), expectAuthOk: false, expectError: 'rol_no_permitido' });
run('ROL basura', { env: baseEnvelope({ rol: 'x', actor: 'vicky' }), expectAuthOk: false, expectError: 'rol_no_permitido' });

// ---- actor ----
run('ACTOR fuera de enum', { env: baseEnvelope({ actor: 'pepe' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('ACTOR incoherente vicky->franco', { env: baseEnvelope({ rol: 'vicky', actor: 'franco' }), expectAuthOk: false, expectError: 'rol_no_permitido' });
run('ACTOR incoherente socio->vicky', { env: baseEnvelope({ rol: 'socio', actor: 'vicky' }), expectAuthOk: false, expectError: 'rol_no_permitido' });
run('ACTOR ausente', { env: (() => { const e = baseEnvelope(); delete e.actor; return e; })(), expectAuthOk: false, expectError: 'payload_invalido' });

// ---- envelope reject-unknown ----
run('SOBRE clave extra', { env: baseEnvelope({ extra: 1 }), expectAuthOk: false, expectError: 'payload_invalido' });
run('SOBRE nonce ausente', { env: (() => { const e = baseEnvelope(); delete e.nonce; return e; })(), expectAuthOk: false, expectError: 'payload_invalido' });
run('SOBRE ambiente_esperado ausente', { env: (() => { const e = baseEnvelope(); delete e.ambiente_esperado; return e; })(), expectAuthOk: false, expectError: 'payload_invalido' });

// ---- payload reject-unknown (spoof server-side fields) ----
run('SPOOF actor en payload', { env: baseEnvelope({}, { actor: 'franco' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('SPOOF tipo en payload', { env: baseEnvelope({}, { tipo: 'sena' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('SPOOF source_event en payload', { env: baseEnvelope({}, { source_event: 'x' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('SPOOF estado_inicial en payload', { env: baseEnvelope({}, { estado_inicial: 'confirmado' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('SPOOF validado_por en payload', { env: baseEnvelope({}, { validado_por: 'franco' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('SPOOF monto_esperado en payload', { env: baseEnvelope({}, { monto_esperado: 1 }), expectAuthOk: false, expectError: 'payload_invalido' });
run('SPOOF id_pre_reserva en payload', { env: baseEnvelope({}, { id_pre_reserva: 5 }), expectAuthOk: false, expectError: 'payload_invalido' });

// ---- id_reserva ----
run('ID_RESERVA cero', { env: baseEnvelope({}, { id_reserva: 0 }), expectAuthOk: false, expectError: 'payload_invalido' });
run('ID_RESERVA negativo', { env: baseEnvelope({}, { id_reserva: -3 }), expectAuthOk: false, expectError: 'payload_invalido' });
run('ID_RESERVA string', { env: baseEnvelope({}, { id_reserva: '101' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('ID_RESERVA float', { env: baseEnvelope({}, { id_reserva: 10.5 }), expectAuthOk: false, expectError: 'payload_invalido' });

// ---- monto ----
run('MONTO cero', { env: baseEnvelope({}, { monto: 0 }), expectAuthOk: false, expectError: 'payload_invalido' });
run('MONTO negativo', { env: baseEnvelope({}, { monto: -100 }), expectAuthOk: false, expectError: 'payload_invalido' });
run('MONTO string', { env: baseEnvelope({}, { monto: '50000' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('MONTO 3 decimales', { env: baseEnvelope({}, { monto: 100.123 }), expectAuthOk: false, expectError: 'payload_invalido' });
run('MONTO fuera de rango (>NUMERIC 12,2)', { env: baseEnvelope({}, { monto: 10000000000.00 }), expectAuthOk: false, expectError: 'payload_invalido' });
// MONTO Infinity: JSON.parse('1e400') => Infinity. Firmamos el raw mutado para que llegue
// a la validacion de monto y rebote por !Number.isFinite (no por firma).
{
  const rawInf = Buffer.from(JSON.stringify(baseEnvelope()).replace('"monto":50000', '"monto":1e400'), 'utf8');
  const sigInf = 'sha256=' + crypto.createHmac('sha256', SECRET).update(rawInf).digest('hex');
  const r = coreValidate(rawInf, sigInf, SECRET, NOW);
  const ok = r.auth_ok === false && r.error === 'payload_invalido';
  if (ok) passed++; else { failed++; fails.push({ name: 'MONTO Infinity via raw', got: r.auth_ok ? 'auth_ok' : r.error, msg: r.message }); }
  console.log(`${ok ? 'PASS' : 'FAIL'}  MONTO Infinity via raw (1e400 -> Infinity)`);
}

// ---- medio_pago ----
run('MEDIO mp_link (no expuesto en A10)', { env: baseEnvelope({}, { medio_pago: 'mp_link' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('MEDIO invalido', { env: baseEnvelope({}, { medio_pago: 'bitcoin' }), expectAuthOk: false, expectError: 'payload_invalido' });

// ---- idempotency_key ----
run('IDEMKEY ausente', { env: baseEnvelope({}, { idempotency_key: undefined }), expectAuthOk: false, expectError: 'payload_invalido' });
run('IDEMKEY corta (<8)', { env: baseEnvelope({}, { idempotency_key: 'abc' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('IDEMKEY larga (>64)', { env: baseEnvelope({}, { idempotency_key: 'a'.repeat(65) }), expectAuthOk: false, expectError: 'payload_invalido' });
run('IDEMKEY charset invalido', { env: baseEnvelope({}, { idempotency_key: 'abc def!' }), expectAuthOk: false, expectError: 'payload_invalido' });
run('IDEMKEY UUID v4 valido', { env: baseEnvelope({}, { idempotency_key: '550e8400-e29b-41d4-a716-446655440000' }), expectAuthOk: true });

// ---- notas ----
run('NOTAS demasiado larga', { env: baseEnvelope({}, { notas: 'x'.repeat(1001) }), expectAuthOk: false, expectError: 'payload_invalido' });

console.log('\n=== source_event deterministico (PII-free) ===');
const se1 = deriveSourceEvent(101, 'a1b2c3d4e5f6');
const se2 = deriveSourceEvent(101, 'a1b2c3d4e5f6');
const se3 = deriveSourceEvent(101, 'OTRA-key-distinta');
const se4 = deriveSourceEvent(202, 'a1b2c3d4e5f6');
console.log('  determinista (misma key => mismo se):', se1 === se2 ? 'PASS' : 'FAIL', se1);
console.log('  key distinta => se distinto:', se1 !== se3 ? 'PASS' : 'FAIL');
console.log('  reserva distinta => prefijo distinto:', (se1 !== se4 && se4.startsWith('portal_test_a10_res202_')) ? 'PASS' : 'FAIL', se4);
console.log('  formato/PII-free:', /^portal_test_a10_res\d+_[0-9a-f]{12}$/.test(se1) ? 'PASS' : 'FAIL');
if (se1 !== se2 || se1 === se3 || se1 === se4 || !/^portal_test_a10_res\d+_[0-9a-f]{12}$/.test(se1)) failed++;

console.log(`\n=== RESULTADO: ${passed} PASS / ${failed} FAIL ===`);
if (failed > 0) {
  console.log('\nFallos:');
  for (const f of fails) console.log('  -', f.name, '=> got', f.got, '(', f.msg, ')');
  process.exit(1);
}
console.log('TODO VERDE');
