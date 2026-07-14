# SB-UI-6-FIX2 — cómo aplicar

`src/` **no se toca**. `package-lock.json` **no se entrega**: no hay dependencias nuevas.

1. Copiar `qa/` (8 archivos), `.gitignore` y `package.json`.
2. `python SB_UI_6_FIX2_patcher.py` — verifica los 4 gates y aborta si algo no cuadra.
3. `npm ci`

## Archivos

| archivo | qué cambia |
|---|---|
| `qa/estructural.mjs` | **M** — F3 renombrado a CLEANUP · **F7** (`reqId` aislado) · **F8** (fail-closed real) · **F9** (retry A30 con clic) · migrado al shape nuevo del stub |
| `qa/mutacion.mjs` | **NUEVO** — mutation gate de `useAction`, autónomo (server propio en el 5199) |
| `qa/HostReqId.tsx` | **NUEVO** — host de una sola instancia del hook, sin StrictMode |
| `qa/stubs/red.ts` | **M** — cola de respuestas + **snapshot al recibir** |
| `qa/stubs/rutas.tsx` | **M** — modo `?host=requid` |
| `qa/main.tsx` | **M** — sesión con acciones configurables (`?acciones=`) · sin StrictMode en el host de reqId |
| `qa/fixtures.ts` | **M** — F20 coherente · F9 corregido (lo cazó el bloque G) |
| `qa/probes.tsx` | **M** — **bloque G** (coherencia de fixtures) · D9 con la correlación real |
| `qa/RUNSHEET.md` `qa/COBERTURA.md` | **M** — 10 comandos · AUTO ≠ CI · cleanup/reqId/token separados |
| `.gitignore` | **NUEVO** — `dist-qa` + `qa/screenshots/` |
| `package.json` | **M** — solo agrega el script `qa:mutacion` |

## Los 10 comandos

```powershell
npm run build ; npm run typecheck ; npm run typecheck:qa
npm run qa:probes ; npm run qa:higiene ; npm run qa:build
npm run qa:mutacion                       # autónomo, server propio en el 5199
npm run qa                                # y en otra consola:
npm run qa:estructural ; npm run qa:responsive
```

Después de la suite, `git status --short` no muestra builds ni screenshots.
