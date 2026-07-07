-- =====================================================================
-- B1.2-core - Motor de Horarios / Carril B1
-- Artefacto 3/4: SMOKE DE RUTAS REALES (como owner = produccion)
-- ---------------------------------------------------------------------
-- Confirma que el cableado fluye por las rutas reales, ejecutando como owner
-- (la vista es el limite de seguridad; en produccion se consulta como owner,
-- ver R0). Elige fechas LIBRES dinamicamente (dia habil, sin comprometido) para
-- no fallar por datos vivos, y usa vigencias de UN SOLO DIA. Tres tests:
--   A) vista_disponibilidad / ODR reflejan la vigencia en la fecha cubierta (14:00,
--      distinto de config 13:00) y config fuera de la vigencia.
--   B) crear_prereserva CONGELA la hora de la vigencia (14:00) en fecha cubierta
--      (usa resolver_horario(...)->>'hora_checkin' como base). Confirma que el
--      wrapper LANGUAGE sql no rompe la cadena/permisos/inlining al escribir.
--   C) INV-1: public._resolver_horario(cab, fecha_con_vigencia, false) -> config
--      (ciego), y el wrapper resolver_horario(...) -> vigencia. El interno ciego
--      es el unico punto llamado directo (prueba la no-autorreferencia del helper G1).
-- Si no hay fecha libre para algun test -> STOP claro (no error crudo).
--
-- DEJA TEST IDENTICO: cada test corre en subtransaccion que revierte (variables
-- plpgsql sobreviven; los INSERT al reporte se hacen fuera de la subtx).
-- META explicito que ABORTA si falla y se reporta unificado:
--   META-A: filas de vigencias/huespedes/pre_reservas/reservas/overrides sin cambios.
--   META-B: secuencias de vigencias/huespedes/pre_reservas restauradas (last_value + is_called).
-- ALCANCE: TEST-only. Requiere core aplicado + crear_prereserva (B3) presente.
-- Ejecutar en Supabase SQL Editor SIN texto seleccionado (script entero).
-- =====================================================================

-- ---- GATE (core aplicado; por ESTADO) ----
DO $gate$
DECLARE v_amb text; v_res text; v_odr text;
BEGIN
  SELECT valor INTO v_amb FROM public.configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE core-rutas: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'GATE core-rutas: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NULL THEN
    RAISE EXCEPTION 'GATE core-rutas: _resolver_horario no existe (core no aplicado). Abortando.';
  END IF;
  v_res := md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure));
  IF v_res = '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'GATE core-rutas: resolver sigue en R0 (core no aplicado). Abortando.';
  END IF;
  v_odr := md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE core-rutas: ODR fp=% (esperado 37009a32... intacto). Abortando.', v_odr;
  END IF;
  IF to_regprocedure('public.crear_prereserva(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'GATE core-rutas: crear_prereserva (B3) no existe. Abortando.';
  END IF;
END
$gate$;

SET client_min_messages = warning;

DROP TABLE IF EXISTS pg_temp._rutas_res;
BEGIN;
CREATE TEMP TABLE _rutas_res(orden INT, test TEXT, detalle TEXT, verdict TEXT) ON COMMIT DROP;

-- ---- Helpers efimeros (patron smoke B3) ----
CREATE FUNCTION pg_temp._cab() RETURNS bigint LANGUAGE sql AS $fn$
  SELECT id_cabana FROM public.cabanas WHERE activa ORDER BY id_cabana LIMIT 1;
$fn$;
CREATE FUNCTION pg_temp._mk(p_in date, p_out date) RETURNS jsonb LANGUAGE sql AS $fn$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'id_cabana',      pg_temp._cab(),
    'fecha_in',       to_char(p_in,  'YYYY-MM-DD'),
    'fecha_out',      to_char(p_out, 'YYYY-MM-DD'),
    'personas',       2,
    'canal_origen',   'manual',
    'canal_pago_esperado', 'efectivo',
    'source_event',   'smoke_core_rutas',
    'monto_total',    100000,
    'monto_sena',     30000,
    'huesped', jsonb_build_object('nombre', 'Smoke Core Rutas', 'telefono', '1100000000')
  ));
