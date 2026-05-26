# Workflows/n8n/supabase

Templates sanitizados de los workflows n8n que apuntan a **Supabase** como backend.
Pertenecen a la **Etapa 6C** del sistema Vita Delta, **cerrada el 2026-05-26**.

## Diferencia con los workflows legacy

| Carpeta | Backend | Estado |
|---|---|---|
| `Workflows/n8n/*.template.json` | Google Sheets | Legacy — congelados, no se modifican |
| `Workflows/n8n/supabase/*.template.json` | Supabase PostgreSQL | Vigentes — Etapa 6C cerrada |

**Los workflows de esta carpeta reemplazan funcionalmente a los legacy.** No hay convivencia operativa entre ambos backends — DEV apunta solo a Supabase desde Etapa 6B.

## Estado de los workflows de 6C

| Workflow | Función SQL / vista | Template | Estado |
|---|---|---|---|
| `vita_w00_smoke_test_supabase` | `SELECT 1` (smoke test) | `vita_w00_smoke_test_supabase.template.json` | ✅ Cerrado |
| `vita_w01_consultar_disponibilidad_supabase` | `obtener_disponibilidad_rango(date, date, bigint)` | `vita_w01_consultar_disponibilidad_supabase.template.json` | ✅ Cerrado |
| `vita_w02_crear_prereserva_supabase` | `crear_prereserva(jsonb)` | `vita_w02_crear_prereserva_supabase.template.json` | ✅ Cerrado |
| `vita_w03_registrar_pago_supabase` | `registrar_pago(jsonb)` | `vita_w03_registrar_pago_supabase.template.json` | ✅ Cerrado |
| `vita_w04_confirmar_reserva_supabase` | `confirmar_reserva(jsonb)` | `vita_w04_confirmar_reserva_supabase.template.json` | ✅ Cerrado |
| `vita_w05_cancelar_prereserva_supabase` | `cancelar_prereserva(jsonb)` | `vita_w05_cancelar_prereserva_supabase.template.json` | ✅ Cerrado |
| `vita_w06_crear_bloqueo_supabase` | `crear_bloqueo(jsonb)` | `vita_w06_crear_bloqueo_supabase.template.json` | ✅ Cerrado |
| `vita_w07_vistas_operativas_supabase` | 6 vistas read-only (paramétrico) | `vita_w07_vistas_operativas_supabase.template.json` | ✅ Cerrado |

**Total: 8 workflows operativos, 40 tests funcionales aprobados, 3 verificaciones cruzadas end-to-end.**

Documentación de referencia:

- Cierre formal de la etapa: `Docs/Implementacion/6C_CIERRE.md`.
- Bitácora detallada por workflow: `Docs/Bitacora/6C_EJECUCION.md`.
- Lecciones aprendidas (L-6C-01 a L-6C-09): `Docs/Operacional/Lecciones_Aprendidas.md`.

## Cómo usar estos templates

### 1. Pre-requisitos

- Tener una credencial PostgreSQL en n8n apuntando al pooler transaccional de Supabase DEV (o TEST/PROD según corresponda).
- Para DEV, la credencial estándar se llama `vita_supabase_dev`.
- **Importante:** la credencial requiere `Ignore SSL Issues: ON` por el pooler transaccional (L-6C-01).
- Configuración detallada de la credencial: ver `Docs/Bitacora/6C_EJECUCION.md`, entrada W0.

### 2. Copiar el template

```bash
cp vita_w02_crear_prereserva_supabase.template.json mi_workflow.json
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
5. Verificar que `Always Output Data: ON` está habilitado en el nodo Postgres (L-6C-04).
6. Ctrl+S para guardar.
7. Ejecutar para validar (el template arranca con valores del happy path de cada workflow).

### 5. Settings recomendados

A diferencia de los workflows legacy (Sheets), los workflows de Supabase **no necesitan `Max Concurrency = 1`** porque PostgreSQL serializa con advisory locks (`pg_advisory_xact_lock(10, 0)` y `(1, id_cabana)`).

Excepción: si bajo retries/timeouts aparecen problemas inesperados, evaluar caso por caso.

## Patrones técnicos consolidados durante 6C

### Estructura de workflows

**5 nodos lineal** (W2, W3, W4, W5, W6):

```
Manual Trigger → Build Input → Build Payload → Postgres → Build Response
```

**4 nodos con parameter binding** (W1):

```
Manual Trigger → Build Input → Postgres → Build Response
```

**6 nodos con ramificación IF** (W7 — primer workflow con nodo IF):

```
Manual Trigger → Build Input → Build Query → IF Validation Error
                                              ├─ true  → Build Response (error estructurado)
                                              └─ false → Postgres → Build Response
```

### Wrapper externo unificado

Todos los workflows devuelven un wrapper consistente alrededor del JSONB de la función SQL:

```json
{
  "ok": true/false,
  "workflow": "vita_wNN_nombre_supabase",
  "source_event": "n8n_wNN_nombre_manual",
  "idempotency_key": "..." | null,
  "id_evento_dev": "...",
  "error": null | "codigo",
  "warning": null | "codigo",
  "result": { },
  "executed_at": "ISO timestamp"
}
```

Extensiones específicas: `idempotency_key` solo aplica en W2, `warning` solo aplica en W3 (caso v1.3 de pago tardío sobre pre-reserva terminal), `vista` solo aplica en W7.

### Normalización defensiva con `nv()`

Patrón establecido a partir de W3 (registrar_pago): aplicar `nv()` a **todos los campos del payload, incluidos los obligatorios**, no solo a los opcionales.

```javascript
const nv = (v) => (v === '' || v === undefined ? null : v);
```

Razón: las funciones SQL del schema actual no aplican uniformemente `NULLIF(TRIM(...))` a los campos obligatorios de texto. Mandar `""` desde n8n puede pasar la validación inicial (`v_campo IS NULL` falla porque `""` no es NULL) y chocar contra CHECK constraints, generando errores crudos de Postgres en vez de JSONB estructurado.

Mitigación temporal mientras el hardening SQL no se aplique (ver `Docs/Implementacion/Pendiente_pre_produccion.md`).

### Convención de "todas las cabañas" (no universal)

Diferencia de contrato entre funciones:

- **W1** (`obtener_disponibilidad_rango`): `id_cabana = 0` significa "todas". La función usa `NULLIF($N::TYPE, 0)`.
- **W6** (`crear_bloqueo`): `id_cabana = null` significa "todas". La función no trata 0 como caso especial — `0` resultaría en `cabana_no_existe`.

Esto NO es un bug, es una diferencia de contrato. Cada función define su propia semántica. Documentado en código de cada Build Payload.

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
- **Build Input del template debe tener los valores del happy path**, no del último test ejecutado al exportar.

Si el archivo viene con secrets accidentalmente:
1. Rotar las credenciales en Supabase / n8n inmediatamente.
2. No commitear ese archivo.
3. Volver a exportar después de rotar.

## Convenciones de naming

- Workflows: `vita_w{NN}_{nombre}_supabase`.
- Templates: `<nombre_workflow>.template.json`.
- `source_event` en los payloads JSONB: `n8n_w{NN}_{nombre_corto}_{disparador}`.
- `id_evento_dev` para trazabilidad de pruebas en el wrapper externo: `{canal}_{id_evento}`.

Detalle completo en `Docs/Implementacion/6C_CIERRE.md`, sección "Convenciones consolidadas".
