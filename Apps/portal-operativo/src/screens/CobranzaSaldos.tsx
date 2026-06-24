import { useAction } from '../hooks/useAction';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { Vacio } from '../ui/Vacio';
import { DataTable, type Columna } from '../ui/DataTable';
import { Money } from '../ui/Money';
import { Fecha } from '../ui/Fecha';
import type { SaldosData, SaldoFila } from '../lib/contratos';

const COLUMNAS: Columna<SaldoFila>[] = [
  { key: 'reserva', header: 'Reserva', render: (f) => `#${f.id_reserva}` },
  { key: 'cabana', header: 'Cabaña', render: (f) => f.cabana },
  {
    key: 'huesped',
    header: 'Huésped',
    render: (f) => (
      <div>
        <div>{f.huesped.nombre ?? '—'}</div>
        {(f.huesped.telefono || f.huesped.email) && (
          <div className="text-xs text-reed">{f.huesped.telefono ?? f.huesped.email}</div>
        )}
      </div>
    ),
  },
  {
    key: 'estadia',
    header: 'Estadía',
    render: (f) => (
      <span className="whitespace-nowrap">
        <Fecha valor={f.fecha_checkin} /> → <Fecha valor={f.fecha_checkout} />
      </span>
    ),
  },
  { key: 'total', header: 'Total', align: 'right', render: (f) => (f.monto_total != null ? <Money monto={f.monto_total} /> : '—') },
  { key: 'pagado', header: 'Pagado', align: 'right', render: (f) => (f.total_pagado_confirmado != null ? <Money monto={f.total_pagado_confirmado} /> : '—') },
  { key: 'saldo', header: 'Saldo', align: 'right', render: (f) => (f.saldo_real != null ? <Money monto={f.saldo_real} /> : '—') },
];

export function CobranzaSaldos() {
  const { data, loading, error, refetch } = useAction<SaldosData>('cobranza.saldos');

  return (
    <div className="mx-auto max-w-5xl space-y-4">
      <header>
        <p className="text-xs font-medium uppercase tracking-wide text-reed">cobranza.saldos</p>
        <h2 className="mt-1 text-xl font-semibold text-ink">Saldos a cobrar</h2>
      </header>

      {loading && <Cargando mensaje="Cargando saldos..." />}
      {!loading && error && <ErrorCard error={error} onRetry={refetch} />}
      {!loading && !error && data &&
        (data.filas.length === 0 ? (
          <Vacio mensaje="No hay saldos pendientes." />
        ) : (
          <DataTable columnas={COLUMNAS} filas={data.filas} filaKey={(f) => f.id_reserva} />
        ))}
    </div>
  );
}
