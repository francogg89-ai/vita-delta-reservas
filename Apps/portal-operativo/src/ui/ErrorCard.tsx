import type { PortalApiError } from '../lib/callPortal';

interface ErrorCardProps {
  error: PortalApiError;
  onRetry?: () => void;
}

/**
 * Tarjeta de error generica de pantalla. Muestra el `message` curado del envelope y,
 * si se pasa onRetry, un boton de reintento (D-FE-13/18). El frontend ramifica por
 * body.ok; aca solo presenta el error ya tipado por callPortal.
 */
export function ErrorCard({ error, onRetry }: ErrorCardProps) {
  return (
    <div role="alert" className="rounded-2xl border border-red-200 bg-red-50 px-6 py-5 text-red-800">
      <p className="font-medium">No se pudo cargar la informacion.</p>
      <p className="mt-1 text-sm">{error.message}</p>
      {onRetry && (
        <button
          type="button"
          onClick={onRetry}
          className="mt-3 rounded-lg border border-red-300 bg-white px-3 py-1.5 text-sm text-red-800 transition hover:bg-red-100"
        >
          Reintentar
        </button>
      )}
    </div>
  );
}
