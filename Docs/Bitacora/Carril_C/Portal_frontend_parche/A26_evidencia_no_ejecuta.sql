-- ============================================================================
-- A26_evidencia_no_ejecuta.sql  --  Carril C / Bloque A (Opcion B)
-- EVIDENCIA en TEST de que, con id_cabana inexistente/inactiva, la funcion
-- obtener_disponibilidad_rango(...) NO se evalua (compuerta CTE + LATERAL).
--
-- READ-ONLY: EXPLAIN ANALYZE ejecuta la consulta, pero la consulta es un SELECT
-- que solo invoca una funcion de lectura; no hay DML. No muta nada, no consume
-- secuencias. (L-8A-01: el editor corre solo el texto seleccionado.)
--
-- Que mirar:
--   [INVALIDA] el plan debe mostrar, en el Function Scan de
--              obtener_disponibilidad_rango, la marca "(never executed)".
--              => la funcion canonica NO se invoco.
--   [VALIDA]   el mismo Function Scan debe figurar ejecutado (loops=1, rows=N).
--              => la funcion se invoco una sola vez y devolvio las noches.
-- Es la query EXACTA del nodo "PG: disponibilidad" del wrapper (el parametro
-- $1::jsonb se reemplaza aca por un literal para poder correrlo en el editor).
-- ============================================================================


-- [INVALIDA] -----------------------------------------------------------------
-- id_cabana inexistente (o cambiar por una INACTIVA). Buscar "(never executed)".
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF, TIMING OFF)
WITH valida AS (
  SELECT c.id_cabana
  FROM cabanas c
  WHERE c.id_cabana = ('{"id_cabana":999999,"fecha_desde":"2026-07-01","fecha_hasta":"2026-07-08"}'::jsonb ->> 'id_cabana')::bigint
    AND c.activa = TRUE
),
existe AS (
  SELECT EXISTS(SELECT 1 FROM valida) AS cabana_existe
),
disp AS (
  SELECT f.fecha, f.estado, f.id_cabana, f.hora_checkin_base, f.hora_checkout_base
  FROM valida v
  CROSS JOIN LATERAL obtener_disponibilidad_rango(
    ('{"id_cabana":999999,"fecha_desde":"2026-07-01","fecha_hasta":"2026-07-08"}'::jsonb ->> 'fecha_desde')::date,
    ('{"id_cabana":999999,"fecha_desde":"2026-07-01","fecha_hasta":"2026-07-08"}'::jsonb ->> 'fecha_hasta')::date,
    v.id_cabana
  ) AS f
)
SELECT e.cabana_existe, d.fecha, d.estado, d.id_cabana, d.hora_checkin_base, d.hora_checkout_base
FROM existe e
LEFT JOIN disp d ON TRUE
ORDER BY d.fecha NULLS LAST;


-- [VALIDA] -------------------------------------------------------------------
-- id_cabana de una cabana ACTIVA (ajustar el 1). El Function Scan debe ejecutarse.
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF, TIMING OFF)
WITH valida AS (
  SELECT c.id_cabana
  FROM cabanas c
  WHERE c.id_cabana = ('{"id_cabana":1,"fecha_desde":"2026-07-01","fecha_hasta":"2026-07-08"}'::jsonb ->> 'id_cabana')::bigint
    AND c.activa = TRUE
),
existe AS (
  SELECT EXISTS(SELECT 1 FROM valida) AS cabana_existe
),
disp AS (
  SELECT f.fecha, f.estado, f.id_cabana, f.hora_checkin_base, f.hora_checkout_base
  FROM valida v
  CROSS JOIN LATERAL obtener_disponibilidad_rango(
    ('{"id_cabana":1,"fecha_desde":"2026-07-01","fecha_hasta":"2026-07-08"}'::jsonb ->> 'fecha_desde')::date,
    ('{"id_cabana":1,"fecha_desde":"2026-07-01","fecha_hasta":"2026-07-08"}'::jsonb ->> 'fecha_hasta')::date,
    v.id_cabana
  ) AS f
)
SELECT e.cabana_existe, d.fecha, d.estado, d.id_cabana, d.hora_checkin_base, d.hora_checkout_base
FROM existe e
LEFT JOIN disp d ON TRUE
ORDER BY d.fecha NULLS LAST;
