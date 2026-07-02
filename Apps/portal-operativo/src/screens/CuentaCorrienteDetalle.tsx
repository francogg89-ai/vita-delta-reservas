import { useMemo, useState } from 'react';
import { useAction } from '../hooks/useAction';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { Vacio } from '../ui/Vacio';
import { DataTable, type Columna } from '../ui/DataTable';
import { Money } from '../ui/Money';
import { FLOOR_MES } from '../lib/constantes';
import { mesActualOFloor, primerDiaMes } from '../lib/periodo';
import type {
  CuentaCorrienteDetalleData,
  MatrizSocioDetalle,
  MatrizCabanaDetalle,
  IncidenciaGastoFila,
} from '../lib/contratos';

// ---- helpers de mes ----
const MESES_ES = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
function etiquetaMes(ym: string): string {
  const [y, m] = ym.split('-').map(Number);
  return `${MESES_ES[m - 1]} ${y}`;
}
function mesesDisponibles(): string[] {
  const out: string[] = [];
  const [fy, fm] = mesActualOFloor(FLOOR_MES).split('-').map(Number);
  let [y, m] = FLOOR_MES.split('-').map(Number);
  while (y < fy || (y === fy && m <= fm)) {
    out.push(`${y}-${String(m).padStart(2, '0')}`);
    m += 1;
    if (m > 12) { m = 1; y += 1; }
  }
  return out.reverse(); // más reciente primero
}

// ---- cascada: etiquetas de los pasos agregados ----
const LABEL_PASO: Record<string, string> = {
  ingreso_operativo_sena_saldo_confirmados: 'Ingreso operativo (seña + saldo)',
  gastos_clase_A: 'Gastos clase A',
  base_operativa: 'Base operativa',
  retribucion_operativo_sobre_base_positiva: 'Retribución operativo (25%)',
  resultado_post_operativo: 'Resultado post-operativo',
  ingresos_extra_post_operativo: 'Ingresos extra',
  gastos_clase_C: 'Gastos clase C',
  base_de_ganancia: 'Base de ganancia',
};
function labelConcepto(c: string): string {
  return LABEL_PASO[c] ?? c.replace(/_/g, ' ');
}
function pct(v: number | null): string {
  return v == null ? '—' : `${(v * 100).toFixed(2)}%`;
}

function Tarjeta({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <section className="rounded-2xl border border-sand bg-white p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-reed">{titulo}</p>
      <div className="mt-3">{children}</div>
    </section>
  );
}

// ---- secciones ----
function SeccionCascada({ data }: { data: CuentaCorrienteDetalleData }) {
  const agregados = data.cascada
    .filter((p) => p.id_socio == null)
    .sort((a, b) => a.paso - b.paso);

  type FilaSocio = { id_socio: number; socio: string; p9: number | null; p10: number | null; p11: number | null };
  const porSocio = useMemo(() => {
    const map = new Map<number, FilaSocio>();
    for (const p of data.cascada) {
      if (p.id_socio == null) continue;
      const e = map.get(p.id_socio) ?? { id_socio: p.id_socio, socio: p.socio ?? '', p9: null, p10: null, p11: null };
      if (p.paso === 9) e.p9 = p.monto;
      if (p.paso === 10) e.p10 = p.monto;
      if (p.paso === 11) e.p11 = p.monto;
      map.set(p.id_socio, e);
    }
    return Array.from(map.values());
  }, [data.cascada]);

  const colsSocio: Columna<FilaSocio>[] = [
    { key: 'socio', header: 'Socio', render: (f) => f.socio },
    { key: 'p9', header: 'Reparto', align: 'right', render: (f) => (f.p9 != null ? <Money monto={f.p9} /> : '—') },
    { key: 'p10', header: 'Incidencias D/E', align: 'right', render: (f) => (f.p10 != null ? <Money monto={f.p10} /> : '—') },
    { key: 'p11', header: 'Saldo final', align: 'right', render: (f) => (f.p11 != null ? <Money monto={f.p11} className="font-semibold" /> : '—') },
  ];

  return (
    <Tarjeta titulo="Cascada del mes">
      {agregados.length === 0 ? (
        <Vacio mensaje="Sin actividad contable en este mes." />
      ) : (
        <>
          <ul className="space-y-1 text-sm">
            {agregados.map((p) => (
              <li key={p.paso} className="flex items-center justify-between gap-3 border-b border-sand/60 pb-1 last:border-0">
                <span className="text-ink">
                  <span className="text-reed">{p.paso}.</span> {labelConcepto(p.concepto)}
                </span>
                {p.monto != null ? <Money monto={p.monto} /> : <span className="text-reed">—</span>}
              </li>
            ))}
          </ul>
          {porSocio.length > 0 && (
            <div className="mt-4">
              <p className="mb-2 text-xs text-reed">Reparto por socio (pasos 9-11)</p>
              <DataTable columnas={colsSocio} filas={porSocio} filaKey={(f) => f.id_socio} />
            </div>
          )}
        </>
      )}
    </Tarjeta>
  );
}

