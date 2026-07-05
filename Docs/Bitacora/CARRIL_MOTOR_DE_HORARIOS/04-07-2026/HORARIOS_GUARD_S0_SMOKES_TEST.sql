-- =====================================================================
-- HORARIOS_GUARD_S0_SMOKES_TEST.sql
-- Smokes de S0 (los tres validadores). ALCANCE: SOLO TEST.
-- Los validadores son read-only; el smoke SIEMBRA estado (overrides/reservas/pre_reservas/huesped),
-- llama a los validadores, y revierte todo (BEGIN..ROLLBACK). Compuerta de asercion ANTES del
-- ROLLBACK; el ultimo SELECT (post-ROLLBACK) escupe veredicto + residuales (=0).
-- Aislamiento por anclas de fecha distintas (200..290), sin DELETE.
-- Correr el script COMPLETO (L-8A-01).
--
-- Casos:
--   1   fecha libre + base -> ok
--   2   override checkout 16 (checkin base 13) -> override_incompatible_same_day
--   3   paquete checkout 16 + checkin 18 (gap 2h) -> ok
--   4   reserva comprometida con check-in en la fecha -> override_pisa_reserva
--   5   reserva comprometida con check-out en la fecha -> override_pisa_reserva
--   6   reserva comprometida aunque la hora del override coincida -> igual override_pisa_reserva
--   7   valor de override invalido (25:99) -> override_hora_invalido
--   81  fecha_hasta NULL aplica en fecha_desde (dispara same-day) 
--   82  fecha_hasta NULL NO aplica en fecha_desde+5 (base, ok)  [semantica R0]
--   91  override por cabana afecta esa cabana
--   92  misma fecha, otra cabana sin override -> ok (cabana-especificidad)
--   93  override GLOBAL afecta una cabana especifica (prep expansion S1/S3)
--   4b  pre-reserva vigente comprometida -> override_pisa_prereserva
-- =====================================================================

BEGIN;

-- ---- GATE: TEST/public + resolver post-R0 (58d75c1b) + ODR (37009a32) ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM configuracion_general WHERE clave = 'ambiente');
  v_res text;
  v_odr text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'SMOKE S0 abortado: ambiente=% (esperado test).', v_amb;
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'SMOKE S0 abortado: schema=% (esperado public).', current_schema();
  END IF;
  v_res := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'SMOKE S0 abortado: fingerprint resolver=% (esperado 58d75c1b, post-R0).', v_res;
  END IF;
  v_odr := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'SMOKE S0 abortado: fingerprint ODR=% (esperado 37009a32).', v_odr;
  END IF;
  IF to_regprocedure('public.validar_estado_override(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'SMOKE S0 abortado: falta validar_estado_override. Corre HORARIOS_GUARD_S0_VALIDADORES_TEST.sql primero.';
  END IF;
  RAISE NOTICE 'SMOKE S0 GATE OK: test/public, resolver=58d75c1b, ODR=37009a32, validadores presentes.';
END
$gate$;

-- ---- Helpers efimeros (revierten en ROLLBACK) ----
CREATE OR REPLACE FUNCTION _nextmon(off int) RETURNS date LANGUAGE sql AS $fn$
  SELECT d + ((8 - EXTRACT(DOW FROM d)::int) % 7) FROM (SELECT fecha_hoy_ar() + off AS d) x;
$fn$;
CREATE OR REPLACE FUNCTION _cab()  RETURNS bigint LANGUAGE sql AS $fn$
  SELECT id_cabana FROM cabanas WHERE activa ORDER BY id_cabana LIMIT 1;
$fn$;
CREATE OR REPLACE FUNCTION _cab2() RETURNS bigint LANGUAGE sql AS $fn$
  SELECT id_cabana FROM cabanas WHERE activa ORDER BY id_cabana OFFSET 1 LIMIT 1;
$fn$;

-- huesped efimero para seeds de reservas/pre_reservas
INSERT INTO huespedes(nombre, telefono) VALUES ('Smoke S0', '1190000000');
CREATE OR REPLACE FUNCTION _hsp() RETURNS bigint LANGUAGE sql AS $fn$
  SELECT id_huesped FROM huespedes WHERE nombre = 'Smoke S0' ORDER BY id_huesped DESC LIMIT 1;
$fn$;

-- helper de seed de override (columnas reales; source_event sentinel)
CREATE OR REPLACE FUNCTION _mkovr(p_tipo text, p_valor text, p_cab bigint, p_desde date, p_hasta date) RETURNS void
LANGUAGE sql AS $fn$
  INSERT INTO overrides_operativos(tipo_override, valor, id_cabana, fecha_desde, fecha_hasta, motivo, creado_por, source_event)
  VALUES (p_tipo, p_valor, p_cab, p_desde, p_hasta, 'smoke s0', 'smoke', 'smoke_s0');
$fn$;

-- helper de seed de reserva comprometida
CREATE OR REPLACE FUNCTION _mkres(p_cab bigint, p_ci date, p_co date, p_hci time, p_hco time) RETURNS void
LANGUAGE sql AS $fn$
  INSERT INTO reservas(id_cabana, id_huesped, fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
                       personas, estado, canal_origen, monto_total, monto_sena, monto_saldo, source_event)
  VALUES (p_cab, _hsp(), p_ci, p_co, p_hci, p_hco, 2, 'confirmada', 'manual', 100000, 30000, 70000, 'smoke_s0');
$fn$;

CREATE TEMP TABLE _res (orden int, test text, got text, verdict text) ON COMMIT DROP;

-- ===================== 1: fecha libre + base -> ok (ancla 200) =====================
INSERT INTO _res
SELECT 1, 'C1 fecha libre base -> ok', got::text,
  CASE WHEN (got->>'ok')::bool THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_override(_cab(), _nextmon(200)) AS got) s;

