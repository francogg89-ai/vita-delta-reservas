# ETAPA 9G — CASCADA DE LIQUIDACIÓN READ-ONLY — CIERRE

**Estado:** ✅ **Cerrada y verificada en TEST.** Completa la capa **derivada** del Carril B (composición ingreso → gastos → matriz → saldos por período). Queda pendiente 9H (saldos acumulados entre períodos, retiros, revaluación) para el cierre total del carril.
**Entorno de validación:** TEST (`vita-delta-test`) — IDs de cabaña 1–5.
**Entorno de operación:** — (9G **no** se promovió a OPS; promoción diferida a la operación coordinada única de todo el Carril B, por DDL y **sin copiar datos**).
**Fecha de cierre:** 2026-06-11.
**Base conceptual:** `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md` (v0.8) — §4 (cascada de 11 pasos), §4.2 (equivalencia de deducción C), §4.3 (5% post-operativo), §5 (matriz dinámica), §6 (clase ⇒ momento + alcance), §7.3 (override), §8 (tabla práctica). Documento de encuadre: `PROMPT_ETAPA_9G_CASCADA.md`. 9G no tiene conceptual propio.

---

## 1. Resumen ejecutivo

9G construyó y validó las **seis funciones read-only** que derivan la liquidación mensual completa del Carril B **sin persistir nada**: cada llamada compone ingreso percibido (`pagos`), gastos internos (9F), matriz dinámica y reparto (9E), seam de beneficiario (9C) y activaciones (9D), y devuelve la cascada de 11 pasos y el saldo por socio del período. No hay tablas nuevas, no hay liquidaciones guardadas, no hay snapshot: cambiar un dato fuente re-deriva todo el pasado y el futuro de forma coherente.

La validación reprodujo **al centavo** el ejemplo numérico aprobado en diseño (julio @25%: base de ganancia $456.150; Remo $154.800,80 con residual; Franco y Rodrigo $120.674,60), demostró la incidencia patrimonial con cabaña fuera del pool (termotanque de Guatemala en agosto → Franco $-180.000), el empate de matriz resuelto por D-9E-08 (noviembre: residual a Franco por menor id, no a Rodrigo), el gasto de zona repartido entre activas (jardín de chicas → Franco/Remo $15.000 c/u), y la **anomalía de arranque real** de la caja percibida: junio con $1.345.000 ingresados y pool vacío — pasos 1–8 computan, nadie recibe (D-9G-03 a la vista, con datos reales).

Único write de la etapa: un seed de 5 pagos de laboratorio (Bloque B v2, 9 gates que pinearon la foto del Bloque A antes de escribir). Todo lo demás fue read-only o DDL de funciones con gate programático de ambiente por run.

**Veredictos en TEST:** Bloque A `VERDE (FALLO=0 · OK=28 · INFO=29)` · Bloque B v2 `RUN 0 APTO (9/9) → INSERT 5 → RUN 2 VERDE (10 OK)` · Bloque C v2 `10/10 runs OK` · Bloque D `VERDE (40 OK / 0 FALLO)` · Bloque E `VERDE (13 OK / 0 FALLO / 1 INFO)`.

---

## 2. Qué quedó construido en TEST

Seis funciones `LANGUAGE sql STABLE SECURITY INVOKER`, sin vistas, sin tablas, con `REVOKE ALL FROM PUBLIC, anon, authenticated, service_role` (solo `postgres`/owner las ejecuta hoy; el GRANT operativo se decide en la promoción coordinada):

| Función | Firma | Qué devuelve |
|---|---|---|
| `cascada_periodo` | `(p_periodo DATE, p_pct_operativo NUMERIC)` | Los 11 pasos del período: 1–8 una fila c/u (agregados, `id_socio NULL`), 9/10/11 fila por socio. Guard de pct inválido: una fila `paso=0`. |
| `saldo_socios_periodo` | `(p_periodo DATE, p_pct_operativo NUMERIC)` | Por socio: `saldo_bruto` (paso 9), `gastos_d`, `gastos_e` (negativos), `saldo_final` (= paso 11), `desembolsado_periodo` (informativo D-9G-09). |
| `incidencia_gasto` | `(p_id_gasto BIGINT)` — **sin pct** | Incidencia estructural de un gasto puntual: A → 1 fila `pool_pre_operativo`; C → exacto por matriz; D → activas de zona por `valor_relativo` → seam; E → beneficiario. No derivable ⇒ 0 filas. |
| `reporte_overrides_periodo` | `(p_periodo DATE)` | Gastos con `clase IS DISTINCT FROM clase_sugerida` (incluye sin sugerencia). |
| `reporte_5_vs_fiscal_periodo` | `(p_periodo DATE)` | Extra confirmado del mes vs etiqueta literal `monotributo` (lower/btrim, patrón D-9F-09). Siempre 1 fila. |
| `gastos_sin_incidencia_periodo` | `(p_periodo DATE)` | A/C con pool vacío (`pool_vacio`) y D con zona sin activas (`zona_sin_activas`). E nunca aparece. |

