# 7A_DOCUMENTACION_PENDIENTE.md — Working Note

> **ESTADO: WORKING NOTE TEMPORAL — NO ES CIERRE FORMAL NI CANÓNICO**
>
> Este archivo es un checklist temporal para no perder trabajo documental
> pendiente de la Etapa 7A. **No reemplaza** `6B_SCHEMA_SQL.md`,
> `7A_CIERRE.md` ni ninguna decisión en `DECISIONES_NO_REABRIR.md`.
>
> El bump documental del canónico a v1.7.3 está **deliberadamente postergado**
> hasta cerrar también el bloque del horizonte configurable 120 días
> (PreOPS-A6), para no editar los mismos archivos dos veces.
>
> **Mientras este archivo exista, NO se deben tocar los archivos finales
> listados en la sección "Archivos a actualizar luego".**

---

## Contexto de la etapa

**Etapa 7A — Correcciones pre-TEST / pre-OPS.**

Objetivo: resolver pendientes livianos de `Pendiente_pre_produccion.md` antes
de levantar TEST/OPS y antes de diseñar dashboard. Estrategia general aprobada:
DEV → TEST → OPS → PROD. Esta etapa opera **solo en DEV**.

**Schema funcional en DEV:** v1.7.3 (aplicado, validado, **pendiente de bump
documental**). El canónico `6B_SCHEMA_SQL.md` sigue marcado v1.7.2 hasta
PreOPS-A7.

---

## Estado de bloques PreOPS-A1 a PreOPS-A5

| Bloque | Descripción | Estado |
|---|---|---|
| PreOPS-A1 | Snapshot read-only de contrato real (DEV) | ✅ Cerrado |
| PreOPS-A2 | Decisión final sobre opciones (Opción A + Opción A) | ✅ Cerrado |
| PreOPS-A3 | Diseño del patch SQL + tests + rollback | ✅ Cerrado |
| PreOPS-A4 | Ejecución del patch + verificación estructural (T4) | ✅ Cerrado |
| — | Tests funcionales obligatorios 9/9 | ✅ Cerrado |
| — | Cleanup de pre-reservas de test (5/5) | ✅ Cerrado |
| PreOPS-A5 | Limpieza legacy `ninos='false'` (3 filas) | ✅ Cerrado |
| PreOPS-A6 | Horizonte configurable disponibilidad/calendario a 120 días | ✅ Cerrado |

**Bloques siguientes (no iniciados):**

| Bloque | Descripción | Estado |
|---|---|---|
| PreOPS-A7 | Documentación y bump canónico v1.7.3 | ⏳ Pendiente |
| PreOPS-A8 | Cierre formal 7A (`7A_CIERRE.md`) | ⏳ Pendiente |

---

## Resumen del patch ya aplicado en `crear_prereserva`

**Función:** `crear_prereserva(payload jsonb)`. Aplicado en DEV vía
`CREATE OR REPLACE FUNCTION` (camino limpio, sin bug del Dashboard).

**3 cambios quirúrgicos, nada más:**

1. Declaración: `v_ninos BOOLEAN` → `v_ninos TEXT`.
2. Extract: `v_ninos := COALESCE(NULLIF(TRIM(payload->>'ninos'), '')::BOOLEAN, FALSE);`
   → `v_ninos := NULLIF(TRIM(payload->>'ninos'), '');`
3. Validación de obligatorios: agregado `OR v_canal_pago_esperado IS NULL`
   al IF que rebota con `payload_invalido`.

**Sin cambios en:** firma, retorno, locks, idempotencia, validación de cabaña,
validación de disponibilidad, cálculo de horarios (regla D47 dominical intacta),
INSERT, logs. El comentario del cuerpo NO lleva marcas v1.7.3 (decisión: el
versionado vive en changelog/bitácora/canónico, no en el cuerpo operativo).

**Verificación estructural post-deploy (T4):** `pg_get_functiondef` confirma
los 3 cambios presentes y ninguna divergencia adicional.

