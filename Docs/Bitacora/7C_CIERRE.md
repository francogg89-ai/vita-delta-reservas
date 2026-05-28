# 7C_CIERRE.md — Cierre formal Etapa 7C

**Etapa:** 7C — Validación funcional ampliada sobre TEST
**Estado:** ✅ Cerrada (validación funcional ampliada con casos no-felices)
**Fecha de cierre:** 2026-05-28
**Entorno validado:** Supabase TEST (`vita-delta-test`, sa-east-1, Free tier)
**Schema de referencia:** `6B_SCHEMA_SQL.md v1.7.3` (no modificado)
**Autores:** Franco (titular) + Claude (arquitecto)

---

## 1. Resumen ejecutivo

La Etapa 7C ejecutó la **validación funcional ampliada** de los 8 workflows n8n
`__TEST` sobre el entorno TEST levantado en 7B: la batería sistemática de
caminos no-felices (errores controlados, edge cases, validaciones defensivas,
condiciones de borde) que 7B dejó fuera de alcance al elegir happy paths como
evidencia de levantamiento.

Donde 7B demostró que el entorno **existe y es paritario** (paridad estructural
10/10 vs DEV) y que los caminos felices funcionan, 7C demuestra que el sistema
**se comporta como espera bajo casos negativos**: rebota con errores controlados
(`ok:false` + código semántico), no produce escrituras espurias, normaliza
entradas defensivas y mantiene la trazabilidad (doble logging + `source_event`).

La validación se ejecutó manualmente: Franco editó el nodo `Build Input` de cada
workflow, ejecutó en su instancia n8n contra TEST, y pegó cada output completo de
`Build Response`; Claude validó PASS/FAIL contra una matriz pre-aprobada. Claude
no ejecutó workflows ni tocó Supabase mediante herramientas (decisión de
seguridad: los workflows `__TEST` son manuales con inputs hardcodeados, y se
evitó introducir incertidumbre sobre workflow IDs, credenciales o instancia
conectada).

**Resultado global:**

- **48 casos funcionales (Grupo A)** — todos conformes.
- **6 verificaciones transversales** (TR-01 source_event + TR-02 doble logging) —
  todas conformes.
- **54 verificaciones conformes en total.**
- **0 fallos inesperados.** 1 mutación no planificada pero válida y comprendida:
  bloqueo id 2.
- **2 comportamientos observados/documentados** (ninguno es defecto): rango
  invertido con set vacío, y bloqueo id 2 generado por A-W6-06 como mutación no
  planificada pero entendida.

---

## 2. Alcance y método

### 2.1 Lo que SÍ cubrió 7C

Cobertura funcional ampliada de los casos ejecutables vía workflows `__TEST`
definidos para 7C, agrupados por workflow:

- **W0:** smoke de conexión contra TEST.
- **W1:** comportamiento de `obtener_disponibilidad_rango` ante cabaña
  inexistente, rango invertido, fuera de horizonte, fixture ocupado, fecha mal
  formada.
- **W2:** validaciones de payload, capacidad, cabaña, solapamientos
  (reserva/pre-reserva/bloqueo), hora fuera de rango, normalización whitespace,
  idempotencia rama `pre_lock`.
- **W3:** payload inválido, referencia requerida, pre-reserva/reserva inexistente,
  pago sobre pre-reserva convertida, monto inconsistente.
- **W4:** payload inválido, pre-reserva inexistente, re-confirmación de convertida,
  camino estricto sin pago confirmado, camino combinado sin pago asociado.
- **W5:** payload inválido, motivo inválido, pre-reserva inexistente, estados no
  cancelables (cancelada, convertida).
- **W6:** payload inválido, fechas inválidas, motivo inválido, `id_cabana:0`,
  conflictos con reserva/pre-reserva/bloqueo.
- **W7:** vista inválida (validación en n8n), vista vacía sin detención de flujo,
  clamp de límite.
- **Transversales:** persistencia de `source_event` con marcador de ambiente,
  doble logging en transición de estado.

Quedaron explícitamente fuera de alcance de 7C: `unique_violation`, cabaña
inactiva, `conflicto_al_confirmar` forzado y carga/concurrencia pesada (ver
sección 11).

### 2.2 Método de ejecución

Patrón seguro confirmado al inicio de la etapa:

1. Franco edita el nodo `Build Input` con los valores exactos dictados por la
   matriz.
2. Franco ejecuta el workflow en su instancia n8n.
3. Franco pega el output completo de `Build Response` (o el error crudo del
   Postgres node si aplica).
4. Claude valida PASS/FAIL contra el expected pre-derivado del cuerpo SQL real.
5. Claude no opera n8n ni Supabase por herramientas.

