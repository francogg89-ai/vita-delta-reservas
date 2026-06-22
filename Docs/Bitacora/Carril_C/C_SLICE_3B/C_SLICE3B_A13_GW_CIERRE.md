# CARRIL C — SLICE 3b — A13 `gastos.listado` (GATEWAY `portal-api`) — CIERRE

**Estado:** ✅ **Extensión del gateway APROBADA en TEST.** A13 queda cableada de punta a punta por el **gateway `portal-api`** (autenticación JWT → validación de payload server-side → firma HMAC → wrapper n8n → SELECT). Es la **tercera lectura** del Portal Operativo Interno accesible vía gateway (tras A24/A25 en Slice 3a) y la **lectura companion de A11**. Validada end-to-end por **smoke JWT** (seguridad + funcional con **cruce al centavo** + **paridad gateway↔wrapper directo**) contra Supabase + n8n TEST reales. **Lectura pura** → sin `injectActor`, sin `isWrite`, sin `needsIdempotencyKey`, sin teardown. Cierra el pendiente §7 del `C_SLICE3B_A13_DIRECTO_CIERRE.md`.

**Entorno de validación:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`) — IDs de cabaña 1–5, marcador `configuracion_general.ambiente='test'`.
**Entorno de operación:** — (A13 **no** se promovió a OPS; el Carril C **no** toca OPS para experimentar).
**Fecha de cierre:** 2026-06-22.
**Base:** `C_SLICE3B_A13_DIRECTO_CIERRE.md` (contrato A13, wrapper `portal-a13-gastos-listado`, D-C-58/59, L-C-22) + `C_SLICE3B_A11_portal-api_index.ts` (gateway de Slice 3b tras el cableado de A11, **CATALOG 12 — punto de partida**) + `C_SLICE3A_A25_GW_smoke.ps1` / `C_SLICE2_A10_GW_common.ps1` (molde de smoke JWT de **lectura** con el helper congelado).
**Depende de:** D-C-30 (JWT vía `getUser`) · D-C-34 (identidad/rol server-side desde `portal_usuarios`) · D-C-36/37 (dispatch a n8n firmado; `ambiente_esperado` desde `VITA_AMBIENTE`) · D-C-39/41 (doble allowlist rol×action + action binding) · D-C-18/35 (envelope uniforme; HTTP 200 + envelope para resultados manejados) · D-C-03 (jenny sin contenido económico) · D-NEG-02 (floor contable duro `2026-07-01`) · **D-C-58, D-C-59** (contrato A13 / período truncado a mes, del cierre directo) · L-C-11 (validador declarado antes del CATALOG, TDZ) · L-C-17 (cuarteto PowerShell 5.1) · L-C-19 (BIGINT → number en el contrato) · L-C-22 (PS 5.1: propiedad-array vacía deserializa como `$null`).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.8.1` — **NO modificado por este cierre.** A13 es **lectura pura**: la extensión del gateway no introduce DDL, columnas ni funciones; `gastos_internos` se consulta vía el wrapper inmutable.
**Autores:** Franco (titular, ejecutor de **todos** los deploys/smokes en Supabase y n8n) + Claude (arquitecto/copiloto; estrictamente advisory — no tocó infraestructura).
**Decisiones registradas:** D-C-60 🔒. **Lecciones:** L-C-23 📝. *(Propuestas en este documento hasta la propagación formal a satélites — §8.)*

---

## 1. Alcance

Extender el gateway `portal-api` para cablear **únicamente** la acción `gastos.listado` (A13, **lectura**), partiendo del gateway tras A11 (CATALOG 12), y validarla por **smoke JWT** con cruce al centavo y paridad. El wrapper directo A13, su SQL y el ground-truth quedan **inmutables** (cerrados en el directo); este cierre **no** los toca.

**Lo que el gateway agrega para A13:**
- Validación de payload de negocio **antes de firmar** (espejo del paso 9 del wrapper, doble allowlist D-C-39), con **semántica mensual** espejada (D-C-60): truncado a primer día de mes antes del clamp y del check de inversión.
- Normalización/whitelisteo del payload (REJECT-UNKNOWN, 9 claves), reusando los enums y el floor ya declarados arriba para A11.

**Lo que A13 NO necesita (lectura pura):** `injectActor` (no hay actor que inyectar), `isWrite`/`estado_incierto` (no hay write que proteger), `needsIdempotencyKey` (no hay anti-replay). Tampoco hay teardown ni gate de write-residual.

