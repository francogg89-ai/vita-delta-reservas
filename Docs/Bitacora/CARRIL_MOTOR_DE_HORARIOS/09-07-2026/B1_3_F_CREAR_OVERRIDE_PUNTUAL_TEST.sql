-- =====================================================================
-- B1.3-F - crear_override_horario_puntual(jsonb)  [FUNCION NUEVA UNIFICADA]
-- =====================================================================
-- REEMPLAZA a crear_paquete_dia_especial(jsonb) (S3): DROP del viejo + CREATE del nuevo,
-- sin coexistencia. Generaliza S3 agregando el eje `bordes` (checkin | checkout | ambos).
-- S2 (crear_override_horario) queda INTACTO como primitiva. No toca A/B/C/D/E.
--
-- Semantica de `bordes` (D2/D3):
--   checkout : inserta SOLO override hora_checkout; EFECTO valida SOLO .hora_checkout.
--              Exige hora_checkout; PROHIBE hora_checkin (=> borde_horas_incompatibles).
--   checkin  : inserta SOLO override hora_checkin;  EFECTO valida SOLO .hora_checkin.
--              Exige hora_checkin;  PROHIBE hora_checkout (=> borde_horas_incompatibles).
--   ambos    : semantica S3. Inserta hora_checkout + hora_checkin; EFECTO valida ambos.
--              Exige hora_checkout; hora_checkin derivada (checkout+gap) o explicita; gap_minutos validado.
-- El gap same-day de un borde suelto lo garantiza S0 contra el borde efectivo del otro lado;
-- F no inventa el borde no pedido. Un override preexistente del borde contrario NO hace fallar
-- una operacion de un solo borde salvo que S0 detecte estado horario final invalido (gap real).
--
-- Alcances: producto MVP {cabana, grupo_estricto, todas_posibles}; capacidad interna
--   {grupo_posibles, global_estricto} (aceptados para que F sea superset de S3). Ramas:
--   cabana/grupo_estricto = all-or-nothing per-cabana; global_estricto = override(s) global(es)
--   real(es); grupo_posibles/todas_posibles = subtransaccion por cabana (aplica validas+efectivas,
--   reporta excluidas; sin_cabanas_aplicables si ninguna).
--
-- EFECTO (postcondicion de precedencia, D5): para cada cabana/fecha aplicada, resolver_horario
--   debe devolver la(s) hora(s) del/los borde(s) SOLICITADO(S). Si no => override_no_aplicado_efectivamente
--   (clase efecto_no_aplicado). Reemplaza conceptualmente a paquete_no_aplicado_efectivamente de S3.
-- Rango (D6): fecha_hasta >= fecha, si no => rango_invalido.
-- created_at/id_override NO son parametros. source_event deriva hijos por borde insertado:
--   <source>:checkout:<id_cabana|global> y/o <source>:checkin:<id_cabana|global>.
--
-- Instalacion fail-closed (transaccional):
--   GATE 0 ambiente == 'test'.
--   GATE 1 resolver_horario(bigint,date) fp == 1bd96c89... (wrapper actual post-A).
--   GATE 2 S0 presentes (validar_estado_horario_final, validar_no_eventos_comprometidos, validar_estado_override).
--   GATE 3 S1 presente: trg_guard_overrides() + trg_ov_guard sobre public.overrides_operativos,
--          constraint trigger (tgconstraint<>0) y habilitado (tgenabled<>'D').
--   GATE 4 S2 presente (crear_override_horario(jsonb)).
--   GATE 5 no-callers: ninguna otra funcion referencia crear_paquete_dia_especial en pg_proc.prosrc.
--   GATE 6 crear_paquete_dia_especial(jsonb) existe (se reemplaza); crear_override_horario_puntual(jsonb) no existe.
-- DROP crear_paquete_dia_especial + CREATE (no OR REPLACE) F + REVOKE owner-only + postcheck ACL.
-- Reversible por B1_3_F_ROLLBACK_TEST.sql (restaura S3). Ejecutar el script ENTERO.
-- =====================================================================

BEGIN;

DO $gate$
DECLARE
  c_fp_wrap CONSTANT text := '1bd96c89e587b15582fd7b2e29ae7e18';  -- resolver_horario (wrapper, post-A)
  v_amb text;
  v_tgenabled "char";
  v_tgconstraint oid;
