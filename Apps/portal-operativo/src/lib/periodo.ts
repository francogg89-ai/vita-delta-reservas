// Helpers de período mensual para los reportes A25/A13.
// El backend espera fechas YMD; nosotros elegimos MESES. Regla uniforme (sirve para A25 y A13):
//   periodo_desde = primer día del mes "desde"; periodo_hasta = ÚLTIMO día del mes "hasta".
// A25 usa bound inclusivo a nivel día (created_at, half-open +1); A13 trunca a primer día de mes
// igual, así que el último día del mes "hasta" cae dentro de ese mes en ambos. Siempre mandamos
// strings (nunca null) para no caer en la divergencia A25-estricto / A13 (sin periodo_hasta da vacío).

/** 'YYYY-MM' -> 'YYYY-MM-01' */
export function primerDiaMes(ym: string): string {
  return `${ym}-01`;
}

/** 'YYYY-MM' -> 'YYYY-MM-DD' con DD = último día del mes. */
export function ultimoDiaMes(ym: string): string {
  const [y, m] = ym.split('-').map(Number);
  // m es 1-based; new Date(y, m, 0) = día 0 del mes siguiente = último día del mes m.
  const dia = new Date(y, m, 0).getDate();
  return `${ym}-${String(dia).padStart(2, '0')}`;
}

/** Mes actual en 'YYYY-MM', pero nunca antes del floor contable. */
export function mesActualOFloor(floorMes: string): string {
  const hoy = new Date();
  const actual = `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}`;
  return actual < floorMes ? floorMes : actual;
}

// ---------------------------------------------------------------------------------------------
// Helpers de periodo del historico L3 (A30/A31). ADITIVOS: no tocan los helpers de arriba (A25/A13)
// ni CuentaCorrienteDetalle.tsx (pantalla cerrada, D-FE-55), que conserva sus copias locales de
// `etiquetaMes` / `mesesDisponibles`. Deuda cosmetica registrada: `etiquetaMes` queda duplicado.
//
// Todas las comparaciones de 'YYYY-MM' y 'YYYY-MM-DD' son LEXICAS: para estos formatos, el orden
// lexicografico coincide con el cronologico. Nunca se construye un Date para comparar.
// ---------------------------------------------------------------------------------------------

const MESES_ES = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/** 'YYYY-MM' -> 'julio 2026'. Sin Date (no corre zona horaria). */
export function etiquetaMes(ym: string): string {
  const [y, m] = ym.split('-').map(Number);
  const nombre = MESES_ES[m - 1];
  return nombre !== undefined ? `${nombre} ${y}` : ym;
}

/** 'YYYY-MM-DD' -> 'YYYY-MM'. Puramente lexico: los `date` del jsonb llegan como string ISO. */
export function ymDeFecha(ymd: string): string {
  return ymd.slice(0, 7);
}

/**
 * Mes actual en 'YYYY-MM', en horario de Argentina.
 *
 * Usa Intl con `timeZone` explicito en vez de `getFullYear()`/`getMonth()` (hora local del
 * navegador) para que el mes no dependa del huso del cliente. `mesActualOFloor` (A25/A13) conserva
 * el criterio viejo y NO se toca: divergencia deliberada, sin efecto practico para usuarios en AR.
 */
export function mesActualYM(): string {
  const ymd = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Argentina/Buenos_Aires',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
  return ymd.slice(0, 7);
}

/** El mayor de dos 'YYYY-MM' (comparacion lexica === cronologica). */
export function maxYM(a: string, b: string): string {
  return a >= b ? a : b;
}

/** Lista ASCENDENTE de meses 'YYYY-MM' en [desde, hasta] inclusive. Vacia si hasta < desde. */
export function rangoMesesYM(desde: string, hasta: string): string[] {
  const out: string[] = [];
  if (hasta < desde) return out;
  let [y, m] = desde.split('-').map(Number);
  const [hy, hm] = hasta.split('-').map(Number);
  while (y < hy || (y === hy && m <= hm)) {
    out.push(`${y}-${String(m).padStart(2, '0')}`);
    m += 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
  }
  return out;
}