**Fuera de alcance:** el cierre formal de Slice 3b (`C_SLICE3B_CIERRE.md` + propagación a satélites + CATALOG 11→13 en la documentación), y cualquier toque a A11, OPS o al canónico (§7/§8).

---

## 2. Artefactos finales

**Gateway `portal-api` (TypeScript, deploy por Dashboard, `verify_jwt OFF`):**
- `C_SLICE3B_A13_portal-api_index.ts` — copia del gateway tras A11 + **2 cambios puramente aditivos** (verificado por diff: **111 líneas agregadas / 0 removidas**; todo lo previo byte-idéntico):
  1. Validador `payloadGastosListado` (export), **declarado antes del CATALOG** (TDZ, L-C-11). Espejo del paso 9 del wrapper: **9 claves permitidas** (REJECT-UNKNOWN: `periodo_desde/periodo_hasta/clase/id_zona/id_cabana/pagador_tipo/q/limit/offset`) + tipos + 2 enums (`clase` ∈ {A,C,D,E}, `pagador_tipo` ∈ {socio,caja}) + **truncado a primer día de mes** (`firstOfMonth_GW`, D-C-59/60) **antes** del clamp al floor y del check de inversión + `periodo_hasta` **híbrido laxo** (omitido **o** null → no va en `value`; string → YMD + truncar + comparar a nivel mes; otro tipo o mal formado → `payload_invalido`). Reusa `isYMD_GW`, `ENUM_CLASE_GW`, `ENUM_PAGADOR_GW` y `FLOOR_A24_GW` (declarados arriba para A11); `q` con cap propio **120**. Los filtros válidos van en `value`; los ausentes/null **no** (el wrapper usa `IS NULL`). El validador devuelve el payload **normalizado/whitelisteado**.
  2. Entrada CATALOG `'gastos.listado'`: `roles:['vicky','socio']`, `webhook:'portal-a13-gastos-listado'` (**sin `__TEST`**, convención de lecturas A12/A24/A25), `validate:payloadGastosListado`, **SIN `injectActor`/`isWrite`/`needsIdempotencyKey`**. **CATALOG 12 → 13.**

**Smoke (PowerShell ASCII-puro):**
- `C_SLICE3B_A13_GW_smoke.ps1` — **34 asserts** por JWT. Reusa el helper congelado `C_SLICE2_A10_GW_common.ps1` (JWT, `Invoke-Gateway`, asserts, allowlist) y los asserts funcionales/IDs del smoke directo A13, ahora por gateway (se accede `$r.data` directo, sin `.json`). **Lectura → SIN teardown.** Reusa el ground-truth `C_SLICE3B_A13_smoke_expected.sql` del cierre directo (**no se re-emitió**) para el cruce al centavo.

---

## 3. Evidencia (TEST)

**Validación estática del gateway (toolchain local):**
```
esbuild transpile ............................ OK (rc=0)
diff quirurgico (a11 -> a13) ................. TODO ADITIVO (111 lineas +, 0 -)
  - intocables byte-identicos: dispatchN8n, buildSignedEnvelope, allowlist,
    CORS, payloadIngresosPeriodo (A25, semantica de null ESTRICTA, sin tocar),
    y las 12 entradas previas del CATALOG
CATALOG ...................................... 12 -> 13 (las 12 previas verbatim)
test paridad gateway<->wrapper directo (24) .. 24/24 al byte
  - gateway-then-wrapper == wrapper-directo para toda la bateria de inputs
  - sanity: SIN el truncado de D-C-60, el caso mismo-mes DIVERGE (REJECT vs agosto)
```

**Smoke JWT (corrida real de Franco):**
```
SMOKE GATEWAY A13 ............................ 34/34 PASS / 0 FAIL
  SEGURIDAD (5): vicky OK, socio (franco) OK, jenny -> rol_no_permitido,
    sin JWT -> no_autorizado, accion desconocida -> accion_desconocida
  FUNCIONALES (12):
    universo: total_gastos=335000 filas=5 por_clase A:40000(1) C:25000(1) E:240000(2) D:30000(1)
    G0a/G0b cruce al centavo .................. total_gastos==335000, n_filas==5
    G1 cuadre por_clase==total==filas ........ PASS
    G2 por_clase {A,C,D,E} + n cuadra ........ PASS
    G3 default {} vacio (floor futuro) ....... PASS
    G4 clamp periodo_desde<floor ............. PASS
    G5/G6 particion clase / pagador == universo PASS
    G7 monotonia clase=A <= universo ......... PASS
    G8 q sin match -> vacio .................. PASS
    G9/G10 paginacion limit=1 / offset sin solape PASS
  PARIDAD (2):
    GP mismo mes (hasta<desde dia) -> agosto 180000, NO payload_invalido (D-C-60) .. PASS
    P-null periodo_hasta null == omitido (ambos ok:true, mismo resultado) -> 24/24 .. PASS
  PAYLOAD INVALIDO (14): clave / periodo_desde malformado / inversion cross-month /
    periodo_hasta malformado / periodo_hasta otro tipo (P4b) / limit / clase / pagador /
    id_zona=0 / id_cabana / q vacio / q oversized / payload string / payload array
  META allowlist ............................. PASS
  Codigos vistos: accion_desconocida, no_autorizado, payload_invalido, rol_no_permitido
```

