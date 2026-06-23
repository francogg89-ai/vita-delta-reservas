# FRONTEND SUB-SLICE 0 — CIERRE

**Estado:** ✅ **Sub-slice 0 (Frontend TEST) validado en TEST** (2026-06-23). Primer **código de frontend** del Carril C: el **shell del Portal Operativo Interno** — auth Supabase (login/logout + persistencia/autorefresh) + llamada de bootstrap a `sesion.contexto` + **menú por rol armado desde `acciones`** + placeholder por acción + `no_autorizado` → re-login. Construido contra el **gateway real** (CATALOG 13) usando `CONTRATO_FRONTEND_PORTAL_v1.md` como única referencia. **Sin una sola línea tocada en backend, n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1.**

**Entorno de referencia:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5. Endpoint: `https://bdskhhbmcksskkzqkcdp.supabase.co/functions/v1/portal-api`.
**Fecha de cierre:** 2026-06-23.
**Ubicación del frontend en el repo:** `apps/portal-operativo/` (Vite app).
**Base / fuente de verdad:** `CONTRATO_FRONTEND_PORTAL_v1.md` (API reference del portal, CATALOG 13) reflejando el gateway real de Slice 3b.
**Depende de (no se reabre):** D-FE-01…08 (contrato frontend↔portal) · D-C-03 (jenny sin económico) · D-C-34 (`portal_usuarios` TEST-only) · D-C-39/41 (allowlist doble + action binding) · D-C-43/47 (envelope `{ok,data|error}`, lista vacía ≠ `no_encontrado`) · D-NEG-02 (floor contable 2026-07-01).
**Autores:** Franco (titular; corrió y validó la app en local contra TEST con evidencia visual, y ejecutará la propagación) + Claude (arquitecto/copiloto, estrictamente advisory; escribió el código fuente como entregable de repo — Franco lo ejecutó/deployó/probó: la regla de ejecución queda intacta).
**Decisiones registradas:** **D-FE-09, D-FE-10, D-FE-11** 🔒 (namespace propio de frontend). **Lección:** **L-FE-01** (primera `L-FE` real; el namespace estaba reservado desde el cierre del contrato).

---

## 1. Qué se produjo

El **Vite app** `apps/portal-operativo/`: el shell del portal que consume `portal-api`.

**Stack (D-FE-10/11):** React 18 + Vite 5 + TypeScript estricto + Tailwind 3 (paleta propia delta/río) + `@supabase/supabase-js` v2 **solo para auth/sesión**.

**Funcionalidad del shell (alcance del sub-slice 0):**

- **Login / logout** email+password vía Supabase Auth; **persistencia + autorefresh** de sesión (sobrevive al refresh del navegador).
- **Bootstrap:** una llamada a `sesion.contexto` (A02) tras tener sesión → estado `{ nombre, rol, acciones }`.
- **Menú por rol** armado desde `acciones` (no hardcodeado) — implementa **D-FE-09** en `lib/actionRegistry.ts` (`construirMenu` = intersección `acciones ∩ ACTION_REGISTRY`, con tolerancia forward y drop de grupos vacíos).
- **Placeholder por acción:** cada ítem del menú abre un stub ("pantalla en construcción → sub-slice 1/2"); cero pantallas reales.
- **`no_autorizado` → re-login:** si `sesion.contexto` devuelve `no_autorizado` (usuario de Supabase sin fila en `portal_usuarios` / `activo=false` / sesión inválida), se cierra la sesión y se vuelve a login con aviso "No tenés acceso al portal".
- **`callPortal` propio** (`lib/callPortal.ts`): cliente único con `fetch`; headers `Content-Type` + `apikey` (anon) + `Authorization: Bearer <jwt>`; **ramifica por `body.ok`, nunca por status HTTP** (D-FE-04); **defensivo** si un 5xx no trae JSON parseable (sintetiza error genérico). El frontend nunca firma HMAC ni manda campos de control.
- **`.env.example`** con la URL de TEST + placeholder `__PEGAR_ANON_KEY_TEST__` (la anon es publishable/browser-safe, pero va por entorno, no hardcodeada). `.env` real en `.gitignore`.

