# ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md
# Etapa 6B — Migración a Supabase / PostgreSQL

**Versión:** 1.0
**Fecha:** Mayo 2026
**Estado:** Arquitectura consolidada — base de datos lista para ejecución
**Proyecto:** Sistema de gestión y automatización — Complejo Vita Delta
**Autores:** Franco (titular) + Claude (arquitecto)
**Depende de:** `Docs/Arquitectura/ARQUITECTURA_ETAPA_6A_DECISION_MIGRACION.md v1.1`
**Sucesora directa de:** `Docs/Arquitectura/ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md v1.1`

> **Sanitización:** Este documento está sanitizado para GitHub. No contiene Project ID, Project URL, passwords, connection strings, anon keys, service role keys ni datos reales de huéspedes. Cualquier credencial real vive fuera del repositorio.

---

## ÍNDICE

1. Resumen ejecutivo
2. Contexto
3. Decisión técnica
4. Principios de diseño
5. Componentes de la solución
6. Funciones críticas
7. Estrategia anti-double-booking
8. Flujo web futuro
9. Carga manual segura
10. Alcance de la Etapa 6B
11. Documentos relacionados
12. Estado actual
13. Riesgos y mitigaciones
14. Próximo paso

---

## 1. RESUMEN EJECUTIVO

### Por qué se migra de Sheets a Supabase

Sheets sirvió como base de datos inicial durante las Etapas 1 a 5. Hizo posible iterar rápido sobre el modelo operativo del complejo, validar flujos de reserva con n8n y construir el motor de disponibilidad sin pagar infraestructura. Pero tiene tres limitaciones que se volvieron incompatibles con lo que sigue:

1. **No garantiza integridad transaccional.** Una pre-reserva, su pago y la actualización de disponibilidad no pueden coordinarse en Sheets como una sola operación atómica. Si algo falla a mitad de camino, queda inconsistencia silenciosa.

2. **No previene double booking estructuralmente.** En Sheets, evitar que dos pre-reservas pisen el mismo rango depende enteramente de lógica imperativa en n8n. Cualquier carrera entre workflows o entre canales puede producir reservas solapadas.

3. **No escala al volumen que viene.** El workflow de pre-reserva en n8n contra Sheets demora varios segundos por la latencia del API. Cuando entre la web pública y se reciban consultas de disponibilidad en paralelo, esto se vuelve un cuello de botella.

### Qué problema resuelve esta etapa

Esta etapa **migra la fuente de verdad operacional** de Sheets a una base de datos PostgreSQL alojada en Supabase. El resultado es:

- Integridad transaccional real.
- Prevención de double booking enforced por constraints del schema (no por código).
- Latencia mucho menor para operaciones de disponibilidad.
- Base sólida sobre la que se podrán construir: la web pública, la reescritura de workflows n8n, la integración real con MercadoPago, y eventualmente contabilidad.

### Qué gana el proyecto

- **Confianza.** Las reglas de negocio críticas viven en la base, no en n8n. Si n8n se reinicia, se reescribe o se reemplaza, las reglas siguen.
- **Velocidad.** PostgreSQL responde en milisegundos a operaciones que en Sheets tardaban segundos.
- **Trazabilidad.** Toda escritura crítica deja registro en `log_cambios` con `source_event`.
- **Idempotencia.** Reintentos seguros sin riesgo de duplicación.
- **Concurrencia controlada.** Locks globales y por cabaña garantizan que operaciones simultáneas se serialicen correctamente.

### Qué NO se está intentando resolver todavía

- **No** se está construyendo la web pública en esta etapa.
- **No** se está reescribiendo n8n todavía.
- **No** se está integrando MercadoPago real.
- **No** se están migrando los datos productivos desde Sheets.
- **No** se está habilitando RLS ni Supabase Auth.
- **No** se está tocando producción.

Esta etapa solo construye la base de datos en un entorno DEV controlado y la valida con tests. Las demás piezas vienen después, una por una.

---

## 2. CONTEXTO

### Estado previo (Etapas 1 a 5)

**Sheets como base de datos inicial.** El complejo opera desde hace meses con un Google Sheets donde Vicky carga reservas manualmente, donde n8n vuelca consultas de Instagram/WhatsApp, y donde un calendario consolidado muestra disponibilidad. Funciona, pero es frágil.

**n8n como orquestador.** Los workflows de n8n son los que efectivamente "operan" el sistema: reciben mensajes, llaman a APIs, escriben en Sheets, calculan disponibilidad, mandan respuestas. n8n es el motor.

**Workflow de pre-reserva tardando demasiado.** El workflow actual para crear una pre-reserva hace varias llamadas seriales a la API de Sheets y a subworkflows de validación/recalculo. En pruebas reales llegó a tardar alrededor de 23–26 segundos. Ese tiempo puede ser tolerable para carga manual o pruebas internas, pero resulta poco profesional para una web pública con usuarios esperando respuesta inmediata.

**Necesidad de garantías transaccionales.** Una pre-reserva implica: insertar la pre-reserva, actualizar disponibilidad cache, registrar log, opcionalmente notificar. Si una de esas escrituras falla, las otras no deben quedar aplicadas. Sheets no ofrece transacciones; PostgreSQL sí.

**Necesidad de evitar double booking.** Con Instagram + WhatsApp + Booking + Airbnb operando en paralelo, y eventualmente la web pública, el riesgo de que dos clientes terminen reservando la misma cabaña en el mismo rango es real. Sheets no puede prevenir esto estructuralmente.

