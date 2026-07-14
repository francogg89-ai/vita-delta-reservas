# H7 — BARRIDO DE S3 EN EL REPO · CRUDO Y CLASIFICADO  *(v2 — recuento corregido)*

**Objeto:** `crear_paquete_dia_especial` (S3)  
**HEAD:** `07fea85802bc4fccbff1236813593762aefe58d9`  
**Propósito:** cerrar el **gate externo** de `apto_para_freeze` — el único criterio no verificable desde la DB.

> **Documento diagnóstico. Fuera del repo.**

## Corrección respecto de v1

v1 declaró **23** invocaciones. Eran **21**. Dos hits estaban mal clasificados:

| hit | archivo:línea | v1 decía | es en realidad |
|---|---|---|---|
| **#68** | `09-07/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:442` | `INVOCA_S3` | `COMMENT_TEXTO` — texto **dentro** del `COMMENT` descriptivo de F |
| **#81** | `09-07/B1_3_F_ROLLBACK_TEST.sql:337` | `INVOCA_S3` | `ACL_CHECK` — `has_function_privilege(...)`, chequeo de permisos |

Causa: el regex `crear_paquete_dia_especial\s*\(` matcheaba tanto `…especial (S3)` dentro de un string como el nombre dentro de `'public.crear_paquete_dia_especial(jsonb)'` pasado como argumento.

**`INVOCA_S3` = 21.** Las 21 siguen íntegramente en el smoke histórico. **El veredicto no cambia.**

---

## 1. Comandos, exit codes y stdout crudo

### 1.1 Barrido total

```
$ git grep -n -I 'crear_paquete_dia_especial' -- .
```

**exit code: `0`** · **91 hits** · **stderr vacío (0 bytes)**

<sub>`git grep`: exit 0 = hubo hits; exit 1 = cero hits; exit >1 = error.</sub>

