-- =====================================================================
-- HORARIOS_FASEB_B2_RESOLVER_HORARIO_TEST.sql
-- Fase B (Bloque 2) - Motor formal de horarios : resolver_horario() standalone.
-- ALCANCE: SOLO TEST. NO ejecutar en OPS.
-- Funcion PURA / sin writes: lee configuracion_general y overrides_operativos,
-- NO escribe (ni log_cambios). Resuelve la BASE de check-in/check-out para una
-- fecha/cabana (base -> patron domingo -> override global -> override cabana).
-- NO integra con crear_prereserva ni obtener_disponibilidad_rango.
-- NO toca EXCLUDE, modelo [fecha_in, fecha_out), A07/A08, gateway, frontend.
-- HARD de override en 3 etapas: formato estricto HH:MM[:SS] -> cast TIME -> ventana 07:00-22:00.
-- Ejecutar el script completo (sin seleccion parcial).
-- =====================================================================

CREATE OR REPLACE FUNCTION resolver_horario(p_id_cabana BIGINT, p_fecha DATE)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
  v_config       JSONB;
  v_ventana_min  TIME;
  v_ventana_max  TIME;
  v_es_domingo   BOOLEAN := (EXTRACT(DOW FROM p_fecha) = 0);
  v_tipo         TEXT;
  v_base         TIME;
  v_origen       TEXT;
  v_ovr_id       BIGINT;
  v_ovr_valor    TEXT;
  v_ovr_cabana   BOOLEAN;
  v_hora         TIME;
  v_res          JSONB := '{}'::JSONB;
BEGIN
  -- Config (claves de horarios + bordes de ventana). COALESCE con fallback documentado.
  SELECT jsonb_object_agg(clave, valor) INTO v_config
  FROM configuracion_general
  WHERE clave IN (
    'hora_checkin_default','hora_checkin_domingo',
    'hora_checkout_default','hora_checkout_domingo',
    'hora_checkin_max_cliente','hora_checkout_min_cliente'
  );

  -- Ventana absoluta anti-typo: [hora_checkout_min_cliente, hora_checkin_max_cliente] = 07:00-22:00.
  v_ventana_min := COALESCE((v_config->>'hora_checkout_min_cliente')::TIME, TIME '07:00');
  v_ventana_max := COALESCE((v_config->>'hora_checkin_max_cliente')::TIME, TIME '22:00');

  FOREACH v_tipo IN ARRAY ARRAY['hora_checkin','hora_checkout'] LOOP
    -- Paso A: base / patron domingo.
    IF v_es_domingo THEN
      v_base := COALESCE(
        (v_config->>(v_tipo || '_domingo'))::TIME,
        CASE v_tipo WHEN 'hora_checkin' THEN TIME '18:00' ELSE TIME '16:00' END);
      v_origen := 'patron_domingo';
    ELSE
      v_base := COALESCE(
        (v_config->>(v_tipo || '_default'))::TIME,
        CASE v_tipo WHEN 'hora_checkin' THEN TIME '13:00' ELSE TIME '10:00' END);
      v_origen := 'base';
    END IF;

    -- Paso B: override ganador (determinista). fecha_hasta INCLUSIVA. SELECT INTO sin fila => NULL.
    SELECT id_override, valor, (id_cabana IS NOT NULL)
      INTO v_ovr_id, v_ovr_valor, v_ovr_cabana
    FROM overrides_operativos
    WHERE activo
      AND tipo_override = v_tipo
      AND fecha_desde <= p_fecha
      AND (fecha_hasta IS NULL OR fecha_hasta >= p_fecha)
      AND (id_cabana = p_id_cabana OR id_cabana IS NULL)
    ORDER BY (id_cabana IS NOT NULL) DESC, created_at DESC, id_override DESC
    LIMIT 1;

    -- Paso C: aplicar override (con HARD en 3 etapas) o caer a base/patron.
    IF v_ovr_valor IS NOT NULL THEN
      -- HARD 1: formato ESTRICTO HH:MM o HH:MM:SS. PostgreSQL parsea formatos mas laxos
      -- (ej. '7:00' -> 07:00), pero la convencion cerrada solo acepta dos digitos por campo.
      IF v_ovr_valor !~ '^\d{2}:\d{2}(:\d{2})?$' THEN
        RETURN jsonb_build_object(
          'ok', false, 'error', 'override_hora_invalido', 'causa', 'formato_invalido',
          'tipo_override', v_tipo, 'id_override', v_ovr_id, 'valor', v_ovr_valor,
          'ventana_min', v_ventana_min, 'ventana_max', v_ventana_max);
      END IF;
      -- HARD 2: cast a TIME. Ya paso el formato; rangos invalidos (ej. '25:99') caen aca.
      BEGIN
        v_hora := v_ovr_valor::TIME;
      EXCEPTION WHEN data_exception THEN
        RETURN jsonb_build_object(
          'ok', false, 'error', 'override_hora_invalido', 'causa', 'cast_invalido',
          'tipo_override', v_tipo, 'id_override', v_ovr_id, 'valor', v_ovr_valor,
          'ventana_min', v_ventana_min, 'ventana_max', v_ventana_max);
      END;
      -- HARD 3: dentro de la ventana absoluta (inclusiva).
      IF v_hora < v_ventana_min OR v_hora > v_ventana_max THEN
        RETURN jsonb_build_object(
          'ok', false, 'error', 'override_hora_invalido', 'causa', 'fuera_de_ventana',
          'tipo_override', v_tipo, 'id_override', v_ovr_id, 'valor', v_ovr_valor,
          'ventana_min', v_ventana_min, 'ventana_max', v_ventana_max);
      END IF;
      v_origen := CASE WHEN v_ovr_cabana THEN 'override_cabana' ELSE 'override_global' END;
    ELSE
      v_hora := v_base;
    END IF;

    -- Acumular por tipo.
    IF v_tipo = 'hora_checkin' THEN
      v_res := v_res || jsonb_build_object('hora_checkin', v_hora, 'origen_checkin', v_origen);
    ELSE
      v_res := v_res || jsonb_build_object('hora_checkout', v_hora, 'origen_checkout', v_origen);
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok', true) || v_res;
END;
$$;

-- Hardening (espejo Bloque 23): solo el owner ejecuta. Cierra proacl IS NULL => PUBLIC (L-PROMO-06).
REVOKE EXECUTE ON FUNCTION public.resolver_horario(bigint, date) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.resolver_horario(bigint, date) IS
  'Resuelve la base de check-in/check-out para (id_cabana, fecha): base -> patron domingo -> override global -> override por cabana (overrides_operativos, fecha_hasta inclusiva). Funcion PURA (sin writes). Devuelve jsonb {ok:true, hora_checkin, hora_checkout, origen_checkin, origen_checkout} o {ok:false, error:override_hora_invalido, causa:formato_invalido|cast_invalido|fuera_de_ventana, ...}. Override de hora => HARD en 3 etapas: formato estricto HH:MM[:SS], cast a TIME, ventana 07:00-22:00. Fase B - motor de horarios.';
