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
