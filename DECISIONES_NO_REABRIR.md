# DECISIONES NO REABRIR — VITA DELTA

Estas decisiones ya fueron trabajadas y NO deben reabrirse salvo contradicción crítica explícita. Si se propone reabrir una, justificar por qué y esperar confirmación del usuario.

---

## Arquitectura general

- **Supabase/PostgreSQL es la base de datos del sistema.** La migración Sheets → Supabase ya se completó a nivel de diseño e implementación en DEV (Etapa 6B), y los workflows n8n contra Supabase ya están operativos en DEV (Etapa 6C). **No revisitar la opción "volver a Sheets".**
- **n8n es el orquestador operativo de workflows.** Recibe eventos, arma payloads, llama funciones SQL, maneja respuestas y dispara comunicaciones. No reemplazar con otra plataforma en esta etapa. Las reglas críticas viven en PostgreSQL.
- **Apps Script** queda congelado como legado. Solo puede usarse para lectura/reportería histórica de Sheets si el usuario lo pide explícitamente. No debe incorporarse a nuevos flujos operativos.
- **Google Sheets** ya NO es la fuente de verdad. Puede usarse para reportería pero no para escritura crítica.
- **La IA no ejecuta lógica crítica.** Conversa, interpreta, ordena, pero no confirma reservas ni pagos por sí sola.
- **El sistema tiene una sola fuente de verdad** (Supabase → tabla `reservas` y derivadas).

## Modelo de datos y consistencia

- **`fecha_in` es inclusive, `fecha_out` es exclusive.** El día de salida no se cobra como noche pero la cabaña puede estar ocupada hasta el horario de check-out de ese día.
- **Modelo daterange `[)`** para evitar solapamientos. Validado empíricamente: permite reservas pegadas (5-6, 6-7, 7-8 jun) en la misma cabaña sin gaps obligatorios. Maximiza ocupación.
- **EXCLUDE constraint** sobre `reservas` y `bloqueos` es protección estructural. No se puede eludir con bugs de aplicación. Imposible de saltearse.

## Reservas y disponibilidad

- **Toda reserva confirmada pasa por `confirmar_reserva()`.** No existe INSERT directo a la tabla `reservas` desde n8n ni desde ningún lugar.
- **`crear_prereserva()` es PUERTA ÚNICA** para crear pre-reservas. Implementa locks (advisory locks anidados: global → por cabaña), idempotencia (vía `idempotency_key`), validación de disponibilidad y cálculo de horarios.
- **Pre-reservas vigentes bloquean disponibilidad temporalmente** hasta que expiran o se confirman.
- **Revalidación obligatoria antes de confirmar.** `confirmar_reserva()` re-chequea disponibilidad bajo locks.
- **Confirmación tiene dos caminos**: estricto (pago confirmado por Mercado Pago) y combinado (pago en revisión + validación humana).
- **Operaciones críticas son secuenciales** vía locks. No hay concurrencia destructiva.
- **Acciones automáticas registran `source_event`** para trazabilidad.

## Locks y concurrencia

- **Lock global SIEMPRE va primero**, después el lock por cabaña. Este orden es INVARIANTE.
- **Lock por cabaña usa cast `::INTEGER`** (la firma `pg_advisory_xact_lock(integer, integer)` no acepta `BIGINT` en segundo argumento). Decisión cerrada del v1.6.

## Disponibilidad

- **La disponibilidad no se edita manualmente ni vive en una cache como fuente de verdad.** Es derivada del estado de `reservas`, `pre_reservas` y `bloqueos`, expuesta mediante funciones/vistas como `obtener_disponibilidad_rango()` y `vista_disponibilidad`.
- **El bot y la web no calculan disponibilidad por su cuenta.** Consultan `obtener_disponibilidad_rango()` y/o las vistas (`vista_disponibilidad`, etc.).
- **n8n consulta funciones del schema**, no escribe directo a las tablas (salvo casos muy controlados).

## Precios

- **Los precios viven en TARIFAS.**
- **`configuracion_general` NO guarda precios de alojamiento.** Guarda horarios, expiración, switches operativos.
- **El tipo de cabaña determina la tarifa.** Las cabañas específicas heredan tarifas por tipo.
- **Año Nuevo y eventos especiales NO pasan por el motor estándar.** Tienen su propio mecanismo (CAPA_DE_CARGOS futura + `eventos_especiales`).

