# 6B_EJECUCION_DEV.md
# Bitácora de Ejecución — Etapa 6B Migración a Supabase (entorno DEV)

**Entorno:** Supabase DEV (región `sa-east-1`)
**Documento base:** `Docs/Implementacion/6B_SCHEMA_SQL.md v1.5`
**Plan de ejecución:** `Docs/Implementacion/6B_PLAN_FASES.md v1.1`
**Inicio:** Mayo 2026

> Bitácora sanitizada. Sin credenciales, sin URLs de proyecto, sin IDs internos.
> Cada entrada documenta: bloque ejecutado, resultado, verificación, decisión de avanzar o frenar.

---

## Fase 0 — Preparación

**Estado:** Cerrada.

### Smoke test del SQL Editor

Query ejecutada:
```sql
SELECT NOW() AS server_time,
       current_database() AS db_name,
       version() AS pg_version;
```

Resultado:
- `server_time`: timestamp UTC actual devuelto correctamente.
- `db_name`: `postgres`.
- `pg_version`: PostgreSQL 17.6 sobre aarch64 Linux.

### Verificación de extensiones disponibles

Query ejecutada:
```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name IN ('btree_gist', 'pg_cron')
ORDER BY name;
```

Resultado:

| name       | default_version | installed_version |
|------------|-----------------|-------------------|
| btree_gist | 1.7             | NULL              |
| pg_cron    | 1.6.4           | NULL              |

Ambas extensiones disponibles en el servidor, ninguna habilitada en el proyecto todavía. Habilitación pendiente para Bloque 1.

### Checklist de precondiciones (Sección 2 del plan de fases)

- [x] Proyecto Supabase DEV creado en región sa-east-1.
- [x] Credenciales fuera del repo (gestor de contraseñas / variables locales).
- [x] Extensiones `btree_gist` y `pg_cron` disponibles.
- [x] SQL Editor operativo (smoke test pasado).
- [x] Documentación local accesible (`6B_SCHEMA_SQL.md v1.5`, `6B_PLAN_FASES.md v1.1`).
- [x] GitHub NO conectado a Supabase (decisión consciente: branching no aporta valor en DEV con free tier).

### Decisión

Fase 0 cerrada. Habilitado para ejecutar Bloque 1 (Extensiones).

---

## Fase 1 — Infraestructura base

### Bloque 1 — Extensiones

**Estado:** Cerrado.

**SQL ejecutado:**
```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_cron;
```

**Resultado de ejecución:** `Success. No rows returned`.

**Verificación post-ejecución:**
```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('btree_gist', 'pg_cron')
ORDER BY extname;
```

| extname    | extversion |
|------------|------------|
| btree_gist | 1.7        |
| pg_cron    | 1.6.4      |

Ambas extensiones quedaron habilitadas en el proyecto.

**Observación:** `pg_cron` se habilitó sin necesidad de activación previa desde el panel Database → Extensions. El permiso a través del SQL Editor con rol `postgres` es suficiente en este proyecto.

**Decisión:** avanzar a Bloque 2.

---

### Bloque 2 — Enums

**Estado:** Cerrado.

**SQL ejecutado:**
```sql
CREATE TYPE estado_prereserva_enum AS ENUM (
  'pendiente_pago', 'pago_en_revision', 'vencida', 'convertida',
  'cancelada_por_cliente', 'cancelada_por_bloqueo', 'conflicto_pendiente'
);

CREATE TYPE estado_reserva_enum AS ENUM (
  'confirmada', 'activa', 'completada', 'cancelada',
  'cancelada_con_cargo', 'conflicto_pendiente'
);

CREATE TYPE estado_pago_enum AS ENUM (
  'pendiente', 'en_revision', 'confirmado', 'rechazado', 'reembolsado'
);

CREATE TYPE nivel_log_enum AS ENUM (
  'info', 'warning', 'error'
);
```

**Resultado de ejecución:** `Success. No rows returned`.

**Verificación post-ejecución:**

Tres queries de verificación ejecutadas (filtradas por `typtype='e'` y `nspname='public'` para excluir tipos internos de PostgreSQL y arrays auto-generados):

1. Listado de tipos enum:

| typname                | schema_name |
|------------------------|-------------|
| estado_pago_enum       | public      |
| estado_prereserva_enum | public      |
| estado_reserva_enum    | public      |
| nivel_log_enum         | public      |

2. Conteo de valores por enum:

| typname                | n_valores |
|------------------------|-----------|
| estado_pago_enum       | 5         |
| estado_prereserva_enum | 7         |
| estado_reserva_enum    | 6         |
| nivel_log_enum         | 3         |

3. Listado completo de labels y orden: 21 filas devueltas, orden y valores coinciden con la definición del schema v1.5.

**Observación operativa:** la query inicial de verificación del plan (`WHERE typname LIKE '%_enum'`) devolvió 11 filas por incluir arrays auto-generados (`_estado_*_enum`) y tipos internos de PostgreSQL (`pg_enum`, `anyenum`, `_pg_enum`). Verificación reemplazada por filtro estricto sobre `pg_type.typtype = 'e'` + `pg_namespace.nspname = 'public'`. Convención adoptada para verificaciones de objetos en bloques posteriores.

**Decisión:** avanzar a Bloque 3.

---

### Bloque 3 — Tablas catálogo

**Estado:** Cerrado.

**SQL ejecutado:** 8 tablas creadas en `public` sin dependencias entre sí: `cabanas`, `huespedes`, `feriados`, `tarifas`, `temporadas`, `socios`, `cuentas_cobro`, `plantillas_mensajes`. Incluye `telefono_normalizado` en `huespedes` (v1.1), 3 índices únicos parciales (`dni`, `telefono_normalizado`, `LOWER(email)`), 1 índice único parcial por concepto vigente en `tarifas`, 10 CHECK constraints.

**Resultado de ejecución:** `Success. No rows returned`.

**Advertencia "Potential issue detected" (RLS):** Supabase advirtió que las tablas se crean sin Row Level Security habilitada. Resuelto con "Run without RLS", alineado con la arquitectura aprobada.

Justificación documental (`6B_SCHEMA_SQL.md` Sección 20 y `ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md` Sección "RLS pendiente"):
- Vita Delta no tiene UI interna ni Supabase Auth en esta etapa.
- n8n usa credencial de servicio (`service_role_key`), que bypassea RLS por diseño.
- Las tablas quedan protegidas por el default de PostgreSQL: sin `GRANT` explícito a roles `anon` o `authenticated`, no son accesibles desde la API REST autogenerada.
- RLS se implementará en una etapa específica posterior, cuando se construya frontend público con Supabase Auth, junto con `SECURITY DEFINER` en funciones críticas.

Esta misma decisión aplicará a los Bloques 4, 5, 6 y 7 (todos crean tablas).

**Verificaciones post-ejecución:**

