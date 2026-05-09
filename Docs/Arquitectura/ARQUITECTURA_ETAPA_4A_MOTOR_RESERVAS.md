# ARQUITECTURA_ETAPA_4A_MOTOR_RESERVAS.md
# Motor de Reservas Determinístico

**Versión:** 1.0
**Fecha:** Mayo 2026
**Estado:** Aprobado — CERRADO
**Depende de:** ARQUITECTURA_ETAPA_1_VITA_DELTA.md v1.1 / ARQUITECTURA_ETAPA_2_VITA_DELTA.md v1.1 / ARQUITECTURA_ETAPA_3_VITA_DELTA.md v3.0
**Autores:** Franco (titular) + Claude (arquitecto)

---

## ÍNDICE

1. Objetivo del motor de reservas
2. Principios del motor
3. Entidades involucradas y decisiones de persistencia
4. Estados de CONSULTAS
5. Estados de PRE_RESERVAS
6. Estados de RESERVAS
7. Estados de PAGOS
8. Flujo principal: consulta → cotización → pre-reserva → pago → confirmación
9. Expiración automática de pre-reserva
10. Arquitectura de PAGOS multicanal
11. Confirmación automática con MercadoPago
12. Confirmación manual con comprobante
13. Revalidación de disponibilidad antes de confirmar
14. Actualización de DISPONIBILIDAD_CACHE
15. Actualización del calendario visual
16. Mensajes automáticos al huésped
17. Mensajes automáticos al grupo operativo
18. Coordinación con Jennifer
19. Asignación del encargado semanal Franco/Rodrigo
20. Cancelaciones y modificaciones post-confirmación
21. Conflictos y resolución manual
22. source_event por acción
23. Workflows internos n8n
24. Edge cases
25. Pendientes para Etapa 4B

---

## 1. OBJETIVO DEL MOTOR DE RESERVAS

El motor de reservas es el componente que convierte una consulta en una reserva confirmada, gestionando de forma determinística todos los estados intermedios, validaciones, pagos y notificaciones.

> **Pregunta central que resuelve esta etapa:**
> ¿Cómo pasa el sistema de "el cliente quiere reservar" a "la reserva está confirmada, el pago registrado, el equipo notificado y la disponibilidad actualizada"?

### Qué incluye esta etapa

- Ciclo de vida completo de CONSULTAS, PRE_RESERVAS, RESERVAS y PAGOS
- Flujo transaccional desde consulta hasta confirmación
- Expiración automática de pre-reservas
- Arquitectura multicanal de pagos
- Revalidación de disponibilidad antes de confirmar
- Actualización de DISPONIBILIDAD_CACHE y calendario visual
- Mensajes automáticos al huésped y al equipo operativo
- Coordinación básica con Jennifer por WhatsApp
- Cancelaciones con intervención humana
- Manejo de conflictos

### Qué NO incluye esta etapa

- El bot conversacional con IA (Etapa 4B)
- La lógica de cómo el bot interpreta mensajes del cliente
- Automatización completa de cancelaciones (intervención humana en esta versión)
- App de tareas para Jennifer (prevista para etapa posterior)
- Implementación real de webhooks de MercadoPago (solo arquitectura)
- Contabilidad y distribución entre socios

---

## 2. PRINCIPIOS DEL MOTOR

**1. Determinismo absoluto.** Cada acción del motor produce siempre el mismo resultado ante las mismas condiciones. No hay ambigüedad ni decisiones implícitas.

**2. Secuencialidad en operaciones críticas.** Crear pre-reserva, confirmar reserva y registrar pago son operaciones que nunca se ejecutan en paralelo. n8n garantiza esto con concurrencia = 1 en los workflows críticos.

**3. Revalidación antes de confirmar.** Ninguna reserva se confirma sin verificar disponibilidad en el momento exacto de la confirmación, independientemente de si la pre-reserva existía previamente.

**4. La IA no ejecuta operaciones transaccionales.** El bot puede recibir solicitudes, interpretarlas y estructurarlas. La ejecución real siempre la dispara un workflow determinístico de n8n.

**5. Todo queda registrado.** Cada cambio de estado, cada pago, cada notificación enviada queda en LOG_CAMBIOS con timestamp, autor y source_event.

**6. Mínima persistencia nueva.** Antes de crear una tabla nueva, se evalúa si el concepto puede resolverse como paso de workflow, log auxiliar o campo en una tabla existente.

**7. Degradación controlada.** Si n8n no está disponible, el sistema no colapsa. Vicky puede operar manualmente en Sheets. Al recuperarse n8n, se ejecuta recálculo masivo y se verifican inconsistencias.

---

## 3. ENTIDADES INVOLUCRADAS Y DECISIONES DE PERSISTENCIA

### 3.1 Entidades principales (ya definidas en Etapas 1 y 2)

| Entidad | Rol en esta etapa |
|---|---|
| CONSULTAS | Representa la conversación activa del cliente |
| PRE_RESERVAS | Bloqueo temporal con tiempo de expiración |
| RESERVAS | Reserva confirmada con pago validado |
| PAGOS | Registro de cada transacción económica |
| DISPONIBILIDAD_CACHE | Cache derivada que refleja el estado de ocupación |
| BLOQUEOS | Bloqueos manuales, sin cambios en esta etapa |
| LOG_CAMBIOS | Auditoría de toda operación crítica |
| CONFIGURACION_GENERAL | Parámetros operativos: timeouts, porcentajes, ciclos |

### 3.2 Decisiones de persistencia para conceptos nuevos

**Mensajes automáticos al huésped y al equipo**

Decisión: no es una tabla persistente nueva.

Los mensajes son pasos dentro de los workflows de n8n. Las plantillas de texto viven como filas en una hoja auxiliar `PLANTILLAS_MENSAJES` en Sheets (estructura clave-valor similar a CONFIGURACION_GENERAL). El envío es un paso del workflow, no una entidad con ciclo de vida propio.

Lo que sí queda registrado en LOG_CAMBIOS: que el mensaje fue enviado, a quién, en qué evento. Pero el mensaje en sí no necesita una tabla propia en esta etapa.

**Tareas para Jennifer**

Decisión: en Etapa 4A, la coordinación con Jennifer es un mensaje de WhatsApp automático enviado por n8n. No hay tabla TAREAS_OPERATIVAS en esta etapa.

La tabla TAREAS_OPERATIVAS prevista en Etapa 1 queda para una etapa posterior cuando sea necesario rastrear estado de tareas, asignación múltiple o checklist. En esta etapa, el mensaje saliente a Jennifer es suficiente y la tarea queda implícita.

**Encargado semanal**

Decisión: la asignación vive en CONFIGURACION_GENERAL como ciclo configurable. No necesita tabla propia. El campo `encargado_semana` en RESERVAS almacena el resultado calculado.

**Plantillas de mensajes**

Decisión: hoja auxiliar `PLANTILLAS_MENSAJES` en Sheets con estructura mínima:

| id_plantilla | evento_disparador | canal | texto | activa |
|---|---|---|---|---|
| prereserva_creada | prereserva_created | whatsapp | Hola {nombre}, tu pre-reserva... | true |

No es necesaria una tabla compleja con variables separadas. Las variables van embebidas como `{nombre}`, `{fecha_checkin}`, etc., y n8n las reemplaza al enviar.

---

## 4. ESTADOS DE CONSULTAS

### 4.1 Diagrama de estados

```
[inicio]
    │
    ▼
[eligiendo_fechas]
    │
    ▼
[cotizando]  ──────────────────────────────► [derivada_a_humano]
    │                                                │
    ▼                                                │ (humano resuelve o cierra)
[esperando_pago]                                     │
    │                                                ▼
    ▼                                           [cerrada]
[pago_en_proceso]
    │
    ├──► [cerrada]      (pago confirmado → reserva creada)
    └──► [derivada_a_humano]  (conflicto o error)
```

