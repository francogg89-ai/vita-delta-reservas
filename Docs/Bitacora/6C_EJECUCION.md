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


Entrada W1 para 6C_EJECUCION.md

Cómo usar este archivo: copiar el bloque de abajo y pegarlo al final de Docs/Bitacora/6C_EJECUCION.md, después de la entrada de W0. Actualizar también la tabla "Estado general de la etapa" del encabezado del archivo, cambiando la fila de W1 a estado ✅ OK con fecha de cierre.


Actualización de la tabla "Estado general de la etapa"
En la tabla del encabezado del archivo, reemplazar la fila de W1:
| W1 — Consultar disponibilidad | `obtener_disponibilidad_rango()` + vistas | — | — |
Por:
| W1 — Consultar disponibilidad | `obtener_disponibilidad_rango()` | ✅ OK | 2026-05-25 |

Bloque a pegar después de la entrada de W0
markdown## W1 — Consultar disponibilidad

**Estado:** ✅ OK
**Fecha de cierre:** 2026-05-25
**Propósito:** primera invocación real de una función del schema desde n8n. Lectura read-only de disponibilidad por rango de fechas y opcionalmente por cabaña. Establece el patrón base que replican W2–W7.

### Decisiones de diseño tomadas

| Decisión | Justificación |
|---|---|
| Llamar `obtener_disponibilidad_rango()` directamente (no consultar `vista_disponibilidad`) | La vista tiene horizonte fijo 60 días forward. La función acepta rango arbitrario, que es lo que necesita el bot conversacional y la web pública. |
| Output estructurado en wrapper `{ ok, workflow, source_event, result: { rango, id_cabana, total_dias, dias }, executed_at }` | Coherente con `6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2` Sección 5.6. Contrato estable y reutilizable para W2+. |
| `source_event` se envía en input/output de n8n pero **no se loguea en `log_cambios`** | La función es read-only y no recibe `source_event` como parámetro. Queda solo para trazabilidad de ejecución dentro de n8n (visible en Executions). |
| `Build Input` implementado como Code node (no Set node) | Un único objeto JSON editable. Patrón reutilizable para workflows con muchos parámetros (W2+). |
| `Build Response` implementado como Code node | Necesario para agrupar N filas del Postgres en un único objeto. Set node no agrupa. |
| n8n no reinterpreta semántica | Si la función devuelve `tipo_dia = "semana"` para un domingo, así llega al output. n8n orquesta, no decide. |

### Estructura del workflow

4 nodos en cadena lineal:
Manual Trigger → Build Input (Code) → Call obtener_disponibilidad_rango (Postgres) → Build Response (Code)

### Query SQL invocada

```sql
SELECT *
FROM obtener_disponibilidad_rango(
  $1::DATE,
  $2::DATE,
  NULLIF($3::BIGINT, 0)
);
```

### Tests ejecutados

Los 4 tests definidos en `6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2` Sección 10 para W1.

**Test 1 — Happy path (cabaña específica)**

Payload: `fecha_desde=2026-06-07`, `fecha_hasta=2026-06-14`, `id_cabana=17`.

| Verificación | Esperado | Real | OK |
|---|---|---|---|
| `result.total_dias` | 7 | 7 | ✅ |
| Domingo 2026-06-07 `hora_checkin_base` | 18:00:00 | 18:00:00 | ✅ |
| Domingo 2026-06-07 `hora_checkout_base` (D47) | 16:00:00 | 16:00:00 | ✅ |
| Resto de días `hora_checkout_base` | 10:00:00 | 10:00:00 | ✅ |
| Viernes y sábado `tipo_dia` | "finde" | "finde" | ✅ |
| `result.id_cabana` en wrapper | 17 | 17 | ✅ |

**Test 2 — Sin cabaña específica (todas las cabañas)**

