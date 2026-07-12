# B2A — Runsheet de ejecución (TEST)

**Frente:** Motor de Precios v2 · Bloque **B2A — Estructura + Hardening + Seeds mínimos**
**Canónico de partida:** `6B_SCHEMA_SQL.md` v1.12.0 (HEAD `3648c95`)
**Naturaleza:** aditivo · **TEST-only** · gated anti-`ambiente` · idempotente
**Validación:** ejecutado y verde en harness local PostgreSQL 16.14 (VERIFY 13/13, SMOKES 12/12, round-trip de rollback OK, gate negativo confirmado).

> **Ejecuta Franco.** Claude no toca Supabase/OPS/git. Este bloque **no** modifica funciones de motor, **no** toca `crear_prereserva`, **no** carga grillas masivas, **no** mezcla hardening legacy y **no** toca OPS.

---

## 0. Pre-requisitos

1. Estás apuntando al entorno **TEST** (ref `bdskhhbmcksskkzqkcdp`).
2. Confirmá que `configuracion_general('ambiente') = 'test'` en TEST:
   ```sql
   SELECT valor FROM configuracion_general WHERE clave = 'ambiente';
   ```
   Si el valor no es exactamente `test`, **ajustá la constante `v_esperado`** en el gate de `B2A_MIGRACION.sql` (línea del bloque `$gate$`) al valor real de TEST **antes** de correr. El gate está hardcodeado a `test` a propósito: **físicamente rechaza correr en OPS** (`ambiente='ops'/'prod'` → aborta).

## 1. Orden de ejecución (Supabase SQL Editor)

Correr **en este orden**, cada archivo completo:

| Paso | Archivo | Qué hace |
|---|---|---|
| 1 | `B2A_MIGRACION.sql` | Crea 7 tablas + columnas aditivas + config keys + hardening + seeds mínimos. Una transacción; si el gate falla, no aplica nada. |
| 2 | `B2A_VERIFY.sql` | 13 checks de catálogo (PASS/FAIL) + **fingerprint estructural**. Read-only. |
| 3 | `B2A_SMOKES.sql` | Suite S1–S12 (catálogo + comportamiento). Self-cleaning por savepoints. |

**Rollback (solo si hace falta revertir):** `B2A_ROLLBACK.sql` — ver §4.

## 2. Expected output

**`B2A_MIGRACION.sql`** → termina en `COMMIT`, sin `ERROR`. (Si ves `B2A abortado: ambiente=…`, el gate te frenó: revisá §0.)

**`B2A_VERIFY.sql`** → tabla con **13 filas, todas `PASS`**:

```
V1_tablas_nuevas ........... PASS   (7 tablas)
V2_columnas_aditivas ....... PASS   (7 columnas)
V3_capacidad_override ...... PASS   (boolean/NO/false)
V4_backfill_cabanas ........ PASS   (5/0)
V5_perfiles_seed ........... PASS   (grande=4, chica=3)
V6_config_keys ............. PASS   (8)
V7_config_editable ......... PASS   (6 true / 2 false)
V8_idx_paquetes_evento ..... PASS   (índice FK correctivo)
V9_uq_tarifas_vigente ...... PASS
V10_hardening_tablas ....... PASS   (0 expuestas al Data API)
V11_hardening_secuencias ... PASS   (0 expuestas)
V12_rls_off ................ PASS
V13_trg_precios_inmutable .. PASS   (existe / revocado)
```

Y al final el **fingerprint estructural**. En el harness (PG16.14, sobre la base v1.12.0) dio:

```
b2a_fingerprint_estructural = da52a16c045689523a5f1f113f513a87   (124 líneas)
```

> El valor en TEST **puede diferir** del harness si el orden/tipos de catálogo de Supabase (PG17.6) difieren en detalles de formato. Lo que importa: **guardá el valor que te dé TEST**; será la referencia para comparar contra OPS cuando promovamos B2A. Las 13 filas deben ser `PASS` sí o sí.