**Preparación para web pública futura.** Una web de reservas tiene tres requisitos no negociables que Sheets no cumple bien: (a) latencia baja en consultas de disponibilidad, (b) prevención atómica de race conditions cuando dos visitantes intentan reservar lo mismo a la vez, (c) idempotencia ante retries del cliente o problemas de red.

### Decisión previa (Etapa 6A)

La Etapa 6A evaluó alternativas concretas (Sheets enriquecido, Airtable, Supabase, Postgres self-hosted) y concluyó en **Supabase PostgreSQL** por combinación de: integridad transaccional real, latencia baja, costo cero en el tier free para DEV, ecosistema maduro, y disponibilidad de extensiones (`btree_gist`, `pg_cron`) que el modelo necesita.

Esta etapa 6B materializa esa decisión.

---

## 3. DECISIÓN TÉCNICA

### Postgres nativo en Supabase

La base de datos es **PostgreSQL** corriendo en **Supabase** (`sa-east-1`, plan free para DEV). No se usa Airtable ni un Postgres self-hosted. Razones consolidadas en Etapa 6A.

### Supabase DEV como primer entorno

Antes de cualquier consideración de producción, se construye **un único entorno DEV**. En DEV se ejecuta el schema completo, se carga seed mínimo, se corren 36 tests funcionales y de concurrencia, y solo después de pasar todos los tests se declara "Supabase DEV listo".

No se mezcla DEV con datos reales de huéspedes. No se conecta DEV con n8n productivo. DEV es un entorno aislado y desechable.

### PostgreSQL como fuente de verdad

A partir del cierre de esta etapa, **PostgreSQL pasa a ser la fuente de verdad operacional**. Sheets puede seguir existiendo como vista auxiliar o espejo (replicado vía n8n con propósitos operativos: panel de Vicky, calendario impreso), pero **toda escritura crítica pasa por funciones SQL en PostgreSQL**.

Si Sheets y PostgreSQL discrepan, PostgreSQL gana.

### n8n como orquestador

n8n sigue siendo el cerebro que orquesta el mundo externo: recibe mensajes de WhatsApp/Instagram, llama a MercadoPago, sincroniza calendarios externos (Booking/Airbnb cuando se conecten), notifica al equipo. Pero **n8n no calcula disponibilidad ni decide si una pre-reserva es válida**. n8n llama a las funciones SQL de PostgreSQL, que son las que aplican las reglas.

n8n es ejecutor. PostgreSQL es juez.

### Sheets como vista auxiliar, no como base principal

Después de esta etapa, Sheets cumplirá uno o varios de estos roles operativos, ninguno de ellos como fuente de verdad:

- **Panel de Vicky.** Vista de calendario semanal con reservas confirmadas + pre-reservas activas.
- **Calendario impreso para limpieza.** Vista filtrada por fecha y cabaña.
- **Espejo histórico.** Backup eventual de reservas para revisión humana.

La reescritura de los workflows n8n (etapa siguiente) replicará estos roles vía sincronización Postgres → Sheets, no al revés.

---

## 4. PRINCIPIOS DE DISEÑO

Los principios que guiaron las decisiones de schema, funciones, locks y testing.

### PostgreSQL protege integridad

Constraints, EXCLUDE, CHECK, FOREIGN KEY y triggers son la primera línea de defensa. Si el schema no permite un estado inconsistente, el resto del sistema no necesita preocuparse por ese estado. Ejemplos:

- `EXCLUDE` en `reservas` impide dos reservas confirmadas solapadas en la misma cabaña.
- `CHECK` en `pagos` exige `id_prereserva` o `id_reserva` (al menos uno).
- `UNIQUE` parcial en `idempotency_key` previene pre-reservas duplicadas por retries.

### n8n orquesta, no valida disponibilidad crítica

n8n llama a `crear_prereserva()`, `confirmar_reserva()`, `crear_bloqueo()`. **No** decide si esas operaciones son válidas. Las funciones SQL devuelven `{ok: true/false, error: '...'}` y n8n actúa en consecuencia, pero la decisión es de PostgreSQL.

Esta separación protege contra: workflows mal escritos, race conditions en n8n, errores humanos al modificar workflows, eventuales reemplazos de n8n por otra herramienta.

### Funciones SQL como puertas únicas

Toda escritura crítica pasa por una función SQL que valida, lockea, opera y registra. No hay INSERTs sueltos desde n8n a `reservas`, `pre_reservas`, `pagos` o `bloqueos`. Las funciones son las puertas únicas:

| Operación | Puerta única |
|---|---|
| Crear pre-reserva | `crear_prereserva(payload)` |
| Confirmar reserva | `confirmar_reserva(payload)` |
| Cancelar pre-reserva | `cancelar_prereserva(payload)` |
| Crear bloqueo | `crear_bloqueo(payload)` |
| Registrar pago | `registrar_pago(payload)` |
| Expirar pre-reservas vencidas | `expirar_prereservas_vencidas()` |

Esto garantiza que: las validaciones se aplican siempre, los logs se escriben siempre, los locks se toman siempre, los retries son idempotentes siempre.

### No edición directa insegura