**Cruce AL CENTAVO (lo central):** la salida del gateway para el universo (`total_gastos=335000.00`, `por_clase` A=40000(1)/C=25000(1)/D=30000(1)/E=240000(2), `filas=5`) coincide **exactamente** con `E1/E2/E3` del ground-truth `C_SLICE3B_A13_smoke_expected.sql`. Las particiones (clase, pagador) cierran contra el universo: `A+C+D+E == socio+caja == 335000`. **Cero `estado_incierto`, cero `error_interno`** en todos los caminos.

---

## 4. Notas de construcción / propiedades validadas

1. **Acciones previas byte-idénticas.** El validador y la entrada son puramente aditivos; las **12 entradas previas** del CATALOG y todo el andamiaje (`dispatchN8n`, `buildSignedEnvelope`, allowlist, CORS, `actorCoherente`, los validadores previos) quedan byte-idénticos (diff: 111 líneas +, 0 −). **Cero regresión.**
2. **Semántica mensual espejada (D-C-60).** El gateway trunca `periodo_desde`/`periodo_hasta` a `YYYY-MM-01` **antes** del clamp al floor y del check de inversión, igual que el wrapper (D-C-59). Sin esto, un rango del mismo mes con día de hasta < día de desde (ej. `2026-08-15` / `2026-08-10`) rebotaría `payload_invalido` en el gateway mientras el wrapper directo devuelve agosto → **divergencia**. **GP** lo prueba (ambos truncan a `2026-08-01` → agosto `180000`, `ok:true`). El wrapper **re-trunca** (idempotente) y mantiene la verdad autoritativa.
3. **Paridad `null == omitido` (precisión de D-C-60).** Para A13 la **verdad de referencia es el wrapper directo**, que trata `periodo_hasta:null` como **omitido** (defaultea al mes actual, sin check). El gateway hace lo mismo: ni omitido ni null entran en `value`. **P-null** prueba que omitido y null dan `ok:true` y el **mismo resultado** (`total_gastos`, `n_filas`, `periodo_hasta` resuelto). A25 mantiene su semántica **estricta** (`null` → `payload_invalido`): son acciones distintas, su `payloadIngresosPeriodo` quedó **intacto**. Verificado además por el **test de paridad ejecutable 24/24** (antes 23/24, con el null como único delta).
4. **Lectura pura.** Sin `injectActor` (no hay actor que inyectar), sin `isWrite` (no hay write que proteger → `estado_incierto` no es alcanzable), sin `needsIdempotencyKey`. El gateway valida el payload, firma el sobre y forwardea; el wrapper revalida (2da defensa, espejo).
5. **`q` con cap propio.** El validador del gateway usa `Q_MAXLEN_A13_GW = 120` (no `MAXLEN_GW`), espejando el wrapper. P9 (vacío tras `trim`) y P10 (>120) → `payload_invalido`; `q` ausente/null = sin filtro.

---

## 5. Decisiones y lecciones nuevas

**🔒 D-C-60 — El gateway A13 espeja la semántica MENSUAL del wrapper directo (incluye la paridad `null == omitido`).**
`payloadGastosListado` trunca `periodo_desde`/`periodo_hasta` a primer día de mes (`firstOfMonth_GW(s)=s.slice(0,8)+'01'`) **antes** del clamp al floor (`2026-07-01`, D-NEG-02) y del check de inversión explícita, para **no ser más estricto que el wrapper**: un rango del mismo mes con día de hasta < día de desde **no** es inversión a nivel mes y **no** debe rebotar (el wrapper directo lo acepta y devuelve ese mes). `periodo_hasta` **híbrido**: omitido (`undefined`) **o** `null` → **no** se incluye en `value` (paridad con el wrapper directo, que trata null como omitido y defaultea al mes actual sin check); `string` → YMD válido, truncado y, tras el clamp, `>= periodo_desde` a nivel mes; **otro tipo** o mal formado/invertido → `payload_invalido`. El wrapper **re-trunca** (idempotente) y mantiene la verdad autoritativa. La **verdad de referencia de A13 es su wrapper directo**, distinta de A25 (cuyo `payloadIngresosPeriodo` rechaza `null` y queda intacto). Verificado por test de paridad ejecutable gateway↔wrapper (**24/24**) y por el smoke JWT (**GP** mismo-mes + **P-null** null==omitido). *(La parte de `null == omitido` es una precisión de paridad de A13, no una decisión separada.)*

