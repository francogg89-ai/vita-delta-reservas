-- =====================================================================
-- B1.3-F - SMOKE de crear_override_horario_puntual  (13 casos)
-- =====================================================================
-- Cubre: ACL owner-only; checkin-only / checkout-only / ambos en una cabaña (EFECTO del
-- borde pedido); grupo_estricto aplica-todo y falla-todo (all-or-nothing); todas_posibles
-- aplica libres + reporta excluida comprometida; EFECTO restringido no mira el otro borde
-- (override contrario preexistente no hace fallar checkin-only si el borde pedido queda
-- efectivo); caso viejo S3 reproducido como bordes:'ambos'; checkin con hora_checkout /
-- checkout con hora_checkin => borde_horas_incompatibles; fecha_hasta < fecha => rango_invalido;
-- residual cero. Horas de override elegidas para gap same-day >= 2h con cualquier base.
-- Cada caso corre en subtransaccion que revierte (RAISE '__rb__') -> residual 0.
-- Ultimo statement: SELECT * FROM _smoke. Ejecutar ENTERO.
-- =====================================================================

DROP TABLE IF EXISTS pg_temp._smoke;
CREATE TEMP TABLE _smoke(id serial, seccion text, caso text, detalle text, ok boolean) ON COMMIT PRESERVE ROWS;

CREATE OR REPLACE FUNCTION pg_temp.reg(p_sec text, p_caso text, p_det text, p_ok boolean)
RETURNS void LANGUAGE sql AS $$ INSERT INTO _smoke(seccion,caso,detalle,ok) VALUES (p_sec,p_caso,p_det,p_ok); $$;

BEGIN;

DO $g$
DECLARE v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
BEGIN
  IF COALESCE(v_amb,'') <> 'test' THEN RAISE EXCEPTION 'SMOKE B1.3-F: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>'); END IF;
  IF to_regprocedure('public.crear_override_horario_puntual(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'SMOKE B1.3-F: la funcion no existe (F no instalada). Abortando.';
  END IF;
END $g$;

-- SEG (cero escrituras): owner-only.
DO $seg$
DECLARE r text; v_bad int := 0;
BEGIN
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r, 'public.crear_override_horario_puntual(jsonb)', 'EXECUTE') THEN v_bad := v_bad + 1; END IF;
  END LOOP;
  PERFORM pg_temp.reg('SEG','acl_owner_only', format('privilegios_indebidos=%s (esperado 0)', v_bad), v_bad=0);
END $seg$;

-- F1: checkin-only en una cabaña => override checkin, EFECTO solo checkin.
DO $f1$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_eff jsonb; v_co int; v_ci int;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM cabanas); v_d := CURRENT_DATE+7000;
  BEGIN
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','checkin','alcance','cabana','id_cabana', v_cab::text,
      'fecha', v_d::text,'hora_checkin','19:00','motivo','smoke F','creado_por','harness'));
    IF (v_res->>'ok')::boolean THEN
      v_eff := resolver_horario(v_cab, v_d);
      SELECT count(*) INTO v_ci FROM overrides_operativos WHERE id_cabana=v_cab AND fecha_desde=v_d AND tipo_override='hora_checkin';
      SELECT count(*) INTO v_co FROM overrides_operativos WHERE id_cabana=v_cab AND fecha_desde=v_d AND tipo_override='hora_checkout';
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','checkin_only_cabana',
    format('ok=%s checkin_efectivo=%s ov_checkin=%s ov_checkout=%s', v_res->>'ok', v_eff->>'hora_checkin', v_ci, v_co),
    (v_res->>'ok')::boolean IS TRUE AND (v_eff->>'hora_checkin')='19:00:00' AND v_ci=1 AND v_co=0);
END $f1$;

