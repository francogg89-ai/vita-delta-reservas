-- =====================================================================
-- HORARIOS_FASEB_B3_SMOKES_TEST.sql  (v5)
-- Fase B / Bloque 3 - Smokes de la integracion resolver_horario() en
--   crear_prereserva. SOLO TEST. Correr DESPUES de aplicar la integracion.
-- Un unico BEGIN..ROLLBACK: NADA persiste (sin seed permanente, sin DELETE,
--   sin teardown, sin DROP). Gate de ambiente al inicio: si no es TEST, RAISE
--   y revierte todo. Helpers y overrides son efimeros (revierten en ROLLBACK).
-- Aislamiento: cada test usa un rango de fechas lejano y distinto; los overrides
--   se acotan por fecha (fecha_desde=fecha_hasta), no se pisan.
-- 18 tests. Secuencias BIGSERIAL pueden avanzar en los exitos (nextval no hace
--   rollback: inocuo). En los HARD el retorno es en el bloque 3.5 (antes de
--   upsert_huesped/INSERT): _seq_pr_movio y _seq_hu_movio DEBEN ser false, y eso
--   se GATEA en el veredicto (no solo se informa).
-- Compuerta de asercion ANTES del ROLLBACK: si no se cumplen 18/18 PASS + 8
--   pre_reservas creadas, RAISE EXCEPTION con detalle (y la tx se revierte).
-- El editor de Supabase solo muestra el ULTIMO SELECT: por eso el ultimo SELECT
--   (post-ROLLBACK) escupe el veredicto en texto + los residuales. Ver esa fila
--   = la compuerta paso; si hubiera fallado, el script cortaba con la EXCEPTION
--   antes de llegar. En fallo NO vas a ver 'VALIDADO', vas a ver la excepcion.
-- Ejecutar completo, con NADA seleccionado.
-- =====================================================================
BEGIN;

-- ---- GATE de ambiente (aborta y revierte si no es TEST) ----
DO $gate$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM configuracion_general
                 WHERE clave = 'ambiente' AND valor = 'test') THEN
    RAISE EXCEPTION 'SMOKE B3 abortado: configuracion_general.ambiente <> ''test''.';
  END IF;
END
$gate$;

-- ---- Helpers efimeros ----
CREATE OR REPLACE FUNCTION _nextmon(off int) RETURNS date LANGUAGE sql AS $fn$
  SELECT d + ((8 - EXTRACT(DOW FROM d)::int) % 7) FROM (SELECT fecha_hoy_ar() + off AS d) x;
$fn$;

CREATE OR REPLACE FUNCTION _nextsun(off int) RETURNS date LANGUAGE sql AS $fn$
  SELECT d + ((7 - EXTRACT(DOW FROM d)::int) % 7) FROM (SELECT fecha_hoy_ar() + off AS d) x;
$fn$;

CREATE OR REPLACE FUNCTION _cab() RETURNS bigint LANGUAGE sql AS $fn$
  SELECT id_cabana FROM cabanas WHERE activa ORDER BY id_cabana LIMIT 1;
$fn$;

CREATE OR REPLACE FUNCTION _mk(p_in date, p_out date, p_key text DEFAULT NULL,
                               p_hci text DEFAULT NULL, p_hco text DEFAULT NULL,
                               p_cab bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $fn$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'id_cabana',                COALESCE(p_cab, _cab()),
    'fecha_in',                 to_char(p_in,  'YYYY-MM-DD'),
    'fecha_out',                to_char(p_out, 'YYYY-MM-DD'),
    'personas',                 2,
    'canal_origen',             'manual',
    'canal_pago_esperado',      'efectivo',
    'source_event',             'smoke_b3',
    'monto_total',              100000,
    'monto_sena',               30000,
    'idempotency_key',          p_key,
    'hora_checkin_solicitada',  p_hci,
    'hora_checkout_solicitada', p_hco,
    'huesped', jsonb_build_object('nombre', 'Smoke B3', 'telefono', '1100000000')
  ));
$fn$;