---

## Decisiones fuertes PENDIENTES DE DOCUMENTAR

Estas tres van a `DECISIONES_NO_REABRIR.md` en PreOPS-A7. **Todavía no escritas
ahí.** (D-7A-01 y D-7A-02 del patch `crear_prereserva`; D-7A-03 del horizonte
configurable de A6.)

- **D-7A-01** — `canal_pago_esperado` requerido en la validación manual de
  `crear_prereserva`. Si llega ausente / vacío / whitespace, la función rebota
  con `error='payload_invalido'` (rebote temprano, antes de locks y antes de
  `upsert_huesped`). La columna `pre_reservas.canal_pago_esperado` permanece
  `TEXT NOT NULL`. El CHECK de 5 valores permanece. **Fuera de alcance:**
  validación manual de valores no-NULL fuera del CHECK (ej. `"canal_invalido"`)
  — esos siguen rebotando por constraint, no por validación manual.

- **D-7A-02** — `ninos` modelado como `TEXT nullable` en variable local y en
  columnas (`pre_reservas.ninos`, `reservas.ninos` ya eran TEXT). Semántica:
  `NULL` = no informado; texto libre = detalle operativo (cantidad/edades/
  necesidades). El literal `"false"` **no** es valor esperado nuevo. **No** se
  introduce `detalle_ninos` (se evaluará solo si aparece necesidad operativa
  concreta).

- **D-7A-03** — Horizonte de `vista_disponibilidad` y `vista_calendario`
  configurable vía `configuracion_general.horizonte_disponibilidad_dias`, con
  fallback `120` por `COALESCE`. Valor actual en DEV: `120`. Convenciones de
  rango (cada vista mantiene la suya, solo cambió el valor del horizonte):
  `vista_disponibilidad` exclusiva `[CURRENT_DATE, CURRENT_DATE + N)` vía
  `obtener_disponibilidad_rango`; `vista_calendario` inclusiva `<= CURRENT_DATE + N`.

---

## PreOPS-A6 — Horizonte configurable (resumen)

**Clave `horizonte_disponibilidad_dias`:**
- Ya existía en DEV antes de A6 (valor `120`). Origen no confirmado en esta
  sesión; probablemente de ejecución histórica/intermedia de DEV
  (`6B_EJECUCION_DEV.md`, no auditado). **No documentar como "creada en A6".**
- A6.1 solo cambió la `descripcion` a "Horizonte forward en días para
  vista_disponibilidad y vista_calendario". No tocó `valor` ni `tipo_valor`.

**Vistas conectadas (CREATE OR REPLACE VIEW):**
- `vista_disponibilidad`: segundo arg de `obtener_disponibilidad_rango` pasó de
  `CURRENT_DATE + 60` a lectura de config con fallback 120. 9 columnas
  preservadas.
- `vista_calendario`: filtro `WHERE r.fecha_checkin <= (CURRENT_DATE + 60)` pasó
  a lectura de config con fallback 120, operador `<=` inclusivo mantenido. 13
  columnas preservadas, `TRIM(BOTH FROM ...)` de H6 preservado.

**Tests (4/4):**
- T-A6-1 empírico `vista_disponibilidad`: `dias_distintos=120`, `filas=600`,
  `fecha_max = CURRENT_DATE + 119 = 2026-09-24`. ✅
- T-A6-2 estructural `vista_calendario`: usa la clave, sin `+60` residual,
  columnas intactas. ✅
- T-A6-3 no-regresión: reserva 8 sigue apareciendo. ✅
- T-A6-4 estructural `vista_disponibilidad`: usa la clave, sin `+60` residual,
  columnas intactas. ✅

**Nota para el canónico (A7):** la forma persistida de `vista_disponibilidad`
**no** incluye el `::DATE` que se escribió en el SQL propuesto — PostgreSQL lo
absorbió porque `CURRENT_DATE + INTEGER` ya retorna DATE. Documentar en
`6B_SCHEMA_SQL.md` la forma persistida real (sin `::DATE`), capturada vía
`pg_get_viewdef`. Las viewdefs reales post-A6 están en los resultados de
T-A6-2 y T-A6-4.