Las tablas críticas no se editan a mano desde la consola SQL Editor en operación normal. Si Vicky o Franco necesitan hacer una corrección puntual (caso real, ej: corregir una nota tipeada mal), pueden:

- Hacer UPDATE de campos no críticos (notas, observaciones).
- **NO** modificar manualmente `estado`, `fecha_in`, `fecha_out`, `id_cabana` ni montos. Para eso se diseñará una función de "edición controlada" en etapa posterior si hace falta.

### Carga manual segura

Vicky carga pre-reservas manualmente desde el panel de Vicky o el bot interno. Esa carga manual pasa por `crear_prereserva()` (la misma función que usaría la web). El campo `canal_origen='manual'` distingue el origen, pero el flujo de validación es idéntico.

Resultado: no hay un "modo manual" más laxo que el modo automático. Las reglas son las mismas.

### Locks globales para disponibilidad

Toda operación que afecte disponibilidad toma primero un advisory lock global `(10, 0)` antes de cualquier otro lock (row, cabaña, table). Esto serializa entre sí a las operaciones críticas y elimina race conditions entre canales.

Detalle completo en Sección 7.

### Idempotencia

Las pre-reservas soportan `idempotency_key`. Si n8n o la web envían el mismo payload dos veces (por retry, doble click, network glitch), la segunda llamada devuelve la pre-reserva original en lugar de crear una nueva.

Tres caminos de recuperación cubren todos los escenarios de carrera posible:
- `pre_lock`: detectada antes del advisory lock.
- `post_lock`: detectada después del advisory lock pero antes del INSERT.
- `unique_violation`: detectada por el constraint UNIQUE durante el INSERT.

En cualquiera de los tres casos, el cliente recibe la misma `id_pre_reserva` sin saber por qué camino se recuperó.

### Errores esperables como JSONB controlado

Las funciones SQL no lanzan excepciones para casos esperables. Devuelven `{ok: false, error: '<código>', ...}` con códigos estables. n8n puede hacer `switch(error)` y actuar.

Códigos de error estables: `huesped_nombre_requerido`, `huesped_contacto_requerido`, `cabana_no_existe`, `excede_capacidad`, `no_disponible`, `precio_requerido`, `sin_pago_confirmado`, `conflicto_con_reserva`, `conflicto_con_prereserva`, `bloqueo_solapado`, `prereserva_no_activa` (warning, no error), etc.

Excepciones reales solo aparecen ante errores técnicos no esperables (constraint inesperado, conexión cortada, etc.).

### Secrets fuera del repo

Las credenciales de Supabase (Project ID, password, anon key, service role key, connection string) **nunca se commitean al repo**. Los documentos del proyecto usan placeholders como `__SUPABASE_PROJECT_ID_DEV__`. Las credenciales reales viven en gestores de contraseñas y en credentials de n8n.

---

## 5. COMPONENTES DE LA SOLUCIÓN

Descripción a alto nivel de qué construye la Etapa 6B. El detalle SQL completo vive en `6B_SCHEMA_SQL.md v1.5`.

### Tablas (20 tablas)

**Catálogo (8):** `cabanas`, `huespedes`, `feriados`, `tarifas`, `temporadas`, `socios`, `cuentas_cobro`, `plantillas_mensajes`.

**Configuración (4):** `configuracion_general`, `eventos_especiales`, `paquetes_evento`, `descuentos`.

**Dependientes nivel 1 (2):** `consultas` (registro de interacciones bot/canal), `overrides_operativos`.

**Transaccionales (5):** `pre_reservas`, `reservas`, `pagos`, `bloqueos`, `gastos`.

**Auditoría (1):** `log_cambios` (con índice GIN sobre el JSONB de detalle).

### Constraints

- **EXCLUDE en `reservas`** sobre `(id_cabana, daterange(fecha_checkin, fecha_checkout))` con condición `estado IN ('confirmada', 'activa')`. Garantía estructural contra double booking.
- **EXCLUDE en `bloqueos`** sobre `(id_cabana, daterange(fecha_desde, fecha_hasta))` con condición `activo = TRUE AND id_cabana IS NOT NULL`. Garantía estructural contra bloqueos específicos solapados.
- **CHECK** en pagos: `id_prereserva` o `id_reserva` debe estar presente.
- **UNIQUE parcial** en pre_reservas: `idempotency_key` única solo cuando estado es activo (`pendiente_pago` o `pago_en_revision`).
- **FOREIGN KEY** entre todas las tablas relacionadas, con `ON DELETE` apropiado para cada caso.

### Funciones críticas (11 funciones)

Listadas en Sección 6. Implementan todas las operaciones de negocio críticas como puertas únicas transaccionales.

### Triggers (13+ triggers)

- **`updated_at`** automático en 9 tablas con campo `updated_at`.
- **Log de cambios de estado** en `pre_reservas`, `reservas`, `pagos`. Captura quién, cuándo, desde qué `source_event`, qué estado anterior y nuevo.
- **Normalización de teléfono** en `huespedes`: trigger que llena `telefono_normalizado` automáticamente al insertar o actualizar.

### Vistas (6 vistas)

- `vista_disponibilidad`: rango de fechas + cabaña → disponible/ocupado con motivo.
- `vista_calendario`: calendario general de reservas + bloqueos.
- `vista_prereservas_activas`: pre-reservas no terminales con tiempo restante hasta vencimiento.
- `vista_ocupacion`: porcentaje de ocupación por período.
- `vista_calendario_semanal`: vista compacta para operación semanal.
- `vista_limpieza_semana`: vista filtrada para Jennifer/limpieza.