Los expected outputs se anclaron al **código SQL real** de las funciones (leído
de `6B_SCHEMA_SQL.md v1.7.3`), no a supuestos. Esto corrigió tres asunciones del
plan v1 antes de ejecutar (ver sección 6).

---

## 3. Resultados por bloque

| Bloque | Contenido | Casos | Resultado |
|---|---|---|---|
| 7C-1 | W0 + W1 + W7 (read-only) | 9 | ✅ 9/9 |
| 7C-2 | W2 rebotes tempranos | 12 | ✅ 12/12 |
| 7C-3 | Fixture viva + solapamientos W2/W6 + rebotes W6 | 9 | ✅ 9/9 |
| 7C-4 | Cadena pago/confirmación (W3/W4) | 12 | ✅ 12/12 |
| 7C-5 | Cancelaciones (W5) + idempotencia pre_lock | 6 | ✅ 6/6 |
| 7C-6 | Verificaciones transversales (TR-01/TR-02) | 6 | ✅ 6/6 |

**Grupo A funcional: 48/48. Transversales: 6/6. Total: 54/54.**

### 3.1 Detalle Grupo A (48 casos)

**W0/W1/W7 (7C-1):** A-W0-01 (smoke de conexión, `db=postgres`) · A-W1-05 (todas
las cabañas, `id_cabana:null`, 20 días) · A-W1-04 (fixture ocupado, reserva id 1
reflejada, regla dominical D47 observada en el tramo) · A-W1-03 (fuera de
horizonte, `ok:true`, confirma que la función no recorta) · A-W1-02 (rango
invertido, `ok:true, 0 días` — observado) · A-W7-02 (vista vacía, no detiene
flujo) · A-W7-03 (clamp 99999→5000) · A-W7-01 (vista inválida, error en n8n,
Postgres no ejecuta) · A-W1-06 (fecha mal formada, error crudo del Postgres node).

**W2 rebotes (7C-2):** payload_invalido, precio_requerido,
huesped_nombre_requerido, huesped_contacto_requerido, fechas_invalidas,
cabana_no_existe, excede_capacidad (grande cap 5 / chica cap 4), no_disponible vs
reserva, no_disponible vs bloqueo, hora_fuera_de_rango (min 13:00 / max 22:00),
normalización whitespace. Ninguno creó pre-reserva.

**Fixture + solapamientos (7C-3):** A-W2-12 creó la fixture viva (pre-reserva id 3,
Madre Selva, `pendiente_pago`, huésped id 3). A-W2-13 (no_disponible vs
pre_reservas). W6 rebotes: payload_invalido, fechas_invalidas, motivo_invalido,
cabana_no_existe (`id_cabana:0`). W6 solapamientos: conflicto_con_reserva [1],
conflicto_con_prereserva [3], bloqueo_solapado [1].

**Cadena pago/confirmación (7C-4):** W3 rebotes (payload_invalido,
referencia_requerida, prereserva_no_existe, reserva_no_existe). A-W3-05 (pago id 2
sobre pre-reserva convertida id 2, `en_revision`, **sin warning**). A-W3-06 (pago
id 3 sobre pre-reserva 3, monto inconsistente 50k/30k → `en_revision`, promovió
pre-reserva 3 a `pago_en_revision`). W4: payload_invalido, prereserva_no_existe,
estado_invalido/convertida, sin_pago_confirmado (estricto), A-W4-05a (fixture
dedicada pre-reserva id 4, Tokio, huésped id 5, checkout 16:00 por domingo
13-sep), sin_pago_asociado (combinado).

**Cancelaciones + idempotencia (7C-5):** payload_invalido (motivo vacío),
motivo_invalido (`"otro"` válido en W6 pero no en W5), prereserva_no_existe,
estado_no_cancelable/cancelada (id 1), estado_no_cancelable/convertida (id 2),
A-W2-15 idempotencia `pre_lock` (devolvió pre-reserva 3 existente con estado
actual `pago_en_revision`, sin crear).

### 3.2 Detalle transversales (6 verificaciones)

- **TR-01:** logs de 7C aislados por timestamp de las tablas transaccionales —
  2 `prereserva_creada` (id 3, id 4), 2 `pago_registrado` (id 2, id 3),
  1 `bloqueo_creado` (id 2), todos nivel `info`. 2 pre-reservas, 2 pagos y
  1 bloqueo creados por 7C (confirma que ~30 rebotes no escribieron datos).
- **TR-02:** doble logging confirmado en la promoción de la pre-reserva 3 (log de
  negocio `pago_registrado` id_log 15 de la función + log de transición de estado
  id_log 14 del trigger `pendiente_pago`→`pago_en_revision`, ambos con
  `source_event` heredado vía `set_config` D38). Pago sobre convertida (id 2) sin
  transición ni warning, confirmando L-7C-04.

