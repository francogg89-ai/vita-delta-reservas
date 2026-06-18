-- ============================================================================
-- PROMO_K1_DUMP_DIFERENCIAS_v2.sql  (SQL puro — sin \echo ni meta-comandos psql)
-- READ-ONLY. Correr en TEST y en OPS con NADA seleccionado; traer ambas salidas.
-- Dos result sets, una fila por objeto, para comparar TEST vs OPS lado a lado:
--   (1) FUNCION: las 4 funciones que difieren (atributos + cuerpo normalizado).
--   (2) TABLA  : las 4 tablas tempranas que difieren + 2 tablas 9H de control.
-- No prepara parches. Solo diagnóstico.
-- ============================================================================

-- ── (1) FUNCIONES — una fila por función ────────────────────────────────────
SELECT
  'FUNCION'                                                   AS seccion,
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

-- ── (2) TABLAS — una fila por tabla ─────────────────────────────────────────
SELECT
  'TABLA'                                                     AS seccion,
  c.relname                                                   AS tabla,
  pg_get_userbyid(c.relowner)                                 AS owner,
  COALESCE(c.relacl::text, 'NULL')                            AS relacl,
  COALESCE(
    (SELECT string_agg(g.rol || '=' || g.priv, ', ' ORDER BY g.rol, g.priv)
       FROM (
         SELECT CASE WHEN acl.grantee = 0 THEN 'PUBLIC'
                     ELSE pg_get_userbyid(acl.grantee) END AS rol,
                acl.privilege_type                          AS priv
         FROM aclexplode(c.relacl) acl
         WHERE acl.grantee = 0
            OR pg_get_userbyid(acl.grantee) IN ('anon','authenticated','service_role')
       ) g),
    '(sin grants a PUBLIC/anon/authenticated/service_role)')  AS grants_data_api
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos',
                    'liquidaciones_periodo','movimientos_socio')
ORDER BY c.relname;
