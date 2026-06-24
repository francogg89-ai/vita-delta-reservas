import { formatARS } from '../lib/formato';

/**
 * Monto en PESOS (no centavos) renderizado como ARS (L-FE-02: nunca /100).
 * Negativos en rojo (caso real: saldo_real negativo = sobrecobro en A12/A24).
 */
export function Money({ monto, className }: { monto: number; className?: string }) {
  const negativo = monto < 0;
  return (
    <span className={(negativo ? 'text-red-600 ' : 'text-ink ') + (className ?? '')}>
      {formatARS(monto)}
    </span>
  );
}
