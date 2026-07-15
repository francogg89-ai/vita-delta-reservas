// Sustituye `src/app/rutas.tsx` SOLO dentro del harness (alias en vite.qa.config.ts).
// El AppShell que se monta es el REAL: header, drawer mobile, <main class="min-w-0 flex-1 p-6">.
// __VITA_QA_FIXTURE_DO_NOT_SHIP__
//
// DOS MODOS:
//   por defecto        -> HistoricoVista (VISTA PURA) con props controladas desde la barra QA.
//                         Sirve para el responsive y para barrer estados sin timing.
//   ?contenedor=1      -> HistoricoCuentaCorriente REAL, con la red interceptada en `stubs/red.ts`.
//                         Aca corren de verdad el token de peticion, el anti-doble-request y el
//                         `enabled` de los hooks. Es lo que exige el punto 3 de SB-UI-6-FIX.
import type { HistoricoAcumuladosData, HistoricoMesData } from '../../src/lib/contratos';
import type { PortalApiError } from '../../src/lib/callPortal';
import { HistoricoCuentaCorriente } from '../../src/screens/HistoricoCuentaCorriente';
import { HistoricoVista, type EstadoLectura } from '../../src/screens/historico/HistoricoVista';
import { construirPlanSelector } from '../../src/screens/historico/planSelector';
import { CATALOGO_A30, CATALOGO_A31 } from '../fixtures';
import { HostReqId } from '../HostReqId';
import { useQA } from '../store';

const ERROR_FALSO = {
  code: 'error_interno',
  message: 'Fallo simulado por el harness de QA.',
  detail: null,
} as unknown as PortalApiError;

/** Contador de invocaciones de refetch, para probar que el retry se cablea DE VERDAD. */
export const RETRY = { a30: 0, a31: 0 };

function lectura<T>(estado: string, data: T | null, quien: 'a30' | 'a31'): EstadoLectura<T> {
  return {
    data: estado === 'data' ? data : null,
    loading: estado === 'loading',
    error: estado === 'error' ? ERROR_FALSO : null,
    refetch: () => {
      RETRY[quien] += 1;
      (window as unknown as { __QA_RETRY__: typeof RETRY }).__QA_RETRY__ = RETRY;
    },
  };
}

export function AppRoutes() {
  const { sel, set } = useQA();

  const qs = new URLSearchParams(window.location.search);

  // Modo HOST-REQID: una sola instancia del `useAction` REAL, para probar su `reqId`.
  if (qs.get('host') === 'requid') {
    return <HostReqId />;
  }

  // Modo CONTENEDOR: se monta la pantalla real, sin tocarle un solo prop.
  if (qs.get('contenedor') === '1') {
    return <HistoricoCuentaCorriente />;
  }

  const d30 = CATALOGO_A30.find((f) => f.id === sel.a30)?.data ?? null;
  const d31 = CATALOGO_A31.find((f) => f.id === sel.a31)?.data ?? null;

  const acum = lectura<HistoricoAcumuladosData>(sel.estadoA31, d31, 'a31');
  const foto = lectura<HistoricoMesData>(sel.estadoA30, d30, 'a30');
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
      mesApplied={sel.estadoA30 === 'inactivo' ? null : sel.mesApplied}
      reiniciadoPorPiso={sel.reiniciadoPorPiso}
      onMesDraftChange={() => undefined}
      onConsultar={() => set({ fotoPendiente: false })}
    />
  );
}