| # | Query | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 3.1 | 8 tablas catálogo en `pg_tables` | 8 filas | 8 filas ✓ |
| 3.2 | Columna `telefono_normalizado` en `huespedes` | 1 fila, tipo `text`, nullable | 1 fila ✓ |
| 3.3 | Índices únicos parciales `uq_%` en `huespedes` | 3 filas (`uq_huespedes_dni`, `uq_huespedes_email`, `uq_huespedes_telefono_normalizado`) | 3 filas ✓ |
| 3.4 | CHECK constraints del bloque | 10 filas | 10 filas ✓ |

**Decisión:** avanzar a Bloque 4.

---

### Bloque 4 — Tablas de configuración

**Estado:** Cerrado.

**SQL ejecutado:** 4 tablas creadas en `public`: `configuracion_general` (PK natural por `clave`), `eventos_especiales` (con JSONB en `reglas_especiales`), `paquetes_evento` (FK obligatoria a `eventos_especiales` con ON DELETE CASCADE), `descuentos` (5 CHECKs sobre tipo, aplica_a, aplica_sobre, valor positivo, fechas).

**Resultado de ejecución:** `Success. No rows returned`.

**Advertencia RLS:** Misma decisión que Bloque 3, "Run without RLS" — justificación ya documentada en la entrada del Bloque 3.

**Verificaciones post-ejecución:**

| # | Query | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 4.1 | 4 tablas en `pg_tables` | 4 filas | 4 filas ✓ |
| 4.2 | FK de `paquetes_evento.id_evento` a `eventos_especiales.id_evento` con ON DELETE CASCADE | 1 fila con `on_delete_action='c'` | 1 fila, `c` ✓ |
| 4.3 | CHECK constraints sobre `eventos_especiales` y `descuentos` | 6 filas (1 + 5) | 6 filas ✓ |

**Decisión:** avanzar a Bloque 5.

---

### Bloque 5 — Tablas dependientes nivel 1

**Estado:** Cerrado.

**SQL ejecutado:** 2 tablas creadas en `public`: `consultas` (con 3 FKs implícitas: `huespedes` y `cabanas` con SET NULL, 2 CHECKs sobre canal y estado_conversacion, 3 índices, 2 columnas JSONB) y `overrides_operativos` (FK a `cabanas` con RESTRICT, 2 CHECKs incluyendo lista cerrada de 8 valores en `tipo_override`, 1 índice).

**Resultado de ejecución:** `Success. No rows returned`.

**Advertencia RLS:** Misma decisión que Bloque 3 — "Run without RLS".

**Nota de trazabilidad:** El CHECK `chk_overrides_tipo` incluye `'escalonamiento_umbral_checkins_dia'`, rename oficial cerrado en Etapa 2 v1.3 + 5A v1.1. Reemplaza las claves antiguas `'escalonamiento_umbral_checkout'` y `'escalonamiento_umbral_checkin'`. No modificar sin actualizar primero la documentación de esas etapas.

**Verificaciones post-ejecución:**

| # | Query | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 5.1 | 2 tablas en `pg_tables` | 2 filas | 2 filas ✓ |
| 5.2 | 3 FKs (2 de `consultas` con SET NULL, 1 de `overrides_operativos` con RESTRICT) | 3 filas con `confdeltype` n, n, r | 3 filas, n/n/r ✓ |
| 5.3 | CHECK constraints del bloque | 4 filas (2 `consultas` + 2 `overrides_operativos`) | 4 filas ✓ |
| 5.4 | Índices `idx_*` del bloque | 4 filas (3 `consultas` + 1 `overrides_operativos`) | 4 filas ✓ |

**Decisión:** avanzar a Bloque 6 (riesgo medio — tablas transaccionales).

---

### Bloque 6 — Tablas transaccionales

**Estado:** Cerrado. **Riesgo: medio (el más sensible de Fase 1).**

**SQL ejecutado:** 5 tablas transaccionales creadas en `public`:
- `pre_reservas` con campos nuevos v1.1 (mascotas, detalle_mascotas, ninos, notas_reserva, idempotency_key), índice único parcial `uq_prereservas_idempotency_activa` sobre `idempotency_key` cuando `estado IN ('pendiente_pago','pago_en_revision')`, 6 CHECKs, 4 índices regulares.
- `reservas` con campos operativos v1.1 (mascotas, detalle_mascotas, ninos, notas_reserva), 5 CHECKs, 4 índices.
- `pagos` con cambio v1.1 crítico: `id_prereserva` y `id_reserva` ambos nullable + CHECK `chk_pagos_referencia_minima` que asegura que al menos una de las dos referencias exista. 5 CHECKs, 3 índices.
- `bloqueos` con `id_cabana` nullable (soporta lock total via función `crear_bloqueo()` futura). 2 CHECKs, 1 índice parcial.
- `gastos` sin CHECKs propios, 2 índices.

**Resultado de ejecución:** `Success. No rows returned`.

**Advertencia RLS:** Misma decisión que Bloque 3 — "Run without RLS".

**Verificaciones post-ejecución:**

| # | Query | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 6.1 | 5 tablas en `pg_tables` | 5 filas | 5 filas ✓ |
| 6.2 | Campos operativos v1.1 (mascotas/detalle_mascotas/ninos/notas_reserva en pre_reservas y reservas) | 8 filas, `mascotas` boolean NOT NULL DEFAULT false, otros 3 TEXT nullables | 8 filas ✓ |
| 6.3 | Columna `idempotency_key` (text, nullable) + índice único parcial `uq_prereservas_idempotency_activa` | columna verificada indirectamente vía existencia del índice; índice presente con cláusula WHERE parcial | índice presente ✓ |
| 6.4 | CHECK `chk_pagos_referencia_minima` v1.1 | definición `CHECK (((id_prereserva IS NOT NULL) OR (id_reserva IS NOT NULL)))` | exacto ✓ |
| 6.5 | 11 Foreign Keys del bloque con ON DELETE correcto | 11 filas con tabla/columna/referencia/acción esperada | 11 filas con acciones RESTRICT/SET NULL como diseño ✓ |
| 6.6 | Conteo de CHECKs por tabla | pre_reservas 6, reservas 5, pagos 5, bloqueos 2 (gastos 0) | exacto ✓ |

**Observación operativa:** Verify 6.3 originalmente proponía dos queries en una sola pestaña (a: columna; b: índice). Se ejecutó solo la query (b) — la existencia del índice único parcial sobre `idempotency_key` confirma indirectamente que la columna existe en `pre_reservas`, ya que PostgreSQL no permite crear índices sobre columnas inexistentes. La verificación se considera válida.

**Decisión:** avanzar a Bloque 7 (tabla de auditoría `log_cambios`).

---

### Bloque 7 — Tabla de auditoría

**Estado:** Cerrado.

**SQL ejecutado:** Tabla `log_cambios` creada con 11 columnas, incluyendo `nivel` tipado con el enum `nivel_log_enum` (default `'info'`) y `detalle` como JSONB. 4 índices creados: btree sobre `fecha_hora DESC`, btree sobre `tabla_afectada`, btree parcial sobre `nivel` (solo cuando `nivel <> 'info'`), y **GIN sobre `detalle`** para búsquedas eficientes dentro del JSONB.

