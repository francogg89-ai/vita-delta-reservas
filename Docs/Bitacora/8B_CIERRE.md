# 8B_CIERRE.md — Cierre formal Etapa 8B

**Etapa:** 8B — Capa de carga interna de reservas (Form Trigger n8n)
**Estado:** ✅ Cerrada (TEST validado + smoke OPS exitoso con la primera reserva real)
**Fecha de cierre:** 2026-05-30
**Entorno de validación:** TEST (`vita-delta-test`) — batería funcional completa
**Entorno de operación:** OPS (`vita-delta-ops`) — smoke exitoso, primer write real confirmado (reserva id 1)
**Documento de diseño:** `ARQUITECTURA_ETAPA_8B_CAPA_CARGA.md v3.4`
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3`
**Autores:** Franco (titular) + Claude (arquitecto)
**Decisiones registradas:** D-8B-01 a D-8B-21 (D-8B-12 revisada en v3.3)

---

## 1. Resumen ejecutivo

La Etapa 8B construyó la **capa de carga interna de reservas**: un formulario n8n
(Form Trigger) usable desde celular que permite a Franco, Vicky, Rodrigo o Remo
cargar una reserva ya cerrada (cliente identificado + seña confirmada por WhatsApp)
en **una sola acción**. Detrás del formulario, n8n encadena las tres puertas del
motor en secuencia —`crear_prereserva()` → `registrar_pago()` →
`confirmar_reserva()`— y devuelve al operador **un único resultado**: reserva
confirmada, error de negocio comprensible, o aviso de revisión manual.

El encadenado vive en n8n; el motor sigue con sus tres funciones separadas (locks,
idempotencia y revalidación intactos). No hay INSERT directo a ninguna tabla
transaccional: toda escritura pasa por las funciones existentes. La cabaña se elige
por nombre (el operador nunca ve ni escribe IDs ni estados internos).

El diseño se desarrolló de forma incremental (v1 → v3.3), con **verificación
read-only de los contratos reales contra OPS** antes de construir nada, y el
workflow se **validó íntegramente en TEST** con la batería de la sección 7.1. El
primer write real en OPS (smoke) queda pendiente de la primera reserva real futura,
por decisión de no ensuciar OPS con datos ficticios (D-8-12).

---

## 2. Qué se construyó

- **Workflow TEST:** `vita_w8b_carga_reserva__TEST` (21 nodos), validado.
- **Workflow OPS:** `vita_w8b_carga_reserva__OPS`, derivado del TEST validado,
  preparado e inactivo (smoke pendiente).
- **Template sanitizado:** `vita_w8b_carga_reserva__TEMPLATE` — reutilizable, sin
  datos reales, con placeholders y marcas `// AJUSTAR`.

### 2.1 Topología del workflow

```
Form Trigger (Basic Auth, Workflow Finishes, timezone BA)
  → Validar/Normalizar Input (mapeos, validaciones de capa, seña, idempotency_key)
  → IF validación → [error → Build Response]
  → Build Payload P1 → Postgres crear_prereserva → Normalize C
  → IF P1 ok → [error → Build Response]
  → Build Payload P2 → Postgres registrar_pago → Normalize P2
  → IF P2 ok ESTRICTO (ok && estado=confirmado && sin warning) → [no → Compensación]
  → Build Payload P3 → Postgres confirmar_reserva → Normalize P3
  → IF P3 ok → [no → Compensación]
  → [PUNTO EXTENSIÓN 8C: placeholder, sin lógica]
  → Build Response → Form Ending

Compensación (unificada): Build Compensation Context → Postgres cancelar_prereserva
  → Normalize I → Build Response → Form Ending
```

- **Continue On Fail + Always Output Data** en los 4 nodos Postgres.
- **Envelope uniforme** por paso (`step`/`ok`/`error_type`/`raw_error`/
  `business_result`/`id_*`) que distingue error técnico de error de negocio.
- **`ctx` enriquecido paso a paso** (id_pre_reserva tras P1, id_pago tras P2) — no
  depende de que cada función devuelva todos los IDs.
- **Build Response centraliza la decisión del mensaje** (7 casos); **Form Ending**
  (nodo `form` operation `completion`) lo muestra.

---

## 3. Decisiones registradas (D-8B-01 a D-8B-21)