### 4.2 Definición de cada estado

| Estado | Descripción | Quién puede cambiarla |
|---|---|---|
| `inicio` | Conversación nueva, cliente identificado o no | Bot / n8n al recibir primer mensaje |
| `eligiendo_fechas` | Cliente está indicando fechas y cabaña | Bot guía, n8n registra |
| `cotizando` | Sistema calculó precio, cliente evalúa | n8n al calcular cotización |
| `esperando_pago` | Pre-reserva creada, aguardando pago | n8n al crear PRE_RESERVA |
| `pago_en_proceso` | Pago detectado o comprobante enviado, pendiente de validar | n8n (webhook MP) o Vicky (manual) |
| `cerrada` | Proceso terminado: reserva confirmada o sin interés | n8n al confirmar reserva |
| `derivada_a_humano` | Requiere intervención de Vicky/Franco/Rodrigo | Bot o n8n según regla |

### 4.3 Condiciones de transición

- `inicio` → `eligiendo_fechas`: cliente envía fechas o intención de reserva
- `eligiendo_fechas` → `cotizando`: n8n tiene fechas, cabaña y personas confirmadas; calcula precio
- `cotizando` → `esperando_pago`: cliente acepta cotización; n8n crea PRE_RESERVA
- `esperando_pago` → `pago_en_proceso`: cliente envía comprobante o webhook de MP llega
- `pago_en_proceso` → `cerrada`: pago validado y reserva confirmada
- `pago_en_proceso` → `derivada_a_humano`: conflicto en validación o disponibilidad cambió
- cualquier estado → `derivada_a_humano`: bot no puede resolver, cliente pide hablar con persona, o regla de derivación activa
- cualquier estado → `cerrada`: cliente abandona, pre-reserva vence sin retomar

### 4.4 Expiración de conversación inactiva

Una CONSULTA en estado `esperando_pago` o `cotizando` que no registra actividad en `conversacion_expiracion_horas` (configurable, default: 24hs) pasa a `cerrada` automáticamente. n8n ejecuta este chequeo junto con el de expiración de pre-reservas.

---

## 5. ESTADOS DE PRE_RESERVAS

### 5.1 Diagrama de estados

```
[pendiente_pago]
    │
    ├──► [vencida]              (tiempo agotado sin pago)
    ├──► [convertida]           (pago confirmado → RESERVA creada)
    ├──► [cancelada_por_cliente] (cliente cancela antes de pagar)
    ├──► [cancelada_por_bloqueo] (admin crea bloqueo encima)
    └──► [conflicto_pendiente]  (race condition detectada)
```

### 5.2 Definición de cada estado

| Estado | Bloquea disponibilidad | Descripción |
|---|---|---|
| `pendiente_pago` | Sí | PRE_RESERVA activa esperando pago |
| `vencida` | No | Expiró sin pago. Disponibilidad liberada |
| `convertida` | — | Se convirtió en RESERVA confirmada |
| `cancelada_por_cliente` | No | Cliente canceló antes de pagar |
| `cancelada_por_bloqueo` | No | Admin creó bloqueo sobre estas fechas |
| `conflicto_pendiente` | Sí | Dos pre-reservas simultáneas detectadas. Requiere resolución manual |

### 5.3 Reglas de bloqueo de disponibilidad

Una PRE_RESERVA bloquea disponibilidad en DISPONIBILIDAD_CACHE desde el momento de su creación hasta que:
- vence (`vencida`),
- se convierte (`convertida`), o
- se cancela por cualquier motivo.

El estado `conflicto_pendiente` mantiene el bloqueo hasta que el equipo resuelve manualmente.

### 5.4 Campos adicionales relevantes para esta etapa

Los campos ya definidos en Etapa 1 son suficientes. Se agrega un campo:

| Campo | Tipo | Descripción |
|---|---|---|
| `intentos_pago` | Integer | Cuántas veces el cliente intentó pagar (para detectar problemas de MP) |
| `canal_pago_esperado` | String | Medio de pago que el cliente eligió: `mp_link`, `transferencia_bancaria`, `transferencia_mp`, `cripto` |

---

## 6. ESTADOS DE RESERVAS

### 6.1 Diagrama de estados completo

```
[confirmada]
    │
    ├──► [activa]           (día de checkin registrado)
    │        │
    │        └──► [completada]   (checkout registrado)
    │
    ├──► [cancelada]             (cancelación sin cargo)
    ├──► [cancelada_con_cargo]   (cancelación con retención)
    └──► [conflicto_pendiente]   (error detectado post-confirmación)
```

### 6.2 Definición de cada estado

| Estado | Bloquea disponibilidad | Notifica equipo | Descripción |
|---|---|---|---|
| `confirmada` | Sí | Sí | Pago validado, reserva firme |
| `activa` | Sí | No | Huésped en el complejo |
| `completada` | No | Sí | Checkout realizado |
| `cancelada` | No | Sí | Cancelada sin cargo económico |
| `cancelada_con_cargo` | No | Sí | Cancelada con retención de seña u otro cargo |
| `conflicto_pendiente` | Sí | Sí | Error post-confirmación. Resolución manual requerida |

### 6.3 Transiciones y responsables

| Transición | Disparador | Responsable |
|---|---|---|
| PRE_RESERVA → `confirmada` | Pago validado (auto o manual) | n8n workflow `db_confirmar_reserva` |
| `confirmada` → `activa` | Check-in registrado | Vicky o Franco en Sheets / futuro formulario |
| `activa` → `completada` | Checkout registrado | Ídem |
| `confirmada` → `cancelada` | Solicitud validada por humano | Vicky o Franco → dispara workflow |
| `confirmada` → `cancelada_con_cargo` | Ídem, con condición de cargo | Ídem |
| cualquier estado → `conflicto_pendiente` | n8n detecta inconsistencia | n8n automático |

---

## 7. ESTADOS DE PAGOS

### 7.1 Diagrama de estados

```
[pendiente]
    │
    ├──► [en_revision]    (comprobante recibido, pendiente de validación humana)
    │        │
    │        ├──► [confirmado]
    │        └──► [rechazado]
    │
    ├──► [confirmado]     (validado automáticamente via webhook)
    ├──► [rechazado]      (pago fallido o comprobante inválido)
    └──► [reembolsado]    (devolución ejecutada)
```

### 7.2 Definición de cada estado

| Estado | Descripción | Acción siguiente |
|---|---|---|
| `pendiente` | Pago esperado, instrucciones enviadas al cliente | Esperar webhook o comprobante |
| `en_revision` | Comprobante recibido de un pago manual, pendiente de validación humana | Vicky o Franco aprueban o rechazan |
| `confirmado` | Pago validado. Reserva puede confirmarse | n8n continúa flujo de confirmación |
| `rechazado` | Pago fallido, comprobante apócrifo o monto incorrecto | Notificar cliente. PRE_RESERVA sigue activa si no venció |
| `reembolsado` | Devolución procesada | Registrar en PAGOS. Notificar cliente y equipo |

### 7.3 Relación PAGOS ↔ RESERVAS

Un PAGO en estado `confirmado` no confirma automáticamente la RESERVA. El workflow de confirmación hace la revalidación de disponibilidad primero. Solo si la disponibilidad está OK convierte la PRE_RESERVA en RESERVA.

Esto es importante: el pago y la confirmación de reserva son pasos secuenciales, no simultáneos.

---

## 8. FLUJO PRINCIPAL: CONSULTA → COTIZACIÓN → PRE-RESERVA → PAGO → CONFIRMACIÓN

### 8.1 Mapa del flujo completo

