# Bloque B — A26 `disponibilidad.cabana` en el gateway · Runsheet (deploy + smoke vía gateway, TEST)

**Etapa:** Carril C / Portal Operativo Interno — **Bloque B** (cableado de A26 en el `portal-api`).
**Ámbito:** 100% **TEST**. Edge Function `portal-api`. **Sin OPS, sin frontend, sin A07/A08, sin SQL/canónico, sin tocar otras acciones.**
**Rol:** Claude diseñó/validó/generó; **Franco ejecuta** (deploy del `index.ts` + smoke vía gateway). Frená al terminar.

---

## 1. Qué entrega el Bloque B

| Artefacto | Para qué |
|---|---|
| `portal-api_A26_TEST_index.ts` | `index.ts` del gateway **TEST** con A26 cableado (a desplegar). |
| `build_a26_gateway.py` | Builder con diff anclado (regenera el `index.ts` desde la base TEST). |
| `A26_GW_smoke.ps1` | Smoke **vía gateway** (JWT → Edge Function), reusa `C_SLICE2_A10_GW_common.ps1`. |

**Base del patch:** el `index.ts` TEST actual (A10MP_B2, 13 acciones n8n, sin `__OPS`). El builder inserta **solo 2 cosas** (diff: +47 líneas, 0 borrados, LF-puro):

1. el validador `payloadDisponibilidadCabana` (justo antes de `const CATALOG`);
2. la entrada CATALOG `'disponibilidad.cabana'` (tras la última lectura `'gastos.listado'`).

**Validación en build (verde):** `esbuild` transforma el archivo completo (sintaxis TS OK); `tsc --noEmit --strict` sobre el código nuevo aislado (tipos OK); el diff es exactamente esas 2 inserciones.

---

## 2. Diseño (qué se agrega y por qué nada más)

- **Entrada CATALOG (lectura pura):**
  ```ts
  'disponibilidad.cabana': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a26-disponibilidad', validate: payloadDisponibilidadCabana },
  ```
  - `roles: ['vicky', 'socio']` (D-C-39): jenny rebota con `rol_no_permitido` **en el gateway antes de firmar**.
  - `webhook: 'portal-a26-disponibilidad'` **sin sufijo** — convención de lecturas (A05/A12/A24/A25); coincide con el wrapper de Bloque A (que tu smoke directo ya validó).
  - **Lectura pura**: sin `injectActor`, sin `isWrite`, sin `needsIdempotencyKey`. El dispatch genérico ya maneja esto: actor `undefined`, y un dispatch no confiable devuelve `error_entorno` (no `estado_incierto`). En éxito reconstruye `ok(data)`.
- **Validador `payloadDisponibilidadCabana`** — ESPEJO exacto del wrapper (doble allowlist D-C-39/40): reject-unknown `{id_cabana, fecha_desde, fecha_hasta}`; `id_cabana` entero positivo seguro **obligatorio**; fechas YMD reales (reusa `isYMD_GW`) con `hasta > desde`; span ≤ 366; devuelve el payload whitelisteado. El gateway valida **antes de firmar**; el wrapper revalida antes del Postgres.
- **No se toca**: `dispatchN8n`, auth/JWT, CORS, env, ni ninguna otra acción del CATALOG. La compuerta SQL que evita evaluar la función para cabaña inválida vive en el **wrapper** (Bloque A); el gateway no la replica.

---

## 3. Deploy (TEST)

1. Reemplazá tu `supabase/functions/portal-api/index.ts` local por `portal-api_A26_TEST_index.ts`.
2. Desplegá a la Edge Function `portal-api` de **TEST** con tu flujo habitual de slices: `supabase functions deploy portal-api` apuntando al proyecto TEST (ref `bdskhhbmcksskkzqkcdp`), o pegándolo en el editor del dashboard.
3. **Sin cambios de entorno**: `VITA_HMAC_SECRET` (TEST), `VITA_AMBIENTE=test`, `N8N_BASE_URL`, `SUPABASE_*` ya están. `verify_jwt` sigue OFF (el handler valida el JWT). El wrapper `portal-a26-disponibilidad` ya está activo (Bloque A).

> No se promueve a OPS en este bloque. La promoción del gateway a OPS (sufijos `__OPS` para escrituras, etc.) es un paso posterior y coordinado.

---

## 4. Validación (smoke vía gateway)

1. Asegurate de tener el helper común `C_SLICE2_A10_GW_common.ps1` junto al smoke (o editá `$CommonPath`).
2. Exportá las variables de TEST: `VITA_SUPABASE_URL_TEST`, `VITA_SUPABASE_ANON_TEST`, `VITA_PW_VICKY`, `VITA_PW_FRANCO`, `VITA_PW_JENNY`.
3. Corré `A26_GW_smoke.ps1` (PS 5.1). Esperado: **15/15 PASS** + META allowlist OK.

**Casos del smoke (15):**

| # | Caso | Esperado |
|---|---|---|
| 1 | vicky, ventana libre | `ok:true` + `data.dias` no vacío |
| 2 | socio (franco), ventana libre | `ok:true` + `data.dias` no vacío |
| 3 | jenny | `rol_no_permitido` (gateway, antes de firmar) |
| 4 | sin JWT | `no_autorizado` |
| 5 | action inexistente | `accion_desconocida` |
| 6 | **paridad**: Tokio id=5, `2026-07-08..2026-07-16` | `ok:true`, `dias.Count=8`, `08`=bloqueada, `15`=checkout_disponible |
| 7 | cabaña inexistente (999999) | `no_encontrado` |
| 8 | rango invertido | `payload_invalido` (gateway) |
| 9 | span > 366 | `payload_invalido` |
| 10–12 | `id_cabana` 0 / negativo / string | `payload_invalido` |
| 13 | clave desconocida | `payload_invalido` |
| 14 | falta `fecha_hasta` | `payload_invalido` |
| 15 | payload array | `payload_invalido` |
| META | todos los `error.code` ∈ allowlist del gateway | OK |

> El caso 6 confirma **paridad gateway↔oráculo** con la misma ventana de Bloque A. LECTURA pura: el smoke no consume secuencias.

---

## 5. Verdict row

| Gate | Estado |
|---|---|
| `esbuild` archivo completo (sintaxis TS) | ✅ PASS |
| `tsc --noEmit --strict` código nuevo (tipos) | ✅ PASS |
| Diff = solo 2 inserciones (validador + entrada), 0 borrados, LF | ✅ |
| Smoke gateway ASCII-puro, delimitadores balanceados, 15 casos + META | ✅ build |
| Deploy a TEST + smoke 15/15 | ⏳ **lo ejecutás vos** |

---

## 6. Qué NO toca este bloque

OPS · frontend · A07/A08 · SQL/canónico (`6B_SCHEMA_SQL.md`) · `dispatchN8n`/auth/CORS/env · las otras 13 acciones del CATALOG · el wrapper de Bloque A (se **consume**).

---

**Handoff:** desplegá el `index.ts` parcheado a la Edge Function `portal-api` de TEST y corré `A26_GW_smoke.ps1`. Pasame el resultado (esperado 15/15 + META). Con eso, A26 queda expuesto end-to-end por el gateway en TEST; la promoción a OPS y la integración en los date pickers de A07/A08 (frontend) son frentes posteriores, cada uno con su bloque.
