-- =====================================================================
-- B1.3-E - SMOKE de crear_reserva_con_horario_pactado  (contrato v2)
-- =====================================================================
-- Cubre: alta pactada, source_event ausente (interno) / invalido, horario pactado
-- requerido, borde no pactado resuelto (con el otro pactado), ambos bordes del gap,
-- gap exacto 2h, log con motivo CONSTANTE + fechas + horas, huesped actualizado,
-- campos operativos persistidos (con notas_reserva del payload, sin el motivo tecnico),
-- fecha_in pasada rechazada, residual cero y ACL. Los casos de gap usan horas pactadas
-- dentro de la ventana fisica con el vecino anclado relativo a la pactada (gap
-- determinístico). La funcion ESCRIBE: cada caso corre en subtransaccion que revierte ->
-- residual 0. Ultimo statement: SELECT * FROM _smoke. Ejecutar ENTERO.
-- =====================================================================

DROP TABLE IF EXISTS pg_temp._smoke;
CREATE TEMP TABLE _smoke(id serial, seccion text, caso text, detalle text, ok boolean) ON COMMIT PRESERVE ROWS;

CREATE OR REPLACE FUNCTION pg_temp.reg(p_sec text, p_caso text, p_det text, p_ok boolean)
RETURNS void LANGUAGE sql AS $$ INSERT INTO _smoke(seccion,caso,detalle,ok) VALUES (p_sec,p_caso,p_det,p_ok); $$;

BEGIN;

DO $g$
DECLARE v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
BEGIN
  IF COALESCE(v_amb,'') <> 'test' THEN
    RAISE EXCEPTION 'SMOKE B1.3-E: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF to_regprocedure('public.crear_reserva_con_horario_pactado(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'SMOKE B1.3-E: la funcion no existe (E no instalada). Abortando.';
  END IF;
END $g$;

-- SEG (cero escrituras): owner-only.
DO $seg$
DECLARE r text; v_bad int := 0;
BEGIN
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r, 'public.crear_reserva_con_horario_pactado(jsonb)', 'EXECUTE') THEN v_bad := v_bad + 1; END IF;
  END LOOP;
  PERFORM pg_temp.reg('SEG','acl_owner_only', format('privilegios_indebidos=%s (esperado 0)', v_bad), v_bad=0);
END $seg$;

-- E0: alta pactada normal sin vecinos => ok; horas congeladas = pactadas.
DO $e0$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_hci time; v_hco time;
  c_pci CONSTANT time := TIME '14:00'; c_pco CONSTANT time := TIME '12:00';
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6000;
  BEGIN
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','reserva_manual_horario_pactado',
      'hora_checkin_pactada', c_pci::text, 'hora_checkout_pactada', c_pco::text,
      'huesped', jsonb_build_object('nombre','Titular Smoke E0','telefono','+5491160000000')));
    IF (v_res->>'ok')::boolean THEN
      SELECT hora_checkin, hora_checkout INTO v_hci, v_hco FROM public.reservas WHERE id_reserva=(v_res->>'id_reserva')::bigint;
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','alta_pactada_normal_sin_vecinos',
    format('ok=%s id=%s horas=%s/%s (pactadas %s/%s)', v_res->>'ok', v_res->>'id_reserva', v_hci, v_hco, c_pci, c_pco),
    (v_res->>'ok')::boolean IS TRUE AND (v_res->>'id_reserva') IS NOT NULL AND v_hci=c_pci AND v_hco=c_pco);
END $e0$;

-- E1: payload SIN source_event => ok; la reserva queda con el source_event interno.
DO $e1$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_se text;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6015;
  BEGIN
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'hora_checkin_pactada','14:00', 'hora_checkout_pactada','12:00',
      'huesped', jsonb_build_object('nombre','Titular Smoke E1','telefono','+5491160000015')));
    IF (v_res->>'ok')::boolean THEN
      SELECT source_event INTO v_se FROM public.reservas WHERE id_reserva=(v_res->>'id_reserva')::bigint;
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','sin_source_event_usa_interno',
    format('ok=%s source_event=%s (esperado reserva_manual_horario_pactado)', v_res->>'ok', v_se),
    (v_res->>'ok')::boolean IS TRUE AND v_se='reserva_manual_horario_pactado');
