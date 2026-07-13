import type { PortalApiError } from '../../lib/callPortal';
import type { HistoricoAcumuladosData, HistoricoMesData } from '../../lib/contratos';
import { Banner } from '../../ui/Banner';
import { Cargando } from '../../ui/Cargando';
import { ErrorCard } from '../../ui/ErrorCard';
import { Tarjeta } from '../../ui/Tarjeta';
import { controlClass, botonPrimario } from '../../ui/estilos';
import { ContenidoAcumulados } from './ContenidoAcumulados';
import { clasificarFoto } from './estadoFoto';
import type { PlanSelector } from './planSelector';

// =============================================================================================
// HistoricoVista -- VISTA PURA de la pantalla combinada A30 (foto del mes) + A31 (acumulados).
//
// INVARIANTE DE ARQUITECTURA (D-FE-54 / harness de SB-UI-6): este modulo y todo su arbol de
// dependencias son PUROS. No importa `useAction`, ni `callPortal` como VALOR, ni `supabase`, ni
// `useAuth`. `PortalApiError` entra SOLO como `import type` (se elide en compilacion): importarlo
// como valor arrastraria `supabase.ts`, que hace `throw` en el top-level del modulo si faltan las
// env vars -- y eso ataria el harness de QA a las credenciales de Supabase. `ErrorCard` tambien usa
// `import type`, asi que la cadena queda limpia.
//
// Toda la red vive en el contenedor `HistoricoCuentaCorriente`. Aca solo entran props.
//
// SB-UI-2 (este bloque) = esqueleto ESTRUCTURAL: guard fail-closed, selector draft -> applied con
// piso seguro, y la maquina de estados de ambas lecturas. El CONTENIDO de las secciones (tablas,
// tarjetas, banners de integridad de A31) es SB-UI-3 (Acumulados) y SB-UI-4 (Foto del mes).
// =============================================================================================

/** Tupla de lectura que expone `useAction`. Se pasa entera para preservar el retry por seccion. */
export interface EstadoLectura<T> {
  data: T | null;
  loading: boolean;
  error: PortalApiError | null;
  refetch: () => void;
}

export interface HistoricoVistaProps {
  /** Fail-closed (D-FE-46): falta A30 y/o A31 en `sesion.contexto.acciones`. */
  faltaAccion: boolean;
  acum: EstadoLectura<HistoricoAcumuladosData>;
  foto: EstadoLectura<HistoricoMesData>;
  /**
   * Hay una peticion A30 en curso, incluido el tramo en que `useAction` todavia no arranco su
   * ciclo (`loading:false` con el `data` del mes ANTERIOR en mano). Lo calcula el contenedor
   * conciliando el token de peticion contra la lectura servida. Gobierna dos cosas:
   *   1. la seccion Foto NUNCA clasifica un `data` que no corresponda al mes pedido (anti-flash);
   *   2. el boton Consultar queda deshabilitado (anti-doble-request).
   */
  fotoPendiente: boolean;
  /**
   * El piso seguro subio y la seleccion actual quedo por debajo, pero el efecto que normaliza el
   * estado todavia no corrio. En este render: se bloquean selector y Consultar, NO se renderiza la
   * foto vieja (quedo fuera del piso), se muestra el aviso, y el <select> usa `plan.porDefecto`
   * como `value` -- que siempre existe entre las opciones.
   */
  seleccionFueraDePiso: boolean;
  plan: PlanSelector;
  mesDraft: string | null;
  mesApplied: string | null;
  /** El piso seguro subio por encima del mes aplicado y la seleccion se invalido (D-FE-49). */
  reiniciadoPorPiso: boolean;
  onMesDraftChange: (ym: string) => void;
  onConsultar: () => void;
}

/**
 * D-FE-56: la respuesta de A30 llego pero NO respeta el contrato. Se presenta con `ErrorCard`
 * (mismo tratamiento visual que un error de lectura) + retry, y CERO cifras.
 *
 * El `PortalApiError` se construye ESTRUCTURALMENTE: la clase no tiene miembros private/protected,
 * asi que es compatible por forma. Esto evita importar `callPortal` como valor (ver la invariante
 * de arquitectura arriba).
 */
function errorRespuestaInconsistente(): PortalApiError {
  return Object.assign(
    new Error('El servidor devolvió una respuesta histórica inconsistente para este mes.'),
    { name: 'PortalApiError', code: 'respuesta_inconsistente', detail: null },
  ) as PortalApiError;
}

function Cabecera() {
  return (
    <header>
      <p className="text-xs font-medium uppercase tracking-wide text-reed">
        cuenta_corriente.historico
      </p>
      <h2 className="mt-1 text-xl font-semibold text-ink">Histórico de cuenta corriente</h2>
      <p className="mt-1 text-xs text-reed">
        Los acumulados y la foto de cada mes cerrado. Parte de la información está congelada en la
        foto del cierre y parte se actualiza al consultar.
      </p>
    </header>
  );
}

