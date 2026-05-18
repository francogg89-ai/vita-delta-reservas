# Contrato técnico — `db_crear_prereserva`

## 1. Propósito

Crea una pre-reserva temporal para una cabaña en un rango de fechas, bloqueando
la disponibilidad de forma provisional hasta que se confirme el pago.

**Hace:**
- Valida el input (cabaña, fechas, personas, canales).
- Verifica disponibilidad en dos capas: DISPONIBILIDAD_CACHE + fuentes directas.
- Valida que la cabaña exista, esté activa, no esté bloqueada operativamente y
  que la capacidad no sea excedida.
- Crea una fila en PRE_RESERVAS con `estado = pendiente_pago`.
- Calcula `expira_en` desde `CONFIGURACION_GENERAL.prereserva_expiracion_minutos`
  (default: 60 minutos).
- Escribe LOG_CAMBIOS en todos los casos relevantes.
- Llama a `db_recalcular_disponibilidad` como subworkflow síncrono para que
  DISPONIBILIDAD_CACHE refleje el bloqueo inmediatamente.

**No hace:**
- No confirma reserva definitiva.
- No registra pagos.
- No llama a MercadoPago.
- No envía mensajes de WhatsApp.
- No calcula precio (monto_total/monto_sena son opcionales en v2).
- No valida `id_consulta` contra la hoja CONSULTAS (diferido a v3).

---

## 2. Estado

| Campo | Valor |
|---|---|
| Versión validada | v2 |
| Archivo template | `Workflows/n8n/db_crear_prereserva.template.json` |
| DEV | validado mayo 2026 |
| TEST | validado mayo 2026 |
| Concurrencia requerida | Max Concurrency = 1 |
| Disparador producción | Webhook POST o llamada desde bot/frontend |
| Disparador DEV/TEST | Manual Trigger con MANUAL_INPUT editable |

**Dependencias:**

| Dependencia | Requerido | Notas |
|---|---|---|
| Google Sheets | Si | CABAÑAS, CONFIGURACION_GENERAL, DISPONIBILIDAD_CACHE, PRE_RESERVAS, RESERVAS, BLOQUEOS, LOG_CAMBIOS |
| `db_recalcular_disponibilidad` v8 | Si | Debe tener trigger "When Executed by Another Workflow" |

---

## 3. Input esperado

```json
{
  "id_consulta": 1,
  "id_cabana": 1,
  "id_huesped": null,
  "fecha_in": "2026-07-10",
  "fecha_out": "2026-07-12",
  "hora_checkin": "",
  "hora_checkout": "",
  "personas": 2,
  "monto_total": null,
  "monto_sena": null,
  "canal_pago_esperado": "transferencia_bancaria",
  "canal_origen": "manual",
  "notas": "",
  "source_event": "whatsapp_inbound"   
}
```

| Campo | Tipo | Obligatorio | Descripcion |
|---|---|---|---|
| `id_consulta` | `integer/null` | No | FK a CONSULTAS. No validado contra Sheets en v2. |
| `id_cabana` | `integer` | Si | ID de la cabana solicitada. Si no existe en `CABAÑAS`, retorna `input_invalido`. |
| `id_huesped` | `integer/null` | No | FK a HUESPEDES. Sin lookup en v2. |
| `fecha_in` | `string YYYY-MM-DD` | Si | Check-in. Inclusive. |
| `fecha_out` | `string YYYY-MM-DD` | Si | Check-out. Exclusiva. Debe ser posterior a fecha_in. |
| `hora_checkin` | `string HH:MM` o vacio | No | Vacio = calcular segun dia (domingo 18:00, resto 13:00). |
| `hora_checkout` | `string HH:MM` o vacio | No | Vacio = usar hora_checkout_default de CONFIGURACION_GENERAL. |
| `personas` | `integer` | Si | Debe ser menor o igual a CABAÑAS.capacidad_max. |
| `monto_total` | `float/null` | No | Si es null, precio_pendiente = true en el output. |
| `monto_sena` | `float/null` | No | Si es null, precio_pendiente = true en el output. |
| `canal_pago_esperado` | `string` | No | Default: transferencia_bancaria. Validos: mp_link, transferencia_bancaria, transferencia_mp, cripto, efectivo. |
| `canal_origen` | `string` | Si | Validos: whatsapp, instagram, web, manual. |
| `notas` | `string` | No | Texto libre. |
| `source_event` | `string` | No | Origen del evento. Default: `manual`. En pruebas puede usarse `manual_test` o `manual_dev` como ejemplo (editable en MANUAL_INPUT). |