```
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_ALTA_OVERRIDES_CIERRE_TECNICO_PRELIMINAR.md:18:- **S3** — alta asistida **de paquete**: `crear_paquete_dia_especial(jsonb)` (checkout + checkin juntos, con verificación de efecto pretendido).
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_ALTA_OVERRIDES_CIERRE_TECNICO_PRELIMINAR.md:37:| S3 | `crear_paquete_dia_especial(jsonb)` | Alta asistida de paquete (checkout+checkin), con S0 + verificación de efecto pretendido |
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_ALTA_OVERRIDES_CIERRE_TECNICO_PRELIMINAR.md:48:Para las **funciones nuevas del bloque** (validadores S0, `trg_guard_overrides`, `crear_override_horario`, `crear_paquete_dia_especial`) **no hay fingerprint consolidado todavía**: su integridad se verifica por **presencia/firma** (`to_regprocedure('fn(args)')`) y, para el trigger, por existencia en `pg_trigger` (`trg_ov_guard`, no interno). La consolidación de fingerprints de estas funciones sería un artefacto natural del **cierre formal/canonización**, no de este preliminar.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_ALTA_OVERRIDES_CIERRE_TECNICO_PRELIMINAR.md:83:### `crear_paquete_dia_especial(jsonb)` (S3)
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_ALTA_OVERRIDES_CIERRE_TECNICO_PRELIMINAR.md:103:3. **Cableado operativo** (n8n/gateway/frontend) para exponer `crear_override_horario` y `crear_paquete_dia_especial` a la operación, si corresponde, respetando la división de labor y el ciclo de promoción.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_ALTA_OVERRIDES_CIERRE_TECNICO_PRELIMINAR.md:125:- S3: `HORARIOS_GUARD_S3_ROLLBACK_TEST.sql` (dropea solo `crear_paquete_dia_especial(jsonb)`; verificado que deja R0/S0/S1/S2 intactos).
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S0_RUNSHEET.md:4:`crear_override_horario` ni `crear_paquete_dia_especial` (esos son S1/S2/S3).
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S0_RUNSHEET.md:74:**Freno acá.** No generé trigger, `crear_override_horario` ni `crear_paquete_dia_especial`.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql:12:-- NO incluye trigger, ni crear_override_horario, ni crear_paquete_dia_especial (S1/S2/S3).
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S1_RUNSHEET.md:4:`trg_ov_guard`. No incluye `crear_override_horario`, `crear_paquete_dia_especial`,
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S1_RUNSHEET.md:98:**Freno acá.** No generé `crear_override_horario`, `crear_paquete_dia_especial`, gateway,
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S1_TRIGGER_TEST.sql:11:-- NO incluye crear_override_horario ni crear_paquete_dia_especial (S2/S3).
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S2_RUNSHEET.md:4:`crear_paquete_dia_especial`, función de grupo/`todas_posibles`, gateway, frontend ni n8n.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S2_RUNSHEET.md:118:**Freno acá.** No generé `crear_paquete_dia_especial`, función de grupo/`todas_posibles`,
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S2_RUNSHEET.md:120:seguimos con **S3** (`crear_paquete_dia_especial(jsonb)`: paquetes checkout+checkin y alcances
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_FUNCION_TEST.sql:3:-- Sub-bloque S3: puerta sancionada crear_paquete_dia_especial(jsonb).
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_FUNCION_TEST.sql:64:CREATE OR REPLACE FUNCTION crear_paquete_dia_especial(p_payload jsonb)
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_FUNCION_TEST.sql:340:REVOKE EXECUTE ON FUNCTION public.crear_paquete_dia_especial(jsonb) FROM PUBLIC, anon, authenticated, service_role;
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_FUNCION_TEST.sql:342:COMMENT ON FUNCTION public.crear_paquete_dia_especial(jsonb) IS
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_FUNCION_TEST.sql:348:SELECT to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL AS funcion_ok;
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_ROLLBACK_TEST.sql:3:-- Revierte SOLO S3: elimina crear_paquete_dia_especial(jsonb).
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_ROLLBACK_TEST.sql:19:DROP FUNCTION IF EXISTS public.crear_paquete_dia_especial(jsonb);
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_ROLLBACK_TEST.sql:24:  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL THEN
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_ROLLBACK_TEST.sql:25:    RAISE EXCEPTION 'ROLLBACK S3 FALLA: crear_paquete_dia_especial sigue presente.';
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_ROLLBACK_TEST.sql:41:  RAISE NOTICE 'ROLLBACK S3 OK: crear_paquete_dia_especial eliminada; R0/S0/S1/S2 intactos.';
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_ROLLBACK_TEST.sql:49:  to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL AS s3_ausente,
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_RUNSHEET.md:3:**Función:** `crear_paquete_dia_especial(jsonb)` — puerta sancionada de **paquete de día especial**.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_RUNSHEET.md:118:   - Dropea **solo** `crear_paquete_dia_especial(jsonb)`.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_RUNSHEET.md:158:- Verificado empíricamente: efecto pretendido cerrado (global_estricto no deja global si un específico lo sombrea; todas_posibles excluye la cabaña sombreada y aplica el resto sin global; cabana estricta falla si no gana; control positivo pasa); no quedan mitades ante `ok:false`; `ids_cabanas` mal formado (ausente/null/escalar/vacío) → `payload_invalido` sin error inesperado, y con duplicados/inexistente → `ids_cabanas_invalidos`; `gap_minutos < 120` → `payload_invalido`; rollback dropea solo `crear_paquete_dia_especial` dejando R0/S0/S1/S2 intactos.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:3:-- Smokes de S3 (crear_paquete_dia_especial). ALCANCE: SOLO TEST. Todo en BEGIN..ROLLBACK.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:54:  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL THEN
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:55:    RAISE EXCEPTION 'SMOKE S3 abortado: falta crear_paquete_dia_especial. Corre HORARIOS_GUARD_S3_FUNCION_TEST.sql primero.';
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:127:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(540)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:131:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(570)::text,'hora_checkout','16:00','gap_minutos',90,
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:135:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(600)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:139:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(630)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:143:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(660)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:147:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(690)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:151:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(720)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:155:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(750)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:159:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(780)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:163:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(810)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:167:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(840)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:171:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(870)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:175:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(930)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:179:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(960)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:183:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(990)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:187:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1020)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:191:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1050)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:196:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1080)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:201:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1110)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:206:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1140)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql:211:  crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1170)::text,'hora_checkout','16:00',
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/06-07-2026/INVENTARIO_Y_BARRIDO_B1_2_CASCADE.md:46:| `HORARIOS_GUARD_S3_FUNCION_TEST.sql` | 1 | gate (`crear_paquete_dia_especial`; verifica efecto vía resolver) |
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/07-07-2026/EVALUACION_PIVOTE_VIGENCIAS_SEMANALES.md:25:- **S3 `crear_paquete_dia_especial`**: paquete checkout+checkin conjunto con **5 alcances ya implementados** — `cabana | grupo_estricto | grupo_posibles | global_estricto | todas_posibles` — recibiendo `ids_cabanas` (array = tu concepto de "grupo"), con:
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/07-07-2026/EVALUACION_PIVOTE_VIGENCIAS_SEMANALES.md:80:Se conserva `overrides_operativos` + `crear_override_horario` (S2) + `crear_paquete_dia_especial` (S3). Mapeo directo a tu requisito 2:
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/07-07-2026/KICKOFF_B1_3_VIGENCIAS_SEMANALES.md:39:- **Subsistema de overrides completo:** tabla `overrides_operativos` (per-cabaña/global, rango, tipo, valor); validadores S0 (`validar_estado_horario_final`, `validar_no_eventos_comprometidos`, `validar_estado_override`); guard S2 `crear_override_horario` (borde único, `cabana`/`global_estricto`); guard S3 `crear_paquete_dia_especial` (checkout+checkin conjunto, 5 alcances `cabana`/`grupo_estricto`/`grupo_posibles`/`global_estricto`/`todas_posibles`, con `ids_cabanas`).
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:4:-- REEMPLAZA a crear_paquete_dia_especial(jsonb) (S3): DROP del viejo + CREATE del nuevo,
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:39:--   GATE 5 no-callers: ninguna otra funcion referencia crear_paquete_dia_especial en pg_proc.prosrc.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:40:--   GATE 6 crear_paquete_dia_especial(jsonb) existe (se reemplaza); crear_override_horario_puntual(jsonb) no existe.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:41:-- DROP crear_paquete_dia_especial + CREATE (no OR REPLACE) F + REVOKE owner-only + postcheck ACL.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:101:  -- No-callers: ninguna OTRA funcion referencia crear_paquete_dia_especial en su cuerpo.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:103:             WHERE p.prosrc ILIKE '%crear_paquete_dia_especial%' AND p.proname <> 'crear_paquete_dia_especial') THEN
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:104:    RAISE EXCEPTION 'F-GATE: hay funciones que referencian crear_paquete_dia_especial en pg_proc.prosrc. Abortando.';
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:107:  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL THEN
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:108:    RAISE EXCEPTION 'F-GATE: crear_paquete_dia_especial (S3) ausente; se esperaba para reemplazar. Abortando.';
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:118:DROP FUNCTION public.crear_paquete_dia_especial(jsonb);
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:442:  'Guard horarios (F). Alta unificada de override horario puntual. REEMPLAZA a crear_paquete_dia_especial (S3). Eje bordes: checkin | checkout | ambos. checkout/checkin insertan y validan EFECTO SOLO su borde (prohiben la hora del borde contrario => borde_horas_incompatibles); ambos = semantica S3 (checkout req, checkin derivado checkout+gap o explicito, gap_minutos>=120 validado). Alcances producto {cabana, grupo_estricto, todas_posibles} + capacidad interna {grupo_posibles, global_estricto} (superset de S3). Ramas: cabana/grupo_estricto all-or-nothing per-cabana; global_estricto override(s) global(es) real(es); grupo_posibles/todas_posibles subtransaccion por cabana (aplica validas+efectivas, excluye resto con reporte; sin_cabanas_aplicables si ninguna). Valida estado FINAL con validar_estado_override (S0) y EFECTO restringido al/los borde(s) solicitado(s) via resolver_horario => override_no_aplicado_efectivamente (clase efecto_no_aplicado; reemplaza paquete_no_aplicado_efectivamente). Rango: fecha_hasta>=fecha si no rango_invalido. Toma pg_advisory_xact_lock(10,0); subtransacciones BEGIN..EXCEPTION; created_at/id_override no son parametros; source_event deriva hijos por borde <source>:checkout|checkin:<id_cabana|global>. NO usa crear_override_horario (S2). El trigger diferido trg_ov_guard (S1) revalida en commit. Errores: payload_invalido, bordes_no_soportado, borde_horas_incompatibles, rango_invalido, alcance_no_soportado, cabana_no_encontrada, ids_cabanas_invalidos, sin_cabanas_aplicables, override_no_aplicado_efectivamente, override_pisa_reserva, override_pisa_prereserva, override_incompatible_same_day, override_hora_invalido. Fase B1.3-F.';
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:455:  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL THEN
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:456:    RAISE EXCEPTION 'F-POST: crear_paquete_dia_especial deberia estar ausente tras el reemplazo. Abortando.';
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:5:-- crear_paquete_dia_especial (S3) con su cuerpo original, compatible con el resolver VIVO
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:10:--   crear_override_horario_puntual PRESENTE (hay algo que revertir), crear_paquete_dia_especial AUSENTE.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:37:  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL THEN
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:38:    RAISE EXCEPTION 'F-RB-GATE: crear_paquete_dia_especial ya existe (estado inesperado). Abortando.';
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:45:-- ===== Restauracion del cuerpo original de S3 (crear_paquete_dia_especial) =====
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:46:CREATE FUNCTION public.crear_paquete_dia_especial(p_payload jsonb)
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:322:REVOKE EXECUTE ON FUNCTION public.crear_paquete_dia_especial(jsonb) FROM PUBLIC, anon, authenticated, service_role;
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:324:COMMENT ON FUNCTION public.crear_paquete_dia_especial(jsonb) IS
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:330:  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL THEN
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:331:    RAISE EXCEPTION 'F-RB-POST: crear_paquete_dia_especial no quedo restaurada. Abortando.';
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:337:    IF has_function_privilege(r, 'public.crear_paquete_dia_especial(jsonb)', 'EXECUTE') THEN v_bad := v_bad + 1; END IF;
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/B1_3_F_ROLLBACK_TEST.sql:347:SELECT to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL AS s3_restaurada,
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/CIERRE_B1_3_Y_KICKOFF_INTEGRACION_TEST.md:23:| F | `crear_override_horario_puntual(jsonb)` — override puntual unificado con eje `bordes`; **reemplaza** `crear_paquete_dia_especial` (S3), sin coexistencia | VERDE TEST (smoke 15/15) |
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/CIERRE_B1_3_Y_KICKOFF_INTEGRACION_TEST.md:41:`crear_paquete_dia_especial(jsonb)` (S3): **ya no existe** (reemplazada por F).
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/CIERRE_B1_3_Y_KICKOFF_INTEGRACION_TEST.md:85:4. **Barrido OPS de S3 (bajo)** — el barrido de callers de `crear_paquete_dia_especial` fue sobre repo (limpio); repetir contra OPS antes de promover.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/CIERRE_B1_3_Y_KICKOFF_INTEGRACION_TEST.md:119:- **S3 reemplazado por F**: `crear_paquete_dia_especial` ya no existe; vive `crear_override_horario_puntual(jsonb)`.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md:38:| `crear_paquete_dia_especial(jsonb)` | **`crear_override_horario_puntual(jsonb)`** | F |
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md:68:**Query de re-pin en TEST** (read-only): `SELECT md5(pg_get_functiondef('<obj>'::regprocedure));` por cada uno + confirmar que S3 (`crear_paquete_dia_especial`) ya **no existe** (`to_regprocedure(...) IS NULL`).
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md:140:- `crear_paquete_dia_especial` (lo que F reemplaza) **no tenía** acción ni workflow (era DB-only). Por lo tanto F **no rompe** nada del portal.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md:168:- **Gates previos OPS**: ambiente `ops`; fingerprints OPS baseline pre-B1.3 == esperados; `crear_paquete_dia_especial` sin callers vivos en OPS (barrido en OPS, no solo repo); backup/*point-in-time* disponible.
Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md:201:6. **Barrido OPS de S3 (bajo)**: el barrido de callers de `crear_paquete_dia_especial` fue sobre el repo (limpio); antes de OPS, repetirlo contra OPS real.
```

