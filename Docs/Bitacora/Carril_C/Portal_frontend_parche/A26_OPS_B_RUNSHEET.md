# OPS-B — Runsheet: A26 en el gateway `portal-api` OPS (`disponibilidad.cabana`)

**Etapa:** Promoción A26 a OPS — Bloque **OPS-B**. Expone `disponibilidad.cabana` por el gateway OPS apuntando a `portal-a26-disponibilidad__OPS`. **Esto des-rompe la grilla** de A07/A08 en OPS (el frontend ya está desplegado y llama A26).
**Alcance:** SOLO gateway OPS. **NO** toca: wrapper n8n (OPS-A ya verde), frontend, SQL/canónico, B2/B3/OPS-H, CORS, HMAC, JWT, dispatch, getUser, allowlist general, ni ninguna otra action.
**Quién ejecuta:** Franco (despliega la Edge Function OPS y corre el smoke). Claude generó/validó; no toca OPS.
**Read-only:** `disponibilidad.cabana` es lectura pura → cero escrituras, cero secuencias, cero reservas/bloqueos/pagos.

---

## 0. Artefactos de OPS-B

| Archivo | Qué es |
|---|---|
| `portal-api_OPS_index_A26.ts` | Gateway OPS **completo** con A26 agregado (= `supabase/functions/portal-api/index.ts` de OPS). |
| `A26_GW_smoke_OPS.ps1` | Smoke gateway OPS read-only (JWT por rol, auth, payloads, `no_encontrado`, META allowlist). |

## 1. Pre-flight (vos)

- **OPS-A verde** (wrapper `portal-a26-disponibilidad__OPS` activo, smoke directo 13/0/2).
- **HMAC coherente:** el HMAC que pegaste en el wrapper (OPS-A) **debe ser el mismo** `VITA_HMAC_SECRET` que tiene el gateway OPS. El gateway firma server-side y el wrapper revalida; si difieren, el wrapper devuelve `firma_invalida`. (Es el mismo secreto OPS de los otros `__OPS`.)
- **Gateway OPS = repo:** confirmá que la Edge Function `portal-api` desplegada en OPS coincide con `portal-api_OPS_index.ts` (sin parches manuales). Vas a desplegar la versión con A26 sobre esa base.

## 2. Cambio en el gateway (qué se agregó)

Diff **100% aditivo** (`+38` líneas, cero borrados/modificaciones), en dos lugares:
1. **Antes del `CATALOG`** (línea 638): `const SPAN_MAX_A26_GW = 366;` + `export const payloadDisponibilidadCabana` (validator: reject-unknown `{id_cabana, fecha_desde, fecha_hasta}`, `id_cabana` entero positivo, fechas YMD, `hasta>desde`, span ≤ 366). Declarado **antes** del CATALOG → sin temporal-dead-zone.
2. **En el `CATALOG`, después de `gastos.listado`**: 
   `'disponibilidad.cabana': { handler:'n8n', roles:['vicky','socio'], webhook:'portal-a26-disponibilidad__OPS', validate: payloadDisponibilidadCabana }`.

**Intacto:** CORS (`CORS_ALLOW_ORIGIN`), HMAC (`VITA_HMAC_SECRET`), JWT/`getUser`, dispatch, `Deno.serve`, las 14 actions previas, todos los flags. El validator reusa `isYMD_GW` y los tipos ya existentes (no se duplican).

## 3. Desplegar la Edge Function OPS

1. Reemplazá el contenido de `supabase/functions/portal-api/index.ts` (proyecto OPS) por `portal-api_OPS_index_A26.ts`.
2. Deploy a OPS (Dashboard → Edge Functions → portal-api → Deploy, o `supabase functions deploy portal-api --project-ref lpiatqztudxiwdlcoasv`).
3. **`verify_jwt` OFF** (el gateway hace su propio `getUser`). **Mismos secrets** (no se cambia ninguno): `SUPABASE_URL`, `SUPABASE_SECRET_KEYS`/`SERVICE_ROLE_KEY`, `VITA_HMAC_SECRET`, `VITA_AMBIENTE=ops`, `N8N_BASE_URL`, `CORS_ALLOW_ORIGIN`.

## 4. Smoke gateway (read-only)

