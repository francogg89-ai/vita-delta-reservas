# CLAUDE.md — Vita Delta Reservas

## Regla principal

Antes de trabajar, leer en este orden:

1. ESTADO_ACTUAL_VITA_DELTA.md
2. DECISIONES_NO_REABRIR.md
3. 6B_SCHEMA_SQL.md (schema canónico actual: v1.7.1)
4. 6C_CIERRE.md (cierre formal de workflows n8n contra Supabase DEV)
5. 6B_PLAN_FASES.md
6. Docs/Bitacora/6B_EJECUCION_DEV.md (si necesitás contexto histórico de implementación de backend)
7. Docs/Bitacora/6C_EJECUCION.md (si necesitás contexto histórico de implementación de workflows)
8. Docs/Operacional/Lecciones_Aprendidas.md (gotchas operativos)
9. Docs/Operacional/Pendientes_Pre_Produccion.md (items para deploy a prod)

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

**Schema canónico actual:** `6B_SCHEMA_SQL.md v1.7.1`. **DEV está 100% alineado.**

**Próxima etapa — Por decidir entre 4 opciones:**

- **A — Hardening pre-producción:** ejecutar items de `Pendiente_pre_produccion.md` (NULLIF/TRIM en funciones write, fix de `vista_ocupacion`, etc.). Recomendado como primer paso.
- **B — Entorno TEST:** replicar DEV en proyecto Supabase separado.
- **C — Webhook MercadoPago:** primer consumidor productivo de W3 + W4.
- **D — Bot conversacional (Etapa 4B implementación):** habilita canal Instagram + WhatsApp.

Recomendación documentada en `6C_CIERRE.md`: **A primero, después B**. Cerrar deudas técnicas conocidas antes de complicar el sistema con nuevos consumidores.
No avanzar a MercadoPago real, bot conversacional, frontend público o producción sin decisión explícita del usuario y sin revisar primero `Pendientes_Pre_Produccion.md`.

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
- **Tests funcionales primero, limpieza después.** Validar el comportamiento esperado antes de borrar la evidencia.
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
