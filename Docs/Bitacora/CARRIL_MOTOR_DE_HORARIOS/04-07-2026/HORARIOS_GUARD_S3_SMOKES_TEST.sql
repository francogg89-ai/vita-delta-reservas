-- =====================================================================
-- HORARIOS_GUARD_S3_SMOKES_TEST.sql
-- Smokes de S3 (crear_paquete_dia_especial). ALCANCE: SOLO TEST. Todo en BEGIN..ROLLBACK.
--
-- Patron de DOS FASES (por visibilidad intra-statement, igual que S2):
--   FASE 1: cada caso llama la funcion UNA vez en su propio statement -> guarda el jsonb en _raw.
--   FASE 2: statements separados computan el verdict (ya ven las filas insertadas por la fase 1).
-- Anclas espaciadas de a 30 (los seeds llegan hasta +7; con ese aire no colisionan tras el
-- redondeo a lunes de _nextmon). Overrides de paquete llevan source_event hijo 'pkg:...';
-- reservas comprometidas + INSERT directo llevan 'smoke_s3'; overrides SEMBRADOS de precedencia
-- llevan 'seed_s3'. Compuerta ANTES del ROLLBACK; ultimo SELECT da veredicto + residuales (=0).
-- Correr el script COMPLETO (L-8A-01).
--
-- Casos (18 aserciones + residuales):
--   1  cabana valido co16+ci18 -> ok:true, crea 2 overrides
--   2  cabana gap_minutos=90 (<120) -> ok:false payload_invalido, NO deja mitades
--   3  cabana con reserva comprometida -> ok:false override_pisa_reserva, NO deja mitades
--   4  global_estricto todas libres -> ok:true global_real, 2 overrides globales
--   5  global_estricto con 1 comprometida -> ok:false override_pisa_reserva, NO deja globales
--   6  todas_posibles con 1 comprometida -> ok:true, resto per-cabana, excluye 1, NO global
--   7  todas_posibles todas comprometidas -> ok:false sin_cabanas_aplicables, NO deja overrides
--   8  grupo_estricto con 1 conflictiva -> ok:false override_pisa_reserva, NO deja nada del grupo
--   9  grupo_posibles mismo grupo -> ok:true, aplica libres, excluye la conflictiva
--   10 ids_cabanas con id inexistente -> ok:false ids_cabanas_invalidos
--   11 fecha_hasta NULL solo afecta fecha (comprometido en +5 no bloquea) -> ok:true
--   12 source_event trazable en checkout/checkin (hijos deterministas)
--   13 trigger S1 sigue activo: INSERT directo invalido (fuera de la funcion) -> FALLA
--   14 global_estricto SOMBREADO por override especifico (efecto) -> ok:false
--      paquete_no_aplicado_efectivamente, NO deja globales
--   15 todas_posibles con cabana sombreada por especifico de MAYOR precedencia (created_at futuro)
--      -> ok:true, excluye esa cabana con paquete_no_aplicado_efectivamente, aplica el resto, NO global
--   16 cabana sombreada por especifico de mayor precedencia (created_at futuro) -> ok:false
--      paquete_no_aplicado_efectivamente, NO deja mitades
--   17 control positivo: sin sombra (seed global de MENOR precedencia) el paquete queda efectivo -> ok:true
--   18 ids_cabanas con duplicados [1,1,2] -> ok:false ids_cabanas_invalidos
--   19 grupo_estricto SIN ids_cabanas (clave ausente) -> ok:false payload_invalido (no error inesperado)
--   20 grupo_posibles con ids_cabanas: null (JSON null) -> ok:false payload_invalido
--   21 grupo_estricto con ids_cabanas string (no-array escalar) -> ok:false payload_invalido
--   22 grupo_estricto con ids_cabanas [] (array vacio) -> ok:false payload_invalido
-- =====================================================================

BEGIN;

