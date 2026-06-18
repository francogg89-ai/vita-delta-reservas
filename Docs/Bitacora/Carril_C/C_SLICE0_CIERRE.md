# CARRIL C — SLICE 0 (ESPINA DE SEGURIDAD) — CIERRE

**Estado:** ✅ **Cerrado y verificado en TEST.** Primera vertical del Portal Operativo Interno: la frontera de confianza completa (`login → JWT → gateway → rol → allowlist → HMAC → n8n → ambiente`) anda de punta a punta. Sin Slice 0 no opera ninguna acción del portal.
**Entorno de validación:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5.
**Entorno de operación:** — (Slice 0 **no** se promovió a OPS; el Carril C es independiente del Carril B y del canónico, y no toca OPS para experimentar).
**Fecha de cierre:** 2026-06-16.
**Base de diseño:** `CARRIL_C_BACKEND_API_DISENO_CIERRE.md` (cierre Backend/API: 25 acciones A01–A25, matriz rol×endpoint, modelo de identidad/frontera de confianza, error envelope, MVP por slices; D-C-01…28).
**Depende de:** D-C-13/14/15/16/18/22 (modelo de identidad y seguridad) — cerradas en el diseño.
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.8.1` — **NO modificado por este cierre.** `portal_usuarios` es infra nueva del Carril C, **TEST-only**, no promovida a OPS; no entra al canónico hasta una eventual promoción coordinada.
**Autores:** Franco (titular, ejecutor de **todos** los writes en Supabase y n8n) + Claude (arquitecto/copiloto; no tocó infraestructura — validó configs de nodos contra el schema de la instancia, solo lectura).
**Decisiones registradas:** D-C-29 a D-C-35 🔒. **Lecciones:** L-C-05 a L-C-09.

---

## 1. Resumen ejecutivo

Slice 0 construyó la **espina de seguridad** del portal: el camino mínimo que demuestra que una persona se autentica una sola vez, que su rol se resuelve **server-side** sin confiar en el navegador, y que **toda** llamada cruza una frontera de confianza con **doble defensa** antes de poder ejecutar algo.

Tres piezas. (a) La tabla **`portal_usuarios`** (identidad→rol, interna, invisible al Data API). (b) La Edge Function **`portal-api`** (gateway/BFF que valida el JWT, resuelve el rol, impone la allowlist rol×action y firma HMAC hacia n8n). (c) El **patrón de revalidación en n8n** (un workflow probe que recomputa el HMAC sobre el raw body, valida la ventana de tiempo y el ambiente). La acción **`sesion.contexto`** (A02) quedó como primer vertical end-to-end, resuelta íntegra en la Edge Function **sin tocar n8n**.

La validación fue empírica: **6/6 smokes** de `portal-api` (rol por usuario, sin-JWT, JWT inválido, acción desconocida) y **4/4 casos** del probe n8n (firma válida, firma mala, `ts` viejo, cruce de ambiente). El caso 1 del probe cerró además la salvedad técnica abierta en D-C-29: el HMAC firmado sobre los **bytes literales** del body **validó byte a byte en n8n**, así que **no hizo falta** el fallback de JSON canónico.

La defensa en profundidad quedó demostrada de punta a punta: `portal-api` valida (JWT → rol → allowlist → HMAC) y **n8n revalida** (HMAC sobre raw body + `ts` + `ambiente`) antes de cualquier acción. Metodología estricta respetada: diseño aprobado → decisiones numeradas → artefactos verificables → Franco ejecuta cada paso → verificación.

---

## 2. Qué quedó construido en TEST

### 2.1 Tabla `portal_usuarios` (Fase A)
- DDL con **gate de entorno** (`configuracion_general('ambiente')='test'`), FK a `auth.users` (`ON DELETE CASCADE`), CHECK de `rol ∈ {jenny,vicky,socio}`, `nombre` TEXT UNIQUE (identificador de **persona**, D-C-22), `activo`.
- **Hardening D-C-34:** REVOKE a `PUBLIC`/`anon`/`authenticated`; GRANT **SELECT** solo a `service_role`. **Assert duro** en el DDL: rollback si `anon`/`authenticated` pudieran leer la tabla.
- **5 usuarios sembrados por email** (franco/rodrigo/remo = `socio`; vicky = `vicky`; jenny = `jenny`), resolviendo `user_id` contra `auth.users` (el SQL no contiene UUIDs ni passwords).

### 2.2 Edge Function `portal-api` (Fase B)
- Gateway/BFF en `supabase/functions/portal-api/`, con **`verify_jwt = false`** (la validación del JWT ocurre **en el handler**, para devolver siempre el envelope uniforme).
- Flujo: CORS → **preflight de env** (resuelve la secret key nueva/legacy; exige `VITA_HMAC_SECRET`; aborta ruidoso si falta algo) → parseo `{action,payload}` → JWT del header `Bearer` → **`getUser`** (D-C-30) → lookup `portal_usuarios` server-side (secret key) → chequeo `activo` → catálogo → **allowlist rol×action** (D-C-31) → dispatch.
- `sesion.contexto` (A02) devuelve `{ok:true,data:{nombre,rol,acciones}}`, resuelto íntegro, **sin n8n**.
- Helper de firma HMAC (`buildSignedEnvelope`: bytes literales del body + `ts`/`nonce`) construido y listo; **ninguna acción de Slice 0 lo usa todavía** (fiel a "una acción en allowlist = una acción wired"; se ejercita recién en los workflows de acción de Slice 1+).

### 2.3 Workflow n8n `portal-probe-ambiente` (Fase C)
- Pipeline lineal: `Webhook (Raw Body)` → `validar_firma_ts` (Code: HMAC-SHA256 sobre el raw body **desde binario**, comparación timing-safe, ventana `ts` ±300 s) → `leer_ambiente` (Postgres, credencial TEST `vita_supabase_test`) → `verificar_ambiente_responder` (Code: compara `ambiente_esperado` vs real, arma envelope D-C-18) → `responder` (HTTP 200 + envelope, D-C-35).
- Exportado al repo como **`portal-probe-ambiente__TEMPLATE.json` sanitizado** (secreto y credencial → placeholder; ids de instancia/versión limpiados; `active:false`).

---

## 3. Fases ejecutadas (bitácora)

| Fase | Qué | Resultado |
|---|---|---|
| **A** | `portal_usuarios` DDL + 5 usuarios en Supabase Auth + seed por email | tabla creada; grants D-C-34 verificados; 5 filas sembradas |
| **B** | `portal-api` desplegada (verify_jwt OFF; secreto seteado) | **6/6 smokes verdes**; `getUser` con secret key confirmado |
| **C** | workflow n8n probe + script PowerShell de firma | **4/4 casos verdes**; raw body byte a byte confirmado |

---

## 4. Decisiones registradas (D-C-29 a D-C-35) 🔒

- **D-C-29** — **HMAC:** HMAC-**SHA-256** sobre los **bytes literales** del body (`{action,payload,rol,ambiente_esperado,ts,nonce}` serializado una sola vez); header `X-Vita-Signature: sha256=<hex>`; `ts` epoch ms + `nonce` uuid **dentro** del body firmado; tolerancia de clock-skew **±300 s**; **sin store persistente de nonce en Slice 0** (la ventana de tiempo alcanza; la tabla de unicidad se suma en la primera escritura no-idempotente sin guard sobre n8n —realísticamente A11— o en hardening). **Salvedad de raw body cerrada empíricamente** (probe Fase C): n8n recomputa el HMAC sobre el raw body y valida byte a byte ⇒ **no** se necesita el fallback de JSON canónico.
- **D-C-30** — **Validación del JWT** en `portal-api` vía **`supabase.auth.getUser(jwt)`** (no verificación local con JWT secret), con **`verify_jwt = false`** en `config.toml` para que la validación ocurra en el handler y siempre devuelva el envelope uniforme: simplicidad, revocación correcta, un secreto menos. Confirmado empíricamente que funciona con el cliente creado con la **secret key** server-side (no hace falta un cliente aparte con publishable key).
- **D-C-31** — **Allowlist rol×action = constante versionada en código** en la Edge Function (`CATALOG`), no tabla: política-como-código auditable en git, sin hop de red, sin drift entre lo impuesto y lo desplegado. Una acción aparece en el catálogo **solo cuando está wired** (Slice 0: únicamente `sesion.contexto`). n8n revalida su propia allowlist por-workflow (segunda defensa).
- **D-C-32** — **Usuarios del portal creados por Dashboard** en Supabase Auth (TEST, con **Auto Confirm ON**; emails `@vitadelta.test`) + **seed por email** (`INSERT…SELECT` resolviendo `user_id` contra `auth.users`): el SQL del repo no contiene UUIDs ni passwords. Emails reales diferidos a OPS.
- **D-C-33** — **Secretos por entorno:** `VITA_HMAC_SECRET` en **Supabase secrets** (TEST), **mismo nombre** de variable en OPS con **valor distinto**; la secret key se resuelve **defensivamente** (`SUPABASE_SECRET_KEYS[default]` → legacy `SUPABASE_SERVICE_ROLE_KEY`) con **preflight ruidoso** que aborta si falta `SUPABASE_URL` / secret key / `VITA_HMAC_SECRET`. Nada de secretos al repo; workflows n8n exportados como `__TEMPLATE` **sanitizado**.
- **D-C-34** — **`portal_usuarios` es interna:** vive en `public` pero con permisos **revocados** a `anon`/`authenticated` (roles del navegador) y **solo SELECT** a `service_role` (lector server-side de `portal-api`). El Data API no la ve; rol y acciones se exponen **únicamente** vía `sesion.contexto`. **Assert duro** en el DDL (rollback si el navegador pudiera leerla). Misma estrategia que las 9 tablas del Carril B.
- **D-C-35** — **Contrato HTTP de `portal-api`:** **HTTP 200 + envelope** (`{ok:...}`) para **todo resultado manejado** (auth/permiso/negocio); **5xx solo para fallos inesperados** (preflight de config incompleto, excepción no controlada). El frontend lee siempre `body.ok`; `error.code` lleva la semántica. (Si se quisieran códigos HTTP por clase para observabilidad de infra, es un cambio acotado en el helper.)

---

## 5. Lecciones aprendidas (para `Lecciones_Aprendidas.md`)

- **L-C-05** — En este n8n Cloud, el nodo Webhook con **"Raw Body" ON entrega el cuerpo crudo como BINARIO** (`item.binary.data`, mime `application/json`), **no** como `$json.rawBody`. Para el HMAC byte-exacto se lee con `await this.helpers.getBinaryDataBuffer(0,'data')` en el Code node (con fallback a `rawBody`). Aplica a **todos** los workflows de acción de Slice 1+ que validen firma sobre el raw body.
- **L-C-06** — Las Edge Functions creadas/editadas por el **Dashboard de Supabase reactivan solo** el toggle "Verify JWT with legacy secret" en **cada redeploy** desde el editor. Para `portal-api` (que valida el JWT en el handler) hay que **re-apagarlo después de cada edición**, o usar CLI + `config.toml` (`verify_jwt=false`), que **no** se resetea.
- **L-C-07** — **Fidelidad de bytes en PowerShell:** para que el HMAC valide, enviar el body como **byte-array UTF-8 explícito** y firmar **esos mismos bytes**; pasar un string deja que PowerShell lo re-encodee y rompe firma y parseo. (Misma familia que el lío de comillas de `curl.exe` en PowerShell 5.1: para JSON con comillas, usar `Invoke-RestMethod` + `ConvertTo-Json`, no `curl.exe`.)
- **L-C-08** — **Nunca pegar secretos reales en artefactos compartidos**; sanitizar **antes** de exportar/commitear. La sanitización del `__TEMPLATE` se hace programáticamente con un **assert duro** que aborta si el secreto sigue presente en el JSON final. Si un secreto se expone, **rotarlo** (generar nuevo, actualizar los dos lados, el viejo queda inútil) — barato mientras no haya nada productivo dependiendo de él. *(Aplicado: el `VITA_HMAC_SECRET` de TEST se rotó el 2026-06-16.)*
- **L-C-09** — Supabase está **migrando sus API keys:** conviven `SUPABASE_SECRET_KEYS` / `SUPABASE_PUBLISHABLE_KEYS` (dict JSON por nombre, key `default`) con las legacy `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_ANON_KEY`, y en proyectos migrados la var legacy puede **contener** la key nueva. Resolver la secret key **defensivamente** (`SECRET_KEYS[default]` → legacy) con preflight ruidoso. El prefijo **`SUPABASE_` está reservado** para secrets (por eso el HMAC va como `VITA_HMAC_SECRET`). `crypto` está **whitelisteado** en el Code node de n8n Cloud (se usa con `require`).

---

## 6. Evidencia de pruebas

**Smokes `portal-api` (Fase B)** — todos HTTP 200 + envelope:
1. Vicky → `{ok:true,data:{nombre:"vicky",rol:"vicky",acciones:["sesion.contexto"]}}`
2. Franco → `rol:"socio"`
3. Jenny → `rol:"jenny"`
4. sin JWT → `{ok:false,error:{code:"no_autorizado"}}`
5. JWT basura → `{ok:false,error:{code:"no_autorizado"}}`
6. acción desconocida → `{ok:false,error:{code:"accion_desconocida"}}`

> `rol_no_permitido` **no es testeable en Slice 0** (la única acción habilita los 3 roles); aparece como caso real en Slice 1.

**Probe n8n (Fase C):**
1. firma válida + `ambiente_esperado="test"` → `{ok:true,data:{ambiente:"test",rol:"vicky"}}` ← **prueba de fidelidad del raw body (cierra la salvedad de D-C-29)**
2. firma con secreto equivocado → `{ok:false,error:{code:"firma_invalida"}}`
3. `ts` 10 min viejo → `{ok:false,error:{code:"ts_fuera_de_ventana"}}`
4. `ambiente_esperado="ops"` contra workflow TEST → `{ok:false,error:{code:"ambiente_incorrecto",detail:{esperado:"ops",real:"test"}}}`; **OPS intacto**

---

## 7. Supuestos y límites del slice

- Slice 0 cablea **solo** `sesion.contexto`. Lecturas (Slice 1), escrituras (Slice 2/3), frontend visual y promoción a OPS quedan **fuera**.
- `rol_no_permitido` y el store anti-replay de `nonce` existen en el diseño pero **no se ejercitan** en Slice 0 (la primera acción restringida por rol llega en Slice 1; la tabla de nonce en la primera escritura no-idempotente sin guard, realísticamente A11).
- **CORS abierto (`*`)** en `portal-api` para Slice 0; restringir al origin del portal en hardening.
- Identidad = **persona** (D-C-22). Emails `@vitadelta.test` (placeholders); reales en OPS.
- El lookup de `portal_usuarios` usa `service_role` (lector server-side); rol Postgres dedicado de mínimos disponible como hardening posterior, no bloqueante.

---

## 8. Pendientes y handoff

- **→ Slice 1** (lecturas: reuse A03/A04/A05/A06/A12): primer caso real de `rol_no_permitido`; primeros **workflows de acción n8n** que reusan el patrón de revalidación de Fase C — **clave la lección L-C-05** (raw body como binario).
- **Hardening (pre-OPS):** restringir **CORS** al origin real del portal; generar el `VITA_HMAC_SECRET` de **OPS** (distinto de TEST); evaluar **store de nonce** persistente al entrar la primera escritura no-idempotente; evaluar **rol Postgres dedicado** de mínimos en lugar de `service_role` para el lookup.
- **Operativo n8n / Supabase:** el toggle "Verify JWT with legacy secret" se reactiva en cada redeploy desde el editor del Dashboard (L-C-06); usar CLI + `config.toml` si los redeploys se vuelven frecuentes.
- **Secreto rotado:** el `VITA_HMAC_SECRET` de TEST fue **rotado el 2026-06-16** tras quedar expuesto en un artefacto compartido; el valor viejo quedó inútil (ver L-C-08).

---

## 9. Deltas para documentos satélite (aplicar con este cierre)

- **`DECISIONES_NO_REABRIR.md`** — agregar **D-C-29 … D-C-35** (sección Carril C, después de D-C-28).
- **`Lecciones_Aprendidas.md`** — agregar **L-C-05 … L-C-09** (CRLF, después de L-C-04).
- **`ESTADO_ACTUAL_VITA_DELTA.md`** — Carril C / **Slice 0 cerrado en TEST**; `portal_usuarios`, `portal-api` y `portal-probe-ambiente` operativos en TEST; próximo **Slice 1** (lecturas).
- **`Pendiente_pre_produccion.md`** — agregar los pendientes de hardening de §8 (CORS origin, secreto OPS, nonce store, rol dedicado, toggle verify_jwt).
- **`CLAUDE.md`** — agregar quirks: rawBody **binario** en n8n Cloud, `crypto` whitelisteado en Code node, toggle verify_jwt que se reactiva, claves nuevas de Supabase / resolución defensiva.
- **`6B_SCHEMA_SQL.md`** — **sin cambios** (Carril C no toca el canónico; `portal_usuarios` es TEST-only).
- **`README.md`** — opcional: mención del Portal Operativo Interno / `portal-api` en el estado del proyecto.

---

## 10. Inventario de artefactos de la etapa

- **Fase A:** `C_SLICE0_A1_DDL_portal_usuarios.sql`, `C_SLICE0_A2_SEED_portal_usuarios.sql`, `C_SLICE0_A_RUNSHEET.md`.
- **Fase B:** `C_SLICE0_B_portal-api_index.ts` (→ `supabase/functions/portal-api/index.ts`), `C_SLICE0_B_RUNSHEET.md`.
- **Fase C:** `portal-probe-ambiente__TEMPLATE.json` (→ `Workflows/n8n/Supabase/`), `C_SLICE0_C_probe.ps1`, `C_SLICE0_C_validar_firma_ts_v2.js`, `C_SLICE0_C_RUNSHEET.md`.
- **Cierre:** este documento (`C_SLICE0_CIERRE.md`).
