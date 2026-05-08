# ARQUITECTURA_ETAPA_1_VITA_DELTA.md

**Versión:** 1.0  
**Fecha:** Mayo 2026  
**Estado:** Aprobado  
**Proyecto:** Sistema de gestión y automatización — Complejo Vita Delta  
**Autores:** Franco (titular) + Claude (arquitecto)

---

## ÍNDICE

1. Objetivo general del sistema
2. Principios rectores
3. Herramientas elegidas y rol de cada una
4. Decisiones técnicas aprobadas
5. Modelo de datos — tablas y campos
6. Relaciones entre tablas
7. Permisos por rol
8. Flujo general del sistema
9. Flujo CONSULTAS → PRE_RESERVAS → RESERVAS
10. Disponibilidad: arquitectura de DISPONIBILIDAD_CACHE
11. Arquitectura de BLOQUEOS
12. Principios de migrabilidad futura
13. Pendientes para Etapa 2

---

## 1. OBJETIVO GENERAL DEL SISTEMA

Construir un sistema de gestión integral para Complejo Vita Delta (complejo de cabañas en el Delta del Tigre, Argentina) que automatice al máximo las operaciones del negocio, con una única fuente de verdad centralizada.

### Alcance funcional completo (visión final)

- Reservas automáticas desde Instagram, WhatsApp y web propia
- Bot conversacional con IA para atención 24/7
- Motor de disponibilidad en tiempo real
- Motor de precios configurable por temporada, tipo de día y cantidad de personas
- Pagos automatizados (transferencia bancaria, MercadoPago, cripto)
- Calendario visual para el equipo interno
- Notificaciones automáticas a huéspedes y equipo
- Coordinación automática con personal de limpieza
- Contabilidad automatizada con distribución entre socios
- Post-estadía: recordatorios, reseñas, reenganche

### Contexto actual del negocio

- 5 cabañas activas: Bamboo, Madre Selva, Arrebol (grandes, hasta 5 personas), Guatemala y Tokio (chicas, hasta 4 personas)
- Sistema diseñado para escalar a 10+ cabañas sin rehacer la arquitectura
- Equipo: Franco y Rodrigo (socios encargados), Vicky (encargada de reservas), Jennifer (limpieza), tercer socio
- Canales actuales: Instagram (98% de consultas), WhatsApp, ocasionalmente Airbnb/Booking

---

## 2. PRINCIPIOS RECTORES

Estos principios guían todas las decisiones técnicas del sistema. Ante cualquier duda, volver a este listado.

1. **Una sola fuente de verdad.** Cada dato existe en un único lugar. No hay duplicación de información entre herramientas.

2. **Configuración sobre código.** Todo lo que puede cambiar sin intervención técnica (precios, horarios, textos, porcentajes) vive en tablas de configuración, no en código.

3. **Migrabilidad desde el día uno.** Toda tabla está diseñada como si fuera SQL. IDs únicos, relaciones explícitas, sin mezclar datos con presentación.

4. **n8n como cerebro lógico.** Toda la lógica de negocio, automatizaciones y decisiones viven en n8n. Apps Script solo hace puentes mínimos.

5. **Escrituras centralizadas.** Toda escritura a la base de datos pasa por n8n con cola de ejecución. Nunca escritura directa concurrente desde múltiples fuentes.

6. **Disponibilidad precalculada.** El bot y la web nunca calculan disponibilidad en tiempo real. Consultan una cache ya calculada.

7. **Escalabilidad sin rehacer.** Agregar una cabaña nueva es agregar una fila en la tabla CABAÑAS. Nada más.

8. **Auditoría completa.** Todo cambio importante queda registrado en LOG_CAMBIOS con timestamp y autor.

---

## 3. HERRAMIENTAS ELEGIDAS Y ROL DE CADA UNA

### Google Sheets
**Rol:** Base de datos central y panel operativo del equipo.  
**Qué hace:** Almacena todas las tablas del sistema. Es la fuente de verdad. También funciona como interfaz visual para Vicky y los socios — pueden ver y editar datos directamente sin interfaz técnica.  
**Qué NO hace:** Lógica de negocio, cálculos complejos, comunicación con APIs externas.  
**Límites conocidos:** 400 requests/100 segundos a la API. Riesgo de escritura concurrente si múltiples procesos escriben simultáneamente. Solución: todas las escrituras pasan por n8n con cola.

