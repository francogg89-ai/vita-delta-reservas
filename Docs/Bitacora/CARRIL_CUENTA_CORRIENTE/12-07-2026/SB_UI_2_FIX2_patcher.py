#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SB-UI-2 FIX2 -- Reconciliacion sincronica del piso, retries tokenizados, seq monotonico, wording.

Alcance CERRADO. Toca exactamente 2 archivos:
  1. src/screens/HistoricoCuentaCorriente.tsx   -- seq monotonico, onRetryFoto, seleccionFueraDePiso
  2. src/screens/historico/HistoricoVista.tsx   -- compuerta sincronica, wording degradado

NO toca: planSelector.ts, estadoFoto.ts, Tarjeta.tsx, contratos.ts, periodo.ts, actionRegistry.ts,
         rutas.tsx.

SEGURIDAD FRENTE A DRIFT (obligacion nueva):
  - Antes de escribir NADA, se verifica el SHA-256 de los 9 archivos del bloque contra el estado
    esperado (post SB-UI-2 + FIX). Los 2 que se tocan y los 7 que NO se tocan.
  - El hash se computa sobre el contenido NORMALIZADO A LF (se descarta '\\r'), asi el gate es
    robusto a la config de line endings de git pero ESTRICTO en contenido.
  - Cualquier drift -> AssertionError -> NO se escribe ni un byte (all-or-nothing).
  - Ya no hay swap de archivo completo: el contenedor se parchea con str_replace anclado.
"""

import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, 'src')

# --- Precondicion: estado esperado ANTES de aplicar este patcher (post SB-UI-2 + FIX) ---------
SHA_ESPERADO = {
    # los 2 que este patcher MODIFICA
    'screens/HistoricoCuentaCorriente.tsx':
        'ae38932cd1a0d572d322d5cd16b9bd2c33f4b9c7c7ec634dea68dc77b60dc0f9',
    'screens/historico/HistoricoVista.tsx':
        'a1996fbcdfa4004891de88e1383821e0817e20d37396d5f1ba2e1607925ca8d6',
    # los 7 que este patcher NO debe tocar (se verifican igual: si alguno derivo, algo esta mal)
    'screens/historico/planSelector.ts':
        'bc6a52b26ed6d88e54e3d84c527bb213a18e8305e08266305efea95dd4ffb5ce',
    'screens/historico/estadoFoto.ts':
        '81fadd27eaa3bb0ddaba88f5600242bdf58099dfb9071e07325a85b5ee286a27',
    'ui/Tarjeta.tsx':
        '758683d2fab45eaa0deedee2fcfbaea0ad26fef4b19f78daee7aecd164275341',
    'lib/contratos.ts':
        '1716c58f306c83059d87ebc8eb7e6e23fbe5cb4c6067c76c1ca8fa24bcd18b6f',
    'lib/periodo.ts':
        'aeedb71dec7f7bfd484ad0718b54f038b0cf6a1eb5ec4aaf3623323dd1d1f32c',
    'lib/actionRegistry.ts':
        '5523ea8f7586d50d33d94696c1026486e254c68b030960acc6a13836d81c5808',
    'app/rutas.tsx':
        '8db14885a0d08b20068e5c3559270cbe2572153b3d01aa7ad3ded10f98056368',
}

MODIFICA = ('screens/HistoricoCuentaCorriente.tsx', 'screens/historico/HistoricoVista.tsx')

EDITS = []


def edit(path, anchor, replacement, label):
    EDITS.append({'path': path, 'anchor': anchor, 'replacement': replacement, 'label': label})


def sha_lf(texto):
    return hashlib.sha256(texto.replace('\r', '').encode('utf-8')).hexdigest()


C = 'screens/HistoricoCuentaCorriente.tsx'
V = 'screens/historico/HistoricoVista.tsx'

# =============================================================================================
# CONTENEDOR -- EDIT 1: seq MONOTONICO (punto 3)
# =============================================================================================
edit(C, """  const interactuado = useRef(false);

  // --- Lecturas (estados y retries INDEPENDIENTES por seccion) -------------------------------
