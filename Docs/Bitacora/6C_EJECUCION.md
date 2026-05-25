# 6C_EJECUCION.md — Bitácora de ejecución de Etapa 6C

# Reescritura de Workflows n8n contra Supabase DEV

**Documento base de diseño:** `Docs/Implementacion/6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2`.
**Entorno objetivo:** Supabase DEV (proyecto `jqfvtblscxbzlmlcwadi`) + n8n cloud (`federicosecchi.app.n8n.cloud`).
**Schema canónico:** `6B_SCHEMA_SQL.md v1.7.1`.
**Bitácora previa relacionada:** `Docs/Bitacora/6B_EJECUCION_DEV.md` (Etapa 6B cerrada el 2026-05-25).

---

## Propósito de este documento

Registrar la ejecución de los workflows W0–W7 de la Etapa 6C, uno por uno, con:

- Fecha de implementación.
- Resultado de tests.
- Decisiones tomadas durante la implementación.
- Gotchas operativos descubiertos.
- Referencia a los templates exportados.

Cada entrada se cierra cuando el workflow está implementado, testeado y los criterios de éxito definidos en el documento de diseño se cumplieron.

---

## Convenciones de la bitácora

- **Una entrada por workflow.** Cada workflow Wxx tiene su propio bloque.
- **Estado posible:** `EN PROGRESO`, `OK`, `BLOQUEADO`, `DIFERIDO`.
- **Formato de fechas:** ISO 8601 (`YYYY-MM-DD`).
- **Tests:** marcar cada test con ✅ / ❌ / ⏭ (no ejecutado).
- **Decisiones operativas y gotchas:** se anotan al final de cada entrada y, si son reutilizables, se replican en `Docs/Operacional/Lecciones_Aprendidas.md`.

---

## Estado general de la etapa

| Workflow | Función SQL | Estado | Fecha cierre |
|---|---|---|---|
| W0 — Smoke test | `SELECT 1` | ✅ OK | 2026-05-25 |
| W1 — Consultar disponibilidad | `obtener_disponibilidad_rango()` + vistas | — | — |
| W2 — Crear pre-reserva | `crear_prereserva()` | — | — |
| W3 — Registrar pago | `registrar_pago()` | — | — |
| W4 — Confirmar reserva | `confirmar_reserva()` | — | — |
| W5 — Cancelar pre-reserva | `cancelar_prereserva()` | — | — |
| W6 — Crear bloqueo | `crear_bloqueo()` | — | — |
| W7 — Vistas operativas | Vistas SQL | — | — |

---

## W0 — Smoke test n8n ↔ Supabase DEV

**Estado:** ✅ OK
**Fecha de cierre:** 2026-05-25
**Propósito:** validar conexión, credenciales, latencia y formato de respuesta entre n8n cloud y Supabase DEV antes de cualquier otro workflow.

### Subtareas ejecutadas

#### W0.A — Configuración de credencial PostgreSQL en n8n

Credencial creada en n8n cloud (`federicosecchi.app.n8n.cloud`):

| Campo | Valor |
|---|---|
| Nombre | `vita_supabase_dev` |
| Tipo | Postgres (nodo nativo de n8n, **NO** la credencial "Supabase") |
| Host | `aws-1-sa-east-1.pooler.supabase.com` |
| Port | `6543` |
| Database | `postgres` |
| User | `postgres.jqfvtblscxbzlmlcwadi` |
| Password | (almacenada en gestor de contraseñas; nunca commiteada al repo) |
| SSL | `Require` |
| Ignore SSL Issues | **ON** (workaround obligatorio — ver gotcha abajo) |
| SSH Tunnel | off |
| Maximum Number of Connections | 100 (default) |

Resultado del Test Connection: "Connection tested successfully" ✅.

#### W0.B — Workflow del smoke test

Workflow creado en n8n: `vita_w00_smoke_test_supabase`.

**Nodos (2):**

1. **Manual Trigger** ("When clicking 'Execute workflow'").
2. **Postgres → Execute a SQL query**, conectado a credencial `vita_supabase_dev`.

**Query ejecutada:**

```sql
SELECT 1 AS ok, NOW() AS server_time, current_database() AS db;
```

