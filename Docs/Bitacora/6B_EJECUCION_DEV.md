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