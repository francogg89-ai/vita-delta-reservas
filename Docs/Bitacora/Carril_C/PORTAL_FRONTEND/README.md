# Vita Delta — Portal Operativo Interno (frontend)

Frontend del Portal Operativo Interno (Carril C), construido contra el gateway `portal-api`
según `CONTRATO_FRONTEND_PORTAL_v1.md` (CATALOG 13, TEST). El frontend habla **solo** con
`portal-api` vía `action`; nunca con n8n ni con tablas de Supabase.

> Ubicación canónica de la doc de contrato: `Docs/Implementacion/Carril_C/Portal_Frontend/`.

## Estado: Sub-slice 0 — shell de auth + menú por rol

Alcance de este sub-slice:

- Shell del frontend (estructura del proyecto).
- Login / logout con Supabase Auth; persistencia y refresh de sesión.
- Primera llamada a `sesion.contexto` (A02) → estado `{ nombre, rol, acciones }`.
- Menú por rol armado desde `acciones` (no hardcodeado).
- Placeholder por acción (las pantallas reales llegan en sub-slices siguientes).
- Manejo de `no_autorizado` → re-login.

**Fuera de alcance (todavía):** pantallas reales de lectura (sub-slice 1), formularios de
escritura (sub-slice 2), router, QA/UAT (sub-slice 3). Sin cambios en backend, n8n, OPS ni
`6B_SCHEMA_SQL.md`.

## Stack

- **React 18 + Vite 5 + TypeScript** (estricto).
- **Supabase JS 2** — solo para la capa de **auth/sesión** (D-FE-10).
- **`callPortal`** propio con `fetch` para hablar con `portal-api`: lee siempre el envelope y
  ramifica por `body.ok`, nunca por status HTTP (D-FE-04). Manejo defensivo si un 5xx no trae
  JSON parseable.
- **Tailwind 3** — UI base desde el sub-slice 0 (D-FE-11), paleta propia delta/río.

## Decisiones

- **D-FE-09 (lockeada)** — Composición del menú = `acciones` de `sesion.contexto` ∩
  `ACTION_REGISTRY`. El backend es la única autoridad de visibilidad; el frontend solo aporta
  presentación (`label`, `grupo`, `orden`, `ruta`) por acción. Acción que venga en `acciones`
  pero no esté en el registry se ignora silenciosamente por pin de versión; entrada del registry
  no presente en `acciones` no se muestra. Cero hardcodeo de visibilidad por rol.
- **D-FE-10 (a formalizar en el cierre)** — Stack del sub-slice 0: React + Vite + Supabase JS
  para auth + `fetch` propio para `portal-api`.
- **D-FE-11 (a formalizar en el cierre)** — UI base con Tailwind desde el sub-slice 0.

## Cómo correrlo

Ver `RUNSHEET_SUBSLICE0.md`. Resumen:

```bash
cd apps/portal-operativo
npm install
cp .env.example .env   # completá VITE_SUPABASE_ANON_KEY (anon de TEST)
npm run dev            # http://localhost:5173
```

## Scripts

- `npm run dev` — servidor de desarrollo (Vite).
- `npm run build` — typecheck (`tsc`) + bundle de producción (`vite build`).
- `npm run typecheck` — solo typecheck.
- `npm run preview` — sirve el build de producción localmente.
