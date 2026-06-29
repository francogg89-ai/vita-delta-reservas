-- ============================================================================
-- BOOTSTRAP ENTORNO NUEVO v1.9.0 — 01_VERIFY: CIERRE DE PARTE B (read-only)
-- Criterios: checkpoint de F2 (reconstrucción DEV) + post-check de hardening del
--   motor (Bloque 23). 100% read-only (solo catálogos). Devuelve UNA fila.
-- ----------------------------------------------------------------------------
-- USO: SQL Editor del PROYECTO NUEVO, NADA seleccionado. Correr DESPUÉS del
--   Bloque 23 (fin de 01_BOOTSTRAP_PARTE_B_BASE.sql) y ANTES de la Parte C.
-- VEREDICTO: PARTE_B_OK (habilita 02_BOOTSTRAP) | PARTE_B_INCOMPLETA.
-- NOTA: en este punto config = 10 (las 10 claves del seed del Bloque 21). El
--   marcador 'ambiente' lo agrega C13.1 (Parte C) y lo lleva a 11 — todavía no.
-- HARDENING: las 13 funciones del motor deben quedar SIN EXECUTE a PUBLIC/anon/
--   authenticated/service_role. La trampa `proacl IS NULL ⇒ PUBLIC ejecuta`
--   (L-PROMO-06) se contempla: una función con proacl NULL cuenta como EXPUESTA.
--   Se excluyen funciones de extensión (btree_gist) por pg_depend deptype='e'.
-- ============================================================================
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
cron     AS (SELECT count(*) n FROM cron.job WHERE jobname IN ('expirar_prereservas','cleanup_cron_history')),
-- Hardening del motor: 13 funciones SIN EXECUTE a PUBLIC/anon/authenticated/service_role.
-- Trampa proacl IS NULL contemplada; extensiones excluidas (deptype='e').
motor_exec AS (
  SELECT count(*) n
  FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
  WHERE s.nspname='public'
    AND NOT EXISTS (SELECT 1 FROM pg_depend d
                    WHERE d.objid=p.oid AND d.classid='pg_proc'::regclass AND d.deptype='e')
    AND p.proname IN (
      'cancelar_prereserva','confirmar_reserva','crear_bloqueo','crear_prereserva',
      'expirar_prereservas_vencidas','log_cambio_estado','normalizar_telefono',
      'obtener_disponibilidad_rango','registrar_pago','set_telefono_normalizado',
      'set_updated_at','upsert_huesped','validar_disponibilidad')
    AND (
      p.proacl IS NULL
      OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                 WHERE a.privilege_type='EXECUTE'
                   AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role')))
    )
)
SELECT
  (SELECT n FROM ext)        AS extensiones,                 -- esperado 2
  (SELECT n FROM enums)      AS enums,                       -- esperado 4
  (SELECT n FROM tabs)       AS tablas,                      -- esperado 20
  (SELECT n FROM vistas)     AS vistas,                      -- esperado 6
  (SELECT n FROM funcs)      AS funciones_motor,             -- esperado 13
  (SELECT n FROM trigs)      AS triggers_no_internos,        -- esperado 13
  (SELECT n FROM excl)       AS exclude_constraints,         -- esperado 2
  (SELECT n FROM seed_cab)   AS cabanas,                     -- esperado 5
  (SELECT n FROM seed_soc)   AS socios,                      -- esperado 3
  (SELECT n FROM seed_cfg)   AS config,                      -- esperado 10 (sin 'ambiente' aún)
  (SELECT n FROM seed_cta)   AS cuentas_cobro,               -- esperado 1
  (SELECT n FROM seed_tmp)   AS temporadas,                  -- esperado 1
  (SELECT n FROM seed_pla)   AS plantillas,                  -- esperado 1
  (SELECT n FROM cron)       AS cron_jobs,                   -- esperado 2
  (SELECT n FROM motor_exec) AS funciones_motor_expuestas,   -- esperado 0
  CASE WHEN (SELECT n FROM ext)=2  AND (SELECT n FROM enums)=4  AND (SELECT n FROM tabs)=20
        AND (SELECT n FROM vistas)=6 AND (SELECT n FROM funcs)=13 AND (SELECT n FROM trigs)=13
        AND (SELECT n FROM excl)=2  AND (SELECT n FROM seed_cab)=5 AND (SELECT n FROM seed_soc)=3
        AND (SELECT n FROM seed_cfg)=10 AND (SELECT n FROM seed_cta)=1 AND (SELECT n FROM seed_tmp)=1
        AND (SELECT n FROM seed_pla)=1 AND (SELECT n FROM cron)=2
        AND (SELECT n FROM motor_exec)=0
       THEN 'PARTE_B_OK -> habilita 02_BOOTSTRAP_PARTE_C_CARRIL_B.sql'
       ELSE 'PARTE_B_INCOMPLETA -> revisar el conteo que no cuadra (motor_exec>0 = falta Bloque 23)'
  END AS veredicto;
