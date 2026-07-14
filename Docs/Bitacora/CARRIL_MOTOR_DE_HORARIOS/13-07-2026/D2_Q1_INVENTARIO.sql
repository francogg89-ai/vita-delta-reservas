-- ====================================================================================
-- D2_Q1_INVENTARIO.sql
-- Bloque B1.3-consolidacion-canonica * D2 * inventario completo de los 7 objetos
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

-- Q1 -- INVENTARIO DE LOS 7 OBJETOS FUERA DEL PIN (N filas, 1 por firma viva).
--
--   METODO: el universo se arma por PRONAME, no por firma. Si la firma real en TEST
--   difiere de la presunta (derivada del repo), este bloque igual la encuentra y lo
--   reporta en la columna 'coincide_con_firma_esperada'. No se pierde ningun objeto
--   por haber asumido mal los argumentos.
--
--   md5_raw : md5(pg_get_functiondef(oid))                            -- pin del vivo
--   md5_lf  : md5(replace(pg_get_functiondef(oid), chr(13), ''))      -- pin del canonico LF-only
--   Ver D1_DECISION_FIDELIDAD_FUNCTIONDEF.md (opcion C adoptada).
WITH esperadas(pron, firma_esperada, artefacto_repo) AS (
  VALUES
    ('validar_estado_horario_final',     'public.validar_estado_horario_final(bigint,date)',     '04-07/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql'),
    ('validar_no_eventos_comprometidos', 'public.validar_no_eventos_comprometidos(bigint,date)', '04-07/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql'),
    ('validar_estado_override',          'public.validar_estado_override(bigint,date)',          '04-07/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql'),
    ('trg_guard_overrides',              'public.trg_guard_overrides()',                         '04-07/HORARIOS_GUARD_S1_TRIGGER_TEST.sql'),
    ('crear_override_horario',           'public.crear_override_horario(jsonb)',                 '04-07/HORARIOS_GUARD_S2_FUNCION_TEST.sql'),
    ('crear_bloqueo',                    'public.crear_bloqueo(jsonb)',                          'HORARIOS_B2_GUARD_HELPER_TEST.sql'),
    ('fecha_hoy_ar',                     'public.fecha_hoy_ar()',                                'HORARIOS_B2_GUARD_HELPER_TEST.sql')
)
SELECT
  'D2_Q1_INVENTARIO'                                          AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  p.oid                                                       AS oid,
  n.nspname                                                   AS schema,
  p.proname                                                   AS nombre,
  format('%I.%I(%s)', n.nspname, p.proname,
         pg_get_function_identity_arguments(p.oid))           AS firma_viva,
  e.firma_esperada                                            AS firma_esperada,
  (p.oid = to_regprocedure(e.firma_esperada)::oid)            AS coincide_con_firma_esperada,
  e.artefacto_repo                                            AS artefacto_repo,
  pg_get_function_arguments(p.oid)                            AS args_completos,
  pg_get_function_result(p.oid)                               AS retorno,
  pg_get_userbyid(p.proowner)                                 AS owner,
  l.lanname                                                   AS lenguaje,
  p.prokind                                                   AS prokind,
  CASE p.provolatile WHEN 'i' THEN 'IMMUTABLE'
                     WHEN 's' THEN 'STABLE'
                     WHEN 'v' THEN 'VOLATILE' END             AS volatilidad,
  CASE WHEN p.prosecdef THEN 'SECURITY DEFINER'
       ELSE 'SECURITY INVOKER' END                            AS security_mode,
  p.proisstrict                                               AS proisstrict,
  p.proleakproof                                              AS proleakproof,
  CASE p.proparallel WHEN 's' THEN 'SAFE'
                     WHEN 'r' THEN 'RESTRICTED'
                     WHEN 'u' THEN 'UNSAFE' END               AS parallel,
  COALESCE(array_to_string(p.proconfig, ' | '), '<null>')     AS proconfig,
  COALESCE(p.proacl::text,
           '<null> (= ACL por defecto: EXECUTE a PUBLIC)')    AS proacl,
  COALESCE(obj_description(p.oid, 'pg_proc'), '<sin comentario>') AS comentario,
  md5(pg_get_functiondef(p.oid))                              AS md5_raw,
  md5(replace(pg_get_functiondef(p.oid), chr(13), ''))        AS md5_lf,
  octet_length(pg_get_functiondef(p.oid))                     AS bytes_raw,
  octet_length(pg_get_functiondef(p.oid))
    - octet_length(replace(pg_get_functiondef(p.oid), chr(13), '')) AS cantidad_cr,
  CASE
    WHEN octet_length(pg_get_functiondef(p.oid))
         - octet_length(replace(pg_get_functiondef(p.oid), chr(13), '')) = 0
      THEN 'LF puro'
    ELSE 'CONTIENE CR -- EOL mixto o CRLF'
  END                                                         AS eol
FROM esperadas e
LEFT JOIN pg_proc      p  ON p.proname = e.pron
LEFT JOIN pg_namespace n  ON n.oid = p.pronamespace AND n.nspname = 'public'
LEFT JOIN pg_language  l  ON l.oid = p.prolang
WHERE p.oid IS NULL OR n.nspname = 'public'
ORDER BY e.pron, p.oid;

COMMIT;
