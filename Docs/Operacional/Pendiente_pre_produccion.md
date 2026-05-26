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

### 3.2 Endpoint obligatorio antes de web pública — `consultar_disponibilidad_precio`

**Estado actual:** no implementado en DEV.

**Motivo:** antes de exponer una web pública, el cliente debe poder elegir cabaña, fechas y cantidad de personas, y recibir disponibilidad + precio sin crear una pre-reserva todavía.

**Cambio antes de producción web:**

Crear un endpoint backend —inicialmente en n8n o Supabase Edge Function— que:

- recibe `id_cabana`, `fecha_in`, `fecha_out`, `personas`;
- valida disponibilidad;
- calcula `monto_total` y `monto_sena`;
- devuelve desglose de precio;
- NO crea pre-reserva;
- NO permite que el frontend sea fuente de verdad del precio.

**Regla:** la web puede mostrar el precio, pero nunca calcularlo como autoridad final.

**Origen:** decisión D40 del schema 6B.

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

### 4.4 Agregar clave `hora_checkout_domingo` al seed productivo

**Estado actual:** clave cargada en DEV vía hotfix v1.7. Falta agregarla
al seed productivo (Bloque 21).

**Cuando se despliegue producción, agregar al seed:**

\`\`\`sql
INSERT INTO configuracion_general (clave, valor, descripcion, categoria) VALUES
  ('hora_checkout_domingo', '16:00', 
   'Check-out cuando domingo es último día (vs default 10:00)', 'horarios');
\`\`\`

**Razón operativa:** los clientes que se van un domingo se quedan hasta las
16:00 (última lancha colectiva). Sin esta clave, `crear_prereserva` usaría el
default hardcoded 16:00 (vía COALESCE) y funcionaría igual, pero queda registro
explícito en `configuracion_general`.

**Función dependiente:** `crear_prereserva` v1.7 lee esta clave en sección 2.
Si la clave no existe, se genera un warning en `log_cambios` pero la función
no falla.

**Origen:** Hotfix v1.7 (Fase 3, post-cierre).

### 4.5 Completar seed productivo no técnico

Antes de producción, completar y verificar datos reales de:

- `socios`: nombres reales y porcentajes definitivos.
- `cuentas_cobro`: alias, medio, titular, detalle y estado activo/inactivo.
- `temporadas`: alta, media, baja, fechas y multiplicadores.
- `feriados`: feriados nacionales/provinciales/locales relevantes.
- `eventos_especiales`: Año Nuevo, Semana Santa u otros eventos con reglas propias.
- `plantillas_mensajes`: textos reales para huéspedes/equipo.

**Regla:** no subir datos sensibles reales a GitHub. El documento puede decir qué cargar, pero no debe contener CBU, alias reales sensibles, wallets, teléfonos privados ni credenciales.

**Origen:** preparación de seed productivo posterior a Fase 3.

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

## 7. Backup y rollback

### 7.1 Backup antes de aplicar schema en producción

Antes de ejecutar cualquier bloque o migración en PROD:

- exportar backup desde Supabase;
- guardar dump SQL o snapshot disponible;
- verificar que se puede restaurar o recrear el entorno;
- registrar commit exacto del repo usado para deploy.

### 7.2 Plan de rollback

Para cada ejecución productiva:

- definir hasta qué punto se puede revertir;
- no usar `DROP ... CASCADE` sin revisión explícita;
- documentar qué datos podrían perderse;
- si ya hay reservas reales cargadas, priorizar migraciones reversibles o scripts correctivos.

**Origen:** control mínimo de riesgo antes de producción.

---

## 8. Secrets y credenciales

### 8.1 Variables de entorno productivas

Antes de producción, verificar que las credenciales reales estén fuera de GitHub:

- Supabase Project URL.
- Supabase anon key, si aplica.
- Supabase service role key para n8n.
- Credenciales n8n.
- MercadoPago access token / webhook secret.
- WhatsApp / Meta tokens.
- Credenciales de email, si aplica.

**Regla:** ningún secret real debe commitearse. Usar `.env`, gestor de secretos o variables del entorno de n8n.

### 8.2 Archivo `.env.example`

Mantener solo placeholders:

```text
SUPABASE_URL=__SUPABASE_URL__
SUPABASE_SERVICE_ROLE_KEY=__SUPABASE_SERVICE_ROLE_KEY__
MERCADOPAGO_ACCESS_TOKEN=__MERCADOPAGO_ACCESS_TOKEN__

---

## Cómo usar este archivo

- **Cuando se identifica un nuevo pendiente:** agregar acá con título,
  estado actual, cambio para producción, y origen.