""", """  const interactuado = useRef(false);

  /**
   * Contador MONOTONICO de peticiones A30. Es un ref independiente y NO se deriva de
   * `peticion?.seq`: al invalidar la peticion por piso, `peticion` pasa a null y derivar de ella
   * reiniciaria el contador en 1. Un `seq` repetido dejaria que una `servida` VIEJA declarara
   * servida una peticion creada DESPUES de la invalidacion -> el frame stale volveria a colarse.
   * Con un contador monotonico, ningun token se repite durante la vida del componente, y
   * `servida.mes === peticion.mes && servida.seq === peticion.seq` implica que son LA MISMA.
   */
  const siguienteSeq = useRef(0);
  const crearPeticion = useCallback(
    (mes: string): PeticionFoto => ({ mes, seq: ++siguienteSeq.current }),
    [],
  );

  // --- Lecturas (estados y retries INDEPENDIENTES por seccion) -------------------------------
""", 'seq monotonico (crearPeticion)')

# =============================================================================================
# CONTENEDOR -- EDIT 2: retry tokenizado + lectura que ve la vista (punto 2)
# =============================================================================================
edit(C, """  const fotoPendiente = peticion !== null && (!peticionServida || foto.loading);

  // --- Plan del selector ---------------------------------------------------------------------
""", """  const fotoPendiente = peticion !== null && (!peticionServida || foto.loading);

  // --- Retry A30: UNICA puerta de entrada ----------------------------------------------------
  /**
   * Todo reintento de A30 pasa por aca: el ErrorCard de error real, el ErrorCard de INCONSISTENTE
   * y el "Consultar" sobre el mismo mes. Genera un token NUEVO, con lo cual el pendiente se activa
   * SINCRONICAMENTE en el mismo render (`!peticionServida`), y recien despues fuerza el ciclo real
   * del hook.
   *
   * `refetchFoto()` es imprescindible: el mes no cambia, asi que el `payloadKey` de useAction
   * tampoco, y el hook no re-dispararia solo. Y es UNA sola llamada -> UN solo request.
   */
  const onRetryFoto = useCallback(() => {
    if (peticion === null) return; // no hay mes aplicado: no hay nada que reintentar
    if (fotoPendiente) return; // ya hay una consulta en vuelo
    setPeticion(crearPeticion(peticion.mes));
    refetchFoto();
  }, [peticion, fotoPendiente, crearPeticion, refetchFoto]);

  /**
   * La lectura A30 TAL COMO LA VE LA VISTA: mismo estado, pero con el `refetch` REEMPLAZADO por el
   * callback tokenizado. La vista no recibe `foto.refetch` crudo, asi que ningun ErrorCard puede
   * saltearse el token, el pendiente sincronico ni la compuerta anti-doble-request.
   */
  const fotoVista = useMemo<EstadoLectura<HistoricoMesData>>(
    () => ({ data: foto.data, loading: foto.loading, error: foto.error, refetch: onRetryFoto }),
    [foto.data, foto.loading, foto.error, onRetryFoto],
  );

  // --- Plan del selector ---------------------------------------------------------------------
""", 'onRetryFoto tokenizado + fotoVista (refetch crudo fuera del alcance de la vista)')

# =============================================================================================
# CONTENEDOR -- EDIT 3: reconciliacion SINCRONICA del piso (punto 1)
# =============================================================================================
edit(C, """  const plan = useMemo(() => construirPlanSelector(acumParaPlan, anclas), [acumParaPlan, anclas]);

  // --- Aplicacion inicial + reconciliacion contra el piso seguro (D-FE-49) --------------------
