# CLAUDE.md — Vita Delta Reservas

## Regla principal

Antes de trabajar, leer en este orden:

1. Docs/Operacional/ESTADO_ACTUAL_VITA_DELTA.md
2. Docs/Operacional/DECISIONES_NO_REABRIR.md
3. Docs/Implementacion/6B_SCHEMA_SQL.md (schema canónico actual: **v1.10.0**)
4. Docs/Bitacora/9H_CIERRE.md (cierre formal Etapa 9H — cuenta corriente interna / capa con estado; cierra el Carril B en TEST)
5. Docs/Bitacora/9G_CIERRE.md (cierre formal Etapa 9G — cascada de liquidación read-only)
6. Docs/Bitacora/9F_CIERRE.md (cierre formal Etapa 9F — gasto interno rediseñado)
7. Docs/Bitacora/9E_CIERRE.md (cierre formal Etapa 9E — matriz dinámica y reparto)
8. Docs/Bitacora/9D_CIERRE.md (cierre formal Etapa 9D — activación operativa por rango)
9. Docs/Bitacora/9C_CIERRE.md (cierre formal Etapa 9C — catálogo enriquecido, zonas y seam)
10. Docs/Bitacora/9B_CIERRE.md (cierre formal Etapa 9B / Fase 3b — cobranza posterior multi-porción)
11. Docs/Arquitectura/ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md (base conceptual de contabilidad operativa interna)
12. Docs/Arquitectura/ARQUITECTURA_ETAPA_8_ARRANQUE_OPS.md (diseño Etapa 8 — arranque OPS; subetapas 8A-8D)
13. Docs/Arquitectura/ARQUITECTURA_ETAPA_8D_BLOQUEOS_OPERATIVOS.md (diseño Etapa 8D — capa de bloqueos; **v1.1**)
14. Docs/Bitacora/8D_CIERRE.md (cierre formal Etapa 8D — bloqueos validados en TEST + OPS; **cierra la Etapa 8 completa**)
14-bis. Docs/Bitacora/8C-bis_CIERRE.md (cierre formal Sub-etapa 8C-bis — alerta por reserva próxima por mail, validada en TEST + activa en OPS; recoge el item 3.1)
15. Docs/Arquitectura/ARQUITECTURA_ETAPA_8C_CALENDARIOS_VISUALES.md (diseño Etapa 8C — calendarios visuales; **v1.3**)
16. Docs/Bitacora/8C_CIERRE.md (cierre formal Etapa 8C — tres calendarios validados en TEST y activos en OPS; 8C-bis posterior)
17. Docs/Arquitectura/ARQUITECTURA_ETAPA_8B_CAPA_CARGA.md (diseño Etapa 8B — capa de carga interna; **v3.5**)
18. Docs/Bitacora/8B_CIERRE.md (cierre formal Etapa 8B — capa de carga validada en TEST + smoke OPS con primera reserva real)
19. Docs/Bitacora/8A_CIERRE.md (cierre formal Etapa 8A — levantamiento del entorno OPS)
20. Docs/Bitacora/7E_CIERRE.md (cierre formal Etapa 7E — endurecimiento de permisos Data API en DEV)
21. Docs/Bitacora/7D_CIERRE.md (cierre formal Etapa 7D — limpieza/reset del entorno TEST)
22. Docs/Bitacora/7C_CIERRE.md (cierre formal Etapa 7C — validación funcional ampliada sobre TEST)
23. Docs/Bitacora/7B_CIERRE.md (cierre formal Etapa 7B — levantamiento del entorno TEST)
24. Docs/Bitacora/7A_CIERRE.md (cierre formal Etapa 7A — correcciones pre-TEST/pre-OPS)
25. Docs/Bitacora/6D_CIERRE.md (cierre formal Etapa 6D — hardening pre-producción)
26. Docs/Bitacora/6C_CIERRE.md (cierre formal de workflows n8n contra Supabase DEV)
27. Docs/Implementacion/6B_PLAN_FASES.md
28. Docs/Operacional/Pendiente_pre_produccion.md (items para deploy a PROD)
29. Docs/Operacional/Lecciones_Aprendidas.md (gotchas operativos)
30. Docs/Bitacora/8D_EJECUCION.md (bitácora de ejecución de 8D, si necesitás el detalle de construcción/incidencias)
31. Docs/Bitacora/8C_EJECUCION.md (bitácora de ejecución de 8C)
32. Docs/Bitacora/6B_EJECUCION_DEV.md (si necesitás contexto histórico de implementación de backend)
33. Docs/Bitacora/6C_EJECUCION.md (si necesitás contexto histórico de implementación de workflows)

No cargar contexto histórico largo salvo pedido explícito del usuario.

## Rol de Claude

Actuás como arquitecto técnico, diseñador de automatizaciones y copiloto de implementación para el sistema de reservas y operación digital de Complejo Vita Delta.

El objetivo es construir un sistema escalable para reservas automáticas, disponibilidad, precios, pagos, coordinación operativa, contabilidad operativa interna, bot conversacional, web de reservas y futuras capas contables/fiscales.

## Equipo de Vita Delta

- **Franco:** socio, visión estratégica, automatización y sistema. Es quien interactúa con Claude.
- **Rodrigo:** socio, recepción/operación.
- **Remo:** tercer socio.
- **Vicky:** encargada de reservas (cierra reservas vía WhatsApp).
- **Jennifer:** encargada de limpieza.

## Principios no negociables

### Arquitectura

- **Supabase/PostgreSQL** es la base de datos objetivo y la fuente de verdad técnica del sistema. La base en Supabase DEV fue implementada en Etapa 6B; los workflows n8n contra Supabase DEV fueron implementados y validados en Etapa 6C.
- **n8n** es el orquestador de workflows: recibe eventos, arma payloads, llama funciones SQL, maneja respuestas y dispara comunicaciones. Las reglas críticas de disponibilidad, reservas, pagos y bloqueos viven en PostgreSQL.
- **Apps Script** queda como puente residual mínimo solo si es estrictamente necesario para Google Sheets legacy.
- **Google Sheets** ya NO es la fuente de verdad operativa. Puede usarse como panel de lectura o reportería, pero la verdad vive en Supabase.
- **La IA no es fuente de verdad operacional** — interpreta, conversa, ordena, pero no confirma reservas ni pagos.

### Reservas y disponibilidad

- **RESERVAS es la fuente final de verdad.**
- **Toda reserva confirmada pasa por `confirmar_reserva()`** — no existe INSERT directo a la tabla `reservas`.
- **`crear_prereserva()` es PUERTA ÚNICA** para crear pre-reservas (incluye locks, idempotencia, validación de disponibilidad).
- **Pre-reservas vigentes bloquean disponibilidad temporalmente.**
- **Toda escritura crítica debe ser secuencial o pasar por funciones del schema** (no UPDATE/INSERT manual desde n8n salvo casos muy controlados).
- **`obtener_disponibilidad_rango()` y vistas son fuente de lectura** — n8n y bots consultan ahí, no calculan disponibilidad por su cuenta.

### Fechas y horarios

- `fecha_in` es **inclusive**.
- `fecha_out` es **exclusive** (no se cobra como noche, pero la cabaña está ocupada hasta el horario de check-out).
- Modelo daterange `[)` permite reservas pegadas (5-6, 6-7, 7-8 jun) con ocupación máxima sin gaps obligatorios. Validado empíricamente.
- **EXCLUDE constraint** sobre reservas (`exc_reservas_no_overlap`) es protección estructural — imposible de eludir con bugs de aplicación.

### Precios y configuración

- Los precios viven en **TARIFAS**.
- **CONFIGURACION_GENERAL** guarda reglas operativas, switches y parámetros (horarios, expiración, horizonte, etc.) — NO guarda precios de alojamiento.

### Trazabilidad

- Toda acción automática debe registrar `source_event`.
- Doble log validado: trigger automático (`trg_log_*_estado`) captura transición pura + log explícito de la función captura evento de negocio.

### Workflows n8n (Etapa 6C consolidada)

- **Las funciones SQL son contratos estables** para n8n. Los workflows deben adaptarse a los payloads y respuestas JSONB definidos por el schema; no deben replicar lógica interna de las funciones.
- **Patrón establecido para workflows write:**
  ```
  Manual Trigger → Build Input → Build Payload → Postgres → Build Response
  ```
- **Patrón para workflows con validación temprana** (W7): agregar nodo IF antes de Postgres para evitar ejecutar queries inválidas.
- **Patrón para cadenas multi-función (Etapa 8B):** Form Trigger → validar/normalizar → encadenar funciones con envelope normalizada por paso (`Continue On Fail` + Normalize tras cada Postgres, distinguiendo error técnico de negocio), `ctx` enriquecido paso a paso, compensación unificada ante fallo parcial, y un nodo `Form Ending` (`form` operation `completion`) para el resultado al operador. Template sanitizado reutilizable: `vita_w8b_carga_reserva__TEMPLATE.json`.
- **Normalización defensiva con `nv()`** en Build Payload para todos los obligatorios, hasta que se aplique el hardening SQL.
- **Wrapper externo unificado**: todos los workflows devuelven `{ ok, workflow, source_event, error, result, executed_at }` con extensiones específicas según el caso.
- **Templates en repo** con sanitización obligatoria (placeholders `__CREDENTIAL_ID__`, `__WORKFLOW_VERSION_ID__`, etc.).
- **Verificación cruzada con W1** obligatoria para workflows que modifican disponibilidad.

## Estado del proyecto

**Etapas de DISEÑO cerradas:**

- Etapa 1 — Arquitectura base.
- Etapa 2 — Motor de disponibilidad.
- Etapa 3 — Motor de precios.
- Etapa 4A — Motor de Reservas Determinístico (diseño).
- Etapa 4B — Bot Conversacional con IA (diseño).
- Etapa 5 — Implementación vertical mínima.
- Etapa 6A — Decisión de migración Sheets → Supabase.
- Etapa 6B — Migración a Supabase (diseño completo).

**Fases de IMPLEMENTACIÓN en Supabase DEV (Etapa 6B):**