$fn$;

-- ---- Captura para META (secuencias last+is_called + counts) ----
DO $cap$
DECLARE v_sv TEXT := pg_get_serial_sequence('public.vigencias_horario_base','id_vigencia');
        v_sh TEXT := pg_get_serial_sequence('public.huespedes','id_huesped');
        v_sp TEXT := pg_get_serial_sequence('public.pre_reservas','id_pre_reserva');
        a BIGINT; ac BOOLEAN;
BEGIN
  EXECUTE format('SELECT last_value, is_called FROM %s', v_sv) INTO a, ac;
  INSERT INTO _rutas_res VALUES (0, '_seq_vig', v_sv||'|'||a||'|'||ac, '');
  EXECUTE format('SELECT last_value, is_called FROM %s', v_sh) INTO a, ac;
  INSERT INTO _rutas_res VALUES (0, '_seq_hue', v_sh||'|'||a||'|'||ac, '');
  EXECUTE format('SELECT last_value, is_called FROM %s', v_sp) INTO a, ac;
  INSERT INTO _rutas_res VALUES (0, '_seq_pre', v_sp||'|'||a||'|'||ac, '');
  INSERT INTO _rutas_res VALUES
    (0, '_cnt_vig', (SELECT count(*) FROM public.vigencias_horario_base)::text, ''),
    (0, '_cnt_hue', (SELECT count(*) FROM public.huespedes)::text, ''),
    (0, '_cnt_pre', (SELECT count(*) FROM public.pre_reservas)::text, ''),
    (0, '_cnt_res', (SELECT count(*) FROM public.reservas)::text, ''),
    (0, '_cnt_ovr', (SELECT count(*) FROM public.overrides_operativos)::text, '');
END
$cap$;

-- ========== Tests A + C (fecha habil LIBRE en la ventana; vigencia de 1 dia) ==========
DO $ac$
DECLARE
  v_cab bigint := pg_temp._cab();
  v_d date; v_out date;
  v_base time; v_rh time; v_ori text; v_ori_out text; v_ciego text; v_wrap text;
