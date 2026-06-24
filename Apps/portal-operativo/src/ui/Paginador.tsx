/**
 * Paginador server-side (D-FE-15). Trabaja con limit/offset y el `total` del universo filtrado
 * que devuelve el backend (A24/A25: COUNT(*) OVER()). Muestra el rango "desde–hasta de total"
 * y Anterior/Siguiente, deshabilitados en los bordes. No pagina del lado del cliente: avisa el
 * nuevo offset y la pantalla re-consulta.
 */
export function Paginador({
  total,
  limit,
  offset,
  onPage,
}: {
  total: number;
  limit: number;
  offset: number;
  onPage: (offset: number) => void;
}) {
  const desde = total === 0 ? 0 : offset + 1;
  const hasta = Math.min(offset + limit, total);
  const hayAnterior = offset > 0;
  const haySiguiente = offset + limit < total;

  const btn =
    'rounded-lg border border-sand px-3 py-1.5 text-ink transition hover:bg-mist ' +
    'disabled:cursor-not-allowed disabled:opacity-40';

  return (
    <div className="flex items-center justify-between gap-3 px-1 py-2 text-sm text-reed">
      <span>{total === 0 ? 'Sin resultados' : `${desde}–${hasta} de ${total}`}</span>
      <div className="flex gap-2">
        <button type="button" className={btn} disabled={!hayAnterior} onClick={() => onPage(Math.max(offset - limit, 0))}>
          Anterior
        </button>
        <button type="button" className={btn} disabled={!haySiguiente} onClick={() => onPage(offset + limit)}>
          Siguiente
        </button>
      </div>
    </div>
  );
}
