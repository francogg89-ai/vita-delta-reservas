#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SB-UI-2 -- Patcher quirurgico (4 archivos existentes, todos ADITIVOS).

Reglas de la casa:
  - str_replace anclado, nunca reescritura de archivo entero.
  - assert count == 1 por edit (el ancla debe ser unica).
  - verificacion de identidad inversa: el ancla original debe reaparecer intacta dentro del reemplazo.
  - all-or-nothing: si cualquier assert falla, NO se escribe nada.
  - LF puro, UTF-8 sin BOM.
"""

import io
import os
import sys

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'src')

EDITS = []


def edit(path, anchor, replacement, label):
    EDITS.append({'path': path, 'anchor': anchor, 'replacement': replacement, 'label': label})


# =============================================================================================
# EDIT 1 -- src/lib/contratos.ts : tipos exactos de A30 y A31 (aditivo, al final del archivo)
# =============================================================================================
A_CONTRATOS = """export interface DisponibilidadCabanaData {
  dias: DiaDisponibilidad[];
}
"""

R_CONTRATOS = A_CONTRATOS + """
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
"""

edit('lib/contratos.ts', A_CONTRATOS, R_CONTRATOS, 'A30/A31: tipos exactos (aditivo)')


# =============================================================================================
# EDIT 2 -- src/lib/periodo.ts : helpers minimos de periodo para el historico (aditivo)
# =============================================================================================
A_PERIODO = """/** Mes actual en 'YYYY-MM', pero nunca antes del floor contable. */
export function mesActualOFloor(floorMes: string): string {
  const hoy = new Date();
  const actual = `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}`;
  return actual < floorMes ? floorMes : actual;
}
"""

R_PERIODO = A_PERIODO + """
// ---------------------------------------------------------------------------------------------
// Helpers de periodo del historico L3 (A30/A31). ADITIVOS: no tocan los helpers de arriba (A25/A13)
// ni CuentaCorrienteDetalle.tsx (pantalla cerrada, D-FE-55), que conserva sus copias locales de
// `etiquetaMes` / `mesesDisponibles`. Deuda cosmetica registrada: `etiquetaMes` queda duplicado.
//
// Todas las comparaciones de 'YYYY-MM' y 'YYYY-MM-DD' son LEXICAS: para estos formatos, el orden
// lexicografico coincide con el cronologico. Nunca se construye un Date para comparar.
// ---------------------------------------------------------------------------------------------

const MESES_ES = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/** 'YYYY-MM' -> 'julio 2026'. Sin Date (no corre zona horaria). */
export function etiquetaMes(ym: string): string {
  const [y, m] = ym.split('-').map(Number);
  const nombre = MESES_ES[m - 1];
  return nombre !== undefined ? `${nombre} ${y}` : ym;
}

/** 'YYYY-MM-DD' -> 'YYYY-MM'. Puramente lexico: los `date` del jsonb llegan como string ISO. */
export function ymDeFecha(ymd: string): string {
  return ymd.slice(0, 7);
}

/**
 * Mes actual en 'YYYY-MM', en horario de Argentina.
 *
 * Usa Intl con `timeZone` explicito en vez de `getFullYear()`/`getMonth()` (hora local del
 * navegador) para que el mes no dependa del huso del cliente. `mesActualOFloor` (A25/A13) conserva
 * el criterio viejo y NO se toca: divergencia deliberada, sin efecto practico para usuarios en AR.
 */
export function mesActualYM(): string {
  const ymd = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Argentina/Buenos_Aires',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
  return ymd.slice(0, 7);
}

/** El mayor de dos 'YYYY-MM' (comparacion lexica === cronologica). */
export function maxYM(a: string, b: string): string {
  return a >= b ? a : b;
}

/** Lista ASCENDENTE de meses 'YYYY-MM' en [desde, hasta] inclusive. Vacia si hasta < desde. */
export function rangoMesesYM(desde: string, hasta: string): string[] {
  const out: string[] = [];
  if (hasta < desde) return out;
  let [y, m] = desde.split('-').map(Number);
  const [hy, hm] = hasta.split('-').map(Number);
  while (y < hy || (y === hy && m <= hm)) {
    out.push(`${y}-${String(m).padStart(2, '0')}`);
    m += 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
  }
  return out;
}
"""

edit('lib/periodo.ts', A_PERIODO, R_PERIODO, 'periodo: helpers del historico (aditivo)')


# =============================================================================================
# EDIT 3 -- src/lib/actionRegistry.ts : UNA entrada (A30). A31 NO entra (tolerancia forward).
# =============================================================================================
A_REGISTRY = """  'cuenta_corriente.retirar': {
    action: 'cuenta_corriente.retirar',
    label: 'Retirar saldo',
    grupo: 'socios',
    orden: 30,
    ruta: '/socios/retirar',
  },