```
[Cliente inicia conversación]
        │
        ▼
[n8n identifica o crea HUÉSPED]
[Crea o retoma CONSULTA en estado 'inicio']
        │
        ▼
[Bot recopila: fechas, cabaña, personas]
[CONSULTA → 'eligiendo_fechas']
        │
        ▼
[n8n consulta DISPONIBILIDAD_CACHE]
        │
        ├── No disponible ──► [Bot informa. CONSULTA → 'cerrada' o sugiere fechas alternativas]
        │
        └── Disponible
                │
                ▼
        [n8n calcula precio (Motor Etapa 3)]
        [CONSULTA → 'cotizando']
        [Bot presenta cotización al cliente]
                │
                ├── Cliente no acepta ──► [CONSULTA → 'cerrada']
                │
                └── Cliente acepta
                        │
                        ▼
                [n8n ejecuta db_crear_prereserva]
                [PRE_RESERVA creada en 'pendiente_pago']
                [DISPONIBILIDAD_CACHE actualizada]
                [CONSULTA → 'esperando_pago']
                [Bot informa medio de pago y monto de seña]
                        │
                        ├── Tiempo agota (ver Sección 9)
                        │
                        └── Cliente paga
                                │
                                ├── MercadoPago Link ──► [Webhook automático → Sección 11]
                                │
                                └── Manual (transferencia/cripto/etc.) ──► [Sección 12]
                                        │
                                        ▼
                                [CONSULTA → 'pago_en_proceso']
                                [n8n ejecuta db_confirmar_reserva]
                                [Revalidación disponibilidad (Sección 13)]
                                        │
                                        ├── Conflicto ──► [conflicto_pendiente → Sección 21]
                                        │
                                        └── OK
                                                │
                                                ▼
                                        [PRE_RESERVA → 'convertida']
                                        [RESERVA creada en 'confirmada']
                                        [PAGO → 'confirmado']
                                        [DISPONIBILIDAD_CACHE actualizada]
                                        [Calendario visual actualizado]
                                        [Mensajes al huésped]
                                        [Mensajes al equipo]
                                        [Mensaje a Jennifer]
                                        [CONSULTA → 'cerrada']
                                        [LOG_CAMBIOS registrado]
```

### 8.2 Quién hace qué

| Paso | Bot | n8n | Vicky/Franco | Cliente |
|---|---|---|---|---|
| Recopilación de datos | ✓ | — | — | Responde |
| Consulta disponibilidad | — | ✓ | — | — |
| Calcula precio | — | ✓ | — | — |
| Presenta cotización | ✓ | — | — | Acepta/rechaza |
| Crea PRE_RESERVA | — | ✓ | — | — |
| Informa instrucciones de pago | ✓ | — | — | — |
| Valida pago automático (MP) | — | ✓ | — | — |
| Valida pago manual | — | — | ✓ | — |
| Confirma reserva | — | ✓ | — | — |
| Notifica al huésped | — | ✓ | — | — |
| Notifica al equipo | — | ✓ | — | — |

---

## 9. EXPIRACIÓN AUTOMÁTICA DE PRE-RESERVA

### 9.1 Mecanismo

n8n ejecuta un workflow programado cada 5 minutos:

```
WORKFLOW: sistema_expirar_prereservas (schedule: cada 5 min)

PASO 1: Buscar PRE_RESERVAS WHERE estado = 'pendiente_pago'
                               AND expira_en < NOW()

PASO 2: Para cada PRE_RESERVA encontrada:
  a. Cambiar estado → 'vencida'
  b. Registrar en LOG_CAMBIOS con source_event = 'sistema_expiracion'
  c. Disparar db_recalcular_disponibilidad para las fechas afectadas
  d. Cambiar CONSULTA asociada → 'cerrada' (si no hay actividad reciente)
  e. Enviar mensaje al cliente: "Tu pre-reserva venció. Si querés reservar,
     podemos verificar disponibilidad nuevamente."
  f. Notificar al equipo si el monto de la pre-reserva superaba un umbral
     configurable (default: $200.000)
```

### 9.2 Edge case: cliente paga justo cuando vence

**Situación:** La PRE_RESERVA tiene `expira_en = 14:00:00`. El webhook de MP llega a las 13:59:58. El workflow de expiración también corre en ese momento.

**Solución:** El workflow `db_confirmar_reserva` tiene concurrencia = 1. Si el webhook de confirmación llega primero, la PRE_RESERVA pasa a `convertida` antes de que el workflow de expiración la pueda marcar como `vencida`. Si el workflow de expiración llega primero, el webhook de MP encontrará una PRE_RESERVA en estado `vencida` y disparará el flujo de conflicto (Sección 21, edge case 2).

**Regla:** El workflow `db_confirmar_reserva` verifica el estado de la PRE_RESERVA en su Paso 1. Si está `vencida`, no confirma y notifica al equipo.

### 9.3 Reintento del cliente

Si la PRE_RESERVA venció y el cliente quiere continuar:
1. Bot verifica disponibilidad nuevamente (puede haber cambiado)
2. Si sigue disponible: crea nueva PRE_RESERVA con nuevo tiempo de expiración
3. Si no está disponible: informa al cliente y ofrece alternativas

### 9.4 Configuración

| Clave | Valor default | Descripción |
|---|---|---|
| `prereserva_expiracion_minutos` | 60 | Tiempo de vida de una PRE_RESERVA |
| `prereserva_notificacion_vencimiento_umbral` | 200000 | Monto desde el que se notifica al equipo al vencer |
| `prereserva_recordatorio_minutos_antes` | 15 | Minutos antes del vencimiento para enviar recordatorio al cliente |

---

## 10. ARQUITECTURA DE PAGOS MULTICANAL

### 10.1 Principio

El motor de reservas no debe depender de un único proveedor de pago. La tabla PAGOS y los workflows de confirmación deben soportar cualquier medio presente o futuro sin modificar la lógica central.

### 10.2 Tabla PAGOS — estructura completa

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_pago | Integer | Sí | ID único autoincremental |
| id_prereserva | Integer | Sí | FK → PRE_RESERVAS |
| id_reserva | Integer | No | FK → RESERVAS (se llena al confirmar) |
| tipo | String | Sí | `sena`, `saldo`, `extra`, `reembolso` |
| medio_pago | String | Sí | Ver valores válidos abajo |
| proveedor | String | No | `mercadopago`, `banco_galicia`, `banco_santander`, `binance`, etc. |
| cuenta_destino | String | No | CBU, alias, dirección cripto o cuenta MP |
| monto_esperado | Number | Sí | Monto que el sistema espera recibir |
| monto_recibido | Number | No | Monto real recibido (puede diferir) |
| moneda | String | Sí | `ARS`, `USD`, `USDT`, `BTC` |
| estado | String | Sí | `pendiente`, `confirmado`, `rechazado`, `reembolsado` |
| es_automatico | Boolean | Sí | Si la validación fue automática (webhook) o manual |
| comprobante_url | String | No | Link a imagen o PDF del comprobante |
| referencia_externa | String | No | ID de la transacción en MP u otro proveedor |
| tx_hash | String | No | Hash de transacción para pagos cripto |
| validado_por | String | No | `bot_mp`, `vicky`, `franco`, `rodrigo` |
| validado_en | Timestamp | No | Cuándo se confirmó el pago |
| motivo_rechazo | String | No | Por qué fue rechazado |
| notas | Text | No | Observaciones adicionales |
| source_event | String | Sí | Origen del evento que creó/modificó el pago |
| created_at | Timestamp | Sí | |

### 10.3 Valores válidos de `medio_pago`

