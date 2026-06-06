# ARQUITECTURA_ETAPA_9B_COBRANZA_POSTERIOR.md

**Etapa:** 9B — Capa de cobranza posterior (corresponde al Bloque 1B del Carril A, Etapa 9)
**Estado:** ✅ Diseño aprobado y cerrado — pendiente implementación en TEST. Satélites sin actualizar.
**Tipo:** Documento de arquitectura (sin implementación, sin SQL ejecutable, sin workflow JSON)
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` (NO se modifica)
**Contratos leídos (read-only):** `registrar_pago(payload jsonb)` (1B-0) · `confirmar_reserva(payload jsonb)` (post-9A)
**Dependencia:** `9A_DIAGNOSTICO_INGRESOS.md` (diagnóstico read-only cerrado)
**Entorno de diseño/validación:** TEST (`vita-delta-test`) — OPS solo tras aprobación explícita
**Autores:** Franco (titular) + Claude (arquitecto)
**Decisiones registradas:** D-9B-01 a D-9B-10

> Documento de diseño para revisión. **No implementa nada.** No actualiza satélites.
> Sin writes, sin DDL, sin workflow JSON, sin SQL ejecutable, sin OPS.

---

## 1. Resumen ejecutivo

La Etapa 9B construye la **capa de cobranza posterior**: un formulario n8n (Form Trigger,
Basic Auth, usable desde celular) con el que el operador (Vicky/Rodrigo/Franco/Remo)
registra un pago **posterior a la confirmación** de una reserva — típicamente el saldo que
se cobra al ingresar a la cabaña, en efectivo o transferencia, y eventualmente el recargo
5% cuando el saldo se paga por transferencia.

Llena el agujero medido en el diagnóstico 9A: **13 reservas con $1.245.000 de saldo** que
el sistema hoy no sabe registrar, porque solo conoce la seña inicial.

La capa **invoca `registrar_pago()` existente. No toca schema, no toca la función, no toca
el motor.** Toda la lógica nueva vive en la capa n8n y en el cálculo de saldo real.

Es la primera capa del proyecto donde el formulario **no es solo UX**: como `registrar_pago()`
no valida el saldo pendiente, la capa asume co-responsabilidad sobre la integridad contable.

---

## 2. Contexto y dependencias

### 2.1 Qué viene del diagnóstico 9A
- En TEST: 14 pagos, todos `sena`, todos `confirmado`. **0 pagos de tipo `saldo`.**
- El ciclo de cobranza posterior no está representado: el saldo nunca se registra como pago.
- `saldo_real` y `saldo_documental` coinciden hoy solo por ausencia de cobranza; divergirán
  cuando exista el primer pago de saldo (es decir, cuando opere esta capa).

### 2.2 Qué viene de 1B-0 (contrato de `registrar_pago`)
- Acepta `id_reserva` directo (no exige pre-reserva). El CHECK `chk_pagos_referencia_minima`
  se satisface con `id_reserva` solo.
- No ramifica por `tipo`; acepta `saldo`/`extra`/`ajuste`/`reembolso` (todos en el CHECK).
- Permite múltiples pagos por reserva (sin unique que lo impida).
- Confirma un pago **solo si** `estado_inicial='confirmado'` Y `monto_recibido = monto_esperado`;
  cualquier otro caso cae en `en_revision`.
- **No valida saldo** (no sabe cuánto se debe) y **no tiene idempotencia** (no hay índice único).
- Registra log con `source_event`.

### 2.3 Qué viene de la lectura de `confirmar_reserva` (L-9A-01 confirmada)
- Al confirmar, ejecuta `UPDATE pagos SET id_reserva = v_id_reserva WHERE id_prereserva = ...`:
  rellena `id_reserva` en los pagos de la pre-reserva sin borrar `id_prereserva`.
- Por eso los pagos del flujo normal quedan con ambos IDs.
- **Consecuencia para 9B:** la cobranza posterior se registra **directamente contra
  `id_reserva`**, no contra `id_prereserva` (que para entonces está en estado `convertida`).

---

## 3. Principio de diseño: co-responsabilidad contable de la capa

### 3.1 El patrón 8B/8D y por qué acá NO aplica del todo
En 8B (reservas) y 8D (bloqueos), la función SQL del motor es la **única barrera**: valida
todo (existencia, fechas, conflictos), y el formulario es solo capa de UX y mensajería. Si
la función dice OK, el dato es íntegro.

En 9B esto **no se cumple del todo**: `registrar_pago()` valida el formato del pago, pero
**no valida el saldo pendiente de la reserva** — no sabe cuánto se debe. Puede registrar un
saldo que duplica otro ya cobrado, o que excede lo adeudado, sin error.

### 3.2 Qué valida el motor vs qué debe validar la capa

| Validación | ¿La hace `registrar_pago`? | ¿La hace la capa 9B? |
|---|---|---|
| Reserva existe | ✅ (`reserva_no_existe`) | — |
| `tipo`/`medio` válidos | ✅ (CHECKs) | — |
| Montos > 0 / >= 0 | ✅ (CHECKs) | — |
| Confirma si exacto | ✅ | (la capa fuerza exacto) |
| **Saldo pendiente real** | ❌ | ✅ |
| **No duplicar saldo** | ❌ | ✅ |
| **No exceder saldo** | ❌ | ✅ |
| **Separar saldo de extra** | ❌ | ✅ |

### 3.3 Responsabilidades que la capa asume (D-9B-01)
1. Calcular el saldo real antes de registrar.
2. Mostrarlo al operador.
3. Impedir cargar `tipo=saldo` si el saldo real = 0.
4. Impedir cargar como `saldo` un monto mayor al saldo real.
5. Obligar a separar saldo y extra cuando corresponda.
6. Recalcular y mostrar el saldo después de registrar.

> **D-9B-01 — Co-responsabilidad contable de la capa.** A diferencia de 8B/8D, en 9B la
> capa no es solo UX: como `registrar_pago()` no valida saldo, la capa es co-responsable de
> la integridad contable, asumiendo las seis responsabilidades anteriores.

---

## 4. Alcance del MVP

### 4.1 Entra en el MVP (D-9B-04)
- `tipo='saldo'` (efectivo y transferencia).
- `tipo='extra'` **exclusivamente** para recargo 5%.
- Cálculo de saldo real + secuencia de validaciones anti-duplicación.

### 4.2 Fuera del MVP (diferido)
`ajuste`, `reembolso`, caja por lugar, gastos, liquidaciones, `cancelada_con_cargo`,
promoción de pagos `en_revision`, y toda integración externa (AFIP/ARCA/IVA, MercadoPago,
bancos, frontend, bot, WhatsApp, Airbnb/Booking).

> **D-9B-04 — Alcance MVP.** El MVP registra únicamente `saldo` y `extra` (recargo 5%).
> Todo lo demás se difiere a etapas posteriores con reglas de negocio propias.

---

## 5. Cálculo del saldo real (fundamento contable)

### 5.1 Fórmula
```
saldo_real = reservas.monto_total
           − SUM(pagos confirmados WHERE tipo IN ('sena','saldo'))