-- ===================== 2: override checkout 16, checkin base 13 -> same-day (ancla 210) =====================
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(210), _nextmon(210));
INSERT INTO _res
SELECT 2, 'C2 co16 + ci base -> override_incompatible_same_day', got::text,
  CASE WHEN (got->>'ok')::bool = false AND got->>'error' = 'override_incompatible_same_day' THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_override(_cab(), _nextmon(210)) AS got) s;

-- ===================== 3: paquete co16 + ci18 (gap 2h) -> ok (ancla 220) =====================
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(220), _nextmon(220));
SELECT _mkovr('hora_checkin', '18:00', _cab(), _nextmon(220), _nextmon(220));
INSERT INTO _res
SELECT 3, 'C3 paquete co16+ci18 (gap 2h) -> ok', got::text,
  CASE WHEN (got->>'ok')::bool THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_override(_cab(), _nextmon(220)) AS got) s;

-- ===================== 4: reserva comprometida con check-in en la fecha (ancla 230) =====================
SELECT _mkres(_cab(), _nextmon(230), _nextmon(230)+2, '13:00','10:00');
INSERT INTO _res
SELECT 4, 'C4 evento check-in comprometido -> override_pisa_reserva', got::text,
  CASE WHEN (got->>'ok')::bool = false AND got->>'error' = 'override_pisa_reserva' THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_override(_cab(), _nextmon(230)) AS got) s;

-- ===================== 5: reserva comprometida con check-out en la fecha (ancla 240) =====================
SELECT _mkres(_cab(), _nextmon(240)-2, _nextmon(240), '13:00','10:00');
INSERT INTO _res
SELECT 5, 'C5 evento check-out comprometido -> override_pisa_reserva', got::text,
  CASE WHEN (got->>'ok')::bool = false AND got->>'error' = 'override_pisa_reserva' THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_override(_cab(), _nextmon(240)) AS got) s;

-- ===================== 6: comprometido aunque hora coincida (ancla 250) =====================
-- reserva con hora_checkin 18:00, y override ci 18:00 (misma hora). Igual falla por existencia.
SELECT _mkres(_cab(), _nextmon(250), _nextmon(250)+2, '18:00','10:00');
SELECT _mkovr('hora_checkin','18:00', _cab(), _nextmon(250), _nextmon(250));
INSERT INTO _res
SELECT 6, 'C6 comprometido aunque hora coincide -> override_pisa_reserva', got::text,
  CASE WHEN (got->>'ok')::bool = false AND got->>'error' = 'override_pisa_reserva' THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_override(_cab(), _nextmon(250)) AS got) s;

-- ===================== 7: valor invalido (25:99) -> override_hora_invalido (ancla 260) =====================
SELECT _mkovr('hora_checkin','25:99', _cab(), _nextmon(260), _nextmon(260));
INSERT INTO _res
SELECT 7, 'C7 valor invalido 25:99 -> override_hora_invalido', got::text,
  CASE WHEN (got->>'ok')::bool = false AND got->>'error' = 'override_hora_invalido' THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_override(_cab(), _nextmon(260)) AS got) s;

-- ===================== 81/82: fecha_hasta NULL semantica R0 (ancla 270) =====================
-- override checkout 16 con fecha_hasta NULL en D. Aplica en D (same-day), NO en D+5.
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(270), NULL);
INSERT INTO _res
SELECT 81, 'C81 fecha_hasta NULL aplica en fecha_desde (same-day)', got::text,
  CASE WHEN (got->>'ok')::bool = false AND got->>'error' = 'override_incompatible_same_day' THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_horario_final(_cab(), _nextmon(270)) AS got) s;
