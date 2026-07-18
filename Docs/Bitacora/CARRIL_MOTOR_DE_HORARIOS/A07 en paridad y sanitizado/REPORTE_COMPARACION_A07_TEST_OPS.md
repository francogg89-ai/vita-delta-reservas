# REPORTE DE COMPARACIÓN — A07 `portal-a07-crear-reserva` (TEST vs OPS)

**Contexto.** Una corrección manual que arreglaba una salida incorrecta se aplicó en **TEST** y **no** en **OPS**. Por lo tanto, para este workflow: **TEST = lógica funcional candidata** (la buena) y **OPS = versión anterior**. El objetivo es llevar OPS a la misma lógica funcional que TEST, conservando únicamente los valores ambientales legítimos de OPS.

**Método.** Comparación nodo por nodo de los dos exports, normalizando lo ambiental (ver `MANIFIESTO_AMBIENTES_A07.md`) para aislar diferencias reales de lógica. Todo el análisis es **read-only**: no se modificó ni TEST ni OPS.

**Insumos (exports reales):**

| Archivo | Bytes | SHA-256 |
|---|---|---|
| `portal-a07-crear-reserva__TEST.json` | 42 387 | `2d36154207df8dae3eeccd0706619d8ae0fb3b7b4bdeefbc540f54be36a41625` |
| `portal-a07-crear-reserva__OPS.json` | 40 845 | `19d2439abc50bfb4669ae6906d13261fe713075c509dde4e50e4f52b6d7f10f7` |

**Artefactos versionables producidos:**

| Archivo | Bytes | SHA-256 |
|---|---|---|
| `portal-a07-crear-reserva__TEMPLATE.json` | 42 004 | `3208b0687e4ef878eb74378173ded2bc5c634cac55ca08f336096de04eaa8fcd` |
| `portal-a07-crear-reserva__OPS__CANDIDATO_SANITIZADO.json` | 41 981 | `d0342c9cdd05a884c74c57bc4107fe2b001f27dfaa6887b6fc78a162742509c7` |

---

## 1. Inventario estructural

| Métrica | TEST | OPS | ¿Igual? |
|---|---|---|---|
| Nodos | 24 | 24 | ✅ |
| Aristas (conexiones) | 28 | 28 | ✅ (idénticas tras normalizar sufijos de nombre) |
| Tipos de nodo + `typeVersion` | — | — | ✅ idénticos en los 24 |
| `meta.instanceId` | presente | presente | ✅ **idéntico** (misma instancia n8n Cloud) |
| Mapeo lógico de nodos | — | — | ✅ 1-a-1 |

**Sobre los nombres de nodo.** TEST arrastra el sufijo `1` en casi todos los nodos (artefacto típico de duplicar un workflow en n8n) — p. ej. `router1_crear1`, `Code: derivar1`. OPS usa nombres limpios (`router1_crear`, `Code: derivar`). El template del repo también usa **nombres limpios** (estilo OPS). Este sufijo es puramente cosmético: no cambia la ejecución, solo obliga a normalizar referencias internas al comparar y al pegar código (ver §2).

**Sobre las conexiones.** Las 28 aristas son idénticas una vez normalizado el sufijo de nombres. Detalle relevante para la migración: `router3_confirmar` tiene **dos** salidas en `main[0]` → `IF3 recheck` **y** `IF aviso 8C-bis (alta nueva)`. Ambas deben preservarse.

---

## 2. Diferencias FUNCIONALES — el fix (2 nodos)

La corrección afecta exactamente a **dos** nodos. Es lo único que hay que trasladar de TEST a OPS.

### 2.1 `router1_crear`

- **En OPS (viejo):** `jsCode` de ~1 555 caracteres. Le falta el manejo de dos gaps de calendario y el mapeo del código de error `override_hora_invalido`. Incluso **carece** de la rama `fecha_in_pasada` (OPS quedó más viejo que el propio template del repo, que sí la tenía).
- **En TEST (candidato):** `jsCode` de ~2 129 caracteres. Agrega:
  - `override_hora_invalido` dentro de `payloadInv`;
  - handler `checkin_pisa_checkout_anterior` → `code: 'conflicto'`, mensaje de gap de check-in;
  - handler `checkout_pisa_checkin_posterior` → mensaje de gap de check-out;
  - (y mantiene `fecha_in_pasada`).

