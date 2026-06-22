# CARRIL C — SLICE 3b — A13 `gastos.listado` (WRAPPER DIRECTO) — CIERRE

**Estado:** ✅ **Wrapper directo APROBADO en TEST.** A13 es la **segunda acción de lectura** del Portal Operativo Interno (después de A24/A25 en Slice 3a) y la **lectura companion de A11**: lista los **gastos internos** (`gastos_internos`) de un período contable, con filtros opcionales y agregados, detrás de un wrapper n8n firmado. Validado end-to-end por el **camino wrapper-directo** (seguridad + funcional + cruce al centavo contra ground-truth) contra n8n + Supabase TEST reales. La extensión del **gateway** queda explícitamente pendiente (ver §7).

**Entorno de validación:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5, marcador `configuracion_general.ambiente='test'`.
**Entorno de operación:** — (A13 **no** se promovió a OPS; el Carril C **no** toca OPS para experimentar).
**Fecha de cierre:** 2026-06-22.
**Base:** `C_SLICE3A_CIERRE.md` (lecturas A24/A25, **molde de wrapper de lectura**, D-C-52…54, L-C-18/19) + `C_SLICE3B_A11_DIRECTO_CIERRE.md` (escritura companion sobre `gastos_internos`, D-C-55/56, L-C-20) + `C_SLICE3B_SNAPSHOT_A11_A13.sql` (snapshot anti-OPS de `gastos_internos`, validado limpio antes del diseño).
**Depende de:** D-C-39/41 (allowlist de rol + action binding) · D-C-43/47 (contrato JSON `{ok,data|error}`) · D-C-03 (jenny sin contenido económico) · **D-NEG-02** (inicio contable 2026-07-01 = floor duro) · L-C-05 (HMAC sobre los bytes del raw body binario) · L-C-10 (placeholder de secreto por prefijo `__PEGAR_`, Modo B) · L-C-16 (`($1::jsonb)` casteo del `queryReplacement` que llega como texto) · L-C-17 (cuarteto PowerShell 5.1) · L-C-18 (payload no-objeto **rechazado**, no coercionado a `{}`) · L-C-19 (IDs BIGINT → número en el contrato) · L-8D-01 (leer `item.resultado` del Postgres node) · **D-C-58, D-C-59** (este documento).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.8.1` — **NO modificado por este cierre.** A13 es **lectura pura**: cero DDL, cero columnas, cero funciones nuevas. `gastos_internos` se consulta tal cual (17 columnas, 18 constraints, índice `idx_gastos_internos_periodo_clase`), con joins de solo-lectura a `socios`/`zonas`/`cabanas` para los nombres.
**Autores:** Franco (titular, ejecutor de **todos** los imports/deploys/smokes/SQL en Supabase y n8n) + Claude (arquitecto/copiloto; estrictamente advisory — no tocó infraestructura).
**Decisiones registradas:** D-C-58, D-C-59 🔒. **Lecciones:** L-C-22 📝. *(Propuestas en este documento hasta la propagación formal a satélites — §8.)*

---

## 1. Alcance

A13 = **lectura** de gastos internos por período contable, vía el Portal Operativo Interno, detrás de un wrapper n8n firmado. Patrón de Slice 3a (SQL devuelve el universo filtrado completo sin LIMIT; el render agrega en centavos y pagina).

**Contrato de la acción** (`action = 'gastos.listado'`):
- **Webhook:** `portal-a13-gastos-listado` — **sin sufijo `__TEST`** (convención de **lecturas** A12/A24/A25; las escrituras A07/A08/A11 sí llevan `__TEST`). **D0.**
- **Roles:** `vicky`, `socio` (sin `jenny`, D-C-03 — contenido económico).
- **Eje de filtro:** `periodo` **contable** (día 1), NO `fecha` de pago. **Q2.**
- **Período (REJECT-UNKNOWN, todos opcionales):** `periodo_desde?` / `periodo_hasta?` (YYYY-MM-DD). Floor duro `2026-07-01` (D-NEG-02) **clampea** `periodo_desde` (clamp, no reject; el SQL además lo impone con `GREATEST`). Ambos bordes se **truncan a primer día de mes** (D-C-59): un borde a mitad de mes **incluye el mes completo**. `periodo_hasta` **híbrido**: omitido → mes actual (primer día del mes de hoy), **sin** check de inversión; explícito → YMD válido y, truncado y tras el clamp, `>= periodo_desde`, sino `payload_invalido`.
- **Filtros opcionales (ausente/null = sin filtro, sin sentinela):** `clase` ∈ `{A,C,D,E}` · `id_zona` / `id_cabana` (entero seguro > 0) · `pagador_tipo` ∈ `{socio,caja}` · `q` (string `trim`, 1..120, ILIKE sobre `etiqueta` + `comentario`, sin escape de `%`/`_` en MVP, **parametrizado vía `$1::jsonb` — sin interpolación insegura**). **Q4 / D3.**
- **Paginación:** `limit` default 50 / cap 200 · `offset` default 0. **Q7.**
- **Salida:** `{ ok:true, data:{ periodo_desde, periodo_hasta, total_gastos, por_clase, filas, limit, offset } }`. Universo vacío → `total_gastos:0, por_clase:[], filas:[], ok:true` (no error).
- **Agregados sobre el universo FILTRADO COMPLETO (no solo la página):** `total_gastos = SUM(monto)` (sumado en **centavos**, sin float drift) · `por_clase = [{ clase, monto, n }]` (D2). **Q5.**
- **Columnas por fila (20, lockeadas):** `id_gasto, periodo, fecha, clase, clase_sugerida, etiqueta, monto, moneda, pagador_tipo, id_socio_pagador, socio_pagador_nombre, id_zona, zona, id_cabana, cabana, medio_pago, comentario, comprobante_url, creado_por, created_at`. IDs BIGINT → número (L-C-19); opcionales null-safe. `socio_pagador_nombre`/`zona`/`cabana` por LEFT JOIN. **Microajuste:** `moneda` (ARS por default) se expone junto a `monto` — no se muestran montos sin moneda.
- **Default con floor futuro:** hoy (junio 2026) < floor (2026-07-01) → el `{}` por defecto devuelve **vacío `ok:true`** (idéntico a A25). El smoke usa períodos explícitos para ver datos. **D4.**

**Fuera de alcance de este cierre:** la extensión del gateway `portal-api` (§7), el cierre formal de Slice 3b, y cualquier toque a A11, OPS o al canónico (§8).

---

## 2. Artefactos finales

**Wrapper directo** (importado y activo en n8n TEST; **sanitizado** para el repo — secreto → `__PEGAR_SECRETO_O_USAR_VARIABLE__`, sin `webhookId`, `active:false`, `pinData:{}`):
- `portal-a13-gastos-listado__TEMPLATE.json` — **8 nodos**, clonado **byte-fiel** del molde de lectura A25: `Webhook(2.1, rawBody) → validar_firma_ts_rol → leer_ambiente → verificar_acceso → IF acceso → PG: leer gastos → Code: render envelope → Respond`. `validar_firma_ts_rol` recomputa el HMAC sobre el raw body (Modo B, assert por prefijo `__PEGAR_`), valida `ts` (±300 s) / `rol` (allowlist) / action binding (`gastos.listado`) y normaliza el payload A13 (reject-unknown, truncado a mes, floor, filtros, límite/offset) en `payload_norm`. `PG: leer gastos` ejecuta el SELECT con `options.queryReplacement = JSON.stringify($('validar_firma_ts_rol').first().json.payload_norm)` → `$1`, leído con el patrón tipado `($1::jsonb->>'campo')`. `Code: render envelope` arma `total_gastos`/`por_clase` en centavos sobre el universo y pagina `filas` con `.slice(offset, offset+limit)`.
  - **SQL** (`PG: leer gastos`): `SELECT … FROM gastos_internos g LEFT JOIN socios s LEFT JOIN zonas z LEFT JOIN cabanas c WHERE g.periodo >= GREATEST(DATE '2026-07-01', ($1::jsonb->>'periodo_desde')::date) AND g.periodo <= ($1::jsonb->>'periodo_hasta')::date AND (<guards null=sin filtro para clase/id_zona/id_cabana/pagador_tipo/q ILIKE>) ORDER BY g.periodo, g.id_gasto;` — **sin LIMIT** (pagina el render). Validado con pglast: **1 `SelectStmt`**.

**Ground-truth read-only + smoke (PowerShell ASCII-puro / SQL, sanitizados):**
- `C_SLICE3B_A13_smoke_expected.sql` — SELECT read-only (gate anti-OPS + `E2 total_gastos` + `E3 por_clase` + particiones por clase/pagador + distribución por mes + chequeo de floor), **replicando exacto el WHERE del wrapper** (floor `GREATEST`, período inclusivo, bordes ya a primer día de mes) para la ventana canónica `[2026-07-01 .. 2099-12-01]`. Validado: **1 `SelectStmt`, sin DML/DDL**. Produce el ground-truth para el cruce al centavo.
- `C_SLICE3B_A13_smoke_directo.ps1` — smoke HMAC directo. **32 asserts base** (34 con los dos opcionales `G0a/G0b` cuando se cargan `$EXP_NFILAS`/`$EXP_TOTAL` del expected): seguridad (8), funcionales (G1 cuadre · G2 enum/conteo · G3 default vacío · G4 clamp · **G5 partición por clase A+C+D+E == universo** · **G6 partición por pagador socio+caja == universo** · G7 monotonía · G8 q sin match · G9/G10 paginación), payload inválido (P1…P11b, incluye los filtros nuevos `clase`/`pagador_tipo`/`id_zona`/`id_cabana`/`q`), META allowlist. HMAC en PS espejado de A25; cuarteto L-C-17 respetado. **Lectura → SIN teardown y SIN gate de write-residual** (nada que limpiar).

---

## 3. Evidencia (TEST)

Corrida real contra `https://federicosecchi.app.n8n.cloud/webhook/portal-a13-gastos-listado` + Supabase TEST.

