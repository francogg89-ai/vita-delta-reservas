# CARRIL C — SLICE 3b — A11 `cargar.gasto_interno` (GATEWAY `portal-api`) — CIERRE

**Estado:** ✅ **Extensión del gateway APROBADA en TEST.** A11 queda cableada de punta a punta por el **gateway `portal-api`** (autenticación JWT → `injectActor` server-side → firma HMAC → wrapper n8n → función). Es la **primera escritura no-idempotente** accesible vía gateway. Validada end-to-end por **smoke JWT** (seguridad + spoof + funcional con regresión Q4) contra Supabase + n8n TEST reales, más teardown FK-safe. Cierra el pendiente §7 del `C_SLICE3B_A11_DIRECTO_CIERRE.md`.

**Entorno de validación:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5, marcador `configuracion_general.ambiente='test'`.
**Entorno de operación:** — (A11 **no** se promovió a OPS; el Carril C **no** toca OPS para experimentar).
**Fecha de cierre:** 2026-06-22.
**Base:** `C_SLICE3B_A11_DIRECTO_CIERRE.md` (contrato A11, función `portal_cargar_gasto_interno`, `portal_idempotencia`, D-C-55/56, L-C-20) + `C_SLICE3A_A25_portal-api_index.ts` (gateway final de Slice 3a, CATALOG 11, **punto de partida**) + `C_SLICE2_A10_GW_smoke.ps1` / `C_SLICE2_A10_GW_common.ps1` (molde de smoke JWT de escritura con el assert de regresión).
**Depende de:** D-C-30 (JWT vía `getUser`) · D-C-34 (identidad/rol server-side desde `portal_usuarios`) · D-C-36/37 (dispatch a n8n firmado; `ambiente_esperado` desde `VITA_AMBIENTE`) · D-C-39/41 (doble allowlist rol×action + action binding) · D-C-18/35 (envelope uniforme; HTTP 200 + envelope para resultados manejados) · D-C-50/51 (`isWrite` → `estado_incierto` ante dispatch no confiable, jamás enmascara un write) · **D-C-55/56** (guard de dos capas; `nonce` derivado de la firma) · L-C-11 (validador declarado antes del CATALOG, TDZ) · L-C-17 (cuarteto PowerShell 5.1) · L-C-19 (BIGINT → number en el contrato).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.8.1` — **NO modificado por este cierre.** La extensión del gateway no introduce DDL; la infra de idempotencia (`portal_idempotencia`, `portal_cargar_gasto_interno`) ya existía del cierre directo, fuera del canónico.
**Autores:** Franco (titular, ejecutor de **todos** los deploys/smokes en Supabase y n8n) + Claude (arquitecto/copiloto; estrictamente advisory — no tocó infraestructura).
**Decisiones registradas:** D-C-57 🔒. **Lecciones:** L-C-21 📝. *(Propuestas en este documento hasta la propagación formal a satélites — §8.)*

---

## 1. Alcance

Extender el gateway `portal-api` para cablear **únicamente** la acción `cargar.gasto_interno` (A11), partiendo del gateway final de Slice 3a (CATALOG 11), y validarla por **smoke JWT**. El wrapper directo, la función `portal_cargar_gasto_interno` y `portal_idempotencia` quedan **inmutables** (cerrados en el directo); este cierre **no** los toca.

**Lo que el gateway agrega para A11:**
- Validación de payload de negocio **antes de firmar** (espejo del paso 10 del wrapper, doble allowlist D-C-39).
- Inyección de `actor` server-side desde `portal_usuarios.nombre` (`injectActor`), **nunca** del frontend.
- Recepción/validación de `idempotency_key` como **sibling de `payload`** y su firma **top-level** en el sobre (D-C-57).
- `isWrite` → ante dispatch no confiable devuelve `estado_incierto` (no enmascara un write).

**Fuera de alcance:** **A13** (`gastos.listado`, lectura), el cierre formal de Slice 3b (`C_SLICE3B_CIERRE.md` + propagación a satélites + CATALOG 11→13), y cualquier toque a OPS o al canónico (§7/§8).

---

## 2. Artefactos finales

**Gateway `portal-api` (TypeScript, deploy por Dashboard, `verify_jwt OFF`):**
- `C_SLICE3B_A11_portal-api_index.ts` — copia del gateway de Slice 3a + **6 cambios puramente aditivos** (verificado por diff: todo lo previo byte-idéntico):
  1. `CatalogEntry` (variante n8n): `+ needsIdempotencyKey?: boolean`.
  2. Validador `payloadCargarGastoInterno` (export), **declarado antes del CATALOG** (TDZ, L-C-11). Espejo exacto del paso 10 del wrapper: 13 claves permitidas (REJECT-UNKNOWN) + tipos + 2 enums (`clase` ∈ {A,C,D,E}, `pagador_tipo` ∈ {socio,caja}) + **rechazo explícito de control en payload** (`actor/rol/nonce/source_event/creado_por/request_ts/idempotency_key`). Devuelve el payload **normalizado/whitelisteado**. La **coherencia** (clase×zona/cabaña, pagador, comentario, horas, periodo) la siguen decidiendo las **18 constraints** de `gastos_internos` dentro de la función.
  3. Entrada CATALOG `'cargar.gasto_interno'`: `roles:['vicky','socio']`, `webhook:'portal-a11-cargar-gasto-interno__TEST'`, `validate:payloadCargarGastoInterno`, `injectActor:true`, `isWrite:true`, `needsIdempotencyKey:true`. **CATALOG 11 → 12.**
  4. `buildSignedEnvelope`: param opcional `idempotencyKey?` → emite `idempotency_key` **top-level** solo si presente (D-C-57). `nonce` sin cambios.
  5. `dispatchN8n`: threadea el `idempotencyKey?` opcional.
  6. Handler: **guard global** que rechaza control TOP-LEVEL del request para cualquier acción (defense-in-depth) + validación `IDEM_RE_GW` (`^[A-Za-z0-9_-]{8,64}$`) del `idempotency_key` sibling con **type-guard positivo** (narrowing TS strict).

**Smoke + teardown (PowerShell ASCII-puro / SQL):**
- `C_SLICE3B_A11_GW_smoke.ps1` — 24 casos por JWT. Reusa el helper congelado `C_SLICE2_A10_GW_common.ps1` (JWT, asserts, `Assert-Code-NotIncierto`, allowlist). Marcador de teardown `idempotency_key LIKE 'smoke-a11gw-<runid>-%'`.
- `C_SLICE3B_A11_GW_teardown.sql` — **idéntico byte-a-byte al teardown directo (`C_SLICE3B_A11_teardown.sql`) salvo el marcador** (`smoke-a11-` → `smoke-a11gw-`): gate `$gate$` (ambiente='test' + identidad de cabañas por nombre), borrado FK-safe (CTE traza → gasto), veredicto `jsonb` con `PASS/FAIL`, intacto el fixture 9F.

---

## 3. Evidencia (TEST)

**Validación estática del gateway (toolchain local):**
```
esbuild transpile ............................ OK
tsc --strict --noEmit ........................ 0 errores
harness validador A11 (52 casos) ............. 52/52 PASS
harness envelope byte-identidad (9 casos) .... 9/9 PASS
  - reads (sin actor) y writes previos (con actor): sobre BYTE-IDENTICO orig==a11
  - A11 con idempotencyKey: unico delta = idempotency_key appendeado al final
