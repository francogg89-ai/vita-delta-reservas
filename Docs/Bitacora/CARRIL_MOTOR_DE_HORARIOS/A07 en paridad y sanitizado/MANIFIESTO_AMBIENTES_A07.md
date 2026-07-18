# MANIFIESTO DE AMBIENTES — `portal-a07-crear-reserva`

**Workflow:** A07 (crear reserva) · Motor de Horarios B1.3
**Propósito:** catálogo cerrado de todo lo que cambia entre TEST y OPS en este workflow, con su ubicación exacta (JSON path), el valor esperado en cada ambiente, si es obligatorio reemplazarlo al importar, si afecta el comportamiento y cómo validarlo.
**Alcance:** solo A07. No cubre otros workflows del portal.

> **Regla de oro operativa.** Si editás OPS **en el lugar** (reemplazando solo el texto del campo `jsCode` de los dos routers, como indica la guía), **ninguno** de los valores ambientales de abajo se toca: n8n los conserva automáticamente. Este manifiesto es la red de seguridad para auditar que quedaron bien y para poder reconstruir el workflow desde el template del repo si hiciera falta.

> **Nota.** El literal del fallback HMAC en los exports es un dummy sintético sin valor operativo (ver §4), no el secreto real. Los identificadores de instancia (`id`, `versionId`, `instanceId`) sí se omiten por higiene: donde correspondería uno, aparece `«REDACTADO»`.

---

## Convención de columnas

- **Path** — ruta JSON dentro del export del workflow.
- **TEST vivo / OPS vivo** — lo que hoy tienen los exports reales.
- **Template repo / Candidato OPS** — lo que llevan los artefactos versionables (`__TEMPLATE.json` y `__OPS__CANDIDATO_SANITIZADO.json`).
- **Obligatorio** — si hay que reemplazarlo sí o sí antes de que el workflow funcione en el ambiente.
- **Afecta comportamiento** — si un valor equivocado cambia la lógica o rompe la ejecución (≠ un simple rótulo).

---

## 1. Nombre del workflow

| Campo | Valor |
|---|---|
| **Path** | `name` (top-level) |
| **TEST vivo** | `portal-a07-crear-reserva__TEST` |
| **OPS vivo** | `portal-a07-crear-reserva__OPS` |
| **Template repo** | `portal-a07-crear-reserva__TEST` (flavor por defecto del template) |
| **Candidato OPS** | `portal-a07-crear-reserva__OPS` |
| **Obligatorio** | Sí — identifica el workflow dentro de la instancia. |
| **Afecta comportamiento** | No — es rótulo. |
| **Validación** | Debe terminar en `__TEST` o `__OPS` según el destino. |

---

## 2. Webhook — ruta (path)

| Campo | Valor |
|---|---|
| **Path** | `nodes[0].parameters.path` (nodo `Webhook`) |
| **TEST vivo** | `portal-a07-crear-reserva__TEST` |
| **OPS vivo** | `portal-a07-crear-reserva__OPS` |
| **Template repo** | `portal-a07-crear-reserva__TEST` |
| **Candidato OPS** | `portal-a07-crear-reserva__OPS` |
| **Obligatorio** | Sí. |
| **Afecta comportamiento** | **Sí.** Define la URL pública del webhook; el gateway/portal apunta a esta ruta para ese ambiente. |
| **Validación** | Debe coincidir exactamente con la URL que el portal usa para A07 en ese ambiente. |

---

## 3. Webhook — identificador interno (webhookId)

| Campo | Valor |
|---|---|
| **Path** | `nodes[0].webhookId` |
| **TEST vivo** | presente (UUID interno de n8n, «REDACTADO») |
| **OPS vivo** | presente (UUID distinto, «REDACTADO») |
| **Template repo** | **ausente** (n8n lo regenera al crear/importar) |
| **Candidato OPS** | **ausente** |
| **Obligatorio** | No — lo administra n8n. |
| **Afecta comportamiento** | No de forma directa (identificador interno). |
| **Validación** | No tocar. Al editar OPS en el lugar se conserva solo; en el repo no debe versionarse. |

---

## 4. Fallback HMAC (dummy sintético)

| Campo | Valor |
|---|---|
| **Path** | `nodes[1].parameters.jsCode` — línea del ternario `const SECRET = (... $vars.VITA_HMAC_SECRET) ? ... : '<fallback>'` (nodo `validar_firma_ts_rol`) |
| **TEST vivo** | Dummy sintético de 64 caracteres, sin valor operativo. Se utiliza únicamente en los exports de trabajo para preservar longitud. |
| **OPS vivo** | Mismo dummy sintético de 64 caracteres, sin valor operativo. |
| **Template repo** | Placeholder `__PEGAR_SECRETO_O_USAR_VARIABLE__`. |
| **Candidato OPS** | Placeholder `__PEGAR_SECRETO_O_USAR_VARIABLE__`. |
| **Obligatorio** | El secreto operativo se toma de `$vars.VITA_HMAC_SECRET`; el literal del fallback es solo un dummy de longitud. |
| **Afecta comportamiento** | El literal del fallback, **no** (es un dummy sin valor operativo). La validación de firma usa el secreto de `$vars.VITA_HMAC_SECRET`, que debe coincidir con el del emisor (gateway/portal). |
| **Validación** | Los artefactos versionables reemplazan el dummy por `__PEGAR_SECRETO_O_USAR_VARIABLE__`. No hace falta rotar nada por este literal: no es el secreto real. |

