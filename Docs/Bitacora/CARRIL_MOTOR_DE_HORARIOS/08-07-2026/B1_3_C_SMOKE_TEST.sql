-- =====================================================================
-- B1.3-C - SMOKE de crear_prereserva con el validador gap cableado  [POST-C]
-- =====================================================================
-- Verifica que el gate de gap de turno actua DENTRO de crear_prereserva, en AMBOS
-- bordes: un alta que pasa el daterange (semiabierto) pero pisa una hora congelada
-- de un vecino ahora es rechazada (checkin y checkout); un alta con gap >=2h se
-- crea; pre-reservas pago_en_revision cuentan aunque expira_en este pasado;
-- pre-reservas expiradas no bloquean. Incluye chequeo de ambiente=test y de que
-- crear_prereserva quedo owner-only.
-- Fixtures FIELES (huesped sintetico + NOT NULL reales). crear_prereserva ESCRIBE:
-- cada caso corre en una subtransaccion que revierte -> residual 0. El ULTIMO
-- statement es SELECT * FROM _smoke. Ejecutar el script ENTERO.
-- =====================================================================

DROP TABLE IF EXISTS pg_temp._smoke;
CREATE TEMP TABLE _smoke(id serial, seccion text, caso text, detalle text, ok boolean) ON COMMIT PRESERVE ROWS;

CREATE OR REPLACE FUNCTION pg_temp.reg(p_sec text, p_caso text, p_det text, p_ok boolean)
RETURNS void LANGUAGE sql AS $$ INSERT INTO _smoke(seccion,caso,detalle,ok) VALUES (p_sec,p_caso,p_det,p_ok); $$;

BEGIN;

-- Gate: ambiente test + C aplicado (validador cableado). Antes de cualquier fixture/escritura.
DO $g$
DECLARE v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
BEGIN
  IF COALESCE(v_amb,'') <> 'test' THEN
    RAISE EXCEPTION 'SMOKE B1.3-C: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF position('validar_gap_bordes_congelados' in pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'SMOKE B1.3-C: crear_prereserva NO tiene el validador cableado (C no aplicado). Abortando.';
  END IF;
END $g$;

-- SEGURIDAD (cero escrituras): crear_prereserva debe quedar owner-only.
DO $seg$
DECLARE r text; v_bad int := 0;
BEGIN
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r, 'public.crear_prereserva(jsonb)', 'EXECUTE') THEN v_bad := v_bad + 1; END IF;
  END LOOP;
  PERFORM pg_temp.reg('SEG','acl_owner_only', format('privilegios_indebidos=%s (esperado 0)', v_bad), v_bad=0);
END $seg$;

-- Helper: arma el payload de una candidata con hora de check-in solicitada.
-- (definido inline por caso; aca solo documentamos la forma)

