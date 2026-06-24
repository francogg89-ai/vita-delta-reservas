// Formato de presentacion compartido.
//
// L-FE-02: los montos llegan del backend en PESOS como number (numeric(12,2)).
// "centavos" es solo la tecnica interna de suma del backend/render (Math.round(n*100)
// y luego /100) para evitar float drift. El frontend NUNCA divide por 100.

const ARS = new Intl.NumberFormat('es-AR', {
  style: 'currency',
  currency: 'ARS',
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** Formatea un monto en PESOS (no centavos) como ARS (ej. 335000 -> "$ 335.000,00"). */
export function formatARS(monto: number): string {
  return ARS.format(monto);
}

/** 'YYYY-MM-DD' -> 'dd/mm/aaaa'. Sin Date para evitar corrimiento de zona horaria. */
export function formatFecha(ymd: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(ymd);
  if (!m) return ymd;
  const [, y, mo, d] = m;
  return `${d}/${mo}/${y}`;
}