```
con normalización de asociación de pagos:
```
id_reserva_normalizado = COALESCE(
  pagos.id_reserva,
  reserva cuyo id_pre_reserva = pagos.id_prereserva
)
```

### 5.2 Por qué NO se usa `reservas.monto_saldo` como saldo vivo (D-9B-05)
`confirmar_reserva` fija `monto_saldo = monto_total − monto_sena` **una sola vez** en el
alta y nunca lo recalcula; ningún trigger lo actualiza; la columna no es generada (L-9A-02).
Por lo tanto es una **referencia documental/inicial**, no el saldo vivo. El saldo vivo
siempre se calcula desde los pagos confirmados.

> **D-9B-05 — Saldo calculado, no documental.** El saldo pendiente operativo se calcula
> desde pagos confirmados (`sena`+`saldo`). `reservas.monto_saldo` queda como referencia.

### 5.3 Comportamiento con parciales (D-9B-06)
Cada pago parcial se registra como **pago confirmado por el monto que efectivamente entra**
(`monto_esperado = monto_recibido`, `estado_inicial = confirmado`). El saldo vivo se reduce
con cada parcial confirmado. No se generan pagos `en_revision` en este flujo.

> **D-9B-06 — Parciales permitidos como pagos confirmados.** Un saldo puede cobrarse en
> varios pagos; cada uno confirma por su propio monto exacto. El saldo vivo se recalcula.

---

## 6. Flujo operativo de la capa (paso a paso)

1. **Selección de reserva** → la capa calcula y muestra `monto_total`, cobrado de
   alojamiento y **saldo_real** (§5).
2. **Secuencia anti-duplicación (Regla 3):**
   - Si `tipo=saldo`: impedir si saldo_real = 0; impedir si monto > saldo_real; si el monto
     excede el saldo, obligar a separar saldo (hasta saldo_real) + extra (excedente, si
     corresponde).
   - Si `tipo=extra` (recargo 5%): la capa sugiere el 5% sobre el saldo transferido; el
     operador confirma o ajusta con justificación.
3. **Registro** vía `registrar_pago()` con `estado_inicial='confirmado'`,
   `monto_esperado = monto_recibido`, `id_reserva` del selector, `source_event` generado.
4. **Verificación del resultado real**: no confiar en `ok:true` (lección 8B); releer el
   pago y confirmar que quedó `confirmado`.
5. **Recálculo y visualización** del nuevo saldo_real al operador.

---

## 7. Campos del formulario

### 7.1 Completa el operador
Reserva (selección), tipo de cobro (`saldo` / `extra (recargo 5%)`), medio de pago
(efectivo / transferencia_bancaria / transferencia_mp), monto, validado por, notas
(opcional).

> **Medios visibles en el MVP (D-9B-08).** El formulario muestra solo los tres medios
> operativos actuales: `efectivo`, `transferencia_bancaria`, `transferencia_mp`. Los medios
> `mp_link` y `cripto` siguen soportados por el contrato y la base, pero **no se exponen en
> el formulario inicial** salvo decisión posterior.

### 7.2 Arma la capa automáticamente
`monto_esperado` (= monto recibido), `estado_inicial` (= `confirmado`), `source_event`
(generado), `id_reserva` (del selector), marcado del 5% (`source_event` + `notas`).

### 7.3 Mapeo campo → payload de `registrar_pago`
| Formulario | Payload | Valor |
|---|---|---|
| Reserva | `id_reserva` | id del selector |
| Tipo de cobro | `tipo` | `saldo` o `extra` |
| Medio de pago | `medio_pago` | efectivo / transferencia_bancaria / transferencia_mp (MVP) |
| Monto | `monto_recibido` y `monto_esperado` | el mismo valor (forzado) |
| Validado por | `validado_por` | operador |
| (fijo) | `estado_inicial` | `confirmado` |
| (generado) | `source_event` | distintivo de la capa |
| Notas | `notas` | texto + marcado automático si 5% |

---

## 8. Tratamiento del recargo 5%

### 8.1 Cuándo aplica
**Solo cuando el saldo se paga por transferencia** (no en efectivo).

### 8.2 Cálculo y confirmación
La capa **calcula el 5% sugerido sobre el monto de saldo que se paga por transferencia en
esa carga**, no sobre el saldo total de la reserva. Ejemplo: si el saldo real es $100.000 y
el cliente paga $40.000 por transferencia, el 5% sugerido se calcula sobre $40.000 (= $2.000).
El operador lo **confirma o ajusta con justificación** (la justificación va en notas).

### 8.3 Registro como línea separada (Regla 2)
Se registra como un pago **`tipo=extra` aparte**, `medio_pago=transferencia_bancaria` o
`transferencia_mp`, `monto_esperado = monto_recibido = importe del recargo`,
`estado_inicial=confirmado`. **No se suma dentro del saldo** — eso rompería la conciliación
de alojamiento (§5).

### 8.4 Marcado automático (D-9B-02)
- En `source_event`: identificador distintivo `recargo_5_saldo_transferencia`.
- En `notas`: etiqueta generada automáticamente `recargo_5_saldo_transferencia` + la
  justificación del operador si ajustó el monto.

> **D-9B-02 — Modelado del recargo 5%.** Solo aplica a saldo por transferencia. Se registra
> como línea separada `tipo=extra`, nunca dentro del saldo. La capa sugiere el 5% **sobre el
> monto de saldo transferido en esa carga** (no sobre el saldo total de la reserva); el
> operador confirma/ajusta con justificación. Marcado en `source_event` y `notas` como
> `recargo_5_saldo_transferencia`. (Su tratamiento en liquidación — repartible o no — queda
> abierto en el Carril B: "entrada real de caja, no necesariamente ingreso repartible".)

---

## 9. Mapeo de casos reales al contrato

| Caso real | `tipo` | `medio_pago` | Monto | ¿Confirma solo? |
|---|---|---|---|---|
| Saldo efectivo al ingresar | `saldo` | `efectivo` | = saldo o parcial | ✅ |
| Saldo transferencia al ingresar | `saldo` | transferencia (bancaria/mp) | = saldo o parcial | ✅ |
| Saldo parcial | `saldo` | el que sea (de los 3 del MVP) | lo que entra | ✅ (cada parcial exacto) |
| Recargo 5% | `extra` | transferencia (bancaria/mp) | 5% del saldo transferido en la carga | ✅ |
| Cliente confianza, casi todo al llegar | seña $1 (8B) + `saldo` posterior | efectivo | resto | ✅ |
| Mixto (parte efectivo, parte transferencia) | dos pagos `saldo` | distinto medio | cada parte | ✅ dos operaciones separadas del formulario |

Todos confirman porque la capa fuerza `recibido=esperado` y `estado_inicial=confirmado`.
**Cero `en_revision`** en el flujo de cobranza posterior.

---

## 10. Validaciones de la capa (detalle)

### 10.1 Por tipo
- `saldo`: saldo_real > 0; monto ≤ saldo_real.
- `extra` (5%): solo si hubo/hay saldo por transferencia; monto sugerido = 5%, ajustable
  con justificación.

### 10.2 Reglas duras
- Impedir `saldo` si saldo_real = 0.
- Impedir `saldo` con monto > saldo_real.
- Forzar separación saldo + extra cuando el monto excede el saldo.

### 10.3 Qué NO valida la capa (lo cubre el motor)
Existencia de la reserva, validez de `tipo`/`medio` (CHECKs), montos > 0 / >= 0. La capa no
duplica esas validaciones; confía en el motor para ellas.

---

## 11. Privacidad y minimización de datos (D-9B-03)

### 11.1 Selector de reserva
**Lista solo reservas con `saldo_real > 0` y estado `confirmada` o `activa`** (salvo decisión
posterior): no muestra reservas sin saldo ni históricas/completadas en el MVP (D-9B-10).
Para cada reserva muestra: ID de reserva, cabaña, fecha entrada/salida, saldo pendiente, y
opcionalmente **nombre corto** del huésped si hace falta para operar.
**No muestra:** DNI, email, teléfono, ni notas.

### 11.2 Público Basic Auth
Operativo (Vicky/Rodrigo/Franco/Remo). No es un público amplio. La capa maneja datos
personales mínimos, lo que la diferencia del diagnóstico (que no leía `huespedes`).

### 11.3 Datos sensibles fuera de GitHub
Montos, recargos y cualquier cifra real no se documentan con valores reales en el repositorio.

> **D-9B-03 — Minimización de datos en el selector.** El selector expone solo lo necesario
> para operar (ID, cabaña, fechas, saldo, nombre corto opcional); nunca DNI, email, teléfono
> ni notas.

---

## 12. Riesgos conocidos

### 12.1 No-atomicidad de la anti-duplicación por capa
La protección anti-duplicación vive en la capa (Regla 3), no en el schema. **No es atómica**:
dos operadores cargando el mismo saldo casi simultáneamente podrían ambos pasar la validación
"saldo_real > 0" antes de que cualquiera inserte, y duplicar.

**Riesgo aceptado para el MVP** porque el uso es interno, con pocos operadores y baja
concurrencia, y la cobranza es presencial. **Salida futura** si la concurrencia crece: un
índice único parcial de idempotencia sobre `pagos` (cambio de schema menor), o resolver la
secuencia dentro de una función transaccional.

### 12.2 Dependencia permanente de la normalización
No es un riesgo, es una característica: la seña vive con ambos IDs y el saldo posterior con
`id_reserva`. Todo reporte contable depende de `COALESCE(id_reserva, vía_prereserva)` de
forma permanente. Se documenta para que no sorprenda.

### 12.3 Menores
- El operador podría elegir mal el medio (efectivo vs transferencia) → afecta el cálculo del
  5%. Mitigación: la capa solo sugiere 5% si el medio es transferencia.

> **D-9B-07 — No-atomicidad de la anti-duplicación (riesgo aceptado).** La protección
> anti-duplicación por capa no es atómica; se acepta para el MVP por uso interno y baja
> concurrencia, con índice de idempotencia como salida futura si la concurrencia crece.

---

## 13. Topología técnica de la capa (nivel medio, sin implementar)

> Esta sección describe el **flujo técnico previsto**, no la implementación. Sin JSON de
> workflow ni SQL ejecutable.

Workflow tipo **Form Trigger n8n**, familia `vita_w0X_*_supabase`, Basic Auth, credencial
por entorno (TEST primero: `vita_supabase_test`). Nodos conceptuales, en orden:

1. **Nodo formulario (Form Trigger).** Recibe selección de reserva, tipo de cobro, medio,
   monto, validado_por, notas. El selector de reserva se alimenta de una **consulta de
   reservas con saldo** que lista solo reservas con `saldo_real > 0` y estado `confirmada`
   o `activa` (D-9B-10), para mostrar opciones legibles y mínimas (§11).

2. **Nodo consulta de saldo real.** Antes de permitir cargar, una consulta read-only calcula
   el `saldo_real` de la reserva elegida con la fórmula del §5 (normalización +
   `monto_total − Σ pagos confirmados sena/saldo`). Devuelve saldo_real, monto_total y
   cobrado. *(SQL conceptual, no incluido aquí; se escribirá en implementación.)*

3. **Nodo validación de capa.** Aplica las reglas duras del §10.2 sobre el saldo_real y el
   monto ingresado:
   - saldo_real = 0 con tipo=saldo → corta con error de negocio.
   - monto > saldo_real con tipo=saldo → corta y pide separar saldo/extra.
   - tipo=extra sin transferencia → corta.
   Si pasa, arma el payload (campos forzados del §7.2).

4. **Nodo llamada a `registrar_pago()`.** Invoca la función con el payload. **Una ejecución
   del formulario = un solo pago = una sola llamada.** Un cobro mixto (parte efectivo, parte
   transferencia) se carga como **dos operaciones separadas del formulario**, no como dos
   llamadas dentro de la misma ejecución (D-9B-09). `estado_inicial = confirmado`,
   `monto_esperado = monto_recibido`.

5. **Nodo verificación posterior del pago.** Relee el pago recién creado (por `id_pago`
   devuelto) y confirma `estado = confirmado`. No confía en `ok:true` (lección 8B). Si no
   quedó confirmado → tratar como anomalía y avisar.

6. **Nodo recálculo de saldo.** Vuelve a calcular el saldo_real (mismo SQL del punto 2) para
   reflejar el nuevo estado tras el pago.

7. **Nodo respuesta humana.** Devuelve al operador un mensaje claro: pago registrado (tipo,
   monto, medio), saldo anterior → saldo nuevo, y si fue recargo 5% lo indica. Lenguaje
   humano, no JSON crudo.

8. **Manejo de error técnico.** Fallo de conexión, timeout, error inesperado de la función →
   mensaje genérico "no se pudo registrar, reintentá" + no deja estado a medias (un pago o se
   registró o no; la verificación del punto 5 lo confirma).

9. **Manejo de error de negocio.** Los cortes del nodo 3 (saldo 0, exceso, medio incorrecto)
   y los errores de negocio de `registrar_pago` (`reserva_no_existe`, `payload_invalido`) se
   traducen a mensajes claros y accionables, distintos del error técnico.

---

## 14. Plan de validación en TEST

### 14.1 Datos ficticios
Reservas confirmadas con saldo pendiente (las del 9A sirven de base; agregar alguna con seña
$1 para el caso cliente-confianza). Todo en TEST, cabañas IDs 1-5.

### 14.2 Casos a probar
- Los seis casos del §9 (saldo efectivo, saldo transferencia, parcial, recargo 5%, cliente
  confianza, mixto).
- Casos de borde: saldo_real = 0 (debe cortar), monto > saldo (debe cortar/separar), dos
  parciales sucesivos (el saldo baja correctamente en cada uno), recargo 5% con medio
  efectivo (debe cortar).

### 14.3 Verificación
Correr las consultas del 9A (Q3, Q6) tras cada carga y confirmar que `saldo_real` baja
exactamente por el monto registrado, y que los `extra` aparecen separados (Q4) sin
contaminar la conciliación.

---

## 15. Decisiones registradas

| ID | Decisión |
|---|---|
| D-9B-01 | Co-responsabilidad contable de la capa (no solo UX). |
| D-9B-02 | Modelado del recargo 5%: línea `extra` separada, solo transferencia, sugerido por la capa, marcado `recargo_5_saldo_transferencia`. |
| D-9B-03 | Minimización de datos en el selector de reserva. |
| D-9B-04 | Alcance MVP: solo `saldo` y `extra` (5%); resto diferido. |
| D-9B-05 | Saldo calculado desde pagos confirmados, no `reservas.monto_saldo`. |
| D-9B-06 | Parciales permitidos como pagos confirmados por su monto exacto. |
| D-9B-07 | Riesgo de no-atomicidad de la anti-duplicación por capa **aceptado** para el MVP, documentado como riesgo conocido. |
| D-9B-08 | Medios visibles en el formulario MVP: solo `efectivo`, `transferencia_bancaria`, `transferencia_mp`. `mp_link`/`cripto` soportados por la base pero no expuestos. |
| D-9B-09 | Cobro mixto: se carga como dos operaciones separadas del formulario, no como dos llamadas en una misma ejecución (evita rollback parcial / respuesta compuesta). |
| D-9B-10 | Selector lista solo reservas con `saldo_real > 0` y estado `confirmada`/`activa`; no muestra reservas sin saldo ni históricas en el MVP. |

---

## 16. Lo que NO hace el 9B (alcance respetado)

No modifica schema, no modifica `registrar_pago()` ni `confirmar_reserva()`, no crea tablas,
no hace caja por lugar, no hace gastos, no hace liquidaciones, no maneja `ajuste`/`reembolso`,
no toca `cancelada_con_cargo`, no promueve pagos `en_revision`, no toca
AFIP/ARCA/IVA/MercadoPago/bancos/frontend/bot/WhatsApp/Airbnb/Booking. Solo registra pagos
posteriores (`saldo` y `extra` 5%) contra reservas existentes.

---

## 17. Artefactos y próximos pasos

**Este documento entrega:** el diseño de arquitectura completo del 9B para aprobación.

**Próximos pasos (tras aprobación):**
1. Cierre del diseño (aprobación de Franco).
2. Implementación bloque por bloque en TEST (recién ahí: SQL de saldo real, workflow n8n).
3. Validación en TEST con la batería del §14.
4. Promoción a OPS solo tras aprobación explícita.
5. Cierre formal `9B_CIERRE.md` + actualización de los seis satélites.