| ID | Decisión |
|---|---|
| D-8B-01 | Capa = Form Trigger que encadena las 3 funciones en una acción, camino estricto |
| D-8B-02 | Formulario para celular, mínimo texto libre (desplegables/date/numérico) |
| D-8B-03 | `operador` = desplegable obligatorio, autodeclarado, sin login en el MVP |
| D-8B-04 | Trazabilidad: operador en `source_event` + `validado_por` explícito + `created_by` |
| D-8B-05 | Pago = seña (`tipo='sena'`, monto_esperado=monto_recibido=seña, estado_inicial='confirmado'); saldo derivado por la función |
| D-8B-06 | `idempotency_key` Opción A: `ops_8b_<id_cabana>_<fecha_in>_<fecha_out>_<contact_key>` (constraint parcial confirmada) |
| D-8B-07 | Fallo parcial → compensación activa; mensaje según `pagos_asociados_count`; nunca "revertido" si quedó pago |
| D-8B-08 | Colisión → mensaje de negocio claro, nunca error técnico crudo |
| D-8B-09 | Punto de extensión 8C marcado (post-confirmar ok), repintado NO construido |
| D-8B-10 | Form Trigger protegido con Basic Auth |
| D-8B-11 | Fechas: flujo normal hoy/futuro; pasadas o ya iniciadas → decisión manual |
| D-8B-12 | **(Revisada v3.3)** Nombre del huésped en campo único "Nombre y apellido", persistido en `huesped.nombre` (apellido vacío). Reemplaza el apellido separado |
| D-8B-13 | Seña Variante A: vacía/0 → 50% automático; valor >0 → se respeta |
| D-8B-14 | Validación completa en TEST; smoke mínimo en OPS con reserva real futura |
| D-8B-15 | Tras `registrar_pago`: exigir `ok && estado='confirmado' && sin warning`; no basta `ok:true` |
| D-8B-16 | Capacidad/cabaña la valida el motor (`cabana_no_existe`/`cabana_inactiva`/`excede_capacidad`); n8n solo UX |
| D-8B-17 | Normalización del teléfono para la key en n8n: solo dígitos; o `email_<email>` si no hay teléfono |
| D-8B-18 | `source_event` = `<marcador>_w8b_carga_<operador>_manual`, operador en minúscula |
| D-8B-19 | `encargado_semana` vacío en 8B |
| D-8B-20 | Compensación: `motivo='cliente'` + `descripcion='rollback_8b_fallo_cadena'` |
| D-8B-21 | Desplegables con strings compatibles con CHECK reales (ver §5) |

---

## 4. Hallazgos de la verificación contra OPS (read-only)

La verificación de contratos reales (`pg_get_functiondef` + catálogo) reveló cosas
que el canónico no mostraba y que corrigieron el diseño:

1. **`crear_prereserva` valida cabaña y capacidad** (`cabana_no_existe`,
   `cabana_inactiva`, `excede_capacidad`): la defensa de integridad la da el motor,
   no la capa (D-8B-16).
2. **`registrar_pago` degrada a `en_revision` sobre pre-reserva no activa** y
   devuelve `ok:true` con `warning`: un `ok:true` no garantiza pago confirmado →
   verificación estricta del paso 2 (D-8B-15).
3. **`cancelar_prereserva` devuelve `pagos_asociados_count`/`pagos_asociados_ids`**:
   permite decidir el mensaje de compensación sin consulta adicional (D-8B-07).
4. **`canal_origen`/`canal_pago_esperado`/`medio_pago`/`tipo` NO son enums; son
   TEXT con CHECK** (ver §5).
5. **Constraint de `idempotency_key` es PARCIAL** (`uq_prereservas_idempotency_activa`,
   solo sobre estados activos): habilita la Opción A sin riesgo de falso bloqueo tras
   cancelación (D-8B-06).

---

## 5. Valores persistidos compatibles con los CHECK reales

`canal_origen` (CHECK `pre_reservas`: whatsapp/instagram/web/manual):

| Etiqueta visible | Persiste | Origen fino en notas |
|---|---|---|
| WhatsApp / Instagram | whatsapp / instagram | no |
| Directo / Referido / Otro | manual | "Origen operativo: …" |
| Airbnb / Booking | web | "Origen operativo: …" |

`canal_pago_esperado` y `medio_pago` (CHECK: transferencia_bancaria / transferencia_mp
/ mp_link / cripto / efectivo):

| Etiqueta visible | Persiste |
|---|---|
| Transferencia bancaria | transferencia_bancaria |
| Transferencia MercadoPago | transferencia_mp |
| Link MercadoPago | mp_link |
| Efectivo | efectivo |
| Cripto | cripto |

`tipo` = `sena` (confirmado por `chk_pagos_tipo`). El dato operativo fino
(Airbnb/Booking/Directo/Referido/Otro) se preserva en `notas` con prefijo
`Origen operativo: <etiqueta> | <notas del operador>`, ya que el CHECK de
`canal_origen` obliga a un valor genérico. Nota: `reservas.canal_origen` sí acepta
`airbnb`/`booking`, pero `pre_reservas` no, y la cadena pasa primero por la
pre-reserva → manda el CHECK más restrictivo.

---

## 6. Validación en TEST (batería sección 7.1) — ✅ completa

