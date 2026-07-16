# KICKOFF — B1.3 CONTINUACIÓN POST-D2

> **Documento autocontenido.** Abre la conversación de H1 sin depender de ningún chat anterior. Todo lo necesario está acá.

---

## 0. Apertura — HEAD y gate

```
repo:   github.com/francogg89-ai/vita-delta-reservas  (público)
rama:   main

HEAD base mínimo auditado para H1:
  82f28dfdab4acbb5ae6a4391a80e657d871765d5
  (commit: docs(horarios): cerrar evidencia D2 de B1.3, 2026-07-15)
```

**Gate de apertura de la conversación nueva:**

```bash
git merge-base --is-ancestor 82f28dfdab4acbb5ae6a4391a80e657d871765d5 HEAD
```

El gate exige que `82f28df` (el cierre de evidencia de D2) sea **ancestro** del HEAD sobre el que se trabaje. Es decir: se puede operar sobre ese commit exacto **o sobre cualquier descendiente que lo incluya**. Si el gate devuelve exit 0, el estado es válido.

> **Nota sobre el HEAD vivo.** Al generar este kickoff, el `main` ya tenía un commit posterior a `82f28df` — `d6fc392 test(portal): agregar harness QA del histórico contable`, que pertenece al **Carril C / contable**, no al Motor de Horarios, y **no afecta el cierre de D2**. El gate `--is-ancestor` pasó igual. Por eso el criterio correcto es el gate, no la igualdad literal `HEAD == 82f28df`.

**Antes de trabajar en H1:** clone **completo** (no `--depth 1`, porque un clone superficial del HEAD descendiente puede no contener el commit `82f28df` y el gate fallaría aunque la relación de ancestro sea verdadera), correr el gate, y confirmar que estos 6 archivos del cierre de D2 están presentes:

```bash
git clone https://github.com/francogg89-ai/vita-delta-reservas.git
cd vita-delta-reservas
git merge-base --is-ancestor 82f28dfdab4acbb5ae6a4391a80e657d871765d5 HEAD
```


```
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/13-07-2026/D2_Q5_CUERPOS_TEST.json
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/13-07-2026/D2_RESULTADOS_TEST_Y_CIERRE_B1_3.md
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/13-07-2026/D2_RUNBOOK.md
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/13-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/14-07-2026/D1_RESULTADOS_TEST_Y_FREEZE_B1_3.md
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/14-07-2026/D1_DECISION_FIDELIDAD_FUNCTIONDEF.md
```

El `D2_Q5_CUERPOS_TEST.json` debe tener `sha256 = 8b9a9c92f26668e5cf3e378b9095a19a91ad83930be815858e6ef366f742b490`.

---

## 1. Resumen ejecutivo de B1.3

El bloque `B1.3-consolidacion-canonica` del **Carril Motor de Horarios** llegó al punto donde **todo el inventario DB del carril está cerrado y congelado**. Falta un solo bloqueante para consolidar el canónico v1.13.0: **H1** — la política durable del artefacto A07 y su cadena de custodia.

- **D1** congeló los 11 objetos del pin + 2 triggers de vigencias. TEST, verde.
- **D2** midió los 7 objetos fuera del pin + el trigger `trg_ov_guard`. TEST, verde. Comparación cuerpo-vivo-vs-repo: **7/7 byte-idéntica** (`comparacion_directa_lf = true`, `sha256_lf_vivo = sha256_lf_repo`).
- **H1 sigue abierto.** Único bloqueante para v1.13.0.

**División de trabajo (invariante):** Claude inspecciona, diseña, valida y genera artefactos. **Franco ejecuta todas las escrituras** (Supabase, n8n, Vercel, git). Claude nunca toca servicios vivos, OPS, el canónico, los satélites, ni git remoto. Hard stop antes de cada escritura.

---

## 2. Bloques A–F de B1.3 — cerrados

