-- =====================================================================
-- B1.3-D - SMOKE de confirmar_reserva con el validador gap cableado  [POST-D]
-- =====================================================================
-- Verifica que el gate de gap de turno actua DENTRO de confirmar_reserva usando las
-- horas CONGELADAS de la pre-reserva y EXCLUYENDO la propia pre-reserva. Cada caso
-- crea huesped + pre-reserva (horas ancladas al horario base resuelto) + pago
-- confirmado, y confirma. Los vecinos se anclan relativos al base (gap 1h conflicto,
-- 2h exacto permite): sin horarios fijos. confirmar_reserva ESCRIBE: cada caso corre
-- en una subtransaccion que revierte -> residual 0. Ultimo statement: SELECT * FROM
-- _smoke. Ejecutar el script ENTERO.
-- =====================================================================

DROP TABLE IF EXISTS pg_temp._smoke;
CREATE TEMP TABLE _smoke(id serial, seccion text, caso text, detalle text, ok boolean) ON COMMIT PRESERVE ROWS;

CREATE OR REPLACE FUNCTION pg_temp.reg(p_sec text, p_caso text, p_det text, p_ok boolean)
RETURNS void LANGUAGE sql AS $$ INSERT INTO _smoke(seccion,caso,detalle,ok) VALUES (p_sec,p_caso,p_det,p_ok); $$;

BEGIN;

-- Gate: ambiente test + D aplicado (validador cableado). Antes de cualquier fixture/escritura.
DO $g$
DECLARE v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
BEGIN
  IF COALESCE(v_amb,'') <> 'test' THEN
    RAISE EXCEPTION 'SMOKE B1.3-D: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF position('validar_gap_bordes_congelados' in pg_get_functiondef('public.confirmar_reserva(jsonb)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'SMOKE B1.3-D: confirmar_reserva NO tiene el validador cableado (D no aplicado). Abortando.';
  END IF;
END $g$;

-- SEGURIDAD (cero escrituras): confirmar_reserva debe quedar owner-only.
DO $seg$
DECLARE r text; v_bad int := 0;
BEGIN
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r, 'public.confirmar_reserva(jsonb)', 'EXECUTE') THEN v_bad := v_bad + 1; END IF;
  END LOOP;
  PERFORM pg_temp.reg('SEG','acl_owner_only', format('privilegios_indebidos=%s (esperado 0)', v_bad), v_bad=0);
END $seg$;

-- D0: confirmacion normal sin vecinos => ok:true con id_reserva.
DO $d0$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_hp bigint; v_pr bigint; v_bci time; v_bco time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+5000;
  BEGIN
    v_bci := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    v_bco := (public.resolver_horario(v_cab, v_d+3)->>'hora_checkout')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Titular Smoke D0','+5491150000000') RETURNING id_huesped INTO v_hp;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_hp,v_d,v_d+3,v_bci,v_bco,2,1000,300,'pendiente_pago',NOW()+INTERVAL '1 hour','transferencia_bancaria','web','smoke_d') RETURNING id_pre_reserva INTO v_pr;
    INSERT INTO public.pagos(id_prereserva,tipo,medio_pago,monto_esperado,monto_recibido,estado,source_event)
      VALUES (v_pr,'sena','transferencia_bancaria',300,300,'confirmado','smoke_d');
    v_res := public.confirmar_reserva(jsonb_build_object('id_pre_reserva', v_pr::text, 'source_event','smoke_d'));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','confirmacion_normal_sin_vecinos',
    format('ok=%s id_reserva=%s', v_res->>'ok', v_res->>'id_reserva'),
    (v_res->>'ok')::boolean IS TRUE AND (v_res->>'id_reserva') IS NOT NULL);
END $d0$;

