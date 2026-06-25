import type { ReactNode } from 'react';
import { botonPrimario } from './estilos';

/**
 * Boton de submit con spinner + anti-doble-click (D-FE-25). `enviando` muestra el spinner y lo
 * deshabilita; `disabled` lo deshabilita por validacion (D-FE-21: bloqueo duro de A10). El
 * anti-doble-click tambien lo refuerza useEnviar (ignora `enviar` en vuelo); aca es la capa UX.
 * type="button": el submit lo dispara el onClick de la pantalla (sin <form>, D-FE-10).
 */
export function BotonSubmit({
  enviando,
  disabled,
  onClick,
  children,
}: {
  enviando: boolean;
  disabled?: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={enviando || disabled}
      aria-busy={enviando}
      className={botonPrimario + ' w-full sm:w-auto'}
    >
      {enviando && (
        <span
          className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent"
          aria-hidden
        />
      )}
      {children}
    </button>
  );
}
