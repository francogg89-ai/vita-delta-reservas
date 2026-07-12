#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SB-UI-2 FIX -- Correccion de la maquina de estado del selector / A30.

Alcance CERRADO. Toca exactamente 3 archivos:
  1. src/screens/historico/planSelector.ts        -- Estrategia A (preservar anclas)
  2. src/screens/historico/HistoricoVista.tsx     -- prop fotoPendiente + compuerta del boton
  3. src/screens/HistoricoCuentaCorriente.tsx     -- maquina de estado (reemplazo integro)

NO toca: contratos.ts, actionRegistry.ts, rutas.tsx, periodo.ts, estadoFoto.ts, Tarjeta.tsx.

Reglas de la casa: str_replace anclado, assert count==1, identidad inversa donde el edit es
aditivo, all-or-nothing, LF puro.
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, 'src')

EDITS = []


def edit(path, anchor, replacement, label, aditivo=True):
    EDITS.append({
        'path': path, 'anchor': anchor, 'replacement': replacement,
        'label': label, 'aditivo': aditivo,
    })


# =============================================================================================
# planSelector.ts -- EDIT 1: OpcionMes con estado tri-valuado (no mentir "sin foto" en degradado)
# =============================================================================================
A_PS_1 = """/** Una opcion del selector de mes. `conFoto` se DERIVA de A31.evolucion, nunca se hardcodea. */
export interface OpcionMes {
  ym: string;
  etiqueta: string;
  conFoto: boolean;
}
"""

R_PS_1 = """/**
 * Que sabe el selector sobre la foto de un mes.
 *   'con_foto'      -- A31 lo confirma en `evolucion`.
 *   'sin_foto'      -- A31 resolvio y NO esta en `evolucion`.
 *   'no_verificada' -- A31 no esta disponible (degradado): no se puede afirmar NADA.
 *
 * `no_verificada` NO se renderiza como "sin foto": etiquetar asi un mes que quiza la tenga seria
 * afirmar algo falso. Se muestra sin sufijo.
 */
export type EstadoFotoMes = 'con_foto' | 'sin_foto' | 'no_verificada';

/** Una opcion del selector de mes. `foto` se DERIVA de A31.evolucion, nunca se hardcodea. */
export interface OpcionMes {
  ym: string;
  etiqueta: string;
  foto: EstadoFotoMes;
}
"""

edit('screens/historico/planSelector.ts', A_PS_1, R_PS_1,
     'OpcionMes: conFoto:boolean -> foto:EstadoFotoMes', aditivo=False)


# =============================================================================================
# planSelector.ts -- EDIT 2: firma + cuerpo (Estrategia A: preservar anclas)
# =============================================================================================
A_PS_2 = """/**
 * Construye el plan del selector de mes (D-FE-49). Modulo PURO: sin hooks, sin red.
 *
 * PISO SEGURO
 *   pisoConsulta = max(FLOOR_CONTABLE, A31.piso)   (o FLOOR_CONTABLE si A31 no esta disponible)
 *   El frontend no puede leer FLOOR_CC_GW (el validador del gateway, que es quien efectivamente
 *   REBOTA con payload_invalido). Solo dispone del espejo local y del piso runtime. Tomar el `max`
 *   es el piso mas conservador computable: si existiera drift hacia un piso runtime MENOR, usar
 *   A31.piso ofreceria meses que el gateway rechazaria.
 *
 * TECHO
 *   techo = max(pisoMes, mesActual, mayorPeriodoSeleccionable)
 *   `pisoMes` entra al max para que el rango [pisoMes .. techo] NUNCA sea vacio, incluso con drift
 *   extremo del piso por delante del mes actual.
 *
 * PRE-PISO (D-FE-54)
 *   Los periodos con foto anteriores al piso NO se ofrecen en el selector, pero SIGUEN incluidos en
 *   evolucion, en los totales acumulados y en los componentes congelados de los saldos por socio.
 *   La UI no filtra ni recalcula el DATO: solo acota lo que ofrece consultar.
 *
 * DEFAULT
 *   Foto mas reciente que este >= piso y <= mes actual. Si no existe, mes actual clampeado al piso.
 *   Las fotos FUTURAS aparecen como opcion (se pueden abrir a mano) pero NUNCA autoabren.
 *
 * @param acum  respuesta de A31, o null si esta cargando / fallo (fallback local).
 */
export function construirPlanSelector(acum: HistoricoAcumuladosData | null): PlanSelector {
  const pisoLocalMes = ymDeFecha(FLOOR_CONTABLE);
  const pisoRuntimeMes = acum !== null ? ymDeFecha(acum.piso) : null;

  const pisoMes = pisoRuntimeMes !== null ? maxYM(pisoLocalMes, pisoRuntimeMes) : pisoLocalMes;
  const pisoDivergente = pisoRuntimeMes !== null && pisoRuntimeMes !== pisoLocalMes;

  const mesActual = mesActualYM();

  // Periodos con foto vigente, excluidos los pre-piso (no se OFRECEN; siguen contando en el dato).
  const conFoto = (acum?.evolucion ?? [])
    .map((e) => ymDeFecha(e.periodo))
    .filter((ym) => ym >= pisoMes);
  const setConFoto = new Set(conFoto);

  const mayorConFoto = conFoto.length > 0 ? conFoto.reduce(maxYM) : pisoMes;
  const techo = maxYM(maxYM(pisoMes, mesActual), mayorConFoto);

  const opciones: OpcionMes[] = rangoMesesYM(pisoMes, techo)
    .map((ym) => ({ ym, etiqueta: etiquetaMes(ym), conFoto: setConFoto.has(ym) }))
    .reverse(); // mas reciente primero

  const candidatos = conFoto.filter((ym) => ym <= mesActual);
  const porDefecto = candidatos.length > 0 ? candidatos.reduce(maxYM) : maxYM(mesActual, pisoMes);

  return { pisoMes, opciones, porDefecto, pisoDivergente, degradado: acum === null };
}
"""