diff quirurgico (3a -> a11) .................. TODO ADITIVO
  - intocables byte-identicos: actorCoherente, CORS, ROLES_VALIDOS,
    CODIGOS_ERROR_PERMITIDOS, hmacSha256Hex
CATALOG ...................................... 11 -> 12 (las 11 previas verbatim)
```

**Smoke JWT (corrida real de Franco, runid `20260622114732970`):**
```
SMOKE GATEWAY A11 ............................ 24/24 PASS / 0 FAIL
  SEGURIDAD / TRANSPORTE (9): rol_no_permitido (jenny), no_autorizado (sin JWT),
    accion_desconocida, payload_invalido (clase invalida / payload string /
    idempotency_key ausente / corta / simbolos / vacia)
  SPOOF control EN payload (7): payload_invalido
    (actor/rol/nonce/source_event/creado_por/request_ts/idempotency_key dentro del payload)
  SPOOF control TOP-LEVEL (3): payload_invalido (combo / actor / nonce al tope del request)
  FUNCIONAL (4):
    F1 alta nueva (vicky, K1) ............... ok + id_gasto=47
    F2 retry idempotente (vicky, K1) ....... ok + idempotente:true + mismo id=47
    F3 payload_mismatch (vicky, K1) ........ conflicto (NUNCA estado_incierto)
    F4 actor_mismatch (franco, K1) ......... conflicto (NUNCA estado_incierto; valida injectActor)
  META allowlist ............................. PASS
  Codigos vistos: accion_desconocida, conflicto, no_autorizado, payload_invalido, rol_no_permitido
