# ARQUITECTURA_ETAPA_9B_COBRANZA_POSTERIOR.md

**Etapa:** 9B — Capa de cobranza posterior (corresponde al Bloque 1B del Carril A, Etapa 9)
**Estado:** ✅ Diseño v2 aprobado y cerrado — pendiente esqueleto 3a-v2. Satélites sin actualizar.
**Versión:** v2 (revisa el modelo de pago único de v1 → pago multi-porción)
**Tipo:** Documento de arquitectura (sin implementación, sin SQL ejecutable, sin workflow JSON)
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` (NO se modifica)
**Contratos leídos (read-only):** `registrar_pago(payload jsonb)` (1B-0) · `confirmar_reserva(payload jsonb)` (post-9A)
**Dependencia:** `9A_DIAGNOSTICO_INGRESOS.md` (diagnóstico read-only cerrado)
**Validación previa:** esqueleto 3a probado en TEST (multi-step confirmado — D-9B-13 OK)
**Entorno de diseño/validación:** TEST (`vita-delta-test`) — OPS solo tras aprobación explícita
**Autores:** Franco (titular) + Claude (arquitecto)
**Decisiones registradas:** D-9B-01 a D-9B-18

> Documento de diseño para revisión. **No implementa nada.** No actualiza satélites.
> Sin writes, sin DDL, sin workflow JSON, sin SQL ejecutable, sin OPS.

---

## 0. Qué cambia en la v2 (respecto del diseño v1 aprobado)

La v1 asumía **un pago por formulario** (y cobro mixto = dos cargas separadas, D-9B-09).
La operación real mostró que un mismo evento de cobranza puede combinar **varios medios a la
vez**, con recargo 5% solo sobre la porción de transferencia. La v2 reemplaza ese modelo por
un **formulario multi-porción** (hasta 3 porciones en una sola carga).

Cambios concretos:
- **D-9B-08 corregida:** medios visibles pasan a tres categorías de porción (efectivo /
  transferencia / otros).
- **D-9B-09 reemplazada:** un formulario puede registrar **varias líneas** de pago (hasta 5).
- **Nuevas:** D-9B-14 (multi-porción + 5% interno), D-9B-15 (monedas en pesos),
  D-9B-16 (fallo parcial informado), D-9B-17 (parciales en el tiempo), D-9B-18 (marcado de
  origen de la porción "otros").

El esqueleto 3a probado en TEST validó el patrón multi-step y las validaciones básicas con
**una porción**; sirvió para confirmar que el multi-step funciona (D-9B-13). Pero **queda
reemplazado** para el flujo final: la v2 exige un nuevo **`3a-v2` read-only multi-porción**
antes de cablear escritura. No se avanza a 3b hasta probar `3a-v2`.

---

## 1. Resumen ejecutivo

La Etapa 9B construye la **capa de cobranza posterior**: un formulario n8n (Form Trigger
multi-step, Basic Auth, usable desde celular) con el que el operador (Vicky/Rodrigo/Franco/Remo)
registra el saldo que se cobra **después** de confirmada la reserva — típicamente al ingresar
a la cabaña. Un mismo cobro puede combinar varias formas de pago, y la transferencia lleva un
recargo del 5%.

Llena el agujero medido en el diagnóstico 9A: **13 reservas con $1.245.000 de saldo** que el
sistema hoy no sabe registrar, porque solo conoce la seña inicial.

La capa **invoca `registrar_pago()` existente. No toca schema, no toca la función, no toca el
motor.** Toda la lógica nueva vive en la capa n8n y en el cálculo de saldo real.

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
- Registra log con `source_event`. Acepta `medio_pago` ∈ {efectivo, transferencia_bancaria,
  transferencia_mp, mp_link, cripto} y `moneda` (default ARS).

### 2.3 Qué viene de la lectura de `confirmar_reserva` (L-9A-01 confirmada)
- Al confirmar, ejecuta `UPDATE pagos SET id_reserva = v_id_reserva WHERE id_prereserva = ...`:
  rellena `id_reserva` en los pagos de la pre-reserva sin borrar `id_prereserva`.
- Por eso los pagos del flujo normal quedan con ambos IDs.
- **Consecuencia para 9B:** la cobranza posterior se registra **directamente contra
  `id_reserva`**, no contra `id_prereserva` (que para entonces está en estado `convertida`).

### 2.4 Qué viene de la prueba del esqueleto 3a (TEST)
- Multi-step confirmado: el Form Trigger + nodo Form `page` muestra una pantalla intermedia
  de resumen y espera la confirmación antes de continuar (D-9B-13 resuelta).
- El paso de datos entre nodos, el cálculo de saldo, la detección de ID inexistente, monto >
  saldo y 5% con efectivo funcionaron. La verificación confirmó que el esqueleto no escribió
  nada (`pagos` quedó en 14/0/0).
- Pendiente para la v2: el esqueleto validó **una porción**; falta validar **multi-porción**.

---

## 3. Principio de diseño: co-responsabilidad contable de la capa

### 3.1 El patrón 8B/8D y por qué acá NO aplica del todo
En 8B (reservas) y 8D (bloqueos), la función SQL del motor es la **única barrera**: valida
todo (existencia, fechas, conflictos), y el formulario es solo capa de UX y mensajería.

En 9B esto **no se cumple del todo**: `registrar_pago()` valida el formato del pago, pero
**no valida el saldo pendiente de la reserva** — no sabe cuánto se debe. Puede registrar un
saldo que duplica otro ya cobrado, o que excede lo adeudado, sin error.

### 3.2 Qué valida el motor vs qué debe validar la capa

| Validación | ¿La hace `registrar_pago`? | ¿La hace la capa 9B? |
|---|---|---|
| Reserva existe | ✅ (`reserva_no_existe`) | — |
| `tipo`/`medio` válidos | ✅ (CHECKs) | — |
| Montos > 0 / >= 0 | ✅ (CHECKs) | (la capa refuerza monto > 0) |
| Confirma si exacto | ✅ | (la capa fuerza exacto) |
| **Saldo pendiente real** | ❌ | ✅ |
| **No duplicar saldo** | ❌ | ✅ |
| **No exceder saldo (suma de porciones)** | ❌ | ✅ |
| **Separar saldo de recargo 5%** | ❌ | ✅ (interno) |

### 3.3 Responsabilidades que la capa asume (D-9B-01)
1. Calcular el saldo real antes de registrar.
2. Mostrarlo al operador.
3. Impedir registrar si la suma de porciones de saldo = 0.
4. Impedir que la suma de porciones de saldo supere el saldo real.
5. Calcular y separar internamente el recargo 5% de la(s) porción(es) de transferencia.
6. Recalcular y mostrar el saldo después de registrar.

> **D-9B-01 — Co-responsabilidad contable de la capa.** A diferencia de 8B/8D, en 9B la
> capa no es solo UX: como `registrar_pago()` no valida saldo, la capa es co-responsable de
> la integridad contable, asumiendo las seis responsabilidades anteriores.

---

## 4. Alcance del MVP

### 4.1 Entra en el MVP
- `tipo='saldo'` cobrado en una o varias porciones simultáneas (efectivo / transferencia / otros).
- `tipo='extra'` **exclusivamente** para recargo 5%, calculado y registrado **internamente**
  por la capa sobre la(s) porción(es) de transferencia.
- Cálculo de saldo real + validaciones anti-duplicación.
- Pagos parciales en el tiempo (varias cargas sobre la misma reserva hasta saldar).

> **D-9B-04 (actualizada) — Alcance MVP.** El MVP registra `saldo` (multi-porción) y `extra`
> (recargo 5% interno). Todo lo demás se difiere.

### 4.2 Fuera del MVP (diferido)
`ajuste`, `reembolso`, caja por lugar, gastos, liquidaciones, `cancelada_con_cargo`,
promoción de pagos `en_revision`, **tabla de conversión de monedas / ahorro** (ver §5.4 y
pendientes), y toda integración externa (AFIP/ARCA/IVA, MercadoPago automático, bancos,
frontend, bot, WhatsApp, Airbnb/Booking).

---

## 5. Cálculo del saldo real y modelo de porciones

### 5.1 Fórmula del saldo real
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
El recargo (`tipo='extra'`) **no** entra en el cálculo de saldo: no reduce lo adeudado.

### 5.2 Por qué NO se usa `reservas.monto_saldo` como saldo vivo (D-9B-05)
`confirmar_reserva` fija `monto_saldo = monto_total − monto_sena` **una sola vez** en el alta
y nunca lo recalcula; ningún trigger lo actualiza; la columna no es generada (L-9A-02). Es
**referencia documental/inicial**, no saldo vivo. El saldo vivo siempre se calcula desde los
pagos confirmados.

> **D-9B-05 — Saldo calculado, no documental.** El saldo pendiente operativo se calcula
> desde pagos confirmados (`sena`+`saldo`). `reservas.monto_saldo` queda como referencia.

### 5.3 Modelo de porciones (D-9B-14)
Un evento de cobranza se compone de hasta **tres porciones**, cada una opcional:

| Porción | Medio | ¿Recargo 5%? | Líneas que genera |
|---|---|---|---|
| Efectivo | `efectivo` | No | 1 línea `saldo` |
| Transferencia | `transferencia_bancaria` **o** `transferencia_mp` | **Sí** | 1 línea `saldo` + 1 línea `extra` (5% de esa porción) |
| Otros | a registrar como `efectivo` en ARS, **marcado `medio_original`** (ver §5.4) | No | 1 línea `saldo` |

Reglas del modelo:
- El **recargo 5% se calcula y registra internamente** por la capa sobre el monto de la
  porción de transferencia. El operador **no** carga el extra a mano: ingresa cuánto saldo
  paga por transferencia y la capa agrega el 5% por encima (registra `saldo` por el monto y
  `extra` por el 5%). El recargo solo se agrega cuando la porción de transferencia es > 0.
- La **suma de las porciones de saldo** (efectivo + transferencia + otros) es lo que reduce
  el saldo real; debe ser > 0 y ≤ saldo_real.
- Un evento puede generar entre 1 y 5 líneas de pago según qué porciones se usen
  (3 porciones de saldo + hasta 2 recargos si hubiera dos tipos de transferencia; en la
  práctica una sola porción de transferencia → máximo 4 líneas).

Ejemplo (caso real de Franco): saldo pendiente $350.000. Cobro: $150.000 efectivo +
$200.000 transferencia. La capa registra:
- `saldo` $150.000 efectivo
- `saldo` $200.000 transferencia
- `extra` $10.000 transferencia (5% de $200.000, marcado `recargo_5_saldo_transferencia`)

Saldo cubierto: $350.000 → reserva saldada. El cliente entregó $360.000 ($350.000 saldo +
$10.000 recargo).

> **D-9B-14 — Modelo multi-porción con 5% interno.** El formulario captura hasta 3 porciones
> (efectivo / transferencia / otros) en una sola carga. El recargo 5% se calcula y registra
> internamente como línea `extra` separada, solo sobre la(s) porción(es) de transferencia
> (bancaria o MP). El operador ingresa el saldo que paga por transferencia; la capa agrega el
> 5% por encima. Reemplaza a D-9B-09 (un pago por formulario).

### 5.4 Monedas: todo en pesos en el MVP, con marcado de origen (D-9B-15)
El saldo de la reserva está en ARS. En el MVP, **todo pago se registra en pesos**:
- Pagos en dólares, cripto u otra forma → el operador ingresa el **equivalente en pesos** y se
  registra como porción "otros" que reduce el saldo.
- La capa **no** hace conversión de divisa ni la persiste como tal en el MVP.

**Marcado obligatorio del origen (evita contaminar la caja efectivo):** aunque la porción
"otros" se registre técnicamente con `medio_pago='efectivo'` (porque entra al saldo en ARS),
**no es efectivo ARS puro**. Por eso debe quedar marcado obligatoriamente en `notas` y
`source_event` con el origen real:
- `medio_original=USD`
- `medio_original=cripto`
- `medio_original=otro`

Además, si `monto_otros > 0`, la **descripción de "otros" es obligatoria** (ej. "USD",
"USDT", "pago en especie"). Esto permite que la futura caja/contabilidad distinga un cobro en
dólares registrado en pesos de un cobro genuinamente en efectivo ARS.

Pendiente explícito (fuera del 9B, ver §17): a futuro habrá una **tabla de conversión de
monedas / ahorro** en la contabilidad, que lea de `pagos` (en ARS, con su `medio_original`) y
registre el equivalente en USD/cripto cuando el negocio cambie pesos a otra moneda. Este
formulario eventualmente deberá alimentarla, pero **no se diseña ni construye ahora** (es etapa
de contabilidad posterior, schema nuevo, Carril B).

> **D-9B-15 — Monedas en pesos en el MVP, con marcado de origen.** Pagos en dólares/cripto/otros
> se registran por su equivalente en ARS (porción "otros", técnicamente `medio_pago='efectivo'`),
> pero **marcados obligatoriamente** en `notas`/`source_event` como `medio_original=USD|cripto|otro`,
> y con descripción obligatoria si `monto_otros > 0`. Esto evita contaminar la caja efectivo. La
> conversión y la tabla de ahorro son contabilidad posterior, fuera del 9B, anotadas como pendiente.

### 5.5 Parciales en el tiempo (D-9B-17)
Como el saldo se calcula (no es estático) y el listado muestra reservas con `saldo_real > 0`,
una reserva puede cobrarse en **varias cargas a lo largo del tiempo**: el cliente paga una
parte hoy, la capa registra esas porciones, el saldo baja, y la reserva **sigue apareciendo
en el listado** con lo que falta hasta llegar a $0. Cada carga es un evento independiente que
puede tener sus propias porciones.

> **D-9B-17 — Parciales en el tiempo.** Una reserva puede cobrarse en varias cargas sucesivas
> hasta saldar. El formulario no "cierra" la reserva; el saldo calculado refleja el acumulado
> y la reserva permanece en el listado mientras `saldo_real > 0`.

---

## 6. Flujo operativo de la capa (paso a paso)

1. **Listado HTML interno** (pieza separada, obligatoria — D-9B-12): el operador ve las
   reservas con saldo y copia el `#ID` de la que va a cobrar.