`p_periodo` se normaliza a inicio de mes en todas (validado: día 15 ≡ día 1).

### 2.1 La cascada con julio @0.25 como referencia

| Paso | Concepto | Regla | Julio 2026 |
|---:|---|---|---:|
| 1 | ingreso operativo | `sena`+`saldo` confirmados del mes (caja percibida) | +670.200,00 |
| 2 | gastos clase A | − (solo si pool no vacío, D-9G-06) | −40.000,00 |
| 3 | base operativa | 1+2 | 630.200,00 |
| 4 | retribución operativo | `−ROUND(GREATEST(p3,0) × pct, 2)` — único clamp | −157.550,00 |
| 5 | resultado post-operativo | 3+4 | 472.650,00 |
| 6 | ingresos extra | `extra` confirmados del mes (5% transferencia) | +8.500,00 |
| 7 | gastos clase C | − (solo si pool no vacío) | −25.000,00 |
| 8 | base de ganancia | 5+6+7 (con signo, sin clamps) | 456.150,00 |
| 9 | reparto por matriz | `repartir_por_matriz(mes, p8)` — residual D-9E-08 | Remo 214.800,80 · Franco 120.674,60 · Rodrigo 120.674,60 |
| 10 | incidencias D+E | por socio, negativas (D: activas de zona; E: seam) | Remo −60.000,00 |
| 11 | saldo final | 9+10, universo D-9G-08 | Remo 154.800,80 · Franco 120.674,60 · Rodrigo 120.674,60 |

Conservación verificada: Σ paso 9 = paso 8 ($456.150,00 exacto).

### 2.2 Los otros tres meses validados

- **Agosto:** pasos 1–8 en 0; paso 9 = 3 filas de 0,00 (pool 378 vigente); paso 11: **Franco −180.000** — el termotanque de Guatemala incide en su beneficiario aunque la cabaña esté desactivada (E = patrimonial, seam independiente de activación). Rodrigo figura con `desembolsado_periodo=180.000` (pagó él; la deuda Rodrigo↔Franco se deriva en 9H, no acá).
- **Noviembre:** matriz de 5 activas (pool 456), empate Franco=Remo=178 → residual $0,01 a **Franco** (menor id, D-9E-08 — no a Rodrigo); D jardín de chicas repartido Guatemala+Tokio (78=78) → Franco/Remo $15.000 c/u. Paso 11: Franco 58.483,56 · Remo 58.483,55 · Rodrigo 41.282,89.
- **Junio (datos reales):** $1.345.000 percibidos + $15.150 extra con pool vacío → pasos 1–8 computan (base de ganancia $1.023.900), pasos 9–11 **sin filas**. Es la consecuencia documentada de D-9G-03: la liquidación de ese dinero es **política de arranque entre socios, fuera del sistema** (ver §8).

### 2.3 Extremos y guards validados

`pct=0` → operativo cobra 0, p8=613.700. `pct=1` → base de ganancia **negativa** (−16.500) repartida con signo por la matriz (Remo −7.769,84 · Franco/Rodrigo −4.365,08), Remo arrastra además la E (paso 11 = −67.769,84): D-9G-07 sin clamps debajo del paso 4, saldos negativos visibles. Guards: `pct=1.5`, `pct=NULL`, `pct=-0.1` → una fila explícita `PARAMETRO_INVALIDO_PCT_OPERATIVO` (jamás 0 filas mudas).

---

## 3. Bloques ejecutados

