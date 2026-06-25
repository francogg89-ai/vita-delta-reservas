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

/**
 * P-FE-01 - Socios en TEST. id_socio->nombre, CONFIRMADO por snapshot read-only en TEST
 * (2026-06-24: 1 Franco, 2 Rodrigo, 3 Remo, los tres activos). Solo valido en TEST (la
 * secuencia SERIAL difiere en DEV/OPS). NO portable: reemplazar por endpoint de catalogo
 * antes de OPS. Se usa en A11 cuando pagador_tipo='socio' (id_socio_pagador).
 */
export const SOCIOS_TEST: ReadonlyArray<{ id: number; nombre: string }> = [
  { id: 1, nombre: 'Franco' },
  { id: 2, nombre: 'Rodrigo' },
  { id: 3, nombre: 'Remo' },
];

/**
 * P-FE-01 / P-FE-05 - Zonas en TEST. id_zona->nombre, CONFIRMADO por snapshot read-only en TEST
 * (2026-06-24: 1 grandes, 2 chicas). Solo valido en TEST. NO portable: reemplazar por endpoint
 * de catalogo antes de OPS. Se usa en A11 cuando clase='D' (id_zona).
 */
export const ZONAS_TEST: ReadonlyArray<{ id: number; nombre: string }> = [
  { id: 1, nombre: 'grandes' },
  { id: 2, nombre: 'chicas' },
];

/** Motivos de bloqueo (A08, enum del wrapper crear_bloqueo). */
export const MOTIVOS_BLOQUEO: ReadonlyArray<{ valor: string; etiqueta: string }> = [
  { valor: 'mantenimiento', etiqueta: 'Mantenimiento' },
  { valor: 'uso_propio', etiqueta: 'Uso propio' },
  { valor: 'tormenta', etiqueta: 'Tormenta' },
  { valor: 'overbooking', etiqueta: 'Overbooking' },
  { valor: 'otro', etiqueta: 'Otro' },
];

/**
 * Medios de pago para A07 crear reserva (canal_pago_esperado + medio_pago, mismo enum).
 * Incluye mp_link (link de pago). Distinto de A10 (carga de saldo ya cobrado, sin mp_link).
 */
export const MEDIOS_PAGO_RESERVA: ReadonlyArray<{ valor: string; etiqueta: string }> = [
  { valor: 'efectivo', etiqueta: 'Efectivo' },
  { valor: 'transferencia_bancaria', etiqueta: 'Transferencia bancaria' },
  { valor: 'transferencia_mp', etiqueta: 'Transferencia Mercado Pago' },
  { valor: 'mp_link', etiqueta: 'Link de pago (Mercado Pago)' },
  { valor: 'cripto', etiqueta: 'Cripto' },
];

/** Medios de pago para A10 registrar cobro (saldo ya cobrado). SIN mp_link (D-C-50 / contrato). */
export const MEDIOS_PAGO_COBRO: ReadonlyArray<{ valor: string; etiqueta: string }> = [
  { valor: 'efectivo', etiqueta: 'Efectivo' },
  { valor: 'transferencia_bancaria', etiqueta: 'Transferencia bancaria' },
  { valor: 'transferencia_mp', etiqueta: 'Transferencia Mercado Pago' },
  { valor: 'cripto', etiqueta: 'Cripto' },
];

/** Pagador de gasto (A11) con etiquetas legibles. Valores = gastos_internos.pagador_tipo. */
export const PAGADORES_GASTO: ReadonlyArray<{ valor: string; etiqueta: string }> = [
  { valor: 'caja', etiqueta: 'Caja' },
  { valor: 'socio', etiqueta: 'Socio' },
];
