# Contrato técnico — `db_registrar_pago`

## 1. Propósito

Registra un pago reportado manualmente por el huésped para una PRE_RESERVA existente,
dejando el pago en revisión manual para que Franco o Rodrigo lo verifiquen.

**Hace:**
- Valida el input y la existencia de la PRE_RESERVA.
- Verifica que la PRE_RESERVA esté en `pendiente_pago` y no vencida.
- Detecta pagos duplicados para la misma pre-reserva.
- Crea una fila en PAGOS con `estado = en_revision`.
- Actualiza PRE_RESERVAS: `estado → pago_en_revision`, incrementa `intentos_pago`,
  copia referencia de pago, actualiza `updated_at`.
- Escribe LOG_CAMBIOS.
- Llama a `db_recalcular_disponibilidad` al final para que la cache refleje
  que la pre-reserva ahora tiene `pago_en_revision` (bloquea aunque esté vencida).

**No hace:**
- No confirma la reserva definitiva.
- No crea RESERVA.
- No integra MercadoPago automático.
- No envía notificaciones ni WhatsApp.
- No valida si el monto reportado coincide con el esperado (solo registra ambos).
- No implementa bypass de pago duplicado en v1.

---

## 2. Estado

| Campo | Valor |
|---|---|
| Versión validada | v1 |
| Archivo template | `Workflows/n8n/db_registrar_pago.template.json` |
| DEV | validado |
| TEST | validado |
| Concurrencia | Sin restricción crítica (no hay race condition de disponibilidad) |
| Disparador producción | Webhook POST o llamada desde bot/frontend |
| Disparador DEV/TEST | Manual Trigger con MANUAL_INPUT editable |

**Dependencias:**

| Dependencia | Requerido | Notas |
|---|---|---|
| Google Sheets | Si | PRE_RESERVAS, PAGOS, LOG_CAMBIOS |
| `db_recalcular_disponibilidad` | Si | Debe tener trigger "When Executed by Another Workflow" |

---

## 3. Input esperado

```json
{
  "id_prereserva": 1,
  "monto_reportado": 50000,
  "metodo_pago": "transferencia_mp",
  "referencia_pago": "TEST-TRANSFERENCIA-001",
  "comprobante_url": "https://example.com/comprobante.jpg",
  "fecha_pago_reportada": "",
  "notas": "Pago de seña",
  "source_event": "manual"
}
```

| Campo | Tipo | Obligatorio | Descripcion |
|---|---|---|---|
| `id_prereserva` | `integer` | Si | FK a PRE_RESERVAS. Debe existir y estar en `pendiente_pago`. |
| `monto_reportado` | `float` | Si | Monto que el huesped reporta haber pagado. Debe ser mayor a 0. |
| `metodo_pago` | `string` | Si | Valores validos: `mp_link`, `transferencia_mp`, `transferencia_bancaria`, `tarjeta`, `efectivo`, `cripto`. |
| `referencia_pago` | `string` | No | Referencia externa del pago (ID de transferencia, comprobante MP, etc.). Se copia a `PAGOS.referencia_externa` y `PRE_RESERVAS.referencia_mp`. |
| `comprobante_url` | `string` | No | URL del comprobante de pago. |
| `fecha_pago_reportada` | `string ISO 8601` | No | Fecha/hora del pago segun el huesped. Si viene vacia, se usa `now`. |
| `notas` | `string` | No | Texto libre. |
| `source_event` | `string` | No | Origen del evento. Default: `manual`. |

---

## 4. Output exitoso

```json
{
  "ok": true,
  "id_pago": 1,
  "id_prereserva": 1,
  "estado_pago": "en_revision",
  "estado_prereserva": "pago_en_revision",
  "requiere_revision_manual": true,
  "recalculo_cache": "ok",
  "recalculo_error": null,
  "mensaje": "Pago registrado para revisión manual"
}
```

| Campo | Tipo | Descripcion |
|---|---|---|
| `ok` | boolean | `true` si el pago fue registrado. |
| `id_pago` | integer | ID asignado en PAGOS. |
| `estado_pago` | string | Siempre `en_revision` en creacion exitosa. |
| `estado_prereserva` | string | Siempre `pago_en_revision` en creacion exitosa. |
| `requiere_revision_manual` | boolean | Siempre `true` en v1. |
| `recalculo_cache` | `"ok"` o `"warning"` | `warning` si el recalculo fallo post-escritura. |
| `recalculo_error` | `string` o `null` | Mensaje de accion correctiva si `recalculo_cache = warning`. |

---

## 5. Outputs de error

**input_invalido** — no escribe nada:
```json
{ "ok": false, "error": "input_invalido", "detalle": ["monto_reportado debe ser mayor a 0"] }
```

