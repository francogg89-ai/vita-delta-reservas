# Contrato técnico — `db_confirmar_reserva`

## 1. Propósito

Confirma definitivamente una reserva a partir de una PRE_RESERVA en `pago_en_revision`
y un PAGO en `en_revision`. Es el paso final del flujo de reservas antes de que
el huesped sea notificado y el equipo operativo comience a preparar la estadía.

**Hace:**
- Valida el input y verifica la existencia y estado de PRE_RESERVA y PAGO.
- Verifica que el PAGO corresponda a la PRE_RESERVA indicada.
- Detecta conflictos contra RESERVAS existentes confirmadas o activas en las mismas fechas y cabana.
- Crea una fila en RESERVAS con `estado = confirmada`.
- Actualiza `PRE_RESERVAS.estado` de `pago_en_revision` a `convertida`.
- Actualiza `PAGOS.estado` de `en_revision` a `confirmado`, y registra `id_reserva`, `validado_por` y `validado_en`.
- Escribe LOG_CAMBIOS (nivel `info` o `warning` si faltan montos).
- Llama a `db_recalcular_disponibilidad` al final para actualizar la cache.

**No hace:**
- No integra MercadoPago automatico.
- No envia WhatsApp ni notificaciones.
- No usa IA.
- No crea ni modifica HUESPEDES.
- No toca CONSULTAS.
- No calcula precio (monto_total y monto_sena vienen de la PRE_RESERVA, pueden estar vacios).
- No asigna encargado_semana automaticamente (diferido a calendario de turnos).
- No hace rollback transaccional si falla a mitad de escritura.

---

## 2. Estado

| Campo | Valor |
|---|---|
| Version validada | v1 |
| Archivo template | `Workflows/n8n/db_confirmar_reserva.template.json` |
| DEV | validado mayo 2026 |
| TEST | validado mayo 2026 |
| Concurrencia requerida | Max Concurrency = 1 |
| Disparador produccion | Webhook POST, llamada desde panel interno o ejecucion manual controlada |
| Disparador DEV/TEST | Manual Trigger con MANUAL_INPUT editable |

**Dependencias:**

| Dependencia | Requerido | Notas |
|---|---|---|
| Google Sheets | Si | PRE_RESERVAS, PAGOS, RESERVAS, LOG_CAMBIOS |
| `db_recalcular_disponibilidad` v8 | Si | Debe tener trigger "When Executed by Another Workflow" |

---

## 3. Input esperado

```json
{
  "id_prereserva": 8,
  "id_pago": 1,
  "validado_por": "Franco",
  "encargado_semana": "",
  "notas": "Pago verificado manualmente",
  "source_event": "manual"
}
```

| Campo | Tipo | Obligatorio | Descripcion |
|---|---|---|---|
| `id_prereserva` | `integer` | Si | FK a PRE_RESERVAS. Debe existir y estar en `pago_en_revision`. |
| `id_pago` | `integer` | No (recomendado) | FK a PAGOS. Si no viene, el workflow busca un unico pago `en_revision` asociado a la PRE_RESERVA. Si hay mas de uno, retorna `pago_duplicado_ambiguo`. |
| `validado_por` | `string` | Si | Quien confirma el pago. Ej: `Franco`, `Rodrigo`. Se registra en PAGOS y LOG_CAMBIOS. |
| `encargado_semana` | `string` | No | Operador asignado a la semana. Vacio en v1 — en produccion deberia asignarse automaticamente segun calendario de turnos. |
| `notas` | `string` | No | Texto libre. Se escribe en RESERVAS. |
| `source_event` | `string` | No | Origen del evento. Default: `manual`. |

---

## 4. Output exitoso

```json
{
  "ok": true,
  "id_reserva": 1,
  "id_prereserva": 8,
  "id_pago": 1,
  "estado_reserva": "confirmada",
  "estado_prereserva": "convertida",
  "estado_pago": "confirmado",
  "precio_pendiente": true,
  "monto_total": null,
  "monto_sena": null,
  "monto_saldo": null,
  "validado_por": "Franco",
  "recalculo_cache": "ok",
  "recalculo_error": null,
  "mensaje": "Reserva confirmada correctamente"
}
```

