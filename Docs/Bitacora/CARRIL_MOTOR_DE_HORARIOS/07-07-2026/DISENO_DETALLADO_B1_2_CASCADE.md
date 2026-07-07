# DISEÑO DETALLADO — B1.2-cascade (barrido de fingerprints)

**Carril:** Motor de Horarios / B1 · **Naturaleza:** barrido de fingerprints + realineación de texto (NO cambio funcional del resolver) · **Estado:** diseño para aprobación — NO se generan artefactos hasta el OK.

**Base verificada:** clone fresco, HEAD `b99a0b9`. Fingerprint viejo del resolver `58d75c1b6b812ee2d2c9751ddcb0cd4d` = **35 ocurrencias / 22 archivos** de guardas/smokes/docs (excluidos los 3 meta-docs de cascade). Contención total bajo `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/`; **cero** en satélites globales (DC-04 se cumple solo).

**Fingerprints canónicos post-core (confirmados en `B1_2_CORE_MIGRACION_TEST.sql`):**

| Objeto | fp | rol |
|---|---|---|
| wrapper `resolver_horario(bigint,date)` | `1bd96c89e587b15582fd7b2e29ae7e18` | pass-through → interno(...,true) |
| interno `_resolver_horario(bigint,date,boolean)` | `566ea522351a6b4e57b6dd770124814b` | precedencia; flag true/false |
| helper `vigencias_conflictos_comprometidos(...)` | `871fcde54be66b47c3e303e73b893c24` | LATERAL → interno(...,false) [INV-1] |
| ODR `obtener_disponibilidad_rango(...)` | `37009a32154f93b80520500c0f15b46b` | INTACTO (firma preservada) |
| viejo resolver R0/B1.1 | `58d75c1b6b812ee2d2c9751ddcb0cd4d` | pre-core |
| pre-R0 | `759662b4afaed7af426917aa3717b34c` | pre-fix (histórico) |

**FUERA DE ALCANCE (confirmado):** canónico, OPS, portal-api, frontend, n8n, Vercel, lifecycle, cambio funcional del resolver, satélites globales. Todo LF puro (`git ls-files --eol` → `i/lf` en los 27 archivos del carril).

---

## 0. Principio organizador

> **El fingerprint esperado de un artefacto = el estado del resolver en el momento en que ese artefacto se ejecuta en el lifecycle canónico.**

Esto parte el barrido en dos grupos, y resuelve limpio tu Punto 1 (rollbacks) y tu Punto 2 (CREATE_VIGENCIA):

- **Grupo INTERNO-AUSENTE** — corren cuando `_resolver_horario` NO existe. Son (a) los pasos de **build por capas** (pre-core, cadena R0 → B1.1 → core) y (b) los **rollbacks de stage** (post-core-rollback, cadena R0 ← B1.1 ← core). En ambos casos el resolver está en R0/B1.1 = **`58d75c1b`**.
  → **Conservan `58d75c1b`** + reciben **gate fail-closed "abortar si el interno existe"**.

- **Grupo INTERNO-PRESENTE** — corren con core aplicado. Son los **smokes** (la red de regresión activa que verifica el estado post-core corriente, DC-01).
  → **Swap `58d75c1b` → `1bd96c89`**; el smoke B1.1 recibe además el gate completo DC-C5 + INV-1.

La simetría es exacta: builds y rollbacks comparten el mismo gate (interno ausente ⟺ core no aplicado / ya revertido ⟺ resolver = `58d75c1b`); los smokes son el único grupo que corre contra el interno presente.

**Corolario que refina el inventario:** el inventario (Cat 1) agrupó builds + smokes como "swap todo". Este diseño los **separa**: los smokes son la red de regresión (swap); los builds son pasos de instalación pre-core (conservan `58d75c1b`). Esto responde tu condicional del Punto 2 ("Opción B preferida SI la suite queda rerunnable"): para los **installs** la condición NO se cumple (rerunnearlos post-core es no-op o degradante), así que van por Opción A. Ver §2.

---

## 1. Clasificación de los 20 archivos

