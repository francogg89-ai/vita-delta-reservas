# CONTRATO FRONTEND PORTAL — CIERRE

**Estado:** ✅ **Contrato Frontend ↔ Portal v1 aprobado** (2026-06-22). Etapa de **diseño/documento puro**: se produjo `CONTRATO_FRONTEND_PORTAL_v1.md`, la **especificación de consumo del gateway `portal-api` desde el navegador** (API reference del portal), reflejando el **gateway real de Slice 3b** (CATALOG 13), no la documentación. **Sin una sola línea de frontend, sin cambios en backend, n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1.**

**Entorno de referencia:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5, marcador `configuracion_general.ambiente='test'`. Endpoint documentado: `https://bdskhhbmcksskkzqkcdp.supabase.co/functions/v1/portal-api`.
**Fecha de cierre:** 2026-06-22.
**Base / fuente de verdad:** `C_SLICE3B_A13_portal-api_index.ts` (gateway vigente, CATALOG 13) + los cuatro cierres de slice (`CARRIL_C_BACKEND_API_DISENO_CIERRE.md` para A01–A25/matriz rol×endpoint, `C_SLICE1_CIERRE.md`, `C_SLICE2_CIERRE.md`, `C_SLICE3A_CIERRE.md`, `C_SLICE3B_CIERRE.md`) + templates `portal-aXX-*__TEMPLATE.json` (formas de `data`) + smokes (headers de transporte).
**Depende de (no se reabre):** D-C-03 (jenny sin económico) · D-C-09 (calendarios HTML temporal; JSON formal = P-C-3) · D-C-18 (envelope uniforme, `detail` mínimo) · D-C-39/41 (allowlist doble + action binding) · D-C-43/47 (contrato `{ok,data|error}`, lista vacía → `ok:true`) · D-C-50/51 (escrituras + `estado_incierto`) · D-C-54/57/59/60 (semántica `periodo_hasta`, transporte de `idempotency_key`, período mensual) · D-NEG-02 (floor contable 2026-07-01) · L-C-19 (BIGINT → number) · L-C-23 (el gateway espeja el wrapper directo de cada acción).
**Autores:** Franco (titular; aprobó el contrato y ejecutará la propagación) + Claude (arquitecto/copiloto; estrictamente advisory).
**Decisiones registradas:** **D-FE-01, D-FE-02, D-FE-03, D-FE-04, D-FE-05, D-FE-06, D-FE-07, D-FE-08** 🔒 (namespace propio de frontend/contrato). **Lecciones:** ninguna (no hubo `L-FE` real; el namespace queda reservado).

---

## 1. Qué se produjo

`CONTRATO_FRONTEND_PORTAL_v1.md` (15 secciones), API reference autosuficiente del portal: arquitectura de consumo, endpoint/transporte (URL TEST + `apikey` + JWT), auth Supabase, sobre de request, modelo de respuesta, **catálogo de las 13 acciones** (payload + forma de `data` + errores + UX por acción, extraídos de templates/cierres), errores en dos familias, idempotencia, visibilidad por rol, convenciones de datos, acciones futuras, versionado, hallazgos y ejemplos por familia.

**Alcance:** 13 acciones construidas (CATALOG 13 = 1 Edge + 8 lecturas + 4 escrituras). **Fuera de alcance:** acciones futuras (A09, A14–A23), OPS, implementación del frontend, contrato JSON formal de calendarios (P-C-3).

Ubicación canónica en el repo: `Docs/Implementacion/Carril_C/Portal_Frontend/CONTRATO_FRONTEND_PORTAL_v1.md`.

---

## 2. CATALOG 13 confirmado (verdad de referencia)

