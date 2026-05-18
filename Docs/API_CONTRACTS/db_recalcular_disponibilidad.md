# Contrato técnico — `db_recalcular_disponibilidad`

## 1. Propósito

Regenera completamente la hoja `DISPONIBILIDAD_CACHE` para un conjunto de cabañas y fechas.

**Hace:**
- Lee el estado actual de RESERVAS, PRE_RESERVAS, BLOQUEOS, TEMPORADAS, FERIADOS y CONFIGURACION_GENERAL.
- Calcula el estado de disponibilidad para cada par `(id_cabana, fecha)` del producto cartesiano de inputs.
- Limpia el rango `DISPONIBILIDAD_CACHE!A2:R` conservando encabezados.
- Escribe las filas recalculadas.
- Registra un único entrada en LOG_CAMBIOS por ejecución.

**No hace:**
- No valida disponibilidad para el usuario final (eso es `db_crear_prereserva`).
- No crea ni modifica RESERVAS, PRE_RESERVAS ni BLOQUEOS.
- No envía notificaciones.
- No consulta precios.
- No aplica OVERRIDES_OPERATIVOS (diferido, ver restricciones).

---

## 2. Estado

| Campo | Valor |
|---|---|
| Versión validada | v8 |
| Archivo n8n | `dev_db_recalcular_disponibilidad_v8_final.json` / `test_db_recalcular_disponibilidad_v8_final.json` |
| DEV | ✅ validado |
| TEST | ✅ validado |
| Concurrencia configurada | 1 (nunca en paralelo) |
| Disparador en DEV | Manual Trigger |
| Disparador en producción | Llamado por otros workflows vía Execute Workflow |

---

## 3. Input

En producción este workflow es llamado por otros workflows, no por el usuario directamente.
El input se pasa como JSON al nodo Execute Workflow.

```json
{
  "id_cabanas": [1, 2, 3],
  "fechas": ["2026-06-20", "2026-06-21"],
  "source_event": "string"
}
```

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `id_cabanas` | `integer[]` | No | IDs de cabañas a recalcular. Vacío = todas las cabañas activas |
| `fechas` | `string[]` | No | Fechas `YYYY-MM-DD` a recalcular. Vacío = próximos 60 días desde hoy |
| `source_event` | `string` | No | Origen del llamado. Default: `recalculo_manual` |

**Defaults cuando viene vacío:**
- `id_cabanas = []` → recalcula las 5 cabañas activas
- `fechas = []` → genera las próximas 60 fechas desde hoy (UTC)
- Resultado típico: 300 filas (5 cabañas × 60 días)

---

## 4. Output exitoso

```json
{
  "ok": true,
  "version": "v8",
  "mensaje": "db_recalcular_disponibilidad completado — regeneración completa",
  "stats": {
    "total_calculadas": 300,
    "warnings": 0
  },
  "hay_warnings": false,
  "warnings": [],
  "source_event": "recalculo_manual"
}
```

| Campo | Tipo | Descripción |
|---|---|---|
| `ok` | `boolean` | Siempre `true` si el workflow completó |
| `stats.total_calculadas` | `integer` | Filas escritas en DISPONIBILIDAD_CACHE |
| `stats.warnings` | `integer` | Cantidad de conflictos detectados |
| `warnings` | `array` | Detalle de cada conflicto (BLOQUEO sobre RESERVA, etc.) |

---

## 5. Output de error

Este workflow no tiene validación de input explícita — si falla, falla por error de nodo
(credencial, Sheets no accesible, etc.). El error queda en el log de ejecución de n8n.

En caso de conflictos de datos (no errores técnicos), los warnings se incluyen en el output
exitoso y se registran en LOG_CAMBIOS.

---

## 6. Hojas que lee

| Hoja | Filtro aplicado |
|---|---|
| `CABAÑAS` | Sin filtro (filtra `activa = TRUE` en código) |
| `CONFIGURACION_GENERAL` | Sin filtro |
| `TEMPORADAS` | Sin filtro (filtra `activa = TRUE` en código) |
| `FERIADOS` | Sin filtro (filtra `activo = TRUE` en código) |
| `RESERVAS` | Sin filtro — puede estar vacía |
| `PRE_RESERVAS` | Sin filtro — puede estar vacía |
| `BLOQUEOS` | Sin filtro (filtra `activo = TRUE` en código) |

> **Nota:** los filtros de Google Sheets fueron removidos porque el tipo booleano `TRUE`
> no matchea correctamente con el filtro nativo del nodo. El filtrado se hace en código dentro del workflow.

---

## 7. Hojas que escribe

| Hoja | Operación | Detalle |
|---|---|---|
| `DISPONIBILIDAD_CACHE` | Clear + Append | Limpia `A2:R`, luego escribe todas las filas recalculadas |
| `LOG_CAMBIOS` | Append | 1 fila por ejecución |

---

## 8. LOG_CAMBIOS generado

Se escribe **siempre exactamente 1 fila** por ejecución, independientemente de cuántas
filas se recalcularon.