-- ---- GATE ----
DO $gate$
DECLARE v_amb text := (SELECT valor FROM configuracion_general WHERE clave='ambiente'); v_res text; v_odr text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN RAISE EXCEPTION 'SMOKE S3 abortado: ambiente=% (esperado test).', v_amb; END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN RAISE EXCEPTION 'SMOKE S3 abortado: schema=%.', current_schema(); END IF;
  v_res := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN RAISE EXCEPTION 'SMOKE S3 abortado: resolver=%.', v_res; END IF;
  v_odr := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN RAISE EXCEPTION 'SMOKE S3 abortado: ODR=%.', v_odr; END IF;
  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'SMOKE S3 abortado: falta crear_paquete_dia_especial. Corre HORARIOS_GUARD_S3_FUNCION_TEST.sql primero.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                 WHERE c.relname='overrides_operativos' AND t.tgname='trg_ov_guard' AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION 'SMOKE S3 abortado: falta el constraint trigger trg_ov_guard (S1).';
  END IF;
  RAISE NOTICE 'SMOKE S3 GATE OK.';
END
$gate$;

-- ---- Helpers efimeros ----
CREATE OR REPLACE FUNCTION _nextmon(off int) RETURNS date LANGUAGE sql AS $fn$
  SELECT d + ((8 - EXTRACT(DOW FROM d)::int) % 7) FROM (SELECT fecha_hoy_ar() + off AS d) x;
$fn$;
CREATE OR REPLACE FUNCTION _cab() RETURNS bigint LANGUAGE sql AS $fn$ SELECT id_cabana FROM cabanas WHERE activa ORDER BY id_cabana LIMIT 1; $fn$;

INSERT INTO huespedes(nombre, telefono) VALUES ('Smoke S3', '1190000003');
CREATE OR REPLACE FUNCTION _hsp() RETURNS bigint LANGUAGE sql AS $fn$ SELECT id_huesped FROM huespedes WHERE nombre='Smoke S3' ORDER BY id_huesped DESC LIMIT 1; $fn$;

CREATE OR REPLACE FUNCTION _mkres(p_cab bigint, p_ci date, p_co date) RETURNS void LANGUAGE sql AS $fn$
  INSERT INTO reservas(id_cabana, id_huesped, fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
                       personas, estado, canal_origen, monto_total, monto_sena, monto_saldo, source_event)
  VALUES (p_cab, _hsp(), p_ci, p_co, '13:00','10:00', 2, 'confirmada', 'manual', 100000, 30000, 70000, 'smoke_s3');
$fn$;

-- Seed de override de precedencia. p_fut=true => created_at futuro (para vencer a un paquete
-- ESPECIFICO por created_at DESC). p_cab NULL => override GLOBAL.
CREATE OR REPLACE FUNCTION _mkovr(p_cab bigint, p_tipo text, p_valor text, p_fecha date, p_fut boolean) RETURNS void LANGUAGE sql AS $fn$
  INSERT INTO overrides_operativos(fecha_desde, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event, created_at)
  VALUES (p_fecha, p_cab, p_tipo, p_valor, 'seed s3', 'smoke', true, 'seed_s3', CASE WHEN p_fut THEN NOW()+interval '1 day' ELSE NOW() END);
$fn$;

CREATE TEMP TABLE _raw (orden text, test text, got jsonb, anchor date) ON COMMIT DROP;
CREATE TEMP TABLE _res (orden text, test text, got text, verdict text) ON COMMIT DROP;

-- ---- Seeds de eventos comprometidos (reservas; no crean eventos diferidos de overrides) ----
SELECT _mkres(_cab(), _nextmon(600), _nextmon(600)+2);                 -- caso 3
SELECT _mkres(_cab(), _nextmon(660), _nextmon(660)+2);                 -- caso 5
SELECT _mkres(_cab(), _nextmon(690), _nextmon(690)+2);                 -- caso 6
SELECT _mkres(c.id_cabana, _nextmon(720), _nextmon(720)+2) FROM cabanas c WHERE c.activa;  -- caso 7
SELECT _mkres(2, _nextmon(750), _nextmon(750)+2);                      -- caso 8
SELECT _mkres(2, _nextmon(780), _nextmon(780)+2);                      -- caso 9
SELECT _mkres(_cab(), _nextmon(840)+5, _nextmon(840)+7);               -- caso 11