CREATE OR REPLACE FUNCTION _call(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
  s_pr text := split_part(pg_get_serial_sequence('public.pre_reservas','id_pre_reserva'),'.',2);
  s_hu text := split_part(pg_get_serial_sequence('public.huespedes','id_huesped'),'.',2);
  pr_b bigint; pr_a bigint; hu_b bigint; hu_a bigint; r jsonb;
BEGIN
  SELECT last_value INTO pr_b FROM pg_sequences WHERE schemaname='public' AND sequencename=s_pr;
  SELECT last_value INTO hu_b FROM pg_sequences WHERE schemaname='public' AND sequencename=s_hu;
  r := crear_prereserva(p);
  SELECT last_value INTO pr_a FROM pg_sequences WHERE schemaname='public' AND sequencename=s_pr;
  SELECT last_value INTO hu_a FROM pg_sequences WHERE schemaname='public' AND sequencename=s_hu;
  RETURN r || jsonb_build_object('_seq_pr_movio', (pr_b IS DISTINCT FROM pr_a),
                                 '_seq_hu_movio', (hu_b IS DISTINCT FROM hu_a));
END
$fn$;

CREATE TEMP TABLE _res (orden int, test text, got jsonb, verdict text) ON COMMIT DROP;

-- ===================== T2 no-regresion habil =====================
INSERT INTO _res
SELECT 2, 'T2 no-reg habil (base default check-in/out)', got,
  CASE WHEN (got->>'ok')::bool
       AND (got->>'hora_checkin')::time  = COALESCE((SELECT valor FROM configuracion_general WHERE clave='hora_checkin_default')::time,  time '13:00')
       AND (got->>'hora_checkout')::time = COALESCE((SELECT valor FROM configuracion_general WHERE clave='hora_checkout_default')::time, time '10:00')
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(300), _nextmon(300)+2)) AS got) s;

-- ===================== T3 no-regresion domingo =====================
INSERT INTO _res
SELECT 3, 'T3 no-reg domingo (patron check-in/out)', got,
  CASE WHEN (got->>'ok')::bool
       AND (got->>'hora_checkin')::time  = COALESCE((SELECT valor FROM configuracion_general WHERE clave='hora_checkin_domingo')::time,  time '18:00')
       AND (got->>'hora_checkout')::time = COALESCE((SELECT valor FROM configuracion_general WHERE clave='hora_checkout_domingo')::time, time '16:00')
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextsun(330), _nextsun(330)+7)) AS got) s;

-- ===================== T4 override global check-in (anchor #1) =====================
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkin','15:00', NULL, _nextmon(360), _nextmon(360), 'smoke_b3','smoke';
INSERT INTO _res
SELECT 4, 'T4 override global check-in=15:00 (v_res_in->hora_checkin)', got,
  CASE WHEN (got->>'ok')::bool AND (got->>'hora_checkin')::time = time '15:00'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(360), _nextmon(360)+2)) AS got) s;

-- ===================== T4b override global check-out en fecha_out (anchor #2) =====================
-- valida DIRECTAMENTE v_hora_checkout_max := (v_res_out->>'hora_checkout')::TIME
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkout','12:00', NULL, _nextmon(690)+2, _nextmon(690)+2, 'smoke_b3','smoke';
INSERT INTO _res
SELECT 45, 'T4b override global check-out=12:00 en fecha_out (v_res_out->hora_checkout)', got,
  CASE WHEN (got->>'ok')::bool AND (got->>'hora_checkout')::time = time '12:00'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(690), _nextmon(690)+2)) AS got) s;

-- ===================== T5 override cabana gana a global (check-in) =====================
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkin','15:00', NULL,    _nextmon(390), _nextmon(390), 'smoke_b3','smoke';
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkin','16:00', _cab(),  _nextmon(390), _nextmon(390), 'smoke_b3','smoke';
INSERT INTO _res
SELECT 5, 'T5 override cabana(16:00) gana a global(15:00)', got,
  CASE WHEN (got->>'ok')::bool AND (got->>'hora_checkin')::time = time '16:00'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(390), _nextmon(390)+2)) AS got) s;

-- ===================== T6a HARD formato_invalido (borde=fecha_in) =====================
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkin','7:00', NULL, _nextmon(420), _nextmon(420), 'smoke_b3','smoke';
INSERT INTO _res
SELECT 61, 'T6a HARD formato_invalido (borde=fecha_in, sin consumo)', got,
  CASE WHEN (got->>'ok')='false' AND got->>'error'='override_hora_invalido'
       AND got->>'causa'='formato_invalido' AND got->>'borde'='fecha_in'
       AND (got->>'fecha_resolver')::date = _nextmon(420)
       AND (got->>'_seq_pr_movio')::boolean = false
       AND (got->>'_seq_hu_movio')::boolean = false
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(420), _nextmon(420)+2)) AS got) s;

-- ===================== T6b HARD cast_invalido =====================
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkin','25:99', NULL, _nextmon(450), _nextmon(450), 'smoke_b3','smoke';
INSERT INTO _res
SELECT 62, 'T6b HARD cast_invalido (sin consumo)', got,
  CASE WHEN (got->>'ok')='false' AND got->>'error'='override_hora_invalido'
       AND got->>'causa'='cast_invalido' AND got->>'borde'='fecha_in'
       AND (got->>'_seq_pr_movio')::boolean = false
       AND (got->>'_seq_hu_movio')::boolean = false
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(450), _nextmon(450)+2)) AS got) s;

