-- ============================================================================
-- C_SLICE2_A08 — GATE RESIDUAL (read-only). crear_bloqueo solo escribe en las
-- tablas bloqueos + log_cambios. Esperado en un entorno limpio: 0 y 0.
-- Correr ANTES del smoke funcional (Bloque 3) y DESPUES del teardown (Bloque 6).
-- ============================================================================
SELECT 'bloqueos'    AS tabla, COUNT(*) AS n FROM bloqueos    WHERE source_event LIKE 'portal_test_a08_%'
UNION ALL
SELECT 'log_cambios' AS tabla, COUNT(*) AS n FROM log_cambios WHERE source_event LIKE 'portal_test_a08_%';
