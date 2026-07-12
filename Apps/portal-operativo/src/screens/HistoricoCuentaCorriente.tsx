import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useAuth } from '../auth/useAuth';
import { useAction } from '../hooks/useAction';
import { primerDiaMes } from '../lib/periodo';
import type { HistoricoAcumuladosData, HistoricoMesData } from '../lib/contratos';
import { HistoricoVista } from './historico/HistoricoVista';
import type { EstadoLectura } from './historico/HistoricoVista';
import { construirPlanSelector } from './historico/planSelector';

// =============================================================================================
// A30 + A31 -- Historico y acumulados de cuenta corriente (PANTALLA COMBINADA, D-FE-46).
//
// Unico modulo del bloque con acceso a red. Toda la presentacion vive en `HistoricoVista`, que es
// pura (ver la invariante de arquitectura en ese archivo).
//
// A31 NO tiene entrada en ACTION_REGISTRY: llega en `sesion.contexto.acciones` y se consume por
// tolerancia forward (D-FE-01/09), asi que no genera item de menu ni ruta. El route guard es A30.
//
// ---------------------------------------------------------------------------------------------
// MAQUINA DE ESTADO DEL SELECTOR / A30
// ---------------------------------------------------------------------------------------------
// El estado de A30 NO es `mesApplied` a secas, sino un TOKEN de peticion `{ mes, seq }`:
//
//   * `mes`  -- el mes pedido. Gobierna el payload y, por lo tanto, el `payloadKey` de useAction.
//   * `seq`  -- sube en CADA "Consultar", incluso si el mes no cambia. Sin el, un refetch del mismo
//               mes seria indistinguible del estado ya resuelto y no habria forma de saber, de
//               forma SINCRONICA, que hay una consulta nueva en curso.
//
// Y un espejo, `servida`, que registra que peticion esta sirviendo el `useAction` que tenemos en
// mano. La necesidad viene de como funciona useAction (hooks/useAction.ts):
//
//   - `setLoading(true)` esta DENTRO de su useEffect (linea 51);
//   - `setData(...)` NUNCA se limpia al cambiar de payload.
//
// => En el render inmediatamente posterior a cambiar de mes, y ANTES de que corran los efectos,
//    useAction reporta `loading:false` con el `data` del mes ANTERIOR. Clasificar eso contra el mes
//    nuevo dispara T1 -> INCONSISTENTE -> un FLASH ROJO en cada cambio de mes.
//
// `servida` se sincroniza en un efecto declarado DESPUES de useAction, asi que se actualiza en el
// MISMO commit en que arranca el ciclo del hook. Mientras `servida != peticion`, la lectura es
// STALE y la pantalla la trata como PENDIENTE. No hace falta que el espejo dispare su propio
// re-render: el commit en que se actualiza es el mismo en que useAction hace `setLoading(true)`,
// y React batchea ambos setState.
//
// Lo que este espejo NO hace: enmascarar T1. Una vez que la peticion esta servida, si la respuesta
// trae un `periodo` que no corresponde, `clasificarFoto` la marca INCONSISTENTE igual (ver la
// tabla de transiciones en el cierre del sub-bloque).
//
// Respuestas fuera de orden: ya las cubre useAction con su guard de `reqId` + `activo` (lineas
// 56/61). Un resultado viejo nunca completa el estado del mes nuevo.
// =============================================================================================

const ACTION_A30 = 'cuenta_corriente.historico';
const ACTION_A31 = 'cuenta_corriente.historico_acumulados';

/** A31 exige payload VACIO ESTRICTO (`payloadVacioEstricto` del gateway): ni una clave de mas. */
const SIN_PAYLOAD: Record<string, unknown> = {};

/** Token de una peticion A30. `seq` sube en cada Consultar, aun con el mismo `mes`. */
interface PeticionFoto {
  mes: string;
  seq: number;
}

