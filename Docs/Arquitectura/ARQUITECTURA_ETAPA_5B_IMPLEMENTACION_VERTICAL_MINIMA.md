# ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md
# Implementación Vertical Mínima

**Versión:** 1.1
**Fecha:** Mayo 2026
**Estado:** Aprobado — CERRADO
**Depende de:** ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md v1.1 y todas las etapas anteriores
**Autores:** Franco (titular) + Claude (arquitecto)

---

## ÍNDICE

1. Objetivo de esta etapa
2. Alcance exacto del primer slice vertical
3. Qué queda explícitamente fuera
4. Estado mínimo del Google Sheets para arrancar
5. Separación de entornos: DEV / TEST / PROD
6. Fuentes de verdad y consistencia
7. Workflows a implementar — catálogo mínimo
8. Workflow: db_crear_consulta
9. Workflow: db_crear_prereserva
10. Workflow: db_confirmar_reserva
11. Workflow: db_registrar_pago
12. Workflow: db_recalcular_disponibilidad
13. Workflow: sistema_expirar_prereservas
14. Validación previa a escrituras críticas
15. Estrategia de idempotencia
16. Estrategia de locking lógico
17. Manejo de race conditions
18. Qué acciones siguen siendo manuales
19. Formulario interno mínimo de Vicky
20. Logging mínimo
21. Estrategia de rollback y recuperación
22. Casos de prueba del primer flujo
23. Protocolo de prueba
24. Criterio de éxito
25. Pendientes para etapas siguientes

---

## 1. OBJETIVO DE ESTA ETAPA

Construir y probar el corazón transaccional mínimo del sistema: el flujo completo desde una consulta hasta una reserva confirmada, con disponibilidad actualizada y auditoría completa, sin depender de ningún canal externo.

El objetivo no es automatizar todo. Es demostrar que la arquitectura diseñada en las Etapas 1 a 5A funciona de forma real, consistente y auditable cuando se ejecuta sobre datos reales.

> **Definición de "operativo":** el sistema es operativo cuando puede procesar un flujo completo `CONSULTA → PRE_RESERVA → PAGO manual → RESERVA confirmada → DISPONIBILIDAD_CACHE actualizada → LOG_CAMBIOS` sin intervención técnica, sin double booking y sin pérdida de datos, incluso ante reintentos, fallos parciales o ejecuciones concurrentes.

### Por qué construir esto antes de conectar canales externos

Conectar WhatsApp, Instagram o MercadoPago sobre un sistema transaccional no probado genera deuda técnica difícil de depurar. Los errores en producción con clientes reales son costosos. Este slice vertical permite:

- Validar que los workflows funcionan correctamente
- Verificar que el locking lógico previene double bookings
- Confirmar que LOG_CAMBIOS es útil para debugging
- Entrenar a Vicky en el flujo antes de que lleguen clientes reales
- Detectar edge cases antes de exponerlos al público

---

## 2. ALCANCE EXACTO DEL PRIMER SLICE VERTICAL

### El flujo completo a implementar

```
[Franco o Vicky crea una CONSULTA manualmente o via formulario]
        │
        ▼
[db_crear_consulta]
  → Escribe en CONSULTAS
  → Registra en LOG_CAMBIOS
        │
        ▼
[Franco o Vicky crea una PRE_RESERVA via formulario]
        │
        ▼
[db_crear_prereserva]
  → Valida disponibilidad en DISPONIBILIDAD_CACHE
  → Valida que no existe PRE_RESERVA activa para (cabaña, fechas)
  → Escribe en PRE_RESERVAS
  → Actualiza DISPONIBILIDAD_CACHE → estado 'ocupada'
  → Registra en LOG_CAMBIOS
        │
        ▼
[Cliente transfiere. Vicky valida el comprobante via Google Form]
        │
        ▼
[db_registrar_pago]
  → Escribe en PAGOS con estado 'en_revision'
  → Registra en LOG_CAMBIOS
        │
        ▼
[Vicky aprueba el pago via Google Form]
        │
        ▼
[db_confirmar_reserva]  ← WORKFLOW CRÍTICO
  → Recheck de disponibilidad (segunda verificación)
  → Locking lógico (concurrencia = 1)
  → PRE_RESERVA → 'convertida'
  → Crea RESERVA en estado 'confirmada'
  → PAGO → 'confirmado'
  → Llama a db_recalcular_disponibilidad
  → Notificación mínima al equipo (WhatsApp manual o log visible)
  → Registra en LOG_CAMBIOS
        │
        ▼
[db_recalcular_disponibilidad]
  → Actualiza DISPONIBILIDAD_CACHE para fechas afectadas ± 2 días
  → Registra en LOG_CAMBIOS
```

### Qué está en scope

- Creación manual de CONSULTAS (via formulario o directamente en Sheets en DEV)
- Creación de PRE_RESERVAS con validación de disponibilidad
- Registro de pagos manuales (transferencia bancaria)
- Validación de comprobante por Vicky via Google Form
- Confirmación de reserva con recheck de disponibilidad
- Recálculo parcial de DISPONIBILIDAD_CACHE
- Expiración automática de PRE_RESERVAS vencidas
- LOG_CAMBIOS completo para todo lo anterior

---

## 3. QUÉ QUEDA EXPLÍCITAMENTE FUERA

Esta lista es cerrada. Nada de lo siguiente se toca en esta etapa.

| Qué | Por qué se difiere |
|---|---|
| WhatsApp Cloud API | Requiere número Business dedicado y configuración Meta |
| Instagram Graph API | Ídem |
| Claude API / bot conversacional | El flujo transaccional debe estar probado primero |
| MercadoPago automático (webhook) | La validación manual prueba el mismo flujo de fondo |
| Frontend web | El flujo se activa manualmente en esta etapa |
| Escalonamiento de horarios | Simplifica las pruebas; los horarios se cargan manualmente |
| Descuentos | DESCUENTOS existe en el Sheets pero no participa del flujo |
| Eventos especiales (Año Nuevo) | Los paquetes sin precio no pueden confirmarse |
| Cancelaciones automáticas | Las cancelaciones son manuales en esta etapa |
| Recálculo masivo nocturno | Solo recálculo parcial por evento |
| Contabilidad y distribución entre socios | Etapa posterior |
| Coordinación automática con Jennifer | Mensaje manual en esta etapa |
| Google Calendar como vista secundaria | La vista operativa es el Sheets |
| Múltiples medios de pago | Solo transferencia bancaria en esta etapa |

---

## 4. ESTADO MÍNIMO DEL GOOGLE SHEETS PARA ARRANCAR

Antes de ejecutar el primer flujo, el Sheets de TEST debe tener estos datos cargados:

### Hojas con datos obligatorios

| Hoja | Datos mínimos requeridos |
|---|---|
| CABAÑAS | Las 5 cabañas reales (Sección 5 de Etapa 5A) |
| TARIFAS | Al menos los conceptos `finde_completo`, `semana_1`, `semana_completa` para `grande` y `chica` |
| TEMPORADAS | Al menos la temporada vigente con su multiplicador |
| CONFIGURACION_GENERAL | Todas las claves de Etapa 5A, Sección 19, más la clave nueva `prereserva_pago_en_revision_alerta_horas` = `2` |
| CUENTAS_COBRO | Al menos una cuenta activa de tipo `transferencia_bancaria` |
| PLANTILLAS_MENSAJES | Al menos `nueva_reserva_equipo` y `prereserva_creada` |

### Hojas que deben existir pero pueden estar vacías

CONSULTAS, PRE_RESERVAS, RESERVAS, PAGOS, BLOQUEOS, OVERRIDES_OPERATIVOS, LOG_CAMBIOS, HUÉSPEDES, FERIADOS, EVENTOS_ESPECIALES, PAQUETES_EVENTO, DESCUENTOS, GASTOS.

### Hojas que se pueblan automáticamente al ejecutar el flujo

DISPONIBILIDAD_CACHE (el primer recálculo masivo la genera), LOG_CAMBIOS (cada workflow escribe).

### Acción previa obligatoria: poblar DISPONIBILIDAD_CACHE

Antes de la primera prueba, ejecutar manualmente el workflow `db_recalcular_disponibilidad` con scope total (todas las cabañas, próximos 60 días). Esto genera la base de la cache sobre la que opera el flujo.

---

## 5. SEPARACIÓN DE ENTORNOS: DEV / TEST / PROD

### 5.1 Tres Google Sheets completamente separados

| Entorno | Nombre del Sheets | Propósito |
|---|---|---|
| DEV | `VITA_DELTA_DEV` | Desarrollo y experimentación. Datos ficticios. Se puede romper. |
| TEST | `VITA_DELTA_TEST` | Pruebas controladas del flujo completo. Datos de prueba realistas. |
| PROD | `VITA_DELTA_PROD` | Producción real. Solo se activa cuando TEST está validado. |

