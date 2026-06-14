# PROMOCIÓN DEL CARRIL B A OPS — CIERRE

**Etapa:** N — Cierre de promoción del Carril B (contabilidad operativa interna) a OPS + actualización de satélites.
**Fecha de cierre:** 2026-06-14.
**Estado:** ✅ Cerrada. El Carril B completo (sub-etapas **9C→9H** + helper **9B**) quedó **promovido a OPS** en una operación coordinada bloque por bloque (junio 2026), con **paridad estructural TEST↔OPS certificada por huella** y el canónico `6B_SCHEMA_SQL.md` **bumpeado a v1.8.0**. DEV queda fuera del alcance (reconstrucción posterior).
**Ámbito:** 100% documental + de promoción de schema. Claude actuó como arquitecto: generó los artefactos `PROMO_BLOQUE_*`, las verificaciones y este cierre; **Franco ejecutó todos los writes** en Supabase y la importación del workflow en n8n.

> **Qué NO reabre este cierre.** No reabre ni redefine las decisiones conceptuales del Carril B (9C→9H), que conservan su numeración `D-9x` y son la fuente de diseño. No reabre los cierres de sub-etapa `9B_CIERRE.md` … `9H_CIERRE.md`. Las decisiones de esta etapa (`D-PROMO-XX`) son **decisiones de promoción/ejecución**, no rediseño del modelo; las lecciones (`L-PROMO-XX`) son de promoción, validación y documentación.

---

## 1. Resumen ejecutivo

Hasta v1.7.3 el Carril B vivía **solo en TEST** como capa aditiva no canónica. Esta etapa lo **promovió a OPS** recreándolo **por DDL bloque por bloque, sin copiar datos de TEST** (estructura, no filas), y lo **consolidó en el canónico v1.8.0** como capa real, autocontenida y apta para bootstrappear un entorno de cero.

Resultado verificado:

- **Paridad estructural TEST↔OPS exacta:** la huella `TOTAL_CARRIL` sobre los **31 objetos** del carril quedó **idéntica** en ambos entornos (`f5187092083451ceb5b182334bdb4a17`), tras alinear 4 funciones cosméticas y limpiar ACL residual en TEST.
- **Cero exposición** a la Data API: las 9 tablas, las 6 secuencias y las 21 funciones quedaron sin grant a `PUBLIC`/`anon`/`authenticated`/`service_role`, sin RLS.
- **Smokes read-only 18/18 verde** en OPS, preservando las tablas 9H vacías y las secuencias en 1 (la primera liquidación real arranca en 1).
- **Workflow de cobranza posterior** (`vita_w09_cobranza_posterior`, 14 nodos) + listado de saldos read-only **andando en OPS**.
- **Canónico v1.8.0 entregado** (sección 24 conceptual + PARTE C ejecutable C0–C14 con cuerpos en estado post-K1 + changelog), con **bootstrap real Parte B + Parte C verificado en limpio**.

El equipo opera ahora la contabilidad operativa interna sobre OPS sobre los mismos datos reales del complejo. El carril fiscal/legal (AFIP/ARCA/IVA) sigue fuera de alcance por diseño.

---

## 2. Estado de entrada (verificado)

- **Carril B cerrado y validado en TEST** en seis sub-etapas aditivas: 9C (catálogo enriquecido + zonas + seam), 9D (activación operativa por rango), 9E (matriz + reparto read-only), 9F (gasto interno rediseñado), 9G (cascada de liquidación read-only), 9H (cuenta corriente / capa con estado). Helper **9B** `abortar_si_falla(jsonb)` creado en TEST para el rollback transaccional de la cobranza posterior.
- **Canónico v1.7.3** intacto; los objetos del Carril B eran aditivos y **no canónicos**, existentes solo en TEST. **Nada en OPS.**
- **OPS** (`vita-delta-ops`): primer entorno de operación real interna, paritario con v1.7.3, con datos reales del complejo (reservas, pagos, bloqueos), cabañas ids **1-5**, socios **Franco(1) / Rodrigo(2) / Remo(3)**.
- **Política de promoción** (decisión vigente desde 9B, ratificada en 9G/9H): promoción **coordinada única** de todo el Carril B, por DDL, sin copiar datos ni fixtures.

