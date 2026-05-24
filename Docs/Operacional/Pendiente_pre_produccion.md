# Pendientes Pre-Producción

Lista de cambios a aplicar antes del despliegue de producción.
Ítems destinados a producción que NO se hacen en DEV para mantener
la trazabilidad de cómo evolucionó el sistema.

---

## Configuración y vistas

### Horizonte de disponibilidad — pasar de hardcoded a configurable

**Estado actual (DEV):** `vista_disponibilidad` y `vista_calendario` 
tienen el horizonte hardcoded a 60 días forward.

**Cambio para producción:**
1. Agregar clave a `configuracion_general`:
   - clave: `horizonte_disponibilidad_dias`
   - valor: `120`
   - tipo_valor: `integer`
   - descripcion: `Horizonte forward en días para vista_disponibilidad y vista_calendario`

2. Modificar `vista_disponibilidad` para leer desde config (snippet abajo).
3. Modificar `vista_calendario` para leer desde config (snippet abajo).

**Snippet listo para producción:**

\`\`\`sql
-- vista_disponibilidad con horizonte configurable
CREATE OR REPLACE VIEW vista_disponibilidad AS
SELECT *
FROM obtener_disponibilidad_rango(
  CURRENT_DATE,
  (CURRENT_DATE + COALESCE(
    (SELECT valor::INTEGER FROM configuracion_general 
     WHERE clave = 'horizonte_disponibilidad_dias'),
    120
  ))::DATE,
  NULL
);

-- vista_calendario con horizonte configurable
CREATE OR REPLACE VIEW vista_calendario AS
SELECT
  c.id_cabana, c.nombre AS cabana, r.id_reserva,
  r.fecha_checkin, r.fecha_checkout, r.hora_checkin, r.hora_checkout,
  r.personas, r.estado AS estado_reserva,
  h.nombre || ' ' || COALESCE(h.apellido, '') AS huesped_nombre,
  h.telefono AS huesped_telefono,
  r.monto_total, r.monto_saldo, r.encargado_semana
FROM reservas r
JOIN cabanas c ON c.id_cabana = r.id_cabana
JOIN huespedes h ON h.id_huesped = r.id_huesped
WHERE r.estado IN ('confirmada', 'activa')
  AND r.fecha_checkout >= CURRENT_DATE
  AND r.fecha_checkin <= (CURRENT_DATE + COALESCE(
    (SELECT valor::INTEGER FROM configuracion_general 
     WHERE clave = 'horizonte_disponibilidad_dias'),
    120
  ))::DATE
ORDER BY r.fecha_checkin, c.id_cabana;
\`\`\`

**Por qué `COALESCE` con default 120:** si la clave no existe por algún 
motivo, la vista sigue funcionando con un valor sensato en vez de fallar.

**Cambio futuro del valor:**
\`\`\`sql
UPDATE configuracion_general 
SET valor = '90'  -- o '150' o lo que decidan
WHERE clave = 'horizonte_disponibilidad_dias';
\`\`\`

**Origen:** decisión del Bloque 20, Fase 3, sesión XX/XX/2026.