-- F2: checkout-only en una cabaña => override checkout, EFECTO solo checkout.
DO $f2$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_eff jsonb; v_co int; v_ci int;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM cabanas); v_d := CURRENT_DATE+7010;
  BEGIN
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','checkout','alcance','cabana','id_cabana', v_cab::text,
      'fecha', v_d::text,'hora_checkout','08:00','motivo','smoke F','creado_por','harness'));
    IF (v_res->>'ok')::boolean THEN
      v_eff := resolver_horario(v_cab, v_d);
      SELECT count(*) INTO v_co FROM overrides_operativos WHERE id_cabana=v_cab AND fecha_desde=v_d AND tipo_override='hora_checkout';
      SELECT count(*) INTO v_ci FROM overrides_operativos WHERE id_cabana=v_cab AND fecha_desde=v_d AND tipo_override='hora_checkin';
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','checkout_only_cabana',
    format('ok=%s checkout_efectivo=%s ov_checkout=%s ov_checkin=%s', v_res->>'ok', v_eff->>'hora_checkout', v_co, v_ci),
    (v_res->>'ok')::boolean IS TRUE AND (v_eff->>'hora_checkout')='08:00:00' AND v_co=1 AND v_ci=0);
END $f2$;

-- F3: ambos en una cabaña => override checkout + checkin, EFECTO ambos.
DO $f3$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_eff jsonb; v_co int; v_ci int;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM cabanas); v_d := CURRENT_DATE+7020;
  BEGIN
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','ambos','alcance','cabana','id_cabana', v_cab::text,
      'fecha', v_d::text,'hora_checkout','09:00','hora_checkin','14:00','motivo','smoke F','creado_por','harness'));
    IF (v_res->>'ok')::boolean THEN
      v_eff := resolver_horario(v_cab, v_d);
      SELECT count(*) INTO v_co FROM overrides_operativos WHERE id_cabana=v_cab AND fecha_desde=v_d AND tipo_override='hora_checkout';
      SELECT count(*) INTO v_ci FROM overrides_operativos WHERE id_cabana=v_cab AND fecha_desde=v_d AND tipo_override='hora_checkin';
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','ambos_cabana',
    format('ok=%s co=%s ci=%s ov_co=%s ov_ci=%s', v_res->>'ok', v_eff->>'hora_checkout', v_eff->>'hora_checkin', v_co, v_ci),
    (v_res->>'ok')::boolean IS TRUE AND (v_eff->>'hora_checkout')='09:00:00' AND (v_eff->>'hora_checkin')='14:00:00' AND v_co=1 AND v_ci=1);
END $f3$;

-- F4: grupo_estricto con 2 cabañas libres => ambas aplican.
DO $f4$
DECLARE v_res jsonb; v_c1 bigint; v_c2 bigint; v_d date; v_n int;
BEGIN
  v_c1 := (SELECT MIN(id_cabana) FROM cabanas);
  v_c2 := (SELECT MIN(id_cabana) FROM cabanas WHERE id_cabana > v_c1);
  v_d := CURRENT_DATE+7030;
  BEGIN
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','checkin','alcance','grupo_estricto','ids_cabanas', jsonb_build_array(v_c1, v_c2),
      'fecha', v_d::text,'hora_checkin','19:00','motivo','smoke F','creado_por','harness'));
    IF (v_res->>'ok')::boolean THEN
      SELECT count(*) INTO v_n FROM overrides_operativos WHERE id_cabana IN (v_c1,v_c2) AND fecha_desde=v_d AND tipo_override='hora_checkin';
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','grupo_estricto_aplica_todo',
    format('ok=%s aplicadas=%s overrides=%s (esperado 2 cabanas / 2 overrides)', v_res->>'ok', v_res->'cabanas_aplicadas', v_n),
    (v_res->>'ok')::boolean IS TRUE AND jsonb_array_length(v_res->'cabanas_aplicadas')=2 AND v_n=2);
END $f4$;

-- F5: grupo_estricto con 1 cabaña comprometida => falla todo, ningun override queda.
DO $f5$
DECLARE v_res jsonb; v_c1 bigint; v_c2 bigint; v_d date; v_h bigint; v_n int;
BEGIN
  v_c1 := (SELECT MIN(id_cabana) FROM cabanas);
  v_c2 := (SELECT MIN(id_cabana) FROM cabanas WHERE id_cabana > v_c1);
  v_d := CURRENT_DATE+7040;
  BEGIN
    INSERT INTO huespedes(nombre,telefono) VALUES ('Comprometido F5','+5491170000040') RETURNING id_huesped INTO v_h;
    INSERT INTO reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_c2, v_h, v_d, v_d+2, '14:00','10:00', 2,'confirmada','manual',1000,300,700,'smoke_f');
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','checkin','alcance','grupo_estricto','ids_cabanas', jsonb_build_array(v_c1, v_c2),
      'fecha', v_d::text,'hora_checkin','19:00','motivo','smoke F','creado_por','harness'));
    SELECT count(*) INTO v_n FROM overrides_operativos WHERE id_cabana IN (v_c1,v_c2) AND fecha_desde=v_d;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','grupo_estricto_falla_todo',
    format('ok=%s error=%s overrides_restantes=%s (esperado false/override_pisa_reserva/0)', v_res->>'ok', v_res->>'error', v_n),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='override_pisa_reserva' AND v_n=0);
