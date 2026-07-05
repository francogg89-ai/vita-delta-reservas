-- ============================================================================
-- CC_RETIRO_SB0_A0_DIAG_OPS.sql  --  Bloque A / A0: diagnostico READ-ONLY previo al SB0 en OPS.
--
-- SOLO SELECT. Sin DDL, sin escrituras, sin nextval => 0-write / 0-sequence. Seguro en OPS.
-- A0 es PREVIO al SB0: portal_usuarios.id_socio TODAVIA NO existe. Por eso D1/D3/GATE NO
-- referencian esa columna (el diagnostico de match no la necesita); SOLO D0 informa si ya existe.
-- Los id_socio que si aparecen son de la tabla socios (su PK, siempre presente).
-- Espeja EXACTAMENTE el match del backfill SB0: lower(btrim(nombre)) en AMBOS lados, contra
-- TODOS los socios (el backfill NO filtra por activo). El SQL Editor de Supabase muestra solo
-- el ULTIMO result set: correr todo el archivo => se ve el GATE; para ver D0..D3, seleccionar
-- y correr cada SELECT.
--
-- REGLA: avanzar a A1 (dry-run DDL con rollback) SOLO si el GATE da los 4 chequeos criticos en
-- PASS. Si alguno da FAIL -> STOP y resolver nombres en socios/portal_usuarios antes de tocar DDL.
-- ============================================================================


-- ---- D0: DRIFT -- la columna id_socio ya existe en OPS?  (0 = SB0 no aplicado, esperado;
--                   1 = ya aplicado/parcial -> A1/A2 abortarian por su preflight, revisar).
SELECT count(*) AS id_socio_ya_existe
FROM pg_attribute
WHERE attrelid = 'public.portal_usuarios'::regclass
  AND attname  = 'id_socio'
  AND NOT attisdropped;


-- ---- D1: portal_usuarios rol='socio' (nombre, user_id, activo, normalizado).
--          NO referencia id_socio (no existe pre-SB0; D0 informa su existencia).
SELECT nombre,
       rol,
       user_id,
       activo,
       lower(btrim(nombre)) AS nombre_norm
FROM public.portal_usuarios
WHERE rol = 'socio'
ORDER BY nombre;


-- ---- D2: socios (TODOS; activo visible). El backfill matchea contra todos, no solo activos.
SELECT id_socio,
       nombre,
       activo,
       lower(btrim(nombre)) AS nombre_norm
FROM public.socios
ORDER BY nombre;


-- ---- D3: match normalizado portal_usuarios(socio) -> socios (mismo criterio que el backfill SB0).
--          n_matches = cuantas filas de socios matchean; 'matches' lista id:nombre (marca inactivos).
--          NO referencia portal_usuarios.id_socio (no existe pre-SB0); s.id_socio es el PK de socios.
SELECT p.nombre                    AS portal_nombre,
       count(s.id_socio)           AS n_matches,
       string_agg(
         s.id_socio::text || ':' || s.nombre ||
         CASE WHEN s.activo THEN '' ELSE ' (inactivo)' END,
         ', ' ORDER BY s.id_socio
       )                           AS matches
FROM public.portal_usuarios p
LEFT JOIN public.socios s
       ON lower(btrim(s.nombre)) = lower(btrim(p.nombre))
WHERE p.rol = 'socio'
GROUP BY p.nombre
ORDER BY p.nombre;


-- ---- GATE (ultimo statement): 4 chequeos criticos. Los cuatro deben dar PASS para avanzar a A1.
WITH
pu_soc AS (
  SELECT nombre, lower(btrim(nombre)) AS n
    FROM public.portal_usuarios
   WHERE rol = 'socio'
),
soc AS (
  SELECT id_socio, lower(btrim(nombre)) AS n
    FROM public.socios
),
pu_match AS (
  SELECT p.nombre, p.n, count(s.id_socio) AS n_matches
    FROM pu_soc p
    LEFT JOIN soc s ON s.n = p.n
   GROUP BY p.nombre, p.n
),
soc_hits AS (
  SELECT s.id_socio, count(p.nombre) AS n_portal
    FROM soc s
    JOIN pu_soc p ON p.n = s.n
   GROUP BY s.id_socio
),
checks(orden, chequeo, esperado, obtenido) AS (
  VALUES
    (1, 'socios con nombre normalizado DUPLICADO (preflight SB0)',
        '0',
        (SELECT count(*)::text FROM (SELECT n FROM soc GROUP BY n HAVING count(*) > 1) d)),
    (2, 'portal_usuarios rol=socio SIN match en socios',
        '0',
        (SELECT count(*)::text FROM pu_match WHERE n_matches = 0)),
    (3, 'portal_usuarios rol=socio con match MULTIPLE (>1)',
        '0',
        (SELECT count(*)::text FROM pu_match WHERE n_matches > 1)),
    (4, 'socios matcheados por 2+ portal socios (colision UNIQUE)',
        '0',
        (SELECT count(*)::text FROM soc_hits WHERE n_portal > 1))
)
SELECT orden,
       chequeo,
       esperado,
       obtenido,
       CASE WHEN esperado = obtenido THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM checks
ORDER BY orden;
