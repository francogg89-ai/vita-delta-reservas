# Pendientes Pre-Producción

Lista de cambios y configuraciones a aplicar antes del despliegue de
producción. Incluye pendientes que no se hicieron en DEV, ajustes ya cerrados en DEV que deben replicarse en TEST/PROD, y decisiones postergadas explícitamente.

**Estado del archivo:** actualizado al cierre de H6-bis (sesión 2026-05-26).
Items cerrados durante Etapa 6D listados en el resumen de abajo; detalle
histórico de cada uno en el Apéndice al final del documento.

---

## Items cerrados en Etapa 6D — resumen

| Item | Estado | Bloque que lo cerró | Apéndice |
|---|---|---|---|
| Hardening de validación SQL en funciones write | ✅ Cerrado | H2, H3, H4, H4-bis, H4-ter | A.1 |
| Fix `vista_ocupacion` (rango 25 → 24 meses) | ✅ Cerrado | H5 | A.2 |
| Espacio colgando en concatenación nombre + apellido | ✅ Cerrado | H6, H6-bis | A.3 |

**Items pendientes activos:** ver secciones 1 a 8 abajo.

**Bitácora del hardening:** `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` (H1-H6-bis documentados; H7-H8 pendientes).

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
-- Nota: el TRIM en huesped_nombre ya fue aplicado en H6 (Etapa 6D).
CREATE OR REPLACE VIEW vista_calendario AS
SELECT
  c.id_cabana, c.nombre AS cabana, r.id_reserva,
  r.fecha_checkin, r.fecha_checkout, r.hora_checkin, r.hora_checkout,
  r.personas, r.estado AS estado_reserva,
  TRIM(h.nombre || ' ' || COALESCE(h.apellido, '')) AS huesped_nombre,
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

**Estado actual (DEV):** ✅ Cerrado / activo. El job `expirar_prereservas`
está programado en pg_cron con schedule `*/5 * * * *` y validado end-to-end
(verificado 2026-05-27: 12 ejecuciones consecutivas con status `succeeded`
en una hora, una pre-reserva real procesada durante 6C).

**Pendiente pre-producción:** replicar y verificar el schedule cuando se
creen los ambientes TEST y PROD.

**Query a aplicar en TEST/PROD:**

```sql
SELECT cron.schedule(
  'expirar_prereservas',
  '*/5 * * * *',  -- cada 5 minutos
  'SELECT expirar_prereservas_vencidas()'
);
```

**Verificación post-schedule en TEST/PROD:**

```sql
SELECT * FROM cron.job WHERE jobname = 'expirar_prereservas';
```

**Cambio futuro de frecuencia (si fuera necesario):**

```sql
SELECT cron.unschedule('expirar_prereservas');
SELECT cron.schedule('expirar_prereservas', '*/10 * * * *',
                     'SELECT expirar_prereservas_vencidas()');
```

**Nota adicional:** en DEV también está activo el job `cleanup_cron_history`
(día 1 de cada mes a las 03:00 UTC) para purgar registros viejos de
`cron.job_run_details`. Replicar también en TEST/PROD.

**Origen:** decisión del Bloque 18, Fase 2. Ejecutado en Bloque 22 (Fase 3).

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
SI fecha_checkin de la nueva reserva está dentro de los próximos 7 días
ENTONCES enviar notificación a Jennifer (WhatsApp/Email) con:

Cabaña, fecha, hora checkin
Datos del huésped (nombre, teléfono, personas, mascotas)
Tipo: "Reserva nueva confirmada dentro de tu semana"


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

**Estado actual (DEV):** ✅ Parcialmente cerrado. Las 5 cabañas reales de
Vita Delta están cargadas en DEV con IDs 17-21:
- Bamboo (id=17, grande, capacidad 3-5)
- Madre Selva (id=18, grande, capacidad 3-5)
- Arrebol (id=19, grande, capacidad 3-5)
- Guatemala (id=20, chica, capacidad 2-4)
- Tokio (id=21, chica, capacidad 2-4)

**Pendiente pre-producción:** replicar el mismo seed en TEST y PROD cuando
se creen esos ambientes. Decidir si mantener los IDs actuales o re-crear
desde 1.
Si se decide conservar referencias o migrar datos desde DEV/TEST, no asumir IDs secuenciales desde 1. Preferir seeds explícitos o mapeos controlados.

### 4.2 Tarifas reales por temporada

