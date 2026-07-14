#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SB-UI-6 -- Harness y QA integral.

SB-UI-6 NO MUEVE UN SOLO BYTE DE `src/`. Agrega el harness (`qa/`), dos configs propias y seis
scripts a `package.json`. El unico archivo de produccion que se toca es `package.json`, y solo en
la seccion `scripts`.

Archivos NUEVOS que hay que copiar ANTES de correr esto:
  qa/fixtures.ts          qa/probes.tsx        qa/higiene.mjs      qa/responsive.mjs
  qa/store.tsx            qa/stubs/rutas.tsx   qa/BarraQA.tsx      qa/main.tsx
  qa/index.html           qa/RUNSHEET.md       qa/SMOKE_MANUAL.md
  vite.qa.config.ts       tsconfig.qa.json

------------------------------------------------------------------------------------------------
GATES -- todos ANTES de escribir un solo byte (all-or-nothing)

  G1  SHA-256 de los 12 archivos de `src/` que quedaron cerrados en SB-UI-5. Si alguno se movio,
      aborta: SB-UI-6 no tiene por que tocarlos, asi que un drift aca significa que el arbol no es
      el que Franco aprobo.
  G2  SHA-256 de los 13 archivos nuevos. Si se copio una version equivocada, aborta ANTES de tocar
      `package.json`.
  G3  SHA-256 de `package.json`. Acepta DOS estados -> IDEMPOTENTE:
        PRE  (sin los scripts de qa) -> los agrega;
        POST (ya aplicado)           -> no hace nada y sale.
  G4  Los 6 scripts se agregan solo si NO existen (idempotencia fina), y el resultado se verifica
      contra el SHA-256 POST esperado antes de escribir.