**Regla absoluta:** Nunca ejecutar pruebas sobre PROD. Nunca copiar datos de PROD a DEV sin anonimizarlos. Nunca apuntar un workflow de DEV o TEST a la Sheet ID de PROD.

### 5.2 Parametrización por entorno en n8n

Cada workflow lee el entorno activo desde una variable de entorno de n8n, nunca desde un valor hardcodeado.

**Variables de entorno a configurar en n8n:**

| Variable | DEV | TEST | PROD |
|---|---|---|---|
| `ENTORNO` | `dev` | `test` | `prod` |
| `SHEETS_ID` | ID del Sheets DEV | ID del Sheets TEST | ID del Sheets PROD |
| `SHEETS_URL_BASE` | URL base DEV | URL base TEST | URL base PROD |
| `WEBHOOK_BASE_URL` | URL webhook DEV | URL webhook TEST | URL webhook PROD |
| `NOTIF_WHATSAPP_EQUIPO` | Número de prueba | Número de prueba | Número real del equipo |
| `LOG_NIVEL_MINIMO` | `info` | `info` | `warning` |

### 5.3 Cómo los workflows usan las variables

```javascript
// Patrón estándar en todos los workflows — primer nodo siempre:

const entorno = $env.ENTORNO  // 'dev', 'test' o 'prod'
const sheetsId = $env.SHEETS_ID

// Nunca esto:
const sheetsId = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms"  // ❌ hardcoded

// Siempre esto:
const sheetsId = $env.SHEETS_ID  // ✅ parametrizado
```

### 5.4 Ciclo de promoción entre entornos

```
DEV → (pruebas unitarias de cada workflow)
    → TEST → (prueba del flujo completo, casos de prueba de Sección 22)
           → PROD → (flujo real con datos de clientes reales)
```

Un workflow solo se promueve a TEST cuando funciona correctamente en DEV. Solo se promueve a PROD cuando todos los casos de prueba de TEST pasan. La promoción es manual y documentada en LOG_CAMBIOS con `source_event = 'deploy_manual'`.

### 5.5 En esta etapa

Solo se implementan DEV y TEST. PROD queda creado (el Sheets existe con estructura completa) pero sin activar workflows. Los workflows apuntan a TEST para validación final.

---

## 6. FUENTES DE VERDAD Y CONSISTENCIA

### 6.1 Jerarquía de fuentes de verdad

```
NIVEL 1 — Fuente primaria absoluta
  RESERVAS: es la fuente final de verdad del sistema.
  En caso de cualquier conflicto entre entidades, RESERVAS prevalece.

NIVEL 2 — Fuentes primarias operativas
  PRE_RESERVAS: verdad temporal. Bloquea disponibilidad mientras está activa.
  PAGOS: verdad de transacciones económicas. No depende de otros estados.
  BLOQUEOS: verdad de impedimentos manuales.

NIVEL 3 — Fuente de configuración con override
  OVERRIDES_OPERATIVOS: modifica el comportamiento del motor para fechas
  específicas. Tiene prioridad sobre CONFIGURACION_GENERAL pero no sobre
  RESERVAS ni PRE_RESERVAS.

NIVEL 4 — Fuente derivada (nunca fuente de verdad)
  DISPONIBILIDAD_CACHE: refleja el estado calculado a partir de los niveles
  anteriores. Nunca se usa para resolver conflictos. Si hay inconsistencia
  entre la cache y RESERVAS, siempre gana RESERVAS.
```

### 6.2 Prioridades por entidad

| Entidad | Categoría | Prevalece sobre | Puede ser sobreescrita por |
|---|---|---|---|
| RESERVAS | Fuente primaria absoluta | Todo | Solo corrección manual documentada en LOG_CAMBIOS |
| PRE_RESERVAS | Fuente primaria temporal | DISPONIBILIDAD_CACHE | RESERVAS, BLOQUEOS |
| PAGOS | Fuente primaria de transacciones | — | Solo corrección manual documentada |
| BLOQUEOS | Fuente primaria operativa | PRE_RESERVAS, DISPONIBILIDAD_CACHE | RESERVAS |
| OVERRIDES_OPERATIVOS | Fuente de configuración | CONFIGURACION_GENERAL | RESERVAS, PRE_RESERVAS, BLOQUEOS |
| CONFIGURACION_GENERAL | Fuente de parámetros base | — | OVERRIDES_OPERATIVOS |
| DISPONIBILIDAD_CACHE | Derivada | — | Todo (se recalcula desde las fuentes) |

### 6.3 Resolución de conflictos entre entidades

**Conflicto RESERVAS vs DISPONIBILIDAD_CACHE:**
RESERVAS gana siempre. Si la cache dice `disponible` pero existe una RESERVA confirmada para esa (cabaña, fecha), la cache está desactualizada. n8n recalcula. No se cancela la reserva.

**Conflicto PRE_RESERVAS vs DISPONIBILIDAD_CACHE:**
PRE_RESERVA gana. Si existe una PRE_RESERVA en estado `pendiente_pago`, la cache debe mostrar `ocupada`. Si no lo hace, hay inconsistencia → recalcular cache.

**Conflicto dos PRE_RESERVAS para la misma (cabaña, fechas):**
Imposible en condiciones normales gracias al locking lógico. Si ocurre (falla técnica), prevalece la de menor `id_prereserva` (la más antigua). La más reciente pasa a `conflicto_pendiente`. Notificación inmediata al equipo.

**Conflicto PAGOS vs estado de PRE_RESERVA:**
Un PAGO en estado `confirmado` asociado a una PRE_RESERVA en estado `vencida` es un conflicto real (el cliente pagó tarde). No se resuelve automáticamente. Notificación al equipo. El equipo decide.

**Conflicto BLOQUEOS vs PRE_RESERVA activa:**
BLOQUEO gana operativamente (la cabaña no está disponible), pero la PRE_RESERVA no se cancela automáticamente. n8n notifica al equipo para resolución manual. La PRE_RESERVA pasa a `cancelada_por_bloqueo` solo cuando el equipo lo confirma.

**Conflicto OVERRIDES_OPERATIVOS solapados:**
El override más específico (cabaña específica > todas las cabañas) tiene prioridad. Si el nivel de especificidad es igual, el override con mayor `id_override` (más reciente) gana. Se registra el conflicto en LOG_CAMBIOS con nivel `warning`.

### 6.4 Regla de reconstrucción

Si DISPONIBILIDAD_CACHE está corrupta o desactualizada, el sistema puede reconstruirla completamente desde cero leyendo en orden:
1. CABAÑAS (qué cabañas existen y están activas)
2. BLOQUEOS (qué fechas están bloqueadas)
3. RESERVAS (qué fechas están confirmadas)
4. PRE_RESERVAS (qué fechas están en proceso)
5. OVERRIDES_OPERATIVOS (qué reglas especiales aplican)
6. CONFIGURACION_GENERAL (parámetros base)

Esta reconstrucción es lo que hace el recálculo masivo nocturno. En esta etapa se ejecuta manualmente cuando sea necesario.

---

## 7. WORKFLOWS A IMPLEMENTAR — CATÁLOGO MÍNIMO

### 7.1 Lista y orden de implementación

| Orden | Workflow | Concurrencia | Disparador |
|---|---|---|---|
| 1 | `db_recalcular_disponibilidad` | 1 | Llamado por otros workflows o manualmente |
| 2 | `db_crear_consulta` | — | Webhook desde formulario o llamada directa |
| 3 | `db_crear_prereserva` | 1 | Webhook desde formulario |
| 4 | `db_registrar_pago` | 1 | Webhook desde formulario de Vicky |
| 5 | `db_confirmar_reserva` | 1 | Webhook desde formulario de Vicky (aprobación) |
| 6 | `sistema_expirar_prereservas` | Schedule (5 min) | Cron automático |

**Por qué este orden:** `db_recalcular_disponibilidad` se implementa primero porque todos los demás workflows lo llaman. Sin cache poblada, nada puede validar disponibilidad.

### 7.2 Dependencias entre workflows

```
sistema_expirar_prereservas
    └── llama a → db_recalcular_disponibilidad

db_crear_prereserva
    └── llama a → db_recalcular_disponibilidad

db_confirmar_reserva
    ├── llama a → db_recalcular_disponibilidad
    └── verifica → db_registrar_pago (que el PAGO exista)

db_registrar_pago
    └── no llama a otros workflows (solo escribe y notifica)

db_crear_consulta
    └── no llama a otros workflows (solo escribe)
```

---

## 8. WORKFLOW: db_crear_consulta

**Concurrencia:** Sin restricción (las consultas no generan conflictos de disponibilidad)
**Disparador:** Webhook POST desde formulario interno o llamada directa en DEV

