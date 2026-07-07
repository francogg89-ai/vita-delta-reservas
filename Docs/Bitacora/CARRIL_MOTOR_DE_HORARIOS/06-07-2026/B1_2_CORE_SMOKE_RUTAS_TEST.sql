-- =====================================================================
-- B1.2-core - Motor de Horarios / Carril B1
-- Artefacto 3/4: SMOKE DE RUTAS REALES (como owner = produccion)
-- ---------------------------------------------------------------------
-- Confirma que el cableado fluye por las rutas reales, ejecutando como
-- owner (la vista es el limite de seguridad; en produccion se consulta
-- como owner, ver R0). Tres tests:
--   A) vista_disponibilidad / ODR reflejan la vigencia en fecha cubierta,
--      y config fuera de vigencia (via origen del resolver).
--   B) crear_prereserva CONGELA la hora de la vigencia en fecha cubierta
--      (usa resolver_horario(...)->>'hora_checkin' como base). Confirma que
--      el wrapper LANGUAGE sql no rompe la cadena/permisos/inlining en el
--      camino de escritura.
--   C) INV-1: public._resolver_horario(cab, fecha_con_vigencia, false) -> config
--      (ciego), mientras el wrapper resolver_horario(cab, fecha_con_vigencia)
--      -> vigencia. El interno ciego es el unico punto llamado directo
--      (justificado: prueba la no-autorreferencia del helper G1).
--
-- DEJA TEST IDENTICO: cada test corre en una subtransaccion que revierte
-- (las variables plpgsql sobreviven al rollback; los INSERT al reporte se
-- hacen DESPUES, fuera de la subtx). Secuencias de vigencias/huespedes/
-- pre_reservas restauradas con setval.
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
CREATE FUNCTION pg_temp._nextmon(off INT) RETURNS date LANGUAGE sql AS $fn$
  SELECT d + ((8 - EXTRACT(DOW FROM d)::int) % 7) FROM (SELECT CURRENT_DATE + off AS d) x;
$fn$;
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

-- ---- Captura de secuencias (para restaurar al final) ----
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
END
$cap$;

-- ========== Tests A + C (vigencia efimera en subtx; captura en variables) ==========
DO $ac$
DECLARE
  v_cab bigint := pg_temp._cab();
  v_d   date   := pg_temp._nextmon(1);   -- proximo lunes (habil), dentro de +13
  v_base time; v_rh time; v_ori text; v_ori30 text; v_ciego text; v_wrap text;
BEGIN
  BEGIN
    INSERT INTO public.vigencias_horario_base(fecha_desde,fecha_hasta,abierta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por,activo)
      VALUES (CURRENT_DATE, CURRENT_DATE+13, FALSE, '14:00','19:00','11:00','17:00','smoke rutas','smoke',TRUE);
    -- A: la vista refleja la vigencia (habil cubierta)
    SELECT hora_checkin_base INTO v_base FROM public.vista_disponibilidad WHERE id_cabana = v_cab AND fecha = v_d;
    v_rh  := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    v_ori := (public.resolver_horario(v_cab, v_d)->>'origen_checkin');
    -- A2: fuera de vigencia (hoy+30) => config
    v_ori30 := (public.resolver_horario(v_cab, CURRENT_DATE+30)->>'origen_checkin');
    -- C: INV-1 (interno ciego = config; wrapper = vigencia)
    v_ciego := (public._resolver_horario(v_cab, v_d, false)->>'origen_checkin');
    v_wrap  := (public.resolver_horario(v_cab, v_d)->>'origen_checkin');
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM !~ '__RB__' THEN RAISE; END IF;
  END;
  INSERT INTO _rutas_res VALUES (10, 'A vista_disponibilidad refleja vigencia (fecha habil cubierta)',
    'vista.hora_checkin_base='||COALESCE(v_base::text,'<null>')||' resolver.hora='||COALESCE(v_rh::text,'<null>')||' origen='||COALESCE(v_ori,'<null>'),
    CASE WHEN v_base = TIME '14:00' AND v_base = v_rh AND v_ori = 'vigencia' THEN 'PASS' ELSE 'FAIL' END);
  INSERT INTO _rutas_res VALUES (11, 'A vista/ODR usa config fuera de vigencia (hoy+30)',
    'origen='||COALESCE(v_ori30,'<null>'),
    CASE WHEN v_ori30 IN ('base','patron_domingo') THEN 'PASS' ELSE 'FAIL' END);
  INSERT INTO _rutas_res VALUES (12, 'C INV-1: interno(false)=config, wrapper=vigencia (fecha cubierta)',
    'ciego='||COALESCE(v_ciego,'<null>')||' wrapper='||COALESCE(v_wrap,'<null>'),
    CASE WHEN v_ciego IN ('base','patron_domingo') AND v_wrap = 'vigencia' THEN 'PASS' ELSE 'FAIL' END);
END
$ac$;

-- ========== Test B (crear_prereserva congela vigencia; en subtx) ==========
DO $b$
DECLARE v_got jsonb;
BEGIN
  BEGIN
    INSERT INTO public.vigencias_horario_base(fecha_desde,fecha_hasta,abierta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por,activo)
      VALUES (pg_temp._nextmon(300), pg_temp._nextmon(300)+3, FALSE, '14:00','19:00','11:00','17:00','smoke rutas B','smoke',TRUE);
    v_got := public.crear_prereserva(pg_temp._mk(pg_temp._nextmon(300), pg_temp._nextmon(300)+2));
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM !~ '__RB__' THEN RAISE; END IF;
  END;
  INSERT INTO _rutas_res VALUES (20, 'B crear_prereserva congela hora de vigencia (14:00, no config 13:00)',
    'ok='||COALESCE((v_got->>'ok'),'<null>')||' hora_checkin='||COALESCE((v_got->>'hora_checkin'),'<null>')||' error='||COALESCE((v_got->>'error'),'-'),
    CASE WHEN (v_got->>'ok')::boolean AND (v_got->>'hora_checkin')::time = TIME '14:00' THEN 'PASS' ELSE 'FAIL' END);
END
$b$;

-- ---- RESTORE secuencias (los inserts revertidos avanzaron nextval) ----
DO $rest$
DECLARE v_seq TEXT; a BIGINT; ac BOOLEAN;
BEGIN
  FOR v_seq, a, ac IN
    SELECT split_part(detalle,'|',1), split_part(detalle,'|',2)::bigint, split_part(detalle,'|',3)::boolean
    FROM _rutas_res WHERE orden = 0
  LOOP
    PERFORM setval(v_seq::regclass, a, ac);
  END LOOP;
END
$rest$;

-- ---- Reporte (ULTIMO): resultados de tests (excluye filas _seq) ----
SELECT orden, test, detalle, verdict
FROM _rutas_res
WHERE orden > 0
ORDER BY orden;

COMMIT;

DROP TABLE IF EXISTS pg_temp._rutas_res;
