# CIERRE — Bloque 1: Extensión del snapshot mensual a P-CC-2 completo

- **Frente:** Snapshot mensual congelado + L3 histórico (Opción B) — capa de detalle fino
- **Bloque:** 1 de N (extensión del snapshot; L3 y cierre asistido son bloques posteriores)
- **Fecha de cierre:** 2026-07-06
- **Estado:** CERRADO — verde en TEST (funcional) y OPS (estructural)
- **Entornos:** TEST `bdskhhbmcksskkzqkcdp` · OPS `lpiatqztudxiwdlcoasv`
- **Canónico de referencia al abrir:** `6B_SCHEMA_SQL.md` v1.11.0 (NO modificado en este bloque)
- **Documento inmutable:** una vez aprobado, no se edita; correcciones van en documento nuevo.

---

## 1. Resumen ejecutivo

Se decidió y ejecutó la **Opción B / P-CC-2 completo**: extender el snapshot mensual existente (9H) para que, además del esqueleto que ya congelaba (cabecera + cascada 1–8 + saldos por socio), congele también el **detalle fino** que P-CC-2 exige: participación por cabaña, gastos individuales (foto fiel de `gastos_internos`) e incidencias por gasto. La extensión es **aditiva**: reusa `registrar_snapshot_periodo` como congelador y agrega tres tablas append-only con la misma disciplina de inmutabilidad, REVOKE y supersesión que las cinco tablas 9H actuales. No se tocó ninguna lectura en vivo (L1/L2) ni ninguno de los dos retiros. OPS quedó **greenfield en datos**: solo se promovió la estructura; el primer cierre real (congelar un mes concreto con su detalle) es un paso controlado posterior.

---

## 2. Contexto y decisión de negocio

El inventario read-only ejecutado en TEST y OPS confirmó que **OPS no tenía ninguna foto real** en las tablas 9H (greenfield) y que la brecha estructural contra P-CC-2 era concreta: matriz/incidencias/detalle por cabaña/lista de gastos **no** estaban congelados. Sobre ese diagnóstico se eligió la Opción B (snapshot completo) por sobre un L3 recortado, porque OPS estaba limpio (sin fotos incompletas que migrar) y era preferible resolver el congelado completo **antes** del primer cierre real, en vez de dejar el detalle fino como deuda estructural desde el arranque.

---

## 3. Objetos creados / modificados

### 3.1 Tablas nuevas (append-only) — 3

**`liquidacion_participacion`** (5 columnas) — grano: cabaña. Congela `detalle_participacion(periodo)`.
- Columnas: `id_liquidacion`, `id_cabana`, `valor_relativo`, `id_socio_beneficiario`, `participa`.
- PK `(id_liquidacion, id_cabana)`.
- FK `ON DELETE RESTRICT`: `id_liquidacion`→`liquidaciones_periodo`, `id_cabana`→`cabanas`, `id_socio_beneficiario`→`socios`.
- CHECK: `chk_lpart_valor_pos` (`valor_relativo > 0`); `participa` NOT NULL.

**`liquidacion_gasto`** (19 columnas) — grano: gasto. Foto fiel de la fila de `gastos_internos` + estado de incidencia congelado.
- Columnas: `id_liquidacion`, `id_gasto`, `fecha`, `clase`, `clase_sugerida`, `etiqueta`, `monto` NUMERIC(14,2), `moneda`, `id_zona`, `id_cabana`, `pagador_tipo`, `id_socio_pagador`, `medio_pago`, `comentario`, `comprobante_url`, `creado_por`, `created_at`, `sin_incidencia`, `motivo_sin_incidencia`.
- PK `(id_liquidacion, id_gasto)`.
- FK `ON DELETE RESTRICT`: `id_liquidacion`→`liquidaciones_periodo`, `id_zona`→`zonas`, `id_cabana`→`cabanas`, `id_socio_pagador`→`socios`. **`id_gasto` es referencia histórica COPIADA, sin FK a `gastos_internos`** (D-CC-30 candidata: fuente mutable, foto autocontenida).
- CHECKs: `chk_lgasto_clase` (A/C/D/E), `chk_lgasto_monto_pos` (>0), `chk_lgasto_moneda` (=ARS), `chk_lgasto_pagador_tipo` (socio/caja), `chk_lgasto_pagador_cons` (socio⇒pagador NOT NULL / caja⇒NULL), `chk_lgasto_alcance_clase` (D⇒zona/E⇒cabaña/A,C⇒ninguno), `chk_lgasto_sin_incidencia_coherente` (`sin_incidencia = (motivo_sin_incidencia IS NOT NULL)`), `chk_lgasto_clase_sug` (NULL o A/C/D/E), `chk_lgasto_motivo_dom` (NULL o `pool_vacio`/`zona_sin_activas`).

