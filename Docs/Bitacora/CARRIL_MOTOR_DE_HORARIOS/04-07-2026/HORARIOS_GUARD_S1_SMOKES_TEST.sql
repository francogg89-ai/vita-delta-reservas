-- =====================================================================
-- HORARIOS_GUARD_S1_SMOKES_TEST.sql
-- Smokes de S1 (la barrera diferida). ALCANCE: SOLO TEST.
-- Todo en BEGIN..ROLLBACK. El trigger es DEFERRABLE INITIALLY DEFERRED: cada caso fuerza el
-- chequeo con SET CONSTRAINTS trg_ov_guard IMMEDIATE (nombre especifico, no ALL) dentro de una
-- subtransaccion BEGIN..EXCEPTION que ataja SQLSTATE '45000'. Compuerta ANTES del ROLLBACK;
-- el ultimo SELECT (post-ROLLBACK) escupe veredicto + residuales (=0).
--
-- Seeds: los eventos comprometidos (reservas) no disparan el trigger de overrides. Los overrides
-- PRE-EXISTENTES se siembran con el trigger DESHABILITADO (ALTER TABLE ... DISABLE TRIGGER) para
-- que no encolen eventos diferidos que contaminen los _try. Anclas de fecha distintas (400..530).
--
-- Casos (14):
--   1  INSERT co16 solo, cabana libre -> FALLA same-day
--   2  INSERT paquete co16+ci18 (multi-row), cabana libre -> PASA
--   3  INSERT global paquete, una cabana comprometida -> FALLA completo
--   4  UPDATE activo false->true sobre override que pisa comprometido -> FALLA
--   5  UPDATE activo true->false sobre override activo en comprometida -> FALLA
--   6  UPDATE metadata-only sobre override activo en comprometida -> PASA
--   7  DELETE override activo en comprometida -> FALLA
--   8  DELETE override inactivo sin efecto -> PASA
--   9  DELETE media mitad de paquete en libre (orphan) -> FALLA same-day
--   10 DELETE paquete completo en libre -> PASA
--   11a INSERT paquete fecha_hasta NULL, comprometido en fecha_desde+5 -> PASA (NULL solo fecha_desde)
--   11b INSERT paquete fecha_desde..fecha_desde+5, comprometido en fecha_desde+5 -> FALLA (rango cubre)
--   12 INSERT global paquete, _cab2() comprometido -> FALLA (expansion llega a _cab2())
--   13 INSERT cabana-especifico en _cab(), _cab2() comprometido -> PASA (no afecta _cab2())
--   14 UPDATE created_at para flip de ganador (2 overrides activos, gana por created_at) ->
--        el nuevo ganador da same-day invalido -> FALLA (created_at es EFECTIVA, no metadata)
--   15 UPDATE metadata-only REAL (motivo+creado_por+source_event) en comprometida -> PASA
-- Correr el script COMPLETO (L-8A-01).
-- =====================================================================

BEGIN;

-- ---- GATE ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM configuracion_general WHERE clave = 'ambiente');
  v_res text; v_odr text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN RAISE EXCEPTION 'SMOKE S1 abortado: ambiente=% (esperado test).', v_amb; END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN RAISE EXCEPTION 'SMOKE S1 abortado: schema=% (esperado public).', current_schema(); END IF;
  v_res := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN RAISE EXCEPTION 'SMOKE S1 abortado: resolver=% (esperado 58d75c1b).', v_res; END IF;
  v_odr := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN RAISE EXCEPTION 'SMOKE S1 abortado: ODR=% (esperado 37009a32).', v_odr; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                 WHERE c.relname='overrides_operativos' AND t.tgname='trg_ov_guard' AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION 'SMOKE S1 abortado: falta el constraint trigger trg_ov_guard. Corre HORARIOS_GUARD_S1_TRIGGER_TEST.sql primero.';
  END IF;
  RAISE NOTICE 'SMOKE S1 GATE OK.';
END
$gate$;

