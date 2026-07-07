-- =====================================================================
-- B1.2-core - Motor de Horarios / Carril B1
-- Artefacto 2/4: SMOKE DE PERFORMANCE (calendario operativo 120d)
-- ---------------------------------------------------------------------
-- Mide el costo del calendario operativo 120d (vista_disponibilidad =
-- ODR agregada NULL = cabanas_activas x 120 dias, 1 llamada al resolver por
-- fila) tras el cableado, en 3 escenarios, contra el baseline B1.2-pre de
-- 192.2 ms (mediana):
--   1. sin vigencia activa   -> GATE: mediana <= 288.3 ms (1.5x baseline)
--   2. con vigencia cubriendo 120d, HORAS = CONFIG ACTUAL (mide el lookup de la
--      capa vigencia sin introducir una regla nueva que pueda pisar comprometidos)
--   3. con override POR CABANA en una celda (cabana,fecha) elegida dinamicamente
--      LIBRE (sin comprometido); si no hay celda libre -> STOP claro (no error crudo)
-- + EXPLAIN del lookup de vigencia (documenta el plan real).
--
-- DEJA TEST IDENTICO: siembra en subtransacciones que revierten; secuencias
-- restauradas con setval y VERIFICADAS por last_value E is_called. Veredicto
-- tri-parte que ABORTA si algo falla y ademas se reporta en el resultado unificado:
--   META-A: filas de vigencias/reservas/pre_reservas/huespedes/overrides sin cambios.
--   META-B: secuencias de vigencias/overrides restauradas (last_value + is_called).
--   META-C: fingerprint ODR intacto (37009a32) y resolver != R0 (sigue en core).
-- ALCANCE: TEST-only. Requiere core aplicado (B1_2_CORE_MIGRACION_TEST.sql).
-- Ejecutar en Supabase SQL Editor SIN texto seleccionado (script entero).
-- =====================================================================

-- ---- GATE (core aplicado; por ESTADO) ----
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
  -- config actual (para la vigencia config-equal)
  v_ci_def TIME; v_ci_dom TIME; v_co_def TIME; v_co_dom TIME;
  -- celda libre para override por cabana
  v_ovr_cab BIGINT; v_ovr_date DATE;
  -- secuencias (last_value + is_called)
  v_seq_vig TEXT := pg_get_serial_sequence('public.vigencias_horario_base','id_vigencia');
  v_seq_ovr TEXT := pg_get_serial_sequence('public.overrides_operativos','id_override');
  v_vig_last BIGINT; v_vig_called BOOLEAN; v_ovr_last BIGINT; v_ovr_called BOOLEAN;
  v_chk_last BIGINT; v_chk_called BOOLEAN;
  -- counts pre
  v_vig_cnt0 BIGINT; v_ovr_cnt0 BIGINT; v_res_cnt0 BIGINT; v_pre_cnt0 BIGINT; v_hue_cnt0 BIGINT;
  v_line TEXT; v_metaA BOOLEAN; v_metaB BOOLEAN; v_metaC BOOLEAN;
