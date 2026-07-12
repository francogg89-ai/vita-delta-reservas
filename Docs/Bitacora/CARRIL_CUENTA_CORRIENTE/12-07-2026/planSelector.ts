import type { HistoricoAcumuladosData } from '../../lib/contratos';
import { FLOOR_CONTABLE } from '../../lib/constantes';
import { etiquetaMes, maxYM, mesActualYM, rangoMesesYM, ymDeFecha } from '../../lib/periodo';

/**
 * Que sabe el selector sobre la foto de un mes.
 *   'con_foto'      -- A31 lo confirma en `evolucion`.
 *   'sin_foto'      -- A31 resolvio y NO esta en `evolucion`.
 *   'no_verificada' -- A31 no esta disponible (degradado): no se puede afirmar NADA.
 *
 * `no_verificada` NO se renderiza como "sin foto": etiquetar asi un mes que quiza la tenga seria
 * afirmar algo falso. Se muestra sin sufijo.
 */
export type EstadoFotoMes = 'con_foto' | 'sin_foto' | 'no_verificada';

/** Una opcion del selector de mes. `foto` se DERIVA de A31.evolucion, nunca se hardcodea. */
export interface OpcionMes {
  ym: string;
  etiqueta: string;
  foto: EstadoFotoMes;
}

export interface PlanSelector {
  /** Piso SEGURO en 'YYYY-MM'. Ningun mes por debajo se ofrece ni se aplica. */
  pisoMes: string;
  /** Opciones del <select>, mas reciente primero (patron A28). Nunca vacia. */
  opciones: OpcionMes[];
  /** Mes por defecto en 'YYYY-MM'. */
  porDefecto: string;
  /** A31.piso difiere del espejo local FLOOR_CONTABLE (anomalia de configuracion). */
  pisoDivergente: boolean;
  /** A31 no disponible (loading/error): el plan sale del fallback local, sin marcas de foto. */
  degradado: boolean;
}

/**
 * Construye el plan del selector de mes (D-FE-49). Modulo PURO: sin hooks, sin red.
 *
 * PISO SEGURO
 *   pisoConsulta = max(FLOOR_CONTABLE, A31.piso)   (o FLOOR_CONTABLE si A31 no esta disponible)
 *   El frontend no puede leer FLOOR_CC_GW (el validador del gateway, que es quien efectivamente
 *   REBOTA con payload_invalido). Solo dispone del espejo local y del piso runtime. Tomar el `max`
 *   es el piso mas conservador computable: si existiera drift hacia un piso runtime MENOR, usar
 *   A31.piso ofreceria meses que el gateway rechazaria.
 *
 * TECHO
 *   techo = max(pisoMes, mesActual, mayorPeriodoSeleccionable)
 *   `pisoMes` entra al max para que el rango [pisoMes .. techo] NUNCA sea vacio, incluso con drift
 *   extremo del piso por delante del mes actual.
 *
 * ANCLAS -- ESTRATEGIA A (preservar)
 *   Los meses ANCLADOS (el draft y el aplicado) que sigan >= piso SIEMPRE entran en las opciones,
 *   aunque queden por encima del techo. Garantiza la invariante
 *
 *       mesDraft === null || opciones.some((o) => o.ym === mesDraft)     (idem mesApplied)
 *
 *   Sin esto, si A31 cae y el plan degradado achica el techo, un `<select value="2026-11">` se
 *   queda sin su `<option>`: el browser salta EN SILENCIO a la primera opcion y el `value` de React
 *   deja de coincidir con lo que el usuario ve. Reset visual invisible.
 *
 *   Se eligio A (preservar) sobre B (invalidar) porque A30 y A31 tienen estados y retries
 *   INDEPENDIENTES por diseño (D-FE-46): que A31 falle en un retry no puede tirar abajo una consulta
 *   de A30 sana y ya renderizada. Y el mes anclado sigue siendo consultable -- esta por encima del
 *   piso seguro y el gateway lo aceptaria. Lo unico que se pierde con A31 caido es SABER si tiene
 *   foto, que es informativo, no un permiso: por eso se marca 'no_verificada' y no 'sin_foto'.
 *
 *   Los anclas por DEBAJO del piso NO se preservan: el piso es fail-closed y el gateway rechazaria
 *   esos meses. Esos los invalida el contenedor, con aviso explicito.
 *
 * PRE-PISO (D-FE-54)
 *   Los periodos con foto anteriores al piso NO se ofrecen en el selector, pero SIGUEN incluidos en
 *   evolucion, en los totales acumulados y en los componentes congelados de los saldos por socio.
 *   La UI no filtra ni recalcula el DATO: solo acota lo que ofrece consultar.
 *
 * DEFAULT
 *   Foto mas reciente que este >= piso y <= mes actual. Si no existe, mes actual clampeado al piso.
 *   Las fotos FUTURAS aparecen como opcion (se pueden abrir a mano) pero NUNCA autoabren.
 *
 * @param acum    respuesta de A31, o null si esta cargando / fallo (fallback local -> degradado).
 * @param anclas  meses que DEBEN tener opcion si siguen >= piso (draft y aplicado). Nulls ignorados.
 */
export function construirPlanSelector(
  acum: HistoricoAcumuladosData | null,
  anclas: readonly (string | null)[] = [],
): PlanSelector {
  const pisoLocalMes = ymDeFecha(FLOOR_CONTABLE);
  const pisoRuntimeMes = acum !== null ? ymDeFecha(acum.piso) : null;

  const pisoMes = pisoRuntimeMes !== null ? maxYM(pisoLocalMes, pisoRuntimeMes) : pisoLocalMes;
  const pisoDivergente = pisoRuntimeMes !== null && pisoRuntimeMes !== pisoLocalMes;
  const degradado = acum === null;

  const mesActual = mesActualYM();

  // Periodos con foto vigente, excluidos los pre-piso (no se OFRECEN; siguen contando en el dato).
  const conFoto = (acum?.evolucion ?? [])
    .map((e) => ymDeFecha(e.periodo))
    .filter((ym) => ym >= pisoMes);
  const setConFoto = new Set(conFoto);

  const mayorConFoto = conFoto.length > 0 ? conFoto.reduce(maxYM) : pisoMes;
  const techo = maxYM(maxYM(pisoMes, mesActual), mayorConFoto);

  const meses = new Set(rangoMesesYM(pisoMes, techo));
  for (const ancla of anclas) {
    if (ancla !== null && ancla >= pisoMes) meses.add(ancla);
  }

  const opciones: OpcionMes[] = [...meses]
    .sort() // 'YYYY-MM': orden lexico === cronologico
    .reverse() // mas reciente primero
    .map((ym) => ({
      ym,
      etiqueta: etiquetaMes(ym),
      foto: degradado ? 'no_verificada' : setConFoto.has(ym) ? 'con_foto' : 'sin_foto',
    }));

  const candidatos = conFoto.filter((ym) => ym <= mesActual);
  const porDefecto = candidatos.length > 0 ? candidatos.reduce(maxYM) : maxYM(mesActual, pisoMes);

  return { pisoMes, opciones, porDefecto, pisoDivergente, degradado };
}