| # | Archivo | Grupo | Corre cuando | fp esperado | Tratamiento |
|---|---|---|---|---|---|
| 1 | `HORARIOS_GUARD_S0_SMOKES_TEST.sql` | SMOKE | interno presente | `1bd96c89` | swap |
| 2 | `HORARIOS_GUARD_S1_SMOKES_TEST.sql` | SMOKE | interno presente | `1bd96c89` | swap |
| 3 | `HORARIOS_GUARD_S2_SMOKES_TEST.sql` | SMOKE | interno presente | `1bd96c89` | swap |
| 4 | `HORARIOS_GUARD_S3_SMOKES_TEST.sql` | SMOKE | interno presente | `1bd96c89` | swap |
| 5 | `B1_1_SMOKES_TEST.sql` | SMOKE | interno presente | `1bd96c89` | swap + **DC-C5** + INV-1 |
| 6 | `HORARIOS_GUARD_S1_ROLLBACK_TEST.sql` | ROLLBACK | interno ausente | `58d75c1b` | gate fail-closed |
| 7 | `HORARIOS_GUARD_S2_ROLLBACK_TEST.sql` | ROLLBACK | interno ausente | `58d75c1b` | gate + conserva `resolver_r0_intacto` |
| 8 | `HORARIOS_GUARD_S3_ROLLBACK_TEST.sql` | ROLLBACK | interno ausente | `58d75c1b` | gate fail-closed |
| 9 | `B1_1_ROLLBACK_TEST.sql` | ROLLBACK | interno ausente | `58d75c1b` | **gate DURO** (dropea tabla/helper de los que core depende) |
| 10 | `HORARIOS_R0_RESOLVER_ROLLBACK_TEST.sql` | ROLLBACK | interno ausente | `759662b4` | **[FLAG scope]** recomiendo gate (ver §3.4) |
| 11 | `HORARIOS_GUARD_S0_VALIDADORES_TEST.sql` | BUILD | interno ausente | `58d75c1b` | **DD-CASCADE** |
| 12 | `HORARIOS_GUARD_S1_TRIGGER_TEST.sql` | BUILD | interno ausente | `58d75c1b` | **DD-CASCADE** |
| 13 | `HORARIOS_GUARD_S2_FUNCION_TEST.sql` | BUILD | interno ausente | `58d75c1b` | **DD-CASCADE** |
| 14 | `HORARIOS_GUARD_S3_FUNCION_TEST.sql` | BUILD | interno ausente | `58d75c1b` | **DD-CASCADE** |
| 15 | `B1_1_VIGENCIAS_DDL_TEST.sql` | BUILD | interno ausente | `58d75c1b` | **DD-CASCADE** |
| 16 | `B1_1_GUARD_TRIGGER_TEST.sql` | BUILD | interno ausente | `58d75c1b` | **DD-CASCADE** |
| 17 | `B1_1_CREAR_VIGENCIA_FUNCION_TEST.sql` | BUILD | interno ausente | `58d75c1b` | **DD-CASCADE / tu Opción A↔B** (recrea helper) |
| 18 | `HORARIOS_R0_RESOLVER_FIX_TEST.sql` | DOC | — | — | banner SUPERSEDED (DC-02) |
| 19 | `HORARIOS_R0_RESOLVER_RUNSHEET.md` | DOC | — | — | banner SUPERSEDED |
| 20a | `B1_2_PRE_BASELINE_PERF_120D_TEST.sql` | HISTÓRICO | — | — | anotar spent (DC-C1) |
| 20b | `B1_2_PRE_DIAGNOSTICO_G1_TEST.sql` | HISTÓRICO | — | — | anotar spent (DC-C1) |

**Runsheets S0–S3** (`HORARIOS_GUARD_S{0,1,2,3}_RUNSHEET.md`): bajo Path 1 sus referencias a `58d75c1b` describen los **gates de build** (VALIDADORES/TRIGGER/FUNCION) → quedan intactas. Ver §3.7.
**Cierres técnicos preliminares** (ALTA_OVERRIDES, B1.1_VIGENCIAS, B1.2_CORE): **inmutables** (DC-C4) → NO se tocan.

---

## 2. DD-CASCADE — decisión abierta (grupo BUILD, archivos 11–17)

Los installs no instalan nada post-core: el wrapper/interno/helper post-core los instala **core**. Su valor como regresión es nulo (los smokes cubren eso). Hay dos caminos:

### Path 1 — "build queda pre-core" (RECOMENDADO) — = tu Opción A para CREATE_VIGENCIA

- Conservan gate en `58d75c1b` (correcto para su momento en un rebuild por capas).
- Reciben gate fail-closed **"abortar si el interno existe"** (obligatorio en CREATE_VIGENCIA por degradación; defense-in-depth en el resto, con mensaje claro).
- `B1_1_CREAR_VIGENCIA_FUNCION_TEST.sql` **conserva su cuerpo viejo del helper** (provenance vía `resolver_horario(...)`) — correcto pre-core; **core lo refactoriza a ciego después**.
- **Preserva el orden de rebuild R0 → B1.1 → core** (del que depende el harness local PG16.14).
- La red de regresión post-core son los **smokes** (§3.1, §3.2).