| Campo | Tipo | Descripcion |
|---|---|---|
| `ok` | boolean | `true` si la reserva fue confirmada. |
| `id_reserva` | integer | ID asignado en RESERVAS. |
| `estado_reserva` | string | Siempre `confirmada` en creacion exitosa. |
| `estado_prereserva` | string | Siempre `convertida` en creacion exitosa. |
| `estado_pago` | string | Siempre `confirmado` en creacion exitosa. |
| `precio_pendiente` | boolean | `true` si `monto_total` o `monto_sena` estan vacios en la PRE_RESERVA. No bloquea la confirmacion en v1. |
| `recalculo_cache` | `"ok"` o `"warning"` | `warning` si el recalculo fallo post-escritura. |
| `recalculo_error` | `string` o `null` | Mensaje de accion correctiva si `recalculo_cache = warning`. |

---

## 5. Outputs de error

**input_invalido** — no escribe nada:
```json
{ "ok": false, "error": "input_invalido", "detalle": ["validado_por es obligatorio en v1"] }
```

**prereserva_no_encontrada:**
```json
{ "ok": false, "error": "prereserva_no_encontrada", "detalle": ["id_prereserva 999 no existe en PRE_RESERVAS"] }
```

**prereserva_estado_invalido** — la PRE_RESERVA no esta en `pago_en_revision`:
```json
{ "ok": false, "error": "prereserva_estado_invalido", "estado_actual": "pendiente_pago", "detalle": ["..."] }
```

**pago_no_encontrado:**
```json
{ "ok": false, "error": "pago_no_encontrado", "detalle": ["id_pago 999 no existe en PAGOS"] }
```

**pago_estado_invalido** — el PAGO no esta en `en_revision`:
```json
{ "ok": false, "error": "pago_estado_invalido", "estado_actual": "confirmado", "detalle": ["..."] }
```

**pago_no_corresponde** — el PAGO es de otra PRE_RESERVA:
```json
{ "ok": false, "error": "pago_no_corresponde", "detalle": ["PAGO 1 corresponde a id_prereserva 5, no a 8"] }
```

**pago_duplicado_ambiguo** — mas de un pago `en_revision` sin `id_pago` en input:
```json
{
  "ok": false,
  "error": "pago_duplicado_ambiguo",
  "pagos_en_revision": [{ "id_pago": 1, "created_at": "..." }, { "id_pago": 2, "created_at": "..." }],
  "detalle": ["Hay 2 pagos en_revision para id_prereserva 8. Especificar id_pago en el input."]
}
```

**conflicto_reserva_existente** — ya hay una RESERVA confirmada/activa en las mismas fechas y cabana. No escribe nada:
```json
{
  "ok": false,
  "error": "conflicto_reserva_existente",
  "reserva_conflicto": { "id_reserva": 10, "fecha_checkin": "2026-07-10", "fecha_checkout": "2026-07-12", "estado": "confirmada" },
  "detalle": ["Ya existe una RESERVA (id=10) en estado 'confirmada' que se solapa con las fechas solicitadas."]
}
```

**recalculo_cache = warning** — reserva confirmada correctamente pero recalculo fallo:
```json
{
  "ok": true,
  "id_reserva": 1,
  "recalculo_cache": "warning",
  "recalculo_error": "db_recalcular_disponibilidad fallo despues de confirmar la reserva. Cache puede estar desactualizada. Ejecutar recalculo manual."
}
```

Si falla cualquier validacion antes de escribir, no se escribe nada en ninguna hoja.

---

## 6. Hojas que lee

| Hoja | Proposito | Puede estar vacia |
|---|---|---|
| `PRE_RESERVAS` | Verificar existencia, estado y extraer datos para crear RESERVA | No |
| `PAGOS` | Verificar existencia, estado y correspondencia | Si |
| `RESERVAS` | Detectar conflictos de solapamiento + calcular max id_reserva | Si |

---

## 7. Hojas que escribe

| Hoja | Operacion | Cuando |
|---|---|---|
| `RESERVAS` | Append 1 fila (24 columnas) | Solo si todas las validaciones pasan |
| `PRE_RESERVAS` | Update row por `id_prereserva` (estado, updated_at) | Despues de escribir RESERVAS |
| `PAGOS` | Update row por `id_pago` (estado, id_reserva, validado_por, validado_en, updated_at) | Despues de actualizar PRE_RESERVAS |
| `LOG_CAMBIOS` | Append 1 fila | Despues de actualizar PAGOS |

### Campos escritos en RESERVAS (24 columnas)