> Nota metodológica: el filtro inicial por `fecha_hora >= hoy` capturó también la
> actividad de 7B (mismo día calendario). La reconciliación se hizo por timestamp
> horario sobre las tablas transaccionales, que sí discriminan 7B (18:00-18:15
> UTC) de 7C (20:36-21:26 UTC). Los conteos quedaron exactos tras separar ambas
> etapas.

---

## 4. Cobertura de idempotencia

- **`post_lock`:** ya observada empíricamente en H7/C-6 (Etapa 6D).
- **`pre_lock`:** observada en 7C (A-W2-15), reproducida de forma secuencial y
  controlada, sin concurrencia (consistente con la regla de no convertir 7C en
  etapa de concurrencia pesada). Devolvió la pre-reserva existente con su estado
  actual (`pago_en_revision`), sin crear duplicado.
- **`unique_violation`:** **fuera de alcance de 7C** (cobertura opcional pre-PROD;
  requiere cruce concurrente en ventana estrechísima, no reproducible de forma
  simple). Permanece como pendiente opcional no bloqueante
  (`Pendiente_pre_produccion.md` 6.3).

Dos de las tres ramas del detector de idempotencia quedan cubiertas
empíricamente.

---

## 5. Comportamientos observados/documentados (no son defectos)

### 5.1 Rango invertido devuelve set vacío

`obtener_disponibilidad_rango` con `fecha_desde > fecha_hasta` (A-W1-02,
15-jul→10-jul) devolvió wrapper `ok:true, total_dias:0, dias:[]` — no error, no
fallo del Postgres node. El workflow W1 degrada con gracia ante rango invertido.
Comportamiento esperado y aceptado. → L-7C-01.

### 5.2 Bloqueo id 2 — mutación no planificada pero entendida

Durante A-W6-06 (primer intento), se ejecutó con `id_cabana:1` (Bamboo) en lugar
de `2` (Madre Selva). Como Bamboo no tenía conflicto en 2-3 ago, el payload era
válido y el sistema **creó correctamente** el bloqueo id 2 (Bamboo,
2026-08-02→08-03, motivo `mantenimiento`, activo). El segundo intento, con
`id_cabana:2`, dio el `conflicto_con_prereserva` esperado.

Esto **no es un bug**: el sistema hizo lo correcto ante un payload válido. Es un
dato de prueba extra, trazable por `id_evento_test: manual_test_7c3_w6_conf_pre`.
Validó incidentalmente un happy path de W6 (creación de bloqueo específico sobre
cabaña libre) que no estaba en la matriz. Por decisión D-7C-01, se conserva como
evidencia y queda marcado para el bloque de limpieza/reset futuro.

---

## 6. Correcciones de plan ancladas al código real

Antes de ejecutar, la lectura del cuerpo SQL real corrigió tres asunciones del
plan v1:

1. **W1 no tiene errores de negocio:** `obtener_disponibilidad_rango` devuelve
   `SETOF`, no JSONB de error. Cabaña inexistente / rango inválido →
   `ok:true, 0 días`, no `ok:false`.
2. **Pago sobre convertida no da warning:** la lista terminal de `registrar_pago`
   es `vencida, cancelada_por_cliente, cancelada_por_bloqueo, conflicto_pendiente`;
   `convertida` no está incluida. Verificado empíricamente (A-W3-05).
3. **Monto inconsistente no es error:** con `estado_inicial` vacío,
   `registrar_pago` deja el pago en `en_revision` sin comparar montos. Verificado
   (A-W3-06).

---

## 7. Lecciones aprendidas (L-7C)

- **L-7C-01:** `obtener_disponibilidad_rango` con rango invertido devuelve set
  vacío (`ok:true, 0 días`), no error.
- **L-7C-02:** el horizonte de 120 días vive en las vistas
  (`vista_disponibilidad`), no en la función `obtener_disponibilidad_rango`; W1
  (vía función) entrega cualquier rango futuro.