| Bloque | Objeto(s) | Autoridad (artefacto) |
|---|---|---|
| **A** | `_resolver_horario`, `vigencias_conflictos_comprometidos`, `crear_vigencia_horario`, `trg_guard_vigencias`, 2 triggers, **DDL de vigencias** | `08-07/B1_3_A_MIGRACION_SEMANAL_TEST.sql` |
| **B** | `validar_gap_bordes_congelados` | `08-07/B1_3_B_VALIDADOR_GAP_TEST.sql` |
| **C** | `crear_prereserva` (patch) | `08-07/B1_3_C_PATCH_CREAR_PRERESERVA_TEST.sql` |
| **D** | `confirmar_reserva` (patch) | `09-07/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` — **variante 09-07** |
| **E** | `crear_reserva_con_horario_pactado` | `09-07/B1_3_E_CREAR_RESERVA_PACTADA_TEST.sql` |
| **F** | `crear_override_horario_puntual` (dropea S3) | `09-07/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` |

**H4 resuelto:** la variante viva de `confirmar_reserva` es la del **09-07** (`firma_variante_09_07 = true`, `fp_raw = e6ac8ddc…`). El rollback del 08-07 ancla por texto literal que **no existe en el vivo**; el único aplicable es el de 09-07.
**S3** está ausente de la DB viva y no tiene callers vivos en DB ni workflows. El repo conserva artefactos históricos/superados de S3 —migración, rollback, runsheet, smokes y el rollback de F que lo recrea—, todos clasificados en H3; ninguno constituye autoridad activa.

---

## 3. D1 y D2 — fingerprints congelados (doble hash, opción C)

### 3.1 Los 11 del pin (D1)

| Objeto | `fp_raw` | `fp_lf` |
|---|---|---|
| `resolver_horario(bigint,date)` | `1bd96c89e587b15582fd7b2e29ae7e18` | `4acc0e1ca329837f589d87ab45805c30` |
| `_resolver_horario(bigint,date,boolean)` | `7e5bfa21b39d90b674c1a83d76b71b1d` | `b3d56eebd3fdca7305b3010d8630e9f4` |
| `vigencias_conflictos_comprometidos(date,date,boolean,jsonb)` | `c684340c893d8668dc2d74c7564106a8` | `d99fe0016195d1ff4134ab5ce8ef5519` |
| `crear_vigencia_horario(jsonb)` | `1a7d0d2d3507019563cedd376997780d` | `8137c2115bcd2e3ec1c6af618bf051f2` |
| `trg_guard_vigencias()` | `b4e48e49123a4c189609d0adc21730f5` | `275cf44652f567c687eb073565f2ff70` |
| `validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)` | `5c5ef50eff10db716d17305dcbd54669` | `6c53d905269fcd1bd6087deb43b4bacf` |
| `crear_prereserva(jsonb)` | `62fefb63ef64e443ea2697645cd4e0a8` | `a16f10e6ae9db3c7552b2d813bb6740e` |
| `confirmar_reserva(jsonb)` | `e6ac8ddce8a12a9c48ecc1aa128b311c` | `98871669c650abcc73f1c2b4ee44936f` |
| `crear_reserva_con_horario_pactado(jsonb)` | `93c1700f5940b0e53095e08635e159d0` | `7016058f8e7d98c943c4e007671636cf` |
| `crear_override_horario_puntual(jsonb)` | `33d7ac8ad5f80b72a0266fb4eb4f7f4d` | `d0402e3abb4bcb1943777cf0649b607c` |
| `obtener_disponibilidad_rango(date,date,bigint)` | `37009a32154f93b80520500c0f15b46b` | `1560f8991dc854e0b0155146d1de2718` |

**Triggers de vigencias:** `trg_vig_guard = e8cf4990e3fc36d92ee97198e16085bd` · `trg_vig_guard_detalle = 99a7a7b61631db62b63cf4bebf9d0e54`

### 3.2 Los 7 fuera del pin (D2)

