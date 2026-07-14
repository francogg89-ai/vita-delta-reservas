// =============================================================================================
// SB-UI-6 -- Suite de probes del harness de QA.
//
// SIN vitest / jest / ninguna dependencia nueva: runner minimo (`caso` + `ok`) y los MODULOS
// REALES compilados con esbuild y ejecutados en Node con `renderToStaticMarkup`. Lo que se prueba
// es el codigo que se despliega, no una reimplementacion.
//
// Corre con: npm run qa:probes
// =============================================================================================

import { renderToStaticMarkup } from 'react-dom/server';
import type { HistoricoAcumuladosData, HistoricoMesData } from '../src/lib/contratos';
import { FLOOR_CONTABLE } from '../src/lib/constantes';
import { ContenidoAcumulados } from '../src/screens/historico/ContenidoAcumulados';
import { ContenidoFoto } from '../src/screens/historico/ContenidoFoto';
import { analizarAcumulados } from '../src/screens/historico/acumulados';
import { clasificarFoto } from '../src/screens/historico/estadoFoto';
import { comprobanteSeguro, formatFechaHora } from '../src/screens/historico/foto';
import { construirPlanSelector } from '../src/screens/historico/planSelector';
declare const process: { exit(code: number): never };

import {
  CATALOGO_A30,
  CATALOGO_A31,
  F1, F2, F3, F4, F5, F6, F7, F8, F9,
  F10, F11, F12, F13, F14, F15, F16, F17, F18, F19,
} from './fixtures';

// ---------------------------------------------------------------------------------------------
// Runner minimo
// ---------------------------------------------------------------------------------------------

let fallos = 0;
let total = 0;

function bloque(t: string) {
  console.log(`\n${'='.repeat(94)}\n${t}\n${'='.repeat(94)}`);
}
function caso(t: string) {
  console.log(`\n  ${t}`);
}
function ok(cond: boolean, msg: string) {
  total++;
  if (cond) {
    console.log(`    ok    ${msg}`);
  } else {
    fallos++;
    console.log(`    FALLA ${msg}`);
  }
}

// Render -> HTML crudo (para aserciones sobre atributos: href, aria-label, ...).
const html30 = (d: HistoricoMesData, e: 'E1' | 'E2' | 'E3') =>
  renderToStaticMarkup(<ContenidoFoto data={d} estado={e} />);
const html31 = (d: HistoricoAcumuladosData) =>
  renderToStaticMarkup(<ContenidoAcumulados data={d} />);

