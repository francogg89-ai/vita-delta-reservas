// harness_router1_crear.mjs
// Ejecuta el jsCode REAL de router1_crear del template A07 parcheado, con mocks n8n
// ($json, $('Code: derivar')). No reimplementa logica: extrae el codigo del artefacto.
//
//   node harness_router1_crear.mjs [ruta_template]
//
// Default: ../vita-delta-reservas/Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json
import { readFileSync } from 'node:fs';

const RUTA = process.argv[2] ||
  new URL('../vita-delta-reservas/Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json', import.meta.url).pathname;

const tpl = JSON.parse(readFileSync(RUTA, 'utf-8'));
const node = tpl.nodes.find(n => n.name === 'router1_crear');
if (!node) { console.error('NO se encontro router1_crear'); process.exit(1); }
const jsCode = node.parameters.jsCode;

// Mock de derivar (usado en ramas success y unique_violation).
const D = { sev: 'sev-1', idem: 'idem-1', payload2_base: { cabana: 'Tokio', noches: 2 } };
const mk$ = () => (nombre) => {
  if (nombre === 'Code: derivar') return { first: () => ({ json: D }) };
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

console.log('== Harness B: router1_crear ==');

// 1) gap check-in -> conflicto + gap_checkin:
let r = correr({ ok: false, error: 'checkin_pisa_checkout_anterior' });
check('gap check-in: continuar=false', r.continuar === false, JSON.stringify(r));
check('gap check-in: code=conflicto', r.envelope.error.code === 'conflicto', JSON.stringify(r.envelope));
check('gap check-in: message exacto (prefijo gap_checkin:)', r.envelope.error.message === MSG_IN, r.envelope.error.message);
check('gap check-in: detail=null', r.envelope.error.detail === null);

// 2) gap check-out -> conflicto + gap_checkout:
r = correr({ ok: false, error: 'checkout_pisa_checkin_posterior' });
check('gap check-out: code=conflicto', r.envelope.error.code === 'conflicto', JSON.stringify(r.envelope));
check('gap check-out: message exacto (prefijo gap_checkout:)', r.envelope.error.message === MSG_OUT, r.envelope.error.message);

// 3) no_disponible INTACTO
r = correr({ ok: false, error: 'no_disponible' });
check('no_disponible: code=conflicto', r.envelope.error.code === 'conflicto');
check('no_disponible: message historico intacto', r.envelope.error.message === 'sin disponibilidad en el rango', r.envelope.error.message);

// 4) fecha_in_pasada INTACTO -> payload_invalido
r = correr({ ok: false, error: 'fecha_in_pasada' });
check('fecha_in_pasada: code=payload_invalido', r.envelope.error.code === 'payload_invalido', JSON.stringify(r.envelope));
check('fecha_in_pasada: message intacto', r.envelope.error.message === 'datos de reserva rechazados: fecha_in_pasada', r.envelope.error.message);

// 5) excede_capacidad INTACTO -> payload_invalido
r = correr({ ok: false, error: 'excede_capacidad' });
check('excede_capacidad: code=payload_invalido', r.envelope.error.code === 'payload_invalido', JSON.stringify(r.envelope));

// 6) error desconocido -> error_interno
r = correr({ ok: false, error: 'algo_totalmente_desconocido' });
check('desconocido: code=error_interno', r.envelope.error.code === 'error_interno', JSON.stringify(r.envelope));

// 7) exito -> conserva pg2_args
r = correr({ ok: true, id_pre_reserva: 'PRE-123' });
check('exito: continuar=true', r.continuar === true, JSON.stringify(r));
check('exito: id_pre propagado', r.id_pre === 'PRE-123');
check('exito: pg2_args presente (string)', typeof r.pg2_args === 'string' && r.pg2_args.length > 0);
try {
  const args = JSON.parse(r.pg2_args);
  check('exito: pg2_args.payload2 incluye id_pre_reserva', args.payload2 && args.payload2.id_pre_reserva === 'PRE-123', JSON.stringify(args));
  check('exito: pg2_args conserva idem/sev', args.idem === 'idem-1' && args.sev === 'sev-1');
} catch (e) { check('exito: pg2_args parseable', false, String(e)); }

console.log(`\nB total: ${pass} PASS / ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
