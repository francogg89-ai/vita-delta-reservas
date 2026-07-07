# Inventario exacto + propuesta de barrido — B1.2-cascade

**Relevamiento:** clone fresco `git clone --depth 1` en HEAD `f3e8fcb` (615 archivos). Grep exhaustivo del fp viejo `58d75c1b6b812ee2d2c9751ddcb0cd4d` sobre `*.sql *.md *.ts *.json`.
**Estado:** inventario para aprobación. **No hay artefactos todavía.** Con tu OK sobre el barrido y las decisiones abiertas, se abre la generación.

---

## 1. Hallazgos del relevamiento

1. **El set B1.1/S0–S3 está commiteado** en el repo (Franco lo subió tras ejecutarlo). El clone fresco es la autoridad; las copias en `/tmp` se ignoran.
2. **El fp viejo del resolver aparece 35 veces en 22 archivos**, todas **contenidas en `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/`**. Cero ocurrencias en satélites globales (`DECISIONES_NO_REABRIR`, `Lecciones_Aprendidas`, `ESTADO_ACTUAL`, `Pendiente_pre_produccion`, `README`, `CLAUDE`) y cero en canónico. Esto confirma que el barrido de fingerprints queda **contenido al carril del Motor** — DC-04 (diferir satélites) se cumple naturalmente para el fp.
3. **No existe un fp viejo del helper hardcodeado.** El helper `vigencias_conflictos_comprometidos` nunca estuvo fingerprint-gateado en los smokes; se verificaba por existencia/comportamiento. El único md5 del helper en el repo es la línea de **reporte** de la migración de core (computada en runtime). ⇒ DC-05 **agrega** un gate de fp del helper (`871fcde5…`), no reemplaza uno viejo.
4. **Censo de fingerprints (todos identificados):**

| Fingerprint | Objeto | Acción |
|---|---|---|
| `58d75c1b…` (35) | resolver R0/B1.1 (VIEJO) | **objetivo del barrido** |
| `37009a32…` (49) | ODR (intacto) | sin cambio |
| `759662b4…` (20) | resolver **pre-R0** (target del rollback de R0) | histórico, sin cambio |
| `f258ad9b…` (9) | `crear_prereserva` (valor B3) | core no lo tocó — sin cambio |
| `f8d6bbf5…` (8) | ODR **pre-A** (era DISPONIBILIDAD_RANGO) | histórico, sin cambio |
| `d92a438e…` (3) | `crear_prereserva` (after B3) | core no lo tocó — sin cambio |
| `a60d…`, `81a5…`, `5a85…`, `0391…` (1 c/u) | baselines/afters de otros cierres | históricos, sin cambio |

**Conclusión:** el único fingerprint que cambió y necesita realineación es el del **resolver** (`58d75c1b` → `1bd96c89`); más el **agregado** del gate del helper (`871fcde5`, DC-05). Todos los demás fps son de funciones que core no tocó (siguen válidos) o son referencias históricas legítimas.

---

## 2. Clasificación de las 35 ocurrencias

### Categoría 1 — REALINEAR (guardas activos que esperan `resolver == R0`)

Estos gatean "el resolver debe ser R0" como precondición; post-core es falso ⇒ fallan (deuda controlada declarada en el cierre). Son la red de regresión que DC-01 re-arma.

**Suite guard de alta de overrides (04-07-2026):**

