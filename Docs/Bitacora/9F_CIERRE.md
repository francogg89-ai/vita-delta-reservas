# 9F_CIERRE.md — Cierre parcial Etapa 9F / Carril B

**Etapa:** 9F — Gasto rediseñado: entidad `gastos_internos` con clases A/C/D/E, alcance condicional, pagador-socio y separación desembolso/incidencia. Cuarta sub-etapa de **schema** del Carril B / contabilidad operativa interna; **primera que vuelve a escribir tablas** (9E fue read-only).
**Estado:** ✅ **Cerrada y verificada en TEST.** Cierre **parcial** de Carril B (9G sigue pendiente).
**Entorno de validación:** TEST (`vita-delta-test`) — IDs de cabaña 1–5.
**Entorno de operación:** — (9F **no** se promovió a OPS; promoción diferida a la operación coordinada única de todo el Carril B).
**Fecha de cierre:** 2026-06-10.
**Base conceptual:** `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md` (v0.8) — §1 (tres ejes + dos niveles de atadura), §4 (cascada de 11 pasos), §6 (clase ⇒ momento + alcance), §7 (estructura de gasto, sugerencia, override), §8 (tabla práctica y filtro maestro); decisión marco **D-9C-03** (horas de socio = gasto valorizado manual; pagador puede ser socio). 9F **no tiene conceptual propio**; su dirección vive en el conceptual del Carril B. Documento de encuadre: `PROMPT_ETAPA_9F_GASTO_REDISEÑADO.md`.
**Depende de:** 9C (catálogo enriquecido + zonas + seam), 9D (activación por rango) y 9E (matriz derivada), las tres cerradas en TEST.
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` — **NO modificado** (sin bump; se actualizará con bump único en la promoción coordinada).
**Autores:** Franco (titular, ejecutor de todos los writes) + Claude (arquitecto).
**Decisiones registradas:** D-9F-01 a D-9F-21. **Lecciones:** L-9F-01 a L-9F-04.

---

## 1. Resumen ejecutivo

9F materializó la **entidad de gasto del Carril B**: la tabla `gastos_internos`, que reemplaza funcionalmente a la `gastos` legacy del canónico (estructuralmente insuficiente: FK de una sola cabaña con `SET NULL`, `pagado_por` TEXT libre, sin clase A/C/D/E, sin alcance, sin separación desembolso/incidencia, sin trazabilidad de override). La entidad nueva captura los tres ejes del conceptual — **clase** (que define momento de cascada **y** alcance, juntos), **detalle de alcance** (zona para D, cabaña para E, ninguno para A/C) y **desembolso** (socio o caja) — y deja la **incidencia como derivación pura**, jamás persistida, resuelta por el seam de 9C + activaciones de 9D + matriz de 9E.

El corazón del diseño es el **set de 18 constraints** (14 CHECK + 3 FK `RESTRICT` + PK) que hace estructuralmente imposibles las incoherencias del §7.4 del conceptual (D sin zona, E sin cabaña, A/C con detalle, pagador inconsistente, override sin comentario), validado con **29 smokes** (24 negativos con SQLSTATE y constraint exactos; 5 positivos aceptados y revertidos por sentinel). La **trazabilidad del override** quedó sin columna redundante: se persiste `clase_sugerida` y el override **se deriva** comparando, con comentario obligatorio tanto en override como en carga sin sugerencia.

La validación semántica (Bloque D) demostró en vivo, con un fixture de 5 gastos y consultas read-only bajo frontera estricta (destinatarios por nombre, sin montos finales ni cascada): el gasto de zona bajando a los dueños de las **activas del período** (Guatemala+Tokio en noviembre; solo Tokio en julio — la incidencia es función del período, no del gasto); lo patrimonial (E) incidiendo en su beneficiario **aunque la cabaña esté fuera del pool**; y **desembolso ≠ incidencia** en monotributo pagado por Franco y horas de Rodrigo en Tokio (incidencia Remo), sin calcular deuda alguna (eso es 9G).

Metodología estricta respetada: diagnóstico read-only → diseño aprobado por decisiones numeradas → DDL bloque por bloque ejecutado por Franco en TEST → smokes → seed → verificación consolidada → este cierre. La `gastos` legacy quedó **intacta byte a byte** (recomparada contra el snapshot del Bloque A) y la base 9C/9D/9E sin regresión alguna.

---

## 2. Qué se construyó (objetos de 9F en TEST)

- **Tabla `gastos_internos`** — un renglón = un gasto interno del Carril B, con 17 columnas:
  - `id_gasto BIGSERIAL PK`
  - `fecha DATE NOT NULL` (fecha real del gasto) + `periodo DATE NOT NULL` (primer día del mes de imputación, `CHECK EXTRACT(DAY)=1`) — separa "cuándo se pagó" de "a qué liquidación entra"; el período entra directo a `matriz_participacion(periodo)`
  - `clase TEXT NOT NULL CHECK IN ('A','C','D','E')` + `clase_sugerida TEXT NULL` (mismo dominio; `NULL` = sin sugerencia / "otros")
  - `etiqueta TEXT NOT NULL` no vacía (libre, sin catálogo; `'horas de trabajo'` como literal especial de D-9C-03)
  - `monto NUMERIC(12,2) NOT NULL CHECK > 0` + `moneda TEXT NOT NULL DEFAULT 'ARS' CHECK ARS-only`
  - `id_zona BIGINT NULL` FK `zonas` RESTRICT (solo clase D) + `id_cabana BIGINT NULL` FK `cabanas` RESTRICT (solo clase E), atados por `chk_gastos_internos_alcance_por_clase`
  - `pagador_tipo TEXT NOT NULL CHECK IN ('socio','caja')` + `id_socio_pagador BIGINT NULL` FK `socios` RESTRICT, atados por `chk_gastos_internos_pagador_consistente`
  - `medio_pago TEXT NULL`, `comentario TEXT NULL`, `comprobante_url TEXT NULL` (los tres NULL-o-no-vacíos; comentario **obligatorio** si override o sin sugerencia)
  - `creado_por TEXT NOT NULL` no vacío + `created_at TIMESTAMPTZ DEFAULT NOW()`
  - **Sin** `source_event` (carga SQL controlada), **sin** soft-delete, **sin** columna `es_override` (derivado), **sin** columna de incidencia (derivada), **sin** rangos/`EXCLUDE`.
- **Índice** `idx_gastos_internos_periodo_clase (periodo, clase)` — la consulta dominante de 9G.
- **Fixture técnico** de 5 gastos (`creado_por='seed_9f_validacion'`, ids 30–34; gap 1–29 por smokes revertidos, D-9F-21), conservado hasta 9G (D-9F-17). **No son datos reales y no viajan a OPS.**
- RLS deshabilitado (paridad con el resto del schema; hardening en el pendiente coordinado).

### 2.1 Fixture de validación (datos de laboratorio en TEST)

| id | Clase | Etiqueta | Período | Monto | Desembolso | Alcance | Incidencia derivada (validada en D.2) |
|---|---|---|---|---|---|---|---|
| 30 | A | insumos de limpieza | 2026-07 | 40.000,00 | caja | pool | Operativo + beneficiarios del pool de julio (Franco, Remo, Rodrigo) — paso 2 |
| 31 | C | monotributo | 2026-07 | 25.000,00 | **socio Franco** | pool | Solo beneficiarios (Franco, Remo, Rodrigo) — paso 7; desembolso ≠ incidencia |
| 32 | D | jardin (**override C→D** + comentario) | 2026-11 | 30.000,00 | caja | zona chicas | Guatemala>Franco \| Tokio>Remo (activas de la zona en nov). Contraste julio: solo Tokio>Remo |
| 33 | E | termotanque | 2026-08 | 180.000,00 | **socio Rodrigo** | cabaña Guatemala | **Franco** vía seam, con la cabaña **fuera del pool** (`activa_en_periodo=false`) |
| 34 | E | horas de trabajo (sin sugerencia + comentario) | 2026-07 | 60.000,00 | **socio Rodrigo** | cabaña Tokio | Remo — la deuda Remo→Rodrigo se deriva en 9G, no acá |

---

## 3. Bloques ejecutados (bitácora)

| Bloque | Contenido | Resultado |
|---|---|---|
| **A** | Gate/diagnóstico read-only: ambiente `test`, cabañas 1–5, socios únicos, base 9C/9D/9E presente y **ejecutando** (seam a 2 fechas, matriz jul/nov), `gastos` legacy con **0 filas y secuencia nunca usada** (confirma D-7D-01), estructura legacy snapshoteada, `gastos_internos` ausente, md5 baseline de `cabanas.activa` (`90e55df2…`), EXCLUDE=3. | Verde 1ª corrida (21/21). |
| **B** | B.1: gate transaccional + `CREATE TABLE gastos_internos` (18 constraints) + índice. B.2: verificación read-only (columnas, constraints, FKs `r`, índices, defaults, RLS, 0 filas, aislamiento). | Verde (15/15, defaults incluidos). |
| **C** | 29 smokes con sentinel `P9F01` + `GET STACKED DIAGNOSTICS`: 24 negativos rechazados con SQLSTATE y constraint exactos (`23514`/`23503`/`23502`); 5 positivos (uno por clase + horas) aceptados y revertidos. Reversión total: 0 filas. Secuencia consumida = 29. | Verde (36/36). Nota: smokes 1 y 7 reportaron la *otra* constraint del multi-check (L-9F-01). |
| **D** | D.1 v2: seed de 5 gastos con gate reforzado de 4 condiciones (ambiente → existe → **marcador → vacía**, diagnóstico progresivo). D.2: validación semántica read-only bajo frontera D-9F-20 — seed fila por fila + incidencias derivadas por nombre (pool A/C, zona→activas→dueños con contraste jul/nov, seam con cabaña desactivada, desembolso≠incidencia). D.R: borrado por marcador, **disponible y no corrido** (D-9F-17). | D.1: 5 filas. D.2: verde (18/18). |
| **E** | Verificación consolidada final: estado completo de `gastos_internos` + fixture, **legacy recomparada en detalle contra el snapshot de A** (columnas, constraints, índices, filas, secuencia), 9C/9D/9E en detalle (datos, seam, matriz), md5 idéntico, EXCLUDE=3, secuencia=34 (29+5, aritmética exacta). | Verde (23/23 + INFO). |
| **F** | Este documento de cierre parcial. | — |

---

## 4. Decisiones registradas (D-9F-01 .. D-9F-21)

Todas aprobadas explícitamente por Franco e implementadas/verificadas en TEST.

- **D-9F-01** — **Tabla nueva** `gastos_internos`; la `gastos` legacy queda **congelada/deprecada e intacta** (0 filas, secuencia nunca usada, estructura idéntica A↔E). **Sin migración** (el Bloque A certificó que no hay datos). Su destino formal (DROP o rename) se decide en la **promoción coordinada**, con el bump único del canónico. Se descartaron el ALTER in-place (cadena quirúrgica divergente del canónico sin bump) y el DROP+CREATE con el mismo nombre (haría desaparecer un objeto del canónico en TEST; rompe la disciplina de aditividad de 9C/9D).
- **D-9F-02** — Nombre **`gastos_internos`** (ancla con "contabilidad operativa interna"; distingue del legacy y de lo fiscal).
- **D-9F-03** — `clase` como **TEXT + CHECK** `('A','C','D','E')`, no enum nativo (paridad con `bloqueos.motivo`; evolución más barata).
- **D-9F-04** — **Alcance condicional**: `id_zona`/`id_cabana` nullable + `chk_gastos_internos_alcance_por_clase` (D ⇒ zona sin cabaña; E ⇒ cabaña sin zona; A/C ⇒ ninguno). El alcance **no se elige**: lo deriva la clase (§6 del conceptual); los FKs son solo el *detalle*. La incoherencia estructural del §7.4 queda imposible por constraint.
- **D-9F-05** — **Pagador**: `pagador_tipo IN ('socio','caja')` + `id_socio_pagador` nullable FK `socios` `ON DELETE RESTRICT` + CHECK de consistencia (socio ⇔ id presente; caja ⇔ id ausente). Materializa D-9C-03: el pagador de un gasto puede ser un socio.
- **D-9F-06** — **La incidencia NO se persiste.** Se deriva por clase + alcance + período, vía `resolver_beneficiario` (9C), `activaciones_operativas` (9D) y `matriz_participacion` (9E). Validado en vivo en D.2. Misma filosofía que la matriz: derivada, nunca guardada.
- **D-9F-07** — `etiqueta` **TEXT libre** NOT NULL no vacía; **sin catálogo de etiquetas en 9F**. El mapa etiqueta→clase sugerida (§7.2) queda como guía de carga; el catálogo nace, si nace, con la capa de formulario futura.
- **D-9F-08** — **Trazabilidad del override sin columna redundante**: se persiste `clase_sugerida` (nullable; NULL = sin sugerencia) y el override **se deriva** (`clase <> clase_sugerida` con sugerencia presente). Un único CHECK (`chk_gastos_internos_comentario_requerido`) exige comentario no vacío tanto en **override** (§7.3) como en **carga sin sugerencia** (§7.2, rama "otros").
- **D-9F-09** — **Horas de socio sin flag**: la literal `'horas de trabajo'` (D-9C-03) + `chk_gastos_internos_horas_pagador_socio` con `lower(btrim(etiqueta))` — endurecido contra mayúsculas/espacios (la caja no trabaja horas). Fragilidad asumida: no protege typos; un typo produce una fila sin guarda, nunca un rechazo falso.
- **D-9F-10** — **`fecha` + `periodo` explícito** normalizado a primer día de mes (`CHECK EXTRACT(DAY FROM periodo)=1`). "Cuándo se pagó" ≠ "a qué liquidación entra"; la incidencia de D y la matriz de A/C se evalúan contra `periodo`. El cargador lo setea (típicamente el mes de la fecha, salvo decisión).
- **D-9F-11** — **`moneda` como campo** `TEXT NOT NULL DEFAULT 'ARS'` con CHECK ARS-only. Ampliación futura = relajar un CHECK (9H si corresponde), sin semántica retroactiva sobre filas sin unidad.
- **D-9F-12** — **Sin función formal de expansión de incidencia en 9F**; queda para 9G (la incidencia de A/C depende de matriz y % operativo — abierto — y la de D arrastra los pesos internos de zona, también de 9G). La validación de 9F se hizo con consultas read-only ad-hoc, sin crear objetos.
- **D-9F-13** — **Set completo de constraints**: 14 CHECK + 3 FK RESTRICT + PK (18 totales, todas nombradas). Cada una ejercitada al menos una vez en el Bloque C.
- **D-9F-14** — **Auditoría**: `creado_por` NOT NULL **no vacío** + `created_at`; **sin `source_event`** (carga SQL controlada, paridad D-9D-07). Más estricto que 9D (`creado_por` allá nullable) porque acá hay plata.
- **D-9F-15** — **Sin soft-delete** ni estado de anulación; corrección de errores por SQL controlado (paridad 9D). Se rediscute si la carga deja de ser SQL controlado.
- **D-9F-16** — `medio_pago` **TEXT nullable**, sin FK a `cuentas_cobro` (catálogo de **cobro**/ingreso; cruzarlo mezclaría sentidos del flujo).
- **D-9F-17** — El seed de validación se **conserva como fixture técnico de TEST hasta 9G**, marcado `creado_por='seed_9f_validacion'` y **borrable por marcador** con el run D.R (documentado en §6). Las 5 filas son **datos de laboratorio, no reales**, y **no viajan a OPS**: la promoción coordinada recrea estructura por DDL, **no copia datos de TEST**.
- **D-9F-18** — **Un solo índice** inicial `(periodo, clase)`; sin índices por zona/cabaña/fecha en el MVP ("índices solo si justifican consulta o integridad").
- **D-9F-19** — **Higiene de TEXT NULL-safe**: obligatorios no vacíos post-`btrim` (`etiqueta`, `creado_por`, y `comentario` cuando el CHECK condicional lo exige); opcionales NULL-o-no-vacíos (`medio_pago`, `comprobante_url`). Formulación siempre NULL-safe explícita (en un CHECK, una expresión que evalúa a NULL **pasa**: `length(trim(x)) > 0` solo no rechaza el NULL).
- **D-9F-20** — **Frontera de las consultas semánticas** (Bloque D): muestran **destinatarios por nombre** (pool / activas de zona → dueños / beneficiario vía seam), **jamás** saldos, deudas, netos pagador-vs-incidencia, montos finales de A/C, porcentajes ni cascada — el % operativo sigue abierto y todo eso es 9G.
- **D-9F-21** — **No resetear secuencias por estética.** Los gaps de smokes revertidos (ids 1–29 consumidos) son comportamiento normal de BIGSERIAL/PostgreSQL y no afectan la contabilidad. Coherente con D-7D-01 (reset solo en vaciados, nunca cosmético).

---

## 5. Verificación (estado final probado en TEST)

- **Estructura:** `gastos_internos` con 17 columnas (tipos y nullabilidad exactos), 18 constraints nombradas (14 `c` + 3 `f` con `confdeltype='r'` + PK), índice compuesto `(periodo, clase)`, defaults `now()`/`'ARS'`, RLS deshabilitado (paridad).
- **Constraints probadas en vivo (Bloque C):** 24 intentos inválidos rechazados con SQLSTATE y constraint exactos — clase/sugerida fuera de dominio, alcance↔clase en sus 4 combinaciones inválidas, pagador inconsistente en ambos sentidos, monto 0, moneda USD, período no normalizado, TEXT vacíos/espacios en los 5 campos guardados, override sin comentario (y con comentario de espacios), rama "otros" sin comentario, horas con pagador caja (mayúsculas+espacios incluidos), 3 FKs inexistentes. 5 positivos (A/C/D/E/horas) aceptados y revertidos. **0 filas residuales.**
- **Semántica derivada (Bloque D.2):** incidencia A/C = socios del pool del período del gasto; D = dueños de las activas de la zona en el período (**Guatemala>Franco | Tokio>Remo** en noviembre; **Tokio>Remo** en julio); E = beneficiario vía seam **con la cabaña fuera del pool** (`activa_en_periodo=false`); horas: desembolso Rodrigo ≠ incidencia Remo, sin cálculo de deuda. Override y sin-sugerencia derivados sin columna: `override=1|sin_sugerencia=1`.
- **No regresión:** `gastos` legacy **idéntica al snapshot del Bloque A** (columnas, constraints, índices, 0 filas, secuencia nunca usada); 9C/9D/9E intactos en detalle (catálogo, pertenencias, activaciones, seam coherente a 2 fechas, matriz ejecutando jul=378/nov=456); md5 de `cabanas.activa` = `90e55df2e433c09ee57c06eaa753c618` (baseline A) en B, C, D y E; `EXCLUDE` global = 3 (9F no agrega).
- **Aritmética de secuencia:** `last_value` = 34 = 29 smokes + 5 fixture; ids del fixture 30–34. Ambiente `test` en todos los runs.

---

## 6. DDL aplicado (registro — fuente hasta el bump del canónico)

Como el canónico **no se bumpea** en 9F, esta sección es el registro autoritativo del schema de 9F en TEST hasta la promoción coordinada. Todos los runs write llevaron **gate transaccional de ambiente** (`configuracion_general('ambiente','test')`) y, en D.1, gate de diagnóstico progresivo (existe → marcador ausente → tabla vacía); los gates no se reproducen aquí.

```sql
-- Estructura (Bloque B, runs B.1)
CREATE TABLE gastos_internos (
  id_gasto          BIGSERIAL PRIMARY KEY,
  fecha             DATE NOT NULL,
  periodo           DATE NOT NULL,            -- primer dia del mes de imputacion (D-9F-10)
  clase             TEXT NOT NULL,            -- A/C/D/E elegida (D-9F-03)
  clase_sugerida    TEXT,                     -- NULL = sin sugerencia ("otros") (D-9F-08)
  etiqueta          TEXT NOT NULL,            -- descriptiva; 'horas de trabajo' especial (D-9C-03)
  monto             NUMERIC(12,2) NOT NULL,
  moneda            TEXT NOT NULL DEFAULT 'ARS',  -- ARS-only por CHECK (D-9F-11)
  id_zona           BIGINT,                   -- solo clase D
  id_cabana         BIGINT,                   -- solo clase E
  pagador_tipo      TEXT NOT NULL,            -- 'socio' | 'caja' (D-9F-05)
  id_socio_pagador  BIGINT,                   -- NOT NULL sii pagador_tipo='socio'
  medio_pago        TEXT,                     -- opcional (D-9F-16)
  comentario        TEXT,                     -- obligatorio si override o sin sugerencia
  comprobante_url   TEXT,
  creado_por        TEXT NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT fk_gastos_internos_zona
    FOREIGN KEY (id_zona) REFERENCES zonas(id_zona) ON DELETE RESTRICT,
  CONSTRAINT fk_gastos_internos_cabana
    FOREIGN KEY (id_cabana) REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  CONSTRAINT fk_gastos_internos_socio_pagador
    FOREIGN KEY (id_socio_pagador) REFERENCES socios(id_socio) ON DELETE RESTRICT,

  CONSTRAINT chk_gastos_internos_clase
    CHECK (clase IN ('A','C','D','E')),
  CONSTRAINT chk_gastos_internos_clase_sugerida
    CHECK (clase_sugerida IS NULL OR clase_sugerida IN ('A','C','D','E')),
  CONSTRAINT chk_gastos_internos_alcance_por_clase
    CHECK (
         (clase = 'D' AND id_zona IS NOT NULL AND id_cabana IS NULL)
      OR (clase = 'E' AND id_cabana IS NOT NULL AND id_zona IS NULL)
      OR (clase IN ('A','C') AND id_zona IS NULL AND id_cabana IS NULL)
    ),
  CONSTRAINT chk_gastos_internos_pagador_tipo
    CHECK (pagador_tipo IN ('socio','caja')),
  CONSTRAINT chk_gastos_internos_pagador_consistente
    CHECK (
         (pagador_tipo = 'socio' AND id_socio_pagador IS NOT NULL)
      OR (pagador_tipo = 'caja'  AND id_socio_pagador IS NULL)
    ),
  CONSTRAINT chk_gastos_internos_monto
    CHECK (monto > 0),
  CONSTRAINT chk_gastos_internos_moneda
    CHECK (moneda = 'ARS'),
  CONSTRAINT chk_gastos_internos_periodo_normalizado
    CHECK (EXTRACT(DAY FROM periodo) = 1),
  CONSTRAINT chk_gastos_internos_etiqueta_no_vacia
    CHECK (length(btrim(etiqueta)) > 0),
  CONSTRAINT chk_gastos_internos_creado_por_no_vacio
    CHECK (length(btrim(creado_por)) > 0),
  CONSTRAINT chk_gastos_internos_comentario_requerido
    CHECK (
         (clase_sugerida IS NOT NULL AND clase = clase_sugerida)
      OR (comentario IS NOT NULL AND length(btrim(comentario)) > 0)
    ),
  CONSTRAINT chk_gastos_internos_medio_pago_no_vacio
    CHECK (medio_pago IS NULL OR length(btrim(medio_pago)) > 0),
  CONSTRAINT chk_gastos_internos_comprobante_no_vacio
    CHECK (comprobante_url IS NULL OR length(btrim(comprobante_url)) > 0),
  CONSTRAINT chk_gastos_internos_horas_pagador_socio
    CHECK (lower(btrim(etiqueta)) <> 'horas de trabajo' OR pagador_tipo = 'socio')
);
CREATE INDEX idx_gastos_internos_periodo_clase ON gastos_internos(periodo, clase);