Hashes sobre contenido NORMALIZADO A LF (se descarta '\\r').
------------------------------------------------------------------------------------------------
"""

import hashlib
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

PKG = 'package.json'
SHA_PKG_PRE = '93535b948d751ff1bf39508bd172dce560f7a588bff09d4f542f0708b9ae2d95'
SHA_PKG_POST = 'f8855e0063f745ccf315b3b108718bb308e59a4503d546cb8ab920e611cd7076'

SCRIPTS = {
    'qa': 'vite --config vite.qa.config.ts',
    'qa:build': 'vite build --config vite.qa.config.ts --outDir ../dist-qa',
    'qa:probes': (
        'esbuild qa/probes.tsx --bundle --platform=node --format=cjs --jsx=automatic '
        '--outfile=node_modules/.qa/probes.cjs --log-level=error --external:react '
        '--external:react-dom --external:node:* && node node_modules/.qa/probes.cjs'
    ),
    'qa:responsive': 'node qa/responsive.mjs',
    'qa:higiene': 'node qa/higiene.mjs',
    'typecheck:qa': 'tsc --noEmit -p tsconfig.qa.json',
}

SHA_NUEVOS = {
    'qa/fixtures.ts': '1f674441ac15256fadc91fde88c690017644ccd0d58234149c843490ccbe0440',
    'qa/probes.tsx': 'e58a4c9e2d9d3dc9e90c898b8bca97994cdbd477b319147b87f35a1bd54542e1',
    'qa/higiene.mjs': 'ae56c21f977342b45df583870d25b8b37912540497ba3ce6b4904b36f8c7c683',
    'qa/responsive.mjs': '08151567bf7a8e9f10b034c4a0b734ce3df97e897b7b9349f88ec6f63ca87426',
    'qa/store.tsx': 'c128fcfed096e30de95098da2362e4b4fbe660a0eefe768325efa20b690af23f',
    'qa/stubs/rutas.tsx': '6e3269174c823d825310422d108d7d7e1a8ee6d5e0c23deccfd71260853fc653',
    'qa/BarraQA.tsx': 'e12b1e990702d5e56c76ca69c1be1d6885258bb4c494b2a894e5e1fffa0b4421',
    'qa/main.tsx': '3f4e358f59f8f2cca74d3fadba70600a9ca92398e55de3d32a3918e8f1a8ca94',
    'qa/index.html': 'c7f565c72ed3da164591e2f45822d46434d83d6f0447d124d06a48253cfa4843',
    'qa/RUNSHEET.md': '71b59194f8e181aa9d3c90c09df8c891ed226686a01c4a7d8c3019e993552ff2',
    'qa/SMOKE_MANUAL.md': '489558d899ab83840c19b1026754d2a104cd598c0b0a0f8b98fbba89882799e6',
    'vite.qa.config.ts': 'c9bf82ff672f964c1e6749e51df155dcd6270a18412e5aef28db3bc29db1e853',
    'tsconfig.qa.json': '074eae34aa606912853eccf168fb12e346fb88e182078ed354875a8e32ed9d09',
}

# `src/` NO se toca en SB-UI-6. Estos son los hashes aprobados al cierre de SB-UI-5.
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
            print('  DRIFT   [%s] %-34s NO EXISTE' % (marca, rel))
            continue
        real = sha_lf(txt)
        if real != esperado:
            drift.append('%s :: esperado %s / real %s' % (rel, esperado[:16], real[:16]))
            print('  DRIFT   [%s] %-34s esperado %s / real %s'
                  % (marca, rel, esperado[:16], real[:16]))
        else:
            print('  ok      [%s] %-34s %s' % (marca, rel, real[:16]))
    return drift


def main():
    drift = gate('G1 -- src/ CERRADO (SB-UI-6 no lo toca):', SHA_CERRADOS, 'cerrado')
    drift += gate('G2 -- HARNESS (13 archivos nuevos):', SHA_NUEVOS, ' nuevo ')

    print('\nG3 -- package.json (idempotente):')
    src = leer(PKG)
    aplicar = False
    if src is None:
        drift.append('%s :: NO EXISTE' % PKG)
        print('  DRIFT   [MODIFICA] %-34s NO EXISTE' % PKG)
    else:
        s = sha_lf(src)
        if s == SHA_PKG_PRE:
            aplicar = True
            print('  ok      [MODIFICA] %-34s %s  (PRE -> se agregan los scripts)' % (PKG, s[:16]))
        elif s == SHA_PKG_POST:
            print('  ok      [ ya ok  ] %-34s %s  (POST -> SB-UI-6 ya aplicado)' % (PKG, s[:16]))
        else:
            drift.append('%s :: hash %s no coincide ni con PRE ni con POST' % (PKG, s[:16]))
            print('  DRIFT   [MODIFICA] %-34s %s  (ni PRE ni POST)' % (PKG, s[:16]))

    assert not drift, (
        '\n\nDRIFT DETECTADO -- NO se escribio NADA. package.json queda intacto.\n  '
        + '\n  '.join(drift)
    )

    if not aplicar:
        print('\nNADA QUE HACER: package.json ya tiene los scripts de qa, y los 13 archivos del '
              'harness son los correctos.')
        return 0

    # G4 -- agregar los scripts que falten, sin pisar nada existente
    d = json.loads(src)
    agregados = []
    for k, v in SCRIPTS.items():
        if k in d.get('scripts', {}):
            assert d['scripts'][k] == v, 'EL SCRIPT "%s" YA EXISTE CON OTRO VALOR -- no se pisa' % k
        else:
            d.setdefault('scripts', {})[k] = v
            agregados.append(k)

    out = json.dumps(d, indent=2, ensure_ascii=False) + '\n'

    assert '\r' not in out, 'CRLF DETECTADO en %s' % PKG
    assert sha_lf(out) == SHA_PKG_POST, (
        'EL RESULTADO NO COINCIDE CON EL SHA-256 POST ESPERADO -- NO se escribio nada. '
        'Esperado %s / obtenido %s' % (SHA_PKG_POST[:16], sha_lf(out)[:16])
    )

    with io.open(os.path.join(HERE, PKG), 'w', encoding='utf-8', newline='') as fh:
        fh.write(out)

    print('\nOK: %d script(s) agregado(s) a package.json' % len(agregados))
    for k in agregados:
        print('  [OK] %s' % k)
    print('  [OK] resultado verificado contra el SHA-256 POST esperado.')
    print('\nsrc/ NO se modifico: SB-UI-6 no toca el codigo de produccion.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