---

## 3. Inventario promovido a OPS

**2 columnas** en `cabanas`:
- `valor_relativo` NUMERIC(6,2) (peso en el pool de reparto) e `id_socio_beneficiario` BIGINT NOT NULL FK RESTRICT (titularidad operativa). Backfill **por nombre** (no ids literales): Arrebol→Franco/100, Madre Selva→Rodrigo/100, Bamboo→Remo/100, Guatemala→Franco/78, Tokio→Remo/78.

**9 tablas:**
- 9C: `zonas`, `cabana_zona` (grandes = Arrebol/Madre Selva/Bamboo; chicas = Guatemala/Tokio).
- 9D: `activaciones_operativas` (rangos `[)`, EXCLUDE gist por cabaña). Pool D-9D-10: Bamboo/Madre Selva/Arrebol/Tokio desde 2026-07-01; **Guatemala desde 2026-11-01**.
- 9F: `gastos_internos`.
- 9H: `liquidaciones_periodo`, `liquidacion_cascada`, `liquidacion_socio`, `movimientos_socio`, `revaluaciones`.

**21 funciones** (incluyen la función de trigger de inmutabilidad y el helper 9B, según el inventario del canónico):
- Seam (9C): `resolver_beneficiario`.
- Matriz/reparto (9E): `matriz_participacion`, `repartir_por_matriz`, `detalle_participacion`.
- Cascada read-only (9G): `cascada_periodo`, `saldo_socios_periodo`, `incidencia_gasto`, `reporte_overrides_periodo`, `reporte_5_vs_fiscal_periodo`, `gastos_sin_incidencia_periodo`.
- Cuenta corriente (9H): lectura — `liquidacion_vigente`, `saldo_corriente_socio`, `mayor_socio`, `reporte_retribucion_operativo_periodo`; escritura solo-INSERT con advisory locks — `registrar_snapshot_periodo`, `registrar_retiro`, `registrar_movimiento_manual`, `registrar_reversa`, `registrar_revaluacion`.
- Función de trigger de inmutabilidad (9H): `trg_9h_inmutable`.
- Helper (9B): `abortar_si_falla`.

**10 triggers** de inmutabilidad (BEFORE UPDATE + BEFORE DELETE sobre las 5 tablas de 9H), vía `trg_9h_inmutable()`.

**6 secuencias:** `zonas_id_zona_seq`, `activaciones_operativas_id_activacion_seq`, `gastos_internos_id_gasto_seq`, `liquidaciones_periodo_id_liquidacion_seq`, `movimientos_socio_id_movimiento_seq`, `revaluaciones_id_revaluacion_seq`.

**1 marcador:** `configuracion_general('ambiente') = 'ops'` (sembrado recién en la promoción).

> **`gastos` legacy se conserva.** La tabla base `gastos` sigue existiendo como tabla histórica/base de la Parte B (catálogo "Sin cambio"); el Carril B opera sobre `gastos_internos`. **No se migran ni copian datos de `gastos` legacy.** Cualquier `DROP TABLE IF EXISTS gastos` en los artefactos es teardown/rollback documental, no una decisión de promoción.

---

## 4. Bloques ejecutados (bitácora A-bis → M)