""", """  const plan = useMemo(() => construirPlanSelector(acumParaPlan, anclas), [acumParaPlan, anclas]);

  // --- Reconciliacion SINCRONICA del piso (D-FE-49) -------------------------------------------
  /**
   * El efecto de abajo normaliza el ESTADO PERSISTIDO, pero corre DESPUES del render. En el frame
   * en que A31 devuelve un piso mas alto, `mesDraft` y `peticion` todavia apuntan a un mes que ya
   * NO esta en `plan.opciones` (los anclas por debajo del piso no se preservan: fail-closed).
   * Sin esta compuerta, ese unico frame mostraria las cuatro cosas prohibidas a la vez:
   *   - un <select value> sin su <option>  -> el browser salta en silencio a la primera opcion;
   *   - la foto vieja, ya FUERA del piso;
   *   - el boton Consultar habilitado para un mes invalido;
   *   - ningun aviso.
   * El efecto no puede ser la unica defensa. Este derivado bloquea el selector y Consultar, evita
   * que se renderice la foto vieja, dispara el aviso y hace que el <select> use un `value` que SI
   * existe entre las opciones -- todo en el MISMO render en que aparece el piso nuevo.
   */
  const seleccionFueraDePiso =
    (mesDraft !== null && mesDraft < plan.pisoMes) ||
    (mesApplied !== null && mesApplied < plan.pisoMes);

  // --- Aplicacion inicial + reconciliacion contra el piso seguro (D-FE-49) --------------------
""", 'seleccionFueraDePiso (compuerta sincronica)')

# =============================================================================================
# CONTENEDOR -- EDIT 4/5: crearPeticion en la aplicacion inicial y en la invalidacion
# =============================================================================================
edit(C, """      inicializado.current = true;
      setMesDraft(porDefecto);
      setPeticion({ mes: porDefecto, seq: 1 });
      setReiniciadoPorPiso(false);
      return;""", """      inicializado.current = true;
      setMesDraft(porDefecto);
      setPeticion(crearPeticion(porDefecto));
      setReiniciadoPorPiso(false);
      return;""", 'aplicacion inicial usa crearPeticion')

edit(C, """  }, [ambas, acum.loading, acum.error, acum.data, plan, mesDraft, peticion]);""",
     """  }, [ambas, acum.loading, acum.error, acum.data, plan, mesDraft, peticion, crearPeticion]);""",
     'deps del efecto: + crearPeticion')

# =============================================================================================
# CONTENEDOR -- EDIT 6: onConsultar (seq monotonico + guard de piso)
# =============================================================================================
edit(C, """  const onConsultar = useCallback(() => {
    if (mesDraft === null) return;
    // Compuerta anti-doble-request (defensa 2 de 2; la 1 es el `disabled` del boton). Usa el
    // pendiente LOCAL: `foto.loading` no cambia sincronicamente en el primer render posterior al
    // click, asi que mirarlo solo dejaria pasar un segundo request.
    if (fotoPendiente) return;

    interactuado.current = true;
    setReiniciadoPorPiso(false);

    const mismoMes = peticion !== null && peticion.mes === mesDraft;
    setPeticion({ mes: mesDraft, seq: (peticion?.seq ?? 0) + 1 });

    // Mismo mes => el `payloadKey` de useAction NO cambia => el hook no re-dispara por si solo.
    // Hay que forzarlo. Con un mes DISTINTO no se llama: el cambio de payloadKey ya dispara, y
    // llamar refetch ademas produciria DOS requests.
    if (mismoMes) refetchFoto();
  }, [mesDraft, peticion, fotoPendiente, refetchFoto]);""",
     """  const onConsultar = useCallback(() => {
    if (mesDraft === null) return;
    // Compuerta anti-doble-request (defensa 2 de 2; la 1 es el `disabled` del boton). Usa el
    // pendiente LOCAL: `foto.loading` no cambia sincronicamente en el primer render posterior al
    // click, asi que mirarlo solo dejaria pasar un segundo request.
    if (fotoPendiente) return;
    // El estado todavia no fue normalizado contra un piso nuevo: no se consulta un mes invalido.
    if (seleccionFueraDePiso) return;

    interactuado.current = true;
    setReiniciadoPorPiso(false);

    const mismoMes = peticion !== null && peticion.mes === mesDraft;
    setPeticion(crearPeticion(mesDraft));

    // Mismo mes => el `payloadKey` de useAction NO cambia => el hook no re-dispara por si solo.
    // Hay que forzarlo. Con un mes DISTINTO no se llama: el cambio de payloadKey ya dispara, y
    // llamar refetch ademas produciria DOS requests.
    if (mismoMes) refetchFoto();
  }, [mesDraft, peticion, fotoPendiente, seleccionFueraDePiso, crearPeticion, refetchFoto]);""",
     'onConsultar: crearPeticion + guard de piso')

# =============================================================================================
# CONTENEDOR -- EDIT 7: props a la vista
# =============================================================================================
edit(C, """      acum={acum}
      foto={foto}
      fotoPendiente={fotoPendiente}
      plan={plan}
      mesDraft={mesDraft}
      mesApplied={mesApplied}
      reiniciadoPorPiso={reiniciadoPorPiso}""",
     """      acum={acum}
      foto={fotoVista}
      fotoPendiente={fotoPendiente}
      seleccionFueraDePiso={seleccionFueraDePiso}
      plan={plan}
      mesDraft={mesDraft}
      mesApplied={mesApplied}
      reiniciadoPorPiso={reiniciadoPorPiso}""",
     'props: foto -> fotoVista, + seleccionFueraDePiso')

# =============================================================================================
# CONTENEDOR -- EDIT 8: import del tipo EstadoLectura
# =============================================================================================
edit(C, """import { HistoricoVista } from './historico/HistoricoVista';""",
     """import { HistoricoVista } from './historico/HistoricoVista';
