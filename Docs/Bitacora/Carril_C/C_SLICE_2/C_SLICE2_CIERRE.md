# CARRIL C — SLICE 2 (ESCRITURAS REUSE) — CIERRE

**Estado:** ✅ **Cerrado y verificado en TEST.** Slice 2 puso las **tres primeras escrituras operativas** del Portal Operativo Interno sobre la espina de Slice 0 y las lecturas de Slice 1: A07 (`reserva.crear_manual`), A08 (`bloqueo.crear_manual`) y A10 (`cobranza.registrar_saldo`). Las tres las sirve `portal-api` vía **wrappers n8n firmados** que revalidan en cinco dimensiones (HMAC · ts · rol · action · ambiente), **inyectan el actor server-side** desde el JWT (nunca del payload) y reusan funciones del motor existentes (`crear_prereserva`/`registrar_pago`/`confirmar_reserva`, `crear_bloqueo`, `registrar_pago`/`abortar_si_falla`), **sin** invocar los webhooks viejos (8B/8D/W09).

**Entorno de validación:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5, marcador `configuracion_general.ambiente='test'`.
**Entorno de operación:** — (Slice 2 **no** se promovió a OPS; el Carril C no toca OPS para experimentar).
**Fecha de cierre:** 2026-06-20.
**Base:** `C_SLICE0_CIERRE.md` (espina de seguridad; D-C-29…35) + `C_SLICE1_CIERRE.md` (molde de wrapper + lecturas reuse; D-C-36…49, L-C-10…15) + `C_SLICE2_A10_DIRECTO_CIERRE.md` (mini-cierre del wrapper directo A10; D-C-50/51, L-C-16/17) + `ARQUITECTURA_ETAPA_9B_COBRANZA_POSTERIOR.md` (flujo `registrar_pago`/`abortar_si_falla`, D-9B-19).
**Depende de:** D-C-29…35 (HMAC/JWT/allowlist/ambiente), D-C-39/41 (allowlist doble + action binding), D-C-40 / D-9B-05 (`saldo_real` recomputado desde pagos confirmados), D-C-43/47 (contrato JSON), D-C-49 / L-C-14 (lógica de saldo byte-alineada a A12), L-C-05 (HMAC sobre raw body binario), L-C-10/11 (placeholder de secreto por prefijo; TDZ del validador antes del CATALOG), L-C-15 (molde de error de los Postgres node), D-9B-19 (`abortar_si_falla`).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.8.1` — **NO modificado por este cierre.** Las tres acciones **reusan** funciones del motor existentes; **no** introducen DDL ni funciones nuevas en la base. `portal_usuarios` sigue siendo infra **TEST-only**, no promovida a OPS.
**Autores:** Franco (titular, ejecutor de **todos** los writes y deploys en Supabase y n8n) + Claude (arquitecto/copiloto; estrictamente advisory — no tocó infraestructura).
**Decisiones registradas:** D-C-50, D-C-51 🔒 (A10). **Lecciones:** L-C-16, L-C-17 (A10). *(A07/A08 no introdujeron decisiones/lecciones nuevas: reusaron el molde de seguridad de Slice 0/1 y el patrón de wrapper.)*

---

## 1. Resumen ejecutivo

Slice 1 puso a operar las lecturas sobre la frontera de confianza. Slice 2 dio el siguiente salto: **las primeras escrituras** del Portal Operativo Interno, reusando las funciones del motor ya validadas y sin reabrir nada del Carril B ni del canónico.

Cada acción es un **wrapper n8n firmado** del mismo molde de la Fase C, con dos diferencias respecto de las lecturas: (a) **inyección de actor server-side** — el gateway agrega `actor` (la persona) dentro del sobre firmado, derivado de `portal_usuarios.nombre` y coherente con el rol (`actorCoherente`), **nunca** del payload; el wrapper lo usa como `created_by`/`validado_por` aguas abajo (D-C-22); y (b) **`isWrite`** — ante un dispatch no confiable de una escritura, el gateway responde `estado_incierto` (no `error_entorno`), porque la escritura pudo haberse aplicado. El gateway `portal-api` mantiene la **allowlist doble** (CATALOG rol×action + allowlist del wrapper, D-C-39) y el **action binding** (key del CATALOG == `EXPECTED_ACTION`, D-C-41).

Hitos del slice: **primera escritura vía gateway** (A07, con inyección de actor y verificación de que `validado_por`/`created_by` salen del JWT, no del payload); **reject-unknown probado como defensa anti-spoof** (un `actor`/`creado_por` dentro del payload rebota con `payload_invalido` en las tres acciones); **primer write transaccional con lock** (A10: `pg_advisory_xact_lock` por `id_reserva` + dos sentencias con snapshot fresco que impiden el doble cobro, D-C-50); y **el modelo de error de dos capas** que mapea etiquetas internas a la allowlist sin filtrar códigos crudos (D-C-51). La validación fue **empírica y por capa**: cada wrapper con su batería directa (seguridad + funcional + concurrencia) y cada cableado con su batería vía gateway, con el **assert de regresión obligatorio** de A10 (SOBREPAGO → `conflicto`, nunca `estado_incierto`) corrido end-to-end. Metodología estricta respetada: snapshot read-only → blueprint aprobado en chat → diff mínimo → Franco ejecuta/deploya → verificación. **OPS y `6B_SCHEMA_SQL.md` intactos.**

---

## 2. Qué quedó construido en TEST

El gateway `portal-api` quedó con **9 entradas** en el CATALOG: 1 resuelta en la Edge (`sesion.contexto`, A02) + 5 lecturas n8n (Slice 1) + **3 escrituras n8n** (este slice). Las tres escrituras llevan `injectActor:true` + `isWrite:true`.

### 2.1 A07 `reserva.crear_manual` — crear reserva manual
- Roles {vicky, socio}; **jenny excluida** (D-C-39). Wrapper `portal-a07-crear-reserva__TEST`. **Primera escritura del portal.** Reusa la cadena del motor `crear_prereserva → registrar_pago → confirmar_reserva` (capa 8B) detrás del wrapper firmado, sin invocar el formulario viejo. Validador espejo `payloadCrearManual` (fecha YMD real, hora en rango, contacto con dígitos/email, enums, montos con seña ≤ total). El **actor** (persona) se inyecta server-side y queda como `created_by` de la reserva y `validado_por` de la seña.

### 2.2 A08 `bloqueo.crear_manual` — crear bloqueo manual
- Roles {vicky, socio} (D-C-39). Wrapper `portal-a08-crear-bloqueo__TEST`. Reusa `crear_bloqueo` (capa 8D) detrás del wrapper firmado. Validador espejo `payloadCrearBloqueo`; **`id_cabana` OBLIGATORIO** (bloqueo total NO se expone en el portal, decisión 8D). El actor inyectado queda como `creado_por` del bloqueo.

### 2.3 A10 `cobranza.registrar_saldo` — registrar pago de saldo
- Roles {vicky, socio} (D-C-39). Wrapper `portal-a10-registrar-saldo__TEST`. Registra **un** pago `tipo='saldo'`, estado inicial `confirmado`, sobre una reserva `confirmada`/`activa`, reusando el flujo de cobranza posterior (Etapa 9B: `registrar_pago` + `abortar_si_falla`, D-9B-19), **sin** invocar el webhook viejo de W09. Validador espejo `payloadRegistrarSaldo`: `id_reserva` entero positivo, `monto` finito >0 con ≤2 decimales dentro de `NUMERIC(12,2)`, `medio_pago ∈ {efectivo, transferencia_bancaria, transferencia_mp, cripto}` (**sin `mp_link`**), `idempotency_key` 8–64 `[A-Za-z0-9_-]`, `notas?`. **Escritura transaccional con lock** (D-C-50) e **idempotencia con match exacto** + modelo de error de dos capas (D-C-51). `saldo_real` recomputado en SQL desde pagos confirmados, byte-alineado a A12 (D-C-49/L-C-14). Detalle en `C_SLICE2_A10_DIRECTO_CIERRE.md`.

---

## 3. Acciones ejecutadas (bitácora)

| Acción | Wrapper | Reusa | injectActor / isWrite | Estado |
|---|---|---|:---:|---|
| **A07** `reserva.crear_manual` | `portal-a07-crear-reserva__TEST` | `crear_prereserva`/`registrar_pago`/`confirmar_reserva` (8B) | ✓ / ✓ | cerrado (directo + gateway) |
| **A08** `bloqueo.crear_manual` | `portal-a08-crear-bloqueo__TEST` | `crear_bloqueo` (8D) | ✓ / ✓ | cerrado (directo + gateway) |
| **A10** `cobranza.registrar_saldo` | `portal-a10-registrar-saldo__TEST` | `registrar_pago`/`abortar_si_falla` (9B) | ✓ / ✓ | cerrado (directo + gateway, 2026-06-20) |

---

## 4. Decisiones registradas (D-C-50, D-C-51) 🔒

> A10 las introdujo y quedaron **propuestas** en `C_SLICE2_A10_DIRECTO_CIERRE.md`; este cierre las **promueve** a `DECISIONES_NO_REABRIR.md`. A07/A08 no agregaron decisiones nuevas.

- **D-C-50** — **Estructura transaccional de una escritura con lock (A10).** Una escritura del portal que debe prevenir condiciones de carrera se modela como **UN** nodo Postgres con **DOS sentencias** bajo `options.queryBatching:"transaction"`: **St1** = `pg_advisory_xact_lock(hashtext('a10_cobranza_saldo:' || (($1::jsonb)->>'id_reserva')))` (lock por `id_reserva`, namespaced, se libera en COMMIT/ROLLBACK); **St2** = CTE de idempotencia (por `source_event`) → recálculo de saldo **dentro de la txn** → `abortar_si_falla(registrar_pago($1::jsonb))` (D-9B-19). Las dos sentencias van **separadas a propósito**: así el snapshot READ COMMITTED de St2 se toma **después** de adquirir el lock, y cada request concurrente ve los commits previos (sin esto, varios leerían el mismo saldo y sobrepagarían). El lock cubre **A10-vs-A10** únicamente; **W09 debe estar inactivo** durante los smokes. Confirmado empíricamente que n8n bindea `$1` a AMBAS sentencias bajo `queryBatching:transaction` (no hizo falta el fallback `$2`). Validado por C2 (saldo 90000 → 0 exacto, 3 ok + 1 conflicto).
- **D-C-51** — **Modelo de error de dos capas para escrituras (A10).** El SQL devuelve **etiquetas internas** (`reserva_no_existe`, `estado_no_cobrable`, `saldo_ya_cancelado`, `excede_saldo`, `idempotency_mismatch`); el nodo `render` las mapea a la **allowlist externa**: `reserva_no_existe → no_encontrado`; el resto → `conflicto`; excepción P0001 de `abortar_si_falla` → `error_interno` (vía `render_error_pg`); éxito → `{ok:true,data}`. **Cero códigos externos nuevos.** `resultado.ok===true` es **autoritativo** (`abortar_si_falla` garantiza `confirmado` o tira P0001; en idempotencia el pago ya existe); `PG_verif_post` solo **enriquece** `saldo_real_actual` post-COMMIT y **no** baja a `estado_incierto` si degrada (L-C-15). La **idempotencia con match exacto** exige coincidencia de `id_reserva` + `tipo='saldo'` + `medio_pago` + `monto_recibido` + `validado_por`; cualquier divergencia con la misma `idempotency_key` → `idempotency_mismatch → conflicto`. **Verificado end-to-end por el gateway (2026-06-20): SOBREPAGO → `conflicto`, nunca `estado_incierto`** (el wrapper devuelve HTTP 200 + envelope `conflicto`; `dispatchN8n`/`noConfiable` no lo enmascara).

---

## 5. Lecciones registradas (L-C-16, L-C-17)

- **L-C-16** — **`queryReplacement` de n8n llega como TEXTO; castear a `jsonb` explícito.** En un Postgres node con `options.queryReplacement = "={{ JSON.stringify($json.<obj>) }}"`, `$1` se bindea como **texto**, no `jsonb`. Cualquier operador jsonb (`$1->>'campo'`, etc.) tira **`Could not choose a best candidate operator. You might need to add explicit type casts.`** (`unknown ->> text` tiene dos candidatos `json`/`jsonb`). Solución: **`($1::jsonb)->>'campo'`** en **cada** uso (incluido el `hashtext` del advisory lock, primera sentencia → falla primero, dando un `error_interno` uniforme). El error es de **tipo/cast**, no de binding (`there is no parameter $1` sería binding → recién ahí aplica el fallback `$2`).
- **L-C-17** — **Cuarteto de gotchas de PowerShell 5.1 en el harness de smokes.** (a) **`[string]$X = $null` coerce a `""`** → usar **`[object]$X = $null`** para opcionales que deben quedar `$null` (si no, `ContentLength=0` → `raw_body_ausente`). (b) **`Invoke-WebRequest -Body byte[]`** puede mandar cuerpo vacío en PS 5.1 → usar **`HttpWebRequest`** con `ContentLength` explícito + `GetRequestStream().Write` + **TLS 1.2 forzado** (camino directo/HMAC, donde n8n recomputa el HMAC sobre el raw body). *(En el camino gateway no hay HMAC sobre el raw body — el gateway parsea JSON y refirma server-side —, así que `Invoke-RestMethod` alcanza; reconciliado con el harness GW de A07/A08.)* (c) **`(Where-Object …).Count` sobre un solo objeto** no devuelve 1 confiable → envolver en **`@(… | Where-Object …).Count`**. (d) **Contadores dentro de `function`** necesitan **`$script:`** (`$pass++` crea copia local → resumen `0/0`).

---

## 6. Evidencia de pruebas

> **Nota de evidencia (disciplina del cierre):** la batería **re-corrida y registrada en esta sesión** es la de **A10 vía gateway** (abajo, §6.1). El **wrapper directo de A10** está documentado en su cierre inmutable aprobado (`C_SLICE2_A10_DIRECTO_CIERRE.md`, §6.2). **A07 y A08** se incorporan **por referencia** a sus runsheets/cierres previos (§6.3): están **cerrados y wired en el gateway** (verificable en el CATALOG: `reserva.crear_manual`, `bloqueo.crear_manual`), pero **no se re-corrieron en esta sesión**; sus cifras textuales no se transcriben acá para no presentar como verificado lo que no se re-ejecutó. Si se desea incorporarlas como evidencia de primera clase, se completan desde sus documentos.

### 6.1 A10 vía gateway — evidencia de esta sesión (2026-06-20)

```
PRECHECK AUTH .......... 9 PASS / 0 FAIL
  3 JWT (vicky/franco/jenny) + sesion.contexto; cobranza.registrar_saldo
  habilitada para vicky/socio, NO para jenny.

