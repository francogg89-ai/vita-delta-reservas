import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useEnviar } from '../hooks/useEnviar';
import { Campo } from '../ui/Campo';
import { BotonSubmit } from '../ui/BotonSubmit';
import { TarjetaExito } from '../ui/TarjetaExito';
import { Banner } from '../ui/Banner';
import { controlClass, botonPrimario, botonSecundario } from '../ui/estilos';
import { CABANAS_TEST, ZONAS_TEST, SOCIOS_TEST, CLASES_GASTO, PAGADORES_GASTO } from '../lib/constantes';
import { mensajeUsuario } from '../lib/erroresEscritura';
import type { CargarGastoData } from '../lib/contratos';

// A11 cargar.gasto_interno (escritura, idempotency_key SIBLING: viaja top-level, no en payload).
// Validacion cliente = espejo de las 14 constraints de gastos_internos, NUNCA mas estricta
// (D-FE-23). El gateway anula detail.constraint (P-FE-07): los mensajes finos salen de aca; el
// fallback ante una coherencia que el cliente no cubre es el message generico del backend.
// No se exponen: periodo (la funcion lo deriva = dia 1 del mes de fecha), moneda (ARS fijo),
// clase_sugerida (omitida -> comentario SIEMPRE obligatorio).

const HORAS_TRABAJO = 'horas de trabajo';

