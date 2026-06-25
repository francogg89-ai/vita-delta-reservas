# A10-MP · Bloque 3 (+ patches B3.1 / B3.2) — Wrapper `portal-a10mp-registrar-cobro__TEST` · RUNSHEET

**Alcance:** wrapper n8n que expone la cobranza multi-porción + recargo 5% por el gateway. Clona la estructura verificada de **W10** (A10) e injerta la lógica de **W09** (porciones, recargo, líneas `saldo`+`extra`, "otros" como efectivo-equivalente con traza). **No toca** `registrar_pago`, tablas, enums, A12/A25/A13, OPS ni canónico — solo los invoca.

**Entregable:** `portal-a10mp-registrar-cobro__TEMPLATE.json` (sanitizado: sin `webhookId`/`instanceId`/ids de credencial; placeholders de secreto y credencial).

> **B3.1:** la idempotencia compara una **firma canónica de líneas** (no la financiera). Misma `idempotency_key` + medio/traza distintos → `conflicto`.
> **B3.2:** la **nota del operador** (`notas` del payload) se persiste en las líneas `saldo` sin pisar la traza interna (antes se descartaba). Forma parte de la firma canónica.

---

## 1. Estructura (12 nodos, topología idéntica a W10)

```
Webhook ─→ validar_firma_ts_rol ─→ leer_ambiente ─→ verificar_acceso ─→ IF_acceso
                                                                          ├─(true)→ derivar ─→ PG_cobro_mp ─┬─(ok)→ PG_verif_post ─→ render ─────→ Respond
                                                                          │                                 └─(error PG)──────────────→ render_error_pg ─→ Respond
                                                                          └─(false)──────────────────────────────────────────────────→ render_error ────→ Respond
```

| Nodo | Origen | Qué hace |
|---|---|---|
| `Webhook` | W10 (path nuevo) | POST firmado, `rawBody:true`, path `portal-a10mp-registrar-cobro__TEST`. |
| `validar_firma_ts_rol` | W10 **adaptado** | HMAC-SHA256 idéntico; `EXPECTED_ACTION='cobranza.registrar_cobro'`; `PAYLOAD_KEYS` multi-porción; revalida espejando `payloadRegistrarCobro`. |
| `leer_ambiente` / `verificar_acceso` / `IF_acceso` | W10 **verbatim** | ambiente=test; `acceso===true` → derivar, else → render_error. |
| `derivar` | **nuevo** (N3+N4.5 W09) | porciones; `recargo`; arma `lineas[]` (cada una = payload de `registrar_pago`); `source_event` determinista; `detalle`. |
| `PG_cobro_mp` | W10 `PG_cobranza` **generalizado** | nodo transaccional único (§3). |
| `PG_verif_post` | W10 **generalizado** | recalcula `saldo_real_actual` (A12) + suma `saldo`/`extra`/`cant` por `source_event`. |
| `render` | W10 **adaptado** | `data` multi-línea; mismo mapeo de errores. |
| `render_error` / `render_error_pg` / `Respond` | W10 **verbatim** | allowlist; P0001 → `error_interno`; HTTP 200 + envelope. |

---

## 2. `derivar` — armado de líneas (lógica W09)