### n8n (instancia en n8n Cloud)
**Rol:** Motor de automatización y lógica central del sistema.  
**URL actual:** `https://federicosecchi.app.n8n.cloud`  
**Workflow activo:** `2BiRaMLKTcPOlkow` — Pipeline de Reservas (Etapa 0)  
**Qué hace:** Toda la lógica de negocio, automatizaciones, integraciones con APIs externas (WhatsApp, Instagram, MercadoPago), procesamiento de eventos, cálculo de precios, recálculo de disponibilidad, envío de mensajes.  
**Qué NO hace:** Almacenamiento de datos (eso es Sheets), interfaz de usuario.

### Apps Script
**Rol:** Puente mínimo entre Google Forms/Sheets y n8n.  
**Qué hace ÚNICAMENTE:**
- Trigger: cuando Vicky envía el Google Form de reserva → dispara webhook a n8n
- Endpoint HTTP liviano: la web consulta disponibilidad cacheada (lee DISPONIBILIDAD_CACHE, devuelve JSON)
- Protección de celdas en Sheets

**Qué NO hace:** Lógica de negocio, cálculos, decisiones de flujo, comunicación con APIs externas. Si una función en Apps Script tiene más de una condición o toca más de una tabla, esa lógica se mueve a n8n.

### Meta Business API (pendiente de configurar)
**Rol:** Canal de entrada y salida de mensajes de WhatsApp e Instagram.  
**Prerequisitos:** Página de Facebook del complejo + Meta Business Suite + app en Meta for Developers + número de WhatsApp Business dedicado.  
**Costo:** Gratis hasta 1.000 conversaciones/mes. ~USD 0.06/conversación después.

### MercadoPago API (pendiente de configurar)
**Rol:** Generación de links de pago y detección automática de pagos acreditados.  
**Costo:** Comisión por transacción con tarjeta. Transferencias entre cuentas: sin costo.  
**Prerequisito:** Cuenta MercadoPago vinculada al CUIT/monotributo del titular.

### Web de reservas
**Rol:** Canal de reserva directa para clientes.  
**Estado actual:** Prototipo funcional en `https://francogg89-ai.github.io/vita-delta-reservas/`  
**Stack:** HTML + CSS + JavaScript puro (un solo archivo `index.html`).  
**Repositorio:** `https://github.com/francogg89-ai/vita-delta-reservas`  
**Pendiente:** Conectar a disponibilidad real desde Sheets, integrar MercadoPago.

### Google Calendar
**Rol:** Vista visual de reservas para el equipo. Secundario a Sheets.  
**Sincronización:** n8n crea/modifica eventos cuando se confirma una reserva.

### Claude API (Anthropic)
**Rol:** Motor de IA para el bot conversacional.  
**Modelo:** Claude Sonnet (claude-sonnet-4-20250514)  
**Integración:** Llamadas desde n8n con prompt caching activado para reducir costos.  
**Costo estimado:** ~USD 2-9/mes según temporada con optimizaciones aplicadas.

---

## 4. DECISIONES TÉCNICAS APROBADAS

### Google Sheets vs Supabase/PostgreSQL
**Decisión:** Arrancar con Google Sheets. Diseñar como SQL desde el día uno. Migrar a Supabase cuando el volumen lo justifique.

**Justificación:**
- Sheets permite que el equipo operativo (Vicky, socios) vea y edite datos directamente sin interfaz técnica adicional
- El volumen proyectado de Vita Delta no alcanza los límites reales de Sheets en los próximos 2 años
- Diseñando con IDs y relaciones explícitas, la migración futura es copiar datos y reapuntar conexiones de n8n

**Punto de quiebre para migrar a Supabase:** Más de 50 reservas por mes procesadas automáticamente en simultáneo, o necesidad de reportes contables cruzados en tiempo real.

### n8n vs Apps Script como núcleo lógico
**Decisión:** n8n es el cerebro. Apps Script solo hace puentes y triggers mínimos.

**Justificación:**
- Apps Script no tiene control de versiones real, el debugger es primitivo, los logs desaparecen, límite de ejecución de 6 minutos
- n8n tiene ejecuciones históricas con logs completos, manejo de errores real, versionado, visibilidad total de cada paso

**Regla práctica:** Si una función tiene más de una condición o toca más de una tabla → va en n8n.

### Reglas operativas: configuración vs hardcoding
**Decisión:** Configuración para lo que cambia frecuentemente. Código documentado para lógica compleja estable.

