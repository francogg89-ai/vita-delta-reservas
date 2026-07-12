import type { ReactNode } from 'react';

/**
 * Contenedor de seccion: superficie blanca, borde `sand`, titulo en `reed` (D-FE-18, paleta
 * ink/river/sand/mist/reed).
 *
 * Componente NUEVO (D-FE-55). `CuentaCorrienteDetalle.tsx` (A28) tiene su propia copia local de
 * `Tarjeta` y NO se toca: es una pantalla cerrada y desplegada, y no hay bloqueo que justifique
 * abrirla. Deuda cosmetica registrada: dos copias conviven hasta que A28 se abra por otra razon.
 *
 * `acciones` permite colgar un control a la derecha del titulo (ej. un toggle de colapsado en
 * SB-UI-4). Es opcional y no lo usa el esqueleto.
 */
export function Tarjeta({
  titulo,
  acciones,
  children,
}: {
  titulo: string;
  acciones?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="rounded-2xl border border-sand bg-white p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs font-medium uppercase tracking-wide text-reed">{titulo}</p>
        {acciones}
      </div>
      <div className="mt-3">{children}</div>
    </section>
  );
}
