# CARRIL_MP_PAGOS_AUTONOMOS_DISENO.md — Diseño preparatorio del carril Mercado Pago

**Frente:** Pagos Autónomos / Mercado Pago (frente separado del Carril C; letra/número de carril pendiente de asignación por Franco)
**Estado:** ✅ Diseño preparatorio v1 — aprobado conceptualmente en chat. **No implementa nada.** Satélites sin actualizar.
**Tipo:** Documento de diseño y auditoría preparatoria (sin código, sin DDL, sin SQL ejecutable, sin workflow JSON)
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md` v1.8.1 — **no se modifica**
**Contratos existentes leídos (read-only, alineación):** `crear_prereserva`, `registrar_pago`, `confirmar_reserva`, `obtener_disponibilidad_rango`, `vista_calendario`
**Entorno de diseño:** conceptual. Cuando se implemente, **TEST primero** (`vita-delta-test`); OPS solo tras promoción explícita
**Autores:** Franco (titular) + Claude (arquitecto)
**Decisiones registradas:** D-MP-01 a D-MP-11 (lockeadas)

> Documento de diseño para revisión. **No toca** Supabase, n8n, OPS, portal operativo, `portal-api` ni el schema canónico. **No genera código.** Todos los secretos se tratan como placeholders.

---

## 0. Encuadre

Este carril prepara la base para que, cuando el frontend público esté listo, una persona pueda reservar en Vita Delta **sin pasar por Franco**, cobrando con Mercado Pago.

Principio rector (no negociable): **Mercado Pago solo cobra y notifica. La fuente de verdad de reservas, prereservas y pagos sigue siendo Supabase/Vita Delta.**

Existe arte previo conceptual en `ARQUITECTURA_ETAPA_4A_MOTOR_RESERVAS.md` (§11), anterior a la migración a Supabase y pensado para un bot que enviaba el link. Se toma como insumo, no como decisión cerrada: el objetivo nuevo es **reserva autónoma iniciada por el frontend público**, que es arquitectónicamente distinto.

---

## 1. Recomendación de producto: Checkout Pro (D-MP-01)

Para el MVP público se adopta **Checkout Pro** (checkout con redirección a entorno seguro de Mercado Pago).

Motivos:

- El frontend de pago queda bajo responsabilidad de Mercado Pago → **cero carga de PCI / seguridad de datos de tarjeta** de nuestro lado.
- Es la opción más rápida de integrar y la adecuada sin equipo de desarrollo dedicado.
- Encastra con el modelo existente: el backend crea una *preference* (con el Access Token, server-side), le adjunta `external_reference` y `metadata`, y Mercado Pago devuelve un `init_point` (la URL del checkout).

Checkout API y Checkout Bricks quedan como **evolución futura**, no como base del MVP.

---

## 2. Medios de pago (D-MP-02, D-MP-05, D-MP-10, D-MP-11)

### 2.1 Regla central (D-MP-02)

El **flujo automático de Mercado Pago no acepta medios offline/ticket**. Quien quiera pagar por otro medio sale del flujo automático y pasa a **cierre humano por WhatsApp** (Camino B).

Mecanismo de exclusión (para cuando se implemente): en Checkout Pro todos los medios están habilitados por defecto y se excluyen desde la *preference*. La exclusión del tipo `ticket` (efectivo offline tipo Rapipago/Pago Fácil) se hace vía `payment_methods.excluded_payment_types`.

### 2.2 Fundamentación del bloqueo de offline (D-MP-05)

La razón **no** se basa en un plazo de acreditación concreto, sino en una **incompatibilidad estructural**:

> **Los medios offline no son compatibles con prereservas cortas porque requieren vencimientos y compensación fuera del flujo inmediato.**

El riesgo concreto que se evita:

1. El cliente inicia la reserva.
2. Se crea una prereserva temporal (corta).
3. Mercado Pago genera un pago offline/`pending`.
4. La prereserva vence.
5. Otra persona reserva esa misma cabaña/fecha.
6. El pago offline se acredita más tarde.
7. Queda dinero cobrado sin poder confirmar automáticamente la reserva.

Por eso, **si alguna vez se habilitan pagos offline**, ese flujo **no** comparte el vencimiento corto: debe ser un **estado operativo separado** (por ejemplo `pendiente_pago_offline`), con vencimiento más largo, revisión manual, y **sin confirmación automática directa**.

### 2.3 Vencimiento de preference ↔ prereserva (D-MP-05)

- Como el MVP **excluye offline/ticket**, es válido evaluar alinear `expiration_date_to` de la *preference* con `expira_en` de la prereserva (solo medios de acreditación rápida → coherencia real).
- Esta alineación **no** aplica al hipotético flujo offline futuro, que vive en su propio estado.

### 2.4 Medios no-ticket sujetos a verificación (D-MP-11)

Lo **único** decidido por ahora es excluir offline/ticket. **Todos los demás medios** (transferencia bancaria / Transferencia 3.0 / CVU, `atm`, y cualquier otro) quedan **sujetos a verificación contra la lista real de medios de Argentina** antes de habilitarse en el flujo automático. No se asume ninguno como incluido por defecto hasta verificarlo.

> Nota: "Dinero en cuenta" no es excluible en Checkout Pro y es de acreditación inmediata, por lo que no presenta el problema de offline.

### 2.5 `binary_mode` (D-MP-10)

El `binary_mode` (que fuerza el pago a solo aprobado/rechazado, sin `pending`) **queda diferido. No se adopta todavía.** Se deja señalado como palanca futura, a evaluar junto con D-MP-11. Tiene contras (puede rechazar pagos que en revisión se aprobarían), por eso no entra al MVP sin análisis.

---

## 3. Dos caminos de venta separados (D-MP-03, D-MP-04)

### 3.1 Camino A — Reserva automática con Checkout Pro

Aplica cuando el cliente paga online con medios compatibles con acreditación rápida (verificados según D-MP-11). El flujo detallado va en la Sección 4.

### 3.2 Camino B — Cierre asistido por WhatsApp

Aplica cuando el cliente no quiere o no puede pagar por el flujo automático.

1. El cliente ve disponibilidad, precio y seña.
2. En lugar de pagar online, toca un botón tipo **"Coordinar por WhatsApp"**.
3. Se abre WhatsApp con un mensaje precargado, por ejemplo: *"Hola, quiero reservar Bamboo del X al Y para N personas. Me figura una seña de $X."*
4. Franco / Rodrigo / Vicky revisan manualmente.
5. Si la disponibilidad sigue libre y se valida la seña, se carga la reserva/prereserva/pago **manualmente** por el formulario/portal correspondiente.
6. Este camino **no depende de webhook de Mercado Pago ni de estados `pending`**.

### 3.3 UX obligatoria del Camino B (D-MP-04)

El botón de WhatsApp **no promete reserva asegurada**. Texto base del MVP:

> *"La disponibilidad puede cambiar hasta que confirmemos la seña."*

**Base del MVP:** el botón de WhatsApp es **lead / asistencia humana, no pago automático**.

**Variante comercial más agresiva (opcional, no obligatoria):** si más adelante se decide crear una prereserva temporal al derivar a WhatsApp, el texto pasa a:

> *"Te guardamos esta opción por unos minutos mientras coordinamos el pago. La reserva queda confirmada recién cuando validamos la seña."*

Esto queda marcado como **variante**, no como base.

---

## 4. Flujo futuro ajustado — Camino A, paso a paso

1. El front público consulta disponibilidad.
2. El backend consulta disponibilidad/cache (vía `obtener_disponibilidad_rango` / `vista_calendario`). **El frontend no calcula nada crítico.**
3. El backend cotiza precio y seña (el backend fija el `monto_esperado`).
4. El cliente confirma la reserva automática.
5. El backend crea la prereserva con **lock + idempotencia** (`crear_prereserva` con `idempotency_key`).
6. El backend crea la *preference* de Checkout Pro (contrato en Sección 5).
7. El cliente paga en Mercado Pago.
8. Llega el webhook.
9. El backend **valida la firma** (manifiesto oficial; Sección 6).
10. El backend **responde rápido** (HTTP 200/201).
11. El backend **consulta el pago real por API** usando el Access Token.
12. El backend valida, todo junto:
    - `payment_id` **no procesado** antes;
    - `status = approved`;
    - **monto exacto** esperado;
    - **moneda ARS**;
    - `external_reference` **conocida**;
    - **ambiente correcto**;
    - **prereserva vigente**;
    - **cabaña/fechas todavía confirmables**.
13. **Si todo cierra** → registra el pago (`registrar_pago`) y confirma la reserva (`confirmar_reserva`).
    **Si algo no cierra** → registra el evento/pago **en revisión**, sin confirmar automáticamente.

> Encastre: del paso 13 en adelante se reusan funciones existentes y testeadas. El frente nuevo es, en lo esencial, crear la *preference* y recibir/validar el webhook.

---

## 5. Contrato preliminar de la *preference* (conceptual)

Descrito a nivel de campos y propósito (no es código ni payload final):

| Campo | Propósito | Nota de diseño |
|---|---|---|
| `unit_price` (ítem) | Monto de la seña | **Calculado por el backend**, nunca por el cliente |
| `external_reference` | Vínculo con la prereserva | **Token opaco** `vd_{ambiente}_pre_<uuid>` (Sección 7) |
| `metadata` | Datos útiles auxiliares | **Mínima y no sensible**; no es fuente de verdad |
| `notification_url` | URL del webhook del backend | Placeholder hasta tener backend |
| `back_urls` | Retorno del cliente al sitio | **Solo UX**; no confirman nada |
| `payment_methods.excluded_payment_types` | Exclusión de offline/ticket | Excluir `ticket`; resto sujeto a D-MP-11 |
| `expiration_date_to` | Vencimiento del checkout | Coherente con `expira_en` de la prereserva (solo medios rápidos) |
| `moneda` (currency) | ARS | Validada también al consultar el pago |

---

## 6. Webhook y validación de firma (D-MP-06)

**El cuerpo del webhook no es fuente de verdad.** La validación **no** se describe como "validar el raw body".

### 6.1 Validación de firma (manifiesto oficial de Mercado Pago)

A partir de:

- `data.id` (query param de la notificación),
- `x-request-id` (header),
- `ts` (extraído del header `x-signature`, cuyo formato es `ts=...,v1=...`),
- y el **Webhook Secret**,

se compone la **cadena canónica que define Mercado Pago** (forma: `id:<data.id>;request-id:<x-request-id>;ts:<ts>;`), se calcula su **HMAC-SHA256** con el Webhook Secret y se compara, **en tiempo constante**, contra el componente `v1` de la firma.

### 6.2 Reglas complementarias

- **Comparación en tiempo constante.**
- **Validar el `ts`** dentro de una ventana razonable para **reducir replay**.
- **Responder 200/201 rápido** (Mercado Pago reintenta si no recibe confirmación a tiempo).
- **Procesar de forma idempotente** (Sección 8).
- **Consultar el pago real por API** (Access Token) para conocer status/monto/moneda.
- **Nunca confirmar reserva solo por recibir el webhook.**

### 6.3 Advertencia sobre pruebas de webhook

Las pruebas de webhook con credenciales de prueba tienen una particularidad: **los pagos de prueba pueden no disparar notificaciones reales** como uno esperaría. Para validar la recepción se usa el **simulador de notificaciones** de "Tus integraciones".

> Dejarlo asentado para **no perder tiempo** pensando que "el webhook no anda": primero validar recepción con el simulador; la prueba end-to-end completa se deja para más cerca de producción.

---

## 7. `external_reference` y `metadata` (D-MP-07)

**Decisión:** no usar `external_reference = id_prereserva`. Se usa un **token opaco**:

- Test: `external_reference = "vd_test_pre_<uuid>"`
- Producción: `external_reference = "vd_prod_pre_<uuid>"`

El backend genera el token al crear la *preference*. **Más adelante**, Supabase guarda el mapeo interno `external_reference_opaco → id_prereserva` (ver Sección 9; no se toca Supabase ahora).

Ventajas:

- No se exponen IDs secuenciales internos.
- Se evita la enumeración.
- Se distingue el ambiente.
- Se pueden recrear *preferences* sin acoplar todo al ID real.

**`metadata`:** mínima y no sensible. Puede duplicar datos útiles, pero **no es fuente de verdad**: la verdad es el mapeo en Supabase.

---

## 8. Idempotencia y persistencia futura (D-MP-08)

No alcanza con "el backend chequea si ya procesó el `payment_id`". El diseño debe prever **persistencia e idempotencia dura**. Queda como **criterio de diseño futuro** (sin DDL, sin implementar ahora):

- índice/constraint **único por `mp_payment_id`** o equivalente;
- **relación única** entre `external_reference` y el pago confirmado de seña;
- **log de eventos Mercado Pago separado**;
- **estado de procesamiento** del evento: `recibido`, `validado`, `procesado`, `ignorado`, `en_revision`;
- **deduplicación** de webhooks repetidos;
- **defensa ante eventos fuera de orden** (tratar la consulta a Mercado Pago como verdad del status actual);
- **reconciliación periódica** (barrido de pagos/prereservas para cazar webhooks perdidos).

> Encastre: `registrar_pago` hoy **no tiene índice de idempotencia**. Esta capa de persistencia es la que cierra ese hueco más adelante.

---

## 9. Datos a guardar en Supabase (preparatorio, sin DDL)

### 9.1 Lo que ya existe en el schema (no se rediseña)

- `pagos.referencia_externa` → `payment_id`
- `pre_reservas.referencia_mp` → `preference_id`
- `pagos.medio_pago` (incluye `mp_link`, `transferencia_mp`), `pagos.moneda`, timestamps
- `source_event` en logs; vínculo `id_reserva` / `id_prereserva`

### 9.2 Lo que faltaría más adelante (criterio, no DDL)

- Mapeo `external_reference_opaco → id_prereserva` (+ ambiente).
- Superficie de **auditoría de eventos Mercado Pago**: log saneado del webhook (`status`, `status_detail`, monto, `x-request-id`, timestamps), sin datos sensibles.
- Conciliación explícita **`monto_esperado` vs `monto_pagado`**.
- **Índice único anti-duplicado** sobre el `payment_id` de Mercado Pago.
- **Estado de procesamiento** del evento (ver Sección 8).

---

## 10. Endpoints / workflows futuros (mapa preliminar)

Siguiendo la frontera de confianza del Carril C (Edge Function como BFF; n8n hace las escrituras vía funciones existentes):

**Backend (Edge Function — frontera pública):**

- Consulta de **disponibilidad** (read-only; público → rate-limit, **cero PII**).
- **Cotización** de precio/seña (determinística, sin escribir).
- **Iniciar reserva**: `crear_prereserva` (con `idempotency_key`) + crear *preference* + devolver `init_point`. Acá vive el Access Token.
- **Receptor de webhook**: valida firma, responde rápido, consulta el pago por API, dispara confirmación.

**Camino de escritura (n8n, reusando lo existente):**

- El receptor de webhook, ya validado, llama a las **mismas acciones de escritura** `registrar_pago` y `confirmar_reserva` que el Carril C expone. El frente MP se vuelve **otro consumidor** de esas acciones, no un camino paralelo.

**Trabajo de fondo (cron):**

- **Reconciliación** periódica (cazar webhooks perdidos / barrer prereservas).

---

## 11. Riesgos y defensas

| Riesgo | Defensa |
|---|---|
| Pago offline acreditado tarde sobre prereserva vencida | Excluir `ticket`/offline (D-MP-02). Offline futuro → estado `pendiente_pago_offline` aparte, sin confirmación automática (D-MP-05). |
| Webhook falsificado | Validar firma por manifiesto (`data.id` + `x-request-id` + `ts` + Webhook Secret), en tiempo constante. El cuerpo no es verdad (D-MP-06). |
| Webhook duplicado | Idempotencia **persistente**: unique por `payment_id`, dedup, estado de procesamiento (D-MP-08). |
| Eventos fuera de orden | La consulta a Mercado Pago por API es la verdad del status actual; manejar transiciones (D-MP-08). |
| Pago aprobado tras expirar prereserva | Con offline excluido, raro. Si pasa, `registrar_pago` lo deja en `en_revision`; el dinero no se pierde, resolución manual. |
| Dos personas, misma cabaña/fecha | Advisory lock por cabaña en `crear_prereserva` + revalidación en `confirmar_reserva` (excluyendo la propia). |
| Monto/moneda incorrectos | `monto_esperado`/ARS fijados por el backend; `registrar_pago` confirma solo si coincide exacto; si no, `en_revision`. |
| Cliente paga pero no vuelve al sitio | El **webhook** confirma, no el `back_url`. |
| Cliente abandona el checkout | La prereserva vence y libera; la *preference* muere por `expiration_date_to`. |
| Enumeración de IDs internos | `external_reference` opaco `vd_{ambiente}_pre_<uuid>`; mapeo en Supabase (D-MP-07). |
| Replay de notificación vieja | Validar `ts` dentro de ventana + idempotencia. |
| Pruebas que "no notifican" | Usar el simulador de "Tus integraciones"; no asumir que el webhook está roto. |

---

## 12. Recargo/comisión Mercado Pago (D-MP-09)

La decisión sobre si se traslada al cliente un recargo/comisión de Mercado Pago **queda diferida**. Se cruza más adelante con la **capa de cargos/precios**, no se resuelve en este carril.

---

## 13. Checklist de acciones de Franco ahora en Mercado Pago Developers

Solo configuración en el panel, sin código y sin pegar tokens en ningún chat:

1. Crear/verificar la **aplicación de Vita Delta** en Mercado Pago Developers.
2. Ubicar las **credenciales de prueba**: Public Key y Access Token.
3. Identificar el **Webhook Secret** y tratarlo como secreto **distinto** del Access Token.
4. Ver **dónde se configuran los Webhooks**.
5. Ver **qué eventos** se pueden seleccionar, especialmente **pagos**.
6. Ver **dónde se configuran los medios de pago permitidos/excluidos** para Checkout Pro.
7. Crear/verificar **usuarios de prueba** si aplica.
8. Probar visualmente el **simulador de notificaciones**, si está disponible.
9. **No** conectar nada todavía con Supabase/n8n/OPS.
10. **No** activar producción todavía.
11. **No** generar código todavía.

### Credenciales y secretos (tratamiento)

| Credencial | Pública / Secreta | Dónde se usa |
|---|---|---|
| Public Key (test/prod) | Pública | Cliente (en Checkout Pro redirect casi no se usa) |
| Access Token (test/prod) | **SECRETA** | Server-side: crear *preference* y consultar el pago |
| Webhook Secret | **SECRETA** | Server-side: validar `x-signature` (**distinto** del Access Token) |
| Client ID / Client Secret | **SECRETA** | Solo OAuth/marketplace; probablemente no se necesiten |

Convención de placeholders alineada al proyecto (L-C-08 / L-C-10): `__PEGAR_MP_ACCESS_TOKEN_TEST__`, `__PEGAR_MP_WEBHOOK_SECRET_TEST__`, etc., con assert por prefijo `__PEGAR_`. Secretos en variables de entorno del backend, nunca en cliente ni repo. Separación test/prod por configuración, **nunca por payload**.

---

## 14. Qué NO hacer todavía

- **No** activar credenciales productivas.
- **No** conectar webhooks reales.
- **No** tocar Supabase.
- **No** tocar n8n.
- **No** tocar OPS.
- **No** tocar el portal operativo.
- **No** tocar `portal-api`.
- **No** tocar el schema canónico (`6B_SCHEMA_SQL.md`).
- **No** generar código.
- **No** aceptar pagos offline dentro del flujo automático del MVP.
- **No** adoptar `binary_mode` todavía (D-MP-10).
- **No** habilitar medios no-ticket sin verificación previa (D-MP-11).
- **No** decidir todavía recargo/comisión Mercado Pago al cliente (D-MP-09).

---

## 15. Bitácora de decisiones — D-MP-01 a D-MP-11 (lockeadas 🔒)

| ID | Decisión |
|---|---|
| **D-MP-01** | Producto: Checkout Pro para el MVP público. Mercado Pago solo cobra/notifica; Supabase es fuente de verdad. |
| **D-MP-02** | El flujo automático excluye medios offline/ticket (`excluded_payment_types`). |
| **D-MP-03** | Dos caminos: A (automático Checkout Pro) y B (WhatsApp = lead/asistencia humana, sin webhook). |
| **D-MP-04** | La UX de WhatsApp no promete reserva asegurada; prereserva temporal en la derivación = variante agresiva opcional. |
| **D-MP-05** | Alinear vencimiento *preference* ↔ prereserva solo bajo medios de acreditación rápida. Offline (si se habilita) = estado operativo separado (`pendiente_pago_offline`), con vencimiento más largo, revisión manual, sin confirmación automática directa. **Razón formal:** offline no es compatible con prereservas cortas porque requiere vencimientos y compensación fuera del flujo inmediato. |
| **D-MP-06** | Validación de webhook por **manifiesto oficial** de Mercado Pago (no "raw body"); el cuerpo no es fuente de verdad; consultar el pago real por API. |
| **D-MP-07** | `external_reference` opaco `vd_{ambiente}_pre_<uuid>`; metadata mínima no sensible; mapeo a `id_prereserva` en Supabase a futuro. |
| **D-MP-08** | Idempotencia **persistente** como criterio de diseño futuro (unique por `payment_id`, log de eventos, estados de procesamiento, reconciliación). |
| **D-MP-09** | Recargo/comisión Mercado Pago al cliente: **diferido**; se cruza con la capa de cargos/precios. |
| **D-MP-10** | `binary_mode` **diferido**; no se adopta todavía. |
| **D-MP-11** | Medios no-ticket (transferencia/atm/otros) **sujetos a verificación** antes de habilitarse en el flujo automático. Lo único decidido por ahora es excluir offline/ticket. |

---

## 16. Pendientes / próximos pasos (no ejecutar ahora)

- Asignar letra/número de carril (decisión de Franco).
- Verificar, contra la lista real de medios de Argentina, qué medios no-ticket se habilitan (D-MP-11).
- Definir el contrato final de la *preference* y del receptor de webhook (cuando se autorice pasar a implementación).
- Definir el diseño de persistencia de eventos Mercado Pago e idempotencia dura (D-MP-08), recién al tocar Supabase.
- Coordinar el reuso de las acciones de escritura del Carril C (`registrar_pago`, `confirmar_reserva`) como camino de escritura del frente MP.

> **Estado de avance:** diseño preparatorio aprobado conceptualmente. Próximo artefacto solo con OK explícito de Franco. Nada se conecta a Supabase/n8n/OPS hasta autorización.
