// Mapa estado -> estilo. Cubre estados de reserva, prereserva y pago; default neutro para
// cualquier valor no listado (robusto ante estados nuevos del backend).
const COLORES: Record<string, string> = {
  confirmada: 'bg-green-50 text-green-700 border-green-200',
  confirmado: 'bg-green-50 text-green-700 border-green-200',
  activa: 'bg-green-50 text-green-700 border-green-200',
  completada: 'bg-river-light text-river-dark border-river/30',
  pendiente_pago: 'bg-amber-50 text-amber-700 border-amber-200',
  pago_en_revision: 'bg-amber-50 text-amber-700 border-amber-200',
  pendiente: 'bg-amber-50 text-amber-700 border-amber-200',
  conflicto_pendiente: 'bg-red-50 text-red-700 border-red-200',
  cancelada: 'bg-red-50 text-red-700 border-red-200',
  cancelada_con_cargo: 'bg-red-50 text-red-700 border-red-200',
};
const DEFECTO = 'bg-mist text-reed border-sand';

/** Badge de estado (reserva/prereserva/pago). Muestra el valor con guiones bajos como espacios. */
export function EstadoBadge({ estado }: { estado: string }) {
  const cls = COLORES[estado] ?? DEFECTO;
  return (
    <span className={'inline-block whitespace-nowrap rounded-full border px-2 py-0.5 text-xs font-medium ' + cls}>
      {estado.replace(/_/g, ' ')}
    </span>
  );
}
