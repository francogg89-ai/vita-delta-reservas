# MANIFIESTO — Paquete coordinado de canonicalización CC (Bloque 1 + L3) + satélites + bootstrap

- **Tipo:** documento de trabajo (worksheet ejecutable; NO es un cierre inmutable).
- **Objetivo:** aterrizar en el canónico y satélites todo el frente Cuenta Corriente que quedó rezagado (Bloque 1 = extensión del snapshot; L3 = lecturas históricas), acuñar sus decisiones/lecciones, y **dejar el bootstrap a paridad con el canónico** (resolver P-CC-4).
- **Alcance de escritura real:** solo documentación/canónico/satélites/bootstrap. **No** se crea SQL funcional nuevo. **No** se toca gateway, n8n, frontend, cierre asistido, L1/L2 (ya canónicos), retiros (ya canónicos), ni la primera foto real de OPS.
- **Fecha de emisión del manifiesto:** 2026-07-07.

---

## 0. Estado de partida (verificado en clone fresco `b99a0b9`)

**Canónico `6B_SCHEMA_SQL.md` = v1.11.0.** El frente CC ya está *parcialmente* canonicalizado:
- **v1.10.0** — L1/L2: `cuenta_corriente_viva`, `cuenta_corriente_detalle` (PARTE C).
- **v1.10.1** — pct operativo a `configuracion_general` (`pct_operativo`, D-CC-13) + helper `pct_operativo_vigente()`.
- **v1.11.0** — capa de escritura (retiro desde saldo vivo): `portal_usuarios.id_socio`, `portal_idempotencia_cc`, `registrar_retiro_desde_saldo_vivo`, wrapper `portal_registrar_retiro(jsonb)`, D5 extendido.

**Rezagados (lo que este paquete debe canonicalizar):**
- **Bloque 1** — extensión del snapshot: 3 tablas append-only + 6 triggers + `registrar_snapshot_periodo` extendida. Desplegado y verde TEST/OPS; **no** en el canónico.
- **L3** — lecturas históricas: `cuenta_corriente_historico(date)` y `cuenta_corriente_historico_acumulados()`. Desplegado y verde TEST/OPS; **no** en el canónico.

**Numeración (verificada):**
- Decisiones: `DECISIONES_NO_REABRIR.md` tiene **D-CC-01..22 acuñadas**. Candidatas **D-CC-23..30** (Bloque 1) y **D-CC-31..39** (L3) viven solo en los cierres.
- Lecciones: `Lecciones_Aprendidas.md` tiene **L-CC-01..12 acuñadas**. Bloque 1 dejó **3 lecciones candidatas SIN numerar**; L3 numeró **L-CC-14..17** asumiendo 13 tomado → **requiere reconciliación** (ver §5).
- Pendientes: `Pendiente_pre_produccion.md` tiene P-CC-1..5. **P-CC-4 = deuda de bootstrap** (a resolver en este paquete).

**Bootstrap = `bootstrap_entorno_nuevo_v1.9.0`** (base + Carril B + Carril C 3 objetos). Está **2 versiones atrás** del canónico (le faltan v1.10.0/v1.10.1/v1.11.0) **antes** de sumarle Bloque 1 + L3.

---

## 1. Orden de lectura recomendado (para la conversación que ejecute esto)