BEGIN
  -- fecha habil (DOW<>0) LIBRE dentro de la ventana de la vista (sin evento checkin/checkout)
  SELECT d::date INTO v_d
  FROM generate_series(CURRENT_DATE, CURRENT_DATE + (119 || ' days')::interval, interval '1 day') d
  WHERE EXTRACT(DOW FROM d) <> 0
    AND NOT EXISTS (SELECT 1 FROM public.reservas r WHERE r.estado IN ('confirmada','activa','completada') AND (r.fecha_checkin = d::date OR r.fecha_checkout = d::date))
    AND NOT EXISTS (SELECT 1 FROM public.pre_reservas pr WHERE ((pr.estado='pendiente_pago' AND pr.expira_en > NOW()) OR pr.estado='pago_en_revision') AND (pr.fecha_in = d::date OR pr.fecha_out = d::date))
  ORDER BY d LIMIT 1;
  IF v_d IS NULL THEN
    INSERT INTO _rutas_res VALUES (10, 'A/C (fecha libre habil)', 'STOP: no hay fecha habil libre en la ventana de vista_disponibilidad', 'STOP');
    RETURN;
  END IF;
  v_out := v_d + 1;   -- fuera de la vigencia de 1 dia [v_d, v_d]

  BEGIN
    INSERT INTO public.vigencias_horario_base(fecha_desde,fecha_hasta,abierta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por,activo)
      VALUES (v_d, v_d, FALSE, '14:00','19:00','11:00','17:00','smoke rutas 1 dia','smoke',TRUE);
    -- A: la vista refleja la vigencia (14:00, distinto de config 13:00) en v_d
    SELECT hora_checkin_base INTO v_base FROM public.vista_disponibilidad WHERE id_cabana = v_cab AND fecha = v_d;
    v_rh  := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    v_ori := (public.resolver_horario(v_cab, v_d)->>'origen_checkin');
    -- A2: fuera de la vigencia (v_out) => config
    v_ori_out := (public.resolver_horario(v_cab, v_out)->>'origen_checkin');
    -- C: INV-1 (interno ciego = config; wrapper = vigencia)
    v_ciego := (public._resolver_horario(v_cab, v_d, false)->>'origen_checkin');
    v_wrap  := (public.resolver_horario(v_cab, v_d)->>'origen_checkin');
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM !~ '__RB__' THEN RAISE; END IF;
  END;
  INSERT INTO _rutas_res VALUES (10, 'A vista refleja vigencia (fecha libre '||v_d||', 1 dia, 14:00 vs config 13:00)',
    'vista.hora_checkin_base='||COALESCE(v_base::text,'<null>')||' resolver.hora='||COALESCE(v_rh::text,'<null>')||' origen='||COALESCE(v_ori,'<null>'),
    CASE WHEN v_base = TIME '14:00' AND v_base = v_rh AND v_ori = 'vigencia' THEN 'PASS' ELSE 'FAIL' END);
  INSERT INTO _rutas_res VALUES (11, 'A fuera de vigencia ('||v_out||') usa config',
    'origen='||COALESCE(v_ori_out,'<null>'),
    CASE WHEN v_ori_out IN ('base','patron_domingo') THEN 'PASS' ELSE 'FAIL' END);
  INSERT INTO _rutas_res VALUES (12, 'C INV-1: interno(false)=config, wrapper=vigencia',
    'ciego='||COALESCE(v_ciego,'<null>')||' wrapper='||COALESCE(v_wrap,'<null>'),
    CASE WHEN v_ciego IN ('base','patron_domingo') AND v_wrap = 'vigencia' THEN 'PASS' ELSE 'FAIL' END);
END
$ac$;

-- ========== Test B (crear_prereserva congela vigencia; slot habil LIBRE 2 noches) ==========
DO $b$
DECLARE
  v_cab bigint := pg_temp._cab();
  v_d date; v_got jsonb;
BEGIN
  -- inicio habil (DOW<>0) con [v_d, v_d+2) LIBRE para la cabana (disponibilidad)
  SELECT d::date INTO v_d
  FROM generate_series(CURRENT_DATE + (200 || ' days')::interval, CURRENT_DATE + (320 || ' days')::interval, interval '1 day') d
  WHERE EXTRACT(DOW FROM d) <> 0
    AND NOT EXISTS (SELECT 1 FROM public.reservas r WHERE r.id_cabana = v_cab AND r.estado IN ('confirmada','activa','completada') AND daterange(r.fecha_checkin, r.fecha_checkout) && daterange(d::date, (d + interval '2 days')::date))
    AND NOT EXISTS (SELECT 1 FROM public.pre_reservas pr WHERE pr.id_cabana = v_cab AND ((pr.estado='pendiente_pago' AND pr.expira_en > NOW()) OR pr.estado='pago_en_revision') AND daterange(pr.fecha_in, pr.fecha_out) && daterange(d::date, (d + interval '2 days')::date))
  ORDER BY d LIMIT 1;
  IF v_d IS NULL THEN
    INSERT INTO _rutas_res VALUES (20, 'B crear_prereserva', 'STOP: no hay slot habil de 2 noches libre para la cabana en +200..+320d', 'STOP');
    RETURN;
  END IF;

  BEGIN
    -- vigencia de 1 dia cubriendo fecha_in con checkin DISTINTO de config (14:00 vs 13:00)
    INSERT INTO public.vigencias_horario_base(fecha_desde,fecha_hasta,abierta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por,activo)
      VALUES (v_d, v_d, FALSE, '14:00','19:00','11:00','17:00','smoke rutas B','smoke',TRUE);
    v_got := public.crear_prereserva(pg_temp._mk(v_d, v_d + 2));
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM !~ '__RB__' THEN RAISE; END IF;
  END;
  INSERT INTO _rutas_res VALUES (20, 'B crear_prereserva congela vigencia (checkin 14:00, no config 13:00) fecha '||v_d,
    'ok='||COALESCE((v_got->>'ok'),'<null>')||' hora_checkin='||COALESCE((v_got->>'hora_checkin'),'<null>')||' error='||COALESCE((v_got->>'error'),'-'),
    CASE WHEN (v_got->>'ok')::boolean AND (v_got->>'hora_checkin')::time = TIME '14:00' THEN 'PASS' ELSE 'FAIL' END);