/** Fecha de hoy en YMD local (para el default del campo fecha). */
function hoyYMD(): string {
  const d = new Date();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${mm}-${dd}`;
}

interface FormGasto {
  fecha: string;
  clase: string;
  id_zona: string;
  id_cabana: string;
  etiqueta: string;
  monto: string;
  pagador_tipo: string;
  id_socio_pagador: string;
  medio_pago: string;
  comentario: string;
  comprobante_url: string;
}
const INICIAL: FormGasto = {
  fecha: hoyYMD(), clase: '', id_zona: '', id_cabana: '', etiqueta: '', monto: '',
  pagador_tipo: 'caja', id_socio_pagador: '', medio_pago: '', comentario: '', comprobante_url: '',
};

type Errores = Partial<Record<keyof FormGasto, string>>;

function validar(f: FormGasto): Errores {
  const e: Errores = {};
  if (!f.fecha) e.fecha = 'Indica la fecha del gasto.';
  if (!f.clase) e.clase = 'Elegi la clase.';
  if (f.clase === 'D' && !f.id_zona) e.id_zona = 'Elegi la zona.';
  if (f.clase === 'E' && !f.id_cabana) e.id_cabana = 'Elegi la cabana.';
  if (f.etiqueta.trim() === '') e.etiqueta = 'Indica una etiqueta.';

  if (f.monto.trim() === '') {
    e.monto = 'Indica el monto.';
  } else {
    const m = Number(f.monto);
    if (!Number.isFinite(m) || m <= 0) e.monto = 'El monto debe ser mayor a 0.';
  }

  if (!f.pagador_tipo) e.pagador_tipo = 'Elegi quien pago.';
  if (f.pagador_tipo === 'socio' && !f.id_socio_pagador) e.id_socio_pagador = 'Elegi el socio que pago.';
  if (f.comentario.trim() === '') e.comentario = 'El comentario es obligatorio.';

  // chk_gastos_internos_horas_pagador_socio: 'horas de trabajo' exige pagador socio.
  if (f.etiqueta.trim().toLowerCase() === HORAS_TRABAJO && f.pagador_tipo !== 'socio') {
    e.pagador_tipo = "Si la etiqueta es 'horas de trabajo', el pagador debe ser un socio.";
  }

  return e;
}

function Encabezado() {
  return (
    <header>
      <p className="text-xs font-medium uppercase tracking-wide text-reed">cargar.gasto_interno</p>
      <h2 className="mt-1 text-xl font-semibold text-ink">Cargar gasto</h2>
    </header>
  );
}

function Seccion({ titulo }: { titulo: string }) {
  return <h3 className="border-b border-sand pb-1 text-sm font-semibold text-ink">{titulo}</h3>;
}

export function CargarGasto() {
  const [form, setForm] = useState<FormGasto>(INICIAL);
  const [errores, setErrores] = useState<Errores>({});
  const { enviar, enviando, resultado, error, estadoIncierto, reset } =
    useEnviar<CargarGastoData>('cargar.gasto_interno', 'sibling');

  function set<K extends keyof FormGasto>(k: K, v: FormGasto[K]) {
    setForm((f) => ({ ...f, [k]: v }));
    setErrores((e) => {
      const n: Errores = { ...e, [k]: undefined };
      if (k === 'etiqueta') n.pagador_tipo = undefined; // 'horas de trabajo' afecta al pagador
      if (k === 'clase') { n.id_zona = undefined; n.id_cabana = undefined; }
      if (k === 'pagador_tipo') n.id_socio_pagador = undefined;
      return n;
    });
  }

  function submit() {
    const e = validar(form);
    setErrores(e);
    if (Object.values(e).some(Boolean)) return;

    // El payload incluye id_zona SOLO en D, id_cabana SOLO en E, id_socio_pagador SOLO en socio:
    // aunque el estado tenga un valor viejo al cambiar de clase/pagador, no se manda (coherencia).
    const payload: Record<string, unknown> = {
      fecha: form.fecha,
      clase: form.clase,
      etiqueta: form.etiqueta.trim(),
      monto: Number(form.monto),
      pagador_tipo: form.pagador_tipo,
      comentario: form.comentario.trim(),
    };
    if (form.clase === 'D') payload.id_zona = Number(form.id_zona);
    if (form.clase === 'E') payload.id_cabana = Number(form.id_cabana);
    if (form.pagador_tipo === 'socio') payload.id_socio_pagador = Number(form.id_socio_pagador);
    if (form.medio_pago.trim()) payload.medio_pago = form.medio_pago.trim();
    if (form.comprobante_url.trim()) payload.comprobante_url = form.comprobante_url.trim();

    void enviar(payload);
  }

  function otro() {
    reset();
    setForm(INICIAL);
    setErrores({});
  }

  if (resultado) {
    return (
      <div className="mx-auto max-w-2xl space-y-4">
        <Encabezado />
        <TarjetaExito
          titulo={`Gasto cargado #${resultado.id_gasto}`}
          acciones={
            <>
              <Link to="/economico/gastos" className={botonPrimario}>Ver gastos</Link>
              <button type="button" onClick={otro} className={botonSecundario}>Cargar otro</button>
            </>
          }
        >
          {resultado.idempotente ? 'Este gasto ya estaba cargado: no se duplico.' : null}
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
            ? 'Hubo un conflicto de idempotencia. Carga el gasto de nuevo.'
            : mensajeUsuario(error)}
        </Banner>
      )}

      {estadoIncierto && (
        <Banner
          tono="incierto"
          titulo="No se pudo confirmar el gasto."
          acciones={
            <>
              <Link to="/economico/gastos" className={botonPrimario}>Ver gastos</Link>
              <button type="button" onClick={submit} className={botonSecundario}>Reintentar</button>
            </>
          }
        >
          Revisa el listado de gastos para ver si quedo cargado. Reintentar reusa la misma clave:
          si ya se cargo, vuelve como idempotente (no duplica).
        </Banner>
      )}

      <div className="space-y-5 rounded-2xl border border-sand bg-white p-4 sm:p-6">
        <Seccion titulo="Gasto" />
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Campo label="Fecha" requerido error={errores.fecha}>
            <input type="date" value={form.fecha} onChange={(e) => set('fecha', e.target.value)} className={controlClass} />
          </Campo>
          <Campo label="Clase" requerido error={errores.clase} hint="Impacta contabilidad y distribucion.">
            <select value={form.clase} onChange={(e) => set('clase', e.target.value)} className={controlClass}>
              <option value="">Elegi una clase</option>
              {CLASES_GASTO.map((c) => (
                <option key={c.valor} value={c.valor}>{c.etiqueta}</option>
              ))}
            </select>
          </Campo>
        </div>

        {form.clase === 'D' && (
          <Campo label="Zona" requerido error={errores.id_zona}>
            <select value={form.id_zona} onChange={(e) => set('id_zona', e.target.value)} className={controlClass}>
              <option value="">Elegi una zona</option>
              {ZONAS_TEST.map((z) => (
                <option key={z.id} value={String(z.id)}>{z.nombre}</option>
              ))}
            </select>
          </Campo>
        )}

        {form.clase === 'E' && (
          <Campo label="Cabana" requerido error={errores.id_cabana}>
            <select value={form.id_cabana} onChange={(e) => set('id_cabana', e.target.value)} className={controlClass}>
              <option value="">Elegi una cabana</option>
              {CABANAS_TEST.map((c) => (
                <option key={c.id} value={String(c.id)}>{c.nombre}</option>
              ))}
            </select>
          </Campo>
        )}

        <Campo label="Etiqueta" requerido error={errores.etiqueta} hint="Descriptiva (ej. nafta, mantenimiento). 'horas de trabajo' exige pagador socio.">
          <input type="text" value={form.etiqueta} onChange={(e) => set('etiqueta', e.target.value)} className={controlClass} />
        </Campo>
        <Campo label="Monto" requerido error={errores.monto} hint="En pesos (ARS).">
          <input type="number" inputMode="decimal" min={0} step="0.01" value={form.monto} onChange={(e) => set('monto', e.target.value)} className={controlClass} />
        </Campo>

        <Seccion titulo="Pago" />
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Campo label="Pagador" requerido error={errores.pagador_tipo}>
            <select value={form.pagador_tipo} onChange={(e) => set('pagador_tipo', e.target.value)} className={controlClass}>
              {PAGADORES_GASTO.map((p) => (
                <option key={p.valor} value={p.valor}>{p.etiqueta}</option>
              ))}
            </select>
          </Campo>
          {form.pagador_tipo === 'socio' && (
            <Campo label="Socio" requerido error={errores.id_socio_pagador}>
              <select value={form.id_socio_pagador} onChange={(e) => set('id_socio_pagador', e.target.value)} className={controlClass}>
                <option value="">Elegi un socio</option>
                {SOCIOS_TEST.map((s) => (
                  <option key={s.id} value={String(s.id)}>{s.nombre}</option>
                ))}
              </select>
            </Campo>
          )}
        </div>
        <Campo label="Medio de pago" hint="Opcional.">
          <input type="text" value={form.medio_pago} onChange={(e) => set('medio_pago', e.target.value)} className={controlClass} />
        </Campo>

        <Seccion titulo="Detalle" />
        <Campo label="Comentario" requerido error={errores.comentario}>
          <textarea value={form.comentario} onChange={(e) => set('comentario', e.target.value)} rows={2} className={controlClass} />
        </Campo>
        <Campo label="Comprobante (URL)" hint="Opcional. Link a un comprobante externo (sin subir archivos).">
          <input type="url" value={form.comprobante_url} onChange={(e) => set('comprobante_url', e.target.value)} placeholder="https://..." className={controlClass} />
        </Campo>

        <div className="flex justify-end">
          <BotonSubmit enviando={enviando} onClick={submit}>Cargar gasto</BotonSubmit>
        </div>
      </div>
    </div>
  );
}
