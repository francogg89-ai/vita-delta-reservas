import type { ReactNode } from 'react';

/**
 * Tarjeta de exito de una escritura (D-FE-25). `titulo` (ej. "Reserva creada #12"), `children`
 * = detalle opcional (ej. saldo_real_actual en A10), `acciones` = fila de botones/links que pasa
 * la pantalla (ej. Ver detalle / Crear otra). Verde con rol de status para lectores de pantalla.
 */
export function TarjetaExito({
  titulo,
  children,
  acciones,
}: {
  titulo: string;
  children?: ReactNode;
  acciones?: ReactNode;
}) {
  return (
    <div role="status" className="rounded-2xl border border-green-200 bg-green-50 px-6 py-5">
      <p className="font-medium text-green-800">{titulo}</p>
      {children && <div className="mt-1 text-sm text-green-900">{children}</div>}
      {acciones && <div className="mt-4 flex flex-wrap gap-2">{acciones}</div>}
    </div>
  );
}
