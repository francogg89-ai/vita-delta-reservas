# 7D_CIERRE — Limpieza/reset del entorno TEST

**Etapa:** 7D — Diseño y ejecución del bloque de limpieza/reset de TEST.
**Estado:** ✅ Cerrada.
**Fecha de cierre:** 2026-05-28.
**Ámbito:** exclusivamente entorno TEST (`vita-delta-test`). DEV, OPS y PROD no
fueron tocados.
**Schema canónico:** `6B_SCHEMA_SQL.md v1.7.3` — **no modificado**.
**Origen:** D-7C-01 (`DECISIONES_NO_REABRIR.md`); `Pendiente_pre_produccion.md`
sección 6.5.

---

## 1. Objetivo

Dejar TEST como **entorno limpio**: schema v1.7.3 + seed estructural + extensiones
+ funciones + vistas + triggers + cron + grants + workflows `__TEST`, **sin ningún
dato transaccional de prueba** generado durante 7B y 7C.

El objetivo no fue "volver al estado con fixtures de 7B", sino vaciar por completo
lo transaccional preservando intacta la base estructural.

---

## 2. Seed estructural preservado vs. datos transaccionales limpiados

### Matriz de clasificación de las 20 tablas reales del schema

| Clasificación | Tablas |
|---|---|
| **PRESERVAR** (11) | `cabanas`, `socios`, `configuracion_general`, `temporadas`, `tarifas`, `feriados`, `eventos_especiales`, `paquetes_evento`, `descuentos`, `plantillas_mensajes`, `cuentas_cobro` |
| **VACIAR** (6) | `huespedes`, `pre_reservas`, `reservas`, `pagos`, `bloqueos`, `log_cambios` |
| **VACIAR CONDICIONAL** (3) | `consultas`, `overrides_operativos`, `gastos` — solo si el snapshot mostraba filas de prueba |

**`DISPONIBILIDAD_CACHE` no es tabla del schema actual.** Es histórica/pre-Supabase,
reemplazada por funciones (`validar_disponibilidad`, `obtener_disponibilidad_rango`)
y la vista `vista_disponibilidad`. No figura en `public` (confirmado por el
inventario A.1).

**Resolución de las condicionales:** en el snapshot pre-reset, `consultas`,
`overrides_operativos` y `gastos` estaban en **0 filas** y sus secuencias sin uso
(`null`). No entraron al borrado ni al reset. No apareció ningún dato inesperado;
no hubo freno.

---

## 3. Decisiones bisagra aprobadas

### D-7D-01 — Reset de secuencias a 1 en las tablas vaciadas

Se aprobó resetear a 1 las secuencias de las tablas efectivamente vaciadas con
datos (`pagos`, `reservas`, `pre_reservas`, `bloqueos`, `huespedes`,
`log_cambios`), vía `ALTER SEQUENCE ... RESTART WITH 1`.

- Las secuencias del seed estructural (`cabanas`, `socios`, `temporadas`,
  `plantillas_mensajes`, `cuentas_cobro`) **no se tocaron**.
- Las secuencias de las condicionales sin uso (`consultas`, `overrides_operativos`,
  `gastos`) **no se tocaron** (seguían en `null`).
- Los nombres de secuencia no se hardcodearon: se obtuvieron de
  `pg_get_serial_sequence` en el snapshot (sección A.4) y se usaron textualmente.

### D-7D-02 — Vaciado de `log_cambios` con evidencia documentada

Se aprobó vaciar `log_cambios`. La evidencia de auditoría de 7B/7C **no se archivó
en una tabla dentro de TEST**; quedó documentada en este cierre (ver sección 5).

---

## 4. Método de ejecución

- **`DELETE` explícito** en orden seguro por foreign keys. Sin `DROP ... CASCADE`,
  sin `TRUNCATE`, sin `TRUNCATE ... CASCADE`.
