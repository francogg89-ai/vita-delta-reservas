import type { ReactNode } from 'react';
import type {
  CabeceraFoto,
  CascadaFoto,
  GastoFoto,
  GastoSinIncidenciaFoto,
  HistoricoMesData,
  IncidenciaFoto,
  MatrizSocioFoto,
  MovimientoFoto,
  ParticipacionFoto,
  RetribucionOperativoFoto,
  SocioFoto,
} from '../../lib/contratos';
import { Banner } from '../../ui/Banner';
import { DataTable } from '../../ui/DataTable';
import type { Columna } from '../../ui/DataTable';
import { Money } from '../../ui/Money';
import { Tarjeta } from '../../ui/Tarjeta';
import { Vacio } from '../../ui/Vacio';
import { formatFecha } from '../../lib/formato';
import { etiquetaMes, ymDeFecha } from '../../lib/periodo';
import {
  CLASE_GASTO,
  DESTINO_INCIDENCIA,
  ESTADO_RETRIBUCION,
  MOTIVO_SIN_INCIDENCIA,
  TIPO_MOVIMIENTO,
  alcanceGasto,
  analizarFoto,
  comprobanteSeguro,
  formatFechaHora,
  formatNum,
  formatPct,
  incidenciaGasto,
  pagadorGasto,
  textoLinaje,
} from './foto';
import { Nat, NATURALEZA } from './naturaleza';
import type { Naturaleza } from './naturaleza';

// =============================================================================================
// Contenido de la seccion Foto del mes (A30). Componente PURO: sin hooks, sin red, sin auth.
//
// Recibe el `data` YA CLASIFICADO. La maquina de estados (inactivo / pendiente / error /
// INCONSISTENTE), el retry tokenizado, T1-T7 y la reconciliacion de piso viven en
// `HistoricoVista.SeccionFotoMes` y NO se tocan.
//
// QUE SE MUESTRA EN CADA ESTADO
//   E1  foto completa       cabecera + cascada + socios + retribucion + movimientos + DETALLE FINO
//   E2  foto pre-extension  cabecera + cascada + socios + retribucion + movimientos
//                           SIN detalle fino: no se renderiza NADA de esas secciones, ni siquiera
//                           un `Vacio`. "No aplica" no es "sin datos" -- el desglose no se congelo
//                           para ese periodo, no es que este vacio.
//   E3  sin foto            SOLO banner + estado minimo. Sin cabecera, sin cascada, sin socios,
//                           sin retribucion, sin movimientos, sin detalle fino.
//
// El colapsable usa <details>/<summary> nativo: cero hooks, accesible por teclado por defecto, y
// mantiene este modulo sin estado (mas facil de montar en el harness de SB-UI-6).
// =============================================================================================

/**
 * Entidad de la foto: ID CONGELADO + nombre VIVO.
 *
 * Las tablas del snapshot (`liquidacion_socio`, `liquidacion_participacion`,
 * `liquidacion_incidencia`) guardan SOLO IDs -- ningun nombre. A30 los resuelve con JOINS VIVOS
 * al catalogo actual (`liquidacion_socio ls JOIN socios s -> 'socio', s.nombre`). Si maniana se
 * renombra a un socio o a una cabaña, la foto de julio va a mostrar el nombre NUEVO.
 *
 * Por eso el ID va SIEMPRE adelante: es lo unico que quedo congelado y lo unico con lo que se
 * puede correlacionar la foto contra si misma. El nombre es una comodidad de lectura, no un dato
 * historico. El chip [F] de la tarjeta sigue valiendo para importes, IDs y relaciones -- que es
 * lo que efectivamente esta congelado.
 */
function Ent({ prefijo, id, nombre }: { prefijo: string; id: number; nombre: string }) {
  return (
    <span className="whitespace-nowrap">
      <span className="tabular-nums text-reed">
        {prefijo} #{id}
      </span>
      <span className="text-reed"> · </span>
      <span className="font-medium text-ink">{nombre}</span>
    </span>
  );
}

