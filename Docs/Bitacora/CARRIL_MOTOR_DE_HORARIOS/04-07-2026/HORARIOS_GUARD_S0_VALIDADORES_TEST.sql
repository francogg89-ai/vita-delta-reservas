-- =====================================================================
-- HORARIOS_GUARD_S0_VALIDADORES_TEST.sql
-- Sub-bloque S0 del guard de overrides horarios: los TRES validadores.
-- ALCANCE: SOLO TEST. NO ejecutar en OPS. NO tocar canonico/gateway/frontend/workflows.
-- Sin acuñar D-*/L-*.
--
-- Contenido (solo lectura, sin locks, sin writes):
--   1) validar_estado_horario_final(id_cabana, fecha)  -> resolver ok + same-day gap>=2h
--   2) validar_no_eventos_comprometidos(id_cabana, fecha) -> reservas/pre_reservas comprometidas
--   3) validar_estado_override(id_cabana, fecha) -> orquesta (comprometidos primero, luego final)
--
-- NO incluye trigger, ni crear_override_horario, ni crear_paquete_dia_especial (S1/S2/S3).
-- Metodo: CREATE OR REPLACE (funciones nuevas; idempotente y re-ejecutable; auto-RLS OFF en TEST
--   => sin bug del Dashboard, L-CC-07). Hardening REVOKE espejo Bloque 23.
-- Correr el script COMPLETO (sin seleccion parcial; L-8A-01). El aviso "Run without RLS" es esperado.
-- =====================================================================

BEGIN;

-- ---- GATE anti-OPS (aborta y revierte si no es TEST/public o los fingerprints no coinciden) ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM configuracion_general WHERE clave = 'ambiente');
  v_res text;
  v_odr text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE S0: ambiente=% (esperado test). Abortando.', v_amb;
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'GATE S0: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('public.resolver_horario(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'GATE S0: falta resolver_horario(bigint,date). Abortando.';
  END IF;
  IF to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)') IS NULL THEN
    RAISE EXCEPTION 'GATE S0: falta obtener_disponibilidad_rango(date,date,bigint). Abortando.';
  END IF;
  v_res := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'GATE S0: fingerprint resolver=% (esperado 58d75c1b6b812ee2d2c9751ddcb0cd4d, post-R0). Abortando.', v_res;
  END IF;
  v_odr := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE S0: fingerprint ODR=% (esperado 37009a32154f93b80520500c0f15b46b). Abortando.', v_odr;
  END IF;
  RAISE NOTICE 'GATE S0 OK: ambiente=test, schema=public, resolver=58d75c1b (post-R0), ODR=37009a32.';
END
$gate$;

-- =====================================================================
-- 1) validar_estado_horario_final: estado horario FINAL de (cabana, fecha).
--    Llama al resolver (que ya ve el estado efectivo); valida ok + same-day gap>=2h.
--    NO toma locks. VOLATILE (lee estado mutable / NOW indirecto via resolver). INVOKER.
-- =====================================================================
CREATE OR REPLACE FUNCTION validar_estado_horario_final(p_id_cabana BIGINT, p_fecha DATE)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
AS $$
DECLARE
  v_res JSONB;
  v_ci  TIME;
  v_co  TIME;
BEGIN
  v_res := resolver_horario(p_id_cabana, p_fecha);

  -- El resolver rechaza valores de override invalidos (formato/cast/ventana). Propagar.
  IF NOT (v_res->>'ok')::boolean THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'override_hora_invalido',
      'id_cabana', p_id_cabana,
      'fecha', p_fecha,
      'causa', v_res->>'causa',
      'detalle_resolver', v_res
    );
  END IF;

  v_ci := (v_res->>'hora_checkin')::time;
  v_co := (v_res->>'hora_checkout')::time;

  -- Same-day: la entrada efectiva debe ser >= 2h despues de la salida efectiva.
  -- Resta de TIME (no checkout + interval) para evitar wrap de medianoche.
  IF (v_ci - v_co) < interval '2 hours' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'override_incompatible_same_day',
      'id_cabana', p_id_cabana,
      'fecha', p_fecha,
      'hora_checkin_efectiva', v_ci,
      'hora_checkout_efectiva', v_co,
      'gap_efectivo', (v_ci - v_co),
      'gap_minimo', interval '2 hours'
    );
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$$;

