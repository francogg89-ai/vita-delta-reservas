-- =====================================================================
-- HORARIOS_R0_RESOLVER_SMOKES_TEST.sql
-- Smokes del pre-bloque R0 (resolver corregido). ALCANCE: SOLO TEST.
-- Corre DESPUES del FIX. Un unico BEGIN..ROLLBACK: NADA persiste (helpers y
--   overrides son efimeros; crear_prereserva escribe y se revierte). Compuerta de
--   asercion ANTES del ROLLBACK: si no son 9/9 PASS, RAISE EXCEPTION (y revierte).
--   El ultimo SELECT (post-ROLLBACK) escupe el veredicto + residuales (=0).
-- Aislamiento por anclas de fecha distintas (200/260/320/380/440/500), sin DELETE.
-- Correr el script COMPLETO (L-8A-01).
--
-- Casos (requisito de Franco):
--   C1  override fecha_hasta NULL APLICA en fecha_desde.
--   C2  el mismo override NO aplica en fecha_desde+5 (NULL = solo fecha_desde).
--   C3a rango fecha_hasta no-null: inclusivo en el borde superior (D+2 aplica).
--   C3b rango fecha_hasta no-null: NO aplica pasado el borde (D+3 = base).
--   C4  precedencia cabana > global.
--   C5  HARD por valor invalido (cast_invalido) sigue intacto.
--   C6a obtener_disponibilidad_rango ejecuta contra el resolver corregido (override en D).
--   C6b obtener_disponibilidad_rango: D+5 = base (NULL corregido, via ODR).
--   C6c crear_prereserva ejecuta contra el resolver corregido y ESCRIBE.
-- =====================================================================

BEGIN;

-- ---- GATE: TEST/public + FIX aplicado (resolver <> 759662b4) + ODR intacta ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM configuracion_general WHERE clave = 'ambiente');
  v_res text;
  v_odr text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'SMOKE R0 abortado: ambiente=% (esperado test).', v_amb;
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'SMOKE R0 abortado: schema=% (esperado public).', current_schema();
  END IF;
  v_res := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
  IF v_res = '759662b4afaed7af426917aa3717b34c' THEN
    RAISE EXCEPTION 'SMOKE R0 abortado: resolver AUN en fingerprint pre-fix 759662b4. Corre HORARIOS_R0_RESOLVER_FIX_TEST.sql primero.';
  END IF;
  v_odr := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'SMOKE R0 abortado: fingerprint ODR=% (esperado 37009a32154f93b80520500c0f15b46b).', v_odr;
  END IF;
  RAISE NOTICE 'SMOKE R0 GATE OK: test/public, resolver post-fix=%, ODR=37009a32.', v_res;
END
$gate$;

-- ---- Helpers efimeros (revierten en ROLLBACK) ----
CREATE OR REPLACE FUNCTION _nextmon(off int) RETURNS date LANGUAGE sql AS $fn$
  SELECT d + ((8 - EXTRACT(DOW FROM d)::int) % 7) FROM (SELECT fecha_hoy_ar() + off AS d) x;
$fn$;

CREATE OR REPLACE FUNCTION _cab() RETURNS bigint LANGUAGE sql AS $fn$
  SELECT id_cabana FROM cabanas WHERE activa ORDER BY id_cabana LIMIT 1;
$fn$;

-- base default de check-in (fallback 13:00), fuente honesta = configuracion_general.
CREATE OR REPLACE FUNCTION _base_ci() RETURNS time LANGUAGE sql AS $fn$
  SELECT COALESCE((SELECT valor FROM configuracion_general WHERE clave='hora_checkin_default')::time, time '13:00');
$fn$;