> **Aclaración.** El literal de 64 caracteres del fallback en TEST y OPS es un dummy sintético colocado para mantener la longitud, **sin valor operativo**. No es el secreto real y no requiere ninguna acción. Se documenta solo para que no se confunda con un secreto ni se trate como tal (por ejemplo, por su longitud).

---

## 5. Credenciales PostgreSQL (Supabase del ambiente)

Aplica **idéntico** a los seis nodos Postgres del workflow.

| Campo | Valor |
|---|---|
| **Path** | `nodes[i].credentials.postgres.name` y `nodes[i].credentials.postgres.id`, para `i ∈ {2, 6, 9, 12, 15, 18}` |
| **Nodos** | `leer_ambiente` (2), `PG-0 precheck_reserva` (6), `PG-1 crear_prereserva` (9), `PG-2 lock_precheck_pago` (12), `PG-3 confirmar_reserva` (15), `PG-4 recheck_reserva_post_confirmar` (18) |
| **TEST vivo** | `name = vita_supabase_test`, `id = «REDACTADO»` (id de credencial de la instancia) |
| **OPS vivo** | `name = vita_supabase_ops`, `id = «REDACTADO»` (distinto) |
| **Template repo** | `name = vita_supabase_test (reemplazar al importar)`, `id = REEMPLAZAR_POR_CRED_TEST` |
| **Candidato OPS** | `name = vita_supabase_ops (reemplazar al importar)`, `id = REEMPLAZAR_POR_CRED_OPS` |
| **Obligatorio** | Sí. |
| **Afecta comportamiento** | **Sí, crítico.** Define contra qué base Supabase (TEST vs OPS) corren los seis pasos SQL. |
| **Validación** | Los **seis** nodos deben referenciar la **misma** credencial del ambiente, y el `id` debe existir en n8n. Al editar OPS en el lugar, ya está resuelto — no tocar. |

---

## 6. Subworkflow de avisos 8C-bis (alta nueva)

| Campo | Valor |
|---|---|
| **Path (nombre)** | `nodes[23].name` (nodo `executeWorkflow`) |
| **Path (id destino)** | `nodes[23].parameters.workflowId.value` |
| **Path (url cache)** | `nodes[23].parameters.workflowId.cachedResultUrl` |
| **Path (nombre cache)** | `nodes[23].parameters.workflowId.cachedResultName` |
| **TEST vivo** | name `Call 'vita_w8cbis_alerta__TEST' (aviso)`; `value = «REDACTADO»`; `cachedResultUrl = /workflow/«REDACTADO»`; `cachedResultName` **presente** |
| **OPS vivo** | name `Call 'vita_w8cbis_alerta__OPS' (aviso)`; `value = «REDACTADO»` (distinto); `cachedResultUrl = /workflow/«REDACTADO»`; `cachedResultName` (según export) |
| **Template repo** | name `Call 'vita_w8cbis_alerta__TEST' (aviso)`; `value = REEMPLAZAR_ID_8CBIS_TEST`; `cachedResultUrl = /workflow/REEMPLAZAR_ID_8CBIS_TEST`; `cachedResultName` **ausente** |
| **Candidato OPS** | name `Call 'vita_w8cbis_alerta__OPS' (aviso)`; `value = REEMPLAZAR_ID_8CBIS_OPS`; `cachedResultUrl = /workflow/REEMPLAZAR_ID_8CBIS_OPS`; `cachedResultName` **ausente** |
| **Obligatorio** | Sí — el `workflowId.value` debe apuntar al subworkflow de avisos 8C-bis del ambiente. |
| **Afecta comportamiento** | **Sí.** Dispara el aviso de alta nueva; con un id inválido, el aviso falla. |
| **Validación** | El `value` debe existir en la instancia y ser el subworkflow correcto del ambiente. `cachedResultName` es un cache de UI: n8n lo repuebla solo. Al editar OPS en el lugar, ya está resuelto. |

---

## 7. Prefijo de idempotencia

