#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SB-UI-4 -- Contenido de la Foto del mes (A30).

Alcance CERRADO. Toca UN SOLO archivo existente:
  src/screens/historico/HistoricoVista.tsx  -- 2 edits: import + reemplazo del placeholder de la
                                               seccion Foto del mes.

Archivos NUEVOS que hay que copiar ANTES de correr esto:
  src/screens/historico/foto.ts
  src/screens/historico/ContenidoFoto.tsx

NO toca nada de SB-UI-2 (maquina A30/selector, planSelector, estadoFoto, Tarjeta, contratos,
periodo, actionRegistry, rutas) ni de SB-UI-3 (acumulados.ts, ContenidoAcumulados.tsx) ni `ui/`.

------------------------------------------------------------------------------------------------
GATES -- todos ANTES de escribir un solo byte (all-or-nothing)

  G1  SHA-256 de los 10 archivos CERRADOS (SB-UI-2 + SB-UI-3).
  G2  SHA-256 de los 2 archivos NUEVOS. No alcanza con que existan: si se copio una version
      equivocada, aborta ANTES de tocar HistoricoVista.tsx, que queda intacto.
  G3  SHA-256 de HistoricoVista.tsx. Acepta DOS estados -> IDEMPOTENTE:
        PRE  (post SB-UI-3, placeholder de la foto sin reemplazar) -> aplica los 2 edits;
        POST (SB-UI-4 ya aplicado)                                 -> no hace nada y sale.
      Cualquier otro hash = drift -> aborta.
  G4  Anclas unicas (count == 1) + el resultado se verifica contra el SHA-256 POST esperado antes
      de escribir.

Hashes sobre contenido NORMALIZADO A LF (se descarta '\\r').
------------------------------------------------------------------------------------------------
"""

import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, 'src')

V = 'screens/historico/HistoricoVista.tsx'

SHA_VISTA_PRE = '34bfb01db6691327690b9e1b70206e14026a4c982589c6b6fc6ac67b57c295ce'
SHA_VISTA_POST = 'c0293a454dc695d0913b6bee366970a103e74f36572332f594d68862cc475237'

SHA_NUEVOS = {
    'screens/historico/foto.ts':
        'a28ba21d6bcea59b7eaabc06ac03a73383020681477460f4f58b246e7a8cd47c',
    'screens/historico/ContenidoFoto.tsx':
        'b4d913f6ae26ff7623ab81a1c716016c6ac967ea60a62f3b483ef7ec9357bb94',
}

SHA_CERRADOS = {
    # SB-UI-2
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
    # SB-UI-3
    'screens/historico/acumulados.ts':
        '2e39b462c29015cc0a3cdd2855681f6043cb6bb39b85d6a6a04b32c5ae231df3',
    'screens/historico/ContenidoAcumulados.tsx':
        '51019b36935cc6cafc77c416e32d25246612a6a2d3c67e21765b54a9fa45dbb9',
}

EDITS = [
    {
        'label': 'import de ContenidoFoto',
        'anchor': "import { ContenidoAcumulados } from './ContenidoAcumulados';",
        'replacement': (
            "import { ContenidoAcumulados } from './ContenidoAcumulados';\n"
            "import { ContenidoFoto } from './ContenidoFoto';"
        ),
    },
    {
        # Reemplaza SOLO el `return` final de SeccionFotoMes. Todo lo de arriba (inactivo,
        # seleccionFueraDePiso, fotoPendiente, error, INCONSISTENTE, retry tokenizado, T1-T7)
        # queda EXACTAMENTE como estaba.
        'label': 'placeholder de la foto -> ContenidoFoto',
        'anchor': """  return (
    <div className="space-y-4">
      {estado === 'E2' && (
        <Banner tono="info" titulo="Foto anterior a la extensión del detalle fino">
          La cascada y el resultado por socio están completos. El desglose gasto por gasto no se
          congeló para este período.
        </Banner>
      )}

      {estado === 'E3' && (
        <Banner tono="info" titulo="Este mes todavía no tiene foto congelada">
          Todavía no se corrió el cierre del período.
        </Banner>
      )}

      <Tarjeta titulo="Foto del mes">
        <p className="text-sm text-reed">
          Estado <span className="font-medium text-ink">{estado}</span> · período{' '}
          <span className="font-medium text-ink">{foto.data.periodo}</span>.
        </p>
        <p className="mt-2 text-sm text-reed">
          Pendiente SB-UI-4: cabecera de la foto, cascada, resultado por socio, retribución
          operativa (mixta), movimientos del mes (en vivo) y detalle fino colapsable.
        </p>
      </Tarjeta>
    </div>
  );
}""",
        'replacement': """  // SB-UI-4. `estado` ya quedo estrechado a 'E1' | 'E2' | 'E3' por el early return de arriba.
  // `ContenidoFoto` recibe el `data` YA clasificado y validado contra T1-T7, y es puro (sin hooks,
  // sin red). Los banners de E2 y E3 viven ahora ahi, junto al contenido que gobiernan.
  return <ContenidoFoto data={foto.data} estado={estado} />;
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
            print('  DRIFT   [%s] %-44s NO EXISTE' % (marca, rel))
            continue
        real = sha_lf(txt)
        if real != esperado:
            drift.append('%s :: esperado %s / real %s' % (rel, esperado[:16], real[:16]))
            print('  DRIFT   [%s] %-44s esperado %s / real %s'
                  % (marca, rel, esperado[:16], real[:16]))
        else:
            print('  ok      [%s] %-44s %s' % (marca, rel, real[:16]))
    return drift


def main():
    drift = gate('G1 -- CERRADOS en SB-UI-2 / SB-UI-3 (no se tocan):', SHA_CERRADOS, 'cerrado')
    drift += gate('G2 -- NUEVOS de SB-UI-4 (copiarlos antes de correr esto):', SHA_NUEVOS, ' nuevo ')

    print('\nG3 -- HistoricoVista.tsx (idempotente):')
    vista = leer(V)
    aplicar = False
    if vista is None:
        drift.append('%s :: NO EXISTE' % V)
        print('  DRIFT   [MODIFICA] %-44s NO EXISTE' % V)
    else:
        sha_vista = sha_lf(vista)
        if sha_vista == SHA_VISTA_PRE:
            aplicar = True
            print('  ok      [MODIFICA] %-44s %s  (PRE -> se aplican los 2 edits)'
                  % (V, sha_vista[:16]))
        elif sha_vista == SHA_VISTA_POST:
            print('  ok      [ ya ok  ] %-44s %s  (POST -> SB-UI-4 ya aplicado)'
                  % (V, sha_vista[:16]))
        else:
            drift.append('%s :: hash %s no coincide ni con PRE ni con POST' % (V, sha_vista[:16]))
            print('  DRIFT   [MODIFICA] %-44s %s  (ni PRE ni POST)' % (V, sha_vista[:16]))

    assert not drift, (
        '\n\nDRIFT DETECTADO -- NO se escribio NADA. HistoricoVista.tsx queda intacto.\n  '
        + '\n  '.join(drift)
    )

    if not aplicar:
        print('\nNADA QUE HACER: HistoricoVista.tsx ya tiene SB-UI-4 aplicado, y los dos archivos '
              'nuevos son los correctos.')
        return 0

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

    with io.open(os.path.join(BASE, V), 'w', encoding='utf-8', newline='') as fh:
        fh.write(src)

    print('\nOK: %d edits sobre 1 archivo' % len(EDITS))
    for e in EDITS:
        print('  [OK] %-38s %s' % (V, e['label']))
    print('  [OK] resultado verificado contra el SHA-256 POST esperado.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
