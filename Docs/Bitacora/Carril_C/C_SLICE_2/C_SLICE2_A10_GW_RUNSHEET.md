# C_SLICE2 / A10 GATEWAY — RUNSHEET de smoke vía gateway (orden estricto)

End-to-end por el gateway `portal-api` → wrapper A10 firmado. **TEST only.** Extiende el
gateway de A07/A08 con la constante `ENUM_MEDIO_A10_GW` + `MONTO_MAX_A10_GW`, el validador
espejo `payloadRegistrarSaldo` (declarado **antes** del `CATALOG`, TDZ-safe, L-C-11) y la
entrada de CATALOG `'cobranza.registrar_saldo'`. Reusa toda la infra A07/A08 (firma HMAC,
JWT, `buildSignedEnvelope` con actor, `dispatchN8n` con `isWrite → estado_incierto`,
`actorCoherente`). **No agrega códigos de error nuevos** (D-C-51: el wrapper mapea todo a la
allowlist existente).

El `actor` se inyecta server-side desde `portal_usuarios.nombre` y el wrapper A10 lo usa como
`validado_por`. El smoke **nunca** firma HMAC ni ve el secreto: se autentica con **JWT** y el
gateway firma hacia n8n internamente.

---

## Diff aplicado al gateway (canónico nuevo: `C_SLICE2_A10_portal-api_index.ts`)

Tres adiciones quirúrgicas sobre el index de A08 (0 líneas borradas, 0 modificadas):

1. `const ENUM_MEDIO_A10_GW = ['efectivo','transferencia_bancaria','transferencia_mp','cripto'];`
   y `const MONTO_MAX_A10_GW = 9999999999.99;` (junto a `ENUM_MOTIVO_GW`).
2. `export const payloadRegistrarSaldo` (después de `payloadCrearBloqueo`, **antes** del CATALOG).
   Espejo exacto de la capa de payload de `coreValidate` del wrapper (`a10_validator_core.mjs`):
   reject-unknown, `id_reserva` entero positivo, `monto` finito >0 con ≤2 decimales dentro de
   `NUMERIC(12,2)`, `medio_pago` en `ENUM_MEDIO_A10` (sin `mp_link`), `idempotency_key` 8–64
   `[A-Za-z0-9_-]`, `notas` opcional.
3. Entrada de CATALOG:
   ```ts
   'cobranza.registrar_saldo': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a10-registrar-saldo__TEST', validate: payloadRegistrarSaldo, injectActor: true, isWrite: true },
   ```

Verificado: transpile esbuild VERDE (0 warnings), EOL LF preservado, validador antes del CATALOG.

---

## Pre-condiciones de entorno (estado correcto antes del deploy)

1. **Wrapper A10 directo `portal-a10-registrar-saldo__TEST` ACTIVO** (`active:true`). El gateway
   despacha a su webhook productivo `/webhook/...`, que exige el workflow activo. **NO** se desactiva
   al final (a diferencia de A07/A08, que eran validaciones standalone): A10 queda accesible por el
   gateway en TEST.
2. **W09 (`vita_w09_cobranza_posterior`) INACTIVO** hasta decisión explícita posterior. El advisory
   lock de A10 cubre A10-vs-A10 únicamente; W09 no lo toma. Debe estar inactivo durante los smokes
   que escriben (precondición de concurrencia, D-C-50).
3. `index.ts` parcheado (`C_SLICE2_A10_portal-api_index.ts`) **desplegado** como la Edge Function
   `portal-api` de TEST (reemplaza el index de A08; trae A05+A07+A08+A10 + lecturas de Slice 1).
4. Env vars en la consola de los `.ps1`:
   - `VITA_SUPABASE_URL_TEST`, `VITA_SUPABASE_ANON_TEST`
   - `VITA_PW_VICKY`, `VITA_PW_FRANCO`, `VITA_PW_JENNY`
   > **Auth (RECONCILIADO con A08):** la capa HTTP/auth de `C_SLICE2_A10_GW_common.ps1` calca
   > `C_SLICE2_A08_GW_smoke.ps1` — `Invoke-RestMethod`, grant `/auth/v1/token?grant_type=password`,
   > header `apikey`. Las identidades `vicky@vitadelta.test` / `franco@vitadelta.test` /
   > `jenny@vitadelta.test` están hardcodeadas en el precheck y el smoke (igual que A08); por eso
   > NO hay env vars `VITA_EMAIL_*`. Si alguna identidad cambia, ajustar la constante en ambos `.ps1`.

---

## Orden de ejecución (corregido)

| # | Paso | Archivo | Escribe | Esperado |
|---|------|---------|:---:|----------|
| 1 | Wrapper A10 directo **ACTIVO** | (n8n: `active:true`) | — | webhook productivo disponible |
| 2 | W09 **INACTIVO** | (n8n: `active:false`) | — | sin otra vía de cobro sobre los fixtures |
| 3 | **Deploy** del `portal-api` parcheado | `C_SLICE2_A10_portal-api_index.ts` | — | Edge Function desplegada en TEST |
| 4 | **Precheck auth** | `C_SLICE2_A10_GW_precheck_auth.ps1` | no | vicky/franco/jenny con JWT; `cobranza.registrar_saldo` habilitado vicky/socio, **NO** jenny |
| 5 | **Setup fixtures** (fresco) | `A10_setup.sql` | sí | 9900001..9900007 (self-cleaning, idempotente) |
| 6 | **Gate residual (pre)** | `A10_gate_residual.sql` | no | escrituras de smoke = 0 (fixtures de setup no cuentan) |
| 7 | **Smoke gateway** | `C_SLICE2_A10_GW_smoke.ps1` | sí (a/b) | **8/8 PASS** + META allowlist |
| 8 | **Verif (actor inyectado)** | `C_SLICE2_A10_GW_verif.sql` | no | ver abajo |
| 9 | **Teardown FK-safe** | `A10_teardown.sql` | borra | NOTICE con filas borradas (namespace `portal_test_a10_%`) |
| 10 | **Gate post** | `A10_gate_post.sql` | no | todo en 0 |
| 11 | **Mantener A10 directo ACTIVO** | — | — | el gateway queda operativo en TEST |
| 12 | **Mantener W09 INACTIVO** | — | — | hasta decisión explícita posterior |

