# 6C_REESCRITURA_WORKFLOWS_SUPABASE.md

# Reescritura de Workflows n8n contra Supabase DEV — Etapa 6C

**Versión:** 1.2
**Fecha:** Mayo 2026
**Estado:** Aprobado como diseño base de 6C por Franco.
**Documento base:** `6B_SCHEMA_SQL.md v1.7.1`, `ESTADO_VITA_DELTA_ACTUAL.md`, `DECISIONES_NO_REABRIR.md`.
**Entorno objetivo:** Supabase DEV.
**Autores:** Franco (titular) + Claude (arquitecto).

> **Sanitización:** este documento usa placeholders para credenciales. Los valores reales viven fuera del repo (gestor de contraseñas, n8n credentials, `.env` no versionado). Ver Sección 13.

---

## CHANGELOG

### v1.2 — corrección residual

Una corrección menor de consistencia.

1. **Riesgo R7 (Sección 15):** cambiado "Service role key con permisos amplios sin RLS" por "Credencial PostgreSQL técnica con permisos amplios sin RLS". Alinea con la corrección de Sección 6 y Sección 13 ya aplicada en v1.1 (el Postgres node no usa `service_role_key`).

### v1.1 — correcciones de revisión

Cinco ajustes pedidos por Franco sobre v1.0, más dos menciones residuales detectadas en verificación. Cero cambios de diseño.

1. **Sección 6 (canal de invocación):** clarificado que el Postgres node usa una credencial PostgreSQL técnica con permisos amplios, no `service_role_key`. `service_role_key` aplica solo a RPC/HTTP y queda como placeholder futuro.
2. **Sección 4 + W4:** unificadas — 6C **no envía `id_pago`** en `confirmar_reserva()` porque la firma actual de la función no lo acepta. Queda como mejora futura si la ambigüedad aparece en práctica.
3. **W2 test 8 (domingo):** independizado del mini-pendiente v1.7.1. `crear_prereserva()` ya aplica D47 desde v1.7. El mini-pendiente solo afecta lecturas (W1).
4. **Sección 11:** consulta de ejemplo a `log_cambios` ahora ordena por `fecha_hora` (el nombre real del campo), no por `created_at`.
5. **Sección 7 (concurrencia):** suavizada. n8n no necesita `Max Concurrency = 1` por integridad de datos (locks SQL serializan), pero el comportamiento bajo retries/timeouts se valida durante la implementación de 6C, no se asume.
6. **Sección 13:** alineada con la corrección 1 (credencial PostgreSQL, no service_role).
7. **Riesgo R3 (Sección 15):** alineado con la corrección 2 (no recomendar enviar `id_pago` en 6C).

### v1.0 — borrador inicial

Estructura completa, alcance, convenciones, mapa W0–W7, detalles por workflow, errores, logging, tests, riesgos.

---

## ÍNDICE

1. Objetivo y alcance
2. Lo que NO entra en 6C
3. Principios de la integración
4. Inventario legacy y mapeo a workflows nuevos
5. Convenciones globales
6. Canal de invocación n8n → Supabase
7. Patrón común de workflow
8. Matriz de errores por función SQL
9. Mapa de workflows W0–W7
10. Detalle por workflow
11. Logging y observabilidad
12. Tests mínimos por workflow
13. Secrets y credenciales
14. Mini-pendiente previo a W1
15. Riesgos abiertos y supuestos
16. Próximo paso (6D)

---

## 1. OBJETIVO Y ALCANCE

### Objetivo

Reescribir los workflows operativos de n8n para que ejecuten sus operaciones críticas contra **Supabase DEV** invocando las funciones SQL del schema canónico `6B_SCHEMA_SQL.md v1.7.1`, en lugar de Google Sheets.

### Alcance

- 8 workflows nuevos (W0–W7) que cubren: smoke test, consulta de disponibilidad, crear pre-reserva, registrar pago, confirmar reserva, cancelar pre-reserva, crear bloqueo y vistas operativas de lectura.
- Disparadores manuales o internos en n8n (sin canales reales todavía).
- Contratos JSON estables entre n8n y las funciones SQL.
- Manejo de errores controlados y logging.

### Para qué se construye este alcance

Validar el patrón **n8n → payload JSON → función SQL Supabase → respuesta JSONB → manejo de éxito/error → log/bitácora** en condiciones controladas antes de meter IA, frontend o pagos automáticos. Si el patrón funciona acá, los siguientes pasos (canales reales, MercadoPago, web pública) se montan encima sin rediseñar.

---

## 2. LO QUE NO ENTRA EN 6C

Decisiones explícitas de scope-out:

- ❌ Bot conversacional con IA (Claude API).
- ❌ Frontend web público.
- ❌ MercadoPago real (webhook).
- ❌ WhatsApp / Instagram (Meta API).
- ❌ RLS (Row Level Security) y Supabase Auth.
- ❌ Migración de datos productivos desde Sheets.
- ❌ `consultar_disponibilidad_precio()` (función futura, D40).
- ❌ `cancelar_reserva()` y `modificar_reserva()` (funciones futuras).
- ❌ Workflow `db_crear_consulta` reescrito (se difiere a 6D cuando entren canales reales).
- ❌ Workflow autónomo `db_crear_huesped` (la lógica vive embebida en `crear_prereserva()`).
- ❌ Fase 4 exhaustiva de tests de concurrencia (queda como hardening previo a TEST/PROD).
- ❌ Notificaciones operativas a Vicky, Jennifer y socios (vienen después de que los workflows core funcionen).

Lo que sí está dentro del alcance está en la Sección 9 (Mapa de workflows).

---

## 3. PRINCIPIOS DE LA INTEGRACIÓN

Heredados de las etapas cerradas (no se reabren):

1. **Supabase/PostgreSQL es la fuente de verdad.** n8n orquesta y comunica; no decide.
2. **Toda escritura crítica pasa por funciones SQL.** No hay `INSERT`/`UPDATE` directo desde n8n contra `reservas`, `pre_reservas`, `pagos`, `bloqueos` ni `huespedes`.
3. **Las funciones SQL son contratos estables.** Los workflows se adaptan a los payloads y respuestas JSONB definidos por el schema; no replican lógica interna de las funciones.
4. **`source_event` obligatorio.** Toda llamada a función crítica lleva `source_event` para trazabilidad. Sin `source_event`, la función rechaza el payload (excepto consultas read-only).
5. **`idempotency_key` la genera n8n.** Aplica solo a `crear_prereserva()`. Es estable ante retries del mismo evento, distinta ante cambios reales del payload.
6. **Errores controlados como JSONB.** Las funciones devuelven `{ok: false, error: 'codigo'}` para casos esperables. n8n hace `switch(error)` sobre códigos estables, no parseo de texto.
7. **Granularidad: un workflow por función crítica.** No monolitos. Orquestadores y composiciones vienen en 6D.
8. **PostgreSQL es responsable de locks, idempotencia, validaciones y consistencia.** n8n no replica esa lógica.
9. **n8n loguea su propia ejecución.** Supabase loguea el evento de negocio en `log_cambios`. Los dos logs coexisten.
10. **Lecturas vs escrituras.** Vistas y funciones de lectura se consultan sin lock. Escrituras se hacen vía funciones que ya gestionan los locks (`pg_advisory_xact_lock(10, 0)`, `(1, id_cabana)`).