// --------------------------------------------------------------------------------------------
// Seccion Acumulados (A31). Orden loading -> error -> data: `useAction` CONSERVA el `data` viejo
// cuando falla un refetch (el catch setea `error` pero no limpia `data`), asi que el error tiene
// que ganarle a los datos o se renderizarian cifras stale bajo un error.
// --------------------------------------------------------------------------------------------
function SeccionAcumulados({ acum }: { acum: EstadoLectura<HistoricoAcumuladosData> }) {
  if (acum.loading) return <Cargando mensaje="Cargando acumulados..." />;
  if (acum.error) return <ErrorCard error={acum.error} onRetry={acum.refetch} />;
  if (!acum.data) return null;

  // SB-UI-3. El ciclo loading -> error -> data y el retry independiente de A31 quedan ACA, tal como
  // se aprobaron; `ContenidoAcumulados` recibe el `data` ya resuelto y es puro (sin hooks, sin red).
  return <ContenidoAcumulados data={acum.data} />;
}

// --------------------------------------------------------------------------------------------
// Selector de mes (D-FE-49): draft -> applied. Cambiar el <select> NO dispara nada; el disparo lo
// gobierna "Consultar".
// --------------------------------------------------------------------------------------------
function SelectorMes({
  plan,
  mesDraft,
  cargandoAcum,
  fotoPendiente,
  seleccionFueraDePiso,
  reiniciadoPorPiso,
  onMesDraftChange,
  onConsultar,
}: {
  plan: PlanSelector;
  mesDraft: string | null;
  cargandoAcum: boolean;
  fotoPendiente: boolean;
  seleccionFueraDePiso: boolean;
  reiniciadoPorPiso: boolean;
  onMesDraftChange: (ym: string) => void;
  onConsultar: () => void;
}) {
  const listo = !cargandoAcum && mesDraft !== null;
  // Defensa 1 de 2 contra el doble request (la 2 es el early-return de `onConsultar`). El select
  // queda habilitado a proposito mientras A30 esta en vuelo: cambiar el draft no dispara nada.
  const puedeConsultar = listo && !fotoPendiente && !seleccionFueraDePiso;

  // Con la seleccion fuera del piso, el `value` NO puede ser `mesDraft` (ya no tiene <option>: el
  // browser saltaria en silencio a la primera opcion). `plan.porDefecto` siempre esta entre las
  // opciones, por construccion de `construirPlanSelector`.
  const valorSelect = seleccionFueraDePiso ? plan.porDefecto : (mesDraft ?? '');
  const selectHabilitado = listo && !seleccionFueraDePiso && plan.opciones.length > 0;

  return (
    <div className="space-y-3">
      {plan.pisoDivergente && (
        <Banner tono="aviso">
          El piso contable informado por el servidor no coincide con el del portal. Se usa el más
          restrictivo de los dos para no ofrecer meses que el servidor pueda rechazar.
        </Banner>
      )}

      {plan.degradado && !cargandoAcum && (
        <Banner tono="aviso">
          No se pudieron cargar los acumulados. El listado puede estar incompleto y no se puede
          verificar qué meses tienen foto. Los meses que ya habías seleccionado o consultado se
          conservan.
        </Banner>
      )}

      {(seleccionFueraDePiso || reiniciadoPorPiso) && (
        <Banner tono="aviso">
          El piso contable del servidor cambió y es posterior al mes que estabas consultando. Se
          reinició la selección: elegí un mes y tocá Consultar.
        </Banner>
      )}

      <div className="flex flex-wrap items-end gap-3">
        <div className="w-full sm:w-64">
          <label
            htmlFor="mes-historico"
            className="text-xs font-medium uppercase tracking-wide text-reed"
          >
            Mes
          </label>
          <select
            id="mes-historico"
            className={controlClass}
            value={valorSelect}
            disabled={!selectHabilitado}
            onChange={(e) => onMesDraftChange(e.target.value)}
          >
            {mesDraft === null && <option value="">Cargando meses...</option>}
            {plan.opciones.map((o) => (
              <option key={o.ym} value={o.ym}>
                {/* 'no_verificada' va SIN sufijo: con A31 caido no se puede afirmar que no hay foto. */}
                {o.foto === 'sin_foto' ? `${o.etiqueta} · sin foto` : o.etiqueta}
              </option>
            ))}
          </select>
        </div>

        <button
          type="button"
          className={botonPrimario}
          disabled={!puedeConsultar}
          onClick={onConsultar}
        >
          {fotoPendiente ? 'Consultando...' : 'Consultar'}
        </button>
      </div>
    </div>
  );
}