### Path 2 — "build realineado post-core" — = tu Opción B

- Swap gate `58d75c1b` → `1bd96c89` + agregar precondición "el interno DEBE existir".
- `B1_1_CREAR_VIGENCIA_FUNCION_TEST.sql` **realinea el cuerpo del helper al ciego** (`_resolver_horario(...,false)`, fp `871fcde5`) + comentario + gate del helper `871fcde5`.
- **Consecuencia:** los installs quedan post-core-only. **Rompe el orden de rebuild**: B1.1 ya no puede buildearse antes de core (referencia el interno que core crea). El harness que reconstruye por capas se rompe.

### Recomendación

**Path 1.** Rerunnear installs post-core es no-op (o degradante en CREATE_VIGENCIA); el valor de la red de regresión está en los smokes; preserva la historia de build por capas y el harness. La deuda de autorreferencia que te preocupa se neutraliza con el gate fail-closed (el artefacto se niega a correr post-core, en vez de degradar). Responde tu condicional: para los installs, la suite NO es "activa/rerunnable post-core" — lo son los smokes.

Abajo (§3.5 y §3.6) especifico **ambas ramas exactas** para que elijas.

---

## 3. Ediciones exactas por archivo

Formato: bloques `ANTES` → `DESPUÉS`, verbatim del HEAD `b99a0b9`. Todo patch con `str_replace count==1` + prueba de identidad reverse-replace. Indentación exacta preservada.

### 3.1 SMOKES S0–S3 — swap `58d75c1b` → `1bd96c89`

Todos comparten el patrón de gate `IF v_res IS DISTINCT FROM '58d75c1b…' THEN RAISE EXCEPTION …`. El hash completo aparece **1×** por archivo (en el IF); el swap del hash es directo. Los mensajes con forma corta `58d75c1b` / etiqueta `post-R0` se realinean con anchor descriptivo.

**S0_SMOKES** — 2 ediciones:
```
# E1 (hash del IF, anchor único)
ANTES:   IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
DESPUÉS: IF v_res IS DISTINCT FROM '1bd96c89e587b15582fd7b2e29ae7e18' THEN
# E2 (mensaje, anchor único por la frase)
ANTES:   RAISE EXCEPTION 'SMOKE S0 abortado: fingerprint resolver=% (esperado 58d75c1b, post-R0).', v_res;
DESPUÉS: RAISE EXCEPTION 'SMOKE S0 abortado: fingerprint resolver=% (esperado 1bd96c89, post-core).', v_res;
```

**S1_SMOKES** — 1 edición (el hash completo y la forma corta están en la MISMA línea; se reemplaza la línea entera):
```
ANTES:   IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN RAISE EXCEPTION 'SMOKE S1 abortado: resolver=% (esperado 58d75c1b).', v_res; END IF;
DESPUÉS: IF v_res IS DISTINCT FROM '1bd96c89e587b15582fd7b2e29ae7e18' THEN RAISE EXCEPTION 'SMOKE S1 abortado: resolver=% (esperado 1bd96c89).', v_res; END IF;
```

**S2_SMOKES** — 1 edición (mensaje sin forma corta):
```
ANTES:   IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN RAISE EXCEPTION 'SMOKE S2 abortado: resolver=%.', v_res; END IF;
DESPUÉS: IF v_res IS DISTINCT FROM '1bd96c89e587b15582fd7b2e29ae7e18' THEN RAISE EXCEPTION 'SMOKE S2 abortado: resolver=%.', v_res; END IF;
```

**S3_SMOKES** — 1 edición (idéntico patrón a S2):
```
ANTES:   IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN RAISE EXCEPTION 'SMOKE S3 abortado: resolver=%.', v_res; END IF;
DESPUÉS: IF v_res IS DISTINCT FROM '1bd96c89e587b15582fd7b2e29ae7e18' THEN RAISE EXCEPTION 'SMOKE S3 abortado: resolver=%.', v_res; END IF;
```

**Nota de invariancia funcional:** los smokes S0–S3 ejercitan overrides sin vigencias activas. Con 0 vigencias, el resolver post-core es idéntico a R0 (invariante de core). Por eso las aserciones de comportamiento se preservan; **solo cambia el fingerprint del gate**. (El único smoke que crea una vigencia y por ende cambia de comportamiento es B1.1 — §3.2.)

### 3.2 B1.1 SMOKE — swap + DC-C5 (gate exacto) + INV-1 comportamental

