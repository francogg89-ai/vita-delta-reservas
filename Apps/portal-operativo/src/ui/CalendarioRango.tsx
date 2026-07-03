import { useEffect, useRef, useState } from 'react';
import { useAction } from '../hooks/useAction';
import { formatFecha } from '../lib/formato';
import {
  hoyAR,
  mananaAR,
  sumarDias,
  ymDe,
  primerDiaMes,
  primerDiaMesSiguiente,
  mesSiguiente,
  mesAnterior,
  diasDelMes,
  offsetLunes,
} from '../lib/fecha';
import { inicioValido, maxFinSeleccionable, validarRango } from '../lib/disponibilidad';
import type { ModoCalendario } from '../lib/disponibilidad';
import type { DisponibilidadCabanaData, EstadoDisponibilidad } from '../lib/contratos';

// Calendario de seleccion de rango para UNA cabana (criterios de la matriz minima del Bloque C).
// Flujo: el form elige cabana -> recien ahi se habilita -> consulta A26 por mes visible ->
// pinta dias por estado de su NOCHE -> ocupada/bloqueada no elegibles -> checkout_disponible
// elegible -> el rango no puede cruzar una noche ocupada/bloqueada (la seleccion se capea en la
// primera noche ocupada). Backend = autoridad; esto previene. Componente CONTROLADO: el form
// mantiene fecha_in/fecha_out (A07) o fecha_desde/fecha_hasta (A08) y los recibe por desde/hasta.

interface Props {
  /** id de la cabana ya elegida en el form. null/0 -> calendario deshabilitado. */
  idCabana: number | null;
  /** 'reserva' (A07: inicio = check-in, no pasado) | 'bloqueo' (A08: fin = liberacion, no <= hoy). */
  modo: ModoCalendario;
  /** Valor controlado por el form (A07 fecha_in / A08 fecha_desde) o ''. */
  desde: string;
  /** Valor controlado por el form (A07 fecha_out / A08 fecha_hasta) o ''. */
  hasta: string;
  onChange: (desde: string, hasta: string) => void;
  labelDesde: string;
  labelHasta: string;
  errorDesde?: string;
  errorHasta?: string;
}

const DIAS_SEMANA = ['Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab', 'Dom'];
const NOMBRE_MES = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

// Tintes de estado, alineados conceptualmente con el calendario operativo (A04): ocupada en verde,
// bloqueada en gris, libre en blanco. La leyenda aclara la semantica.
const TINTE: Record<EstadoDisponibilidad, string> = {
  disponible: '#ffffff',
  checkout_disponible: '#ffffff',
  ocupada: '#cdeccd',
  bloqueada: '#d9d9d9',
};

const ESTADO_LEGIBLE: Record<EstadoDisponibilidad, string> = {
  disponible: 'disponible',
  checkout_disponible: 'disponible (con salida ese dia)',
  ocupada: 'ocupada',
  bloqueada: 'bloqueada',
};

function etiquetaMes(ym: string): string {
  const [y, m] = ym.split('-').map(Number);
  return `${NOMBRE_MES[m - 1]} ${y}`;
}

function diaNumero(ymd: string): string {
  return String(Number(ymd.slice(8, 10)));
}