-- ===================== 13 (primero, para aislar su SET CONSTRAINTS IMMEDIATE) =====================
-- Va antes de sembrar overrides: asi el IMMEDIATE de este caso solo valida SU insert directo malo.
DO $c13$
DECLARE v_verd text;
BEGIN
  BEGIN
    SET CONSTRAINTS trg_ov_guard DEFERRED;
    INSERT INTO overrides_operativos(tipo_override,valor,id_cabana,fecha_desde,fecha_hasta,motivo,creado_por,source_event,activo)
    VALUES ('hora_checkout','16:00', _cab(), _nextmon(900), _nextmon(900), 'smoke s3','smoke','smoke_s3', true);
    SET CONSTRAINTS trg_ov_guard IMMEDIATE;
    v_verd := 'PASA';
  EXCEPTION WHEN SQLSTATE '45000' THEN
    v_verd := 'FALLA';
  END;
  INSERT INTO _res VALUES ('13', 'trigger S1 sigue activo: INSERT directo invalido (co16 solo) -> FALLA', v_verd,
    CASE WHEN v_verd='FALLA' THEN 'PASS' ELSE 'FAIL' END);
END
$c13$;
SET CONSTRAINTS trg_ov_guard DEFERRED;

-- ---- Seeds de overrides de PRECEDENCIA (diferidos; el trigger no dispara: la tx se revierte) ----
SELECT _mkovr(1,'hora_checkin','20:00',_nextmon(930),false);  SELECT _mkovr(1,'hora_checkout','17:00',_nextmon(930),false);  -- 14: especifico sombrea al global
SELECT _mkovr(1,'hora_checkin','20:00',_nextmon(960),true);   SELECT _mkovr(1,'hora_checkout','17:00',_nextmon(960),true);   -- 15: especifico futuro vence al paquete
SELECT _mkovr(1,'hora_checkin','20:00',_nextmon(990),true);   SELECT _mkovr(1,'hora_checkout','17:00',_nextmon(990),true);   -- 16: idem, cabana estricta
SELECT _mkovr(NULL,'hora_checkin','14:00',_nextmon(1020),false);                                                            -- 17: global de MENOR precedencia

-- ===================== FASE 1: una llamada por caso (statement propio) -> _raw =====================
INSERT INTO _raw VALUES ('1', 'cabana valido co16+ci18 -> ok:true crea 2 overrides',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(540)::text,'hora_checkout','16:00',
    'alcance','cabana','id_cabana',_cab(),'motivo','m','creado_por','c','source_event','pkg')), _nextmon(540));

INSERT INTO _raw VALUES ('2', 'cabana gap_minutos=90 (<120) -> ok:false payload_invalido, NO deja mitades',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(570)::text,'hora_checkout','16:00','gap_minutos',90,
    'alcance','cabana','id_cabana',_cab(),'motivo','m','creado_por','c','source_event','pkg')), _nextmon(570));

INSERT INTO _raw VALUES ('3', 'cabana con reserva comprometida -> ok:false override_pisa_reserva, NO deja mitades',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(600)::text,'hora_checkout','16:00',
    'alcance','cabana','id_cabana',_cab(),'motivo','m','creado_por','c','source_event','pkg')), _nextmon(600));

INSERT INTO _raw VALUES ('4', 'global_estricto todas libres -> ok:true global_real, 2 overrides globales',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(630)::text,'hora_checkout','16:00',
    'alcance','global_estricto','motivo','m','creado_por','c','source_event','pkg')), _nextmon(630));

INSERT INTO _raw VALUES ('5', 'global_estricto con 1 comprometida -> ok:false override_pisa_reserva, NO deja globales',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(660)::text,'hora_checkout','16:00',
    'alcance','global_estricto','motivo','m','creado_por','c','source_event','pkg')), _nextmon(660));

INSERT INTO _raw VALUES ('6', 'todas_posibles con 1 comprometida -> ok:true, resto per-cabana, excluye 1, NO global',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(690)::text,'hora_checkout','16:00',
    'alcance','todas_posibles','motivo','m','creado_por','c','source_event','pkg')), _nextmon(690));

