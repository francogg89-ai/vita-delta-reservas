# PROMOCIÓN COORDINADA DEL CARRIL C A OPS — PLAN Y SECUENCIA

**Etapa:** Punto 2 — Promoción coordinada del Carril C (Portal Operativo Interno) a OPS.
**Estado del documento:** 📋 **PLAN PROPUESTO — NO EJECUTADO.** OPS sigue intacto. Este documento se aprueba antes de tocar OPS; recién con el plan aprobado arranca el Bloque A.
**Fecha de redacción:** 2026-06-27.
**Verificación de partida:** clon fresco del remoto en `5113d1a` ("aviso 8C-bis enganchado al alta por portal A07"). Canónico vigente **`6B_SCHEMA_SQL.md v1.8.1`**.
**Método de referencia:** `PROMOCION_CARRIL_B_OPS_CIERRE.md` (promoción coordinada del Carril B 9C→9H a OPS, 2026-06-14, bloques A-bis→M). Este plan **calca** ese método: snapshot read-only antes de habilitar DDL, recreación por DDL sin copiar datos de TEST, validación por capa, fingerprint estructural y smokes read-only, bump único del canónico.

**Rol:** Claude implementa y valida (genera artefactos `PROMO_*`, verificaciones, runsheets y este plan); **Franco ejecuta todos los writes** en Supabase, los imports/deploys en n8n y Vercel, y los commits. Claude **no toca** Supabase, n8n ni OPS directamente.

---

## 1. Resumen ejecutivo

El Carril C está **cerrado y validado en TEST de punta a punta y es 100% TEST-only** — OPS nunca se tocó. Esta etapa lo promueve a OPS de forma **coordinada, capa por capa, por DDL sin copiar datos**, para que el equipo opere el portal real interno sobre OPS.

Cinco capas viajan a OPS: infra del portal (3 objetos), gateway `portal-api`, los wrappers n8n (CATALOG 14), la rama de aviso 8C-bis en el A07, y el frontend (build con env de OPS). Más una decisión de canónico: la infra del portal se **incorpora a `6B_SCHEMA_SQL.md` y bumpea a v1.9.0** (igual que el Carril B canonizó sus 9 tablas en v1.8.0), con la frontera estricta de que **al canónico entra solo estructura** (DDL, grants/RLS, funciones, comentarios) y **nunca seeds reales, emails, secretos ni URLs**.

Resultado esperado al cierre: portal interno real andando sobre OPS, con identidad real de los 5 usuarios, paridad estructural TEST↔OPS de la infra del portal certificada por huella, smokes read-only verdes, y canónico v1.9.0 autocontenido.

---

## 2. Estado de entrada (verificado contra el remoto `5113d1a`)

- **Carril C cerrado y validado en TEST**, 100% TEST-only. OPS intacto.
  - **Backend:** gateway Edge Function `portal-api` (JWT → rol → allowlist rol×action → firma HMAC) + 14 entradas en el CATALOG (1 Edge + 8 lecturas + 5 escrituras, una de ellas deprecada-in-place). El gateway más nuevo es `A10MP_B2_portal-api_index.ts` (incluye A10-MP).
  - **Infra del portal FUERA del canónico, TEST-only:** `portal_usuarios`, `portal_idempotencia`, `portal_cargar_gasto_interno`.
  - **Frontend:** React+Vite+TS publicado en Vercel (link TEST) con banner de ambiente; piloto operativo OK con usuarios reales.
  - **Aviso:** A07 dispara el aviso 8C-bis por rama lateral (D-C-71/72/73), validado end-to-end en TEST.
- **OPS** (`vita-delta-ops`): entorno de operación real interna, paritario y endurecido, con el Carril B ya promovido (canónico v1.8.0→v1.8.1), datos reales del complejo, cabañas ids **1-5** (Bamboo=1, Madre Selva=2, Arrebol=3, Guatemala=4, Tokio=5), socios **Franco(1)/Rodrigo(2)/Remo(3)**, `pg_cron` activo, credencial n8n `vita_supabase_ops` verificada, sub-workflow `vita_w8cbis_alerta__OPS` (id `fHzMFj7pGMKuYEOb`) activo desde 8C-bis.
- **Canónico `6B_SCHEMA_SQL.md v1.8.1`** intacto; la infra del portal es aditiva y **no canónica**, existente solo en TEST. **Nada del Carril C en OPS.**
- **Política de promoción** (precedente Carril B): promoción **coordinada**, por DDL, sin copiar datos ni fixtures.

---

## 3. Inventario reconciliado — CATALOG 14