### pg_cron

Dos jobs schedulados:

- `expirar_prereservas` cada 5 minutos: marca como `vencida` toda pre-reserva `pendiente_pago` con `expira_en <= NOW()`.
- `cleanup_cron_history` mensual: limpia tabla interna de historia de pg_cron.

### Seed mínimo

Datos imprescindibles para que el sistema arranque:

- 5 cabañas con capacidades correctas (Bamboo/Madre Selva/Arrebol = 3/5; Guatemala/Tokio = 2/4).
- 3 socios (Franco, Rodrigo, "Socio 3" placeholder).
- 9 claves de `configuracion_general` (horarios default, expiración default de pre-reserva, escalonamiento de check-ins, etc.).
- 1 cuenta de cobro placeholder.
- 1 temporada baseline.
- 1 plantilla de mensaje de ejemplo.

### Tests

36 tests obligatorios distribuidos en 8 categorías (huéspedes, pre-reservas, disponibilidad, confirmación, bloqueos, pagos, expiración, concurrencia). Cuatro de ellos son tests de concurrencia que requieren ejecutar manualmente en dos pestañas del SQL Editor de Supabase con `pg_sleep`.

Detalle en `6B_PLAN_FASES.md v1.1`.

### Plan de ejecución

5 fases ordenadas:

- **Fase 0:** preparación (no ejecuta SQL).
- **Fase 1:** infraestructura base (Bloques 1-8).
- **Fase 2:** funciones y triggers (Bloques 9-19).
- **Fase 3:** vistas, seed, cron (Bloques 20-22).
- **Fase 4:** tests funcionales y de concurrencia.
- **Fase 5:** cierre formal.

Detalle en `6B_PLAN_FASES.md v1.1`.

---

## 6. FUNCIONES CRÍTICAS

Resumen breve de cada función. El SQL completo vive en `6B_SCHEMA_SQL.md v1.5`.

### `upsert_huesped(payload JSONB)`

Crea o actualiza un huésped. Resuelve por teléfono normalizado primero, después por email, después por DNI. Maneja `unique_violation` con recuperación silenciosa. Devuelve `{ok, modo, id_huesped, encontrado_por}`.

Flexible para callers diversos (bot conversacional, consultas preliminares) — acepta payloads incompletos. La validación estricta de nombre y contacto la hace `crear_prereserva`.

### `crear_prereserva(payload JSONB)`

**Puerta única para crear pre-reservas.** Llamada desde n8n (manual, WhatsApp, web futura) y eventualmente desde el bot.

Flujo: extrae payload → valida nombre y contacto → idempotency pre-check → toma lock global + lock por cabaña → idempotency post-check (cubre carrera con el pre-check) → resuelve huésped vía `upsert_huesped` → valida cabaña/capacidad → valida disponibilidad → calcula horarios desde `configuracion_general` → INSERT → maneja `unique_violation` → log.

Devuelve `{ok, idempotent_match, recovery_path, id_pre_reserva, id_huesped, estado, expira_en, hora_checkin, hora_checkout}`.

### `confirmar_reserva(payload JSONB)`

**Convierte pre-reserva en reserva confirmada.** Soporta camino estricto (solo con pago confirmado) y camino combinado (con `permitir_pago_en_revision=true` + `validado_por`).

Flujo: extrae payload → set_config para contexto de logs → **lock global PRIMERO (orden crítico v1.5)** → SELECT FOR UPDATE de la pre-reserva → lock por cabaña → verifica pago → revalida disponibilidad excluyendo la propia pre-reserva → INSERT en reservas copiando todos los campos operativos (mascotas, ninos, notas) → UPDATE pre-reserva a `convertida` → UPDATE pago con `id_reserva` → UPDATE huésped (total_reservas, primera_reserva_fecha) → log.

Devuelve `{ok, id_reserva, id_pre_reserva}`.

### `cancelar_prereserva(payload JSONB)`

Cancela una pre-reserva con motivo. **No toca pagos asociados** — los devuelve para revisión humana posterior. El equipo decide si reembolsa, reasigna o gestiona manualmente.

Toma lock global (no lock por cabaña — solo libera disponibilidad). Mapea motivo (`cliente` / `bloqueo`) al estado terminal correspondiente.

### `crear_bloqueo(payload JSONB)`

Crea un bloqueo de cabaña específica o un bloqueo total del complejo. Valida conflictos con reservas activas, pre-reservas vigentes y bloqueos solapados (las 4 combinaciones).

Toma lock global. Si es bloqueo específico, también toma lock por cabaña. **No usa `LOCK TABLE`** (eliminado en v1.4 por D46).

### `registrar_pago(payload JSONB)`

Registra un pago asociado a una pre-reserva o a una reserva. Determina el estado del pago según monto recibido vs esperado y `estado_inicial` del payload.

Si la pre-reserva referenciada está en estado terminal (`vencida`, `cancelada_*`, `conflicto_pendiente`): fuerza estado del pago a `en_revision`, no reactiva la pre-reserva, devuelve `warning: 'prereserva_no_activa'` con el estado real de la pre-reserva. Esto permite que un pago tardío quede registrado para revisión humana sin corromper el estado del sistema.

### `expirar_prereservas_vencidas()`

