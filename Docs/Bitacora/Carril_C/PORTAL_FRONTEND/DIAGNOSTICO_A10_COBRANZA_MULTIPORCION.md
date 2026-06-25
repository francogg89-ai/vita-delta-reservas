# DIAGNÓSTICO — A10 cobranza: pago partido + recargo 5%

**Pregunta:** ¿el frontend puede hacer pago partido (hasta 3 medios) + recargo 5% sobre transferencia, con el extra separado del 25%, usando el A10 actual? **Respuesta corta: no con el endpoint que hoy ve el frontend; pero la lógica completa ya existe en otro workflow. Hace falta un cambio de backend (exponerla por el gateway).** No inventar nada en el frontend.

## 1. Qué soporta HOY cada pieza (leído de la fuente viva)

**Gateway A10 `cobranza.registrar_saldo` → W10 (`vita_w10_registrar_saldo`, Webhook):**
- Acepta **solo** `{ id_reserva, monto, medio_pago, idempotency_key, notas }` — **una porción, un medio**.
- Llama `registrar_pago` **una vez** (envuelto en `abortar_si_falla`) → registra **un `saldo`**.
- **NO calcula recargo, NO genera línea `extra`.** (Verificado: ningún nodo de W10 menciona recargo/0.05/extra.)
- Es lo que llama el frontend hoy.

**Carril B `cobranza_posterior` → W09 (`vita_w09_cobranza_posterior_supabase__TEST_3b`, 14 nodos, Form Trigger Basic Auth):**
- **Hace TODO lo que pedís, y ya está verificado con smokes** (9B_CIERRE: recargos $8.500 / $5.000 / $1.650; rollback atómico):
  - Entrada: `id_reserva`, `monto_efectivo`, `monto_transferencia`, `subtipo_transferencia` (bancaria/MP), `monto_otros` (+ origen/descripción).
  - `suma_saldo = ef + tr + ot`; valida `suma_saldo > 0` y `suma_saldo ≤ saldo_real`.
  - **`recargo = tr > 0 ? round(tr * 0.05) : 0`** — 5% **solo** sobre transferencia; efectivo y "otros" **no** generan recargo.
  - **"Otros"** (cripto/dólares/etc.) se registra como `saldo` **efectivo‑equivalente ARS** con traza (`medio_original=otros; …; registrado_como=efectivo_ars`).
  - Genera líneas: `saldo` efectivo + `saldo` "otros" + `saldo` transferencia + **`extra`** transferencia (recargo, marcado `recargo_5_saldo_transferencia`). Máx 4 líneas.
  - **El `extra` NO reduce el saldo**: `saldo_proyectado = saldo_real − suma_saldo`.
  - **Atómico** (D-9B-19): cada línea por `registrar_pago` + `abortar_si_falla` → si una falla, rollback de TODO el evento.
- **Pero se dispara por Form Trigger (Basic Auth), NO por el gateway portal-api** → **el frontend (JWT/gateway) no lo puede llamar.**

**Contabilidad (tu regla #4) — ya resuelta:**
- `pagos.tipo` incluye `'extra'` (enum `sena/saldo/extra/reembolso/ajuste`).
- Las funciones de distribución separan **`p1 = SUM(seña+saldo)`** de **`p6 = SUM(extra)`**: el **25% se calcula sobre base (`p1`)** y el **`extra` (`p6`) queda afuera**. Exactamente lo que pediste, sin cambios.

## 2. Conclusión

- **El split + 5% NO se puede resolver desde el frontend con el A10 actual.** Hacer N llamadas secuenciales a W10 registraría las porciones de `saldo`, pero **W10 no agrega el recargo 5%** → el `extra` quedaría **sin generar** → resultado incompleto e incorrecto. **Descartado.**
- La lógica correcta **ya existe y está verificada en W09**, pero **no está expuesta por el gateway**.
- **Fix correcto = cambio de backend: exponer la cobranza multi-porción de W09 a través del gateway portal-api.** La parte difícil (validación multi-porción, recargo, expansión de líneas, `registrar_pago` transaccional, verificación, separación del `extra`) **ya está hecha**; es básicamente **cambiar el disparador** (Form Trigger → Webhook del gateway) + envelope (firma/ts/rol vicky+socio) + un validador de payload. **No toca `registrar_pago`, ni tablas, ni enums** (igual que 9B).

## 3. Camino propuesto (tu decisión — reabre/extiende backend A10)

**Etapa backend "A10‑MP" (exponer cobranza multi-porción por el gateway), después B5 frontend sobre ese contrato.** Entregables que te prepararía (vos deployás):
1. **Gateway:** nueva acción de CATALOG (ej. `cobranza.registrar_cobro`) + validador de payload que espeja la entrada de W09:
   ```
   { id_reserva, monto_efectivo?, monto_transferencia?, subtipo_transferencia? ('bancaria'|'MP'),
     monto_otros?, origen_otros?, descripcion_otros?, idempotency_key, notas? }
   ```
   (o un array `porciones`; mirroreo la forma de W09, lo que minimiza el riesgo).
2. **Wrapper nuevo:** injerto del cuerpo verificado de W09 (N3 validación+recargo, N4.5 expandir, N5 transaccional + `abortar_si_falla`, N6 verificación, N7) sobre el preámbulo estándar del gateway (Webhook → `validar_firma_ts_rol` → `leer_ambiente` → `verificar_acceso` → cuerpo W09 → `render` envelope → `Respond`).
3. **Smokes** (HMAC directo + JWT gateway), con los casos de 9B (recargos + rollback).
4. **Frontend B5** sobre el nuevo contrato: multi-línea, preview del 5%, anti-sobrepago sobre la suma de `saldo`, resumen (aplicado a saldo / extra 5% / total a cobrar / saldo restante) — mapea 1:1 a la salida de W09 (`suma_saldo`, `recargo`, `total_paga`, `saldo_proyectado`).

> Esto **reabre/extiende un área de backend cerrada** (A10 / Carril C ↔ Carril B). Es una decisión deliberada. La alternativa (B5 single-porción sin split/5%) **vos ya la descartaste**, y con razón: dejaría afuera la operación real.

## 4. Qué necesito de vos

Decime cómo seguimos:
- **(A)** Avanzamos con la etapa backend **A10‑MP** (te preparo gateway + wrapper desde W09 + smokes), y después B5 frontend sobre el contrato nuevo. **(recomendado)**
- **(B)** Otra cosa.

No necesito que me pases los templates: ya leí W09 y W10. Y **no escribo código de B5** hasta que exista el endpoint multi-porción en el gateway.
