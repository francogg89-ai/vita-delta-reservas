-- =====================================================================
-- B1.3-A - SMOKE del artefacto A (vigencias semanales)  [POST-A]
-- Orden: SEGURIDAD (cero escrituras) -> FUNCIONAL -> TEARDOWN (residual 0).
-- Sin residuo: los datos de prueba viven en un rango lejano (~10 anios) con
-- motivo '__smoke_b13a__' y se eliminan en el teardown; los casos de error usan
-- subtransacciones (savepoints) que revierten su escritura.
-- No hardcodea fingerprints (captura el del wrapper y compara post==pre), asi
-- corre igual en TEST (PG17) y en el harness (PG16).
-- El ULTIMO statement es SELECT * FROM _smoke => es lo que muestra el editor.
-- Ejecutar en Supabase SQL Editor SIN texto seleccionado (script entero).
-- =====================================================================

-- Tabla de resultados: acotada a pg_temp para que el DROP nunca pueda alcanzar
-- una tabla permanente homonima en public (si existiera). Con pg_temp inexistente
-- el DROP emite un NOTICE 'skipping' y sigue; CREATE TEMP crea el schema temporal.
DROP TABLE IF EXISTS pg_temp._smoke;
CREATE TEMP TABLE _smoke(id serial, seccion text, caso text, detalle text, ok boolean) ON COMMIT PRESERVE ROWS;

CREATE OR REPLACE FUNCTION pg_temp.reg(p_sec text, p_caso text, p_det text, p_ok boolean)
RETURNS void LANGUAGE sql AS $$ INSERT INTO _smoke(seccion,caso,detalle,ok) VALUES (p_sec,p_caso,p_det,p_ok); $$;

BEGIN;

-- Gate ligero: A aplicado (estructura, no fingerprint).
DO $g$
BEGIN
  IF to_regclass('public.vigencias_horario_detalle') IS NULL
     OR to_regprocedure('public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'SMOKE B1.3-A: A no aplicado (falta detalle o helper jsonb). Abortando.';
  END IF;
END $g$;

CREATE TEMP TABLE _sk_meta(k text, v text) ON COMMIT DROP;
INSERT INTO _sk_meta VALUES ('wrapper_pre', md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure)));

-- =====================================================================
-- SECCION SEGURIDAD (cero escrituras)
-- =====================================================================
DO $seg$
DECLARE r text; v_bad int := 0;
BEGIN
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'public._resolver_horario(bigint,date,boolean)','EXECUTE') THEN v_bad:=v_bad+1; END IF;
    IF has_function_privilege(r,'public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)','EXECUTE') THEN v_bad:=v_bad+1; END IF;
    IF has_function_privilege(r,'public.crear_vigencia_horario(jsonb)','EXECUTE') THEN v_bad:=v_bad+1; END IF;
    IF has_function_privilege(r,'public.trg_guard_vigencias()','EXECUTE') THEN v_bad:=v_bad+1; END IF;
  END LOOP;
  PERFORM pg_temp.reg('SEG','acl_owner_only', format('privilegios_indebidos=%s (esperado 0)', v_bad), v_bad=0);
END $seg$;

-- =====================================================================
-- SECCION FUNCIONAL
-- =====================================================================

