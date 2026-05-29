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

## Prototipos legacy

- `index.html` — presentación visual estática del estado del sistema. No es frontend operativo ni web pública de reservas.
- `vita_delta_workflow.json` y similares — pilotos del backend pre-Supabase.
- Archivos `.gs` — scripts de Apps Script del backend viejo.
- Archivos JSON de tests del Bloque 13 (`dev_db_*.json`, `test_db_*.json`) — artefactos de validación pre-migración.
- `Workflows/n8n/*.template.json` (sin subcarpeta `supabase/`) — workflows legacy contra Sheets, congelados.

**Ninguno de estos artefactos debe contradecir las decisiones cerradas de las Etapas 1-6D, 7A ni 7B, ni de las Fases 1-3 de implementación en DEV ni del levantamiento de TEST.**