SETUP / GATE RESIDUAL PRE
  Fixtures 9900001..9900007 creados (self-cleaning).
  pagos_a10_smoke=0, log_a10_smoke=0   (cero escrituras de smoke antes de empezar)

SMOKE GATEWAY .......... 9 PASS / 0 FAIL  (8 casos a-g + R + META allowlist)
  a vicky feliz (9900001, 50000 -> 20000) ............ ok
  b socio/franco feliz (9900002, 70000 -> 0) ......... ok
  c jenny -> rol_no_permitido (gateway, antes de firmar)
  d sin JWT -> no_autorizado
  e payload invalido (mp_link) -> payload_invalido (gateway)
  f spoof actor en payload -> payload_invalido (reject-unknown)
  g action inexistente -> accion_desconocida
  R SOBREPAGO (9900006, 80000 > 70000) -> conflicto   (REGRESION: nunca estado_incierto)
  Codigos vistos ..... accion_desconocida, conflicto, no_autorizado,
                       payload_invalido, rol_no_permitido   (todos en la allowlist)

VERIF DE ESCRITURAS (actor inyectado desde el JWT)
  9900001 .... 1 pago saldo confirmado 50000  · validado_por vicky
  9900002 .... 1 pago saldo confirmado 70000  · validado_por franco
  9900006 .... SIN pago de smoke   (la regresion de sobrepago no escribio)

