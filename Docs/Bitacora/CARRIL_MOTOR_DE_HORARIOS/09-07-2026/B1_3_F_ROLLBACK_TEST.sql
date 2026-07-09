-- =====================================================================
-- B1.3-F - ROLLBACK de crear_override_horario_puntual  ->  restaura S3
-- =====================================================================
-- Red de seguridad de F. Revierte SOLO F: DROP crear_override_horario_puntual + restaura
-- crear_paquete_dia_especial (S3) con su cuerpo original, compatible con el resolver VIVO
-- actual (wrapper post-A 1bd96c89). NO revierte A ni el resolver semanal. El cuerpo S3
-- llama resolver_horario dinamicamente, por eso NO se re-exige el resolver viejo pre-B1.2 de S3 (D4).
--
-- Gate fail-closed: ambiente=test, schema=public, resolver_horario == 1bd96c89 (wrapper actual),
--   crear_override_horario_puntual PRESENTE (hay algo que revertir), crear_paquete_dia_especial AUSENTE.
-- DROP F + CREATE S3 (no OR REPLACE) + REVOKE owner-only + COMMENT. Postcheck: S3 presente, F ausente,
-- ACL de S3 owner-only. Ejecutar el script ENTERO.
-- =====================================================================

BEGIN;

DO $gate$
DECLARE
  c_fp_wrap CONSTANT text := '1bd96c89e587b15582fd7b2e29ae7e18';
  v_amb text;