---

## 4. Output exitoso

```json
{
  "ok": true,
  "id_prereserva": 1,
  "estado": "pendiente_pago",
  "expira_en": "2026-07-10T14:23:00.000Z",
  "id_consulta": 1,
  "id_cabana": 1,
  "fecha_in": "2026-07-10",
  "fecha_out": "2026-07-12",
  "personas": 2,
  "hora_checkin": "13:00",
  "hora_checkout": "10:00",
  "precio_pendiente": true,
  "monto_total": null,
  "monto_sena": null,
  "source_event": "manual",   // editable segun entorno
  "recalculo_cache": "ok",
  "recalculo_error": null
}
```

| Campo | Tipo | Descripcion |
|---|---|---|
| `ok` | boolean | true si la pre-reserva fue creada. |
| `id_prereserva` | integer | ID asignado. |
| `estado` | string | Siempre pendiente_pago en creacion exitosa. |
| `expira_en` | string ISO 8601 | Timestamp de vencimiento. |
| `precio_pendiente` | boolean | true si monto_total o monto_sena son null. |
| `recalculo_cache` | "ok" o "warning" | warning si el subworkflow fallo post-escritura. |
| `recalculo_error` | string o null | Mensaje de accion correctiva si recalculo_cache = warning. |

---

## 5. Outputs de error

**input_invalido** — no escribe nada en Sheets:
```json
{ "ok": false, "error": "input_invalido", "detalle": ["fecha_out debe ser posterior a fecha_in"] }
```

**input_invalido** — si id_cabana no existe en CABAÑAS (ademas de los casos de validacion de campos):
```json
{ "ok": false, "error": "input_invalido", "detalle": ["id_cabana 99 no existe en CABAÑAS"] }
```

**cabana_no_disponible** — cabana inactiva o bloqueada operativamente (existe pero no esta disponible para reservar):
```json
{ "ok": false, "error": "cabana_no_disponible", "detalle": ["Cabana 1 esta bloqueada operativamente"] }
```

**capacidad_excedida** — personas supera capacidad_max:
```json
{ "ok": false, "error": "capacidad_excedida", "detalle": ["personas=5 excede capacidad_max=4"] }
```

**no_disponible** — Capa 1 detecta fechas bloqueadas, no escribe nada:
```json
{
  "ok": false,
  "error": "no_disponible",
  "motivo": "Fechas bloqueadas segun DISPONIBILIDAD_CACHE",
  "conflictos": [{ "fecha": "2026-07-10", "estado": "ocupada", "fuente": "DISPONIBILIDAD_CACHE" }]
}
```

**no_disponible_conflicto_detectado** — Capa 1 paso pero Capa 2 detecto conflicto. No escribe PRE_RESERVA. Si escribe LOG_CAMBIOS nivel warning:
```json
{ "ok": false, "error": "no_disponible_conflicto_detectado", "conflictos": [...] }
```

**recalculo_cache = warning** — PRE_RESERVA creada correctamente pero recalculo fallo. Cache puede estar desactualizada. Ejecutar db_recalcular_disponibilidad manualmente:
```json
{ "ok": true, "id_prereserva": 1, "recalculo_cache": "warning", "recalculo_error": "..." }
```

---

## 6. Hojas que lee

| Hoja | Proposito | Puede estar vacia |
|---|---|---|
| `CABAÑAS` | Validar existencia, activa, bloqueada, capacidad_max | No |
| CONFIGURACION_GENERAL | hora_checkin_default, hora_checkin_domingo, hora_checkout_default, prereserva_expiracion_minutos | No |
| DISPONIBILIDAD_CACHE | Verificacion Capa 1 | No — debe tener las 300 filas del ciclo |
| PRE_RESERVAS | Verificacion Capa 2 + calcular max id_prereserva | Si |
| RESERVAS | Verificacion Capa 2 | Si |
| BLOQUEOS | Verificacion Capa 2 | Si |