| Archivo | Ocurr. | Rol del fp |
|---|---|---|
| `HORARIOS_GUARD_S0_VALIDADORES_TEST.sql` | 2 | gate (validadores S0: `validar_estado_horario_final` llama al resolver) |
| `HORARIOS_GUARD_S0_SMOKES_TEST.sql` | 1 | gate |
| `HORARIOS_GUARD_S1_TRIGGER_TEST.sql` | 2 | gate (trigger-barrera `trg_ov_guard`, delega en S0) |
| `HORARIOS_GUARD_S1_SMOKES_TEST.sql` | 1 | gate |
| `HORARIOS_GUARD_S2_FUNCION_TEST.sql` | 1 | gate (`crear_override_horario`) |
| `HORARIOS_GUARD_S2_SMOKES_TEST.sql` | 1 | gate |
| `HORARIOS_GUARD_S2_ROLLBACK_TEST.sql` | 1 | aserción `resolver_r0_intacto` |
| `HORARIOS_GUARD_S3_FUNCION_TEST.sql` | 1 | gate (`crear_paquete_dia_especial`; verifica efecto vía resolver) |
| `HORARIOS_GUARD_S3_SMOKES_TEST.sql` | 1 | gate |

**Suite B1.1 vigencias (05-07-2026):**

| Archivo | Ocurr. | Rol del fp |
|---|---|---|
| `B1_1_VIGENCIAS_DDL_TEST.sql` | 2 | gate |
| `B1_1_CREAR_VIGENCIA_FUNCION_TEST.sql` | 2 | gate |
| `B1_1_GUARD_TRIGGER_TEST.sql` | 2 | gate |
| `B1_1_ROLLBACK_TEST.sql` | 2 | aserción `resolver_fp_ok` |

**En la suite pero SIN literal del fp viejo** (parte del re-arme por DC-01, aunque no requieren swap de fp):

| Archivo | Gate actual | Nota |
|---|---|---|
| `HORARIOS_GUARD_S1_ROLLBACK_TEST.sql` | (ninguno) | rollback por existencia |
| `HORARIOS_GUARD_S3_ROLLBACK_TEST.sql` | `resolver IS NOT NULL AS r0_ok` | renombrar `r0_ok` (engañoso post-core) |
| `B1_1_SMOKES_TEST.sql` | captura fp resolver pre==post (sin drift) | **acá van los agregados DC-05** (gate helper + INV-1) |

**Subtotal Cat 1:** 19 ocurrencias con literal en 13 archivos + 3 archivos de la suite sin literal.

### Categoría 2 — PRESERVAR (artefactos de transición, 06-07-2026)

Referencian `58d75c1b` **correctamente** como el estado del que core parte / target de restauración / chequeo "core aplicado". No están rotos. Son el registro de la transición R0 → core.

| Archivo | Ocurr. | Rol del fp |
|---|---|---|
| `B1_2_CORE_MIGRACION_TEST.sql` | 3 | precondición (resolver == R0 antes de core) + postcheck (wrapper ≠ R0) |
| `B1_2_CORE_ROLLBACK_TEST.sql` | 3 | target de restauración R0 + verificación |
| `B1_2_CORE_SMOKE_PERF_TEST.sql` | 2 | gate "core aplicado" (resolver ≠ R0) + META-C |
| `B1_2_CORE_SMOKE_RUTAS_TEST.sql` | 1 | gate "core aplicado" (resolver ≠ R0) |

**Propuesta:** no tocar. Los gates "core aplicado" (`resolver ≠ 58d75c1b`) siguen siendo verdaderos y correctos post-core.

### Categoría 3 — DOCUMENTACIÓN (según DC-02 / DC-04)

| Archivo | Ocurr. | Tipo | Propuesta |
|---|---|---|---|
| `HORARIOS_R0_RESOLVER_FIX_TEST.sql` | 0 (no hardcodea) | fix R0 | **banner SUPERSEDED por B1.2-core (DC-02)** — solo anotación, sin swap |
| `HORARIOS_R0_RESOLVER_RUNSHEET.md` | 0 | runsheet R0 | nota SUPERSEDED (DC-02) |
| `HORARIOS_GUARD_S0_RUNSHEET.md` | 1 | runsheet operativo | realinear fp esperado a `1bd96c89` (doc técnica directa, DC-04) |
| `HORARIOS_GUARD_ALTA_OVERRIDES_CIERRE_TECNICO_PRELIMINAR.md` | 1 | **cierre (inmutable)** | **no tocar** — es registro histórico (DC-03: preservar fp viejo en doc histórica) |
| `B1_1_VIGENCIAS_HORARIO_BASE_CIERRE_TECNICO_PRELIMINAR.md` | 1 | **cierre (inmutable)** | **no tocar** — registro histórico (DC-03) |

