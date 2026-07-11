// harness_texto_error_reserva.mjs
// Ejecuta la funcion REAL textoErrorReserva() extraida del CrearReserva.tsx parcheado
// (se le quita solo el tipado TS y se le inyecta un mock de mensajeUsuario). No reimplementa
// la logica: valida el artefacto real.
//
//   node harness_texto_error_reserva.mjs [ruta_tsx]
import { readFileSync } from 'node:fs';

const RUTA = process.argv[2] ||
  new URL('../vita-delta-reservas/Apps/portal-operativo/src/screens/CrearReserva.tsx', import.meta.url).pathname;

const src = readFileSync(RUTA, 'utf-8');

// Extraer el cuerpo de textoErrorReserva por brace-matching desde su primera '{'.
const firma = 'function textoErrorReserva(error: PortalApiError): string {';
const i = src.indexOf(firma);
if (i < 0) { console.error('NO se encontro textoErrorReserva'); process.exit(1); }
let j = i + firma.length - 1; // posicion de la '{' de apertura
let depth = 0, fin = -1;
for (let k = j; k < src.length; k++) {
  if (src[k] === '{') depth++;
  else if (src[k] === '}') { depth--; if (depth === 0) { fin = k; break; } }
}
if (fin < 0) { console.error('no se pudo cerrar el bloque'); process.exit(1); }
const body = src.slice(j + 1, fin); // contenido entre llaves

// mock de mensajeUsuario (fallback para codigos no especiales)
const mensajeUsuario = (error) => 'FALLBACK_MENSAJE_USUARIO:' + error.code;
const textoErrorReserva = new Function('error', 'mensajeUsuario',
  body + '\n//# sourceURL=textoErrorReserva').bind(null);
const run = (error) => textoErrorReserva(error, mensajeUsuario);

let pass = 0, fail = 0;
function check(nombre, cond, detalle) {
  if (cond) { pass++; console.log('  PASS ' + nombre); }
  else { fail++; console.log('  FAIL ' + nombre + (detalle ? '  -> ' + detalle : '')); }
}

const HIST = 'Sin disponibilidad en ese rango (se solapa con una reserva, pre-reserva o bloqueo).';
const MSG_IN = 'gap_checkin: El check-in queda demasiado cerca del checkout anterior. Elegí un horario de entrada más tarde.';
const MSG_OUT = 'gap_checkout: El check-out queda demasiado cerca del check-in posterior. Elegí un horario de salida más temprano.';
const HUM_IN = 'El check-in queda demasiado cerca del checkout anterior. Elegí un horario de entrada más tarde.';
const HUM_OUT = 'El check-out queda demasiado cerca del check-in posterior. Elegí un horario de salida más temprano.';

console.log('== Harness Frontend: textoErrorReserva ==');

// 1) gap check-in -> SOLO frase humana (sin prefijo ni codigo crudo)
let t = run({ code: 'conflicto', message: MSG_IN });
check('gap check-in: frase humana exacta', t === HUM_IN, t);
check('gap check-in: NO muestra prefijo gap_checkin:', !t.includes('gap_checkin'), t);
check('gap check-in: NO muestra codigo crudo SP', !t.includes('checkin_pisa_checkout_anterior'), t);

// 2) gap check-out -> SOLO frase humana
t = run({ code: 'conflicto', message: MSG_OUT });
check('gap check-out: frase humana exacta', t === HUM_OUT, t);
check('gap check-out: NO muestra prefijo gap_checkout:', !t.includes('gap_checkout'), t);
check('gap check-out: NO muestra codigo crudo SP', !t.includes('checkout_pisa_checkin_posterior'), t);

// 3) no_disponible (message que envia A07 router1) -> texto historico
t = run({ code: 'conflicto', message: 'sin disponibilidad en el rango' });
check('no_disponible: texto historico', t === HIST, t);

// 4) conflicto historico de confirmacion -> texto historico
t = run({ code: 'conflicto', message: 'conflicto de disponibilidad al confirmar' });
check('conflicto confirmar: texto historico', t === HIST, t);

// 5) payload_invalido/fecha_in_pasada INTACTO
t = run({ code: 'payload_invalido', message: 'datos de reserva rechazados: fecha_in_pasada' });
check('fecha_in_pasada: mensaje intacto', t === 'No podes crear una reserva con check-in anterior a hoy.', t);

// 6) otro codigo -> fallback mensajeUsuario intacto
t = run({ code: 'estado_incierto', message: 'x' });
check('otro codigo: cae a mensajeUsuario', t === 'FALLBACK_MENSAJE_USUARIO:estado_incierto', t);

console.log(`\nFrontend total: ${pass} PASS / ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