| Objeto | `fp_raw` | `fp_lf` |
|---|---|---|
| `public.crear_bloqueo(jsonb)` | `0391133ff2eea689bb18e65088536555` | `c097dcc70e5c3b19b3ce26b74e3e17f3` |
| `public.crear_override_horario(jsonb)` | `239c2e4c41f7905382bc1d49758abc6f` | `3036c6789e4c4e2a0d3b628249162604` |
| `public.fecha_hoy_ar()` | `fbfa96e0fa3f0ab855f1782c6c28000f` | `dce59fab0ab52076d81e7f87a03828b2` |
| `public.trg_guard_overrides()` | `c7d217ea134dddba215e88c2e26d844a` | `279ca092b303e99d5cc9cdb47d12ac0e` |
| `public.validar_estado_horario_final(bigint,date)` | `348d26e9abb7caebfaeb05305fc77e23` | `493c14c62dff590505151fa73ba1951c` |
| `public.validar_estado_override(bigint,date)` | `d27ea6e16f22c2ae17a0c3fe40b2a5c0` | `ec17b66abe6c08f6eb8f5f409141468f` |
| `public.validar_no_eventos_comprometidos(bigint,date)` | `4b0dbe1be47ea92509a2857816fd13e6` | `a3f60d6065a20ec3d5dcfae85b644c5b` |

**Trigger `trg_ov_guard`:** `fp_triggerdef = f6a5394751129110617e9c7ce22e5cab`. Los 7 con CR (`cr_totales = 540`).

**Q7 final de D2:** `firmas_esperadas_presentes=7`, `ausentes=0`, `distintas=0`, `overloads_extra=0`, `execute_a_public=0`, `priv_efectivos_data_api=0`, `trg_ov_guard_ok=true`, `observaciones=<ninguna>`.

---

## 4. Comparación directa vivo–repo — 7/7 byte a byte

Cada `functiondef_completo` de `D2_Q5_CUERPOS_TEST.json` (export original, sha `8b9a9c92…`) se normalizó a LF y se comparó **byte a byte** contra el `functiondef` reconstruido del fragmento del repo. El SHA-256 se calculó independientemente en cada lado.

| Objeto | `comparacion_directa_lf` | `sha256_lf_vivo` = `sha256_lf_repo` |
|---|---|---|
| `fecha_hoy_ar` | **true** | `1a07c72819d590e4b869db91…` |
| `validar_estado_horario_final` | **true** | `391ef9dc913e75b72f50c3c6…` |
| `validar_no_eventos_comprometidos` | **true** | `9d9a84ba7f66218e73e38518…` |
| `validar_estado_override` | **true** | `fe0498944bfba84027b13c93…` |
| `trg_guard_overrides` | **true** | `a61d55ffa42acfa6df1018eb…` |
| `crear_override_horario` | **true** | `2d1804ce4a9658becb123baf…` |
| `crear_bloqueo` | **true** | `72d9ea6ee73ce2d3abe51333…` |

**7/7 `comparacion_directa_lf = true`**, longitudes idénticas, `fp_raw` difiere por EOL (repo LF, vivo CRLF). El insumo vivo se validó contra `md5_raw` + `md5_lf` + `bytes` + `cantidad_cr` del propio Q5: 7/7.

---

## 5. Estado de H3

**107 archivos** en `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/` (denominador de la matriz). Recuento:

- **estado:** VIGENTE 59 · HISTORICO 26 · SUPERADO 16 · COLISION_DIVERGENTE 2 · CONTAMINACION 3 · DUPLICADO 1
- **autoridad_actual:** SI 12 · PARCIAL 1 · PENDIENTE_H1 1 · NO 93
- **accion_v1_13:** CONSOLIDAR 12 · CITAR 58 · ARCHIVAR 31 · RECLASIFICAR 3 · PRESERVAR_APP 1 · ARCHIVAR_EVIDENCIA 1 · BLOQUEADO_H1 1

Post-D2, las filas 4/8/9/86 pasaron a `SI` / `CONSOLIDAR` (comparación directa 7/7). **Ya no hay `PENDIENTE_D2`.** Sólo la fila 70 (A07) sigue `PENDIENTE_H1`.

- **Colisión divergente:** `HORARIOS_B2_RUNSHEET (1).md` (`1a152ac9…`, 13129 B) y `(2).md` (`e0f1b023…`, 15725 B) **difieren**. Ambos → `ARCHIVAR`; tras el canónico se genera un runsheet nuevo desde el estado congelado. **No elegir por tamaño.**
- **Contaminación (documentar, NO mover):** `11-07/CC_L3_BLOQUE0_CIERRE.md`, `11-07/CC_L3_BLOQUE0_EVIDENCIAS_EJECUCION_TEST.md`, `CIERRE_UI_RETIRO_SALDO_FRONTEND.md` — pertenecen a Cuenta Corriente / Frontend.