-- Fixture de validación (Bloque D, run D.1 v2, D-9F-17) — resolución por nombre, sin ids literales
INSERT INTO gastos_internos
  (fecha, periodo, clase, clase_sugerida, etiqueta, monto, pagador_tipo, id_socio_pagador,
   id_zona, id_cabana, medio_pago, comentario, creado_por)
SELECT v.fecha, v.periodo, v.clase, v.clase_sugerida, v.etiqueta, v.monto, v.pagador_tipo,
       (SELECT id_socio  FROM socios  WHERE nombre = v.socio_pagador),
       (SELECT id_zona   FROM zonas   WHERE nombre = v.zona),
       (SELECT id_cabana FROM cabanas WHERE nombre = v.cabana),
       v.medio_pago, v.comentario, 'seed_9f_validacion'
FROM (VALUES
  (DATE '2026-07-05', DATE '2026-07-01', 'A', 'A',
   'insumos de limpieza', 40000.00::numeric(12,2), 'caja', NULL::text, NULL::text, NULL::text,
   NULL::text, NULL::text),
  (DATE '2026-07-20', DATE '2026-07-01', 'C', 'C',
   'monotributo', 25000.00, 'socio', 'Franco', NULL, NULL,
   'transferencia', NULL),
  (DATE '2026-11-12', DATE '2026-11-01', 'D', 'C',
   'jardin', 30000.00, 'caja', NULL, 'chicas', NULL,
   NULL, 'jardin del sector chicas, acordado de zona (seed 9F)'),
  (DATE '2026-08-10', DATE '2026-08-01', 'E', 'E',
   'termotanque', 180000.00, 'socio', 'Rodrigo', NULL, 'Guatemala',
   NULL, NULL),
  (DATE '2026-07-18', DATE '2026-07-01', 'E', NULL,
   'horas de trabajo', 60000.00, 'socio', 'Rodrigo', NULL, 'Tokio',
   NULL, '6 hs arreglo de deck, valor hora acordado a mano (seed 9F)')
) AS v(fecha, periodo, clase, clase_sugerida, etiqueta, monto, pagador_tipo, socio_pagador,
       zona, cabana, medio_pago, comentario);