```

**Teardown (corrida real de Franco):**
```
veredicto = PASS | trazas_smoke_restantes = 0 | fixture_9f_intacto = 5
```

---

## 4. Notas de construcción / propiedades validadas

1. **Sobres de acciones previas byte-idénticos** (D-C-57). El param `idempotencyKey?` es inerte salvo para A11: con `idempotencyKey === undefined`, `buildSignedEnvelope` produce el mismo `body` firmado que antes (probado fijando `Date.now`/`randomUUID` y comparando orig 3a vs a11). Cero regresión para los 11 reads/writes previos.
2. **`nonce` genérico inerte para A11** (D-C-56). El sobre del gateway igual lleva un `nonce` UUID, pero el wrapper lo **ignora** y deriva el suyo de la firma esperada recomputada. Por eso `nonce_replay` **no es alcanzable de forma representativa vía gateway** (cada request del frontend re-firma → `ts`/firma distintos → nonce distinto); queda cubierto por el smoke **directo** (re-POST byte-idéntico). Los otros dos mismatches (`payload_mismatch`/`actor_mismatch`) sí se prueban end-to-end por gateway (F3/F4).
3. **Regresión Q4 sostenida.** `payload_mismatch`/`actor_mismatch` → `conflicto`, **nunca** `estado_incierto`. El gateway forwardea `conflicto` (allowlisted) sin convertirlo; `dispatchN8n`/`noConfiable` solo da `estado_incierto` ante dispatch no confiable (no ocurrió). Cero `estado_incierto`/`error_entorno`/`error_interno` en toda la corrida.
4. **`injectActor` probado.** F4 (franco con la `idempotency_key` de vicky + mismo payload) → `actor_mismatch`: el actor entra desde el **JWT** (`portal_usuarios.nombre`), no del payload; difiere del `vicky` registrado en F1. Un `actor`/control en el payload o al tope del request → `payload_invalido`.
5. **`idempotency_key` sibling, no clave del payload** (D-C-57). Viaja `{action, payload, idempotency_key}` (frontend→gateway) y top-level en el sobre (gateway→wrapper). El gateway lo valida fail-fast con `IDEM_RE_GW` antes de firmar (doble allowlist); el validador del payload lo **rechaza** dentro de `payload`.

---

## 5. Decisiones y lecciones nuevas

**🔒 D-C-57 — `idempotency_key` top-level en el sobre del gateway, vía param opcional aditivo.**
El wrapper A11 (inmutable) lee `body.idempotency_key` **top-level** y reject-unknownea control dentro del payload; el `nonce` lo deriva de la firma (D-C-56). Para que el sobre del gateway lleve `idempotency_key` top-level **sin** romper la condición "no tocar `buildSignedEnvelope`" tal como estaba redactada, se adopta la **Opción A**: `buildSignedEnvelope`/`dispatchN8n` reciben un param **opcional** `idempotencyKey?: string` que emite `idempotency_key` top-level **solo si está presente**. Para todo caller que no lo pase (los 11 reads/writes previos) el sobre queda **byte-idéntico** (probado, §3). El `idempotency_key` viaja **sibling de `payload`** (frontend→gateway), validado fail-fast en el gateway con `^[A-Za-z0-9_-]{8,64}$` (gobernado por `needsIdempotencyKey`). **D-C-56 sin cambios** (el `nonce` genérico sigue inerte para A11). El frontend **no** puede inyectar control ni en el payload ni top-level del request (guard global del handler + rechazo del validador) → `payload_invalido`.

**📝 L-C-21 — En TS strict, narrowing de `unknown` a string validado requiere type-guard POSITIVO.**
Para leer un campo `unknown` (ej. `idempotency_key` del request) y asignarlo ya estrechado a `string`, hay que usar la forma **positiva** `if (typeof x === 'string' && RE.test(x)) { key = x; } else return fail(...)`. La forma negada (`if (typeof x !== 'string' || !RE.test(x)) return fail(...); key = x;`) **no** estrecha `x` a `string` en la asignación posterior bajo `strict`, y rompe el `tsc`. (Patrón aplicado al guard de `idempotency_key` en el handler.)

---

## 6. Estado final

✅ **A11 `cargar.gasto_interno` — extensión del gateway `portal-api` CERRADA en TEST.**
Gateway validado estáticamente (esbuild + tsc strict + 52/52 + 9/9 + diff aditivo + intocables byte-idénticos, CATALOG 11→12); smoke JWT **24/24** (seguridad/spoof-payload/spoof-top-level/funcional Q4); teardown **PASS** (0 residuos, fixture 9F intacto). El gateway inyecta `actor` server-side, valida `idempotency_key` sibling, firma todo el sobre, no enmascara writes (cero `estado_incierto`) y deja byte-idénticas todas las acciones previas. A11 ahora es accesible por gateway **y** por wrapper directo.

---

## 7. Pendiente explícito

**A13 `gastos.listado` (lectura) — fase discreta, siguiente conversación:**
- Patrón Slice 3a (lectura sin `injectActor` ni `isWrite`): validador → entrada CATALOG → smoke JWT de lectura.
- Wrapper n8n firmado correspondiente (si aún no existe, se diseña/importa antes del cableado).
- **CATALOG 12 → 13** al cablear A13.

**Cierre formal de Slice 3b — después de A13:**
- `C_SLICE3B_CIERRE.md` + **propagación a satélites** + **CATALOG 11→13** en la documentación.

---

## 8. Aclaraciones (límites de este cierre)

- **No cierra Slice 3b.** Este es un **mini-cierre de la extensión del gateway de A11** (paralelo al mini-cierre del wrapper directo), no el cierre del slice. Slice 3b cierra tras **A13**.
- **Gateway desplegado en TEST con CATALOG 12.** En la **documentación satélite** el conteo de CATALOG sigue reflejando el estado previo hasta el cierre formal de Slice 3b (que lo lleva a 13 tras A13).
- **Satélites no propagados.** `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `CLAUDE.md`, `README.md` y `Pendiente_pre_produccion.md` se actualizan recién en el cierre formal del slice. **D-C-57 y L-C-21 quedan propuestas en este documento** hasta esa propagación (junto con D-C-55, D-C-56 y L-C-20 del cierre directo).
- **No se tocó la infra del directo.** El wrapper, `portal_cargar_gasto_interno` y `portal_idempotencia` quedaron inmutables.
- **No se tocó `6B_SCHEMA_SQL.md` ni OPS.** El canónico se bumpea una sola vez por carril, en la promoción coordinada a OPS. Toda la validación fue en TEST.

---
