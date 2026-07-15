// =============================================================================================
// SB-UI-6-FIX -- Chequeos de HIGIENE del harness.
//
// PORTABLE A WINDOWS. Cero dependencia de bash, grep, sed, mkdir -p, `||` o cualquier utilidad
// Unix. Todo con APIs de Node:
//   - recorrido recursivo con `readdirSync({ withFileTypes: true })`
//   - `mkdirSync(..., { recursive: true })`
//   - esbuild por su API JS (`build({ metafile: true })`), NO por linea de comandos
//   - separadores de path con `path.join`, nunca strings con "/" hardcodeado
//
// Contesta UNA pregunta: como harness puede llegar a produccion? La respuesta tiene que ser NO.
//
//   npm run qa:higiene      (requiere `npm run build` antes)
// =============================================================================================

import { readdirSync, readFileSync, existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MARCADOR = '__VITA_QA_FIXTURE_DO_NOT_SHIP__';

let fallos = 0;
const ok = (c, m) => {
  console.log(`  ${c ? 'ok   ' : 'FALLA'} ${m}`);
  if (!c) fallos++;
};

/** Recorrido recursivo con readdirSync. Reemplaza a `grep -r` / `find`. */
function archivos(dir, filtro = () => true, acc = []) {
  if (!existsSync(dir)) return acc;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
      archivos(p, filtro, acc);
    } else if (filtro(p)) {
      acc.push(p);
    }
  }
  return acc;
}

console.log('\nHIGIENE DEL HARNESS -- qa/ NO puede llegar a produccion\n');

// -------------------------------------------------------------------------------------------
// H1 -- el canario no esta en el bundle de produccion
// -------------------------------------------------------------------------------------------
const DIST = path.join(RAIZ, 'dist', 'assets');
if (!existsSync(DIST)) {
  ok(false, 'no existe dist/ -- corre `npm run build` primero');
} else {
  const bundle = archivos(DIST)
    .map((f) => readFileSync(f, 'utf8'))
    .join('');
  ok(!bundle.includes(MARCADOR), `el canario "${MARCADOR}" NO aparece en dist/assets`);
  ok(!bundle.includes('CATALOGO_A30'), 'los fixtures no se filtraron al bundle');
}

// -------------------------------------------------------------------------------------------
// H2 -- ningun modulo de src/ referencia qa/ (reemplaza a `grep -rl`)
// -------------------------------------------------------------------------------------------
const SRC = path.join(RAIZ, 'src');
const fuentes = archivos(SRC, (f) => /\.(ts|tsx|js|jsx|css)$/.test(f));
const sucios = fuentes.filter((f) => {
  const t = readFileSync(f, 'utf8');
  return /from\s+['"][^'"]*\bqa\//.test(t) || /require\(\s*['"][^'"]*\bqa\//.test(t);
});
ok(
  sucios.length === 0,
  `ninguno de los ${fuentes.length} modulos de src/ importa nada de qa/` +
    (sucios.length ? ` -- ENCONTRADO EN: ${sucios.map((f) => path.relative(RAIZ, f)).join(', ')}` : '')
);

// -------------------------------------------------------------------------------------------
// H3 -- el grafo del entry de produccion no alcanza qa/ (esbuild por API JS, no por CLI)
// -------------------------------------------------------------------------------------------
mkdirSync(path.join(RAIZ, 'node_modules', '.qa'), { recursive: true });
const r = await build({
  entryPoints: [path.join(RAIZ, 'src', 'main.tsx')],
  bundle: true,
  write: false,
  metafile: true,
  format: 'esm',
  logLevel: 'silent',
  loader: { '.css': 'empty' },
  absWorkingDir: RAIZ,
});
const inputs = Object.keys(r.metafile.inputs);
// esbuild siempre emite las claves del metafile con "/", incluso en Windows.
const desdeQa = inputs.filter((f) => f.split('/')[0] === 'qa');
ok(desdeQa.length === 0, `el grafo de src/main.tsx (${inputs.length} modulos) no toca qa/`);

// -------------------------------------------------------------------------------------------
// H4 -- el harness tiene su propia config; la de produccion no lo menciona
// -------------------------------------------------------------------------------------------
const viteProd = readFileSync(path.join(RAIZ, 'vite.config.ts'), 'utf8');
ok(!/\bqa\b/.test(viteProd), 'vite.config.ts (produccion) no menciona qa/');
ok(existsSync(path.join(RAIZ, 'vite.qa.config.ts')), 'el harness tiene su propio vite.qa.config.ts');

// -------------------------------------------------------------------------------------------
// H5 -- PORTABILIDAD: ningun script del harness invoca utilidades Unix ni shell
// -------------------------------------------------------------------------------------------
const UNIX = /(^|[\s;&|(`])(grep|sed|awk|cat|rm|cp|mv|ls|find|which|touch|chmod)\s|mkdir\s+-p/;
const scriptsQa = archivos(path.join(RAIZ, 'qa'), (f) => /\.(mjs|ts|tsx)$/.test(f));
const conUnix = scriptsQa.filter((f) => {
  const t = readFileSync(f, 'utf8')
    .split('\n')
    .filter((l) => {
      const s = l.trim();
      return !s.startsWith('//') && !s.startsWith('*') && !s.startsWith('/*');
    })
    .join('\n');
  return UNIX.test(t) || /\bexecSync\s*\(/.test(t);
});
ok(
  conUnix.length === 0,
  `ninguno de los ${scriptsQa.length} scripts de qa/ invoca utilidades Unix ni execSync` +
    (conUnix.length ? ` -- ${conUnix.map((f) => path.basename(f)).join(', ')}` : '')
);

const pkg = JSON.parse(readFileSync(path.join(RAIZ, 'package.json'), 'utf8'));
const scriptsSucios = Object.entries(pkg.scripts)
  .filter(([k]) => k.startsWith('qa') || k === 'typecheck:qa')
  .filter(([, v]) => /&&|\|\||;|\bmkdir\b|\bgrep\b|\brm\b/.test(v));
ok(
  scriptsSucios.length === 0,
  'ningun script npm de qa usa encadenamiento de shell (&&, ||, ;) ni utilidades Unix' +
    (scriptsSucios.length ? ` -- ${scriptsSucios.map(([k]) => k).join(', ')}` : '')
);

// -------------------------------------------------------------------------------------------
// H6 -- las herramientas del harness son devDependencies DIRECTAS (reproducible con `npm ci`)
// -------------------------------------------------------------------------------------------
for (const dep of ['esbuild', 'playwright']) {
  ok(
    Object.prototype.hasOwnProperty.call(pkg.devDependencies ?? {}, dep),
    `"${dep}" es devDependency directa (no se depende de una transitiva de vite)`
  );
}

console.log(fallos === 0 ? '\n  HIGIENE OK\n' : `\n  ${fallos} FALLAS\n`);
process.exit(fallos === 0 ? 0 : 1);