- Fase 1 (Schema base — Bloques 1-8) ✅ Cerrada.
- Fase 2 (Funciones + triggers — Bloques 9-19) ✅ Cerrada.
- Fase 3 (Vistas + seed productivo + pg_cron — Bloques 20-22) ✅ Cerrada.
- Hotfix v1.7 (regla `hora_checkout_domingo`) ✅ Aplicado en DEV.
- Alineación v1.7.1 (`obtener_disponibilidad_rango` con CASE de domingo en `hora_checkout_base`) ✅ Aplicada en DEV el 2026-05-25.

**Etapa 6C — Workflows n8n contra Supabase DEV ✅ Cerrada (2026-05-26):**

- 8 workflows operativos en DEV (W0-W7).
- 40 tests funcionales aprobados.
- 3 verificaciones cruzadas end-to-end.
- Patrón de trabajo establecido y reutilizable.
- Documento de cierre formal: `6C_CIERRE.md`.

**Etapa 6D — Hardening pre-producción ✅ Cerrada (2026-05-27):**

- Hardening estructural de validación SQL en las 5 funciones write (patrón `NULLIF(TRIM(...), '')`).
- Fix de rango en `vista_ocupacion`; fix de `TRIM` en concatenación nombre + apellido.
- Tests de concurrencia real validados (H7).
- Bump documental del schema a v1.7.2.
- Decisiones D-HARD-01 a D-HARD-11. Documento de cierre: `6D_CIERRE.md`.

**Etapa 7A — Correcciones pre-TEST / pre-OPS ✅ Cerrada (2026-05-28):**

- Patch `crear_prereserva`: `v_ninos` a TEXT; `canal_pago_esperado` requerido en validación manual.
- Limpieza puntual de datos legacy `ninos='false'` (3 registros → NULL).
- Horizonte de `vista_disponibilidad`/`vista_calendario` configurable vía `configuracion_general.horizonte_disponibilidad_dias` (fallback 120).
- Bump documental del schema a v1.7.3. Decisiones D-7A-01, D-7A-02, D-7A-03.
- 9 tests funcionales + 4 de horizonte aprobados. Documento de cierre: `7A_CIERRE.md`.

**Etapa 7B — Levantamiento del entorno TEST ✅ Cerrada (2026-05-28):**

- TEST creado como proyecto Supabase independiente (`vita-delta-test`); schema reconstruido desde el canónico v1.7.3 (no clon de DEV).
- Paridad estructural demostrada 10/10 vs DEV; seeds mínimos cargados; `pg_cron` activo con ejecuciones reales.
- Permisos Data API normalizados (REVOKE EXECUTE sobre las 13 funciones a `PUBLIC`/`anon`/`authenticated`/`service_role`).
- 8 workflows `__TEST` importados con credencial propia; happy path 8/8 + **cadena transaccional end-to-end W2→W3→W4 validada en TEST**.
- **IDs de cabaña no portables:** DEV 17-21, TEST 1-5. Cada workflow usa los IDs del ambiente al que apunta.
- DEV intacto durante toda la etapa. Decisiones D-7B-01 a D-7B-05; lecciones L-7B-01 a L-7B-03. Documento de cierre: `7B_CIERRE.md`.

**Etapa 7C — Validación funcional ampliada sobre TEST ✅ Cerrada (2026-05-28):**

- Batería sistemática de caminos no-felices de los 8 workflows `__TEST` sobre TEST (errores controlados, edge cases, validaciones defensivas, condiciones de borde) que 7B dejó fuera de alcance.
- **54 verificaciones conformes:** 48 casos funcionales (Grupo A) + 6 verificaciones transversales (TR-01 source_event + TR-02 doble logging). **0 fallos inesperados.**
- **1 mutación no planificada pero válida y comprendida:** bloqueo id 2 (Bamboo, generado en A-W6-06 con `id_cabana:1`; el sistema actuó correctamente ante un payload válido).
- Idempotencia: rama `pre_lock` cubierta empíricamente (A-W2-15), sumada a `post_lock` (H7); resta solo `unique_violation` como opcional no bloqueante.
- DEV intacto; schema canónico v1.7.3 sin modificar; fixtures de TEST conservados como evidencia (D-7C-01, no-limpieza). Lecciones L-7C-01 a L-7C-06. Documento de cierre: `7C_CIERRE.md`.

**Etapa 7D — Limpieza/reset del entorno TEST ✅ Cerrada (2026-05-28):**

- Bloque dedicado de reset con SQL explícito y aprobado, en tres partes separadas: snapshot read-only (A) → limpieza transaccional atómica (B) → verificación posterior (C).
- **Doble gate anti-error-de-entorno** por identidad exacta de las 5 cabañas TEST (IDs 1-5, nombres Bamboo/Madre Selva/Arrebol/Guatemala/Tokio): preflight read-only previo + re-gate dentro de la transacción (`RAISE EXCEPTION` si no coincide).
- **6 tablas transaccionales vaciadas** (`pagos`, `reservas`, `pre_reservas`, `bloqueos`, `huespedes`, `log_cambios`) vía `DELETE` en orden seguro por FKs (`pagos` → `reservas` → `pre_reservas` → `bloqueos` → `huespedes` → `log_cambios`), en transacción única atómica, sin `DROP/TRUNCATE ... CASCADE`. Secuencias reseteadas a 1.
- Las 3 condicionales (`consultas`, `overrides_operativos`, `gastos`) estaban en 0 y no entraron al borrado. Seed estructural (11 tablas), cron, funciones/vistas/triggers, grants y workflows `__TEST` intactos.
- **TEST quedó como entorno limpio.** Verificación post-reset conforme (transaccionales en 0, seed idéntico, secuencias en próximo id = 1, cron y vistas operativas OK). Workflows `__TEST` confirmados sobre credencial `vita_supabase_test`.
- Decisiones D-7D-01 (reset de secuencias en tablas vaciadas) y D-7D-02 (vaciado de `log_cambios` con evidencia documentada). Documento de cierre: `7D_CIERRE.md`.

**Etapa 7E — Endurecimiento de permisos Data API en DEV ✅ Cerrada (2026-05-28):**

- Aplicado a DEV el `REVOKE EXECUTE` sobre las 13 funciones del proyecto a `PUBLIC`/`anon`/`authenticated`/`service_role`, en paridad con TEST (7B-GRANTS). Cierra el pendiente explícito 1.5. Owner `postgres` intacto → n8n sigue ejecutando por ownership (conecta por pooler como `postgres.<DEV_REF>`, no vía Data API).
- Método de cuatro bloques separados: snapshot read-only (A) → cambio transaccional `BEGIN/COMMIT` con re-gate anti-error-de-entorno por identidad de cabañas DEV 17-21 (B) → verificación posterior (C) → cierre documental (D). Sin `DROP/TRUNCATE ... CASCADE`, sin tocar schema.
- Verificación conforme: 0 fugas de EXECUTE para los 4 grantees; owner `postgres` en las 13; schema sin cambios (201 funciones / 6 vistas / 19 triggers — de las 201, solo 13 son del proyecto, las otras 188 son de `btree_gist`/`supabase_admin`); residual de tablas intacto (480 grants).
- **Hallazgo A5 (fuera de alcance por decisión — Opción 1):** en DEV los roles `anon`/`authenticated`/`service_role` tienen SELECT/escritura completos sobre todas las tablas/vistas, más amplio que el `Dxtm` de TEST. No se tocó; registrado como pendiente nuevo `Pendiente_pre_produccion.md` 1.7.
- DEV es el único entorno tocado; TEST/OPS/PROD intactos. Decisiones D-7E-01, D-7E-02; lección L-7E-01. Documento de cierre: `7E_CIERRE.md`.

**Etapa 8A — Levantamiento del entorno OPS ✅ Cerrada (2026-05-29):**

- OPS creado como proyecto Supabase independiente (`vita-delta-ops`, `OPS_REF=lpiatqztudxiwdlcoasv`, sa-east-1, Free tier, PostgreSQL 17.6). **Tercer entorno** de la estrategia DEV → TEST → OPS → PROD y **primer entorno de operación real interna** (D-8-09).
- Schema reconstruido desde el canónico v1.7.3 en 7 tandas (4.1-4.7), con **paridad estructural P01-P10 10/10**: 2 extensiones, 4 enums, 20 tablas, 6 vistas, 13 funciones, 13 triggers, 2 EXCLUDE, 38 CHECK, 15 FK, 27 índices.
- **Seeds reales** sembrados: 5 cabañas (IDs **1-5**: Bamboo=1, Madre Selva=2, Arrebol=3, Guatemala=4, Tokio=5), 3 socios (Franco 33.33 / Rodrigo 33.34 / Remo 33.33), 10 claves de `configuracion_general` (horizonte 120), 1 cuenta de cobro real y activa (alias playario), 1 temporada baseline, 1 plantilla. Sin tarifas reales (monto manual en 8B, D-8-04).
- **OPS nació más cerrado que TEST:** con el switch "Automatically expose new tables = OFF" desde el día cero, 0 funciones con EXECUTE a Data API y 0 grants RW a roles Data API sobre tablas, sin remediar nada. El `REVOKE EXECUTE` idempotente se aplicó igual como barrera explícita (Opción B).
- Default privileges cerrado sin ejecución (D-8-13): los defaults del rol `postgres` conceden solo `Dxtm` inocuo → objetos futuros nacen cerrados; los 21 defaults amplios son del rol de plataforma `supabase_admin` y no se tocan.
- `pg_cron` activo (2 jobs) con una corrida real `succeeded` verificada. Credencial n8n `vita_supabase_ops` creada, probada y **verificada por identidad** (lee las 5 cabañas reales de OPS). Verificación consolidada 17/17.
- **Smoke de cierre solo lectura** (D-8-12): OPS sin datos transaccionales; el primer write real será una reserva real por 8B. DEV/TEST/PROD no se tocaron.
- Decisiones D-8-09, D-8-13 (+ confirmación de cumplimiento de D-8-03). Lecciones L-8A-01 a L-8A-07. Documento de cierre: `8A_CIERRE.md`. Diseño de la Etapa 8: `ARQUITECTURA_ETAPA_8_ARRANQUE_OPS.md`.

**Etapa 8B — Capa de carga interna de reservas ✅ Cerrada (2026-05-30):**

