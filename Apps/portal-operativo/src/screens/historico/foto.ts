import type {
  CascadaFoto,
  ClaseGasto,
  DestinoIncidencia,
  EstadoRetribucion,
  GastoFoto,
  HistoricoMesData,
  IncidenciaFoto,
  LinajeFoto,
  MotivoSinIncidencia,
  TipoMovimiento,
} from '../../lib/contratos';

// =============================================================================================
// Logica pura de la seccion Foto del mes (A30). Sin hooks, sin red, sin JSX.
// =============================================================================================

// ---------------------------------------------------------------------------------------------
// FORMATEADORES -- lo mas peligroso de esta pantalla.
//
// NO TODO LO QUE ES `numeric` ES PLATA. Verificado contra el canonico v1.12.0:
//   - `pct_operativo`  -> FRACCION 0..1  (CHECK chk_liq_pct_rango: >= 0 AND <= 1; seed = 0.25).
//   - `participacion`  -> FRACCION 0..1  (matriz_participacion: valor_socio / valor_pool).
//   - `valor_socio`, `valor_pool`, `valor_relativo` -> VALORES RELATIVOS de cabaña, no montos
//     (valor_socio = SUM(cabanas.valor_relativo); valor_pool = SUM(valor_socio)).
//
// Pasar cualquiera de estos por `Money` mostraria "$ 0,25" donde va "25,00 %", o "$ 3,00" donde va
// un peso relativo. Por eso viven aca, separados de `formatARS`.
// ---------------------------------------------------------------------------------------------

