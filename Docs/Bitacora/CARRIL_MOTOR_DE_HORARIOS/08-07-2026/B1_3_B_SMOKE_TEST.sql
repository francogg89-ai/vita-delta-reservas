-- =====================================================================
-- B1.3-B - SMOKE del validador validar_gap_bordes_congelados  [POST-B]
-- SEGURIDAD (owner-only) -> FUNCIONAL -> TEARDOWN (residual 0).
-- Fixtures FIELES a la DDL real: cada caso crea un huesped sintetico (telefono
-- unico) e inserta en reservas/pre_reservas con TODOS los NOT NULL reales
-- (id_huesped, personas, canal_origen, montos, source_event, canal_pago, etc.),
-- dentro de una subtransaccion (savepoint) que lo revierte: cero residuo. El
-- validador es read-only. El ULTIMO statement es SELECT * FROM _smoke.
-- Ejecutar el script entero en SQL Editor.
-- =====================================================================

DROP TABLE IF EXISTS pg_temp._smoke;
CREATE TEMP TABLE _smoke(id serial, seccion text, caso text, detalle text, ok boolean) ON COMMIT PRESERVE ROWS;

CREATE OR REPLACE FUNCTION pg_temp.reg(p_sec text, p_caso text, p_det text, p_ok boolean)
RETURNS void LANGUAGE sql AS $$ INSERT INTO _smoke(seccion,caso,detalle,ok) VALUES (p_sec,p_caso,p_det,p_ok); $$;

BEGIN;

DO $g$
BEGIN
  IF to_regprocedure('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)') IS NULL THEN
    RAISE EXCEPTION 'SMOKE B1.3-B: B no aplicado (falta la funcion). Abortando.';
  END IF;
END $g$;

-- =====================================================================
-- SEGURIDAD (cero escrituras)
-- =====================================================================
DO $seg$
DECLARE r text; v_bad int := 0;
BEGIN
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)','EXECUTE') THEN v_bad:=v_bad+1; END IF;
  END LOOP;
  PERFORM pg_temp.reg('SEG','acl_owner_only', format('privilegios_indebidos=%s (esperado 0)', v_bad), v_bad=0);
END $seg$;

-- =====================================================================
-- FUNCIONAL
-- =====================================================================

-- B1: sin vecinos => ok:true.
DO $b1$
DECLARE v_cab bigint; v_res jsonb;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  v_res := public.validar_gap_bordes_congelados(v_cab, CURRENT_DATE+3650, TIME '15:00', CURRENT_DATE+3653, TIME '10:00');
  PERFORM pg_temp.reg('FUN','sin_vecinos', format('ok=%s', v_res->>'ok'), (v_res->>'ok')::boolean IS TRUE);
END $b1$;

-- B2: Caso A conflicto. Vecino reserva SALE base+10 14:00; candidata ENTRA 15:00 (gap 1h).
DO $b2$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+3660;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Smoke B1.3-B','+5491100000002') RETURNING id_huesped INTO v_h;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d,TIME '13:00',TIME '14:00',2,'confirmada','manual',1000,300,700,'smoke_b13b');
    v_res := public.validar_gap_bordes_congelados(v_cab, v_d, TIME '15:00', v_d+3, TIME '10:00');
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','casoA_conflicto', format('error=%s (esperado checkin_pisa_checkout_anterior)', v_res->>'error'),
    (v_res->>'error')='checkin_pisa_checkout_anterior');
END $b2$;

-- B3: Caso A limite OK. Vecino SALE base+10 14:00; candidata ENTRA 16:00 (gap 2h).
DO $b3$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+3660;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Smoke B1.3-B','+5491100000003') RETURNING id_huesped INTO v_h;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d,TIME '13:00',TIME '14:00',2,'confirmada','manual',1000,300,700,'smoke_b13b');
    v_res := public.validar_gap_bordes_congelados(v_cab, v_d, TIME '16:00', v_d+3, TIME '10:00');
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('ok','exc'); END IF; END;
  PERFORM pg_temp.reg('FUN','casoA_limite_2h_ok', format('ok=%s (gap 2h => ok:true)', v_res->>'ok'), (v_res->>'ok')::boolean IS TRUE);
