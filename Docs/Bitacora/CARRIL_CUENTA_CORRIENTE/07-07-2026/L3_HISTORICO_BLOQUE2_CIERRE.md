# CIERRE — Bloque 2: L3 histórico (lecturas sobre la foto congelada 9H + extensión)

- **Frente:** Snapshot mensual congelado + L3 histórico (Opción B)
- **Bloque:** 2 de N — capa de **lecturas** L3 (Bloque 1 = extensión del snapshot, ya cerrado; cierre asistido y gateway/frontend son bloques posteriores)
- **Fecha de cierre:** 2026-07-07
- **Estado:** CERRADO — verde en TEST y OPS (técnico)
- **Entornos:** TEST `bdskhhbmcksskkzqkcdp` · OPS `lpiatqztudxiwdlcoasv`
- **Canónico de referencia al abrir:** `6B_SCHEMA_SQL.md` v1.11.0 (**NO modificado** en este bloque; queda rezagado, ver §11)
- **Documento inmutable:** una vez aprobado, no se edita; correcciones van en documento nuevo.

---

## 1. Resumen ejecutivo

Se diseñaron, validaron y desplegaron **dos funciones de lectura read-only** sobre la foto mensual congelada (las cinco tablas 9H originales + las tres tablas de detalle fino de Bloque 1):

- **`cuenta_corriente_historico(p_mes date) → jsonb`** — detalle de **un** mes: resuelve la foto vigente del período y devuelve cabecera + linaje + cascada 1–8 + saldos por socio + detalle fino (participación, gastos, incidencias, matriz por socio derivada, gastos sin incidencia) + movimientos del mes + conciliación de retribución.
- **`cuenta_corriente_historico_acumulados() → jsonb`** — agregados globales sobre **todas** las fotos vigentes + el mayor: totales, desglose de gastos, evolución mes a mes (con retiros del mes), saldos vivos por socio y checks de piso.

Ambas son **puras de lectura**: no escriben, no tocan las lecturas en vivo (L1/L2) ni ninguno de los dos retiros, y **no modifican** las tablas ni `registrar_snapshot_periodo`. Toleran los dos estados reales del sistema hoy: en **TEST**, fotos vigentes **pre-extensión** (sin detalle fino persistido) → `detalle_disponible=false`; en **OPS**, **greenfield** (0 fotos) → `sin_foto` / `sin_datos`. El camino de detalle completo (caso A con datos persistidos) se validó de forma efímera (rollback-first) y queda pendiente de un primer cierre real para verse con datos reales (§9).

---

## 2. Objetos creados / desplegados

Dos funciones nuevas, idénticas en TEST y OPS (mismo cuerpo; solo difiere el gate de ambiente del artefacto de despliegue).

**`cuenta_corriente_historico(p_mes date) → jsonb`**
- `LANGUAGE sql`, `STABLE`, `SECURITY INVOKER`, `SET search_path = pg_catalog, public`.
- Resuelve la vigente vía `liquidacion_vigente(date_trunc('month', p_mes))`; nunca lee una foto superseded.
- `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated, service_role`.

**`cuenta_corriente_historico_acumulados() → jsonb`**
- `LANGUAGE sql`, `STABLE`, `SECURITY INVOKER`, `SET search_path = pg_catalog, public`.
- Reutiliza `saldo_corriente_socio(bigint)` **verbatim** (vía LATERAL) para `saldos_por_socio`.
- `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated, service_role`.

**Patrón de despliegue:** `DROP FUNCTION IF EXISTS` + `CREATE FUNCTION` + `REVOKE EXECUTE`, dentro de `BEGIN … COMMIT` con **gate anti-ambiente** (`configuracion_general('ambiente')`). Artefacto TEST con gate `test`; artefacto OPS con gate `ops`. Cuerpos byte-idénticos entre ambos (verificado por diff).