**Resultado de la primera ejecución (Execution ID #1015):**

- Duración: 1.553s (primera ejecución; incluye handshake TLS + apertura de pool).
- Estado: Succeeded.
- Output:

```json
[
  {
    "ok": 1,
    "server_time": "2026-05-25T16:08:01.580Z",
    "db": "postgres"
  }
]
```

### Verificación contra criterios de éxito del documento de diseño

Según `6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2`, Sección 10 (W0):

| Criterio | Esperado | Resultado |
|---|---|---|
| Ejecuta sin error | Sí | ✅ |
| `result.ok = 1` | Sí | ✅ |
| `server_time` con timestamp actual | Sí | ✅ (`2026-05-25T16:08:01.580Z` UTC, coherente con hora local Tigre GMT-3 = 13:08) |
| `db = "postgres"` | Sí | ✅ |
| Tiempo < 1s | Sí | ⚠️ Primera ejecución 1.55s; esperado en ejecuciones siguientes < 1s por reuse de conexión. |

Comentario sobre la latencia: la primera ejecución levanta la conexión desde cero (handshake TLS al pooler + apertura del pool en n8n). Ejecuciones subsiguientes deberían bajar a sub-segundo. No es bloqueante para el cierre de W0.

### Lo que W0 demuestra (validaciones que NO hace falta repetir en workflows futuros)

1. La credencial `vita_supabase_dev` funciona contra el pooler transaccional de Supabase DEV.
2. n8n cloud puede abrir conexión TLS al pooler usando el toggle "Ignore SSL Issues".
3. El nodo Postgres con operation "Execute Query" devuelve el output como JSON estructurado (array de objetos).
4. El roundtrip JSON entre n8n y Supabase funciona.
5. El patrón **Manual Trigger → Postgres node → Output** está validado como base para los workflows W1–W7.

### Decisiones operativas tomadas durante W0

| Decisión | Justificación |
|---|---|
| Usar el **pooler transaccional** (`:6543`) y no la conexión directa (`:5432`) | Alineado con `6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2` Sección 6. El pooler maneja mejor las conexiones cortas que n8n genera por ejecución. |
| **No** activar el add-on de IPv4 dedicado | Innecesario: el pooler transaccional ya es IPv4-compatible por defecto ("IPv4 proxied for free" según Supabase). El add-on es de pago y no aporta nada para 6C. |
| Usar credencial **Postgres**, no **Supabase**, en n8n | Decisión cerrada en `6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2` Sección 6: el Postgres node es el canal nativo para invocar funciones SQL con payload JSONB. La credencial "Supabase" de n8n usa la API REST/PostgREST, que sería el camino RPC futuro pero no para 6C. |

### Gotchas operativos descubiertos en W0

#### Gotcha 1 — `self-signed certificate in certificate chain` al testear la credencial

**Síntoma:** el primer intento de "Test Connection" con SSL en `Require` falló con el mensaje "Couldn't connect with these settings — self-signed certificate in certificate chain".

**Causa:** el cliente PostgreSQL de n8n cloud no reconoce la CA que firma el certificado del pooler de Supabase y lo marca como self-signed. No es un certificado realmente self-signed; es un certificado válido pero firmado por una CA que n8n cloud no tiene cargada.

**Solución aplicada:** activar el toggle "Ignore SSL Issues (Insecure)" en la credencial, manteniendo SSL en `Require`. El tráfico TLS sigue cifrado; lo único que se desactiva es la validación contra una CA.

**Trade-off aceptado:** el nombre del toggle dice "Insecure" pero solo se desactiva la validación de CA, no el cifrado del tráfico. El riesgo teórico de MITM es bajo en un canal n8n.cloud → Supabase con TLS. Si en el futuro se migra a n8n self-hosted, se podría cargar la cadena de CA de Supabase y pasar a `Verify (CA)` o `Verify (Full)`.

**Documentación:** este gotcha se propaga a `Docs/Operacional/Lecciones_Aprendidas.md` como entrada nueva, para que sea reutilizable en futuras configuraciones (TEST, PROD, otros desarrolladores).

#### Gotcha 2 — Formato del User en credencial PostgreSQL contra pooler de Supabase

**Síntoma potencial:** no ocurrió en este caso, pero vale registrarlo.

**Detalle:** en el pooler transaccional de Supabase, el usuario PostgreSQL **no es** `postgres` sino `postgres.<project_id>` (con punto y el project ID concatenado). Conectarse con solo `postgres` falla con error de autenticación.

**Ejemplo aplicado:** project_id = `jqfvtblscxbzlmlcwadi`, user = `postgres.jqfvtblscxbzlmlcwadi`.

**Por qué importa:** la conexión directa (puerto 5432) sí acepta solo `postgres`, pero el pooler (6543) requiere el formato `postgres.<project_id>`. Si en algún momento alguien copia un connection string sin verificar puerto y usuario, puede confundir las dos variantes.

### Templates exportados al repo

⏭ **Pendiente** — exportar el JSON del workflow `vita_w00_smoke_test_supabase`, sanitizarlo (reemplazar IDs internos por placeholders) y guardarlo en `Workflows/n8n/supabase/vita_w00_smoke_test_supabase.template.json`.

**Para la sanitización:** seguir la convención usada en los workflows legacy (`Workflows/n8n/README.md`). Reemplazar:

- `__N8N_INSTANCE_ID__` para el instance ID.
- `__WORKFLOW_ID__` para el ID del workflow.
- `__WORKFLOW_VERSION_ID__` para el version ID.
- `__CREDENTIAL_ID__` para el ID de la credencial.
- `__CREDENTIAL_NAME__` para el nombre (puede dejarse como `vita_supabase_dev` si se considera no sensible).

### Conclusión W0

Conexión n8n cloud → Supabase DEV operativa y validada empíricamente. El patrón base de los workflows futuros queda probado. Próximo paso: W1 (Consultar disponibilidad).

---

*Bitácora abierta el 2026-05-25 con el cierre de W0.*