### Input
```json
{
  "canal": "whatsapp | instagram | web | manual",
  "id_contacto_externo": "string",
  "id_huesped": "integer | null",
  "fecha_in_tentativa": "YYYY-MM-DD | null",
  "fecha_out_tentativa": "YYYY-MM-DD | null",
  "personas_tentativa": "integer | null",
  "source_event": "string"
}
```

### Lógica

```
PASO 1 — Validar input
  → canal debe ser valor válido
  → id_contacto_externo no puede estar vacío
  → Si fechas presentes: fecha_out > fecha_in

PASO 2 — Verificar si existe CONSULTA activa para ese id_contacto_externo
  → Buscar en CONSULTAS WHERE id_contacto_externo = input.id_contacto_externo
    AND estado_conversacion NOT IN ('cerrada', 'derivada_a_humano')
  → Si existe: retornar la CONSULTA existente (no crear duplicado)
  → Si no existe: continuar

PASO 3 — Normalizar
  → Fechas a YYYY-MM-DD
  → id_contacto_externo: trim, lowercase si es email

PASO 4 — Escribir en CONSULTAS
  → Asignar id_consulta = max(id_consulta) + 1
  → estado_conversacion = 'inicio'
  → created_at = now()
  → updated_at = now()

PASO 5 — Escribir en LOG_CAMBIOS
  → tabla_afectada: CONSULTAS
  → id_registro: nuevo id_consulta
  → campo_modificado: estado_conversacion
  → valor_nuevo: inicio
  → nivel: info
```

### Output
```json
{
  "ok": true,
  "id_consulta": 1,
  "es_nueva": true
}
```
o si ya existía:
```json
{
  "ok": true,
  "id_consulta": 1,
  "es_nueva": false,
  "nota": "consulta_activa_existente"
}
```

---

## 9. WORKFLOW: db_crear_prereserva

**Concurrencia:** 1 (nunca en paralelo)
**Disparador:** Webhook POST desde formulario interno

### Input
```json
{
  "id_consulta": "integer",
  "id_cabana": "integer",
  "id_huesped": "integer",
  "fecha_in": "YYYY-MM-DD",
  "fecha_out": "YYYY-MM-DD",
  "hora_checkin": "HH:MM",
  "hora_checkout": "HH:MM",
  "personas": "integer",
  "canal_pago_esperado": "string",
  "canal_origen": "string",
  "source_event": "string"
}
```

### Lógica

```
PASO 1 — Validar input
  → Todos los campos obligatorios presentes
  → fecha_out > fecha_in
  → personas > 0 Y personas <= capacidad_max de la cabaña
  → id_cabana existe en CABAÑAS Y activa = TRUE Y bloqueada = FALSE
  → id_huesped existe en HUÉSPEDES
  → canal_pago_esperado es valor válido

PASO 2 — Verificar que no existe PRE_RESERVA activa para (id_cabana, fechas)
  → Buscar en PRE_RESERVAS WHERE id_cabana = input.id_cabana
    AND estado = 'pendiente_pago'
    AND fecha_in < input.fecha_out
    AND fecha_out > input.fecha_in
  → Si existe: RETORNAR { error: 'prereserva_activa_existente', id_prereserva_conflicto }

PASO 3 — Verificar disponibilidad en DISPONIBILIDAD_CACHE
  → Para cada fecha entre fecha_in y fecha_out - 1 día:
    → estado debe ser 'disponible' o 'checkout_disponible'
  → Si alguna fecha tiene estado 'ocupada' o 'bloqueada':
    → RETORNAR { error: 'fechas_no_disponibles', fechas_conflicto: [...] }

PASO 4 — Calcular precio
  → Llamar al motor de precios (Etapa 3) con (id_cabana, fecha_in, fecha_out, personas)
  → Si es evento especial con precio = 0: RETORNAR { error: 'paquete_sin_precio' }

PASO 5 — Calcular expira_en
  → expira_en = now() + prereserva_expiracion_minutos (de CONFIGURACION_GENERAL)

PASO 6 — Escribir en PRE_RESERVAS
  → id_prereserva = max(id_prereserva) + 1
  → estado = 'pendiente_pago'
  → intentos_pago = 0
  → created_at = now()
  → updated_at = now()

PASO 7 — Actualizar DISPONIBILIDAD_CACHE
  → Para cada fecha del rango: estado = 'ocupada', id_prereserva_activa = nuevo id
  → Llamar a db_recalcular_disponibilidad con scope mínimo (solo fechas afectadas)

PASO 8 — Actualizar CONSULTAS
  → estado_conversacion = 'esperando_pago'
  → updated_at = now()

PASO 9 — Escribir en LOG_CAMBIOS
  → nivel: info
  → detalle: { id_cabana, fecha_in, fecha_out, monto_sena }
```

### Output
```json
{
  "ok": true,
  "id_prereserva": 1,
  "expira_en": "2026-06-05T16:23:00Z",
  "monto_total": 350000,
  "monto_sena": 175000
}
```

### Idempotencia
Si se llama dos veces con el mismo `id_consulta` e `id_cabana` y las mismas fechas, el Paso 2 detecta la PRE_RESERVA existente y retorna `error: 'prereserva_activa_existente'`. No se crea un duplicado.

---

## 10. WORKFLOW: db_confirmar_reserva

**Concurrencia:** 1 — este es el workflow más crítico del sistema
**Disparador:** Webhook POST desde formulario de Vicky (aprobación de pago)

### Input
```json
{
  "id_prereserva": "integer",
  "id_pago": "integer",
  "validado_por": "string",
  "source_event": "string"
}
```

### Lógica

```
PASO 1 — Verificar estado de la PRE_RESERVA
  → Leer PRE_RESERVAS WHERE id = id_prereserva
  → SI estado = 'convertida':
      RETORNAR { ok: true, nota: 'ya_confirmada' }  // idempotencia
  → SI estado = 'vencida':
      RETORNAR { error: 'prereserva_vencida' }
  → SI estado = 'conflicto_pendiente':
      RETORNAR { error: 'conflicto_pendiente_requiere_resolucion_manual' }
  → SI estado != 'pendiente_pago':
      RETORNAR { error: 'estado_invalido', estado_actual }
  → Registrar timestamp de inicio de procesamiento en PRE_RESERVAS.notas
    (campo auxiliar: "procesando_desde: {timestamp}")

PASO 2 — Verificar que el PAGO existe y está en estado correcto
  → Leer PAGOS WHERE id = id_pago AND id_prereserva = id_prereserva
  → SI no existe: RETORNAR { error: 'pago_no_encontrado' }
  → SI estado = 'confirmado': RETORNAR { ok: true, nota: 'ya_confirmada' }  // idempotencia
  → SI estado NOT IN ('en_revision', 'pendiente'):
      RETORNAR { error: 'pago_en_estado_invalido', estado_pago }

PASO 3 — RECHECK de disponibilidad (segunda verificación, momento de confirmación)
  → Consultar RESERVAS WHERE id_cabana = prereserva.id_cabana
    AND estado IN ('confirmada', 'activa')
    AND fecha_checkin < prereserva.fecha_out
    AND fecha_checkout > prereserva.fecha_in
  → Si existe RESERVA conflictiva: ir a PASO CONFLICTO

  → Consultar PRE_RESERVAS WHERE id_cabana = prereserva.id_cabana
    AND estado = 'pendiente_pago'
    AND id != id_prereserva  // excluir la propia
    AND fecha_in < prereserva.fecha_out
    AND fecha_out > prereserva.fecha_in
  → Si existe otra PRE_RESERVA activa: ir a PASO CONFLICTO

  → Consultar BLOQUEOS WHERE (id_cabana = prereserva.id_cabana OR id_cabana IS NULL)
    AND activo = TRUE
    AND fecha_desde < prereserva.fecha_out
    AND fecha_hasta > prereserva.fecha_in
  // Detecta cualquier solapamiento parcial o total entre el bloqueo y el rango
  // de la reserva. La condición anterior (fecha_desde <= fecha_in AND fecha_hasta >= fecha_out)
  // solo detectaba bloqueos que cubrían el rango completo, dejando pasar
  // bloqueos que intersectaban parcialmente.
  → Si existe BLOQUEO: ir a PASO CONFLICTO

PASO CONFLICTO (si aplica):
  → PRE_RESERVA.estado = 'conflicto_pendiente'
  → PAGO.estado permanece en 'en_revision' (el cliente pagó, no rechazar automáticamente)
  → Registrar en LOG_CAMBIOS con nivel 'error' y todos los detalles
  → Notificar a Franco y Vicky: "⚠️ Conflicto al confirmar reserva ID {id_prereserva}"
  → RETORNAR { error: 'conflicto_disponibilidad' }

PASO 4 — Confirmar (disponibilidad verificada, sin conflicto)
  → PRE_RESERVA.estado = 'convertida'
  → PRE_RESERVA.updated_at = now()

PASO 5 — Crear RESERVA
  → id_reserva = max(id_reserva) + 1
  → Copiar datos de PRE_RESERVA a RESERVA
  → estado = 'confirmada'
  → encargado_semana = calcular_encargado(prereserva.fecha_in)
  → monto_saldo = monto_total - monto_sena
  → created_by = validado_por
  → created_at = now()
  → updated_at = now()

PASO 6 — Actualizar PAGO
  → PAGO.estado = 'confirmado'
  → PAGO.id_reserva = nuevo id_reserva
  → PAGO.validado_en = now()
  → PAGO.updated_at = now()

PASO 7 — Actualizar CONSULTA
  → CONSULTA.estado_conversacion = 'cerrada'
  → CONSULTA.updated_at = now()

PASO 8 — Recalcular disponibilidad
  → Llamar a db_recalcular_disponibilidad con:
    id_cabanas: [prereserva.id_cabana]
    fechas: rango fecha_in - 2 días hasta fecha_out + 2 días
    source_event: 'reserva_confirmada'

PASO 9 — Notificación mínima al equipo
  → Log visible en VISTA_PRERESERVAS_ACTIVAS
  → En esta etapa: entrada en LOG_CAMBIOS con nivel 'info' y mensaje completo
  → (WhatsApp real se activa en etapa posterior)

PASO 10 — Escribir en LOG_CAMBIOS
  → Un registro por cada entidad modificada:
    RESERVAS (creada), PRE_RESERVAS (convertida), PAGOS (confirmado), CONSULTAS (cerrada)
  → nivel: info
```

