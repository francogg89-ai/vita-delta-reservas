import type { EvolucionAcum, HistoricoAcumuladosData } from '../../lib/contratos';
import { FLOOR_CONTABLE } from '../../lib/constantes';
import { formatARS } from '../../lib/formato';

// =============================================================================================
// Logica pura de la seccion Acumulados (A31). Sin hooks, sin red, sin JSX.
// La consume `ContenidoAcumulados` y, en SB-UI-6, el harness.
//
// PRINCIPIO RECTOR (precedencia de presentacion): los DATOS gobiernan el render.
//   - Los totales salen de `totales`, siempre.
//   - El vacio de la evolucion lo decide `evolucion.length`, no `sin_datos`.
//   - Los saldos salen de `saldos_por_socio`, que trae UNA FILA POR SOCIO aunque no haya ninguna
//     foto (socios CROSS JOIN LATERAL saldo_corriente_socio).
//   - `sin_datos` NO gobierna NINGUN render: solo entra como una de las dos partes de I1.
// Toda anomalia es un AVISO NO DESTRUCTIVO: nunca oculta filas, nunca reemplaza cifras, nunca
// recalcula el dato. Si el backend mando algo raro, se muestra el dato y se avisa.
// =============================================================================================

/** Codigo estable de cada anomalia. Sirve de key de React y de identificador en QA. */
export type CodigoAnomalia =
  | 'piso_divergente'
  | 'i1_sin_datos'
  | 'i2_cardinalidad'
  | 'orden_evolucion'
  | 'identidad_gastos'
  | 'fotos_pre_piso'
  | 'movimientos_pre_piso';

export interface Anomalia {
  codigo: CodigoAnomalia;
  mensaje: string;
}

export interface AnalisisAcumulados {
  /**
   * COPIA ordenada ascendente por periodo. Es la UNICA fuente de la tabla de evolucion.
   * `data.evolucion` NO se muta (el spread crea un array nuevo) y NO se deduplica.
   */
  evolucionOrdenada: EvolucionAcum[];
  anomalias: Anomalia[];
  /** a_paso2 + c_paso7 + d_e_socios. Se muestra SIEMPRE, al lado de `gastos_acumulados`. */
  sumaDesglose: number;
  /** La identidad del desglose cierra contra `gastos_acumulados`. */
  identidadGastosOk: boolean;
}

/**
 * Pesos -> centavos enteros. Los montos llegan como numeric(12,2) => sumar tres de ellos en float
 * puede driftear (0.1 + 0.2 !== 0.3). Comparar en centavos enteros es EXACTO y evita inventar una
 * tolerancia arbitraria. Es la misma tecnica que usa el backend para agregar.
 */
function centavos(n: number): number {
  return Math.round(n * 100);
}