**`liquidacion_incidencia`** (7 columnas) — grano: incidencia. Congela `incidencia_gasto(id_gasto)` por gasto, con `regla`.
- Columnas: `id_liquidacion`, `id_gasto`, `seq`, `destino`, `id_socio`, `monto_incidido` NUMERIC(14,2), `regla`.
- PK `(id_liquidacion, id_gasto, seq)`.
- FK `ON DELETE RESTRICT`: `(id_liquidacion, id_gasto)`→`liquidacion_gasto` (entre tablas congeladas), `id_socio`→`socios`.
- CHECKs: `chk_linc_seq_pos` (>0), `chk_linc_destino` (pool_pre_operativo/socio), `chk_linc_monto_centavos` (`= ROUND(...,2)`), `chk_linc_destino_socio` (socio⇒id_socio NOT NULL / pool⇒NULL).

Ninguna tabla usa secuencias (PKs compuestas → 0 objetos de secuencia nuevos).

**Derivados (NO son tablas):** la matriz por socio se deriva de `liquidacion_participacion` (suma de `valor_relativo` por beneficiario entre `participa=true` sobre el pool); "gastos sin incidencia" está congelado explícitamente en `liquidacion_gasto` (`sin_incidencia`/`motivo`); los nombres de cabaña/socio se derivan por join.

### 3.2 Triggers de inmutabilidad — 6

Dos por tabla, reusando la función existente `trg_9h_inmutable()`:
- `trg_{tabla}_no_upd_del` — BEFORE UPDATE OR DELETE, por fila.
- `trg_{tabla}_no_truncate` — BEFORE TRUNCATE, por statement.

(Para las 3 tablas nuevas. Idénticos en construcción a los 10 triggers de 9H.)

### 3.3 REVOKE

- `REVOKE ALL ON TABLE` para las 3 tablas frente a `PUBLIC, anon, authenticated, service_role` (0 Data API).

### 3.4 Función modificada — 1

**`registrar_snapshot_periodo(date, numeric, text, bigint, text)`** — reemplazada por `DROP FUNCTION` + `CREATE` (no `CREATE OR REPLACE`, por L-CC-07) + `REVOKE EXECUTE` explícito frente a `PUBLIC/anon/authenticated/service_role`.
- **Cuerpo original preservado byte-a-byte** salvo un fold ASCII de 3 caracteres (`período`→`periodo` en 1 comentario y 2 mensajes de `RAISE`), sin cambio de lógica.
- **Bloque de extensión agregado** después de los INSERT de cascada y socios, dentro de la misma transacción y el mismo `pg_advisory_xact_lock`:
  1. `liquidacion_participacion` ← `detalle_participacion(v_periodo)`.
  2. `liquidacion_gasto` ← `gastos_internos WHERE periodo = v_periodo` con `LEFT JOIN gastos_sin_incidencia_periodo(v_periodo)` (congela `sin_incidencia`/`motivo`).
  3. `liquidacion_incidencia` ← `gastos_internos g CROSS JOIN LATERAL incidencia_gasto(g.id_gasto)`, con `seq = ROW_NUMBER() OVER (PARTITION BY id_gasto ORDER BY id_socio NULLS FIRST)`.
- **Guards nuevos** (espejo del `v_n_cascada=8`, ambos permiten 0): filas de participación = nº de cabañas; filas de gasto = nº de gastos del mes.
- Firma, lock, supersesión y guards originales (8 pasos, 0-o-N socios) **sin cambios**.

---

## 4. Qué NO se tocó (verificado)

