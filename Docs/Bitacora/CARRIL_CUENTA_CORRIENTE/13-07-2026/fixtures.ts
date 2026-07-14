// =============================================================================================
// SB-UI-6 -- Fixtures F1..F19 del harness de QA.
//
// __VITA_QA_FIXTURE_DO_NOT_SHIP__
//
// Ese marcador es un CANARIO. Vive solo aca. Si alguna vez aparece en `dist/`, significa que el
// harness se filtro al bundle de produccion y hay que frenar el deploy. El chequeo esta en
// `qa/probes.ts` (grep sobre dist) y en el runsheet.
//
// El harness NO entra al grafo de `vite build`: el build parte de `index.html` en la raiz, que
// solo alcanza `src/`. Nada de `src/` importa nada de `qa/` (verificado por probe).
//
// Los fixtures estan tipados contra el contrato REAL (`src/lib/contratos.ts`). No hay `as any`:
// si el contrato cambia, esto deja de compilar, que es exactamente lo que queremos.
// =============================================================================================

import type {
  GastoFoto,
  HistoricoAcumuladosData,
  HistoricoMesData,
  MovimientoFoto,
} from '../src/lib/contratos';

export const MARCADOR_QA = '__VITA_QA_FIXTURE_DO_NOT_SHIP__';

// ---------------------------------------------------------------------------------------------
// Helpers de construccion. Todo parte de una base valida y se desvia con un override explicito,
// para que cada fixture diga UNA sola cosa.
// ---------------------------------------------------------------------------------------------

const NOMBRE: Record<number, string> = { 2: 'Rodrigo', 3: 'Remo', 4: 'Franco' };
const CABANA: Record<number, string> = {
  1: 'Bamboo',
  2: 'Madre Selva',
  3: 'Arrebol',
  4: 'Guatemala',
  5: 'Tokio',
};

export function gasto(o: Partial<GastoFoto> = {}): GastoFoto {
  return {
    id_gasto: 42,
    fecha: '2026-07-12',
    clase: 'D',
    clase_sugerida: null,
    etiqueta: 'Mantenimiento de bomba',
    monto: 45000,
    moneda: 'ARS',
    id_zona: 3,
    id_cabana: null,
    pagador_tipo: 'socio',
    id_socio_pagador: 2,
    medio_pago: 'transferencia',
    comentario: null,
    comprobante_url: null,
    creado_por: 'Franco',
    // 21:35Z = 18:35 hora AR (UTC-3).
    created_at: '2026-07-12T21:35:00Z',
    sin_incidencia: false,
    motivo_sin_incidencia: null,
    ...o,
  };
}

export function movimiento(o: Partial<MovimientoFoto> = {}): MovimientoFoto {
  return {
    id_movimiento: 1,
    id_socio: 2,
    socio: 'Rodrigo',
    fecha: '2026-07-15',
    tipo: 'retribucion_operativo',
    monto: -30000,
    medio_pago: 'transferencia',
    comentario: null,
    periodo: '2026-07-01',
    ...o,
  };
}

