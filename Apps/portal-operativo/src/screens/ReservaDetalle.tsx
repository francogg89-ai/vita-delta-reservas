import { useState } from 'react';
import type { ReactNode } from 'react';
import { useAction } from '../hooks/useAction';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { Vacio } from '../ui/Vacio';
import { Money } from '../ui/Money';
import { Fecha } from '../ui/Fecha';
import { EstadoBadge } from '../ui/EstadoBadge';
import { DataTable, type Columna } from '../ui/DataTable';
import type { ReservaDetalleData, ReservaPago } from '../lib/contratos';

const COLS_PAGOS: Columna<ReservaPago>[] = [
  { key: 'tipo', header: 'Tipo', render: (p) => p.tipo },
  { key: 'medio', header: 'Medio', render: (p) => p.medio_pago ?? '—' },
  { key: 'recibido', header: 'Recibido', align: 'right', render: (p) => (p.monto_recibido != null ? <Money monto={p.monto_recibido} /> : '—') },
  { key: 'estado', header: 'Estado', render: (p) => <EstadoBadge estado={p.estado} /> },
  { key: 'fecha', header: 'Fecha', render: (p) => <Fecha valor={p.created_at} /> },
];

/** Valida el id tipeado: entero positivo seguro (espeja la validación del gateway). */
function parseId(s: string): number | null {
  const t = s.trim();
  if (!/^\d+$/.test(t)) return null;
  const n = Number(t);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
}

function Campo({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <dt className="text-xs text-reed">{label}</dt>
      <dd className="mt-0.5 text-ink">{children}</dd>
    </div>
  );
}

function Tarjeta({ label, valor, resaltar }: { label: string; valor: number | null; resaltar?: boolean }) {
  return (
    <div className={'rounded-2xl border bg-white p-4 ' + (resaltar ? 'border-river/40' : 'border-sand')}>
      <p className="text-xs text-reed">{label}</p>
      <p className="mt-1 text-lg font-semibold">{valor != null ? <Money monto={valor} /> : '—'}</p>
    </div>
  );
}

function DetalleReserva({ data }: { data: ReservaDetalleData }) {
  const r = data.reserva;
  const hayExtras = Boolean(r.mascotas || r.ninos != null || r.notas_reserva || r.notas || r.detalle_mascotas);

  return (
    <div className="space-y-4">
      <div className="rounded-2xl border border-sand bg-white p-6">
        <div className="flex items-center justify-between gap-3">
          <h3 className="text-lg font-semibold text-ink">
            {r.cabana} · #{r.id_reserva}
          </h3>
          <EstadoBadge estado={r.estado} />
        </div>
        <dl className="mt-4 grid grid-cols-2 gap-4 md:grid-cols-3">
          <Campo label="Check-in">
            <Fecha valor={r.fecha_checkin} />
            {r.hora_checkin ? ` ${r.hora_checkin}` : ''}
          </Campo>
          <Campo label="Check-out">
            <Fecha valor={r.fecha_checkout} />
            {r.hora_checkout ? ` ${r.hora_checkout}` : ''}
          </Campo>
          <Campo label="Personas">{r.personas}</Campo>
          <Campo label="Huésped">{r.huesped.nombre ?? '—'}</Campo>
          <Campo label="Teléfono">{r.huesped.telefono ?? '—'}</Campo>
          <Campo label="Email">{r.huesped.email ?? '—'}</Campo>
        </dl>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Tarjeta label="Monto total" valor={r.monto_total} />
        <Tarjeta label="Seña" valor={r.monto_sena} />
        <Tarjeta label="Pagado" valor={r.total_pagado_confirmado} />
        <Tarjeta label="Saldo" valor={r.saldo_real} resaltar />
      </div>

      {hayExtras && (
        <div className="space-y-1 rounded-2xl border border-sand bg-white p-6 text-sm">
          {r.mascotas && (
            <p>
              <span className="text-reed">Mascotas:</span> sí{r.detalle_mascotas ? ` — ${r.detalle_mascotas}` : ''}
            </p>
          )}
          {r.ninos != null && (
            <p>
              <span className="text-reed">Niños:</span> {r.ninos}
            </p>
          )}
          {r.notas_reserva && (
            <p>
              <span className="text-reed">Notas de reserva:</span> {r.notas_reserva}
            </p>
          )}
          {r.notas && (
            <p>
              <span className="text-reed">Notas:</span> {r.notas}
            </p>
          )}
        </div>
      )}

      <div>
        <h4 className="mb-2 text-sm font-medium text-reed">Pagos</h4>
        {data.pagos.length === 0 ? (
          <Vacio mensaje="Sin pagos registrados." />
        ) : (
          <DataTable columnas={COLS_PAGOS} filas={data.pagos} filaKey={(p) => p.id_pago} />
        )}
      </div>
    </div>
  );
}

export function ReservaDetalle() {
  const [draft, setDraft] = useState('');
  const [idBuscado, setIdBuscado] = useState<number | null>(null);
  const idValido = parseId(draft);

  const { data, loading, error, refetch } = useAction<ReservaDetalleData>(
    'reserva.detalle',
    { id_reserva: idBuscado ?? 0 },
    { enabled: idBuscado != null },
  );

  function buscar() {
    if (idValido != null) setIdBuscado(idValido);
  }

  return (
    <div className="mx-auto max-w-4xl space-y-4">
      <header>
        <p className="text-xs font-medium uppercase tracking-wide text-reed">reserva.detalle</p>
        <h2 className="mt-1 text-xl font-semibold text-ink">Detalle de reserva</h2>
      </header>

      <div className="flex items-end gap-2 rounded-2xl border border-sand bg-white p-4">
        <label className="flex-1">
          <span className="block text-sm text-reed">ID de reserva</span>
          <input
            type="text"
            inputMode="numeric"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') buscar();
            }}
            placeholder="Ej. 13"
            className="mt-1 w-full rounded-lg border border-sand px-3 py-2 text-ink outline-none focus:border-river"
          />
        </label>
        <button
          type="button"
          onClick={buscar}
          disabled={idValido == null}
          className="rounded-lg bg-river px-4 py-2 text-sm font-medium text-white transition hover:bg-river-dark disabled:cursor-not-allowed disabled:opacity-40"
        >
          Buscar
        </button>
      </div>

      {/* Estados: solo después de buscar. Cargando cubre el gap hasta tener data/error.
          no_encontrado se muestra suave (no como error rojo); el resto via ErrorCard. */}
      {idBuscado != null &&
        (error ? (
          error.code === 'no_encontrado' ? (
            <Vacio mensaje={`No existe una reserva con ID ${idBuscado}.`} />
          ) : (
            <ErrorCard error={error} onRetry={refetch} />
          )
        ) : data && !loading ? (
          <DetalleReserva data={data} />
        ) : (
          <Cargando mensaje="Cargando reserva..." />
        ))}
    </div>
  );
}
