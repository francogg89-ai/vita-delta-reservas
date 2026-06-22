-- ============================================================================
-- VITA DELTA . CARRIL C . SLICE 3b . A13 (gastos.listado) . SMOKE EXPECTED
-- ----------------------------------------------------------------------------
-- Entorno objetivo : TEST (vita-delta-test, ref bdskhhbmcksskkzqkcdp, cabanas 1-5).
--                    100% read-only (solo SELECT). NO correr en OPS. Si la fila
--                    VEREDICTO (orden 99.99) NO da OK, FRENAR.
-- Proposito        : producir el GROUND TRUTH para cruzar al centavo contra la salida
--                    del smoke directo (C_SLICE3B_A13_smoke_directo.ps1). Replica EXACTO
--                    el WHERE del wrapper (floor GREATEST 2026-07-01, periodo inclusivo,
--                    bordes ya a primer dia de mes) para la VENTANA CANONICA del smoke:
--                       periodo_desde = floor (default)   ->  2026-07-01
--                       periodo_hasta = $HASTA del smoke   ->  2099-12-01
--                    (ventana amplia para capturar el fixture 9F de julio y los gastos
--                     sinteticos de periodo 2099; D4: el default {} en junio 2026 da vacio).
-- Como correr      : seleccionar TODO y ejecutar como UN run. Salida = una tabla;
--                    leer la fila VEREDICTO y despues E2/E3/E4 (los numeros a cruzar).
-- Lo que el smoke debe reproducir (limit 200, periodo_hasta=2099-12-01):
--    E2 total_gastos   == data.total_gastos
--    E3 por_clase      == data.por_clase  (mismos {clase, monto, n})
--    E4 particiones     -> sum(clase)=sum(pagador)=total_gastos (asserts G5/G6 del PS1)
-- ============================================================================

