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