### 2.2 `router3_confirmar`

- **En OPS (viejo):** `jsCode` de ~1 170 caracteres. Sin los handlers de gap.
- **En TEST (candidato):** `jsCode` de ~1 833 caracteres. Agrega los dos handlers de gap, devolviendo el envelope `{ recheck: false, envelope: { ok: false, error: { ... } } }`.

### 2.3 Referencias internas a normalizar al pegar en OPS

El `jsCode` de TEST contiene referencias con el sufijo `1` que **no** existen con ese nombre en OPS. Al pegar en OPS hay que usar los nombres limpios:

- `$('Code: derivar1')` → `$('Code: derivar')`
- `$('router1_crear1')` → `$('router1_crear')`

> **Verificación clave.** El `jsCode` corregido con referencias limpias (y sin *newline* final) es **byte-idéntico** al de TEST vivo (que usa referencias con sufijo `1`) una vez normalizadas esas referencias, y byte-idéntico a la convención limpia del repo. Es decir: **la lógica es la misma**; lo único que cambia entre las tres formas son los nombres de las referencias `$('...')`. Ambos `jsCode` corregidos pasan `node --check` (sintaxis OK).

**Neutralidad de ambiente de los routers.** Ninguno de los dos routers contiene literales `__TEST`/`__OPS` ni valores de ambiente: son *flavor-neutrales* por diseño. Por eso el mismo `jsCode` sirve tal cual para los dos ambientes, y por eso el fix se puede aplicar **editando OPS en el lugar** sin arrastrar nada de TEST.

---

## 3. Diferencias AMBIENTALES — conservar OPS

Legítimas: reflejan que TEST y OPS apuntan a recursos distintos. **No** se copian desde TEST; se conservan las de OPS. Detalle completo con paths en `MANIFIESTO_AMBIENTES_A07.md`.

| Ítem | Nodo(s) | Naturaleza |
|---|---|---|
| Webhook path | `Webhook` | `__TEST` vs `__OPS` |
| `webhookId` | `Webhook` | UUID interno distinto |
| Credenciales PostgreSQL | `leer_ambiente`, `PG-0..PG-4` (6 nodos) | `vita_supabase_test` vs `vita_supabase_ops`; id distinto |
| Subworkflow avisos 8C-bis | `Call '...__FLAVOR' (aviso)` | `name` + `workflowId.value` + `cachedResultUrl` distintos; `cachedResultName` solo en TEST |
| Prefijo de idempotencia | `Code: derivar` | `portal_test_a07_` vs `portal_ops_a07_` |

> **`Code: derivar` NO se toca.** Su única diferencia real es el prefijo de idempotencia embebido (`portal_test_a07_` vs `portal_ops_a07_`) más el comentario de cabecera. La lógica es idéntica. Copiarlo desde TEST rompería el prefijo de OPS.

---

## 4. Diferencias COSMÉTICAS — no tocar

No cambian la ejecución.

| Ítem | Detalle |
|---|---|
| `id` / `versionId` (top-level) | Identificadores de instancia; se remueven en el repo, n8n los regenera. |
| `settings` | TEST trae extras (`availableInMCP: true`, `timeSavedMode`, `callerPolicy`); OPS mínimo (`availableInMCP: false`). Conservar los de OPS. |
| UUID de condición del `IF aviso 8C-bis` | Identificador interno distinto; la lógica de la condición es idéntica. |
| Comentarios de cabecera con flavor | En `validar_firma_ts_rol`, `verificar_acceso`, `Code: render`, `Code: derivar`. |
| Posiciones y orden del array de nodos | n8n ejecuta por `connections`, no por posición u orden. |
| Nodo `Respond` | El vivo omite `respondWith` (usa el default `firstIncomingItem`); el template lo declara explícito. **Mismo comportamiento.** |

---

## 5. Fallback HMAC (aclaración, sin acción)

