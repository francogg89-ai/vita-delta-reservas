# 7A_CIERRE.md — Cierre formal Etapa 7A

**Etapa:** 7A — Correcciones pre-TEST / pre-OPS
**Estado:** ✅ Cerrada
**Fecha de cierre:** 2026-05-28
**Entorno:** Supabase DEV (único entorno operativo)
**Schema canónico resultante:** `6B_SCHEMA_SQL.md v1.7.3`
**Autores:** Franco (titular) + Claude (arquitecto)

---

## 1. Resumen ejecutivo

La Etapa 7A resolvió tres pendientes livianos documentados en
`Pendiente_pre_produccion.md` (secciones 1.1, 1.2, 1.3) antes de levantar el
entorno TEST, el entorno OPS y el dashboard operativo. Todos los cambios se
aplicaron y validaron en DEV. No se tocó TEST, OPS ni PROD (no existen aún).

Resultado: DEV quedó alineado funcionalmente con el schema canónico
`6B_SCHEMA_SQL.md v1.7.3`, con los tres hallazgos cerrados, un dataset limpio
de residuos legacy y el horizonte de disponibilidad/calendario configurable.

**Estrategia general vigente:** DEV → TEST → OPS → PROD. Esta etapa operó solo
en DEV.

---

## 2. Alcance y bloques

La etapa se ejecutó con la disciplina de bloques numerados (PreOPS-A1 a A8),
cada uno con snapshot read-only previo, diseño aprobado, ejecución y validación.

| Bloque | Descripción | Estado |
|---|---|---|
| PreOPS-A1 | Snapshot read-only de contrato real (DEV) | ✅ |
| PreOPS-A2 | Decisión final de opciones (Opción A + Opción A) | ✅ |
| PreOPS-A3 | Diseño del patch SQL + tests + rollback | ✅ |
| PreOPS-A4 | Ejecución del patch `crear_prereserva` + verificación estructural (T4) | ✅ |
| — | Tests funcionales obligatorios (T1.1-T1.4, T2.1-T2.4) | ✅ 9/9 |
| — | Cleanup de pre-reservas de test (5/5) | ✅ |
| PreOPS-A5 | Limpieza puntual de datos legacy `ninos='false'` (3 filas) | ✅ |
| PreOPS-A6 | Horizonte configurable disponibilidad/calendario (60 → 120) | ✅ |
| PreOPS-A7 | Documentación y bump canónico v1.7.3 | ✅ |
| PreOPS-A8 | Cierre formal (este documento) | ✅ |

---

## 3. Cambios aplicados en DEV

### 3.1 Patch en `crear_prereserva` (Bloque 13 del schema)

Tres cambios quirúrgicos vía `CREATE OR REPLACE FUNCTION` (camino limpio, sin el
bug del Dashboard sobre variables `v_`):

1. Declaración `v_ninos`: `BOOLEAN` → `TEXT`.
2. Extract `v_ninos`: `COALESCE(NULLIF(TRIM(payload->>'ninos'), '')::BOOLEAN, FALSE)`
   → `NULLIF(TRIM(payload->>'ninos'), '')`.
3. IF de obligatorios: agregado `OR v_canal_pago_esperado IS NULL`.

Sin cambios en firma, retorno, locks, idempotencia, validación de
cabaña/disponibilidad, cálculo de horarios (regla D47 dominical intacta), INSERT
ni logs.

### 3.2 Horizonte configurable (Bloque 20 del schema)

`vista_disponibilidad` y `vista_calendario` actualizadas vía
`CREATE OR REPLACE VIEW` para leer el horizonte forward desde
`configuracion_general.horizonte_disponibilidad_dias` con fallback `120`
(antes hardcoded `CURRENT_DATE + 60`).

- `vista_disponibilidad`: rango exclusivo `[CURRENT_DATE, CURRENT_DATE + N)`.
- `vista_calendario`: filtro inclusivo `<= (CURRENT_DATE + N)`, operador sin cambios.
- Cero dependientes de ambas vistas (verificado con `pg_depend`/`pg_rewrite`).

### 3.3 Configuración (Bloque 21 del schema)