**Resultado de ejecución:** `Success. No rows returned`.

**Advertencia RLS:** Misma decisión que Bloque 3 — "Run without RLS".

**Verificaciones post-ejecución:**

| # | Query | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 7.1 | Tabla en `pg_tables` | 1 fila | 1 fila ✓ |
| 7.2 | Columna `nivel` con `udt_name = nivel_log_enum` y default `'info'` | 1 fila con USER-DEFINED + nivel_log_enum | exacto ✓ |
| 7.3 | 4 índices con los tipos correctos (gin/btree) y predicados parciales | 4 filas | `idx_log_cambios_detalle_gin USING gin (detalle)`, `idx_log_cambios_fecha USING btree (fecha_hora DESC)`, `idx_log_cambios_nivel USING btree (nivel) WHERE (nivel <> 'info'::nivel_log_enum)`, `idx_log_cambios_tabla USING btree (tabla_afectada)` ✓ |

**Observación operativa:** la columna `indexdef` se cortaba visualmente en la captura inicial. Resuelto ampliando el ancho de columna manualmente en el SQL Editor — las 4 definiciones completas confirmaron en una sola captura que el GIN está bien creado, el índice parcial sobre `nivel` tiene el WHERE correcto, y el índice sobre `fecha_hora` está en orden DESC. Convención adoptada para futuras verificaciones con `indexdef`: ampliar columna antes de pedir queries adicionales.

**Decisión:** avanzar a Bloque 8 (constraints EXCLUDE — el último de Fase 1).

---

### Bloque 8 — Constraints EXCLUDE (anti-doble-booking estructural)

**Estado:** Cerrado. **Riesgo: medio (último de Fase 1, primera ejercitación de `btree_gist`).**

**SQL ejecutado:** 2 constraints EXCLUDE agregados vía `ALTER TABLE`:

- `exc_reservas_no_overlap` sobre `reservas`: impide solapamiento de `(id_cabana, daterange(fecha_checkin, fecha_checkout, '[)'))` cuando `estado IN ('confirmada','activa')`.
- `exc_bloqueos_no_overlap` sobre `bloqueos`: impide solapamiento de `(id_cabana, daterange(fecha_desde, fecha_hasta, '[)'))` cuando `activo = TRUE AND id_cabana IS NOT NULL`.

