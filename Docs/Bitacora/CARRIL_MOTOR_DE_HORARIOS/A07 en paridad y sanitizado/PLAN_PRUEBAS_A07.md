# PLAN DE PRUEBAS — A07 `portal-a07-crear-reserva` (post-migración OPS)

**Cuándo correrlo.** Después de aplicar el fix en OPS (reemplazo del `jsCode` de `router1_crear` y `router3_confirmar`, según `GUIA_COPIA_A07_TEST_A_OPS.md`) y de que el verificador dé **exit 0**.

**Objetivo.** Confirmar que la lógica corregida quedó activa en OPS **sin romper** el camino feliz, y que los errores se devuelven **específicos** (nunca degradados a un error genérico).

**Cómo se ejecuta.** Hay dos capas:

- **Capa A — mapeo a nivel router (harness/fixture controlado).** Verifica que cada **código de error** que puede devolver la capa SQL se traduzca al envelope correcto en `router1_crear` / `router3_confirmar`. No depende de la promoción de la capa SQL: se alimenta el router con un `resultado` simulado y se observa su salida.
- **Capa B — end-to-end contra el webhook de OPS.** Ejercita el flujo real. El camino feliz, la forma de la respuesta y el aviso se pueden cerrar ya; los casos de **gap** y de **conflicto al confirmar** end-to-end **solo cierran cuando la capa SQL B1.3 correspondiente esté promovida a OPS** (antes de eso el workflow queda alineado, pero la base no necesariamente emite esos errores).

> **Nota sobre `override_hora_invalido` / `hora_fuera_de_rango`.** **No** son flags del payload de A07 (no aparecen en `PERMITIDAS`). Son **códigos de error** que devuelve el motor SQL y que `router1_crear` **mapea a `payload_invalido`**. El cliente **no** puede pisar esa validación desde A07. Por eso se prueban en la **Capa A** (mapeo), no enviándolos en la request.

> **Sobre el harness de Capa A.** El verificador ya confirma **estáticamente** que el `jsCode` de los dos routers es el correcto (byte-idéntico a TEST). Si además querés un chequeo en runtime del mapeo, alimentá el nodo router con un `resultado` simulado — por ejemplo con *pin data* sobre ese nodo en un entorno de prueba (no en OPS), o con un stub local de Node que reproduzca `$json.resultado` y `$('Code: derivar')` / `$('router1_crear')`. No cambia la lógica del workflow.

---

## Capa A — Mapeo a nivel router (harness controlado)

Cada caso alimenta el router con un `resultado` simulado (la salida que daría el PG previo) y verifica el envelope resultante.

### A1 — `router1_crear`: gap de check-in
- **Entrada simulada:** `resultado = { ok:false, error:'checkin_pisa_checkout_anterior' }`.
- **Esperado:** `continuar:false`; envelope `code:'conflicto'`, `message` que empieza con `gap_checkin: ...`.
- **PASS si:** el envelope es el de gap de check-in (no genérico).

### A2 — `router1_crear`: gap de check-out
- **Entrada simulada:** `resultado = { ok:false, error:'checkout_pisa_checkin_posterior' }`.
- **Esperado:** `continuar:false`; envelope `code:'conflicto'`, `message` que empieza con `gap_checkout: ...`.
- **PASS si:** el envelope es el de gap de check-out.

### A3 — `router1_crear`: códigos de error del motor → `payload_invalido`
- **Entrada simulada (dos corridas):** `resultado = { ok:false, error:'hora_fuera_de_rango' }` y `resultado = { ok:false, error:'override_hora_invalido' }`.
- **Esperado (en ambas):** `continuar:false`; envelope `code:'payload_invalido'`, `message` = `datos de reserva rechazados: <error>`.
- **PASS si:** ambos códigos se mapean a `payload_invalido` (confirma que son códigos de error, no flags del cliente).

### A4 — `router1_crear`: `fecha_in_pasada` → `payload_invalido`
- **Motivo:** OPS venía **sin** esta rama (quedó más viejo que el template). El fix la recupera.
- **Entrada simulada:** `resultado = { ok:false, error:'fecha_in_pasada' }`.
- **Esperado:** `continuar:false`; envelope `code:'payload_invalido'`, `message` = `datos de reserva rechazados: fecha_in_pasada`.
- **PASS si:** se mapea a `payload_invalido` (no genérico, no dejando pasar).

### A5 — `router3_confirmar`: éxito
- **Entrada simulada:** `resultado = { ok:true, id_reserva, id_pre_reserva, id_huesped }`.
- **Esperado:** `recheck:false`; envelope `ok:true` con `data` (ids + `idempotent_match:false`).
- **PASS si:** devuelve `recheck:false` y el envelope de éxito.

