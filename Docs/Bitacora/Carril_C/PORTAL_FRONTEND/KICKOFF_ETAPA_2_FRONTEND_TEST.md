# KICKOFF — Etapa 2 / Frontend TEST (Carril C — Portal Operativo Interno)

Soy Franco, del proyecto Vita Delta Reservas.

## 0. Rol y modo de trabajo

Sos arquitecto técnico y copiloto de implementación del **frontend** del Portal Operativo Interno.

Disciplina:

- diseño antes de código;
- **una etapa (sub-slice) por conversación**;
- decisiones lockeadas no se reabren (`D-FE-XX` para frontend/contrato; `D-C-XX` queda para el backend);
- si aparece una tensión, se documenta y se pregunta;
- el contrato manda: el frontend habla **solo** con `portal-api` vía `action`, nunca con n8n ni con tablas Supabase;
- castellano rioplatense, con voseo;
- entregables claros, verificables y aptos para repo.

**A confirmar en esta conversación (Q1):** modo de ejecución del frontend. Hasta ahora vos ejecutás todo (Supabase/n8n) y yo diseño. En frontend el entregable **es** código; propongo que **yo escriba los componentes/archivos como artefactos** y vos los corras/deployes/pruebes en TEST. Confirmá si vamos así o si preferís diseño + vos escribís.

## 1. Dónde estamos

El **backend** del Carril C está construido y verificado en TEST hasta Slice 3b (gateway `portal-api` con **CATALOG 13**). El **Contrato Frontend ↔ Portal v1** está **aprobado** (2026-06-22): es la API reference del portal vista desde el navegador, contra el gateway real, con decisiones `D-FE-01…08`.

- `portal-api` (Edge Function) = gateway/BFF: Supabase Auth JWT → lookup `portal_usuarios` → rol → allowlist → HMAC a n8n.
- 13 acciones: 1 Edge (`sesion.contexto`) + 8 lecturas + 4 escrituras.
- OPS y `6B_SCHEMA_SQL.md` v1.8.1 intactos. Carril C es **TEST-only** hasta una promoción coordinada futura.

Hacia dónde vamos: **construir el frontend TEST contra el contrato**, por sub-slices, y recién después QA/UAT por rol y evaluación de promoción coordinada a OPS.

## 2. Objetivo de Etapa 2 y sub-slices

Construir el Portal Operativo Interno (frontend) sobre **TEST**, en sub-slices verticales:

- **Sub-slice 0 — Shell de auth + contexto:** estructura del proyecto + Supabase Auth (login/logout/refresh) + llamada a `sesion.contexto` + **menú por rol** armado con `acciones`. End-to-end mínimo: login → ver el menú correcto por rol (jenny / vicky / socio). ← **primera conversación.**
- **Sub-slice 1 — Pantallas de lectura:** las 8 lecturas (A02 ya en el shell). Calendarios A03/A04 = render del HTML temporal; A05/A06/A12/A24/A25/A13 = JSON estructurado (objeto / listas / reportes de período). Manejo de listas vacías, paginación, filtros, privacidad por rol.
- **Sub-slice 2 — Pantallas de escritura:** A07 `reserva.crear_manual`, A08 `bloqueo.crear_manual`, A10 `cobranza.registrar_saldo`, A11 `cargar.gasto_interno`. Idempotencia por intento de submit (A10 key en `payload`; A11 key sibling), manejo de `conflicto` y `estado_incierto` (reconsulta de la lectura companion, nunca retry ciego).
- **Sub-slice 3 — QA/UAT por rol:** pruebas sobre TEST con Jenny / Vicky / socios. Recién después se evalúa promoción coordinada a OPS.

## 3. Alcance / no-alcance

- **Alcance:** frontend contra las **13 acciones** del contrato v1, sobre TEST.
- **Fuera de alcance:** acciones futuras (A09, A14–A23); contrato JSON formal de calendarios (P-C-3); tocar backend/n8n/OPS/canónico; promoción a OPS (etapa posterior); reset/seed de UAT (etapa separada, solo anotada).

## 4. Orden de lectura

1. **Fuente de verdad del consumo:** `CONTRATO_FRONTEND_PORTAL_v1.md` (`Docs/Implementacion/Carril_C/Portal_Frontend/`). Es autosuficiente para hablar con `portal-api`.
2. **Cierre de contrato:** `CONTRATO_FRONTEND_PORTAL_CIERRE.md` (D-FE-01…08, hallazgos).
3. **Solo si hace falta** (detalle de una acción puntual): el gateway `C_SLICE3B_A13_portal-api_index.ts` y el cierre del slice correspondiente. **No** leer toda la historia de Carril C: con el contrato alcanza.
4. **Satélites como contexto:** `ESTADO_ACTUAL_VITA_DELTA.md`, `DECISIONES_NO_REABRIR.md` (D-FE + D-C), `Pendiente_pre_produccion.md` (P-C-7).

