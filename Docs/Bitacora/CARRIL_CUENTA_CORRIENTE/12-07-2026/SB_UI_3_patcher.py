#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SB-UI-3 -- Contenido de Acumulados (A31).  [corregido]

Alcance CERRADO. Toca UN SOLO archivo existente:
  src/screens/historico/HistoricoVista.tsx  -- 2 edits: import + reemplazo del placeholder.

Archivos NUEVOS que hay que copiar ANTES de correr esto:
  src/screens/historico/acumulados.ts
  src/screens/historico/ContenidoAcumulados.tsx

NO toca ninguno de los archivos cerrados en SB-UI-2 (maquina A30/selector, planSelector, estadoFoto,
Tarjeta, contratos, periodo, actionRegistry, rutas) ni `ui/`.

------------------------------------------------------------------------------------------------
GATES -- todos ANTES de escribir un solo byte (all-or-nothing)

  G1  SHA-256 de los 8 archivos CERRADOS.
  G2  SHA-256 de los 2 archivos NUEVOS. No alcanza con que EXISTAN: si se copio una version
      equivocada, el patcher aborta ANTES de tocar HistoricoVista.tsx, que queda intacto.
  G3  SHA-256 de HistoricoVista.tsx. Acepta DOS estados -> IDEMPOTENTE:
        PRE  (post SB-UI-2 FIX2, placeholder sin reemplazar) -> aplica los 2 edits;
        POST (SB-UI-3 ya aplicado)                           -> no hace nada, informa y sale.
      Cualquier otro hash = drift -> aborta.
  G4  Anclas unicas (count == 1) + el resultado se verifica contra el SHA-256 POST esperado antes
      de escribir.

