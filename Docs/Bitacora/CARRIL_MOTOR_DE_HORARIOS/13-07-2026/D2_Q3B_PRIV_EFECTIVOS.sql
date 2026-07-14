-- ====================================================================================
-- D2_Q3B_PRIV_EFECTIVOS.sql
-- Bloque B1.3-consolidacion-canonica * D2 * privilegios efectivos anon/authenticated/service_role
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

-- Q3-BIS -- PRIVILEGIOS EFECTIVOS de los 3 roles de la Data API.
--   has_function_privilege resuelve herencia y PUBLIC: es la verdad operativa.
WITH objs AS (
  SELECT p.oid,
         format('%I.%I(%s)', n.nspname, p.proname,
                pg_get_function_identity_arguments(p.oid)) AS firma,
         p.proname
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
),
roles(rolname) AS (VALUES ('anon'),('authenticated'),('service_role'))
SELECT
  'D2_Q3B_PRIV_EFECTIVOS'                                   AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  o.firma                                                   AS firma,
  ro.rolname                                                AS rol,
  CASE
    WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ro.rolname) THEN NULL
    ELSE has_function_privilege(ro.rolname, o.oid, 'EXECUTE')
  END                                                       AS puede_ejecutar,
  CASE
    WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ro.rolname) THEN 'ROL INEXISTENTE'
    WHEN has_function_privilege(ro.rolname, o.oid, 'EXECUTE')
      THEN '>>> EXPUESTA -- REVISAR <<<'
    ELSE 'ok (revocada)'
  END                                                       AS veredicto
FROM objs o CROSS JOIN roles ro
ORDER BY o.proname, ro.rolname;

COMMIT;