-- C0: SANIDAD - alta sin vecinos, sin forzar hora (entra al check-in base resuelto) => ok:true.
DO $c0$
DECLARE v_cab bigint; v_res jsonb; v_d date;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+3980;
  BEGIN
    v_res := public.crear_prereserva(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'canal_origen','web','canal_pago_esperado','transferencia_bancaria','source_event','smoke_c',
      'huesped', jsonb_build_object('nombre','Cand Smoke C0','telefono','+5491140000000')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','sanidad_sin_vecinos', format('ok=%s (alta normal => ok:true)', v_res->>'ok'), (v_res->>'ok')::boolean IS TRUE);
END $c0$;

-- C1: alta que PASA daterange Y la ventana horaria normal, pero FALLA gap vs una
-- reserva confirmada ANTERIOR. La candidata NO fuerza hora: entra al check-in base
-- resuelto por el motor. El vecino sale 1h antes de ese mismo base (gap 1h < 2h),
-- anclando el fixture al valor resuelto para no depender del horario concreto
-- (robusto tanto en TEST con motor real como en el harness con stub).
DO $c1$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint; v_base_ci time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+4000;
  BEGIN
    v_base_ci := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke C1','+5491140000011') RETURNING id_huesped INTO v_h;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d, v_base_ci - INTERVAL '2 hours', v_base_ci - INTERVAL '1 hour',2,'confirmada','manual',1000,300,700,'smoke_c');
    v_res := public.crear_prereserva(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'canal_origen','web','canal_pago_esperado','transferencia_bancaria','source_event','smoke_c',
      'huesped', jsonb_build_object('nombre','Cand Smoke C1','telefono','+5491140000012')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','pasa_daterange_falla_gap',
    format('ok=%s error=%s (esperado ok:false / checkin_pisa_checkout_anterior)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='checkin_pisa_checkout_anterior');
END $c1$;

-- C2: alta compatible con gap EXACTO 2h. Vecino anterior sale 2h antes del check-in
-- base resuelto; la candidata entra a ese base (sin forzar). Gap 2h => se crea.
DO $c2$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint; v_base_ci time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+4020;
  BEGIN
    v_base_ci := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke C2','+5491140000021') RETURNING id_huesped INTO v_h;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d, v_base_ci - INTERVAL '3 hours', v_base_ci - INTERVAL '2 hours',2,'confirmada','manual',1000,300,700,'smoke_c');
    v_res := public.crear_prereserva(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'canal_origen','web','canal_pago_esperado','transferencia_bancaria','source_event','smoke_c',
      'huesped', jsonb_build_object('nombre','Cand Smoke C2','telefono','+5491140000022')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','gap_exacto_2h_ok',
    format('ok=%s id_pre=%s (gap 2h => ok:true con id)', v_res->>'ok', v_res->>'id_pre_reserva'),
    (v_res->>'ok')::boolean IS TRUE AND (v_res->>'id_pre_reserva') IS NOT NULL);
END $c2$;

-- C3: conflicto vs pre-reserva pago_en_revision (cuenta aunque expira_en este pasado).
-- Vecino sale 1h antes del check-in base resuelto; candidata entra a ese base. Gap 1h.
DO $c3$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint; v_base_ci time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+4040;
  BEGIN
    v_base_ci := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke C3','+5491140000031') RETURNING id_huesped INTO v_h;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d, v_base_ci - INTERVAL '2 hours', v_base_ci - INTERVAL '1 hour',2,1000,300,'pago_en_revision',NOW()-INTERVAL '1 hour','transferencia_bancaria','web','smoke_c');
    v_res := public.crear_prereserva(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'canal_origen','web','canal_pago_esperado','transferencia_bancaria','source_event','smoke_c',
      'huesped', jsonb_build_object('nombre','Cand Smoke C3','telefono','+5491140000032')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','conflicto_vs_pago_en_revision',
    format('ok=%s error=%s (pago_en_revision cuenta => checkin_pisa_checkout_anterior)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='checkin_pisa_checkout_anterior');
END $c3$;

-- C4: pre-reserva EXPIRADA (pendiente_pago, expira pasado) NO bloquea. El vecino sale
-- 1h antes del check-in base resuelto (generaria conflicto SI contara); como esta
-- expirada, no cuenta y la candidata se crea => ok:true con id.
DO $c4$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint; v_base_ci time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+4060;
  BEGIN
    v_base_ci := (public.resolver_horario(v_cab, v_d)->>'hora_checkin')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke C4','+5491140000041') RETURNING id_huesped INTO v_h;
    INSERT INTO public.pre_reservas(id_cabana,id_huesped,fecha_in,fecha_out,hora_checkin,hora_checkout,personas,monto_total,monto_sena,estado,expira_en,canal_pago_esperado,canal_origen,source_event)
      VALUES (v_cab,v_h,v_d-2,v_d, v_base_ci - INTERVAL '2 hours', v_base_ci - INTERVAL '1 hour',2,1000,300,'pendiente_pago',NOW()-INTERVAL '1 hour','transferencia_bancaria','web','smoke_c');
    v_res := public.crear_prereserva(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'canal_origen','web','canal_pago_esperado','transferencia_bancaria','source_event','smoke_c',
      'huesped', jsonb_build_object('nombre','Cand Smoke C4','telefono','+5491140000042')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','expirada_no_bloquea',
    format('ok=%s id_pre=%s (expirada no cuenta => ok:true con id)', v_res->>'ok', v_res->>'id_pre_reserva'),
    (v_res->>'ok')::boolean IS TRUE AND (v_res->>'id_pre_reserva') IS NOT NULL);
END $c4$;

-- C5: alta que PASA daterange pero FALLA gap en el SEGUNDO borde. La candidata sale al
-- check-out base resuelto (sin forzar); el vecino posterior entra 1h despues de ese
-- checkout (gap 1h). => checkout_pisa_checkin_posterior.
DO $c5$
DECLARE v_cab bigint; v_res jsonb; v_d date; v_h bigint; v_base_co time;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+4080;
  BEGIN
    v_base_co := (public.resolver_horario(v_cab, v_d+3)->>'hora_checkout')::time;
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke C5','+5491140000051') RETURNING id_huesped INTO v_h;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_h,v_d+3,v_d+5, v_base_co + INTERVAL '1 hour', v_base_co + INTERVAL '2 hours',2,'confirmada','manual',1000,300,700,'smoke_c');
    v_res := public.crear_prereserva(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'canal_origen','web','canal_pago_esperado','transferencia_bancaria','source_event','smoke_c',
      'huesped', jsonb_build_object('nombre','Cand Smoke C5','telefono','+5491140000052')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','pasa_daterange_falla_gap_checkout',
    format('ok=%s error=%s (esperado ok:false / checkout_pisa_checkin_posterior)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='checkout_pisa_checkin_posterior');
END $c5$;

-- C6: residual cero (ningun vecino ni candidata quedaron persistidos).
DO $c6$
DECLARE v_cab bigint; v_r bigint; v_p bigint; v_h bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  SELECT count(*) INTO v_r FROM public.reservas
    WHERE id_cabana=v_cab AND fecha_checkin BETWEEN CURRENT_DATE+3970 AND CURRENT_DATE+4090;
  SELECT count(*) INTO v_p FROM public.pre_reservas
    WHERE id_cabana=v_cab AND fecha_in BETWEEN CURRENT_DATE+3970 AND CURRENT_DATE+4090;
  SELECT count(*) INTO v_h FROM public.huespedes WHERE nombre LIKE 'Cand Smoke C%' OR nombre LIKE 'Vecino Smoke C%';
  PERFORM pg_temp.reg('TD','residual_cero', format('reservas=%s pre_reservas=%s huespedes=%s (esperado 0/0/0)', v_r, v_p, v_h),
    v_r=0 AND v_p=0 AND v_h=0);
END $c6$;

COMMIT;

SELECT seccion, caso, detalle, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS estado FROM _smoke ORDER BY id;