R_PS_2 = """/**
 * Construye el plan del selector de mes (D-FE-49). Modulo PURO: sin hooks, sin red.
 *
 * PISO SEGURO
 *   pisoConsulta = max(FLOOR_CONTABLE, A31.piso)   (o FLOOR_CONTABLE si A31 no esta disponible)
 *   El frontend no puede leer FLOOR_CC_GW (el validador del gateway, que es quien efectivamente
 *   REBOTA con payload_invalido). Solo dispone del espejo local y del piso runtime. Tomar el `max`
 *   es el piso mas conservador computable: si existiera drift hacia un piso runtime MENOR, usar
 *   A31.piso ofreceria meses que el gateway rechazaria.
 *
 * TECHO
 *   techo = max(pisoMes, mesActual, mayorPeriodoSeleccionable)
 *   `pisoMes` entra al max para que el rango [pisoMes .. techo] NUNCA sea vacio, incluso con drift
 *   extremo del piso por delante del mes actual.
 *
 * ANCLAS -- ESTRATEGIA A (preservar)
 *   Los meses ANCLADOS (el draft y el aplicado) que sigan >= piso SIEMPRE entran en las opciones,
 *   aunque queden por encima del techo. Garantiza la invariante
 *
 *       mesDraft === null || opciones.some((o) => o.ym === mesDraft)     (idem mesApplied)
 *
 *   Sin esto, si A31 cae y el plan degradado achica el techo, un `<select value="2026-11">` se
 *   queda sin su `<option>`: el browser salta EN SILENCIO a la primera opcion y el `value` de React
 *   deja de coincidir con lo que el usuario ve. Reset visual invisible.
 *
 *   Se eligio A (preservar) sobre B (invalidar) porque A30 y A31 tienen estados y retries
 *   INDEPENDIENTES por diseño (D-FE-46): que A31 falle en un retry no puede tirar abajo una consulta
 *   de A30 sana y ya renderizada. Y el mes anclado sigue siendo consultable -- esta por encima del
 *   piso seguro y el gateway lo aceptaria. Lo unico que se pierde con A31 caido es SABER si tiene
 *   foto, que es informativo, no un permiso: por eso se marca 'no_verificada' y no 'sin_foto'.
 *
 *   Los anclas por DEBAJO del piso NO se preservan: el piso es fail-closed y el gateway rechazaria
 *   esos meses. Esos los invalida el contenedor, con aviso explicito.
 *
 * PRE-PISO (D-FE-54)
 *   Los periodos con foto anteriores al piso NO se ofrecen en el selector, pero SIGUEN incluidos en
 *   evolucion, en los totales acumulados y en los componentes congelados de los saldos por socio.
 *   La UI no filtra ni recalcula el DATO: solo acota lo que ofrece consultar.
 *
 * DEFAULT
 *   Foto mas reciente que este >= piso y <= mes actual. Si no existe, mes actual clampeado al piso.
 *   Las fotos FUTURAS aparecen como opcion (se pueden abrir a mano) pero NUNCA autoabren.
 *
 * @param acum    respuesta de A31, o null si esta cargando / fallo (fallback local -> degradado).
 * @param anclas  meses que DEBEN tener opcion si siguen >= piso (draft y aplicado). Nulls ignorados.
 */
export function construirPlanSelector(
  acum: HistoricoAcumuladosData | null,
  anclas: readonly (string | null)[] = [],
): PlanSelector {
  const pisoLocalMes = ymDeFecha(FLOOR_CONTABLE);
  const pisoRuntimeMes = acum !== null ? ymDeFecha(acum.piso) : null;

  const pisoMes = pisoRuntimeMes !== null ? maxYM(pisoLocalMes, pisoRuntimeMes) : pisoLocalMes;
  const pisoDivergente = pisoRuntimeMes !== null && pisoRuntimeMes !== pisoLocalMes;
  const degradado = acum === null;

  const mesActual = mesActualYM();

  // Periodos con foto vigente, excluidos los pre-piso (no se OFRECEN; siguen contando en el dato).
  const conFoto = (acum?.evolucion ?? [])
    .map((e) => ymDeFecha(e.periodo))
    .filter((ym) => ym >= pisoMes);
  const setConFoto = new Set(conFoto);

  const mayorConFoto = conFoto.length > 0 ? conFoto.reduce(maxYM) : pisoMes;
  const techo = maxYM(maxYM(pisoMes, mesActual), mayorConFoto);

  const meses = new Set(rangoMesesYM(pisoMes, techo));
  for (const ancla of anclas) {
    if (ancla !== null && ancla >= pisoMes) meses.add(ancla);
  }

  const opciones: OpcionMes[] = [...meses]
    .sort() // 'YYYY-MM': orden lexico === cronologico
    .reverse() // mas reciente primero
    .map((ym) => ({
      ym,
      etiqueta: etiquetaMes(ym),
      foto: degradado ? 'no_verificada' : setConFoto.has(ym) ? 'con_foto' : 'sin_foto',
    }));

  const candidatos = conFoto.filter((ym) => ym <= mesActual);
  const porDefecto = candidatos.length > 0 ? candidatos.reduce(maxYM) : maxYM(mesActual, pisoMes);

  return { pisoMes, opciones, porDefecto, pisoDivergente, degradado };
}
"""

