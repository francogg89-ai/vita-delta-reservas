-- =====================================================================
-- B1.2-core - Motor de Horarios / Carril B1
-- Artefacto 2/4: SMOKE DE PERFORMANCE (calendario operativo 120d)
-- ---------------------------------------------------------------------
-- Mide el costo del calendario operativo 120d (vista_disponibilidad =
-- ODR agregada NULL = 5 cabanas x 120 dias = 600 filas, 600 llamadas al
-- resolver) tras el cableado, en 3 escenarios, contra el baseline B1.2-pre
-- de 192.2 ms (mediana):
--   1. sin vigencia activa   -> GATE: mediana <= 288.3 ms (1.5x baseline)
--   2. con vigencia cubriendo 120d (lookup por fila)
--   3. con override puntual
-- + EXPLAIN del lookup de vigencia (documenta el plan real: seqscan de tabla chica).
--
-- DEJA TEST IDENTICO: siembra en subtransacciones que revierten; secuencias
-- restauradas con setval. Veredicto tri-parte (registrado, no aborta):
--   META-A: filas de vigencias/reservas/pre_reservas/huespedes/overrides sin cambios.
--   META-B: secuencias de vigencias/overrides restauradas al valor previo.
--   META-C: fingerprint ODR intacto (37009a32) y resolver != R0 (sigue en core).
-- ALCANCE: TEST-only. Requiere core aplicado (B1_2_CORE_MIGRACION_TEST.sql).
-- Ejecutar en Supabase SQL Editor SIN texto seleccionado (script entero).
-- =====================================================================

-- ---- GATE (core aplicado; por ESTADO, no por fp exacto del wrapper nuevo) ----
DO $gate$
DECLARE v_amb text; v_res text; v_odr text;
BEGIN
  SELECT valor INTO v_amb FROM public.configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE core-perf: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'GATE core-perf: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NULL THEN
    RAISE EXCEPTION 'GATE core-perf: _resolver_horario no existe (core no aplicado). Abortando.';
  END IF;
  v_res := md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure));
  IF v_res = '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'GATE core-perf: resolver sigue en R0 (core no aplicado). Abortando.';
  END IF;
  v_odr := md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE core-perf: ODR fp=% (esperado 37009a32... intacto). Abortando.', v_odr;
  END IF;
END
$gate$;

SET client_min_messages = warning;

DROP TABLE IF EXISTS pg_temp._perf_res;
DROP TABLE IF EXISTS pg_temp._perf_meta;
BEGIN;
CREATE TEMP TABLE _perf_res(escenario TEXT, corrida INT, filas BIGINT, ms NUMERIC) ON COMMIT DROP;
CREATE TEMP TABLE _perf_meta(orden INT, k TEXT, v TEXT) ON COMMIT DROP;

DO $perf$
DECLARE
  N INT := 120; K INT := 3; i INT;
  v_t0 TIMESTAMPTZ; v_t1 TIMESTAMPTZ; v_rows BIGINT; v_ms NUMERIC;
  v_seq_vig TEXT := pg_get_serial_sequence('public.vigencias_horario_base','id_vigencia');
  v_seq_ovr TEXT := pg_get_serial_sequence('public.overrides_operativos','id_override');
  v_vig_last BIGINT; v_vig_called BOOLEAN; v_ovr_last BIGINT; v_ovr_called BOOLEAN;
  v_vig_cnt0 BIGINT; v_ovr_cnt0 BIGINT; v_res_cnt0 BIGINT; v_pre_cnt0 BIGINT; v_hue_cnt0 BIGINT;
  v_line TEXT; v_ok BOOLEAN;