-- =====================================================================
-- 2) validar_no_eventos_comprometidos: existencia de evento comprometido en (cabana, fecha).
--    INDEPENDIENTE de si hay override activo en el estado final (criterio conservador).
--    Reservas {confirmada, activa, completada}; pre_reservas (pendiente_pago vigente | pago_en_revision).
--    Considera fecha_checkin/fecha_checkout (reservas) y fecha_in/fecha_out (pre_reservas).
--    NO toma locks. VOLATILE. INVOKER.
-- =====================================================================
CREATE OR REPLACE FUNCTION validar_no_eventos_comprometidos(p_id_cabana BIGINT, p_fecha DATE)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
AS $$
DECLARE
  v_id_reserva BIGINT;
  v_id_pre     BIGINT;
BEGIN
  SELECT id_reserva INTO v_id_reserva
  FROM reservas
  WHERE id_cabana = p_id_cabana
    AND estado IN ('confirmada', 'activa', 'completada')
    AND (fecha_checkin = p_fecha OR fecha_checkout = p_fecha)
  ORDER BY id_reserva
  LIMIT 1;

  IF v_id_reserva IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'override_pisa_reserva',
      'id_cabana', p_id_cabana,
      'fecha', p_fecha,
      'id_reserva', v_id_reserva
    );
  END IF;

  SELECT id_pre_reserva INTO v_id_pre
  FROM pre_reservas
  WHERE id_cabana = p_id_cabana
    AND ((estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision')
    AND (fecha_in = p_fecha OR fecha_out = p_fecha)
  ORDER BY id_pre_reserva
  LIMIT 1;

  IF v_id_pre IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'override_pisa_prereserva',
      'id_cabana', p_id_cabana,
      'fecha', p_fecha,
      'id_pre_reserva', v_id_pre
    );
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$$;

-- =====================================================================
-- 3) validar_estado_override: orquestador. Eventos comprometidos PRIMERO (conservador),
--    luego estado horario final. Devuelve el primer verdict no-ok, o {ok:true}.
--    NO toma locks. VOLATILE. INVOKER. Es la unica fuente de verdad que usaran S1/S2/S3.
-- =====================================================================
CREATE OR REPLACE FUNCTION validar_estado_override(p_id_cabana BIGINT, p_fecha DATE)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
AS $$
DECLARE
  v JSONB;
BEGIN
  v := validar_no_eventos_comprometidos(p_id_cabana, p_fecha);
  IF NOT (v->>'ok')::boolean THEN
    RETURN v;
  END IF;

  v := validar_estado_horario_final(p_id_cabana, p_fecha);
  RETURN v;
END;
$$;

-- ---- Hardening (espejo Bloque 23): solo el owner ejecuta ----
REVOKE EXECUTE ON FUNCTION public.validar_estado_horario_final(bigint, date)   FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.validar_no_eventos_comprometidos(bigint, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.validar_estado_override(bigint, date)        FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.validar_estado_horario_final(bigint, date) IS
  'S0 guard horarios. Valida el estado horario FINAL de (id_cabana, fecha) via resolver_horario: si el resolver rechaza el valor => override_hora_invalido; si el gap same-day (hora_checkin_efectiva - hora_checkout_efectiva) < 2h => override_incompatible_same_day; si no {ok:true}. Read-only, sin locks. Fase B - guard overrides.';
COMMENT ON FUNCTION public.validar_no_eventos_comprometidos(bigint, date) IS
  'S0 guard horarios. Valida existencia de evento comprometido en (id_cabana, fecha), independiente del estado de overrides: reservas {confirmada,activa,completada} con fecha_checkin/fecha_checkout=fecha => override_pisa_reserva; pre_reservas (pendiente_pago vigente | pago_en_revision) con fecha_in/fecha_out=fecha => override_pisa_prereserva; si no {ok:true}. Read-only, sin locks. Fase B - guard overrides.';
COMMENT ON FUNCTION public.validar_estado_override(bigint, date) IS
  'S0 guard horarios. Orquestador: valida eventos comprometidos primero (conservador) y luego estado horario final para (id_cabana, fecha). Devuelve el primer verdict no-ok {ok:false, error:...} o {ok:true}. Unica fuente de verdad para trigger/funciones de alta (S1/S2/S3). Read-only, sin locks. Fase B - guard overrides.';

COMMIT;

-- ---- Confirmacion: las tres funciones existen con la firma esperada ----
SELECT
  to_regprocedure('public.validar_estado_horario_final(bigint,date)')     IS NOT NULL AS f1_ok,
  to_regprocedure('public.validar_no_eventos_comprometidos(bigint,date)') IS NOT NULL AS f2_ok,
  to_regprocedure('public.validar_estado_override(bigint,date)')          IS NOT NULL AS f3_ok;
