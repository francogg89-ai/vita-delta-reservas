# F2 — Ejecución de Parte B (schema base) · Runsheet

**Proyecto:** `VITA_DELTA_DEV` · **DEV_REF:** `wsrdzjmvnzxidjlovlja` · **PG 17.6**
**Fuente de SQL:** `6B_SCHEMA_SQL.md` **v1.8.0**, sección **PARTE B** (Bloques 1→22)
**Estado de entrada:** F1 cerrado (base vacía, switches cerrados, extensiones disponibles, roles API presentes).

> Este runsheet **orquesta**, no re-emite SQL. Cada bloque se **copia del canónico** (Parte B). No re-tipear desde otra fuente: el canónico es la fuente de verdad; re-emitirlo arriesga drift.

---

## Reglas de ejecución

1. SQL Editor del **proyecto DEV nuevo** (confirmar `DEV_REF` en la URL, nunca `lpiatqztudxiwdlcoasv` = OPS).
2. **Un bloque por vez, con NADA seleccionado** (L-8A-01: el editor corre solo lo resaltado).
3. Correr la **"Verificación post-ejecución"** que trae el propio bloque en el canónico **antes** de pasar al siguiente.
4. Si un bloque falla → **parar y diagnosticar**, no continuar. Cada bloque trae su rollback en el canónico.
5. **F2 NO toca el Carril B.** Las columnas de `cabanas` del Carril B, zonas, activaciones, gastos_internos, 9H, seam, matriz, cascada y el marcador `ambiente='dev'` son **F3 / Parte C**.

---

## Orden de bloques (1 → 22)

| # | Bloque (canónico) | Qué deja | Verificación |
|---|---|---|---|
| 1 | Extensiones | `btree_gist` + `pg_cron` | 2 filas en `pg_extension` |
| 2 | Enums | 4 enums (`estado_prereserva/reserva/pago_enum`, `nivel_log_enum`) | la del bloque |
| 3 | Tablas catálogo | `cabanas`, `socios`, `cuentas_cobro`, `temporadas`, `feriados`, `tarifas`, `plantillas_mensajes`… | la del bloque |
| 4 | Tablas de configuración | `configuracion_general`, `descuentos`, `overrides_operativos`… | la del bloque |
| 5 | Tablas dependientes N1 | `huespedes`, `consultas`, `eventos_especiales`, `paquetes_evento`… | la del bloque |
| 6 | Tablas transaccionales | `pre_reservas`, `reservas`, `pagos`, `bloqueos` | la del bloque |
| 7 | Tabla de auditoría | `log_cambios` | la del bloque |
| 8 | Constraints EXCLUDE | 2 EXCLUDE (`reservas`, `bloqueos`) | la del bloque |
| 9 | `normalizar_telefono` + columna + trigger | 1ª función + `trg_huespedes_telefono_norm` | la del bloque |
| 10 | `upsert_huesped` | función | la del bloque |
| 11 | `validar_disponibilidad` | función | la del bloque |
| 12 | `obtener_disponibilidad_rango` | función | la del bloque |
| 13 | `crear_prereserva` (puerta única) | función · **cast `::INTEGER` del advisory lock ya incluido (v1.6+)** | la del bloque |
| 14 | `confirmar_reserva` | función · lock global antes del `FOR UPDATE` (v1.5) | la del bloque |
| 15 | `cancelar_prereserva` | función | la del bloque |
| 16 | `crear_bloqueo` | función · cast `::INTEGER` ya incluido | la del bloque |
| 17 | `registrar_pago` | función | la del bloque |
| 18 | `expirar_prereservas_vencidas` | función | la del bloque |
| 19 | Triggers automáticos | resto de triggers (`updated_at` ×9, `log_*_estado` ×3) → **13 no-internos en total** | la del bloque |
| 20 | Vistas SQL | 6 vistas (horizonte leído de `configuracion_general`, D-7A-03) | la del bloque |
| 21 | Datos seed mínimos | cabañas 5 / socios 3 (**Remo real**) / config 10 / cuenta 1 (placeholder) / temporada 1 / plantilla 1 | **5/3/10/1/1/1** |
| 22 | Schedule pg_cron | 2 jobs (`expirar_prereservas`, `cleanup_cron_history`) | 2 filas `active=TRUE` |

---

## Gotchas ya resueltos en el canónico (solo para saber; no hay que hacer nada)

- **Bloques 13/14/16 — advisory lock por cabaña:** el cast `::INTEGER` ya está en el canónico desde v1.6. No vas a ver `pg_advisory_xact_lock(integer, bigint) does not exist`.
- **Bloque 21 — seed:** `socios = 3` con **Remo real** (dejó de ser placeholder `Socio 3`, D-PROMO v1.8.0). Esto es **prerrequisito** del backfill de beneficiarios por nombre de C13 (Parte C). La cuenta de cobro nace **inactiva** (placeholder) y la temporada baseline es **solo para DEV** (evita gaps de precio), no productiva.
- **Bloque 22 — pg_cron:** P2 confirmó `pg_cron` disponible (1.6.4) → **procede normal**. Si en algún proyecto futuro no estuviera disponible, este bloque se omite/maneja; acá no es el caso.