**Funciones reutilizadas (NO modificadas), solo leídas:** `liquidacion_vigente`, `saldo_corriente_socio`, `reporte_retribucion_operativo_periodo`. **Tablas leídas (NO modificadas):** `liquidaciones_periodo`, `liquidacion_cascada`, `liquidacion_socio`, `liquidacion_participacion`, `liquidacion_gasto`, `liquidacion_incidencia`, `movimientos_socio`, `cabanas`, `socios`, `zonas`.

**Sin secuencias, sin triggers, sin tablas nuevas.** L3 es solo dos funciones.

---

## 3. Evidencia — TEST (ejecutada por Franco)

| Artefacto | Resultado |
|---|---|
| `L3_01_DDL_FUNCIONES_TEST.sql` | Success. No rows returned (gate `test` OK; 2 funciones creadas). |
| `L3_02_VERIF_ESTRUCTURAL_FUNCIONES.sql` | **14/14 OK** (firma exacta, STABLE, INVOKER, `search_path=pg_catalog, public` exacto, retorno jsonb, proacl materializado, 0 EXECUTE sensibles — por cada función). |
| `L3_03_VALIDACION_PRE_EXTENSION_TEST.sql` | **3 fotos vigentes OK**, todas `PRE_EXTENSION`: 2026-07-01 liq#11, 2026-08-01 liq#9, 2026-11-01 liq#10. Sub-checks de contrato (`keys_ok`/`arrays_ok`/`retrib_ok`/`mov_ok`/`secciones_ok`) en verde. |
| `L3_04_VALIDACION_ROLLBACK_FIRST_TEST.sql` | **TODAS LAS ASERCIONES OK.** Foto efímera 2026-12: detalle completo (participación = cabañas, cascada 8, matriz derivada, `es_raiz=true`); supersesión **liq#14 supersede liq#13** (L3 lee la vigente V2, linaje correcto, mes de lab **1 sola vez** en evolución); acumulados con la foto efímera dentro de la transacción; `retiros_mes` coherente contra el mayor; `fotos_pre_piso=0`, `movimientos_pre_piso=0`; **ROLLBACK sin persistencia**. |

Nota: en TEST no hay foto vigente **con detalle** persistido (las tres vigentes son pre-extensión), por lo que L3-detalle allí devuelve `detalle_disponible=false` / `foto_pre_extension` — comportamiento esperado y aseverado por `L3_03`.

---

## 4. Evidencia — OPS (ejecutada por Franco)

| Artefacto | Resultado |
|---|---|
| `L3_05a_DDL_FUNCIONES_OPS.sql` | Success. No rows returned (gate `ops` OK; 2 funciones creadas; cuerpos idénticos a TEST). |
| `L3_02_VERIF_ESTRUCTURAL_FUNCIONES.sql` (en OPS) | **14/14 OK** (misma verificación estructural; artefacto agnóstico al ambiente). |
| `L3_05b_SMOKE_GREENFIELD_OPS.sql` | **6/6 OK**: `total_fotos=0` / `vigentes=0`; detalle → `sin_foto=true`, `detalle_disponible=false`, `detalle_motivo=sin_foto_vigente`, `retribucion_operativo=null`, secciones vacías; acumulados → `sin_datos=true`, evolución `[]`, totales en 0; `fotos_pre_piso=0`, `movimientos_pre_piso=0`. |

OPS queda **greenfield en datos**: solo estructura de funciones. Hasta el primer cierre real, L3 devuelve `sin_foto` / `sin_datos` (verificado).

---

## 5. Contrato final — `cuenta_corriente_historico(p_mes date) → jsonb`

Resuelve la foto **vigente** del mes de `p_mes` (`date_trunc('month', …)`). Dos ramas top-level. **Las 14 claves top-level están siempre presentes** en ambas ramas.

### 5.1 Rama SIN FOTO (`liquidacion_vigente` = NULL)

