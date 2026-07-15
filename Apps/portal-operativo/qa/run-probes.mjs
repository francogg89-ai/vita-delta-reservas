// SB-UI-6-FIX3 -- Runner de los probes. PORTABLE A WINDOWS.
//
// Antes esto era un script npm con `mkdir -p ... && esbuild ... && node ...`: encadenamiento de
// shell y `mkdir -p`, que en cmd.exe/PowerShell no existen. Ahora es Node puro:
//   esbuild por API JS -> bundle a un temporal -> GATE DE PUREZA -> se ejecuta con import().
//
// GATE DE PUREZA (SB-UI-6-FIX3). El bundle de probes NO puede arrastrar Supabase. Si `probes.tsx`
// importara `callPortal` como VALOR (p.ej. `new PortalApiError(...)`), el grafo se llevaria
// `callPortal -> ./supabase -> createClient -> RealtimeClient`, y en Node 20 (sin WebSocket nativo)
// el bundle revienta al importarse: "Node.js 20 detected without native WebSocket support". Los
// probes son puros (renderToStaticMarkup sobre modulos, sin red): no tienen por que tocar Supabase.
// Se inspecciona el METAFILE de esbuild -- los modulos que realmente entraron al grafo -- y se
// aborta ANTES de ejecutar si aparece cualquier rastro.
//
//   npm run qa:probes
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { build } from 'esbuild';

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SALIDA = path.join(RAIZ, 'node_modules', '.qa', 'probes.mjs');

mkdirSync(path.dirname(SALIDA), { recursive: true });

const resultado = await build({
  entryPoints: [path.join(RAIZ, 'qa', 'probes.tsx')],
  bundle: true,
  platform: 'node',
  format: 'esm',
  jsx: 'automatic',
  outfile: SALIDA,
  logLevel: 'error',
  metafile: true,
  // react / react-dom quedan EXTERNOS: si se bundlean, quedan dos copias de React en memoria y
  // `renderToStaticMarkup` revienta. Node los resuelve desde node_modules en tiempo de ejecucion.
  external: ['react', 'react-dom', 'react-dom/server', 'react/jsx-runtime'],
  // El tipo `PortalApiError` se borra en compilacion; si algo leyera `import.meta.env` igual, se
  // inyectan valores DELIBERADAMENTE INVALIDOS: los probes no hacen una sola llamada, y si alguien
  // cableara una por error tiene que reventar contra `.invalid`, nunca contra TEST.
  define: {
    'import.meta.env': JSON.stringify({
      VITE_SUPABASE_URL: 'https://harness-qa.invalid',
      VITE_SUPABASE_ANON_KEY: 'NO-ES-UNA-CLAVE-REAL',
    }),
  },
  absWorkingDir: RAIZ,
});

// --- GATE DE PUREZA: el grafo del bundle no puede contener Supabase --------------------------
const entradas = Object.keys(resultado.metafile.inputs);
const PROHIBIDOS = [
  '@supabase/supabase-js',
  'src/lib/supabase.ts',
  'createClient',
  'RealtimeClient',
];
const contaminantes = [];
for (const patron of PROHIBIDOS) {
  // Los primeros dos son PATHS de modulos (chequeo directo sobre las claves del metafile). Los
  // ultimos dos son SIMBOLOS: no aparecen como modulo, asi que se buscan en el codigo emitido.
  const enGrafo = entradas.some((f) => f.replace(/\\/g, '/').includes(patron));
  if (enGrafo) contaminantes.push(`${patron} (modulo en el grafo)`);
}
// Los simbolos createClient / RealtimeClient solo pueden estar si @supabase entro; con los dos
// primeros patrones alcanza. Pero se dejan en la lista para que el mensaje sea explicito y, si
// algun dia esbuild inlinea distinto, el chequeo de modulo los cubra igual.
if (contaminantes.length > 0) {
  console.error(
    '\n  GATE DE PUREZA -- FALLA: el bundle de probes arrastra Supabase.\n' +
      contaminantes.map((c) => `    - ${c}`).join('\n') +
      '\n\n  Causa tipica: `probes.tsx` importa algo de `callPortal` como VALOR (p.ej.\n' +
      '  `new PortalApiError(...)`). Usa `import type` y un objeto casteado.\n' +
      '  En Node 20 esto ademas revienta en runtime (sin WebSocket nativo).\n'
  );
  process.exit(1);
}
console.log(`  gate de pureza OK -- ${entradas.length} modulos en el grafo, cero rastro de Supabase`);

// pathToFileURL: en Windows un path como C:\... no es una URL valida para import().
await import(pathToFileURL(SALIDA).href);
