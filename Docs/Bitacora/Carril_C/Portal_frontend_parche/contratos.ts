// Tipos de las respuestas (`data`) de portal-api, espejando lo que devuelven los wrappers
// (SELECT + render). Fuente: CONTRATO_FRONTEND_PORTAL_v1.md + templates n8n. Crece por bloque.
// L-C-19: los BIGINT llegan ya normalizados a number. Montos: PESOS crudos como number (L-FE-02).

/** A03/A04 (D-FE-03): calendarios HTML temporal. data:{ formato:"html", html }. */
export interface CalendarioHtmlData {
  formato: string;
  html: string;
}

/** Huésped anidado (A05/A06/A12). email solo en A05/A12. */
export interface HuespedContacto {
  id_huesped?: number;
  nombre: string | null;
  telefono: string | null;
  email?: string | null;
}

// ----- A05 reserva.detalle → data:{ reserva, pagos } -----
export interface ReservaPago {
  id_pago: number;
  tipo: string;
  medio_pago: string | null;
  monto_esperado: number | null;
  monto_recibido: number | null;
  moneda: string;
  estado: string;
  es_automatico: boolean;
  validado_en: string | null;
  created_at: string;
}
export interface ReservaDetalle {
  id_reserva: number;
  id_cabana: number;
  cabana: string;
  fecha_checkin: string;
  fecha_checkout: string;
  hora_checkin: string | null;
  hora_checkout: string | null;
  personas: number;
  estado: string;
  canal_origen: string | null;
  monto_total: number | null;
  monto_sena: number | null;
  monto_saldo_registrado: number | null;
  total_pagado_confirmado: number | null;
  saldo_real: number | null;
  encargado_semana: string | null;
  mascotas: boolean;
  detalle_mascotas: string | null;
  ninos: number | null;
  notas: string | null;
  notas_reserva: string | null;
  created_at: string;
  huesped: HuespedContacto;
}
export interface ReservaDetalleData {
  reserva: ReservaDetalle;
  pagos: ReservaPago[];
}

// ----- A06 prereservas.activas → data:{ filas } -----
export interface PrereservaFila {
  id_pre_reserva: number;
  id_cabana: number;
  cabana: string;
  fecha_in: string;
  fecha_out: string;
  personas: number;
  estado: string;
  expira_en: string;
  minutos_para_vencer: number | null;
  monto_total: number | null;
  monto_sena: number | null;
  canal_origen: string | null;
  canal_pago_esperado: string | null;
  huesped: Pick<HuespedContacto, 'nombre' | 'telefono'>;
}
export interface PrereservasData {
  filas: PrereservaFila[];
}

// ----- A12 cobranza.saldos → data:{ filas } -----
export interface SaldoFila {
  id_reserva: number;
  id_cabana: number;
  cabana: string;
  fecha_checkin: string;
  fecha_checkout: string;
  monto_total: number | null;
  total_pagado_confirmado: number | null;
  saldo_real: number | null;
  huesped: HuespedContacto;
}
export interface SaldosData {
  filas: SaldoFila[];
}

// ----- A24 historico.reservas → data:{ filas, limit, offset, total } -----
// Paginado server-side; `total` = universo filtrado (COUNT(*) OVER()). saldo_real recomputado
// (mismo criterio que A12, puede ser negativo por sobrepago: en reporte se muestra crudo).
export interface HistoricoFila {
  id_reserva: number;
  id_cabana: number;
  cabana: string;
  fecha_checkin: string;
  fecha_checkout: string;
  personas: number;
  estado: string;
  canal_origen: string | null;
  monto_total: number | null;
  monto_sena: number | null;
  saldo_real: number | null;
  created_at: string;
  huesped: HuespedContacto;
}
export interface HistoricoData {
  filas: HistoricoFila[];
  limit: number;
  offset: number;
  total: number;
}

// ----- A25 ingresos.cobrados_periodo -----
// total_cobrado/total se calculan sobre CAJA (tipo seña+saldo). `filas` (paginadas) = caja.
// Agregados con forma [{ <clave>, monto, n }]. `otros_movimientos` = extra/ajuste/reembolso
// (NO suman al total_cobrado). Período echo-back (puede venir null).
export interface IngresoFila {
  id_pago: number;
  id_reserva: number | null;
  cabana: string | null;
  tipo: string;
  medio_pago: string;
  monto: number;
  created_at: string;
  validado_en: string | null;
}
export interface AgrTipo { tipo: string; monto: number; n: number }
export interface AgrMedio { medio_pago: string; monto: number; n: number }
export interface AgrMes { mes: string; monto: number; n: number }
export interface IngresosData {
  periodo_desde: string | null;
  periodo_hasta: string | null;
  total_cobrado: number;
  total: number;
  por_tipo: AgrTipo[];
  por_medio: AgrMedio[];
  por_mes: AgrMes[];
  otros_movimientos: { por_tipo: AgrTipo[] };
  filas: IngresoFila[];
  limit: number;
  offset: number;
}

