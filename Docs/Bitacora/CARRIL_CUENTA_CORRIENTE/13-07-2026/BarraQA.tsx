// Panel de control del harness. Vive FUERA del <main> (overlay fijo) para NO contaminar la
// medicion de responsive: el ancho de la pagina lo tiene que decidir la pantalla, no esta barra.
// __VITA_QA_FIXTURE_DO_NOT_SHIP__
import { CATALOGO_A30, CATALOGO_A31 } from './fixtures';
import { useQA, type SeleccionQA } from './store';

const S = 'rounded border border-slate-600 bg-slate-800 px-1.5 py-1 text-xs text-slate-100';

export function BarraQA() {
  const { sel, set } = useQA();
  const flag = (k: keyof SeleccionQA, t: string) => (
    <label key={k} className="flex items-center gap-1 whitespace-nowrap">
      <input type="checkbox" checked={sel[k] as boolean} onChange={(e) => set({ [k]: e.target.checked })} />
      {t}
    </label>
  );
  return (
    <div
      data-qa-barra
      className="fixed bottom-0 left-0 right-0 z-50 flex flex-wrap items-center gap-x-3 gap-y-1.5 border-t border-slate-700 bg-slate-900 px-3 py-2 text-xs text-slate-200"
    >
      <span className="font-semibold text-amber-400">QA</span>
      <label className="flex items-center gap-1">
        A30
        <select className={S} value={sel.a30} onChange={(e) => set({ a30: e.target.value })}>
          {CATALOGO_A30.map((f) => (
            <option key={f.id} value={f.id}>{f.titulo}</option>
          ))}
        </select>
      </label>
      <select className={S} value={sel.estadoA30} onChange={(e) => set({ estadoA30: e.target.value as SeleccionQA['estadoA30'] })}>
        {['data', 'loading', 'error', 'inactivo'].map((e) => <option key={e} value={e}>{e}</option>)}
      </select>
      <label className="flex items-center gap-1">
        A31
        <select className={S} value={sel.a31} onChange={(e) => set({ a31: e.target.value })}>
          {CATALOGO_A31.map((f) => (
            <option key={f.id} value={f.id}>{f.titulo}</option>
          ))}
        </select>
      </label>
      <select className={S} value={sel.estadoA31} onChange={(e) => set({ estadoA31: e.target.value as SeleccionQA['estadoA31'] })}>
        {['data', 'loading', 'error'].map((e) => <option key={e} value={e}>{e}</option>)}
      </select>
      {flag('faltaAccion', 'faltaAccion')}
      {flag('fotoPendiente', 'fotoPendiente')}
      {flag('seleccionFueraDePiso', 'fueraDePiso')}
      {flag('reiniciadoPorPiso', 'reiniciadoPorPiso')}
    </div>
  );
}
