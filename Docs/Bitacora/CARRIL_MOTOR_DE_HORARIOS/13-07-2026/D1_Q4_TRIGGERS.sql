-- ====================================================================================
-- D1_Q4_TRIGGERS.sql
-- Bloque B1.3-consolidacion-canonica * D1 * triggers trg_vig_guard / trg_vig_guard_detalle
-- TEST unicamente. 100% LECTURA. Autocontenido: trae su propio gate y su propia
-- transaccion READ ONLY. No se puede ejecutar esta Q sin el gate: el archivo ES la Q.
-- Repo de referencia: HEAD 07fea85802bc4fccbff1236813593762aefe58d9
-- ====================================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog, public;

DO $gate$
DECLARE
  v_amb text := (
    SELECT valor
    FROM public.configuracion_general
    WHERE clave = 'ambiente'
  );
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION
      'GATE D1: ambiente=% (esperado test). Abortando.',
      COALESCE(v_amb, '<null>');
  END IF;
END
$gate$;

-- Q4 -- TRIGGERS (N filas).
--   El baseline b4e48e... de S8 es de la FUNCION trg_guard_vigencias(), no de estas
--   definiciones. Las definiciones de trigger NO tienen baseline en S8: se miden aca
--   por primera vez con pg_get_triggerdef().
--
--   Esperado (segun B1_3_A_MIGRACION_SEMANAL_TEST.sql):
--     trg_vig_guard          -> public.vigencias_horario_base
--     trg_vig_guard_detalle  -> public.vigencias_horario_detalle
--   Ambos CONSTRAINT TRIGGER, DEFERRABLE INITIALLY DEFERRED, enabled, compartiendo
--   la trigger-fn public.trg_guard_vigencias().
SELECT
  'Q4_TRIGGERS'                                        AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  t.oid                                                AS trigger_oid,
  t.tgname                                             AS trigger_name,
  ns.nspname                                           AS schema,
  c.relname                                            AS tabla,
  format('%I.%I(%s)', pn.nspname, p.proname,
         pg_get_function_identity_arguments(p.oid))    AS trigger_fn,
  (p.oid = to_regprocedure('public.trg_guard_vigencias()')::oid) AS fn_es_trg_guard_vigencias,
  (t.tgconstraint <> 0)                                AS es_constraint_trigger,
  t.tgdeferrable                                       AS es_deferrable,
  t.tginitdeferred                                     AS initially_deferred,
  t.tgenabled                                          AS tgenabled_raw,
  (t.tgenabled = 'O')                                  AS enabled_origin,
  pg_get_triggerdef(t.oid, true)                       AS triggerdef,
  md5(pg_get_triggerdef(t.oid, true))                  AS fingerprint_triggerdef,
  COALESCE(obj_description(t.oid, 'pg_trigger'), '<sin comentario>') AS comentario,
  CASE
    WHEN t.tgname = 'trg_vig_guard'
         AND ns.nspname = 'public' AND c.relname = 'vigencias_horario_base'
         AND p.oid = to_regprocedure('public.trg_guard_vigencias()')::oid
         AND t.tgconstraint <> 0 AND t.tgdeferrable AND t.tginitdeferred AND t.tgenabled = 'O'
      THEN 'OK -- exacto y bien configurado'
    WHEN t.tgname = 'trg_vig_guard_detalle'
         AND ns.nspname = 'public' AND c.relname = 'vigencias_horario_detalle'
         AND p.oid = to_regprocedure('public.trg_guard_vigencias()')::oid
         AND t.tgconstraint <> 0 AND t.tgdeferrable AND t.tginitdeferred AND t.tgenabled = 'O'
      THEN 'OK -- exacto y bien configurado'
    WHEN t.tgname IN ('trg_vig_guard','trg_vig_guard_detalle')
      THEN '>>> NOMBRE ESPERADO PERO CONFIGURACION INCORRECTA <<<'
    ELSE '>>> TRIGGER NO ESPERADO <<<'
  END                                                  AS veredicto
FROM pg_trigger t
JOIN pg_class     c  ON c.oid  = t.tgrelid
JOIN pg_namespace ns ON ns.oid = c.relnamespace
JOIN pg_proc      p  ON p.oid  = t.tgfoid
JOIN pg_namespace pn ON pn.oid = p.pronamespace
WHERE NOT t.tgisinternal
  AND (
        p.oid = to_regprocedure('public.trg_guard_vigencias()')::oid
     OR t.tgname IN ('trg_vig_guard','trg_vig_guard_detalle')
      )
ORDER BY t.tgname;

COMMIT;
