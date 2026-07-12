-- =====================================================================
-- QAGAP_C_CLEANUP_TEST.sql
-- Teardown del fixture QA de gap de turno. Transaccion UNICA, fail-closed.
-- ---------------------------------------------------------------------
-- ALCANCE: SOLO TEST (gate transaccional sobre configuracion_general.ambiente).
--
-- PRINCIPIO RECTOR: este script NO limpia evidencia de fallo.
-- Si una candidata quedo persistida como pre-reserva o como reserva, eso significa
-- que el GAP NO CORTO. En ese caso el script hace RAISE EXCEPTION y ROLLBACK,
-- dejando TODO en su lugar para que puedas diagnosticar. Por eso NO se captura ni
-- se borra genericamente "toda reserva cuyo id_huesped sea QA": eso ocultaria
-- exactamente el fallo que estamos tratando de detectar.
--
-- IDENTIFICACION: por EMAIL EXACTO (constante), nunca por el nombre tipeado en la UI.
--   vecinos    : notas_internas = RUNID  AND lower(email) IN (vA, vB)
--   candidatas : lower(email) IN (cA, cB)
--
-- CARDINALIDADES ESPERADAS (tras correr los casos A y B en el portal):
--   2 huespedes vecinos | 2 huespedes candidatas
--   2 reservas (exclusivamente las vecinas, source_event = RUNID)
--   0 pre_reservas QA   | 0 pagos QA
-- Si abortaste antes de probar el portal, pone c_candidatas_esperadas := 0.
--
-- PAGOS: no se borra ningun pago. Se asserta 0; si aparece alguno se informan los
-- id_pago y se aborta (el CHECK chk_pagos_referencia_minima puede romper un SET NULL).
--
-- Ejecutar el script ENTERO (sin seleccion parcial).
-- =====================================================================

BEGIN;

DO $cleanup$
DECLARE
  ---------------------------------------------------------------- PARAMETROS
  c_runid   CONSTANT text := 'qagap_20260712_01';
  c_cabana  CONSTANT text := 'Tokio';
  c_mail_vA CONSTANT text := 'qagap+qagap_20260712_01.vecinoa@example.invalid';
  c_mail_vB CONSTANT text := 'qagap+qagap_20260712_01.vecinob@example.invalid';
  c_mail_cA CONSTANT text := 'qagap+qagap_20260712_01.candidataa@example.invalid';
  c_mail_cB CONSTANT text := 'qagap+qagap_20260712_01.candidatab@example.invalid';
  -- 2 = corriste los casos A y B (default).  0 = abortaste antes de tocar el portal.
  c_candidatas_esperadas CONSTANT int := 2;
  ---------------------------------------------------------------- ESTADO
  v_amb text; v_cab bigint;
  v_ids_vec bigint[]; v_ids_can bigint[]; v_ids_all bigint[];
  v_ids_res_vec bigint[]; v_ids_pag bigint[];
  v_n int; v_bad int;
  v_n_res int; v_n_hue int;