function SeccionMatriz({ data }: { data: CuentaCorrienteDetalleData }) {
  const colsSocio: Columna<MatrizSocioDetalle>[] = [
    { key: 'socio', header: 'Socio', render: (f) => f.socio },
    { key: 'part', header: 'Participación', align: 'right', render: (f) => pct(f.participacion) },
    {
      key: 'valor',
      header: 'Valor / pool',
      align: 'right',
      render: (f) => `${f.valor_socio ?? '—'} / ${f.valor_pool ?? '—'}`,
    },
  ];
  const colsCabana: Columna<MatrizCabanaDetalle>[] = [
    { key: 'cabana', header: 'Cabaña', render: (f) => f.cabana },
    { key: 'vr', header: 'Valor relativo', align: 'right', render: (f) => (f.valor_relativo ?? '—').toString() },
    { key: 'benef', header: 'Beneficiario', render: (f) => f.beneficiario },
    { key: 'participa', header: 'Participa', render: (f) => (f.participa ? 'Sí' : 'No') },
  ];

  return (
    <Tarjeta titulo="Matriz de participación">
      {data.matriz.length === 0 ? (
        <Vacio mensaje="Sin pool este mes (ninguna cabaña cubre el mes completo)." />
      ) : (
        <DataTable columnas={colsSocio} filas={data.matriz} filaKey={(f) => f.id_socio} />
      )}
      <div className="mt-4">
        <p className="mb-2 text-xs text-reed">Detalle por cabaña</p>
        <DataTable columnas={colsCabana} filas={data.matriz_cabanas} filaKey={(f) => f.id_cabana} />
      </div>
    </Tarjeta>
  );
}

function SeccionIncidencias({ data }: { data: CuentaCorrienteDetalleData }) {
  const cols: Columna<IncidenciaGastoFila>[] = [
    { key: 'gasto', header: 'Gasto', render: (f) => <span className="text-ink">{f.etiqueta} <span className="text-reed">#{f.id_gasto}</span></span> },
    { key: 'clase', header: 'Clase', render: (f) => f.clase },
    { key: 'monto', header: 'Monto', align: 'right', render: (f) => (f.monto != null ? <Money monto={f.monto} /> : '—') },
    { key: 'afectado', header: 'Afectado', render: (f) => f.socio ?? 'pool' },
    { key: 'incidido', header: 'Incidido', align: 'right', render: (f) => (f.monto_incidido != null ? <Money monto={f.monto_incidido} /> : '—') },
    { key: 'regla', header: 'Regla', render: (f) => <span className="text-xs text-reed">{f.regla}</span> },
  ];

  return (
    <Tarjeta titulo="Incidencias por gasto">
      {data.incidencias.length === 0 ? (
        <Vacio mensaje="Sin gastos con incidencia en este mes." />
      ) : (
        <DataTable columnas={cols} filas={data.incidencias} filaKey={(f) => `${f.id_gasto}-${f.id_socio ?? 'pool'}`} />
      )}
      {data.gastos_sin_incidencia.length > 0 && (
        <p className="mt-3 text-xs text-reed">
          Gastos sin incidencia (pool vacío): {data.gastos_sin_incidencia.map((g) => `${g.etiqueta} (#${g.id_gasto})`).join(', ')}
        </p>
      )}
    </Tarjeta>
  );
}

export function CuentaCorrienteDetalle() {
  const meses = useMemo(() => mesesDisponibles(), []);
  const [mesSel, setMesSel] = useState(meses[0] ?? FLOOR_MES);
  const payload = useMemo(() => ({ mes: primerDiaMes(mesSel) }), [mesSel]);
  const { data, loading, error, refetch } = useAction<CuentaCorrienteDetalleData>('cuenta_corriente.detalle', payload);

  const selectCls = 'mt-1 rounded-lg border border-sand px-3 py-2 text-ink outline-none focus:border-river';

  return (
    <div className="mx-auto max-w-5xl space-y-4">
      <header>
        <p className="text-xs font-medium uppercase tracking-wide text-reed">cuenta_corriente.detalle</p>
        <h2 className="mt-1 text-xl font-semibold text-ink">Detalle mensual</h2>
        <p className="mt-1 text-xs text-reed">
          Desglose del mes: cómo se llega a la base de ganancia, cómo se reparte por socio, y qué gasto incide en quién.
        </p>
      </header>

      <div>
        <label className="text-xs font-medium uppercase tracking-wide text-reed" htmlFor="mes">Mes</label>
        <div>
          <select id="mes" className={selectCls} value={mesSel} onChange={(e) => setMesSel(e.target.value)}>
            {meses.map((m) => (
              <option key={m} value={m}>{etiquetaMes(m)}</option>
            ))}
          </select>
        </div>
      </div>

      {loading && <Cargando mensaje="Cargando detalle..." />}
      {!loading && error && <ErrorCard error={error} onRetry={refetch} />}
      {!loading && !error && data && (
        <div className="space-y-4">
          <SeccionCascada data={data} />
          <SeccionMatriz data={data} />
          <SeccionIncidencias data={data} />
        </div>
      )}
    </div>
  );
}