END $f5$;

-- F6: todas_posibles con 1 comprometida => aplica el resto, reporta la excluida.
DO $f6$
DECLARE v_res jsonb; v_cx bigint; v_d date; v_h bigint; v_activas int; v_excl_tiene boolean; v_aplic_tiene boolean;
BEGIN
  v_cx := (SELECT MIN(id_cabana) FROM cabanas);  -- esta se compromete
  v_d := CURRENT_DATE+7050;
  v_activas := (SELECT count(*) FROM cabanas WHERE activa);
  BEGIN
    INSERT INTO huespedes(nombre,telefono) VALUES ('Comprometido F6','+5491170000050') RETURNING id_huesped INTO v_h;
    INSERT INTO reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_cx, v_h, v_d, v_d+2, '14:00','10:00', 2,'confirmada','manual',1000,300,700,'smoke_f');
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','checkin','alcance','todas_posibles',
      'fecha', v_d::text,'hora_checkin','19:00','motivo','smoke F','creado_por','harness'));
    IF (v_res->>'ok')::boolean THEN
      v_excl_tiene  := EXISTS (SELECT 1 FROM jsonb_array_elements(v_res->'cabanas_excluidas') e WHERE (e->>'id_cabana')::bigint = v_cx);
      v_aplic_tiene := EXISTS (SELECT 1 FROM jsonb_array_elements(v_res->'cabanas_aplicadas') a WHERE a::text::bigint = v_cx);
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','todas_posibles_aplica_libres_reporta_excluidas',
    format('ok=%s aplicadas=%s excluidas=%s (activas=%s; comprometida en excluidas=%s, no en aplicadas=%s)',
           v_res->>'ok', jsonb_array_length(v_res->'cabanas_aplicadas'), jsonb_array_length(v_res->'cabanas_excluidas'), v_activas, v_excl_tiene, NOT v_aplic_tiene),
    (v_res->>'ok')::boolean IS TRUE
      AND jsonb_array_length(v_res->'cabanas_aplicadas') = v_activas - 1
      AND v_excl_tiene IS TRUE AND v_aplic_tiene IS FALSE);
END $f6$;

-- F7: EFECTO restringido no mira el otro borde. Override checkout preexistente + checkin-only.
DO $f7$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_eff jsonb;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM cabanas); v_d := CURRENT_DATE+7060;
  BEGIN
    -- override checkout preexistente (distinto del base) que quedaria "sombreando" el checkout
    INSERT INTO overrides_operativos(fecha_desde, id_cabana, tipo_override, valor, motivo, creado_por, activo)
      VALUES (v_d, v_cab, 'hora_checkout', '08:00', 'preexistente', 'harness', true);
    -- checkin-only: solo mira checkin. checkout efectivo (08:00) da gap 11h con checkin 19:00 -> S0 ok.
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','checkin','alcance','cabana','id_cabana', v_cab::text,
      'fecha', v_d::text,'hora_checkin','19:00','motivo','smoke F','creado_por','harness'));
    IF (v_res->>'ok')::boolean THEN v_eff := resolver_horario(v_cab, v_d); END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','efecto_restringido_no_mira_otro_borde',
    format('ok=%s checkin_efectivo=%s checkout_efectivo=%s (checkin-only aplica pese a checkout preexistente 08:00)',
           v_res->>'ok', v_eff->>'hora_checkin', v_eff->>'hora_checkout'),
    (v_res->>'ok')::boolean IS TRUE AND (v_eff->>'hora_checkin')='19:00:00' AND (v_eff->>'hora_checkout')='08:00:00');
END $f7$;