-- ---- Helpers efimeros ----
CREATE OR REPLACE FUNCTION _nextmon(off int) RETURNS date LANGUAGE sql AS $fn$
  SELECT d + ((8 - EXTRACT(DOW FROM d)::int) % 7) FROM (SELECT fecha_hoy_ar() + off AS d) x;
$fn$;
CREATE OR REPLACE FUNCTION _cab()  RETURNS bigint LANGUAGE sql AS $fn$ SELECT id_cabana FROM cabanas WHERE activa ORDER BY id_cabana LIMIT 1; $fn$;
CREATE OR REPLACE FUNCTION _cab2() RETURNS bigint LANGUAGE sql AS $fn$ SELECT id_cabana FROM cabanas WHERE activa ORDER BY id_cabana OFFSET 1 LIMIT 1; $fn$;

INSERT INTO huespedes(nombre, telefono) VALUES ('Smoke S1', '1190000001');
CREATE OR REPLACE FUNCTION _hsp() RETURNS bigint LANGUAGE sql AS $fn$ SELECT id_huesped FROM huespedes WHERE nombre='Smoke S1' ORDER BY id_huesped DESC LIMIT 1; $fn$;

CREATE OR REPLACE FUNCTION _mkovr(p_tipo text, p_valor text, p_cab bigint, p_desde date, p_hasta date, p_activo boolean) RETURNS void
LANGUAGE sql AS $fn$
  INSERT INTO overrides_operativos(tipo_override, valor, id_cabana, fecha_desde, fecha_hasta, motivo, creado_por, source_event, activo)
  VALUES (p_tipo, p_valor, p_cab, p_desde, p_hasta, 'smoke s1', 'smoke', 'smoke_s1', p_activo);
$fn$;
CREATE OR REPLACE FUNCTION _mkres(p_cab bigint, p_ci date, p_co date, p_hci time, p_hco time) RETURNS void
LANGUAGE sql AS $fn$
  INSERT INTO reservas(id_cabana, id_huesped, fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
                       personas, estado, canal_origen, monto_total, monto_sena, monto_saldo, source_event)
  VALUES (p_cab, _hsp(), p_ci, p_co, p_hci, p_hco, 2, 'confirmada', 'manual', 100000, 30000, 70000, 'smoke_s1');
$fn$;