2. **Formulario — captura de porciones:** el operador ingresa el `id_reserva` y hasta 3
   porciones (efectivo / transferencia / otros), cada una con su monto. Marca el tipo de
   transferencia (bancaria o MP) si usa esa porción.
3. **Consulta de saldo real** de la reserva (§5.1).
4. **Validación de capa:** ID existe; suma de porciones de saldo > 0 y ≤ saldo_real; cada
   monto > 0. Calcula internamente el recargo 5% de la porción de transferencia.
5. **Pantalla de resumen + confirmar:** muestra el desglose completo y espera confirmación:
   - Saldo actual.
   - Cada porción que reduce saldo (efectivo / transferencia / otros), con su monto.
   - **Suma total que reduce saldo.**
   - **Recargo 5% separado** (si hubo transferencia).
   - **Total que entrega/paga el cliente** (suma de saldo + recargo).
   - **Saldo proyectado después.**

   Ejemplo:
   ```
   Saldo actual:               $350.000
   Efectivo:                   $150.000
   Transferencia:              $200.000
   Recargo 5%:                  $10.000
   Total que reduce saldo:     $350.000
   Total que paga el cliente:  $360.000
   Saldo proyectado:                 $0
   ```
6. **Registro** vía `registrar_pago()` — una llamada por línea (§8), `estado_inicial='confirmado'`,
   `monto_esperado = monto_recibido`, contra `id_reserva`.
