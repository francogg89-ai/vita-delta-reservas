-- =====================================================================
-- HORARIOS_GUARD_S2_FUNCION_TEST.sql
-- Sub-bloque S2: puerta sancionada simple crear_override_horario(jsonb).
-- ALCANCE: SOLO TEST. NO OPS/canonico/gateway/frontend/workflows. Sin acuñar D-*/L-*.
--
-- Da de alta UN override horario individual (un solo tipo_override por llamada), por cabaña
-- o global estricto. NO resuelve paquetes checkout+checkin, ni grupo, ni todas_posibles (S3).
-- S2 restringe tipo_override a hora_checkin / hora_checkout.
--
-- Patron (obligatorio): lock (10,0) primero -> parsear payload -> validar requeridos ->
--   INSERT tentativo -> validar pares afectados con validadores S0 (en subtransaccion
--   BEGIN..EXCEPTION) -> si ok, persiste y devuelve {ok:true, id_override, ...}; si falla
--   validacion esperada, revierte SOLO el insert tentativo y devuelve {ok:false, error, ...};
--   errores inesperados propagan y abortan todo. El trigger diferido S1 (trg_ov_guard) queda
--   como red final no evitable y revalida en el commit.
-- Metodo: CREATE OR REPLACE (idempotente; auto-RLS OFF en TEST). REVOKE espejo Bloque 23.
-- Correr el script COMPLETO (L-8A-01).
-- =====================================================================

BEGIN;