- Form Trigger n8n usable desde celular (Basic Auth, `Respond When = Workflow Finishes`, `Form Ending`) que encadena `crear_prereserva` → `registrar_pago` → `confirmar_reserva` en **una sola acción**, con compensación vía `cancelar_prereserva` ante fallo parcial. Sin INSERT directo: toda escritura pasa por las funciones.
- **Contratos reales verificados contra OPS (read-only)** antes de implementar. Hallazgos clave: `canal_origen`/`canal_pago_esperado`/`medio_pago`/`tipo` son **TEXT con CHECK** (no enums); `crear_prereserva` ya valida cabaña/capacidad; `ok:true` de `registrar_pago` no garantiza pago confirmado (verificación estricta de estado + warning); constraint de `idempotency_key` es **parcial** (solo estados activos).
- Cabaña por nombre (mapeo a IDs reales 1-5). Seña vacía/0 → 50% automático; valor explícito → se respeta (D-8B-13). Nombre+apellido en campo único (D-8B-12 revisada). Strings persistidos compatibles con los CHECK reales (D-8B-21), con origen fino (Airbnb/Booking/Directo/etc.) preservado en `notas`.
- **Validación funcional completa en TEST** (happy path en ambos caminos de seña, colisión, idempotencia, validaciones de capa, compensación con pago).
- **Smoke OPS exitoso = primer write real del sistema:** reserva id 1 (Tokio, Paula Lugo, 06→07 jun 2026, total 150000, seña 75000, saldo 75000, `created_by`/`validado_por` = vicky, `source_event` `n8n_ops_w8b_carga_vicky_manual`). Trazabilidad multiusuario verificada en producción.
- Punto de extensión para el repintado de calendario (8C) marcado pero NO construido.
- Artefactos: workflows `__TEST`/`__OPS`/`__TEMPLATE` (sanitizado). Decisiones D-8B-01 a D-8B-21; lecciones L-8B-01 a L-8B-07. Diseño: `ARQUITECTURA_ETAPA_8B_CAPA_CARGA.md v3.5`. Documento de cierre: `8B_CIERRE.md`.
- **Estado operativo:** al cierre de 8C-bis, `vita_w8b_carga_reserva__OPS` quedó activo y publicado para uso por URL; el pendiente operativo de activación quedó cubierto.

**Etapa 8C — Calendarios visuales por evento ✅ Cerrada (2026-06-01, TEST + OPS):**

- **Tres calendarios derivados de solo lectura** desde Supabase (fuente de verdad), sin tocar schema ni funciones del motor. Cero escrituras en tablas transaccionales; ninguna llamada a las funciones del motor.
- **HTML operativo** (Franco/Rodrigo/Vicky/Remo): grilla día×cabaña 120 días con pestañas por mes; reservas confirmadas/activas + bloqueos; montos/horarios/teléfono. `vita_w8c_html_operativo` (TEST id `8vFm5cb4vrhwMCi5`; derivado a OPS y activo).
- **HTML limpieza** (Jennifer): grilla 7 días, **sin montos**, con mascotas y notas operativas. Basic Auth propia y separada (D-8C-20). `vita_w8c_html_limpieza` (TEST id `OcLCHBVfatqr8ljs`; derivado a OPS y activo).
- **Sheet de resguardo**: operativo (CON montos) volcado a un Google Sheet como respaldo offline; grilla con meses apilados, sin colores, clear+write vía HTTP a la API REST de Sheets (**NO Apps Script** — D-8C-22). Disparo manual, autónomo para invocación futura desde 8B. `vita_w8c_sheet_resguardo` (TEST id `ufvxuLE9C2JiCUpi`).
- **Aclaración clave:** los HTML son **ventanas en vivo** (se arman en cada visita a la URL, siempre muestran el estado actual); NO necesitan disparo. Solo el Sheet de resguardo es una foto estática que se regenera por ejecución.
- Lógica de pintado en capa de presentación: operativo **rojo > gris > verde > blanco**; limpieza **rojo > gris > amarillo (salida) > verde > blanco**. Detección de salida incluye `confirmada`/`activa`/`completada` (4ta query sobre `reservas`); bloqueo con `EXISTS` sin asumir unicidad (totales `id_cabana IS NULL` fuera del EXCLUDE); fechas normalizadas a `YYYY-MM-DD`.
- **Validación funcional completa en TEST** y **smoke OPS ejecutado**: los HTML operativo y limpieza están **activos y en uso real** por el equipo (resguardo OPS manual).
- **8C-bis (alerta por reserva próxima): ✅ resuelta después como sub-etapa propia** (canal = mail; no reabre `8C_CIERRE.md`). Ver el bloque "Sub-etapa 8C-bis" más abajo y `8C-bis_CIERRE.md`.
- Artefactos: workflows `__TEST`/`__OPS` + 2 templates sanitizados (`vita_w8c_html_operativo__TEMPLATE.json`, `vita_w8c_sheet_resguardo__TEMPLATE.json`) + nodos Code versionados. Decisiones D-8C-01 a D-8C-23; lecciones L-8C-01 a L-8C-05. Diseño: `ARQUITECTURA_ETAPA_8C_CALENDARIOS_VISUALES.md v1.3`. Cierre: `8C_CIERRE.md`. Ejecución: `8C_EJECUCION.md`.

**Etapa 8D — Capa de bloqueos operativos ✅ Cerrada (2026-06-04, TEST + OPS) — cierra la Etapa 8:**

- **Formulario n8n** (Form Trigger, Basic Auth propia, usable desde celular) que invoca `crear_bloqueo()` en **una sola acción** (sin cadena, sin pagos, sin compensación; sin INSERT directo; sin tocar schema). El bloqueo aparece en gris en los calendarios de 8C.
- **Contrato verificado read-only** (TEST, 2026-06-03): la función valida TODO (cabaña, fechas, motivo, y los tres conflictos: reserva confirmada/activa, pre-reserva vigente, bloqueo solapado) → el formulario es solo UX. Un bloqueo NO convive con reservas (las rechaza). Concurrencia resuelta en la función; triple protección de solapamiento.
- **Campos:** cabaña (desplegable, nombre→id 1-5, **sin opción TODAS** — D-8D-03), fecha desde, fecha hasta/liberación (modelo `[)`, exclusive), motivo (5 valores del CHECK), descripción opcional, creado por. Una cabaña por vez; varias = varias cargas (D-8D-02).
- **Manejo de errores en dos familias:** conflictos unificados ("esas fechas no están disponibles", sin exponer IDs — D-8D-04/05); errores de entrada diferenciados. **Éxito en lenguaje humano** (último día inclusive + día de liberación — D-8D-08).
- **8D SOLO CREA bloqueos** (D-8D-09): corregir o levantar uno requiere intervención manual controlada (`activo=false` vía SQL); no hay desbloqueo desde el formulario. Riesgo aceptado para el MVP.
- **Validado en TEST y operativo en OPS:** `vita_w8d_bloqueo__TEST` (id `GIfBlI6xCnrkH2Y4`, 9 nodos) y `vita_w8d_bloqueo__OPS` (activo, primer bloqueo real creado). Incidencia clave (L-8D-01): el nodo Postgres devuelve el resultado de la función envuelto en la columna `resultado`; el Normalize debe leer `item.resultado.ok`, no `item.ok` (un "Problema técnico" inicial era esto; la base nunca falló).
- Artefactos: workflows `__TEST`/`__OPS` + template sanitizado `vita_w8d_bloqueo__TEMPLATE.json` + nodos Code. Decisiones D-8D-01 a D-8D-09; lecciones L-8D-01 a L-8D-03. Diseño: `ARQUITECTURA_ETAPA_8D_BLOQUEOS_OPERATIVOS.md v1.1`. Cierre: `8D_CIERRE.md`. Ejecución: `8D_EJECUCION.md`.

**Sub-etapa 8C-bis — Alerta por reserva próxima (mail) ✅ Cerrada (2026-06-04, TEST + OPS):**

- **Sub-workflow independiente** (`vita_w8cbis_alerta__OPS`, id `fHzMFj7pGMKuYEOb`, 13 nodos) invocado desde el formulario de carga 8B mediante Execute Workflow **en rama lateral**. Recoge el item 3.1 de `Pendiente_pre_produccion.md` y D-8C-21.
- **Disparo:** cuando se confirma una reserva con `fecha_checkin ∈ [hoy, hoy+7]` (TZ America/Argentina/Buenos_Aires), envía un mail al equipo operativo (Franco + Rodrigo) y a Jennifer (limpieza). Sin cron/polling.
- **Garantía estructural (D-8Cbis-02):** el PUNTO EXTENSION de 8B alimenta `Build Response` (item original, respuesta al operador) y el Call (sub-workflow) **en paralelo**; el Call queda como hoja sin salida. Si el mail falla, la reserva confirmada NO se ve afectada. Validado end-to-end en TEST con el Call pineado para fallar → `Build Response` igual mostró "✅ Reserva confirmada".
- **Privacidad por construcción (D-8Cbis-05):** el mail solo informa cabaña/entrada/salida y enlaza al calendario correspondiente; NO incluye montos, huésped, teléfono ni notas. El detalle se ve abriendo el calendario (con su propio Basic Auth).
- **Solo lectura (D-8Cbis-04):** consulta la reserva por `id_reserva` (`SELECT` sobre `reservas`+`cabanas`, sin join a `huespedes`); no invoca funciones del motor ni escribe. `confirmar_reserva` solo devuelve ids, por eso se consulta aparte; las vistas de calendario no sirven para lookup puntual (filtran por ventana).
- **Canal = mail (D-8Cbis-01)**, no Telegram/WhatsApp. Remitente temporal = Gmail personal de Franco (credencial "SMTP gmail"), migrable al futuro mail de las cabañas sin rediseño (D-8Cbis-09). Config por entorno: bloque `test` → mail de Franco (red de seguridad para pruebas), bloque `ops` → destinatarios reales (D-8Cbis-08).
- **Validado en TEST** (6 casos de lógica con pin data + envío real + aislamiento de la rama lateral) y **publicado/activo en OPS** (credencial `vita_supabase_ops`, Call de 8B OPS con `entorno: "ops"`, destinatarios reales). La **primera ejecución real** quedará registrada con la próxima reserva en ventana (Franco decidió no forzar prueba: el formulario ya opera con reservas reales).
- Hallazgos: el `\t` invisible heredado en un destinatario (L-8Cbis-02) y la diferencia draft vs. `activeVersion` al publicar (L-8Cbis-03), ambos detectados por lectura del JSON y resueltos antes del cierre.
- Workflows: `vita_w8cbis_alerta__TEST` (id `TdTlv9ZhswwzijF2`) y `vita_w8cbis_alerta__OPS` (id `fHzMFj7pGMKuYEOb`, activo). Decisiones D-8Cbis-01 a D-8Cbis-10; lecciones L-8Cbis-01 a L-8Cbis-03. Cierre: `8C-bis_CIERRE.md`. No reabre los cierres de 8B, 8C ni 8D.