```jsonc
{
  "sin_foto": true,
  "detalle_disponible": false,
  "detalle_motivo": "sin_foto_vigente",
  "periodo": "YYYY-MM-01",
  "cabecera": null,
  "cascada": [], "socios": [], "participacion": [], "gastos": [],
  "incidencias": [], "movimientos": [], "matriz_por_socio": [],
  "gastos_sin_incidencia": [],
  "retribucion_operativo": null
}
```

### 5.2 Rama FOTO EXISTE (cubre caso A = con detalle y caso B = pre-extensión con la MISMA construcción)

```jsonc
{
  "sin_foto": false,
  "detalle_disponible": <bool>,          // true si participación > 0 (caso A); false si 0 (caso B)
  "detalle_motivo": <null|"foto_pre_extension">,  // null en A; "foto_pre_extension" en B
  "periodo": "YYYY-MM-01",
  "cabecera": {
    "id_liquidacion": <bigint>,          // la VIGENTE (nunca superseded)
    "periodo": "YYYY-MM-01",
    "pct_operativo": <numeric>,
    "creado_por": <text>,
    "created_at": <timestamptz>,
    "comentario": <text|null>,
    "linaje": { "es_raiz": <bool>, "id_liquidacion_supersede": <bigint|null> }
  },
  // --- lectura de la FOTO congelada (presentes en A y B) ---
  "cascada":  [ { "paso": 1..8, "concepto": <text>, "monto": <numeric> } ],   // 8 filas
  "socios":   [ { "id_socio", "socio", "saldo_bruto", "gastos_d", "gastos_e", "saldo_final", "desembolsado_periodo" } ],
  // --- detalle fino: poblado en A, [] en B (tablas de detalle vacías) ---
  "participacion": [ { "id_cabana", "cabana", "valor_relativo", "id_socio_beneficiario", "beneficiario", "participa" } ],
  "gastos":        [ { "id_gasto","fecha","clase","clase_sugerida","etiqueta","monto","moneda","id_zona","id_cabana",
                       "pagador_tipo","id_socio_pagador","medio_pago","comentario","comprobante_url","creado_por",
                       "created_at","sin_incidencia","motivo_sin_incidencia" } ],
  "incidencias":   [ { "id_gasto","seq","destino","id_socio","socio","monto_incidido","regla" } ],
  "matriz_por_socio": [ { "id_socio","socio","valor_socio","valor_pool","participacion" } ],  // DERIVADA de participación
  "gastos_sin_incidencia": [ { "id_gasto","clase","etiqueta","monto","motivo" } ],            // DERIVADO (filtro sin_incidencia)
  // --- lectura VIVA del mayor (NO es parte de la foto), ventaneada por fecha [mes, mes+1) ---
  "movimientos": [ { "id_movimiento","id_socio","socio","fecha","tipo","monto","medio_pago","comentario","periodo" } ],
  // --- conciliación del paso 4 (presente en A y B) ---
  "retribucion_operativo": { "periodo","calculado","asignado","diferencia","estado" }
}
```

**Notas de contrato:**
- `detalle_disponible` / `detalle_motivo` se **derivan de la cardinalidad de `liquidacion_participacion`** (0 filas ⇔ foto pre-extensión). No hay ramas A/B separadas: las secciones de detalle fino salen `[]` solas cuando las tablas están vacías.
- `cascada` y `socios` son las tablas originales 9H → **presentes también en pre-extensión**.
- `matriz_por_socio` y `gastos_sin_incidencia` son **derivados** de la foto, no reimplementan las funciones vivas.
- `movimientos` es **lectura viva** del mayor ventaneada por `fecha ∈ [mes, mes+1 mes)`; **no** forma parte del congelado.
- **Convención de signos: fiel a la foto** — ingresos positivos, gastos negativos (deducciones), utilidad neta con su signo.

---

## 6. Contrato final — `cuenta_corriente_historico_acumulados() → jsonb`

Agrega sobre **todas** las fotos vigentes + el mayor. Estructura única (no hay ramas):

