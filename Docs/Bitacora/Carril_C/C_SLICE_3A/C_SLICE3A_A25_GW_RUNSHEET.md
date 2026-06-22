# C_SLICE3A_A25_GW_RUNSHEET.md — A25 `ingresos.cobrados_periodo` (cableado en el gateway)

**Carril C / Slice 3a · Bloque gateway A25.** Cablear `ingresos.cobrados_periodo` en `portal-api` + smoke por JWT. **TEST exclusivamente.** Read-only (sin `injectActor`, sin `isWrite`).

Prerrequisitos:
- **A25 directo cerrado en verde** (26/26 — ver `C_SLICE3A_A25_DIRECTO_CIERRE.md`).
- Wrapper `portal-a25-ingresos` **activo** en n8n TEST.

Artefactos:
- `C_SLICE3A_A25_portal-api_index.ts` — gateway extendido (CATALOG 10→11).
- `C_SLICE3A_A25_GW_smoke.ps1` — smoke por JWT (reusa `C_SLICE2_A10_GW_common.ps1`).

---

## Qué cambió en el gateway (diff quirúrgico)

Sobre `C_SLICE3A_A24_portal-api_index.ts`: **0 líneas eliminadas, 58 agregadas** (pura inserción). Dos bloques:

1. **Validador `payloadIngresosPeriodo`** (+ const `FLOOR_A25_GW = FLOOR_A24_GW`, mismo floor Carril B) **antes del `CATALOG`** (TDZ). Reusa `isYMD_GW`. **Preserva la ausencia real de `periodo_hasta`**: si el cliente lo omite, el `value` **no** incluye la clave (el wrapper aplica el default "hoy" sin tratarlo como explícito ni disparar el check de inversión). Si viene explícito (incluido `null`/no-string/mal formado/invertido) → `payload_invalido`. `periodo_desde` (clampeado al floor), `limit` y `offset` sí se normalizan siempre en `value`.
2. **Entrada CATALOG** `'ingresos.cobrados_periodo'` → `roles:['vicky','socio']`, `webhook:'portal-a25-ingresos'`, `validate: payloadIngresosPeriodo`. **CATALOG 10 → 11.**

**No se tocó:** `dispatchN8n`, `buildSignedEnvelope`, `actorCoherente`, CORS, `CODIGOS_ERROR_PERMITIDOS` (allowlist), `resolveEnv`/preflight, HMAC, `payloadHistoricoReservas` (A24), ni las 10 entradas previas.

---

## Pasos de ejecución (Franco)

**1. Deploy del Edge Function.** Reemplazá `supabase/functions/portal-api/index.ts` por `C_SLICE3A_A25_portal-api_index.ts` y deployá (`supabase functions deploy portal-api` o dashboard). Las env vars ya están de Slice 1 — no se tocan.

**2. Env vars del smoke** (las de A08/A10): `VITA_SUPABASE_URL_TEST`, `VITA_SUPABASE_ANON_TEST`, `VITA_PW_VICKY`/`VITA_PW_FRANCO`/`VITA_PW_JENNY`. Si el común está en otra carpeta, editá `$CommonPath` arriba del smoke.

**3. Correr el smoke** y pegame la salida:
```
pwsh ./C_SLICE3A_A25_GW_smoke.ps1
```

---

## Criterios de PASS (gateway)

| # | Caso | Esperado |
|---|---|---|
| 1 | vicky (JWT) `{}` | `ok:true` (default vacío hoy, total_cobrado=0) |
| 2 | socio (franco, JWT) | `ok:true` |
| 3 | jenny (JWT) | `rol_no_permitido` (rebota en el gateway) |
| 4 | sin JWT | `no_autorizado` |
| 5 | action inexistente | `accion_desconocida` |
| G1 | `periodo_hasta=2026-12-31`, `limit=200` | `total_cobrado=921200`, `total=4` |
| G2 | cuadre (`limit=200`) | `Σ por_medio = Σ por_tipo = Σ filas = total_cobrado` |
| G3 | `por_mes` | julio 670200 · noviembre 251000 |
| G4 | `por_medio` | efectivo 300200 · transferencia 621000 |
| G5 | `otros_movimientos` | extra 8500, **NO sumado** |
| G8 | `por_tipo` | solo `sena`/`saldo` |
| **G6** | **default `{}` (regresión)** | `ok:true`, `total_cobrado=0`, `filas:[]` → vacío por floor futuro **Y** `periodo_hasta` omitido preservado (si el gateway lo rellenara, daría `payload_invalido`) |
| G7 | `periodo_desde=2026-06-01` | recortado al floor → `total_cobrado=921200` |
| G9 | `limit=1` | `≤1` fila · `total=4` |
| G10 | `limit=2 offset=2` | página distinta de G9 |
| P1 | clave no permitida | `payload_invalido` |
| P2 | `periodo_desde` mal formado | `payload_invalido` |
| **P3** | **inversión explícita (regresión)** | `payload_invalido` (rebota en el gateway) |
| P4 | `periodo_hasta` mal formado | `payload_invalido` |
| **P5** | **`periodo_hasta` null explícito (regresión)** | `payload_invalido` (no se trata como omitido) |
| P6 | `limit` no entero | `payload_invalido` |
| P7a/P7b | `payload` string / array | `payload_invalido` |
| META | allowlist | todos los `error.code` en la allowlist |

**Cierre del bloque gateway A25** = smoke en verde (5 seguridad + 10 funcionales + 8 payload + META) **y** las 10 acciones previas intactas (garantizado por el diff de 0 líneas eliminadas). Con esto, A25 (directo + gateway) queda terminado.

---

## Notas

- Igual que A24, en el gateway no se testean `firma_invalida`/`ts_fuera_de_ventana`/`ambiente_incorrecto` (los maneja server-side).
- La diferencia de A25 vs A24 en el validador: `payloadIngresosPeriodo` **no** rellena `periodo_hasta` cuando se omite (a propósito), para no cambiar la semántica del híbrido respecto del wrapper directo. El resto del patrón es idéntico.

---

## Verificación previa hecha por Claude (antes de pasarte esto)

- Gateway: transpila con **esbuild** (sintaxis OK) · `payloadIngresosPeriodo` pasa **`tsc --strict`** · se ejecutó el validador con **13 casos → 13 PASS** (incluida la preservación de ausencia de `periodo_hasta` y el rechazo de null/no-string/invertido) · diff contra el gateway A24 = **0 eliminadas / 58 agregadas** · validador antes del CATALOG (TDZ) · CATALOG 11 entradas · entrada A25 sin `injectActor`/`isWrite` · `dispatchN8n`/`buildSignedEnvelope`/`actorCoherente`/allowlist/CORS y `payloadHistoricoReservas` intactos.
- Smoke GW: ASCII puro · CRLF · llaves/paréntesis balanceados · reusa el común por dot-source. *(El parse-check de PowerShell y la ejecución contra Supabase los corrés vos.)*
