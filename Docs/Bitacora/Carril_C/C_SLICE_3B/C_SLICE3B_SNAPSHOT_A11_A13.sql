-- ============================================================================
-- VITA DELTA · CARRIL C · SLICE 3b · SNAPSHOT READ-ONLY — A11 / A13
-- ----------------------------------------------------------------------------
-- Entorno objetivo : TEST (vita-delta-test, ref bdskhhbmcksskkzqkcdp, cabañas 1-5).
--                    NO correr en OPS. Es 100% read-only, pero si la fila
--                    VEREDICTO (orden 99.99) NO da OK, FRENAR y no diseñar nada.
-- Naturaleza       : 100% read-only (solo SELECT + catálogos de sistema).
--                    Sin DDL, sin DML, sin CREATE FUNCTION, sin writes.
-- Cómo correr      : seleccionar TODO el archivo y ejecutarlo como UN único run.
--                    Salida = una sola tabla; leer primero la fila VEREDICTO.
-- Propósito (resuelve las preguntas de diseño del kickoff):
--   S0) Gate duro de entorno e identidad (ambiente 'test', cabañas 1-5, socios).
--   S1) Estructura real de `gastos_internos` (destino de A11 / fuente de A13):
--       17 columnas, 18 constraints (14 c + 3 f RESTRICT + PK), índice, RLS.
--   S2) Funciones de inserción reusables (Q2) + NO colisión de nombres candidatos
--       para A11/A13 y para una eventual función de infra del portal.
--   S3) Store de nonce P-C-9 (Q3): confirmar que NO existe todavía (se construye
--       fresh como infra del portal TEST-only, precedente `portal_usuarios`).
--   S4) Catálogos de alcance/pagador (Q4): zonas (clase D), cabañas (clase E),
--       socios (pagador socio). El seam `resolver_beneficiario` es read-side (9G),
--       NO se necesita en la escritura.
--   S5) Datos de muestra para los cruces: filas de `gastos_internos`, conteos por
--       clase, períodos vs floor 2026-07-01 (clamp de A13), override/sin-sugerencia.
-- Estados de fila  : OK / FALLO (bloquea) / ATENCION (no bloquea) / INFO.
-- Lecciones aplicadas: L-9C-02 (cast ::text en columnas de UNION), L-9C-03
--                    (conrelid para constraints), conteo de funciones excluyendo
--                    las owned por extensión (pg_depend deptype='e'). Uso de
--                    to_regclass (NULL si falta la tabla) para no abortar el run.
-- ============================================================================