```jsonc
{
  "sin_datos": <bool>,                     // true si no hay fotos vigentes
  "piso": "2026-07-01",                    // D-NEG-02 (constante)
  "totales": {
    "ingresos_acumulados":  <numeric>,     // Σ (paso1 + paso6) sobre vigentes            [positivo]
    "gastos_acumulados":    <numeric>,     // a_paso2 + c_paso7 + d_e_socios              [negativo: deducciones]
    "gastos_desglose": {
      "a_paso2":    <numeric>,             // Σ cascada paso 2 (clase A)                  [negativo]
      "c_paso7":    <numeric>,             // Σ cascada paso 7 (clase C)                  [negativo]
      "d_e_socios": <numeric>              // Σ (gastos_d + gastos_e) de socios (D+E)     [negativo]
    },
    "utilidad_acumulada":   <numeric>,     // Σ cascada paso 8 (base_de_ganancia)         [neto]
    "repartos_acumulados":  <numeric>,     // Σ saldo_bruto de socios
    "retiros_acumulados":   <numeric>      // Σ movimientos tipo 'retiro' (TODOS)         [negativo]
  },
  "evolucion": [                           // una entrada por foto vigente, ordenada por período
    { "periodo","id_liquidacion","ingresos","gastos","utilidad","repartos",
      "retiros_mes": <numeric> }           // Σ retiros con fecha ∈ [periodo, periodo+1 mes)  [negativo]
  ],
  "saldos_por_socio": [                     // reusa saldo_corriente_socio VERBATIM (pivot de las 4 componentes)
    { "id_socio","socio","resultado_liquidacion","reembolso_desembolso","movimientos","saldo_vivo" }
  ],
  "meta": {
    "fotos_vigentes":       <int>,
    "fotos_pre_piso":       <int>,         // fotos vigentes con período < piso (check; debe ser 0)
    "movimientos_pre_piso": <int>          // movimientos con fecha < piso (check; debe ser 0)
  }
}
```

**Política de piso (importante):** L3-acumulados **NO doble-filtra** por piso. `saldo_corriente_socio` se reutiliza verbatim (suma todas las fotos vigentes y todos los movimientos, sin recorte de piso); el piso solo se **expone como check** en `meta`. Esto mantiene una sola fuente de verdad para el saldo vivo.

---

## 7. Decisiones — candidatas D-CC-31+ (propuestas, NO acuñadas)

Se proponen para acuñar en el bump coordinado (§11). Numeración continúa desde D-CC-30.

- **D-CC-31** — L3 es **read-only sobre la foto vigente**: resuelve vía `liquidacion_vigente(mes)` y nunca lee una foto superseded. Sin escrituras, sin efectos.
- **D-CC-32** — **Dos ramas top-level** (`sin_foto` / foto-existe). Los casos A (con detalle) y B (pre-extensión) comparten construcción; `detalle_disponible`/`detalle_motivo` se **derivan de la cardinalidad de `liquidacion_participacion`** (0 ⇔ pre-extensión). No se ramifica por A/B.
- **D-CC-33** — **Convención de signos fiel a la foto congelada**: ingresos positivos, gastos negativos (deducciones), utilidad neta, retiros con signo. L3 **no transforma**; `gastos_acumulados` es la suma de deducciones (negativa).
- **D-CC-34** — `movimientos` en L3-detalle es **lectura viva del mayor**, ventaneada por `fecha ∈ [mes, mes+1 mes)`; **no** forma parte del congelado. Las otras 8 secciones sí son lectura de la foto.
- **D-CC-35** — `matriz_por_socio` y `gastos_sin_incidencia` son **derivados** (de `liquidacion_participacion` / filtro `sin_incidencia` sobre `liquidacion_gasto`); no reimplementan las funciones vivas de la matriz/incidencias.
- **D-CC-36** — L3 **fija `search_path = pg_catalog, public`** (a diferencia de L1/L2, que no lo fijaban), es `SECURITY INVOKER`, `STABLE`, y `REVOKE EXECUTE` a los tres roles Data API + `PUBLIC`.
- **D-CC-37** — **El piso no se doble-filtra** en L3-acumulados: `saldo_corriente_socio` se reutiliza verbatim (sin recorte de piso); el piso `2026-07-01` (reafirma D-NEG-02) solo se expone como check en `meta`.
- **D-CC-38** — `saldos_por_socio` **reutiliza `saldo_corriente_socio` verbatim** (vía LATERAL, pivot de las 4 componentes), en vez de reimplementar el saldo vivo.
- **D-CC-39** — `retribucion_operativo` (conciliación del paso 4 vía `reporte_retribucion_operativo_periodo`) está **presente cuando hay foto** (A y B) y es **`null` en `sin_foto`** (C).

