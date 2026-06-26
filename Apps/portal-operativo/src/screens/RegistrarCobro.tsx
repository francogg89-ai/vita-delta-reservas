import { useState } from 'react';
import type { ReactNode } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { useAction } from '../hooks/useAction';
import { useEnviar } from '../hooks/useEnviar';
import { Campo } from '../ui/Campo';
import { BotonSubmit } from '../ui/BotonSubmit';
import { TarjetaExito } from '../ui/TarjetaExito';
import { Banner } from '../ui/Banner';
import { Money } from '../ui/Money';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { Vacio } from '../ui/Vacio';
import { EstadoBadge } from '../ui/EstadoBadge';
import { controlClass, botonPrimario, botonSecundario } from '../ui/estilos';
import { SUBTIPOS_TRANSFERENCIA } from '../lib/constantes';
import { formatARS } from '../lib/formato';
import { mensajeUsuario } from '../lib/erroresEscritura';
import type { ReservaDetalleData, RegistrarCobroData, SubtipoTransferencia } from '../lib/contratos';

// A10-MP cobranza.registrar_cobro (escritura, idempotency_key PAYLOAD: viaja DENTRO del payload,
// D-FE-02). Cobranza multi-porcion (efectivo + transferencia bancaria/mp + otros) con recargo 5%
// sobre la porcion de transferencia. Validacion cliente = espejo del gateway payloadRegistrarCobro,
// NUNCA mas estricta (D-FE-23). El encabezado/saldo sale de reserva.detalle (A05), byte-alineado al
// saldo que usa el anti-sobrepago HARD del backend; el bloqueo de sobrepago de la UI (D-FE-21) usa
// ese snapshot y el backend igual rebota conflicto/excede_saldo si quedo viejo.
// Contabilidad (D-C-68): suma_saldo (efectivo+transferencia+otros) BAJA el saldo; el recargo es
// `extra` y NO baja saldo (no se resta del saldo estimado). El portal NUNCA llama W10
// (cobranza.registrar_saldo) ni manda campos de control (actor/rol/nonce/source_event/...).

const MONTO_MAX = 9999999999.99;
const ESTADOS_COBRABLES = ['confirmada', 'activa'];

/** id de reserva tipeado: entero positivo seguro (espeja el gateway). */
function parseId(s: string): number | null {
  const t = s.trim();
  if (!/^\d+$/.test(t)) return null;
  const n = Number(t);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
}

/** Monto de porcion: vacio -> 0; si no, number finito >=0, <=2 decimales, <= NUMERIC(12,2). null si invalido. */
function parseMonto(s: string): number | null {
  const t = s.trim();
  if (t === '') return 0;
  if (!/^\d+(\.\d{1,2})?$/.test(t)) return null;
  const n = Number(t);
  if (!Number.isFinite(n) || n < 0 || n > MONTO_MAX) return null;
  return n;
}

interface FormCobro {
  efectivo: string;
  transferencia: string;
  subtipo: SubtipoTransferencia;
  otros: string;
  origen_otros: string;
  descripcion_otros: string;
  notas: string;
}
const INICIAL: FormCobro = {
  efectivo: '', transferencia: '', subtipo: 'bancaria', otros: '',
  origen_otros: '', descripcion_otros: '', notas: '',
};

type Errores = Partial<Record<keyof FormCobro | 'general', string>>;

/**
 * Validacion en submit (espejo del gateway, nunca mas estricta). El sobrepago se bloquea aparte
 * (boton disabled + aviso en vivo, D-FE-21), por eso no se chequea aca.
 */