- **L-7C-03:** fecha mal formada genera error crudo del Postgres node, sin wrapper
  controlado (confirma pendiente #2 del ESTADO_ACTUAL).
- **L-7C-04:** pago sobre pre-reserva `convertida` no dispara
  `prereserva_no_activa`; solo aplican los estados terminales listados por la
  función (`vencida, cancelada_por_cliente, cancelada_por_bloqueo,
  conflicto_pendiente`).
- **L-7C-05:** `id_cabana:0` en W6 no significa bloqueo total; da
  `cabana_no_existe`. El bloqueo total se pide con `id_cabana:null`. El patrón
  `0=todas` es exclusivo de W1.
- **L-7C-06:** `log_cambios` usa `fecha_hora` como columna de timestamp, mientras
  las tablas transaccionales (`pre_reservas`, `pagos`, `bloqueos`) usan
  `created_at`. A tener presente en queries de auditoría.

---

## 8. Decisiones tomadas en 7C

### D-7C-01 — Política de no-limpieza de fixtures de 7C

Los datos vivos generados durante 7C se conservan como evidencia: pre-reservas
id 3 (`pago_en_revision`) e id 4 (`pendiente_pago`), pagos id 2 e id 3
(`en_revision`), bloqueo id 2 (Bamboo, activo), huéspedes id 3 e id 5. Cualquier
reset/limpieza de TEST debe ser un **bloque separado, con SQL explícito y
aprobación previa** — no se improvisa caso por caso ni en medio de una
validación. **No reabrir.**

---

## 9. Estado de fixtures en TEST tras 7C

| Dato | Estado | Origen |
|---|---|---|
| Pre-reserva id 1 (Bamboo, 10-13 jul) | cancelada_por_cliente | 7B |
| Pre-reserva id 2 (Bamboo, 10-13 jul) | convertida | 7B (+ pago id 2 asociado, sin transición de estado, de A-W3-05) |
| Pre-reserva id 3 (Madre Selva, 1-4 ago) | pago_en_revision | A-W2-12 → A-W3-06 |
| Pre-reserva id 4 (Tokio, 10-13 sep) | pendiente_pago | A-W4-05a |
| Reserva id 1 (Bamboo) | confirmada | 7B |
| Pago id 1 | confirmado | 7B |
| Pago id 2 (sobre pre 2) | en_revision | A-W3-05 |
| Pago id 3 (sobre pre 3) | en_revision | A-W3-06 |
| Bloqueo id 1 (Arrebol, 20-22 nov) | activo | 7B |
| Bloqueo id 2 (Bamboo, 2-3 ago) | activo | A-W6-06 (no planificado, conservado) |
| Huéspedes id 1, 3, 5 | activos | 7B / A-W2-12 / A-W4-05a |

---

## 10. Lo que 7C NO es / NO hace

- **No es OPS.** No diseña ni levanta el entorno de operación interna.
- **No es PROD.**
- **No habilita consumidores reales.**
- **No conecta MercadoPago real, bot, frontend ni dashboard.**
- **No toca DEV.** La validación ocurrió íntegramente sobre TEST.
- **No modifica el schema canónico `6B_SCHEMA_SQL.md v1.7.3`.** 7C es validación de
  comportamiento, no cambia SQL.
- **No limpia fixtures de TEST.** Todo dato generado se conserva como evidencia
  (D-7C-01).

---

## 11. Pendientes que permanecen abiertos tras 7C

(Ninguno nuevo bloqueante; se mantienen los heredados.)

- Endurecimiento de permisos Data API en DEV (`Pendiente_pre_produccion.md` 1.5).
- Cobertura empírica de `unique_violation` (opcional, 6.3).
- `conflicto_al_confirmar` forzado (Grupo B/C, no ejecutado — requiere manipular
  timing bajo lock).
- Cabaña inactiva (Grupo C — no ejecutable sin fixture estructural aprobado; no se
  creó ni desactivó ninguna cabaña).
- Validación de tipos inválidos no-vacíos (`id_cabana:"abc"`, error crudo —
  pendiente histórico #2).
- `tipo_valor` sin poblar en `configuracion_general` (1.4).
- Revisión futura del contrato SQL de `registrar_pago` frente a entradas no-vacías
  mal tipadas; hoy mitigado en workflows por `nv()` defensivo para
  vacíos/undefined.
- Tests de carga real, RLS, tarifas/feriados productivos (pendientes históricos).
- Diseño del bloque de limpieza/reset de TEST (necesario por la acumulación de
  fixtures de 7C).

---

## 12. Próximo paso recomendado

Con TEST levantado (7B) y validado funcionalmente de punta a punta (7C), las
opciones disponibles a priorizar por Franco (no comprometidas en este cierre), en
el orden sugerido:

1. **Diseño del bloque de limpieza/reset de TEST** (dado D-7C-01 y la acumulación
   de fixtures de 7C).
2. **Endurecimiento de permisos en DEV** (paridad con TEST).
3. **Diseño del entorno OPS.**
4. **Consumidores reales sobre TEST** (webhook MP, bot, frontend), con decisión
   explícita.

No avanzar a OPS/PROD, MercadoPago real, bot o frontend sin decisión explícita.

---

_Cierre formal de Etapa 7C — 2026-05-28._
