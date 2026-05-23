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
| `db_recalcular_disponibilidad` | [db_recalcular_disponibilidad.md](./db_recalcular_disponibilidad.md) | validado | Si | Si |
| `db_crear_consulta` | [db_crear_consulta.md](./db_crear_consulta.md) | validado | Si | Si |
| `db_crear_huesped` | [db_crear_huesped.md](./db_crear_huesped.md) | validado | Si | Si |
| `db_crear_prereserva` | [db_crear_prereserva.md](./db_crear_prereserva.md) | validado | Si | — |
| `db_registrar_pago` | [db_registrar_pago.md](./db_registrar_pago.md) | validado | Si | Si |
| `db_confirmar_reserva` | [db_confirmar_reserva.md](./db_confirmar_reserva.md) | validado | Si | Si |
| `sistema_expirar_prereservas` | [sistema_expirar_prereservas.md](./sistema_expirar_prereservas.md) | validado | Si | Si |

> `db_crear_prereserva v3` fue validado en DEV. TEST pendiente.

## Convenciones

- **Fechas:** siempre `YYYY-MM-DD` como texto plano en Google Sheets.
- **Timestamps:** ISO 8601 (`2026-06-05T14:23:00Z`).
- **Booleanos en Sheets:** `TRUE` / `FALSE` en mayúsculas.
- **IDs:** enteros positivos, calculados como `max + 1` en DEV/TEST.
  Para producción con alta concurrencia migrar a UUID o DB transaccional.
- **fecha_in / fecha_out:** intervalo semiabierto `[fecha_in, fecha_out)`.
  `fecha_in` es inclusive, `fecha_out` es exclusiva.
- **SHEETS_ID:** no incluido en este repositorio. Ver `.env.example`.
- **Credenciales n8n:** no portables entre instancias. Sanitizar antes de commitear.

## Cómo leer los contratos

Cada contrato tiene estas secciones:

1. Propósito — que hace y que NO hace
2. Estado — version validada y entornos
3. Input — campos esperados con tipo y obligatoriedad
4. Output exitoso — estructura JSON de respuesta ok
5. Output de error — estructura JSON de respuesta con error
6. Hojas que lee — fuentes de datos
7. Hojas que escribe — efectos en Sheets
8. Subworkflows llamados — dependencias de ejecución
9. LOG_CAMBIOS — que registra y cuando
10. Reglas de negocio — disponibilidad, vencimiento, etc.
11. Fuera de alcance — que no esta implementado todavia
12. Riesgos conocidos — limitaciones técnicas documentadas
13. Casos de prueba validados — escenarios probados en DEV y TEST
14. Notas para frontend/bot — como consumir este workflow

## Sanitizacion antes de commitear

Reemplazar en los JSON de workflow antes de subir a GitHub:

```
SHEETS_ID de DEV  → __SHEETS_ID__
SHEETS_ID de TEST → __SHEETS_ID__
credential id     → __CREDENTIAL_ID__
workflow id       → __WORKFLOW_ID__
instanceId        → __N8N_INSTANCE_ID__
versionId         → __WORKFLOW_VERSION_ID__
subworkflow IDs   → __RECALCULAR_DISPONIBILIDAD_WORKFLOW_ID__ (u otros placeholders segun el caso)
credential name   → __CREDENTIAL_NAME__
subworkflow name  → __RECALCULAR_DISPONIBILIDAD_WORKFLOW_NAME__ (u otros placeholders según el caso)
```

## Nota sobre migración a Supabase

El sistema fue diseñado sobre Google Sheets como base de datos operativa
para las etapas de diseño, prototipado y validación (DEV/TEST).

La migración a Supabase está planificada como próxima etapa.
Los contratos técnicos de los workflows documentan el comportamiento esperado
independientemente de la capa de persistencia — los inputs, outputs, reglas de negocio
y flujos de datos son válidos para Supabase con ajustes en los nodos de lectura/escritura.