| Campo | Valor |
|---|---|
| `id_reserva` | `max(id_reserva) + 1` |
| `id_prereserva` | De la PRE_RESERVA (trazabilidad) |
| `id_cabana` | De la PRE_RESERVA |
| `id_huesped` | De la PRE_RESERVA (puede estar vacio) |
| `fecha_checkin` | `PRE_RESERVAS.fecha_in` |
| `fecha_checkout` | `PRE_RESERVAS.fecha_out` |
| `hora_checkin` | De la PRE_RESERVA |
| `hora_checkout` | De la PRE_RESERVA |
| `personas` | De la PRE_RESERVA |
| `estado` | `confirmada` |
| `canal_origen` | De la PRE_RESERVA |
| `id_tarifa_aplicada` | Vacio — motor de precios no implementado en v1 |
| `monto_total` | De la PRE_RESERVA (puede estar vacio) |
| `monto_sena` | De la PRE_RESERVA (puede estar vacio) |
| `monto_saldo` | `monto_total - monto_sena` si ambos existen, vacio si falta alguno |
| `mascotas` | Vacio en v1 |
| `detalle_mascotas` | Vacio en v1 |
| `ninos` | Vacio en v1 |
| `encargado_semana` | Del input (opcional, puede estar vacio) |
| `notas` | Del input o de la PRE_RESERVA |
| `created_by` | `input.validado_por` |
| `source_event` | Del input |
| `created_at` | Timestamp de ejecucion |
| `updated_at` | Timestamp de ejecucion |

### Campos actualizados en PRE_RESERVAS

| Campo | Valor |
|---|---|
| `estado` | `convertida` |
| `updated_at` | Timestamp de ejecucion |

### Campos actualizados en PAGOS

| Campo | Valor |
|---|---|
| `id_reserva` | ID de la nueva RESERVA |
| `estado` | `confirmado` |
| `validado_por` | Del input |
| `validado_en` | Timestamp de ejecucion |
| `updated_at` | Timestamp de ejecucion |

---

## 8. Subworkflows llamados

| Workflow | Cuando | Modo | continueOnFail |
|---|---|---|---|
| `db_recalcular_disponibilidad` | Al final, despues de escribir LOG_CAMBIOS | Sincrono | Si |

Si el recalculo falla, la RESERVA ya fue creada correctamente. Output retorna `recalculo_cache = warning`. Accion correctiva: ejecutar `db_recalcular_disponibilidad` manualmente.

---

## 9. LOG_CAMBIOS generado

Un unico registro por ejecucion exitosa:

```json
{
  "tabla_afectada": "RESERVAS",
  "id_registro": "1",
  "campo_modificado": "estado",
  "valor_anterior": "",
  "valor_nuevo": "confirmada",
  "modificado_por": "n8n",
  "source_event": "manual",
  "nivel": "info",
  "detalle": {
    "id_reserva": 1,
    "id_prereserva": 8,
    "id_pago": 1,
    "id_cabana": 1,
    "fecha_checkin": "2026-07-10",
    "fecha_checkout": "2026-07-12",
    "validado_por": "Franco",
    "precio_pendiente": false,
    "monto_total": 100000,
    "monto_sena": 50000,
    "monto_saldo": 50000
  }
}
```

Si `precio_pendiente = true`, el `nivel` pasa a `warning` y el detalle refleja los montos nulos. El workflow no se interrumpe por esto — es un aviso operativo para que el equipo revise los montos antes de cerrar la comunicacion comercial.

---

## 10. Reglas de negocio

**Condicion para confirmar:**
- `PRE_RESERVAS.estado = pago_en_revision`
- `PAGOS.estado = en_revision`
- `PAGOS.id_prereserva = input.id_prereserva`
- No hay solapamiento con RESERVAS en `confirmada` o `activa` para la misma cabana y rango de fechas

**Solapamiento de rangos (intervalo semiabierto):**
Dos rangos `[A, B)` y `[C, D)` se solapan si `A < D AND B > C`.
`fecha_checkout` es exclusiva — una reserva que termina el dia X no bloquea una nueva que empieza el mismo dia X.

**Montos:**
- `monto_total` y `monto_sena` se copian de la PRE_RESERVA. Pueden estar vacios.
- `monto_saldo = monto_total - monto_sena` si ambos estan presentes. Si falta alguno, queda vacio.
- `precio_pendiente = true` si alguno falta. No bloquea la confirmacion en v1.