-- ===================== T6c HARD fuera_de_ventana =====================
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkin','23:30', NULL, _nextmon(480), _nextmon(480), 'smoke_b3','smoke';
INSERT INTO _res
SELECT 63, 'T6c HARD fuera_de_ventana >22:00 (sin consumo)', got,
  CASE WHEN (got->>'ok')='false' AND got->>'error'='override_hora_invalido'
       AND got->>'causa'='fuera_de_ventana' AND got->>'borde'='fecha_in'
       AND (got->>'_seq_pr_movio')::boolean = false
       AND (got->>'_seq_hu_movio')::boolean = false
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(480), _nextmon(480)+2)) AS got) s;

-- ===================== T6d over-block: checkout corrupto en fecha_in =====================
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkout','99:99', NULL, _nextmon(510), _nextmon(510), 'smoke_b3','smoke';
INSERT INTO _res
SELECT 64, 'T6d over-block: checkout corrupto en fecha_in bloquea (borde=fecha_in, sin consumo)', got,
  CASE WHEN (got->>'ok')='false' AND got->>'error'='override_hora_invalido'
       AND got->>'borde'='fecha_in'
       AND (got->>'_seq_pr_movio')::boolean = false
       AND (got->>'_seq_hu_movio')::boolean = false
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(510), _nextmon(510)+2)) AS got) s;

-- ===================== T6e precedencia: gana a cabana_no_existe =====================
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkin','7:00', NULL, _nextmon(540), _nextmon(540), 'smoke_b3','smoke';
INSERT INTO _res
SELECT 65, 'T6e precedencia: override corrupto gana a cabana_no_existe (sin consumo)', got,
  CASE WHEN (got->>'ok')='false' AND got->>'error'='override_hora_invalido'
       AND got->>'borde'='fecha_in'
       AND (got->>'_seq_pr_movio')::boolean = false
       AND (got->>'_seq_hu_movio')::boolean = false
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(540), _nextmon(540)+2, NULL, NULL, NULL, 999999999)) AS got) s;

-- ===================== T6f HARD en segunda llamada: borde=fecha_out =====================
-- fecha_in limpio; override corrupto de hora_checkout SOLO en fecha_out =>
-- resolver(v_fecha_in) OK, resolver(v_fecha_out) HARD => borde=fecha_out.
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkout','25:99', NULL, _nextmon(720)+2, _nextmon(720)+2, 'smoke_b3','smoke';
INSERT INTO _res
SELECT 66, 'T6f HARD segunda llamada (borde=fecha_out, cast_invalido, sin consumo)', got,
  CASE WHEN (got->>'ok')='false' AND got->>'error'='override_hora_invalido'
       AND got->>'causa'='cast_invalido' AND got->>'borde'='fecha_out'
       AND (got->>'fecha_resolver')::date = _nextmon(720)+2
       AND (got->>'_seq_pr_movio')::boolean = false
       AND (got->>'_seq_hu_movio')::boolean = false
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(720), _nextmon(720)+2)) AS got) s;

-- ===================== T7 dentro del margen recomputado =====================
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkin','15:00', NULL, _nextmon(570), _nextmon(570), 'smoke_b3','smoke';
INSERT INTO _res
SELECT 7, 'T7 solicitada 16:00 dentro de [15:00,22:00] recomputado', got,
  CASE WHEN (got->>'ok')::bool AND (got->>'hora_checkin')::time = time '16:00'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(570), _nextmon(570)+2, NULL, '16:00')) AS got) s;

-- ===================== T8 fuera del margen recomputado =====================
INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkin','15:00', NULL, _nextmon(600), _nextmon(600), 'smoke_b3','smoke';
INSERT INTO _res
SELECT 8, 'T8 solicitada 14:00 < min recomputado 15:00 (hora_fuera_de_rango)', got,
  CASE WHEN (got->>'ok')='false' AND got->>'error'='hora_fuera_de_rango'
       AND got->>'campo'='hora_checkin' AND (got->>'minimo')::time = time '15:00'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(600), _nextmon(600)+2, NULL, '14:00')) AS got) s;

-- ===================== T9 guard fecha_in_pasada =====================
INSERT INTO _res
SELECT 9, 'T9 guard fecha_in_pasada (antes del resolver)', got,
  CASE WHEN (got->>'ok')='false' AND got->>'error'='fecha_in_pasada'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(fecha_hoy_ar()-10, fecha_hoy_ar()-8)) AS got) s;

-- ===================== T10 idempotencia intacta =====================
INSERT INTO _res
SELECT 101, 'T10 call1 crea (idempotent_match=false)', got,
  CASE WHEN (got->>'ok')::bool AND (got->>'idempotent_match')::bool = false
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(630), _nextmon(630)+2, 'SMOKEKEY10AB')) AS got) s;