### Output
```json
{
  "ok": true,
  "id_reserva": 142,
  "encargado_semana": "Franco",
  "monto_saldo": 175000
}
```

### Idempotencia
El Paso 1 detecta si la PRE_RESERVA ya fue convertida y retorna `ok: true` sin volver a crear la RESERVA. El Paso 2 detecta si el PAGO ya fue confirmado. En ambos casos el workflow termina sin efecto secundario.

---

## 11. WORKFLOW: db_registrar_pago

**Concurrencia:** 1
**Disparador:** Webhook POST desde formulario de Vicky (recepción de comprobante)

### Input
```json
{
  "id_prereserva": "integer",
  "tipo": "sena | saldo | extra | reembolso",
  "medio_pago": "string",
  "proveedor": "string | null",
  "cuenta_destino": "string | null",
  "monto_esperado": "number",
  "monto_recibido": "number",
  "moneda": "ARS | USD | USDT | BTC",
  "comprobante_url": "string | null",
  "referencia_externa": "string | null",
  "validado_por": "string",
  "notas": "string | null",
  "source_event": "string"
}
```

### Lógica

```
PASO 1 — Validar input
  → id_prereserva existe en PRE_RESERVAS y estado = 'pendiente_pago'
  → monto_esperado > 0
  → monto_recibido >= 0
  → medio_pago es valor válido

PASO 2 — Verificar idempotencia
  → Buscar PAGOS WHERE id_prereserva = input.id_prereserva
    AND tipo = input.tipo
    AND estado IN ('en_revision', 'confirmado')
  → Si existe y estado = 'confirmado':
      RETORNAR { ok: true, nota: 'pago_ya_confirmado', id_pago: existente.id }
  → Si existe y estado = 'en_revision':
      RETORNAR { ok: true, nota: 'pago_ya_en_revision', id_pago: existente.id }

PASO 3 — Verificar diferencia de monto
  → diferencia = ABS(monto_esperado - monto_recibido)
  → umbral = diferencia_pago_tolerancia (de CONFIGURACION_GENERAL, default 5000)
  → SI diferencia > umbral:
      → Registrar warning en LOG_CAMBIOS
      → Continuar (Vicky tomó la decisión de registrar igual)
  → SI diferencia > 0 Y diferencia <= umbral:
      → Registrar info en LOG_CAMBIOS con nota de diferencia menor

PASO 4 — Escribir en PAGOS
  → id_pago = max(id_pago) + 1
  → estado = 'en_revision'
  → es_automatico = FALSE
  → created_at = now()
  → updated_at = now()

PASO 5 — Actualizar PRE_RESERVAS
  → intentos_pago = intentos_pago + 1
  → updated_at = now()

PASO 6 — Escribir en LOG_CAMBIOS
  → nivel: info
  → detalle: { monto_esperado, monto_recibido, medio_pago, comprobante_url }
```

### Output
```json
{
  "ok": true,
  "id_pago": 1,
  "estado": "en_revision"
}
```

---

## 12. WORKFLOW: db_recalcular_disponibilidad

**Concurrencia:** 1
**Disparador:** Llamado por otros workflows (nunca directamente por el usuario)

### Input
```json
{
  "id_cabanas": [1, 2, 3],
  "fechas": ["2026-06-20", "2026-06-21", "2026-06-22"],
  "source_event": "string"
}
```

Si `id_cabanas` está vacío: recalcular todas las cabañas activas.
Si `fechas` está vacío: recalcular próximos 60 días.

### Lógica

```
PARA CADA (id_cabana, fecha) en el producto cartesiano de inputs:

  PASO 1 — Verificar BLOQUEOS activos
  → SI existe BLOQUEO activo para (id_cabana O null, fecha):
      estado = 'bloqueada'
      → escribir y continuar con siguiente (id_cabana, fecha)

  PASO 2 — Verificar RESERVAS confirmadas
  // Dos consultas separadas para distinguir ocupada de checkout_disponible

  // 2A: ¿La fecha está dentro del período de ocupación de la reserva?
  → SI existe RESERVA WHERE id_cabana = id_cabana
    AND estado IN ('confirmada', 'activa')
    AND fecha_checkin <= fecha
    AND fecha_checkout > fecha:
      estado = 'ocupada', id_reserva_activa = reserva.id
      → escribir y continuar

  // 2B: ¿La fecha es exactamente el día de checkout de una reserva?
  //     (fecha_checkout = fecha significa que el huésped sale ese día:
  //      la cabaña puede recibir un nuevo checkin si no hay otro conflicto)
  → SI existe RESERVA WHERE id_cabana = id_cabana
    AND estado IN ('confirmada', 'activa')
    AND fecha_checkout = fecha:
      // Verificar que ningún otro elemento ocupa ese mismo día
      // (otra RESERVA que entra ese día, PRE_RESERVA activa, o BLOQUEO)
      SI no existe conflicto adicional para (id_cabana, fecha):
        estado = 'checkout_disponible', id_reserva_activa = reserva.id
        → escribir y continuar
      // Si hay conflicto adicional: el PASO 2A o PASO 1 ya lo habrán capturado

  PASO 3 — Verificar PRE_RESERVAS activas
  → SI existe PRE_RESERVA WHERE id_cabana = id_cabana
    AND estado = 'pendiente_pago'
    AND fecha_in <= fecha
    AND fecha_out > fecha:
      estado = 'ocupada', id_prereserva_activa = prereserva.id
      → escribir y continuar

  PASO 4 — Calcular disponible
  → estado = 'disponible'
  → Calcular hora_checkin_minima según reglas de horario (sin escalonamiento en esta etapa)
  → Calcular tipo_dia: finde / semana / feriado
  → Calcular temporada desde TEMPORADAS
  → Calcular minimo_noches desde CONFIGURACION_GENERAL

  PASO 5 — Escribir en DISPONIBILIDAD_CACHE
  → Upsert: si existe la fila (id_cabana, fecha), actualizar; si no, insertar
  → recalculado_en = now()

PASO FINAL — Escribir en LOG_CAMBIOS
  → Un único registro por ejecución del workflow (no por fila)
  → nivel: info
  → detalle: { cabanas_recalculadas, fechas_recalculadas, source_event }
```

### Output
```json
{
  "ok": true,
  "filas_actualizadas": 15,
  "duracion_ms": 340
}
```

---

## 13. WORKFLOW: sistema_expirar_prereservas

**Concurrencia:** Schedule (cada 5 minutos)
**Disparador:** Cron automático de n8n

### Lógica

