# Requisito obligatorio diferido — Guard de alta de overrides horarios vs. reservas/pre-reservas comprometidas

**Frente:** Motor formal de horarios.
**Tipo:** 🔒 **Requisito obligatorio** + **bloque futuro** (diseño de alta segura / barrera en DB).
**Estado:** 📌 **REGISTRADO. NO implementado.** No forma parte del bloque de integración en `obtener_disponibilidad_rango` (A+B). Sin `D-*`/`L-*` (se acuñarán en el cierre del bloque que lo implemente).
**Fecha de registro:** 2026-07-02 (AR).

---

## 1. Contexto y motivación

La integración de `resolver_horario()` en `obtener_disponibilidad_rango` (bloque actual, **lectura**) hace que la disponibilidad **respete** `overrides_operativos`. Pero **nada** valida hoy la **carga** de un override contra reservas/pre-reservas ya existentes.

**Riesgo:** cargar un override horario (global o por cabaña) sobre un día/rango en el que ya hay **reserva o pre-reserva con check-in/check-out comprometido** **pisa un horario ya comunicado o comprometido** con el huésped. Esto debe **rechazarse en el alta**, no descubrirse después.

Este requisito es sobre la **escritura** de overrides; es independiente del bloque de lectura actual, pero es parte del mismo frente de horarios.

---

## 2. Regla obligatoria

**No se puede permitir crear/cargar un override horario — global o por cabaña — si alguna cabaña afectada ya tiene una reserva o pre-reserva con check-in o check-out comprometido en ese día/rango.**

Cobertura exigida:

- **Alcance por tipo de override:**
  - **Override global (`id_cabana IS NULL`):** validar **todas las cabañas activas** afectadas por el rango.
  - **Override por cabaña (`id_cabana = X`):** validar **solo esa cabaña**.
- **Aplica a `tipo_override IN ('hora_checkin','hora_checkout')`.** (Otros tipos de override, si los hubiera, quedan fuera de esta regla salvo que se especifique.)
- **Condición de rechazo:** existe, en alguna cabaña afectada, **reserva activa/confirmada/completada** o **pre-reserva vigente/en revisión** con `fecha_checkin`, `fecha_checkout`, `fecha_in` o `fecha_out` **dentro del rango afectado**, según corresponda al borde que el override modifica.
  - Un override de `hora_checkin` compromete los **check-in** (`reservas.fecha_checkin`, `pre_reservas.fecha_in`) que caigan en el rango.
  - Un override de `hora_checkout` compromete los **check-out** (`reservas.fecha_checkout`, `pre_reservas.fecha_out`) que caigan en el rango.
  - Estados a considerar: reservas en `('confirmada','activa','completada')`; pre-reservas en `pendiente_pago` **vigente** (`expira_en > NOW()`) o `pago_en_revision`. (A afinar en el diseño del bloque, alineado con los estados que ya usa `obtener_disponibilidad_rango` / `crear_prereserva`.)
- **Rango afectado:** el `[fecha_desde, fecha_hasta]` del override, recordando que en `overrides_operativos` **`fecha_hasta` es inclusiva** (distinto del modelo `[fecha_in, fecha_out)` de reservas). El diseño debe mapear con cuidado inclusividad vs. semántica media-abierta al comparar contra `fecha_checkin`/`fecha_checkout`/`fecha_in`/`fecha_out`.

**Objetivo:** evitar pisar horarios ya comunicados o comprometidos con huéspedes.

---

## 3. Punto crítico — la validación no puede vivir solo en n8n

**Para proteger contra carga manual directa, no alcanza con validar en el wrapper n8n.** Un `INSERT` directo sobre `overrides_operativos` (desde el SQL Editor, un script, o cualquier vía que no pase por n8n) **saltearía** la validación.

El bloque futuro debe diseñar **al menos uno** (idealmente ambos, en capas):

1. **Función de alta segura** (p. ej. `crear_override_horario(jsonb)` / `registrar_override(...)`) que encapsule la validación y sea el **único** camino sancionado para cargar overrides, con hardening de ACL (owner/rol, espejo Bloque 23).
2. **Barrera en DB** que impida el bypass por `INSERT` directo: un **trigger `BEFORE INSERT/UPDATE`** sobre `overrides_operativos` que ejecute la validación y haga `RAISE EXCEPTION` si se viola la regla. (Es la defensa que no se puede saltear desde el SQL Editor.)

**Criterio de aceptación del bloque futuro:** un `INSERT` directo que viole la regla debe **fallar en la DB**, no solo en n8n.

---

## 4. Relación con el bloque actual (A+B) y con B3

- **No se implementa en A+B.** A+B solo integran el resolver en la **lectura** (`obtener_disponibilidad_rango`), con política D1. No tocan el alta de overrides.
- **Coherencia con B3:** `crear_prereserva` (B3) ya rechaza (HARD) crear una pre-reserva cuando el resolver da override corrupto. Esta regla es el **espejo en el sentido inverso**: impedir que un override (aunque sea *válido* de formato) **pise** una reserva/pre-reserva **ya existente**. Son protecciones complementarias en bordes distintos del ciclo.
- **Interacción con D1 (lectura):** mientras esta guard no exista, un override cargado sobre un día ya reservado se reflejaría en la lectura (o lo NULLearía si es corrupto), pero el problema de negocio —pisar un horario comprometido— seguiría latente en el alta. Esta guard lo cierra en origen.

---

## 5. Estado de formalización

Requisito registrado, **no** implementado. Se convertirá en un bloque de diseño→artefactos→ejecución propio (con su gate anti-OPS, validación pglast + harness, smokes y cierre). Los `D-*`/`L-*` correspondientes se acuñarán en **ese** cierre, no ahora. Entra al backlog del frente de horarios junto con: canonización del motor y promoción coordinada a OPS.