| Cód | `action` | Tipo | Roles | `idempotency_key` |
|---|---|---|---|---|
| A02 | `sesion.contexto` | Edge | jenny · vicky · socio | — |
| A03 | `calendario.limpieza` | lectura | jenny · vicky · socio | — |
| A04 | `calendario.operativo` | lectura | vicky · socio | — |
| A05 | `reserva.detalle` | lectura | vicky · socio | — |
| A06 | `prereservas.activas` | lectura | vicky · socio | — |
| A12 | `cobranza.saldos` | lectura | vicky · socio | — |
| A24 | `historico.reservas` | lectura | vicky · socio | — |
| A25 | `ingresos.cobrados_periodo` | lectura | vicky · socio | — |
| A13 | `gastos.listado` | lectura | vicky · socio | — |
| A07 | `reserva.crear_manual` | escritura | vicky · socio | no (key interna del wrapper) |
| A08 | `bloqueo.crear_manual` | escritura | vicky · socio | no (guard por `conflicto`) |
| A10 | `cobranza.registrar_saldo` | escritura | vicky · socio | **sí — en `payload`** |
| A11 | `cargar.gasto_interno` | escritura | vicky · socio | **sí — sibling de `payload`** |

---

## 3. Decisiones registradas (D-FE-01…08) 🔒

> Namespace propio de frontend/contrato. **No se mezcla con `D-C-XX`** (backend Carril C). Las lecciones del frontend usarán `L-FE-XX`.

- **D-FE-01 — Alcance del contrato = CATALOG 13.** Cubre exactamente las 13 acciones construidas y verificadas en TEST (Slice 3b). Las futuras se listan sin contrato detallado. El frontend **pinea** la versión del contrato que implementa. Cambios → v1.1 (aditivo) / v2 (rompe).
- **D-FE-02 — Transporte dual de `idempotency_key`.** No es uniforme entre escrituras: **A10** la lleva **dentro de `payload`** (`payload.idempotency_key`); **A11** la lleva **top-level, sibling de `payload`**; **A07** no recibe key del frontend (el wrapper deriva idempotencia interna para `crear_prereserva`; la respuesta trae `idempotent_match`); **A08** sin key, guard por `conflicto`/solapamiento. El frontend respeta el transporte **por acción**.
- **D-FE-03 — Calendarios A03/A04 = HTML temporal.** Devuelven `data:{ formato:"html", html }`; el frontend **renderiza ese HTML** (contenedor/iframe), no lo re-pinta como datos estructurados. Contrato JSON formal de calendarios = **P-C-3**, post-MVP.
- **D-FE-04 — Ramificación por `body.ok`, no por status HTTP.** `portal-api` responde **HTTP 200 + envelope** para todo resultado manejado (incluido `no_autorizado`); el único no-200 es **500** (crash de infra → `error_interno`). El frontend decide éxito/error por **`body.ok`**. **No** se documenta 401 como contrato normal.
- **D-FE-05 — Taxonomía de errores en dos familias.** (a) **alcanzables por el frontend** (`no_autorizado`, `rol_no_permitido`, `accion_desconocida`, `payload_invalido`, `no_encontrado`, `conflicto`, `estado_incierto`, `error_interno`); (b) **canal gateway↔n8n / "no debería pasar"** (`firma_invalida`, `ts_fuera_de_ventana`, `raw_body_ausente`, `ambiente_incorrecto`, `error_entorno`) — el frontend no las gatilla (no firma ni manda `ts`); si aparecen, es bug de backend → mensaje genérico / contactar admin.
- **D-FE-06 — Ante `estado_incierto` en escritura, no reintentar a ciegas.** El frontend **reconsulta la lectura companion** (A24/A05/A04 para A07; A24 para A08; A12/A05 para A10; A13 para A11) o muestra verificación manual. Nunca reenvío automático.
- **D-FE-07 — La `idempotency_key` la genera el frontend, por intento de submit.** Mismo submit (retry de red/UI) → **misma** key; nuevo submit intencional → **nueva** key. Regex `^[A-Za-z0-9_-]{8,64}$`. Aplica a A10 (en payload) y A11 (sibling). Semántica: misma key + mismo payload + mismo actor → idempotente; payload distinto → `conflicto`/`payload_mismatch`; actor distinto → `conflicto`/`actor_mismatch`. (A11 además tiene anti-replay de `nonce` server-side; el frontend no lo ve ni lo calcula.)
- **D-FE-08 — Namespace.** Decisiones de contrato/frontend = `D-FE-XX`; lecciones = `L-FE-XX`. No se mezclan con `D-C-XX`.

