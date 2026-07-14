// =============================================================================================
// SB-UI-6-FIX2 -- MUTATION GATE sobre `useAction`.
//
// Una prueba que pasa no dice nada si tambien pasaria con el codigo roto. Este script rompe
// `useAction` A PROPOSITO y comprueba que la suite lo CAZA. Si la suite pasa igual con el codigo
// mutado, la prueba es decorativa y hay que decirlo.
//
// NO TOCA `src/`, ni escribe un solo archivo. El mutante se DERIVA del original y se inyecta EN
// MEMORIA con un plugin de Vite. Antes de derivar, se verifica el SHA-256 del original: si
// `useAction.ts` cambio, el mutante ya no representa lo que se cree y el script aborta.
//
// Las dos guardas de `useAction` son:
//     if (!activo || myId !== reqId.current) return;
//      ^^^^^^^^^^    ^^^^^^^^^^^^^^^^^^^^^^^
//      cleanup       reqId
//
// Se prueban las TRES mutaciones, porque la pregunta interesante no es "el test pasa?", sino
// "cual de las dos guardas es la que efectivamente protege?":
//
//   sin-reqId    -> se borra `myId !== reqId.current`, queda `!activo`
//   sin-activo   -> se borra `!activo`, queda `myId !== reqId.current`
//   sin-ninguna  -> se borran las dos: el hook queda sin ninguna proteccion
//
// Es AUTONOMO: levanta su propio server de Vite en el 5199. No necesita `npm run qa`.
//
//   npm run qa:mutacion
// =============================================================================================

import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ORIGINAL = path.join(RAIZ, 'src', 'hooks', 'useAction.ts');

// SHA-256 (LF) del `useAction.ts` aprobado. Si no coincide, el mutante no es lo que se cree.
const SHA_ESPERADO = '0035ae7dbcaf44b2d4eebc49fcb676a1371743aa21c6f56562af672d46c9f378';

let chromium, createServer;
try {
  ({ chromium } = await import('playwright'));
  ({ createServer } = await import('vite'));
} catch {
  console.error('\n  Falta playwright o vite.  npm ci && npx playwright install chromium\n');
  process.exit(2);
}
const lanzar = () =>
  chromium.launch({
    args: ['--no-sandbox'],
    ...(process.env.QA_CHROME ? { executablePath: process.env.QA_CHROME } : {}),
  });

const PUERTO = 5199; // NO 5173: este script levanta su propio server y no pelea con `npm run qa`

/**
 * Levanta un harness efimero. Si `mutado` es true, `useAction` se resuelve al mutante que este
 * escrito en `node_modules/.qa/useAction.mutado.ts`. `src/` NO se toca nunca.
 */
async function servidor(codigoMutado) {
  const s = await createServer({
    configFile: path.join(RAIZ, 'vite.qa.config.ts'),
    root: path.join(RAIZ, 'qa'),
    logLevel: 'silent',
    server: { port: PUERTO, strictPort: true },
    plugins: codigoMutado
      ? [
          {
            // El mutante vive EN MEMORIA. No se escribe ningun archivo: `src/hooks/useAction.ts`
            // ni se toca, no queda nada que limpiar, y `git status --short` sigue limpio.
            name: 'qa-mutante-useAction',
            enforce: 'pre',
            load(id) {
              return id.replace(/\\/g, '/').endsWith('/src/hooks/useAction.ts') ? codigoMutado : null;
            },
          },
        ]
      : [],
  });
  await s.listen();
  return s;
}

// ---------------------------------------------------------------------------------------------
// Derivacion de los mutantes -- desde el ORIGINAL, nunca desde una copia guardada
// ---------------------------------------------------------------------------------------------
const src = readFileSync(ORIGINAL, 'utf8');
const sha = createHash('sha256').update(src.replace(/\r/g, ''), 'utf8').digest('hex');

console.log('\n' + '='.repeat(92));
console.log('MUTATION GATE -- useAction');
console.log('='.repeat(92));
console.log(`\n  original: src/hooks/useAction.ts`);
console.log(`  sha-256:  ${sha}`);

if (sha !== SHA_ESPERADO) {
  console.error(
    `\n  ABORTA: el SHA no coincide con el aprobado.\n` +
      `    esperado ${SHA_ESPERADO}\n` +
      `    real     ${sha}\n` +
      `  El mutante se deriva del original: si el original cambio, esta prueba ya no significa\n` +
      `  lo que dice. Revisa el archivo o actualiza SHA_ESPERADO a conciencia.\n`
  );
  process.exit(2);
}

const GUARDA = 'if (!activo || myId !== reqId.current) return;';
const apariciones = src.split(GUARDA).length - 1;
if (apariciones !== 2) {
  console.error(`\n  ABORTA: se esperaban 2 guardas, se encontraron ${apariciones}.\n`);
  process.exit(2);
}
console.log(`  guardas encontradas: ${apariciones}  ->  "${GUARDA}"`);

