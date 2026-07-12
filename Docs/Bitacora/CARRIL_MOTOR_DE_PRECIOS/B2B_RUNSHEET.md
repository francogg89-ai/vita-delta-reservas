# B2B — Runsheet de ejecución (TEST)

**Frente:** Motor de Precios v2 · Bloque **B2B — Seeds de pricing**
**Requisito:** B2A aplicado y cerrado en TEST (fingerprint estructural `da52a16c045689523a5f1f113f513a87`).
**Naturaleza:** **solo datos** · aditivo · **TEST-only** · gated anti-`ambiente` · **idempotente** · version-aware.
**Validación:** ejecutado y verde en harness PostgreSQL 16.14 (VERIFY 8/8, SMOKES 9/9, idempotencia y round-trip de rollback OK, gate negativo confirmado).

> **Ejecuta Franco.** Este bloque **no** toca estructura, reservas/pre-reservas, funciones de motor, gateway/portal, hardening legacy ni OPS.

---

## 0. Pre-requisitos

1. Estás en **TEST** (ref `bdskhhbmcksskkzqkcdp`) y `configuracion_general('ambiente') = 'test'`.
2. B2A ya aplicado. El seed tiene un **pre-check** que aborta si faltan las tablas/perfiles de pricing.
3. El gate está hardcodeado a `test`: con `ambiente='ops'` **aborta** (verificado).

## 1. Orden de ejecución (Supabase SQL Editor)

| Paso | Archivo | Qué hace |
|---|---|---|
| 1 | `B2B_SEED.sql` | Siembra 8 filas en `temporada_vigencia` + 32 celdas vigentes en `tarifas_motor`. |
| 2 | `B2B_VERIFY.sql` | 8 checks (PASS/FAIL) + detalle de discrepancias + fingerprints. Read-only. |
| 3 | `B2B_SMOKES.sql` | Suite Sm1–Sm9. Read-only. |

**Rollback (si hace falta):** `B2B_ROLLBACK.sql` — ver §4.

## 2. Expected output

**`B2B_SEED.sql`** → `INSERT 0 8` (temporadas) + `INSERT 0 32` (tarifas) + `COMMIT`.
Re-correr es seguro: la segunda corrida da **`INSERT 0 0` / `INSERT 0 0`** (idempotente, no duplica ni pisa versiones posteriores).

**`B2B_VERIFY.sql`** → **8 filas, todas `PASS`**:

```
T1a_temporadas_exactas ... PASS   (8 filas / 8 match)
T1b_cobertura_continua ... PASS   (0 discontinuidades)
T2_tarifas_vigentes ...... PASS   (32)
T3_completitud_grillas ... PASS   (0 faltantes)
T4_sin_ceros ............. PASS   (0)
T5_unicidad_vigente ...... PASS   (0 duplicadas)
T6_precios_exactos_32 .... PASS   (32/32 match)
T7_hardening_intacto ..... PASS
```

Después: **tabla de discrepancias de precio → debe salir vacía (`0 rows`)**. Si aparece alguna fila, muestra `perfil / temporada / concepto / precio_esperado / precio_cargado / problema`.

Y los dos fingerprints:

```
b2a_fingerprint_estructural = da52a16c045689523a5f1f113f513a87   (124 líneas)
   estado = "PASS - estructura intacta"    ← B2B NO tocó estructura

b2b_fingerprint_datos       = 6d1653748d68ee9b62aa20aba5f3333d   (40 líneas)
```

**`B2B_SMOKES.sql`** → **9 filas, todas `PASS`**:

```
Sm1_temporadas ............... PASS - 8 filas, continua 2026-03-15..2030-03-15
Sm2_8_conceptos_x_grilla ..... PASS - 4 grillas x 8 conceptos = 32
Sm3_sin_celdas_faltantes ..... PASS - cartesiano 100% cubierto
Sm4_sin_ceros ................ PASS - ninguna tarifa <= 0
Sm5_unicidad_vigente ......... PASS - 1 sola versión vigente por celda
Sm6_precios_exactos_32 ....... PASS - 32/32 precios exactos
Sm7_grillas_completas ........ PASS - grande/chica x alta/baja completas (tarifa_incompleta no aplicaría)
Sm8_resolucion_bordes ........ PASS - bordes inclusive/exclusive correctos, resolución única
Sm9_hardening_y_estructura ... PASS - hardening intacto + fingerprint B2A sin cambios
```

