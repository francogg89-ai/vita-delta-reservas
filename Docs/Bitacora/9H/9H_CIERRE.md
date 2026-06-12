# ETAPA 9H — CUENTA CORRIENTE INTERNA (CAPA CON ESTADO) — CIERRE

**Estado:** ✅ **Cerrada y verificada en TEST.** Es la **última sub-etapa del Carril B**; con ella el **Carril B / contabilidad operativa interna queda completo** en TEST (capa derivada 9C–9G + capa con estado 9H).
**Entorno de validación:** TEST (`vita-delta-test`) — IDs de cabaña 1–5.
**Entorno de operación:** — (9H **no** se promovió a OPS; promoción diferida a la operación coordinada única de **todo** el Carril B, por DDL y **sin copiar datos**).
**Fecha de cierre:** 2026-06-12.
**Base conceptual:** `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md` (v0.8) y `PENDIENTE_CARRIL_B_9H_SALDOS_RETIROS_REVALUACION.md` (breadcrumb de encuadre). 9H no tiene conceptual propio; su dirección vive en el conceptual del Carril B.
**Depende de:** 9C (catálogo + zonas + seam), 9D (activaciones), 9E (matriz + reparto), 9F (`gastos_internos`) y 9G (las 6 funciones de cascada read-only) — las cinco cerradas en TEST. 9H **congela** la salida de 9G; no la reemplaza.
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` — **NO modificado** (sin bump; el bump único se hace en la promoción coordinada).
**Autores:** Franco (titular, ejecutor de todos los writes en TEST) + Claude (arquitecto; no tocó Supabase ni n8n).
**Decisiones registradas:** D-9H-01 a D-9H-38. **Lecciones:** L-9H-01 a L-9H-04.

---

## 1. Resumen ejecutivo

9H materializó la **capa con estado** del Carril B: lo que 9C–9G derivan en vivo sin persistir nada, 9H lo **congela** en el momento que se decide cerrar un período, y le agrega lo que **no** es derivable de los datos fuente — el **mayor de movimientos** del socio (retiros, ajustes, reversas, retribución operativa) y la **revaluación ARS→USD**. La capa derivada responde "cuánto da el período X si lo calculo hoy"; la capa con estado responde "cuánto se cerró, cuánto se llevó cada socio y cuál es su saldo vivo acumulado".

Se construyeron **cinco tablas** (`liquidaciones_periodo`, `liquidacion_cascada`, `liquidacion_socio`, `movimientos_socio`, `revaluaciones`) bajo dos garantías estructurales fuertes: **append-only por triggers** de inmutabilidad (anti UPDATE/DELETE/TRUNCATE en las cinco) y **cadena de supersesión lineal** (re-snapshot sin borrar la foto anterior, con una sola raíz y una sola cola vigente por período, garantizadas por índices parciales únicos + FK compuesta de mismo-período). El **saldo vivo** nunca se almacena: es la fórmula D-9H-12 (`saldo_final + desembolsado_periodo + Σ movimientos`), con las tres fuentes en columnas separadas y la suma viviendo solo en la función `saldo_corriente_socio`. La **pertenencia de socio** de reversas y conversiones también es estructural (FK compuestas `(id_movimiento, id_socio)`): una reversa o una conversión no se pueden vincular al movimiento de otro socio.

Sobre esa estructura, **nueve funciones** (cuatro de lectura `STABLE`, cinco de escritura `VOLATILE` solo-INSERT con advisory locks) encapsulan toda la lógica de congelado, retiro con guard de saldo vivo, movimientos manuales, reversa de monto opuesto y revaluación ligada con tope acumulado.

La validación reprodujo **al centavo** los canónicos de 9G una vez congelados: julio @25% (Franco/Rodrigo $120.674,60; Remo $154.800,80 con gasto E de $60.000 aplicado a Remo), agosto (Franco $-180.000 compensado exactamente por el desembolso de Rodrigo de $180.000 ⇒ Σ neta = 0), noviembre (residual de $0,01 a Franco por menor id, D-9E-08). Demostró además el **mayor de Rodrigo** cerrando en **$351.957,49** con el retiro de $50.000 adentro, la **revaluación** de $30.000 → US$30,00 ligada a ese retiro **sin alterar el saldo vivo**, y **una raíz / una vigente** por período de forma empírica. Los tres saldos vivos finales: **Franco $24.158,16 · Rodrigo $351.957,49 · Remo $213.284,35.**

Metodología estricta respetada: diseño → decisiones numeradas → **harness local PostgreSQL** (réplica con el DDL exacto + stubs fieles de 9G + escenarios rotos sintéticos para los guards) → entrega → Franco ejecuta bloque por bloque en TEST → verificación. Retorno del harness: **cero FALLOs en TEST en los seis bloques.**

---

## 2. Qué quedó construido en TEST

### 2.1 Cinco tablas (capa con estado, append-only)

| Tabla | Rol | Notas estructurales |
|---|---|---|
| `liquidaciones_periodo` | Cabecera de cada foto de cierre + cadena de supersesión | `pct_operativo`, `id_liquidacion_supersede` (NULL = raíz). Índices parciales únicos: una raíz por período, sin forks. FK compuesta `(supersede, periodo)→(id, periodo)` ⇒ la sucesora hereda el período. |
| `liquidacion_cascada` | Los **8 pasos agregados** de la cascada congelados (paso 4 incluido) | PK `(id_liquidacion, paso)`, `CHECK paso BETWEEN 1 AND 8`. |
| `liquidacion_socio` | La fila de 9G **verbatim** por socio | `saldo_bruto`, `gastos_d`, `gastos_e`, `saldo_final`, `desembolsado_periodo` — **columnas separadas** (D-9H-12); CHECK de coherencia `saldo_final = bruto + d + e`. |
| `movimientos_socio` | Mayor append-only del socio | `tipo IN (retiro, adelanto, ajuste_manual, retribucion_operativo, ajuste_arranque, reversa)`; signo, comentario obligatorio y período exigido según tipo; reversa única por movimiento; FK compuesta de mismo-socio. |
| `revaluaciones` | Valuación/conversión ARS→USD fechada (no re-contabiliza) | `monto_usd = ROUND(monto_ars/tipo_cambio, 2)` por CHECK; `id_movimiento_origen` (FK compuesta mismo-socio, nullable: NULL = valuación, no-NULL = conversión ligada). |

- **Inmutabilidad (D-9H-15):** función `trg_9h_inmutable()` + **10 triggers** (`BEFORE UPDATE OR DELETE` row + `BEFORE TRUNCATE` statement, 2 × 5 tablas). Append-only deja de ser disciplina y pasa a ser estructural; el único bypass es DDL visible (DROP del trigger). Limpieza de la capa = **teardown por DROP** (D-9H-20), nunca DELETE.
- **Seguridad:** `REVOKE ALL` de PUBLIC + `anon`/`authenticated`/`service_role` en las 5 tablas, las 3 secuencias y la función de trigger (D-9H-16/21/23). Verificación exhaustiva de los 7 privilegios de tabla y 3 de secuencia.

### 2.2 Nueve funciones (`SECURITY INVOKER`, REVOKE de los 3 roles Data API)

**Lectura (`STABLE`):**

| Función | Firma | Devuelve |
|---|---|---|
| `liquidacion_vigente` | `(p_periodo DATE)` | `BIGINT` — la cola de la cadena del período (no superseded). |
| `saldo_corriente_socio` | `(p_id_socio BIGINT)` | 4 filas (D-9H-12 desglosado): `resultado_liquidacion`, `reembolso_desembolso`, `movimientos`, `saldo_vivo`. |
| `mayor_socio` | `(p_id_socio BIGINT)` | Libro mayor línea por línea con `saldo_acumulado` (liquidación + reembolso + movimientos, orden cronológico). |
| `reporte_retribucion_operativo_periodo` | `(p_periodo DATE)` | Calculado (paso 4 de la foto vigente) vs asignado (Σ `retribucion_operativo` neto de reversas) — anti-duplicación, D-9H-14. |

**Escritura (`VOLATILE`, solo INSERT, advisory locks D-9H-32):**

| Función | Firma | Qué hace |
|---|---|---|
| `registrar_snapshot_periodo` | `(periodo, pct, creado_por, supersede_id DEFAULT NULL, comentario DEFAULT NULL)` | Congela la cascada (8 filas, assert D-9H-35) + socios (0 ó N, assert D-9H-37); re-snapshot explícito (D-9H-24): si ya hay vigente, exige `supersede_id` = cola actual + comentario. Lock por período. |
| `registrar_retiro` | `(id_socio, fecha, monto[>0], medio_pago, creado_por, comentario DEFAULT NULL)` | Guarda `-monto`; **guard de saldo vivo** (bloquea si < 0, permite = 0, D-9H-07/25). Lock por socio. |
| `registrar_movimiento_manual` | `(id_socio, fecha, tipo, monto, creado_por, comentario, periodo DEFAULT NULL, medio_pago DEFAULT NULL)` | 4 tipos manuales (sin guard de saldo: el negativo se logra con `adelanto`/`ajuste_manual`). |
| `registrar_reversa` | `(id_movimiento_revertido, fecha, creado_por, comentario)` | Calcula el monto opuesto internamente (D-9H-28). |
| `registrar_revaluacion` | `(id_socio, fecha, tipo_cambio, monto_ars, alcance, creado_por, id_movimiento_origen DEFAULT NULL, comentario DEFAULT NULL)` | `monto_usd` interno (D-9H-33); conversión ligada solo a `retiro`/`adelanto` (D-9H-34) con tope acumulado (D-9H-29). |

### 2.3 Datos persistidos por la carga (Bloque D, marcador `seed_9h_d`)

Cuatro fotos (julio raíz + julio re-snapshot vigente + agosto + noviembre), 32 filas de cascada, 12 de socio, 1 movimiento (retiro Rodrigo $50.000), 1 revaluación (conversión $30.000 ligada al retiro). IDs en TEST: julio raíz **id8** → vigente **id11** (supersede id8); agosto **id9**; noviembre **id10**; retiro **mov#6**.

---

## 3. Bloques ejecutados (bitácora)

| Bloque | Naturaleza | Resultado en TEST |
|---|---|---|
| **A0** — Gate + diagnóstico | read-only, 1 statement | VERDE (FALLO=0, OK=14). Banco 9F/9G intacto, canónicos de julio al centavo, cero objetos 9H previos. |
| **B.1 v3 / B.2 v3.1** — DDL de estructura + verificación | write (DDL) + read-only | B.1 "Success, no rows" (gate + 5 tablas + 10 triggers + FK compuestas + REVOKE). B.2 v3.1 **VERDE (OK=26)** tras el fix `contype::text` (L-9H-01). |
| **C v3 / verificación v2** — 9 funciones | write (DDL) + read-only | Ejecutado VERDE: 9 firmas exactas, sin overloads, REVOKE de los 3 roles efectivo, ambiente test. |
| **C.3 smokes + postcheck** — efímero (D-9H-38) | `BEGIN…ROLLBACK` + read-only | Smokes **20/20** (3 positivos con 9G real + 17 negativos con SQLSTATE/constraint/MESSAGE exactos). Postcheck VERDE: 0 filas persistidas; secuencias avanzaron por diseño (L-9H-03). |
| **D carga** — persistente (preflight + assert pre-COMMIT) | write | VERDE: 4/32/12/1/1, marcador `seed_9h_d`. El **assert pre-COMMIT** (14 chequeos estructurales) protege la salida antes de hacerla irreversible. |
| **E validación** — read-only consolidada | read-only | **VERDE (FALLO=0, OK=38, INFO=13).** Canónicos jul/ago/nov al centavo, saldos vivos, mayor de Rodrigo, revaluación, una raíz/una vigente, marcador, no-regresión 9C-9G. |

---

## 4. Decisiones registradas (D-9H-01 a D-9H-38) 🔒

**Modelo de snapshot y cadena:**
- **D-9H-01/02** — Snapshot = fila completa de `saldo_socios_periodo` + cascada agregada de 8 pasos + metadatos (pct, creado_por).
- **D-9H-04** — Append-only **estricto**: sin columna `estado`, sin UPDATE; vigencia derivada por `NOT EXISTS` supersesor.
- **D-9H-11 (opción c)** — La foto **congela y muestra** el paso 4 (retribución operativa); el destino se registra después con movimiento `retribucion_operativo`. Sin caja operativa ni asignación automática.
- **D-9H-12** — `saldo_vivo = saldo_final + desembolsado_periodo + Σ movimientos`; columnas separadas, suma solo en `saldo_corriente_socio`.
- **D-9H-24** — Re-snapshot **explícito**: si el período ya tiene vigente, `registrar_snapshot_periodo` falla salvo `supersede_id` = cola actual + comentario obligatorio.
- **D-9H-27** — Permitir congelar junio (cascada 8 pasos, 0 filas de socio: anomalía de arranque real).
- **D-9H-35** — `registrar_snapshot_periodo` exige exactamente 8 filas en cascada (`GET DIAGNOSTICS`).
- **D-9H-37** — Valida filas de socio: 0 (junio) o exactamente `COUNT(socios)`. Salvedad anotada: si una cabaña grande se desactivara, refinar a `WHERE activo`.

**Retiros y movimientos:**
- **D-9H-07** — Saldos negativos por liquidación/incidencia permitidos; un `retiro` que dejaría saldo vivo < 0 va bloqueado por la función; el negativo solo se logra con `adelanto`/`ajuste_manual` + comentario.
- **D-9H-25** — Retiro a saldo exactamente 0 permitido; bloquea solo si < 0.
- **D-9H-18** — `retribucion_operativo` es positivo (acredita); corrección solo por reversa.
- **D-9H-14** — `reporte_retribucion_operativo_periodo` compara calculado (paso 4) vs asignado (Σ neto de reversas).
- **D-9H-28** — La reversa recibe solo id + fecha + comentario + creado_por; la función calcula el monto opuesto.
- **D-9H-31** — Funciones específicas (retiro/reversa/revaluación) + genérica `registrar_movimiento_manual` (4 tipos manuales).

**Revaluación:**
- **D-9H-19** — `revaluaciones.id_movimiento_origen` (FK nullable): NULL = valuación de saldo; no-NULL = conversión ligada.
- **D-9H-29** — Conversión parcial ligada con tope acumulado (Σ `monto_ars` ≤ `|movimiento.monto|`).
- **D-9H-30** — Valuación `total` no atada al saldo vivo en MVP (informativa, no certificada).
- **D-9H-33** — `registrar_revaluacion` calcula `monto_usd = ROUND(monto_ars/tipo_cambio, 2)` internamente.
- **D-9H-34** — Conversión ligada **solo** a `retiro`/`adelanto` (débitos ARS entregados al socio); excluye los demás tipos.

**Inmutabilidad, integridad y seguridad:**
- **D-9H-15** — Inmutabilidad estructural: triggers `BEFORE UPDATE OR DELETE` (row) + `BEFORE TRUNCATE` (statement) en las 5 tablas.
- **D-9H-16/21/23** — REVOKE de PUBLIC + 3 roles en tablas, 3 secuencias y la función de trigger; verificación de seguridad exhaustiva (7 privilegios de tabla, 3 de secuencia).
- **D-9H-17** — Reversa única por movimiento (índice parcial único) + validación de monto opuesto.
- **D-9H-20** — Teardown por DROP en orden explícito (revaluaciones → movimientos_socio → liquidacion_socio → liquidacion_cascada → liquidaciones_periodo → función), **sin CASCADE**.
- **D-9H-22** — Pertenencia de socio estructural: `UNIQUE (id_movimiento, id_socio)` como target de FK compuestas en reversa y conversión (MATCH SIMPLE).
- **D-9H-32** — Advisory locks: `pg_advisory_xact_lock(919001, hashtext(periodo))` en snapshot; `(919002, id_socio)` en retiro/movimiento/reversa/revaluación (porque guards y topes son derivados).

**Endurecimiento de escala y pruebas:**
- **D-9H-26** — Doble defensa de pct (validación temprana + filtro en pasos 1-8).
- **D-9H-36** — Rechazo de precisión sub-centavo en ARS (`valor <> ROUND(valor,2)`); `tipo_cambio := ROUND(., 4)` antes de calcular USD (corrige bug latente con TC > 4 decimales); pct rechaza > 4 decimales.
- **D-9H-38** — C.3 efímero: `BEGIN → seed → smokes → veredicto → ROLLBACK`; no persiste filas (las secuencias BIGSERIAL pueden avanzar, sin significado contable).

> El detalle completo de cada decisión se propaga a `DECISIONES_NO_REABRIR.md` con este cierre.

---

## 5. Lecciones aprendidas (para `Lecciones_Aprendidas.md`)

- **L-9H-01** — **Cast `::text` en concatenación de tipos internos.** `pg_constraint.contype` es `"char"` interno; `contype || ', '` no resuelve operador único (ERROR 42725). Hay que castear (`contype::text`) en **concatenación**, no solo en comparación. Pariente de L-9C-02, pero en concatenación.
- **L-9H-02** — **Un smoke negativo que viola dos defensas reporta solo la primera evaluada.** Hay que aislar el caso para validar la defensa correcta (descubierto: una reversa cross-socio sobre un movimiento ya revertido chocaba `uq_mov_reversa_unica` en vez de `fk_mov_reversa_mismo_socio`; el smoke se reescribió sobre un movimiento no revertido).
- **L-9H-03** — **Las secuencias BIGSERIAL avanzan con `nextval` no transaccional bajo ROLLBACK**, y solo si la operación llega a evaluar el serial. Un postcheck de un bloque efímero debe separar filas (transaccionales, deben quedar en 0) de secuencias (no transaccionales, pueden avanzar y no se resetean).
- **L-9H-04** — **Todo `RAISE` de plpgsql es SQLSTATE `P0001`.** Un smoke negativo sobre lógica de función debe verificar el `MESSAGE_TEXT` (fragmento), no solo el SQLSTATE, para no validar la defensa equivocada (todos los guards de función comparten P0001).

---

## 6. Estado de los datos de laboratorio en TEST (al cierre)

| Banco | Filas | Marcador | Limpieza |
|---|---|---|---|
| Capa 9H (carga D) | 4 liq · 32 casc · 12 socio · 1 mov · 1 reval | `creado_por='seed_9h_d'` | **Teardown por DROP** (D-9H-20) — inmutable, NO hay DELETE. Documentado al pie de `9H_BLOQUE_D_CARGA.sql`, **no ejecutado**. |
| Pagos seed 9G | 5 (ids 39–43) | `source_event LIKE 'seed\_9g\_%' ESCAPE '\'` | DELETE por marcador documentado (apéndice de `9G_BLOQUE_B_SEED_v2.sql`), **no ejecutado**. |
| Gastos fixture 9F | 5 (ids 30–34) | `creado_por='seed_9f_validacion'` | Run D.R en `9F_CIERRE.md` §6, **no ejecutado**. |

