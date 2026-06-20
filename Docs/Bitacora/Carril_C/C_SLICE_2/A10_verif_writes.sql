-- C_SLICE2 / A10 - Verificacion de escrituras tras el bloque funcional.
-- Lista cada pago de saldo creado por A10 (smokes) con su reserva, estado y monto.
-- Esperado (segun runsheet): FELIZ=1, RETRY/MISMATCH no agregan, COMPLETA=1, SOBREPAGO/SALDADA/CANCELADA=0.
SELECT
  p.id_reserva,
  p.source_event,
  p.tipo,
  p.medio_pago,
  p.estado::text AS estado_pago,
  p.monto_recibido,
  p.validado_por,
  p.created_at
FROM pagos p
WHERE p.source_event LIKE 'portal_test_a10_res%'
ORDER BY p.id_reserva, p.id_pago;
