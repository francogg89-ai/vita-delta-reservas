# HORARIOS_B2 — Cierre técnico (TEST)

**Frente:** Motor formal de horarios — sub-frente guard temporal de creación.
**Estado:** B2 validado técnicamente en TEST. **Cierre preliminar:** sin acuñar `D-*`/`L-*`, sin propagar satélites, sin modificar el canónico.
**Entorno:** TEST (ref `bdskhhbmcksskkzqkcdp`).
**Artefactos:** `HORARIOS_B2_GUARD_HELPER_TEST.sql`, `HORARIOS_B2_RUNSHEET.md`.
**Validado:** 2026-06-29 (AR).
**Nomenclatura `HORARIOS_B2_*`:** provisional; el prefijo definitivo se acuña en el cierre formal del frente.

---

## 1. Veredicto

🟢 **VERDE.** El helper `fecha_hoy_ar()` y el guard temporal quedaron aplicados y validados en TEST. El backend bloquea de forma determinística la creación con fecha pasada en zona Argentina, **sin** tocar el modelo `[fecha_in, fecha_out)` ni el EXCLUDE, **sin** romper los caminos normales de A07/A08, y con los errores nuevos pasando **controlados** (no `estado_incierto`).

## 2. Qué cambió en TEST

- **Nueva función `fecha_hoy_ar()`** — `LANGUAGE sql`, `STABLE`, `SECURITY INVOKER`, cuerpo `(NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date`. Hardening: `REVOKE EXECUTE … FROM PUBLIC, anon, authenticated, service_role` (solo owner ejecuta). Con `COMMENT`.
- **`crear_prereserva(jsonb)`** — agregado `IF v_fecha_in < fecha_hoy_ar()` → error `fecha_in_pasada` (con `campo`/`minimo`/`recibido`). `CREATE OR REPLACE` (preservó grants del Bloque 23). Único delta vs canónico: el bloque `IF`.
- **`crear_bloqueo(jsonb)`** — agregado `IF v_fecha_hasta <= fecha_hoy_ar()` → error `rango_pasado` (con `campo`/`minimo`/`recibido`). `CREATE OR REPLACE`. Único delta: el bloque `IF`.

Fingerprints (`md5(pg_get_functiondef())`), antes → después:
- `crear_prereserva`: `a60d6c457b277202e1a805e6329b072e` → `f258ad9b6e4cd0f7dcb7318e5724f0ce`
- `crear_bloqueo`: `81a590ae5244dcf7b8fb434fc7b3f625` → `0391133ff2eea689bb18e65088536555`

(El cambio de huella es esperado: corresponde exactamente al bloque `IF` agregado; el resto del cuerpo es byte-idéntico al canónico, probado por diff reproducible.)

## 3. Evidencia resumida

- **Timezone (prueba central):** sesión UTC → `current_date = 2026-06-30` pero `fecha_hoy_ar = 2026-06-29`; sesión AR → ambos `2026-06-29`. El helper devuelve el día calendario argentino independiente del timezone de sesión.
- **Helper:** `es_definer = false` (INVOKER), `volatilidad = s` (STABLE), `acl_cerrado = true` (REVOKE materializó el ACL).
- **Paso 0:** `current_schema = public`, `helper_ausente = true`, `overrides_operativos = 0`, EXCLUDE baseline guardado.
- **EXCLUDE:** `constraintdef` idéntico antes/después → modelo `[fecha_in, fecha_out)` intacto.
- **Rechazos reales:** `crear_prereserva` `fecha_in=2026-06-28` → `fecha_in_pasada` (campo `fecha_in`, mínimo `2026-06-29`, recibido `2026-06-28`); `crear_bloqueo` `[2026-06-26, 2026-06-29)` → `rango_pasado` (campo `fecha_hasta`, mínimo `2026-06-29`, recibido `2026-06-29`).
- **Bordes:** pre-reserva → ayer rechaza / hoy permite / mañana permite; bloqueo → hasta-hoy rechaza / hasta-mañana permite.
- **No-regresión (sin consumo):** pre-reserva futura pasó el guard y cortó en `huesped_contacto_requerido`; bloqueo futuro pasó el guard y cortó en `motivo_invalido`. Cero secuencias, cero datos.
- **Propagación de errores (precheck 0.6, read-only):** `fecha_in_pasada`/`rango_pasado` → default del wrapper → `error_interno` (allowlisted) → el frontend ve `'error interno'`, **NO** `estado_incierto`.
- **Gold-standard destructivo:** NO ejecutado (no aporta lo suficiente y consumiría secuencias).