## Horarios operativos

- **Check-in default: 13:00.**
- **Check-in domingo: 18:00** (por última lancha colectiva).
- **Check-out default: 10:00.**
- **Check-out domingo: 16:00** (regla D47 / hotfix v1.7). Por la misma razón operativa de la lancha. No hay solapamiento porque el check-in del próximo huésped en domingo es a las 18:00.
- **Cliente puede elegir horarios dentro del rango** (`hora_checkin_min_cliente` / `hora_checkin_max_cliente` / `hora_checkout_min_cliente` / `hora_checkout_max_cliente`).
- **Validación del rango la hace `crear_prereserva()`.** Si el cliente elige hora fuera de rango, error `hora_fuera_de_rango` con `minimo` y `maximo` apropiados según día.

## Trazabilidad y auditoría

- **Doble log validado y aceptado**:
  - Triggers `trg_log_*_estado` capturan transiciones de estado puras (campo_modificado='estado', valor_anterior, valor_nuevo).
  - Logs explícitos de las funciones capturan eventos de negocio (evento='prereserva_creada', 'prereserva_vencida', etc.).
  - Ambos coexisten y son complementarios. No es duplicación errónea.
- **`set_config('app.modificado_por', ...)` + `set_config('app.source_event', ...)`** (D38) es el mecanismo para que triggers automáticos hereden el contexto de la función llamante.

## Mantenimiento automático

- **`pg_cron` corre `expirar_prereservas_vencidas()` cada 5 minutos.**
- **`cleanup_cron_history`** limpia historial mensualmente (día 1 a las 03:00 UTC).
- **Sistema es resiliente sin el cron** — las funciones manuales también detectan pre-reservas vencidas vía `WHERE expira_en > NOW()`. El cron acelera la limpieza visible pero no es crítico para integridad.

## IA

- **La IA conversa, interpreta, ordena y guía** al usuario.
- **La IA NO confirma pagos.**
- **La IA NO confirma disponibilidad real.**
- **La IA NO modifica RESERVAS directamente.**
- **La IA llama workflows determinísticos** cuando necesita operar (vía n8n → funciones del schema).

## Migración y compatibilidad

- **La decisión de migración Sheets → Supabase está cerrada y el backend Supabase DEV fue implementado** (Etapa 6B). No volver atrás a Sheets como fuente de verdad.
- **Los workflows n8n contra Supabase fueron implementados y validados en DEV** (Etapa 6C, cerrada el 2026-05-26). No volver a workflows contra Sheets como camino productivo.
- **El nuevo backend funcional vive en Supabase DEV.** Los archivos `*.gs`, `index.html`, y JSONs de tests del Bloque 13 son **artefactos del pasado pre-migración** y no son fuente de verdad actual.
- **Los workflows legacy contra Sheets están congelados** en `Workflows/n8n/*.template.json` (sin subcarpeta) y se conservan solo como referencia histórica. No se mantienen ni se actualizan.

## Reglas operativas para modificar el schema

- **No usar `DROP ... CASCADE`.** Las vistas dependen de funciones (ej. `vista_disponibilidad` depende de `obtener_disponibilidad_rango`). Un DROP CASCADE puede eliminar dependencias silenciosamente y romper consultas posteriores.
- **Intentar primero `CREATE OR REPLACE FUNCTION`** para modificar funciones existentes.
- **Si Supabase Dashboard interfiere** agregando `ALTER TABLE ENABLE RLS` sobre variables locales con prefijo `v_` (bug conocido del Dashboard, no del schema), usar workaround DROP + CREATE en runs separados, **validando antes que no haya vistas o funciones dependientes** que se rompan con el DROP. Documentado en `Lecciones_Aprendidas.md`.

## Workflows n8n contra Supabase (Etapa 6C — cerrada 2026-05-26)

Las siguientes decisiones quedaron firmes durante la implementación y validación de los 8 workflows W0-W7. **NO REABRIR sin justificación crítica.**

### Estructura de workflows

- **Patrón de 5 nodos lineal** para workflows write (W2-W6):
  ```
  Manual Trigger → Build Input → Build Payload → Postgres → Build Response
  ```
- **Patrón de consulta paramétrica** para W1:
  ```
  Manual Trigger → Build Input → Postgres → Build Response
  ```