---

## 4. Hallazgos / pendientes (sin parchear; el gateway vigente manda)

- **CORS abierto (`*`) — P-C-7.** Restringir al origin del portal antes de exponerlo fuera de TEST. **Comentario inline del gateway cita "(P-C-4)", pero el ítem real es P-C-7** (P-C-4 es otro: hardening post-MVP). Comentario de código stale; sin impacto funcional.
- **Origin del frontend TEST sin decidir.** Placeholder `<ORIGIN_PORTAL_TEST>`; `http://localhost:5173` es solo ejemplo no vinculante de desarrollo local.
- **`apikey` (anon) requerida además del JWT.** Confirmado en los smokes (header `apikey` = anon de TEST). Es publishable (browser-safe); su valor real se documenta al construir, no se hardcodea.
- **Transporte dual de `idempotency_key`** (A10 en payload / A11 sibling) — trampa principal del contrato (D-FE-02).
- **A03/A04 devuelven HTML, no JSON estructurado** (D-FE-03). Migración a JSON = P-C-3.
- **Sin 401** — todo error es HTTP 200 + envelope; solo 500 = crash de infra (D-FE-04).
- **`estado_incierto` requiere reconsulta, no retry ciego** (D-FE-06).
- **UAT/reset de TEST = etapa separada.** Este contrato solo deja anotado el requisito (seeds QA por rol). OPS intacto.

---

## 5. Líneas rojas respetadas

- Solo diseño/documento. Cero frontend code. Cero deploy. Cero cambios en gateway, wrappers, OPS ni `6B_SCHEMA_SQL.md`. No se reabrió A11/A13 ni ningún slice cerrado. No se inventaron payloads (el gateway vigente mandó en cada caso). Los gaps se anotaron como hallazgos.

---

## 6. Deltas para documentos satélite (aplicar tras auditar este cierre)

> **EOL por archivo** (verificado con `file` contra los archivos reales): `README.md` LF · `ESTADO_ACTUAL_VITA_DELTA.md` **CRLF** · `DECISIONES_NO_REABRIR.md` LF · `CLAUDE.md` LF · `Pendiente_pre_produccion.md` LF · `Lecciones_Aprendidas.md` (sin cambios). En cada `str_replace`, **asegurar `count==1`** del ancla antes de aplicar. **`6B_SCHEMA_SQL.md` y OPS: sin cambios.**

### 6.1 `README.md` (LF) — dos ediciones

**(a)** En el párrafo "Estado actual" (cierra el bloque del Carril C). **Ancla** (única):
`**cumple P-C-9 en TEST**; **OPS y schema (v1.8.1) siguen intactos**. Próximo: promoción coordinada del Carril C a OPS (al cerrar el MVP).`
**Reemplazo:** la misma frase hasta `intactos**.` y luego:
`Sobre eso se aprobó el **Contrato Frontend ↔ Portal v1** (2026-06-22): la API reference del portal vista desde el navegador, contra el gateway real (CATALOG 13), con reglas estructurales (transporte dual de \`idempotency_key\`, calendarios HTML temporal, ramificación por \`body.ok\` sin 401) y decisiones D-FE-01…08, sin tocar el backend (\`Docs/Implementacion/Carril_C/Portal_Frontend/CONTRATO_FRONTEND_PORTAL_v1.md\`). Próximo: construir el **Frontend TEST** contra ese contrato (luego promoción coordinada del Carril C a OPS al cerrar el MVP).`

