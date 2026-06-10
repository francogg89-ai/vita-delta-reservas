# 9D_CIERRE.md — Cierre parcial Etapa 9D / Carril B

**Etapa:** 9D — Activación operativa por rango (segunda sub-etapa de **schema** del Carril B / contabilidad operativa interna).
**Estado:** ✅ **Cerrada y verificada en TEST.** Cierre **parcial** de Carril B (9E–9G siguen pendientes).
**Entorno de validación:** TEST (`vita-delta-test`) — IDs de cabaña 1–5.
**Entorno de operación:** — (9D **no** se promovió a OPS; promoción diferida a la operación coordinada única de todo el Carril B).
**Fecha de cierre:** 2026-06-10.
**Base conceptual:** `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md` (v0.8) §3 (tres ejes), §2.3 (pool derivado), §177-192 (matriz); decisión marco **D-9C-04 / P4** (activación por rango `[)`, política mensual MVP, pro-rata diferido).
**Depende de:** 9C (cerrada en TEST) — cuelga del catálogo enriquecido de cabañas.
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` — **NO modificado** (sin bump).
**Autores:** Franco (titular, ejecutor de todos los writes) + Claude (arquitecto).
**Decisiones registradas:** D-9D-01 a D-9D-10. **Lecciones:** L-9D-01.

---

## 1. Resumen ejecutivo

9D materializó el **eje de activación operativa**: la capacidad de registrar, por rango `[)`, qué cabañas están "puestas a disposición del pool económico" en cada período. Es uno de los **tres ejes independientes** del conceptual (bloqueo ≠ activación ≠ titularidad), y el primero que **no derivaba de los otros**. Es también **la primera sub-etapa de Carril B donde aparece legítimamente un `daterange`/`EXCLUDE`** — en 9C se había verificado su ausencia; tras 9D el conteo global de `EXCLUDE` pasó de 2 a 3.

El modelo es de **presencia de rango = "en el pool"; gap = "fuera del pool"**: no hay booleano `activa` (sería redundante); desactivar es dejar un hueco sin rango, reactivar es insertar un nuevo rango. La no-doble-activación está garantizada estructuralmente por un `EXCLUDE USING gist` por cabaña. La **política mensual** ("cubre el mes completo") **no se horneó en 9D**: 9D guarda rangos flexibles y esa regla se aplicará en 9E (matriz derivada).

Se siguió la metodología estricta del proyecto (diagnóstico read-only → diseño aprobado bloque por bloque → ejecución en TEST por Franco → verificación → cierre). El gate de entorno fue **programático y duro** desde el inicio gracias al marcador `ambiente='test'` sembrado en 9C (sin bootstrap). La garantía estructural se **probó en vivo**: un intento de solapamiento fue rechazado con `23P01`.

---

## 2. Qué se construyó (objetos de 9D en TEST)

- **Tabla `activaciones_operativas`** — un renglón = "la cabaña X está en el pool durante `[fecha_desde, fecha_hasta)`":
  - `id_activacion BIGSERIAL PK`
  - `id_cabana BIGINT NOT NULL` → FK `cabanas(id_cabana)` `ON DELETE RESTRICT`
  - `fecha_desde DATE NOT NULL`
  - `fecha_hasta DATE` (**nullable = activación abierta/indefinida**, "activa hasta nuevo aviso")
  - `comentario TEXT`, `creado_por TEXT`, `created_at TIMESTAMPTZ DEFAULT NOW()`
  - `CONSTRAINT chk_activaciones_fechas CHECK (fecha_hasta IS NULL OR fecha_hasta > fecha_desde)`
  - `CONSTRAINT exc_activaciones_no_overlap EXCLUDE USING gist (id_cabana WITH =, daterange(fecha_desde, fecha_hasta, '[)') WITH &&)`
  - `CREATE INDEX idx_activaciones_cabana ON activaciones_operativas(id_cabana)`
- **Sin `source_event`** (carga SQL controlada, no workflow) y **sin formulario** (MVP).

---

## 3. Composición oficial del pool inicial (D-9D-10)

Fechas **reales** (aplican igual a OPS; en TEST se replicaron para realismo). La contabilidad formal arranca el **2026-07-01**.

| Cabaña | fecha_desde | fecha_hasta | Estado |
|---|---|---|---|
| Bamboo | 2026-07-01 | NULL (abierta) | En el pool desde el inicio |
| Madre Selva | 2026-07-01 | NULL (abierta) | En el pool desde el inicio |
| Arrebol | 2026-07-01 | NULL (abierta) | En el pool desde el inicio |
| Tokio | 2026-07-01 | NULL (abierta) | En el pool desde el inicio |
| **Guatemala** | **2026-11-01** | NULL (abierta) | **Desactivada jul–oct 2026 inclusive; en el pool desde noviembre** |

**Verificado con datos (modelo, no política 9E):** participación por mes vía `daterange ... @> mes_completo`:
- **Julio 2026:** 4 cabañas cubren el mes (Guatemala afuera). ✔️
- **Octubre 2026:** 4 cabañas (Guatemala afuera). ✔️
- **Noviembre 2026:** 5 cabañas (Guatemala adentro). ✔️

> La fecha `2026-11-01` es la correcta bajo el modelo `[)` + "cubre el mes completo": el rango `[2026-11-01, NULL)` cubre noviembre `[2026-11-01, 2026-12-01)` y siguientes, y no cubre octubre `[2026-10-01, 2026-11-01)`.

---

## 4. Bloques ejecutados (bitácora)

| Bloque | Contenido | Resultado |
|---|---|---|
| **A** | Gate read-only (ambiente `test`, cabañas 1–5, `btree_gist` presente, ausencia de objetos 9D, base 9C intacta, snapshot `activa`). | Verde. |
| **B** | Estructura: `CREATE TABLE activaciones_operativas` + CHECK + EXCLUDE + índice. | OK (10/10; EXCLUDE global 2→3; tabla vacía). |
| **C** | Carga inicial oficial (D-9D-10) + smokes del EXCLUDE. | OK (5 activaciones; pool jul=4/nov=5). Smoke solapamiento → **`23P01`** (rechazado, correcto). |
| **D** | Verificación consolidada read-only (estructura + carga + aislamiento + ambiente). | Verde (todos OK). |
| **E** | Este documento de cierre parcial. | — |

**Nota sobre los smokes (C.3):** el smoke de solapamiento (insertar un rango que pisa la activación abierta de Bamboo) fue **rechazado con `23P01` (`exclusion_violation`)** — la garantía estructural funciona. El smoke de adyacencia tuvo un error de tipeo en la primera corrida (coma de más, `42601`, sin efecto sobre los datos); la versión corregida confirma que `[)` permite rangos pegados. Ambos smokes revierten (`ROLLBACK`); el estado final es las 5 filas del seed.

---

## 5. Decisiones registradas (D-9D-01 .. D-9D-10)

- **D-9D-01** — Tabla independiente `activaciones_operativas` (eje propio; **no deriva** de `bloqueos` ni de `cabanas.activa`; se mantiene la reversión conceptual de derivar activación del bloqueo `uso_propio`).
- **D-9D-02** — Rango con `fecha_desde`/`fecha_hasta DATE` + CHECK (consistente con `bloqueos`); **sin columna `daterange` almacenada** (el `daterange` vive en la expresión del EXCLUDE).
- **D-9D-03** — `fecha_hasta NULL` = activación **abierta/indefinida**. Desactivar = dejar hueco sin rango activo; reactivar = nuevo rango desde la fecha correspondiente.
- **D-9D-04** — `EXCLUDE USING gist (id_cabana WITH =, daterange(fecha_desde, fecha_hasta, '[)') WITH &&)` — **no-solapamiento por cabaña**, sin `WHERE` (no hay soft-delete). Primer EXCLUDE de Carril B; usa `btree_gist`. Adyacencia (`[)`) permitida; solapamiento prohibido.
- **D-9D-05** — FK `id_cabana → cabanas(id_cabana)` `ON DELETE RESTRICT` (paridad con `bloqueos`/`reservas`).
- **D-9D-06** — La **política mensual** ("cubre el mes completo") se aplica en **9E**, no en 9D. 9D guarda rangos flexibles; no bucketiza por mes.
- **D-9D-07** — Auditoría con `creado_por` + `comentario` + `created_at`; **sin `source_event`** (carga SQL controlada, no acción de workflow).
- **D-9D-08** — Carga por **SQL controlado, sin formulario** en el MVP.
- **D-9D-09** — **Estructura primero (Bloque B); carga inicial en bloque separado (Bloque C)** con decisión explícita. El diseño no fuerza ninguna cabaña como activa.
- **D-9D-10** — **Composición oficial del pool inicial:** Bamboo, Madre Selva, Arrebol, Tokio activas desde `2026-07-01` (`fecha_hasta NULL`); **Guatemala desactivada operativamente hasta octubre 2026 inclusive → activa desde `2026-11-01`** (`fecha_hasta NULL`). Fechas reales (aplican a OPS; replicadas en TEST).

---

## 6. DDL aplicado (registro — fuente hasta el bump del canónico)

```sql
-- Estructura (Bloque B)
CREATE TABLE activaciones_operativas (
  id_activacion   BIGSERIAL PRIMARY KEY,
  id_cabana       BIGINT NOT NULL,
  fecha_desde     DATE NOT NULL,
  fecha_hasta     DATE,                 -- NULL = activacion abierta/indefinida
  comentario      TEXT,
  creado_por      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_activaciones_cabana
    FOREIGN KEY (id_cabana) REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  CONSTRAINT chk_activaciones_fechas
    CHECK (fecha_hasta IS NULL OR fecha_hasta > fecha_desde),
  CONSTRAINT exc_activaciones_no_overlap
    EXCLUDE USING gist (
      id_cabana WITH =,
      daterange(fecha_desde, fecha_hasta, '[)') WITH &&
    )
);
CREATE INDEX idx_activaciones_cabana ON activaciones_operativas(id_cabana);

