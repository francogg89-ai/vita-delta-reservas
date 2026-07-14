-- ====================================================================================
-- D2_Q4_TRIGGER_OV_GUARD.sql
-- Bloque B1.3-consolidacion-canonica * D2 * trigger trg_ov_guard sobre overrides_operativos
-- ALCANCE: objetos del carril Motor de Horarios que quedaron FUERA del pin de 11 de S8.
-- TEST unicamente. 100% LECTURA. Autocontenido: trae su propio gate y su propia
-- transaccion READ ONLY. No se puede ejecutar esta Q sin el gate: el archivo ES la Q.
-- Repo de referencia: HEAD 07fea85802bc4fccbff1236813593762aefe58d9
--
-- v2 -- El predicado del veredicto pasa a ser IDENTICO al de Q7. La v1 emitia
--       on_truncate como columna pero NO lo exigia en el CASE, y tampoco exigia
--       NOT INSTEAD OF. Q4 y Q7 podian discrepar sobre el mismo trigger.
--       AHORA ambas comparten los 13 requisitos: fn por OID, tabla, schema, AFTER,
--       INSERT+UPDATE+DELETE, NOT TRUNCATE, FOR EACH ROW, no INSTEAD OF, CONSTRAINT,
--       DEFERRABLE, INITIALLY DEFERRED, enabled.
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
      'GATE D2: ambiente=% (esperado test). Abortando.',
      COALESCE(v_amb, '<null>');
  END IF;
END
$gate$;

-- Q4 -- TRIGGER trg_ov_guard (N filas).
--
--   Este trigger NUNCA fue consultado por el D1: Q4 de D1 solo buscaba los triggers de
--   vigencias. Es el hueco principal que motiva el D2.
--
--   Esperado (segun 04-07/HORARIOS_GUARD_S1_TRIGGER_TEST.sql, lineas 152-155):
--     CREATE CONSTRAINT TRIGGER trg_ov_guard
--       AFTER INSERT OR UPDATE OR DELETE ON overrides_operativos
--       DEFERRABLE INITIALLY DEFERRED
--       FOR EACH ROW
--   trigger-fn: public.trg_guard_overrides()
--
--   La comparacion de la trigger-fn es POR OID, no por texto: regprocedure::text omite
--   el schema cuando el objeto es visible en el search_path.
SELECT
  'D2_Q4_TRIGGER_OV_GUARD'                             AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  t.oid                                                AS trigger_oid,
  t.tgname                                             AS trigger_name,
  ns.nspname                                           AS schema,
  c.relname                                            AS tabla,
  format('%I.%I(%s)', pn.nspname, p.proname,
         pg_get_function_identity_arguments(p.oid))    AS trigger_fn,
  (p.oid = to_regprocedure('public.trg_guard_overrides()')::oid) AS fn_es_trg_guard_overrides,
  -- eventos (tgtype bitmask): 1=ROW, 2=BEFORE, 4=INSERT, 8=DELETE, 16=UPDATE, 32=TRUNCATE, 64=INSTEAD
  (t.tgtype::int & 4)  <> 0                            AS on_insert,
  (t.tgtype::int & 8)  <> 0                            AS on_delete,
  (t.tgtype::int & 16) <> 0                            AS on_update,
  (t.tgtype::int & 32) <> 0                            AS on_truncate,
  (t.tgtype::int & 1)  <> 0                            AS for_each_row,
  CASE WHEN (t.tgtype::int & 64) <> 0 THEN 'INSTEAD OF'
       WHEN (t.tgtype::int & 2)  <> 0 THEN 'BEFORE'
       ELSE 'AFTER' END                                AS momento,
  (t.tgconstraint <> 0)                                AS es_constraint_trigger,
  t.tgdeferrable                                       AS es_deferrable,
  t.tginitdeferred                                     AS initially_deferred,
  t.tgenabled                                          AS tgenabled_raw,
  (t.tgenabled = 'O')                                  AS enabled_origin,
  pg_get_triggerdef(t.oid, true)                       AS triggerdef,
  md5(pg_get_triggerdef(t.oid, true))                  AS fingerprint_triggerdef,
  COALESCE(obj_description(t.oid, 'pg_trigger'), '<sin comentario>') AS comentario,
  CASE
    WHEN t.tgname = 'trg_ov_guard'
         AND ns.nspname = 'public' AND c.relname = 'overrides_operativos'
         AND p.oid = to_regprocedure('public.trg_guard_overrides()')::oid
         AND t.tgconstraint <> 0            -- CONSTRAINT TRIGGER
         AND t.tgdeferrable                 -- DEFERRABLE
         AND t.tginitdeferred               -- INITIALLY DEFERRED
         AND t.tgenabled = 'O'              -- enabled (origin)
         AND (t.tgtype::int &  4) <> 0      -- INSERT
         AND (t.tgtype::int &  8) <> 0      -- DELETE
         AND (t.tgtype::int & 16) <> 0      -- UPDATE
         AND (t.tgtype::int & 32) =  0      -- NOT TRUNCATE
         AND (t.tgtype::int &  1) <> 0      -- FOR EACH ROW
         AND (t.tgtype::int &  2) =  0      -- AFTER (no BEFORE)
         AND (t.tgtype::int & 64) =  0      -- no INSTEAD OF
      THEN 'OK -- exacto y bien configurado (AFTER I/U/D, no TRUNCATE, FOR EACH ROW, no INSTEAD OF, constraint, deferrable, initially deferred, enabled)'
    WHEN t.tgname = 'trg_ov_guard'
      THEN '>>> NOMBRE ESPERADO PERO CONFIGURACION DISTINTA -- revisar columnas <<<'
    ELSE '>>> TRIGGER NO ESPERADO EN ESTE UNIVERSO <<<'
  END                                                  AS veredicto
FROM pg_trigger t
JOIN pg_class     c  ON c.oid  = t.tgrelid
JOIN pg_namespace ns ON ns.oid = c.relnamespace
JOIN pg_proc      p  ON p.oid  = t.tgfoid
JOIN pg_namespace pn ON pn.oid = p.pronamespace
WHERE NOT t.tgisinternal
  AND (
        t.tgname = 'trg_ov_guard'
     OR p.oid = to_regprocedure('public.trg_guard_overrides()')::oid
     OR c.relname = 'overrides_operativos'
      )
ORDER BY t.tgname;

COMMIT;