- **Transacción única atómica** (`BEGIN`/`COMMIT`): cualquier error revertía el
  conjunto completo, dejando TEST sin cambios.
- **Doble gate anti-error-de-entorno:** preflight read-only previo (sección A.0) +
  re-gate dentro de la transacción (bloque `DO $$ ... RAISE EXCEPTION`) verificando
  la identidad exacta de las 5 cabañas TEST (IDs 1–5, nombres Bamboo / Madre Selva
  / Arrebol / Guatemala / Tokio). Si la identidad no coincidía, la transacción
  abortaba.

### Orden de borrado (fundamentado en las FKs de `6B_SCHEMA_SQL.md` §6)

`pagos` → `reservas` → `pre_reservas` → `bloqueos` → `huespedes` → `log_cambios`.

Razones:
- `pagos.id_prereserva` → `pre_reservas` con `ON DELETE RESTRICT` ⇒ pagos primero.
- `pre_reservas.id_huesped` y `reservas.id_huesped` → `huespedes` con
  `ON DELETE RESTRICT` ⇒ huespedes al final.
- `bloqueos` y `log_cambios` independientes (bloqueos solo referencia `cabanas`,
  que se preserva; `log_cambios` sin FK).

---

## 5. Snapshot de `log_cambios` antes del vaciado (evidencia)

Estado capturado en el snapshot pre-reset (Bloque A, sección A.5):

- **Total:** 18 filas.
- **Rango temporal:** `2026-05-28 18:00:09.715426+00` →
  `2026-05-28 22:30:00.016324+00` (columna `fecha_hora`, no `created_at` — L-7C-06).

**Por `tabla_afectada`:**

| tabla_afectada | filas |
|---|---|
| `pre_reservas` | 11 |
| `pagos` | 4 |
| `bloqueos` | 2 |
| `reservas` | 1 |

**Por `source_event`:**

| source_event | filas |
|---|---|
| `n8n_test_w03_registrar_pago_manual` | 5 |
| `n8n_test_w02_crear_prereserva_manual` | 4 |
| `n8n_test_w04_confirmar_reserva_manual` | 3 |
| `cron_expirar_prereservas` | 2 |
| `n8n_test_w05_cancelar_prereserva_manual` | 2 |
| `n8n_test_w06_crear_bloqueo_manual` | 2 |

Todos los registros son trazables como actividad de prueba de 7B/7C
(`n8n_test_w0X_*` + el cron de expiración). Ninguno es dato real ni de seed.

---

## 6. Estado pre-reset (línea base del snapshot)

### Transaccionales (A.2 / A.3)

| Tabla | Filas | MAX(id) |
|---|---|---|
| `pagos` | 3 | 3 |
| `reservas` | 1 | 1 |
| `pre_reservas` | 4 | 4 |
| `bloqueos` | 2 | 2 |
| `huespedes` | 5 | 5 |
| `log_cambios` | 18 | 18 |
| `consultas` | 0 | null |
| `overrides_operativos` | 0 | null |
| `gastos` | 0 | null |

Coincide exactamente con lo documentado en `7C_CIERRE.md` §9.

### Seed estructural (A.6)

| Tabla | Filas |
|---|---|
| `cabanas` | 5 |
| `configuracion_general` | 10 |
| `cuentas_cobro` | 1 |
| `descuentos` | 0 |
| `eventos_especiales` | 0 |
| `feriados` | 0 |
| `paquetes_evento` | 0 |
| `plantillas_mensajes` | 1 |
| `socios` | 3 |
| `tarifas` | 0 |
| `temporadas` | 1 |

### Cron (A.7)

2 jobs activos: `expirar_prereservas_vencidas()` (`*/5 * * * *`) y limpieza mensual
de `cron.job_run_details` (`0 3 1 * *`).

---

## 7. Verificación post-reset (Bloque C)

