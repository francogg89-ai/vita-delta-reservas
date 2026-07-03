# Runsheet — Integración de `resolver_horario()` en `obtener_disponibilidad_rango` (TEST)

**Frente:** Motor formal de horarios — bloque de integración en la función de LECTURA.
**Entorno:** TEST (ref `bdskhhbmcksskkzqkcdp`). **No** toca OPS, canónico, gateway, frontend, workflows, A07/A08 ni `crear_prereserva`.
**Política aplicada:** D1 (ante `resolver_horario()` HARD → preservar `estado` ocupacional, ambas horas → NULL, all-or-nothing por fila).
**Estado global:** A+B ✅ ejecutados y verdes en TEST · C ⬜ pendiente de correr · Cierre formal ⬜ (diferido).
**Sin `D-*`/`L-*`** (se acuñan en el cierre del frente completo de horarios).

---

## 0. Artefactos del bloque

| # | Archivo | Rol | Estado |
|---|---|---|---|
| — | `HORARIOS_DISPONIBILIDAD_RANGO_RELEVAMIENTO.md` | Relevamiento + diseño (opciones, D1, riesgos) | ✅ |
| 0 | `HORARIOS_DISPONIBILIDAD_RANGO_PASO0_LIVE_TEST.sql` | Verificación live + fingerprints baseline | ✅ ejecutado |
| A | `HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql` | `CREATE OR REPLACE` + gate anti-OPS/baseline | ✅ aplicado |
| B | `HORARIOS_DISPONIBILIDAD_RANGO_B_VERIFICACION_TEST.sql` | Verificación PRE/POST (read-only) | ✅ ejecutado |
| C | `HORARIOS_DISPONIBILIDAD_RANGO_C_SMOKES_TEST.sql` | Smokes completos (12 casos) — gate anti-OPS + writes controlados en tx + teardown | ⬜ correr |
| — | `HORARIOS_REQUISITO_GUARD_ALTA_OVERRIDES_PENDIENTE.md` | Requisito obligatorio diferido (bloque futuro) | 📌 registrado |

**Fingerprints:**
- Baseline ODR (pre-A): `f8d6bbf533c775349642e7ed34d5ea8c`
- Resolver (dependencia): `759662b4afaed7af426917aa3717b34c`
- **Post-A ODR (nuevo baseline del motor): `37009a32154f93b80520500c0f15b46b`**

---

## 1. Prerequisitos (todos ✅ verificados en Paso 0)

- `ambiente='test'`, `current_schema()='public'`.
- Existen `obtener_disponibilidad_rango(date,date,bigint)` y `resolver_horario(bigint,date)`.
- Resolver `STABLE`/`INVOKER`/owner-only (hardening intacto).
- ODR owner-only (`postgres=X/postgres`) → método `CREATE OR REPLACE`.

---

## 2. Secuencia ejecutada (Paso 0 → A → B)

### Paso 0 — Verificación live ✅
Correr `PASO0` bloque `[A]` (nada seleccionado) y `[B]` (seleccionado aparte). **Resultado:** entorno TEST, ambas funciones presentes, def live ≡ canónico salvo comentarios/EOL (cero drift lógico), fingerprints capturados.

### Paso A — Integración ✅
1. Correr `[PRE]` del archivo B → confirmar **`gate_ok = true`**.
2. Aplicar `A` con **nada seleccionado** (script completo, un solo `BEGIN…COMMIT`; el gate embebido aborta si algo no coincide).
**Resultado obtenido:** aplicado sin error.

### Paso B — Verificación PRE/POST ✅
Correr `[POST-A]`, `[POST-B]`, `[POST-C1]`, `[POST-C2]`.
**Resultado obtenido:** `[POST-A].todo_ok = true`; `fingerprint_after = 37009a32154f93b80520500c0f15b46b` (≠ baseline); ACL/owner/INVOKER/volatile preservados; firma + 9 columnas iguales; resolver fp igual; `CROSS JOIN LATERAL` presente; CASE viejos ausentes; extracción nueva presente; `vista_disponibilidad` ejecuta; ODR con cabaña concreta y `NULL` devuelven estructura correcta (horas base, sin overrides en TEST).

---

## 3. Paso C — Smokes (PENDIENTE de correr)

**C hace writes controlados en TEST dentro de una transacción, con teardown y cero residuos** — no es read-only. Estructura: `CREATE TEMP TABLE _smoke_res … ON COMMIT PRESERVE ROWS` → `BEGIN` → **GATE anti-OPS** → SETUP (siembra overrides + 1 bloqueo marcados `__SMOKE_HORARIOS__`, en fechas lejanas `hoy+300..`) → E2E (12 casos; oracle `pg_temp._smoke_odr_vieja` para no-regresión) → TEARDOWN (borra el fixture y dropea el oracle) → POSTCHECK → `COMMIT` → `SELECT * FROM _smoke_res` (último statement, visible).

