# 9B_CIERRE.md — Cierre formal Etapa 9B / Fase 3b

**Etapa:** 9B / Fase 3b — Cobranza posterior multi-porción (primera fase que escribe pagos)
**Estado:** ✅ Cerrada en TEST (validada con batería funcional completa, incluido rollback)
**Entorno de validación:** TEST (`vita-delta-test`) — IDs de cabaña 1–5
**Entorno de operación:** — (3b **no** se promovió a OPS en esta fase; promoción diferida)
**Fecha de cierre:** 2026-06-07
**Documento de diseño:** `ARQUITECTURA_ETAPA_9B_COBRANZA_POSTERIOR.md` (v2) + esta fase 3b
**Base estructural:** workflow real `3a-v2` (read-only multi-porción), convertido a 3b
**Contrato verificado:** `registrar_pago(payload jsonb)` — releído en TEST; sin modificar
**Helper nuevo en TEST:** `public.abortar_si_falla(jsonb)` — creado y micro-testeado
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3`
**Autores:** Franco (titular) + Claude (arquitecto)
**Decisiones registradas en esta fase:** D-9B-19 (atomicidad transaccional) + comportamiento conocido del doble-mensaje

---

## 1. Resumen ejecutivo

La Fase 3b construyó la **capa de cobranza posterior**: el formulario n8n con el que el
equipo registra el saldo cobrado **después** de confirmada una reserva, en una sola acción,
con soporte para **hasta tres porciones simultáneas** (efectivo / transferencia
bancaria o MP / "otros" en equivalente ARS) y **recargo 5% interno** sobre la porción de
transferencia. Es la **primera fase de la Etapa 9 que escribe pagos** (las anteriores eran
diagnóstico read-only).

A diferencia del diseño 9B v2 original —que aceptaba fallo parcial informado sin
auto-revertir (D-9B-16)— la Fase 3b adopta **registro transaccional atómico (todo-o-nada,
D-9B-19)**: si cualquier línea de un evento multi-línea falla o queda no-confirmada, se
revierte **todo** el evento. Esto se logró sin modificar `registrar_pago()` ni el schema de
tablas, mediante un helper SQL mínimo y aditivo (`abortar_si_falla`) y `queryBatching:
transaction` en el nodo de registro.

Se siguió la metodología estricta del proyecto: relectura del contrato → diseño aprobado →
helper creado y micro-testeado en TEST → generación de JSON con verificador estructural
(generador + verificador en Python) → importación manual por Franco → batería de smokes en
TEST. **3b queda validada en TEST**; la promoción a OPS se trata como paso posterior con
aprobación explícita (ver §8).

---

## 2. Qué se construyó

- **Workflow TEST:** `vita_w09_cobranza_posterior_supabase__TEST_3b` (14 nodos), validado.
  Path `vita-cobranza-posterior-3b-test`, credencial `vita_supabase_test`, Basic Auth,
  `active=false`.
- **Helper SQL (TEST):** `public.abortar_si_falla(jsonb)` — convierte un pago no confirmado
  de `registrar_pago()` en excepción P0001 para forzar rollback bajo `queryBatching:
  transaction`. Aditivo: no toca tablas, enums ni `registrar_pago()`.
- **Generador:** `generar_3b.py` — construye el JSON desde la topología de 3a-v2 con los
  cambios mínimos de 3b.
- **Verificador:** `verificar_3b.py` — 34 controles estructurales (anti-OPS, no-DDL,
  topología, núcleo transaccional, verificación posterior, mensajería, grafo). Veredicto
  PASA 34/34 sobre el JSON definitivo.
- **Copia desechable de laboratorio:** `cobranza_posterior_3b_SMOKE10.json` — idéntica al 3b
  salvo nombre/path y una línea inducida-a-fallar en N4.5, usada solo para el smoke de
  rollback y luego eliminada. No forma parte del entregable productivo.

### 2.1 Topología del workflow (3b)

```
N1 Form Trigger (porciones, Basic Auth)
  → N2 Consulta saldo real (Postgres; saldo_real = monto_total − Σ pagos confirmados sena+saldo)
  → N3 Validación multi-porción (Code: valida; calcula recargo 5%; genera source_event único;
                                 arma lineas[] payload-ready; emite UN solo evento)
  → IF ¿Error de negocio?
       ├─ true  → N9 Error de negocio (completion)
       └─ false → N4 Resumen + Confirmar (form page)
                   → N4.5 Expandir líneas (Code: 1 evento → N ítems, uno por línea)
                   → N5 Registro transaccional (Postgres executeQuery,
                        queryBatching=transaction,
                        SELECT public.abortar_si_falla(public.registrar_pago($1::jsonb)))
                        ├─ éxito  → N6 Verificación posterior (Postgres; relee por source_event
                        │            + recalcula saldo real post-write desde la base)
                        │            → N6b Control verificación (Code: lee item.resultado)
                        │            → IF ¿Verificación OK?
                        │                 ├─ true  → N7 Éxito (saldo anterior→nuevo; saldada si 0)
                        │                 └─ false → N8b Error de verificación posterior
                        └─ error  → N8a Error transaccional (rollback: no quedó ningún pago)