INSERT INTO _raw VALUES ('7', 'todas_posibles todas comprometidas -> ok:false sin_cabanas_aplicables, NO deja overrides',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(720)::text,'hora_checkout','16:00',
    'alcance','todas_posibles','motivo','m','creado_por','c','source_event','pkg')), _nextmon(720));

INSERT INTO _raw VALUES ('8', 'grupo_estricto con 1 conflictiva -> ok:false override_pisa_reserva, NO deja nada del grupo',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(750)::text,'hora_checkout','16:00',
    'alcance','grupo_estricto','ids_cabanas',jsonb_build_array(1,2,3),'motivo','m','creado_por','c','source_event','pkg')), _nextmon(750));

INSERT INTO _raw VALUES ('9', 'grupo_posibles mismo grupo -> ok:true, aplica libres, excluye la conflictiva',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(780)::text,'hora_checkout','16:00',
    'alcance','grupo_posibles','ids_cabanas',jsonb_build_array(1,2,3),'motivo','m','creado_por','c','source_event','pkg')), _nextmon(780));

INSERT INTO _raw VALUES ('10', 'ids_cabanas con id inexistente -> ok:false ids_cabanas_invalidos',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(810)::text,'hora_checkout','16:00',
    'alcance','grupo_estricto','ids_cabanas',jsonb_build_array(1,999999),'motivo','m','creado_por','c','source_event','pkg')), _nextmon(810));

INSERT INTO _raw VALUES ('11', 'fecha_hasta NULL solo afecta fecha (comprometido en +5 no bloquea) -> ok:true',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(840)::text,'hora_checkout','16:00',
    'alcance','cabana','id_cabana',_cab(),'motivo','m','creado_por','c','source_event','pkg')), _nextmon(840));

INSERT INTO _raw VALUES ('12', 'source_event trazable en checkout/checkin (hijos deterministas)',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(870)::text,'hora_checkout','16:00',
    'alcance','cabana','id_cabana',_cab(),'motivo','m','creado_por','c','source_event','pkg')), _nextmon(870));

INSERT INTO _raw VALUES ('14', 'global_estricto sombreado por especifico (efecto) -> ok:false paquete_no_aplicado_efectivamente, NO globales',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(930)::text,'hora_checkout','16:00',
    'alcance','global_estricto','motivo','m','creado_por','c','source_event','pkg')), _nextmon(930));

INSERT INTO _raw VALUES ('15', 'todas_posibles con cabana sombreada por especifico de mayor precedencia -> excluye esa, aplica resto, NO global',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(960)::text,'hora_checkout','16:00',
    'alcance','todas_posibles','motivo','m','creado_por','c','source_event','pkg')), _nextmon(960));

INSERT INTO _raw VALUES ('16', 'cabana sombreada por especifico de mayor precedencia -> ok:false paquete_no_aplicado_efectivamente, NO mitades',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(990)::text,'hora_checkout','16:00',
    'alcance','cabana','id_cabana',1,'motivo','m','creado_por','c','source_event','pkg')), _nextmon(990));

INSERT INTO _raw VALUES ('17', 'control positivo: sin sombra (seed global menor precedencia) el paquete queda efectivo -> ok:true',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1020)::text,'hora_checkout','16:00',
    'alcance','cabana','id_cabana',1,'motivo','m','creado_por','c','source_event','pkg')), _nextmon(1020));

INSERT INTO _raw VALUES ('18', 'ids_cabanas con duplicados [1,1,2] -> ok:false ids_cabanas_invalidos',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1050)::text,'hora_checkout','16:00',
    'alcance','grupo_estricto','ids_cabanas',jsonb_build_array(1,1,2),'motivo','m','creado_por','c','source_event','pkg')), _nextmon(1050));

-- 19: clave ausente (jsonb_build_object SIN 'ids_cabanas')
INSERT INTO _raw VALUES ('19', 'grupo_estricto SIN ids_cabanas -> ok:false payload_invalido (no error inesperado)',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1080)::text,'hora_checkout','16:00',
    'alcance','grupo_estricto','motivo','m','creado_por','c','source_event','pkg')), _nextmon(1080));