**Estados resultantes:**

| Hoja | Campo | Antes | Despues |
|---|---|---|---|
| PRE_RESERVAS | estado | `pago_en_revision` | `convertida` |
| PAGOS | estado | `en_revision` | `confirmado` |
| RESERVAS | estado | — | `confirmada` (nueva fila) |

**encargado_semana:**
Opcional en v1. En produccion deberia resolverse automaticamente segun calendario de turnos (Franco / Rodrigo) o asignacion operativa.

---

## 11. Fuera de alcance en v1

| Funcionalidad | Estado |
|---|---|
| MercadoPago automatico | Diferido |
| WhatsApp / notificaciones | Diferido |
| IA | Diferido |
| Creacion o modificacion de HUESPEDES | Diferido |
| Validacion contra CONSULTAS | Diferido |
| Calculo de precios / id_tarifa_aplicada | Diferido — motor de precios |
| Asignacion automatica de encargado_semana | Diferido — calendario de turnos |
| Rollback transaccional | Diferido — requiere DB relacional |
| Calendario operativo / VISTA_CALENDARIO | Diferido |
| Notificacion automatica al huesped | Diferido |

---

## 12. Riesgos conocidos

| Riesgo | Severidad | Mitigacion actual |
|---|---|---|
| Google Sheets no es transaccional | Alta a escala | Si falla despues de crear RESERVA pero antes de actualizar PRE_RESERVAS o PAGOS, los estados quedan inconsistentes. Detectar por LOG_CAMBIOS ausente. Solucion definitiva: DB relacional. |
| `id_reserva = max + 1` con posible race condition | Media | Max Concurrency = 1 en n8n. Solucion definitiva: UUID o DB transaccional. |
| Fallo del recalculo final post-escritura | Media | `continueOnFail: true`. Output retorna `recalculo_cache = warning`. Accion: ejecutar recalculo manual. |
| `precio_pendiente = true` permite confirmar sin montos cerrados | Baja | El LOG registra el warning. El equipo debe revisar montos antes de comunicar al huesped. |

---

## 13. Casos de prueba validados

| # | Caso | Resultado esperado |
|---|---|---|
| 1 | Confirmacion exitosa con PRE_RESERVA en `pago_en_revision` y PAGO en `en_revision` | `ok: true`, RESERVA creada `confirmada`, PRE_RESERVA → `convertida`, PAGO → `confirmado`, cache recalculada |
| 2 | PRE_RESERVA inexistente | `prereserva_no_encontrada` |
| 3 | PRE_RESERVA en estado incorrecto (ej: `pendiente_pago`) | `prereserva_estado_invalido` |
| 4 | PAGO inexistente | `pago_no_encontrado` |
| 5 | PAGO en estado incorrecto (ej: `confirmado`) | `pago_estado_invalido` |
| 6 | PAGO que corresponde a otra PRE_RESERVA | `pago_no_corresponde` |
| 7 | Sin `id_pago` en input y hay mas de un pago `en_revision` | `pago_duplicado_ambiguo` con lista de pagos candidatos |
| 8 | Conflicto con RESERVA confirmada en mismas fechas y cabana | `conflicto_reserva_existente` — no escribe nada |
| 9 | PRE_RESERVA sin `monto_total` ni `monto_sena` | `ok: true`, `precio_pendiente: true`, LOG con `nivel: warning` |
| 10 | Recalculo final fallido | `ok: true`, `recalculo_cache: warning`, RESERVA y estados correctamente actualizados |

Todos los casos validados en DEV y TEST.

---

## 14. Notas para frontend / bot / operacion

- Este workflow no debe exponerse al huesped como accion automatica. En v1 lo ejecuta un operador humano (Franco o Rodrigo) despues de revisar el comprobante de pago.
- El huesped recibe confirmacion definitiva solo cuando este workflow devuelve `ok: true`.
- Si `precio_pendiente = true`, el equipo debe revisar y cerrar los montos antes de la comunicacion comercial final.
- Este workflow es el paso posterior a `db_registrar_pago`. El flujo completo es: `db_crear_consulta` → `db_crear_prereserva` → `db_registrar_pago` → `db_confirmar_reserva`.
- El proximo sistema relacionado es `sistema_expirar_prereservas` (automatizacion para liberar pre-reservas vencidas sin pago) y futuras automatizaciones de notificacion y calendario operativo.