Los tres bancos forman un único laboratorio coherente: la cascada de jul/ago/nov reproduce el canónico solo con los fixtures 9F/9G vivos, y la carga 9H los congela. **Ninguno viaja a OPS** — la promoción recrea estructura y funciones por DDL, sin datos. La decisión de borrar los fixtures (o conservarlos) se toma en la operación coordinada.

---

## 7. Supuestos explícitos y límites del MVP

1. **Revaluación `total` informativa** (D-9H-30): no se certifica contra el saldo vivo en MVP; es una foto de valuación, no un movimiento.
2. **Conversión ligada solo a `retiro`/`adelanto`** (D-9H-34): los demás tipos no admiten `id_movimiento_origen`.
3. **Timezone del bucket mensual** (heredado de D-9G-03): UTC de sesión; refinamiento argentino diferible y re-derivable (afecta la capa derivada, no la congelada una vez tomada la foto).
4. **`reporte_retribucion_operativo_periodo`** asume que el paso 4 negativo de la foto vigente es la magnitud a asignar; el destino del paso 4 es decisión de socios vía movimiento, nunca automático (D-9H-11).
5. **Permisos:** las 9 funciones y las 5 tablas quedan ejecutables/accesibles solo por owner; el GRANT operativo (¿`service_role` para n8n?) y la exposición Data API se deciden en la promoción coordinada, no antes.
6. **Salvedad de `registrar_snapshot_periodo` (D-9H-37):** el assert "0 ó N socios" asume que todo período con matriz incluye a todos los socios (cierto hoy: cada socio tiene ≥1 cabaña activa desde julio). Si eso cambiara, refinar a `WHERE activo`.