| Bloque | Naturaleza | Resultado en TEST |
|---|---|---|
| **A** — Gate + diagnóstico | read-only, 1 statement | VERDE. Foto autoritativa: 26 pagos (todos confirmados, `created_at` solo may/jun), mayo p1=530.000, junio p1=1.345.000/p6=15.150, 1 residuo sin atribución ($100.000, entra igual al paso 1), 13 reservas, md5 `cabanas.activa` = `90e55df2e433c09ee57c06eaa753c618` (= baseline 9F, fórmula validada cruzada). |
| **B v2** — Seed (único write) | INSERT gateado G1–G9 + RUN 0 diagnóstico + RUN 2 verificación | RUN 0: 9/9 gates OK. INSERT 5 (ids 39–43). RUN 2 VERDE: julio 670.200/8.500, noviembre 251.000, agosto vacío a propósito, reales intactos 26/$1.875.000. |
| **C v2** — DDL de las 6 funciones | 10 runs separados, cada uno con gate `DO + RAISE` de ambiente | 10/10 OK. DROP/CREATE separados (quirk del editor), REVOKE de los 4 roles. |
| **D** — Validación numérica | read-only, 1 statement | **VERDE 40/40**: julio canónico al centavo, agosto, noviembre, junio real, extremos pct, guards, coherencia `paso 11 = saldo_final` (0 discrepancias en 3 meses), las 5 incidencias del fixture, los 3 reportes, no-regresión. |
| **E** — No-regresión consolidada | read-only, 1 statement | **VERDE 13/13**: 9C/9D/9E/9F re-pineados contra el Bloque A; estado final 9G; único delta declarado: pagos 26→31. Secuencia de pagos al cierre: 43. |

**Validación de laboratorio (harness):** réplica local PostgreSQL 16 con el DDL exacto de los cierres 9C–9F y datos espejados a los agregados reales del Bloque A. Allí se validaron 56 chequeos previos a cada entrega, los **tests negativos de gates** (pago intruso en julio → B frena nombrando G4/G5/G7; `ambiente='dev'` → C aborta en el primer gate sin tocar funciones), la idempotencia y limpieza del seed, y el **caso positivo de D-9G-06** no ejercitable en TEST sin writes: gastos sintéticos A/C en junio y D en zona sin activas, bajo `BEGIN/ROLLBACK` — la cascada no restó nada (pasos 2/7 en 0, paso 8 inalterado) y el reporte expuso los tres con motivo correcto.

---

## 4. Decisiones (🔒 — no reabrir)

