// Primitivas de fecha sobre strings 'YYYY-MM-DD' (YMD).
//
// Dos reglas de correccion que el resto del portal ya respeta (ver lib/formato.ts):
//  1. "Hoy/manana" en zona Argentina se calculan con Intl + timeZone, NO con el huso del
//     navegador ni con toISOString (que adelanta un dia cerca de la medianoche AR, UTC-3).
//     Asi hoyAR() espeja fecha_hoy_ar() del backend ((NOW() AT TIME ZONE 'America/...')::date).
//  2. La aritmetica de calendario (sumar dias, mes anterior/siguiente) se hace en UTC, leyendo
//     y escribiendo SOLO componentes UTC: nunca se interpreta wall-clock local, por lo que no
//     hay corrimiento de dia. Date se usa exclusivamente como aritmetica entera de calendario.

const FMT_AR = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Argentina/Buenos_Aires',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

/** "Hoy" en zona Argentina como 'YYYY-MM-DD'. Espejo de fecha_hoy_ar() (independiente del navegador). */
export function hoyAR(): string {
  // en-CA produce directamente 'YYYY-MM-DD'.
  return FMT_AR.format(new Date());
}

/** Suma `n` dias (negativo = resta) a un 'YYYY-MM-DD'. Aritmetica en UTC: sin corrimiento. */
export function sumarDias(ymd: string, n: number): string {
  const [y, m, d] = ymd.split('-').map(Number);
  const f = new Date(Date.UTC(y, m - 1, d) + n * 86400000);
  const yy = f.getUTCFullYear();
  const mm = String(f.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(f.getUTCDate()).padStart(2, '0');
  return `${yy}-${mm}-${dd}`;
}

/** "Manana" en zona Argentina como 'YYYY-MM-DD'. */
export function mananaAR(): string {
  return sumarDias(hoyAR(), 1);
}

/** 'YYYY-MM-DD' -> 'YYYY-MM' (mes calendario). */
export function ymDe(ymd: string): string {
  return ymd.slice(0, 7);
}

/** 'YYYY-MM' -> 'YYYY-MM-01' (primer dia del mes). */
export function primerDiaMes(ym: string): string {
  return `${ym}-01`;
}

/** 'YYYY-MM' del mes siguiente. (dia 1 + 32 dias cae siempre en el mes siguiente). */
export function mesSiguiente(ym: string): string {
  return ymDe(sumarDias(primerDiaMes(ym), 32));
}

/** 'YYYY-MM' del mes anterior. */
export function mesAnterior(ym: string): string {
  const [y, m] = ym.split('-').map(Number);
  const f = new Date(Date.UTC(y, m - 1, 1) - 1); // un ms antes del dia 1 = ultimo instante del mes anterior
  return `${f.getUTCFullYear()}-${String(f.getUTCMonth() + 1).padStart(2, '0')}`;
}

/** Primer dia ('YYYY-MM-DD') del mes siguiente a `ym` (sirve como `fecha_hasta` EXCLUSIVO de A26). */
export function primerDiaMesSiguiente(ym: string): string {
  return primerDiaMes(mesSiguiente(ym));
}

/** Dias del mes `ym` como lista de 'YYYY-MM-DD' (01..fin de mes). */
export function diasDelMes(ym: string): string[] {
  const [y, m] = ym.split('-').map(Number);
  const ultimo = new Date(Date.UTC(y, m, 0)).getUTCDate(); // dia 0 del mes siguiente = ultimo del mes
  const out: string[] = [];
  for (let d = 1; d <= ultimo; d++) out.push(`${ym}-${String(d).padStart(2, '0')}`);
  return out;
}

/** Offset (0..6) de la primera celda con semana que arranca el LUNES. getUTCDay: 0=Dom..6=Sab. */
export function offsetLunes(ym: string): number {
  const [y, m] = ym.split('-').map(Number);
  const dow = new Date(Date.UTC(y, m - 1, 1)).getUTCDay();
  return (dow + 6) % 7;
}