**En CONFIGURACION_GENERAL (configurable sin código):**
- Horarios de checkin/checkout
- Umbral y minutos de escalonamiento
- Porcentaje de seña
- Fechas de temporada alta
- Tiempos de expiración de pre-reservas

**En código n8n (documentado):**
- Lógica de escalonamiento
- Cálculo de temporada
- Motor de conversión de tarifas

**NO se hace:** tabla de REGLAS_OPERATIVAS con condición/acción/prioridad. Es sobreingeniería para esta etapa y crea un mini-lenguaje que nadie puede mantener.

### Escritura concurrente
**Decisión:** Todas las escrituras críticas (crear reserva, modificar disponibilidad) pasan por un solo workflow de n8n con cola de ejecución. Nunca escritura directa concurrente desde bot, web o formularios simultáneamente.

**Patrón:** Cada tipo de escritura tiene un workflow "API interna" dedicado en n8n. Los demás workflows llaman a ese workflow, no escriben directamente a Sheets.

---

## 5. MODELO DE DATOS — TABLAS Y CAMPOS

### CABAÑAS
Tabla maestra. Una fila por cabaña.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_cabana | Integer | Sí | ID único autoincremental. Nunca cambia |
| nombre | String | Sí | "Bamboo", "Madre Selva", etc. |
| tipo | String | Sí | "grande" o "chica" |
| capacidad_base | Integer | Sí | Personas incluidas en precio base (3 para grandes, 2 para chicas) |
| capacidad_max | Integer | Sí | Máximo absoluto (5 para grandes, 4 para chicas) |
| activa | Boolean | Sí | False = cabaña eliminada del sistema |
| bloqueada | Boolean | Sí | True = existe pero no disponible temporalmente |
| motivo_bloqueo | String | No | "Mantenimiento", "Uso propio", etc. |
| orden_limpieza | Integer | Sí | Prioridad para Jennifer |
| descripcion | Text | No | Para bot y web |
| fotos_urls | Text | No | URLs separadas por coma |
| created_at | Timestamp | Sí | |

**Diferencia entre `activa` y `bloqueada`:**
- `activa = false`: la cabaña dejó de existir en el sistema. No aparece en ningún flujo.
- `bloqueada = true`: la cabaña existe y puede volver a estar disponible. Solo afecta disponibilidad temporalmente.

**Cabañas actuales:**

| id | nombre | tipo | cap_base | cap_max |
|---|---|---|---|---|
| 1 | Bamboo | grande | 3 | 5 |
| 2 | Madre Selva | grande | 3 | 5 |
| 3 | Arrebol | grande | 3 | 5 |
| 4 | Guatemala | chica | 2 | 4 |
| 5 | Tokio | chica | 2 | 4 |

---

### HUÉSPEDES
Base de datos de clientes. Separada de reservas para historial y reconocimiento.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_huesped | Integer | Sí | ID único autoincremental |
| nombre | String | Sí | |
| apellido | String | No | |
| dni | String | No | |
| telefono | String | Sí | Con código de país. Ej: +5491158297725 |
| email | String | No | |
| canal_preferido | String | No | "whatsapp", "instagram" |
| primera_reserva_fecha | Date | No | Calculado al confirmar primera reserva |
| total_reservas | Integer | No | Calculado automáticamente |
| notas_internas | Text | No | "Cliente VIP", "Siempre trae perro", etc. |
| created_at | Timestamp | Sí | |

---

### CONSULTAS
Conversaciones activas del bot. No bloquean disponibilidad.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_consulta | Integer | Sí | ID único |
| canal | String | Sí | "whatsapp", "instagram", "web" |
| id_contacto_externo | String | Sí | ID del usuario en la plataforma |
| id_huesped | Integer | No | FK → HUÉSPEDES (null si no identificado aún) |
| estado_conversacion | String | Sí | Ver estados abajo |
| id_cabana_tentativa | Integer | No | FK → CABAÑAS |
| fecha_in_tentativa | Date | No | |
| fecha_out_tentativa | Date | No | |
| personas_tentativa | Integer | No | |
| ultimo_mensaje_at | Timestamp | Sí | Para detectar conversaciones inactivas |
| contexto_json | JSON | No | Historial completo para el bot |
| created_at | Timestamp | Sí | |

**Estados de conversación:**
`inicio` → `eligiendo_fechas` → `eligiendo_cabana` → `cotizando` → `esperando_pago` → `cerrada` / `derivada_a_humano`

---