-- D1: exclusion propia. La pre-reserva (pago_en_revision, viva) NO se auto-conflictua
-- ni en disponibilidad ni en el gap (p_excluir_prereserva) => se confirma.
DO $d1$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_hp bigint; v_pr bigint; v_bci time; v_bco time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+5020;
  BEGIN
    v_bci := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    v_bco := (public.resolver_horario(v_cab, v_d+3)->>'hora_checkout')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Titular Smoke D1','+5491150000010') RETURNING id_huesped INTO v_hp;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_hp,v_d,v_d+3,v_bci,v_bco,2,1000,300,'pago_en_revision',NOW()-INTERVAL '1 hour','transferencia_bancaria','web','smoke_d') RETURNING id_pre_reserva INTO v_pr;
    INSERT INTO public.pagos(id_prereserva,tipo,medio_pago,monto_esperado,monto_recibido,estado,source_event)
      VALUES (v_pr,'sena','transferencia_bancaria',300,300,'confirmado','smoke_d');
    v_res := public.confirmar_reserva(jsonb_build_object('id_pre_reserva', v_pr::text, 'source_event','smoke_d'));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','exclusion_propia_sin_auto_conflicto',
    format('ok=%s id_reserva=%s (pre-reserva viva no se auto-bloquea)', v_res->>'ok', v_res->>'id_reserva'),
    (v_res->>'ok')::boolean IS TRUE AND (v_res->>'id_reserva') IS NOT NULL);
END $d1$;

