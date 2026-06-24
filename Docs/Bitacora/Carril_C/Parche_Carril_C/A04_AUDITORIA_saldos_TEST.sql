-- =====================================================================================
-- AUDITORÍA de saldos negativos en TEST (read-only). Misma lógica que el wrapper A12/A04:
--   reserva_por_prereserva = MIN(id_reserva) por id_pre_reserva (mapeo determinístico)
--   pago normalizado a reserva = COALESCE(p.id_reserva, vía id_prereserva)
--   saldo_real = monto_total − SUM(pagos confirmados tipo sena/saldo, normalizados)
-- NO modifica nada. Correr cada consulta por separado (el SQL Editor de Supabase corre
-- solo el texto seleccionado).
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- CONSULTA A — Resumen por reserva (ordenado: saldo más negativo primero)
-- Muestra por reserva: monto_total, pagado confirmado (lo que usa el cálculo), saldo_real,
-- y el DESGLOSE de dónde vino el pago: directo por id_reserva vs vía id_prereserva, más
-- los conteos de pagos (n_pagos_confirmados alto = posible duplicación).
-- -------------------------------------------------------------------------------------
WITH reserva_por_prereserva AS (
  SELECT id_pre_reserva, MIN(id_reserva) AS id_reserva
  FROM reservas
  WHERE id_pre_reserva IS NOT NULL
  GROUP BY id_pre_reserva
),
pagos_norm AS (
  SELECT p.id_pago,
         p.id_reserva                              AS id_reserva_directo,
         p.id_prereserva,
         rpp.id_reserva                            AS id_reserva_via_prereserva,
         COALESCE(p.id_reserva, rpp.id_reserva)    AS id_reserva_norm,
         p.estado, p.tipo, p.monto_recibido
  FROM pagos p
  LEFT JOIN reserva_por_prereserva rpp ON rpp.id_pre_reserva = p.id_prereserva
)
SELECT
  r.id_reserva,
  TRIM(BOTH FROM (h.nombre || ' ') || COALESCE(h.apellido, '')) AS huesped,
  c.nombre AS cabana,
  r.monto_total,
  COALESCE(SUM(pn.monto_recibido) FILTER (
    WHERE pn.estado = 'confirmado' AND pn.tipo IN ('sena','saldo')), 0) AS pagado_confirmado,
  (r.monto_total - COALESCE(SUM(pn.monto_recibido) FILTER (
    WHERE pn.estado = 'confirmado' AND pn.tipo IN ('sena','saldo')), 0))::numeric(12,2) AS saldo_real,
  COALESCE(SUM(pn.monto_recibido) FILTER (
    WHERE pn.estado = 'confirmado' AND pn.tipo IN ('sena','saldo')
      AND pn.id_reserva_directo IS NOT NULL), 0) AS pagado_directo_id_reserva,
  COALESCE(SUM(pn.monto_recibido) FILTER (
    WHERE pn.estado = 'confirmado' AND pn.tipo IN ('sena','saldo')
      AND pn.id_reserva_directo IS NULL), 0) AS pagado_via_prereserva,
  COUNT(*) FILTER (
    WHERE pn.estado = 'confirmado' AND pn.tipo IN ('sena','saldo')) AS n_pagos_confirmados,
  COUNT(pn.id_pago) AS n_pagos_asociados_total
FROM reservas r
JOIN cabanas   c ON c.id_cabana  = r.id_cabana
JOIN huespedes h ON h.id_huesped = r.id_huesped
LEFT JOIN pagos_norm pn ON pn.id_reserva_norm = r.id_reserva
WHERE r.estado IN ('confirmada','activa','completada')
GROUP BY r.id_reserva, r.monto_total, h.nombre, h.apellido, c.nombre
ORDER BY saldo_real ASC, r.id_reserva;


-- -------------------------------------------------------------------------------------
-- CONSULTA B — Detalle de pagos por reserva (una fila por pago)
-- Lista CADA pago asociado a las reservas activas, mostrando si vino directo (id_reserva)
-- o vía id_prereserva, su tipo/estado/monto. Acá se ven los duplicados/sobrepagos a ojo.
-- (Para enfocar una reserva puntual, agregá:  AND COALESCE(p.id_reserva, rpp.id_reserva) = 13 )
-- -------------------------------------------------------------------------------------
WITH reserva_por_prereserva AS (
  SELECT id_pre_reserva, MIN(id_reserva) AS id_reserva
  FROM reservas
  WHERE id_pre_reserva IS NOT NULL
  GROUP BY id_pre_reserva
),
activas AS (
  SELECT id_reserva FROM reservas WHERE estado IN ('confirmada','activa','completada')
)
SELECT
  COALESCE(p.id_reserva, rpp.id_reserva) AS id_reserva_norm,
  p.id_pago,
  p.id_reserva     AS id_reserva_directo,
  p.id_prereserva,
  rpp.id_reserva   AS id_reserva_via_prereserva,
  p.tipo,
  p.estado,
  p.monto_recibido,
  p.es_automatico,
  p.created_at
FROM pagos p
LEFT JOIN reserva_por_prereserva rpp ON rpp.id_pre_reserva = p.id_prereserva
WHERE COALESCE(p.id_reserva, rpp.id_reserva) IN (SELECT id_reserva FROM activas)
ORDER BY id_reserva_norm, p.created_at, p.id_pago;