### PRE_RESERVAS
Cliente eligió cabaña y fechas. Bloquea disponibilidad temporalmente.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_prereserva | Integer | Sí | ID único |
| id_consulta | Integer | No | FK → CONSULTAS |
| id_cabana | Integer | Sí | FK → CABAÑAS |
| id_huesped | Integer | Sí | FK → HUÉSPEDES |
| fecha_in | Date | Sí | |
| fecha_out | Date | Sí | |
| hora_checkin | Time | Sí | Calculada con reglas de escalonamiento |
| hora_checkout | Time | Sí | |
| personas | Integer | Sí | |
| monto_total | Number | Sí | Calculado al crear |
| monto_sena | Number | Sí | 50% del total por defecto |
| estado | String | Sí | "pendiente_pago", "vencida", "convertida" |
| expira_en | Timestamp | Sí | Cuándo se libera si no paga. Default: 60 min |
| canal_origen | String | Sí | "whatsapp", "instagram", "web" |
| created_at | Timestamp | Sí | |

---

### RESERVAS
Reservas confirmadas. Solo llega acá cuando el pago está validado.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_reserva | Integer | Sí | ID único autoincremental |
| id_prereserva | Integer | No | FK → PRE_RESERVAS (trazabilidad) |
| id_cabana | Integer | Sí | FK → CABAÑAS |
| id_huesped | Integer | Sí | FK → HUÉSPEDES |
| fecha_checkin | Date | Sí | |
| fecha_checkout | Date | Sí | |
| hora_checkin | Time | Sí | |
| hora_checkout | Time | Sí | |
| personas | Integer | Sí | |
| estado | String | Sí | Ver tabla ESTADOS_RESERVA |
| canal_origen | String | Sí | "whatsapp", "instagram", "web", "airbnb", "booking" |
| id_tarifa_aplicada | Integer | Sí | FK → TARIFAS |
| monto_total | Number | Sí | |
| mascotas | Boolean | No | |
| detalle_mascotas | String | No | |
| ninos | Boolean | No | |
| notas | Text | No | |
| encargado_semana | String | Sí | "Franco" o "Rodrigo" |
| created_at | Timestamp | Sí | |
| created_by | String | Sí | "bot", "vicky", "web", "franco" |

---

### ESTADOS_RESERVA
Tabla de referencia para estados válidos.

| estado | descripcion | bloquea_disponibilidad | notifica_equipo |
|---|---|---|---|
| pre_reserva | Pendiente de pago | Sí | Sí |
| confirmada | Seña cobrada | Sí | Sí |
| activa | Huésped en el complejo | Sí | No |
| completada | Checkout realizado | No | Sí |
| cancelada | Sin penalidad | No | Sí |
| cancelada_con_cargo | Con retención | No | Sí |
| bloqueada_manual | Sin reserva real | Sí | No |

---

### TARIFAS
Motor de precios. Toda modificación de precios se hace aquí.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_tarifa | Integer | Sí | ID único |
| nombre | String | Sí | "Temporada alta finde 2 noches grandes" |
| tipo_cabana | String | Sí | "grande", "chica", "todas" |
| tipo_dia | String | Sí | "semana", "finde", "feriado", "ano_nuevo" |
| temporada | String | Sí | "alta", "media", "baja" |
| noches_min | Integer | Sí | Mínimo de noches para esta tarifa |
| noches_max | Integer | Sí | Máximo (-1 = sin límite) |
| precio_total | Number | Sí | Precio del bloque completo |
| precio_por_noche | Number | Sí | Calculado: precio_total / noches_min |
| extra_persona_noche | Number | Sí | Costo por persona sobre capacidad base |
| minimo_noches_obligatorio | Integer | No | Mínimo que el sistema no permite bajar |
| activa | Boolean | Sí | Para desactivar sin borrar |
| valida_desde | Date | No | Null = siempre |
| valida_hasta | Date | No | Null = siempre |
| created_at | Timestamp | Sí | |

---

### PAGOS
Cada transacción es un registro independiente.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_pago | Integer | Sí | ID único |
| id_reserva | Integer | Sí | FK → RESERVAS |
| tipo | String | Sí | "sena", "saldo", "extra", "reembolso" |
| monto | Number | Sí | |
| moneda | String | Sí | "ARS", "USD", "USDT" |
| medio | String | Sí | "transferencia", "mp_link", "efectivo", "cripto" |
| estado | String | Sí | "pendiente", "confirmado", "rechazado" |
| comprobante_url | String | No | Link a imagen del comprobante |
| fecha_pago | Date | No | Cuando se acreditó |
| confirmado_por | String | No | "vicky", "bot_mp", "franco" |
| notas | Text | No | |
| created_at | Timestamp | Sí | |

