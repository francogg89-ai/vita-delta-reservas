# C_SLICE2 — DELTAS PARA DOCUMENTOS SATÉLITE (para revisión antes de fijar/commitear)

> Bloques **listos para pegar** que propagan el cierre de Slice 2 a los satélites.
> EOL **verificado contra los archivos reales** (no contra notas previas):
> `DECISIONES_NO_REABRIR.md` = **LF** · `Lecciones_Aprendidas.md` = **MIXTO (bloque L-C en CRLF)** ·
> `ESTADO_ACTUAL_VITA_DELTA.md` = **CRLF** · `CLAUDE.md` = **LF** · `Pendiente_pre_produccion.md` = **LF (sin cambios)**.
>
> Todos los writes los ejecutás vos. Nada acá toca OPS, el canónico ni W09.

---

## 1. `DECISIONES_NO_REABRIR.md` (LF)

**Anchor / ubicación:** insertar la subsección nueva **inmediatamente después** de la entrada `- **D-C-49** — A12 reusa la lógica de vita_w09_listado_saldos: ...` (fin de la subsección "Carril C — Slice 1") y **antes** de la línea `## Lecciones operativas n8n consolidadas (L-6C-XX)`.

**Bloque a insertar (LF):**

```markdown
## Carril C — Slice 2 (escrituras reuse) — cerrada 2026-06-20

Decisiones de la **construcción de Slice 2**: las tres primeras escrituras operativas del Portal Operativo Interno (A07 `reserva.crear_manual`, A08 `bloqueo.crear_manual`, A10 `cobranza.registrar_saldo`), sobre **TEST**, vía wrappers n8n firmados que revalidan HMAC+ts+rol+action+ambiente, **inyectan el actor server-side** desde el JWT (nunca del payload) y reusan funciones del motor existentes (`crear_prereserva`/`registrar_pago`/`confirmar_reserva` de 8B, `crear_bloqueo` de 8D, `registrar_pago`/`abortar_si_falla` de 9B), **sin** invocar los webhooks viejos (8B/8D/W09). No reabre el Carril B ni el canónico; **OPS intacto**. **No promovido a OPS.** `vita_w09_cobranza_posterior` queda **INACTIVO** hasta decisión posterior; el wrapper A10 directo queda **ACTIVO** (el gateway lo necesita para despachar). A07/A08 no introdujeron decisiones nuevas (reusaron el molde de seguridad de Slice 0/1 y el patrón de wrapper). Cierres: `C_SLICE2_CIERRE.md` + `C_SLICE2_A10_DIRECTO_CIERRE.md`.

- **D-C-50** — **Estructura transaccional de una escritura con lock (A10).** Una escritura del portal que debe prevenir condiciones de carrera se modela como **UN** nodo Postgres con **DOS sentencias** bajo `options.queryBatching:"transaction"`: **St1** = `pg_advisory_xact_lock(hashtext('a10_cobranza_saldo:' || (($1::jsonb)->>'id_reserva')))` (lock por `id_reserva`, namespaced, se libera en COMMIT/ROLLBACK); **St2** = CTE de idempotencia (por `source_event`) → recálculo de saldo **dentro de la txn** → `abortar_si_falla(registrar_pago($1::jsonb))` (D-9B-19). Las dos sentencias van **separadas a propósito**: así el snapshot READ COMMITTED de St2 se toma **después** de adquirir el lock, y cada request concurrente ve los commits previos (sin esto, varios leerían el mismo saldo y sobrepagarían). El lock cubre **A10-vs-A10** únicamente; **W09 debe estar inactivo** durante los smokes. Confirmado empíricamente que n8n bindea `$1` a AMBAS sentencias bajo `queryBatching:transaction` (no hizo falta el fallback `$2`). Validado por C2 (saldo 90000 → 0 exacto, 3 ok + 1 conflicto).
- **D-C-51** — **Modelo de error de dos capas para escrituras (A10).** El SQL devuelve **etiquetas internas** (`reserva_no_existe`, `estado_no_cobrable`, `saldo_ya_cancelado`, `excede_saldo`, `idempotency_mismatch`); el nodo `render` las mapea a la **allowlist externa**: `reserva_no_existe → no_encontrado`; el resto → `conflicto`; excepción P0001 de `abortar_si_falla` → `error_interno` (vía `render_error_pg`); éxito → `{ok:true,data}`. **Cero códigos externos nuevos.** `resultado.ok===true` es **autoritativo** (`abortar_si_falla` garantiza `confirmado` o tira P0001; en idempotencia el pago ya existe); `PG_verif_post` solo **enriquece** `saldo_real_actual` post-COMMIT y **no** baja a `estado_incierto` si degrada (L-C-15). La **idempotencia con match exacto** exige coincidencia de `id_reserva` + `tipo='saldo'` + `medio_pago` + `monto_recibido` + `validado_por`; cualquier divergencia con la misma `idempotency_key` → `idempotency_mismatch → conflicto`. **Verificado end-to-end por el gateway (2026-06-20): SOBREPAGO → `conflicto`, nunca `estado_incierto`** (el wrapper devuelve HTTP 200 + envelope `conflicto`; `dispatchN8n`/`noConfiable` no lo enmascara).
```