const PCT = new Intl.NumberFormat('es-AR', {
  style: 'percent',
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** Fraccion 0..1 -> '25,00 %'. NO es plata. */
export function formatPct(fraccion: number): string {
  return PCT.format(fraccion);
}

const NUM = new Intl.NumberFormat('es-AR', {
  minimumFractionDigits: 0,
  maximumFractionDigits: 4,
});

/** Numero adimensional (valor relativo de cabaña, pool). NO es plata: no lleva simbolo. */
export function formatNum(n: number): string {
  return NUM.format(n);
}

const FECHA_HORA = new Intl.DateTimeFormat('es-AR', {
  timeZone: 'America/Argentina/Buenos_Aires',
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

/**
 * timestamptz ISO -> 'dd/mm/aaaa HH:MM' en hora de Argentina.
 *
 * Se usa Intl con timeZone explicito, NO el prefijo del string: el ISO viaja en UTC, y cortarle
 * 'YYYY-MM-DD' a un created_at de las 23:30 hora AR daria el DIA SIGUIENTE.
 *
 * Se arma desde `formatToParts` porque ICU en es-AR intercala una coma ("12/07/2026, 18:35") y en
 * la fila del gasto ya hay un separador (" · "). `hourCycle: 'h23'` evita que medianoche salga
 * como "24:00".
 *
 * Fallback: el string crudo (nunca "Invalid Date").
 */
export function formatFechaHora(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const p: Record<string, string> = {};
  for (const parte of FECHA_HORA.formatToParts(d)) p[parte.type] = parte.value;
  return `${p.day}/${p.month}/${p.year} ${p.hour}:${p.minute}`;
}

// ---------------------------------------------------------------------------------------------
// ETIQUETAS de los enums congelados (CHECKs del DDL).
// ---------------------------------------------------------------------------------------------

export const CLASE_GASTO: Record<ClaseGasto, string> = {
  A: 'A · común (todos)',
  C: 'C · común operativo',
  D: 'D · por zona',
  E: 'E · por cabaña',
};

export const TIPO_MOVIMIENTO: Record<TipoMovimiento, string> = {
  retiro: 'Retiro',
  adelanto: 'Adelanto',
  ajuste_manual: 'Ajuste manual',
  retribucion_operativo: 'Retribución operativa',
  ajuste_arranque: 'Ajuste de arranque',
  reversa: 'Reversa',
};

export const MOTIVO_SIN_INCIDENCIA: Record<MotivoSinIncidencia, string> = {
  pool_vacio: 'Pool vacío',
  zona_sin_activas: 'Zona sin cabañas activas',
};

export const DESTINO_INCIDENCIA: Record<DestinoIncidencia, string> = {
  pool_pre_operativo: 'Pool pre-operativo',
  socio: 'Socio',
};

export const ESTADO_RETRIBUCION: Record<EstadoRetribucion, { texto: string; clase: string }> = {
  SIN_CALCULADO: { texto: 'Sin calculado', clase: 'border-sand bg-mist text-reed' },
  PENDIENTE: { texto: 'Pendiente', clase: 'border-amber-200 bg-amber-50 text-amber-800' },
  CONCILIADO: { texto: 'Conciliado', clase: 'border-river/30 bg-river-light text-river-dark' },
  PARCIAL: { texto: 'Parcial', clase: 'border-amber-200 bg-amber-50 text-amber-800' },
  EXCEDIDO: { texto: 'Excedido', clase: 'border-red-200 bg-red-50 text-red-800' },
};

// ---------------------------------------------------------------------------------------------
// DERIVACIONES
// ---------------------------------------------------------------------------------------------

/**
 * Linaje. Se decide por el VALOR (`id_liquidacion_supersede`), no por el flag `es_raiz`.
 * La invariante dice que son equivalentes; si el backend las contradijera, decidir por el flag
 * imprimiria "la liquidacion #null". Decidir por el valor nunca puede hacer eso.
 */
export function textoLinaje(l: LinajeFoto): string {
  return l.id_liquidacion_supersede !== null
    ? `Reemplaza (supersede) a la liquidación #${l.id_liquidacion_supersede}.`
    : 'Raíz: no reemplaza a ninguna otra liquidación.';
}

/**
 * Alcance de un gasto congelado.
 *
 * NO se resuelven los IDs contra CABANAS_TEST / ZONAS_TEST: esas constantes solo valen en TEST
 * (P-FE-01, la secuencia SERIAL difiere en OPS) y la foto congelada NO trae los nombres -- a
 * diferencia de A13, que es la lectura VIVA y si los resuelve por join. Se muestra el ID CRUDO.
 *
 * Se decide por el VALOR, no por la clase: si el backend mandara una fila que viola el CHECK
 * (id_zona != null sii clase='D'), la pantalla la MUESTRA en vez de esconderla.
 */
export function alcanceGasto(g: GastoFoto): string {
  if (g.id_zona !== null && g.id_cabana !== null) {
    return `Zona #${g.id_zona} + Cabaña #${g.id_cabana}`;
  }
  if (g.id_zona !== null) return `Zona #${g.id_zona}`;
  if (g.id_cabana !== null) return `Cabaña #${g.id_cabana}`;
  return '—';
}

/**
 * Pagador de un gasto congelado. El ID SIEMPRE se muestra. El nombre se agrega solo si el socio
 * aparece en `data.socios` -- es decir, en la MISMA respuesta A30, no en constantes TEST.
 * Si el backend viola el CHECK (pagador_tipo='socio' sin id_socio_pagador), se dice, no se esconde.
 */
export function pagadorGasto(g: GastoFoto, nombreSocio: (id: number) => string | null): string {
  if (g.pagador_tipo === 'caja') return 'Caja';
  if (g.id_socio_pagador === null) return 'Socio (sin ID)';
  const nombre = nombreSocio(g.id_socio_pagador);
  return nombre !== null
    ? `Socio #${g.id_socio_pagador} · ${nombre}`
    : `Socio #${g.id_socio_pagador}`;
}

/** Estado de incidencia de un gasto congelado. `sin_incidencia === (motivo !== null)` por CHECK. */
export function incidenciaGasto(g: GastoFoto): string {
  if (!g.sin_incidencia) return 'Incidida';
  return g.motivo_sin_incidencia !== null
    ? MOTIVO_SIN_INCIDENCIA[g.motivo_sin_incidencia]
    : 'Sin incidencia';
}

/**
 * SEGURIDAD -- `comprobante_url` NUNCA se pasa crudo a un `href`.
 *
 * Ni el gateway ni el SQL validan el PROTOCOLO de esta columna: solo tipo, longitud y no-vacio.
 * Un `javascript:alert(document.domain)` cargado por A11 llega intacto hasta la foto congelada, y
 * React 18 solo emite un warning en consola: el `href` se renderiza igual. Eso es un XSS
 * ALMACENADO, servido a un socio que mira su plata.
 *
 * `new URL()` es la defensa correcta porque implementa el parser WHATWG: descarta tabs y newlines
 * embebidos (`java\nscript:` -> `javascript:`), hace trim del whitespace, y normaliza el protocolo
 * a minusculas. No hay forma de colar un esquema peligroso por encoding.
 *
 * @returns la URL normalizada si es http/https ABSOLUTA; `null` en cualquier otro caso
 *          (javascript:, data:, vbscript:, esquemas desconocidos, relativas, invalidas).
 *
 * DEUDA registrada: el hardening deberia estar EN ORIGEN (CHECK de protocolo en
 * `gastos_internos.comprobante_url` + validacion en el gateway/A11). Esta funcion es la ultima
 * linea de defensa, no la unica que deberia existir. No se abre A11/gateway/SQL en este bloque.
 */
export function comprobanteSeguro(valor: string): string | null {
  try {
    const url = new URL(valor);
    return url.protocol === 'https:' || url.protocol === 'http:' ? url.href : null;
  } catch {
    return null;
  }
}

export interface AnalisisFoto {
  /** COPIA ordenada por paso. `data.cascada` NO se muta. */
  cascadaOrdenada: CascadaFoto[];
  /** COPIA ordenada por (id_gasto, seq). `data.incidencias` NO se muta. */
  incidenciasOrdenadas: IncidenciaFoto[];
  /** id_socio -> nombre, tomado de `data.socios` (misma respuesta). `null` si no está. */
  nombreSocio: (id: number) => string | null;
}

export function analizarFoto(data: HistoricoMesData): AnalisisFoto {
  // Ordenamientos DEFENSIVOS por copia. El orden por paso y por (gasto, seq) es estructural, no un
  // dato observable como el de A31: se normaliza en silencio, sin aviso (fuera del contrato de este
  // sub-bloque). Nunca se muta ni se deduplica el original.
  const cascadaOrdenada = [...data.cascada].sort((a, b) => a.paso - b.paso);
  const incidenciasOrdenadas = [...data.incidencias].sort(
    (a, b) => a.id_gasto - b.id_gasto || a.seq - b.seq,
  );

  const mapa = new Map(data.socios.map((s) => [s.id_socio, s.socio]));

  return {
    cascadaOrdenada,
    incidenciasOrdenadas,
    nombreSocio: (id) => mapa.get(id) ?? null,
  };
}