---

## 8. Lecciones — candidatas L-CC nuevas (propuestas)

Numeración continúa desde L-CC-13.

- **L-CC-14** — Una sola construcción cubre "foto con detalle" y "foto pre-extensión": las secciones de detalle fino caen a `[]` por sí solas cuando las tablas de detalle están vacías para ese `id_liquidacion`. Validado en harness con una foto de cada clase corriendo el mismo código; evita ramas y duplicación.
- **L-CC-15** — Para el denominador de participación en `matriz_por_socio`, `SUM(SUM(valor_relativo)) OVER ()` (window sobre el agregado) da el pool total en una sola pasada tras el `GROUP BY` por beneficiario.
- **L-CC-16** — Validación de contrato JSON **asertiva**: `?&` para exigir todas las claves top-level, `jsonb_typeof(...)='array'` para los tipos de sección, y sub-checks booleanos por foto — más fuerte y diagnosticable que contar filas. La comparación de `search_path` debe ser por **valor exacto normalizado** (no basta con que exista un `SET`).
- **L-CC-17** — Patrón **rollback-first** para validar escritura sin ensuciar: `BEGIN` → gate → `CREATE TEMP … ON COMMIT DROP` (dentro de la txn) → congelar con la función real → asserts vía bloques `DO` que abortan (`RAISE`) → grilla de evidencia → `ROLLBACK`. Post-ROLLBACK no persiste ni la foto efímera ni el temp (solo queda el hueco de secuencia por `nextval`, benigno).

---

## 9. Pendientes explícitos

- **P-L3-01 — Camino de detalle completo con datos reales:** ni TEST (solo fotos pre-extensión) ni OPS (greenfield) tienen hoy una foto vigente **con detalle persistido**. L3 se validó contra las pre-extensión reales y contra una foto efímera con detalle (rollback-first); ver el caso A con datos reales requiere un **commit-freeze controlado** (o el primer cierre real). Queda pendiente, sin bloquear el cierre técnico.
- **P-L3-02 — Primera foto real OPS:** congelar un mes concreto con su detalle en OPS es un paso controlado posterior (fuera de este bloque).
- **P-L3-03 — Canonicalización + satélites + bootstrap:** ver §11 (recomendación: paquete coordinado).
- **P-CC-4 (vigente):** regeneración del bootstrap kit sigue diferida hasta que el frente CC completo cierre y el canónico estabilice.
- **Fuera de L3 (no pendientes de este bloque):** exposición vía gateway `portal-api`, workflows n8n, frontend, y el **cierre asistido**.

---

## 10. Qué NO se tocó (verificado)

- **L1/L2** (`cuenta_corriente_viva`, `cuenta_corriente_detalle`): intactas.
- **Los dos retiros** y el resto de escrituras del mayor (`registrar_retiro`, `registrar_movimiento_manual`, `registrar_reversa`, `registrar_revaluacion`): intactos.
- **`registrar_snapshot_periodo`** y las **tres tablas de detalle** (`liquidacion_participacion`/`gasto`/`incidencia`) y las cinco 9H: **solo se leen**, no se modificaron. L3 no altera la foto.
- **Gateway `portal-api`, n8n, frontend, cierre asistido:** sin cambios.
- **Canónico `6B_SCHEMA_SQL.md` (v1.11.0):** **NO modificado** — queda rezagado (las 2 funciones L3 no figuran aún; se alinean en el bump coordinado).
- **Satélites** (`DECISIONES_NO_REABRIR`, `Lecciones_Aprendidas`, `ESTADO_ACTUAL`, `Pendiente_pre_produccion`, `CLAUDE`, `README`) y **bootstrap kit:** sin tocar.
- **Primera foto real OPS:** no ejecutada.

