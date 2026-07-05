# Cierre OPS — Frente Retiro desde saldo vivo (escritura de Cuenta Corriente)

> **Estado:** **CERRADO en OPS.** El lado **escritura** de la cuenta corriente de socios —registrar
> un **retiro** validado contra el **saldo VIVO** y escrito append-only en `movimientos_socio`—
> quedó **promovido a OPS** (SB0 + SB1 + gateway A29 + wrapper), con el **canónico bumpeado a
> `6B_SCHEMA_SQL.md v1.11.0`** y los satélites propagados. Cierra la **acción**
> `cuenta_corriente.retirar` (backend + gateway).
>
> **Alcance explícito:** este cierre **NO** agrega UI en el portal (botón/formulario "Retirar
> saldo") — eso es un **frente frontend posterior**. "Frente retiro completo" = **backend +
> gateway**, no "ya visible en el portal": nadie puede disparar un retiro desde el portal hasta
> que ese frente frontend exista.
>
> **Namespace:** el retiro es el lado escritura del frente Cuenta Corriente (**P-CC-2**), por lo
> que continúa el namespace `D-CC-*` / `L-CC-*` del frente de lecturas L1/L2
> (`CIERRE_CARRIL_CUENTA_CORRIENTE_L1_L2.md`). Este cierre **acuña formalmente** `D-CC-15..22` y
> `L-CC-12` (antes candidatas en el cierre TEST) y las deja propagadas a los satélites.

---

## 1. Qué cierra este frente

El lado **escritura** de la cuenta corriente de socios: registrar un **retiro** validado contra el
**saldo VIVO** (`cuenta_corriente_viva`, no fotos congeladas) y escrito **append-only** en
`movimientos_socio` (`tipo='retiro'`, `monto` negativo). Tres sub-bloques, todos verdes en TEST y
promovidos a OPS:

- **SB0** — FK `portal_usuarios.id_socio` → `socios` (+ backfill + `CHECK` + `UNIQUE`). Vincula la
  fila del portal con el socio de negocio (todo socio 1-a-1; jenny/vicky sin `id_socio`).
- **SB1** — tabla `portal_idempotencia_cc` + función de dominio `registrar_retiro_desde_saldo_vivo(...)`
  + wrapper `portal_registrar_retiro(jsonb)`. Lógica de negocio + idempotencia + vínculo de
  identidad, en el mismo patrón que `portal_cargar_gasto_interno`.
- **A29** — exposición por el gateway `portal-api` (acción `cuenta_corriente.retirar`, **socio-only**)
  + wrapper n8n `portal-a29-retiro__OPS`.

---

## 2. Arquitectura (cuatro capas, patrón A11/A10-MP)

1. **Schema (SB0):** `portal_usuarios.id_socio bigint` (nullable) FK→`socios(id_socio)`
   `ON DELETE RESTRICT`, `CHECK ((rol='socio')=(id_socio IS NOT NULL))`, `UNIQUE(id_socio)`.
2. **Negocio (SB1):** `registrar_retiro_desde_saldo_vivo(id_socio, monto, medio_pago, creado_por,
   comentario)` — lock por socio `pg_advisory_xact_lock(919002, id_socio::int)`, valida contra
   `cuenta_corriente_viva(NULL, pct_operativo_vigente()).saldo_al_dia` (**idéntico a L1**), inserta
   el retiro con `monto` **NEGATIVO**. Errores de dominio: `VD001`=saldo insuficiente,
   `VD002`=argumento inválido. `SECURITY INVOKER`, `SET search_path = public, pg_temp`.
3. **Idempotencia + contrato (SB1):** `portal_registrar_retiro(jsonb)` — espeja
   `portal_cargar_gasto_interno`: control inyectado por el gateway (`actor/rol/id_socio/nonce`) +
   `idempotency_key` del cliente; vínculo fuerte `id_socio↔actor` vía `portal_usuarios`; anti-replay
   por `nonce`, idempotencia por `(action,idempotency_key)`; `saldo_insuficiente` (VD001) **no quema
   la key** (savepoint revierte, sin fila en `portal_idempotencia_cc`). Contrato `{ok,data|error}`.
4. **Gateway + wrapper (A29):** acción `cuenta_corriente.retirar` (socio-only) → wrapper n8n firmado
   `portal-a29-retiro__OPS` → `portal_registrar_retiro`. `id_socio`+`user_id` inyectados server-side
   (`injectSocioIdentity`); `monto` como string; `saldo_insuficiente` allowlisted con `detail`
   sanitizado.

---

## 3. Recorrido TEST → OPS

| Sub-bloque | TEST | OPS |
|---|---|---|
| **SB0** (FK `id_socio`) | `CC_RETIRO_SB0_A_FK_ID_SOCIO_TEST.sql` + verify | `A0` diagnóstico → `A1` dry-run (`BEGIN…ROLLBACK`) → `A2` commit + verify |
| **SB1** (tabla + 2 funciones) | `CC_RETIRO_SB1_A_FUNCIONES_TEST.sql` + verify | `CC_RETIRO_SB1_FUNCIONES_OPS.sql` (`DROP FUNCTION`+`CREATE`) + verify estructural/negativo |
| **A29** (gateway + wrapper) | `portal-api_A29_TEST_index.ts` + `portal-a29-retiro__TEST` | gateway re-derivado contra `A28_OPS` (`portal-a29-retiro__OPS`), wrapper `__OPS` |
| **Canónico** | — | bump a **v1.11.0** (SB0/SB1 en PARTE C/D + D5 extendido) |
| **Satélites** | candidatos | `D-CC-15..22` / `L-CC-12` **acuñados** + propagados |

**Método de promoción (precedente D-CC-12 / patrón K1 del Carril B):** clone fresco, gate
anti-ambiente en cada migración, `DROP FUNCTION`+`CREATE` en OPS (L-CC-07, evita RLS espurias del
Dashboard), y **verificaciones OPS read-only con prueba empírica de cero filas nuevas y cero consumo
de secuencia** (`pg_sequence_last_value` con comparación NULL-safe `IS NOT DISTINCT FROM`).

---

## 4. Validación en OPS

> **Principio no negociable de la verificación OPS (D-CC del frente):** las verificaciones OPS son
> **read-only**: validan **estructura + negativos que cortan ANTES de cualquier `INSERT`**, con
> **prueba empírica de 0 filas nuevas y 0 `nextval`**. **No** se ejecuta ningún retiro exitoso en
> OPS —ni siquiera en `BEGIN…ROLLBACK`—, porque PostgreSQL **no revierte `nextval()`** con `ROLLBACK`:
> un retiro "exitoso en rollback" quemaría igual la secuencia de `movimientos_socio` /
> `portal_idempotencia_cc`. El happy-path queda cubierto por (a) verde en TEST, (b) funciones
> idénticas TEST↔OPS, (c) verify estructural en OPS.

- **SB0 en OPS:** `A0` diagnóstico read-only verde (0 duplicados normalizados en `socios`, 0 socios
  del portal sin match, 0 matches múltiples) → `A1` dry-run en `BEGIN…ROLLBACK` (mapeo 1:1 confirmado,
  sin dejar nada) → `A2` commit + verify **10/10 PASS**.
- **SB1 en OPS:** verify estructural + negativos **23/23 PASS** — tabla/columnas, `CHECK`/`FK`/`UNIQUE`,
  `REVOKE`/ACL (sin Data API), firmas de las 2 funciones y `SET search_path`; los negativos N1..N7
  cortan **antes** de cualquier `INSERT`. Guarda de 0-delta: `count_antes == count_despues` y
  secuencias sin avanzar (`pg_sequence_last_value` NULL-safe).
- **Gateway A29 en OPS:** patcher **re-derivado contra `portal-api_A28_OPS_index.ts`** (1232 líneas ≠
  1213 de TEST: sufijos `__OPS`, `ambiente`), mismos 12 parches lógicos, webhook
  `'portal-a29-retiro__OPS'`. **`tsc --noEmit --strict` y `esbuild` con delta 0** contra la base A28
  (mismo shim, L-CC-12); wrapper `portal-a29-retiro__OPS.json` con **`node --check` async 5/5**.
- **Smoke OPS (negative-only): 32 PASS / 0 FAIL.** Solo casos **0-escritura**: `rol_no_permitido`
  (jenny/vicky), `no_autorizado` (sin JWT), `payload_invalido` (montos/medios/keys inválidos + control
  en payload **y** top-level + `id_socio` ajeno), `saldo_insuficiente` con monto enorme (VD001 corta
  antes del `INSERT`). **El happy-path NO se smoke-testea en OPS** (escribiría un retiro real
  append-only en el libro de un socio real) — decisión explícita del frente.
- **PART A (secuencias antes/después): idéntico.** `movimientos_socio` y `portal_idempotencia_cc`
  con `pg_sequence_last_value` **sin avanzar** por los smokes.
- **PART B (estado en DB): 8/8 PASS.** Cero filas nuevas en `portal_idempotencia_cc` y en
  `movimientos_socio` por los smokes negativos (todos los contadores en 0).
- **Neto: cero escrituras / cero consumo de secuencias en OPS** por toda la verificación.

---

## 5. Contrato de `cuenta_corriente.retirar`

- **Request (cliente → gateway):** `{ action:'cuenta_corriente.retirar', payload:{ monto (string),
  medio_pago (efectivo|transferencia_bancaria), comentario? }, idempotency_key (sibling, 8-64) }`.
  El cliente **NO** manda `id_socio`/`user_id`/control (rebotan `payload_invalido` top-level y en
  payload).
- **Sobre firmado (gateway → wrapper):** el gateway inyecta `actor` (persona), `id_socio` (de
  `portal_usuarios.id_socio`), `user_id` (del JWT), `nonce`, `ambiente_esperado`, `ts`.
- **Éxito:** `{ ok:true, data:{ id_movimiento, idempotente } }`.
- **Errores (allowlist):** `payload_invalido`, `rol_no_permitido`, `no_autorizado`,
  `accion_desconocida`, `conflicto` (nonce_replay / payload_mismatch / actor_mismatch),
  `saldo_insuficiente` (con `detail:{saldo_disponible, monto_solicitado}`), `error_entorno`,
  `error_interno`, `estado_incierto`.

---

## 6. Decisiones acuñadas (`D-CC-15..22`)

- **D-CC-15** [SB1] — El retiro escribe **append-only** en `movimientos_socio` (`tipo='retiro'`,
  `monto` NEGATIVO), **nunca** en `gastos_internos`, y valida contra el **saldo VIVO**
  (`cuenta_corriente_viva(NULL, pct_operativo_vigente()).saldo_al_dia`, idéntico a L1), **no** contra
  fotos congeladas. Si no hay fila de saldo vivo para el socio (sin actividad contable) → saldo 0 →
  no puede retirar (`VD001`).
- **D-CC-16** [SB1] — Se agregan **dos funciones nuevas** (`registrar_retiro_desde_saldo_vivo` +
  `portal_registrar_retiro`) y **NO se toca `registrar_retiro` histórica** (que valida snapshots
  congelados). Conviven; el frente de escritura usa solo las nuevas.
- **D-CC-17** [SB0] — `portal_usuarios.id_socio` FK→`socios` (nullable, `ON DELETE RESTRICT`), con
  `CHECK ((rol='socio')=(id_socio IS NOT NULL))` y `UNIQUE(id_socio)`: todo socio tiene su fila
  vinculada 1-a-1; jenny/vicky quedan sin `id_socio`.
- **D-CC-18** [SB1] — **Vínculo de identidad `id_socio↔actor`** exigido en el wrapper SQL: el
  `id_socio` debe pertenecer al `actor` (vía `portal_usuarios`, case-insensitive); si el gateway
  inyectó `user_id`, debe ser la **misma fila** (binding fuerte). Divergencia →
  `identity_mismatch`/`user_id_mismatch`.
- **D-CC-19** [A29] — Gateway **`injectSocioIdentity`** (flag nuevo, solo esta acción): `id_socio`
  (de `portal_usuarios.id_socio`) + `user_id` (del JWT `uid`) se inyectan **server-side** en el sobre
  firmado; el cliente **nunca** los manda. Un cliente que los mande **rebota `payload_invalido`** —
  top-level y en payload. **Fail-closed** si al socio le falta `id_socio` (no se firma).
- **D-CC-20** [A29] — `monto` viaja como **STRING validado textualmente** (sin float) de punta a
  punta: gateway `^[0-9]{1,12}(\.[0-9]{1,2})?$` + wrapper n8n + SQL `^[0-9]+([.][0-9]{1,2})?$`
  (clase `[.]` por L-CC-09), por precisión de plata.
- **D-CC-21** [A29+SB1] — **Excepción acotada de `detail` SOLO para `saldo_insuficiente`**: se propaga
  `{saldo_disponible, monto_solicitado}` reconstruido y **solo si ambos son números finitos**; todo
  otro código `detail:null`. El saldo se revela recién **después** de validar identidad (no antes),
  para no filtrar saldos a un actor no vinculado.
- **D-CC-22** [SB1] — Idempotencia de retiro en **tabla propia** `portal_idempotencia_cc`
  (FK→`movimientos_socio`, rol **socio-only**, **REVOKE-all** / sin Data API): `nonce` UNIQUE =
  anti-replay; `(action,idempotency_key)` UNIQUE = idempotencia; `payload_norm`+`actor` = conflicto.
  `saldo_insuficiente` (VD001) **no quema la key** (savepoint revierte).

> **Nota sobre `D-A29-1`/`D-A29-3`:** referencias que aparecen en comentarios del gateway heredadas
> del diseño A29; **no** son del namespace de decisiones (no reabren nada). El namespace formal del
> frente es `D-CC-*`.

---

## 7. Lección acuñada (`L-CC-12`)

- **L-CC-12** [A29] — **Validar un delta de gateway `.ts` por patcher aislando artefactos del shim.**
  El cliente Supabase sin tipos generados es `any` en runtime; un shim ambiental demasiado estricto
  genera falsos positivos. Se aísla el delta real corriendo `tsc --noEmit --strict` sobre la **base**
  (A28) **y** el **patcheado** (A29) con el **mismo** shim y comparando: errores idénticos =
  pre-existentes/shim; errores nuevos = tu delta. (A29 dio **delta 0** con shim realista `data:any`
  en ambos.)

> **L-CC-13 NO se acuña:** el gotcha del `await` top-level en Code nodes de n8n que `node --check`
> falsea como CJS ya está cubierto por **L-C-27** (misma lección, frente Carril C). Se evita duplicar.

---

## 8. Artefactos finales

**Del cierre (batch coordinado, para el commit final por Franco):**

- **Satélites (Grupo a)** — patcher único `patch_satelites_E.py` sobre 4 satélites:
  `DECISIONES_NO_REABRIR.md` (acuña `D-CC-15..22`), `Lecciones_Aprendidas.md` (acuña `L-CC-12`),
  `ESTADO_ACTUAL_VITA_DELTA.md` (nueva "Etapa actual" del retiro cerrado en OPS),
  `Pendiente_pre_produccion.md` (bloque CERRADO 2026-07-05 + `P-CC-2` reformulado + `P-CC-4` a
  v1.11.0 + header actualizado).
- **Canónico (Grupo b)** — patcher único `patch_canonico_E.py` (30 edits, `count==1` + reversa
  byte-idéntica, LF) sobre `6B_SCHEMA_SQL.md`: bump **v1.10.1 → v1.11.0**, changelog, SB0/SB1 en
  PARTE C (`registrar_retiro_desde_saldo_vivo`, bloque C10-bis) y PARTE D (`portal_usuarios.id_socio`,
  `portal_idempotencia_cc` bloque D2-bis, `portal_registrar_retiro` bloque D3-bis), **D5 extendido a
  las 2 FKs de `portal_usuarios`** + los objetos nuevos, conteos (32 tablas / 36 funciones), índice,
  sección 25, orden de dependencias, nota C14 y footer. Generado por `make_patcher.py` (builder;
  extrae las definiciones SQL byte-exactas del SB0/SB1 OPS).
- **Este cierre** — `CIERRE_RETIRO_SALDO_VIVO_OPS.md`.

**Artefactos de ejecución OPS (evidencia, ya ejecutados por Franco):**

- **SB0:** `CC_RETIRO_SB0_A0_DIAG_OPS.sql`, `CC_RETIRO_SB0_A1_DRYRUN_OPS.sql`,
  `CC_RETIRO_SB0_A2_COMMIT_OPS.sql`, `CC_RETIRO_SB0_A2_VERIFY_OPS.sql`.
- **SB1:** `CC_RETIRO_SB1_FUNCIONES_OPS.sql`, `CC_RETIRO_SB1_VERIFY_OPS.sql`.
- **A29:** `portal-a29-retiro__OPS.json` (wrapper), `portal-a29-retiro__GW_smoke_OPS.ps1`,
  `portal-a29-retiro__GW_verify_OPS.sql` (gateway OPS re-derivado del `A28_OPS`).

---

## 9. Fuera de alcance / pendientes

- **UI del retiro (frente frontend posterior):** este cierre deja lista la acción backend/gateway
  `cuenta_corriente.retirar`, pero **NO** agrega el botón/formulario "Retirar saldo" en el portal.
  Es un frente **posterior**; hasta entonces nadie puede disparar un retiro desde el portal.
- **Bootstrap kit — NO se regenera ahora (P-CC-4).** Sigue pineado en
  `bootstrap_entorno_nuevo_v1.9.0/`, con deuda consciente acumulada (v1.10.0 lecturas CC + v1.10.1
  `pct_operativo` + **v1.11.0 SB0/SB1 del retiro**). Se regenera **recién al cierre del frente
  completo de cuenta corriente** (snapshot mensual/congelado + L3), no en este cierre.
- **Próximo frente backend contable:** **snapshot mensual/congelado + L3 histórico** (la foto
  mes-a-mes que habilita L3; hoy diferido por D-CC-11). El retiro escribe el saldo vivo; la foto
  congelada es un frente aparte.
- **Reembolsos:** **siguen pendientes** — no entraron en este frente. Quedan como pendiente separado
  dentro del remanente de **P-CC-2** (registro/exposición de reembolsos, análogo al retiro).
- **`pct_operativo`:** NO se cambia en este frente (guardrail P-CC-5); se lee vía
  `pct_operativo_vigente()` (D-CC-13/14).

> **Este artefacto es documental.** No toca **OPS, n8n, Vercel ni git**; no dispara ejecuciones. La
> promoción a OPS ya la ejecutó Franco (SB0/SB1/A29); el commit final del batch (satélites + canónico
> + este cierre) y el bump del canónico a v1.11.0 los hace **Franco**, sobre su propio clone fresco,
> aplicando los **dos patchers** (`patch_satelites_E.py` + `patch_canonico_E.py`).

---

## 10. Estado final

Frente **Retiro desde saldo vivo** (lado escritura de la cuenta corriente, **P-CC-2**) **cerrado en
backend + gateway sobre OPS**: SB0 + SB1 + A29 verdes, verificación OPS read-only con **cero
escrituras y cero consumo de secuencias**, canónico en **v1.11.0**, decisiones `D-CC-15..22` y
lección `L-CC-12` acuñadas y propagadas. Queda pendiente, como frentes separados, la **UI del
retiro** (frontend) y el **snapshot mensual/congelado + L3**; y dentro del remanente de P-CC-2, los
**reembolsos**.