### A6 — `router3_confirmar`: gap al confirmar
- **Entrada simulada (dos corridas):** `resultado = { ok:false, error:'checkin_pisa_checkout_anterior' }` y `...'checkout_pisa_checkin_posterior'`.
- **Esperado:** `recheck:false`; envelope `code:'conflicto'` con el `gap_checkin:`/`gap_checkout:` correspondiente.
- **PASS si:** devuelve `recheck:false` y el envelope de gap.

### A7 — `router3_confirmar`: conflicto específico directo de `confirmar_reserva`
- **Entrada simulada (dos corridas):** `resultado = { ok:false, error:'conflicto_al_confirmar' }` y `...'no_disponible'`.
- **Esperado:** `recheck:false`; envelope `code:'conflicto'`, `message:'conflicto de disponibilidad al confirmar'`.
- **PASS si:** el conflicto se reporta directo (sin pasar por recheck) con ese mensaje.

### A8 — `router3_confirmar`: recheck idempotente por estado ya convertido
- **Entrada simulada:** `resultado = { ok:false, error:'estado_invalido', estado_actual:'convertida' }`.
- **Esperado:** `recheck:true` (esta es la **única** rama que hace que `IF3 recheck` dispare `PG-4`).
- **PASS si:** devuelve `recheck:true` (habilita la revalidación idempotente).

### A9 — `router3_confirmar`: default → `estado_incierto`
- **Entrada simulada:** `resultado = { ok:false, error:'<cualquier_otro>' }`.
- **Esperado:** `recheck:false`; envelope `code:'estado_incierto'` con `detail.paso:'confirmacion'`.
- **PASS si:** cae al envelope de estado incierto.

---

## Capa B — End-to-end contra OPS

### P0 — Camino feliz (alta + pago + confirmación)
- **Precondición:** cabaña y rango de fechas **libres** (sin reservas ni bloqueos que solapen ni que violen los gaps).
- **Entrada:** request válida y firmada, con fechas correctas y datos de pago que permitan confirmar.
- **Resultado esperado:**
  1. Se crea la pre-reserva (`PG-1`), `router1_crear` deja seguir.
  2. Se registra el pago (`PG-2`), `router2_pago` deja seguir.
  3. Se confirma (`PG-3`). En el camino feliz, `router3_confirmar` devuelve **`recheck:false`**.
  4. Por lo tanto **`IF3 recheck` va directo a `Code: render`**: **`PG-4` NO se ejecuta** en el camino normal. (`PG-4` solo corre en el caso `estado_invalido` + `estado_actual='convertida'` — ver A8.)
  5. **HTTP 200** con envelope `ok:true`.
  6. Se dispara el aviso 8C-bis (ver P7).
- **PASS si:** la reserva queda confirmada en OPS, la respuesta es `ok:true`, `PG-4` no se ejecutó y el aviso salió.

### P6 — Respuesta HTTP y envelope
- **Objetivo:** confirmar la forma de la respuesta en éxito y en error.
- **Entrada:** reutilizá P0 (éxito) y cualquier caso de error que la BD ya pueda emitir (o el harness de Capa A para la forma del envelope).
- **Resultado esperado:**
  - **Éxito:** HTTP 200, envelope `ok:true` con los datos de la reserva.
  - **Error:** envelope `ok:false` con `error` **específico** (código y mensaje que identifican el caso: gap de check-in/out, `payload_invalido`, conflicto al confirmar, estado incierto). Nunca un error genérico que oculte la causa.
  - El nodo `Respond` responde con el ítem correcto (comportamiento `firstIncomingItem`).
- **PASS si:** ambos formatos son correctos y el error **conserva su especificidad** de punta a punta.

> Este caso es el guardarraíl central del pedido: **los errores específicos no deben degradarse a genéricos** en ningún punto del render/respuesta.

### P7 — Aviso 8C-bis (alta nueva)
- **Objetivo:** confirmar que, ante un alta nueva válida, se dispara el subworkflow de avisos del ambiente **OPS**.
- **Precondición:** P0 exitoso.
- **Resultado esperado:**
  - El `IF aviso 8C-bis (alta nueva)` evalúa verdadero y `Call 'vita_w8cbis_alerta__OPS' (aviso)` se invoca contra el subworkflow **de OPS** (no el de TEST).
  - El aviso se emite sin error (workflowId de OPS válido).
- **PASS si:** el aviso sale y apunta al subworkflow correcto de OPS.

> Chequeo ambiental incluido: verificá que el aviso invocó `...__OPS` (no `...__TEST`). Es el control de que el `workflowId` del subworkflow quedó bien tras el fix.