BEGIN
  -- config de horarios actuales
  SELECT
    (SELECT valor FROM public.configuracion_general WHERE clave='hora_checkin_default')::time,
    (SELECT valor FROM public.configuracion_general WHERE clave='hora_checkin_domingo')::time,
    (SELECT valor FROM public.configuracion_general WHERE clave='hora_checkout_default')::time,
    (SELECT valor FROM public.configuracion_general WHERE clave='hora_checkout_domingo')::time
  INTO v_ci_def, v_ci_dom, v_co_def, v_co_dom;

  -- celda (cabana,fecha) LIBRE en 120d: sin ocupacion activa y sin evento checkin/checkout
  SELECT v.id_cabana, v.fecha INTO v_ovr_cab, v_ovr_date
  FROM public.vista_disponibilidad v
  WHERE v.id_reserva_activa IS NULL AND v.id_prereserva_activa IS NULL
    AND v.fecha >= CURRENT_DATE AND v.fecha < CURRENT_DATE + (N || ' days')::interval
    AND NOT EXISTS (SELECT 1 FROM public.reservas r WHERE r.id_cabana = v.id_cabana AND r.estado IN ('confirmada','activa','completada') AND (r.fecha_checkin = v.fecha OR r.fecha_checkout = v.fecha))
    AND NOT EXISTS (SELECT 1 FROM public.pre_reservas pr WHERE pr.id_cabana = v.id_cabana AND ((pr.estado='pendiente_pago' AND pr.expira_en > NOW()) OR pr.estado='pago_en_revision') AND (pr.fecha_in = v.fecha OR pr.fecha_out = v.fecha))
  ORDER BY v.fecha, v.id_cabana
  LIMIT 1;

  -- captura pre (secuencias last+is_called + counts)
  EXECUTE format('SELECT last_value, is_called FROM %s', v_seq_vig) INTO v_vig_last, v_vig_called;
  EXECUTE format('SELECT last_value, is_called FROM %s', v_seq_ovr) INTO v_ovr_last, v_ovr_called;
  SELECT count(*) INTO v_vig_cnt0 FROM public.vigencias_horario_base;
  SELECT count(*) INTO v_ovr_cnt0 FROM public.overrides_operativos;
  SELECT count(*) INTO v_res_cnt0 FROM public.reservas;
  SELECT count(*) INTO v_pre_cnt0 FROM public.pre_reservas;
  SELECT count(*) INTO v_hue_cnt0 FROM public.huespedes;

  -- Warmup (NO medido): varias corridas hasta estado estacionario (cache/plan/JIT);
  -- el baseline B1.2-pre se mide en estado estacionario.
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

  -- Escenario 2: vigencia cubriendo 120d con HORAS = CONFIG ACTUAL (subtx que revierte)
  FOR i IN 1..K LOOP
    BEGIN
      INSERT INTO public.vigencias_horario_base(fecha_desde,fecha_hasta,abierta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por,activo)
        VALUES (CURRENT_DATE, CURRENT_DATE+N, FALSE, v_ci_def, v_ci_dom, v_co_def, v_co_dom, 'perf smoke config-equal','smoke',TRUE);
      v_t0 := clock_timestamp();
      SELECT count(*) INTO v_rows FROM public.vista_disponibilidad
        WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + (N || ' days')::interval;
      v_t1 := clock_timestamp();
      v_ms := EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000;
      RAISE EXCEPTION '__RB__';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM !~ '__RB__' THEN RAISE; END IF;
    END;
    INSERT INTO _perf_res VALUES ('2_vigencia_config_equal', i, v_rows, v_ms);
  END LOOP;

  -- Escenario 3: override POR CABANA en celda libre (subtx que revierte) o STOP
  IF v_ovr_cab IS NULL THEN
    INSERT INTO _perf_meta VALUES (5, 'ESCENARIO-3', 'STOP: no hay celda (cabana,fecha) libre en 120d; override no medido.');
  ELSE
    FOR i IN 1..K LOOP
      BEGIN
        INSERT INTO public.overrides_operativos(fecha_desde,fecha_hasta,id_cabana,tipo_override,valor,motivo,creado_por,activo,source_event)
          VALUES (v_ovr_date, v_ovr_date, v_ovr_cab, 'hora_checkin', '15:00', 'perf smoke','smoke',TRUE,'perf');
        v_t0 := clock_timestamp();
        SELECT count(*) INTO v_rows FROM public.vista_disponibilidad
          WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + (N || ' days')::interval;
        v_t1 := clock_timestamp();
        v_ms := EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000;
        RAISE EXCEPTION '__RB__';
      EXCEPTION WHEN OTHERS THEN
        IF SQLERRM !~ '__RB__' THEN RAISE; END IF;
      END;
      INSERT INTO _perf_res VALUES ('3_override_cabana', i, v_rows, v_ms);
    END LOOP;
    INSERT INTO _perf_meta VALUES (5, 'ESCENARIO-3', 'override_cabana en cabana='||v_ovr_cab||' fecha='||v_ovr_date::text);
  END IF;

  -- EXPLAIN del lookup de vigencia (subtx con vigencia efimera config-equal)
  BEGIN
    INSERT INTO public.vigencias_horario_base(fecha_desde,fecha_hasta,abierta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por,activo)
      VALUES (CURRENT_DATE, CURRENT_DATE+N, FALSE, v_ci_def, v_ci_dom, v_co_def, v_co_dom, 'perf explain','smoke',TRUE);
    FOR v_line IN
      EXECUTE 'EXPLAIN SELECT hora_checkin_default FROM public.vigencias_horario_base WHERE activo AND (CASE WHEN abierta THEN daterange(fecha_desde, NULL) ELSE daterange(fecha_desde, fecha_hasta, ''[]'') END) @> (CURRENT_DATE+60) LIMIT 1'
    LOOP
      INSERT INTO _perf_meta VALUES (3, 'explain_lookup', v_line);
    END LOOP;
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM !~ '__RB__' THEN RAISE; END IF;
  END;

  -- RESTORE secuencias (setval last_value + is_called). Non-transaccional: persiste aun si luego abortamos.
  PERFORM setval(v_seq_vig::regclass, v_vig_last, v_vig_called);
  PERFORM setval(v_seq_ovr::regclass, v_ovr_last, v_ovr_called);

  -- ---- VERIFICACION META (aborta si falla; ademas se reporta unificado) ----
  -- META-A: filas sin cambios
  v_metaA := (SELECT count(*) FROM public.vigencias_horario_base) = v_vig_cnt0
         AND (SELECT count(*) FROM public.overrides_operativos)   = v_ovr_cnt0
         AND (SELECT count(*) FROM public.reservas)               = v_res_cnt0
         AND (SELECT count(*) FROM public.pre_reservas)           = v_pre_cnt0
         AND (SELECT count(*) FROM public.huespedes)              = v_hue_cnt0;
  -- META-B: secuencias restauradas (last_value E is_called; consulta directa a la secuencia)
  EXECUTE format('SELECT last_value, is_called FROM %s', v_seq_vig) INTO v_chk_last, v_chk_called;
  v_metaB := (v_chk_last = v_vig_last AND v_chk_called = v_vig_called);
  EXECUTE format('SELECT last_value, is_called FROM %s', v_seq_ovr) INTO v_chk_last, v_chk_called;
  v_metaB := v_metaB AND (v_chk_last = v_ovr_last AND v_chk_called = v_ovr_called);
  -- META-C: fingerprints
  v_metaC := md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure)) = '37009a32154f93b80520500c0f15b46b'
         AND md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure)) <> '58d75c1b6b812ee2d2c9751ddcb0cd4d';

  IF NOT (v_metaA AND v_metaB AND v_metaC) THEN
    RAISE EXCEPTION 'PERF META FAIL: A_filas=% B_secuencias=% C_fingerprints=%. TEST no quedo identico / estado alterado. Revisar antes de confiar en los numeros.', v_metaA, v_metaB, v_metaC;
  END IF;
  INSERT INTO _perf_meta VALUES
    (10, 'META-A_filas_sin_cambios',            'OK'),
    (11, 'META-B_secuencias_last+is_called',    'OK'),
    (12, 'META-C_fingerprints',                 'OK');