- **Cuando se completa un pendiente:** mover a un archivo
  `Pendientes_Completados.md` con fecha de implementación.
- **En la revisión pre-deploy:** verificar que TODOS los items se hayan
  resuelto o tengan decisión explícita de postergación.

  ## Hardening de validación en funciones SQL write

**Descubierto durante:** 6C — implementación de W3 (registrar_pago).
**Fecha:** 2026-05-25.
**Prioridad:** alta antes de TEST/PROD.
**Bitácora detallada:** `Docs/Bitacora/6C_EJECUCION.md` — entrada W3, sección "Hallazgo importante".

### Problema

Las funciones de escritura del schema no son uniformes en cómo manejan strings vacíos en campos obligatorios. Específicamente, `registrar_pago()` extrae los campos obligatorios `tipo` y `medio_pago` así:

```sql
v_tipo := payload->>'tipo';
v_medio_pago := payload->>'medio_pago';
```

Sin `NULLIF` y sin `TRIM`. Si el payload trae estos campos como `""` (string vacío), la validación posterior:

```sql
IF v_tipo IS NULL OR v_medio_pago IS NULL OR ... THEN
  RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
END IF;
```

No los detecta como faltantes, porque `""` no es `NULL`. La función avanza hasta el INSERT y choca contra los CHECK constraints (`chk_pagos_tipo`, `chk_pagos_medio`), generando un error crudo de Postgres en vez de un JSONB estructurado.

**Impacto:** un cliente que mande payload con campo obligatorio vacío recibe error 500 técnico en vez de `{ok: false, error: 'payload_invalido'}` controlado.

### Mitigación temporal aplicada (6C)

En W3 — Build Payload normaliza con `nv()` los campos obligatorios antes de mandar al payload (convierte `""` a `null` explícito). Esto hace que `payload->>'campo'` devuelve NULL real y la validación de la función rebota limpio.

**Limitación de la mitigación:** solo cubre el camino de W3. Si en el futuro otro consumidor de la función (otro workflow, llamada directa SQL, etc.) manda payload con string vacío, el agujero sigue.

### Fix estructural a aplicar antes de TEST/PROD

Auditar todas las funciones write del schema y asegurar que los campos obligatorios de texto se normalicen con `NULLIF(TRIM(payload->>'campo'), '')` en el extract inicial:

```sql
-- Patrón correcto
v_tipo := NULLIF(TRIM(payload->>'tipo'), '');
v_medio_pago := NULLIF(TRIM(payload->>'medio_pago'), '');
```

**Pattern de referencia:** `crear_prereserva()` v1.7 ya aplica este patrón al nombre del huésped:

```sql
IF v_huesped_payload IS NULL OR NULLIF(TRIM(v_huesped_payload->>'nombre'), '') IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'error', 'huesped_nombre_requerido', ...);
END IF;
```

### Funciones a auditar

Al menos las siguientes (lista completa pendiente al revisar el schema):

- [ ] `registrar_pago()` — confirmado: aplica al menos a `tipo` y `medio_pago`.
- [ ] `crear_prereserva()` — revisar campos obligatorios distintos a `huesped.nombre`.
- [ ] `confirmar_reserva()` — revisar al implementar W4.
- [ ] `cancelar_prereserva()` — revisar al implementar W5.
- [ ] `crear_bloqueo()` — revisar al implementar W6.
- [ ] `upsert_huesped()` — revisar campos obligatorios.

### Estrategia recomendada de implementación

Hacerlo como cierre formal post-6C, análogo al cierre de 6B v1.7.1:

1. Generar plan de cambio con snapshots de cada función previo a modificar.
2. Aplicar `CREATE OR REPLACE FUNCTION` con el patrón unificado.
3. Re-ejecutar los tests de cada workflow (W2-W6) para confirmar que el comportamiento de "happy path" no cambia.
4. Confirmar que los tests negativos ahora devuelven `{ok: false, error: 'payload_invalido'}` aun **sin** la mitigación de Build Payload en n8n.
5. Una vez confirmado, podemos **opcionalmente** retirar la mitigación defensiva de los workflows (los `nv()` en obligatorios). No es estrictamente necesario — pueden coexistir.

### Decisión a tomar antes del fix

¿La función debería rechazar también strings con solo whitespace (`"   "`)? El patrón con `TRIM` lo haría. **Recomendación: sí**, porque un campo con solo espacios no tiene valor semántico. Pero si algún caso de negocio real lo necesita, ajustar.

Generado como parte del cierre de W3 — 2026-05-25.

## 9. Vistas operativas — ajustes menores detectados en W7

