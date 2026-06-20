-- C_SLICE2 / A10 -- Nodo PG_verif_post (read-only, post-COMMIT). $1 = sql_payload jsonb.
-- Relee por source_event, confirma estado del pago y RECALCULA saldo_real con la MISMA
-- normalizacion byte-alineada a A12 (reserva_por_prereserva + pagos_reserva_normalizados +
-- FILTER-en-SUM). No escribe. Devuelve 'resultado' jsonb.
WITH
  pago AS (
    SELECT id_pago, estado
    FROM pagos
    WHERE source_event = ($1::jsonb)->>'source_event'
    ORDER BY id_pago
    LIMIT 1
  ),
  reserva_por_prereserva AS (
    SELECT id_pre_reserva, MIN(id_reserva) AS id_reserva
    FROM reservas
    WHERE id_pre_reserva IS NOT NULL
    GROUP BY id_pre_reserva
  ),
  pagos_reserva_normalizados AS (
    SELECT p.estado, p.tipo, p.monto_recibido,
           COALESCE(p.id_reserva, rpp.id_reserva) AS id_reserva_normalizado
    FROM pagos p
    LEFT JOIN reserva_por_prereserva rpp ON rpp.id_pre_reserva = p.id_prereserva
  ),
  pagado AS (
    SELECT COALESCE(SUM(prn.monto_recibido) FILTER (
             WHERE prn.estado = 'confirmado' AND prn.tipo IN ('sena', 'saldo')), 0) AS total_pagado_confirmado
    FROM pagos_reserva_normalizados prn
    WHERE prn.id_reserva_normalizado = (($1::jsonb)->>'id_reserva')::bigint
  )
SELECT jsonb_build_object(
  'id_pago',           (SELECT id_pago FROM pago),
  'estado_pago',       (SELECT estado::text FROM pago),
  'pago_confirmado',   COALESCE((SELECT estado::text FROM pago) = 'confirmado', false),
  'saldo_real_actual', (SELECT monto_total FROM reservas WHERE id_reserva = (($1::jsonb)->>'id_reserva')::bigint)
                       - (SELECT total_pagado_confirmado FROM pagado)
) AS resultado;
