# HORARIOS_FASEB_B3 — Cierre técnico (TEST)

**Sub-frente:** Motor formal de horarios — integración de `resolver_horario()` en `crear_prereserva`.
**Estado:** Bloque 3 aplicado y validado en TEST. **Cierre preliminar:** sin acuñar `D-*`/`L-*`, sin propagar satélites, sin modificar el canónico.
**Entorno:** TEST (ref `bdskhhbmcksskkzqkcdp`).
**Artefactos:** `HORARIOS_FASEB_B3_INTEGRACION_CREAR_PRERESERVA_TEST.sql` (v3), `HORARIOS_FASEB_B3_VERIFICACION_TEST.sql` (v3), `HORARIOS_FASEB_B3_SMOKES_TEST.sql` (v5), `HORARIOS_FASEB_B3_RUNSHEET.md` (v3).
**Validado:** 2026-07-01 (AR).
**Fingerprint `crear_prereserva` (TEST):** baseline `f258ad9b6e4cd0f7dcb7318e5724f0ce` → **after `d92a438eb4f11decac981cc65f2a5e53`**.

---

## 1. Veredicto

🟢 **VERDE.** El motor de horarios pasa de "existe" a "manda" en `crear_prereserva` (TEST). La base de check-in/check-out ahora sale de `resolver_horario()` en vez de las dos `CASE` hardcodeadas; un override inválido corta como **HARD puro antes de consumir `id_huesped`/`id_pre_reserva`**, con error enriquecido (`borde` + `fecha_resolver`); y todo lo demás quedó intacto. 18/18 smokes, residuales en cero, ACL preservada sin `GRANT`.

## 2. Qué cambió

Cambio **puramente aditivo/quirúrgico** sobre `crear_prereserva` vía `CREATE OR REPLACE` (no `DROP`: preserva ACL del Bloque 23, `COMMENT` y ownership — precedente B2). Cuatro deltas de cuerpo + firma calificada:

- **D1 — DECLARE:** `+v_res_in`, `+v_res_out` (`JSONB`).
- **D2 — Bloque 3.5 (nuevo):** dos llamadas `resolver_horario(v_id_cabana, v_fecha_in)` y `(…, v_fecha_out)`, chequeo **fail-closed** (`COALESCE((…->>'ok')::BOOLEAN,false) IS NOT TRUE`) y `RETURN` enriquecido con `borde`/`fecha_resolver`. Ubicado **después del pre-check de idempotencia (bloque 3) y antes de `upsert_huesped` (bloque 4)** — el único punto que corta el HARD sin consumir secuencias.
- **D3 — base check-in:** `v_hora_checkin_min := (v_res_in->>'hora_checkin')::TIME` (reemplaza la `CASE` 18:00/13:00).
- **D4 — base check-out:** `v_hora_checkout_max := (v_res_out->>'hora_checkout')::TIME` (reemplaza la `CASE` 16:00/10:00).
- **D5 — firma calificada:** `public.crear_prereserva(payload JSONB)` (sin ambigüedad de `search_path`).

**Gate anti-OPS embebido** (en `BEGIN…COMMIT`): valida `ambiente='test'` + `current_schema()='public'` + existencia de la función + fingerprint baseline; si algo falla, `RAISE EXCEPTION` aborta la tx y el `CREATE` no corre.

## 3. Evidencia

**[PRE] Gate (antes de aplicar):**
- `fingerprint_baseline = f258ad9b6e4cd0f7dcb7318e5724f0ce`, `coincide_baseline = true`.
- `ambiente = test`, `schema_actual = public`, `gate_ok = true`.

**[POST] Post-apply:**
- **POST-1:** `fingerprint_after = d92a438eb4f11decac981cc65f2a5e53`, `difiere_del_baseline = true`.
- **POST-2:** `security_definer = false`, `owner = postgres`, ACL `{postgres=X/postgres}` (**preservada, sin `GRANT`**).
- **POST-3 estructural:** **15/15** checks en `true` (4 deltas presentes; las dos `CASE` de horario base eliminadas; bounds 22:00/07:00, guard `fecha_in_pasada` y `validar_disponibilidad` intactos).