-- Carga inicial oficial (Bloque C, D-9D-10) — idempotente
INSERT INTO activaciones_operativas (id_cabana, fecha_desde, fecha_hasta, creado_por, comentario)
SELECT c.id_cabana, v.desde, NULL, 'seed_9d', v.coment
FROM (VALUES
    ('Bamboo',      DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Madre Selva', DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Arrebol',     DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Tokio',       DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Guatemala',   DATE '2026-11-01', 'Desactivada jul-oct 2026 inclusive; activa desde nov (D-9D-10)')
) AS v(cab_nombre, desde, coment)
JOIN cabanas c ON c.nombre = v.cab_nombre
WHERE NOT EXISTS (SELECT 1 FROM activaciones_operativas a WHERE a.id_cabana = c.id_cabana);
```

---

## 7. Verificación (estado final probado en TEST)

- **Estructura:** tabla creada; `fecha_hasta` nullable; `fecha_desde` NOT NULL; FK RESTRICT; CHECK; **EXCLUDE no-solapamiento**; índice por cabaña.
- **Carga:** 5 activaciones, **todas abiertas** (`fecha_hasta NULL`); 4 desde `2026-07-01`; Guatemala desde `2026-11-01`.
- **Modelo de pool por mes:** julio = 4, octubre = 4, noviembre = 5 (vía `daterange @> mes`).
- **Garantía estructural probada en vivo:** solapamiento rechazado con `23P01`; adyacencia `[)` permitida.
- **Aislamiento:** `EXCLUDE` global = 3, en `activaciones_operativas` = 1; `cabanas.activa` sin cambios (md5 `facd2112861454dd5699484c22ba265d`); base 9C intacta (`zonas`, `cabana_zona`, `resolver_beneficiario`); ambiente `test`.

---

## 8. Lo que NO se hizo en 9D (alcance respetado)

- **No se tocó OPS.** 9D vive solo en TEST.
- **No se bumpeó el canónico.** `6B_SCHEMA_SQL.md v1.7.3` sigue vigente.
- **No se tocó** `cabanas.activa`, `bloqueos`, ni objetos de 9C.
- **No se diseñó ni implementó:** matriz derivada (9E); regla "cubre el mes" como lógica formal (va en 9E); pool persistido (se deriva); gasto rediseñado (9F); cascada read-only (9G); pro-rata diario / period atómico fino (latente); columna booleana `activa` en la tabla (redundante); formulario/workflow de activación; derivar activación de bloqueo; fiscal/AFIP/ARCA/IVA; saldos/liquidaciones persistidas.
- **No se usó `source_event`** (carga manual, no workflow).

---

## 9. Lecciones (para `Lecciones_Aprendidas.md`)

- **L-9D-01** — Modelo de estado por rango con presencia/ausencia: para "activo/inactivo por período" sin booleano, usar rangos `[)` + `EXCLUDE USING gist` (no-solapamiento por entidad). La adyacencia `[)` permite rangos pegados (back-to-back) sin gaps obligatorios; el solapamiento se rechaza con `23P01`. "Desactivar" = dejar un hueco entre rangos (no marcar inactivo). Verificar la participación mensual con `daterange(desde,hasta,'[)') @> daterange(mes_inicio, mes_siguiente,'[)')`.

---

## 10. Pendiente para la promoción coordinada (NO ahora)

Todo Carril B se promueve a OPS en **una sola operación**, con aprobación explícita y **bump único** del canónico. Lo que 9D deja anotado:

- **Recrear en OPS:** la tabla `activaciones_operativas` con su CHECK, EXCLUDE e índice; y la **carga inicial real** del pool — **con la misma desactivación de Guatemala (jul–oct 2026 inclusive; activa desde `2026-11-01`)**. Las fechas de D-9D-10 son reales, no de laboratorio.
- **Exposición Data API:** `activaciones_operativas` se creó con RLS deshabilitado (acceso por ownership vía n8n-as-`postgres`); aplicar el mismo hardening que 7B/7E sobre los objetos existentes (o confirmar "Automatically expose new tables" OFF). Junto al pendiente análogo de 9C (`zonas`/`cabana_zona`).
- **Marcador de ambiente:** sembrar `('ambiente','ops')` en OPS como parte de la operación coordinada (hoy solo existe `('ambiente','test')` en TEST).

---

## 11. Estado tras 9D y forward pointers

- **Carril B / schema:** 9C y **9D cerradas y verificadas en TEST**. Quedan construidos los insumos estáticos (9C) y la activación por período (9D) que alimentan la matriz.
- **Inmediato siguiente:** **9E — matriz derivada read-only.** Lee los cuatro insumos: catálogo + valor relativo (9C) + titularidad vía `resolver_beneficiario` (9C) + **activación por período (9D)**. Acá aterriza la **política mensual** ("cubre el mes completo", D-9D-06/D-9C-04) y el **centavo residual** (D-9C-02). La matriz **se deriva, no se guarda** (conceptual §177).
- **Después:** **9F** (gasto rediseñado; pagador puede ser socio, D-9C-03) → **9G** (cascada read-only de 11 pasos).

> **Nota de proceso:** este cierre se redacta **antes** de actualizar los seis satélites (`ESTADO_ACTUAL_VITA_DELTA.md`, `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `Pendiente_pre_produccion.md`, `6B_SCHEMA_SQL.md`, `CLAUDE.md`). La propagación es el paso siguiente y se hace como conjunto, con Franco aportando los satélites actuales. Hasta entonces, este documento (junto con `9C_CIERRE.md`) es la fuente del contenido a propagar. El canónico **no** se bumpea en 9D.

---

**Fin de `9D_CIERRE.md` — 9D cerrada y verificada en TEST. Sin OPS, sin bump del canónico. Carril B continúa en 9E (matriz derivada).**