```json
{
  "tabla_afectada": "DISPONIBILIDAD_CACHE",
  "id_registro": "batch_300_filas",
  "campo_modificado": "recalculo_completo",
  "modificado_por": "n8n",
  "source_event": "recalculo_manual",
  "nivel": "info",
  "detalle": {
    "stats": { "total_calculadas": 300, "warnings": 0 },
    "warnings": [],
    "ts_inicio": "...",
    "ts_calculo": "...",
    "ts_escritura": "..."
  }
}
```

Si hay warnings, `nivel` pasa a `"warning"` y el array `warnings` incluye el detalle
de cada conflicto detectado.

---

## 9. Efectos secundarios

- Borra y regenera completamente el rango `DISPONIBILIDAD_CACHE!A2:R`.
  Si se ejecuta dos veces seguidas, el resultado es idéntico (idempotente).
- Añade 1 fila al LOG_CAMBIOS. Ejecutar N veces genera N filas en el log.

---

## 10. Restricciones

| Restricción | Detalle |
|---|---|
| Concurrencia | 1. Nunca ejecutar en paralelo. |
| Fuente de verdad | DISPONIBILIDAD_CACHE es derivada, no editable manualmente. |
| OVERRIDES_OPERATIVOS | No implementados en v8. Diferido para iteración posterior. |
| `es_ultimo_dia_bloque` | Siempre `FALSE` en v8. Requiere lookahead al día siguiente. |
| Escalonamiento de check-in | No implementado. Diferido por arquitectura (Etapa 2 v1.3). |
| Conflicto RESERVA vs RESERVA | No genera warning en v8. Issue documentado en GitHub. |

---

## 11. Notas para frontend / bot

- **No llamar directamente.** Este workflow es interno — lo llaman otros workflows.
- **No leer DISPONIBILIDAD_CACHE en tiempo real desde el browser.** La cache puede
  tener hasta 60 segundos de delay si hay un recálculo en curso.
- El estado `checkout_disponible` significa que la noche está libre, pero hay un huésped haciendo checkout ese día.
  Operativamente requiere atención de limpieza/recambio antes de un posible nuevo check-in.
  El horario base de check-in sigue siendo el definido por configuración: normalmente 13:00, y 18:00 los domingos.
- Los estados posibles en `DISPONIBILIDAD_CACHE.estado` son:
  `disponible`, `checkout_disponible`, `ocupada`, `bloqueada`.

---

## 12. Casos de prueba validados

### DEV

| # | Descripción | Resultado esperado | ✅ |
|---|---|---|---|
| 1 | Ejecución inicial con cache vacía, sin reservas | 300 filas `disponible`, 0 warnings, 1 LOG | ✅ |
| 2 | Reserva simple `id_cabana=1`, `2026-06-16 → 2026-06-17` | `2026-06-16 = ocupada`, `2026-06-17 = checkout_disponible` | ✅ |
| 3 | Tres reservas consecutivas en la misma cabaña | Bordes correctos, `tiene_checkout` y `tiene_checkin` simultáneos en fechas compartidas | ✅ |
| 4 | Bloqueo `2026-06-20 → 2026-06-22` (exclusive) | `20 = bloqueada`, `21 = bloqueada`, `22 = disponible` | ✅ |
| 5 | PRE_RESERVA vigente `2026-06-23 → 2026-06-24` con `expira_en` futuro | `23 = ocupada` con `id_prereserva_activa`, `24 = disponible` | ✅ |
| 6 | Feriado `2026-06-20` | `tipo_dia = feriado`, estado según bloqueos/reservas | ✅ |
| 7 | Domingo cualquiera | `hora_checkin_minima = 18:00` | ✅ |
| 8 | Viernes y sábado | `tipo_dia = finde` | ✅ |

### TEST

| # | Descripción | Resultado | ✅ |
|---|---|---|---|
| 1 | Ejecución inicial con cache vacía, sin datos | 300 filas `disponible`, 0 warnings, 1 LOG | ✅ |

### Modos de ejecución

Este workflow puede ejecutarse de dos formas:

1. **Manual Trigger**
   - Uso: pruebas DEV/TEST, recálculo manual, reparación operativa.
   - Permite regenerar DISPONIBILIDAD_CACHE completa a demanda.

2. **When Executed by Another Workflow**
   - Uso: ejecución como subworkflow desde otros workflows.
   - Actualmente es llamado por `db_crear_prereserva` después de crear una PRE_RESERVA.
   - Debe estar conectado al mismo nodo inicial que el Manual Trigger.

En ambos casos, la lógica ejecutada es la misma.

### Advertencia sobre recálculo completo

La versión v8 realiza recálculo completo:
- limpia `DISPONIBILIDAD_CACHE!A2:R`,
- recalcula todas las cabañas del rango configurado,
- reescribe la cache completa.

No debe usarse con scope parcial (`id_cabanas`, `fechas`) hasta que exista una versión específica de recálculo parcial.