### 1.2 Barrido de `Workflows/`

```
$ git grep -n -I 'crear_paquete_dia_especial' -- Workflows
```

**exit code: `1`** · **CERO HITS** · **stdout vacío** · **stderr vacío (0 bytes)**

El exit 1 es *"sin coincidencias"*, no *"path inexistente"*. El directorio existe:

```
$ git ls-tree --name-only HEAD
Apps
CLAUDE.md
Docs
Prototipos
README.md
Workflows
index.html
```

Un path inexistente habría dado exit 128 con mensaje en stderr. Salió 1, stderr vacío.

**⇒ Ningún workflow de n8n referencia S3.**

---

## 2. Distribución

91 hits, **17 archivos**, **todos** bajo `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/`.

```
$ git grep -n -I 'crear_paquete_dia_especial' -- . | grep -vc "^Docs/"
0
```

**Cero en `Apps/`** (frontend). **Cero en `Workflows/`** (n8n). **Cero en `Prototipos/`.**

| clase | n | significado |
|---|---|---|
| `DOC_MENCION` | 21 | Mencion en documentacion (.md) |
| **`INVOCA_S3`** | **21** | Invocacion real de S3 |
| `COMENTARIO_SQL` | 13 | Comentario SQL (--) |
| `GATE_PRESENCIA` | 9 | Gate/postcheck de presencia (to_regprocedure) |
| `DOC_NEGATIVE_SCOPE` | 8 | Documentacion: negative-scope / ausencia |
| `MENSAJE_ERROR` | 7 | Texto de RAISE EXCEPTION/NOTICE |
| **`CREA_S3`** | **2** | CREATE FUNCTION de S3 |
| `ACL_REVOKE` | 2 | REVOKE EXECUTE |
| `COMMENT_ON` | 2 | COMMENT ON FUNCTION |
| **`DROPEA_S3`** | **2** | DROP FUNCTION de S3 |
| `BARRIDO_PROSRC` | 2 | Barrido de no-callers sobre pg_proc.prosrc |
| `COMMENT_TEXTO` | 1 | Texto DENTRO del COMMENT descriptivo |
| `ACL_CHECK` | 1 | Chequeo ACL (has_function_privilege) |
| **total** | **91** | |

