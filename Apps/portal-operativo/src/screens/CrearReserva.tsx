import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useEnviar } from '../hooks/useEnviar';
import { useBorradorPersistente } from '../hooks/useBorradorPersistente';
import { Campo } from '../ui/Campo';
import { BotonSubmit } from '../ui/BotonSubmit';
import { TarjetaExito } from '../ui/TarjetaExito';
import { Banner } from '../ui/Banner';
import { controlClass, botonPrimario, botonSecundario } from '../ui/estilos';
import { CABANAS_TEST, MEDIOS_PAGO_RESERVA } from '../lib/constantes';
import { mensajeUsuario } from '../lib/erroresEscritura';
import { CalendarioRango } from '../ui/CalendarioRango';
import { hoyAR } from '../lib/fecha';
import type { CrearReservaData } from '../lib/contratos';
import type { PortalApiError } from '../lib/callPortal';
import { supabase } from '../lib/supabase';

// A07 reserva.crear_manual (escritura, sin idempotency_key: el wrapper deriva idempotencia de
// cabana+fechas+contacto -> la respuesta trae idempotent_match). Validacion cliente = espejo del
// validador del gateway, NUNCA mas estricta (D-FE-23): requeridos, fecha_out>fecha_in, personas>=1
// (SIN tope de capacidad: lo valida el backend), 0<=sena<=total, contacto telefono O email.
// canal_pago_esperado y medio_pago se llenan con UN selector (decision aprobada).

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

interface FormReserva {
  id_cabana: string;
  fecha_in: string;
  fecha_out: string;
  personas: string;
  monto_total: string;
  monto_sena: string;
  medio_pago: string;
  huesped_nombre: string;
  huesped_telefono: string;
  huesped_email: string;
  mascotas: boolean;
  detalle_mascotas: string;
  ninos: string;
  notas: string;
  notas_reserva: string;
  hora_checkin: string;
  hora_checkout: string;
}
const INICIAL: FormReserva = {
  id_cabana: '', fecha_in: '', fecha_out: '', personas: '', monto_total: '', monto_sena: '0',
  medio_pago: 'transferencia_bancaria', huesped_nombre: '', huesped_telefono: '', huesped_email: '', mascotas: false,
  detalle_mascotas: '', ninos: '', notas: '', notas_reserva: '', hora_checkin: '', hora_checkout: '',
};

type CampoError = keyof FormReserva | 'contacto';
type Errores = Partial<Record<CampoError, string>>;

