# Workflows/n8n/supabase

Templates sanitizados de los workflows n8n que apuntan a **Supabase** como backend.
Pertenecen a la **Etapa 6C** del sistema Vita Delta.

## Diferencia con los workflows legacy

| Carpeta | Backend | Estado |
|---|---|---|
| `Workflows/n8n/*.template.json` | Google Sheets | Legacy — congelados, no se modifican |
| `Workflows/n8n/supabase/*.template.json` | Supabase PostgreSQL | Vigentes — se actualizan a medida que avanza 6C |

**Los workflows de esta carpeta reemplazan progresivamente a los legacy.** No hay convivencia operativa entre ambos backends — DEV apunta solo a Supabase desde Etapa 6B.

## Estado de los workflows de 6C

| Workflow | Función SQL | Template | Estado |
|---|---|---|---|
| `vita_w00_smoke_test_supabase` | `SELECT 1` | `vita_w00_smoke_test_supabase.template.json` | ✅ Cerrado |
| `vita_w01_consultar_disponibilidad_supabase` | `obtener_disponibilidad_rango()` + vistas | — | Pendiente |
| `vita_w02_crear_prereserva_supabase` | `crear_prereserva()` | — | Pendiente |
| `vita_w03_registrar_pago_supabase` | `registrar_pago()` | — | Pendiente |
| `vita_w04_confirmar_reserva_supabase` | `confirmar_reserva()` | — | Pendiente |
| `vita_w05_cancelar_prereserva_supabase` | `cancelar_prereserva()` | — | Pendiente |
| `vita_w06_crear_bloqueo_supabase` | `crear_bloqueo()` | — | Pendiente |
| `vita_w07_vistas_operativas_supabase` | Vistas SQL | — | Pendiente |

Detalle de implementación y bitácora: `Docs/Bitacora/6C_EJECUCION.md`.
Documento de diseño: `Docs/Implementacion/6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2`.

## Cómo usar estos templates

### 1. Pre-requisitos

- Tener una credencial PostgreSQL en n8n apuntando al pooler transaccional de Supabase DEV (o TEST/PROD según corresponda).
- Para DEV, la credencial estándar se llama `vita_supabase_dev`.
- Configuración detallada de la credencial: ver `Docs/Bitacora/6C_EJECUCION.md`, entrada W0, sección W0.A.

### 2. Copiar el template

```bash
cp vita_w00_smoke_test_supabase.template.json mi_workflow.json
```

### 3. Reemplazar placeholders

Antes de importar en n8n, reemplazar:

| Placeholder | Qué poner |
|---|---|
| `__CREDENTIAL_ID__` | ID de la credencial PostgreSQL en tu instancia n8n |
| `__CREDENTIAL_NAME__` | Nombre de la credencial (típicamente `vita_supabase_dev`) |
| `__WORKFLOW_ID__` | ID del workflow (se autocompleta al importar) |
| `__WORKFLOW_VERSION_ID__` | Version ID del workflow (se autocompleta al importar) |
| `__N8N_INSTANCE_ID__` | Instance ID de tu instancia n8n |

**Nota:** los IDs de workflow, versión e instancia se autoasignan al importar — en general no hace falta tocarlos a mano. Lo crítico de reemplazar es `__CREDENTIAL_ID__` y `__CREDENTIAL_NAME__`.

Cómo obtener el `__CREDENTIAL_ID__`:

1. En n8n: Credentials → abrir la credencial PostgreSQL → mirar la URL del navegador.
2. La URL tiene formato `.../credentials/<CREDENTIAL_ID>`.
3. Copiar ese ID.

### 4. Importar en n8n

1. n8n → Workflows → "+" o "Add Workflow".
2. Tres puntos arriba a la derecha → **Import from File**.
3. Seleccionar el archivo modificado.
4. Verificar que el nodo Postgres apunta a la credencial correcta.
5. Ctrl+S para guardar.
6. Ejecutar para validar.

### 5. Settings recomendados

A diferencia de los workflows legacy (Sheets), los workflows de Supabase **no necesitan `Max Concurrency = 1`** porque PostgreSQL serializa con advisory locks (`pg_advisory_xact_lock(10, 0)` y `(1, id_cabana)`).

Excepción: si durante 6C aparecen problemas bajo retries/timeouts, evaluar caso por caso. Ver `Docs/Implementacion/6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2` Sección 7.

## DEV vs TEST vs PROD

El mismo template sirve para los tres entornos. Solo cambia la credencial PostgreSQL apuntando a cada Supabase project:

| Entorno | Credencial sugerida |
|---|---|
| DEV | `vita_supabase_dev` |
| TEST | `vita_supabase_test` (cuando exista) |
| PROD | `vita_supabase_prod` (cuando exista) |

## Sanitización antes de commit

Antes de subir un workflow nuevo al repo, asegurarse de:

- Reemplazar `__CREDENTIAL_ID__` (es específico de la instancia n8n).
- Reemplazar `__WORKFLOW_ID__`, `__WORKFLOW_VERSION_ID__`, `__N8N_INSTANCE_ID__`.
- Verificar que **no haya secrets** (passwords, tokens, service role keys) en ningún `parameter` ni en `credentials`.
- Verificar que **no haya datos reales de huéspedes** en pin data o casos de prueba dentro del workflow.

Si el archivo viene con secrets accidentalmente:
1. Rotar las credenciales en Supabase / n8n inmediatamente.
2. No commitear ese archivo.
3. Volver a exportar después de rotar.

## Convenciones de naming

- Workflows: `vita_w{NN}_{nombre}_supabase`.
- Templates: `<nombre_workflow>.template.json`.
- `source_event` en los payloads JSONB: `n8n_w{NN}_{nombre_corto}_{disparador}`.

Detalle: `Docs/Implementacion/6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2` Sección 5.
