-- =====================================================================
-- B1.2-pre - Integracion de vigencias en resolver_horario
-- Artefacto 2/2: BASELINE DE PERFORMANCE - calendario operativo 120 dias
-- -----------------------------------------------------------------------
-- OBJETIVO: medir el costo ACTUAL (resolver R0, ciego a vigencias) del
--   calendario operativo 120d, para comparar contra el post-cambio en
--   B1.2-core (gate de performance: si se degrada visiblemente, core no
--   queda aprobado).
-- FORMA REAL DE CONSUMO (verificada en el repo):
--   * A04 (calendario operativo) lee vista_disponibilidad filtrada a 120d.
--   * vista_disponibilidad = obtener_disponibilidad_rango(CURRENT_DATE,
--       CURRENT_DATE + horizonte(fallback 120), NULL) => AGREGADA (todas las
--       cabanas activas), 1 llamada a resolver_horario por fila (cabana x fecha)
--       = ~600 llamadas (120d x 5 cabanas) por scan.
-- MEDICION: clock_timestamp() (avanza dentro de la transaccion), K corridas
--   por forma; se reporta min / mediana / max en ms + filas.
-- ALCANCE: read-only. NO muta, NO consume secuencia, NO toca resolver_horario,
--   OPS, portal-api, frontend, wrappers n8n, Vercel, canonico ni config.
-- NOTA: el EXPLAIN del lookup de vigencias NO va aca (el lookup no existe en
--   R0); va en la perf smoke de B1.2-core, junto con los 3 escenarios de datos.
-- =====================================================================

-- ---- GATE anti-ambiente + estado esperado (read-only) ----
DO $gate$
DECLARE v_amb TEXT; v_res TEXT; v_odr TEXT;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE B1.2-pre-perf: ambiente=% (esperado test). Abortando.', v_amb;
  END IF;
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'GATE B1.2-pre-perf: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  v_res := md5(pg_get_functiondef('resolver_horario(bigint,date)'::regprocedure));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'GATE B1.2-pre-perf: fingerprint resolver=% (esperado 58d75c1b6b812ee2d2c9751ddcb0cd4d, estado B1.1/R0). Abortando.', v_res;
  END IF;
  v_odr := md5(pg_get_functiondef('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE B1.2-pre-perf: fingerprint ODR=% (esperado 37009a32154f93b80520500c0f15b46b). Abortando.', v_odr;
  END IF;
  IF to_regclass('public.vista_disponibilidad') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.2-pre-perf: falta vista_disponibilidad. Abortando.';
  END IF;
END
$gate$;

SET client_min_messages = warning;

-- Hardening temp table: DROP calificado pg_temp (nunca puede tocar una tabla
-- real public._perf_base) + ON COMMIT DROP. El wrapper BEGIN/COMMIT es
-- necesario para que ON COMMIT DROP funcione a traves de la medicion
-- multi-statement (CREATE + DO + SELECT en la MISMA transaccion); en
-- autocommit sin el, la temp se caeria al terminar el CREATE.
DROP TABLE IF EXISTS pg_temp._perf_base;
BEGIN;
CREATE TEMP TABLE _perf_base(forma TEXT, corrida INT, filas BIGINT, ms NUMERIC) ON COMMIT DROP;

DO $perf$
DECLARE
  N INT := 120;   -- horizonte de dias del calendario operativo
  K INT := 3;     -- corridas por forma (suaviza cache frio)
  i INT;
  v_t0 TIMESTAMPTZ; v_t1 TIMESTAMPTZ;
  v_rows BIGINT;
  v_sum BIGINT;
  r RECORD;
BEGIN
  -- Forma 1: consumo REAL A04 (vista_disponibilidad filtrada 120d)
  FOR i IN 1..K LOOP
    v_t0 := clock_timestamp();
    SELECT count(*) INTO v_rows FROM vista_disponibilidad
      WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + (N || ' days')::interval;
    v_t1 := clock_timestamp();
    INSERT INTO _perf_base VALUES ('A04_vista_disponibilidad_120d', i, v_rows, EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000);
  END LOOP;

  -- Forma 2: ODR agregada directa (todas las cabanas, p_id_cabana = NULL)
  FOR i IN 1..K LOOP
    v_t0 := clock_timestamp();
    SELECT count(*) INTO v_rows FROM obtener_disponibilidad_rango(CURRENT_DATE, CURRENT_DATE + N, NULL);
    v_t1 := clock_timestamp();
    INSERT INTO _perf_base VALUES ('ODR_agregada_NULL_120d', i, v_rows, EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000);
  END LOOP;

  -- Forma 3: por-cabana en loop (referencia; suma de cabanas activas)
  FOR i IN 1..K LOOP
    v_sum := 0;
    v_t0 := clock_timestamp();
    FOR r IN SELECT id_cabana FROM cabanas WHERE activa ORDER BY id_cabana LOOP
      SELECT count(*) INTO v_rows FROM obtener_disponibilidad_rango(CURRENT_DATE, CURRENT_DATE + N, r.id_cabana);
      v_sum := v_sum + v_rows;
    END LOOP;
    v_t1 := clock_timestamp();
    INSERT INTO _perf_base VALUES ('ODR_por_cabana_loop_120d', i, v_sum, EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000);
  END LOOP;
END
$perf$;

-- Resumen (unico result set): por forma, min / mediana / max ms + filas
SELECT
  forma,
  min(filas) AS filas,
  round(min(ms), 1) AS ms_min,
  round((percentile_cont(0.5) WITHIN GROUP (ORDER BY ms))::numeric, 1) AS ms_mediana,
  round(max(ms), 1) AS ms_max
FROM _perf_base
GROUP BY forma
ORDER BY forma;
COMMIT;   -- dispara ON COMMIT DROP: la temp se cae aca

DROP TABLE IF EXISTS pg_temp._perf_base;   -- cinturon (no-op tras ON COMMIT DROP)