/** E1 canonico: foto vigente con detalle disponible. Base de casi todos los fixtures de A30. */
export function fotoE1(o: Partial<HistoricoMesData> = {}): HistoricoMesData {
  return {
    sin_foto: false,
    detalle_disponible: true,
    detalle_motivo: null,
    periodo: '2026-07-01',
    cabecera: {
      id_liquidacion: 12,
      periodo: '2026-07-01',
      pct_operativo: 0.25, // FRACCION 0..1 -> se muestra 25,00%, nunca "$ 0,25"
      creado_por: 'franco@vitadelta',
      created_at: '2026-08-05T02:30:00Z',
      comentario: 'Cierre de julio con ajuste por la bomba',
      linaje: { es_raiz: false, id_liquidacion_supersede: 7 },
    },
    cascada: [1, 2, 3, 4, 5, 6, 7, 8].map((paso) => ({
      paso,
      concepto: `Concepto del paso ${paso}`,
      monto: 100000 - paso * 9000,
    })),
    socios: [2, 3, 4].map((id) => ({
      id_socio: id,
      socio: NOMBRE[id],
      saldo_bruto: 120000,
      gastos_d: -12000,
      gastos_e: -8000,
      saldo_final: 100000,
      desembolsado_periodo: 45000,
    })),
    participacion: [1, 2, 3, 4, 5].map((c) => ({
      id_cabana: c,
      cabana: CABANA[c],
      valor_relativo: 3, // NO es plata: SUM(cabanas.valor_relativo)
      id_socio_beneficiario: 2 + (c % 3),
      beneficiario: NOMBRE[2 + (c % 3)],
      participa: true,
    })),
    gastos: [gasto({ id_gasto: 42 })],
    incidencias: [
      {
        id_gasto: 42,
        seq: 1,
        destino: 'socio',
        id_socio: 2,
        socio: 'Rodrigo',
        monto_incidido: 45000,
        regla: 'zona_prorrateo_valor_relativo',
      },
    ],
    movimientos: [movimiento()],
    matriz_por_socio: [2, 3, 4].map((id) => ({
      id_socio: id,
      socio: NOMBRE[id],
      valor_socio: 5, // NO es plata
      valor_pool: 15, // NO es plata
      participacion: 0.3333, // FRACCION 0..1
    })),
    gastos_sin_incidencia: [],
    retribucion_operativo: {
      periodo: '2026-07-01',
      calculado: 100000, // <- congelado (foto)
      asignado: 80000, // <- VIVO (movimientos_socio del periodo)
      diferencia: 20000,
      estado: 'PARCIAL',
    },
    ...o,
  };
}

export function acum(o: Partial<HistoricoAcumuladosData> = {}): HistoricoAcumuladosData {
  return {
    sin_datos: false,
    piso: '2026-07-01',
    totales: {
      ingresos_acumulados: 5000000,
      gastos_acumulados: 1200000,
      // Identidad: a_paso2 + c_paso7 + d_e_socios === gastos_acumulados
      gastos_desglose: { a_paso2: 400000, c_paso7: 300000, d_e_socios: 500000 },
      utilidad_acumulada: 3800000,
      repartos_acumulados: 900000,
      retiros_acumulados: 700000,
    },
    evolucion: ['2026-07-01', '2026-08-01', '2026-09-01'].map((periodo, i) => ({
      periodo,
      id_liquidacion: 12 + i,
      ingresos: 1600000,
      gastos: 400000,
      utilidad: 1200000,
      repartos: 300000,
      retiros_mes: -230000,
    })),
    saldos_por_socio: [2, 3, 4].map((id) => ({
      id_socio: id,
      socio: NOMBRE[id],
      resultado_liquidacion: 900000,
      reembolso_desembolso: 120000,
      movimientos: -300000,
      saldo_vivo: 720000,
    })),
    meta: { fotos_vigentes: 3, fotos_pre_piso: 0, movimientos_pre_piso: 0 },
    ...o,
  };
}

// =============================================================================================
// F1..F9 -- A30
// =============================================================================================

/** F1 -- E1 completo: las 6 secciones, todas las tablas pobladas. */
export const F1 = fotoE1();

/** F2 -- E2 (`foto_pre_extension`): hay cabecera y cascada, NO hay detalle fino. */
export const F2 = fotoE1({
  detalle_disponible: false,
  detalle_motivo: 'foto_pre_extension',
  participacion: [],
  gastos: [],
  incidencias: [],
  matriz_por_socio: [],
  gastos_sin_incidencia: [],
});

/** F3 -- E3 (`sin_foto_vigente`): no hay foto. Cabecera y retribucion en null (T6/T7). */
export const F3 = fotoE1({
  sin_foto: true,
  detalle_disponible: false,
  detalle_motivo: 'sin_foto_vigente',
  cabecera: null,
  cascada: [],
  socios: [],
  participacion: [],
  gastos: [],
  incidencias: [],
  movimientos: [],
  matriz_por_socio: [],
  gastos_sin_incidencia: [],
  retribucion_operativo: null,
});

/**
 * F4 -- Matriz VACIA LEGITIMA: `matriz_por_socio: []` con `detalle_disponible: true`.
 * El SQL filtra `WHERE valor_pool > 0`, asi que el vacio NO es un error ni una inconsistencia.
 */
export const F4 = fotoE1({ matriz_por_socio: [] });