export function HistoricoCuentaCorriente() {
  const { contexto } = useAuth();

  // --- Guard fail-closed conjunto (D-FE-46) -------------------------------------------------
  // A30 y A31 son entradas INDEPENDIENTES del CATALOG. Compartir rol (socio-only) no garantiza
  // presencia atomica en `acciones`. Si falta cualquiera, NINGUNA lectura se habilita:
  // `enabled:false` corta en el guard de `useAction` ANTES de llamar a `callPortal` (y `refetch`
  // vuelve a caer en el mismo guard), asi que quedan CERO requests.
  const tieneA30 = contexto?.acciones.includes(ACTION_A30) ?? false;
  const tieneA31 = contexto?.acciones.includes(ACTION_A31) ?? false;
  const ambas = tieneA30 && tieneA31;
  const faltaAccion = !ambas;

  if (import.meta.env.DEV && faltaAccion) {
    console.warn(
      '[historico] fail-closed: falta(n) accion(es) en sesion.contexto.acciones ->',
      [!tieneA30 ? ACTION_A30 : null, !tieneA31 ? ACTION_A31 : null].filter(Boolean).join(', '),
    );
  }

  // --- Estado del selector (draft -> applied, D-FE-49) ---------------------------------------
  const [mesDraft, setMesDraft] = useState<string | null>(null);
  const [peticion, setPeticion] = useState<PeticionFoto | null>(null);
  const [reiniciadoPorPiso, setReiniciadoPorPiso] = useState(false);

  const mesApplied = peticion?.mes ?? null;

  /** La aplicacion automatica inicial ya ocurrio (o quedo cerrada por un retry exitoso de A31). */
  const inicializado = useRef(false);
  /**
   * Hubo interaccion HUMANA con el selector: cambio de draft o Consultar.
   * Poblar el draft automaticamente en modo degradado NO cuenta como interaccion (lo hace la UI
   * para que el <select> tenga un valor, no el usuario).
   */
  const interactuado = useRef(false);

  /**
   * Contador MONOTONICO de peticiones A30. Es un ref independiente y NO se deriva de
   * `peticion?.seq`: al invalidar la peticion por piso, `peticion` pasa a null y derivar de ella
   * reiniciaria el contador en 1. Un `seq` repetido dejaria que una `servida` VIEJA declarara
   * servida una peticion creada DESPUES de la invalidacion -> el frame stale volveria a colarse.
   * Con un contador monotonico, ningun token se repite durante la vida del componente, y
   * `servida.mes === peticion.mes && servida.seq === peticion.seq` implica que son LA MISMA.
   */
  const siguienteSeq = useRef(0);
  const crearPeticion = useCallback(
    (mes: string): PeticionFoto => ({ mes, seq: ++siguienteSeq.current }),
    [],
  );

  // --- Lecturas (estados y retries INDEPENDIENTES por seccion) -------------------------------
  const acum = useAction<HistoricoAcumuladosData>(ACTION_A31, SIN_PAYLOAD, { enabled: ambas });

  const payloadFoto = useMemo(
    () => (mesApplied !== null ? { mes: primerDiaMes(mesApplied) } : SIN_PAYLOAD),
    [mesApplied],
  );
  const foto = useAction<HistoricoMesData>(ACTION_A30, payloadFoto, {
    enabled: ambas && mesApplied !== null,
  });
  const refetchFoto = foto.refetch; // estable (useCallback con deps [])

  // --- Conciliacion peticion <-> lectura (anti-flash) -----------------------------------------
  // Efecto declarado DESPUES de useAction => corre despues de su efecto, en el mismo commit.
  const [servida, setServida] = useState<PeticionFoto | null>(null);
  useEffect(() => {
    setServida(peticion);
  }, [peticion]);

  const peticionServida =
    peticion !== null &&
    servida !== null &&
    servida.mes === peticion.mes &&
    servida.seq === peticion.seq;

  /**
   * A30 pendiente. Dos causas, ambas SINCRONICAS en el render:
   *   (a) el ciclo de useAction para esta peticion todavia no arranco (`!peticionServida`);
   *   (b) ya arranco y sigue en vuelo (`foto.loading`).
   * Gobierna el render (loading en vez de clasificar data stale) y la compuerta anti-doble-request.
   */
  const fotoPendiente = peticion !== null && (!peticionServida || foto.loading);

  // --- Retry A30: UNICA puerta de entrada ----------------------------------------------------
  /**
   * Todo reintento de A30 pasa por aca: el ErrorCard de error real, el ErrorCard de INCONSISTENTE
   * y el "Consultar" sobre el mismo mes. Genera un token NUEVO, con lo cual el pendiente se activa
   * SINCRONICAMENTE en el mismo render (`!peticionServida`), y recien despues fuerza el ciclo real
   * del hook.
   *
   * `refetchFoto()` es imprescindible: el mes no cambia, asi que el `payloadKey` de useAction
   * tampoco, y el hook no re-dispararia solo. Y es UNA sola llamada -> UN solo request.
   */
  const onRetryFoto = useCallback(() => {
    if (peticion === null) return; // no hay mes aplicado: no hay nada que reintentar
    if (fotoPendiente) return; // ya hay una consulta en vuelo
    setPeticion(crearPeticion(peticion.mes));
    refetchFoto();
  }, [peticion, fotoPendiente, crearPeticion, refetchFoto]);

  /**
   * La lectura A30 TAL COMO LA VE LA VISTA: mismo estado, pero con el `refetch` REEMPLAZADO por el
   * callback tokenizado. La vista no recibe `foto.refetch` crudo, asi que ningun ErrorCard puede
   * saltearse el token, el pendiente sincronico ni la compuerta anti-doble-request.
   */
  const fotoVista = useMemo<EstadoLectura<HistoricoMesData>>(
    () => ({ data: foto.data, loading: foto.loading, error: foto.error, refetch: onRetryFoto }),
    [foto.data, foto.loading, foto.error, onRetryFoto],
  );

  // --- Plan del selector ---------------------------------------------------------------------
  // Precedencia error-antes-de-data: useAction conserva el `data` viejo cuando falla un refetch.
  // Si no se anulara aca, un retry fallido de A31 seguiria alimentando el selector con datos stale
  // y el aviso de degradado nunca apareceria.
  const acumParaPlan = acum.error ? null : acum.data;

  // ESTRATEGIA A (preservar): los meses anclados (draft y aplicado) se pasan al plan para que
  // SIEMPRE tengan su <option>, aunque A31 caiga y el plan degradado achique el techo. Sin esto, un
  // `<select value="2026-11">` sin `<option value="2026-11">` hace que el browser salte en silencio
  // a la primera opcion: reset visual invisible, y el `value` de React deja de coincidir con lo
  // que el usuario ve. Los anclas por debajo del piso NO se preservan (el piso es fail-closed):
  // esos se invalidan mas abajo, con aviso explicito.
  const anclas = useMemo(() => [mesDraft, mesApplied], [mesDraft, mesApplied]);
  const plan = useMemo(() => construirPlanSelector(acumParaPlan, anclas), [acumParaPlan, anclas]);

  // --- Reconciliacion SINCRONICA del piso (D-FE-49) -------------------------------------------
  /**
   * El efecto de abajo normaliza el ESTADO PERSISTIDO, pero corre DESPUES del render. En el frame
   * en que A31 devuelve un piso mas alto, `mesDraft` y `peticion` todavia apuntan a un mes que ya
   * NO esta en `plan.opciones` (los anclas por debajo del piso no se preservan: fail-closed).
   * Sin esta compuerta, ese unico frame mostraria las cuatro cosas prohibidas a la vez:
   *   - un <select value> sin su <option>  -> el browser salta en silencio a la primera opcion;
   *   - la foto vieja, ya FUERA del piso;
   *   - el boton Consultar habilitado para un mes invalido;
   *   - ningun aviso.
   * El efecto no puede ser la unica defensa. Este derivado bloquea el selector y Consultar, evita
   * que se renderice la foto vieja, dispara el aviso y hace que el <select> use un `value` que SI
   * existe entre las opciones -- todo en el MISMO render en que aparece el piso nuevo.
   */
  const seleccionFueraDePiso =
    (mesDraft !== null && mesDraft < plan.pisoMes) ||
    (mesApplied !== null && mesApplied < plan.pisoMes);

  // --- Aplicacion inicial + reconciliacion contra el piso seguro (D-FE-49) --------------------
  useEffect(() => {
    if (!ambas) return;
    if (acum.loading) return; // esperando A31: nada que decidir, y A30 sigue con enabled:false

    const { pisoMes, porDefecto } = plan;
    const resueltoOk = !acum.error && acum.data !== null;

    // (1) Aplicacion automatica inicial. Solo si A31 resolvio OK Y NO hubo interaccion humana.
    //     Sin el guard de `interactuado`, este bloque tambien correria cuando A31 falla, el usuario
    //     consulta A30 en modo degradado, y despues A31 resuelve en un retry: pisaria el mes que el
    //     usuario eligio y dispararia otra consulta sin que la haya pedido.
    if (resueltoOk && !inicializado.current && !interactuado.current) {
      inicializado.current = true;
      setMesDraft(porDefecto);
      setPeticion(crearPeticion(porDefecto));
      setReiniciadoPorPiso(false);
      return;
    }

    // (2) A31 resolvio OK despues de haber operado en degradado: se CIERRA la inicializacion (para
    //     que no vuelva a intentar) y se CONSERVA lo que el usuario eligio. Nada se autodispara.
    if (resueltoOk) inicializado.current = true;

    // (3) Draft vacio o por debajo del piso seguro -> al default. En degradado esto es lo que puebla
    //     el <select> por primera vez; no cuenta como interaccion.
    if (mesDraft === null || mesDraft < pisoMes) setMesDraft(porDefecto);

    // (4) Peticion por debajo del piso seguro (drift del piso tras un retry de A31) -> se INVALIDA,
    //     no se clampa. Clampar dispararia A30 con un mes que el usuario NO eligio. Con peticion
    //     null el hook queda en enabled:false y el dato anterior deja de renderizarse.
    if (peticion !== null && peticion.mes < pisoMes) {
      setPeticion(null);
      setReiniciadoPorPiso(true);
    }
  }, [ambas, acum.loading, acum.error, acum.data, plan, mesDraft, peticion, crearPeticion]);

  // --- Handlers ------------------------------------------------------------------------------
  const onMesDraftChange = useCallback((ym: string) => {
    interactuado.current = true;
    setMesDraft(ym);
  }, []);

  const onConsultar = useCallback(() => {
    if (mesDraft === null) return;
    // Compuerta anti-doble-request (defensa 2 de 2; la 1 es el `disabled` del boton). Usa el
    // pendiente LOCAL: `foto.loading` no cambia sincronicamente en el primer render posterior al
    // click, asi que mirarlo solo dejaria pasar un segundo request.
    if (fotoPendiente) return;
    // El estado todavia no fue normalizado contra un piso nuevo: no se consulta un mes invalido.
    if (seleccionFueraDePiso) return;

    interactuado.current = true;
    setReiniciadoPorPiso(false);

    const mismoMes = peticion !== null && peticion.mes === mesDraft;
    setPeticion(crearPeticion(mesDraft));

    // Mismo mes => el `payloadKey` de useAction NO cambia => el hook no re-dispara por si solo.
    // Hay que forzarlo. Con un mes DISTINTO no se llama: el cambio de payloadKey ya dispara, y
    // llamar refetch ademas produciria DOS requests.
    if (mismoMes) refetchFoto();
  }, [mesDraft, peticion, fotoPendiente, seleccionFueraDePiso, crearPeticion, refetchFoto]);

  return (
    <HistoricoVista
      faltaAccion={faltaAccion}
      acum={acum}
      foto={fotoVista}
      fotoPendiente={fotoPendiente}
      seleccionFueraDePiso={seleccionFueraDePiso}
      plan={plan}
      mesDraft={mesDraft}
      mesApplied={mesApplied}
      reiniciadoPorPiso={reiniciadoPorPiso}
      onMesDraftChange={onMesDraftChange}
      onConsultar={onConsultar}
    />
  );
}