```
PASO 1 — Buscar PRE_RESERVAS vencidas
  → WHERE estado = 'pendiente_pago'
    AND expira_en < NOW()

PASO 2 — Para cada PRE_RESERVA encontrada:

  PASO 2a — Idempotencia
  → Verificar que estado sigue siendo 'pendiente_pago'
    (puede haber cambiado entre el SELECT y el UPDATE si hubo otra ejecución)
  → Si estado ya cambió: saltar esta PRE_RESERVA

  PASO 2b — Verificar si hay PAGO en 'en_revision' asociado
  → SI existe PAGO WHERE id_prereserva = id AND estado = 'en_revision':
      NO vencer automáticamente

      → Marcar en PRE_RESERVAS.notas:
          "requiere_revision_manual: pago_en_revision_vencido"
      → PRE_RESERVAS.updated_at = now()

      → Registrar en LOG_CAMBIOS con nivel 'warning':
          "PRE_RESERVA {id} venció en tiempo pero tiene PAGO en revisión.
           Requiere atención manual. Monto: {monto_sena}."

      → Calcular horas_transcurridas = horas entre expira_en y now()
      → SI horas_transcurridas <= prereserva_pago_en_revision_alerta_horas:
          Notificar a Vicky solamente
      → SI horas_transcurridas > prereserva_pago_en_revision_alerta_horas:
          Notificar a Franco Y Rodrigo (alerta elevada):
            "⚠️ PRE_RESERVA {id} lleva más de {X}hs vencida con pago en revisión
             sin resolver. Requiere atención inmediata."
          Registrar en LOG_CAMBIOS con nivel 'error'

      → saltar esta PRE_RESERVA (no vencer)

  PASO 2c — Vencer PRE_RESERVA
  → PRE_RESERVA.estado = 'vencida'
  → PRE_RESERVA.updated_at = now()

  PASO 2d — Actualizar CONSULTA asociada
  → SI CONSULTA.estado_conversacion = 'esperando_pago':
      CONSULTA.estado_conversacion = 'cerrada'
      CONSULTA.updated_at = now()

  PASO 2e — Recalcular disponibilidad
  → Llamar a db_recalcular_disponibilidad para las fechas de la PRE_RESERVA

  PASO 2f — Registrar en LOG_CAMBIOS
  → nivel: info
  → source_event: 'sistema_expiracion'

PASO 3 — Log de ejecución del schedule
  → SI prereservas_vencidas > 0 OR prereservas_con_pago_pendiente > 0:
      Registrar en LOG_CAMBIOS
      → nivel: info
      → detalle: { prereservas_vencidas: N, prereservas_con_pago_pendiente: M }
  → SI prereservas_vencidas = 0 AND prereservas_con_pago_pendiente = 0:
      → En DEV/TEST: registrar igualmente (útil para verificar que el schedule corre)
      → En PROD: NO registrar (evitar saturar LOG_CAMBIOS con ejecuciones sin efecto)
      → El nivel de log activo se lee de CONFIGURACION_GENERAL clave `LOG_NIVEL_MINIMO`
```

### Idempotencia
El Paso 2a garantiza que si el schedule corre dos veces casi simultáneamente, la segunda ejecución no vence una PRE_RESERVA que ya fue vencida por la primera.

---

## 14. VALIDACIÓN PREVIA A ESCRITURAS CRÍTICAS

### 14.1 Regla general

Ningún workflow escribe en una hoja crítica sin ejecutar en orden estricto:

```
1. VALIDAR    → el input es estructuralmente correcto
2. NORMALIZAR → los datos tienen el formato exacto esperado
3. DEDUPLICAR → el registro no existe ya en un estado equivalente
4. CONSISTENCIA → las entidades relacionadas están en estado compatible
5. ESCRIBIR   → recién aquí se toca el Sheets
```

Si cualquiera de los pasos 1 a 4 falla, el workflow retorna error sin escribir nada. El error queda en LOG_CAMBIOS. No hay escrituras parciales.

### 14.2 Qué se valida en cada hoja

**CONSULTAS:**
- `canal` es valor del enum válido
- `id_contacto_externo` no está vacío
- Si hay fechas: `fecha_out > fecha_in`
- Si hay `id_huesped`: existe en HUÉSPEDES

**PRE_RESERVAS:**
- `id_cabana` existe en CABAÑAS, `activa = TRUE`, `bloqueada = FALSE`
- `id_huesped` existe en HUÉSPEDES
- `fecha_out > fecha_in`
- `personas > 0` y `personas <= cabaña.capacidad_max`
- No existe PRE_RESERVA en `pendiente_pago` para misma (cabaña, fechas)
- DISPONIBILIDAD_CACHE confirma `disponible` o `checkout_disponible` para todo el rango

**RESERVAS:**
- Solo se crea desde `db_confirmar_reserva`
- Recheck de disponibilidad completado sin conflictos (Paso 3 de Sección 10)
- PRE_RESERVA en estado `pendiente_pago`
- PAGO en estado `en_revision` o `pendiente`

**PAGOS:**
- `id_prereserva` existe y está en estado `pendiente_pago`
- `monto_esperado > 0`
- `medio_pago` es valor válido
- `moneda` es valor válido

### 14.3 Cómo se rechaza una escritura inválida

```json
{
  "ok": false,
  "error": "validacion_fallida",
  "campo": "fecha_out",
  "detalle": "fecha_out debe ser mayor que fecha_in",
  "input_recibido": { "fecha_in": "2026-06-22", "fecha_out": "2026-06-20" }
}
```

El error se registra en LOG_CAMBIOS con nivel `warning`. El formulario que disparó el webhook muestra el error al usuario. No se reintenta automáticamente.

---

## 15. ESTRATEGIA DE IDEMPOTENCIA

### 15.1 Principio

Cualquier workflow puede ser ejecutado más de una vez con el mismo input sin producir efectos diferentes al de la primera ejecución exitosa.

### 15.2 Mecanismo por workflow

| Workflow | Clave de idempotencia | Comportamiento si ya existe |
|---|---|---|
| `db_crear_consulta` | `id_contacto_externo` + estado activo | Retorna consulta existente, no crea nueva |
| `db_crear_prereserva` | `id_cabana` + `fecha_in` + `fecha_out` + estado `pendiente_pago` | Retorna error con id del conflicto |
| `db_registrar_pago` | `id_prereserva` + `tipo` + estado activo | Retorna pago existente, no crea nuevo |
| `db_confirmar_reserva` | Estado de PRE_RESERVA + estado de PAGO | Retorna `ya_confirmada` si ya fue procesado |
| `db_recalcular_disponibilidad` | Upsert por (id_cabana, fecha) | Sobreescribe con el valor más reciente |
| `sistema_expirar_prereservas` | Verifica estado antes de vencer | No procesa PRE_RESERVAS ya vencidas |

### 15.3 Registro de ejecuciones

Cada ejecución de un workflow crítico registra en LOG_CAMBIOS:
- El input recibido (sin datos sensibles)
- El resultado (ok o error)
- Si fue idempotente (retornó resultado existente)
- El timestamp de ejecución

Esto permite reconstruir exactamente qué pasó ante un reintento o replay accidental.

---

## 16. ESTRATEGIA DE LOCKING LÓGICO

### 16.1 El problema

Google Sheets no tiene transacciones nativas ni locks de fila. Si dos ejecuciones de `db_confirmar_reserva` corren simultáneamente para la misma cabaña y fechas, ambas podrían pasar el recheck de disponibilidad y crear dos RESERVAS.

### 16.2 La solución: tres capas

**Capa 1 — Concurrencia = 1 en n8n**
El workflow `db_confirmar_reserva` tiene concurrencia configurada en 1. Si llegan dos ejecuciones simultáneas, la segunda espera en cola hasta que la primera termine. Esta es la protección principal.

**Capa 2 — Timestamp de inicio de procesamiento**
Al entrar al Paso 1 de `db_confirmar_reserva`, el workflow escribe en `PRE_RESERVAS.notas` un campo auxiliar: `"procesando_desde: {timestamp}"`. Si una segunda ejecución llega para la misma PRE_RESERVA y encuentra ese campo con un timestamp reciente (menos de 60 segundos), retorna error `procesamiento_en_curso`.

```
procesando_desde: 2026-06-05T14:23:00Z
```

**Capa 3 — Recheck de estado antes de cada escritura crítica**
Antes de ejecutar cualquier escritura en el Paso 4 en adelante, el workflow vuelve a leer el estado actual de la PRE_RESERVA desde Sheets. Si el estado cambió desde el Paso 1 (por ejemplo, otra ejecución ya la convirtió), aborta sin escribir.

### 16.3 Detección de carrera escapada

Si a pesar de las tres capas se detecta una doble RESERVA (en el recálculo de disponibilidad o en una auditoría manual):

1. Ambas RESERVAS pasan a estado `conflicto_pendiente`
2. LOG_CAMBIOS registra el conflicto con nivel `error`
3. Notificación inmediata a Franco
4. El equipo resuelve manualmente cuál RESERVA es válida

### 16.4 Ventana de riesgo real

Con concurrencia = 1 en n8n, la ventana de riesgo real es prácticamente cero en condiciones normales. El timestamp de procesamiento cubre el caso extremo de que n8n falle y se reinicie en medio de una ejecución.

---

## 17. MANEJO DE RACE CONDITIONS

### Race condition 1 — Dos formularios enviados simultáneamente para la misma cabaña

**Escenario:** Franco y Vicky crean pre-reservas para Bamboo el mismo fin de semana con diferencia de segundos.