-- ---- GATE anti-OPS + dependencias R0/S0/S1 ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM configuracion_general WHERE clave = 'ambiente');
  v_res text; v_odr text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN RAISE EXCEPTION 'GATE S2: ambiente=% (esperado test).', v_amb; END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN RAISE EXCEPTION 'GATE S2: schema=% (esperado public).', current_schema(); END IF;
  v_res := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN RAISE EXCEPTION 'GATE S2: resolver=% (esperado 58d75c1b).', v_res; END IF;
  v_odr := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN RAISE EXCEPTION 'GATE S2: ODR=% (esperado 37009a32154f93b80520500c0f15b46b).', v_odr; END IF;
  IF to_regprocedure('public.validar_estado_horario_final(bigint,date)') IS NULL
     OR to_regprocedure('public.validar_no_eventos_comprometidos(bigint,date)') IS NULL
     OR to_regprocedure('public.validar_estado_override(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'GATE S2: faltan validadores S0.';
  END IF;
  IF to_regprocedure('public.trg_guard_overrides()') IS NULL THEN
    RAISE EXCEPTION 'GATE S2: falta trg_guard_overrides() (S1).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                 WHERE c.relname='overrides_operativos' AND t.tgname='trg_ov_guard' AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION 'GATE S2: falta el constraint trigger trg_ov_guard (S1).';
  END IF;
  RAISE NOTICE 'GATE S2 OK: test/public, resolver=58d75c1b, ODR=37009a32, validadores S0 + trigger S1 presentes.';
END
$gate$;

CREATE OR REPLACE FUNCTION crear_override_horario(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
AS $$
DECLARE
  v_fecha_desde date;
  v_fecha_hasta date   := NULL;
  v_id_cabana   bigint := NULL;
  v_tipo        text;
  v_valor       text;
  v_motivo      text;
  v_creado_por  text;
  v_activo      boolean := true;
  v_source      text   := NULL;
  v_id_override bigint;
  v_verd        jsonb;
  v_detalle_txt text;
  v_alcance     text;
  rec           record;
BEGIN
  -- Capa 0: lock global de disponibilidad SIEMPRE primero (antes de validar o insertar).
  PERFORM pg_advisory_xact_lock(10, 0);

  -- (1) estructura del payload
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'payload no es objeto jsonb');
  END IF;

  -- (2) columnas que NO son parametros (las asigna la DB)
  IF (p_payload ? 'created_at') OR (p_payload ? 'id_override') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido',
      'detalle', 'created_at/id_override no son parametros del payload; los asigna la DB');
  END IF;

  -- (3) requeridos presentes y no nulos
  IF (p_payload->>'fecha_desde')  IS NULL
     OR (p_payload->>'tipo_override') IS NULL
     OR (p_payload->>'valor')      IS NULL
     OR (p_payload->>'motivo')     IS NULL
     OR (p_payload->>'creado_por') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido',
      'detalle', 'faltan requeridos: fecha_desde, tipo_override, valor, motivo, creado_por');
  END IF;

  -- (4) casts tipados; errores de cast (fecha/bigint/boolean) => payload_invalido
  BEGIN
    v_fecha_desde := (p_payload->>'fecha_desde')::date;
    IF (p_payload ? 'fecha_hasta') AND (p_payload->>'fecha_hasta') IS NOT NULL THEN
      v_fecha_hasta := (p_payload->>'fecha_hasta')::date;
    END IF;
    IF (p_payload ? 'id_cabana') AND (p_payload->>'id_cabana') IS NOT NULL THEN
      v_id_cabana := (p_payload->>'id_cabana')::bigint;
    END IF;
    IF (p_payload ? 'activo') AND (p_payload->>'activo') IS NOT NULL THEN
      v_activo := (p_payload->>'activo')::boolean;
    END IF;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow OR invalid_datetime_format THEN
      RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'cast de campo fallido (fecha/id_cabana/activo)');
  END;

  v_tipo       := p_payload->>'tipo_override';
  v_valor      := p_payload->>'valor';
  v_motivo     := p_payload->>'motivo';
  v_creado_por := p_payload->>'creado_por';
  IF (p_payload ? 'source_event') AND (p_payload->>'source_event') IS NOT NULL THEN
    v_source := p_payload->>'source_event';
  END IF;

  -- (5) coherencia de fechas (ademas del CHECK de tabla, para error limpio)
  IF v_fecha_hasta IS NOT NULL AND v_fecha_hasta < v_fecha_desde THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'fecha_hasta < fecha_desde');
  END IF;

  -- (6) tipo soportado (S2: solo horarios)
  IF v_tipo NOT IN ('hora_checkin', 'hora_checkout') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'tipo_override_no_soportado',
      'tipo_override', v_tipo, 'detalle', 'S2 solo admite hora_checkin/hora_checkout');
  END IF;

  -- (7) cabana existe (si es especifica); NULL = global estricto
  v_alcance := CASE WHEN v_id_cabana IS NULL THEN 'global_estricto' ELSE 'cabana' END;
  IF v_id_cabana IS NOT NULL AND NOT EXISTS (SELECT 1 FROM cabanas WHERE id_cabana = v_id_cabana) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_encontrada', 'id_cabana', v_id_cabana);
  END IF;

  -- (8) INSERT tentativo + validacion S0 en subtransaccion.
  BEGIN
    INSERT INTO overrides_operativos
      (fecha_desde, fecha_hasta, id_cabana, tipo_override, valor, motivo, creado_por, activo, source_event)
    VALUES
      (v_fecha_desde, v_fecha_hasta, v_id_cabana, v_tipo, v_valor, v_motivo, v_creado_por, v_activo, v_source)
    RETURNING id_override INTO v_id_override;

    -- Solo validar si queda ACTIVO (inactivo no afecta horarios; el trigger S1 tambien lo saltea).
    IF v_activo THEN
      FOR rec IN
        -- applied_set: (esa cabaña, o todas las activas si global) x [fecha_desde, COALESCE(fecha_hasta, fecha_desde)]  (R0)
        SELECT c.id_cabana AS id_cabana, g::date AS fecha
        FROM cabanas c
        CROSS JOIN LATERAL generate_series(v_fecha_desde, COALESCE(v_fecha_hasta, v_fecha_desde), interval '1 day') AS g
        WHERE (v_id_cabana IS NULL AND c.activa) OR (c.id_cabana = v_id_cabana)
      LOOP
        v_verd := validar_estado_override(rec.id_cabana, rec.fecha);
        IF NOT (v_verd->>'ok')::boolean THEN
          -- Falla esperada: llevar el verdict en DETAIL y forzar rollback de la subtransaccion.
          RAISE EXCEPTION 'validacion_override_fallida'
            USING ERRCODE = '45000', DETAIL = v_verd::text;
        END IF;
      END LOOP;
    END IF;
    -- Aca: valido (o inactivo). El insert tentativo persiste.
  EXCEPTION
    WHEN SQLSTATE '45000' THEN
      -- El insert tentativo se revirtio con la subtransaccion. Recuperar el verdict del DETAIL.
      GET STACKED DIAGNOSTICS v_detalle_txt = PG_EXCEPTION_DETAIL;
      v_verd := v_detalle_txt::jsonb;
      RETURN jsonb_build_object(
        'ok', false,
        'error', v_verd->>'error',
        'id_cabana', v_id_cabana,
        'alcance', v_alcance,
        'tipo_override', v_tipo,
        'fecha_desde', v_fecha_desde,
        'fecha_hasta', v_fecha_hasta,
        'detalle_validador', v_verd
      );
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'id_override', v_id_override,
    'id_cabana', v_id_cabana,
    'alcance', v_alcance,
    'tipo_override', v_tipo,
    'valor', v_valor,
    'fecha_desde', v_fecha_desde,
    'fecha_hasta', v_fecha_hasta,
    'activo', v_activo,
    'nota', CASE WHEN NOT v_activo
                 THEN 'insertado inactivo: no afecta horarios ni dispara validacion (se revalida al activarse)'
                 ELSE NULL END
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.crear_override_horario(jsonb) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.crear_override_horario(jsonb) IS
  'S2 guard horarios. Puerta sancionada simple: alta de UN override horario individual (un solo tipo_override: hora_checkin/hora_checkout), por cabaña (id_cabana) o global estricto (id_cabana NULL = todas las cabañas activas). Toma pg_advisory_xact_lock(10,0) primero; parsea/valida payload; INSERT tentativo; valida pares afectados con validar_estado_override (S0) en subtransaccion; ok:true persiste, ok:false revierte solo el insert. Errores parseables: payload_invalido, tipo_override_no_soportado, cabana_no_encontrada, override_pisa_reserva, override_pisa_prereserva, override_incompatible_same_day, override_hora_invalido. created_at/id_override NO son parametros. NO hace paquetes/grupo/todas_posibles (S3). El trigger diferido trg_ov_guard (S1) revalida en commit. Fase B - guard overrides.';

COMMIT;

-- ---- Confirmacion ----
SELECT to_regprocedure('public.crear_override_horario(jsonb)') IS NOT NULL AS funcion_ok;
