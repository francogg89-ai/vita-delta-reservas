// =============================================================================================
// Chip de NATURALEZA del dato. Modulo puro compartido: sin hooks, sin red, sin estado.
//
// Consolidacion de SB-UI-5. `Nat` / `NATURALEZA` vivian DUPLICADOS en `ContenidoAcumulados.tsx`
// (SB-UI-3) y `ContenidoFoto.tsx` (SB-UI-4). Las dos copias eran identicas salvo lineas en blanco,
// pero convivian con el riesgo de driftear: si maniana alguien cambia el color de [M] en una sola,
// la misma sigla significa dos cosas distintas en la misma pantalla.
//
// La consolidacion es un REFACTOR PURO: el output HTML renderizado es byte a byte identico al de
// las dos copias (verificado por SHA-256 del markup en SB-UI-5). No cambia ni una regla de render
// ni la semantica contable.
//
// SEMANTICA (cerrada; no se reabre):
//   F  congelado  el dato salio de la foto del cierre y no se recalcula.
//   V  vivo       el dato se lee del mayor en el momento de consultar.
//   M  mixto      una parte viene de la foto y la otra se recalcula contra el mayor.
//
// OJO: [F] califica importes, IDs y relaciones. NO califica los NOMBRES de socios y cabañas, que
// A30 resuelve con joins vivos al catalogo actual. Esa aclaracion la hace la nota al pie de cada
// pantalla, no el chip.
// =============================================================================================

export type Naturaleza = 'congelado' | 'vivo' | 'mixto';

export const NATURALEZA: Record<Naturaleza, { sigla: string; texto: string; clase: string }> = {
  congelado: {
    sigla: 'F',
    texto: 'Congelado en la foto del cierre',
    clase: 'border-sand bg-mist text-reed',
  },
  vivo: {
    sigla: 'V',
    texto: 'En vivo al momento de consultar',
    clase: 'border-river/30 bg-river-light text-river-dark',
  },
  mixto: {
    sigla: 'M',
    texto: 'Mixto: parte congelada, parte en vivo',
    clase: 'border-amber-200 bg-amber-50 text-amber-800',
  },
};

export function Nat({ n }: { n: Naturaleza }) {
  const c = NATURALEZA[n];
  return (
    <span
      role="img"
      aria-label={c.texto}
      title={c.texto}
      className={
        'inline-flex h-4 w-4 shrink-0 items-center justify-center rounded border ' +
        'text-[10px] font-semibold leading-none ' +
        c.clase
      }
    >
      {c.sigla}
    </span>
  );
}
