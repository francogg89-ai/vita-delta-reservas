-- ====================================================================================
-- D2_Q3_ACL.sql
-- Bloque B1.3-consolidacion-canonica * D2 * ACL expandida
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

-- Q3 -- ACL EXPANDIDA (N filas).
--   COALESCE(proacl, acldefault('f', proowner)): sin esto, un objeto sin hardening
--   (proacl IS NULL) se veria como "sin grants" cuando en realidad tiene EXECUTE a PUBLIC.
SELECT
  'D2_Q3_ACL'                                                         AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  format('%I.%I(%s)', n.nspname, p.proname,
         pg_get_function_identity_arguments(p.oid))                   AS firma,
  CASE WHEN a.grantee = 0 THEN 'PUBLIC'
       ELSE COALESCE(pg_get_userbyid(a.grantee), '<oid ' || a.grantee || '>') END AS grantee,
  pg_get_userbyid(a.grantor)                                          AS grantor,
  a.privilege_type                                                    AS privilegio,
  a.is_grantable                                                      AS grantable,
  CASE
    WHEN a.grantee = 0 AND a.privilege_type = 'EXECUTE'
      THEN '>>> EXECUTE A PUBLIC -- SIN HARDENING <<<'
    WHEN COALESCE(pg_get_userbyid(a.grantee),'') IN ('anon','authenticated','service_role')
         AND a.privilege_type = 'EXECUTE'
      THEN '>>> EXECUTE A ROL DATA API -- REVISAR <<<'
    ELSE 'ok'
  END                                                                 AS veredicto
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
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
ORDER BY p.proname, grantee, a.privilege_type;

COMMIT;
