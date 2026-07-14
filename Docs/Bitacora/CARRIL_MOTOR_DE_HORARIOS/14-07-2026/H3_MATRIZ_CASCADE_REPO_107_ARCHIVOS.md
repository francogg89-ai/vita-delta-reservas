# H3 — MATRIZ CASCADE DEL REPO · 107 ARCHIVOS  *(v3 — corregida)*

**Bloque:** `B1.3-consolidacion-canonica`  
**HEAD:** `07fea85802bc4fccbff1236813593762aefe58d9` (rama `main`, árbol limpio)  
**Alcance:** `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/` — **107 archivos versionados**, uno por fila.

> **Documento diagnóstico. Fuera del repo.**

## Cambios en v3

| Fila | Corrección |
|---|---|
| **16** | `~24 invocaciones de S3` → **`21 invocaciones reales`** (recuento del barrido H7) |
| **4, 8, 9, 86** | `accion_v1_13` = **`PENDIENTE_D2`**. Eran `CONSOLIDAR`, lo cual **contradecía el propio diccionario**: `CONSOLIDAR` significa *entra al canónico*, y el D2 todavía no corrió |
| **70** | `autoridad_actual` = **`PENDIENTE_H1`**. No puede ser `SI` mientras la cadena de custodia y la sanitización del A07 sigan bloqueadas |

`CONSOLIDAR` baja de 12 a **8**. `autoridad_actual = SI` baja de 9 a **8**.

---

## El hallazgo que separó autoridad de ejecutabilidad

Los gates de S0/S1/S2 (y de B1.1 y B1.2-core) hardcodean el fingerprint **viejo** del resolver:

```sql
IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
  RAISE EXCEPTION 'GATE S0: fingerprint resolver=% ... Abortando.', v_res;
```

El vivo es **`1bd96c89e587b15582fd7b2e29ae7e18`**. **Esos scripts abortan hoy.**

```
$ grep -rlE "IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d'" --include=*.sql .
  -> 15 archivos
```

Un archivo puede ser autoridad de un **cuerpo de función** y a la vez un **script muerto**. `06-07/B1_2_CORE_MIGRACION_TEST.sql` es el caso claro: su `CREATE` de `resolver_horario` sigue siendo la autoridad del wrapper vivo, pero el script es un one-shot que ya corrió y no se puede re-ejecutar.

---

## Diccionario

| Columna | Valores |
|---|---|
| `estado` | `VIGENTE` · `SUPERADO` · `HISTORICO` · `DUPLICADO` · `COLISION_DIVERGENTE` · `CONTAMINACION` |
| `autoridad_actual` | `SI` = probada contra el vivo · `CANDIDATO_REPO_HASTA_D2` = el repo lo dice, TEST no lo confirmó · `PENDIENTE_H1` = bloqueada por cadena de custodia · `PARCIAL` · `NO` |
| `dominio_autoridad` | `CUERPO_FN` · `TRIGGER` · `DDL` · `ACL` · `APP_FRONTEND` · `APP_N8N` · `NINGUNO` |
| `fragmento_autoritativo` | Qué parte del archivo manda. El gate y el script casi nunca lo son |
| `estado_script` | `EJECUTABLE` · `NO_EJECUTABLE_GATE_OBSOLETO` (aborta: gatea `58d75c1b`) · `NO_APLICA` |
| `accion_v1_13` | **`CONSOLIDAR` = entra al canónico SQL (6B)** · `PENDIENTE_D2` · `CITAR` · `ARCHIVAR` · `ARCHIVAR_EVIDENCIA` · `PRESERVAR_APP` · `RECLASIFICAR` · `BLOQUEADO_H1` |

## Resumen

| estado | n | | autoridad_actual | n | | accion_v1_13 | n | | estado_script | n |
|---|---|---|---|---|---|---|---|---|---|---|
| `VIGENTE` | 59 | | `NO` | 93 | | `CITAR` | 58 | | `EJECUTABLE` | 47 |
| `HISTORICO` | 26 | | `SI` | 8 | | `ARCHIVAR` | 31 | | `NO_APLICA` | 45 |
| `SUPERADO` | 16 | | `CANDIDATO_REPO_HASTA_D2` | 4 | | `CONSOLIDAR` | 8 | | `NO_EJECUTABLE_GATE_OBSOLETO` | 15 |
| `CONTAMINACION` | 3 | | `PARCIAL` | 1 | | `PENDIENTE_D2` | 4 | |  |  |
| `COLISION_DIVERGENTE` | 2 | | `PENDIENTE_H1` | 1 | | `RECLASIFICAR` | 3 | |  |  |
| `DUPLICADO` | 1 | |  |  | | `PRESERVAR_APP` | 1 | |  |  |
|  |  | |  |  | | `BLOQUEADO_H1` | 1 | |  |  |
|  |  | |  |  | | `ARCHIVAR_EVIDENCIA` | 1 | |  |  |

**Sólo 8 archivos entran al canónico SQL.** Otros 4 esperan al D2. Uno espera a H1.

---

## Autoridad probada contra el vivo — 8 archivos (+1 parcial)