Bloque 1 — vista_ocupacion devuelve 25 meses en vez de 24
Descubierto durante: 6C — implementación de W7 (vistas operativas), Test 4.
Fecha: 2026-05-26.
Prioridad: baja (micro-imprecisión, no rompe lógica).
Bitácora detallada: Docs/Bitacora/6C_EJECUCION.md — entrada W7, sección "Test 4 — vista_ocupacion".
Problema
vista_ocupacion está definida con:
sqlgenerate_series(
  date_trunc('month', CURRENT_DATE) - '1 year'::interval,
  date_trunc('month', CURRENT_DATE) + '1 year'::interval,
  '1 mon'
)
generate_series con paso temporal incluye ambos extremos, generando 25 puntos en vez de 24. Esto resulta en 25 meses × 5 cabañas = 125 filas en el output, en vez del valor teóricamente esperado de 120.
Ejemplo concreto al 2026-05-26:

date_trunc('month', hoy) = 2026-05-01.
Inicio del rango: 2025-05-01. Fin del rango: 2027-05-01.
Pasos: 2025-05, 2025-06, ..., 2026-04, 2026-05, 2026-06, ..., 2027-04, 2027-05.
Total: 25 puntos.

Impacto
Funcional: ninguno. Los cálculos de noches_ocupadas para cada mes siguen siendo correctos. El mes "extra" tiene noches_ocupadas: 0 mientras no haya reservas tan lejanas en el futuro.
Operativo: una fila más por cabaña por consulta. En reportes que consumen la vista, puede causar confusión si alguien espera "exactamente 24 meses" para gráficos.
Fix propuesto
Cambiar la cláusula del generate_series para que excluya el último mes:
sql-- Opción A: usar interval - 1 mes en el límite superior
generate_series(
  date_trunc('month', CURRENT_DATE) - '1 year'::interval,
  date_trunc('month', CURRENT_DATE) + '1 year'::interval - '1 mon'::interval,
  '1 mon'
)
O:
sql-- Opción B: usar < en un WHERE
SELECT * FROM generate_series(
  date_trunc('month', CURRENT_DATE) - '1 year'::interval,
  date_trunc('month', CURRENT_DATE) + '1 year'::interval,
  '1 mon'
) AS d(fecha)
WHERE d.fecha < date_trunc('month', CURRENT_DATE) + '1 year'::interval
Recomendación: Opción A, más simple y mantiene el espíritu del código original.
Estrategia recomendada
Aplicar como mini-fix junto con el hardening SQL ya documentado (NULLIF en funciones write). En la misma sesión post-6C de hardening pre-producción, revisar las vistas operativas y aplicar este fix.

Bloque 2 — Espacio colgando en concatenación de nombre + apellido
Descubierto durante: 6C — implementación de W7 (vistas operativas), Test 3.
Fecha: 2026-05-26.
Prioridad: muy baja (cosmético).
Bitácora detallada: Docs/Bitacora/6C_EJECUCION.md — entrada W7, sección "Test 3 — vista_calendario".
Problema
Las vistas vista_calendario y vista_limpieza_semana concatenan el nombre del huésped así:
sqlnombre || ' ' || COALESCE(apellido, '')
Cuando apellido es string vacío "" (no NULL), COALESCE(apellido, '') devuelve "" sin reemplazar. La concatenación queda como "Juan Pérez Test " || ' ' || "" = "Juan Pérez Test " con espacio al final.
Ejemplo real visto en Test 3 de W7: huesped_nombre: "Juan Pérez Test ".
Impacto
Funcional: ninguno.
UX/Cosmético: strings con espacios colgando se ven mal en UI / mensajes a clientes. Si una futura plantilla hace "Hola {huesped_nombre}," queda "Hola Juan Pérez Test ," con espacio antes de la coma.
Fix propuesto
Reemplazar la concatenación por una forma que normalice el resultado:
sql-- Opción A: trim al final
TRIM(nombre || ' ' || COALESCE(apellido, ''))

-- Opción B: solo agregar el espacio si hay apellido real
CASE
  WHEN NULLIF(TRIM(apellido), '') IS NULL THEN nombre
  ELSE nombre || ' ' || apellido
END
Recomendación: Opción A es más simple y funciona en ambos casos (apellido NULL o vacío).
Estrategia recomendada
Aplicar junto con el fix de vista_ocupacion (Bloque 1) en la sesión post-6C de hardening de vistas. Revisar también si hay otras concatenaciones similares en el schema.
Nota sobre la fuente del problema
El espacio colgando aparece porque las huéspedes en DEV se crearon con apellido: "" (string vacío) en lugar de apellido: NULL. La función crear_prereserva u upsert_huesped podría también normalizar este input con NULLIF(TRIM(apellido), '') antes de insertar. Esto se solapa con el item de hardening de validación SQL ya documentado.