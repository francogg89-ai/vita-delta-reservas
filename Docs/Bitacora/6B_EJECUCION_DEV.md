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