**Etapa 9B / Fase 3b — Cobranza posterior multi-porción ✅ Cerrada en TEST (2026-06-07):**

- **Primera fase de la Etapa 9 que escribe pagos** (9A diagnóstico y 3a-v2 listado eran read-only). Capa de cobranza del saldo posterior a la confirmación: formulario n8n (Basic Auth, `active=false`) con hasta tres porciones simultáneas (efectivo / transferencia bancaria o MP / "otros" en equivalente ARS) y **recargo 5% interno** sobre la porción de transferencia.
- **Recargo (D-9B-02/18):** línea `tipo='extra'` separada, marcada `recargo_5_saldo_transferencia`, que **no reduce** el saldo de alojamiento (el saldo baja solo por `tipo IN ('sena','saldo')`). La porción "otros" se registra en ARS como `efectivo` con trazabilidad obligatoria en notas (`medio_original=otros; origen_otros=...; descripcion_otros=...; registrado_como=efectivo_ars`).
- **Núcleo transaccional todo-o-nada (D-9B-19):** `queryBatching: transaction` + helper SQL `public.abortar_si_falla(jsonb)` que convierte cualquier pago no confirmado en excepción P0001 y revierte el evento completo. Éxito operativo = `ok=true AND estado='confirmado' AND warning IS NULL` (no basta `ok:true` — L-8B-03 / D-8B-15). El helper es **aditivo** (no toca tablas, enums ni `registrar_pago()`), vive **solo en TEST**; si 3b se promueve a OPS, hay que crearlo allí primero o falla.
- **Cadena:** N1 form → N2 saldo real → N3 validación + armado de `lineas[]` + `source_event` único → N4 resumen → N4.5 expansión a N ítems → N5 registro transaccional `SELECT public.abortar_si_falla(public.registrar_pago($1::jsonb))` → N6 verificación posterior (relee por `source_event` + recalcula saldo real desde la base) → N6b control (lee `item.resultado`) → N7 éxito / N8a error transaccional / N8b error de verificación / N9 error de negocio.
- **Generación + verificación:** workflow generado con script Python (`generar_3b.py`) y **verificador estructural** (`verificar_3b.py`, 34 controles, 34/34) antes de importar. Franco importó manualmente; Claude no operó la instancia.
- **Validado en TEST:** batería de 9 smokes + pago parcial + **rollback multi-línea** (0 pagos tras abort, verificado por `source_event`). Recargo correcto en los tres casos con transferencia ($8.500 / $5.000 / $1.650). Promovido a OPS en jun-2026 junto con el Carril B (workflow `vita_w09_cobranza_posterior`, 14 nodos, andando en OPS).
- Incidencias resueltas: bug de SQL en N6 (mezcla coma+`LEFT JOIN` → `invalid reference to FROM-clause entry`; corregido y blindado con un control del verificador — L-9B-03); aclaración `created_at`/`updated_at` vs `fecha_hora` en `pagos` (L-9B-04). **Comportamiento conocido aceptado:** doble-mensaje N8b→N8a ante rollback (con `onError: continueErrorOutput` el nodo transaccional dispara ambas salidas; cosmético, integridad intacta; se intentó un Filter N5.5 y se revirtió — L-9B-05).
- Artefactos: `cobranza_posterior_3b.json`, `generar_3b.py`, `verificar_3b.py`, templates sanitizados `vita_w09_cobranza_posterior__TEMPLATE.json` y `vita_w09_listado_saldos__TEMPLATE.json`. Decisiones: bloque 9B + D-9B-19 (en `DECISIONES_NO_REABRIR.md`); lecciones L-9B-01 a L-9B-05. Cierre: `9B_CIERRE.md`. No reabre 8B/8C/8D/8C-bis ni el diagnóstico 9A.

**Etapas 9C→9H / Carril B — contabilidad operativa interna completa ✅ Cerradas en TEST (9F 2026-06-10, 9G 2026-06-11, 9H 2026-06-12) y promovidas a OPS (jun-2026, canónico v1.8.0):**
- **9C:** `cabanas.valor_relativo` + `cabanas.id_socio_beneficiario` (NOT NULL, FK RESTRICT); `zonas` + `cabana_zona` (grandes/chicas); seam `resolver_beneficiario(id_cabana, fecha)` (fecha incluida e ignorada en el MVP); marcador `configuracion_general('ambiente','test')` como gate anti-OPS (D-9C-19); placeholder `Socio 3`→`Remo` resuelto (D-9C-21).
- **9D:** `activaciones_operativas` (rangos `[)`, EXCLUDE gist por cabaña, `fecha_hasta NULL`=abierta; desactivar = hueco); pool real D-9D-10: 4 cabañas desde 2026-07-01, **Guatemala desde 2026-11-01**.
- **9E:** `matriz_participacion` / `repartir_por_matriz` / `detalle_participacion`, read-only; matriz derivada, jamás persistida; centavo residual D-9E-08 (mayor participación; empate del máximo: Rodrigo si está, sino menor id).
- **9F:** `gastos_internos` (17 col, 18 constraints; clase A/C/D/E ⇒ momento+alcance por CHECK; override derivado con comentario obligatorio; `periodo` normalizado a día 1; pagador socio|caja); legacy `gastos` congelada e intacta (D-9F-01); fixture ids 30–34.
- **9G:** cascada de 11 pasos en 6 funciones `sql STABLE SECURITY INVOKER` (`cascada_periodo`, `saldo_socios_periodo`, `incidencia_gasto`, `reporte_overrides_periodo`, `reporte_5_vs_fiscal_periodo`, `gastos_sin_incidencia_periodo`); % operativo por parámetro con guard explícito (D-9G-01); **caja percibida** = mes de `created_at` (D-9G-03); `GREATEST(base,0)` solo en paso 4 (D-9G-07); no-derivable se reporta sin restar (D-9G-06); `desembolsado_periodo` informativo, la compensación es 9H (D-9G-09). Validación 40/40 en TEST reproduciendo el ejemplo canónico al centavo; junio quedó como anomalía de arranque real ($1.345.000 con pool vacío, sin destinatarios). Seed de 5 pagos (único write, gates G1–G9) conservado junto al fixture 9F como **banco de laboratorio hasta la promoción coordinada** (D-9G-13: no datos reales, distorsión declarada, **no viajan a OPS**).
- **9H:** capa **con estado** — 5 tablas append-only (`liquidaciones_periodo`, `liquidacion_cascada`, `liquidacion_socio`, `movimientos_socio`, `revaluaciones`) con inmutabilidad por 10 triggers y cadena de supersesión lineal (re-snapshot sin borrar; una raíz/una vigente por período) + 9 funciones (4 lectura `STABLE` + 5 escritura solo-INSERT con advisory locks) que congelan la foto de 9G, llevan el mayor de movimientos (retiros/ajustes/reversas/retribución) y la revaluación ARS→USD; **saldo vivo derivado** (D-9H-12, nunca almacenado; columnas separadas, suma solo en la función). Paso 4 sin beneficiario predefinido, destino por movimiento manual (D-9H-11/13/14). Validación seis bloques verdes (A0 + B + C + C.3 smokes 20/20 + D + E 38 OK), canónicos jul/ago/nov al centavo + saldos vivos finales (Franco $24.158,16 · Rodrigo $351.957,49 · Remo $213.284,35); limpieza por **teardown DROP**, nunca DELETE (D-9H-20). Carga `seed_9h_d` conservada con el banco 9F/9G (no viaja a OPS).
- Decisiones D-9C-14..21 / D-9D-01..10 / D-9E-01..08 / D-9F-01..21 / D-9G-01..14 / D-9H-01..38; lecciones L-9C, L-9D, L-9E, L-9F, L-9G, L-9H (en los satélites). Cierres `9C_CIERRE.md` … `9H_CIERRE.md`. **Promovido a OPS** en junio 2026 (paquete único, canónico v1.8.0; ver `PROMOCION_CARRIL_B_OPS_CIERRE.md`).

**Promoción del Carril B a OPS + canónico v1.8.0 ✅ Cerrada (2026-06-14):** el Carril B completo (helper 9B + 9C→9H) se promovió a OPS como **paquete único por DDL** (sin copiar datos de TEST; los fixtures no viajan); paridad estructural por huella `TOTAL_CARRIL` (31 objetos) **idéntica TEST↔OPS** (`f5187092083451ceb5b182334bdb4a17`), hardening sin exposición a Data API (9 tablas + 6 secuencias + 21 funciones), smokes **18/18 read-only** en OPS, workflow `vita_w09_cobranza_posterior` (14 nodos) + listado de saldos andando en OPS. **D-PROMO-01..13 / L-PROMO-01..08**, cierre `PROMOCION_CARRIL_B_OPS_CIERRE.md`.