-- _try: subtransaccion; fuerza el diferido con SET CONSTRAINTS trg_ov_guard IMMEDIATE; ataja 45000.
CREATE OR REPLACE FUNCTION _try(p_orden text, p_test text, p_esperado text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE v text;
BEGIN
  BEGIN
    SET CONSTRAINTS trg_ov_guard DEFERRED;   -- resetear diferido (por si quedo IMMEDIATE de un caso previo)
    EXECUTE p_sql;
    SET CONSTRAINTS trg_ov_guard IMMEDIATE;  -- dispara el trigger diferido AHORA
    v := 'PASA';
  EXCEPTION
    WHEN SQLSTATE '45000' THEN v := 'FALLA';
  END;
  INSERT INTO _res(orden, test, esperado, got, verdict)
  VALUES (p_orden, p_test, p_esperado, v, CASE WHEN p_esperado = v THEN 'PASS' ELSE 'FAIL' END);
END $fn$;

CREATE TEMP TABLE _res (orden text, test text, esperado text, got text, verdict text) ON COMMIT DROP;

-- ===================== SEEDS PERSISTENTES =====================
-- eventos comprometidos (no disparan el trigger de overrides)
SELECT _mkres(_cab(),  _nextmon(420),   _nextmon(420)+2, '13:00','10:00');  -- caso 3
SELECT _mkres(_cab(),  _nextmon(430),   _nextmon(430)+2, '13:00','10:00');  -- caso 4
SELECT _mkres(_cab(),  _nextmon(440),   _nextmon(440)+2, '13:00','10:00');  -- caso 5
SELECT _mkres(_cab(),  _nextmon(450),   _nextmon(450)+2, '13:00','10:00');  -- caso 6
SELECT _mkres(_cab(),  _nextmon(460),   _nextmon(460)+2, '13:00','10:00');  -- caso 7
SELECT _mkres(_cab(),  _nextmon(500)+5, _nextmon(500)+7, '13:00','10:00');  -- caso 11a (comprometido en fecha_desde+5)
SELECT _mkres(_cab(),  _nextmon(510)+5, _nextmon(510)+7, '13:00','10:00');  -- caso 11b (comprometido en fecha_desde+5)
SELECT _mkres(_cab2(), _nextmon(520),   _nextmon(520)+2, '13:00','10:00');  -- caso 12 (en _cab2())
SELECT _mkres(_cab2(), _nextmon(530),   _nextmon(530)+2, '13:00','10:00');  -- caso 13 (en _cab2())
SELECT _mkres(_cab(),  _nextmon(550),   _nextmon(550)+2, '13:00','10:00');  -- caso 15 (comprometida, para metadata-only real)

-- overrides pre-existentes con TRIGGER DESHABILITADO (no encolan eventos diferidos)
ALTER TABLE overrides_operativos DISABLE TRIGGER trg_ov_guard;
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(430), _nextmon(430), false);  -- 4: inactivo, comprometida
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(440), _nextmon(440), true);   -- 5: activo, comprometida
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(450), _nextmon(450), true);   -- 6: activo, comprometida
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(460), _nextmon(460), true);   -- 7: activo, comprometida
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(470), _nextmon(470), false);  -- 8: inactivo, libre
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(480), _nextmon(480), true);   -- 9: paquete co, libre
SELECT _mkovr('hora_checkin', '18:00', _cab(), _nextmon(480), _nextmon(480), true);   -- 9: paquete ci, libre
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(490), _nextmon(490), true);   -- 10: paquete co, libre
SELECT _mkovr('hora_checkin', '18:00', _cab(), _nextmon(490), _nextmon(490), true);   -- 10: paquete ci, libre
-- 14: dos overrides hora_checkout mismos cabana/fecha (540, libre). A(10:00) gana por created_at (valido); B(16:00) pierde.
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo,created_at)
VALUES ('hora_checkout','10:00', _cab(), _nextmon(540), _nextmon(540), 'A gana smoke','smoke','smoke_s1', true, NOW());               -- mas nuevo -> gana
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo,created_at)
VALUES ('hora_checkout','16:00', _cab(), _nextmon(540), _nextmon(540), 'B pierde smoke','smoke','smoke_s1', true, NOW() - interval '1 day'); -- mas viejo -> pierde
-- 15: override activo en comprometida (550) para el UPDATE metadata-only real
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(550), _nextmon(550), true);
ALTER TABLE overrides_operativos ENABLE TRIGGER trg_ov_guard;

-- ===================== CASOS =====================
-- 1: INSERT co16 solo, cabana libre -> FALLA same-day
SELECT _try('1', 'INSERT co16 solo cabana libre -> FALLA same-day', 'FALLA',
  $q$ INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo)
      VALUES ('hora_checkout','16:00', _cab(), _nextmon(400), _nextmon(400), 'smoke s1','smoke','smoke_s1', true) $q$);

-- 2: INSERT paquete co16+ci18 (multi-row), cabana libre -> PASA
SELECT _try('2', 'INSERT paquete co16+ci18 cabana libre -> PASA', 'PASA',
  $q$ INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo)
      VALUES ('hora_checkout','16:00', _cab(), _nextmon(410), _nextmon(410), 'smoke s1','smoke','smoke_s1', true),
             ('hora_checkin', '18:00', _cab(), _nextmon(410), _nextmon(410), 'smoke s1','smoke','smoke_s1', true) $q$);

-- 3: INSERT global paquete, _cab() comprometido -> FALLA completo
SELECT _try('3', 'INSERT global paquete con cabana comprometida -> FALLA completo', 'FALLA',
  $q$ INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo)
      VALUES ('hora_checkout','16:00', NULL, _nextmon(420), _nextmon(420), 'smoke s1','smoke','smoke_s1', true),
             ('hora_checkin', '18:00', NULL, _nextmon(420), _nextmon(420), 'smoke s1','smoke','smoke_s1', true) $q$);

