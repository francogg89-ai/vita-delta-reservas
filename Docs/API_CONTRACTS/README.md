# Docs/API_CONTRACTS

Contratos técnicos de los workflows de n8n del sistema Vita Delta.

## Qué es esto

Cada archivo documenta un workflow de n8n como si fuera un endpoint de API:
input esperado, output, hojas que toca, efectos secundarios y casos de prueba validados.

El formato es pre-OpenAPI: está pensado para ser legible por humanos ahora
y convertible a OpenAPI/Swagger más adelante cuando se expongan como webhooks reales.

## Estado general del sistema

| Workflow | Archivo | Estado | DEV | TEST |
|---|---|---|---|---|
| `db_recalcular_disponibilidad` | [db_recalcular_disponibilidad.md](./db_recalcular_disponibilidad.md) | ✅ validado | ✅ | ✅ |
| `db_crear_consulta` | [db_crear_consulta.md](./db_crear_consulta.md) | ✅ validado | ✅ | ✅ |
| `db_crear_prereserva` | — | ⬜ pendiente | — | — |
| `db_registrar_pago` | — | ⬜ pendiente | — | — |
| `db_confirmar_reserva` | — | ⬜ pendiente | — | — |
| `sistema_expirar_prereservas` | — | ⬜ pendiente | — | — |

## Convenciones

- **Fechas:** siempre `YYYY-MM-DD` como texto plano en Google Sheets.
- **Timestamps:** ISO 8601 (`2026-06-05T14:23:00Z`).
- **Booleanos en Sheets:** `TRUE` / `FALSE` en mayúsculas.
- **IDs:** en workflows actuales de DEV/TEST se usan enteros positivos calculados como `max + 1` cuando aplica.
  Para producción con alta concurrencia migrar a IDs tipo `CON-<timestamp>` o UUID según entidad.
- **fecha_in / fecha_out:** intervalo semiabierto `[fecha_in, fecha_out)`.
  `fecha_in` es inclusive, `fecha_out` es exclusive (día de salida, no ocupa noche).
- **SHEETS_ID:** no incluido en este repositorio. Ver `.env.example`.
- **Credenciales n8n:** no portables entre instancias. Sanitizar antes de commitear.
- **Entornos:** los contratos describen el comportamiento funcional. Los `SHEETS_ID`, credenciales y URLs reales no se documentan en estos archivos.

## Cómo leer los contratos

Cada contrato tiene estas secciones:

1. **Propósito** — qué hace y qué NO hace
2. **Estado** — versión validada y entornos
3. **Input** — campos esperados con tipo y obligatoriedad
4. **Output exitoso** — estructura JSON de respuesta ok
5. **Output de error** — estructura JSON de respuesta con error
6. **Hojas que lee** — fuentes de datos
7. **Hojas que escribe** — efectos en Sheets
8. **LOG_CAMBIOS** — qué registra y cuándo
9. **Efectos secundarios** — qué más ocurre al ejecutar
10. **Restricciones** — límites, concurrencia, idempotencia
11. **Notas para frontend/bot** — cómo consumir este workflow
12. **Casos de prueba validados** — escenarios probados en DEV y TEST

## Sanitización antes de commitear

Reemplazar en los JSON de workflow antes de subir:

```
SHEETS_ID de DEV  → __SHEETS_ID_DEV__
SHEETS_ID de TEST → __SHEETS_ID_TEST__
credential id     → __CREDENTIAL_ID__
```
