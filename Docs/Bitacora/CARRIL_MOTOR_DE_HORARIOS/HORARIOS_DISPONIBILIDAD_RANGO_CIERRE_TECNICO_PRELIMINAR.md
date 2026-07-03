# Cierre técnico preliminar — Integración de `resolver_horario()` en `obtener_disponibilidad_rango` (TEST)

**Frente:** Motor formal de horarios — bloque de integración en la función de **lectura** que alimenta el calendario del frontend (vía wrapper n8n A26).
**Entorno:** TEST (ref `bdskhhbmcksskkzqkcdp`).
**Estado:** ✅ **Cerrado técnicamente en TEST.** Cierre **preliminar** — **sin** promoción a OPS, **sin** canonización, **sin** acuñar `D-*`/`L-*`.
**Repo de referencia:** commit `aca90143` (canónico v1.10.0; el commit es "ajustando el motor contable", de otro frente, no afecta horarios).
**Fecha:** 2026-07-03 (AR).

---

## 1. Resumen

Se integró `resolver_horario()` dentro de `obtener_disponibilidad_rango(date,date,bigint)` en TEST, aplicando la política **D1**. La función de lectura pasa a **respetar `overrides_operativos` válidos** y a **fail-closed en horas** (NULL) ante override corrupto, preservando el `estado` ocupacional. A+B aplicados y verdes; C rev2 corrido con **16/16 PASS**. No se tocó nada fuera de TEST.

---

## 2. Alcance y no-alcance

**Se tocó (solo TEST):** la definición de `obtener_disponibilidad_rango` en el entorno TEST, vía `CREATE OR REPLACE` (owner-only, sin `DROP`, para preservar ACL y la dependiente `vista_disponibilidad`).

**Intacto (verificado / no tocado):**

| Componente | Estado |
|---|---|
| **OPS** (ref `lpiatqztudxiwdlcoasv`) | Intacto — no se generó ni ejecutó ningún artefacto contra OPS |
| **Canónico** `6B_SCHEMA_SQL.md` (v1.10.0) | Intacto — `resolver_horario` aparece **0 veces** en el canónico; la ODR canónica conserva los `CASE` hardcodeados |
| **Gateway** `portal-api` | Intacto — sin cambios |
| **Frontend** (contrato + `CalendarioRango.tsx`) | Intacto — el frontend consume solo `estado`; D1 no exige cambios |
| **Workflows n8n** (A26 y demás) | Intacto — sin cambios |
| **A07 / A08** (guards UX del motor temporal) | Intacto — fuera de este bloque |
| **`crear_prereserva`** (integración B3) | Intacto — fuera de este bloque |
| **`resolver_horario`** (dependencia) | Intacto — fingerprint sin cambios |

---

## 3. Artefactos del bloque

| Archivo | Rol |
|---|---|
| `HORARIOS_DISPONIBILIDAD_RANGO_RELEVAMIENTO.md` | Relevamiento + diseño (opciones, D1, riesgos) |
| `HORARIOS_DISPONIBILIDAD_RANGO_PASO0_LIVE_TEST.sql` | Verificación live + fingerprints baseline |
| `HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql` | `CREATE OR REPLACE` + gate anti-OPS/baseline |
| `HORARIOS_DISPONIBILIDAD_RANGO_B_VERIFICACION_TEST.sql` | Verificación PRE/POST (read-only) |
| `HORARIOS_DISPONIBILIDAD_RANGO_C_SMOKES_TEST.sql` (rev 2) | Smokes (12 casos) — gate + writes controlados en tx + teardown |
| `HORARIOS_DISPONIBILIDAD_RANGO_D_RUNSHEET.md` | Runsheet de ejecución |
| `HORARIOS_REQUISITO_GUARD_ALTA_OVERRIDES_PENDIENTE.md` | Requisito obligatorio diferido (bloque futuro) |

---

## 4. Estado de ejecución

- **Paso 0 (live):** ✅ entorno TEST, ambas funciones presentes, def live ≡ canónico salvo comentarios/EOL (cero drift lógico), fingerprints capturados.
- **Paso A (integración):** ✅ aplicado con `todo_ok = true`. Gate embebido validó ambiente/schema/existencia/fingerprints antes del `CREATE OR REPLACE`.
- **Paso B (verificación):** ✅ ACL/owner/INVOKER/volatile preservados; firma + 9 columnas iguales; `CROSS JOIN LATERAL` presente; `CASE` viejos ausentes; extracción D1 presente; `vista_disponibilidad` ejecuta; modos cabaña-concreta y `NULL` correctos.
- **Paso C (smokes rev 2):** ✅ **16/16 PASS**, `VEREDICTO FINAL = TODOS VERDES`. Incluye gate anti-OPS (fila `-1`), los 12 casos, TEARDOWN y POSTCHECK.

---

## 5. Fingerprints (`md5(pg_get_functiondef(...))`)

| Objeto | Fingerprint | Nota |
|---|---|---|
| ODR baseline (pre-A) | `f8d6bbf533c775349642e7ed34d5ea8c` | punto de partida del delta |
| **ODR post-A (nuevo baseline del motor)** | **`37009a32154f93b80520500c0f15b46b`** | motor integrado en TEST |
| **Resolver (dependencia)** | **`759662b4afaed7af426917aa3717b34c`** | **intacto** (sin cambios) |

