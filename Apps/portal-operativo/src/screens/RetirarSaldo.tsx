import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../auth/useAuth';
import { useAction } from '../hooks/useAction';
import { useEnviar } from '../hooks/useEnviar';
import { Campo } from '../ui/Campo';
import { Money } from '../ui/Money';
import { BotonSubmit } from '../ui/BotonSubmit';
import { TarjetaExito } from '../ui/TarjetaExito';
import { Banner } from '../ui/Banner';
import { Cargando } from '../ui/Cargando';
import { ErrorCard } from '../ui/ErrorCard';
import { controlClass, botonPrimario, botonSecundario } from '../ui/estilos';
import { formatARS } from '../lib/formato';
import { mensajeUsuario } from '../lib/erroresEscritura';
import type { PortalApiError } from '../lib/callPortal';
import type { CuentaCorrienteData, RegistrarRetiroData } from '../lib/contratos';

// A29 cuenta_corriente.retirar (ESCRITURA, socio-only, idempotency_key SIBLING).
//
// Contrato (C1 / D-A29-1 / D-CC-20): `monto` viaja como STRING ^[0-9]{1,12}(\.[0-9]{1,2})?$ y > 0.
// Se envia `form.monto.trim()`, NUNCA `Number(monto)` dentro del payload (sin floats en el camino).
// La validacion cliente ESPEJA el gateway, nunca mas estricta (D-FE-23). El backend es la autoridad
// final del saldo; la prevalidacion es solo UX.
//
// Fail-closed de saldo (D1): L1 (cuenta_corriente.al_dia) devuelve TODOS los socios (C3) y el cliente
// no recibe id_socio, asi que la fila propia se identifica por nombre normalizado contra
// `contexto.nombre`. Si no hay match UNICO (o el saldo llega null), NO hay formulario ni submit: no se
// retira a ciegas.
//
// Confirmacion en dos fases (D2): formulario -> resumen -> "Confirmar retiro" (sin librerias).
//
// estado_incierto (D8): la accion PRIMARIA es "Verificar saldo" -> refetch de L1, sin reintento
// automatico bajo ningun caso. La secundaria "Reintentar este mismo retiro" reusa la MISMA
// idempotency_key (enviar(ultimoPayload,{reintento:true})); si ya se registro vuelve idempotente:true
// (no duplica). Queda deshabilitada sin `ultimoPayload` o mientras `enviando`.

const MONTO_RE = /^[0-9]{1,12}(\.[0-9]{1,2})?$/;

const MEDIOS: { valor: string; etiqueta: string }[] = [
  { valor: 'efectivo', etiqueta: 'Efectivo' },
  { valor: 'transferencia_bancaria', etiqueta: 'Transferencia bancaria' },
];
const MEDIOS_OK = new Set(MEDIOS.map((m) => m.valor));

/** Normalizacion para el match de la fila propia (espeja el invariante SB0 lower(btrim(nombre))). */
function norm(s: string): string {
  return s.trim().toLowerCase();
}

function medioLabel(valor: string): string {
  return MEDIOS.find((m) => m.valor === valor)?.etiqueta ?? valor;
}

/** Mensaje del error de escritura del retiro. saldo_insuficiente enriquece con el detail sanitizado. */
function mensajeErrorRetiro(error: PortalApiError): string {
  if (error.code === 'saldo_insuficiente') {
    const d = error.detail as { saldo_disponible?: unknown; monto_solicitado?: unknown } | null;
    const disp = d && typeof d.saldo_disponible === 'number' ? d.saldo_disponible : null;
    const sol = d && typeof d.monto_solicitado === 'number' ? d.monto_solicitado : null;
    if (disp != null && sol != null) {
      return `Saldo insuficiente: tu saldo disponible es ${formatARS(disp)} y pediste retirar ${formatARS(sol)}.`;
    }
    if (disp != null) return `Saldo insuficiente: tu saldo disponible es ${formatARS(disp)}.`;
    return 'Saldo insuficiente para el retiro.';
  }
  if (error.code === 'conflicto') {
    return 'Hubo un conflicto con la operacion. Volve a cargar el retiro.';
  }
  return mensajeUsuario(error);
}

interface FormRetiro {
  monto: string;
  medio_pago: string;
  comentario: string;
}
const INICIAL: FormRetiro = { monto: '', medio_pago: '', comentario: '' };