---

## 8. Pendientes y handoff

**9H es la última sub-etapa del Carril B.** No hay más diseño de schema interno pendiente; lo que queda es operación y producto.

1. **Promoción coordinada de TODO el Carril B a OPS** (sin fecha): paquete único por DDL — 9C (columnas, zonas, `cabana_zona`, seam) + 9D (`activaciones_operativas`) + 9E (3 funciones) + 9F (`gastos_internos`) + 9G (6 funciones) + 9H (5 tablas + 10 triggers + 9 funciones) + `abortar_si_falla` + workflow `cobranza_posterior_3b`. **Sin datos de TEST.** Incluye decidir GRANTs operativos y RLS/exposición (pendiente de hardening). Prerequisito: `socios` con Remo y la base 9C ya en OPS (L-9C-01).
2. **Bump único del canónico** `6B_SCHEMA_SQL.md` reflejando todo el Carril B (capa derivada + capa con estado), en el evento de promoción — no antes.
3. **Destino de los fixtures de laboratorio** (`seed_9h_d` por DROP; `seed_9g_%` y `seed_9f_validacion` por DELETE): se decide en la operación coordinada; los DELETE/teardown están documentados y no ejecutados.
4. **Valor real del % operativo:** las funciones lo reciben por parámetro; los socios deben fijar el número (las validaciones usaron 0,25 como valor de trabajo, sin carácter normativo).
5. **Producto (fuera del Carril B):** dashboard manual, bot de WhatsApp, web pública de reservas, integración de webhook de MercadoPago — etapas posteriores, ya sobre el Carril B cerrado.