| Objeto vivo (pineado) | Artefacto | dominio | estado_script |
|---|---|---|---|
| `resolver_horario` (wrapper) | `06-07/B1_2_CORE_MIGRACION_TEST.sql` | CUERPO_FN | **NO_EJECUTABLE** (gatea 58d75c1b) |
| `_resolver_horario`, `vigencias_conflictos_comprometidos`,<br>`crear_vigencia_horario`, `trg_guard_vigencias`,<br>2 triggers, **DDL de vigencias** | `08-07/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | CUERPO_FN + TRIGGER + DDL + ACL | EJECUTABLE |
| `validar_gap_bordes_congelados` | `08-07/B1_3_B_VALIDADOR_GAP_TEST.sql` | CUERPO_FN + ACL | EJECUTABLE |
| `crear_prereserva` | `08-07/B1_3_C_PATCH_CREAR_PRERESERVA_TEST.sql` | CUERPO_FN | EJECUTABLE |
| `confirmar_reserva` | **`09-07/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql`** | CUERPO_FN | EJECUTABLE |
| `crear_reserva_con_horario_pactado` | `09-07/B1_3_E_CREAR_RESERVA_PACTADA_TEST.sql` | CUERPO_FN + ACL | EJECUTABLE |
| `crear_override_horario_puntual` | `09-07/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | CUERPO_FN + ACL | EJECUTABLE |
| `obtener_disponibilidad_rango` | `HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql` | CUERPO_FN | EJECUTABLE |

## `PENDIENTE_D2` — 4 archivos

Crean objetos vivos o presuntamente vivos que **no están pineados** y que **nadie midió contra TEST**. **No entran al canónico hasta que el D2 corra.**

| # | Artefacto | Objetos | estado_script |
|---|---|---|---|
| 4 | `04-07/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql` | `validar_estado_horario_final` **(viva — Q6)**, `validar_no_eventos_comprometidos`, `validar_estado_override` | **NO_EJECUTABLE** |
| 8 | `04-07/HORARIOS_GUARD_S1_TRIGGER_TEST.sql` | `trg_guard_overrides()` + `trg_ov_guard` | **NO_EJECUTABLE** |
| 9 | `04-07/HORARIOS_GUARD_S2_FUNCION_TEST.sql` | `crear_override_horario(jsonb)` | **NO_EJECUTABLE** |
| 86 | `HORARIOS_B2_GUARD_HELPER_TEST.sql` | `crear_bloqueo(jsonb)`, `fecha_hoy_ar()` | EJECUTABLE (sin gate de fingerprint) |

## `PENDIENTE_H1` — 1 archivo

| # | Artefacto | Motivo |
|---|---|---|
| 70 | `10-07/portal-a07-crear-reserva__TEMPLATE.PATCHED.json` | Cadena de custodia y sanitización **bloqueadas**. Sin hash del crudo, hash del sanitizado, manifiesto de paths alterados y confirmación de que no cambiaron nodos/conexiones/`jsCode`, **no puede declararse autoridad de nada** |

---

## Matriz — 107 filas