-- payload de crear_prereserva con source_event='smoke_r0'.
CREATE OR REPLACE FUNCTION _mk_r0(p_in date, p_out date) RETURNS jsonb LANGUAGE sql AS $fn$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'id_cabana',            _cab(),
    'fecha_in',             to_char(p_in,  'YYYY-MM-DD'),
    'fecha_out',            to_char(p_out, 'YYYY-MM-DD'),
    'personas',             2,
    'canal_origen',         'manual',
    'canal_pago_esperado',  'efectivo',
    'source_event',         'smoke_r0',
    'monto_total',          100000,
    'monto_sena',           30000,
    'huesped', jsonb_build_object('nombre', 'Smoke R0', 'telefono', '1100000000')
  ));
$fn$;

-- llama crear_prereserva y anexa flag de "escribio" (avanzo la secuencia de pre_reservas).
CREATE OR REPLACE FUNCTION _call_r0(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
  s_pr text := split_part(pg_get_serial_sequence('public.pre_reservas','id_pre_reserva'),'.',2);
  pr_b bigint; pr_a bigint; r jsonb;
BEGIN
  SELECT last_value INTO pr_b FROM pg_sequences WHERE schemaname='public' AND sequencename=s_pr;
  r := crear_prereserva(p);
  SELECT last_value INTO pr_a FROM pg_sequences WHERE schemaname='public' AND sequencename=s_pr;
  RETURN r || jsonb_build_object('_seq_pr_movio', (pr_b IS DISTINCT FROM pr_a));
END
$fn$;

CREATE TEMP TABLE _res (orden int, test text, got text, verdict text) ON COMMIT DROP;

-- ===================== C1/C2  NULL = solo fecha_desde (ancla 200) =====================
-- override hora_checkin, cabana, fecha_desde=D(lunes), fecha_hasta=NULL, valor 15:00.
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event)
  SELECT 'hora_checkin','15:00', _cab(), _nextmon(200), NULL, 'smoke r0 c1c2','smoke','smoke_r0';

INSERT INTO _res
SELECT 1, 'C1 NULL aplica en fecha_desde (15:00, override_cabana)', got::text,
  CASE WHEN (got->>'ok')::bool
       AND (got->>'hora_checkin')::time = time '15:00'
       AND (got->>'origen_checkin') = 'override_cabana'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT resolver_horario(_cab(), _nextmon(200)) AS got) s;

INSERT INTO _res
SELECT 2, 'C2 NULL NO aplica en fecha_desde+5 (base, origen base)', got::text,
  CASE WHEN (got->>'ok')::bool
       AND (got->>'hora_checkin')::time = _base_ci()
       AND (got->>'origen_checkin') = 'base'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT resolver_horario(_cab(), _nextmon(200)+5) AS got) s;   -- lunes+5 = sabado (no domingo)

-- ===================== C3  rango fecha_hasta no-null inclusivo (ancla 260) =====================
-- override [D, D+2] valor 15:00.
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event)
  SELECT 'hora_checkin','15:00', _cab(), _nextmon(260), _nextmon(260)+2, 'smoke r0 c3','smoke','smoke_r0';

INSERT INTO _res
SELECT 31, 'C3a fecha_hasta no-null: D+2 (borde) aplica (15:00)', got::text,
  CASE WHEN (got->>'ok')::bool
       AND (got->>'hora_checkin')::time = time '15:00'
       AND (got->>'origen_checkin') = 'override_cabana'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT resolver_horario(_cab(), _nextmon(260)+2) AS got) s;

INSERT INTO _res
SELECT 32, 'C3b fecha_hasta no-null: D+3 fuera de rango (base)', got::text,
  CASE WHEN (got->>'ok')::bool
       AND (got->>'hora_checkin')::time = _base_ci()
       AND (got->>'origen_checkin') = 'base'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT resolver_horario(_cab(), _nextmon(260)+3) AS got) s;   -- lunes+3 = jueves (no domingo)

-- ===================== C4  precedencia cabana > global (ancla 320) =====================
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event)
  SELECT 'hora_checkin','16:00', NULL,    _nextmon(320), _nextmon(320), 'smoke r0 c4 global','smoke','smoke_r0';
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event)
  SELECT 'hora_checkin','17:00', _cab(),  _nextmon(320), _nextmon(320), 'smoke r0 c4 cabana','smoke','smoke_r0';