### Categoría 4 — DIAGNÓSTICOS ONE-TIME (decisión de alcance)

| Archivo | Ocurr. | Naturaleza |
|---|---|---|
| `B1_2_PRE_BASELINE_PERF_120D_TEST.sql` | 2 | midió el baseline (192.2ms) una vez; ya consumido |
| `B1_2_PRE_DIAGNOSTICO_G1_TEST.sql` | 2 | diagnóstico G1 (CAMINO_LIBRE) una vez; ya consumido |

Sus gates esperan `resolver == R0/B1.1`. Re-ejecutarlos post-core aborta (correcto: midieron el estado pre-core). **No son smokes de regresión** — son diagnósticos gastados cuyo output ya está capturado en el cierre. **Propuesta: anotar como históricos (spent), NO re-armar.** → **Decisión abierta DC-C1** (ver §5).

**Total: 19 (Cat 1) + 9 (Cat 2) + 3 (Cat 3) + 4 (Cat 4) = 35 ✓**

---

## 3. Propuesta de barrido por categoría

### Cat 1 — re-arme (DC-01, DC-03, DC-05)

Por cada archivo, sin rediseñar lógica funcional:

1. **Gate de fp del resolver:** literal `58d75c1b…` → `1bd96c89e587b15582fd7b2e29ae7e18`. Mensajes "esperado 58d75c1b (post-R0)" → "esperado 1bd96c89 (post-core)".
2. **Aserciones de rollback** (`resolver_r0_intacto`, `resolver_fp_ok`): fp esperado → `1bd96c89`; renombrar la variable a algo neutro (`resolver_fp_intacto`).
3. **Suite B1.1 (`B1_1_SMOKES_TEST.sql`) — agregados DC-05:**
   - gate de identidad del helper: `md5(helper) = 871fcde54be66b47c3e303e73b893c24`.
   - smoke comportamental **INV-1**: `_resolver_horario(cab, fecha_con_vigencia, false)` → origen config (base/patron_domingo) **y** `resolver_horario(cab, fecha_con_vigencia)` → origen `vigencia`. (Reusa el patrón ya validado en el rutas smoke de core.)
   - mantener el test G1 fail-closed existente (induce `resolver.ok=false`, verifica `resolver_horario_invalido`); su lógica no cambia.
4. **Preservar intacto:** fixtures inline, subtransacciones que revierten, snapshot/restore de secuencias con `last_value`+`is_called`, veredicto META tri-parte, anti-ambiente gate, REVOKE espejo, EOL per-file.

### Cat 2 — no tocar. Registro de transición correcto.

### Cat 3 — según DC-02/DC-04:
- `HORARIOS_R0_RESOLVER_FIX_TEST.sql` + su runsheet: banner **SUPERSEDED por B1.2-core** (anotación de cabecera, sin swap).
- `HORARIOS_GUARD_S0_RUNSHEET.md`: realinear el fp esperado documentado.
- Cierres (`*_CIERRE_TECNICO_PRELIMINAR.md`): **inmutables, no tocar** (son la doc histórica que DC-03 manda preservar).

### Cat 4 — anotar históricos (propuesta), sujeto a DC-C1.

---

## 4. Decisión de diseño crítica: orden de los rollbacks

La cadena de dependencias es **R0 → B1.1 → core**. Los rollbacks de stage (S0–S3, B1.1) fueron diseñados para deshacer su stage asumiendo estado pre-core.

