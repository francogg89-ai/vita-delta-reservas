import type { ReactNode } from 'react';
import type {
  EvolucionAcum,
  HistoricoAcumuladosData,
  SaldoSocioAcum,
} from '../../lib/contratos';
import { Banner } from '../../ui/Banner';
import { DataTable } from '../../ui/DataTable';
import type { Columna } from '../../ui/DataTable';
import { Money } from '../../ui/Money';
import { Tarjeta } from '../../ui/Tarjeta';
import { Vacio } from '../../ui/Vacio';
import { formatARS, formatFecha } from '../../lib/formato';
import { etiquetaMes, ymDeFecha } from '../../lib/periodo';
import { analizarAcumulados } from './acumulados';

// =============================================================================================
// Contenido de la seccion Acumulados (A31). Componente PURO: sin hooks, sin red, sin auth.
// Recibe el `data` ya resuelto; el ciclo loading -> error -> data y el retry siguen viviendo en
// `HistoricoVista.SeccionAcumulados`, que es lo unico que cambia alla.
//
// NATURALEZA DEL DATO -- lo mas importante de esta pantalla. La misma tabla mezcla cifras
// CONGELADAS en la foto del cierre con cifras que se leen EN VIVO al consultar. Presentarlas sin
// distinguirlas induciria a error a un socio que mira su plata:
//
//   CONGELADO  ingresos, gastos, utilidad, repartos (totales y evolucion);
//              resultado_liquidacion y reembolso_desembolso (saldos por socio).
//   VIVO       retiros_acumulados; retiros_mes; movimientos (saldos por socio).
//   MIXTO      saldo_vivo = (congelado + congelado) + vivo.
// =============================================================================================

type Naturaleza = 'congelado' | 'vivo' | 'mixto';

const NATURALEZA: Record<Naturaleza, { sigla: string; texto: string; clase: string }> = {
  congelado: {
    sigla: 'F',
    texto: 'Congelado en la foto del cierre',
    clase: 'border-sand bg-mist text-reed',
  },
  vivo: {
    sigla: 'V',
    texto: 'En vivo al momento de consultar',
    clase: 'border-river/30 bg-river-light text-river-dark',
  },
  mixto: {
    sigla: 'M',
    texto: 'Mixto: parte congelada, parte en vivo',
    clase: 'border-amber-200 bg-amber-50 text-amber-800',
  },
};

function Nat({ n }: { n: Naturaleza }) {
  const c = NATURALEZA[n];
  return (
    <span
      role="img"
      aria-label={c.texto}
      title={c.texto}
      className={
        'inline-flex h-4 w-4 shrink-0 items-center justify-center rounded border ' +
        'text-[10px] font-semibold leading-none ' +
        c.clase
      }
    >
      {c.sigla}
    </span>
  );
}

function Leyenda() {
  return (
    <div className="flex flex-wrap items-center gap-x-5 gap-y-1 px-1 text-xs text-reed">
      {(['congelado', 'vivo', 'mixto'] as const).map((n) => (
        <span key={n} className="inline-flex items-center gap-1.5">
          <Nat n={n} />
          {NATURALEZA[n].texto}
        </span>
      ))}
    </div>
  );
}

// --------------------------------------------------------------------------------------------
// Totales
// --------------------------------------------------------------------------------------------
function FilaTotal({
  label,
  nat,
  monto,
  nota,
  destacado,
  children,
}: {
  label: string;
  nat: Naturaleza;
  monto: number;
  nota?: string;
  destacado?: boolean;
  children?: ReactNode;
}) {
  return (
    <div className="py-3">
      <div className="flex items-baseline justify-between gap-4">
        <dt
          className={
            'flex items-center gap-1.5 ' +
            (destacado ? 'text-sm font-medium text-ink' : 'text-sm text-reed')
          }
        >
          {label}
          <Nat n={nat} />
        </dt>
        <dd className={'shrink-0 tabular-nums ' + (destacado ? 'text-base font-semibold' : 'text-sm')}>
          <Money monto={monto} />
        </dd>
      </div>
      {nota && <p className="mt-1 max-w-prose text-xs text-reed">{nota}</p>}
      {children}
    </div>
  );
}

function SubFila({ label, monto }: { label: string; monto: number }) {
  return (
    <div className="flex items-baseline justify-between gap-4 text-xs">
      <dt className="text-reed">{label}</dt>
      <dd className="shrink-0 tabular-nums">
        <Money monto={monto} />
      </dd>
    </div>
  );
}