| Valor | Descripción | Validación |
|---|---|---|
| `mp_link` | Link de pago generado por MercadoPago | Automática via webhook |
| `transferencia_mp` | Transferencia a cuenta de MercadoPago | Manual (comprobante) |
| `transferencia_bancaria` | CBU/CVU bancario | Manual (comprobante) |
| `tarjeta` | Tarjeta via MP u otro procesador | Automática (futuro) |
| `efectivo` | Efectivo en mano | Manual (registro por Vicky/Franco) |
| `cripto` | Criptomonedas | Manual (tx_hash + validación) |

### 10.4 Cuáles son automáticos y cuáles manuales

| Medio | Flujo | Automatizable ahora |
|---|---|---|
| `mp_link` | Webhook de MP notifica pago → n8n valida y confirma | Sí |
| `transferencia_mp` | Cliente envía comprobante → Vicky valida → dispara workflow | No (manual) |
| `transferencia_bancaria` | Ídem | No (manual) |
| `tarjeta` | Vía MP, mismo webhook | Sí (si usa link MP con tarjeta) |
| `efectivo` | Franco/Vicky registra manualmente | No (siempre manual) |
| `cripto` | Cliente envía tx_hash → validación manual | No (manual en esta etapa) |

### 10.5 Cuentas destino

Las cuentas destino (CBU, alias, dirección cripto) viven en una tabla auxiliar `CUENTAS_COBRO` en Sheets:

| id_cuenta | nombre | medio | datos | activa |
|---|---|---|---|---|
| 1 | MP Vita Delta | transferencia_mp | alias: vitadelta.mp | true |
| 2 | Galicia Franco | transferencia_bancaria | CBU: ... | true |
| 3 | USDT TRC20 | cripto | dirección: ... | true |

El bot consulta `CUENTAS_COBRO` para presentar los datos de pago al cliente según el medio elegido. Si el cliente no elige, el bot presenta los medios disponibles (los que tienen `activa = true`).

---

## 11. CONFIRMACIÓN AUTOMÁTICA CON MERCADOPAGO

### 11.1 Arquitectura del webhook

```
[MercadoPago detecta pago acreditado]
        │
        ▼
[MP envía POST al webhook de n8n]
[URL: https://federicosecchi.app.n8n.cloud/webhook/mp-pago]
        │
        ▼
[WORKFLOW: recibir_webhook_mp]

PASO 1: Verificar autenticidad del webhook
  → Header X-Signature debe coincidir con secret configurado en MP
  → Si no coincide → rechazar con 401, registrar en LOG_CAMBIOS

PASO 2: Extraer datos del payload
  → referencia_externa (payment_id de MP)
  → monto
  → estado del pago en MP ('approved', 'pending', 'rejected')
  → metadata: id_prereserva (debe estar en el metadata del link generado)

PASO 3: Verificar que el estado de MP sea 'approved'
  → Si es 'pending': ignorar (puede llegar otro webhook cuando se apruebe)
  → Si es 'rejected': actualizar PAGO → 'rechazado', notificar cliente

PASO 4: Buscar el PAGO correspondiente por referencia_externa o id_prereserva
  → Si no existe: crear registro PAGO con los datos recibidos
  → Si existe y ya está 'confirmado': ignorar (pago duplicado)

PASO 5: Verificar que monto_recibido >= monto_esperado
  → Si hay diferencia: notificar a Vicky para revisión manual
  → Si coincide: continuar

PASO 6: Llamar a db_confirmar_reserva (Sección 13)
```

### 11.2 Generación del link de pago

Cuando el cliente elige `mp_link` como medio de pago:

```
WORKFLOW: generar_link_mp

INPUT: { id_prereserva, monto_sena, descripcion }

PASO 1: Llamar a MP API → crear preference
  Datos:
    title: "Seña cabaña {nombre_cabana} - {fecha_in} a {fecha_out}"
    unit_price: monto_sena
    quantity: 1
    metadata: { id_prereserva: id_prereserva }
    notification_url: URL del webhook n8n
    expiration_date_to: expira_en de la PRE_RESERVA

PASO 2: Guardar preference_id en PRE_RESERVAS.referencia_mp
PASO 3: Devolver init_point (URL del link de pago)
PASO 4: Bot envía el link al cliente
```

### 11.3 Expiración del link de MP

El link de MP se configura con `expiration_date_to` igual a `expira_en` de la PRE_RESERVA. Esto garantiza que si la PRE_RESERVA vence, el link también queda inactivo automáticamente.

---

## 12. CONFIRMACIÓN MANUAL CON COMPROBANTE

### 12.1 Flujo para transferencias bancarias y MP

```
[Cliente envía comprobante por WhatsApp o Instagram]
        │
        ▼
[Bot recibe el comprobante (imagen o PDF)]
[Bot confirma recepción al cliente: "Recibimos tu comprobante, lo estamos revisando."]
[n8n guarda el archivo y notifica a Vicky y Franco]
        │
        ▼
[Vicky o Franco revisan el comprobante]
        │
        ├── Comprobante inválido o monto incorrecto
        │        │
        │        ▼
        │   [Vicky marca "rechazado" en formulario interno]
        │   [n8n actualiza PAGO → 'rechazado']
        │   [Bot notifica al cliente con motivo]
        │   [PRE_RESERVA sigue activa si no venció]
        │
        └── Comprobante válido
                 │
                 ▼
        [Vicky marca "aprobado" en formulario interno]
        [Completa: monto_recibido, cuenta_destino, referencia si tiene]
        [Formulario dispara webhook a n8n]
                 │
                 ▼
        [n8n ejecuta db_confirmar_reserva]
        [Mismo flujo que confirmación automática desde Paso 2 de Sección 13]
```

### 12.2 Formulario interno de validación manual

El formulario para Vicky es un Google Form conectado a n8n via Apps Script (mismo patrón de la Etapa 1). Campos:

- ID de pre-reserva (manual o búsqueda)
- Decisión: Aprobar / Rechazar
- Monto recibido
- Medio de pago
- Cuenta destino utilizada
- Referencia de la transferencia
- Notas
- Botón de envío → trigger webhook n8n

### 12.3 Flujo para cripto

Igual que transferencia bancaria, con campo adicional `tx_hash`. Vicky o Franco verifican la transacción en el explorador de la blockchain antes de aprobar. En esta etapa la verificación es 100% manual.

---

## 13. REVALIDACIÓN DE DISPONIBILIDAD ANTES DE CONFIRMAR

### 13.1 Principio

Esta es la garantía central del sistema contra double bookings. Ninguna reserva se confirma sin ejecutar esta verificación en el momento exacto de la confirmación.

### 13.2 Workflow: db_confirmar_reserva