La clave `horizonte_disponibilidad_dias` ya existía en DEV antes de 7A (origen
probable: ejecución histórica intermedia, no auditada). 7A solo:
- normalizó su `descripcion` ("Horizonte forward en días para
  vista_disponibilidad y vista_calendario");
- la agregó al seed del Bloque 21 para que TEST/PROD nazcan con ella
  (`categoria='disponibilidad'`, `valor='120'`, conteo de
  `configuracion_general` 9 → 10).

`tipo_valor` se mantuvo `NULL`, coherente con las otras 9 claves.

### 3.4 Limpieza puntual de datos legacy

Los 3 registros con `ninos='false'` (residuo del cast BOOLEAN→TEXT de v1.7.2)
fueron migrados a `NULL`:
- `pre_reservas.id_pre_reserva IN (25, 26)` → `ninos = NULL`.
- `reservas.id_reserva = 8` → `ninos = NULL`.

UPDATE acotado por IDs con condición defensiva `AND ninos='false'`, solo tocó
`ninos` y `updated_at` (no `estado`). Verificación previa/posterior con conteos.
**Es limpieza puntual de datos, no una decisión arquitectural; no tiene número
de decisión.**

---

## 4. Decisiones fuertes registradas

Registradas en `DECISIONES_NO_REABRIR.md`, sección "Correcciones pre-TEST /
pre-OPS (Etapa 7A)".

- **D-7A-01** — `canal_pago_esperado` requerido en validación manual de
  `crear_prereserva` → rebota `payload_invalido` para ausente/vacío/whitespace.
  Columna sigue `TEXT NOT NULL`; CHECK de 5 valores intacto. Validación de
  valores fuera del CHECK queda fuera de alcance.
- **D-7A-02** — `ninos` como TEXT nullable: `NULL` = no informado; texto libre =
  detalle operativo. Sin `detalle_ninos`. El literal `"false"` no es valor
  esperado.
- **D-7A-03** — Horizonte de disponibilidad/calendario configurable vía
  `configuracion_general.horizonte_disponibilidad_dias`, fallback 120.
  `vista_disponibilidad` exclusiva `[)`, `vista_calendario` inclusiva `<=`.

La limpieza legacy de `ninos='false'` **no** generó decisión (sin número).

---

## 5. Validación — tests ejecutados

### 5.1 Patch `crear_prereserva` — 9 tests funcionales (9/9 aprobados)

| ID | Escenario | Resultado |
|---|---|---|
| T1.1 | `canal_pago_esperado` válido (camino feliz) | ✅ pre-reserva creada (id 35) |
| T1.2 | `canal_pago_esperado` ausente | ✅ `payload_invalido` |
| T1.3 | `canal_pago_esperado` `""` | ✅ `payload_invalido` |
| T1.4 | `canal_pago_esperado` `"   "` | ✅ `payload_invalido` |
| T2.1 | `ninos` ausente | ✅ `ninos IS NULL` (id 36) |
| T2.2 | `ninos` `""` | ✅ `ninos IS NULL` (id 37) |
| T2.3 | `ninos` `"2 niños, 3 y 6 años"` | ✅ texto preservado, UTF-8 OK (id 38) |
| T2.4 | `ninos` `"  Bebé con cuna  "` | ✅ TRIM aplicado, LENGTH=13 (id 39) |
| T4 | Verificación estructural post-deploy (`pg_get_functiondef`) | ✅ 3 cambios confirmados |

Hallazgo lateral validado: regla D47 dominical operativa post-patch (T2.1
check-in domingo 18:00; T2.2 check-out domingo 16:00).

### 5.2 Horizonte configurable — 4 tests (4/4 aprobados)

| ID | Tipo | Resultado |
|---|---|---|
| T-A6-1 | Empírico `vista_disponibilidad` | ✅ 120 días, 600 filas, `MAX(fecha)=CURRENT_DATE+119` |
| T-A6-2 | Estructural `vista_calendario` | ✅ usa la clave, sin `+60`, columnas intactas |
| T-A6-3 | No-regresión `vista_calendario` | ✅ reserva 8 sigue apareciendo |
| T-A6-4 | Estructural `vista_disponibilidad` | ✅ usa la clave, sin `+60`, columnas intactas |

### 5.3 Cleanup de tests

5 pre-reservas de test (id 35-39) canceladas vía `cancelar_prereserva`
(`motivo='cliente'` → `cancelada_por_cliente`), `source_event` específico por
test. 0 pagos asociados. Conservadas como evidencia (no borradas físicamente).

**Frenos activados:** ninguno. **Rollback:** no necesario en ningún bloque.

---

## 6. Estado de DEV al cierre de 7A

| Recurso | Valor | Nota |
|---|---|---|
| Schema funcional | v1.7.3 | Alineado con canónico |
| Pre-reservas | 7 | 2 baseline 6D + 5 tests 7A (terminales) |
| Huéspedes | 3 | 2 baseline + 1 test 7A (id 45) |
| Reservas | 1 | reserva 8 (`ninos=NULL` tras limpieza) |
| Pagos | 1 | sin cambios |
| Bloqueos | 2 | sin cambios |
| Logs | 26 | +15 vs baseline 7A (5 creaciones + 5 cancelaciones + 5 transiciones) |
| Filas con `ninos='false'` | 0 | limpieza legacy |
| `configuracion_general` | 10 | incluye `horizonte_disponibilidad_dias=120` |
| Horizonte de vistas | 120 | configurable, fallback 120 |

---

## 7. Documentación actualizada

| Archivo | Cambio |
|---|---|
| `6B_SCHEMA_SQL.md` | Bump v1.7.2 → v1.7.3. Header, changelog nuevo, cuerpo `crear_prereserva`, 2 vistas, seed, notas de sección 10.5, nota de cierre en hallazgos v1.7.2. |
| `DECISIONES_NO_REABRIR.md` | Sección nueva con D-7A-01, D-7A-02, D-7A-03. |
| `Pendiente_pre_produccion.md` | Tabla de items cerrados 7A; secciones 1.1/1.2/1.3 marcadas cerradas; item nuevo 1.4 (`tipo_valor`). |
| `ESTADO_ACTUAL_VITA_DELTA.md` | Resumen ejecutivo, schema canónico, estado de DEV, pendientes técnicos → v1.7.3 / post-7A. |
| `7A_CIERRE.md` | Este documento (nuevo). |
| `6B_SCHEMA_SQL_v1.7.2_PRE_PREOPS.md` | Backup del estado pre-7A (archivado por Franco). |

**Working note temporal:** `Docs/Bitacora/7A_DOCUMENTACION_PENDIENTE.md` — su
contenido fue absorbido en los documentos finales. Puede archivarse o borrarse
tras verificación de absorción.

`Lecciones_Aprendidas.md` **no se modificó**: las candidatas (SQL Editor
mostrando solo el último statement; PostgreSQL absorbiendo casts redundantes)
ya están cubiertas por lecciones existentes (L-6C / L-6D-02). No se duplicó.

---

## 8. Observaciones abiertas (no bloqueantes)

- **`tipo_valor` sin poblar:** las 10 claves de `configuracion_general` tienen
  `tipo_valor=NULL`. No afecta funcionamiento. A evaluar antes del dashboard OPS
  si se usa para render de inputs. Ver `Pendiente_pre_produccion.md` 1.4.

---

## 9. Próximos pasos sugeridos (no parte de 7A)

Con los pendientes pre-OPS resueltos, los caminos disponibles (a decidir por
Franco, no comprometidos en esta etapa):

- **Entorno TEST:** replicar DEV en proyecto Supabase separado.
- **Entorno OPS:** operación interna real (Vicky, Franco, Rodrigo, Jenny), sin
  consumidores externos automáticos.
- **Dashboard operativo manual:** UI de lectura/carga para el equipo.
- **Poblar `tipo_valor`** si el dashboard lo requiere.

No avanzar a TEST/OPS/PROD, MercadoPago real, bot o frontend público sin
decisión explícita.

---

_Cierre formal de Etapa 7A — 2026-05-28._