Función llamada por pg_cron cada 5 minutos. Marca como `vencida` toda pre-reserva en `pendiente_pago` con `expira_en <= NOW()`. Usa `FOR UPDATE SKIP LOCKED` para no bloquearse contra otras operaciones.

**No toma lock global** — opera sobre pre-reservas que ya no bloquean disponibilidad lógica.

### `validar_disponibilidad(id_cabana, fecha_in, fecha_out, excluir_prereserva)`

Función auxiliar. Verifica solapamientos con reservas activas, pre-reservas vigentes (`pendiente_pago` con `expira_en > NOW()` o `pago_en_revision`) y bloqueos activos (incluidos totales).

Usa `SELECT FOR UPDATE` internamente. **Debe llamarse solo desde funciones que ya tomaron el lock global** (Observación G de v1.5).

### `obtener_disponibilidad_rango(fecha_desde, fecha_hasta, id_cabana)`

Función de solo lectura. Devuelve disponibilidad por día para una cabaña (o todas) en un rango. Usada por vistas y eventualmente por la web pública para mostrar calendarios.

### `normalizar_telefono(input TEXT)`

Helper `IMMUTABLE` que normaliza teléfonos: elimina espacios/guiones/paréntesis, convierte `00` a `+`, colapsa múltiples `+`. **Conservadora**: no asume prefijo argentino si no viene. Usada por trigger en `huespedes`.

---

## 7. ESTRATEGIA ANTI-DOUBLE-BOOKING

Defensa en profundidad con 5 capas. Cada capa cubre un tipo de conflicto.

### Capa 0 — Lock global de disponibilidad

`pg_advisory_xact_lock(10, 0)` se toma al inicio de toda función que afecta disponibilidad. Serializa entre sí a `crear_prereserva`, `confirmar_reserva`, `cancelar_prereserva`, `crear_bloqueo`. Solo una de estas operaciones puede correr a la vez en todo el sistema.

A 5 cabañas y volumen bajo, la contención es invisible (milisegundos). El beneficio es que ningún tipo de race puede ocurrir entre estas operaciones.

### Capa 1 — EXCLUDE en `reservas`

Constraint estructural: dos reservas en estado `confirmada` o `activa` no pueden solaparse en la misma cabaña. Esto vive en el schema, no en código. Aún si una función fallara catastróficamente, PostgreSQL rechaza el INSERT.

### Capa 2 — EXCLUDE en `bloqueos` específicos

Constraint estructural para bloqueos por cabaña específica (`id_cabana IS NOT NULL`). No cubre bloqueos totales (`id_cabana IS NULL`) porque el EXCLUDE no aplica con NULL.

### Capa 3 — `validar_disponibilidad` + locks

Las pre-reservas no se pueden cubrir con EXCLUDE porque su vigencia depende de `expira_en > NOW()` (no determinista). La validación es transaccional: dentro del lock global + lock por cabaña, se chequean reservas, pre-reservas vigentes y bloqueos solapados.

### Capa 4 — Revalidación al confirmar

`confirmar_reserva` revalida disponibilidad antes del INSERT en `reservas`, excluyendo la propia pre-reserva. Esto previene que entre la creación de la pre-reserva y su confirmación (que puede ser horas o días después) haya entrado otra reserva o bloqueo en el rango.

### Capa 5 — Validaciones manuales en `crear_bloqueo` total

Para bloqueos totales (que el EXCLUDE no cubre), `crear_bloqueo` valida manualmente las 4 combinaciones: total vs total, total vs específico, específico vs total, específico vs específico. La Capa 0 garantiza que estas validaciones son seguras (no hay race condition).

### Por qué se eliminó `LOCK TABLE`

Hasta v1.3 inclusive, los bloqueos totales se serializaban con `LOCK TABLE EXCLUSIVE`. En v1.4 se detectó que mezclar `LOCK TABLE` con `pg_advisory_xact_lock(1, id_cabana)` no se coordinaba: las dos primitivas son independientes en PostgreSQL.

Ejemplo del bug: `crear_prereserva` tomaba advisory lock por cabaña, validaba que no había bloqueo total, luego `crear_bloqueo` total tomaba `LOCK TABLE`, validaba, insertaba. Pero `crear_prereserva` ya había pasado la validación y seguía con su INSERT. Resultado: pre-reserva y bloqueo total solapados.

La solución (v1.4, D46) fue introducir el lock global `(10, 0)` como mecanismo común a TODAS las operaciones críticas, y eliminar `LOCK TABLE` por completo.

### Por qué esto es suficiente para 5 cabañas

Vita Delta tiene 5 cabañas y opera con volúmenes bajos (decenas de pre-reservas por mes). El lock global serializa todo el sistema, lo cual sería un problema si hubiera miles de operaciones por segundo. A esta escala, no lo es.

Si en el futuro la operación escala a decenas de cabañas o cientos de operaciones concurrentes, se puede migrar a un patrón más granular (locks por cabaña sin lock global, con coordinación shared/exclusive para bloqueos totales). Esa migración está documentada como camino futuro pero no como necesidad actual.

---

## 8. FLUJO WEB FUTURO

Cómo se diseñará el flujo cuando exista la web pública. **Esto NO se implementa en 6B**, pero se diseña ahora para que el schema lo soporte sin cambios.

### Flujo cliente