## 3. Qué siembra B2B

**`temporada_vigencia` — 8 filas** (D-PR-16: `anio` = año de inicio; fin exclusive; cobertura continua `2026-03-15 → 2030-03-15`):

| clave | anio | fecha_in | fecha_out_excl |
|---|---|---|---|
| baja | 2026 | 2026-03-15 | 2026-11-15 |
| alta | 2026 | 2026-11-15 | 2027-03-15 |
| baja | 2027 | 2027-03-15 | 2027-11-15 |
| alta | 2027 | 2027-11-15 | 2028-03-15 |
| baja | 2028 | 2028-03-15 | 2028-11-15 |
| alta | 2028 | 2028-11-15 | 2029-03-15 |
| baja | 2029 | 2029-03-15 | 2029-11-15 |
| alta | 2029 | 2029-11-15 | 2030-03-15 |

**`tarifas_motor` — 32 celdas vigentes** (4 grillas × 8 conceptos), `vigente_desde=NOW()`, `vigente_hasta=NULL`, `created_by='seed_b2b'`, `source_event='b2b:seed_inicial'`:

| concepto | grande·alta | grande·baja | chica·alta | chica·baja |
|---|---|---|---|---|
| semana_noche_1 | 165000 | 130000 | 140000 | 110000 |
| semana_noche_2 | 130000 | 100000 | 110000 | 90000 |
| semana_noche_3 | 105000 | 80000 | 90000 | 70000 |
| semana_noche_4 | 105000 | 80000 | 90000 | 70000 |
| semana_noche_5plus | 105000 | 80000 | 90000 | 70000 |
| alta_demanda_noche_1 | 255000 | 180000 | 220000 | 150000 |
| alta_demanda_noche_2 | 130000 | 120000 | 115000 | 100000 |
| alta_demanda_noche_3plus | 190000 | 150000 | 165000 | 125000 |

## 4. Rollback / reversibilidad

`B2B_ROLLBACK.sql` es **quirúrgico**: borra solo las filas del seed (`source_event='b2b:seed_inicial'` + `created_by='seed_b2b'`) y las 8 temporadas. **No toca estructura** (fingerprint B2A queda intacto) ni versiones de tarifas creadas después por el portal.

Round-trip validado en harness: seed (8|32) → rollback (0|0, estructura intacta con las 7 tablas) → re-seed (8|32).

Seguro mientras no existan cotizaciones/reservas apoyadas en estas tarifas.

## 5. Integridad de artefactos

**SHA256:**
```
B2B_SEED.sql      9e3c802756b4f7a6a5fd3dbf255eff8edda9d982169f8b3160e0c2652359f6db
B2B_VERIFY.sql    297b22356653a00b7691cab367be9b1b1bb0b322c2ade5de3df2518cd7af9680
B2B_SMOKES.sql    e4cc385e0b1e6fb13f30950ee7a08f0293904178f95bb6b96324a3541938315e
B2B_ROLLBACK.sql  72789b5e901a097a471d8a4b30dac694d22b688a0e576eb402041cf5d5d449a5
```

**Fingerprints (harness):**
```
estructural B2A (debe seguir igual) : da52a16c045689523a5f1f113f513a87   (124 líneas)
datos B2B (nuevo)                   : 6d1653748d68ee9b62aa20aba5f3333d   (40 líneas)
```

## 6. Después de B2B

- Confirmame VERIFY 8/8 + discrepancias vacías + SMOKES 9/9, y pasame el **fingerprint de datos** que te dé TEST.
- Con B2B cerrado, sigue **B3 — Funciones** (helpers deterministas + `precios_cotizar`): ahí entran resolución de temporada, clasificación de noche, ordinales acumulados, eventos, extras, reglas de venta y el error `tarifa_incompleta`.
- Pendiente aparte: **B3.1** (override de capacidad: `crear_prereserva` + A07 + UI).
- Pendiente de diseño en B3: **precedencia de overrides solapados** (riesgo diferido de B2A).

---
**Recordatorio de alcance:** B2B = solo seeds. No estructura, no funciones, no gateway/portal, no OPS, no hardening legacy.