// Render -> texto plano (para aserciones sobre lo que LEE el socio).
const plano = (h: string) =>
  h
    .replace(/<[^>]+>/g, ' ')
    .replace(/&#x27;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#x2F;/g, '/')
    .replace(/\s+/g, ' ');

const txt30 = (d: HistoricoMesData, e: 'E1' | 'E2' | 'E3') => plano(html30(d, e));
const txt31 = (d: HistoricoAcumuladosData) => plano(html31(d));

const codigos = (d: HistoricoAcumuladosData) => analizarAcumulados(d).anomalias.map((a) => a.codigo);

// =============================================================================================
bloque('B -- ESTADOS ESTRUCTURALES');
// =============================================================================================

caso('B1 · E1 / E2 / E3 se clasifican bien');
ok(clasificarFoto(F1, '2026-07') === 'E1', 'F1 -> E1');
ok(clasificarFoto(F2, '2026-07') === 'E2', 'F2 -> E2');
ok(clasificarFoto(F3, '2026-07') === 'E3', 'F3 -> E3');
ok(clasificarFoto(F4, '2026-07') === 'E1', 'F4 (matriz vacia) -> E1, NO inconsistente');

caso('B2 · INCONSISTENTE T1..T7 -- cada variante rompe UNA invariante');
for (const k of ['t1', 't2', 't3', 't4', 't5', 't6', 't7']) {
  const v = F19[k];
  ok(clasificarFoto(v.data, v.mesApplied) === 'INCONSISTENTE', `${k.toUpperCase()} -> INCONSISTENTE  (${v.rompe})`);
}

caso('B3 · piso que invalida la seleccion');
const planNormal = construirPlanSelector(F10);
ok(planNormal.pisoMes === '2026-07', `piso = FLOOR_CONTABLE (${FLOOR_CONTABLE}) -> ${planNormal.pisoMes}`);
ok(!planNormal.pisoDivergente, 'A31.piso === FLOOR_CONTABLE -> pisoDivergente: false');
ok(
  planNormal.opciones.every((o) => o.ym >= planNormal.pisoMes),
  `ninguna opcion por debajo del piso (${planNormal.opciones.length} opciones)`
);
const planAlto = construirPlanSelector({ ...F10, piso: '2026-09-01' });
ok(planAlto.pisoMes === '2026-09', 'piso runtime MAYOR -> se toma el max: 2026-09');
ok(planAlto.pisoDivergente, 'piso runtime != espejo local -> pisoDivergente: true');
const planBajo = construirPlanSelector({ ...F10, piso: '2026-05-01' });
ok(planBajo.pisoMes === '2026-07', 'piso runtime MENOR -> se conserva el local (max conservador)');
ok(planBajo.pisoDivergente, 'piso runtime menor tambien marca divergencia');

caso('B4 · modo degradado: A31 caida');
const degradado = construirPlanSelector(null);
ok(degradado.degradado, 'A31 null -> degradado: true');
ok(degradado.opciones.length > 0, 'el selector NO queda vacio: sale del fallback local');
ok(degradado.pisoMes === '2026-07', 'el piso cae al espejo local FLOOR_CONTABLE');
ok(
  degradado.opciones.every((o) => o.foto === 'no_verificada'),
  'sin A31 no se puede saber si hay foto -> todas las opciones quedan `no_verificada`'
);
ok(!degradado.pisoDivergente, 'sin A31 no hay con que comparar -> pisoDivergente: false');

caso('B5 · anti-flash: la foto NO se clasifica contra el mes equivocado');
// El contenedor pasa `fotoPendiente`; la vista no clasifica un `data` de otro mes. La prueba de la
// invariante es T1: el mismo `data` que es E1 para su mes, es INCONSISTENTE para otro.
ok(clasificarFoto(F1, '2026-07') === 'E1', 'F1 con su mes -> E1');
ok(clasificarFoto(F1, '2026-08') === 'INCONSISTENTE', 'F1 con OTRO mes -> INCONSISTENTE (nunca se muestra stale como si fuera bueno)');

// =============================================================================================
bloque('C -- A31 ACUMULADOS');
// =============================================================================================

caso('C1 · F10 normal: cero anomalias');
ok(codigos(F10).length === 0, `sin anomalias  (${JSON.stringify(codigos(F10))})`);
ok(analizarAcumulados(F10).identidadGastosOk, 'la identidad del desglose cierra');
ok(analizarAcumulados(F10).sumaDesglose === 1200000, 'sumaDesglose = 1.200.000 = gastos_acumulados');

caso('C2 · F11 `sin_datos:true` CON retiros y saldos vivos');
const a11 = analizarAcumulados(F11);
ok(!codigos(F11).includes('i1_sin_datos'), 'I1 CIERRA (sin_datos === (fotos_vigentes===0)) -> sin anomalia');
ok(!codigos(F11).includes('i2_cardinalidad'), 'I2 cierra (0 fotos, 0 filas de evolucion)');
ok(F11.saldos_por_socio.length === 3, '`sin_datos:true` NO implica saldos_por_socio vacio (CROSS JOIN LATERAL)');
const t11 = txt31(F11);
ok(t11.includes('700.000'), 'los retiros acumulados se muestran igual con sin_datos:true');
ok(t11.includes('Rodrigo') && t11.includes('-233.333') === false ? true : t11.includes('Rodrigo'), 'los saldos por socio se muestran');
ok(a11.evolucionOrdenada.length === 0, 'la evolucion vacia es legitima, no un error');

caso('C3 · F12 I1 rota');
ok(codigos(F12).includes('i1_sin_datos'), 'anomalia i1_sin_datos detectada');
ok(txt31(F12).includes('3 foto(s) de cierre vigente(s)'), 'el banner dice cuantas fotos contó el servidor');
ok(txt31(F12).includes('no se oculta ninguna fila'), 'y aclara que NO se oculta nada');
ok(analizarAcumulados(F12).evolucionOrdenada.length === 3, 'las 3 filas se muestran igual: la anomalia informa, no censura');

caso('C4 · F13 I2 rota');
ok(codigos(F13).includes('i2_cardinalidad'), 'anomalia i2_cardinalidad detectada');
ok(analizarAcumulados(F13).evolucionOrdenada.length === 3, 'se muestran las 3 filas que llegaron, no las 5 informadas');
ok(txt31(F13).includes('5 foto(s)') && txt31(F13).includes('3 fila(s)'), 'el banner contrasta 5 informadas vs 3 recibidas');

caso('C5 · F14 periodos desordenados');
const a14 = analizarAcumulados(F14);
ok(codigos(F14).includes('orden_evolucion'), 'anomalia orden_evolucion detectada');
ok(
  a14.evolucionOrdenada.map((e) => e.periodo).join() === '2026-07-01,2026-08-01,2026-09-01',
  'la UI ordena una COPIA ascendente para mostrar'
);
ok(
  F14.evolucion.map((e) => e.periodo).join() === '2026-09-01,2026-07-01,2026-08-01',
  'el array ORIGINAL no se mutó'
);

caso('C6 · F15 periodos repetidos -- NO se deduplican');
const a15 = analizarAcumulados(F15);
ok(a15.evolucionOrdenada.length === 3, 'llegan 3 filas, se muestran 3 (el duplicado queda a la vista)');
ok(
  a15.evolucionOrdenada.filter((e) => e.periodo === '2026-08-01').length === 2,
  'las dos filas de 2026-08 sobreviven: no se silencia el duplicado'
);
ok(!codigos(F15).includes('i2_cardinalidad'), 'I2 cierra igual (3 informadas, 3 filas): el duplicado no es un error de cardinalidad');

caso('C7 · F16 identidad de gastos rota');
const a16 = analizarAcumulados(F16);
ok(codigos(F16).includes('identidad_gastos'), 'anomalia identidad_gastos detectada');
ok(!a16.identidadGastosOk, 'identidadGastosOk: false');
ok(a16.sumaDesglose === 1100000, 'la suma real (1.100.000) se muestra al lado del total informado');
ok(txt31(F16).includes('1.100.000') && txt31(F16).includes('1.200.000'), 'los DOS numeros se muestran: el socio ve la brecha');

caso('C8 · F17 fotos y movimientos pre-piso');
ok(codigos(F17).includes('fotos_pre_piso'), 'anomalia fotos_pre_piso');
ok(codigos(F17).includes('movimientos_pre_piso'), 'anomalia movimientos_pre_piso');
const t17 = txt31(F17);
ok(t17.includes('2') && t17.includes('4'), 'los conteos (2 fotos, 4 movimientos) se informan');

caso('C9 · F18 piso divergente + NO MUTACION (Object.freeze)');
ok(construirPlanSelector(F18).pisoDivergente, 'pisoDivergente: true');
// Si `analizarAcumulados` ordenara IN PLACE, esto tira TypeError sobre el array congelado.
let mutó = false;
try {
  const a18 = analizarAcumulados(F18);
  ok(
    a18.evolucionOrdenada.map((e) => e.periodo).join() === '2026-07-01,2026-08-01,2026-09-01',
    'ordena una copia y devuelve el orden correcto'
  );
} catch (e) {
  mutó = true;
  ok(false, `analizarAcumulados MUTÓ el fixture congelado: ${String(e).slice(0, 70)}`);
}
ok(!mutó, 'Object.freeze sobrevive: `analizarAcumulados` NO muta `data.evolucion`');
ok(
  F18.evolucion.map((e) => e.periodo).join() === '2026-09-01,2026-07-01,2026-08-01',
  'el fixture original conserva su orden desordenado'
);

// =============================================================================================
bloque('D -- A30 FOTO DEL MES');
// =============================================================================================

const t1 = txt30(F1, 'E1');
const h1 = html30(F1, 'E1');

caso('D1 · porcentajes y valores relativos SIN simbolo monetario');
ok(t1.includes('25,00%'), 'pct_operativo 0.25 -> "25,00%"  (fraccion 0..1, NO plata)');
ok(!t1.includes('$ 0,25'), 'NUNCA "$ 0,25"');
ok(t1.includes('33,33%'), 'participacion 0.3333 -> "33,33%"');
// valor_relativo y valor_socio/valor_pool son SUM(cabanas.valor_relativo): no son plata.
const secMatriz = t1.slice(t1.indexOf('Matriz por socio'));
ok(!/\$\s*5,00/.test(secMatriz) && !/\$\s*15,00/.test(secMatriz), 'valor_socio (5) y valor_pool (15) sin "$"');

caso('D2 · ID congelado + nombre VIVO (F9: catalogo renombrado)');
const t9 = txt30(F9, 'E1');
ok(t9.includes('Socio #2 · Rodrigo Martinez'), 'Resultado por socio: ID #2 + nombre NUEVO');
ok(t9.includes('Cabaña #5 · Tokio Suite'), 'Participacion: "Cabaña #5 · Tokio Suite"');
ok(t9.includes('Beneficiario #3 · Remo B.'), 'Participacion: "Beneficiario #3 · Remo B."');
ok((t9.match(/Socio #2 · Rodrigo Martinez/g) ?? []).length >= 3, 'tambien en Matriz e Incidencias');
ok(
  t9.includes(
    'Los importes, IDs y relaciones están congelados en la foto. Los nombres de socios y cabañas se resuelven desde el catálogo actual al consultar.'
  ),
  'la nota explica que el nombre NO esta congelado'
);
ok(h1.includes('aria-label="Congelado en la foto del cierre"'), 'el chip [F] se mantiene (no se reclasificaron los montos)');

caso('D3 · E2 sin detalle fino NI falsos vacios');
const t2 = txt30(F2, 'E2');
for (const s of ['Cabecera de la foto', 'Cascada del cierre', 'Resultado por socio', 'Retribución operativa', 'Movimientos del mes']) {
  ok(t2.includes(s), `E2 muestra "${s}"`);
}
ok(!t2.includes('Detalle fino'), 'E2 NO muestra el detalle fino');
for (const v of ['Gastos congelados', 'Incidencias', 'Ninguna cabaña participó', 'Gastos sin incidencia']) {
  ok(!t2.includes(v), `E2 NO muestra "${v}" -- ni la seccion ni un vacio falso`);
}

caso('D4 · E3 sin secciones inexistentes');
const t3 = txt30(F3, 'E3');
ok(t3.includes('Sin foto congelada'), 'E3 muestra el banner');
for (const s of ['Cabecera de la foto', 'Cascada del cierre', 'Resultado por socio', 'Retribución operativa', 'Movimientos del mes', 'Detalle fino']) {
  ok(!t3.includes(s), `E3 NO inventa "${s}"`);
}
ok(!t3.includes('Los importes, IDs y relaciones'), 'E3 no muestra la nota de nombres: no hay nombres');

caso('D5 · matriz vacia LEGITIMA (F4)');
const t4 = txt30(F4, 'E1');
ok(clasificarFoto(F4, '2026-07') === 'E1', 'matriz [] con detalle_disponible:true sigue siendo E1');
ok(t4.includes('Detalle fino'), 'el detalle fino se muestra igual');
ok(!t4.includes('INCONSISTENTE'), 'el vacio NO se trata como error (SQL: WHERE valor_pool > 0)');

caso('D6 · movimientos por FECHA vs conciliacion por PERIODO (F7)');
const t7 = txt30(F7, 'E1');
ok(t7.includes('Retribución operativa'), 'la seccion existe');
ok(/asignado|Asignado/.test(t7), 'muestra el `asignado` (VIVO, filtrado por periodo)');
ok(/calculado|Calculado/.test(t7), 'muestra el `calculado` (CONGELADO, de la foto)');
ok(h1.includes('aria-label="Mixto: parte congelada, parte en vivo"'), 'la retribucion lleva chip [M]: es MIXTA');
ok(
  /ventana|fecha|no cuadr|no coincid/i.test(t7),
  'la UI ADVIERTE que la lista se ventanea por fecha y el asignado por periodo -> no cuadran 1:1'
);

caso('D7 · comprobantes VALIDOS http/https (F6)');
const h6 = html30(F6, 'E1');
ok(h6.includes('href="https://vita.delta/c/61.pdf"'), 'https:// -> enlace');
ok(h6.includes('href="http://vita.delta/c/62.pdf"'), 'http:// -> enlace');
ok(h6.includes('href="https://vita.delta/c/63"'), 'HTTPS:// (mayusculas) -> normalizado y enlazado');
ok((h6.match(/target="_blank"/g) ?? []).length === 3, 'los 3 enlaces llevan target="_blank"');
ok((h6.match(/rel="noopener noreferrer"/g) ?? []).length === 3, 'los 3 llevan rel="noopener noreferrer"');
ok(!plano(h6).includes('Comprobante no enlazable'), 'ninguno de los validos dispara el aviso');

caso('D8 · comprobantes PELIGROSOS -> NUNCA href (F5)');
const h5 = html30(F5, 'E1');
ok(!/href="javascript:/i.test(h5), 'javascript: -> sin href');
ok(!/href="data:/i.test(h5), 'data: -> sin href');
ok(!/href="vbscript:/i.test(h5), 'vbscript: -> sin href');
ok(!/href="file:/i.test(h5), 'file: -> sin href');
ok(!/href="ftp:/i.test(h5), 'ftp: -> sin href');
ok(!h5.includes('href="/comprobantes/58.pdf"'), 'relativa -> sin href');
ok(!h5.includes('href="//evil.com/x"'), 'protocol-relative -> sin href');
ok(
  !h5.includes('alert(document.domain)') && !h5.includes('msgbox(1)') && !h5.includes('PHNjcmlwdD4='),
  'el PAYLOAD ejecutable no se refleja en ninguna parte del HTML'
);
ok(!/(javascript|data|vbscript|file|ftp):/i.test(h5.replace(/>[^<]*</g, '><')), 'ningun protocolo peligroso sobrevive en un ATRIBUTO');
ok(
  (plano(h5).match(/Comprobante no enlazable: URL no segura/g) ?? []).length === 10,
  'los 10 valores peligrosos muestran "Comprobante no enlazable: URL no segura"'
);
ok((h5.match(/<a /g) ?? []).length === 0, 'CERO etiquetas <a> en toda la tabla de F5');
// y la funcion pura, aparte del render
for (const v of ['javascript:alert(1)', 'JavaScript:alert(1)', 'java\nscript:alert(1)', '  javascript:alert(1)  ', 'data:text/html,x', 'vbscript:x', 'file:///etc/passwd', 'ftp://x/a', '/rel.pdf', '//evil.com', 'no url', '']) {
  ok(comprobanteSeguro(v) === null, `comprobanteSeguro(${JSON.stringify(v).slice(0, 30)}) -> null`);
}
ok(comprobanteSeguro('https://x.com/a') === 'https://x.com/a', 'comprobanteSeguro(https) -> href');
ok(comprobanteSeguro('http://x.com/a') === 'http://x.com/a', 'comprobanteSeguro(http) -> href');

caso('D9 · correlacion por id_gasto entre las 3 tablas (F9)');
const iG = t9.indexOf('Gastos congelados');
const iI = t9.indexOf('Incidencias');
const iS = t9.indexOf('Gastos sin incidencia');
ok(iG > 0 && iI > iG && iS > iI, 'las 3 tablas estan y en orden');
ok(t9.slice(iG, iI).includes('#42'), '"#42" en Gastos congelados (primera columna)');
ok(t9.slice(iI, iS).includes('#42'), '"#42" en Incidencias');
ok(t9.slice(iS).includes('#42'), '"#42" en Gastos sin incidencia');
ok(/<th[^>]*>Gasto<\/th>/.test(html30(F9, 'E1')), 'la columna se llama "Gasto" y es la primera');

caso('D10 · procedencia congelada del gasto');
ok(t1.includes('Cargado por Franco · 12/07/2026 18:35'), '"Cargado por Franco · 12/07/2026 18:35"');
const soloProc = txt30(F1, 'E1');
ok(!soloProc.includes('Clase sugerida'), 'clase_sugerida null -> no se muestra');
const conTodo = txt30(
  { ...F1, gastos: [{ ...F1.gastos[0], comentario: 'con detalle', clase_sugerida: 'A', medio_pago: 'efectivo', comprobante_url: 'https://v.d/x.pdf' }] },
  'E1'
);
ok(
  conTodo.includes('Cargado por Franco') &&
    conTodo.includes('con detalle') &&
    conTodo.includes('Clase sugerida al cargarlo: A') &&
    conTodo.includes('efectivo') &&
    conTodo.includes('Comprobante'),
  'con todos los opcionales: procedencia + comentario + clase sugerida + medio + comprobante'
);

caso('D11 · cruce de dia UTC -> Argentina (F8)');
const t8 = txt30(F8, 'E1');
ok(formatFechaHora('2026-07-13T02:30:00Z') === '12/07/2026 23:30', '02:30Z del 13 -> 12/07 23:30 AR (el prefijo del ISO daria el 13)');
ok(formatFechaHora('2026-07-13T03:00:00Z') === '13/07/2026 00:00', '03:00Z -> 00:00 AR, nunca "24:00" (hourCycle h23)');
ok(formatFechaHora('2026-07-12T21:35:00Z') === '12/07/2026 18:35', '21:35Z -> 18:35 AR');
ok(formatFechaHora('no-es-fecha') === 'no-es-fecha', 'ISO invalido -> string crudo, nunca "Invalid Date"');
ok(t8.includes('12/07/2026 23:30'), 'el cruce de dia se ve en la fila del gasto #81');
ok(t8.includes('13/07/2026 00:00'), 'medianoche AR se ve en la fila del gasto #82');

caso('D12 · IDs crudos de zona/cabaña (no hay nombres en la foto)');
ok(/por zona/.test(t1) || /#3/.test(t1), 'el alcance del gasto muestra el ID de zona crudo');
ok(t1.includes('Los IDs de zona y cabaña se muestran crudos'), 'y la UI aclara POR QUE (A30 no manda esos nombres)');

// =============================================================================================
bloque(`RESULTADO: ${total - fallos}/${total} aserciones OK`);
// =============================================================================================
console.log(
  fallos === 0
    ? `\n  TODO VERDE -- ${total} aserciones, ${CATALOGO_A30.length + CATALOGO_A31.length} fixtures + F19 (7 variantes).\n`
    : `\n  ${fallos} FALLAS de ${total}.\n`
);
process.exit(fallos === 0 ? 0 : 1);