---

## 6. Autoridad de los 12 artefactos `CONSOLIDAR`

Los que entran al canónico SQL, autoridad probada contra el vivo:

| Objeto vivo | Artefacto | estado_script |
|---|---|---|
| wrapper `resolver_horario` | `06-07/B1_2_CORE_MIGRACION_TEST.sql` | **NO_EJECUTABLE** (gatea 58d75c1b) · **autoridad PARCIAL** |
| 4 fns semanales + 2 triggers + DDL vigencias | `08-07/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | EJECUTABLE |
| `validar_gap_bordes_congelados` | `08-07/B1_3_B_VALIDADOR_GAP_TEST.sql` | EJECUTABLE |
| `crear_prereserva` | `08-07/B1_3_C_PATCH_CREAR_PRERESERVA_TEST.sql` | EJECUTABLE |
| `confirmar_reserva` | `09-07/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` | EJECUTABLE |
| `crear_reserva_con_horario_pactado` | `09-07/B1_3_E_CREAR_RESERVA_PACTADA_TEST.sql` | EJECUTABLE |
| `crear_override_horario_puntual` | `09-07/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | EJECUTABLE |
| `obtener_disponibilidad_rango` | `HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql` | EJECUTABLE |
| 3 validadores S0 | `04-07/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql` | **NO_EJECUTABLE** · D2: 3/3 byte-idéntico |
| `trg_guard_overrides` + `trg_ov_guard` | `04-07/HORARIOS_GUARD_S1_TRIGGER_TEST.sql` | **NO_EJECUTABLE** · D2: byte-idéntico |
| `crear_override_horario` (S2) | `04-07/HORARIOS_GUARD_S2_FUNCION_TEST.sql` | **NO_EJECUTABLE** · D2: byte-idéntico |
| `crear_bloqueo`, `fecha_hoy_ar` | `HORARIOS_B2_GUARD_HELPER_TEST.sql` | EJECUTABLE · D2: 2/2 byte-idéntico |

**El parcial es `B1_2_CORE_MIGRACION_TEST.sql` (fila 30):** autoridad del wrapper `resolver_horario`, pero su `_resolver_horario` y helper fueron superados por A. Ya contado dentro de los 12 — **no es un archivo 13**.

---

## 7. Autoridad ≠ ejecutabilidad

4 de esos 12 artefactos son `NO_EJECUTABLE_GATE_OBSOLETO`: su gate hardcodea el fingerprint **viejo** del resolver (`IS DISTINCT FROM 58d75c1b6b812ee2d2c9751ddcb0cd4d`) y **abortan hoy** (el vivo es `1bd96c89…`). Pero su `CREATE` sigue siendo la **fuente autoritativa del cuerpo vivo**.

**El canónico se arma del cuerpo de la función (probado byte-idéntico al vivo), no de re-ejecutar el script.** 15 scripts del carril tienen ese gate obsoleto; que aborten no invalida su autoridad de contenido.

---

## 8. Doble fingerprint (opción C) — CERRADA

```
fp_raw = md5(pg_get_functiondef(...))                        -- verifica el VIVO (con CRLF)
fp_lf  = md5(replace(pg_get_functiondef(...), chr(13), ''))  -- verifica el CANONICO LF-only
```

- Canónico y bootstrap **LF-only**. TEST **intacto**. Sin re-pin, sin escritura.
- Validada en harness **PostgreSQL 17.10**: recrear desde LF-only reproduce el `fp_lf`.
- **Detección de normalización accidental** (no impedida): `cr_baseline>0 ∧ fp_raw_actual≠fp_raw_baseline ∧ fp_lf_actual==fp_lf_baseline ∧ cr_actual=0` ⇒ diff exclusivamente físico. Si `fp_lf` también cambió, hubo cambio textual.
- **Válidos para PG 17.x** — `md5(pg_get_functiondef())` no es portable entre major versions (el header lo reconstruye el servidor). El bootstrap v1.13.0 debe declararlo.
- **Hash siempre dentro de la base** (`SELECT md5(replace(pg_get_functiondef(oid), chr(13), ''))`); exportar con `psql -tA -o` agrega un `\n` final que cambia todos los hashes.

---

