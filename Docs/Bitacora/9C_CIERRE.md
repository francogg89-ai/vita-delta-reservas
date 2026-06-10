# 9C_CIERRE.md — Cierre parcial Etapa 9C / Carril B

**Etapa:** 9C — Catálogo enriquecido, zonas y punto único de resolución de titularidad (primera sub-etapa de **schema** del Carril B / contabilidad operativa interna).
**Estado:** ✅ **Cerrada y verificada en TEST.** Cierre **parcial** de Carril B (no cierra el carril; 9D–9G siguen pendientes).
**Entorno de validación:** TEST (`vita-delta-test`) — IDs de cabaña 1–5.
**Entorno de operación:** — (9C **no** se promovió a OPS; promoción diferida a la operación coordinada única de todo el Carril B).
**Fecha de cierre:** 2026-06-10.
**Documentos de diseño:** `ARQUITECTURA_ETAPA_9C_CATALOGO_ZONAS_TITULARIDAD.md` (v1.0, conceptual aprobado) + `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md` (v0.8, base).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` — **NO modificado** (sin bump; se actualizará con bump único en la promoción coordinada).
**Autores:** Franco (titular, ejecutor de todos los writes) + Claude (arquitecto).
**Decisiones registradas:** D-9C-14 a D-9C-21. **Lecciones:** L-9C-01 a L-9C-03.

---

## 1. Resumen ejecutivo

9C materializó los **insumos estáticos** que después consumirá la matriz dinámica de participación: el **catálogo de cabañas enriquecido** (valor relativo + beneficiario económico), el **catálogo de zonas** con su **pertenencia muchos-a-muchos**, y el **punto único de resolución de titularidad** (seam). Es la primera sub-etapa de schema del Carril B; convierte el conceptual aprobado de 9C en estructura real, sin avanzar sobre activación por rango (9D), matriz (9E), gasto rediseñado (9F) ni cascada (9G).

Se siguió la metodología estricta del proyecto: **diagnóstico read-only → diseño aprobado bloque por bloque → ejecución en TEST por Franco → verificación read-only → cierre parcial documentado**. Todos los writes fueron ejecutados por Franco; Claude generó diseño, DDL, verificaciones y rollback. Cada bloque corrió con su gate, su verificación y su rollback disponible.

Durante el diagnóstico (Bloque A) el gate **frenó correctamente**: el tercer socio seguía como el placeholder `Socio 3` del seed canónico de 6B, sin un socio `Remo`. Se resolvió como **prerequisito** (D-9C-21) renombrando el placeholder, se re-corrió el Bloque A en verde, y recién entonces se avanzó. La verificación consolidada final (Bloque F) confirmó estructura, datos, seam, **que `cabanas.activa` no cambió** (cross-check de fingerprint md5) y **ausencia total de artefactos de 9D**.

---

## 2. Qué se construyó (objetos de 9C en TEST)

- **`cabanas` enriquecida** — dos columnas nuevas, agregadas **nullable → backfill → NOT NULL**:
  - `valor_relativo NUMERIC(6,2)`, con `CHECK (valor_relativo > 0)`. Sin DEFAULT/generated/trigger (el `tipo` sugiere el valor solo en el seed; no lo impone).
  - `id_socio_beneficiario BIGINT NOT NULL`, FK a `socios(id_socio)` con `ON DELETE RESTRICT`.
- **`zonas`** — catálogo plano nombrado, sin jerarquía, **sin `activa`**, sin beneficiario ni bolsillo (intermediario de distribución). Seed MVP: `grandes`, `chicas`.
- **`cabana_zona`** — pertenencia muchos-a-muchos con **PK compuesta** `(id_cabana, id_zona)`, FK `CASCADE` del lado cabaña / `RESTRICT` del lado zona, e índice inverso `idx_cabana_zona_id_zona`. Seed: 5 pertenencias.
- **`resolver_beneficiario(p_id_cabana BIGINT, p_fecha DATE) RETURNS BIGINT`** — el seam. `LANGUAGE sql`, `STABLE`, `SECURITY INVOKER`. `p_fecha` **incluido pero ignorado** en el MVP (forward-compat para titularidad por rango futura). `REVOKE EXECUTE` de `PUBLIC`/`anon`/`authenticated`/`service_role` (paridad con los objetos existentes).
- **Marcador de ambiente** — fila `configuracion_general('ambiente','test', editable=false)` usada como **gate anti-OPS duro** en los bloques write de 9C (y reutilizable por 9D–9G).

### 2.1 Datos sembrados (seed 9C en TEST)

| Cabaña (id TEST) | Valor relativo | Beneficiario | Zona |
|---|---|---|---|
| Arrebol (3) | 100.00 | Franco | grandes |
| Madre Selva (2) | 100.00 | Rodrigo | grandes |
| Bamboo (1) | 100.00 | Remo | grandes |
| Guatemala (4) | 78.00 | Franco | chicas |
| Tokio (5) | 78.00 | Remo | chicas |

> Nota: el seed se resolvió **por nombre**, no por id; los ids de TEST (Bamboo=1, etc.) no afectan el resultado.

---

## 3. Bloques ejecutados (bitácora)

| Bloque | Contenido | Resultado |
|---|---|---|
| **A** | Diagnóstico / gate read-only (identidad, cabañas 1–5, unicidad de socios, snapshot de `activa`, ausencia de objetos 9C, estado del marcador). | 1ª corrida: **FRENAR** en socios (`Remo`=0, `Socio 3` presente). 2ª corrida (post-prerequisito): **verde**. |
| **Prerequisito** | D-9C-21 — `UPDATE socios SET nombre='Remo' WHERE id_socio=3 AND nombre='Socio 3'`. | OK (idempotente, reversible). |
| **B** | Marcador de ambiente `('ambiente','test')`, primer write, bootstrap auto-protegido. | OK → `valor='test'`. |
| **C** | Estructura aditiva: columnas nullable (FK + CHECK), `zonas`, `cabana_zona`, índice. | OK (14/14 chequeos; columnas nullable, tablas vacías). |
| **D** | Seed de zonas + backfill por nombre (con re-aserción de unicidad de socios) + pertenencias + `SET NOT NULL`. | OK (5/5 cabañas, 2 zonas, 5 pertenencias, NOT NULL activo). |
| **E** | Seam `resolver_beneficiario` (DROP+CREATE en runs separados) + `REVOKE EXECUTE`. | OK (firma/retorno/STABLE/INVOKER correctos; 5/5 resuelve; 5/5 fecha-independiente; 0 expuestos). |
| **F** | Verificación consolidada read-only + cross-check md5 de `activa` + confirmación de EXCLUDE. | OK (todos los chequeos; md5 idéntico; EXCLUDE solo en `reservas`/`bloqueos`, 0 en tablas 9C). |
| **G** | Este documento de cierre parcial. | — |

---

## 4. Decisiones registradas (D-9C-14 .. D-9C-21)

Continúan la numeración del conceptual (D-9C-01..13 ya cerradas). Todas implementadas y verificadas en TEST.

- **D-9C-14** — `valor_relativo` (`NUMERIC(6,2)`, `CHECK > 0`) e `id_socio_beneficiario` como **columnas en `cabanas`** (no satélite); agregadas **nullable → backfill → NOT NULL**. Sin DEFAULT/generated/trigger (`tipo` sugiere, no impone — D-9C-05).
- **D-9C-15** — FK `id_socio_beneficiario → socios(id_socio)`, **NOT NULL** (post-backfill), **`ON DELETE RESTRICT`**, nombre con rol explícito.
- **D-9C-16** — `zonas`: catálogo plano, **sin `activa`**; constraints `PK` + `uq_zonas_nombre` + `nombre NOT NULL` + `chk_zonas_nombre_no_vacio`.
- **D-9C-17** — `cabana_zona`: M2M con **PK compuesta** `(id_cabana, id_zona)`, FKs (**CASCADE** cabaña / **RESTRICT** zona), índice inverso en `id_zona`.
- **D-9C-18** — Seam `resolver_beneficiario(p_id_cabana, p_fecha) RETURNS BIGINT` `STABLE` `SECURITY INVOKER`, con `p_fecha` **incluido pero ignorado** en el MVP; `REVOKE EXECUTE` de `PUBLIC`/`anon`/`authenticated`/`service_role`. **Confirmado en vivo:** el REVOKE no rompe la invocación por ownership (los chequeos 6/7 de E.4 llamaron a la función como `postgres` tras el REVOKE).
- **D-9C-19** — Gate anti-OPS por **marcador `configuracion_general('ambiente','test')`**: bloque propio (bootstrap) con rollback y verificación; guard duro de los bloques write de Carril B. El marcador `'ops'` se sembrará recién en la promoción coordinada.
- **D-9C-20** — Seed **sin ambigüedad**: el gate exige `Franco`/`Rodrigo`/`Remo` exactamente una vez, y el bloque de seed **re-asegura la unicidad en la misma transacción** antes de resolver por nombre (no se usan ids literales).
- **D-9C-21** — **Completar el placeholder del tercer socio** (`Socio 3` → `Remo`) como **prerequisito** de Carril B. Detectado por el gate de unicidad del Bloque A; resuelto con un `UPDATE` guardado por `WHERE id_socio=3 AND nombre='Socio 3'` (idempotente, reversible) antes de cualquier write de 9C.

---

## 5. Verificación (estado final probado en TEST)

- **Estructura:** `cabanas.valor_relativo` y `cabanas.id_socio_beneficiario` existen y son **NOT NULL**; tablas `zonas` y `cabana_zona` creadas con sus constraints e índice; función `resolver_beneficiario` presente con firma y propiedades correctas (`STABLE`, `SECURITY INVOKER`, retorno `bigint`).
- **Datos:** sin NULLs en las columnas nuevas; `zonas` = 2 (`grandes`, `chicas`); `cabana_zona` = 5; las 5 cabañas con valor+beneficiario esperados; las 5 pertenencias correctas.
- **Seam:** `resolver_beneficiario(id, fecha)` = `id_socio_beneficiario` para las 5 cabañas, e **independiente de la fecha** (mismo resultado con fechas distintas).
- **No regresión sobre el flag global:** `cabanas.activa` sin cambios — fingerprint md5 `facd2112861454dd5699484c22ba265d` idéntico al snapshot tomado en el Bloque A (antes de cualquier write).
- **Aislamiento de 9D:** sin columnas de tipo rango (`daterange`/`tsrange`/`tstzrange`) introducidas por 9C; los únicos `EXCLUDE` del schema son los anti-overbooking pre-existentes de `reservas` y `bloqueos` (2 en total, 0 en tablas de 9C).
- **Grants:** `resolver_beneficiario` sin `EXECUTE` a `PUBLIC`/`anon`/`authenticated`/`service_role`.

---

## 6. DDL aplicado (registro — esta sección es la fuente hasta el bump del canónico)

Como el canónico **no se bumpea** en 9C, este documento es el registro autoritativo del schema de 9C en TEST hasta la promoción coordinada.

```sql
-- Prerequisito (D-9C-21)
UPDATE socios SET nombre = 'Remo' WHERE id_socio = 3 AND nombre = 'Socio 3';