WITH dx AS (

-- ===========================================================================
-- S0 — GATE DE ENTORNO E IDENTIDAD  (FALLO bloquea)
-- ===========================================================================
SELECT 0.01::numeric AS orden, 'S0_GATE'::text AS seccion,
       'marcador de ambiente'::text AS chequeo,
       'test'::text AS esperado,
       COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(ausente)')::text AS obtenido,
       (CASE WHEN (SELECT valor FROM configuracion_general WHERE clave='ambiente')='test'
             THEN 'OK' ELSE 'FALLO' END)::text AS estado

UNION ALL
SELECT 0.02,'S0_GATE','cabanas: cantidad e ids (identidad TEST)','5 filas, ids 1-5',
       (SELECT COUNT(*)::text || ' filas, ids ' || COALESCE(MIN(id_cabana)::text,'-') || '-' || COALESCE(MAX(id_cabana)::text,'-') FROM cabanas),
       (CASE WHEN (SELECT COUNT(*) FROM cabanas)=5
              AND (SELECT MIN(id_cabana) FROM cabanas)=1
              AND (SELECT MAX(id_cabana) FROM cabanas)=5
             THEN 'OK' ELSE 'FALLO' END)

UNION ALL
SELECT 0.03,'S0_GATE','cabanas: los 5 nombres esperados','5',
       (SELECT COUNT(*)::text FROM cabanas WHERE nombre IN ('Bamboo','Madre Selva','Arrebol','Guatemala','Tokio')),
       (CASE WHEN (SELECT COUNT(*) FROM cabanas WHERE nombre IN ('Bamboo','Madre Selva','Arrebol','Guatemala','Tokio'))=5
             THEN 'OK' ELSE 'FALLO' END)

UNION ALL
SELECT 0.04,'S0_GATE','socios Franco/Rodrigo/Remo (1 c/u)','Franco=1, Remo=1, Rodrigo=1',
       COALESCE((SELECT string_agg(nombre||'='||n::text, ', ' ORDER BY nombre)
                   FROM (SELECT nombre, COUNT(*) AS n FROM socios
                          WHERE nombre IN ('Franco','Rodrigo','Remo') GROUP BY nombre) s),'(ninguno)'),
       (CASE WHEN (SELECT COUNT(*) FROM (SELECT nombre FROM socios
                                          WHERE nombre IN ('Franco','Rodrigo','Remo')
                                          GROUP BY nombre HAVING COUNT(*)=1) t)=3
             THEN 'OK' ELSE 'FALLO' END)

-- ===========================================================================
-- S1 — ESTRUCTURA DE gastos_internos
-- ===========================================================================
UNION ALL
SELECT 1.01,'S1_GI','tabla gastos_internos existe','presente',
       (CASE WHEN to_regclass('public.gastos_internos') IS NOT NULL THEN 'presente' ELSE '(ausente)' END),
       (CASE WHEN to_regclass('public.gastos_internos') IS NOT NULL THEN 'OK' ELSE 'FALLO' END)

UNION ALL
SELECT 1.02,'S1_GI','columnas (cantidad)','17',
       (SELECT COUNT(*)::text FROM pg_attribute
         WHERE attrelid=to_regclass('public.gastos_internos') AND attnum>0 AND NOT attisdropped),
       (CASE WHEN (SELECT COUNT(*) FROM pg_attribute
                    WHERE attrelid=to_regclass('public.gastos_internos') AND attnum>0 AND NOT attisdropped)=17
             THEN 'OK' ELSE 'FALLO' END)

UNION ALL
SELECT 1.03,'S1_GI','columnas (nombre:tipo:null/NN)','(informativo)',
       COALESCE((SELECT string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod)||
                                   CASE WHEN a.attnotnull THEN ':NN' ELSE ':null' END, ' | ' ORDER BY a.attnum)
                   FROM pg_attribute a
                  WHERE a.attrelid=to_regclass('public.gastos_internos') AND a.attnum>0 AND NOT a.attisdropped),'(sin tabla)'),
       'INFO'

UNION ALL
SELECT 1.04,'S1_GI','constraints (cantidad esperada 18)','18',
       (SELECT COUNT(*)::text FROM pg_constraint WHERE conrelid=to_regclass('public.gastos_internos')),
       (CASE WHEN (SELECT COUNT(*) FROM pg_constraint WHERE conrelid=to_regclass('public.gastos_internos'))=18
             THEN 'OK' ELSE 'ATENCION' END)

UNION ALL
SELECT 1.05,'S1_GI','constraints por tipo','c=14, f=3, p=1',
       COALESCE((SELECT string_agg(contype||'='||n::text, ', ' ORDER BY contype)
                   FROM (SELECT contype::text AS contype, COUNT(*) AS n
                           FROM pg_constraint WHERE conrelid=to_regclass('public.gastos_internos')
                          GROUP BY contype) z),'(sin tabla)'),
       (CASE WHEN (SELECT COUNT(*) FROM pg_constraint WHERE conrelid=to_regclass('public.gastos_internos') AND contype='c')=14
              AND (SELECT COUNT(*) FROM pg_constraint WHERE conrelid=to_regclass('public.gastos_internos') AND contype='f')=3
              AND (SELECT COUNT(*) FROM pg_constraint WHERE conrelid=to_regclass('public.gastos_internos') AND contype='p')=1
             THEN 'OK' ELSE 'ATENCION' END)

UNION ALL
SELECT 1.06,'S1_GI','FKs ON DELETE RESTRICT (confdeltype=r)','3',
       (SELECT COUNT(*)::text FROM pg_constraint
         WHERE conrelid=to_regclass('public.gastos_internos') AND contype='f' AND confdeltype='r'),
       (CASE WHEN (SELECT COUNT(*) FROM pg_constraint
                    WHERE conrelid=to_regclass('public.gastos_internos') AND contype='f' AND confdeltype='r')=3
             THEN 'OK' ELSE 'ATENCION' END)

UNION ALL
SELECT 1.07,'S1_GI','indice idx_gastos_internos_periodo_clase','presente',
       (CASE WHEN EXISTS (SELECT 1 FROM pg_indexes
                           WHERE schemaname='public' AND tablename='gastos_internos'
                             AND indexname='idx_gastos_internos_periodo_clase') THEN 'presente' ELSE '(ausente)' END),
       (CASE WHEN EXISTS (SELECT 1 FROM pg_indexes
                           WHERE schemaname='public' AND tablename='gastos_internos'
                             AND indexname='idx_gastos_internos_periodo_clase') THEN 'OK' ELSE 'ATENCION' END)

