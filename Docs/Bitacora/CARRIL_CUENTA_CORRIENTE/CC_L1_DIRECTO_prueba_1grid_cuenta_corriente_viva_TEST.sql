-- =========================================================================
-- CC_L1_DIRECTO_prueba_1grid_cuenta_corriente_viva   --   ENTORNO: TEST
-- Version "una sola grilla" de la prueba directa. Existe porque el SQL Editor
-- de Supabase, ante varios SELECT, ejecuta todos pero SOLO muestra el ultimo.
-- Aca todo sale en UNA grilla: una fila por test, columnas (test, estado, detalle).
--
--   * Read-only. No escribe, no consume secuencias, no toca OPS.
--   * SQL puro. Correr en el SQL Editor de TEST con NADA seleccionado.
--   * Requisito: haber cargado la funcion cuenta_corriente_viva en el MISMO entorno.
--
-- Lectura del resultado:
--   P0_preflight      PASS  = las 2 funciones estan presentes
--   T1_al_dia         INFO  = estado real al dia (saldo por socio); si TEST no
--                             tiene actividad en el rango, sale "sin actividad"
--   T2_reconciliacion PASS  = la funcion == Sigma mes a mes (identidad); si no
--                             hay datos, "PASS (sin datos)" (mecanica OK)
--   T3_guard          PASS  = los 3 casos de pct invalido devuelven marcador
--   T4_pre_piso       PASS  = hasta < piso -> 0 filas
-- =========================================================================

WITH
-- P0
p0 AS (
  SELECT count(*) AS n
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('saldo_socios_periodo', 'cuenta_corriente_viva')
),
r_p0 AS (
  SELECT 1 AS ord, 'P0_preflight'::text AS test,
         CASE WHEN n = 2 THEN 'PASS' ELSE 'FAIL' END AS estado,
         (n || '/2 funciones presentes')::text AS detalle
  FROM p0
),
-- T1
t1 AS (
  SELECT count(*) AS n,
         string_agg(socio || '=' || round(saldo_al_dia, 2)::text, ', ' ORDER BY id_socio) AS resumen
  FROM cuenta_corriente_viva(NULL, 0.25)
  WHERE id_socio IS NOT NULL
),
r_t1 AS (
  SELECT 2, 'T1_al_dia'::text, 'INFO'::text,
         COALESCE(n || ' socios | saldo_al_dia: ' || resumen,
                  '0 socios (TEST sin actividad contable en el rango: esperado)')::text
  FROM t1
),
-- T2 reconciliacion (jul-2026..jun-2027)
h AS (SELECT DATE '2027-06-30' AS hasta, DATE '2026-07-01' AS piso),
esp AS (
  SELECT s.id_socio, SUM(s.saldo_final + s.desembolsado_periodo) AS liq
  FROM h
  CROSS JOIN LATERAL generate_series(h.piso::timestamp, date_trunc('month', h.hasta)::timestamp, INTERVAL '1 month') gs
  CROSS JOIN LATERAL saldo_socios_periodo(gs::date, 0.25) s
  WHERE s.id_socio IS NOT NULL
  GROUP BY s.id_socio
),
mesp AS (
  SELECT m.id_socio, SUM(m.monto) AS mv
  FROM movimientos_socio m CROSS JOIN h
  WHERE m.fecha >= h.piso AND m.fecha <= h.hasta
  GROUP BY m.id_socio
),
obt AS (
  SELECT c.id_socio,
         c.liquidacion_meses_previos + c.liquidacion_mes_en_curso + c.reembolsos_acumulados AS liq,
         c.movimientos, c.saldo_al_dia
  FROM h CROSS JOIN LATERAL cuenta_corriente_viva(h.hasta, 0.25) c
  WHERE c.id_socio IS NOT NULL
),
recon AS (
  SELECT (COALESCE(o.liq, 0) = COALESCE(e.liq, 0)
          AND COALESCE(o.movimientos, 0) = COALESCE(m.mv, 0)
          AND COALESCE(o.saldo_al_dia, 0) = COALESCE(e.liq, 0) + COALESCE(m.mv, 0)) AS ok
  FROM obt o
  FULL JOIN esp e USING (id_socio)
  LEFT JOIN mesp m ON m.id_socio = COALESCE(o.id_socio, e.id_socio)
),
r_t2 AS (
  SELECT 3, 'T2_reconciliacion'::text,
         CASE WHEN count(*) = 0 THEN 'PASS (sin datos)'
              WHEN count(*) FILTER (WHERE NOT ok) = 0 THEN 'PASS'
              ELSE 'FAIL' END::text,
         (count(*) FILTER (WHERE ok) || '/' || count(*) || ' socios reconcilian')::text
  FROM recon
),
-- T3 guard
g AS (
  SELECT count(*) AS n,
         count(*) FILTER (WHERE id_socio IS NULL AND socio = 'PARAMETRO_INVALIDO_PCT_OPERATIVO') AS marc
  FROM (
    SELECT id_socio, socio FROM cuenta_corriente_viva(NULL, NULL)
    UNION ALL SELECT id_socio, socio FROM cuenta_corriente_viva(NULL, 1.5)
    UNION ALL SELECT id_socio, socio FROM cuenta_corriente_viva(NULL, -0.1)
  ) q
),
r_t3 AS (
  SELECT 4, 'T3_guard'::text,
         CASE WHEN marc = 3 AND n = 3 THEN 'PASS' ELSE 'FAIL' END::text,
         (marc || '/3 casos devuelven marcador')::text
  FROM g
),
-- T4 pre-piso
t4 AS (SELECT count(*) AS n FROM cuenta_corriente_viva(DATE '2026-05-01', 0.25)),
r_t4 AS (
  SELECT 5, 'T4_pre_piso'::text,
         CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END::text,
         ('filas=' || n)::text
  FROM t4
)
SELECT test, estado, detalle
FROM (
  SELECT * FROM r_p0
  UNION ALL SELECT * FROM r_t1
  UNION ALL SELECT * FROM r_t2
  UNION ALL SELECT * FROM r_t3
  UNION ALL SELECT * FROM r_t4
) x
ORDER BY ord;