-- 4: UPDATE activo false->true sobre override que pisa comprometido -> FALLA
SELECT _try('4', 'UPDATE activo false->true pisa comprometido -> FALLA', 'FALLA',
  $q$ UPDATE overrides_operativos SET activo=true
      WHERE id_cabana=_cab() AND fecha_desde=_nextmon(430) AND source_event='smoke_s1' $q$);

-- 5: UPDATE activo true->false sobre override activo en comprometida -> FALLA
SELECT _try('5', 'UPDATE activo true->false en comprometida -> FALLA', 'FALLA',
  $q$ UPDATE overrides_operativos SET activo=false
      WHERE id_cabana=_cab() AND fecha_desde=_nextmon(440) AND source_event='smoke_s1' $q$);

-- 6: UPDATE metadata-only sobre override activo en comprometida -> PASA
SELECT _try('6', 'UPDATE metadata-only (motivo) en comprometida -> PASA', 'PASA',
  $q$ UPDATE overrides_operativos SET motivo='editado smoke'
      WHERE id_cabana=_cab() AND fecha_desde=_nextmon(450) AND source_event='smoke_s1' $q$);

-- 7: DELETE override activo en comprometida -> FALLA
SELECT _try('7', 'DELETE override activo en comprometida -> FALLA', 'FALLA',
  $q$ DELETE FROM overrides_operativos
      WHERE id_cabana=_cab() AND fecha_desde=_nextmon(460) AND source_event='smoke_s1' $q$);

-- 8: DELETE override inactivo sin efecto -> PASA
SELECT _try('8', 'DELETE override inactivo sin efecto -> PASA', 'PASA',
  $q$ DELETE FROM overrides_operativos
      WHERE id_cabana=_cab() AND fecha_desde=_nextmon(470) AND source_event='smoke_s1' $q$);

-- 9: DELETE media mitad de paquete en libre (orphan) -> FALLA same-day
SELECT _try('9', 'DELETE media mitad de paquete (orphan) -> FALLA same-day', 'FALLA',
  $q$ DELETE FROM overrides_operativos
      WHERE id_cabana=_cab() AND fecha_desde=_nextmon(480) AND tipo_override='hora_checkin' AND source_event='smoke_s1' $q$);

-- 10: DELETE paquete completo en libre -> PASA
SELECT _try('10', 'DELETE paquete completo en libre -> PASA', 'PASA',
  $q$ DELETE FROM overrides_operativos
      WHERE id_cabana=_cab() AND fecha_desde=_nextmon(490) AND source_event='smoke_s1' $q$);

-- 11a: INSERT paquete fecha_hasta NULL, comprometido en fecha_desde+5 -> PASA
SELECT _try('11a', 'INSERT paquete fecha_hasta NULL, comprometido en +5 -> PASA (solo fecha_desde)', 'PASA',
  $q$ INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo)
      VALUES ('hora_checkout','16:00', _cab(), _nextmon(500), NULL, 'smoke s1','smoke','smoke_s1', true),
             ('hora_checkin', '18:00', _cab(), _nextmon(500), NULL, 'smoke s1','smoke','smoke_s1', true) $q$);

-- 11b: INSERT paquete fecha_desde..fecha_desde+5, comprometido en fecha_desde+5 -> FALLA
SELECT _try('11b', 'INSERT paquete rango fecha_desde..+5, comprometido en +5 -> FALLA (rango cubre)', 'FALLA',
  $q$ INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo)
      VALUES ('hora_checkout','16:00', _cab(), _nextmon(510), _nextmon(510)+5, 'smoke s1','smoke','smoke_s1', true),
             ('hora_checkin', '18:00', _cab(), _nextmon(510), _nextmon(510)+5, 'smoke s1','smoke','smoke_s1', true) $q$);