function validar(f: FormReserva, emailUsuario: string | null): Errores {
  const e: Errores = {};
  if (!f.id_cabana) e.id_cabana = 'Elegi una cabana.';
  if (!f.fecha_in) e.fecha_in = 'Indica el check-in.';
  if (!f.fecha_out) e.fecha_out = 'Indica el check-out.';
  if (f.fecha_in && f.fecha_out && !(f.fecha_in < f.fecha_out)) {
    e.fecha_out = 'El check-out debe ser posterior al check-in.';
  }
  // Espejo del guard backend (fecha_in_pasada): el check-in no puede ser anterior a hoy (zona AR).
  // El calendario ya lo impide; esto es el espejo de validacion (D-FE-23), nunca mas estricto.
  if (f.fecha_in && f.fecha_in < hoyAR()) {
    e.fecha_in = 'El check-in no puede ser anterior a hoy.';
  }

  if (f.personas.trim() === '') {
    e.personas = 'Indica cuantas personas.';
  } else {
    const n = Number(f.personas);
    if (!Number.isInteger(n) || n < 1) e.personas = 'Debe ser un entero de 1 o mas.';
  }

  const total = Number(f.monto_total);
  if (f.monto_total.trim() === '') {
    e.monto_total = 'Indica el monto total.';
  } else if (!Number.isFinite(total) || total <= 0) {
    e.monto_total = 'Monto invalido (mayor a 0).';
  }

  // Sena: vacio o 0 => AUTOMATICO (se enviara el 50% del total). >0 => valor exacto, debe ser <= total.
  const senaTrim = f.monto_sena.trim();
  if (senaTrim !== '') {
    const sena = Number(senaTrim);
    if (!Number.isFinite(sena) || sena < 0) {
      e.monto_sena = 'Sena invalida.';
    } else if (sena > 0 && Number.isFinite(total) && total > 0 && sena > total) {
      e.monto_sena = 'La sena no puede superar el total.';
    }
  }

  if (!f.medio_pago) e.medio_pago = 'Elegi el medio de pago.';
  if (f.huesped_nombre.trim() === '') e.huesped_nombre = 'Indica el nombre del huesped.';

  const telDigits = f.huesped_telefono.replace(/\D/g, '');
  const telOk = telDigits.length >= 6;
  const emailTrim = f.huesped_email.trim();
  const emailPresente = emailTrim !== '';
  const emailOk = EMAIL_RE.test(emailTrim);
  // Espejo del gateway: si hay email NO vacio, debe ser valido, aunque el telefono sea valido
  // (el gateway rechaza huesped.email no vacio mal formado de forma independiente).
  if (emailPresente && !emailOk) e.huesped_email = 'El email cargado no es valido.';
  // Anti-autofill: el navegador puede rellenar el email del huesped con el del operador
  // logueado. Si coinciden, se rechaza: ese email es del operador, no del huesped (evita
  // que upsert_huesped dedupee distintas reservas al mismo huesped por el email).
  if (emailPresente && emailOk && emailUsuario && emailTrim.toLowerCase() === emailUsuario) {
    e.huesped_email = 'Ese es tu email de operador, no el del huesped. Dejalo vacio si no tenes el del huesped.';
  }
  // Requisito de contacto: al menos un telefono valido O un email valido.
  if (!telOk && !(emailPresente && emailOk)) {
    e.contacto = 'Indica un telefono valido o un email valido.';
  }

  return e;
}

function Encabezado() {
  return (
    <header>
      <p className="text-xs font-medium uppercase tracking-wide text-reed">reserva.crear_manual</p>
      <h2 className="mt-1 text-xl font-semibold text-ink">Crear reserva</h2>
    </header>
  );
}

// Mensaje de error de escritura para el banner. Espeja el `error.code` del backend con texto UX:
// payload_invalido por fecha pasada (token `fecha_in_pasada`) -> mensaje claro; el resto cae al
// mensaje curado del backend (mensajeUsuario). conflicto conserva su caso especial.
function textoErrorReserva(error: PortalApiError): string {
  if (error.code === 'conflicto') {
    return 'Sin disponibilidad en ese rango (se solapa con una reserva, pre-reserva o bloqueo).';
  }
  if (error.code === 'payload_invalido' && error.message.includes('fecha_in_pasada')) {
    return 'No podes crear una reserva con check-in anterior a hoy.';
  }
  return mensajeUsuario(error);
}

function Seccion({ titulo }: { titulo: string }) {
  return <h3 className="border-b border-sand pb-1 text-sm font-semibold text-ink">{titulo}</h3>;
}