**prereserva_no_encontrada** — `id_prereserva` no existe en PRE_RESERVAS:
```json
{ "ok": false, "error": "prereserva_no_encontrada", "detalle": ["id_prereserva 999 no existe en PRE_RESERVAS"] }
```

**prereserva_estado_invalido** — la PRE_RESERVA existe pero no esta en `pendiente_pago`:
```json
{ "ok": false, "error": "prereserva_estado_invalido", "estado_actual": "pago_en_revision", "detalle": ["..."] }
```

**prereserva_vencida** — `estado = pendiente_pago` pero `expira_en <= now`:
```json
{ "ok": false, "error": "prereserva_vencida", "expira_en": "2026-05-01T10:00:00Z", "detalle": ["..."] }
```

**pago_duplicado_posible** — ya existe un pago con `estado IN ('en_revision', 'confirmado')` para esa pre-reserva:
```json
{
  "ok": false,
  "error": "pago_duplicado_posible",
  "pago_existente": { "id_pago": 1, "estado": "en_revision", "medio_pago": "transferencia_mp", "created_at": "..." },
  "detalle": ["..."]
}
```

**recalculo_cache = warning** — pago registrado correctamente pero recalculo fallo:
```json
{
  "ok": true,
  "id_pago": 1,
  "recalculo_cache": "warning",
  "recalculo_error": "db_recalcular_disponibilidad falló después de registrar el pago..."
}
```

---

## 6. Hojas que lee

| Hoja | Proposito | Puede estar vacia |
|---|---|---|
| `PRE_RESERVAS` | Verificar existencia, estado, vencimiento y extraer `monto_sena` | No |
| `PAGOS` | Detectar pago duplicado + calcular `id_pago = max + 1` | Si |

---

## 7. Hojas que escribe

| Hoja | Operacion | Cuando |
|---|---|---|
| `PAGOS` | Append 1 fila (22 columnas) | Solo si todas las verificaciones pasan |
| `PRE_RESERVAS` | Update row por `id_prereserva` (4 campos) | Despues de escribir PAGOS |
| `LOG_CAMBIOS` | Append 1 fila | Despues de actualizar PRE_RESERVAS |

### Campos escritos en PAGOS (22 columnas)

| Campo | Valor |
|---|---|
| `id_pago` | `max(id_pago) + 1` |
| `id_prereserva` | Del input |
| `id_reserva` | Vacio — se llena en `db_confirmar_reserva` |
| `tipo` | `sena` (default v1) |
| `medio_pago` | Del input (`metodo_pago`) |
| `proveedor` | Vacio en v1 |
| `cuenta_destino` | Vacio en v1 |
| `monto_esperado` | `PRE_RESERVAS.monto_sena` de la pre-reserva existente |
| `monto_recibido` | Del input (`monto_reportado`) — no se valida contra `monto_esperado` |
| `moneda` | `ARS` (default v1) |
| `estado` | `en_revision` |
| `es_automatico` | `FALSE` — siempre manual en v1 |
| `comprobante_url` | Del input (opcional) |
| `referencia_externa` | Del input (`referencia_pago`, opcional) |
| `tx_hash` | Vacio en v1 |
| `validado_por` | Vacio — lo completa el operador al confirmar |
| `validado_en` | Vacio |
| `motivo_rechazo` | Vacio |
| `notas` | Del input (opcional) |
| `source_event` | Del input |
| `created_at` | Timestamp de ejecucion |
| `updated_at` | Timestamp de ejecucion |

### Campos actualizados en PRE_RESERVAS (4 campos por id_prereserva)

| Campo | Valor |
|---|---|
| `estado` | `pago_en_revision` |
| `intentos_pago` | `intentos_pago_actual + 1` |
| `referencia_mp` | Del input (`referencia_pago`, puede quedar vacio) |
| `updated_at` | Timestamp de ejecucion |

---

## 8. Subworkflows llamados

| Workflow | Cuando | Modo |
|---|---|---|
| `db_recalcular_disponibilidad` | Despues de escribir LOG_CAMBIOS | Sincrono con `continueOnFail: true` |

El recalculo es necesario porque `pago_en_revision` bloquea disponibilidad
aunque `expira_en` este vencido. Sin recalcular, la cache podria mostrar
fechas disponibles que en realidad estan bloqueadas por el pago en revision.

---

## 9. LOG_CAMBIOS generado