-- F1: guard feliz (7 dias) + 7 filas + resolver por DOW + barrera acepta el estado completo.
DO $f1$
DECLARE v_res jsonb; v_id bigint; v_n int; v_ci_mar text; v_ori text; v_cab bigint;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde', to_char(CURRENT_DATE+3650,'YYYY-MM-DD'),
    'fecha_hasta', to_char(CURRENT_DATE+3680,'YYYY-MM-DD'),
    'motivo','__smoke_b13a__','creado_por','smoke',
    'dias', jsonb_build_object(
      '0',jsonb_build_object('hora_checkin','20:00','hora_checkout','18:00'),
      '1',jsonb_build_object('hora_checkin','13:00','hora_checkout','10:00'),
      '2',jsonb_build_object('hora_checkin','14:00','hora_checkout','11:00'),
      '3',jsonb_build_object('hora_checkin','15:00','hora_checkout','12:00'),
      '4',jsonb_build_object('hora_checkin','16:00','hora_checkout','13:00'),
      '5',jsonb_build_object('hora_checkin','17:00','hora_checkout','14:00'),
      '6',jsonb_build_object('hora_checkin','12:00','hora_checkout','09:00'))));
  PERFORM pg_temp.reg('FUN','guard_feliz', format('ok=%s', v_res->>'ok'), (v_res->>'ok')::boolean IS TRUE);
  v_id := (v_res->>'id_vigencia')::bigint;
  SELECT count(*) INTO v_n FROM public.vigencias_horario_detalle WHERE id_vigencia=v_id;
  PERFORM pg_temp.reg('FUN','detalle_7_filas', format('filas=%s (esperado 7)', v_n), v_n=7);
  SELECT public.resolver_horario(v_cab, f::date)->>'hora_checkin', public.resolver_horario(v_cab, f::date)->>'origen_checkin'
    INTO v_ci_mar, v_ori
  FROM generate_series(CURRENT_DATE+3650, CURRENT_DATE+3657, INTERVAL '1 day') f WHERE EXTRACT(DOW FROM f)=2 LIMIT 1;
  PERFORM pg_temp.reg('FUN','resolver_dow_martes', format('ci=%s origen=%s (esperado 14:00:00/vigencia)', v_ci_mar, v_ori), v_ci_mar='14:00:00' AND v_ori='vigencia');
  BEGIN
    SET CONSTRAINTS ALL IMMEDIATE;
    PERFORM pg_temp.reg('FUN','barrera_acepta_feliz','sin excepcion al forzar IMMEDIATE', true);
    SET CONSTRAINTS ALL DEFERRED;
  EXCEPTION WHEN others THEN
    PERFORM pg_temp.reg('FUN','barrera_acepta_feliz', 'excepcion inesperada: '||SQLERRM, false);
    SET CONSTRAINTS ALL DEFERRED;
  END;
END $f1$;

-- F2: dias_incompleto (6 claves) => {ok:false, error:dias_incompleto}, sin insertar.
DO $f2$
DECLARE v_res jsonb; v_pre int; v_post int;
BEGIN
  SELECT count(*) INTO v_pre FROM public.vigencias_horario_base;
  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde', to_char(CURRENT_DATE+3700,'YYYY-MM-DD'), 'fecha_hasta', to_char(CURRENT_DATE+3710,'YYYY-MM-DD'),
    'motivo','__smoke_b13a__','creado_por','smoke',
    'dias', (SELECT jsonb_object_agg(d::text, jsonb_build_object('hora_checkin','13:00','hora_checkout','10:00')) FROM generate_series(0,5) d)));
  SELECT count(*) INTO v_post FROM public.vigencias_horario_base;
  PERFORM pg_temp.reg('FUN','dias_incompleto', format('error=%s filas_delta=%s', v_res->>'error', v_post-v_pre),
    (v_res->>'error')='dias_incompleto' AND v_post=v_pre);
END $f2$;

-- F3: hora_fuera_de_ventana y gap_insuficiente.
DO $f3$
DECLARE v_res jsonb;
BEGIN
  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde', to_char(CURRENT_DATE+3700,'YYYY-MM-DD'), 'fecha_hasta', to_char(CURRENT_DATE+3710,'YYYY-MM-DD'),
    'motivo','__smoke_b13a__','creado_por','smoke',
    'dias', (SELECT jsonb_object_agg(d::text, CASE WHEN d=4 THEN jsonb_build_object('hora_checkin','13:00','hora_checkout','05:00')
                                                   ELSE jsonb_build_object('hora_checkin','13:00','hora_checkout','10:00') END) FROM generate_series(0,6) d)));
  PERFORM pg_temp.reg('FUN','hora_fuera_de_ventana', format('error=%s dia=%s', v_res->>'error', v_res->>'dia_semana'), (v_res->>'error')='hora_fuera_de_ventana');
  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde', to_char(CURRENT_DATE+3700,'YYYY-MM-DD'), 'fecha_hasta', to_char(CURRENT_DATE+3710,'YYYY-MM-DD'),
    'motivo','__smoke_b13a__','creado_por','smoke',
    'dias', (SELECT jsonb_object_agg(d::text, CASE WHEN d=2 THEN jsonb_build_object('hora_checkin','11:00','hora_checkout','10:00')
                                                   ELSE jsonb_build_object('hora_checkin','13:00','hora_checkout','10:00') END) FROM generate_series(0,6) d)));
  PERFORM pg_temp.reg('FUN','gap_insuficiente', format('error=%s dia=%s', v_res->>'error', v_res->>'dia_semana'), (v_res->>'error')='gap_insuficiente');
