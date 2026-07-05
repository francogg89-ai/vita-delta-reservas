-- =====================================================================
-- HORARIOS_GUARD_S2_SMOKES_TEST.sql
-- Smokes de S2 (crear_override_horario). ALCANCE: SOLO TEST. Todo en BEGIN..ROLLBACK.
--
-- Patron de DOS FASES (importante): la funcion inserta dentro de su propia subtransaccion, y esa
-- fila NO es visible para un EXISTS del MISMO statement (snapshot del statement). Por eso:
--   FASE 1: cada caso llama la funcion UNA vez en su propio statement -> guarda el jsonb en _raw.
--   FASE 2: un statement separado computa el verdict (ve las filas ya insertadas por la fase 1).
-- Los ok:false chequean que NO quedo fila; los ok:true, que la fila existe.
-- Compuerta ANTES del ROLLBACK; ultimo SELECT (post-ROLLBACK) da veredicto + residuales (=0).
-- Anclas de fecha espaciadas de a 10 (evita colision por redondeo a lunes de _nextmon).
-- Correr el script COMPLETO (L-8A-01).
--
-- Casos (12):
--   1  alta valida cabana hora_checkin libre -> ok:true e inserta
--   2  alta valida global estricto libre -> ok:true e inserta global
--   3  same-day invalido (co16 solo) -> ok:false override_incompatible_same_day y NO inserta
--   4  reserva comprometida -> ok:false override_pisa_reserva y NO inserta
--   5  pre-reserva vigente -> ok:false override_pisa_prereserva y NO inserta
--   6  tipo no soportado -> ok:false tipo_override_no_soportado
--   7a fecha_desde invalida -> ok:false payload_invalido
--   7b fecha_hasta < fecha_desde -> ok:false payload_invalido
--   8  id_cabana inexistente -> ok:false cabana_no_encontrada
--   9  fecha_hasta NULL solo afecta fecha_desde (comprometido en +5 no bloquea) -> ok:true
--   10 activo=false -> ok:true inactivo, sin incompatibilidad, e inserta inactivo
--   11 trigger S1 sigue activo: INSERT directo invalido (fuera de la funcion) -> FALLA
-- =====================================================================

BEGIN;