1. **Cliente elige cabaña, fechas y personas.** La web muestra calendario de disponibilidad (proveniente de `vista_disponibilidad` o `obtener_disponibilidad_rango`).

2. **`consultar_disponibilidad_precio()` devuelve precio.** Función pendiente de implementar. Combina disponibilidad + cálculo de precio (motor de precios en n8n por ahora, eventualmente migrado a PostgreSQL). Devuelve precio total, seña, descuentos aplicados.

3. **Cliente acepta.** La web muestra resumen + términos + botón "pagar seña".

4. **`crear_prereserva()`.** La web llama a la función con `idempotency_key` único (UUID generado en el cliente). Si el cliente refresca o doble-clickea, la idempotencia garantiza que no se crea otra pre-reserva.

5. **Pago.** La web redirige al cliente al checkout de MercadoPago. n8n recibe el webhook de MercadoPago.

6. **`registrar_pago()`.** n8n llama a la función con los datos del pago. Si el pago es exacto y `estado_inicial='confirmado'`, el pago queda confirmado automáticamente. Si no, queda en `en_revision`.

7. **`confirmar_reserva()`.** n8n llama a la función. Si todo está OK, la pre-reserva pasa a `convertida` y se crea la reserva en `reservas`. n8n notifica al cliente y al equipo.

### Pieza obligatoria pendiente: `consultar_disponibilidad_precio`

**Esta función NO existe en 6B.** Su falta no bloquea la ejecución de 6B porque el motor de precios actual vive en n8n y sigue funcionando ahí.

Pero **antes de habilitar la web pública**, esta función es obligatoria. Por dos razones:

- **Atomicidad.** La web necesita un endpoint único que devuelva precio + disponibilidad en la misma transacción, no dos llamadas separadas que pueden quedar inconsistentes.
- **Latencia.** Cálculos de precio en n8n son ~1 segundo. Para una web pública, eso es demasiado por cada cambio de fechas/personas.

Cuándo y cómo se implementa esta función queda fuera del alcance de 6B. Probablemente se haga en una etapa dedicada que migre el motor de precios desde n8n a PostgreSQL.

---

## 9. CARGA MANUAL SEGURA

Vicky, Rodrigo y Franco siguen operando el sistema mientras la web pública no exista. La carga manual debe ser segura: mismo nivel de validación que la web automática, sin atajos.

### Operaciones del equipo

- **Crear pre-reserva manualmente.** Vicky carga datos en un formulario (futuro panel propio o Sheets-input). Eso dispara n8n → `crear_prereserva()` con `canal_origen='manual'`. Idéntico flujo que la web pública.

- **Confirmar reserva manualmente.** Cuando llega un comprobante de pago por WhatsApp, Vicky registra el pago vía n8n → `registrar_pago()`. Si el pago es correcto, dispara `confirmar_reserva()`. Si está en revisión, queda pendiente para Franco.

- **Registrar pago manualmente.** Pagos en efectivo, transferencias manuales, MercadoPago manual (link enviado por WhatsApp): todos pasan por `registrar_pago()` con `medio_pago` apropiado.

- **Bloquear fechas.** Mantenimiento, uso propio, tormenta: pasan por `crear_bloqueo()` con motivo. Si hay reservas en conflicto, la función las rechaza y obliga a resolverlas primero.

- **Cancelar pre-reserva.** Si el cliente desiste o no paga, Vicky cancela vía `cancelar_prereserva()`. Los pagos asociados quedan para revisión manual.

### Lo que NO se debe hacer manualmente

- **NO** modificar estados directamente con `UPDATE pre_reservas SET estado = ...`.
- **NO** insertar reservas a mano con `INSERT INTO reservas ...`.
- **NO** borrar pagos.
- **NO** editar `id_cabana`, `fecha_in`, `fecha_out` ni montos directamente.

Si surge un caso operativo que las funciones no cubren bien (ej: una reserva firmada en papel hace 2 años que hay que cargar retroactivamente), se diseña una función dedicada para ese caso o se decide caso-por-caso con Franco. **Nunca por edición directa silenciosa.**

### Donde vive el "panel de carga manual" físicamente

Indefinido en 6B. Puede ser: Sheets con n8n que dispara funciones, un formulario simple en n8n, un panel React futuro, o una pestaña interna de la web pública cuando exista. Lo importante es que **el destino final siempre sea las funciones SQL**, no INSERT directo.

---

## 10. ALCANCE DE LA ETAPA 6B

### Qué entra

- ✅ Schema completo en PostgreSQL (20 tablas, 4 enums, 6 vistas, EXCLUDE constraints).
- ✅ 11 funciones críticas implementadas.
- ✅ 13+ triggers automáticos.
- ✅ pg_cron con 2 jobs.
- ✅ Seed mínimo (5 cabañas, 3 socios, configuración, etc.).
- ✅ Plan de ejecución bloque por bloque con verificación y rollback.
- ✅ 36 tests funcionales y de concurrencia documentados.
- ✅ Entorno Supabase DEV configurado y validado.
- ✅ Documentación sanitizada para GitHub.

### Qué NO entra

