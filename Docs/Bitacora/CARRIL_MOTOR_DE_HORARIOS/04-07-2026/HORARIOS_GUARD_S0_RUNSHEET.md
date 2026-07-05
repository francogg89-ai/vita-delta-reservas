# S0 — Validadores del guard de overrides horarios — RUNSHEET

**Sub-bloque S0. Solo los tres validadores read-only.** No incluye trigger,
`crear_override_horario` ni `crear_paquete_dia_especial` (esos son S1/S2/S3).

- **Alcance:** SOLO **TEST** (`bdskhhbmcksskkzqkcdp`). **NO** OPS, **NO** canónico,
  **NO** gateway/frontend/workflows.
- **Sin acuñar `D-*`/`L-*`** (se mintean en el cierre formal del frente de horarios).
- Ejecutás vos; yo no toco TEST/OPS/n8n/Vercel/git.

---

## Qué se crea (read-only, sin locks)

1. **`validar_estado_horario_final(id_cabana, fecha) → jsonb`** — llama a
   `resolver_horario`; si el resolver rechaza el valor → `override_hora_invalido`;
   si `(hora_checkin_efectiva - hora_checkout_efectiva) < 2h` →
   `override_incompatible_same_day`; si no `{ok:true}`.
2. **`validar_no_eventos_comprometidos(id_cabana, fecha) → jsonb`** — existencia de
   evento comprometido, **independiente** del estado de overrides: reservas
   `{confirmada, activa, completada}` con `fecha_checkin`/`fecha_checkout=fecha` →
   `override_pisa_reserva`; pre-reservas (`pendiente_pago` vigente | `pago_en_revision`)
   con `fecha_in`/`fecha_out=fecha` → `override_pisa_prereserva`; si no `{ok:true}`.
3. **`validar_estado_override(id_cabana, fecha) → jsonb`** — orquestador: eventos
   comprometidos **primero** (conservador), luego estado horario final. Única fuente de
   verdad para S1/S2/S3.

Los tres: `VOLATILE`, `SECURITY INVOKER`, sin locks, `REVOKE EXECUTE` espejo Bloque 23.

**Método:** `CREATE OR REPLACE` (funciones nuevas; idempotente/re-ejecutable; auto-RLS
OFF en TEST → sin bug del Dashboard, L-CC-07).

---

## Orden de ejecución (Supabase SQL Editor, **sin selección parcial** — L-8A-01)

1. **`HORARIOS_GUARD_S0_VALIDADORES_TEST.sql`**
   Gate valida `ambiente='test'` + `schema=public` + resolver
   `58d75c1b6b812ee2d2c9751ddcb0cd4d` (post-R0) + ODR `37009a32154f93b80520500c0f15b46b`.
   El aviso *"Run without RLS"* es esperado (L-8A-04). Último SELECT → `f1_ok`, `f2_ok`,
   `f3_ok` = `true`.

2. **`HORARIOS_GUARD_S0_SMOKES_TEST.sql`**
   Gate exige que los validadores ya existan. Esperado: veredicto
   **`SMOKE S0 VALIDADO: compuerta 13/13 PASS, 0 FAIL`** con los cuatro residuales
   (`overrides`/`reservas`/`prereservas`/`huespedes`) = 0. Si la compuerta falla, el editor
   muestra la excepción con las filas No-PASS y la tx se revierte sola (nada persiste).

---

## Cobertura de smokes (13 casos)

`1` fecha libre base → ok · `2` co16 + ci base → `override_incompatible_same_day` ·
`3` paquete co16+ci18 (gap 2 h) → ok · `4` reserva check-in comprometido →
`override_pisa_reserva` · `5` reserva check-out comprometido → `override_pisa_reserva` ·
`6` comprometido aunque la hora coincida → **igual** `override_pisa_reserva` (existencia) ·
`7` valor inválido `25:99` → `override_hora_invalido` · `4b` pre-reserva vigente →
`override_pisa_prereserva` · `81`/`82` `fecha_hasta NULL` aplica en `fecha_desde` pero no en
`fecha_desde+5` (semántica R0) · `91`/`92` cabaña-especificidad · `93` override global afecta
una cabaña específica (prep expansión S1/S3).

---

## Validación previa (mi parte del split)

- **pglast** `parse_sql` + `parse_plpgsql` → **OK** en los dos SQL.
- **Harness PostgreSQL 16 fiel** (schema con columnas y enums reales de `reservas`/
  `pre_reservas`/`overrides_operativos`/`cabanas`/`huespedes`/`configuracion_general` +
  resolver R0 corregido): los tres validadores reales + los seeds reales del smoke corren
  **13/13 PASS, 0 FAIL**, compuerta real sin excepción, residuales **0**.

---

**Freno acá.** No generé trigger, `crear_override_horario` ni `crear_paquete_dia_especial`.
Cuando corras S0 y me confirmes 13/13 verde en TEST, arranco **S1** (la barrera:
`trg_guard_overrides()` + `CREATE CONSTRAINT TRIGGER … DEFERRABLE INITIALLY DEFERRED`), que
consume estos validadores.
