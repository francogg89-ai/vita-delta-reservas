# Contrato técnico — `db_crear_consulta`

## 1. Propósito

Registra una nueva consulta entrante en la hoja `CONSULTAS`, o recupera una consulta
activa reciente si ya existe para el mismo contacto.

Es el punto de entrada del sistema: toda interacción de un potencial huésped
(desde WhatsApp, Instagram, web o carga manual) empieza con este workflow.

**Hace:**
- Valida el input (canal, id_contacto_externo, fechas tentativas).
- Busca si existe una consulta activa reciente (últimas 24 horas) para el mismo contacto.
- Si existe: la reutiliza y registra un LOG de reutilización.
- Si no existe: crea una nueva consulta con `estado_conversacion = inicio`.
- Registra siempre en LOG_CAMBIOS (excepto cuando el input es inválido).

**No hace:**
- No consulta disponibilidad.
- No bloquea fechas.
- No crea PRE_RESERVAS.
- No toca RESERVAS, PAGOS ni DISPONIBILIDAD_CACHE.
- No envía notificaciones ni mensajes de WhatsApp.
- No calcula precios.

---

## 2. Estado

| Campo | Valor |
|---|---|
| Versión validada | v3 |
| Archivo n8n DEV | `dev_db_crear_consulta_v3_final.json` |
| Archivo n8n TEST | `test_db_crear_consulta_v3.json` |
| DEV | ✅ validado |
| TEST | ✅ validado |
| Concurrencia | Sin restricción (las consultas no generan conflictos de disponibilidad) |
| Disparador en DEV | Manual Trigger con DEV_INPUT editable |
| Disparador en producción | Webhook POST o llamada desde bot |

---

## 3. Input

```json
{
  "canal": "whatsapp",
  "id_contacto_externo": "+5491112345678",
  "id_huesped": null,
  "fecha_in_tentativa": "2026-07-01",
  "fecha_out_tentativa": "2026-07-03",
  "personas_tentativa": 2,
  "source_event": "whatsapp_inbound"
}
```

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `canal` | `string` | **Sí** | Canal de origen. Valores válidos: `whatsapp`, `instagram`, `web`, `manual` |
| `id_contacto_externo` | `string` | **Sí** | Identificador del contacto en la plataforma (teléfono, ID de IG, etc.). No puede estar vacío. |
| `id_huesped` | `integer \| null` | No | FK → HUÉSPEDES. `null` si el contacto aún no está identificado como huésped. |
| `fecha_in_tentativa` | `string YYYY-MM-DD \| null` | No | Fecha de entrada tentativa. |
| `fecha_out_tentativa` | `string YYYY-MM-DD \| null` | No | Fecha de salida tentativa. Debe ser posterior a `fecha_in_tentativa` si ambas están presentes. |
| `personas_tentativa` | `integer \| null` | No | Cantidad de personas tentativa. |
| `source_event` | `string` | No | Origen del evento. Default: `manual_dev`. |

**Normalización automática:**
- `id_contacto_externo` se aplica `.trim()`.
- Si `id_contacto_externo` contiene `@` (parece email), se convierte a lowercase.

---

## 4. Output exitoso — consulta nueva

```json
{
  "ok": true,
  "es_nueva": true,
  "id_consulta": 1,
  "estado_conversacion": "inicio",
  "accion": "creada",
  "source_event": "whatsapp_inbound"
}
```

---

## 5. Output exitoso — consulta reutilizada

```json
{
  "ok": true,
  "es_nueva": false,
  "id_consulta": 1,
  "estado_conversacion": "eligiendo_fechas",
  "accion": "existente_reutilizada",
  "source_event": "whatsapp_inbound"
}
```

| Campo | Tipo | Descripción |
|---|---|---|
| `ok` | `boolean` | `true` en ambos casos exitosos |
| `es_nueva` | `boolean` | `true` si se creó, `false` si se reutilizó |
| `id_consulta` | `integer` | ID de la consulta (nueva o existente) |
| `estado_conversacion` | `string` | Estado actual de la consulta |
| `accion` | `string` | `"creada"` o `"existente_reutilizada"` |
| `source_event` | `string` | El mismo que vino en el input |

---

## 6. Output de error — input inválido

Se produce cuando el input no pasa las validaciones. **No escribe nada en Sheets.**

```json
{
  "ok": false,
  "error": "input_invalido",
  "detalle": [
    "canal inválido: 'telegram'. Valores aceptados: whatsapp, instagram, web, manual"
  ]
}
```

| Campo | Tipo | Descripción |
|---|---|---|
| `ok` | `boolean` | Siempre `false` |
| `error` | `string` | Código de error |
| `detalle` | `string[]` | Lista de errores de validación encontrados |

---

## 7. Hojas que lee

| Hoja | Filtro | Propósito |
|---|---|---|
| `CONSULTAS` | Sin filtro | Verificar idempotencia y calcular próximo `id_consulta` |

---

## 8. Hojas que escribe

| Hoja | Operación | Cuándo |
|---|---|---|
| `CONSULTAS` | Append (1 fila) | Solo cuando se crea una consulta nueva |
| `LOG_CAMBIOS` | Append (1 fila) | Siempre que el input es válido (nueva o reutilizada) |

**Campos escritos en CONSULTAS:**