- **Patrón de 6 nodos con IF** para W7 (validación temprana de whitelist de vistas con ramificación que evita ejecutar Postgres si el input es inválido).
- **No agregar nodos intermedios** (HTTP Request, Transform, Wait, etc.) en estos workflows write. Si en el futuro se necesita lógica adicional, debe vivir en la función SQL o en un workflow separado que llame al actual.

### Wrapper externo unificado

Todos los workflows devuelven un wrapper consistente:

```json
{
  "ok": true/false,
  "workflow": "vita_wNN_nombre_supabase",
  "source_event": "n8n_wNN_nombre_manual",
  "idempotency_key": "..." | null,
  "id_evento_dev": "...",
  "error": null | "codigo",
  "warning": null | "codigo",
  "result": { },
  "executed_at": "ISO timestamp"
}
```

Extensiones específicas:
- `idempotency_key` solo aplica en W2 (`crear_prereserva` es la única función con idempotencia explícita).
- `warning` solo aplica en W3 (caso v1.3 de pago tardío sobre pre-reserva terminal).
- `vista` solo aplica en W7.

### Normalización defensiva con `nv()`

Patrón establecido a partir de W3: aplicar `nv()` (convierte `""` o `undefined` a `null`) a **todos los campos del payload, incluidos los obligatorios**.

```javascript
const nv = (v) => (v === '' || v === undefined ? null : v);
```

Razón: las funciones SQL del schema actual no aplican uniformemente `NULLIF(TRIM(...))` a los campos obligatorios de texto. La normalización en n8n es una mitigación temporal hasta que se aplique el hardening SQL (documentado en `Pendiente_pre_produccion.md`).

### Convenciones de naming

- **Workflows:** `vita_w{NN}_{nombre}_supabase` (ej. `vita_w02_crear_prereserva_supabase`).
- **Templates en repo:** `<nombre_workflow>.template.json` dentro de `Workflows/n8n/supabase/`.
- **Source events:** `n8n_w{NN}_{nombre_corto}_{disparador}` (ej. `n8n_w02_crear_prereserva_manual`). No incluye ambiente.
- **`id_evento_dev`** para trazabilidad de pruebas en el wrapper: `{canal}_{id_evento}` (ej. `manual_dev_test_w02_001`).

### Convención de "todas las cabañas" — NO universal

Diferencia de contrato entre funciones, documentada y no se unifica:

- **W1** (`obtener_disponibilidad_rango(date,date,bigint)`): la función SQL usa `NULL` para "todas". En n8n se adoptó la convención `id_cabana = 0` porque Query Parameters no soportó `NULL` real; el SQL del workflow convierte `0` a `NULL` con `NULLIF(..., 0)`.
- **W6** (`crear_bloqueo`): `id_cabana = null` significa "todas". La función no trata 0 como caso especial — `0` resultaría en `cabana_no_existe`.

**Cada función define su propia semántica.** Siempre verificar el contrato real antes de asumir.

### Idempotencia diferenciada por función

Las funciones SQL del schema NO tienen idempotencia uniforme — cada una refleja su semántica de negocio:

| Función | Idempotencia |
|---|---|
| `crear_prereserva` | Sí, con `idempotency_key` + `idempotent_match=true` (puerta única crítica) |
| `registrar_pago` | No (deduplicación es responsabilidad del caller — webhook MP) |
| `confirmar_reserva` | No (re-ejecutar devuelve `estado_invalido` con `estado_actual`) |
| `cancelar_prereserva` | No (re-ejecutar devuelve `estado_no_cancelable` con `estado_actual`) |
| `crear_bloqueo` | No (re-ejecutar devuelve `bloqueo_solapado` con `bloqueos_en_conflicto`) |

**No agregar idempotencia artificial client-side** en n8n. El caller real (webhook MP, bot, frontend) debe manejar su propia deduplicación cuando corresponda.

### Patrón de trabajo establecido para nuevos workflows

Verificado en 8 workflows consecutivos. **NO saltar pasos:**