GATE POST
  pagos_ns=0 · log_ns=0 · reservas_ns=0 · huespedes_ns=0   (teardown limpio)
```

**Lo que la evidencia gateway demuestra:** el **actor se inyecta server-side** (`validado_por` = identidad del JWT, no del payload); el **reject-unknown** bloquea el spoof de actor; jenny rebota **en el gateway** antes de firmar; y — central — la **regresión de sobrepago llega como `conflicto` end-to-end**, confirmando que `dispatchN8n`/`noConfiable` no enmascara un write con `estado_incierto` (el wrapper responde HTTP 200 + envelope allowlisted).

### 6.2 A10 wrapper directo — según `C_SLICE2_A10_DIRECTO_CIERRE.md` (cierre inmutable aprobado)

```
SEGURIDAD ...... 33 PASS / 0 FAIL  (32 casos S01-S32 + META)
FUNCIONAL ...... 11 PASS / 0 FAIL  (unico codigo de error: conflicto)
  Escrituras: 9900001 50000 (vicky), 9900002 70000 (franco), 9900003 40000 (remo)
CONCURRENCIA ... 7 PASS / 0 FAIL
  C1 retry-race  9900006: 8 req misma key -> 1 escritura, 7 idempotentes, 1 id_pago
  C2 sobrepago-race 9900007: saldo 90000, 4 req de 30000 keys distintas -> 3 ok + 1 conflicto, saldo 0