/** F5 -- Comprobantes PELIGROSOS. Ninguno debe emitir `href`. */
export const F5 = fotoE1({
  gastos: [
    gasto({ id_gasto: 51, etiqueta: 'XSS por protocolo', comprobante_url: 'javascript:alert(document.domain)' }),
    gasto({ id_gasto: 52, etiqueta: 'XSS mayusculas', comprobante_url: 'JavaScript:alert(1)' }),
    gasto({ id_gasto: 53, etiqueta: 'XSS con newline embebido', comprobante_url: 'java\nscript:alert(1)' }),
    gasto({ id_gasto: 54, etiqueta: 'Data URI', comprobante_url: 'data:text/html;base64,PHNjcmlwdD4=' }),
    gasto({ id_gasto: 55, etiqueta: 'VBScript', comprobante_url: 'vbscript:msgbox(1)' }),
    gasto({ id_gasto: 56, etiqueta: 'Archivo local', comprobante_url: 'file:///etc/passwd' }),
    gasto({ id_gasto: 57, etiqueta: 'FTP', comprobante_url: 'ftp://x.com/a' }),
    gasto({ id_gasto: 58, etiqueta: 'Ruta relativa', comprobante_url: '/comprobantes/58.pdf' }),
    gasto({ id_gasto: 59, etiqueta: 'Protocol-relative', comprobante_url: '//evil.com/x' }),
    gasto({ id_gasto: 60, etiqueta: 'URL invalida', comprobante_url: 'no es una url' }),
  ],
  incidencias: [],
  gastos_sin_incidencia: [],
});

/** F6 -- Comprobantes VALIDOS http/https. Deben enlazar con target=_blank + rel=noopener. */
export const F6 = fotoE1({
  gastos: [
    gasto({ id_gasto: 61, etiqueta: 'https', comprobante_url: 'https://vita.delta/c/61.pdf' }),
    gasto({ id_gasto: 62, etiqueta: 'http', comprobante_url: 'http://vita.delta/c/62.pdf' }),
    gasto({ id_gasto: 63, etiqueta: 'https mayusculas', comprobante_url: 'HTTPS://VITA.DELTA/c/63' }),
    gasto({ id_gasto: 64, etiqueta: 'sin comprobante', comprobante_url: null }),
  ],
  incidencias: [],
  gastos_sin_incidencia: [],
});

/**
 * F7 -- Movimientos por FECHA vs conciliacion por PERIODO.
 * `retribucion_operativo.asignado` se calcula filtrando `movimientos_socio` por `periodo`.
 * La lista `movimientos[]` se ventanea por `fecha`. NO cuadran 1:1 y la UI debe decirlo.
 * Aca: un movimiento de periodo 2026-07 pero con fecha de AGOSTO (cae fuera de la ventana),
 * y otro con fecha de julio pero periodo NULL (entra en la lista, no en el asignado).
 */
export const F7 = fotoE1({
  movimientos: [
    movimiento({ id_movimiento: 1, fecha: '2026-07-15', periodo: '2026-07-01', monto: -30000 }),
    movimiento({ id_movimiento: 2, fecha: '2026-07-20', periodo: null, monto: -5000, tipo: 'retiro' }),
  ],
  retribucion_operativo: {
    periodo: '2026-07-01',
    calculado: 100000,
    asignado: 80000, // incluye un movimiento de periodo 07 con fecha de agosto, que NO esta en la lista
    diferencia: 20000,
    estado: 'PARCIAL',
  },
});

/**
 * F8 -- CRUCE DE DIA UTC -> Argentina.
 * `2026-07-13T02:30:00Z` es el 13 en UTC, pero el 12 a las 23:30 en AR.
 * Cortar el prefijo del ISO daria el dia SIGUIENTE. Debe mostrar 12/07/2026 23:30.
 * El segundo caso es medianoche AR exacta: 00:00, nunca 24:00.
 */
export const F8 = fotoE1({
  gastos: [
    gasto({ id_gasto: 81, etiqueta: 'cruce de dia', created_at: '2026-07-13T02:30:00Z' }),
    gasto({ id_gasto: 82, etiqueta: 'medianoche AR', created_at: '2026-07-13T03:00:00Z' }),
  ],
  incidencias: [],
  gastos_sin_incidencia: [],
});

/**
 * F9 -- ID CONGELADO + nombre VIVO.
 * Mismos IDs e importes que F1, pero los socios y cabañas fueron RENOMBRADOS en el catalogo.
 * A30 resuelve los nombres con joins vivos, asi que la foto vieja muestra los nombres NUEVOS.
 * El ID tiene que seguir visible y la nota tiene que explicarlo.
 */