**Resolución:**
- Concurrencia = 1 en `db_crear_prereserva`
- La primera ejecución pasa el Paso 2 (no existe PRE_RESERVA) y escribe
- La segunda ejecución entra al Paso 2 y encuentra la PRE_RESERVA recién creada
- Retorna `error: 'prereserva_activa_existente'`
- No hay double booking

---

### Race condition 2 — PRE_RESERVA vence mientras se procesa el pago

**Escenario:** La PRE_RESERVA tiene `expira_en = 14:00`. El schedule de expiración corre a las 14:00. Vicky aprueba el comprobante también a las 14:00.

**Resolución:**
- `sistema_expirar_prereservas` verifica si hay PAGO en `en_revision` antes de vencer (Paso 2b)
- Si el PAGO ya fue registrado: NO vence la PRE_RESERVA, registra warning, notifica al equipo
- Si el PAGO no está registrado aún: vence normalmente
- Si `db_confirmar_reserva` llega después de que la PRE_RESERVA ya venció: Paso 1 detecta estado `vencida` y retorna error
- En ambos casos: sin double booking, sin pérdida silenciosa del pago

---

### Race condition 3 — Bloqueo creado sobre PRE_RESERVA activa

**Escenario:** Franco crea un bloqueo para Bamboo el 20 de junio. Hay una PRE_RESERVA activa para esas fechas.

**Resolución:**
- El bloqueo se crea en BLOQUEOS (no hay validación que lo impida)
- n8n detecta el conflicto al recalcular disponibilidad: la fecha tiene estado `ocupada` (por PRE_RESERVA) pero también hay BLOQUEO
- LOG_CAMBIOS registra el conflicto con nivel `warning`
- Notificación a Franco: "Hay un bloqueo que conflictúa con PRE_RESERVA #{id}"
- El equipo decide: cancelar PRE_RESERVA o eliminar el bloqueo
- El sistema no resuelve automáticamente

---

### Race condition 4 — n8n se reinicia en medio de db_confirmar_reserva

**Escenario:** n8n falla entre el Paso 4 (PRE_RESERVA → convertida) y el Paso 5 (crear RESERVA).

**Estado inconsistente:** PRE_RESERVA en `convertida` sin RESERVA correspondiente.

**Resolución:**
- Al reiniciarse n8n, el webhook de Vicky puede reintentarse
- `db_confirmar_reserva` Paso 1: PRE_RESERVA está en `convertida`
- El workflow no retorna `ya_confirmada` porque no hay RESERVA
- Detecta el estado inconsistente: PRE_RESERVA en `convertida` sin RESERVA
- Registra en LOG_CAMBIOS con nivel `error`: "PRE_RESERVA {id} en estado convertida sin RESERVA asociada"
- Notifica a Franco para resolución manual
- El equipo puede crear la RESERVA manualmente o revertir la PRE_RESERVA a `pendiente_pago`

Esta es la razón por la que el timestamp de procesamiento (Sección 16) es útil: permite identificar que la ejecución anterior llegó hasta cierto punto.

---

## 18. QUÉ ACCIONES SIGUEN SIENDO MANUALES

### 18.1 Lista de acciones manuales en esta etapa

| Acción | Quién | Cómo |
|---|---|---|
| Crear CONSULTA inicial | Franco / Vicky | Formulario interno o directamente en Sheets DEV |
| Crear PRE_RESERVA | Franco / Vicky | Formulario interno → webhook → `db_crear_prereserva` |
| Validar comprobante de pago | Vicky | Google Form → webhook → `db_registrar_pago` |
| Aprobar pago y confirmar reserva | Vicky | Google Form → webhook → `db_confirmar_reserva` |
| Registrar checkin | Franco / Vicky | Directamente en RESERVAS (cambio de estado a `activa`) |
| Registrar checkout | Franco / Vicky | Directamente en RESERVAS (cambio de estado a `completada`) |
| Crear bloqueos | Franco / Rodrigo | Directamente en BLOQUEOS → Apps Script notifica a n8n |
| Cargar feriados | Franco / Rodrigo | Directamente en FERIADOS |
| Actualizar tarifas | Franco / Rodrigo | Directamente en TARIFAS |
| Cancelar reservas | Franco / Vicky | Directamente en RESERVAS + registrar en LOG_CAMBIOS |
| Notificar a Jennifer | Franco / Rodrigo | WhatsApp manual |
| Notificar al cliente | Vicky | WhatsApp manual |

### 18.2 Qué automatiza n8n en esta etapa

| Acción | Workflow |
|---|---|
| Validar disponibilidad al crear PRE_RESERVA | `db_crear_prereserva` |
| Calcular precio | Motor de precios (llamado desde `db_crear_prereserva`) |
| Bloquear disponibilidad al crear PRE_RESERVA | `db_crear_prereserva` → `db_recalcular_disponibilidad` |
| Recheck de disponibilidad al confirmar | `db_confirmar_reserva` |
| Crear RESERVA con todos los campos | `db_confirmar_reserva` |
| Recalcular DISPONIBILIDAD_CACHE | `db_recalcular_disponibilidad` |
| Vencer PRE_RESERVAS expiradas | `sistema_expirar_prereservas` |
| Registrar todo en LOG_CAMBIOS | Todos los workflows |

---

## 19. FORMULARIO INTERNO MÍNIMO DE VICKY

En esta etapa, el único punto de entrada manual estructurado es un Google Form con dos propósitos: registrar el comprobante recibido y aprobar el pago.

### 19.1 Formulario A: Registro de comprobante

**Nombre:** "Vita Delta — Registrar comprobante de pago"
**Propósito:** Vicky completa este formulario cuando el cliente envía un comprobante.

**Campos:**

| Campo | Tipo | Obligatorio | Validación |
|---|---|---|---|
| ID de pre-reserva | Número | Sí | Mayor que 0 |
| Monto recibido | Número | Sí | Mayor que 0 |
| Medio de pago | Lista | Sí | transferencia_bancaria / transferencia_mp / efectivo / cripto |
| Proveedor / banco | Texto corto | No | |
| Referencia de la transferencia | Texto corto | No | |
| URL del comprobante | URL | No | |
| Notas | Texto largo | No | |

**Al enviar:** Apps Script dispara webhook a n8n → `db_registrar_pago`

### 19.2 Formulario B: Aprobación de pago

**Nombre:** "Vita Delta — Aprobar pago"
**Propósito:** Vicky o Franco completan este formulario tras verificar el comprobante.

**Campos:**

| Campo | Tipo | Obligatorio | Validación |
|---|---|---|---|
| ID de pago | Número | Sí | Mayor que 0 |
| ID de pre-reserva | Número | Sí | Mayor que 0 |
| Decisión | Lista | Sí | Aprobar / Rechazar |
| Validado por | Lista | Sí | Vicky / Franco / Rodrigo |
| Motivo de rechazo | Texto | Solo si Rechazar | |

**Al enviar:** Apps Script dispara webhook a n8n → `db_confirmar_reserva` (si Aprobar) o `db_registrar_pago` con estado rechazado (si Rechazar)

### 19.3 Apps Script mínimo

El script que dispara los webhooks es el puente mínimo definido en la arquitectura (Etapa 1). Solo hace esto:

```javascript
function onFormSubmit(e) {
  const datos = e.namedValues;
  const payload = {
    id_prereserva: parseInt(datos['ID de pre-reserva'][0]),
    // ... mapeo de campos ...
    source_event: 'vicky_form'
  };

  const url = PropertiesService.getScriptProperties()
    .getProperty('N8N_WEBHOOK_URL');  // nunca hardcodeado

  UrlFetchApp.fetch(url, {
    method: 'POST',
    contentType: 'application/json',
    payload: JSON.stringify(payload)
  });
}
```

La URL del webhook se guarda en las propiedades del script, no en el código. Cambiar de DEV a TEST a PROD es cambiar esa propiedad.

---

## 20. LOGGING MÍNIMO

### 20.1 Qué escribe cada workflow en LOG_CAMBIOS

| Workflow | Qué loguea | Nivel |
|---|---|---|
| `db_crear_consulta` | CONSULTA creada o existente retornada | info |
| `db_crear_prereserva` | PRE_RESERVA creada; errores de validación | info / warning |
| `db_registrar_pago` | PAGO registrado; diferencia de monto | info / warning |
| `db_confirmar_reserva` | RESERVA creada; PRE_RESERVA convertida; PAGO confirmado; conflictos | info / error |
| `db_recalcular_disponibilidad` | Resumen de filas actualizadas | info |
| `sistema_expirar_prereservas` | PRE_RESERVAS vencidas; casos con PAGO pendiente | info / warning |

### 20.2 Estructura mínima de un registro útil

Un registro de LOG_CAMBIOS es útil para debugging si permite responder: ¿qué pasó, cuándo, por qué workflow, sobre qué registro, y cuál fue el resultado?