-- 20: JSON null
INSERT INTO _raw VALUES ('20', 'grupo_posibles con ids_cabanas null -> ok:false payload_invalido',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1110)::text,'hora_checkout','16:00',
    'alcance','grupo_posibles','ids_cabanas','null'::jsonb,'motivo','m','creado_por','c','source_event','pkg')), _nextmon(1110));

-- 21: escalar no-array (string) -> el que arriesgaba error en jsonb_array_length
INSERT INTO _raw VALUES ('21', 'grupo_estricto con ids_cabanas string -> ok:false payload_invalido',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1140)::text,'hora_checkout','16:00',
    'alcance','grupo_estricto','ids_cabanas',to_jsonb('no_soy_array'::text),'motivo','m','creado_por','c','source_event','pkg')), _nextmon(1140));

-- 22: array vacio
INSERT INTO _raw VALUES ('22', 'grupo_estricto con ids_cabanas [] -> ok:false payload_invalido',
  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1170)::text,'hora_checkout','16:00',
    'alcance','grupo_estricto','ids_cabanas','[]'::jsonb,'motivo','m','creado_por','c','source_event','pkg')), _nextmon(1170));

-- ===================== FASE 2: verdict por caso (statements separados) =====================
INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool AND jsonb_array_length(got->'overrides_creados')=1
            AND EXISTS(SELECT 1 FROM overrides_operativos WHERE id_override=(got->'overrides_creados'->0->>'id_override_checkout')::bigint AND tipo_override='hora_checkout')
            AND EXISTS(SELECT 1 FROM overrides_operativos WHERE id_override=(got->'overrides_creados'->0->>'id_override_checkin')::bigint  AND tipo_override='hora_checkin')
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='1';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='payload_invalido'
            AND NOT EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor)
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='2';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='override_pisa_reserva'
            AND NOT EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor)
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='3';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool AND got->>'modo_aplicacion_real'='global_real'
            AND EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor AND id_cabana IS NULL AND tipo_override='hora_checkout')
            AND EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor AND id_cabana IS NULL AND tipo_override='hora_checkin')
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='4';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='override_pisa_reserva'
            AND NOT EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor AND id_cabana IS NULL)
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='5';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool AND got->>'modo_aplicacion_real'='expandido_por_cabana'
            AND jsonb_array_length(got->'cabanas_excluidas')=1
            AND jsonb_array_length(got->'cabanas_aplicadas') = (SELECT count(*)::int FROM cabanas WHERE activa)-1
            AND NOT EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor AND id_cabana IS NULL)
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='6';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='sin_cabanas_aplicables'
            AND NOT EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor)
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='7';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='override_pisa_reserva'
            AND NOT EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor)
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='8';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool AND jsonb_array_length(got->'cabanas_aplicadas')=2 AND jsonb_array_length(got->'cabanas_excluidas')=1
            AND (got->'cabanas_excluidas'->0->>'id_cabana')='2'
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='9';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='ids_cabanas_invalidos'
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='10';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool
            AND EXISTS(SELECT 1 FROM overrides_operativos WHERE id_override=(got->'overrides_creados'->0->>'id_override_checkout')::bigint)
            AND EXISTS(SELECT 1 FROM overrides_operativos WHERE id_override=(got->'overrides_creados'->0->>'id_override_checkin')::bigint)
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='11';

INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool
            AND EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor AND tipo_override='hora_checkout'
                       AND source_event = 'pkg:checkout:'||(got->'cabanas_aplicadas'->>0))
            AND EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor AND tipo_override='hora_checkin'
                       AND source_event = 'pkg:checkin:'||(got->'cabanas_aplicadas'->>0))
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='12';

-- 14: global_estricto sombreado por especifico -> efecto no se cumple -> ok:false, sin globales
INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='paquete_no_aplicado_efectivamente'
            AND NOT EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor AND id_cabana IS NULL)
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='14';