-- 12: INSERT global paquete, _cab2() comprometido -> FALLA (expansion a _cab2())
SELECT _try('12', 'INSERT global, _cab2() comprometido -> FALLA (expansion global)', 'FALLA',
  $q$ INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo)
      VALUES ('hora_checkout','16:00', NULL, _nextmon(520), _nextmon(520), 'smoke s1','smoke','smoke_s1', true),
             ('hora_checkin', '18:00', NULL, _nextmon(520), _nextmon(520), 'smoke s1','smoke','smoke_s1', true) $q$);

-- 13: INSERT cabana-especifico en _cab(), _cab2() comprometido -> PASA (no afecta _cab2())
SELECT _try('13', 'INSERT cabana-especifico _cab(), _cab2() comprometido -> PASA (cabana-especificidad)', 'PASA',
  $q$ INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo)
      VALUES ('hora_checkout','16:00', _cab(), _nextmon(530), _nextmon(530), 'smoke s1','smoke','smoke_s1', true),
             ('hora_checkin', '18:00', _cab(), _nextmon(530), _nextmon(530), 'smoke s1','smoke','smoke_s1', true) $q$);

-- 14: UPDATE created_at del perdedor (B,16:00) para hacerlo ganar -> checkout efectivo 16:00 -> same-day invalido.
--     created_at es EFECTIVA (desempate del resolver); el trigger NO debe saltearlo -> FALLA.
SELECT _try('14', 'UPDATE created_at flip de ganador -> FALLA same-day (created_at efectiva, no metadata)', 'FALLA',
  $q$ UPDATE overrides_operativos SET created_at = now() + interval '1 day'
      WHERE id_cabana=_cab() AND fecha_desde=_nextmon(540) AND valor='16:00' AND source_event='smoke_s1' $q$);

-- 15: UPDATE metadata-only REAL (motivo+creado_por+source_event) en comprometida -> PASA (siguen siendo inertes)
SELECT _try('15', 'UPDATE metadata-only real (motivo+creado_por+source_event) en comprometida -> PASA', 'PASA',
  $q$ UPDATE overrides_operativos SET motivo='m2', creado_por='c2', source_event='smoke_s1_meta'
      WHERE id_cabana=_cab() AND fecha_desde=_nextmon(550) AND source_event='smoke_s1' $q$);

-- ===================== COMPUERTA (antes del ROLLBACK) =====================
DO $assert$
DECLARE v_pass int; v_fail int; v_total int; v_fails text;
BEGIN
  SELECT count(*) FILTER (WHERE verdict='PASS'), count(*) FILTER (WHERE verdict='FAIL'), count(*)
    INTO v_pass, v_fail, v_total FROM _res;
  SELECT string_agg(format('#%s [%s] esperado=%s got=%s', orden, test, esperado, got), ' || ' ORDER BY orden)
    INTO v_fails FROM _res WHERE verdict <> 'PASS';
  IF v_fail > 0 OR v_total <> 16 THEN
    RAISE EXCEPTION 'SMOKE S1 FALLA: pass=% (esp 16) fail=% (esp 0) total=% (esp 16). No-PASS: %',
      v_pass, v_fail, v_total, COALESCE(v_fails, '(ninguno; revisar conteo)');
  END IF;
  RAISE NOTICE 'SMOKE S1 OK: 16/16 PASS, 0 FAIL. (la tx se revierte a continuacion)';
END
$assert$;

ROLLBACK;

-- ---- VEREDICTO + POSTCHECK (unico SELECT visible, tras el ROLLBACK) ----
SELECT
  'SMOKE S1 VALIDADO: compuerta 16/16 PASS, 0 FAIL; el trigger diferido disparo con SET CONSTRAINTS trg_ov_guard IMMEDIATE; created_at tratada como columna efectiva; seeds revertidos.' AS veredicto,
  (SELECT count(*) FROM overrides_operativos WHERE source_event LIKE 'smoke_s1%') AS overrides_residual,
  (SELECT count(*) FROM reservas            WHERE source_event='smoke_s1') AS reservas_residual,
  (SELECT count(*) FROM pre_reservas        WHERE source_event='smoke_s1') AS prereservas_residual,
  (SELECT count(*) FROM huespedes           WHERE nombre='Smoke S1')       AS huespedes_residual;