**Árbol entregado:**

```
apps/portal-operativo/
├─ package.json · index.html · vite.config.ts · tsconfig.json
├─ postcss.config.js · tailwind.config.js · .gitignore · .env.example
├─ README.md · RUNSHEET_SUBSLICE0.md · package-lock.json
└─ src/
   ├─ main.tsx · App.tsx · index.css · vite-env.d.ts
   ├─ lib/   types.ts · supabase.ts · callPortal.ts · actionRegistry.ts
   ├─ auth/  AuthProvider.tsx · useAuth.ts · LoginScreen.tsx
   └─ app/   AppShell.tsx · Menu.tsx · PlaceholderView.tsx
```

**Verificación de build (previa a la entrega):** `tsc --noEmit` exit 0 + `npm run build` (`tsc && vite build`) exit 0; 81 módulos; Tailwind purgó correcto (CSS ~10 kB); paleta propia confirmada en el CSS compilado (`bg-river` → `#0f6e7d`, `bg-mist` → `#f4f6f5`, `text-ink` → `#10211f`).

**Fuera de alcance (sub-slices siguientes):** pantallas de lectura (1), formularios de escritura (2), router, QA/UAT por rol (3). Sin backend, n8n, OPS ni canónico.

---

## 2. Evidencia de validación en TEST

Franco corrió la app en local (`http://localhost:5173`) contra TEST con las identidades sembradas. El menú lo arma `sesion.contexto`, así que esto valida el **acuerdo backend↔frontend por rol** (D-FE-09): el backend es la única autoridad de visibilidad; el front solo presenta.

| Identidad | Rol mostrado | Menú renderizado | Evidencia | Resultado |
|---|---|---|---|---|
| `franco@vitadelta.test` | Socio | 12 ítems / 5 grupos — Calendarios (2), Reservas (4), Bloqueos (1), Cobranzas (2), Económico (3) | a1 | ✅ |
| `vicky@vitadelta.test` | Operación | idéntico a franco (12 / 5) | a3 | ✅ |
| `jenny@vitadelta.test` | Limpieza | **solo** Calendarios → Calendario de limpieza (1 ítem). **Sin** Reservas/Bloqueos/Cobranzas/Económico | a2 | ✅ |

La exclusión económica de jenny (**D-C-03**) se sostiene **desde el backend** vía `acciones`, sin hardcodeo en el front: justo lo que valida D-FE-09.

Otros caminos verificados:

- **Login + error de credenciales** (a4, a5): pantalla de login; contraseña incorrecta → "Email o contraseña incorrectos." sin romper.
- **Placeholder** (a6): clic en "Detalle de reserva" → stub "sub-slice 1 (pantallas de lectura)", con el ítem activo resaltado.
- **Logout:** "Salir" → vuelve a login.
- **Persistencia:** refresh estando logueado → menú reconstruido (confirmado por Franco).
- **Consola** (a7 + capturas de Console/Issues): **cero errores de aplicación** — ver **L-FE-01**.

---

## 3. Decisiones registradas (D-FE-09…11) 🔒

> Namespace propio de frontend. **No se mezcla con `D-C-XX`** (backend Carril C). Lecciones de frontend = `L-FE-XX`.