---

## 7. Hojas que escribe

| Hoja | Operacion | Cuando |
|---|---|---|
| PRE_RESERVAS | Append 1 fila | Solo cuando ambas capas pasan |
| LOG_CAMBIOS | Append 1 fila | Al crear PRE_RESERVA (nivel info) o al detectar conflicto en Capa 2 (nivel warning) |

---

## 8. Subworkflows llamados

| Workflow | Cuando | Modo | continueOnFail |
|---|---|---|---|
| `db_recalcular_disponibilidad` | Al inicio, antes de leer DISPONIBILIDAD_CACHE | Sincrono | Si — si falla, no se crea la PRE_RESERVA |
| `db_recalcular_disponibilidad` | Al final, despues de escribir PRE_RESERVAS y LOG_CAMBIOS | Sincrono | Si — si falla, PRE_RESERVA ya fue creada; output retorna `recalculo_cache = warning` |

**Recalculo inicial (antes de verificar disponibilidad):**
El workflow recalcula la cache antes de consultarla. Esto garantiza que pre-reservas
vencidas en `pendiente_pago` ya no bloquen disponibilidad al momento de la verificacion.
Si el recalculo inicial falla, el workflow retorna `error: recalculo_inicial_fallido`
y no crea la PRE_RESERVA — no se verifica contra cache potencialmente desactualizada.

**Recalculo final (despues de crear la PRE_RESERVA):**
Actualiza la cache para que refleje el nuevo bloqueo de la PRE_RESERVA recien creada.
Si falla, la PRE_RESERVA ya existe correctamente en Sheets, pero la cache puede estar
desactualizada. Output retorna `recalculo_cache = warning`.

**Notas criticas:**
- `db_recalcular_disponibilidad` debe tener un trigger "When Executed by Another Workflow" conectado al mismo nodo inicial que el Manual Trigger. Sin este trigger n8n no puede llamarlo como subworkflow.
- La version actual v8 ejecuta recalculo COMPLETO: limpia DISPONIBILIDAD_CACHE!A2:R y reescribe las 300 filas.
- `db_crear_prereserva` NO envia `id_cabanas` ni `fechas` al subworkflow. Enviarlo con scope parcial borraria todas las filas y escribiria solo las del rango solicitado.
- Cuando exista una version de `db_recalcular_disponibilidad` con recalculo parcial real, actualizar ambos nodos de recalculo para enviar scope especifico.

---

## 9. LOG_CAMBIOS generado

Al crear PRE_RESERVA exitosamente: nivel info, campo_modificado = estado, valor_nuevo = pendiente_pago. Detalle incluye id_prereserva, id_cabana, fechas, expira_en, precio_pendiente y minutos_expiracion.

Al detectar conflicto en Capa 2: nivel warning, campo_modificado = verificacion_capa2, id_registro = N/A. Detalle incluye motivo, id_cabana, fechas y array de conflictos.

---

## 10. Reglas de disponibilidad

Intervalo semiabierto [fecha_in, fecha_out): fecha_in inclusive, fecha_out exclusiva. El dia de salida no ocupa noche. Una reserva JUE-VIE ocupa solo la noche del jueves.

Estados de DISPONIBILIDAD_CACHE:

| Estado | Bloquea |
|---|---|
| ocupada | Si |
| bloqueada | Si |
| limite_escalonamiento | Si |
| disponible | No |
| checkout_disponible | No — la noche esta libre |

Fuentes directas que bloquean en Capa 2:

| Fuente | Condicion |
|---|---|
| RESERVAS | estado IN (confirmada, activa) + solapamiento de rango |
| PRE_RESERVAS | estado = `pendiente_pago` + expira_en > ahora + solapamiento de rango |
| PRE_RESERVAS | estado = `pago_en_revision` + solapamiento de rango (bloquea siempre, sin verificar expira_en) |
| BLOQUEOS | activo = TRUE + solapamiento de rango [fecha_desde, fecha_hasta) |

Deteccion de solapamiento: rangoA_in menor que rangoB_out AND rangoA_out mayor que rangoB_in.

---

## 11. Reglas de vencimiento

