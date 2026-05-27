# 6D_CIERRE.md — Cierre formal de Etapa 6D

**Etapa:** 6D — Hardening pre-producción
**Fecha de apertura:** 2026-05-26 (post-cierre de 6C)
**Fecha de cierre:** 2026-05-27
**Estado:** ✅ CERRADA
**Documento canónico de referencia:** este archivo.

---

## 1. Resumen ejecutivo

Etapa 6D consistió en consolidar el backend Supabase DEV (definido en 6B v1.7.1 y operado por workflows 6C) antes de habilitar entorno TEST o consumidores reales. La etapa se ejecutó en **3 frentes de cierre**:

- **Frente 1 — Hardening estructural (H1-H6-bis):** extracts defensivos en 5 funciones write críticas, fix de rango en `vista_ocupacion`, fix cosmético de concatenación nombre+apellido en 3 vistas.
- **Frente 2 — Validación de concurrencia (H7):** 6 tests de concurrencia real con `pg_sleep` validando la invariante de locks v1.5 bajo paralelismo real, sin modificar SQL.
- **Frente 3 — Cierre documental (H8):**
  - **H8 Frente A:** bump documental del schema canónico `6B_SCHEMA_SQL.md` de v1.7.1 a v1.7.2, reflejando el estado real de DEV post-hardening.
  - **H8 Frente B:** actualización de archivos satélite (`ESTADO_ACTUAL_VITA_DELTA.md`, `Pendiente_pre_produccion.md`, `DECISIONES_NO_REABRIR.md`, `HARDENING_PRE_PRODUCCION_EJECUCION.md`) + creación de este documento.

**Schema canónico vigente al cierre: `6B_SCHEMA_SQL.md v1.7.2`.** Backup v1.7.1 archivado con banner explícito en `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md`.

La etapa no agregó funcionalidad nueva al negocio. Es **consolidación pre-TEST**: cerrar deudas técnicas conocidas, validar empíricamente decisiones arquitecturales clave (locks, idempotencia, concurrencia) y dejar los cuerpos SQL afectados del documento canónico alineados con los snapshots reales de DEV antes de complicar el sistema con nuevos consumidores reales (webhook MercadoPago, bot, frontend).

---

## 2. Alcance ejecutado

### 2.1 Bloques estructurales (Frente 1: H1-H6-bis)

| Bloque | Objeto | Tipo | Tests | Cierre |
|---|---|---|---|---|
| H1 | Decisiones previas (patrón canónico, TRIM agresivo) | metodológico | n/a | 2026-05-26 |
| H2 | `registrar_pago` | extract defensivo | 15/15 | 2026-05-26 |
| H3 | `confirmar_reserva` | extract defensivo | 11/11 | 2026-05-26 |
| H4 | `crear_prereserva` | extract defensivo | 31/31 | 2026-05-26 |
| H4-bis | `cancelar_prereserva` | extract defensivo | 9/9 | 2026-05-26 |
| H4-ter | `crear_bloqueo` | extract defensivo | 17/17 | 2026-05-26 |
| H5 | `vista_ocupacion` | fix de rango 25→24 meses | 7/7 | 2026-05-26 |
| H6 | `vista_calendario` + `vista_limpieza_semana` | fix cosmético TRIM | 7/7 | 2026-05-26 |
| H6-bis | `vista_prereservas_activas` | fix cosmético TRIM | 5/5 | 2026-05-26 |

**Subtotal Frente 1:** 9 bloques, **101 tests de hardening estructural** con `ok=true`.

### 2.2 Bloque de concurrencia (Frente 2: H7)

| Test | Funciones | Tipo | Resultado |
|---|---|---|---|
| C-1 | `crear_prereserva` + `crear_bloqueo total` | Principal | ✅ |
| C-2 | `cancelar_prereserva` + `crear_bloqueo total` | Principal | ✅ |
| C-5 | `confirmar_reserva` + `cancelar_prereserva` | Regresión legacy v1.5 | ✅ |
| C-3 | `confirmar_reserva` + `crear_bloqueo específico` | Principal | ✅ |
| C-4 | Doble `confirmar_reserva` | Principal | ✅ |
| C-6 | Doble `crear_prereserva` + `idempotency_key` | Legacy idempotencia | ✅ |

**Subtotal Frente 2:** 6/6 tests aprobados, ejecutados el 2026-05-27.

