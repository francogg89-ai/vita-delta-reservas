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