Payload: `id_cabana=0` (convención workaround, ver gotcha #2 más abajo).

| Verificación | Esperado | Real | OK |
|---|---|---|---|
| `result.total_dias` | 35 (7 días × 5 cabañas) | 35 | ✅ |
| `result.id_cabana` en wrapper | null (conversión 0→null) | null | ✅ |
| Cabañas presentes en `dias` | 17, 18, 19, 20, 21 | Las 5 ✅ | ✅ |
| Domingo: las 5 cabañas con `hora_checkout_base = 16:00` | Sí | Sí | ✅ |

**Test 3 — Rango invertido (fecha_hasta < fecha_desde)**

Payload: `fecha_desde=2026-06-14`, `fecha_hasta=2026-06-07`, `id_cabana=17`.

| Verificación | Esperado | Real | OK |
|---|---|---|---|
| `ok` | true | true | ✅ |
| `result.total_dias` | 0 | 0 | ✅ |
| `result.dias` | `[]` | `[]` | ✅ |

**Comportamiento documentado:** la función `obtener_disponibilidad_rango()` no valida que `fecha_hasta > fecha_desde`. Si las fechas se invierten, `generate_series` devuelve 0 filas y la función no tira error. Quien consume W1 (futuro bot/web) debe validar el rango antes de llamar si quiere informar al usuario.

**Test 4 — Cabaña inexistente**

Payload: `id_cabana=9999` (no existe en `cabanas`).

| Verificación | Esperado | Real | OK |
|---|---|---|---|
| `ok` | true | true | ✅ |
| `result.total_dias` | 0 | 0 | ✅ |
| `result.id_cabana` en wrapper | 9999 (refleja lo pedido) | 9999 | ✅ |

**Observación de contrato:** el wrapper devuelve `id_cabana: 9999` aunque la cabaña no exista, porque refleja lo que pidió el caller. El indicador real de "cabaña no encontrada" es `total_dias: 0`. Si en el futuro el bot/web quiere distinguir "no hay disponibilidad" vs "cabaña inválida", deberá validar el id contra el catálogo antes de llamar.

### Lo que W1 demuestra (validaciones reutilizables para W2+)

1. Patrón base **Manual Trigger → Build Input (Code) → Postgres → Build Response (Code)** funciona y es legible.
2. `Build Input` como Code node con objeto JSON editable es cómodo para pruebas manuales y se versiona limpio.
3. Pasaje de parámetros desde Code node a Postgres node vía `options.queryReplacement` con expressions `={{ $json.<campo> }}` funciona en n8n cloud, typeVersion 2.6 del Postgres node.
4. La estructura del wrapper `{ ok, workflow, source_event, result, executed_at }` queda como contrato base para los workflows siguientes.
5. Casteo de tipos PostgreSQL ↔ JSON validado empíricamente:
   - `BIGINT` → string en JSON (driver de n8n).
   - `DATE` → string ISO con `T00:00:00.000Z` (no es bug, es el cast a `Date` JS).
   - `TIME` → string `"HH:MM:SS"`.
6. D47 está aplicada y propagada correctamente desde Supabase hasta el output JSON de n8n.

### Gotchas descubiertos durante la ejecución de W1

#### Gotcha 1 — `Query Parameters` de n8n no permiten enviar NULL real al driver de PostgreSQL

**Síntomas observados durante la implementación:**

- Con `id_cabana: ""` (string vacío) en el Build Input → n8n omite el parámetro y la query falla con `there is no parameter $3`.
- Con `id_cabana: null` en el Build Input → n8n lo envía como string literal `"null"` y la query falla con `invalid input syntax for type bigint: "null"`.

**Causa:** los `Query Parameters` de n8n en formato string-con-comas (`={{ $a }},={{ $b }},={{ $c }}`) no soportan valores "vacíos" en ningún formato. Si la expression evalúa a `""`, n8n descarta el parámetro de la lista. Si evalúa a `null`, lo serializa como `"null"`.

**Workaround aplicado en W1 (convención `0 = todas`):**

- En Build Input: `id_cabana = 0` significa "todas las cabañas".
- En query: `NULLIF($3::BIGINT, 0)` convierte `0` a `NULL` antes de pasarlo a la función.
- En Build Response: si `Build Input.id_cabana = 0`, el wrapper devuelve `id_cabana: null` para que el contrato externo siga siendo NULL = todas.

**Por qué este enfoque:** el parámetro nunca llega vacío a n8n (siempre es un número), la función SQL sigue recibiendo NULL como antes, y el consumidor externo del workflow nunca ve la convención `0`.

**Trade-off aceptado:** convención artificial en la frontera n8n → Postgres. Documentada en `Lecciones_Aprendidas.md` para que cualquier workflow futuro con parámetros opcionales aplique el mismo patrón.

#### Gotcha 2 — Resultados vacíos detienen el workflow por default

**Síntoma observado:** Tests 3 y 4 fallaron con el mensaje `No output data returned — n8n stops executing the workflow when a node has no output data`. El nodo Postgres ejecutaba sin error y devolvía 0 filas, pero el Build Response no se ejecutaba.

**Causa:** comportamiento por default de n8n: si un nodo no devuelve items, el workflow se detiene en ese punto.

**Fix aplicado:**

1. En el nodo `Call obtener_disponibilidad_rango`, pestaña Settings → activar `Always Output Data`. Cuando la función devuelve 0 filas, n8n inyecta un único item con `json` vacío `{}` para que el flujo continúe.
2. En `Build Response`, agregar filter defensivo: `items.filter(d => d && Object.keys(d).length > 0)`. Sin esto, el item vacío inyectado por n8n contaría como una fila en `total_dias`.

**Por qué importa:** un workflow read-only de disponibilidad **debe** poder responder "no hay disponibilidad" sin romper. Esto es operativamente más importante que ahorrar un setting. Aplica también para W7 y cualquier workflow futuro de lectura.

### Template exportado al repo

Template sanitizado en `Workflows/n8n/supabase/vita_w01_consultar_disponibilidad_supabase.template.json`.

Placeholders reemplazados al sanitizar:
- `__CREDENTIAL_ID__` (ID interno de la credencial en n8n)
- `__CREDENTIAL_NAME__` (nombre, típicamente `vita_supabase_dev`)
- `__WORKFLOW_VERSION_ID__`
- `__N8N_INSTANCE_ID__`
- `__WORKFLOW_ID__`

Los IDs internos de los nodos (UUIDs) se preservan: identifican nodos dentro del workflow y mantenerlos consistentes facilita el diff entre versiones del template.

### Conclusión W1

Workflow operativo, los 4 tests del documento de diseño pasaron. Patrón base validado y reutilizable. Próximo paso: **W2 — Crear pre-reserva**, que va a ser la primera invocación a una función que **escribe** en Supabase. Va a usar el mismo patrón base, sumando el manejo de errores de negocio (`p_status = "ok"` vs `"no_disponible"` vs `"superpuesto_con_reserva"`, etc.) según `6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2` Sección 11.

Generado como cierre formal de W1 — 2026-05-25.