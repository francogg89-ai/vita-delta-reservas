// Constantes de presentación del portal.

/** Floor contable duro (D-NEG-02 / D-C-11/20): no hay datos ni filtros antes de esta fecha. */
export const FLOOR_CONTABLE = '2026-07-01';

/**
 * P-FE-01 — Cabañas en TEST. Mapeo id_cabana→nombre SOLO válido en TEST (IDs 1–5, secuencia
 * fresca; en DEV/OPS la secuencia SERIAL difiere → IDs distintos, p. ej. 17–21 en DEV). NO
 * portable: reemplazar por un endpoint de catálogo del backend antes de promover a OPS. Las
 * filas igual muestran el nombre correcto vía el campo `cabana` del backend, así que esta
 * constante solo afecta las ETIQUETAS del filtro de cabaña.
 */
export const CABANAS_TEST: ReadonlyArray<{ id: number; nombre: string }> = [
  { id: 1, nombre: 'Bamboo' },
  { id: 2, nombre: 'Madre Selva' },
  { id: 3, nombre: 'Arrebol' },
  { id: 4, nombre: 'Guatemala' },
  { id: 5, nombre: 'Tokio' },
];

/** Estados de reserva (enum del contrato/wrapper A24; portable). */
export const ESTADOS_RESERVA: readonly string[] = [
  'confirmada',
  'activa',
  'completada',
  'cancelada',
  'cancelada_con_cargo',
  'conflicto_pendiente',
];

/** Floor contable como mes 'YYYY-MM' (para inputs type=month en A25/A13). */
export const FLOOR_MES = '2026-07';

/**
 * Clases de gasto (gastos_internos.clase, enum {A,C,D,E}). Alcance: A/C sin zona ni cabaña;
 * D = por zona; E = por cabaña. Etiquetas legibles para el filtro y el desglose.
 */
export const CLASES_GASTO: ReadonlyArray<{ valor: string; etiqueta: string }> = [
  { valor: 'A', etiqueta: 'A · Común (todos)' },
  { valor: 'C', etiqueta: 'C · Común operativo' },
  { valor: 'D', etiqueta: 'D · Por zona' },
  { valor: 'E', etiqueta: 'E · Por cabaña' },
];

/** Tipo de pagador del gasto (gastos_internos.pagador_tipo). */
export const PAGADOR_TIPOS: readonly string[] = ['socio', 'caja'];