**Hallazgo central (lo más importante del barrido):** el caso **AISLA** (hoy) crea una vigencia con `hora_checkin_default=15:00` que cubre `v_i` y afirma que `resolver_horario(1, v_i)` = `13:00:00|base` — es decir, **el resolver IGNORA la vigencia** (comportamiento PRE-core). **Post-core esa aserción se invierte:** el wrapper ahora RESPETA la vigencia. Esto no es un swap de fp: es la mitad comportamental de DC-C5.

**Edición A — captura de fps del interno/helper + gate fail-closed exacto.**
Vars nuevas en el `DECLARE` del bloque `$smoke$` (anchor: la línea `v_res_fp_pre  TEXT;  v_res_fp_post TEXT;`):
```
ANTES:   v_res_fp_pre  TEXT;  v_res_fp_post TEXT;
DESPUÉS: v_res_fp_pre  TEXT;  v_res_fp_post TEXT;
  v_int_fp      TEXT;  v_hlp_fp     TEXT;
  v_int_res     jsonb; v_int_ci     TEXT; v_int_ori TEXT;
```
Gate exacto, insertado tras la captura `v_odr_fp_pre := …` (anchor único):
```
ANTES:
  v_odr_fp_pre := md5(pg_get_functiondef('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
DESPUÉS:
  v_odr_fp_pre := md5(pg_get_functiondef('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  -- ---- GATE DC-C5: estado post-core exacto (fail-closed) ----
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NULL THEN
    RAISE EXCEPTION 'SMOKE B1.1 abortado: falta interno _resolver_horario (core B1.2 no aplicado). Cadena: R0 -> B1.1 -> core.';
  END IF;
  v_int_fp := md5(pg_get_functiondef('_resolver_horario(bigint,date,boolean)'::regprocedure));
  v_hlp_fp := md5(pg_get_functiondef('vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)'::regprocedure));
  IF v_res_fp_pre IS DISTINCT FROM '1bd96c89e587b15582fd7b2e29ae7e18' THEN
    RAISE EXCEPTION 'SMOKE B1.1 abortado: wrapper fp=% (esperado 1bd96c89, post-core).', v_res_fp_pre;
  END IF;
  IF v_int_fp IS DISTINCT FROM '566ea522351a6b4e57b6dd770124814b' THEN
    RAISE EXCEPTION 'SMOKE B1.1 abortado: interno fp=% (esperado 566ea522).', v_int_fp;
  END IF;
  IF v_hlp_fp IS DISTINCT FROM '871fcde54be66b47c3e303e73b893c24' THEN
    RAISE EXCEPTION 'SMOKE B1.1 abortado: helper fp=% (esperado 871fcde5).', v_hlp_fp;
  END IF;
  IF v_odr_fp_pre IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'SMOKE B1.1 abortado: ODR fp=% (esperado 37009a32).', v_odr_fp_pre;
  END IF;
```

**Edición B — transformar AISLA en INV-1 comportamental.** Reemplazo del bloque completo (anchor: el `BEGIN … PERFORM pg_temp.rec('AISLA',…)`):
```
ANTES:
  BEGIN
    v_res := public.crear_vigencia_horario(jsonb_build_object(
      'fecha_desde',(v_i-3)::text,'fecha_hasta',(v_i+3)::text,
      'hora_checkin_default','15:00','hora_checkin_domingo','18:00',
      'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','aislamiento','creado_por','smoke'));
    SELECT resolver_horario(1, v_i) INTO v_resolver;
    v_ci_res := v_resolver->>'hora_checkin';
    v_origen := v_resolver->>'origen_checkin';
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '__RB__' THEN v_ci_res := 'EXC:'||SQLERRM; v_origen := '?'; END IF;
  END;
  PERFORM pg_temp.rec('AISLA','resolver ignora vigencia (13:00/base)','13:00:00|base',
    coalesce(v_ci_res,'?')||'|'||coalesce(v_origen,'?'));
DESPUÉS:
  BEGIN
    v_res := public.crear_vigencia_horario(jsonb_build_object(
      'fecha_desde',(v_i-3)::text,'fecha_hasta',(v_i+3)::text,
      'hora_checkin_default','15:00','hora_checkin_domingo','18:00',
      'hora_checkout_default','10:00','hora_checkout_domingo','16:00','motivo','aislamiento','creado_por','smoke'));
    -- INV-1 (post-core): interno CIEGO (flag=false) ignora la vigencia => config/base 13:00;
    --   wrapper publico (delega en flag=true) RESPETA la vigencia que cubre v_i => 15:00.
    SELECT public._resolver_horario(1, v_i, false) INTO v_int_res;
    v_int_ci  := v_int_res->>'hora_checkin';
    v_int_ori := v_int_res->>'origen_checkin';
    SELECT resolver_horario(1, v_i) INTO v_resolver;
    v_ci_res := v_resolver->>'hora_checkin';
    v_origen := v_resolver->>'origen_checkin';
    RAISE EXCEPTION '__RB__';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '__RB__' THEN
      v_int_ci := 'EXC'; v_int_ori := '?'; v_ci_res := 'EXC:'||SQLERRM; v_origen := '?';
    END IF;
  END;
  PERFORM pg_temp.rec('INV-1','interno ciego (flag=false) ignora vigencia','13:00:00|base',
    coalesce(v_int_ci,'?')||'|'||coalesce(v_int_ori,'?'));
  PERFORM pg_temp.rec('INV-1','wrapper respeta vigencia que cubre la fecha','15:00:00|vigencia',
    coalesce(v_ci_res,'?')||'|'||coalesce(v_origen,'?'));
```