```
WORKFLOW: db_confirmar_reserva
CONCURRENCIA: 1 (una ejecución a la vez — garantía de secuencialidad)

INPUT: { id_prereserva, id_pago, validado_por, source_event }

PASO 1: Verificar estado de la PRE_RESERVA
  → Buscar PRE_RESERVA WHERE id = id_prereserva
  → SI estado != 'pendiente_pago':
      SI estado = 'vencida':
        → Disparar notificación al equipo: pago recibido pero PRE_RESERVA ya venció
        → Actualizar PAGO → estado='rechazado', motivo='prereserva_vencida'
        → Registrar en LOG_CAMBIOS
        → RETORNAR { error: 'prereserva_vencida' }
      SI estado = 'convertida':
        → Ignorar (pago duplicado, reserva ya confirmada)
        → RETORNAR { ok: true, nota: 'ya_confirmada' }
      OTRO:
        → Notificar al equipo con detalle del estado inesperado
        → RETORNAR { error: 'estado_inesperado' }

PASO 2: Revalidar disponibilidad completa
  → Consultar RESERVAS: ¿hay reserva confirmada para (id_cabana, fechas)?
  → Consultar PRE_RESERVAS: ¿hay otra PRE_RESERVA vigente (pendiente_pago) para las mismas fechas?
  → Consultar BLOQUEOS: ¿hay bloqueo activo para esas fechas?

  Nota: la propia PRE_RESERVA en validación se excluye de la consulta de conflictos.

PASO 3a: Si hay conflicto
  → NO confirmar la reserva
  → PRE_RESERVA → 'conflicto_pendiente'
  → PAGO → estado='pendiente' (queda registrado pero no confirmado)
  → Registrar en LOG_CAMBIOS con todos los detalles del conflicto
  → Notificar INMEDIATAMENTE a Franco y Vicky por WhatsApp:
      "⚠️ Conflicto de reserva: [cabaña] [fechas]. Cliente [nombre] pagó pero
       hay conflicto de disponibilidad. ID pre-reserva: [id]. Revisar manualmente."
  → RETORNAR { error: 'conflicto_disponibilidad' }

PASO 3b: Si disponibilidad OK
  → PRE_RESERVA → 'convertida'
  → Crear RESERVA en estado 'confirmada' con todos los campos
  → PAGO → estado='confirmado', id_reserva=nueva_reserva.id
  → Recalcular DISPONIBILIDAD_CACHE para las fechas afectadas ± 2 días
  → Actualizar calendario visual
  → Ejecutar mensajes al huésped (Sección 16)
  → Ejecutar mensajes al equipo (Sección 17)
  → Ejecutar mensaje a Jennifer (Sección 18)
  → Registrar en LOG_CAMBIOS
  → RETORNAR { ok: true, id_reserva: nueva_reserva.id }
```

### 13.3 Por qué la concurrencia = 1 es suficiente

Con concurrencia = 1 en n8n, si dos webhooks de pago llegan simultáneamente para la misma cabaña y fechas:
- El primero entra al workflow y ejecuta la revalidación
- El segundo queda en cola
- Cuando el primero termina (PRE_RESERVA → `convertida`, RESERVA creada), el segundo entra
- El segundo encuentra la PRE_RESERVA en estado `convertida` → flujo de duplicado (Paso 1)

No hay window de race condition porque el estado de la PRE_RESERVA se lee y escribe dentro del mismo workflow secuencial.

---

## 14. ACTUALIZACIÓN DE DISPONIBILIDAD_CACHE

### 14.1 Qué eventos disparan recálculo en esta etapa

| Evento | Scope de recálculo |
|---|---|
| PRE_RESERVA creada | Fechas de la pre-reserva |
| PRE_RESERVA vencida | Fechas de la pre-reserva + días adyacentes (escalonamiento) |
| PRE_RESERVA convertida en RESERVA | Fechas de la reserva ± 2 días (buffer de escalonamiento) |
| RESERVA cancelada | Ídem |
| PAGO rechazado (PRE_RESERVA sigue activa) | Sin recálculo — la cache ya refleja el bloqueo |

### 14.2 Recálculo parcial post-confirmación

```
WORKFLOW: db_recalcular_disponibilidad (llamado desde db_confirmar_reserva)

INPUT: { id_cabanas: [array], fechas: [array], source_event }

Para cada (id_cabana, fecha):
  1. Verificar BLOQUEOS activos → si existe: estado = 'bloqueada'
  2. Verificar RESERVAS confirmadas → si existe: estado = 'ocupada'
  3. Verificar PRE_RESERVAS pendientes → si existe: estado = 'ocupada'
  4. Verificar si es día de checkout de una reserva → estado = 'checkout_disponible'
  5. Si nada anterior: estado = 'disponible'
  6. Calcular horarios con escalonamiento (Etapa 2)
  7. Escribir en DISPONIBILIDAD_CACHE
  8. Registrar en LOG_CAMBIOS si el estado cambió
```

El recálculo masivo nocturno (03:00am, definido en Etapa 2) sigue vigente como corrección de inconsistencias.

---

## 15. ACTUALIZACIÓN DEL CALENDARIO VISUAL

### 15.1 Qué es el calendario visual

El calendario visual operativo principal de esta etapa es una vista en Google Sheets utilizada por el equipo interno (Franco, Rodrigo, Vicky y Jennifer).

La web pública y el frontend del cliente utilizan una representación visual independiente basada en DISPONIBILIDAD_CACHE y el motor de reservas.

Google Calendar puede incorporarse más adelante como vista secundaria o integración adicional, pero no es la fuente principal de operación en esta etapa.

### 15.2 Cuándo y cómo actualiza n8n

n8n actualiza la vista en Sheets en estos momentos:

| Evento | Acción en calendario (Sheets) |
|---|---|
| RESERVA confirmada | Agregar fila con: cabaña, huésped, fechas, horarios, encargado |
| RESERVA cancelada | Marcar fila como cancelada |
| Modificación de fechas (manual) | Actualizar fila |
| RESERVA → `activa` (checkin) | Actualizar estado en la fila |
| RESERVA → `completada` (checkout) | Marcar como completada |

### 15.3 Información por fila en el calendario de Sheets

```
Título: [Cabaña] - [Apellido huésped]
Ejemplo: "Bamboo - García"

Descripción:
  Huésped: Juan García
  Teléfono: +54 9 11 XXXX XXXX
  Personas: 4
  Checkin: vie 20 jun 13:00
  Checkout: dom 22 jun 16:00
  Encargado semana: Franco
  Total: $350.000 | Seña: $175.000
  Canal: WhatsApp
  ID Reserva: #142
```

---

## 16. MENSAJES AUTOMÁTICOS AL HUÉSPED

### 16.1 Principio de implementación

Los mensajes son pasos de los workflows de n8n. Las plantillas de texto viven en `PLANTILLAS_MENSAJES` (hoja auxiliar en Sheets). El canal de envío (WhatsApp o Instagram) se determina por el `canal_origen` de la CONSULTA/RESERVA.

### 16.2 Catálogo de mensajes al huésped

| id_plantilla | Evento disparador | Canal | Momento |
|---|---|---|---|
| `prereserva_creada` | PRE_RESERVA creada | Origen de la consulta | Inmediato |
| `instrucciones_pago` | PRE_RESERVA creada | Ídem | Inmediato (junto al anterior) |
| `recordatorio_pago` | 15 min antes de vencer | Ídem | Automático |
| `prereserva_vencida` | PRE_RESERVA vencida | Ídem | Inmediato |
| `pago_recibido` | PAGO en revisión manual | Ídem | Al recibir comprobante |
| `reserva_confirmada` | RESERVA confirmada | Ídem | Inmediato |
| `recordatorio_checkin` | 24hs antes del checkin | WhatsApp preferido | Programado |
| `bienvenida_checkin` | Día de checkin | WhatsApp preferido | A la hora del checkin |
| `recordatorio_checkout` | Noche anterior al checkout | WhatsApp preferido | 20:00 del día anterior |
| `post_checkout` | RESERVA completada | WhatsApp preferido | 2hs después del checkout |

### 16.3 Ejemplo de plantillas

**prereserva_creada:**
```
Hola {nombre}! 🌿 Reservaste {nombre_cabana} del {fecha_in} al {fecha_out}
para {personas} personas.

Tu pre-reserva está activa por {expiracion_minutos} minutos.
A continuación te enviamos los datos para la seña.
```

**reserva_confirmada:**
```
¡Reserva confirmada! ✅

{nombre_cabana} | {fecha_in} → {fecha_out}
Check-in: {hora_checkin}hs | Check-out: {hora_checkout}hs
{personas} personas

Saldo a pagar al llegar: ${saldo}
Cualquier consulta estamos acá. ¡Nos vemos pronto! 🛶
```

**recordatorio_checkin:**
```
Hola {nombre}! Mañana es tu día 🎉
{nombre_cabana} te espera a las {hora_checkin}hs.
{instrucciones_llegada}

¿Tenés alguna duda de último momento?
```

---

## 17. MENSAJES AUTOMÁTICOS AL GRUPO OPERATIVO

