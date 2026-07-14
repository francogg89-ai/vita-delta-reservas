-- ====================================================================================
-- D2_Q5_CUERPOS.sql
-- Bloque B1.3-consolidacion-canonica * D2 * cuerpos completos pg_get_functiondef
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

-- Q5 -- CUERPOS COMPLETOS pg_get_functiondef() (N filas).
--   EXPORTAR A CSV. No copiar a mano.
--   Necesarios para consolidar estos objetos en el canonico v1.13.0 desde el VIVO,
--   no desde los artefactos del repo (cuyos scripts ya no son re-ejecutables: sus
--   gates esperan el resolver viejo 58d75c1b, y el vivo es 1bd96c89).
SELECT
  'D2_Q5_CUERPOS'                                       AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  format('%I.%I(%s)', n.nspname, p.proname,
         pg_get_function_identity_arguments(p.oid))     AS firma,
  md5(pg_get_functiondef(p.oid))                        AS md5_raw,
  md5(replace(pg_get_functiondef(p.oid), chr(13), ''))  AS md5_lf,
  octet_length(pg_get_functiondef(p.oid))               AS bytes,
  octet_length(pg_get_functiondef(p.oid))
    - octet_length(replace(pg_get_functiondef(p.oid), chr(13), '')) AS cantidad_cr,
  pg_get_functiondef(p.oid)                             AS functiondef_completo
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'validar_estado_horario_final',
    'validar_no_eventos_comprometidos',
    'validar_estado_override',
    'trg_guard_overrides',
    'crear_override_horario',
    'crear_bloqueo',
    'fecha_hoy_ar'
  )
ORDER BY p.proname, p.oid;

COMMIT;
