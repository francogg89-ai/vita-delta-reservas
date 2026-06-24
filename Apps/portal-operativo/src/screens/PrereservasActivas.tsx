import { useAction } from '../hooks/useAction';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { Vacio } from '../ui/Vacio';
import { DataTable, type Columna } from '../ui/DataTable';
import { Money } from '../ui/Money';
import { Fecha } from '../ui/Fecha';
import { EstadoBadge } from '../ui/EstadoBadge';
import type { PrereservasData, PrereservaFila } from '../lib/contratos';

const COLUMNAS: Columna<PrereservaFila>[] = [
  { key: 'cabana', header: 'Cabaña', render: (f) => f.cabana },
  {
    key: 'huesped',
    header: 'Huésped',
    render: (f) => (
      <div>
        <div>{f.huesped.nombre ?? '—'}</div>
        {f.huesped.telefono && <div className="text-xs text-reed">{f.huesped.telefono}</div>}
      </div>
    ),
  },
  {
    key: 'estadia',
    header: 'Estadía',
    render: (f) => (
      <span className="whitespace-nowrap">
        <Fecha valor={f.fecha_in} /> → <Fecha valor={f.fecha_out} />
      </span>
    ),
  },
  { key: 'personas', header: 'Pers.', align: 'center', render: (f) => f.personas },
  { key: 'estado', header: 'Estado', render: (f) => <EstadoBadge estado={f.estado} /> },
  {
    key: 'vence',
    header: 'Vence',
    align: 'right',
    render: (f) => (f.minutos_para_vencer != null ? `${f.minutos_para_vencer} min` : '—'),
  },
  { key: 'total', header: 'Total', align: 'right', render: (f) => (f.monto_total != null ? <Money monto={f.monto_total} /> : '—') },
  { key: 'sena', header: 'Seña', align: 'right', render: (f) => (f.monto_sena != null ? <Money monto={f.monto_sena} /> : '—') },
];

export function PrereservasActivas() {
  const { data, loading, error, refetch } = useAction<PrereservasData>('prereservas.activas');

  return (
    <div className="mx-auto max-w-6xl space-y-4">
      <header>
        <p className="text-xs font-medium uppercase tracking-wide text-reed">prereservas.activas</p>
        <h2 className="mt-1 text-xl font-semibold text-ink">Pre-reservas activas</h2>
      </header>

      {loading && <Cargando mensaje="Cargando pre-reservas..." />}
      {!loading && error && <ErrorCard error={error} onRetry={refetch} />}
      {!loading && !error && data &&
        (data.filas.length === 0 ? (
          <Vacio mensaje="No hay pre-reservas activas." />
        ) : (
          <DataTable columnas={COLUMNAS} filas={data.filas} filaKey={(f) => f.id_pre_reserva} />
        ))}
    </div>
  );
}