Pendiente acordar con Franco y socios:
- Tarifas base por tipo (grande / chica)
- Tarifas por temporada (alta / media / baja)
- Tarifas por evento especial (años nuevo, semana santa, etc.)

**Estado actual:** DEV tiene solo una temporada baseline con multiplicador
neutro (no productiva).

### 4.3 Configuración productiva en `configuracion_general`

Valores sugeridos para producción (ajustar según decisión operativa):
- `hora_checkin_default`: 13:00
- `hora_checkin_domingo`: 18:00
- `hora_checkin_max_cliente`: 22:00
- `hora_checkout_min_cliente`: 07:00
- `hora_checkout_default`: 10:00
- `hora_checkout_domingo`: 16:00 (ver 4.4)
- `prereserva_expiracion_minutos`: 60 (revisable según patrones reales)
- `horizonte_disponibilidad_dias`: 120 (ver punto 1.1)

### 4.4 Agregar clave `hora_checkout_domingo` al seed productivo

**Estado actual (DEV):** ✅ Parcialmente cerrado. Clave cargada en DEV vía
hotfix v1.7 con valor `16:00`. Función `crear_prereserva` v1.7 ya la usa.

**Pendiente pre-producción:** agregar al seed productivo cuando se cree
PROD. Snippet:

```sql
INSERT INTO configuracion_general (clave, valor, descripcion, categoria) VALUES
  ('hora_checkout_domingo', '16:00',
   'Check-out cuando domingo es último día (vs default 10:00)', 'horarios');
```

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

## 6. Validaciones empíricas pendientes

### 6.1 Tests de concurrencia — H7 de Etapa 6D

**Estado:** ⏳ Pendiente. Bloque H7 de Etapa 6D (Hardening pre-producción).
Fuente: `6B_PLAN_FASES.md` Sección 6.8.
Ejecución prevista: sesión separada con setup explícito, dos pestañas SQL
Editor en paralelo, y plan de limpieza dirigida por `source_event`.

**Por qué se difirieron:**

1. Durante 6B (implementación de funciones), se priorizó "función compila y
   se comporta básicamente" para avanzar al siguiente bloque.
2. Durante 6C (workflows), los tests fueron funcionales end-to-end, no de
   concurrencia. n8n manual no permite reproducir la condición de carrera
   con `pg_sleep`.
3. Operativamente no es bloqueante hasta tener consumidores reales que
   generen concurrencia (webhook MP, bot multicanal, frontend público).

**Los 4 tests pendientes (según `6B_PLAN_FASES.md` Sección 6.8):**

1. **C-1**: `crear_prereserva` + `crear_bloqueo total` simultáneos sobre el
   mismo rango — validar que uno gana y el otro rebota con conflicto.
2. **C-2**: `cancelar_prereserva` + `crear_bloqueo total` simultáneos sobre
   rango con pre-reserva pre-existente — validar el orden correcto.
3. **C-3**: `confirmar_reserva` + `crear_bloqueo` simultáneos sobre el rango
   de la pre-reserva — validar que la pre-reserva se convierte primero y el
   bloqueo rebota con `conflicto_con_reserva`. **Test crítico** — está en
   criterios de freno por riesgo histórico de deadlock pre-v1.5.
4. **C-4**: Doble `confirmar_reserva` simultánea sobre la misma pre-reserva
   — validar que solo una invocación crea la reserva.

**Setup requerido:**

- Pre-reservas y/o bloqueos creados específicamente para los tests, con
  `source_event LIKE 'test_C%'`.
- Patrón con `pg_sleep(8)` en una pestaña y lanzamiento manual de la
  segunda pestaña a los ~2 segundos.
- Limpieza al cierre: `DELETE` dirigido por `source_event` para no dejar
  residuos en DEV.

**Riesgo de no ejecutar antes de TEST/PROD:**

Los locks (`pg_advisory_xact_lock(10, 0)` y `(1, id_cabana::INTEGER)`) están
implementados en todas las funciones críticas y el `EXCLUDE constraint`
actúa como red de seguridad estructural. **Lo más probable es que pasen sin
sorpresas.** Pero un test empírico es la única forma de confirmar que los
patrones de lock anidado funcionan bajo concurrencia real, no solo en
aislamiento. Sin estos tests, el primer evento de concurrencia real en
producción (ej. dos clientes que clickean "reservar" simultáneamente, o
webhook MP que dispara al mismo tiempo que confirmación manual) sería el
primer test de concurrencia del sistema. Es preferible que ocurra en DEV
controlado.

### 6.2 Tests de carga real (post-tests-de-concurrencia)