function Leyenda() {
  return (
    <div className="space-y-2 px-1">
      <div className="flex flex-wrap items-center gap-x-5 gap-y-1 text-xs text-reed">
        {(['congelado', 'vivo', 'mixto'] as const).map((n) => (
          <span key={n} className="inline-flex items-center gap-1.5">
            <Nat n={n} />
            {NATURALEZA[n].texto}
          </span>
        ))}
      </div>
      <p className="max-w-prose text-xs text-reed">
        Los importes, IDs y relaciones están congelados en la foto. Los nombres de socios y cabañas
        se resuelven desde el catálogo actual al consultar.
      </p>
    </div>
  );
}

function Fila({ label, nat, children }: { label: string; nat?: Naturaleza; children: ReactNode }) {
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 py-2.5">
      <dt className="flex items-center gap-1.5 text-sm text-reed">
        {label}
        {nat && <Nat n={nat} />}
      </dt>
      <dd className="text-sm text-ink">{children}</dd>
    </div>
  );
}

function FilaMonto({
  label,
  nat,
  monto,
  destacado,
}: {
  label: string;
  nat: Naturaleza;
  monto: number;
  destacado?: boolean;
}) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-2.5">
      <dt className="flex items-center gap-1.5 text-sm text-reed">
        {label}
        <Nat n={nat} />
      </dt>
      <dd className={'shrink-0 tabular-nums ' + (destacado ? 'text-base font-semibold' : 'text-sm')}>
        <Money monto={monto} />
      </dd>
    </div>
  );
}

/** Sub-seccion dentro del detalle fino (no puede ser otra `Tarjeta`: quedaria anidada). */
function Sub({ titulo, nota, children }: { titulo: string; nota?: ReactNode; children: ReactNode }) {
  return (
    <section>
      <p className="text-xs font-medium uppercase tracking-wide text-reed">{titulo}</p>
      {nota && <p className="mt-1 max-w-prose text-xs text-reed">{nota}</p>}
      <div className="mt-2">{children}</div>
    </section>
  );
}

// --------------------------------------------------------------------------------------------
// E1 / E2 -- Cabecera (CONGELADA)
// --------------------------------------------------------------------------------------------
function CabeceraCard({ c }: { c: CabeceraFoto }) {
  return (
    <Tarjeta titulo="Cabecera de la foto" acciones={<Nat n="congelado" />}>
      <dl className="divide-y divide-sand">
        <Fila label="Período">{etiquetaMes(ymDeFecha(c.periodo))}</Fila>
        <Fila label="Liquidación">
          <span className="tabular-nums">#{c.id_liquidacion}</span>
        </Fila>
        {/* `pct_operativo` es una FRACCION 0..1 (CHECK chk_liq_pct_rango). Nunca `Money`. */}
        <Fila label="% operativo">
          <span className="tabular-nums">{formatPct(c.pct_operativo)}</span>
        </Fila>
        <Fila label="Congelada por">
          {c.creado_por}
          <span className="text-reed"> · {formatFechaHora(c.created_at)}</span>
        </Fila>
        {c.comentario !== null && (
          <Fila label="Comentario">
            <span className="max-w-prose">{c.comentario}</span>
          </Fila>
        )}
        <Fila label="Linaje">{textoLinaje(c.linaje)}</Fila>
      </dl>
    </Tarjeta>
  );
}

// --------------------------------------------------------------------------------------------
// E1 / E2 -- Cascada (CONGELADA)
// --------------------------------------------------------------------------------------------
const COLS_CASCADA: Columna<CascadaFoto>[] = [
  {
    key: 'paso',
    header: 'Paso',
    render: (c) => <span className="tabular-nums text-reed">{c.paso}</span>,
  },
  { key: 'concepto', header: 'Concepto', render: (c) => <span className="text-ink">{c.concepto}</span> },
  { key: 'monto', header: 'Monto', align: 'right', render: (c) => <Money monto={c.monto} /> },
];