| # | ruta | fecha | bloque | tipo | estado | autoridad_actual | dominio_autoridad | fragmento_autoritativo | estado_script | referencia_viva | superado_por | accion_v1_13 | motivo | sha256 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `04-07-2026/HORARIOS_GUARD_ALTA_OVERRIDES_CIERRE_TECNICO_PRELIMINAR.md` | 04-07-2026 | GUARD-cierre | MD_CIERRE | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre preliminar de S0-S3. S3 ya no existe; el resto sigue vivo pero sin pin. | `3ee96779128f` |
| 2 | `04-07-2026/HORARIOS_GUARD_S0_RUNSHEET.md` | 04-07-2026 | GUARD-S0 | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de S0. Negative-scope explicito sobre S1/S2/S3. | `18f88c2cb5ed` |
| 3 | `04-07-2026/HORARIOS_GUARD_S0_SMOKES_TEST.sql` | 04-07-2026 | GUARD-S0 | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | `validar_estado_horario_final` | — | ARCHIVAR | Smoke de S0. Helpers temporales en BEGIN..ROLLBACK. | `dc06fc3a5e41` |
| 4 | `04-07-2026/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql` | 04-07-2026 | GUARD-S0 | SQL_MIGRACION | VIGENTE | **CANDIDATO_REPO_HASTA_D2** | CUERPO_FN | CREATE de los 3 validadores S0 (no el gate, no el script) | **NO_EJECUTABLE_GATE_OBSOLETO** | `validar_estado_horario_final, validar_no_eventos_comprometidos, validar_estado_override` | — | **PENDIENTE_D2** | CANDIDATO a autoridad del CUERPO de los 3 validadores S0. validar_estado_horario_final CONFIRMADA VIVA por Q6. NO esta en el pin de 11. Script NO re-ejecutable: su gate espera resolver 58d75c1b y el vivo es 1bd96c89. NO entra al canonico hasta que D2 lo mida contra TEST. | `4708bb164965` |
| 5 | `04-07-2026/HORARIOS_GUARD_S1_ROLLBACK_TEST.sql` | 04-07-2026 | GUARD-S1 | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `trg_ov_guard, trg_guard_overrides` | — | CITAR | Rollback de S1. Vigente si S1 sigue vivo (no verificado en D1). | `cde0bc9bd5ed` |
| 6 | `04-07-2026/HORARIOS_GUARD_S1_RUNSHEET.md` | 04-07-2026 | GUARD-S1 | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de S1. | `737f137b0e3b` |
| 7 | `04-07-2026/HORARIOS_GUARD_S1_SMOKES_TEST.sql` | 04-07-2026 | GUARD-S1 | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | `trg_ov_guard` | — | ARCHIVAR | Smoke de S1. | `dd3f8f5ed124` |
| 8 | `04-07-2026/HORARIOS_GUARD_S1_TRIGGER_TEST.sql` | 04-07-2026 | GUARD-S1 | SQL_MIGRACION | VIGENTE | **CANDIDATO_REPO_HASTA_D2** | CUERPO_FN + TRIGGER | CREATE trg_guard_overrides() + CREATE CONSTRAINT TRIGGER trg_ov_guard (lin. 152-155) | **NO_EJECUTABLE_GATE_OBSOLETO** | `trg_guard_overrides, trg_ov_guard` | — | **PENDIENTE_D2** | CANDIDATO a autoridad del CUERPO de trg_guard_overrides + trg_ov_guard. NO esta en el pin de 11 ni fue consultado por Q4. Script NO re-ejecutable: su gate espera resolver 58d75c1b y el vivo es 1bd96c89. NO entra al canonico hasta que D2 lo mida contra TEST. | `7bcef3c4c1fc` |
| 9 | `04-07-2026/HORARIOS_GUARD_S2_FUNCION_TEST.sql` | 04-07-2026 | GUARD-S2 | SQL_MIGRACION | VIGENTE | **CANDIDATO_REPO_HASTA_D2** | CUERPO_FN | CREATE de crear_override_horario(jsonb) | **NO_EJECUTABLE_GATE_OBSOLETO** | `crear_override_horario` | — | **PENDIENTE_D2** | CANDIDATO a autoridad del CUERPO de crear_override_horario (S2). NO esta en el pin de 11. F NO la reemplaza (F reemplazo a S3). Script NO re-ejecutable: su gate espera resolver 58d75c1b y el vivo es 1bd96c89. NO entra al canonico hasta que D2 lo mida contra TEST. | `632adaac7363` |
| 10 | `04-07-2026/HORARIOS_GUARD_S2_ROLLBACK_TEST.sql` | 04-07-2026 | GUARD-S2 | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `crear_override_horario` | — | CITAR | Rollback de S2. | `a200c7a6580b` |
| 11 | `04-07-2026/HORARIOS_GUARD_S2_RUNSHEET.md` | 04-07-2026 | GUARD-S2 | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de S2. | `5d27dd404857` |
| 12 | `04-07-2026/HORARIOS_GUARD_S2_SMOKES_TEST.sql` | 04-07-2026 | GUARD-S2 | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | `crear_override_horario` | — | ARCHIVAR | Smoke de S2. | `bf6548df2811` |
| 13 | `04-07-2026/HORARIOS_GUARD_S3_FUNCION_TEST.sql` | 04-07-2026 | GUARD-S3 | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | ARCHIVAR | CREA crear_paquete_dia_especial (S3). S3 AUSENTE del vivo (Q7). Reemplazada por F. | `c6cf43e1abe8` |
| 14 | `04-07-2026/HORARIOS_GUARD_S3_ROLLBACK_TEST.sql` | 04-07-2026 | GUARD-S3 | SQL_ROLLBACK | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | ARCHIVAR | Dropea S3. Ya no aplica: S3 no existe. | `ded094625308` |
| 15 | `04-07-2026/HORARIOS_GUARD_S3_RUNSHEET.md` | 04-07-2026 | GUARD-S3 | MD_RUNSHEET | **SUPERADO** | NO | NINGUNO | — | NO_APLICA | — | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | ARCHIVAR | Runsheet de S3. | `d36512ce5a5d` |
| 16 | `04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql` | 04-07-2026 | GUARD-S3 | SQL_SMOKE | **SUPERADO** | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | ARCHIVAR | 21 invocaciones reales de S3 (barrido H7). Inejecutable: S3 no existe. | `2caa6a765090` |
| 17 | `04-07-2026/HORARIOS_R0_RESOLVER_FIX_TEST.sql` | 04-07-2026 | R0-resolver | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | ARCHIVAR | Fix R0 de resolver_horario. B1.2-CORE reescribio wrapper + interno. | `41bc861abb0d` |
| 18 | `04-07-2026/HORARIOS_R0_RESOLVER_PREFLIGHT_TEST.sql` | 04-07-2026 | R0-resolver | SQL_DIAG | HISTORICO | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR | Preflight diagnostico de R0. | `8c54bbe47625` |
| 19 | `04-07-2026/HORARIOS_R0_RESOLVER_ROLLBACK_TEST.sql` | 04-07-2026 | R0-resolver | SQL_ROLLBACK | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | ARCHIVAR | Rollback de un fix superado. | `202061b03cad` |
| 20 | `04-07-2026/HORARIOS_R0_RESOLVER_RUNSHEET.md` | 04-07-2026 | R0-resolver | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de R0. | `459f378bd18b` |
| 21 | `04-07-2026/HORARIOS_R0_RESOLVER_SMOKES_TEST.sql` | 04-07-2026 | R0-resolver | SQL_SMOKE | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | ARCHIVAR | Smokes de R0. | `db39b76feb1c` |
| 22 | `05-07-2026/B1_1_CREAR_VIGENCIA_FUNCION_TEST.sql` | 05-07-2026 | B1.1 | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | Firma B1.1 de vigencias_conflictos_comprometidos (7 args) + crear_vigencia_horario. Ambas reemplazadas por A (jsonb). | `d80a9a0e1fb0` |
| 23 | `05-07-2026/B1_1_GUARD_TRIGGER_TEST.sql` | 05-07-2026 | B1.1 | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | Version B1.1 de trg_guard_vigencias + los 2 triggers. A los recrea. | `5c834f714482` |
| 24 | `05-07-2026/B1_1_ROLLBACK_TEST.sql` | 05-07-2026 | B1.1 | SQL_ROLLBACK | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | Rollback de B1.1. | `44b2f486d223` |
| 25 | `05-07-2026/B1_1_SMOKES_TEST.sql` | 05-07-2026 | B1.1 | SQL_SMOKE | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | Smokes contra la firma de 7 args. | `384780f68a66` |
| 26 | `05-07-2026/B1_1_VIGENCIAS_DDL_TEST.sql` | 05-07-2026 | B1.1 | SQL_DDL | **SUPERADO** | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | DDL original de vigencias_horario_base/detalle. A las DROPEA y RECREA (lineas 107-132) => A es la autoridad del DDL. | `3abc356e0d1b` |
| 27 | `05-07-2026/B1_1_VIGENCIAS_HORARIO_BASE_CIERRE_TECNICO_PRELIMINAR.md` | 05-07-2026 | B1.1 | MD_CIERRE | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre preliminar B1.1. | `030820727e9b` |
| 28 | `05-07-2026/B1_2_PRE_BASELINE_PERF_120D_TEST.sql` | 05-07-2026 | B1.2-PRE | SQL_DIAG | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | — | ARCHIVAR | Baseline de performance pre-B1.2. Diagnostico. | `80fa4c86b3c1` |
| 29 | `05-07-2026/B1_2_PRE_DIAGNOSTICO_G1_TEST.sql` | 05-07-2026 | B1.2-PRE | SQL_DIAG | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | — | ARCHIVAR | Diagnostico G1 pre-B1.2. | `09b98b8be664` |
| 30 | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | 06-07-2026 | B1.2-CORE | SQL_MIGRACION | VIGENTE | **PARCIAL** | CUERPO_FN | CREATE de resolver_horario (wrapper). Su _resolver_horario y el helper fueron superados por A | **NO_EJECUTABLE_GATE_OBSOLETO** | `resolver_horario` | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | **CONSOLIDAR** | AUTORIDAD de resolver_horario (wrapper INTACTO, fp 1bd96c89). Su _resolver_horario y vigencias_conflictos_comprometidos fueron superados por A. | `f88f7d2e87b3` |
| 31 | `06-07-2026/B1_2_CORE_ROLLBACK_TEST.sql` | 06-07-2026 | B1.2-CORE | SQL_ROLLBACK | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | Rollback de B1.2-CORE. | `42827c111002` |
| 32 | `06-07-2026/B1_2_CORE_SMOKE_PERF_TEST.sql` | 06-07-2026 | B1.2-CORE | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR | Smoke de performance B1.2. | `1ef1fcfa53d2` |
| 33 | `06-07-2026/B1_2_CORE_SMOKE_RUTAS_TEST.sql` | 06-07-2026 | B1.2-CORE | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR | Smoke de rutas B1.2. | `1aec6e2f66a9` |
| 34 | `06-07-2026/CIERRE_TECNICO_PRELIMINAR_B1_2_CORE.md` | 06-07-2026 | B1.2-CORE | MD_CIERRE | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre preliminar B1.2-CORE. | `e62de3f15ebd` |
| 35 | `06-07-2026/INVENTARIO_Y_BARRIDO_B1_2_CASCADE.md` | 06-07-2026 | B1.2-CASCADE | MD_INVENTARIO | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Inventario del barrido B1.2-CASCADE (nunca implementado). | `cb38ec33209d` |
| 36 | `06-07-2026/KICKOFF_B1_2_CASCADE.md` | 06-07-2026 | B1.2-CASCADE | MD_KICKOFF | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Kickoff de B1.2-CASCADE. Abandonado por el pivote semanal. | `e07c594a6b96` |
| 37 | `07-07-2026/DISENO_DETALLADO_B1_2_CASCADE.md` | 07-07-2026 | B1.2-CASCADE | MD_DISENO | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | `07-07-2026/EVALUACION_PIVOTE_VIGENCIAS_SEMANALES.md` | CITAR | Diseno de B1.2-CASCADE. Descartado por el pivote a vigencias semanales. | `756dae091aa5` |
| 38 | `07-07-2026/EVALUACION_PIVOTE_VIGENCIAS_SEMANALES.md` | 07-07-2026 | pivote-semanal | MD_DISENO | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Decision del pivote a vigencias semanales. Fundamento de B1.3. | `e67acada0c2a` |
| 39 | `07-07-2026/KICKOFF_B1_3_VIGENCIAS_SEMANALES.md` | 07-07-2026 | B1.3-kickoff | MD_KICKOFF | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Kickoff de B1.3. | `7c2a9c2fcdb1` |
| 40 | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | 08-07-2026 | B1.3-A | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN + TRIGGER + DDL + ACL | CREATE de 4 fns + 2 triggers + DDL de vigencias (lin. 107-132) + REVOKEs | EJECUTABLE | `_resolver_horario, vigencias_conflictos_comprometidos, crear_vigencia_horario, trg_guard_vigencias, trg_vig_guard, trg_vig_guard_detalle, DDL vigencias` | — | **CONSOLIDAR** | AUTORIDAD de 4 de los 11 + los 2 triggers + el DDL de vigencias. Dropea el overload de 7 args (consistente con Q2 (0 overloads): la ausencia esta probada, no el comando que la produjo). | `f5cf08b3a51c` |
| 41 | `08-07-2026/B1_3_A_ROLLBACK_TEST.sql` | 08-07-2026 | B1.3-A | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Rollback de A. Vigente. | `31c2244def3b` |
| 42 | `08-07-2026/B1_3_A_SMOKE_TEST.sql` | 08-07-2026 | B1.3-A | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Smoke de A. Vigente. | `5aa95dad7419` |
| 43 | `08-07-2026/B1_3_B_ROLLBACK_TEST.sql` | 08-07-2026 | B1.3-B | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Rollback de B. Vigente. | `a6eecc988934` |
| 44 | `08-07-2026/B1_3_B_SMOKE_TEST.sql` | 08-07-2026 | B1.3-B | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Smoke de B. Vigente. | `61c2fcef5a83` |
| 45 | `08-07-2026/B1_3_B_VALIDADOR_GAP_TEST.sql` | 08-07-2026 | B1.3-B | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN + ACL | CREATE de validar_gap_bordes_congelados + REVOKE | EJECUTABLE | `validar_gap_bordes_congelados` | — | **CONSOLIDAR** | AUTORIDAD de validar_gap_bordes_congelados (fp 5c5ef50e). | `a324bb597841` |
| 46 | `08-07-2026/B1_3_C_PATCH_CREAR_PRERESERVA_TEST.sql` | 08-07-2026 | B1.3-C | SQL_PATCH | VIGENTE | **SI** | CUERPO_FN | Patcher: reescribe crear_prereserva via pg_get_functiondef + regexp_replace | EJECUTABLE | `crear_prereserva` | — | **CONSOLIDAR** | AUTORIDAD de crear_prereserva (fp 62fefb63). Patcher via pg_get_functiondef + regexp_replace. | `2b1ddd188563` |
| 47 | `08-07-2026/B1_3_C_ROLLBACK_TEST.sql` | 08-07-2026 | B1.3-C | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Rollback de C. Vigente. | `b6d283705c9a` |
| 48 | `08-07-2026/B1_3_C_SMOKE_TEST.sql` | 08-07-2026 | B1.3-C | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Smoke de C. Vigente. | `b2ce1b38c51c` |
| 49 | `08-07-2026/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` | 08-07-2026 | B1.3-D | SQL_PATCH | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `09-07-2026/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` | ARCHIVAR | *** H4 RESUELTO *** Ancla por texto literal e inserta el bloque D ANTES del BEGIN. El vivo NO tiene esta forma (firma_variante_08_07=false). | `fab12ead8fce` |
| 50 | `08-07-2026/B1_3_D_ROLLBACK_TEST.sql` | 08-07-2026 | B1.3-D | SQL_ROLLBACK | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `09-07-2026/B1_3_D_ROLLBACK_TEST.sql` | ARCHIVAR | Rollback simetrico del patch 08-07. Inaplicable al vivo. | `fd3851f4ff27` |
| 51 | `08-07-2026/B1_3_D_SMOKE_TEST.sql` | 08-07-2026 | B1.3-D | SQL_SMOKE | **DUPLICADO** | NO | NINGUNO | — | EJECUTABLE | `confirmar_reserva` | `09-07-2026/B1_3_D_SMOKE_TEST.sql` | ARCHIVAR | Byte-identico al de 09-07 (sha b9a8ddd5...). Duplicado exacto, sin conflicto. | `b9a8ddd5f9d4` |
| 52 | `09-07-2026/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` | 09-07-2026 | B1.3-D | SQL_PATCH | VIGENTE | **SI** | CUERPO_FN | Patcher: reescribe confirmar_reserva. Ancla por regex (variante 09-07) | EJECUTABLE | `confirmar_reserva` | — | **CONSOLIDAR** | *** H4 RESUELTO *** AUTORIDAD de confirmar_reserva (fp e6ac8ddc). Ancla por regex; bloque D DENTRO del BEGIN. firma_variante_09_07=true en el vivo. | `8ab4e29cf7c7` |
| 53 | `09-07-2026/B1_3_D_ROLLBACK_TEST.sql` | 09-07-2026 | B1.3-D | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `confirmar_reserva` | — | CITAR | Rollback correspondiente a la variante desplegada. El unico aplicable. | `81716cf6b3af` |
| 54 | `09-07-2026/B1_3_D_SMOKE_TEST.sql` | 09-07-2026 | B1.3-D | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `confirmar_reserva` | — | CITAR | Smoke de D. Byte-identico al de 08-07. | `b9a8ddd5f9d4` |
| 55 | `09-07-2026/B1_3_E_CREAR_RESERVA_PACTADA_TEST.sql` | 09-07-2026 | B1.3-E | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN + ACL | CREATE de crear_reserva_con_horario_pactado + REVOKE | EJECUTABLE | `crear_reserva_con_horario_pactado` | — | **CONSOLIDAR** | AUTORIDAD de crear_reserva_con_horario_pactado (fp 93c1700f). DB-only. | `5b197ed638da` |
| 56 | `09-07-2026/B1_3_E_ROLLBACK_TEST.sql` | 09-07-2026 | B1.3-E | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Rollback de E. Vigente. | `0e28c6da953f` |
| 57 | `09-07-2026/B1_3_E_SMOKE_TEST.sql` | 09-07-2026 | B1.3-E | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Smoke de E. Vigente. | `8e5f6f2e82ee` |
| 58 | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | 09-07-2026 | B1.3-F | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN + ACL | CREATE de crear_override_horario_puntual + DROP de S3 + REVOKE | EJECUTABLE | `crear_override_horario_puntual` | — | **CONSOLIDAR** | AUTORIDAD de crear_override_horario_puntual (fp 33d7ac8a). contiene el DROP de S3 (linea 118) + postcheck de ausencia (455-456). DB-only. | `917b2ec6a0d0` |
| 59 | `09-07-2026/B1_3_F_ROLLBACK_TEST.sql` | 09-07-2026 | B1.3-F | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `crear_paquete_dia_especial` | — | CITAR | Rollback de F: RECREA S3 (linea 46). Es la unica referencia legitima que crea S3 en el repo. | `ade9cc4b8d1a` |
| 60 | `09-07-2026/B1_3_F_SMOKE_TEST.sql` | 09-07-2026 | B1.3-F | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Smoke de F (15/15 verde). | `f4394477f8d3` |
| 61 | `09-07-2026/CIERRE_B1_3_Y_KICKOFF_INTEGRACION_TEST.md` | 09-07-2026 | B1.3-cierre | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Documento, no SQL. Fuente de los baselines S8, se cita. | `068d90858ccb` |
| 62 | `09-07-2026/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md` | 09-07-2026 | B1.3-cierre | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Documento, no SQL. Se cita. | `7fa040714c9c` |
| 63 | `10-07-2026/CrearReserva.PATCHED.tsx` | 10-07-2026 | integracion-A07 | TSX_FRONTEND | VIGENTE | **SI** | APP_FRONTEND | Componente React desplegado. No es SQL | NO_APLICA | — | — | PRESERVAR_APP | Frontend desplegado. NO entra al canonico SQL (6B). Se preserva y se cita. | `f0ce620b6218` |
| 64 | `10-07-2026/REPORTE_VALIDACION_A07_gap_conflicto.md` | 10-07-2026 | integracion-A07 | MD_REPORTE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Reporte de validacion de la integracion A07. | `d7980db0ced2` |
| 65 | `10-07-2026/harness_router1_crear.mjs` | 10-07-2026 | integracion-A07 | MJS_HARNESS | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Harness local del router 1 (crear). | `803ab49d83f3` |
| 66 | `10-07-2026/harness_router3_confirmar.mjs` | 10-07-2026 | integracion-A07 | MJS_HARNESS | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Harness local del router 3 (confirmar). | `ea3b2ee46e2a` |
| 67 | `10-07-2026/harness_texto_error_reserva.mjs` | 10-07-2026 | integracion-A07 | MJS_HARNESS | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Harness de textos de error. | `22eb202b7c0c` |
| 68 | `10-07-2026/patch_a07_gap_conflicto.py` | 10-07-2026 | integracion-A07 | PY_PATCHER | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Patcher Python del A07. | `73eb5c1da527` |
| 69 | `10-07-2026/patch_crear_reserva_gap_conflicto.py` | 10-07-2026 | integracion-A07 | PY_PATCHER | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Patcher Python del frontend. | `3683f6ad579e` |
| 70 | `10-07-2026/portal-a07-crear-reserva__TEMPLATE.PATCHED.json` | 10-07-2026 | integracion-A07 | JSON_WORKFLOW | VIGENTE | **PENDIENTE_H1** | APP_N8N | Workflow n8n. No es SQL. BLOQUEADO por H1 | NO_APLICA | `A07 (n8n)` | — | **BLOQUEADO_H1** | *** NUDO DE H1 *** Template A07 (sha 2c99db28..., 24 nodos, 5 refs $(), 0 huerfanas). NO puede ser autoridad mientras la cadena de custodia y la sanitizacion sigan bloqueadas. Politica durable de artefactos A07 SIN RESOLVER. | `3188bceb777b` |
| 71 | `11-07-2026/CC_L3_BLOQUE0_CIERRE.md` | 11-07-2026 | CUENTA-CORRIENTE | MD_CIERRE | **CONTAMINACION** | NO | NINGUNO | — | NO_APLICA | — | — | RECLASIFICAR | Pertenece al carril CUENTA CORRIENTE, no a Horarios. DECISION: documentar y NO mover. | `635eca352e50` |
| 72 | `11-07-2026/CC_L3_BLOQUE0_EVIDENCIAS_EJECUCION_TEST.md` | 11-07-2026 | CUENTA-CORRIENTE | MD_EVIDENCIA | **CONTAMINACION** | NO | NINGUNO | — | NO_APLICA | — | — | RECLASIFICAR | Pertenece al carril CUENTA CORRIENTE. DECISION: documentar y NO mover. | `9019f878740a` |
| 73 | `12-07-2026/QAGAP_A_SEED_TEST.sql` | 12-07-2026 | QA-gap | SQL_SEED | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `crear_prereserva, confirmar_reserva` | — | CITAR | Seed del QA formal de gaps. RUNID qagap_20260712_01. ASCII puro (unico .sql que cumple). | `590e1ff07bcf` |
| 74 | `12-07-2026/QAGAP_B_RUNBOOK_PORTAL.md` | 12-07-2026 | QA-gap | MD_RUNSHEET | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runbook del QA de gaps via portal. | `653cfba37162` |
| 75 | `12-07-2026/QAGAP_C_CLEANUP_TEST.sql` | 12-07-2026 | QA-gap | SQL_TEARDOWN | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Cleanup del QA de gaps. | `24e964a25f37` |
| 76 | `CIERRE_UI_RETIRO_SALDO_FRONTEND.md` | (raiz) | FRONTEND-CC | MD_CIERRE | **CONTAMINACION** | NO | NINGUNO | — | NO_APLICA | — | — | RECLASIFICAR | Pertenece al carril FRONTEND / CUENTA CORRIENTE. DECISION: documentar y NO mover. | `461018c2b225` |
| 77 | `FUNCION_RESGUARDO.md` | (raiz) | resguardo | MD_DUMP_JSON | HISTORICO | NO | NINGUNO | — | NO_APLICA | `crear_prereserva` | — | ARCHIVAR_EVIDENCIA | Dump JSON, no SQL. Evidencia del EOL mixto: se archiva y se cita en el doc de fidelidad. Dump JSON de pg_get_functiondef(crear_prereserva): header con \n (LF), cuerpo con \r\n (CRLF). Resguardo pre-B1.3-C. Ver D1_DECISION_FIDELIDAD_FUNCTIONDEF.md. | `2f2811b9018d` |
| 78 | `HORARIOS_A07UX_CIERRE.md` | (raiz) | A07UX | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre del mini-bloque UX A07 (override_hora_invalido -> payload_invalido). | `924530eadba1` |
| 79 | `HORARIOS_A07UX_POSTCHECK_TEST.sql` | (raiz) | A07UX | SQL_VERIF | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Postcheck del A07UX. | `a88386e64cef` |
| 80 | `HORARIOS_A07UX_RUNSHEET.md` | (raiz) | A07UX | MD_RUNSHEET | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet del A07UX. | `54d66d28ff69` |
| 81 | `HORARIOS_A07UX_SETUP_TEARDOWN_POSTCHECK_TEST.sql` | (raiz) | A07UX | SQL_VERIF | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Setup+teardown+postcheck combinado del A07UX. | `3ce1084eaa1a` |
| 82 | `HORARIOS_A07UX_SETUP_TEST.sql` | (raiz) | A07UX | SQL_SETUP | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Setup del A07UX. | `95f78fa788b0` |
| 83 | `HORARIOS_A07UX_TEARDOWN_TEST.sql` | (raiz) | A07UX | SQL_TEARDOWN | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Teardown del A07UX. | `aac2abf21536` |
| 84 | `HORARIOS_A07UX_smoke_e2e_TEST.ps1` | (raiz) | A07UX | PS1_SMOKE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Smoke E2E del A07UX (PowerShell). | `08e4d9eb552d` |
| 85 | `HORARIOS_B2_CIERRE.md` | (raiz) | HORARIOS-B2 | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | `crear_bloqueo, fecha_hoy_ar` | — | CITAR | Cierre de HORARIOS_B2 (guard helper). Distinto de HORARIOS_FASEB_B2. | `1625275470db` |
| 86 | `HORARIOS_B2_GUARD_HELPER_TEST.sql` | (raiz) | HORARIOS-B2 | SQL_MIGRACION | VIGENTE | **CANDIDATO_REPO_HASTA_D2** | CUERPO_FN | CREATE de crear_bloqueo(jsonb) y fecha_hoy_ar() | EJECUTABLE | `crear_bloqueo, fecha_hoy_ar, crear_prereserva` | — | **PENDIENTE_D2** | CANDIDATO a autoridad del CUERPO de crear_bloqueo y fecha_hoy_ar. NINGUNA de las dos esta en el pin de 11. NO entra al canonico hasta que D2 lo mida contra TEST. | `31e7558fbfc9` |
| 87 | `HORARIOS_B2_RUNSHEET (1).md` | (raiz) | HORARIOS-B2 | MD_RUNSHEET | **COLISION_DIVERGENTE** | NO | NINGUNO | — | NO_APLICA | — | — | ARCHIVAR | md5 1a152ac9..., 13129 B. Divergente del (2). Sufijo de descarga. NO se elige por tamano. | `8497b436780a` |
| 88 | `HORARIOS_B2_RUNSHEET (2).md` | (raiz) | HORARIOS-B2 | MD_RUNSHEET | **COLISION_DIVERGENTE** | NO | NINGUNO | — | NO_APLICA | — | — | ARCHIVAR | md5 e0f1b023..., 15725 B. Divergente del (1). Sufijo de descarga. NO se elige por tamano. | `c87e4a587c48` |
| 89 | `HORARIOS_B3_CIERRE.md` | (raiz) | HORARIOS-B3 | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre de HORARIOS_B3 (wrappers UX A07/A08). | `f3b2af9783c4` |
| 90 | `HORARIOS_B3_RUNSHEET.md` | (raiz) | HORARIOS-B3 | MD_RUNSHEET | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de HORARIOS_B3. | `c4cd2b613107` |
| 91 | `HORARIOS_B3_smoke_e2e_TEST.ps1` | (raiz) | HORARIOS-B3 | PS1_SMOKE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Smoke E2E de HORARIOS_B3 (PowerShell). | `145004e552d1` |
| 92 | `HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql` | (raiz) | DISP-RANGO | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN | CREATE de obtener_disponibilidad_rango | EJECUTABLE | `obtener_disponibilidad_rango` | — | **CONSOLIDAR** | AUTORIDAD de obtener_disponibilidad_rango (fp 37009a32, ODR INTACTO/pin). Q6: llamada por precios_disponibilidad_noches y vista_disponibilidad. | `84442d908ae7` |
| 93 | `HORARIOS_DISPONIBILIDAD_RANGO_B_VERIFICACION_TEST.sql` | (raiz) | DISP-RANGO | SQL_VERIF | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `obtener_disponibilidad_rango` | — | CITAR | Verificacion del ODR. | `5f29c47a301c` |
| 94 | `HORARIOS_DISPONIBILIDAD_RANGO_CIERRE_TECNICO_PRELIMINAR.md` | (raiz) | DISP-RANGO | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre preliminar de la integracion resolver_horario -> ODR. | `4e9e6db393b8` |
| 95 | `HORARIOS_DISPONIBILIDAD_RANGO_C_SMOKES_TEST.sql` | (raiz) | DISP-RANGO | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `obtener_disponibilidad_rango` | — | CITAR | Smokes del ODR. | `42a8ccae1049` |
| 96 | `HORARIOS_DISPONIBILIDAD_RANGO_D_RUNSHEET.md` | (raiz) | DISP-RANGO | MD_RUNSHEET | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet del ODR. | `83373d493575` |
| 97 | `HORARIOS_DISPONIBILIDAD_RANGO_PASO0_LIVE_TEST.sql` | (raiz) | DISP-RANGO | SQL_DIAG | HISTORICO | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR | Paso 0 live del ODR. Diagnostico previo. | `43c75efa3dfe` |
| 98 | `HORARIOS_DISPONIBILIDAD_RANGO_RELEVAMIENTO.md` | (raiz) | DISP-RANGO | MD_DISENO | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Relevamiento y diseno de la integracion ODR. | `5a01a9ad1e34` |
| 99 | `HORARIOS_FASEB_B2_CIERRE.md` | (raiz) | FASEB-B2 | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | `resolver_horario` | — | CITAR | Cierre de FASEB_B2 (resolver_horario standalone). | `d9079c35847b` |
| 100 | `HORARIOS_FASEB_B2_RESOLVER_HORARIO_TEST.sql` | (raiz) | FASEB-B2 | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | ARCHIVAR | Primera version de resolver_horario. Superada por B1.2-CORE (wrapper + interno). | `7850c4d035cf` |
| 101 | `HORARIOS_FASEB_B2_RUNSHEET.md` | (raiz) | FASEB-B2 | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de FASEB_B2. | `c787bd8bbe92` |
| 102 | `HORARIOS_FASEB_B3_CIERRE.md` | (raiz) | FASEB-B3 | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | `crear_prereserva` | — | CITAR | Cierre de FASEB_B3 (resolver_horario -> crear_prereserva). | `83e37795f3e6` |
| 103 | `HORARIOS_FASEB_B3_INTEGRACION_CREAR_PRERESERVA_TEST.sql` | (raiz) | FASEB-B3 | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `08-07-2026/B1_3_C_PATCH_CREAR_PRERESERVA_TEST.sql` | ARCHIVAR | Integracion original de resolver_horario en crear_prereserva. Superada por el patch C. | `040ad93a48dd` |
| 104 | `HORARIOS_FASEB_B3_RUNSHEET.md` | (raiz) | FASEB-B3 | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de FASEB_B3 (v3). | `b94aa43cda6d` |
| 105 | `HORARIOS_FASEB_B3_SMOKES_TEST.sql` | (raiz) | FASEB-B3 | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | EJECUTABLE | `crear_prereserva` | — | ARCHIVAR | Smokes de FASEB_B3. 5 helpers temporales. | `7ffd5ca04663` |
| 106 | `HORARIOS_FASEB_B3_VERIFICACION_TEST.sql` | (raiz) | FASEB-B3 | SQL_VERIF | HISTORICO | NO | NINGUNO | — | EJECUTABLE | `crear_prereserva` | — | ARCHIVAR | Verificacion de FASEB_B3. | `66c99936dc42` |
| 107 | `HORARIOS_REQUISITO_GUARD_ALTA_OVERRIDES_PENDIENTE.md` | (raiz) | requisito-diferido | MD_REQUISITO | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Requisito diferido: guard de alta de overrides vs reservas. Origen de S0-S3. | `bfc4e0008eac` |