-- ---- GATE ----
DO $gate$
DECLARE v_amb text := (SELECT valor FROM configuracion_general WHERE clave='ambiente'); v_res text; v_odr text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN RAISE EXCEPTION 'SMOKE S2 abortado: ambiente=% (esperado test).', v_amb; END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN RAISE EXCEPTION 'SMOKE S2 abortado: schema=%.', current_schema(); END IF;
  v_res := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN RAISE EXCEPTION 'SMOKE S2 abortado: resolver=%.', v_res; END IF;
  v_odr := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN RAISE EXCEPTION 'SMOKE S2 abortado: ODR=%.', v_odr; END IF;
  IF to_regprocedure('public.crear_override_horario(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'SMOKE S2 abortado: falta crear_override_horario. Corre HORARIOS_GUARD_S2_FUNCION_TEST.sql primero.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                 WHERE c.relname='overrides_operativos' AND t.tgname='trg_ov_guard' AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION 'SMOKE S2 abortado: falta el constraint trigger trg_ov_guard (S1).';
  END IF;
  RAISE NOTICE 'SMOKE S2 GATE OK.';
END
$gate$;

-- ---- Helpers efimeros ----
CREATE OR REPLACE FUNCTION _nextmon(off int) RETURNS date LANGUAGE sql AS $fn$
  SELECT d + ((8 - EXTRACT(DOW FROM d)::int) % 7) FROM (SELECT fecha_hoy_ar() + off AS d) x;
$fn$;
CREATE OR REPLACE FUNCTION _cab()  RETURNS bigint LANGUAGE sql AS $fn$ SELECT id_cabana FROM cabanas WHERE activa ORDER BY id_cabana LIMIT 1; $fn$;

INSERT INTO huespedes(nombre, telefono) VALUES ('Smoke S2', '1190000002');
CREATE OR REPLACE FUNCTION _hsp() RETURNS bigint LANGUAGE sql AS $fn$ SELECT id_huesped FROM huespedes WHERE nombre='Smoke S2' ORDER BY id_huesped DESC LIMIT 1; $fn$;

CREATE OR REPLACE FUNCTION _mkres(p_cab bigint, p_ci date, p_co date) RETURNS void LANGUAGE sql AS $fn$
  INSERT INTO reservas(id_cabana, id_huesped, fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
                       personas, estado, canal_origen, monto_total, monto_sena, monto_saldo, source_event)
  VALUES (p_cab, _hsp(), p_ci, p_co, '13:00','10:00', 2, 'confirmada', 'manual', 100000, 30000, 70000, 'smoke_s2');
$fn$;
CREATE OR REPLACE FUNCTION _mkpre(p_cab bigint, p_in date, p_out date) RETURNS void LANGUAGE sql AS $fn$
  INSERT INTO pre_reservas(id_cabana, id_huesped, fecha_in, fecha_out, hora_checkin, hora_checkout,
                           personas, monto_total, monto_sena, estado, expira_en, canal_pago_esperado, canal_origen, source_event)
  VALUES (p_cab, _hsp(), p_in, p_out, '13:00','10:00', 2, 100000, 30000, 'pendiente_pago', NOW() + interval '1 day', 'efectivo', 'manual', 'smoke_s2');
$fn$;

CREATE TEMP TABLE _raw (orden text, test text, got jsonb, anchor date, expect_ok boolean, expect_err text, row_check text) ON COMMIT DROP;
CREATE TEMP TABLE _res (orden text, test text, got text, verdict text) ON COMMIT DROP;

-- ---- Seeds de eventos comprometidos (no disparan el trigger de overrides) ----
SELECT _mkres(_cab(), _nextmon(570),   _nextmon(570)+2);  -- caso 4
SELECT _mkpre(_cab(), _nextmon(580),   _nextmon(580)+2);  -- caso 5
SELECT _mkres(_cab(), _nextmon(620)+5, _nextmon(620)+7);  -- caso 9 (comprometido en fecha_desde+5)

-- ===================== 11 (primero, para aislar su SET CONSTRAINTS IMMEDIATE) =====================
DO $c11$
DECLARE v_verd text;
BEGIN
  BEGIN
    SET CONSTRAINTS trg_ov_guard DEFERRED;
    INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo)
    VALUES ('hora_checkout','16:00', _cab(), _nextmon(640), _nextmon(640), 'smoke s2','smoke','smoke_s2', true);
    SET CONSTRAINTS trg_ov_guard IMMEDIATE;   -- fuerza el trigger diferido
    v_verd := 'PASA';                          -- si no fallo, el trigger NO actuo => mal
  EXCEPTION WHEN SQLSTATE '45000' THEN
    v_verd := 'FALLA';                         -- el trigger actuo => bien
  END;
  INSERT INTO _res VALUES ('11', 'trigger S1 sigue activo: INSERT directo invalido (co16 solo) -> FALLA', v_verd,
    CASE WHEN v_verd='FALLA' THEN 'PASS' ELSE 'FAIL' END);
END
$c11$;
SET CONSTRAINTS trg_ov_guard DEFERRED;   -- reset explicito para las llamadas a la funcion

-- ===================== FASE 1: una llamada por caso (statement propio) -> _raw =====================
INSERT INTO _raw VALUES ('1', 'alta valida cabana hora_checkin libre -> ok:true e inserta',
  crear_override_horario(jsonb_build_object('fecha_desde',_nextmon(540)::text,'id_cabana',_cab(),
    'tipo_override','hora_checkin','valor','15:00','motivo','m','creado_por','c','source_event','smoke_s2')),
  NULL, true, NULL, 'exists_id');

