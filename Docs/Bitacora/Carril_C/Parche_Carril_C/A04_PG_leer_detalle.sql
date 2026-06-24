WITH reserva_por_prereserva AS (
  SELECT id_pre_reserva, MIN(id_reserva) AS id_reserva
  FROM reservas
  WHERE id_pre_reserva IS NOT NULL
  GROUP BY id_pre_reserva
),
pagos_norm AS (
  SELECT COALESCE(p.id_reserva, rpp.id_reserva) AS id_reserva_norm,
         p.estado, p.tipo, p.monto_recibido
  FROM pagos p
  LEFT JOIN reserva_por_prereserva rpp ON rpp.id_pre_reserva = p.id_prereserva
)
SELECT vc.id_cabana, vc.id_reserva, vc.fecha_checkin, vc.fecha_checkout,
       vc.hora_checkin, vc.hora_checkout, vc.personas, vc.estado_reserva,
       vc.huesped_nombre, vc.huesped_telefono, vc.monto_total,
       (vc.monto_total - COALESCE((
          SELECT SUM(pn.monto_recibido)
          FROM pagos_norm pn
          WHERE pn.id_reserva_norm = vc.id_reserva
            AND pn.estado = 'confirmado'
            AND pn.tipo IN ('sena','saldo')
       ), 0))::numeric(12,2) AS saldo_real,
       r.notas_reserva
FROM vista_calendario vc
LEFT JOIN reservas r ON r.id_reserva = vc.id_reserva
WHERE vc.fecha_checkin < CURRENT_DATE + INTERVAL '120 days'
  AND vc.fecha_checkout > CURRENT_DATE
ORDER BY vc.id_cabana, vc.fecha_checkin;
