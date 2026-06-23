import { supabase } from './supabase';
import type { PortalErrorShape } from './types';

// Cliente unico contra el gateway portal-api (D-FE-10).
// Reglas del contrato que se respetan aca:
//  - Toda llamada lleva Authorization: Bearer <jwt> + apikey (anon, browser-safe) + Content-Type (contrato §3).
//  - Se ramifica SIEMPRE por body.ok, nunca por status HTTP (D-FE-04): el gateway
//    responde HTTP 200 + envelope para todo resultado manejado (incluido no_autorizado);
//    el unico no-200 es 500 (crash de infra).
//  - El frontend NUNCA calcula HMAC ni manda campos de control (actor/rol/nonce/etc.) (contrato §2).
//  - Transporte de idempotency_key POR accion (D-FE-02): A10 va dentro de `payload`;
//    A11 va en `extra` (sibling de payload). En sub-slice 0 solo se usa A02 (sin key).

const PORTAL_URL = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/portal-api`;
const ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

/** Error tipado de portal-api. `code` pertenece a la taxonomia del contrato (§8). */
export class PortalApiError extends Error {
  readonly code: string;
  readonly detail: unknown;
  constructor(shape: PortalErrorShape) {
    super(shape.message || shape.code);
    this.name = 'PortalApiError';
    this.code = shape.code;
    this.detail = shape.detail ?? null;
  }
}

type Envelope =
  | { ok: true; data: unknown }
  | { ok: false; error: PortalErrorShape };

function esEnvelope(value: unknown): value is Envelope {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as { ok?: unknown }).ok === 'boolean'
  );
}

/**
 * Llama una accion del catalogo via portal-api y devuelve `data` en caso de exito.
 * Lanza PortalApiError en cualquier otro caso (incluido envelope con ok:false).
 *
 * @param action  nombre de la accion del catalogo (ej. 'sesion.contexto')
 * @param payload objeto de parametros de la accion (default {})
 * @param extra   campos hermanos de payload en el sobre (ej. idempotency_key de A11)
 */
export async function callPortal<T = unknown>(
  action: string,
  payload: Record<string, unknown> = {},
  extra: Record<string, unknown> = {},
): Promise<T> {
  const { data } = await supabase.auth.getSession();
  const jwt = data.session?.access_token ?? '';

  let res: Response;
  try {
    res = await fetch(PORTAL_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: ANON_KEY,
        Authorization: `Bearer ${jwt}`,
      },
      body: JSON.stringify({ action, payload, ...extra }),
    });
  } catch {
    // Red caida / DNS / CORS: no llegamos al gateway.
    throw new PortalApiError({
      code: 'error_entorno',
      message: 'No se pudo contactar al servidor. Revisa tu conexion y proba de nuevo.',
      detail: null,
    });
  }

  // Manejo defensivo: un 5xx de infra puede no traer envelope JSON parseable.
  let body: unknown;
  try {
    body = await res.json();
  } catch {
    throw new PortalApiError({
      code: res.status >= 500 ? 'error_interno' : 'error_entorno',
      message: 'El servidor devolvio una respuesta inesperada. Proba de nuevo en un momento.',
      detail: null,
    });
  }

  if (!esEnvelope(body)) {
    throw new PortalApiError({
      code: 'error_entorno',
      message: 'Respuesta del servidor con formato inesperado.',
      detail: body,
    });
  }

  if (!body.ok) {
    throw new PortalApiError(
      body.error ?? {
        code: 'error_entorno',
        message: 'Error desconocido del servidor.',
        detail: null,
      },
    );
  }

  return body.data as T;
}