**Gate anti-OPS (aborta antes de tocar fixture):** valida `ambiente='test'`, `current_schema()='public'`, existencia de `fecha_hoy_ar()` / `obtener_disponibilidad_rango(date,date,bigint)` / `resolver_horario(bigint,date)`, fingerprint ODR = `37009a32…` (post-A) y fingerprint resolver = `759662b4…`. Si algo no coincide → `RAISE EXCEPTION` y la transacción aborta sin sembrar nada. (Verificado: gate negativo aborta con fixture=0.)

**Cero residuos (mecanismo):** el fixture se **borra en el TEARDOWN antes del `COMMIT`**. Si el script termina bien, el `COMMIT` persiste **solo la limpieza** (fixture=0), nunca los datos del fixture. Si explota antes del teardown, la transacción **aborta** y no persiste nada. La tabla `_smoke_res` es `TEMP` y sobrevive al `COMMIT` (para mostrarse) pero no es un residuo en tablas reales; muere al cerrar la sesión. Verificado en harness: tras el `COMMIT`, 0 overrides/bloqueos marcados, oracle pg_temp inexistente, ODR real intacta.

**Cómo correr:** un solo run con **nada seleccionado**. El resultado visible (último statement, tras el `COMMIT`) es la tabla `_smoke_res` (una fila por caso + `GATE` + `VEREDICTO FINAL`). **Pegame esa tabla.**

**Qué esperar:** `pass = t` en las 16 filas, `VEREDICTO FINAL = TODOS VERDES`. Cobertura:

1. no-regresión columnas/firma · 2. no-regresión estados (nueva=vieja, 120d) · 3. semántica `[in,out)` + `checkout_disponible` (oracle no-horas + bloqueo media-abierta) · 4. override válido global · 5. override por cabaña gana al global · 6. override corrupto global → D1 NULL · 7. override corrupto por cabaña → D1 sin contaminar · 8. modo A26/cabaña concreta · 9. modo `NULL`/todas activas · 10. performance rango real A26 · 11. performance rango grande (365 noches) · 12. fixture limpio (TEARDOWN + POSTCHECK, residuos=0, oracle DROP).

> **Performance:** los umbrales son **generosos** (caso 10 `< 5000 ms`, caso 11 `< 30000 ms`) — el objetivo es medir la cota, no ajustarla. En el harness local dieron ~400 ms y ~445 ms. **Reportá los tiempos reales de TEST** en `obtenido`; si el caso 11 se acercara al umbral o lo superara, evaluamos optimización (precargar config/overrides fuera del LATERAL) en un bloque aparte. No es bloqueante salvo que supere el umbral.

---

## 4. Contingencia / rollback

- **C hace writes transitorios de fixture dentro de la transacción** (no es read-only). No puede dejar residuos ni alterar la función: el fixture se borra en el teardown antes del `COMMIT`, y si el editor mostrara un error a mitad, la transacción aborta y nada persiste. Si aborta, volvé a correrlo (el `DROP TABLE IF EXISTS _smoke_res` inicial tolera re-corridas en la misma sesión).
- **Revertir A** (solo si hiciera falta por una regresión detectada): re-aplicar la definición **baseline** de `obtener_disponibilidad_rango` (la de fingerprint `f8d6bbf5…`, con los 2 `CASE` hardcodeados) vía `CREATE OR REPLACE`. No se genera el artefacto de revert ahora (no solicitado); si lo necesitás, lo preparo con el mismo patrón (gate + `CREATE OR REPLACE`, baseline como objetivo). La verificación B sirve para confirmar el revert (fingerprint vuelve a `f8d6bbf5…`).
- **No usar `DROP`** sobre la función: `vista_disponibilidad` depende de ella.

---

## 5. Criterio de cierre del bloque (en TEST)

El bloque queda **verde en TEST** cuando:
- A aplicado con `todo_ok = true` (✅ hecho).
- C con `VEREDICTO FINAL = TODOS VERDES` y residuos=0 (⬜ pendiente de tu corrida).

Con eso, el bloque de integración en lectura está **cerrado en TEST**. El **cierre formal** (documento de cierre + `D-*`/`L-*` + propagación a satélites) se hace **al cerrar el frente completo de horarios**, no ahora.

---

## 6. Diferidos del frente (fuera de este bloque)

- **Canonización + promoción coordinada a OPS** de todo el motor de horarios (guard B2 + resolver + integración B3 en `crear_prereserva` + wrapper A07 + **esta integración**), con **un solo bump** sobre v1.10.0 y el gate anti-OPS adaptado (marcador OPS, fingerprint parity). El fingerprint del motor en `obtener_disponibilidad_rango` OPS deberá coincidir con el TEST post-promoción.
- **Requisito obligatorio — guard de alta de overrides** (`HORARIOS_REQUISITO_GUARD_ALTA_OVERRIDES_PENDIENTE.md`): impedir cargar overrides horarios sobre días con reservas/pre-reservas comprometidas; con **función de alta segura y/o trigger en DB** (un `INSERT` directo que viole la regla debe fallar en la DB). Bloque futuro propio.
- **Organización de bitácora:** decidir si la carpeta `Actualizacion_motor_de_horarios/` se mueve a `Docs/Bitacora/` (consistencia con Cuenta Corriente y Carril C) ahora o en el cierre del frente.
