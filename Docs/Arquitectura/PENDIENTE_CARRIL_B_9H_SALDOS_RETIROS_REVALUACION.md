# PENDIENTE_CARRIL_B_9H_SALDOS_RETIROS_REVALUACION.md — Cuenta corriente interna de socios (alcance posterior)

**Etapa:** 9H — *Cuenta corriente interna de socios* (capa **posterior** a la liquidación). Carril B.
**Estado:** 🅿️ **PENDIENTE EXPLÍCITO — encuadrado, NO implementado.** No es diseño, no es schema, no es cierre.
**Tipo:** Breadcrumb de alcance. Registra un subsistema posterior detectado durante 9C, para no perderlo ni mezclarlo con 9C.
**No toca:** 9C (catálogo/zonas/titularidad), ni el canónico `6B_SCHEMA_SQL.md`, ni los seis satélites, ni OPS. Se foldea en el cierre formal del Carril B.
**Depende de (para poder diseñarse algún día):** 9G (cascada read-only que produce el saldo por socio del período).
**Autores:** Franco + Claude.

> Detectado en 9C: después de liquidar mes a mes, existe una capa posterior de **saldos internos, retiros/cobros de socios y eventual conversión ARS→USD**. Se documenta acá como alcance posterior del Carril B, sin frenar 9C y sin diseñarse todavía.

---

## 1. Por qué es una capa aparte (y posterior)

Dos mundos del Carril B que no se cruzan:

- **Mundo derivado (9C–9G):** todo se computa desde primitivas (catálogo, valor relativo, activación, gastos, pagos). Cambiás una primitiva → se re-deriva. Nada se congela, salvo los snapshots al final.
- **Mundo con estado (esta etapa, 9H):** saldos que **se acumulan**, retiros que son **movimientos**, conversiones que son **eventos fechados**. Modelo append-only e inmutable.

Son modelos de consistencia distintos. Por eso 9H va **después de 9G** y nunca dentro de 9C.

---

## 2. Alcance (lo que abarca 9H)

1. **La liquidación calcula el saldo de cada socio por período** (salida de 9G).
2. **Si no se retira, el saldo puede acumularse** período a período.
3. **Cuando un socio cobra, se registra un retiro/pago contra su saldo.**
4. **Conversión ARS→USD opcional:** si se decide convertir un saldo ARS acumulado a USD en una fecha, se registra como **evento posterior con tipo de cambio y fecha, sin recalcular la contabilidad original**.

---

## 3. Tres bloques, en orden (conceptual, sin diseñar)

1. **Persistencia de liquidación (snapshots).** Congelar el saldo mensual por socio.
   - *Es la base, no un extra:* acumular saldos **re-derivables** sería inseguro (un cambio retroactivo en una primitiva corrompería el acumulado). Se acumulan **snapshots congelados**.
   - Acá aterriza la protección contra "reescribir historia" señalada en 9C §4.
2. **Mayor / cuenta corriente de socios + retiros.** El saldo congelado de cada período entra como **haber**; cada cobro/retiro es un **movimiento (debe)**. Saldo vivo = acumulado − retirado. **Append-only**: no se editan saldos, se registran movimientos y se deriva el saldo.
3. **Revaluación / conversión ARS→USD.** Evento **fechado con tipo de cambio** sobre un saldo acumulado. **No recalcula** la contabilidad original: el ARS queda intacto; el USD es una valuación en un punto del tiempo. Es **revaluación, no re-contabilización**.

---

## 4. Invariantes (no negociables)

- 9H **solo lee** salidas **congeladas** de liquidación y **registra sus propios movimientos**.
- 9H **NUNCA** modifica `valor_relativo`, beneficiarios, zonas ni activación operativa. Esos viven en el mundo derivado/catálogo (9C–9D).
- La conversión ARS→USD es **valuación interna entre socios**, separada por completo del FX **fiscal/AFIP**. El muro interno↔fiscal sigue en pie.
- Movimientos (retiros, revaluaciones) son **eventos inmutables**, no ediciones.

---

## 5. Reubicación del viejo "9H complementarias"

Este breadcrumb consolida y limpia lo que antes era un cajón heterogéneo:

| Ítem del viejo 9H | Destino |
|---|---|
| Snapshots de liquidación | **9H, bloque 1** (base de esta etapa) |
| Estado de saldado | **9H, bloque 2** (mayor + retiros) |
| FX / conversión contable | **9H, bloque 3** (revaluación ARS→USD) |
| Cancelaciones con cargo | Fuera de 9H → relacionado con ingreso (encuadrar aparte) |
| Motor de valor/hora | Fuera de 9H → mejora de **9F** (gasto/horas) |
| Precisión diaria / pro-rata de la matriz | Fuera de 9H → mejora de **9D/9E** (matriz) |

---

## 6. Frontera con 9G (qué SÍ es de corto plazo)

- **9G (read-only):** puede mostrar el **saldo del período + saldado sí/no** como reporting básico. Esto sí está permitido ya, como estado/reporting.
- **9H (persistente):** el mayor acumulado con retiros y revaluación. Posterior, no ahora.

---

## 7. Qué NO hacer todavía

No diseñar ni implementar nada de 9H: ni snapshots, ni mayor, ni retiros, ni FX. No frena 9C. No se promueve a OPS. No se actualiza el canónico ni los satélites por este breadcrumb. Se retoma como sub-etapa propia recién después de 9G, con su propio diseño conceptual → schema → TEST → (eventual) promoción coordinada del Carril B.

---

**Fin del breadcrumb 9H.** Registro de alcance posterior, sin diseño y sin mezcla con 9C.