```json
{
  "tabla_afectada": "PRE_RESERVAS",
  "id_registro": "1",
  "campo_modificado": "estado",
  "valor_anterior": "pendiente_pago",
  "valor_nuevo": "pago_en_revision",
  "modificado_por": "n8n",
  "source_event": "manual",
  "nivel": "info",
  "detalle": {
    "id_pago": 1,
    "id_prereserva": 1,
    "medio_pago": "transferencia_mp",
    "monto_recibido": 50000,
    "monto_esperado": 50000,
    "referencia_externa": "TEST-TRANSFERENCIA-001",
    "requiere_revision_manual": true
  }
}
```

---

## 10. Reglas de negocio

**Condicion para aceptar el pago:**
- `PRE_RESERVAS.estado = pendiente_pago`
- `PRE_RESERVAS.expira_en > ahora`
- No existe pago previo con `estado IN ('en_revision', 'confirmado')` para esa pre-reserva

**Vencimiento:**
- Si `estado = pendiente_pago` y `expira_en <= ahora` → `prereserva_vencida`.
- Una PRE_RESERVA en `pago_en_revision` NO puede recibir un segundo pago a traves de este workflow (la verificacion de estado lo rechaza).

**Deteccion de duplicado:**
- Estados bloqueantes para duplicado: `en_revision`, `confirmado`.
- Estado `rechazado` NO bloquea — permite reintentar despues de un rechazo.
- No hay bypass de duplicado en v1. Si el operador necesita forzar, debe hacerlo manualmente en Sheets.

**Monto:**
- `monto_recibido` = lo que el huesped reporta.
- `monto_esperado` = `PRE_RESERVAS.monto_sena` leido de la pre-reserva.
- No se valida si coinciden — esa decision queda para el operador durante la revision manual.

---

## 11. Fuera de alcance en v1

| Funcionalidad | Estado |
|---|---|
| MercadoPago automatico (webhook) | Diferido |
| Validacion de monto recibido vs esperado | Diferido |
| Bypass de pago duplicado | Diferido |
| Confirmacion de reserva definitiva | Diferido — `db_confirmar_reserva` |
| Creacion de RESERVA | Diferido |
| WhatsApp / notificaciones | Diferido |
| Motor de precios | Diferido |

---

## 12. Riesgos conocidos

| Riesgo | Severidad | Mitigacion |
|---|---|---|
| `id_pago = max + 1` con posible race condition | Baja (concurrencia baja en v1) | Max + 1 es suficiente. Para alta concurrencia migrar a UUID. |
| Fallo del recalculo post-escritura | Media | `continueOnFail: true`. Output retorna `recalculo_cache = warning`. Accion: ejecutar recalculo manual. |
| Google Sheets no es transaccional | Alta a escala | Si falla `Actualizar PRE_RESERVAS` despues de `Escribir PAGOS`, quedan inconsistentes. Detectar por LOG_CAMBIOS ausente. Solucion definitiva: DB relacional. |

---

## 13. Casos de prueba

| # | Caso | Resultado esperado |
|---|---|---|
| 1 | Pago exitoso sobre pre-reserva valida | `ok: true`, fila en PAGOS, PRE_RESERVAS en `pago_en_revision`, cache recalculada |
| 2 | `id_prereserva` inexistente | `prereserva_no_encontrada` |
| 3 | PRE_RESERVA ya en `pago_en_revision` | `prereserva_estado_invalido` |
| 4 | PRE_RESERVA vencida (`expira_en` en el pasado) | `prereserva_vencida` |
| 5 | Segunda ejecucion sobre PRE_RESERVA ya en `pago_en_revision` (flujo normal post-pago exitoso) | `prereserva_estado_invalido` — el estado ya no es `pendiente_pago` |
| 6 | PRE_RESERVA aun en `pendiente_pago` pero PAGOS ya tiene un pago `en_revision` o `confirmado` | `pago_duplicado_posible` con datos del pago existente |
| 7 | `monto_reportado = 0` | `input_invalido` |
| 8 | `metodo_pago` invalido (ej: `otro`) | `input_invalido` |
| 9 | Verificar columna `updated_at` en PAGOS | Timestamp correcto en columna V de la hoja |

---

## 14. Notas para frontend / bot

- Este workflow **no confirma la reserva**. Informar al huesped que el pago queda pendiente de verificacion.
- El huesped debe saber que la reserva esta asegurada solo cuando reciba confirmacion explicita de Franco o Rodrigo.
- Si `recalculo_cache = warning`, es un aviso operativo interno — no impacta al huesped.
- El siguiente paso despues de la verificacion manual es `db_confirmar_reserva` (pendiente de implementacion).
- Una PRE_RESERVA en `pago_en_revision` sigue bloqueando las fechas incluso si `expira_en` esta vencido — el bloqueo no se libera automaticamente hasta que el pago sea rechazado o cancelado.