### 17.1 Canales del equipo

Los mensajes al equipo van al grupo de WhatsApp operativo. Para notificaciones críticas (conflictos, pagos pendientes de monto alto), se envía también mensaje directo a Franco.

### 17.2 Catálogo de mensajes al equipo

| Evento | Destinatario | Urgencia |
|---|---|---|
| PRE_RESERVA creada (monto > umbral) | Grupo | Normal |
| RESERVA confirmada | Grupo | Normal |
| PRE_RESERVA vencida (monto > umbral) | Grupo | Normal |
| Conflicto de reserva detectado | Grupo + Franco directo | ⚠️ Alta |
| Pago rechazado | Vicky + Franco | Media |
| Límite de escalonamiento alcanzado | Franco + Rodrigo | ⚠️ Alta |
| RESERVA cancelada | Grupo | Normal |
| RESERVA completada (checkout) | Grupo | Normal |

### 17.3 Ejemplo de mensajes

**RESERVA confirmada:**
```
✅ Nueva reserva confirmada

Cabaña: Bamboo
Huésped: Juan García | +54 9 11 XXXX XXXX
Fechas: vie 20 jun → dom 22 jun
Checkin: 13:00hs | Checkout: 16:00hs
Personas: 4
Total: $350.000 | Seña cobrada: $175.000
Encargado: Franco
Canal: WhatsApp | ID: #142
```

**Conflicto detectado:**
```
⚠️ CONFLICTO DE RESERVA

Cabaña: Bamboo | Fechas: 20-22 jun
Cliente: Juan García
El cliente pagó pero hay conflicto de disponibilidad.
Estado: conflicto_pendiente
ID pre-reserva: #89

Revisar manualmente y resolver.
```

---

## 18. COORDINACIÓN CON JENNIFER

### 18.1 Principio para esta etapa

La coordinación con Jennifer en Etapa 4A es simple: mensaje automático de WhatsApp en dos momentos clave. No hay tabla de tareas, no hay app, no hay checklist en esta versión.

### 18.2 Momentos de notificación

**Al confirmarse una reserva:**
```
🌿 Nueva reserva — Vita Delta

Cabaña: {nombre_cabana}
Checkin: {fecha_checkin} a las {hora_checkin}hs
Checkout: {fecha_checkout} a las {hora_checkout}hs
Personas: {personas}

Por favor prepará la cabaña el día anterior al checkin.
```

**Al registrarse el checkout:**
```
🧹 Checkout realizado — Vita Delta

Cabaña: {nombre_cabana}
El huésped hizo checkout hoy a las {hora_checkout}hs.

Por favor coordiná la limpieza para dejarla lista.
{nota_proxima_reserva}
```

La variable `{nota_proxima_reserva}` incluye, si existe, la información del próximo checkin en esa cabaña: "⚡ La próxima reserva entra el {fecha} a las {hora}hs."

### 18.3 Número de Jennifer

Configurado en CONFIGURACION_GENERAL como `whatsapp_jennifer`. Si aún no existe, debe agregarse a CONFIGURACION_GENERAL.

---

## 19. ASIGNACIÓN DEL ENCARGADO SEMANAL FRANCO/RODRIGO

### 19.1 Lógica del ciclo

El encargado de semana alterna entre Franco y Rodrigo en ciclos semanales (lunes a domingo). La configuración de inicio del ciclo ya existe en CONFIGURACION_GENERAL:

| Clave | Valor actual |
|---|---|
| `encargado_ciclo_inicio_fecha` | 2026-05-11 |
| `encargado_ciclo_inicio_nombre` | Franco |

### 19.2 Algoritmo de asignación

```
FUNCIÓN calcular_encargado(fecha_checkin):
  dias_desde_inicio = dias_entre(encargado_ciclo_inicio_fecha, fecha_checkin)
  semanas = FLOOR(dias_desde_inicio / 7)

  SI semanas MOD 2 = 0:
    RETORNAR encargado_ciclo_inicio_nombre  (Franco en semanas pares)
  SINO:
    RETORNAR el_otro_socio                  (Rodrigo en semanas impares)
```

La semana se asigna según la fecha de checkin. Si la reserva cruza el cambio de semana, el encargado es el de la semana del checkin.

### 19.3 Registro

El encargado calculado se guarda en `RESERVAS.encargado_semana` al crear la reserva. Aparece en:
- El mensaje al grupo operativo de confirmación
- El evento del calendario visual
- El mensaje a Jennifer (para que sepa a quién contactar si hay algo)

---

## 20. CANCELACIONES Y MODIFICACIONES POST-CONFIRMACIÓN

### 20.1 Principio para esta etapa

Las cancelaciones y modificaciones post-confirmación requieren intervención humana. El bot puede recibir y estructurar la solicitud del cliente, pero no ejecuta la cancelación automáticamente.

### 20.2 Flujo de cancelación solicitada por el cliente

```
[Cliente solicita cancelación por WhatsApp/Instagram]
        │
        ▼
[Bot recibe y estructura la solicitud]
[Bot responde: "Recibimos tu solicitud. La vamos a revisar y te confirmamos
 en breve. Un momento."]
        │
        ▼
[n8n notifica a Vicky y Franco]
Mensaje: "⚠️ Solicitud de cancelación
  Reserva: [ID] | Cabaña: [nombre]
  Huésped: [nombre] | Fechas: [fechas]
  Canal: WhatsApp/Instagram
  Motivo indicado: [texto del cliente si lo dio]"
        │
        ▼
[Vicky o Franco evalúan]
        │
        ├── Sin cargo → Vicky usa formulario interno:
        │     → Acción: Cancelar sin cargo
        │     → n8n ejecuta db_cancelar_reserva(tipo='sin_cargo')
        │
        └── Con cargo → Franco evalúa monto de retención:
              → n8n ejecuta db_cancelar_reserva(tipo='con_cargo', monto_retencion=X)
```

### 20.3 Workflow: db_cancelar_reserva

```
WORKFLOW: db_cancelar_reserva
CONCURRENCIA: 1

INPUT: { id_reserva, tipo_cancelacion, monto_retencion, cancelado_por, source_event }

PASO 1: Verificar estado de RESERVA (debe ser 'confirmada' o 'activa')
PASO 2: Cambiar estado RESERVA → 'cancelada' o 'cancelada_con_cargo'
PASO 3: Si hay PAGO confirmado y tipo = 'sin_cargo':
          Registrar PAGO de reembolso (tipo='reembolso', estado='pendiente')
          Nota: el reembolso real lo procesa Vicky/Franco manualmente
PASO 4: Si tipo = 'con_cargo':
          Registrar PAGO de reembolso parcial (monto = pagado - monto_retencion)
PASO 5: Recalcular DISPONIBILIDAD_CACHE para las fechas afectadas
PASO 6: Notificar al huésped: "Tu reserva fue cancelada. {detalle_reembolso}"
PASO 7: Notificar al equipo
PASO 8: Notificar a Jennifer si el checkin era en los próximos 7 días
PASO 9: Registrar en LOG_CAMBIOS
```

### 20.4 Modificaciones de fechas

En esta etapa, cualquier modificación de fechas se trata como:
1. Cancelación de la reserva original
2. Nueva reserva con las fechas modificadas

No hay workflow de "modificar reserva" directamente. Esto simplifica la lógica y evita casos complejos de diferencia de precio, disponibilidad parcial, etc. En una etapa futura puede incorporarse un flujo de modificación directa.

**Trazabilidad entre reservas:** Al crear la nueva reserva, se registra en `RESERVAS.notas` la referencia a la reserva original con el formato `modificacion_de:#ID_RESERVA_ORIGINAL`. Al cancelar la original, se registra en su `notas` la referencia a la nueva con el formato `reemplazada_por:#ID_NUEVA_RESERVA`. Ambos registros quedan también en LOG_CAMBIOS con el mismo `source_event` para poder reconstruir la cadena completa de modificaciones.

