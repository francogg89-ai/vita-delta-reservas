-- ====================================================================================
-- D2_Q2_PRESENCIA_Y_OVERLOADS.sql
-- Bloque B1.3-consolidacion-canonica * D2 * presencia / ausencia / overloads
-- ALCANCE: objetos del carril Motor de Horarios que quedaron FUERA del pin de 11 de S8.
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
      'GATE D2: ambiente=% (esperado test). Abortando.',
      COALESCE(v_amb, '<null>');
  END IF;
END
$gate$;

-- Q2 -- PRESENCIA, AUSENCIA Y OVERLOADS (7 filas, 1 por proname).
--   Responde: cada objeto existe? con cuantas firmas? coincide con la del repo?
WITH esperadas(pron, firma_esperada) AS (
  VALUES
    ('validar_estado_horario_final',     'public.validar_estado_horario_final(bigint,date)'),
    ('validar_no_eventos_comprometidos', 'public.validar_no_eventos_comprometidos(bigint,date)'),
    ('validar_estado_override',          'public.validar_estado_override(bigint,date)'),
    ('trg_guard_overrides',              'public.trg_guard_overrides()'),
    ('crear_override_horario',           'public.crear_override_horario(jsonb)'),
    ('crear_bloqueo',                    'public.crear_bloqueo(jsonb)'),
    ('fecha_hoy_ar',                     'public.fecha_hoy_ar()')
)
SELECT
  'D2_Q2_PRESENCIA_Y_OVERLOADS'                               AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  e.pron                                                      AS nombre,
  e.firma_esperada                                            AS firma_esperada,
  (to_regprocedure(e.firma_esperada) IS NOT NULL)             AS firma_esperada_existe,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = e.pron)       AS firmas_vivas,
  (SELECT string_agg(format('%I.%I(%s)', n.nspname, p.proname,
                            pg_get_function_identity_arguments(p.oid)), ' | ' ORDER BY p.oid)
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = e.pron)       AS todas_las_firmas,
  CASE
    WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public' AND p.proname = e.pron) = 0
      THEN '>>> AUSENTE EN TEST <<<'
    WHEN to_regprocedure(e.firma_esperada) IS NULL
      THEN '>>> PRESENTE PERO CON OTRA FIRMA -- revisar todas_las_firmas <<<'
    WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public' AND p.proname = e.pron) > 1
      THEN '>>> OVERLOAD: mas de una firma viva <<<'
    ELSE 'OK -- una sola firma, la esperada'
  END                                                         AS veredicto
FROM esperadas e
ORDER BY e.pron;

COMMIT;