/**
 * Desglose de gastos con la IDENTIDAD VISIBLE. La identidad `a_paso2 + c_paso7 + d_e_socios ===
 * gastos_acumulados` se muestra SIEMPRE, cierre o no: si el socio ve tres numeros y un total, tiene
 * que poder verificar a ojo que cierran. Si no cierra, ademas del cartel de abajo hay un Banner
 * arriba -- pero las cifras se muestran igual, tal como llegaron.
 */
function DesgloseGastos({
  data,
  sumaDesglose,
  identidadOk,
}: {
  data: HistoricoAcumuladosData;
  sumaDesglose: number;
  identidadOk: boolean;
}) {
  const g = data.totales.gastos_desglose;
  return (
    <div className="mt-2 rounded-lg border border-sand bg-mist px-3 py-2">
      <dl className="space-y-1">
        <SubFila label="A · paso 2 (comunes)" monto={g.a_paso2} />
        <SubFila label="C · paso 7 (comunes operativos)" monto={g.c_paso7} />
        <SubFila label="D / E · imputados a socios" monto={g.d_e_socios} />
      </dl>
      <dl className="mt-2 border-t border-sand pt-2">
        <SubFila label="Suma del desglose" monto={sumaDesglose} />
      </dl>
      <p className={'mt-1 text-xs ' + (identidadOk ? 'text-reed' : 'font-medium text-red-700')}>
        {identidadOk
          ? 'Coincide con los gastos acumulados: la identidad cierra.'
          : `NO coincide con los gastos acumulados (${formatARS(data.totales.gastos_acumulados)}).`}
      </p>
    </div>
  );
}

// --------------------------------------------------------------------------------------------
// Evolucion
// --------------------------------------------------------------------------------------------
/**
 * `_k` es una key posicional. `periodo` no sirve como key: si el backend mandara periodos
 * repetidos (anomalia I2/orden), React tendria keys duplicadas -- y esas filas NO se deduplican
 * por contrato, se muestran todas.
 */
type FilaEvolucion = EvolucionAcum & { _k: string };

const COLS_EVOLUCION: Columna<FilaEvolucion>[] = [
  {
    key: 'periodo',
    header: 'Período',
    render: (f) => <span className="whitespace-nowrap">{etiquetaMes(ymDeFecha(f.periodo))}</span>,
  },
  { key: 'ingresos', header: 'Ingresos', align: 'right', render: (f) => <Money monto={f.ingresos} /> },
  { key: 'gastos', header: 'Gastos', align: 'right', render: (f) => <Money monto={f.gastos} /> },
  { key: 'utilidad', header: 'Utilidad', align: 'right', render: (f) => <Money monto={f.utilidad} /> },
  { key: 'repartos', header: 'Repartos', align: 'right', render: (f) => <Money monto={f.repartos} /> },
  {
    key: 'retiros_mes',
    header: 'Retiros del mes',
    align: 'right',
    render: (f) => <Money monto={f.retiros_mes} />,
  },
];

// --------------------------------------------------------------------------------------------
// Saldos por socio
// --------------------------------------------------------------------------------------------
const COLS_SALDOS: Columna<SaldoSocioAcum>[] = [
  {
    key: 'socio',
    header: 'Socio',
    render: (f) => <span className="whitespace-nowrap font-medium text-ink">{f.socio}</span>,
  },
  {
    key: 'resultado_liquidacion',
    header: 'Resultado liquidación',
    align: 'right',
    render: (f) => <Money monto={f.resultado_liquidacion} />,
  },
  {
    key: 'reembolso_desembolso',
    header: 'Reembolso / desembolso',
    align: 'right',
    render: (f) => <Money monto={f.reembolso_desembolso} />,
  },
  {
    key: 'movimientos',
    header: 'Movimientos',
    align: 'right',
    render: (f) => <Money monto={f.movimientos} />,
  },
  {
    key: 'saldo_vivo',
    header: 'Saldo vivo',
    align: 'right',
    render: (f) => <Money monto={f.saldo_vivo} className="font-semibold" />,
  },
];

/** Mapa columna -> naturaleza, arriba de cada tabla. `DataTable.header` es string, asi que la
 *  marca no puede ir en el <th>; ponerla aca la deja igual de inequivoca sin tocar `ui/`. */