INSERT INTO _res
SELECT 4, 'C4 cabana(17:00) gana a global(16:00)', got::text,
  CASE WHEN (got->>'ok')::bool
       AND (got->>'hora_checkin')::time = time '17:00'
       AND (got->>'origen_checkin') = 'override_cabana'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT resolver_horario(_cab(), _nextmon(320)) AS got) s;

-- ===================== C5  HARD valor invalido (ancla 380) =====================
-- '25:99' pasa el regex ^\d{2}:\d{2}$ pero falla el cast a TIME => causa cast_invalido.
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event)
  SELECT 'hora_checkin','25:99', _cab(), _nextmon(380), _nextmon(380), 'smoke r0 c5','smoke','smoke_r0';

INSERT INTO _res
SELECT 5, 'C5 HARD valor invalido => override_hora_invalido/cast_invalido', got::text,
  CASE WHEN (got->>'ok')::bool = false
       AND (got->>'error') = 'override_hora_invalido'
       AND (got->>'causa') = 'cast_invalido'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT resolver_horario(_cab(), _nextmon(380)) AS got) s;

-- ===================== C6a/C6b  ODR contra el resolver corregido (ancla 440) =====================
-- override NULL en D; la ODR debe mostrar 15:00 en D y base en D+5.
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event)
  SELECT 'hora_checkin','15:00', _cab(), _nextmon(440), NULL, 'smoke r0 c6','smoke','smoke_r0';

INSERT INTO _res
SELECT 61, 'C6a ODR ejecuta + override NULL en D (hora_checkin_base=15:00)', hci::text,
  CASE WHEN hci = time '15:00' THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT hora_checkin_base AS hci
      FROM obtener_disponibilidad_rango(_nextmon(440), _nextmon(440)+6, _cab())
      WHERE fecha = _nextmon(440)) s;

INSERT INTO _res
SELECT 62, 'C6b ODR D+5 = base (NULL corregido, hora_checkin_base=base)', hci::text,
  CASE WHEN hci = _base_ci() THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT hora_checkin_base AS hci
      FROM obtener_disponibilidad_rango(_nextmon(440), _nextmon(440)+6, _cab())
      WHERE fecha = _nextmon(440)+5) s;

-- ===================== C6c  crear_prereserva contra el resolver corregido (ancla 500) =====================
-- estadia limpia (sin override), lunes->jueves; debe ejecutar (ok=true) y ESCRIBIR.
INSERT INTO _res
SELECT 63, 'C6c crear_prereserva ejecuta contra resolver corregido y escribe', got::text,
  CASE WHEN (got->>'ok')::bool AND (got->>'_seq_pr_movio')::bool
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call_r0(_mk_r0(_nextmon(500), _nextmon(500)+3)) AS got) s;

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
  IF v_fail > 0 OR v_total <> 9 THEN
    RAISE EXCEPTION 'SMOKE R0 FALLA: pass=% (esp 9) fail=% (esp 0) total=% (esp 9). No-PASS: %',
      v_pass, v_fail, v_total, COALESCE(v_fails, '(ninguno; revisar conteo)');
  END IF;
  RAISE NOTICE 'SMOKE R0 OK: 9/9 PASS, 0 FAIL. (la tx se revierte a continuacion)';
END
$assert$;

ROLLBACK;

-- ---- VEREDICTO + POSTCHECK (unico SELECT que muestra el editor, tras el ROLLBACK) ----
SELECT
  'SMOKE R0 VALIDADO: compuerta 9/9 PASS, 0 FAIL; overrides y pre_reservas efimeras revertidas.' AS veredicto,
  (SELECT count(*) FROM overrides_operativos WHERE source_event = 'smoke_r0') AS overrides_residual,
  (SELECT count(*) FROM pre_reservas         WHERE source_event = 'smoke_r0') AS prereservas_residual;
