-- ============================================================================
-- E3_gate_no_escribe.sql  (READ-ONLY)
-- Conteo de las tablas que tocan A07/A10-MP. Corré este SELECT ANTES del smoke
-- de seguridad y DESPUÉS: si los conteos son IDÉNTICOS, ningún probe escribió
-- (confirma que action mismatch / firma inválida / rol / ambiente rebotan ANTES
-- de los nodos de escritura). NO modifica nada.
-- ============================================================================
SELECT 'reservas'     AS tabla, count(*) AS filas FROM reservas
UNION ALL
SELECT 'pre_reservas' AS tabla, count(*)          FROM pre_reservas
UNION ALL
SELECT 'pagos'        AS tabla, count(*)          FROM pagos
ORDER BY tabla;
