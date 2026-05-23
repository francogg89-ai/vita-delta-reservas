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