- `recargo = tr > 0 ? round(tr * 0.05) : 0` (5% **solo** sobre transferencia).
- **Mapeo verificado:** `subtipo_transferencia === 'mp'` → `'transferencia_mp'`; cualquier otro → `'transferencia_bancaria'`.
- Líneas (orden efectivo → otros → transferencia(saldo) → extra), shape exacto de `registrar_pago` (`id_reserva, tipo, medio_pago, monto_esperado, monto_recibido, moneda:'ARS', estado_inicial:'confirmado', validado_por:actor, notas, source_event`):
  - `efectivo>0` → `saldo`/`efectivo` (`notas='porcion_efectivo'`).
  - `otros>0` → `saldo`/**`efectivo`** (equiv. ARS) con `notas = medio_original=otros; origen_otros=…; descripcion_otros=…; registrado_como=efectivo_ars`.
  - `transferencia>0` → `saldo`/`transferencia_(bancaria|mp)` **+** (si `recargo>0`) `extra`/mismo medio por el `recargo` (`notas='recargo_5_saldo_transferencia'`).
- `source_event = 'portal_test_a10mp_res' + id_reserva + '_' + sha256(id_reserva+'|'+key).slice(0,12)`.

- **B3.2 — nota del operador:** el campo opcional `notas` del payload se **anexa** a las notas internas de las líneas `saldo` vía `appendNotaOperador(base)`: si `notas` viene → `base + '; nota_operador=' + notas.trim()`; si no → `base` intacto. Se aplica a efectivo, transferencia(saldo) y otros (después de la traza); **NO** a la línea `extra` (interna/automática). Persiste en `pagos.notas` y es visible en A05/A13.

> **Ajuste de robustez (incluido en B3.1, decímelo si preferís el literal de W09):** la línea `extra` se crea **solo si `recargo>0`**. `registrar_pago` exige `monto_esperado>0` (`chk_pagos_monto_esperado`); una transferencia tan chica que redondea el recargo a 0 generaría una línea `extra` en 0 que violaría el constraint y haría **rollback de un cobro válido**. Con el guard, esa transferencia se cobra sin línea `extra` (recargo 0). No afecta los smokes (usan 100k → recargo 5000).

---

## 3. `PG_cobro_mp` — nodo transaccional (corazón) · **B3.1**

Un nodo Postgres, `queryBatching: transaction`, `onError: continueErrorOutput`. Dos statements:

1. **St1 — advisory lock:** `pg_advisory_xact_lock(hashtext('a10mp_cobro_saldo:'||id_reserva))`.
2. **St2 — `WITH … CASE`:**
   - **B3.1 — firma canónica de líneas:** dos CTE `existing_arr` (firma de las líneas ya registradas para el `source_event`, desde `pagos`) y `expected_arr` (firma de las líneas entrantes, desde `sql_payload.lineas`), **ambas con la MISMA normalización EN SQL** — sin render JS→SQL. Por línea: `{t:tipo, m:medio_pago, mr:to_char(monto,'FM…0.00'), n:COALESCE(notas,'')}`. Se comparan como **multiset** (`array_agg(obj::text ORDER BY obj::text)`, order-independent). `registrar_pago` persiste `tipo/medio_pago/monto_recibido/notas` (con `NULLIF(TRIM(...))`), por eso la firma reconstruida desde `pagos` coincide byte-a-byte con la entrante.
   - CTEs de saldo A12-alineado (`reserva_por_prereserva`, `pagos_reserva_normalizados`, `pagado`, `sr`).
   - **CASE (orden):**
     - **A) Idempotencia primero** — si `cardinality(existing_arr)>0`: `existing_arr = expected_arr` ⇒ `idempotent_match:true` (no escribe); difiere ⇒ `idempotency_mismatch`.
     - **B/C/D)** reserva inexistente / estado no cobrable / saldo ya cancelado.
     - **E) Anti-sobrepago HARD** — `suma_saldo > saldo_real` ⇒ `excede_saldo` (no escribe).
     - **F) Alta válida y nueva** — CTE `_ins AS MATERIALIZED` que recorre `jsonb_array_elements(lineas)` y por cada una hace `abortar_si_falla(registrar_pago(l.value))`. Si una línea falla → **P0001** → **rollback atómico** → `render_error_pg`.
   - La rama F solo se evalúa si A–E no matchean (CASE lazy-eval; mismo mecanismo que W10).

**Semántica de idempotencia (B3.1):** misma key + **mismas líneas exactas** (tipo+medio+monto+traza) → `idempotent_match`; misma key + **cualquier diferencia** de medio/monto/traza → `conflicto`. La traza de `otros` vive en `notas`, así que cambiar `origen_otros`/`descripcion_otros` cambia la firma → `conflicto`.

---

## 4. Response (`data`)

`{ source_event, cant_lineas, suma_saldo, suma_extra, total_cobrado, saldo_anterior, saldo_real_actual, saldada, idempotent_match, detalle }`. Montos autoritativos de `PG_verif_post` (post-commit por `source_event`). `saldo_anterior = saldo_real_actual + suma_saldo`. `total_cobrado = suma_saldo + suma_extra`. Errores: `excede_saldo`/`estado_no_cobrable`/`saldo_ya_cancelado`/`idempotency_mismatch` → `conflicto`; `reserva_no_existe` → `no_encontrado`; P0001 → `error_interno`.

---

## 5. Verificación hecha (local)

| Check | Resultado |
|---|---|
| pglast `PG_cobro_mp` (desde el JSON final) | **OK** (2 statements) |
| pglast `PG_verif_post` | **OK** (1 statement) |
| `node --check` de los 3 Code nodes (async-wrapped) | **OK** (3/3) |
| Invariantes estructurales | **OK** (12 nodos, topología, rename, placeholders, creds sanitizadas, sin fugas) |
| **B3.1 — lógica de firma canónica** (simulación derivar + normalización SQL) | **7/7 OK** (A, A2-mixto, B, C, D, E, F-order-independent) |
| **B3.2 — persistencia de notas + idempotencia** (simulación) | **6/6 OK** (nota persiste en saldo, extra sin nota, G match, H conflicto, I conflicto, J regresión) |

Evidencia caso B: firma `efectivo` = `[(saldo,efectivo,100000.00,porcion_efectivo)]` ≠ firma `transferencia` = `[(extra,…,5000.00,recargo…),(saldo,transferencia_bancaria,100000.00,porcion_transferencia)]` → `conflicto`.

---

## 6. Import / deploy (n8n)

1. **Importar** el JSON. *(Si ya importaste B3, dejalo inactivo y reimportá B3.1 antes de activar.)*
2. **Secreto HMAC (Modo B, L-C-10):** reemplazar `__PEGAR_SECRETO_O_USAR_VARIABLE__` en `validar_firma_ts_rol` por el **mismo `VITA_HMAC_SECRET`** de los otros wrappers. (assert por prefijo te frena si te lo olvidás).
3. **Credencial Postgres:** los 3 nodos PG → credencial **TEST** real.
4. **Path/binding:** Webhook `portal-a10mp-registrar-cobro__TEST` = `webhook` del CATALOG (bloque 2). `EXPECTED_ACTION='cobranza.registrar_cobro'` (D-C-41).
5. **Activar** el workflow.

> Smokes JWT-gateway completos requieren el **bloque 2 deployado**. Smokes HMAC directo corren con solo el wrapper activo.

---

## 7. Smokes obligatorios (bloque 4)

Doble camino (HMAC directo + JWT gateway). **Idempotencia (B3.1):**
- **A.** misma key, **mismo payload exacto** → `idempotent_match:true` (sin doble alta).
- **B.** misma key, **efectivo 100k vs transferencia 100k** → `conflicto`.
- **C.** misma key, **transferencia_bancaria 100k vs transferencia_mp 100k** → `conflicto`.
- **D.** misma key, **efectivo 100k vs otros 100k** → `conflicto`.
- **E.** misma key, **otros mismos montos, `descripcion_otros` distinta** → `conflicto`.

**Notas del operador (B3.2):**
- **F-notas.** cobro con `notas` → confirmar que aparece persistida (`nota_operador=…`) en las líneas `saldo` esperadas (y NO en `extra`).
- **G.** misma key + **mismas notas** → `idempotent_match:true`.
- **H.** misma key + **nota distinta** → `conflicto`.
- **I.** misma key + **con-nota vs sin-nota** → `conflicto`.

**Resto:** efectivo solo · transferencia bancaria (+5%) · transferencia MP (+5%) · mixto ef+transf · ef+transf+otros · otros sin recargo · **sobrepago** (`suma_saldo>saldo_real` ⇒ rebota sin escribir, 0 pagos por `source_event`) · **rollback** (línea inválida ⇒ 0 pagos) · **jenny** bloqueada.

**Verificaciones contables (las tres que pediste):** tras un cobro con transferencia + recargo: (a) **A12** baja solo por `suma_saldo`, no por `suma_extra`; (b) **A25** muestra `suma_saldo + suma_extra` como caja percibida; (c) la **distribución** toma solo `seña + saldo` como base del 25%.

**Próximo:** bloque 4 — smokes (PS5.1 ASCII-pure CRLF).