**📝 L-C-23 — Para un campo híbrido (omitido vs explícito), el gateway espeja la verdad del wrapper DIRECTO de ESA acción, no la de un validador hermano; y nunca es más estricto que su wrapper.**
A13 y A25 comparten el andamiaje de período, pero su semántica de `periodo_hasta:null` **difiere legítimamente**: el wrapper directo de A13 trata `null` como omitido (laxo), mientras A25 lo rechaza (estricto). Espejar A25 en A13 habría hecho al gateway **más estricto que su propio wrapper** → divergencia gateway↔directo en un caso de borde. **Regla:** para cada acción, el gateway se valida contra **SU** wrapper directo, no contra hermanos de estructura similar. **Técnica de verificación:** un **test de paridad ejecutable** que porta ambas normalizaciones (gateway-then-wrapper vs wrapper-directo) y compara el resultado sobre una batería de inputs (acá 24/24) — barato y atrapa divergencias sutiles que el razonamiento manual pasa por alto (acá detectó el delta del `null` antes del deploy).

---

## 6. Estado final

✅ **A13 `gastos.listado` — extensión del gateway `portal-api` CERRADA en TEST.**
Gateway validado estáticamente (esbuild rc=0 + diff aditivo 111/0 + intocables byte-idénticos —incl. `payloadIngresosPeriodo` de A25 estricto—, CATALOG 12→13 + **paridad ejecutable 24/24**); smoke JWT **34/34** (seguridad/funcional con cruce al centavo/paridad **GP**+**P-null**/payload inválido incl. **P4b**); **sin teardown** (lectura pura). El gateway valida el payload con semántica mensual espejada (D-C-60), forwardea sin enmascarar (cero `estado_incierto`), deja byte-idénticas las 12 acciones previas, y cierra **paridad 24/24** con el wrapper directo. A13 ahora es accesible por **gateway** y por **wrapper directo**.

---

## 7. Pendiente explícito

**Cierre formal de Slice 3b — ahora habilitado (A11 + A13 cerrados, directo + gateway):**
- `C_SLICE3B_CIERRE.md` + **propagación a satélites** (`DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `CLAUDE.md`, `README.md`, `Pendiente_pre_produccion.md`).
- **CATALOG 11→13** en la documentación (A11 lo llevó a 12, A13 a 13).
- Propagar **D-C-55/56/57** (A11) + **D-C-58/59** (A13 directo) + **D-C-60** (A13 gateway) + **L-C-20/21/22/23**.

**Promoción coordinada del Carril C a OPS — cuando cierren todas las slices** (bump único del canónico `6B_SCHEMA_SQL.md` en la promoción).

---

## 8. Aclaraciones (límites de este cierre)

- **No cierra Slice 3b.** Este es un **mini-cierre de la extensión del gateway de A13** (paralelo al mini-cierre del wrapper directo), no el cierre del slice. Con **A11 + A13 cerrados (directo + gateway)**, Slice 3b queda listo para su **cierre formal**.
- **Gateway desplegado en TEST con CATALOG 13.** En la **documentación satélite** el conteo de CATALOG sigue reflejando el estado previo hasta el cierre formal de Slice 3b (que lo lleva a 13 en docs).
- **Satélites no propagados.** `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `CLAUDE.md`, `README.md` y `Pendiente_pre_produccion.md` se actualizan recién en el cierre formal del slice. **D-C-60 y L-C-23 quedan propuestas en este documento** hasta esa propagación (junto con D-C-55/56/57/58/59 y L-C-20/21/22).
- **No se tocó el wrapper directo A13 ni A11.** Quedaron inmutables. `payloadIngresosPeriodo` (A25) quedó **intacto** (semántica estricta de `null`).
- **No se tocó `6B_SCHEMA_SQL.md` ni OPS.** A13 es lectura pura, cero DDL; toda la validación fue en TEST.

---
