# A10-MP · Bloque 4 — Smokes · RUNSHEET

End-to-end de validación de `cobranza.registrar_cobro` (multi-porción) en **TEST**. Dos paths: **HMAC directo** al wrapper (suite completa) y **JWT gateway** (chain `portal-api` → wrapper, subset). Más verificación contable (A12/A25/distribución) y rollback atómico por SQL.

> **No avanzar a B5 frontend hasta que esta validación pase en TEST.**

---

## 0. Pre-condiciones (en orden)

1. **Wrapper B3.2 reimportado** (no el B3 viejo): workflow inactivo → reimportar `portal-a10mp-registrar-cobro__TEMPLATE.json` → reemplazar `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el mismo `VITA_HMAC_SECRET` de los otros wrappers → apuntar los **3 nodos PG** (`PG_cobro_mp`, `PG_verif_post`, y el de credencial) a la credencial Postgres **TEST** → **activar**.
2. **Gateway bloque 2 desplegado**: `portal-api` parcheado (con `cobranza.registrar_cobro`, CATALOG 14) en Supabase **TEST**.
3. **Credenciales del smoke gateway** (env del shell donde corras PowerShell):
   `VITA_SUPABASE_URL_TEST`, `VITA_SUPABASE_ANON_TEST`, `VITA_PW_VICKY`, `VITA_PW_FRANCO`, `VITA_PW_JENNY`.
4. **Secreto del smoke directo**: pegar `VITA_HMAC_SECRET` en `$Secret` dentro de `A10MP_B4_smoke_directo.ps1` (mismo valor del nodo `validar_firma_ts_rol`). No se commitea.

---

## 1. Orden de corrida

| # | Archivo | Dónde | Qué hace |
|---|---------|-------|----------|
| 1 | `A10MP_B4_setup.sql` | SQL Editor TEST (todo el archivo, nada seleccionado) | Crea 21 reservas con saldo (9910001..16 directo, 9910051..55 gateway) + huésped fixture. Veredicto **PASS** = 21 reservas. |
| 2 | `A10MP_B4_smoke_directo.ps1` | PowerShell 5.1 | Suite completa HMAC directo (seguridad + funcional + idempotencia A–E + notas F/G/H/I + sobrepago). |
| 3 | `A10MP_B4_smoke_gateway.ps1` | PowerShell 5.1 | Subset end-to-end por el gateway (felices, rol/payload/sobrepago, idempotencia match+mismatch). |
| 4 | `A10MP_B4_verif.sql` | SQL Editor TEST | Líneas por caso + **3 separaciones contables** sobre 9910002 + **rollback atómico**. |
| 5 | `A10MP_B4_teardown.sql` | SQL Editor TEST | Limpia cobros + fixtures FK-safe. Veredicto **PASS** = 0 cobros + 0 seed. |

> El paso 4 verifica la separación contable sobre **9910002** (transferencia + recargo), que escribe el **paso 2**. Si solo corrés el gateway, corré igual el directo antes del verif.

---

## 2. Smoke DIRECTO — matriz (`A10MP_B4_smoke_directo.ps1`)

**SEGURIDAD (0 escrituras — `secWrites` debe quedar en 0):**

| Caso | Esperado |
|------|----------|
| 1 firma inválida | `firma_invalida` |
| 2 / 3 ts viejo / futuro | `ts_fuera_de_ventana` |
| 4 / 5 rol jenny / vacío | `rol_no_permitido` |
| 6 action incorrecta (en el sobre firmado) | `payload_invalido` |
| 7 ambiente ops | `ambiente_incorrecto` |
| 8 actor desconocido | `payload_invalido` |
| 9 suma 0 (sin porciones) | `payload_invalido` |
| 10 otros sin origen | `payload_invalido` |
| 11 monto 3 decimales | `payload_invalido` |
| 12 idempotency_key corta | `payload_invalido` |
| 13 control `actor` en payload | `payload_invalido` |
| 14 subtipo inválido | `payload_invalido` |

**FUNCIONAL (escribe 6 cobros):**

| Caso | Reserva | Porciones | Esperado |
|------|---------|-----------|----------|
| D1 | 9910001 | efectivo 60000 | saldo 60000, extra 0, **saldada** |
| D2 | 9910002 | transf bancaria 40000 | saldo 40000, **extra 2000** |
| D3 | 9910003 | transf mp 40000 | saldo 40000, extra 2000 (`transferencia_mp`) |
| D4 | 9910004 | ef 50000 + transf 30000 | saldo 80000, extra 1500 |
| D5 | 9910005 | ef 50000 + transf 30000 + otros 20000 | saldo 100000, extra 1500, **saldada** |
| D6 | 9910006 | otros 20000 | saldo 20000, extra 0 |

**IDEMPOTENCIA (firma canónica B3.1 — 5 escrituras + 5 replays):**

| Caso | Reserva | 1er submit | Replay (misma key) | Esperado replay |
|------|---------|-----------|--------------------|-----------------|
| A | 9910007 | efectivo 100000 | mismo payload | `idempotent_match` |
| B | 9910008 | efectivo 100000 | transferencia 100000 | `conflicto` |
| C | 9910009 | transf bancaria 100000 | transf mp 100000 | `conflicto` |
| D | 9910010 | efectivo 100000 | otros 100000 | `conflicto` |
| E | 9910011 | otros 100000 desc-A | otros 100000 desc-B | `conflicto` |

**NOTAS (B3.2 — 4 escrituras + replays):**

| Caso | Reserva | 1er submit | Replay | Esperado |
|------|---------|-----------|--------|----------|
| F | 9910012 | transf 100000 + nota | — | ok (la nota se verifica en el paso 4) |
| G | 9910013 | ef 100000 + nota | misma nota | `idempotent_match` |
| H | 9910014 | ef 100000 + nota | nota distinta | `conflicto` |
| I | 9910015 | ef 100000 + nota | sin nota | `conflicto` |

**SOBREPAGO:** R · 9910016 saldo 70000, paga 80000 → `conflicto` (0 cobros).

**META:** allowlist (todos los `error.code` en la allowlist del gateway).

**Escrituras netas directo:** 6 (funcional) + 5 (idempotencia 1er submit) + 4 (notas 1er submit) = **15 eventos de cobro**. Replays/conflictos/seguridad: 0.

---

## 3. Smoke GATEWAY — matriz (`A10MP_B4_smoke_gateway.ps1`)

| # | Reserva | Caso | Esperado |
|---|---------|------|----------|
| 1 | 9910051 | vicky, efectivo 50000 | ok, saldo 50000, extra 0 |
| 2 | 9910052 | franco, transf mp 40000 | ok, saldo 40000, **extra 2000** |
| 3 | — | jenny | `rol_no_permitido` |
| 4 | — | sin JWT | `no_autorizado` |
| 5 | — | otros sin origen | `payload_invalido` |
| 6 | — | spoof `actor` en payload | `payload_invalido` |
| 7 | — | action inexistente | `accion_desconocida` |
| 8 | 9910053 | sobrepago 80000 > 70000 | `conflicto` **(nunca `estado_incierto`)** |
| 9 | 9910054 | efectivo 100000 + replay | `idempotent_match` |
| 10 | 9910055 | ef 100000 → transf 100000 | `conflicto` |
| META | — | allowlist | sin códigos fuera de allowlist |

**Escrituras netas gateway:** casos 1, 2, 9.1, 10.1 = **4 eventos de cobro**. El resto rebota o es idempotente.

> El caso 8 prueba end-to-end que el gateway **no enmascara un write con `estado_incierto`**: el wrapper devuelve `excede_saldo`→`conflicto` con HTTP 200 (D-C-51 / regresión A10).

---

## 4. Verificación contable + rollback (`A10MP_B4_verif.sql`)

Corre **después** del smoke directo. Tres secciones, cada una con veredicto:

1. **Líneas por caso** (`seccion='lineas_por_caso'`): confirma que
   - 9910002 tiene línea `saldo`/`transferencia_bancaria` + `extra`/`transferencia_bancaria` con `recargo_5_saldo_transferencia`;
   - 9910003 tiene `transferencia_mp` (medio derivado del subtipo, punto #5);
   - 9910006 registra `otros` como `saldo`/`efectivo` con traza `medio_original=otros;`;
   - 9910012 tiene `nota_operador=` en la línea `saldo` **y** la línea `extra` SIN `nota_operador`.

2. **Separación contable sobre 9910002** (`veredicto_contable` debe dar **PASS**):
   - `base_a12_y_25` = SUM(seña+saldo) → **A12 baja solo por esto** (el extra NO bajó saldo);
   - `caja_a25` = SUM(seña+saldo+extra) → **A25 incluye el extra**;
   - `caja_a25 − base = extra_total` y `caja_a25 > base` → el extra es caja percibida pero **no** base del 25%.
   Esto verifica los tres puntos: A12 baja solo por `suma_saldo`; A25 muestra `suma_saldo + suma_extra`; distribución toma solo seña+saldo.

3. **Rollback atómico** (`seccion='rollback_test'`, NOTICE con `raised=true, P0001, 0 pagos`): una línea con reserva inexistente hace que `registrar_pago` devuelva `ok:false` → `abortar_si_falla` lanza **P0001** → la sub-transacción revierte **ambas** líneas. Si no se cumple, la sección lanza excepción (FAIL visible). La probe se revierte: no deja datos.

---

## 5. Teardown (`A10MP_B4_teardown.sql`)

FK-safe (cobros `portal_test_a10mp_res%` → seña/reservas `seed_a10mp_%` → huésped 9910000), gate anti-OPS, idempotente. Veredicto **PASS** = 0 cobros + 0 seed restantes.

---

## Notas

- **Setup (excepción TEST-only controlada):** `A10MP_B4_setup.sql` inserta reservas en estado `confirmada` directamente para fabricar fixtures de cobranza con saldo. Está protegido por el gate anti-OPS y **no toca OPS ni canónico**. Las fechas se **escalonan** (rango único `[base+3k, base+3k+2)` desde 2030-08-01, paso 3 días) para no violar el `EXCLUDE USING gist` de `reservas` por solapamiento (B4.1). Las cabañas se asignan cíclicas pero ningún par comparte fechas → 0 solapamientos.
- Todos los scripts SQL llevan **gate anti-OPS** por `configuracion_general('ambiente')='test'` + identidad de cabañas 1–5. Si el ambiente no es TEST, abortan sin tocar nada.
- Los smokes PowerShell son **ASCII-puro CRLF** (PS 5.1), `HttpWebRequest` + `ContentLength` + TLS 1.2.
- El secreto HMAC del smoke directo **no se commitea** (placeholder con guard `StartsWith('__PEGAR_')`).
- Re-ejecución: si querés re-correr, volvé a correr `setup.sql` (es self-cleaning) para resetear los saldos, ya que los smokes consumen saldo.