---

### DISPONIBILIDAD_CACHE
Tabla precalculada. El bot y la web solo consultan aquí. Nunca calculan en tiempo real.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_cabana | Integer | Sí | FK → CABAÑAS |
| fecha | Date | Sí | Un registro por día por cabaña |
| estado | String | Sí | "disponible", "ocupada", "bloqueada", "checkout_disponible" |
| hora_checkin_disponible | Time | No | Calculada con escalonamiento incluido |
| hora_checkout | Time | No | |
| precio_base_noche | Number | No | Tarifa aplicable ese día |
| tipo_dia | String | No | "semana", "finde", "feriado", "ano_nuevo" |
| temporada | String | No | "alta", "media", "baja" |
| minimo_noches | Integer | No | Mínimo desde este día |
| id_reserva_activa | Integer | No | FK → RESERVAS si está ocupada |
| id_prereserva_activa | Integer | No | FK → PRE_RESERVAS si está en proceso |
| recalculado_en | Timestamp | Sí | Para saber si la cache está vigente |

**Clave primaria compuesta:** (id_cabana, fecha)

**Cuándo se recalcula:**
- Al confirmar una reserva → recalcular fechas afectadas ± 2 días buffer
- Al cancelar una reserva → ídem
- Al crear/eliminar un bloqueo → fechas del bloqueo
- Al vencer una pre-reserva → fechas de la pre-reserva
- Al cambiar configuración de temporada o feriados → recálculo masivo programado

**Recálculo parcial vs masivo:**
- Parcial: evento puntual (reserva, bloqueo). Solo fechas afectadas.
- Masivo: cambio de configuración general. Programado, no en tiempo real.

---

### BLOQUEOS
Bloqueos manuales de cabañas sin reserva real.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_bloqueo | Integer | Sí | ID único |
| id_cabana | Integer | No | FK → CABAÑAS. Null = todas las cabañas |
| fecha_desde | Date | Sí | |
| fecha_hasta | Date | Sí | |
| motivo | String | Sí | "mantenimiento", "uso_propio", "tormenta", "overbooking" |
| descripcion | Text | No | Detalle libre |
| creado_por | String | Sí | |
| activo | Boolean | Sí | Para desactivar sin borrar |
| created_at | Timestamp | Sí | |

**Nota:** `id_cabana = null` bloquea todas las cabañas simultáneamente (cierre total por tormenta, mantenimiento general, etc.)

**Precedencia en motor de disponibilidad:**
1. ¿Hay bloqueo activo? → No disponible
2. ¿Hay reserva confirmada o pre-reserva vigente? → No disponible
3. ¿Libre? → Disponible, calcular horarios y precio

---

### GASTOS
Contabilidad de egresos.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_gasto | Integer | Sí | ID único |
| fecha | Date | Sí | |
| categoria | String | Sí | "limpieza", "mantenimiento", "servicios", "marketing" |
| descripcion | String | Sí | |
| monto | Number | Sí | |
| id_cabana | Integer | No | Null si es gasto general del complejo |
| pagado_por | String | Sí | Socio que pagó |
| reembolsable | Boolean | Sí | Si se descuenta de utilidades |
| comprobante_url | String | No | |
| created_at | Timestamp | Sí | |

---

### FERIADOS
Cargados manualmente por el administrador.

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| fecha | Date | Sí | YYYY-MM-DD. Clave primaria |
| nombre | String | Sí | "Día del Trabajador" |
| tipo | String | Sí | "nacional", "ano_nuevo", "local" |
| activo | Boolean | Sí | Para desactivar sin borrar |

---

### CONFIGURACION_GENERAL
Pares clave-valor. Todo lo configurable sin tocar código.

