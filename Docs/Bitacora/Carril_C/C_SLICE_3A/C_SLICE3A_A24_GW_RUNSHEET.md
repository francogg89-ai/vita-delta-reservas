# C_SLICE3A_A24_GW_RUNSHEET.md — A24 `historico.reservas` (cableado en el gateway)

**Carril C / Slice 3a · Bloque gateway A24.** Cablear `historico.reservas` en `portal-api` + smoke por JWT. **TEST exclusivamente.** Read-only (sin `injectActor`, sin `isWrite`).

Prerrequisitos:
- **A24 directo cerrado en verde** (26/26 — ver `C_SLICE3A_A24_DIRECTO_CIERRE.md`).
- Wrapper `portal-a24-historico-reservas` **activo** en n8n TEST (el gateway le rutea).

Artefactos:
- `C_SLICE3A_A24_portal-api_index.ts` — gateway extendido (CATALOG 9→10).
- `C_SLICE3A_A24_GW_smoke.ps1` — smoke por JWT (reusa `C_SLICE2_A10_GW_common.ps1`).

---

## Qué cambió en el gateway (diff quirúrgico)

Sobre `C_SLICE2_A10_portal-api_index.ts`: **0 líneas eliminadas, 79 agregadas** (pura inserción). Solo dos bloques:

1. **Validador `payloadHistoricoReservas`** (+ consts `FLOOR_A24_GW`, `ENUM_ESTADO_RESERVA_GW`) **antes del `CATALOG`** (TDZ, L-C-11). Espejo exacto del paso 9 del wrapper; reusa `isYMD_GW`/`MAXLEN_GW`. Devuelve el payload **normalizado/whitelisteado** (`{ fecha_desde, fecha_hasta, id_cabana, estado, texto, limit, offset }`), que es lo que el handler firma y manda (`v.value`). El wrapper revalida idempotentemente (2da defensa).
2. **Entrada CATALOG** `'historico.reservas': { handler:'n8n', roles:['vicky','socio'], webhook:'portal-a24-historico-reservas', validate: payloadHistoricoReservas }` — **sin `injectActor`, sin `isWrite`** (lectura).

**No se tocó:** `dispatchN8n` · `buildSignedEnvelope` · `actorCoherente` · CORS · `CODIGOS_ERROR_PERMITIDOS` (allowlist) · `resolveEnv`/preflight · HMAC · ninguna de las 9 entradas previas del CATALOG.

---

## Pasos de ejecución (Franco)

**1. Deploy del Edge Function.** Reemplazá `supabase/functions/portal-api/index.ts` por `C_SLICE3A_A24_portal-api_index.ts` y deployá:
```
supabase functions deploy portal-api
```
*(o por el dashboard).* Las env vars del gateway (`VITA_AMBIENTE=test`, `N8N_BASE_URL`, HMAC, keys de Supabase) **ya están de Slice 1** — no se tocan. `VITA_AMBIENTE=test` hace que el gateway firme `ambiente_esperado='test'`, que matchea el `leer_ambiente` del wrapper.

**2. Preflight rápido.** Una llamada cualquiera autenticada NO debe dar 5xx por env faltante (el preflight es global y ruidoso). El smoke ya lo ejercita.

**3. Env vars del smoke** (las mismas de A08/A10):
```
VITA_SUPABASE_URL_TEST   = https://<ref-test>.supabase.co
VITA_SUPABASE_ANON_TEST  = <anon key TEST>
VITA_PW_VICKY  / VITA_PW_FRANCO / VITA_PW_JENNY   = passwords de los 3 usuarios portal
```
Si `C_SLICE2_A10_GW_common.ps1` está en otra carpeta (p.ej. `..\C_SLICE_2\`), editá `$CommonPath` arriba del smoke.

**4. Correr el smoke** y pegame la salida:
```
pwsh ./C_SLICE3A_A24_GW_smoke.ps1
```

---

## Criterios de PASS (gateway)

| # | Caso | Esperado |
|---|---|---|
| 1 | vicky (JWT) sin filtros | `ok:true` · `filas`+`total`+`limit=50`+`offset=0` |
| 2 | socio (franco, JWT) | `ok:true` · `filas` |
| 3 | jenny (JWT) | `rol_no_permitido` (rebota en el gateway, antes de firmar) |
| 4 | sin JWT | `no_autorizado` |
| 5 | action inexistente | `accion_desconocida` |
| F1 | sin filtros | `filas`+`total` |
| F2 | `fecha_desde=2026-07-10` | todas `fecha_checkin >= 2026-07-10` |
| F3 | `fecha_desde=2026-06-01` | **0 filas < 2026-07-01** (clamp en gateway y wrapper) |
| F4 | `id_cabana=5` | todas `id_cabana=5` |
| F5 | `id_cabana=3` (Arrebol) | `filas:[]` |
| F6 | `estado=confirmada` | todas `confirmada` |
| F7 | `estado=completada` | `filas:[]` |
| F8 | `texto` sin match | `filas:[]` |
| F9 | `limit=2 offset=0` | `≤2` filas · `total` presente |
| F10 | `limit=2 offset=2` | página distinta de F9 |
| P1–P5 | clave no permitida / fecha mala / estado fuera enum / `id_cabana=1.5` / `fecha_hasta<fecha_desde` | `payload_invalido` (rechazado en el gateway, antes de firmar) |
| P6a/P6b | `payload` string / array | `payload_invalido` |
| META | allowlist | todos los `error.code` en la allowlist |

**Cierre del bloque gateway A24** = smoke en verde (5 seguridad + 10 funcionales + 7 payload + META) **y** las 9 acciones previas intactas (garantizado por el diff de 0 líneas eliminadas). Con esto, A24 (directo + gateway) queda terminado; recién ahí arrancamos **A25**.

---

## Notas

- A diferencia del directo, en el gateway **no** se testean `firma_invalida`/`ts_fuera_de_ventana`/`ambiente_incorrecto`: el gateway los maneja server-side (firma y arma el sobre correctamente), no son superficie del cliente.
- El `payload` no-objeto (string/array) lo rechaza el validador del gateway (`payloadHistoricoReservas`) **antes** de firmar — el handler solo defaultea `null/undefined` a `{}`, no el resto.
- Anti-regresión opcional: una llamada `cobranza.saldos` con vicky debe seguir dando `ok:true` (no la cubre este smoke; el diff garantiza que no se tocó).

---

## Verificación previa hecha por Claude (antes de pasarte esto)

- Gateway: transpila con **esbuild** (sintaxis OK) · `payloadHistoricoReservas` pasa **`tsc --strict`** (cero errores de tipo) · se ejecutó el validador con **17 casos → 17 PASS** (idéntico al wrapper) · diff contra el base = **0 eliminadas / 79 agregadas** · validador antes del CATALOG (TDZ) · CATALOG 10 entradas · entrada A24 sin `injectActor`/`isWrite` · `dispatchN8n`/`buildSignedEnvelope`/`actorCoherente`/allowlist/CORS intactos.
- Smoke GW: ASCII puro · CRLF · llaves/paréntesis balanceados · reusa el común por dot-source. *(El parse-check de PowerShell y la ejecución contra Supabase los corrés vos.)*