---

## 21. CONFLICTOS Y RESOLUCIÓN MANUAL

### 21.1 Qué dispara un conflicto

- Race condition: dos pagos simultáneos para la misma cabaña y fechas
- Pago llegó después del vencimiento de la PRE_RESERVA
- Error de sincronización detectado en recálculo masivo
- Bloqueo creado sobre PRE_RESERVA activa (ya definido en Etapa 2)

### 21.2 Estado `conflicto_pendiente`

Cuando n8n detecta cualquiera de las situaciones anteriores:

1. La entidad afectada (PRE_RESERVA o RESERVA) pasa a `conflicto_pendiente`
2. El PAGO queda en `pendiente` (no se confirma ni rechaza automáticamente)
3. Se registra en LOG_CAMBIOS con nivel `error` y todos los detalles:
   - IDs involucrados
   - Timestamps
   - Estado en el que se encontraron las entidades
   - source_event de cada una
4. Notificación inmediata a Franco y Vicky por WhatsApp

### 21.3 Opciones de resolución manual

Una vez que el equipo revisa el conflicto:

| Opción | Cuándo | Acción |
|---|---|---|
| Confirmar el primer pago | El primero fue el válido | Franco/Vicky ejecutan db_confirmar_reserva manualmente |
| Cancelar y reembolsar | Ambos pagos llegaron pero hay error | Cancelar ambas pre-reservas, registrar reembolsos |
| Reasignar a otra cabaña | Hay disponibilidad en otra | Con acuerdo del cliente, crear nueva reserva en otra cabaña |
| Escalar a caso especial | Situación no contemplada | Franco decide y registra manualmente en LOG_CAMBIOS |

### 21.4 Resolución del estado

Una vez resuelta, el equipo actualiza el estado de la entidad desde el formulario interno o directamente en Sheets. n8n recalcula la disponibilidad afectada al detectar el cambio de estado.

---

## 22. SOURCE_EVENT POR ACCIÓN

Tabla completa de valores de `source_event` para esta etapa. Se agrega a los valores ya definidos en Etapa 1.

| Valor | Descripción |
|---|---|
| `bot_whatsapp` | Acción iniciada por bot en WhatsApp (ya existía) |
| `bot_instagram` | Acción iniciada por bot en Instagram (ya existía) |
| `web_publica` | Acción desde la web de reservas (ya existía) |
| `admin_manual` | Acción manual de un socio (ya existía) |
| `vicky_form` | Vicky completó el formulario interno (ya existía) |
| `webhook_mp` | Webhook automático de MercadoPago (ya existía) |
| `n8n_scheduled` | Proceso automático programado (ya existía) |
| `sistema_expiracion` | Vencimiento automático de PRE_RESERVA (ya existía) |
| `sistema_correccion` | Corrección de inconsistencia (ya existía) |
| `sistema_revalidacion` | Revalidación de disponibilidad en db_confirmar_reserva |
| `vicky_validacion_pago` | Vicky aprobó un comprobante manualmente |
| `franco_validacion_pago` | Franco aprobó un comprobante manualmente |
| `vicky_cancelacion` | Vicky ejecutó cancelación desde formulario |
| `franco_cancelacion` | Franco ejecutó cancelación |
| `sistema_conflicto` | n8n detectó conflicto automáticamente |
| `franco_resolucion_conflicto` | Franco resolvió un conflicto manualmente |

---

## 23. WORKFLOWS INTERNOS N8N

### 23.1 Catálogo completo de workflows de Etapa 4A

| Workflow | Concurrencia | Descripción |
|---|---|---|
| `db_crear_prereserva` | 1 | Crea PRE_RESERVA, actualiza disponibilidad, inicia timer |
| `db_confirmar_reserva` | 1 | Revalida y convierte PRE_RESERVA en RESERVA |
| `db_cancelar_reserva` | 1 | Cancela RESERVA, libera disponibilidad, registra reembolso |
| `db_registrar_pago` | 1 | Registra un PAGO (manual o automático) |
| `sistema_expirar_prereservas` | schedule (5 min) | Detecta y vence PRE_RESERVAS expiradas |
| `recibir_webhook_mp` | — | Recibe y procesa webhook de MercadoPago |
| `generar_link_mp` | — | Genera preference en MP y devuelve link |
| `enviar_mensaje_huesped` | — | Envía mensaje al huésped por WhatsApp/Instagram |
| `enviar_mensaje_equipo` | — | Envía mensaje al grupo operativo |
| `enviar_mensaje_jennifer` | — | Envía mensaje a Jennifer por WhatsApp |
| `db_recalcular_disponibilidad` | 1 | Recalcula DISPONIBILIDAD_CACHE (ya definido Etapa 2) |
| `actualizar_calendario_visual` | — | Crea/modifica evento en Google Calendar |
| `calcular_encargado_semana` | — | Función auxiliar, retorna encargado para una fecha |
| `procesar_solicitud_cancelacion` | — | Recibe solicitud del cliente y notifica al equipo |

### 23.2 Esquema de inputs/outputs de los workflows críticos

**db_crear_prereserva**
```
INPUT:
  id_consulta, id_cabana, id_huesped, fecha_in, fecha_out,
  hora_checkin, hora_checkout, personas, monto_total, monto_sena,
  canal_pago_esperado, source_event

OUTPUT:
  { ok: true, id_prereserva, expira_en }
  { error: 'disponibilidad_cambio', motivo }
  { error: 'cabaña_inactiva' }
```

**db_confirmar_reserva**
```
INPUT:
  id_prereserva, id_pago, validado_por, source_event

OUTPUT:
  { ok: true, id_reserva }
  { error: 'prereserva_vencida' }
  { error: 'conflicto_disponibilidad' }
  { error: 'estado_inesperado', estado_actual }
  { ok: true, nota: 'ya_confirmada' }
```

**db_cancelar_reserva**
```
INPUT:
  id_reserva, tipo_cancelacion, monto_retencion (opcional),
  cancelado_por, source_event

OUTPUT:
  { ok: true }
  { error: 'estado_invalido_para_cancelar', estado_actual }
```

**db_registrar_pago**
```
INPUT:
  id_prereserva, tipo, medio_pago, proveedor, cuenta_destino,
  monto_esperado, monto_recibido, moneda, comprobante_url,
  referencia_externa, tx_hash, validado_por, source_event

OUTPUT:
  { ok: true, id_pago }
  { error: 'prereserva_no_encontrada' }
```

---

## 24. EDGE CASES

### Edge case 1 — PRE_RESERVA expira mientras el cliente está en el proceso de pago

**Situación:** El cliente tiene el link de MP abierto. La PRE_RESERVA vence a las 14:00. El cliente toca "Pagar" a las 14:01.

**Comportamiento:**
- El link de MP ya venció (configurado con `expiration_date_to`)
- MP no procesa el pago y devuelve error al cliente
- No llega webhook a n8n
- La PRE_RESERVA ya fue marcada como `vencida` por `sistema_expirar_prereservas`
- El cliente ve error en MP y contacta al bot
- Bot verifica disponibilidad: si sigue libre, ofrece crear nueva PRE_RESERVA

**Resultado:** Sin double booking. Sin pago perdido. El cliente puede reintentar si la cabaña sigue disponible.

---

### Edge case 2 — Pago llega después del vencimiento (webhook tardío de MP)

**Situación:** El webhook de MP tiene delay y llega 5 minutos después de que la PRE_RESERVA venció.