END $b3$;

-- B4: Caso B conflicto. Vecino reserva ENTRA base+20 12:00; candidata SALE 11:00 (gap 1h).
DO $b4$
DECLARE v_cab bigint; v_res jsonb; v_e date; v_h bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_e := CURRENT_DATE+3680;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Smoke B1.3-B','+5491100000004') RETURNING id_huesped INTO v_h;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_h,v_e,v_e+2,TIME '12:00',TIME '10:00',2,'confirmada','manual',1000,300,700,'smoke_b13b');
    v_res := public.validar_gap_bordes_congelados(v_cab, v_e-3, TIME '15:00', v_e, TIME '11:00');
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','casoB_conflicto', format('error=%s (esperado checkout_pisa_checkin_posterior)', v_res->>'error'),
    (v_res->>'error')='checkout_pisa_checkin_posterior');
END $b4$;

-- B5: Caso B limite OK. Vecino ENTRA base+20 12:00; candidata SALE 10:00 (gap 2h).
DO $b5$
DECLARE v_cab bigint; v_res jsonb; v_e date; v_h bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_e := CURRENT_DATE+3680;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Smoke B1.3-B','+5491100000005') RETURNING id_huesped INTO v_h;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_h,v_e,v_e+2,TIME '12:00',TIME '10:00',2,'confirmada','manual',1000,300,700,'smoke_b13b');
    v_res := public.validar_gap_bordes_congelados(v_cab, v_e-3, TIME '15:00', v_e, TIME '10:00');
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('ok','exc'); END IF; END;
  PERFORM pg_temp.reg('FUN','casoB_limite_2h_ok', format('ok=%s (gap 2h => ok:true)', v_res->>'ok'), (v_res->>'ok')::boolean IS TRUE);
END $b5$;

-- B6: pre_reserva VIVA (pendiente_pago vigente) cuenta => conflicto Caso A.
DO $b6$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+3700;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Smoke B1.3-B','+5491100000006') RETURNING id_huesped INTO v_h;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d,TIME '13:00',TIME '14:00',2,1000,300,'pendiente_pago',NOW()+INTERVAL '1 hour','transferencia_bancaria','manual','smoke_b13b');
    v_res := public.validar_gap_bordes_congelados(v_cab, v_d, TIME '15:00', v_d+3, TIME '10:00');
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','prereserva_viva_cuenta', format('error=%s (esperado checkin_pisa_checkout_anterior)', v_res->>'error'),
    (v_res->>'error')='checkin_pisa_checkout_anterior');
END $b6$;

-- B7: pre_reserva EXPIRADA (pendiente_pago, expira pasado) NO cuenta => ok:true.
DO $b7$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+3700;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Smoke B1.3-B','+5491100000007') RETURNING id_huesped INTO v_h;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d,TIME '13:00',TIME '14:00',2,1000,300,'pendiente_pago',NOW()-INTERVAL '1 hour','transferencia_bancaria','manual','smoke_b13b');
    v_res := public.validar_gap_bordes_congelados(v_cab, v_d, TIME '15:00', v_d+3, TIME '10:00');
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('ok','exc'); END IF; END;
  PERFORM pg_temp.reg('FUN','prereserva_expirada_no_cuenta', format('ok=%s (expirada => ok:true)', v_res->>'ok'), (v_res->>'ok')::boolean IS TRUE);
END $b7$;

-- B8: exclusion de reserva. Vecino conflictivo, excluido por p_excluir_reserva => ok:true.
DO $b8$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint; v_id bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+3720;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Smoke B1.3-B','+5491100000008') RETURNING id_huesped INTO v_h;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d,TIME '13:00',TIME '14:00',2,'confirmada','manual',1000,300,700,'smoke_b13b') RETURNING id_reserva INTO v_id;
    v_res := public.validar_gap_bordes_congelados(v_cab, v_d, TIME '15:00', v_d+3, TIME '10:00', v_id, NULL);
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('ok','exc'); END IF; END;
  PERFORM pg_temp.reg('FUN','exclusion_reserva', format('ok=%s (excluida => ok:true)', v_res->>'ok'), (v_res->>'ok')::boolean IS TRUE);