-- Marcador de ambiente (D-9C-19)
INSERT INTO configuracion_general (clave, valor, descripcion, categoria, editable)
VALUES ('ambiente', 'test',
        'Marcador de entorno para gates de Carril B (D-9C-19)', 'infra', FALSE)
ON CONFLICT (clave) DO NOTHING;

-- Estructura cabanas (D-9C-14 / D-9C-15) — agregadas nullable; NOT NULL aplicado luego
ALTER TABLE cabanas
  ADD COLUMN valor_relativo NUMERIC(6,2)
    CONSTRAINT chk_cabanas_valor_relativo_positivo CHECK (valor_relativo > 0);
ALTER TABLE cabanas
  ADD COLUMN id_socio_beneficiario BIGINT
    CONSTRAINT fk_cabanas_socio_beneficiario
      REFERENCES socios(id_socio) ON DELETE RESTRICT;

-- zonas (D-9C-16)
CREATE TABLE zonas (
  id_zona      BIGSERIAL PRIMARY KEY,
  nombre       TEXT NOT NULL,
  descripcion  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_zonas_nombre UNIQUE (nombre),
  CONSTRAINT chk_zonas_nombre_no_vacio CHECK (length(trim(nombre)) > 0)
);

-- cabana_zona (D-9C-17)
CREATE TABLE cabana_zona (
  id_cabana    BIGINT NOT NULL,
  id_zona      BIGINT NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_cabana_zona PRIMARY KEY (id_cabana, id_zona),
  CONSTRAINT fk_cabana_zona_cabana
    FOREIGN KEY (id_cabana) REFERENCES cabanas(id_cabana) ON DELETE CASCADE,
  CONSTRAINT fk_cabana_zona_zona
    FOREIGN KEY (id_zona) REFERENCES zonas(id_zona) ON DELETE RESTRICT
);
CREATE INDEX idx_cabana_zona_id_zona ON cabana_zona(id_zona);

