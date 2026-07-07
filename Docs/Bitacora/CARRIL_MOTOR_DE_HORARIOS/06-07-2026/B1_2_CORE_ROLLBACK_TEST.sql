-- =====================================================================
-- B1.2-core - Motor de Horarios / Carril B1 (integracion de vigencias)
-- Artefacto 4/4: ROLLBACK QUIRURGICO
-- ---------------------------------------------------------------------
-- Revierte SOLO el cableado del resolver:
--   * public.resolver_horario -> cuerpo R0 verbatim (restaura fp 58d75c1b6b812ee2d2c9751ddcb0cd4d)
--   * public.vigencias_conflictos_comprometidos -> version B1.1 verbatim (LATERAL a resolver_horario)
--   * DROP public._resolver_horario
-- NO toca public.vigencias_horario_base (los datos de vigencias se conservan).
-- NO ejecuta el cascade de fingerprints (gates/smokes/docs B1.1/S0-S3 quedan como estan).
-- Transaccion unica. Doble lock (10,0)->(919010). DROP+CREATE (no CASCADE). TEST-only.
-- Ejecutar en Supabase SQL Editor SIN texto seleccionado (script entero).
-- =====================================================================

BEGIN;

SELECT pg_advisory_xact_lock(10, 0);
SELECT pg_advisory_xact_lock(919010);

-- GATE: core efectivamente aplicado (si no, no hay nada que revertir).
DO $gate$
DECLARE v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE core-rollback: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'GATE core-rollback: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NULL THEN
    RAISE EXCEPTION 'GATE core-rollback: _resolver_horario no existe (core no aplicado). Nada que revertir. Abortando.';
  END IF;
  RAISE NOTICE 'GATE core-rollback OK: core aplicado; revirtiendo.';
END
$gate$;

-- ---- 1. restaurar wrapper resolver_horario -> cuerpo R0 (verbatim) ----
DROP FUNCTION public.resolver_horario(bigint, date);
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

REVOKE EXECUTE ON FUNCTION public.resolver_horario(bigint, date) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.resolver_horario(bigint, date) IS
  'Resuelve la base de check-in/check-out para (id_cabana, fecha): base -> patron domingo -> override global -> override por cabana (overrides_operativos; fecha_hasta inclusiva, NULL = solo fecha_desde [Etapa 2, correccion R0]). Funcion read-only (sin writes). Devuelve jsonb {ok:true, hora_checkin, hora_checkout, origen_checkin, origen_checkout} o {ok:false, error:override_hora_invalido, causa:formato_invalido|cast_invalido|fuera_de_ventana, ...}. Override de hora => HARD en 3 etapas: formato estricto HH:MM[:SS], cast a TIME, ventana 07:00-22:00. Fase B - motor de horarios.';