### 2.3 Bloque documental (Frente 3: H8)

| Sub-frente | Objeto | Estado |
|---|---|---|
| H8 Frente A | Bump `6B_SCHEMA_SQL.md` v1.7.1 → v1.7.2 | ✅ Cerrado 2026-05-27 |
| H8 Frente A | Backup histórico `6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md` con banner | ✅ Cerrado 2026-05-27 |
| H8 Frente B | Actualización `ESTADO_ACTUAL_VITA_DELTA.md` | ✅ Cerrado |
| H8 Frente B | Actualización `Pendiente_pre_produccion.md` | ✅ Cerrado |
| H8 Frente B | Actualización `DECISIONES_NO_REABRIR.md` | ✅ Cerrado |
| H8 Frente B | Actualización `HARDENING_PRE_PRODUCCION_EJECUCION.md` | ✅ Cerrado |
| H8 Frente B | Creación de `6D_CIERRE.md` | ⏳ Este documento |

### 2.4 Totales de la etapa

- **9 bloques estructurales** cerrados (H1-H6-bis).
- **101 tests de hardening estructural** con `ok=true`.
- **6/6 tests de concurrencia** aprobados (H7).
- **0 deadlocks** `40P01`.
- **0 races** observados.
- **0 doble booking** detectado.
- **0 residuos post-cleanup**: conteos finales idénticos a baseline pre-H7.
- **Baseline final restaurado**: pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, log_cambios=11.
- **1 bump documental** del schema canónico ejecutado (H8 Frente A).
- **4 archivos satélite** actualizados (H8 Frente B).

---

## 3. Convenciones consolidadas durante la etapa

### 3.1 Patrón canónico de extract defensivo

```sql
v_campo := NULLIF(TRIM(payload->>'campo'), '')::TIPO;
```

Aplicado en los extracts de payload de las 5 funciones write críticas: `registrar_pago`, `confirmar_reserva`, `crear_prereserva`, `cancelar_prereserva`, `crear_bloqueo`. Cubre vacíos y whitespace antes del cast.

**Excepción documentada inline:** `v_huesped_payload` en `crear_prereserva` usa `payload->'huesped'` (operador JSONB anidado, no derivado de `payload->>'...'`); su normalización vive en `upsert_huesped()` y no aplica el patrón canónico.

**Caso especial `crear_bloqueo`:** mantiene la semántica "NULL = bloqueo total" — `id_cabana: null`, `""` y `"   "` se interpretan como bloqueo total; un ID válido implica bloqueo específico.

Decisión consolidada: **D-HARD-01** (`DECISIONES_NO_REABRIR.md`).

### 3.2 TRIM agresivo en obligatorios

Whitespace puro (`"   "`) en campo obligatorio equivale a vacío equivale a NULL. La función rebota con `payload_invalido` en vez de aceptar el whitespace o intentar castearlo. Decisión consolidada: **D-HARD-02**.

### 3.3 Snapshot-first

Para todo bloque de hardening estructural o documental, capturar primero el cuerpo real con `pg_get_functiondef()` / `pg_get_viewdef()` / `information_schema.columns`, y diseñar el diff mínimo contra ese cuerpo, no contra el canónico previo. La fuente de verdad estructural es DEV, no el canónico v1.7.1 (lección **L-6D-01** consolidada en `Lecciones_Aprendidas.md`).

Patrón extendido en H8 Frente A: snapshot-first se aplicó también para verificar columnas destino cuando el extract aplica `NULLIF(TRIM(...))` (caso `ninos`, `canal_pago_esperado`).

### 3.4 Convención `source_event` para tests de concurrencia

`test_H7_C{N}_{ROL}` con `{ROL}` ∈ `{A, B, FIXTURE, FIXTURE_PR, FIXTURE_PAGO}`. Permite trazabilidad fina del test y su rol en la concurrencia, sin colisionar con `source_event` operativos reales. Decisión consolidada: **D-HARD-08**.

### 3.5 Forma persistida adoptada como canónica

PostgreSQL normaliza ciertas expresiones al persistir vistas y funciones (`TRIM(x)` → `TRIM(BOTH FROM x)`, `'1 month'::interval` → `'1 mon'::interval`, etc.). El bump v1.7.2 adoptó la **forma persistida** (`pg_get_viewdef()` / `pg_get_functiondef()`) en el canónico para garantizar fidelidad textual con el cuerpo persistido por DEV en los objetos afectados. Lección **L-6D-02** en `Lecciones_Aprendidas.md`.