// --------------------------------------------------------------------------------------------
// E1 / E2 -- Resultado por socio (CONGELADO)
// --------------------------------------------------------------------------------------------
const COLS_SOCIOS: Columna<SocioFoto>[] = [
  {
    key: 'socio',
    header: 'Socio',
    render: (s) => <Ent prefijo="Socio" id={s.id_socio} nombre={s.socio} />,
  },
  { key: 'saldo_bruto', header: 'Saldo bruto', align: 'right', render: (s) => <Money monto={s.saldo_bruto} /> },
  { key: 'gastos_d', header: 'Gastos D', align: 'right', render: (s) => <Money monto={s.gastos_d} /> },
  { key: 'gastos_e', header: 'Gastos E', align: 'right', render: (s) => <Money monto={s.gastos_e} /> },
  {
    key: 'saldo_final',
    header: 'Saldo final',
    align: 'right',
    render: (s) => <Money monto={s.saldo_final} className="font-semibold" />,
  },
  {
    key: 'desembolsado_periodo',
    header: 'Desembolsado',
    align: 'right',
    render: (s) => <Money monto={s.desembolsado_periodo} />,
  },
];

// --------------------------------------------------------------------------------------------
// E1 / E2 -- Retribucion operativa (MIXTA)
// --------------------------------------------------------------------------------------------
function RetribucionCard({ r }: { r: RetribucionOperativoFoto }) {
  const est = ESTADO_RETRIBUCION[r.estado];
  return (
    <Tarjeta titulo="Retribución operativa">
      <dl className="divide-y divide-sand">
        <FilaMonto label="Calculado (foto)" nat="congelado" monto={r.calculado} />
        <FilaMonto label="Asignado (mayor)" nat="vivo" monto={r.asignado} />
        <FilaMonto label="Diferencia" nat="mixto" monto={r.diferencia} destacado />
        <div className="flex items-baseline justify-between gap-4 py-2.5">
          <dt className="flex items-center gap-1.5 text-sm text-reed">
            Estado
            <Nat n="mixto" />
          </dt>
          <dd>
            <span
              className={
                'inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium ' +
                est.clase
              }
            >
              {est.texto}
            </span>
          </dd>
        </div>
      </dl>
      <p className="mt-3 max-w-prose text-xs text-reed">
        El calculado sale de la foto congelada. El asignado, la diferencia y el estado se recalculan
        contra el mayor cada vez que consultás.
      </p>
    </Tarjeta>
  );
}

// --------------------------------------------------------------------------------------------
// E1 / E2 -- Movimientos del mes (VIVOS)
// --------------------------------------------------------------------------------------------
const COLS_MOVIMIENTOS: Columna<MovimientoFoto>[] = [
  {
    key: 'fecha',
    header: 'Fecha',
    render: (m) => <span className="whitespace-nowrap tabular-nums">{formatFecha(m.fecha)}</span>,
  },
  {
    key: 'socio',
    header: 'Socio',
    render: (m) => <span className="whitespace-nowrap font-medium text-ink">{m.socio}</span>,
  },
  {
    key: 'tipo',
    header: 'Tipo',
    render: (m) => <span className="whitespace-nowrap">{TIPO_MOVIMIENTO[m.tipo]}</span>,
  },
  { key: 'monto', header: 'Monto', align: 'right', render: (m) => <Money monto={m.monto} /> },
  { key: 'medio_pago', header: 'Medio', render: (m) => m.medio_pago ?? <span className="text-reed">—</span> },
  {
    key: 'periodo',
    header: 'Período imputado',
    render: (m) =>
      m.periodo !== null ? (
        <span className="whitespace-nowrap">{etiquetaMes(ymDeFecha(m.periodo))}</span>
      ) : (
        <span className="text-reed">—</span>
      ),
  },
  {
    key: 'comentario',
    header: 'Comentario',
    render: (m) =>
      m.comentario !== null ? (
        <span className="text-xs text-reed">{m.comentario}</span>
      ) : (
        <span className="text-reed">—</span>
      ),
  },
];