**Valores esperados (verificados contra el cuerpo del interno de core, líneas 131–141):** interno ciego no-domingo → base config `13:00:00`, origen `'base'`; wrapper con vigencia cubriendo la fecha no-domingo → `15:00:00`, origen `'vigencia'` (no `'vigencia_domingo'`, porque `v_i` se fuerza no-domingo en la línea 86).

**Edición C (opcional, evidencia) — META-C exacto.** Los rec META-C actuales solo comparan invariancia pre==post. Se pueden fortalecer para que el resultado consolidado muestre los fps exactos (además del gate fail-closed de Edición A). Recomendado por trazabilidad; lo confirmás:
```
ANTES:
  PERFORM pg_temp.rec('META-C','fingerprint resolver intacto', v_res_fp_pre, v_res_fp_post);
  PERFORM pg_temp.rec('META-C','fingerprint ODR intacto', v_odr_fp_pre, v_odr_fp_post);
DESPUÉS:
  PERFORM pg_temp.rec('META-C','fingerprint resolver intacto', v_res_fp_pre, v_res_fp_post);
  PERFORM pg_temp.rec('META-C','fingerprint ODR intacto', v_odr_fp_pre, v_odr_fp_post);
  PERFORM pg_temp.rec('META-C','wrapper fp = 1bd96c89 (post-core)', '1bd96c89e587b15582fd7b2e29ae7e18', v_res_fp_pre);
  PERFORM pg_temp.rec('META-C','interno fp = 566ea522', '566ea522351a6b4e57b6dd770124814b', v_int_fp);
  PERFORM pg_temp.rec('META-C','helper fp = 871fcde5', '871fcde54be66b47c3e303e73b893c24', v_hlp_fp);
```

### 3.3 ROLLBACKS S1–S3 / B1.1 — gate fail-closed + conservar `58d75c1b` (tu Punto 1)

Gate insertado en el bloque de gate existente, **antes** de cualquier DROP. Mensaje literal según tu pedido. En S1/S2/S3 es disciplina de orden (dropean objetos de override/paquete que core NO usa); en **B1.1 es seguridad dura** (dropea `vigencias_horario_base` + helper, de los que el interno/wrapper de core dependen → sin gate, correrlo post-core rompe core).

**S1_ROLLBACK** (anchor: la RAISE NOTICE del gate):
```
ANTES:
  RAISE NOTICE 'ROLLBACK S1: ambiente=test OK, quitando trigger + trigger-fn.';
DESPUÉS:
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK S1 abortado: core B1.2 sigue aplicado (interno _resolver_horario presente). Correr primero B1_2_CORE_ROLLBACK_TEST.sql. Cadena de rollback: R0 -> B1.1 -> core.';
  END IF;
  RAISE NOTICE 'ROLLBACK S1: ambiente=test OK, quitando trigger + trigger-fn.';
```

**S2_ROLLBACK** (anchor: su RAISE NOTICE; **la aserción `resolver_r0_intacto = 58d75c1b` del SELECT final queda intacta** por tu pedido):
```
ANTES:
  RAISE NOTICE 'ROLLBACK S2: ambiente=test OK, quitando crear_override_horario(jsonb).';
DESPUÉS:
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK S2 abortado: core B1.2 sigue aplicado (interno _resolver_horario presente). Correr primero B1_2_CORE_ROLLBACK_TEST.sql. Cadena de rollback: R0 -> B1.1 -> core.';
  END IF;
  RAISE NOTICE 'ROLLBACK S2: ambiente=test OK, quitando crear_override_horario(jsonb).';
```