### 3.6 Cifras evitadas en redacción canónica

Las cifras de conteo de asignaciones de extract (52, 56, 58, 60) **no se usan** en redacción canónica de Etapa 6D. Razón: durante H8 Frente A se identificó que distintas métricas (asignaciones de extract manuales vs ocurrencias textuales con/sin TRIM) producen cifras distintas, y la cifra histórica "56" no coincide con ninguna métrica observable empíricamente. Se adopta redacción cualitativa ("asignaciones de extract") en `6B_SCHEMA_SQL.md v1.7.2`, `DECISIONES_NO_REABRIR.md`, `Pendiente_pre_produccion.md` y `ESTADO_ACTUAL_VITA_DELTA.md`.

---

## 4. Patrón de trabajo establecido

### 4.1 Para bloques de hardening estructural (H2-H6-bis)

1. **Snapshot-first** del objeto a modificar.
2. **Diff mínimo propuesto en chat** con aprobación explícita.
3. **Ejecutar SQL.** Para funciones: `CREATE OR REPLACE FUNCTION`. Para vistas: `CREATE OR REPLACE VIEW` cuando no cambian columnas; verificar dependencias antes. No usar `DROP / CASCADE` salvo decisión explícita (ver L-6D-05).
4. **Tests funcionales inmediatos** sobre el objeto modificado.
5. **Verificación cruzada** cuando aplica (W1 para disponibilidad, conteos pre/post para no-regresión).
6. **Bitácora del bloque** con tests, decisiones, observaciones.

### 4.2 Para tests de concurrencia (H7)

1. **Plan de tests aprobado primero** (6 tests con frenos especiales por regresión).
2. **Fixtures bien aislados** con `source_event` único.
3. **Mecánica de paralelismo** con `pg_sleep` y dos tabs/sesiones (decisión D-HARD-09).
4. **Freno duro ante cualquier `40P01`** (decisión D-HARD-11). Frenos especiales por orden: `40P01` en C-5 bloquea C-3/C-4/C-6; `40P01` en C-3 bloquea C-4/C-6.
5. **Cleanup FK-seguro** al final de cada test (logs → bloqueos/pagos → pre_reservas/reservas → huésped huérfano).
6. **Verificación de baseline restaurada** después de cada test.

### 4.3 Para cierre documental (H8)

1. **Frente A primero, Frente B después.** Frente A consolida el canónico antes de actualizar satélites.
2. **Snapshot read-only contra DEV** vía `pg_get_functiondef()` / `pg_get_viewdef()` / `information_schema.columns`.
3. **Edición in-place quirúrgica** del canónico (ningún schema paralelo).
4. **Backup histórico con banner** explícito de archivo no canónico.
5. **Working note auxiliar** (`H8_SNAPSHOTS_SCHEMA_v1.7.2_WORKING_NOTES.md`) durante la sesión para registrar snapshots y veredictos. Se archiva al cerrar.
6. **Búsqueda final con `grep`** antes de cerrar (`56`, `v1.7.1`, `H7-H8 pendientes`, `H8 pendiente`, `En curso`).
7. **Aprobación explícita** del usuario antes de cada cambio significativo.

---

## 5. Gotchas y lecciones aprendidas — Resumen ejecutivo

Las decisiones D-HARD-01 a D-HARD-11 están consolidadas en `DECISIONES_NO_REABRIR.md`. Las lecciones principales del hardening estructural (L-6D-01 a L-6D-05) están consolidadas en `Lecciones_Aprendidas.md`. Lecciones de H7 (concurrencia) y H8 (cierre documental) están registradas en `HARDENING_PRE_PRODUCCION_EJECUCION.md` y en la working note auxiliar de H8 Frente A.

Síntesis ejecutiva (≤ 10 lecciones clave):