function MovimientosCard({ movimientos }: { movimientos: MovimientoFoto[] }) {
  return (
    <Tarjeta titulo="Movimientos del mes" acciones={<Nat n="vivo" />}>
      {/* D-CC-34 / H-N2. La lista se ventanea por FECHA; la conciliacion de la retribucion filtra
          por PERIODO. Son ventanas distintas y NO cuadran 1:1. Decirlo es obligatorio: un socio que
          intente cuadrar el "asignado" sumando esta lista va a llegar a otro numero. */}
      <p className="-mt-1 mb-3 max-w-prose text-xs text-reed">
        Se lee en vivo del mayor, ventaneado por <span className="font-medium text-ink">fecha</span>{' '}
        dentro de este mes. La conciliación de la retribución operativa, en cambio, filtra por{' '}
        <span className="font-medium text-ink">período imputado</span>: un movimiento con período de
        julio y fecha de agosto cuenta en la conciliación de julio, pero aparece en la lista de
        agosto.{' '}
        <span className="font-medium text-ink">
          Esta lista no explica 1:1 la conciliación de arriba.
        </span>
      </p>
      {movimientos.length === 0 ? (
        <Vacio mensaje="No hubo movimientos del mayor con fecha en este mes." />
      ) : (
        <DataTable
          columnas={COLS_MOVIMIENTOS}
          filas={movimientos}
          filaKey={(m) => m.id_movimiento}
        />
      )}
    </Tarjeta>
  );
}

// --------------------------------------------------------------------------------------------
// E1 -- Detalle fino (CONGELADO, colapsable)
// --------------------------------------------------------------------------------------------
const COLS_PARTICIPACION: Columna<ParticipacionFoto>[] = [
  {
    key: 'cabana',
    header: 'Cabaña',
    render: (p) => <Ent prefijo="Cabaña" id={p.id_cabana} nombre={p.cabana} />,
  },
  {
    // NO es plata: es el valor relativo de la cabaña.
    key: 'valor_relativo',
    header: 'Valor relativo',
    align: 'right',
    render: (p) => <span className="tabular-nums">{formatNum(p.valor_relativo)}</span>,
  },
  {
    key: 'beneficiario',
    header: 'Beneficiario',
    render: (p) => (
      <Ent prefijo="Beneficiario" id={p.id_socio_beneficiario} nombre={p.beneficiario} />
    ),
  },
  {
    key: 'participa',
    header: 'Participa',
    align: 'center',
    render: (p) => (p.participa ? 'Sí' : <span className="text-reed">No</span>),
  },
];

const COLS_MATRIZ: Columna<MatrizSocioFoto>[] = [
  {
    key: 'socio',
    header: 'Socio',
    render: (m) => <Ent prefijo="Socio" id={m.id_socio} nombre={m.socio} />,
  },
  {
    key: 'valor_socio',
    header: 'Valor del socio',
    align: 'right',
    render: (m) => <span className="tabular-nums">{formatNum(m.valor_socio)}</span>,
  },
  {
    key: 'valor_pool',
    header: 'Valor del pool',
    align: 'right',
    render: (m) => <span className="tabular-nums">{formatNum(m.valor_pool)}</span>,
  },
  {
    // Fraccion 0..1 -> porcentaje. Nunca `Money`.
    key: 'participacion',
    header: 'Participación',
    align: 'right',
    render: (m) => (
      <span className="tabular-nums font-semibold text-ink">{formatPct(m.participacion)}</span>
    ),
  },
];

