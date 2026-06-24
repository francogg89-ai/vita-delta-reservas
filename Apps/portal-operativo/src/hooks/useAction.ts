import { useCallback, useEffect, useRef, useState } from 'react';
import { callPortal, PortalApiError } from '../lib/callPortal';

export interface UseActionResult<T> {
  data: T | null;
  loading: boolean;
  error: PortalApiError | null;
  refetch: () => void;
}

/**
 * Hook unico de lectura contra portal-api (D-FE-13). Envuelve callPortal y expone
 * { data, loading, error, refetch } con una sola convencion de estados.
 *
 *  - Re-dispara cuando cambian `action`, el `payload` (serializado) o `enabled`.
 *  - `enabled:false` -> NO dispara (util para A05: sin id no se consulta). El patron
 *    de filtros es draft -> applied: la pantalla mantiene el borrador y al "Buscar"
 *    hace setApplied(draft); el hook re-dispara al cambiar el payload aplicado.
 *  - Proteccion contra setState tras unmount y respuestas fuera de orden: un flag por
 *    corrida (`activo`) + un request-id incremental (`reqId`) descartan resultados de
 *    corridas viejas o de componentes ya desmontados.
 *  - El "vacio" lo decide la PANTALLA (filas.length===0 -> <Vacio/>), no el hook,
 *    porque "vacio" difiere por accion (filas:[] != no_encontrado de A05, D-C-47).
 *
 * AbortController quedo como mejora posterior (lo dejo flageado): requeriria threadear
 * un `signal` por la firma ya validada de callPortal; la correccion de unmount /
 * out-of-order ya esta cubierta por el guard de request-id, asi que no se toca el shell.
 */
export function useAction<T = unknown>(
  action: string,
  payload: Record<string, unknown> = {},
  options: { enabled?: boolean } = {},
): UseActionResult<T> {
  const { enabled = true } = options;
  // Clave estable del payload: evita re-fetch en loop por identidad de objeto.
  const payloadKey = JSON.stringify(payload);

  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState<boolean>(enabled);
  const [error, setError] = useState<PortalApiError | null>(null);
  const [tick, setTick] = useState(0); // disparador de refetch
  const reqId = useRef(0);

  useEffect(() => {
    if (!enabled) {
      setLoading(false);
      return;
    }
    let activo = true;
    const myId = ++reqId.current;
    setLoading(true);
    setError(null);

    callPortal<T>(action, JSON.parse(payloadKey) as Record<string, unknown>)
      .then((d) => {
        if (!activo || myId !== reqId.current) return; // corrida vieja / desmontado
        setData(d);
        setLoading(false);
      })
      .catch((e) => {
        if (!activo || myId !== reqId.current) return;
        setError(
          e instanceof PortalApiError
            ? e
            : new PortalApiError({ code: 'error_entorno', message: 'Error inesperado.', detail: null }),
        );
        setLoading(false);
      });

    return () => {
      activo = false;
    };
  }, [action, payloadKey, enabled, tick]);

  const refetch = useCallback(() => setTick((t) => t + 1), []);

  return { data, loading, error, refetch };
}