### P8 — Gap de calendario end-to-end  *(cierra cuando B1.3 esté promovido a OPS)*
- **Depende de:** la capa SQL B1.3 promovida a OPS. Antes de eso, el workflow está alineado (Capa A lo confirma), pero la BD **no necesariamente** emite `checkin_pisa_checkout_anterior` / `checkout_pisa_checkin_posterior`.
- **Precondición:** existe una reserva anterior/posterior que deja un gap **insuficiente** respecto del check-in/check-out solicitado.
- **Entrada:** request válida y firmada con esas fechas.
- **Resultado esperado:** la BD emite el error de gap, `router1_crear` corta con el envelope `code:'conflicto'` (`gap_checkin`/`gap_checkout`), **no** se crea la reserva.
- **PASS si:** se rechaza con el error de gap correcto y no queda reserva creada. (Hasta la promoción de B1.3, cubierto por A1/A2 a nivel router.)

### P9 — Conflicto al confirmar end-to-end  *(cierra cuando B1.3 esté promovido a OPS)*
- **Depende de:** la capa SQL B1.3 promovida a OPS.
- **Dos variantes que hay que distinguir:**
  - **P9-A (conflicto específico directo):** entre el alta y la confirmación, la disponibilidad se rompe y `confirmar_reserva` devuelve `conflicto_al_confirmar` / `no_disponible`. → `router3_confirmar` devuelve `recheck:false` + envelope conflicto "conflicto de disponibilidad al confirmar". `IF3` va directo a render (sin `PG-4`). La reserva **no** se confirma. (Cubierto a nivel router por A7.)
  - **P9-B (recheck idempotente por estado convertido):** la confirmación llega con `estado_invalido` + `estado_actual='convertida'` (la reserva ya estaba convertida). → `router3_confirmar` devuelve `recheck:true`; `IF3` dispara **`PG-4` (`recheck_reserva_post_confirmar`)** → `router4_recheck`. Esta es la **única** ruta que ejecuta `PG-4`. (Cubierto a nivel router por A8.)
- **PASS si:** cada variante toma su rama (P9-A sin `PG-4`; P9-B con `PG-4`) y el resultado final es correcto (reserva no confirmada indebidamente / recheck idempotente coherente).

---

## Planilla de resultados

**Capa A (harness):**

| # | Caso | Esperado | Obtenido | PASS/FAIL |
|---|---|---|---|---|
| A1 | r1 gap check-in | `conflicto` + `gap_checkin:` | | |
| A2 | r1 gap check-out | `conflicto` + `gap_checkout:` | | |
| A3 | r1 `hora_fuera_de_rango` / `override_hora_invalido` | `payload_invalido` (ambos) | | |
| A4 | r1 `fecha_in_pasada` | `payload_invalido` | | |
| A5 | r3 éxito | `recheck:false` + `ok:true` | | |
| A6 | r3 gap al confirmar | `recheck:false` + envelope gap | | |
| A7 | r3 conflicto directo | `recheck:false` + "conflicto ... al confirmar" | | |
| A8 | r3 `estado_invalido`+`convertida` | `recheck:true` | | |
| A9 | r3 default | `recheck:false` + `estado_incierto` | | |

**Capa B (end-to-end OPS):**

| # | Caso | Esperado | Obtenido | PASS/FAIL |
|---|---|---|---|---|
| P0 | Camino feliz | `ok:true`, confirmada, **PG-4 no ejecuta**, aviso OK | | |
| P6 | HTTP / envelope | forma correcta, error específico | | |
| P7 | Aviso 8C-bis | dispara hacia `...__OPS` | | |
| P8 | Gap end-to-end *(pend. B1.3 OPS)* | error de gap, sin alta | | |
| P9-A | Conflicto directo al confirmar *(pend. B1.3 OPS)* | conflicto, sin `PG-4`, no confirma | | |
| P9-B | Recheck idempotente *(pend. B1.3 OPS)* | `recheck:true` → `PG-4` | | |

---

## Criterio de cierre

La migración de A07 a OPS se considera **validada** cuando:

1. **Capa A completa** (A1–A9) pasa: el mapeo de todos los códigos de error al envelope correcto está confirmado a nivel router.
2. **P0** pasa (el fix no rompió el camino feliz) y se verifica que **`PG-4` no se ejecuta** en el camino normal.
3. **P6** confirma que ningún error específico se degrada a genérico.
4. **P7** confirma que el aviso apunta al subworkflow **de OPS**.
5. **P8 / P9** quedan **pendientes de la promoción de B1.3 a OPS**; hasta entonces su cobertura es la de Capa A (A1/A2/A7/A8). Una vez promovido B1.3, se cierran end-to-end.

Si algún caso falla, revisá primero que el `jsCode` de los dos routers haya quedado pegado completo y con las referencias limpias (`$('Code: derivar')`, `$('router1_crear')`), y volvé a correr el verificador.