---

## 3. Clasificación individual — los 91 hits

### `04-07-2026/HORARIOS_GUARD_ALTA_OVERRIDES_CIERRE_TECNICO_PRELIMINAR.md`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 1 | 18 | DOC_MENCION | `- **S3** — alta asistida **de paquete**: ‘crear_paquete_dia_especial(jsonb)‘ (checkout + checkin juntos, …` | no |
| 2 | 37 | DOC_MENCION | `\| S3 \| ‘crear_paquete_dia_especial(jsonb)‘ \| Alta asistida de paquete (checkout+checkin), con S0 + verifi…` | no |
| 3 | 48 | DOC_NEGATIVE_SCOPE | `Para las **funciones nuevas del bloque** (validadores S0, ‘trg_guard_overrides‘, ‘crear_override_horario‘…` | no |
| 4 | 83 | DOC_MENCION | `### ‘crear_paquete_dia_especial(jsonb)‘ (S3)` | no |
| 5 | 103 | DOC_MENCION | `3. **Cableado operativo** (n8n/gateway/frontend) para exponer ‘crear_override_horario‘ y ‘crear_paquete_d…` | no |
| 6 | 125 | DOC_MENCION | `- S3: ‘HORARIOS_GUARD_S3_ROLLBACK_TEST.sql‘ (dropea solo ‘crear_paquete_dia_especial(jsonb)‘; verificado …` | no |