-- Seed zonas + backfill + pertenencias (D-9C-14 / D-9C-20)
INSERT INTO zonas (nombre, descripcion) VALUES
  ('grandes', 'Zona de cabañas grandes (seed MVP 9C)'),
  ('chicas',  'Zona de cabañas chicas (seed MVP 9C)')
ON CONFLICT (nombre) DO NOTHING;

UPDATE cabanas c
SET valor_relativo = v.valrel, id_socio_beneficiario = s.id_socio
FROM (VALUES
    ('Arrebol',100,'Franco'),('Madre Selva',100,'Rodrigo'),('Bamboo',100,'Remo'),
    ('Guatemala',78,'Franco'),('Tokio',78,'Remo')
) AS v(cab_nombre, valrel, socio_nombre)
JOIN socios s ON s.nombre = v.socio_nombre
WHERE c.nombre = v.cab_nombre;

INSERT INTO cabana_zona (id_cabana, id_zona)
SELECT c.id_cabana, z.id_zona
FROM (VALUES
    ('Arrebol','grandes'),('Madre Selva','grandes'),('Bamboo','grandes'),
    ('Guatemala','chicas'),('Tokio','chicas')
) AS m(cab_nombre, zona_nombre)
JOIN cabanas c ON c.nombre = m.cab_nombre
JOIN zonas   z ON z.nombre = m.zona_nombre
ON CONFLICT (id_cabana, id_zona) DO NOTHING;