| Campo | Valor |
|---|---|
| `id_consulta` | `max(id_consulta) + 1` |
| `canal` | Del input |
| `id_contacto_externo` | Del input, normalizado |
| `id_huesped` | Del input o vacío |
| `estado_conversacion` | `inicio` |
| `id_cabana_tentativa` | Vacío |
| `fecha_in_tentativa` | Del input o vacío |
| `fecha_out_tentativa` | Del input o vacío |
| `personas_tentativa` | Del input o vacío |
| `ultimo_mensaje_at` | Timestamp de creación |
| `contexto_json` | Vacío |
| `tokens_json` | Vacío |
| `motivo_derivacion` | Vacío |
| `source_event` | Del input |
| `created_at` | Timestamp de creación |
| `updated_at` | Timestamp de creación |

---

## 9. LOG_CAMBIOS generado

### Cuando se crea consulta nueva

```json
{
  "tabla_afectada": "CONSULTAS",
  "id_registro": "1",
  "campo_modificado": "estado_conversacion",
  "valor_anterior": "",
  "valor_nuevo": "inicio",
  "modificado_por": "n8n",
  "source_event": "whatsapp_inbound",
  "nivel": "info",
  "detalle": {
    "id_consulta": 1,
    "canal": "whatsapp",
    "id_contacto_externo": "+5491112345678",
    "fecha_in_tentativa": "2026-07-01",
    "fecha_out_tentativa": "2026-07-03",
    "personas_tentativa": 2
  }
}
```

### Cuando se reutiliza consulta existente

```json
{
  "tabla_afectada": "CONSULTAS",
  "id_registro": "1",
  "campo_modificado": "consulta_reutilizada",
  "valor_anterior": "",
  "valor_nuevo": "1",
  "modificado_por": "n8n",
  "source_event": "whatsapp_inbound",
  "nivel": "info",
  "detalle": {
    "id_consulta": 1,
    "canal": "whatsapp",
    "id_contacto_externo": "+5491112345678",
    "motivo": "consulta_activa_reciente_existente"
  }
}
```

### Cuando el input es inválido

**No se escribe LOG_CAMBIOS.**

---

## 10. Efectos secundarios

- Ninguno fuera de las escrituras documentadas en §8.
- No llama a otros workflows.
- No modifica el estado de ninguna cabaña ni bloquea disponibilidad.

---

## 11. Restricciones

| Restricción | Detalle |
|---|---|
| Idempotencia | Si existe una consulta activa del mismo `id_contacto_externo` con `updated_at` dentro de las últimas **24 horas** y estado estado no pertenece a `cerrada` / `derivada_a_humano`, se reutiliza sin crear duplicado. |
| Ventana de reutilización | 24 horas. Consultas activas pero más viejas generan una nueva consulta. |
| `id_consulta` | Calculado como `max(id_consulta) + 1`. ⚠️ Race condition posible en alta concurrencia. Para producción con carga alta, migrar a `CON-<timestamp>` o UUID. |
| Canal | Solo acepta `whatsapp`, `instagram`, `web`, `manual`. Cualquier otro valor retorna error sin escribir. |
| Fechas tentativas | Si se proveen ambas, `fecha_out_tentativa` debe ser estrictamente posterior a `fecha_in_tentativa`. |
| LOG en error | No se escribe LOG_CAMBIOS cuando el input es inválido. |

---

## 12. Notas para frontend / bot

- **Llamar siempre primero.** Antes de hacer cualquier otra acción (calcular precio,
  crear pre-reserva), asegurarse de tener un `id_consulta` válido.
- El campo `es_nueva` permite al bot saber si debe saludar o retomar una conversación
  existente.
- El campo `estado_conversacion` del output indica en qué punto estaba la conversación
  anterior si se reutilizó.
- Si `accion = "existente_reutilizada"`, el bot debería cargar el `contexto_json`
  de la consulta para retomar el hilo de la conversación.
- Las fechas tentativas son opcionales — se pueden pasar si el usuario las mencionó
  en el primer mensaje, pero no es obligatorio en el primer llamado.
- El campo `id_huesped` se puede omitir en el primer contacto (`null`) y actualizar
  más adelante cuando el contacto se identifique como huésped registrado.

---

## 13. Casos de prueba validados

### DEV

| # | Descripción | Input clave | Output esperado | ✅ |
|---|---|---|---|---|
| 1 | Consulta nueva con hoja vacía | `canal=whatsapp`, `id_contacto_externo=+5491112345678` | `es_nueva=true`, `id_consulta=1`, `accion=creada` | ✅ |
| 2 | Misma consulta — reutilización dentro de 24h | Mismo input que prueba 1 | `es_nueva=false`, `id_consulta=1`, `accion=existente_reutilizada` | ✅ |
| 3 | Segundo contacto distinto | `id_contacto_externo=+5491199999999` | `es_nueva=true`, `id_consulta=2`, `accion=creada` | ✅ |
| 4 | Canal inválido | `canal=telegram` | `ok=false`, `error=input_invalido`, sin escritura en Sheets | ✅ |

### TEST

| # | Descripción | Resultado | ✅ |
|---|---|---|---|
| 1-4 | Mismos casos que DEV con VITA_DELTA_TEST | Resultados idénticos | ✅ |
