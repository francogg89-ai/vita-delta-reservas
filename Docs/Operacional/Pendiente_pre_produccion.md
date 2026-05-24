# Pendientes Pre-Producción

Lista de cambios y configuraciones a aplicar antes del despliegue de
producción. Ítems destinados a producción que NO se hicieron en DEV para
mantener la trazabilidad de cómo evolucionó el sistema o que no se podían
hacer técnicamente en DEV.

---

## 1. Configuración de schema

### 1.1 Horizonte de disponibilidad — pasar de hardcoded a configurable

**Estado actual (DEV):** `vista_disponibilidad` y `vista_calendario` tienen
el horizonte hardcoded a 60 días forward.

**Cambio para producción:**

Paso 1 — Agregar clave a `configuracion_general` (junto con el seed productivo):
- clave: `horizonte_disponibilidad_dias`
- valor: `120` (sugerido)
- tipo_valor: `integer`
- descripcion: `Horizonte forward en días para vista_disponibilidad y vista_calendario`

Paso 2 — Modificar las 2 vistas para leer desde config:

```sql
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
```

**Por qué `COALESCE` con default 120:** si la clave no existe por algún motivo,
la vista sigue funcionando con un valor sensato en vez de fallar.

**Cambio futuro del valor sin redeploy:**

```sql
UPDATE configuracion_general
SET valor = '90'  -- o '150' o lo que decidan
WHERE clave = 'horizonte_disponibilidad_dias';
```

**Origen:** decisión del Bloque 20, Fase 3.

---

## 2. Programación de jobs automáticos

### 2.1 Schedule pg_cron — expirar_prereservas_vencidas

**Estado actual (DEV):** la función `expirar_prereservas_vencidas()` está
creada y probada (Bloque 18), pero NO está programada en pg_cron.

**Razón:** pg_cron requiere ser superuser en Supabase, restricción de DEV.

**Cambio para producción:**

```sql
SELECT cron.schedule(
  'expirar-prereservas',
  '*/5 * * * *',  -- cada 5 minutos
  'SELECT expirar_prereservas_vencidas()'
);
```

**Verificación post-schedule:**

```sql
SELECT * FROM cron.job WHERE jobname = 'expirar-prereservas';
```

**Cambio futuro de frecuencia (si fuera necesario):**

```sql
SELECT cron.unschedule('expirar-prereservas');
SELECT cron.schedule('expirar-prereservas', '*/10 * * * *',
                     'SELECT expirar_prereservas_vencidas()');
```

**Origen:** decisión del Bloque 18, Fase 2. A ejecutar en Bloque 22 (Fase 3)
si el ambiente lo permite, o quedar como tarea de despliegue final.

---

## 3. Notificaciones operativas (n8n)

### 3.1 Notificación a Jennifer cuando pre-reserva se convierte a reserva dentro del horizonte de limpieza

**Contexto:** `vista_limpieza_semana` muestra check-ins y check-outs de los
próximos 7 días. `vista_calendario_semanal` muestra estado día por día.
Ambas SOLO consideran reservas confirmadas y bloqueos (decisión de diseño:
no incluir pre-reservas que son "posibilidades", no certezas).

**Problema operativo:** si Jennifer mira la vista el lunes y planifica la
semana, una pre-reserva que se confirme el miércoles para el viernes
NO aparecerá en lo que ya consultó.

**Mitigación propuesta vía n8n:**

Workflow disparado cuando se crea una reserva (vía evento de
`confirmar_reserva`):

```
SI fecha_checkin de la nueva reserva está dentro de los próximos 7 días
ENTONCES enviar notificación a Jennifer (WhatsApp/Email) con:
  - Cabaña, fecha, hora checkin
  - Datos del huésped (nombre, teléfono, personas, mascotas)
  - Tipo: "Reserva nueva confirmada dentro de tu semana"
```

**Origen:** discusión del Bloque 20, Fase 3 (decisión de diseño confirmada
por Franco — Jennifer necesita updates cuando la semana cambia).

---

## 4. Configuración futura del seed productivo

### 4.1 Cabañas reales

**Estado actual (DEV):** se usaron cabañas test (B11, B12, etc.) que se
crean y borran en cada test.

**Para producción (Bloque 21):**

Cargar las 5 cabañas reales de Vita Delta:
- Bamboo (grande, capacidad 3-5)
- Madre Selva (grande, capacidad 3-5)
- Arrebol (grande, capacidad 3-5)
- Guatemala (chica, capacidad 2-4)
- Tokio (chica, capacidad 2-4)

### 4.2 Tarifas reales por temporada

Pendiente acordar con Franco y socios:
- Tarifas base por tipo (grande / chica)
- Tarifas por temporada (alta / media / baja)
- Tarifas por evento especial (años nuevo, semana santa, etc.)

### 4.3 Configuración productiva en `configuracion_general`

Valores sugeridos para producción (ajustar según decisión operativa):
- `hora_checkin_default`: 13:00
- `hora_checkin_domingo`: 18:00
- `hora_checkin_max_cliente`: 22:00
- `hora_checkout_min_cliente`: 07:00
- `hora_checkout_default`: 10:00
- `prereserva_expiracion_minutos`: 60 (revisable según patrones reales)
- `horizonte_disponibilidad_dias`: 120 (ver punto 1.1)

---

## 5. Seguridad

### 5.1 Row Level Security (RLS)

**Estado actual (DEV):** todas las tablas creadas con "Run without RLS".
Razón: n8n usa `service_role_key` que bypassea RLS de todas formas.

**Cambio para producción:**

Cuando se sume frontend público (web pública con login de huéspedes), se
deberán definir policies RLS sobre:

- `huespedes`: usuarios solo ven su propio registro.
- `pre_reservas`: usuarios solo ven las suyas.
- `reservas`: usuarios solo ven las suyas + staff ve todas.
- `pagos`: usuarios solo ven los suyos + staff ve todos.

**Decisión registrada en bitácora:** "RLS implementación pospuesta hasta
que haya frontend público. n8n con service_role_key no la necesita."

---

## 6. Validaciones empíricas pendientes (Fase 4)

### 6.1 Tests de concurrencia

Validar comportamiento del sistema bajo carga real:
- 2 clientes intentando reservar la misma cabaña simultáneamente.
- Webhook MP llegando mientras Vicky confirma manualmente.
- Cron de expiración corriendo mientras hay pago en proceso.

**Origen:** plan de Fase 4 según `6B_PLAN_FASES.md`.

---

## Cómo usar este archivo

- **Cuando se identifica un nuevo pendiente:** agregar acá con título,
  estado actual, cambio para producción, y origen.
- **Cuando se completa un pendiente:** mover a un archivo
  `Pendientes_Completados.md` con fecha de implementación.
- **En la revisión pre-deploy:** verificar que TODOS los items se hayan
  resuelto o tengan decisión explícita de postergación.