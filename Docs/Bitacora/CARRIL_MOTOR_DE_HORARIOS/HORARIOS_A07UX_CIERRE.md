# Cierre tecnico (preliminar) - Mini-bloque UX A07: `override_hora_invalido` -> `payload_invalido`

**Veredicto: 🟢 VERDE - cerrado tecnicamente en TEST.**
Fecha: 2026-07-02. Alcance: SOLO A07, SOLO TEST.

## 1. Que cambio (unico delta)
Un solo string `'override_hora_invalido'` agregado al array `payloadInv` del Code node **`router1_crear`** (despues de `'fecha_in_pasada'`). **+25 bytes exactos** (`,'override_hora_invalido'`). Aplicado por **edicion directa del nodo live** (sin re-import -> HMAC/credenciales intactas); template de repo actualizado en paridad. Delta probado por reverse-replace, JSON valido, `node --check` EXIT 0.

## 2. Efecto
`router1_crear` mapea el HARD del resolver (`error='override_hora_invalido'`, emitido por `crear_prereserva` en el bloque 3.5) a **`payload_invalido`**, con message `datos de reserva rechazados: override_hora_invalido` y `detail:null`. Gateway y frontend sin cambios (code ya allowlisted, probado por el guard B3).

## 3. Evidencia (ejecucion en TEST)
- **SETUP:** `estado=SETUP_OK`, `id_override=80`, `id_cabana=1`, `tipo_override=hora_checkin`, `valor=25:99`, `fecha_desde=fecha_hasta=2027-06-15`, `motivo=smoke_a07_ovr_e2268a33`.
- **Smoke E2E:** POST `portal-a07-crear-reserva__TEST` -> HTTP 200; `ok=false`, `error.code=payload_invalido`, `error.message=datos de reserva rechazados: override_hora_invalido`, `error.detail=null`. Script: **PASS**.
- **TEARDOWN:** `estado=TEARDOWN_OK`, `overrides_restantes=0`.
- **POSTCHECK:** `estado=POSTCHECK_OK`, `overrides_smoke=0`, `prereservas_smoke=0`, `huespedes_smoke=0`.

## 4. Confirmaciones
- [x] Unico delta: `'override_hora_invalido'` en `payloadInv` de `router1_crear`.
- [x] A07 traduce el HARD del resolver a `payload_invalido` (evidencia: smoke).
- [x] El HARD no crea pre-reserva ni huesped: corta en 3.5 antes de `upsert_huesped`/INSERT (evidencia: `prereservas_smoke=0`, `huespedes_smoke=0`).
- [x] Fixture limpio (teardown `overrides_restantes=0`, postcheck `overrides_smoke=0`).
- [x] A08 fuera de alcance por evidencia: `crear_bloqueo` no llama a `resolver_horario()` ni puede emitir `override_hora_invalido` (seria dead code).
- [x] No se toco gateway, frontend, SQL de negocio, canonico, OPS ni `obtener_disponibilidad_rango`.
- [x] Sin `D-*` ni `L-*`.

## 5. Que NO se toco
Gateway `portal-api`; frontend; todas las funciones SQL de negocio (`crear_prereserva` incluida - el delta vive solo en el wrapper n8n); `6B_SCHEMA_SQL.md`; OPS; A08; `obtener_disponibilidad_rango`. HMAC/credenciales del wrapper intactas (edicion directa, no re-import).

## 6. Rollback
Abrir `router1_crear` en n8n TEST, quitar `,'override_hora_invalido'` del array `payloadInv`, guardar (o re-importar el template previo). Vuelve a `error_interno`. Trivial, sin efectos colaterales. Fixture: `HORARIOS_A07UX_TEARDOWN_TEST.sql` (idempotente, ya corrido).

## 7. Formalizacion (diferida)
Los `D-*`/`L-*` de este mini-bloque, junto con los de la integracion B3 y el guard B2, se acunan y se propagan a satelites (`ESTADO_ACTUAL`, `DECISIONES_NO_REABRIR`, `Lecciones_Aprendidas`, etc.) en **un solo paso coordinado**, al cierre del frente completo de horarios. No se abre ahora.

---

## Proximo paso diferido - BLOQUE PRINCIPAL DE MOTOR
**Relevamiento/diseno: integrar `resolver_horario()` en `obtener_disponibilidad_rango`** (funcion de lectura).

Objetivo: saldar el hardcode de horarios de la funcion de disponibilidad de rango, alineandola con el motor formal ya cableado en `crear_prereserva` (B3).

Primer paso del bloque (modo relevamiento, sin tocar nada):
1. Clonar fresco el repo y leer la definicion live de `obtener_disponibilidad_rango` (canonico + fuente real).
2. Mapear exactamente donde y como hardcodea horarios de check-in/check-out.
3. Definir la **forma de salida** que expone hoy (que campos de horario y en que estructura) para no romper el frontend que la consume.
4. Decidir el tratamiento del HARD del resolver en una funcion de LECTURA (no puede "rebotar" una reserva; hay que definir si degrada, omite, o marca la fecha) - punto de diseno central, distinto de `crear_prereserva`.
5. Recien entonces: diseno del delta -> aprobacion -> artefactos -> ejecuta Franco -> verifica Claude.

Menor riesgo que `crear_prereserva` (no escribe), pero el contrato de salida hacia el frontend es el punto sensible.