const COLS_INCIDENCIAS: Columna<IncidenciaFoto>[] = [
  {
    key: 'id_gasto',
    header: 'Gasto',
    render: (i) => <span className="tabular-nums text-reed">#{i.id_gasto}</span>,
  },
  { key: 'seq', header: 'Seq', align: 'right', render: (i) => <span className="tabular-nums text-reed">{i.seq}</span> },
  {
    key: 'destino',
    header: 'Destino',
    render: (i) => <span className="whitespace-nowrap">{DESTINO_INCIDENCIA[i.destino]}</span>,
  },
  {
    // `socio` e `id_socio` son null sii destino='pool_pre_operativo' (CHECK chk_linc_destino_socio).
    key: 'socio',
    header: 'Socio',
    render: (i) =>
      i.id_socio !== null && i.socio !== null ? (
        <Ent prefijo="Socio" id={i.id_socio} nombre={i.socio} />
      ) : (
        <span className="text-reed">—</span>
      ),
  },
  {
    key: 'monto_incidido',
    header: 'Monto incidido',
    align: 'right',
    render: (i) => <Money monto={i.monto_incidido} />,
  },
  { key: 'regla', header: 'Regla', render: (i) => <span className="text-xs text-reed">{i.regla}</span> },
];

const COLS_GSI: Columna<GastoSinIncidenciaFoto>[] = [
  {
    key: 'id_gasto',
    header: 'Gasto',
    render: (g) => <span className="tabular-nums text-reed">#{g.id_gasto}</span>,
  },
  { key: 'clase', header: 'Clase', render: (g) => <span className="whitespace-nowrap">{CLASE_GASTO[g.clase]}</span> },
  { key: 'etiqueta', header: 'Etiqueta', render: (g) => <span className="text-ink">{g.etiqueta}</span> },
  { key: 'monto', header: 'Monto', align: 'right', render: (g) => <Money monto={g.monto} /> },
  {
    key: 'motivo',
    header: 'Motivo',
    render: (g) => <span className="whitespace-nowrap">{MOTIVO_SIN_INCIDENCIA[g.motivo]}</span>,
  },
];

