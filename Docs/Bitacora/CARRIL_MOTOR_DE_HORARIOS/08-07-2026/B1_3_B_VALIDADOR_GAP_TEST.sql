-- =====================================================================
-- B1.3-B - Motor de Horarios / Vigencias Semanales
-- Artefacto B (aislado): validar_gap_bordes_congelados
-- ---------------------------------------------------------------------
-- Valida el GAP DE TURNO (>=2h) contra las horas CONGELADAS de vecinos de la
-- MISMA cabana en los dias de borde de una reserva CANDIDATA (Modelo alfa):
--   * Caso A - la candidata ENTRA en p_fecha_checkin y un vecino SALE ese mismo
--     dia: exige p_hora_checkin - vecino.hora_checkout >= 2h. Si no =>
--     error 'checkin_pisa_checkout_anterior'.
--   * Caso B - la candidata SALE en p_fecha_checkout y un vecino ENTRA ese mismo
--     dia: exige vecino.hora_checkin - p_hora_checkout >= 2h. Si no =>
--     error 'checkout_pisa_checkin_posterior'.
-- Estos dos errores direccionales REEMPLAZAN un generico gap_same_day_insuficiente.
-- FUENTE DE VERDAD del conflicto same-day = horas congeladas de:
--   reservas {confirmada, activa, completada} + pre_reservas {pendiente_pago
--   vigente | pago_en_revision}, de la misma cabana, menos exclusiones. Aplica
--   AUNQUE las horas no provengan de vigencia/override (son las horas guardadas).
-- READ-ONLY, STABLE, SIN locks (los toma el llamador). NO valida solapamiento de
--   rango (eso es validar_disponibilidad/EXCLUDE) ni la ventana [07:00,22:00] (eso
--   queda en crear_prereserva); B cubre EXCLUSIVAMENTE el turno en los bordes.
-- ---------------------------------------------------------------------
-- ALCANCE: TEST-only. NO cablea llamadores (crear_prereserva, confirmar_reserva,
--   crear_reserva_con_horario_pactado son C/D/E). NO toca el motor semanal
--   (no llama al resolver; lee horas congeladas directas). Transaccion unica.
--   Lock global (10,0). REVOKE owner-only. Ejecutar el script entero en SQL Editor.
-- =====================================================================

BEGIN;

SELECT pg_advisory_xact_lock(10, 0);

