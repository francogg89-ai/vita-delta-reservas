# CARRIL C — SLICE 2 — A10 `cobranza.registrar_saldo` (WRAPPER DIRECTO) — CIERRE

**Estado:** ✅ **Wrapper directo APROBADO en TEST.** A10 registra **un pago de tipo `saldo` contra el saldo pendiente** de una reserva confirmada/activa a través del Portal Operativo Interno, reusando el flujo de cobranza posterior (Etapa 9B: `registrar_pago` + `abortar_si_falla`) detrás de un wrapper n8n firmado, **sin** invocar el webhook viejo de W09. Validado end-to-end por el **camino wrapper-directo** (seguridad + funcional + concurrencia + teardown). La extensión del **gateway** queda explícitamente pendiente (ver §7).

**Entorno de validación:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5, marcador `configuracion_general.ambiente='test'`.
**Entorno de operación:** — (A10 **no** se promovió a OPS; el Carril C no toca OPS para experimentar).
**Fecha de cierre:** 2026-06-20.
**Base:** `C_SLICE1_CIERRE.md` (espina de seguridad + molde de wrapper; D-C-29…49, L-C-10…15) + `ARQUITECTURA_ETAPA_9B_COBRANZA_POSTERIOR.md` (flujo `registrar_pago`/`abortar_si_falla`, D-9B-19).
**Depende de:** D-C-29…35 (HMAC/JWT/allowlist/ambiente), D-C-39/41 (allowlist doble + action binding), D-C-40 / D-9B-05 (`saldo_real` recomputado desde pagos confirmados), D-C-43/47 (contrato JSON), D-C-49 / L-C-14 (lógica de saldo byte-alineada a A12), L-C-05 (HMAC sobre bytes del raw body binario), L-C-10 (placeholder de secreto por prefijo), L-C-15 (molde de error de los Postgres node), D-9B-19 (`abortar_si_falla`).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.8.1` — **NO modificado por este cierre.** A10 **reusa** `registrar_pago` y `abortar_si_falla` existentes; **no** introduce DDL ni funciones nuevas en la base.
**Autores:** Franco (titular, ejecutor de **todos** los writes en Supabase y n8n) + Claude (arquitecto/copiloto; estrictamente advisory — no tocó infraestructura).
**Decisiones registradas:** D-C-50, D-C-51 🔒. **Lecciones:** L-C-16, L-C-17.

---

## 1. Alcance

A10 = **primera escritura del Carril C** (Slice 2 es el primer slice con writes del Portal Operativo Interno). Registra **un** pago de tipo `saldo`, estado inicial `confirmado`, sobre una reserva en estado `confirmada` o `activa`, reusando el flujo de cobranza posterior de la Etapa 9B.

**Contrato de la acción** (`action = 'cobranza.registrar_saldo'`):
- **Roles:** `vicky`, `socio` (sin `jenny`, D-C-03).
- **Payload:** `{ id_reserva (entero positivo), monto (number finito, >0, ≤ 9.999.999.999,99, ≤2 decimales), medio_pago (enum), idempotency_key (8–64, `[A-Za-z0-9_-]`), notas? }`. **Reject-unknown** en sobre y payload.
- **`medio_pago` (ENUM_MEDIO_A10):** `efectivo`, `transferencia_bancaria`, `transferencia_mp`, `cripto`. **No** expone `mp_link` (D — A10 es carga manual de saldo ya cobrado, no link de pago).
- **Actor server-side:** `validado_por` se setea desde el actor del JWT validado, **nunca** desde el payload (molde de seguridad A07).
- **`source_event` determinístico y sin PII:** `portal_test_a10_res<id_reserva>_<sha256(id_reserva|idempotency_key)[:12]>` — sin timestamp, sin datos del huésped.
- **`saldo` recomputado en SQL** desde pagos confirmados (`sena`+`saldo`), `monto_total − SUM(...)` (D-C-40 / D-9B-05), **nunca** desde `reservas.monto_saldo`. Lógica byte-alineada a A12 (D-C-49 / L-C-14): CTEs `reserva_por_prereserva` (MIN) + `pagos_reserva_normalizados` + FILTER-en-SUM.
- **Sin recargo del 5%** (eso es del link MP, no de la carga manual de saldo).

**Fuera de alcance de este cierre:** la extensión del gateway `portal-api` (§7), el cierre formal de Slice 2, y cualquier toque a OPS o a W09 (§8).

---

## 2. Artefactos finales

**En el repo** (`francogg89-ai/vita-delta-reservas`):
- `vita_w10_registrar_saldo__TEMPLATE.json` — workflow del wrapper (12 nodos), **sanitizado** (L-C-08/L-C-10): secreto → placeholder `__PEGAR_SECRETO_O_USAR_VARIABLE__`, IDs de credencial → `REEMPLAZAR_POR_CRED_TEST`, sin `webhookId`, `active:false`, `pinData:{}`.
  Cadena de nodos: `Webhook(2.1, rawBody) → validar_firma_ts_rol → leer_ambiente → verificar_acceso → IF_acceso → derivar → PG_cobranza → PG_verif_post → render → Respond` (+ ramas `render_error` y `render_error_pg`).

**SQL (ejecutables, dry-parse VERDE con `pglast`):**
- `A10_pg_cobranza.sql` — St1 (advisory xact lock) + St2 (idempotencia → recálculo de saldo in-txn → `abortar_si_falla(registrar_pago(...))`). **Byte-idéntico al query del nodo.**
- `A10_pg_verif_post.sql` — lectura post-COMMIT (saldo real actual, read-only).
- `A10_privilege_check.sql` — `has_function_privilege` de `registrar_pago`/`abortar_si_falla` (devolvió true/true).
- `A10_setup.sql` — fixtures 9900001–9900007 (self-cleaning, idempotente; fechas sintéticas 2099; anti-OPS guard).
- `A10_teardown.sql` — limpieza FK-safe de `portal_test_a10_%` (log_cambios → pagos → reservas → huespedes).
- `A10_gate_residual.sql` / `A10_gate_post.sql` — conteos de residuos (excluyen setup).
- `A10_verif_writes.sql` — verificación de las escrituras esperadas.

**Smokes PowerShell (ASCII-puro):**
- `A10_smoke_common.ps1` — helper `Invoke-A10` (envío `HttpWebRequest` + HMAC + asserts + allowlist meta).
- `A10_smoke_seguridad.ps1` — 32 casos S01–S32 + META allowlist.
- `A10_smoke_funcional.ps1` — A, B, C, D, Da, F, E, G, H, I.
- `A10_smoke_concurrencia.ps1` — C1 (retry-race) + C2 (sobrepago-race) con RunspacePool.
- `A10_diag_rawbody.ps1` — diagnóstico de un disparo (firma inválida, no escribe).

**Orquestación / dev tooling:**
- `C_SLICE2_A10_RUNSHEET.md` — orden de ejecución y puntos de verificación al importar.
- `a10_validator_core.mjs` + `test_a10_validator.mjs` — espejo de la lógica de validación + test (**51 PASS / 0 FAIL**).
- `gen_workflow.py` / `dryparse.py` / `ascii_clean.py` — generación y verificación.

---

## 3. Evidencia por bloque (TEST)

```
SEGURIDAD (sin escritura)
  A10_smoke_seguridad.ps1 ........ 33 PASS / 0 FAIL  (32 casos S01–S32 + META allowlist)
  Codigos vistos ................. ambiente_incorrecto, firma_invalida, payload_invalido,
                                   rol_no_permitido, ts_fuera_de_ventana
  Gate residual seguridad ........ pagos_a10_smoke=0, log_a10_smoke=0   (cero escrituras)

