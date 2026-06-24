import { useMemo, useState } from 'react';
import { useAction } from '../hooks/useAction';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { Vacio } from '../ui/Vacio';
import { DataTable, type Columna } from '../ui/DataTable';
import { Paginador } from '../ui/Paginador';
import { Money } from '../ui/Money';
import { Fecha } from '../ui/Fecha';
import { EstadoBadge } from '../ui/EstadoBadge';
import { CABANAS_TEST, ESTADOS_RESERVA, FLOOR_CONTABLE } from '../lib/constantes';
import type { HistoricoData, HistoricoFila } from '../lib/contratos';

const LIMIT = 50; // tamaño de página fijo (D-FE-15)

interface Filtros {
  fecha_desde: string;
  fecha_hasta: string;
  id_cabana: string; // '' = todas
  estado: string; // '' = todos
  texto: string;
}
const VACIO: Filtros = { fecha_desde: '', fecha_hasta: '', id_cabana: '', estado: '', texto: '' };

/** Arma el payload omitiendo filtros vacíos (ausente = sin filtro). El backend clampea
 *  fecha_desde al floor 2026-07-01 (GREATEST en el SQL); acá además limitamos el input con `min`. */
function construirPayload(f: Filtros, offset: number): Record<string, unknown> {
  const p: Record<string, unknown> = { limit: LIMIT, offset };
  if (f.fecha_desde) p.fecha_desde = f.fecha_desde;
  if (f.fecha_hasta) p.fecha_hasta = f.fecha_hasta;
  if (f.id_cabana) p.id_cabana = Number(f.id_cabana);
  if (f.estado) p.estado = f.estado;
  if (f.texto.trim()) p.texto = f.texto.trim();
  return p;
}

const COLUMNAS: Columna<HistoricoFila>[] = [
  { key: 'reserva', header: 'Reserva', render: (f) => `#${f.id_reserva}` },
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
    header: 'Check-in → out',
    render: (f) => (
      <span className="whitespace-nowrap">
        <Fecha valor={f.fecha_checkin} /> → <Fecha valor={f.fecha_checkout} />
      </span>
    ),
  },
  { key: 'personas', header: 'Pers.', align: 'center', render: (f) => f.personas },
  { key: 'estado', header: 'Estado', render: (f) => <EstadoBadge estado={f.estado} /> },
  { key: 'total', header: 'Total', align: 'right', render: (f) => (f.monto_total != null ? <Money monto={f.monto_total} /> : '—') },
  { key: 'saldo', header: 'Saldo', align: 'right', render: (f) => (f.saldo_real != null ? <Money monto={f.saldo_real} /> : '—') },
];

export function HistoricoReservas() {
  const [draft, setDraft] = useState<Filtros>(VACIO);
  const [aplicados, setAplicados] = useState<Filtros>(VACIO);
  const [offset, setOffset] = useState(0);

  const payload = useMemo(() => construirPayload(aplicados, offset), [aplicados, offset]);
  const { data, loading, error, refetch } = useAction<HistoricoData>('historico.reservas', payload);

  function set<K extends keyof Filtros>(k: K, v: string) {
    setDraft((d) => ({ ...d, [k]: v }));
  }
  function buscar() {
    setOffset(0);
    setAplicados(draft);
  }
  function limpiar() {
    setDraft(VACIO);
    setOffset(0);
    setAplicados(VACIO);
  }

  const inputCls = 'mt-1 w-full rounded-lg border border-sand px-3 py-2 text-ink outline-none focus:border-river';

  return (
    <div className="mx-auto max-w-6xl space-y-4">
      <header>
        <p className="text-xs font-medium uppercase tracking-wide text-reed">historico.reservas</p>
        <h2 className="mt-1 text-xl font-semibold text-ink">Histórico de reservas</h2>
      </header>

      <div className="space-y-3 rounded-2xl border border-sand bg-white p-4">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <label>
            <span className="block text-sm text-reed">Check-in desde</span>
            <input type="date" min={FLOOR_CONTABLE} value={draft.fecha_desde} onChange={(e) => set('fecha_desde', e.target.value)} className={inputCls} />
          </label>
          <label>
            <span className="block text-sm text-reed">Check-in hasta</span>
            <input type="date" min={FLOOR_CONTABLE} value={draft.fecha_hasta} onChange={(e) => set('fecha_hasta', e.target.value)} className={inputCls} />
          </label>
          <label>
            <span className="block text-sm text-reed">Cabaña</span>
            <select value={draft.id_cabana} onChange={(e) => set('id_cabana', e.target.value)} className={inputCls}>
              <option value="">Todas</option>
              {CABANAS_TEST.map((c) => (
                <option key={c.id} value={String(c.id)}>{c.nombre}</option>
              ))}
            </select>
          </label>
          <label>
            <span className="block text-sm text-reed">Estado</span>
            <select value={draft.estado} onChange={(e) => set('estado', e.target.value)} className={inputCls}>
              <option value="">Todos</option>
              {ESTADOS_RESERVA.map((s) => (
                <option key={s} value={s}>{s.replace(/_/g, ' ')}</option>
              ))}
            </select>
          </label>
          <label className="sm:col-span-2 lg:col-span-1">
            <span className="block text-sm text-reed">Buscar (nombre, teléfono o email)</span>
            <input
              type="text"
              value={draft.texto}
              onChange={(e) => set('texto', e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') buscar(); }}
              placeholder="Ej. juan / 1155…"
              className={inputCls}
            />
          </label>
        </div>
        <div className="flex items-center justify-between gap-3">
          <p className="text-xs text-reed">Datos desde jul 2026.</p>
          <div className="flex gap-2">
            <button type="button" onClick={limpiar} className="rounded-lg border border-sand px-4 py-2 text-sm text-ink transition hover:bg-mist">
              Limpiar
            </button>
            <button type="button" onClick={buscar} className="rounded-lg bg-river px-4 py-2 text-sm font-medium text-white transition hover:bg-river-dark">
              Buscar
            </button>
          </div>
        </div>
      </div>

      {loading && <Cargando mensaje="Cargando reservas..." />}
      {!loading && error && <ErrorCard error={error} onRetry={refetch} />}
      {!loading && !error && data &&
        (data.filas.length === 0 ? (
          <Vacio mensaje="Sin reservas para esos filtros." />
        ) : (
          <div className="space-y-1">
            <DataTable columnas={COLUMNAS} filas={data.filas} filaKey={(f) => f.id_reserva} />
            <Paginador total={data.total} limit={LIMIT} offset={offset} onPage={setOffset} />
          </div>
        ))}
    </div>
  );
}
