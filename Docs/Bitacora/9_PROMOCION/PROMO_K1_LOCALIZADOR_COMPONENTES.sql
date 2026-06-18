-- ============================================================================
-- PROMO_K1_LOCALIZADOR_COMPONENTES.sql
-- Descompone la huella K1 de los 8 objetos que difieren en SUB-HUELLAS por
-- componente, para localizar QUÉ difiere (estructura vs ACL vs cuerpo).
-- READ-ONLY. Correr en TEST y en OPS con NADA seleccionado; comparar las dos
-- salidas fila por fila: las (objeto, componente) cuya sub_huella difiera son
-- el origen exacto de la diferencia.
-- Mismos componentes que usa K1: tablas = cols/cons/idx/trg/acl; funciones = def/acl.
-- ============================================================================
WITH
difs_tab(nom) AS (VALUES ('zonas'),('cabana_zona'),('activaciones_operativas'),('gastos_internos')),
difs_fn(nom)  AS (VALUES ('resolver_beneficiario'),('matriz_participacion'),('repartir_por_matriz'),('detalle_participacion')),
-- componentes de tabla
tab AS (
  SELECT 'tabla:'||dt.nom AS objeto, comp.componente, comp.sub AS sub_huella, dt.nom AS ord1, comp.k AS ord2
  FROM difs_tab dt
  JOIN pg_class c ON c.relname=dt.nom
  JOIN pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public' AND c.relkind='r'
  CROSS JOIN LATERAL (VALUES
    (1,'cols', md5(COALESCE((SELECT string_agg(format('%s|%s|%s|%s', a.attnum, a.attname, format_type(a.atttypid,a.atttypmod), a.attnotnull), E'\n' ORDER BY a.attnum)
                 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),''))),
    (2,'cons', md5(COALESCE((SELECT string_agg(format('%s|%s', con.conname, pg_get_constraintdef(con.oid)), E'\n' ORDER BY con.conname)
                 FROM pg_constraint con WHERE con.conrelid=c.oid),''))),
    (3,'idx',  md5(COALESCE((SELECT string_agg(format('%s|%s', i.indexname, i.indexdef), E'\n' ORDER BY i.indexname)
                 FROM pg_indexes i WHERE i.schemaname='public' AND i.tablename=dt.nom),''))),
    (4,'trg',  md5(COALESCE((SELECT string_agg(format('%s|%s', tg.tgname, pg_get_triggerdef(tg.oid)), E'\n' ORDER BY tg.tgname)
                 FROM pg_trigger tg WHERE tg.tgrelid=c.oid AND NOT tg.tgisinternal),''))),
    (5,'acl',  md5(COALESCE(c.relacl::text,'NULL')))
  ) AS comp(k, componente, sub)
),
-- componentes de función
fn AS (
  SELECT 'func:'||p.proname AS objeto, comp.componente, comp.sub AS sub_huella, p.proname AS ord1, comp.k AS ord2
  FROM difs_fn df
  JOIN pg_proc p ON p.proname=df.nom
  JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
  CROSS JOIN LATERAL (VALUES
    (1,'def', md5(replace(pg_get_functiondef(p.oid), E'\r',''))),
    (2,'acl', md5(COALESCE(p.proacl::text,'NULL')))
  ) AS comp(k, componente, sub)
)
SELECT objeto, componente, sub_huella FROM tab
UNION ALL SELECT objeto, componente, sub_huella FROM fn
ORDER BY 1, 2;