// ----- A13 gastos.listado -----
// SIN campo `total`: el conteo del universo se deriva de Σ por_clase.n. `por_clase` = [{clase,monto,n}].
export interface GastoFila {
  id_gasto: number;
  periodo: string;
  fecha: string;
  clase: string;
  clase_sugerida: string | null;
  etiqueta: string;
  monto: number;
  moneda: string | null;
  pagador_tipo: string;
  id_socio_pagador: number | null;
  socio_pagador_nombre: string | null;
  id_zona: number | null;
  zona: string | null;
  id_cabana: number | null;
  cabana: string | null;
  medio_pago: string | null;
  comentario: string | null;
  comprobante_url: string | null;
  creado_por: string;
  created_at: string;
}
export interface AgrClase { clase: string; monto: number; n: number }
export interface GastosData {
  periodo_desde: string | null;
  periodo_hasta: string | null;
  total_gastos: number;
  por_clase: AgrClase[];
  filas: GastoFila[];
  limit: number;
  offset: number;
}

// ===== Escrituras: data de RESPUESTA (forma EXACTA leida de los wrappers/funcion) =====
// A07/A08/A10: del nodo `render`/routers del wrapper. A11: de la funcion portal_cargar_gasto_interno.
// Montos en pesos (L-FE-02). IDs BIGINT ya normalizados a number.

/** A07 reserva.crear_manual. `idempotent_match:true` => cayo sobre una reserva ya existente. */
export interface CrearReservaData {
  id_reserva: number;
  id_pre_reserva: number;
  id_huesped: number;
  idempotent_match: boolean;
}

/** A08 bloqueo.crear_manual. */
export interface CrearBloqueoData {
  id_bloqueo: number;
  id_cabana: number;
  tipo_bloqueo: string;
}

/**
 * A10 cobranza.registrar_saldo (W10) — DEPRECATED en el frontend (B5). El portal ya no llama
 * registrar_saldo; el tipo queda solo por referencia historica (W10 sigue desplegado en backend,
 * deprecated-in-place). B5 usa RegistrarCobroData. `saldo_real_actual` recomputado post-commit.
 */
export interface RegistrarSaldoData {
  id_pago: number;
  estado_pago: string;
  idempotent_match: boolean;
  saldo_real_actual: number | null;
  saldo_real_previo?: number | null;
}

/** Subtipo de la porcion de transferencia (contrato A10-MP): solo `bancaria` o `mp`. */
export type SubtipoTransferencia = 'bancaria' | 'mp';

/** A10-MP `cobranza.registrar_cobro` -> `detalle` (eco de `derivar`, no autoridad de montos). */
export interface RegistrarCobroDetalle {
  efectivo: number;
  transferencia: number;
  /** null si `transferencia == 0` (cierre A10-MP §4.5). */
  subtipo_transferencia: SubtipoTransferencia | null;
  otros: number;
  recargo: number;
}

/**
 * A10-MP `cobranza.registrar_cobro` (cobranza multi-porcion + recargo 5%). Forma EXACTA del
 * `response.data` (cierre A10-MP §4.5). `suma_saldo`/`suma_extra`/`saldo_real_actual` son
 * autoritativos (recomputados post-COMMIT por PG_verif_post); `detalle` es eco de `derivar`.
 * Contabilidad (D-C-68): las lineas `saldo` bajan saldo y entran al 25%; el `extra` (recargo) NO
 * baja saldo (no se resta del saldo) pero SI es caja percibida. `saldada` = saldo_real_actual === 0.
 */
export interface RegistrarCobroData {
  source_event: string;
  cant_lineas: number;
  suma_saldo: number;
  suma_extra: number;
  total_cobrado: number;
  saldo_anterior: number;
  saldo_real_actual: number;
  saldada: boolean;
  idempotent_match: boolean;
  detalle: RegistrarCobroDetalle;
}

/** A11 cargar.gasto_interno. OJO: la clave es `idempotente` (no `idempotent_match`). */
export interface CargarGastoData {
  id_gasto: number;
  idempotente: boolean;
}

// ----- A26 disponibilidad.cabana (lectura preventiva, UX de A07/A08) -----
// data:{ dias } con UNA fila por NOCHE en [fecha_desde, fecha_hasta) (excluye fecha_hasta).
// Cabana inexistente/inactiva -> error no_encontrado. Payload invalido -> payload_invalido.
// hora_checkin_base/hora_checkout_base llegan por contrato pero NO se usan en este bloque
// (sin recambio ni validacion horaria).
export type EstadoDisponibilidad = 'disponible' | 'checkout_disponible' | 'ocupada' | 'bloqueada';
export interface DiaDisponibilidad {
  fecha: string;
  estado: EstadoDisponibilidad;
  id_cabana: number | null;
  hora_checkin_base: string | null;
  hora_checkout_base: string | null;
}
export interface DisponibilidadCabanaData {
  dias: DiaDisponibilidad[];
}
