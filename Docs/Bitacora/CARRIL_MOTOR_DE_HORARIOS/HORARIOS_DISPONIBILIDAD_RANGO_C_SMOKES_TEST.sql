-- =====================================================================
-- HORARIOS_DISPONIBILIDAD_RANGO_C_SMOKES_TEST.sql   (REV 2)
-- C) Smokes completos de obtener_disponibilidad_rango integrada. SOLO TEST.
--    C NO es read-only: hace WRITES CONTROLADOS de fixture dentro de la
--    transaccion, con TEARDOWN antes del COMMIT -> CERO RESIDUOS.
--
-- Cambios rev 2:
--   [1] GATE anti-OPS al inicio (ambiente/schema/funciones/fingerprints post-A),
--       ANTES de crear el oracle o sembrar fixture. RAISE EXCEPTION aborta.
--   [2] Visibilidad Supabase: _smoke_res es TEMP ON COMMIT PRESERVE ROWS creada
--       ANTES del BEGIN; el bloque cierra en COMMIT y el ULTIMO statement es
--       SELECT * FROM _smoke_res (ya no queda tapado por un ROLLBACK).
--   [3] Oracle en pg_temp (pg_temp._smoke_odr_vieja) -> sin DDL temporal en public.
--
-- Garantia de limpieza: el fixture (overrides+bloqueo marcados '__SMOKE_HORARIOS__')
--   se BORRA en el TEARDOWN antes del COMMIT. Si el script explota antes del
--   teardown, la transaccion ABORTA y no persiste nada. Si termina bien, queda
--   persistida SOLO la limpieza (fixture=0), nunca los datos del fixture.
--
-- COMO CORRERLO: correr con NADA seleccionado. El resultado visible es la tabla
--   _smoke_res (una fila por caso + VEREDICTO FINAL). Pegamela.
-- =====================================================================

-- Tabla de resultados: TEMP, sobrevive al COMMIT para poder mostrarse al final.
DROP TABLE IF EXISTS _smoke_res;
CREATE TEMP TABLE _smoke_res (orden int, caso text, esperado text, obtenido text, pass boolean)
  ON COMMIT PRESERVE ROWS;

BEGIN;