-- Borrado del fixture por marcador (run D.R) — DISPONIBLE, NO ejecutado (D-9F-17: se corre al cierre de 9G
-- o en limpieza explícita; sin reset de secuencia, D-9F-21)
-- DELETE FROM gastos_internos WHERE creado_por = 'seed_9f_validacion';
```

---

## 7. Lo que NO se hizo en 9F (alcance respetado)

- **No se tocó OPS.** 9F vive solo en TEST.
- **No se bumpeó el canónico.** `6B_SCHEMA_SQL.md v1.7.3` sigue vigente; la `gastos` legacy que describe sigue existiendo **intacta** en TEST.
- **No se tocó** la `gastos` legacy (ni filas, ni DDL, ni secuencia), ni ningún objeto de 9C/9D/9E, ni `cabanas.activa`, ni `pagos`.
- **No se construyó:** la **cascada read-only de 11 pasos (9G)**; el **% operativo** (sigue abierto, sujeto a la conversación de Franco con sus socios — 9F no tiene ningún campo de porcentaje); función de expansión de incidencia (9G); **pesos del reparto interno de zona** (9G); lectura de `pagos`/ingresos (9G); persistencia de incidencia, liquidaciones o snapshots (9H); saldos/retiros/FX (9H); motor de valor/hora; catálogo de etiquetas con motor de sugerencias (capa formulario futura); workflows n8n/formularios; fiscal/AFIP/ARCA/IVA; soft-delete; `source_event`; reset de secuencias; hardening Data API adicional (pendiente coordinado).
- **No se migró nada** — el Bloque A certificó `gastos` legacy con 0 filas y secuencia nunca usada.

---

## 8. Lecciones (para `Lecciones_Aprendidas.md`)

- **L-9F-01** — **El orden de evaluación de múltiples CHECK no es el de declaración.** Cuando una fila viola varias CHECK a la vez, PostgreSQL reporta **una sola**, y no necesariamente la "más específica" (smokes 1 y 7: clase `'B'` reportó `alcance_por_clase` y pagador `'proveedor'` reportó `pagador_consistente`, no las constraints de dominio). En smokes multi-violación, validar **solo el SQLSTATE**; reservar la validación por nombre de constraint para intentos que violan exactamente una.
- **L-9F-02** — **Patrón de smoke transaccional con sentinel:** dentro de un `DO`, `EXECUTE` del intento + `RAISE ... USING ERRCODE` propio (`P9F01`) para revertir los inserts aceptados; handler con `GET STACKED DIAGNOSTICS ... CONSTRAINT_NAME` para capturar la constraint exacta del rechazo. Garantiza 0 filas residuales y precisión por constraint sin transacciones manuales por smoke, con resultados acumulados en una tabla `TEMP` (artefacto efímero aceptado: muere con la sesión, no toca el schema).
- **L-9F-03** — **El SQL Editor de Supabase cierra la sesión por run:** una transacción no puede quedar abierta esperando una decisión humana, y un `ROLLBACK` final taparía el último `SELECT` (solo se muestra el último). Para seeds con decisión diferida sobre su permanencia: separar en runs independientes (seed+`COMMIT` / verificación read-only / borrado por marcador) y convertir la decisión en "*cuándo* correr el borrado", no en "commitear o no".
- **L-9F-04** — **Gate de diagnóstico progresivo:** ordenar los chequeos de más específico a más genérico (marcador del seed **antes** que tabla-no-vacía) para que cada freno conserve su diagnóstico y su remediación propios. El orden inverso vuelve **inalcanzable** el chequeo específico (toda tabla con seed frena antes en el genérico) y degrada el mensaje de error justo en el caso más probable.

---

## 9. Pendiente para la promoción coordinada (NO ahora)

Todo Carril B se promueve a OPS en **una sola operación**, con aprobación explícita y **bump único** del canónico. Lo que 9F deja anotado:

- **Recrear `gastos_internos` en OPS** con el DDL de §6 (estructura + índice), **sin el fixture**: la promoción recrea estructura por DDL, **no copia datos de TEST** (D-9F-17). Depende de que 9C (zonas, `cabana_zona`, seam, columnas de `cabanas`) y `socios` con Remo ya estén en OPS (prerequisito L-9C-01).
- **Destino formal de la `gastos` legacy** (DROP o rename a `gastos_legacy`): decisión a tomar en la promoción, reflejada en el bump del canónico. Hasta entonces sigue intacta en TEST y OPS.
- **Hardening/exposición Data API en lote:** `gastos_internos` nació con RLS deshabilitado (paridad; acceso por ownership vía n8n-as-`postgres`). Aplicar el mismo hardening que 7B/7E (o confirmar "Automatically expose new tables" OFF), junto a los pendientes análogos de 9C (`zonas`/`cabana_zona`) y 9D (`activaciones_operativas`).
- **Borrado del fixture en TEST** (run D.R, por marcador `seed_9f_validacion`): al cierre de 9G o en limpieza explícita; sin reset de secuencia (D-9F-21).
- **Preguntas heredadas formalmente a 9G:** **Q-9G-zona-pesos** (¿el gasto D se reparte entre las activas de la zona en partes iguales o por valor relativo? — el conceptual no fija pesos y el caso chicas 78=78 no desambigua) y **Q-9G-zona-vacía** (gasto D imputado a un período sin activas en su zona: 9F no impide la carga; cómo lo reporta/arrastra la cascada es de 9G, análogo del pool vacío D-9E-06).

---

## 10. Estado tras 9F y forward pointers

- **Carril B / schema:** 9C, 9D, 9E y **9F cerradas y verificadas en TEST.** Quedan construidos: insumos estáticos (9C), activación por período (9D), matriz + primitivo de reparto (9E) y la **entidad de gasto** con sus cuatro clases, alcance, pagador-socio y trazabilidad (9F).
- **Inmediato siguiente:** **9G — cascada read-only de 11 pasos.** Compone ingreso (lectura de `pagos`, tipos `sena`/`saldo` al paso 1; `extra` al paso 6), gastos de `gastos_internos` por `periodo` y `clase` (A al paso 2; C al paso 7; D/E al paso 10), matriz y `repartir_por_matriz` (9E, paso 9), incidencia vía seam (9C); aplica el **% operativo** (paso 4) **cuando Franco lo cierre con sus socios** — sigue abierto; resuelve Q-9G-zona-pesos y Q-9G-zona-vacía; produce el saldo por socio del período como derivación, **sin persistir liquidaciones** (eso es 9H). El fixture de 9F queda como dato de prueba inicial.
- **Después:** **9H** — snapshots de liquidación, cuenta corriente de socios, retiros, revaluación ARS→USD (encuadrado en `PENDIENTE_CARRIL_B_9H_SALDOS_RETIROS_REVALUACION.md`).

> **Nota de proceso:** este cierre se redacta **antes** de actualizar los seis satélites (`ESTADO_ACTUAL_VITA_DELTA.md`, `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `Pendiente_pre_produccion.md`, `6B_SCHEMA_SQL.md`, `CLAUDE.md`). La propagación es el paso siguiente del Carril B y se hace como conjunto en su cierre formal, con Franco aportando los satélites actuales. Hasta entonces, este documento (junto con `9C_CIERRE.md`, `9D_CIERRE.md` y `9E_CIERRE.md`) es la fuente autoritativa del schema de Carril B en TEST. El canónico **no** se bumpea en 9F.

---

**Fin de `9F_CIERRE.md` — 9F cerrada y verificada en TEST. Sin OPS, sin bump del canónico, sin migración, legacy intacta, fixture conservado hasta 9G. Carril B continúa en 9G (cascada read-only de 11 pasos).**
