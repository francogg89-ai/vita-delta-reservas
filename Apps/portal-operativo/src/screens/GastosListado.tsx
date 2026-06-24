import { useMemo, useState } from 'react';
import { useAction } from '../hooks/useAction';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { Vacio } from '../ui/Vacio';
import { DataTable, type Columna } from '../ui/DataTable';
import { Paginador } from '../ui/Paginador';
import { Money } from '../ui/Money';
import { Fecha } from '../ui/Fecha';
import { FLOOR_MES, CLASES_GASTO, PAGADOR_TIPOS } from '../lib/constantes';
import { primerDiaMes, ultimoDiaMes, mesActualOFloor } from '../lib/periodo';
import type { GastosData, GastoFila } from '../lib/contratos';

const LIMIT = 50;

interface Filtros {
  desde: string;
  hasta: string;
  clase: string; // '' = todas
  pagador_tipo: string; // '' = todos
  q: string;
}

function construirPayload(f: Filtros, offset: number): Record<string, unknown> {
  const p: Record<string, unknown> = {
    periodo_desde: primerDiaMes(f.desde),
    periodo_hasta: ultimoDiaMes(f.hasta),
    limit: LIMIT,
    offset,
  };
  if (f.clase) p.clase = f.clase;
  if (f.pagador_tipo) p.pagador_tipo = f.pagador_tipo;
  if (f.q.trim()) p.q = f.q.trim();
  return p;
}

// Etiqueta corta de clase para tabla/desglose (A=común, C=común op., D=zona, E=cabaña).
const CLASE_LABEL: Record<string, string> = { A: 'Común', C: 'Común op.', D: 'Por zona', E: 'Por cabaña' };

const COLUMNAS: Columna<GastoFila>[] = [
  { key: 'gasto', header: 'Gasto', render: (f) => `#${f.id_gasto}` },
  { key: 'periodo', header: 'Período', render: (f) => (f.periodo ? f.periodo.slice(0, 7) : '—') },
  { key: 'fecha', header: 'Fecha', render: (f) => <Fecha valor={f.fecha} /> },
  { key: 'clase', header: 'Clase', render: (f) => `${f.clase} · ${CLASE_LABEL[f.clase] ?? ''}`.trim() },
  { key: 'etiqueta', header: 'Etiqueta', render: (f) => f.etiqueta },
  { key: 'alcance', header: 'Alcance', render: (f) => f.cabana ?? f.zona ?? '—' },
  { key: 'pagador', header: 'Pagador', render: (f) => (f.pagador_tipo === 'socio' ? (f.socio_pagador_nombre ?? 'socio') : 'caja') },
  { key: 'monto', header: 'Monto', align: 'right', render: (f) => (f.monto != null ? <Money monto={f.monto} /> : '—') },
];