| Bloque | Qué hizo | Resultado |
|---|---|---|
| **A / A-bis** | Snapshot baseline **read-only** de OPS (sin writes, sin DDL): identidad por seed (L-7E-01), baseline de EXECUTE contemplando la trampa `proacl NULL ⇒ PUBLIC ejecuta`, exclusión de funciones de extensión (`pg_depend deptype='e'`, btree_gist). DDL habilitado solo con A y A-bis en verde. | ✅ Verde; DDL habilitado |
| **B1 (9C)** | Columnas de `cabanas` + `zonas`/`cabana_zona` + seam, backfill por nombre + `NOT NULL`. | ✅ |
| **C (9D)** | `activaciones_operativas` + EXCLUDE gist + pool real D-9D-10. | ✅ |
| **D (9E)** | `matriz_participacion`/`repartir_por_matriz`/`detalle_participacion` read-only. | ✅ |
| **E (9F)** | `gastos_internos` (17 col, 18 constraints nombradas). | ✅ |
| **F (9G)** | Cascada read-only: 6 funciones `sql STABLE SECURITY INVOKER`. | ✅ |
| **G (9H estructura)** | 5 tablas append-only + `trg_9h_inmutable()` + 10 triggers. | ✅ |
| **H (9H funciones)** | 9 funciones (4 lectura + 5 escritura solo-INSERT con advisory locks). | ✅ |
| **I (helper 9B)** | `abortar_si_falla(jsonb)` creado **último**, con gate de orden de promoción + `search_path` + `REVOKE EXECUTE`. | ✅ |
| **J (hardening sweep)** | Barrido read-only de exposición sobre 9 tablas + 6 secuencias + 21 funciones. | ✅ **Cero exposición** |
| **K1 (huella estructural)** | Doble corrida del mismo script simétrico en TEST y OPS; 8 divergencias **cosméticas** (4 tablas con `Dxtm` residual + 4 funciones de formato) → 2 parches (K1B: OPS alineado a la versión de TEST para esas 4 funciones, con companion de revert + limpieza ACL en TEST). | ✅ `TOTAL_CARRIL` **idéntica** |
| **K2 (smokes)** | Smokes **read-only puros** sobre OPS (sin escritura 9H ni bajo ROLLBACK): lecturas, helper con JSON sintético, pool real (jul=4 / nov=5), invariante tablas 9H vacías + secuencias en 1. | ✅ **18/18** |
| **L (workflow 3b)** | Port a OPS de `vita_w09_cobranza_posterior` (14 nodos, `abortar_si_falla` + `queryBatching:transaction`) + listado de saldos read-only; revisión de marcadores de entorno embebidos (L-8D-03). | ✅ Andando en OPS |
| **M (bump canónico)** | `6B_SCHEMA_SQL.md` → **v1.8.0**: sección 24 (conceptual) + PARTE C (DDL C0–C14, cuerpos post-K1) + changelog + Bloque 21 (`Socio 3`→`Remo`). Excluye la maquinaria de promoción. | ✅ Bootstrap fresco verificado |

---

## 5. Evidencia dura consolidada

| Ítem | Valor |
|---|---|
| Paridad estructural K1 (`TOTAL_CARRIL`, 31 objetos) | `f5187092083451ceb5b182334bdb4a17` — **idéntica TEST↔OPS** |
| Hardening J | 0 exposición a Data API/PUBLIC sobre 9 tablas + 6 secuencias + 21 funciones |
| Smokes K2 | 18/18 verde (read-only) en OPS |
| Pool real (9D) verificado | julio = 4 cabañas (matriz 378) · noviembre = 5 (matriz 456) |
| Reparto (9E) verificado | Σ exacto al centavo (`repartir_por_matriz(2026-07-01, 100000)` = 100000.00) |
| Workflow L | `vita_w09_cobranza_posterior`, 14 nodos, importado/configurado/andando en OPS |
| PARTE C del canónico v1.8.0 (hash calculado durante M-bis) | `ff2272fd53f7bf2ef125e9bb14a4af17` |
| Bootstrap real (Parte B + Parte C, en limpio) | 9 tablas · 21 funciones · 10 triggers · seam 5/5 · matriz 378/456 · reparto Σ exacto · hardening sin exposición |