END
$b$;

-- ---- RESTORE secuencias + META (aborta si falla) ----
DO $meta$
DECLARE v_seq TEXT; a BIGINT; ac BOOLEAN; v_chk_last BIGINT; v_chk_called BOOLEAN;
        v_metaA BOOLEAN := TRUE; v_metaB BOOLEAN := TRUE;
BEGIN
  -- restaurar + verificar secuencias (last_value E is_called)
  FOR v_seq, a, ac IN
    SELECT split_part(detalle,'|',1), split_part(detalle,'|',2)::bigint, split_part(detalle,'|',3)::boolean
    FROM _rutas_res WHERE orden = 0 AND test LIKE '\_seq\_%'
  LOOP
    PERFORM setval(v_seq::regclass, a, ac);
    EXECUTE format('SELECT last_value, is_called FROM %s', v_seq) INTO v_chk_last, v_chk_called;
    IF v_chk_last <> a OR v_chk_called <> ac THEN v_metaB := FALSE; END IF;
  END LOOP;
  -- META-A: filas sin cambios
  IF (SELECT count(*) FROM public.vigencias_horario_base) <> (SELECT detalle::bigint FROM _rutas_res WHERE orden=0 AND test='_cnt_vig') THEN v_metaA := FALSE; END IF;
  IF (SELECT count(*) FROM public.huespedes)              <> (SELECT detalle::bigint FROM _rutas_res WHERE orden=0 AND test='_cnt_hue') THEN v_metaA := FALSE; END IF;
  IF (SELECT count(*) FROM public.pre_reservas)           <> (SELECT detalle::bigint FROM _rutas_res WHERE orden=0 AND test='_cnt_pre') THEN v_metaA := FALSE; END IF;
  IF (SELECT count(*) FROM public.reservas)               <> (SELECT detalle::bigint FROM _rutas_res WHERE orden=0 AND test='_cnt_res') THEN v_metaA := FALSE; END IF;
  IF (SELECT count(*) FROM public.overrides_operativos)   <> (SELECT detalle::bigint FROM _rutas_res WHERE orden=0 AND test='_cnt_ovr') THEN v_metaA := FALSE; END IF;

  IF NOT (v_metaA AND v_metaB) THEN
    RAISE EXCEPTION 'RUTAS META FAIL: A_filas=% B_secuencias=%. TEST no quedo identico.', v_metaA, v_metaB;
  END IF;
  INSERT INTO _rutas_res VALUES
    (30, 'META-A_filas_sin_cambios',         'filas de vigencias/huespedes/pre_reservas/reservas/overrides == pre', 'OK'),
    (31, 'META-B_secuencias_last+is_called', 'vigencias/huespedes/pre_reservas restauradas (last_value + is_called)', 'OK');
END
$meta$;

-- ---- Reporte UNIFICADO (ULTIMO): tests + META (excluye filas de captura orden=0) ----
SELECT orden, test, detalle, verdict
FROM _rutas_res
WHERE orden > 0
ORDER BY orden;

COMMIT;

DROP TABLE IF EXISTS pg_temp._rutas_res;