**[SMOKES] 18/18 (un `BEGIN…ROLLBACK`, con compuerta de aserción):**
- `pass=18`, `fail=0`. `8 pre_reservas` creadas dentro de la tx y revertidas.
- POSTCHECK: `pre_reservas_residual = 0`, `overrides_residual = 0`.
- **Cobertura:** no-regresión hábil (T2) y domingo (T3) contra fórmula derivada de `configuracion_general`; override check-in global (T4) y **override check-out en `fecha_out` → `hora_checkout=12:00` (T4b, valida el 2º anchor)**; cabaña > global (T5); HARD 3 causas con `borde=fecha_in` (T6a `formato_invalido`, T6b `cast_invalido`, T6c `fuera_de_ventana`); over-blocking / tipo no consumido (T6d); precedencia sobre `cabana_no_existe` (T6e); **HARD en segunda llamada con `borde=fecha_out` (T6f)**; margen recomputado dentro (T7) y fuera (T8); guard `fecha_in_pasada` (T9); idempotencia intacta (T10); **idempotencia ganando a override corrupto** (T10b: la 2ª llamada cae en el pre-check antes del resolver → `idempotent_match`, no HARD). Los HARD (T6a–f) **gatean `_seq_pr_movio=false` y `_seq_hu_movio=false`** en el PASS.

## 4. Invariantes confirmados

- **Nuevo fingerprint TEST:** `d92a438eb4f11decac981cc65f2a5e53`.
- **ACL preservada, sin `GRANT`** (POST-2).
- **El HARD del resolver corta antes de `upsert_huesped` y antes de `INSERT INTO pre_reservas`:** garantizado por construcción (bloque 3.5 < bloque 4 < bloque 9) y verificado empíricamente (la presencia de `borde` en la respuesta ⇒ retorno en 3.5; y `_seq_pr_movio`/`_seq_hu_movio = false` gateados en los 6 HARD).
- **Intactos** (POST-3 + no-regresión + T10/T10b): bounds `max_cliente`/`min_cliente` (22:00/07:00), guard `fecha_in_pasada`, advisory locks, double-check de idempotencia, `validar_disponibilidad`, `EXCLUDE`, `INSERT`s y retorno exitoso.
- **POSTCHECK residual en cero.**

## 5. Qué NO se tocó

- `obtener_disponibilidad_rango`: **sin tocar** (integración de lectura, posterior/opcional).
- Wrappers **A07/A08**, gateway, frontend: **sin tocar**.
- **OPS**, **canónico** (`6B_SCHEMA_SQL.md`), satélites, Bootstrap kit: **sin tocar**. Sin `D-*`/`L-*`.
- Modelo `[fecha_in, fecha_out)` de reservas, `EXCLUDE`: sin tocar.

## 6. Rollback

Reaplicar el `crear_prereserva` **baseline** (fingerprint `f258ad9b…`) con `CREATE OR REPLACE` — el cuerpo baseline es el de `HORARIOS_B2_GUARD_HELPER_TEST.sql` (o el `pg_get_functiondef` guardado en el Paso 0-bis del runsheet). No hay datos que revertir: los smokes usaron `ROLLBACK` y los residuales quedaron en 0. Las secuencias `id_pre_reserva`/`id_huesped` pueden haber avanzado por los 8 éxitos revertidos (inocuo).

## 7. Decisiones de este bloque (pendientes de formalizar)

Cerradas informalmente; **se acuñarán como `D-C-XX` en el cierre formal del frente** (no ahora):