---

## 9. Deltas para documentos satélite (aplicar con este cierre)

- **`ESTADO_ACTUAL_VITA_DELTA.md`**: Carril B **completo** (9C→9H cerradas y verificadas en TEST); capa con estado viva en TEST (5 tablas + 9 funciones); fixtures conservados; nada nuevo en OPS; próximo hito = promoción coordinada.
- **`DECISIONES_NO_REABRIR.md`**: agregar D-9H-01 … D-9H-38 (🔒).
- **`Lecciones_Aprendidas.md`**: agregar L-9H-01 … L-9H-04.
- **`Pendiente_pre_produccion.md`**: el paquete coordinado a OPS ahora incluye 9H (5 tablas + 10 triggers + 9 funciones); recordatorio explícito: los tres fixtures **no viajan**; GRANTs/RLS de tablas y funciones a decidir en la promoción; bump único del canónico en ese evento.
- **`6B_SCHEMA_SQL.md`**: **no se bumpea en 9H** (sigue v1.7.3); el bump consolidado del Carril B se hace en la promoción. Hasta entonces, los cierres 9C–9H son la fuente autoritativa del schema de Carril B en TEST.
- **`CLAUDE.md`**: actualizar estado de etapa (Carril B cerrado; 9H es la última sub-etapa; abrir conversación nueva para la promoción coordinada o para la primera etapa de producto).