```
fecha_hora:        2026-06-05T15:45:00Z
tabla_afectada:    RESERVAS
id_registro:       142
campo_modificado:  estado
valor_anterior:    (vacío — registro nuevo)
valor_nuevo:       confirmada
modificado_por:    n8n
source_event:      vicky_form
nivel:             info
detalle:           {"id_prereserva": 1, "id_pago": 1, "validado_por": "vicky",
                    "encargado_semana": "Franco", "monto_total": 350000}
```

### 20.3 Qué NO se loguea para no saturar

- Lecturas de Sheets (SELECT sin escritura)
- Ejecuciones del schedule de expiración que no encontraron nada que vencer (salvo en DEV/TEST cuando se quiera verificar que el schedule está corriendo)
- Recálculos de disponibilidad donde ninguna fila cambió de estado
- Llamadas internas entre workflows que no producen escritura

### 20.4 Nivel mínimo de log por entorno

| Entorno | Nivel mínimo | Qué se registra |
|---|---|---|
| DEV | info | Todo, incluyendo ejecuciones sin cambios |
| TEST | info | Todo |
| PROD | warning | Solo cambios de estado, errores y conflictos |

El nivel mínimo se configura en CONFIGURACION_GENERAL con la clave `LOG_NIVEL_MINIMO`.

---

## 21. ESTRATEGIA DE ROLLBACK Y RECUPERACIÓN

### 21.1 Principio

Google Sheets no tiene transacciones. Si un workflow falla a mitad de ejecución, puede dejar el sistema en estado parcialmente modificado. El objetivo no es evitar que esto ocurra (imposible sin transacciones reales) sino detectarlo y recuperarlo de forma sistemática.

### 21.2 Estados inconsistentes posibles y cómo detectarlos

| Inconsistencia | Cómo detectar | Cómo recuperar |
|---|---|---|
| PRE_RESERVA en `convertida` sin RESERVA | Query: PRE_RESERVAS convertidas sin id_prereserva en RESERVAS | Crear RESERVA manualmente o revertir PRE_RESERVA a `pendiente_pago` |
| RESERVA confirmada sin PAGO confirmado | Query: RESERVAS confirmadas sin PAGO confirmado | Registrar PAGO manualmente con `source_event: 'sistema_correccion'` |
| DISPONIBILIDAD_CACHE desincronizada | Recálculo masivo manual | Ejecutar `db_recalcular_disponibilidad` con scope total |
| PRE_RESERVA en `pendiente_pago` con DISPONIBILIDAD_CACHE libre | Recálculo masivo | Ídem |
| Dos RESERVAS para la misma (cabaña, fechas) | Query sobre RESERVAS | Ambas a `conflicto_pendiente`, resolución manual |

### 21.3 Checklist de recuperación post-falla

Ejecutar en orden después de cualquier falla de workflow:

1. Revisar LOG_CAMBIOS de la última hora: ¿hay registros de nivel `error`?
2. Verificar estado de la PRE_RESERVA involucrada: ¿es coherente con lo esperado?
3. Verificar estado del PAGO asociado: ¿coincide con el estado de la PRE_RESERVA?
4. Verificar que existe RESERVA si la PRE_RESERVA está en `convertida`
5. Ejecutar `db_recalcular_disponibilidad` para las fechas afectadas
6. Registrar en LOG_CAMBIOS la corrección manual con `source_event: 'sistema_correccion'`
7. Si el cliente pagó y hubo error: contactar al cliente manualmente, no dejar en silencio

### 21.4 Caso específico: PRE_RESERVA vencida con PAGO en revisión durante más de X horas

**Cómo se detecta:** LOG_CAMBIOS muestra registros de nivel `warning` o `error` con el texto `pago_en_revision_vencido`. PRE_RESERVAS.notas contiene `requiere_revision_manual: pago_en_revision_vencido`.

**Protocolo de recuperación:**

1. Identificar la PRE_RESERVA y el PAGO asociado en LOG_CAMBIOS
2. Revisar el comprobante manualmente (URL en PAGOS.comprobante_url)
3. **Si el pago es válido:**
   - Confirmar que la cabaña sigue disponible (consultar DISPONIBILIDAD_CACHE)
   - Si disponible: aprobar el PAGO via formulario B → `db_confirmar_reserva` crea la RESERVA normalmente
   - Si no disponible (otra reserva entró mientras tanto): notificar al cliente, coordinar reembolso o reasignación, registrar en LOG_CAMBIOS con `source_event: 'sistema_correccion'`
4. **Si el pago es inválido** (comprobante apócrifo, monto incorrecto, transferencia de tercero):
   - Cambiar PAGOS.estado = `rechazado`, PAGOS.motivo_rechazo = motivo
   - Cambiar PRE_RESERVAS.estado = `cancelada_por_cliente` (o el motivo real)
   - Llamar a `db_recalcular_disponibilidad` para liberar las fechas
   - Registrar en LOG_CAMBIOS con `source_event: 'sistema_correccion'` y detalle completo
   - Notificar al cliente manualmente
5. En ambos casos: limpiar el campo PRE_RESERVAS.notas de la marca `requiere_revision_manual`

**Regla:** Ningún caso de `pago_en_revision_vencido` se resuelve en silencio. Toda decisión queda registrada en LOG_CAMBIOS con `source_event: 'sistema_correccion'` y el nombre de quien tomó la decisión.

---

### 21.5 Recuperación de entorno TEST después de pruebas

Después de cada ronda de pruebas, limpiar el entorno TEST:

1. Eliminar filas de prueba de CONSULTAS, PRE_RESERVAS, RESERVAS, PAGOS
2. Limpiar LOG_CAMBIOS de registros de prueba (o crear nueva hoja `LOG_CAMBIOS_TEST_BACKUP`)
3. Ejecutar `db_recalcular_disponibilidad` para regenerar DISPONIBILIDAD_CACHE limpia
4. Verificar que CONFIGURACION_GENERAL sigue con los valores correctos

---

## 22. CASOS DE PRUEBA DEL PRIMER FLUJO

### Caso 1 — Happy path: flujo completo exitoso

**Input:** Bamboo, vie 20 jun → dom 22 jun, 3 personas, transferencia bancaria
**Pasos esperados:** Consulta creada → PRE_RESERVA creada → DISPONIBILIDAD_CACHE actualizada (ocupada) → PAGO registrado (en_revision) → PAGO aprobado → RESERVA confirmada → DISPONIBILIDAD_CACHE actualizada
**Output esperado en Sheets:** 1 fila en CONSULTAS (cerrada), 1 en PRE_RESERVAS (convertida), 1 en RESERVAS (confirmada), 1 en PAGOS (confirmado)
**LOG_CAMBIOS esperado:** 4 registros de nivel info (uno por entidad modificada)

---

### Caso 2 — Fechas no disponibles

**Input:** Bamboo, mismas fechas del Caso 1 (ya ocupadas), 2 personas
**Pasos esperados:** `db_crear_prereserva` Paso 3 detecta fechas ocupadas en cache
**Output esperado:** Error `fechas_no_disponibles`, sin escritura en PRE_RESERVAS
**LOG_CAMBIOS esperado:** 1 registro de nivel warning con fechas en conflicto

---

### Caso 3 — PRE_RESERVA vence sin pago

**Input:** PRE_RESERVA creada con `expira_en` en el pasado (simular en TEST con fecha manual)
**Pasos esperados:** `sistema_expirar_prereservas` detecta la PRE_RESERVA → vence → recalcula disponibilidad
**Output esperado:** PRE_RESERVA en estado `vencida`, DISPONIBILIDAD_CACHE vuelve a `disponible`
**LOG_CAMBIOS esperado:** registro de nivel info con `source_event: sistema_expiracion`

---

### Caso 4 — Comprobante con monto diferente (dentro del umbral)

**Input:** Seña esperada $175.000, monto recibido $174.000 (diferencia $1.000 < umbral $5.000)
**Pasos esperados:** `db_registrar_pago` registra con diferencia, continúa normalmente
**Output esperado:** PAGO en `en_revision`, LOG_CAMBIOS con nota de diferencia menor
**Comportamiento esperado:** No bloquea el flujo, Vicky puede aprobar igual

---

### Caso 5 — Comprobante con monto muy diferente (sobre el umbral)

**Input:** Seña esperada $175.000, monto recibido $100.000 (diferencia $75.000 > umbral)
**Pasos esperados:** `db_registrar_pago` registra pero con warning explícito
**Output esperado:** PAGO en `en_revision`, LOG_CAMBIOS con nivel warning, Vicky debe decidir
**Comportamiento esperado:** El flujo no se bloquea automáticamente; Vicky puede rechazar o aprobar

---

### Caso 6 — Idempotencia: db_confirmar_reserva llamado dos veces

