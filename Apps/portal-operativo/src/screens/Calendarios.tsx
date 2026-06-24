import { useAction } from '../hooks/useAction';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { CalendarFrame } from '../ui/CalendarFrame';
import type { CalendarioHtmlData } from '../lib/contratos';

/**
 * Vista compartida de calendario HTML temporal (A03/A04, D-FE-03). Tres estados:
 * Cargando / ErrorCard (con reintentar) / contenido (CalendarFrame). El frontend
 * renderiza el HTML que devuelve el backend; no lo reinterpreta como datos.
 */
function CalendarioView({ action, titulo }: { action: string; titulo: string }) {
  const { data, loading, error, refetch } = useAction<CalendarioHtmlData>(action);

  return (
    <div className="mx-auto max-w-5xl space-y-4">
      <header>
        <p className="text-xs font-medium uppercase tracking-wide text-reed">{action}</p>
        <h2 className="mt-1 text-xl font-semibold text-ink">{titulo}</h2>
      </header>

      {loading && <Cargando mensaje="Cargando calendario..." />}
      {!loading && error && <ErrorCard error={error} onRetry={refetch} />}
      {!loading && !error && data && <CalendarFrame html={data.html} title={titulo} />}
    </div>
  );
}

/** A03 `calendario.limpieza` — visible para jenny/vicky/socio (unica lectura de jenny). */
export function CalendarioLimpieza() {
  return <CalendarioView action="calendario.limpieza" titulo="Calendario de limpieza" />;
}

/** A04 `calendario.operativo` — vicky/socio (jenny bloqueada por guard de ruta + backend). */
export function CalendarioOperativo() {
  return <CalendarioView action="calendario.operativo" titulo="Calendario operativo" />;
}