BEGIN
  PERFORM pg_advisory_xact_lock(10, 0);
  v_amb := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  IF COALESCE(v_amb, '') <> 'test' THEN
    RAISE EXCEPTION 'F-RB-GATE: ambiente=% (esperado test). Abortando.', COALESCE(v_amb, '<null>');
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'F-RB-GATE: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('public.resolver_horario(bigint,date)') IS NULL
     OR md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure)) <> c_fp_wrap THEN
    RAISE EXCEPTION 'F-RB-GATE: resolver_horario ausente o fingerprint distinto del esperado (post-A). Abortando.';
  END IF;
  IF to_regprocedure('public.crear_override_horario_puntual(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'F-RB-GATE: crear_override_horario_puntual ausente (nada que revertir). Abortando.';
  END IF;
  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'F-RB-GATE: crear_paquete_dia_especial ya existe (estado inesperado). Abortando.';
  END IF;
  RAISE NOTICE 'F-RB-GATE OK: test/public, resolver post-A, F presente, S3 ausente.';
END $gate$;

DROP FUNCTION public.crear_override_horario_puntual(jsonb);

-- ===== Restauracion del cuerpo original de S3 (crear_paquete_dia_especial) =====
CREATE FUNCTION public.crear_paquete_dia_especial(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
AS $$
DECLARE
  v_fecha        date;
  v_fecha_hasta  date := NULL;
  v_co           time;
  v_ci           time := NULL;
  v_gap          int  := 120;
  v_alcance      text;
  v_id_cabana    bigint := NULL;
  v_ids          bigint[] := NULL;
  v_targets      bigint[] := ARRAY[]::bigint[];
  v_motivo       text;
  v_creado_por   text;
  v_source       text := NULL;
  v_co_txt       text;
  v_ci_txt       text;
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
  v_cab          bigint;
  rec            record;
BEGIN
  -- Capa 0: lock global primero.
  PERFORM pg_advisory_xact_lock(10, 0);

  -- ===== Validacion de payload (antes de insertar) =====
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'payload no es objeto jsonb');
  END IF;
  IF (p_payload ? 'created_at') OR (p_payload ? 'id_override') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'created_at/id_override no son parametros; los asigna la DB');
  END IF;
  IF (p_payload->>'fecha') IS NULL OR (p_payload->>'hora_checkout') IS NULL OR (p_payload->>'alcance') IS NULL
     OR (p_payload->>'motivo') IS NULL OR (p_payload->>'creado_por') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'faltan requeridos: fecha, hora_checkout, alcance, motivo, creado_por');
  END IF;

  BEGIN
    v_fecha := (p_payload->>'fecha')::date;
    IF (p_payload ? 'fecha_hasta') AND (p_payload->>'fecha_hasta') IS NOT NULL THEN v_fecha_hasta := (p_payload->>'fecha_hasta')::date; END IF;
    v_co := (p_payload->>'hora_checkout')::time;
    IF (p_payload ? 'gap_minutos') AND (p_payload->>'gap_minutos') IS NOT NULL THEN v_gap := (p_payload->>'gap_minutos')::int; END IF;
    IF (p_payload ? 'hora_checkin') AND (p_payload->>'hora_checkin') IS NOT NULL THEN v_ci := (p_payload->>'hora_checkin')::time; END IF;
    IF (p_payload ? 'id_cabana') AND (p_payload->>'id_cabana') IS NOT NULL THEN v_id_cabana := (p_payload->>'id_cabana')::bigint; END IF;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow OR invalid_datetime_format THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'cast de campo fallido (fecha/hora/gap/id_cabana)');
  END;

  v_alcance     := p_payload->>'alcance';
  v_motivo      := p_payload->>'motivo';
  v_creado_por  := p_payload->>'creado_por';
  IF (p_payload ? 'source_event') AND (p_payload->>'source_event') IS NOT NULL THEN v_source := p_payload->>'source_event'; END IF;

  IF v_fecha_hasta IS NOT NULL AND v_fecha_hasta < v_fecha THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'fecha_hasta < fecha');
  END IF;

  -- gap: default 120; < 120 => payload_invalido (la barrera DB exige >= 2h; no dependemos de S0/S1)
  IF v_gap < 120 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'gap_minutos < 120');
  END IF;

  -- hora_checkin: derivar o validar
  IF v_ci IS NULL THEN
    v_ci := v_co + make_interval(mins => v_gap);
  END IF;
  IF v_ci <= v_co OR (v_ci - v_co) < make_interval(mins => v_gap) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'hora_checkin <= hora_checkout (cruza medianoche) o gap insuficiente');
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
    -- ids_cabanas debe ser array no vacio (contrato parseable; validado ANTES de jsonb_array_elements_text/v_ids).
    -- jsonb_typeof(...) IS DISTINCT FROM 'array' cubre en una: clave ausente (SQL NULL -> jsonb_typeof NULL),
    -- JSON null ('null'), y no-array (object/string/number). Recien tras confirmar array se llama
    -- jsonb_array_length (que sobre un escalar/objeto tiraria error), sin depender del short-circuit del OR.
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
    -- duplicados => ids_cabanas_invalidos (ids_cabanas representa un conjunto de cabanas objetivo)
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

  v_co_txt := to_char(v_co, 'HH24:MI');
  v_ci_txt := to_char(v_ci, 'HH24:MI');

  -- ============================================================
  -- Rama 1: cabana / grupo_estricto -> all-or-nothing, per-cabana
  -- ============================================================
  IF v_alcance IN ('cabana','grupo_estricto') THEN
    v_modo := CASE WHEN v_alcance = 'cabana' THEN 'cabana_unica' ELSE 'expandido_por_cabana' END;
    BEGIN
      FOREACH v_cab IN ARRAY v_targets LOOP
        v_soc := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkout:' || v_cab::text END;
        v_sic := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkin:'  || v_cab::text END;
        INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
        VALUES (v_fecha, v_fecha_hasta, v_cab, 'hora_checkout', v_co_txt, v_motivo, v_creado_por, true, v_soc) RETURNING id_override INTO v_ovc;
        INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
        VALUES (v_fecha, v_fecha_hasta, v_cab, 'hora_checkin',  v_ci_txt, v_motivo, v_creado_por, true, v_sic) RETURNING id_override INTO v_ovi;
        v_creados   := v_creados   || jsonb_build_object('id_cabana', v_cab, 'id_override_checkout', v_ovc, 'id_override_checkin', v_ovi);
        v_aplicadas := v_aplicadas || to_jsonb(v_cab);
      END LOOP;
      -- validar estado FINAL + EFECTO de todos los pares (ambas mitades ya presentes)
      FOR rec IN
        SELECT t AS cab, g::date AS fecha
        FROM unnest(v_targets) AS t
        CROSS JOIN LATERAL generate_series(v_fecha, COALESCE(v_fecha_hasta, v_fecha), interval '1 day') AS g
      LOOP
        v_verd := validar_estado_override(rec.cab, rec.fecha);
        IF NOT (v_verd->>'ok')::boolean THEN
          RAISE EXCEPTION 'paquete_estricto_fallo' USING ERRCODE = '45000', DETAIL = v_verd::text;
        END IF;
        v_eff := resolver_horario(rec.cab, rec.fecha);
        IF (v_eff->>'ok')::boolean IS NOT TRUE
           OR (v_eff->>'hora_checkout')::time <> v_co
           OR (v_eff->>'hora_checkin')::time  <> v_ci THEN
          RAISE EXCEPTION 'paquete_no_aplicado' USING ERRCODE = '45000',
            DETAIL = jsonb_build_object('error','paquete_no_aplicado_efectivamente','id_cabana', rec.cab, 'fecha', rec.fecha,
              'esperado', jsonb_build_object('hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt),
              'obtenido', jsonb_build_object('hora_checkout', v_eff->'hora_checkout', 'hora_checkin', v_eff->'hora_checkin'))::text;
        END IF;
      END LOOP;
    EXCEPTION
      WHEN SQLSTATE '45000' THEN
        GET STACKED DIAGNOSTICS v_detalle_txt = PG_EXCEPTION_DETAIL;
        v_verd := v_detalle_txt::jsonb;
        RETURN jsonb_build_object('ok', false, 'error', v_verd->>'error', 'alcance_solicitado', v_alcance,
          'id_cabana', v_verd->'id_cabana', 'fecha', v_verd->'fecha', 'detalle_validador', v_verd);
    END;
    RETURN jsonb_build_object('ok', true, 'alcance_solicitado', v_alcance, 'modo_aplicacion_real', v_modo,
      'fecha_desde', v_fecha, 'fecha_hasta', v_fecha_hasta, 'hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt, 'gap_minutos', v_gap,
      'cabanas_aplicadas', v_aplicadas, 'cabanas_excluidas', '[]'::jsonb, 'overrides_creados', v_creados);

  -- ============================================================
  -- Rama 2: global_estricto -> dos overrides GLOBALES reales (all-or-nothing)
  -- ============================================================
  ELSIF v_alcance = 'global_estricto' THEN
    BEGIN
      v_soc := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkout:global' END;
      v_sic := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkin:global'  END;
      INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
      VALUES (v_fecha, v_fecha_hasta, NULL, 'hora_checkout', v_co_txt, v_motivo, v_creado_por, true, v_soc) RETURNING id_override INTO v_ovc;
      INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
      VALUES (v_fecha, v_fecha_hasta, NULL, 'hora_checkin',  v_ci_txt, v_motivo, v_creado_por, true, v_sic) RETURNING id_override INTO v_ovi;
      -- validar estado FINAL + EFECTO de todas las cabanas activas x rango.
      -- Clave: un override ESPECIFICO de cabana preexistente sombrea al global -> el efecto no se
      -- cumple para esa cabana -> global_estricto debe fallar y no dejar los globales.
      FOR rec IN
        SELECT c.id_cabana AS cab, g::date AS fecha
        FROM cabanas c
        CROSS JOIN LATERAL generate_series(v_fecha, COALESCE(v_fecha_hasta, v_fecha), interval '1 day') AS g
        WHERE c.activa
      LOOP
        v_verd := validar_estado_override(rec.cab, rec.fecha);
        IF NOT (v_verd->>'ok')::boolean THEN
          RAISE EXCEPTION 'paquete_global_fallo' USING ERRCODE = '45000', DETAIL = v_verd::text;
        END IF;
        v_eff := resolver_horario(rec.cab, rec.fecha);
        IF (v_eff->>'ok')::boolean IS NOT TRUE
           OR (v_eff->>'hora_checkout')::time <> v_co
           OR (v_eff->>'hora_checkin')::time  <> v_ci THEN
          RAISE EXCEPTION 'paquete_no_aplicado' USING ERRCODE = '45000',
            DETAIL = jsonb_build_object('error','paquete_no_aplicado_efectivamente','id_cabana', rec.cab, 'fecha', rec.fecha,
              'esperado', jsonb_build_object('hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt),
              'obtenido', jsonb_build_object('hora_checkout', v_eff->'hora_checkout', 'hora_checkin', v_eff->'hora_checkin'))::text;
        END IF;
      END LOOP;
      v_creados   := jsonb_build_array(jsonb_build_object('id_cabana', NULL, 'id_override_checkout', v_ovc, 'id_override_checkin', v_ovi));
      v_aplicadas := COALESCE((SELECT jsonb_agg(id_cabana ORDER BY id_cabana) FROM cabanas WHERE activa), '[]'::jsonb);
    EXCEPTION
      WHEN SQLSTATE '45000' THEN
        GET STACKED DIAGNOSTICS v_detalle_txt = PG_EXCEPTION_DETAIL;
        v_verd := v_detalle_txt::jsonb;
        RETURN jsonb_build_object('ok', false, 'error', v_verd->>'error', 'alcance_solicitado', v_alcance,
          'id_cabana', v_verd->'id_cabana', 'fecha', v_verd->'fecha', 'detalle_validador', v_verd);
    END;
    RETURN jsonb_build_object('ok', true, 'alcance_solicitado', v_alcance, 'modo_aplicacion_real', 'global_real',
      'fecha_desde', v_fecha, 'fecha_hasta', v_fecha_hasta, 'hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt, 'gap_minutos', v_gap,
      'cabanas_aplicadas', v_aplicadas, 'cabanas_excluidas', '[]'::jsonb, 'overrides_creados', v_creados);

  -- ============================================================
  -- Rama 3: grupo_posibles / todas_posibles -> subtransaccion POR cabana
  -- ============================================================
  ELSE
    FOREACH v_cab IN ARRAY v_targets LOOP
      BEGIN
        v_soc := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkout:' || v_cab::text END;
        v_sic := CASE WHEN v_source IS NULL THEN NULL ELSE v_source || ':checkin:'  || v_cab::text END;
        INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
        VALUES (v_fecha, v_fecha_hasta, v_cab, 'hora_checkout', v_co_txt, v_motivo, v_creado_por, true, v_soc) RETURNING id_override INTO v_ovc;
        INSERT INTO overrides_operativos (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
        VALUES (v_fecha, v_fecha_hasta, v_cab, 'hora_checkin',  v_ci_txt, v_motivo, v_creado_por, true, v_sic) RETURNING id_override INTO v_ovi;
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
             OR (v_eff->>'hora_checkout')::time <> v_co
             OR (v_eff->>'hora_checkin')::time  <> v_ci THEN
            RAISE EXCEPTION 'cabana_no_efectiva' USING ERRCODE = '45000',
              DETAIL = jsonb_build_object('error','paquete_no_aplicado_efectivamente','id_cabana', v_cab, 'fecha', rec.fecha,
                'esperado', jsonb_build_object('hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt),
                'obtenido', jsonb_build_object('hora_checkout', v_eff->'hora_checkout', 'hora_checkin', v_eff->'hora_checkin'))::text;
          END IF;
        END LOOP;
        -- la cabana paso: conserva sus dos overrides
        v_aplicadas := v_aplicadas || to_jsonb(v_cab);
        v_creados   := v_creados   || jsonb_build_object('id_cabana', v_cab, 'id_override_checkout', v_ovc, 'id_override_checkin', v_ovi);
      EXCEPTION
        WHEN SQLSTATE '45000' THEN
          -- solo esta cabana se revirtio; reportar exclusion
          GET STACKED DIAGNOSTICS v_detalle_txt = PG_EXCEPTION_DETAIL;
          v_verd := v_detalle_txt::jsonb;
          v_excluidas := v_excluidas || jsonb_build_object('id_cabana', v_cab, 'error', v_verd->>'error', 'detalle', v_verd);
      END;
    END LOOP;

    IF jsonb_array_length(v_aplicadas) = 0 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'sin_cabanas_aplicables', 'alcance_solicitado', v_alcance,
        'cabanas_excluidas', v_excluidas);
    END IF;
    RETURN jsonb_build_object('ok', true, 'alcance_solicitado', v_alcance, 'modo_aplicacion_real', 'expandido_por_cabana',
      'fecha_desde', v_fecha, 'fecha_hasta', v_fecha_hasta, 'hora_checkout', v_co_txt, 'hora_checkin', v_ci_txt, 'gap_minutos', v_gap,
      'cabanas_aplicadas', v_aplicadas, 'cabanas_excluidas', v_excluidas, 'overrides_creados', v_creados);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.crear_paquete_dia_especial(jsonb) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.crear_paquete_dia_especial(jsonb) IS
  'S3 guard horarios. Puerta sancionada de paquete de dia especial: override hora_checkout + hora_checkin JUNTOS. Valida (a) estado final valido con validar_estado_override (S0) y (b) EFECTO PRETENDIDO: que resolver_horario devuelva las horas solicitadas para cada cabana/fecha aplicada (postcondicion de precedencia; un override especifico preexistente puede sombrear un paquete global, o uno especifico con created_at posterior) -> si no, error paquete_no_aplicado_efectivamente. NO usa crear_override_horario (S2). Alcances: cabana/grupo_estricto (all-or-nothing per-cabana), global_estricto (dos overrides globales reales si todas las activas quedan validas y efectivas; no expande), grupo_posibles/todas_posibles (subtransaccion por cabana; aplica las validas y efectivas, excluye el resto con reporte; nunca global; sin_cabanas_aplicables si ninguna aplica). Toma pg_advisory_xact_lock(10,0) primero; subtransacciones BEGIN..EXCEPTION. gap_minutos default 120, <120 => payload_invalido; hora_checkin derivada (checkout+gap) o explicita (checkin-checkout>=gap); checkin<=checkout => payload_invalido. ids_cabanas: enteros existentes y sin duplicados (si no => ids_cabanas_invalidos). created_at/id_override NO son parametros; source_event deriva hijos <source>:checkout|checkin:<id_cabana|global>. Errores: payload_invalido, cabana_no_encontrada, ids_cabanas_invalidos, alcance_no_soportado, sin_cabanas_aplicables, paquete_no_aplicado_efectivamente, override_pisa_reserva, override_pisa_prereserva, override_incompatible_same_day, override_hora_invalido. El trigger diferido trg_ov_guard (S1) revalida en commit. Fase B - guard overrides.';

DO $post$
DECLARE r text; v_bad int := 0;
BEGIN
  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'F-RB-POST: crear_paquete_dia_especial no quedo restaurada. Abortando.';
  END IF;
  IF to_regprocedure('public.crear_override_horario_puntual(jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'F-RB-POST: crear_override_horario_puntual deberia estar ausente. Abortando.';
  END IF;
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r, 'public.crear_paquete_dia_especial(jsonb)', 'EXECUTE') THEN v_bad := v_bad + 1; END IF;
  END LOOP;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'F-RB-POST-ACL: privilegios EXECUTE indebidos en S3 = %. Abortando.', v_bad;
  END IF;
  RAISE NOTICE 'Rollback F OK. S3 restaurada, F ausente, ACL owner-only.';
END $post$;

COMMIT;

SELECT to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL AS s3_restaurada,
       to_regprocedure('public.crear_override_horario_puntual(jsonb)') IS NULL AS f_ausente;