---

## 6. Política D1 (aplicada)

Ante `resolver_horario()` con `ok=false` (override horario corrupto: `formato_invalido` / `cast_invalido` / `fuera_de_ventana`), la ODR pone **ambas** horas (`hora_checkin_base`, `hora_checkout_base`) → **NULL** por fila, **preservando el `estado` ocupacional** (all-or-nothing por fila; espejo del over-blocking de B3 en el lado de escritura).

**Matiz explícito (no es "no miente" a secas):** D1 preserva la disponibilidad **ocupacional**, pero **no** garantiza reservabilidad **horaria**. Un día libre con override corrupto sale `estado='disponible'` con horas `NULL`; como el frontend hoy ignora las horas, lo pinta disponible aunque `crear_prereserva` lo rechace por el mismo override. Es una **incoherencia residual en la capa de presentación**, cuyo cierre queda como trabajo futuro (fuera de este bloque). D1 fue elegida porque no requiere cambios de frontend y es consistente con la política de B3.

---

## 7. Cambio funcional aprobado

La ODR **ahora respeta `overrides_operativos` válidos** (precedencia cabaña > global, `created_at` DESC; `fecha_hasta` inclusiva). Antes ignoraba los overrides con `CASE` hardcodeados, lo que generaba divergencia latente con `crear_prereserva` desde B3. Este cambio alinea la lectura con la escritura. Aprobado por Franco previo a la generación de artefactos.

---

## 8. No-regresión comprobada

- **Estados:** comparación NUEVA vs VIEJA (oracle `pg_temp._smoke_odr_vieja`) sobre 120 días de datos reales → **0 diferencias** en `estado` (los estados no dependen de overrides).
- **Semántica `[fecha_in, fecha_out)` + `checkout_disponible`:** columnas no-horas idénticas NUEVA vs VIEJA; y bloqueo media-abierta determinista `[j, j+2)` verificado (`j` y `j+1` bloqueadas, `j+2` libre).
- **Firma/columnas:** args + result idénticos al baseline.

---

## 9. Performance real (TEST)

| Escenario | Tiempo real | Umbral | Resultado |
|---|---|---|---|
| 45 noches / 1 cabaña (rango típico A26) | **13.4 ms** | < 5000 ms | ✅ holgado |
| 365 noches / 1 cabaña (rango grande ~366) | **104.7 ms** | < 30000 ms | ✅ holgado |

El `CROSS JOIN LATERAL` que invoca el resolver por fila no introduce costo problemático en TEST. No se requiere optimización.

---

## 10. Cero residuos

Post-`COMMIT` de C rev2: `overrides` marcados = **0**, `bloqueos` marcados = **0**, oracle `pg_temp._smoke_odr_vieja` **eliminado**, ODR real intacta. Mecanismo: el fixture se borra en el TEARDOWN antes del `COMMIT` (se persiste solo la limpieza); si el script abortara antes del teardown, la transacción revierte y nada persiste. Gate negativo verificado: fingerprint no coincidente → `RAISE EXCEPTION` sin sembrar fixture.

---

## 11. Requisito obligatorio diferido registrado

**Guard de alta segura de overrides horarios contra reservas/pre-reservas comprometidas** (`HORARIOS_REQUISITO_GUARD_ALTA_OVERRIDES_PENDIENTE.md`): impedir crear/cargar un override horario (global → todas las cabañas activas; por cabaña → solo esa; `tipo_override IN ('hora_checkin','hora_checkout')`) si alguna cabaña afectada ya tiene reserva activa/confirmada/completada o pre-reserva vigente/en revisión con check-in/check-out en el rango. **Punto crítico:** n8n no alcanza; el bloque futuro debe diseñar una **función de alta segura y/o un trigger en DB** (criterio de aceptación: un `INSERT` directo que viole la regla debe **fallar en la DB**). Registrado como bloque futuro, **no** implementado.

---

## 12. Formalización

**Sin `D-*`/`L-*` acuñados.** Se mantiene el criterio de reservar la acuñación (y la propagación a satélites) para el **cierre formal del frente completo de horarios**. Este documento es un cierre **técnico preliminar** del bloque en TEST.

---

## 13. Diferidos del frente (NO en este bloque)

- **Promoción a OPS** — **no** generar todavía. Cuando se abra: coordinada con el resto del motor (guard B2 + resolver + integración B3 en `crear_prereserva` + wrapper A07 + esta integración), gate anti-OPS adaptado, y parity de fingerprint del motor.
- **Canonización** — **no** todavía. Un solo bump sobre v1.10.0 al cerrar el frente completo, cubriendo todos los cambios del motor de horarios.
- **Guard de alta de overrides** (requisito §11) — bloque futuro propio.
- **Organización de bitácora** — decidir si `Actualizacion_motor_de_horarios/` se mueve a `Docs/Bitacora/` (consistencia con Cuenta Corriente y Carril C).

---

## 14. Próximo paso

El bloque está **cerrado técnicamente en TEST**. No se avanza a OPS ni canónico. El siguiente movimiento del frente lo decidís vos: abrir otro bloque del motor de horarios, o preparar el cierre formal del frente completo (con acuñación de `D-*`/`L-*` y promoción coordinada).