**Schema canónico actual:** `6B_SCHEMA_SQL.md v1.10.0` (v1.10.0 agrega a la **PARTE C** las 2 funciones de lectura de la cuenta corriente de socios —`cuenta_corriente_viva`, `cuenta_corriente_detalle`—, promovidas a OPS; v1.9.0 incorpora el **Carril C / Portal Operativo Interno** como **PARTE D** —`portal_usuarios`, `portal_idempotencia`, `portal_cargar_gasto_interno(jsonb)`— + §25, promovido a OPS; ver `PROMOCION_CARRIL_C_OPS_CIERRE.md`). **TEST y OPS están alineados** con el Carril B promovido (TEST reconstruido desde el canónico en 7B con paridad 10/10; OPS reconstruido en 8A con paridad P01-P10 10/10, más el Carril B promovido en jun-2026 con huella `TOTAL_CARRIL` idéntica). **DEV quedó fuera del alcance de la promoción** y se **reconstruyó desde cero desde v1.8.0** (cerrada 2026-06-15, proyecto nuevo `wsrdzjmvnzxidjlovlja`). Ni 8C ni 8D modificaron el schema: los calendarios son solo lectura y los bloqueos usan `crear_bloqueo()` tal cual. **8C-bis tampoco toca schema:** es solo lectura + envío de mail. **3b tampoco modifica el canónico:** la única adición es la función de orquestación `public.abortar_si_falla(jsonb)`, aditiva (no toca tablas, enums ni `registrar_pago()`); con la promoción quedó también en OPS, con `SET search_path = public, pg_temp` + `REVOKE EXECUTE`, e incorporada al canónico v1.8.0. **El Carril B (9C→9H), ya promovido a OPS e incorporado al canónico v1.8.0, aporta:** columnas `valor_relativo`/`id_socio_beneficiario` en `cabanas`, tablas `zonas`/`cabana_zona`/`activaciones_operativas`/`gastos_internos` (capa derivada) más las **5 tablas con estado de 9H** (`liquidaciones_periodo`/`liquidacion_cascada`/`liquidacion_socio`/`movimientos_socio`/`revaluaciones`) con 10 triggers de inmutabilidad, el marcador `configuracion_general('ambiente')` y **diecinueve funciones** (seam + 3 de 9E + 6 read-only de 9G + 9 de 9H: 4 de lectura y 5 de escritura). Con la promoción, estos objetos están en TEST y OPS y en el **canónico v1.8.0** (bump único); **DEV también los tiene desde su reconstrucción del 2026-06-15** (proyecto nuevo, ver `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md`).

**Carril C — Portal Operativo Interno / Backend-API (diseño) ✅ Cerrada (2026-06-15):** etapa de diseño puro — catálogo de 25 acciones (A01–A25), matriz rol×endpoint (`jenny`/`vicky`/`socio`), modelo de identidad/frontera de confianza (Supabase Auth + `portal_usuarios` + Edge Function `portal-api` como gateway + HMAC a n8n + validación de ambiente), andamiaje de contrato con error uniforme, MVP por slices (0→3b; menor operable = Slice 0 + A03) y estrategia de pruebas en TEST. **Decisiones D-C-01…D-C-28, lecciones L-C-01…04.** Nada construido (sin workflows, Edge Function, código ni `portal_usuarios`); OPS y schema intactos (canónico v1.8.0 sin bump). Carril independiente del Carril B. Cierre `CARRIL_C_BACKEND_API_DISENO_CIERRE.md`. **Próxima etapa (conversación nueva): construcción de Slice 0** (espina de seguridad) **sobre TEST.**

**Carril C — Portal Operativo Interno / Slice 0 (espina de seguridad) ✅ Cerrada (2026-06-16):** primera **construcción** del Carril C, sobre **TEST**. Tres piezas: tabla **`portal_usuarios`** (identidad→rol, interna: REVOKE a `anon`/`authenticated`, SELECT solo a `service_role`, invisible al Data API — D-C-34; 5 usuarios por Supabase Auth, seed por email); Edge Function **`portal-api`** (gateway/BFF, `verify_jwt=false`, JWT→`getUser`→lookup rol→allowlist rol×action→dispatch; `sesion.contexto` resuelta sin n8n; helper HMAC listo, aún sin acción que lo use); workflow n8n **`portal-probe-ambiente`** que **revalida** HMAC sobre raw body + ventana `ts` ±300 s + `ambiente` (segunda defensa). **6/6 smokes** `portal-api` + **4/4** del probe; el caso firma-válida cerró la salvedad de D-C-29 (HMAC sobre bytes literales valida byte a byte en n8n). **Decisiones D-C-29…D-C-35, lecciones L-C-05…09.** OPS intacto; canónico **v1.8.1 sin cambios** (`portal_usuarios` es TEST-only). Secreto `VITA_HMAC_SECRET` de TEST rotado 2026-06-16. Cierre `C_SLICE0_CIERRE.md`. **Próxima etapa: Slice 1 (lecturas reuse A03/A04/A05/A06/A12).**

**Carril C — Portal Operativo Interno / Slice 1 (lecturas reuse) ✅ Cerrada (2026-06-18):** las **cinco primeras lecturas operativas** del portal sobre **TEST**, vía **wrappers n8n firmados** (revalidan HMAC + `ts` + rol + **action binding** + ambiente; reusan lógica/vistas/queries existentes, sin los webhooks viejos — D-C-36). A03 `calendario.limpieza` (HTML; jenny/vicky/socio), A04 `calendario.operativo` (HTML 120 días con montos; vicky/socio), A05 `reserva.detalle` (JSON `data:{reserva,pagos}`, primera acción con payload `id_reserva` vía `queryReplacement`; vicky/socio), A06 `prereservas.activas` y A12 `cobranza.saldos` (JSON `data:{filas}`; vicky/socio). Gateway `portal-api` con **allowlist doble** (D-C-39) + **action binding** (D-C-41); CATALOG con 6 entradas (1 Edge + 5 n8n). Hitos: primer `rol_no_permitido` real (jenny rebota en el gateway), semántica de listas `filas:[]` ≠ `no_encontrado` (D-C-47). Validado por bloque (smoke directo + vía gateway), 11 bloques. **Decisiones D-C-36…D-C-49, lecciones L-C-10…15.** OPS intacto; canónico **v1.8.1 sin cambios** (lecturas read-only; `portal_usuarios` sigue TEST-only). Cierre `C_SLICE1_CIERRE.md`. **Próxima etapa: Slice 2 (escrituras reuse A07/A08/A10).**

**Carril C — Portal Operativo Interno / Slice 2 (escrituras reuse) ✅ Cerrada (2026-06-20):** las **tres primeras escrituras operativas** del portal sobre **TEST**, vía **wrappers n8n firmados** (revalidan HMAC + `ts` + rol + **action binding** + ambiente; **inyectan el actor server-side** desde el JWT —`actorCoherente`, nunca del payload— y reusan funciones del motor existentes, sin los webhooks viejos). A07 `reserva.crear_manual` (reusa `crear_prereserva`/`registrar_pago`/`confirmar_reserva` de 8B; vicky/socio), A08 `bloqueo.crear_manual` (reusa `crear_bloqueo` de 8D, `id_cabana` obligatorio —bloqueo total no se expone—; vicky/socio), A10 `cobranza.registrar_saldo` (reusa `registrar_pago`/`abortar_si_falla` de 9B; vicky/socio). Gateway `portal-api` con **allowlist doble** (D-C-39) + **action binding** (D-C-41) + `isWrite` (dispatch no confiable → `estado_incierto`); CATALOG con 9 entradas (1 Edge + 5 lecturas + 3 escrituras). Hitos: primera escritura vía gateway (actor inyectado verificado en base, reject-unknown anti-spoof), primer write transaccional con lock (A10, `pg_advisory_xact_lock` + dos sentencias con snapshot fresco, D-C-50), modelo de error de dos capas (D-C-51). Validado por capa con el **assert de regresión de A10 end-to-end** (SOBREPAGO → `conflicto`, nunca `estado_incierto`): A10 gateway 9/9 + 9/9 + verif; A10 directo 33/0 + 11/0 + 7/0; A07/A08 por referencia. **Decisiones D-C-50/51, lecciones L-C-16/17** (A07/A08 no agregaron). OPS intacto; canónico **v1.8.1 sin cambios**; `portal_usuarios` sigue TEST-only. **W09 INACTIVO** hasta decisión posterior; wrapper A10 directo **ACTIVO** (el gateway lo necesita). Cierre `C_SLICE2_CIERRE.md`. **Próxima etapa: Slice 3a (lecturas nuevas A24/A25) / Slice 3b (gastos A11/A13).**

**Carril C — Portal Operativo Interno / Slice 3a (lecturas nuevas) ✅ Cerrada (2026-06-20):** las **dos primeras lecturas nuevas** del portal sobre **TEST** (las de Slice 1 eran *reuse*), vía **wrappers n8n firmados** (revalidan HMAC + `ts` + rol + **action binding** + ambiente; `SELECT` inline, sin funciones nuevas ni DDL; **sin** `injectActor` ni `isWrite`). A24 `historico.reservas` (buscador operativo de reservas; floor inferior duro 2026-07-01 recortado por el gateway; `fecha_hasta` default `null` = sin cota, incluye futuras; `id_cabana`/`estado` `null` = todas/todos sin sentinela; `saldo_real` por la CTE de A12 desde `reservas.id_pre_reserva`, puede ser negativo; devuelve `id_cabana`+`cabana`; vicky/socio), A25 `ingresos.cobrados_periodo` (caja percibida; `total_cobrado` solo `sena`+`saldo` confirmados, mes de `created_at`; suma sobre `pagos` —incluye residuo, `cabana` por LEFT JOIN—; `otros_movimientos` informativo no sumado; `periodo_hasta` híbrido —omitido→hoy sin check, explícito→YMD y ≥`periodo_desde` sino `payload_invalido`—; `filas` paginada; vicky/socio). Gateway `portal-api` con **allowlist doble** (D-C-39) + **action binding** (D-C-41); CATALOG con **11 entradas** (1 Edge + 7 lecturas + 3 escrituras). En A25, `payloadIngresosPeriodo` **preserva la ausencia de `periodo_hasta`** (omitido no va en el `value` firmado) para no cambiar la semántica gateway↔directo. Validado por capa cruzando S8/S9 al centavo: A24 directo 26/26 + gateway 23/23; A25 directo 26/26 + gateway 24/24 (`total_cobrado=921200`; regresiones del híbrido en verde). **Decisiones D-C-52/53/54, lecciones L-C-18/19.** OPS intacto; canónico **v1.8.1 sin cambios**; `portal_usuarios` sigue TEST-only. Cierre `C_SLICE3A_CIERRE.md`. **Próxima etapa: Slice 3b (gastos A11/A13).**