Ante discrepancia: **gateway vigente → cierre de slice → contrato → diseño**.

## 5. Sub-slice 0 en detalle (primera conversación)

Objetivo: shell mínimo que loguea y muestra el menú correcto por rol.

- **Estructura del proyecto** (stack a fijar en Q2): organización de carpetas, cliente HTTP único contra `portal-api` (un solo `callPortal(action, payload, extra)`), manejo de sesión.
- **Supabase Auth:** login (email+password de las identidades TEST), obtención del `access_token`, refresh, logout, manejo de sesión vencida (`no_autorizado` → re-login).
- **Transporte:** `Authorization: Bearer <jwt>` + `apikey: <ANON_KEY_TEST>` + `Content-Type: application/json`. Ramificar por `body.ok`, nunca por status HTTP (sin 401).
- **`sesion.contexto` (A02):** primera llamada tras login; `data:{ nombre, rol, acciones }`. El **menú se arma con `acciones`** (no se hardcodea).
- **Verificación end-to-end:** login con vicky / franco / jenny → menú correcto por rol (jenny ve solo limpieza; vicky/socio ven operativo/económico).

## 6. Preguntas abiertas a cerrar antes de arrancar

Respondé con recomendación esperada y esperá mi OK.

- **Q1 — Modo de ejecución del frontend** (ver §0): ¿yo escribo el código como artefactos y vos corrés/deployás, o diseño + vos escribís? *Recomendación: yo escribo el código, vos ejecutás/deployás/probás en TEST.*
- **Q2 — Stack frontend.** El contrato es agnóstico. ¿Qué fijamos? *Recomendación: React + Vite + Supabase JS (encaja con los ejemplos del contrato; Supabase JS setea `apikey`+`Authorization` solo).* Alternativas: otro framework, fetch plano.
- **Q3 — Hosting TEST + origin (P-C-7).** ¿Dónde corre el frontend TEST? *Recomendación: desarrollo local primero (`http://localhost:5173`), host estático (Vercel/Netlify) cuando convenga; el origin real se fija ahí y se restringe el CORS (P-C-7). Hoy el ACAO es `*`, no bloquea.*
- **Q4 — Anon key TEST.** Necesito el valor real de `<ANON_KEY_TEST>` (publishable, browser-safe) o confirmar que vamos con Supabase JS (que la toma de la config). *Recomendación: Supabase JS con la config del proyecto TEST.*
- **Q5 — Sistema de diseño / UI.** ¿Librería de componentes o CSS propio? *Recomendación: algo liviano (ej. Tailwind o componentes mínimos); se fija en sub-slice 0, no es del contrato.*
- **Q6 — Identidades TEST para QA.** ¿Las identidades sembradas (vicky/franco/rodrigo/remo/jenny) alcanzan para sub-slice 0, o querés crear/usuarios extra? *Recomendación: usar las existentes; el reset/seed de UAT es etapa separada.*

## 7. Líneas rojas

- El frontend nunca llama a n8n directo ni toca tablas Supabase.
- El frontend nunca calcula HMAC ni manda campos de control (`actor`/`rol`/`nonce`/`source_event`/`creado_por`/`request_ts`).
- Cero cambios en gateway, wrappers, OPS ni `6B_SCHEMA_SQL.md`.
- No se reabre el contrato v1 ni los slices cerrados. Si el frontend revela un gap del contrato, se anota como hallazgo y se evalúa v1.1/v2 — no se parchea el backend en caliente.
- Transporte de `idempotency_key` por acción (A10 en `payload` / A11 sibling): no uniformar.

## 8. Entregable de la primera conversación

- Diseño de sub-slice 0 (estructura + auth + `sesion.contexto` + menú por rol) aprobado en chat.
- Si Q1 = "Claude escribe": los archivos del shell como artefactos, para que vos corras en TEST.
- Eventuales `D-FE-09…` / `L-FE-XX` que surjan, con mini-registro.
- Cierre de sub-slice 0 + kickoff de sub-slice 1 (pantallas de lectura).

---

*Kickoff de Etapa 2 — Frontend TEST. Base: `CONTRATO_FRONTEND_PORTAL_v1.md` (CATALOG 13). No se toca backend, n8n, OPS ni canónico.*