---

## 11. Recomendación — canonicalización / satélites / bootstrap

**Recomiendo dejarlo para un paquete coordinado posterior, no artefactos sueltos de documentación ahora.** Razones:

1. **El canónico ya está rezagado por más de un bloque.** Bloque 1 (3 tablas + 6 triggers + `registrar_snapshot_periodo` extendida) tampoco se canonicalizó todavía, y ahora se suman las 2 funciones L3. Un **único bump coordinado** que aterrice todo CC (Bloque 1 + L3) en `6B_SCHEMA_SQL.md` es más limpio y evita bumps parciales que se pisen (trampa del canónico rezagado).
2. **El bootstrap ya está diferido como P-CC-4** hasta que el frente CC completo cierre y el canónico estabilice. Regenerarlo por L3 solo sería trabajo que hay que rehacer en el próximo bloque.
3. **Los satélites conviene patcharlos en una sola pasada quirúrgica** (con los patchers Python `str_replace`, disciplina de la casa) en ese bump: ahí se **acuñan** D-CC-31+ y L-CC-14+ (hoy candidatas), se actualiza `ESTADO_ACTUAL`, `Pendiente_pre_produccion`, `CLAUDE`, `README` y el bloque de esquema en un movimiento consistente.

**Qué propongo entonces:**
- **Ahora:** este documento de cierre queda como **bitácora inmutable** del Bloque 2 (registro del hecho, contratos y decisiones candidatas) — sin tocar canónico ni satélites ni bootstrap.
- **Cuando digas:** un **paquete coordinado de canonicalización CC** (Bloque 1 + L3 juntos): bump de `6B_SCHEMA_SQL.md`, patchers de satélites acuñando D-CC-31..39 y L-CC-14..17, y — recién si el frente CC ya está estable — la regeneración del bootstrap (P-CC-4).

Si preferís, puedo en cambio generar **artefactos separados de documentación** (p. ej. un delta de decisiones/lecciones como bitácora) sin canonicalizar; decímelo y lo armo. **No genero patchers ni toco satélites/canónico/bootstrap hasta tu OK explícito.**

---

### Anexo — artefactos del bloque

| Artefacto | Rol | Ambiente |
|---|---|---|
| `L3_01_DDL_FUNCIONES_TEST.sql` | DDL de las 2 funciones (gate TEST) | TEST |
| `L3_02_VERIF_ESTRUCTURAL_FUNCIONES.sql` | Verificación estructural read-only | TEST y OPS |
| `L3_03_VALIDACION_PRE_EXTENSION_TEST.sql` | Validación de contrato sobre fotos vigentes | TEST |
| `L3_04_VALIDACION_ROLLBACK_FIRST_TEST.sql` | Rollback-first (foto efímera con detalle) | TEST |
| `L3_05a_DDL_FUNCIONES_OPS.sql` | DDL de las 2 funciones (gate OPS; cuerpo idéntico a `L3_01`) | OPS |
| `L3_05b_SMOKE_GREENFIELD_OPS.sql` | Smoke greenfield (`sin_foto`/`sin_datos`) | OPS |

Validación previa: `pglast` + harness PostgreSQL 16.14 (fiel: cuerpos reales de `liquidacion_vigente`/`saldo_corriente_socio`/`reporte_retribucion_operativo_periodo`; fotos con detalle, pre-extensión y superseded; registrar de harness para el rollback-first) + ASCII-puro/LF. Ejecución real en TEST/OPS por Franco (§3, §4).
