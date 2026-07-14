-- ====================================================================================
-- D1_Q7_S3_AUSENCIA.sql
-- Bloque B1.3-consolidacion-canonica * D1 * ausencia de S3 crear_paquete_dia_especial
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

-- Q7 -- S3 crear_paquete_dia_especial: AUSENCIA POR CUATRO VIAS (1 fila).
--   Debe estar AUSENTE: B1_3_F (crear_override_horario_puntual) la reemplazo con
--   DROP + CREATE, sin coexistencia.
--   NOTA: la ausencia en repo y en Workflows es un GATE EXTERNO (git grep), fuera de la DB.
SELECT
  'Q7_S3_AUSENCIA'                                                                AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL              AS v1_to_regprocedure_null,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname = 'crear_paquete_dia_especial')                               AS v2_pg_proc_filas,
  (SELECT count(*) FROM pg_depend d
     WHERE d.refclassid = 'pg_proc'::regclass
       AND d.refobjid = COALESCE(to_regprocedure('public.crear_paquete_dia_especial(jsonb)')::oid, 0)) AS v3_dependencias,
  (SELECT count(*) FROM (
      SELECT pg_get_functiondef(p.oid) AS cuerpo
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname='public' AND p.prokind IN ('f','p')
      UNION ALL SELECT definition FROM pg_views    WHERE schemaname='public'
      UNION ALL SELECT definition FROM pg_matviews WHERE schemaname='public'
   ) x WHERE x.cuerpo ~ '\mcrear_paquete_dia_especial\M')                         AS v4_callers_db_por_texto,
  CASE WHEN to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL
        AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE p.proname='crear_paquete_dia_especial') = 0
        AND (SELECT count(*) FROM (
                SELECT pg_get_functiondef(p.oid) AS cuerpo
                  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                 WHERE n.nspname='public' AND p.prokind IN ('f','p')
                UNION ALL SELECT definition FROM pg_views    WHERE schemaname='public'
                UNION ALL SELECT definition FROM pg_matviews WHERE schemaname='public'
             ) x WHERE x.cuerpo ~ '\mcrear_paquete_dia_especial\M') = 0
       THEN 'S3 AUSENTE EN DB -- OK (repo/workflows: gate externo)'
       ELSE '>>> S3 PRESENTE O REFERENCIADA EN DB -- INVESTIGAR <<<'
  END                                                                              AS veredicto;

COMMIT;
