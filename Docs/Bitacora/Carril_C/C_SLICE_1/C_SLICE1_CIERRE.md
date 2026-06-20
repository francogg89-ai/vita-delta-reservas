# CARRIL C — SLICE 1 (LECTURAS REUSE) — CIERRE

**Estado:** ✅ **Cerrado y verificado en TEST.** Slice 1 puso las **cinco primeras lecturas operativas** del Portal Operativo Interno sobre la espina de Slice 0: A03 (calendario de limpieza), A04 (calendario operativo), A05 (detalle de reserva), A06 (prereservas activas) y A12 (saldos de cobranza). Las cinco las sirve `portal-api` vía **wrappers n8n firmados** que revalidan en cinco dimensiones (HMAC · ts · rol · action · ambiente) y reusan lógica/vistas/queries existentes, **sin** invocar los webhooks viejos.
**Entorno de validación:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5.
**Entorno de operación:** — (Slice 1 **no** se promovió a OPS; el Carril C es independiente del Carril B y del canónico, y no toca OPS para experimentar).
**Fecha de cierre:** 2026-06-18.
**Base:** `C_SLICE0_CIERRE.md` (espina de seguridad; D-C-29…35) + `CARRIL_C_BACKEND_API_DISENO_CIERRE.md` (diseño Backend/API; D-C-01…28).
**Depende de:** D-C-29…35 (espina HMAC/JWT/allowlist/ambiente) + D-C-09/13/15/18/31/35 (contrato, gateway, error envelope).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.8.1` — **NO modificado por este cierre.** Las cinco acciones son **read-only** sobre el schema existente; no introducen DDL. `portal_usuarios` sigue siendo infra **TEST-only**, no promovida a OPS, no entra al canónico hasta una eventual promoción coordinada.
**Autores:** Franco (titular, ejecutor de **todos** los writes en Supabase y n8n) + Claude (arquitecto/copiloto; no tocó infraestructura — validó configs de nodos y queries contra el schema de la instancia, solo lectura).
**Decisiones registradas:** D-C-36 a D-C-49 🔒. **Lecciones:** L-C-10 a L-C-15.

---

## 1. Resumen ejecutivo

Slice 0 demostró que una persona se autentica una vez y cruza una frontera de confianza con doble defensa. Slice 1 puso a **operar las primeras lecturas** sobre esa frontera, reusando todo lo construido y sin reabrir nada del Carril B ni del canónico.

Cada acción es un **wrapper n8n firmado** clonado del patrón de la Fase C: `Webhook(rawBody) → validar_firma_ts_rol → leer_ambiente → verificar_acceso → IF → [lecturas Postgres] → render → Respond`. El wrapper **revalida** las cinco dimensiones de seguridad (HMAC sobre los bytes exactos del raw body — binario, L-C-05; ventana `ts` ±300 s; allowlist de rol propia; **action binding** `EXPECTED_ACTION`; `ambiente`) y reusa la lógica de negocio existente (queries, vistas, render), **sin** llamar a los webhooks viejos (D-C-36). El gateway `portal-api` impone la **allowlist doble** (CATALOG rol×action + allowlist del wrapper, D-C-39) y el **action binding** (key del CATALOG == `EXPECTED_ACTION`, D-C-41).

Hitos del slice: **primer `rol_no_permitido` real** (jenny → A04/A05/A06/A12 rebota **en el gateway antes de firmar**, sin tocar n8n); **primera acción con payload** (A05, `id_reserva` bindeado con `queryReplacement`, L-C-12); **primeros contratos JSON de lista** (A06/A12, con la semántica `filas:[]` ≠ `no_encontrado`, D-C-47). La validación fue **empírica y por bloque**: cada wrapper con su smoke directo (8 dimensiones de seguridad) y cada cableado con su smoke vía gateway (menú por rol + camino feliz + `no_autorizado`). Metodología estricta respetada: snapshot read-only → diseño aprobado → bloque por bloque → Franco ejecuta → verificación. **OPS y `6B_SCHEMA_SQL.md` intactos.**

---

## 2. Qué quedó construido en TEST

El gateway `portal-api` quedó con **6 entradas** en el CATALOG: 1 resuelta en la Edge (`sesion.contexto`, A02, de Slice 0) + **5 wrappers n8n** (las acciones de este slice). Deploy por Dashboard con **verify_jwt OFF** (L-C-06).

### 2.1 A03 `calendario.limpieza` — HTML (Bloques 1A · 2 · 3)
- Roles {jenny, vicky, socio} (la única que ve jenny). Wrapper `portal-a03-limpieza`, render **HTML** (`data:{formato:"html",html}`, D-C-09/38) con **escaping** de todo texto dinámico (nombre, teléfono, mascotas, detalle, notas). Sin payload (`payloadVacio`).
- **Bloque 1A** dejó lista la **infraestructura común del gateway** (preflight de `VITA_AMBIENTE`+`N8N_BASE_URL`, dispatch genérico n8n con validación estricta del envelope de vuelta, validadores de payload) **sin** cablear ninguna acción (fiel a D-C-31). Bloque 2 = wrapper (**7/7** directo). Bloque 3 = cableado (**3/3 + `no_autorizado`** vía gateway).

### 2.2 A04 `calendario.operativo` — HTML 120 días con montos (Bloques 4 · 5)
- Roles {vicky, socio}; **jenny excluida** (ve económicos, D-C-03/39). Wrapper `portal-a04-operativo` (gemelo de A03), render HTML con `ymd()` (hardening de fecha), `money()` y `esc()`; `onError:continueRegularOutput` en los Postgres (L-C-15). Sin payload.
- **Hito:** primer `rol_no_permitido` real — jenny → A04 rebota en el gateway. Smoke wrapper **8/8** + vía gateway **12/12**.

### 2.3 A05 `reserva.detalle` — JSON objeto, con payload (Bloques 6 · 7)
- Roles {vicky, socio}. Wrapper `portal-a05-detalle`. **Primera acción con payload** (`{id_reserva}`): el gateway valida `payloadIdReserva` (entero positivo seguro) **antes** de firmar, y el wrapper lo revalida y lo bindea como `$1` al Postgres node con `options.queryReplacement` (L-C-12).
- Lectura por **JOIN directo** `reservas JOIN cabanas JOIN huespedes` (D-C-44, no `vista_calendario`). Contrato `data:{reserva, pagos}` (D-C-43), montos crudos, `saldo_real` recomputado en SQL desde pagos confirmados sena/saldo (D-C-40). Huésped con nombre/teléfono/**email**; sin DNI ni notas internas. 0 filas → `no_encontrado`. Smoke wrapper **14/14** + vía gateway **17/17**.

### 2.4 A06 `prereservas.activas` — JSON lista (Bloques 8 · 9)
- Roles {vicky, socio}. Wrapper `portal-a06-prereservas`, lee **`vista_prereservas_activas`** (reuse, D-C-46), `ORDER BY expira_en, id_pre_reserva`. Contrato `data:{filas}` (D-C-47); sin payload. Smoke wrapper **8/8** + vía gateway **11/11** (TEST tenía 0 prereservas activas → `filas=0` es PASS válido, D-C-47).

### 2.5 A12 `cobranza.saldos` — JSON lista (Bloques 10 · 11)
- Roles {vicky, socio}. Wrapper `portal-a12-saldos`, reusa la **lógica de `vita_w09_listado_saldos`** (D-C-49): universo `reservas estado IN ('confirmada','activa') AND saldo_real > 0`; `saldo_real = monto_total − SUM(pagos confirmados sena/saldo)` (D-C-40/D-9B-05); pagos normalizados al reserva con **CTE de mapeo agrupada `reserva_por_prereserva` (`MIN`)** en vez de subquery escalar (no hay UNIQUE en `reservas.id_pre_reserva`); **sin la fila centinela** del workflow HTML; huésped con nombre/teléfono/email. Contrato `data:{filas}` (D-C-47); sin payload.
- Smoke wrapper **8/8** + vía gateway **sin fallos**; TEST tenía **3 reservas con saldo** (`filas=3`) en el directo y vía gateway. La query read-only del runsheet B10 permite verificar IDs y saldos contra Supabase si se desea conservar esa evidencia puntual (ver §6).

---

## 3. Bloques ejecutados (bitácora)

| Bloque | Acción | Qué | Resultado |
|---|---|---|---|
| **1A** | (infra) | gateway: preflight `VITA_AMBIENTE`+`N8N_BASE_URL`, dispatch n8n, validadores | sin acción cableada (D-C-31) |
| **2** | A03 | wrapper `portal-a03-limpieza` (HTML + escaping) | **7/7** directo |
| **3** | A03 | cableado en CATALOG | **3/3 + `no_autorizado`** |
| **4** | A04 | wrapper `portal-a04-operativo` (HTML montos, `onError` PG) | **8/8** directo |
| **5** | A04 | cableado + corrección TDZ (L-C-11) | **12/12** (hito `rol_no_permitido`) |
| **6** | A05 | wrapper `portal-a05-detalle` (JOIN directo, `queryReplacement`) | **14/14** directo |
| **7** | A05 | cableado (`payloadIdReserva` rebota en gateway) | **17/17** |
| **8** | A06 | wrapper `portal-a06-prereservas` (vista, lista) | **8/8** directo |
| **9** | A06 | cableado | **11/11** |
| **10** | A12 | wrapper `portal-a12-saldos` (CTE agrupada, lista) | **8/8** (3 filas reales) |
| **11** | A12 | cableado | **sin fallos** |

---

## 4. Decisiones registradas (D-C-36 a D-C-49) 🔒

> Convención del archivo: decisiones posteriores pueden **precisar o superar** partes operativas de decisiones anteriores; se conservan ambas y se indica qué parte queda vigente. En este slice, **D-C-42/43/44 refinan la porción de salida/fuente de A05 de D-C-40** (la regla de `saldo_real` de D-C-40 se mantiene vigente).

- **D-C-36** — Slice 1 cablea A03/A04/A05/A06/A12 vía wrappers n8n firmados (HMAC sobre raw body binario + ts ±300s + allowlist de rol + ambiente), reusando lógica/consultas/vistas/render existentes pero **sin** invocar los webhooks viejos. `portal-api` no rutea a ningún workflow que no revalide HMAC+rol+ambiente. A02 es la única acción Edge-only. Lectura directa desde la Edge = optimización futura, no default.
- **D-C-37** — `portal-api` resuelve su entorno por `VITA_AMBIENTE` ∈ {test,ops} e inyecta `ambiente_esperado` desde esa var (nunca del payload, D-C-16); ruteo a n8n por `N8N_BASE_URL`. Ambas entran al preflight duro de `resolveEnv()`: si falta cualquiera → 5xx ruidoso, sin default silencioso.
- **D-C-38** — Contratos de salida: A03/A04 → `data:{formato:"html",html}` (D-C-09); A06/A12 → `data:{filas:[...]}` (A06 ya es JSON nativo de la fuente; A12 deriva del rowset de saldos, sin la fila centinela del workflow HTML); A05 → objeto detalle. Objeto (A05) → `no_encontrado` si 0 filas; listas (A06/A12) → `data.filas=[]` sin error.
- **D-C-39** — Allowlist doble: gateway impone rol×action (CATALOG) y rebota `rol_no_permitido` antes de firmar; cada wrapper porta allowlist propia hardcodeada (segunda defensa). A03={jenny,vicky,socio}; A04/A05/A06/A12={vicky,socio}. Payload mínimo (D-C-18) validado en ambas capas: gateway antes de firmar, wrapper antes del Postgres node.
- **D-C-40** — A05-detalle = composición read-only acotada (lectura 8C-bis parametrizada por `id_reserva` + tablas existentes + `saldo_real` recomputado como A12 desde `pagos` confirmados sena/saldo, **no** `reservas.monto_saldo`). Campos originales: `id_reserva, cabana, fecha_checkin, fecha_checkout, hora_checkin, hora_checkout, personas, estado, huesped_nombre, huesped_telefono, monto_total, saldo_real`. `id_reserva` validado (entero positivo) en gateway y wrapper; 0 filas → `no_encontrado`; nunca cast error crudo al frontend. **Refinada por D-C-42/43/44 en la porción de salida/fuente de A05** (ver abajo). **Parte que queda como regla fuerte vigente:** `saldo_real = monto_total − pagos confirmados sena/saldo`; `reservas.monto_saldo` no es fuente operativa.
- **D-C-41** — Action binding: el wrapper exige `body.action === EXPECTED_ACTION`, y el key del CATALOG **debe** ser igual a `EXPECTED_ACTION` del wrapper. Quinta dimensión de validación (HMAC · ts · rol · **action** · ambiente).
- **D-C-42** — *(refina D-C-40)* A05 action congelada = **`reserva.detalle`** (sin sufijo). Roles {vicky, socio}. **Primera acción del portal con payload** (`{id_reserva}`): el gateway valida `payloadIdReserva` (entero positivo seguro, `Number.isSafeInteger`) antes de firmar; el wrapper lo revalida y lo bindea como `$1` al Postgres node vía `options.queryReplacement`.
- **D-C-43** — *(refina/supera D-C-40)* A05 contrato de salida = **JSON `data:{reserva, pagos}`**, montos numéricos crudos. **Incluye el bloque `pagos`** (líneas de pago confirmadas) — supera la porción de D-C-40 que no las exponía. El huésped **incluye `email`** además de nombre/teléfono; mantiene el criterio de privacidad (sin DNI ni notas internas).
- **D-C-44** — *(refina/supera D-C-40)* A05 estrategia de lectura = **JOIN directo** `reservas JOIN cabanas JOIN huespedes` (**no** `vista_calendario`, que filtra por estado/horizonte; **no** limitada a la lectura 8C-bis). `saldo_real` recomputado en SQL (LATERAL) desde pagos confirmados sena/saldo (regla vigente de D-C-40, que se conserva).
- **D-C-45** — A06 action congelada = **`prereservas.activas`**. Roles {vicky, socio}. Sin payload (`payloadVacio`).
- **D-C-46** — A06 fuente = **`vista_prereservas_activas`** (reuse, no query propia); SELECT explícito de columnas (no `SELECT *`), `ORDER BY expira_en, id_pre_reserva`. Contrato `data:{filas}` (D-C-47).
- **D-C-47** — **Semántica de listas:** en los contratos de lista (A06, A12), cero filas → `data:{filas:[]}` con `ok:true`, **nunca** `no_encontrado` (reservado a las acciones-objeto, p.ej. A05). Distingue "lista vacía" (resultado válido) de "objeto inexistente" (error). Concreta la parte de listas de D-C-38.
- **D-C-48** — A12 action congelada = **`cobranza.saldos`** (módulo de cobranza operativa). Roles {vicky, socio}. Sin payload (`payloadVacio`).
- **D-C-49** — A12 reusa la **lógica de `vita_w09_listado_saldos`**: universo `reservas estado IN ('confirmada','activa') AND saldo_real > 0`; `saldo_real = monto_total − SUM(pagos confirmados sena/saldo)` (D-C-40/D-9B-05); pagos normalizados al reserva por `COALESCE(id_reserva, vía id_prereserva)`, resuelto con **CTE de mapeo agrupada `reserva_por_prereserva` (`MIN(id_reserva)` GROUP BY `id_pre_reserva`)** en vez de subquery escalar (no hay UNIQUE en `reservas.id_pre_reserva` → un dato sucio explotaría la escalar; la CTE toma una de forma determinística); **sin la fila centinela** del workflow HTML (el JSON maneja la lista vacía con `filas:[]`, D-C-47). Huésped con nombre/teléfono/email (sin DNI ni notas).

---

## 5. Lecciones aprendidas (para `Lecciones_Aprendidas.md`)

> L-C-10 y L-C-11 se establecieron durante A03/A04 (sin propagar a satélites hasta este cierre); L-C-12 a L-C-15 son de A05/A06/A12.

- **L-C-10** — Detectar el placeholder del secreto HMAC por **prefijo** (`SECRET.startsWith('__PEGAR_')`), no por igualdad del string completo: en Modo B (n8n Cloud **sin** Variables) el secreto real se pega **reemplazando** el placeholder en el nodo `validar_firma_ts_rol`, y una comparación contra el string completo terminaría comparando el secreto contra sí mismo tras el reemplazo. El assert por prefijo sobrevive al reemplazo y aborta si te lo olvidás. El template commiteado queda sanitizado (con el placeholder); el secreto vive solo en el nodo de la instancia.
- **L-C-11** — En el gateway TypeScript, los validadores de payload (`payloadVacio`/`payloadIdReserva`) deben declararse **antes** del `const CATALOG` que los referencia: una `const` referenciada antes de su declaración cae en la temporal dead zone y tira `ReferenceError` en la carga del módulo (la Edge Function no levanta). Se corrige por **reorden**, sin tocar lógica/nombres/dispatch (mordió al derivar el gateway de A04 de B3).
- **L-C-12** — Para bindear parámetros en un Postgres node de n8n (acciones con payload, p.ej. A05), usar **`options.queryReplacement`** (typeVersion 2.6) con `$1` en la query y el valor desde el nodo de validación: `queryReplacement = "={{ $('validar_firma_ts_rol').first().json.id_reserva }}"`. Un solo parámetro **entero** esquiva el bug de parsing de comas (#14955) de la lista de replacements. El campo es `options.queryReplacement` (verificado contra la fuente de n8n), no un parámetro de query suelto.
- **L-C-13** — **Semántica de listas vs objeto en contratos JSON** (D-C-47): la lista vacía es un resultado **válido** (`filas:[]`, `ok:true`), no un error; `no_encontrado` queda para acciones-objeto. Consecuencia de testing: el smoke de una acción-lista debe **pasar con `filas=0`** — no se crean fixtures "para tener datos". (A06 cerró con `filas=0` real en TEST; A12 además ejerció el camino poblado con 3 filas reales.)
- **L-C-14** — Al reusar una query que normaliza pagos por prereserva, resolver el mapeo `prereserva→reserva` con una **CTE agrupada (`MIN(id_reserva)` GROUP BY `id_pre_reserva`)**, no con subquery escalar: **no hay UNIQUE en `reservas.id_pre_reserva`**, así que un dato sucio (dos reservas por una prereserva) haría explotar la escalar (`more than one row`); la CTE toma una de forma determinística. **Nota de robustez A05↔A12:** A05 suma pagos solo por `id_reserva`; A12 normaliza vía el fallback de prereserva. En el **flujo normal coinciden**, porque `confirmar_reserva` (paso 8) backfillea `pagos.id_reserva` al convertir; difieren solo en el borde de un pago con `id_prereserva` y `id_reserva` NULL sin backfillear (legacy/dato sucio), donde A12 es más completo. No es bug de A05 en el flujo normal; alinear A05 a esa normalización sería decisión futura, fuera de este slice.
- **L-C-15** — Los nodos Postgres de los wrappers (lecturas + `leer_ambiente`) usan **`onError:continueRegularOutput` + `alwaysOutputData`** (lecturas además `executeOnce`): un error de query **degrada** a un envelope limpio (`error_interno` / `ambiente_incorrecto`) en vez de colgar el workflow. El template de A03 lo había perdido y se restauró en A04; es parte del molde de todos los wrappers.

---

## 6. Evidencia de pruebas

Cada **wrapper** tiene su smoke directo (8 dimensiones: rol habilitado ×2, `rol_no_permitido` ×2, firma inválida, `ts` viejo, ambiente cruzado, action ajena), y cada **cableado** su smoke vía gateway (menú por rol en `sesion.contexto` + camino feliz + `no_autorizado`):

| Acción | Wrapper directo | Vía gateway | Nota |
|---|---|---|---|
| A03 `calendario.limpieza` | 7/7 | 3/3 + `no_autorizado` | 3 roles habilitados |
| A04 `calendario.operativo` | 8/8 | 12/12 | hito `rol_no_permitido` (jenny) |
| A05 `reserva.detalle` | 14/14 | 17/17 | payload `id_reserva`; `no_encontrado` para id inexistente; 5 payloads inválidos rebotan en gateway |
| A06 `prereservas.activas` | 8/8 | 11/11 | `filas=0` real en TEST = PASS (D-C-47) |
| A12 `cobranza.saldos` | 8/8 | sin fallos | camino poblado: `filas=3` en directo y vía gateway (evidencia read-only abajo) |

**Evidencia read-only verificada (A12).** La query read-only del runsheet B10, corrida sobre TEST, devolvió **3 filas** coincidentes con `filas=3` del smoke (directo y vía gateway), con `saldo_real` recomputado desde pagos confirmados (D-C-40) y orden `fecha_checkin, id_reserva`:

| `id_reserva` | cabaña | `monto_total` | `total_pagado_confirmado` | `saldo_real` |
|---|---|---|---|---|
| 13 | Madre Selva | 200000 | 150000 | 50000 |
| 8 | Tokio | 150000 | 75000 | 75000 |
| 9 | Tokio | 150000 | 75000 | 75000 |

En todas: jenny (cuando no está habilitada) → `rol_no_permitido` **en el gateway** sin tocar n8n; sin JWT → `no_autorizado`; firma/`ts`/ambiente/action validados en el wrapper.

---

## 7. Supuestos y límites del slice

- Slice 1 = **solo lecturas**. Escrituras (Slice 2: A07/A08/A10), lecturas nuevas (Slice 3a: A24 histórico / A25 ingresos), gastos (Slice 3b: A11/A13) quedan **fuera**.
- El **contrato HTML** de A03/A04 es temporal (D-C-09); el contrato **JSON formal** de calendarios es post-MVP (P-C-3).
- **Cobertura A06:** el camino poblado **no se ejerció** en TEST (0 prereservas activas al cierre); se verá cuando aparezca una, o con un fixture aprobado. A12 sí ejerció el camino poblado con datos reales.
- **A05↔A12 normalización de pagos:** coinciden en el flujo normal (ver L-C-14); alinear A05 a la normalización por prereserva sería decisión futura, no abierta en este slice.
- Los **2 comentarios stale** del CATALOG (`Bloque 1A NO agrega ninguna` y `A04/A05/A06/A12 se agregan al cablearse`) se dejaron a propósito durante el slice; se limpian al commitear el `index.ts` final de este cierre.

---

## 8. Pendientes y handoff

- **→ Slice 2** (escrituras reuse A07/A08/A10): primer uso del helper HMAC para **escrituras**; aparece la tabla de unicidad de `nonce` en la primera escritura no-idempotente sin guard (realísticamente A11, más adelante).
- **Limpieza de CATALOG:** quitar los 2 comentarios stale al commitear el `index.ts` final (parte de la propagación de este cierre).
- **Cobertura A06:** ejercer el camino poblado cuando exista una prereserva activa (o fixture aprobado).
- **A05↔A12:** evaluar (futuro) alinear el cómputo de `saldo_real` de A05 a la normalización por prereserva de A12.
- **Hardening pre-OPS** (sigue abierto, P-C-7…11): restringir **CORS** al origin del portal; generar `VITA_HMAC_SECRET` de **OPS** distinto del de TEST; **store de nonce** persistente; **rol Postgres dedicado** de mínimos en lugar de `service_role`; migrar `portal-api` a CLI + `config.toml` si los redeploys se vuelven frecuentes (L-C-06).

---

## 9. Deltas para documentos satélite (aplicar tras auditar este cierre)

- **`DECISIONES_NO_REABRIR.md`** (LF) — agregar **subsección "Carril C — Slice 1"** con **D-C-36 … D-C-49**, antes de "## Lecciones operativas n8n consolidadas". Slice 0 no agregó decisiones nuevas → no se toca esa parte.
- **`Lecciones_Aprendidas.md`** (MIXTO; bloque L-C en CRLF) — agregar **L-C-10 … L-C-15** después de L-C-09, con EOL CRLF.
- **`ESTADO_ACTUAL_VITA_DELTA.md`** (CRLF) — nuevo "Etapa actual: **Slice 1 cerrada 2026-06-18**"; el bloque de **Slice 0** baja de "actual" a "previa".
- **`CLAUDE.md`** (LF) — entrada de cierre de **Slice 1** después de la de Slice 0, mismo formato.
- **`README.md`** (LF) — actualizar el estado ("Al 2026-06-18", sumar Slice 1) y corregir la línea **stale** que dice "construcción sin empezar / D-C-01…28 / v1.8.0".
- **`Pendiente_pre_produccion.md`** — **sin cambios** (P-C-1…11 siguen abiertos; decisión explícita de Franco de dejarlo intacto).
- **`6B_SCHEMA_SQL.md`** y **OPS** — **sin cambios** (Carril C no toca el canónico; lecturas read-only sobre el schema existente).
- **Commit:** los 5 `__TEMPLATE.json` de wrapper + el `index.ts` final (con los 2 comentarios stale limpiados) + los smokes, sanitizados.

---

## 10. Inventario de artefactos de la etapa

- **A03:** `C_SLICE1_B1A_portal-api_index.ts`, `C_SLICE1_B2_*` (wrapper `portal-a03-limpieza__TEMPLATE.json` + smoke), `C_SLICE1_B3_portal-api_index.ts` + smoke vía gateway + runsheets.
- **A04:** `portal-a04-operativo__TEMPLATE.json`, `C_SLICE1_B4_smoke_a04_directo.ps1`, `C_SLICE1_B5_portal-api_index.ts`, `C_SLICE1_B5_smoke_a04_via_portal.ps1` + runsheets.
- **A05:** `portal-a05-detalle__TEMPLATE.json`, `C_SLICE1_B6_smoke_a05_directo.ps1`, `C_SLICE1_B7_portal-api_index.ts`, `C_SLICE1_B7_smoke_a05_via_portal.ps1` + runsheets.
- **A06:** `portal-a06-prereservas__TEMPLATE.json`, `C_SLICE1_B8_smoke_a06_directo.ps1`, `C_SLICE1_B9_portal-api_index.ts`, `C_SLICE1_B9_smoke_a06_via_portal.ps1` + runsheets.
- **A12:** `portal-a12-saldos__TEMPLATE.json`, `C_SLICE1_B10_smoke_a12_directo.ps1`, `C_SLICE1_B11_portal-api_index.ts` (gateway final del slice), `C_SLICE1_B11_smoke_a12_via_portal.ps1` + runsheets.
- **Cierre:** este documento (`C_SLICE1_CIERRE.md`).