| Campo | Valor |
|---|---|
| **Path** | `nodes[5].parameters.jsCode` — línea `` const idem = `portal_<flavor>_a07_...` `` (nodo `Code: derivar`) |
| **TEST vivo** | `portal_test_a07_` |
| **OPS vivo** | `portal_ops_a07_` |
| **Template repo** | `portal_test_a07_` |
| **Candidato OPS** | `portal_ops_a07_` |
| **Obligatorio** | Sí. |
| **Afecta comportamiento** | **Sí.** Es el namespacing de la clave de idempotencia: separa las claves de TEST y OPS para que no colisionen entre ambientes. |
| **Validación** | **No copiar el nodo `Code: derivar` desde TEST hacia OPS** — arrastraría el prefijo `portal_test_a07_` y rompería la idempotencia de OPS. Por eso este nodo queda **fuera** del fix (su lógica es idéntica salvo este prefijo y el comentario de cabecera). |

---

## 8. Comentarios de cabecera con flavor

| Campo | Valor |
|---|---|
| **Path** | primeras líneas de comentario dentro de `parameters.jsCode` en `validar_firma_ts_rol` (1), `verificar_acceso` (3), `Code: derivar` (5), `Code: render` (20) |
| **Diferencia** | rótulo `__TEST` vs `__OPS` en el texto del comentario |
| **Obligatorio** | No. |
| **Afecta comportamiento** | No — son comentarios. |
| **Validación** | Cosmético. No requiere acción. |

---

## 9. Metadata de instancia (a remover en el repo)

| Campo | Valor |
|---|---|
| **Paths** | `id` (top-level), `versionId` (top-level), `meta.instanceId` |
| **TEST vivo** | `id` presente («REDACTADO»); `versionId` presente («REDACTADO»); `meta.instanceId` presente («REDACTADO») |
| **OPS vivo** | `id` presente («REDACTADO»); `versionId` presente («REDACTADO»); `meta.instanceId` **idéntico** al de TEST (misma instancia n8n Cloud, «REDACTADO») |
| **Template repo** | `id` y `versionId` **ausentes**; `meta = null` |
| **Candidato OPS** | `id` y `versionId` **ausentes**; `meta = null` |
| **Obligatorio** | N/A — se remueven para poder versionar. |
| **Afecta comportamiento** | No. |
| **Validación** | En el repo **no** deben aparecer; n8n los regenera al importar. Al editar OPS en el lugar, no se tocan. |

---

## 10. Settings del workflow

| Campo | Valor |
|---|---|
| **Path** | `settings` (top-level) |
| **TEST vivo** | `{executionOrder: v1, binaryMode: separate, availableInMCP: true, timeSavedMode: fixed, callerPolicy: workflowsFromSameOwner}` |
| **OPS vivo** | `{executionOrder: v1, binaryMode: separate, availableInMCP: false}` |
| **Template repo** | `{executionOrder: v1, binaryMode: separate}` |
| **Candidato OPS** | `{executionOrder: v1, binaryMode: separate}` |
| **Obligatorio** | No — los extras son preferencias de instancia. |
| **Afecta comportamiento** | No funcional para A07. `availableInMCP` solo expone o no el workflow al MCP de n8n; `callerPolicy` restringe quién puede invocarlo. |
| **Validación** | Conservar los settings de OPS al editar en el lugar. En el template se dejan mínimos. |

---

## 11. UUID de condición del IF de avisos 8C-bis

| Campo | Valor |
|---|---|
| **Path** | `nodes[22]` (`IF aviso 8C-bis (alta nueva)`) — `id` de la condición dentro de `parameters.conditions` |
| **TEST vivo** | UUID «REDACTADO» |
| **OPS vivo** | UUID distinto «REDACTADO» |
| **Obligatorio** | No — n8n genera un id por condición. |
| **Afecta comportamiento** | No — la **lógica** de la condición es idéntica; solo cambia el identificador interno. |
| **Validación** | Cosmético. |

---

## 12. Posiciones y orden del array de nodos

| Campo | Valor |
|---|---|
| **Paths** | `nodes[*].position` (coordenadas x/y del canvas) y el orden del array `nodes` |
| **Diferencia** | difieren entre exports |
| **Obligatorio** | No. |
| **Afecta comportamiento** | No — n8n ejecuta según `connections`, no según el orden del array ni las posiciones del canvas. |
| **Validación** | Irrelevante para el comportamiento. |

---

## Resumen: ¿qué es lo único que importa por ambiente?

Solo **cinco** ítems afectan comportamiento y hay que tener bien en cada ambiente:

1. **Webhook path** (§2) — URL correcta del ambiente.
2. **Secreto HMAC operativo** (§4) — vía `$vars.VITA_HMAC_SECRET`, debe coincidir con el emisor (el literal del fallback en el export es un dummy).
3. **Credenciales PostgreSQL** (§5) — los 6 nodos a la Supabase del ambiente.
4. **Subworkflow de avisos 8C-bis** (§6) — id válido del ambiente.
5. **Prefijo de idempotencia** (§7) — `portal_test_` vs `portal_ops_`.

Todo lo demás (§1, §3, §8–§12) es rótulo, cache o metadata: no cambia la lógica. Y como el fix se aplica **editando OPS en el lugar**, los cinco críticos ya vienen resueltos de OPS — este manifiesto sirve para **auditarlos**, no para rehacerlos.