export function analizarAcumulados(data: HistoricoAcumuladosData): AnalisisAcumulados {
  const { totales, evolucion, meta } = data;

  // --- Evolucion: copia ordenada (fuente unica de la tabla) -----------------------------------
  const evolucionOrdenada = [...evolucion].sort((a, b) => a.periodo.localeCompare(b.periodo));

  // Un solo recorrido detecta las DOS anomalias que el contrato agrupa bajo un mismo mensaje:
  // `localeCompare(actual, previo) <= 0` es true tanto si el periodo actual es MENOR que el previo
  // (orden no estrictamente ascendente) como si es IGUAL (periodo repetido).
  // NO se deduplica: si el backend mando una fila de mas, esconderla es peor que mostrarla.
  let ordenRoto = false;
  let previo: string | null = null;
  for (const fila of evolucion) {
    if (previo !== null && fila.periodo.localeCompare(previo) <= 0) {
      ordenRoto = true;
      break;
    }
    previo = fila.periodo;
  }

  // --- Identidad del desglose de gastos --------------------------------------------------------
  const g = totales.gastos_desglose;
  const sumaCent = centavos(g.a_paso2) + centavos(g.c_paso7) + centavos(g.d_e_socios);
  const identidadGastosOk = sumaCent === centavos(totales.gastos_acumulados);

  // --- Anomalias (orden de presentacion: contexto -> integridad -> forma -> pre-piso) ----------
  const anomalias: Anomalia[] = [];

  if (data.piso !== FLOOR_CONTABLE) {
    anomalias.push({
      codigo: 'piso_divergente',
      mensaje:
        'El servidor informa un piso contable distinto del configurado en el portal. Los ' +
        'acumulados incluyen todas las fotos vigentes y los movimientos devueltos por A31; la ' +
        'pantalla no filtra ni recalcula las cifras por piso.',
    });
  }

  if (data.sin_datos !== (meta.fotos_vigentes === 0)) {
    anomalias.push({
      codigo: 'i1_sin_datos',
      mensaje:
        `El servidor informa que ${data.sin_datos ? 'no hay datos' : 'hay datos'}, pero cuenta ` +
        `${meta.fotos_vigentes} foto(s) de cierre vigente(s). Las cifras se muestran tal como ` +
        'llegaron; no se oculta ninguna fila.',
    });
  }

  if (meta.fotos_vigentes !== evolucion.length) {
    anomalias.push({
      codigo: 'i2_cardinalidad',
      mensaje:
        `El servidor informa ${meta.fotos_vigentes} foto(s) de cierre vigente(s) pero mandó ` +
        `${evolucion.length} fila(s) de evolución. Se muestran todas las filas que llegaron.`,
    });
  }

  if (ordenRoto) {
    anomalias.push({
      codigo: 'orden_evolucion',
      mensaje:
        'La evolución llegó en un orden inesperado o con períodos repetidos. Se muestra ordenada ' +
        'por período.',
    });
  }

  if (!identidadGastosOk) {
    anomalias.push({
      codigo: 'identidad_gastos',
      mensaje:
        `El desglose de gastos suma ${formatARS(sumaCent / 100)}, que no coincide con el total de ` +
        `gastos acumulados (${formatARS(totales.gastos_acumulados)}). Se muestran los dos valores ` +
        'tal como llegaron.',
    });
  }

  // SEMANTICA REAL DEL PISO (verificada contra el canonico v1.12.0):
  //   - `vig` (las fotos que alimentan casc/soc/evo y TODOS los totales) se arma con un unico
  //     WHERE: el de supersesion. NO hay filtro de piso.
  //   - `retiros_acumulados` = SUM(monto) FROM movimientos_socio WHERE tipo='retiro'. Filtra TIPO,
  //     sin ventana de fecha ni de piso.
  //   - `saldo_corriente_socio` arma su propio `vig` igual (sin piso) y su `mov` suma TODOS los
  //     movimientos del socio, sin filtrar tipo ni fecha.
  //   - El `piso` viaja SOLO como dato informado y como base de estos dos contadores.
  // Por eso los avisos dicen "estan INCLUIDOS": no piden una accion, explican por que las cifras
  // contienen periodos que el selector no ofrece consultar. Filtrarlos en la UI produciria numeros
  // que no existen en ningun lado del backend (D-CC-37).
  if (meta.fotos_pre_piso > 0) {
    anomalias.push({
      codigo: 'fotos_pre_piso',
      mensaje:
        `Hay ${meta.fotos_pre_piso} foto(s) de cierre anteriores al piso contable. Están INCLUIDAS ` +
        'en la evolución, en los totales y en los componentes congelados de los saldos por socio. ' +
        'La pantalla no filtra ni recalcula el dato.',
    });
  }

  if (meta.movimientos_pre_piso > 0) {
    anomalias.push({
      codigo: 'movimientos_pre_piso',
      mensaje:
        `Hay ${meta.movimientos_pre_piso} movimientos del mayor anteriores al piso contable. Están ` +
        'incluidos en los movimientos y el saldo vivo de los socios; los que son de tipo retiro ' +
        'también están incluidos en los retiros acumulados. La pantalla no filtra ni recalcula el ' +
        'dato.',
    });
  }

  return { evolucionOrdenada, anomalias, sumaDesglose: sumaCent / 100, identidadGastosOk };
}