1. Este manifiesto.
2. `Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/06-07-2026/EXT_SNAPSHOT_BLOQUE1_CIERRE.md` (contratos, objetos y **textos D-CC-23..30** de Bloque 1; §8 ya bosqueja el paquete).
3. `L3_HISTORICO_BLOQUE2_CIERRE.md` (contratos finales y **textos D-CC-31..39 / lecciones L3**).
4. Canónico `Docs/Implementacion/6B_SCHEMA_SQL.md` v1.11.0 (dónde insertar: PARTE C / sección CC).
5. Satélites: `Docs/Operacional/DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `Pendiente_pre_produccion.md`; y `CLAUDE.md`, `README.md`.
6. Bootstrap: `Docs/Implementacion/bootstrap_entorno_nuevo_v1.9.0/`.
7. DDL byte-exacto de referencia: `Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/05-07-2026/EXT_SNAPSHOT_01_DDL_TABLAS_TEST.sql` y `_02_TRIGGERS_TEST.sql`; artefactos L3 `L3_01_DDL_FUNCIONES_TEST.sql` / `L3_05a_DDL_FUNCIONES_OPS.sql`.

**Regla de oro (trampa del canónico rezagado):** verificar contra el estado real de Supabase (TEST/OPS), no solo contra el canónico. Los cierres ya certifican paridad TEST=OPS; igualmente confirmar objetos/firmas antes de canonizar.

---

## 2. Workstream 1 — Canónico (`6B_SCHEMA_SQL.md`)

### 2.1 Objetos a agregar — Bloque 1
Ubicación: PARTE C / sección de la cuenta corriente congelada (junto a las 5 tablas 9H).
- **3 tablas append-only:** `liquidacion_participacion` (5 col), `liquidacion_gasto` (19 col), `liquidacion_incidencia` (7 col). DDL exacto en `EXT_SNAPSHOT_01_DDL_TABLAS_TEST.sql`. Detalle de columnas/constraints en el cierre Bloque 1 §3.1.
- **6 triggers de inmutabilidad** (2 por tabla, reusan `trg_9h_inmutable()`). DDL en `EXT_SNAPSHOT_02_TRIGGERS_TEST.sql`; cierre Bloque 1 §3.2.
- **`registrar_snapshot_periodo` extendida** (congela también el detalle fino). Cierre Bloque 1 §3.4.
- **REVOKE** de las 3 tablas a PUBLIC + 3 roles Data API.

### 2.2 Objetos a agregar — L3
Ubicación: PARTE C / capa de lectura CC (junto a `cuenta_corriente_viva`/`cuenta_corriente_detalle`).
- **`cuenta_corriente_historico(date) → jsonb`** y **`cuenta_corriente_historico_acumulados() → jsonb`**. Cuerpos exactos en `L3_01_DDL_FUNCIONES_TEST.sql` (idéntico a `L3_05a` salvo el gate). Ambas `sql`/`STABLE`/`SECURITY INVOKER`/`SET search_path = pg_catalog, public` + `REVOKE EXECUTE`. Contratos finales en el cierre L3 §5 y §6.
- **Nota:** el DDL canónico va **sin** el gate anti-ambiente (el gate es del artefacto de despliegue, no del canónico — igual que el resto del canónico).

### 2.3 Bump de versión (DECISIÓN A RESOLVER)
- Opción 1: **un** bump que consolide Bloque 1 + L3 (p. ej. **v1.12.0**).
- Opción 2: **dos** bumps (v1.12.0 = Bloque 1; v1.13.0 = L3).
- Actualizar el bloque de changelog del canónico con el mismo estilo que v1.10.0→v1.11.0 (qué se consolidó, promoción TEST→OPS, huellas si aplica).

### 2.4 Fold ASCII (DECISIÓN A RESOLVER)
El cierre Bloque 1 §7 marca 3 mensajes `RAISE`/comentario que quedaron sin acento (ASCII-puro) respecto del canónico. Al canonizar: **mantener el fold** (recomendado, ASCII-puro) o restaurar acentos. Decidir y aplicar consistentemente.

---

## 3. Workstream 2 — Satélites (patchers Python `str_replace`, disciplina de la casa)

| Satélite | Cambio |
|---|---|
| `DECISIONES_NO_REABRIR.md` | **Acuñar D-CC-23..30** (textos en cierre Bloque 1 §6) y **D-CC-31..39** (textos en cierre L3 §7). |
| `Lecciones_Aprendidas.md` | **Acuñar** las 3 lecciones de Bloque 1 (prosa en cierre Bloque 1 §"Candidatas de lección") + las 4 de L3 (cierre L3 §8), con la **numeración reconciliada** (§5). |
| `ESTADO_ACTUAL_VITA_DELTA.md` | Reflejar frente CC cerrado (Bloque 1 + L3 desplegados TEST+OPS); canónico bumpeado; OPS greenfield en fotos hasta primer cierre real. |
| `Pendiente_pre_produccion.md` | Marcar **P-CC-4 resuelto** (bootstrap a paridad). Agregar **P-L3-01** (camino de detalle con datos reales / commit-freeze) y **P-L3-02** (primera foto real OPS). Revisar estado de P-CC-2 (extensión snapshot → cubierta por Bloque 1). |
| `CLAUDE.md` | Reflejar nueva versión canónica + capacidades CC (lecturas históricas L3). |
| `README.md` | Ídem, a nivel overview. |

**Disciplina de patch:** `str_replace` con aserción de anclaje `count==1` + prueba de identidad reverse-replace por cada edición; LF puro; los `.md` de satélite llevan acentos españoles (no ASCII-puro, a diferencia de los SQL). Satélites se tocan **solo** en este paquete (no mid-stage).

---

## 4. Workstream 3 — Bootstrap a paridad (resuelve P-CC-4)

**Gap actual (v1.9.0 → canónico final):** el bootstrap debe incorporar **todo** lo que el canónico sumó desde v1.9.0:
- **v1.10.0** — `cuenta_corriente_viva`, `cuenta_corriente_detalle` (PARTE C).
- **v1.10.1** — `pct_operativo` en `configuracion_general` + `pct_operativo_vigente()`; A27/A28 leyendo pct de config.
- **v1.11.0** — `portal_usuarios.id_socio` (FK/UNIQUE/CHECK), `portal_idempotencia_cc`, `registrar_retiro_desde_saldo_vivo` (PARTE C), `portal_registrar_retiro(jsonb)` (PARTE D), D5 extendido.
- **Bloque 1** — 3 tablas + 6 triggers + `registrar_snapshot_periodo` extendida.
- **L3** — las 2 funciones históricas + REVOKE.

**Enfoque:** el canónico es autocontenido y apto para bootstrappear de cero; el bootstrap se **regenera derivándolo del canónico final**. Target de versión: alineado al bump de §2.3 (p. ej. `bootstrap_entorno_nuevo_v1.12.0`). Verificación: los VERIFY del bootstrap deben cerrar verde y la huella estructural debe reproducir el canónico (las huellas `TOTAL_CARRIL`/`TOTAL_PORTAL` cambian por los deltas — documentarlo como en los changelogs previos).

**Nota de tamaño:** este workstream es el más pesado (el bootstrap está 2 versiones + 2 bloques atrás). Conviene tratarlo como bloque propio con su propio hard stop.

---

## 5. Reconciliación de numeración (RESOLVER ANTES DE ACUÑAR)

**Decisiones D-CC — sin colisión, contiguas:**
- Acuñadas: D-CC-01..22.
- Bloque 1: D-CC-23..30 (ya numeradas en su cierre).
- L3: D-CC-31..39 (ya numeradas en su cierre).
- → Acuñar 23..39 en orden. Sin conflicto.

**Lecciones L-CC — HAY que reconciliar:**
- Acuñadas: L-CC-01..12.
- Bloque 1: 3 lecciones candidatas **sin numerar** (fold ASCII de mensajes heredados al emitir SQL ASCII-puro; validación de re-snapshot con variante rollback-first; verificación ACL real por `aclexplode` cubriendo PUBLIC + roles Data API + todos los privilegios).
- L3: 4 lecciones numeradas **L-CC-14..17** (asumió 13 tomado).
- **Colisión:** si Bloque 1 toma 13/14/15, pisa a L3 (14/15).
- **Propuesta:** Bloque 1 → **L-CC-13, L-CC-14, L-CC-15**; L3 → **L-CC-16, L-CC-17, L-CC-18, L-CC-19** (renumerar los L-CC-14..17 del cierre L3). Confirmar antes de acuñar.

---

## 6. Secuencia recomendada (un bloque por conversación, hard stops)

1. **Bloque A — Canónico:** agregar objetos Bloque 1 + L3, bump de versión, changelog, resolver fold ASCII. Franco ejecuta el commit; verificar.
2. **Bloque B — Satélites:** patchers de los 6 satélites, acuñando D-CC-23..39 y las lecciones reconciliadas; actualizar pendientes (P-CC-4 resuelto, P-L3-01/02 nuevos). Franco commitea; verificar.
3. **Bloque C — Bootstrap:** regenerar a paridad con el canónico final; VERIFY verde; documentar huellas. Franco ejecuta en entorno de prueba si corresponde; verificar.

Cada bloque: diseño → aprobación de Franco → artefactos/patchers (validados: `str_replace count==1` + reverse-identity; cualquier SQL nuevo del bootstrap por `pglast` + harness) → Franco ejecuta → verificación → siguiente bloque. Nada avanza sin OK explícito.

---

## 7. Decisiones a resolver primero (antes de cualquier artefacto)

1. **Versión:** un bump (v1.12.0 = Bloque 1 + L3) o dos (v1.12.0 / v1.13.0). [§2.3]
2. **Numeración L-CC:** confirmar Bloque 1 → 13/14/15 y L3 → 16/17/18/19. [§5]
3. **Fold ASCII:** mantener fold (ASCII-puro) o restaurar acentos en el canónico. [§2.4]
4. **Bootstrap:** confirmar regeneración completa a paridad (v1.9.0 → target) derivada del canónico final. [§4]
5. **Empaquetado:** ¿los 3 workstreams como 3 bloques separados (recomendado) o algún merge?

---

## 8. Qué NO se toca (recordatorio duro)

Gateway `portal-api`, n8n, frontend, cierre asistido, **L1/L2 y retiros** (ya canónicos; no se re-tocan salvo que la canonicalización de Bloque 1/L3 los referencie), y **la primera foto real de OPS**. **No se crea SQL funcional nuevo**: este paquete es canonicalización + satélites + bootstrap. El siguiente frente (posterior a este paquete) es **exponer L3 / la capa CC en el portal operativo**.