> `type Rol = 'jenny' | 'vicky' | 'socio'`. Verificado línea por línea contra `A10MP_B2_portal-api_index.ts` (objeto `CATALOG`, L620-729).

**Los tres conteos del Carril C (todos correctos, fotos de momentos distintos):**

| Fuente | Número | Composición |
|---|---|---|
| Gateway desplegado (`A10MP_B2_portal-api_index.ts`) | **14 entradas** | 1 Edge + 8 lecturas + **5** escrituras |
| Contrato Frontend v1 (`CONTRATO_FRONTEND_PORTAL_v1.md`, 2026-06-22) | **13 acciones** | 1 Edge + 8 lecturas + **4** escrituras (lista A10, anterior a A10-MP) |
| Frontend real (`ACTION_REGISTRY` en la UI) | **12 expuestas** | No incluye `cobranza.registrar_saldo` (W10, deprecada) |

**Objetivo técnico de esta promoción:** reproducir el **CATALOG 14** en OPS, gateway byte-paritario con TEST (sin tocar `index.ts`). El frontend productivo en OPS sigue usando solo las acciones vigentes — en particular A10-MP `cobranza.registrar_cobro`, nunca W10.

### 3.1 Las 14 entradas y su destino OPS

> Convención de sufijo OPS (decidida): **`__OPS` para todos los wrappers n8n** (paridad con `vita_w8cbis_alerta__OPS`). En TEST las escrituras llevan `__TEST`; las lecturas no llevan sufijo. En OPS, todos `__OPS`.

| # | acción (key) | descripción | tipo | roles | TEST target | OPS target | env var / workflow esperado | estado | observaciones |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `sesion.contexto` | Identidad→rol→menú (A02) | **Edge** | jenny·vicky·socio | resuelto en `portal-api` TEST | resuelto en `portal-api` OPS | ninguna (lee `portal_usuarios` por service_role) | ✅ TEST | **No es wrapper n8n.** Cero workflow. Se resuelve íntegro en la Edge Fn. |
| 2 | `calendario.limpieza` | Calendario limpieza HTML (A03) | n8n | jenny·vicky·socio | `portal-a03-limpieza` | `portal-a03-limpieza__OPS` | wrapper n8n OPS firmado HMAC-OPS | ✅ TEST | Único endpoint además de sesión que ve jenny. Sin parámetros. |
| 3 | `calendario.operativo` | Calendario operativo 120d c/montos (A04) | n8n | vicky·socio | `portal-a04-operativo` | `portal-a04-operativo__OPS` | wrapper n8n OPS | ✅ TEST | jenny rebota en gateway (D-C-03). |
| 4 | `reserva.detalle` | Detalle de reserva por id (A05) | n8n | vicky·socio | `portal-a05-detalle` | `portal-a05-detalle__OPS` | wrapper n8n OPS | ✅ TEST | `payloadIdReserva` (entero positivo estricto). |
| 5 | `prereservas.activas` | Lista prereservas activas (A06) | n8n | vicky·socio | `portal-a06-prereservas` | `portal-a06-prereservas__OPS` | wrapper n8n OPS | ✅ TEST | Lee `vista_prereservas_activas`. |
| 6 | `cobranza.saldos` | Saldos pendientes (A12) | n8n | vicky·socio | `portal-a12-saldos` | `portal-a12-saldos__OPS` | wrapper n8n OPS | ✅ TEST | Reusa lógica `vita_w09_listado_saldos`. |
| 7 | `historico.reservas` | Buscador histórico reservas (A24) | n8n | vicky·socio | `portal-a24-historico-reservas` | `portal-a24-historico-reservas__OPS` | wrapper n8n OPS | ✅ TEST | Floor 2026-07-01 (D-NEG-02). |
| 8 | `ingresos.cobrados_periodo` | Caja percibida por período (A25) | n8n | vicky·socio | `portal-a25-ingresos` | `portal-a25-ingresos__OPS` | wrapper n8n OPS | ✅ TEST | Floor 2026-07-01. |
| 9 | `gastos.listado` | Gastos internos por mes (A13) | n8n | vicky·socio | `portal-a13-gastos-listado` | `portal-a13-gastos-listado__OPS` | wrapper n8n OPS | ✅ TEST | Companion lectura de A11. |
| 10 | `reserva.crear_manual` | Crear reserva manual (A07) | n8n **write** | vicky·socio | `portal-a07-crear-reserva__TEST` | `portal-a07-crear-reserva__OPS` | wrapper n8n OPS **+ rama aviso 8C-bis** | ✅ TEST | **Único wrapper con +2 nodos:** rama lateral → `Call fHzMFj7pGMKuYEOb`, `entorno` por `leer_ambiente.valor` (D-C-71…73). |
| 11 | `bloqueo.crear_manual` | Crear bloqueo manual (A08) | n8n **write** | vicky·socio | `portal-a08-crear-bloqueo__TEST` | `portal-a08-crear-bloqueo__OPS` | wrapper n8n OPS | ✅ TEST | id_cabana obligatorio (bloqueo total no se expone, 8D). |
| 12 | **`cobranza.registrar_saldo`** ⚠️ | Registrar saldo (W10/A10) — **legacy** | n8n **write** | vicky·socio | `portal-a10-registrar-saldo__TEST` | `portal-a10-registrar-saldo__OPS` | wrapper n8n OPS | ⚠️ **DEPRECATED-IN-PLACE** | **Viaja solo por paridad** (ver §3.2). El frontend no la expone ni la llama. |
| 13 | `cargar.gasto_interno` | Cargar gasto interno (A11) | n8n **write** | vicky·socio | `portal-a11-cargar-gasto-interno__TEST` | `portal-a11-cargar-gasto-interno__OPS` | wrapper n8n OPS | ✅ TEST | `needsIdempotencyKey` (nonce sibling). Depende de `portal_idempotencia` + `portal_cargar_gasto_interno`. |
| 14 | `cobranza.registrar_cobro` | Cobranza multi-porción +5% (A10-MP) | n8n **write** | vicky·socio | `portal-a10mp-registrar-cobro__TEST` | `portal-a10mp-registrar-cobro__OPS` | wrapper n8n OPS | ✅ TEST | **Acción vigente de cobranza.** `idempotency_key` en payload. Reemplaza a A10/W10. |

