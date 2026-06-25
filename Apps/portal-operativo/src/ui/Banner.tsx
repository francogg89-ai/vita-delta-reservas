import type { ReactNode } from 'react';

export type TonoBanner = 'aviso' | 'error' | 'incierto' | 'info';

const TONOS: Record<TonoBanner, string> = {
  aviso: 'border-amber-200 bg-amber-50 text-amber-800',
  error: 'border-red-200 bg-red-50 text-red-800',
  incierto: 'border-amber-200 bg-amber-50 text-amber-800',
  info: 'border-sand bg-mist text-ink',
};

/**
 * Banner inline para feedback de escritura no-exito: `conflicto` (aviso/error), `estado_incierto`
 * (incierto, con accion companion), o info. `acciones` = botones/links que pasa la pantalla (ej.
 * "Ver calendario operativo" en A08, accion PRINCIPAL ante incierto, D-FE-22). role="alert" para
 * que el lector de pantalla lo anuncie.
 */
export function Banner({
  tono,
  titulo,
  children,
  acciones,
}: {
  tono: TonoBanner;
  titulo?: string;
  children: ReactNode;
  acciones?: ReactNode;
}) {
  return (
    <div role="alert" className={'rounded-2xl border px-5 py-4 ' + TONOS[tono]}>
      {titulo && <p className="font-medium">{titulo}</p>}
      <div className={titulo ? 'mt-1 text-sm' : 'text-sm'}>{children}</div>
      {acciones && <div className="mt-3 flex flex-wrap gap-2">{acciones}</div>}
    </div>
  );
}