- **D-FE-09 — Composición del menú = `acciones` de `sesion.contexto` ∩ `ACTION_REGISTRY`.** El backend es la **única autoridad de visibilidad**; el frontend solo aporta presentación (`label`, `grupo`, `orden`, `ruta`) por `action`. Acción que venga en `acciones` pero no esté en el registry **se ignora silenciosamente** (tolerancia forward, coherente con el pin de versión D-FE-01); entrada del registry no presente en `acciones` **no se muestra**. **Cero hardcodeo de visibilidad por rol** en el frontend. (Lockeada 2026-06-22; validada empíricamente en este sub-slice — §2.)
- **D-FE-10 — Stack del frontend.** React + Vite + TypeScript estricto. **Supabase JS solo para auth/sesión** (login/logout/persistencia/autorefresh). Para hablar con `portal-api`, **`callPortal` propio con `fetch`**: lee siempre el envelope, **ramifica por `body.ok`** (no por status HTTP, D-FE-04) y es **defensivo** si un 5xx no trae JSON parseable (error genérico). El frontend **no** firma HMAC ni calcula campos de control.
- **D-FE-11 — UI base con Tailwind desde el sub-slice 0.** Tailwind 3 con **paleta propia delta/río** (no clichés cream/acid). Se incorpora desde el shell para evitar refactor al entrar las pantallas reales.

---

## 4. Lección registrada (L-FE-01)

- **L-FE-01 — El ruido de consola de extensiones del navegador no es error de la app.** Al verificar el frontend en local, la consola puede mostrar errores/advertencias que **no** son de la app sino de **extensiones del navegador** inyectando un content script. Caso real de esta validación: una wallet (tipo MetaMask) → todo el ruido trazaba a `contentscript.js`, con firmas inconfundibles (`ObjectMultiplex - orphaned data for stream "app-init-liveness"/"background-liveness"`, `MaxListenersExceededWarning: ... EventEmitter memory leak`, más dos *Issues*: CSP bloquea `eval` y "Shared Storage API deprecated"). **Criterio de discriminación = la fuente del mensaje:** `localhost:5173` o `/src/…` → app; `chrome-extension://…`, `contentscript.js`, `favicon.ico` o terceros → ruido. **Verificación definitiva:** abrir el portal en una ventana de incógnito / perfil sin extensiones → consola limpia. La app **no setea CSP ni usa `eval`** y solo llama `sesion.contexto` una vez; los *Issues* de CSP-eval y Shared Storage observados eran de la extensión, no del portal.

---

## 5. Líneas rojas respetadas

- **Cero** cambios en backend, n8n, OPS y `6B_SCHEMA_SQL.md` v1.8.1. No se reabrió `CONTRATO_FRONTEND_PORTAL_v1.md` ni ningún slice cerrado. No se tocó `portal_usuarios`, `portal_idempotencia`, el gateway ni los wrappers.
- El frontend **solo** consume `portal-api` vía `action`; nunca llama a n8n ni a tablas de Supabase directamente.
- **Regla de ejecución intacta:** Claude escribió el código fuente como entregable de repo; **Franco** ejecutó/deployó/probó/commiteará. Claude no operó infraestructura.
- **Anti-leak:** la anon key no se hardcodeó ni se pegó en chat (placeholder `__PEGAR_ANON_KEY_TEST__`, valor por entorno).

---

## 6. Propagación a documentos satélite (aplicada 2026-06-23)

> **EOL por archivo:** `README.md` LF · `ESTADO_ACTUAL_VITA_DELTA.md` **CRLF** · `DECISIONES_NO_REABRIR.md` LF · `CLAUDE.md` LF · `Pendiente_pre_produccion.md` LF · `Lecciones_Aprendidas.md` (mixto; bloques recientes CRLF). **`6B_SCHEMA_SQL.md` y OPS: sin cambios.**

La propagación del **cierre del contrato** (`CONTRATO_FRONTEND_PORTAL_CIERRE.md` §6) **ya estaba aplicada** (los satélites tenían D-FE-01…08 y `ESTADO_ACTUAL` con "Etapa actual: Contrato Frontend"), así que esta propagación se aplicó **por layer encima**, no consolidada. Ediciones (8 `str_replace`, cada una verificada **`count==1`** contra los archivos vigentes, con **EOL preservado**):

