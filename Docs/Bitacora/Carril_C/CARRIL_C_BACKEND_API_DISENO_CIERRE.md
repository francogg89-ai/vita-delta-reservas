# CARRIL C — BACKEND/API VÍA n8n — CIERRE (ETAPA DE DISEÑO)

**Etapa:** Carril C / Portal Operativo Interno — **Backend/API vía n8n**. Etapa de **diseño** (contratos, identidad/seguridad, alcance MVP, estrategia de pruebas). Primera etapa del Carril C.
**Estado:** ✅ **Cerrada (diseño).** **No se construyó nada** — sin workflows, sin Edge Function, sin código. **OPS intacto. Schema intacto (sin bump).**
**Fecha de cierre:** 2026-06-15.
**Ámbito:** 100% documental / de diseño. Claude actuó como **arquitecto y auditor**: produjo el catálogo de contratos, la matriz rol×endpoint, el modelo de identidad/frontera de confianza, el alcance MVP por slices y la estrategia de pruebas. **No hubo writes que ejecutar** (etapa de diseño); en la etapa de construcción, Franco ejecuta todos los writes (Supabase, n8n).
**Carril:** C — **independiente del Carril B**. No reabre 9C→9H, no toca el canónico, no toca OPS.
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md` **v1.8.0 — no modificado, sin bump** (Carril C no introduce DDL en esta etapa).
**Autores:** Franco (titular) + Claude (arquitecto).
**Decisiones registradas:** D-C-01 … D-C-28. **Lecciones:** L-C-01 … L-C-04.

> **Qué NO reabre este cierre.** No redefine el Carril B (9C→9H conservan su numeración `D-9x`), ni `D-PROMO`, ni `D-NEG`. Las funciones SQL del motor de reservas y del Carril B se **envuelven**, no se reescriben ni se duplican en n8n.

---

## 1. Resumen ejecutivo

Esta etapa diseñó **todo el contrato portal → gateway → n8n** del Portal Operativo Interno: un catálogo cerrado de **25 acciones** (A01–A25), su **matriz rol×endpoint**, el **modelo mínimo de identidad y frontera de confianza** (Supabase Auth + tabla `portal_usuarios` + una **Edge Function `portal-api`** como gateway/BFF que firma llamadas **HMAC** a n8n y valida entorno), el **andamiaje común de contrato** (entrada/éxito/error uniforme), el **alcance MVP por slices verticales** y la **estrategia de pruebas en TEST**.

El principio rector que ordena todo: **el frontend es zona no confiable** (no guarda secretos, no firma, no decide permisos); la frontera de confianza vive en la Edge Function; **n8n queda como backend invisible** y revalida como segunda defensa; **una sola autenticación humana**.

**No se construyó nada.** La próxima etapa arranca por **Slice 0 sobre TEST** (la espina de seguridad). OPS no se tocó. El schema no se tocó.

---

## 2. Qué se diseñó (entregables)

- **Inventario de 25 acciones** (A01–A25) por módulo, tipo (R/W), reuse/nuevo y flag MVP.
- **Matriz rol × endpoint** (`jenny` / `vicky` / `socio`).
- **Modelo mínimo de identidad y frontera de confianza** portal ↔ n8n (Fase 0.5).
- **Andamiaje común de contrato**: entrada (`action`+`payload`), respuesta de éxito `{ok:true,data}`, **contrato de error uniforme** `{ok:false,error:{code,message,detail}}`.
- **Alcance MVP por slices** (Slice 0 → 3b) + menor slice operable.
- **Estrategia de pruebas en TEST** (aislamiento, reversibilidad, no-contaminación de julio, bordes transversales).

---

## 3. Catálogo de acciones (snapshot autoritativo — 25 acciones)

R = lectura, W = escritura. *Reusa* = workflow/función existente; *Nuevo* = falta crear. MVP = mínimo operable.

| Módulo | ID | Acción | R/W | Reusa / Nuevo | Workflow n8n / función SQL | MVP |
|---|---|---|---|---|---|---|
| Sesión | A01 | Autenticación del portal — proveedor y frontera de confianza definidos en Fase 0.5 | — | Nuevo (infra) | Supabase Auth + Edge Function | ✅ |
| Sesión | A02 | Home / menú por rol (`sesion.contexto`) | R | Nuevo (solo Edge Fn) | Lookup `portal_usuarios` | ✅ |
| Calendarios | A03 | Calendario de limpieza | R | Reusa | `vita_w8c_html_limpieza` | ✅ |
| Calendarios | A04 | Calendario operativo (4 meses) | R | Reusa | `vita_w8c_html_operativo` | ✅ |
| Reservas | A05 | Detalle de reserva | R | Reusa | lectura 8C-bis (por `id_reserva`) | ✅ |
| Reservas | A06 | Prereservas activas | R | Reusa | `vita_w07_vistas_operativas` | ✅ |
| Reservas | A07 | Crear reserva manual (flujo completo) | W | Reusa | `vita_w8b_carga_reserva` → `crear_prereserva`→`registrar_pago`→`confirmar_reserva` | ✅ |
| Bloqueos | A08 | Crear bloqueo | W | Reusa | `vita_w8d_bloqueo` → `crear_bloqueo` | ✅ |
| Bloqueos | A09 | Editar / levantar bloqueo | W | Nuevo | No existe hoy (8D solo crea) | ◻ futuro |
| Pagos | A10 | Registrar pago post-reserva | W | Reusa | `vita_w09_cobranza_posterior` → `registrar_pago` + cobranza transaccional | ✅ |
| Gastos | A11 | Cargar gasto interno (workflow controlado) | W | Nuevo | INSERT `gastos_internos` con validaciones | ✅ |
| Ingresos (R) | A25 | Ingresos cobrados por período | R | Nuevo | lectura `reservas`+`pagos` (apoyo opcional 9A); sin lógica societaria | ✅ |
| Contab. (R) | A13 | Gastos por período | R | Nuevo | reporte de gastos/incidencia (9F/9G) | ✅ |
| Contab. (R) | A12 | Saldos de cobranza (reservas con saldo pendiente) | R | Reusa | `vita_w09_listado_saldos` | ✅ |
| Histórico | A24 | Histórico operativo de reservas (nuevo sistema) | R | Nuevo | buscador `reservas`+`huespedes`+`pagos`, floor server-side | ✅ |
| Contab. (R) | A14 | Cascada del período | R | Nuevo | `cascada_periodo` (9G) | ◻ |
| Contab. (R) | A15 | Saldo socios del período | R | Nuevo | `saldo_socios_periodo` (9G) | ◻ |
| Contab. (R) | A16 | Detalle de participación | R | Nuevo | `detalle_participacion` (9E) | ◻ |
| Contab. (R) | A17 | Cuenta corriente / mayor por socio | R | Nuevo | `mayor_socio` / `saldo_corriente_socio` (9H) | ◻ |
| Contab. (R) | A18 | Resumen contable del período (cascada/matriz/mayor) | R | Nuevo | composición 9E/9G/9H | ◻ |
| Contab. (W) | A19 | Registrar snapshot de liquidación | W | Nuevo | `registrar_snapshot_periodo` (9H) | ✖ posterior |
| Contab. (W) | A20 | Registrar retiro | W | Nuevo | `registrar_retiro` (9H) | ✖ posterior |
| Contab. (W) | A21 | Registrar movimiento manual | W | Nuevo | `registrar_movimiento_manual` (9H) | ✖ posterior |
| Contab. (W) | A22 | Registrar reversa | W | Nuevo | `registrar_reversa` (9H) | ✖ posterior |
| Contab. (W) | A23 | Registrar revaluación ARS→USD | W | Nuevo | `registrar_revaluacion` (9H) | ✖ posterior |

**Notas de catálogo:**
- **A25 ingresos** (plata que entró, por fecha de pago) y **A13 gastos** (plata que salió, por período) son las dos lecturas operativas de período, ambas `vicky`+`socio`, **sin cascada**. La contabilidad societaria (A14–A18) es otro plano.
- **A07** usa el flujo 8B completo; el portal **no** expone "crear prereserva suelta" (D-C-06).
- **A11** es **workflow controlado**, no INSERT pelado (D-C-10): espeja las 18 constraints de `gastos_internos` para devolver error humano.
- **Calendarios (A03/A04):** contrato **temporal HTML** en el MVP (D-C-09); el contrato formal JSON queda post-MVP.

---

## 4. Matriz rol × endpoint

`socio` = Franco / Rodrigo / Remo. La matriz es de **permisos** (independiente del timing MVP). Es de aplicación real: el gateway la impone en cada llamada y n8n la revalida (defensa en profundidad).

| Acción | jenny | vicky | socio |
|---|:--:|:--:|:--:|
| A01 Autenticación · A02 Menú por rol | ✓ | ✓ | ✓ |
| A03 Calendario de limpieza | ✓ | ✓ | ✓ |
| A04 Calendario operativo | — | ✓ | ✓ |
| A05 Detalle de reserva | — | ✓ | ✓ |
| A06 Prereservas activas | — | ✓ | ✓ |
| A07 Crear reserva manual (flujo completo) | — | ✓ | ✓ |
| A08 Crear bloqueo | — | ✓ | ✓ |
| A09 Editar / levantar bloqueo *(futuro)* | — | ✓ | ✓ |
| A10 Registrar pago post-reserva | — | ✓ | ✓ |
| A11 Cargar gasto interno | — | ✓ | ✓ |
| A12 Saldos de cobranza | — | ✓ | ✓ |
| A13 Gastos por período | — | ✓ | ✓ |
| A24 Histórico operativo de reservas | — | ✓ | ✓ |
| A25 Ingresos cobrados por período | — | ✓ | ✓ |
| A14 Cascada del período | — | — | ✓ |
| A15 Saldo socios del período | — | — | ✓ |
| A16 Detalle de participación | — | — | ✓ |
| A17 Cuenta corriente / mayor por socio | — | — | ✓ |
| A18 Resumen contable del período | — | — | ✓ |
| A19–A23 Contabilidad con escritura | — | — | ✓ |

**Lecturas operativas de verificación de Vicky:** A05/A06 + A12 + **A25 (ingresos)** + **A13 (gastos)** + A24 (histórico).
**Visibilidad de datos sensibles:** Jenny ve cabaña/fechas/personas + **nombre y teléfono** (puede hacer check-in a futuro, D-C-02), sin datos contables/financieros; Vicky ve contacto y montos a nivel reserva/pago/gasto, **no** el reparto por socio; `socio` ve todo, incluida la distribución.

---

## 5. Modelo de identidad y frontera de confianza (resumen)

**Frontera de confianza = Supabase Edge Function `portal-api`** (gateway/BFF). El builder (Lovable u otro) puede ser el frontend visual, **no** la frontera de confianza.

**Flujo de referencia:**
```
frontend → Supabase Auth → Edge Function portal-api → webhook n8n firmado (HMAC) → Postgres vía credencial n8n
```

**Orden de validación en la Edge Function** (toda acción): verifica JWT → `user_id`; `SELECT rol, activo FROM portal_usuarios` (inexistente/`activo=false` ⇒ `no_autorizado`); `action` en catálogo (si no, `accion_desconocida`); `rol` en allowlist de la acción (si no, `rol_no_permitido`); forma mínima del payload (si no, `payload_invalido`); rutea al webhook **del entorno del deploy**, firmando payload + claim `rol` (aseverado por el server) + `ts`/`nonce` + **HMAC**.

**Revalidación en n8n** (segunda defensa): HMAC válido → rol en allowlist del workflow → `configuracion_general('ambiente')` == entorno esperado → ejecuta función/vista as owner → lee `item.resultado` (envelope del Postgres node) → devuelve.

**Identidad:** Supabase Auth + tabla `portal_usuarios(user_id→auth.users, nombre, rol ∈ {jenny,vicky,socio}, activo, created_at)`. Rol resuelto **server-side**; no se confía en roles del navegador. **Tabla > custom claims** (auditable, cambia permisos sin refrescar tokens). `creado_por`/`validado_por` = **identificador de la persona** (`vicky`/`franco`/`rodrigo`/`remo`), no el rol (D-C-22).

**Entorno:** por **deploy/URL/credenciales**, no por payload. Los IDs de cabaña 1-5 **no** discriminan TEST de OPS (iguales en ambos, L-7B-01); el discriminador es el marcador `ambiente` + credenciales/URLs separadas.

**Andamiaje de contrato (D-C-18):**
- Entrada: `POST /functions/v1/portal-api` + `Authorization: Bearer <jwt>` + `{action, payload}`.
- Éxito: `{ "ok": true, "data": <…> }`.
- Error uniforme: `{ "ok": false, "error": { "code", "message", "detail" } }`. Códigos base: `no_autorizado`, `rol_no_permitido`, `accion_desconocida`, `payload_invalido`, `no_encontrado`, `conflicto`, `error_entorno`, `error_interno`. **Nunca** error crudo de Postgres al navegador.

**Idempotencia de escrituras (heredada, caracterizada por función):**

| Acción | Idempotencia | Mecanismo | Reintento |
|---|---|---|---|
| A07 reserva | Fuerte | `idempotency_key` (crear_prereserva) | Seguro (manual/controlado, no auto) |
| A08 bloqueo | Ninguna | guard natural EXCLUDE | No dup (rebota `conflicto`); sin auto-retry |
| A10 cobranza | Débil / no atómica entre eventos | transaccional por evento; anti-dup de capa (D-9B-07) | No auto-retry; incierto → conservador |
| A11 gasto | Ninguna, sin guard | detección preventiva 24 h (D-C-23) | No; advertir-y-confirmar |

**`pct_operativo`** nunca lo manda/sugiere el frontend: lo inyecta el server-side desde config/decisión vigente (25% este ciclo, D-NEG-01) — decisión de seguridad (D-C-19).

---

## 6. Decisiones registradas (D-C-01 … D-C-28)

> Fuente autoritativa para `DECISIONES_NO_REABRIR.md` (cada una se archiva con 🔒). Algunas refinan a otras (se indica); se conservan ambas porque marcan el principio (Fase 0/0.5) y su realización concreta.

- **D-C-01** — Fuente de roles/permisos del portal: Sección 8 + Apéndice A del prompt + README + prompt de arranque. Sin brief específico por ahora; reconciliable si aparece, sin bloquear.
- **D-C-02** — Jenny: usa el workflow de limpieza existente; ve cabaña/fechas/personas + **nombre y teléfono** (puede hacer check-in a futuro); sin datos contables/financieros; sin acceso al resto del portal.
- **D-C-03** — Vicky: resumen operativo de cargas (reservas, pagos, saldos de cobranza, gastos cargados, histórico, ingresos). **No** ve cascada, matriz, participación, saldo por socio ni mayor.
- **D-C-04** — `socio` (Franco/Rodrigo/Remo): acceso total. Contabilidad con escritura (A19–A23) fuera del MVP.
- **D-C-05** — El portal **no** crea acciones de negocio nuevas; las nuevas (A11 gasto, A24 histórico, A25 ingresos) operan sobre el schema existente sin reabrir 9C→9H ni tocar el canónico.
- **D-C-06** — A07: "Crear reserva manual (flujo completo)" vía form 8B (prereserva→pago→confirmación encadenados). El portal **no** expone "crear prereserva suelta".
- **D-C-07** — Seguridad base: el navegador **no** llama directo a n8n para acciones sensibles; debe existir un componente server-side que guarde el secreto y firme/revalide. *(Concretado en D-C-13.)*
- **D-C-08** — Entorno: el portal **no** elige TEST/OPS por payload. URLs/credenciales separadas por entorno + n8n valida `configuracion_general('ambiente')` antes de ejecutar. *(Concretado en D-C-16.)*
- **D-C-09** — Calendarios: contrato temporal HTML (reusa, MVP) ≠ contrato formal JSON (frontend renderiza). El HTML no es contrato API definitivo.
- **D-C-10** — A11 (gasto interno): **workflow controlado** con validaciones (rol, clase A/C/D/E, período, pagador, zona/cabaña, `creado_por`, entorno, constraints; `source_event` a nivel workflow). Sin idempotencia fuerte.
- **D-C-11** — A24 (histórico): read-only; roles `vicky`+`socio` (Jenny sin acceso); fuente `reservas`+`huespedes`+`pagos`; **floor `fecha_in ≥ 2026-07-01` server-side** (no solo UI); nada pre-julio se muestra/importa/liquida/arrastra/recontabiliza; formato v1 listado/buscador; filtros recortables, floor no negociable.
- **D-C-12** — A09 (editar/levantar bloqueo): no existe hoy (8D solo crea, D-8D-09); capa futura, fuera del MVP.
- **D-C-13** — Frontera de confianza = **Supabase Edge Function** (BFF/gateway). El builder puede ser frontend visual, no frontera de confianza. Flujo: frontend → Supabase Auth → Edge Function (`portal-api`) → webhook n8n firmado → Postgres vía credencial n8n. *(Concreta D-C-07.)*
- **D-C-14** — Identidad: **Supabase Auth + tabla `portal_usuarios`** (`user_id`→`auth.users`, `nombre`, `rol ∈ {jenny,vicky,socio}`, `activo`, `created_at`). La Edge Function valida el JWT, resuelve rol server-side, no confía en roles del navegador. **Tabla > custom claims**.
- **D-C-15** — **Gateway único `portal-api`** (`action`+`payload`) + **workflows n8n separados por acción**. Validación primaria en la Edge Function; cada workflow **revalida** HMAC + rol + `ambiente` + payload (segunda defensa).
- **D-C-16** — Entorno por **deploy/URL/credenciales**, no por payload; n8n valida `configuracion_general('ambiente')` antes de ejecutar. *(Concreta D-C-08.)*
- **D-C-17** — Toda escritura registra `source_event` + `creado_por`: **siempre a nivel evento/workflow**, y a nivel **fila cuando la tabla lo soporte**. A11 es excepción a nivel fila (ver D-C-24).
- **D-C-18** — Andamiaje común Fase 1: `POST /functions/v1/portal-api` + `Bearer` JWT + body `{action,payload}`; orden JWT→lookup `portal_usuarios`→allowlist rol×action→payload mínimo→ruteo HMAC+ts/nonce; n8n revalida HMAC+rol+`ambiente`+payload; éxito `{ok:true,data}`; error `{ok:false,error:{code,message,detail}}`; nunca error crudo de Postgres. Códigos base: `no_autorizado`, `rol_no_permitido`, `accion_desconocida`, `payload_invalido`, `no_encontrado`, `conflicto`, `error_entorno`, `error_interno`.
- **D-C-19** — `pct_operativo` **nunca** del frontend; inyectado server-side desde config/decisión vigente (25%, D-NEG-01). Decisión de seguridad, no de comodidad.
- **D-C-20** — A24 floor: el gateway **recorta** `fecha_desde` < 2026-07-01 a 2026-07-01 (no rechaza); el data layer tiene floor duro `fecha_in ≥ 2026-07-01`.
- **D-C-21** — A13 `contab.gastos_periodo` entra al **MVP** (`vicky`+`socio`): lectura operativa de gastos cargados por período, sin cascada/matriz/saldo por socio/mayor. A14–A18 post-MVP solo `socio`; A19–A23 post-MVP solo `socio`.
- **D-C-22** — Identidad del operador: `creado_por`/`validado_por` de la sesión autenticada = **identificador de la persona** (`vicky`/`franco`/`rodrigo`/`remo`), no el rol. En A10 reemplaza el dropdown del form; el usuario no elige validador.
- **D-C-23** — A11 anti-duplicado: detección preventiva con clave natural `pagador+clase+monto+periodo+etiqueta+fecha`, ventana **24 h**, modo **advertir-y-confirmar** (no bloqueo). Confirmación explícita permite cargar igual (dos gastos legítimos iguales son posibles). Sin `idempotency_key` persistente; no reabre 9F.
- **D-C-24** — A11 `source_event`: **excepción consciente a nivel fila** — `gastos_internos` no tiene columna `source_event` (D-9F-14); traza de fila = `creado_por`+`created_at`; el `source_event` vive en el log del workflow n8n; **no** se escribe en `comentario` (no contaminar campo de negocio con metadata técnica).
- **D-C-25** — Política de reintentos del gateway: **no auto-reintenta escrituras**; timeout / estado incierto / error de verificación → código conservador + el frontend indica verificar antes de reintentar; nunca recarga ni reenvía automático. A07 (idempotencia fuerte heredada): reintento manual/controlado, nunca auto-retry ciego.
- **D-C-26** — Priorización MVP por slices verticales: **Slice 0** (espina de seguridad: Supabase Auth + `portal_usuarios` + Edge Function `portal-api` + JWT→rol→allowlist + HMAC→n8n + validación de ambiente + `sesion.contexto`) → **Slice 1** (lecturas reuse A03/A04/A05/A06/A12) → **Slice 2** (escrituras reuse A07/A08/A10) → **Slice 3a** (lecturas nuevas: A24 histórico; A25 ingresos se suma por D-C-27) → **Slice 3b** (gastos A11 + A13 verificación). Menor slice operable = **Slice 0 + A03**. Fuera del MVP: A09, A14–A18, A19–A23. A11 último.
- **D-C-27** — A25 `ingresos.cobrados_periodo`: read-only, `vicky`+`socio`, MVP, fuente `reservas`+`pagos`, **Nuevo** (envuelve consulta/reporte simple, sin lógica societaria). Separación de catálogo: **A25 ingresos** / **A13 gastos** / **A14–A18 societario**. No reparto, no matriz, no saldo por socio, no cascada (coherente con D-9F-20). Se prioriza junto a A24 en Slice 3a.
- **D-C-28** — Pruebas TEST: `periodo='2099-01-01'` como **período sintético** para los gastos A11 de prueba (garantía extra anti-contaminación), siempre con sentinel + teardown verificado.

---

## 7. Alcance MVP por slices

| Slice | Contenido | Driver | Naturaleza |
|---|---|---|---|
| **0** | Espina de seguridad: Supabase Auth + `portal_usuarios` + Edge Function `portal-api` (JWT→rol→allowlist→HMAC→ambiente→error envelope) + `sesion.contexto` (A02) | todos | infra + 1er vertical end-to-end |
| **1** | Lecturas reuse: A03, A04, A05, A06, A12 | Jenny + Vicky | read-only |
| **2** | Escrituras reuse: A07, A08, A10 | Vicky | write (idempotencia heredada) |
| **3a** | Lecturas nuevas: A24 histórico + A25 ingresos | Vicky | read-only nuevo |
| **3b** | Gastos: A11 (write controlado + anti-dup) + A13 (verificación) | Vicky | write nuevo (último) |

- **Menor slice operable:** Slice 0 + A03 → Jenny entrando al portal y viendo su calendario de limpieza.
- **A24/A25 adelantables** si conviene (read-only, sin idempotencia, aportan valor) sin alterar el orden base.
- **Fuera del MVP:** A09 (capa futura, D-8D-09); A14–A18 (contabilidad de socios, solo `socio`); A19–A23 (escritura contable 9H, fase posterior). La contabilidad de socios arranca con la operación de julio.
- **Camino crítico:** Slice 0 bloquea todo. A11 es el único write nuevo y el más sensible → último, con batería propia.

---

## 8. Estrategia de pruebas en TEST (resumen)

Diseño del plan; se ejecuta en la etapa de construcción. **Reglas duras:**

1. **Nada se prueba en OPS.** La colección apunta solo a infra TEST (Edge Function TEST + webhooks `__TEST` + `vita_supabase_test` + `ambiente='test'`). El muro TEST≠OPS se prueba **dentro** de TEST (firmar un request `ambiente_esperado='ops'` contra el workflow TEST → rechaza por marcador `'test'`), nunca contactando OPS.
2. **Cada escritura de TEST es aislable/reversible.** Todas las escrituras del MVP (A07/A08/A10/A11) son **DELETE-ables** (ninguna toca 9H, que está fuera del MVP). Teardown por sentinel: `source_event='portal_test_*'` (A07/A08/A10) y `creado_por` (A11, que no tiene `source_event` de fila). Ventana de fechas de prueba **lejana (2027)**. Sentinels namespaced **distintos** de los fixtures de Carril B (`seed_9f_*`, `seed_9g_*`, `seed_9h_*`).
3. **No-contaminación del arranque contable de julio:** (a) gastos A11 de prueba con `periodo='2099-01-01'` (D-C-28), nunca en un mes operativo real; (b) ventana 2027 para reservas/bloqueos/pagos; (c) teardown verificado con **0 residual** del namespace de portal; (d) snapshot pre/post (patrón 9F/9G) que vuelve al baseline; (e) regla de salida: TEST queda limpio/conocido.
4. **A25 / fecha de pago:** A25 agrupa por **fecha de pago**. Si A07/A10 permiten controlar `fecha_pago`, los pagos de prueba usan una **fecha sintética claramente no-real**. Si el workflow usa la fecha actual y no se puede controlar, el **teardown se ejecuta ANTES de cualquier validación contra períodos reales**, para que A25 no muestre pagos de prueba en un período operativo.
5. **Bordes transversales obligatorios:** rol no permitido (gateway **y** n8n — defensa en profundidad), payload inválido (→ código, nunca error crudo), HMAC inválido/ausente, ambiente cruzado, envelope `resultado` (L-8D-01), reintento A07 (`idempotent_match` sin duplicar), reintento A08 (`conflicto` sin duplicar), estado incierto A10 (mensaje conservador, sin auto-retry), duplicado A11 (advertencia + confirmación permite cargar).
6. **Forma:** cada test con header → precondición (auto-validante donde se pueda, L-9E-02) → acción → esperado → fila de veredicto; colección parametrizada por entorno (**todo a TEST**); **objetivo cero-FALLOs** antes de conectar el frontend.

---

## 9. Lecciones (L-C-01 … L-C-04)

- **L-C-01** — Cuando faltan documentos ancla (el brief del portal, el patrón de contratos API), el diseño puede **avanzar sobre el prompt + README con supuestos explícitos marcados**, reconciliables al cierre, en vez de bloquearse. La disciplina es marcar el supuesto, no inventar el dato.
- **L-C-02** — La idempotencia de un endpoint de escritura es **heredada de la función SQL que envuelve**, no una propiedad del contrato: hay que **caracterizarla por función** contra su cierre (A07 fuerte vía `idempotency_key`; A08 ninguna, guard EXCLUDE; A10 débil/no atómica entre eventos, D-9B-07; A11 ninguna, sin guard). No asumir uniformidad.
- **L-C-03** — `gastos_internos` **no tiene columna `source_event`** (D-9F-14): cuando una tabla no la soporta, la trazabilidad de evento queda a nivel workflow/log, no de fila; diseñar el contrato sabiéndolo y **no contaminar campos de negocio** con metadata técnica.
- **L-C-04** — Para discriminar entorno, los **IDs de cabaña 1-5 no sirven** (iguales en TEST y OPS, L-7B-01): el discriminador es el marcador `ambiente` + credenciales/URLs separadas. Ventaja de prueba: el cruce de ambiente se valida **íntegro en TEST** (firmar `ambiente_esperado='ops'` contra el workflow TEST) sin tocar OPS.

---

## 10. Pendientes (para `Pendiente_pre_produccion.md`)

- **P-C-1** — Brief del portal: si aparece un brief más específico (`Prompt_Portal_Operativo_Interno.md`), reconciliar roles/permisos contra el catálogo. No bloqueante (D-C-01).
- **P-C-2** — Confirmación al construir: los nombres exactos de campos/columnas de los workflows reusados (8B, 8D, 9, calendarios) y la reutilizabilidad de la lectura de 8C-bis para A05 se confirman contra los `__TEMPLATE.json` reales (no están en el repo) en la etapa de construcción.
- **P-C-3** — Contrato formal JSON de calendarios (vs. HTML temporal, D-C-09): diseñarlo cuando el portal pase de HTML embebido a render propio. Post-MVP.
- **P-C-4** — Endurecimiento de seguridad del portal post-MVP: rate-limiting/abuso, rotación del secreto HMAC, expiración/refresh de sesión fino. Fuera del modelo mínimo (Fase 0.5); pasada de hardening posterior.
- **P-C-5** — A09 (editar/levantar bloqueo): capa futura con su propio contrato/workflow (D-C-12 / D-8D-09).
- **P-C-6** — Contabilidad societaria con lectura (A14–A18) y escritura (A19–A23): fases posteriores, solo `socio`; arrancan con la operación contable de julio.

---

## 11. Lo que NO se hizo (explícito)

- **No se construyó ningún workflow, ni la Edge Function, ni código, ni la tabla `portal_usuarios`.** Esta etapa es de diseño.
- **No se tocó OPS.**
- **No se tocó el schema.** `6B_SCHEMA_SQL.md` queda en **v1.8.0 sin cambios y sin bump** (Carril C no introdujo DDL).
- Los campos exactos de los workflows reusados quedan **por confirmar contra los `__TEMPLATE.json` reales** al construir (P-C-2).

> **Nota de schema para la etapa de construcción.** Cuando se construya Slice 0, la tabla `portal_usuarios` se crea **en TEST** como **infraestructura nueva del Carril C** (autenticación del portal), **separada del canónico de reservas/contabilidad**: no modifica el schema de `6B_SCHEMA_SQL.md` y **no requiere bump**. Se documentará en el cierre de su propia etapa.

---

## 12. Próxima etapa

**Construcción de Slice 0 sobre TEST** (la espina de seguridad): Supabase Auth + `portal_usuarios` (DDL + seed real) + Edge Function `portal-api` (gateway/BFF) + patrón de validación n8n (HMAC + rol + ambiente) + `sesion.contexto` end-to-end. Kickoff: `KICKOFF_CARRIL_C_SLICE_0_TEST.md`. **TEST primero; OPS no se toca.**

---

## 13. Deltas a documentos satélite (aplicar con este cierre)

- **`ESTADO_ACTUAL_VITA_DELTA.md`**: nota de estado — Carril C (Backend/API, diseño) cerrado; design-only; nada construido; OPS/schema intactos; próximo = Slice 0 en TEST.
- **`DECISIONES_NO_REABRIR.md`**: agregar D-C-01 … D-C-28 (🔒) — §6 es la fuente.
- **`Lecciones_Aprendidas.md`**: agregar L-C-01 … L-C-04.
- **`Pendiente_pre_produccion.md`**: agregar P-C-1 … P-C-6.
- **`CLAUDE.md`**: actualizar estado de etapa (Carril C diseño cerrado; próxima = Slice 0 build en TEST; una conversación por etapa).
- **`README.md`**: actualizar la línea de Carril C (de "diseño conceptual, sin empezar" a "diseño de Backend/API cerrado; sin construir; próximo = Slice 0 en TEST").
- **`6B_SCHEMA_SQL.md`**: **sin cambios, sin bump** (Carril C no toca DDL).
