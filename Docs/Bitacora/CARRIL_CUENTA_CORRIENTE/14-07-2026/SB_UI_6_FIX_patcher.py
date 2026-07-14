#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SB-UI-6-FIX -- Correccion del harness.

SIGUE SIN MOVER UN SOLO BYTE DE `src/`. No toca AppShell ni DataTable. H-1 y H-2 quedan
confirmados para el siguiente sub-bloque de correccion de produccion.

QUE CAMBIA RESPECTO DE SB-UI-6
  1. PORTABILIDAD WINDOWS -- `qa/higiene.mjs` no invoca mas `grep`, `mkdir -p` ni shell POSIX.
     Todo con APIs de Node. `qa:probes` pasa a `node qa/run-probes.mjs` (sin `&&`, sin `mkdir -p`).
     El propio `qa:higiene` (H5) verifica esto y falla si alguien reintroduce una dependencia POSIX.
  2. DEPENDENCIAS REPRODUCIBLES -- `esbuild` y `playwright` pasan a devDependencies DIRECTAS.
     Por eso hay que copiar `package.json` Y `package-lock.json`: editar el lock a mano rompe
     `npm ci`. El patcher NO los edita: los verifica.
  3. COBERTURA ESTRUCTURAL REAL -- bloque E (HistoricoVista renderizada, 10 casos) y
     `qa/estructural.mjs` (contenedor REAL en Chromium, 29 aserciones: token, anti-doble-request,
     `enabled`). Solo `window.fetch` es falso: `useAction` y `callPortal` corren de verdad.
  4. SCROLL NO TAUTOLOGICO -- se lee `overflowX` computado, se ASIGNA `scrollLeft`, se comprueba
     que CAMBIO, y se restaura.
  5. H-2 REPRODUCIBLE -- lo mide `qa:responsive`, con screenshot. Ya no vive solo en un .md.
  6. F20 CORREGIDO -- clase E -> (id_zona null, id_cabana 5); clase D -> (id_zona 3, id_cabana null).
  7. DOC CORREGIDA -- 197 aserciones (no 145), siete comandos (no cinco), matriz de cobertura con
     AUTO / MANUAL / NO CUBIERTO.

------------------------------------------------------------------------------------------------
COMO SE APLICA

  1. Copiar los 17 archivos del harness (qa/, vite.qa.config.ts, tsconfig.qa.json).
  2. Copiar `package.json` y `package-lock.json` (los DOS: si no, `npm ci` falla).
  3. python SB_UI_6_FIX_patcher.py     <- verifica TODO y aborta si algo no cuadra
  4. npm ci
  5. npx playwright install chromium

------------------------------------------------------------------------------------------------
GATES

  G1  SHA-256 de los 14 archivos de `src/` cerrados en SB-UI-5. SB-UI-6-FIX no los toca: un drift
      aca significa que el arbol no es el que Franco aprobo.
  G2  SHA-256 de los 17 archivos del harness.
  G3  SHA-256 de `package.json` y `package-lock.json`. Aceptan DOS estados -> IDEMPOTENTE:
        PRE  (SB-UI-6 aplicado, sin esbuild/playwright) -> avisa exactamente que falta copiar;
        POST (SB-UI-6-FIX aplicado)                     -> todo listo.
      Si UNO esta en POST y el otro en PRE, aborta: un `npm ci` con manifests desalineados falla.