Todos los hashes se calculan sobre el contenido NORMALIZADO A LF (se descarta '\\r'): robusto a la
config de line endings de git, estricto en contenido.
------------------------------------------------------------------------------------------------
"""

import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, 'src')

V = 'screens/historico/HistoricoVista.tsx'

# --- G3: los dos estados aceptables de HistoricoVista.tsx -------------------------------------
SHA_VISTA_PRE = 'e01e70abd62d80f25b17a1f194f7db5204e8e7c6e1e7038e252616676b23e053'
SHA_VISTA_POST = '34bfb01db6691327690b9e1b70206e14026a4c982589c6b6fc6ac67b57c295ce'

# --- G2: los archivos NUEVOS de este sub-bloque -----------------------------------------------
SHA_NUEVOS = {
    'screens/historico/acumulados.ts':
        '2e39b462c29015cc0a3cdd2855681f6043cb6bb39b85d6a6a04b32c5ae231df3',
    'screens/historico/ContenidoAcumulados.tsx':
        '51019b36935cc6cafc77c416e32d25246612a6a2d3c67e21765b54a9fa45dbb9',
}

# --- G1: los archivos CERRADOS en SB-UI-2 -----------------------------------------------------
SHA_CERRADOS = {
    'screens/HistoricoCuentaCorriente.tsx':
        '34c22426cb9f84643c689a96d6ed94644ad239e76e67b68fb6ec9beca654a1f6',
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

EDITS = [
    {
        'label': 'import de ContenidoAcumulados',
        'anchor': "import { clasificarFoto } from './estadoFoto';",
        'replacement': (
            "import { ContenidoAcumulados } from './ContenidoAcumulados';\n"
            "import { clasificarFoto } from './estadoFoto';"
        ),
    },
    {
        'label': 'placeholder -> ContenidoAcumulados',
        'anchor': """  if (acum.loading) return <Cargando mensaje="Cargando acumulados..." />;
  if (acum.error) return <ErrorCard error={acum.error} onRetry={acum.refetch} />;
  if (!acum.data) return null;

  return (
    <Tarjeta titulo="Acumulados históricos">
      <p className="text-sm text-reed">
        Pendiente SB-UI-3: totales acumulados (con desglose de gastos), evolución por período
        (ordenada) y saldos por socio, más los avisos de integridad (I1, I2, orden, pre-piso).
      </p>
    </Tarjeta>
  );
}""",
        'replacement': """  if (acum.loading) return <Cargando mensaje="Cargando acumulados..." />;
  if (acum.error) return <ErrorCard error={acum.error} onRetry={acum.refetch} />;
  if (!acum.data) return null;

  // SB-UI-3. El ciclo loading -> error -> data y el retry independiente de A31 quedan ACA, tal como
  // se aprobaron; `ContenidoAcumulados` recibe el `data` ya resuelto y es puro (sin hooks, sin red).
  return <ContenidoAcumulados data={acum.data} />;
}""",
    },
]


def sha_lf(texto):
    return hashlib.sha256(texto.replace('\r', '').encode('utf-8')).hexdigest()


def leer(rel):
    full = os.path.join(BASE, rel)
    if not os.path.exists(full):
        return None
    with io.open(full, 'r', encoding='utf-8', newline='') as fh:
        return fh.read()


def gate(titulo, esperados, marca):
    print('\n%s' % titulo)
    drift = []
    for rel, esperado in sorted(esperados.items()):
        txt = leer(rel)
        if txt is None:
            drift.append('%s :: NO EXISTE' % rel)
            print('  DRIFT   [%s] %-42s NO EXISTE' % (marca, rel))
            continue
        real = sha_lf(txt)
        if real != esperado:
            drift.append('%s :: esperado %s / real %s' % (rel, esperado[:16], real[:16]))
            print('  DRIFT   [%s] %-42s esperado %s / real %s'
                  % (marca, rel, esperado[:16], real[:16]))
        else:
            print('  ok      [%s] %-42s %s' % (marca, rel, real[:16]))
    return drift


def main():
    # ---- G1 -----------------------------------------------------------------------------------
    drift = gate('G1 -- archivos CERRADOS en SB-UI-2 (no se tocan):', SHA_CERRADOS, 'cerrado')

    # ---- G2: se valida el CONTENIDO de los nuevos, no solo su existencia. ---------------------
    drift += gate('G2 -- archivos NUEVOS de SB-UI-3 (copiarlos antes de correr esto):',
                  SHA_NUEVOS, ' nuevo ')

    # ---- G3: PRE -> aplica. POST -> ya aplicado. Otro -> drift. -------------------------------
    print('\nG3 -- HistoricoVista.tsx (idempotente):')
    vista = leer(V)
    aplicar = False
    if vista is None:
        drift.append('%s :: NO EXISTE' % V)
        print('  DRIFT   [MODIFICA] %-42s NO EXISTE' % V)
    else:
        sha_vista = sha_lf(vista)
        if sha_vista == SHA_VISTA_PRE:
            aplicar = True
            print('  ok      [MODIFICA] %-42s %s  (PRE -> se aplican los 2 edits)'
                  % (V, sha_vista[:16]))
        elif sha_vista == SHA_VISTA_POST:
            print('  ok      [ ya ok  ] %-42s %s  (POST -> SB-UI-3 ya aplicado)'
                  % (V, sha_vista[:16]))
        else:
            drift.append('%s :: hash %s no coincide ni con PRE ni con POST' % (V, sha_vista[:16]))
            print('  DRIFT   [MODIFICA] %-42s %s  (ni PRE ni POST)' % (V, sha_vista[:16]))

    assert not drift, (
        '\n\nDRIFT DETECTADO -- NO se escribio NADA. HistoricoVista.tsx queda intacto.\n  '
        + '\n  '.join(drift)
    )

    if not aplicar:
        print('\nNADA QUE HACER: HistoricoVista.tsx ya tiene SB-UI-3 aplicado, y los dos archivos '
              'nuevos son los correctos.')
        return 0

    # ---- G4: anclas unicas + verificacion del resultado. Todo en memoria. ---------------------
    src = vista
    for e in EDITS:
        n = src.count(e['anchor'])
        assert n == 1, 'ANCLA NO UNICA (%d) en %s :: %s' % (n, V, e['label'])
        src = src.replace(e['anchor'], e['replacement'], 1)

    assert '\r' not in src, 'CRLF DETECTADO en %s' % V
    assert sha_lf(src) == SHA_VISTA_POST, (
        'EL RESULTADO NO COINCIDE CON EL SHA-256 POST ESPERADO -- NO se escribio nada. '
        'Esperado %s / obtenido %s' % (SHA_VISTA_POST[:16], sha_lf(src)[:16])
    )

    # ---- write --------------------------------------------------------------------------------
    with io.open(os.path.join(BASE, V), 'w', encoding='utf-8', newline='') as fh:
        fh.write(src)

    print('\nOK: %d edits sobre 1 archivo' % len(EDITS))
    for e in EDITS:
        print('  [OK] %-38s %s' % (V, e['label']))
    print('  [OK] resultado verificado contra el SHA-256 POST esperado.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
