-- =====================================================================
-- QAGAP_A_SEED_TEST.sql
-- Fixture QA para provocar los dos errores de gap de turno DESDE EL PORTAL.
-- ---------------------------------------------------------------------
-- ALCANCE: SOLO TEST (gate transaccional sobre configuracion_general.ambiente).
-- NO ejecutar en OPS. NO toca configuracion_general, vigencias ni overrides:
-- las horas colisionantes se CONGELAN en las columnas hora_checkin/hora_checkout
-- de la reserva vecina (el validador lee horas congeladas directas).
--
-- Siembra 2 vecinos (reservas 'confirmada') en 2 islas de fechas disjuntas:
--   Isla A -> vecino SALE el dia dA a (bciA - 1h)  => la candidata que ENTRA el dA
--             a la hora base dispara checkin_pisa_checkout_anterior (gap 60 min).
--   Isla B -> vecino ENTRA el dia dB+3 a (bcoB + 1h) => la candidata que SALE el
--             dB+3 a la hora base dispara checkout_pisa_checkin_posterior (gap 60 min).
--
-- Geometria (validador B1.3-B, umbral < 2h conflicta; >= 2h permite):
--   Caso A: checkin_candidata - checkout_anterior  < 2h
--   Caso B: checkin_posterior - checkout_candidata < 2h
--
-- ATOMICO Y FAIL-CLOSED: gates -> INSERTs -> asserts de cardinalidad ->
-- asserts de geometria. Cualquier fallo => RAISE EXCEPTION => ROLLBACK total.
-- NUNCA quedan fixtures parciales.
--
-- Ejecutar el script ENTERO (sin seleccion parcial).
-- =====================================================================

BEGIN;

DO $seed$
DECLARE
  ---------------------------------------------------------------- PARAMETROS
  c_runid   CONSTANT text := '<RUNID>';        -- ej: qagap_20260712_01  (solo [a-z0-9_])
  c_cabana  CONSTANT text := '<CABANA>';       -- ej: Tokio  (la MISMA que usas en la UI)
  c_dA      CONSTANT date := DATE '<dA>';      -- check-in de la candidata A
  c_dB      CONSTANT date := DATE '<dB>';      -- check-in de la candidata B
  -- Identidades QA: email-only (telefono NULL => upsert_huesped matchea SOLO por
  -- lower(email); sin ambiguedad de normalizacion telefonica). example.invalid = RFC 2606.
  c_mail_vA CONSTANT text := 'qagap+<RUNID>.vecinoa@example.invalid';
  c_mail_vB CONSTANT text := 'qagap+<RUNID>.vecinob@example.invalid';
  c_mail_cA CONSTANT text := 'qagap+<RUNID>.candidataa@example.invalid';
  c_mail_cB CONSTANT text := 'qagap+<RUNID>.candidatab@example.invalid';
  ---------------------------------------------------------------- ESTADO
  v_amb text; v_cab bigint; v_rh jsonb;
  v_bciA time;   -- hora check-in base de la candidata A (dia dA)
  v_bcoB time;   -- hora check-out base de la candidata B (dia dB+3)
  v_hue_vA bigint; v_hue_vB bigint;
  v_res_vA bigint; v_res_vB bigint;
  v_n int; v_g jsonb; v_c jsonb;
