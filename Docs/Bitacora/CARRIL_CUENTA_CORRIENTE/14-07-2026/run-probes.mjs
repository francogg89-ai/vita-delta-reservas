// SB-UI-6-FIX -- Runner de los probes. PORTABLE A WINDOWS.
//
// Antes esto era un script npm con `mkdir -p ... && esbuild ... && node ...`: encadenamiento de
// shell y `mkdir -p`, que en cmd.exe/PowerShell no existen. Ahora es Node puro:
//   esbuild por API JS -> bundle a un temporal -> se ejecuta con `pathToFileURL` + import().
//
//   npm run qa:probes
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { build } from 'esbuild';

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SALIDA = path.join(RAIZ, 'node_modules', '.qa', 'probes.mjs');

mkdirSync(path.dirname(SALIDA), { recursive: true });

await build({
  entryPoints: [path.join(RAIZ, 'qa', 'probes.tsx')],
  bundle: true,
  platform: 'node',
  format: 'esm',
  jsx: 'automatic',
  outfile: SALIDA,
  logLevel: 'error',
  // react / react-dom quedan EXTERNOS: si se bundlean, quedan dos copias de React en memoria y
  // `renderToStaticMarkup` revienta. Node los resuelve desde node_modules en tiempo de ejecucion.
  external: ['react', 'react-dom', 'react-dom/server', 'react/jsx-runtime'],
  // `PortalApiError` vive en `callPortal`, que lee `import.meta.env` al importarse. En Node eso no
  // existe. Se inyectan valores DELIBERADAMENTE INVALIDOS: los probes no hacen una sola llamada, y
  // si alguien cableara una por error tiene que reventar contra `.invalid`, nunca contra TEST.
  define: {
    'import.meta.env': JSON.stringify({
      VITE_SUPABASE_URL: 'https://harness-qa.invalid',
      VITE_SUPABASE_ANON_KEY: 'NO-ES-UNA-CLAVE-REAL',
    }),
  },
  absWorkingDir: RAIZ,
});

// pathToFileURL: en Windows un path como C:\... no es una URL valida para import().
await import(pathToFileURL(SALIDA).href);