-- ---- GATE B: ambiente + precondiciones estructurales y de datos (fail-closed) ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  v_bad_cols int;
  v_null_res bigint;
  v_null_pre bigint;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE B1.3-B: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'GATE B1.3-B: schema=% (esperado public). Abortando.', current_schema();
  END IF;

  -- Estructural: las 4 columnas de hora existen y son NOT NULL (is_nullable='NO').
  SELECT count(*) INTO v_bad_cols
  FROM (VALUES ('reservas','hora_checkin'), ('reservas','hora_checkout'),
               ('pre_reservas','hora_checkin'), ('pre_reservas','hora_checkout')) AS req(tbl, col)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema='public' AND c.table_name=req.tbl AND c.column_name=req.col
      AND c.is_nullable='NO');
  IF v_bad_cols > 0 THEN
    RAISE EXCEPTION 'GATE B1.3-B: % columna(s) hora_checkin/hora_checkout faltan o son NULLable en reservas/pre_reservas (se requieren NOT NULL). Abortando (fail-closed).', v_bad_cols;
  END IF;

  -- Datos vivos: ninguna fila con hora NULL (defensivo; con NOT NULL debe ser 0).
  SELECT count(*) INTO v_null_res FROM public.reservas WHERE hora_checkin IS NULL OR hora_checkout IS NULL;
  SELECT count(*) INTO v_null_pre FROM public.pre_reservas WHERE hora_checkin IS NULL OR hora_checkout IS NULL;
  IF v_null_res > 0 OR v_null_pre > 0 THEN
    RAISE EXCEPTION 'GATE B1.3-B: filas con hora NULL (reservas=%, pre_reservas=%). Abortando (fail-closed).', v_null_res, v_null_pre;
  END IF;

  -- La funcion no debe existir aun (alta limpia; si existe, correr rollback).
  IF to_regprocedure('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'GATE B1.3-B: validar_gap_bordes_congelados ya existe (estado inesperado; correr rollback). Abortando.';
  END IF;

  RAISE NOTICE 'GATE B OK: ambiente=test, schema=public, horas NOT NULL en reservas/pre_reservas, 0 filas con hora NULL, funcion ausente.';
END
$gate$;

-- =====================================================================
-- FUNCION validar_gap_bordes_congelados
-- =====================================================================
CREATE FUNCTION public.validar_gap_bordes_congelados(
  p_id_cabana          bigint,
  p_fecha_checkin      date,
  p_hora_checkin       time,
  p_fecha_checkout     date,
  p_hora_checkout      time,
  p_excluir_reserva    bigint DEFAULT NULL,
  p_excluir_prereserva bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $fn$
  WITH vecinos AS (
    -- Reservas vivas de la cabana: un lado por fila (checkin=entra, checkout=sale), hora congelada.
    SELECT 'reserva'::text AS tipo, id_reserva AS id, fecha_checkin AS fecha, 'checkin'::text AS lado, hora_checkin AS hora
      FROM public.reservas
      WHERE id_cabana = p_id_cabana AND estado IN ('confirmada','activa','completada')
        AND (p_excluir_reserva IS NULL OR id_reserva <> p_excluir_reserva)
    UNION ALL
    SELECT 'reserva', id_reserva, fecha_checkout, 'checkout', hora_checkout
      FROM public.reservas
      WHERE id_cabana = p_id_cabana AND estado IN ('confirmada','activa','completada')
        AND (p_excluir_reserva IS NULL OR id_reserva <> p_excluir_reserva)
    UNION ALL
    -- Pre-reservas vigentes (misma definicion que S0/helper de vigencias).
    SELECT 'pre_reserva', id_pre_reserva, fecha_in, 'checkin', hora_checkin
      FROM public.pre_reservas
      WHERE id_cabana = p_id_cabana AND ((estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision')
        AND (p_excluir_prereserva IS NULL OR id_pre_reserva <> p_excluir_prereserva)
    UNION ALL
    SELECT 'pre_reserva', id_pre_reserva, fecha_out, 'checkout', hora_checkout
      FROM public.pre_reservas
      WHERE id_cabana = p_id_cabana AND ((estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision')
        AND (p_excluir_prereserva IS NULL OR id_pre_reserva <> p_excluir_prereserva)
  ),
  conflictos AS (
    -- Caso A: la candidata ENTRA en p_fecha_checkin; un vecino SALE ese dia.
    -- Exige p_hora_checkin - vecino.hora_checkout >= 2h.
    SELECT 'checkin_pisa_checkout_anterior'::text AS motivo, v.tipo, v.id, v.fecha, v.lado,
           v.hora AS hora_vecino, p_hora_checkin AS hora_candidata, (p_hora_checkin - v.hora) AS gap
      FROM vecinos v
      WHERE v.lado = 'checkout' AND v.fecha = p_fecha_checkin AND (p_hora_checkin - v.hora) < INTERVAL '2 hours'
    UNION ALL
    -- Caso B: la candidata SALE en p_fecha_checkout; un vecino ENTRA ese dia.
    -- Exige vecino.hora_checkin - p_hora_checkout >= 2h.
    SELECT 'checkout_pisa_checkin_posterior', v.tipo, v.id, v.fecha, v.lado,
           v.hora, p_hora_checkout, (v.hora - p_hora_checkout)
      FROM vecinos v
      WHERE v.lado = 'checkin' AND v.fecha = p_fecha_checkout AND (v.hora - p_hora_checkout) < INTERVAL '2 hours'
  )
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM conflictos)
    THEN jsonb_build_object('ok', true)
    ELSE jsonb_build_object(
      'ok', false,
      -- error direccional determinista: Caso A tiene prioridad, luego por fecha/id.
      'error', (SELECT motivo FROM conflictos ORDER BY (motivo = 'checkin_pisa_checkout_anterior') DESC, fecha, id LIMIT 1),
      'conflictos', (SELECT jsonb_agg(jsonb_build_object(
                       'motivo', motivo, 'tipo', tipo, 'id', id, 'fecha', fecha, 'lado', lado,
                       'hora_vecino', hora_vecino, 'hora_candidata', hora_candidata,
                       'gap_minutos', (EXTRACT(EPOCH FROM gap)/60)::int)
                     ORDER BY motivo, fecha, id) FROM conflictos))
  END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint) IS
  'B1.3-B validador de gap de turno (Modelo alfa) owner-only, read-only STABLE, sin locks. Verifica que una reserva CANDIDATA respete >=2h contra las horas CONGELADAS de vecinos de la misma cabana en los dias de borde. Caso A (checkin de la candidata vs checkout de un vecino el mismo dia) => error checkin_pisa_checkout_anterior; Caso B (checkout de la candidata vs checkin de un vecino el mismo dia) => error checkout_pisa_checkin_posterior; ambos reemplazan un generico gap_same_day_insuficiente. Fuente: reservas {confirmada,activa,completada} + pre_reservas {pendiente_pago vigente | pago_en_revision} de la cabana, menos p_excluir_reserva / p_excluir_prereserva. Devuelve {ok:true} o {ok:false, error, conflictos:[{motivo,tipo,id,fecha,lado,hora_vecino,hora_candidata,gap_minutos}]}. NO valida solapamiento de rango (validar_disponibilidad) ni ventana (crear_prereserva). El cableado en crear_prereserva/confirmar_reserva/crear_reserva_con_horario_pactado es C/D/E. B1.3-B - TEST.';

-- ---- POSTCHECKS intra-tx ----
DO $post$
DECLARE r text; v_probe jsonb;
BEGIN
  IF to_regprocedure('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)') IS NULL THEN
    RAISE EXCEPTION 'POST-B: la funcion no quedo creada.';
  END IF;
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r, 'public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)', 'EXECUTE') THEN
      RAISE EXCEPTION 'POST-B: EXECUTE concedido a % (esperado owner-only, incl. PUBLIC).', r;
    END IF;
  END LOOP;
  -- sanity: una cabana inexistente no tiene vecinos => ok:true
  v_probe := public.validar_gap_bordes_congelados(-1, CURRENT_DATE+500, TIME '15:00', CURRENT_DATE+503, TIME '10:00');
  IF COALESCE((v_probe->>'ok')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'POST-B: sanity fallo (esperado ok:true sin vecinos): %', v_probe;
  END IF;
  RAISE NOTICE 'POSTCHECKS-B OK: funcion presente, owner-only (incl. PUBLIC), sanity ok:true sin vecinos.';
END
$post$;

COMMIT;

-- ---- REPORTE (read-only; ULTIMO) ----
SELECT
  'B1.3-B aplicado (TEST)'                                                                              AS estado,
  md5(pg_get_functiondef('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)'::regprocedure)) AS validador_fp_nuevo;