---

## 4. INVENTARIO LEGACY Y MAPEO A WORKFLOWS NUEVOS

### Inventario legacy (Sheets)

| # | Workflow legacy | Versión | Responsabilidad |
|---|---|---|---|
| L1 | `db_recalcular_disponibilidad` | v8 | Regeneraba `DISPONIBILIDAD_CACHE` |
| L2 | `db_crear_consulta` | v3 | Crear/reutilizar consulta de canal |
| L3 | `db_crear_huesped` | v1.1 | Upsert de huésped con dedup |
| L4 | `db_crear_prereserva` | v3 | Pre-reserva con verificación en dos capas |
| L5 | `db_registrar_pago` | v1 | Registrar pago manual |
| L6 | `db_confirmar_reserva` | v1 | Confirmar reserva definitiva |
| — | `sistema_expirar_prereservas` | — | Eliminado: vive ahora en `pg_cron` de Supabase. |

### Mapeo legacy → 6C

| Legacy | Decisión 6C | Función SQL |
|---|---|---|
| L1 `db_recalcular_disponibilidad` | ❌ Desaparece. La cache no existe en Supabase. | — |
| L2 `db_crear_consulta` | ⏭ Se difiere a 6D (sin canal real no tiene disparador natural). | — |
| L3 `db_crear_huesped` | ❌ Desaparece como workflow autónomo. La lógica vive embebida en `crear_prereserva()` vía `upsert_huesped()`. | `upsert_huesped()` (interna) |
| L4 `db_crear_prereserva` v3 | 🔁 Se reemplaza por **W2**. | `crear_prereserva()` |
| L5 `db_registrar_pago` v1 | 🔁 Se reemplaza por **W3**. | `registrar_pago()` |
| L6 `db_confirmar_reserva` v1 | 🔁 Se reemplaza por **W4**. | `confirmar_reserva()` |
| — | ➕ **W0** Smoke test (nuevo) | `SELECT 1` |
| — | ➕ **W1** Consulta de disponibilidad (nuevo) | `obtener_disponibilidad_rango()` |
| — | ➕ **W5** Cancelar pre-reserva (nuevo, sin equivalente legacy) | `cancelar_prereserva()` |
| — | ➕ **W6** Crear bloqueo (nuevo, sin equivalente legacy) | `crear_bloqueo()` |
| — | ➕ **W7** Vistas operativas (nuevo) | Vistas SQL |

### Por qué L1 desaparece

En el legacy, `DISPONIBILIDAD_CACHE` era una tabla derivada de 300 filas (5 cabañas × 60 días) que había que regenerar manualmente con cada cambio. En Supabase, esa cache no existe:

- `obtener_disponibilidad_rango()` calcula al vuelo.
- Vistas (`vista_disponibilidad`, `vista_calendario`, `vista_calendario_semanal`, `vista_limpieza_semana`) siempre frescas.
- Constraint `EXCLUDE` estructural impide double-booking.
- `pg_cron` corre `expirar_prereservas_vencidas()` cada 5 minutos.

**Impacto colateral:** los 3 workflows legacy que llamaban a `db_recalcular_disponibilidad` como subworkflow al final (L4, L5, L6) **pierden ese paso por completo**. No se reemplaza por otro nodo. El `recalculo_cache: "ok"|"warning"` del output legacy ya no existe.

### Diferencia operativa conocida — `confirmar_reserva`

| Aspecto | Legacy L6 (Sheets) | Supabase actual |
|---|---|---|
| Múltiples pagos en revisión | Detectaba `pago_duplicado_ambiguo` si había >1 sin `id_pago` específico. | `confirmar_reserva()` toma el más reciente: `ORDER BY created_at DESC LIMIT 1`. |

**Decisión 6C:** se acepta el comportamiento actual del schema. No se modifica `confirmar_reserva()`. **W4 no envía `id_pago` explícito porque la firma actual de la función no acepta ese parámetro**: la selección del pago la hace internamente la función SQL. Si en la práctica aparecen casos reales de ambigüedad (múltiples pagos en revisión sobre la misma pre-reserva y el operador necesita decidir cuál usar), se registra como mejora futura posible de `confirmar_reserva()` y se discute fuera de 6C.

---

## 5. CONVENCIONES GLOBALES

### 5.1 Naming de workflows en n8n

Formato: `vita_w{NN}_{nombre}_supabase`.

Ejemplos:
- `vita_w00_smoke_test_supabase`
- `vita_w02_crear_prereserva_supabase`
- `vita_w04_confirmar_reserva_supabase`

El prefijo `vita_` separa de cualquier workflow legacy que conviva durante la transición. El sufijo `_supabase` evita confusión con workflows legacy si quedan activos en n8n apuntando a Sheets.

### 5.2 `source_event`

Obligatorio en todo workflow que llame a función crítica.

Formato: `n8n_{wNN}_{nombre_corto}_{disparador}`.

Ejemplos:
- `n8n_w02_crear_prereserva_manual`
- `n8n_w03_registrar_pago_manual`
- `n8n_w04_confirmar_reserva_estricto`
- `n8n_w04_confirmar_reserva_combinado`

Cuando lleguen los canales reales (6D), `disparador` pasará a ser `whatsapp`, `instagram`, `mp_webhook`, etc.

### 5.3 `idempotency_key`

Aplica **solo a `crear_prereserva`**. Las demás funciones críticas no consumen este campo (su idempotencia se resuelve por estado: `confirmar_reserva` rechaza si la pre-reserva ya no está en `pendiente_pago`/`pago_en_revision`; `cancelar_prereserva` idem; `registrar_pago` permite múltiples pagos por diseño).

Formato: `{canal}_{id_evento_o_uuid}_{id_cabana}_{fecha_in}_{fecha_out}`.

Ejemplo:
```
manual_2026-05-25T12:00:00Z_17_2026-06-10_2026-06-12
```

Regla: estable ante retries del mismo evento, distinta ante cambios reales del payload (cabaña, fechas).

**Por qué incluye `id_cabana` + `fecha_in` + `fecha_out`:** si un mismo `id_evento` reintenta con cabaña o fechas distintas (cliente cambió de idea), debe ser una pre-reserva diferente, no un match idempotente.

### 5.4 Naming de payloads y respuestas

Todo workflow tiene tres "estaciones" obligatorias:

| Estación | Nombre del nodo n8n | Propósito |
|---|---|---|
| Input | `Parse Input` | Validar y normalizar el input del trigger. |
| Payload | `Build Payload` | Armar el JSONB que recibe la función SQL. |
| Llamada | `Call <nombre_funcion>` | Postgres node con `SELECT funcion(:payload::jsonb)`. |
| Branch | `Switch on ok/error` | Bifurca según `ok=true|false` y código de error. |
| Respuesta | `Build Response` | Arma el output del workflow para el caller. |

### 5.5 Fechas, montos, booleanos

- Fechas: `YYYY-MM-DD` (DATE).
- Timestamps: ISO 8601 UTC con `Z` (`2026-06-15T14:30:00Z`).
- Montos: número decimal con 2 decimales (no string).
- Booleanos: `true`/`false` JSON nativo.
- Strings vacíos: enviar `null`, no `""`.

### 5.6 Convención de respuesta del workflow

Todo workflow devuelve al caller un JSON con esta forma mínima:

```json
{
  "ok": true|false,
  "workflow": "vita_w02_crear_prereserva_supabase",
  "source_event": "n8n_w02_crear_prereserva_manual",
  "result": { ...respuesta de la función SQL... },
  "error": null | { "code": "...", "message": "...", "details": {...} },
  "executed_at": "2026-05-25T14:30:00Z"
}
```

---

## 6. CANAL DE INVOCACIÓN n8n → SUPABASE

### Decisión

**Postgres node** de n8n contra Supabase DEV, autenticándose con una **credencial PostgreSQL técnica de DEV con permisos amplios**, guardada en n8n credentials.

### Aclaración sobre `service_role_key`

`service_role_key` aplica al canal **HTTP/REST/RPC** de Supabase (PostgREST), no al Postgres node nativo. El Postgres node abre una conexión PostgreSQL directa al pooler y autentica con usuario y password de base. **No usa el `service_role_key`.**

El `service_role_key` queda como placeholder futuro únicamente si más adelante se decide invocar funciones por RPC/HTTP.

### Justificación de usar Postgres node

- Permite invocar funciones directamente con `SELECT funcion(:payload::jsonb)`.
- El contrato JSONB → JSONB se mapea naturalmente.
- Menos overhead que REST: una conexión, una query, una respuesta.
- Más fácil de debuggear (logs SQL directos, EXPLAIN si hace falta).

### Por qué no REST/RPC todavía

Supabase expone funciones vía `POST /rest/v1/rpc/{nombre_funcion}` con `Authorization: Bearer <service_role_key>`. Es válido y portable, pero:

- Agrega una capa HTTP innecesaria para 6C.
- Las respuestas se serializan a JSON con reglas de PostgREST que no siempre coinciden 1:1 con JSONB nativo.
- Cuando llegue la web pública (que usará `anon` key + RLS), ahí sí RPC será el canal natural.

**Postponer la decisión RPC hasta que aparezca un caller no-n8n** (web, edge function, app móvil).

### Connection string

Vive solo en n8n credentials. Nunca en payloads, nunca en repo. La credencial PostgreSQL se configura como connection string apuntando al pooler de Supabase:

```
postgresql://postgres.__SUPABASE_PROJECT_ID_DEV__:__SUPABASE_DB_PASSWORD__@aws-0-sa-east-1.pooler.supabase.com:6543/postgres
```

Notas técnicas:
- Usar el **pooler** (`:6543`) y no la conexión directa (`:5432`). El pooler maneja mejor las conexiones cortas que n8n genera por ejecución.
- Mode: `transaction` (default del pooler).
- SSL: requerido (`sslmode=require`). Supabase lo fuerza.

### Patrón de la query

Todas las llamadas a función crítica usan parameter binding, **no concatenación de strings**:

```sql
SELECT crear_prereserva($1::jsonb) AS resultado;
```

En n8n, el Postgres node recibe el payload como parámetro posicional o nombrado (según versión de n8n). Esto evita inyección SQL incluso si el payload trae strings raros.

**Anti-patrón explícito:**

```sql
-- NO HACER
SELECT crear_prereserva('{{ JSON.stringify($json.payload) }}'::jsonb);
```

---

## 7. PATRÓN COMÚN DE WORKFLOW

Todos los workflows W2–W6 siguen la misma estructura. Cambia el payload, la función SQL y los errores manejados.

```
[Trigger Manual]
      ↓
[Code: Parse Input]
   - Lee input del trigger
   - Valida campos obligatorios a nivel n8n (defensivo, no reemplaza validación SQL)
   - Genera idempotency_key si aplica
   - Compone source_event
      ↓
[Code: Build Payload]
   - Arma el JSONB exacto que espera la función SQL
   - Filtra campos vacíos a null
      ↓
[Postgres: Call <funcion>]
   - SELECT funcion($1::jsonb) AS resultado
   - Bind del payload como parámetro
      ↓
[Code: Parse Result]
   - Extrae result.ok
   - Si ok=false, extrae result.error y result.motivo
      ↓
[Switch: ok vs error]
   ├─ ok=true  → [Build Response success]
   └─ ok=false → [Switch: por código de error]
                  ├─ huesped_nombre_requerido → ...
                  ├─ no_disponible            → ...
                  ├─ etc.
                  └─ default                  → [Build Response generic_error]
      ↓
[Build Response]
      ↓
[Respond to Webhook / Return]
```

### Side-effects post-éxito

n8n **no tiene transacción** con Supabase. Una vez que la función SQL hizo COMMIT, lo que pase en n8n después (notificaciones, logs externos, llamadas a otros servicios) es **side-effect no transaccional**.

Implicación: si una notificación de WhatsApp falla después de `confirmar_reserva()` OK, la reserva ya está creada en Supabase. **Esto es correcto** — PostgreSQL es la fuente de verdad. Los side-effects que fallan se reintentan o se reportan operativamente.

### Concurrencia n8n

- W2 (`crear_prereserva`): no requiere `Max Concurrency = 1` por integridad de datos. Los advisory locks de Supabase serializan internamente.
- W3 (`registrar_pago`): no toma lock global, no requiere concurrency 1 por integridad.
- W4 (`confirmar_reserva`): no requiere concurrency 1 por integridad. Locks SQL serializan.
- W5 (`cancelar_prereserva`): idem.
- W6 (`crear_bloqueo`): idem.

**Diferencia vs legacy:** los workflows legacy en Sheets necesitaban `Max Concurrency = 1` porque Sheets no tiene transacciones ni locks. En Supabase, la serialización es responsabilidad del schema. **n8n no necesita `Max Concurrency = 1` por integridad de datos.**

**Validación pendiente en 6C:** durante la implementación de los workflows se validará el comportamiento bajo retries y timeouts (qué pasa si n8n reintenta una llamada que la base ya commiteó pero cuya respuesta no llegó a n8n). El comportamiento esperado:

- En `crear_prereserva`: la `idempotency_key` resuelve el retry devolviendo la pre-reserva original con `idempotent_match=true`.
- En el resto: el segundo retry recibe un error controlado (`estado_invalido`, `estado_no_cancelable`, etc.) que el workflow debe tratar como "ya estaba hecho", no como fallo.

Si en esa validación aparece algún caso que el schema no cubre limpiamente, se documenta y se decide si activar concurrencia 1 puntualmente como mitigación temporal o ajustar el workflow.

---

## 8. MATRIZ DE ERRORES POR FUNCIÓN SQL

Códigos estables que n8n debe poder reconocer. Tomados de `6B_SCHEMA_SQL.md v1.7.1`.

### `crear_prereserva()`

| Código | Significado | Acción n8n |
|---|---|---|
| `payload_invalido` | Falta campo obligatorio. | Devolver al caller como error de validación. |
| `huesped_requerido` | Falta objeto `huesped` en payload. | Idem. |
| `huesped_nombre_requerido` | `huesped.nombre` vacío o ausente. | Idem. |
| `huesped_contacto_requerido` | Sin teléfono ni email. | Idem. |
| `precio_requerido` | `monto_total` o `monto_sena` ausentes. | Idem. Indicar que falta calcular precio. |
| `montos_invalidos` | `monto_total <= 0` o `monto_sena < 0` o `monto_sena > monto_total`. | Devolver error. |
| `fechas_invalidas` | `fecha_out <= fecha_in`. | Idem. |
| `cabana_no_existe` | `id_cabana` no está en `cabanas`. | Idem. |
| `excede_capacidad` | `personas > capacidad_max`. | Idem. |
| `hora_fuera_de_rango` | Hora elegida fuera de margen permitido. | Devolver con `minimo` y `maximo` para que el caller corrija. |
| `no_disponible` | Conflicto con reserva/pre-reserva/bloqueo existente. | Devolver al caller. **No reintentar.** |

| Caso especial | Significado | Acción n8n |
|---|---|---|
| `ok=true, idempotent_match=true` | Idempotency hit (3 caminos: `pre_lock`, `post_lock`, `unique_violation`). | Devolver al caller como éxito normal. La `id_pre_reserva` es la original. |

### `confirmar_reserva()`

| Código | Significado | Acción n8n |
|---|---|---|
| `payload_invalido` | Falta `id_pre_reserva` o `source_event`. | Error de validación. |
| `prereserva_no_existe` | `id_pre_reserva` no existe. | Idem. |
| `estado_invalido` | Pre-reserva no está en `pendiente_pago` ni `pago_en_revision`. Devuelve `estado_actual`. | Idem. Caso típico: ya está `convertida`. |
| `sin_pago_asociado` | Camino combinado: no hay pago en revisión asociado. | Idem. |
| `sin_pago_confirmado` | Camino estricto: no hay pago confirmado y no se permitió usar pago en revisión. | Idem. |
| `conflicto_al_confirmar` | Apareció bloqueo/reserva entre la pre-reserva y la confirmación. Devuelve `conflictos`. | **Alertar operativamente.** La pre-reserva queda en `conflicto_pendiente`. |

### `cancelar_prereserva()`

| Código | Significado | Acción n8n |
|---|---|---|
| `payload_invalido` | Falta campo. | Error de validación. |
| `motivo_invalido` | Motivo no es `cliente` ni `bloqueo`. | Idem. |
| `prereserva_no_existe` | ID inexistente. | Idem. |
| `estado_no_cancelable` | Pre-reserva ya está en estado terminal. | Idem. |

### `registrar_pago()`

| Código | Significado | Acción n8n |
|---|---|---|
| `referencia_requerida` | No vino `id_pre_reserva` ni `id_reserva`. | Error de validación. |
| `payload_invalido` | Falta campo obligatorio. | Idem. |
| `prereserva_no_existe` | Idem. | Idem. |
| `reserva_no_existe` | Idem. | Idem. |

| Caso especial | Significado | Acción n8n |
|---|---|---|
| `ok=true, warning='prereserva_no_activa'` | Pago registrado pero la pre-reserva está en estado terminal (vencida/cancelada/conflicto). Forzado a `en_revision`. | **Devolver al caller con flag de aviso.** Operativamente revisar. |

### `crear_bloqueo()`

| Código | Significado | Acción n8n |
|---|---|---|
| `payload_invalido` | Falta campo. | Error de validación. |
| `fechas_invalidas` | `fecha_hasta <= fecha_desde`. | Idem. |
| `motivo_invalido` | Motivo fuera de lista. | Idem. |
| `conflicto_con_reserva` | Hay reserva confirmada/activa solapando. Devuelve IDs. | **Operativamente revisar.** |
| `conflicto_con_prereserva` | Hay pre-reserva vigente solapando. Devuelve IDs. | Idem. |
| `bloqueo_solapado` | Hay bloqueo activo solapando. Devuelve IDs. | Idem. |

### `obtener_disponibilidad_rango()`

Función de lectura. Devuelve `SETOF` (set de filas), no JSONB con `ok`. Errores típicos: parámetros inválidos al castear DATE/BIGINT, que aparecen como excepciones de PostgreSQL.

W1 debe normalizar la respuesta a JSON estructurado y manejar excepciones como `error_postgres` genérico.

---

## 9. MAPA DE WORKFLOWS W0–W7

| ID | Nombre | Función SQL | Tipo | Idempotency | Concurrencia n8n |
|---|---|---|---|---|---|
| W0 | Smoke test | `SELECT 1` | Lectura | — | Libre |
| W1 | Consultar disponibilidad | `obtener_disponibilidad_rango()` + vistas | Lectura | — | Libre |
| W2 | Crear pre-reserva | `crear_prereserva()` | Escritura | Sí (clave generada por n8n) | Libre (SQL serializa) |
| W3 | Registrar pago | `registrar_pago()` | Escritura | No | Libre |
| W4 | Confirmar reserva | `confirmar_reserva()` | Escritura | No | Libre (SQL serializa) |
| W5 | Cancelar pre-reserva | `cancelar_prereserva()` | Escritura | No | Libre (SQL serializa) |
| W6 | Crear bloqueo | `crear_bloqueo()` | Escritura | No | Libre (SQL serializa) |
| W7 | Vistas operativas | Vistas SQL | Lectura | — | Libre |

Orden de implementación: W0 → W1 → W2 → W3 → W4 → W5 → W6 → W7.

---

## 10. DETALLE POR WORKFLOW

### W0 — Smoke test n8n ↔ Supabase

**Propósito:** validar conexión, credentials, latencia y formato de respuesta antes de cualquier otro workflow.

**Trigger:** Manual.

**Input:** ninguno.

**Función SQL:** `SELECT 1 AS ok, NOW() AS server_time, current_database() AS db;`

**Output esperado:**