---

## 6. Decisiones de promoción (D-PROMO-01 a D-PROMO-13) 🔒

Decisiones de **ejecución de la promoción** (no rediseño del modelo). Versión sintética; el detalle bloque por bloque vive en este cierre (§4) y en los artefactos `PROMO_BLOQUE_*`.

- **D-PROMO-01** — Promoción coordinada **bloque por bloque por DDL, sin copiar datos de TEST**: se recrea estructura, no se migran filas; los fixtures de laboratorio (`seed_9f_validacion`, `seed_9g_%`, `seed_9h_d`) **no viajan**. Materializa D-9F-17 / D-9G-13 / D-9H-20.
- **D-PROMO-02** — **Snapshot baseline doble (A + A-bis) read-only antes de habilitar DDL**, con gate de identidad por seed; el baseline de EXECUTE contempla `proacl IS NULL ⇒ PUBLIC ejecuta por default` y excluye funciones de extensión (`pg_depend deptype='e'`).
- **D-PROMO-03** — **Marcador `ambiente='ops'` sembrado recién en la promoción** + gate `DO+RAISE` de ambiente/seed (cabañas 1-5) en cada bloque, como pre-check y dentro de la transacción. Reconcilia D-9C-19.
- **D-PROMO-04** — **`Socio 3` → `Remo` + backfill de beneficiarios POR NOMBRE** (no ids literales) en el seed base del canónico (Bloque 21). **Materializa D-9C-20 / D-9C-21**; no las duplica.
- **D-PROMO-05** — **Alineación de las 4 funciones 9C/9E en OPS contra la versión de TEST vía DROP+CREATE** (no `CREATE OR REPLACE`); diferencia 100% cosmética (comentarios/formato + 1 alias redundante en `detalle_participacion` que no altera la salida), con parche **K1B + companion de revert** (sin CASCADE).
- **D-PROMO-06** — **Limpieza de ACL residual `Dxtm` en las 4 tablas tempranas de TEST (`REVOKE ALL`)** para sacar los grants que dejó `ALTER DEFAULT PRIVILEGES`; OPS ya estaba limpio (más hardened).
- **D-PROMO-07** — **GRANTs/RLS del Carril B = cerrado sin grants y sin RLS**: `REVOKE` total sobre las 9 tablas, las 6 secuencias y las 21 funciones (incluidos `trg_9h_inmutable()` y `abortar_si_falla(jsonb)`) frente a `PUBLIC`/`anon`/`authenticated`/`service_role`; acceso exclusivo del owner vía funciones (modelo Opción A de OPS). Resuelve el "GRANTs/RLS a decidir" de D-9C-19.
- **D-PROMO-08** — **Criterio de cierre estructural = huella `TOTAL_CARRIL` (31 objetos) idéntica TEST↔OPS** (`f5187092083451ceb5b182334bdb4a17`), por doble corrida del mismo script simétrico (sin nada embebido).
- **D-PROMO-09** — **Smokes K2 read-only puros: no ejecutar escritura 9H ni siquiera bajo ROLLBACK** (`nextval` no es transaccional y consumiría secuencias reales); se preservan las tablas 9H vacías y las secuencias en 1 para que la **primera liquidación real arranque en 1**.
- **D-PROMO-10** — **Gate de orden de promoción embebido en el helper 9B**: `abortar_si_falla` se crea **último**, exigiendo `registrar_pago` por firma exacta + 9H completo + 9G intacto + helper ausente; con `SET search_path=public,pg_temp` + `REVOKE EXECUTE` (paridad D-7B-05).
- **D-PROMO-11** — **Port del workflow 3b a OPS** (`vita_w09_cobranza_posterior`, 14 nodos) + listado de saldos read-only, revisando marcadores de entorno embebidos en el código, no solo la credencial (L-8D-03).
- **D-PROMO-12** — **Bump único v1.8.0** (sección 24 + PARTE C C0–C14, cuerpos post-K1) **excluyendo la maquinaria de promoción** (gates/asserts/snapshots/reversiones quedan en los `PROMO_BLOQUE_*` + cierres); PARTE C verificada en bootstrap fresco.
- **D-PROMO-13** — **DEV fuera del alcance** de la promoción TEST→OPS; se reconstruirá posteriormente desde cero a partir del canónico v1.8.0 (Parte B + Parte C, `ambiente='dev'`).