- **D-9G-01** 🔒 — `p_pct_operativo` es **parámetro explícito** (NUMERIC, fracción 0–1), sin default y sin congelar en DB. Parámetro inválido (NULL, <0, >1) ⇒ **fila guard explícita**: en `cascada_periodo`, `paso=0, concepto='PARAMETRO_INVALIDO_PCT_OPERATIVO'` con el valor recibido en `monto`; en `saldo_socios_periodo`, `id_socio NULL, socio='PARAMETRO_INVALIDO_PCT_OPERATIVO'`, montos NULL. Jamás 0 filas mudas por parámetro.
- **D-9G-02** 🔒 — Filtro de pagos: **paso 1** = `tipo IN ('sena','saldo') AND estado='confirmado'`; **paso 6** = `tipo='extra' AND estado='confirmado'`; monto = `monto_recibido`. `reembolso`/`ajuste` quedan **fuera del MVP de la cascada** (hoy 0 en TEST); cuando existan exigirán decisión propia.
- **D-9G-03** 🔒 — **Criterio de caja percibida (cash basis):** el período de un pago es el **mes calendario de `created_at`**. NO es criterio por estadía/devengado; la alternativa queda **DESCARTADA** para el MVP, no diferida. Consecuencias asumidas: (a) cobros previos al arranque del pool caen en períodos sin matriz y **no se reparten por sistema** salvo política de arranque manual entre socios (fuera de 9G) — demostrado con junio real; (b) un cambio futuro de criterio **re-bucketiza toda la historia** (coherente pero retroactivo) y exige re-correr las validaciones. *Precisión técnica:* el bucket usa `date_trunc('month', created_at)` en timezone de sesión (UTC en Supabase); un pago cercano a medianoche de fin de mes (hora argentina) puede bucketizar al mes siguiente. Refinamiento `AT TIME ZONE 'America/Argentina/Buenos_Aires'` diferible y re-derivable.
- **D-9G-04** 🔒 — Retribución del operativo como **número único agregado**: `paso 4 = −ROUND(GREATEST(paso3, 0) × pct, 2)`; el paso 5 es resta exacta. El residual de la **matriz global** existe **solo** en el paso 9 vía `repartir_por_matriz` (D-9E-08); los gastos **D** tienen su propio **residual interno de zona**, definido en D-9G-05.
- **D-9G-05** 🔒 — Expansión de clase **D**: zona → cabañas **activas** de la zona en el período (mismo criterio `@>` rango-mes que la matriz) → pesos `valor_relativo` → `ROUND` por cabaña + **residual interno de la zona** a la cabaña de mayor `valor_relativo` (empate: menor `id_cabana`) → seam → socio.
- **D-9G-06** 🔒 — **Incidencia no derivable NO se resta y se reporta:** A/C con pool vacío no entran a los pasos 2/7 (`pool_vacio`); D con zona sin activas no entra al paso 10 (`zona_sin_activas`); E es siempre derivable (seam, independiente de la activación). `gastos_sin_incidencia_periodo()` es el reporte obligatorio de ese dinero.
- **D-9G-07** 🔒 — **Signos:** `GREATEST(base,0)` existe **únicamente** en el paso 4. Debajo de esa línea, matemática con signo sin clamps; bases de ganancia y saldos negativos se reparten y se muestran tal cual (validado con pct=1).
- **D-9G-08** 🔒 — Universo de socios del período = **matriz ∪ incidencias D/E**. Un socio solo-incidencia entra con `saldo_bruto=0` (caso agosto/Franco).
- **D-9G-09** 🔒 — `desembolsado_periodo` es **informativo**: suma de `gastos_internos` del período con `pagador_tipo='socio'` para ese socio. **No** es deuda ni neteo automático; desembolso ≠ incidencia (la compensación pagador↔incidido es materia de 9H).
- **D-9G-10** 🔒 — El entregable es un **set de 6 funciones** `LANGUAGE sql STABLE SECURITY INVOKER`, sin vistas, sin tablas, sin persistencia de liquidaciones, con REVOKE de PUBLIC/anon/authenticated/service_role.
- **D-9G-11** 🔒 — Lado fiscal del reporte 5-vs-fiscal: etiqueta **literal** `'monotributo'` (lower/btrim, patrón D-9F-09).
- **D-9G-12** 🔒 — Seed de pagos por **INSERT directo** como excepción de laboratorio (sin `registrar_pago()`): 5 pagos marcados `source_event` con prefijo `seed_9g_`, gates reforzados **G1–G9** que pinearon la foto completa del Bloque A antes del write (conteos, sumas globales, pin por mes, ningún pago real fuera de may/jun), RUN 0 diagnóstico por gate + re-validación atómica en el WHERE, borrable por marcador, sin reset de secuencia (D-9F-21).
- **D-9G-13** 🔒 — **Fixtures de laboratorio con distorsión declarada, conservados hasta 9H:** (a) los 5 pagos `seed_9g_%` (ids 39–43) quedan **vivos en TEST** como banco de prueba para 9H; (b) son **fixture técnico, no datos reales**; (c) **distorsionan los saldos derivados de las reservas 5/6/7/10** mientras existan, y eso queda aceptado y documentado; (d) **no viajan a OPS bajo ninguna circunstancia**; (e) la promoción coordinada recrea estructura y funciones **por DDL, no copia datos** de TEST; (f) el DELETE por marcador queda **documentado, no ejecutado** (`DELETE FROM pagos WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\';`). Asimismo, el fixture 9F de gastos (ids 30–34, D-9F-17 "hasta 9G") **se extiende hasta 9H** con las mismas condiciones: ambos fixtures forman un único banco coherente — la cascada de jul/ago/nov reproduce el ejemplo canónico solo con ambos vivos. El run D.R de 9F (§6 de su cierre) sigue documentado y no ejecutado. Al abrir o cerrar 9H se decide el destino conjunto.
- **D-9G-14** 🔒 — `incidencia_gasto()` para clase **A** devuelve **una fila estructural** `destino='pool_pre_operativo'` con el monto completo, **sin expansión por porcentajes**: con `GREATEST` en el paso 4, la incidencia marginal de un gasto A es contextual al período entero (régimen positivo / negativo / cruce de cero) y una expansión fija sería una aproximación con régimen de validez. La absorción efectiva se ve en `cascada_periodo`. Consecuencia: la firma pierde el pct. Asimetría deliberada y documentada con C, que **sí** expande por socio en forma exacta (lineal pura debajo de la línea, §4.2; centavos vía `repartir_por_matriz`).