INSERT INTO _res
SELECT 82, 'C82 fecha_hasta NULL NO aplica en fecha_desde+5 (base ok)', got::text,
  CASE WHEN (got->>'ok')::bool THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_horario_final(_cab(), _nextmon(270)+5) AS got) s;   -- lunes+5 = sabado (no domingo)

-- ===================== 91/92: cabana-especificidad (ancla 280) =====================
SELECT _mkovr('hora_checkout','16:00', _cab(), _nextmon(280), _nextmon(280));   -- solo _cab()
INSERT INTO _res
SELECT 91, 'C91 override por cabana afecta esa cabana (same-day)', got::text,
  CASE WHEN (got->>'ok')::bool = false AND got->>'error' = 'override_incompatible_same_day' THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_horario_final(_cab(), _nextmon(280)) AS got) s;
INSERT INTO _res
SELECT 92, 'C92 otra cabana sin override en misma fecha -> ok', got::text,
  CASE WHEN (got->>'ok')::bool THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_horario_final(_cab2(), _nextmon(280)) AS got) s;

-- ===================== 93: override GLOBAL afecta cabana especifica (ancla 290) =====================
SELECT _mkovr('hora_checkout','16:00', NULL, _nextmon(290), _nextmon(290));     -- global (id_cabana NULL)
INSERT INTO _res
SELECT 93, 'C93 override global afecta cabana especifica (prep S1/S3)', got::text,
  CASE WHEN (got->>'ok')::bool = false AND got->>'error' = 'override_incompatible_same_day' THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_horario_final(_cab(), _nextmon(290)) AS got) s;

-- ===================== 4b: pre-reserva vigente comprometida (ancla 300) =====================
INSERT INTO pre_reservas(id_cabana, id_huesped, fecha_in, fecha_out, hora_checkin, hora_checkout,
                         personas, monto_total, monto_sena, estado, expira_en, canal_pago_esperado, canal_origen, source_event)
SELECT _cab(), _hsp(), _nextmon(300), _nextmon(300)+2, '13:00','10:00', 2, 100000, 30000,
       'pendiente_pago', NOW() + interval '1 day', 'efectivo', 'manual', 'smoke_s0';
INSERT INTO _res
SELECT 45, 'C4b pre-reserva vigente comprometida -> override_pisa_prereserva', got::text,
  CASE WHEN (got->>'ok')::bool = false AND got->>'error' = 'override_pisa_prereserva' THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT validar_estado_override(_cab(), _nextmon(300)) AS got) s;

-- ===================== COMPUERTA DE ASERCION (antes del ROLLBACK) =====================
DO $assert$
DECLARE
  v_pass int; v_fail int; v_total int; v_fails text;
BEGIN
  SELECT count(*) FILTER (WHERE verdict='PASS'),
         count(*) FILTER (WHERE verdict='FAIL'),
         count(*)
    INTO v_pass, v_fail, v_total
  FROM _res;
  SELECT string_agg(format('#%s %s => %s', orden, test, got), ' || ' ORDER BY orden)
    INTO v_fails FROM _res WHERE verdict <> 'PASS';
  IF v_fail > 0 OR v_total <> 13 THEN
    RAISE EXCEPTION 'SMOKE S0 FALLA: pass=% (esp 13) fail=% (esp 0) total=% (esp 13). No-PASS: %',
      v_pass, v_fail, v_total, COALESCE(v_fails, '(ninguno; revisar conteo)');
  END IF;
  RAISE NOTICE 'SMOKE S0 OK: 13/13 PASS, 0 FAIL. (la tx se revierte a continuacion)';
END
$assert$;

ROLLBACK;

-- ---- VEREDICTO + POSTCHECK (unico SELECT visible, tras el ROLLBACK) ----
SELECT
  'SMOKE S0 VALIDADO: compuerta 13/13 PASS, 0 FAIL; seeds efimeros revertidos.' AS veredicto,
  (SELECT count(*) FROM overrides_operativos WHERE source_event = 'smoke_s0') AS overrides_residual,
  (SELECT count(*) FROM reservas            WHERE source_event = 'smoke_s0') AS reservas_residual,
  (SELECT count(*) FROM pre_reservas        WHERE source_event = 'smoke_s0') AS prereservas_residual,
  (SELECT count(*) FROM huespedes           WHERE nombre = 'Smoke S0')       AS huespedes_residual;
