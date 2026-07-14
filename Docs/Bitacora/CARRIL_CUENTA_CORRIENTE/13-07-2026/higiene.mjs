// SB-UI-6 -- Chequeos de HIGIENE del harness. JS puro (no entra al typecheck de TS, no necesita
// @types/node): lo unico que hace es mirar el filesystem y el grafo de modulos.
//
// Contesta UNA pregunta: ¿el harness puede llegar a produccion? La respuesta tiene que ser NO.
//
// Corre con: npm run qa:higiene   (requiere `npm run build` antes)
import { execSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';

const MARCADOR = '__VITA_QA_FIXTURE_DO_NOT_SHIP__';
let fallos = 0;
const ok = (c, m) => {
  console.log(`  ${c ? 'ok   ' : 'FALLA'} ${m}`);
  if (!c) fallos++;
};

console.log('\nHIGIENE DEL HARNESS -- qa/ NO puede llegar a produccion\n');

// H1 -- el canario no esta en el bundle
if (!existsSync('dist/assets')) {
  ok(false, 'no existe dist/ -- corre `npm run build` primero');
} else {
  const bundle = readdirSync('dist/assets')
    .map((f) => readFileSync(`dist/assets/${f}`, 'utf8'))
    .join('');
  ok(!bundle.includes(MARCADOR), `el canario "${MARCADOR}" NO aparece en dist/assets/*`);
  ok(!bundle.includes('CATALOGO_A30'), 'los fixtures no se filtraron al bundle');
}

// H2 -- src/ no referencia qa/
const ref = execSync('grep -rlE "qa/" src/ || true', { encoding: 'utf8' }).trim();
ok(ref === '', `ningun modulo de src/ referencia qa/${ref ? ` -- ENCONTRADO EN: ${ref}` : ''}`);

// H3 -- el entry de produccion no alcanza qa/
// esbuild no puede escribir el metafile a /dev/stdout: va a un temporal y se lee.
const META = 'node_modules/.qa/meta-prod.json';
execSync(
  'mkdir -p node_modules/.qa && npx esbuild src/main.tsx --bundle --format=esm ' +
    `--outfile=node_modules/.qa/prod.js --metafile=${META} --log-level=error --loader:.css=empty`,
  { stdio: 'pipe' }
);
const meta = JSON.parse(readFileSync(META, 'utf8'));
const desdeQa = Object.keys(meta.inputs).filter((f) => f.startsWith('qa/'));
ok(desdeQa.length === 0, `el grafo de src/main.tsx (${Object.keys(meta.inputs).length} modulos) no toca qa/`);

// H4 -- el harness NO esta en el vite.config de produccion
const vc = readFileSync('vite.config.ts', 'utf8');
ok(!vc.includes('qa'), 'vite.config.ts (produccion) no menciona qa/');
ok(existsSync('vite.qa.config.ts'), 'el harness tiene su propio vite.qa.config.ts');

console.log(fallos === 0 ? '\n  HIGIENE OK\n' : `\n  ${fallos} FALLAS\n`);
process.exit(fallos === 0 ? 0 : 1);