7. **Verificación del resultado real:** releer los pagos creados y confirmar que quedaron
   `confirmado` (no confiar en `ok:true` — lección 8B).
8. **Recálculo y visualización** del nuevo saldo_real al operador.

---

## 7. Campos del formulario

### 7.1 Completa el operador
- `id_reserva` (copiado del listado).
- **Porción efectivo:** monto (opcional, default 0).
- **Porción transferencia:** monto (opcional, default 0) + tipo de transferencia
  (`transferencia_bancaria` / `transferencia_mp`).
- **Porción otros:** monto en pesos equivalente (opcional, default 0) + **tipo de origen
  obligatorio si monto > 0** (`USD` / `cripto` / `otro`) + descripción obligatoria si monto > 0
  (ej. "USDT", "pago en especie").
- `validado_por`.
- `notas` (opcional).

> **D-9B-08 (corregida) — Porciones visibles en el formulario.** El formulario expone tres
> porciones: efectivo, transferencia (con subtipo bancaria/MP), y "otros" (dólares/cripto/etc,
> ingresados por su equivalente en pesos). `mp_link` queda soportado por la base pero no
> expuesto en el MVP.

### 7.2 Arma la capa automáticamente
Por cada porción usada: `tipo` (`saldo`), `medio_pago` (según la porción), `monto_esperado` (=
monto de la porción), `estado_inicial` (`confirmado`), `source_event` (generado), `id_reserva`.
Para la porción de transferencia: además una línea `extra` con el 5%, `monto_esperado =
monto_recibido = recargo`, marcado `recargo_5_saldo_transferencia` en `source_event` y `notas`.