- **Lecturas en vivo L1/L2:** `cuenta_corriente_viva`, `cuenta_corriente_detalle` — intactas.
- **Retiros:** `registrar_retiro` (9H, snapshots congelados) y `registrar_retiro_desde_saldo_vivo` (v1.11.0) — intactos; ambos preservados.
- **9G/9H existentes:** las 5 tablas 9H previas, la cascada (`cascada_periodo`, `saldo_socios_periodo`), matriz/incidencias/reportes — sin cambios (solo se los invoca de lectura).
- **Fuera de alcance del frente:** gateway `portal-api`, wrappers n8n, frontend, fiscal/legal (AFIP/ARCA/IVA), Mercado Pago, bot.
- **Satélites y canónico:** `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `Pendiente_pre_produccion.md`, `6B_SCHEMA_SQL.md` (v1.11.0) — **NO modificados** (se propagan en paquete coordinado al cierre del frente completo).
- **Bootstrap kit:** sigue en v1.9.0 (deuda consciente P-CC-4) — no regenerado.

---

## 5. Validación

### 5.1 Local — harness PostgreSQL 16.14 (pipeline reproducido)
- **`pglast`:** los 7 artefactos TEST + 6 OPS parsean; los read-only confirmados `SelectStmt` puro.
- **Poblamiento fiel:** `liquidacion_participacion` == `detalle_participacion`; `liquidacion_gasto` == `gastos_internos` fila a fila (las 19 columnas); `liquidacion_incidencia` == `incidencia_gasto` con `regla`.
- **Invariantes:** matriz derivada == `matriz_participacion`; `{sin_incidencia=true}` == `{gastos con 0 filas en T3}` == `gastos_sin_incidencia_periodo`; motivo congelado == motivo vivo.
- **Inmutabilidad:** UPDATE/DELETE/TRUNCATE sobre las 3 tablas → bloqueados por trigger.
- **Autocontención:** borrado del gasto vivo tras congelar → la foto sobrevive intacta y el gasto borrado sigue congelado (prueba del `id_gasto` copiado sin FK).
- **Gate anti-ambiente:** aborta (exit 3) en ambiente incorrecto; wrapper transaccional protege el `DROP` (la función no se dropea si el gate corta).
- **Negativo de CHECKs nuevos:** `clase_sugerida='X'` → `chk_lgasto_clase_sug`; `motivo='foo'` → `chk_lgasto_motivo_dom`; fila válida aceptada.
- **Teardown round-trip:** revierte a la función original y el bloque es re-runnable.

### 5.2 TEST — funcional (ejecutado por Franco)
- Runs 00→04 verdes; estructura y ACL correctas.
- **Run 05 rollback-first: 11/11 PASS** (poblamiento, invariantes, supersesión, foto previa sin detalle tolerada) y **sin dejar mutación** (ROLLBACK: 0 fotos nuevas, vigente sin cambio, 0 detalle persistido).
- *Nota: el Run 05 rollback-first no deja filas persistidas ni cambia la foto vigente; puede haber consumido un valor de secuencia en TEST por semántica normal de PostgreSQL (`nextval` no se revierte en `ROLLBACK`). Efecto: un hueco en la secuencia de `liquidaciones_periodo.id_liquidacion` en TEST, sin impacto funcional.*

### 5.3 OPS — estructural (ejecutado por Franco)
- **00_PREFLIGHT_OPS:** ambiente=ops; 3 tablas libres; 6 triggers en 0; 0 vistas dependientes; función y fuentes vivas.
- **01/02/03_OPS:** Success (DDL aplicado).
- **04_VERIFY_ESTRUCTURAL_OPS:** T1=5/T2=19/T3=7 columnas; 6 triggers; **0 grants** ACL (PUBLIC/anon/authenticated/service_role) y **total sensible=0**; función presente; **EXECUTE=0** para esos grantees; `proacl_materializado=true`.
- **Anti-OPS:** DDL sin filas de datos nuevas, sin consumo de secuencias; fotos existentes intactas.
- **NO se corrió Run 05 ni teardown en OPS.**
- Nota de robustez del gate: un intento accidental de `01_DDL` en OPS antes de tiempo fue **abortado por el gate**, sin dejar DDL aplicado (confirmado por preflight).

---

## 6. Decisiones candidatas (propuestas — NO acuñadas)

Se mantienen como candidatas; se acuñan formalmente en `DECISIONES_NO_REABRIR.md` al cierre del **frente completo** de cuenta corriente (junto con L3 y el cierre asistido), no en este bloque.

- **D-CC-23** — Opción B: el snapshot congela también el detalle fino (participación + gastos + incidencias) en la misma txn/lock que cascada+socios.
- **D-CC-24** — Tres tablas append-only (`liquidacion_participacion`, `liquidacion_gasto`, `liquidacion_incidencia`), PKs compuestas (sin secuencias); `liquidacion_gasto` es foto fiel de `gastos_internos` + `sin_incidencia`/`motivo` congelados; matriz por socio y nombres derivados.
- **D-CC-25** — Inmutabilidad, REVOKE y supersesión idénticas a 9H.
- **D-CC-26** — Re-snapshot: cada versión de foto posee su set completo de detalle; el de la superseded queda congelado pero fuera de las lecturas vigentes; nada se borra ni actualiza.
- **D-CC-27** — Detalle congelado pct-independiente; solo la cascada usa `pct_operativo_vigente()`.
- **D-CC-28** — Fotos anteriores a la extensión (solo fixtures TEST) quedan sin detalle; L3 tolera detalle vacío; OPS nace con detalle completo.
- **D-CC-29** — `regla` congelada en T3; pagador congelado en T2; `motivo_sin_incidencia` congelado en T2; nombres derivados.
- **D-CC-30** — `liquidacion_gasto.id_gasto` = referencia histórica copiada sin FK a `gastos_internos`; FK `ON DELETE RESTRICT` a catálogos estables (`socios`/`cabanas`/`zonas`); FK compuesta T3→T2 entre tablas congeladas.

Candidatas de lección (a acuñar en `Lecciones_Aprendidas.md` al cierre del frente): fold ASCII de mensajes heredados del canónico al emitir artefactos SQL ASCII-puros; validación de re-snapshot con variante rollback-first para no ensuciar TEST; verificación ACL real por `aclexplode` cubriendo PUBLIC + roles Data API y todos los privilegios.

---

## 7. Riesgos residuales

- **Primer cierre real en OPS pendiente:** la estructura está, pero la mecánica de poblamiento en OPS recién se ejercita con la primera foto real. Mitigación: mecánica ya validada al centavo en harness y TEST; la primera foto real se hará por cierre asistido (revisada antes de congelar) y la supersesión la hace no-destructiva.
- **Coherencia L2 (vivo) vs L3 (congelado):** para un mes cerrado, ambos divergen si se editan datos de ese mes después del cierre. Es el comportamiento buscado (estabilidad); se comunica en el contrato de L3 (Bloque 2): para un mes con foto vigente, L3 es la autoritativa.
- **Fotos pre-extensión:** solo existen como fixtures en TEST (sin detalle). OPS greenfield no las tiene. L3 debe tolerar detalle vacío para esas fotos.
- **Reembolsos (seam abierto, remanente P-CC-2):** `movimientos_socio` es un mayor genérico por `tipo`; un reembolso futuro se leería genéricamente. No se implementa en este frente.
- **Fold ASCII:** 3 mensajes de `RAISE`/comentario quedaron sin acento respecto del canónico. Al actualizar el canónico se decide mantener el fold (recomendado, ASCII-puro) o restaurar acentos.
- **Namespace D-CC-23…30 no acuñado:** riesgo de colisión si otro frente acuña en paralelo. Mitigación: un frente por vez; se acuñan al cierre del frente.
- **Deuda de propagación:** canónico, satélites y bootstrap quedan rezagados respecto del estado real de OPS hasta el paquete coordinado (ver §8).

---

## 8. Próximos pasos

1. **Bloque 2 — L3 (lecturas del detalle congelado):** funciones de lectura sobre la foto vigente (cabecera + cascada 1–8 + saldos por socio + participación + gastos + incidencias + movimientos) + acumulados históricos. Conversación aparte, un bloque, con su checkpoint. Debe tolerar fotos sin detalle (fixtures TEST) y leer siempre la vigente.
2. **Cierre asistido + primer snapshot real:** flujo preparar (preview read-only reusando `cascada_periodo`/`saldo_socios_periodo` + reportes de calidad) → revisar → congelar. Con esto se hace el **primer cierre real en OPS** (candidato: julio 2026, primer mes del piso contable D-NEG-02), que valida el poblamiento del detalle sobre datos reales de producción. El congelado usa `registrar_snapshot_periodo` (ya extendida) con `pct_operativo_vigente()`.
3. **Actualización canónico / satélites / bootstrap (paquete coordinado, al cierre del frente completo):**
   - `6B_SCHEMA_SQL.md`: agregar las 3 tablas + 6 triggers + la función extendida; bump de versión.
   - `DECISIONES_NO_REABRIR.md`: acuñar D-CC-23…30.
   - `Lecciones_Aprendidas.md`: registrar las lecciones candidatas de §6.
   - `ESTADO_ACTUAL_VITA_DELTA.md`: reflejar la capa de detalle congelado en OPS.
   - Bootstrap kit: regenerar (cierra la deuda P-CC-4) recién al cerrar el frente completo de cuenta corriente.

---

## 9. Anexo — artefactos del bloque

**Paquete TEST (`EXT_SNAPSHOT/`):** `00_PREFLIGHT_TEST`, `01_DDL_TABLAS_TEST`, `02_TRIGGERS_TEST`, `03_FUNCION_TEST`, `04_VERIFY_ESTRUCTURAL_TEST`, `05_VALIDACION_FUNCIONAL_TEST_ROLLBACK`, `99_TEARDOWN_TEST`.

**Paquete OPS (`EXT_SNAPSHOT_OPS/`):** `00_PREFLIGHT_OPS`, `01_DDL_TABLAS_OPS`, `02_TRIGGERS_OPS`, `03_FUNCION_OPS`, `04_VERIFY_ESTRUCTURAL_OPS`, `99_TEARDOWN_OPS` (emergencia). Sin Run 05.

Todos: ASCII-puro + LF, validados con `pglast` y ejecutados en harness local antes de TEST/OPS. Gate anti-ambiente (`configuracion_general('ambiente')`) en todos los runs de escritura.

---

*Fin del cierre de Bloque 1. Documento inmutable — aprobado 2026-07-06 (incluye la nota de secuencia en §5.2 solicitada en la aprobación). La ejecución en sistemas reales (TEST/OPS) fue realizada por Franco; el diseño, la generación de artefactos y la validación en harness local por Claude.*
