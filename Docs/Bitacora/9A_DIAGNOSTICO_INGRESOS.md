# 9A_DIAGNOSTICO_INGRESOS.md — Diagnóstico read-only de ingresos y saldos

**Etapa:** 9 — Contabilidad operativa interna (Carril A, Bloque 1A)
**Estado:** ✅ Versión final aprobada como cierre conceptual del Bloque 1A — satélites aún sin actualizar
**Tipo:** Diagnóstico read-only (solo lectura, sin escritura, sin cambio de schema)
**Entorno de ejecución:** TEST (`vita-delta-test`) — gate de entorno confirmado (cabañas IDs 1-5)
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` (sin modificar)
**Contrato leído (read-only):** `registrar_pago(payload jsonb)` — Bloque 1B-0
**Autores:** Franco (titular) + Claude (arquitecto)
**Alcance respetado:** sin OPS, sin writes, sin DDL, sin workflow, sin diseño de liquidación

> Este documento es la **versión final del Bloque 1A**, aprobada como cierre conceptual.
> Todavía **no actualiza los seis satélites** (`ESTADO_ACTUAL`, `DECISIONES_NO_REABRIR`,
> `Lecciones_Aprendidas`, `Pendiente_pre_produccion`, `CLAUDE`, `README`): esa
> actualización queda pendiente de instrucción explícita de Franco.

---

## 1. Objetivo del bloque

Producir una foto de solo lectura del dinero ya registrado en el sistema, para responder
con números verificables: cuánto se facturó, cuánto entró, por qué medio, cuánto falta
cobrar, y —sobre todo— **dónde el modelo actual no representa el flujo real del negocio**.

El diagnóstico es deliberadamente no comprometedor: no cierra decisiones de liquidación
(Carril B), no escribe nada, y su salida es regenerable. Su valor real terminó siendo
**cuantificar el agujero**: medir el monto de cobranza que el sistema no registra.

---

## 2. Metodología

- Set de 10 consultas diagnósticas (Q1–Q10) + consulta de asociación (Q0) + controles.
- Todas `SELECT`. Introspección de catálogo donde hizo falta (contrato, enums, constraints).
- **CTE `pagos_reserva_normalizados`**: cada pago se atribuye a una sola reserva por
  `COALESCE(id_reserva, reserva_vía_id_prereserva)`. Resolución por fila → sin duplicación.
  Usada en Q3, Q4, Q5, Q6, Q10.
- Fórmula de saldo aprobada (Reglas 1–3 del Carril A):

  ```
  saldo_real = reservas.monto_total
             − SUM(pagos confirmados WHERE tipo IN ('sena','saldo'))
  ```

  `reservas.monto_saldo` se conserva solo como **referencia documental/inicial**, nunca
  como saldo vivo (validado: `registrar_pago` no actualiza `reservas.monto_saldo`; no hay
  trigger que lo recalcule; la columna no es generada).

---

## 3. Estado de los datos en TEST (universo del diagnóstico)

- **14 pagos** totales, **todos tipo `sena`, todos `confirmado`.**
- **13 reservas** confirmadas + 1 pago residuo de prueba manual (no atribuido a reserva).
- **0 pagos** de tipo `saldo`, `extra`, `ajuste`, `reembolso`.
- **0 pagos** en estados `pendiente` / `en_revision` / `rechazado` / `reembolsado`.
- Medios de pago observados: `transferencia_bancaria` (13 señas) y `efectivo` (1 seña).

---

## 4. Hallazgo central

**El sistema registra la seña inicial de alta y NADA del ciclo de cobranza posterior.**

No es una sospecha: son **0 pagos de tipo `saldo` sobre 13 reservas con saldo pendiente**.
El saldo nunca se registró como pago en ninguna reserva.

Consecuencias medidas:

- **Conciliación cuadra hoy** (`saldo_real` = `saldo_documental` en las 13 reservas), pero
  **solo por ausencia de cobranza**: las dos formas de medir el saldo no pueden divergir
  todavía porque no hay pagos de saldo. Divergirán recién cuando se registre el primer
  pago de saldo (es decir, después del Bloque 1B).
- **La caja de efectivo no está representada de forma significativa todavía**: solo hay
  una seña en efectivo ($50.000), y el flujo principal de efectivo —saldos al ingreso— no
  se registra.
- Los mecanismos para `extra` (recargo 5%), `ajuste` y `reembolso` **existen** en el CHECK
  de `pagos.tipo` pero **nunca se usaron**.

Esto confirma con datos la conclusión del Bloque 1B: **la cobranza posterior es
prerrequisito de la contabilidad de ingresos.** Un reporte de ingresos hecho hoy mostraría
solo señas, subvaluando el ingreso real en casi exactamente la mitad.

---

## 5. Números agregados (TEST)

| Métrica | Valor |
|---|---|
| Reservas confirmadas | 13 |
| Total facturado (`monto_total`) | $2.350.000 |
| Cobrado de alojamiento (señas confirmadas, atribuidas) | $1.105.000 |
| Saldo real pendiente total | $1.245.000 |
| Verificación de cuadre | 1.105.000 + 1.245.000 = 2.350.000 ✅ |
| Pagos totales | 14 (13 atribuidos + 1 residuo) |
| Efectivo confirmado | $50.000 (1 seña, reserva 11) |

**Cuadre pago por pago (control):** 13 señas atribuidas 1:1 a las 13 reservas
(suma $1.105.000 = `cobrado_alojamiento` de Q3) + 1 pago residuo `id_pago=5` ($100.000,
sin reserva, prueba manual conocida) = 14. Cero descuadre.

---

## 6. Resultados por consulta

| Consulta | Resultado | Lectura |
|---|---|---|
| Q0 | 13 `3_ambos` + 1 residuo `solo_prereserva` | Flujo normal puebla ambos campos; CTE obligatoria |
| Q1 | 14 señas (13 transferencia + 1 efectivo), 0 de otros tipos | Solo señas en el sistema |
| Q2 | 13 confirmadas, $2.350.000 facturado | Universo de reservas |
| Q3 | 13 reservas, saldo_real = saldo_documental en todas | Conciliación cuadra (por ausencia de saldos) |
| Q4 | sin filas | No hay extra/ajuste/reembolso |
| Q5 | sin filas | No hay mixtos (cada reserva = 1 pago) |
| Q6 | 13 reservas con saldo > 0, total $1.245.000 | Todo el "pendiente" es saldo no cobrado |
| Q7 | sin filas | No hay pre-reservas vigentes pendientes |
| Q8 | sin filas | No hay dinero ambiguo |
| Q9 | 1 efectivo, $50.000 | Efectivo poco representado todavía |
| Q10 | sin filas | No hay candidatos a recargo 5% |

---

## 7. Qué se validó

1. El diagnóstico read-only **funciona**: 10 consultas + controles ejecutan limpio.
2. La **normalización vía pre-reserva atribuye correctamente** las señas (que viven con
   `id_prereserva` poblado). Sin esta normalización, el reporte quedaría frágil:
   dependería de que todos los pagos tengan `id_reserva` poblado, y fallaría ante pagos
   asociados solo por `id_prereserva`. (En TEST los 13 pagos normales tienen ambos IDs,
   así que un join directo por `id_reserva` habría funcionado en este dataset; la CTE es
   correcta y obligatoria como patrón robusto, no por una falla observada hoy.)
3. La **fórmula de saldo calculado es correcta** y será la única confiable cuando existan
   saldos cobrados.
4. El modelo **soporta señas en efectivo** (reserva 11 lo demuestra), no solo transferencia.
5. La relación pre-reserva → reserva es **1:1** (verificación de unicidad: 0 filas).
6. **Sin tocar OPS, sin writes, sin DDL.** Privacidad preservada: no se leyó `huespedes`;
   `notas` se usó solo para diagnóstico en TEST, sin volcado crudo a salida compartible.

---

## 8. Qué NO se pudo concluir (queda para después)

- El comportamiento de `saldo_real` vs `saldo_documental` cuando haya saldos cobrados —
  solo verificable tras el Bloque 1B.
- El comportamiento de mixtos, recargos 5% y reembolsos reales — no hay casos en datos.
- Tratamiento contable de `cancelada_con_cargo` (ingreso sin estadía) y de
  `reembolsado` / `tipo='reembolso'` (salida de dinero) — anotados como pendientes de
  Carril B, no resueltos.

---

## 9. Hallazgos estructurales para registrar como lecciones

- **L-9A-01 — Pago colgado en dos columnas.** La seña inicial queda con `id_prereserva`
  poblado (y `id_reserva` también, tras conversión). **Hipótesis:** lo hace
  `confirmar_reserva()` rellenando `id_reserva` en los pagos existentes. **Pendiente de
  confirmar por lectura read-only de `confirmar_reserva()` antes de diseñar el Bloque 1B.**
  Todo el contable depende de la normalización `COALESCE(id_reserva, vía_prereserva)` de
  forma permanente, se confirme o no la hipótesis.
- **L-9A-02 — `reservas.monto_saldo` es estático.** No es saldo vivo. El saldo real se
  calcula siempre desde pagos confirmados. `monto_saldo` queda como referencia inicial.
- **L-9A-03 — `registrar_pago` confirma solo si `estado_inicial='confirmado'` Y
  `monto_recibido = monto_esperado`.** Cualquier desajuste cae en `en_revision`. La capa
  de cobranza posterior debe enviar ambos exactos por pago (incluye parciales: cada parcial
  es un pago confirmado por su propio monto — Regla 1).
- **L-9A-04 — Enums con estados no contemplados originalmente:** `estado_pago_enum` incluye
  `rechazado` y `reembolsado`; `estado_reserva_enum` incluye `cancelada_con_cargo`. Tienen
  implicancia contable futura.

---

## 10. Conclusión y recomendación de secuencia

El diagnóstico cumplió su objetivo y queda cuadrado. La evidencia es inequívoca: **la
contabilidad de ingresos no tiene sentido pleno hasta que exista registro de cobranza
posterior.** Hoy el sistema "ve" $1.105.000 (señas) de $2.350.000 facturados; los
$1.245.000 restantes son saldo que no se sabe cobrar/registrar.

Secuencia recomendada (sin reabrir lo aprobado):

1. **Cerrar este diagnóstico** (aprobación de Franco).
2. (Opcional, recomendado antes de diseñar) **Lectura read-only de `confirmar_reserva()`**
   para confirmar la hipótesis L-9A-01 (si rellena `id_reserva` en pagos existentes).
3. **Bloque 1B — diseño de la capa de cobranza posterior** sobre `registrar_pago()`
   (capa n8n, sin schema), aplicando Reglas 1–3 ya aprobadas.
4. Recién con cobranza posterior operativa, los reportes de ingresos y la futura caja
   adquieren sentido contable real.

---

**Restricciones respetadas en todo el bloque:** sin AFIP/ARCA/IVA/fiscal, sin integración
bancaria/MP automática, sin frontend/bot/WhatsApp/Airbnb/Booking, sin tocar OPS, sin writes,
sin DDL, sin workflow de escritura, sin diseño final de reparto.
