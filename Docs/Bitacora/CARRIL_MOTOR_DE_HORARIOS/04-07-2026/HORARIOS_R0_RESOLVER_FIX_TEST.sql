-- =====================================================================
-- HORARIOS_R0_RESOLVER_FIX_TEST.sql
-- Pre-bloque R0 (correccion de drift del resolver, NO parte del guard).
-- ALCANCE: SOLO TEST. NO ejecutar en OPS. NO tocar canonico/gateway/frontend/workflows.
-- Sin acuñar D-*/L-*.
--
-- QUE HACE: corrige la semantica de fecha_hasta IS NULL en resolver_horario()
--   para alinearla con Etapa 2 (ARQUITECTURA_ETAPA_2 L373-374/L427: "NULL = solo
--   fecha_desde"). Unico cambio de cuerpo: el predicado de seleccion de override
--   pasa de:
--       AND (fecha_hasta IS NULL OR fecha_hasta >= p_fecha)
--   a:
--       AND p_fecha <= COALESCE(fecha_hasta, fecha_desde)
--   (con fecha_desde <= p_fecha ya en el WHERE => NULL colapsa a p_fecha = fecha_desde).
--   El resto del cuerpo es IDENTICO al vigente (fingerprint 759662b4...).
--
-- METODO: CREATE OR REPLACE FUNCTION (NO DROP+CREATE, NO CASCADE). Justificacion:
--   * La firma (bigint,date)->jsonb NO cambia (solo cambia el cuerpo) => CREATE OR
--     REPLACE aplica sin el fallo de cambio de tipo de retorno.
--   * Preserva OID => ACL/owner/COMMENT sobreviven (DROP+CREATE los resetearia:
--     proacl IS NULL => PUBLIC ejecuta, L-RDEV-01). Igual re-afirmamos REVOKE+COMMENT
--     de forma idempotente (cinturon-y-tiradores).
--   * TEST tiene "Enable automatic RLS = OFF" (L-8A-03/04) => el bug del Dashboard
--     (Supabase confunde variables v_ con tablas y appendea ALTER TABLE ... ENABLE RLS,
--     truncando el SQL, 42601) NO dispara aca. El resolver original ya se aplico con
--     CREATE OR REPLACE en TEST sin incidente. Ref L-CC-07.
--   * No hay dependientes duros (ver PREFLIGHT); los callers (ODR, crear_prereserva)
--     resuelven resolver_horario por nombre en runtime y siguen apuntando al mismo OID.
--   Contingencia: si el editor mostrara 42601 por auto-RLS ON inesperado, fallback al
--   workaround DROP FUNCTION + CREATE FUNCTION en dos runs (L-CC-07). No esperado.
--
-- El aviso "Run without RLS" del editor es ESPERADO y correcto (L-8A-04).
-- Correr el script COMPLETO (sin seleccion parcial; L-8A-01). El ultimo SELECT
--   reporta el fingerprint NUEVO del resolver.
-- =====================================================================

BEGIN;

-- ---- GATE anti-OPS + version esperada (aborta y revierte si no coincide) ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM configuracion_general WHERE clave = 'ambiente');
  v_res text;
  v_odr text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE R0: ambiente=% (esperado test). Abortando fix.', v_amb;
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'GATE R0: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('public.resolver_horario(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'GATE R0: no existe resolver_horario(bigint,date). Abortando.';
  END IF;
  IF to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)') IS NULL THEN
    RAISE EXCEPTION 'GATE R0: no existe obtener_disponibilidad_rango(date,date,bigint). Abortando.';
  END IF;
  v_res := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
  IF v_res IS DISTINCT FROM '759662b4afaed7af426917aa3717b34c' THEN
    RAISE EXCEPTION 'GATE R0: fingerprint resolver ACTUAL=% (esperado 759662b4afaed7af426917aa3717b34c, pre-fix). Abortando.', v_res;
  END IF;
  v_odr := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE R0: fingerprint ODR=% (esperado 37009a32154f93b80520500c0f15b46b). Abortando.', v_odr;
  END IF;
  RAISE NOTICE 'GATE R0 OK: ambiente=test, schema=public, resolver=759662b4 (pre-fix), ODR=37009a32.';
END
$gate$;

-- ---- Correccion del resolver (CREATE OR REPLACE; cuerpo identico salvo 1 predicado) ----
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

    -- Paso B: override ganador (determinista). fecha_hasta inclusiva; NULL = solo fecha_desde
    -- (Etapa 2, correccion R0). SELECT INTO sin fila => NULL.
    SELECT id_override, valor, (id_cabana IS NOT NULL)
      INTO v_ovr_id, v_ovr_valor, v_ovr_cabana
    FROM overrides_operativos
    WHERE activo
      AND tipo_override = v_tipo
      AND fecha_desde <= p_fecha
      AND p_fecha <= COALESCE(fecha_hasta, fecha_desde)
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

-- Hardening (espejo Bloque 23): solo el owner ejecuta. Idempotente / re-afirmado tras el REPLACE.
REVOKE EXECUTE ON FUNCTION public.resolver_horario(bigint, date) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.resolver_horario(bigint, date) IS
  'Resuelve la base de check-in/check-out para (id_cabana, fecha): base -> patron domingo -> override global -> override por cabana (overrides_operativos; fecha_hasta inclusiva, NULL = solo fecha_desde [Etapa 2, correccion R0]). Funcion read-only (sin writes). Devuelve jsonb {ok:true, hora_checkin, hora_checkout, origen_checkin, origen_checkout} o {ok:false, error:override_hora_invalido, causa:formato_invalido|cast_invalido|fuera_de_ventana, ...}. Override de hora => HARD en 3 etapas: formato estricto HH:MM[:SS], cast a TIME, ventana 07:00-22:00. Fase B - motor de horarios.';

COMMIT;

-- ---- Reporte del fingerprint NUEVO (unico SELECT visible; post-COMMIT) ----
SELECT
  md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')))                 AS resolver_fingerprint_nuevo,
  (md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')))
      <> '759662b4afaed7af426917aa3717b34c')                                                        AS cambio_confirmado,
  md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)'))) AS odr_fingerprint_sin_cambio;