En **ambos** exports, el nodo `validar_firma_ts_rol` tiene, en la línea del ternario `const SECRET`, un **dummy sintético de 64 caracteres, sin valor operativo**, colocado únicamente para preservar longitud en los exports de trabajo. **No es el secreto real.** Estructura (fallback mostrado como marcador):

```
const SECRET = ($vars.VITA_HMAC_SECRET) ? $vars.VITA_HMAC_SECRET : '<dummy-sintetico-64>';
if (!SECRET || SECRET.startsWith('__PEGAR_')) throw ...
```

El cuerpo de `validar_firma_ts_rol` es **idéntico** en TEST y OPS (por eso no forma parte del fix). En el **template del repo** esta línea es el placeholder `__PEGAR_SECRETO_O_USAR_VARIABLE__` (33 chars), que es lo que llevan los artefactos versionables.

No hay ninguna corrección ni rotación pendiente por este literal: el secreto operativo se toma de `$vars.VITA_HMAC_SECRET`. Se documenta solo para que el dummy no se confunda con un secreto (ni se clasifique como tal por su longitud).

---

## 6. Verificación

| Chequeo | Resultado |
|---|---|
| Validez JSON de ambos exports | ✅ |
| Conteo de nodos / aristas / tipos | ✅ (§1) |
| `jsCode` corregido de los 2 routers · `node --check` | ✅ sintaxis OK |
| `jsCode` corregido byte-idéntico a TEST vivo (refs normalizadas) | ✅ |
| Verificador `verificador_a07.py` (Candidato vs Template vs TEST) | ✅ **exit 0 — paridad funcional confirmada** |
| Tokens de conducta presentes en Candidato/Template | ✅ router1: `gap_checkin`, `gap_checkout`, `override_hora_invalido`, `fecha_in_pasada` · router3: `gap_checkin`, `gap_checkout`, `estado_incierto`, `recheck` |
| Literal HMAC en artefactos versionables | ✅ placeholder `__PEGAR_SECRETO_O_USAR_VARIABLE__` (el fallback del export es un dummy sintético) |
| Metadata de instancia en artefactos versionables | ✅ removida (`id`/`versionId` ausentes, `meta = null`) |

El verificador imprime además una nota `[HMAC]` **informativa** (describe el dummy sintético del fallback; no lo compara ni lo imprime, y no clasifica ningún literal como secreto por su longitud) y valida `active` como **estado de despliegue** (versionables inactivos, vivos activos), sin que ninguno de los dos afecte el exit code.

El verificador corre además **self-tests negativos** que garantizan que el exit 0 es **imposible** si se modifica cualquiera de: `onError`, `alwaysOutputData`, `disabled`, `retryOnFail`, `maxTries`, `waitBetweenTries`, `executeOnce`, `settings.executionOrder`, `settings.binaryMode`, la cantidad de nodos (duplicado), los nombres normalizados (colisión), el flavor de las credenciales PostgreSQL, o cualquier literal funcional del `jsCode` de los routers. Un self-test positivo confirma, en paralelo, que cambiar **solo** el dummy HMAC no produce diferencia ni lenguaje de secreto.

---

## 7. Conclusión

- El delta funcional entre OPS y TEST es **exactamente dos nodos** (`router1_crear` y `router3_confirmar`), y consiste en agregar el manejo de dos gaps de calendario y sumar `override_hora_invalido` a la lista de errores de payload (se mapea a `payload_invalido`) —es un código de error del motor SQL, no un flag del cliente— y, en `router1_crear`, recuperar `fecha_in_pasada`.
- Todo lo demás que difiere es **ambiental** (conservar OPS) o **cosmético** (ignorar).
- La forma correcta de aplicar el fix es **editar OPS en el lugar**, reemplazando solo el texto del campo `jsCode` de esos dos nodos — así los cinco valores ambientales críticos de OPS se conservan automáticamente.
- El literal del fallback HMAC es un dummy sintético sin valor operativo (§5): no requiere corrección ni rotación.

Procedimiento paso a paso en `GUIA_COPIA_A07_TEST_A_OPS.md`. Pruebas posteriores en `PLAN_PRUEBAS_A07.md`.
