-- ============================================================================
-- PROMO_C_BLOQUE_H_FINGERPRINT.sql
-- Promocion Carril C a OPS - BLOQUE H.1: huella estructural de la infra del portal.
--
-- DOBLE CORRIDA (D-PROMO-08 / L-PROMO-04): correr el MISMO script en TEST y en OPS
-- y comparar las dos salidas. Si la fila TOTAL_PORTAL coincide -> paridad
-- estructural exacta. Si no, las filas por objeto localizan la diferencia.
-- NADA embebido especifico de un entorno (script 100% simetrico).
--
-- 100% READ-ONLY. Sin DDL, sin tablas temporales, sin comandos psql-meta.
-- Compara ESTRUCTURA, grants/RLS, funciones y comentarios; NUNCA datos:
--   SI: columnas (nombre+tipo+nullability), constraints (nombre+definicion),
--       indices (nombre+definicion), triggers no internos (nombre+definicion),
--       ACL de tabla, estado RLS (relrowsecurity/relforcerowsecurity) + policies,
--       comentarios de tabla y de cada columna; para la funcion: cuerpo completo
--       (pg_get_functiondef) + ACL + comentario.
--   NO: filas de portal_usuarios/portal_idempotencia, secretos, emails, uuids,
--       gastos reales, valores/uso de secuencias, marcador 'ambiente', fecha/hora,
--       ref del proyecto. Nada de eso entra al hash.
--
-- Objetos cubiertos (3 - infra del portal del Carril C):
--   tabla    portal_usuarios
--   tabla    portal_idempotencia
--   funcion  portal_cargar_gasto_interno(jsonb)
--
-- Determinismo entre entornos:
--   - sin OIDs en la salida;
--   - ACL (de tablas y funcion) por su texto, con los aclitems DESARMADOS y
--     ORDENADOS por texto: el mismo conjunto de grants en distinto orden de array
--     NO produce falso rojo. Usa nombres de rol y grantor (iguales en TEST/OPS,
--     dueno esperado postgres en ambos);
--   - la FUNCION se resuelve por FIRMA EXACTA via to_regprocedure('public.fn(jsonb)')
--     (no por nombre): un overload con otra firma no matchea; si la firma exacta no
--     existe en un entorno, la huella de la funcion es '<<AUSENTE>>' (el script no
--     lanza, asi la comparacion localiza la ausencia);
--   - roles de policies resueltos por NOMBRE (no OID); oid 0 -> 'PUBLIC';
--   - cuerpo de funcion y comentarios NORMALIZADOS quitando '\r' (TEST puede tener
--     \r\n y OPS \n - L-PROMO-01); de hecho se normaliza el blob completo de cada
--     objeto antes del md5, para que ninguna diferencia de EOL produzca falso rojo.
--
-- Correr con NADA seleccionado (L-8A-01: el SQL Editor de Supabase ejecuta solo
-- lo seleccionado; con nada seleccionado corre el script entero).
-- ============================================================================

WITH
portal_tabs(nom) AS (VALUES ('portal_usuarios'), ('portal_idempotencia')),
portal_fns(sig)  AS (VALUES ('public.portal_cargar_gasto_interno(jsonb)')),

