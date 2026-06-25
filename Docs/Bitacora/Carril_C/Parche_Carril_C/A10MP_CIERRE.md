# CARRIL C — A10-MP `cobranza.registrar_cobro` (cobranza multi-porción) — CIERRE

**Estado:** ✅ **Etapa SOLO-DOCUMENTAL.** A10-MP (endpoint `cobranza.registrar_cobro`, multi-porción + recargo 5%) está **CERRADO y VALIDADO en TEST** de punta a punta: gateway `portal-api` (JWT → `injectActor` server-side → firma HMAC → wrapper n8n → función) + wrapper directo + corazón SQL multi-línea atómico. Este documento **transcribe el contrato exacto desde el código** (no de memoria) y **congela la numeración oficial de decisiones D-C-64…70** (ver nota de renumeración en §3). No toca runtime, gateway, wrapper, OPS, el canónico (`6B_SCHEMA_SQL.md`), tablas ni el endpoint viejo W10.

**Entorno de validación:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5, marcador `configuracion_general.ambiente='test'`.
**Entorno de operación:** — (A10-MP **no** se promovió a OPS; el Carril C **no** toca OPS para experimentar; W10 sigue desplegado en su lugar).
**Fecha de cierre:** 2026-06-25.
**Base (artefactos reales transcritos):** `A10MP_B2_portal-api_index.ts` (gateway, validador `payloadRegistrarCobro`, CATALOG 14) · `A10MP_B3_PG_cobro_mp.sql` (corazón SQL) · `portal-a10mp-registrar-cobro__TEMPLATE.json` (wrapper n8n) · `A10MP_B4_setup.sql` / `A10MP_B4_smoke_directo.ps1` / `A10MP_B4_smoke_gateway.ps1` / `A10MP_B4_verif.sql` / `A10MP_B4_teardown.sql` (+ `A10MP_B4_RUNSHEET.md`) · runsheets `A10MP_B2_RUNSHEET.md` / `A10MP_B3_RUNSHEET.md`.
**Depende de:** D-C-30 (JWT vía `getUser`) · D-C-34 (identidad/rol server-side desde `portal_usuarios`) · D-C-36/37 (dispatch a n8n firmado; `ambiente_esperado` desde variable) · D-C-39/41 (doble allowlist rol×action + action binding) · D-C-18/35 (envelope uniforme; HTTP 200 + envelope para resultados manejados) · D-C-50/51 (`isWrite` → `estado_incierto` ante dispatch no confiable, jamás enmascara un write) · D-C-49 / D-9B-05 (saldo recomputado por pagos confirmados con normalización por prereserva, byte-alineado a A12) · D-9B-19 (`abortar_si_falla` por línea → rollback atómico) · L-C-10 (assert del secreto por prefijo `__PEGAR_`) · L-C-11 (validador declarado antes del CATALOG, TDZ). Origen funcional de la lógica multi-porción + recargo 5%: **W09** (cobranza posterior). Convivencia con **W10 / `cobranza.registrar_saldo`** (A10): ver §6.
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.8.1` — **NO modificado por este cierre.** A10-MP **no** introduce DDL: reusa `public.registrar_pago`, `public.abortar_si_falla`, las tablas `pagos`/`reservas` y los enums existentes; el endpoint solo **invoca**.
**Autores:** Franco (titular, ejecutor de **todos** los deploys/smokes en Supabase y n8n) + Claude (arquitecto/copiloto; estrictamente advisory — no tocó infraestructura).
**Decisiones registradas:** D-C-64 · D-C-65 · D-C-66 · D-C-67 · D-C-68 · D-C-69 · D-C-70 🔒 (numeración **oficial** del cierre). **Lecciones propuestas:** guard `recargo>0`, fixtures escalonados por el EXCLUDE gist, "el SQL Editor de Supabase muestra solo el último `SELECT`" 📝. *(Las lecciones y la propagación a satélites quedan pendientes hasta el cierre formal de propagación — §7.)*

---

## 1. Resumen ejecutivo

A10-MP es una mini-etapa del Parche Carril C que agrega un **nuevo action de escritura** al gateway `portal-api`: **`cobranza.registrar_cobro`**. Expone por el gateway la lógica de **cobranza multi-porción** (efectivo + transferencia bancaria/MP + "otros") con **recargo 5% sobre la porción de transferencia**, generalizando el `PG_cobranza` de W10/A10 (que cobraba una sola porción) hacia el comportamiento de W09. Una sola llamada registra **N líneas de pago** en una **única transacción atómica**: si una línea falla, no queda nada escrito (rollback con `P0001`).

El endpoint es **idempotente** (clave en payload, `source_event` determinístico y PII-free, dedup por evento con **firma canónica multiset de las líneas**, incluida la nota del operador) y tiene **anti-sobrepago HARD dentro de la transacción** (la suma aplicada a saldo nunca puede exceder el `saldo_real` vivo; si excede, rebota `conflicto` sin escribir). La **separación contable** queda garantizada en SQL: las líneas `saldo` bajan el saldo real y entran al 25%, mientras la línea `extra` (recargo) **no** baja saldo, **no** entra a la base del 25%, pero **sí** suma a la caja percibida (A25).

W10 / `cobranza.registrar_saldo` queda **deprecated-in-place**: sigue desplegado y operativo, pero el portal deja de llamarlo; **B5 frontend usa únicamente `cobranza.registrar_cobro`** (§6, §8). Validado en TEST: smoke directo **40/40**, smoke gateway **13/13**, verificación SQL **6/6** + separación contable PASS + rollback atómico PASS + teardown sin residual (§5).

---

## 2. Qué se construyó

**Gateway `portal-api` — action `cobranza.registrar_cobro` (`A10MP_B2_portal-api_index.ts`):**
- **Validador `payloadRegistrarCobro`** (export, declarado **antes** del CATALOG por TDZ — L-C-11). Espejo de la capa de payload del wrapper (doble allowlist D-C-39): reject-unknown, montos de porción `number` finitos ≥0 con ≤2 decimales dentro de `NUMERIC(12,2)` (`MONTO_MAX_A10_GW = 9999999999.99`), suma de porciones > 0, `subtipo_transferencia` ∈ `{bancaria,mp}` default `bancaria`, regla de "otros", `idempotency_key` **en payload** (`IDEM_RE_GW = /^[A-Za-z0-9_-]{8,64}$/`), `notas` opcional (`MAXLEN_GW = 1000`). Devuelve el payload **normalizado/whitelisteado**.
- **Entrada CATALOG** `'cobranza.registrar_cobro'`: `handler:'n8n'`, `roles:['vicky','socio']`, `webhook:'portal-a10mp-registrar-cobro__TEST'`, `validate:payloadRegistrarCobro`, `injectActor:true`, `isWrite:true`. **CATALOG 14** = 1 Edge (`sesion.contexto`) + 8 lecturas + **5 escrituras** (A07, A08, A10/W10, A11, **A10-MP**).
- El `actor` (persona) se inyecta **server-side** desde `portal_usuarios.nombre` (`injectActor`); **nunca** viaja desde el frontend. `idempotency_key` **no** usa `needsIdempotencyKey` (es clave legítima del payload, como A10/W10), a diferencia de A11 donde es sibling.

**Wrapper n8n directo — `portal-a10mp-registrar-cobro__TEST` (`portal-a10mp-registrar-cobro__TEMPLATE.json`):**
Cadena de nodos `Webhook → validar_firma_ts_rol → leer_ambiente → verificar_acceso → IF_acceso → derivar → PG_cobro_mp → PG_verif_post → render` (con ramas `render_error` / `render_error_pg`) `→ Respond`.
- `validar_firma_ts_rol`: HMAC-SHA256 timing-safe (`firma_invalida`), ventana de `ts` `TS_WINDOW_MS = 300000` (`ts_fuera_de_ventana`), raw body presente (`raw_body_ausente`), `EXPECTED_ACTION = 'cobranza.registrar_cobro'` (action binding; mismatch → `payload_invalido`), `ROLES_OK = ['vicky','socio']` + coherencia actor↔rol, assert del secreto por prefijo `startsWith('__PEGAR_')` (L-C-10).
- `verificar_acceso`: cruza ambiente de la BD (`leer_ambiente`) contra el esperado → `ambiente_incorrecto` (wrapper **TEST-only**).
- `derivar`: arma `source_event` determinístico + `lineas[]` payload-ready para `registrar_pago`, calcula `recargo` y `suma_saldo` (detalle en §4).
- `PG_cobro_mp` (`A10MP_B3_PG_cobro_mp.sql`): lock advisory transaccional + idempotencia por firma canónica + saldo vivo + alta multi-línea atómica.
- `PG_verif_post`: relectura read-only post-COMMIT (montos autoritativos por `source_event`).
- `render`: arma `response.data` y mapea etiquetas internas → códigos externos de la allowlist.

**Smokes / SQL B4:**
- `A10MP_B4_setup.sql` — fixtures de reservas `confirmada` (DIRECTO 9910001…9910016, GATEWAY 9910051…9910055), cada una `monto_total = saldo + 30000` con **una seña confirmada de 30000** ⇒ `saldo_real = saldo`. Fechas **escalonadas** (rango único por fixture) para no violar el `EXCLUDE USING gist` de `reservas`.
- `A10MP_B4_smoke_directo.ps1` — **40 casos** contra el wrapper directo.
- `A10MP_B4_smoke_gateway.ps1` — **13 casos** por JWT contra el gateway.
- `A10MP_B4_verif.sql` — verificación SQL (líneas por caso + separación contable 9910002 + rollback atómico).
- `A10MP_B4_teardown.sql` — limpieza FK-safe con gate anti-OPS.

---

## 3. Decisiones (numeración oficial del cierre)

> **Nota de renumeración (importante).** Los comentarios del **código desplegado** (gateway y runsheets de A10-MP) citan provisionalmente **D-C-61…64** por arrastre del parche. Esos números **ya están tomados en el ledger canónico (`DECISIONES_NO_REABRIR.md`) por decisiones de A04** (D-C-61 saldo recomputado, D-C-62 `max(saldo_real,0)`, D-C-63 visibilidad de notas) y **no se reabren**. Esa cita en los comentarios es una **inconsistencia cosmética de documentación interna; no afecta runtime** (los comentarios no se ejecutan; el sobre firmado, los enums y la lógica son idénticos). **La numeración oficial del cierre queda D-C-64…70.** Corregir los comentarios del artefacto queda como **pendiente pre-producción cosmético**, a ejecutar solo si el artefacto se propaga/edita (ver §7). Esta renumeración **no toca** A04, ni el runtime, ni el gateway, ni el wrapper.

- **D-C-64** — **Nuevo action `cobranza.registrar_cobro` expone cobranza multi-porción + recargo 5% por gateway.** Generaliza la lógica de W09 (porciones efectivo/transferencia/otros + recargo del 5% sobre transferencia) y la cablea por el gateway `portal-api`. **W10 / `cobranza.registrar_saldo`** queda **deprecated-in-place** y **convive** (sigue desplegado y operativo), pero el portal deja de llamarlo: **B5 frontend usa SOLO el endpoint nuevo**.
- **D-C-65** — **Payload flat multi-porción.** Tres porciones independientes en el mismo payload: `monto_efectivo`; `monto_transferencia` con `subtipo_transferencia` ∈ `{bancaria,mp}`; `monto_otros` registrado como **efectivo-equivalente ARS** (con traza del medio original). Si `monto_otros > 0`, **exige** `origen_otros` + `descripcion_otros` (no vacíos). Si `monto_otros = 0`, esos campos **no deben venir** (rechazo explícito).
- **D-C-66** — **Idempotencia.** La `idempotency_key` viaja **dentro del payload** (como A10/W10, no como sibling). El `source_event` es **determinístico y PII-free** (derivado de `id_reserva` + `idempotency_key`, mismo para todas las líneas del evento). El dedup es **por evento** (`source_event`).
- **D-C-67** — **Anti-sobrepago HARD.** Tope `suma_saldo <= saldo_real`. La **autoridad es el wrapper**, que conoce el `saldo_real` vivo, y la verificación ocurre **dentro de la transacción** (tras el lock advisory). Si la suma aplicada a saldo excede el saldo pendiente, devuelve **`conflicto`** y **no escribe nada**.
- **D-C-68** — **Separación contable.** Los pagos `saldo` **bajan** el saldo real; los pagos `extra` (recargo) **no** bajan saldo. **A12** (saldos) **excluye** `extra`; **A25** (caja percibida) **incluye** `extra` como caja percibida. La **distribución / base del 25%** toma **solo `seña + saldo`** (nunca `extra`).
- **D-C-69** — **Firma canónica de idempotencia (B3.1).** El match idempotente compara por **multiset normalizado de líneas** (order-independent), construido en SQL con la **misma** normalización para las líneas existentes y las entrantes. Incluye `tipo`, `medio_pago`, `monto_recibido` (formateado) y `notas`. Misma key + **líneas exactamente iguales** → `idempotent_match:true`. Misma key + medio/monto/traza/notas distinto → **`conflicto`** (`idempotency_mismatch`).
- **D-C-70** — **Notas del operador (B3.2).** El campo opcional `notas` del payload se **persiste en las líneas `saldo`** anexado como `nota_operador=...` (sin pisar la traza interna `porcion_efectivo`/`porcion_transferencia`/traza de "otros"). **No** se agrega a la línea `extra` (auto-generada, interna). Forma parte de la **firma canónica** (D-C-69): misma key + **nota distinta** → **`conflicto`** (comportamiento correcto: cambió el evento).

**Sin ID propio (lecciones, §7):** el guard `recargo > 0` (no se genera línea `extra` cuando el recargo redondea a 0) y las **fechas escalonadas** del setup B4 (necesarias por el `EXCLUDE gist` de `reservas`).

---

## 4. Contrato final del endpoint (transcrito del código)

### 4.1. Payload

```
{
  id_reserva:            entero positivo estricto (Number.isSafeInteger, > 0)            [obligatorio]
  monto_efectivo:        number finito >= 0, <= 2 decimales, <= 9999999999.99            [opcional, default 0]
  monto_transferencia:   number finito >= 0, <= 2 decimales, <= 9999999999.99            [opcional, default 0]
  monto_otros:           number finito >= 0, <= 2 decimales, <= 9999999999.99            [opcional, default 0]
  subtipo_transferencia: 'bancaria' | 'mp'                                               [opcional, default 'bancaria']
  origen_otros:          string 1..120  (trim)                                           [obligatorio SOLO si monto_otros > 0]
  descripcion_otros:     string 1..200  (trim)                                           [obligatorio SOLO si monto_otros > 0]
  idempotency_key:       string ^[A-Za-z0-9_-]{8,64}$  (EN PAYLOAD)                       [obligatorio]
  notas:                 string <= 1000                                                  [opcional]
}
```

**Validaciones (gateway `payloadRegistrarCobro`, espejadas en el wrapper):**
- **reject-unknown**: claves permitidas exactamente las 9 de arriba; cualquier otra → `payload_invalido`.
- **Control prohibido en payload** (fail-fast): `actor`, `rol`, `nonce`, `source_event`, `creado_por`, `request_ts` → `payload_invalido`. El `actor` se inyecta server-side (`injectActor`) y el wrapper lo usa como `validado_por`.
- **Montos de porción**: ausente/`null` → 0; `number` finito ≥0; ≤2 decimales; dentro de `NUMERIC(12,2)`. Se devuelven **normalizados**.
- **Suma > 0**: `monto_efectivo + monto_transferencia + monto_otros` debe ser > 0 (al menos una porción). El **tope** `suma_saldo <= saldo_real` **no** se valida acá: es autoridad del wrapper, in-txn (D-C-67).
- **`subtipo_transferencia`**: lenient — se acepta aunque `monto_transferencia = 0` (queda inerte aguas abajo).
- **"otros"**: si `monto_otros > 0` exige `origen_otros` (1..120) y `descripcion_otros` (1..200) no vacíos; si `monto_otros = 0`, ambos deben estar ausentes (D-C-65).
- **`idempotency_key`**: en payload, 8..64 `[A-Za-z0-9_-]` (D-C-66).
- **`notas`**: opcional, ≤1000.

### 4.2. Roles

`['vicky','socio']`. **jenny → `rol_no_permitido` EN EL GATEWAY** (allowlist), antes de firmar y sin tocar n8n. En el wrapper, coherencia actor↔rol: `vicky` ⇒ actor `vicky`; `socio` ⇒ actor ∈ `{franco, rodrigo, remo}`. `injectActor:true` (actor server-side desde `portal_usuarios.nombre`). `isWrite:true` (ante dispatch no confiable → `estado_incierto`, jamás enmascara un write).

### 4.3. Allowlist de errores (gateway, `CODIGOS_ERROR_PERMITIDOS`)

```
payload_invalido · no_autorizado · rol_no_permitido · accion_desconocida ·
no_encontrado · conflicto · error_entorno · error_interno · estado_incierto ·
firma_invalida · ts_fuera_de_ventana · raw_body_ausente · ambiente_incorrecto
```

Cualquier código fuera de la allowlist (p.ej. un SQLSTATE crudo de Postgres) se enmascara como `error_entorno`. Para los códigos de infraestructura (`error_entorno`/`error_interno`/`estado_incierto`) el **gateway impone el message** (última barrera).

### 4.4. Derivación server-side (`derivar`)

- `recargo = (monto_transferencia > 0) ? Math.round(monto_transferencia * 0.05) : 0`. Solo sobre la porción de transferencia; **interno**, no lo carga el operador. **Guard `recargo > 0`**: si redondea a 0 (transferencia muy chica), **no** se genera línea `extra` (`registrar_pago` exige `monto_esperado > 0`).
- `suma_saldo = monto_efectivo + monto_transferencia + monto_otros`.
- **Medio de transferencia**: `subtipo_transferencia === 'mp'` → `transferencia_mp`; en otro caso → `transferencia_bancaria`.
- **`source_event`** (determinístico, PII-free, mismo para todas las líneas): `'portal_test_a10mp_res' + id_reserva + '_' + sha256(id_reserva + '|' + idempotency_key).slice(0,12)`.
- **Líneas** (orden `efectivo → otros → transferencia(saldo) → extra(recargo)`), cada una un payload completo de `registrar_pago` con `monto_esperado = monto_recibido = monto`, `moneda:'ARS'`, `estado_inicial:'confirmado'`, `validado_por: actor`, `source_event`:
  - `efectivo > 0` → línea `saldo` / `efectivo`, nota `porcion_efectivo`.
  - `otros > 0` → línea `saldo` / `efectivo` (efectivo-equivalente ARS), nota `medio_original=otros; origen_otros=...; descripcion_otros=...; registrado_como=efectivo_ars`.
  - `transferencia > 0` → línea `saldo` / `transferencia_(bancaria|mp)`, nota `porcion_transferencia`; **si `recargo > 0`** → línea `extra` / `transferencia_(bancaria|mp)`, nota `recargo_5_saldo_transferencia` (**sin** `nota_operador`).
- **Nota del operador (D-C-70)**: si `notas` no vacío, se anexa `'; nota_operador=' + notas` a las **líneas `saldo`** (no a la `extra`).

### 4.5. `response.data` (render, camino éxito)

```
{
  source_event,                       // del evento (derivar)
  cant_lineas,                        // post-commit (PG_verif_post), por source_event
  suma_saldo,                         // SUM(monto_recibido) FILTER (tipo='saldo')
  suma_extra,                         // SUM(monto_recibido) FILTER (tipo='extra')
  total_cobrado,                      // suma_saldo + suma_extra
  saldo_anterior,                     // saldo_real_actual + suma_saldo
  saldo_real_actual,                  // monto_total - SUM(confirmados sena+saldo)  [byte-alineado a A12]
  saldada,                            // (saldo_real_actual === 0)
  idempotent_match,                   // (resultado.idempotent_match === true)
  detalle: {
    efectivo,
    transferencia,
    subtipo_transferencia,            // null si transferencia == 0
    otros,
    recargo
  }
}
```

`suma_saldo`, `suma_extra` y `saldo_real_actual` son **autoritativos** (recomputados post-COMMIT por `PG_verif_post`, no ecos del request). En **replay idempotente**, `PG_verif_post` relee por `source_event`, de modo que `suma_saldo`/`suma_extra`/`total_cobrado` reflejan las líneas **ya** registradas y `saldo_real_actual` es el saldo vivo. `detalle` es eco de `derivar` (no es autoridad de montos).

### 4.6. Semántica de idempotencia (`PG_cobro_mp`, St1+St2)

- **St1** — `pg_advisory_xact_lock(hashtext('a10mp_cobro_saldo:' || id_reserva))`: serializa cobros concurrentes sobre la misma reserva; se libera en COMMIT/ROLLBACK.
- **St2** — orden de ramas (la idempotencia se evalúa **primero**):
  - **A) Idempotencia**: si existen líneas con ese `source_event` → compara **firma canónica** (multiset). Igual → `{ok:true, idempotent_match:true}`. Distinta → `idempotency_mismatch`.
  - **B)** Reserva inexistente → `reserva_no_existe`.
  - **C)** Estado ∉ `{confirmada, activa}` → `estado_no_cobrable` (+ `estado_reserva`).
  - **D)** `saldo_real <= 0` → `saldo_ya_cancelado` (+ `saldo_real`).
  - **E)** `suma_saldo > saldo_real` → `excede_saldo` (+ `saldo_real`). **HARD, sin escritura** (D-C-67).
  - **F)** Alta válida y nueva → registra **todas** las líneas con `abortar_si_falla(registrar_pago(...))` por línea dentro de una CTE `MATERIALIZED` → **rollback atómico** si una falla (`P0001`, D-9B-19). Devuelve `{ok:true, idempotent_match:false, cant_lineas, saldo_real_previo}`.

**Firma canónica (D-C-69)**: por línea, `jsonb_build_object('t',tipo,'m',medio_pago,'mr',to_char(monto_recibido,'FM999999999990.00'),'n',COALESCE(notas,''))`, agregada con `array_agg(... ORDER BY obj::text)` (multiset, order-independent). La firma **esperada** se deriva de `sql_payload.lineas` y la **existente** de `pagos` por `source_event`, con la **misma** normalización en SQL. Por eso un replay con misma key pero medio/traza/nota distintos da `idempotency_mismatch`, no match.

**Mapeo de errores internos → externos (render):**

| interno (SQL/wrapper) | externo (allowlist) | message |
|---|---|---|
| `reserva_no_existe` | `no_encontrado` | reserva inexistente |
| `estado_no_cobrable` | `conflicto` | la reserva no admite cobranza de saldo (estado: X) |
| `saldo_ya_cancelado` | `conflicto` | la reserva ya no tiene saldo pendiente |
| `excede_saldo` | `conflicto` | la suma aplicada a saldo excede el saldo pendiente |
| `idempotency_mismatch` | `conflicto` | idempotency_key reutilizada con datos distintos |
| (sin resultado) | `estado_incierto` | no se pudo determinar el resultado; verificá la reserva antes de reintentar |

### 4.7. Saldo y contabilidad (byte-alineado a A12)

`saldo_real = monto_total − SUM(monto_recibido)` filtrando **confirmados** con `tipo ∈ {sena, saldo}`, usando la normalización por prereserva de A12 (`reserva_por_prereserva` con `MIN` + `COALESCE(id_reserva, vía id_prereserva)`). **Nunca** `reservas.monto_saldo`. La línea `extra` (recargo) **no** entra a ese saldo ni a la base del 25%; **sí** entra a la caja percibida de A25 (`tipo ∈ {sena, saldo, extra, ajuste, reembolso}`). Ver D-C-68.

---

## 5. Evidencia de validación (TEST)

Toda la evidencia se ejecutó contra Supabase + n8n **TEST** reales, con Franco como ejecutor.

**Smoke directo (`A10MP_B4_smoke_directo.ps1`) — 40/40 PASS:**
```
SEGURIDAD (0 escrituras) ..... firma_invalida; ts viejo/futuro -> ts_fuera_de_ventana;
                               rol jenny / rol vacio -> rol_no_permitido; action incorrecta
                               -> payload_invalido; META allowlist (todo error.code en allowlist)