-- F8: caso viejo S3 reproducido como bordes:'ambos'.
DO $f8$
DECLARE v_res jsonb; v_cab bigint; v_d date; v_eff jsonb;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM cabanas); v_d := CURRENT_DATE+7070;
  BEGIN
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','ambos','alcance','cabana','id_cabana', v_cab::text,
      'fecha', v_d::text,'hora_checkout','09:00','motivo','smoke F','creado_por','harness'));  -- checkin derivado 11:00
    IF (v_res->>'ok')::boolean THEN v_eff := resolver_horario(v_cab, v_d); END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','caso_viejo_s3_como_ambos',
    format('ok=%s co=%s ci=%s (checkin derivado checkout+120=11:00)', v_res->>'ok', v_eff->>'hora_checkout', v_eff->>'hora_checkin'),
    (v_res->>'ok')::boolean IS TRUE AND (v_eff->>'hora_checkout')='09:00:00' AND (v_eff->>'hora_checkin')='11:00:00');
END $f8$;

-- F9 (D7): checkin con hora_checkout => borde_horas_incompatibles.
DO $f9$
DECLARE v_res jsonb; v_cab bigint; v_d date;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM cabanas); v_d := CURRENT_DATE+7080;
  BEGIN
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','checkin','alcance','cabana','id_cabana', v_cab::text,
      'fecha', v_d::text,'hora_checkin','19:00','hora_checkout','08:00','motivo','smoke F','creado_por','harness'));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','checkin_con_hora_checkout_falla',
    format('ok=%s error=%s (esperado borde_horas_incompatibles)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='borde_horas_incompatibles');
END $f9$;

-- F10 (D7): checkout con hora_checkin => borde_horas_incompatibles.
DO $f10$
DECLARE v_res jsonb; v_cab bigint; v_d date;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM cabanas); v_d := CURRENT_DATE+7090;
  BEGIN
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','checkout','alcance','cabana','id_cabana', v_cab::text,
      'fecha', v_d::text,'hora_checkout','08:00','hora_checkin','19:00','motivo','smoke F','creado_por','harness'));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','checkout_con_hora_checkin_falla',
    format('ok=%s error=%s (esperado borde_horas_incompatibles)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='borde_horas_incompatibles');
END $f10$;

-- F11 (D7): fecha_hasta < fecha => rango_invalido.
DO $f11$
DECLARE v_res jsonb; v_cab bigint; v_d date;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM cabanas); v_d := CURRENT_DATE+7100;
  BEGIN
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','checkin','alcance','cabana','id_cabana', v_cab::text,
      'fecha', v_d::text,'fecha_hasta', (v_d-1)::text,'hora_checkin','19:00','motivo','smoke F','creado_por','harness'));
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','fecha_hasta_menor_fecha_falla',
    format('ok=%s error=%s (esperado rango_invalido)', v_res->>'ok', v_res->>'error'),
    (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='rango_invalido');
END $f11$;

-- F12: grupo_posibles con 1 comprometida => aplica la libre, reporta la excluida (capacidad interna).
DO $f12$
DECLARE v_res jsonb; v_c1 bigint; v_c2 bigint; v_d date; v_h bigint; v_excl boolean; v_aplic boolean; v_n int;
BEGIN
  v_c1 := (SELECT MIN(id_cabana) FROM cabanas);
  v_c2 := (SELECT MIN(id_cabana) FROM cabanas WHERE id_cabana > v_c1);
  v_d := CURRENT_DATE+7110;
  BEGIN
    INSERT INTO huespedes(nombre,telefono) VALUES ('Comprometido FA','+5491170000110') RETURNING id_huesped INTO v_h;
    INSERT INTO reservas(id_cabana,id_huesped,fecha_checkin,fecha_checkout,hora_checkin,hora_checkout,personas,estado,canal_origen,monto_total,monto_sena,monto_saldo,source_event)
      VALUES (v_c2, v_h, v_d, v_d+2, '14:00','10:00', 2,'confirmada','manual',1000,300,700,'smoke_f');
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','checkin','alcance','grupo_posibles','ids_cabanas', jsonb_build_array(v_c1, v_c2),
      'fecha', v_d::text,'hora_checkin','19:00','motivo','smoke F','creado_por','harness'));
    IF (v_res->>'ok')::boolean THEN
      v_aplic := EXISTS (SELECT 1 FROM jsonb_array_elements(v_res->'cabanas_aplicadas') a WHERE a::text::bigint = v_c1);
      v_excl  := EXISTS (SELECT 1 FROM jsonb_array_elements(v_res->'cabanas_excluidas') e WHERE (e->>'id_cabana')::bigint = v_c2);
      SELECT count(*) INTO v_n FROM overrides_operativos WHERE id_cabana = v_c1 AND fecha_desde = v_d AND tipo_override='hora_checkin';
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','grupo_posibles_aplica_libres_reporta_excluidas',
    format('ok=%s aplicadas=%s excluidas=%s (c1 aplicada=%s, c2 excluida=%s, ov_c1=%s)',
      v_res->>'ok', jsonb_array_length(v_res->'cabanas_aplicadas'), jsonb_array_length(v_res->'cabanas_excluidas'), v_aplic, v_excl, v_n),
    (v_res->>'ok')::boolean IS TRUE
      AND jsonb_array_length(v_res->'cabanas_aplicadas')=1 AND jsonb_array_length(v_res->'cabanas_excluidas')=1
      AND v_aplic IS TRUE AND v_excl IS TRUE AND v_n=1);
