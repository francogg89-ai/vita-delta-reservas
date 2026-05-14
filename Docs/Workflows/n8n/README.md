# Workflows/n8n

Templates sanitizados de los workflows n8n del sistema Vita Delta.

## Qué son estos archivos

Cada archivo `.template.json` es la exportación real de un workflow n8n,
con todos los datos sensibles o dependientes de entorno reemplazados por
placeholders. La lógica, los nodos, las conexiones y el código JavaScript
están intactos.

**Estos archivos NO contienen:**
- SHEETS_ID reales de ningún entorno
- Credential IDs de la instancia n8n
- Teléfonos, emails ni datos de contacto
- Tokens ni secrets
- URLs internas de infraestructura

## Cómo usar estos templates

### 1. Copiar el archivo

```bash
cp db_recalcular_disponibilidad.template.json mi_workflow.json
```

### 2. Reemplazar los placeholders

Buscar y reemplazar en el archivo antes de importar en n8n:

| Placeholder | Qué poner |
|---|---|
| `__SHEETS_ID__` | ID del Google Sheets del entorno (DEV o TEST o PROD) |
| `__CREDENTIAL_ID__` | ID de la credencial OAuth de Google Sheets en tu instancia n8n |
| `__CREDENTIAL_NAME__` | Nombre de la credencial OAuth en tu instancia n8n |
| `__TELEFONO_EJEMPLO__` | Teléfono de prueba para DEV_INPUT (solo en db_crear_consulta) |

El SHEETS_ID está en la URL del Sheets:
```
https://docs.google.com/spreadsheets/d/__SHEETS_ID__/edit
```

El CREDENTIAL_ID y CREDENTIAL_NAME se obtienen desde n8n →
**Credentials** → abrir la credencial Google Sheets → copiar el ID y nombre.

### 3. Importar en n8n

1. n8n → **Workflows** → **+ Add Workflow**
2. Tres puntos `···` → **Import from File**
3. Seleccionar el archivo modificado
4. Verificar que los nodos Google Sheets apuntan al Sheet correcto
5. Ctrl+S → **Execute workflow**

## DEV vs TEST vs PROD

El mismo template sirve para todos los entornos.
La única diferencia es el valor de `__SHEETS_ID__` y las credenciales.

| Entorno | SHEETS_ID | Credencial |
|---|---|---|
| DEV | ID del Sheets DEV | Credencial OAuth conectada a la cuenta con acceso DEV |
| TEST | ID del Sheets TEST | Idem |
| PROD | ID del Sheets PROD | Idem |

## Workflows disponibles

| Archivo | Descripción | Contrato técnico |
|---|---|---|
| `db_recalcular_disponibilidad.template.json` | Regenera DISPONIBILIDAD_CACHE completa | [Docs/API_CONTRACTS/db_recalcular_disponibilidad.md](../../Docs/API_CONTRACTS/db_recalcular_disponibilidad.md) |
| `db_crear_consulta.template.json` | Registra o recupera una consulta activa | [Docs/API_CONTRACTS/db_crear_consulta.md](../../Docs/API_CONTRACTS/db_crear_consulta.md) |

## Workflows pendientes de implementar

| Workflow | Estado |
|---|---|
| `db_crear_prereserva` | ⬜ pendiente |
| `db_registrar_pago` | ⬜ pendiente |
| `db_confirmar_reserva` | ⬜ pendiente |
| `sistema_expirar_prereservas` | ⬜ pendiente |

## Estructura del repositorio relacionada

```
Docs/
└── API_CONTRACTS/
    ├── README.md                          ← índice de contratos
    ├── db_recalcular_disponibilidad.md    ← contrato técnico completo
    └── db_crear_consulta.md               ← contrato técnico completo

Workflows/
└── n8n/
    ├── README.md                                          ← este archivo
    ├── db_recalcular_disponibilidad.template.json
    └── db_crear_consulta.template.json
```

## Notas

- Los workflows usan la estrategia `id = max + 1` para generar IDs en DEV.
  Para producción con alta concurrencia, migrar a `CON-<timestamp>` o UUID.
- El workflow `db_recalcular_disponibilidad` debe ejecutarse con concurrencia 1
  (nunca en paralelo). Configurar en n8n → Settings del workflow.
- El nodo `Leer CABAÑAS` y similares no tienen filtro nativo en el nodo Google Sheets
  porque el tipo booleano `TRUE` no matchea correctamente. El filtrado se hace en el
  nodo Code siguiente.