export function CrearReserva() {
  const { valor: form, setValor: setForm, limpiar: limpiarBorrador } =
    useBorradorPersistente<FormReserva>('a07-crear-reserva:v1', INICIAL);
  const [errores, setErrores] = useState<Errores>({});
  const [emailUsuario, setEmailUsuario] = useState<string | null>(null);
  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setEmailUsuario(data.session?.user?.email?.toLowerCase() ?? null);
    });
  }, []);
  const { enviar, enviando, resultado, error, estadoIncierto, reset } =
    useEnviar<CrearReservaData>('reserva.crear_manual', 'none');

  // Al confirmarse la reserva, el borrador deja de tener sentido: se limpia. `limpiarBorrador`
  // tiene referencia estable (useCallback en el hook), asi el efecto solo corre al cambiar `resultado`.
  useEffect(() => {
    if (resultado) limpiarBorrador();
  }, [resultado, limpiarBorrador]);

  function set<K extends keyof FormReserva>(k: K, v: FormReserva[K]) {
    setForm((f) => ({ ...f, [k]: v }));
    // limpia el error del campo y el de contacto (este depende de telefono+email) al editar
    setErrores((e) => ({ ...e, [k]: undefined, contacto: undefined }));
  }

  function submit() {
    const e = validar(form, emailUsuario);
    setErrores(e);
    if (Object.values(e).some(Boolean)) return;

    // Sena automatica: 0 o vacio => 50% del total; >0 => valor exacto. NUNCA se manda 0
    // (0 es la convencion de "auto"; una sena real $0 seria otra decision explicita).
    const total = Number(form.monto_total);
    const senaInput = form.monto_sena.trim() === '' ? 0 : Number(form.monto_sena);
    const montoSena = senaInput > 0 ? senaInput : Math.round((total / 2) * 100) / 100;

    const huesped: { nombre: string; telefono?: string; email?: string } = { nombre: form.huesped_nombre.trim() };
    const tel = form.huesped_telefono.trim();
    const email = form.huesped_email.trim();
    if (tel) huesped.telefono = tel;
    if (email) huesped.email = email;

    const payload: Record<string, unknown> = {
      id_cabana: Number(form.id_cabana),
      fecha_in: form.fecha_in,
      fecha_out: form.fecha_out,
      personas: Number(form.personas),
      monto_total: total,
      monto_sena: montoSena,
      canal_pago_esperado: form.medio_pago,
      medio_pago: form.medio_pago,
      mascotas: form.mascotas,
      huesped,
    };
    if (form.mascotas && form.detalle_mascotas.trim()) payload.detalle_mascotas = form.detalle_mascotas.trim();
    if (form.ninos.trim()) payload.ninos = form.ninos.trim();
    if (form.notas.trim()) payload.notas = form.notas.trim();
    if (form.notas_reserva.trim()) payload.notas_reserva = form.notas_reserva.trim();
    if (form.hora_checkin) payload.hora_checkin_solicitada = form.hora_checkin;
    if (form.hora_checkout) payload.hora_checkout_solicitada = form.hora_checkout;

    void enviar(payload);
  }

  function otra() {
    limpiarBorrador();
    reset();
    setForm(INICIAL);
    setErrores({});
  }

  if (resultado) {
    return (
      <div className="mx-auto max-w-3xl space-y-4">
        <Encabezado />
        <TarjetaExito
          titulo={`Reserva creada #${resultado.id_reserva}`}
          acciones={
            <>
              <Link to="/calendarios/operativo" className={botonPrimario}>Ver calendario operativo</Link>
              <button type="button" onClick={otra} className={botonSecundario}>Crear otra</button>
            </>
          }
        >
          {resultado.idempotent_match
            ? 'Esta reserva ya existia: no se duplico.'
            : `Pre-reserva #${resultado.id_pre_reserva} confirmada.`}
        </TarjetaExito>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <Encabezado />

      {error && !estadoIncierto && (
        <Banner tono={error.code === 'conflicto' ? 'aviso' : 'error'}>
          {textoErrorReserva(error)}
        </Banner>
      )}

      {estadoIncierto && (
        <Banner
          tono="incierto"
          titulo="No se pudo confirmar la reserva."
          acciones={
            <>
              <Link to="/reservas/historico" className={botonPrimario}>Ver historico</Link>
              <button type="button" onClick={submit} className={botonSecundario}>Reintentar</button>
            </>
          }
        >
          Revisa el historico o el calendario operativo para ver si la reserva quedo creada.
          Reintentar es seguro: si ya existe, el sistema no la duplica.
        </Banner>
      )}

      <div className="space-y-5 rounded-2xl border border-sand bg-white p-4 sm:p-6">
        <Seccion titulo="Estadia" />
        <Campo label="Cabana" requerido error={errores.id_cabana}>
          <select value={form.id_cabana} onChange={(e) => set('id_cabana', e.target.value)} className={controlClass}>
            <option value="">Elegi una cabana</option>
            {CABANAS_TEST.map((c) => (
              <option key={c.id} value={String(c.id)}>{c.nombre}</option>
            ))}
          </select>
        </Campo>
        <CalendarioRango
          idCabana={form.id_cabana ? Number(form.id_cabana) : null}
          modo="reserva"
          desde={form.fecha_in}
          hasta={form.fecha_out}
          onChange={(d, h) => {
            setForm((f) => ({ ...f, fecha_in: d, fecha_out: h }));
            setErrores((e) => ({ ...e, fecha_in: undefined, fecha_out: undefined }));
          }}
          labelDesde="Check-in"
          labelHasta="Check-out"
          errorDesde={errores.fecha_in}
          errorHasta={errores.fecha_out}
        />
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Campo label="Personas" requerido error={errores.personas}>
            <input type="number" inputMode="numeric" min={1} value={form.personas} onChange={(e) => set('personas', e.target.value)} className={controlClass} />
          </Campo>
        </div>

        <Seccion titulo="Pago" />
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Campo label="Monto total" requerido error={errores.monto_total}>
            <input type="number" inputMode="decimal" min={0} step="0.01" value={form.monto_total} onChange={(e) => set('monto_total', e.target.value)} className={controlClass} />
          </Campo>
          <Campo label="Sena" requerido error={errores.monto_sena} hint="0 = calcular 50% automaticamente.">
            <input type="number" inputMode="decimal" min={0} step="0.01" value={form.monto_sena} onChange={(e) => set('monto_sena', e.target.value)} className={controlClass} />
          </Campo>
        </div>
        <Campo label="Medio de pago" requerido error={errores.medio_pago} hint="Se usa como canal esperado y medio de la sena.">
          <select value={form.medio_pago} onChange={(e) => set('medio_pago', e.target.value)} className={controlClass}>
            {MEDIOS_PAGO_RESERVA.map((m) => (
              <option key={m.valor} value={m.valor}>{m.etiqueta}</option>
            ))}
          </select>
        </Campo>

        <Seccion titulo="Huesped" />
        <Campo label="Nombre" requerido error={errores.huesped_nombre}>
          <input type="text" value={form.huesped_nombre} onChange={(e) => set('huesped_nombre', e.target.value)} className={controlClass} />
        </Campo>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Campo label="Telefono" error={errores.contacto}>
            <input type="tel" value={form.huesped_telefono} onChange={(e) => set('huesped_telefono', e.target.value)} placeholder="Ej. 1155..." className={controlClass} />
          </Campo>
          <Campo label="Email" error={errores.huesped_email} hint="Telefono o email: al menos uno.">
            <input type="email" autoComplete="off" value={form.huesped_email} onChange={(e) => set('huesped_email', e.target.value)} className={controlClass} />
          </Campo>
        </div>

        <Seccion titulo="Detalles (opcional)" />
        <label className="flex items-center gap-2">
          <input type="checkbox" checked={form.mascotas} onChange={(e) => set('mascotas', e.target.checked)} className="h-4 w-4 rounded border-sand text-river focus:ring-river" />
          <span className="text-sm text-ink">Viene con mascotas</span>
        </label>
        {form.mascotas && (
          <Campo label="Detalle de mascotas">
            <input type="text" value={form.detalle_mascotas} onChange={(e) => set('detalle_mascotas', e.target.value)} className={controlClass} />
          </Campo>
        )}
        <Campo label="Ninos" hint="Detalle libre (ej. edades).">
          <input type="text" value={form.ninos} onChange={(e) => set('ninos', e.target.value)} className={controlClass} />
        </Campo>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Campo label="Hora check-in solicitada">
            <input type="time" value={form.hora_checkin} onChange={(e) => set('hora_checkin', e.target.value)} className={controlClass} />
          </Campo>
          <Campo label="Hora check-out solicitada">
            <input type="time" value={form.hora_checkout} onChange={(e) => set('hora_checkout', e.target.value)} className={controlClass} />
          </Campo>
        </div>
        <Campo label="Notas">
          <textarea value={form.notas} onChange={(e) => set('notas', e.target.value)} rows={2} className={controlClass} />
        </Campo>
        <Campo label="Notas de la reserva">
          <textarea value={form.notas_reserva} onChange={(e) => set('notas_reserva', e.target.value)} rows={2} className={controlClass} />
        </Campo>

        <div className="flex justify-end">
          <BotonSubmit enviando={enviando} onClick={submit}>Crear reserva</BotonSubmit>
        </div>
      </div>
    </div>
  );
}