---

## 7. Reconciliación con decisiones conceptuales (no duplicar)

Estas decisiones del modelo **conservan su código `D-9x`**; la promoción las **aplica/materializa**, no las reemplaza:

- **Centavo residual** → **D-9E-08** (transportada y reverificada: reparto Σ exacto al centavo en OPS). No es D-PROMO.
- **Beneficiarios por nombre** → **D-9C-20**; **`Socio 3`→`Remo`** → **D-9C-21**. Referenciadas desde D-PROMO-04 (materialización en el Bloque 21 del canónico).
- **Pool de activaciones (D-9D-10), matriz dinámica (9E), clases de gasto A/C/D/E (9F) y toda la capa con estado de 9H** → **no se renombran como D-PROMO**; viajaron por DDL sin cambio de diseño.

---

## 8. Lecciones de la promoción (L-PROMO-01 a L-PROMO-08)

Lecciones de promoción, validación y documentación (no de arquitectura productiva).

- **L-PROMO-01** — El DDL congelado en cierres markdown puede **driftar cosméticamente** del DDL vivo; la **huella `def` normalizada** (`md5` de `pg_get_functiondef` quitando `\r` y formato) lo detecta sin ruido.
- **L-PROMO-02** — `ALTER DEFAULT PRIVILEGES` de Supabase deja grants residuales `Dxtm` en tablas creadas bajo ese contexto; `REVOKE ALL` explícito los saca.
- **L-PROMO-03** — Barrer nodos *code* de n8n por **substring**, no por límite de palabra: `n8n_test_` no matchea `\btest\b` y se escapa de un barrido por `\b`.
- **L-PROMO-04** — Para certificar paridad estructural entre dos entornos Supabase: **doble corrida del mismo script simétrico** (nada embebido), comparando una fila-huella agregada (`TOTAL_CARRIL`) + filas por objeto que localizan la diferencia; ACL por su **texto** (nombres de rol iguales, owner=postgres en ambos), sin OIDs. Generaliza L-PROMO-01.
- **L-PROMO-05** — En smokes post-promoción sobre OPS real, **no ejecutar funciones de escritura con secuencias ni bajo ROLLBACK**: `nextval` no es transaccional y consume secuencias reales; validar solo lectura + helpers con JSON sintético para no contaminar el arranque en 1. Relaciona L-9H-03.
- **L-PROMO-06** — **Snapshot baseline read-only doble (evidencia + hardened) con gate por seed antes de habilitar DDL** en un entorno real; el baseline de EXECUTE debe contemplar `proacl IS NULL ⇒ PUBLIC ejecuta` y excluir extensiones por `pg_depend deptype='e'`. Relaciona L-7E-01 / L-8A-02.
- **L-PROMO-07** *(validación/documentación)* — **Finales de línea heterogéneos/mezclados en los satélites** exigen detección por archivo leyendo bytes en Python (`b.count(b'\r\n')` vs `b.count(b'\n')`), no `grep $'\r'` (bajo `sh`/dash no expande ANSI-C quoting → falso "LF" global); en archivos mixtos, anclar el `str_replace` al terminador **real de la región del ancla**.
- **L-PROMO-08** *(validación/documentación)* — **Harness PostgreSQL local como banco de pre-validación** del bootstrap del canónico (Parte B + Parte C) antes de tocar el doc; PG16 local no tiene el privilegio `MAINTAIN(m)` ni `pg_cron` (OPS real PG17 sí), y los roles cluster-level `anon`/`authenticated`/`service_role` sobreviven a `DROP SCHEMA` (limpiar con `DROP ROLE IF EXISTS` antes de re-seedear). Extiende L-9G-04.