FUNCIONAL (escribe sobre fixtures)
  A10_smoke_funcional.ps1 ........ 11 PASS / 0 FAIL  (+ META allowlist)
  Unico codigo de error visto .... conflicto   (ni error_interno ni estado_incierto)
  Verif de escrituras:
    9900001 (A FELIZ) ............ 1 pago saldo confirmado 50000  · validado_por vicky
    9900002 (E COMPLETA) ......... 1 pago saldo confirmado 70000  · validado_por franco
    9900003 (I ACTIVA) ........... 1 pago saldo confirmado 40000  · validado_por remo
    C / D / Da / F / G / H ....... sin pago (rebote por conflicto, sin escribir)
    source_event ................. deterministico y sin PII (portal_test_a10_res<id>_<hash12>)

CONCURRENCIA (advisory lock; W09 inactivo)
  A10_smoke_concurrencia.ps1 ..... 7 PASS / 0 FAIL
    C1 retry-race  (9900006) ..... 8 requests con MISMA key -> 1 escritura nueva,
                                   7 idempotentes, UN unico id_pago    (saldo 70000->20000)
    C2 sobrepago-race (9900007) .. saldo 90000; 4 requests de 30000 con keys DISTINTAS
                                   -> 3 ok + 1 conflicto, suma ok <= saldo   (saldo final 0)