### `04-07-2026/HORARIOS_GUARD_S0_RUNSHEET.md`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 7 | 4 | DOC_MENCION | `‘crear_override_horario‘ ni ‘crear_paquete_dia_especial‘ (esos son S1/S2/S3).` | no |
| 8 | 74 | DOC_NEGATIVE_SCOPE | `**Freno acá.** No generé trigger, ‘crear_override_horario‘ ni ‘crear_paquete_dia_especial‘.` | no |

### `04-07-2026/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 9 | 12 | COMENTARIO_SQL | `-- NO incluye trigger, ni crear_override_horario, ni crear_paquete_dia_especial (S1/S2/S3).` | no |

### `04-07-2026/HORARIOS_GUARD_S1_RUNSHEET.md`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 10 | 4 | DOC_NEGATIVE_SCOPE | `‘trg_ov_guard‘. No incluye ‘crear_override_horario‘, ‘crear_paquete_dia_especial‘,` | no |
| 11 | 98 | DOC_NEGATIVE_SCOPE | `**Freno acá.** No generé ‘crear_override_horario‘, ‘crear_paquete_dia_especial‘, gateway,` | no |

### `04-07-2026/HORARIOS_GUARD_S1_TRIGGER_TEST.sql`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 12 | 11 | COMENTARIO_SQL | `-- NO incluye crear_override_horario ni crear_paquete_dia_especial (S2/S3).` | no |

### `04-07-2026/HORARIOS_GUARD_S2_RUNSHEET.md`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 13 | 4 | DOC_MENCION | `‘crear_paquete_dia_especial‘, función de grupo/‘todas_posibles‘, gateway, frontend ni n8n.` | no |
| 14 | 118 | DOC_NEGATIVE_SCOPE | `**Freno acá.** No generé ‘crear_paquete_dia_especial‘, función de grupo/‘todas_posibles‘,` | no |
| 15 | 120 | DOC_MENCION | `seguimos con **S3** (‘crear_paquete_dia_especial(jsonb)‘: paquetes checkout+checkin y alcances` | no |

### `04-07-2026/HORARIOS_GUARD_S3_FUNCION_TEST.sql`
*Artefacto HISTORICO que CREA S3. Superado por B1_3_F.*

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 16 | 3 | COMENTARIO_SQL | `-- Sub-bloque S3: puerta sancionada crear_paquete_dia_especial(jsonb).` | no |
| 17 | 64 | **CREA_S3** | `CREATE OR REPLACE FUNCTION crear_paquete_dia_especial(p_payload jsonb)` | no |
| 18 | 340 | ACL_REVOKE | `REVOKE EXECUTE ON FUNCTION public.crear_paquete_dia_especial(jsonb) FROM PUBLIC, anon, authenticated, ser…` | no |
| 19 | 342 | COMMENT_ON | `COMMENT ON FUNCTION public.crear_paquete_dia_especial(jsonb) IS` | no |
| 20 | 348 | GATE_PRESENCIA | `SELECT to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL AS funcion_ok;` | no |