-- == Manifiesto por TABLA del portal ========================================
tab_manifest AS (
  SELECT
    ct.nom,
    -- columnas: attnum|nombre|tipo|notnull (orden por attnum)
    COALESCE((SELECT string_agg(
                format('%s|%s|%s|%s', a.attnum, a.attname,
                       format_type(a.atttypid, a.atttypmod), a.attnotnull),
                E'\n' ORDER BY a.attnum)
              FROM pg_attribute a
              WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped), '') AS cols,
    -- constraints: nombre|definicion (orden por nombre)
    COALESCE((SELECT string_agg(
                format('%s|%s', con.conname, pg_get_constraintdef(con.oid)),
                E'\n' ORDER BY con.conname)
              FROM pg_constraint con WHERE con.conrelid = c.oid), '') AS cons,
    -- indices: nombre|definicion (orden por nombre)
    COALESCE((SELECT string_agg(
                format('%s|%s', i.indexname, i.indexdef),
                E'\n' ORDER BY i.indexname)
              FROM pg_indexes i
              WHERE i.schemaname = 'public' AND i.tablename = ct.nom), '') AS idx,
    -- triggers no internos: nombre|definicion (orden por nombre)
    COALESCE((SELECT string_agg(
                format('%s|%s', tg.tgname, pg_get_triggerdef(tg.oid)),
                E'\n' ORDER BY tg.tgname)
              FROM pg_trigger tg
              WHERE tg.tgrelid = c.oid AND NOT tg.tgisinternal), '') AS trg,
    -- ACL de la tabla (texto; 'NULL' explicito si sin grants)
    -- ACL: aclitems desarmados y ORDENADOS por texto (mismo grant en distinto
    -- orden de array NO debe producir falso rojo). 'NULL' explicito si sin grants.
    COALESCE((SELECT string_agg(ai::text, E'\n' ORDER BY ai::text)
              FROM unnest(c.relacl) AS ai), 'NULL') AS acl,
    -- estado RLS de la tabla
    format('rls=%s|force=%s', c.relrowsecurity, c.relforcerowsecurity) AS rls,
    -- policies RLS: nombre|cmd|permissive|roles(por nombre)|qual|withcheck
    COALESCE((SELECT string_agg(
                format('%s|%s|%s|%s|%s|%s',
                  pol.polname, pol.polcmd, pol.polpermissive,
                  COALESCE((SELECT string_agg(COALESCE(r.rolname, 'PUBLIC'), ',' ORDER BY 1)
                            FROM unnest(pol.polroles) AS pr(oid)
                            LEFT JOIN pg_roles r ON r.oid = pr.oid), ''),
                  COALESCE(pg_get_expr(pol.polqual, pol.polrelid), ''),
                  COALESCE(pg_get_expr(pol.polwithcheck, pol.polrelid), '')),
                E'\n' ORDER BY pol.polname)
              FROM pg_policy pol WHERE pol.polrelid = c.oid), '') AS pol,
    -- comentario de tabla
    COALESCE(obj_description(c.oid, 'pg_class'), 'NULL') AS com_tab,
    -- comentarios de columnas: nombre|comentario (orden por attnum)
    COALESCE((SELECT string_agg(
                format('%s|%s', a.attname, COALESCE(col_description(c.oid, a.attnum), 'NULL')),
                E'\n' ORDER BY a.attnum)
              FROM pg_attribute a
              WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped), '') AS com_cols
  FROM portal_tabs ct
  JOIN pg_class c     ON c.relname = ct.nom AND c.relkind = 'r'
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
),
tab_huellas AS (
  SELECT
    'tabla:' || nom AS objeto,
    md5(replace(
      'COLS'    || E'\n' || cols     || E'\n' ||
      'CONS'    || E'\n' || cons     || E'\n' ||
      'IDX'     || E'\n' || idx      || E'\n' ||
      'TRG'     || E'\n' || trg      || E'\n' ||
      'ACL'     || E'\n' || acl      || E'\n' ||
      'RLS'     || E'\n' || rls      || E'\n' ||
      'POL'     || E'\n' || pol      || E'\n' ||
      'COMTAB'  || E'\n' || com_tab  || E'\n' ||
      'COMCOLS' || E'\n' || com_cols
    , E'\r', '')) AS huella,
    '1_tabla_' || nom AS ord
  FROM tab_manifest
),

-- == Manifiesto por FUNCION del portal ======================================
fn_huellas AS (
  SELECT
    'func:' || pf.sig AS objeto,
    CASE
      WHEN p.oid IS NULL THEN '<<AUSENTE>>'   -- firma exacta no existe en este entorno
      ELSE md5(replace(
        pg_get_functiondef(p.oid)
        || E'\n--ACL--\n' ||
           -- ACL de la funcion: aclitems ORDENADOS por texto (mismo motivo que en tablas)
           COALESCE((SELECT string_agg(ai::text, E'\n' ORDER BY ai::text)
                     FROM unnest(p.proacl) AS ai), 'NULL')
        || E'\n--COMMENT--\n' || COALESCE(obj_description(p.oid, 'pg_proc'), 'NULL')
      , E'\r', ''))
    END AS huella,
    '2_func_' || pf.sig AS ord
  FROM portal_fns pf
  -- Resolucion por FIRMA EXACTA: to_regprocedure('public.fn(jsonb)') -> OID de esa
  -- firma, o NULL si no existe (no lanza). Un overload con otra firma NO matchea.
  LEFT JOIN pg_proc p ON p.oid = to_regprocedure(pf.sig)::oid
),

todo AS (
  SELECT objeto, huella, ord FROM tab_huellas
  UNION ALL
  SELECT objeto, huella, ord FROM fn_huellas
)
SELECT objeto, huella FROM todo
UNION ALL
-- Huella total: md5 del concatenado deterministico de todas las huellas por objeto.
SELECT 'TOTAL_PORTAL (' || count(*) || ' objetos)' AS objeto,
       md5(string_agg(huella, '|' ORDER BY ord)) AS huella
FROM todo
ORDER BY 1;