### 7.3 Mapeo porción → líneas de `registrar_pago`
| Porción del formulario | Líneas generadas | medio_pago | tipo |
|---|---|---|---|
| Efectivo $X | 1 | `efectivo` | `saldo` |
| Transferencia $Y (bancaria/MP) | 2 | `transferencia_bancaria`/`_mp` | `saldo` ($Y) + `extra` (5% de $Y) |
| Otros $Z (equiv. ARS) | 1 | `efectivo` + `medio_original=USD\|cripto\|otro` en notas/source | `saldo` |

---

## 8. Tratamiento del recargo 5%

### 8.1 Cuándo aplica
**Solo sobre la porción que entra por transferencia bancaria o Mercado Pago.** Efectivo y
"otros" no llevan recargo. Ambos tipos de transferencia (bancaria y MP) cargan el 5% por igual.

### 8.2 Cálculo
La capa calcula el 5% **sobre el monto de la porción de transferencia de esa carga** (no sobre
el saldo total ni sobre las otras porciones). Ejemplo: porción transferencia $200.000 → recargo
$10.000. El operador ingresa el saldo que paga por transferencia; la capa agrega el 5% por
encima automáticamente (no lo carga el operador).

### 8.3 Registro como línea separada
Se registra como un pago **`tipo=extra` aparte**, mismo `medio_pago` de transferencia,
`monto_esperado = monto_recibido = importe del recargo`, `estado_inicial=confirmado`.
**No se suma dentro del saldo** — eso rompería la conciliación de alojamiento (§5).

