# S1 — Barrera DB (constraint trigger diferido) — RUNSHEET

**Sub-bloque S1. Solo la barrera:** trigger-fn `trg_guard_overrides()` + constraint trigger
`trg_ov_guard`. No incluye `crear_override_horario`, `crear_paquete_dia_especial`,
gateway, frontend ni n8n.

- **Alcance:** SOLO **TEST** (`bdskhhbmcksskkzqkcdp`). **NO** OPS/canónico/gateway/frontend/workflows.
- **Sin acuñar `D-*`/`L-*`.** Ejecutás vos; yo no toco TEST/OPS/n8n/Vercel/git.

> **Nota sobre el fingerprint ODR:** en tu pedido de S1 quedó escrito como
> `37009a32154f93b80500c0f15b46b` (29 chars), pero el correcto —el de R0/S0, con los 32 chars
> de un md5— es **`37009a32154f93b80520500c0f15b46b`** (faltaba el `205`). Los artefactos usan el
> correcto. Si el gate te tira `fingerprint ODR=...`, verificá cuál esperás.

---

## Qué se crea

- **`trg_guard_overrides()`** (trigger-fn, `SECURITY INVOKER`): toma
  `pg_advisory_xact_lock(10,0)` **primero**; computa `(id_cabana, fecha)` afectados desde
  `OLD`/`NEW` según operación; delega en `validar_estado_override` (S0, sin reimplementar el
  resolver); `RAISE` `ERRCODE 45000` con `DETAIL` jsonb
  `{error, id_cabana, fecha, tg_op, id_override_old, id_override_new, detalle_validador}`.
  - `INSERT` → `NEW` si `NEW.activo`; `DELETE` → `OLD` si `OLD.activo`;
    `UPDATE` → skip **solo** si el cambio se limita a columnas inertes
    (`motivo`/`creado_por`/`source_event`), si no `applied_set(OLD)` si `OLD.activo` ∪
    `applied_set(NEW)` si `NEW.activo`.
  - **Columnas efectivas (v2):** además de `activo`/`tipo_override`/`valor`/`fecha_desde`/
    `fecha_hasta`/`id_cabana`, ahora **`created_at` e `id_override`** — participan del desempate
    del resolver (`ORDER BY (id_cabana IS NOT NULL) DESC, created_at DESC, id_override DESC`), así
    que un `UPDATE` de cualquiera puede cambiar el ganador y el horario efectivo. NO son metadata.
    Invariante documentada en el código: si el resolver pasa a leer otra columna, agregarla ahí.
  - `applied_set` = (esa cabaña, o **todas las activas** si `id_cabana IS NULL`) ×
    `[fecha_desde, COALESCE(fecha_hasta, fecha_desde)]` (**semántica R0**: `fecha_hasta NULL`
    = solo `fecha_desde`).
- **`CREATE CONSTRAINT TRIGGER trg_ov_guard AFTER INSERT OR UPDATE OR DELETE ON
  overrides_operativos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW`**: valida el estado
  efectivo **final** (paquete completo) en el commit, no un `NEW` aislado.

**Método:** `CREATE OR REPLACE FUNCTION` + `DROP TRIGGER IF EXISTS` + `CREATE CONSTRAINT
TRIGGER` (idempotente; auto-RLS OFF en TEST → sin bug Dashboard).

---

## Orden de ejecución (Supabase SQL Editor, **sin selección parcial** — L-8A-01)

1. **`HORARIOS_GUARD_S1_TRIGGER_TEST.sql`** — gate (`ambiente=test` + resolver `58d75c1b` +
   ODR `37009a32154f93b80520500c0f15b46b` + los 3 validadores S0). Último SELECT →
   `trigger_fn_ok`, `constraint_trigger_ok` = `true`.
2. **`HORARIOS_GUARD_S1_SMOKES_TEST.sql`** — esperado:
   **`SMOKE S1 VALIDADO: compuerta 14/14 PASS, 0 FAIL`** con los cuatro residuales = 0. Si algo
   falla, el editor muestra la excepción con los casos No-PASS y la tx se revierte sola.

**Rollback (si hace falta):** **`HORARIOS_GUARD_S1_ROLLBACK_TEST.sql`** — quita trigger +
trigger-fn; deja intactos los validadores S0 y el resolver R0. Confirma
`trigger_ausente`, `trigger_fn_ausente`, `validadores_s0_intactos` = `true`.

---

## Cobertura de smokes (16 casos, `SET CONSTRAINTS trg_ov_guard IMMEDIATE` con nombre específico)

`1` INSERT co16 solo → FALLA same-day · `2` INSERT paquete co16+ci18 → PASA · `3` INSERT global
con cabaña comprometida → FALLA completo · `4` UPDATE `activo false→true` que pisa comprometido
→ FALLA · `5` UPDATE `activo true→false` en comprometida → FALLA · `6` UPDATE metadata-only en
comprometida → PASA · `7` DELETE activo en comprometida → FALLA · `8` DELETE inactivo → PASA ·
`9` DELETE media mitad de paquete (orphan) → FALLA same-day · `10` DELETE paquete completo →
PASA · `11a` `fecha_hasta NULL` comprometido en `+5` → PASA · `11b` rango `fecha_desde..+5`
comprometido en `+5` → FALLA · `12` global con `_cab2()` comprometido → FALLA (expansión) ·
`13` cabaña-específico en `_cab()` con `_cab2()` comprometido → PASA (cabaña-especificidad) ·
**`14` UPDATE `created_at` para flip de ganador** (dos overrides activos, gana por `created_at`;
el nuevo ganador da same-day inválido) → **FALLA** (`created_at` es efectiva) ·
**`15` UPDATE metadata-only real (`motivo`+`creado_por`+`source_event`) en comprometida → PASA**.

Los overrides pre-existentes se siembran con el trigger **deshabilitado**
(`ALTER TABLE … DISABLE TRIGGER trg_ov_guard`) para que no encolen eventos que contaminen los
casos; los eventos comprometidos (reservas) no disparan el trigger de overrides. El caso 14 fija
`created_at` explícito en el seed para forzar un ganador inicial válido.

---

## Validación previa (mi parte del split)

- **pglast** `parse_sql` + `parse_plpgsql` → **OK** en los tres SQL.
- **Harness PostgreSQL 16 fiel** (schema con columnas/enums reales + resolver R0 + validadores
  S0): **16/16 PASS, 0 FAIL**, compuerta real sin excepción, residuales **0**.
- **Bypass `created_at` reproducido y cerrado:** con el trigger v1 (sin el fix), un `UPDATE` de
  solo `created_at` del override perdedor lo hacía ganar y el `COMMIT` **pasaba**, dejando un
  checkout 16:00 same-day inválido persistido. Con el trigger v2 (`created_at`/`id_override`
  efectivas), el mismo `UPDATE` **aborta en el COMMIT** con
  `guard_overrides: override_incompatible_same_day` y el estado se revierte; el `UPDATE`
  metadata-only real sigue pasando.
- **Disparo confirmado** con `SET CONSTRAINTS trg_ov_guard IMMEDIATE` (los 16 casos) **y en el
  COMMIT real** sin `SET CONSTRAINTS`. Rollback S1 deja `fn`/`trigger` ausentes y validadores S0
  intactos.

---

**Freno acá.** No generé `crear_override_horario`, `crear_paquete_dia_especial`, gateway,
frontend ni n8n. Cuando corras el trigger + smokes y me confirmes 14/14 verde en TEST, seguimos
con **S2** (`crear_override_horario(jsonb)`: alta sancionada que valida contra el guard antes de
insertar) o con lo que definas.