---

## 10. Inventario de artefactos de la etapa

| Archivo | Rol | Estado |
|---|---|---|
| `9H_BLOQUE_B1_v3.sql` | DDL de estructura (5 tablas + 10 triggers + FK compuestas + REVOKE) | Ejecutado, VERDE (entregado inline; v1/v2 descartadas) |
| `9H_BLOQUE_B2_v3.1.sql` | Verificación read-only de estructura (fix `contype::text`) | Ejecutado, VERDE (OK=26) |
| `9H_BLOQUE_C_FUNCIONES_v3.sql` | DDL de las 9 funciones (4 lectura + 5 escritura) | Ejecutado, VERDE |
| `9H_BLOQUE_C_VERIFICACION_v2.sql` | Verificación read-only de firmas/seguridad (9 firmas exactas) | Ejecutado, VERDE |
| `9H_BLOQUE_C3_SMOKES.sql` | Smokes efímeros transaccionales (3 positivos + 17 negativos) | Ejecutado, 20/20 |
| `9H_BLOQUE_C3_POSTCHECK.sql` | Postcheck read-only (0 filas persistidas) | Ejecutado, VERDE |
| `9H_BLOQUE_D_CARGA.sql` | Carga real (preflight + assert pre-COMMIT + teardown documentado) | Ejecutado, VERDE |
| `9H_BLOQUE_E_VALIDACION.sql` | Validación read-only consolidada (38 OK / 0 FALLO / 13 INFO) | Ejecutado, VERDE |
| `9H_CIERRE.md` | Este documento | — |

Los `.sql` se commitean al repo tal cual (no contienen credenciales ni ids de instancia). Las versiones v1/v2 de los bloques iterados no se commitean.

---

*Cierre redactado el 2026-06-12. Etapa ejecutada íntegramente por Franco en TEST sobre propuestas verificadas en harness local PostgreSQL; Claude no tocó Supabase ni n8n. Con 9H cerrada, el **Carril B / contabilidad operativa interna queda completo** en TEST: capa derivada (9C–9G) + capa con estado (9H). Próximo hito del carril: la promoción coordinada a OPS por DDL, con bump único del canónico y decisión de GRANTs/RLS.*