- ❌ Entorno de producción (Supabase PROD).
- ❌ Migración real de datos desde Sheets.
- ❌ Web pública.
- ❌ Reescritura de workflows n8n (etapa siguiente: `6B_REESCRITURA_WORKFLOWS.md`).
- ❌ Integración real con MercadoPago.
- ❌ Integración real con WhatsApp / Instagram (DM API).
- ❌ Function `consultar_disponibilidad_precio()`.
- ❌ Migración del motor de precios desde n8n a PostgreSQL.
- ❌ RLS (Row Level Security) habilitado.
- ❌ Supabase Auth.
- ❌ Contabilidad completa (D32: contemplada, no implementada).
- ❌ Tabla de usuarios del sistema (`created_by` queda como TEXT libre).

### Por qué este alcance

El alcance de 6B se eligió para que sea **un trozo terminable en una sesión continua** y que **deje el sistema en un estado verificable** antes de empezar a tocar n8n.

Si se mezclara 6B con la reescritura de n8n, ante cualquier bug sería difícil saber si el problema está en el schema o en los workflows. Separando las dos etapas, primero se valida el schema con tests aislados, y solo cuando ese cierre formal pasa, se empiezan a reescribir workflows contra una base estable.

---

## 11. DOCUMENTOS RELACIONADOS

### Hijos de esta etapa

- **`Docs/Implementacion/6B_SCHEMA_SQL.md v1.5`** — Schema completo, funciones, triggers, vistas, seed. Aprobado.
- **`Docs/Implementacion/6B_PLAN_FASES.md v1.1`** — Plan operativo bloque por bloque, 36 tests, criterios de éxito/freno. Aprobado y sanitizado.
- **`Docs/Implementacion/6B_REESCRITURA_WORKFLOWS.md`** — Futuro. NO existe todavía. Se genera después de cerrar DEV.

### Hijo conceptual (este documento)

- **`Docs/Arquitectura/ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md v1.0`** (este documento) — Visión consolidada de la etapa.

### Padre conceptual

- **`Docs/Arquitectura/ARQUITECTURA_ETAPA_6A_DECISION_MIGRACION.md v1.1`** — Decisión de migrar a Supabase (vs. alternativas). Esta etapa 6B materializa esa decisión.

### Predecesores arquitecturales

- `ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md v1.1` — Modelo de datos consolidado (precursor del schema actual).
- `ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md` — Implementación vertical mínima en Sheets + n8n.
- `ARQUITECTURA_ETAPA_4A_MOTOR_RESERVAS.md` — Motor de reservas determinístico.
- `ARQUITECTURA_ETAPA_4B_BOT_CONVERSACIONAL.md` — Bot conversacional.
- `ARQUITECTURA_ETAPA_3_VITA_DELTA.md` — Motor de precios.
- `ARQUITECTURA_ETAPA_2_VITA_DELTA.md` — Motor de disponibilidad.
- `ARQUITECTURA_ETAPA_1_VITA_DELTA.md` — Arquitectura base.

---

## 12. ESTADO ACTUAL

### Schema aprobado técnicamente

`6B_SCHEMA_SQL.md v1.5` cerró 5 iteraciones quirúrgicas (v1.1 → v1.5) y está en estado "Aprobada para planificación de ejecución en Supabase DEV — NO EJECUTAR SIN PLAN DE FASES".

Las 5 iteraciones cubrieron, en orden: consolidación de 17 ajustes técnicos (v1.1), 9 ajustes operativos (v1.2), 5 ajustes finales antes de ejecutar (v1.3), introducción del lock global de disponibilidad (v1.4), y corrección crítica del orden de locks en `confirmar_reserva` para evitar deadlocks (v1.5).

### Plan de fases aprobado y sanitizado

`6B_PLAN_FASES.md v1.1` está aprobado, sanitizado para GitHub, con:
- 11 secciones operativas.
- 5 fases ordenadas con dependencias claras.
- Tabla detallada de 22 bloques SQL.
- 36 tests obligatorios distribuidos en 8 categorías.
- Rollback documentado por bloque, sin opciones destructivas ciegas.
- Criterios de éxito y de freno explícitos.
- Scope-out claro de lo que NO forma parte de la etapa.

### Arquitectura 6B consolidada

Este documento (`ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md v1.0`) cierra la trilogía de documentos de la etapa: schema (qué), plan (cómo) y arquitectura (por qué).

### Próximo paso

Tres opciones, en orden de preferencia:

1. **Ejecutar Fase 0 → Bloque 1 → bitácora → avance bloque por bloque** en Supabase DEV siguiendo `6B_PLAN_FASES.md v1.1`. Es la opción recomendada.
2. Subir los documentos sanitizados al repo de GitHub si todavía no lo hiciste.
3. (No recomendado) Empezar a redactar `6B_REESCRITURA_WORKFLOWS.md` antes de cerrar DEV. Esto introduce riesgo: si ejecutar el schema revela algo que requiere v1.6, la reescritura quedaría desactualizada antes de empezar.

---

## 13. RIESGOS Y MITIGACIONES

### Errores de ejecución SQL

**Riesgo:** un bloque falla a mitad de camino y deja el schema en estado parcial.

**Mitigación:** cada bloque tiene su rollback documentado en v1.5. El plan de fases (v1.1) exige verificación post-ejecución antes de avanzar. Si algo falla, se detiene la ejecución y se evalúa: rollback de bloque, reset del proyecto (si DEV está vacío), o investigación con bitácora.

### Mala configuración de secrets

**Riesgo:** un Project ID, password o service role key termina commiteado al repo público.