---

## Checkpoint de cierre de Parte B (READ-ONLY)

Correr **después del Bloque 22**, con nada seleccionado. Es read-only (solo cuenta). Confirma el inventario base **equivalente al bootstrap de OPS (8A)** antes de pasar a Parte C.

```sql
-- CHECKPOINT FIN DE PARTE B (read-only). Habilita F3 si veredicto = PARTE_B_OK.
WITH
ext      AS (SELECT count(*) n FROM pg_extension WHERE extname IN ('btree_gist','pg_cron')),
enums    AS (SELECT count(*) n FROM pg_type t JOIN pg_namespace s ON s.oid=t.typnamespace
              WHERE s.nspname='public' AND t.typtype='e'),
tabs     AS (SELECT count(*) n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
              WHERE s.nspname='public' AND c.relkind='r'),
vistas   AS (SELECT count(*) n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
              WHERE s.nspname='public' AND c.relkind='v'),
funcs    AS (SELECT count(*) n FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
              WHERE s.nspname='public' AND p.proname IN (
                'cancelar_prereserva','confirmar_reserva','crear_bloqueo','crear_prereserva',
                'expirar_prereservas_vencidas','log_cambio_estado','normalizar_telefono',
                'obtener_disponibilidad_rango','registrar_pago','set_telefono_normalizado',
                'set_updated_at','upsert_huesped','validar_disponibilidad')),
trigs    AS (SELECT count(*) n FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
              JOIN pg_namespace s ON s.oid=c.relnamespace
              WHERE s.nspname='public' AND NOT t.tgisinternal),
excl     AS (SELECT count(*) n FROM pg_constraint con JOIN pg_namespace s ON s.oid=con.connamespace
              WHERE s.nspname='public' AND con.contype='x'),
seed_cab AS (SELECT count(*) n FROM cabanas),
seed_soc AS (SELECT count(*) n FROM socios),
seed_cfg AS (SELECT count(*) n FROM configuracion_general),
seed_cta AS (SELECT count(*) n FROM cuentas_cobro),
seed_tmp AS (SELECT count(*) n FROM temporadas),
seed_pla AS (SELECT count(*) n FROM plantillas_mensajes),
cron     AS (SELECT count(*) n FROM cron.job WHERE jobname IN ('expirar_prereservas','cleanup_cron_history'))
SELECT
  (SELECT n FROM ext)      AS extensiones,            -- esperado 2
  (SELECT n FROM enums)    AS enums,                  -- esperado 4
  (SELECT n FROM tabs)     AS tablas,                 -- esperado 20
  (SELECT n FROM vistas)   AS vistas,                 -- esperado 6
  (SELECT n FROM funcs)    AS funciones_motor,        -- esperado 13
  (SELECT n FROM trigs)    AS triggers_no_internos,   -- esperado 13
  (SELECT n FROM excl)     AS exclude_constraints,    -- esperado 2
  (SELECT n FROM seed_cab) AS cabanas,                -- esperado 5
  (SELECT n FROM seed_soc) AS socios,                 -- esperado 3
  (SELECT n FROM seed_cfg) AS config,                 -- esperado 10
  (SELECT n FROM seed_cta) AS cuentas_cobro,          -- esperado 1
  (SELECT n FROM seed_tmp) AS temporadas,             -- esperado 1
  (SELECT n FROM seed_pla) AS plantillas,             -- esperado 1
  (SELECT n FROM cron)     AS cron_jobs,              -- esperado 2
  CASE WHEN (SELECT n FROM ext)=2  AND (SELECT n FROM enums)=4  AND (SELECT n FROM tabs)=20
        AND (SELECT n FROM vistas)=6 AND (SELECT n FROM funcs)=13 AND (SELECT n FROM trigs)=13
        AND (SELECT n FROM excl)=2  AND (SELECT n FROM seed_cab)=5 AND (SELECT n FROM seed_soc)=3
        AND (SELECT n FROM seed_cfg)=10 AND (SELECT n FROM seed_cta)=1 AND (SELECT n FROM seed_tmp)=1
        AND (SELECT n FROM seed_pla)=1 AND (SELECT n FROM cron)=2
       THEN 'PARTE_B_OK -> habilita F3 (Parte C)'
       ELSE 'PARTE_B_INCOMPLETA -> revisar el bloque cuyo conteo no cuadra'
  END AS veredicto;
```

**Nota:** `config = 10` es correcto en este punto (las 10 claves del seed). El marcador `ambiente='dev'` lo agrega **C13.1 en Parte C** y lo llevará a 11 — todavía no.

---

## Qué NO hace F2 (para que no haya ambigüedad)

- No crea objetos del Carril B (9 tablas, 21 funciones, 10 triggers, 6 secuencias).
- No siembra beneficiarios, `valor_relativo`, zonas, `cabana_zona` ni activaciones.
- No setea `configuracion_general('ambiente') = 'dev'`.
- No aplica el `NOT NULL` de las columnas Carril B de `cabanas` (eso es C13.4, post-backfill).

Todo eso es **F3 (Parte C, C0→C14)**, que preparo cuando el checkpoint dé `PARTE_B_OK`.
