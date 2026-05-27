| sql_vista_disponibilidad                                                                                                                                                                                                                                                                                                                                                                                               |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|  SELECT id_cabana,
    fecha,
    estado,
    tipo_dia,
    temporada,
    hora_checkin_base,
    hora_checkout_base,
    id_reserva_activa,
    id_prereserva_activa
   FROM obtener_disponibilidad_rango(CURRENT_DATE, CURRENT_DATE + 60, NULL::bigint) obtener_disponibilidad_rango(id_cabana, fecha, estado, tipo_dia, temporada, hora_checkin_base, hora_checkout_base, id_reserva_activa, id_prereserva_activa); |