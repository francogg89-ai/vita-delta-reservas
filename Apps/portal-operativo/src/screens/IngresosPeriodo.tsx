import { useMemo, useState } from 'react';
import { useAction } from '../hooks/useAction';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { Vacio } from '../ui/Vacio';
import { DataTable, type Columna } from '../ui/DataTable';
import { Paginador } from '../ui/Paginador';
import { Money } from '../ui/Money';
import { Fecha } from '../ui/Fecha';
import { FLOOR_MES } from '../lib/constantes';
import { primerDiaMes, ultimoDiaMes, mesActualOFloor } from '../lib/periodo';
import type { IngresosData, IngresoFila } from '../lib/contratos';

const LIMIT = 50;

function construirPayload(desde: string, hasta: string, offset: number): Record<string, unknown> {
  return { periodo_desde: primerDiaMes(desde), periodo_hasta: ultimoDiaMes(hasta), limit: LIMIT, offset };
}

const COLUMNAS: Columna<IngresoFila>[] = [
  { key: 'pago', header: 'Pago', render: (f) => `#${f.id_pago}` },
  { key: 'reserva', header: 'Reserva', render: (f) => (f.id_reserva != null ? `#${f.id_reserva}` : '—') },
  { key: 'cabana', header: 'Cabaña', render: (f) => f.cabana ?? '—' },
  { key: 'tipo', header: 'Tipo', render: (f) => f.tipo },
  { key: 'medio', header: 'Medio', render: (f) => f.medio_pago },
  { key: 'monto', header: 'Monto', align: 'right', render: (f) => <Money monto={f.monto} /> },
  { key: 'fecha', header: 'Fecha', render: (f) => <Fecha valor={f.created_at} /> },
];

function Desglose({ titulo, items }: { titulo: string; items: { etiqueta: string; monto: number; n: number }[] }) {
  if (items.length === 0) return null;
  return (
    <div className="rounded-2xl border border-sand bg-white p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-reed">{titulo}</p>
      <ul className="mt-2 space-y-1 text-sm">
        {items.map((it) => (
          <li key={it.etiqueta} className="flex items-center justify-between gap-3">
            <span className="text-ink">{it.etiqueta} <span className="text-reed">· {it.n}</span></span>
            <Money monto={it.monto} />
          </li>
        ))}
      </ul>
    </div>
  );
}

export function IngresosPeriodo() {
  const inicial = mesActualOFloor(FLOOR_MES);
  const [draft, setDraft] = useState({ desde: inicial, hasta: inicial });
  const [aplicados, setAplicados] = useState({ desde: inicial, hasta: inicial });
  const [offset, setOffset] = useState(0);

  const payload = useMemo(() => construirPayload(aplicados.desde, aplicados.hasta, offset), [aplicados, offset]);
  const { data, loading, error, refetch } = useAction<IngresosData>('ingresos.cobrados_periodo', payload);

  function buscar() { setOffset(0); setAplicados(draft); }

  const inputCls = 'mt-1 w-full rounded-lg border border-sand px-3 py-2 text-ink outline-none focus:border-river';

  return (
    <div className="mx-auto max-w-6xl space-y-4">
      <header>
        <p className="text-xs font-medium uppercase tracking-wide text-reed">ingresos.cobrados_periodo</p>
        <h2 className="mt-1 text-xl font-semibold text-ink">Ingresos cobrados</h2>
      </header>

      <div className="space-y-3 rounded-2xl border border-sand bg-white p-4">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <label>
            <span className="block text-sm text-reed">Mes desde</span>
            <input type="month" min={FLOOR_MES} value={draft.desde} onChange={(e) => setDraft((d) => ({ ...d, desde: e.target.value }))} className={inputCls} />
          </label>
          <label>
            <span className="block text-sm text-reed">Mes hasta</span>
            <input type="month" min={FLOOR_MES} value={draft.hasta} onChange={(e) => setDraft((d) => ({ ...d, hasta: e.target.value }))} className={inputCls} />
          </label>
          <div className="flex items-end">
            <button type="button" onClick={buscar} className="w-full rounded-lg bg-river px-4 py-2 text-sm font-medium text-white transition hover:bg-river-dark">Buscar</button>
          </div>
        </div>
        <p className="text-xs text-reed">Datos desde jul 2026. Cuenta seña + saldo confirmados (criterio Carril B).</p>
      </div>

      {loading && <Cargando mensaje="Cargando ingresos..." />}
      {!loading && error && <ErrorCard error={error} onRetry={refetch} />}
      {!loading && !error && data && (
        <div className="space-y-4">
          <div className="rounded-2xl border border-sand bg-white p-5">
            <p className="text-xs font-medium uppercase tracking-wide text-reed">Total cobrado</p>
            <p className="mt-1 text-2xl font-semibold text-ink"><Money monto={data.total_cobrado} /></p>
            <p className="text-sm text-reed">{data.total} pago{data.total === 1 ? '' : 's'} (seña + saldo)</p>
          </div>

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <Desglose titulo="Por mes" items={data.por_mes.map((x) => ({ etiqueta: x.mes, monto: x.monto, n: x.n }))} />
            <Desglose titulo="Por medio" items={data.por_medio.map((x) => ({ etiqueta: x.medio_pago, monto: x.monto, n: x.n }))} />
            <Desglose titulo="Por tipo" items={data.por_tipo.map((x) => ({ etiqueta: x.tipo, monto: x.monto, n: x.n }))} />
          </div>

          {data.otros_movimientos.por_tipo.length > 0 && (
            <Desglose
              titulo="Otros movimientos (no suman al total)"
              items={data.otros_movimientos.por_tipo.map((x) => ({ etiqueta: x.tipo, monto: x.monto, n: x.n }))}
            />
          )}

          {data.filas.length === 0 ? (
            <Vacio mensaje="Sin ingresos cobrados en ese período." />
          ) : (
            <div className="space-y-1">
              <DataTable columnas={COLUMNAS} filas={data.filas} filaKey={(f) => f.id_pago} />
              <Paginador total={data.total} limit={LIMIT} offset={offset} onPage={setOffset} />
            </div>
          )}
        </div>
      )}
    </div>
  );
}
