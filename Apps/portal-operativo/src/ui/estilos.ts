// Clases Tailwind compartidas de los formularios de escritura (B2-B5). Centralizadas para
// no driftear entre pantallas. Paleta ink/river/sand/mist/reed. Mobile-first: controles de
// ancho completo y text-base (16px) para no disparar el zoom de iOS al enfocar.

/** input / select / textarea estandar. Ancho completo (un campo por fila en celular). */
export const controlClass =
  'mt-1 w-full rounded-lg border border-sand px-3 py-2 text-base text-ink outline-none ' +
  'focus:border-river disabled:cursor-not-allowed disabled:bg-mist disabled:text-reed';

/** Boton primario (accion principal). Full-width en mobile, auto en >=sm. */
export const botonPrimario =
  'inline-flex items-center justify-center gap-2 rounded-lg bg-river px-4 py-2.5 text-sm ' +
  'font-medium text-white transition hover:bg-river-dark disabled:cursor-not-allowed disabled:opacity-40';

/** Boton secundario (accion alternativa / navegacion). */
export const botonSecundario =
  'inline-flex items-center justify-center gap-2 rounded-lg border border-sand px-4 py-2.5 ' +
  'text-sm text-ink transition hover:bg-mist disabled:cursor-not-allowed disabled:opacity-40';
