import type { ReactNode } from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '../auth/useAuth';

/** Estado que viaja al home cuando se bloquea una ruta por rol (lo lee Home). */
export interface AvisoRolState {
  rolBloqueado?: string;
}

/**
 * Guard de ruta por rol (D-FE-17). Espeja D-FE-09: el backend es la unica autoridad
 * de visibilidad; el front solo defiende en profundidad. Si la `action` no esta en
 * `contexto.acciones` (p. ej. navegacion directa por URL a una ruta no permitida para
 * el rol), redirige a `/` con un aviso breve. Si por algun motivo se saltara este
 * guard, el backend igual rebotaria `rol_no_permitido` y lo agarraria el estado de
 * error de la pantalla.
 */
export function RutaProtegida({ action, children }: { action: string; children: ReactNode }) {
  const { contexto } = useAuth();
  // AppShell solo monta en estado 'autenticado'; este check es defensivo.
  if (!contexto) return null;
  if (!contexto.acciones.includes(action)) {
    const state: AvisoRolState = { rolBloqueado: action };
    return <Navigate to="/" replace state={state} />;
  }
  return <>{children}</>;
}
