-- =====================================================================
-- HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql
-- A) Integracion de resolver_horario() en obtener_disponibilidad_rango (LECTURA).
-- ALCANCE: SOLO TEST. NO ejecutar en OPS. NO toca canonico, gateway, frontend,
--   workflows, A07/A08 ni crear_prereserva. Solo reemplaza obtener_disponibilidad_rango.
--
-- METODO: CREATE OR REPLACE (NO DROP) -> preserva ACL owner-only, COMMENT, owner,
--   y NO voltea vista_disponibilidad (dependiente). Firma y 9 columnas IDENTICAS.
--
-- UNICO DELTA FUNCIONAL (politica D1):
--   - Los 2 CASE hardcodeados de horas se reemplazan por resolver_horario() via
--     CROSS JOIN LATERAL (1 llamada por fila cabana x fecha).
--   - Extraccion fail-closed: ok=true -> hora_checkin/hora_checkout del resolver;
--     ok=false o ausente -> AMBAS horas NULL en esa fila (all-or-nothing por fila).
--   Todo lo demas (matriz, estados, reservas/pre-reservas/bloqueos, generate_series,
--   semantica [fecha_in, fecha_out), checkout_disponible) queda intacto.
--
-- GATE ANTI-OPS + BASELINE (embebido en la transaccion): si algo no coincide,
--   RAISE EXCEPTION aborta la tx y el CREATE NO se aplica.
--
-- COMO CORRERLO: correr con NADA seleccionado (script completo, un solo BEGIN..COMMIT).
--   Nada-seleccionado evita el truncado auto-RLS del editor de Supabase.
--   Antes conviene correr el [PRE] del archivo B y confirmar gate_ok=true.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- GATE (6 condiciones). Usa to_regprocedure (NULL si no existe) para no
-- explotar; falla limpio via RAISE. % = un placeholder por parametro.
-- ---------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM configuracion_general WHERE clave = 'ambiente');
  v_odr text := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  v_res text := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE: ambiente=% (esperado test). Abortando.', v_amb;
  END IF;
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'GATE: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)') IS NULL THEN
    RAISE EXCEPTION 'GATE: no existe obtener_disponibilidad_rango(date,date,bigint). Abortando.';
  END IF;
  IF to_regprocedure('public.resolver_horario(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'GATE: no existe resolver_horario(bigint,date). Abortando.';
  END IF;
  IF v_odr IS DISTINCT FROM 'f8d6bbf533c775349642e7ed34d5ea8c' THEN
    RAISE EXCEPTION 'GATE: fingerprint ODR=% (esperado f8d6bbf533c775349642e7ed34d5ea8c). Abortando.', v_odr;
  END IF;
  IF v_res IS DISTINCT FROM '759662b4afaed7af426917aa3717b34c' THEN
    RAISE EXCEPTION 'GATE: fingerprint resolver=% (esperado 759662b4afaed7af426917aa3717b34c). Abortando.', v_res;
  END IF;
  RAISE NOTICE 'GATE OK: ambiente=test, schema=public, ODR y resolver presentes con fingerprints baseline esperados.';
END
$gate$;

-- ---------------------------------------------------------------------
-- CREATE OR REPLACE (firma calificada public.; 9 columnas identicas).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.obtener_disponibilidad_rango(
  p_fecha_desde   DATE,
  p_fecha_hasta   DATE,
  p_id_cabana     BIGINT DEFAULT NULL
)
RETURNS TABLE (
  id_cabana              BIGINT,
  fecha                  DATE,
  estado                 TEXT,
  tipo_dia               TEXT,
  temporada              TEXT,
  hora_checkin_base      TIME,
  hora_checkout_base     TIME,
  id_reserva_activa      BIGINT,
  id_prereserva_activa   BIGINT
)
LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  WITH dias AS (
    SELECT generate_series(p_fecha_desde, p_fecha_hasta - INTERVAL '1 day', '1 day')::DATE AS d
  ),
  cabanas_activas AS (
    SELECT c.id_cabana, c.nombre
    FROM cabanas c
    WHERE c.activa = TRUE
      AND (p_id_cabana IS NULL OR c.id_cabana = p_id_cabana)
  ),
  matriz AS (
    SELECT ca.id_cabana, d.d AS fecha
    FROM cabanas_activas ca
    CROSS JOIN dias d
  )
  SELECT
    m.id_cabana,
    m.fecha,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM bloqueos b
        WHERE b.activo = TRUE
          AND (b.id_cabana = m.id_cabana OR b.id_cabana IS NULL)
          AND m.fecha >= b.fecha_desde
          AND m.fecha < b.fecha_hasta
      ) THEN 'bloqueada'
      WHEN EXISTS (
        SELECT 1 FROM reservas r
        WHERE r.id_cabana = m.id_cabana
          AND r.estado IN ('confirmada', 'activa')
          AND m.fecha >= r.fecha_checkin
          AND m.fecha < r.fecha_checkout
      ) THEN 'ocupada'
      WHEN EXISTS (
        SELECT 1 FROM pre_reservas pr
        WHERE pr.id_cabana = m.id_cabana
          AND (
            (pr.estado = 'pendiente_pago' AND pr.expira_en > NOW())
            OR pr.estado = 'pago_en_revision'
          )
          AND m.fecha >= pr.fecha_in
          AND m.fecha < pr.fecha_out
      ) THEN 'ocupada'
      WHEN EXISTS (
        SELECT 1 FROM reservas r
        WHERE r.id_cabana = m.id_cabana
          AND r.estado IN ('confirmada', 'activa', 'completada')
          AND r.fecha_checkout = m.fecha
      ) THEN 'checkout_disponible'
      ELSE 'disponible'
    END AS estado,
    CASE
      WHEN EXISTS (SELECT 1 FROM feriados f WHERE f.fecha = m.fecha AND f.activo = TRUE) THEN 'feriado'
      WHEN EXTRACT(DOW FROM m.fecha) IN (5, 6) THEN 'finde'
      ELSE 'semana'
    END AS tipo_dia,
    (
      SELECT t.nombre FROM temporadas t
      WHERE t.activa = TRUE
        AND m.fecha BETWEEN t.fecha_desde AND t.fecha_hasta
      LIMIT 1
    ) AS temporada,
    -- Hora base desde resolver_horario() (motor de horarios). D1: HARD del resolver (ok=false/ausente) => ambas horas NULL en la fila.
    CASE WHEN COALESCE((hr.rh->>'ok')::boolean, false)
         THEN (hr.rh->>'hora_checkin')::TIME  ELSE NULL END AS hora_checkin_base,
    CASE WHEN COALESCE((hr.rh->>'ok')::boolean, false)
         THEN (hr.rh->>'hora_checkout')::TIME ELSE NULL END AS hora_checkout_base,
    (
      SELECT r.id_reserva FROM reservas r
      WHERE r.id_cabana = m.id_cabana
        AND r.estado IN ('confirmada', 'activa')
        AND m.fecha >= r.fecha_checkin
        AND m.fecha < r.fecha_checkout
      LIMIT 1
    ) AS id_reserva_activa,
    (
      SELECT pr.id_pre_reserva FROM pre_reservas pr
      WHERE pr.id_cabana = m.id_cabana
        AND (
          (pr.estado = 'pendiente_pago' AND pr.expira_en > NOW())
          OR pr.estado = 'pago_en_revision'
        )
        AND m.fecha >= pr.fecha_in
        AND m.fecha < pr.fecha_out
      LIMIT 1
    ) AS id_prereserva_activa
  FROM matriz m
  CROSS JOIN LATERAL (SELECT resolver_horario(m.id_cabana, m.fecha) AS rh) hr;
END;
$function$;

COMMIT;