**Hallazgo lateral — `tipo_valor` generalizado:** las 10 claves de
`configuracion_general` tienen `tipo_valor = NULL` (no solo el horizonte).
**No es bloqueo de A6.** Observación para evaluar antes del dashboard OPS: si
el dashboard usa `tipo_valor` para renderizar inputs, conviene poblar las 10
claves. Candidato a item nuevo en `Pendiente_pre_produccion.md` (NO abrir bloque
en 7A para esto).

---

## Limpieza legacy realizada (NO es decisión fuerte)

Limpieza puntual de datos legacy con `ninos = 'false'` (residuo del cast
implícito BOOLEAN→TEXT de v1.7.2). **Se documenta en bitácora/cierre 7A como
limpieza puntual, NO como D-7A-03 ni como decisión arquitectural.**

| Tabla | Filtro | Acción | Filas |
|---|---|---|---|
| `pre_reservas` | `id_pre_reserva IN (25, 26)` | `ninos → NULL` | 2 |
| `reservas` | `id_reserva = 8` | `ninos → NULL` | 1 |

- Snapshot previo: 3 filas con `ninos='false'` (estados: convertida,
  cancelada_por_cliente, confirmada).
- UPDATE acotado por IDs exactos + condición defensiva `AND ninos='false'`.
  Solo tocó `ninos` y `updated_at`; **no tocó `estado`**.
- `set_config('app.source_event','cleanup_legacy_ninos_7a')` usado como traceo
  auxiliar (no como evidencia principal).
- Snapshot posterior: 3 filas con `ninos IS NULL`, estados sin cambio.
- Verificación de ausencia total: 0 filas con `ninos='false'` en `pre_reservas`
  y 0 en `reservas`.

Evidencia principal = conteo previo/posterior documentado (arriba).

---

## Tests funcionales obligatorios — 9/9 aprobados

| ID | Escenario | Resultado |
|---|---|---|
| T1.1 | `canal_pago_esperado` válido (camino feliz) | ✅ ok=true, pre-reserva creada |
| T1.2 | `canal_pago_esperado` ausente | ✅ `payload_invalido` |
| T1.3 | `canal_pago_esperado` `""` | ✅ `payload_invalido` |
| T1.4 | `canal_pago_esperado` `"   "` (whitespace) | ✅ `payload_invalido` |
| T2.1 | `ninos` ausente | ✅ `ninos IS NULL` persistido |
| T2.2 | `ninos` `""` | ✅ `ninos IS NULL` persistido |
| T2.3 | `ninos` `"2 niños, 3 y 6 años"` | ✅ texto operativo preservado (UTF-8 OK) |
| T2.4 | `ninos` `"  Bebé con cuna  "` | ✅ TRIM aplicado, LENGTH=13 |
| T4 | Verificación estructural post-deploy | ✅ 3 cambios confirmados |

Hallazgo lateral validado: regla D47 dominical sigue operativa post-patch
(T2.1 checkin domingo 18:00; T2.2 checkout domingo 16:00).

**Frenos:** ninguno activado. **Rollback:** no necesario.

---

## Cleanup de tests 7A — completado

5 pre-reservas de test creadas (id 35, 36, 37, 38, 39) canceladas vía
`cancelar_prereserva` con `motivo='cliente'` → estado `cancelada_por_cliente`.
`source_event` específico por test (`cleanup_test_7a_t11` … `cleanup_test_7a_t24`).
0 pagos asociados. Pre-reservas conservadas como evidencia (no borradas).

**Nota de contrato confirmada:** `cancelar_prereserva` acepta `motivo` ∈
`{'cliente','bloqueo'}` únicamente (no `motivo_cancelacion`/`cancelado_por`).
Campos: `id_pre_reserva`, `motivo`, `descripcion` (opcional), `source_event`.

---