WITH
params AS (
  SELECT DATE '2026-07-01' AS floor_,
         GREATEST(DATE '2026-07-01', DATE '2026-07-01') AS p_desde,  -- default = floor
         DATE '2099-12-01' AS p_hasta                                 -- $HASTA (ya dia 1)
),
universo AS (
  -- MISMO filtro que el wrapper, sin filtros opcionales (universo completo de la ventana).
  SELECT g.*
  FROM gastos_internos g, params
  WHERE g.periodo >= GREATEST(params.floor_, params.p_desde)
    AND g.periodo <= params.p_hasta
),
dx AS (

-- S0 GATE (FALLO bloquea) -----------------------------------------------------
SELECT 0.01::numeric AS orden, 'S0_GATE'::text AS seccion,
       'marcador de ambiente'::text AS chequeo, 'test'::text AS valor,
       (CASE WHEN (SELECT valor FROM configuracion_general WHERE clave='ambiente')='test'
             THEN 'OK' ELSE 'FALLO' END)::text AS estado
UNION ALL
SELECT 0.02,'S0_GATE','cabanas ids 1-5 (identidad TEST)',
       (SELECT COUNT(*)::text FROM cabanas),
       (CASE WHEN (SELECT COUNT(*) FROM cabanas)=5
              AND (SELECT MIN(id_cabana) FROM cabanas)=1
              AND (SELECT MAX(id_cabana) FROM cabanas)=5
             THEN 'OK' ELSE 'FALLO' END)

-- E0 VENTANA ------------------------------------------------------------------
UNION ALL
SELECT 1.00,'E0_VENTANA','periodo_desde (clamp floor) .. periodo_hasta',
       (SELECT to_char(GREATEST(floor_,p_desde),'YYYY-MM-DD')||' .. '||to_char(p_hasta,'YYYY-MM-DD') FROM params),
       'INFO'

-- E1 CONTEO -------------------------------------------------------------------
UNION ALL
SELECT 2.01,'E1_CONTEO','n_filas (universo de la ventana)',
       (SELECT COUNT(*)::text FROM universo),
       'INFO'

-- E2 TOTAL --------------------------------------------------------------------
UNION ALL
SELECT 3.01,'E2_TOTAL','total_gastos = SUM(monto) [cruzar con data.total_gastos]',
       (SELECT COALESCE(SUM(monto),0)::text FROM universo),
       'INFO'

-- E3 POR_CLASE ----------------------------------------------------------------
UNION ALL
SELECT 4.01,'E3_POR_CLASE','clase=monto(n) [cruzar con data.por_clase]',
       COALESCE((SELECT string_agg(clase||'='||monto::text||'('||n::text||')', ', ' ORDER BY clase)
                   FROM (SELECT clase, SUM(monto) AS monto, COUNT(*) AS n
                           FROM universo GROUP BY clase) q),'(vacio)'),
       'INFO'

-- E4 PARTICIONES (sustento de G5/G6 del PS1) ----------------------------------
UNION ALL
SELECT 5.01,'E4_PARTICION','sum(por_clase) == total_gastos',
       (SELECT (COALESCE(SUM(monto),0))::text FROM universo),
       (CASE WHEN (SELECT COALESCE(SUM(monto),0) FROM universo)
                = (SELECT COALESCE(SUM(monto),0) FROM (SELECT clase, SUM(monto) AS monto FROM universo GROUP BY clase) z)
             THEN 'OK' ELSE 'ATENCION' END)
UNION ALL
SELECT 5.02,'E4_PARTICION','por_pagador: socio=monto(n), caja=monto(n)',
       COALESCE((SELECT string_agg(pagador_tipo||'='||monto::text||'('||n::text||')', ', ' ORDER BY pagador_tipo)
                   FROM (SELECT pagador_tipo, SUM(monto) AS monto, COUNT(*) AS n
                           FROM universo GROUP BY pagador_tipo) q),'(vacio)'),
       'INFO'
UNION ALL
SELECT 5.03,'E4_PARTICION','sum(por_pagador) == total_gastos',
       (SELECT (COALESCE(SUM(monto),0))::text FROM universo),
       (CASE WHEN (SELECT COALESCE(SUM(monto),0) FROM universo)
                = (SELECT COALESCE(SUM(monto),0) FROM (SELECT pagador_tipo, SUM(monto) AS monto FROM universo GROUP BY pagador_tipo) z)
             THEN 'OK' ELSE 'ATENCION' END)

-- E5 DISTRIBUCION POR MES (informativo: donde estan los datos) -----------------
UNION ALL
SELECT 6.01,'E5_POR_MES','periodo=n(monto)',
       COALESCE((SELECT string_agg(to_char(periodo,'YYYY-MM')||'='||n::text||'('||monto::text||')', ', ' ORDER BY periodo)
                   FROM (SELECT periodo, COUNT(*) AS n, SUM(monto) AS monto
                           FROM universo GROUP BY periodo) q),'(vacio)'),
       'INFO'

-- E6 FLOOR (lo de antes del floor queda EXCLUIDO del universo) -----------------
UNION ALL
SELECT 7.01,'E6_FLOOR','gastos con periodo < floor (excluidos del universo)',
       (SELECT COUNT(*)::text FROM gastos_internos WHERE periodo < DATE '2026-07-01'),
       'INFO'

-- E7 MUESTRA (id|periodo|clase|monto|moneda|pagador|socio|zona|cab) -----------
UNION ALL
SELECT 8.01,'E7_MUESTRA','primeras filas (orden periodo, id_gasto)',
       COALESCE((SELECT string_agg(
           u.id_gasto::text||'|'||to_char(u.periodo,'YYYY-MM')||'|'||u.clase||'|'||u.monto::text
           ||'|'||u.moneda||'|'||u.pagador_tipo||'|'||COALESCE(u.id_socio_pagador::text,'-')
           ||'|'||COALESCE(u.id_zona::text,'-')||'|'||COALESCE(u.id_cabana::text,'-'),
           E'\n' ORDER BY u.periodo, u.id_gasto)
           FROM (SELECT * FROM universo ORDER BY periodo, id_gasto LIMIT 15) u),'(vacio)'),
       'INFO'

)
SELECT * FROM dx
UNION ALL
SELECT 99.99,'VEREDICTO',
       'gate OK + particiones cuadran (sustento del cruce al centavo del PS1)',
       'FALLO='||(SELECT COUNT(*) FROM dx WHERE estado='FALLO')::text
        ||' ATENCION='||(SELECT COUNT(*) FROM dx WHERE estado='ATENCION')::text,
       (CASE WHEN (SELECT COUNT(*) FROM dx WHERE estado='FALLO')=0
              AND (SELECT COUNT(*) FROM dx WHERE estado='ATENCION')=0
             THEN 'OK' ELSE 'REVISAR' END)
ORDER BY orden;
