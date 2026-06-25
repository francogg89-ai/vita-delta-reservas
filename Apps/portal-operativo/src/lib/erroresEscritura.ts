import type { PortalApiError } from './callPortal';

// Familia B del contrato (§8): canal gateway<->n8n / "no deberia pasar". El frontend no firma
// ni manda ts/nonce, asi que no las gatilla en operacion normal; si aparecen, es bug de backend
// -> mensaje generico, NUNCA tratarlas como validacion del usuario (D-FE-22/25).
const FAMILIA_B = new Set<string>([
  'firma_invalida', 'ts_fuera_de_ventana', 'raw_body_ausente', 'ambiente_incorrecto', 'error_entorno',
]);

const MSG_FAMILIA_B = 'Error del sistema. Reintenta en un momento o avisa al administrador.';

/** True si el error es estado_incierto (escritura sin confirmar): la pantalla reconsulta companion. */
export function esEstadoIncierto(error: PortalApiError | null): boolean {
  return error?.code === 'estado_incierto';
}

/**
 * Mensaje para mostrar al usuario a partir del error tipado (D-FE-25):
 *  - familia B -> mensaje generico (no es culpa del usuario);
 *  - resto (familia A: payload_invalido/conflicto/no_encontrado/error_interno/...) -> el message
 *    curado del backend. Para A11 el de coherencia es generico y detail.constraint NO llega por
 *    el gateway (P-FE-07): los mensajes finos salen de la pre-validacion del cliente, no de aca.
 */
export function mensajeUsuario(error: PortalApiError): string {
  if (FAMILIA_B.has(error.code)) return MSG_FAMILIA_B;
  return error.message || 'Ocurrio un error.';
}
