import type { ReactNode } from 'react';

/**
 * Envoltura de campo de formulario (mobile-first): label + control + error/hint.
 * El control real (input/select/textarea) lo pasa la pantalla como children, con la clase
 * compartida `controlClass` (ui/estilos). `error` se muestra en rojo bajo el control; `hint`
 * en gris. No se muestran a la vez: el error tiene prioridad. El <label> envuelve el control
 * para que toda el area sea tappable en celular.
 */
export function Campo({
  label,
  requerido,
  error,
  hint,
  children,
}: {
  label: string;
  requerido?: boolean;
  error?: string | null;
  hint?: ReactNode;
  children: ReactNode;
}) {
  return (
    <label className="block">
      <span className="block text-sm font-medium text-reed">
        {label}
        {requerido && <span className="ml-0.5 text-river-dark" aria-hidden>*</span>}
      </span>
      {children}
      {error ? (
        <span className="mt-1 block text-xs text-red-600">{error}</span>
      ) : hint ? (
        <span className="mt-1 block text-xs text-reed">{hint}</span>
      ) : null}
    </label>
  );
}