| Clave | Valor actual | Descripción |
|---|---|---|
| hora_checkin_default | 13:00 | Hora estándar de entrada |
| hora_checkout_default | 10:00 | Hora estándar de salida |
| hora_checkin_domingo_temp_alta | 18:00 | Excepción domingo temporada alta |
| hora_checkout_domingo_temp_alta | 16:00 | Excepción domingo temporada alta |
| escalonamiento_umbral | 3 | Número de checkouts simultáneos que activa escalonamiento |
| escalonamiento_minutos | 45 | Minutos extra por cabaña sobre el umbral |
| sena_porcentaje | 50 | % de seña sobre el total |
| prereserva_expiracion_minutos | 60 | Tiempo hasta que vence una pre-reserva sin pago |
| temporada_alta_inicio | 12-01 | MM-DD inicio temporada alta |
| temporada_alta_fin | 02-28 | MM-DD fin temporada alta |
| encargado_ciclo_inicio_fecha | 2026-05-11 | Fecha inicio ciclo Franco/Rodrigo |
| encargado_ciclo_inicio_nombre | Franco | Quién arranca el ciclo |
| whatsapp_franco | +5491158297725 | |
| whatsapp_rodrigo | +5491135659035 | |
| whatsapp_jennifer | +5491151789772 | |
| max_cabanas_sistema | 10 | Límite configurable (no hardcodeado) |

---

### MENSAJES_AUTOMATICOS
Textos editables sin tocar código.

| Campo | Tipo | Descripción |
|---|---|---|
| id_mensaje | Integer | ID único |
| nombre | String | Identificador interno |
| canal | String | "whatsapp", "instagram", "email" |
| evento_disparador | String | "reserva_confirmada", "recordatorio_checkin", etc. |
| texto | Text | Con variables tipo {nombre}, {fecha_checkin}, etc. |
| activo | Boolean | |

---

### SOCIOS
Distribución de utilidades y encargados de semana.

| Campo | Tipo | Descripción |
|---|---|---|
| id_socio | Integer | ID único |
| nombre | String | |
| porcentaje_utilidades | Number | % de distribución |
| whatsapp | String | |
| activo | Boolean | |

---

### LOG_CAMBIOS
Auditoría de modificaciones importantes.

| Campo | Tipo | Descripción |
|---|---|---|
| id_log | Integer | ID único autoincremental |
| fecha_hora | Timestamp | |
| tabla_afectada | String | "RESERVAS", "TARIFAS", etc. |
| id_registro | Integer | ID del registro modificado |
| campo_modificado | String | |
| valor_anterior | String | |
| valor_nuevo | String | |
| modificado_por | String | Usuario o proceso |

---

## 6. RELACIONES ENTRE TABLAS

```
CABAÑAS (1) ──────────────── (N) RESERVAS
CABAÑAS (1) ──────────────── (N) DISPONIBILIDAD_CACHE
CABAÑAS (1) ──────────────── (N) BLOQUEOS
CABAÑAS (1) ──────────────── (N) PRE_RESERVAS
CABAÑAS (1) ──────────────── (N) GASTOS

HUÉSPEDES (1) ─────────────── (N) RESERVAS
HUÉSPEDES (1) ─────────────── (N) PRE_RESERVAS
HUÉSPEDES (1) ─────────────── (N) CONSULTAS

CONSULTAS (1) ─────────────── (1) PRE_RESERVAS
PRE_RESERVAS (1) ──────────── (1) RESERVAS

RESERVAS (1) ──────────────── (N) PAGOS
TARIFAS (1) ───────────────── (N) RESERVAS
```

---

## 7. PERMISOS POR ROL

| Tabla | Admin (Franco/socios) | Encargado (Vicky) | Bot / n8n | Web pública |
|---|---|---|---|---|
| CABAÑAS | R + W | R | R | R |
| HUÉSPEDES | R + W | R + W | R + W | Crear |
| CONSULTAS | R + W | R | R + W | No |
| PRE_RESERVAS | R + W | R + W | R + W | Crear |
| RESERVAS | R + W | R + W | R + W | Crear |
| ESTADOS_RESERVA | R + W | R | R | No |
| TARIFAS | R + W | R | R | R |
| PAGOS | R + W | R + W | Crear | No |
| DISPONIBILIDAD_CACHE | R + W | R | R + W | R |
| BLOQUEOS | R + W | No | R | No |
| GASTOS | R + W | No | No | No |
| FERIADOS | R + W | No | R | No |
| CONFIGURACION_GENERAL | R + W | No | R | No |
| MENSAJES_AUTOMATICOS | R + W | R | R | No |
| SOCIOS | R + W | No | No | No |
| LOG_CAMBIOS | R | No | W | No |

**R** = Leer | **W** = Escribir | **R + W** = Leer y escribir

---

## 8. FLUJO GENERAL DEL SISTEMA