import type { EstadoLectura } from './historico/HistoricoVista';""",
     'import type EstadoLectura')

# =============================================================================================
# VISTA -- EDIT 9: prop seleccionFueraDePiso
# =============================================================================================
edit(V, """  fotoPendiente: boolean;
  plan: PlanSelector;""",
     """  fotoPendiente: boolean;
  /**
   * El piso seguro subio y la seleccion actual quedo por debajo, pero el efecto que normaliza el
   * estado todavia no corrio. En este render: se bloquean selector y Consultar, NO se renderiza la
   * foto vieja (quedo fuera del piso), se muestra el aviso, y el <select> usa `plan.porDefecto`
   * como `value` -- que siempre existe entre las opciones.
   */
  seleccionFueraDePiso: boolean;
  plan: PlanSelector;""",
     'props: + seleccionFueraDePiso')

# =============================================================================================
# VISTA -- EDIT 10: SelectorMes -- firma + compuertas
# =============================================================================================
edit(V, """function SelectorMes({
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
""",
     """function SelectorMes({
  plan,
  mesDraft,
  cargandoAcum,
  fotoPendiente,
  seleccionFueraDePiso,
  reiniciadoPorPiso,
  onMesDraftChange,
  onConsultar,
}: {
  plan: PlanSelector;
  mesDraft: string | null;
  cargandoAcum: boolean;
  fotoPendiente: boolean;
  seleccionFueraDePiso: boolean;
  reiniciadoPorPiso: boolean;
  onMesDraftChange: (ym: string) => void;
  onConsultar: () => void;
}) {
  const listo = !cargandoAcum && mesDraft !== null;
  // Defensa 1 de 2 contra el doble request (la 2 es el early-return de `onConsultar`). El select
  // queda habilitado a proposito mientras A30 esta en vuelo: cambiar el draft no dispara nada.
  const puedeConsultar = listo && !fotoPendiente && !seleccionFueraDePiso;

  // Con la seleccion fuera del piso, el `value` NO puede ser `mesDraft` (ya no tiene <option>: el
  // browser saltaria en silencio a la primera opcion). `plan.porDefecto` siempre esta entre las
  // opciones, por construccion de `construirPlanSelector`.
  const valorSelect = seleccionFueraDePiso ? plan.porDefecto : (mesDraft ?? '');
  const selectHabilitado = listo && !seleccionFueraDePiso && plan.opciones.length > 0;
""",
     'SelectorMes: + seleccionFueraDePiso, valorSelect, selectHabilitado')

# =============================================================================================
# VISTA -- EDIT 11: banner degradado (wording verdadero) + banner de reinicio sincronico
# =============================================================================================
edit(V, """      {plan.degradado && !cargandoAcum && (
        <Banner tono="aviso">
          No se pudieron cargar los acumulados. El listado de meses puede estar incompleto: no se
          muestran meses posteriores al actual ni la marca de qué meses tienen foto.
        </Banner>
      )}

      {reiniciadoPorPiso && (
        <Banner tono="aviso">
          El piso contable del servidor cambió y es posterior al mes que estabas consultando. Se
          reinició la selección: elegí un mes y tocá Consultar.
        </Banner>
      )}
""",
     """      {plan.degradado && !cargandoAcum && (
        <Banner tono="aviso">
          No se pudieron cargar los acumulados. El listado puede estar incompleto y no se puede
          verificar qué meses tienen foto. Los meses que ya habías seleccionado o consultado se
          conservan.
        </Banner>
      )}

      {(seleccionFueraDePiso || reiniciadoPorPiso) && (
        <Banner tono="aviso">
          El piso contable del servidor cambió y es posterior al mes que estabas consultando. Se
          reinició la selección: elegí un mes y tocá Consultar.
        </Banner>
      )}
""",
     'banners: wording degradado verdadero + aviso de reinicio sincronico')

# =============================================================================================
# VISTA -- EDIT 12: <select> con value/disabled seguros
# =============================================================================================
edit(V, """          <select
            id="mes-historico"
            className={controlClass}
            value={mesDraft ?? ''}
            disabled={!listo}
            onChange={(e) => onMesDraftChange(e.target.value)}
          >
            {mesDraft === null && <option value="">Cargando meses...</option>}""",
     """          <select
            id="mes-historico"
            className={controlClass}
            value={valorSelect}
            disabled={!selectHabilitado}
            onChange={(e) => onMesDraftChange(e.target.value)}
          >
            {mesDraft === null && <option value="">Cargando meses...</option>}""",
     'select: value/disabled seguros')

# =============================================================================================
# VISTA -- EDIT 13: SeccionFotoMes -- no renderizar la foto fuera del piso
# =============================================================================================
edit(V, """function SeccionFotoMes({
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
""",
     """function SeccionFotoMes({
  foto,
  fotoPendiente,
  seleccionFueraDePiso,
  mesApplied,
}: {
  foto: EstadoLectura<HistoricoMesData>;
  fotoPendiente: boolean;
  seleccionFueraDePiso: boolean;
  mesApplied: string | null;
}) {
  // Inactivo: sin mes aplicado el hook va con enabled:false -> CERO request.
  // `seleccionFueraDePiso` entra por la misma puerta: el piso subio y el mes que teniamos aplicado
  // quedo por debajo. La foto vieja NO se renderiza aunque el `data` siga en mano y su T1 pase: ese
  // mes ya no es consultable. El aviso de reinicio, arriba, da el contexto.
  if (seleccionFueraDePiso || mesApplied === null) {
    return (
      <Tarjeta titulo="Foto del mes">
        <p className="text-sm text-reed">Elegí un mes y tocá Consultar.</p>
      </Tarjeta>
    );
  }
""",
     'SeccionFotoMes: + seleccionFueraDePiso (no renderiza la foto fuera del piso)')

# =============================================================================================
# VISTA -- EDIT 14/15: destructuring + cableado
# =============================================================================================
edit(V, """  acum,
  foto,
  fotoPendiente,
  plan,
  mesDraft,
  mesApplied,
  reiniciadoPorPiso,
  onMesDraftChange,
  onConsultar,
}: HistoricoVistaProps) {""",
     """  acum,
  foto,
  fotoPendiente,
  seleccionFueraDePiso,
  plan,
  mesDraft,
  mesApplied,
  reiniciadoPorPiso,
  onMesDraftChange,
  onConsultar,
}: HistoricoVistaProps) {""",
     'HistoricoVista: destructurar seleccionFueraDePiso')

edit(V, """      <SelectorMes
        plan={plan}
        mesDraft={mesDraft}
        cargandoAcum={acum.loading}
        fotoPendiente={fotoPendiente}
        reiniciadoPorPiso={reiniciadoPorPiso}
        onMesDraftChange={onMesDraftChange}
        onConsultar={onConsultar}
      />
      <SeccionFotoMes foto={foto} fotoPendiente={fotoPendiente} mesApplied={mesApplied} />""",
     """      <SelectorMes
        plan={plan}
        mesDraft={mesDraft}
        cargandoAcum={acum.loading}
        fotoPendiente={fotoPendiente}
        seleccionFueraDePiso={seleccionFueraDePiso}
        reiniciadoPorPiso={reiniciadoPorPiso}
        onMesDraftChange={onMesDraftChange}
        onConsultar={onConsultar}
      />
      <SeccionFotoMes
        foto={foto}
        fotoPendiente={fotoPendiente}
        seleccionFueraDePiso={seleccionFueraDePiso}
        mesApplied={mesApplied}
      />""",
     'HistoricoVista: cablear seleccionFueraDePiso')


# =============================================================================================
# Ejecucion
# =============================================================================================
def main():
    # ---- GATE 1: precondicion por SHA-256. Antes de leer anclas, antes de escribir nada. -----
    print('GATE SHA-256 (contenido normalizado a LF):')
    drift = []
    for rel, esperado in sorted(SHA_ESPERADO.items()):
        full = os.path.join(BASE, rel)
        if not os.path.exists(full):
            drift.append('%s :: NO EXISTE' % rel)
            continue
        with io.open(full, 'r', encoding='utf-8', newline='') as fh:
            real = sha_lf(fh.read())
        marca = 'MODIFICA' if rel in MODIFICA else 'intacto '
        if real != esperado:
            drift.append('%s :: esperado %s / real %s' % (rel, esperado[:16], real[:16]))
            print('  DRIFT   [%s] %s' % (marca, rel))
        else:
            print('  ok      [%s] %s  %s' % (marca, rel.ljust(38), real[:16]))

    assert not drift, 'DRIFT DETECTADO -- NO se escribio nada:\n  ' + '\n  '.join(drift)

    # ---- GATE 2: anclas unicas. Todo en memoria. ---------------------------------------------
    planned = {}
    for e in EDITS:
        full = os.path.join(BASE, e['path'])
        if full not in planned:
            with io.open(full, 'r', encoding='utf-8', newline='') as fh:
                planned[full] = fh.read()
        src = planned[full]
        n = src.count(e['anchor'])
        assert n == 1, 'ANCLA NO UNICA (%d) en %s :: %s' % (n, e['path'], e['label'])
        planned[full] = src.replace(e['anchor'], e['replacement'], 1)

    for full, content in planned.items():
        assert '\r' not in content, 'CRLF DETECTADO en %s' % full

    # ---- GATE 3: solo se tocan los 2 archivos declarados --------------------------------------
    tocados = {os.path.relpath(f, BASE).replace(os.sep, '/') for f in planned}
    assert tocados == set(MODIFICA), 'ALCANCE VIOLADO: %s' % sorted(tocados)

    # ---- write (all-or-nothing: recien aca se toca el disco) ----------------------------------
    for full, content in planned.items():
        with io.open(full, 'w', encoding='utf-8', newline='') as fh:
            fh.write(content)

    print('\nOK: %d edits sobre %d archivos' % (len(EDITS), len(planned)))
    for e in EDITS:
        print('  [OK] %-38s %s' % (e['path'], e['label']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
