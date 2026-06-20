-- ============================================================================
-- C_SLICE2_A08 — BLOQUE 5: TEARDOWN. crear_bloqueo solo escribe en bloqueos +
-- log_cambios (no crea huespedes/reservas/prereservas), asi que el teardown es
-- mucho mas simple que el de A07. Guard anti-OPS: aborta (rollback total) si el
-- entorno no es TEST. Sentinels EXCLUSIVOS del namespace A08 (source_event
-- 'portal_test_a08_%'). NO toca datos reales ni fixtures de Carril B.
-- ============================================================================
DO $$
DECLARE n_blo INT; n_log INT; v_amb TEXT;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ABORT anti-OPS: configuracion_general.ambiente=% (esperado ''test''). Ningun DELETE ejecutado.', COALESCE(v_amb, '<null>');
  END IF;

  DELETE FROM bloqueos    WHERE source_event LIKE 'portal_test_a08_%';
  GET DIAGNOSTICS n_blo = ROW_COUNT;

  DELETE FROM log_cambios WHERE source_event LIKE 'portal_test_a08_%';
  GET DIAGNOSTICS n_log = ROW_COUNT;

  RAISE NOTICE 'TEARDOWN A08: bloqueos=% log_cambios=%', n_blo, n_log;
END $$;

-- Acto seguido, correr C_SLICE2_A08_gate_residual.sql (BLOQUE 6): esperado 0 y 0.
