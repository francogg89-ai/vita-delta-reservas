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
Manual Trigger → Build Input → Build Payload → Postgres → Build Response
- **Patrón de consulta paramétrica** para W1:
Manual Trigger → Build Input → Postgres → Build Response
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

**Razón original (Etapa 6C):** las funciones SQL del schema no aplicaban uniformemente `NULLIF(TRIM(...))` a los campos obligatorios de texto. La normalización en n8n era una mitigación.

**Estado actual (post-Etapa 6D):** el hardening SQL fue aplicado en las 5 funciones write críticas durante bloques H2-H4-ter (sesión 2026-05-26). Las funciones ahora aplican `NULLIF(TRIM(...))` en sus extracts. Aun así, **los `nv()` defensivos se mantienen en n8n como defensa en profundidad** (ver D-HARD-05). No remover.

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

## Hardening pre-producción (Etapa 6D — H1-H7 cerrados)

Las siguientes decisiones quedaron firmes durante las sesiones del hardening pre-producción:
- H1 a H6-bis (sesión 2026-05-26, hardening estructural): D-HARD-01 a D-HARD-06.
- H7 (sesión 2026-05-27, tests de concurrencia): D-HARD-07 a D-HARD-11.

**NO REABRIR sin justificación crítica.**
Bitácora detallada: `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### D-HARD-01 — Patrón canónico de extract defensivo

Aplicado al extract de payload de las 5 funciones write críticas (`registrar_pago`, `confirmar_reserva`, `crear_prereserva`, `cancelar_prereserva`, `crear_bloqueo`). Asignaciones de extract unificadas al patrón:

```sql
v_campo := NULLIF(TRIM(payload->>'campo'), '')::TIPO;
```

Cubre vacíos y whitespace antes del cast. **No agregar validación adicional para tipos inválidos no vacíos** (ej. `id_cabana="abc"`, `fecha_in="no-es-fecha"`) — eso queda fuera del alcance del hardening por strings/whitespace y se trata como item pendiente separado.

### D-HARD-02 — TRIM agresivo en obligatorios

Whitespace puro (`"   "`) en campo obligatorio equivale a vacío equivale a NULL. La función rebota con `payload_invalido` en vez de aceptar el whitespace como valor o intentar castearlo. Aceptado por consistencia con el patrón canónico D-HARD-01.

### D-HARD-03 — Cambio observable consistente

Whitespace en campo obligatorio devuelve `payload_invalido`, no errores específicos del dominio (como `motivo_invalido`, `huesped_nombre_requerido` u otros). Esto significa que algunos errores que antes eran específicos pasaron a ser estructurales:

- `motivo: "   "` en `cancelar_prereserva` → antes `motivo_invalido` con `motivos_validos`; ahora `payload_invalido`.
- `motivo: "   "` en `crear_bloqueo` → mismo cambio.
- `creado_por: "   "` en `crear_bloqueo` → antes aceptado como nombre del creador; ahora `payload_invalido`.

Los errores específicos del dominio siguen vigentes para valores no-vacíos fuera de enum (ej. `motivo: "fantasma"` → `motivo_invalido`).

### D-HARD-04 — `id_cabana="   "` en `crear_bloqueo` se interpreta como bloqueo total

Caso especial documentado: en `crear_bloqueo`, `id_cabana = NULL` significa "bloqueo total" (válido, no error). El patrón canónico mantiene esa semántica:

- `id_cabana: null` → bloqueo total.
- `id_cabana: ""` → bloqueo total (ya era así antes del hardening, vía `NULLIF` previo).
- `id_cabana: "   "` → bloqueo total (cambio observable nuevo).
- `id_cabana: 17` → bloqueo específico.

Aceptado por consistencia con el patrón. **No se rediseña el contrato** para tratar whitespace como error específico — `crear_bloqueo` mantiene su semántica de "null = total".

### D-HARD-05 — `nv()` en n8n se mantiene como defensa en profundidad

Aun con el hardening SQL aplicado en las 5 funciones write, los workflows n8n mantienen el `nv()` defensivo en obligatorios. **No remover.**

Razón: defensa en profundidad. Si en el futuro algún consumidor llama directo a las funciones SQL sin pasar por los workflows, el hardening protege. Si llama vía workflows, `nv()` actúa como primera línea redundante. Ambas líneas coexisten.

Esta decisión consolida el patrón de mitigación documentado durante 6C y lo eleva a estrategia explícita post-hardening.

### D-HARD-06 — UPDATE de `huespedes` para normalizar `apellido=""` NO ejecutado

La Parte 6.2 del plan original de H6 contemplaba un UPDATE sobre `huespedes` para normalizar `apellido = ''` a `NULL`. **No se ejecutó.**

Razón: al abrir H6, DEV ya tenía `apellido = NULL` en los 2 huéspedes existentes (limpieza entre cierre de 6C y apertura de 6D eliminó los huéspedes con `apellido = ''`). `upsert_huesped()` ya aplicaba `NULLIF(TRIM(apellido), '')` desde antes del hardening, por lo que huéspedes futuros no van a tener el problema. El TRIM en vistas (H6, H6-bis) actúa como defensa adicional.

**No reabrir.** Si en el futuro se detectan huéspedes con `apellido = ''` o whitespace en DEV/TEST/PROD, ejecutar un UPDATE puntual con `WHERE TRIM(apellido) = ''`, pero no es necesario como parte de un plan de hardening estructural.

### D-HARD-07 — Nomenclatura de tests de concurrencia H7 consolidada

Los 6 tests de concurrencia ejecutados en H7 mantienen una nomenclatura mixta consolidada, no se renombran:

- **C-1 a C-4:** versión consolidada documentada en `Pendiente_pre_produccion.md` Sección 6.1 (vigente al iniciar H7).
  - C-1: `crear_prereserva` + `crear_bloqueo total`.
  - C-2: `cancelar_prereserva` + `crear_bloqueo total`.
  - C-3: `confirmar_reserva` + `crear_bloqueo específico`.
  - C-4: doble `confirmar_reserva` sobre la misma pre-reserva.
- **C-5 y C-6:** legacy del plan original 6B Sección 6.8, agregados como complementarios para no perder cobertura histórica.
  - C-5: `confirmar_reserva` + `cancelar_prereserva` (regresión del deadlock pre-v1.5).
  - C-6: doble `crear_prereserva` con misma `idempotency_key`.

Orden de ejecución en H7: C-1 → C-2 → C-5 → C-3 → C-4 → C-6. Frenos especiales (`40P01` en C-5 bloqueaba C-3/C-4/C-6; `40P01` en C-3 bloqueaba C-4/C-6) no se activaron.

**No reabrir.** Si en el futuro se vuelven a ejecutar tests de concurrencia (en TEST o post-cambios estructurales), mantener esta nomenclatura. No renombrar a "C-3 ↔ C-5" para "alinear con el plan original".

### D-HARD-08 — Convención `source_event` para tests de concurrencia

Todos los recursos creados en H7 usan `source_event` con el prefijo:

```
test_H7_C{N}_{ROL}
```

Donde `{N}` ∈ `{1, 2, 3, 4, 5, 6}` y `{ROL}` ∈ `{A, B, FIXTURE, FIXTURE_PR, FIXTURE_PAGO}`. Ejemplos: `test_H7_C1_A`, `test_H7_C5_FIXTURE_PR`, `test_H7_C5_FIXTURE_PAGO`.

**Cleanup por test con prefijo específico** (`LIKE 'test_H7_C{N}_%'`), no cleanup global al final de la sesión. Reduce contaminación si un test rompe a mitad de camino.

**No reabrir.** Para futuras sesiones de concurrencia (TEST, repetir H7, agregar tests nuevos), mantener el mismo patrón pero variando el nombre de la sesión (`test_TEST_C{N}_{ROL}`, `test_H7r_C{N}_{ROL}`, etc.).

### D-HARD-09 — Mecánica de paralelismo para tests con `pg_sleep`

Para tests de concurrencia con `pg_sleep` largo en una transacción y otra lanzada poco después, la mecánica aprobada es:

1. **Dos tabs separadas del navegador** (no la opción "+" interna del SQL Editor que comparte runner cliente).
2. **Mini-test de validación previo** con `pg_sleep(5)` simultáneo en ambas tabs, verificando PIDs distintos y solapamiento temporal.
3. **CTEs encadenadas con `MATERIALIZED` + `FROM cte_anterior`** para garantizar orden de ejecución dentro de cada tab.
4. **`clock_timestamp()` y `pg_backend_pid()`** dentro de las CTEs para captura empírica de inicio/fin/PID y reporte en una sola fila del último SELECT.

Validado empíricamente durante H7. PIDs siempre distintos entre tabs (rango observado: 359653-378629). Lock global serializó consistentemente con `B.elapsed` entre 6.058s y 6.539s.

**No reabrir.** Si por algún motivo dos tabs del navegador no logran paralelismo (versión nueva de Supabase, restricción de sesión, etc.), las alternativas ordenadas son: ventana incógnita o segundo navegador → `psql` local contra el pooler → mover Tab B a un workflow n8n manual (A queda en SQL Editor). Validar siempre con mini-test previo.

### D-HARD-10 — Cobertura empírica parcial de ramas de idempotencia es aceptable

C-6 de H7 observó empíricamente la rama `post_lock` del detector de idempotencia de `crear_prereserva` (sección 5.bis del cuerpo). Las otras dos ramas (`pre_lock` y `unique_violation`, secciones 3 y 9 respectivamente) están vigentes en el cuerpo de la función y son alcanzables por diseño, pero **no fueron gatilladas en H7** por el timing del test (B llegó al pre-check antes del COMMIT de A, no después).

**Decisión:** la cobertura parcial es aceptable y no bloqueante para avanzar a TEST o a integraciones reales. Las 3 ramas están presentes en el cuerpo de la función y validadas estáticamente. La rama `post_lock` queda validada empíricamente bajo concurrencia real.

**No reabrir.** Si en el futuro se considera necesario gatillar empíricamente `pre_lock` o `unique_violation`, queda documentado como item opcional pre-PROD en `Pendiente_pre_produccion.md` Sección 6.3. No es regresión ni bug abierto.

### D-HARD-11 — Freno duro ante `40P01` en cualquier test de concurrencia

Cualquier aparición de `40P01 (deadlock_detected)` en una sesión de tests de concurrencia es **señal de regresión estructural**, no de "mala suerte" ni de un caso edge tolerable. La política aprobada es **freno duro sin reintento**.

Frenos especiales adicionales documentados en H7 (no activados):

- `40P01` en C-5 (regresión v1.5) bloquea C-3, C-4, C-6.
- `40P01` en C-3 (lock global + lock por cabaña combinados) bloquea C-4, C-6.

Razón: la corrección estructural v1.5 (lock global SIEMPRE primero, antes de FOR UPDATE / lock por cabaña / table-level) elimina la posibilidad de deadlock cruzado. Si aparece `40P01`, una de las funciones involucradas violó la invariante de orden — eso no se resuelve reintentando, se resuelve auditando el cuerpo de la función.

**No reabrir.** Mantener la política. No agregar reintentos automáticos ni tolerancia a deadlocks en workflows n8n o en código de cliente.

## Correcciones pre-TEST / pre-OPS (Etapa 7A — cerrada 2026-05-28)

Decisiones firmes derivadas de la Etapa 7A — correcciones livianas pre-TEST/pre-OPS aplicadas y validadas en DEV. Resolvieron los pendientes 1.1, 1.2 y 1.3 de `Pendiente_pre_produccion.md`. Schema canónico bumpeado a v1.7.3. **NO REABRIR sin justificación crítica.**

Bitácora de la etapa: `7A_CIERRE.md`. Todas las decisiones fueron validadas empíricamente en DEV (9 tests funcionales del patch `crear_prereserva` + 4 tests del horizonte configurable).

### D-7A-01 — `canal_pago_esperado` requerido en validación manual de `crear_prereserva`

`crear_prereserva` valida `canal_pago_esperado` en su IF de obligatorios. Si el campo llega ausente, vacío o whitespace puro, el extract canónico `NULLIF(TRIM(...), '')` lo convierte a NULL y la función rebota con `error='payload_invalido'` (rebote temprano, antes de `set_config`, antes de `upsert_huesped` y antes de cualquier lock).

- La columna `pre_reservas.canal_pago_esperado` permanece `TEXT NOT NULL`. **No se hizo nullable.**
- El CHECK constraint `chk_pre_reservas_canal_pago` (5 valores: `transferencia_bancaria`, `transferencia_mp`, `mp_link`, `cripto`, `efectivo`) permanece sin cambios.
- **Fuera de alcance del patch:** validación manual de valores no-NULL fuera del CHECK (ej. `canal_pago_esperado="canal_invalido"`). Esos siguen rebotando por el CHECK constraint con error crudo de PostgreSQL, no por validación manual controlada. Coherente con D-HARD-01 (el hardening por strings/whitespace no cubre tipos/valores inválidos no vacíos).

**Motivación:** antes del patch, `canal_pago_esperado` no estaba en la validación manual; un payload sin el campo llegaba al INSERT y fallaba con error crudo de constraint NOT NULL en vez de `payload_invalido` controlado. Relevante para OPS (carga manual de Vicky) y para futuros consumidores (webhook MP, bot, frontend).

**No reabrir.** Si en el futuro aparece un caso de uso "pre-reserva sin canal de pago definido", se resuelve quitando la condición del IF (más simple que recuperar un `NOT NULL` perdido), con decisión explícita.

### D-7A-02 — `ninos` como TEXT nullable con semántica de detalle operativo

`crear_prereserva` declara la variable local `v_ninos` como `TEXT` (antes `BOOLEAN`) y su extract es `v_ninos := NULLIF(TRIM(payload->>'ninos'), '');` (sin cast a BOOLEAN). Las columnas `pre_reservas.ninos` y `reservas.ninos` ya eran `TEXT nullable`; el cambio alinea la variable con las columnas.

Semántica definitiva:
- `NULL` = no informado (payload ausente, vacío o whitespace).
- Texto libre = detalle operativo (cantidad, edades, necesidades). Ejemplo: `"2 niños, 3 y 6 años"`, `"Bebé con cuna"`.
- El literal `"false"` **no** es un valor esperado nuevo (era residuo del cast implícito BOOLEAN→TEXT de v1.7.2).
- **No se introduce `detalle_ninos`** como columna separada. Se evaluará solo si aparece una necesidad operativa concreta de separar presencia (booleana) de detalle (texto), análogo a `mascotas`/`detalle_mascotas`.

**Motivación:** antes del patch, el cast `::BOOLEAN` persistía `"false"` para payloads sin `ninos` y rompía con error crudo si llegaba texto libre real (ej. `'2 niños...'::BOOLEAN` → `invalid input syntax for type boolean`). El cambio habilita información operativamente útil para Jennifer (limpieza) y Vicky (mensajes a clientes).

**Nota de limpieza (no es decisión):** los 3 registros legacy con `ninos='false'` (pre_reservas 25, 26; reserva 8) fueron migrados a `NULL` mediante limpieza puntual de datos durante 7A. Es limpieza puntual documentada en `7A_CIERRE.md`, **no una decisión arquitectural** y **no tiene número de decisión**.

**No reabrir.**

### D-7A-03 — Horizonte de disponibilidad/calendario configurable

El horizonte forward de `vista_disponibilidad` y `vista_calendario` se lee desde `configuracion_general.horizonte_disponibilidad_dias` (antes hardcoded a 60), con fallback `120` por `COALESCE`. Valor actual en DEV: `120`.

```sql
... COALESCE(
  (SELECT valor::INTEGER FROM configuracion_general
   WHERE clave = 'horizonte_disponibilidad_dias'),
  120
) ...
```

Convenciones de rango (cada vista mantiene la suya; solo cambió el valor, no la semántica del operador):
- **`vista_disponibilidad`:** rango exclusivo `[CURRENT_DATE, CURRENT_DATE + N)` vía `obtener_disponibilidad_rango`. Con N=120, `MAX(fecha) = CURRENT_DATE + 119`, 120 días distintos.
- **`vista_calendario`:** filtro inclusivo `r.fecha_checkin <= (CURRENT_DATE + N)`. El operador `<=` se mantuvo; **no se cambió a `<`**.

La clave `horizonte_disponibilidad_dias` se agregó al seed del Bloque 21 (`categoria='disponibilidad'`, `tipo_valor=NULL`, `editable=true`) para que TEST/PROD nazcan con ella y no dependan solo del fallback. Cambio futuro del horizonte sin redeploy: `UPDATE configuracion_general SET valor='<N>' WHERE clave='horizonte_disponibilidad_dias';`.

**Nota:** la clave ya existía en DEV antes de la Etapa 7A (origen probable: ejecución histórica intermedia, no auditada en esta sesión). 7A solo normalizó su `descripcion` y conectó las vistas para que la usen.

**No reabrir** la decisión de hacer el horizonte configurable ni las convenciones de rango por vista. El valor concreto (120) sí es ajustable vía UPDATE sin tocar schema.

## Levantamiento del entorno TEST (Etapa 7B — cerrada 2026-05-28)

Decisiones firmes derivadas de la Etapa 7B — levantamiento del entorno TEST como proyecto Supabase independiente, paritario y aislado de DEV. **NO REABRIR sin justificación crítica.**

Bitácora de la etapa: `7B_CIERRE.md`. Cadena W2 → W3 → W4 validada end-to-end en TEST; 8 workflows con happy paths aprobados. DEV no se tocó durante 7B (solo consultas read-only de diagnóstico).

### D-7B-01 — TEST como proyecto Supabase independiente, no clon físico de DEV

TEST se construyó como **proyecto Supabase separado** (`vita-delta-test`), reconstruyendo el schema **desde el canónico `6B_SCHEMA_SQL.md v1.7.3`** — no por dump/restore desde DEV ni por copia física. La paridad estructural se demostró 10/10 vs DEV mediante script comparativo (extensiones, enums, tablas, vistas, funciones, triggers, EXCLUDE, CHECK, FK, índices únicos).

Esto garantiza que TEST queda alineado con la fuente de verdad documental (el canónico) y evita arrastrar artefactos accidentales de DEV (datos huérfanos, ALTERs históricos no auditados, claves duplicadas, etc.). El procedimiento se ejecutó en 6 tandas (Bloques 1-20 del canónico + Bloque 21 seeds + Bloque 22 cron).

**No reabrir.** Futuros entornos (OPS, PROD) deben seguir el mismo patrón: reconstrucción desde el canónico vigente, no clonación de DEV/TEST/OPS.

### D-7B-02 — IDs de cabaña no portables entre DEV y TEST

DEV conserva IDs históricos `17-21` para las 5 cabañas (Bamboo, Madre Selva, Arrebol, Guatemala, Tokio). TEST nació limpio con IDs `1-5` para las mismas cabañas (mismo seed Bloque 21, secuencia arrancando en 1). **Los IDs no son portables entre ambientes.**

Aprendizaje consolidado: **lo portable es la estructura lógica de los workflows, no los valores de input.** Cada workflow debe usar los IDs reales del ambiente al que apunta. En la práctica:
- Workflows DEV mantienen inputs de prueba con IDs `17`/`19`/etc.
- Workflows `__TEST` usan IDs `1`/`3`/etc.
- Workflows OPS/PROD futuros usarán los IDs que tengan en su seed.

**No reabrir.** No se renumerará DEV (riesgo de romper FKs reales y referencias históricas en `log_cambios`, `reservas`, `pagos`, etc.) ni se renumerará TEST para "alinear" con DEV. Si en el futuro un workflow se mueve entre ambientes, los inputs de prueba se adaptan; la lógica del workflow no cambia.

### D-7B-03 — Modelo de grants mínimo en TEST, no paridad de grants con DEV

TEST adopta un **modelo cerrado de permisos Data API**, distinto al de DEV:

- Roles `anon`, `authenticated`, `service_role`: sin grants Data API útiles sobre objetos del proyecto (solo `Dxtm` residual, ver abajo).
- `PUBLIC`: sin `EXECUTE` sobre las 13 funciones del proyecto (REVOKE explícito en 7B-GRANTS).
- Owner `postgres` intacto (n8n entra como owner por pooler, ejecuta por ownership).
- RLS postergado (decisión histórica: hasta tener frontend público).
- `Dxtm` residual (TRUNCATE/REFERENCES/TRIGGER) sobre tablas/vistas se documenta como **aceptado, no removido**. No incluye SELECT ni escritura; no habilita lectura/escritura vía Data API; es default de Supabase post-cambio del 30/05/2026; revocarlo agrega complejidad sin cerrar riesgo real.
- `sequences` sin grants Data API (estado de fábrica respetado).

**DEV queda más abierto que TEST a propósito.** No se aplicó endurecimiento equivalente a DEV durante 7B (decisión explícita: 7B no toca DEV). El endurecimiento de DEV era pendiente futuro separado (ver `Pendiente_pre_produccion.md` 1.5). _(Actualización: ese pendiente quedó cerrado en la Etapa 7E para el EXECUTE sobre funciones — ver D-7E-01 y `7E_CIERRE.md`. Resta solo el residual de permisos de tabla en DEV, registrado como pendiente 1.7.)_

**No reabrir.** Ningún workflow ni consumidor en TEST debe asumir grants Data API que no estén explícitos. Si un consumidor futuro requiere acceso vía PostgREST/Data API en TEST (ej. dashboard, frontend), se diseña un perfil de grants específico para ese consumidor — no se reabre el modelo mínimo general.

### D-7B-04 — Convención de aislamiento de workflows TEST

Los workflows que apuntan a TEST se duplican con convenciones explícitas que evitan colisión con los de DEV:

- **Naming:** sufijo `__TEST` en el `name` del workflow (ej. `vita_w02_crear_prereserva_supabase__TEST`).
- **Credencial:** propia y separada — `vita_supabase_test` (apunta al pooler de TEST con user `postgres.<TEST_REF>`).
- **Limpieza pre-import:** eliminar `id`, `versionId` y `meta.instanceId` del JSON exportado para que n8n cree workflows nuevos en lugar de pisar los de DEV.
- **`source_event` con marcador de ambiente:** `n8n_test_w0X_..._manual` (los workflows DEV mantienen `n8n_w0X_..._manual`). Se persiste en `log_cambios` para los writes.
- **`idempotency_key` de W2 con prefijo de ambiente:** `manual_test_...` (W2 es el único workflow con idempotency_key explícita; W3-W6 no la usan). Se persiste en la pre-reserva → inequívoca de TEST.
- **`canal` en inputs de prueba:** `manual_test` en TEST (vs `manual_dev` en DEV). Alimenta `id_evento_test` (renombrado desde `id_evento_dev` en los workflows TEST que lo usaban: W5, W6, W3, W4).
- **IDs de cabaña reales del ambiente** (1-5 en TEST, 17-21 en DEV; ver D-7B-02).

**No reabrir.** Cualquier nuevo workflow para TEST debe mantener esta convención. Para OPS/PROD futuros se generaliza el patrón con sus propios marcadores (`__OPS`, `__PROD`, `n8n_ops_...`, `n8n_prod_...`, etc.).

### D-7B-05 — Regla operativa: funciones nuevas en `public` requieren REVOKE EXECUTE

Los defaults de PostgreSQL aplican `EXECUTE` a `PUBLIC` automáticamente al crear cada función (lo confirmamos empíricamente en 7B-GRANTS: las 13 funciones del proyecto tenían EXECUTE-PUBLIC tras Bloque 9-19 a pesar de que TEST "nació cerrado" en el snapshot pre-objetos).

**Regla:** toda función nueva creada en el schema `public` de TEST (y eventualmente OPS/PROD) debe revisarse y normalizarse con:

```sql
REVOKE EXECUTE ON FUNCTION <nombre>(<firma>) FROM PUBLIC, anon, authenticated, service_role;
```

como paso explícito de su creación, no asumir que "nace cerrada". El owner (`postgres`) conserva su capacidad de ejecutar por ownership, independientemente del REVOKE.

Esta regla se aplicó retroactivamente a DEV en la Etapa 7E (cerrada 2026-05-28): las 13 funciones existentes de DEV quedaron con `REVOKE EXECUTE` a PUBLIC/anon/authenticated/service_role, en paridad con TEST. Ver D-7E-01 y `7E_CIERRE.md`. _(Nota: la redacción original de D-7B-05 dejaba DEV como pendiente futuro; ese pendiente — `Pendiente_pre_produccion.md` 1.5 — quedó cerrado por 7E.)_

**No reabrir.** Es una regla operativa de creación, no una decisión arquitectónica negociable.

### D-7C-01 — Política de no-limpieza de fixtures de 7C

La validación funcional ampliada (Etapa 7C, cerrada 2026-05-28) generó datos vivos en TEST que se **conservan como evidencia**, no se limpian:

- Pre-reserva id 3 (Madre Selva, 1-4 ago, `pago_en_revision`).
- Pre-reserva id 4 (Tokio, 10-13 sep, `pendiente_pago`).
- Pago id 2 (sobre pre-reserva 2 convertida, `en_revision`) y pago id 3 (sobre pre-reserva 3, `en_revision`).
- Bloqueo id 2 (Bamboo, 2-3 ago, activo) — mutación no planificada pero válida, generada durante A-W6-06 con `id_cabana:1`; el sistema actuó correctamente ante un payload válido.
- Huéspedes id 3 e id 5.

Todos quedan trazables por `source_event` / `id_evento_test` / `idempotency_key` con marcador de ambiente TEST.

**Regla:** cualquier reset/limpieza de TEST debe ser un **bloque separado, con SQL explícito y aprobación previa**. No se improvisa caso por caso ni en medio de una validación. El diseño de ese bloque queda como pendiente (ver `Pendiente_pre_produccion.md` 6.5).

Las lecciones operativas de 7C (L-7C-01 a L-7C-06) quedaron consolidadas en `Lecciones_Aprendidas.md`; no se duplican aquí.

**No reabrir.**

### D-7D-01 — Reset de secuencias a 1 en las tablas vaciadas de TEST

En la limpieza/reset de TEST (Etapa 7D, cerrada 2026-05-28), se reseteó a 1 la secuencia de cada tabla efectivamente vaciada con datos: `pagos`, `reservas`, `pre_reservas`, `bloqueos`, `huespedes`, `log_cambios`, vía `ALTER SEQUENCE ... RESTART WITH 1`.

- Las secuencias del **seed estructural** (`cabanas`, `socios`, `temporadas`, `plantillas_mensajes`, `cuentas_cobro`) **no se tocaron**.
- Las secuencias de las **condicionales sin uso** (`consultas`, `overrides_operativos`, `gastos`) **no se tocaron** (estaban en `null`, nunca usadas).
- Los nombres de secuencia **no se hardcodearon**: se obtuvieron de `pg_get_serial_sequence` en el snapshot pre-reset y se usaron textualmente.

**Regla operativa:** cualquier reset futuro de un entorno de prueba debe resetear únicamente las secuencias de las tablas que vacía, nunca las del seed estructural, y obtener los nombres de secuencia del catálogo, no de memoria. **No reabrir.**

### D-7D-02 — Vaciado de `log_cambios` en TEST con evidencia documentada

En la Etapa 7D se vació `log_cambios` en TEST (18 filas, todas de prueba 7B/7C). La evidencia de auditoría **no se archivó en una tabla dentro de TEST**; quedó documentada en `7D_CIERRE.md` (snapshot mínimo: total, conteo por `tabla_afectada`, conteo por `source_event`, rango temporal).

**Regla:** la traza de auditoría de pruebas vive en los documentos de cierre, no en tablas archivo dentro del entorno. **No reabrir.**

### Método de limpieza/reset de TEST (regla derivada de 7D)

El método validado y a reutilizar para cualquier reset de entorno de prueba:

- **`DELETE` explícito** en orden seguro por foreign keys (`pagos` → `reservas` → `pre_reservas` → `bloqueos` → `huespedes` → `log_cambios`). **Sin `DROP ... CASCADE`, sin `TRUNCATE`, sin `TRUNCATE ... CASCADE`.**
- **Transacción única atómica** (`BEGIN`/`COMMIT`).
- **Doble gate anti-error-de-entorno:** preflight read-only previo + re-gate dentro de la transacción (`RAISE EXCEPTION` si la identidad de las 5 cabañas no coincide con el entorno objetivo).
- **Snapshot read-only previo** + **verificación posterior** como bloques separados del destructivo (nunca un único bloque opaco).

**No reabrir** salvo contradicción crítica.

### D-7E-01 — Endurecimiento de permisos Data API en DEV (7E estricta)

En la Etapa 7E (cerrada 2026-05-28) se aplicó a DEV el `REVOKE EXECUTE` sobre las 13 funciones del proyecto a `PUBLIC`, `anon`, `authenticated` y `service_role`, dejando el owner `postgres` intacto. Cierra el pendiente explícito 1.5 (`Pendiente_pre_produccion.md`) y deja DEV en paridad con TEST en cuanto a ejecución de funciones vía Data API.

Verificado (Bloque C): 0 fugas de `EXECUTE` para los 4 grantees, owner `postgres` intacto en las 13, `postgres` sigue ejecutando por ownership (n8n no afectado), schema sin cambios (201 funciones / 6 vistas / 19 triggers), residual de tablas intacto (480 grants).

El alcance fue **estricto**: solo `EXECUTE` sobre funciones. El residual amplio de permisos sobre tablas/vistas/secuencias a roles Data API (hallazgo A5: `SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN` sobre todas las tablas, mucho más amplio que el `Dxtm` de TEST) **NO se tocó** y queda como asimetría documentada (ver `Pendiente_pre_produccion.md` 1.7).

La regla operativa heredada de TEST (D-7B-05) ahora aplica también a DEV: toda función nueva en `public` de DEV debe revisarse con `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated, service_role` como paso de su creación. Documento de cierre: `7E_CIERRE.md`. **No reabrir.**

### D-7E-02 — Funciones de trigger incluidas en el REVOKE por paridad

Las 3 funciones de trigger (`log_cambio_estado`, `set_telefono_normalizado`, `set_updated_at`) se incluyeron en el `REVOKE EXECUTE` de 7E. Es inocuo —los triggers se disparan por el motor, no por `EXECUTE` de un rol— y mantiene paridad total con el endurecimiento de TEST. **No reabrir.**

## Levantamiento del entorno OPS (Etapa 8A — cerrada 2026-05-29)

Decisiones firmes derivadas de la Etapa 8A — creación de `vita-delta-ops`, el tercer entorno (DEV → TEST → OPS → PROD) y el **primer entorno de operación real interna**. Reconstruido desde el canónico `6B_SCHEMA_SQL.md v1.7.3`, paritario, seguro, con pg_cron activo y conectado a n8n. **NO REABRIR sin justificación crítica.**

Bitácora de la etapa: `8A_CIERRE.md`. Paridad estructural P01-P10 10/10 vs canónico. DEV no se tocó en toda la etapa (criterio: DEV en pausa hasta abordar su pendiente 1.7). El smoke de cierre fue solo lectura (ver D-8-12); el primer write real será una reserva real por 8B.

### Ficha del entorno OPS (referencia firme)

- **Proyecto:** `vita-delta-ops` · **OPS_REF:** `lpiatqztudxiwdlcoasv`
- **Región:** sa-east-1 (São Paulo) · **Tier:** Free · **PostgreSQL:** 17.6
- **Switches de creación:** Data API ON · "Automatically expose new tables" **OFF** · "Enable automatic RLS" **OFF**
- **Pooler:** host `aws-1-sa-east-1.pooler.supabase.com`, puerto `6543`, db `postgres`, user `postgres.lpiatqztudxiwdlcoasv`
- **Credencial n8n:** `vita_supabase_ops` (Postgres, Ignore SSL Issues ON — L-6C-01)
- **Modelo de acceso:** Opción A (n8n entra como `postgres` por pooler; sin consumidores Data API; RLS postergado)
- **IDs reales de cabaña en OPS:** Bamboo=1, Madre Selva=2, Arrebol=3, Guatemala=4, Tokio=5 (secuencia natural; en el form de 8B se eligen por nombre, ver D-8-10).

### D-8-09 — OPS es operación real interna desde el inicio

OPS **no es un entorno de prueba más**: es el entorno real interno donde viven los datos reales de reservas. Jerarquía firme: DEV (desarrollo) → TEST (pruebas funcionales completas, antes de pasar a OPS) → OPS (operación real interna; sin pruebas destructivas ni experimentos; solo smoke mínimo controlado) → PROD (futuro, público). OPS todavía no es PROD público, pero sí operación real interna. **No reabrir.**

### D-8-13 — Default privileges de OPS: cerrado sin ejecución

El diagnóstico del Bloque 7 (snapshot `pg_default_acl`) mostró que los defaults del rol `postgres` —los únicos que rigen los objetos que crea el proyecto— conceden a los roles Data API solo el residual inocuo `Dxtm` (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN), sin SELECT/INSERT/UPDATE/DELETE/EXECUTE. Por lo tanto, **todo objeto futuro creado por el proyecto nace cerrado** y D-8-03 (OPS nace con grants mínimos) queda cumplida **sin necesidad de `ALTER DEFAULT PRIVILEGES`**.

Los 21 defaults "amplios" detectados pertenecen al rol de plataforma `supabase_admin`, **no aplican a objetos creados por el proyecto** y **no se modifican**. Se mantiene la línea de 7B: cerrar lo propio, no reconfigurar la plataforma. Tocar los defaults de `supabase_admin` sería riesgo sin beneficio de seguridad real mientras OPS sea Opción A (Data API no en uso). **No reabrir.**

### Confirmación de cumplimiento de D-8-03 (OPS nació más cerrado que TEST)

A diferencia de TEST —donde el default de PostgreSQL concedía EXECUTE-PUBLIC y hubo que revocarlo (D-7B-05)—, en OPS las 13 funciones nacieron con `proacl` NULL (solo owner) y las tablas con solo `Dxtm` inocuo para roles Data API, gracias al switch "Automatically expose new tables = OFF" desde la creación. El diagnóstico del Bloque 6 confirmó 0 funciones con EXECUTE a Data API y 0 grants de lectura/escritura a roles Data API sobre tablas.

El `REVOKE EXECUTE` sobre las 13 funciones a PUBLIC/anon/authenticated/service_role **se aplicó igual** (Opción B elegida por Franco) como barrera explícita e intencional y para paridad de procedimiento con 7B/7E, no porque hubiera EXECUTE que quitar. Es idempotente y no afecta al owner `postgres`. La regla operativa D-7B-05 aplica a OPS para funciones futuras. **No reabrir.**

### Regla heredada para PROD (derivada de 8A)

Futuros entornos (PROD) deben crearse con los **mismos switches** que OPS — Data API ON, "Automatically expose new tables" OFF, "Enable automatic RLS" OFF — para nacer cerrados desde el día cero, en vez de remediar después (como hubo que hacer en TEST/DEV). Reconstrucción desde el canónico vigente, nunca clonación física (consistente con D-7B-01). **No reabrir.**

## Capa de carga interna de reservas (Etapa 8B — cerrada 2026-05-30)

Decisiones firmes de la Etapa 8B — capa de carga interna vía Form Trigger n8n que encadena `crear_prereserva` → `registrar_pago` → `confirmar_reserva` en una acción. Diseño verificado contra los contratos reales de OPS (read-only), validado funcionalmente en TEST y con smoke OPS exitoso (primera reserva real: id 1, Tokio, Paula Lugo). Documento de diseño: `ARQUITECTURA_ETAPA_8B_CAPA_CARGA.md v3.5`. Cierre: `8B_CIERRE.md`. **NO REABRIR sin justificación crítica.**

### D-8B-01 — Capa = Form Trigger que encadena las 3 funciones en una acción
El encadenado vive en n8n; el motor mantiene sus 3 funciones separadas (locks, idempotencia, revalidación intactos). Camino estricto (pago confirmado). Sin INSERT directo a tablas transaccionales.

### D-8B-02 — Formulario para celular, mínimo texto libre
Desplegables para todo lo enumerable, date pickers, numéricos; texto libre solo para nombre+apellido (campo único), teléfono, email, notas, niños.

### D-8B-03 — `operador` autodeclarado por desplegable
Desplegable obligatorio (Franco/Vicky/Rodrigo/Remo), sin login individual en el MVP.

### D-8B-04 — Trazabilidad del operador por contrato real
Operador embebido en `source_event` + `validado_por` explícito en `registrar_pago` (NULL se convierte en `'sistema_auto'`, por eso se manda explícito) + `created_by` en `confirmar_reserva`. Verificado contra OPS.

### D-8B-05 — Pago = seña, no total
`tipo='sena'`, `monto_esperado=monto_recibido=seña`, `estado_inicial='confirmado'`. El saldo lo deriva `confirmar_reserva` como `monto_total − monto_sena`. La capa no calcula ni manda el saldo.

### D-8B-06 — `idempotency_key` Opción A (constraint parcial confirmada)
`ops_8b_<id_cabana>_<fecha_in>_<fecha_out>_<contact_key>`, donde `contact_key` = teléfono solo dígitos o `email_<email>`. La constraint `uq_prereservas_idempotency_activa` es **parcial** (solo estados activos), por lo que una recarga tras cancelación no choca. Opción B (con fecha de carga) descartada.

### D-8B-07 — Fallo parcial → compensación activa con regla de comunicación
Si P2 o P3 fallan tras crear la pre-reserva, se intenta cancelar vía `cancelar_prereserva`. El mensaje se decide por `pagos_asociados_count`: count=0 → reversión limpia; count>0 → revisión manual mencionando el/los pago/s. **Nunca comunicar "revertido" si quedó un pago registrado.**

### D-8B-08 — Colisión → mensaje de negocio claro
`no_disponible`/`conflicto_al_confirmar` se traducen a "Esa cabaña ya está ocupada en esas fechas", nunca error técnico crudo.

### D-8B-09 — Punto de extensión 8C marcado, repintado NO construido
En 8B solo se deja un nodo placeholder post-`confirmar_reserva` ok. El repintado del calendario se construye en 8C.

### D-8B-10 — Form Trigger protegido con Basic Auth
Sin URL abierta. Sin IP Allowlist (los celulares tienen IP móvil/dinámica).

### D-8B-11 — Fechas: flujo normal hoy/futuro
`fecha_in >= hoy` y `fecha_out > fecha_in` en el flujo normal. Reservas pasadas o ya iniciadas quedan fuera, requieren decisión manual (consistente con D-8-01, sin backfill).

### D-8B-12 — Nombre del huésped en campo único (revisada en v3.3)
Un único campo "Nombre y apellido" obligatorio, persistido completo en `huesped.nombre` con `apellido` vacío. Reemplaza la decisión previa de apellido obligatorio separado (la función no lo usa estructuralmente; el campo único es más simple para el operador).

### D-8B-13 — Seña Variante A
Campo seña vacío o 0 → n8n calcula 50% del total automáticamente; valor >0 → se respeta. Pago 100% se carga como total=X, seña=X. Texto de ayuda "dejá vacío para 50% automático".

### D-8B-14 — Validación completa en TEST, smoke mínimo en OPS
Batería funcional completa en TEST antes de OPS; smoke en OPS con reserva real futura (primer write real, hecho).

### D-8B-15 — Verificación estricta del resultado de `registrar_pago`
Tras P2 no basta `ok:true`: se exige `ok && estado==='confirmado' && sin warning`. Un `ok:true` con `estado='en_revision'`/`warning` (pre-reserva no activa) se trata como anómalo con pago registrado → revisión manual.

### D-8B-16 — Capacidad/cabaña la valida el motor, no la capa
`crear_prereserva` ya valida `cabana_no_existe`/`cabana_inactiva`/`excede_capacidad`. La validación en n8n es solo UX temprana; la defensa de integridad la da el motor.

### D-8B-17 — Normalización del teléfono para la key en n8n
Solo dígitos (quitar espacios, guiones, paréntesis, `+`). No requiere E.164 perfecto, sí consistencia. Si no hay teléfono, `contact_key = email_<email_min>`.

### D-8B-18 — Convención de `source_event`
`<marcador_ambiente>_w8b_carga_<operador>_manual`, con operador en minúscula sin espacios (`franco`/`vicky`/`rodrigo`/`remo`). Marcador: `n8n_ops`/`n8n_test` según ambiente.

### D-8B-19 — `encargado_semana` vacío en 8B
No se mezcla "quién cargó" (cubierto por operador/source_event/validado_por/created_by) con el rol rotativo de la semana. Se deja vacío.

### D-8B-20 — Motivo de cancelación en la compensación
`motivo='cliente'` + `descripcion='rollback_8b_fallo_cadena'` (uso técnico de un motivo permitido por el contrato, con descripción que lo distingue de una cancelación normal del cliente).

### D-8B-21 — Desplegables con strings compatibles con CHECK reales
`canal_origen`/`canal_pago_esperado`/`medio_pago` son TEXT con CHECK (no enums). Etiqueta visible amigable → string persistido compatible: `canal_origen` ∈ {whatsapp, instagram, web, manual} (Directo/Referido/Otro→manual, Airbnb/Booking→web, con origen fino preservado en `notas` como "Origen operativo: …"); `canal_pago_esperado`/`medio_pago` ∈ {transferencia_bancaria, transferencia_mp, mp_link, cripto, efectivo}. `pre_reservas.canal_origen` es más restrictivo que `reservas.canal_origen` (no acepta airbnb/booking) y manda por ser la primera puerta de la cadena.

### D-8C-22 — Resguardo en Google Sheets vía n8n (HTTP a API REST), NO Apps Script
El Sheet de resguardo se escribe desde n8n mediante HTTP Request contra la API REST de Google Sheets (`values:clear` + `values:update`), reutilizando la credencial OAuth existente. Se evaluó y **descartó Apps Script** con argumento reforzado: reintroducir Apps Script (jubilado en la migración 6A) justo para el resguardo —la pieza de menor criticidad de 8C— empeoraría la arquitectura sin beneficio. El único caso donde Apps Script ganaría (que el Sheet se autogestione con trigger interno) contradice el propósito del resguardo: si n8n está vivo para darle los datos desde Supabase, n8n también puede escribir el Sheet directamente. La lógica de calendario vive en un solo lugar (n8n), versionable y trazable. NO reabrir salvo aparición de un caso concreto donde Apps Script aporte (no identificado en 8C).

### D-8C-23 — Formato del resguardo: grilla con meses apilados, sin colores, clear+write
Grilla cabañas×días (consistente con el operativo) con meses apilados verticalmente en una sola hoja (sin pestañas-por-mes en Sheets, por robustez: manejar creación/limpieza dinámica de hojas agrega fragilidad en la pieza que debe ser más confiable); sin pintado de colores (datos completos y legibles priorizados; el formato de fondos en Sheets va por otra API y es costoso/frágil); estrategia clear+write (POST `values:clear` sobre rango amplio + PUT `values:update` desde A1) para reflejar el estado actual sin residuos. Disparo manual, con el workflow diseñado autónomo para invocación futura desde el punto de extensión de 8B (post-`confirmar_reserva`). El ancho de columnas no se autoajusta (mejora opcional menor): el ancho fijado a mano se conserva entre regeneraciones porque clear+write solo toca valores, no formato.

### D-8D-01 — 8D = Form Trigger que llama a `crear_bloqueo()` en una acción
La capa de bloqueos operativos es un formulario n8n que invoca `crear_bloqueo()` una sola vez (sin cadena, sin pagos, sin compensación). El motor valida todo (cabaña, fechas, motivo, y los tres tipos de conflicto: reserva, pre-reserva, bloqueo solapado); la capa es solo UX + mensajería. Sin INSERT directo a `bloqueos`; sin tocar schema.

### D-8D-02 — Una cabaña por vez; varias cabañas = varias cargas
8D bloquea una cabaña por formulario. Para bloquear varias cabañas específicas, se cargan varios bloqueos separados. No hay selección múltiple. Evita errores parciales y compensaciones.

### D-8D-03 — NO se expone el bloqueo total (`id_cabana IS NULL`) en el formulario
El motor soporta el bloqueo total del complejo, pero NO se expone en el formulario: nunca se usó en la práctica; si hiciera falta, se cubre con cargas individuales de las 5 cabañas. La capacidad sigue existiendo en la función por si en el futuro se decide exponerla.

### D-8D-04 — Mensajes de conflicto unificados; errores de entrada diferenciados
Los tres conflictos (`conflicto_con_reserva`, `conflicto_con_prereserva`, `bloqueo_solapado`) muestran un mismo mensaje unificado ("Esas fechas no están disponibles para bloquear. Revisá el calendario."). Los errores de entrada (`fechas_invalidas`, `cabana_no_existe`, `motivo_invalido`, `payload_invalido`) llevan mensajes claros y diferenciados, porque indican qué corregir.

### D-8D-05 — El mensaje de conflicto NO expone IDs ni datos de reservas/pre-reservas
Cuando un bloqueo se rechaza por conflicto, el formulario solo informa que las fechas no están disponibles; nunca muestra IDs, nombres ni datos de las reservas/pre-reservas en conflicto.

### D-8D-06 — `source_event` = `n8n_<marcador>_w8d_bloqueo_<operador>_manual`
Convención de trazabilidad análoga a 8B. Marcador de entorno `test`/`ops` (en una constante `TEST_OPS` al inicio del nodo Validar); operador en minúscula sin espacios.

### D-8D-07 — Basic Auth propia de 8D, separada de 8B y 8C
El Form Trigger de bloqueos usa una credencial Basic Auth propia, distinta de la del formulario de carga 8B y de las de los calendarios 8C. No reutilizar credenciales entre formularios/públicos.

### D-8D-08 — `fecha_hasta` exclusive; campo "Fecha hasta / liberación" + mensaje humano
Se mantiene el modelo `[)` (fecha hasta exclusive). El campo se llama "Fecha hasta / liberación" con ayuda explícita ("ese día YA NO queda bloqueado; para bloquear 10, 11 y 12, poner desde 10 y hasta 13"), y el mensaje de éxito se expresa en lenguaje humano mostrando el último día inclusive (`fecha_hasta − 1`, solo en el texto) y el día de liberación. La validación de fechas la hace el motor.

### D-8D-09 — 8D SOLO CREA bloqueos; corregir/levantar es manual controlado
El formulario 8D solo crea bloqueos. No hay edición ni baja desde el formulario. Para corregir un bloqueo cargado por error o levantarlo antes de tiempo, se requiere intervención manual controlada (`activo=false` vía SQL aprobado, o un workflow dedicado futuro). Riesgo operativo aceptado conscientemente para el MVP; una capa de edición/baja sería una etapa posterior si se vuelve necesaria.

## Alerta por reserva próxima (Sub-etapa 8C-bis — cerrada 2026-06-04)

Decisiones de la sub-etapa que recoge el item 3.1 de `Pendiente_pre_produccion.md` (notificación a Jennifer / equipo por reserva próxima). No reabren los cierres de 8B, 8C ni 8D. Detalle en `8C-bis_CIERRE.md`.

### D-8Cbis-01 — Canal de notificación = mail (SMTP)
La alerta se envía por **mail** (nodo SMTP de n8n), no por Telegram ni WhatsApp. WhatsApp queda reservado para comunicación externa con huéspedes (PROD). Remitente SMTP a título temporal = Gmail personal de Franco (credencial n8n "SMTP gmail"); migrable al futuro mail propio de las cabañas cambiando solo la credencial/remitente, sin rediseño (ver D-8Cbis-09).

### D-8Cbis-02 — Disparo en rama lateral desde 8B, nunca en serie
8C-bis se invoca desde el PUNTO EXTENSION de 8B (post-`confirmar_reserva` OK) mediante Execute Workflow, **en rama lateral**: el PUNTO EXTENSION alimenta `Build Response` (rama principal, item original) y el Call (rama lateral) en paralelo, y el Call queda como hoja sin salida. Motivo: Execute Workflow emite el output del sub-workflow, no el item original; conectarlo en serie hacia `Build Response` rompería la respuesta al operador. Garantía estructural: si el aviso falla, la reserva confirmada no se ve afectada (validado end-to-end en TEST). El Call lleva `onError: continueRegularOutput` y los nodos de mail `Continue On Fail`.

### D-8Cbis-03 — Sub-workflow independiente con `workflowInputs` explícitos
La alerta es un sub-workflow separado (`vita_w8cbis_alerta__TEST`/`__OPS`) invocado por Execute Workflow con contrato explícito de 5 entradas (`id_reserva`, `id_pre_reserva`, `entorno`, `source`, `operador`), no passthrough. El `entorno` es valor fijo en el Call: `"test"` en 8B TEST, `"ops"` en 8B OPS.

### D-8Cbis-04 — Fuente de datos = query read-only por `id_reserva` a `reservas`+`cabanas`
`confirmar_reserva()` solo devuelve `{ ok, id_reserva, id_pre_reserva }` (schema §10.6): no trae cabaña, fechas ni huésped. Por eso 8C-bis consulta los datos con su propia query (`SELECT` sobre `reservas` JOIN `cabanas` por `id_reserva`, sin join a `huespedes`). NO se usan `vista_calendario` ni `vista_limpieza_semana` porque filtran por ventana temporal en su WHERE y no sirven para lookup puntual. 8C-bis es solo lectura: no invoca funciones del motor ni escribe en ninguna tabla.

### D-8Cbis-05 — Privacidad por construcción del mail
El correo solo informa **cabaña, entrada y salida**, y enlaza al calendario correspondiente (operativo o de limpieza). NO incluye montos, nombre/teléfono del huésped ni notas. El detalle sensible se consulta abriendo el calendario, que ya tiene su propio control de acceso (Basic Auth, D-8C-20). Esto reemplaza lo bosquejado originalmente en el item 3.1 ("datos del huésped, teléfono, mascotas"), que se descartó por privacidad.

### D-8Cbis-06 — Ventana [hoy, hoy+7] inclusive, TZ America/Argentina/Buenos_Aires
El aviso se envía solo si `fecha_checkin ∈ [hoy, hoy+7]` calculado en zona horaria de Buenos Aires. Las fechas se normalizan a `YYYY-MM-DD` con helper `ymd()` antes de comparar (robusto a timestamps, consistente con L-8C-02).

### D-8Cbis-07 — Sin deduplicación persistente ni tabla nueva
No se crea tabla de control ni mecanismo de deduplicación. El disparo normal (una confirmación = un aviso) no duplica; una reejecución manual de una reserva ya confirmada podría reenviar el aviso. Riesgo aceptado conscientemente para esta sub-etapa.

### D-8Cbis-08 — Configuración por entorno dentro del nodo, con bloque `test` de seguridad
El nodo "Ventana + armar mail" tiene un objeto `CFG` con bloques `test` y `ops`. El bloque `test` apunta al mail de Franco (red de seguridad para pruebas manuales del workflow OPS sin molestar a destinatarios reales); el bloque `ops` a los destinatarios reales (operativo: Franco + Rodrigo; limpieza: Jennifer). El bloque elegido lo determina el `entorno` recibido del Call.

### D-8Cbis-09 — Remitente SMTP migrable sin rediseño
El remitente actual (Gmail personal de Franco) es temporal. Cuando exista el mail propio de las cabañas, se cambia la credencial/remitente SMTP en los nodos de mail sin tocar la lógica ni la topología. Queda como pendiente menor futuro.

### D-8Cbis-10 — Validación de entrada estricta en el sub-workflow
Si `id_reserva` no es entero positivo o `entorno` no es válido, el sub-workflow corta sin enviar (rama "Stop: entrada inválida"). Si la reserva no se encuentra por id, corta en "Stop: reserva no encontrada". Defensa en profundidad además de la validación que ya hace 8B.


- **D3** — Mantener solo `hora_checkin` y `hora_checkout` en tablas (sin "hora base" vs "hora real").
- **D27** — Horarios = lo elegido por cliente, validado contra margen.
- **D35** — Idempotencia post-lock vía `idempotency_key`.
- **D37** — Horarios leídos de `configuracion_general` con fallback COALESCE.
- **D38** — Triggers leen contexto vía `current_setting('app.modificado_por', TRUE)`.
- **D47** — Regla operativa de domingo: check-in 18:00 y check-out 16:00. Implementada en `crear_prereserva()` por hotfix v1.7 y propagada a `obtener_disponibilidad_rango()` en la alineación v1.7.1 (ejecutada en DEV el 2026-05-25).

## Etapa 9 — Contabilidad / Carril A

### Diagnóstico de ingresos (9A — cerrada)
- **9A fue read-only.** Diagnóstico de cómo se registran ingresos sobre el modelo
  existente (`registrar_pago`, `confirmar_reserva`), sin cambios de schema ni de
  funciones. Documento: `9A_DIAGNOSTICO_INGRESOS.md`. No reabrir el diagnóstico.

### Cobranza posterior multi-porción (9B / Fase 3b — cerrada en TEST 2026-06-07)
Decisiones de diseño 9B (promovidas desde `ARQUITECTURA_ETAPA_9B_COBRANZA_POSTERIOR.md v2`;
detalle histórico completo D-9B-01 a D-9B-19 en ese documento y en `9B_CIERRE.md`).

- **D-9B-01** — Co-responsabilidad contable de la capa (no solo UX).
- **D-9B-02** — Recargo 5%: solo porción de transferencia (bancaria/MP por igual),
  calculado interno, línea `extra` separada, marcada `recargo_5_saldo_transferencia`.
- **D-9B-04** — Alcance MVP: `saldo` multi-porción + `extra` (5% interno); resto diferido.
- **D-9B-05** — Saldo calculado desde pagos confirmados (`tipo IN ('sena','saldo')`),
  nunca desde `reservas.monto_saldo`.
- **D-9B-06** — Parciales permitidos como pagos confirmados por su monto exacto.
- **D-9B-07** — Riesgo de no-atomicidad de la anti-duplicación por capa, aceptado para
  el MVP (la atomicidad de D-9B-19 protege dentro de una carga, no entre dos cargas
  concurrentes de la misma reserva).
- **D-9B-08** — Porciones visibles: efectivo / transferencia (bancaria/MP) / otros.
  Subtipo de transferencia **opcional con default bancaria** (refinado en 3b); `mp_link`
  no expuesto.
- **D-9B-10** — Listado solo reservas con `saldo_real > 0` y estado `confirmada`/`activa`.
- **D-9B-12** — Listado HTML interno obligatorio en el MVP (mecanismo principal de
  selección); selector dinámico nativo descartado.
- **D-9B-13** — Multi-step confirmado viable (probado en 3a).
- **D-9B-14** — Modelo multi-porción (hasta 3) con recargo 5% interno sobre transferencia.
- **D-9B-16** — *(histórica)* Fallo parcial informado sin auto-revertir. **Reemplazada
  para la Fase 3b por D-9B-19.**
- **D-9B-17** — Parciales en el tiempo: varias cargas sobre la misma reserva hasta saldar.
- **D-9B-18** — Porción "otros" (USD/cripto/otro): se registra en ARS como `efectivo`
  pero marcada obligatoriamente `medio_original` en notas/source, con descripción
  obligatoria si monto > 0, para no contaminar la caja efectivo.
- **D-9B-19 🔒** — **Atomicidad transaccional en 3b.** La Fase 3b adopta
  `queryBatching: transaction` + helper SQL `public.abortar_si_falla(jsonb)` que convierte
  cualquier pago no confirmado en excepción P0001, reemplazando para esta fase el modelo
  de fallo parcial informado de D-9B-16. Si una línea falla o queda no-confirmada, se
  revierte **todo** el evento. Éxito operativo = `ok=true AND estado='confirmado' AND
  warning IS NULL` (coherente con D-8B-15). El helper es **aditivo** (no toca tablas,
  enums ni `registrar_pago()`), vive en TEST y debe crearse en OPS antes de promover 3b.

### Comportamiento conocido aceptado (3b)
- **Doble-mensaje ante rollback:** con `onError: continueErrorOutput` en el nodo Postgres
  transaccional, un rollback puede disparar **ambas** salidas (error→N8a y éxito→N6→N8b),
  mostrando N8b un instante y luego N8a. **La integridad no se ve afectada** (0 pagos tras
  rollback, verificado). Se intentó un nodo Filter intermedio (N5.5); no lo corrigió y fue
  revertido. **Decisión (Franco): aceptado como está**; no se invierte más esfuerzo en esta
  fase. N8b es el lado conservador (nunca conduce a estado peligroso).

### Alcance NO reabierto en 3b
- 3b **no** promovida a OPS (solo validada en TEST). 3b **no** tocó `registrar_pago()`,
  tablas ni enums. Quedan para Carril B / arquitectura global de contabilidad: gastos,
  caja por lugar, liquidaciones 75/25, reparto entre socios, conversión de monedas,
  cancelaciones con cargo, AFIP/ARCA/IVA, MercadoPago automático, bancos, frontend, bot,
  WhatsApp, Airbnb/Booking, y la liquidación del `extra`.

---

## Etapa 9 — Contabilidad / Carril B (9C–9H — cerrada en TEST y promovida a OPS 2026-06-14)

Implementación de la capa derivada de la contabilidad interna sobre TEST, en cinco sub-etapas aditivas (9C catálogo+zonas+seam → 9D activación operativa → 9E matriz+reparto → 9F gasto rediseñado → 9G cascada read-only). Promovido a OPS en junio 2026 (promoción coordinada única por DDL, sin copiar datos; ver la sección "Promoción Carril B a OPS" más abajo y `PROMOCION_CARRIL_B_OPS_CIERRE.md`); incorporado al canónico v1.8.0 (sección 24 + PARTE C). Detalle completo en `9C_CIERRE.md`, `9D_CIERRE.md`, `9E_CIERRE.md`, `9F_CIERRE.md`, `9G_CIERRE.md`.

### Catálogo enriquecido, zonas y seam (9C — cerrada)

D-9C-01..13 son las decisiones conceptuales del Carril B (en `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md v0.8`).

- **D-9C-14** — `valor_relativo` (NUMERIC(6,2), CHECK > 0) e `id_socio_beneficiario` como **columnas en `cabanas`** (nullable → backfill → NOT NULL); sin DEFAULT/generated/trigger.
- **D-9C-15** — FK beneficiario → `socios`, NOT NULL, ON DELETE RESTRICT, nombre con rol explícito.
- **D-9C-16** — `zonas`: catálogo plano sin `activa` (PK + unique nombre + no vacío).
- **D-9C-17** — `cabana_zona`: M2M con PK compuesta; FKs CASCADE cabaña / RESTRICT zona; índice inverso.
- **D-9C-18** — Seam `resolver_beneficiario(id_cabana, fecha)` STABLE SECURITY INVOKER, fecha **incluida pero ignorada** en el MVP; REVOKE de los 4 roles (ownership sigue ejecutando).
- **D-9C-19** — Gate anti-OPS por marcador `configuracion_general('ambiente','test')`; `'ops'` se siembra recién en la promoción coordinada.
- **D-9C-20** — Seed sin ambigüedad: unicidad de Franco/Rodrigo/Remo re-asegurada en transacción; resolución por nombre, nunca ids literales.
- **D-9C-21** — Completar el placeholder `Socio 3` → `Remo` como prerequisito de Carril B (UPDATE idempotente guardado).

### Activación operativa por rango (9D — cerrada)

- **D-9D-01** — Tabla independiente `activaciones_operativas` (eje propio; no deriva de `bloqueos` ni de `cabanas.activa`).
- **D-9D-02** — Rango `fecha_desde`/`fecha_hasta DATE` + CHECK; sin columna `daterange` almacenada.
- **D-9D-03** — `fecha_hasta NULL` = activación abierta; desactivar = dejar hueco; reactivar = nuevo rango.
- **D-9D-04** — EXCLUDE gist no-solapamiento por cabaña (adyacencia `[)` permitida); primer EXCLUDE de Carril B.
- **D-9D-05** — FK `id_cabana` ON DELETE RESTRICT (paridad con `bloqueos`/`reservas`).
- **D-9D-06** — La política mensual ("cubre el mes completo") se aplica en 9E, no en 9D.
- **D-9D-07** — Auditoría `creado_por`+`comentario`+`created_at`; **sin `source_event`** (carga SQL controlada).
- **D-9D-08** — Carga por SQL controlado, sin formulario en el MVP.
- **D-9D-09** — Estructura primero; carga inicial en bloque separado con decisión explícita.
- **D-9D-10** — **Pool inicial real:** Bamboo, Madre Selva, Arrebol, Tokio activas desde `2026-07-01`; **Guatemala desde `2026-11-01`** (ambas con `fecha_hasta NULL`).

### Matriz dinámica y reparto (9E — cerrada)

- **D-9E-01** — Solo funciones read-only; la matriz se deriva, jamás se persiste.
- **D-9E-02** — `matriz_participacion(p_periodo)` normaliza internamente al mes (cualquier día sirve).
- **D-9E-03** — Regla "cubre el mes completo" vía `daterange @> mes`; titularidad vía el seam; `detalle_participacion` a nivel cabaña para auditoría.
- **D-9E-04** — `participacion` como fracción 0..1 exponiendo `valor_socio` y `valor_pool` (transparencia).
- **D-9E-05** — `repartir_por_matriz` vive en 9E; reparte un monto dado, no lee `pagos` ni hace cascada.
- **D-9E-06** — Pool vacío ⇒ matriz vacía (0 filas) y reparto vacío; sin división por cero.
- **D-9E-07** — REVOKE de los 4 roles; SECURITY INVOKER (paridad con el seam).
- **D-9E-08** — **Centavo residual:** al de mayor participación; en empate del máximo, Rodrigo si está, sino menor `id_socio` (`ORDER BY participacion DESC, (nombre='Rodrigo') DESC, id_socio ASC LIMIT 1`). Rodrigo no recibe el residual fuera del empate.

### Gasto interno rediseñado (9F — cerrada 2026-06-10)

- **D-9F-01** — Tabla nueva `gastos_internos`; la `gastos` legacy queda **congelada/deprecada e intacta**; su destino (DROP/rename) se decide en la promoción coordinada con el bump único del canónico.
- **D-9F-02** — Nombre `gastos_internos` (ancla con la contabilidad operativa interna).
- **D-9F-03** — `clase` TEXT + CHECK ('A','C','D','E'), no enum nativo.
- **D-9F-04** — **Alcance condicional por clase** vía CHECK: D ⇒ zona sin cabaña; E ⇒ cabaña sin zona; A/C ⇒ ninguno. El alcance no se elige: lo deriva la clase.
- **D-9F-05** — Pagador `socio|caja` + `id_socio_pagador` FK RESTRICT + CHECK de consistencia (materializa D-9C-03).
- **D-9F-06** — **La incidencia NO se persiste**: se deriva por clase+alcance+período vía seam (9C), activaciones (9D) y matriz (9E).
- **D-9F-07** — `etiqueta` TEXT libre no vacía; sin catálogo en 9F.
- **D-9F-08** — Override derivado (`clase <> clase_sugerida`); un CHECK exige comentario no vacío en override y en carga sin sugerencia.
- **D-9F-09** — Horas de socio por etiqueta literal `'horas de trabajo'` + CHECK pagador socio (`lower(btrim())`); no protege typos (fila sin guarda, nunca rechazo falso).
- **D-9F-10** — `fecha` + `periodo` explícito normalizado a día 1 ("cuándo se pagó" ≠ "a qué liquidación entra").
- **D-9F-11** — `moneda` TEXT NOT NULL DEFAULT 'ARS' con CHECK ARS-only.
- **D-9F-12** — Sin función de expansión de incidencia en 9F (es 9G).
- **D-9F-13** — 18 constraints nombradas (14 CHECK + 3 FK + PK), todas ejercitadas en el Bloque C.
- **D-9F-14** — `creado_por` NOT NULL no vacío + `created_at`; sin `source_event` (más estricto que 9D: acá hay plata).
- **D-9F-15** — Sin soft-delete; corrección por SQL controlado.
- **D-9F-16** — `medio_pago` TEXT nullable, sin FK a `cuentas_cobro`.
- **D-9F-17** — Fixture técnico (ids 30–34, `creado_por='seed_9f_validacion'`) conservado y borrable por marcador; **no viaja a OPS** (conservación extendida hasta 9H por D-9G-13).
- **D-9F-18** — Un solo índice `(periodo, clase)` en el MVP.
- **D-9F-19** — Higiene TEXT NULL-safe en todos los CHECK de texto.
- **D-9F-20** — Frontera de las consultas semánticas: destinatarios por nombre, jamás saldos/montos finales/porcentajes/cascada (eso fue 9G).
- **D-9F-21** — No resetear secuencias por estética (gaps de smokes = normal; coherente con D-7D-01).

### Cascada de liquidación read-only (9G — cerrada 2026-06-11)

- **D-9G-01** — `p_pct_operativo` parámetro explícito (fracción 0..1, sin default, sin congelar). Inválido/NULL ⇒ **fila guard explícita** (`paso=0` en cascada; `socio` marcado en saldos); jamás 0 filas mudas.
- **D-9G-02** — Paso 1 = `sena`+`saldo` confirmados; paso 6 = `extra` confirmado; monto = `monto_recibido`. `reembolso`/`ajuste` fuera del MVP.
- **D-9G-03** — **Criterio de caja percibida:** período = mes calendario de `created_at`; devengado/estadía **DESCARTADO**. Cobros pre-arranque caen en pool vacío y no se reparten salvo política manual de socios; cambio futuro re-bucketiza toda la historia. Precisión: bucket en TZ de sesión (UTC); refinamiento argentino diferible y re-derivable.
- **D-9G-04** — Paso 4 = `−ROUND(GREATEST(base,0)×pct,2)` como número único agregado. El residual de la matriz global existe solo en el paso 9 (D-9E-08); los gastos D tienen su residual interno de zona (D-9G-05).
- **D-9G-05** — Expansión D: activas de la zona en el mes → `valor_relativo` → ROUND por cabaña + residual interno a mayor `valor_relativo` (empate: menor `id_cabana`) → seam → socio.
- **D-9G-06** — **Incidencia no derivable NO se resta y se reporta** (`pool_vacio` para A/C; `zona_sin_activas` para D); E siempre derivable (seam, independiente de la activación).
- **D-9G-07** — `GREATEST(base,0)` solo en el paso 4; debajo, signo sin clamps; negativos visibles.
- **D-9G-08** — Universo de socios del período = matriz ∪ incidencias D/E (solo-incidencia entra con bruto 0).
- **D-9G-09** — `desembolsado_periodo` informativo; desembolso ≠ incidencia; la compensación pagador↔incidido es 9H.
- **D-9G-10** — Set de 6 funciones `sql STABLE SECURITY INVOKER`, sin vistas/tablas/persistencia, REVOKE de los 4 roles.
- **D-9G-11** — Lado fiscal del reporte 5-vs-fiscal: etiqueta literal `'monotributo'` (lower/btrim, patrón D-9F-09).
- **D-9G-12** — Seed por INSERT directo (excepción de laboratorio, sin `registrar_pago()`): 5 pagos `seed_9g_%`, gates G1–G9 pineando la foto del Bloque A + RUN 0 diagnóstico + WHERE atómico; borrable por marcador escapado; sin reset de secuencia.
- **D-9G-13** — **Fixtures 9F+9G = banco conjunto de laboratorio conservado hasta 9H**: fixture técnico, no datos reales; distorsionan saldos derivados de las reservas 5/6/7/10 mientras existan (aceptado y documentado); **no viajan a OPS**; la promoción recrea estructura por DDL sin copiar datos; DELETEs documentados sin ejecutar.
- **D-9G-14** — `incidencia_gasto()` clase A = una fila estructural `pool_pre_operativo` **sin expansión por porcentajes** (la incidencia marginal de A es contextual al período por el GREATEST del paso 4); firma sin pct. Asimetría deliberada con C, que sí expande exacto por socio (§4.2, vía `repartir_por_matriz`).

### Cuenta corriente interna — capa con estado (9H — cerrada 2026-06-12)

Última sub-etapa del Carril B: la capa **con estado** que congela la salida derivada de 9C–9G y agrega lo no derivable (mayor de movimientos, revaluación). Cierra el Carril B en TEST. No promovida a OPS (promoción coordinada única). Numeración completa D-9H-01 a D-9H-38, sin saltos.

- **D-9H-01** — Snapshot = fila completa de `saldo_socios_periodo` por socio + cascada agregada de 8 pasos, congeladas en tablas propias (`liquidacion_socio`, `liquidacion_cascada`).
- **D-9H-02** — La cabecera del snapshot (`liquidaciones_periodo`) guarda los metadatos de la corrida: `pct_operativo` y `creado_por` (más `created_at`).
- **D-9H-03** — El congelado se dispara por **función SQL controlada** (`registrar_snapshot_periodo`), nunca por automatismo ni trigger; el período a congelar es decisión humana.
- **D-9H-04** — Append-only **estricto**: sin columna `estado`, sin UPDATE en todo el diseño. La vigencia de una foto se **deriva** por `NOT EXISTS` supersesor, no se marca.
- **D-9H-05** — La compensación pagador↔incidido (la deuda Rodrigo↔Franco del termotanque, Remo↔Rodrigo de las horas) es **derivada** leyendo `desembolsado_periodo`; **no** hay tabla de deuda.
- **D-9H-06** — El arranque de junio (base de ganancia sin destinatarios, pool vacío) se maneja —si los socios lo deciden— con un movimiento manual de tipo `ajuste_arranque`, no con lógica especial en la cascada.
- **D-9H-07** — Retiros: saldos negativos **por liquidación/incidencia** permitidos; un `retiro` que dejaría el saldo vivo < 0 va **bloqueado por la función**; el negativo solo se logra con un movimiento `adelanto` o `ajuste_manual`, con **comentario obligatorio**.
- **D-9H-08** — La revaluación ARS→USD es un **evento aparte** (tabla `revaluaciones`); valúa o convierte, **no re-contabiliza** el saldo en ARS.
- **D-9H-09** — La capa se implementa con **tablas + funciones**, sin vistas.
- **D-9H-10** — El mayor de movimientos es **ARS-only**; el USD aparece únicamente en `revaluaciones`.
- **D-9H-11** — Paso 4 (retribución operativa), **opción (c)**: la foto **congela y muestra** el paso 4 en `liquidacion_cascada`; el destino se registra después con un movimiento `retribucion_operativo`. **Sin caja operativa, sin asignación automática a ningún socio.**
- **D-9H-12** — `saldo_vivo = saldo_final + desembolsado_periodo + Σ movimientos`. En `liquidacion_socio` van **columnas separadas**; la suma vive **solo** en la función `saldo_corriente_socio` (sin columna materializada de crédito).
- **D-9H-13** — El paso 4 / retribución operativa **no tiene beneficiario predefinido** ni se asigna automáticamente por rol operativo. La foto de liquidación lo congela y lo muestra como magnitud calculada; el destino real se decide entre socios y se registra después mediante un movimiento manual de tipo `retribucion_operativo`. El sistema controla la no-duplicación con `reporte_retribucion_operativo_periodo`, pero **no decide el beneficiario**. (No agrega regla nueva: documenta explícitamente lo ya resuelto por D-9H-11 y D-9H-14.)
- **D-9H-14** — Reporte anti-duplicación: `reporte_retribucion_operativo_periodo(periodo)` compara **calculado** (paso 4 de la foto vigente) vs **asignado** (Σ de movimientos `retribucion_operativo` del período, neto de reversas).
- **D-9H-15** — Inmutabilidad **estructural**: función `trg_9h_inmutable()` + triggers `BEFORE UPDATE OR DELETE` (row) y `BEFORE TRUNCATE` (statement) en las 5 tablas. Append-only deja de ser disciplina y pasa a ser estructural; el único bypass es DDL visible (DROP del trigger).
- **D-9H-16** — Cierre de seguridad: `REVOKE ALL` de PUBLIC + `anon`/`authenticated`/`service_role` en las 5 tablas **y** en las 3 secuencias BIGSERIAL.
- **D-9H-17** — Reversa **única por movimiento**: índice parcial único `uq_mov_reversa_unica` + validación funcional de **monto opuesto** en la función.
- **D-9H-18** — `retribucion_operativo` es **positivo** (acredita); su corrección solo por reversa.
- **D-9H-19** — `revaluaciones.id_movimiento_origen` (FK nullable): NULL = valuación de saldo; no-NULL = conversión ligada a un movimiento concreto (el retiro/adelanto).
- **D-9H-20** — Limpieza de la capa por **teardown DROP** en orden explícito (`revaluaciones` → `movimientos_socio` → `liquidacion_socio` → `liquidacion_cascada` → `liquidaciones_periodo` → función), **sin CASCADE**. Como las tablas son inmutables, **no hay DELETE**.
- **D-9H-21** — `REVOKE ALL ON FUNCTION trg_9h_inmutable()` de PUBLIC + 3 roles (higiene + defensa en profundidad; no afecta el enforcement del trigger).
- **D-9H-22** — Pertenencia de socio **estructural**: `UNIQUE (id_movimiento, id_socio)` como target de FK compuestas `(id_movimiento_revertido, id_socio)` y `(id_movimiento_origen, id_socio)` (MATCH SIMPLE: si el origen es NULL no se chequea). Una reversa o conversión no se puede ligar al movimiento de otro socio; se eliminan las FK de una sola columna.
- **D-9H-23** — Verificación de seguridad **exhaustiva** en B.2: 7 privilegios de tabla (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER) y 3 de secuencia (USAGE/SELECT/UPDATE) para PUBLIC + 3 roles, más EXECUTE de la función de trigger.
- **D-9H-24** — Re-snapshot **explícito**: si el período ya tiene foto vigente, `registrar_snapshot_periodo` **falla** salvo que se pase `p_supersede_id` = cola actual + comentario obligatorio. Apunta la sucesora a la cola, no a un nodo medio.
- **D-9H-25** — Retiro a saldo **exactamente 0** permitido; bloquea solo si el resultado es < 0.
- **D-9H-26** — Doble defensa del pct operativo: validación temprana del rango + filtro en los pasos 1-8 (nunca congela un paso guard).
- **D-9H-27** — Permitir **congelar junio** (cascada de 8 pasos, 0 filas de socio: anomalía de arranque real, pool vacío).
- **D-9H-28** — La reversa recibe solo `id_movimiento_revertido` + fecha + comentario + `creado_por`; la función **calcula el monto opuesto** internamente.
- **D-9H-29** — Conversión parcial ligada con **tope acumulado**: Σ `monto_ars` convertido ≤ `|monto|` del movimiento origen.
- **D-9H-30** — Valuación `total` **no atada al saldo vivo** en el MVP (informativa, no certificada).
- **D-9H-31** — Funciones de escritura específicas (`registrar_retiro` / `registrar_reversa` / `registrar_revaluacion`) + una genérica `registrar_movimiento_manual` para los 4 tipos manuales.
- **D-9H-32** — **Advisory locks** transaccionales: `pg_advisory_xact_lock(919001, hashtext(periodo))` en el snapshot; `pg_advisory_xact_lock(919002, id_socio)` en retiro / movimiento manual / reversa / revaluación. Necesarios porque los guards y topes son **derivados** (se leen y se decide en la misma transacción).
- **D-9H-33** — `registrar_revaluacion` calcula `monto_usd = ROUND(monto_ars / tipo_cambio, 2)` internamente (no se pasa por fuera).
- **D-9H-34** — La conversión ligada se permite **solo** sobre movimientos `retiro` o `adelanto` (débitos ARS efectivamente entregados al socio); excluye `retribucion_operativo` / `ajuste_arranque` / `ajuste_manual` / `reversa`.
- **D-9H-35** — `registrar_snapshot_periodo` exige **exactamente 8 filas** insertadas en `liquidacion_cascada` (`GET DIAGNOSTICS ROW_COUNT`); si no, `RAISE`.
- **D-9H-36** — Endurecimiento de escala: ARS rechaza precisión sub-centavo (`valor <> ROUND(valor, 2)`); `tipo_cambio := ROUND(., 4)` antes de calcular USD (corrige un bug latente del CHECK de coherencia con TC > 4 decimales); el pct rechaza > 4 decimales.
- **D-9H-37** — `registrar_snapshot_periodo` valida las filas de `liquidacion_socio`: **0** (junio) o **exactamente `COUNT(socios)`**. Asume que todo período con matriz incluye a todos los socios (cierto hoy: cada socio tiene ≥1 cabaña activa desde julio). Salvedad: si una cabaña grande se desactivara, refinar a `WHERE activo`.
- **D-9H-38** — Smokes C.3 **efímeros**: `BEGIN → seed mínimo → smokes → veredicto → ROLLBACK`; no persisten filas. Las secuencias BIGSERIAL pueden avanzar (nextval no transaccional), sin significado contable y sin resetearse.

## Promoción Carril B a OPS — cerrada 2026-06-14

El Carril B completo (9C→9H + helper 9B) fue **promovido a OPS** en una operación coordinada bloque por bloque (junio 2026), **por DDL y sin copiar datos de TEST**, con el canónico bumpeado a **v1.8.0**. Paridad estructural TEST↔OPS certificada por huella (`TOTAL_CARRIL`, 31 objetos, idéntica), cero exposición a la Data API y smokes read-only 18/18 en OPS. El detalle bloque por bloque (A-bis→M) y la evidencia dura viven en **`PROMOCION_CARRIL_B_OPS_CIERRE.md`**; acá va la versión sintética de las decisiones.

Decisiones de **promoción/ejecución** (no rediseño; las conceptuales 9C→9H conservan su numeración `D-9x`):

- **D-PROMO-01** — Promoción por DDL bloque por bloque, **sin copiar datos de TEST**; los fixtures de laboratorio no viajan (materializa D-9F-17 / D-9G-13 / D-9H-20).
- **D-PROMO-02** — Snapshot baseline doble (A + A-bis) read-only con gate por seed antes de habilitar DDL; baseline de EXECUTE contemplando `proacl NULL ⇒ PUBLIC ejecuta` y exclusión de extensiones (`pg_depend deptype='e'`).
- **D-PROMO-03** — Marcador `ambiente='ops'` sembrado recién en la promoción + gate `DO+RAISE` de ambiente/seed (cabañas 1-5) en cada bloque (reconcilia D-9C-19).
- **D-PROMO-04** — `Socio 3`→`Remo` + backfill de beneficiarios **por nombre** en el seed base del canónico (Bloque 21): **materializa D-9C-20 / D-9C-21**, no las duplica.
- **D-PROMO-05** — Las 4 funciones 9C/9E quedaron **alineadas en OPS contra la versión de TEST** vía DROP+CREATE (diferencia 100% cosmética), con parche K1B + companion de revert (sin `CASCADE`).
- **D-PROMO-06** — Limpieza de ACL residual `Dxtm` en las 4 tablas tempranas de TEST (`REVOKE ALL`); OPS ya estaba limpio (más hardened).
- **D-PROMO-07** — GRANTs/RLS del Carril B = **cerrados sin grants y sin RLS** (REVOKE total sobre 9 tablas + 6 secuencias + 21 funciones; acceso solo por owner vía funciones). Resuelve el "GRANTs/RLS a decidir" de D-9C-19.
- **D-PROMO-08** — Cierre estructural por **huella `TOTAL_CARRIL` (31 objetos) idéntica TEST↔OPS** (doble corrida del mismo script simétrico, sin nada embebido).
- **D-PROMO-09** — Smokes K2 **read-only puros** (sin escritura 9H ni bajo ROLLBACK): se preservan tablas 9H vacías + secuencias en 1 para que la primera liquidación real arranque en 1.
- **D-PROMO-10** — Gate de orden de promoción en el helper 9B (`abortar_si_falla` último; firma exacta de `registrar_pago` + 9H completo + 9G intacto + helper ausente; `search_path` + `REVOKE EXECUTE`).
- **D-PROMO-11** — Port del workflow 3b a OPS (`vita_w09_cobranza_posterior`, 14 nodos) + listado de saldos read-only, revisando marcadores de entorno embebidos (L-8D-03).
- **D-PROMO-12** — Bump único v1.8.0 (sección 24 + PARTE C, cuerpos post-K1), **excluyendo la maquinaria de promoción** (gates/asserts/snapshots/reversiones quedan en los `PROMO_BLOQUE_*`); PARTE C verificada en bootstrap fresco.
- **D-PROMO-13** — **DEV fuera del alcance**; reconstrucción posterior desde v1.8.0.

**Reconciliación (no son D-PROMO nuevas):** el desempate de centavo residual sigue siendo **D-9E-08** (transportado y reverificado); beneficiarios por nombre / `Socio 3`→`Remo` se referencian contra **D-9C-20 / D-9C-21**; pool (D-9D-10), matriz (9E), clases de gasto A/C/D/E (9F) y la capa con estado de 9H **no se renombran** como D-PROMO. La `gastos` legacy **se conserva** (D-9F-01); el Carril B opera sobre `gastos_internos`; **no se migran ni copian datos** de gastos legacy.

## Reglas de negocio del Carril B — cerradas 2026-06-14

Definiciones de negocio que los socios dejaron servidas en 9G/9H y que se **cierran** acá. Son reglas para operar; **revisables por decisión de socios más adelante**, pero no son pendientes para operar ahora.

- **D-NEG-01 — % operativo del Carril B = 25%.** Se fija en **25%** (0,25), calculado sobre los **ingresos cobrados del período** (criterio de caja percibida, D-9G-03) **después de restar los gastos operativos/Carril B**. Las funciones de cascada ya lo reciben por parámetro (D-9G-01); este es su valor de negocio vigente (deja de ser "valor de trabajo sin carácter normativo").
- **D-NEG-02 — Inicio oficial contable del Carril B = 2026-07-01.** El negocio contable operativo del Carril B arranca el **2026-07-01**. Todo período anterior a julio 2026 queda **fuera de alcance contable operativo**: no se liquida, no se arrastra, no se recontabiliza (etapa previa al inicio oficial). Esto **cierra** el pendiente de "política de arranque para períodos raros": el arranque de junio (pool vacío, base de ganancia sin destinatarios) queda fuera de alcance y **no requiere** `ajuste_arranque` ni congelado de junio (las capacidades de D-9H-06 / D-9H-27 permanecen como código, pero **no se ejercen para pre-julio**).

## Carril C — Portal Operativo Interno / Backend-API (diseño, cerrada 2026-06-15)

Decisiones de la etapa de **diseño** del Backend/API del Portal Operativo Interno (Carril C). Carril **independiente del Carril B**: no reabre 9C→9H, no toca el canónico ni OPS. Etapa de **diseño puro — nada construido** (sin workflows, sin Edge Function, sin código, sin `portal_usuarios`). Cierre: `CARRIL_C_BACKEND_API_DISENO_CIERRE.md`. Algunas decisiones refinan a otras (se indica); se conservan ambas (principio en Fase 0/0.5 + realización concreta). Convención del archivo: no se marca 🔒 por línea; toda la sección es de no-reabrir.

- **D-C-01** — Fuente de roles/permisos del portal: Sección 8 + Apéndice A del prompt de arranque + README + prompt actual. Sin brief específico por ahora; reconciliable si aparece, sin bloquear.
- **D-C-02** — Jenny: usa el workflow de limpieza existente; ve cabaña/fechas/personas + **nombre y teléfono** del huésped (puede hacer check-in a futuro); sin datos contables/financieros; sin acceso al resto del portal.
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
- **D-C-13** — Frontera de confianza = **Supabase Edge Function** (BFF/gateway). El builder (Lovable) puede ser frontend visual, no frontera de confianza. Flujo: frontend → Supabase Auth → Edge Function (`portal-api`) → webhook n8n firmado → Postgres vía credencial n8n. *(Concreta D-C-07.)*
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
- **D-C-24** — A11 `source_event`: **excepción consciente a nivel fila** — `gastos_internos` no tiene columna `source_event` (D-9F-14); traza de fila = `creado_por`+`created_at`; el `source_event` vive en el log del workflow n8n; **no** se escribe en `comentario`.
- **D-C-25** — Política de reintentos del gateway: **no auto-reintenta escrituras**; timeout / estado incierto / error de verificación → código conservador + el frontend indica verificar antes de reintentar; nunca recarga ni reenvía automático. A07 (idempotencia fuerte heredada): reintento manual/controlado, nunca auto-retry ciego.
- **D-C-26** — Priorización MVP por slices verticales: **Slice 0** (espina de seguridad: Supabase Auth + `portal_usuarios` + Edge Function `portal-api` + JWT→rol→allowlist + HMAC→n8n + validación de ambiente + `sesion.contexto`) → **Slice 1** (lecturas reuse A03/A04/A05/A06/A12) → **Slice 2** (escrituras reuse A07/A08/A10) → **Slice 3a** (lecturas nuevas: A24 histórico; A25 ingresos se suma por D-C-27) → **Slice 3b** (gastos A11 + A13 verificación). Menor slice operable = **Slice 0 + A03**. Fuera del MVP: A09, A14–A18, A19–A23. A11 último.
- **D-C-27** — A25 `ingresos.cobrados_periodo`: read-only, `vicky`+`socio`, MVP, fuente `reservas`+`pagos`, **Nuevo** (envuelve consulta/reporte simple, sin lógica societaria). Separación: **A25 ingresos** / **A13 gastos** / **A14–A18 societario**. No reparto, no matriz, no saldo por socio, no cascada (coherente con D-9F-20). Se prioriza junto a A24 en Slice 3a.
- **D-C-28** — Pruebas TEST: `periodo='2099-01-01'` como **período sintético** para los gastos A11 de prueba (garantía extra anti-contaminación), siempre con sentinel + teardown verificado.
- **D-C-29** — **HMAC:** HMAC-**SHA-256** sobre los **bytes literales** del body (`{action,payload,rol,ambiente_esperado,ts,nonce}` serializado una sola vez); header `X-Vita-Signature: sha256=<hex>`; `ts` epoch ms + `nonce` uuid **dentro** del body firmado; tolerancia de clock-skew **±300 s**; **sin store persistente de nonce en Slice 0** (la ventana de tiempo alcanza; la tabla de unicidad se suma en la primera escritura no-idempotente sin guard sobre n8n —realísticamente A11— o en hardening). **Salvedad de raw body cerrada empíricamente** (probe Fase C): n8n recomputa el HMAC sobre el raw body y valida byte a byte ⇒ **no** se necesita el fallback de JSON canónico.
- **D-C-30** — **Validación del JWT** en `portal-api` vía **`supabase.auth.getUser(jwt)`** (no verificación local con JWT secret), con **`verify_jwt = false`** en `config.toml` para que la validación ocurra en el handler y siempre devuelva el envelope uniforme: simplicidad, revocación correcta, un secreto menos. Confirmado empíricamente que funciona con el cliente creado con la **secret key** server-side (no hace falta un cliente aparte con publishable key).
- **D-C-31** — **Allowlist rol×action = constante versionada en código** en la Edge Function (`CATALOG`), no tabla: política-como-código auditable en git, sin hop de red, sin drift entre lo impuesto y lo desplegado. Una acción aparece en el catálogo **solo cuando está wired** (Slice 0: únicamente `sesion.contexto`). n8n revalida su propia allowlist por-workflow (segunda defensa).
- **D-C-32** — **Usuarios del portal creados por Dashboard** en Supabase Auth (TEST, con **Auto Confirm ON**; emails `@vitadelta.test`) + **seed por email** (`INSERT…SELECT` resolviendo `user_id` contra `auth.users`): el SQL del repo no contiene UUIDs ni passwords. Emails reales diferidos a OPS.
- **D-C-33** — **Secretos por entorno:** `VITA_HMAC_SECRET` en **Supabase secrets** (TEST), **mismo nombre** de variable en OPS con **valor distinto**; la secret key se resuelve **defensivamente** (`SUPABASE_SECRET_KEYS[default]` → legacy `SUPABASE_SERVICE_ROLE_KEY`) con **preflight ruidoso** que aborta si falta `SUPABASE_URL` / secret key / `VITA_HMAC_SECRET`. Nada de secretos al repo; workflows n8n exportados como `__TEMPLATE` **sanitizado**.
- **D-C-34** — **`portal_usuarios` es interna:** vive en `public` pero con permisos **revocados** a `anon`/`authenticated` (roles del navegador) y **solo SELECT** a `service_role` (lector server-side de `portal-api`). El Data API no la ve; rol y acciones se exponen **únicamente** vía `sesion.contexto`. **Assert duro** en el DDL (rollback si el navegador pudiera leerla). Misma estrategia que las 9 tablas del Carril B.
- **D-C-35** — **Contrato HTTP de `portal-api`:** **HTTP 200 + envelope** (`{ok:...}`) para **todo resultado manejado** (auth/permiso/negocio); **5xx solo para fallos inesperados** (preflight de config incompleto, excepción no controlada). El frontend lee siempre `body.ok`; `error.code` lleva la semántica. (Si se quisieran códigos HTTP por clase para observabilidad de infra, es un cambio acotado en el helper.)

## Carril C — Slice 1 (lecturas reuse) — cerrada 2026-06-18

Decisiones de la **construcción de Slice 1**: las cinco primeras lecturas operativas del Portal Operativo Interno (A03 `calendario.limpieza`, A04 `calendario.operativo`, A05 `reserva.detalle`, A06 `prereservas.activas`, A12 `cobranza.saldos`), sobre **TEST**, vía wrappers n8n firmados que revalidan HMAC+ts+rol+action+ambiente y reusan lógica/vistas/queries existentes. No reabre el Carril B ni el canónico; **OPS intacto**. Cierre: `C_SLICE1_CIERRE.md`. Convención: decisiones posteriores pueden **precisar o superar** partes operativas de anteriores; se conservan ambas y se indica qué parte queda vigente (en este slice, **D-C-42/43/44 refinan la porción de salida/fuente de A05 de D-C-40**; la regla de `saldo_real` de D-C-40 se mantiene vigente).

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

## Carril C — Slice 2 (escrituras reuse) — cerrada 2026-06-20

Decisiones de la **construcción de Slice 2**: las tres primeras escrituras operativas del Portal Operativo Interno (A07 `reserva.crear_manual`, A08 `bloqueo.crear_manual`, A10 `cobranza.registrar_saldo`), sobre **TEST**, vía wrappers n8n firmados que revalidan HMAC+ts+rol+action+ambiente, **inyectan el actor server-side** desde el JWT (nunca del payload) y reusan funciones del motor existentes (`crear_prereserva`/`registrar_pago`/`confirmar_reserva` de 8B, `crear_bloqueo` de 8D, `registrar_pago`/`abortar_si_falla` de 9B), **sin** invocar los webhooks viejos (8B/8D/W09). No reabre el Carril B ni el canónico; **OPS intacto**. **No promovido a OPS.** `vita_w09_cobranza_posterior` queda **INACTIVO** hasta decisión posterior; el wrapper A10 directo queda **ACTIVO** (el gateway lo necesita para despachar). A07/A08 no introdujeron decisiones nuevas (reusaron el molde de seguridad de Slice 0/1 y el patrón de wrapper). Cierres: `C_SLICE2_CIERRE.md` + `C_SLICE2_A10_DIRECTO_CIERRE.md`.

- **D-C-50** — **Estructura transaccional de una escritura con lock (A10).** Una escritura del portal que debe prevenir condiciones de carrera se modela como **UN** nodo Postgres con **DOS sentencias** bajo `options.queryBatching:"transaction"`: **St1** = `pg_advisory_xact_lock(hashtext('a10_cobranza_saldo:' || (($1::jsonb)->>'id_reserva')))` (lock por `id_reserva`, namespaced, se libera en COMMIT/ROLLBACK); **St2** = CTE de idempotencia (por `source_event`) → recálculo de saldo **dentro de la txn** → `abortar_si_falla(registrar_pago($1::jsonb))` (D-9B-19). Las dos sentencias van **separadas a propósito**: así el snapshot READ COMMITTED de St2 se toma **después** de adquirir el lock, y cada request concurrente ve los commits previos (sin esto, varios leerían el mismo saldo y sobrepagarían). El lock cubre **A10-vs-A10** únicamente; **W09 debe estar inactivo** durante los smokes. Confirmado empíricamente que n8n bindea `$1` a AMBAS sentencias bajo `queryBatching:transaction` (no hizo falta el fallback `$2`). Validado por C2 (saldo 90000 → 0 exacto, 3 ok + 1 conflicto).
- **D-C-51** — **Modelo de error de dos capas para escrituras (A10).** El SQL devuelve **etiquetas internas** (`reserva_no_existe`, `estado_no_cobrable`, `saldo_ya_cancelado`, `excede_saldo`, `idempotency_mismatch`); el nodo `render` las mapea a la **allowlist externa**: `reserva_no_existe → no_encontrado`; el resto → `conflicto`; excepción P0001 de `abortar_si_falla` → `error_interno` (vía `render_error_pg`); éxito → `{ok:true,data}`. **Cero códigos externos nuevos.** `resultado.ok===true` es **autoritativo** (`abortar_si_falla` garantiza `confirmado` o tira P0001; en idempotencia el pago ya existe); `PG_verif_post` solo **enriquece** `saldo_real_actual` post-COMMIT y **no** baja a `estado_incierto` si degrada (L-C-15). La **idempotencia con match exacto** exige coincidencia de `id_reserva` + `tipo='saldo'` + `medio_pago` + `monto_recibido` + `validado_por`; cualquier divergencia con la misma `idempotency_key` → `idempotency_mismatch → conflicto`. **Verificado end-to-end por el gateway (2026-06-20): SOBREPAGO → `conflicto`, nunca `estado_incierto`** (el wrapper devuelve HTTP 200 + envelope `conflicto`; `dispatchN8n`/`noConfiable` no lo enmascara).

## Carril C — Slice 3a (lecturas nuevas) — cerrada 2026-06-20

Decisiones de la **construcción de Slice 3a**: las dos primeras lecturas **nuevas** del Portal Operativo Interno (A24 `historico.reservas`, A25 `ingresos.cobrados_periodo`), sobre **TEST**, escritas como **`SELECT` inline** (sin funciones nuevas, sin DDL), vía wrappers n8n firmados que revalidan HMAC+ts+rol+action+ambiente. **No** llevan `injectActor` ni `isWrite` (lecturas). Reusan la **CTE de saldo de A12** (D-C-49) para `saldo_real` (A24) y la atribución de pagos (A25). No reabren el Carril B ni el canónico; **OPS intacto**. **No promovido a OPS.** CATALOG **9 → 11** (1 Edge + 7 lecturas + 3 escrituras). Cierres: `C_SLICE3A_CIERRE.md` + mini-cierres por bloque (`C_SLICE3A_A24_DIRECTO_CIERRE.md` / `C_SLICE3A_A24_GW_CIERRE.md` / `C_SLICE3A_A25_DIRECTO_CIERRE.md`).

- **D-C-52** — **A24 `historico.reservas` = buscador operativo de reservas.** Floor inferior **duro** `2026-07-01` (D-C-11/20): el gateway recorta `fecha_desde < floor → floor` (no rechaza) y el SQL lo impone además con `GREATEST(DATE '2026-07-01', …)`. `fecha_hasta` default **`null` = sin cota superior** → incluye reservas futuras. Documentado explícitamente: **no** se usa para liquidación ni Carril B, **no** reemplaza el calendario operativo A04. `id_cabana`/`estado` ausentes o `null` = todas/todos, **sin sentinela `0` externa** (el SQL maneja `NULL` directo). Devuelve **`id_cabana` además de `cabana`**. `saldo_real` recomputado por la CTE de A12 (D-C-49) y **puede ser negativo** (sobrecobro): se reporta tal cual. `total` = universo filtrado vía `COUNT(*) OVER()` (caveat: `offset` más allá del universo devuelve `total=0`).
- **D-C-53** — **A25 `ingresos.cobrados_periodo` = caja percibida.** `total_cobrado` = **solo `sena`+`saldo` confirmados** (D-9G-03). `otros_movimientos` (`extra`/`ajuste`/`reembolso`, mismo período+floor, confirmados) es **informativo**: no suma, no resta, no neto, no resultado, no cascada, no matriz, no reabre Carril B (D-C-27). **Suma sobre `pagos`** (no sobre reservas) → **incluye el residuo** (pago cuya pre-reserva nunca convirtió), que aparece con `id_reserva`/`cabana` `null` (LEFT JOIN). Bucket por **mes de `created_at`** (criterio Carril B vigente, sin conversión de zona — sin `AT TIME ZONE`). **`filas` paginada** (`limit`/`offset`): los agregados (`total_cobrado`, `por_tipo`, `por_medio`, `por_mes`) son del **universo completo**; `filas` trae solo la página; el cuadre `Σ filas = total_cobrado` aplica **solo con página completa**, mientras `Σ por_medio = Σ por_tipo = total_cobrado` vale **siempre**. Sumas en **centavos** (sin float drift).
- **D-C-54** — **A25 `periodo_hasta` híbrido + preservación de ausencia en el gateway.** Floor `2026-07-01` (D-NEG-02) clampea `periodo_desde`. `periodo_hasta`: **omitido → hoy (`CURRENT_DATE`), SIN check de inversión** (con el floor en el futuro, `periodo_desde > periodo_hasta` → la query devuelve **vacío con `ok:true`**, totales 0); **explícito → YMD válido y, tras el clamp, `>= periodo_desde`**, sino `payload_invalido` (incluido `null`/no-string/mal formado/invertido). En el gateway, `payloadIngresosPeriodo` **preserva la ausencia real de `periodo_hasta`**: si el cliente la omite, el `value` firmado **NO incluye la clave** (el wrapper directo aplica el default "hoy"), para **no cambiar la semántica entre gateway y directo**. `periodo_hasta` es inclusivo (half-open `+1 día` en el SQL).

## Lecciones operativas n8n consolidadas (L-6C-XX)

Reglas firmes derivadas de la ejecución de la Etapa 6C. Detalle completo en `Lecciones_Aprendidas.md`.

- **L-6C-01:** Credencial PostgreSQL contra pooler de Supabase requiere `Ignore SSL Issues: ON`.
- **L-6C-02:** El user del pooler de Supabase es `postgres.<project_id>`, no `postgres`.
- **L-6C-03:** Query Parameters de n8n no soportan NULL real. Workaround: convención `0=todas` + `NULLIF($N::TYPE, 0)` en función SQL.
- **L-6C-04:** Postgres node con result vacío detiene el flujo. Mitigación obligatoria: `Always Output Data: ON` + filter defensivo en Code downstream.
- **L-6C-05:** BIGINT serializa como string en JSON, DATE como ISO timestamp. Consciencia operativa, no requiere fix.
- **L-6C-06:** `={{ JSON.stringify($json.payload) }}` funciona limpio para JSONB en `queryReplacement`.

## Lecciones operativas hardening consolidadas (L-6D-XX)

Reglas firmes derivadas de la ejecución de la Etapa 6D (bloques H1-H7). Detalle completo en `Lecciones_Aprendidas.md`.

- **L-6D-01:** Schema canónico no es fuente de verdad para cuerpos reales. Snapshot con `pg_get_functiondef`/`pg_get_viewdef` antes de proponer cambios.
- **L-6D-02:** PostgreSQL normaliza expresiones al persistir vistas y funciones (`TRIM(x)` → `TRIM(BOTH FROM x)`, `'12 months'` → `'1 year'`, `'1 month'` → `'1 mon'`).
- **L-6D-03:** Patrón canónico de extract defensivo para funciones write: `NULLIF(TRIM(payload->>'campo'), '')::TIPO`.
- **L-6D-04:** Tests no destructivos deben identificar la frontera antes de la primera escritura. En funciones con operaciones tempranas en tablas (ej. `crear_prereserva` → `upsert_huesped` en paso 4), la frontera es la última validación antes de esa escritura.
- **L-6D-05:** Antes de `CREATE OR REPLACE VIEW`, verificar dependencias con `pg_depend` + `pg_rewrite` y no cambiar estructura de columnas (nombres, tipos, orden).
- **L-6D-06:** Mecánica para tests de concurrencia en SQL Editor de Supabase: dos tabs separadas del navegador + mini-test de PIDs previo + CTEs encadenadas con `MATERIALIZED` + `FROM`.
- **L-6D-07:** Contrato real de `registrar_pago` para pago `confirmado` directo: `estado_inicial='confirmado'` + `monto_recibido=monto_esperado` + pre-reserva activa. Campo de referencia es `referencia_externa`, no `referencia`. `modificado_por` del log = `COALESCE(validado_por, 'registrar_pago')`.
- **L-6D-08:** Trigger `trg_log_*_estado` solo dispara en `AFTER UPDATE OF estado`, no en INSERT ni en UPDATE de otras columnas. Conteo esperado de logs depende de transiciones de estado, no de UPDATE genéricos.
- **L-6D-09:** Naming real confirmado empíricamente en DEV: `cabanas.capacidad_max`, `bloqueos.activo` BOOLEAN, error `estado_invalido` en `confirmar_reserva` con estado terminal, `telefono_normalizado` preserva `+`, payload de pago usa `referencia_externa`.

## Lecciones operativas TEST consolidadas (L-7B-XX)

Reglas firmes derivadas de la ejecución de la Etapa 7B (levantamiento del entorno TEST). Detalle en `Lecciones_Aprendidas.md`.

- **L-7B-01:** `current_database()` no discrimina ambiente en Supabase. Todos los proyectos Supabase tienen la base llamada `postgres`, por lo que un chequeo de ambiente basado en `db` es inválido. Para discriminar usar `current_user` (que trae `postgres.<project_ref>` cuando se entra por pooler), `inet_server_addr()` o, mejor, leer datos del seed específicos del ambiente (ej. IDs de cabaña).
- **L-7B-02:** "Nacer cerrado" solo aplica al snapshot pre-objetos. Los defaults de PostgreSQL/Supabase aplican `Dxtm` (TRUNCATE/REFERENCES/TRIGGER) sobre tablas/vistas y `EXECUTE` para `PUBLIC` sobre funciones al *crear* cada objeto. Cada función nueva en `public` requiere `REVOKE EXECUTE` explícito (ver D-7B-05).
- **L-7B-03:** Para contar triggers usar `pg_trigger` con filtro `NOT tgisinternal`, no `information_schema.triggers`. Esta última vista multiplica filas por evento (INSERT/UPDATE/DELETE) y genera falsos positivos de conteo: 12 triggers reales pueden aparecer como 18-24 según los eventos definidos. Ejemplo: `SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgrelid::regclass::text NOT LIKE 'pg_%';`

## Lecciones operativas de validación funcional consolidadas (L-7C-XX)

Reglas firmes derivadas de la ejecución de la Etapa 7C (validación funcional ampliada sobre TEST). **Detalle completo en `Lecciones_Aprendidas.md` (L-7C-01 a L-7C-06); no se duplican aquí** para evitar divergencia documental.

## Lecciones operativas de endurecimiento DEV consolidadas (L-7E-XX)

Regla firme derivada de la ejecución de la Etapa 7E (endurecimiento de permisos Data API en DEV).

- **L-7E-01:** En Supabase, el SQL Editor del Dashboard conecta como `postgres` directo (no por pooler), por lo que `current_user` allí devuelve `postgres` y NO el patrón `postgres.<project_ref>`. En ese contexto el discriminador fuerte de ambiente debe ser la identidad del seed (IDs exactos de cabaña), no `current_user` (consistente con L-7B-01). El veredicto de entorno por `(id_cabana, nombre)` cumplió ese rol como gate inequívoco en el snapshot, en el re-gate transaccional del cambio y en la verificación posterior.

## Reconstrucción de DEV desde v1.8.0 — cerrada 2026-06-15

Decisiones del **levantamiento de entorno** de la reconstrucción de DEV desde cero a partir del canónico v1.8.0 (proyecto Supabase nuevo `VITA_DELTA_DEV` / `wsrdzjmvnzxidjlovlja`). No reabre 9C→9H, la promoción a OPS ni el canónico. Cierre: `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md`. **No reabrir.**

- **D-RDEV-01** — DEV se reconstruye **desde cero desde v1.8.0** en un proyecto Supabase **nuevo**; no se reusa ni clona el DEV viejo. Materializa D-PROMO-13; consistente con D-7B-01 (reconstrucción desde canónico, nunca clonación física).
- **D-RDEV-02** — El proyecto se crea **cerrado como OPS** (Data API ON, "Automatically expose new tables" OFF, "Enable automatic RLS" OFF). Resuelve el residual A5 / pendiente 1.7 **por construcción**.
- **D-RDEV-03** — El **discriminador de entorno** del DEV nuevo es el marcador `configuracion_general('ambiente')='dev'`, **no** el ID de cabaña: el DEV nuevo nace con IDs 1-5 igual que TEST/OPS. Extiende L-7E-01.
- **D-RDEV-04** — El **residual `Dxtm`** en tablas base/vistas (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN a roles API) se **acepta por paridad OPS/TEST** y **no se revoca**. No incluye SELECT/INSERT/UPDATE/DELETE.
- **D-RDEV-05** — Las **13 funciones del motor** se endurecen por **REVOKE EXECUTE** (espejo de 7E / 8A Opción B), gateado por `ambiente='dev'`. No es rediseño de schema.
- **D-RDEV-06** — El **DEV viejo se conserva congelado** (no se borra) tras cerrar el nuevo. Su eliminación es decisión separada y posterior.

## Prototipos legacy

- `index.html` — presentación visual estática del estado del sistema. No es frontend operativo ni web pública de reservas.
- `vita_delta_workflow.json` y similares — pilotos del backend pre-Supabase.
- Archivos `.gs` — scripts de Apps Script del backend viejo.
- Archivos JSON de tests del Bloque 13 (`dev_db_*.json`, `test_db_*.json`) — artefactos de validación pre-migración.
- `Workflows/n8n/*.template.json` (sin subcarpeta `supabase/`) — workflows legacy contra Sheets, congelados.

**Ninguno de estos artefactos debe contradecir las decisiones cerradas de las Etapas 1-6D, 7A ni 7B, ni de las Fases 1-3 de implementación en DEV ni del levantamiento de TEST.**