## 4. Qué NO se tocó

- **OPS:** intacto. Cero conexiones, cero lecturas, cero writes.
- **Canónico (`6B_SCHEMA_SQL.md v1.9.0`):** sin modificar.
- **EXCLUDE** de `reservas`/`bloqueos`: sin tocar (verificado idéntico).
- **Modelo `[fecha_in, fecha_out)`:** sin cambios.
- **Gateway `portal-api`:** sin tocar.
- **Wrappers n8n A07/A08:** sin tocar.
- **Frontend:** sin tocar (queda como defensa secundaria de UX para más adelante).
- **Override manual por reserva:** frenado (no diseñado ni implementado en B2).
- **`overrides_operativos`:** sin tocar (sigue en 0 filas; fase B futura).
- **Grants del Bloque 23:** preservados (`CREATE OR REPLACE`, no `DROP`).

## 5. Riesgo residual

- **Bajo.** El guard es puramente aditivo (diff probado): cero cambios en el camino de aceptación. El backend bloquea sin escribir, así que no hay riesgo de dato/double-booking.
- **UX (no es riesgo de datos):** hoy un alta/bloqueo con fecha pasada por el portal muestra `'error interno'` genérico en vez del motivo real. Mitigable con el Bloque 3 (punto 6).
- **Deuda preexistente NO abierta en B2** (anotada, no tocada): `obtener_disponibilidad_rango` con hora base hardcodeada; las vistas usan `CURRENT_DATE` crudo (drift UTC). El helper `fecha_hoy_ar()` permitiría saldar lo segundo más adelante.
- **TEST ↔ canónico:** el guard vive en TEST pero **no** en el canónico. Un bootstrap fresco del canónico no tendría el guard hasta su canonización (decisión posterior, fuera de B2).

## 6. Pendiente identificado: UX wrappers A07/A08 (posible Bloque 3 chico)

- **Hoy:** `router1_crear` (A07) y `router_bloqueo` (A08) mapean cualquier error no listado a `error_interno`; `fecha_in_pasada`/`rango_pasado` caen ahí.
- **Propuesta (chica, solo wrappers):** agregar `fecha_in_pasada` al `payloadInv` de A07 y `rango_pasado` al de A08 → se convierten en `payload_invalido` con mensaje específico (`'datos de reserva rechazados: fecha_in_pasada'` / `'datos de bloqueo rechazados: rango_pasado'`), que el gateway conserva.
- **Gateway:** NO requiere cambios (`payload_invalido` ya está en `CODIGOS_ERROR_PERMITIDOS`).
- **Alcance:** solo los 2 templates de wrapper. No toca SQL, gateway, canónico ni OPS.

## 7. Confirmación

- **OPS no fue tocado** en ningún momento del Bloque 2: cero conexiones, cero lecturas, cero writes a OPS.
- **El canónico no se modifica todavía:** el guard + helper viven solo en TEST. La canonización (bump del canónico) es una decisión posterior, fuera del alcance de B2.

---

**Cierre técnico B2:** completo en TEST. **Próximo paso a decidir:** Bloque 3 (UX wrappers A07/A08) **o** retomar override manual / motor de horarios (fase B). El cierre formal del frente (con acuñación de `D-*`/`L-*` y propagación de satélites) queda para cuando el frente alcance su hito de cierre.