---

## 2. `Lecciones_Aprendidas.md` (bloque L-C en **CRLF**)

**Anchor / ubicación:** insertar **después** de la entrada `- **L-C-15** — Los nodos Postgres de los wrappers ...` (fin de "Lecciones del Carril C — Backend/API"). **EOL CRLF** (igual que el resto del bloque L-C).

**Bloque a insertar (CRLF):**

```markdown
- **L-C-16** — **`queryReplacement` de n8n llega como TEXTO; castear a `jsonb` explícito.** En un Postgres node con `options.queryReplacement = "={{ JSON.stringify($json.<obj>) }}"`, `$1` se bindea como **texto**, no `jsonb`. Cualquier operador jsonb (`$1->>'campo'`, etc.) tira **`Could not choose a best candidate operator. You might need to add explicit type casts.`** (`unknown ->> text` tiene dos candidatos `json`/`jsonb`). Solución: **`($1::jsonb)->>'campo'`** en **cada** uso (incluido el `hashtext` del advisory lock, primera sentencia → falla primero, dando un `error_interno` uniforme). El error es de **tipo/cast**, no de binding (`there is no parameter $1` sería binding → recién ahí aplica el fallback `$2`).
- **L-C-17** — **Cuarteto de gotchas de PowerShell 5.1 en el harness de smokes.** (a) **`[string]$X = $null` coerce a `""`** → usar **`[object]$X = $null`** para opcionales que deben quedar `$null` (si no, `ContentLength=0` → `raw_body_ausente`). (b) **`Invoke-WebRequest -Body byte[]`** puede mandar cuerpo vacío en PS 5.1 → usar **`HttpWebRequest`** con `ContentLength` explícito + `GetRequestStream().Write` + **TLS 1.2 forzado** (camino directo/HMAC, donde n8n recomputa el HMAC sobre el raw body). *(En el camino gateway no hay HMAC sobre el raw body — el gateway parsea JSON y refirma server-side —, así que `Invoke-RestMethod` alcanza; reconciliado con el harness GW de A07/A08.)* (c) **`(Where-Object …).Count` sobre un solo objeto** no devuelve 1 confiable → envolver en **`@(… | Where-Object …).Count`**. (d) **Contadores dentro de `function`** necesitan **`$script:`** (`$pass++` crea copia local → resumen `0/0`).
```

---

## 3. `ESTADO_ACTUAL_VITA_DELTA.md` (CRLF)

**Dos cambios (EOL CRLF):**

**(3a) Democión** — en el bloque que hoy empieza con `**Etapa actual:** Carril C — Portal Operativo Interno / **Slice 1 (lecturas reuse)** — **cerrada 2026-06-18**`, cambiar **solo** el prefijo:

- `**Etapa actual:**` → `**Etapa previa:**`

**(3b) Insertar** — el bloque nuevo de Slice 2 como **nueva "Etapa actual"**, inmediatamente **antes** del bloque de Slice 1 ya demotado (queda como primer "Etapa..." bajo "## Resumen ejecutivo"):

```markdown
**Etapa actual:** Carril C — Portal Operativo Interno / **Slice 2 (escrituras reuse)** — **cerrada 2026-06-20**. Las **tres primeras escrituras operativas** del portal sobre **TEST**: A07 `reserva.crear_manual` (crea reserva reusando `crear_prereserva`/`registrar_pago`/`confirmar_reserva` de 8B; vicky/socio), A08 `bloqueo.crear_manual` (reusa `crear_bloqueo` de 8D, `id_cabana` obligatorio —bloqueo total no se expone, 8D—; vicky/socio) y A10 `cobranza.registrar_saldo` (registra un pago `tipo='saldo'` reusando `registrar_pago`/`abortar_si_falla` de 9B; vicky/socio). Cada acción es un **wrapper n8n firmado** que revalida cinco dimensiones (HMAC sobre raw body + `ts` ±300 s + rol + **action binding** + `ambiente`), **inyecta el actor server-side** desde el JWT (`actorCoherente`; nunca del payload → el reject-unknown bloquea el spoof) y reusa funciones del motor existentes, sin invocar los webhooks viejos (8B/8D/W09). El gateway `portal-api` impone **allowlist doble** (D-C-39) + **action binding** (D-C-41) y, por ser escrituras, lleva `isWrite` (dispatch no confiable → `estado_incierto`, no `error_entorno`); su CATALOG quedó con **9 entradas** (1 Edge + 5 lecturas + 3 escrituras). Hitos: primera escritura vía gateway (A07, actor inyectado verificado en base), primer write transaccional con lock (A10: `pg_advisory_xact_lock` por `id_reserva` + dos sentencias con snapshot fresco que impiden el doble cobro, D-C-50), modelo de error de dos capas (etiquetas internas → allowlist, sin códigos crudos, D-C-51). Validación empírica **por capa** (batería directa + batería vía gateway por acción), con el **assert de regresión obligatorio de A10 corrido end-to-end** (SOBREPAGO → `conflicto`, nunca `estado_incierto`): A10 gateway **9/9** precheck + **9/9** smoke + verif con actor inyectado (vicky/franco) + gate post limpio; A10 directo **33/0** seguridad + **11/0** funcional + **7/0** concurrencia (no-sobrepago demostrado); A07/A08 cerrados previamente (directo + gateway), incorporados por referencia a sus runsheets. **Decisiones D-C-50/51; lecciones L-C-16/17** (A07/A08 no agregaron). **OPS intacto; `6B_SCHEMA_SQL.md` v1.8.1 sin cambios** (las tres escrituras reusan funciones del motor; `portal_usuarios` sigue TEST-only). **W09 sigue INACTIVO** hasta decisión posterior; el wrapper A10 directo queda **ACTIVO** (el gateway lo necesita para despachar). Próxima etapa: **Slice 3a** (lecturas nuevas A24/A25) / **Slice 3b** (gastos A11/A13). Cierre: `C_SLICE2_CIERRE.md`.
```