### `04-07-2026/HORARIOS_GUARD_S3_ROLLBACK_TEST.sql`
*Rollback HISTORICO de S3. Inaplicable: S3 ya no existe.*

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 21 | 3 | COMENTARIO_SQL | `-- Revierte SOLO S3: elimina crear_paquete_dia_especial(jsonb).` | no |
| 22 | 19 | **DROPEA_S3** | `DROP FUNCTION IF EXISTS public.crear_paquete_dia_especial(jsonb);` | no |
| 23 | 24 | GATE_PRESENCIA | `IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL THEN` | no |
| 24 | 25 | MENSAJE_ERROR | `RAISE EXCEPTION 'ROLLBACK S3 FALLA: crear_paquete_dia_especial sigue presente.';` | no |
| 25 | 41 | MENSAJE_ERROR | `RAISE NOTICE 'ROLLBACK S3 OK: crear_paquete_dia_especial eliminada; R0/S0/S1/S2 intactos.';` | no |
| 26 | 49 | GATE_PRESENCIA | `to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL AS s3_ausente,` | no |

### `04-07-2026/HORARIOS_GUARD_S3_RUNSHEET.md`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 27 | 3 | DOC_MENCION | `**Función:** ‘crear_paquete_dia_especial(jsonb)‘ — puerta sancionada de **paquete de día especial**.` | no |
| 28 | 118 | DOC_MENCION | `- Dropea **solo** ‘crear_paquete_dia_especial(jsonb)‘.` | no |
| 29 | 158 | DOC_MENCION | `- Verificado empíricamente: efecto pretendido cerrado (global_estricto no deja global si un específico lo…` | no |

### `04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql`
*Smoke HISTORICO. Contiene LAS 21 invocaciones. Inejecutable: S3 no existe.*

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 30 | 3 | COMENTARIO_SQL | `-- Smokes de S3 (crear_paquete_dia_especial). ALCANCE: SOLO TEST. Todo en BEGIN..ROLLBACK.` | no |
| 31 | 54 | GATE_PRESENCIA | `IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL THEN` | no |
| 32 | 55 | MENSAJE_ERROR | `RAISE EXCEPTION 'SMOKE S3 abortado: falta crear_paquete_dia_especial. Corre HORARIOS_GUARD_S3_FUNCION_TES…` | no |
| 33 | 127 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(540)::text,'hora_checkout','16:00',` | no |
| 34 | 131 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(570)::text,'hora_checkout','16:00','gap_mi…` | no |
| 35 | 135 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(600)::text,'hora_checkout','16:00',` | no |
| 36 | 139 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(630)::text,'hora_checkout','16:00',` | no |
| 37 | 143 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(660)::text,'hora_checkout','16:00',` | no |
| 38 | 147 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(690)::text,'hora_checkout','16:00',` | no |
| 39 | 151 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(720)::text,'hora_checkout','16:00',` | no |
| 40 | 155 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(750)::text,'hora_checkout','16:00',` | no |
| 41 | 159 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(780)::text,'hora_checkout','16:00',` | no |
| 42 | 163 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(810)::text,'hora_checkout','16:00',` | no |
| 43 | 167 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(840)::text,'hora_checkout','16:00',` | no |
| 44 | 171 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(870)::text,'hora_checkout','16:00',` | no |
| 45 | 175 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(930)::text,'hora_checkout','16:00',` | no |
| 46 | 179 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(960)::text,'hora_checkout','16:00',` | no |
| 47 | 183 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(990)::text,'hora_checkout','16:00',` | no |
| 48 | 187 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1020)::text,'hora_checkout','16:00',` | no |
| 49 | 191 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1050)::text,'hora_checkout','16:00',` | no |
| 50 | 196 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1080)::text,'hora_checkout','16:00',` | no |
| 51 | 201 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1110)::text,'hora_checkout','16:00',` | no |
| 52 | 206 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1140)::text,'hora_checkout','16:00',` | no |
| 53 | 211 | **INVOCA_S3** | `crear_paquete_dia_especial(jsonb_build_object('fecha',_nextmon(1170)::text,'hora_checkout','16:00',` | no |

### `06-07-2026/INVENTARIO_Y_BARRIDO_B1_2_CASCADE.md`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 54 | 46 | DOC_MENCION | `\| ‘HORARIOS_GUARD_S3_FUNCION_TEST.sql‘ \| 1 \| gate (‘crear_paquete_dia_especial‘; verifica efecto vía reso…` | no |

### `07-07-2026/EVALUACION_PIVOTE_VIGENCIAS_SEMANALES.md`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 55 | 25 | DOC_MENCION | `- **S3 ‘crear_paquete_dia_especial‘**: paquete checkout+checkin conjunto con **5 alcances ya implementado…` | no |
| 56 | 80 | DOC_MENCION | `Se conserva ‘overrides_operativos‘ + ‘crear_override_horario‘ (S2) + ‘crear_paquete_dia_especial‘ (S3). M…` | no |