export function GastosListado() {
  const inicial = mesActualOFloor(FLOOR_MES);
  const VACIO: Filtros = { desde: inicial, hasta: inicial, clase: '', pagador_tipo: '', q: '' };
  const [draft, setDraft] = useState<Filtros>(VACIO);
  const [aplicados, setAplicados] = useState<Filtros>(VACIO);
  const [offset, setOffset] = useState(0);

  const payload = useMemo(() => construirPayload(aplicados, offset), [aplicados, offset]);
  const { data, loading, error, refetch } = useAction<GastosData>('gastos.listado', payload);

  // A13 no trae `total`: el conteo del universo = Σ por_clase.n (D-FE-15).
  const totalConteo = useMemo(() => (data ? data.por_clase.reduce((s, c) => s + c.n, 0) : 0), [data]);

  function set<K extends keyof Filtros>(k: K, v: string) { setDraft((d) => ({ ...d, [k]: v })); }
  function buscar() { setOffset(0); setAplicados(draft); }
  function limpiar() { setDraft(VACIO); setOffset(0); setAplicados(VACIO); }

  const inputCls = 'mt-1 w-full rounded-lg border border-sand px-3 py-2 text-ink outline-none focus:border-river';

  return (
    <div className="mx-auto max-w-6xl space-y-4">
      <header>
        <p className="text-xs font-medium uppercase tracking-wide text-reed">gastos.listado</p>
        <h2 className="mt-1 text-xl font-semibold text-ink">Gastos</h2>
      </header>

      <div className="space-y-3 rounded-2xl border border-sand bg-white p-4">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <label>
            <span className="block text-sm text-reed">Mes desde</span>
            <input type="month" min={FLOOR_MES} value={draft.desde} onChange={(e) => set('desde', e.target.value)} className={inputCls} />
          </label>
          <label>
            <span className="block text-sm text-reed">Mes hasta</span>
            <input type="month" min={FLOOR_MES} value={draft.hasta} onChange={(e) => set('hasta', e.target.value)} className={inputCls} />
          </label>
          <label>
            <span className="block text-sm text-reed">Clase</span>
            <select value={draft.clase} onChange={(e) => set('clase', e.target.value)} className={inputCls}>
              <option value="">Todas</option>
              {CLASES_GASTO.map((c) => (<option key={c.valor} value={c.valor}>{c.etiqueta}</option>))}
            </select>
          </label>
          <label>
            <span className="block text-sm text-reed">Pagador</span>
            <select value={draft.pagador_tipo} onChange={(e) => set('pagador_tipo', e.target.value)} className={inputCls}>
              <option value="">Todos</option>
              {PAGADOR_TIPOS.map((s) => (<option key={s} value={s}>{s}</option>))}
            </select>
          </label>
          <label className="sm:col-span-2 lg:col-span-1">
            <span className="block text-sm text-reed">Buscar (etiqueta o comentario)</span>
            <input
              type="text"
              value={draft.q}
              onChange={(e) => set('q', e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') buscar(); }}
              placeholder="Ej. luz / nafta"
              className={inputCls}
            />
          </label>
        </div>
        <div className="flex items-center justify-between gap-3">
          <p className="text-xs text-reed">Datos desde jul 2026. Período = mes contable.</p>
          <div className="flex gap-2">
            <button type="button" onClick={limpiar} className="rounded-lg border border-sand px-4 py-2 text-sm text-ink transition hover:bg-mist">Limpiar</button>
            <button type="button" onClick={buscar} className="rounded-lg bg-river px-4 py-2 text-sm font-medium text-white transition hover:bg-river-dark">Buscar</button>
          </div>
        </div>
      </div>

      {loading && <Cargando mensaje="Cargando gastos..." />}
      {!loading && error && <ErrorCard error={error} onRetry={refetch} />}
      {!loading && !error && data && (
        <div className="space-y-4">
          <div className="rounded-2xl border border-sand bg-white p-5">
            <p className="text-xs font-medium uppercase tracking-wide text-reed">Total gastos</p>
            <p className="mt-1 text-2xl font-semibold text-ink"><Money monto={data.total_gastos} /></p>
            <p className="text-sm text-reed">{totalConteo} gasto{totalConteo === 1 ? '' : 's'}</p>
          </div>

          {data.por_clase.length > 0 && (
            <div className="rounded-2xl border border-sand bg-white p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-reed">Por clase</p>
              <ul className="mt-2 space-y-1 text-sm">
                {data.por_clase.map((c) => (
                  <li key={c.clase} className="flex items-center justify-between gap-3">
                    <span className="text-ink">{c.clase} · {CLASE_LABEL[c.clase] ?? ''} <span className="text-reed">· {c.n}</span></span>
                    <Money monto={c.monto} />
                  </li>
                ))}
              </ul>
            </div>
          )}

          {data.filas.length === 0 ? (
            <Vacio mensaje="Sin gastos en ese período." />
          ) : (
            <div className="space-y-1">
              <DataTable columnas={COLUMNAS} filas={data.filas} filaKey={(f) => f.id_gasto} />
              <Paginador total={totalConteo} limit={LIMIT} offset={offset} onPage={setOffset} />
            </div>
          )}
        </div>
      )}
    </div>
  );
}