-- 15: todas_posibles con cabana 1 sombreada (futuro) -> excluida con ese error, resto aplicado, sin global
INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool AND got->>'modo_aplicacion_real'='expandido_por_cabana'
            AND jsonb_array_length(got->'cabanas_excluidas')=1
            AND (got->'cabanas_excluidas'->0->>'id_cabana')='1'
            AND (got->'cabanas_excluidas'->0->>'error')='paquete_no_aplicado_efectivamente'
            AND jsonb_array_length(got->'cabanas_aplicadas') = (SELECT count(*)::int FROM cabanas WHERE activa)-1
            AND NOT EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor AND id_cabana IS NULL)
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='15';

-- 16: cabana sombreada (futuro) -> ok:false, sin mitades del paquete
INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='paquete_no_aplicado_efectivamente'
            AND NOT EXISTS(SELECT 1 FROM overrides_operativos WHERE fecha_desde=anchor AND source_event LIKE 'pkg%')
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='16';

-- 17: control positivo -> paquete efectivo (ok:true implica efecto cumplido); mitades presentes
INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool AND jsonb_array_length(got->'overrides_creados')=1
            AND EXISTS(SELECT 1 FROM overrides_operativos WHERE id_override=(got->'overrides_creados'->0->>'id_override_checkout')::bigint)
            AND EXISTS(SELECT 1 FROM overrides_operativos WHERE id_override=(got->'overrides_creados'->0->>'id_override_checkin')::bigint)
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='17';

-- 18: ids duplicados -> ids_cabanas_invalidos
INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='ids_cabanas_invalidos'
       THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='18';

-- 19-22: ids_cabanas mal formado (ausente / null / escalar / vacio) -> payload_invalido, sin error inesperado
INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='payload_invalido' THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='19';
INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='payload_invalido' THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='20';
INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='payload_invalido' THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='21';
INSERT INTO _res SELECT orden, test, got::text,
  CASE WHEN (got->>'ok')::bool=false AND got->>'error'='payload_invalido' THEN 'PASS' ELSE 'FAIL' END FROM _raw WHERE orden='22';

-- ===================== COMPUERTA (antes del ROLLBACK) =====================
DO $assert$
DECLARE v_pass int; v_fail int; v_total int; v_fails text;
BEGIN
  SELECT count(*) FILTER (WHERE verdict='PASS'), count(*) FILTER (WHERE verdict='FAIL'), count(*)
    INTO v_pass, v_fail, v_total FROM _res;
  SELECT string_agg(format('#%s [%s] got=%s', orden, test, got), ' || ' ORDER BY (orden)::int)
    INTO v_fails FROM _res WHERE verdict <> 'PASS';
  IF v_fail > 0 OR v_total <> 22 THEN
    RAISE EXCEPTION 'SMOKE S3 FALLA: pass=% (esp 22) fail=% (esp 0) total=% (esp 22). No-PASS: %',
      v_pass, v_fail, v_total, COALESCE(v_fails, '(ninguno; revisar conteo)');
  END IF;
  RAISE NOTICE 'SMOKE S3 OK: 22/22 PASS, 0 FAIL. (la tx se revierte a continuacion)';
END
$assert$;

ROLLBACK;

-- ---- VEREDICTO + POSTCHECK (unico SELECT visible, tras el ROLLBACK) ----
SELECT
  'SMOKE S3 VALIDADO: compuerta 22/22 PASS, 0 FAIL; efecto pretendido verificado (global_estricto no queda si un especifico lo sombrea; todas_posibles excluye la cabana sombreada; cabana estricta falla si no gana; control positivo pasa); ids_cabanas mal formado (ausente/null/escalar/vacio) -> payload_invalido sin error; sin mitades ante ok:false; gap<120 y duplicados -> invalido; trigger S1 activo; seeds revertidos.' AS veredicto,
  (SELECT count(*) FROM overrides_operativos WHERE source_event LIKE 'pkg%' OR source_event IN ('smoke_s3','seed_s3')) AS overrides_residual,
  (SELECT count(*) FROM reservas            WHERE source_event='smoke_s3') AS reservas_residual,
  (SELECT count(*) FROM pre_reservas        WHERE source_event='smoke_s3') AS prereservas_residual,
  (SELECT count(*) FROM huespedes           WHERE nombre='Smoke S3')       AS huespedes_residual;