BEGIN
  ---------------------------------------------------------------- GATES
  -- G1: ambiente TEST (anti-OPS).
  v_amb := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'CLEANUP QA-GAP: ambiente=% (esperado test). ROLLBACK.', COALESCE(v_amb,'<null>');
  END IF;

  SELECT id_cabana INTO v_cab FROM public.cabanas WHERE nombre = c_cabana;
  IF v_cab IS NULL THEN
    RAISE EXCEPTION 'CLEANUP QA-GAP: cabana % inexistente.', c_cabana;
  END IF;

  ---------------------------------------------------------------- (1) CAPTURA (antes de borrar)
  -- Vecinos: email exacto + tag. Candidatas: email exacto (el nombre lo tipeas vos: no es autoridad).
  SELECT COALESCE(array_agg(id_huesped ORDER BY id_huesped), '{}'::bigint[])
    INTO v_ids_vec
    FROM public.huespedes
   WHERE notas_internas = c_runid
     AND LOWER(email) IN (LOWER(c_mail_vA), LOWER(c_mail_vB));

  SELECT COALESCE(array_agg(id_huesped ORDER BY id_huesped), '{}'::bigint[])
    INTO v_ids_can
    FROM public.huespedes
   WHERE LOWER(email) IN (LOWER(c_mail_cA), LOWER(c_mail_cB));

  v_ids_all := v_ids_vec || v_ids_can;

  ---------------------------------------------------------------- (2) ASSERTS de identidad
  -- Cada email vecino: exactamente 1 fila.
  SELECT count(*) INTO v_n FROM public.huespedes WHERE LOWER(email) = LOWER(c_mail_vA);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CLEANUP: vecinoA (%) tiene % fila(s), esperado 1.', c_mail_vA, v_n; END IF;
  SELECT count(*) INTO v_n FROM public.huespedes WHERE LOWER(email) = LOWER(c_mail_vB);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CLEANUP: vecinoB (%) tiene % fila(s), esperado 1.', c_mail_vB, v_n; END IF;

  -- Cada email candidato: exactamente 1 fila (si se corrieron los dos casos).
  SELECT count(*) INTO v_n FROM public.huespedes WHERE LOWER(email) = LOWER(c_mail_cA);
  IF v_n <> LEAST(c_candidatas_esperadas, 1) THEN
    RAISE EXCEPTION 'CLEANUP: candidataA (%) tiene % fila(s), esperado %.',
      c_mail_cA, v_n, LEAST(c_candidatas_esperadas, 1);
  END IF;
  SELECT count(*) INTO v_n FROM public.huespedes WHERE LOWER(email) = LOWER(c_mail_cB);
  IF v_n <> GREATEST(c_candidatas_esperadas - 1, 0) THEN
    RAISE EXCEPTION 'CLEANUP: candidataB (%) tiene % fila(s), esperado %.',
      c_mail_cB, v_n, GREATEST(c_candidatas_esperadas - 1, 0);
  END IF;

  IF COALESCE(array_length(v_ids_vec, 1), 0) <> 2 THEN
    RAISE EXCEPTION 'CLEANUP: vecinos capturados = % (esperado 2).', COALESCE(array_length(v_ids_vec,1),0);
  END IF;
  IF COALESCE(array_length(v_ids_can, 1), 0) <> c_candidatas_esperadas THEN
    RAISE EXCEPTION 'CLEANUP: candidatas capturadas = % (esperado %).',
      COALESCE(array_length(v_ids_can,1),0), c_candidatas_esperadas;
  END IF;

  -- Ningun OTRO huesped con notas_internas = RUNID (fuera de los 2 vecinos).
  SELECT count(*) INTO v_bad FROM public.huespedes
   WHERE notas_internas = c_runid AND NOT (id_huesped = ANY(v_ids_vec));
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'CLEANUP: % huesped(es) con notas_internas=% fuera de los 2 vecinos.', v_bad, c_runid;
  END IF;

  -- Ningun OTRO huesped con el nombre del RUNID fuera de los 4 emails QA.
  SELECT count(*) INTO v_bad FROM public.huespedes
   WHERE nombre LIKE 'QAGAP ' || c_runid || '%'
     AND LOWER(COALESCE(email,'')) NOT IN
         (LOWER(c_mail_vA), LOWER(c_mail_vB), LOWER(c_mail_cA), LOWER(c_mail_cB));
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'CLEANUP: % huesped(es) con nombre del RUNID pero email ajeno a las 4 identidades QA.', v_bad;
  END IF;

  ---------------------------------------------------------------- (3) ASSERTS de integridad del experimento
  -- 3.1 exactamente 2 reservas vecinas con source_event = RUNID, y son de los vecinos.
  SELECT COALESCE(array_agg(id_reserva ORDER BY id_reserva), '{}'::bigint[])
    INTO v_ids_res_vec
    FROM public.reservas
   WHERE source_event = c_runid;
  IF COALESCE(array_length(v_ids_res_vec, 1), 0) <> 2 THEN
    RAISE EXCEPTION 'CLEANUP: reservas con source_event=% son % (esperado 2).',
      c_runid, COALESCE(array_length(v_ids_res_vec,1),0);
  END IF;

  SELECT count(*) INTO v_bad FROM public.reservas
   WHERE id_reserva = ANY(v_ids_res_vec)
     AND NOT (id_cabana = v_cab AND id_huesped = ANY(v_ids_vec));
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'CLEANUP: % reserva(s) del RUNID no pertenecen a los vecinos/cabana del fixture.', v_bad;
  END IF;

  -- 3.2 CERO reservas asociadas a las candidatas.
  --     Si hay alguna, el gap NO corto: es EVIDENCIA. No se borra nada.
  SELECT count(*) INTO v_bad FROM public.reservas WHERE id_huesped = ANY(v_ids_can);
  IF v_bad <> 0 THEN
    RAISE EXCEPTION
      'CLEANUP ABORTADO: % reserva(s) asociadas a candidataA/candidataB. El gap NO corto: la reserva se creo. '
      'NO se limpia la evidencia. Revisa reservas de los huespedes % y volve a correr el cleanup despues de diagnosticar.',
      v_bad, v_ids_can;
  END IF;

  -- 3.3 CERO pre-reservas asociadas a las candidatas (misma logica: evidencia de que el gap no corto).
  SELECT count(*) INTO v_bad FROM public.pre_reservas WHERE id_huesped = ANY(v_ids_can);
  IF v_bad <> 0 THEN
    RAISE EXCEPTION
      'CLEANUP ABORTADO: % pre-reserva(s) asociadas a candidataA/candidataB. El gap NO corto en crear_prereserva. '
      'NO se limpia la evidencia. Huespedes candidatos: %.', v_bad, v_ids_can;
  END IF;

  -- 3.4 los VECINOS no tienen pre-reservas ni reservas fuera del RUNID.
  SELECT count(*) INTO v_bad FROM public.pre_reservas WHERE id_huesped = ANY(v_ids_vec);
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'CLEANUP: los vecinos tienen % pre-reserva(s) inesperadas.', v_bad;
  END IF;
  SELECT count(*) INTO v_bad FROM public.reservas
   WHERE id_huesped = ANY(v_ids_vec) AND source_event IS DISTINCT FROM c_runid;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'CLEANUP: los vecinos tienen % reserva(s) ajenas al RUNID.', v_bad;
  END IF;

  -- 3.5 CERO pagos asociados a cualquier identidad QA. No se borran pagos: se aborta.
  SELECT COALESCE(array_agg(id_pago ORDER BY id_pago), '{}'::bigint[])
    INTO v_ids_pag
    FROM public.pagos p
   WHERE (p.id_reserva IS NOT NULL AND p.id_reserva IN (
            SELECT id_reserva FROM public.reservas
             WHERE source_event = c_runid OR id_huesped = ANY(v_ids_all)))
      OR (p.id_prereserva IS NOT NULL AND p.id_prereserva IN (
            SELECT id_pre_reserva FROM public.pre_reservas WHERE id_huesped = ANY(v_ids_all)));
  IF COALESCE(array_length(v_ids_pag, 1), 0) <> 0 THEN
    RAISE EXCEPTION
      'CLEANUP ABORTADO: % pago(s) referencian el fixture (esperado 0). id_pago=%. '
      'Los pagos NO se borran automaticamente. Resolvelos a mano y volve a correr.',
      array_length(v_ids_pag,1), v_ids_pag;
  END IF;

  ---------------------------------------------------------------- (4) DELETES (solo lo verificado)
  -- Orden FK: reservas (FK -> huespedes RESTRICT) y despues huespedes.
  -- No hay pre_reservas ni pagos QA (asertado en 3.3 / 3.4 / 3.5).
  DELETE FROM public.reservas WHERE id_reserva = ANY(v_ids_res_vec);
  GET DIAGNOSTICS v_n_res = ROW_COUNT;
  IF v_n_res <> 2 THEN
    RAISE EXCEPTION 'CLEANUP: se borraron % reserva(s) vecinas (esperado 2).', v_n_res;
  END IF;

  DELETE FROM public.huespedes WHERE id_huesped = ANY(v_ids_all);
  GET DIAGNOSTICS v_n_hue = ROW_COUNT;
  IF v_n_hue <> COALESCE(array_length(v_ids_all, 1), 0) THEN
    RAISE EXCEPTION 'CLEANUP: se borraron % huesped(es), esperado %.',
      v_n_hue, COALESCE(array_length(v_ids_all,1), 0);
  END IF;

  ---------------------------------------------------------------- (5) RESIDUO CERO
  SELECT count(*) INTO v_n FROM public.reservas
   WHERE source_event = c_runid OR id_reserva = ANY(v_ids_res_vec);
  IF v_n <> 0 THEN RAISE EXCEPTION 'CLEANUP: residuo reservas=%.', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.pre_reservas WHERE id_huesped = ANY(v_ids_all);
  IF v_n <> 0 THEN RAISE EXCEPTION 'CLEANUP: residuo pre_reservas=%.', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.huespedes
   WHERE id_huesped = ANY(v_ids_all)
      OR notas_internas = c_runid
      OR LOWER(email) IN (LOWER(c_mail_vA), LOWER(c_mail_vB), LOWER(c_mail_cA), LOWER(c_mail_cB))
      OR nombre LIKE 'QAGAP ' || c_runid || '%';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CLEANUP: residuo huespedes=%.', v_n; END IF;

  RAISE NOTICE '--------------------------------------------------------------';
  RAISE NOTICE 'CLEANUP OK | runid=% | reservas borradas=% | huespedes borrados=%',
    c_runid, v_n_res, v_n_hue;
  RAISE NOTICE 'vecinos=%  candidatas=%  | pre_reservas QA=0  pagos QA=0',
    array_length(v_ids_vec,1), COALESCE(array_length(v_ids_can,1),0);
  RAISE NOTICE 'Residuo aceptado y declarado: secuencias, logs de n8n y portal_idempotencia';
  RAISE NOTICE '(append-only). reservas/huespedes NO tienen triggers de INSERT/DELETE que';
  RAISE NOTICE 'escriban log_cambios, y el gap corta antes del INSERT INTO log_cambios.';
  RAISE NOTICE '--------------------------------------------------------------';
END
$cleanup$;

COMMIT;

-- Residuo cero (read-only, post-commit). Debe dar 0 / 0 / 0.
SELECT
  (SELECT count(*) FROM public.reservas  WHERE source_event = 'qagap_20260712_01')                 AS reservas_runid,
  (SELECT count(*) FROM public.huespedes WHERE notas_internas = 'qagap_20260712_01')               AS huespedes_tag,
  (SELECT count(*) FROM public.huespedes WHERE LOWER(email) IN (
      LOWER('qagap+qagap_20260712_01.vecinoa@example.invalid'),
      LOWER('qagap+qagap_20260712_01.vecinob@example.invalid'),
      LOWER('qagap+qagap_20260712_01.candidataa@example.invalid'),
      LOWER('qagap+qagap_20260712_01.candidatab@example.invalid')))                                AS huespedes_qa_email;