---

## Hallazgos

### 1. H4 — cerrado
Fila 49 **SUPERADA**; fila 52 **AUTORIDAD**, probado contra el vivo (`firma_variante_09_07 = true`).

La consecuencia está en los **rollbacks**: el de 08-07 (fila 50) ancla por texto literal, y ese anchor **no existe en el vivo**. **El único aplicable es el de 09-07** (fila 53).

### 2. Colisión divergente — `HORARIOS_B2_RUNSHEET (1)/(2)`
Filas 87 y 88. **No son duplicados: divergen.**

```
1a152ac9b7c733f21020af827999e228  HORARIOS_B2_RUNSHEET (1).md   13129 bytes
e0f1b023d42394390cb9f6a9d04a4456  HORARIOS_B2_RUNSHEET (2).md   15725 bytes
```

Ambos → `ARCHIVAR`. **No se elige uno por tamaño.** Tras el canónico se genera un `HORARIOS_B2_RUNSHEET.md` nuevo desde el estado congelado.

### 3. `B1_3_A` es la autoridad del DDL
Dropea y recrea `vigencias_horario_base` / `_detalle` (líneas 107-132). La fila 26 (`B1_1_VIGENCIAS_DDL`) queda **SUPERADA también en el DDL**.

### 4. Contaminación — 3 archivos
Filas 71, 72 (Cuenta Corriente) y 76 (Frontend/CC). **Documentar y NO mover.**

### 5. Sobre causalidad
La matriz afirma **qué está y qué no está** en el vivo. **No afirma qué comando histórico lo produjo.** Que `B1_3_A` contenga el `DROP` del overload de 7 args y que hoy ese overload no exista son dos hechos **consistentes**; el segundo no prueba criptográficamente al primero.