END $e1$;

-- E2: source_event presente y distinto => source_event_invalido.
DO $e2$
DECLARE v_res jsonb; v_cab bigint; v_d date;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6030;
  BEGIN
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','otro_source_event_cualquiera',
      'hora_checkin_pactada','14:00', 'hora_checkout_pactada','12:00',
      'huesped', jsonb_build_object('nombre','Titular Smoke E2','telefono','+5491160000030')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','source_event_incorrecto_falla',
    format('ok=%s error=%s (esperado source_event_invalido)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='source_event_invalido');
END $e2$;

-- E3: sin NINGUN borde pactado => horario_pactado_requerido.
DO $e3$
DECLARE v_res jsonb; v_cab bigint; v_d date;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6045;
  BEGIN
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','reserva_manual_horario_pactado',
      'huesped', jsonb_build_object('nombre','Titular Smoke E3','telefono','+5491160000045')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','horario_pactado_requerido',
    format('ok=%s error=%s (esperado horario_pactado_requerido)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='horario_pactado_requerido');
END $e3$;

-- E4: un borde pactado (checkin), el otro omitido (checkout) => se resuelve con resolver_horario.
DO $e4$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_hci time; v_hco time; v_bco time;
  c_pci CONSTANT time := TIME '14:00';
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6060;
  BEGIN
    v_bco := (public.resolver_horario(v_cab, v_d+3)->>'hora_checkout')::time;
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','reserva_manual_horario_pactado',
      'hora_checkin_pactada', c_pci::text,   -- checkin pactado; checkout OMITIDO
      'huesped', jsonb_build_object('nombre','Titular Smoke E4','telefono','+5491160000060')));
    IF (v_res->>'ok')::boolean THEN
      SELECT hora_checkin, hora_checkout INTO v_hci, v_hco FROM public.reservas WHERE id_reserva=(v_res->>'id_reserva')::bigint;
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','borde_no_pactado_resuelve_horario',
    format('ok=%s hci=%s(pactado %s) hco=%s(resuelto %s)', v_res->>'ok', v_hci, c_pci, v_hco, v_bco),
    (v_res->>'ok')::boolean IS TRUE AND v_hci=c_pci AND v_hco=v_bco);
END $e4$;

