# Contrato técnico — `sistema_expirar_prereservas`

## 1. Propósito

Marca automáticamente como vencidas las PRE_RESERVAS que quedaron en `pendiente_pago`
y cuyo `expira_en` ya pasó. Es un workflow de limpieza operativa que permite ordenar
el estado operativo de pre-reservas que nunca recibieron pago y mantener limpia la trazabilidad del sistema.

**Hace:**
- Lee PRE_RESERVAS completas.
- Detecta las que tienen `estado = pendiente_pago` y `expira_en <= ahora`.
- Actualiza `estado → vencida` y `updated_at`.
- Escribe un LOG_CAMBIOS por cada PRE_RESERVA vencida.
- Llama a `db_recalcular_disponibilidad` al final, solo si hubo cambios.
- Soporta modo `dry_run` para detectar sin escribir.

**No hace:**
- No toca `pago_en_revision` — aunque `expira_en` esté vencido.
- No toca `convertida`, `vencida`, `cancelada` ni cualquier otro estado.
- No toca PAGOS, RESERVAS ni CONSULTAS.
- No toca DISPONIBILIDAD_CACHE directamente.
- No elimina filas.
- No envía WhatsApp ni notificaciones.
- No usa IA.
- No integra MercadoPago.

---

## 2. Estado

| Campo | Valor |
|---|---|
| Version validada | v1 |
| Archivo template | `Workflows/n8n/sistema_expirar_prereservas.template.json` |
| DEV | validado mayo 2026 |
| TEST | validado mayo 2026 |
| Concurrencia requerida | Max Concurrency = 1 recomendado |
| Disparador produccion | Schedule Trigger diario o ejecucion manual controlada |
| Disparador DEV/TEST | Manual Trigger; Schedule configurado pero recomendado inactivo |

**Dependencias:**

| Dependencia | Requerido | Notas |
|---|---|---|
| Google Sheets | Si | PRE_RESERVAS, LOG_CAMBIOS |
| `db_recalcular_disponibilidad` v8 | Si — si hay cambios | Debe tener trigger "When Executed by Another Workflow". Solo se llama si `expiradas > 0`. |

---

## 3. Input esperado

```json
{
  "source_event": "scheduled_expiration",
  "dry_run": false
}
```

| Campo | Tipo | Obligatorio | Descripcion |
|---|---|---|---|
| `source_event` | `string` | No | Origen del evento. Default: `scheduled_expiration`. |
| `dry_run` | `boolean` | No | Default: `false`. Si es `true`, detecta sin escribir nada. |

Cuando se ejecuta via Schedule Trigger, el input viene vacío y se usan los defaults.
Cuando se ejecuta via Manual Trigger, se puede pasar `dry_run: true` para inspeccionar antes de actuar.

---

## 4. Output sin vencidas

```json
{
  "ok": true,
  "expiradas": 0,
  "dry_run": false,
  "recalculo_cache": "skipped",
  "mensaje": "No hay pre-reservas vencidas para expirar"
}
```

`recalculo_cache = skipped` indica que no se llamo a `db_recalcular_disponibilidad`
porque no habia nada que actualizar.

---

## 5. Output dry_run

```json
{
  "ok": true,
  "dry_run": true,
  "expirarian": 3,
  "ids_prereserva": [1, 2, 3],
  "detalle": [
    {
      "id_prereserva": 1,
      "id_cabana": 1,
      "fecha_in": "2026-06-01",
      "fecha_out": "2026-06-03",
      "expira_en": "2026-05-30T13:00:00Z"
    }
  ],
  "mensaje": "Dry run: no se escribieron cambios"
}
```

No escribe nada en Sheets. No llama a `db_recalcular_disponibilidad`.

---

## 6. Output exitoso con vencidas

```json
{
  "ok": true,
  "expiradas": 5,
  "ids_prereserva": [1, 2, 3, 4, 5],
  "dry_run": false,
  "recalculo_cache": "ok",
  "recalculo_error": null,
  "mensaje": "Pre-reservas vencidas expiradas correctamente"
}
```