---

## 9. Estado final

- **Carril B vivo en OPS**: 9 tablas + 2 columnas + 21 funciones + 10 triggers + 6 secuencias + marcador `ambiente='ops'` + helper 9B, todo cerrado al Data API.
- **Canónico `6B_SCHEMA_SQL.md v1.8.0`**: incorpora el Carril B como capa real (sección 24 + PARTE C), autocontenido y apto para bootstrappear un entorno de cero.
- **TEST = OPS** por huella estructural (`TOTAL_CARRIL` idéntica). TEST conserva sus fixtures de laboratorio; OPS arranca limpio (tablas 9H vacías, secuencias en 1).
- **DEV** queda temporalmente atrás, fuera del alcance de esta promoción.
- El **carril fiscal/legal** (AFIP/ARCA/IVA, facturación, asientos formales) sigue **fuera de alcance** por diseño.

---

## 10. Pendientes y handoff

- **Reconstrucción de DEV desde v1.8.0** (cuenta Supabase nueva): etapa posterior separada; levantar DEV de cero con Parte B + Parte C y `ambiente='dev'`. Registrado en `Pendiente_pre_produccion.md`.
- **Decisiones de negocio del Carril B — cerradas (2026-06-14):**
  - **% operativo = 25%** (D-NEG-01): se calcula sobre los **ingresos cobrados del período** (caja percibida, D-9G-03) **después de restar los gastos operativos/Carril B**. Las funciones lo reciben por parámetro (D-9G-01); 25% es su valor de negocio vigente.
  - **Inicio contable del Carril B = 2026-07-01** (D-NEG-02): los períodos anteriores a julio 2026 quedan **fuera de alcance contable operativo** (no se liquidan, no se arrastran, no se recontabilizan; etapa previa al inicio oficial). El arranque de junio (pool vacío) queda fuera de alcance: no requiere `ajuste_arranque` ni congelado (D-9H-06 / D-9H-27 siguen como capacidad de código, sin ejercerse para pre-julio).
  - Ambas reglas son **revisables por decisión de socios más adelante**, pero **no son pendientes para operar ahora**.
- **`gastos` legacy**: conservada/congelada (ver §3); no requiere acción. El Carril B opera sobre `gastos_internos`.
- **Primera liquidación real** en OPS: arrancará en id 1 (secuencias preservadas). La carga operativa real (gastos, snapshots, movimientos) es trabajo posterior del equipo.

---

## 11. Deltas para documentos satélite (aplicar con este cierre)

> El 6° satélite, `6B_SCHEMA_SQL.md`, **ya quedó hecho en M (v1.8.0)** y no se toca. Los otros 5 se actualizan preservando el final de línea por archivo (L-PROMO-07).