-- E5: check-in pactado temprano pisa checkout de vecino anterior (gap 1h). => checkin_pisa_checkout_anterior.
DO $e5$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_hv bigint;
  c_pci CONSTANT time := TIME '09:00';
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6075;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke E5','+5491160000076') RETURNING id_huesped INTO v_hv;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_hv,v_d-2,v_d, c_pci - INTERVAL '2 hours', c_pci - INTERVAL '1 hour',2,'confirmada','manual',1000,300,700,'smoke_e');
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','reserva_manual_horario_pactado',
      'hora_checkin_pactada', c_pci::text, 'hora_checkout_pactada','12:00',
      'huesped', jsonb_build_object('nombre','Titular Smoke E5','telefono','+5491160000075')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','checkin_pactado_temprano_bloquea_checkout_anterior',
    format('ok=%s error=%s (esperado checkin_pisa_checkout_anterior)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='checkin_pisa_checkout_anterior');
END $e5$;

-- E6: check-out pactado tardio pisa check-in de vecino posterior (gap 1h). => checkout_pisa_checkin_posterior.
DO $e6$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_hv bigint;
  c_pco CONSTANT time := TIME '21:00';
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6090;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke E6','+5491160000091') RETURNING id_huesped INTO v_hv;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_hv,v_d+3,v_d+5, c_pco + INTERVAL '1 hour', c_pco + INTERVAL '2 hours',2,'confirmada','manual',1000,300,700,'smoke_e');
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','reserva_manual_horario_pactado',
      'hora_checkin_pactada','13:00', 'hora_checkout_pactada', c_pco::text,
      'huesped', jsonb_build_object('nombre','Titular Smoke E6','telefono','+5491160000090')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','checkout_pactado_tardio_bloquea_checkin_posterior',
    format('ok=%s error=%s (esperado checkout_pisa_checkin_posterior)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='checkout_pisa_checkin_posterior');
END $e6$;

-- E7: gap EXACTO 2h permite vecino anterior. => ok con id.
DO $e7$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_hv bigint;
  c_pci CONSTANT time := TIME '10:00';
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6105;
  BEGIN
    INSERT INTO public.huespedes(nombre,telefono) VALUES ('Vecino Smoke E7','+5491160000106') RETURNING id_huesped INTO v_hv;
    INSERT INTO public.reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cab,v_hv,v_d-2,v_d, c_pci - INTERVAL '3 hours', c_pci - INTERVAL '2 hours',2,'confirmada','manual',1000,300,700,'smoke_e');
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','reserva_manual_horario_pactado',
      'hora_checkin_pactada', c_pci::text, 'hora_checkout_pactada','12:00',
      'huesped', jsonb_build_object('nombre','Titular Smoke E7','telefono','+5491160000105')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','gap_exacto_2h_permite',
    format('ok=%s id=%s (gap 2h => ok con id)', v_res->>'ok', v_res->>'id_reserva'),
    (v_res->>'ok')::boolean IS TRUE AND (v_res->>'id_reserva') IS NOT NULL);
END $e7$;

-- E8: log explicito con motivo CONSTANTE + fechas + horas; notas_reserva NO contaminado por el motivo.
DO $e8$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_rid bigint; v_det jsonb; v_notas_res text;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6120;
  BEGIN
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','reserva_manual_horario_pactado',
      'motivo','ESTE_MOTIVO_LIBRE_DEBE_IGNORARSE',
      'hora_checkin_pactada','14:00', 'hora_checkout_pactada','12:00',
      'huesped', jsonb_build_object('nombre','Titular Smoke E8','telefono','+5491160000120')));
    IF (v_res->>'ok')::boolean THEN
      v_rid := (v_res->>'id_reserva')::bigint;
      SELECT detalle INTO v_det FROM public.log_cambios
        WHERE tabla_afectada='reservas' AND id_registro=v_rid::text AND modificado_por='crear_reserva_con_horario_pactado';
      SELECT notas_reserva INTO v_notas_res FROM public.reservas WHERE id_reserva=v_rid;
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','log_motivo_constante_fechas_horas',
    format('motivo=%s fci=%s fco=%s hci=%s hco=%s notas_reserva=%s',
           v_det->>'motivo', v_det->>'fecha_checkin', v_det->>'fecha_checkout', v_det->>'hora_checkin', v_det->>'hora_checkout', COALESCE(v_notas_res,'<null>')),
    (v_res->>'ok')::boolean IS TRUE
      AND v_det->>'motivo' = 'Horario especial pactado al crear reserva manual'
      AND v_det->>'fecha_checkin' = v_d::text
      AND v_det->>'fecha_checkout' = (v_d+3)::text
      AND (v_det->>'hora_checkin') IS NOT NULL
      AND (v_det->>'hora_checkout') IS NOT NULL
      AND v_notas_res IS NULL);
END $e8$;

-- E9: huesped actualizado (total_reservas +1, primera_reserva_fecha = fecha_in).
DO $e9$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_hid bigint; v_tr int; v_prf date;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6135;
  BEGIN
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','reserva_manual_horario_pactado',
      'hora_checkin_pactada','14:00', 'hora_checkout_pactada','12:00',
      'huesped', jsonb_build_object('nombre','Titular Smoke E9','telefono','+5491160000135')));
    IF (v_res->>'ok')::boolean THEN
      v_hid := (v_res->>'id_huesped')::bigint;
      SELECT total_reservas, primera_reserva_fecha INTO v_tr, v_prf FROM public.huespedes WHERE id_huesped=v_hid;
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','huesped_actualizado',
    format('ok=%s total_reservas=%s primera_reserva_fecha=%s (esperado 1 y %s)', v_res->>'ok', v_tr, v_prf, v_d),
    (v_res->>'ok')::boolean IS TRUE AND v_tr = 1 AND v_prf = v_d);