-- D2: confirmacion que FALLA por gap vs reserva confirmada vecina anterior (checkout
-- 1h antes del check-in congelado de la pre-reserva). => checkin_pisa_checkout_anterior.
DO $d2$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_hp bigint; v_pr bigint; v_hv bigint; v_bci time; v_bco time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+5040;
  BEGIN
    v_bci := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    v_bco := (public.resolver_horario(v_cab, v_d+3)->>'hora_checkout')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Titular Smoke D2','+5491150000020') RETURNING id_huesped INTO v_hp;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_hp,v_d,v_d+3,v_bci,v_bco,2,1000,300,'pendiente_pago',NOW()+INTERVAL '1 hour','transferencia_bancaria','web','smoke_d') RETURNING id_pre_reserva INTO v_pr;
    INSERT INTO public.pagos(id_prereserva,tipo,medio_pago,monto_esperado,monto_recibido,estado,source_event)
      VALUES (v_pr,'sena','transferencia_bancaria',300,300,'confirmado','smoke_d');
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke D2','+5491150000021') RETURNING id_huesped INTO v_hv;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_hv,v_d-2,v_d, v_bci - INTERVAL '2 hours', v_bci - INTERVAL '1 hour',2,'confirmada','manual',1000,300,700,'smoke_d');
    v_res := public.confirmar_reserva(jsonb_build_object('id_pre_reserva', v_pr::text, 'source_event','smoke_d'));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','falla_vs_reserva_confirmada_vecina',
    format('ok=%s error=%s (esperado checkin_pisa_checkout_anterior)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='checkin_pisa_checkout_anterior');
END $d2$;

-- D3: confirmacion que FALLA por gap vs pre-reserva pago_en_revision AJENA anterior.
DO $d3$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_hp bigint; v_pr bigint; v_hv bigint; v_bci time; v_bco time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+5060;
  BEGIN
    v_bci := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    v_bco := (public.resolver_horario(v_cab, v_d+3)->>'hora_checkout')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Titular Smoke D3','+5491150000030') RETURNING id_huesped INTO v_hp;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_hp,v_d,v_d+3,v_bci,v_bco,2,1000,300,'pendiente_pago',NOW()+INTERVAL '1 hour','transferencia_bancaria','web','smoke_d') RETURNING id_pre_reserva INTO v_pr;
    INSERT INTO public.pagos(id_prereserva,tipo,medio_pago,monto_esperado,monto_recibido,estado,source_event)
      VALUES (v_pr,'sena','transferencia_bancaria',300,300,'confirmado','smoke_d');
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke D3','+5491150000031') RETURNING id_huesped INTO v_hv;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_hv,v_d-2,v_d, v_bci - INTERVAL '2 hours', v_bci - INTERVAL '1 hour',2,1000,300,'pago_en_revision',NOW()-INTERVAL '1 hour','transferencia_bancaria','web','smoke_d');
    v_res := public.confirmar_reserva(jsonb_build_object('id_pre_reserva', v_pr::text, 'source_event','smoke_d'));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','falla_vs_prereserva_pago_en_revision_ajena',
    format('ok=%s error=%s (pago_en_revision ajena cuenta => checkin_pisa_checkout_anterior)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='checkin_pisa_checkout_anterior');
END $d3$;

-- D3b: confirmacion que FALLA por gap en el SEGUNDO borde. La candidata sale al check-out
-- congelado (base resuelto); el vecino confirmado POSTERIOR entra 1h despues de ese
-- checkout (gap 1h). validar_disponibilidad ('[)') deja pasar (no solapan).
-- => checkout_pisa_checkin_posterior.
DO $d3b$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_hp bigint; v_pr bigint; v_hv bigint; v_bci time; v_bco time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+5070;
  BEGIN
    v_bci := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    v_bco := (public.resolver_horario(v_cab, v_d+3)->>'hora_checkout')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Titular Smoke D3b','+5491150000070') RETURNING id_huesped INTO v_hp;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_hp,v_d,v_d+3,v_bci,v_bco,2,1000,300,'pendiente_pago',NOW()+INTERVAL '1 hour','transferencia_bancaria','web','smoke_d') RETURNING id_pre_reserva INTO v_pr;
    INSERT INTO public.pagos(id_prereserva,tipo,medio_pago,monto_esperado,monto_recibido,estado,source_event)
      VALUES (v_pr,'sena','transferencia_bancaria',300,300,'confirmado','smoke_d');
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke D3b','+5491150000071') RETURNING id_huesped INTO v_hv;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_hv,v_d+3,v_d+5, v_bco + INTERVAL '1 hour', v_bco + INTERVAL '2 hours',2,'confirmada','manual',1000,300,700,'smoke_d');
    v_res := public.confirmar_reserva(jsonb_build_object('id_pre_reserva', v_pr::text, 'source_event','smoke_d'));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','falla_vs_reserva_confirmada_posterior_checkout',
    format('ok=%s error=%s (esperado checkout_pisa_checkin_posterior)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='checkout_pisa_checkin_posterior');
END $d3b$;

-- D4: gap EXACTO 2h permite. Vecino confirmado sale 2h antes del check-in congelado. => ok con id.
DO $d4$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_hp bigint; v_pr bigint; v_hv bigint; v_bci time; v_bco time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+5080;
  BEGIN
    v_bci := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    v_bco := (public.resolver_horario(v_cab, v_d+3)->>'hora_checkout')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Titular Smoke D4','+5491150000040') RETURNING id_huesped INTO v_hp;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_hp,v_d,v_d+3,v_bci,v_bco,2,1000,300,'pendiente_pago',NOW()+INTERVAL '1 hour','transferencia_bancaria','web','smoke_d') RETURNING id_pre_reserva INTO v_pr;
    INSERT INTO public.pagos(id_prereserva,tipo,medio_pago,monto_esperado,monto_recibido,estado,source_event)
      VALUES (v_pr,'sena','transferencia_bancaria',300,300,'confirmado','smoke_d');
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke D4','+5491150000041') RETURNING id_huesped INTO v_hv;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_hv,v_d-2,v_d, v_bci - INTERVAL '3 hours', v_bci - INTERVAL '2 hours',2,'confirmada','manual',1000,300,700,'smoke_d');
    v_res := public.confirmar_reserva(jsonb_build_object('id_pre_reserva', v_pr::text, 'source_event','smoke_d'));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','gap_exacto_2h_permite',
    format('ok=%s id_reserva=%s (gap 2h => ok:true con id)', v_res->>'ok', v_res->>'id_reserva'),
    (v_res->>'ok')::boolean IS TRUE AND (v_res->>'id_reserva') IS NOT NULL);
END $d4$;

-- D5: residual cero (ninguna reserva/pre-reserva/pago/huesped quedo persistido).
DO $d5$
DECLARE v_cab bigint; v_r bigint; v_p bigint; v_h bigint; v_pg bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  SELECT count(*) INTO v_r FROM public.reservas WHERE id_cabana=v_cab AND fecha_checkin BETWEEN CURRENT_DATE+4990 AND CURRENT_DATE+5100;
  SELECT count(*) INTO v_p FROM public.pre_reservas WHERE id_cabana=v_cab AND fecha_in BETWEEN CURRENT_DATE+4990 AND CURRENT_DATE+5100;
  SELECT count(*) INTO v_h FROM public.huespedes WHERE nombre LIKE 'Titular Smoke D%' OR nombre LIKE 'Vecino Smoke D%';
  SELECT count(*) INTO v_pg FROM public.pagos WHERE source_event='smoke_d';
  PERFORM pg_temp.reg('TD','residual_cero', format('reservas=%s pre_reservas=%s huespedes=%s pagos=%s (esperado 0/0/0/0)', v_r, v_p, v_h, v_pg),
    v_r=0 AND v_p=0 AND v_h=0 AND v_pg=0);
END $d5$;

COMMIT;

SELECT seccion, caso, detalle, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS estado FROM _smoke ORDER BY id;
