-- ============================================================================
-- EXT_SNAPSHOT_04_VERIFY_ESTRUCTURAL_OPS.sql   (Run 4/6  --  READ-ONLY)
-- Verificacion estructural con ACL REAL por aclexplode:
--   * grants (CUALQUIER privilegio) a PUBLIC/anon/authenticated/service_role
--     sobre las 3 tablas nuevas -> deben ser 0.
--   * EXECUTE sobre registrar_snapshot_periodo para esos grantees -> 0
--     (+ proacl materializado = REVOKE aplicado, PUBLIC sin EXECUTE default).
-- Correr con NADA seleccionado. Un unico result set.
-- ============================================================================
WITH grantees AS (
  SELECT 'PUBLIC'::text AS label, 0::oid AS oid
  UNION ALL
  SELECT r.rolname, r.oid FROM pg_roles r WHERE r.rolname IN ('anon','authenticated','service_role')
),
tabs AS (SELECT unnest(ARRAY['liquidacion_participacion','liquidacion_gasto','liquidacion_incidencia']) AS tab),
tab_acl AS (
  SELECT c.relname AS tab, ae.grantee AS grantee, ae.privilege_type AS priv
  FROM pg_class c
  CROSS JOIN LATERAL aclexplode(c.relacl) ae
  WHERE c.relnamespace='public'::regnamespace
    AND c.relname IN ('liquidacion_participacion','liquidacion_gasto','liquidacion_incidencia')
),
fn_acl AS (
  SELECT ae.grantee AS grantee, ae.privilege_type AS priv
  FROM pg_proc p
  CROSS JOIN LATERAL aclexplode(p.proacl) ae
  WHERE p.oid = to_regprocedure('public.registrar_snapshot_periodo(date,numeric,text,bigint,text)')
)
SELECT 0::int AS orden, '0-AMBIENTE'::text AS seccion, 'ambiente'::text AS item, ''::text AS detalle,
       COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(sin clave)')::text AS valor
UNION ALL
SELECT 1,'1-TABLAS', t.tab, 'existe / columnas (T1=5 T2=19 T3=7)',
       COALESCE(to_regclass('public.'||t.tab)::text,'NO EXISTE')||' / '||
       (SELECT count(*)::text FROM information_schema.columns WHERE table_schema='public' AND table_name=t.tab)
FROM tabs t
UNION ALL
SELECT 2,'2-TRIGGERS','total (esperado 6)','inmutabilidad sobre las 3 tablas',
       (SELECT count(*)::text FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN (
          'public.liquidacion_participacion'::regclass,'public.liquidacion_gasto'::regclass,
          'public.liquidacion_incidencia'::regclass))
UNION ALL
-- ACL real: grants (cualquier privilegio) por tabla y grantee sensible -> 0 esperado
SELECT 3,'3-ACL-TABLAS', g.label||' / '||t.tab, 'grants cualquier priv (debe ser 0)',
       (SELECT count(*)::text FROM tab_acl a WHERE a.tab=t.tab AND a.grantee=g.oid)
FROM tabs t CROSS JOIN grantees g
UNION ALL
SELECT 3,'3-ACL-TABLAS-TOTAL','TODAS','grants sensibles totales (debe ser 0)',
       (SELECT count(*)::text FROM tab_acl a JOIN grantees g ON g.oid=a.grantee)
UNION ALL
-- detalle de cualquier grant ofensor (si aparecen filas aca, es RED FLAG)
SELECT 3,'3-ACL-TABLAS-OFENSOR', a.tab||' -> '||g.label, 'PRIVILEGIO OTORGADO (no deberia)', a.priv
FROM tab_acl a JOIN grantees g ON g.oid=a.grantee
UNION ALL
SELECT 4,'4-FUNCION','firma','registrar_snapshot_periodo (debe existir)',
       COALESCE(to_regprocedure('public.registrar_snapshot_periodo(date,numeric,text,bigint,text)')::text,'NO EXISTE')
UNION ALL
SELECT 5,'5-ACL-EXECUTE','proacl_materializado','true = REVOKE aplicado (PUBLIC sin EXECUTE default)',
       (SELECT (proacl IS NOT NULL)::text FROM pg_proc WHERE oid=to_regprocedure('public.registrar_snapshot_periodo(date,numeric,text,bigint,text)'))
UNION ALL
SELECT 5,'5-ACL-EXECUTE', g.label, 'EXECUTE otorgado? (debe ser 0)',
       (SELECT count(*)::text FROM fn_acl a WHERE a.grantee=g.oid AND a.priv='EXECUTE')
FROM grantees g
ORDER BY 1,2,3;
