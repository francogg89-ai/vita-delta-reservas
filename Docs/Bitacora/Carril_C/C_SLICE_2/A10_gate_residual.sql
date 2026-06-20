-- C_SLICE2 / A10 - Gate de residuales de ESCRITURAS A10 (no cuenta fixtures de setup).
-- Distingue: 'portal_test_a10_res%' = pagos creados por la accion A10 (smokes).
--            'portal_test_a10_setup%' = fixtures (se ignoran aca).
-- PRE-funcional debe dar 0/0. POST-teardown se usa A10_gate_post (namespace completo).
SELECT
  (SELECT COUNT(*) FROM pagos       WHERE source_event LIKE 'portal_test_a10_res%') AS pagos_a10_smoke,
  (SELECT COUNT(*) FROM log_cambios WHERE source_event LIKE 'portal_test_a10_res%') AS log_a10_smoke;