| Caso | Resultado |
|---|---|
| Happy path, seña vacía → 50% | ✅ Reserva N°2: total 200000, seña auto 100000, saldo 100000 |
| Happy path, seña explícita | ✅ Reserva N°3: total 200000, seña 30000, saldo 170000 |
| Colisión / doble booking | ✅ Segunda carga rebota "ya está ocupada" |
| Idempotencia (reenvío misma carga) | ✅ `idempotent_match`, sin duplicar |
| Validaciones de capa (fecha pasada, capacidad, seña>total) | ✅ Mensajes claros sin tocar DB |
| Seña vacía / 0 → 50% (arreglo v4) | ✅ Corregido tras primer hallazgo |
| Compensación con pago (P3 falla con pago confirmado) | ✅ "Carga incompleta (pre-reserva #5, pago #5)… revisión manual" |

El caso de compensación se montó con un nodo Wait temporal de 60s entre P2 y P3 y
una cancelación manual de la pre-reserva vía `cancelar_prereserva` en TEST (único
caso que requirió tocar datos a mano, en TEST, vía función — no INSERT directo). El
Wait se removió tras la prueba. Validó la regla crítica: **cuando hay pago
registrado y la cadena se corta, el operador recibe aviso de revisión manual con los
números concretos, nunca un falso "todo bien".**

---

## 7. Lo que NO se hizo en 8B (alcance respetado)

- **Smoke real en OPS:** pendiente de la primera reserva real futura (§8).
- **Calendarios visuales:** son 8C. En 8B solo se dejó el punto de extensión marcado
  (nodo placeholder post-`confirmar_reserva`, sin lógica de repintado).
- **Bloqueos operativos de uso real:** son 8D.
- **MercadoPago real, bot, tarifas reales, frontend propio:** fuera de alcance.
- **Modificación de schema o funciones SQL:** la verificación no reveló necesidad de
  cambios; el motor soporta el flujo de 8B tal cual.
- **RLS / residual A5 de DEV:** no se tocaron (Opción A se mantiene).

---

## 8. Smoke OPS — ✅ COMPLETADO (2026-05-30)

El smoke en OPS se ejecutó con la **primera reserva real** del sistema y fue
exitoso. Constituye el **primer write real** de todo Vita Delta en producción.

**Reserva cargada (id_reserva 1):**
- Cabaña Tokio, huésped Paula Lugo, 2026-06-06 → 2026-06-07.
- Total 150000, seña 75000, **saldo 75000** (derivado por `confirmar_reserva`).
- Estado `confirmada`, `canal_origen: whatsapp`.
- `created_by: vicky`, `source_event: n8n_ops_w8b_carga_vicky_manual` (marcador OPS
  correcto — confirma escritura en el ambiente real, no en TEST).

**Pago (id_pago 1):** tipo `sena`, `transferencia_bancaria`, 75000, estado
`confirmado`, `validado_por: vicky`.

La cadena corrió completa en producción (crear_prereserva → registrar_pago →
confirmar_reserva → resultado único al operador) y la trazabilidad multiusuario
quedó verificada: la operadora (Vicky) aparece correctamente en `reservas.created_by`,
`pagos.validado_por` y el `source_event` de las tres funciones.

**Con esto la Etapa 8B queda 100% cerrada.** El sistema está tomando reservas reales.

---

## 9. Artefactos entregados

- `ARQUITECTURA_ETAPA_8B_CAPA_CARGA.md` v3.4 — documento de diseño.
- `vita_w8b_carga_reserva__TEST.json` — workflow validado en TEST.
- `vita_w8b_carga_reserva__OPS.json` — workflow de producción (smoke pendiente).
- `vita_w8b_carga_reserva__TEMPLATE.json` — template sanitizado reutilizable.
- `8B_CIERRE.md` — este documento.

---

## 10. Próximos pasos (post-8B)

1. **Activar el workflow `__OPS` para uso productivo normal.** El smoke se hizo con
   ejecución observada; para que el equipo cargue por la URL del formulario sin
   intervención, el workflow debe quedar **activo**.
2. **8C — Calendarios visuales por evento** (operativo del equipo + limpieza de
   Jenny). El equipo lo necesita ahora: el calendario manual se está agotando.
   Engancha en el punto de extensión que 8B dejó marcado. Formato (Sheet repintado
   vs HTML) se decide al diseñar 8C. Revisar también por qué el calendario operativo
   "se acaba" (probable tema de vista, no del motor: `horizonte_disponibilidad_dias=120`).
3. **8D — Bloqueos operativos + cierre de Etapa 8.**

---

*Fin del cierre formal de 8B. Capa de carga construida, validada en TEST y con smoke
OPS exitoso: el sistema tomó su primera reserva real (id 1, Tokio, Paula Lugo).
Etapa 8B 100% cerrada. El sistema está operativo y tomando reservas reales.*