UNION ALL
SELECT 1.08,'S1_GI','defaults moneda / created_at','ARS / now()',
       COALESCE((SELECT string_agg(a.attname||'='||pg_get_expr(d.adbin,d.adrelid), ', ' ORDER BY a.attname)
                   FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
                  WHERE d.adrelid=to_regclass('public.gastos_internos') AND a.attname IN ('moneda','created_at')),'(sin defaults)'),
       'INFO'

UNION ALL
SELECT 1.09,'S1_GI','RLS deshabilitado (paridad schema)','false',
       COALESCE((SELECT relrowsecurity::text FROM pg_class WHERE oid=to_regclass('public.gastos_internos')),'(sin tabla)'),
       (CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('public.gastos_internos'))=false
             THEN 'OK' ELSE 'ATENCION' END)

-- ===========================================================================
-- S2 — FUNCIONES DE INSERCION REUSABLES (Q2) + NO COLISION DE NOMBRES
-- ===========================================================================
UNION ALL
SELECT 2.01,'S2_FN','func. que INSERTAN en gastos_internos (best-effort prosrc)','0 = no hay reuse -> A11 arma el INSERT',
       (SELECT COUNT(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.prokind='f'
           AND COALESCE(p.prosrc,'') ~* 'insert\s+into\s+(public\.)?gastos_internos'
           AND NOT EXISTS (SELECT 1 FROM pg_depend dd WHERE dd.objid=p.oid AND dd.deptype='e')),
       'INFO'

UNION ALL
SELECT 2.02,'S2_FN','func. que MENCIONAN gastos_internos (cascada/cta cte: todas read)','(informativo)',
       COALESCE((SELECT string_agg(p.proname, ', ' ORDER BY p.proname)
                   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.prokind='f'
                    AND COALESCE(p.prosrc,'') ILIKE '%gastos_internos%'
                    AND NOT EXISTS (SELECT 1 FROM pg_depend dd WHERE dd.objid=p.oid AND dd.deptype='e')),'(ninguna)'),
       'INFO'

UNION ALL
SELECT 2.03,'S2_FN','colision de nombres candidatos A11/A13/portal','0 (todos libres)',
       (SELECT COUNT(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public'
           AND p.proname = ANY (ARRAY['cargar_gasto_interno','crear_gasto_interno','insertar_gasto_interno','registrar_gasto_interno',
                                      'portal_cargar_gasto_interno','portal_crear_gasto_interno','portal_gasto_interno',
                                      'gastos_listado','listar_gastos_internos','gastos_internos_listado','portal_listar_gastos','portal_gastos_listado'])),
       (CASE WHEN (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public'
                      AND p.proname = ANY (ARRAY['cargar_gasto_interno','crear_gasto_interno','insertar_gasto_interno','registrar_gasto_interno',
                                                 'portal_cargar_gasto_interno','portal_crear_gasto_interno','portal_gasto_interno',
                                                 'gastos_listado','listar_gastos_internos','gastos_internos_listado','portal_listar_gastos','portal_gastos_listado']))=0
             THEN 'OK' ELSE 'ATENCION' END)

-- ===========================================================================
-- S3 — STORE DE NONCE P-C-9 (Q3)
-- ===========================================================================
UNION ALL
SELECT 3.01,'S3_NONCE','tabla de nonce/anti-replay ya existente','0 (se construye fresh)',
       (SELECT COUNT(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
         WHERE n.nspname='public' AND c.relkind='r'
           AND (c.relname ILIKE '%nonce%' OR c.relname ILIKE '%replay%')),
       (CASE WHEN (SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                    WHERE n.nspname='public' AND c.relkind='r'
                      AND (c.relname ILIKE '%nonce%' OR c.relname ILIKE '%replay%'))=0
             THEN 'OK' ELSE 'ATENCION' END)

UNION ALL
SELECT 3.02,'S3_NONCE','infra portal existente (relname LIKE portal_%)','portal_usuarios (precedente)',
       COALESCE((SELECT string_agg(c.relname, ', ' ORDER BY c.relname)
                   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                  WHERE n.nspname='public' AND c.relkind='r' AND c.relname LIKE 'portal\_%' ESCAPE '\'),'(ninguna)'),
       'INFO'

-- ===========================================================================
-- S4 — CATALOGOS DE ALCANCE/PAGADOR (Q4) — inputs de A11
-- ===========================================================================
UNION ALL
SELECT 4.01,'S4_CAT','zonas (clase D) id:nombre','(informativo)',
       COALESCE((SELECT string_agg(id_zona::text||':'||nombre, ', ' ORDER BY id_zona) FROM zonas),'(sin zonas)'),
       'INFO'

UNION ALL
SELECT 4.02,'S4_CAT','cabanas (clase E) id:nombre','(informativo)',
       COALESCE((SELECT string_agg(id_cabana::text||':'||nombre, ', ' ORDER BY id_cabana) FROM cabanas),'(sin cabanas)'),
       'INFO'

UNION ALL
SELECT 4.03,'S4_CAT','socios (pagador socio) id:nombre','(informativo)',
       COALESCE((SELECT string_agg(id_socio::text||':'||nombre, ', ' ORDER BY id_socio) FROM socios),'(sin socios)'),
       'INFO'

-- ===========================================================================
-- S5 — DATOS DE MUESTRA PARA LOS CRUCES
-- ===========================================================================
UNION ALL
SELECT 5.01,'S5_DATA','gastos_internos: filas totales','(informativo)',
       (SELECT COUNT(*)::text FROM gastos_internos),
       'INFO'

UNION ALL
SELECT 5.02,'S5_DATA','gastos_internos: filas por clase','(informativo)',
       COALESCE((SELECT string_agg(clase||'='||n::text, ', ' ORDER BY clase)
                   FROM (SELECT clase, COUNT(*) AS n FROM gastos_internos GROUP BY clase) q),'(vacia)'),
       'INFO'

UNION ALL
SELECT 5.03,'S5_DATA','gastos_internos: muestra (id|clase|sug|etiqueta|periodo|monto|pagador|socio|zona|cab|creado_por)','(informativo)',
       COALESCE((SELECT string_agg(
                   g.id_gasto::text||'|'||g.clase||'|'||COALESCE(g.clase_sugerida,'-')||'|'||g.etiqueta||'|'||to_char(g.periodo,'YYYY-MM')
                   ||'|'||g.monto::text||'|'||g.pagador_tipo||'|'||COALESCE(g.id_socio_pagador::text,'-')
                   ||'|'||COALESCE(g.id_zona::text,'-')||'|'||COALESCE(g.id_cabana::text,'-')||'|'||g.creado_por,
                   E'\n' ORDER BY g.id_gasto)
                   FROM (SELECT * FROM gastos_internos ORDER BY id_gasto LIMIT 20) g),'(vacia)'),
       'INFO'

UNION ALL
SELECT 5.04,'S5_DATA','periodos vs floor 2026-07-01 (clamp A13)','(informativo)',
       (SELECT 'periodo<floor='||(COUNT(*) FILTER (WHERE periodo < DATE '2026-07-01'))::text
            ||' · periodo>=floor='||(COUNT(*) FILTER (WHERE periodo >= DATE '2026-07-01'))::text
          FROM gastos_internos),
       'INFO'

UNION ALL
SELECT 5.05,'S5_DATA','derivados: override (clase<>sugerida) / sin_sugerencia','(informativo)',
       (SELECT 'override='||(COUNT(*) FILTER (WHERE clase_sugerida IS NOT NULL AND clase<>clase_sugerida))::text
            ||' · sin_sugerencia='||(COUNT(*) FILTER (WHERE clase_sugerida IS NULL))::text
          FROM gastos_internos),
       'INFO'

)
SELECT * FROM dx
UNION ALL
SELECT 99.99,'VEREDICTO',
       'apto para disenar A11/A13 (S0 gate + S1 estructura sin FALLO)',
       'FALLO=0',
       'FALLO='||(SELECT COUNT(*) FROM dx WHERE estado='FALLO')::text
        ||' · ATENCION='||(SELECT COUNT(*) FROM dx WHERE estado='ATENCION')::text
        ||' · OK='||(SELECT COUNT(*) FROM dx WHERE estado='OK')::text
        ||' · INFO='||(SELECT COUNT(*) FROM dx WHERE estado='INFO')::text,
       (CASE WHEN (SELECT COUNT(*) FROM dx WHERE estado='FALLO')=0 THEN 'OK' ELSE 'FALLO' END)
ORDER BY orden;