| Campo | Tipo | Descripcion |
|---|---|---|
| `ok` | boolean | Siempre `true` si el workflow completo sin errores criticos. |
| `expiradas` | integer | Cantidad de PRE_RESERVAS actualizadas. |
| `ids_prereserva` | `integer[]` | IDs de las PRE_RESERVAS vencidas. |
| `recalculo_cache` | `"ok"` / `"skipped"` / `"warning"` | Estado del recalculo final. |
| `recalculo_error` | `string` o `null` | Mensaje de accion si `recalculo_cache = warning`. |

---

## 7. Output de warning

**recalculo_cache = warning** — PRE_RESERVAS actualizadas correctamente pero recalculo fallo:
```json
{
  "ok": true,
  "expiradas": 3,
  "recalculo_cache": "warning",
  "recalculo_error": "db_recalcular_disponibilidad falló después de expirar las pre-reservas. Cache puede estar desactualizada. Ejecutar recálculo manual."
}
```

Las PRE_RESERVAS ya fueron actualizadas y los LOGs ya fueron escritos.
La cache puede quedar temporalmente desactualizada. Accion correctiva: ejecutar `db_recalcular_disponibilidad` manualmente.

---

## 8. Hojas que lee

| Hoja | Proposito | Puede estar vacia |
|---|---|---|
| `PRE_RESERVAS` | Detectar pre-reservas vencibles | Si |

---

## 9. Hojas que escribe

| Hoja | Operacion | Cuando |
|---|---|---|
| `PRE_RESERVAS` | Update row por `id_prereserva` (estado, updated_at) | Una por PRE_RESERVA vencida, solo si `dry_run = false` y `expiradas > 0` |
| `LOG_CAMBIOS` | Append 1 fila por PRE_RESERVA vencida | Solo si `dry_run = false` y `expiradas > 0` |

---

## 10. Subworkflows llamados

| Workflow | Cuando | Modo | continueOnFail |
|---|---|---|---|
| `db_recalcular_disponibilidad` | Al final, solo si `expiradas > 0` y `dry_run = false` | Sincrono | Si |

Si `expiradas = 0`, no se llama al subworkflow — `recalculo_cache = skipped`.

---

## 11. LOG_CAMBIOS generado

Un registro por cada PRE_RESERVA vencida, con `nivel = info`.

```json
{
  "tabla_afectada": "PRE_RESERVAS",
  "id_registro": "1",
  "campo_modificado": "estado",
  "valor_anterior": "pendiente_pago",
  "valor_nuevo": "vencida",
  "modificado_por": "n8n",
  "source_event": "scheduled_expiration",
  "nivel": "info",
  "detalle": "{\"id_prereserva\": 1, \"id_cabana\": 1, \"fecha_in\": \"2026-06-01\", \"fecha_out\": \"2026-06-03\", \"expira_en\": \"2026-05-30T13:00:00Z\"}"
}
```

---

## 12. Reglas de negocio

**Condicion para vencer una PRE_RESERVA:**
- `estado = pendiente_pago` (exacto)
- `expira_en` es un valor valido y parseable como timestamp
- `expira_en <= ahora` (ya paso)

**Estados que NUNCA se tocan:**

| Estado | Razon |
|---|---|
| `pago_en_revision` | Tiene un pago reportado pendiente de revision. Bloquea siempre. |
| `convertida` | Ya fue confirmada como RESERVA definitiva. |
| `vencida` | Ya fue procesada anteriormente. |
| `cancelada` | Cancelada manualmente. |

**Casos especiales:**
- `expira_en` vacio, inválido o no parseable: ignorar silenciosamente. La PRE_RESERVA NO se vence.
- `pago_en_revision` con `expira_en` vencido: ignorar. Solo `db_registrar_pago` y `db_confirmar_reserva` pueden cambiar ese estado.
- Si no hay vencidas: no se escribe nada, no se recalcula, `recalculo_cache = skipped`.
- Si `dry_run = true`: no se escribe nada, no se recalcula, se devuelve solo el analisis.

---

## 13. Schedule