- Placement 3.5: resolver **después** del pre-check de idempotencia y **antes** de `upsert_huesped`.
- Dos llamadas: `resolver(fecha_in) → hora_checkin`, `resolver(fecha_out) → hora_checkout`.
- Chequeo **fail-closed** (`COALESCE(…::BOOLEAN,false) IS NOT TRUE`); cubre `ok` ausente (NULL→false). Un `ok` fuera de contrato haría fallar el cast, no un rebote silencioso.
- HARD puro **sin** `INSERT INTO log_cambios` (observabilidad se ve después).
- Error enriquecido con `borde` + `fecha_resolver`, preservando las 8 claves del resolver.
- **Over-blocking aceptado** (all-or-nothing del resolver: override corrupto de cualquier tipo en cualquier borde bloquea).
- **Precedencia aceptada** (3.5 corre antes de validar cabaña/disponibilidad: override corrupto gana a `cabana_no_existe`/`inactiva`/`no_disponible`).
- Firma calificada `public.`; método `CREATE OR REPLACE` (no `DROP`); no persistir `origen_*`.

## 8. Riesgos residuales

- **R1 — Fingerprint impredecible pre-apply** (depende de la tubería LF→CRLF + normalización de `pg_get_functiondef`). **Resuelto:** se midió (`d92a438e…`) y queda registrado como nuevo baseline del motor.
- **R2 — Over-blocking** (decisión aceptada): testeado (T6d).
- **R3 — Precedencia** sobre errores de cabaña/disponibilidad (decisión aceptada): testeado (T6e).
- **R4 — HARD en escritura bloquea al cliente por dato de admin** (intencional). El envelope trae detalle para el operador; para web pública futura conviene traducir a genérico. **Falta el mapeo `override_hora_invalido → payload_invalido` en A07/A08** (sub-paso posterior, no en este bloque), análogo a los códigos del guard.
- **R5 — `obtener_disponibilidad_rango`:** su política de lectura ante override corrupto sigue **por definir** (el resolver solo reporta `{ok:false}`; el caller de lectura pondrá su política de no romper toda la vista).
- **R6 — Solo vive en TEST:** promoción a OPS = paquete coordinado futuro.
- **R7 — Truncado auto-RLS de Supabase:** mitigado (`CREATE OR REPLACE` + nada seleccionado, precedente B2; el gate embebido + POST-checks lo cazarían).
- **R8 — Dependencia B2 ≡ vivo:** cerrada (el gate P0 exigió el fingerprint baseline y coincidió).

## 9. Próximos pasos diferidos

1. **Wrappers A07/A08:** mapear `override_hora_invalido` a `payloadInv` (traducción UX del HARD), como se hizo con `fecha_in_pasada`/`rango_pasado`.
2. **Bloques de integración restantes del motor:** `obtener_disponibilidad_rango` (lectura, posterior/opcional; saldaría además su hardcode) y cualquier otra función que calcule horarios.
3. **Canonización del motor de horarios:** un solo bump de `6B_SCHEMA_SQL.md` capturando `resolver_horario` + `crear_prereserva` (guard B2 + integración B3) + `crear_bloqueo` + `fecha_hoy_ar()` + los bloques restantes. **Diferida al cierre del frente completo** (evita bumps repetidos sobre funciones que aún evolucionan).
4. **Promoción a OPS:** paquete coordinado (guard B2 + wrappers B3 + `resolver_horario` + esta integración), no piecemeal. Requiere: SQL environment-agnostic, **ajustar el gate embebido** (chequea `ambiente='test'`; para OPS debe validar el marcador de OPS), y fingerprint parity TEST↔OPS.
5. **Formalización de `D-C-XX` / `L-XX`** y propagación de satélites (`ESTADO_ACTUAL`, `DECISIONES_NO_REABRIR`, `Lecciones_Aprendidas`, `Pendiente_pre_produccion`) en el cierre formal.
6. **Regeneración del Bootstrap kit** al bump canónico.

---

**Cierre técnico Fase B / Bloque 3:** completo en TEST. El motor de horarios **manda** en `crear_prereserva` (`d92a438e…`), con no-consumo en HARD probado y todo lo crítico intacto. Wrappers A07/A08, canonización y OPS = paquete futuro coordinado. Sin `D-*`/`L-*` hasta el cierre formal.
