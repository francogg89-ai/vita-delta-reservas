import { useEffect } from 'react';
import { AMBIENTE, type Ambiente } from '../lib/ambiente';

// Banner de ambiente (sub-slice 3). Se monta arriba de toda la app en App.tsx,
// asi que es visible SIEMPRE, incluido antes del login. Ademas diferencia el
// titulo de la pestana.
//
//  'test'        -> aviso claro de ambiente de prueba (amarillo).
//  'desconocido' -> aviso DEFENSIVO: configuracion no reconocida, no operar (rojo).
//
// Barra fija de 2rem (h-8) que se compensa con pt-8 en el contenedor de App.tsx,
// para que el banner no tape el header ni el contenido.

const TITULOS: Record<Ambiente, string> = {
  test: 'TEST · Vita Delta - Portal operativo',
  desconocido: 'NO RECONOCIDO · Vita Delta - Portal',
};

export function BannerAmbiente() {
  useEffect(() => {
    document.title = TITULOS[AMBIENTE];
  }, []);

  if (AMBIENTE === 'test') {
    return (
      <div
        role="status"
        aria-live="polite"
        className="fixed inset-x-0 top-0 z-50 flex h-8 items-center justify-center bg-amber-400 px-3 text-center text-[11px] font-semibold uppercase tracking-wide text-amber-900 sm:text-xs"
      >
        Ambiente de prueba · TEST
      </div>
    );
  }

  // 'desconocido' (estado defensivo)
  return (
    <div
      role="alert"
      className="fixed inset-x-0 top-0 z-50 flex h-8 items-center justify-center bg-red-600 px-3 text-center text-[11px] font-semibold uppercase tracking-wide text-white sm:text-xs"
    >
      Ambiente no reconocido - no operar
    </div>
  );
}