- expira_en = created_at + prereserva_expiracion_minutos × 60 segundos.
- Si la clave no existe en CONFIGURACION_GENERAL o el valor no es numero valido, se usa 60 minutos como default.
- Las pre-reservas con expira_en menor o igual a ahora no bloquean disponibilidad.
- La expiracion automatica de pre-reservas vencidas es responsabilidad de sistema_expirar_prereservas (pendiente de implementacion).

---

## 12. Fuera de alcance en v2

| Funcionalidad | Estado |
|---|---|
| Validar id_consulta contra hoja CONSULTAS | Diferido a v3 |
| Calculo real de precio | Diferido — requiere motor de precios |
| MercadoPago | Diferido |
| Registro de pago | Diferido |
| Confirmacion de reserva definitiva | Diferido |
| WhatsApp | Diferido |
| Bot conversacional | Diferido |
| OVERRIDES_OPERATIVOS | Diferido |
| Escalonamiento automatico de check-in | Diferido |
| Recalculo parcial de disponibilidad | Diferido — requiere nueva version de db_recalcular_disponibilidad |

---

## 13. Riesgos conocidos

| Riesgo | Severidad | Mitigacion actual |
|---|---|---|
| id_prereserva usa max + 1 con posible race condition | Media | Concurrencia = 1. Solucion definitiva: UUID o DB transaccional. |
| Fallo del recalculo inicial — no crea la PRE_RESERVA | Baja | `continueOnFail: true` + IF evalua error. Output retorna `recalculo_inicial_fallido`. Accion: reintentar o ejecutar recalculo manual. |
| No hay rollback si falla el recalculo final post-escritura | Media | `continueOnFail: true`. Output retorna `recalculo_cache = warning`. Accion: ejecutar recalculo manual. |
| Google Sheets no es transaccional | Alta a escala | Aceptado para DEV/TEST. Solucion definitiva: DB relacional. |
| Capa 1 puede estar desactualizada hasta el proximo recalculo exitoso | Baja | El recalculo inicial al comienzo del workflow reduce este riesgo. Capa 2 verifica directamente contra RESERVAS, PRE_RESERVAS y BLOQUEOS antes de escribir. |

---

## 14. Casos de prueba validados

| # | Caso | Resultado esperado |
|---|---|---|
| 1 | Pre-reserva exitosa en fecha libre | ok: true, fila en PRE_RESERVAS, cache recalculada |
| 2 | Repeticion misma fecha | ok: false, error: no_disponible |
| 3 | Superposicion parcial de fechas | ok: false, error: no_disponible |
| 4 | Entrada el dia de checkout | ok: true — checkout_disponible no bloquea |
| 5 | Capacidad excedida | ok: false, error: capacidad_excedida |
| 6 | Fecha invalida (out anterior a in) | ok: false, error: input_invalido |
| 7 | Domingo con hora_checkin vacia | hora_checkin = 18:00 en PRE_RESERVAS |
| 8 | Recalculo post-creacion | DISPONIBILIDAD_CACHE refleja ocupada en fechas del rango |
| 9 | PRE_RESERVA con pago_en_revision y expira_en vencido en las fechas solicitadas | ok: false, error: no_disponible — pago_en_revision bloquea siempre |

Todos los casos validados en DEV y TEST.

---

## 15. Notas para frontend / bot

- Este workflow crea un bloqueo temporal, no una reserva definitiva. El frontend y el bot deben comunicar al usuario que la reserva esta sujeta a pago y confirmacion.
- expira_en indica hasta cuando esta reservado el slot. Mostrar cuenta regresiva si aplica.
- Si precio_pendiente = true, el precio aun no fue calculado. No mostrar monto al usuario hasta tener precio real.
- Si recalculo_cache = warning, la cache puede estar desactualizada por un tiempo breve. Para el usuario final no cambia nada — la pre-reserva existe y bloquea. El warning es operativo, no de negocio.
- El siguiente paso en el flujo es `db_registrar_pago` (validado en DEV y TEST). Llamarlo cuando el huesped reporte haber enviado el pago.
- No comunicar al usuario que la reserva esta confirmada hasta que `db_confirmar_reserva` complete exitosamente.