## Estado actual de DEV post-A6

| Recurso | Valor | Nota |
|---|---|---|
| Schema funcional | v1.7.3 | Pendiente bump documental |
| Pre-reservas | 7 | 2 baseline + 5 tests 7A (terminales) |
| Huéspedes | 3 | 2 baseline + 1 test 7A (id 45) |
| Reservas | 1 | reserva 8 baseline (ahora `ninos=NULL`) |
| Pagos | 1 | sin cambios |
| Bloqueos | 2 | sin cambios |
| Logs | 26 | +15 vs baseline pre-tests (11) |
| Filas con `ninos='false'` | 0 | post limpieza legacy |
| `vista_disponibilidad` | horizonte 120 | configurable, 600 filas / 120 días |
| `vista_calendario` | horizonte 120 | configurable, filtro `<=` inclusivo |
| `horizonte_disponibilidad_dias` | `120` | preexistente; descripción actualizada en A6 |

Baseline pre-tests era: pre_reservas=2, huespedes=2, log_cambios=11,
pre_reservas_activas_7a=0. A6 no modificó conteos de datos (solo config + vistas).

---

## Archivos a actualizar LUEGO (NO TOCAR todavía)

Se actualizan recién en **PreOPS-A7**, juntando los cambios de v1.7.3
(patch `crear_prereserva`) + horizonte configurable (PreOPS-A6), para no
editarlos dos veces.

| Archivo | Cambios pendientes |
|---|---|
| `6B_SCHEMA_SQL.md` | Bump v1.7.2→v1.7.3; cuerpo `crear_prereserva`; changelog; mover hallazgos `ninos`/`canal_pago_esperado` a resueltos; backup v1.7.2 a `Archivados/`. **+ A6: viewdefs reales post-cambio de `vista_disponibilidad` y `vista_calendario` (forma persistida, SIN `::DATE`); nota de que `horizonte_disponibilidad_dias` es preexistente.** |
| `Pendiente_pre_produccion.md` | Mover 1.2 (`ninos`) y 1.3 (`canal_pago_esperado`) a apéndice cerrado. **+ mover 1.1 (horizonte) a cerrado. + agregar item nuevo: poblar `tipo_valor` en `configuracion_general` antes del dashboard OPS (observación, no bloqueo).** |
| `ESTADO_ACTUAL_VITA_DELTA.md` | Schema → v1.7.3; quitar hallazgos no resueltos; actualizar estado de DEV (pre_reservas 7, huespedes 3, logs 26, 0 `'false'`). **+ horizonte de vistas a 120 configurable.** |
| `DECISIONES_NO_REABRIR.md` | Agregar D-7A-01, D-7A-02 **y D-7A-03 (horizonte configurable)**. |
| `7A_CIERRE.md` (nuevo) | Cierre formal de toda la etapa (patch + limpieza + horizonte). Se crea en A8. |
| `Lecciones_Aprendidas.md` | **Solo si aplica.** Candidatas a evaluar: (a) SQL Editor de Supabase muestra solo el último statement del run; (b) PostgreSQL absorbe casts redundantes como `::DATE` sobre `CURRENT_DATE + INTEGER` al persistir vistas. Verificar si ya están documentadas (L-6D-02 cubre normalización de expresiones) antes de duplicar. |

---

## Próximos pasos (orden acordado)

1. ~~**PreOPS-A6 — Horizonte configurable 120 días.**~~ ✅ **Cerrado.** Clave
   preexistente normalizada (descripción), ambas vistas conectadas a la config,
   4 tests aprobados.
2. **PreOPS-A7 — Documentación y bump canónico v1.7.3** (juntando patch
   `crear_prereserva` + horizonte A6). Próximo paso.
3. **PreOPS-A8 — Cierre formal 7A** (`7A_CIERRE.md`), y borrar esta working note.

---

_Working note creada al cierre de PreOPS-A5. Actualizada al cierre de PreOPS-A6._
_Borrar al completar PreOPS-A8._