function Encabezado() {
  return (
    <header>
      <p className="text-xs font-medium uppercase tracking-wide text-reed">cuenta_corriente.retirar</p>
      <h2 className="mt-1 text-xl font-semibold text-ink">Retirar saldo</h2>
    </header>
  );
}

export function RetirarSaldo() {
  const { contexto } = useAuth();
  const {
    data: ccData,
    loading: ccLoading,
    error: ccError,
    refetch: ccRefetch,
  } = useAction<CuentaCorrienteData>('cuenta_corriente.al_dia');
  const { enviar, enviando, resultado, error, estadoIncierto, reset } =
    useEnviar<RegistrarRetiroData>('cuenta_corriente.retirar', 'sibling');

  const [fase, setFase] = useState<'form' | 'confirmar'>('form');
  const [form, setForm] = useState<FormRetiro>(INICIAL);
  const [ultimoPayload, setUltimoPayload] = useState<Record<string, unknown> | null>(null);
  // Verificacion de saldo posterior al estado_incierto (D8): el saldo del banner solo es confiable
  // DESPUES de tocar "Verificar saldo". Antes puede ser el ccData viejo cargado al montar (pre-intento).
  const [saldoVerificadoTrasIncierto, setSaldoVerificadoTrasIncierto] = useState(false);

  // Reconsulta L1 tras un retiro exitoso (D7): el saldo nuevo NO viene en la respuesta.
  const reconsultado = useRef(false);
  useEffect(() => {
    if (resultado && !reconsultado.current) {
      reconsultado.current = true;
      ccRefetch();
    } else if (!resultado && reconsultado.current) {
      reconsultado.current = false;
    }
  }, [resultado, ccRefetch]);

  // AppShell solo monta autenticado; guard defensivo (ademas fija contexto.nombre no-null).
  if (!contexto) return null;

  // Fila propia (D1): match UNICO por nombre normalizado. filas = TODOS los socios (C3).
  const filas = ccData?.filas ?? [];
  const propias = filas.filter((f) => norm(f.socio) === norm(contexto.nombre));
  const filaPropia = propias.length === 1 ? propias[0] : null;
  const saldo = filaPropia?.saldo_al_dia ?? null;

  // Derivados en vivo del monto (validos con saldo identificado > 0, i.e. en fase form/confirmar).
  const montoT = form.monto.trim();
  const montoNum = MONTO_RE.test(montoT) ? Number(montoT) : NaN;
  const montoOk = Number.isFinite(montoNum) && montoNum > 0;
  const sobreRetiro = saldo != null && montoOk && montoNum > saldo;
  const estimadoNuevo = saldo != null && montoOk && !sobreRetiro ? saldo - montoNum : null;
  // Validacion en vivo (medio contra allowlist real, no solo no-vacio).
  const medioOk = MEDIOS_OK.has(form.medio_pago);
  const formValido = montoT !== '' && montoOk && !sobreRetiro && medioOk;
  const montoErr =
    montoT === ''
      ? undefined
      : !montoOk
        ? 'Monto invalido: hasta 12 enteros y 2 decimales, sin signo.'
        : sobreRetiro
          ? `El monto supera tu saldo disponible (${formatARS(saldo ?? 0)}).`
          : undefined;
  const medioErr = montoOk && !sobreRetiro && !medioOk ? 'Elegi el medio de pago.' : undefined;

  function set<K extends keyof FormRetiro>(k: K, v: FormRetiro[K]) {
    setForm((f) => ({ ...f, [k]: v }));
    // Editar tras error/incierto = submit nuevo: soltar la key retenida (proximo submit = key nueva, D-FE-20).
    if (error || estadoIncierto) {
      reset();
      setUltimoPayload(null);
      setSaldoVerificadoTrasIncierto(false);
    }
  }

  function continuar() {
    if (!formValido) return;
    setFase('confirmar');
  }

  function submit() {
    // Guarda dura (espejo del gateway): monto STRING (C1) + medio en allowlist; formValido lo cubre.
    if (saldo == null || !formValido) return;
    const payload: Record<string, unknown> = { monto: form.monto.trim(), medio_pago: form.medio_pago };
    const com = form.comentario.trim();
    if (com) payload.comentario = com;
    setUltimoPayload(payload);
    setSaldoVerificadoTrasIncierto(false);
    void enviar(payload); // idempotency_key SIBLING la agrega useEnviar
  }

  function reintentar() {
    // estado_incierto (D8): reusa la MISMA key. Si ya se aplico, vuelve idempotente:true (no duplica).
    if (!ultimoPayload) return;
    setSaldoVerificadoTrasIncierto(false);
    void enviar(ultimoPayload, { reintento: true });
  }

  function volverAEditar() {
    reset();
    setUltimoPayload(null);
    setSaldoVerificadoTrasIncierto(false);
    setFase('form');
  }

  function otro() {
    reset();
    setUltimoPayload(null);
    setSaldoVerificadoTrasIncierto(false);
    setForm(INICIAL);
    setFase('form');
  }

  // 1) Exito (D7): id_movimiento + monto + medio + idempotente + saldo reconsultado de L1.
  if (resultado) {
    return (
      <div className="mx-auto max-w-2xl space-y-4">
        <Encabezado />
        <TarjetaExito
          titulo={`Retiro registrado #${resultado.id_movimiento}`}
          acciones={
            <>
              <Link to="/socios/cuenta-corriente" className={botonPrimario}>Ir a cuenta corriente</Link>
              <button type="button" onClick={otro} className={botonSecundario}>Retirar de nuevo</button>
            </>
          }
        >
          <div className="space-y-1">
            <p>
              Retiraste <strong>{formatARS(Number(form.monto.trim()))}</strong> por{' '}
              {medioLabel(form.medio_pago)}.
            </p>
            {resultado.idempotente && <p>Este retiro ya estaba registrado: no se duplico.</p>}
            {!reconsultado.current || ccLoading ? (
              <p>Actualizando tu saldo...</p>
            ) : ccError ? (
              <p>No pudimos actualizar el saldo ahora. Revisalo en Cuenta corriente.</p>
            ) : filaPropia && filaPropia.saldo_al_dia != null ? (
              <p>
                Nuevo saldo: <Money monto={filaPropia.saldo_al_dia} className="font-semibold" />
              </p>
            ) : (
              <p>No pudimos confirmar tu saldo actualizado. Revisalo en Cuenta corriente.</p>
            )}
          </div>
        </TarjetaExito>
      </div>
    );
  }

  // 2) Resultado de envio no-exito: estado_incierto (D8) o error normal. Tiene precedencia sobre el form.
  if (error) {
    return (
      <div className="mx-auto max-w-2xl space-y-4">
        <Encabezado />
        {estadoIncierto ? (
          <Banner
            tono="incierto"
            titulo="No pudimos confirmar el retiro."
            acciones={
              <>
                <button
                  type="button"
                  onClick={() => {
                    setSaldoVerificadoTrasIncierto(true);
                    ccRefetch();
                  }}
                  disabled={ccLoading}
                  className={botonPrimario}
                >
                  Verificar saldo
                </button>
                <button
                  type="button"
                  onClick={reintentar}
                  disabled={!ultimoPayload || enviando}
                  className={botonSecundario}
                >
                  Reintentar este mismo retiro
                </button>
                <button
                  type="button"
                  onClick={volverAEditar}
                  disabled={enviando}
                  className={botonSecundario}
                >
                  Volver a editar
                </button>
              </>
            }
          >
            <p>
              No sabemos si el retiro llego a registrarse. Verifica tu saldo: si bajo por el monto que
              pediste, ya se hizo.{' '}
              {!saldoVerificadoTrasIncierto ? (
                'Todavia no verificamos el saldo despues del intento.'
              ) : ccLoading ? (
                'Verificando saldo...'
              ) : ccError ? (
                'No pudimos verificar el saldo ahora.'
              ) : saldo != null ? (
                <>
                  Saldo verificado: <Money monto={saldo} />.
                </>
              ) : (
                'No pudimos confirmar tu saldo.'
              )}
            </p>
            <p className="mt-1">
              "Reintentar este mismo retiro" usa la misma clave de operacion: no crea un retiro nuevo
              si ya se registro.
            </p>
          </Banner>
        ) : (
          <Banner
            tono={error.code === 'conflicto' ? 'aviso' : 'error'}
            acciones={
              <button
                type="button"
                onClick={volverAEditar}
                disabled={enviando}
                className={botonSecundario}
              >
                Volver a editar
              </button>
            }
          >
            {mensajeErrorRetiro(error)}
          </Banner>
        )}
      </div>
    );
  }

  // 3) Compuerta de saldo (fail-closed, D1/D3) + fase form/confirmar.
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <Encabezado />

      {ccLoading ? (
        <Cargando mensaje="Cargando tu saldo..." />
      ) : ccError ? (
        <ErrorCard error={ccError} onRetry={ccRefetch} />
      ) : filaPropia == null || saldo == null ? (
        // D1: sin match UNICO (o saldo null) -> fail-closed, sin formulario.
        <Banner
          tono="error"
          titulo="No pudimos verificar tu saldo disponible."
          acciones={
            <button type="button" onClick={() => ccRefetch()} className={botonSecundario}>
              Reintentar
            </button>
          }
        >
          No pudimos verificar tu saldo disponible. Reintenta o avisa al administrador.
        </Banner>
      ) : saldo <= 0 ? (
        // D3: sin fondos -> bloqueo.
        <Banner
          tono="aviso"
          titulo="No tenes saldo disponible para retirar."
          acciones={
            <>
              <Link to="/socios/cuenta-corriente" className={botonSecundario}>Ver cuenta corriente</Link>
              <button type="button" onClick={() => ccRefetch()} className={botonSecundario}>
                Actualizar saldo
              </button>
            </>
          }
        >
          Tu saldo disponible es {formatARS(saldo)}. No hay monto para retirar.
        </Banner>
      ) : fase === 'form' ? (
        // Fase 1: formulario.
        <div className="space-y-5 rounded-2xl border border-sand bg-white p-4 sm:p-6">
          <div className="rounded-lg border border-sand bg-mist px-4 py-3 text-sm">
            <span className="text-reed">Tu saldo disponible: </span>
            <Money monto={saldo} className="font-semibold" />
          </div>

          <Campo label="Monto a retirar" requerido error={montoErr} hint="En pesos (ARS). Hasta 2 decimales.">
            <input
              type="text"
              inputMode="decimal"
              value={form.monto}
              onChange={(e) => set('monto', e.target.value)}
              placeholder="0.00"
              className={controlClass}
            />
          </Campo>

          <Campo label="Medio de pago" requerido error={medioErr}>
            <select value={form.medio_pago} onChange={(e) => set('medio_pago', e.target.value)} className={controlClass}>
              <option value="">Elegi un medio</option>
              {MEDIOS.map((m) => (
                <option key={m.valor} value={m.valor}>{m.etiqueta}</option>
              ))}
            </select>
          </Campo>

          <Campo label="Comentario" hint="Opcional.">
            <textarea value={form.comentario} onChange={(e) => set('comentario', e.target.value)} rows={2} className={controlClass} />
          </Campo>

          <div className="flex justify-end">
            <button
              type="button"
              onClick={continuar}
              disabled={!formValido}
              className={botonPrimario + ' w-full sm:w-auto'}
            >
              Continuar
            </button>
          </div>
        </div>
      ) : (
        // Fase 2: resumen / confirmacion.
        <div className="space-y-5 rounded-2xl border border-sand bg-white p-4 sm:p-6">
          <h3 className="border-b border-sand pb-1 text-sm font-semibold text-ink">Confirma el retiro</h3>

          <dl className="space-y-2 text-sm">
            <div className="flex justify-between">
              <dt className="text-reed">Monto a retirar</dt>
              <dd><Money monto={montoNum} className="font-semibold" /></dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-reed">Medio de pago</dt>
              <dd className="text-ink">{medioLabel(form.medio_pago)}</dd>
            </div>
            {form.comentario.trim() && (
              <div className="flex justify-between gap-4">
                <dt className="text-reed">Comentario</dt>
                <dd className="text-right text-ink">{form.comentario.trim()}</dd>
              </div>
            )}
            <div className="flex justify-between border-t border-sand pt-2">
              <dt className="text-reed">Saldo actual</dt>
              <dd><Money monto={saldo} /></dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-reed">Saldo estimado luego del retiro</dt>
              <dd>{estimadoNuevo != null ? <Money monto={estimadoNuevo} /> : '—'}</dd>
            </div>
          </dl>
          <p className="text-xs text-reed">El saldo definitivo se confirma al registrar el retiro.</p>

          <div className="flex flex-wrap justify-end gap-2">
            <button type="button" onClick={() => setFase('form')} disabled={enviando} className={botonSecundario}>
              Volver
            </button>
            <BotonSubmit enviando={enviando} onClick={submit}>Confirmar retiro</BotonSubmit>
          </div>
        </div>
      )}
    </div>
  );
}