END $f3$;

-- F4: vigencia_solapada (rango dentro del de F1).
DO $f4$
DECLARE v_res jsonb;
BEGIN
  v_res := public.crear_vigencia_horario(jsonb_build_object(
    'fecha_desde', to_char(CURRENT_DATE+3660,'YYYY-MM-DD'), 'fecha_hasta', to_char(CURRENT_DATE+3670,'YYYY-MM-DD'),
    'motivo','__smoke_b13a__','creado_por','smoke',
    'dias', (SELECT jsonb_object_agg(d::text, jsonb_build_object('hora_checkin','13:00','hora_checkout','10:00')) FROM generate_series(0,6) d)));
  PERFORM pg_temp.reg('FUN','vigencia_solapada', format('error=%s', v_res->>'error'), (v_res->>'error')='vigencia_solapada');
END $f4$;

-- F5: config fallback (fecha fuera de toda vigencia): lunes => base, domingo => patron_domingo.
DO $f5$
DECLARE v_cab bigint; v_lun text; v_dom text; v_lf date; v_df date;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  SELECT f INTO v_lf FROM generate_series(CURRENT_DATE+100, CURRENT_DATE+107, INTERVAL '1 day') f WHERE EXTRACT(DOW FROM f)=1 LIMIT 1;
  SELECT f INTO v_df FROM generate_series(CURRENT_DATE+100, CURRENT_DATE+107, INTERVAL '1 day') f WHERE EXTRACT(DOW FROM f)=0 LIMIT 1;
  v_lun := public.resolver_horario(v_cab, v_lf)->>'origen_checkin';
  v_dom := public.resolver_horario(v_cab, v_df)->>'origen_checkin';
  PERFORM pg_temp.reg('FUN','config_fallback', format('lunes=%s domingo=%s (esperado base/patron_domingo)', v_lun, v_dom), v_lun='base' AND v_dom='patron_domingo');
END $f5$;

-- F6: override_cabana pisa la vigencia (dentro del rango de F1).
DO $f6$
DECLARE v_cab bigint; v_mar date; v_ci text; v_ori text;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  SELECT f INTO v_mar FROM generate_series(CURRENT_DATE+3650, CURRENT_DATE+3657, INTERVAL '1 day') f WHERE EXTRACT(DOW FROM f)=2 LIMIT 1;
  INSERT INTO public.overrides_operativos(fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, source_event, activo)
    VALUES (v_mar, v_mar, v_cab, 'hora_checkin', '21:00', '__smoke_b13a__', 'smoke', '__smoke_b13a__', true);
  v_ci  := public.resolver_horario(v_cab, v_mar)->>'hora_checkin';
  v_ori := public.resolver_horario(v_cab, v_mar)->>'origen_checkin';
  PERFORM pg_temp.reg('FUN','override_pisa_vigencia', format('ci=%s origen=%s (esperado 21:00:00/override_cabana)', v_ci, v_ori), v_ci='21:00:00' AND v_ori='override_cabana');
END $f6$;

-- F7: INV-1 conductual: interno CIEGO (false) sobre fecha con vigencia SIN override => config, NO vigencia.
--     (Se usa jueves: tiene vigencia pero, a diferencia del martes de F6, no tiene override.)
DO $f7$
DECLARE v_cab bigint; v_jue date; v_ori text;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  SELECT f INTO v_jue FROM generate_series(CURRENT_DATE+3650, CURRENT_DATE+3657, INTERVAL '1 day') f WHERE EXTRACT(DOW FROM f)=4 LIMIT 1;
  v_ori := public._resolver_horario(v_cab, v_jue, false)->>'origen_checkin';
  PERFORM pg_temp.reg('FUN','inv1_interno_ciego', format('origen=%s (esperado base; NUNCA vigencia)', v_ori), v_ori IN ('base','patron_domingo'));
END $f7$;