TEARDOWN / GATE POST
  pagos_ns=0 · log_ns=0 · reservas_ns=0 · huespedes_ns=0   (cero residuos en las 4 tablas)
```

**Lo que la evidencia demuestra:** HMAC sobre bytes exactos + anti-replay (`ts` ±300 s) + allowlist de rol + action binding + rechazo de payload (seguridad); idempotencia con control de mismatch (monto/medio/actor → `conflicto`) y actor server-side (funcional); y — lo central — el **advisory lock por `id_reserva` + snapshot fresco por sentencia impide el doble cobro** (C2: el saldo cierra en **exactamente 0**, nunca negativo). Mapeo de errores siempre a la allowlist; **cero `estado_incierto` y cero `error_interno`** en los caminos validados.

---

## 4. Fixes aplicados durante A10

1. **Raw body** — la lectura del cuerpo crudo se alineó al patrón A12: `Webhook typeVersion 2.1` + `getBinaryDataBuffer(0,'data')` con fallback a `wh.rawBody` (incluida la forma serializada `{type:'Buffer',data:[...]}`), L-C-05. *(El síntoma `raw_body_ausente` terminó siendo, en el fondo, el body vacío del cliente — ver fix 2 y L-C-17.)*
2. **PowerShell — envío de bytes reales** — `Invoke-A10` y el worker de concurrencia se reescribieron con `HttpWebRequest` + `ContentLength` explícito + escritura exacta de `$bodyBytes` al request stream + TLS 1.2 forzado; y los parámetros opcionales pasaron de `[string]…=$null` a `[object]…=$null` (en PS 5.1 `[string]$x=$null` se vuelve `""` y mandaba `ContentLength=0`). L-C-17.
3. **Smoke de seguridad — S04/S05** — los casos de `ts` fuera de ventana pasaron de margen `±300001 ms` (pegado al borde, sensible a latencia/clock skew) a `±900000 ms`, con `id_reserva=0` como red de seguridad (si el `ts` no rebotara, cae en `payload_invalido` antes de PG; nunca escribe). El código esperado sigue siendo `ts_fuera_de_ventana` porque la verificación de `ts` va antes que la de `id_reserva` en el validador.
4. **SQL — cast jsonb** — `PG_cobranza` (9) y `PG_verif_post` (3) pasaron todo `$1->>'campo'` a `($1::jsonb)->>'campo'`. n8n manda `queryReplacement` como **texto**, y `unknown ->> text` tiene dos candidatos (`json`/`jsonb`) → `Could not choose a best candidate operator`. El cast desambigua. L-C-16.
5. **Smoke de concurrencia — contadores** — la función `Chk` usaba `$pass++`/`$fail++` (scope local de la función) → el resumen daba `0/0` pese a los PASS individuales. Se corrigió a `$script:pass`/`$script:fail`. *(Además, conteos de `Where-Object` envueltos en `@(...).Count` y el worker devuelve `monto` para el `Measure-Object` — ver L-C-17.)*

---

## 5. Decisiones y lecciones nuevas

**🔒 D-C-50 — Estructura transaccional de una escritura con lock (A10).**
Una escritura del portal que debe prevenir condiciones de carrera se modela como **UN** nodo Postgres con **DOS sentencias** bajo `options.queryBatching: "transaction"`:
- **St1** — lock por `id_reserva` (namespaced; se libera en COMMIT/ROLLBACK):
  ```sql
  SELECT pg_advisory_xact_lock(
    hashtext('a10_cobranza_saldo:' || (($1::jsonb)->>'id_reserva'))
  );
  ```
- **St2:** CTE de idempotencia (por `source_event`) → recálculo de saldo **dentro de la txn** → `abortar_si_falla(registrar_pago($1::jsonb))` (D-9B-19).

Las dos sentencias van **separadas a propósito**: así el snapshot READ COMMITTED de St2 se toma **después** de adquirir el lock, y cada request concurrente ve los commits previos (sin esto, varios leerían el mismo saldo y sobrepagarían). El lock cubre **A10-vs-A10** únicamente; **W09 debe estar inactivo** durante los smokes. Confirmado empíricamente que **n8n bindea `$1` a AMBAS sentencias** bajo `queryBatching:transaction` (no hizo falta el fallback `$2`). *(Validado por C2: saldo 90000 → 0 exacto, 3 ok + 1 conflicto.)*

**🔒 D-C-51 — Modelo de error de dos capas para escrituras (A10).**
El SQL devuelve **etiquetas internas** (`reserva_no_existe`, `estado_no_cobrable`, `saldo_ya_cancelado`, `excede_saldo`, `idempotency_mismatch`); el nodo `render` las mapea a la **allowlist externa**: `reserva_no_existe → no_encontrado`; el resto → `conflicto`; excepción de Postgres (P0001 de `abortar_si_falla`) → `error_interno` (vía `render_error_pg`); éxito → `{ ok:true, data }`. **Cero códigos externos nuevos.** `resultado.ok===true` es **autoritativo** (en alta nueva `abortar_si_falla` garantiza `confirmado` o habría tirado P0001; en idempotencia el pago ya existe); `PG_verif_post` solo **enriquece** `saldo_real_actual` post-COMMIT y **no** baja a `estado_incierto` si degrada (L-C-15). La **idempotencia con match exacto** exige coincidencia de `id_reserva` + `tipo='saldo'` + `medio_pago` + `monto_recibido` + `validado_por`; cualquier divergencia con la misma `idempotency_key` → `idempotency_mismatch → conflicto`.

**📝 L-C-16 — `queryReplacement` de n8n llega como TEXTO; castear a `jsonb` explícito.**
En un Postgres node de n8n con `options.queryReplacement = "={{ JSON.stringify($json.<obj>) }}"`, el parámetro `$1` se bindea como **texto**, no como `jsonb`. Cualquier operador jsonb (`$1->>'campo'`, `$1->'campo'`, etc.) tira **`Could not choose a best candidate operator. You might need to add explicit type casts.`** — porque `unknown ->> text` tiene dos candidatos (`json ->>` y `jsonb ->>`) y el planner no puede elegir. Solución: **`($1::jsonb)->>'campo'`** en **cada** uso (incluido el `hashtext` del advisory lock, que es la primera sentencia y por eso falla primero, dando un `error_interno` **uniforme** en todos los casos). El error es de **tipo/cast**, no de binding (`there is no parameter $1` / `bind message supplies…` sería binding — ahí recién se evalúa el fallback `$2`).

**📝 L-C-17 — Cuarteto de gotchas de PowerShell 5.1 en el harness de smokes.**
(a) **`[string]$X = $null` coerce a `""`** — usar **`[object]$X = $null`** para parámetros opcionales que deben quedar `$null`; si no, el chequeo `$null -eq $X` falla y se arma mal el body (en A10 mandaba `ContentLength=0` → `raw_body_ausente`). (b) **`Invoke-WebRequest -Body byte[]`** puede mandar **cuerpo vacío** en PS 5.1 — usar **`HttpWebRequest`** con `ContentLength` explícito + `GetRequestStream().Write($bytes,…)` + **TLS 1.2 forzado** (`[Net.ServicePointManager]::SecurityProtocol`). (c) **`(Where-Object …).Count` sobre un solo objeto** no devuelve 1 confiable — envolver en **`@(… | Where-Object …).Count`**. (d) **Contadores dentro de `function`** necesitan **`$script:`** (`$pass++` crea una copia local y el resumen queda en `0/0`). *(Confirmar el body con `content-length` en el diag del nodo es la forma más rápida de distinguir "PS manda vacío" de "n8n no materializa el raw".)*

> Nota: la sanitización del template (secreto/credenciales/`pinData`) ya está cubierta por **L-C-08** (sanitizar **antes** de commitear, con assert duro que aborta si el secreto sigue en el JSON). No se registra lección nueva por eso.

---

## 6. Estado final

✅ **A10 `cobranza.registrar_saldo` — wrapper directo APROBADO en TEST.**
Seguridad 33/0, funcional 11/0 con escrituras exactas, concurrencia 7/0 con **no-sobrepago demostrado**, teardown + gate post con **0 residuos**. El wrapper reusa `registrar_pago`/`abortar_si_falla` sin tocar el canónico, escribe el actor server-side, emite `source_event` determinístico sin PII, y mapea todos los errores a la allowlist. Template sanitizado y apto para el repo.

---

## 7. Pendiente explícito

**Extensión del gateway `portal-api` para A10** (fase discreta, siguiente conversación):
- Agregar al CATALOG: `'cobranza.registrar_saldo': { handler:'n8n', roles:['vicky','socio'], webhook:'portal-a10-registrar-saldo__TEST', validate: payloadRegistrarSaldo, injectActor:true, isWrite:true }`. Declarar el validador **antes** del `CATALOG` (TDZ, L-C-11).
- Smokes de gateway con el **assert de regresión obligatorio**: **SOBREPAGO → `conflicto`, NUNCA `estado_incierto`** — A10 solo emite códigos de la allowlist, pero hay que **probarlo end-to-end** por el gateway (que `dispatchN8n`/`noConfiable` no enmascare un write con `estado_incierto`).

Hasta que el gateway esté validado, A10 queda accesible **solo por el wrapper directo**.

---

## 8. Aclaraciones (límites de este cierre)

- **No cerrar Slice 2 todavía.** Slice 2 se cierra (`C_SLICE2_CIERRE.md` + propagación a satélites) **después** de la extensión del gateway de A10. Este documento es un **mini cierre del wrapper directo**, no el cierre del slice.
- **No tocar OPS.** Toda la validación fue en TEST; A10 no se promovió a OPS.
- **`vita_w09_cobranza_posterior` sigue INACTIVO** hasta nuevo aviso (necesario para que el advisory lock de A10 sea la única vía de escritura durante los smokes; reactivarlo es decisión posterior).
- **Satélites no propagados.** `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md` y `Pendiente_pre_produccion.md` se actualizan recién en el cierre formal del slice. D-C-50/51 y L-C-16/17 quedan **propuestas en este documento** hasta esa propagación.

---

*Cierre inmutable una vez aprobado. Generado el 2026-06-20.*
