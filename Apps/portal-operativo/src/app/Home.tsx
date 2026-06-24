import { useLocation } from 'react-router-dom';
import { useAuth } from '../auth/useAuth';
import type { AvisoRolState } from './RutaProtegida';

/** Pantalla de inicio (ruta index). Muestra un aviso si se llego aca por el guard de rol. */
export function Home() {
  const { contexto } = useAuth();
  const location = useLocation();
  const state = (location.state ?? null) as AvisoRolState | null;
  const bloqueado = state?.rolBloqueado;
  const primerNombre = contexto?.nombre.split(' ')[0] ?? '';

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      {bloqueado && (
        <div
          role="alert"
          className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800"
        >
          Esa seccion no esta disponible para tu rol.
        </div>
      )}
      <div className="rounded-2xl border border-sand bg-white p-8">
        <h2 className="text-xl font-semibold text-ink">Hola, {primerNombre}</h2>
        <p className="mt-2 text-reed">Elegi una opcion del menu para empezar.</p>
      </div>
    </div>
  );
}
