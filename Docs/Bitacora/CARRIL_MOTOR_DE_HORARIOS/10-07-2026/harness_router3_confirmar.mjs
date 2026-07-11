// harness_router3_confirmar.mjs
// Ejecuta el jsCode REAL de router3_confirmar del template A07 parcheado, con mocks n8n
// ($json, $('Code: derivar'), $('router1_crear')). Cubre el camino que crear_prereserva
// normalmente NO alcanza (aislado).
//
//   node harness_router3_confirmar.mjs [ruta_template]
import { readFileSync } from 'node:fs';

const RUTA = process.argv[2] ||
  new URL('../vita-delta-reservas/Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json', import.meta.url).pathname;

const tpl = JSON.parse(readFileSync(RUTA, 'utf-8'));
const node = tpl.nodes.find(n => n.name === 'router3_confirmar');
if (!node) { console.error('NO se encontro router3_confirmar'); process.exit(1); }
const jsCode = node.parameters.jsCode;

const D = { sev: 'sev-1', idem: 'idem-1' };
const mk$ = () => (nombre) => {
  if (nombre === 'Code: derivar') return { first: () => ({ json: D }) };
  if (nombre === 'router1_crear') return { first: () => ({ json: { id_pre: 'PRE-123' } }) };
  throw new Error('mock $ inesperado: ' + nombre);
};

function correr(resultado) {
  const fn = new Function('$json', '$', jsCode);
  const out = fn({ resultado }, mk$());
  return out[0].json;
}

let pass = 0, fail = 0;
function check(nombre, cond, detalle) {
  if (cond) { pass++; console.log('  PASS ' + nombre); }
  else { fail++; console.log('  FAIL ' + nombre + (detalle ? '  -> ' + detalle : '')); }
}

const MSG_IN = 'gap_checkin: El check-in queda demasiado cerca del checkout anterior. Elegí un horario de entrada más tarde.';
const MSG_OUT = 'gap_checkout: El check-out queda demasiado cerca del check-in posterior. Elegí un horario de salida más temprano.';

console.log('== Harness C: router3_confirmar ==');

// 1) gap check-in -> conflicto + gap_checkin:
let r = correr({ ok: false, error: 'checkin_pisa_checkout_anterior' });
check('gap check-in: recheck=false', r.recheck === false, JSON.stringify(r));
check('gap check-in: code=conflicto', r.envelope.error.code === 'conflicto', JSON.stringify(r.envelope));
check('gap check-in: message exacto (prefijo gap_checkin:)', r.envelope.error.message === MSG_IN, r.envelope.error.message);
check('gap check-in: detail=null', r.envelope.error.detail === null);

// 2) gap check-out -> conflicto + gap_checkout:
r = correr({ ok: false, error: 'checkout_pisa_checkin_posterior' });
check('gap check-out: code=conflicto', r.envelope.error.code === 'conflicto', JSON.stringify(r.envelope));
check('gap check-out: message exacto (prefijo gap_checkout:)', r.envelope.error.message === MSG_OUT, r.envelope.error.message);

// 3) no_disponible INTACTO -> conflicto historico
r = correr({ ok: false, error: 'no_disponible' });
check('no_disponible: code=conflicto', r.envelope.error.code === 'conflicto');
check('no_disponible: message historico', r.envelope.error.message === 'conflicto de disponibilidad al confirmar', r.envelope.error.message);

// 4) conflicto_al_confirmar INTACTO -> conflicto
r = correr({ ok: false, error: 'conflicto_al_confirmar' });
check('conflicto_al_confirmar: code=conflicto', r.envelope.error.code === 'conflicto');
check('conflicto_al_confirmar: message historico', r.envelope.error.message === 'conflicto de disponibilidad al confirmar', r.envelope.error.message);

// 5) estado_invalido + convertida -> recheck:true
r = correr({ ok: false, error: 'estado_invalido', estado_actual: 'convertida' });
check('estado_invalido+convertida: recheck=true', r.recheck === true, JSON.stringify(r));
check('estado_invalido+convertida: sin envelope', r.envelope === undefined);

// 6) error desconocido -> estado_incierto
r = correr({ ok: false, error: 'algo_desconocido' });
check('desconocido: code=estado_incierto', r.envelope.error.code === 'estado_incierto', JSON.stringify(r.envelope));
check('desconocido: detail conserva id_pre_reserva', r.envelope.error.detail.ids_creados.id_pre_reserva === 'PRE-123');

// 7) exito -> envelope ok:true data
r = correr({ ok: true, id_reserva: 'R-1', id_pre_reserva: 'PRE-123', id_huesped: 'H-1' });
check('exito: recheck=false', r.recheck === false, JSON.stringify(r));
check('exito: envelope.ok=true', r.envelope.ok === true);
check('exito: data.id_reserva', r.envelope.data.id_reserva === 'R-1');
check('exito: idempotent_match=false', r.envelope.data.idempotent_match === false);

console.log(`\nC total: ${pass} PASS / ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
