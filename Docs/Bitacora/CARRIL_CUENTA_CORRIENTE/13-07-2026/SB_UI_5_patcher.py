#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SB-UI-5 -- Responsive e integracion visual de A30/A31.

DOS cambios, los dos medidos en un browser real (Chromium via Playwright, viewports 375/768/1280):

  1. `min-w-0` en el <main> de AppShell.tsx.
     El <main> es un flex item con `min-width: auto`, que resuelve al min-content de su contenido.
     Con las tablas de A30 adentro, el <main> se estiraba a 1072px y ARRASTRABA TODA LA PAGINA:
       375px  -> la pagina medía 1072px  (+697px de desborde)
       768px  -> 1328px                  (+560px)
      1280px  -> 1328px                  (+48px)  <- desbordaba HASTA EN DESKTOP
     El `overflow-x-auto` que DataTable ya tiene nunca llegaba a activarse (1 de 10 tablas
     scrolleaba). Con `min-w-0`: cero desborde en los 3 viewports y 9 de 10 tablas scrollean
     dentro de su contenedor, que es lo que DataTable promete en su docstring.

     NOTA: `.min-w-0` NO existia en el CSS compilado, porque Tailwind JIT solo emite las clases que
     encuentra en el codigo fuente y NINGUN archivo la usaba. Este edit la introduce y el build la
     emite (verificado: `.min-w-0{min-width:0px}` esta en el CSS).

  2. Consolidacion de `Nat` / `NATURALEZA` en `screens/historico/naturaleza.tsx`.
     Vivian DUPLICADOS en ContenidoAcumulados.tsx (SB-UI-3) y ContenidoFoto.tsx (SB-UI-4).
     REFACTOR PURO: el markup renderizado es byte a byte identico (mismo SHA-256 del HTML, para
     A30 y A31, sobre los mismos fixtures). No cambia ninguna regla de render.

Archivos NUEVOS / SOBRESCRITOS que hay que copiar ANTES de correr esto:
  src/screens/historico/naturaleza.tsx           (nuevo)
  src/screens/historico/ContenidoFoto.tsx        (sobrescribe el de SB-UI-4-FIX)
  src/screens/historico/ContenidoAcumulados.tsx  (sobrescribe el de SB-UI-3)

NO toca: HistoricoVista, HistoricoCuentaCorriente, planSelector, estadoFoto, foto.ts, acumulados.ts,
Tarjeta, DataTable, contratos, periodo, actionRegistry, rutas. Ni backend, gateway, wrappers, OPS.

------------------------------------------------------------------------------------------------
GATES -- todos ANTES de escribir un solo byte (all-or-nothing)

  G1  SHA-256 de los 12 archivos CERRADOS que SB-UI-5 no toca.
  G2  SHA-256 de los 3 archivos nuevos/sobrescritos. Si se copio una version equivocada, aborta
      ANTES de tocar AppShell.tsx, que queda intacto.
  G3  SHA-256 de AppShell.tsx. Acepta DOS estados -> IDEMPOTENTE:
        PRE  (sin min-w-0)  -> aplica el edit;
        POST (ya aplicado)  -> no hace nada y sale.
  G4  Ancla unica (count == 1) + el resultado se verifica contra el SHA-256 POST esperado antes de
      escribir.

Hashes sobre contenido NORMALIZADO A LF (se descarta '\\r').
------------------------------------------------------------------------------------------------
"""

import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, 'src')

A = 'app/AppShell.tsx'

SHA_APPSHELL_PRE = '887adb1d82509105ce7f4fb2848c4aca3e29a7682d35e2087ab6a77f2c49e61e'
SHA_APPSHELL_POST = '08ebbbd6289ed20edf67d7708053d13b5f563a3eee54822e0d6302f22438a0ba'

SHA_NUEVOS = {
    'screens/historico/naturaleza.tsx':
        '28ff85c1dd4dbd34db4c676377c05085b4b11e985cca0d189d8172e3a7b36919',
    'screens/historico/ContenidoFoto.tsx':
        'c87d9aaa8e1c6d25a049553c86263b2837b12e925540d213b545c8c06269088e',
    'screens/historico/ContenidoAcumulados.tsx':
        '521cc947fd8a1528dcff42313dd4d36586ac84a10091335066997c38cefdcb3f',
}

SHA_CERRADOS = {
    'screens/historico/HistoricoVista.tsx':
        'c0293a454dc695d0913b6bee366970a103e74f36572332f594d68862cc475237',
    'screens/historico/foto.ts':
        'a61cf1a8838432eb76bae8fecf0190e456f61d5f031815fec758b22fa9262957',
    'screens/historico/acumulados.ts':
        '2e39b462c29015cc0a3cdd2855681f6043cb6bb39b85d6a6a04b32c5ae231df3',
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
        'label': 'min-w-0 en el <main>',
        'anchor': '<main className="flex-1 p-6">',
        'replacement': '<main className="min-w-0 flex-1 p-6">',
    },
]


def sha_lf(t):
    return hashlib.sha256(t.replace('\r', '').encode('utf-8')).hexdigest()


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
    drift = gate('G1 -- CERRADOS (SB-UI-5 no los toca):', SHA_CERRADOS, 'cerrado')
    drift += gate('G2 -- NUEVOS / SOBRESCRITOS (copiarlos antes de correr esto):',
                  SHA_NUEVOS, ' nuevo ')

    print('\nG3 -- AppShell.tsx (idempotente):')
    src = leer(A)
    aplicar = False
    if src is None:
        drift.append('%s :: NO EXISTE' % A)
        print('  DRIFT   [MODIFICA] %-44s NO EXISTE' % A)
    else:
        s = sha_lf(src)
        if s == SHA_APPSHELL_PRE:
            aplicar = True
            print('  ok      [MODIFICA] %-44s %s  (PRE -> se aplica el edit)' % (A, s[:16]))
        elif s == SHA_APPSHELL_POST:
            print('  ok      [ ya ok  ] %-44s %s  (POST -> SB-UI-5 ya aplicado)' % (A, s[:16]))
        else:
            drift.append('%s :: hash %s no coincide ni con PRE ni con POST' % (A, s[:16]))
            print('  DRIFT   [MODIFICA] %-44s %s  (ni PRE ni POST)' % (A, s[:16]))

    assert not drift, (
        '\n\nDRIFT DETECTADO -- NO se escribio NADA. AppShell.tsx queda intacto.\n  '
        + '\n  '.join(drift)
    )

    if not aplicar:
        print('\nNADA QUE HACER: AppShell.tsx ya tiene SB-UI-5 aplicado, y los tres archivos '
              'nuevos son los correctos.')
        return 0

    out = src
    for e in EDITS:
        n = out.count(e['anchor'])
        assert n == 1, 'ANCLA NO UNICA (%d) en %s :: %s' % (n, A, e['label'])
        out = out.replace(e['anchor'], e['replacement'], 1)

    assert '\r' not in out, 'CRLF DETECTADO en %s' % A
    assert sha_lf(out) == SHA_APPSHELL_POST, (
        'EL RESULTADO NO COINCIDE CON EL SHA-256 POST ESPERADO -- NO se escribio nada. '
        'Esperado %s / obtenido %s' % (SHA_APPSHELL_POST[:16], sha_lf(out)[:16])
    )

    with io.open(os.path.join(BASE, A), 'w', encoding='utf-8', newline='') as fh:
        fh.write(out)

    print('\nOK: %d edit sobre 1 archivo' % len(EDITS))
    for e in EDITS:
        print('  [OK] %-38s %s' % (A, e['label']))
    print('  [OK] resultado verificado contra el SHA-256 POST esperado.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