edit('screens/historico/planSelector.ts', A_PS_2, R_PS_2,
     'construirPlanSelector: anclas (Estrategia A) + foto tri-valuada', aditivo=False)


# =============================================================================================
# HistoricoVista.tsx -- EDIT 3: prop fotoPendiente
# =============================================================================================
A_HV_1 = """export interface HistoricoVistaProps {
  /** Fail-closed (D-FE-46): falta A30 y/o A31 en `sesion.contexto.acciones`. */
  faltaAccion: boolean;
  acum: EstadoLectura<HistoricoAcumuladosData>;
  foto: EstadoLectura<HistoricoMesData>;
  plan: PlanSelector;
"""

R_HV_1 = """export interface HistoricoVistaProps {
  /** Fail-closed (D-FE-46): falta A30 y/o A31 en `sesion.contexto.acciones`. */
  faltaAccion: boolean;
  acum: EstadoLectura<HistoricoAcumuladosData>;
  foto: EstadoLectura<HistoricoMesData>;
  /**
   * Hay una peticion A30 en curso, incluido el tramo en que `useAction` todavia no arranco su
   * ciclo (`loading:false` con el `data` del mes ANTERIOR en mano). Lo calcula el contenedor
   * conciliando el token de peticion contra la lectura servida. Gobierna dos cosas:
   *   1. la seccion Foto NUNCA clasifica un `data` que no corresponda al mes pedido (anti-flash);
   *   2. el boton Consultar queda deshabilitado (anti-doble-request).
   */
  fotoPendiente: boolean;
  plan: PlanSelector;
"""

edit('screens/historico/HistoricoVista.tsx', A_HV_1, R_HV_1,
     'props: + fotoPendiente', aditivo=False)


# =============================================================================================
# HistoricoVista.tsx -- EDIT 4: SelectorMes (compuerta del boton + sufijo tri-valuado)
# =============================================================================================
A_HV_2 = """function SelectorMes({
  plan,
  mesDraft,
  cargandoAcum,
  reiniciadoPorPiso,
  onMesDraftChange,
  onConsultar,
}: {
  plan: PlanSelector;
  mesDraft: string | null;
  cargandoAcum: boolean;
  reiniciadoPorPiso: boolean;
  onMesDraftChange: (ym: string) => void;
  onConsultar: () => void;
}) {
  const listo = !cargandoAcum && mesDraft !== null;
"""