## 9. Estado del canónico, bootstrap y satélites

- **Canónico:** `Docs/Implementacion/6B_SCHEMA_SQL.md` en **v1.12.0**. Tiene 6 menciones stale que dicen que el bootstrap sigue pineado a v1.9.0 (líneas ~36/49/59/106/5436/8258) — a corregir en la consolidación v1.13.0.
- **Bootstrap:** existe `Docs/Implementacion/bootstrap_entorno_nuevo_v1.12.0/`. En v1.13.0 se regenera LF-only, con doble fingerprint y declaración de versión PG.
- **Satélites** (en `Docs/Operacional/`, NO en la raíz): `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `Pendiente_pre_produccion.md`. Más `CLAUDE.md` y `README.md` en la raíz. Se tocan **sólo** al cierre formal, con `str_replace` quirúrgico y EOL preservado por archivo (ESTADO_ACTUAL = CRLF; Lecciones = mixto; el resto = LF).

**Series libres para acuñar** (máximos actuales): D-CC-39, D-FE-30, D-HARD-11, D-NEG-02, D-PROMO-13, D-RDEV-06 / L-CC-19, L-FE-09, L-PROMO-08, L-RDEV-04. Para este carril: abrir **`D-HR-*` / `L-HR-*`** (series nuevas).

---

## 10. H1 — el único bloqueante integral restante

El clone confirma que **no aparece ningún otro bloqueante**: los 11+7 objetos y los 3 triggers están congelados, la fidelidad cerrada (comparación directa 7/7), y H3 sólo tiene una fila abierta (la 70). El bloqueante es H1.

H1 es la **política durable del artefacto A07** (`portal-a07-crear-reserva`, workflow n8n del portal operativo) y su **cadena de custodia/sanitización**. El template está en el repo como candidato, pero no puede declararse autoridad ni consolidarse hasta definir la política.

---

## 11. Los tres hashes asociados al A07

No son intercambiables — **no son el mismo archivo**:

```
1) archivo del repo (10-07/portal-a07-crear-reserva__TEMPLATE.PATCHED.json):
     3188bceb777b38dcc12d5aa8475cdb40fe89cb189257644c3b4a738c87cd6def   (41775 B)
     -> PRESENTE en el repo.

2) hash histórico reportado en rondas previas:
     2c99db28866a4e9e7e0ec586e5a18fd443a4b91b64b704fcaa833cbe31a981c3
     -> NO LOCALIZADO en el clone. Hash reportado, no archivo disponible.

3) export __TEST__ (portal-a07-crear-reserva__TEST__.json):
     32337c2eabd9c07767c3863d381f5e7e76b3150af99ea47f36890bb5e7081b92   (42255 B)
     -> disponible FUERA del repo (se entrega en la conversación privada de H1).
