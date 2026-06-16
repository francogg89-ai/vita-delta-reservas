-- ============================================================================
-- RECONSTRUCCIÓN DE DEV — F5: BARRIDO GLOBAL DE PERMISOS (base + Carril B)
-- Proyecto: VITA_DELTA_DEV · DEV_REF: wsrdzjmvnzxidjlovlja · PG 17.6
-- ----------------------------------------------------------------------------
-- USO: SQL Editor del proyecto DEV nuevo, cada bloque por separado, con NADA
--      seleccionado. 100% read-only (solo lee catálogos).
--
-- OBJETIVO (corrección #5): detectar CUALQUIER exposición del schema —base +
--      Carril B— a PUBLIC/anon/authenticated/service_role, distinguiendo:
--        - AMPLIO  = SELECT/INSERT/UPDATE/DELETE (relaciones) o USAGE (secuencias)
--                    o EXECUTE (funciones)  -> exposición real, esperado 0
--        - residual aceptado = Dxtm (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) en
--                    tablas base, heredado del default de postgres; NO incluye
--                    r/a/w/d; NO se revoca (paridad OPS/TEST). Se REPORTA explícito.
--
-- NOTAS DE PRECISIÓN:
--   - Funciones: se contempla la trampa `proacl IS NULL ⇒ PUBLIC ejecuta`
--     (L-PROMO-06) y se EXCLUYEN funciones de extensión (btree_gist) por
--     pg_depend deptype='e' (si no, las ~188 de btree_gist darían falso positivo).
--   - Tablas/secuencias: relacl NULL ⇒ solo el owner (sin PUBLIC) ⇒ no expuesto.
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- S1 — VEREDICTO DE EXPOSICIÓN GLOBAL (read-only; una fila)
-- Esperado: relaciones_amplias=0, secuencias_expuestas=0, funciones_expuestas=0.
-- ────────────────────────────────────────────────────────────────────────────
WITH
broad_rel AS (
  SELECT count(*) AS n
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN LATERAL aclexplode(c.relacl) a
  WHERE n.nspname = 'public' AND c.relkind IN ('r','v')
    AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
    AND (a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
),
seq_exp AS (
  SELECT count(*) AS n
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN LATERAL aclexplode(c.relacl) a
  WHERE n.nspname = 'public' AND c.relkind = 'S'
    AND a.privilege_type IN ('USAGE','SELECT','UPDATE')
    AND (a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
),
func_exp AS (
  SELECT count(*) AS n
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND NOT EXISTS (  -- excluir funciones de extensión (btree_gist, etc.)
      SELECT 1 FROM pg_depend d
      WHERE d.objid = p.oid AND d.classid = 'pg_proc'::regclass AND d.deptype = 'e')
    AND (
      p.proacl IS NULL  -- trampa: NULL ⇒ PUBLIC ejecuta
      OR EXISTS (
        SELECT 1 FROM aclexplode(p.proacl) a
        WHERE a.privilege_type = 'EXECUTE'
          AND (a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role')))
    )
)
SELECT
  (SELECT n FROM broad_rel) AS relaciones_amplias,    -- esperado 0
  (SELECT n FROM seq_exp)   AS secuencias_expuestas,  -- esperado 0
  (SELECT n FROM func_exp)  AS funciones_expuestas,   -- esperado 0
  CASE WHEN (SELECT n FROM broad_rel) = 0
        AND (SELECT n FROM seq_exp)   = 0
        AND (SELECT n FROM func_exp)  = 0
       THEN 'SIN_EXPOSICION_AMPLIA -> schema base + Carril B cerrados'
       ELSE 'EXPOSICION_DETECTADA -> ver S2/S3 y decidir antes de cerrar'
  END AS veredicto;


-- ────────────────────────────────────────────────────────────────────────────
-- S2 — REPORTE EXPLÍCITO DEL RESIDUAL (read-only; 1–2 filas agregadas)
-- Agrupa toda concesión a PUBLIC/API sobre relaciones y secuencias.
-- Esperado: UNA sola fila 'residual_aceptado (Dxtm)' (las 20 tablas base + 6
-- vistas con Dxtm a anon/authenticated/service_role). Las 9 tablas Carril B NO
-- aparecen (REVOKE de C12). Si aparece una fila 'AMPLIO' -> exposición real.
-- ────────────────────────────────────────────────────────────────────────────
WITH grants AS (
  SELECT c.relkind, c.relname, a.grantee,
         string_agg(DISTINCT a.privilege_type, ',' ORDER BY a.privilege_type) AS privs,
         bool_or(a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','USAGE')) AS es_amplio
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN LATERAL aclexplode(c.relacl) a
  WHERE n.nspname = 'public' AND c.relkind IN ('r','v','S')
    AND (a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
  GROUP BY c.relkind, c.relname, a.grantee
)
SELECT
  CASE WHEN es_amplio THEN 'AMPLIO (EXPOSICION)' ELSE 'residual_aceptado (Dxtm)' END AS clase,
  count(*)                       AS pares_objeto_rol,
  count(DISTINCT relname)        AS objetos_distintos,
  string_agg(DISTINCT privs, ' | ' ORDER BY privs) AS sets_de_privilegios
FROM grants
GROUP BY es_amplio
ORDER BY es_amplio DESC;


-- ────────────────────────────────────────────────────────────────────────────
-- S3 — (OPCIONAL) Detalle objeto×rol del residual (read-only; muchas filas)
-- Correr solo si querés la evidencia fila por fila. Esperado: todas 'clase' =
-- residual_aceptado; ninguna SELECT/INSERT/UPDATE/DELETE/USAGE/EXECUTE.
-- ────────────────────────────────────────────────────────────────────────────
SELECT
  CASE c.relkind WHEN 'r' THEN 'tabla' WHEN 'v' THEN 'vista' WHEN 'S' THEN 'secuencia' END AS tipo,
  c.relname AS objeto,
  pg_get_userbyid(a.grantee) AS rol,
  string_agg(DISTINCT a.privilege_type, ',' ORDER BY a.privilege_type) AS privilegios,
  CASE WHEN bool_or(a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','USAGE'))
       THEN 'AMPLIO' ELSE 'residual_aceptado' END AS clase
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(c.relacl) a
WHERE n.nspname = 'public' AND c.relkind IN ('r','v','S')
  AND (a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
GROUP BY c.relkind, c.relname, a.grantee
ORDER BY clase DESC, tipo, objeto, rol;
