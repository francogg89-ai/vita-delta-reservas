Título: Motor db_recalcular_disponibilidad — detectar superposición entre RESERVAS confirmadas

Descripción:
Si dos reservas confirmadas/activas ocupan la misma noche
para la misma cabaña, el motor actualmente marca la fecha
como 'ocupada' con el id_reserva del primero que encuentra,
sin registrar warning.

Esto no debería ocurrir en producción si db_crear_prereserva
y db_confirmar_reserva validan disponibilidad antes de escribir.

Mejora propuesta:
En PASO 2 del Motor de Cálculo, si se detectan 2+ reservas
ocupando la misma noche para la misma cabaña, agregar un
warning nivel 'error' al array warnings con los ids
involucrados. Ese warning quedaría visible en LOG_CAMBIOS.

Implementar cuando db_confirmar_reserva esté funcionando.

Label: mejora-futura
Milestone: Motor de Reservas (Etapa 4A)