// --------------------------------------------------------------------------------------------
// Seccion Foto del mes (A30). Estados: inactivo -> loading -> error -> clasificacion (D-FE-56).
// --------------------------------------------------------------------------------------------
function SeccionFotoMes({
  foto,
  fotoPendiente,
  seleccionFueraDePiso,
  mesApplied,
}: {
  foto: EstadoLectura<HistoricoMesData>;
  fotoPendiente: boolean;
  seleccionFueraDePiso: boolean;
  mesApplied: string | null;
}) {
  // Inactivo: sin mes aplicado el hook va con enabled:false -> CERO request.
  // `seleccionFueraDePiso` entra por la misma puerta: el piso subio y el mes que teniamos aplicado
  // quedo por debajo. La foto vieja NO se renderiza aunque el `data` siga en mano y su T1 pase: ese
  // mes ya no es consultable. El aviso de reinicio, arriba, da el contexto.
  if (seleccionFueraDePiso || mesApplied === null) {
    return (
      <Tarjeta titulo="Foto del mes">
        <p className="text-sm text-reed">Elegí un mes y tocá Consultar.</p>
      </Tarjeta>
    );
  }

  // PENDIENTE va PRIMERO, antes que error y que data. Cubre `foto.loading` y, ademas, el tramo en
  // que useAction todavia no arranco su ciclo: ahi reporta loading:false con el `data` (y el
  // `error`) del mes ANTERIOR. Clasificar ese data contra el mes nuevo daria T1 -> INCONSISTENTE:
  // un flash rojo en cada cambio de mes. Tampoco se muestra el error viejo por la misma razon.
  // Esto NO enmascara T1: una vez servida la peticion, un `periodo` incorrecto en la respuesta
  // NUEVA sigue cayendo en INCONSISTENTE.
  if (fotoPendiente) return <Cargando mensaje="Cargando la foto del mes..." />;
  if (foto.error) return <ErrorCard error={foto.error} onRetry={foto.refetch} />;
  if (!foto.data) return null;

  const estado = clasificarFoto(foto.data, mesApplied);

  if (estado === 'INCONSISTENTE') {
    return <ErrorCard error={errorRespuestaInconsistente()} onRetry={foto.refetch} />;
  }

  return (
    <div className="space-y-4">
      {estado === 'E2' && (
        <Banner tono="info" titulo="Foto anterior a la extensión del detalle fino">
          La cascada y el resultado por socio están completos. El desglose gasto por gasto no se
          congeló para este período.
        </Banner>
      )}

      {estado === 'E3' && (
        <Banner tono="info" titulo="Este mes todavía no tiene foto congelada">
          Todavía no se corrió el cierre del período.
        </Banner>
      )}

      <Tarjeta titulo="Foto del mes">
        <p className="text-sm text-reed">
          Estado <span className="font-medium text-ink">{estado}</span> · período{' '}
          <span className="font-medium text-ink">{foto.data.periodo}</span>.
        </p>
        <p className="mt-2 text-sm text-reed">
          Pendiente SB-UI-4: cabecera de la foto, cascada, resultado por socio, retribución
          operativa (mixta), movimientos del mes (en vivo) y detalle fino colapsable.
        </p>
      </Tarjeta>
    </div>
  );
}

export function HistoricoVista({
  faltaAccion,
  acum,
  foto,
  fotoPendiente,
  seleccionFueraDePiso,
  plan,
  mesDraft,
  mesApplied,
  reiniciadoPorPiso,
  onMesDraftChange,
  onConsultar,
}: HistoricoVistaProps) {
  // Fail-closed (D-FE-46): A30 y A31 son entradas INDEPENDIENTES del CATALOG. Que compartan rol no
  // garantiza presencia atomica. Si falta alguna, no monta ninguna seccion y no se dispara ninguna
  // lectura (el contenedor pasa enabled:false a AMBOS hooks).
  if (faltaAccion) {
    return (
      <div className="mx-auto max-w-5xl space-y-4">
        <Cabecera />
        <Banner
          tono="aviso"
          titulo="No se pudo habilitar toda la información necesaria para mostrar el histórico y los acumulados."
        >
          Probá cerrar sesión y volver a entrar. Si sigue igual, avisale a un administrador.
        </Banner>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-5xl space-y-4">
      <Cabecera />
      <SeccionAcumulados acum={acum} />
      <SelectorMes
        plan={plan}
        mesDraft={mesDraft}
        cargandoAcum={acum.loading}
        fotoPendiente={fotoPendiente}
        seleccionFueraDePiso={seleccionFueraDePiso}
        reiniciadoPorPiso={reiniciadoPorPiso}
        onMesDraftChange={onMesDraftChange}
        onConsultar={onConsultar}
      />
      <SeccionFotoMes
        foto={foto}
        fotoPendiente={fotoPendiente}
        seleccionFueraDePiso={seleccionFueraDePiso}
        mesApplied={mesApplied}
      />
    </div>
  );
}