FUNCIONAL (escribe cobros) ... D1..D6  (efectivo / transferencia bancaria / transferencia mp /
                               otros / mixto / saldada completa)
IDEMPOTENCIA (firma canonica) A..E  (misma key+lineas -> idempotent_match; key+medio/monto/
                               traza distinto -> conflicto)
NOTAS DEL OPERADOR ........... F/G/H/I  (persistida en lineas saldo; misma key + nota distinta
                               -> conflicto)
SOBREPAGO .................... rebota excede_saldo -> conflicto, sin escritura
RESULTADO: 40 PASS / 0 FAIL
```

**Smoke gateway (`A10MP_B4_smoke_gateway.ps1`) — 13/13 PASS:** end-to-end por JWT (seguridad + spoof de control + funcional con `Assert-Code-NotIncierto` + META allowlist). `jenny → rol_no_permitido`.

**Verificación SQL (`A10MP_B4_verif.sql`) — 6/6 + contable + rollback:**
- `lineas_por_caso` (6 chequeos, todos `true`): `9910002_tiene_saldo_transf_bancaria`, `9910002_tiene_extra_recargo`, `9910003_tiene_transferencia_mp`, `9910006_otros_como_efectivo_traza`, `9910012_nota_operador_persistida`, `9910012_extra_sin_nota_operador`.
- `separacion_contable_9910002` — **PASS**: `base_a12_y_25 = 70000`, `caja_a25 = 72000`, `extra_total = 2000`, `saldo_real_A12 = 60000`. Veredicto: `extra_total > 0` **y** `caja_a25 − base = extra_total` **y** `caja_a25 > base`. Interpretación: el `extra` **no** bajó saldo (A12 ok) y **sí** es caja percibida (A25 ok).
- `rollback_test` — **PASS**: `raised=true`, `P0001`, **0 pagos** (la atomicidad de `abortar_si_falla` se cumple).

**Teardown (`A10MP_B4_teardown.sql`) — PASS, 0 residual:** gate anti-OPS (`ambiente='test'` + identidad de 5 cabañas; aborta si no), borrado FK-safe (`pagos` cobro+seña → `reservas` seed → `huesped`).

---

## 6. Diagnóstico de compatibilidad (W10 ↔ A10-MP)

- **W10 / `cobranza.registrar_saldo`** (A10) queda **deprecated-in-place**: sigue desplegado en el gateway (entrada CATALOG intacta, `webhook: portal-a10-registrar-saldo__TEST`) y **operativo**; nada se borra ni se modifica. Es de **una sola porción**.
- **`cobranza.registrar_cobro`** (A10-MP) es el **nuevo canónico multi-porción** (efectivo + transferencia bancaria/MP + otros, con recargo 5% y multi-línea atómica).
- **Conviven** sin interferencia (acciones distintas, webhooks distintos, validadores distintos). La fuente de verdad del saldo es la misma (`saldo_real` recomputado por pagos confirmados, byte-alineado a A12), así que ambos leen el mismo saldo vivo.
- **Regla de migración:** **B5 frontend usa ÚNICAMENTE `cobranza.registrar_cobro`.** No se cablea W10 desde el portal. La eventual baja física de W10 es una decisión futura explícita, fuera de este cierre.

---

## 7. Lecciones / satélites (a propagar en el cierre de propagación)

> Propuestas en este documento. La propagación formal a `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md` y `Pendiente_pre_produccion.md` queda **pendiente** (se hace en su etapa, no acá). El máximo `L-C` vigente es **L-C-23**; las lecciones nuevas tomarían el bloque libre a partir de **L-C-24** si se decide darles ID.

- **Firma canónica de líneas (multiset).** Para idempotencia de altas multi-línea, comparar el **multiset normalizado** de las líneas (no solo la key): misma key + líneas distintas debe ser `conflicto`, no match. Normalización **idéntica** en SQL para existentes y entrantes (formato de monto con `to_char`, `COALESCE(notas,'')`). → formalizado como **D-C-69**.
- **La nota del operador entra en la idempotencia.** Si un campo de texto libre (`notas`) se persiste como parte del pago, **debe** formar parte de la firma canónica, o dos cobros distintos con la misma key colisionarían como "iguales". → formalizado como **D-C-70**.
- **No crear `extra` en 0 (guard `recargo > 0`).** `registrar_pago` exige `monto_esperado > 0` (`chk_pagos_monto_esperado`); una transferencia tan chica que redondea el recargo a 0 **no** debe generar línea `extra` (rompería el cobro). *(Lección, sin ID propio.)*
- **Fixtures de reservas `confirmada` deben evitar solapamientos.** `reservas` tiene `EXCLUDE USING gist (id_cabana =, daterange(checkin,checkout,'[)') &&) WHERE estado IN ('confirmada','activa')`. Los setups que insertan varias reservas confirmadas/activas deben **escalonar fechas** (rango único por fixture) o el `INSERT` rebota. *(Lección, sin ID propio.)*
- **El SQL Editor de Supabase muestra solo el último `SELECT`.** Para que un script de verificación deje veredicto legible, conviene **consolidar todos los veredictos en un único result set** (o asumir que solo se ve el último). El `verif` de A10-MP separa secciones; al correrlo, leer cada `SELECT` o consolidar. *(Lección, sin ID propio.)*
- **Pendiente cosmético de propagación.** Si se propaga/edita el artefacto del gateway A10-MP, corregir los comentarios que citan `D-C-61…64` por la numeración oficial `D-C-64…70` (ver nota en §3). **No** afecta runtime; **no** urge.

---

## 8. Instrucciones para B5 frontend (A10 `cobranza.registrar_cobro`)

- **Endpoint único:** usar **solo `cobranza.registrar_cobro`** (no W10 / `cobranza.registrar_saldo`).
- **Multi-porción:** permitir cargar efectivo, transferencia (con subtipo `bancaria`/`mp`) y "otros" en el mismo submit. Si "otros" > 0, **exigir** `origen_otros` (1..120) y `descripcion_otros` (1..200); si "otros" = 0, **no** enviarlos.
- **Recargo 5%:** calcular y **mostrar** el recargo del 5% sobre la **porción de transferencia** (display informativo; el backend lo recalcula y lo registra como línea `extra` separada). Tener en cuenta que una transferencia que redondea el recargo a 0 no genera `extra`.
- **Anti-sobrepago en UI:** **bloquear el submit** si `suma_saldo` (efectivo + transferencia + otros) supera el `saldo_real_actual` conocido, **antes** de enviar. El backend igual rebota `conflicto` (HARD), pero la UI debe prevenirlo.
- **Idempotencia:** mantener un `idempotency_key` (8..64 `[A-Za-z0-9_-]`) **por submit**, reutilizándolo en los **retry** del mismo submit (mismas líneas → `idempotent_match:true`). Cambiar líneas/medio/monto/nota con la misma key da `conflicto`: en ese caso es un **submit nuevo** y corresponde **key nueva**.
- **`estado_incierto` sin retry ciego:** ante `estado_incierto`, **no** reintentar automáticamente; pedir verificación de la reserva (el saldo/los cobros pueden haberse aplicado). Si se reintenta, debe ser con la **misma** key (la idempotencia protege).
- **Mostrar del `response.data`:** `suma_saldo`, `suma_extra`, `total_cobrado`, `saldo_real_actual`, `saldada` (bool), `idempotent_match` (bool) y `detalle` (`efectivo`, `transferencia`, `subtipo_transferencia`, `otros`, `recargo`). Útiles también `saldo_anterior` y `cant_lineas`.

---

*Cierre A10-MP — etapa solo-documental. Contrato transcrito del código real (gateway `A10MP_B2`, corazón `A10MP_B3`, wrapper `portal-a10mp-registrar-cobro__TEMPLATE.json`, smokes/verif B4). No se modificó runtime, gateway, wrapper, OPS, canónico ni W10. Numeración oficial de decisiones: D-C-64…70. Con este cierre escrito y aprobado, B5 frontend queda habilitado para arrancar.*