### `07-07-2026/KICKOFF_B1_3_VIGENCIAS_SEMANALES.md`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 57 | 39 | DOC_MENCION | `- **Subsistema de overrides completo:** tabla ‘overrides_operativos‘ (per-cabaña/global, rango, tipo, val…` | no |

### `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql`
*VIVO. Contiene el DROP de S3 y el postcheck de su ausencia.*

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 58 | 4 | COMENTARIO_SQL | `-- REEMPLAZA a crear_paquete_dia_especial(jsonb) (S3): DROP del viejo + CREATE del nuevo,` | no |
| 59 | 39 | COMENTARIO_SQL | `--   GATE 5 no-callers: ninguna otra funcion referencia crear_paquete_dia_especial en pg_proc.prosrc.` | no |
| 60 | 40 | COMENTARIO_SQL | `--   GATE 6 crear_paquete_dia_especial(jsonb) existe (se reemplaza); crear_override_horario_puntual(jsonb…` | no |
| 61 | 41 | COMENTARIO_SQL | `-- DROP crear_paquete_dia_especial + CREATE (no OR REPLACE) F + REVOKE owner-only + postcheck ACL.` | no |
| 62 | 101 | COMENTARIO_SQL | `-- No-callers: ninguna OTRA funcion referencia crear_paquete_dia_especial en su cuerpo.` | no |
| 63 | 103 | BARRIDO_PROSRC | `WHERE p.prosrc ILIKE '%crear_paquete_dia_especial%' AND p.proname <> 'crear_paquete_dia_especial') THEN` | no |
| 64 | 104 | BARRIDO_PROSRC | `RAISE EXCEPTION 'F-GATE: hay funciones que referencian crear_paquete_dia_especial en pg_proc.prosrc. Abor…` | no |
| 65 | 107 | GATE_PRESENCIA | `IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL THEN` | no |
| 66 | 108 | MENSAJE_ERROR | `RAISE EXCEPTION 'F-GATE: crear_paquete_dia_especial (S3) ausente; se esperaba para reemplazar. Abortando.…` | no |
| 67 | 118 | **DROPEA_S3** | `DROP FUNCTION public.crear_paquete_dia_especial(jsonb);` | no |
| 68 | 442 | COMMENT_TEXTO ← **corregido** | `'Guard horarios (F). Alta unificada de override horario puntual. REEMPLAZA a crear_paquete_dia_especial (…` | no |
| 69 | 455 | GATE_PRESENCIA | `IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL THEN` | no |
| 70 | 456 | MENSAJE_ERROR | `RAISE EXCEPTION 'F-POST: crear_paquete_dia_especial deberia estar ausente tras el reemplazo. Abortando.';` | no |

### `09-07-2026/B1_3_F_ROLLBACK_TEST.sql`
*VIVO. Rollback de F: RECREA S3. Referencia legitima.*

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 71 | 5 | COMENTARIO_SQL | `-- crear_paquete_dia_especial (S3) con su cuerpo original, compatible con el resolver VIVO` | no |
| 72 | 10 | COMENTARIO_SQL | `--   crear_override_horario_puntual PRESENTE (hay algo que revertir), crear_paquete_dia_especial AUSENTE.` | no |
| 73 | 37 | GATE_PRESENCIA | `IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL THEN` | no |
| 74 | 38 | MENSAJE_ERROR | `RAISE EXCEPTION 'F-RB-GATE: crear_paquete_dia_especial ya existe (estado inesperado). Abortando.';` | no |
| 75 | 45 | COMENTARIO_SQL | `-- ===== Restauracion del cuerpo original de S3 (crear_paquete_dia_especial) =====` | no |
| 76 | 46 | **CREA_S3** | `CREATE FUNCTION public.crear_paquete_dia_especial(p_payload jsonb)` | no |
| 77 | 322 | ACL_REVOKE | `REVOKE EXECUTE ON FUNCTION public.crear_paquete_dia_especial(jsonb) FROM PUBLIC, anon, authenticated, ser…` | no |
| 78 | 324 | COMMENT_ON | `COMMENT ON FUNCTION public.crear_paquete_dia_especial(jsonb) IS` | no |
| 79 | 330 | GATE_PRESENCIA | `IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL THEN` | no |
| 80 | 331 | MENSAJE_ERROR | `RAISE EXCEPTION 'F-RB-POST: crear_paquete_dia_especial no quedo restaurada. Abortando.';` | no |
| 81 | 337 | ACL_CHECK ← **corregido** | `IF has_function_privilege(r, 'public.crear_paquete_dia_especial(jsonb)', 'EXECUTE') THEN v_bad := v_bad +…` | no |
| 82 | 347 | GATE_PRESENCIA | `SELECT to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL AS s3_restaurada,` | no |