-- Endurecimiento NOT NULL (post-backfill)
ALTER TABLE cabanas ALTER COLUMN valor_relativo        SET NOT NULL;
ALTER TABLE cabanas ALTER COLUMN id_socio_beneficiario SET NOT NULL;

-- Seam (D-9C-18) — DROP+CREATE en runs separados (lección del Dashboard)
DROP FUNCTION IF EXISTS resolver_beneficiario(BIGINT, DATE);
CREATE FUNCTION resolver_beneficiario(p_id_cabana BIGINT, p_fecha DATE)
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  -- p_fecha se ignora en el MVP (seam): hoy devuelve el beneficiario estable.
  SELECT id_socio_beneficiario FROM cabanas WHERE id_cabana = p_id_cabana;
$$;
REVOKE EXECUTE ON FUNCTION resolver_beneficiario(BIGINT, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION resolver_beneficiario(BIGINT, DATE) FROM anon;
REVOKE EXECUTE ON FUNCTION resolver_beneficiario(BIGINT, DATE) FROM authenticated;
REVOKE EXECUTE ON FUNCTION resolver_beneficiario(BIGINT, DATE) FROM service_role;
```

---

## 7. Lo que NO se hizo en 9C (alcance respetado)

- **No se tocó OPS.** 9C vive solo en TEST.
- **No se bumpeó el canónico.** `6B_SCHEMA_SQL.md v1.7.3` sigue vigente.
- **No se promovió el helper** `public.abortar_si_falla(jsonb)` de 9B (sigue solo en TEST).
- **No se diseñó ni implementó:** activación por rango / `daterange` / política mensual (9D); matriz derivada (9E); gasto rediseñado con clases A/C/D/E y pagador-socio (9F); cascada read-only de 11 pasos (9G); saldos internos / liquidaciones persistidas / snapshots (9H); fiscal/AFIP/ARCA/IVA (9I); motor de valor/hora; zonas jerárquicas; pool como zona; saldado financiero; workflows n8n.
- **No se construyó historial/tabla de rangos de titularidad** (sería historial encubierto; va contra D-9C-11). La forward-compat queda servida por la firma `(id_cabana, fecha)` del seam, no por estructura de rango.
- **No se usó `socios.porcentaje_utilidades`** como fuente de reparto (legacy, superado por la matriz dinámica).

---

## 8. Lecciones (para `Lecciones_Aprendidas.md`)

- **L-9C-01** — El seed canónico de 6B ships el **tercer socio como placeholder `Socio 3`**. Cada entorno requiere completarlo con el nombre real (`Remo`) **antes** del seed de beneficiarios de 9C. El gate de unicidad de socios del Bloque A lo detecta y frena; resolverlo es prerequisito (D-9C-21). Verificar lo mismo en OPS antes de promover.
- **L-9C-02** — Columnas internas del catálogo de tipo `"char"` (ej. `pg_proc.provolatile`) requieren **cast explícito a `text`** dentro de un `UNION`; si no, falla con `ERROR 42804: UNION types text and "char" cannot be matched`.
- **L-9C-03** — Para verificar que una sub-etapa **no introdujo `EXCLUDE`/rangos**, contar filtrando por `conrelid` de las tablas de la sub-etapa, **no** `COUNT(*) WHERE contype='x'` global: el schema base ya tiene 2 `EXCLUDE` anti-overbooking (`reservas`, `bloqueos`) que inflan el conteo global.

---

## 9. Pendiente para la promoción coordinada (NO ahora)

Todo lo de Carril B se promueve a OPS en **una sola operación**, con aprobación explícita y **bump único** del canónico. Lo que 9C deja anotado para ese momento:

- **Exposición Data API de `zonas`/`cabana_zona`:** se crearon con RLS deshabilitado (igual que el resto del schema; acceso por ownership vía n8n-as-`postgres`). Aplicar el **mismo hardening** que 7B/7E sobre los objetos existentes (o confirmar que "Automatically expose new tables" está OFF). No se tocó en 9C.
- **Recrear en OPS, en la operación coordinada:** marcador `('ambiente','ops')`; las columnas/constraints de `cabanas`; `zonas` y `cabana_zona` (con seed); el seam `resolver_beneficiario` (con la disciplina **DROP+CREATE** + `REVOKE`); el helper `abortar_si_falla` de 9B; y el conjunto 9D–9G cuando esté listo.
- **Prerequisito en OPS:** verificar/completar el placeholder del tercer socio en OPS (L-9C-01) antes del seed de beneficiarios.

---

## 10. Estado tras 9C y forward pointers

- **Carril B / schema:** 9C **cerrada y verificada en TEST**. Es el primer cimiento de datos de la contabilidad operativa interna.
- **Inmediato siguiente:** **9D — activación operativa por rango `[)`** (política mensual, "cubre el mes completo"; pro-rata diario diferido). 9D cuelga los rangos de activación del catálogo enriquecido de 9C.
- **Después:** **9E** (matriz derivada read-only, lee catálogo + valor relativo + activación 9D + titularidad vía seam; aterriza el centavo residual D-9C-02) → **9F** (gasto rediseñado; el pagador podrá ser un socio, D-9C-03) → **9G** (cascada read-only de 11 pasos).
- **Cuatro preguntas marco** (P1–P4) ya decididas y aterrizando en sus sub-etapas; sin reabrir.

> **Nota de proceso:** este cierre se redacta **antes** de actualizar los seis satélites (`ESTADO_ACTUAL_VITA_DELTA.md`, `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `Pendiente_pre_produccion.md`, `6B_SCHEMA_SQL.md`, `CLAUDE.md`). La propagación es el **paso siguiente** y se hace como conjunto, con Franco aportando los satélites actuales. Hasta entonces, este documento es la fuente del contenido a propagar (D-9C-14..21; L-9C-01..03; estado de 9C validada en TEST, OPS pendiente). El canónico **no** se bumpea en 9C.

---

**Fin de `9C_CIERRE.md` — 9C cerrada y verificada en TEST. Sin OPS, sin bump del canónico, sin promoción del helper. Carril B continúa en 9D.**