-- ---------------------------------------------------------------------
-- [1] GATE anti-OPS (antes de tocar cualquier fixture / oracle)
-- ---------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM configuracion_general WHERE clave = 'ambiente');
  v_odr text;
  v_res text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE C: ambiente=% (esperado test). Abortando smoke.', v_amb;
  END IF;
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'GATE C: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('public.fecha_hoy_ar()') IS NULL THEN
    RAISE EXCEPTION 'GATE C: no existe fecha_hoy_ar(). Abortando.';
  END IF;
  IF to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)') IS NULL THEN
    RAISE EXCEPTION 'GATE C: no existe obtener_disponibilidad_rango(date,date,bigint). Abortando.';
  END IF;
  IF to_regprocedure('public.resolver_horario(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'GATE C: no existe resolver_horario(bigint,date). Abortando.';
  END IF;
  v_odr := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE C: fingerprint ODR=% (esperado 37009a32154f93b80520500c0f15b46b). Abortando.', v_odr;
  END IF;
  v_res := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
  IF v_res IS DISTINCT FROM '759662b4afaed7af426917aa3717b34c' THEN
    RAISE EXCEPTION 'GATE C: fingerprint resolver=% (esperado 759662b4afaed7af426917aa3717b34c). Abortando.', v_res;
  END IF;
  RAISE NOTICE 'GATE C OK: ambiente=test, schema=public, fecha_hoy_ar/ODR/resolver presentes, fingerprints post-A esperados.';
  INSERT INTO _smoke_res VALUES (-1, 'GATE anti-OPS (ambiente/schema/funciones/fingerprints post-A)', 'todo OK', 'OK', true);
END
$gate$;

-- ---------------------------------------------------------------------
-- ORACLE en pg_temp (funcion vieja, CASE hardcodeados). Se DROPea en TEARDOWN.
-- ---------------------------------------------------------------------
CREATE FUNCTION pg_temp._smoke_odr_vieja(
  p_fecha_desde DATE, p_fecha_hasta DATE, p_id_cabana BIGINT DEFAULT NULL
)
RETURNS TABLE (
  id_cabana BIGINT, fecha DATE, estado TEXT, tipo_dia TEXT, temporada TEXT,
  hora_checkin_base TIME, hora_checkout_base TIME,
  id_reserva_activa BIGINT, id_prereserva_activa BIGINT
)
LANGUAGE plpgsql
AS $oracle$
BEGIN
  RETURN QUERY
  WITH dias AS (
    SELECT generate_series(p_fecha_desde, p_fecha_hasta - INTERVAL '1 day', '1 day')::DATE AS d
  ),
  cabanas_activas AS (
    SELECT c.id_cabana, c.nombre
    FROM cabanas c
    WHERE c.activa = TRUE
      AND (p_id_cabana IS NULL OR c.id_cabana = p_id_cabana)
  ),
  matriz AS (
    SELECT ca.id_cabana, d.d AS fecha
    FROM cabanas_activas ca
    CROSS JOIN dias d
  )
  SELECT
    m.id_cabana,
    m.fecha,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM bloqueos b
        WHERE b.activo = TRUE
          AND (b.id_cabana = m.id_cabana OR b.id_cabana IS NULL)
          AND m.fecha >= b.fecha_desde
          AND m.fecha < b.fecha_hasta
      ) THEN 'bloqueada'
      WHEN EXISTS (
        SELECT 1 FROM reservas r
        WHERE r.id_cabana = m.id_cabana
          AND r.estado IN ('confirmada', 'activa')
          AND m.fecha >= r.fecha_checkin
          AND m.fecha < r.fecha_checkout
      ) THEN 'ocupada'
      WHEN EXISTS (
        SELECT 1 FROM pre_reservas pr
        WHERE pr.id_cabana = m.id_cabana
          AND (
            (pr.estado = 'pendiente_pago' AND pr.expira_en > NOW())
            OR pr.estado = 'pago_en_revision'
          )
          AND m.fecha >= pr.fecha_in
          AND m.fecha < pr.fecha_out
      ) THEN 'ocupada'
      WHEN EXISTS (
        SELECT 1 FROM reservas r
        WHERE r.id_cabana = m.id_cabana
          AND r.estado IN ('confirmada', 'activa', 'completada')
          AND r.fecha_checkout = m.fecha
      ) THEN 'checkout_disponible'
      ELSE 'disponible'
    END AS estado,
    CASE
      WHEN EXISTS (SELECT 1 FROM feriados f WHERE f.fecha = m.fecha AND f.activo = TRUE) THEN 'feriado'
      WHEN EXTRACT(DOW FROM m.fecha) IN (5, 6) THEN 'finde'
      ELSE 'semana'
    END AS tipo_dia,
    (
      SELECT t.nombre FROM temporadas t
      WHERE t.activa = TRUE
        AND m.fecha BETWEEN t.fecha_desde AND t.fecha_hasta
      LIMIT 1
    ) AS temporada,
    CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '18:00' ELSE TIME '13:00' END AS hora_checkin_base,
    CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '16:00' ELSE TIME '10:00' END AS hora_checkout_base,
    (
      SELECT r.id_reserva FROM reservas r
      WHERE r.id_cabana = m.id_cabana
        AND r.estado IN ('confirmada', 'activa')
        AND m.fecha >= r.fecha_checkin
        AND m.fecha < r.fecha_checkout
      LIMIT 1
    ) AS id_reserva_activa,
    (
      SELECT pr.id_pre_reserva FROM pre_reservas pr
      WHERE pr.id_cabana = m.id_cabana
        AND (
          (pr.estado = 'pendiente_pago' AND pr.expira_en > NOW())
          OR pr.estado = 'pago_en_revision'
        )
        AND m.fecha >= pr.fecha_in
        AND m.fecha < pr.fecha_out
      LIMIT 1
    ) AS id_prereserva_activa
  FROM matriz m;
END;
$oracle$;

-- ---------------------------------------------------------------------
-- E2E: SETUP fixture + 12 casos + TEARDOWN de datos (asserts "soft")
-- ---------------------------------------------------------------------
DO $smoke$
DECLARE
  v_g  date := fecha_hoy_ar() + 300;  -- dia con overrides VALIDOS (checkin global 14:00 + cab1 15:00)
  v_h  date := fecha_hoy_ar() + 301;  -- dia con override CORRUPTO GLOBAL (checkin 25:99)
  v_i  date := fecha_hoy_ar() + 302;  -- dia con override CORRUPTO POR CABANA (cab1 checkin 24:61)
  v_j  date := fecha_hoy_ar() + 303;  -- bloqueo [v_j, v_j+2)
  v_args text; v_res text;
  v_n bigint; v_n2 bigint;
  v_hc time; v_ho time; v_hc1 time; v_ho1 time; v_hc2 time; v_ho2 time;
  v_e1 text; v_e2 text; v_e3 text;
  v_cnt bigint; v_dist bigint; v_min bigint; v_max bigint; v_inact boolean;
  v_ok boolean; t0 timestamptz; t1 timestamptz; v_ms double precision;
  v_ovr bigint; v_blq bigint;
