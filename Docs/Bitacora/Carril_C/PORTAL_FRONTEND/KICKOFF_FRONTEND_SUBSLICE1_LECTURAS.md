# KICKOFF — Frontend TEST · Sub-slice 1 (pantallas de lectura)

**Carril C — Portal Operativo Interno / Frontend TEST.** Etapa 2, sub-slice 1.
**Prerequisito cerrado:** sub-slice 0 (shell) validado en TEST 2026-06-23 (`FRONTEND_SUBSLICE0_CIERRE.md`; D-FE-09/10/11, L-FE-01).
**Entorno:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`).
**Modo de trabajo:** diseño antes que código. Resolvemos las preguntas abiertas → blueprint aprobado → **Claude escribe el código fuente** como entregable de repo y **Franco lo corre/deploya/prueba** (regla de ejecución intacta). Una sola etapa por conversación.

---

## 1. Objetivo

Construir las **pantallas de lectura** del portal sobre el shell existente, consumiendo `portal-api` con el `callPortal` ya hecho. Al cerrar el sub-slice 1, cada acción de lectura del menú abre una pantalla real (no placeholder), con manejo de carga / error / vacío, filtros donde corresponda, y privacidad por rol.

**No** se tocan backend, n8n, OPS ni `6B_SCHEMA_SQL.md`. **No** se reabre `CONTRATO_FRONTEND_PORTAL_v1.md`. Cero escrituras.

---

## 2. Orden de lectura (al arrancar la conversación)

1. **`CONTRATO_FRONTEND_PORTAL_v1.md`** — la API reference. Por cada acción de lectura: `payload`, forma de `data`, errores y UX. **Fuente de verdad del consumo.**
2. **`FRONTEND_SUBSLICE0_CIERRE.md`** — qué provee el shell: `callPortal` (envelope + `body.ok`), `AuthProvider`/`sesion.contexto`, `ACTION_REGISTRY`/`construirMenu`, D-FE-09/10/11.
3. **Código del shell** en `apps/portal-operativo/` (sobre esto se construye): `lib/callPortal.ts`, `lib/actionRegistry.ts`, `auth/*`, `app/AppShell.tsx`/`Menu.tsx`/`PlaceholderView.tsx`.
4. **Detalle de formas de `data`** (si el contrato no alcanza): `C_SLICE1_CIERRE.md` (A03/A04/A05/A06/A12), `C_SLICE3A_CIERRE.md` (A24/A25), `C_SLICE3B_CIERRE.md` (A13), y la matriz rol×endpoint en `CARRIL_C_BACKEND_API_DISENO_CIERRE.md`.

---

## 3. Alcance — 8 acciones de lectura

**Calendarios (HTML temporal, D-FE-03):** se renderiza el HTML que devuelve el backend, no se re-pinta como datos.
- **A03 `calendario.limpieza`** — jenny · vicky · socio. (Única pantalla que ve jenny.)
- **A04 `calendario.operativo`** — vicky · socio.

**Lecturas JSON estructuradas:**
- **A05 `reserva.detalle`** — `data:{reserva,pagos}`; payload `id_reserva`. Vista de detalle (no lista). vicky · socio.
- **A06 `prereservas.activas`** — `data:{filas}`. vicky · socio.
- **A12 `cobranza.saldos`** — `data:{filas}`; `saldo_real` puede ser negativo (sobrecobro). vicky · socio.
- **A24 `historico.reservas`** — buscador con filtros (fecha, cabaña, estado), **floor 2026-07-01** (el backend recorta, no rechaza), paginada; devuelve `id_cabana`+`cabana`. vicky · socio.
- **A25 `ingresos.cobrados_periodo`** — caja percibida por **período mensual**, `periodo_hasta` híbrido, floor; paginada con agregados sobre el universo completo. vicky · socio.
- **A13 `gastos.listado`** — gastos por **período contable mensual** (bordes truncados a primer día de mes), paginada, agregados en centavos. vicky · socio.

> Reglas que ya manda el contrato y hay que respetar: **lista vacía `filas:[]` ≠ `no_encontrado`** (D-C-47) → estado "sin resultados", no error. **IDs BIGINT → number** (L-C-19, ya en el contrato). **Ramificar por `body.ok`** (ya en `callPortal`). Errores alcanzables (Familia A): `rol_no_permitido`, `payload_invalido`, `no_encontrado`, `error_interno`, etc.

---

## 4. Preguntas abiertas a resolver (se vuelven D-FE-12+ al aprobarse)

- **Q-SS1-1 — Router.** ¿`react-router-dom` v6 con rutas anidadas bajo `AppShell`, cableadas desde la `ruta` del `ACTION_REGISTRY`? (Las rutas ya están definidas en D-FE-09.) Define cómo se navega y cómo persiste la selección al refrescar.
- **Q-SS1-2 — Patrón de fetch + estados.** ¿Un hook reutilizable (`useAction(action, payload)`) que envuelva `callPortal` y devuelva `{data, loading, error, refetch}`, con convenciones únicas de **cargando / error (con reintentar) / vacío**? ¿O fetch por pantalla?
- **Q-SS1-3 — Render de calendarios HTML (A03/A04).** ¿`iframe` con `srcdoc` **sandboxed** (aísla estilos/scripts del HTML que viene del backend) o `dangerouslySetInnerHTML`? Recomendación inicial: iframe sandbox por aislamiento e higiene; a decidir.
- **Q-SS1-4 — Render de listas + paginación.** Tabla vs tarjetas; y la paginación de A24/A25/A13: confirmar contra el contrato si es **server-side** (params de página/tamaño en el `payload`, con agregados sobre el universo completo) y cómo se exponen los controles.
- **Q-SS1-5 — UX de filtros.** Selectores de fecha, cabaña y estado para A24; selector de **mes** para A13/A25; y cómo se muestra el **floor 2026-07-01** (clamp) sin confundir al usuario.
- **Q-SS1-6 — Guard de ruta por rol.** Navegación directa a una acción que no está en `acciones` (ej. jenny a `/economico/*`) → bloquear/redirigir en el front (espeja D-FE-09 y el `rol_no_permitido` del backend). ¿Redirigir a home o mostrar aviso?
- **Q-SS1-7 — Formato y componentes reutilizables.** Montos en **centavos → ARS**, fechas, nombres de cabaña, badges de estado. ¿Set de componentes de presentación compartidos (`Money`, `Fecha`, `EstadoBadge`, `Vacio`, `Cargando`, `ErrorCard`)?

---

## 5. Fuera de alcance (sub-slices siguientes)

- **Escrituras** (A07/A08/A10/A11) → sub-slice 2 (idempotencia por submit D-FE-07, `conflicto`/`estado_incierto` D-FE-06).
- **QA/UAT por rol** → sub-slice 3.
- **CORS al origin real** (P-C-7), OPS, y cualquier cambio de backend/n8n/canónico.

---

## 6. Entregables del sub-slice 1

- `apps/portal-operativo/` ampliado: router + pantallas de las 8 lecturas + hook(s) de fetch + componentes de presentación, build verificado (`tsc` + `vite build`).
- Runsheet de ejecución local + matriz de verificación por rol (incluida jenny → solo calendario de limpieza; listas vacías; floor de período; guard de ruta).
- Al validar: `FRONTEND_SUBSLICE1_CIERRE.md` + propagación a satélites (layer encima de sub-slice 0) + kickoff del sub-slice 2.

---

*Para arrancar: abrir conversación nueva del sub-slice 1, leer en el orden de §2, y resolver las preguntas de §4 antes de escribir código.*
