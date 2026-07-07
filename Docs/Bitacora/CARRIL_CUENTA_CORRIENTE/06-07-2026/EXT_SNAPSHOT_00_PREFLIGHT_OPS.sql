-- ============================================================================
-- EXT_SNAPSHOT_00_PREFLIGHT_OPS.sql   (Run 0/6  --  READ-ONLY, no escribe)
-- Extension del snapshot a P-CC-2 completo. Diagnostico previo.
-- Correr con NADA seleccionado. Un unico result set. Seguro (solo SELECT).
-- ============================================================================
SELECT 0::int AS orden, '0-AMBIENTE'::text AS seccion, 'ambiente'::text AS item,
       'debe ser ops para los runs 01-03'::text AS detalle,
       COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(sin clave)')::text AS valor
UNION ALL
SELECT 1,'1-TABLAS-NUEVAS', t.n, 'to_regclass (NULL=libre, OK)',
       COALESCE(to_regclass('public.'||t.n)::text,'NULL (libre)')
FROM (VALUES ('liquidacion_participacion'),('liquidacion_gasto'),('liquidacion_incidencia')) t(n)
UNION ALL
SELECT 2,'2-TRIGGERS-NUEVOS', g.n, 'existe? (0=libre, OK)',
       (SELECT count(*)::text FROM pg_trigger WHERE tgname=g.n AND NOT tgisinternal)
FROM (VALUES ('trg_liquidacion_participacion_no_upd_del'),('trg_liquidacion_participacion_no_truncate'),
             ('trg_liquidacion_gasto_no_upd_del'),('trg_liquidacion_gasto_no_truncate'),
             ('trg_liquidacion_incidencia_no_upd_del'),('trg_liquidacion_incidencia_no_truncate')) g(n)
UNION ALL
SELECT 3,'3-DEP-VISTAS','vistas_dependientes','deben ser 0 para DROP seguro de la funcion',
       (SELECT count(*)::text FROM pg_depend d
        JOIN pg_rewrite r ON r.oid=d.objid
        JOIN pg_class c ON c.oid=r.ev_class AND c.relkind='v'
        WHERE d.refobjid = to_regprocedure('public.registrar_snapshot_periodo(date,numeric,text,bigint,text)'))
UNION ALL
SELECT 4,'4-FUNCION-ACTUAL','registrar_snapshot_periodo','firma a reemplazar (debe existir)',
       COALESCE(to_regprocedure('public.registrar_snapshot_periodo(date,numeric,text,bigint,text)')::text,'NO EXISTE')
UNION ALL
SELECT 5,'5-FUENTES', f.n, 'firma (debe existir)',
       COALESCE(to_regprocedure(f.n)::text,'FALTA')
FROM (VALUES ('public.detalle_participacion(date)'),('public.gastos_sin_incidencia_periodo(date)'),
             ('public.incidencia_gasto(bigint)'),('public.cascada_periodo(date,numeric)'),
             ('public.saldo_socios_periodo(date,numeric)'),('public.liquidacion_vigente(date)')) f(n)
ORDER BY 1,2,3;