**Carril C — Portal Operativo Interno / Slice 3b (gastos: A11 carga + A13 listado) ✅ Cerrada (2026-06-22):** el **gasto interno** del portal, dos acciones companion sobre `gastos_internos`, cada una por **wrapper n8n directo y por gateway** `portal-api` (JWT). **A11** `cargar.gasto_interno` = **primera escritura no-idempotente** del portal: guard de **dos capas en UNA txn** dentro de `portal_cargar_gasto_interno` (capa 1 anti-replay `UNIQUE(nonce)`, `nonce` **derivado de la firma HMAC** del sobre, nunca del cliente; capa 2 idempotencia de negocio `UNIQUE(action,idempotency_key)` comparando `payload_norm`+`actor`: mismo→`ok` idempotente, payload distinto→`payload_mismatch`, actor distinto→`actor_mismatch`); `actor`/`source_event` los **deriva la función** server-side; **18 constraints** de `gastos_internos` = gate de coherencia; `idempotency_key` **sibling de `payload`** firmado **top-level** vía param **opcional aditivo** (sobres de las 11 acciones previas byte-idénticos, D-C-57); vicky/socio. **A13** `gastos.listado` = lectura companion por **período contable**, `SELECT` inline (universo filtrado en SQL, agregados en centavos + paginación en el render), **sin** `injectActor`/`isWrite`: bordes truncados a **primer día de mes** antes del clamp y del check (D-C-59), `periodo_hasta` híbrido, y el **gateway espeja esa semántica mensual** (D-C-60) incluido `null == omitido` (paridad con su wrapper directo; A25 mantiene su `null` estricto, **D-C-54 sin reabrir**); vicky/socio. La **infra de idempotencia** (`portal_idempotencia` + `portal_cargar_gasto_interno`) es **TEST-only, FUERA del canónico** (precedente `portal_usuarios`, D-C-34); `gastos_internos` se usa tal cual (sin `source_event`, sin DDL). Gateway con **allowlist doble** (D-C-39) + **action binding** (D-C-41); CATALOG con **13 entradas** (1 Edge + 8 lecturas + 4 escrituras). Validado por capa, los cuatro caminos: A11 directo 38/38 (seguridad `secWrites=0` + replay/retry/doble-click/conflictos) + gateway 24/24 (spoof de control en payload y top-level) + teardown FK-safe; A13 directo 32/32 + gateway 34/34 con **cruce al centavo** (`total_gastos=335000.00`, `n=5`) y **paridad ejecutable gateway↔wrapper 24/24**. **Cumple P-C-9 en TEST** (store de `nonce` materializado en `portal_idempotencia`; OPS viaja en la promoción coordinada). **Decisiones D-C-55/56/57/58/59/60, lecciones L-C-20/21/22/23.** OPS intacto; canónico **v1.8.1 sin cambios**; `portal_usuarios`/`portal_idempotencia` siguen TEST-only. Cierre `C_SLICE3B_CIERRE.md`. **Próxima etapa: promoción coordinada del Carril C a OPS (al cerrar el MVP) o slices societarias A14–A23 (post-MVP).**

**Carril C — Portal Operativo Interno / Contrato Frontend ↔ Portal v1 ✅ Aprobado (2026-06-22):** especificación de consumo del gateway `portal-api` desde el navegador (API reference del portal), contra el **gateway real de Slice 3b** (CATALOG 13 = 1 Edge + 8 lecturas + 4 escrituras). Reglas estructurales: transporte dual de `idempotency_key` (A10 en `payload`; A11 sibling; A07 key interna del wrapper; A08 sin key), calendarios A03/A04 = HTML temporal (`data:{formato:"html",html}`; JSON formal = P-C-3), ramificación por `body.ok` no por status HTTP (HTTP 200 + envelope, sin 401), `estado_incierto` → reconsulta de la lectura companion, errores en dos familias, menú por rol vía `sesion.contexto`. **Diseño/documento puro:** sin frontend, sin cambios en backend, n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1. **Decisiones D-FE-01…08** (namespace propio, no se mezcla con `D-C-XX`). Documento `CONTRATO_FRONTEND_PORTAL_v1.md` (`Docs/Implementacion/Carril_C/Portal_Frontend/`). Cierre `CONTRATO_FRONTEND_PORTAL_CIERRE.md`. **Próxima etapa: Frontend TEST** (sub-slices: auth + `sesion.contexto` + menú por rol → lecturas → escrituras → QA/UAT).

**Carril C — Portal Operativo Interno / Frontend TEST · sub-slice 0 (shell) ✅ Validado en TEST (2026-06-23):** primer código de frontend del Carril C — el **shell del Portal Operativo** en `apps/portal-operativo/` (React + Vite + TypeScript estricto + Tailwind; Supabase JS **solo** para auth/sesión; `callPortal` propio con `fetch` que ramifica por `body.ok`). Cubre login/logout + persistencia/autorefresh de sesión + llamada de bootstrap a `sesion.contexto` + **menú por rol armado desde `acciones`** (no hardcodeado) + placeholder por acción + `no_autorizado` → re-login. Validado en local contra TEST con evidencia visual: franco/vicky → menú completo (12 ítems / 5 grupos), jenny → solo Calendario de limpieza (exclusión económica D-C-03 sostenida desde el backend vía `acciones`); login, error de credenciales, logout y persistencia OK; consola sin errores de app (el ruido era de una extensión, L-FE-01). **Decisiones D-FE-09/10/11; lección L-FE-01.** Sin cambios en backend, n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1 (el frontend solo consume `portal-api` vía `action`). Cierre `FRONTEND_SUBSLICE0_CIERRE.md`. **Próximo: sub-slice 1 — pantallas de lectura** (A03/A04 render HTML; A05/A06/A12/A24/A25/A13 JSON; router).

**Carril C — Portal Operativo Interno / Frontend TEST · sub-slice 1 (las 8 lecturas) ✅ Cerrado (2026-06-24):** sobre el shell del sub-slice 0, las **8 pantallas de lectura** del portal (cero escrituras), validadas por rol en TEST. A03/A04 calendarios (HTML en `<iframe srcDoc>` `sandbox="allow-same-origin"` **sin** `allow-scripts`; A04 apila meses vía shim CSS inyectado en `onLoad` + autosize, D-FE-14), A05 detalle (buscador + pagos + notas), A06 prereservas, A12 saldos (columna `Reserva #id`), A24 histórico (filtros nativos check-in/cabaña/estado/texto + paginación server-side), A25 ingresos (caja seña+saldo; `otros_movimientos` aparte) y A13 gastos (período contable; sin `total` → conteo por `Σ por_clase.n`); A25/A13 con selector de mes y floor 2026-07-01. Stack: router `react-router-dom` v6 con la URL como fuente (D-FE-12), hook único `useAction` con protección de orden/unmount (D-FE-13), `DataTable`/`Paginador` compartidos `limit`/`offset` (D-FE-15), filtros con floor y `CABANAS_TEST` **solo TEST** → **P-FE-01** (D-FE-16), `RutaProtegida` por `action` (D-FE-17) y componentes en `src/ui/` (`Money` **nunca /100**, D-FE-18). Durante la integración se aplicó un **parche de consistencia A04/A12** en el backend n8n (A04 recomputa `saldo_real` con el criterio de A12; display clampeado a `$0`; notas operativas debajo del teléfono; **D-C-61/62/63**); A24 muestra `saldo_real` **crudo** (reporte) y A04 clampea (operativo) a propósito. Montos en pesos, `Money` nunca divide por 100 (**L-FE-02**). Validado en local contra TEST por rol (jenny solo calendario de limpieza; vicky/socios todo); build `tsc`+`vite build` exit 0. **Decisiones D-FE-12…18 + D-C-61/62/63; lecciones L-FE-01/02.** Sin cambios en OPS ni `6B_SCHEMA_SQL.md` v1.8.1 (las pantallas consumen `portal-api` vía `action`; único toque de backend = el parche A04/A12 sobre el wrapper n8n de TEST). Pendientes: **P-FE-01** (catálogo de cabañas), **P-FE-02** (anti-sobrecobro A10/web/MP), UX diferidas (ver `Pendiente_pre_produccion.md`). Cierre `FRONTEND_SUBSLICE1_CIERRE.md`. **Próxima etapa: pantallas de ESCRITURA (A07/A08/A10/A11).**

**Carril C — Portal Operativo Interno / Frontend TEST · sub-slice 2 (las 4 escrituras) ✅ Cerrado (2026-06-25):** sobre los **cimientos de escritura** (B1: hook `useEnviar`, átomos `Campo`/`BotonSubmit`/`TarjetaExito`/`Banner`, familias de error, tipos de respuesta y catálogos TEST), las **4 pantallas de escritura** del portal: **A08** `bloqueo.crear_manual` (sin key, guard por solapamiento), **A07** `reserva.crear_manual` (sin key; idempotencia derivada → `idempotent_match`; **seña `0`=auto 50%**, nunca se manda `monto_sena:0`, D-FE-26), **A11** `cargar.gasto_interno` (key **sibling**, condicionales por clase A/C/D/E y pagador) y **A10-MP** `cobranza.registrar_cobro` (key **en payload**, cobranza multi-porción efectivo/transferencia bancaria·mp/otros + recargo 5%, **bloqueo de sobrepago** en UI + backend en duro `conflicto`/`excede_saldo`, D-FE-21). **B5 usa solo `cobranza.registrar_cobro`**; **W10 `cobranza.registrar_saldo` queda deprecated-in-place** y desaparece del frontend por **tolerancia-forward** (rename de la entrada del registry, D-FE-27), sin tocar backend. Patrón de escritura común: `useEnviar` con transporte de `idempotency_key` por acción y ciclo key-nueva / reintento-reusa / reset-on-edit (D-FE-19/20), `estado_incierto` como flag con reconsulta de la lectura companion (D-FE-22), validación cliente espejo del gateway (D-FE-23), tarjeta de éxito + dos familias de error (D-FE-25). Se corrigió un bug de `useEnviar` bajo **React.StrictMode** (el ref `montado` quedaba en `false`; L-FE-03). Validado por bloque con `tsc`+`vite build` exit 0 (módulos 107→118); **B5 con QA TEST OK por rol** (jenny no ve/no accede + gateway `rol_no_permitido`; vicky/socio cobran) y funcional (efectivo / transferencia / MP / otros / mixto / saldada / sobrepago bloqueado en UI / conflicto por saldo stale / retry idempotente / edición = key nueva). **Decisiones D-FE-19…28; lecciones L-FE-03…07.** Sin cambios en backend, gateway `portal-api`, wrapper n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1 (las escrituras consumen el gateway vía `action`; el contrato A10-MP backend ya estaba cerrado en TEST, `A10MP_CIERRE.md`). Pendientes: **deep-link "Ver detalle" A12→A05** no implementado (**P-FE-08**), el gateway no propaga `detail.constraint` (**P-FE-07**, mensajes finos por pre-validación), **P-FE-02** anti-sobrecobro cubierto solo para el portal interno A10-MP (web/MP/autónomo siguen pendientes). Cierre `FRONTEND_SUBSLICE2_CIERRE.md`. **Próxima etapa: sub-slice 3 — QA/UAT por rol (TEST, Jenny/Vicky/socios); recién después se evalúa la promoción coordinada del Carril C a OPS.**