| # | Tema | Síntesis | Referencia |
|---|---|---|---|
| 1 | Schema canónico ≠ DEV real | El canónico previo v1.7.1 tenía divergencias menores respecto al cuerpo real en DEV (logs, retornos, tipo de variables). Para todo cambio futuro, `pg_get_functiondef()` es la fuente, no el canónico. | L-6D-01 |
| 2 | Forma persistida de PostgreSQL | PostgreSQL normaliza expresiones al persistir vistas y funciones. El canónico v1.7.2 adopta la forma persistida para garantizar fidelidad textual con el cuerpo persistido por DEV en los objetos afectados. | L-6D-02 |
| 3 | Patrón defensivo `NULLIF(TRIM(...), '')` | Estabiliza errores observables ante strings vacíos y whitespace en payloads. Aplicado en las 5 funciones write críticas. No cubre tipos inválidos no vacíos (pendiente separado). | L-6D-03 / D-HARD-01 / D-HARD-02 |
| 4 | Diseño no destructivo de tests en funciones write | Tests con operaciones tempranas en tablas requieren cleanup FK-seguro y aislamiento por `source_event`. | L-6D-04 |
| 5 | Dependencias antes de `CREATE OR REPLACE VIEW` | Vistas con dependencias (otras vistas, queries cacheadas) requieren validación previa. NO usar `DROP CASCADE` ciego. | L-6D-05 |
| 6 | Invariante de locks v1.5 validada bajo concurrencia real | 6/6 tests aprobados con `pg_sleep` y dos sesiones paralelas. Cero deadlocks, cero races, cero doble booking. | H7 / D-HARD-09 / D-HARD-11 |
| 7 | Cobertura empírica parcial de idempotencia es aceptable | Solo la rama `post_lock` del detector de idempotencia de `crear_prereserva` fue observada empíricamente en C-6. Las ramas `pre_lock` y `unique_violation` quedan como cobertura opcional pre-PROD. | D-HARD-10 |
| 8 | Snapshot-first extendido a columnas destino | Cuando el extract aplica `NULLIF(TRIM(...))` y el campo desaparece de la validación manual, hay que verificar también la columna destino. Aprendizaje del Frente A de H8 (casos `ninos`, `canal_pago_esperado`). | H8 Frente A — working note auxiliar |
| 9 | Cifras numéricas en redacción canónica | Distintas métricas producen cifras distintas (asignaciones manuales vs ocurrencias textuales). Adoptar redacción cualitativa evita inconsistencias entre documentos. | H8 Frente A — working note auxiliar |
| 10 | Defensa en profundidad: `nv()` en n8n permanece | Aunque el hardening SQL cubre el caso, los `nv()` defensivos en Build Payload de n8n se mantienen como defensa en profundidad. NO remover. | D-HARD-05 / L-6C-07 |

---

## 6. Hallazgos pendientes generados durante 6D

### 6.1 Hallazgos gestionados como pendientes livianos para TEST/PROD

| # | Hallazgo | Documentado en |
|---|---|---|
| 1 | Alineación de tipo `ninos` entre función (BOOLEAN) y columnas (TEXT) | `Pendiente_pre_produccion.md` sección 1.2 + changelog v1.7.2 + working note H8 |
| 2 | Contrato de `canal_pago_esperado`: extract aplica patrón canónico pero columna sigue `TEXT NOT NULL` | `Pendiente_pre_produccion.md` sección 1.3 + changelog v1.7.2 + working note H8 |

Ninguno es bloqueante. Conviene resolverlos antes de TEST/PROD para evitar inconsistencias de contrato con consumidores reales.

### 6.2 Hallazgos fuera de alcance del hardening por strings/whitespace

| # | Hallazgo | Estado |
|---|---|---|
| 1 | Validación de tipos inválidos no vacíos (ej. `id_cabana="abc"`, `fecha_in="no-es-fecha"`) | Pendiente histórico, no cubierto por D-HARD-01/02. Sigue rompiendo con error crudo de PostgreSQL. |

### 6.3 Cobertura empírica parcial

| # | Hallazgo | Estado |
|---|---|---|
| 1 | Ramas `pre_lock` y `unique_violation` del detector de idempotencia de `crear_prereserva` no fueron gatilladas empíricamente | Cobertura opcional pre-PROD. D-HARD-10. |

---

## 7. Estado de DEV al cierre de 6D

**Baseline post-H7, cero side effects del hardening completo:**