**Comportamiento:**
- `sistema_expirar_prereservas` ya marcó la PRE_RESERVA como `vencida`
- El webhook llega → `recibir_webhook_mp` llama a `db_confirmar_reserva`
- `db_confirmar_reserva` Paso 1: encuentra PRE_RESERVA en estado `vencida`
- Notificación inmediata a Franco: "Pago recibido pero PRE_RESERVA ya venció"
- PAGO se registra en estado `rechazado` con motivo `prereserva_vencida`
- El equipo evalúa: si la cabaña sigue disponible, puede crear la reserva manualmente y confirmar el pago

**Resultado:** El pago del cliente no se pierde. Requiere intervención humana.

---

### Edge case 3 — Doble tap en MercadoPago (dos webhooks del mismo pago)

**Situación:** MP envía el webhook dos veces por la misma transacción (comportamiento documentado de MP).

**Comportamiento:**
- Primer webhook: `recibir_webhook_mp` procesa, `db_confirmar_reserva` confirma la reserva
- Segundo webhook: `recibir_webhook_mp` busca PAGO por `referencia_externa`
- Encuentra PAGO ya en estado `confirmado`
- `db_confirmar_reserva` Paso 1: PRE_RESERVA ya en estado `convertida`
- Retorna `{ ok: true, nota: 'ya_confirmada' }` → no hace nada
- Se registra en LOG_CAMBIOS como webhook duplicado

**Resultado:** Idempotencia garantizada. La reserva no se duplica.

---

### Edge case 4 — Pago confirmado pero disponibilidad cambió entre el pago y la confirmación

**Situación:** Entre que el cliente pagó y que el webhook llegó a n8n, otra reserva (manual de Vicky) ocupó las mismas fechas.

**Comportamiento:**
- `db_confirmar_reserva` Paso 2: encuentra reserva confirmada para esas fechas
- Conflicto detectado → PRE_RESERVA → `conflicto_pendiente`
- Notificación urgente a Franco y Vicky con todos los detalles
- PAGO queda en `pendiente` (el cliente pagó, no se le rechaza automáticamente)
- El equipo resuelve: reasigna a otra cabaña o coordina reembolso

**Resultado:** Double booking prevenido. El cliente no pierde su dinero sin atención humana.

---

### Edge case 5 — Comprobante apócrifo validado por error

**Situación:** Vicky aprueba un comprobante que resulta ser falso o de otro cliente.

**Comportamiento:**
- La reserva se confirma normalmente
- El error se detecta después (auditoría de banco, reclamo del cliente real, etc.)
- Franco cancela la reserva manualmente (`db_cancelar_reserva`)
- Se registra en LOG_CAMBIOS con nota detallada
- El PAGO queda en estado `rechazado` con motivo `comprobante_invalido`
- Si hay que reembolsar: se registra PAGO de tipo `reembolso`

**Mitigación:** El formulario de validación manual incluye campos obligatorios (monto, referencia, cuenta) que hacen más difícil aprobar sin verificar. No elimina el riesgo pero lo reduce.

---

### Edge case 6 — Cancelación solicitada después del check-in

**Situación:** Un huésped ya está en la cabaña y pide cancelar (abandona la estadía).

**Comportamiento:**
- Bot recibe la solicitud y avisa al equipo
- Franco evalúa: la reserva está en estado `activa`
- `db_cancelar_reserva` acepta `activa` como estado válido para cancelar
- Se calcula el cargo según política (configurable: puede ser el saldo total o una fracción)
- Jennifer es notificada para preparar la cabaña si hay otra reserva entrante

**Resultado:** El flujo maneja el caso aunque es atípico.

---

### Edge case 7 — Jennifer no está disponible cuando llega la notificación

**Situación:** El mensaje a Jennifer falla (WhatsApp no disponible, número incorrecto, etc.).

**Comportamiento:**
- n8n detecta el error de envío (timeout o error de la API)
- Registra el fallo en LOG_CAMBIOS
- Notifica a Franco/Rodrigo: "No pude notificar a Jennifer para la reserva [ID]. Coordinar manualmente."
- No reintenta automáticamente (para evitar spam si el número está mal)

---

### Edge case 8 — Checkout tardío no registrado

**Situación:** El huésped hizo checkout pero nadie lo registró en el sistema. La cabaña aparece como `activa` (ocupada) aunque está vacía.

**Comportamiento actual:** El recálculo masivo nocturno no resuelve este caso por sí solo porque RESERVAS tiene la reserva en `activa` hasta que alguien la cambie.

**Mitigación en esta etapa:** El mensaje a Jennifer al día del checkout incluye hora esperada. Si pasó la hora de checkout y la reserva sigue `activa`, n8n puede enviar un recordatorio al encargado de semana para que registre el checkout.

**Configuración:**
| Clave | Valor default | Descripción |
|---|---|---|
| `checkout_recordatorio_horas_despues` | 2 | Horas después del checkout sin registrar para enviar recordatorio |

---

### Edge case 9 — Monto recibido difiere del monto esperado

**Situación:** El cliente transfirió $174.000 en vez de $175.000 (redondeo, error, o envío de otra cuenta con comisión).

**Comportamiento:**
- Vicky detecta la diferencia al validar el comprobante
- Si la diferencia es menor al umbral configurable (`diferencia_pago_tolerancia`, default: $5.000): puede aprobar igualmente y registrar la diferencia en `notas`
- Si la diferencia supera el umbral: debe consultar a Franco antes de aprobar
- El PAGO se registra con `monto_esperado` y `monto_recibido` distintos para trazabilidad

---

## 25. PENDIENTES PARA ETAPA 4B

La Etapa 4B diseña el Bot Conversacional con IA. Lo que esta etapa deja listo para que el bot se apoye:

### Contratos de API definidos

Los workflows internos de n8n tienen inputs y outputs documentados (Sección 23). El bot de Etapa 4B llama a estos workflows; no necesita saber cómo funcionan por dentro.

### Estados que el bot debe conocer

- Estados de CONSULTAS (Sección 4): el bot los lee y los actualiza a través de n8n
- Estados de PRE_RESERVAS (Sección 5): el bot lee el estado para informar al cliente
- Estados de RESERVAS (Sección 6): el bot puede consultar el estado de una reserva activa
- Estados de PAGOS (Sección 7): el bot informa al cliente sobre el estado de su pago

### Decisiones de arquitectura que el bot hereda

- El bot NO ejecuta `db_confirmar_reserva`. Solo llama a `db_crear_prereserva` y luego espera el resultado del flujo de pago.
- El bot NO valida pagos. Solo comunica instrucciones y estado.
- El bot SÍ puede llamar a `procesar_solicitud_cancelacion` para estructurar y escalar una solicitud.
- El bot SÍ puede consultar DISPONIBILIDAD_CACHE para responder preguntas de disponibilidad.
- El bot SÍ puede llamar al Motor de Precios (Etapa 3) para cotizar.

### Preguntas abiertas que debe resolver Etapa 4B

- [ ] Cómo el bot gestiona el contexto conversacional entre múltiples mensajes (estructura de `contexto_json` en CONSULTAS)
- [ ] Cuándo el bot llama a Claude API vs cuándo responde con plantillas fijas (FAQ sin IA)
- [ ] Reglas de derivación a Vicky/Franco/Rodrigo
- [ ] Tono, personalidad y límites del bot
- [ ] Cómo el bot presenta el desglose de precios al cliente
- [ ] Manejo de eventos especiales (Año Nuevo, etc.) en el flujo conversacional
- [ ] Prompt caching y estrategia de reducción de tokens
- [ ] Seguridad: qué información puede el bot revelar y qué no
- [ ] Formato del handoff a humano

---

*Documento generado como parte del proceso de diseño del sistema Complejo Vita Delta.*
*Siguiente: ARQUITECTURA_ETAPA_4B_BOT_CONVERSACIONAL.md — Bot Conversacional con IA*