function validar(f: FormCobro): Errores {
  const e: Errores = {};
  if (parseMonto(f.efectivo) == null) e.efectivo = 'Monto invalido (maximo 2 decimales).';
  if (parseMonto(f.transferencia) == null) e.transferencia = 'Monto invalido (maximo 2 decimales).';
  if (parseMonto(f.otros) == null) e.otros = 'Monto invalido (maximo 2 decimales).';

  const ef = parseMonto(f.efectivo) ?? 0;
  const tr = parseMonto(f.transferencia) ?? 0;
  const ot = parseMonto(f.otros) ?? 0;
  if (!(ef > 0 || tr > 0 || ot > 0)) e.general = 'Carga al menos una porcion mayor a 0.';

  if (ot > 0) {
    const og = f.origen_otros.trim();
    const de = f.descripcion_otros.trim();
    if (og.length < 1 || og.length > 120) e.origen_otros = 'Obligatorio (1 a 120 caracteres) cuando hay monto en "otros".';
    if (de.length < 1 || de.length > 200) e.descripcion_otros = 'Obligatorio (1 a 200 caracteres) cuando hay monto en "otros".';
  }
  if (f.notas.length > 1000) e.notas = 'Maximo 1000 caracteres.';
  return e;
}

function Encabezado() {
  return (
    <header>
      <p className="text-xs font-medium uppercase tracking-wide text-reed">cobranza.registrar_cobro</p>
      <h2 className="mt-1 text-xl font-semibold text-ink">Registrar cobro</h2>
    </header>
  );
}

function Linea({ etiqueta, children, fuerte }: { etiqueta: string; children: ReactNode; fuerte?: boolean }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className={'text-sm ' + (fuerte ? 'font-medium text-ink' : 'text-reed')}>{etiqueta}</span>
      <span className={fuerte ? 'font-semibold' : ''}>{children}</span>
    </div>
  );
}

