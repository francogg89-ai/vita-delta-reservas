# Cierre TEST — Frente Retiro desde saldo vivo (escritura de Cuenta Corriente)

> **Estado:** **backend/gateway** del retiro COMPLETO y verde en TEST (sub-bloques SB0 + SB1 +
> A29). Este cierre deja lista la **acción** `cuenta_corriente.retirar`; **NO** agrega UI en el
> portal (botón/formulario "Retirar saldo") — eso es un frente **posterior** a la promoción OPS
> del backend (ver Pendientes §9). "Frente retiro completo" = backend, **no** "ya visible en el
> portal". El retiro es el **lado escritura** del frente Cuenta Corriente (P-CC-2), por lo que
> continúa el namespace `D-CC-*` / `L-CC-*` del frente de lecturas.
>
> **Disciplina de códigos (igual que el cierre L1/L2):** las decisiones y lecciones de acá son
> **candidatas** (`D-CC-15..22`, `L-CC-12..13` **propuestas**). Se **acuñan formalmente y se
> propagan a los satélites** (`DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, schema)
> **recién en la promoción a OPS**, junto con el bump canónico a **v1.11.0** — en un solo
> batch, para no tocar satélites a mitad de frente. Nada de esto toca OPS/canónico/frontend
> todavía.

---

## 1. Qué cierra este frente

El lado **escritura** de la cuenta corriente de socios: registrar un **retiro** validado
contra el **saldo VIVO** (no fotos congeladas) y escrito **append-only** en `movimientos_socio`.
Tres sub-bloques, todos verdes en TEST:

- **SB0** — FK `portal_usuarios.id_socio` → `socios` (+ backfill + CHECK + UNIQUE). Vincula la
  fila de portal con el socio de negocio.
- **SB1** — tabla `portal_idempotencia_cc` + `registrar_retiro_desde_saldo_vivo(...)` +
  wrapper `portal_registrar_retiro(jsonb)`. La lógica de negocio + idempotencia + vínculo de
  identidad, en el mismo patrón que `portal_cargar_gasto_interno`.
- **A29** — exposición por el gateway `portal-api` (acción `cuenta_corriente.retirar`,
  socio-only) + wrapper n8n `portal-a29-retiro__TEST`.

---

## 2. Arquitectura (cuatro capas, patrón A11/A10-MP)

1. **Schema (SB0):** `portal_usuarios.id_socio bigint` FK→`socios(id_socio)` `ON DELETE RESTRICT`
   (nullable), `CHECK ((rol='socio')=(id_socio IS NOT NULL))`, `UNIQUE(id_socio)`.
2. **Negocio (SB1):** `registrar_retiro_desde_saldo_vivo(id_socio, monto, medio_pago, creado_por,
   comentario)` — lock por socio `pg_advisory_xact_lock(919002, id_socio::int)`, valida contra
   `cuenta_corriente_viva(NULL, pct_operativo_vigente()).saldo_al_dia` (idéntico a L1), inserta
   retiro `monto` NEGATIVO. Errores de dominio: `VD001`=saldo insuficiente, `VD002`=argumento
   inválido.
3. **Idempotencia + contrato (SB1):** `portal_registrar_retiro(jsonb)` — espeja
   `portal_cargar_gasto_interno`: control inyectado por el gateway (`actor/rol/id_socio/nonce`)
   + `idempotency_key` del cliente; vínculo fuerte `id_socio↔actor` vía `portal_usuarios`;
   anti-replay por `nonce`, idempotencia por `(action,idempotency_key)`, `saldo_insuficiente`
   (VD001) **no** quema la key (savepoint revierte, sin fila en `_cc`). Contrato `{ok,data|error}`.
4. **Gateway + wrapper (A29):** acción `cuenta_corriente.retirar` (socio-only) → wrapper n8n
   firmado `portal-a29-retiro__TEST` → `portal_registrar_retiro`. `id_socio`+`user_id`
   inyectados server-side (`injectSocioIdentity`); `monto` como string; `saldo_insuficiente`
   allowlisted con `detail` sanitizado.

---

## 3. Artefactos generados (fase TEST)

- **SB0:** `CC_RETIRO_SB0_A_FK_ID_SOCIO_TEST.sql`, `CC_RETIRO_SB0_B_VERIFY_TEST.sql`.
- **SB1:** `CC_RETIRO_SB1_A_FUNCIONES_TEST.sql`, `CC_RETIRO_SB1_B_VERIFY_TEST.sql`.
- **A29:** `portal-api_A29_TEST_index.ts` (gateway completo por patcher), `portal-a29-retiro__TEMPLATE.json`
  (wrapper n8n), `portal-a29-retiro__GW_smoke.ps1` + `portal-a29-retiro__GW_verify.sql` (smoke+verify),
  y los generadores `patch_a29.py` / `build_wrapper_a29.py` (provenance reproducible).

---

## 4. Contrato de `cuenta_corriente.retirar`

- **Request (cliente → gateway):** `{ action:'cuenta_corriente.retirar', payload:{ monto (string),
  medio_pago (efectivo|transferencia_bancaria), comentario? }, idempotency_key (sibling, 8-64) }`.
  El cliente **NO** manda `id_socio`/`user_id`/control (rebotan `payload_invalido` top-level y en payload).
- **Sobre firmado (gateway → wrapper):** el gateway inyecta `actor` (persona), `id_socio`
  (de `portal_usuarios.id_socio`), `user_id` (del JWT), `nonce`, `ambiente_esperado`, `ts`.
- **Éxito:** `{ ok:true, data:{ id_movimiento, idempotente } }`.
- **Errores (allowlist):** `payload_invalido`, `rol_no_permitido`, `no_autorizado`,
  `accion_desconocida`, `conflicto` (nonce_replay / payload_mismatch / actor_mismatch),
  `saldo_insuficiente` (con `detail:{saldo_disponible, monto_solicitado}`), `error_entorno`,
  `error_interno`, `estado_incierto`.

---

## 5. Decisiones candidatas (`D-CC-*`, a acuñar en la promoción a OPS)

- **D-CC-15** [SB1] — El retiro escribe **append-only** en `movimientos_socio` (`tipo='retiro'`,
  `monto` NEGATIVO), **nunca** en `gastos_internos`, y valida contra el **saldo VIVO**
  (`cuenta_corriente_viva(NULL, pct_operativo_vigente()).saldo_al_dia`, idéntico a L1), **no**
  contra fotos congeladas.
- **D-CC-16** [SB1] — Se agregan **dos funciones nuevas** (`registrar_retiro_desde_saldo_vivo`
  + `portal_registrar_retiro`) y **NO se toca `registrar_retiro` vieja** (que valida snapshots
  congelados). Conviven; el frente de escritura usa solo las nuevas.
- **D-CC-17** [SB0] — `portal_usuarios.id_socio` FK→`socios` (nullable, `ON DELETE RESTRICT`),
  con `CHECK ((rol='socio')=(id_socio IS NOT NULL))` y `UNIQUE(id_socio)`: todo socio tiene
  su fila vinculada 1-a-1; jenny/vicky quedan sin `id_socio`.
- **D-CC-18** [SB1] — **Vínculo de identidad `id_socio↔actor`** exigido en el wrapper SQL: el
  `id_socio` debe pertenecer al `actor` (vía `portal_usuarios`, case-insensitive); si el gateway
  inyectó `user_id`, debe ser la misma fila. Divergencia → `identity_mismatch`/`user_id_mismatch`.
- **D-CC-19** [A29] — Gateway **`injectSocioIdentity`** (flag nuevo, solo esta acción): `id_socio`
  (de `portal_usuarios.id_socio`) + `user_id` (del JWT `uid`) se inyectan **server-side** en el
  sobre firmado; el cliente **nunca** los manda. Un cliente que los mande **rebota
  `payload_invalido`** — top-level (`CONTROL_TOPLEVEL_PROHIBIDAS`) y en payload (validator).
  **Fail-closed** si al socio le falta `id_socio` (no se firma).
- **D-CC-20** [A29] — `monto` viaja como **STRING validado textualmente** (sin float) de punta a
  punta: gateway `^[0-9]{1,12}(\.[0-9]{1,2})?$` + wrapper n8n + SQL `^[0-9]+([.][0-9]{1,2})?$`
  (clase `[.]` por L-CC-09), por precisión de plata.
- **D-CC-21** [A29+SB1] — **Excepción acotada de `detail` SOLO para `saldo_insuficiente`**: se
  propaga `{saldo_disponible, monto_solicitado}` reconstruido y **solo si ambos son números
  finitos**; todo otro código `detail:null`. El saldo se revela recién **después** de validar
  identidad (no antes) para no filtrar saldos a un actor no vinculado.
- **D-CC-22** [SB1] — Idempotencia de retiro en **tabla propia** `portal_idempotencia_cc`
  (FK→`movimientos_socio`, rol socio-only, **REVOKE-all** / sin Data API): `nonce` UNIQUE =
  anti-replay; `(action,idempotency_key)` UNIQUE = idempotencia; `payload_norm`+`actor` =
  conflicto. `saldo_insuficiente` (VD001) **no quema la key** (savepoint revierte).

## 6. Lecciones candidatas (`L-CC-*`, a acuñar en la promoción a OPS)

- **L-CC-12** [A29] — **Validar un delta de gateway `.ts` por patcher aislando artefactos del
  shim.** El cliente Supabase sin tipos generados es `any` en runtime; un shim ambiental
  demasiado estricto genera falsos positivos (`pu.nombre`, `puErr.message`). Se aísla el delta
  real corriendo `tsc --noEmit --strict` sobre la **base** (A28) **y** el **patcheado** (A29) con
  el **mismo** shim y comparando: errores idénticos = pre-existentes/shim; errores nuevos = tu
  delta. (A29 dio EXIT 0 con shim realista `data:any` en ambos.)
- **L-CC-13** [A29] — *(verificar si no es ya tácito)* Los **Code nodes de n8n corren en contexto
  async**; `await this.helpers.getBinaryDataBuffer(...)` top-level es válido ahí. `node --check`
  trata el `.js` como módulo CJS y **falsea** ese `await` top-level; para validar la sintaxis hay
  que envolver el cuerpo en `(async function(){ ... })`.

---

## 7. Estado de validación (TEST)

- **Generación/estática:** patcher A28→A29 con **12 anclas `count==1` + prueba de reversa global
  byte-idéntica** (cero colateral); TS LF puro, **esbuild** EXIT 0 y **`tsc --strict`** EXIT 0
  (idéntico a A28 con shim realista); wrapper JSON válido + 5 code nodes OK por `node --check`
  async; smoke PS ASCII/LF + balance OK; verify SQL **pglast** OK.
- **End-to-end en TEST (ejecutado por Franco):**
  - **Smoke gateway: 35 PASS / 0 FAIL.** Códigos vistos: `accion_desconocida`, `conflicto`,
    `no_autorizado`, `payload_invalido`, `rol_no_permitido`, `saldo_insuficiente` (todos en la
    allowlist, incl. `saldo_insuficiente`).
  - Relevantes: jenny/vicky → `rol_no_permitido`; sin JWT → `no_autorizado`; montos/medios/keys
    inválidos → `payload_invalido`; control en payload **y** top-level → `payload_invalido`;
    `id_socio` ajeno en payload → `payload_invalido` **con 0 escrituras**; F1 retiro nuevo → ok +
    `id_movimiento`; F2 retry → mismo `id_movimiento`; F3 misma key + payload distinto →
    `conflicto`; F4 monto > saldo → `saldo_insuficiente` + detail; F5 misma key → `saldo_insuficiente`
    (**key no quemada**).
  - **PART B (estado en DB): 9/9 PASS** — 1 fila en `portal_idempotencia_cc` (K_F1); K_SALDO /
    K_AJENO / K_SEC = 0; 1 retiro `tipo=retiro` `monto=-0.01` `creado_por=franco`.

---

## 8. Residuo aceptado en TEST

Un **único retiro append-only de `0.01`** sobre franco (K_F1), idempotente por key fija (re-correr
el smoke = 0 filas nuevas). Aceptado explícitamente por Franco. `movimientos_socio` es append-only
→ no se borra; no afecta OPS.

---

## 9. Pendientes / deuda consciente

- **UI del Portal Operativo (frente posterior):** este cierre deja lista la acción
  backend/gateway `cuenta_corriente.retirar`, pero **todavía NO agrega** el botón/formulario
  "Retirar saldo" en el frontend. La UI de retiro queda como **frente posterior a la promoción
  OPS del backend** (nadie puede disparar un retiro desde el portal hasta que ese frente exista).
- **Kit de bootstrap (P-CC-4):** pinneado en v1.10.0; se regenera cuando cierre el frente completo
  (post-OPS del retiro), no antes.
- **L3 / foto mensual congelada:** sigue diferido (D-CC-11). El retiro escribe el saldo vivo; la
  foto mes-a-mes es frente aparte.
- **`pct_operativo`:** NO se cambia en este frente (guardrail P-CC-5); se lee vía
  `pct_operativo_vigente()` (D-CC-13/14).
- **D5 (auto-test estructural):** `portal_usuarios` ahora tiene una **2da FK** (`id_socio`→`socios`);
  el auto-test de grafo FK debe extenderse a cubrirla en la promoción.

---

## 10. Plan de promoción a OPS — frente retiro completo (SB0+SB1+A29)

> **DISEÑO SOLAMENTE.** No genero ningún artefacto OPS hasta tu OK. Precedente: D-CC-12 (paquete
> coordinado + canónico aditivo + `DROP+CREATE` en OPS + workflows + gateway). Todo con clone
> fresco y **fingerprint estructural OPS antes/después** (patrón K1 del Carril B).

**Bloque A — Schema SB0 en OPS (A0 diagnóstico → A1 dry-run → A2 commit).**

- **A0 (read-only; sin DDL, sin escrituras, sin secuencia):** diagnóstico previo. Lista
  `portal_usuarios` rol='socio' y `socios` activos; muestra el match normalizado
  `lower(btrim(portal_usuarios.nombre)) = lower(btrim(socios.nombre))` (idéntico al backfill SB0);
  detecta **duplicados normalizados en `socios`**, **socios del portal sin match** y **matches
  múltiples**. **Gate:** los cuatro chequeos críticos deben dar **0**. Recién con A0 verde se avanza.
  Artefacto: `CC_RETIRO_SB0_A0_DIAG_OPS.sql`.
- **A1 (dry-run DDL, en `BEGIN…ROLLBACK`):** agrega columna + backfill + postchecks del SB0, todo
  en una transacción que **se revierte**. Como es DDL + `UPDATE` (sin `nextval`), el rollback es
  limpio (no quema secuencia). Confirma mapeo 1:1 y que los asserts pasan, sin dejar nada.
- **A2 (commit):** el mismo SB0 sin rollback (columna + backfill + `CHECK` + `UNIQUE`), permanente.
  Verify estructural.

El `CHECK ((rol='socio')=(id_socio IS NOT NULL))` exige que **todo socio tenga `id_socio` ANTES**
de agregarse: A0 lo predice y A1 lo confirma antes de A2. Si A0 detecta algún socio sin match o
match múltiple/ambiguo → **STOP**, se resuelven los nombres en `socios`/`portal_usuarios` primero.

**Bloque B — SB1 (tabla + funciones) en OPS.**
`portal_idempotencia_cc` (REVOKE-all) + `registrar_retiro_desde_saldo_vivo` + `portal_registrar_retiro`
vía **`DROP FUNCTION` + `CREATE`** (L-CC-07; evita RLS espurias de Supabase).
**Verify OPS = estructural + negativo 0-write / 0-sequence, NO funcional-exitoso.** Motivo:
PostgreSQL **no revierte `nextval()`** con `ROLLBACK`, así que un retiro "exitoso en rollback"
quemaría igual la secuencia de `movimientos_socio`/`portal_idempotencia_cc`. Entonces el verify:
(a) valida **estructura** — tabla, columnas, `CHECK`/`FK`/`UNIQUE`, `REVOKE`/ACL, firmas de las 2
funciones, `SET search_path`; (b) ejecuta solo **errores que cortan ANTES de cualquier `INSERT`**
(p. ej. `payload_invalido` por control faltante, `rol_no_permitido`, `identity_mismatch`, y
`saldo_insuficiente` con monto enorme — VD001 corta antes del `INSERT`, sin `nextval`); (c) **NO**
ejecuta ningún retiro exitoso, ni siquiera en `BEGIN…ROLLBACK`. Preferencia explícita: **no
consumir ninguna secuencia en OPS**. Si en algún punto hiciera falta consumir secuencia, se eleva
como **decisión explícita** antes de ejecutar.

**Bloque C — Gateway A29 + wrapper en OPS.**
El gateway OPS es `portal-api_A28_OPS_index.ts` (**1232 líneas ≠ 1213 de TEST**: sufijos `__OPS`,
`ambiente`), así que el patcher A29 se **re-deriva contra A28_OPS** (no se reusa el de TEST): mismos
12 parches lógicos, webhook `'portal-a29-retiro__OPS'`. Wrapper `portal-a29-retiro__OPS.json`
(webhook `__OPS` por L-CC-06 aunque sea escritura, credencial OPS). Deploy gateway + activar wrapper.

**Bloque D — Smokes OPS (negativos, 0 escrituras).**
**Decisión clave a validar con vos:** el happy-path **no** se smoke-testea en OPS (escribiría un
retiro real append-only en el libro de un socio real). El smoke OPS corre **solo casos 0-escritura**
(rol_no_permitido, no_autorizado, payload_invalido, control-spoof, `id_socio` ajeno, `saldo_insuficiente`
con monto enorme). El happy-path/idempotencia/conflicto quedan cubiertos por: (a) verde en TEST, (b)
funciones idénticas TEST↔OPS (L-CC-07), (c) verify SQL de estructura en OPS. Verify OPS confirma
**0 filas nuevas** en `portal_idempotencia_cc`/`movimientos_socio` por los smokes.

**Bloque E — Canónico v1.11.0 + propagación de satélites (batch único).**
Acuñar `D-CC-15..22` y `L-CC-12..13`; actualizar `6B_SCHEMA_SQL.md` (nueva tabla
`portal_idempotencia_cc`, nueva columna `portal_usuarios.id_socio`, 2 funciones nuevas),
`DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`,
`Pendiente_pre_produccion.md`; bump a **v1.11.0** (aditivo). Propagación con patchers Python
`count==1`. Extender **D5** (2da FK de `portal_usuarios`). Commit + fingerprint OPS final
(diff estructural = solo los objetos aditivos del retiro).

---

**Próximo paso:** decime si el cierre TEST te cierra (namespace `D-CC-*` continuado, candidatos
propuestos) y si aprobás el esqueleto del plan OPS. Con tu OK arranco **Bloque A** (dry-run de
backfill), un bloque por conversación, con hard stop antes de cada COMMIT.