const MUTANTES = {
  'sin-reqId': ['if (!activo) return;', 'se borra `myId !== reqId.current`; queda el cleanup'],
  'sin-activo': ['if (myId !== reqId.current) return;', 'se borra `!activo`; queda el reqId'],
  'sin-ninguna': ['if (false) return;', 'se borran las DOS: el hook queda sin proteccion'],
};

// ---------------------------------------------------------------------------------------------
// El test: UNA instancia, DOS corridas del efecto, fixtures DISTINGUIBLES
// ---------------------------------------------------------------------------------------------
// request 1 -> F2  (E2, detalle_motivo: 'foto_pre_extension')   600 ms   <- VIEJA, llega TARDE
//   refetch() en pleno vuelo
// request 2 -> F1  (E1, detalle_motivo: null)                    50 ms   <- NUEVA, llega ANTES
//
// Si la corrida vieja no se descarta, al final se ve 'foto_pre_extension' (la vieja piso a la
// nueva). Si se descarta, se ve 'null'.
async function correrTest(codigoMutado) {
  const srv = await servidor(codigoMutado);
  const b = await lanzar();
  const p = await b.newPage({ viewport: { width: 900, height: 600 } });
  await p.addInitScript(() => {
    window.__QA_PRECONF__ = {
      colaA30: [
        { fixture: 'F2', latencia: 600, falla: false },
        { fixture: 'F1', latencia: 50, falla: false },
      ],
    };
  });
  await p.goto(`http://localhost:${PUERTO}/?host=requid`);
  await p.waitForSelector('[data-qa-host="requid"]');

  // A los 150ms la request 1 (600ms) sigue en vuelo. Se dispara el refetch -> request 2.
  await p.waitForTimeout(150);
  await p.evaluate(() => window.__QA_REFETCH__?.());

  // 1200ms: la request 2 (50ms) ya volvio, y la request 1 (600ms) TAMBIEN.
  await p.waitForTimeout(1200);

  const r = await p.evaluate(() => ({
    motivo: document.querySelector('[data-qa="motivo"]')?.textContent ?? '?',
    peticiones: window.__QA_RED__.llamadas.map((l) => l.sirvio.fixture),
  }));
  await b.close();
  await srv.close();
  return r;
}

const resultados = [];

// ---- 1. ORIGINAL: el test tiene que PASAR ---------------------------------------------------
console.log('\n  ORIGINAL (sin mutar)');
{
  const r = await correrTest(null);
  const pasa = r.motivo === 'null';
  console.log(`    peticiones servidas: ${JSON.stringify(r.peticiones)}`);
  console.log(`    detalle_motivo final: "${r.motivo}"  (se espera "null", de F1)`);
  console.log(`    ${pasa ? 'ok    el test PASA con el codigo bueno' : 'FALLA el test no pasa ni con el codigo bueno -- el test esta roto'}`);
  resultados.push({ nombre: 'ORIGINAL', debeFallar: false, fallo: !pasa, motivo: r.motivo, n: r.peticiones.length });
}

// ---- 2. MUTANTES: el test tiene que FALLAR --------------------------------------------------
for (const [nombre, [reemplazo, desc]] of Object.entries(MUTANTES)) {
  console.log(`\n  MUTANTE "${nombre}" -- ${desc}`);
  const r = await correrTest(src.split(GUARDA).join(reemplazo));
  const cazado = r.motivo !== 'null'; // el test CAZA la mutacion si el resultado cambia
  console.log(`    peticiones servidas: ${JSON.stringify(r.peticiones)}`);
  console.log(`    detalle_motivo final: "${r.motivo}"`);
  console.log(
    `    ${cazado ? 'ok    CAZADO: con esta mutacion el test FALLA (la guarda sirve)' : '·SOBREVIVE: el test pasa igual -> esta guarda NO es la que protege'}`
  );
  resultados.push({ nombre, debeFallar: true, fallo: !cazado, motivo: r.motivo, n: r.peticiones.length });
}

// ---------------------------------------------------------------------------------------------
console.log('\n' + '-'.repeat(92));
console.log('  variante        detalle_motivo   veredicto');
console.log('  ' + '-'.repeat(60));
for (const r of resultados) {
  const v = r.nombre === 'ORIGINAL' ? (r.fallo ? 'TEST ROTO' : 'pasa (correcto)') : r.fallo ? 'SOBREVIVE' : 'cazado';
  console.log(`  ${r.nombre.padEnd(15)} ${String(r.motivo).padEnd(16)} ${v}`);
}

const original = resultados.find((r) => r.nombre === 'ORIGINAL');
const sinNinguna = resultados.find((r) => r.nombre === 'sin-ninguna');

// El gate DURO: el test tiene que pasar con el codigo bueno, y tiene que cazar al mutante que se
// queda SIN NINGUNA proteccion. Si `sin-ninguna` sobrevive, el test no prueba nada.
const duro = !original.fallo && !sinNinguna.fallo;
console.log(
  '\n  ' +
    (duro
      ? 'MUTATION GATE OK -- el test pasa con el codigo bueno y CAZA al hook sin proteccion.'
      : 'MUTATION GATE FALLA -- el test no distingue el codigo bueno del roto.')
);
process.exit(duro ? 0 : 1);
