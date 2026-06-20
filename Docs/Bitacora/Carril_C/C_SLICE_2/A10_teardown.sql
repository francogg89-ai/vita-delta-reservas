-- ============================================================================
-- C_SLICE2 / A10 - TEARDOWN (TEST ONLY). Guard anti-OPS + DELETE FK-safe atomicos.
-- Borra TODO el namespace 'portal_test_a10_%' (fixtures de setup + escrituras de smokes).
-- Orden FK-safe: log_cambios -> pagos (hoja) -> reservas -> huespedes centinela.
-- ============================================================================
DO $a10_teardown$
DECLARE
  v_amb TEXT;
  n_log INT; n_pag INT; n_res INT; n_hue INT;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ANTI-OPS: ambiente=% (se esperaba test). TEARDOWN A10 abortado.', v_amb;
  END IF;

  DELETE FROM log_cambios WHERE source_event LIKE 'portal_test_a10_%';
  GET DIAGNOSTICS n_log = ROW_COUNT;

  DELETE FROM pagos WHERE source_event LIKE 'portal_test_a10_%';
  GET DIAGNOSTICS n_pag = ROW_COUNT;

  DELETE FROM reservas WHERE source_event LIKE 'portal_test_a10_%';
  GET DIAGNOSTICS n_res = ROW_COUNT;

  DELETE FROM huespedes WHERE nombre LIKE 'PORTAL TEST A10%';
  GET DIAGNOSTICS n_hue = ROW_COUNT;

  RAISE NOTICE 'TEARDOWN A10 OK. Borrados -> log_cambios:% pagos:% reservas:% huespedes:%', n_log, n_pag, n_res, n_hue;
END
$a10_teardown$;