| Recurso | Conteo | Detalle |
|---|---|---|
| Pre-reservas | 2 | Estados terminales (`convertida`, `cancelada_por_cliente`) |
| Pagos | 1 | `confirmado` |
| Reservas | 1 | `confirmada`, cabaña 17 (Bamboo), 10-13 jul 2026 |
| Huéspedes | 2 | id 34 ("Juan Pérez Test") y id 35 ("Test W5 Cliente") |
| Bloqueos | 2 | activos (id 6, id 7) |
| Logs | 11 | en `log_cambios` |

**Conteos idénticos al baseline pre-H7** — confirma cero side effects persistentes post-cleanup de la sesión completa de concurrencia (6 tests con fixtures multipaso, todos limpiados al cierre de cada test).

---

## 8. Entregables generados durante 6D

### 8.1 Schema canónico

- `6B_SCHEMA_SQL.md` bumped v1.7.1 → v1.7.2 (Frente A de H8).
- `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md` con banner histórico.

### 8.2 Bitácora detallada

- `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` con bloques H1-H7 documentados y headers consolidados como "H1-H7 cerrados · H8 en curso".

### 8.3 Working note auxiliar (auditoría, no canónico)

- `H8_SNAPSHOTS_SCHEMA_v1.7.2_WORKING_NOTES.md` — bitácora del Frente A de H8 (snapshots, veredictos, decisiones, divergencias identificadas). **No es fuente canónica.** Se archiva como entregable auxiliar de auditoría para trazabilidad histórica del bump v1.7.2.

### 8.4 Archivos satélite actualizados (Frente B de H8)

- `ESTADO_ACTUAL_VITA_DELTA.md` — schema vigente marcado como v1.7.2, redacción sin cifras numéricas obsoletas, lista de pendientes renumerada (1-6), bump v1.7.2 movido a items cerrados, oración obsoleta sobre "diferida a H8" corregida, bloques duplicados de Etapa 6D consolidados.
- `Pendiente_pre_produccion.md` — sustitución de cifra "56" por redacción cualitativa, nuevos items 1.2 (`ninos`) y 1.3 (`canal_pago_esperado`), header consolidado.
- `DECISIONES_NO_REABRIR.md` — D-HARD-01 con redacción sin cifra.
- `HARDENING_PRE_PRODUCCION_EJECUCION.md` — header global y header del bloque H7 consolidados a estado cerrado.

### 8.5 Decisiones consolidadas

Decisiones **D-HARD-01 a D-HARD-11** consolidadas en `DECISIONES_NO_REABRIR.md`; lecciones principales referenciadas y/o consolidadas en documentos operativos (`Lecciones_Aprendidas.md`, `HARDENING_PRE_PRODUCCION_EJECUCION.md`, working note H8 auxiliar).

---

## 9. Decisiones cerradas durante 6D — NO REABRIR

Las siguientes decisiones quedaron consolidadas en `DECISIONES_NO_REABRIR.md` y no se reabren:

### Hardening estructural (H1-H6-bis, sesión 2026-05-26)

1. **D-HARD-01** — Patrón canónico de extract defensivo `NULLIF(TRIM(payload->>'campo'), '')::TIPO` aplicado en las 5 funciones write críticas.
2. **D-HARD-02** — TRIM agresivo en obligatorios: whitespace puro = vacío = NULL → `payload_invalido`.
3. **D-HARD-03** — Cambio observable consistente: whitespace en campo obligatorio devuelve `payload_invalido`, no errores específicos del dominio.
4. **D-HARD-04** — `id_cabana="   "` en `crear_bloqueo` se interpreta como bloqueo total (consistencia con `null`).
5. **D-HARD-05** — `nv()` en n8n se mantiene como defensa en profundidad. NO remover.
6. **D-HARD-06** — UPDATE de `huespedes` para normalizar `apellido=""` NO ejecutado. Fix cosmético en vistas con TRIM cubre el problema observable sin modificar datos persistidos.

### Tests de concurrencia (H7, sesión 2026-05-27)

7. **D-HARD-07** — Nomenclatura de tests de concurrencia H7 consolidada.
8. **D-HARD-08** — Convención `source_event` para tests de concurrencia: `test_H7_C{N}_{ROL}`.
9. **D-HARD-09** — Mecánica de paralelismo para tests con `pg_sleep` (dos sesiones, timing controlado).
10. **D-HARD-10** — Cobertura empírica parcial de ramas de idempotencia es aceptable; ramas `pre_lock` y `unique_violation` quedan como cobertura opcional pre-PROD.
11. **D-HARD-11** — Freno duro ante `40P01` en cualquier test de concurrencia.