function MapaNaturaleza({ grupos }: { grupos: Array<{ n: Naturaleza; cols: string }> }) {
  return (
    <p className="-mt-1 mb-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-reed">
      {grupos.map((g) => (
        <span key={g.n} className="inline-flex items-center gap-1.5">
          <Nat n={g.n} />
          {g.cols}
        </span>
      ))}
    </p>
  );
}

export function ContenidoAcumulados({ data }: { data: HistoricoAcumuladosData }) {
  const { evolucionOrdenada, anomalias, sumaDesglose, identidadGastosOk } =
    analizarAcumulados(data);

  const t = data.totales;
  const filasEvolucion: FilaEvolucion[] = evolucionOrdenada.map((e, i) => ({ ...e, _k: String(i) }));

  return (
    <div className="space-y-4">
      {/* Avisos NO destructivos. Ninguno oculta filas ni reemplaza cifras. */}
      {anomalias.map((a) => (
        <Banner key={a.codigo} tono="aviso">
          {a.mensaje}
        </Banner>
      ))}

      <Tarjeta titulo="Totales acumulados">
        <p className="-mt-1 mb-1 text-xs text-reed">
          Piso contable informado por el servidor: {formatFecha(data.piso)}.
        </p>
        <dl className="divide-y divide-sand">
          <FilaTotal label="Ingresos" nat="congelado" monto={t.ingresos_acumulados} />

          <FilaTotal label="Gastos" nat="congelado" monto={t.gastos_acumulados}>
            <DesgloseGastos
              data={data}
              sumaDesglose={sumaDesglose}
              identidadOk={identidadGastosOk}
            />
          </FilaTotal>

          <FilaTotal label="Utilidad" nat="congelado" monto={t.utilidad_acumulada} destacado />

          <FilaTotal label="Repartos" nat="congelado" monto={t.repartos_acumulados} />

          <FilaTotal
            label="Retiros acumulados"
            nat="vivo"
            monto={t.retiros_acumulados}
            nota={
              'Se lee en vivo del mayor, sin ventana por foto. Incluye retiros de meses que ' +
              'todavía no tienen foto de cierre, así que NO es la suma de la columna «Retiros del ' +
              'mes» de la evolución.'
            }
          />
        </dl>
      </Tarjeta>

      <Tarjeta
        titulo="Evolución por período"
        acciones={
          /* Dato INFORMADO por el servidor. No gobierna el vacío, no limita ni trunca la tabla, y
             se muestra igual si I2 está rota (ahí, además, sube el banner de cardinalidad y la
             discrepancia con la cantidad de filas queda a la vista). */
          <span className="text-xs text-reed">
            Fotos vigentes informadas:{' '}
            <span className="font-medium tabular-nums text-ink">{data.meta.fotos_vigentes}</span>
          </span>
        }
      >
        <MapaNaturaleza
          grupos={[
            { n: 'congelado', cols: 'Ingresos · Gastos · Utilidad · Repartos' },
            { n: 'vivo', cols: 'Retiros del mes' },
          ]}
        />
        {/* El vacío lo decide `evolucionOrdenada.length`, NUNCA `sin_datos` ni `meta`. La tabla
            sale EXCLUSIVAMENTE de `evolucionOrdenada`: se muestran todas las filas que llegaron. */}
        {filasEvolucion.length === 0 ? (
          <Vacio mensaje="Todavía no hay ninguna foto de cierre vigente." />
        ) : (
          <DataTable columnas={COLS_EVOLUCION} filas={filasEvolucion} filaKey={(f) => f._k} />
        )}
      </Tarjeta>

      <Tarjeta titulo="Saldos por socio">
        <MapaNaturaleza
          grupos={[
            { n: 'congelado', cols: 'Resultado liquidación · Reembolso / desembolso' },
            { n: 'vivo', cols: 'Movimientos' },
            { n: 'mixto', cols: 'Saldo vivo' },
          ]}
        />
        {/* Hay una fila por socio SIEMPRE, exista o no una foto: `sin_datos:true` NO implica
            `saldos_por_socio: []`. Por eso el vacío sale de la longitud, no de `sin_datos`. */}
        {data.saldos_por_socio.length === 0 ? (
          <Vacio mensaje="El servidor no devolvió ningún socio." />
        ) : (
          <DataTable
            columnas={COLS_SALDOS}
            filas={data.saldos_por_socio}
            filaKey={(f) => f.id_socio}
          />
        )}
      </Tarjeta>

      <Leyenda />
    </div>
  );
}