**Mitigación:** los documentos están sanitizados con placeholders. Cualquier nuevo documento futuro debe pasar el mismo check de sanitización antes de subirse. El `.gitignore` del repo debe cubrir `.env`, `.env.local`, archivos de credenciales.

Si por error se sube algo: rotar credenciales inmediatamente en Supabase, hacer `git filter-branch` o `BFG Repo-Cleaner` para borrar del historial, y notificar al equipo.

### Tests de concurrencia fallidos

**Riesgo:** los tests C-1 a C-4 detectan que los locks no están serializando bien, o que aparece deadlock `40P01`.

**Mitigación:** el plan de fases identifica explícitamente estos casos como criterio de freno. Si C-3 falla con deadlock, hay que volver a evaluar el orden de locks en `confirmar_reserva` (que es exactamente el bug que v1.5 corrigió — si reaparece, hay un bug residual). Cualquier falla en concurrencia detiene la ejecución hasta resolverla.

### Dependencia futura de n8n

**Riesgo:** la arquitectura asume que n8n existirá y será el orquestador. Si n8n cambia de versión, se rompe, o decidimos reemplazarlo, las funciones SQL siguen funcionando, pero los workflows tienen que reescribirse.

**Mitigación:** PostgreSQL es la fuente de verdad. n8n es reemplazable. Cualquier orquestador externo (Make, Zapier, un servicio propio, scripts cron) puede llamar a las mismas funciones SQL. La inversión en n8n es transferible.

### Endpoint de precio todavía pendiente

**Riesgo:** lanzar web pública sin `consultar_disponibilidad_precio()` produce inconsistencias entre lo que el cliente ve y lo que el sistema cobra.

**Mitigación:** documentado explícitamente como bloqueador. No se habilita web pública hasta tener ese endpoint. Mientras tanto, n8n calcula precio para canales manuales (WhatsApp, Instagram) sin problema.

### RLS pendiente

**Riesgo:** sin RLS habilitado, cualquiera con el `service role key` puede ver y modificar todo. Si por error ese key se filtra, hay riesgo de exposición de datos.

**Mitigación:**
- El service role key vive solo en n8n credentials y en gestores de contraseñas.
- El anon key (que sí puede exponerse en frontend) no tiene permisos sobre tablas porque las tablas no tienen `GRANT` a `anon` (PostgreSQL deniega por default).
- Cuando exista frontend público, antes de habilitarlo se implementa RLS con policies específicas.

### Migración de datos productivos

**Riesgo:** cuando se migren reservas reales desde Sheets, una mala transformación puede crear pre-reservas/reservas inconsistentes en PostgreSQL.

**Mitigación:** ese paso será una etapa propia con plan específico, no parte de 6B. Probablemente involucre un script de ETL que valide cada fila antes de insertar, y un cierre formal de Sheets como "modo lectura" para evitar drift durante la migración.

### Costos de Supabase

**Riesgo:** al pasar de DEV (free tier) a PROD con uso real, los costos se vuelven relevantes.

**Mitigación:** el tier Pro de Supabase ($25/mes) cubre holgadamente las necesidades de Vita Delta a corto y mediano plazo. El upgrade se hace cuando exista PROD, no antes.

### Pérdida de DEV

**Riesgo:** Supabase suspende un proyecto inactivo o un accidente borra DEV.

**Mitigación:** el schema completo está en `6B_SCHEMA_SQL.md v1.5` versionado en GitHub. Recrear DEV es ejecutar el plan de fases desde Fase 0. El seed mínimo se carga vía Bloque 21. Tiempo total de recreación: 4-6 horas. No se pierde nada irrecuperable.

---

## 14. PRÓXIMO PASO

Plan secuencial recomendado:

1. **Subir documentos sanitizados a GitHub.**
   - `Docs/Implementacion/6B_SCHEMA_SQL.md v1.5` (revisado para sanitización, limpio).
   - `Docs/Implementacion/6B_PLAN_FASES.md v1.1` (sanitizado).
   - `Docs/Arquitectura/ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md v1.0` (este documento).

2. **Ejecutar Fase 0** del plan de fases.
   - Verificar precondiciones (proyecto Supabase DEV creado, extensiones disponibles, credenciales fuera del repo).
   - Smoke test del SQL Editor.
   - NO ejecutar SQL todavía.

3. **Ejecutar Bloque 1** (extensiones).
   - Habilitar `btree_gist` y `pg_cron`.
   - Verificación post-ejecución.

4. **Avanzar bloque por bloque** con bitácora, siguiendo Fases 1 → 2 → 3 → 4 → 5 del plan.

5. **Cerrar DEV** formalmente (Fase 5): "Supabase DEV listo como base de datos operativa".

6. **Recién después, generar `6B_REESCRITURA_WORKFLOWS.md`** para empezar a adaptar n8n a la nueva base de datos. No antes.

Las etapas posteriores (motor de precios en PostgreSQL, web pública, MercadoPago real, contabilidad, RLS, Supabase Auth, migración productiva) tienen cada una su propio plan a definir cuando llegue el momento.

---

**FIN DEL DOCUMENTO — `ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md v1.0`**

**Trazabilidad:**
- v1.0 — Primera redacción consolidada (2026-05-22). Cierra documentalmente la trilogía de la Etapa 6B: schema (v1.5), plan (v1.1) y arquitectura (v1.0). Sanitizado para GitHub desde el inicio.

**Estado:** Arquitectura consolidada — base de datos lista para ejecución.