**Hazard:** correr el rollback de B1.1 **post-core** dropearía la tabla `vigencias_horario_base` y el helper — de los que el interno/wrapper de core **dependen** — dejando core roto. Lo mismo aplica en menor grado a los rollbacks S0–S3 (asumen el resolver R0).

**Esto NO es rediseño de lógica funcional** — es una barrera de seguridad. **Propuesta:** el re-arme agrega a cada rollback de stage un gate fail-closed:
> si core sigue aplicado (`_resolver_horario` existe) ⇒ abortar con mensaje claro "correr primero el rollback de core (B1_2_CORE_ROLLBACK_TEST.sql); la cadena es R0→B1.1→core".

Preserva la disciplina de rollbacks ordenados sin `DROP CASCADE`. → **Decisión abierta DC-C2** (ver §5).

---

## 5. Decisiones abiertas antes de generar artefactos

- **DC-C1 — B1.2-pre:** ¿los diagnósticos one-time (baseline + G1) se anotan como históricos/spent (propuesta), o se re-arman a esperar el estado post-core? *(Propuesta: anotar históricos; su output ya está capturado y re-medir requeriría un artefacto nuevo de baseline de todos modos.)*
- **DC-C2 — gate de orden en rollbacks:** ¿se agrega el gate fail-closed "core aplicado ⇒ abortar" a los rollbacks S0–S3/B1.1 (propuesta), o se los marca como válidos solo pre-core sin gate? *(Propuesta: agregar el gate — es más seguro y respeta la disciplina de rollbacks ordenados.)*
- **DC-C3 — alcance del helper en S0–S3:** los stages S0–S3 (guard de overrides) **no** usan el helper de vigencias; solo llaman al resolver. Confirmo que el gate del helper (DC-05.1) + INV-1 (DC-05.2) van **solo en la suite B1.1**, no en S0–S3. *(Propuesta: sí, solo B1.1.)*
- **DC-C4 — runsheets:** ¿los runsheets operativos (S0_RUNSHEET) se realinean in-place, o el re-arme produce runsheets nuevos junto a los smokes re-armados? *(Propuesta: realinear in-place los que documentan el fp esperado; son procedimientos operativos, no cierres inmutables.)*
- **DC-C5 — gate del interno:** DC-05 pide gate de fp del helper. ¿Agregamos también un gate de existencia/fp del interno `_resolver_horario` (`566ea522…`) en la suite B1.1, o alcanza con el del resolver público + helper + INV-1? *(Propuesta: agregar al menos existencia del interno como precondición de INV-1.)*

---

## 6. Fuera de alcance (confirmado por el relevamiento)

- **Canónico, OPS, portal-api, frontend, n8n, Vercel, lifecycle, cambio funcional al resolver** — sin tocar.
- **Satélites globales** — el fp viejo no aparece en ninguno; se difieren al paquete coordinado de cierre del Motor (DC-04).
- **Interacción vigencia↔override en el guard de alta** — Franco lo asignó a B1.2-lifecycle, no a cascade. El re-arme mantiene la lógica del guard tal cual (override sigue ganando por precedencia sobre vigencia; los smokes con 0 vigencias activas no exponen interacción).
- **Objetos con fp intacto** (`crear_prereserva`, ODR, validadores S0 en su lógica) — no se tocan; sus gates siguen pasando.

---

## 7. Método de ejecución del barrido (cuando se apruebe)

Patchers Python con `str_replace`/`count==1` + prueba de identidad por reverse-replace para cada edición; smokes re-armados validados en harness PG16.14 (pglast → cadena local); EOL per-file preservado (`git ls-files --eol`); ASCII-puro, sin fuga de fp de harness; Franco ejecuta en TEST y verifica. Un bloque, hard stop.

**Próximo paso propuesto:** que resuelvas DC-C1…DC-C5, y con eso genero el diseño detallado del barrido (lista archivo-por-archivo de ediciones exactas + los smokes re-armados) para tu aprobación antes de tocar nada.