**S3_ROLLBACK** (anchor: `RAISE NOTICE 'ROLLBACK S3 GATE OK.';`):
```
ANTES:
  RAISE NOTICE 'ROLLBACK S3 GATE OK.';
DESPUÉS:
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK S3 abortado: core B1.2 sigue aplicado (interno _resolver_horario presente). Correr primero B1_2_CORE_ROLLBACK_TEST.sql. Cadena de rollback: R0 -> B1.1 -> core.';
  END IF;
  RAISE NOTICE 'ROLLBACK S3 GATE OK.';
```

**B1_1_ROLLBACK** — gate DURO (anchor: el cierre del bloque de gate; conserva las **2** ocurrencias de `58d75c1b` del postcheck `resolver_fp_ok`, correctas post-core-rollback):
```
ANTES:
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'GATE B1.1-RB: schema=% (esperado public). Abortando.', current_schema();
  END IF;
END
$gate$;
DESPUÉS:
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'GATE B1.1-RB: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'GATE B1.1-RB abortado: core B1.2 sigue aplicado (interno _resolver_horario presente). Este rollback dropea vigencias_horario_base y el helper, de los que el interno/wrapper de core dependen. Correr primero B1_2_CORE_ROLLBACK_TEST.sql. Cadena: R0 -> B1.1 -> core.';
  END IF;
END
$gate$;
```

**Variables:** ningún rename es necesario. `resolver_r0_intacto` / `resolver_fp_ok` siguen siendo semánticamente correctos post-core-rollback (el resolver ES R0 de nuevo). Se mantienen.

### 3.4 R0 rollback — [FLAG de alcance, recomiendo incluirlo]

`HORARIOS_R0_RESOLVER_ROLLBACK_TEST.sql` **no** tiene literal `58d75c1b` (restaura a `759662b4` vía `CREATE OR REPLACE`), así que **no es target del swap**. Pero tu DC-C2 literal lo dejó fuera ("S0–S3/B1.1"). Hallazgo: correrlo post-core hace `CREATE OR REPLACE` sobre el wrapper y **desconecta silenciosamente vigencias**, dejando el interno huérfano (aún referencia `vigencias_horario_base`). Es el mismo hueco que B1.1 rollback.

**Recomendación:** darle el mismo gate fail-closed por simetría de cadena (es seguridad, no cambio de fp). Anchor: `RAISE NOTICE 'GATE R0-ROLLBACK OK: …';`. Insertar antes:
```
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'GATE R0-ROLLBACK abortado: core B1.2 sigue aplicado (interno presente); R0-rollback sobrescribiria el wrapper y desconectaria vigencias. Correr primero B1_2_CORE_ROLLBACK_TEST.sql, luego B1_1_ROLLBACK_TEST.sql. Cadena: R0 -> B1.1 -> core.';
  END IF;
```
**Decisión tuya:** ¿entra en scope de cascade (recomendado) o queda como superseded sin tocar?

### 3.5 BUILDS S0–S3 (archivos 11–16, sin CREATE_VIGENCIA) — según DD-CASCADE

Patrón idéntico en los 6: gate `v_res := md5(…); IF v_res IS DISTINCT FROM '58d75c1b…' THEN RAISE …; END IF;`.

**Bajo Path 1 (recomendado):** conservar `58d75c1b`; insertar gate fail-closed defense-in-depth tras el bloque del resolver-fp (anchor por archivo = su RAISE EXCEPTION de gate, todos únicos):
```
# insertar después del END IF; del check de resolver, antes de la captura de v_odr:
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'GATE <STAGE>: core B1.2 aplicado (interno presente); este es un paso de build pre-core (cadena R0 -> B1.1 -> core). No re-ejecutar con core aplicado; la red de regresion post-core son los smokes. Abortando.';
  END IF;
```
`<STAGE>` = `S0` / `S1` / `S2` / `S3` / `B1.1-DDL` / `B1.1-TRG` respectivamente. Anchors exactos (líneas de gate ya localizadas): S0-VAL `'GATE S0: fingerprint resolver=% (esperado 58d75c1b…'`; S1-TRIG `'GATE S1: fingerprint resolver=%...'`; S2-FN `'GATE S2: resolver=%...'`; S3-FN `'GATE S3: resolver=%...'`; B1.1-DDL `'GATE B1.1-DDL: fingerprint resolver=%...'`; B1.1-TRG `'GATE B1.1-TRG: fingerprint resolver=%...'`.