| Campo | Valor |
|---|---|
| Cron default | `0 3 * * *` |
| Significado | Una vez por dia a las 03:00 UTC |
| Para dos veces por dia | `0 3,15 * * *` |
| Frecuencia recomendada | 1 vez por dia |
| Frecuencia maxima util | 2 veces por dia |

En DEV/TEST: mantener el workflow **INACTIVO** y usar Manual Trigger para pruebas controladas.
En produccion: activar el workflow cuando se quiera automatizar la expiracion diaria.

---

## 14. Fuera de alcance en v1

| Funcionalidad | Estado |
|---|---|
| WhatsApp / notificaciones | Diferido |
| IA | Diferido |
| MercadoPago | Diferido |
| Eliminacion de filas | Fuera de alcance |
| Cancelacion de reservas | Fuera de alcance |
| Tocar PAGOS | Fuera de alcance |
| Tocar RESERVAS | Fuera de alcance |
| Tocar CONSULTAS | Fuera de alcance |
| Recalculo parcial | Diferido — requiere nueva version de db_recalcular_disponibilidad |
| Notificacion automatica al huesped sobre vencimiento | Diferido |

---

## 15. Riesgos conocidos

| Riesgo | Severidad | Mitigacion actual |
|---|---|---|
| Schedule activo en DEV/TEST puede modificar datos de prueba inesperadamente | Media | Mantener workflow inactivo en DEV/TEST. Usar Manual Trigger. |
| `expira_en` mal cargado puede hacer que una PRE_RESERVA no venza | Baja | El campo se valida antes de procesar. Si no parsea, se ignora. |
| Google Sheets no es transaccional | Media | Si falla a mitad del batch de updates, algunas PRE_RESERVAS pueden quedar sin actualizar. Detectar por LOG_CAMBIOS y reintentar. |
| Fallo del recalculo final post-escritura | Baja | `continueOnFail: true`. Output retorna `recalculo_cache = warning`. Ejecutar recalculo manual. |
| Este workflow es de limpieza, no el mecanismo principal de disponibilidad en tiempo real | Informativo | `db_crear_prereserva` ya recalcula disponibilidad al inicio. Este workflow ordena la operacion pero no es la unica defensa. |

---

## 16. Casos de prueba validados

| # | Caso | Resultado esperado |
|---|---|---|
| 1 | Sin pre-reservas vencidas | `ok:true`, `expiradas:0`, `recalculo_cache:skipped`, nada escrito |
| 2 | Una pre-reserva vencida | `ok:true`, `expiradas:1`, estado → `vencida`, 1 LOG, cache recalculada |
| 3 | Multiples pre-reservas vencidas | `ok:true`, `expiradas:N`, todas actualizadas, N LOGs, cache recalculada |
| 4 | `pago_en_revision` con `expira_en` vencido | No se toca — sigue en `pago_en_revision` |
| 5 | `convertida` con `expira_en` vencido | No se toca |
| 6 | `expira_en` vacio o invalido | Ignorado silenciosamente — no vence, no logea |
| 7 | `dry_run = true` | Devuelve lista sin escribir nada en Sheets ni recalcular |
| 8 | Recalculo final exitoso | `recalculo_cache: ok` |
| 9 | Recalculo final fallido | `ok:true`, `recalculo_cache:warning`, PRE_RESERVAS actualizadas correctamente |

Todos los casos validados en DEV y TEST.

---

## 17. Notas operativas

- Por ahora puede quedar desactivado. Ejecutar manualmente cuando se quiera limpiar el entorno de DEV/TEST.
- En produccion conviene activarlo 1 vez por dia a las 03:00 UTC para que las fechas liberadas estén disponibles al inicio de la jornada.
- No hace falta correrlo cada pocos minutos — `db_crear_prereserva` ya recalcula disponibilidad al inicio de cada creacion de pre-reserva, por lo que las pre-reservas vencidas no bloquean nuevas reservas.
- Este workflow complementa al sistema: ordena el estado de PRE_RESERVAS y mantiene la cache limpia para reportes y operacion.
- Antes de activarlo en produccion, correr con `dry_run = true` para verificar que no hay pre-reservas activas que no deberian vencerse.
