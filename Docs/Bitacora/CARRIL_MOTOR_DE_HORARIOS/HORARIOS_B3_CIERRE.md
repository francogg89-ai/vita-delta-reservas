# HORARIOS_B3 — Cierre técnico (TEST)

**Sub-frente:** Motor formal de horarios — UX de errores del guard temporal en wrappers A07/A08.
**Estado:** B3 aplicado y validado en TEST. **Cierre preliminar:** sin acuñar `D-*`/`L-*`, sin propagar satélites, sin modificar el canónico.
**Entorno:** TEST.
**Artefactos:** `portal-a07-crear-reserva__TEMPLATE.json` y `portal-a08-crear-bloqueo__TEMPLATE.json` (actualizados), `HORARIOS_B3_smoke_e2e_TEST.ps1`, `HORARIOS_B3_RUNSHEET.md`.
**Validado:** 2026-06-29 (AR).

---

## 1. Veredicto

🟢 **VERDE.** `fecha_in_pasada` (A07) y `rango_pasado` (A08) ahora llegan al frontend como `payload_invalido` con mensaje específico, en vez del genérico `error_interno`. Cierra el único pendiente de UX que dejó B2.

## 2. Qué cambió

- **A07**, nodo `router1_crear`: `'fecha_in_pasada'` agregado al array `payloadInv` → mapea a `payload_invalido` con mensaje `'datos de reserva rechazados: fecha_in_pasada'`.
- **A08**, nodo `router_bloqueo`: `'rango_pasado'` agregado al array `payloadInv` → mapea a `payload_invalido` con mensaje `'datos de bloqueo rechazados: rango_pasado'`.
- Aplicado **live por edición directa de nodo** (no re-import → no se tocó HMAC ni credenciales).
- **Templates de repo actualizados** (paridad repo↔live).
- Único delta por wrapper: un string en `payloadInv` (diff probado por reverse-replace; JSON válido; `node --check` EXIT 0).

## 3. Evidencia

- **Repo:** diffs de los dos `__TEMPLATE.json` — única diferencia, el string nuevo en `payloadInv`; JSON válido + `node --check` EXIT 0.
- **Live n8n TEST:** nodos `router1_crear` (A07) y `router_bloqueo` (A08) editados y workflows guardados.
- **Smoke E2E firmado** (payloads válidos salvo la fecha, sin consumo de secuencias): A07 fecha pasada → `payload_invalido` + `fecha_in_pasada` (PASS); A08 rango pasado → `payload_invalido` + `rango_pasado` (PASS); **2/2 PASS**.

## 4. Qué NO se tocó

- **SQL:** `fecha_hoy_ar`, `crear_prereserva`, `crear_bloqueo` intactos (fingerprints de B2 sin cambios).
- **Gateway `portal-api`:** sin tocar (`payload_invalido` ya allowlisted y con mensaje conservado).
- **Frontend / calendario:** sin tocar.
- **Override manual / `overrides_operativos`:** sin tocar.
- **Canónico:** sin modificar.
- **OPS:** sin tocar (ni el `portal-a07-crear-reserva__OPS.json`).
- Sin acuñar `D-*`/`L-*`.

## 5. Rollback

Por wrapper: abrir el nodo y **quitar** el string agregado de `payloadInv` → guardar (o re-importar el `__TEMPLATE.json` previo). El comportamiento vuelve a `error_interno` para esos códigos. Trivial, sin efectos colaterales.

## 6. Estado final del guard temporal (B2 + B3)

- **Backend (B2):** `crear_prereserva` rechaza `fecha_in < hoy_ar` (`fecha_in_pasada`); `crear_bloqueo` rechaza rangos completamente pasados (`rango_pasado`). Helper `fecha_hoy_ar()` en zona Argentina, independiente del timezone de sesión. EXCLUDE y modelo `[fecha_in, fecha_out)` intactos.
- **UX (B3):** esos errores llegan al frontend como `payload_invalido` con motivo legible.
- **Resultado:** guard temporal **completo de punta a punta en TEST** — bloqueo determinístico en backend + error claro en frontend.
- **Pendiente deferido (NO bloqueante):** B2+B3 viven solo en TEST. Falta, como paquete coordinado futuro: **canonización** (bump del canónico) + **promoción a OPS**, que debe incluir el guard SQL, el helper, y el cambio de `payloadInv` en los wrappers `__OPS` de A07 y A08. Está identificado y trackeado; fuera del alcance actual.

## 7. Próximo paso recomendado

No detecto pendiente crítico que bloquee. Recomiendo **retomar el motor de horarios**, retomando exactamente donde pausamos: el **diseño de autorización reforzada del override manual por reserva** — el punto que querías fortalecer antes de aprobar la ruta A (sin bypass amplio; ventana absoluta anti-typo, no cualquier `TIME`). Alternativa igualmente válida: **fase B** (activar `overrides_operativos` con `resolver_horario()`, HARD ante `valor` inválido). El guard temporal queda cerrado y **no es prerequisito** de ninguno de los dos.

---

**Cierre técnico B3:** completo en TEST. El sub-frente de guard temporal (B2+B3) queda cerrado punta a punta. Cierre formal del frente (con `D-*`/`L-*` y satélites) + promoción a OPS quedan para el hito correspondiente.
