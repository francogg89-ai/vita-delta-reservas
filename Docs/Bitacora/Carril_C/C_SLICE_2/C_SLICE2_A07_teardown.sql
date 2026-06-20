-- ============================================================================
-- C_SLICE2_A07 — BLOQUE 5: TEARDOWN FK-SAFE. Correr en TEST despues de las
-- verificaciones de escritura. Borra TODO el namespace de prueba
-- portal_test_a07_% en orden de dependencias (no rompe FKs):
--   pagos  ->  reservas  ->  pre_reservas  ->  huespedes (centinela)  ->  log_cambios
--
-- Sentinels EXCLUSIVOS del namespace A07 (source_event 'portal_test_a07_%',
-- idempotency_key 'portal_test_a07_%', huesped nombre 'PORTAL TEST A07%'). NO
-- toca datos reales ni fixtures de Carril B (seed_9f_*/9g_*/9h_*).
-- Transaccional (DO block): si algo falla, rollback completo.
-- ============================================================================
DO $$
DECLARE n_pagos INT; n_res INT; n_pre INT; n_hue INT; n_log INT; v_amb TEXT;
BEGIN
  -- Guard anti-OPS: abortar (rollback total) si este NO es el entorno TEST.
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ABORT anti-OPS: configuracion_general.ambiente=% (esperado ''test''). Ningun DELETE ejecutado.', COALESCE(v_amb, '<null>');
  END IF;

  -- 1) pagos primero (FK RESTRICT pagos.id_prereserva -> pre_reservas; y -> reservas).
  DELETE FROM pagos        WHERE source_event LIKE 'portal_test_a07_%';
  GET DIAGNOSTICS n_pagos = ROW_COUNT;

  -- 2) reservas (referencia pre_reservas y huespedes).
  DELETE FROM reservas     WHERE source_event LIKE 'portal_test_a07_%';
  GET DIAGNOSTICS n_res = ROW_COUNT;

  -- 3) pre_reservas (por source_event o idempotency_key del namespace).
  DELETE FROM pre_reservas WHERE source_event LIKE 'portal_test_a07_%'
                              OR idempotency_key LIKE 'portal_test_a07_%';
  GET DIAGNOSTICS n_pre = ROW_COUNT;

  -- 4) huespedes centinela (ya sin reservas/prereservas que los referencien).
  --    Incluye los creados por upsert_huesped en casos que fallaron luego
  --    (NODISP/CAPAC: huesped creado, prereserva no).
  DELETE FROM huespedes    WHERE nombre LIKE 'PORTAL TEST A07%';
  GET DIAGNOSTICS n_hue = ROW_COUNT;

  -- 5) log_cambios (sin FK; traza de los eventos de prueba).
  DELETE FROM log_cambios  WHERE source_event LIKE 'portal_test_a07_%';
  GET DIAGNOSTICS n_log = ROW_COUNT;

  RAISE NOTICE 'TEARDOWN A07: pagos=% reservas=% pre_reservas=% huespedes=% log_cambios=%',
               n_pagos, n_res, n_pre, n_hue, n_log;
END $$;

-- Acto seguido, correr C_SLICE2_A07_gate_residual.sql (BLOQUE 6): esperado TODOS 0.