**Carril C — Portal Operativo Interno / Frontend TEST · sub-slice 3 (publicación TEST + piloto operativo) ✅ Cerrado (2026-06-26):** se **publicó el portal** (8 lecturas + 4 escrituras, ya validadas por bloque) en un **link TEST real** y se corrió un **piloto operativo controlado** con los usuarios reales por rol. Deploy: **build estático** (`vite build` → `dist/`) en **Vercel** (Root Directory `Apps/portal-operativo`, fallback SPA por `vercel.json`, sin `base`; dos env vars TEST browser-safe `VITE_SUPABASE_URL`+`VITE_SUPABASE_ANON_KEY`, nunca `service_role`; login email/password → sin tocar Site URL/Redirects), **D-FE-30**. Precondición bloqueante: **banner de ambiente** fijo "AMBIENTE DE PRUEBA · TEST" visible **pre-login** + título de pestaña diferenciado, derivado de `VITE_SUPABASE_URL` (ref TEST `bdskhhbmcksskkzqkcdp`; estado defensivo `'desconocido'` para lo no reconocido; **sin `VITE_AMBIENTE`**), **D-FE-29**. **7 gates en verde** (typecheck+build EXIT 0 · deploy publicado · banner visible · env a TEST · incógnito sin login = solo login+banner · login Jenny/Vicky/socio · sin `service_role`/secretos en frontend/repo/logs/instrucciones). Entregables: **instrucciones por rol** (Jenny/Vicky/socios; "es TEST, sin datos reales de huéspedes, reportar en el tracker") + **tracker de feedback**. **Piloto OK: los usuarios reales operaron sin asistencia, cero blockers, sin fixes menores.** **Decisiones D-FE-29/30; lecciones L-FE-08/09; pendiente nuevo P-FE-09** (extender el banner al ref OPS al promover). Sin cambios en backend, gateway, n8n, OPS, `6B_SCHEMA_SQL.md` v1.8.1, W10 ni el contrato (solo deploy/banner/`vercel.json` + docs); A10 frontend sigue `cobranza.registrar_cobro`. URL TEST `https://vita-delta-reservas.vercel.app`. Cierre `FRONTEND_SUBSLICE3_CIERRE.md`. **Próxima etapa: preparar la promoción coordinada del Carril C a OPS** (P-FE-01 catálogo real, P-C-7 CORS, GRANTs/seed real, P-FE-09 banner).

**Carril C — Portal Operativo Interno / Aviso 8C-bis enganchado al alta por portal (A07) ✅ Cerrado en TEST (2026-06-26):** el aviso por mail 8C-bis (al confirmar una reserva con check-in en `[hoy, hoy+7]`) se disparaba **solo desde 8B**; el wrapper **A07 del portal no lo invocaba** → un alta por el portal no avisaba. Se agregó al A07 una **rama lateral no bloqueante** (espejo de 8B) que llama `vita_w8cbis_alerta` por `executeWorkflow`, **sin lógica nueva de mail** (el sub-workflow es autocontenido: re-lee la reserva, decide la ventana, manda). **+2 nodos, +1 conexión** (22 nodos originales byte-idénticos): un **gate** `if` (solo confirmación fresca `envelope.ok===true && idempotent_match===false` → reintento idempotente no manda mail repetido) y un **`Call`** `executeWorkflow` con `onError: continueRegularOutput`, **Wait ON** (no OFF, que puede abortar el sub-workflow) y **hoja sin salida**, fan-out desde `router3_confirmar` con la **rama principal conectada primero**. **No-afectación por configuración** (no async puro): `onError` + hoja + rama principal primero → `respondToWebhook` emite en su rama (aviso falla → reserva `ok:true` igual). `entorno` desde **`leer_ambiente.valor`** (sin hardcode); input `{id_reserva, id_pre_reserva, entorno, source:'a07_portal', operador}`. Validado en TEST: **5 gates verdes**. **Decisiones D-C-71…73, lecciones L-C-24/25.** Sin cambios en backend del motor, gateway, OPS, `6B_SCHEMA_SQL.md` v1.8.1, W10 ni el contrato (el 8C-bis se reusa tal cual). **No promovido a OPS.** Cierre `AVISO_8CBIS_PORTAL_A07_CIERRE.md`. **Próxima etapa: promoción coordinada del Carril C a OPS** (P-FE-01, P-C-7, P-FE-09, GRANTs/seed real).

**Carril C — Portal Operativo Interno / promoción coordinada a OPS + canónico/kit v1.9.0 ✅ Cerrada (2026-06-29):** el Carril C completo (gateway `portal-api`, los 13 wrappers n8n y el frontend) quedó **promovido a OPS** en una operación coordinada bloque por bloque (Bloques A→H), **por DDL y sin copiar datos de TEST** (infra sin seed; usuarios Auth + seed `portal_usuarios` recién en OPS), con el canónico **bumpeado a v1.9.0** (Bloque I: las 3 estructuras internas del portal como **PARTE D** + §25). **Paridad estructural TEST↔OPS del portal por fingerprint** (`TOTAL_PORTAL` idéntica: `dee953e867aed06a9c65836bac14e8f7`) + **smokes read-only end-to-end por rol 14/14** (anti-OPS respetado: cero escrituras, cero consumo de secuencias del negocio). Los 13 wrappers `__OPS` (path sufijo `__OPS`, credencial + HMAC de OPS; paridad **lógica**, no byte) validados con escrituras reales (cobro A10-MP + alta A07; aviso 8C-bis con `entorno=ops`). Hallazgo del Bloque E: candado anti-OPS `TEST-only` hardcodeado en `verificar_acceso` de A10-MP/W10 (discriminaba por literal `!== 'test'`), removido de A10-MP, **conservado a propósito en W10** (deprecated, nunca invocado). CORS por env var `CORS_ALLOW_ORIGIN` (nunca `'*'`, **P-C-7**), HMAC propio de OPS (**P-C-8**), banner OPS sin banner (**P-FE-09**); incidente de datos del Bloque G (autofill + dedup por email) resuelto con **defensa doble capa**. Bootstrap kit regenerado a `bootstrap_entorno_nuevo_v1.9.0/` (9 archivos, verify final **estricto** por ACL real `aclexplode` + FKs/CHECK/UNIQUE por relación + firma de función + RLS off); kit `v1.8.1/` **retirado del árbol** (decisión de limpieza del cierre; queda en el historial de git). **Decisiones D-PROMO-C-01…14, lecciones L-PROMO-C-01…08; deuda D-C-64…70 (A10-MP) saldada en el ledger.** Cierre `PROMOCION_CARRIL_C_OPS_CIERRE.md`. **Próxima etapa: operación del portal sobre OPS; en frentes separados, Mercado Pago (pagos autónomos) y la web pública.**

**Reconstrucción de DEV desde v1.8.0 ✅ Cerrada (2026-06-15):** DEV se reconstruyó **desde cero** en un proyecto Supabase **nuevo** (`VITA_DELTA_DEV`, `DEV_REF=wsrdzjmvnzxidjlovlja`, PG 17.6), bootstrappeando el canónico v1.8.0 (Parte B + Parte C), **cerrado como OPS** (Data API ON, "Automatically expose new tables" OFF, auto-RLS OFF) y **sin copiar datos** de OPS/TEST. Validado al bootstrap: base = paridad 8A (2 ext, 4 enums, 20 tablas, 6 vistas, 13 funciones, 13 triggers, 2 EXCLUDE; seed 5/3/10/1/1/1; 2 jobs cron); Carril B 9 tablas / 21 funciones / 10 triggers de inmutabilidad / 6 secuencias; seam 5/5; matriz 378/456; reparto Σ exacto; `ambiente='dev'`; secuencias en 1. **Hallazgo (gap del canónico):** un bootstrap fresco de v1.8.0 deja las 13 funciones del motor PUBLIC-ejecutables (NULL-acl) porque Parte B no incorpora el REVOKE del motor (solo C12 endurece el Carril B); se aplicó el REVOKE (espejo de 7E/8A, gate `ambiente='dev'`) → 0 expuestas. **Canonizado en v1.8.1** (Bloque 23: hardening de funciones base en Parte B). **D-RDEV-01..06 / L-RDEV-01..04**, cierre `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md`. DEV viejo conservado **congelado**.

**Próxima etapa — opciones disponibles (orden sugerido):**

Con DEV, TEST, OPS, 6D, 7A-7E, **8A-8D cerradas y la Etapa 8 (operación real interna) completa**, la **sub-etapa 8C-bis** cerrada y activa en OPS, la **Etapa 9 / Carril A** en marcha (9A diagnóstico + 3a-v2 listado + **9B/3b cobranza posterior cerrada y validada en TEST**) y el **Carril B completo (9C→9H) promovido a OPS (canónico v1.8.0; capa derivada con cascada 40/40 + capa con estado validada end-to-end)**, el equipo opera el complejo con tres acciones autoservicio sobre OPS y recibe avisos automáticos por mail. Las opciones a priorizar por Franco de acá en más:

- **Promoción coordinada del Carril B a OPS (incluye 9B/3b) — ✅ hecha (jun-2026):** paquete único por DDL — objetos 9C/9D/9E/9F/9G + la **capa con estado de 9H** (5 tablas + 10 triggers + 9 funciones) + `abortar_si_falla(jsonb)` + workflow 3b `__OPS` — con bump del canónico, marcador `'ambiente'='ops'`, GRANTs/RLS a decidir, verificación de socios reales (L-9C-01) y **sin datos de TEST**. Hecho en jun-2026 con paridad estructural verificada; cierre `PROMOCION_CARRIL_B_OPS_CIERRE.md`. Ver también `Pendiente_pre_produccion.md`.
- **✅ Decisiones de negocio del Carril B — cerradas (2026-06-14):** **% operativo = 25%** (sobre ingresos cobrados del período menos gastos operativos; parámetro de cascada, D-9G-01) e **inicio contable = 2026-07-01** (períodos anteriores fuera de alcance: no se liquidan ni arrastran — D-NEG-01/02). La liquidación del `extra` ya estaba **resuelta por diseño**: ingreso post-operativo, paso 6 de la cascada (D-9G-02 / conceptual §4.3).
- **Resto de la arquitectura global de contabilidad:** caja por lugar, conversión/tabla de ahorro de monedas, cancelaciones con cargo, AFIP/ARCA/IVA (carril fiscal, separado por diseño). El bump del canónico ya llegó con la promoción del Carril B (v1.8.0). Conversación aparte.
- **Registrar la primera ejecución real de 8C-bis** cuando entre la próxima reserva con check-in en ventana. Pendiente menor: migrar el remitente SMTP al futuro mail propio de las cabañas (D-8Cbis-09).
- **Edición / baja de bloqueos:** hoy 8D solo crea (D-8D-09); levantar o corregir un bloqueo es manual. Si se vuelve frecuente, sería una capa posterior con su propio formulario.
- **Apertura al exterior (etapas futuras grandes, sobre TEST primero):** webhook MercadoPago real, bot conversacional (Claude API), web pública, WhatsApp/Instagram (Meta API), y eventualmente PROD público.
- Residual de permisos de tabla en DEV (hallazgo A5 / pendiente 1.7): **resuelto por construcción** en el DEV nuevo (creado cerrado como OPS, 2026-06-15); el item queda solo como histórico del DEV viejo congelado.

No avanzar a PROD público, dashboard, MercadoPago real, bot o frontend público sin decisión explícita del usuario y sin revisar primero `Pendiente_pre_produccion.md`.

## Forma de trabajo

1. **Primero diseñar.** No saltar directo al "configurar nodo X" o "escribir función Y".
2. **Después documentar** la decisión.
3. **Recién después implementar.**
4. **Antes de cualquier código o workflow, validar la arquitectura del paso conmigo.**
5. **Evitar sobreingeniería.** Soluciones simples, migrables y mantenibles.
6. **No mezclar prototipos con arquitectura final.**
7. **Marcar dudas como pendientes explícitos**, no resolver con supuestos silenciosos.
8. **Si se propone cambiar una decisión cerrada, explicar por qué** y esperar confirmación.
9. **Pocas preguntas críticas + supuestos explícitos** para avanzar cuando falte info.
10. **No leer archivos largos de contexto histórico** salvo que el usuario lo pida.
11. **Disciplina de EOL al propagar a satélites.** **Verificar siempre el EOL real con `git ls-files --eol` antes de editar** — no confiar en reglas mnemónicas viejas. Al cierre del **2026-06-29** (promoción del Carril C), **todos los satélites del repo están en LF** (`i/lf w/lf`): no hay `.gitattributes` y los archivos tracked son LF — la vieja nota "`ESTADO_ACTUAL_VITA_DELTA.md` = CRLF / `Lecciones_Aprendidas.md` = mixto" quedó **desactualizada** y se corrige acá. Al editarlos, **preservar el EOL real observado** (no convertir), con anclas únicas (`count==1`) y sin mega-diffs.

### Patrón establecido durante 6C (para futuros workflows)

1. **Verificación read-only de contrato real** con `pg_get_function_result`, `pg_get_functiondef`, `information_schema.columns`, `pg_constraint`, `pg_views` antes de diseñar.
2. **Diseño en chat con aprobación explícita** de decisiones.
3. **JSON importable** (no sanitizado, con credential ID real).
4. **Tests ordenados**: no destructivos primero, destructivos al final.
5. **Verificación cruzada con W1** cuando aplica.
6. **Franco exporta de n8n** con sus IDs reales.
7. **Claude sanitiza** el export y produce template del repo.
8. **Bitácora** con tabla de tests, decisiones, observaciones.
9. **Lecciones aprendidas** o bloques en `Pendiente_pre_produccion.md` si hay gotchas.

## Reglas operativas específicas para Supabase

- **NO usar `DROP ... CASCADE`** — siempre revisar dependencias primero. Las vistas (`vista_disponibilidad`, etc.) dependen de funciones; un DROP CASCADE las elimina silenciosamente.
- **Para modificar funciones existentes, intentar primero `CREATE OR REPLACE FUNCTION`.**
- **Si Supabase Dashboard interfiere agregando `ALTER TABLE ENABLE RLS` sobre variables locales con prefijo `v_`** (bug conocido), usar workaround DROP + CREATE en runs separados, **pero validando antes que no haya vistas dependientes**. Documentado en `Docs/Operacional/Lecciones_Aprendidas.md`.
- **Al alinear funciones entre entornos, comparar por huella normalizada** (`md5` de `pg_get_functiondef` quitando `\r` y formato): el DDL congelado driftea cosméticamente (comentarios/orden) sin cambiar comportamiento, y esa huella lo detecta. Para forzar la alineación, **DROP + CREATE** (no `CREATE OR REPLACE`) en runs separados, con companion de revert (L-PROMO-01 / D-PROMO-05).
- **Tests funcionales primero, limpieza después.** Validar el comportamiento esperado antes de borrar la evidencia. **La limpieza de un entorno de prueba no se improvisa:** es un bloque dedicado con SQL explícito y aprobado (snapshot → limpieza atómica → verificación), con `DELETE` en orden por FKs, sin `DROP/TRUNCATE ... CASCADE`, y doble gate anti-error-de-entorno. Patrón validado en Etapa 7D (D-7C-01, D-7D-01, D-7D-02).
- **`NOW()` en PostgreSQL retorna timestamp de transacción**, no de statement. Para validar triggers de `updated_at`, ejecutar INSERT y UPDATE en runs separados.
- **Supabase SQL Editor muestra solo el resultado del último SELECT.** Para ver múltiples resultados, usar UNION ALL con columna identificadora.
- **"TEXT libre" no implica sin restricción: verificar `CHECK` constraints antes de fijar valores persistidos** (L-8B-01). Columnas como `canal_origen`/`canal_pago_esperado`/`medio_pago`/`tipo` son TEXT pero con `CHECK` que restringe los valores. Leer los `CHECK` reales con `pg_get_constraintdef` sobre `pg_constraint`. Cuando un valor atraviesa varias tablas en cadena (pre_reservas → reservas), los valores válidos son la **intersección** de todos los `CHECK` del camino, no el de la tabla final (L-8B-02).
- **Edge Functions creadas/editadas por el Dashboard reactivan solo el toggle "Verify JWT with legacy secret"** en cada redeploy desde el editor (L-C-06). `portal-api` valida el JWT en el handler (`getUser`), así que el toggle debe quedar **OFF**: re-apagarlo tras cada edición por el editor, o usar CLI + `config.toml` (`verify_jwt=false`), que no se resetea.
- **Supabase está migrando sus API keys** (L-C-09): conviven `SUPABASE_SECRET_KEYS`/`SUPABASE_PUBLISHABLE_KEYS` (dict JSON, key `default`) con las legacy `SERVICE_ROLE_KEY`/`ANON_KEY`, y en proyectos migrados la legacy puede contener la key nueva. Resolver la secret key **defensivamente** (`SECRET_KEYS[default]` → legacy) con preflight ruidoso. El prefijo `SUPABASE_` está **reservado** para secrets → los propios van con otro nombre (ej. `VITA_HMAC_SECRET`).

## Reglas operativas específicas para n8n (consolidadas durante 6C)

- **SSL con Supabase pooler**: la credencial requiere `Ignore SSL Issues: ON` (L-6C-01).
- **Query Parameters n8n no soportan NULL real**: strings vacíos se omiten, `null` se serializa como string `"null"`. Usar convención `0=todas` + `NULLIF($N::TYPE, 0)` en la función SQL (L-6C-03).
- **`Always Output Data: ON`** en el Postgres node + filter defensivo en Code downstream para evitar que resultados vacíos detengan el flujo (L-6C-04).
- **JSONB stringify con `={{ JSON.stringify($json.payload) }}`** funciona limpio para payloads complejos (L-6C-06).
- **BIGINT serializa como string** en JSON, DATE como ISO timestamp. No requiere fix, solo conciencia operativa (L-6C-05).
- **Convención "todas las cabañas" no es universal**: W1 usa `0`, W6 usa `null`. Verificar siempre el contrato real de cada función (L-6C-08).
- **Normalización defensiva con `nv()`** en Build Payload mientras el hardening SQL no se aplique (L-6C-07).
- **Para validaciones tempranas con error estructurado**, usar nodo IF antes de Postgres (L-6C-09).
- **Campo Number vacío de un Form Trigger puede llegar como `0`, no como `""`** (L-8B-05). Para semántica "vacío → default", tratar `0`/`""`/`null`/`undefined` todos como vacío leyendo el valor crudo; validar `>0` solo para valores genuinos.
- **Form Ending es un nodo aparte** (`n8n-nodes-base.form`, `operation: completion`), no una propiedad del Form Trigger (L-8B-06). Con `Respond When = Workflow Finishes` y ramas mutuamente excluyentes por IF, se muestra el Form Ending de la rama ejecutada; la decisión del mensaje puede centralizarse en un Code previo.
- **En cadenas multi-función, enriquecer un `ctx` paso a paso** (clonado entre nodos) en vez de depender de que cada función devuelva todos los IDs (L-8B-07). Tras cada Postgres con `Continue On Fail`, normalizar la salida distinguiendo error técnico de error de negocio; un `ok:true` puede no bastar (ej. `registrar_pago` degradado a `en_revision`, L-8B-03).
- **Al barrer nodos Code buscando marcadores de entorno, comparar por substring, no por palabra** (`\btest\b` no matchea `n8n_test_`): al portar un workflow entre entornos, revisar los marcadores de entorno embebidos en el código, no solo la credencial (L-PROMO-03 / L-8D-03).
- **Webhook con "Raw Body" ON entrega el cuerpo crudo como BINARIO** (`item.binary.data`, mime `application/json`), **no** como `$json.rawBody` (L-C-05). Para HMAC byte-exacto, leerlo en el Code node con `await this.helpers.getBinaryDataBuffer(0,'data')` (fallback a `rawBody`). Aplica a todo workflow de acción que valide firma sobre el raw body.
- **`crypto` está whitelisteado** en el Code node de n8n Cloud (se usa con `require('crypto')`): permite HMAC-SHA256 y `timingSafeEqual` para revalidar la firma del gateway (L-C-09).