```

### 2.2 Campos del formulario

| Campo | Control | Notas |
|---|---|---|
| ID de reserva | Number (obligatorio) | del listado HTML interno (D-9B-12) |
| Porción EFECTIVO | Number | 0 si no aplica |
| Porción TRANSFERENCIA | Number | 0 si no aplica |
| Tipo de transferencia | Desplegable opcional `(bancaria)`/`MP` | **default bancaria** si se deja vacío |
| Porción OTROS | Number | equivalente en ARS, 0 si no aplica |
| Origen de OTROS | Desplegable `(ninguno)`/USD/cripto/otro | obligatorio si `monto_otros > 0` |
| Descripción de OTROS | Text | **obligatoria si `monto_otros > 0`** |
| Validado por | Desplegable Vicky/Rodrigo/Franco/Remo (obligatorio) | |
| Notas | Textarea | opcional |

---

## 3. Contrato real verificado (read-only TEST) y decisiones sobre el helper

Relectura del cuerpo real de `registrar_pago()` (schema §10.9):

- Retorno JSONB: `{ ok, id_pago, estado }`; en los caminos `ok:false` agrega `error`.
- Caminos `ok:false` **sin** excepción: `referencia_requerida`, `payload_invalido`,
  `prereserva_no_existe`, `reserva_no_existe`.
- Camino `ok:true` con `estado='en_revision'` posible si `monto_recibido ≠ monto_esperado`.
- `source_event` existe en `pagos`, es `NOT NULL`, y `registrar_pago()` **lo persiste tal
  cual** lo recibe en el payload (verificado empíricamente: el pago `id_pago=15` quedó con
  `source_event = n8n_test_w09_cobranza_franco_ex1582`).

**Helper `abortar_si_falla` (decisión sobre su contrato):** el éxito operativo se define
como `ok=true AND estado='confirmado' AND warning IS NULL` (coherente con D-8B-15: no basta
`ok:true`). Cualquier otro caso —incluido `ok:true` con `estado='en_revision'`— lanza
P0001 y dispara rollback. Creado con `SET search_path = public, pg_temp`, `REVOKE EXECUTE …
FROM PUBLIC, anon, authenticated, service_role` (grants verificados en 0 filas) y
`COMMENT ON FUNCTION`. Micro-tests en TEST: éxito limpio devuelve el jsonb; `ok:false`
aborta; `ok:true+en_revision` aborta. Los tres se comportaron como se esperaba.

---

## 4. Manejo de errores (tres familias)

- **Error de negocio (N9):** ID inexistente, suma 0, suma > saldo, monto inválido,
  transferencia sin subtipo, "otros" incompleto. Se detecta en N3 **antes** de escribir;
  no registra nada.
- **Error transaccional (N8a):** la transacción de N5 abortó (alguna línea no confirmada);
  rollback completo. Mensaje humano: "la cobranza fue revertida; no quedó ningún pago
  registrado". Sin error técnico crudo.
- **Error de verificación posterior (N8b):** la transacción de N5 **sí cerró**, pero la
  verificación posterior (N6/N6b) no cuadra. Mensaje humano conservador: "la cobranza pudo
  haberse registrado; no vuelvas a cargarla; avisá a Franco y revisá por `source_event`".

Ver §7 sobre el comportamiento conocido del doble-mensaje (N8b seguido de N8a) ante un
rollback.

---

## 5. Decisiones registradas en esta fase

| ID | Decisión |
|---|---|
| **D-9B-19** | **Atomicidad transaccional en 3b.** La Fase 3b adopta `queryBatching: transaction` + helper SQL `abortar_si_falla` que convierte cualquier pago no confirmado en excepción, **reemplazando para esta fase** el modelo de fallo parcial informado de D-9B-16. Si una línea falla o queda no-confirmada, se revierte **todo** el evento de cobranza. El helper define éxito como `ok=true AND estado='confirmado' AND warning IS NULL`. |

**Ajustes de implementación dentro del alcance ya aprobado (no nuevas decisiones):**
- Subtipo de transferencia opcional con **default bancaria**; aplica tanto a la línea
  `saldo` de transferencia como a la línea `extra` del recargo (refina D-9B-08).
- Descripción de "otros" **obligatoria si `monto_otros > 0`** (alineado a D-9B-18); la línea
  de "otros" persiste como `medio_pago='efectivo'` con trazabilidad en notas:
  `medio_original=otros; origen_otros=<v>; descripcion_otros=<t>; registrado_como=efectivo_ars`.
- `source_event` único por evento generado en N3 con `$execution.id` (fallback ms+random) y
  propagado sin mutar a todas las líneas vía N4.5.
- N6 **recalcula el saldo real post-write desde la base** (misma lógica de N2) y N6b lo
  compara contra la proyección `saldo_anterior − suma_saldo`, validando que el `extra` no
  redujo saldo.

---

## 6. Validación (batería en TEST)

| # | Caso | Resultado |
|---|---|---|
| 1 | ID inexistente | ✅ N9 ("no encontré una reserva con ese ID") |
| 2 | Suma 0 | ✅ N9 ("al menos una porción mayor a cero") |
| 3 | Suma > saldo | ✅ N9 ($110.000 > $50.000) |
| 4 | Happy path solo efectivo | ✅ N7; saldo $100.000 → $0; reserva saldada |
| 5 | Transferencia bancaria + extra | ✅ N7; recargo $8.500 (5% de $170.000) aparte; saldo → $0 |
| 6 | Transferencia MP + extra | ✅ N7; recargo $5.000 aparte; `medio_pago='transferencia_mp'` |
| 7 | Multi-porción efectivo+transf+otros | ✅ N7; 4 líneas; recargo $1.650 sobre la transferencia |
| 8 | Otros sin descripción | ✅ N9 ("la porción otros exige una descripción") |
| 9 | Porción única (Bamboo) | ✅ N7; saldo → $0; saldada |
| extra | **Pago parcial** | ✅ N7; saldo $100.000 → $50.000; "queda saldo pendiente" |
| 10 | **Rollback multi-línea** | ✅ **0 pagos** en la base por el `source_event` del intento; rollback confirmado (ver §7) |

El recargo 5% se comportó exactamente como diseñado en los tres casos con transferencia
($8.500 / $5.000 / $1.650): línea `extra` separada, marcada `recargo_5_saldo_transferencia`,
**sin reducir** el saldo de alojamiento (el saldo baja solo por las líneas `saldo`).

---

## 7. Incidencias resueltas y comportamiento conocido

### 7.1 Bug de SQL en N6 (resuelto)
Primera versión de N6 mezclaba coma (cross join implícito) con `LEFT JOIN` en el mismo
`FROM` (`FROM reservas r, ev LEFT JOIN …`), causando
`invalid reference to FROM-clause entry for table "r"`. El happy path registró el pago
(N5 commiteó) pero N6 explotaba con error genérico de n8n. **Resuelto:** `FROM reservas r
LEFT JOIN … WHERE r.id_reserva = (SELECT id_reserva FROM ev)`. Validado con `sqlglot`
(parseo Postgres + resolución de scope). Se añadió el control **B7** al verificador para
impedir la reaparición de la mezcla coma+JOIN.

### 7.2 Columna de timestamp en `pagos` (aclaración)
En `pagos` el timestamp es **`created_at`** / `updated_at` (no `fecha_hora`, que es de
`log_cambios`). Complementa la lección previa sobre `log_cambios.fecha_hora`.

### 7.3 Doble-mensaje ante rollback (comportamiento conocido, aceptado)
Ante un rollback de N5, la pantalla muestra **N8b por un instante y luego N8a** (la base
queda en 0 pagos las tres veces probadas). La causa: con `onError: continueErrorOutput`, el
nodo Postgres en modo transacción saca el error por la salida de error (→N8a) y, además,
deja avanzar un ítem por la salida de éxito (→N6→N6b→N8b). Se intentó un nodo compuerta
(N5.5 Filter) para cortar la rama de éxito; **no resolvió** el doble-mensaje y fue
**revertido** (el JSON definitivo no lo incluye).

**Decisión (Franco):** se **acepta como está**. La integridad —lo crítico— está probada (0
pagos tras rollback). El operador termina viendo N8a, que es el mensaje correcto; el flash
previo de N8b es cosmético y conservador (N8b nunca conduce a un estado peligroso: a lo
sumo invita a revisar por `source_event`, donde no encontrará nada). No se invierte más
esfuerzo en pulirlo en esta fase.

---

## 8. Lo que NO se hizo en 3b (alcance respetado)

- **No se promovió a OPS.** 3b queda validada solo en TEST. La promoción es paso posterior
  con aprobación explícita, y requiere crear primero `public.abortar_si_falla(jsonb)` en
  OPS (si falta, 3b falla). Al promover: revisar marcadores de entorno embebidos
  (L-8D-03), credencial `vita_supabase_ops`, Basic Auth propia.
- **No se tocó `registrar_pago()`, ni tablas, ni enums.** Único cambio de schema: el helper
  aditivo en TEST.
- **No se abordó** (queda para Carril B / arquitectura global de contabilidad): gastos,
  caja por lugar, liquidaciones 75/25, reparto entre socios, tabla de ahorro/conversión de
  monedas, cancelaciones con cargo, AFIP/ARCA/IVA/facturación, MercadoPago automático,
  bancos, frontend, bot, WhatsApp, Airbnb/Booking.
- **Liquidación del `extra`** (si es repartible, gasto financiero, comisión o ingreso
  separado): fuera de 3b; se define en Carril B.

---

## 9. Artefactos entregados

- `cobranza_posterior_3b.json` — workflow definitivo (14 nodos, verificador 34/34).
- `generar_3b.py` — generador del workflow.
- `verificar_3b.py` — verificador estructural (34 controles).
- `vita_w09_cobranza_posterior__TEMPLATE.json` — workflow 3b **sanitizado** para el repo
  (sin ids de credencial, sin webhookId, sin instanceId; placeholders `CRED_POSTGRES`,
  `CRED_BASIC_AUTH`, `PATH_PLACEHOLDER`; `active=false`).
- `vita_w09_listado_saldos__TEMPLATE.json` — workflow del listado HTML de saldos (3a),
  **sanitizado** con el mismo estándar.
- `9B_CIERRE.md` — este documento.
- Helper SQL `public.abortar_si_falla(jsonb)` — vive en TEST (no es archivo; se documenta su
  DDL en este cierre y en `Lecciones_Aprendidas.md`).
- (Descartado tras uso) `cobranza_posterior_3b_SMOKE10.json` — copia de laboratorio para el
  rollback; eliminada de n8n al terminar.

> **Nota de proceso:** este cierre se redacta **antes** de actualizar los seis satélites. La
> actualización de `ESTADO_ACTUAL_VITA_DELTA.md`, `DECISIONES_NO_REABRIR.md`,
> `Lecciones_Aprendidas.md`, `Pendiente_pre_produccion.md`, `CLAUDE.md` y `README.md` es el
> **paso siguiente** (Franco aportará los satélites actuales y se actualizan como conjunto).
> Hasta entonces, este documento es la fuente del contenido a propagar (D-9B-19; lecciones
> L-9B-01 a L-9B-05; estado de 3b validada en TEST, OPS pendiente).

---

## 10. Lecciones (para `Lecciones_Aprendidas.md`)

- **L-9B-01** — `registrar_pago()` persiste el `source_event` del payload tal cual; permite
  verificar y agrupar un evento multi-línea por ese campo.
- **L-9B-02** — Para rollback todo-o-nada de varias llamadas a una función en n8n: helper
  SQL que convierte `ok:false`/estado no-confirmado en excepción + `queryBatching:
  transaction` en un único nodo Postgres. El helper debe exigir `ok ∧ estado='confirmado' ∧
  sin warning`, no solo `ok` (D-8B-15).
- **L-9B-03** — No mezclar coma (cross join) con `LEFT JOIN` en el mismo `FROM` en Postgres:
  el `ON`/`WHERE` no puede referenciar la tabla de la coma → "invalid reference to
  FROM-clause entry". Separar el JOIN y usar subquery escalar para la condición.
- **L-9B-04** — En `pagos` el timestamp es `created_at`/`updated_at` (no `fecha_hora`).
- **L-9B-05** — `onError: continueErrorOutput` en un nodo Postgres en modo transacción puede
  ejecutar **ambas** salidas ante un rollback (error y éxito), produciendo un doble-mensaje
  final. La integridad no se ve afectada (la transacción revierte igual), pero el ruteo de
  errores no queda limpio; un nodo Filter intermedio simple no lo corrige. Tenerlo en cuenta
  en futuros workflows transaccionales con doble final humano.

---

## 11. Estado tras 3b

La **Etapa 9 / Carril A** avanza: 9A (diagnóstico) y 3a-v2 (read-only) estaban cerrados;
ahora **3b (cobranza posterior, escritura transaccional) queda validada en TEST**. Pendiente
inmediato del Carril A: promoción de 3b a OPS (con el helper creado allí primero) y smoke con
datos reales. **Carril B** (políticas de liquidación 75/25, reparto entre socios) sigue
abierto y sin iniciar. La arquitectura global de contabilidad (gastos, monedas, AFIP, etc.)
se tratará en conversación aparte.