**Ground-truth** (`C_SLICE3B_A13_smoke_expected.sql`, ventana `[2026-07-01 .. 2099-12-01]`):
```
VEREDICTO ...................................... OK (FALLO=0 ATENCION=0)
E1 n_filas (universo) ......................... 5
E2 total_gastos ............................... 335000.00
E3 por_clase .................................. A=40000.00(1), C=25000.00(1), D=30000.00(1), E=240000.00(2)
E4 por_pagador ................................ socio=265000.00(3), caja=70000.00(2)   -> sum == total (OK)
E4 sum(por_clase) == total_gastos ............. OK
E5 por_mes .................................... 2026-07=3(125000.00), 2026-08=1(180000.00), 2026-11=1(30000.00)
E6 periodo < floor (excluidos) ................ 0
E7 muestra (id|mes|clase|monto|moneda|pagador|socio|zona|cab):
   30|2026-07|A|40000|ARS|caja|-|-|-     31|2026-07|C|25000|ARS|socio|1|-|-
   34|2026-07|E|60000|ARS|socio|2|-|5    33|2026-08|E|180000|ARS|socio|2|-|4
   32|2026-11|D|30000|ARS|caja|-|2|-
```

**Smoke directo** (`C_SLICE3B_A13_smoke_directo.ps1`):
```
RESULTADO: 32 PASS / 0 FAIL
  SEGURIDAD (8) ............... vicky/socio OK (default {} vacío); jenny/intruso -> rol_no_permitido;
    firma_invalida; ts_fuera_de_ventana; ambiente_incorrecto (ops); accion_desconocida.
  FUNCIONALES (10):
    rFull (periodo_hasta=2099-12-01, limit 200) -> total_gastos=335000, filas=5,
      por_clase A:40000(1) C:25000(1) E:240000(2) D:30000(1)
    G1 cuadre por_clase == total_gastos == filas .. PASS
    G2 por_clase en {A,C,D,E} y n cuadra ........... PASS
    G3 default vacío (total=0, por_clase vacío, filas=[]) PASS
    G4 periodo_desde<floor recortado (== universo) . PASS
    G5 partición por clase A+C+D+E == universo ...... PASS
    G6 partición por pagador socio+caja == universo . PASS
    G7 monotonía clase=A <= universo ............... PASS
    G8 q sin match -> vacío ........................ PASS
    G9 limit=1 (<=1 fila, total==universo, limit=1) . PASS
    G10 limit=2 offset=2 (página distinta) ......... PASS
  PAYLOAD INVALIDO (13) ....... P1 clave; P2/P4 YMD; P3 inversión (nivel mes); P5 limit;
    P6 clase; P7 pagador_tipo; P8 id_zona=0; P8b id_cabana no-int; P9 q vacío; P10 q>120;
    P11a/b payload string/array -> todos payload_invalido.
  META allowlist .............. PASS
  Códigos de error vistos ..... accion_desconocida, ambiente_incorrecto, firma_invalida,
    payload_invalido, rol_no_permitido, ts_fuera_de_ventana.
```