**Input:** Vicky envía el formulario de aprobación dos veces (doble clic accidental)
**Pasos esperados:** Primera llamada confirma. Segunda llamada entra, Paso 1 detecta PRE_RESERVA en `convertida`, retorna `ya_confirmada`
**Output esperado:** Solo 1 RESERVA creada, sin duplicado
**LOG_CAMBIOS esperado:** 2 registros: el de la confirmación real + 1 de nivel info indicando replay idempotente

---

### Caso 7 — Persona excede capacidad máxima

**Input:** Tokio (cap. máx 4), 5 personas
**Pasos esperados:** `db_crear_prereserva` Paso 1 detecta `personas > capacidad_max`
**Output esperado:** Error `capacidad_excedida`, sin escritura
**LOG_CAMBIOS esperado:** 1 registro de nivel warning

---

### Caso 8 — Cabaña bloqueada

**Input:** Franco crea BLOQUEO para Arrebol. Luego intento crear PRE_RESERVA para Arrebol en esas fechas.
**Pasos esperados:** BLOQUEO en BLOQUEOS → recálculo de cache → DISPONIBILIDAD_CACHE muestra `bloqueada` → `db_crear_prereserva` Paso 3 detecta fechas bloqueadas
**Output esperado:** Error `fechas_no_disponibles`, sin PRE_RESERVA

---

### Caso 9 — PRE_RESERVA vence con PAGO en revisión (no debe vencer)

**Input:** PRE_RESERVA vencida en tiempo pero con PAGO en estado `en_revision`
**Pasos esperados:** `sistema_expirar_prereservas` Paso 2b detecta PAGO en revisión → no vence → registra warning → notifica
**Output esperado:** PRE_RESERVA sigue en `pendiente_pago`, LOG_CAMBIOS con warning, equipo notificado
**Comportamiento esperado:** Requiere atención manual; no hay pérdida silenciosa

---

### Caso 10 — Conflicto simulado: dos PRE_RESERVAS para la misma cabaña y fechas

**Input:** Crear manualmente (desde Sheets, saltando el workflow) una segunda PRE_RESERVA activa para la misma (cabaña, fechas). Luego intentar confirmar la primera.
**Pasos esperados:** `db_confirmar_reserva` Paso 3 detecta segunda PRE_RESERVA activa → CONFLICTO
**Output esperado:** Primera PRE_RESERVA en `conflicto_pendiente`, PAGO sin confirmar, LOG_CAMBIOS con nivel error
**Propósito:** Verificar que el recheck detecta situaciones anómalas inyectadas manualmente

---

## 23. PROTOCOLO DE PRUEBA

### 23.1 Entorno

Todas las pruebas se ejecutan sobre `VITA_DELTA_TEST`. Nunca sobre DEV ni PROD.

### 23.2 Precondiciones antes de cada ronda de pruebas

1. VITA_DELTA_TEST tiene los datos mínimos de Sección 4 cargados
2. DISPONIBILIDAD_CACHE está poblada (ejecutar recálculo masivo manual)
3. CONSULTAS, PRE_RESERVAS, RESERVAS, PAGOS y LOG_CAMBIOS están vacías
4. Los workflows de n8n apuntan a VITA_DELTA_TEST (`SHEETS_ID` = ID del Sheets TEST)

### 23.3 Orden de ejecución de casos de prueba

```
1. Caso 7 (capacidad excedida) — prueba validación de input
2. Caso 8 (cabaña bloqueada) — prueba integración BLOQUEOS → CACHE
3. Caso 1 (happy path) — prueba flujo completo
4. Caso 2 (fechas ocupadas) — prueba que la cache se actualizó correctamente en Caso 1
5. Caso 4 (diferencia de monto) — prueba tolerancia
6. Caso 5 (diferencia alta) — prueba warning de monto
7. Caso 6 (idempotencia) — prueba replay
8. Caso 3 (vencimiento) — crear PRE_RESERVA nueva, forzar vencimiento, verificar
9. Caso 9 (vencimiento con pago) — crear PRE_RESERVA + PAGO en revisión, forzar vencimiento
10. Caso 10 (conflicto manual) — prueba del recheck con dato corrupto inyectado
```

### 23.4 Qué verificar después de cada caso

Para cada caso, verificar en el Sheets TEST:

- **CONSULTAS:** estado correcto
- **PRE_RESERVAS:** estado correcto, campos completos
- **RESERVAS:** existe si debería, no existe si no debería
- **PAGOS:** estado correcto, montos correctos
- **DISPONIBILIDAD_CACHE:** refleja correctamente el estado post-operación
- **LOG_CAMBIOS:** tiene los registros esperados con el nivel correcto

### 23.5 Limpieza entre casos

Entre casos que modifiquen datos (Casos 1, 3, 4, 5, 8, 9, 10): limpiar las filas creadas en CONSULTAS, PRE_RESERVAS, RESERVAS y PAGOS, y ejecutar recálculo de disponibilidad para las fechas usadas.

El Caso 2 depende del Caso 1 (verifica que las fechas quedaron ocupadas), por lo que se ejecuta inmediatamente después sin limpiar.

### 23.6 Quién ejecuta y quién valida

| Rol | Responsabilidad |
|---|---|
| Franco | Ejecuta los casos, verifica resultados en Sheets, aprueba o rechaza |
| Claude (arquitecto) | Disponible para debugging de lógica si algo no funciona como se espera |

---

## 24. CRITERIO DE ÉXITO

La Etapa 5B se considera operativa y puede avanzar a la siguiente cuando se cumplan **todas** las siguientes condiciones. Sin excepciones:

### Criterios funcionales

- [ ] Los 10 casos de prueba de la Sección 22 pasan en VITA_DELTA_TEST sin intervención técnica
- [ ] El Caso 1 (happy path) puede ejecutarse tres veces seguidas con distintas fechas y distintas cabañas sin errores
- [ ] El Caso 6 (idempotencia) produce exactamente 1 RESERVA en cada ejecución, sin importar cuántas veces se llame al formulario de aprobación
- [ ] El Caso 10 (conflicto simulado) es detectado por el recheck y NO crea una RESERVA en estado `confirmada`

### Criterios de integridad

- [ ] Después de ejecutar todos los casos de prueba, RESERVAS y PRE_RESERVAS son consistentes (no hay PRE_RESERVAS en `convertida` sin RESERVA correspondiente)
- [ ] DISPONIBILIDAD_CACHE refleja correctamente el estado de ocupación después de cada operación (verificar manualmente al menos para las fechas del Caso 1)
- [ ] LOG_CAMBIOS tiene un registro por cada operación significativa, con nivel y detalle correctos

### Criterios de estabilidad

- [ ] `sistema_expirar_prereservas` puede correr 10 veces seguidas sobre los mismos datos sin producir duplicados ni errores en LOG_CAMBIOS
- [ ] Si se corta la conexión de n8n a Sheets a mitad de una operación y luego se reinicia, el estado final es detectable y recuperable siguiendo el checklist de Sección 21

### Criterio operativo

- [ ] Vicky puede completar el flujo completo (Formulario A → Formulario B → verificar en Sheets) sin instrucciones técnicas adicionales, solo con la documentación de esta etapa

---

## 25. PENDIENTES PARA ETAPAS SIGUIENTES

Lo que queda diferido explícitamente de esta etapa:

### Próxima etapa inmediata: conectar canales de entrada

- [ ] WhatsApp Cloud API como canal de entrada (reemplaza el formulario manual)
- [ ] Instagram Graph API como canal adicional
- [ ] El flujo transaccional de esta etapa no cambia; solo cambia quién lo dispara

### Motor de disponibilidad completo

- [ ] Escalonamiento de horarios (definido en Etapa 2, no implementado en 5B)
- [ ] Recálculo masivo nocturno programado
- [ ] OVERRIDES_OPERATIVOS activos en el motor de disponibilidad

### Pagos automáticos

- [ ] Webhook de MercadoPago (reemplaza el formulario de Vicky para pagos con link MP)
- [ ] El flujo de `db_confirmar_reserva` no cambia; solo cambia el disparador

### Bot conversacional

- [ ] Claude API integrado (Etapa 4B)
- [ ] Clasificador previo
- [ ] FAQ sin IA

### Automatizaciones operativas

- [ ] Notificación automática a Jennifer por WhatsApp
- [ ] Notificación automática al cliente por WhatsApp
- [ ] Actualización automática del calendario visual
- [ ] Asignación automática del encargado semanal (en 5B se calcula pero no se notifica)

### Funcionalidad futura

- [ ] Cancelaciones automáticas
- [ ] Motor de descuentos (DESCUENTOS existe pero no participa)
- [ ] Eventos especiales con precios reales cargados
- [ ] Contabilidad y distribución entre socios
- [ ] Migración a Supabase cuando el volumen lo justifique

---

*Documento generado como parte del proceso de diseño del sistema Complejo Vita Delta.*
*La Etapa 5B es el primer contacto con implementación real. Todo lo construido aquí es la base sobre la que se conectan los canales externos en etapas siguientes.*