**Bajo Path 2:** en cada uno, swap `58d75c1b` → `1bd96c89` en el IF + mensaje, y cambiar el gate por "el interno DEBE existir" (invertir la condición del guard). (Especifico los 6 pares exactos si elegís Path 2.)

### 3.6 B1.1 CREATE_VIGENCIA (archivo 17) — tu Opción A ↔ B, ambas exactas

Este archivo tiene **2× `58d75c1b`** (gate del resolver + comentario de `crear_vigencia_horario`) y **recrea el helper** con cuerpo viejo (autorreferencia vía `resolver_horario`).

#### Opción A (Path 1, RECOMENDADO) — queda pre-core, con guarda anti-degradación

- Conservar `58d75c1b` (ambas ocurrencias: gate línea ~31 y comentario "(fingerprint 58d75c1b intacto)").
- Conservar el cuerpo viejo del helper (correcto pre-core).
- Gate fail-closed **obligatorio** (anchor: `IF to_regclass('public.vigencias_horario_base') IS NULL THEN RAISE EXCEPTION 'GATE B1.1-FN: falta vigencias_horario_base…`; insertar el guard antes de ese check o tras el resolver-check):
```
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'GATE B1.1-FN: core B1.2 aplicado (interno presente). Este artefacto recrea el helper con el cuerpo pre-core (autorreferencia); re-ejecutarlo post-core DEGRADARIA G1 (revierte INV-1). El helper post-core lo instala B1.2-core. Correr primero B1_2_CORE_ROLLBACK_TEST.sql si necesitas reconstruir por capas. Abortando.';
  END IF;
```
- Anotación en el header (la DEUDA DURA B1.2, líneas 10–16): agregar una línea "→ DEUDA descargada por B1.2-core: el helper se refactoriza a `_resolver_horario(...,false)` [INV-1]; este artefacto queda como paso de build pre-core."

#### Opción B (Path 2) — realinear al post-core (cuerpo ciego)

Delta del cuerpo del helper **probado por diff**: exactamente **5 líneas** (cuerpo por lo demás byte-idéntico → produce `871fcde5`). Cada una con anchor único:
```
# B1 y B2: reservas -> public.reservas (2×, anchor con el SELECT previo)
ANTES:   SELECT 'reserva'::text AS tipo, id_reserva AS id, id_cabana, fecha_checkout AS fecha, 'checkout'::text AS lado, hora_checkout AS frozen
      FROM reservas WHERE estado IN ('confirmada','activa','completada')
DESPUÉS: SELECT 'reserva'::text AS tipo, id_reserva AS id, id_cabana, fecha_checkout AS fecha, 'checkout'::text AS lado, hora_checkout AS frozen
      FROM public.reservas WHERE estado IN ('confirmada','activa','completada')

ANTES:   SELECT 'reserva', id_reserva, id_cabana, fecha_checkin, 'checkin', hora_checkin
      FROM reservas WHERE estado IN ('confirmada','activa','completada')
DESPUÉS: SELECT 'reserva', id_reserva, id_cabana, fecha_checkin, 'checkin', hora_checkin
      FROM public.reservas WHERE estado IN ('confirmada','activa','completada')

# B3 y B4: pre_reservas -> public.pre_reservas (2×)
ANTES:   SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_out, 'checkout', hora_checkout
      FROM pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'
DESPUÉS: SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_out, 'checkout', hora_checkout
      FROM public.pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'

ANTES:   SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_in, 'checkin', hora_checkin
      FROM pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'
DESPUÉS: SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_in, 'checkin', hora_checkin
      FROM public.pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'

# B5: la línea INV-1 (única)
ANTES:      CROSS JOIN LATERAL (SELECT resolver_horario(c.id_cabana, c.fecha) AS res) r
DESPUÉS:    CROSS JOIN LATERAL (SELECT public._resolver_horario(c.id_cabana, c.fecha, false) AS res) r
```
Más: swap `58d75c1b` → `1bd96c89` en gate (línea ~31) + comentario (línea ~272); invertir el guard del resolver a "el interno DEBE existir"; agregar postcheck del helper `= 871fcde5`; realinear el COMMENT del helper (líneas 107–108) al de core (ciego/INV-1).
**Advertencia:** el `CREATE OR REPLACE` del helper con cuerpo ciego **requiere que `_resolver_horario` exista** en tiempo de compilación (`check_function_bodies`), por eso el artefacto queda post-core-only y rompe el orden de rebuild.

