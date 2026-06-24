import { formatFecha } from '../lib/formato';

/** 'YYYY-MM-DD' -> dd/mm/aaaa. */
export function Fecha({ valor, className }: { valor: string; className?: string }) {
  return <span className={className}>{formatFecha(valor)}</span>;
}