**`B2A_SMOKES.sql`** → tabla con **12 filas, todas `PASS`**:

```
S1_tablas .............. PASS (7/7)
S2_constraints ......... PASS
S3_indices ............. PASS
S4_columnas_aditivas ... PASS
S5_backfill ............ PASS
S6_perfiles_seed ....... PASS
S7_config_keys ......... PASS
S8_hardening ........... PASS
S9_inmutabilidad ....... update:PASS delete:PASS
S10_precio_positivo .... PASS - precio=0 rechazado
S11_unicidad_vigente ... PASS - duplicado vigente rechazado
S12_gate_logica ........ PASS - gate rechaza ambiente!=test
```

> **Nota de secuencias:** S10/S11 intentan INSERTs que fallan a propósito; `nextval` no se revierte, así que `tarifas_motor_id_seq` puede quedar con 1–3 huecos. Es esperado y aceptado (lección del proyecto). No persiste ninguna fila.

## 3. Qué crea B2A (resumen)

- **7 tablas nuevas:** `perfiles_tarifarios`, `tarifas_motor`, `temporada_vigencia`, `noches_alta_demanda`, `overrides_precio`, `cotizaciones_precio`, `precios_auditoria`.
- **Columnas aditivas:** `cabanas.perfil_tarifario` (FK, backfilleada) · `reservas.precio_source/precio_motivo/precio_snapshot/capacidad_override/cotizacion_id` · `pre_reservas.cotizacion_id`.
- **8 config keys** de pricing (6 editables socio-only, 2 técnicas).
- **Seeds mínimos:** `perfiles_tarifarios` (grande=4, chica=3) + backfill de las 5 cabañas + los 8 config keys con default. **Sin grillas de precios** (van en B2B).
- **Hardening:** `REVOKE ALL` en las 7 tablas + 4 secuencias; RLS off; trigger propio `trg_precios_inmutable()` (revocado) en `precios_auditoria`; índice correctivo `idx_paquetes_evento_id_evento`.

## 4. Rollback / reversibilidad

`B2A_ROLLBACK.sql` revierte B2A por completo (dropea las 7 tablas, las columnas aditivas, los config keys, el trigger propio y el índice correctivo). Es **gated (TEST-only) e idempotente**. Round-trip validado en harness: migración → rollback (queda todo en 0) → re-migración (restaura las 7 tablas).

**Seguro solo antes de poblar datos de pricing** (es decir, inmediatamente post-B2A / pre-B2B). Una vez que B2B seedee grillas o haya cotizaciones/reservas apuntando a `cotizacion_id`, un rollback pierde esos datos: en ese punto conviene una reversión selectiva.

## 5. Integridad de artefactos

**SHA256:**
```
B2A_MIGRACION.sql  c058b8e41c2c05dedcddc128dd1d37e4bcb3098e130685ff5d53ae85e15a67b5
B2A_VERIFY.sql     7088394ffb650db18c5388c49460041e51e27fc5bf722d9ba1a4bcab0c9f372b
B2A_SMOKES.sql     7ffb2871f0c87d47110cae1723084d70e39875a6cf021cf9e796faf32ad2bcd2
B2A_ROLLBACK.sql   16620c647a28b14c8bc511bd2501eea20ee17848fcff82b78f35c4dfeeeed052
```
**Fingerprint estructural (harness):** `da52a16c045689523a5f1f113f513a87`

## 6. Después de B2A

- Guardame el **fingerprint de TEST** y confirmá VERIFY 13/13 + SMOKES 12/12.
- Con eso cerrado, sigue **B2B — Seeds de pricing** (temporada_vigencia ≥3 años, 4 grillas × 8 conceptos, tuning de config, smokes de consistencia de seed), en conversación aparte.
- El micro-bloque de override de capacidad (`crear_prereserva` + A07 + UI) queda para **B3.1**, separado.

---
**Recordatorio de alcance:** B2A = solo estructura + hardening + seeds mínimos. No grillas masivas, no funciones de motor, no `crear_prereserva`, no hardening legacy, no OPS.