```

**El archivo del repo tiene sha `3188bceb…`, no `2c99db28…`.** Estructura del A07 del repo: **24 nodos** (9 `code` con jsCode, 6 `if`, 6 `postgres`, 1 webhook, 1 executeWorkflow, 1 respondToWebhook), **22 conexiones**, **17 ocurrencias de `$('Nodo')` sobre 5 nodos distintos**.

---

## 12. Primer objetivo de H1 — procedencia

**No se trata de elegir arbitrariamente uno de los tres.** En orden:

1. **localizar o descartar el artefacto histórico `2c99db28…`** (el hash sin archivo);
2. **clasificar la procedencia** del archivo del repo (`3188bceb…`) y del export `__TEST__` (`32337c2e…`);
3. **distinguir cuál es crudo y cuál sanitizado**;
4. si la procedencia no alcanza, **Franco hace un export fresco de A07 desde n8n TEST**;
5. **recién entonces se designa el crudo autoritativo.**

---

## 13. Cadena de custodia requerida

Una vez designado el crudo:

1. **hash del crudo** (el designado en el paso 5 de §12);
2. **hash del sanitizado**;
3. **manifiesto de cada JSON path alterado** en la sanitización;
4. **placeholders determinísticos** (secretos / URLs / ids → tokens estables).

> **El crudo del A07 nunca se indica para commit en el repo público.** Se maneja **sólo** en la conversación privada de H1. Al repo va el **sanitizado**, con su manifiesto.

---

## 14. Invariantes de nodos, conexiones y `jsCode`

La sanitización **no puede** alterar la lógica del workflow. Se prueba con un diff estructural que confirme que **no cambiaron**:

- **nodos:** los 24 (mismo `type`, mismo `name`, misma cantidad);
- **conexiones:** las 22 (mismo grafo);
- **`jsCode`:** el contenido de los 9 nodos `code` **byte a byte** (los placeholders sólo tocan credenciales/URLs/ids, nunca el código).

Cualquier cambio fuera del manifiesto de paths es un fallo de sanitización.

---

## 15. Política durable del A07

Definir y dejar escrito:

- **dónde vive** el A07 canónico (sanitizado) en el repo;
- **cómo se versiona** (qué se commitea, con qué nomenclatura);
- **cómo se re-sanitiza** al actualizarlo (el mismo manifiesto + invariantes);
- **cómo se valida** que el sanitizado del repo corresponde a un crudo funcional en n8n TEST.

---

## 16. Secuencia: de H1 a v1.13.0

```
FASE 1 — H1: procedencia y crudo autoritativo del A07
  paso 0 (procedencia): localizar/descartar 2c99db28; clasificar repo y __TEST__;
    distinguir crudo/sanitizado; si no alcanza, export fresco desde n8n TEST;
    designar el crudo autoritativo
  cadena de custodia: hash crudo + hash sanitizado + manifiesto de paths + placeholders
  invariantes: nodos (24) + conexiones (22) + jsCode (9) por diff estructural
  politica durable escrita
  gate: el crudo SOLO en la conversacion privada; al repo va el sanitizado
  aceptacion: sanitizado reproducible desde el crudo por un tercero

FASE 2 — cerrar H3 y el inventario de artefactos A07
  -> fila 70 pasa de PENDIENTE_H1 a su estado definitivo
  aceptacion: H3 sin filas abiertas

FASE 3 — consolidar canonico v1.13.0  (BLOQUE APARTE, con su propio kickoff)
  -> 6B_SCHEMA_SQL.md: consolidar los fragmentos autoritativos de los 12 artefactos CONSOLIDAR
     (18 funciones, 3 triggers, DDL de vigencias y ACL/hardening asociado)
  -> corregir las 6 menciones stale del bootstrap
  -> doble fingerprint (fp_raw + fp_lf) + declaracion PG 17.x
  -> regenerar bootstrap_entorno_nuevo_v1.13.0/ LF-only
  -> nuevo HORARIOS_B2_RUNSHEET.md desde el estado congelado
  -> acunar D-HR-* / L-HR-*
  gate: Franco ejecuta la escritura del canonico y el commit

FASE 4 — promocion a OPS  (BLOQUE APARTE)
  -> misma metodologia: diagnostico -> aprobacion -> artefactos -> Franco ejecuta