---

## 5. Lecciones aprendidas

- **L-9G-01** — Los marcadores con underscore exigen **LIKE escapado**: `source_event LIKE 'seed\_9g\_%' ESCAPE '\'` — `_` es comodín de un carácter en LIKE. Aplica a chequeos de presencia/ausencia y al DELETE de limpieza. Sin escape, el patrón matchea de más (falsos positivos plausibles en gates).
- **L-9G-02** — **Todo run DDL lleva gate programático de ambiente como primer statement** (`DO $$ ... RAISE EXCEPTION ... $$`); la protección por comentario de header no es protección. La etapa usó los tres sabores del mismo principio: chequeo con veredicto (A), condición en el WHERE del write (B), `DO + RAISE` que aborta el batch (C). Validado en laboratorio: con `ambiente='dev'` el primer gate aborta y las funciones quedan intactas.
- **L-9G-03** — Ante un write con muchos gates en el WHERE, un `INSERT 0 0` no dice **cuál** falló. Patrón: **RUN 0 read-only de diagnóstico** (una fila OK/FALLO por gate) + re-validación atómica de los mismos gates en el WHERE del write. El diagnóstico no reemplaza al enforcement ni viceversa.
- **L-9G-04** — **Harness local** (réplica PostgreSQL con el DDL exacto de los cierres + datos espejados a los agregados reales) permitió: validar cada bloque antes de entregarlo (56 chequeos del C), ejercitar tests negativos de gates imposibles de correr en TEST, y cubrir casos que exigirían writes en TEST mediante datos sintéticos bajo `BEGIN/ROLLBACK` (caso positivo de D-9G-06). El costo es mantener la fidelidad del espejo; el retorno fue cero FALLOs en TEST en los cinco bloques.

---

## 6. Estado de los datos de laboratorio en TEST (al cierre)

| Banco | Filas | Ids | Marcador | Borrado documentado |
|---|---|---|---|---|
| Pagos seed 9G | 5 | 39–43 | `source_event LIKE 'seed\_9g\_%' ESCAPE '\'` | Apéndice de `9G_BLOQUE_B_SEED_v2.sql` — **no ejecutado** |
| Gastos fixture 9F | 5 | 30–34 | `creado_por='seed_9f_validacion'` | Run D.R en `9F_CIERRE.md` §6 — **no ejecutado** |

Pagos reales intactos: 26 filas, $1.875.000 en sena+saldo confirmados. Caja percibida al cierre: 2026-05 → 530.000/0 · 2026-06 → 1.345.000/15.150 · 2026-07 → 670.200/8.500 (seed) · 2026-08 → vacío (a propósito) · 2026-11 → 251.000/0 (seed). Secuencias: `pagos`=43, `gastos_internos`=34, `gastos` legacy virgen.

---

## 7. Supuestos explícitos y límites del MVP

1. **Timezone del bucket mensual** (precisión de D-9G-03): UTC de sesión, refinamiento argentino diferible y re-derivable.
2. **`reembolso`/`ajuste`**: fuera del MVP de la cascada; hoy inexistentes en TEST; al aparecer, decisión propia (¿netean paso 1? ¿paso 6? ¿línea aparte?).
3. **`incidencia_gasto` clase C standalone** puede diferir hasta ±$0,01 por socio respecto del efecto incremental del mismo gasto dentro de la cascada (no-linealidad del redondeo entre dos repartos); es diagnóstico por gasto, no resta contable — la cifra contable vive en la cascada.
4. **Cobertura de `gastos_sin_incidencia_periodo`**: el caso positivo (pool_vacio / zona_sin_activas) quedó validado en laboratorio bajo ROLLBACK; en TEST solo se ejercita el caso negativo (0 filas en jul/ago/nov) porque el fixture no tiene gastos en meses sin pool. Si 9H siembra gastos en meses sin matriz, re-ejercitar allí.
5. **Permisos**: las 6 funciones quedan ejecutables solo por owner; el GRANT operativo (¿`service_role` para n8n?) se decide en la promoción coordinada, no antes.

---

## 8. Pendientes y handoff a 9H