**(b)** En el bullet del Carril C de la sección de roadmap/documentación. **Ancla** (única):
`y \`Docs/Bitacora/Carril_C/C_SLICE_3/C_SLICE3B_CIERRE.md\`. **Próximo:** promoción coordinada del Carril C a OPS (al cerrar el MVP) o slices societarias A14–A23 (post-MVP).`
**Reemplazo:** hasta `C_SLICE3B_CIERRE.md\`.` y luego:
`Sobre eso se **aprobó el Contrato Frontend ↔ Portal v1** (2026-06-22): API reference del portal contra el gateway real (CATALOG 13), decisiones D-FE-01…08, en \`Docs/Implementacion/Carril_C/Portal_Frontend/CONTRATO_FRONTEND_PORTAL_v1.md\`; backend/n8n/OPS/canónico intactos (cierre \`CONTRATO_FRONTEND_PORTAL_CIERRE.md\`). **Próximo:** construir el **Frontend TEST** contra ese contrato (sub-slices: auth + \`sesion.contexto\` + menú por rol → lecturas → escrituras → QA/UAT), luego promoción coordinada del Carril C a OPS (al cerrar el MVP).`

### 6.2 `ESTADO_ACTUAL_VITA_DELTA.md` (CRLF) — nuevo "Etapa actual" + degradar Slice 3b

Insertar un nuevo bloque **"Etapa actual"** al inicio y **convertir el actual `**Etapa actual:** … Slice 3b …` en `**Etapa previa:**`**. **Ancla** (inicio del bloque actual, única): `**Etapa actual:** Carril C — Portal Operativo Interno / **Slice 3b (gastos: A11 carga + A13 listado)** — **cerrada en TEST 2026-06-22**.`
**Reemplazo** = nuevo bloque + separador (CRLF) + `**Etapa previa:**` + el resto del bloque de Slice 3b:

> **Etapa actual:** Carril C — Portal Operativo Interno / **Contrato Frontend ↔ Portal v1** — **aprobado 2026-06-22**. La **especificación de consumo del gateway `portal-api` desde el navegador** (API reference del portal): cubre las **13 acciones** realmente construidas y verificadas en TEST (CATALOG 13 = 1 Edge + 8 lecturas + 4 escrituras), reflejando el **gateway real de Slice 3b** (no la documentación). Reglas estructurales: **transporte dual de `idempotency_key`** (A10 dentro de `payload`; A11 sibling top-level; A07 sin key —el wrapper deriva idempotencia interna, `idempotent_match` en la respuesta—; A08 sin key, guard por `conflicto`); **calendarios A03/A04 = HTML temporal** `data:{formato:"html",html}` (contrato JSON formal = P-C-3, post-MVP); **ramificación por `body.ok`, no por status HTTP** (HTTP 200 + envelope para todo resultado manejado; solo 500 = crash de infra; **no hay 401**); **`estado_incierto` en escritura → reconsulta de la lectura companion**, nunca retry ciego; **errores en dos familias** (alcanzables por frontend / canal n8n "no debería pasar"); menú por rol vía `sesion.contexto`. **Decisiones D-FE-01…08** (namespace propio, no se mezcla con `D-C-XX`). **Sin cambios en backend, n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1**: solo diseño/documento. Pendientes anotados: CORS al origin del portal (**P-C-7**, hoy `*`), origin del frontend TEST (`<ORIGIN_PORTAL_TEST>`), valor real de la anon key, preparación/reset de TEST para UAT (etapa separada). Próxima etapa: **Frontend TEST** (sub-slices: shell de auth + `sesion.contexto` + menú por rol → pantallas de lectura → pantallas de escritura → QA/UAT por rol). Documento: `CONTRATO_FRONTEND_PORTAL_v1.md` (`Docs/Implementacion/Carril_C/Portal_Frontend/`). Cierre: `CONTRATO_FRONTEND_PORTAL_CIERRE.md`.

…seguido de una línea en blanco (CRLF) y luego `**Etapa previa:** Carril C — Portal Operativo Interno / **Slice 3b …` (el bloque que hoy es "Etapa actual", sin más cambios).

### 6.3 `DECISIONES_NO_REABRIR.md` (LF) — nueva sección propia de Frontend/Contrato

Insertar una sección nueva **inmediatamente antes** de la línea `## Lecciones operativas n8n consolidadas (L-6C-XX)` (ancla única, `count==1`), después de la sección de Slice 3b (último bullet D-C-60). Estilo idéntico (heading `##` + intro + bullets), EOL LF:

```
## Frontend / Contrato Portal — Contrato Frontend ↔ Portal v1 (D-FE-01…08) — aprobado en TEST 2026-06-22

Decisiones de la **especificación de consumo del gateway `portal-api` desde el navegador** (API reference del portal, `CONTRATO_FRONTEND_PORTAL_v1.md`), reflejando el **gateway real de Slice 3b** (CATALOG 13). Etapa de **diseño/documento puro**: sin frontend, sin cambios en backend, n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1. Namespace propio `D-FE-XX`, **no se mezcla con `D-C-XX`**. Cierre: `CONTRATO_FRONTEND_PORTAL_CIERRE.md`.

- **D-FE-01** — **Alcance = CATALOG 13.** El contrato cubre exactamente las 13 acciones construidas y verificadas en TEST (1 Edge + 8 lecturas + 4 escrituras). Las futuras (A09, A14–A23) se listan sin contrato detallado. El frontend **pinea** la versión; cambios → v1.1 (aditivo) / v2 (rompe).
- **D-FE-02** — **Transporte dual de `idempotency_key`.** A10 la lleva **dentro de `payload`** (`payload.idempotency_key`); A11 **top-level, sibling de `payload`**; A07 **no recibe key** del frontend (el wrapper deriva idempotencia interna; respuesta con `idempotent_match`); A08 **sin key**, guard por `conflicto`/solapamiento. El frontend respeta el transporte por acción.
- **D-FE-03** — **Calendarios A03/A04 = HTML temporal.** Devuelven `data:{formato:"html",html}`; el frontend renderiza el HTML (no lo re-pinta como datos). Contrato JSON formal = **P-C-3**, post-MVP (coherente con D-C-09).
- **D-FE-04** — **Ramificación por `body.ok`, no por status HTTP.** `portal-api` responde HTTP 200 + envelope para todo resultado manejado (incluido `no_autorizado`); el único no-200 es 500 (crash de infra → `error_interno`). **No** se documenta 401 como contrato normal.
- **D-FE-05** — **Taxonomía de errores en dos familias.** (a) alcanzables por el frontend (`no_autorizado`/`rol_no_permitido`/`accion_desconocida`/`payload_invalido`/`no_encontrado`/`conflicto`/`estado_incierto`/`error_interno`); (b) canal gateway↔n8n / "no debería pasar" (`firma_invalida`/`ts_fuera_de_ventana`/`raw_body_ausente`/`ambiente_incorrecto`/`error_entorno`) — el frontend no las gatilla; si aparecen, bug de backend.
- **D-FE-06** — **Ante `estado_incierto` en escritura, no reintentar a ciegas.** Reconsultar la lectura companion (A24/A05/A04 para A07; A24 para A08; A12/A05 para A10; A13 para A11) o mostrar verificación manual. Nunca reenvío automático.
- **D-FE-07** — **La `idempotency_key` la genera el frontend, por intento de submit.** Mismo submit → misma key; nuevo submit intencional → nueva key. Regex `^[A-Za-z0-9_-]{8,64}$`. Aplica a A10 (payload) y A11 (sibling). Semántica: misma key + mismo payload + mismo actor → idempotente; payload distinto → `conflicto`/`payload_mismatch`; actor distinto → `conflicto`/`actor_mismatch`. A11 tiene además anti-replay de `nonce` server-side (el frontend no lo ve).
- **D-FE-08** — **Namespace.** Decisiones de contrato/frontend = `D-FE-XX`; lecciones = `L-FE-XX`. No se mezclan con `D-C-XX`.
```

…seguido de una línea en blanco y la línea `## Lecciones operativas n8n consolidadas (L-6C-XX)` original.

### 6.4 `CLAUDE.md` (LF) — entrada breve de cierre

Insertar **inmediatamente después** del párrafo de cierre de Slice 3b (ancla única, fin de esa línea):
`Cierre \`C_SLICE3B_CIERRE.md\`. **Próxima etapa: promoción coordinada del Carril C a OPS (al cerrar el MVP) o slices societarias A14–A23 (post-MVP).**`
**Reemplazo:** esa línea + una línea en blanco + la entrada nueva:

> **Carril C — Portal Operativo Interno / Contrato Frontend ↔ Portal v1 ✅ Aprobado (2026-06-22):** especificación de consumo del gateway `portal-api` desde el navegador (API reference del portal), contra el **gateway real de Slice 3b** (CATALOG 13 = 1 Edge + 8 lecturas + 4 escrituras). Reglas estructurales: transporte dual de `idempotency_key` (A10 en `payload`; A11 sibling; A07 key interna del wrapper; A08 sin key), calendarios A03/A04 = HTML temporal (`data:{formato:"html",html}`; JSON formal = P-C-3), ramificación por `body.ok` no por status HTTP (HTTP 200 + envelope, sin 401), `estado_incierto` → reconsulta de la lectura companion, errores en dos familias, menú por rol vía `sesion.contexto`. **Diseño/documento puro:** sin frontend, sin cambios en backend, n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1. **Decisiones D-FE-01…08** (namespace propio, no se mezcla con `D-C-XX`). Documento `CONTRATO_FRONTEND_PORTAL_v1.md` (`Docs/Implementacion/Carril_C/Portal_Frontend/`). Cierre `CONTRATO_FRONTEND_PORTAL_CIERRE.md`. **Próxima etapa: Frontend TEST** (sub-slices: auth + `sesion.contexto` + menú por rol → lecturas → escrituras → QA/UAT).

### 6.5 `Pendiente_pre_produccion.md` (LF) — solo P-C-7

Extender **P-C-7** (no tocar el resto). **Ancla** (única):
`- **P-C-7** — **CORS de \`portal-api\`:** hoy abierto (\`*\`) en Slice 0; **restringir al origin real** del Portal Operativo antes de exponerlo. No bloqueante para TEST.`
**Reemplazo:** la misma línea + al final:
` **(Contrato Frontend v1, 2026-06-22):** el origin del frontend TEST queda como placeholder \`<ORIGIN_PORTAL_TEST>\` (ej. no vinculante \`http://localhost:5173\`); se fija al construir el Frontend TEST. Nota: el comentario inline del gateway cita "(P-C-4)" para esta restricción, pero el ítem real es **P-C-7** (P-C-4 es otro: hardening post-MVP).`

### 6.6 `Lecciones_Aprendidas.md` — **sin cambios**

No hubo `L-FE` real (etapa de diseño/documento, sin gotcha operativo). El namespace `L-FE-XX` queda reservado para la construcción del frontend.

---

## 7. Pendientes y handoff

- **Etapa 2 — Frontend TEST** (próxima): construir el frontend contra `CONTRATO_FRONTEND_PORTAL_v1.md`, por sub-slices (0 auth + `sesion.contexto` + menú por rol → 1 lecturas → 2 escrituras → 3 QA/UAT por rol). Kickoff: `KICKOFF_ETAPA_2_FRONTEND_TEST.md`.
- **Antes de Etapa 2:** confirmar empíricamente el valor de `<ANON_KEY_TEST>` y si el cliente Supabase JS alcanza (setea `apikey`+`Authorization` solo) o se va con `fetch` plano.
- **P-C-7 (CORS) + origin del frontend TEST:** se deciden al construir/exponer; hoy `*` no bloquea TEST.
- **UAT/reset de TEST por rol:** etapa separada, solo anotada acá. OPS intacto.

---

## 8. Inventario de artefactos

- **Entregable:** `CONTRATO_FRONTEND_PORTAL_v1.md` (`Docs/Implementacion/Carril_C/Portal_Frontend/`).
- **Cierre:** este documento (`CONTRATO_FRONTEND_PORTAL_CIERRE.md`).
- **Kickoff de la próxima etapa:** `KICKOFF_ETAPA_2_FRONTEND_TEST.md`.

---

*Fin de `CONTRATO_FRONTEND_PORTAL_CIERRE.md` — contrato frontend v1 aprobado contra el gateway real (CATALOG 13). D-FE-01…08. Sin cambios en backend, n8n, OPS ni canónico.*