Hashes sobre contenido NORMALIZADO A LF (se descarta '\\r').
------------------------------------------------------------------------------------------------
"""

import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# --- G3: los dos manifests, que se COPIAN (no se editan) --------------------------------------
MANIFESTS = {
    'package.json': {
        'pre': 'f8855e0063f745ccf315b3b108718bb308e59a4503d546cb8ab920e611cd7076',
        'post': '2bb6f390fd6593f13462c7707bc5839fb6d63335dfd943cceba7b63dd1d759c4',
    },
    'package-lock.json': {
        'pre': '329f9e8a683f566368404aef1150e3fce8070b230f48604e5eef6a493ab7063d',
        'post': '5a1290f3f47baf9b1c7e1511e69c5bb4bbfdb1cdb3c04c9c1a922999e69a0ff5',
    },
}

# --- G2: el harness ---------------------------------------------------------------------------
SHA_HARNESS = {
    'qa/fixtures.ts': 'e169a1c235e013137090de10110ce15100936fd9830a9b51651c6fbe3d3ad6dd',
    'qa/probes.tsx': '2d6c6df0905da9db56bac496b7a04783b5141c0abea0a07f1cfd5036167d91dc',
    'qa/higiene.mjs': '1f02732e4528026a466ea756190dc44cf824d23b0cb9ef30b1b1f386be4ab092',
    'qa/run-probes.mjs': 'ebe3165c87485144e17012e766dc32a61732410ea285c267a92a1e83a68629bb',
    'qa/responsive.mjs': '793cf1818e49227af64eb12267a543e631708b7da800d2d92e4f26db927f697c',
    'qa/estructural.mjs': '2d319ec99576c75b5ff5a1dc83eca2f6397d76636fc9a4f070ccf8e158dfab8d',
    'qa/store.tsx': '62e450d7a96bc3ffd0ad91e95c35e67484398a5c37b14dfbdb5982a1df97187c',
    'qa/stubs/rutas.tsx': '7c16e699d96530a2b2307c06b33ef6f407740434b16037b3df6d1ea9d5fd12a4',
    'qa/stubs/red.ts': 'c03a9805de9d7949b1ba61b533b926a2daeb3d954515a7fb4464be614fbd6d41',
    'qa/BarraQA.tsx': 'd65ca57bbef2558dd6825a4bf0b617e0775ce589af5ca6062645228c2b9cdf18',
    'qa/main.tsx': 'c74accfe968425de68ac73e54e0537f529483da1682de2e1b4a2b258496c6b76',
    'qa/index.html': 'c7f565c72ed3da164591e2f45822d46434d83d6f0447d124d06a48253cfa4843',
    'qa/RUNSHEET.md': '76291c9b4307300fbb01afb54215d6d17c29301bc413022699ee8a391c8dd8dd',
    'qa/SMOKE_MANUAL.md': '3d6e0fbb13388c0ad3f4cd72a942eddb5581c5acfb1bc8713e9e43d3421f15fe',
    'qa/COBERTURA.md': '43ffc346a20b5603a7b3c739ed22ab134559efd6043f1a7bb952ceaf5ea5cab3',
    'vite.qa.config.ts': 'c9bf82ff672f964c1e6749e51df155dcd6270a18412e5aef28db3bc29db1e853',
    'tsconfig.qa.json': '074eae34aa606912853eccf168fb12e346fb88e182078ed354875a8e32ed9d09',
}

# --- G1: `src/` NO se toca --------------------------------------------------------------------
SHA_CERRADOS = {
    'src/app/AppShell.tsx':
        '08ebbbd6289ed20edf67d7708053d13b5f563a3eee54822e0d6302f22438a0ba',
    'src/screens/historico/naturaleza.tsx':
        '28ff85c1dd4dbd34db4c676377c05085b4b11e985cca0d189d8172e3a7b36919',
    'src/screens/historico/ContenidoFoto.tsx':
        'c87d9aaa8e1c6d25a049553c86263b2837b12e925540d213b545c8c06269088e',
    'src/screens/historico/ContenidoAcumulados.tsx':
        '521cc947fd8a1528dcff42313dd4d36586ac84a10091335066997c38cefdcb3f',
    'src/screens/historico/HistoricoVista.tsx':
        'c0293a454dc695d0913b6bee366970a103e74f36572332f594d68862cc475237',
    'src/screens/historico/foto.ts':
        'a61cf1a8838432eb76bae8fecf0190e456f61d5f031815fec758b22fa9262957',
    'src/screens/historico/acumulados.ts':
        '2e39b462c29015cc0a3cdd2855681f6043cb6bb39b85d6a6a04b32c5ae231df3',
    'src/screens/historico/planSelector.ts':
        'bc6a52b26ed6d88e54e3d84c527bb213a18e8305e08266305efea95dd4ffb5ce',
    'src/screens/historico/estadoFoto.ts':
        '81fadd27eaa3bb0ddaba88f5600242bdf58099dfb9071e07325a85b5ee286a27',
    'src/screens/HistoricoCuentaCorriente.tsx':
        '34c22426cb9f84643c689a96d6ed94644ad239e76e67b68fb6ec9beca654a1f6',
    'src/ui/DataTable.tsx':
        'ae62d8f1439f6fee44be5e532b88ae68a09989168579460cfb346c4a623009f2',
    'src/lib/contratos.ts':
        '1716c58f306c83059d87ebc8eb7e6e23fbe5cb4c6067c76c1ca8fa24bcd18b6f',
    # Los dos modulos que el harness monta DE VERDAD en `qa:estructural`. Si cambian, el contenedor
    # que se esta probando ya no es el que se aprobo.
    'src/hooks/useAction.ts': '0035ae7dbcaf44b2d4eebc49fcb676a1371743aa21c6f56562af672d46c9f378',
    'src/lib/callPortal.ts': '06a1c19423c872b5867d9ed4a3f9e1aa09940843c4bd351a8dc9f0a8d21712ab',
}


def sha_lf(t):
    return hashlib.sha256(t.replace('\r', '').encode('utf-8')).hexdigest()


def leer(rel):
    full = os.path.join(HERE, rel)
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
            print('  DRIFT   [%s] %-28s NO EXISTE' % (marca, rel))
            continue
        real = sha_lf(txt)
        if real != esperado:
            drift.append('%s :: esperado %s / real %s' % (rel, esperado[:16], real[:16]))
            print('  DRIFT   [%s] %-28s esperado %s / real %s'
                  % (marca, rel, esperado[:16], real[:16]))
        else:
            print('  ok      [%s] %-28s %s' % (marca, rel, real[:16]))
    return drift


def main():
    drift = gate('G1 -- src/ CERRADO (SB-UI-6-FIX no lo toca):', SHA_CERRADOS, 'cerrado')
    drift += gate('G2 -- HARNESS (17 archivos):', SHA_HARNESS, 'harness')

    print('\nG3 -- MANIFESTS (se COPIAN; editar el lock a mano rompe `npm ci`):')
    estados = {}
    for rel, h in sorted(MANIFESTS.items()):
        txt = leer(rel)
        if txt is None:
            drift.append('%s :: NO EXISTE' % rel)
            print('  DRIFT   [manifest] %-20s NO EXISTE' % rel)
            continue
        s = sha_lf(txt)
        if s == h['post']:
            estados[rel] = 'POST'
            print('  ok      [ ya ok  ] %-20s %s  (POST)' % (rel, s[:16]))
        elif s == h['pre']:
            estados[rel] = 'PRE'
            print('  FALTA   [ copiar ] %-20s %s  (PRE -> copiá el %s del artefacto)'
                  % (rel, s[:16], rel))
        else:
            drift.append('%s :: hash %s no coincide ni con PRE ni con POST' % (rel, s[:16]))
            print('  DRIFT   [manifest] %-20s %s  (ni PRE ni POST)' % (rel, s[:16]))

    assert not drift, (
        '\n\nDRIFT DETECTADO -- NO se escribio NADA.\n  ' + '\n  '.join(drift)
    )

    vals = set(estados.values())
    assert vals != {'PRE', 'POST'}, (
        '\n\nMANIFESTS DESALINEADOS: uno esta en PRE y el otro en POST.\n'
        '  `npm ci` FALLA si package.json y package-lock.json no se corresponden.\n'
        '  Copia los DOS del artefacto.'
    )

    if vals == {'PRE'}:
        print(
            '\nFALTA COPIAR LOS MANIFESTS.\n'
            '  El harness ya esta bien, pero `esbuild` y `playwright` todavia no son\n'
            '  devDependencies directas. Copia package.json Y package-lock.json del artefacto,\n'
            '  volve a correr esto, y despues:  npm ci'
        )
        return 1

    print('\nTODO EN POST. SB-UI-6-FIX aplicado.')
    print('  src/ NO se modifico: el codigo de produccion sigue intacto.')
    print('\n  Siguiente:')
    print('    npm ci')
    print('    npx playwright install chromium')
    print('    npm run build ; npm run typecheck ; npm run typecheck:qa')
    print('    npm run qa:probes ; npm run qa:higiene ; npm run qa:build')
    print('    npm run qa            (y en otra consola:)')
    print('    npm run qa:estructural ; npm run qa:responsive')
    return 0


if __name__ == '__main__':
    sys.exit(main())
