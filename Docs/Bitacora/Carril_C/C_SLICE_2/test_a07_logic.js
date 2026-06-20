#!/usr/bin/env node
// Test harness A07.2 v2: (1) sintaxis; (2) validador REAL con secreto de test
// (valida B3 estricto: firma + reject-unknown + fecha/hora/contacto); (3) derivar idem;
// (4) B1 payload2.id_pre_reserva; (5) B2 {ok,data}; (6) ajustes 2 y 3. No toca n8n ni la base.
const fs = require('fs');
const cp = require('child_process');
const path = require('path');
const crypto = require('crypto');

const wf = JSON.parse(fs.readFileSync('/home/claude/a07_2/portal-a07-crear-reserva__TEST__TEMPLATE_v2.json', 'utf8'));
const code = {};
for (const n of wf.nodes) if (n.type === 'n8n-nodes-base.code') code[n.name] = n.parameters.jsCode;

let fail = 0;
function ok(cond, msg) { console.log((cond ? '  [OK] ' : '  [X]  ') + msg); if (!cond) fail++; }

// ---------- (1) Sintaxis ----------
console.log('== (1) Sintaxis JS de los Code nodes ==');
const tmp = '/tmp/_nodecheck2'; fs.mkdirSync(tmp, { recursive: true });
for (const [name, js] of Object.entries(code)) {
  const fp = path.join(tmp, name.replace(/[^a-z0-9]/gi, '_') + '.js');
  fs.writeFileSync(fp, '(async function(){\n' + js + '\n})();\n');
  try { cp.execSync('node --check ' + fp, { stdio: 'pipe' }); ok(true, 'sintaxis ' + name); }
  catch (e) { ok(false, 'sintaxis ' + name + ' :: ' + String(e.stderr || e).split('\n')[1]); }
}

// ---------- Runners ----------
const SECRET = 'test-secret-a07-xyz';
function runValidador(bodyObj, { tamper = false } = {}) {
  const bodyStr = JSON.stringify(bodyObj);
  const hmac = crypto.createHmac('sha256', SECRET).update(Buffer.from(bodyStr, 'utf8')).digest('hex');
  const sig = tamper ? 'sha256=deadbeef' : ('sha256=' + hmac);
  const item = { json: { rawBody: bodyStr, headers: { 'x-vita-signature': sig } } };
  const $input = { first: () => item };
  const $vars = { VITA_HMAC_SECRET: SECRET };
  const fn = new Function('$input', '$vars', 'require', 'Buffer',
    'return (async () => {\n' + code['validar_firma_ts_rol'] + '\n})();');
  return fn($input, $vars, require, Buffer);
}
function runCode(name, { $json = {}, nodes = {} } = {}) {
  const $ = (n) => ({ first: () => ({ json: nodes[n] || {} }) });
  const fn = new Function('$json', '$', 'require', 'Buffer',
    'return (async () => {\n' + code[name] + '\n})();');
  return fn($json, $, require, Buffer);
}
const J = async (p) => (await p)[0].json;

// payload base valido (fixture A07.1)
const baseEnvelope = () => ({
  action: 'reserva.crear_manual', rol: 'vicky', actor: 'vicky',
  ambiente_esperado: 'test', ts: Date.now(), nonce: 'n1',
  payload: {
    id_cabana: 1, fecha_in: '2027-03-01', fecha_out: '2027-03-03', personas: 2,
    monto_total: 100000, monto_sena: 50000,
    canal_pago_esperado: 'transferencia_mp', medio_pago: 'transferencia_mp',
    huesped: { nombre: 'PORTAL TEST A07', telefono: '+5490000000007' }
  }
});

