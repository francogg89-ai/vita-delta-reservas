# Workflows/n8n

Templates sanitizados de los workflows n8n del sistema Vita Delta.

## Que son estos archivos

Cada archivo `.template.json` es la exportacion real de un workflow n8n,
con todos los datos sensibles o dependientes de entorno reemplazados por
placeholders. La logica, los nodos, las conexiones y el codigo JavaScript
estan intactos.

**Estos archivos NO contienen:**
- SHEETS_ID reales de ningun entorno
- Credential IDs de la instancia n8n
- Workflow IDs reales
- instanceId ni versionId reales
- Telefonos, emails ni datos de contacto
- Tokens ni secrets
- URLs internas de infraestructura

## Como usar estos templates

### 1. Copiar el archivo

```bash
cp db_crear_prereserva.template.json mi_workflow.json
```

### 2. Reemplazar los placeholders

Buscar y reemplazar en el archivo antes de importar en n8n:

| Placeholder | Que poner |
|---|---|
| `__SHEETS_ID__` | ID del Google Sheets del entorno (DEV, TEST o PROD) |
| `__CREDENTIAL_ID__` | ID de la credencial OAuth de Google Sheets en tu instancia n8n |
| `__CREDENTIAL_NAME__` | Nombre de la credencial OAuth en tu instancia n8n |
| `__RECALCULAR_DISPONIBILIDAD_WORKFLOW_ID__` | ID del workflow db_recalcular_disponibilidad en tu instancia n8n |
| `__RECALCULAR_DISPONIBILIDAD_WORKFLOW_NAME__` | Nombre del workflow db_recalcular_disponibilidad |

El SHEETS_ID esta en la URL del Sheet:
```
https://docs.google.com/spreadsheets/d/__SHEETS_ID__/edit
```

El CREDENTIAL_ID y CREDENTIAL_NAME se obtienen desde n8n → Credentials → abrir la credencial Google Sheets → copiar el ID y nombre.

El ID del subworkflow esta en la URL de ese workflow en n8n:
```
https://tu-instancia.n8n.cloud/workflow/__RECALCULAR_DISPONIBILIDAD_WORKFLOW_ID__
```

### 3. Importar en n8n

1. n8n → Workflows → + Add Workflow
2. Tres puntos en la esquina → Import from File
3. Seleccionar el archivo modificado
4. Verificar que los nodos Google Sheets apuntan al Sheet correcto
5. Ctrl+S
6. Settings del workflow → Max Concurrency = 1 cuando aplique:
- db_recalcular_disponibilidad
- db_crear_prereserva
7. Execute workflow

## DEV vs TEST vs PROD

El mismo template sirve para todos los entornos.
La unica diferencia es el valor de `__SHEETS_ID__` y las credenciales.

| Entorno | SHEETS_ID | Credencial |
|---|---|---|
| DEV | ID del Sheet DEV | Credencial OAuth con acceso a DEV |
| TEST | ID del Sheet TEST | Idem |
| PROD | ID del Sheet PROD | Idem |

## Nota sobre db_recalcular_disponibilidad como subworkflow

`db_recalcular_disponibilidad` es llamado como subworkflow por otros workflows.
Para que esto funcione, DEBE tener un trigger "When Executed by Another Workflow"
conectado al nodo inicial (ademas del Manual Trigger que se usa para pruebas manuales).

Sin ese trigger, n8n no puede invocar el workflow como subworkflow.

Workflows que llaman a `db_recalcular_disponibilidad`:

| Workflow que llama | Cuando | Motivo |
|---|---|---|
| `db_crear_prereserva` | Al inicio, antes de verificar disponibilidad | Limpiar pre-reservas vencidas de la cache antes de consultar |
| `db_crear_prereserva` | Al final, despues de crear la PRE_RESERVA | Reflejar el nuevo bloqueo en cache |
| `db_registrar_pago` | Al final, despues de actualizar PRE_RESERVAS | Reflejar que pago_en_revision bloquea aunque expira_en este vencido |

## Workflows disponibles

| Archivo | Descripcion | Contrato tecnico |
|---|---|---|
| `db_recalcular_disponibilidad.template.json` | Regenera DISPONIBILIDAD_CACHE completa | [Docs/API_CONTRACTS/db_recalcular_disponibilidad.md](../../Docs/API_CONTRACTS/db_recalcular_disponibilidad.md) |
| `db_crear_consulta.template.json` | Registra o recupera una consulta activa | [Docs/API_CONTRACTS/db_crear_consulta.md](../../Docs/API_CONTRACTS/db_crear_consulta.md) |
| `db_crear_prereserva.template.json` | Crea pre-reserva temporal con doble verificacion | [Docs/API_CONTRACTS/db_crear_prereserva.md](../../Docs/API_CONTRACTS/db_crear_prereserva.md) |
| `db_registrar_pago.template.json` | Registra pago reportado y pasa PRE_RESERVA a pago_en_revision | [Docs/API_CONTRACTS/db_registrar_pago.md](../../Docs/API_CONTRACTS/db_registrar_pago.md) |

## Workflows pendientes de implementar

| Workflow | Estado |
|---|---|
| `db_confirmar_reserva` | pendiente |
| `sistema_expirar_prereservas` | pendiente |

## Estructura del repositorio relacionada

```
Docs/
└── API_CONTRACTS/
    ├── README.md
    ├── db_recalcular_disponibilidad.md
    ├── db_crear_consulta.md
    ├── db_crear_prereserva.md
    └── db_registrar_pago.md

Workflows/
└── n8n/
    ├── README.md
    ├── db_recalcular_disponibilidad.template.json
    ├── db_crear_consulta.template.json
    ├── db_crear_prereserva.template.json
    └── db_registrar_pago.template.json
```

## Notas generales

- Los workflows usan `id = max + 1` para generar IDs en DEV/TEST. Para produccion con alta concurrencia migrar a UUID o DB transaccional.
- `db_recalcular_disponibilidad` debe ejecutarse con Max Concurrency = 1.
- `db_crear_prereserva` debe ejecutarse con Max Concurrency = 1.
- El filtrado de filas activas (activa = TRUE, activo = TRUE) se hace en codigo JavaScript, no con el filtro nativo del nodo Google Sheets, porque el tipo booleano TRUE no matchea correctamente con ese filtro.