```
┌─────────────────────────────────────────────────────────┐
│                    CANALES DE ENTRADA                    │
│         Instagram DM │ WhatsApp │ Web de reservas        │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│                       n8n                               │
│                                                         │
│  1. Recibe mensaje / evento                             │
│  2. Identifica o crea HUÉSPED                           │
│  3. Crea o actualiza CONSULTA                           │
│  4. Bot (Claude API) responde                           │
│  5. Cliente elige fechas y cabaña                       │
│  6. Consulta DISPONIBILIDAD_CACHE                       │
│  7. Crea PRE_RESERVA (bloqueo temporal)                 │
│  8. Manda instrucciones de pago                         │
│  9. Detecta pago (MP webhook o comprobante)             │
│  10. Convierte PRE_RESERVA → RESERVA                    │
│  11. Recalcula DISPONIBILIDAD_CACHE                     │
│  12. Notifica equipo (grupo WhatsApp)                   │
│  13. Confirma al huésped                                │
│  14. Registra en LOG_CAMBIOS                            │
└─────────────────────────────────────────────────────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
    Google Sheets  Google Calendar  WhatsApp/Instagram
    (fuente verdad) (vista equipo)  (mensajes)
```

---

## 9. FLUJO CONSULTAS → PRE_RESERVAS → RESERVAS

### Fase 1 — CONSULTA
- Se crea cuando el cliente inicia conversación
- No bloquea disponibilidad
- El bot conversa libremente
- Se actualiza en cada mensaje con el estado de la conversación
- Expira si no hay actividad en 24 horas (configurable)
- Puede derivarse a humano en cualquier momento

### Fase 2 — PRE_RESERVA
- Se crea cuando el cliente confirma fechas y cabaña
- **Bloquea disponibilidad inmediatamente** en DISPONIBILIDAD_CACHE
- Tiene un tiempo de expiración (default: 60 minutos desde CONFIGURACION_GENERAL)
- Si vence sin pago: se elimina el bloqueo, se recalcula disponibilidad, n8n manda recordatorio al cliente
- Si el cliente vuelve: se puede crear una nueva pre-reserva si la disponibilidad sigue libre

### Fase 3 — RESERVA
- Solo se crea cuando el pago está confirmado
- El pago puede confirmarse por:
  - Webhook automático de MercadoPago
  - Vicky marca manualmente "comprobante validado" en el formulario
- Al confirmar: se actualiza DISPONIBILIDAD_CACHE, se notifica al equipo, se confirma al huésped
- La PRE_RESERVA queda con estado "convertida" para trazabilidad

### Diagrama de estados

```
CONSULTA ──────────────────────────────────────► CERRADA (sin interés)
    │                                                    │
    │ cliente elige fechas                               │ derivada
    ▼                                                    ▼
PRE_RESERVA ──────────► VENCIDA (sin pago en 60 min) ► DERIVADA_A_HUMANO
    │
    │ pago confirmado
    ▼
RESERVA_CONFIRMADA ──► ACTIVA (día de checkin) ──► COMPLETADA (checkout)
                                                    │
                                                    └──► CANCELADA
```

---

## 10. DISPONIBILIDAD_CACHE — ARQUITECTURA

### Principio
El bot y la web **nunca calculan disponibilidad en tiempo real**. Solo leen la tabla DISPONIBILIDAD_CACHE que ya tiene todo calculado.

### Contenido de cada fila
Una fila por cada combinación (cabaña, fecha). Para 5 cabañas y 365 días = 1.825 filas. Para 10 cabañas y 2 años = 7.300 filas. Completamente manejable en Sheets.

### Lógica de recálculo
Cuando n8n detecta un evento que afecta disponibilidad:
1. Identifica las fechas y cabañas afectadas
2. Para cada combinación (cabaña, fecha):
   - ¿Hay bloqueo activo? → estado = "bloqueada"
   - ¿Hay reserva confirmada? → estado = "ocupada"
   - ¿Hay pre-reserva vigente? → estado = "ocupada" (bloqueo temporal)
   - ¿Es el día de checkout de una reserva? → estado = "checkout_disponible"
   - ¿Libre? → estado = "disponible", calcular hora_checkin con escalonamiento
3. Actualiza solo las filas afectadas (recálculo parcial)
4. Actualiza `recalculado_en` timestamp

### Recálculo masivo
Programado una vez por noche en n8n. Recalcula todo el rango de fechas activas (hoy + 18 meses). Sirve como corrección de inconsistencias y para aplicar cambios de configuración.