TEARDOWN / GATE POST ... 0 residuos en pagos/log/reservas/huespedes
```

### 6.3 A07 / A08 — incorporados por referencia

- **A07** `reserva.crear_manual`: cerrado en sesión previa (wrapper directo + gateway). Evidencia en `C_SLICE2_A07_RUNSHEET.md` / `C_SLICE2_A07_GW_RUNSHEET.md`. Wired en el CATALOG.
- **A08** `bloqueo.crear_manual`: cerrado en sesión previa (wrapper directo + gateway). Evidencia en `C_SLICE2_A08_RUNSHEET.md` / `C_SLICE2_A08_GW_RUNSHEET.md`. Wired en el CATALOG.
- Por disciplina de evidencia, no se transcriben cifras de A07/A08 en este cierre porque no se re-ejecutaron en esta sesión; quedan incorporadas por referencia a sus runsheets/cierres previos.

En las tres: jenny → `rol_no_permitido` **en el gateway** sin tocar n8n; sin JWT → `no_autorizado`; `actor`/`creado_por` en el payload → `payload_invalido` (reject-unknown); actor inyectado server-side desde el JWT.

---

## 7. Supuestos y límites del slice

- Slice 2 = **escrituras reuse** (A07/A08/A10). Lecturas nuevas (Slice 3a: A24 histórico / A25 ingresos) y gastos (Slice 3b: A11/A13) quedan **fuera**.
- **No promovido a OPS.** Toda la validación fue en TEST; ninguna de las tres acciones se promovió a OPS.
- **`vita_w09_cobranza_posterior` sigue INACTIVO** hasta decisión explícita posterior (necesario para que el advisory lock de A10 sea la única vía de escritura de saldo durante los smokes; reactivarlo es decisión posterior).
- **Wrapper A10 directo queda ACTIVO** en TEST (a diferencia del molde standalone de A07/A08): el gateway despacha a su webhook productivo, que exige `active:true`. Desactivarlo dejaría al gateway sin a quién despachar.
- **Idempotencia y nonce:** las tres escrituras son idempotentes/guardadas (A07 por prereserva/seña; A08 por solapamiento; A10 por `idempotency_key` + advisory lock). El **store anti-replay de `nonce`** (P-C-9) sigue correctamente diferido a la primera escritura **no-idempotente sin guard** (realísticamente A11).
- **Evidencia A07/A08 por referencia** (ver §6): este cierre cubre el slice completo, pero la evidencia re-ejecutada en esta sesión es la de A10.

---

## 8. Pendientes y handoff

- **→ Slice 3a** (lecturas nuevas: A24 histórico / A25 ingresos) y **Slice 3b** (gastos: A11/A13). A11 es la primera escritura candidata a **no-idempotente sin guard** → ahí entra el store de `nonce` (P-C-9).
- **Hardening pre-OPS** (sigue abierto, P-C-7…11): restringir **CORS** al origin del portal; generar `VITA_HMAC_SECRET` de **OPS** distinto del de TEST; **store de nonce** persistente; **rol Postgres dedicado** de mínimos en lugar de `service_role`; migrar `portal-api` a CLI + `config.toml` si los redeploys se vuelven frecuentes (L-C-06).
- **Reorganización Tier B del repo** (separar artefactos ejecutables de prosa en `Docs/Bitacora/`): **diferida** hasta después de cerrar el frente de integración Mercado Pago.
- **Integración Mercado Pago** (MP-01 conceptual aprobado, MP-02 readiness en curso): frente paralelo; A10 no expone `mp_link` (es carga manual de saldo ya cobrado), así que no se cruza con este cierre.

---

## 9. Deltas para documentos satélite (aplicar tras auditar este cierre)

Bloques listos para pegar en `C_SLICE2_DELTAS_SATELITES.md`. **EOL por archivo** (verificado contra los archivos reales):

- **`DECISIONES_NO_REABRIR.md`** (LF) — agregar **subsección "## Carril C — Slice 2 (escrituras reuse) — cerrada 2026-06-20"** con **D-C-50 / D-C-51**, **después** de la entrada D-C-49 y **antes** de "## Lecciones operativas n8n consolidadas (L-6C-XX)".
- **`Lecciones_Aprendidas.md`** (bloque L-C en **CRLF**) — agregar **L-C-16 / L-C-17** después de L-C-15, con EOL **CRLF**.
- **`ESTADO_ACTUAL_VITA_DELTA.md`** (CRLF) — nuevo bloque **"Etapa actual: Slice 2 (escrituras reuse) — cerrada 2026-06-20"**; el bloque de **Slice 1** baja de "Etapa actual" a "Etapa previa".
- **`CLAUDE.md`** (LF) — entrada de cierre de **Slice 2** después de la de Slice 1, mismo formato.
- **`Pendiente_pre_produccion.md`** — **sin cambios** (P-C-1…11 siguen abiertos; Slice 2 no resuelve ni agrega ninguno; las tres escrituras son idempotentes/guardadas → P-C-9 sigue diferido a A11). *Recomendado dejar intacto, igual que en el cierre de Slice 1.*
- **`6B_SCHEMA_SQL.md`** y **OPS** — **sin cambios** (Carril C no toca el canónico; las tres acciones reusan funciones del motor existentes).
- **Commit:** `C_SLICE2_A10_portal-api_index.ts` (gateway final del slice, A05+A07+A08+A10 + lecturas Slice 1) + los smokes/SQL/runsheet de A10 gateway, sanitizados.

---

## 10. Inventario de artefactos de la etapa

- **A07:** wrapper `portal-a07-crear-reserva__TEST` + smokes directos/gateway + runsheets `C_SLICE2_A07_RUNSHEET.md` / `C_SLICE2_A07_GW_RUNSHEET.md`.
- **A08:** wrapper `portal-a08-crear-bloqueo__TEST` + smokes directos/gateway + runsheets `C_SLICE2_A08_RUNSHEET.md` / `C_SLICE2_A08_GW_RUNSHEET.md`.
- **A10 directo:** wrapper `vita_w10_registrar_saldo__TEMPLATE.json` + `a10_validator_core.mjs` + smokes (`A10_smoke_common/seguridad/funcional/concurrencia.ps1`) + SQL (`A10_setup/teardown/verif_writes/gate_*/privilege_check/pg_*.sql`) + `C_SLICE2_A10_RUNSHEET.md` + cierre `C_SLICE2_A10_DIRECTO_CIERRE.md`.
- **A10 gateway (esta sesión):** `C_SLICE2_A10_portal-api_index.ts` (gateway final del slice) + `C_SLICE2_A10_GW_common.ps1` + `C_SLICE2_A10_GW_precheck_auth.ps1` + `C_SLICE2_A10_GW_smoke.ps1` + `C_SLICE2_A10_GW_verif.sql` + `C_SLICE2_A10_GW_RUNSHEET.md`.
- **Cierre:** este documento (`C_SLICE2_CIERRE.md`) + las deltas satélite (`C_SLICE2_DELTAS_SATELITES.md`).
