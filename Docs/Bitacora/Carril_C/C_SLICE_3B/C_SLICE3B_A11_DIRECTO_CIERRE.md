# CARRIL C — SLICE 3b — A11 `cargar.gasto_interno` (WRAPPER DIRECTO) — CIERRE

**Estado:** ✅ **Wrapper directo APROBADO en TEST.** A11 es la **primera escritura no-idempotente** del Portal Operativo Interno: carga **un gasto interno** (`gastos_internos`) detrás de un wrapper n8n firmado, con un guard de dos capas (anti-replay de `nonce` + idempotencia de negocio por `idempotency_key`) atómico dentro de la función. Validado end-to-end por el **camino wrapper-directo** (seguridad + funcional + teardown) contra n8n + Supabase TEST reales. La extensión del **gateway** queda explícitamente pendiente (ver §7).

**Entorno de validación:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5, marcador `configuracion_general.ambiente='test'`.
**Entorno de operación:** — (A11 **no** se promovió a OPS; el Carril C **no** toca OPS para experimentar).
**Fecha de cierre:** 2026-06-22.
**Base:** `C_SLICE3A_CIERRE.md` (lecturas A24/A25, molde de wrapper, D-C-52…54, L-C-18/19) + `C_SLICE2_A10_DIRECTO_CIERRE.md` (espina de la **primera escritura**: estructura transaccional con lock, modelo de error de dos capas, teardown FK-safe, D-C-50/51, L-C-16/17) + `C_SLICE3B_SNAPSHOT_A11_A13.sql` (snapshot anti-OPS de `gastos_internos`, validado limpio).
**Depende de:** D-C-29 (store anti-replay de `nonce`, ventana `ts` ±300 s) · D-C-34 (infra del portal fuera del canónico, REVOKE a los 4 roles, no expuesta al Data API; precedente `portal_usuarios`) · D-C-39/41 (allowlist de rol + action binding) · D-C-43/47 (contrato JSON `{ok,data|error}`) · **P-C-9** (la tabla de unicidad de `nonce` se materializa al entrar la primera escritura no-idempotente sin guard sobre n8n — realísticamente A11) · L-C-05 (HMAC sobre los bytes del raw body binario) · L-C-10 (placeholder de secreto por prefijo `__PEGAR_`, Modo B) · L-C-16 (`($1::jsonb)` casteo del `queryReplacement` que llega como texto) · L-C-17 (cuarteto PowerShell 5.1) · L-8D-01 (leer `item.resultado.ok` del Postgres node) · L-9F-03 (DROP+CREATE en vez de `OR REPLACE`, evita auto-RLS de Supabase) · **D-NEG-01/02** (25 % operativo; inicio contable 2026-07-01) · **D-C-55, D-C-56** (este slice).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.8.1` — **NO modificado por este cierre.** A11 **no** introduce DDL ni columnas en tablas canónicas: `gastos_internos` se usa tal cual (17 columnas, 18 constraints) y la infra de idempotencia vive en una tabla **nueva fuera del canónico** (§2).
**Autores:** Franco (titular, ejecutor de **todos** los writes/deploys/imports/smokes en Supabase y n8n) + Claude (arquitecto/copiloto; estrictamente advisory — no tocó infraestructura).
**Decisiones registradas:** D-C-55, D-C-56 🔒. **Lecciones:** L-C-20 📝. *(Propuestas en este documento hasta la propagación formal a satélites — §8.)*

---

## 1. Alcance

A11 = **primera escritura no-idempotente** del Carril C. Registra **un** gasto interno en `gastos_internos`, vía el Portal Operativo Interno, detrás de un wrapper n8n firmado.

**Contrato de la acción** (`action = 'cargar.gasto_interno'`):
- **Roles:** `vicky`, `socio` (sin `jenny`, D-C-03).
- **Payload de negocio (13 claves, REJECT-UNKNOWN):** `fecha` (YYYY-MM-DD real), `periodo?` (día 1; default = primer día del mes de `fecha`), `clase` (`A`/`C`/`D`/`E`), `clase_sugerida?`, `etiqueta` (no vacía), `monto` (number > 0 → `numeric(12,2)`), `id_zona?`, `id_cabana?`, `pagador_tipo` (`socio`/`caja`), `id_socio_pagador?`, `medio_pago?`, `comentario?`, `comprobante_url?`.
- **Control server-side (lo inyecta el wrapper/gateway, NUNCA el cliente):** `actor`, `rol`, `nonce`, `request_ts`. En el camino **directo** el sobre firmado por el smoke trae `actor`/`rol` (simula la salida ya validada del gateway, igual que en Slice 2); el `nonce` lo **deriva el wrapper** de la firma (D-C-56); `request_ts` = `ts` del sobre.
- **Derivados por la función (no viajan en el sobre):** `source_event = 'portal_a11_' || idempotency_key` y `creado_por = actor`.
- **Coherencia:** las **18 constraints** de `gastos_internos` son el gate autoritativo (alcance clase×zona/cabaña, pagador, comentario obligatorio salvo `clase_sugerida=clase`, horas de trabajo → socio, periodo día 1, monto > 0, …). El validador del wrapper queda **fino** (forma/tipos/2 enums); cualquier violación de coherencia la mapea la función a `payload_invalido` con `detail.constraint`, y el savepoint revierte gasto + traza juntos.

**Fuera de alcance de este cierre:** la extensión del gateway `portal-api` (§7), el cierre formal de Slice 3b, **A13** (`gastos.listado`, lectura), y cualquier toque a OPS o al canónico (§8).

---

## 2. Artefactos finales

**Infra Carril C — TEST-only, FUERA del canónico, SIN OPS** (aplicada en TEST, 8/8 PASS):
- `C_SLICE3B_A11_DDL_infra_y_funcion.sql` — un solo run transaccional, gate anti-OPS duro (`ambiente='test'` + identidad de cabañas 1–5), que crea:
  - **`public.portal_idempotencia`** (`CREATE TABLE IF NOT EXISTS`) — infra del portal (precedente `portal_usuarios`, D-C-34). Sirve a la vez de **store anti-replay de `nonce`** (P-C-9), **store de idempotencia de negocio** y **traza/`source_event`**. 12 columnas (`id_registro` bigserial PK, `action`, `actor`, `rol`, `source_event`, `nonce`, `idempotency_key`, `payload_norm` jsonb, `id_gasto` bigint, `estado`, `request_ts`, `created_at`). Constraints: **PK + 2 UNIQUE** (`uq…_nonce` UNIQUE(`nonce`) → anti-replay; `uq…_action_key` UNIQUE(`action`,`idempotency_key`) → idempotencia) **+ 1 FK RESTRICT** (`id_gasto` → `gastos_internos.id_gasto`) **+ 7 CHECK** (no-vacío de los textos, `rol IN ('vicky','socio')`, `estado='ok'`). RLS off. **Nota de esquema:** `gastos_internos` **no** tiene columna `source_event`; la traza/`source_event` vive **solo** acá.
  - **`public.portal_cargar_gasto_interno(p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER`** (DROP+CREATE, L-9F-03). En UNA transacción: `pg_advisory_xact_lock(hashtext(action), hashtext(idempotency_key))` → anti-replay de `nonce` (EXISTS → `conflicto`/`nonce_replay`) → idempotencia `(action,idempotency_key)` (igual `payload_norm`+`actor` → `ok` idempotente; payload distinto → `conflicto`/`payload_mismatch`; actor distinto → `conflicto`/`actor_mismatch`) → alta nueva (INSERT gasto + INSERT traza en el **mismo sub-bloque con savepoint**; una violación de constraint revierte ambos → `payload_invalido` con `detail.constraint`, **sin huérfano**).
  - **Hardening D-C-34:** `REVOKE ALL`/`REVOKE EXECUTE` sobre tabla, secuencia y función a `PUBLIC`/`anon`/`authenticated`/`service_role`. La toca solo el nodo Postgres de n8n como owner (`postgres`). **No** expuesta al Data API.

**Wrapper directo** (importado y activo en n8n TEST; **sanitizado** para el repo — secreto → `__PEGAR_SECRETO_O_USAR_VARIABLE__`, credencial → `REEMPLAZAR_POR_CRED_TEST`, sin `webhookId`, `active:false`, `pinData:{}`):
- `portal-a11-cargar-gasto-interno__TEMPLATE.json` — 10 nodos: `Webhook(2.1, rawBody) → validar_firma_ts_rol → leer_ambiente → verificar_acceso → IF acceso → Code: derivar → PG cargar_gasto → router_cargar → Code: render → Respond`. `validar_firma_ts_rol` recomputa el HMAC sobre el raw body (Modo B, assert por prefijo), valida `ts`/`rol`/action binding/`actor`/`idempotency_key` y **deriva el `nonce`** (D-C-56); `Code: derivar` arma el jsonb de la función con el payload de negocio + control + `idempotency_key` (sin `source_event` ni `creado_por`); `PG cargar_gasto` llama `portal_cargar_gasto_interno($1::jsonb)` con `queryReplacement` y `onError:continueRegularOutput`; `router_cargar` pasa el contrato de la función y solo agrega `estado_incierto` si el dispatch no devolvió contrato.

**Smoke + teardown (PowerShell ASCII-puro / SQL, sanitizados):**
- `C_SLICE3B_A11_smoke_directo.ps1` — 26 casos de seguridad (0 escrituras) + funcional (5 altas + ciclo replay/retry/doble-click/conflictos) + META allowlist. Sobre **sin `nonce`** (D-C-56). Marcador de teardown `idempotency_key LIKE 'smoke-a11-<runid>-%'` (runid único por corrida). HMAC en PS espejado de A25; gotchas L-C-17 respetados.
- `C_SLICE3B_A11_teardown.sql` — borrado FK-safe por marcador `smoke-a11-%` (CTE data-modifying borra la traza → el DELETE principal borra el gasto; la FK RESTRICT fuerza ese orden), gate anti-OPS, veredicto de 0 residuos. **No** toca el fixture 9F (`creado_por='seed_9f_validacion'`).
- `C_SLICE3B_SNAPSHOT_A11_A13.sql` — snapshot read-only anti-OPS de `gastos_internos` (estructura/constraints), validado limpio antes del diseño.

---

## 3. Evidencia (TEST)

Corrida real contra `https://federicosecchi.app.n8n.cloud/webhook/portal-a11-cargar-gasto-interno__TEST` + Supabase TEST. RunID `20260622095134-f901e8`.

```
DDL infra + funcion (un run transaccional) ...... 8/8 PASS
  tabla portal_idempotencia + uq_nonce + uq_action_key + FK RESTRICT a gastos_internos,
  funcion creada, y tabla/secuencia/funcion CERRADAS al Data API (anon/authenticated/service_role).

SMOKE DIRECTO ................................... 38/38 PASS / 0 FAIL
  SEGURIDAD (26, 0 escrituras) ................. secWrites = 0 (empirico)
    transporte/auth (8): firma_invalida, ts_fuera_de_ventana (viejo/futuro), rol_no_permitido
      (jenny/vacio), accion_desconocida, ambiente_incorrecto (ops), payload_invalido (actor desconocido)
    wrapper payload (10): payload_invalido (idem ausente/corta/simbolos; payload string/array;
      clave desconocida creado_por; clase invalida; monto<=0; fecha invalida; pagador_tipo invalido)
    coherencia que llega a la funcion y REVIERTE (8): payload_invalido
      (clase D sin zona; clase E sin cabana; clase A con zona; pagador socio sin id_socio;
       pagador caja con id_socio; override sin comentario; horas de trabajo + caja; periodo dia!=1)
  FUNCIONAL (5 escrituras netas) ............... ids escritos A=42 C=43 D=44 E=45 rep=46
    F1-F4 altas A(caja)/C(caja)/D(zona,socio)/E(cabana,socio) ... ok nuevo
    F5a alta key -rep ............................ ok nuevo (id=46)
    F5b replay BYTE-IDENTICO ..................... conflicto / nonce_replay
    F5c retry (ts nuevo, misma key) ............. idempotente, mismo id=46
    F5d doble-click (otro ts) ................... idempotente, mismo id=46
    F5e misma key, monto distinto ............... conflicto / payload_mismatch
    F5f misma key, actor distinto ............... conflicto / actor_mismatch
  META allowlist ............................... PASS
  Codigos de error vistos ...................... accion_desconocida, ambiente_incorrecto, conflicto,
    firma_invalida, payload_invalido, rol_no_permitido, ts_fuera_de_ventana
    -> CERO estado_incierto, CERO error_interno en todos los caminos.

TEARDOWN ....................................... PASS
  detalle: { trazas_smoke_restantes: 0, fixture_9f_intacto: 5 }
  ids 42-46 + sus trazas barridos; fixture 9F intacto.
```

**Lo que la evidencia demuestra:** HMAC sobre bytes exactos + anti-replay (`ts` ±300 s, `nonce` único) + allowlist de rol + action binding + rechazo de payload **y de coherencia** sin escribir (seguridad: `secWrites=0`); idempotencia de negocio con control de mismatch (monto → `payload_mismatch`; actor → `actor_mismatch`) y actor server-side (funcional); y — lo central de D-C-56 — **el mismo sobre firmado byte-idéntico cae en `nonce_replay`, mientras un retry re-firmado con `ts` nuevo cae en la idempotencia por `idempotency_key` y devuelve el mismo `id_gasto`**. Mapeo de errores siempre a la allowlist; **cero `estado_incierto` y cero `error_interno`** en los caminos validados.

---

## 4. Notas de construcción / propiedades validadas

1. **`nonce` derivado de la firma ESPERADA, no del header** (D-C-56, microcorr. 1). El wrapper hace `nonce = expectedHex.toLowerCase()` sobre el HMAC que **recomputa** del raw body, no sobre el string crudo del header `x-vita-signature`. Esto evita que diferencias de formato/case/prefijo en el header rompan la estabilidad del `nonce` ante replay. Validado: re-POST byte-idéntico → mismo `nonce` → `nonce_replay`.
2. **`idempotency_key` con formato estricto** `^[A-Za-z0-9_-]{8,64}$` (D-C-56, microcorr. 2) — se valida en el wrapper y se usa para idempotencia **y** para construir `source_event`. Casos `abc123` (corta) y `clave!@#invalida` (símbolos) → `payload_invalido`.
3. **Coherencia = constraints, no validador.** El wrapper no replica las reglas cruzadas; deja que las 18 constraints de `gastos_internos` decidan. Las 8 coherencias llegaron a la función y rebotaron con `payload_invalido` + `detail.constraint` (`chk_gi_alcance`, `chk_gi_pagador_consist`, `chk_gi_comentario`, `chk_gi_horas`; el `periodo` día≠1 lo valida la función explícitamente). El savepoint revirtió gasto + traza juntos: **sin huérfanos** (estado final exacto 5 gastos / 5 trazas).
4. **Teardown FK-safe por dependencia de datos.** La FK `id_gasto` es `RESTRICT`, así que hay que borrar la **traza antes** que el gasto. Se hace en UN statement: un CTE data-modifying borra `portal_idempotencia` por marcador y devuelve `id_gasto` por `RETURNING`; el DELETE principal consume ese `RETURNING` para borrar `gastos_internos`. La dependencia de datos fuerza el orden; envuelto en `BEGIN/COMMIT`, `trazas_smoke_restantes=0` implica borrado completo y atómico.

---

## 5. Decisiones y lecciones nuevas

**🔒 D-C-55 — Estructura atómica de la carga de gasto (A11), guard de dos capas.**
A11 cumple **P-C-9** con un guard de **dos capas en UNA transacción**, todo dentro de `portal_cargar_gasto_interno` (Camino B — función infra; el INSERT inline se descartó para separar guard de inserción):
- **Capa 1 — anti-replay de `nonce`** (`UNIQUE(nonce)`): un sobre firmado ya visto → `conflicto`/`nonce_replay`.
- **Capa 2 — idempotencia de negocio** (`UNIQUE(action,idempotency_key)`) con comparación de `payload_norm` (jsonb normalizado, `IS DISTINCT FROM`) **y** `actor`: misma key + mismo payload + mismo actor → `ok` idempotente (devuelve el `id_gasto` existente); payload distinto → `payload_mismatch`; actor distinto → `actor_mismatch`.
- Secuencia: `pg_advisory_xact_lock(hashtext(action), hashtext(idempotency_key))` → capa 1 → capa 2 → alta nueva (INSERT gasto + INSERT traza en el **mismo sub-bloque con savepoint**; constraint → `payload_invalido` con `detail.constraint`, revierte ambos).
- **`portal_idempotencia` es infra del portal FUERA del canónico** (precedente `portal_usuarios`, D-C-34): store anti-replay + store de idempotencia + traza. **`gastos_internos` no lleva `source_event`**; la traza/`source_event` vive en `portal_idempotencia`.
- **`source_event = 'portal_a11_' || idempotency_key` y `creado_por = actor` los DERIVA la función**, nunca el cliente. Un `creado_por` en el payload → `payload_invalido` (REJECT-UNKNOWN del wrapper).
- Las **18 constraints de `gastos_internos`** son el gate de coherencia autoritativo.

**🔒 D-C-56 — `nonce` = firma HMAC del sobre.**
El cliente/frontend **nunca** manda `nonce`. El wrapper lo **deriva de la firma HMAC del sobre** que ya valida: mismo sobre byte-idéntico → misma firma → mismo `nonce` → `conflicto`/`nonce_replay`; retry re-firmado (otro `ts`) o doble-click lógico con la **misma** `idempotency_key` → `nonce` distinto pero respuesta **idempotente** con el mismo `id_gasto`. **Microcorrección 1:** `nonce = expectedSignatureHex.toLowerCase()` desde la firma esperada **recomputada y normalizada**, no del header crudo. **Microcorrección 2:** `idempotency_key` con `^[A-Za-z0-9_-]{8,64}$`. **`buildSignedEnvelope` no se toca** — la firma ya existe en ambos caminos (smoke en directo, `portal-api` en gateway), así que el gateway **no** genera `nonce`. Validado empíricamente en TEST (§3).

**📝 L-C-20 — En un hit idempotente el `nonce` nuevo NO se persiste; cobertura del store de `nonce`.**
Cuando la capa 2 resuelve un **hit idempotente** (misma `idempotency_key`, `payload_norm`+`actor` coincidentes), la función **devuelve el `id_gasto` existente sin INSERT** — por lo tanto el `nonce` de ese request **no** entra a `portal_idempotencia`. Implicación para auditar **P-C-9**: el store de `nonce` solo contiene los `nonce` de **altas nuevas**; un replay del sobre de un **retry** lo atrapa la **idempotencia de negocio**, no el `nonce_replay` (que solo cubre el reenvío exacto del sobre cuyo `nonce` sí se persistió, el del alta). Ambas capas convergen en la misma semántica externa (reenviar no duplica), pero no son intercambiables: la capa 1 protege contra el replay del mismo sobre; la capa 2, contra reintentos legítimos re-firmados.

---

## 6. Estado final

✅ **A11 `cargar.gasto_interno` — wrapper directo CERRADO en TEST.**
DDL infra + función 8/8, smoke directo **38/38** (seguridad 26/0 escrituras con `secWrites=0` empírico, funcional 5 altas con replay/retry/doble-click/conflictos exactos), teardown PASS (0 residuos, fixture 9F intacto). La función escribe el actor y el `source_event` server-side, separa anti-replay de idempotencia de negocio, mapea todo a la allowlist (cero `estado_incierto`/`error_interno`), y la infra queda fuera del canónico y cerrada al Data API. Template y smoke sanitizados y aptos para el repo.

---

## 7. Pendiente explícito

**Extensión del gateway `portal-api` para A11** (fase discreta, **siguiente conversación**):
- Agregar al CATALOG la entrada `'cargar.gasto_interno': { handler:'n8n', roles:['vicky','socio'], webhook:'portal-a11-cargar-gasto-interno__TEST', validate: <validador A11>, injectActor:true, isWrite:true }`.
- **Declarar el validador ANTES del `CATALOG`** (zona muerta temporal / TDZ, L-C-11).
- Smokes de gateway por **JWT** con el assert de regresión obligatorio para una escritura: **`nonce_replay`/`payload_mismatch`/`actor_mismatch` → `conflicto`, NUNCA `estado_incierto`** end-to-end (que `dispatchN8n`/`noConfiable` no enmascare un write con `estado_incierto`).
- **NO tocar** en esa fase: `dispatchN8n`, `buildSignedEnvelope`, `actorCoherente`, la allowlist, CORS, ni **ninguna entrada previa del CATALOG**. En el gateway, `actor`/`rol` salen del **JWT/`portal_usuarios`** (no del payload) — eso recién se prueba ahí.

Hasta que el gateway esté validado, A11 queda accesible **solo por el wrapper directo**.

---

## 8. Aclaraciones (límites de este cierre)

- **No cerrar Slice 3b todavía.** Slice 3b se cierra (`C_SLICE3B_CIERRE.md` + propagación a satélites + CATALOG 11→13) **después** de la extensión del gateway de A11 **y** de **A13** (`gastos.listado`, lectura, patrón Slice 3a). Este documento es un **mini cierre del wrapper directo**, no el cierre del slice.
- **`portal_idempotencia` + `portal_cargar_gasto_interno` son infra Carril C TEST-only**, fuera del canónico y sin OPS. No se promovieron a OPS.
- **No tocar `portal-api` todavía.** La extensión del gateway es la próxima fase; este cierre no la incluye.
- **No tocar `6B_SCHEMA_SQL.md`.** El canónico no se modifica por A11 (se bumpea una sola vez por carril, en la promoción coordinada a OPS).
- **No tocar OPS.** Toda la validación fue en TEST.
- **Satélites no propagados.** `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `CLAUDE.md`, `README.md` y `Pendiente_pre_produccion.md` se actualizan recién en el cierre formal del slice. **D-C-55, D-C-56 y L-C-20 quedan propuestas en este documento** hasta esa propagación.

---

*Cierre inmutable una vez aprobado. Generado el 2026-06-22.*