R_HV_2 = """function SelectorMes({
  plan,
  mesDraft,
  cargandoAcum,
  fotoPendiente,
  reiniciadoPorPiso,
  onMesDraftChange,
  onConsultar,
}: {
  plan: PlanSelector;
  mesDraft: string | null;
  cargandoAcum: boolean;
  fotoPendiente: boolean;
  reiniciadoPorPiso: boolean;
  onMesDraftChange: (ym: string) => void;
  onConsultar: () => void;
}) {
  const listo = !cargandoAcum && mesDraft !== null;
  // Defensa 1 de 2 contra el doble request (la 2 es el early-return de `onConsultar`). El select
  // queda habilitado a proposito: cambiar el draft no dispara nada.
  const puedeConsultar = listo && !fotoPendiente;
"""

edit('screens/historico/HistoricoVista.tsx', A_HV_2, R_HV_2,
     'SelectorMes: + fotoPendiente, + puedeConsultar', aditivo=False)


# =============================================================================================
# HistoricoVista.tsx -- EDIT 5: <option> sin sufijo mentiroso + boton bloqueado
# =============================================================================================
A_HV_3 = """            {plan.opciones.map((o) => (
              <option key={o.ym} value={o.ym}>
                {o.conFoto ? o.etiqueta : `${o.etiqueta} · sin foto`}
              </option>
            ))}
          </select>
        </div>

        <button type="button" className={botonPrimario} disabled={!listo} onClick={onConsultar}>
          Consultar
        </button>
"""

R_HV_3 = """            {plan.opciones.map((o) => (
              <option key={o.ym} value={o.ym}>
                {/* 'no_verificada' va SIN sufijo: con A31 caido no se puede afirmar que no hay foto. */}
                {o.foto === 'sin_foto' ? `${o.etiqueta} · sin foto` : o.etiqueta}
              </option>
            ))}
          </select>
        </div>

        <button
          type="button"
          className={botonPrimario}
          disabled={!puedeConsultar}
          onClick={onConsultar}
        >
          {fotoPendiente ? 'Consultando...' : 'Consultar'}
        </button>
"""

edit('screens/historico/HistoricoVista.tsx', A_HV_3, R_HV_3,
     'SelectorMes: option sin sufijo falso + boton bloqueado en vuelo', aditivo=False)


# =============================================================================================
# HistoricoVista.tsx -- EDIT 6: SeccionFotoMes -- pendiente ANTES de error/data (anti-flash)
# =============================================================================================
A_HV_4 = """function SeccionFotoMes({
  foto,
  mesApplied,
}: {
  foto: EstadoLectura<HistoricoMesData>;
  mesApplied: string | null;
}) {
  // Inactivo: sin mes aplicado el hook va con enabled:false -> CERO request.
  if (mesApplied === null) {
    return (
      <Tarjeta titulo="Foto del mes">
        <p className="text-sm text-reed">Elegí un mes y tocá Consultar.</p>
      </Tarjeta>
    );
  }

  if (foto.loading) return <Cargando mensaje="Cargando la foto del mes..." />;
  if (foto.error) return <ErrorCard error={foto.error} onRetry={foto.refetch} />;
  if (!foto.data) return null;
"""

R_HV_4 = """function SeccionFotoMes({
  foto,
  fotoPendiente,
  mesApplied,
}: {
  foto: EstadoLectura<HistoricoMesData>;
  fotoPendiente: boolean;
  mesApplied: string | null;
}) {
  // Inactivo: sin mes aplicado el hook va con enabled:false -> CERO request.
  if (mesApplied === null) {
    return (
      <Tarjeta titulo="Foto del mes">
        <p className="text-sm text-reed">Elegí un mes y tocá Consultar.</p>
      </Tarjeta>
    );
  }

  // PENDIENTE va PRIMERO, antes que error y que data. Cubre `foto.loading` y, ademas, el tramo en
  // que useAction todavia no arranco su ciclo: ahi reporta loading:false con el `data` (y el
  // `error`) del mes ANTERIOR. Clasificar ese data contra el mes nuevo daria T1 -> INCONSISTENTE:
  // un flash rojo en cada cambio de mes. Tampoco se muestra el error viejo por la misma razon.
  // Esto NO enmascara T1: una vez servida la peticion, un `periodo` incorrecto en la respuesta
  // NUEVA sigue cayendo en INCONSISTENTE.
  if (fotoPendiente) return <Cargando mensaje="Cargando la foto del mes..." />;
  if (foto.error) return <ErrorCard error={foto.error} onRetry={foto.refetch} />;
  if (!foto.data) return null;
"""

