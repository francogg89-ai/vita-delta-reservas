import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useEnviar } from '../hooks/useEnviar';
import { Campo } from '../ui/Campo';
import { BotonSubmit } from '../ui/BotonSubmit';
import { TarjetaExito } from '../ui/TarjetaExito';
import { Banner } from '../ui/Banner';
import { controlClass, botonPrimario, botonSecundario } from '../ui/estilos';
import { CABANAS_TEST, MOTIVOS_BLOQUEO } from '../lib/constantes';
import { mensajeUsuario } from '../lib/erroresEscritura';
import type { CrearBloqueoData } from '../lib/contratos';

// A08 bloqueo.crear_manual (escritura, sin idempotency_key: guard por solapamiento).
// id_cabana OBLIGATORIO: el bloqueo total no se expone en el portal (decision 8D).
// Validacion cliente = espejo del validador del gateway, NUNCA mas estricta (D-FE-23):
// requeridos + fecha_hasta > fecha_desde. La disponibilidad real la valida el backend.

interface FormBloqueo {
  id_cabana: string;
  fecha_desde: string;
  fecha_hasta: string;
  motivo: string;
  descripcion: string;
}
const INICIAL: FormBloqueo = { id_cabana: '', fecha_desde: '', fecha_hasta: '', motivo: '', descripcion: '' };

type Errores = Partial<Record<keyof FormBloqueo, string>>;

function validar(f: FormBloqueo): Errores {
  const e: Errores = {};
  if (!f.id_cabana) e.id_cabana = 'Elegi una cabana.';
  if (!f.fecha_desde) e.fecha_desde = 'Indica la fecha de inicio.';
  if (!f.fecha_hasta) e.fecha_hasta = 'Indica la fecha de liberacion.';
  if (f.fecha_desde && f.fecha_hasta && !(f.fecha_desde < f.fecha_hasta)) {
    e.fecha_hasta = 'La liberacion debe ser posterior al inicio.';
  }
  if (!f.motivo) e.motivo = 'Elegi un motivo.';
  return e;
}

function Encabezado() {
  return (
    <header>
      <p className="text-xs font-medium uppercase tracking-wide text-reed">bloqueo.crear_manual</p>
      <h2 className="mt-1 text-xl font-semibold text-ink">Crear bloqueo</h2>
    </header>
  );
}

export function CrearBloqueo() {
  const [form, setForm] = useState<FormBloqueo>(INICIAL);
  const [errores, setErrores] = useState<Errores>({});
  const { enviar, enviando, resultado, error, estadoIncierto, reset } =
    useEnviar<CrearBloqueoData>('bloqueo.crear_manual', 'none');

  function set<K extends keyof FormBloqueo>(k: K, v: string) {
    setForm((f) => ({ ...f, [k]: v }));
    if (errores[k]) setErrores((e) => ({ ...e, [k]: undefined }));
  }

  function submit() {
    const e = validar(form);
    setErrores(e);
    if (Object.values(e).some(Boolean)) return;
    const payload: Record<string, unknown> = {
      id_cabana: Number(form.id_cabana),
      fecha_desde: form.fecha_desde,
      fecha_hasta: form.fecha_hasta,
      motivo: form.motivo,
    };
    if (form.descripcion.trim()) payload.descripcion = form.descripcion.trim();
    void enviar(payload);
  }

  function otro() {
    reset();
    setForm(INICIAL);
    setErrores({});
  }

  // Exito -> tarjeta (oculta el form). El form sigue cargado por si elige "Crear otro".
  if (resultado) {
    const cab = CABANAS_TEST.find((c) => c.id === resultado.id_cabana);
    return (
      <div className="mx-auto max-w-2xl space-y-4">
        <Encabezado />
        <TarjetaExito
          titulo={`Bloqueo creado #${resultado.id_bloqueo}`}
          acciones={
            <>
              <Link to="/calendarios/operativo" className={botonPrimario}>Ver calendario operativo</Link>
              <button type="button" onClick={otro} className={botonSecundario}>Crear otro</button>
            </>
          }
        >
          {cab ? cab.nombre : `Cabana #${resultado.id_cabana}`} · {resultado.tipo_bloqueo}
        </TarjetaExito>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <Encabezado />

      {error && !estadoIncierto && (
        <Banner tono={error.code === 'conflicto' ? 'aviso' : 'error'}>
          {error.code === 'conflicto'
            ? 'Se solapa con una reserva, pre-reserva o bloqueo en ese rango.'
            : mensajeUsuario(error)}
        </Banner>
      )}

      {estadoIncierto && (
        <Banner
          tono="incierto"
          titulo="No se pudo confirmar el bloqueo."
          acciones={
            <>
              <Link to="/calendarios/operativo" className={botonPrimario}>Ver calendario operativo</Link>
              <button type="button" onClick={submit} className={botonSecundario}>Reintentar</button>
            </>
          }
        >
          Revisa el calendario operativo para ver si el bloqueo quedo creado. Si ya se creo, reintentar
          puede volver como conflicto: primero verifica el calendario.
        </Banner>
      )}

      <div className="space-y-4 rounded-2xl border border-sand bg-white p-4 sm:p-6">
        <Campo label="Cabana" requerido error={errores.id_cabana}>
          <select value={form.id_cabana} onChange={(e) => set('id_cabana', e.target.value)} className={controlClass}>
            <option value="">Elegi una cabana</option>
            {CABANAS_TEST.map((c) => (
              <option key={c.id} value={String(c.id)}>{c.nombre}</option>
            ))}
          </select>
        </Campo>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Campo label="Desde" requerido error={errores.fecha_desde}>
            <input type="date" value={form.fecha_desde} onChange={(e) => set('fecha_desde', e.target.value)} className={controlClass} />
          </Campo>
          <Campo label="Hasta (liberacion)" requerido error={errores.fecha_hasta} hint="La cabana queda libre desde esta fecha.">
            <input type="date" value={form.fecha_hasta} onChange={(e) => set('fecha_hasta', e.target.value)} className={controlClass} />
          </Campo>
        </div>

        <Campo label="Motivo" requerido error={errores.motivo}>
          <select value={form.motivo} onChange={(e) => set('motivo', e.target.value)} className={controlClass}>
            <option value="">Elegi un motivo</option>
            {MOTIVOS_BLOQUEO.map((m) => (
              <option key={m.valor} value={m.valor}>{m.etiqueta}</option>
            ))}
          </select>
        </Campo>

        <Campo label="Descripcion" hint="Opcional.">
          <textarea value={form.descripcion} onChange={(e) => set('descripcion', e.target.value)} rows={3} className={controlClass} />
        </Campo>

        <div className="flex justify-end">
          <BotonSubmit enviando={enviando} onClick={submit}>Crear bloqueo</BotonSubmit>
        </div>
      </div>
    </div>
  );
}