export const F9 = fotoE1({
  socios: [
    { id_socio: 2, socio: 'Rodrigo Martinez', saldo_bruto: 120000, gastos_d: -12000, gastos_e: -8000, saldo_final: 100000, desembolsado_periodo: 45000 },
  ],
  participacion: [
    { id_cabana: 5, cabana: 'Tokio Suite', valor_relativo: 3, id_socio_beneficiario: 3, beneficiario: 'Remo B.', participa: true },
  ],
  matriz_por_socio: [
    { id_socio: 2, socio: 'Rodrigo Martinez', valor_socio: 5, valor_pool: 15, participacion: 0.3333 },
  ],
  incidencias: [
    { id_gasto: 42, seq: 1, destino: 'socio', id_socio: 2, socio: 'Rodrigo Martinez', monto_incidido: 45000, regla: 'zona_prorrateo_valor_relativo' },
  ],
  gastos_sin_incidencia: [
    { id_gasto: 42, clase: 'D', etiqueta: 'Mantenimiento de bomba', monto: 45000, motivo: 'zona_sin_activas' },
  ],
});

// =============================================================================================
// F10..F18 -- A31
// =============================================================================================

/** F10 -- A31 normal: sin anomalias. */
export const F10 = acum();

/**
 * F11 -- `sin_datos: true` CON saldos y retiros vivos.
 * El CROSS JOIN LATERAL hace que `saldos_por_socio` NO sea `[]` aunque no haya fotos.
 * `sin_datos` NO gobierna ningun render: solo entra como una de las dos partes de I1.
 * Aca I1 CIERRA (`sin_datos === (fotos_vigentes === 0)`), asi que NO debe haber anomalia I1.
 */
export const F11 = acum({
  sin_datos: true,
  totales: {
    ingresos_acumulados: 0,
    gastos_acumulados: 0,
    gastos_desglose: { a_paso2: 0, c_paso7: 0, d_e_socios: 0 },
    utilidad_acumulada: 0,
    repartos_acumulados: 0,
    retiros_acumulados: 700000, // hay retiros aunque no haya fotos
  },
  evolucion: [],
  saldos_por_socio: [2, 3, 4].map((id) => ({
    id_socio: id,
    socio: NOMBRE[id],
    resultado_liquidacion: 0,
    reembolso_desembolso: 0,
    movimientos: -233333,
    saldo_vivo: -233333, // saldo vivo NO nulo con sin_datos: true
  })),
  meta: { fotos_vigentes: 0, fotos_pre_piso: 0, movimientos_pre_piso: 0 },
});

/** F12 -- I1 ROTA: `sin_datos: true` pero el servidor cuenta 3 fotos vigentes. */
export const F12 = acum({ sin_datos: true });

/** F13 -- I2 ROTA: informa 5 fotos vigentes pero manda 3 filas de evolucion. */
export const F13 = acum({ meta: { fotos_vigentes: 5, fotos_pre_piso: 0, movimientos_pre_piso: 0 } });

/** F14 -- Periodos DESORDENADOS. La UI ordena una COPIA; no muta `data.evolucion`. */
export const F14 = acum({
  evolucion: ['2026-09-01', '2026-07-01', '2026-08-01'].map((periodo, i) => ({
    periodo,
    id_liquidacion: 12 + i,
    ingresos: 1600000,
    gastos: 400000,
    utilidad: 1200000,
    repartos: 300000,
    retiros_mes: -230000,
  })),
});

/**
 * F15 -- Periodos REPETIDOS. NO se deduplican: se muestran todas las filas que llegaron.
 * `fotos_vigentes: 3` y llegan 3 filas -> I2 cierra. El duplicado es visible, no silenciado.
 */
export const F15 = acum({
  evolucion: ['2026-07-01', '2026-08-01', '2026-08-01'].map((periodo, i) => ({
    periodo,
    id_liquidacion: 12 + i,
    ingresos: 1600000,
    gastos: 400000,
    utilidad: 1200000,
    repartos: 300000,
    retiros_mes: -230000,
  })),
});