END $f12$;

-- F13: global_estricto (bordes ambos) => overrides globales id_cabana NULL, vistos por >=2 cabanas.
DO $f13$
DECLARE v_res jsonb; v_c1 bigint; v_c2 bigint; v_d date; v_eff1 jsonb; v_eff2 jsonb; v_glob int; v_esp int;
BEGIN
  v_c1 := (SELECT MIN(id_cabana) FROM cabanas);
  v_c2 := (SELECT MIN(id_cabana) FROM cabanas WHERE id_cabana > v_c1);
  v_d := CURRENT_DATE+7120;
  BEGIN
    v_res := crear_override_horario_puntual(jsonb_build_object(
      'bordes','ambos','alcance','global_estricto',
      'fecha', v_d::text,'hora_checkout','09:00','hora_checkin','14:00','motivo','smoke F','creado_por','harness'));
    IF (v_res->>'ok')::boolean THEN
      SELECT count(*) INTO v_glob FROM overrides_operativos WHERE id_cabana IS NULL AND fecha_desde = v_d;
      SELECT count(*) INTO v_esp  FROM overrides_operativos WHERE id_cabana IS NOT NULL AND fecha_desde = v_d;
      v_eff1 := resolver_horario(v_c1, v_d);
      v_eff2 := resolver_horario(v_c2, v_d);
    END IF;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN IF SQLERRM<>'__rb__' THEN v_res := jsonb_build_object('error','EXC:'||SQLERRM); END IF; END;
  PERFORM pg_temp.reg('FUN','global_estricto_aplica_global',
    format('ok=%s ov_globales=%s ov_especificos=%s c1=%s/%s c2=%s/%s (esperado 2 globales, 0 especificos, ambas 09:00/14:00)',
      v_res->>'ok', v_glob, v_esp, v_eff1->>'hora_checkout', v_eff1->>'hora_checkin', v_eff2->>'hora_checkout', v_eff2->>'hora_checkin'),
    (v_res->>'ok')::boolean IS TRUE AND v_glob=2 AND v_esp=0
      AND (v_eff1->>'hora_checkout')='09:00:00' AND (v_eff1->>'hora_checkin')='14:00:00'
      AND (v_eff2->>'hora_checkout')='09:00:00' AND (v_eff2->>'hora_checkin')='14:00:00');
END $f13$;

-- F14: residual cero (nada persistio).
DO $f14$
DECLARE v_o bigint; v_r bigint; v_h bigint;
BEGIN
  SELECT count(*) INTO v_o FROM overrides_operativos WHERE fecha_desde BETWEEN CURRENT_DATE+6990 AND CURRENT_DATE+7200;
  SELECT count(*) INTO v_r FROM reservas WHERE source_event='smoke_f';
  SELECT count(*) INTO v_h FROM huespedes WHERE nombre LIKE 'Comprometido F%';
  PERFORM pg_temp.reg('TD','residual_cero', format('overrides=%s reservas=%s huespedes=%s (esperado 0/0/0)', v_o, v_r, v_h),
    v_o=0 AND v_r=0 AND v_h=0);
END $f14$;

COMMIT;

SELECT seccion, caso, detalle, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS estado FROM _smoke ORDER BY id;