**Conteo OPS:** 1 Edge (sin workflow) + 8 lecturas n8n + 5 escrituras n8n = **13 wrappers n8n a importar** + el gateway con CATALOG 14.

### 3.2 Nota explícita — W10 `cobranza.registrar_saldo` DEPRECATED-IN-PLACE

La entrada #12 del CATALOG (`cobranza.registrar_saldo`, W10 / A10) **viaja a OPS solo por paridad y tolerancia-forward**, con esta frontera explícita:

- **No es acción operativa vigente.** La acción vigente de cobranza es `cobranza.registrar_cobro` / **A10-MP** (entrada #14).
- **El frontend no la expone ni la llama.** El `ACTION_REGISTRY` de la UI no la incluye; B5 frontend usa solo A10-MP (D-C-64).
- **Viaja por paridad,** para mantener `gateway OPS ≡ gateway TEST` (CATALOG 14 idéntico) y **no tocar el `index.ts`** en esta promoción — mismo criterio con que el Carril B conservó `gastos` legacy.
- **No es "quinta escritura productiva normal":** es legacy/deprecated promovida por paridad. En cualquier conteo de capacidades operativas reales, las escrituras vigentes son **4** (A07, A08, A11, A10-MP).
- **Deuda futura:** removerla del gateway/allowlist queda como **etapa específica con QA propio** (su propia conversación de diseño). No se ejecuta en esta promoción.

---

## 4. Frontera del canónico — bump a `6B_SCHEMA_SQL.md v1.9.0`

**Decisión (tomada):** la infra del portal (`portal_usuarios`, `portal_idempotencia`, `portal_cargar_gasto_interno`) **se incorpora al canónico** en esta promoción coordinada y bumpea a **v1.9.0**. Criterio: si pasan a OPS, dejan de ser infra experimental TEST-only y pasan a formar parte real del sistema; corresponde consolidarlas. Precedente: el Carril B canonizó sus 9 tablas + 21 funciones en v1.8.0 (D-PROMO-12).

**Frontera estricta (no negociable):** al canónico entra **estructura**; los datos de identidad/secretos/URLs viven **solo** en el script/runsheet operacional de promoción.

### 4.1 ✅ ENTRA al canónico v1.9.0 (estructura estable, idéntica entre entornos)

| Objeto | Qué se canoniza | Fuente |
|---|---|---|
| `portal_usuarios` | CREATE TABLE: `user_id uuid PK FK→auth.users`, `nombre text NOT NULL UNIQUE`, `rol text NOT NULL CHECK IN ('jenny','vicky','socio')`, `activo boolean NOT NULL DEFAULT true`, `created_at timestamptz`. + 3 constraints nombradas + `COMMENT ON TABLE/COLUMN`. | `C_SLICE0_A1_DDL_portal_usuarios.sql` |
| `portal_usuarios` — hardening | REVOKE ALL a PUBLIC/anon/authenticated/service_role; GRANT SELECT solo a service_role; **assert duro** (`has_table_privilege`) — D-C-34. | idem |
| `portal_idempotencia` | CREATE TABLE: 12 columnas; PK + 2 UNIQUE (`uq_nonce`, `uq_action_key` sobre `(action,idempotency_key)`) + 1 FK RESTRICT → `gastos_internos` + 7 CHECK; RLS off; hardening espejo. + comentarios. | `C_SLICE3B_A11_DDL_infra_y_funcion.sql` |
| `portal_cargar_gasto_interno(jsonb)` | Cuerpo de la función `SECURITY INVOKER` + firma + `SET search_path` + guard de dos capas (advisory lock → anti-replay nonce → idempotencia de negocio → INSERT atómico con savepoint). + comentario. | idem |
| Sección conceptual + PARTE C | Nueva sección (p. ej. §25) conceptual del Carril C infra + entrada ejecutable en PARTE C, con cuerpos en estado post-validación. | redacción nueva |
| Changelog | v1.8.1 → v1.9.0. | redacción nueva |

### 4.2 ❌ NO entra al canónico — vive solo en script/runsheet operacional de promoción OPS

- **Seeds reales de `portal_usuarios`** (5 emails reales Franco/Rodrigo/Remo/Vicky/Jenny → rol). El canónico no lleva filas de identidad. Seed por email contra `auth.users` (`INSERT…SELECT`, sin UUIDs literales — D-C-32).
- **Creación de los 5 usuarios en Supabase Auth de OPS** (Dashboard; UUIDs/passwords) — nunca al repo.
- **`VITA_HMAC_SECRET` de OPS** y cualquier secreto (P-C-8, D-C-33).
- **URLs de los wrappers n8n OPS**, config del gateway, origin del CORS.
- **Datos operativos de OPS** (reservas, pagos, gastos reales).
- Marcador `configuracion_general('ambiente') = 'ops'` (se siembra en la promoción; es dato, no estructura).

> Esto calca exactamente D-PROMO-12 del Carril B: bump incorporando estructura + grants + comentarios, excluyendo la maquinaria de promoción (gates/asserts/snapshots/seeds quedan en los `PROMO_*` y este plan).

---

## 5. Secuencia de promoción — bloques A→I

Calcando el método del Carril B (DDL sin datos, gate de identidad por seed en cada bloque, smokes read-only, fingerprint estructural). **Cada bloque tiene su gate; no se avanza al siguiente sin el gate del anterior en verde.** OPS solo se toca a partir del Bloque B (el A es read-only puro).

### Bloque A — Snapshot baseline read-only de OPS
- **Qué hace:** snapshot **sin writes, sin DDL** del estado de OPS antes de habilitar nada. Gate de identidad por seed (cabañas 1-5 por id+nombre, marcador `ambiente='ops'`). Baseline de EXECUTE/exposición contemplando `proacl IS NULL ⇒ PUBLIC ejecuta` y excluyendo funciones de extensión (`pg_depend deptype='e'`).
- **Toca OPS:** solo lectura. **Habilita DDL** únicamente si A queda verde.
- **Patrón:** = D-PROMO-02 (`PROMO_BLOQUE_A_BIS_SNAPSHOT_v2.sql`).

### Bloque B — Infra del portal por DDL (sin seed)
- **Qué hace:** crea `portal_usuarios` + `portal_idempotencia` + `portal_cargar_gasto_interno` en OPS por DDL, con GRANTs/RLS espejo de TEST + assert duro D-C-34. **Sin seed todavía.** Gate de ambiente (`DO+RAISE`, cabañas 1-5) como pre-check y dentro de la transacción.
- **Toca OPS:** DDL (estructura, cero filas de identidad).
- **Fuente:** `C_SLICE0_A1_DDL_portal_usuarios.sql` + `C_SLICE3B_A11_DDL_infra_y_funcion.sql`, adaptados a OPS (gate `ambiente='ops'`).

### Bloque C — Usuarios Auth OPS + seed real de `portal_usuarios`
- **Qué hace:** (1) crear los 5 usuarios reales en Supabase Auth de OPS (Dashboard, emails reales) — **manual de Franco**, fuera del repo; (2) seed por email (`INSERT…SELECT` resolviendo `user_id` contra `auth.users`). Roles: Franco/Rodrigo/Remo → `socio`; Vicky → `vicky`; Jenny → `jenny`.
- **Toca OPS:** Auth (5 usuarios) + 5 filas en `portal_usuarios`.
- **Fuente:** `C_SLICE0_A2_SEED_portal_usuarios.sql` adaptado a emails reales (script operacional, NO canónico).

### Bloque D — Gateway `portal-api` a OPS
- **Qué hace:** deploy de `A10MP_B2_portal-api_index.ts` a OPS con env de OPS: `VITA_HMAC_SECRET` propio de OPS (P-C-8, mismo nombre, valor distinto — D-C-33), `VITA_AMBIENTE`/`N8N_BASE_URL` de OPS, **CORS restringido al origin real** del portal (P-C-7, hoy `*`). Los webhooks del CATALOG apuntan a los wrappers `__OPS`.
- **Toca OPS:** Edge Function desplegada + secrets de OPS (valores fuera del repo).
- **Nota:** el `index.ts` no se edita (CATALOG 14 idéntico a TEST). Solo cambian env vars y, donde el código las lee, las URLs de wrappers OPS.

### Bloque E — Los 13 wrappers n8n a OPS
- **Qué hace:** importar los 13 wrappers a OPS (sufijo `__OPS`), firmados con el secreto de OPS, apuntando a las funciones del motor de OPS (ya vivas desde 8A-8D + Carril B). Credencial `vita_supabase_ops`. TEST antes que OPS para cada uno; smoke directo por wrapper.
- **Toca OPS:** 13 workflows n8n importados/configurados.
- **Fuente:** los 13 templates `portal-a*__TEMPLATE.json` (sanitizados, con `__PEGAR_*` para el secreto).

### Bloque F — Aviso 8C-bis en el A07 de OPS
- **Qué hace:** sobre el A07 OPS vivo (importado en E), agregar la rama lateral del aviso (+2 nodos, +1 conexión): gate anti-duplicado + `Call` al sub-workflow 8C-bis. El `Call` apunta al **8C-bis OPS `fHzMFj7pGMKuYEOb`**; el `entorno` se resuelve por **`leer_ambiente.valor`** (`configuracion_general('ambiente')` → `'ops'`), **sin hardcode** (D-C-72). `onError: continueRegularOutput`, Wait ON, nodo hoja (D-C-73).
- **Toca OPS:** el workflow A07 OPS (+2 nodos).
- **Fuente:** snippet de los 2 nodos `A07_aviso_8cbis__2_nodos_snippet.json` (sin secreto), paste quirúrgico. Verificar live-vs-template antes de anclar (L-C-25).

### Bloque G — Frontend OPS (build + deploy Vercel)
- **Qué hace:** (1) extender `src/lib/ambiente.ts` para reconocer el ref OPS (`lpiatqztudxiwdlcoasv`) → `'ops'` sin banner defensivo (P-FE-09); (2) reemplazar `CABANAS_TEST` por catálogo real — en OPS los IDs difieren por la secuencia SERIAL (P-FE-01); (3) build con env de OPS (`VITE_SUPABASE_URL` + anon de OPS), reutilizando el setup de Vercel D-FE-30; (4) deploy.
- **Toca OPS:** nada en Supabase/n8n; build/deploy en Vercel apuntando a OPS.
- **Fuente:** `src/lib/ambiente.ts`, `callPortal.ts`, `AuthProvider.tsx`, `actionRegistry.ts` + la constante de catálogo a reemplazar.

### Bloque H — Smokes read-only end-to-end en OPS
- **Qué hace:** fingerprint estructural TEST↔OPS de la infra del portal (huella idéntica, doble corrida del mismo script simétrico — D-PROMO-08); smokes read-only puros: login real por rol → `sesion.contexto` (menú correcto por jenny/vicky/socio) → una lectura por acción → verificación de allowlist (jenny rebota en económicos). **Un alta controlada de reserva** (con verificación de que sale el aviso 8C-bis y `entorno='ops'`). Anti-OPS: no ejecutar escrituras que consuman secuencias innecesariamente; preservar el arranque limpio (D-PROMO-09).
- **Toca OPS:** lecturas + un alta controlada de validación.
- **Fuente:** `PROMO_BLOQUE_K1_FINGERPRINT_ESTRUCTURAL.sql` + `PROMO_BLOQUE_K2_SMOKES_READONLY_OPS.sql` como plantilla.

### Bloque I — Bump canónico v1.9.0 (opcional según §4, decidido: SÍ)
- **Qué hace:** `6B_SCHEMA_SQL.md` → v1.9.0: nueva sección conceptual + PARTE C ejecutable (las 3 estructuras del portal, cuerpos post-validación) + changelog. Excluye la maquinaria de promoción y todo seed/secret/URL. Verificar bootstrap fresco (Parte B + Parte C) con harness local (L-PROMO-08).
- **Toca OPS:** nada (es documental).
- **Gate:** bootstrap en limpio reproduce las 3 estructuras + grants sin exposición.

### Closure ritual (post-bloques)
Propagación a satélites con `str_replace` quirúrgico (`count==1`), EOL por archivo:
- `ESTADO_ACTUAL_VITA_DELTA.md` (CRLF) — Carril C promovido a OPS + v1.9.0.
- `DECISIONES_NO_REABRIR.md` (LF) — sección nueva D-PROMO-C-XX (decisiones de promoción del Carril C); **+ propagar la deuda D-C-71…73** (aviso A07) **y D-C-64…70** (A10-MP, ver §8).
- `Lecciones_Aprendidas.md` (mixto→CRLF al final) — lecciones de la promoción del Carril C.
- `Pendiente_pre_produccion.md` (LF) — marcar CERRADOS P-FE-01, P-C-7, P-C-8, P-FE-09, P-C-9-en-OPS; sección de promoción del Carril C cerrada.
- `CLAUDE.md` (LF) — Carril C en OPS + canónico v1.9.0.
- `README.md` (LF) — según corresponda.

---

## 6. Gates de validación por capa

| Bloque | Gate (verde para avanzar) |
|---|---|
| **A** | Snapshot read-only OK; identidad por seed confirmada (cabañas 1-5 + `ambiente='ops'`); cero writes/DDL. DDL habilitado solo con A verde. |
| **B** | 3 estructuras creadas; assert duro D-C-34 PASS (service_role lee `portal_usuarios`; anon/authenticated NO); `portal_idempotencia` con PK+2 UNIQUE+FK+7 CHECK; función creada. Cero filas de identidad. |
| **C** | 5 usuarios Auth OPS creados; 5 filas en `portal_usuarios` con roles correctos; seed por email resolvió todos los `user_id` (cero NULL). |
| **D** | `portal-api` desplegado en OPS; preflight de env PASS (HMAC OPS presente, URLs OPS, CORS al origin real, no `*`); `sesion.contexto` responde por los 3 roles. |
| **E** | 13 wrappers `__OPS` importados; smoke directo por wrapper verde; cada uno apunta al motor OPS y firma con secreto OPS; action binding (key == EXPECTED_ACTION) verificado. |
| **F** | A07 OPS con +2 nodos; `Call`→`fHzMFj7pGMKuYEOb`; `entorno` resuelto a `'ops'` por `leer_ambiente.valor` (verificado en ejecución, no hardcode); no-afectación de la respuesta (aviso pineado para fallar → A07 igual `{ok:true}`). |
| **G** | Build OPS verde (`npm run typecheck` + `npm run build` EXIT 0); banner NO muestra el defensivo (reconoce OPS); catálogo real de cabañas (no `CABANAS_TEST`); deploy Vercel apuntando a OPS. |
| **H** | Fingerprint infra portal TEST↔OPS idéntico; smokes read-only por rol verdes; allowlist confirmada (jenny rebota en económicos); alta controlada OK + aviso 8C-bis disparado con `entorno='ops'`. |
| **I** | Canónico v1.9.0 entregado; bootstrap fresco reproduce las 3 estructuras + grants sin exposición a Data API. |

---

## 7. Qué toca OPS y qué no

| Bloque | Supabase OPS | n8n OPS | Vercel | Auth OPS | Repo/canónico |
|---|---|---|---|---|---|
| A | lectura | — | — | — | — |
| B | **DDL** (3 estructuras) | — | — | — | — |
| C | 5 filas seed | — | — | **5 usuarios** | — |
| D | Edge Fn + secrets | — | — | — | — |
| E | — | **13 wrappers** | — | — | — |
| F | — | A07 (+2 nodos) | — | — | — |
| G | — | — | **build+deploy** | — | front (ambiente.ts, catálogo) |
| H | lectura + 1 alta | (dispara aviso) | — | login | — |
| I | — | — | — | — | **v1.9.0** |

**Nunca se toca en esta promoción:** el motor de OPS (funciones `crear_prereserva`/`registrar_pago`/`confirmar_reserva`/`crear_bloqueo` — ya vivas), las tablas canónicas de OPS, el Carril B de OPS, el sub-workflow `vita_w8cbis_alerta__OPS` (se reusa tal cual), TEST (queda como referencia), DEV.

---

## 8. Deudas de propagación que arrastra esta etapa

Dos bloques de decisiones del Carril C ya están **bloqueadas en sus cierres** pero **todavía no propagadas a `DECISIONES_NO_REABRIR.md`**. El closure ritual de esta promoción es el momento de saldarlas (igual que el Carril B saldó las suyas al cerrar):

- **D-C-64…70** (A10-MP) — bloqueadas en `A10MP_CIERRE.md`; su propagación quedó pendiente como "cierre de propagación de A10-MP". **Nota de renumeración:** los comentarios del código desplegado citan provisionalmente D-C-61…64 por arrastre del parche, pero esos números ya están tomados por A04 (D-C-61/62/63) en el ledger — la numeración oficial es **D-C-64…70**. Corregir los comentarios del artefacto es un pendiente cosmético, a ejecutar solo si el artefacto se edita.
- **D-C-71…73** + **L-C-24/25** (aviso 8C-bis en A07) — bloqueadas en `AVISO_8CBIS_PORTAL_A07_CIERRE.md`; propagación pendiente como paso coordinado.

Se propagan en el closure ritual del Bloque I, no antes.

---

## 9. Rollback por bloque

Cada bloque es reversible de forma aislada. La promoción es **idempotente y reentrante**: si un bloque falla su gate, se revierte ese bloque y se reintenta, sin afectar los anteriores.

| Bloque | Rollback |
|---|---|
| **A** | Ninguno necesario (read-only puro, cero efectos). |
| **B** | `DROP TABLE IF EXISTS portal_idempotencia; DROP FUNCTION IF EXISTS portal_cargar_gasto_interno(jsonb); DROP TABLE IF EXISTS portal_usuarios;` (orden inverso a las FK: idempotencia antes que gastos_internos no aplica — la FK es idempotencia→gastos_internos canónica, que no se dropea). Sin filas de identidad creadas todavía → DROP limpio. |
| **C** | `DELETE FROM portal_usuarios WHERE …` (las 5 filas); deshabilitar/borrar los 5 usuarios Auth desde el Dashboard. La tabla queda creada (de B). |
| **D** | Re-deploy de la versión anterior del `portal-api` OPS, o eliminar la Edge Function. Los secrets de OPS se conservan/rotan según necesidad (no al repo). |
| **E** | Despublicar/eliminar los wrappers `__OPS` importados. TEST intacto. |
| **F** | Quitar los 2 nodos de la rama de aviso del A07 OPS (los 22 nodos originales quedan byte-idénticos — restaurar el A07 sin rama). El sub-workflow `vita_w8cbis_alerta__OPS` no se toca. |
| **G** | Revert del deploy en Vercel a la build anterior; `git revert` de los cambios en `ambiente.ts`/catálogo si ya se commitearon (Franco). |
| **H** | El alta controlada de validación se identifica y se revierte/anula según el patrón de teardown de TEST (`C_SLICE*_teardown.sql` adaptado), preservando el arranque limpio de OPS. Las lecturas no dejan efecto. |
| **I** | `git revert` del bump del canónico (vuelve a v1.8.1). Documental, sin efecto en runtime. |

> **Anti-OPS en cada DDL:** todo bloque con DDL lleva su gate `DO+RAISE` de ambiente/seed como pre-check y dentro de la transacción, para que un script no pueda correr contra el entorno equivocado.

---

## 10. Checklist de secretos / URLs / env vars (sin exponer valores)

> **Ningún valor real va al repo ni a los docs.** Templates sanitizados con prefijo `__PEGAR_*`; la verificación es por presencia/prefijo, nunca por contenido.

### 10.1 Secretos
| Ítem | Dónde vive | Regla | Estado |
|---|---|---|---|
| `VITA_HMAC_SECRET` (OPS) | Supabase secrets de OPS + nodos n8n OPS (embebido, sin plan de Variables) | **Mismo nombre** que TEST, **valor distinto** (D-C-33, P-C-8). Generar nuevo para OPS. Nunca al repo. | ⬜ a generar |
| Passwords de los 5 usuarios Auth OPS | Supabase Auth OPS (Dashboard) | Nunca al repo. Creados manualmente por Franco (D-C-32). | ⬜ a crear |
| Secret key de Supabase (OPS) | env del gateway OPS | Resolución defensiva `SUPABASE_SECRET_KEYS[default]` → legacy `SUPABASE_SERVICE_ROLE_KEY` (L-C-09). Prefijo `SUPABASE_` reservado. | ⬜ a configurar |

### 10.2 URLs / refs
| Ítem | Valor | Notas |
|---|---|---|
| OPS ref | `lpiatqztudxiwdlcoasv` | Para `ambiente.ts` (P-FE-09) y env del front. |
| TEST ref | `bdskhhbmcksskkzqkcdp` | Solo referencia; el banner TEST ya lo reconoce (D-FE-29). |
| URLs wrappers n8n OPS | `federicosecchi.app.n8n.cloud/...__OPS` | En el CATALOG del gateway OPS y/o env. Nunca con secreto en la URL. |
| Origin real del portal (CORS) | el dominio Vercel de OPS | Restringir CORS del gateway a este origin (P-C-7), no `*`. |
| Sub-workflow 8C-bis OPS | id `fHzMFj7pGMKuYEOb` | Destino del `Call` del A07 OPS (no es secreto; es id de workflow). |

### 10.3 Env vars del frontend (Vercel, build OPS)
| Var | Origen | Notas |
|---|---|---|
| `VITE_SUPABASE_URL` | proyecto OPS | URL del proyecto OPS. |
| `VITE_SUPABASE_ANON_KEY` (o equivalente) | proyecto OPS | anon key de OPS. Pública por diseño (anon), pero se configura en Vercel, no se hardcodea en el repo. |
| Setup Vercel | D-FE-30 | Reutiliza el pipeline existente con env de OPS. |

---

## 11. Inventario de artefactos a producir (esta promoción)

Por bloque, Claude produce y Franco ejecuta:

- **A:** `PROMO_C_BLOQUE_A_SNAPSHOT_OPS.sql` (read-only, gate por seed).
- **B:** `PROMO_C_BLOQUE_B_INFRA_OPS.sql` (3 estructuras + grants + asserts + gate ambiente).
- **C:** `PROMO_C_BLOQUE_C_SEED_USUARIOS_OPS.sql` (seed por email, emails reales — script operacional) + runsheet de creación de usuarios Auth.
- **D:** runsheet de deploy del gateway OPS (env, CORS, secrets) — el `index.ts` se reusa sin editar.
- **E:** runsheet de import de los 13 wrappers `__OPS` + smokes directos.
- **F:** runsheet del paste quirúrgico de los 2 nodos en A07 OPS + verificación live-vs-template.
- **G:** parche de `ambiente.ts` (P-FE-09) + reemplazo de catálogo (P-FE-01) + runsheet de build/deploy Vercel OPS.
- **H:** `PROMO_C_BLOQUE_H_FINGERPRINT.sql` + `PROMO_C_BLOQUE_H_SMOKES_READONLY_OPS.sql`.
- **I:** `6B_SCHEMA_SQL.md v1.9.0` + verificación de bootstrap.
- **Closure:** scripts byte-level de `str_replace` para los 6 satélites (EOL por archivo) + este plan archivado como `PROMOCION_CARRIL_C_OPS_*`.

---

## 12. Referencias

- **Método:** `PROMOCION_CARRIL_B_OPS_CIERRE.md` (D-PROMO-01…13 / L-PROMO-01…08).
- **Diseño backend:** `CARRIL_C_BACKEND_API_DISENO_CIERRE.md`.
- **Slices:** `C_SLICE0_CIERRE.md` → `C_SLICE3B_CIERRE.md`.
- **A10-MP:** `A10MP_CIERRE.md` (D-C-64…70).
- **Contrato frontend:** `CONTRATO_FRONTEND_PORTAL_CIERRE.md` / `CONTRATO_FRONTEND_PORTAL_v1.md`.
- **Frontend deploy:** `FRONTEND_SUBSLICE3_CIERRE.md` (P-FE-09, Vercel).
- **Aviso A07:** `AVISO_8CBIS_PORTAL_A07_CIERRE.md` (D-C-71…73 / L-C-24/25).
- **Pendientes:** `Pendiente_pre_produccion.md` (P-FE-01 / P-C-7 / P-C-8 / P-FE-09 / P-C-9).
- **Canónico:** `6B_SCHEMA_SQL.md v1.8.1`.
- **Arranque OPS:** `ARQUITECTURA_ETAPA_8_ARRANQUE_OPS.md` + `8A_CIERRE.md`.
- **Gateway a desplegar:** `A10MP_B2_portal-api_index.ts` (CATALOG 14).
- **Plantillas SQL de promoción:** `PROMO_BLOQUE_K1_FINGERPRINT_ESTRUCTURAL.sql`, `PROMO_BLOQUE_K2_SMOKES_READONLY_OPS.sql`.

---

*Plan de promoción del Carril C a OPS — propuesta. OPS intacto hasta aprobación. Una vez aprobado, arranca el Bloque A (snapshot read-only). Decisiones de promoción del Carril C se numerarán al cerrar; las decisiones conceptuales D-C-XX / D-FE-XX no se reabren.*