/** F16 -- IDENTIDAD DE GASTOS ROTA: el desglose suma 1.100.000 y `gastos_acumulados` dice 1.200.000. */
export const F16 = acum({
  totales: {
    ingresos_acumulados: 5000000,
    gastos_acumulados: 1200000,
    gastos_desglose: { a_paso2: 400000, c_paso7: 300000, d_e_socios: 400000 }, // suma 1.100.000
    utilidad_acumulada: 3800000,
    repartos_acumulados: 900000,
    retiros_acumulados: 700000,
  },
});

/** F17 -- FOTOS y MOVIMIENTOS pre-piso: hay datos anteriores al piso contable, fuera de alcance. */
export const F17 = acum({
  meta: { fotos_vigentes: 3, fotos_pre_piso: 2, movimientos_pre_piso: 4 },
});

/**
 * F18 -- PISO DIVERGENTE + no-mutacion.
 * `piso` del servidor != FLOOR_CONTABLE del espejo local.
 * CONGELADO con `Object.freeze`: si `analizarAcumulados` mutara `data.evolucion` (por ejemplo con
 * un `.sort()` in-place en vez de una copia), en strict mode esto TIRA TypeError. El fixture es la
 * prueba, no el comentario.
 */
export const F18: HistoricoAcumuladosData = Object.freeze({
  ...acum({ piso: '2026-05-01' }),
  evolucion: Object.freeze(
    ['2026-09-01', '2026-07-01', '2026-08-01'].map((periodo, i) =>
      Object.freeze({
        periodo,
        id_liquidacion: 12 + i,
        ingresos: 1600000,
        gastos: 400000,
        utilidad: 1200000,
        repartos: 300000,
        retiros_mes: -230000,
      })
    )
  ) as HistoricoAcumuladosData['evolucion'],
}) as HistoricoAcumuladosData;

// =============================================================================================
// F19 -- INCONSISTENTE: T1..T7
// Cada variante rompe UNA sola invariante. Todas deben clasificar INCONSISTENTE.
// =============================================================================================

export const F19: Record<string, { data: HistoricoMesData; mesApplied: string; rompe: string }> = {
  /** T1 -- round-trip: `data.periodo` no corresponde al mes pedido. */
  t1: {
    data: fotoE1({ periodo: '2026-06-01' }),
    mesApplied: '2026-07',
    rompe: 'T1  data.periodo !== `${mesApplied}-01`',
  },
  /** T2 -- E1 sin cabecera. */
  t2: {
    data: fotoE1({ cabecera: null }),
    mesApplied: '2026-07',
    rompe: 'T2  E1/E2 con cabecera === null',
  },
  /** T3 -- cabecera de OTRO periodo. */
  t3: {
    data: fotoE1({
      cabecera: { ...fotoE1().cabecera!, periodo: '2026-06-01' },
    }),
    mesApplied: '2026-07',
    rompe: 'T3  cabecera.periodo !== data.periodo',
  },
  /** T4 -- E1 sin retribucion_operativo. */
  t4: {
    data: fotoE1({ retribucion_operativo: null }),
    mesApplied: '2026-07',
    rompe: 'T4  E1/E2 con retribucion_operativo === null',
  },
  /** T5 -- retribucion de OTRO periodo. */
  t5: {
    data: fotoE1({
      retribucion_operativo: { periodo: '2026-06-01', calculado: 100000, asignado: 80000, diferencia: 20000, estado: 'PARCIAL' },
    }),
    mesApplied: '2026-07',
    rompe: 'T5  retribucion_operativo.periodo !== data.periodo',
  },
  /** T6 -- E3 CON cabecera (no deberia haberla). */
  t6: {
    data: { ...F3, cabecera: fotoE1().cabecera },
    mesApplied: '2026-07',
    rompe: 'T6  E3 con cabecera !== null',
  },
  /**
   * T7 -- E3 CON retribucion_operativo presente.
   * Esta es la variante que pidio Franco explicitamente: no hay foto, pero el servidor manda
   * una retribucion. Es imposible por contrato -> INCONSISTENTE, no E3.
   */
  t7: {
    data: {
      ...F3,
      retribucion_operativo: { periodo: '2026-07-01', calculado: 100000, asignado: 0, diferencia: 100000, estado: 'PENDIENTE' },
    },
    mesApplied: '2026-07',
    rompe: 'T7  E3 con retribucion_operativo !== null',
  },
};

