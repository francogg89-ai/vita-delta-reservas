-- ============================================================================
-- PROMO_K1_DUMP_FUNCIONES.sql  (SQL puro, UN solo SELECT — sale completo en Supabase)
-- READ-ONLY. Correr en TEST y en OPS con NADA seleccionado; traer ambas salidas.
-- Una fila por función (las 4 que difieren). Para comparar TEST vs OPS.
-- ============================================================================
SELECT
  p.proname                                                   AS objeto,
  pg_get_function_identity_arguments(p.oid)                   AS firma,
  CASE p.provolatile WHEN 'i' THEN 'IMMUTABLE'
                     WHEN 's' THEN 'STABLE'
                     WHEN 'v' THEN 'VOLATILE' END             AS volatilidad,
  CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END     AS security,
  COALESCE(array_to_string(p.proconfig, ', '), '(none)')      AS search_path,
  COALESCE(p.proacl::text, 'NULL')                            AS acl,
  replace(pg_get_functiondef(p.oid), E'\r', '')               AS definicion
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('resolver_beneficiario','matriz_participacion',
                    'repartir_por_matriz','detalle_participacion')
ORDER BY p.proname;
