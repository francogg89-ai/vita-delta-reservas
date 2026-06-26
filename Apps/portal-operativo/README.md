# Vita Delta — Portal Operativo Interno (frontend)

Frontend del Portal Operativo Interno (Carril C), construido contra el gateway `portal-api`
según `CONTRATO_FRONTEND_PORTAL_v1.md` (CATALOG 13, TEST). El frontend habla **solo** con
`portal-api` vía `action`; nunca con n8n ni con tablas de Supabase.

> Ubicación canónica de la doc de contrato: `Docs/Implementacion/Carril_C/Portal_Frontend/`.

## Estado: Sub-slice 2 cerrado — las 4 escrituras (TEST)

Construido y validado por rol sobre TEST:

- **Sub-slice 0 — shell:** estructura del proyecto, login/logout con Supabase Auth (persistencia + refresh), `sesion.contexto` (A02) → `{ nombre, rol, acciones }`, **menú por rol armado desde `acciones`** (no hardcodeado), placeholder por acción, `no_autorizado` → re-login.
- **Sub-slice 1 — las 8 lecturas:** A03/A04 (calendarios en `<iframe srcDoc>` sandbox sin scripts), A05/A06/A12 y A24/A25/A13 (filtros nativos + paginación server-side); router `react-router-dom`, hook `useAction`, `DataTable`/`Paginador`, `Money` que **nunca divide por 100**.
- **Sub-slice 2 — las 4 escrituras:** A08 `bloqueo.crear_manual`, A07 `reserva.crear_manual` (seña 0 = auto 50%), A11 `cargar.gasto_interno` (key sibling) y A10-MP `cobranza.registrar_cobro` (multi-porción + recargo 5% + **bloqueo de sobrepago** UI+backend). Patrón `useEnviar` + idempotencia por intento de submit + `estado_incierto`; W10 `cobranza.registrar_saldo` queda deprecated-in-place, oculto del frontend por tolerancia-forward.

**Próximo:** sub-slice 3 — **QA/UAT por rol** (TEST, Jenny / Vicky / socios); recién después se evalúa la promoción coordinada del Carril C a OPS. Sin cambios en backend, n8n, OPS ni `6B_SCHEMA_SQL.md` (el frontend solo consume `portal-api` vía `action`).

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
- **D-FE-10 (lockeada)** — Stack del sub-slice 0: React + Vite + Supabase JS
  para auth + `fetch` propio para `portal-api`.
- **D-FE-11 (lockeada)** — UI base con Tailwind desde el sub-slice 0.
- Set completo del frontend: **D-FE-01…28 / L-FE-01…07** (ver `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md` y el contrato `CONTRATO_FRONTEND_PORTAL_v1.md`).

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