-- ---- 2. restaurar helper -> version B1.1 (verbatim; LATERAL a resolver_horario) ----
DROP FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time);
CREATE OR REPLACE FUNCTION public.vigencias_conflictos_comprometidos(
  p_fecha_desde DATE, p_fecha_hasta DATE, p_abierta BOOLEAN,
  p_ci_def TIME, p_ci_dom TIME, p_co_def TIME, p_co_dom TIME
) RETURNS jsonb
LANGUAGE sql
STABLE
AS $help$
  WITH comprometidos AS (
    -- Reservas vivas: un lado por fila (checkout y checkin)
    SELECT 'reserva'::text AS tipo, id_reserva AS id, id_cabana, fecha_checkout AS fecha, 'checkout'::text AS lado, hora_checkout AS frozen
      FROM reservas WHERE estado IN ('confirmada','activa','completada')
    UNION ALL
    SELECT 'reserva', id_reserva, id_cabana, fecha_checkin, 'checkin', hora_checkin
      FROM reservas WHERE estado IN ('confirmada','activa','completada')
    UNION ALL
    -- Pre-reservas vigentes (misma definicion que S0)
    SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_out, 'checkout', hora_checkout
      FROM pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'
    UNION ALL
    SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_in, 'checkin', hora_checkin
      FROM pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'
  ),
  en_rango AS (
    SELECT * FROM comprometidos
    WHERE fecha >= p_fecha_desde AND (p_abierta OR fecha <= p_fecha_hasta)
  ),
  eval AS (
    SELECT c.tipo, c.id, c.id_cabana, c.fecha, c.lado, c.frozen,
      COALESCE((r.res->>'ok')::boolean, false) AS resolver_ok,
      (r.res->>'origen_checkin')  AS ori_ci,
      (r.res->>'origen_checkout') AS ori_co,
      CASE WHEN EXTRACT(DOW FROM c.fecha) = 0 THEN p_ci_dom ELSE p_ci_def END AS vig_ci,
      CASE WHEN EXTRACT(DOW FROM c.fecha) = 0 THEN p_co_dom ELSE p_co_def END AS vig_co
    FROM en_rango c
    CROSS JOIN LATERAL (SELECT resolver_horario(c.id_cabana, c.fecha) AS res) r
  ),
  viol AS (
    SELECT tipo, id, id_cabana, fecha, lado,
      CASE WHEN NOT resolver_ok THEN 'resolver_horario_invalido' ELSE 'turno_pegado' END AS motivo
    FROM eval
    WHERE
      -- FAIL-CLOSED: si el resolver no puede determinar provenance (ok<>true),
      -- no se puede verificar que la base no gobierne => conflicto explicito.
      NOT resolver_ok
      -- lado='checkout' (E sale): protege una llegada futura (vig_ci) donde la base gobierna el checkin
      OR (resolver_ok AND lado = 'checkout' AND ori_ci IN ('base','patron_domingo') AND (vig_ci - frozen) < INTERVAL '2 hours')
      -- lado='checkin' (E entra): protege una salida futura (vig_co) donde la base gobierna el checkout
      OR (resolver_ok AND lado = 'checkin'  AND ori_co IN ('base','patron_domingo') AND (frozen - vig_co) < INTERVAL '2 hours')
  )
  SELECT COALESCE(
    jsonb_agg(jsonb_build_object('fecha', fecha, 'id_cabana', id_cabana, 'tipo', tipo, 'id', id, 'lado', lado, 'motivo', motivo)
              ORDER BY fecha, id_cabana, id),
    '[]'::jsonb)
  FROM viol;
$help$;

REVOKE EXECUTE ON FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time) IS
  'B1.1 helper G1 compartido (crear_vigencia_horario + trg_vig_guard). Evalua una vigencia PROSPECTIVA contra comprometidos vivos (reservas confirmada/activa/completada; pre_reservas pendiente_pago vigente | pago_en_revision), SOLO donde la BASE gobierna (provenance via origen_checkin/origen_checkout de resolver_horario, sin reimplementar precedencia). Turno pegado >=2h contra la hora congelada. FAIL-CLOSED: si resolver_horario devuelve ok<>true para alguna fecha/cabana en rango, emite conflicto motivo=resolver_horario_invalido (nunca fail-open). Devuelve array jsonb de conflictos con motivo por entrada. DEUDA DURA B1.2: revisar por autorreferencia y nuevo origen vigencia antes de cablear el resolver.';

-- ---- 3. DROP interno ----
DROP FUNCTION IF EXISTS public._resolver_horario(bigint, date, boolean);

-- ---- POSTCHECKS intra-tx ----
DO $post$
DECLARE v_res text; v_odr text; v_vista int;
BEGIN
  v_res := md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'POST rollback: resolver fp=% (esperado R0 58d75c1b6b812ee2d2c9751ddcb0cd4d).', v_res;
  END IF;
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'POST rollback: _resolver_horario todavia existe.';
  END IF;
  v_odr := md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'POST rollback: ODR fp cambio a % (esperado 37009a32... intacto).', v_odr;
  END IF;
  SELECT count(*) INTO v_vista FROM public.vista_disponibilidad;
  IF v_vista = 0 THEN
    RAISE EXCEPTION 'POST rollback: vista_disponibilidad sin filas.';
  END IF;
  IF to_regclass('public.vigencias_horario_base') IS NULL THEN
    RAISE EXCEPTION 'POST rollback: vigencias_horario_base desaparecio (no debia tocarse).';
  END IF;
  RAISE NOTICE 'POST rollback OK: resolver=R0 (58d75c1b), interno eliminado, ODR intacto, vista=% filas, vigencias conservadas.', v_vista;
END
$post$;

COMMIT;

-- ---- REPORTE (autocommit, read-only; ULTIMO) ----
SELECT
  md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure)) AS resolver_fp_restaurado,
  (to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NULL)    AS interno_eliminado,
  (SELECT count(*) FROM public.vigencias_horario_base)                          AS vigencias_conservadas;
