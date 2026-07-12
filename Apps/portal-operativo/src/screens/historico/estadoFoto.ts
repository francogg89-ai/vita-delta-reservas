import type { HistoricoMesData } from '../../lib/contratos';

/**
 * Estado contractual de la foto mensual A30 (D-FE-56).
 *
 *   E1            foto completa       sin_foto:false / detalle_disponible:true  / motivo:null
 *   E2            foto pre-extension  sin_foto:false / detalle_disponible:false / motivo:'foto_pre_extension'
 *   E3            sin foto vigente    sin_foto:true  / detalle_disponible:false / motivo:'sin_foto_vigente'
 *   INCONSISTENTE cualquier respuesta que NO respete el contrato
 *
 * E2 y E3 NO son errores: son estados de exito (D-CC-44) y se presentan con un Banner informativo,
 * nunca con "error" ni "no encontrado".
 */
export type EstadoFoto = 'E1' | 'E2' | 'E3' | 'INCONSISTENTE';

/**
 * Clasifica la respuesta de `cuenta_corriente.historico` en DOS capas (D-FE-56):
 *
 *   Capa 1 - combinacion de banderas (sin_foto / detalle_disponible / detalle_motivo).
 *   Capa 2 - invariantes temporales y estructurales T1..T7 (round-trip del periodo + nullidad).
 *
 * Cualquier desvio devuelve INCONSISTENTE: la pantalla muestra un error controlado con retry y
 * CERO cifras. NUNCA se elige "el estado mas parecido": atribuirle una semantica incorrecta a
 * numeros de plata es peor que no mostrarlos.
 *
 * Invariantes (respaldadas por el canonico v1.12.0):
 *   T1  data.periodo === `${mesApplied}-01`
 *       El gateway exige dia 01 y `date_trunc('month', ...)` es identidad sobre un dia 01, asi que
 *       el round-trip es exacto. Se evalua SIEMPRE y PRIMERO: renderizar la foto de otro mes bajo
 *       la etiqueta del mes pedido es el peor modo de falla posible.
 *   T2  E1/E2: cabecera !== null
 *   T3  E1/E2: cabecera.periodo === data.periodo
 *       `liquidacion_vigente(p)` filtra `WHERE lp.periodo = date_trunc('month', p)`: la foto
 *       devuelta pertenece POR CONSTRUCCION al periodo consultado. Si esto falla, hay corrupcion.
 *   T4  E1/E2: retribucion_operativo !== null
 *       `reporte_retribucion_operativo_periodo` es un SELECT escalar: siempre devuelve 1 fila.
 *   T5  E1/E2: retribucion_operativo.periodo === data.periodo
 *   T6  E3: cabecera === null
 *   T7  E3: retribucion_operativo === null
 *       La rama `sin_foto` de la funcion hardcodea ambos a NULL.
 *
 * Modulo PURO: sin hooks, sin red, sin estado. Lo consume la vista y (en SB-UI-6) el harness.
 *
 * @param data        respuesta de A30
 * @param mesApplied  mes aplicado en formato 'YYYY-MM' (el que genero el payload)
 */
export function clasificarFoto(data: HistoricoMesData, mesApplied: string): EstadoFoto {
  // --- T1: round-trip del periodo (primero, siempre) ---
  if (data.periodo !== `${mesApplied}-01`) return 'INCONSISTENTE';

  // --- Capa 1: combinacion de banderas ---
  const esE1 =
    data.sin_foto === false && data.detalle_disponible === true && data.detalle_motivo === null;
  const esE2 =
    data.sin_foto === false &&
    data.detalle_disponible === false &&
    data.detalle_motivo === 'foto_pre_extension';
  const esE3 =
    data.sin_foto === true &&
    data.detalle_disponible === false &&
    data.detalle_motivo === 'sin_foto_vigente';

  if (!esE1 && !esE2 && !esE3) return 'INCONSISTENTE';

  // --- Capa 2: invariantes estructurales/temporales por estado ---
  if (esE1 || esE2) {
    if (data.cabecera === null) return 'INCONSISTENTE'; // T2
    if (data.cabecera.periodo !== data.periodo) return 'INCONSISTENTE'; // T3
    if (data.retribucion_operativo === null) return 'INCONSISTENTE'; // T4
    if (data.retribucion_operativo.periodo !== data.periodo) return 'INCONSISTENTE'; // T5
    return esE1 ? 'E1' : 'E2';
  }

  // esE3
  if (data.cabecera !== null) return 'INCONSISTENTE'; // T6
  if (data.retribucion_operativo !== null) return 'INCONSISTENTE'; // T7
  return 'E3';
}