### `09-07-2026/CIERRE_B1_3_Y_KICKOFF_INTEGRACION_TEST.md`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 83 | 23 | DOC_MENCION | `\| F \| ‘crear_override_horario_puntual(jsonb)‘ — override puntual unificado con eje ‘bordes‘; **reemplaza*…` | no |
| 84 | 41 | DOC_NEGATIVE_SCOPE | `‘crear_paquete_dia_especial(jsonb)‘ (S3): **ya no existe** (reemplazada por F).` | no |
| 85 | 85 | DOC_MENCION | `4. **Barrido OPS de S3 (bajo)** — el barrido de callers de ‘crear_paquete_dia_especial‘ fue sobre repo (l…` | no |
| 86 | 119 | DOC_NEGATIVE_SCOPE | `- **S3 reemplazado por F**: ‘crear_paquete_dia_especial‘ ya no existe; vive ‘crear_override_horario_puntu…` | no |

### `09-07-2026/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md`

| # | línea | clase | texto | caller vivo |
|---|---|---|---|---|
| 87 | 38 | DOC_MENCION | `\| ‘crear_paquete_dia_especial(jsonb)‘ \| **‘crear_override_horario_puntual(jsonb)‘** \| F \|` | no |
| 88 | 68 | DOC_MENCION | `**Query de re-pin en TEST** (read-only): ‘SELECT md5(pg_get_functiondef('<obj>'::regprocedure));‘ por cad…` | no |
| 89 | 140 | DOC_NEGATIVE_SCOPE | `- ‘crear_paquete_dia_especial‘ (lo que F reemplaza) **no tenía** acción ni workflow (era DB-only). Por lo…` | no |
| 90 | 168 | DOC_MENCION | `- **Gates previos OPS**: ambiente ‘ops‘; fingerprints OPS baseline pre-B1.3 == esperados; ‘crear_paquete_…` | no |
| 91 | 201 | DOC_MENCION | `6. **Barrido OPS de S3 (bajo)**: el barrido de callers de ‘crear_paquete_dia_especial‘ fue sobre el repo …` | no |

---

## 4. Los hits que importan

De 91, sólo **25** tocan código ejecutable sobre S3.

### 4.1 Los 2 que la CREAN

| Archivo:línea | Contexto |
|---|---|
| `04-07/HORARIOS_GUARD_S3_FUNCION_TEST.sql:64` | Histórico. La creó originalmente. Superado por B1_3_F |
| `09-07/B1_3_F_ROLLBACK_TEST.sql:46` | **Legítimo.** Rollback de F: si F se revierte, S3 debe volver |

### 4.2 Los 2 que la DROPEAN

| Archivo:línea | Contexto |
|---|---|
| `04-07/HORARIOS_GUARD_S3_ROLLBACK_TEST.sql:19` | Rollback histórico |
| `09-07/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql:118` | Es F reemplazando a S3. Su postcheck (455-456) verifica la ausencia |

### 4.3 Las 21 INVOCACIONES

**Las 21 están en `04-07/HORARIOS_GUARD_S3_SMOKES_TEST.sql`**, el smoke histórico. Corre en `BEGIN..ROLLBACK`; no es un caller de producción. Hoy es **inejecutable**: la función no existe.

**Ninguna invocación vive fuera de ese archivo.**

---

## 5. Veredicto

| Chequeo | Resultado |
|---|---|
| **Callers vivos de producción** | **0** |
| Hits en `Workflows/` (n8n) | **0** — exit 1, directorio existente |
| Hits en `Apps/` (frontend) | **0** |
| Hits en `Prototipos/` | **0** |
| Código que crea S3 | 2 — uno histórico, uno es el rollback legítimo de F |
| Código que dropea S3 | 2 — uno histórico, uno es F |
| Invocaciones | **21** — todas en el smoke histórico, inejecutable |

### Sobre causalidad *(corrección 8)*

Lo que este barrido prueba: **hoy no hay referencias vivas a S3 en repo ni en workflows.** Junto con Q7 (S3 ausente en DB por cuatro vías), eso es **consistente** con que `B1_3_F` la reemplazó según su propio cierre.

Lo que **no** prueba: **cuál comando histórico se ejecutó.** El grep lee el repo, no el log de la base. La ausencia está probada; su causa es una inferencia razonable, no un hecho criptográfico.

Confirmación independiente, del propio repo — `09-07/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md:140`:

> `crear_paquete_dia_especial` (lo que F reemplaza) **no tenía** acción ni workflow (era DB-only). Por lo tanto F **no rompe** nada del portal.

El barrido aporta la evidencia cruda que esa afirmación no traía adjunta.

### GATE EXTERNO — CERRADO

S3 **ausente en la DB** (Q7, cuatro vías) y **sin referencias vivas en repo ni workflows** (este barrido).

El criterio 12 de `apto_para_freeze` queda **satisfecho**.