BEGIN
  PERFORM pg_advisory_xact_lock(10, 0);

  v_amb := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  IF COALESCE(v_amb, '') <> 'test' THEN
    RAISE EXCEPTION 'F-GATE: ambiente=% (esperado test). Abortando.', COALESCE(v_amb, '<null>');
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'F-GATE: schema=% (esperado public). Abortando.', current_schema();
  END IF;

  IF to_regprocedure('public.resolver_horario(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'F-GATE: resolver_horario (wrapper) ausente. Abortando.';
  END IF;
  IF md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure)) <> c_fp_wrap THEN
    RAISE EXCEPTION 'F-GATE: fingerprint del wrapper resolver_horario distinto del esperado (post-A). Abortando.';
  END IF;

  IF to_regprocedure('public.validar_estado_horario_final(bigint,date)') IS NULL
     OR to_regprocedure('public.validar_no_eventos_comprometidos(bigint,date)') IS NULL
     OR to_regprocedure('public.validar_estado_override(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'F-GATE: faltan validadores S0. Abortando.';
  END IF;

  IF to_regprocedure('public.trg_guard_overrides()') IS NULL THEN
    RAISE EXCEPTION 'F-GATE: falta trg_guard_overrides() (S1). Abortando.';
  END IF;
  -- trg_ov_guard debe existir sobre public.overrides_operativos, ser constraint trigger y estar habilitado.
  SELECT t.tgenabled, t.tgconstraint INTO v_tgenabled, v_tgconstraint
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'overrides_operativos'
    AND t.tgname = 'trg_ov_guard' AND NOT t.tgisinternal;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'F-GATE: falta el trigger trg_ov_guard sobre public.overrides_operativos (S1). Abortando.';
  END IF;
  IF v_tgconstraint = 0 THEN
    RAISE EXCEPTION 'F-GATE: trg_ov_guard no es constraint trigger (tgconstraint=0) (S1). Abortando.';
  END IF;
  IF v_tgenabled = 'D' THEN
    RAISE EXCEPTION 'F-GATE: trg_ov_guard esta deshabilitado (tgenabled=D) (S1). Abortando.';
  END IF;

  IF to_regprocedure('public.crear_override_horario(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'F-GATE: falta crear_override_horario (S2). Abortando.';
  END IF;

  -- No-callers: ninguna OTRA funcion referencia crear_paquete_dia_especial en su cuerpo.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE p.prosrc ILIKE '%crear_paquete_dia_especial%' AND p.proname <> 'crear_paquete_dia_especial') THEN
    RAISE EXCEPTION 'F-GATE: hay funciones que referencian crear_paquete_dia_especial en pg_proc.prosrc. Abortando.';
  END IF;

  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'F-GATE: crear_paquete_dia_especial (S3) ausente; se esperaba para reemplazar. Abortando.';
  END IF;
  IF to_regprocedure('public.crear_override_horario_puntual(jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'F-GATE: crear_override_horario_puntual ya existe. Usar rollback antes de reinstalar. Abortando.';
  END IF;

  RAISE NOTICE 'F-GATE OK: test/public, resolver post-A, S0+S1+S2 presentes, no-callers, S3 presente.';
END $gate$;

-- Reemplazo sin coexistencia.
DROP FUNCTION public.crear_paquete_dia_especial(jsonb);

CREATE FUNCTION public.crear_override_horario_puntual(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
AS $fn$
DECLARE
  v_bordes       text;
  v_need_co      boolean;
  v_need_ci      boolean;
  v_fecha        date;
  v_fecha_hasta  date := NULL;
  v_co           time := NULL;
  v_ci           time := NULL;
  v_gap          int  := 120;
  v_alcance      text;
  v_id_cabana    bigint := NULL;
  v_ids          bigint[] := NULL;
  v_targets      bigint[] := ARRAY[]::bigint[];
  v_motivo       text;
  v_creado_por   text;
  v_source       text := NULL;
  v_co_txt       text := NULL;
  v_ci_txt       text := NULL;
  v_soc          text;
  v_sic          text;
  v_ovc          bigint;
  v_ovi          bigint;
  v_verd         jsonb;
  v_eff          jsonb;
  v_detalle_txt  text;
  v_modo         text;
  v_aplicadas    jsonb := '[]'::jsonb;
  v_excluidas    jsonb := '[]'::jsonb;
  v_creados      jsonb := '[]'::jsonb;
  v_creados_obj  jsonb;
  v_cab          bigint;
  rec            record;
BEGIN
  PERFORM pg_advisory_xact_lock(10, 0);

  -- ===== Validacion de payload =====
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'payload no es objeto jsonb');
  END IF;
  IF (p_payload ? 'created_at') OR (p_payload ? 'id_override') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'created_at/id_override no son parametros; los asigna la DB');
  END IF;
  IF (p_payload->>'fecha') IS NULL OR (p_payload->>'bordes') IS NULL OR (p_payload->>'alcance') IS NULL
     OR (p_payload->>'motivo') IS NULL OR (p_payload->>'creado_por') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'faltan requeridos: fecha, bordes, alcance, motivo, creado_por');
  END IF;

  -- bordes soportado
  v_bordes := p_payload->>'bordes';
  IF v_bordes NOT IN ('checkin','checkout','ambos') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bordes_no_soportado', 'bordes', v_bordes);
  END IF;
  v_need_co := (v_bordes IN ('checkout','ambos'));
  v_need_ci := (v_bordes IN ('checkin','ambos'));

  -- casts
  BEGIN
    v_fecha := (p_payload->>'fecha')::date;
    IF (p_payload ? 'fecha_hasta') AND (p_payload->>'fecha_hasta') IS NOT NULL THEN v_fecha_hasta := (p_payload->>'fecha_hasta')::date; END IF;
    IF (p_payload ? 'gap_minutos') AND (p_payload->>'gap_minutos') IS NOT NULL THEN v_gap := (p_payload->>'gap_minutos')::int; END IF;
    IF (p_payload ? 'id_cabana') AND (p_payload->>'id_cabana') IS NOT NULL THEN v_id_cabana := (p_payload->>'id_cabana')::bigint; END IF;
    IF (p_payload ? 'hora_checkout') AND (p_payload->>'hora_checkout') IS NOT NULL THEN v_co := (p_payload->>'hora_checkout')::time; END IF;
    IF (p_payload ? 'hora_checkin') AND (p_payload->>'hora_checkin') IS NOT NULL THEN v_ci := (p_payload->>'hora_checkin')::time; END IF;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow OR invalid_datetime_format THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'cast de campo fallido (fecha/hora/gap/id_cabana)');
  END;

  v_alcance     := p_payload->>'alcance';
  v_motivo      := p_payload->>'motivo';
  v_creado_por  := p_payload->>'creado_por';
  IF (p_payload ? 'source_event') AND (p_payload->>'source_event') IS NOT NULL THEN v_source := p_payload->>'source_event'; END IF;

  -- D6: rango
  IF v_fecha_hasta IS NOT NULL AND v_fecha_hasta < v_fecha THEN
    RETURN jsonb_build_object('ok', false, 'error', 'rango_invalido', 'detalle', 'fecha_hasta < fecha', 'fecha', v_fecha, 'fecha_hasta', v_fecha_hasta);
  END IF;

  -- D2: contrato de horas por borde (error, no ignorar)
  IF v_bordes = 'checkin' THEN
    IF v_ci IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'bordes=checkin requiere hora_checkin');
    END IF;
    IF v_co IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'borde_horas_incompatibles', 'detalle', 'bordes=checkin no admite hora_checkout', 'bordes', v_bordes);
    END IF;
  ELSIF v_bordes = 'checkout' THEN
    IF v_co IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'bordes=checkout requiere hora_checkout');
    END IF;
    IF v_ci IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'borde_horas_incompatibles', 'detalle', 'bordes=checkout no admite hora_checkin', 'bordes', v_bordes);
    END IF;
  ELSE  -- ambos (semantica S3)
    IF v_co IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'bordes=ambos requiere hora_checkout');
    END IF;
    IF v_gap < 120 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'gap_minutos < 120');
    END IF;
    IF v_ci IS NULL THEN
      v_ci := v_co + make_interval(mins => v_gap);
    END IF;
    IF v_ci <= v_co OR (v_ci - v_co) < make_interval(mins => v_gap) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'hora_checkin <= hora_checkout (cruza medianoche) o gap insuficiente');
    END IF;
  END IF;

  -- alcance soportado
  IF v_alcance NOT IN ('cabana','grupo_estricto','grupo_posibles','global_estricto','todas_posibles') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'alcance_no_soportado', 'alcance', v_alcance);
  END IF;

  -- targets por alcance
  IF v_alcance = 'cabana' THEN
    IF v_id_cabana IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'alcance cabana requiere id_cabana');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM cabanas WHERE id_cabana = v_id_cabana) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_encontrada', 'id_cabana', v_id_cabana);
    END IF;
    v_targets := ARRAY[v_id_cabana];
  ELSIF v_alcance IN ('grupo_estricto','grupo_posibles') THEN
    IF NOT (p_payload ? 'ids_cabanas') OR jsonb_typeof(p_payload->'ids_cabanas') IS DISTINCT FROM 'array' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'alcance grupo requiere ids_cabanas array no vacio');
    END IF;
    IF jsonb_array_length(p_payload->'ids_cabanas') = 0 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'alcance grupo requiere ids_cabanas array no vacio');
    END IF;
    BEGIN
      SELECT array_agg(val::bigint) INTO v_ids FROM jsonb_array_elements_text(p_payload->'ids_cabanas') AS t(val);
    EXCEPTION WHEN invalid_text_representation THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'ids_cabanas contiene no-enteros');
    END;
    IF cardinality(v_ids) <> (SELECT count(DISTINCT x) FROM unnest(v_ids) AS x) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'ids_cabanas_invalidos', 'detalle', 'ids_cabanas con duplicados', 'ids_cabanas', to_jsonb(v_ids));
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(v_ids) i WHERE NOT EXISTS (SELECT 1 FROM cabanas WHERE id_cabana = i)) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'ids_cabanas_invalidos', 'detalle', 'ids_cabanas con id inexistente', 'ids_cabanas', to_jsonb(v_ids));
    END IF;
    v_targets := v_ids;
  ELSE  -- global_estricto, todas_posibles
    v_targets := COALESCE((SELECT array_agg(id_cabana ORDER BY id_cabana) FROM cabanas WHERE activa), ARRAY[]::bigint[]);
  END IF;

  IF v_need_co THEN v_co_txt := to_char(v_co, 'HH24:MI'); END IF;
  IF v_need_ci THEN v_ci_txt := to_char(v_ci, 'HH24:MI'); END IF;

  -- ============================================================
  -- Rama 1: cabana / grupo_estricto -> all-or-nothing per-cabana
  -- ============================================================
  IF v_alcance IN ('cabana','grupo_estricto') THEN
    v_modo := CASE WHEN v_alcance = 'cabana' THEN 'cabana_unica' ELSE 'expandido_por_cabana' END;
    BEGIN
      FOREACH v_cab IN ARRAY v_targets LOOP
        v_creados_obj := jsonb_build_object('id_cabana', v_cab);
        IF v_need_co THEN
          v_soc := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkout:' || v_cab::text END;
          INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
          VALUES (v_fecha, v_fecha_hasta, v_cab, 'hora_checkout', v_co_txt, v_motivo, v_creado_por, true, v_soc) RETURNING id_override INTO v_ovc;
          v_creados_obj := v_creados_obj || jsonb_build_object('id_override_checkout', v_ovc);
        END IF;
        IF v_need_ci THEN
          v_sic := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkin:' || v_cab::text END;
          INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
          VALUES (v_fecha, v_fecha_hasta, v_cab, 'hora_checkin', v_ci_txt, v_motivo, v_creado_por, true, v_sic) RETURNING id_override INTO v_ovi;
          v_creados_obj := v_creados_obj || jsonb_build_object('id_override_checkin', v_ovi);
        END IF;
        v_creados   := v_creados   || v_creados_obj;
        v_aplicadas := v_aplicadas || to_jsonb(v_cab);
      END LOOP;
      FOR rec IN
        SELECT t AS cab, g::date AS fecha
        FROM unnest(v_targets) AS t
        CROSS JOIN LATERAL generate_series(v_fecha, COALESCE(v_fecha_hasta, v_fecha), interval '1 day') AS g
      LOOP
        v_verd := validar_estado_override(rec.cab, rec.fecha);
        IF NOT (v_verd->>'ok')::boolean THEN
          RAISE EXCEPTION 'estricto_estado_fallo' USING ERRCODE = '45000', DETAIL = v_verd::text;
        END IF;
        v_eff := resolver_horario(rec.cab, rec.fecha);
        IF (v_eff->>'ok')::boolean IS NOT TRUE
           OR (v_need_co AND (v_eff->>'hora_checkout')::time <> v_co)
           OR (v_need_ci AND (v_eff->>'hora_checkin')::time  <> v_ci) THEN
          RAISE EXCEPTION 'estricto_no_efectivo' USING ERRCODE = '45000',
            DETAIL = jsonb_build_object('error','override_no_aplicado_efectivamente','clase','efecto_no_aplicado','bordes',v_bordes,'id_cabana', rec.cab, 'fecha', rec.fecha,
              'esperado', jsonb_strip_nulls(jsonb_build_object('hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt)),
              'obtenido', jsonb_build_object('hora_checkout', v_eff->'hora_checkout', 'hora_checkin', v_eff->'hora_checkin'))::text;
        END IF;
      END LOOP;
    EXCEPTION
      WHEN SQLSTATE '45000' THEN
        GET STACKED DIAGNOSTICS v_detalle_txt = PG_EXCEPTION_DETAIL;
        v_verd := v_detalle_txt::jsonb;
        RETURN jsonb_build_object('ok', false, 'error', v_verd->>'error', 'bordes', v_bordes, 'alcance_solicitado', v_alcance,
          'id_cabana', v_verd->'id_cabana', 'fecha', v_verd->'fecha', 'detalle_validador', v_verd);
    END;
    RETURN jsonb_build_object('ok', true, 'bordes', v_bordes, 'alcance_solicitado', v_alcance, 'modo_aplicacion_real', v_modo,
      'fecha_desde', v_fecha, 'fecha_hasta', v_fecha_hasta, 'hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt,
      'gap_minutos', CASE WHEN v_bordes='ambos' THEN v_gap ELSE NULL END,
      'cabanas_aplicadas', v_aplicadas, 'cabanas_excluidas', '[]'::jsonb, 'overrides_creados', v_creados);

  -- ============================================================
  -- Rama 2: global_estricto -> override(s) GLOBAL(es) real(es) (all-or-nothing)
  -- ============================================================
  ELSIF v_alcance = 'global_estricto' THEN
    BEGIN
      v_creados_obj := jsonb_build_object('id_cabana', NULL);
      IF v_need_co THEN
        v_soc := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkout:global' END;
        INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
        VALUES (v_fecha, v_fecha_hasta, NULL, 'hora_checkout', v_co_txt, v_motivo, v_creado_por, true, v_soc) RETURNING id_override INTO v_ovc;
        v_creados_obj := v_creados_obj || jsonb_build_object('id_override_checkout', v_ovc);
      END IF;
      IF v_need_ci THEN
        v_sic := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkin:global' END;
        INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
        VALUES (v_fecha, v_fecha_hasta, NULL, 'hora_checkin', v_ci_txt, v_motivo, v_creado_por, true, v_sic) RETURNING id_override INTO v_ovi;
        v_creados_obj := v_creados_obj || jsonb_build_object('id_override_checkin', v_ovi);
      END IF;
      FOR rec IN
        SELECT c.id_cabana AS cab, g::date AS fecha
        FROM cabanas c
        CROSS JOIN LATERAL generate_series(v_fecha, COALESCE(v_fecha_hasta, v_fecha), interval '1 day') AS g
        WHERE c.activa
      LOOP
        v_verd := validar_estado_override(rec.cab, rec.fecha);
        IF NOT (v_verd->>'ok')::boolean THEN
          RAISE EXCEPTION 'global_estado_fallo' USING ERRCODE = '45000', DETAIL = v_verd::text;
        END IF;
        v_eff := resolver_horario(rec.cab, rec.fecha);
        IF (v_eff->>'ok')::boolean IS NOT TRUE
           OR (v_need_co AND (v_eff->>'hora_checkout')::time <> v_co)
           OR (v_need_ci AND (v_eff->>'hora_checkin')::time  <> v_ci) THEN
          RAISE EXCEPTION 'global_no_efectivo' USING ERRCODE = '45000',
            DETAIL = jsonb_build_object('error','override_no_aplicado_efectivamente','clase','efecto_no_aplicado','bordes',v_bordes,'id_cabana', rec.cab, 'fecha', rec.fecha,
              'esperado', jsonb_strip_nulls(jsonb_build_object('hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt)),
              'obtenido', jsonb_build_object('hora_checkout', v_eff->'hora_checkout', 'hora_checkin', v_eff->'hora_checkin'))::text;
        END IF;
      END LOOP;
      v_creados   := jsonb_build_array(v_creados_obj);
      v_aplicadas := COALESCE((SELECT jsonb_agg(id_cabana ORDER BY id_cabana) FROM cabanas WHERE activa), '[]'::jsonb);
    EXCEPTION
      WHEN SQLSTATE '45000' THEN
        GET STACKED DIAGNOSTICS v_detalle_txt = PG_EXCEPTION_DETAIL;
        v_verd := v_detalle_txt::jsonb;
        RETURN jsonb_build_object('ok', false, 'error', v_verd->>'error', 'bordes', v_bordes, 'alcance_solicitado', v_alcance,
          'id_cabana', v_verd->'id_cabana', 'fecha', v_verd->'fecha', 'detalle_validador', v_verd);
    END;
    RETURN jsonb_build_object('ok', true, 'bordes', v_bordes, 'alcance_solicitado', v_alcance, 'modo_aplicacion_real', 'global_real',
      'fecha_desde', v_fecha, 'fecha_hasta', v_fecha_hasta, 'hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt,
      'gap_minutos', CASE WHEN v_bordes='ambos' THEN v_gap ELSE NULL END,
      'cabanas_aplicadas', v_aplicadas, 'cabanas_excluidas', '[]'::jsonb, 'overrides_creados', v_creados);

  -- ============================================================
  -- Rama 3: grupo_posibles / todas_posibles -> subtransaccion POR cabana
  -- ============================================================
  ELSE
    FOREACH v_cab IN ARRAY v_targets LOOP
      BEGIN
        v_creados_obj := jsonb_build_object('id_cabana', v_cab);
        IF v_need_co THEN
          v_soc := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkout:' || v_cab::text END;
          INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
          VALUES (v_fecha, v_fecha_hasta, v_cab, 'hora_checkout', v_co_txt, v_motivo, v_creado_por, true, v_soc) RETURNING id_override INTO v_ovc;
          v_creados_obj := v_creados_obj || jsonb_build_object('id_override_checkout', v_ovc);
        END IF;
        IF v_need_ci THEN
          v_sic := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkin:' || v_cab::text END;
          INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
          VALUES (v_fecha, v_fecha_hasta, v_cab, 'hora_checkin', v_ci_txt, v_motivo, v_creado_por, true, v_sic) RETURNING id_override INTO v_ovi;
          v_creados_obj := v_creados_obj || jsonb_build_object('id_override_checkin', v_ovi);
        END IF;
        FOR rec IN
          SELECT g::date AS fecha
          FROM generate_series(v_fecha, COALESCE(v_fecha_hasta, v_fecha), interval '1 day') AS g
        LOOP
          v_verd := validar_estado_override(v_cab, rec.fecha);
          IF NOT (v_verd->>'ok')::boolean THEN
            RAISE EXCEPTION 'cabana_excluida' USING ERRCODE = '45000', DETAIL = v_verd::text;
          END IF;
          v_eff := resolver_horario(v_cab, rec.fecha);
          IF (v_eff->>'ok')::boolean IS NOT TRUE
             OR (v_need_co AND (v_eff->>'hora_checkout')::time <> v_co)
             OR (v_need_ci AND (v_eff->>'hora_checkin')::time  <> v_ci) THEN
            RAISE EXCEPTION 'cabana_no_efectiva' USING ERRCODE = '45000',
              DETAIL = jsonb_build_object('error','override_no_aplicado_efectivamente','clase','efecto_no_aplicado','bordes',v_bordes,'id_cabana', v_cab, 'fecha', rec.fecha,
                'esperado', jsonb_strip_nulls(jsonb_build_object('hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt)),
                'obtenido', jsonb_build_object('hora_checkout', v_eff->'hora_checkout', 'hora_checkin', v_eff->'hora_checkin'))::text;
          END IF;
        END LOOP;
        v_aplicadas := v_aplicadas || to_jsonb(v_cab);
        v_creados   := v_creados   || v_creados_obj;
      EXCEPTION
        WHEN SQLSTATE '45000' THEN
          GET STACKED DIAGNOSTICS v_detalle_txt = PG_EXCEPTION_DETAIL;
          v_verd := v_detalle_txt::jsonb;
          v_excluidas := v_excluidas || jsonb_build_object('id_cabana', v_cab, 'error', v_verd->>'error', 'detalle', v_verd);
      END;
    END LOOP;

    IF jsonb_array_length(v_aplicadas) = 0 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'sin_cabanas_aplicables', 'bordes', v_bordes, 'alcance_solicitado', v_alcance,
        'cabanas_excluidas', v_excluidas);
    END IF;
    RETURN jsonb_build_object('ok', true, 'bordes', v_bordes, 'alcance_solicitado', v_alcance, 'modo_aplicacion_real', 'expandido_por_cabana',
      'fecha_desde', v_fecha, 'fecha_hasta', v_fecha_hasta, 'hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt,
      'gap_minutos', CASE WHEN v_bordes='ambos' THEN v_gap ELSE NULL END,
      'cabanas_aplicadas', v_aplicadas, 'cabanas_excluidas', v_excluidas, 'overrides_creados', v_creados);
  END IF;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.crear_override_horario_puntual(jsonb) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.crear_override_horario_puntual(jsonb) IS
  'Guard horarios (F). Alta unificada de override horario puntual. REEMPLAZA a crear_paquete_dia_especial (S3). Eje bordes: checkin | checkout | ambos. checkout/checkin insertan y validan EFECTO SOLO su borde (prohiben la hora del borde contrario => borde_horas_incompatibles); ambos = semantica S3 (checkout req, checkin derivado checkout+gap o explicito, gap_minutos>=120 validado). Alcances producto {cabana, grupo_estricto, todas_posibles} + capacidad interna {grupo_posibles, global_estricto} (superset de S3). Ramas: cabana/grupo_estricto all-or-nothing per-cabana; global_estricto override(s) global(es) real(es); grupo_posibles/todas_posibles subtransaccion por cabana (aplica validas+efectivas, excluye resto con reporte; sin_cabanas_aplicables si ninguna). Valida estado FINAL con validar_estado_override (S0) y EFECTO restringido al/los borde(s) solicitado(s) via resolver_horario => override_no_aplicado_efectivamente (clase efecto_no_aplicado; reemplaza paquete_no_aplicado_efectivamente). Rango: fecha_hasta>=fecha si no rango_invalido. Toma pg_advisory_xact_lock(10,0); subtransacciones BEGIN..EXCEPTION; created_at/id_override no son parametros; source_event deriva hijos por borde <source>:checkout|checkin:<id_cabana|global>. NO usa crear_override_horario (S2). El trigger diferido trg_ov_guard (S1) revalida en commit. Errores: payload_invalido, bordes_no_soportado, borde_horas_incompatibles, rango_invalido, alcance_no_soportado, cabana_no_encontrada, ids_cabanas_invalidos, sin_cabanas_aplicables, override_no_aplicado_efectivamente, override_pisa_reserva, override_pisa_prereserva, override_incompatible_same_day, override_hora_invalido. Fase B1.3-F.';

DO $post$
DECLARE r text; v_bad int := 0;
BEGIN
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r, 'public.crear_override_horario_puntual(jsonb)', 'EXECUTE') THEN
      v_bad := v_bad + 1;
    END IF;
  END LOOP;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'F-POST-ACL: privilegios EXECUTE indebidos = %. Abortando.', v_bad;
  END IF;
  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'F-POST: crear_paquete_dia_especial deberia estar ausente tras el reemplazo. Abortando.';
  END IF;
  RAISE NOTICE 'F instalada. S3 reemplazada. ACL owner-only OK.';
END $post$;

COMMIT;

SELECT md5(pg_get_functiondef('public.crear_override_horario_puntual(jsonb)'::regprocedure)) AS crear_override_puntual_fp;