/**
 * F20 -- PEOR CASO VISUAL (densidad). No estaba en el plan original y lo agrega SB-UI-6 a
 * proposito: F1 tiene `comentario`, `comprobante_url` y `clase_sugerida` en null, asi que medir la
 * altura de fila con F1 da un falso "todo bien". Este fixture apila TODOS los opcionales en la
 * celda Etiqueta -- etiqueta larga + procedencia + comentario largo + clase sugerida + comprobante --
 * que es lo que estira las filas. Es el fixture con el que se responde la decision 1 de Franco
 * (¿las filas altas INUTILIZAN la tabla en mobile, o solo son feas?).
 */
export const F20 = fotoE1({
  gastos: [
    gasto({
      id_gasto: 71,
      etiqueta: 'Reparación integral de la bomba de agua del muelle norte',
      clase: 'E',
      clase_sugerida: 'A',
      comentario:
        'Se repuso el capacitor de arranque, se limpió el filtro de succión y se cambió la manguera de impulsión. El proveedor dejó garantía de 6 meses por escrito.',
      comprobante_url: 'https://vita.delta/comprobantes/2026-07/bomba-muelle-norte.pdf',
      medio_pago: 'transferencia',
    }),
    gasto({
      id_gasto: 72,
      etiqueta: 'Flete de materiales desde Tigre centro',
      clase: 'D',
      clase_sugerida: 'C',
      id_zona: null,
      id_cabana: 5,
      comentario: 'Dos viajes en lancha colectiva por el volumen de la carga.',
      comprobante_url: 'https://vita.delta/comprobantes/2026-07/flete.pdf',
      medio_pago: 'efectivo',
    }),
    gasto({ id_gasto: 73, etiqueta: 'Compra menor de ferretería', comentario: null, comprobante_url: null }),
  ],
  incidencias: [
    { id_gasto: 71, seq: 1, destino: 'socio', id_socio: 2, socio: 'Rodrigo', monto_incidido: 45000, regla: 'zona_prorrateo_valor_relativo' },
    { id_gasto: 72, seq: 1, destino: 'socio', id_socio: 3, socio: 'Remo', monto_incidido: 45000, regla: 'cabana_directa' },
  ],
  gastos_sin_incidencia: [
    { id_gasto: 73, clase: 'D', etiqueta: 'Compra menor de ferretería', monto: 45000, motivo: 'pool_vacio' },
  ],
});

// ---------------------------------------------------------------------------------------------
// Catalogo para el harness visual.
// ---------------------------------------------------------------------------------------------

export const CATALOGO_A30: { id: string; titulo: string; data: HistoricoMesData }[] = [
  { id: 'F1', titulo: 'F1 · E1 completo', data: F1 },
  { id: 'F2', titulo: 'F2 · E2 (foto_pre_extension)', data: F2 },
  { id: 'F3', titulo: 'F3 · E3 (sin_foto_vigente)', data: F3 },
  { id: 'F4', titulo: 'F4 · matriz vacía legítima', data: F4 },
  { id: 'F5', titulo: 'F5 · comprobantes peligrosos', data: F5 },
  { id: 'F6', titulo: 'F6 · comprobantes válidos', data: F6 },
  { id: 'F7', titulo: 'F7 · movimientos fecha vs período', data: F7 },
  { id: 'F8', titulo: 'F8 · cruce de día UTC→AR', data: F8 },
  { id: 'F9', titulo: 'F9 · ID congelado + nombre vivo', data: F9 },
  { id: 'F20', titulo: 'F20 · peor caso visual (gastos densos)', data: F20 },
];

export const CATALOGO_A31: { id: string; titulo: string; data: HistoricoAcumuladosData }[] = [
  { id: 'F10', titulo: 'F10 · normal', data: F10 },
  { id: 'F11', titulo: 'F11 · sin_datos con saldos vivos', data: F11 },
  { id: 'F12', titulo: 'F12 · I1 rota', data: F12 },
  { id: 'F13', titulo: 'F13 · I2 rota', data: F13 },
  { id: 'F14', titulo: 'F14 · períodos desordenados', data: F14 },
  { id: 'F15', titulo: 'F15 · períodos repetidos', data: F15 },
  { id: 'F16', titulo: 'F16 · identidad de gastos rota', data: F16 },
  { id: 'F17', titulo: 'F17 · fotos y movimientos pre-piso', data: F17 },
  { id: 'F18', titulo: 'F18 · piso divergente (frozen)', data: F18 },
];