```json
{
  "ok": true,
  "workflow": "vita_w00_smoke_test_supabase",
  "result": {
    "ok": 1,
    "server_time": "2026-05-25T14:30:00.123Z",
    "db": "postgres"
  },
  "executed_at": "2026-05-25T14:30:00Z"
}
```

**Criterio de éxito:** ejecuta en < 1s y devuelve `result.ok = 1`.

**Criterio de freno:** error de conexión, timeout, SSL fail, credential inválida. Resolver antes de pasar a W1.

**Tests mínimos:** uno solo, el happy path.

---

### W1 — Consultar disponibilidad

**Propósito:** lectura de disponibilidad por rango y cabaña. Read-only. Base para los siguientes workflows.

**Trigger:** Manual con payload editable.

**Input:**

```json
{
  "fecha_desde": "2026-06-01",
  "fecha_hasta": "2026-06-30",
  "id_cabana": 17,
  "source_event": "n8n_w01_consultar_disponibilidad_manual"
}
```

| Campo | Tipo | Obligatorio | Notas |
|---|---|---|---|
| `fecha_desde` | DATE | Sí | Inclusive. |
| `fecha_hasta` | DATE | Sí | Exclusive. |
| `id_cabana` | BIGINT | No | Si null, devuelve todas las cabañas. |
| `source_event` | TEXT | Sí | Auditoría. |

**Función SQL:**

```sql
SELECT * FROM obtener_disponibilidad_rango(
  ($1->>'fecha_desde')::DATE,
  ($1->>'fecha_hasta')::DATE,
  NULLIF($1->>'id_cabana', '')::BIGINT
);
```

**Output esperado (estructurado por n8n):**

```json
{
  "ok": true,
  "workflow": "vita_w01_consultar_disponibilidad_supabase",
  "result": {
    "rango": { "fecha_desde": "2026-06-01", "fecha_hasta": "2026-06-30" },
    "id_cabana": 17,
    "total_dias": 30,
    "dias": [
      {
        "fecha": "2026-06-01",
        "id_cabana": 17,
        "disponible": true,
        "hora_checkin_base": "13:00",
        "hora_checkout_base": "10:00",
        "tipo_dia": "semana",
        "es_feriado": false
      }
    ]
  }
}
```

**Notas:**
- Después del mini-pendiente (Sección 14), `hora_checkout_base` devolverá `16:00` los domingos. Hasta entonces, los domingos en DEV devuelven `10:00` aunque la regla operativa real sea 16:00. **W1 no debe enmascarar este sesgo** — devolver lo que la función SQL diga.
- Para volumen grande (rangos largos × muchas cabañas), considerar paginación en una futura iteración. Para 6C no es necesario.

**Tests mínimos:**

| # | Caso | Esperado |
|---|---|---|
| 1 | Rango válido, una cabaña | Lista de días con disponibilidad |
| 2 | Rango válido, sin `id_cabana` | Días × todas las cabañas |
| 3 | Rango inválido (`fecha_hasta < fecha_desde`) | Error de PostgreSQL o respuesta vacía (verificar comportamiento real de la función) |
| 4 | Cabaña inexistente | Respuesta vacía o error controlado |

---

### W2 — Crear pre-reserva

**Propósito:** crear pre-reserva temporal con bloqueo de disponibilidad.

**Trigger:** Manual con payload editable. En 6D pasará a trigger desde bot/webhook.

**Input al trigger (entrada n8n):**

```json
{
  "canal_origen": "manual",
  "id_evento": "test-2026-05-25-001",
  "huesped": {
    "nombre": "Juan",
    "apellido": "Pérez",
    "telefono": "+5491112345678",
    "email": "juan@example.com",
    "canal_preferido": "whatsapp"
  },
  "id_cabana": 17,
  "fecha_in": "2026-06-10",
  "fecha_out": "2026-06-12",
  "personas": 2,
  "mascotas": false,
  "ninos": null,
  "monto_total": 100000,
  "monto_sena": 50000,
  "canal_pago_esperado": "transferencia_mp",
  "hora_checkin_solicitada": null,
  "hora_checkout_solicitada": null,
  "notas_reserva": null
}
```

**Payload JSONB construido por n8n (lo que recibe `crear_prereserva()`):**

```json
{
  "huesped": {
    "nombre": "Juan",
    "apellido": "Pérez",
    "telefono": "+5491112345678",
    "email": "juan@example.com",
    "canal_preferido": "whatsapp"
  },
  "id_cabana": 17,
  "fecha_in": "2026-06-10",
  "fecha_out": "2026-06-12",
  "personas": 2,
  "mascotas": false,
  "ninos": null,
  "monto_total": 100000,
  "monto_sena": 50000,
  "canal_origen": "manual",
  "canal_pago_esperado": "transferencia_mp",
  "hora_checkin_solicitada": null,
  "hora_checkout_solicitada": null,
  "notas_reserva": null,
  "source_event": "n8n_w02_crear_prereserva_manual",
  "idempotency_key": "manual_test-2026-05-25-001_17_2026-06-10_2026-06-12"
}
```

**Función SQL:** `crear_prereserva($1::jsonb)`.

**Output happy path:**

```json
{
  "ok": true,
  "workflow": "vita_w02_crear_prereserva_supabase",
  "result": {
    "ok": true,
    "idempotent_match": false,
    "id_pre_reserva": 42,
    "id_huesped": 18,
    "estado": "pendiente_pago",
    "expira_en": "2026-05-25T15:30:00Z",
    "hora_checkin": "13:00",
    "hora_checkout": "10:00",
    "recovery_path": null
  }
}
```

**Output idempotency hit:**

```json
{
  "ok": true,
  "result": {
    "ok": true,
    "idempotent_match": true,
    "id_pre_reserva": 42,
    "recovery_path": "pre_lock"
  }
}
```

`recovery_path` puede ser `pre_lock`, `post_lock` o `unique_violation`. n8n trata los tres igual: éxito con `idempotent_match=true`.

**Errores que W2 debe manejar:** ver matriz Sección 8. Especial atención a `no_disponible` (devolver al caller, no reintentar) y `hora_fuera_de_rango` (devolver `minimo` y `maximo` al caller).

**Tests mínimos:**

| # | Caso | Esperado |
|---|---|---|
| 1 | Pre-reserva exitosa en fecha libre | `ok=true`, `id_pre_reserva` numérico, `expira_en` futuro |
| 2 | Misma `idempotency_key` dos veces | Segunda llamada `idempotent_match=true`, mismo `id_pre_reserva` |
| 3 | `fecha_out <= fecha_in` | `error: fechas_invalidas` |
| 4 | `personas` > capacidad cabaña | `error: excede_capacidad` |
| 5 | Cabaña inexistente | `error: cabana_no_existe` |
| 6 | Sin `huesped.nombre` | `error: huesped_nombre_requerido` |
| 7 | Conflicto con pre-reserva existente | `error: no_disponible` |
| 8 | Domingo como `fecha_out` | `hora_checkout: '16:00'` (regla D47 ya aplicada en `crear_prereserva()` desde v1.7, independiente del mini-pendiente v1.7.1 que solo afecta lecturas) |