**Cruce AL CENTAVO (lo central):** la salida del wrapper para el universo (`total_gastos=335000.00`, `por_clase` A=40000(1)/C=25000(1)/D=30000(1)/E=240000(2)`, `filas=5`) coincide **exactamente** con `E1/E2/E3` del expected. Las particiones del PS1 (independientes de los datos) cierran contra el universo: `A+C+D+E == socio+caja == 335000`. **Cero `error_interno`, cero `estado_incierto`** en todos los caminos.

---

## 4. Notas de construcción / propiedades validadas

1. **Molde A25 clonado byte-fiel.** El wrapper se construyó clonando `portal-a25-ingresos__TEMPLATE.json` nodo por nodo (mismo andamiaje HMAC/ts/rol/ambiente, mismos `typeVersion`), regenerando los `id` de nodo (las conexiones referencian por **nombre**, no por id) y swappeando solo: webhook path, `EXPECTED_ACTION`, normalización de payload, SQL (renombre `PG: leer ingresos` → `PG: leer gastos` con sus conexiones) y render. 0 referencias residuales a `ingresos`.
2. **Truncado a primer día de mes (D-C-59).** Como el eje es `periodo` (día 1), el validador trunca `periodo_desde`/`periodo_hasta` a `YYYY-MM-01` **antes** del clamp y de la comparación. Sin esto, un `periodo_desde='2026-07-15'` excluiría julio (cuyo `periodo` es día 1). El check de inversión explícita opera a **nivel mes** (P3: `desde=2026-08-15`, `hasta=2026-07-20` → `08 > 07` → `payload_invalido`), lo que de paso valida que la truncación ocurre antes del check.
3. **Agregados en centavos sobre el universo.** El SQL devuelve el universo filtrado completo (sin LIMIT); el render suma en centavos (`Math.round(n*100)`, divide por 100) y pagina `filas`. G9 prueba que `limit=1` **no** altera `total_gastos` (sigue siendo el del universo): los agregados son del universo, las `filas` de la página.
4. **Particiones data-independent como prueba de los filtros.** En vez de depender de números fijos del fixture, el smoke valida los filtros por **partición sobre enums cerrados**: `sum(total|clase∈{A,C,D,E}) == total(full)` y `sum(total|pagador∈{socio,caja}) == total(full)`. Como toda fila tiene `clase ∈ {A,C,D,E}` y `pagador_tipo ∈ {socio,caja}` (constraints), la partición debe cuadrar exacto sea cual sea el dato — robusto ante cambios del fixture. El cruce al centavo de los **valores** queda contra el expected (§3).
5. **`q` parametrizado, sin inyección.** El ILIKE concatena `'%'||($1::jsonb->>'q')||'%'` sobre un **parámetro bindeado** (`queryReplacement` pasa `JSON.stringify(payload_norm)` como `$1`, no se interpola texto del usuario en la query). En MVP `%`/`_` actúan como comodín (aceptado).

---

## 5. Decisiones y lecciones nuevas

**🔒 D-C-58 — Contrato de A13 `gastos.listado` (lectura).**
Acción de lectura de `gastos_internos` por **período contable**, patrón Slice 3a (universo filtrado en SQL, agregados+paginación en el render). Webhook `portal-a13-gastos-listado` **sin `__TEST`** (convención de lecturas A12/A24/A25; las escrituras llevan `__TEST` — D0). Roles `vicky`/`socio` (sin jenny, D-C-03). Filtros **REJECT-UNKNOWN, todos opcionales, ausente/null = sin filtro**: `periodo_desde`/`periodo_hasta`, `clase {A,C,D,E}`, `id_zona`/`id_cabana` (entero seguro > 0), `pagador_tipo {socio,caja}`, `q` (string `trim` 1..120, ILIKE sobre `etiqueta`+`comentario`, parametrizado, comodín `%`/`_` sin escape en MVP), `limit` (default 50/cap 200), `offset` (default 0). **Agregados sobre el universo filtrado completo** (no la página): `total_gastos = SUM(monto)` en centavos y `por_clase = [{clase, monto, n}]`. Salida `{ ok:true, data:{ periodo_desde, periodo_hasta, total_gastos, por_clase, filas, limit, offset } }`; vacío → `total_gastos:0, por_clase:[], filas:[]`, `ok:true`. **20 columnas por fila** (incluye `moneda` ARS por default — microajuste: no se exponen montos sin moneda), IDs BIGINT → número, opcionales null-safe, `socio_pagador_nombre`/`zona`/`cabana` por LEFT JOIN. A13 es **lectura pura**: cero DDL/función/columna.

**🔒 D-C-59 — Período contable: bordes truncados a primer día de mes (inclusivo por mes).**
`periodo_desde` y `periodo_hasta` se **normalizan a `YYYY-MM-01`** antes del clamp y de la comparación: un borde a mitad de mes **incluye el mes completo**. Floor duro `2026-07-01` (D-NEG-02) clampea el borde inferior (clamp, no reject; el SQL lo refuerza con `GREATEST`). `periodo_hasta` **híbrido**: omitido → mes actual (sin check de inversión → con floor futuro, el `{}` por defecto da vacío `ok:true`); explícito → YMD válido y, **a nivel mes** y tras el clamp, `>= periodo_desde`, sino `payload_invalido`. Aplica a toda lectura futura cuyo eje sea `periodo` contable.

**📝 L-C-22 — En PowerShell 5.1, una propiedad de array vacía puede deserializar como `$null`; chequear vacío con un helper defensivo o un proxy invariante, nunca con `.Count` pelado.**
`ConvertFrom-Json` en PS 5.1 puede devolver `$null` (no `@()`) para una propiedad JSON `[]`, y `@($null).Count == 1` — un chequeo `@($d.arr).Count -eq 0` daría falso negativo. Patrones seguros: (a) un helper `Filas`-style `if ($x) { @($x) } else { @() }` (que `$null` y `@()` colapsan a Count 0), o (b) un **proxy invariante**: como `gastos_internos.monto > 0` por constraint, `por_clase` vacío ⟺ `SumMonto(por_clase) == 0` (G3 usa esto en vez de `.Count`). Generaliza el helper `Filas` de A25 a principio explícito para todo smoke de lectura con arrays opcionalmente vacíos.

---

## 6. Estado final

✅ **A13 `gastos.listado` — wrapper directo CERRADO en TEST.**
Smoke directo **32/32 PASS** (seguridad 8, funcionales 10 con particiones data-independent que cierran contra el universo, payload inválido 13 incluyendo los filtros nuevos, META allowlist), y **cruce al centavo** del universo (`total_gastos=335000.00`, `por_clase`, `n=5`) contra el ground-truth `C_SLICE3B_A13_smoke_expected.sql`. Lectura pura: cero DDL/función/columna; `gastos_internos` consultada tal cual con joins read-only; agregados en centavos sobre el universo, paginación correcta, todo el error model mapeado a la allowlist (cero `estado_incierto`/`error_interno`). Template y smoke sanitizados y aptos para el repo.

---

## 7. Pendiente explícito

**Extensión del gateway `portal-api` para A13** (fase discreta, **siguiente conversación**):
- Agregar al CATALOG la entrada `'gastos.listado': { handler:'n8n', roles:['vicky','socio'], webhook:'portal-a13-gastos-listado', validate: <validador A13> }` → **CATALOG 12 → 13** (A11 ya lo llevó a 12).
- **Validador del gateway `payloadGastosListado` declarado ANTES del `CATALOG`** (zona muerta temporal / TDZ, L-C-11), espejando la normalización del wrapper. **Lectura → SIN `injectActor`, SIN `isWrite`, SIN `needsIdempotencyKey`** (no es escritura).
- **Paridad `periodo_hasta` omitido:** el validador del gateway debe **preservar la ausencia** de `periodo_hasta` (no firmar un default) para que gateway y directo tengan idéntica semántica; el wrapper defaultea al mes actual.
- Smokes de gateway por **JWT** (molde `C_SLICE3A_A25_GW_smoke.ps1` + `C_SLICE2_A10_GW_common.ps1`), con el cruce al centavo end-to-end contra el mismo expected.
- **NO tocar** en esa fase: `dispatchN8n`, `buildSignedEnvelope`, la allowlist, CORS, ni **ninguna entrada previa del CATALOG** (incluida la de A11).

Hasta que el gateway esté validado, A13 queda accesible **solo por el wrapper directo**.

---

## 8. Aclaraciones (límites de este cierre)

- **No cerrar Slice 3b todavía.** Slice 3b se cierra (`C_SLICE3B_CIERRE.md` + propagación a satélites + CATALOG 11→13) **después** de la extensión del gateway de A13. Este documento es un **mini cierre del wrapper directo**, no el cierre del slice.
- **No tocar A11.** A13 es su lectura companion; comparten tabla (`gastos_internos`) pero A13 no toca la infra de A11 (`portal_idempotencia`, `portal_cargar_gasto_interno`) — es lectura pura.
- **No tocar `portal-api` todavía.** La extensión del gateway es la próxima fase; este cierre no la incluye.
- **No tocar `6B_SCHEMA_SQL.md`.** El canónico no se modifica por A13 (se bumpea una sola vez por carril, en la promoción coordinada a OPS).
- **No tocar OPS.** Toda la validación fue en TEST.
- **Satélites no propagados.** `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `CLAUDE.md`, `README.md` y `Pendiente_pre_produccion.md` se actualizan recién en el cierre formal del slice. **D-C-58, D-C-59 y L-C-22 quedan propuestas en este documento** hasta esa propagación (junto con D-C-55/56/57 y L-C-20/21 de A11).

---

*Cierre inmutable una vez aprobado. Generado el 2026-06-22.*
