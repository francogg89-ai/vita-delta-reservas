-- C_SLICE2 / A10 - Gate POST-teardown: todo el namespace 'portal_test_a10_%' debe dar 0.
SELECT
  (SELECT COUNT(*) FROM pagos       WHERE source_event LIKE 'portal_test_a10_%')          AS pagos_ns,
  (SELECT COUNT(*) FROM log_cambios WHERE source_event LIKE 'portal_test_a10_%')          AS log_ns,
  (SELECT COUNT(*) FROM reservas    WHERE source_event LIKE 'portal_test_a10_%')          AS reservas_ns,
  (SELECT COUNT(*) FROM huespedes   WHERE nombre LIKE 'PORTAL TEST A10%')                 AS huespedes_ns;
