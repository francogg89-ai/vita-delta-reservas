-- ============================================================================
-- C_SLICE2_A07 — GATE RESIDUAL (BLOQUE 2 pre-write  +  BLOQUE 6 post-teardown)
-- Cuenta filas del namespace de prueba portal_test_a07_% en las 5 tablas
-- tocadas. Read-only. Correr en TEST (vita-delta-test).
--   BLOQUE 2: ANTES de cualquier escritura  -> esperado TODOS 0.
--   BLOQUE 6: DESPUES del teardown           -> esperado TODOS 0.
-- Si alguna fila > 0 en el Bloque 2, NO avanzar a escritura (hay residual de
-- una corrida previa: correr el teardown primero).
-- ============================================================================
SELECT 'pagos'               AS tabla, count(*) AS n FROM pagos        WHERE source_event LIKE 'portal_test_a07_%'
UNION ALL
SELECT 'reservas',           count(*) FROM reservas     WHERE source_event LIKE 'portal_test_a07_%'
UNION ALL
SELECT 'pre_reservas',       count(*) FROM pre_reservas WHERE source_event LIKE 'portal_test_a07_%'
                                                            OR idempotency_key LIKE 'portal_test_a07_%'
UNION ALL
SELECT 'huespedes_centinela', count(*) FROM huespedes   WHERE nombre LIKE 'PORTAL TEST A07%'
UNION ALL
SELECT 'log_cambios',        count(*) FROM log_cambios  WHERE source_event LIKE 'portal_test_a07_%'
ORDER BY tabla;
-- Esperado (B2 y B6): n = 0 en las 5 filas.