Ambos usan `EXCLUDE USING gist` (gracias a la extensión `btree_gist` habilitada en Bloque 1) y notación de rango `[)` (`fecha_in` inclusive, `fecha_out` exclusive — alineado con el principio #13 de la arquitectura).

**Resultado de ejecución:** `Success. No rows returned`. No apareció popup RLS (es ALTER TABLE, no CREATE TABLE).

**Verificaciones post-ejecución:**

| # | Query | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 8.1 | 2 constraints EXCLUDE en `pg_constraint` con `contype='x'` | 2 filas | 2 filas ✓ |
| 8.2 | Definiciones completas vía `pg_get_constraintdef` | Predicados parciales correctos, `daterange '[)'`, `USING gist` | exacto ✓ |
| 8.3 | Índices GiST asociados (uno por constraint) | 2 filas con `am.amname = 'gist'` | 2 filas ✓ |

**Observación operativa:** la columna `definicion` del Verify 8.2 se cortaba en la grilla. Resuelto haciendo click en la celda para abrir el panel "Viewing cell details" — muestra el contenido completo sin truncar. Convención adoptada para futuras verificaciones con definiciones largas.

**Significado funcional:** a partir de este bloque, PostgreSQL garantiza estructuralmente que es imposible insertar dos reservas confirmadas o activas que se solapen sobre la misma cabaña, o dos bloqueos activos sobre la misma cabaña específica. Esta es la última línea de defensa contra doble booking — independiente de la lógica de aplicación.

**Decisión:** avanzar a Fase 2.

---

## Cierre de Fase 1

**Estado:** Cerrada. 8 de 8 bloques verificados.

**Resumen estructural del schema:**

| Categoría | Conteo |
|---|---|
| Extensiones | 2 (btree_gist, pg_cron) |
| Enums | 4 (21 valores totales) |
| Tablas catálogo | 8 |
| Tablas configuración | 4 |
| Tablas dependientes nivel 1 | 2 |
| Tablas transaccionales | 5 |
| Tabla auditoría | 1 (log_cambios con índice GIN sobre JSONB) |
| **Total tablas** | **20** |
| CHECK constraints | ~28 (10 Bloque 3 + 6 Bloque 4 + 4 Bloque 5 + 18 Bloque 6) |
| Foreign keys | 15 |
| Índices regulares y parciales | ~25 |
| EXCLUDE constraints | 2 |

**Decisión:** habilitado para arrancar Fase 2 (funciones y triggers, Bloques 9 a 19). La Fase 2 es la más sensible del schema porque introduce la lógica almacenada: normalización de teléfono, upsert de huéspedes, validación de disponibilidad, creación/confirmación/cancelación de pre-reservas, manejo de pagos, expiración automática. Cada función crítica tiene tests funcionales pequeños recomendados durante la ejecución; los tests end-to-end completos van en Fase 4.

---

### Bloque 9 — `normalizar_telefono` + trigger en `huespedes`

**Estado:** Cerrado. **Primera función de Fase 2.**

**SQL ejecutado:** 
- Función `normalizar_telefono(input TEXT) RETURNS TEXT` con `LANGUAGE plpgsql IMMUTABLE`. Aplica reglas de limpieza: quita espacios/guiones/paréntesis/puntos, convierte `00` inicial a `+`, colapsa múltiples `+` a uno solo, no asume prefijo argentino automático.
- Trigger function `set_telefono_normalizado()` que invoca a `normalizar_telefono(NEW.telefono)` y asigna el resultado a `NEW.telefono_normalizado`.
- Trigger `trg_huespedes_telefono_norm BEFORE INSERT OR UPDATE OF telefono ON huespedes FOR EACH ROW`.

**Resultado de ejecución:** `Success. No rows returned`.

**Verificaciones post-ejecución:**

| # | Query | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 9.1 | 2 funciones en `pg_proc` con volatilidad correcta | `normalizar_telefono` IMMUTABLE (i), `set_telefono_normalizado` VOLATILE (v) | exacto ✓ |
| 9.2 | Trigger `trg_huespedes_telefono_norm` registrado en `information_schema.triggers` | 2 filas (INSERT + UPDATE, ambos BEFORE) ejecutando `set_telefono_normalizado()` | exacto ✓ |
| 9.3 | Test funcional con 6 casos | `+5491134567890`, `+541134567890`, `1134567890`, `+541134567890`, NULL, NULL | exacto ✓ |
| 9.4 | Test del trigger en vivo (INSERT + UPDATE + DELETE sobre `huespedes`) | INSERT puebla `telefono_normalizado`, UPDATE de `telefono` lo recalcula, DELETE limpia | confirmado vía RETURNING del UPDATE (1 fila: `(011) 9876-5432` → `01198765432`), implícitamente confirma INSERT previo, DELETE ejecutado sin error |

**Observación sobre Verify 9.4:** Supabase devolvió únicamente el output del último RETURNING visible (el del UPDATE), pero la presencia de esa fila confirma toda la cadena: el INSERT debe haberse ejecutado para que el UPDATE encontrara la fila, y el `telefono_normalizado` se llenó automáticamente por el trigger. El DELETE final se ejecutó sin error. Sanity check post-test (`SELECT COUNT(*) FROM huespedes`) pendiente de correr para confirmar limpieza.

**Advertencia "Potential issue detected — destructive operations":** Supabase advierte ante cualquier query con INSERT/UPDATE/DELETE. Resuelto con "Run query", justificado porque la tabla `huespedes` estaba vacía, el test es auto-contenido (escribe y borra dentro del mismo bloque), y estamos en DEV.

**Decisión:** avanzar a Bloque 10 (`upsert_huesped`).

---

### Bloque 10 — Función `upsert_huesped`

**Estado:** Cerrado. **Primera función de negocio del sistema.**

**SQL ejecutado:** Función `upsert_huesped(payload JSONB) RETURNS JSONB` con lógica de búsqueda priorizada (teléfono normalizado → email → INSERT nuevo), manejo selectivo de UPDATE (COALESCE preserva valores existentes), validación de contacto mínimo, y manejo diferenciado de `unique_violation` según constraint:
- Conflicto por DNI: error controlado `huesped_duplicado` (requiere intervención humana).
- Conflicto por teléfono/email: recuperación silenciosa con `modo='recovered_from_unique_violation'` (cubre race conditions).

**Resultado de ejecución:** `Success. No rows returned`. Sin popup RLS (CREATE FUNCTION). Sin popup destructive (no escribe por sí mismo).

**Verificaciones post-ejecución:**

| # | Test | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 10.1 | Función registrada en `pg_proc` | `upsert_huesped` retorna jsonb, VOLATILE | exacto ✓ |
| 10.2 | T1 — crear nuevo (telefono + email) | `modo='create'`, `encontrado_por=null` | id_huesped=2, exacto ✓ |
| 10.3 | T2 — buscar por teléfono (formato distinto al T1) | `modo='update'`, `encontrado_por='telefono'`, mismo id_huesped | exacto ✓ — confirma normalización end-to-end |
| 10.4 | T3 — sin contacto (solo nombre) | `ok=false`, `error='contacto_requerido'` | exacto ✓ — falla antes del INSERT, no escribe |
| 10.5 | T4 — buscar por email (sin teléfono) | `modo='update'`, `encontrado_por='email'`, mismo id_huesped | exacto ✓ — confirma fallback email |
| 10.6 | Limpieza post-tests | DELETE 1 + COUNT 0 | exacto ✓ |

**Observación operativa — secuencia BIGSERIAL:** El primer huésped insertado por el T1 recibió `id_huesped=2`, no 1, porque la secuencia `huespedes_id_huesped_seq` ya había avanzado durante el test del Bloque 9 (test del trigger). Comportamiento esperado de PostgreSQL: las secuencias no retroceden tras DELETE. No se resetea en DEV — refleja el comportamiento real de producción. Si en algún momento futuro hace falta una secuencia limpia (improbable), se usaría `ALTER SEQUENCE ... RESTART WITH 1`.

**Observación operativa — popup destructive:** El popup "Potential issue detected — destructive operations" aparece cuando el SQL contiene textualmente `INSERT/UPDATE/DELETE/DROP/ALTER`. Las llamadas a funciones almacenadas (`SELECT upsert_huesped(...)`) no disparan el popup aunque internamente escriban, porque Supabase hace análisis estático del texto sin entrar en el cuerpo de la función. Para los próximos bloques esto será frecuente — la mayoría de tests funcionales sobre funciones no dispararán popup.

**Cobertura de tests:** El plan menciona un T5 opcional sobre conflicto DNI que requiere setup previo (crear un huésped con DNI X, luego intentar crear otro con mismo DNI pero datos distintos). Queda implícitamente cubierto por la lógica de `unique_violation` con `LIKE '%dni%'` que está en la función. Si en Fase 4 (tests con seed completo) se quiere verificación explícita, se cubre ahí.

**Decisión:** avanzar a Bloque 11 (`validar_disponibilidad` — función auxiliar de disponibilidad).

---

### Bloque 11 — Función `validar_disponibilidad`

**Estado:** Cerrado. **Función auxiliar más usada de Fase 2.**

**SQL ejecutado:** Función `validar_disponibilidad(p_id_cabana BIGINT, p_fecha_in DATE, p_fecha_out DATE, p_excluir_prereserva BIGINT DEFAULT NULL) RETURNS JSONB`. Verifica solapamientos contra tres fuentes (`reservas` con estado confirmada/activa, `pre_reservas` con estado pendiente_pago vigente o pago_en_revision, `bloqueos` activos específicos o totales). Internamente usa `SELECT ... FOR UPDATE` sobre cabanas/reservas/pre_reservas/bloqueos, por lo que el documento explicita en comentario inline que solo debe llamarse desde transacciones que hayan tomado previamente `pg_advisory_xact_lock(10, 0)` para evitar deadlocks (advertencia v1.5 Obs G).

**Resultado de ejecución:** `Success. No rows returned`. Sin popup destructive (CREATE FUNCTION).

**Verificaciones post-ejecución:**

| # | Test | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 11.1 | Función registrada en `pg_proc` | `validar_disponibilidad`, jsonb, VOLATILE, 4 argumentos | exacto ✓ |
| 11.2 | 4 casos de error en parámetros (UNION ALL) | `fechas_invalidas` ×2, `id_cabana_requerido`, `cabana_no_existe` | exacto ✓ |
| 11.3 | Setup: crear cabaña test (`Cabaña Test B11`) | 1 fila con id_cabana asignado y `activa=true` | id=1 ✓ |
| 11.4 | Disponible con tablas vacías | `{ok: true, disponible: true}` | exacto ✓ |
| 11.5 | **Detección de conflicto: bloqueo solapado** | `{ok: true, disponible: false, conflictos: [{fuente: "bloqueos"}]}` | exacto ✓ — confirma lógica de `daterange && daterange` |
| 11.6 | Limpieza + sanity check | cabanas/bloqueos/huespedes en 0 | exacto ✓ |

**Observación operativa — UNION ALL para múltiples test cases:** El SQL Editor de Supabase muestra por defecto solo el resultado del último statement cuando se ejecutan varios SELECTs separados por `;`. Para los tests de parámetros (4 casos), se reescribió usando `UNION ALL` con una columna `caso` identificadora para ver los 4 outputs en una sola tabla. Patrón adoptado para futuros bloques con tests funcionales múltiples del mismo tipo.

**Observación operativa — orden de claves en JSONB:** En Verify 11.5 el JSON devuelto tenía las claves en orden distinto al predicho (`conflictos` antes de `disponible`). PostgreSQL no garantiza orden de claves en JSONB construido vía `jsonb_build_object` + `||`. Lo relevante son las claves y valores, no su orden de impresión.

**Decisión:** avanzar a Bloque 12 (`obtener_disponibilidad_rango` — última función auxiliar antes de los bloques transaccionales).

---

### Bloque 12 — Función `obtener_disponibilidad_rango`

**Estado:** Cerrado. **Reemplazo conceptual de `DISPONIBILIDAD_CACHE` del modelo Sheets.**

**SQL ejecutado:** Función `obtener_disponibilidad_rango(p_fecha_desde DATE, p_fecha_hasta DATE, p_id_cabana BIGINT DEFAULT NULL) RETURNS TABLE(...)`. Calcula disponibilidad al vuelo cruzando `generate_series` de fechas × cabañas activas, y para cada slot resuelve `estado` (bloqueada/ocupada/checkout_disponible/disponible), `tipo_dia` (feriado/finde/semana), `temporada`, horarios base (con regla especial domingo→18:00), e IDs de reserva/pre-reserva si aplican. **Función de solo lectura — no escribe, no toma locks**. Va a alimentar la `vista_disponibilidad` del Bloque 20.

**Resultado de ejecución:** `Success. No rows returned`. Sin popups.

**Verificaciones post-ejecución:**

| # | Test | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 12.1 | Función registrada en `pg_proc` | `obtener_disponibilidad_rango`, record, VOLATILE, 3 argumentos | exacto ✓ |
| 12.2 | Con tablas vacías (sin cabañas activas) | 0 filas | exacto ✓ |
| 12.3 | Setup: 2 cabañas test + 1 feriado fuera de rango + 1 temporada que cubre 5-12/jul | 2 filas (cabañas id=2 e id=3) | exacto ✓ |
| 12.4 | **Test funcional con datos** (rango 1-8/jul, 2 cabañas) | 14 filas; finde en vie 3 y sáb 4; semana en domingo 5; checkin 18:00 solo domingo; temporada poblada en días 5-7 | exacto ✓ — todas las reglas estructurales verificadas |
| 12.5 | Filtro por id_cabana específico | COUNT = 7 (1 cabaña × 7 días) | exacto ✓ |
| 12.6 | Limpieza + sanity check | cabanas/feriados/temporadas en 0 | exacto ✓ |

**Reglas verificadas en Verify 12.4:**
- Rango `[fecha_desde, fecha_hasta)` con fecha_hasta exclusiva (día 8 no aparece).
- `EXTRACT(DOW) IN (5,6)` → viernes/sábado como `finde`.
- `EXTRACT(DOW) = 0` → domingo con `hora_checkin_base = 18:00` (el resto 13:00).
- `BETWEEN fecha_desde AND fecha_hasta` de temporadas funcionando inclusive.
- `hora_checkout_base = 10:00` fijo.
- Estado `disponible` en todos los slots cuando no hay reservas/pre-reservas/bloqueos.

**Cobertura no verificada (intencional):** Los estados `ocupada`, `bloqueada`, `checkout_disponible` no se ejercitaron porque requieren datos en reservas/pre_reservas/bloqueos. El feriado se creó fuera del rango pedido para no contaminar el test base. Estos casos se cubren en Fase 4 con seed completo.

**Decisión:** avanzar a Bloque 13 (`crear_prereserva` — la puerta única, riesgo ALTO).

---

### Bloque 13 — Función `crear_prereserva` (PUERTA ÚNICA)

**Estado:** Cerrado. **Función más crítica del schema — punto de entrada único para todas las pre-reservas del sistema.**

**SQL ejecutado:** Función `crear_prereserva(payload JSONB) RETURNS JSONB` (~250 líneas). Implementa el flujo completo de creación de pre-reserva con 12 secciones: extracción y validación de payload, lectura de configuración agrupada (`jsonb_object_agg` sobre 6 claves), idempotencia pre-lock, validación y resolución de huésped vía `upsert_huesped`, toma de locks (global + por cabaña), idempotencia post-lock, validación de cabaña/capacidad, validación de disponibilidad vía `validar_disponibilidad`, cálculo de horarios desde config (con regla especial domingo), INSERT con manejo defensivo de `unique_violation`, log de creación, log warning si faltan claves de config, y retorno de JSONB unificado.

**Bug detectado y corregido durante la ejecución:**

El SQL original del documento `6B_SCHEMA_SQL.md v1.5` contiene la línea:
```sql
PERFORM pg_advisory_xact_lock(1, v_id_cabana);
```

Esto falla con `ERROR 42883: function pg_advisory_xact_lock(integer, bigint) does not exist` porque `v_id_cabana` está declarada como `BIGINT` y PostgreSQL no tiene la sobrecarga `(integer, bigint)`. Existen solo `(bigint)` y `(integer, integer)`.

**Corrección aplicada vía `CREATE OR REPLACE FUNCTION`:**
```sql
PERFORM pg_advisory_xact_lock(1, v_id_cabana::INTEGER);
```

El cast a INTEGER es seguro porque `id_cabana` en Vita Delta nunca va a superar el rango integer (~2.1 mil millones). La función `pg_advisory_xact_lock` no necesita el valor exacto, solo un identificador único.

**Acción tomada:**
- Pestaña original "Bloque 13 — crear_prereserva" conservada con el SQL del documento (bug incluido).
- Pestaña nueva "Bloque 13 v2 — fix advisory lock" con el SQL corregido aplicado vía `CREATE OR REPLACE`.

**Acción pendiente para próximos bloques:** Verificar si los Bloques 14 (`confirmar_reserva`) y 16 (`crear_bloqueo`) tienen el mismo patrón. Si sí, aplicar el cast `::INTEGER` proactivamente.

**Acción pendiente para documentación:** Reportar el bug del documento `6B_SCHEMA_SQL.md v1.5` para corrección.

**Verificaciones post-ejecución (9 pasos):**

| # | Test | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 13.1 | Función registrada (1 argumento JSONB) | `crear_prereserva, jsonb, VOLATILE, 1` | exacto ✓ |
| 13.2 | Setup: 1 cabaña + 6 claves config (post-corrección `tipo_valor`) | cabana=1, claves_horario=5, clave_expiracion=1, id_cabana_test=6 | exacto ✓ |
| 13.3 | **T-PR-1: Creación exitosa (camino feliz)** | JSON con `ok:true`, `id_pre_reserva:1`, `estado:pendiente_pago`, `hora_checkin:13:00:00` (sábado, no domingo), `expira_en:~60min`, `recovery_path:null` | exacto ✓ — la función completa funciona end-to-end |
| 13.4 | **T-PR-2: Idempotencia con misma key** | Ambas llamadas devuelven mismo `id_pre_reserva=2` e `id_huesped=5`; llamada 2 con `recovery_path:"pre_lock"` | exacto ✓ — la segunda no creó huésped "Cliente Distinto", cortocircuito perfecto |
| 13.5 | 6 errores controlados (sin_contacto, cabana_no_existe, excede_capacidad, precio_requerido, fechas_invalidas, nombre_vacio) | 6 JSONs con códigos estables y motivos | exacto ✓ — todos los flancos validados |
| 13.6 | T-PR-9: no_disponible (rango solapado con T-PR-1) | `{ok:false, error:"no_disponible", conflictos:[{fuente:"pre_reservas"}]}` | exacto ✓ — confirma integración con `validar_disponibilidad` |
| 13.7 | Logs generados en `log_cambios` | 2 filas (T-PR-1 y T-PR-2 llamada 1), `evento:prereserva_creada`, `nivel:info`, source_event conservado | exacto ✓ — los tests de error NO generan log (diseño correcto) |
| 13.8 | Limpieza inicial (pre-reservas, 3 huéspedes, cabaña, config, logs) | 5 tablas en 0, salvo `huespedes:2` | parcialmente — 2 huéspedes residuales |
| 13.8b | Limpieza extendida (huéspedes residuales de tests de error) | 11 tablas verificadas en 0 | exacto ✓ — DEV en estado limpio |

**Lección operativa importante — huéspedes residuales en tests de error:**

`crear_prereserva` ejecuta `upsert_huesped` en la sección 4, ANTES de la validación de cabaña (sección 6). Por lo tanto, los tests que fallan en secciones ≥ 6 (`cabana_no_existe`, `excede_capacidad`) dejan el huésped creado aunque la pre-reserva no se haya creado.

Esto **no es un bug** — es por diseño. Razón: en el flujo conversacional real, si el huésped es válido pero la cabaña tiene problemas, queremos preservar su contacto para sugerirle alternativas. `upsert_huesped` es idempotente, así que no hay duplicación.

**Implicación para futuros bloques (14-18):** los planes de tests de error deben contemplar limpieza de TODAS las tablas que la función toca antes de devolver el error, no solo de la tabla principal.

**Lección operativa — Supabase rollback transaccional:**

Durante Verify 13.2 inicial (con error de columna `tipo_dato`), Supabase hizo rollback del INSERT a `cabanas` aunque era statement separado del INSERT que falló. Esto sugiere que el SQL Editor envuelve los bloques en una transacción implícita ante errores. Convención adoptada: **asumir rollback ante error y verificar antes de re-correr**.

**Lección operativa — bug del SQL Editor que muestra solo el último resultado:**

Cuando hay múltiples SELECTs separados por `;`, Supabase muestra solo el output del último. Patrón adoptado: usar `UNION ALL` con columna identificadora (`caso`, `test`, `momento`) cuando se quieren ver todos los resultados de una vez.

**Decisión:** avanzar a Bloque 14 (`confirmar_reserva`) en próxima sesión.

---

### Actualización documental posterior al Bloque 13

Durante la ejecución del Bloque 13 se detectó un bug de tipado en `pg_advisory_xact_lock(1, v_id_cabana)` porque `v_id_cabana` es `BIGINT` y PostgreSQL no provee la sobrecarga `(integer, bigint)`. El bug fue corregido en DEV vía `CREATE OR REPLACE FUNCTION` y luego incorporado al documento `6B_SCHEMA_SQL.md v1.6`.

A partir del Bloque 14, la ejecución continúa usando `6B_SCHEMA_SQL.md v1.6`.

---

### Bloque 14 — Función `confirmar_reserva`

**Estado:** Cerrado. **Segunda función crítica de Fase 2. Junto con `crear_prereserva` (B13) forma el flujo completo de "creación → confirmación" de reservas.**

**SQL ejecutado:** Función `confirmar_reserva(payload JSONB) RETURNS JSONB` (~200 líneas). Convierte una pre-reserva en reserva confirmada. Implementa 11 secciones: extracción payload, setear contexto para triggers (D38), lock global (10,0) ANTES del FOR UPDATE (invariante v1.5), SELECT FOR UPDATE pre-reserva + validación de estado, lock por cabaña con `::INTEGER`, verificación de pago (camino estricto o combinado), revalidación de disponibilidad excluyendo la propia pre-reserva, INSERT en reservas con captura defensiva de exclusion_violation, UPDATE pre-reserva → 'convertida', asociar pago con id_reserva, transformación de pago en_revision → confirmado si camino combinado, UPDATE huésped (total_reservas + primera_reserva_fecha vía COALESCE), log con diferenciador `camino: estricto|combinado`.

**Documento usado:** `6B_SCHEMA_SQL.md v1.6.1` (con el fix `pg_advisory_xact_lock(1, v_pre.id_cabana::INTEGER)` aplicado proactivamente desde el documento gracias al reporte del Bloque 13).

**Resultado de ejecución:** `Success. No rows returned`. Sin popup destructive.

**Verificaciones post-ejecución (12 pasos):**

| # | Test | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 14.1 | Función registrada en `pg_proc` | `confirmar_reserva, jsonb, VOLATILE, 1` | exacto ✓ |
| 14.2 | Setup completo (cabaña + 6 config + pre-reserva via `crear_prereserva` + pago confirmado) | id_cabana=7, pre_reserva=3, huesped=9, pago=1 confirmado | exacto ✓ (con corrección: removí re-INSERT de config tras error de unicidad) |
| 14.3 | **T-CR-1: Camino estricto exitoso** | `ok:true, id_reserva:1, id_pre_reserva:3, id_huesped:9` | exacto ✓ — primera reserva del sistema |
| 14.4 | Verificación cruzada (4 tablas afectadas) | `reservas.estado=confirmada`, `pre_reservas.estado=convertida`, `pagos.id_reserva=1`, `huespedes.total_reservas=1` | exacto ✓ — `monto_saldo=50000` calculado por la función, `primera_reserva_fecha` poblada via COALESCE |
| 14.5 | T-CR-2: Idempotencia operativa (confirmar dos veces) | `ok:false, error:estado_invalido, estado_actual:convertida` | exacto ✓ — resistencia a retries de n8n |
| 14.6 | T-CR-3: Pre-reserva inexistente | `ok:false, error:prereserva_no_existe` | exacto ✓ |
| 14.7 | Setup para camino combinado (pre-reserva 4 + pago en_revision id=2) | pre-reserva 4 creada con `hora_checkin: 13:00` (lunes), pago 2 en `en_revision` | exacto ✓ |
| 14.8 | **T-CR-4: Camino combinado exitoso** | `ok:true, id_reserva:2, id_pre_reserva:4, id_huesped:10` | exacto ✓ |
| 14.9 | Verificación cruzada del camino combinado | **`pago_2.estado` cambió de `en_revision` a `confirmado`**, `validado_por=Vicky`, `validado_en` seteado | exacto ✓ — comportamiento distintivo del camino combinado validado |
| 14.10 | T-CR-5: Sin pago confirmado y sin permitir combinado | `ok:false, error:sin_pago_confirmado` | exacto ✓ |
| 14.11 | Logs (5 esperados, 0 de errores controlados) | 3 prereserva_creada + 2 reserva_confirmada (estricto + combinado) | exacto ✓ — errores controlados no loguean (diseño correcto) |
| 14.12 | Limpieza extendida + sanity check global | 11 tablas en 0 | exacto ✓ |

**Comportamientos clave validados:**

1. **Diferencia entre los dos caminos:** en T-CR-1 (estricto), el pago ya estaba `confirmado` y solo se le asoció `id_reserva`. En T-CR-4 (combinado), el pago se transformó de `en_revision` a `confirmado` automáticamente, con `validado_por='Vicky'` y `validado_en=NOW()`. Esto provee auditoría completa para revisión humana posterior de confirmaciones "a riesgo".

2. **Regla especial de domingo aplicada:** en Verify 14.10, la pre-reserva para fecha 2026-11-01 (domingo) se creó con `hora_checkin: 18:00:00` en vez del default 13:00. Confirma que `crear_prereserva` lee correctamente `hora_checkin_domingo` desde `configuracion_general` cuando `EXTRACT(DOW)=0`.

3. **Cálculo de `monto_saldo`:** la función calcula `monto_saldo = monto_total - monto_sena` internamente (no viene en el payload). En T-CR-1: 100000 - 50000 = 50000. En T-CR-4: 120000 - 60000 = 60000. Lógica de negocio centralizada en la función.

4. **`primera_reserva_fecha` con COALESCE:** se setea solo en la primera reserva confirmada por huésped. En confirmaciones siguientes del mismo huésped, NO se sobreescribe (queda la primera). Diseño correcto para uso operativo (Franco quiere saber desde cuándo es cliente).

**Logs diferenciados por camino:**
- Logs id=4 y id=6 contienen `detalle.camino` con valor `'estricto'` o `'combinado'`.
- Permite auditar en producción cómo se confirmó cada reserva. Las combinadas pueden necesitar revisión periódica.

**Observación operativa — Popup destructive:** A partir del Bloque 10 confirmado en Bloque 14: las llamadas `SELECT crear_prereserva(...)` y `SELECT confirmar_reserva(...)` NO disparan popup destructive de Supabase aunque internamente escriban, porque sintácticamente son SELECTs. El popup solo aparece en INSERT/UPDATE/DELETE/DROP/ALTER directos. Esto facilita la velocidad operacional de los tests funcionales, pero requiere atención: si por error se ejecuta una función crítica en PROD, no hay confirmación visual.

**Observación operativa — Error de re-ejecución de bloques con UNIQUE:** Durante Verify 14.2, al reintentar el setup completo después de un paso 1 exitoso, el segundo run chocó con `uq_cabanas_nombre` (la cabaña ya existía). Lección consolidada: **después de un run exitoso, los statements anteriores quedan commiteados en la base. Reducir la pestaña a solo lo faltante en runs siguientes**.

**Decisión:** avanzar a Bloque 15 (`cancelar_prereserva`) en próxima sesión.

---

### Bloque 15 — Función `cancelar_prereserva`

**Estado:** Cerrado. **Cierra el ciclo de vida de pre-reservas.** Junto con B13 (`crear_prereserva`) y B14 (`confirmar_reserva`), provee las 3 transiciones de estado: pendiente_pago → convertida (confirmar), → cancelada_* (cancelar), → expirada (B18 futuro).

**SQL ejecutado:** Función `cancelar_prereserva(payload JSONB) RETURNS JSONB` (~95 líneas). Implementa 6 secciones: extracción payload, setear contexto para triggers (D38), lock global (10,0), mapeo motivo→estado, SELECT FOR UPDATE pre-reserva + validación de estado cancelable, UPDATE pre-reserva, conteo de pagos asociados (sin tocarlos), log + return JSON con IDs de pagos.

**Decisiones de diseño confirmadas:**
- **No toma lock por cabaña** (solo libera disponibilidad, no la consume).
- **No toca pagos asociados** — los cuenta y devuelve sus IDs en el output para revisión humana.
- Motivos cerrados: solo `cliente` o `bloqueo`. Otros valores devuelven `motivo_invalido` con lista de válidos.
- Estados cancelables: solo `pendiente_pago` y `pago_en_revision`.

**Documento usado:** `6B_SCHEMA_SQL.md v1.6`. Sin cambios respecto a v1.5 para este bloque (no usa lock por cabaña → no aplica el fix `::INTEGER`).

**Resultado de ejecución:** `Success. No rows returned`.

**Verificaciones post-ejecución (9 pasos):**

| # | Test | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 15.1 | Función registrada | `cancelar_prereserva, jsonb, VOLATILE, 1` | exacto ✓ |
| 15.2 | Setup (cabaña + config + 2 pre-reservas + 1 pago en_revision) | id_cabana=9, pre_reservas 6 y 7, pago 3 | exacto ✓ |
| 15.3 | T-CP-1: cancelar pre-reserva 6 con motivo `cliente`, sin pagos | `estado_nuevo: cancelada_por_cliente, pagos_asociados_count: 0, pagos_asociados_ids: []` | exacto ✓ |
| 15.4 | T-CP-2: cancelar pre-reserva 7 con motivo `bloqueo`, con pago | `estado_nuevo: cancelada_por_bloqueo, pagos_asociados_count: 1, pagos_asociados_ids: [3]` | exacto ✓ — comportamiento clave validado |
| 15.5 | 4 errores controlados (UNION ALL) | payload_invalido, motivo_invalido (con motivos_validos), prereserva_no_existe, estado_no_cancelable | exacto ✓ |
| 15.6 | Verificación cruzada de estados | pre-reservas en estados terminales, pago 3 intacto | parcialmente — campo `updated_recently` resultó falso positivo |
| 15.6-bis | Confirmación definitiva: `pago.updated_at = pago.created_at` | `nunca_modificado: true`, timestamps idénticos al microsegundo | exacto ✓ |
| 15.7 | Logs (2 cancelaciones, 0 errores) | 2 filas con `evento: prereserva_cancelada`, motivos y pagos diferenciados | exacto ✓ |
| 15.8 | Limpieza extendida + sanity check global | 11 tablas en 0 | exacto ✓ |

**Lección operativa — diseño de tests con timestamps:**

En Verify 15.6 incluí el campo `updated_recently := updated_at > NOW() - INTERVAL '5 minutes'` para verificar que el pago no fue modificado. Resultó **falso positivo** porque el pago se había creado dentro de esa ventana (durante el setup). El test no demostraba que la función no lo modificó — solo que el pago se creó hace poco.

**Patrón correcto:** para verificar que un registro NO fue tocado por una operación, comparar `updated_at = created_at`. Esa igualdad es **independiente del tiempo de creación** y demuestra inequívocamente que ningún UPDATE corrió desde el INSERT inicial.

Aplicado en Verify 15.6-bis: confirmó `nunca_modificado: true` con timestamps idénticos al microsegundo (`2026-05-24 01:51:55.768927+00` en ambos campos). **Principio de diseño verificado al 100%: `cancelar_prereserva` no toca los pagos asociados.**

**Comportamiento clave del log:**
Las 2 entradas de `prereserva_cancelada` (id_log 10 y 11) contienen suficiente detalle para reportes operativos:
- Transición de estado (`estado_anterior` → `estado_nuevo`).
- Motivo de negocio.
- Conteo de pagos sin resolver (`pagos_asociados`).
- Descripción humana opcional.

Esto habilita queries futuras tipo "cancelaciones por motivo en último mes" o "cancelaciones con pagos pendientes de revisar". Los errores controlados NO generan log (diseño correcto).

**Decisión:** avanzar a Bloque 16 (`crear_bloqueo` — alto riesgo) en próxima sesión con cabeza fresca.

---

### Bloque 16 — Función `crear_bloqueo`

**Estado:** Cerrado. **Función operativa de gestión de disponibilidad.** Permite crear bloqueos específicos (1 cabaña) o totales (todas) con validaciones de conflicto contra reservas, pre-reservas y bloqueos existentes.

**SQL ejecutado:** Función `crear_bloqueo(payload JSONB) RETURNS JSONB` (~225 líneas). Implementa 5 secciones: extracción y validación de payload, locks (global siempre + por cabaña con `::INTEGER` si aplica), validaciones de conflicto en 2 ramas (específico vs total), INSERT con captura defensiva de `exclusion_violation`, log con `tipo_bloqueo` diferenciado.

**Documento usado:** `6B_SCHEMA_SQL.md v1.6`. El cast `::INTEGER` en `pg_advisory_xact_lock(1, v_id_cabana::INTEGER)` venía aplicado desde la corrección documental del Bloque 13.

**Resultado de ejecución:** `Success. No rows returned`.

**Verificaciones post-ejecución (12 pasos):**

| # | Test | Resultado esperado | Resultado obtenido |
|---|---|---|---|
| 16.1 | Función registrada | `crear_bloqueo, jsonb, VOLATILE, 1` | exacto ✓ |
| 16.2 | Setup en 5 pasos (2 cabañas, config, pre-reserva vigente en B, reserva confirmada en A, bloqueo previo en A diciembre) | id_cabana_A=10, id_cabana_B=11, pre_reserva 8 sobre B, reserva 3 sobre A (via confirmar_reserva), bloqueo 2 en A diciembre | exacto ✓ — setup atómico en pasos chicos |
| 16.3 | T-BL-1: Bloqueo específico OK en Cabaña A, septiembre (libre) | `ok:true, id_bloqueo:3, tipo_bloqueo:cabana_especifica` | exacto ✓ |
| 16.4 | T-BL-2: Bloqueo total OK en enero 2027 (libre) | `ok:true, id_bloqueo:4, id_cabana:null, tipo_bloqueo:total` | exacto ✓ |
| 16.5 | T-BL-3/4/5: errores de payload (UNION ALL) | `payload_invalido`, `fechas_invalidas`, `motivo_invalido` | exacto ✓ |
| 16.6 | T-BL-6: Conflicto con reserva (Cabaña A en noviembre) | `error:conflicto_con_reserva, reservas_en_conflicto:[3]` | exacto ✓ — ID operativo reportado |
| 16.7 | T-BL-7: Conflicto con pre-reserva (Cabaña B en octubre) | `error:conflicto_con_prereserva, prereservas_en_conflicto:[8], motivo:descriptivo` | exacto ✓ |
| 16.8 | T-BL-8: Bloqueo solapado (Cabaña A en diciembre) | `error:bloqueo_solapado, bloqueos_en_conflicto:[2], motivo:descriptivo` | exacto ✓ — incluye nota "(específico o total)" |
| 16.9 | T-BL-9: Cabaña inexistente | `error:cabana_no_existe` | exacto ✓ |
| 16.10 | Estado final tabla bloqueos | 3 bloqueos (id 2 setup, id 3 T-BL-1, id 4 T-BL-2). Tests rechazados no escribieron. | exacto ✓ |
| 16.11 | Logs (5: 3 de setup + 2 de bloqueos exitosos) | Logs con `tipo_bloqueo` diferenciado, `modificado_por` = creado_por del payload | exacto ✓ |
| 16.12 | Limpieza + sanity check global | 11 tablas en 0 | exacto ✓ |

**Comportamientos clave validados:**

1. **Diferenciación de flujos específico vs total:** La función bifurca correctamente según `id_cabana IS NULL`. El específico toma lock por cabaña con `::INTEGER` (corrección v1.6), valida solo en esa cabaña. El total no toma lock por cabaña, valida contra todas las cabañas.

2. **Detección de conflictos con IDs operativos:** Los 3 tipos de conflicto (`conflicto_con_reserva`, `conflicto_con_prereserva`, `bloqueo_solapado`) devuelven arrays con los IDs específicos del conflicto. Esto permite a n8n/operadores actuar quirúrgicamente (mover reserva específica, cancelar pre-reserva específica, etc.).

3. **Validaciones secuenciales con corte temprano:** Si una validación falla, las siguientes no se ejecutan. El JSON output contiene la **primera causa de conflicto encontrada**, no todas. Diseño correcto: operacionalmente se resuelve un problema a la vez.

4. **Motivos descriptivos en los conflictos:** Además del código de error y los IDs, los errores `conflicto_con_prereserva` y `bloqueo_solapado` incluyen un campo `motivo` con texto humano ("Cancelarlas antes de bloquear...", "Ya hay un bloqueo activo (específico o total)..."). Ayuda contextual para el usuario operativo.

5. **EXCLUDE constraint como red de seguridad:** El INSERT está envuelto en `BEGIN ... EXCEPTION WHEN exclusion_violation` aunque las validaciones manuales ya cubren todos los casos conocidos. Es defensa estructural residual para race conditions extremas o bugs no detectados.

**Decisión de diseño confirmada — Bloqueos totales sin LOCK TABLE:** La versión v1.4 eliminó el `LOCK TABLE bloqueos IN ACCESS EXCLUSIVE MODE` que antes se usaba para bloqueos totales. La serialización ahora pasa exclusivamente por el lock global de disponibilidad `pg_advisory_xact_lock(10, 0)`. Esto evita contención brusca contra otras operaciones de lectura mientras se valida un bloqueo total. Las validaciones manuales se mantienen.

**Detalle técnico — Lock por cabaña sobre cabaña inexistente:** En T-BL-9 la función toma el lock por cabaña `pg_advisory_xact_lock(1, 99999::INTEGER)` **antes** de verificar que la cabaña existe. Esto no es problema: los advisory locks son virtuales (solo identifican un número), no requieren que el registro físico exista, y se liberan al fin de la transacción. Mantener el orden uniforme "global → por cabaña → validar" simplifica el flujo sin penalización real.

**Diseño operativo del log — `modificado_por` con identidad humana:** A diferencia de otras funciones del schema donde `modificado_por` recibe el nombre de la función (ej. `crear_prereserva`, `confirmar_reserva`), `crear_bloqueo` usa el valor del campo `creado_por` del payload. Razón operativa: los bloqueos son acciones humanas explícitas (Vicky decide mantener una cabaña, Franco se queda una semana). Saber quién originó el bloqueo es más relevante que saber qué función lo procesó.

**Decisión:** avanzar a Bloque 17 (`registrar_pago`) en próxima sesión.

---