| Verificación | Esperado | Obtenido | OK |
|---|---|---|---|
| C.1 — transaccionales en 0 | las 9 en 0 | las 9 en 0 | ✅ |
| C.2 — seed intacto | idéntico a A.6 | idéntico a A.6 | ✅ |
| Secuencias vaciadas (consulta directa) | `last_value=1`, `is_called=false` | `last_value=1`, `is_called=false` en las 6 | ✅ |
| C.3 — secuencias seed sin cambios | `cabanas` 5, `socios` 3, `temporadas` 1, `plantillas_mensajes` 1, `cuentas_cobro` 1 | idénticas a A.4-bis | ✅ |
| C.4 — cron intacto | 2 jobs activos iguales a A.7 | 2 jobs activos iguales a A.7 | ✅ |
| C.5 — vistas operativas ejecutan | sin error | `vista_disponibilidad` 600, resto 0 | ✅ |

**Notas de lectura:**
- Las 6 secuencias reseteadas figuran como `last_value=null` en `pg_sequences`
  (C.3): es la contracara de `is_called=false` en esa vista, confirmada por la
  consulta directa a cada secuencia (`last_value=1`, `is_called=false` → próximo
  id = 1). No es discrepancia.
- `vista_disponibilidad` devuelve 600 filas porque deriva del seed estructural
  (cabañas × horizonte de fechas), no de datos transaccionales. Correcto.
- Las otras tres vistas en 0 es lo esperado: no hay transaccional vivo.

**Resultado:** TEST quedó como entorno limpio. Objetivo de 7D cumplido.

---

## 8. Verificación manual (lado n8n, no SQL)

- [x] Confirmado que los 8 workflows `__TEST` siguen usando la credencial
  `vita_supabase_test` y apuntando al proyecto TEST (verificado por Franco,
  2026-05-28). La limpieza de 7D no tocó workflows ni credenciales.

---

## 9. Decisiones registradas en 7D

- **D-7D-01** — Reset de secuencias a 1 en las 6 tablas vaciadas con datos;
  secuencias de seed y de condicionales sin uso intactas.
- **D-7D-02** — Vaciado de `log_cambios` con evidencia documentada en este cierre,
  sin tabla archivo dentro de TEST.

Ambas se incorporan a `DECISIONES_NO_REABRIR.md`.

---

## 10. Lo que 7D NO es / NO hizo

- **No tocó DEV, OPS ni PROD.** Solo TEST.
- **No modificó** schema, funciones, vistas, triggers, enums, constraints, grants
  ni `6B_SCHEMA_SQL.md v1.7.3`.
- **No borró** seed estructural ni workflows n8n.
- **No usó** `DROP ... CASCADE` ni `TRUNCATE`.
- **No conectó** consumidores reales (webhook MP, bot, frontend).
- **No reseteó** secuencias del seed estructural.

---

## 11. Pendientes tras 7D

7D cierra el pendiente 6.5 de `Pendiente_pre_produccion.md`. Permanecen abiertos
los heredados, sin cambios:

- Endurecimiento de permisos en DEV (paridad con TEST) — `Pendiente_pre_produccion.md` 1.5.
- `tipo_valor` sin poblar en `configuracion_general` — 1.4.
- Validación de tipos inválidos no-vacíos (heredado de 6D).
- Cobertura empírica opcional de `unique_violation` — 6.3.
- RLS, tarifas productivas, feriados productivos (pendientes históricos).

---

## 12. Próximo paso recomendado

Con TEST reseteado a entorno limpio, las opciones disponibles a priorizar por
Franco (no comprometidas en este cierre):

1. **Endurecimiento de permisos en DEV** (paridad con TEST).
2. **Diseño del entorno OPS.**
3. **Consumidores reales sobre TEST** (webhook MP, bot, frontend), con decisión
   explícita y sobre TEST primero.

No avanzar a OPS/PROD, MercadoPago real, bot o frontend sin decisión explícita.

---

_Cierre formal de Etapa 7D — 2026-05-28._