**Verificación de fp en Opción B:** el diff prueba que el cuerpo pasa a ser byte-idéntico al de core; como `pg_get_functiondef` de una función `LANGUAGE sql` con cuerpo-string emite `prosrc` verbatim, el md5 será `871fcde5`. Se confirmará empíricamente en el harness PG16.14 al construir el artefacto.

### 3.7 DOCS (DC-02 + DC-04)

**R0 FIX** (`HORARIOS_R0_RESOLVER_FIX_TEST.sql`) — banner SUPERSEDED al tope del comentario de cabecera. Sus referencias internas a `759662b4` (su propia precondición pre-fix) quedan; no emite `58d75c1b` como literal (lo reporta el SELECT). Texto del banner:
```
-- [SUPERSEDED por B1.2-core] El fingerprint que este FIX produce (58d75c1b, R0)
--   fue reemplazado por el wrapper post-core 1bd96c89. R0 permanece como capa
--   historica de la cadena R0 -> B1.1 -> core; este artefacto no se re-ejecuta
--   como paso vivo. Ver CIERRE_TECNICO_PRELIMINAR_B1_2_CORE.md.
```
**R0 RUNSHEET** — mismo banner (bloque markdown al tope). Su tabla de transición `759662b4 → …` queda como registro histórico.

**Runsheets S0–S3** — bajo **Path 1**: sus referencias a `58d75c1b` describen los **gates de build** (que conservan `58d75c1b`) → **quedan intactas** (siguen siendo correctas). Bajo Path 2: swap `58d75c1b` → `1bd96c89` en cada referencia (S0 línea 39, S1 línea 47, S2 línea 71, S3 línea 108). *Verificar por-referencia al generar: si alguna describe el gate del smoke, swapea aunque sea Path 1.*

**Cierres técnicos preliminares** (ALTA_OVERRIDES, B1.1_VIGENCIAS, B1.2_CORE) — **inmutables**. NO se tocan (DC-C4).

### 3.8 HISTÓRICO (DC-C1) — B1.2-pre

`B1_2_PRE_BASELINE_PERF_120D_TEST.sql` y `B1_2_PRE_DIAGNOSTICO_G1_TEST.sql`: anotar como histórico/spent con un banner al tope; **no rearmar** baseline ni diagnóstico G1. Texto:
```
-- [HISTORICO/SPENT — B1.2-pre] Diagnostico/baseline consumido antes de B1.2-core.
--   No re-ejecutar ni realinear a fps post-core. Registro de la fase pre-cableado.
```

---

## 4. Método de ejecución del barrido (cuando apruebes)

- **Patchers Python** con `str_replace` `count==1` + prueba de identidad reverse-replace por edición. Verificador estructural antes de cada import.
- **Smokes re-armados** (S0–S3 + B1.1) validados en harness: `pglast` → PostgreSQL 16.14 local (cadena R0 → B1.1 → core) → recién ahí a TEST. En el harness se confirma empíricamente el `871fcde5` del helper si elegís Opción B.
- **EOL:** LF puro preservado en los 20 archivos (verificado `i/lf`). ASCII puro; sin fuga de fps del harness local.
- **Orden de entrega:** primero los patches sin riesgo (smokes swap, rollback gates, docs), luego el grupo BUILD según DD-CASCADE, por último re-validación de la cadena completa en harness.
- Franco ejecuta en TEST y verifica; un bloque, hard stop.
- **D-*/L-* diferidos** al cierre formal del Motor (los IDs provisionales en comentarios son deuda cosmética documentada, corregida pre-producción).

---

## 5. Antes de generar artefactos — a confirmar

1. **DD-CASCADE (§2):** ¿Path 1 (installs quedan pre-core, `58d75c1b` + guarda; smokes = red de regresión) — recomendado — o Path 2 (installs realineados post-core, rompe orden de rebuild)? Esto fija de una el tratamiento de los 7 builds + CREATE_VIGENCIA.
2. **CREATE_VIGENCIA (§3.6):** consecuencia directa de (1) — Opción A (recom.) u Opción B. Ambas especificadas exactas; el diff de las 5 líneas de la Opción B ya está probado.
3. **R0 rollback (§3.4):** ¿entra en scope con gate fail-closed (recom., por seguridad de cadena) o queda superseded sin tocar?
4. **META-C evidencia (§3.2 Edición C):** ¿agregamos los rec de fps exactos al resultado consolidado del smoke B1.1 (recom.) o alcanza con el gate fail-closed?

Con esas cuatro resueltas, genero los patchers + smokes re-armados y los valido en el harness antes de pasártelos.