---

### W3 — Registrar pago

**Propósito:** registrar pago manual (cliente reportó pago, Vicky lo carga) sobre pre-reserva o reserva existente.

**Trigger:** Manual con payload editable. En 6D, pasará a webhook de MercadoPago para automatización.

**Input:**

```json
{
  "id_pre_reserva": 42,
  "id_reserva": null,
  "tipo": "sena",
  "medio_pago": "transferencia_mp",
  "monto_esperado": 50000,
  "monto_recibido": 50000,
  "moneda": "ARS",
  "es_automatico": false,
  "estado_inicial": "en_revision",
  "comprobante_url": "https://...",
  "referencia_externa": "MP-12345",
  "validado_por": null,
  "notas": "Pago de seña reportado por cliente"
}
```

**Payload JSONB:** se completa con `source_event = "n8n_w03_registrar_pago_manual"`.

**Función SQL:** `registrar_pago($1::jsonb)`.

**Output happy path:**

```json
{
  "ok": true,
  "result": {
    "ok": true,
    "id_pago": 87,
    "estado_pago": "en_revision",
    "warning": null
  }
}
```

**Output con warning (caso v1.3):**

```json
{
  "ok": true,
  "result": {
    "ok": true,
    "id_pago": 88,
    "estado_pago": "en_revision",
    "warning": "prereserva_no_activa",
    "motivo": "La pre-reserva está en estado terminal; el pago se forzó a en_revision."
  }
}
```

**Notas operativas:**
- `monto_recibido` puede ser distinto de `monto_esperado`. La función no falla por eso. Operativamente, el operador revisa al validar.
- Si `estado_inicial = 'confirmado'` Y `monto_recibido = monto_esperado`, la función promueve el pago a `confirmado` automáticamente y la pre-reserva pasa a `pago_en_revision`. Camino útil para futuro webhook MP.

**Tests mínimos:**

| # | Caso | Esperado |
|---|---|---|
| 1 | Pago en revisión sobre pre-reserva activa | `estado_pago='en_revision'`, pre-reserva pasa a `pago_en_revision` |
| 2 | Pago confirmado automático (montos iguales + `estado_inicial=confirmado`) | `estado_pago='confirmado'` |
| 3 | Pago sobre pre-reserva vencida | `warning='prereserva_no_activa'`, pago en `en_revision` |
| 4 | Sin `id_pre_reserva` ni `id_reserva` | `error: referencia_requerida` |
| 5 | Pre-reserva inexistente | `error: prereserva_no_existe` |
| 6 | `monto_recibido != monto_esperado` | OK, queda en `en_revision` para validación manual |

---

### W4 — Confirmar reserva

**Propósito:** convertir pre-reserva con pago en reserva confirmada.

**Trigger:** Manual con payload editable. En 6D, pasará a webhook MP o disparo desde panel operativo.

**Input — camino estricto:**

```json
{
  "id_pre_reserva": 42,
  "permitir_pago_en_revision": false,
  "encargado_semana": "Rodrigo"
}
```

**Input — camino combinado (validación humana):**

```json
{
  "id_pre_reserva": 42,
  "permitir_pago_en_revision": true,
  "validado_por": "Vicky",
  "encargado_semana": "Rodrigo"
}
```

**Payload JSONB:** se completa con `source_event = "n8n_w04_confirmar_reserva_estricto"` o `..._combinado`.

**Función SQL:** `confirmar_reserva($1::jsonb)`.

**Output happy path:**

```json
{
  "ok": true,
  "result": {
    "ok": true,
    "id_reserva": 91,
    "id_pre_reserva": 42
  }
}
```

**Manejo de `conflicto_al_confirmar`:** caso operativamente crítico. Significa que entre la pre-reserva y la confirmación apareció un bloqueo o una reserva en las mismas fechas. La pre-reserva queda en `conflicto_pendiente` y requiere intervención humana.

```json
{
  "ok": false,
  "error": {
    "code": "conflicto_al_confirmar",
    "details": { "conflictos": [...] }
  }
}
```

n8n debe **alertar operativamente** este caso (en 6D, vía notificación a Vicky/socios; en 6C, basta con dejarlo en el output).

**Diferencia operativa documentada (Sección 4):** si hay múltiples pagos en revisión asociados a la misma pre-reserva, `confirmar_reserva()` toma el más reciente. **En 6C W4 no envía `id_pago`** porque la firma actual de la función no acepta ese parámetro; la selección del pago la hace internamente la función SQL. Si esto resulta ambiguo en la práctica, se evalúa como mejora futura de la función (fuera de 6C).

> **Nota de seguimiento (no acción para 6C):** si la ambigüedad de pagos aparece como problema real en producción operativa, considerar agregar `id_pago` opcional al payload de `confirmar_reserva()`. Queda como issue para evaluación posterior, no como compromiso.

**Tests mínimos:**

| # | Caso | Esperado |
|---|---|---|
| 1 | Camino estricto, pago confirmado | `ok=true`, reserva creada |
| 2 | Camino combinado, pago en revisión + validado_por | `ok=true`, pago promovido a confirmado en la misma transacción |
| 3 | Camino estricto, solo pago en revisión | `error: sin_pago_confirmado` |
| 4 | Pre-reserva ya convertida | `error: estado_invalido, estado_actual: convertida` |
| 5 | Aparición de conflicto entre pre-reserva y confirmación | `error: conflicto_al_confirmar`, pre-reserva queda en `conflicto_pendiente` |

---

### W5 — Cancelar pre-reserva

**Propósito:** cancelar una pre-reserva con motivo.

**Trigger:** Manual.

**Input:**

```json
{
  "id_pre_reserva": 42,
  "motivo": "cliente",
  "descripcion": "Cliente cambió de fechas"
}
```

| Campo | Valores válidos |
|---|---|
| `motivo` | `cliente` o `bloqueo` |

**Payload JSONB:** se completa con `source_event = "n8n_w05_cancelar_prereserva_manual"`.

**Función SQL:** `cancelar_prereserva($1::jsonb)`.

**Output happy path:**

```json
{
  "ok": true,
  "result": {
    "ok": true,
    "id_pre_reserva": 42,
    "estado_anterior": "pendiente_pago",
    "estado_nuevo": "cancelada_por_cliente",
    "pagos_asociados_count": 0,
    "pagos_asociados_ids": []
  }
}
```

**Nota importante:** la función **NO toca los pagos**. Si hay pagos asociados, los devuelve como info para que los humanos decidan (reembolso, reasignación). Esto es decisión cerrada del schema (no reabrir).

**Tests mínimos:**