END
$perf$;

-- ---- Reporte UNIFICADO (ULTIMO): META + STOP + EXPLAIN + escenarios en un solo result set ----
WITH esc AS (
  SELECT escenario,
         min(filas) AS filas,
         round(min(ms)::numeric, 1) AS ms_min,
         round((percentile_cont(0.5) WITHIN GROUP (ORDER BY ms))::numeric, 1) AS ms_mediana,
         round(max(ms)::numeric, 1) AS ms_max,
         round((percentile_cont(0.5) WITHIN GROUP (ORDER BY ms))::numeric / 192.2, 2) AS ratio,
         CASE WHEN escenario = '1_sin_vigencia'
              THEN CASE WHEN percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) <= 288.3
                        THEN 'GATE OK (<=288.3ms)' ELSE 'GATE FAIL (>288.3ms)' END
              ELSE '' END AS gate
  FROM _perf_res GROUP BY escenario
)
SELECT 'META/PLAN'::text AS seccion, orden AS ref, k AS item, v AS detalle, NULL::numeric AS ratio_vs_baseline, ''::text AS gate
FROM _perf_meta
UNION ALL
SELECT 'PERF', 100, escenario, 'filas='||filas||' mediana='||ms_mediana||'ms (min '||ms_min||' / max '||ms_max||')', ratio, gate
FROM esc
ORDER BY seccion, ref, item;

COMMIT;

DROP TABLE IF EXISTS pg_temp._perf_res;
DROP TABLE IF EXISTS pg_temp._perf_meta;
