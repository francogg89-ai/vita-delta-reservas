// SB-UI-6-FIX2 -- Host minimo para probar `useAction.reqId` en UNA MISMA INSTANCIA.
// __VITA_QA_FIXTURE_DO_NOT_SHIP__
//
// POR QUE EXISTE. El escenario viejo (dos peticiones A31 bajo StrictMode) NO prueba el `reqId`:
// StrictMode monta, desmulta y REMONTA, asi que las dos peticiones pertenecen a DOS INSTANCIAS
// distintas del hook. Cada instancia tiene su propio `reqId` (es un `useRef`), y la respuesta de la
// instancia muerta se descarta por el `activo=false` de SU cleanup -- el `reqId` ni se entera.
// Encima las dos devolvian F10, asi que una sobrescritura vieja habria sido invisible.
//
// Para probar el `reqId` de verdad hace falta:
//   - UNA sola instancia del hook (sin remount);
//   - DOS corridas del efecto dentro de esa instancia (`refetch` -> `tick` -> re-run);
//   - fixtures DISTINGUIBLES, para que una sobrescritura se vea.
//
// Este host hace exactamente eso: usa el `useAction` REAL, expone su `refetch` a Playwright, y
// muestra el `detalle_motivo` recibido, que distingue F2 ('foto_pre_extension') de F1 (null).
import { useEffect } from 'react';
import { useAction } from '../src/hooks/useAction';
import type { HistoricoMesData } from '../src/lib/contratos';

declare global {
  interface Window {
    /** El `refetch` REAL del hook, para dispararlo desde el test mientras hay una peticion en vuelo. */
    __QA_REFETCH__?: () => void;
  }
}

export function HostReqId() {
  const r = useAction<HistoricoMesData>('cuenta_corriente.historico', { mes: '2026-07-01' });

  useEffect(() => {
    window.__QA_REFETCH__ = r.refetch;
  }, [r.refetch]);

  return (
    <div data-qa-host="requid" className="space-y-1 font-mono text-sm">
      <p>
        loading: <b data-qa="loading">{String(r.loading)}</b>
      </p>
      <p>
        {/* F1 -> "null" (E1) | F2 -> "foto_pre_extension" (E2). Es lo que distingue una respuesta
            de la otra: si la vieja pisa a la nueva, aca se ve. */}
        detalle_motivo: <b data-qa="motivo">{r.data ? String(r.data.detalle_motivo) : '-'}</b>
      </p>
      <p>
        periodo: <b data-qa="periodo">{r.data?.periodo ?? '-'}</b>
      </p>
      <p>
        error: <b data-qa="error">{r.error ? r.error.code : '-'}</b>
      </p>
    </div>
  );
}
