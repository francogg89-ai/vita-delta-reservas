# CARRIL C — SLICE 3a (LECTURAS NUEVAS) — CIERRE

**Estado:** ✅ **Cerrado y verificado en TEST.** Slice 3a sumó las **dos primeras lecturas nuevas** del Portal Operativo Interno (las de Slice 1 eran *reuse* de funciones existentes): **A24** (`historico.reservas`, buscador operativo de reservas) y **A25** (`ingresos.cobrados_periodo`, caja percibida por período). Las dos las sirve `portal-api` vía **wrappers n8n firmados** que revalidan en cinco dimensiones (HMAC · ts · rol · action · ambiente), son **`SELECT` inline** (sin funciones nuevas, sin DDL, sin tocar el canónico) y **NO inyectan actor ni son `isWrite`** (lecturas puras).

**Entorno de validación:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5, marcador `configuracion_general.ambiente='test'`.
**Entorno de operación:** — (Slice 3a **no** se promovió a OPS; el Carril C no toca OPS para experimentar).
**Fecha de cierre:** 2026-06-20.
**Base:** `C_SLICE0_CIERRE.md` (espina de seguridad; D-C-29…35) + `C_SLICE1_CIERRE.md` (molde de wrapper + lecturas reuse) + `C_SLICE2_CIERRE.md` (gateway con escrituras; D-C-39/41, allowlist doble + action binding) + `C_SLICE3A_A24_DIRECTO_CIERRE.md` / `C_SLICE3A_A24_GW_CIERRE.md` / `C_SLICE3A_A25_DIRECTO_CIERRE.md` (mini-cierres de los bloques).
**Depende de:** D-C-29…35 (HMAC/JWT/allowlist/ambiente), D-C-39/41 (allowlist doble + action binding), D-C-43/47 (contrato JSON, lista vacía → `ok:true`), **D-C-49 / L-C-14** (CTE `reserva_por_prereserva` desde `reservas`, byte-alineada a A12), **D-C-11/20** (A24: floor inferior duro 2026-07-01, gateway recorta), **D-C-27** (A25: sin societario), **D-9G-03** (caja percibida = `sena`+`saldo` confirmados, mes de `created_at`), **D-NEG-02** (inicio contable 2026-07-01), L-C-05 (HMAC sobre raw body binario), L-C-10/11 (placeholder de secreto por prefijo; TDZ del validador antes del CATALOG), L-C-16 (`$1::jsonb` casteo del queryReplacement), L-C-17 (cuarteto PowerShell 5.1).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.8.1` — **NO modificado por este cierre.** A24/A25 son `SELECT` inline; **no** introducen DDL ni funciones nuevas. `portal_usuarios` sigue siendo infra **TEST-only**, no promovida a OPS.
**Autores:** Franco (titular, ejecutor de **todos** los imports/deploys/smokes en Supabase y n8n) + Claude (arquitecto/copiloto; estrictamente advisory — no tocó infraestructura).
**Decisiones registradas:** D-C-52, D-C-53, D-C-54 🔒. **Lecciones:** L-C-18, L-C-19.

---

## 1. Resumen ejecutivo

Slice 1 puso lecturas que **reusaban** funciones del motor; Slice 3a dio el siguiente paso: **dos lecturas nuevas, escritas como `SELECT` inline** sobre la frontera de confianza, sin reabrir nada del Carril B ni del canónico. Ambas son del mismo molde de seguridad de la Fase C (`portal-a12-saldos`), con la diferencia de que **no llevan `injectActor` ni `isWrite`** (son lecturas).

**A24 `historico.reservas`** es un **buscador operativo de reservas** con floor inferior duro `2026-07-01` (D-C-11/20): el gateway recorta `fecha_desde < floor → floor` (no rechaza) y el SQL lo impone además con `GREATEST`. Devuelve filas paginadas con `saldo_real` recomputado por la **CTE byte-alineada a A12** (D-C-49) — que sale de `reservas.id_pre_reserva` para no perder señas asociadas solo a pre-reserva. Es buscador, no histórico contable: incluye futuras (`fecha_hasta` default `null`), no se usa para liquidación ni Carril B, no reemplaza el calendario A04.

**A25 `ingresos.cobrados_periodo`** es **caja percibida por período**: `total_cobrado` = solo `sena`+`saldo` confirmados (D-9G-03), bucket por mes de `created_at`. Suma **sobre `pagos`** (incluye el residuo conocido de 9A), con `cabana` por LEFT JOIN. Los movimientos `extra`/`ajuste`/`reembolso` van en un bloque **`otros_movimientos` informativo, jamás sumado** al headline (D-C-27: sin societario, sin neto, sin cascada). La regla de `periodo_hasta` es **híbrida** (D-C-54): omitido → hoy sin check de inversión (con el floor en el futuro, hoy el default da vacío con `ok:true`); explícito → debe ser válido y `>= periodo_desde` tras el clamp.

La validación fue **empírica y por capa**: cada wrapper con su batería directa (seguridad + funcional + payload) y cada cableado con su batería vía gateway por JWT, **cruzando los agregados contra el snapshot read-only S8/S9 al centavo**. Metodología estricta respetada: snapshot read-only → blueprint aprobado en chat → diff mínimo → Franco ejecuta/deploya → verificación. **OPS y `6B_SCHEMA_SQL.md` intactos.**

---

## 2. Qué quedó construido en TEST

El gateway `portal-api` quedó con **11 entradas** en el CATALOG: 1 resuelta en la Edge (`sesion.contexto`, A02) + **7 lecturas n8n** (5 de Slice 1 + **A24/A25** de este slice) + 3 escrituras n8n (Slice 2). Las dos lecturas nuevas **no** llevan `injectActor` ni `isWrite`.

### 2.1 A24 `historico.reservas` — buscador operativo de reservas
- Roles {vicky, socio}; **jenny excluida** (D-C-39, expone montos/saldo). Wrapper `portal-a24-historico-reservas`. **Lectura `SELECT` inline.** Filtros opcionales (reject-unknown): `fecha_desde` (clamp al floor), `fecha_hasta` (default `null` = sin cota), `id_cabana` (entero>0 o ausente/null = todas, **sin sentinela externa**), `estado` (enum o null = todos), `texto` (ILIKE nombre/apellido/teléfono/email), `limit` (1–200, default 50), `offset`. Contrato `data:{ filas[], limit, offset, total }`; `filas` incluye `id_cabana` **y** `cabana`, montos numéricos, `saldo_real` por CTE (puede ser negativo). Privacidad (D-C-03): nombre/teléfono/email; sin `dni` ni `notas_internas`. `total` = universo filtrado vía `COUNT(*) OVER()`.

### 2.2 A25 `ingresos.cobrados_periodo` — caja percibida por período
- Roles {vicky, socio}; **sin societario** (D-C-27). Wrapper `portal-a25-ingresos`. **Lectura `SELECT` inline.** `total_cobrado` = solo `sena`+`saldo` confirmados; `otros_movimientos` (extra/ajuste/reembolso) informativo, no sumado. Suma sobre `pagos` (incluye residuo); `cabana` por LEFT JOIN (null en residuo). Contrato `data:{ periodo_desde, periodo_hasta, total_cobrado, total, por_tipo[], por_medio[], por_mes[], otros_movimientos:{por_tipo[]}, filas[], limit, offset }`. `filas` paginada (los agregados son del universo completo). Payload: `periodo_desde` (clamp al floor), `periodo_hasta` (híbrido, D-C-54), `limit`/`offset`. Bucket por mes de `created_at` (criterio Carril B vigente, sin conversión de zona).

---

## 3. Acciones ejecutadas (bitácora)

| Acción | Wrapper | Tipo | injectActor / isWrite | Estado |
|---|---|---|:---:|---|
| **A24** `historico.reservas` | `portal-a24-historico-reservas` | lectura (SELECT inline) | — / — | cerrado (directo 26/26 + gateway 23/23) |
| **A25** `ingresos.cobrados_periodo` | `portal-a25-ingresos` | lectura (SELECT inline) | — / — | cerrado (directo 26/26 + gateway 24/24) |

---

## 4. Decisiones registradas (D-C-52, D-C-53, D-C-54) 🔒

> Introducidas/aplicadas en este slice; este cierre las **promueve** a `DECISIONES_NO_REABRIR.md`.

- **D-C-52 — A24 `historico.reservas` = buscador operativo de reservas.** Floor inferior **duro** `2026-07-01` (D-C-11/20): el gateway recorta `fecha_desde < floor → floor` (no rechaza) y el SQL lo impone además con `GREATEST(DATE '2026-07-01', …)`. `fecha_hasta` default **`null` = sin cota superior** → incluye reservas futuras. Documentado explícitamente: **no** se usa para liquidación ni Carril B, **no** reemplaza el calendario operativo A04. `id_cabana`/`estado` ausentes o `null` = todas/todos, **sin sentinela `0` externa** (el SQL maneja `NULL` directo). Devuelve **`id_cabana` además de `cabana`**. `saldo_real` recomputado por la CTE de A12 (D-C-49) y **puede ser negativo** (sobrecobro): se reporta tal cual. `total` = universo filtrado vía `COUNT(*) OVER()` (caveat: `offset` más allá del universo devuelve `total=0`).
- **D-C-53 — A25 `ingresos.cobrados_periodo` = caja percibida.** `total_cobrado` = **solo `sena`+`saldo` confirmados** (D-9G-03). `otros_movimientos` (`extra`/`ajuste`/`reembolso`, mismo período+floor, confirmados) es **informativo**: no suma, no resta, no neto, no resultado, no cascada, no matriz, no reabre Carril B (D-C-27). **Suma sobre `pagos`** (no sobre reservas) → **incluye el residuo** (pago cuya pre-reserva nunca convirtió), que aparece con `id_reserva`/`cabana` `null` (LEFT JOIN). Bucket por **mes de `created_at`** (criterio Carril B vigente, sin conversión de zona — sin `AT TIME ZONE`). **`filas` paginada** (`limit`/`offset`): los agregados (`total_cobrado`, `por_tipo`, `por_medio`, `por_mes`) son del **universo completo**; `filas` trae solo la página; el cuadre `Σ filas = total_cobrado` aplica **solo con página completa**, mientras `Σ por_medio = Σ por_tipo = total_cobrado` vale **siempre**. Sumas en **centavos** (sin float drift).
- **D-C-54 — A25 `periodo_hasta` híbrido + preservación de ausencia en el gateway.** Floor `2026-07-01` (D-NEG-02) clampea `periodo_desde`. `periodo_hasta`: **omitido → hoy (`CURRENT_DATE`), SIN check de inversión** (con el floor en el futuro, `periodo_desde > periodo_hasta` → la query devuelve **vacío con `ok:true`**, totales 0); **explícito → YMD válido y, tras el clamp, `>= periodo_desde`**, sino `payload_invalido` (incluido `null`/no-string/mal formado/invertido). En el gateway, `payloadIngresosPeriodo` **preserva la ausencia real de `periodo_hasta`**: si el cliente la omite, el `value` firmado **NO incluye la clave** (el wrapper directo aplica el default "hoy"), para **no cambiar la semántica entre gateway y directo**. `periodo_hasta` es inclusivo (half-open `+1 día` en el SQL).

---

## 5. Lecciones registradas (L-C-18, L-C-19)

- **L-C-18 — `payload` no-objeto se rechaza, no se coerciona (C1).** En los validadores de lectura con payload (gateway *y* wrapper): `payload` ausente/`null` → `{}` (OK, todos los filtros default); objeto plano → se usa; **cualquier otro tipo (string, array, número, bool) → `payload_invalido`**. La coerción silenciosa a `{}` enmascararía un cliente roto (un `payload` mal serializado se trataría como "sin filtros"). Validado por P6a/P6b (directo y gateway) en A24 y A25.
- **L-C-19 — IDs `BIGINT` a número en el contrato (C2).** El driver Postgres entrega `BIGINT` como **string** (para no perder precisión). Como los IDs del dominio (`id_reserva`, `id_cabana`, `id_pago`) están muy por debajo de 2^53, el `render` los normaliza a número con `int0()` para que el contrato no derive en strings. Aplicado en A24 (`id_reserva`/`id_cabana`) y A25 (`id_pago`/`id_reserva`).

---

## 6. Evidencia (smokes en TEST)

### 6.1 A24 `historico.reservas`
- **Directo** (`C_SLICE3A_A24_smoke_directo.ps1`): **26/26 PASS** — 8 seguridad + 10 funcionales + 7 payload + META. Cruce: sin filtros `total=7`/`filas=7` (universo floored = 7 reservas desde julio; las 6 de junio quedan bajo el floor); F3 recorta a floor aún pasando `fecha_desde=2026-06-01`.
- **Gateway** (`C_SLICE3A_A24_GW_smoke.ps1`, JWT): **23/23 PASS** — 5 seguridad + 10 funcionales + 7 payload + META. jenny → `rol_no_permitido` en el gateway (antes de firmar); sin JWT → `no_autorizado`.

### 6.2 A25 `ingresos.cobrados_periodo`
- **Directo** (`C_SLICE3A_A25_smoke_directo.ps1`): **26/26 PASS** — 8 seguridad + 10 funcionales + 7 payload + META.
- **Gateway** (`C_SLICE3A_A25_GW_smoke.ps1`, JWT): **24/24 PASS** — 5 seguridad + 10 funcionales + 8 payload + META.
- Cruce con S8/S9 (período `[2026-07-01, 2026-12-31]`, **idéntico al centavo** en directo y gateway): `total_cobrado=921200` (solo `sena`+`saldo`), `total=4`; `por_mes` julio 670200 / noviembre 251000; `por_medio` efectivo 300200 / transferencia_bancaria 621000; `otros_movimientos` extra 8500 (separado, no sumado); **cuadre** `Σ por_medio = Σ por_tipo = Σ filas = total_cobrado` (con `limit=200`).
- **Regresiones del híbrido (gateway):** default `{}` → vacío `ok:true` (floor futuro) **y** `periodo_hasta` omitido **preservado** (si el gateway lo rellenara, daría `payload_invalido`); rango explícitamente invertido → `payload_invalido`; `periodo_hasta` null explícito → `payload_invalido`.

En las dos acciones (directo y gateway): único conjunto de códigos de error visto = el del molde de seguridad + `payload_invalido`, **todos dentro de la allowlist**.

---

## 7. Supuestos y límites del slice

- Slice 3a = **lecturas nuevas** (A24/A25). Gastos (Slice 3b: A11 `cargar.gasto_interno` / A13 `gastos.listado`) y la contabilidad societaria (A14–A18) quedan **fuera**.
- **No promovido a OPS.** Toda la validación fue en TEST.
- **A24/A25 son `SELECT` inline:** sin funciones nuevas, sin DDL, canónico intacto. `saldo_real` (A24) y la atribución de pagos (A25) usan la CTE de A12 (D-C-49).
- **`total` de A24** vía `COUNT(*) OVER()`: exacto en uso normal; con `offset` más allá del universo devuelve `total=0` (caveat documentado).
- **A25 fetchea todas las filas del período** para los agregados y pagina `filas` en memoria; aceptable para un complejo de 5 cabañas con período acotado por el floor.
- **Datos de TEST con `created_at` futuro** (julio/noviembre 2026): por eso hoy (2026-06-20) el default `{}` de A25 da vacío y el smoke usa `periodo_hasta=2026-12-31` para los casos con datos.

---

## 8. Pendientes y handoff

- **→ Slice 3b** (gastos): A11 `cargar.gasto_interno` (escritura) + A13 `gastos.listado` (lectura). **A11 es la primera escritura candidata a no-idempotente sin guard → ahí entra el store de `nonce` (P-C-9).**
- **Hardening pre-OPS** (sigue abierto, P-C-7…11): CORS al origin del portal; `VITA_HMAC_SECRET` de OPS distinto del de TEST; store de nonce persistente; rol Postgres dedicado de mínimos; migrar `portal-api` a CLI + `config.toml` si los redeploys se vuelven frecuentes.
- **Contabilidad societaria A14–A18** (post-MVP, solo rol socio) y escrituras A19–A23: fuera de alcance del Carril C MVP.
- **Frentes paralelos** (Mercado Pago MP-02+, Marketing): no se cruzan con este cierre.

---

## 9. Deltas para documentos satélite (aplicar tras auditar este cierre)

**EOL por archivo** (verificar contra los archivos reales antes de pegar):

- **`DECISIONES_NO_REABRIR.md`** (LF) — agregar subsección **"## Carril C — Slice 3a (lecturas nuevas) — cerrada 2026-06-20"** con **D-C-52 / D-C-53 / D-C-54**, **después** de D-C-51 y **antes** de la sección de lecciones n8n consolidadas.
- **`Lecciones_Aprendidas.md`** (bloque L-C en **CRLF**) — agregar **L-C-18 / L-C-19** después de L-C-17, EOL **CRLF**.
- **`ESTADO_ACTUAL_VITA_DELTA.md`** (CRLF) — nuevo bloque **"Etapa actual: Slice 3a (lecturas nuevas) — cerrada 2026-06-20"**; el bloque de **Slice 2** baja de "Etapa actual" a "Etapa previa". CATALOG pasa de 9 a **11** entradas (1 edge + 7 lecturas + 3 escrituras).
- **`CLAUDE.md`** (LF) — entrada de cierre de **Slice 3a** después de la de Slice 2, mismo formato.
- **`Pendiente_pre_produccion.md`** — **sin cambios** (P-C-1…11 siguen abiertos; A24/A25 son lecturas → no resuelven ni agregan ninguno; P-C-9 sigue diferido a A11).
- **`6B_SCHEMA_SQL.md`** y **OPS** — **sin cambios** (Carril C no toca el canónico; A24/A25 son `SELECT` inline).
- **Commit:** `C_SLICE3A_A25_portal-api_index.ts` (gateway final del slice: A24 + A25 + todo lo previo) + los wrappers/smokes/runsheets de A24 y A25, sanitizados.

---

## 10. Inventario de artefactos de la etapa

- **Snapshot:** `C_SLICE3A_SNAPSHOT_READONLY.sql` (S0–S12, gated anti-OPS).
- **A24:** wrapper `portal-a24-historico-reservas__TEMPLATE.json` + smokes `C_SLICE3A_A24_smoke_directo.ps1` / `C_SLICE3A_A24_GW_smoke.ps1` + runsheets `C_SLICE3A_A24_RUNSHEET.md` / `C_SLICE3A_A24_GW_RUNSHEET.md` + mini-cierres `C_SLICE3A_A24_DIRECTO_CIERRE.md` / `C_SLICE3A_A24_GW_CIERRE.md`.
- **A25:** wrapper `portal-a25-ingresos__TEMPLATE.json` + smokes `C_SLICE3A_A25_smoke_directo.ps1` / `C_SLICE3A_A25_GW_smoke.ps1` + runsheets `C_SLICE3A_A25_RUNSHEET.md` / `C_SLICE3A_A25_GW_RUNSHEET.md` + mini-cierre `C_SLICE3A_A25_DIRECTO_CIERRE.md`.
- **Gateway final del slice:** `C_SLICE3A_A25_portal-api_index.ts` (CATALOG 11 entradas).
- **Cierre:** este documento (`C_SLICE3A_CIERRE.md`).