export function CalendarioRango({
  idCabana,
  modo,
  desde,
  hasta,
  onChange,
  labelDesde,
  labelHasta,
  errorDesde,
  errorHasta,
}: Props) {
  const hoy = hoyAR();
  const manana = mananaAR();

  const [visibleYm, setVisibleYm] = useState<string>(() => ymDe(desde || hoy));
  // Cache atada a la cabana: si cambia la cabana, la cache vieja deja de valer de inmediato.
  const [cacheState, setCacheState] = useState<{ cabana: number | null; dias: Map<string, EstadoDisponibilidad> }>(
    () => ({ cabana: idCabana, dias: new Map() }),
  );
  const cache: Map<string, EstadoDisponibilidad> =
    cacheState.cabana === idCabana ? cacheState.dias : new Map();

  // Cabana anterior para distinguir el PRIMER montaje de un cambio real de cabana.
  const idCabanaAnterior = useRef<number | null>(idCabana);

  // Cambio de cabana: reinicia cache, vista y seleccion (la disponibilidad es por cabana).
  useEffect(() => {
    // Primer montaje: idCabanaAnterior.current === idCabana -> NO limpia, porque A07 puede venir
    // con fecha_in/fecha_out restaurados desde el borrador persistente. Solo reacciona al cambio
    // REAL de cabana despues del montaje.
    if (idCabanaAnterior.current === idCabana) return;
    idCabanaAnterior.current = idCabana;

    setCacheState({ cabana: idCabana, dias: new Map() });
    setVisibleYm(ymDe(desde || hoy));
    if (desde || hasta) onChange('', '');
    // Intencional: solo reacciona al cambio de cabana. Incluir desde/hasta/onChange reiniciaria
    // la seleccion en cada click. (No hay eslint en el build; se documenta el porque.)
  }, [idCabana]); // eslint-disable-line react-hooks/exhaustive-deps

  const mesCargado = cacheState.cabana === idCabana && cacheState.dias.has(primerDiaMes(visibleYm));

  const { data, loading, error } = useAction<DisponibilidadCabanaData>(
    'disponibilidad.cabana',
    {
      id_cabana: idCabana ?? 0,
      fecha_desde: primerDiaMes(visibleYm),
      fecha_hasta: primerDiaMesSiguiente(visibleYm),
    },
    { enabled: idCabana !== null && !mesCargado },
  );

  // Acumula los dias recibidos en la cache (clave por fecha: no importa el mes visible al fusionar).
  useEffect(() => {
    if (!data) return;
    // Blindaje anti-respuesta-stale (carrera cabana A -> B): A26 estampa id_cabana en CADA noche
    // (obtener_disponibilidad_rango: matriz = cabanas_activas CROSS JOIN dias; libres incluidas).
    // Si la respuesta no corresponde a la cabana actual, se IGNORA COMPLETA: nunca fusion parcial.
    if (idCabana === null) return;
    if (data.dias.some((d) => d.id_cabana !== idCabana)) return;
    setCacheState((prev) => {
      if (prev.cabana !== idCabana) return prev; // data de otra cabana / aun sin reinicio
      const dias = new Map(prev.dias);
      for (const d of data.dias) dias.set(d.fecha, d.estado);
      return { cabana: idCabana, dias };
    });
  }, [data, idCabana]);

  const fase: 'inicio' | 'fin' = desde && !hasta ? 'fin' : 'inicio';
  const maxFin = fase === 'fin' ? maxFinSeleccionable(desde, cache) : null;
  const minFin =
    fase === 'fin'
      ? (() => {
          const base = sumarDias(desde, 1);
          return modo === 'bloqueo' && base < manana ? manana : base;
        })()
      : '';

  function celdaHabilitada(ymd: string): boolean {
    if (cache.get(ymd) === undefined) return false; // no cargada
    if (fase === 'inicio') return inicioValido(ymd, modo, hoy, cache);
    // fase 'fin' (desde fijo, hasta vacio)
    if (ymd <= desde) return inicioValido(ymd, modo, hoy, cache); // click en/antes del inicio -> reinicia
    if (!maxFin) return false;
    return ymd >= minFin && ymd <= maxFin;
  }

  function clickDia(ymd: string) {
    if (!celdaHabilitada(ymd)) return;
    if (fase === 'inicio' || ymd <= desde) {
      onChange(ymd, '');
      return;
    }
    onChange(desde, ymd);
  }

  function enRango(ymd: string): boolean {
    return !!desde && !!hasta && ymd >= desde && ymd <= hasta;
  }

  // Mensaje de validacion del rango ya elegido (refuerzo; la seleccion ya impide rangos invalidos).
  const validacion = desde && hasta ? validarRango(desde, hasta, modo, manana, cache) : null;
  let avisoRango: string | null = null;
  if (validacion && !validacion.ok) {
    if (validacion.motivo === 'falta_cargar') {
      avisoRango = 'Falta cargar la disponibilidad de algun dia del rango. Navega ese mes y reintenta.';
    } else if (validacion.motivo === 'noche_no_elegible') {
      avisoRango = 'El rango incluye una noche ocupada o bloqueada. No se puede confirmar asi.';
    } else if (validacion.motivo === 'fecha_hasta_pasada') {
      avisoRango = 'La fecha de liberacion debe ser posterior a hoy.';
    } else {
      avisoRango = 'El fin del rango debe ser posterior al inicio.';
    }
  }

  const celdaBase =
    'relative flex h-10 items-center justify-center rounded-md text-sm select-none';

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <span className="block text-sm font-medium text-reed">
          {labelDesde} <span aria-hidden className="text-river-dark">*</span>
          <span className="mx-1 text-sand">/</span>
          {labelHasta} <span aria-hidden className="text-river-dark">*</span>
        </span>
        {(desde || hasta) && (
          <button
            type="button"
            onClick={() => onChange('', '')}
            className="text-xs text-river underline-offset-2 hover:underline"
          >
            Limpiar
          </button>
        )}
      </div>

      {idCabana === null ? (
        <div className="rounded-lg border border-dashed border-sand bg-mist px-3 py-6 text-center text-sm text-reed">
          Elegi primero una cabana para ver la disponibilidad.
        </div>
      ) : (
        <div className="rounded-2xl border border-sand bg-white p-3">
          {/* Encabezado de mes + navegacion */}
          <div className="mb-2 flex items-center justify-between">
            <button
              type="button"
              onClick={() => setVisibleYm(mesAnterior(visibleYm))}
              className="rounded-md border border-sand px-2 py-1 text-sm text-ink hover:bg-mist"
              aria-label="Mes anterior"
            >
              {'\u2039'}
            </button>
            <span className="text-sm font-semibold capitalize text-ink">{etiquetaMes(visibleYm)}</span>
            <button
              type="button"
              onClick={() => setVisibleYm(mesSiguiente(visibleYm))}
              className="rounded-md border border-sand px-2 py-1 text-sm text-ink hover:bg-mist"
              aria-label="Mes siguiente"
            >
              {'\u203A'}
            </button>
          </div>

          {/* Cabecera de dias de la semana (arranca lunes) */}
          <div className="grid grid-cols-7 gap-1 text-center text-xs text-reed">
            {DIAS_SEMANA.map((d) => (
              <div key={d} className="py-1">{d}</div>
            ))}
          </div>

          {/* Grilla de dias */}
          <div className="mt-1 grid grid-cols-7 gap-1">
            {Array.from({ length: offsetLunes(visibleYm) }).map((_, i) => (
              <div key={`pad-${i}`} aria-hidden />
            ))}
            {diasDelMes(visibleYm).map((ymd) => {
              const estado = cache.get(ymd);
              const habil = celdaHabilitada(ymd);
              const esInicio = ymd === desde;
              const esFin = ymd === hasta;
              const dentro = enRango(ymd);
              const esCheckout = estado === 'checkout_disponible';

              // Estilo: seleccion (river) tiene prioridad visual sobre el tinte de estado.
              let clase = celdaBase;
              const style: { backgroundColor?: string } = {};
              if (esInicio || esFin) {
                clase += ' bg-river font-semibold text-white';
              } else if (dentro) {
                clase += ' bg-river-light text-ink';
              } else if (estado === undefined) {
                clase += ' text-reed';
                style.backgroundColor = '#f4f6f5';
              } else {
                clase += ' text-ink';
                style.backgroundColor = TINTE[estado];
              }
              if (habil) clase += ' cursor-pointer hover:ring-2 hover:ring-river';
              else clase += ' cursor-not-allowed';
              if (!habil && !esInicio && !esFin && !dentro) clase += ' opacity-60';

              const etiquetaEstado = estado ? ESTADO_LEGIBLE[estado] : 'sin cargar';
              return (
                <button
                  key={ymd}
                  type="button"
                  disabled={!habil}
                  onClick={() => clickDia(ymd)}
                  className={clase}
                  style={style}
                  aria-label={`${diaNumero(ymd)} de ${etiquetaMes(visibleYm)}, ${etiquetaEstado}`}
                  aria-pressed={esInicio || esFin}
                >
                  {diaNumero(ymd)}
                  {esCheckout && !esInicio && !esFin && !dentro && (
                    <span
                      aria-hidden
                      className="absolute right-1 top-0.5 text-[9px] leading-none text-reed"
                    >
                      sale
                    </span>
                  )}
                </button>
              );
            })}
          </div>

          {/* Estado de carga / error de A26 (no rompe la UI) */}
          {loading && <p className="mt-2 text-xs text-reed">Cargando disponibilidad...</p>}
          {!loading && error && (
            <p className="mt-2 text-xs text-red-600">
              {error.code === 'no_encontrado'
                ? 'Esa cabana no esta disponible (inexistente o inactiva).'
                : 'No se pudo cargar la disponibilidad. Proba navegar el mes de nuevo.'}
            </p>
          )}

          {/* Leyenda (parecida al calendario operativo) */}
          <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-reed">
            <span className="inline-flex items-center gap-1">
              <span className="inline-block h-3 w-3 rounded-sm border border-sand" style={{ backgroundColor: '#ffffff' }} /> Libre
            </span>
            <span className="inline-flex items-center gap-1">
              <span className="inline-block h-3 w-3 rounded-sm border border-sand" style={{ backgroundColor: TINTE.ocupada }} /> Ocupada
            </span>
            <span className="inline-flex items-center gap-1">
              <span className="inline-block h-3 w-3 rounded-sm border border-sand" style={{ backgroundColor: TINTE.bloqueada }} /> Bloqueada
            </span>
            <span className="inline-flex items-center gap-1">
              <span className="inline-block h-3 w-3 rounded-sm bg-river" /> Tu seleccion
            </span>
          </div>

          {/* Lectura de la seleccion actual + ayuda contextual */}
          <div className="mt-2 text-sm text-ink">
            {desde ? (
              <span>
                <span className="text-reed">{labelDesde}:</span> {formatFecha(desde)}
                {hasta ? (
                  <>
                    {' '}<span className="text-reed">· {labelHasta}:</span> {formatFecha(hasta)}
                  </>
                ) : (
                  <span className="text-reed"> · elegi {labelHasta.toLowerCase()}</span>
                )}
              </span>
            ) : (
              <span className="text-reed">Elegi {labelDesde.toLowerCase()} en el calendario.</span>
            )}
          </div>

          {avisoRango && <p className="mt-1 text-xs text-red-600">{avisoRango}</p>}
          {(errorDesde || errorHasta) && (
            <p className="mt-1 text-xs text-red-600">{errorDesde || errorHasta}</p>
          )}
        </div>
      )}
    </div>
  );
}