```

---

## 17. Gates y criterios de aceptación

- **Gate de apertura:** `git merge-base --is-ancestor 82f28df HEAD` (exit 0).
- **Cada fase cierra con aprobación explícita de Franco** antes de la siguiente. Ninguna fase escribe en servicios vivos sin su ejecución.
- **FASE 1:** el sanitizado debe ser reproducible desde el crudo por un tercero, con invariantes de nodos/conexiones/jsCode probadas.
- **FASE 2:** H3 sin filas abiertas.
- **FASE 3:** canónico v1.13.0 con los fragmentos autoritativos de los 12 artefactos CONSOLIDAR (18 funciones, 3 triggers, DDL de vigencias y ACL/hardening asociado), doble fingerprint, bootstrap regenerado LF-only; Franco ejecuta la escritura.

---

## 18. Riesgos y falsos verdes conocidos

- **Setup de harness que traga stderr** → evidencia que miente en verde. Todo setup con `-v ON_ERROR_STOP=1` y stderr visible; sonda `to_regprocedure` antes de cada corrida.
- **Presencia por `proname` en vez de por firma** → un objeto con la firma cambiada pasa como presente. Comparar por OID / `to_regprocedure`.
- **`has_function_privilege(NOMBRE,…)` aborta** si el rol no existe, y un guard `WHERE EXISTS AND …` no protege (Postgres no ordena los predicados del WHERE). Usar OID.
- **Predicado de trigger incompleto** → un trigger con TRUNCATE o INSTEAD OF pasa como OK. Exigir los 7 bits de `tgtype`.
- **`md5(pg_get_functiondef())` no es portable entre major versions de PG.** Declarar la versión.
- **`psql -tA -o` agrega un `\n` final** que cambia todos los hashes. Calcular el hash dentro de la base.
- **CRLF vs LF** cambia `fp_raw` sin cambiar el código. Por eso el doble fingerprint.
- **Autoridad ≠ ejecutabilidad.** Un script puede ser autoridad del cuerpo y estar muerto por gate obsoleto.
- **Para el A07:** un diff que ignore el orden de las claves JSON puede ocultar un cambio real; el diff estructural debe ser sobre el grafo de nodos/conexiones y el `jsCode` literal, no sobre el texto serializado.

---

## 19. Hard stops (permanentes)

Claude **no**: ejecuta TEST · toca OPS · genera/modifica el canónico o el bootstrap · toca satélites · importa n8n · modifica el A07 · expone E/F · hace commits · hace push. **Franco ejecuta escrituras y git.**

---

## 20. Archivos a subir a la conversación nueva

A la **conversación privada de H1** (no al repo):

```
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/10-07-2026/portal-a07-crear-reserva__TEMPLATE.PATCHED.json
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/10-07-2026/patch_a07_gap_conflicto.py
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/10-07-2026/REPORTE_VALIDACION_A07_gap_conflicto.md
el export __TEST__ (portal-a07-crear-reserva__TEST__.json), o el export fresco de n8n TEST
```

**El crudo del A07 se sube sólo a esa conversación privada; nunca se commitea al repo público.** Al repo va el sanitizado con su manifiesto. Los documentos del cierre de D2 quedan como referencia; no hace falta subirlos si el kickoff se lee completo.

---

## 21. Mensaje inicial para la conversación nueva

> Copiá y pegá esto para abrir el bloque de H1:

```
Claude: arrancamos el bloque H1 del Carril Motor de Horarios (política durable del
artefacto A07). Contexto completo en KICKOFF_B1_3_CONTINUACION_POST_D2.md.

Estado: D1 y D2 cerraron el inventario DB del carril (11+7 objetos y 3 triggers
congelados con doble fingerprint fp_raw/fp_lf, opción C, válidos para PG 17.x; la
comparación directa vivo-repo dio 7/7 byte-idéntica). H1 es el único bloqueante
para consolidar el canónico v1.13.0.

Gate de apertura (corré esto en un clone fresco antes de trabajar):
  git merge-base --is-ancestor 82f28dfdab4acbb5ae6a4391a80e657d871765d5 HEAD
Debe dar exit 0: podés operar sobre ese commit o sobre un descendiente que lo incluya.

Primer paso, sin generar nada todavía — PROCEDENCIA. Hay hashes divergentes del A07:
el archivo del repo (3188bceb), un hash histórico sin artefacto localizado (2c99db28),
y el export __TEST__ (32337c2e). NO se trata de elegir uno arbitrariamente. La
secuencia es: (1) localizar o descartar 2c99db28; (2) clasificar la procedencia del
repo y del __TEST__; (3) distinguir crudo y sanitizado; (4) si no alcanza, me pedís
que yo haga un export fresco de A07 desde n8n TEST; (5) recién ahí se designa el crudo
autoritativo.
Después: cadena de custodia (hash crudo, hash sanitizado, manifiesto de paths JSON,
placeholders determinísticos) e invariantes de nodos/conexiones/jsCode por diff
estructural.

El crudo del A07 se maneja SOLO en esta conversación privada; nunca va al repo
público. Al repo va el sanitizado con su manifiesto.

Metodología de siempre: vos inspeccionás y proponés, yo ejecuto todo (Supabase, n8n,
git). Hard stop antes de cada escritura. No toques el canónico ni el A07 hasta que
aprobemos la política.

Subo (a esta conversación privada): el A07 del repo, el patcher, el reporte de
validación, y el export __TEST__.
```

---

**Próximo bloque recomendado:** H1 — política durable del A07. Primer paso: procedencia (decisión de Franco sobre los tres hashes), sin generar nada.
