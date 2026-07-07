-- =====================================================================
-- B1.1 - Motor de Horarios / Carril B1 (vigencias de horario base)
-- Artefacto 4/5: SMOKES (matriz completa)
-- -----------------------------------------------------------------------
-- ORDEN: DESPUES de 1/5, 2/5, 3/5 (tabla + helper + funcion + trigger).
-- DISENO: todo dentro de subtransacciones (BEGIN..EXCEPTION) que se revierten;
--   las escrituras a tablas reales NO persisten. Los fixtures (huespedes,
--   reservas, overrides) usan esquema COMPLETO (todas las NOT NULL de TEST) y
--   se CREAN dentro del smoke (huesped controlado; sin depender de datos
--   preexistentes; sin SKIP: G1 siempre se testea).
-- SECUENCIAS: se snapshotean/restauran TODAS las que el smoke consume
--   (vigencias, reservas, huespedes, overrides) via pg_get_serial_sequence +
--   setval (no-transaccional), y se reportan una por una en META-B.
-- VEREDICTO TRI-PARTE (separado al final):
--   (A) filas residuales (vigencias=0) + reservas/pre_reservas/huespedes/overrides sin cambios;
--   (B) por secuencia: pre / post / restaurada (restaurada IS NOT DISTINCT FROM pre);
--   (C) fingerprints resolver + ODR intactos (pre == post).
-- FAIL-CLOSED: el grupo G1-RES induce resolver_horario.ok=false (override malo)
--   y verifica que el helper marque resolver_horario_invalido (nunca fail-open).
-- REGLA: cada barrera manual viola EXACTAMENTE UN constraint (resto valido).
-- ALCANCE: TEST-only. No toca resolver_horario, OPS, portal-api, frontend,
--   n8n, Vercel, canonico ni configuracion_general.
-- =====================================================================

SET client_min_messages = warning;

DROP TABLE IF EXISTS _smoke_res;
CREATE TEMP TABLE _smoke_res(
  id SERIAL, grupo TEXT, caso TEXT, esperado TEXT, obtenido TEXT, ok BOOLEAN
);

-- Secuencias que el smoke consume (nombre logico + secuencia resuelta)
DROP TABLE IF EXISTS _seqs;
CREATE TEMP TABLE _seqs(nombre TEXT, seqname TEXT, pre BIGINT);
INSERT INTO _seqs(nombre, seqname) VALUES
  ('vigencias', pg_get_serial_sequence('public.vigencias_horario_base','id_vigencia')),
  ('reservas',  pg_get_serial_sequence('public.reservas','id_reserva')),
  ('huespedes', pg_get_serial_sequence('public.huespedes','id_huesped')),
  ('overrides', pg_get_serial_sequence('public.overrides_operativos','id_override'));