### Consulta del bot
```
Consulta: ¿Está disponible Bamboo del 10 al 15 de junio?
→ n8n lee DISPONIBILIDAD_CACHE WHERE id_cabana=1 AND fecha BETWEEN '2026-06-10' AND '2026-06-15'
→ Si todas las filas tienen estado='disponible' → disponible
→ Devuelve hora_checkin, hora_checkout, precio_base_noche de cada fila
→ Tiempo de respuesta: < 300ms
```

---

## 11. ARQUITECTURA DE BLOQUEOS

### Cuándo usar BLOQUEOS
- Mantenimiento programado
- Uso propio de los socios
- Tormenta o fuerza mayor
- Overbooking manual (error que se corrige)
- Cierre total del complejo

### Cuándo NO usar BLOQUEOS
- Reservas reales → van en RESERVAS
- Cabañas inactivas permanentemente → campo `activa=false` en CABAÑAS

### Comportamiento de bloqueo total
Si `id_cabana = null`: todas las cabañas quedan bloqueadas en las fechas indicadas. n8n recalcula DISPONIBILIDAD_CACHE para todas las cabañas en ese rango.

### Flujo al crear un bloqueo
1. Admin crea registro en BLOQUEOS
2. Apps Script detecta el cambio → dispara webhook a n8n
3. n8n recalcula DISPONIBILIDAD_CACHE para fechas y cabañas afectadas
4. Si hay PRE_RESERVAS activas en esas fechas → n8n notifica al equipo para gestión manual
5. Registro en LOG_CAMBIOS

---

## 12. PRINCIPIOS DE MIGRABILIDAD FUTURA

### Reglas de diseño que garantizan migrabilidad

1. **IDs numéricos únicos en cada tabla.** Nunca usar nombre como identificador.
2. **Relaciones explícitas.** Toda FK nombrada como `id_[tabla]`.
3. **Nombres de campos en snake_case.** Compatible con SQL desde el día uno.
4. **Sin lógica en Sheets.** Ninguna fórmula de Sheets que calcule datos de negocio. Solo fórmulas de presentación.
5. **Sin referencias cruzadas entre hojas de Sheets.** Cada hoja es autónoma. Las relaciones las gestiona n8n.
6. **Tipos de datos consistentes.** Fechas siempre YYYY-MM-DD, horas siempre HH:MM, booleanos siempre TRUE/FALSE.

### Patrón "API interna" en n8n
Cada tipo de escritura tiene un workflow dedicado:
- `db_escribir_reserva`
- `db_escribir_huesped`
- `db_recalcular_disponibilidad`

Los workflows de negocio llaman a estos workflows, nunca escriben directamente a Sheets. Cuando se migre a Supabase, solo se modifican estos workflows centrales.

### Plan de migración a Supabase (cuando sea necesario)
1. Crear schema en Supabase con las mismas tablas y campos
2. Exportar datos de Sheets a CSV
3. Importar CSV a Supabase
4. Actualizar los workflows "API interna" de n8n para apuntar a Supabase
5. Mantener Sheets como panel de reportes y vista operativa para el equipo
6. Tiempo estimado: 1-2 días de trabajo técnico

---

## 13. PENDIENTES PARA ETAPA 2

La Etapa 2 es el diseño completo del **Motor de Disponibilidad**. Incluye:

### A definir en Etapa 2

- [ ] Algoritmo completo de cálculo de escalonamiento (generalizado, no solo viernes/domingos)
- [ ] Reglas exactas de horarios por tipo de día y temporada
- [ ] Lógica de checkout_disponible: cuándo y cómo se puede usar como checkin
- [ ] Estructura completa del recálculo parcial en n8n
- [ ] Estructura del recálculo masivo nocturno
- [ ] Manejo de edge cases: reserva que cruza cambio de temporada, pre-reserva que vence con reserva encima, bloqueo sobre pre-reserva activa
- [ ] API de consulta de disponibilidad para la web (schema JSON de respuesta)
- [ ] Cómo el bot presenta disponibilidad al cliente (qué información muestra, cómo la estructura)

### Ya definido que impacta Etapa 2

- La condición de escalonamiento es: **más de 3 checkouts en el mismo horario** (no específico de viernes/domingos — aplica a cualquier día con esa condición)
- Horarios default: checkin 13:00 / checkout 10:00
- Excepción temporada alta domingos: checkin 18:00 / checkout 16:00
- Escalonamiento: 45 minutos por cabaña adicional sobre el umbral de 3

---

*Documento generado como parte del proceso de diseño del sistema Complejo Vita Delta.*  
*Para continuar: ver ARQUITECTURA_ETAPA_2_VITA_DELTA.md (pendiente)*
