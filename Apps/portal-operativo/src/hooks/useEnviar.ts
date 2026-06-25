import { useCallback, useEffect, useRef, useState } from 'react';
import { callPortal, PortalApiError } from '../lib/callPortal';

/** Como viaja la idempotency_key en el sobre, POR accion (D-FE-02). */
export type TransporteKey = 'none' | 'payload' | 'sibling';

export interface UseEnviarResult<TRes> {
  /** Envia la escritura. `reintento:true` reusa la MISMA key (solo tras estado_incierto, D-FE-20). */
  enviar: (payload: Record<string, unknown>, opts?: { reintento?: boolean }) => Promise<void>;
  enviando: boolean;
  resultado: TRes | null;
  error: PortalApiError | null;
  /** True si el ultimo error fue estado_incierto: la pantalla reconsulta companion (D-FE-22). */
  estadoIncierto: boolean;
  /** Limpia resultado/error y SUELTA la key retenida (para "cargar otro" -> proximo submit = key nueva). */
  reset: () => void;
}

/** idempotency_key valida (^[A-Za-z0-9_-]{8,64}$): 32 hex desde randomUUID. Sin libs ni storage. */
function nuevaKey(): string {
  return crypto.randomUUID().replace(/-/g, '');
}

/**
 * Hook unico de ESCRITURA contra portal-api (D-FE-19). Envuelve callPortal y agrega lo que
 * las 4 escrituras necesitan y las lecturas no:
 *  - anti-doble-click: ignora `enviar` mientras hay uno en vuelo;
 *  - ciclo de idempotency_key (D-FE-20): key NUEVA por submit; `reintento` reusa la retenida;
 *    `reset()` la suelta. Transporte por accion (D-FE-02): 'payload' (A10) / 'sibling' (A11) /
 *    'none' (A07/A08: el wrapper deriva idempotencia / guard por solapamiento);
 *  - `estadoIncierto` como flag aparte (D-FE-22): la pantalla reconsulta la lectura companion,
 *    NUNCA reintento ciego;
 *  - guard contra setState tras unmount (una accion de exito puede navegar fuera).
 *
 * No usa localStorage/sessionStorage (estado en React). `useAction` (lecturas) no se toca.
 */
export function useEnviar<TRes = unknown>(
  action: string,
  transporteKey: TransporteKey,
): UseEnviarResult<TRes> {
  const [enviando, setEnviando] = useState(false);
  const [resultado, setResultado] = useState<TRes | null>(null);
  const [error, setError] = useState<PortalApiError | null>(null);
  const [estadoIncierto, setEstadoIncierto] = useState(false);

  const keyRef = useRef<string | null>(null);
  const enviandoRef = useRef(false); // anti-doble-click sin depender del re-render del estado
  const montado = useRef(true);
  // El cuerpo del efecto DEBE re-setear montado=true en cada (re)montaje: bajo React.StrictMode
  // (dev) el efecto corre montar->cleanup->montar, y si el cuerpo no lo vuelve a poner en true,
  // queda en false para siempre (el cleanup lo apago) -> el guard descarta el resultado y nunca
  // apaga `enviando` (spinner eterno). useAction no sufre esto porque usa un flag local por corrida.
  useEffect(() => {
    montado.current = true;
    return () => { montado.current = false; };
  }, []);

  const enviar = useCallback(
    async (payload: Record<string, unknown>, opts?: { reintento?: boolean }) => {
      if (enviandoRef.current) return; // anti-doble-click
      enviandoRef.current = true;
      setEnviando(true);
      setError(null);
      setEstadoIncierto(false);
      setResultado(null); // un submit nuevo no debe dejar visible una tarjeta de exito vieja

      // Key por transporte (D-FE-02/20): reintento reusa la retenida; submit normal -> nueva.
      let key: string | null = null;
      if (transporteKey !== 'none') {
        key = opts?.reintento && keyRef.current ? keyRef.current : nuevaKey();
        keyRef.current = key;
      }

      try {
        let data: TRes;
        if (transporteKey === 'payload' && key) {
          data = await callPortal<TRes>(action, { ...payload, idempotency_key: key });
        } else if (transporteKey === 'sibling' && key) {
          data = await callPortal<TRes>(action, payload, { idempotency_key: key });
        } else {
          data = await callPortal<TRes>(action, payload);
        }
        if (!montado.current) return;
        setResultado(data);
      } catch (e) {
        if (!montado.current) return;
        const err =
          e instanceof PortalApiError
            ? e
            : new PortalApiError({ code: 'error_entorno', message: 'Error inesperado.', detail: null });
        setError(err);
        setEstadoIncierto(err.code === 'estado_incierto');
      } finally {
        enviandoRef.current = false;
        if (montado.current) setEnviando(false);
      }
    },
    [action, transporteKey],
  );

  const reset = useCallback(() => {
    keyRef.current = null;
    setResultado(null);
    setError(null);
    setEstadoIncierto(false);
  }, []);

  return { enviar, enviando, resultado, error, estadoIncierto, reset };
}