> **Corrección clave respecto del molde A07/A08:** NO hay paso `wrapper → active:false`. Si A10 se
> desactivara, el gateway no tendría a quién despachar. Lo que permanece inactivo es **W09**, no A10.

---

## Matriz del smoke (paso 7) — `C_SLICE2_A10_GW_smoke.ps1`

| caso | identidad (JWT) | payload | escribe | esperado |
|------|-----------------|---------|:---:|----------|
| a FELIZ vicky | vicky | 9900001, 50000, `transferencia_mp`, key `a10gwAvicky00001` | sí | `ok`; `idempotent_match:false`; `saldo_real_actual` 20000 |
| b FELIZ socio | franco | 9900002, 70000, key `a10gwBsocio00001` | sí | `ok`; `saldo_real_actual` 0 |
| c jenny | jenny | 9900001, 10000 | no | `rol_no_permitido` (allowlist gateway, antes de firmar) |
| d sin JWT | — | 9900001, 10000 | no | `no_autorizado` |
| e payload inválido | vicky | `medio_pago:'mp_link'` (no expuesto por A10) | no | `payload_invalido` (gateway, antes de firmar) |
| f spoof actor | vicky | `{…, actor:'franco'}` (clave extra) | no | `payload_invalido` (reject-unknown) |
| g action inexistente | vicky | `cobranza.registrar_saldo_X` | no | `accion_desconocida` |
| **R SOBREPAGO** (regresión) | vicky | **9900006** (saldo 70000), monto **80000**, key `a10gwRsobrepg0001` | **no** | **`conflicto`, JAMÁS `estado_incierto`** |

**Assert de regresión obligatorio (cierre A10 §7 / D-C-51).** El caso R usa `Assert-Code-NotIncierto`,
que falla ruidoso si el código es `estado_incierto`. El riesgo cubierto: `dispatchN8n`/`noConfiable`
convierte en `estado_incierto` cualquier respuesta `!res.ok` o con código fuera de allowlist para un
`isWrite`. A10 emite `excede_saldo → conflicto` (allowlisted) y el wrapper responde **HTTP 200** (la
única `Respond`, `responseCode:200`, recibe `render`/`render_error`/`render_error_pg`), así que
end-to-end debe llegar `conflicto`. Si llegara `estado_incierto`, revisar el `responseCode` del wrapper
(debe ser 200) — sería el único motivo que justificaría tocar el wrapper directo.

---

## Verif (paso 8) — `C_SLICE2_A10_GW_verif.sql`

Confirma lo que el envelope no muestra:
- `a → 9900001`: 1 pago `saldo` confirmado 50000, **`validado_por = vicky`** (actor del JWT, no del payload).
- `b → 9900002`: 1 pago `saldo` confirmado 70000, **`validado_por = franco`**.
- `R → 9900006`: **0 pagos de smoke** (la regresión de sobrepago no escribe).
- Listado de control: exactamente 2 filas de saldo del smoke (9900001 y 9900002); ninguna otra.

---

## Notas

- **Fixtures reusados:** `A10_setup.sql` / `A10_teardown.sql` / `A10_gate_residual.sql` /
  `A10_gate_post.sql` del bloque directo (mismos 9900001..9900007, fechas sintéticas 2099,
  guard anti-OPS). El `source_event` de las escrituras del gateway cae en el namespace
  `portal_test_a10_%`, así que el teardown directo las cubre.
- **Repetible:** el setup es self-cleaning; correrlo de nuevo limpia el namespace y reinserta
  (no duplica señas). Si re-corrés el smoke sin teardown, `a/b` darían `idempotent_match:true`
  (igual `ok:true`, sin duplicar) salvo que cambie la `idempotency_key`.
- **Sin auto-retry en el gateway:** ante dispatch no confiable de una escritura, el gateway
  responde `estado_incierto` (no `error_entorno`). Es justamente lo que la regresión vigila que
  NO ocurra en el camino de sobrepago (que es un resultado manejado, 200 + envelope).
- **No se toca:** workflow A10 directo, SQL A10 directo, W09, OPS, ni satélites. El cierre formal
  de Slice 2 (`C_SLICE2_CIERRE.md` + propagación) queda para después de validar este gateway.

## Límite de verificación (honesto)

Los `.ps1` no los pude ejecutar desde mi lado (sin `pwsh`/red/JWT). ASCII puro verificado (0 bytes
no-ASCII, 0 byte `0x94`); la lógica del gateway (validador + dispatch) está testeada en Node/esbuild;
las queries son SELECT/DELETE simples con guard anti-OPS. La validación real es al correrlos contra TEST.