"""

R_REGISTRY = """  'cuenta_corriente.retirar': {
    action: 'cuenta_corriente.retirar',
    label: 'Retirar saldo',
    grupo: 'socios',
    orden: 30,
    ruta: '/socios/retirar',
  },
  // A30 (L3) -- Historico y acumulados de cuenta corriente. Socio-only via A02/CATALOG.
  // PANTALLA COMBINADA (D-FE-46): esta UNICA entrada gobierna el item de menu, la ruta y el guard
  // de RutaProtegida. A31 ('cuenta_corriente.historico_acumulados') NO tiene entrada propia: llega
  // en `acciones` y la pantalla la consume por TOLERANCIA FORWARD (D-FE-01/09), asi que no genera
  // item de menu ni ruta. El guard fail-closed conjunto (A30 && A31) vive en la pantalla.
  // Label sin tilde por consistencia con el resto del registry ('Historico de reservas', grupo
  // 'Economico'): el archivo es ASCII. El TITULO de la pantalla si lleva acentos.
  'cuenta_corriente.historico': {
    action: 'cuenta_corriente.historico',
    label: 'Historico y acumulados',
    grupo: 'socios',
    orden: 40,
    ruta: '/socios/historico',
  },
"""

edit('lib/actionRegistry.ts', A_REGISTRY, R_REGISTRY, 'registry: 1 entrada A30 (socios, orden 40)')


# =============================================================================================
# EDIT 4a -- src/app/rutas.tsx : import del contenedor
# =============================================================================================
A_RUTAS_IMPORT = "import { RetirarSaldo } from '../screens/RetirarSaldo';\n"
R_RUTAS_IMPORT = (
    "import { RetirarSaldo } from '../screens/RetirarSaldo';\n"
    "import { HistoricoCuentaCorriente } from '../screens/HistoricoCuentaCorriente';\n"
)
edit('app/rutas.tsx', A_RUTAS_IMPORT, R_RUTAS_IMPORT, 'rutas: import del contenedor')


# =============================================================================================
# EDIT 4b -- src/app/rutas.tsx : entrada en PANTALLAS
# =============================================================================================
A_RUTAS_PANTALLAS = """  'cuenta_corriente.retirar': RetirarSaldo,
"""
R_RUTAS_PANTALLAS = """  'cuenta_corriente.retirar': RetirarSaldo,
  // A30 + A31 combinadas (D-FE-46). La ruta y el guard salen de la entrada A30 del registry;
  // A31 no tiene entrada, la consume la propia pantalla.
  'cuenta_corriente.historico': HistoricoCuentaCorriente,
"""
edit('app/rutas.tsx', A_RUTAS_PANTALLAS, R_RUTAS_PANTALLAS, 'rutas: 1 entrada en PANTALLAS')


# =============================================================================================
# Ejecucion: all-or-nothing
# =============================================================================================
def main():
    planned = {}

    for e in EDITS:
        full = os.path.join(BASE, e['path'])
        if full not in planned:
            with io.open(full, 'r', encoding='utf-8', newline='') as fh:
                planned[full] = fh.read()

        src = planned[full]

        # (1) ancla unica
        n = src.count(e['anchor'])
        assert n == 1, "ANCLA NO UNICA (%d) en %s :: %s" % (n, e['path'], e['label'])

        # (2) identidad inversa: el ancla debe seguir intacta DENTRO del reemplazo (edit aditivo)
        assert e['anchor'] in e['replacement'], \
            "IDENTIDAD INVERSA ROTA en %s :: %s" % (e['path'], e['label'])

        # (3) el reemplazo debe agregar algo
        assert len(e['replacement']) > len(e['anchor']), \
            "REEMPLAZO NO ADITIVO en %s :: %s" % (e['path'], e['label'])

        planned[full] = src.replace(e['anchor'], e['replacement'], 1)

    # (4) sin CR: LF puro
    for full, content in planned.items():
        assert '\r' not in content, "CRLF DETECTADO en %s" % full

    # write
    for full, content in planned.items():
        with io.open(full, 'w', encoding='utf-8', newline='') as fh:
            fh.write(content)

    print("OK: %d edits aplicados sobre %d archivos" % (len(EDITS), len(planned)))
    for e in EDITS:
        print("  [OK] %-26s %s" % (e['path'], e['label']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
