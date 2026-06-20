-- ============================================================================
-- C_SLICE2 / A10 GATEWAY -- Verificacion de escrituras + actor inyectado (read-only).
-- Confirma lo que el envelope NO muestra: el actor (validado_por) salio del JWT
-- (server-side), no del payload; y que la REGRESION de sobrepago (9900006) NO escribio.
--
-- Los pagos de saldo escritos por el smoke tienen source_event 'portal_test_a10_res%'
-- (derivado de id_reserva|idempotency_key) y tipo 'saldo'. Las senas de A10_setup.sql
-- son 'portal_test_a10_setup_sena_%' y tipo 'sena' (quedan excluidas por el filtro tipo).
-- PRE: correr DESPUES del smoke y ANTES del teardown.
-- ============================================================================

WITH smoke_saldo AS (
  SELECT *
  FROM pagos
  WHERE source_event LIKE 'portal_test_a10_res%'
    AND tipo = 'saldo'
)
SELECT 'GW_a_VICKY_9900001  (esp: 1 / vicky / 50000)'  AS caso,
       COUNT(*)                                        AS pagos,
       COALESCE(MAX(validado_por), '(none)')           AS validado_por,
       COALESCE(MAX(monto_recibido)::text, '(none)')   AS monto
FROM smoke_saldo WHERE id_reserva = 9900001
UNION ALL
SELECT 'GW_b_FRANCO_9900002 (esp: 1 / franco / 70000)',
       COUNT(*), COALESCE(MAX(validado_por), '(none)'), COALESCE(MAX(monto_recibido)::text, '(none)')
FROM smoke_saldo WHERE id_reserva = 9900002
UNION ALL
SELECT 'GW_R_SOBREPAGO_9900006 (esp: 0 / none / none)',
       COUNT(*), COALESCE(MAX(validado_por), '(none)'), COALESCE(MAX(monto_recibido)::text, '(none)')
FROM smoke_saldo WHERE id_reserva = 9900006
ORDER BY caso;

-- Listado de control: TODAS las escrituras de saldo del smoke gateway (esperado: exactamente
-- 2 filas -> 9900001 y 9900002; ninguna otra reserva debe aparecer).
SELECT p.id_reserva,
       p.tipo,
       p.medio_pago,
       p.estado::text AS estado_pago,
       p.monto_recibido,
       p.validado_por,
       p.source_event
FROM pagos p
WHERE p.source_event LIKE 'portal_test_a10_res%'
  AND p.tipo = 'saldo'
ORDER BY p.id_reserva, p.id_pago;
