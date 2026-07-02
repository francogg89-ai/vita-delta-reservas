# Runsheet — HORARIOS Fase B / Bloque 3 (v3): integración de `resolver_horario()` en `crear_prereserva`

**Alcance:** SOLO TEST (ref `bdskhhbmcksskkzqkcdp`). NO OPS. NO canónico, wrappers, gateway, frontend ni `obtener_disponibilidad_rango`.
**Estado:** NADA aplicado. Este runsheet se ejecuta recién cuando vos lo autorices.
**Regla de editor:** cada script se corre COMPLETO, con **nada seleccionado** (L-8A-01).

## Artefactos
1. `HORARIOS_FASEB_B3_INTEGRACION_CREAR_PRERESERVA_TEST.sql` (v3) — `CREATE OR REPLACE public.crear_prereserva` con gate anti-OPS embebido (ambiente + schema + existencia + fingerprint), en `BEGIN…COMMIT`.
2. `HORARIOS_FASEB_B3_VERIFICACION_TEST.sql` (v3) — `[PRE]` con `gate_ok`; `[POST-1/2/3]`.
3. `HORARIOS_FASEB_B3_SMOKES_TEST.sql` (v3) — **18 smokes** en un `BEGIN…ROLLBACK` + POSTCHECK.

---

## Paso 0 — Gate anti-OPS OBLIGATORIO (manual, antes de aplicar)
Corré el bloque **[PRE]** de `...VERIFICACION...`. Una sola fila; confirmá:

- [ ] `gate_ok = true` (resume las 3 guardas), y en detalle:
  - `coincide_baseline = true` → fingerprint = `f258ad9b6e4cd0f7dcb7318e5724f0ce`;
  - `ambiente = test`;
  - `schema_actual = public`.

**Si `gate_ok` no es `true` → PARAR.** No aplicar.

> Doble red: las mismas 4 guardas (ambiente, `current_schema()='public'`, existencia de `public.crear_prereserva(jsonb)`, fingerprint) están embebidas y **ejecutables** en el SQL de integración dentro de `BEGIN…COMMIT`. Si algo no da, `RAISE EXCEPTION` aborta la tx y el `CREATE OR REPLACE` **no** corre.

## Paso 0-bis — Respaldo para rollback (recomendado)
```sql
SELECT pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure);
```
Guardá el resultado. Revertir = reaplicar ese texto (o el `crear_prereserva` de `HORARIOS_B2_GUARD_HELPER_TEST.sql`, misma base) con `CREATE OR REPLACE`.

---

## Paso 1 — Aplicar la integración
Correr COMPLETO `HORARIOS_FASEB_B3_INTEGRACION_CREAR_PRERESERVA_TEST.sql` (nada seleccionado).
- El gate corre primero; si pasa, se aplica el `CREATE OR REPLACE` y `COMMIT`.
- Esperado: sin error, función reemplazada. Firma calificada `public.crear_prereserva`.

## Paso 2 — Verificación post-apply
Correr **[POST-1]**, **[POST-2]**, **[POST-3]** de `...VERIFICACION...`:
- [ ] **[POST-1]** `difiere_del_baseline = true`. **Anotá `fingerprint_after`** (nuevo baseline del motor).
- [ ] **[POST-2]** `security_definer=false`, `owner=postgres`, `proacl_raw = {postgres=X/postgres}`.
- [ ] **[POST-3]** las 15 columnas en **TRUE**.

**Si algo no da lo esperado → revertir con el respaldo del Paso 0-bis y avisar.**

## Paso 3 — Smokes (18)
Correr COMPLETO `HORARIOS_FASEB_B3_SMOKES_TEST.sql` (nada seleccionado).
- [ ] Tabla de veredicto: **18/18 `PASS`**.
- [ ] Resumen: `pass=18, fail=0, total=18`.
- [ ] `pre_reservas_creadas_en_tx = 8` (los éxitos: T2, T3, T4, **T4b**, T5, T7, T10·1, T10b·1). Se revierten con el ROLLBACK.

Cobertura: no-reg hábil/domingo (vs fórmula de config); override global check-in (**anchor #1**); **override global check-out en `fecha_out` → `hora_checkout=12:00` (anchor #2, T4b)**; cabaña>global; HARD 3 causas con `borde=fecha_in`; **HARD de segunda llamada con `borde=fecha_out` (T6f)**; over-block (tipo no consumido); precedencia (gana a `cabana_no_existe`); margen recomputado dentro/fuera; guard `fecha_in_pasada`; idempotencia intacta; idempotencia gana a override corrupto. **Todos los HARD (T6a–f) gatean `_seq_pr_movio=false` y `_seq_hu_movio=false` en el PASS** (no-consumo real, no solo informado).

> Si un caso de éxito devuelve `no_disponible`/`conflicto_con_*`: las fechas son lejanas (`fecha_hoy_ar()+300..720`) para minimizar colisión; si TEST tuviera algo ahí, corré con offsets distintos.

## Paso 4 — POSTCHECK (tras el ROLLBACK del smoke)
Incluido al final del script (read-only, fuera de la tx):
- [ ] `pre_reservas` con `source_event='smoke_b3'` = **0**.
- [ ] `overrides_operativos` con `motivo='smoke_b3'` = **0**.

---

## Cierre / siguiente
- Si 18/18 PASS y POSTCHECK en 0: integración verde en TEST. **Anotar el nuevo fingerprint** para el paquete de promoción futuro. Canonización del motor de horarios: **diferida** al cierre del frente (no se toca `6B_SCHEMA_SQL.md` ni satélites ahora).
- **NO** se acuñan `D-*`/`L-*` en este paso. Promoción a OPS: NO en este bloque.