BEGIN
  ---------------------------------------------------------------- GATES
  -- G1: ambiente TEST (anti-OPS, transaccional: aborta antes de escribir nada).
  v_amb := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'SEED QA-GAP: ambiente=% (esperado test). ROLLBACK.', COALESCE(v_amb,'<null>');
  END IF;

  -- G2: el validador de gap debe estar cableado en crear_prereserva (si no, el
  --     fixture no probaria nada y daria un falso verde).
  IF position('validar_gap_bordes_congelados' in
       pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'SEED QA-GAP: crear_prereserva SIN validador de gap cableado (C no aplicado).';
  END IF;

  -- G3: cabana por NOMBRE (nunca id hardcodeado) y activa.
  SELECT id_cabana INTO v_cab FROM public.cabanas WHERE nombre = c_cabana AND activa;
  IF v_cab IS NULL THEN
    RAISE EXCEPTION 'SEED QA-GAP: cabana % inexistente o inactiva.', c_cabana;
  END IF;

  -- G4: las dos islas no se tocan (incluidos los dias de borde).
  IF daterange(c_dA - 2, c_dA + 4, '[)') && daterange(c_dB, c_dB + 6, '[)') THEN
    RAISE EXCEPTION 'SEED QA-GAP: las islas A y B se solapan (dA=%, dB=%).', c_dA, c_dB;
  END IF;

  -- G5: RUNID limpio (no hay restos de una corrida anterior).
  SELECT count(*) INTO v_n FROM public.reservas WHERE source_event = c_runid;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'SEED QA-GAP: ya existen % reserva(s) con source_event=%.', v_n, c_runid;
  END IF;
  SELECT count(*) INTO v_n FROM public.huespedes WHERE notas_internas = c_runid;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'SEED QA-GAP: ya existen % huesped(es) con notas_internas=%.', v_n, c_runid;
  END IF;

  -- G6: las 4 identidades QA no existen (match por email exacto).
  SELECT count(*) INTO v_n FROM public.huespedes
   WHERE LOWER(email) IN (LOWER(c_mail_vA), LOWER(c_mail_vB), LOWER(c_mail_cA), LOWER(c_mail_cB));
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'SEED QA-GAP: % identidad(es) QA ya existen en huespedes.', v_n;
  END IF;

  -- G7a: NOCHES libres en ambas islas. daterange '[)' ESTRICTO (nunca '[]': en tipo
  --      discreto el limite superior inclusivo se canonicaliza y sumaria una noche).
  --      Isla A = [dA-2, dA+3)  (2 noches del vecino + 3 de la candidata)
  --      Isla B = [dB,   dB+5)  (3 noches de la candidata + 2 del vecino)
  SELECT count(*) INTO v_n FROM public.reservas r
   WHERE r.id_cabana = v_cab
     AND r.estado IN ('confirmada','activa','completada')
     AND ( daterange(r.fecha_checkin, r.fecha_checkout, '[)') && daterange(c_dA - 2, c_dA + 3, '[)')
        OR daterange(r.fecha_checkin, r.fecha_checkout, '[)') && daterange(c_dB,     c_dB + 5, '[)') );
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'SEED QA-GAP: % reserva(s) ocupan noches de las islas.', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.pre_reservas pr
   WHERE pr.id_cabana = v_cab
     AND ((pr.estado = 'pendiente_pago' AND pr.expira_en > NOW()) OR pr.estado = 'pago_en_revision')
     AND ( daterange(pr.fecha_in, pr.fecha_out, '[)') && daterange(c_dA - 2, c_dA + 3, '[)')
        OR daterange(pr.fecha_in, pr.fecha_out, '[)') && daterange(c_dB,     c_dB + 5, '[)') );
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'SEED QA-GAP: % pre-reserva(s) vigentes ocupan noches de las islas.', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.bloqueos b
   WHERE b.activo
     AND (b.id_cabana = v_cab OR b.id_cabana IS NULL)
     AND ( daterange(b.fecha_desde, b.fecha_hasta, '[)') && daterange(c_dA - 2, c_dA + 3, '[)')
        OR daterange(b.fecha_desde, b.fecha_hasta, '[)') && daterange(c_dB,     c_dB + 5, '[)') );
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'SEED QA-GAP: % bloqueo(s) activos sobre las islas.', v_n;
  END IF;

  -- G7b: BORDES limpios. Igualdad EXPLICITA (el validador solo mira los dias de borde).
  --   dA   / dB   : checkouts ajenos el dia en que ENTRA la candidata  -> caso A
  --   dA+3 / dB+3 : check-ins ajenos el dia en que SALE la candidata   -> caso B
  --   Critico: un checkout ajeno el dia dB secuestraria el error de la isla B, porque
  --   el validador ordena (motivo='checkin_pisa_checkout_anterior') DESC (caso A gana).
  SELECT count(*) INTO v_n FROM (
      SELECT 1 FROM public.reservas r
       WHERE r.id_cabana = v_cab AND r.estado IN ('confirmada','activa','completada')
         AND r.fecha_checkout IN (c_dA, c_dB)
      UNION ALL
      SELECT 1 FROM public.pre_reservas pr
       WHERE pr.id_cabana = v_cab
         AND ((pr.estado = 'pendiente_pago' AND pr.expira_en > NOW()) OR pr.estado = 'pago_en_revision')
         AND pr.fecha_out IN (c_dA, c_dB)
      UNION ALL
      SELECT 1 FROM public.reservas r
       WHERE r.id_cabana = v_cab AND r.estado IN ('confirmada','activa','completada')
         AND r.fecha_checkin IN (c_dA + 3, c_dB + 3)
      UNION ALL
      SELECT 1 FROM public.pre_reservas pr
       WHERE pr.id_cabana = v_cab
         AND ((pr.estado = 'pendiente_pago' AND pr.expira_en > NOW()) OR pr.estado = 'pago_en_revision')
         AND pr.fecha_in IN (c_dA + 3, c_dB + 3)
  ) x;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'SEED QA-GAP: % borde(s) contaminado(s) en dA/dA+3/dB/dB+3.', v_n;
  END IF;

  -- G8: horas base resueltas (fail-closed ante override invalido).
  v_rh := public.resolver_horario(v_cab, c_dA);
  IF (v_rh->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'SEED QA-GAP: resolver_horario(cab, dA) fallo: %', v_rh;
  END IF;
  v_bciA := (v_rh->>'hora_checkin')::time;

  v_rh := public.resolver_horario(v_cab, c_dB + 3);
  IF (v_rh->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'SEED QA-GAP: resolver_horario(cab, dB+3) fallo: %', v_rh;
  END IF;
  v_bcoB := (v_rh->>'hora_checkout')::time;

  ---------------------------------------------------------------- SIEMBRA
  -- VECINO A: ocupa [dA-2, dA). Su CHECKOUT congelado = bciA - 1h  (colisionante).
  -- telefono se omite (NULL) => trg_huespedes_telefono_norm deja telefono_normalizado NULL.
  INSERT INTO public.huespedes (nombre, email, notas_internas)
  VALUES ('QAGAP ' || c_runid || ' vecinoA', c_mail_vA, c_runid)
  RETURNING id_huesped INTO v_hue_vA;

  INSERT INTO public.reservas (
    id_cabana, id_huesped, fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
    personas, estado, canal_origen, monto_total, monto_sena, monto_saldo, source_event)
  VALUES (
    v_cab, v_hue_vA, c_dA - 2, c_dA,
    (public.resolver_horario(v_cab, c_dA - 2) ->> 'hora_checkin')::time,   -- hora normal
    (v_bciA - INTERVAL '1 hour')::time,                                    -- COLISIONANTE
    2, 'confirmada', 'manual', 1000.00, 300.00, 700.00, c_runid)
  RETURNING id_reserva INTO v_res_vA;

  -- VECINO B: ocupa [dB+3, dB+5). Su CHECK-IN congelado = bcoB + 1h  (colisionante).
  INSERT INTO public.huespedes (nombre, email, notas_internas)
  VALUES ('QAGAP ' || c_runid || ' vecinoB', c_mail_vB, c_runid)
  RETURNING id_huesped INTO v_hue_vB;

  INSERT INTO public.reservas (
    id_cabana, id_huesped, fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
    personas, estado, canal_origen, monto_total, monto_sena, monto_saldo, source_event)
  VALUES (
    v_cab, v_hue_vB, c_dB + 3, c_dB + 5,
    (v_bcoB + INTERVAL '1 hour')::time,                                    -- COLISIONANTE
    (public.resolver_horario(v_cab, c_dB + 5) ->> 'hora_checkout')::time,  -- hora normal
    2, 'confirmada', 'manual', 1000.00, 300.00, 700.00, c_runid)
  RETURNING id_reserva INTO v_res_vB;

  ---------------------------------------------------------------- ASSERTS de cardinalidad
  SELECT count(*) INTO v_n FROM public.reservas WHERE source_event = c_runid;
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'SEED QA-GAP: reservas del RUNID = % (esperado 2).', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.huespedes
   WHERE notas_internas = c_runid AND LOWER(email) IN (LOWER(c_mail_vA), LOWER(c_mail_vB));
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'SEED QA-GAP: huespedes vecinos = % (esperado 2).', v_n;
  END IF;

  ---------------------------------------------------------------- ASSERT geometria A
  v_g := public.validar_gap_bordes_congelados(
           v_cab,
           c_dA,     v_bciA,
           c_dA + 3, (public.resolver_horario(v_cab, c_dA + 3) ->> 'hora_checkout')::time);

  IF (v_g->>'ok')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'GEO-A: ok<>false -> %', v_g;
  END IF;
  IF v_g->>'error' <> 'checkin_pisa_checkout_anterior' THEN
    RAISE EXCEPTION 'GEO-A: error=% (esperado checkin_pisa_checkout_anterior).', v_g->>'error';
  END IF;
  IF jsonb_array_length(v_g->'conflictos') <> 1 THEN
    RAISE EXCEPTION 'GEO-A: conflictos=% (esperado exactamente 1) -> %',
      jsonb_array_length(v_g->'conflictos'), v_g;
  END IF;
  v_c := v_g->'conflictos'->0;
  IF (v_c->>'gap_minutos')::int <> 60 THEN
    RAISE EXCEPTION 'GEO-A: gap_minutos=% (esperado 60).', v_c->>'gap_minutos';
  END IF;
  IF v_c->>'lado' <> 'checkout' THEN
    RAISE EXCEPTION 'GEO-A: lado=% (esperado checkout).', v_c->>'lado';
  END IF;
  IF (v_c->>'fecha')::date <> c_dA THEN
    RAISE EXCEPTION 'GEO-A: fecha de borde=% (esperado %).', v_c->>'fecha', c_dA;
  END IF;
  IF v_c->>'tipo' <> 'reserva' THEN
    RAISE EXCEPTION 'GEO-A: tipo=% (esperado reserva).', v_c->>'tipo';
  END IF;
  IF (v_c->>'id')::bigint <> v_res_vA THEN
    RAISE EXCEPTION 'GEO-A: id vecino=% (esperado %).', v_c->>'id', v_res_vA;
  END IF;
  -- el vecino en conflicto es NUESTRO (reserva con source_event = RUNID)
  SELECT count(*) INTO v_n FROM public.reservas
   WHERE id_reserva = (v_c->>'id')::bigint AND source_event = c_runid;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'GEO-A: el vecino en conflicto NO pertenece al RUNID.';
  END IF;

  ---------------------------------------------------------------- ASSERT geometria B
  v_g := public.validar_gap_bordes_congelados(
           v_cab,
           c_dB,     (public.resolver_horario(v_cab, c_dB) ->> 'hora_checkin')::time,
           c_dB + 3, v_bcoB);

  IF (v_g->>'ok')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'GEO-B: ok<>false -> %', v_g;
  END IF;
  IF v_g->>'error' <> 'checkout_pisa_checkin_posterior' THEN
    RAISE EXCEPTION 'GEO-B: error=% (esperado checkout_pisa_checkin_posterior).', v_g->>'error';
  END IF;
  IF jsonb_array_length(v_g->'conflictos') <> 1 THEN
    RAISE EXCEPTION 'GEO-B: conflictos=% (esperado exactamente 1) -> %',
      jsonb_array_length(v_g->'conflictos'), v_g;
  END IF;
  v_c := v_g->'conflictos'->0;
  IF (v_c->>'gap_minutos')::int <> 60 THEN
    RAISE EXCEPTION 'GEO-B: gap_minutos=% (esperado 60).', v_c->>'gap_minutos';
  END IF;
  IF v_c->>'lado' <> 'checkin' THEN
    RAISE EXCEPTION 'GEO-B: lado=% (esperado checkin).', v_c->>'lado';
  END IF;
  IF (v_c->>'fecha')::date <> c_dB + 3 THEN
    RAISE EXCEPTION 'GEO-B: fecha de borde=% (esperado %).', v_c->>'fecha', c_dB + 3;
  END IF;
  IF v_c->>'tipo' <> 'reserva' THEN
    RAISE EXCEPTION 'GEO-B: tipo=% (esperado reserva).', v_c->>'tipo';
  END IF;
  IF (v_c->>'id')::bigint <> v_res_vB THEN
    RAISE EXCEPTION 'GEO-B: id vecino=% (esperado %).', v_c->>'id', v_res_vB;
  END IF;
  SELECT count(*) INTO v_n FROM public.reservas
   WHERE id_reserva = (v_c->>'id')::bigint AND source_event = c_runid;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'GEO-B: el vecino en conflicto NO pertenece al RUNID.';
  END IF;

  ---------------------------------------------------------------- SALIDA
  RAISE NOTICE '--------------------------------------------------------------';
  RAISE NOTICE 'SEED OK | runid=% | cabana=% (id=%)', c_runid, c_cabana, v_cab;
  RAISE NOTICE 'vecinoA  reserva=%  [% .. %)  checkout congelado=%  (base check-in candidata=%)',
    v_res_vA, c_dA - 2, c_dA, (v_bciA - INTERVAL '1 hour')::time, v_bciA;
  RAISE NOTICE 'vecinoB  reserva=%  [% .. %)  check-in congelado=%  (base check-out candidata=%)',
    v_res_vB, c_dB + 3, c_dB + 5, (v_bcoB + INTERVAL '1 hour')::time, v_bcoB;
  RAISE NOTICE '--------------------------------------------------------------';
  RAISE NOTICE 'UI candidataA:  % -> %   (email %)', c_dA, c_dA + 3, c_mail_cA;
  RAISE NOTICE 'UI candidataB:  % -> %   (email %)', c_dB, c_dB + 3, c_mail_cB;
  RAISE NOTICE 'DEJAR LOS CAMPOS DE HORA VACIOS EN LA UI: el SP congela el horario base';
  RAISE NOTICE 'y el gap queda en exactamente 60 min. Telefono VACIO en las dos candidatas.';
  RAISE NOTICE '--------------------------------------------------------------';
END
$seed$;

COMMIT;

-- Verificacion visual post-seed (read-only).
SELECT r.id_reserva, h.nombre, h.email, r.fecha_checkin, r.fecha_checkout,
       r.hora_checkin, r.hora_checkout, r.estado, r.source_event
  FROM public.reservas r
  JOIN public.huespedes h USING (id_huesped)
 WHERE r.source_event = '<RUNID>'
 ORDER BY r.fecha_checkin;