| # | Caso | Esperado |
|---|---|---|
| 1 | Cancelación normal por cliente | `estado_nuevo='cancelada_por_cliente'` |
| 2 | Cancelación por bloqueo | `estado_nuevo='cancelada_por_bloqueo'` |
| 3 | Motivo inválido | `error: motivo_invalido` |
| 4 | Pre-reserva ya cancelada | `error: estado_no_cancelable` |
| 5 | Pre-reserva con pago asociado | `ok=true`, `pagos_asociados_count > 0` con IDs |

---

### W6 — Crear bloqueo

**Propósito:** crear bloqueo de cabaña específica o total (todas las cabañas).

**Trigger:** Manual.

**Input — bloqueo específico:**

```json
{
  "id_cabana": 17,
  "fecha_desde": "2026-07-01",
  "fecha_hasta": "2026-07-05",
  "motivo": "mantenimiento",
  "descripcion": "Pintura exterior",
  "creado_por": "Franco"
}
```

**Input — bloqueo total:**

```json
{
  "id_cabana": null,
  "fecha_desde": "2027-01-01",
  "fecha_hasta": "2027-01-02",
  "motivo": "uso_propio",
  "descripcion": "Año Nuevo familiar",
  "creado_por": "Franco"
}
```

| Campo | Valores válidos para `motivo` |
|---|---|
| `motivo` | `mantenimiento`, `uso_propio`, `tormenta`, `overbooking`, `otro` |

**Payload JSONB:** se completa con `source_event = "n8n_w06_crear_bloqueo_manual"`.

**Función SQL:** `crear_bloqueo($1::jsonb)`.

**Output happy path:**

```json
{
  "ok": true,
  "result": {
    "ok": true,
    "id_bloqueo": 12,
    "tipo_bloqueo": "especifico"
  }
}
```

`tipo_bloqueo` puede ser `"especifico"` o `"total"`.

**Manejo de conflictos:** los tres errores (`conflicto_con_reserva`, `conflicto_con_prereserva`, `bloqueo_solapado`) devuelven lista de IDs conflictivos. n8n los pasa al caller para decisión humana.

**Tests mínimos:**

| # | Caso | Esperado |
|---|---|---|
| 1 | Bloqueo específico sin conflictos | `ok=true`, `tipo_bloqueo='especifico'` |
| 2 | Bloqueo total sin conflictos | `ok=true`, `tipo_bloqueo='total'` |
| 3 | Bloqueo específico con reserva confirmada en el rango | `error: conflicto_con_reserva` con IDs |
| 4 | Bloqueo total con pre-reserva vigente | `error: conflicto_con_prereserva` con IDs |
| 5 | Motivo inválido | `error: motivo_invalido` |
| 6 | `fecha_hasta <= fecha_desde` | `error: fechas_invalidas` |

---

### W7 — Vistas operativas

**Propósito:** workflows de lectura para uso operativo. Read-only.

**Subworkflows propuestos** (cada uno se diseña por separado al implementar):

#### W7a — Calendario semanal

- Lee: `vista_calendario_semanal`.
- Audiencia: Vicky, socios.
- Disparador 6C: manual. Disparador 6D: notificación periódica.

#### W7b — Limpieza de la semana

- Lee: `vista_limpieza_semana`.
- Audiencia: Jennifer.
- Disparador 6C: manual.

#### W7c — Pre-reservas activas (cronómetro)

- Lee: `vista_prereservas_activas`.
- Audiencia: Vicky (para ver qué expira pronto).
- Disparador 6C: manual.

**Estructura común:** Postgres node con `SELECT * FROM vista_xxx`, transformación a JSON estructurado, output. Sin payload JSONB porque son vistas.

**Tests mínimos:** uno por subworkflow. Verificar que la respuesta tiene la forma esperada y que los datos coinciden con lo que muestra Supabase directamente.

> **Nota de granularidad:** si al implementar W7 conviene mantenerlo como un único workflow con un parámetro de tipo de vista, está bien. La división en W7a/b/c es orientativa según audiencia.

---

## 11. LOGGING Y OBSERVABILIDAD

### Doble capa de logging

| Capa | Quién logguea | Dónde | Qué |
|---|---|---|---|
| 1. Supabase | Las funciones SQL + triggers automáticos | `log_cambios` | Eventos de negocio + transiciones de estado |
| 2. n8n | El workflow propio | Executions de n8n | Ejecución del workflow: input, output, errores, latencia |

Esto es exactamente lo aceptado en `DECISIONES_NO_REABRIR.md` (doble log validado). No es duplicación errónea.

### `source_event` como hilo de correlación

El campo `source_event` que n8n envía en cada llamada queda en `log_cambios.source_event`. Esto permite buscar **todos los eventos de negocio relacionados a una ejecución específica de n8n**:

```sql
SELECT * FROM log_cambios WHERE source_event = 'n8n_w02_crear_prereserva_manual' ORDER BY fecha_hora;
```

Y en n8n, el `source_event` queda en el output del workflow (Sección 5.6), accesible desde Executions.

### Recomendación operativa

Para 6C, no construir un dashboard ni alerting automático. Es prematuro. Basta con:

- n8n Executions panel para ver ejecuciones recientes.
- Supabase SQL Editor para consultar `log_cambios` por `source_event` cuando haga falta.

En 6D, si los workflows se disparan automáticamente desde canales reales, evaluar:
- Tabla `n8n_workflow_runs` propia (resumen de cada ejecución).
- Alerting sobre errores frecuentes vía Slack/email.

**No incluir esto en 6C.**

---

## 12. TESTS MÍNIMOS POR WORKFLOW

Cada workflow tiene su propio bloque de tests en la Sección 10. Patrón común:

| # | Tipo | Propósito |
|---|---|---|
| Test 1 | Happy path | Validar el contrato JSON en condiciones ideales |
| Test 2 | Payload inválido | Verificar manejo de error de validación |
| Test 3+ | Errores de negocio | Verificar manejo de cada código de error relevante |
| Test idempotency | Solo W2 | Doble llamada con misma `idempotency_key` |

**Lo que NO entra en 6C:**

- Tests de concurrencia (C-1 a C-4 de `6B_PLAN_FASES.md`). Quedan diferidos como hardening.
- Tests de carga.
- Tests end-to-end con MercadoPago real.

**Criterio de cierre de cada workflow:** los tests mínimos pasan + bitácora actualizada.

---

## 13. SECRETS Y CREDENCIALES

### Lo que vive en n8n credentials (nunca en repo)

- Credencial PostgreSQL (connection string al pooler + usuario + password) para el Postgres node contra Supabase DEV.
- (Más adelante) MercadoPago access token, Meta API tokens, etc.

### Placeholders en este documento

