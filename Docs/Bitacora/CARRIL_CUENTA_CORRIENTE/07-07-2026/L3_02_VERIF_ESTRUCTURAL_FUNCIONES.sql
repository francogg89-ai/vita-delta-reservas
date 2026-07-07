-- ============================================================================
-- L3_02_VERIF_ESTRUCTURAL_FUNCIONES.sql   (READ-ONLY; una sola sentencia)
-- Verifica la estructura de las 2 funciones L3 recien creadas. NO escribe.
-- Naturaleza: WITH ... SELECT. Sin BEGIN/DO/DDL/DML. Grilla unica final.
-- Sirve igual en TEST y OPS (la estructura de la funcion es identica).
--
-- Chequea, por funcion, y con asercion OK/REVISAR:
--   * firma exacta (to_regprocedure)          * STABLE (provolatile='s')
--   * SECURITY INVOKER (prosecdef=false)       * search_path fijado (proconfig)
--   * retorno jsonb                            * proacl materializado (IS NOT NULL)
--   * 0 EXECUTE a PUBLIC/anon/authenticated/service_role
--
-- v2: SEARCH_PATH_FIJADO ahora valida el valor EXACTO (search_path=pg_catalog,
--     public, normalizado sin espacios); 'search_path=public' -> REVISAR.
-- ============================================================================
WITH
fn_esp(nombre, firma) AS (
  VALUES
    ('cuenta_corriente_historico',            'public.cuenta_corriente_historico(date)'),
    ('cuenta_corriente_historico_acumulados', 'public.cuenta_corriente_historico_acumulados()')
),
sensibles(rol) AS (VALUES ('public'),('anon'),('authenticated'),('service_role')),
fn AS (
  SELECT fe.nombre, fe.firma, to_regprocedure(fe.firma)::oid AS oid,
         p.provolatile, p.prosecdef, p.proconfig, p.proacl, p.prorettype
  FROM fn_esp fe
  LEFT JOIN pg_proc p ON p.oid = to_regprocedure(fe.firma)::oid
),
c_firma AS (
  SELECT f.nombre, 1 AS orden, 'FIRMA_EXACTA' AS chequeo,
         f.firma AS esperado,
         (CASE WHEN f.oid IS NULL THEN 'AUSENTE'
               ELSE 'args=(' || pg_get_function_identity_arguments(f.oid) || ') ret=' || pg_get_function_result(f.oid) END) AS actual,
         (CASE WHEN f.oid IS NULL THEN 'REVISAR' ELSE 'OK' END) AS estado
  FROM fn f
),
c_vol AS (
  SELECT f.nombre, 2, 'VOLATILIDAD_STABLE', 's (STABLE)',
         (CASE WHEN f.oid IS NULL THEN 'AUSENTE' ELSE f.provolatile::text END),
         (CASE WHEN f.provolatile = 's' THEN 'OK' ELSE 'REVISAR' END)
  FROM fn f
),
c_sec AS (
  SELECT f.nombre, 3, 'SECURITY_INVOKER', 'false (INVOKER)',
         (CASE WHEN f.oid IS NULL THEN 'AUSENTE' ELSE 'prosecdef=' || f.prosecdef::text END),
         (CASE WHEN f.oid IS NOT NULL AND f.prosecdef = false THEN 'OK' ELSE 'REVISAR' END)
  FROM fn f
),
c_sp AS (
  -- match EXACTO (normalizado sin espacios): search_path=pg_catalog,public.
  -- 'search_path=public' u otro valor -> REVISAR (no basta con que exista un SET).
  SELECT f.nombre, 4, 'SEARCH_PATH_FIJADO', 'search_path=pg_catalog, public (exacto)',
         (CASE WHEN f.oid IS NULL THEN 'AUSENTE'
               ELSE COALESCE((SELECT cfg FROM unnest(f.proconfig) cfg WHERE cfg LIKE 'search_path=%'), '(sin SET search_path)') END),
         (CASE WHEN f.oid IS NULL THEN 'REVISAR'
               WHEN replace((SELECT cfg FROM unnest(f.proconfig) cfg WHERE cfg LIKE 'search_path=%'), ' ', '')
                    = 'search_path=pg_catalog,public'
               THEN 'OK' ELSE 'REVISAR' END)
  FROM fn f
),
c_ret AS (
  SELECT f.nombre, 5, 'RETORNO_JSONB', 'jsonb',
         (CASE WHEN f.oid IS NULL THEN 'AUSENTE' ELSE format_type(f.prorettype, NULL) END),
         (CASE WHEN f.oid IS NOT NULL AND f.prorettype = 'jsonb'::regtype THEN 'OK' ELSE 'REVISAR' END)
  FROM fn f
),
c_acl AS (
  SELECT f.nombre, 6, 'PROACL_MATERIALIZADO', 'true (REVOKE aplicado)',
         (CASE WHEN f.oid IS NULL THEN 'AUSENTE' ELSE 'proacl_no_nulo=' || (f.proacl IS NOT NULL)::text END),
         (CASE WHEN f.oid IS NOT NULL AND f.proacl IS NOT NULL THEN 'OK' ELSE 'REVISAR' END)
  FROM fn f
),
c_exec AS (
  SELECT f.nombre, 7, 'EXECUTE_SENSIBLES', '0 (ni PUBLIC/anon/authenticated/service_role)',
         (CASE WHEN f.oid IS NULL THEN 'AUSENTE'
               ELSE 'execute_sensibles=' || COALESCE((SELECT count(*)::text FROM aclexplode(f.proacl) ax
                     WHERE ax.privilege_type = 'EXECUTE'
                       AND (CASE WHEN ax.grantee = 0 THEN 'public' ELSE ax.grantee::regrole::text END) IN (SELECT rol FROM sensibles)), '0') END),
         (CASE WHEN f.oid IS NULL THEN 'REVISAR'
               WHEN COALESCE((SELECT count(*) FROM aclexplode(f.proacl) ax
                     WHERE ax.privilege_type = 'EXECUTE'
                       AND (CASE WHEN ax.grantee = 0 THEN 'public' ELSE ax.grantee::regrole::text END) IN (SELECT rol FROM sensibles)), 0) = 0
               THEN 'OK' ELSE 'REVISAR' END)
  FROM fn f
),
todo AS (
  SELECT * FROM c_firma UNION ALL SELECT * FROM c_vol UNION ALL SELECT * FROM c_sec
  UNION ALL SELECT * FROM c_sp UNION ALL SELECT * FROM c_ret UNION ALL SELECT * FROM c_acl
  UNION ALL SELECT * FROM c_exec
)
SELECT nombre AS funcion, chequeo, esperado, actual, estado
FROM todo
ORDER BY nombre, orden;
