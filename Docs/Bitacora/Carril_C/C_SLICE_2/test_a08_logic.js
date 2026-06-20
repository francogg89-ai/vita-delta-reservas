const crypto = require('crypto');
const fs = require('fs');
const wf = JSON.parse(fs.readFileSync('portal-a08-crear-bloqueo__TEST__TEMPLATE.json','utf8'));
const validarCode = wf.nodes.find(n=>n.name==='validar_firma_ts_rol').parameters.jsCode;
const derivarCode = wf.nodes.find(n=>n.name==='Code: derivar').parameters.jsCode;
const SECRET = 'test_secret_a08_0123456789abcdef';

function runValidar(bodyObj, opts={}) {
  const bodyStr = JSON.stringify(bodyObj);
  const sig = opts.badSig ? 'sha256=deadbeef'
            : 'sha256=' + crypto.createHmac('sha256', SECRET).update(Buffer.from(bodyStr,'utf8')).digest('hex');
  const rawBody = opts.noBody ? undefined : bodyStr;
  const $input = { first: () => ({ json: { rawBody, headers: { 'x-vita-signature': sig } } }) };
  const $vars = { VITA_HMAC_SECRET: SECRET };
  const ctx = { helpers: { getBinaryDataBuffer: async () => Buffer.from(bodyStr,'utf8') } };
  const factory = new Function('$input','$vars','require','return (async function(){\n'+validarCode+'\n});');
  return factory($input,$vars,require).call(ctx).then(r => r[0].json);
}
function runDerivar(V) {
  const $ = () => ({ first: () => ({ json: V }) });
  const factory = new Function('$','require','return (async function(){\n'+derivarCode+'\n})();');
  return factory($, require).then(r => r[0].json);
}
const body = (payloadOver={}, over={}) => ({
  action: over.action ?? 'bloqueo.crear_manual', rol: over.rol ?? 'vicky', actor: over.actor ?? 'vicky',
  ambiente_esperado: 'test', ts: over.ts ?? Date.now(), nonce: 'x',
  payload: Object.assign({ id_cabana:1, fecha_desde:'2027-03-01', fecha_hasta:'2027-03-05', motivo:'mantenimiento' }, payloadOver)
});
const noCab = () => { const p = { fecha_desde:'2027-03-01', fecha_hasta:'2027-03-05', motivo:'mantenimiento' }; return { action:'bloqueo.crear_manual', rol:'vicky', actor:'vicky', ambiente_esperado:'test', ts:Date.now(), nonce:'x', payload:p }; };

(async () => {
  let fail = 0;
  const ok = (c,m) => { console.log((c?'  [OK] ':'  [X]  ')+m); if(!c) fail++; };
  const ex = async (b,o,expFirma,expMotivo,label) => { const r = await runValidar(b,o); ok(r.ok_firma===expFirma && (expFirma||r.motivo===expMotivo), label+' -> ok_firma='+r.ok_firma+(r.motivo?(' motivo='+r.motivo):'')); return r; };

  console.log('== validar_firma_ts_rol A08 ==');
  const rv = await ex(body(), {}, true, null, 'valido');
  ok(rv.payload && rv.payload.id_cabana===1 && rv.payload.descripcion===null, '   payloadWL correcto (descripcion null)');
  await ex(noCab(), {}, false, 'payload_invalido', 'id_cabana AUSENTE (obligatorio)');
  await ex(body({id_cabana:null}), {}, false, 'payload_invalido', 'id_cabana null');
  await ex(body({id_cabana:0}), {}, false, 'payload_invalido', 'id_cabana 0');
  await ex(body({id_cabana:-1}), {}, false, 'payload_invalido', 'id_cabana negativo');
  await ex(body({id_cabana:1.5}), {}, false, 'payload_invalido', 'id_cabana no entero');
  await ex(body({fecha_desde:'2027-02-30'}), {}, false, 'payload_invalido', 'fecha 2027-02-30');
  await ex(body({fecha_hasta:'2027-03-01'}), {}, false, 'payload_invalido', 'fecha_hasta<=desde');
  await ex(body({motivo:'xxx'}), {}, false, 'payload_invalido', 'motivo invalido');
  await ex(body({motivo:'tormenta'}), {}, true, null, 'motivo tormenta (valido)');
  await ex(body({foo:'x'}), {}, false, 'payload_invalido', 'clave extra (reject-unknown)');
  const rd = await ex(body({descripcion:'pintura'}), {}, true, null, 'descripcion valida');
  ok(rd.payload.descripcion==='pintura', '   descripcion en payloadWL');
  await ex(body({descripcion:123}), {}, false, 'payload_invalido', 'descripcion no-string');
  await ex(body({}, {rol:'jenny'}), {}, false, 'rol_no_permitido', 'rol jenny');
  await ex(body({}, {action:'otra.cosa'}), {}, false, 'accion_desconocida', 'action ajena');
  await ex(body({}, {actor:'intruso'}), {}, false, 'payload_invalido', 'actor fuera de enum');
  await ex(body(), {badSig:true}, false, 'firma_invalida', 'firma mala');
  await ex(body({}, {ts: Date.now()-999999}), {}, false, 'ts_fuera_de_ventana', 'ts viejo');

  console.log('== derivar A08 (source_event deterministico, sin idem) ==');
  const V = { payload:{ id_cabana:1, fecha_desde:'2027-03-01', fecha_hasta:'2027-03-05', motivo:'mantenimiento', descripcion:null }, actor:'vicky' };
  const d = await runDerivar(V);
  ok(/^portal_test_a08_cab1_2027-03-01_2027-03-05_[a-f0-9]{12}$/.test(d.source_event), 'source_event formato: '+d.source_event);
  const p1 = JSON.parse(d.payload1);
  ok(p1.creado_por==='vicky' && p1.source_event===d.source_event && p1.id_cabana===1 && p1.motivo==='mantenimiento' && !('idempotency_key' in p1), 'payload1 correcto (creado_por=actor, sin idempotency_key)');
  const d2 = await runDerivar(V);
  ok(d2.source_event===d.source_event, 'source_event determinístico (mismo input -> mismo sev)');

  console.log('\n'+(fail===0?'TODOS OK':('FALLARON '+fail)));
  process.exit(fail===0?0:1);
})();