-- F8: resolver fail-closed => vigencia_incompleta (borra 1 detalle en savepoint; revierte).
DO $f8$
DECLARE v_cab bigint; v_mie date; v_vid bigint; v_err text;
BEGIN
  v_cab := (SELECT MIN(id_cabana) FROM public.cabanas);
  v_vid := (SELECT id_vigencia FROM public.vigencias_horario_base WHERE motivo='__smoke_b13a__' AND fecha_desde=CURRENT_DATE+3650 LIMIT 1);
  SELECT f INTO v_mie FROM generate_series(CURRENT_DATE+3650, CURRENT_DATE+3657, INTERVAL '1 day') f WHERE EXTRACT(DOW FROM f)=3 LIMIT 1;
  BEGIN
    DELETE FROM public.vigencias_horario_detalle WHERE id_vigencia=v_vid AND dia_semana=3;
    SELECT public.resolver_horario(v_cab, v_mie)->>'error' INTO v_err;
    RAISE EXCEPTION '__rb__';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> '__rb__' THEN v_err := 'EXC:'||SQLERRM; END IF;
  END;
  PERFORM pg_temp.reg('FUN','resolver_vigencia_incompleta', format('error=%s (esperado vigencia_incompleta)', v_err), v_err='vigencia_incompleta');
END $f8$;

-- F9: barrera diferida rechaza cabecera activa con <7 filas (cabecera + 6 detalle).
DO $f9$
DECLARE v_vid bigint; v_err text;
BEGIN
  BEGIN
    INSERT INTO public.vigencias_horario_base(fecha_desde, fecha_hasta, abierta, motivo, creado_por)
      VALUES (CURRENT_DATE+3800, CURRENT_DATE+3810, false, '__smoke_b13a__', 'smoke') RETURNING id_vigencia INTO v_vid;
    INSERT INTO public.vigencias_horario_detalle(id_vigencia, dia_semana, hora_checkin, hora_checkout)
      SELECT v_vid, d, TIME '13:00', TIME '10:00' FROM generate_series(0,5) d;   -- solo 6 (falta 6)
    SET CONSTRAINTS ALL IMMEDIATE;   -- fuerza la barrera => debe lanzar vigencia_incompleta
    v_err := 'sin_excepcion';
  EXCEPTION WHEN others THEN
    v_err := CASE WHEN position('vigencia_incompleta' in SQLERRM) > 0
                  THEN 'vigencia_incompleta' ELSE SQLERRM END;
  END;
  -- El savepoint del sub-bloque revierte la cabecera+6 filas; no queda residuo.
  PERFORM pg_temp.reg('FUN','barrera_rechaza_incompleta', format('resultado=%s (esperado vigencia_incompleta)', v_err),
    v_err='vigencia_incompleta');
  BEGIN SET CONSTRAINTS ALL DEFERRED; EXCEPTION WHEN others THEN NULL; END;
END $f9$;

-- =====================================================================
-- TEARDOWN (elimina todo lo de prueba; residual debe ser 0)
-- =====================================================================
DELETE FROM public.overrides_operativos WHERE motivo='__smoke_b13a__';
DELETE FROM public.vigencias_horario_base WHERE motivo='__smoke_b13a__';   -- CASCADE -> detalle

DO $td$
DECLARE v_vig int; v_ovr int; v_det int; v_wrap_pre text; v_wrap_post text;
BEGIN
  SELECT count(*) INTO v_vig FROM public.vigencias_horario_base WHERE motivo='__smoke_b13a__';
  SELECT count(*) INTO v_ovr FROM public.overrides_operativos WHERE motivo='__smoke_b13a__';
  SELECT count(*) INTO v_det FROM public.vigencias_horario_detalle d
    JOIN public.vigencias_horario_base b USING (id_vigencia) WHERE b.motivo='__smoke_b13a__';
  PERFORM pg_temp.reg('TD','residual_cero', format('vigencias=%s overrides=%s detalle=%s (esperado 0/0/0)', v_vig, v_ovr, v_det),
    v_vig=0 AND v_ovr=0 AND v_det=0);
  SELECT v INTO v_wrap_pre FROM _sk_meta WHERE k='wrapper_pre';
  v_wrap_post := md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure));
  PERFORM pg_temp.reg('TD','wrapper_estable', format('post==pre=%s', (v_wrap_post=v_wrap_pre)), v_wrap_post=v_wrap_pre);
END $td$;

COMMIT;

-- ---- Resultado (ULTIMO statement => visible en el editor) ----
SELECT
  seccion, caso, detalle,
  CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS estado
FROM _smoke ORDER BY id;