### 8.4 Marcado automático
- En `source_event`: identificador distintivo que incluye `recargo_5_saldo_transferencia`.
- En `notas`: etiqueta `recargo_5_saldo_transferencia`.

> **D-9B-02 (actualizada) — Modelado del recargo 5%.** Aplica solo a la porción de
> transferencia (bancaria o MP, por igual). Se calcula internamente sobre el monto de esa
> porción y se registra como línea `extra` separada, nunca dentro del saldo. El operador no
> carga el extra a mano. Marcado en `source_event` y `notas` como `recargo_5_saldo_transferencia`.
> (Su tratamiento en liquidación — repartible o no — queda abierto en el Carril B: "entrada
> real de caja, no necesariamente ingreso repartible".)

---

## 9. Mapeo de casos reales al modelo

| Caso real | Porciones | Líneas registradas |
|---|---|---|
| Saldo todo efectivo | efectivo = saldo | 1 `saldo` efectivo |
| Saldo todo transferencia | transferencia = saldo | `saldo` + `extra` (5%) |
| Saldo mixto (efectivo + transferencia) | ambas | `saldo` efectivo + `saldo` transf + `extra` |
| Saldo parcial hoy, resto después | una porción ahora, otra carga luego | una/s línea/s por carga (D-9B-17) |
| Pago en dólares/cripto | porción "otros" (equiv. ARS) | 1 `saldo` efectivo en ARS (D-9B-15) |
| Cliente confianza, casi todo al llegar | seña $1 (8B) + porciones posteriores | seña + saldos posteriores |

Todas las líneas confirman porque la capa fuerza `recibido=esperado` y `estado_inicial=confirmado`.
**Cero `en_revision`** en el flujo de cobranza posterior.

---

## 10. Validaciones de la capa (detalle)

### 10.1 Sobre las porciones
- Cada monto de porción: numérico y ≥ 0 (las porciones en 0 se ignoran).
- Al menos una porción de saldo > 0 (no se registra un evento vacío).
- **Suma de porciones de saldo** (efectivo + transferencia + otros) ≤ saldo_real.
- Porción de transferencia: si > 0, exige subtipo (`transferencia_bancaria` o `transferencia_mp`)
  y dispara el cálculo del recargo 5%.
- Porción "otros": `monto_otros >= 0`; si `monto_otros > 0` exige **tipo de origen**
  (`USD`/`cripto`/`otro`) y **descripción** obligatorios; "otros" **no genera recargo**; "otros"
  reduce saldo por el equivalente ARS informado; se marca `medio_original` en notas/source.

### 10.2 Reglas duras
- Impedir registrar si saldo_real = 0.
- Impedir si la suma de porciones de saldo = 0.
- Impedir si la suma de porciones de saldo > saldo_real.
- Monto de cualquier porción no numérico o < 0 → corte.

### 10.3 Qué NO valida la capa (lo cubre el motor)
Existencia de la reserva, validez de `tipo`/`medio` (CHECKs), montos > 0 / >= 0. La capa no
duplica esas validaciones; confía en el motor para ellas.

---

## 11. Privacidad y minimización de datos (D-9B-03)

### 11.1 Listado y selección de reserva
El **listado HTML interno** lista solo reservas con `saldo_real > 0` y estado `confirmada` o
`activa` (D-9B-10); muestra ID, cabaña, fechas y saldo. **No muestra** DNI, email, teléfono ni
notas; tampoco nombre de huésped en el MVP (se evaluará agregar nombre corto solo si hay riesgo
de confusión entre reservas similares).

### 11.2 Público Basic Auth
Operativo (Vicky/Rodrigo/Franco/Remo). No es un público amplio.

### 11.3 Datos sensibles fuera de GitHub
Montos, recargos y cualquier cifra real no se documentan con valores reales en el repositorio.

> **D-9B-03 — Minimización de datos en el listado/selector.** Expone solo lo necesario para
> operar (ID, cabaña, fechas, saldo); nunca DNI, email, teléfono ni notas.

---

## 12. Riesgos conocidos

### 12.1 No-atomicidad de la anti-duplicación por capa (D-9B-07)
La protección anti-duplicación vive en la capa, no en el schema. **No es atómica**: dos
operadores cargando el mismo saldo casi simultáneamente podrían ambos pasar la validación
antes de que cualquiera inserte, y duplicar. **Riesgo aceptado para el MVP** (uso interno,
pocos operadores, baja concurrencia, cobranza presencial). Salida futura: índice único parcial
de idempotencia o función transaccional.

### 12.2 Fallo parcial al registrar varias líneas (D-9B-16)
Como un evento genera varias líneas (varias llamadas a `registrar_pago`), una puede fallar
después de que otra se registró. **No se auto-revierte.** La capa informa qué línea se registró
y cuál falló, y dirige al operador a verificar el saldo real con el listado antes de reintentar.
Esto es seguro porque el saldo se calcula desde los pagos confirmados: el listado siempre
refleja la verdad, sin estado inconsistente que reconciliar.

Orden de registro recomendado: **primero las porciones no recargadas (efectivo, otros), al
final la transferencia con su recargo**, para que un corte deje la situación más simple de
identificar y rehacer.

> **D-9B-16 — Fallo parcial informado, sin auto-revertir.** Si al registrar varias líneas una
> falla, la verificación posterior (N6) lista las líneas registradas correctamente, las que
> fallaron, y el saldo recalculado; N8 entrega ese detalle con instrucción explícita de no
> reintentar sin revisar el listado o avisar a Franco. Mensaje **no genérico**. El saldo
> calculado garantiza que no haya estado inconsistente. Orden: no-recargado primero,
> transferencia+recargo al final.

### 12.3 Dependencia permanente de la normalización
No es un riesgo, es una característica: la seña vive con ambos IDs y el saldo posterior con
`id_reserva`. Todo reporte contable depende de `COALESCE(id_reserva, vía_prereserva)`.

### 12.4 Menores
- El operador podría confundir el medio de una porción → afecta el recargo. Mitigación: el 5%
  solo se calcula sobre la porción explícitamente marcada como transferencia.
- Porción "otros" en pesos mal convertida por el operador → es responsabilidad del operador en
  el MVP (la conversión asistida es pendiente, §5.4).

---

## 13. Topología técnica de la capa (nivel medio, sin implementar)

> Flujo técnico previsto, no implementación. Sin JSON ni SQL ejecutable. La pieza es **dos
> workflows**: listado HTML (read-only) + formulario multi-step.

**Pieza 1 — Listado HTML interno** (read-only): trigger Basic Auth → SELECT de reservas con
saldo (con fila centinela para no cortar si está vacío) → arma tabla HTML escapada → muestra.

**Pieza 2 — Formulario multi-porción** (multi-step):

1. **N1 — Form Trigger (datos del cobro).** Captura `id_reserva` y las tres porciones
   (efectivo / transferencia + subtipo / otros), `validado_por`, `notas`. Basic Auth.
2. **N2 — Consulta de saldo real.** SELECT parametrizado por `id_reserva`. **Siempre devuelve
   una fila** (fila sintética + LEFT JOIN + flag `reserva_encontrada`), para no cortar la
   cadena si el ID no existe.
3. **N3 — Validación de capa + armado de líneas.** Verifica ID existe (flag), suma de porciones
   de saldo > 0 y ≤ saldo_real, montos válidos. Calcula el recargo 5% de la porción de
   transferencia. Arma la **lista de líneas** a registrar (entre 1 y 4). Emite también campos
   `*_html` ya escapados para el resumen. Si algo falla → deriva a error de negocio (N9).
4. **N4 — Resumen + Confirmar** (Form `page`). Muestra el desglose completo: saldo actual,
   cada porción que reduce saldo, suma total que reduce saldo, recargo 5% separado, total que
   paga el cliente, y saldo proyectado (formato del §6 paso 5). Espera confirmación. HTML con
   campos pre-escapados.
5. **N5 — Registro de líneas.** Por cada línea armada en N3, una llamada a `registrar_pago()`
   (`vita_supabase_test` en TEST). Orden: no-recargado primero, transferencia+recargo al final
   (D-9B-16). `estado_inicial=confirmado`, `monto_esperado=monto_recibido`.
6. **N6 — Verificación posterior.** Relee los pagos creados; confirma `estado=confirmado` de
   cada uno; recalcula saldo. Arma un **detalle operativo**: lista de líneas registradas
   correctamente (con id_pago, tipo, medio, monto), lista de líneas que fallaron, y el saldo
   recalculado. Si alguna línea no quedó confirmada o falló → marca fallo parcial y pasa ese
   detalle a N8.
7. **N7 — Respuesta humana (éxito).** Mensaje claro: líneas registradas, saldo anterior →
   nuevo, recargo si hubo.
8. **N8 — Error técnico**, con la distinción de zona y mensaje **no genérico**:
   - Falla **antes** de N5 → "No se registró nada. Reintentá."
   - Falla **en/después** de N5 (fallo parcial) → mensaje operativo que lista:
     - líneas registradas correctamente (tipo, medio, monto);
     - líneas que fallaron (tipo, medio, monto);
     - saldo recalculado de la reserva;
     - instrucción explícita: **"No reintentes esta carga sin revisar primero el saldo de la
       reserva #X en el listado, o avisá a Franco, para no duplicar el pago."**
9. **N9 — Error de negocio.** Cortes de N3 (ID inexistente, suma 0, suma > saldo, monto
   inválido) y errores de negocio de `registrar_pago`. Mensajes claros y accionables.

---

## 14. Plan de validación en TEST

### 14.1 Datos ficticios
Reservas confirmadas con saldo (las del 9A); agregar alguna con seña $1 para el caso
cliente-confianza. Todo en TEST, cabañas IDs 1-5.

### 14.2 Casos a probar
- Una sola porción: efectivo; transferencia (verifica recargo 5% interno); otros.
- Multi-porción: efectivo + transferencia (el caso de los $350.000); efectivo + transferencia + otros.
- Parcial en el tiempo: cobrar parte, verificar que la reserva sigue en el listado con el resto, cobrar el resto.
- Bordes: saldo_real = 0 (corta), suma de porciones > saldo_real (corta), monto de porción < 0
  o no numérico (corta), porción transferencia con recargo bien calculado.
- Fallo parcial simulado (si se puede inducir): confirmar que N8 informa qué entró y qué no.

### 14.3 Verificación
Tras cada carga, correr las consultas del 9A (saldo real / Q3 / Q4) y confirmar: el saldo baja
exactamente por la suma de porciones de saldo; los `extra` (recargo) aparecen separados sin
contaminar la conciliación; cero `en_revision`.

---

## 15. Decisiones registradas

| ID | Decisión |
|---|---|
| D-9B-01 | Co-responsabilidad contable de la capa (no solo UX). |
| D-9B-02 | Recargo 5%: solo porción de transferencia (bancaria/MP por igual), calculado interno, línea `extra` separada, marcado `recargo_5_saldo_transferencia`. **(actualizada v2)** |
| D-9B-03 | Minimización de datos en el listado/selector. |
| D-9B-04 | Alcance MVP: `saldo` multi-porción + `extra` (5% interno); resto diferido. **(actualizada v2)** |
| D-9B-05 | Saldo calculado desde pagos confirmados, no `reservas.monto_saldo`. |
| D-9B-06 | Parciales permitidos como pagos confirmados por su monto exacto. |
| D-9B-07 | Riesgo de no-atomicidad de la anti-duplicación por capa, aceptado para el MVP. |
| D-9B-08 | Porciones visibles: efectivo / transferencia (bancaria/MP) / otros. `mp_link` no expuesto. **(corregida v2)** |
| D-9B-09 | ~~Cobro mixto = dos operaciones separadas.~~ **Reemplazada por D-9B-14.** |
| D-9B-10 | Listado solo reservas con `saldo_real > 0` y estado `confirmada`/`activa`. |
| D-9B-11 | `id_reserva` es valor interno; el operador elige opción legible / copia el #ID del listado. |
| D-9B-12 | Listado HTML interno obligatorio en el MVP (mecanismo principal de selección); selector dinámico nativo descartado (dropdown estático). Calendario operativo sin tocar. |
| D-9B-13 | Multi-step confirmado viable (probado en 3a). Fallback de dos workflows como red de seguridad. |
| D-9B-14 | Modelo multi-porción (hasta 3) con recargo 5% interno sobre transferencia. Reemplaza D-9B-09. |
| D-9B-15 | Monedas en pesos en el MVP; conversión/tabla de ahorro como pendiente fuera del 9B. |
| D-9B-16 | Fallo parcial informado, sin auto-revertir; verificación por listado; orden no-recargado→transferencia. |
| D-9B-17 | Parciales en el tiempo: varias cargas sobre la misma reserva hasta saldar. |
| D-9B-18 | Porción "otros" (USD/cripto/otro): se registra en ARS como `efectivo` pero marcada obligatoriamente `medio_original` en notas/source + descripción obligatoria si monto > 0, para no contaminar la caja efectivo. |

---

## 16. Lo que NO hace el 9B (alcance respetado)

No modifica schema, no modifica `registrar_pago()` ni `confirmar_reserva()`, no crea tablas,
no hace caja por lugar, no hace gastos, no hace liquidaciones, no maneja `ajuste`/`reembolso`,
no hace conversión de divisas ni tabla de ahorro, no toca `cancelada_con_cargo`, no promueve
pagos `en_revision`, no toca AFIP/ARCA/IVA/MercadoPago/bancos/frontend/bot/WhatsApp/Airbnb/Booking.
Solo registra pagos posteriores (`saldo` multi-porción y `extra` 5%) en pesos contra reservas
existentes.

---

## 17. Artefactos, pendientes y próximos pasos

**Este documento entrega:** el diseño de arquitectura v2 del 9B (modelo multi-porción) para
aprobación.

**Pendientes registrados para el Carril B / contabilidad posterior:**
- Tabla de conversión de monedas / ahorro que lea de `pagos` (ARS) y registre el equivalente
  en USD/cripto cuando el negocio cambie moneda. Este formulario deberá alimentarla a futuro.

**Próximos pasos (tras aprobación de esta v2):**
1. Cierre del diseño v2 (aprobación de Franco).
2. **El esqueleto 3a anterior queda reemplazado.** Sirvió para validar el multi-step simple
   (una porción), pero el flujo final usa un nuevo **`3a-v2` read-only multi-porción**.
   Rediseñarlo y probarlo en TEST (multi-step con varias porciones, sin escritura).
   **No avanzar a 3b hasta probar `3a-v2`.**
3. Cableado de escritura (3b): `registrar_pago` por línea + verificación posterior operativa
   (N6/N8, D-9B-16) + manejo de fallo parcial, solo en TEST.
4. Batería de validación del §14.
5. Promoción a OPS solo tras aprobación explícita.
6. Cierre formal `9B_CIERRE.md` + actualización de los seis satélites.
