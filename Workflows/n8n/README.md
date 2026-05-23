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
| `__CREAR_HUESPED_WORKFLOW_ID__` | ID del workflow db_crear_huesped en tu instancia n8n |
| `__CREAR_HUESPED_WORKFLOW_NAME__` | Nombre del workflow db_crear_huesped |

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
- db_crear_huesped
7. Execute workflow

## DEV vs TEST vs PROD

El mismo template sirve para todos los entornos.
La unica diferencia es el valor de `__SHEETS_ID__` y las credenciales.

| Entorno | SHEETS_ID | Credencial |
|---|---|---|
| DEV | ID del Sheet DEV | Credencial OAuth con acceso a DEV |
| TEST | ID del Sheet TEST | Idem |
| PROD | ID del Sheet PROD | Idem |

## Nota sobre subworkflows

Varios workflows llaman a otros como subworkflows. Para que esto funcione,
el workflow llamado DEBE tener un trigger "When Executed by Another Workflow"
conectado al nodo inicial (ademas del Manual Trigger que se usa para pruebas manuales).

### Workflows que llaman a `db_recalcular_disponibilidad`

| Workflow que llama | Cuando | Motivo |
|---|---|---|
| `db_crear_prereserva` | Al final, despues de crear la PRE_RESERVA | Reflejar el nuevo bloqueo en cache |
| `db_registrar_pago` | Al final, despues de actualizar PRE_RESERVAS | Reflejar que pago_en_revision bloquea aunque expira_en este vencido |
| `db_confirmar_reserva` | Al final, despues de confirmar la RESERVA | Actualizar cache para reflejar la reserva confirmada |
| `sistema_expirar_prereservas` | Al final, solo si hubo pre-reservas vencidas | Ordenar estados vencidos y actualizar disponibilidad derivada |

> **Nota:** `db_crear_prereserva v3` ya no llama a `db_recalcular_disponibilidad` al inicio.
> El recalculo inicial fue eliminado en v3 (Opcion B): Capa 1 es informativa,
> la autoridad real es Capa 2 + Revalidacion Final con lecturas frescas.

### Workflows que llaman a `db_crear_huesped`

| Workflow que llama | Cuando | Motivo |
|---|---|---|
| `db_crear_prereserva` | Al inicio, antes de verificar disponibilidad | Crear o recuperar huesped y obtener id_huesped |

## Workflows disponibles

| Archivo | Descripcion | Contrato tecnico |
|---|---|---|
| `db_recalcular_disponibilidad.template.json` | Regenera DISPONIBILIDAD_CACHE completa | [Docs/API_CONTRACTS/db_recalcular_disponibilidad.md](../../Docs/API_CONTRACTS/db_recalcular_disponibilidad.md) |
| `db_crear_consulta.template.json` | Registra o recupera una consulta activa | [Docs/API_CONTRACTS/db_crear_consulta.md](../../Docs/API_CONTRACTS/db_crear_consulta.md) |
| `db_crear_huesped.template.json` | Crea o actualiza huesped con deduplicacion por telefono y email | [Docs/API_CONTRACTS/db_crear_huesped.md](../../Docs/API_CONTRACTS/db_crear_huesped.md) |
| `db_crear_prereserva.template.json` | Crea pre-reserva temporal con verificacion en dos capas y revalidacion fresh | [Docs/API_CONTRACTS/db_crear_prereserva.md](../../Docs/API_CONTRACTS/db_crear_prereserva.md) |
| `db_registrar_pago.template.json` | Registra pago reportado y pasa PRE_RESERVA a pago_en_revision | [Docs/API_CONTRACTS/db_registrar_pago.md](../../Docs/API_CONTRACTS/db_registrar_pago.md) |
| `db_confirmar_reserva.template.json` | Confirma reserva definitiva a partir de PRE_RESERVA y PAGO en revision | [Docs/API_CONTRACTS/db_confirmar_reserva.md](../../Docs/API_CONTRACTS/db_confirmar_reserva.md) |
| `sistema_expirar_prereservas.template.json` | Marca como vencidas las PRE_RESERVAS pendiente_pago con expira_en vencido | [Docs/API_CONTRACTS/sistema_expirar_prereservas.md](../../Docs/API_CONTRACTS/sistema_expirar_prereservas.md) |

## Estructura del repositorio relacionada

```
Docs/
└── API_CONTRACTS/
    ├── README.md
    ├── db_recalcular_disponibilidad.md
    ├── db_crear_consulta.md
    ├── db_crear_huesped.md
    ├── db_crear_prereserva.md
    ├── db_registrar_pago.md
    ├── db_confirmar_reserva.md
    └── sistema_expirar_prereservas.md

Workflows/
└── n8n/
    ├── README.md
    ├── db_recalcular_disponibilidad.template.json
    ├── db_crear_consulta.template.json
    ├── db_crear_huesped.template.json
    ├── db_crear_prereserva.template.json
    ├── db_registrar_pago.template.json
    ├── db_confirmar_reserva.template.json
    └── sistema_expirar_prereservas.template.json
```

## Notas generales

- Los workflows usan `id = max + 1` para generar IDs en DEV/TEST. Para produccion con alta concurrencia migrar a UUID o DB transaccional.
- `db_recalcular_disponibilidad` debe ejecutarse con Max Concurrency = 1.
- `db_crear_prereserva` debe ejecutarse con Max Concurrency = 1.
- `db_crear_huesped` debe ejecutarse con Max Concurrency = 1.
- El filtrado de filas activas (activa = TRUE, activo = TRUE) se hace en codigo JavaScript, no con el filtro nativo del nodo Google Sheets, porque el tipo booleano TRUE no matchea correctamente con ese filtro.
- `db_crear_prereserva v3` implementa la Opcion B de disponibilidad: Capa 1 es informativa (nunca rechaza por si sola), la autoridad real es Capa 2 contra fuentes reales mas revalidacion final con lecturas frescas.
- Tiempo estimado de `db_crear_prereserva v3`: 20-30 segundos. La web debe mostrar un estado de espera durante la ejecucion.
