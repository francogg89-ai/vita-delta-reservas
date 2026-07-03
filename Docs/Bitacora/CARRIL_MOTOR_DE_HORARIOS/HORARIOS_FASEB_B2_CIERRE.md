# HORARIOS_FASEB_B2 — Cierre técnico (TEST)

**Sub-frente:** Motor formal de horarios — `resolver_horario()` standalone (base / patrón domingo / overrides_operativos).
**Estado:** Bloque 2 aplicado y validado en TEST. **Cierre preliminar:** sin acuñar `D-*`/`L-*`, sin propagar satélites, sin modificar el canónico.
**Entorno:** TEST.
**Artefactos:** `HORARIOS_FASEB_B2_RESOLVER_HORARIO_TEST.sql`, `HORARIOS_FASEB_B2_RUNSHEET.md`.
**Validado:** 2026-06-29 (AR). Pre-validado contra PostgreSQL 16 local (11/11) y confirmado idéntico en TEST.

---

## 1. Veredicto

🟢 **VERDE.** `resolver_horario()` existe y resuelve correctamente check-in/check-out para (cabaña, fecha) siguiendo la precedencia base → patrón domingo → override global → override por cabaña, con HARD ante override inválido y desempate determinístico. Función **pura** (sin writes), **aditiva** (nadie la llama todavía). Primer ladrillo del motor formal de horarios en pie.

## 2. Qué cambió

- **Nueva función** `resolver_horario(bigint, date) → jsonb`, `LANGUAGE plpgsql`, `STABLE`, `SECURITY INVOKER`.
- Lee `configuracion_general` y `overrides_operativos`; **no escribe** (ni `log_cambios`).
- **HARD en 3 etapas** sobre el override ganador: `formato_invalido` (regex estricta `^\d{2}:\d{2}(:\d{2})?$`) → `cast_invalido` (`::TIME`) → `fuera_de_ventana` (`[07:00, 22:00]`). Sin fallback silencioso.
- **Desempate determinístico:** `(id_cabana IS NOT NULL) DESC, created_at DESC, id_override DESC`.
- **`fecha_hasta` inclusiva** en overrides (distinto del modelo `[fecha_in, fecha_out)` de reservas, que no se toca).
- Hardening espejo Bloque 23 (`REVOKE EXECUTE FROM PUBLIC, anon, authenticated, service_role`) + `COMMENT`.

## 3. Evidencia

- **Paso 1:** SQL aplicado (`Success. No rows returned`). DDL puro, cero writes de datos.
- **2.A:** `definer=false` (INVOKER), `volat='s'` (STABLE), `acl_cerrado=true`.
- **2.B (read-only):** base lunes `13:00/10:00` base ; domingo `18:00/16:00` patron_domingo ; fechas distintas → check-in domingo `18:00`, check-out lunes `10:00`.
- **2.C (fixtures, con `ROLLBACK`):** global `16:00 override_global` ; cabaña gana a global (`17:00 override_cabana` / `16:00 override_global`) ; empate → mayor `id_override` (`12:00`) ; `25:99 → cast_invalido` ; `23:30 → fuera_de_ventana` ; rango inclusivo (`08-14` aplica, `08-16` vuelve a patrón domingo) ; `7:00 → formato_invalido` ; post-rollback `overrides_filas=0`.
- Los 11 casos coinciden con lo pre-validado en PG16.

## 4. Qué NO se tocó

- **Integración:** `crear_prereserva` y `obtener_disponibilidad_rango` **no** se tocaron (la función es standalone; nadie la llama).
- **Funciones existentes:** intactas (fingerprints sin cambios).
- **EXCLUDE, modelo `[fecha_in, fecha_out)`, A07/A08, gateway, frontend:** sin tocar.
- **OPS, canónico:** sin tocar. Sin `D-*`/`L-*`.

## 5. Rollback

`DROP FUNCTION public.resolver_horario(bigint, date);`
No hay datos que revertir (función pura, no escribió nada). Tras el `ROLLBACK` de 2.C, `overrides_operativos` quedó en 0 filas; solo la secuencia `id_override` quedó avanzada (inocuo).

## 6. Riesgos residuales

- **Inerte por diseño:** la función existe pero **no aporta valor hasta integrarla**. Impacto operativo actual = cero (esto es deliberado, pero el valor llega recién con la integración).
- **La integración en `crear_prereserva` es write-crítica** — el punto sensible que viene. Se mitiga con el rigor de B2 (fingerprint antes/después, diff probado, smokes). Además requerirá mapear el código `override_hora_invalido` en el wrapper A07 (como los códigos del guard).
- **HARD en escritura bloquea al cliente por dato de admin** (intencional). En el bloque de integración conviene log `nivel='error'` + mensaje útil al operador; para web pública futura, traducir a genérico.
- **Política de lectura ante override corrupto** (para `obtener_disponibilidad_rango`) queda por definir cuando se diseñe esa integración: el resolver solo **reporta** `{ok:false}`, el caller de lectura pondrá su política (no romper toda la vista).
- **Solo vive en TEST:** canonización + promoción a OPS es paquete futuro coordinado (idealmente junto con el guard B2+B3).
- **`overrides_operativos` sin UNIQUE/EXCLUDE:** solapamientos resueltos por orden determinístico, no por constraint (consciente, sin sobrediseñar).

## 7. Próximo paso recomendado

El **bloque de integración**: cablear `resolver_horario()` en `crear_prereserva` — reemplazar las dos `CASE` (`v_hora_checkin_min ← resolver(cab, fecha_in).hora_checkin`; `v_hora_checkout_max ← resolver(cab, fecha_out).hora_checkout`), manejar el `{ok:false}` propagando HARD, y **dejar el margen (`max_cliente`/`min_cliente`) y la validación de hora solicitada igual**. Con rigor B2: fingerprint de `crear_prereserva` antes/después, diff probado por builder, smokes (incluyendo un override válido que cambie la base y uno inválido que dispare el HARD). `obtener_disponibilidad_rango` queda como integración **posterior y opcional** (saldaría además la deuda de hardcode).

Ese es el paso que convierte el motor de "existe" a "manda". Recomiendo abrirlo en modo relevamiento/diseño (leer el cuerpo exacto de `crear_prereserva`, mapear los anchors de reemplazo) antes de generar artefactos.

---

**Cierre técnico Fase B / Bloque 2:** completo en TEST. `resolver_horario()` standalone, puro, validado (11/11). Integración = próximo bloque. Canonización + OPS = paquete futuro.