export function RegistrarCobro() {
  const [params] = useSearchParams();
  const idParam = parseId(params.get('id_reserva') ?? '');
  const [draft, setDraft] = useState(idParam != null ? String(idParam) : '');
  const [idBuscado, setIdBuscado] = useState<number | null>(idParam);
  const [form, setForm] = useState<FormCobro>(INICIAL);
  const [errores, setErrores] = useState<Errores>({});
  const [ultimoPayload, setUltimoPayload] = useState<Record<string, unknown> | null>(null);

  const idValido = parseId(draft);

  const detalle = useAction<ReservaDetalleData>(
    'reserva.detalle',
    { id_reserva: idBuscado ?? 0 },
    { enabled: idBuscado != null },
  );
  const { enviar, enviando, resultado, error, estadoIncierto, reset } =
    useEnviar<RegistrarCobroData>('cobranza.registrar_cobro', 'payload');

  const r = detalle.data?.reserva ?? null;
  const saldoReal = r?.saldo_real ?? null;
  const cobrable = r != null && ESTADOS_COBRABLES.includes(r.estado) && saldoReal != null && saldoReal > 0;

  // Derivados en vivo (resumen + bloqueo sobrepago). El recargo es informativo: el backend recalcula.
  const ef = parseMonto(form.efectivo) ?? 0;
  const tr = parseMonto(form.transferencia) ?? 0;
  const ot = parseMonto(form.otros) ?? 0;
  const sumaSaldo = ef + tr + ot;
  const recargo = tr > 0 ? Math.round(tr * 0.05) : 0;
  const totalCobrado = sumaSaldo + recargo;
  const saldoEstimado = saldoReal != null ? saldoReal - sumaSaldo : null;
  const sobrepago = saldoReal != null && sumaSaldo > saldoReal;

  function buscar() {
    if (idValido != null) {
      reset();
      setUltimoPayload(null);
      setForm(INICIAL);
      setErrores({});
      setIdBuscado(idValido);
    }
  }

  function set<K extends keyof FormCobro>(k: K, v: FormCobro[K]) {
    setForm((f) => ({ ...f, [k]: v }));
    setErrores((e) => {
      const n: Errores = { ...e, [k]: undefined, general: undefined };
      if (k === 'otros') { n.origen_otros = undefined; n.descripcion_otros = undefined; }
      return n;
    });
    // Editar tras un error/incierto = submit nuevo: soltar la key retenida (proximo submit = key nueva, D-FE-20).
    if (error || estadoIncierto) { reset(); setUltimoPayload(null); }
  }

  function construirPayload(f: FormCobro, id: number): Record<string, unknown> {
    const payload: Record<string, unknown> = {
      id_reserva: id,
      monto_efectivo: parseMonto(f.efectivo) ?? 0,
      monto_transferencia: parseMonto(f.transferencia) ?? 0,
      monto_otros: parseMonto(f.otros) ?? 0,
      subtipo_transferencia: f.subtipo,
    };
    // origen/descripcion SOLO si otros > 0 (D-C-65). idempotency_key lo agrega useEnviar ('payload').
    if ((parseMonto(f.otros) ?? 0) > 0) {
      payload.origen_otros = f.origen_otros.trim();
      payload.descripcion_otros = f.descripcion_otros.trim();
    }
    if (f.notas.trim()) payload.notas = f.notas.trim();
    return payload;
  }

  function submit() {
    if (idBuscado == null || !cobrable || saldoReal == null) return;
    if (sumaSaldo > saldoReal) return; // bloqueo duro de sobrepago (redundante con disabled, D-FE-21)
    const e = validar(form);
    setErrores(e);
    if (Object.values(e).some(Boolean)) return;
    const payload = construirPayload(form, idBuscado);
    setUltimoPayload(payload);
    void enviar(payload);
  }

  function reintentar() {
    // estado_incierto: reusa la MISMA key (D-FE-20). Si ya se aplico, vuelve idempotent_match:true.
    if (ultimoPayload) void enviar(ultimoPayload, { reintento: true });
  }

  function cobrarOtra() {
    reset();
    setUltimoPayload(null);
    setForm(INICIAL);
    setErrores({});
    setIdBuscado(null);
    setDraft('');
  }

  function seguirCobrando() {
    reset();
    setUltimoPayload(null);
    setForm(INICIAL);
    setErrores({});
    detalle.refetch(); // refresca el saldo tras un cobro parcial
  }

  // ---------- Exito ----------
  if (resultado) {
    const d = resultado.detalle;
    return (
      <div className="mx-auto max-w-2xl space-y-4">
        <Encabezado />
        {r && (
          <div className="rounded-2xl border border-sand bg-white p-4 text-sm">
            <span className="font-medium text-ink">{r.cabana} · #{idBuscado}</span>
            {r.huesped.nombre ? <span className="text-reed"> · {r.huesped.nombre}</span> : null}
          </div>
        )}
        <TarjetaExito
          titulo={resultado.saldada ? 'Cobro registrado · saldo saldado' : 'Cobro registrado'}
          acciones={
            <>
              {!resultado.saldada && (
                <button type="button" onClick={seguirCobrando} className={botonPrimario}>
                  Seguir cobrando esta reserva
                </button>
              )}
              <Link to="/cobranzas/saldos" className={resultado.saldada ? botonPrimario : botonSecundario}>
                Ver saldos
              </Link>
              <button type="button" onClick={cobrarOtra} className={botonSecundario}>
                Cobrar otra reserva
              </button>
            </>
          }
        >
          <div className="space-y-1">
            <Linea etiqueta="Aplicado a saldo">{formatARS(resultado.suma_saldo)}</Linea>
            <Linea etiqueta="Recargo 5% (extra)">{formatARS(resultado.suma_extra)}</Linea>
            <Linea etiqueta="Total cobrado" fuerte>{formatARS(resultado.total_cobrado)}</Linea>
            <Linea etiqueta="Saldo anterior">{formatARS(resultado.saldo_anterior)}</Linea>
            <Linea etiqueta="Saldo actual" fuerte>{formatARS(resultado.saldo_real_actual)}</Linea>
            <Linea etiqueta="Lineas registradas">{resultado.cant_lineas}</Linea>
            <div className="pt-1 text-xs text-green-900">
              Detalle: efectivo {formatARS(d.efectivo)}, transferencia {formatARS(d.transferencia)}
              {d.transferencia > 0 && d.subtipo_transferencia ? ` (${d.subtipo_transferencia})` : ''}, otros{' '}
              {formatARS(d.otros)}, recargo {formatARS(d.recargo)}.
            </div>
            {resultado.idempotent_match && (
              <p className="pt-1 text-xs">Este cobro ya estaba registrado: no se duplico.</p>
            )}
          </div>
        </TarjetaExito>
      </div>
    );
  }

  // ---------- Formulario ----------
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <Encabezado />

      {/* Paso 1: elegir la reserva (deep-link ?id_reserva= o tipeo manual). */}
      <div className="flex items-end gap-2 rounded-2xl border border-sand bg-white p-4">
        <label className="flex-1">
          <span className="block text-sm text-reed">ID de reserva</span>
          <input
            type="text"
            inputMode="numeric"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') buscar(); }}
            placeholder="Ej. 13"
            disabled={enviando}
            className={controlClass}
          />
        </label>
        <button type="button" onClick={buscar} disabled={idValido == null || enviando} className={botonPrimario}>
          Buscar
        </button>
      </div>

      {/* Estado de carga de la reserva. */}
      {idBuscado != null && detalle.loading && !detalle.data && <Cargando mensaje="Cargando reserva..." />}
      {idBuscado != null && detalle.error && (
        detalle.error.code === 'no_encontrado'
          ? <Vacio mensaje={`No existe una reserva con ID ${idBuscado}.`} />
          : <ErrorCard error={detalle.error} onRetry={detalle.refetch} />
      )}

      {/* Reserva cargada. */}
      {r && (
        <>
          <div className="rounded-2xl border border-sand bg-white p-4">
            <div className="flex items-center justify-between gap-3">
              <h3 className="text-base font-semibold text-ink">{r.cabana} · #{r.id_reserva}</h3>
              <EstadoBadge estado={r.estado} />
            </div>
            <dl className="mt-3 grid grid-cols-2 gap-3 text-sm">
              <div>
                <dt className="text-xs text-reed">Huesped</dt>
                <dd className="text-ink">{r.huesped.nombre ?? '—'}</dd>
              </div>
              <div>
                <dt className="text-xs text-reed">Saldo pendiente</dt>
                <dd>{saldoReal != null ? <Money monto={saldoReal} /> : '—'}</dd>
              </div>
            </dl>
          </div>

          {!cobrable ? (
            <Banner tono="aviso">
              {!ESTADOS_COBRABLES.includes(r.estado)
                ? `Esta reserva no admite cobranza de saldo (estado: ${r.estado}).`
                : saldoReal == null
                  ? 'No se pudo determinar el saldo de esta reserva.'
                  : 'Esta reserva no tiene saldo pendiente.'}
            </Banner>
          ) : (
            <>
              {error && !estadoIncierto && (
                <Banner
                  tono={error.code === 'conflicto' ? 'aviso' : 'error'}
                  titulo={error.code === 'conflicto' ? 'No se pudo registrar el cobro.' : undefined}
                  acciones={
                    error.code === 'conflicto' || error.code === 'no_encontrado'
                      ? <button type="button" onClick={() => detalle.refetch()} disabled={enviando} className={botonSecundario}>Verificar reserva</button>
                      : undefined
                  }
                >
                  {mensajeUsuario(error)}
                </Banner>
              )}

              {estadoIncierto && (
                <Banner
                  tono="incierto"
                  titulo="No se pudo confirmar el cobro."
                  acciones={
                    <>
                      <button type="button" onClick={() => detalle.refetch()} disabled={enviando} className={botonPrimario}>Verificar reserva</button>
                      <button type="button" onClick={reintentar} disabled={enviando || !ultimoPayload} className={botonSecundario}>Reintentar este cobro</button>
                    </>
                  }
                >
                  El cobro pudo haberse aplicado o no. Verifica la reserva antes de reintentar. Si reintentas,
                  se reusa la misma operacion: si ya se aplico, vuelve como idempotente y no duplica.
                </Banner>
              )}

              <div className="space-y-5 rounded-2xl border border-sand bg-white p-4 sm:p-6">
                <h3 className="border-b border-sand pb-1 text-sm font-semibold text-ink">Porciones</h3>

                <Campo label="Efectivo" error={errores.efectivo} hint="En pesos (ARS).">
                  <input type="number" inputMode="decimal" min={0} step="0.01" value={form.efectivo}
                    onChange={(e) => set('efectivo', e.target.value)} disabled={enviando} className={controlClass} />
                </Campo>

                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <Campo label="Transferencia" error={errores.transferencia} hint="En pesos (ARS). Genera recargo 5%.">
                    <input type="number" inputMode="decimal" min={0} step="0.01" value={form.transferencia}
                      onChange={(e) => set('transferencia', e.target.value)} disabled={enviando} className={controlClass} />
                  </Campo>
                  <Campo label="Subtipo de transferencia">
                    <select value={form.subtipo} onChange={(e) => set('subtipo', e.target.value as SubtipoTransferencia)}
                      disabled={enviando} className={controlClass}>
                      {SUBTIPOS_TRANSFERENCIA.map((s) => (
                        <option key={s.valor} value={s.valor}>{s.etiqueta}</option>
                      ))}
                    </select>
                  </Campo>
                </div>

                <Campo label="Otros (efectivo-equivalente ARS)" error={errores.otros}
                  hint="Otro medio registrado como efectivo, con traza.">
                  <input type="number" inputMode="decimal" min={0} step="0.01" value={form.otros}
                    onChange={(e) => set('otros', e.target.value)} disabled={enviando} className={controlClass} />
                </Campo>

                {ot > 0 && (
                  <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                    <Campo label="Origen de otros" requerido error={errores.origen_otros}
                      hint="Medio original (ej. cripto, tarjeta).">
                      <input type="text" maxLength={120} value={form.origen_otros}
                        onChange={(e) => set('origen_otros', e.target.value)} disabled={enviando} className={controlClass} />
                    </Campo>
                    <Campo label="Descripcion de otros" requerido error={errores.descripcion_otros}>
                      <input type="text" maxLength={200} value={form.descripcion_otros}
                        onChange={(e) => set('descripcion_otros', e.target.value)} disabled={enviando} className={controlClass} />
                    </Campo>
                  </div>
                )}

                <Campo label="Notas del operador" error={errores.notas} hint="Opcional, hasta 1000 caracteres.">
                  <textarea value={form.notas} onChange={(e) => set('notas', e.target.value)} rows={2}
                    disabled={enviando} className={controlClass} />
                </Campo>

                {/* Resumen en vivo. suma_saldo BAJA el saldo; el recargo (extra) NO se resta (D-C-68). */}
                <div className="space-y-1 rounded-xl bg-mist p-4">
                  <Linea etiqueta="Aplicado a saldo (efectivo + transferencia + otros)"><Money monto={sumaSaldo} /></Linea>
                  <Linea etiqueta="Recargo 5% (sobre transferencia)"><Money monto={recargo} /></Linea>
                  <Linea etiqueta="Total a cobrar" fuerte><Money monto={totalCobrado} /></Linea>
                  <Linea etiqueta="Saldo estimado despues">
                    {saldoEstimado != null ? <Money monto={saldoEstimado} /> : '—'}
                  </Linea>
                </div>

                {sobrepago && (
                  <p className="text-sm text-red-600">
                    La suma aplicada a saldo (<Money monto={sumaSaldo} />) supera el saldo pendiente
                    {' '}(<Money monto={saldoReal ?? 0} />). Ajusta los montos.
                  </p>
                )}
                {errores.general && <p className="text-sm text-red-600">{errores.general}</p>}

                <div className="flex justify-end">
                  <BotonSubmit enviando={enviando} disabled={sobrepago} onClick={submit}>Registrar cobro</BotonSubmit>
                </div>
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}