Pendiente histórico. Validar comportamiento del sistema bajo carga real:

- 2 clientes intentando reservar la misma cabaña simultáneamente.
- Webhook MP llegando mientras Vicky confirma manualmente.
- Cron de expiración corriendo mientras hay pago en proceso.

Estos no reemplazan H7. H7 valida concurrencia controlada con SQL y locks; 6.2 queda como validación posterior de carga/uso real cuando existan consumidores reales conectados.

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
```

---

## Cómo usar este archivo

- **Cuando se identifica un nuevo pendiente:** agregar acá con título,
  estado actual, cambio para producción, y origen.
- **Cuando se completa un pendiente:** marcar como cerrado y, si genera
  contexto histórico relevante, mover a `Apéndice histórico` al final.
- **En la revisión pre-deploy:** verificar que TODOS los items se hayan
  resuelto o tengan decisión explícita de postergación.

---

# Apéndice histórico — items cerrados en Etapa 6D

Esta sección preserva el contexto técnico de los items resueltos durante
Etapa 6D (Hardening pre-producción), sesión 2026-05-26. Las secciones que
siguen describen cómo fueron descubiertos los problemas y qué se decidió
en cada caso. **Para detalle de ejecución, ver `HARDENING_PRE_PRODUCCION_EJECUCION.md`.**

---

## A.1 [CERRADO en H2-H4-ter] Hardening de validación en funciones SQL write

**Descubierto durante:** 6C — implementación de W3 (registrar_pago).
**Fecha de descubrimiento:** 2026-05-25.
**Estado:** ✅ Cerrado en bloques H2, H3, H4, H4-bis, H4-ter de Etapa 6D
(sesión 2026-05-26).
**Bitácora detallada:** `Docs/Bitacora/6C_EJECUCION.md` — entrada W3,
sección "Hallazgo importante". Ejecución del fix en
`Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### Problema original (pre-hardening)

Las funciones de escritura del schema no eran uniformes en cómo manejaban
strings vacíos en campos obligatorios. Específicamente, `registrar_pago()`
extraía los campos obligatorios `tipo` y `medio_pago` así:

```sql
v_tipo := payload->>'tipo';
v_medio_pago := payload->>'medio_pago';
```

Sin `NULLIF` y sin `TRIM`. Si el payload traía estos campos como `""`
(string vacío), la validación posterior:

```sql
IF v_tipo IS NULL OR v_medio_pago IS NULL OR ... THEN
  RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
END IF;
```

No los detectaba como faltantes, porque `""` no es `NULL`. La función
avanzaba hasta el INSERT y chocaba contra los CHECK constraints
(`chk_pagos_tipo`, `chk_pagos_medio`), generando un error crudo de Postgres
en vez de un JSONB estructurado.

### Mitigación temporal aplicada en 6C

En W3 — Build Payload, n8n normalizaba con `nv()` los campos obligatorios
antes de mandarlos al payload (convertía `""` a `null` explícito). Esto
hacía que `payload->>'campo'` devolviera NULL real y la validación de la
función rebotara limpio.

**Limitación de la mitigación:** solo cubría el camino de W3. Si otro
consumidor de la función (otro workflow, llamada directa SQL, bot, etc.)
mandaba payload con string vacío, el agujero seguía.

### Fix definitivo aplicado en Etapa 6D

Patrón canónico unificado aplicado al extract de payload de las 5
funciones write críticas:

```sql
v_campo := NULLIF(TRIM(payload->>'campo'), '')::TIPO;
```

Cubre vacíos y whitespace antes del cast. Aplicado a 56 asignaciones
totales en las funciones:
- `registrar_pago` (H2)
- `confirmar_reserva` (H3)
- `crear_prereserva` (H4)
- `cancelar_prereserva` (H4-bis)
- `crear_bloqueo` (H4-ter)

`upsert_huesped` ya cumplía el patrón desde antes.

**101 tests de hardening** sobre las 5 funciones, todos con `ok=true`. Cero
side effects: conteos de DEV idénticos pre y post hardening.

**Mitigación defensiva `nv()` en n8n:** se mantiene como defensa en
profundidad. No se removió.

---

## A.2 [CERRADO en H5] Vista_ocupacion devuelve 25 meses en vez de 24

