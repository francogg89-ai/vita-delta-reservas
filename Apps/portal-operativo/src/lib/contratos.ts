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

// A27 (cuenta_corriente.al_dia) -- saldo de socios acumulado EN VIVO desde el piso contable.
// Montos NUMERICOS crudos (pesos, no centavos). null solo por robustez (el backend siempre
// devuelve numero). liquidacion_mes_en_curso es PROVISORIA (el mes no cerro).
export interface CuentaCorrienteFila {
  id_socio: number;
  socio: string;
  liquidacion_meses_previos: number | null;
  liquidacion_mes_en_curso: number | null;
  reembolsos_acumulados: number | null;
  movimientos: number | null;
  saldo_al_dia: number | null;
}
export interface CuentaCorrienteData {
  filas: CuentaCorrienteFila[];
}

// A28 (cuenta_corriente.detalle) -- drill-down por mes. Espejo del jsonb de
// cuenta_corriente_detalle. Montos NUMERICOS crudos; null solo por robustez.
export interface CascadaPaso {
  paso: number;
  concepto: string;
  id_socio: number | null;
  socio: string | null;
  monto: number | null;
}
export interface MatrizSocioDetalle {
  id_socio: number;
  socio: string;
  valor_socio: number | null;
  valor_pool: number | null;
  participacion: number | null;
}
export interface MatrizCabanaDetalle {
  id_cabana: number;
  cabana: string;
  valor_relativo: number | null;
  id_socio: number;
  beneficiario: string;
  participa: boolean;
}
export interface IncidenciaGastoFila {
  id_gasto: number;
  clase: string;
  etiqueta: string;
  monto: number | null;
  destino: string;
  id_socio: number | null;
  socio: string | null;
  monto_incidido: number | null;
  regla: string;
}
export interface GastoSinIncidenciaFila {
  id_gasto: number;
  clase: string;
  etiqueta: string;
  monto: number | null;
  motivo: string;
}
export interface CuentaCorrienteDetalleData {
  mes: string;
  cascada: CascadaPaso[];
  matriz: MatrizSocioDetalle[];
  matriz_cabanas: MatrizCabanaDetalle[];
  incidencias: IncidenciaGastoFila[];
  gastos_sin_incidencia: GastoSinIncidenciaFila[];
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

/**
 * A29 cuenta_corriente.retirar (retiro socio contra saldo vivo). Forma EXACTA del `data` de exito
 * de portal_registrar_retiro: { id_movimiento, idempotente } (espeja CargarGastoData: la clave es
 * `idempotente`). El saldo nuevo NO viene aca: se reconsulta L1 (cuenta_corriente.al_dia).
 */
export interface RegistrarRetiroData {
  id_movimiento: number;
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

// ===== A30 / A31 -- L3 historico de cuenta corriente (socio-only, read-only) =====
//
// Espejo EXACTO del jsonb de `cuenta_corriente_historico(date)` y
// `cuenta_corriente_historico_acumulados()` (canonico 6B_SCHEMA_SQL.md v1.12.0).
//
// Los wrappers n8n de A30/A31 son PASSTHROUGH PURO: el nodo de render hace
// `return [{ json: { ok: true, data: <jsonb> } }]`, sin normalizar ni renombrar claves (a
// diferencia de A27/A28, que si tienen capa de render). Por eso estos tipos reflejan el
// `jsonb_build_object` de la funcion SQL tal cual.
//
// Convenciones (matriz de nullabilidad, SB-UI-1):
//   - `jsonb_build_object` SIEMPRE emite la clave, aunque el valor sea NULL -> aparece como `null`,
//     nunca ausente. Por eso NO hay ningun campo opcional (`?:`): todo es `T` o `T | null`.
//   - Los `date` / `timestamptz` viajan ANIDADOS dentro del jsonb -> el driver hace `JSON.parse`
//     del jsonb y NO aplica su parser de tipo `date`: llegan como string ('YYYY-MM-DD' / ISO),
//     nunca como `Date` de JS. Por eso el round-trip del periodo se compara con `===` de strings.
//   - Montos: PESOS crudos como number (L-FE-02, nunca /100). BIGINT -> number (L-C-19).
//   - La nullabilidad es la del DDL, no defensiva: NO se replica el patron de A27 (que tipa los
//     montos `number | null` "por robustez"). Para A30/A31 el contrato es exacto.

/** Motivo por el que el detalle fino no esta disponible. `null` solo en E1 (foto completa). */
export type DetalleMotivo = 'sin_foto_vigente' | 'foto_pre_extension';

/** Clase de gasto congelada (CHECK chk_lgasto_clase). */
export type ClaseGasto = 'A' | 'C' | 'D' | 'E';

/** Motivo de "sin incidencia" congelado (CHECK chk_lgasto_motivo_dom). */
export type MotivoSinIncidencia = 'pool_vacio' | 'zona_sin_activas';

/** Destino de la incidencia congelada (CHECK chk_linc_destino). */
export type DestinoIncidencia = 'pool_pre_operativo' | 'socio';

/** Tipo de movimiento del mayor (CHECK chk_mov_tipo). */
export type TipoMovimiento =
  | 'retiro'
  | 'adelanto'
  | 'ajuste_manual'
  | 'retribucion_operativo'
  | 'ajuste_arranque'
  | 'reversa';

/** Estado de conciliacion de la retribucion operativa (CASE exhaustivo de la funcion). */
export type EstadoRetribucion =
  | 'SIN_CALCULADO'
  | 'PENDIENTE'
  | 'CONCILIADO'
  | 'PARCIAL'
  | 'EXCEDIDO';

/** Linaje de supersesion. Invariante: `es_raiz === (id_liquidacion_supersede === null)`. */
export interface LinajeFoto {
  es_raiz: boolean;
  id_liquidacion_supersede: number | null;
}

/** CONGELADO. Cabecera de la foto (liquidaciones_periodo). `null` sii `sin_foto`. */
export interface CabeceraFoto {
  id_liquidacion: number;
  periodo: string;
  pct_operativo: number;
  creado_por: string;
  created_at: string;
  comentario: string | null;
  linaje: LinajeFoto;
}

/** CONGELADO. liquidacion_cascada (pasos 1-8 agregados). Ordenada por `paso`. */
export interface CascadaFoto {
  paso: number;
  concepto: string;
  monto: number;
}

/** CONGELADO. liquidacion_socio (resultado por socio de la foto). */
export interface SocioFoto {
  id_socio: number;
  socio: string;
  saldo_bruto: number;
  gastos_d: number;
  gastos_e: number;
  saldo_final: number;
  desembolsado_periodo: number;
}

/** CONGELADO (detalle fino). `[]` en E2 (pre-extension) y E3 (sin foto). */
export interface ParticipacionFoto {
  id_cabana: number;
  cabana: string;
  valor_relativo: number;
  id_socio_beneficiario: number;
  beneficiario: string;
  participa: boolean;
}

/**
 * CONGELADO (detalle fino). Foto fiel de `gastos_internos`. `[]` en E2/E3.
 *
 * OJO: trae `id_zona` / `id_cabana` pero NO sus nombres (a diferencia de A13, que es la lectura
 * viva y si resuelve los nombres por join). La UI muestra el ID crudo: resolverlo con
 * CABANAS_TEST / ZONAS_TEST seria NO portable a OPS (P-FE-01).
 *
 * Invariantes del DDL: `id_zona !== null` sii `clase === 'D'`; `id_cabana !== null` sii
 * `clase === 'E'`; `id_socio_pagador !== null` sii `pagador_tipo === 'socio'`;
 * `sin_incidencia === (motivo_sin_incidencia !== null)`.
 */
export interface GastoFoto {
  id_gasto: number;
  fecha: string;
  clase: ClaseGasto;
  clase_sugerida: ClaseGasto | null;
  etiqueta: string;
  monto: number;
  moneda: 'ARS';
  id_zona: number | null;
  id_cabana: number | null;
  pagador_tipo: 'socio' | 'caja';
  id_socio_pagador: number | null;
  medio_pago: string | null;
  comentario: string | null;
  comprobante_url: string | null;
  creado_por: string;
  created_at: string;
  sin_incidencia: boolean;
  motivo_sin_incidencia: MotivoSinIncidencia | null;
}

/**
 * CONGELADO (detalle fino). `[]` en E2/E3.
 * LEFT JOIN a socios: `socio` es `null` sii `id_socio` es `null`, y eso ocurre sii
 * `destino === 'pool_pre_operativo'` (CHECK chk_linc_destino_socio).
 */
export interface IncidenciaFoto {
  id_gasto: number;
  seq: number;
  destino: DestinoIncidencia;
  id_socio: number | null;
  socio: string | null;
  monto_incidido: number;
  regla: string;
}

/**
 * VIVO (D-CC-34). Lectura del mayor ventaneada por FECHA en [mes, mes+1). NO es parte de la foto.
 * En E3 (sin foto) el contrato devuelve `[]`: la rama `sin_foto` de la funcion no lee el mayor.
 *
 * OJO: la ventana es por `fecha`, mientras que `retribucion_operativo.asignado` filtra por
 * `periodo`. Un movimiento `retribucion_operativo` con periodo de julio y fecha de agosto aparece
 * en la lista de AGOSTO y cuenta en la conciliacion de JULIO: esta lista NO explica 1:1 la
 * conciliacion de la retribucion.
 */
export interface MovimientoFoto {
  id_movimiento: number;
  id_socio: number;
  socio: string;
  fecha: string;
  tipo: TipoMovimiento;
  monto: number;
  medio_pago: string | null;
  comentario: string | null;
  periodo: string | null;
}

/**
 * CONGELADO (derivado de `participacion`, filtro `participa = true`).
 * Puede ser `[]` AUN con `detalle_disponible: true` (si ninguna cabana participo ese mes) ->
 * es un vacio legitimo, no un error.
 */
export interface MatrizSocioFoto {
  id_socio: number;
  socio: string;
  valor_socio: number;
  valor_pool: number;
  participacion: number;
}

/**
 * CONGELADO (derivado de `gastos`, filtro `sin_incidencia = true`).
 * `motivo` NO es nullable en este subconjunto: el CHECK garantiza
 * `sin_incidencia === (motivo_sin_incidencia !== null)`.
 */
export interface GastoSinIncidenciaFoto {
  id_gasto: number;
  clase: ClaseGasto;
  etiqueta: string;
  monto: number;
  motivo: MotivoSinIncidencia;
}

/**
 * MIXTO. `calculado` sale del paso 4 CONGELADO de la cascada; `asignado` se recalcula al consultar
 * contra `movimientos_socio` VIVOS (tipo `retribucion_operativo` + reversas, filtrados por
 * `periodo`). `diferencia` y `estado` derivan de ambos.
 * `null` sii `sin_foto`: con foto SIEMPRE viene (la funcion es un SELECT escalar de 1 fila).
 */
export interface RetribucionOperativoFoto {
  periodo: string;
  calculado: number;
  asignado: number;
  diferencia: number;
  estado: EstadoRetribucion;
}

/**
 * A30 `cuenta_corriente.historico` -> data. 14 claves top-level, TODAS siempre presentes.
 * Payload: `{ mes: 'YYYY-MM-01' }` (dia 01 obligatorio, >= piso contable).
 * `sin_foto: true` y `detalle_disponible: false` son ok:true (D-CC-44), NUNCA `no_encontrado`.
 */
export interface HistoricoMesData {
  sin_foto: boolean;
  detalle_disponible: boolean;
  detalle_motivo: DetalleMotivo | null;
  periodo: string;
  cabecera: CabeceraFoto | null;
  cascada: CascadaFoto[];
  socios: SocioFoto[];
  participacion: ParticipacionFoto[];
  gastos: GastoFoto[];
  incidencias: IncidenciaFoto[];
  movimientos: MovimientoFoto[];
  matriz_por_socio: MatrizSocioFoto[];
  gastos_sin_incidencia: GastoSinIncidenciaFoto[];
  retribucion_operativo: RetribucionOperativoFoto | null;
}

/** Desglose de `gastos_acumulados`. Identidad exacta: a_paso2 + c_paso7 + d_e_socios === total. */
export interface GastosDesgloseAcum {
  a_paso2: number;
  c_paso7: number;
  d_e_socios: number;
}

/**
 * FOTOS, salvo `retiros_acumulados`, que es VIVO: suma TODOS los movimientos tipo `retiro` del
 * mayor, SIN ventana por foto vigente.
 *
 * OJO: `retiros_acumulados` NO es la suma de `evolucion[].retiros_mes`. Un retiro con fecha en un
 * mes SIN foto vigente cuenta en el total y no aparece en ninguna fila de la evolucion.
 * (Signo: los retiros son negativos por CHECK chk_mov_signo_debe.)
 */
export interface TotalesAcum {
  ingresos_acumulados: number;
  gastos_acumulados: number;
  gastos_desglose: GastosDesgloseAcum;
  utilidad_acumulada: number;
  repartos_acumulados: number;
  retiros_acumulados: number;
}

/**
 * Una fila por foto vigente, ordenada ASC por `periodo` (ORDER BY del jsonb_agg).
 * `retiros_mes` es VIVO (ventana [periodo, periodo+1) por fecha); el resto sale de la foto.
 */
export interface EvolucionAcum {
  periodo: string;
  id_liquidacion: number;
  ingresos: number;
  gastos: number;
  utilidad: number;
  repartos: number;
  retiros_mes: number;
}

/**
 * Una fila por socio SIEMPRE (`socios CROSS JOIN LATERAL saldo_corriente_socio`), exista o no una
 * foto vigente. Es decir: `sin_datos: true` NO implica `saldos_por_socio: []`.
 *
 * Los 4 componentes son NON-NULL: `saldo_corriente_socio` es un UNION ALL de 4 constantes con
 * `COALESCE(..., 0)`, asi que el `MAX(...) FILTER (WHERE orden = N)` siempre encuentra su fila.
 * Naturaleza: `resultado_liquidacion` y `reembolso_desembolso` salen de las fotos;
 * `movimientos` es VIVO; `saldo_vivo` es la suma (mixto).
 */
export interface SaldoSocioAcum {
  id_socio: number;
  socio: string;
  resultado_liquidacion: number;
  reembolso_desembolso: number;
  movimientos: number;
  saldo_vivo: number;
}

/**
 * Integridad. `fotos_pre_piso` y `movimientos_pre_piso` DEBEN ser 0 (D-NEG-02, piso 2026-07-01).
 * Si no lo son, la UI lo AVISA sin filtrar ni recalcular: esas fotos/movimientos SI estan incluidos
 * en la evolucion, en los totales y en los saldos por socio (D-CC-37: el piso no se doble-filtra).
 * Invariante: `fotos_vigentes === evolucion.length`.
 */
export interface MetaAcum {
  fotos_vigentes: number;
  fotos_pre_piso: number;
  movimientos_pre_piso: number;
}

/**
 * A31 `cuenta_corriente.historico_acumulados` -> data. 6 claves top-level, TODAS siempre presentes.
 * Payload: `{}` VACIO ESTRICTO (`payloadVacioEstricto` del gateway rechaza cualquier clave).
 * `sin_datos: true` es ok:true (D-CC-44) e implica `evolucion: []` y totales de foto en 0, pero
 * NO implica `saldos_por_socio: []` ni `retiros_acumulados === 0`.
 * Invariante: `sin_datos === (meta.fotos_vigentes === 0)`.
 */
export interface HistoricoAcumuladosData {
  sin_datos: boolean;
  piso: string;
  totales: TotalesAcum;
  evolucion: EvolucionAcum[];
  saldos_por_socio: SaldoSocioAcum[];
  meta: MetaAcum;
}