1. **Verificación read-only de contrato real** con `pg_get_function_result`, `pg_get_functiondef`, `information_schema.columns`, `pg_constraint`, `pg_views` antes de diseñar.
2. **Diseño con aprobación explícita** de decisiones de payload, defaults, plan de tests.
3. **JSON importable** (sin sanitizar, con credential ID real) para que Franco lo importe directo.
4. **Tests ordenados** (no destructivos primero, destructivos al final).
5. **Verificación cruzada con W1** cuando el workflow modifica disponibilidad (W5 cancelación, W6 bloqueo).
6. **Franco exporta** desde n8n con sus IDs reales.
7. **Claude sanitiza** el export → template del repo con placeholders.
8. **Bitácora detallada** por workflow en `Docs/Bitacora/6C_EJECUCION.md`.
9. **Lecciones aprendidas** en `Lecciones_Aprendidas.md` si hay gotchas.
10. **Pendientes pre-producción** en `Pendiente_pre_produccion.md` si hay hallazgos estructurales.

### Sanitización antes de commit

- Reemplazar `__CREDENTIAL_ID__`, `__CREDENTIAL_NAME__`, `__WORKFLOW_ID__`, `__WORKFLOW_VERSION_ID__`, `__N8N_INSTANCE_ID__`.
- **Build Input del template debe tener los valores del happy path**, no del último test ejecutado al exportar.
- Verificar que no haya secrets ni datos reales de huéspedes.

### Settings de Postgres node

- **`Always Output Data: ON`** es obligatorio (L-6C-04: resultados vacíos detienen el flujo sin esto).
- **No requiere `Max Concurrency = 1`** porque PostgreSQL serializa con advisory locks. A diferencia de los workflows legacy contra Sheets.

## Decisiones aprobadas con código de referencia

- **D3** — Mantener solo `hora_checkin` y `hora_checkout` en tablas (sin "hora base" vs "hora real").
- **D27** — Horarios = lo elegido por cliente, validado contra margen.
- **D35** — Idempotencia post-lock vía `idempotency_key`.
- **D37** — Horarios leídos de `configuracion_general` con fallback COALESCE.
- **D38** — Triggers leen contexto vía `current_setting('app.modificado_por', TRUE)`.
- **D47** — Regla operativa de domingo: check-in 18:00 y check-out 16:00. Implementada en `crear_prereserva()` por hotfix v1.7 y propagada a `obtener_disponibilidad_rango()` en la alineación v1.7.1 (ejecutada en DEV el 2026-05-25).

## Lecciones operativas n8n consolidadas (L-6C-XX)

Reglas firmes derivadas de la ejecución de la Etapa 6C. Detalle completo en `Lecciones_Aprendidas.md`.

- **L-6C-01:** Credencial PostgreSQL contra pooler de Supabase requiere `Ignore SSL Issues: ON`.
- **L-6C-03:** Query Parameters de n8n no soportan NULL real. Workaround: convención `0=todas` + `NULLIF($N::TYPE, 0)` en función SQL.
- **L-6C-04:** Postgres node con result vacío detiene el flujo. Mitigación obligatoria: `Always Output Data: ON` + filter defensivo en Code downstream.
- **L-6C-05:** BIGINT serializa como string en JSON, DATE como ISO timestamp. Consciencia operativa, no requiere fix.
- **L-6C-06:** `={{ JSON.stringify($json.payload) }}` funciona limpio para JSONB en `queryReplacement`.
- **L-6C-07:** Normalización defensiva con `nv()` en obligatorios mientras el hardening SQL no se aplique.
- **L-6C-08:** Convención "todas las cabañas" no es universal (W1 `0=todas`, W6 `null=todas`). Verificar siempre el contrato real.
- **L-6C-09:** Para validaciones tempranas con error estructurado, usar nodo IF antes de Postgres.

## Prototipos legacy

- `index.html` — presentación visual estática del estado del sistema. No es frontend operativo ni web pública de reservas.
- `vita_delta_workflow.json` y similares — pilotos del backend pre-Supabase.
- Archivos `.gs` — scripts de Apps Script del backend viejo.
- Archivos JSON de tests del Bloque 13 (`dev_db_*.json`, `test_db_*.json`) — artefactos de validación pre-migración.
- `Workflows/n8n/*.template.json` (sin subcarpeta `supabase/`) — workflows legacy contra Sheets, congelados.

**Ninguno de estos artefactos debe contradecir las decisiones cerradas de las Etapas 1-6C ni de las Fases 1-3 de implementación en DEV.**