INSERT INTO _raw VALUES ('2', 'alta valida global estricto libre -> ok:true e inserta global',
  crear_override_horario(jsonb_build_object('fecha_desde',_nextmon(550)::text,
    'tipo_override','hora_checkin','valor','15:00','motivo','m','creado_por','c','source_event','smoke_s2')),
  NULL, true, NULL, 'exists_id_global');

INSERT INTO _raw VALUES ('3', 'same-day invalido (co16 solo) -> ok:false override_incompatible_same_day y NO inserta',
  crear_override_horario(jsonb_build_object('fecha_desde',_nextmon(560)::text,'id_cabana',_cab(),
    'tipo_override','hora_checkout','valor','16:00','motivo','m','creado_por','c','source_event','smoke_s2')),
  _nextmon(560), false, 'override_incompatible_same_day', 'not_exists_anchor');

INSERT INTO _raw VALUES ('4', 'reserva comprometida -> ok:false override_pisa_reserva y NO inserta',
  crear_override_horario(jsonb_build_object('fecha_desde',_nextmon(570)::text,'id_cabana',_cab(),
    'tipo_override','hora_checkin','valor','15:00','motivo','m','creado_por','c','source_event','smoke_s2')),
  _nextmon(570), false, 'override_pisa_reserva', 'not_exists_anchor');

INSERT INTO _raw VALUES ('5', 'pre-reserva vigente -> ok:false override_pisa_prereserva y NO inserta',
  crear_override_horario(jsonb_build_object('fecha_desde',_nextmon(580)::text,'id_cabana',_cab(),
    'tipo_override','hora_checkin','valor','15:00','motivo','m','creado_por','c','source_event','smoke_s2')),
  _nextmon(580), false, 'override_pisa_prereserva', 'not_exists_anchor');

INSERT INTO _raw VALUES ('6', 'tipo no soportado (minimo_noches) -> ok:false tipo_override_no_soportado',
  crear_override_horario(jsonb_build_object('fecha_desde',_nextmon(590)::text,'id_cabana',_cab(),
    'tipo_override','minimo_noches','valor','2','motivo','m','creado_por','c','source_event','smoke_s2')),
  NULL, false, 'tipo_override_no_soportado', 'none');

INSERT INTO _raw VALUES ('7a', 'fecha_desde invalida -> ok:false payload_invalido',
  crear_override_horario(jsonb_build_object('fecha_desde','no-es-fecha','id_cabana',_cab(),
    'tipo_override','hora_checkin','valor','15:00','motivo','m','creado_por','c','source_event','smoke_s2')),
  NULL, false, 'payload_invalido', 'none');

INSERT INTO _raw VALUES ('7b', 'fecha_hasta < fecha_desde -> ok:false payload_invalido',
  crear_override_horario(jsonb_build_object('fecha_desde',_nextmon(600)::text,'fecha_hasta',(_nextmon(600)-2)::text,'id_cabana',_cab(),
    'tipo_override','hora_checkin','valor','15:00','motivo','m','creado_por','c','source_event','smoke_s2')),
  NULL, false, 'payload_invalido', 'none');

INSERT INTO _raw VALUES ('8', 'id_cabana inexistente -> ok:false cabana_no_encontrada',
  crear_override_horario(jsonb_build_object('fecha_desde',_nextmon(610)::text,'id_cabana',999999,
    'tipo_override','hora_checkin','valor','15:00','motivo','m','creado_por','c','source_event','smoke_s2')),
  NULL, false, 'cabana_no_encontrada', 'none');

INSERT INTO _raw VALUES ('9', 'fecha_hasta NULL solo afecta fecha_desde (comprometido en +5 no bloquea) -> ok:true',
  crear_override_horario(jsonb_build_object('fecha_desde',_nextmon(620)::text,'id_cabana',_cab(),
    'tipo_override','hora_checkin','valor','15:00','motivo','m','creado_por','c','source_event','smoke_s2')),
  NULL, true, NULL, 'exists_id');

