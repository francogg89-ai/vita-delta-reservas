-- =========================================================================
-- CC_L2_DIRECTO_prueba_1grid_cuenta_corriente_detalle   --   ENTORNO: TEST
-- Prueba directa READ-ONLY de cuenta_corriente_detalle (jsonb). Una sola grilla
-- (el SQL Editor de Supabase muestra solo el ultimo SELECT). SQL puro.
--   * No escribe, no consume secuencias, no toca OPS.
--   * Correr con NADA seleccionado. Requisito: haber cargado la funcion en TEST.
--
-- Usa el mes 2026-07-01 (donde TEST tiene actividad). Los chequeos de consistencia
-- son data-agnostic: si el mes estuviera vacio, la cascada es [] y pasan vacuamente.
-- =========================================================================

WITH j AS (
  SELECT cuenta_corriente_detalle(DATE '2026-07-01', 0.25) AS d
),
casc AS (
  SELECT (e->>'paso')::int AS paso, (e->>'id_socio')::bigint AS ids, (e->>'monto')::numeric AS monto
  FROM j, jsonb_array_elements(j.d->'cascada') e
),
-- por socio: paso 11 vs paso 9 + paso 10
socio_chk AS (
  SELECT s.ids,
         (SELECT monto FROM casc WHERE paso=11 AND ids=s.ids) AS p11,
         COALESCE((SELECT monto FROM casc WHERE paso=9  AND ids=s.ids),0)
         + COALESCE((SELECT monto FROM casc WHERE paso=10 AND ids=s.ids),0) AS p9p10
  FROM (SELECT DISTINCT ids FROM casc WHERE ids IS NOT NULL) s
),
-- por gasto: suma de monto_incidido vs monto del gasto
inc AS (
  SELECT (e->>'id_gasto')::bigint AS idg, (e->>'monto')::numeric AS monto,
         (e->>'monto_incidido')::numeric AS mi
  FROM j, jsonb_array_elements(j.d->'incidencias') e
),
inc_chk AS (
  SELECT idg, MAX(monto) AS monto_gasto, SUM(mi) AS suma_incidida
  FROM inc GROUP BY idg
),
p0 AS (
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='cuenta_corriente_detalle'
  ) THEN 'PASS' ELSE 'FAIL' END AS estado
),
r AS (
  SELECT 1 AS ord, 'P0_funcion_presente'::text AS test, (SELECT estado FROM p0) AS estado,
         'cuenta_corriente_detalle'::text AS detalle
  UNION ALL
  SELECT 2, 'T1_jsonb_6_claves',
         CASE WHEN (SELECT count(*) FROM j, jsonb_object_keys(j.d) k) = 6 THEN 'PASS' ELSE 'FAIL' END,
         'claves: ' || (SELECT string_agg(k, ',' ORDER BY k) FROM j, jsonb_object_keys(j.d) k)
  UNION ALL
  SELECT 3, 'T2_guard_pct_invalido',
         CASE WHEN cuenta_corriente_detalle(DATE '2026-07-01', 1.5) ->> 'error'
                   = 'PARAMETRO_INVALIDO_PCT_OPERATIVO' THEN 'PASS' ELSE 'FAIL' END,
         COALESCE(cuenta_corriente_detalle(DATE '2026-07-01', 1.5) ->> 'error', '(sin error)')
  UNION ALL
  SELECT 4, 'T3a_paso8=suma(paso9)',
         CASE
           WHEN NOT EXISTS (SELECT 1 FROM casc WHERE paso=9) THEN 'PASS (mes vacio)'
           WHEN (SELECT monto FROM casc WHERE paso=8 AND ids IS NULL)
              = (SELECT SUM(monto) FROM casc WHERE paso=9) THEN 'PASS'
           ELSE 'FAIL' END,
         'base_de_ganancia vs reparto_por_matriz'
  UNION ALL
  SELECT 5, 'T3b_paso11=paso9+paso10',
         CASE WHEN (SELECT count(*) FROM socio_chk WHERE p11 IS DISTINCT FROM p9p10) = 0
              THEN 'PASS' ELSE 'FAIL' END,
         (SELECT count(*)::text FROM socio_chk) || ' socios chequeados'
  UNION ALL
  SELECT 6, 'T4_incidencia_suma=monto_gasto',
         CASE WHEN (SELECT count(*) FROM inc_chk WHERE abs(suma_incidida - monto_gasto) > 0.005) = 0
              THEN 'PASS' ELSE 'FAIL' END,
         (SELECT count(*)::text FROM inc_chk) || ' gastos con incidencia'
)
SELECT test, estado, detalle FROM r ORDER BY ord;