1. **Definí las env vars OPS** (nada se imprime; podés usar prompt seguro si faltan):
   - `VITA_OPS_SUPABASE_URL` = `https://lpiatqztudxiwdlcoasv.supabase.co`
   - `VITA_OPS_GATEWAY_URL` = `https://lpiatqztudxiwdlcoasv.supabase.co/functions/v1/portal-api`
   - `VITA_OPS_ANON`, `VITA_OPS_VICKY_EMAIL/PASS`, `VITA_OPS_SOCIO_EMAIL/PASS`, `VITA_OPS_JENNY_EMAIL/PASS`.
2. (Opcional) `-CabValida <id>` con una cabaña activa OPS (default 1; confirmá con [A] del oráculo de OPS-A).
3. Corré: `powershell -ExecutionPolicy Bypass -File .\A26_GW_smoke_OPS.ps1`

**Guard anti-OPS:** FRENA (exit 3) antes de login si las URLs no contienen el ref `lpiatqztudxiwdlcoasv` y `/functions/v1/portal-api`. Login fallido → exit 2. Algún caso en rojo → exit 1.

**Casos (los 13 pedidos):**
| # | Caso | Espera |
|---|---|---|
| 1 | vicky | `ok:true` + `data.dias` no vacío |
| 2 | socio | `ok:true` + `data.dias` no vacío |
| 3 | jenny | `rol_no_permitido` |
| 4 | sin JWT | `no_autorizado` |
| 5 | action inexistente | `accion_desconocida` |
| 6 | cabaña inexistente (999999) | `no_encontrado` |
| 7 | rango invertido | `payload_invalido` |
| 8 | span > 366 | `payload_invalido` |
| 9a/b/c | `id_cabana` 0 / negativo / string | `payload_invalido` |
| 10 | clave desconocida | `payload_invalido` |
| 11 | falta `fecha_hasta` | `payload_invalido` |
| 12 | payload array | `payload_invalido` |
| 13 | META allowlist | todos los `error.code` ∈ allowlist |

**Verde esperado:** `PASS=15  FAIL=0`. La paridad ocupada/checkout no se testea acá (se cubrió en el contrato directo de OPS-A; igual queda disponible vía el oráculo si querés volcado). **Cero escrituras.**

## 5. Evidencia de validación (corrida por Claude)

| Check | Resultado |
|---|---|
| Diff `portal-api_OPS_index.ts` → `_A26.ts` **100% aditivo** (solo 2 inserts, +38 líneas) | OK |
| `'disponibilidad.cabana'` aparece **1 vez** en el CATALOG | OK |
| Apunta a `portal-a26-disponibilidad__OPS` | OK |
| **0** ocurrencias `portal-a26-disponibilidad` **sin sufijo** | OK |
| Las **14 actions previas** intactas (mismos counts) | OK |
| Validator + `SPAN_MAX_A26_GW` **antes** del CATALOG (sin TDZ) | OK |
| CORS / HMAC / `VITA_AMBIENTE` / `Deno.serve` intactos (sin cambios de secrets) | OK |
| `esbuild` del Edge Function (sintaxis TS) | **EXIT 0** |
| `tsc --noEmit --strict` sobre snippet autocontenido (tipos + validator + CATALOG) | **EXIT 0** |
| Smoke: ASCII puro, llaves balanceadas (127/127), guard anti-OPS, exit 0/1/2/3 | OK |
| Smoke: sin secretos hardcodeados (env/prompt), no invoca ninguna escritura, PII no se imprime | OK |
| Sin cambios de frontend, SQL/canónico, wrapper n8n, B2/B3 | OK |

> El validator se extrajo **verbatim** del gateway TEST (no se transcribió a mano). `tsc`/`deno check` completos del archivo no aplican en el entorno (Edge Function Deno con `jsr:` + `Deno.*`, sin `deno` instalado); por eso la validación de tipos/TDZ es por snippet autocontenido + esbuild de sintaxis sobre el archivo entero + orden textual del validator.

## 6. Después de OPS-B

Con el deploy y el smoke en verde, **la grilla de A07/A08 en OPS deja de estar rota** (A26 resuelve por gateway OPS). La **excepción D-FE-23 sigue viva** (frontend OPS más estricto que backend OPS en fechas pasadas) hasta **OPS-H** (promover B2/B3: `fecha_hoy_ar()` + guards en `crear_prereserva`/`crear_bloqueo` + `payloadInv` en los `__OPS` de A07/A08 + bump de canónico). Después de OPS-H, smoke visual / cierre.
