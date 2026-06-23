import type { ActionMeta } from '../lib/actionRegistry';

// Acciones de escritura (contrato §7). Definen el mensaje del placeholder.
const ESCRITURAS = new Set([
  'reserva.crear_manual',
  'bloqueo.crear_manual',
  'cobranza.registrar_saldo',
  'cargar.gasto_interno',
]);

export function PlaceholderView({ meta }: { meta: ActionMeta }) {
  const esEscritura = ESCRITURAS.has(meta.action);
  const subSlice = esEscritura
    ? 'sub-slice 2 (pantallas de carga)'
    : 'sub-slice 1 (pantallas de lectura)';

  return (
    <div className="mx-auto max-w-2xl">
      <p className="text-xs font-medium uppercase tracking-wide text-reed">{meta.action}</p>
      <h2 className="mt-1 text-xl font-semibold text-ink">{meta.label}</h2>
      <div className="mt-6 rounded-2xl border border-dashed border-sand bg-white p-8 text-center">
        <p className="text-ink">Esta pantalla todavia no esta construida.</p>
        <p className="mt-1 text-sm text-reed">Llega en el {subSlice}.</p>
      </div>
    </div>
  );
}