INSERT INTO _res
SELECT 102, 'T10 call2 misma key => idempotent_match=true (pre_lock)', got,
  CASE WHEN (got->>'ok')::bool AND (got->>'idempotent_match')::bool = true
       AND got->>'recovery_path'='pre_lock'
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(630), _nextmon(630)+2, 'SMOKEKEY10AB')) AS got) s;

-- ===================== T10b idempotencia gana a override corrupto =====================
INSERT INTO _res
SELECT 103, 'T10b call1 crea', got,
  CASE WHEN (got->>'ok')::bool AND (got->>'idempotent_match')::bool = false
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(660), _nextmon(660)+2, 'SMOKEKEY10B01')) AS got) s;

INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por)
  SELECT 'hora_checkin','7:00', NULL, _nextmon(660), _nextmon(660), 'smoke_b3','smoke';

INSERT INTO _res
SELECT 104, 'T10b call2 idempotent_match pese a override corrupto (pre-check gana, NO HARD)', got,
  CASE WHEN (got->>'ok')::bool AND (got->>'idempotent_match')::bool = true
       AND got->>'recovery_path'='pre_lock'
       AND (got ? 'error') = false
       THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT _call(_mk(_nextmon(660), _nextmon(660)+2, 'SMOKEKEY10B01')) AS got) s;

-- ===================== VEREDICTO =====================
SELECT orden, test, verdict,
       got->>'error'            AS error,
       got->>'causa'            AS causa,
       got->>'borde'            AS borde,
       got->>'hora_checkin'     AS hci,
       got->>'hora_checkout'    AS hco,
       got->>'idempotent_match' AS idem,
       got->>'_seq_pr_movio'    AS seq_pr,
       got->>'_seq_hu_movio'    AS seq_hu
FROM _res
ORDER BY orden;

SELECT count(*) FILTER (WHERE verdict='PASS') AS pass,
       count(*) FILTER (WHERE verdict='FAIL') AS fail,
       count(*)                               AS total
FROM _res;

-- INFO: filas pre_reservas creadas en la tx (deben ser solo los 8 exitos; se revierten).
SELECT count(*) AS pre_reservas_creadas_en_tx
FROM pre_reservas WHERE source_event = 'smoke_b3';

-- ===================== COMPUERTA DE ASERCION (antes del ROLLBACK) =====================
-- El editor solo muestra el ultimo SELECT; esta compuerta valida en ejecucion.
DO $verdict$
DECLARE
  v_pass  int;
  v_fail  int;
  v_total int;
  v_pr    int;
  v_fails text;
BEGIN
  SELECT count(*) FILTER (WHERE verdict = 'PASS'),
         count(*) FILTER (WHERE verdict = 'FAIL'),
         count(*)
    INTO v_pass, v_fail, v_total
  FROM _res;

  SELECT count(*) INTO v_pr
  FROM pre_reservas WHERE source_event = 'smoke_b3';

  IF v_pass <> 18 OR v_fail <> 0 OR v_total <> 18 OR v_pr <> 8 THEN
    SELECT string_agg(orden || ':' || test, ' | ' ORDER BY orden)
      INTO v_fails
    FROM _res WHERE verdict <> 'PASS';
    RAISE EXCEPTION 'SMOKE B3 FALLA: pass=% (esp 18) fail=% (esp 0) total=% (esp 18) pre_reservas_creadas=% (esp 8). No-PASS: %',
      v_pass, v_fail, v_total, v_pr, COALESCE(v_fails, '(ninguno; revisar conteo de pre_reservas)');
  END IF;

  RAISE NOTICE 'SMOKE B3 OK: 18/18 PASS, 0 FAIL, pre_reservas_creadas = 8. (la tx se revierte a continuacion)';
END
$verdict$;

ROLLBACK;

-- =====================================================================
-- VEREDICTO + POSTCHECK (unico SELECT que muestra el editor, tras el ROLLBACK).
--   Ver esta fila = la compuerta paso (18/18 PASS, 0 FAIL, 8 pre_reservas); si
--   hubiera fallado, el script habria cortado con la EXCEPTION de la compuerta
--   antes de este punto. Los dos residuales DEBEN ser 0 (rollback limpio).
-- =====================================================================
SELECT
  'SMOKE B3 VALIDADO: compuerta 18/18 PASS, 0 FAIL, 8 pre_reservas creadas y revertidas.' AS veredicto,
  (SELECT count(*) FROM pre_reservas         WHERE source_event = 'smoke_b3') AS pre_reservas_residual,
  (SELECT count(*) FROM overrides_operativos WHERE motivo       = 'smoke_b3') AS overrides_residual;
