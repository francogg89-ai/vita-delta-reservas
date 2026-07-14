// Config del HARNESS de QA (SB-UI-6). Separado de `vite.config.ts` a proposito:
// `npm run build` NUNCA ve esto, asi que `qa/` no puede entrar al bundle de produccion.
import path from 'node:path';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  root: path.resolve(__dirname, 'qa'),
  plugins: [react()],
  define: {
    // `AppShell` -> `AuthProvider` -> `callPortal` valida estas dos AL IMPORTARSE (top-level), asi
    // que sin ellas el harness ni siquiera monta. Se inyectan valores DELIBERADAMENTE INVALIDOS:
    // el harness no hace una sola llamada (todo sale de `qa/fixtures.ts`), y si alguna vez alguien
    // cableara una por error, tiene que reventar contra `.invalid` -- NUNCA contra TEST ni OPS.
    // Esto NO lee ni pisa el `.env` real: vive solo en la config del harness.
    'import.meta.env.VITE_SUPABASE_URL': JSON.stringify('https://harness-qa.invalid'),
    'import.meta.env.VITE_SUPABASE_ANON_KEY': JSON.stringify('NO-ES-UNA-CLAVE-REAL'),
  },
  resolve: {
    alias: [
      // El harness monta el AppShell REAL (header, drawer mobile, <main class="min-w-0 flex-1 p-6">)
      // y le sustituye SOLO el arbol de rutas, que arrastraria todas las pantallas y la red.
      { find: /^\.\/rutas$/, replacement: path.resolve(__dirname, 'qa/stubs/rutas.tsx') },
    ],
  },
  server: { port: 5173, strictPort: true },
});