| Placeholder | Reemplaza | Vive en |
|---|---|---|
| `__SUPABASE_PROJECT_ID_DEV__` | ID del proyecto Supabase DEV | Gestor de contraseñas |
| `__SUPABASE_DB_PASSWORD__` | Password de la base (usada por el Postgres node de n8n) | Gestor de contraseñas |
| `__SUPABASE_PROJECT_URL_DEV__` | URL completa del proyecto | Idem |
| `__SUPABASE_SERVICE_ROLE_KEY__` | Service role key. **No aplica al Postgres node de 6C.** Reservado para invocación futura por RPC/HTTP si llega a hacer falta. | n8n credentials |

### Reglas

- Ningún secret real va al repo, ni en `Workflows/n8n/*.json` ni en docs.
- `.gitignore` cubre `.env`, `.env.local`, `*-credentials.json`.
- Antes de commitear exports de n8n, sanitizar IDs de credentials y workflows.
- Si por error se commitea algo: rotar inmediatamente en Supabase + `git filter-branch` o `BFG Repo-Cleaner`.

---

## 14. MINI-PENDIENTE PREVIO A W1

**Estado:** abierto. Debe cerrarse o documentarse explícitamente antes de implementar W1.

### Qué falta

Actualizar `obtener_disponibilidad_rango()` en DEV para que `hora_checkout_base` aplique la regla D47 (16:00 los domingos):

```sql
CASE
  WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '16:00'
  ELSE TIME '10:00'
END AS hora_checkout_base
```

### Plan de ejecución

1. Verificar que no hay nadie usando DEV en ese momento.
2. Intentar `CREATE OR REPLACE FUNCTION obtener_disponibilidad_rango(...)` manteniendo firma idéntica.
3. Si Supabase Dashboard interfiere con el bug del prefijo `v_` (documentado en `Lecciones_Aprendidas.md`):
   - **NO usar `DROP ... CASCADE`** porque `vista_disponibilidad` y `vista_calendario` dependen de la función.
   - Evaluar workaround: DROP de la función después de salvar las vistas, recreación de función, recreación de vistas. O un patrón equivalente que preserve las dependencias.
4. Verificación post-update: `SELECT * FROM vista_disponibilidad WHERE EXTRACT(DOW FROM fecha) = 0 LIMIT 5;` debe mostrar `hora_checkout_base = 16:00`.
5. Bitacorear el cambio en `Docs/Bitacora/6B_EJECUCION_DEV.md`.

### Hasta que esto se cierre

- W1 puede implementarse, pero los outputs de domingos en DEV mostrarán `10:00` en lugar de `16:00`.
- **No declarar DEV 100% alineado con v1.7.1 hasta cerrarlo.**

---

## 15. RIESGOS ABIERTOS Y SUPUESTOS

### Riesgos

| # | Riesgo | Severidad | Mitigación |
|---|---|---|---|
| R1 | n8n no es transaccional con Supabase | Media | Aceptado. PostgreSQL es la fuente de verdad. Side-effects post-éxito se reintentan o reportan operativamente. |
| R2 | Postgres node de n8n puede tener bugs/limitaciones en parameter binding | Baja | Validar en W0. Si aparece, evaluar RPC como alternativa. |
| R3 | `confirmar_reserva()` toma el pago más reciente sin avisar de ambigüedad | Baja | Documentado en Sección 4. En 6C se acepta el comportamiento; si aparecen casos reales de ambigüedad, se evalúa agregar `id_pago` opcional al payload como mejora futura de la función (fuera de 6C). |
| R4 | Sin `consultar_disponibilidad_precio()`, el precio lo calcula n8n o Franco a mano | Media | Aceptado para 6C. Aparecerá como bloqueador antes de web pública. |
| R5 | DEV puede quedar desalineado con v1.7.1 si no se cierra el mini-pendiente | Baja | Sección 14 lo cubre. |
| R6 | Workflows legacy en Sheets siguen activos durante la transición | Media | No tocar Sheets. Naming `vita_*` separa los nuevos. En 6D se evalúa cuándo apagar los legacy. |
| R7 | Credencial PostgreSQL técnica con permisos amplios sin RLS | Media | Aceptado para DEV. Habilitar RLS antes de exponer cualquier frontend público (registrado en `Pendiente_pre_produccion.md`). |

### Supuestos explícitos

1. La conexión Postgres pooler de Supabase soporta el patrón de queries cortas que genera n8n. **A validar en W0.**
2. Los advisory locks de Supabase serializan correctamente bajo n8n con concurrencia libre. **Tests C-1 a C-4 lo validaron en el schema, pero no bajo n8n. Asumimos que se mantiene.**
3. Las funciones SQL son contratos estables. No se modifican durante 6C salvo el mini-pendiente.
4. n8n queda apuntando solo a DEV durante toda la etapa 6C. Cuando exista TEST o PROD en Supabase, los workflows se duplicarán o parametrizarán.
5. No hay migración de datos productivos durante 6C. Las pruebas se hacen con datos inventados o cabañas/huéspedes de prueba.

---

## 16. PRÓXIMO PASO (6D)

Una vez cerrados W0–W7:

### 6D — Integración con canales reales y bot conversacional

Bloques tentativos:

1. Reescribir/crear `db_crear_consulta` contra Supabase (decidir entre función SQL `crear_consulta()` o INSERT directo desde n8n).
2. Webhook de WhatsApp Cloud API → workflow que crea consulta → bot.
3. Webhook de Instagram Graph API → idem.
4. Bot conversacional Claude API conectado a workflows W1, W2 (recolectar datos + crear pre-reserva).
5. Webhook MercadoPago → W3 (registrar pago) + W4 (confirmar reserva).
6. Notificaciones operativas: Vicky, Jennifer, socios.
7. Orquestadores: workflows que componen W1+W2+W3+W4 para flujos end-to-end.

**No abrir 6D antes de cerrar 6C.**

---

## CHECKLIST PARA CERRAR 6C

- [ ] Mini-pendiente v1.7.1 ejecutado y bitacoreado (Sección 14).
- [ ] W0 implementado, smoke test pasa.
- [ ] W1 implementado, tests 1–4 pasan.
- [ ] W2 implementado, tests 1–8 pasan.
- [ ] W3 implementado, tests 1–6 pasan.
- [ ] W4 implementado, tests 1–5 pasan.
- [ ] W5 implementado, tests 1–5 pasan.
- [ ] W6 implementado, tests 1–6 pasan.
- [ ] W7 (a/b/c) implementado, tests básicos pasan.
- [ ] Convenciones de naming, `source_event` e `idempotency_key` aplicadas consistentemente.
- [ ] Templates de workflows sanitizados en `Workflows/n8n/supabase/*.template.json` con placeholders.
- [ ] Bitácora de ejecución de 6C cerrada.
- [ ] Documento `6D_PLAN_CANALES_REALES.md` iniciado (esqueleto, no implementación).

---

*Documento generado como parte del proceso de diseño del sistema Complejo Vita Delta.*
*Versión 1.2 — aprobado como diseño base de 6C.*