CREATE OR REPLACE FUNCTION pg_temp.rec(p_grupo TEXT, p_caso TEXT, p_esperado TEXT, p_obtenido TEXT)
RETURNS void LANGUAGE plpgsql AS $r$
BEGIN
  INSERT INTO _smoke_res(grupo, caso, esperado, obtenido, ok)
  VALUES (p_grupo, p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
END $r$;

DO $smoke$
DECLARE
  v_hid       BIGINT;
  v_h         DATE := CURRENT_DATE + 30;   -- happy + barreras CHECK/EXCLUDE
  v_g         DATE := CURRENT_DATE + 60;   -- G1 via funcion (no-domingo)
  v_t         DATE := CURRENT_DATE + 80;   -- G1 via trigger (no-domingo)
  v_r         DATE := CURRENT_DATE + 90;   -- G1 resolver invalido (no-domingo)
  v_i         DATE := CURRENT_DATE + 100;  -- aislamiento (no-domingo)
  v_res       jsonb;
  v_cnt       BIGINT;
  v_state     TEXT;
  v_cname     TEXT;
  v_resolver  jsonb;
  v_ci_res    TEXT;
  v_origen    TEXT;
  rec_seq     RECORD;
  v_post      BIGINT;
  v_restored  BIGINT;
  -- meta
  v_res_fp_pre  TEXT;  v_res_fp_post TEXT;
  v_odr_fp_pre  TEXT;  v_odr_fp_post TEXT;
  v_resv_pre    BIGINT; v_resv_post BIGINT;
  v_prer_pre    BIGINT; v_prer_post BIGINT;
  v_hues_pre    BIGINT; v_hues_post BIGINT;
  v_ovr_pre     BIGINT; v_ovr_post  BIGINT;
  v_residual    BIGINT;
BEGIN
  -- ---- capturas PRE ----
  UPDATE _seqs SET pre = pg_sequence_last_value(seqname::regclass);
  v_res_fp_pre := md5(pg_get_functiondef('resolver_horario(bigint,date)'::regprocedure));
  v_odr_fp_pre := md5(pg_get_functiondef('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  SELECT count(*) INTO v_resv_pre FROM reservas;
  SELECT count(*) INTO v_prer_pre FROM pre_reservas;
  SELECT count(*) INTO v_hues_pre FROM huespedes;
  SELECT count(*) INTO v_ovr_pre  FROM overrides_operativos;
  IF EXTRACT(DOW FROM v_g) = 0 THEN v_g := v_g + 1; END IF;
  IF EXTRACT(DOW FROM v_t) = 0 THEN v_t := v_t + 1; END IF;
  IF EXTRACT(DOW FROM v_r) = 0 THEN v_r := v_r + 1; END IF;
  IF EXTRACT(DOW FROM v_i) = 0 THEN v_i := v_i + 1; END IF;

  -- =================================================================
  -- GRUPO HAPPY (funcion; consume secuencia vigencias; revertido por subtx)
  -- =================================================================
  BEGIN
    v_res := public.crear_vigencia_horario(jsonb_build_object(
      'fecha_desde', (v_h)::text, 'fecha_hasta', (v_h + 10)::text,
      'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
      'hora_checkout_default','10:00','hora_checkout_domingo','16:00',
      'motivo','smoke happy cerrada','creado_por','smoke'));
    SELECT count(*) INTO v_cnt FROM public.vigencias_horario_base
      WHERE id_vigencia = (v_res->>'id_vigencia')::bigint;
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '__RB__' THEN v_res := jsonb_build_object('ok',false,'error','EXC:'||SQLERRM); v_cnt := -1; END IF;
  END;
  PERFORM pg_temp.rec('HAPPY','alta valida cerrada','ok:true+fila',
    CASE WHEN (v_res->>'ok')::bool AND v_cnt=1 THEN 'ok:true+fila' ELSE 'FALLO:'||coalesce(v_res->>'error','?')||' cnt='||v_cnt END);

  BEGIN
    v_res := public.crear_vigencia_horario(jsonb_build_object(
      'fecha_desde', (v_h)::text, 'abierta', true,
      'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
      'hora_checkout_default','10:00','hora_checkout_domingo','16:00',
      'motivo','smoke happy abierta','creado_por','smoke'));
    SELECT count(*) INTO v_cnt FROM public.vigencias_horario_base
      WHERE id_vigencia = (v_res->>'id_vigencia')::bigint AND abierta;
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '__RB__' THEN v_res := jsonb_build_object('ok',false,'error','EXC:'||SQLERRM); v_cnt := -1; END IF;
  END;
  PERFORM pg_temp.rec('HAPPY','alta valida abierta','ok:true+fila',
    CASE WHEN (v_res->>'ok')::bool AND v_cnt=1 THEN 'ok:true+fila' ELSE 'FALLO:'||coalesce(v_res->>'error','?')||' cnt='||v_cnt END);

  -- =================================================================
  -- GRUPO FUNCION-NEGATIVAS (NO consumen secuencia: retorna pre-INSERT)
  -- =================================================================
  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde',(v_h)::text,'fecha_hasta',(v_h+10)::text,
    'hora_checkin_default','11:00','hora_checkin_domingo','18:00',
    'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','m','creado_por','c'));
  PERFORM pg_temp.rec('FN-NEG','G2 gap default <2h','gap_insuficiente', v_res->>'error');

  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde',(v_h)::text,'fecha_hasta',(v_h+10)::text,
    'hora_checkin_default','23:00','hora_checkin_domingo','18:00',
    'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','m','creado_por','c'));
  PERFORM pg_temp.rec('FN-NEG','ventana checkin 23:00','hora_fuera_de_ventana', v_res->>'error');

  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde',(v_h)::text,'fecha_hasta',(v_h+10)::text,'abierta',true,
    'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
    'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','m','creado_por','c'));
  PERFORM pg_temp.rec('FN-NEG','abierta=true con fecha_hasta','abierta_inconsistente', v_res->>'error');

  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde',(v_h)::text,
    'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
    'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','m','creado_por','c'));
  PERFORM pg_temp.rec('FN-NEG','abierta=false sin fecha_hasta','abierta_inconsistente', v_res->>'error');

  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde',(v_h)::text,'fecha_hasta',(v_h-5)::text,
    'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
    'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','m','creado_por','c'));
  PERFORM pg_temp.rec('FN-NEG','fecha_hasta < fecha_desde','fechas_invalidas', v_res->>'error');

  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde',(CURRENT_DATE-5)::text,'fecha_hasta',(CURRENT_DATE+10)::text,
    'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
    'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','m','creado_por','c'));
  PERFORM pg_temp.rec('FN-NEG','fecha_desde pasada','fechas_invalidas', v_res->>'error');

  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde',(v_h)::text,'fecha_hasta',(v_h+10)::text,
    'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
    'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','   ','creado_por','c'));
  PERFORM pg_temp.rec('FN-NEG','motivo en blanco','payload_invalido', v_res->>'error');

  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde',(v_h)::text,'fecha_hasta',(v_h+10)::text,
    'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
    'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','m','creado_por',''));
  PERFORM pg_temp.rec('FN-NEG','creado_por en blanco','payload_invalido', v_res->>'error');

  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde',(v_h)::text,'fecha_hasta',(v_h+10)::text,'activo',true,
    'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
    'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','m','creado_por','c'));
  PERFORM pg_temp.rec('FN-NEG','clave prohibida activo','payload_invalido', v_res->>'error');

  -- Formato de hora invalido (regex estricto HH:MM[:SS])
  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde',(v_h)::text,'fecha_hasta',(v_h+10)::text,
    'hora_checkin_default','13:005','hora_checkin_domingo','18:00',
    'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','m','creado_por','c'));
  PERFORM pg_temp.rec('FN-NEG','hora formato 13:005 (regex)','payload_invalido', v_res->>'error');

  -- =================================================================
  -- GRUPO SOLAPAMIENTO (funcion; v1 valida + v2 solapa; ambas revertidas)
  -- =================================================================
  BEGIN
    v_res := public.crear_vigencia_horario(jsonb_build_object(
      'fecha_desde',(v_h)::text,'fecha_hasta',(v_h+10)::text,
      'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
      'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','v1','creado_por','smoke'));
    v_res := public.crear_vigencia_horario(jsonb_build_object(
      'fecha_desde',(v_h+5)::text,'fecha_hasta',(v_h+15)::text,
      'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
      'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','v2 solapa','creado_por','smoke'));
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '__RB__' THEN v_res := jsonb_build_object('ok',false,'error','EXC:'||SQLERRM); END IF;
  END;
  PERFORM pg_temp.rec('SOLAPA','v2 solapa v1 activa','vigencia_solapada', v_res->>'error');

  -- =================================================================
  -- GRUPO G1 via funcion (fixture huesped+reserva; funcion retorna pre-INSERT)
  -- =================================================================
  BEGIN
    INSERT INTO huespedes(nombre, telefono) VALUES ('Smoke G1 fixture','+549990000001') RETURNING id_huesped INTO v_hid;
    INSERT INTO reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,
                         personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (1, v_hid, v_g-2, v_g, '13:00','21:00', 2,'confirmada','manual',100000,50000,50000,'smoke');
    v_res := public.crear_vigencia_horario(jsonb_build_object(
      'fecha_desde',(v_g-5)::text,'fecha_hasta',(v_g+5)::text,
      'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
      'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','pisa','creado_por','smoke'));
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '__RB__' THEN v_res := jsonb_build_object('ok',false,'error','EXC:'||SQLERRM); END IF;
  END;
  PERFORM pg_temp.rec('G1-FN','base 13:00 pisa checkout 21:00','base_pisa_comprometido', v_res->>'error');

  -- =================================================================
  -- GRUPO G1-RES fail-closed: resolver.ok=false (override malo) => resolver_horario_invalido
  -- =================================================================
  BEGIN
    INSERT INTO huespedes(nombre, telefono) VALUES ('Smoke G1 res','+549990000002') RETURNING id_huesped INTO v_hid;
    -- override con hora invalida para cabana 1 en v_r => resolver_horario(1,v_r).ok=false
    INSERT INTO overrides_operativos(fecha_desde,fecha_hasta,id_cabana,tipo_override,valor,motivo,creado_por)
      VALUES (v_r, v_r, 1, 'hora_checkin', '99:99', 'smoke resolver invalido','smoke');
    INSERT INTO reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,
                         personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (1, v_hid, v_r-2, v_r, '13:00','10:00', 2,'confirmada','manual',100000,50000,50000,'smoke');
    v_res := public.crear_vigencia_horario(jsonb_build_object(
      'fecha_desde',(v_r-5)::text,'fecha_hasta',(v_r+5)::text,
      'hora_checkin_default','13:00','hora_checkin_domingo','18:00',
      'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','res','creado_por','smoke'));
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '__RB__' THEN v_res := jsonb_build_object('ok',false,'error','EXC:'||SQLERRM); END IF;
  END;
  PERFORM pg_temp.rec('G1-RES','resolver ok=false => fail-closed','resolver_horario_invalido', v_res->>'error');

  -- =================================================================
  -- GRUPO BARRERAS MANUALES (raw INSERT; una defensa por caso)
  -- Consumen nextval de vigencias (default id antes del check) => restaurado.
  -- =================================================================
  BEGIN
    INSERT INTO public.vigencias_horario_base
      (fecha_desde,fecha_hasta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por)
      VALUES (v_h, v_h+10, '11:00','18:00','10:00','16:00','m','c');
    v_state := 'NO_RECHAZO'; RAISE EXCEPTION '__RB__';
  EXCEPTION
    WHEN check_violation THEN GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_state := v_cname;
    WHEN OTHERS THEN IF SQLERRM='__RB__' THEN NULL; ELSE v_state := 'OTRO:'||SQLERRM; END IF;
  END;
  PERFORM pg_temp.rec('BARRERA','CHECK gap','chk_vigencias_gap', v_state);

  BEGIN
    INSERT INTO public.vigencias_horario_base
      (fecha_desde,fecha_hasta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por)
      VALUES (v_h, v_h+10, '23:00','18:00','10:00','16:00','m','c');
    v_state := 'NO_RECHAZO'; RAISE EXCEPTION '__RB__';
  EXCEPTION
    WHEN check_violation THEN GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_state := v_cname;
    WHEN OTHERS THEN IF SQLERRM='__RB__' THEN NULL; ELSE v_state := 'OTRO:'||SQLERRM; END IF;
  END;
  PERFORM pg_temp.rec('BARRERA','CHECK ventana','chk_vigencias_ventana', v_state);

  BEGIN
    INSERT INTO public.vigencias_horario_base
      (fecha_desde,fecha_hasta,abierta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por)
      VALUES (v_h, v_h+10, true, '13:00','18:00','10:00','16:00','m','c');
    v_state := 'NO_RECHAZO'; RAISE EXCEPTION '__RB__';
  EXCEPTION
    WHEN check_violation THEN GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_state := v_cname;
    WHEN OTHERS THEN IF SQLERRM='__RB__' THEN NULL; ELSE v_state := 'OTRO:'||SQLERRM; END IF;
  END;
  PERFORM pg_temp.rec('BARRERA','CHECK abierta','chk_vigencias_abierta', v_state);

  BEGIN
    INSERT INTO public.vigencias_horario_base
      (fecha_desde,fecha_hasta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por)
      VALUES (v_h, v_h+10, '13:00','18:00','10:00','16:00','', 'c');
    v_state := 'NO_RECHAZO'; RAISE EXCEPTION '__RB__';
  EXCEPTION
    WHEN check_violation THEN GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_state := v_cname;
    WHEN OTHERS THEN IF SQLERRM='__RB__' THEN NULL; ELSE v_state := 'OTRO:'||SQLERRM; END IF;
  END;
  PERFORM pg_temp.rec('BARRERA','CHECK motivo blanco','chk_vigencias_motivo', v_state);

  BEGIN
    INSERT INTO public.vigencias_horario_base
      (fecha_desde,fecha_hasta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por)
      VALUES (v_h, v_h+10, '13:00','18:00','10:00','16:00','m','');
    v_state := 'NO_RECHAZO'; RAISE EXCEPTION '__RB__';
  EXCEPTION
    WHEN check_violation THEN GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_state := v_cname;
    WHEN OTHERS THEN IF SQLERRM='__RB__' THEN NULL; ELSE v_state := 'OTRO:'||SQLERRM; END IF;
  END;
  PERFORM pg_temp.rec('BARRERA','CHECK creado_por blanco','chk_vigencias_creado_por', v_state);

  BEGIN
    INSERT INTO public.vigencias_horario_base
      (fecha_desde,fecha_hasta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por,source_event)
      VALUES (v_h, v_h+10, '13:00','18:00','10:00','16:00','m','c','');
    v_state := 'NO_RECHAZO'; RAISE EXCEPTION '__RB__';
  EXCEPTION
    WHEN check_violation THEN GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_state := v_cname;
    WHEN OTHERS THEN IF SQLERRM='__RB__' THEN NULL; ELSE v_state := 'OTRO:'||SQLERRM; END IF;
  END;
  PERFORM pg_temp.rec('BARRERA','CHECK source_event blanco','chk_vigencias_source_event', v_state);

  BEGIN
    INSERT INTO public.vigencias_horario_base
      (fecha_desde,fecha_hasta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por)
      VALUES (v_h, v_h+10, NULL,'18:00','10:00','16:00','m','c');
    v_state := 'NO_RECHAZO'; RAISE EXCEPTION '__RB__';
  EXCEPTION
    WHEN not_null_violation THEN GET STACKED DIAGNOSTICS v_cname = COLUMN_NAME; v_state := 'NOTNULL:'||v_cname;
    WHEN OTHERS THEN IF SQLERRM='__RB__' THEN NULL; ELSE v_state := 'OTRO:'||SQLERRM; END IF;
  END;
  PERFORM pg_temp.rec('BARRERA','NOT NULL hora_checkin_default','NOTNULL:hora_checkin_default', v_state);

  BEGIN
    INSERT INTO public.vigencias_horario_base
      (fecha_desde,fecha_hasta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por)
      VALUES (v_h, v_h+10, '13:00','18:00','10:00','16:00','v1','c');
    INSERT INTO public.vigencias_horario_base
      (fecha_desde,fecha_hasta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por)
      VALUES (v_h+5, v_h+15, '13:00','18:00','10:00','16:00','v2','c');
    v_state := 'NO_RECHAZO'; RAISE EXCEPTION '__RB__';
  EXCEPTION
    WHEN exclusion_violation THEN GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_state := v_cname;
    WHEN OTHERS THEN IF SQLERRM='__RB__' THEN NULL; ELSE v_state := 'OTRO:'||SQLERRM; END IF;
  END;
  PERFORM pg_temp.rec('BARRERA','EXCLUDE overlap','exc_vigencias_no_overlap', v_state);

  BEGIN
    SET CONSTRAINTS trg_vig_guard IMMEDIATE;
    INSERT INTO huespedes(nombre, telefono) VALUES ('Smoke G1 trg','+549990000003') RETURNING id_huesped INTO v_hid;
    INSERT INTO reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,
                         personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (1, v_hid, v_t-2, v_t, '13:00','21:00', 2,'confirmada','manual',100000,50000,50000,'smoke');
    INSERT INTO public.vigencias_horario_base
      (fecha_desde,fecha_hasta,hora_checkin_default,hora_checkin_domingo,hora_checkout_default,hora_checkout_domingo,motivo,creado_por)
      VALUES (v_t-5, v_t+5, '13:00','18:00','10:00','16:00','pisa','c');
    v_state := 'NO_RECHAZO'; RAISE EXCEPTION '__RB__';
  EXCEPTION
    WHEN SQLSTATE '45000' THEN v_state := '45000';
    WHEN OTHERS THEN IF SQLERRM='__RB__' THEN NULL; ELSE v_state := 'OTRO:'||SQLSTATE; END IF;
  END;
  PERFORM pg_temp.rec('BARRERA','TRIGGER g1 (45000)','45000', v_state);
  SET CONSTRAINTS trg_vig_guard DEFERRED;  -- reset defensivo

  -- =================================================================
  -- GRUPO AISLAMIENTO B1.1<->B1.2 (el resolver NO lee la tabla)
  -- =================================================================
  BEGIN
    v_res := public.crear_vigencia_horario(jsonb_build_object(
      'fecha_desde',(v_i-3)::text,'fecha_hasta',(v_i+3)::text,
      'hora_checkin_default','15:00','hora_checkin_domingo','18:00',
      'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','aislamiento','creado_por','smoke'));
    SELECT resolver_horario(1, v_i) INTO v_resolver;
    v_ci_res := v_resolver->>'hora_checkin';
    v_origen := v_resolver->>'origen_checkin';
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '__RB__' THEN v_ci_res := 'EXC:'||SQLERRM; v_origen := '?'; END IF;
  END;
  PERFORM pg_temp.rec('AISLA','resolver ignora vigencia (13:00/base)','13:00:00|base',
    coalesce(v_ci_res,'?')||'|'||coalesce(v_origen,'?'));

  -- =================================================================
  -- GRUPO HARDENING (grants 0 a los 4 roles; read-only)
  -- =================================================================
  WITH roles(r) AS (VALUES ('anon'),('authenticated'),('service_role'),('public')),
  p AS (
    SELECT
      -- tabla: cualquier privilegio util PARCIAL (no una combinacion agregada)
      bool_or(has_table_privilege(r,'public.vigencias_horario_base','SELECT')
           OR has_table_privilege(r,'public.vigencias_horario_base','INSERT')
           OR has_table_privilege(r,'public.vigencias_horario_base','UPDATE')
           OR has_table_privilege(r,'public.vigencias_horario_base','DELETE')) AS c_tab,
      -- secuencia: USAGE OR SELECT OR UPDATE (privilegio por privilegio)
      bool_or(has_sequence_privilege(r, pg_get_serial_sequence('public.vigencias_horario_base','id_vigencia'), 'USAGE')
           OR has_sequence_privilege(r, pg_get_serial_sequence('public.vigencias_horario_base','id_vigencia'), 'SELECT')
           OR has_sequence_privilege(r, pg_get_serial_sequence('public.vigencias_horario_base','id_vigencia'), 'UPDATE')) AS c_seq,
      bool_or(has_function_privilege(r,'public.crear_vigencia_horario(jsonb)','EXECUTE')) AS c_fn,
      bool_or(has_function_privilege(r,'public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)','EXECUTE')) AS c_hlp,
      bool_or(has_function_privilege(r,'public.trg_guard_vigencias()','EXECUTE')) AS c_trg
    FROM roles
  )
  SELECT CASE WHEN NOT (c_tab OR c_seq OR c_fn OR c_hlp OR c_trg) THEN 'grants=0' ELSE 'HAY_GRANTS' END
  INTO v_state FROM p;
  PERFORM pg_temp.rec('HARDEN','0 grants tabla/seq/fn/helper/trigger a 4 roles','grants=0', v_state);

  -- ---- restauracion de secuencias (setval no-transaccional) + META-B ----
  FOR rec_seq IN SELECT nombre, seqname, pre FROM _seqs ORDER BY nombre LOOP
    v_post := pg_sequence_last_value(rec_seq.seqname::regclass);
    IF rec_seq.pre IS NULL THEN PERFORM setval(rec_seq.seqname::regclass, 1, false);
    ELSE PERFORM setval(rec_seq.seqname::regclass, rec_seq.pre, true); END IF;
    v_restored := pg_sequence_last_value(rec_seq.seqname::regclass);
    PERFORM pg_temp.rec('META-B',
      'secuencia '||rec_seq.nombre||' pre='||coalesce(rec_seq.pre::text,'NULL')||' post='||coalesce(v_post::text,'NULL')||' restaurada='||coalesce(v_restored::text,'NULL'),
      coalesce(rec_seq.pre::text,'NULL'), coalesce(v_restored::text,'NULL'));
  END LOOP;

  -- ---- capturas POST ----
  v_res_fp_post := md5(pg_get_functiondef('resolver_horario(bigint,date)'::regprocedure));
  v_odr_fp_post := md5(pg_get_functiondef('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  SELECT count(*) INTO v_residual FROM public.vigencias_horario_base;
  SELECT count(*) INTO v_resv_post FROM reservas;
  SELECT count(*) INTO v_prer_post FROM pre_reservas;
  SELECT count(*) INTO v_hues_post FROM huespedes;
  SELECT count(*) INTO v_ovr_post  FROM overrides_operativos;

  -- ---- (A) residual + tablas reales sin cambios ----
  PERFORM pg_temp.rec('META-A','filas residuales en vigencias','0', v_residual::text);
  PERFORM pg_temp.rec('META-A','reservas sin cambios (fixtures revertidos)', v_resv_pre::text, v_resv_post::text);
  PERFORM pg_temp.rec('META-A','pre_reservas sin cambios', v_prer_pre::text, v_prer_post::text);
  PERFORM pg_temp.rec('META-A','huespedes sin cambios (fixtures revertidos)', v_hues_pre::text, v_hues_post::text);
  PERFORM pg_temp.rec('META-A','overrides sin cambios (fixture revertido)', v_ovr_pre::text, v_ovr_post::text);
  -- ---- (C) fingerprints ----
  PERFORM pg_temp.rec('META-C','fingerprint resolver intacto', v_res_fp_pre, v_res_fp_post);
  PERFORM pg_temp.rec('META-C','fingerprint ODR intacto', v_odr_fp_pre, v_odr_fp_post);

  -- ---- TOTAL ----
  PERFORM pg_temp.rec('TOTAL','veredicto global',
    'PASS', (SELECT CASE WHEN bool_and(ok) THEN 'PASS' ELSE 'FAIL' END FROM _smoke_res));
END
$smoke$;

-- Resultado consolidado (unico result set; ultima sentencia con resultado)
SELECT lpad(id::text,2,'0') AS n, grupo, caso, esperado, obtenido,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS veredicto
FROM _smoke_res
ORDER BY id;

DROP TABLE IF EXISTS _seqs;
DROP TABLE IF EXISTS _smoke_res;