INSERT INTO _raw VALUES ('10', 'activo=false (co16) -> ok:true inactivo, sin incompatibilidad e inserta inactivo',
  crear_override_horario(jsonb_build_object('fecha_desde',_nextmon(630)::text,'id_cabana',_cab(),'activo',false,
    'tipo_override','hora_checkout','valor','16:00','motivo','m','creado_por','c','source_event','smoke_s2')),
  NULL, true, NULL, 'exists_id_inactive');

-- ===================== FASE 2: verdict en statement separado (ve las filas insertadas) =====================
INSERT INTO _res
SELECT orden, test, got::text,
  CASE
    WHEN expect_ok AND row_check='exists_id'
         AND (got->>'ok')::bool
         AND EXISTS (SELECT 1 FROM overrides_operativos WHERE id_override=(got->>'id_override')::bigint) THEN 'PASS'
    WHEN expect_ok AND row_check='exists_id_global'
         AND (got->>'ok')::bool AND got->>'alcance'='global_estricto'
         AND EXISTS (SELECT 1 FROM overrides_operativos WHERE id_override=(got->>'id_override')::bigint AND id_cabana IS NULL) THEN 'PASS'
    WHEN expect_ok AND row_check='exists_id_inactive'
         AND (got->>'ok')::bool AND (got->>'activo')::bool = false
         AND EXISTS (SELECT 1 FROM overrides_operativos WHERE id_override=(got->>'id_override')::bigint AND activo=false) THEN 'PASS'
    WHEN (NOT expect_ok) AND (got->>'ok')::bool = false AND got->>'error' = expect_err
         AND (row_check <> 'not_exists_anchor'
              OR NOT EXISTS (SELECT 1 FROM overrides_operativos WHERE source_event='smoke_s2' AND fecha_desde=anchor)) THEN 'PASS'
    ELSE 'FAIL'
  END
FROM _raw;

-- ===================== COMPUERTA (antes del ROLLBACK) =====================
DO $assert$
DECLARE v_pass int; v_fail int; v_total int; v_fails text;
BEGIN
  SELECT count(*) FILTER (WHERE verdict='PASS'), count(*) FILTER (WHERE verdict='FAIL'), count(*)
    INTO v_pass, v_fail, v_total FROM _res;
  SELECT string_agg(format('#%s [%s] got=%s', orden, test, got), ' || ' ORDER BY orden)
    INTO v_fails FROM _res WHERE verdict <> 'PASS';
  IF v_fail > 0 OR v_total <> 12 THEN
    RAISE EXCEPTION 'SMOKE S2 FALLA: pass=% (esp 12) fail=% (esp 0) total=% (esp 12). No-PASS: %',
      v_pass, v_fail, v_total, COALESCE(v_fails, '(ninguno; revisar conteo)');
  END IF;
  RAISE NOTICE 'SMOKE S2 OK: 12/12 PASS, 0 FAIL. (la tx se revierte a continuacion)';
END
$assert$;

ROLLBACK;

-- ---- VEREDICTO + POSTCHECK (unico SELECT visible, tras el ROLLBACK) ----
SELECT
  'SMOKE S2 VALIDADO: compuerta 12/12 PASS, 0 FAIL; la funcion no deja override cuando devuelve ok:false; el trigger S1 sigue activo; seeds revertidos.' AS veredicto,
  (SELECT count(*) FROM overrides_operativos WHERE source_event='smoke_s2') AS overrides_residual,
  (SELECT count(*) FROM reservas            WHERE source_event='smoke_s2') AS reservas_residual,
  (SELECT count(*) FROM pre_reservas        WHERE source_event='smoke_s2') AS prereservas_residual,
  (SELECT count(*) FROM huespedes           WHERE nombre='Smoke S2')       AS huespedes_residual;