- **`ESTADO_ACTUAL_VITA_DELTA.md` (CRLF)** — La "Etapa actual" (Carril B cerrado en TEST, nada en OPS) pasa a "Etapa previa"; nueva "Etapa actual" = promoción a OPS + v1.8.0. **Consistencia:** actualizar todas las afirmaciones de estado obsoletas (canónico vigente → v1.8.0; "no canónico / solo en TEST / no promovido a OPS" → promovido); marcar la promoción como hecha en "Próxima etapa"; sumar este cierre a "Documentación viva"; nota DEV. Los snapshots fechados (p. ej. "Estado de OPS al cierre de 8A") quedan como históricos, con nota opcional de que OPS fue extendido con el Carril B en junio 2026.
- **`DECISIONES_NO_REABRIR.md` (LF)** — Nueva sección "## Promoción Carril B a OPS — cerrada 2026-06-14" con la **versión sintética** de D-PROMO-01..13 + reconciliación (D-9C-20/21, D-9E-08). Nota en la sección Carril B existente de que ahora está en OPS / v1.8.0. El detalle largo A→M vive en este cierre, no duplicado. Además, sección "## Reglas de negocio del Carril B — cerradas 2026-06-14" con **D-NEG-01** (% operativo 25%) y **D-NEG-02** (inicio contable 2026-07-01).
- **`Lecciones_Aprendidas.md` (MIXTO → CRLF al final)** — Nueva sección "## Lecciones de la promoción a OPS (L-PROMO-XX)" con L-PROMO-01..08, **append al final** (región CRLF).
- **`Pendiente_pre_produccion.md` (LF)** — Marcar **CERRADA** la sección "Promoción coordinada del Carril B a OPS", referenciando este cierre; nuevo pendiente "Reconstrucción de DEV desde v1.8.0". (Los dos pendientes de negocio —% operativo, política de arranque— quedaron **cerrados** en D-NEG-01/02, ver `DECISIONES_NO_REABRIR.md`.)
- **`CLAUDE.md` (LF)** — Nueva entrada en "## Estado del proyecto" (Carril B en OPS + v1.8.0); actualizar "Schema canónico actual" → v1.8.0; marcar la promoción como hecha en "Próxima etapa"; opcional: sumar L-PROMO-01 (huella `def` normalizada) y L-PROMO-03 (barrido por substring) a las reglas operativas.

---

## 12. Inventario de artefactos / fuentes

- **Artefactos de promoción (SQL):** `PROMO_BLOQUE_A_BIS_SNAPSHOT_v2.sql`, `PROMO_BLOQUE_B1_9C_OPS.sql`, `PROMO_BLOQUE_C_9D_OPS.sql`, `PROMO_BLOQUE_D_9E_OPS.sql`, `PROMO_BLOQUE_E_9F_OPS.sql`, `PROMO_BLOQUE_F_9G_OPS.sql`, `PROMO_BLOQUE_G_9H_ESTRUCTURA_OPS.sql`, `PROMO_BLOQUE_H_9H_FUNCIONES_OPS.sql`, `PROMO_BLOQUE_I_HELPER_9B_OPS_v2.sql`, `PROMO_BLOQUE_J_HARDENING_SWEEP_OPS.sql`, `PROMO_BLOQUE_K1_FINGERPRINT_ESTRUCTURAL.sql`, `PROMO_BLOQUE_K1B_PARCHE_FUNCIONES_OPS.sql`, `PROMO_BLOQUE_K1B_REVERT_FUNCIONES_OPS.sql`, `PROMO_BLOQUE_K2_SMOKES_READONLY_OPS.sql`, `PARCHE_TEST_LIMPIEZA_ACL_TABLAS.sql`, y los auxiliares `PROMO_K1_FINGERPRINT/DUMP/LOCALIZADOR`.
- **Workflow:** `vita_w09_cobranza_posterior__OPS` (14 nodos) + listado de saldos read-only; template sanitizado `vita_w09_cobranza_posterior__TEMPLATE.json`.
- **Cierres de sub-etapa (referencia de diseño):** `9B_CIERRE.md` … `9H_CIERRE.md`.
- **Canónico:** `6B_SCHEMA_SQL.md v1.8.0` (sección 24 + PARTE C + changelog v1.7.3 → v1.8.0).
- **Este cierre:** `PROMOCION_CARRIL_B_OPS_CIERRE.md` (ubicar en `Docs/Bitacora/Promocion/`).

---

*Cierre N — promoción del Carril B a OPS + canónico v1.8.0. Decisiones `D-PROMO-01..13` lockeadas; lecciones `L-PROMO-01..08`. Las decisiones conceptuales 9C→9H conservan su numeración `D-9x` y no se reabren.*