BEGIN
  -- captura pre (secuencias + counts)
  EXECUTE format('SELECT last_value, is_called FROM %s', v_seq_vig) INTO v_vig_last, v_vig_called;
  EXECUTE format('SELECT last_value, is_called FROM %s', v_seq_ovr) INTO v_ovr_last, v_ovr_called;
  SELECT count(*) INTO v_vig_cnt0 FROM public.vigencias_horario_base;
  SELECT count(*) INTO v_ovr_cnt0 FROM public.overrides_operativos;
  SELECT count(*) INTO v_res_cnt0 FROM public.reservas;
  SELECT count(*) INTO v_pre_cnt0 FROM public.pre_reservas;
  SELECT count(*) INTO v_hue_cnt0 FROM public.huespedes;

  -- Warmup (NO medido): varias corridas hasta estado estacionario (cache de
  -- paginas / plan / JIT). El baseline B1.2-pre se mide en estado estacionario;
  -- con una sola corrida la 1a medicion cae en la curva de calentamiento.
  FOR i IN 1..5 LOOP
    PERFORM count(*) FROM public.vista_disponibilidad
      WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + (N || ' days')::interval;
  END LOOP;

  -- Escenario 1: sin vigencia activa
  FOR i IN 1..K LOOP
    v_t0 := clock_timestamp();
    SELECT count(*) INTO v_rows FROM public.vista_disponibilidad
      WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + (N || ' days')::interval;
    v_t1 := clock_timestamp();
    INSERT INTO _perf_res VALUES ('1_sin_vigencia', i, v_rows, EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000);
  END LOOP;

  -- Escenario 2: con vigencia cubriendo 120d (subtx que revierte)
  FOR i IN 1..K LOOP
    BEGIN
      INSERT INTO public.vigencias_horario_base(fecha_desde,fecha_hasta,abierta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por,activo)
        VALUES (CURRENT_DATE, CURRENT_DATE+N, FALSE, '14:00','19:00','11:00','17:00','perf smoke','smoke',TRUE);
      v_t0 := clock_timestamp();
      SELECT count(*) INTO v_rows FROM public.vista_disponibilidad
        WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + (N || ' days')::interval;
      v_t1 := clock_timestamp();
      v_ms := EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000;
      RAISE EXCEPTION '__RB__';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM !~ '__RB__' THEN RAISE; END IF;
    END;
    INSERT INTO _perf_res VALUES ('2_con_vigencia_120d', i, v_rows, v_ms);
  END LOOP;

  -- Escenario 3: override puntual (subtx que revierte)
  FOR i IN 1..K LOOP
    BEGIN
      INSERT INTO public.overrides_operativos(fecha_desde,fecha_hasta,id_cabana,tipo_override,valor,motivo,creado_por,activo,source_event)
        VALUES (CURRENT_DATE+10, CURRENT_DATE+10, NULL, 'hora_checkin', '15:00', 'perf smoke','smoke',TRUE,'perf');
      v_t0 := clock_timestamp();
      SELECT count(*) INTO v_rows FROM public.vista_disponibilidad
        WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + (N || ' days')::interval;
      v_t1 := clock_timestamp();
      v_ms := EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000;
      RAISE EXCEPTION '__RB__';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM !~ '__RB__' THEN RAISE; END IF;
    END;
    INSERT INTO _perf_res VALUES ('3_override_puntual', i, v_rows, v_ms);
  END LOOP;

  -- EXPLAIN del lookup de vigencia (subtx con vigencia efimera)
  BEGIN
    INSERT INTO public.vigencias_horario_base(fecha_desde,fecha_hasta,abierta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por,activo)
      VALUES (CURRENT_DATE, CURRENT_DATE+N, FALSE, '14:00','19:00','11:00','17:00','perf explain','smoke',TRUE);
    FOR v_line IN
      EXECUTE 'EXPLAIN SELECT hora_checkin_default FROM public.vigencias_horario_base WHERE activo AND (CASE WHEN abierta THEN daterange(fecha_desde, NULL) ELSE daterange(fecha_desde, fecha_hasta, ''[]'') END) @> (CURRENT_DATE+60) LIMIT 1'
    LOOP
      INSERT INTO _perf_meta VALUES (3, 'explain_lookup', v_line);
    END LOOP;
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM !~ '__RB__' THEN RAISE; END IF;
  END;

  -- RESTORE secuencias (META-B): los inserts revertidos avanzaron nextval (no transaccional).
  PERFORM setval(v_seq_vig::regclass, v_vig_last, v_vig_called);
  PERFORM setval(v_seq_ovr::regclass, v_ovr_last, v_ovr_called);

  -- META-A: filas sin cambios
  v_ok := (SELECT count(*) FROM public.vigencias_horario_base) = v_vig_cnt0
      AND (SELECT count(*) FROM public.overrides_operativos)   = v_ovr_cnt0
      AND (SELECT count(*) FROM public.reservas)               = v_res_cnt0
      AND (SELECT count(*) FROM public.pre_reservas)           = v_pre_cnt0
      AND (SELECT count(*) FROM public.huespedes)              = v_hue_cnt0;
  INSERT INTO _perf_meta VALUES (10, 'META-A_filas_sin_cambios', CASE WHEN v_ok THEN 'OK' ELSE 'FAIL' END);
  -- META-B: secuencias restauradas
  v_ok := (SELECT last_value FROM pg_sequences WHERE schemaname||'.'||sequencename = v_seq_vig) = v_vig_last
      AND (SELECT last_value FROM pg_sequences WHERE schemaname||'.'||sequencename = v_seq_ovr) = v_ovr_last;
  INSERT INTO _perf_meta VALUES (11, 'META-B_secuencias_restauradas', CASE WHEN v_ok THEN 'OK' ELSE 'FAIL' END);
  -- META-C: fingerprints
  v_ok := md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure)) = '37009a32154f93b80520500c0f15b46b'
      AND md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure)) <> '58d75c1b6b812ee2d2c9751ddcb0cd4d';
  INSERT INTO _perf_meta VALUES (12, 'META-C_fingerprints', CASE WHEN v_ok THEN 'OK' ELSE 'FAIL' END);
END
$perf$;

-- ---- Reporte 1: META + EXPLAIN (diagnostico) ----
SELECT k AS meta, v AS valor FROM _perf_meta ORDER BY orden, k;

-- ---- Reporte 2 (ULTIMO, KEY): resumen por escenario + ratio + gate ----
SELECT
  escenario,
  min(filas) AS filas,
  round(min(ms)::numeric, 1) AS ms_min,
  round((percentile_cont(0.5) WITHIN GROUP (ORDER BY ms))::numeric, 1) AS ms_mediana,
  round(max(ms)::numeric, 1) AS ms_max,
  round((percentile_cont(0.5) WITHIN GROUP (ORDER BY ms))::numeric / 192.2, 2) AS ratio_vs_baseline,
  CASE WHEN escenario = '1_sin_vigencia'
       THEN CASE WHEN percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) <= 288.3
                 THEN 'GATE OK (<=288.3ms)' ELSE 'GATE FAIL (>288.3ms)' END
       ELSE '' END AS gate
FROM _perf_res
GROUP BY escenario
ORDER BY escenario;

COMMIT;

DROP TABLE IF EXISTS pg_temp._perf_res;
DROP TABLE IF EXISTS pg_temp._perf_meta;