(async () => {
  // ---------- (2) Validador estricto (B3) ----------
  console.log('\n== (2) validar_firma_ts_rol (firma real + validacion estricta B3) ==');
  let o;
  o = await J(runValidador(baseEnvelope()));
  ok(o.ok_firma === true && o.actor === 'vicky', 'payload valido -> ok_firma:true');
  ok(o.payload && o.payload.huesped.telefono === '+5490000000007' && o.payload.huesped.email === null, 'payloadWL.huesped normalizado');

  o = await J(runValidador(baseEnvelope(), { tamper: true }));
  ok(o.ok_firma === false && o.motivo === 'firma_invalida', 'firma adulterada -> firma_invalida');

  let b;
  b = baseEnvelope(); b.payload.fecha_in = '2027-02-30';
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', 'fecha imposible 2027-02-30 -> payload_invalido');
  b = baseEnvelope(); b.payload.fecha_out = '2027-13-01';
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', 'mes 13 -> payload_invalido');
  b = baseEnvelope(); b.payload.hora_checkin_solicitada = '99:99';
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', 'hora 99:99 -> payload_invalido');
  b = baseEnvelope(); b.payload.hora_checkin_solicitada = '14:30';
  o = await J(runValidador(b)); ok(o.ok_firma === true, 'hora 14:30 valida -> ok');
  b = baseEnvelope(); b.payload.huesped = { nombre: 'X', telefono: 'abc' };
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', "telefono 'abc' (0 digitos) -> payload_invalido");
  b = baseEnvelope(); b.payload.huesped = { nombre: 'X', email: 'no-es-mail' };
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', 'email invalido -> payload_invalido');
  b = baseEnvelope(); b.payload.huesped = { nombre: 'X', email: 'a@b.com' };
  o = await J(runValidador(b)); ok(o.ok_firma === true, 'email valido (sin telefono) -> ok');
  b = baseEnvelope(); b.payload.huesped = { nombre: 'X' };
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', 'sin contacto -> payload_invalido');
  b = baseEnvelope(); b.payload.foo = 'x';
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', 'clave desconocida top-level -> payload_invalido');
  b = baseEnvelope(); b.payload.huesped.dni = '123';
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', 'clave desconocida en huesped -> payload_invalido');
  b = baseEnvelope(); b.payload.monto_sena = 150000;
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', 'monto_sena>monto_total -> payload_invalido');
  b = baseEnvelope(); b.payload.fecha_out = '2027-03-01';
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', 'fecha_out<=fecha_in -> payload_invalido');
  b = baseEnvelope(); b.actor = 'intruso';
  o = await J(runValidador(b)); ok(o.motivo === 'payload_invalido', 'actor fuera de enum -> payload_invalido');
  b = baseEnvelope(); b.rol = 'jenny';
  o = await J(runValidador(b)); ok(o.motivo === 'rol_no_permitido', 'rol jenny -> rol_no_permitido');
  b = baseEnvelope(); b.action = 'reserva.detalle';
  o = await J(runValidador(b)); ok(o.motivo === 'accion_desconocida', 'action ajena -> accion_desconocida');
  b = baseEnvelope(); b.ts = Date.now() - 999999;
  o = await J(runValidador(b)); ok(o.motivo === 'ts_fuera_de_ventana', 'ts viejo -> ts_fuera_de_ventana');

  // ---------- (3) derivar reproduce idem A07.1 ----------
  console.log('\n== (3) Code: derivar (idem A07.1) ==');
  const V = await J(runValidador(baseEnvelope()));
  const dOut = await J(runCode('Code: derivar', { nodes: { 'validar_firma_ts_rol': V } }));
  const EXP_IDEM = 'portal_test_a07_1_2027-03-01_2027-03-03_247269094ba8b76e3d43b027d48e39371ec72c162af3de1b408e833fc0491ef6_dee3c866744b';
  ok(dOut.idem === EXP_IDEM, 'idem reproduce vector A07.1 (validador->derivar end-to-end)');
  ok(JSON.parse(dOut.payload1).canal_origen === 'manual', "payload1.canal_origen='manual'");
  ok(dOut.payload2_base.estado_inicial === 'confirmado' && dOut.payload2_base.validado_por === 'vicky', 'payload2_base seña confirmada');

  // ---------- (4) B1: router1 payload2.id_pre_reserva ----------
  console.log('\n== (4) router1_crear (B1: payload2 con id_pre_reserva) ==');
  const Dfull = { idem: 'IDEM', sev: 'SEV', payload2_base: { tipo: 'sena', source_event: 'SEV' } };
  o = await J(runCode('router1_crear', { $json: { resultado: { ok: true, id_pre_reserva: 42 } }, nodes: { 'Code: derivar': Dfull } }));
  const pg2 = JSON.parse(o.pg2_args);
  ok(o.continuar === true && o.id_pre === 42, 'ok -> continuar con id_pre');
  ok(pg2.payload2.id_pre_reserva === 42, 'B1: pg2_args.payload2 incluye id_pre_reserva');
  ok(pg2.payload2.tipo === 'sena' && pg2.idem === 'IDEM', 'pg2_args conserva base + idem');
  o = await J(runCode('router1_crear', { $json: { resultado: { ok: false, error: 'no_disponible' } }, nodes: { 'Code: derivar': Dfull } }));
  ok(o.envelope.error.code === 'conflicto', 'no_disponible -> conflicto');
  o = await J(runCode('router1_crear', { $json: { resultado: { ok: false, error: 'excede_capacidad' } }, nodes: { 'Code: derivar': Dfull } }));
  ok(o.envelope.error.code === 'payload_invalido', 'excede_capacidad -> payload_invalido');

  // ---------- (5) B2: exitos con {ok,data} ----------
  console.log('\n== (5) routers de exito (B2: {ok:true,data}) ==');
  const nD = { 'Code: derivar': { idem: 'IDEM', sev: 'SEV', payload3_base: { created_by: 'vicky' } }, 'router1_crear': { id_pre: 42 } };
  o = await J(runCode('router0_precheck', { $json: { n: 1, id_reserva: 7, id_pre_reserva: 3, id_huesped: 9 }, nodes: { 'Code: derivar': { idem: 'I', sev: 'S' } } }));
  ok(o.envelope.ok === true && o.envelope.data && o.envelope.data.id_reserva === 7 && o.envelope.data.idempotent_match === true, 'router0 n=1 -> {ok,data,idempotent_match:true}');
  o = await J(runCode('router3_confirmar', { $json: { resultado: { ok: true, id_reserva: 100, id_pre_reserva: 42, id_huesped: 9 } }, nodes: nD }));
  ok(o.envelope.ok === true && o.envelope.data.id_reserva === 100 && o.envelope.data.idempotent_match === false, 'router3 ok -> {ok,data,idempotent_match:false}');
  o = await J(runCode('router4_recheck', { $json: { n: 1, id_reserva: 100, id_pre_reserva: 42, id_huesped: 9 }, nodes: nD }));
  ok(o.envelope.ok === true && o.envelope.data.idempotent_match === true, 'router4 n=1 -> {ok,data,idempotent_match:true}');

  // ---------- (6) Ajuste 2 (router2) ----------
  console.log('\n== (6) router2_pago (ajuste 2) ==');
  o = await J(runCode('router2_pago', { $json: { n: 0, resultado_registro: { ok: true, estado: 'confirmado' } }, nodes: nD }));
  ok(o.continuar === true && JSON.parse(o.payload3).id_pre_reserva === 42, 'n=0 ok+confirmado+sin-warning -> seguir (payload3 con id_pre_reserva)');
  o = await J(runCode('router2_pago', { $json: { n: 0, resultado_registro: { ok: true, estado: 'en_revision' } }, nodes: nD }));
  ok(o.envelope.error.code === 'estado_incierto', "n=0 estado!='confirmado' -> incierto");
  o = await J(runCode('router2_pago', { $json: { n: 0, resultado_registro: { ok: true, estado: 'confirmado', warning: 'prereserva_no_activa' } }, nodes: nD }));
  ok(o.envelope.error.code === 'estado_incierto', 'n=0 con warning -> incierto');
  o = await J(runCode('router2_pago', { $json: { n: 1, n_conf: 1, id_pago_conf: 5 }, nodes: nD }));
  ok(o.continuar === true, 'n=1 & n_conf=1 -> reusar');
  o = await J(runCode('router2_pago', { $json: { n: 1, n_conf: 0 }, nodes: nD }));
  ok(o.envelope.error.code === 'estado_incierto', 'n=1 & n_conf=0 -> incierto');
  o = await J(runCode('router2_pago', { $json: { n: 2, n_conf: 2 }, nodes: nD }));
  ok(o.envelope.error.code === 'estado_incierto', 'n>1 -> incierto');

  // ---------- (7) Ajuste 3 (router3/router4) ----------
  console.log('\n== (7) router3/router4 (ajuste 3) ==');
  o = await J(runCode('router3_confirmar', { $json: { resultado: { ok: false, error: 'estado_invalido', estado_actual: 'convertida' } }, nodes: nD }));
  ok(o.recheck === true && o.envelope === undefined, 'estado_invalido+convertida -> recheck');
  o = await J(runCode('router3_confirmar', { $json: { resultado: { ok: false, error: 'conflicto_al_confirmar' } }, nodes: nD }));
  ok(o.recheck === false && o.envelope.error.code === 'conflicto', 'conflicto_al_confirmar -> conflicto');
  o = await J(runCode('router3_confirmar', { $json: { resultado: { ok: false, error: 'estado_invalido', estado_actual: 'vencida' } }, nodes: nD }));
  ok(o.envelope.error.code === 'estado_incierto', 'estado_invalido no-convertida -> incierto');
  o = await J(runCode('router4_recheck', { $json: { n: 0 }, nodes: nD }));
  ok(o.envelope.error.code === 'estado_incierto', 'router4 n=0 -> incierto');
  o = await J(runCode('router4_recheck', { $json: { n: 2 }, nodes: nD }));
  ok(o.envelope.error.code === 'estado_incierto', 'router4 n>1 -> incierto');

  // ---------- (8) render ----------
  console.log('\n== (8) Code: render ==');
  o = await J(runCode('Code: render', { $json: { recheck: false, envelope: { ok: true, data: { id_reserva: 1 } } } }));
  ok(o.ok === true && o.data.id_reserva === 1 && !('envelope' in o) && !('recheck' in o), 'extrae envelope de router');
  o = await J(runCode('Code: render', { $json: { ok: false, error: { code: 'firma_invalida' } } }));
  ok(o.ok === false && o.error.code === 'firma_invalida', 'pasa rechazo de verificar_acceso');

  console.log('\n' + '='.repeat(50));
  console.log(fail === 0 ? 'TODOS LOS TESTS OK' : ('FALLARON ' + fail + ' TESTS'));
  process.exit(fail === 0 ? 0 : 1);
})();
