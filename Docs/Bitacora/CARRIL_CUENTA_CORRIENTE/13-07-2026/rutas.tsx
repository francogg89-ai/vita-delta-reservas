// Sustituye `src/app/rutas.tsx` SOLO dentro del harness (alias en vite.qa.config.ts).
// El AppShell que se monta es el REAL: header, drawer mobile, <main class="min-w-0 flex-1 p-6">.
// Lo unico que cambia es lo que va adentro del <main>: la vista pura con un fixture, sin red.
// __VITA_QA_FIXTURE_DO_NOT_SHIP__
import type { HistoricoAcumuladosData, HistoricoMesData } from '../../src/lib/contratos';
import type { PortalApiError } from '../../src/lib/callPortal';
import { HistoricoVista, type EstadoLectura } from '../../src/screens/historico/HistoricoVista';
import { construirPlanSelector } from '../../src/screens/historico/planSelector';
import { CATALOGO_A30, CATALOGO_A31 } from '../fixtures';
import { useQA } from '../store';

const ERROR_FALSO = {
  code: 'INTERNAL',
  message: 'Fallo simulado por el harness de QA.',
  detail: null,
} as unknown as PortalApiError;

function lectura<T>(estado: string, data: T | null): EstadoLectura<T> {
  return {
    data: estado === 'data' ? data : null,
    loading: estado === 'loading',
    error: estado === 'error' ? ERROR_FALSO : null,
    refetch: () => window.alert('refetch() -- el retry esta cableado.'),
  };
}

export function AppRoutes() {
  const { sel, set } = useQA();

  const d30 = CATALOGO_A30.find((f) => f.id === sel.a30)?.data ?? null;
  const d31 = CATALOGO_A31.find((f) => f.id === sel.a31)?.data ?? null;

  const acum = lectura<HistoricoAcumuladosData>(sel.estadoA31, d31);
  const foto = lectura<HistoricoMesData>(sel.estadoA30 === 'inactivo' ? 'inactivo' : sel.estadoA30, d30);
  const plan = construirPlanSelector(acum.data, []);

  return (
    <HistoricoVista
      faltaAccion={sel.faltaAccion}
      acum={acum}
      foto={foto}
      fotoPendiente={sel.fotoPendiente}
      seleccionFueraDePiso={sel.seleccionFueraDePiso}
      plan={plan}
      mesDraft={plan.porDefecto}
      mesApplied={sel.estadoA30 === 'inactivo' ? null : '2026-07'}
      reiniciadoPorPiso={sel.reiniciadoPorPiso}
      onMesDraftChange={() => undefined}
      onConsultar={() => set({ fotoPendiente: false })}
    />
  );
}
