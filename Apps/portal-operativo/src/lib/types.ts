// Tipos compartidos del Portal Operativo.
// Reflejan el contrato CONTRATO_FRONTEND_PORTAL_v1.md (no lo reabren).

/** Roles del portal (contrato §10). `socio` cubre franco/rodrigo/remo. */
export type Rol = 'jenny' | 'vicky' | 'socio';

/** data de `sesion.contexto` (A02). `acciones` = base del menu (autoridad de visibilidad). */
export interface SesionContexto {
  nombre: string;
  rol: Rol;
  acciones: string[];
}

/** Forma del error del envelope: { ok:false, error:{ code, message, detail } } (contrato §6). */
export interface PortalErrorShape {
  code: string;
  message: string;
  detail: unknown;
}
