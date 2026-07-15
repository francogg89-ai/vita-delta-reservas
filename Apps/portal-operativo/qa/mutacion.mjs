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

// La matriz esperada, variante por variante. El gate exige que se cumpla ENTERA -- no alcanza con
// "original pasa y sin-ninguna falla". Cada variante tiene un `detalle_motivo` esperado:
//   original    -> null                (la nueva gana)
//   sin-reqId    -> null                (el cleanup solo alcanza)
//   sin-activo   -> null                (el reqId solo alcanza)
//   sin-ninguna  -> foto_pre_extension  (sin ninguna guarda, la vieja pisa)
const ESPERADO = {
  ORIGINAL: 'null',
  'sin-reqId': 'null',
  'sin-activo': 'null',
  'sin-ninguna': 'foto_pre_extension',
};

// ---- 1. ORIGINAL: el test tiene que PASAR ---------------------------------------------------
console.log('\n  ORIGINAL (sin mutar)');
{
  const r = await correrTest(null);
  const pasa = r.motivo === 'null';
  console.log(`    peticiones servidas: ${JSON.stringify(r.peticiones)}`);
  console.log(`    detalle_motivo final: "${r.motivo}"  (se espera "null", de F1)`);
  console.log(`    ${pasa ? 'ok    el test PASA con el codigo bueno' : 'FALLA el test no pasa ni con el codigo bueno -- el test esta roto'}`);
  resultados.push({ nombre: 'ORIGINAL', motivo: r.motivo, peticiones: r.peticiones });
}

// ---- 2. MUTANTES ----------------------------------------------------------------------------
for (const [nombre, [reemplazo, desc]] of Object.entries(MUTANTES)) {
  console.log(`\n  MUTANTE "${nombre}" -- ${desc}`);
  const r = await correrTest(src.split(GUARDA).join(reemplazo));
  const cazado = r.motivo !== 'null'; // el test CAZA la mutacion si el resultado cambia
  console.log(`    peticiones servidas: ${JSON.stringify(r.peticiones)}`);
  console.log(`    detalle_motivo final: "${r.motivo}"`);
  console.log(
    `    ${cazado ? 'ok    CAZADO: con esta mutacion el test FALLA (la guarda sirve)' : '·SOBREVIVE: el test pasa igual -> esta guarda NO es la que protege'}`
  );
  resultados.push({ nombre, motivo: r.motivo, peticiones: r.peticiones });
}

// ---------------------------------------------------------------------------------------------
console.log('\n' + '-'.repeat(92));
console.log('  variante        detalle_motivo      servidas         veredicto');
console.log('  ' + '-'.repeat(74));
for (const r of resultados) {
  const motivoOk = r.motivo === ESPERADO[r.nombre];
  const servidasOk = JSON.stringify(r.peticiones) === JSON.stringify(['F2', 'F1']);
  const v = motivoOk && servidasOk ? 'OK' : 'NO CUMPLE';
  console.log(
    `  ${r.nombre.padEnd(15)} ${String(r.motivo).padEnd(19)} ${JSON.stringify(r.peticiones).padEnd(16)} ${v}`
  );
}

// GATE DURO. No alcanza con "original pasa y sin-ninguna falla": se exige la matriz ENTERA.
//   (a) cada variante dio EXACTAMENTE el detalle_motivo esperado (incluye que sin-reqId y sin-activo
//       SOBREVIVEN -> confirma que las guardas son redundantes; si una empezara a fallar, el modelo
//       de por que la prueba pasa cambio y hay que revisarlo);
//   (b) TODAS sirvieron exactamente ["F2","F1"] -> el escenario fue el mismo en las cuatro corridas
//       (una instancia, dos peticiones, en ese orden). Si alguna sirvio otra cosa, el StrictMode se
//       colo, o el host monto dos instancias, y el resultado no significa lo que se cree.
const matrizOk = resultados.every((r) => r.motivo === ESPERADO[r.nombre]);
const escenarioOk = resultados.every((r) => JSON.stringify(r.peticiones) === JSON.stringify(['F2', 'F1']));
const duro = matrizOk && escenarioOk;

if (!matrizOk) {
  const desvios = resultados
    .filter((r) => r.motivo !== ESPERADO[r.nombre])
    .map((r) => `${r.nombre}: esperaba "${ESPERADO[r.nombre]}", dio "${r.motivo}"`);
  console.log(`\n  matriz INCOMPLETA: ${desvios.join(' | ')}`);
}
if (!escenarioOk) {
  const malos = resultados
    .filter((r) => JSON.stringify(r.peticiones) !== JSON.stringify(['F2', 'F1']))
    .map((r) => `${r.nombre}: ${JSON.stringify(r.peticiones)}`);
  console.log(`\n  escenario CONTAMINADO (alguna variante no sirvio ["F2","F1"]): ${malos.join(' | ')}`);
}

console.log(
  '\n  ' +
    (duro
      ? 'MUTATION GATE OK -- matriz completa: original/reqId/activo dan "null", sin-ambas pisa; las 4 sirvieron ["F2","F1"].'
      : 'MUTATION GATE FALLA -- la matriz no se cumple entera.')
);
process.exit(duro ? 0 : 1);