function columnasGastos(nombreSocio: (id: number) => string | null): Columna<GastoFoto>[] {
  return [
    {
      // Punto de correlacion con Incidencias y con Gastos sin incidencia, que muestran el mismo
      // `#id_gasto`. No depende de `filaKey` (que es invisible para el que lee la pantalla).
      key: 'id_gasto',
      header: 'Gasto',
      render: (g) => <span className="tabular-nums text-reed">#{g.id_gasto}</span>,
    },
    {
      key: 'fecha',
      header: 'Fecha',
      render: (g) => <span className="whitespace-nowrap tabular-nums">{formatFecha(g.fecha)}</span>,
    },
    { key: 'clase', header: 'Clase', render: (g) => <span className="whitespace-nowrap">{CLASE_GASTO[g.clase]}</span> },
    {
      key: 'etiqueta',
      header: 'Etiqueta',
      render: (g) => {
        // SEGURIDAD: el `href` sale de `comprobanteSeguro`, NUNCA del valor crudo. Si el valor
        // existe pero no es http/https absoluta, se dice y no se enlaza.
        const href = g.comprobante_url !== null ? comprobanteSeguro(g.comprobante_url) : null;
        return (
          <div className="min-w-[10rem]">
            <div className="text-ink">{g.etiqueta}</div>
            {/* Procedencia CONGELADA: `creado_por` y `created_at` viven en `liquidacion_gasto`. */}
            <div className="mt-0.5 text-xs text-reed">
              Cargado por {g.creado_por} · {formatFechaHora(g.created_at)}
            </div>
            {g.comentario !== null && <div className="mt-0.5 text-xs text-reed">{g.comentario}</div>}
            {g.clase_sugerida !== null && g.clase_sugerida !== g.clase && (
              <div className="mt-0.5 text-xs text-reed">
                Clase sugerida al cargarlo: {g.clase_sugerida}
              </div>
            )}
            {g.comprobante_url !== null &&
              (href !== null ? (
                <a
                  href={href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="mt-0.5 inline-block text-xs text-river underline"
                >
                  Comprobante
                </a>
              ) : (
                <div className="mt-0.5 text-xs font-medium text-red-700">
                  Comprobante no enlazable: URL no segura
                </div>
              ))}
          </div>
        );
      },
    },
    {
      // IDs CRUDOS: la foto no trae los nombres, y resolverlos con constantes TEST no es portable.
      key: 'alcance',
      header: 'Alcance',
      render: (g) => <span className="whitespace-nowrap tabular-nums">{alcanceGasto(g)}</span>,
    },
    {
      key: 'pagador',
      header: 'Pagador',
      render: (g) => <span className="whitespace-nowrap">{pagadorGasto(g, nombreSocio)}</span>,
    },
    {
      key: 'medio_pago',
      header: 'Medio',
      render: (g) => g.medio_pago ?? <span className="text-reed">—</span>,
    },
    { key: 'monto', header: 'Monto', align: 'right', render: (g) => <Money monto={g.monto} /> },
    {
      key: 'incidencia',
      header: 'Incidencia',
      render: (g) => <span className="whitespace-nowrap text-xs">{incidenciaGasto(g)}</span>,
    },
  ];
}

/** Fila rotulada dentro de la card mobile de gasto (label a la izquierda, valor a la derecha). */
function ParGasto({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt className="shrink-0 text-reed">{label}</dt>
      <dd className="text-right text-ink">{children}</dd>
    </div>
  );
}

/**
 * Representacion MOBILE de un gasto congelado (fix de H-2). Card vertical: cada campo en su propia
 * linea, legible sin scroll horizontal ni filas gigantes casi vacias. En desktop/tablet se conserva
 * la tabla de 9 columnas (`columnasGastos`).
 *
 * Usa EXACTAMENTE los mismos helpers que la tabla (`alcanceGasto`, `pagadorGasto`, `incidenciaGasto`,
 * `comprobanteSeguro`, `Money`, `formatFecha`, `formatFechaHora`, `CLASE_GASTO`): no se duplica ni
 * una linea de formato ni de seguridad. Preserva: #id_gasto congelado (correlacion), fecha, clase,
 * etiqueta, alcance con IDs CRUDOS de zona/cabaña, pagador, medio de pago, monto, incidencia (que
 * incluye el motivo sin incidencia via `incidenciaGasto`), procedencia congelada (creado_por +
 * created_at), comentario, clase sugerida, comprobante SEGURO y los nullables.
 *
 * Pagador e Incidencia van en filas SEPARADAS y rotuladas a proposito: "quien pago" (Pagador) NO
 * es "a quien/como se imputo en el reparto" (Incidencia).
 *
 * Se EXPORTA para que `qa/probes.tsx` mida el componente productivo real, no una copia de prueba.
 */
export function GastoCardMobile({
  gasto,
  nombreSocio,
}: {
  gasto: GastoFoto;
  nombreSocio: (id: number) => string | null;
}) {
  const g = gasto;
  // SEGURIDAD: el href sale SIEMPRE de comprobanteSeguro, NUNCA del valor crudo. Si existe pero no
  // es http/https absoluta, se dice y no se enlaza.
  const href = g.comprobante_url !== null ? comprobanteSeguro(g.comprobante_url) : null;
  return (
    <div data-qa="gasto-card" data-qa-gasto-id={g.id_gasto} className="rounded-2xl border border-sand bg-white p-3 text-sm">
      <div className="flex items-baseline justify-between gap-3">
        <span className="tabular-nums text-reed">#{g.id_gasto}</span>
        <span className="shrink-0 text-base font-semibold tabular-nums">
          <Money monto={g.monto} />
        </span>
      </div>

      <div className="mt-1">
        <div className="text-ink">{g.etiqueta}</div>
        <div className="mt-0.5 text-xs text-reed">
          <span className="tabular-nums">{formatFecha(g.fecha)}</span>
          {' · '}
          {CLASE_GASTO[g.clase]}
        </div>
      </div>

      <dl className="mt-2 space-y-1">
        <ParGasto label="Pagador">{pagadorGasto(g, nombreSocio)}</ParGasto>
        <ParGasto label="Medio">{g.medio_pago ?? <span className="text-reed">—</span>}</ParGasto>
        <ParGasto label="Alcance">
          <span className="tabular-nums">{alcanceGasto(g)}</span>
        </ParGasto>
        <ParGasto label="Incidencia">{incidenciaGasto(g)}</ParGasto>
      </dl>

      <div className="mt-2 text-xs text-reed">
        Cargado por {g.creado_por} · {formatFechaHora(g.created_at)}
      </div>
      {g.comentario !== null && <div className="mt-0.5 text-xs text-reed">{g.comentario}</div>}
      {g.clase_sugerida !== null && g.clase_sugerida !== g.clase && (
        <div className="mt-0.5 text-xs text-reed">Clase sugerida al cargarlo: {g.clase_sugerida}</div>
      )}
      {g.comprobante_url !== null &&
        (href !== null ? (
          <a
            href={href}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-1 inline-block text-xs text-river underline"
          >
            Comprobante
          </a>
        ) : (
          <div className="mt-1 text-xs font-medium text-red-700">
            Comprobante no enlazable: URL no segura
          </div>
        ))}
    </div>
  );
}

function DetalleFino({ data }: { data: HistoricoMesData }) {
  const { incidenciasOrdenadas, nombreSocio } = analizarFoto(data);

  return (
    <details className="group rounded-2xl border border-sand bg-white">
      <summary className="flex cursor-pointer list-none items-center justify-between gap-3 p-4 [&::-webkit-details-marker]:hidden">
        <span className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-reed">
          Detalle fino
          <Nat n="congelado" />
        </span>
        <span className="text-xs text-river underline">
          <span className="group-open:hidden">Mostrar</span>
          <span className="hidden group-open:inline">Ocultar</span>
        </span>
      </summary>

      <div className="space-y-6 border-t border-sand p-4">
        <Sub
          titulo="Participación por cabaña"
          nota="El valor relativo es un peso de reparto, no un monto."
        >
          {data.participacion.length === 0 ? (
            <Vacio mensaje="La foto no congeló ninguna fila de participación para este mes." />
          ) : (
            <DataTable
              columnas={COLS_PARTICIPACION}
              filas={data.participacion}
              filaKey={(p) => p.id_cabana}
            />
          )}
        </Sub>

        <Sub
          titulo="Matriz por socio"
          nota="Valores relativos, no montos. La participación es la fracción «valor del socio / valor del pool»."
        >
          {/* Vacío LEGÍTIMO en E1: si ninguna cabaña cubrió el mes completo, el pool queda en cero
              y `matriz_participacion` no devuelve filas (WHERE valor_pool > 0). No es un error. */}
          {data.matriz_por_socio.length === 0 ? (
            <Vacio mensaje="Ninguna cabaña participó del pool este mes." />
          ) : (
            <DataTable
              columnas={COLS_MATRIZ}
              filas={data.matriz_por_socio}
              filaKey={(m) => m.id_socio}
            />
          )}
        </Sub>

        <Sub
          titulo="Gastos congelados"
          nota="Los IDs de zona y cabaña se muestran crudos: la foto congelada no incluye sus nombres."
        >
          {data.gastos.length === 0 ? (
            <Vacio mensaje="No hubo gastos internos en este mes." />
          ) : (
            <>
              {/* Desktop/tablet: tabla de 9 columnas (D-FE-15). Mobile: una card por gasto (fix
                  de H-2). Se muestran mutuamente excluyentes por breakpoint; `DataTable` no se toca. */}
              <div className="hidden md:block">
                <DataTable
                  columnas={columnasGastos(nombreSocio)}
                  filas={data.gastos}
                  filaKey={(g) => g.id_gasto}
                />
              </div>
              <div className="space-y-2 md:hidden">
                {data.gastos.map((g) => (
                  <GastoCardMobile key={g.id_gasto} gasto={g} nombreSocio={nombreSocio} />
                ))}
              </div>
            </>
          )}
        </Sub>

        <Sub titulo="Incidencias">
          {incidenciasOrdenadas.length === 0 ? (
            <Vacio mensaje="Ningún gasto incidió sobre un socio o sobre el pool este mes." />
          ) : (
            <DataTable
              columnas={COLS_INCIDENCIAS}
              filas={incidenciasOrdenadas}
              filaKey={(i) => `${i.id_gasto}#${i.seq}`}
            />
          )}
        </Sub>

        <Sub
          titulo="Gastos sin incidencia"
          nota="Subconjunto de los gastos de arriba: los que no incidieron sobre ningún socio."
        >
          {data.gastos_sin_incidencia.length === 0 ? (
            <Vacio mensaje="Todos los gastos del mes incidieron." />
          ) : (
            <DataTable
              columnas={COLS_GSI}
              filas={data.gastos_sin_incidencia}
              filaKey={(g) => g.id_gasto}
            />
          )}
        </Sub>
      </div>
    </details>
  );
}

// =============================================================================================
// Raiz
// =============================================================================================
export function ContenidoFoto({
  data,
  estado,
}: {
  data: HistoricoMesData;
  /** Ya clasificado y validado contra T1-T7. INCONSISTENTE nunca llega hasta acá. */
  estado: 'E1' | 'E2' | 'E3';
}) {
  const mes = etiquetaMes(ymDeFecha(data.periodo));

  // --- E3: sin foto congelada. Solo banner + estado minimo. --------------------------------
  // T6/T7 ya garantizaron cabecera === null y retribucion_operativo === null. No hay nada que
  // mostrar, y un `Vacio` por seccion daria a entender que la seccion existe pero vino sin datos.
  if (estado === 'E3') {
    return (
      <div className="space-y-4">
        <Banner tono="info" titulo="Este mes todavía no tiene foto congelada">
          Todavía no se corrió el cierre de {mes}. No hay cabecera, ni cascada, ni resultado por
          socio, ni retribución operativa: nada de eso existe hasta que el cierre se ejecute.
        </Banner>
        <Tarjeta titulo="Foto del mes">
          <dl className="divide-y divide-sand">
            <Fila label="Período">{mes}</Fila>
            <Fila label="Estado">Sin foto congelada.</Fila>
          </dl>
        </Tarjeta>
      </div>
    );
  }

  // --- E1 / E2 ------------------------------------------------------------------------------
  // T2/T4 ya garantizaron que cabecera y retribucion_operativo NO son null. El narrowing de TS no
  // lo sabe, asi que se chequea igual; si alguna fuera null aca, seria una violacion de contrato
  // que `clasificarFoto` habria mandado a INCONSISTENTE antes de llegar hasta este componente.
  const { cascadaOrdenada } = analizarFoto(data);

  return (
    <div className="space-y-4">
      {estado === 'E2' && (
        <Banner tono="info" titulo="Foto anterior a la extensión del detalle fino">
          La cascada y el resultado por socio están completos. El desglose gasto por gasto{' '}
          <span className="font-medium">no se congeló</span> para este período, así que no se
          muestra: no es que esté vacío, es que no existe.
        </Banner>
      )}

      {data.cabecera !== null && <CabeceraCard c={data.cabecera} />}

      <Tarjeta titulo="Cascada del cierre" acciones={<Nat n="congelado" />}>
        {cascadaOrdenada.length === 0 ? (
          <Vacio mensaje="La foto no congeló ningún paso de la cascada." />
        ) : (
          <DataTable columnas={COLS_CASCADA} filas={cascadaOrdenada} filaKey={(c) => c.paso} />
        )}
      </Tarjeta>

      <Tarjeta titulo="Resultado por socio" acciones={<Nat n="congelado" />}>
        {data.socios.length === 0 ? (
          <Vacio mensaje="La foto no congeló ningún resultado por socio." />
        ) : (
          <DataTable columnas={COLS_SOCIOS} filas={data.socios} filaKey={(s) => s.id_socio} />
        )}
      </Tarjeta>

      {data.retribucion_operativo !== null && <RetribucionCard r={data.retribucion_operativo} />}

      <MovimientosCard movimientos={data.movimientos} />

      {/* E2 NO renderiza el detalle fino: ni tarjetas, ni `Vacio`. El banner de arriba explica que
          no se congeló, que es distinto de estar vacío. */}
      {estado === 'E1' && <DetalleFino data={data} />}

      <Leyenda />
    </div>
  );
}