### Cierre documental (H8, sesión 2026-05-27 en adelante)

- **Snapshot-first como método** para todo bump documental.
- **Redacción sin cifras numéricas** en documentos canónicos (asignaciones de extract, ocurrencias textuales).
- **No schema paralelo:** el canónico actualizado pasa a reflejar DEV real; backup histórico no canónico.
- **Frente A primero, Frente B después** dentro de H8.

---

## 10. Próxima etapa — Por decidir

Con 6D cerrado, las opciones inmediatas son:

### 10.1 Opción B — Entorno TEST (RECOMENDADA)

Replicar DEV en un proyecto Supabase separado para integrar consumidores reales sin riesgo a datos reales de DEV.

**Ventaja:** habilita pruebas con webhook MercadoPago, frontend, bot conversacional, etc., sin contaminar el ambiente de desarrollo activo. Cierra el último item bloqueante antes de productizar el sistema.
**Costo:** sesión media (2-3 horas) — duplicar schema, seeds operativos, credenciales, ajustar workflows n8n para parametrizar ambiente.

**Recomendación explícita:** ejecutar Opción B antes de conectar consumidores reales (C, D). Los pendientes livianos de H8 (`ninos`, `canal_pago_esperado`) conviene resolverlos durante el setup de TEST.

### 10.2 Opción C — Webhook MercadoPago

Workflow operativo real que invoca W3 (`registrar_pago`) tras webhook de MP, con deduplicación por `payment_id`.

**Ventaja:** primer flujo productivo end-to-end.
**Costo:** sesión larga (3-4 horas). Diseño del webhook, deduplicación, manejo de estados, integración con W4 si el monto matchea.

**Posición:** posterior a B, o paralela solo si se asume riesgo operativo conocido (integración productiva contra DEV).

### 10.3 Opción D — Bot conversacional (Etapa 4B implementación)

Implementar el bot diseñado en Etapa 4B usando Claude API + Meta API.

**Ventaja:** habilita el canal principal de consultas (Instagram + WhatsApp).
**Costo:** sesión larga. Depende de definiciones de Etapa 4B y de tener Meta API conectada.

**Posición:** posterior a B, o paralela solo si se asume riesgo operativo conocido.

### 10.4 Recomendación documentada

**Opción B primero.** Cerrar el último item bloqueante (entorno TEST) antes de conectar consumidores reales. Las opciones C y D pueden ejecutarse contra TEST con seguridad operativa, no contra DEV.

---

## 11. Resumen del cierre

**Etapa 6D cerrada formalmente al 2026-05-27.**

- ✅ 9 bloques estructurales cerrados (H1, H2, H3, H4, H4-bis, H4-ter, H5, H6, H6-bis).
- ✅ 101 tests de hardening estructural con `ok=true`.
- ✅ 6/6 tests de concurrencia aprobados (H7).
- ✅ 0 deadlocks, 0 races, 0 doble booking, 0 residuos post-cleanup.
- ✅ Baseline final restaurado.
- ✅ Bump documental v1.7.1 → v1.7.2 ejecutado (H8 Frente A).
- ✅ 4 archivos satélite actualizados (H8 Frente B).
- ✅ Backup histórico de v1.7.1 archivado con banner.
- ✅ 11 decisiones D-HARD-NN consolidadas en `DECISIONES_NO_REABRIR.md`.
- ✅ Lecciones principales referenciadas y/o consolidadas en documentos operativos.
- ✅ 2 hallazgos no resueltos gestionados como pendientes livianos para TEST/PROD.
- ✅ Schema canónico vigente: `6B_SCHEMA_SQL.md v1.7.2`.

La etapa demostró que la robustez estructural del backend (locks v1.5, idempotencia de `crear_prereserva`, invariante de orden de adquisición) se mantiene bajo concurrencia real, y que el schema canónico v1.7.2 refleja el estado real de DEV post-hardening en los objetos afectados. Está listo para que en etapas futuras se levante entorno TEST y se incorporen consumidores reales (webhook MP, bot, frontend) sin reabrir decisiones arquitecturales.

---

*Documento de cierre formal aprobado el 2026-05-27.*
*Próxima sesión arranca con decisión de etapa (B / C / D), recomendado B.*