1. **Política de arranque (decisión de socios, fuera del sistema):** junio 2026 tiene base de ganancia derivada de $1.023.900 sin destinatarios (pool vacío). El sistema lo muestra y no lo reparte (D-9G-03/06). Los socios deben decidir qué hacer con ese dinero (reparto manual externo, o convención de arranque); cualquier mecanismo dentro del sistema sería materia de una decisión nueva, no de 9G.
2. **Valor real del % operativo:** las funciones lo reciben por parámetro; los socios deben fijar el número (las validaciones usaron 0,25 como valor de trabajo, sin carácter normativo).
3. **9H — saldos acumulados, retiros, revaluación** (`PENDIENTE_CARRIL_B_9H_SALDOS_RETIROS_REVALUACION.md`): acumulación entre períodos, compensación pagador↔incidido (la deuda Rodrigo↔Franco del termotanque, Remo↔Rodrigo de las horas), retiros de socios, revaluación. 9G le deja: las 6 funciones como fuente derivada por período, el banco de laboratorio vivo (ambos fixtures), y junio como caso real de arranque.
4. **Promoción coordinada a OPS** (sin fecha): paquete único por DDL — objetos 9C (columnas, zonas, seam) + 9D (activaciones) + 9E (3 funciones) + 9F (`gastos_internos`) + 9G (6 funciones) + `abortar_si_falla` + workflow `cobranza_posterior_3b`. **Sin datos de TEST.** Incluye decidir GRANTs operativos y RLS (pendiente de hardening).
5. **Estado de las 4 preguntas abiertas del conceptual:** (1) titularidad por período — la costura existe (`resolver_beneficiario(id, fecha)` ya recibe fecha; hoy resuelve fecha-independiente); activarla exigirá la tabla de titularidad temporal, materia futura; (2) centavo residual — **resuelto** (D-9E-08 reparto; D-9G-05 zona); (3) valoración horaria del trabajo de socio — **resuelto como manual** (D-9C-03 / 9F: gasto E valorizado a mano); (4) átomo de la matriz — **resuelto: mes calendario** (9E/9G operan por mes normalizado).

---

## 9. Deltas para documentos satélite (aplicar con este cierre)

- **`ESTADO_ACTUAL_VITA_DELTA.md`**: Carril B derivado completo (9C→9G cerradas); próxima etapa 9H; las 6 funciones de cascada vivas en TEST; fixtures conservados; nada nuevo en OPS.
- **`DECISIONES_NO_REABRIR.md`**: agregar D-9G-01 … D-9G-14 (🔒).
- **`Lecciones_Aprendidas.md`**: agregar L-9G-01 … L-9G-04.
- **`Pendiente_pre_produccion.md`**: el paquete coordinado a OPS ahora incluye las 6 funciones 9G; recordatorio explícito: los fixtures (`seed_9g_%`, `seed_9f_validacion`) **no viajan**; GRANTs/RLS de las funciones a decidir en la promoción.
- **`CLAUDE.md`**: actualizar estado de etapa (9G cerrada; abrir conversación nueva para 9H).

---

## 10. Inventario de artefactos de la etapa

| Archivo | Rol | Estado |
|---|---|---|
| `9G_BLOQUE_A_DIAGNOSTICO.sql` | Gate + foto autoritativa de TEST | Ejecutado, VERDE |
| `9G_BLOQUE_B_SEED_v2.sql` | Seed con gates G1–G9 + RUN 0 + verificación + DELETE documentado | Ejecutado, VERDE (v1 descartada: sin gates de foto) |
| `9G_BLOQUE_C_FUNCIONES_v2.sql` | DDL de las 6 funciones, 10 runs con gate DO de ambiente | Ejecutado, 10/10 (v1 descartada: sin gate programático) |
| `9G_BLOQUE_D_VALIDACION.sql` | Batería numérica (40 chequeos) | Ejecutado, VERDE 40/40 |
| `9G_BLOQUE_E_NO_REGRESION.sql` | No-regresión consolidada (13 chequeos) | Ejecutado, VERDE 13/13 |
| `9G_CIERRE.md` | Este documento | — |

Los `.sql` se commitean al repo tal cual (no contienen credenciales ni ids de instancia). Las versiones v1 de B y C no se commitean.

---

*Cierre redactado el 2026-06-11. Etapa ejecutada íntegramente por Franco en TEST sobre propuestas verificadas en harness local; Claude no tocó Supabase ni n8n.*