BEGIN
  -- ===== SETUP: sembrar fixture (marcado) en fechas lejanas =====
  INSERT INTO overrides_operativos(fecha_desde,fecha_hasta,id_cabana,tipo_override,valor,motivo,creado_por,source_event)
    VALUES (v_g, v_g, NULL, 'hora_checkin', '14:00', '__SMOKE_HORARIOS__','smoke','__SMOKE_HORARIOS__');  -- global valido
  INSERT INTO overrides_operativos(fecha_desde,fecha_hasta,id_cabana,tipo_override,valor,motivo,creado_por,source_event)
    VALUES (v_g, v_g, 1, 'hora_checkin', '15:00', '__SMOKE_HORARIOS__','smoke','__SMOKE_HORARIOS__');     -- cab1 gana al global
  INSERT INTO overrides_operativos(fecha_desde,fecha_hasta,id_cabana,tipo_override,valor,motivo,creado_por,source_event)
    VALUES (v_h, v_h, NULL, 'hora_checkin', '25:99', '__SMOKE_HORARIOS__','smoke','__SMOKE_HORARIOS__');  -- corrupto global (cast_invalido)
  INSERT INTO overrides_operativos(fecha_desde,fecha_hasta,id_cabana,tipo_override,valor,motivo,creado_por,source_event)
    VALUES (v_i, v_i, 1, 'hora_checkin', '24:61', '__SMOKE_HORARIOS__','smoke','__SMOKE_HORARIOS__');     -- corrupto por cabana
  INSERT INTO bloqueos(id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,descripcion)
    VALUES (2, v_j, v_j + 2, 'mantenimiento','smoke','__SMOKE_HORARIOS__','__SMOKE_HORARIOS__');          -- bloqueo [v_j, v_j+2)
  INSERT INTO _smoke_res VALUES (0,'SETUP','fixture sembrado','ok',true);

  -- ===== Caso 1: no-regresion columnas/firma =====
  v_args := pg_get_function_arguments('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure);
  v_res  := pg_get_function_result('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure);
  v_ok := (v_args = 'p_fecha_desde date, p_fecha_hasta date, p_id_cabana bigint DEFAULT NULL::bigint'
       AND v_res  = 'TABLE(id_cabana bigint, fecha date, estado text, tipo_dia text, temporada text, hora_checkin_base time without time zone, hora_checkout_base time without time zone, id_reserva_activa bigint, id_prereserva_activa bigint)');
  INSERT INTO _smoke_res VALUES (1,'no-regresion columnas/firma','args+result canonicos', CASE WHEN v_ok THEN 'coincide' ELSE 'DIFIERE' END, v_ok);

  -- ===== Caso 2: no-regresion de estados (NUEVA vs VIEJA, rango cercano) =====
  SELECT count(*) INTO v_n FROM (
    SELECT id_cabana,fecha,estado FROM obtener_disponibilidad_rango(fecha_hoy_ar(), fecha_hoy_ar()+120, NULL)
    EXCEPT SELECT id_cabana,fecha,estado FROM pg_temp._smoke_odr_vieja(fecha_hoy_ar(), fecha_hoy_ar()+120, NULL)) d;
  SELECT count(*) INTO v_n2 FROM (
    SELECT id_cabana,fecha,estado FROM pg_temp._smoke_odr_vieja(fecha_hoy_ar(), fecha_hoy_ar()+120, NULL)
    EXCEPT SELECT id_cabana,fecha,estado FROM obtener_disponibilidad_rango(fecha_hoy_ar(), fecha_hoy_ar()+120, NULL)) d;
  v_ok := (v_n = 0 AND v_n2 = 0);
  INSERT INTO _smoke_res VALUES (2,'no-regresion estados (nueva=vieja, 120d)','0 diferencias', format('dif=%s / %s', v_n, v_n2), v_ok);

  -- ===== Caso 3: semantica [in,out) + checkout_disponible =====
  --  (a) columnas NO-horas identicas nueva vs vieja (codifican ocupada [in,out) y checkout_disponible sobre datos reales)
  --  (b) bloqueo determinista [v_j, v_j+2): v_j y v_j+1 bloqueada, v_j+2 NO (media-abierta)
  SELECT count(*) INTO v_n FROM (
    SELECT id_cabana,fecha,estado,tipo_dia,temporada,id_reserva_activa,id_prereserva_activa
      FROM obtener_disponibilidad_rango(fecha_hoy_ar(), fecha_hoy_ar()+120, NULL)
    EXCEPT
    SELECT id_cabana,fecha,estado,tipo_dia,temporada,id_reserva_activa,id_prereserva_activa
      FROM pg_temp._smoke_odr_vieja(fecha_hoy_ar(), fecha_hoy_ar()+120, NULL)) d;
  SELECT estado INTO v_e1 FROM obtener_disponibilidad_rango(v_j,   v_j+1, 2);
  SELECT estado INTO v_e2 FROM obtener_disponibilidad_rango(v_j+1, v_j+2, 2);
  SELECT estado INTO v_e3 FROM obtener_disponibilidad_rango(v_j+2, v_j+3, 2);
  v_ok := (v_n = 0 AND v_e1 = 'bloqueada' AND v_e2 = 'bloqueada' AND v_e3 <> 'bloqueada');
  INSERT INTO _smoke_res VALUES (3,'semantica [in,out)+checkout_disp (oracle no-horas + bloqueo media-abierta)','no-horas idem & [j,j+1] bloq, j+2 libre', format('dif=%s j=%s j1=%s j2=%s', v_n, v_e1, v_e2, v_e3), v_ok);

  -- ===== Caso 4: override VALIDO GLOBAL (cab 2 usa checkin 14:00) =====
  SELECT hora_checkin_base INTO v_hc FROM obtener_disponibilidad_rango(v_g, v_g+1, 2);
  v_ok := (v_hc = TIME '14:00');
  INSERT INTO _smoke_res VALUES (4,'override valido global (cab 2 checkin 14:00)','14:00:00', COALESCE(v_hc::text,'NULL'), v_ok);

  -- ===== Caso 5: override POR CABANA gana al global (cab1=15:00, cab2=14:00) =====
  SELECT hora_checkin_base INTO v_hc1 FROM obtener_disponibilidad_rango(v_g, v_g+1, 1);
  SELECT hora_checkin_base INTO v_hc2 FROM obtener_disponibilidad_rango(v_g, v_g+1, 2);
  v_ok := (v_hc1 = TIME '15:00' AND v_hc2 = TIME '14:00');
  INSERT INTO _smoke_res VALUES (5,'override por cabana gana al global','cab1=15:00 & cab2=14:00', format('cab1=%s cab2=%s', v_hc1, v_hc2), v_ok);

  -- ===== Caso 6: override CORRUPTO GLOBAL -> D1 (ambas horas NULL, cab 2) =====
  SELECT hora_checkin_base, hora_checkout_base INTO v_hc, v_ho FROM obtener_disponibilidad_rango(v_h, v_h+1, 2);
  v_ok := (v_hc IS NULL AND v_ho IS NULL);
  INSERT INTO _smoke_res VALUES (6,'override corrupto global -> D1 horas NULL (cab 2)','checkin=NULL & checkout=NULL', format('checkin=%s checkout=%s', COALESCE(v_hc::text,'NULL'), COALESCE(v_ho::text,'NULL')), v_ok);

  -- ===== Caso 7: override CORRUPTO POR CABANA -> D1, sin contaminar (cab1 NULL, cab2 base) =====
  SELECT hora_checkin_base, hora_checkout_base INTO v_hc1, v_ho1 FROM obtener_disponibilidad_rango(v_i, v_i+1, 1);
  SELECT hora_checkin_base, hora_checkout_base INTO v_hc2, v_ho2 FROM obtener_disponibilidad_rango(v_i, v_i+1, 2);
  v_ok := (v_hc1 IS NULL AND v_ho1 IS NULL AND v_hc2 IS NOT NULL AND v_ho2 IS NOT NULL);
  INSERT INTO _smoke_res VALUES (7,'override corrupto por cabana -> D1 sin contaminar','cab1 NULL/NULL & cab2 no-NULL', format('cab1=%s/%s cab2=%s/%s', COALESCE(v_hc1::text,'NULL'), COALESCE(v_ho1::text,'NULL'), v_hc2, v_ho2), v_ok);

  -- ===== Caso 8: modo A26 / cabana concreta (id=1, 7 noches -> 7 filas solo cab 1) =====
  SELECT count(*), count(DISTINCT id_cabana), min(id_cabana), max(id_cabana)
    INTO v_cnt, v_dist, v_min, v_max FROM obtener_disponibilidad_rango(fecha_hoy_ar(), fecha_hoy_ar()+7, 1);
  v_ok := (v_cnt = 7 AND v_dist = 1 AND v_min = 1 AND v_max = 1);
  INSERT INTO _smoke_res VALUES (8,'modo A26 / cabana concreta (id=1, 7 noches)','7 filas, solo cab 1', format('filas=%s distinct=%s', v_cnt, v_dist), v_ok);

  -- ===== Caso 9: modo NULL / todas activas (5 cabanas, inactiva excluida) =====
  SELECT count(DISTINCT id_cabana), bool_or(id_cabana = 6)
    INTO v_dist, v_inact FROM obtener_disponibilidad_rango(fecha_hoy_ar(), fecha_hoy_ar()+1, NULL);
  v_ok := (v_dist = 5 AND COALESCE(v_inact,false) = false);
  INSERT INTO _smoke_res VALUES (9,'modo NULL / todas activas (5 cabanas, inactiva excluida)','5 distinct, sin cab 6', format('distinct=%s incluye_inactiva=%s', v_dist, COALESCE(v_inact::text,'false')), v_ok);

  -- ===== Caso 10: performance rango real A26 (45 noches, 1 cabana) =====
  t0 := clock_timestamp();
  PERFORM count(*) FROM obtener_disponibilidad_rango(fecha_hoy_ar(), fecha_hoy_ar()+45, 1);
  t1 := clock_timestamp();
  v_ms := extract(epoch from (t1 - t0)) * 1000;
  INSERT INTO _smoke_res VALUES (10,'performance rango real A26 (45 noches, 1 cabana)','< 5000 ms', round(v_ms::numeric,1)::text||' ms', v_ms < 5000);

  -- ===== Caso 11: performance rango grande ~366 (365 noches, 1 cabana) =====
  t0 := clock_timestamp();
  PERFORM count(*) FROM obtener_disponibilidad_rango(fecha_hoy_ar(), fecha_hoy_ar()+365, 1);
  t1 := clock_timestamp();
  v_ms := extract(epoch from (t1 - t0)) * 1000;
  INSERT INTO _smoke_res VALUES (11,'performance rango grande (365 noches, 1 cabana)','< 30000 ms', round(v_ms::numeric,1)::text||' ms', v_ms < 30000);

  -- ===== TEARDOWN de datos (overrides + bloqueo marcados) =====
  DELETE FROM overrides_operativos WHERE motivo = '__SMOKE_HORARIOS__';
  DELETE FROM bloqueos WHERE source_event = '__SMOKE_HORARIOS__';
  SELECT count(*) INTO v_ovr FROM overrides_operativos WHERE motivo = '__SMOKE_HORARIOS__';
  SELECT count(*) INTO v_blq FROM bloqueos WHERE source_event = '__SMOKE_HORARIOS__';
  INSERT INTO _smoke_res VALUES (120,'TEARDOWN datos (overrides+bloqueo)','overrides=0 & bloqueos=0', format('overrides=%s bloqueos=%s', v_ovr, v_blq), (v_ovr = 0 AND v_blq = 0));
END
$smoke$;

-- ---------------------------------------------------------------------
-- TEARDOWN oracle (dentro de la tx) + POSTCHECK de cero residuos
-- ---------------------------------------------------------------------
DROP FUNCTION pg_temp._smoke_odr_vieja(date,date,bigint);

INSERT INTO _smoke_res
SELECT 130, 'POSTCHECK cero residuos', 'overrides=0 & bloqueos=0 & oracle DROP',
  format('ovr=%s blq=%s oracle=%s',
    (SELECT count(*) FROM overrides_operativos WHERE motivo = '__SMOKE_HORARIOS__'),
    (SELECT count(*) FROM bloqueos WHERE source_event = '__SMOKE_HORARIOS__'),
    CASE WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE p.proname='_smoke_odr_vieja' AND n.nspname LIKE 'pg_temp%') = 0
         THEN 'no-existe' ELSE 'EXISTE' END),
  ( (SELECT count(*) FROM overrides_operativos WHERE motivo = '__SMOKE_HORARIOS__') = 0
    AND (SELECT count(*) FROM bloqueos WHERE source_event = '__SMOKE_HORARIOS__') = 0
    AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE p.proname='_smoke_odr_vieja' AND n.nspname LIKE 'pg_temp%') = 0 );

-- Veredicto agregado como fila final
INSERT INTO _smoke_res
SELECT 999, 'VEREDICTO FINAL', 'todos verdes',
  CASE WHEN bool_and(pass) THEN 'TODOS VERDES' ELSE 'HAY FALLOS' END, bool_and(pass)
FROM _smoke_res;

COMMIT;  -- persiste SOLO la limpieza (fixture ya borrado) + las filas de _smoke_res

-- Resultado visible (ULTIMO statement). Pegar esta tabla.
SELECT * FROM _smoke_res ORDER BY orden;
