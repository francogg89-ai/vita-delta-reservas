import { Link } from 'react-router-dom';
import { useAuth } from '../auth/useAuth';
import { useAction } from '../hooks/useAction';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { Vacio } from '../ui/Vacio';
import { DataTable, type Columna } from '../ui/DataTable';
import { Money } from '../ui/Money';
import { botonSecundario } from '../ui/estilos';
import type { CuentaCorrienteData, CuentaCorrienteFila } from '../lib/contratos';

// A27 (cuenta_corriente.al_dia) -- lectura socio-only. Clon del patron de CobranzaSaldos (A12):
// useAction sin payload + estados cargando/error/vacio/tabla. Montos via Money (negativos en rojo).
// El "vacio" lo decide la pantalla (filas.length===0), no el hook (D-C-47).
const COLUMNAS: Columna<CuentaCorrienteFila>[] = [
  { key: 'socio', header: 'Socio', render: (f) => f.socio },
  {
    key: 'previos',
    header: 'Meses previos',
    align: 'right',
    render: (f) => (f.liquidacion_meses_previos != null ? <Money monto={f.liquidacion_meses_previos} /> : '—'),
  },
  {
    key: 'encurso',
    header: 'Mes en curso',
    align: 'right',
    render: (f) => (f.liquidacion_mes_en_curso != null ? <Money monto={f.liquidacion_mes_en_curso} /> : '—'),
  },
  {
    key: 'reembolsos',
    header: 'Reembolsos',
    align: 'right',
    render: (f) => (f.reembolsos_acumulados != null ? <Money monto={f.reembolsos_acumulados} /> : '—'),
  },
  {
    key: 'movimientos',
    header: 'Movimientos',
    align: 'right',
    render: (f) => (f.movimientos != null ? <Money monto={f.movimientos} /> : '—'),
  },
  {
    key: 'saldo',
    header: 'Saldo al día',
    align: 'right',
    render: (f) => (f.saldo_al_dia != null ? <Money monto={f.saldo_al_dia} className="font-semibold" /> : '—'),
  },
];

export function CuentaCorriente() {
  const { contexto } = useAuth();
  const { data, loading, error, refetch } = useAction<CuentaCorrienteData>('cuenta_corriente.al_dia');
  // Visibilidad por A02 (autoridad de acciones), sin hardcodear rol: el boton solo aparece si el
  // backend expone la accion de retiro para este usuario. La ruta ademas la protege RutaProtegida.
  const puedeRetirar = contexto?.acciones.includes('cuenta_corriente.retirar') ?? false;

  return (
    <div className="mx-auto max-w-5xl space-y-4">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-reed">cuenta_corriente.al_dia</p>
          <h2 className="mt-1 text-xl font-semibold text-ink">Cuenta corriente</h2>
          <p className="mt-1 text-xs text-reed">
            Acumulado en vivo desde el inicio del año contable. El mes en curso es provisorio (el mes todavía no
            cerró). "Movimientos" son retiros y ajustes de socios.
          </p>
        </div>
        {puedeRetirar && (
          <Link to="/socios/retirar" className={botonSecundario}>Retirar saldo</Link>
        )}
      </header>

      {loading && <Cargando mensaje="Cargando cuenta corriente..." />}
      {!loading && error && <ErrorCard error={error} onRetry={refetch} />}
      {!loading && !error && data &&
        (data.filas.length === 0 ? (
          <Vacio mensaje="Todavía no hay movimientos en el año contable." />
        ) : (
          <DataTable columnas={COLUMNAS} filas={data.filas} filaKey={(f) => f.id_socio} />
        ))}
    </div>
  );
}