---

## 4. `CLAUDE.md` (LF)

**Anchor / ubicación:** insertar **después** del bloque `**Carril C — Portal Operativo Interno / Slice 1 (lecturas reuse) ✅ Cerrada (2026-06-18):** ...` (en la sección "## Estado del proyecto").

**Bloque a insertar (LF):**

```markdown
**Carril C — Portal Operativo Interno / Slice 2 (escrituras reuse) ✅ Cerrada (2026-06-20):** las **tres primeras escrituras operativas** del portal sobre **TEST**, vía **wrappers n8n firmados** (revalidan HMAC + `ts` + rol + **action binding** + ambiente; **inyectan el actor server-side** desde el JWT —`actorCoherente`, nunca del payload— y reusan funciones del motor existentes, sin los webhooks viejos). A07 `reserva.crear_manual` (reusa `crear_prereserva`/`registrar_pago`/`confirmar_reserva` de 8B; vicky/socio), A08 `bloqueo.crear_manual` (reusa `crear_bloqueo` de 8D, `id_cabana` obligatorio —bloqueo total no se expone—; vicky/socio), A10 `cobranza.registrar_saldo` (reusa `registrar_pago`/`abortar_si_falla` de 9B; vicky/socio). Gateway `portal-api` con **allowlist doble** (D-C-39) + **action binding** (D-C-41) + `isWrite` (dispatch no confiable → `estado_incierto`); CATALOG con 9 entradas (1 Edge + 5 lecturas + 3 escrituras). Hitos: primera escritura vía gateway (actor inyectado verificado en base, reject-unknown anti-spoof), primer write transaccional con lock (A10, `pg_advisory_xact_lock` + dos sentencias con snapshot fresco, D-C-50), modelo de error de dos capas (D-C-51). Validado por capa con el **assert de regresión de A10 end-to-end** (SOBREPAGO → `conflicto`, nunca `estado_incierto`): A10 gateway 9/9 + 9/9 + verif; A10 directo 33/0 + 11/0 + 7/0; A07/A08 por referencia. **Decisiones D-C-50/51, lecciones L-C-16/17** (A07/A08 no agregaron). OPS intacto; canónico **v1.8.1 sin cambios**; `portal_usuarios` sigue TEST-only. **W09 INACTIVO** hasta decisión posterior; wrapper A10 directo **ACTIVO** (el gateway lo necesita). Cierre `C_SLICE2_CIERRE.md`. **Próxima etapa: Slice 3a (lecturas nuevas A24/A25) / Slice 3b (gastos A11/A13).**
```

---

## 5. `Pendiente_pre_produccion.md` (LF) — **SIN CAMBIOS (recomendado)**

Slice 2 **no resuelve ni agrega** ningún ítem `P-C-*`:
- P-C-7/8/10/11 (hardening pre-OPS) siguen abiertos.
- **P-C-9** (store anti-replay de `nonce`) sigue **correctamente diferido a la primera escritura no-idempotente sin guard (A11)**: las tres escrituras de Slice 2 son idempotentes/guardadas (A07 por prereserva/seña, A08 por solapamiento, A10 por `idempotency_key` + advisory lock), así que la ventana `ts` ±300 s alcanza.

Igual que en el cierre de Slice 1, **se recomienda dejarlo intacto**. (Si preferís dejar rastro explícito, una opción mínima es anotar en P-C-9 que Slice 2 confirmó que sus tres escrituras son idempotentes/guardadas y por eso el store de `nonce` sigue diferido a A11 — opcional.)

---

## 6. `6B_SCHEMA_SQL.md` y OPS — **SIN CAMBIOS**

Carril C no toca el canónico: las tres acciones **reusan** funciones del motor existentes, sin DDL. OPS intacto.
