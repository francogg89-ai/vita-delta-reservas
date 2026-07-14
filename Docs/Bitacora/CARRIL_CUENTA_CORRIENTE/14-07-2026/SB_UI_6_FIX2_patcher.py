#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SB-UI-6-FIX2 -- Correccion acotada del harness.

SIGUE SIN MOVER UN SOLO BYTE DE `src/`. H-1 y H-2 quedan para el sub-bloque productivo posterior.

QUE CAMBIA RESPECTO DE SB-UI-6-FIX

  1. F3 YA NO MIENTE. Se llamaba "token de peticion" y no lo era: las dos peticiones A31 de
     StrictMode pertenecen a DOS INSTANCIAS distintas del hook, cada una con su propio `reqId`
     (`useRef`), y lo que descarta la respuesta huerfana es el `activo=false` de SU cleanup -- el
     `reqId` ni se entera. Encima las dos devolvian F10, asi que una sobrescritura vieja habria sido
     invisible. Ahora F3 se llama CLEANUP, que es lo que prueba.

  2. `reqId` PROBADO DE VERDAD (F7). Host `?host=requid`: UNA sola instancia de `useAction`, SIN
     StrictMode. Request 1 = F2 (anomalo, 600ms) -> `refetch` en vuelo -> request 2 = F1 (normal,
     50ms). La vieja llega DESPUES y no puede pisar a la nueva.

  3. MUTATION GATE (`npm run qa:mutacion`). Deriva mutantes de `useAction` y los inyecta EN MEMORIA
     con un plugin de Vite: no escribe un solo archivo y no toca `src/`.
     HALLAZGO: cleanup y `reqId` son REDUNDANTES entre si. Borrando `myId !== reqId.current` la
     prueba pasa igual; borrando `!activo` tambien. Solo borrando LAS DOS la respuesta vieja pisa a
     la nueva. React corre el cleanup del efecto anterior ANTES de re-ejecutarlo, asi que `activo`
     ya cubre el caso. `reqId` es defensa en profundidad, no el mecanismo activo. Esta documentado
     como tal: F7 prueba el DESCARTE, no que lo haga `reqId`.

  4. FAIL-CLOSED EN EL CONTENEDOR REAL (F8). Las acciones de la sesion QA ahora son configurables
     (`?acciones=ambas|solo-a30|solo-a31|ninguna`). En los tres estados incompletos: banner,
     selector ausente, cero cifras, CERO llamadas A30 y CERO A31. Renderizar `HistoricoVista` con
     `faltaAccion:true` era asumir la conclusion.

  5. RETRY DE A30 CON CLIC (F9). El bloque E4 invocaba `foto.refetch()` a mano: probaba el callback,
     no el boton. Ahora: A31 OK -> A30 ok:false -> ErrorCard -> el servidor se recupera -> CLIC en el
     boton real -> exactamente UNA peticion A30 adicional -> la foto aparece.

  6. SNAPSHOT AL RECIBIR. El stub leia el fixture DESPUES del `await` de la latencia, desde un
     control global mutable: una peticion que salio pidiendo el fixture A y tardo 600ms terminaba
     devolviendo el fixture B. El stub se "auto-corregia" y tapaba justo el bug que hay que cazar.
     Ahora cada request captura fixture, demora y resultado AL ENTRAR, y no vuelve a mirar el control.

  7. `.gitignore` -- `dist-qa/` y `qa/screenshots/` son SALIDA, no fuente. Gate G4.

  8. F20 COHERENTE + BLOQUE G. #71 (clase E) -> regla `cabana_directa`; #72 (clase D) -> regla
     `zona_prorrateo_valor_relativo`; #73 -> `sin_incidencia:true` + `pool_vacio`. El bloque G
     verifica la coherencia de TODOS los fixtures -- y al escribirlo cazo un tercer fixture roto:
     F9 tenia el gasto #42 en `incidencias` Y en `gastos_sin_incidencia` a la vez.

  9. DOC -- 10 comandos operativos. AUTO = prueba automatizada y REPRODUCIBLE, no "corre en CI"
     (no hay CI: alguien tiene que correr los comandos).

------------------------------------------------------------------------------------------------
COMO SE APLICA

  1. Copiar los archivos del harness (qa/, vite.qa.config.ts, tsconfig.qa.json) y el `.gitignore`.
  2. Copiar `package.json` (agrega el script `qa:mutacion`).
     `package-lock.json` NO CAMBIA: no hay dependencias nuevas.
  3. python SB_UI_6_FIX2_patcher.py    <- verifica TODO y aborta si algo no cuadra
  4. npm ci