- **`ESTADO_ACTUAL_VITA_DELTA.md` (CRLF):** nuevo bloque **"Etapa actual: Carril C — Frontend TEST · sub-slice 0 (shell) — validado 2026-06-23"** (shell auth + `sesion.contexto` + menú por rol, evidencia visual, D-FE-09/10/11 / L-FE-01, sin backend/n8n/OPS/canónico); el bloque del **Contrato Frontend** pasó a **"Etapa previa"**.
- **`DECISIONES_NO_REABRIR.md` (LF):** encabezado de la sección Frontend `(D-FE-01…08)` → `(D-FE-01…11)`, y **D-FE-09/10/11** agregadas tras D-FE-08 (formato satélite, dos spans en negrita).
- **`Lecciones_Aprendidas.md` (CRLF):** nueva sección **`## Lecciones de Frontend (L-FE-XX)`** con **L-FE-01** (primera del namespace).
- **`CLAUDE.md` (LF):** entrada **"sub-slice 0 (shell) ✅ Validado en TEST (2026-06-23)"** tras la del Contrato Frontend.
- **`README.md` (LF):** dos ediciones (estado actual + bullet de roadmap del Carril C) → "Frontend TEST: sub-slice 0 (shell) validado; próximo sub-slice 1 (pantallas de lectura)".
- **`Pendiente_pre_produccion.md` (LF):** **P-C-7** extendido — origin del frontend concretado a `http://localhost:5173` en dev; CORS `*` no bloquea; restringir al origin real al exponer.

**Verificación:** las 8 anclas matchearon `count==1`; EOL preservado (ESTADO_ACTUAL CRLF puro; Lecciones CRLF/mixto; el resto LF puro). Con esto **D-FE-09/10/11 y L-FE-01 quedan lockeados** y el sub-slice 0 cierra formalmente. Pendiente de Franco: ubicar este cierre en el repo (p. ej. `Docs/Bitacora/Carril_C/...`) y commitear el conjunto (satélites + cierre + `apps/portal-operativo/`).

---

## 7. Pendientes y handoff

- **Sub-slice 1 — Pantallas de lectura (próximo):** A03/A04 (render del **HTML temporal**, D-FE-03), y JSON estructurado para A05 (`reserva.detalle`), A06 (`prereservas.activas`), A12 (`cobranza.saldos`), A24 (`historico.reservas`), A25 (`ingresos.cobrados_periodo`), A13 (`gastos.listado`). Manejo de **listas vacías** (`filas:[]` ≠ `no_encontrado`, D-C-47), paginación, **filtros por período** con floor 2026-07-01 (D-NEG-02) y semántica mensual de A13/A25, privacidad por rol. El **router** (react-router) entra acá: las `ruta` ya están definidas en el registry (D-FE-09). Kickoff sugerido: `KICKOFF_FRONTEND_SUBSLICE1_LECTURAS.md`.
- **P-C-7 (CORS):** hoy `*` no bloquea `localhost:5173`; restringir al origin real al exponer el portal.
- **Sub-slices siguientes:** **2** (escrituras A07/A08/A10/A11; idempotencia por intento de submit, D-FE-07; manejo de `conflicto`/`estado_incierto`, D-FE-06) → **3** (QA/UAT por rol). Luego, **promoción coordinada del Carril C a OPS** al cerrar el MVP.

---

## 8. Inventario de artefactos

- **App:** `apps/portal-operativo/` (árbol en §1). Entrega: `portal-operativo-subslice0.tar.gz` (solo fuente + lockfile).
- **Runsheet:** `RUNSHEET_SUBSLICE0.md`. **README:** `apps/portal-operativo/README.md`.
- **Evidencia:** capturas `a1`–`a7` (menús por rol, login, error de credenciales, placeholder, consola).
- **Cierre:** este documento (`FRONTEND_SUBSLICE0_CIERRE.md`).
- **Referencia:** `CONTRATO_FRONTEND_PORTAL_v1.md` (`Docs/Implementacion/Carril_C/Portal_Frontend/`).

---

*Fin de `FRONTEND_SUBSLICE0_CIERRE.md` — shell del Portal Operativo validado en TEST (login → `sesion.contexto` → menú por rol). D-FE-09/10/11 · L-FE-01. Sin cambios en backend, n8n, OPS ni canónico.*