edit('screens/historico/HistoricoVista.tsx', A_HV_4, R_HV_4,
     'SeccionFotoMes: pendiente antes de error/data (anti-flash)', aditivo=False)


# =============================================================================================
# HistoricoVista.tsx -- EDIT 7: cablear la prop en el componente raiz
# =============================================================================================
A_HV_5 = """export function HistoricoVista({
  faltaAccion,
  acum,
  foto,
  plan,
  mesDraft,
  mesApplied,
  reiniciadoPorPiso,
  onMesDraftChange,
  onConsultar,
}: HistoricoVistaProps) {
"""

R_HV_5 = """export function HistoricoVista({
  faltaAccion,
  acum,
  foto,
  fotoPendiente,
  plan,
  mesDraft,
  mesApplied,
  reiniciadoPorPiso,
  onMesDraftChange,
  onConsultar,
}: HistoricoVistaProps) {
"""

edit('screens/historico/HistoricoVista.tsx', A_HV_5, R_HV_5,
     'HistoricoVista: destructurar fotoPendiente', aditivo=False)


A_HV_6 = """      <SeccionAcumulados acum={acum} />
      <SelectorMes
        plan={plan}
        mesDraft={mesDraft}
        cargandoAcum={acum.loading}
        reiniciadoPorPiso={reiniciadoPorPiso}
        onMesDraftChange={onMesDraftChange}
        onConsultar={onConsultar}
      />
      <SeccionFotoMes foto={foto} mesApplied={mesApplied} />
"""

R_HV_6 = """      <SeccionAcumulados acum={acum} />
      <SelectorMes
        plan={plan}
        mesDraft={mesDraft}
        cargandoAcum={acum.loading}
        fotoPendiente={fotoPendiente}
        reiniciadoPorPiso={reiniciadoPorPiso}
        onMesDraftChange={onMesDraftChange}
        onConsultar={onConsultar}
      />
      <SeccionFotoMes foto={foto} fotoPendiente={fotoPendiente} mesApplied={mesApplied} />
"""

edit('screens/historico/HistoricoVista.tsx', A_HV_6, R_HV_6,
     'HistoricoVista: cablear fotoPendiente a las dos secciones', aditivo=False)


# =============================================================================================
# Ejecucion: all-or-nothing
# =============================================================================================
def main():
    planned = {}

    for e in EDITS:
        full = os.path.join(BASE, e['path'])
        if full not in planned:
            with io.open(full, 'r', encoding='utf-8', newline='') as fh:
                planned[full] = fh.read()

        src = planned[full]

        n = src.count(e['anchor'])
        assert n == 1, "ANCLA NO UNICA (%d) en %s :: %s" % (n, e['path'], e['label'])

        if e['aditivo']:
            assert e['anchor'] in e['replacement'], \
                "IDENTIDAD INVERSA ROTA en %s :: %s" % (e['path'], e['label'])

        planned[full] = src.replace(e['anchor'], e['replacement'], 1)

    for full, content in planned.items():
        assert '\r' not in content, "CRLF DETECTADO en %s" % full

    # Swap del contenedor (reemplazo integro: la maquina de estado se rehace).
    cont = os.path.join(BASE, 'screens', 'HistoricoCuentaCorriente.tsx')
    nuevo = cont + '.new'
    assert os.path.exists(nuevo), "FALTA %s" % nuevo
    with io.open(nuevo, 'r', encoding='utf-8', newline='') as fh:
        cont_txt = fh.read()
    assert '\r' not in cont_txt, "CRLF en el contenedor nuevo"
    assert 'PeticionFoto' in cont_txt and 'fotoPendiente' in cont_txt, "contenedor nuevo incompleto"

    for full, content in planned.items():
        with io.open(full, 'w', encoding='utf-8', newline='') as fh:
            fh.write(content)
    with io.open(cont, 'w', encoding='utf-8', newline='') as fh:
        fh.write(cont_txt)
    os.remove(nuevo)

    print("OK: %d edits sobre %d archivos + swap del contenedor" % (len(EDITS), len(planned)))
    for e in EDITS:
        print("  [OK] %-38s %s" % (e['path'], e['label']))
    print("  [OK] %-38s %s" % ('screens/HistoricoCuentaCorriente.tsx', 'maquina de estado (integro)'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