**Descubierto durante:** 6C — implementación de W7 (vistas operativas),
Test 4.
**Fecha de descubrimiento:** 2026-05-26.
**Estado:** ✅ Cerrado en bloque H5 de Etapa 6D (sesión 2026-05-26).
**Bitácora detallada:** `Docs/Bitacora/6C_EJECUCION.md` — entrada W7,
sección "Test 4". Ejecución del fix en
`Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### Problema original (pre-hardening)

`vista_ocupacion` estaba definida con:

```sql
generate_series(
  date_trunc('month', CURRENT_DATE) - '1 year'::interval,
  date_trunc('month', CURRENT_DATE) + '1 year'::interval,
  '1 mon'
)
```

`generate_series` con paso temporal incluye ambos extremos, generando 25
puntos en vez de 24. Esto resultaba en 25 meses × 5 cabañas = 125 filas en
el output, en vez del valor teóricamente esperado de 120.

**Impacto:**
- Funcional: ninguno. Los cálculos de `noches_ocupadas` para cada mes
  seguían siendo correctos.
- Operativo: una fila más por cabaña por consulta. En reportes que
  consumían la vista, podía causar confusión si alguien esperaba
  "exactamente 24 meses" para gráficos.

### Fix aplicado en Etapa 6D

Una sola línea modificada — al límite superior del `generate_series` se le
resta `'1 mon'::interval`:

```sql
generate_series(
  date_trunc('month', CURRENT_DATE) - '1 year'::interval,
  date_trunc('month', CURRENT_DATE) + '1 year'::interval - '1 mon'::interval,
  '1 mon'
)
```

Resultado: 120 filas (24 meses × 5 cabañas). 7 tests con `ok=true`.
Cálculos de `noches_ocupadas` idénticos a los previos.

---

## A.3 [CERRADO en H6, H6-bis] Espacio colgando en concatenación nombre + apellido

**Descubierto durante:** 6C — implementación de W7 (vistas operativas),
Test 3.
**Fecha de descubrimiento:** 2026-05-26.
**Estado:** ✅ Cerrado en bloques H6 y H6-bis de Etapa 6D (sesión 2026-05-26).
**Bitácora detallada:** `Docs/Bitacora/6C_EJECUCION.md` — entrada W7,
sección "Test 3". Ejecución del fix en
`Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### Problema original (pre-hardening)

Las vistas `vista_calendario`, `vista_limpieza_semana` y
`vista_prereservas_activas` concatenaban el nombre del huésped así:

```sql
nombre || ' ' || COALESCE(apellido, '')
```

Cuando `apellido` era string vacío `""` (no NULL), `COALESCE(apellido, '')`
devolvía `""` sin reemplazar. La concatenación quedaba como
`"Juan Pérez Test "` con espacio al final.

**Impacto:**
- Funcional: ninguno.
- UX/Cosmético: strings con espacios colgando se veían mal en UI / mensajes
  a clientes. Si una plantilla hacía `"Hola {huesped_nombre},"` quedaba
  `"Hola Juan Pérez Test ,"` con espacio antes de la coma.

### Fix aplicado en Etapa 6D

Reemplazo en las 3 vistas afectadas:

```sql
TRIM(nombre || ' ' || COALESCE(apellido, ''))
```

Aplicado a `vista_calendario`, `vista_limpieza_semana` (2 ocurrencias por
UNION ALL), y `vista_prereservas_activas` (1 ocurrencia).

PostgreSQL al persistir normalizó `TRIM(...)` a `TRIM(BOTH FROM ...)`.
Sintaxis equivalente.

H6: 7 tests con `ok=true`. H6-bis: 5 tests con `ok=true`. Categoría
cosmética cerrada.

**Parte 6.2 (UPDATE de huéspedes):** NO ejecutado. DEV ya tiene
`apellido = NULL` en los 2 huéspedes existentes (limpieza pre-hardening
eliminó los problemáticos). `upsert_huesped` aplica `NULLIF(TRIM(...))` para
casos futuros.

---

## A.4 [MIGRADO a Sección 6.1] Tests de concurrencia Sección 6.8

**Descubierto durante:** preparación del cierre formal post-6C.
**Fecha de registro:** 2026-05-26.
**Estado:** ⏳ Pendiente. Migrado y consolidado en **Sección 6.1** de este
documento. Asignado al bloque H7 de Etapa 6D.

Este item NO está cerrado. Se mueve al apéndice porque originalmente
ocupaba la Sección 10 del archivo y se consolidó con la Sección 6.1 para
evitar duplicación. El contenido actual está en Sección 6.1.

**Plan de ejecución:** sesión separada con foco completo en concurrencia
y limpieza. Decisión tomada al cierre de la sesión 2026-05-26 (H6-bis).