------------------------------------------------------------------------------------------------
GATES

  G1  SHA-256 de los 14 archivos de `src/` cerrados. SB-UI-6-FIX2 no los toca.
  G2  SHA-256 de los 20 archivos del harness (incluido el `.gitignore`).
  G3  SHA-256 de `package.json`. Acepta DOS estados -> IDEMPOTENTE:
        PRE  (SB-UI-6-FIX aplicado, sin `qa:mutacion`) -> avisa que falta copiar;
        POST (SB-UI-6-FIX2 aplicado)                   -> todo listo.
      `package-lock.json` tiene que quedar como esta: si cambio, algo se instalo de mas.
  G4  `.gitignore` ignora `dist-qa` y `qa/screenshots/`. Sin esto, correr la suite deja el arbol
      sucio y un `git add .` distraido se lleva un build entero al repo.

Hashes sobre contenido NORMALIZADO A LF (se descarta el CR).
------------------------------------------------------------------------------------------------
"""

import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

SHA_PKG_PRE = '2bb6f390fd6593f13462c7707bc5839fb6d63335dfd943cceba7b63dd1d759c4'
SHA_PKG_POST = 'e5740e643d570b01789bedd6aedcb9840dbb4f0b6a14ac0c960c438c714661fc'
SHA_LOCK = '5a1290f3f47baf9b1c7e1511e69c5bb4bbfdb1cdb3c04c9c1a922999e69a0ff5'   # no cambia: sin dependencias nuevas

SHA_HARNESS = {
    'qa/fixtures.ts': 'f1662ef8905e670895b077448fdceced4d030677b4bffffd36775f5fd9af7917',
    'qa/probes.tsx': 'd1b64505440417bb6b4a52ffc6b2de294d67f537f8a31d97061a12ac058e08ac',
    'qa/higiene.mjs': '1f02732e4528026a466ea756190dc44cf824d23b0cb9ef30b1b1f386be4ab092',
    'qa/run-probes.mjs': 'ebe3165c87485144e17012e766dc32a61732410ea285c267a92a1e83a68629bb',
    'qa/responsive.mjs': '793cf1818e49227af64eb12267a543e631708b7da800d2d92e4f26db927f697c',
    'qa/estructural.mjs': '30f85263bc1bb46f557f96e169c92a89b6f049d311b0b2c955f914f83b696f93',
    'qa/mutacion.mjs': '1b5586f6868439496b497ea93d3dabb6c9c8a5f6f268c83c787416eee10d9407',
    'qa/store.tsx': '62e450d7a96bc3ffd0ad91e95c35e67484398a5c37b14dfbdb5982a1df97187c',
    'qa/stubs/rutas.tsx': '431ce15215af3ff893f0e6515012b3a66b38162fab162e3396ff78c56db4dd1c',
    'qa/stubs/red.ts': '3876971a7b4944730d3e849eccee63ecc071397615b5bd7b19c3b43c063aa1b4',
    'qa/HostReqId.tsx': '0df6c8b4226c545d7264dd526b5c7577812b900f9463586638c714eae0ab0465',
    'qa/BarraQA.tsx': 'd65ca57bbef2558dd6825a4bf0b617e0775ce589af5ca6062645228c2b9cdf18',
    'qa/main.tsx': '7e2b297e31d5206ffed777f7e806e7f9210a0ed2eaf89d146c34722a478c6f19',
    'qa/index.html': 'c7f565c72ed3da164591e2f45822d46434d83d6f0447d124d06a48253cfa4843',
    'qa/RUNSHEET.md': '4204c0b97d8f369263fb176faedd3b9b0ae7941d77abae659d06ce56165663ae',
    'qa/SMOKE_MANUAL.md': '3d6e0fbb13388c0ad3f4cd72a942eddb5581c5acfb1bc8713e9e43d3421f15fe',
    'qa/COBERTURA.md': '41db7f3fd757f7f71ecb57e1fffdaa2eb76a756e9fdcd513320238140fa1ca59',
    'vite.qa.config.ts': 'c9bf82ff672f964c1e6749e51df155dcd6270a18412e5aef28db3bc29db1e853',
    'tsconfig.qa.json': '074eae34aa606912853eccf168fb12e346fb88e182078ed354875a8e32ed9d09',
    '.gitignore': '11638f6b35eb45060e035a874618ccb17a9067adc48915daa08c88e787a337f5',
}

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
    'src/hooks/useAction.ts':
        '0035ae7dbcaf44b2d4eebc49fcb676a1371743aa21c6f56562af672d46c9f378',
    'src/lib/callPortal.ts':
        '06a1c19423c872b5867d9ed4a3f9e1aa09940843c4bd351a8dc9f0a8d21712ab',
}

IGNORAR = (('dist-qa', 'npm run qa:build'), ('qa/screenshots/', 'npm run qa:responsive'))


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
            print('  DRIFT   [%s] %-30s NO EXISTE' % (marca, rel))
            continue
        real = sha_lf(txt)
        if real != esperado:
            drift.append('%s :: esperado %s / real %s' % (rel, esperado[:16], real[:16]))
            print('  DRIFT   [%s] %-30s esperado %s / real %s' % (marca, rel, esperado[:16], real[:16]))
        else:
            print('  ok      [%s] %-30s %s' % (marca, rel, real[:16]))
    return drift


def main():
    drift = gate('G1 -- src/ CERRADO (SB-UI-6-FIX2 no lo toca):', SHA_CERRADOS, 'cerrado')
    drift += gate('G2 -- HARNESS (%d archivos):' % len(SHA_HARNESS), SHA_HARNESS, 'harness')

    # --- G4: los artefactos GENERADOS no pueden ensuciar el arbol ------------------------------
    print('\nG4 -- .gitignore (los artefactos de la suite son SALIDA, no fuente):')
    gi = leer('.gitignore')
    if gi is None:
        drift.append('.gitignore :: NO EXISTE')
        print('  DRIFT   [gitignore] NO EXISTE')
    else:
        lineas = [l.strip() for l in gi.splitlines()]
        for patron, genera in IGNORAR:
            if patron in lineas:
                print('  ok      [gitignore] %-18s (lo genera %s)' % (patron, genera))
            else:
                drift.append('.gitignore :: falta "%s"' % patron)
                print('  DRIFT   [gitignore] FALTA "%s" -- lo genera %s' % (patron, genera))

    # --- G3: manifests -------------------------------------------------------------------------
    print('\nG3 -- MANIFESTS:')
    pkg = leer('package.json')
    lock = leer('package-lock.json')
    estado_pkg = None
    if pkg is None:
        drift.append('package.json :: NO EXISTE')
        print('  DRIFT   [manifest] package.json       NO EXISTE')
    else:
        s = sha_lf(pkg)
        if s == SHA_PKG_POST:
            estado_pkg = 'POST'
            print('  ok      [ ya ok  ] package.json       %s  (POST)' % s[:16])
        elif s == SHA_PKG_PRE:
            estado_pkg = 'PRE'
            print('  FALTA   [ copiar ] package.json       %s  (PRE -> copia el package.json del artefacto)' % s[:16])
        else:
            drift.append('package.json :: %s no coincide ni con PRE ni con POST' % s[:16])
            print('  DRIFT   [manifest] package.json       %s  (ni PRE ni POST)' % s[:16])

    if lock is None:
        drift.append('package-lock.json :: NO EXISTE')
        print('  DRIFT   [manifest] package-lock.json  NO EXISTE')
    elif sha_lf(lock) != SHA_LOCK:
        drift.append('package-lock.json :: cambio; SB-UI-6-FIX2 no agrega dependencias')
        print('  DRIFT   [manifest] package-lock.json  %s  (CAMBIO -- SB-UI-6-FIX2 no agrega deps)' % sha_lf(lock)[:16])
    else:
        print('  ok      [ ya ok  ] package-lock.json  %s  (sin cambios, correcto)' % sha_lf(lock)[:16])

    assert not drift, '\n\nDRIFT DETECTADO -- NO se escribio NADA.\n  ' + '\n  '.join(drift)

    if estado_pkg == 'PRE':
        print('\nFALTA COPIAR package.json (le falta el script `qa:mutacion`).')
        print('  Copialo del artefacto, volve a correr esto, y despues: npm ci')
        return 1

    print('\nTODO EN POST. SB-UI-6-FIX2 aplicado.')
    print('  src/ NO se modifico.')
    print('\n  Los 10 comandos:')
    print('    npm ci')
    print('    npm run build ; npm run typecheck ; npm run typecheck:qa')
    print('    npm run qa:probes ; npm run qa:higiene ; npm run qa:build')
    print('    npm run qa:mutacion                     (autonomo: server propio en el 5199)')
    print('    npm run qa                              (y en otra consola:)')
    print('    npm run qa:estructural ; npm run qa:responsive')
    print('\n  Despues de la suite, `git status --short` NO debe mostrar builds ni screenshots.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