END $b8$;

-- B9: estado NO vivo (reserva cancelada) NO cuenta => ok:true.
DO $b9$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+3740;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Smoke B1.3-B','+5491100000009') RETURNING id_huesped INTO v_h;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d,TIME '13:00',TIME '14:00',2,'cancelada','manual',1000,300,700,'smoke_b13b');
    v_res := public.validar_gap_bordes_congelados(v_cab, v_d, TIME '15:00', v_d+3, TIME '10:00');
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('ok','exc'); END IF; END;
  PERFORM pg_temp.reg('FUN','estado_cancelada_no_cuenta', format('ok=%s (cancelada => ok:true)', v_res->>'ok'), (v_res->>'ok')::boolean IS TRUE);
END $b9$;

-- B10: pre_reserva 'pago_en_revision' cuenta AUNQUE expira_en no sea futuro => conflicto Caso A.
DO $b10$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+3760;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Smoke B1.3-B','+5491100000010') RETURNING id_huesped INTO v_h;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d,TIME '13:00',TIME '14:00',2,1000,300,'pago_en_revision',NOW()-INTERVAL '1 hour','transferencia_bancaria','manual','smoke_b13b');
    v_res := public.validar_gap_bordes_congelados(v_cab, v_d, TIME '15:00', v_d+3, TIME '10:00');
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','prereserva_pago_en_revision_cuenta', format('error=%s (esperado checkin_pisa_checkout_anterior; expira pasado no importa)', v_res->>'error'),
    (v_res->>'error')='checkin_pisa_checkout_anterior');
END $b10$;

-- B11: exclusion de pre_reserva. Pre-reserva viva conflictiva, excluida por p_excluir_prereserva => ok:true.
DO $b11$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint; v_pid bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+3780;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Smoke B1.3-B','+5491100000011') RETURNING id_huesped INTO v_h;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d,TIME '13:00',TIME '14:00',2,1000,300,'pendiente_pago',NOW()+INTERVAL '1 hour','transferencia_bancaria','manual','smoke_b13b') RETURNING id_pre_reserva INTO v_pid;
    v_res := public.validar_gap_bordes_congelados(v_cab, v_d, TIME '15:00', v_d+3, TIME '10:00', NULL, v_pid);
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('ok','exc'); END IF; END;
  PERFORM pg_temp.reg('FUN','exclusion_prereserva', format('ok=%s (excluida => ok:true)', v_res->>'ok'), (v_res->>'ok')::boolean IS TRUE);
END $b11$;

-- =====================================================================
-- TEARDOWN (residual 0: nunca se commitea un vecino; se verifica el rango de prueba)
-- =====================================================================
DO $td$
DECLARE v_cab bigint; v_res bigint; v_pre bigint; v_hue bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  SELECT count(*) INTO v_res FROM public.reservas
    WHERE id_cabana=v_cab AND fecha_checkin BETWEEN CURRENT_DATE+3640 AND CURRENT_DATE+3800;
  SELECT count(*) INTO v_pre FROM public.pre_reservas
    WHERE id_cabana=v_cab AND fecha_in BETWEEN CURRENT_DATE+3640 AND CURRENT_DATE+3800;
  SELECT count(*) INTO v_hue FROM public.huespedes WHERE nombre='Smoke B1.3-B';
  PERFORM pg_temp.reg('TD','residual_cero', format('reservas=%s pre_reservas=%s huespedes=%s (esperado 0/0/0)', v_res, v_pre, v_hue),
    v_res=0 AND v_pre=0 AND v_hue=0);
END $td$;

COMMIT;

SELECT seccion, caso, detalle, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS estado FROM _smoke ORDER BY id;
