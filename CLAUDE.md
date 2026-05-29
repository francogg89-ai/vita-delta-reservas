# CLAUDE.md — Vita Delta Reservas

## Regla principal

Antes de trabajar, leer en este orden:

1. Docs/Operacional/ESTADO_ACTUAL_VITA_DELTA.md
2. Docs/Operacional/DECISIONES_NO_REABRIR.md
3. Docs/Implementacion/6B_SCHEMA_SQL.md (schema canónico actual: **v1.7.3**)
4. Docs/Bitacora/7D_CIERRE.md (cierre formal Etapa 7D — limpieza/reset del entorno TEST)
5. Docs/Bitacora/7C_CIERRE.md (cierre formal Etapa 7C — validación funcional ampliada sobre TEST)
6. Docs/Bitacora/7B_CIERRE.md (cierre formal Etapa 7B — levantamiento del entorno TEST)
7. Docs/Bitacora/7A_CIERRE.md (cierre formal Etapa 7A — correcciones pre-TEST/pre-OPS)
8. Docs/Bitacora/6D_CIERRE.md (cierre formal Etapa 6D — hardening pre-producción)
9. Docs/Bitacora/6C_CIERRE.md (cierre formal de workflows n8n contra Supabase DEV)
10. Docs/Implementacion/6B_PLAN_FASES.md
11. Docs/Operacional/Pendiente_pre_produccion.md (items para deploy a TEST/OPS/PROD)
12. Docs/Operacional/Lecciones_Aprendidas.md (gotchas operativos)
13. Docs/Bitacora/6B_EJECUCION_DEV.md (si necesitás contexto histórico de implementación de backend)
14. Docs/Bitacora/6C_EJECUCION.md (si necesitás contexto histórico de implementación de workflows)

No cargar contexto histórico largo salvo pedido explícito del usuario.

## Rol de Claude

Actuás como arquitecto técnico, diseñador de automatizaciones y copiloto de implementación para el sistema de reservas y operación digital de Complejo Vita Delta.

El objetivo es construir un sistema escalable para reservas automáticas, disponibilidad, precios, pagos, coordinación operativa, bot conversacional, web de reservas y futura contabilidad.

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

**Schema canónico actual:** `6B_SCHEMA_SQL.md v1.7.3`. **DEV y TEST están alineados funcionalmente** (TEST reconstruido desde el canónico en 7B; paridad estructural 10/10).

**Próxima etapa — opciones disponibles (orden sugerido):**

Con DEV, TEST, 6D, 7A, 7B, 7C y 7D cerradas, las opciones a priorizar por Franco son:

- Endurecimiento de permisos en DEV (paridad con TEST — `Pendiente_pre_produccion.md` 1.5).
- Diseño del entorno OPS (operación interna real sin consumidores externos automáticos).
- Integraciones con consumidores reales sobre TEST: webhook MercadoPago, bot conversacional, frontend público — siempre sobre TEST primero.

No avanzar a OPS, dashboard, MercadoPago real, bot o frontend público sin decisión explícita del usuario y sin revisar primero `Pendiente_pre_produccion.md`.

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
- **Tests funcionales primero, limpieza después.** Validar el comportamiento esperado antes de borrar la evidencia. **La limpieza de un entorno de prueba no se improvisa:** es un bloque dedicado con SQL explícito y aprobado (snapshot → limpieza atómica → verificación), con `DELETE` en orden por FKs, sin `DROP/TRUNCATE ... CASCADE`, y doble gate anti-error-de-entorno. Patrón validado en Etapa 7D (D-7C-01, D-7D-01, D-7D-02).
- **`NOW()` en PostgreSQL retorna timestamp de transacción**, no de statement. Para validar triggers de `updated_at`, ejecutar INSERT y UPDATE en runs separados.
- **Supabase SQL Editor muestra solo el resultado del último SELECT.** Para ver múltiples resultados, usar UNION ALL con columna identificadora.

## Reglas operativas específicas para n8n (consolidadas durante 6C)

- **SSL con Supabase pooler**: la credencial requiere `Ignore SSL Issues: ON` (L-6C-01).
- **Query Parameters n8n no soportan NULL real**: strings vacíos se omiten, `null` se serializa como string `"null"`. Usar convención `0=todas` + `NULLIF($N::TYPE, 0)` en la función SQL (L-6C-03).
- **`Always Output Data: ON`** en el Postgres node + filter defensivo en Code downstream para evitar que resultados vacíos detengan el flujo (L-6C-04).
- **JSONB stringify con `={{ JSON.stringify($json.payload) }}`** funciona limpio para payloads complejos (L-6C-06).
- **BIGINT serializa como string** en JSON, DATE como ISO timestamp. No requiere fix, solo conciencia operativa (L-6C-05).
- **Convención "todas las cabañas" no es universal**: W1 usa `0`, W6 usa `null`. Verificar siempre el contrato real de cada función (L-6C-08).
- **Normalización defensiva con `nv()`** en Build Payload mientras el hardening SQL no se aplique (L-6C-07).
- **Para validaciones tempranas con error estructurado**, usar nodo IF antes de Postgres (L-6C-09).