END $e9$;

-- E10: campos operativos persistidos; notas_reserva = nota del payload (NO el motivo tecnico).
DO $e10$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_rid bigint;
  v_notas text; v_masc boolean; v_detm text; v_nin text; v_nres text;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas); v_d := CURRENT_DATE+6150;
  BEGIN
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', v_d::text, 'fecha_out', (v_d+3)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','reserva_manual_horario_pactado',
      'hora_checkin_pactada','14:00', 'hora_checkout_pactada','12:00',
      'notas','nota general del sistema', 'mascotas', true, 'detalle_mascotas','un perro grande',
      'ninos','dos ninos', 'notas_reserva','nota operativa de Vicky',
      'huesped', jsonb_build_object('nombre','Titular Smoke E10','telefono','+5491160000150')));
    IF (v_res->>'ok')::boolean THEN
      v_rid := (v_res->>'id_reserva')::bigint;
      SELECT notas, mascotas, detalle_mascotas, ninos, notas_reserva
        INTO v_notas, v_masc, v_detm, v_nin, v_nres FROM public.reservas WHERE id_reserva=v_rid;
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','campos_operativos_persisten',
    format('notas=%s mascotas=%s detalle=%s ninos=%s notas_reserva=%s', v_notas, v_masc, v_detm, v_nin, v_nres),
    (v_res->>'ok')::boolean IS TRUE
      AND v_notas='nota general del sistema' AND v_masc IS TRUE AND v_detm='un perro grande'
      AND v_nin='dos ninos' AND v_nres='nota operativa de Vicky'
      AND v_nres <> 'Horario especial pactado al crear reserva manual');
END $e10$;

-- E11: fecha_in en el pasado => fecha_in_pasada (no crea nada).
DO $e11$
DECLARE v_res jsonb; v_cab bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  BEGIN
    v_res := public.crear_reserva_con_horario_pactado(jsonb_build_object(
      'id_cabana', v_cab::text, 'fecha_in', (CURRENT_DATE-5)::text, 'fecha_out', (CURRENT_DATE-2)::text,
      'personas','2','monto_total','1000','monto_sena','300',
      'source_event','reserva_manual_horario_pactado',
      'hora_checkin_pactada','14:00', 'hora_checkout_pactada','12:00',
      'huesped', jsonb_build_object('nombre','Titular Smoke E11','telefono','+5491160000165')));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','fecha_in_pasada',
    format('ok=%s error=%s (esperado fecha_in_pasada)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='fecha_in_pasada');
END $e11$;

-- E12: residual cero (nada persistio).
DO $e12$
DECLARE v_cab bigint; v_r bigint; v_h bigint; v_l bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  SELECT count(*) INTO v_r FROM public.reservas WHERE id_cabana=v_cab AND fecha_checkin BETWEEN CURRENT_DATE+5990 AND CURRENT_DATE+6200 AND source_event IN ('reserva_manual_horario_pactado','smoke_e');
  SELECT count(*) INTO v_h FROM public.huespedes WHERE nombre LIKE 'Titular Smoke E%' OR nombre LIKE 'Vecino Smoke E%';
  SELECT count(*) INTO v_l FROM public.log_cambios WHERE modificado_por='crear_reserva_con_horario_pactado';
  PERFORM pg_temp.reg('TD','residual_cero', format('reservas=%s huespedes=%s logs=%s (esperado 0/0/0)', v_r, v_h, v_l),
    v_r=0 AND v_h=0 AND v_l=0);
END $e12$;

COMMIT;

SELECT seccion, caso, detalle, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS estado FROM _smoke ORDER BY id;
