-- ============================================================================
-- BOOTSTRAP ENTORNO NUEVO v1.8.1 — 02: PARTE C (CARRIL B) · DDL EJECUTABLE
-- Fuente: 6B_SCHEMA_SQL.md v1.8.1, PARTE C, Bloques C0→C14 (EXTRACCIÓN LITERAL).
--   Carril B autocontenido (contabilidad operativa interna 9C→9H + helper 9B):
--   tablas, funciones, triggers de inmutabilidad, hardening (C12) y seeds
--   estructurales (C13). Cierra con C14, un bloque DO de asserts (auto-test):
--   su veredicto sale por el panel de NOTICE, no como fila (L-RDEV-04). La
--   fila-veredicto final vive en 02_VERIFY_FINAL_ENTORNO.sql.
-- ----------------------------------------------------------------------------
-- ESTADO DE ENTRADA: 01_VERIFY == PARTE_B_OK. Corre DESPUÉS de la Parte B.
-- USO: SQL Editor del PROYECTO NUEVO (confirmar Project Ref por URL; nunca OPS).
--   Pegar el archivo COMPLETO o por SECCIONES "-- ═══ BLOQUE CN ═══", una a la
--   vez con NADA seleccionado. C13 es un solo bloque con 6 sub-statements
--   (C13.1→C13.6): correrlo ENTERO (el NOT NULL de C13.4 depende del backfill
--   de C13.3).
-- ----------------------------------------------------------------------------
-- VARIANTE DEV: C13.1 siembra configuracion_general('ambiente') = 'dev'.
--   *** PUNTO DE SWAP PARA TEST/OPS: *** para bootstrappear TEST u OPS, cambiar
--   ÚNICAMENTE el literal 'dev' por 'test' / 'ops' en C13.1 (ver el comentario
--   inline marcado en el bloque). No hay otro punto a tocar. (Ver README.)
-- ============================================================================


-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C0 — Prerrequisito de extensión
-- ══════════════════════════════════════════════════════════════════════════
-- ============================================================================
-- PARTE C — SQL EJECUTABLE CARRIL B (CONTABILIDAD OPERATIVA INTERNA)
-- Estado canónico final del Carril B (9C→9H + helper 9B), consolidado en v1.8.0.
-- Corre DESPUÉS de Parte B sobre una base fresca. Autocontenido. SIN maquinaria
-- de promoción (gates de ambiente, asserts de promo, snapshots, reversiones).
-- ============================================================================

-- ── C0. Prerrequisito de extensión (ya creada en Bloque 1; defensivo idempotente) ──
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C1 — Columnas nuevas en cabanas
-- ══════════════════════════════════════════════════════════════════════════
-- ── C1. Columnas nuevas en cabanas (NULLABLE; NOT NULL se aplica en C13 post-backfill) ──
ALTER TABLE cabanas
  ADD COLUMN valor_relativo NUMERIC(6,2)
    CONSTRAINT chk_cabanas_valor_relativo_positivo CHECK (valor_relativo > 0);
ALTER TABLE cabanas
  ADD COLUMN id_socio_beneficiario BIGINT
    CONSTRAINT fk_cabanas_socio_beneficiario
      REFERENCES socios(id_socio) ON DELETE RESTRICT;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C2 — Catálogo de zonas y pertenencias
-- ══════════════════════════════════════════════════════════════════════════
-- ── C2. Catálogo de zonas y pertenencias (M2M) ──
CREATE TABLE zonas (
  id_zona      BIGSERIAL PRIMARY KEY,
  nombre       TEXT NOT NULL,
  descripcion  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_zonas_nombre UNIQUE (nombre),
  CONSTRAINT chk_zonas_nombre_no_vacio CHECK (length(trim(nombre)) > 0)
);

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

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C3 — Activaciones operativas (pool)
-- ══════════════════════════════════════════════════════════════════════════
-- ── C3. Activaciones operativas (pool; rango [) + EXCLUDE no-solape por cabaña) ──
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

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C4 — Gastos internos
-- ══════════════════════════════════════════════════════════════════════════
-- ── C4. Gastos internos (clasificación A/C/D/E; alcance por clase) ──
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

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C5 — Cuenta corriente 9H — tablas append-only
-- ══════════════════════════════════════════════════════════════════════════
-- ── C5. Cuenta corriente 9H — tablas append-only ──
CREATE TABLE liquidaciones_periodo (
  id_liquidacion            BIGSERIAL PRIMARY KEY,
  periodo                   DATE NOT NULL,
  pct_operativo             NUMERIC(6,4) NOT NULL,
  id_liquidacion_supersede  BIGINT,          -- NULL = raíz (primera foto del período)
  creado_por                TEXT NOT NULL,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  comentario                TEXT,

  CONSTRAINT chk_liq_periodo_dia1      CHECK (EXTRACT(DAY FROM periodo) = 1),
  CONSTRAINT chk_liq_pct_rango         CHECK (pct_operativo >= 0 AND pct_operativo <= 1),
  CONSTRAINT chk_liq_creado_por_ne     CHECK (btrim(creado_por) <> ''),
  CONSTRAINT chk_liq_comentario_ne     CHECK (comentario IS NULL OR btrim(comentario) <> ''),
  CONSTRAINT chk_liq_no_auto_supersede CHECK (id_liquidacion_supersede IS NULL
                                              OR id_liquidacion_supersede <> id_liquidacion),
  CONSTRAINT uq_liq_id_periodo         UNIQUE (id_liquidacion, periodo),
  CONSTRAINT fk_liq_supersede_mismo_periodo
      FOREIGN KEY (id_liquidacion_supersede, periodo)
      REFERENCES liquidaciones_periodo (id_liquidacion, periodo) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_liq_una_raiz_por_periodo
  ON liquidaciones_periodo (periodo) WHERE id_liquidacion_supersede IS NULL;
CREATE UNIQUE INDEX uq_liq_sin_fork
  ON liquidaciones_periodo (id_liquidacion_supersede) WHERE id_liquidacion_supersede IS NOT NULL;

-- ── 2) LIQUIDACION_CASCADA (pasos 1-8 agregados; aquí vive el paso 4) ────────
CREATE TABLE liquidacion_cascada (
  id_liquidacion   BIGINT NOT NULL
                   REFERENCES liquidaciones_periodo(id_liquidacion) ON DELETE RESTRICT,
  paso             SMALLINT NOT NULL,
  concepto         TEXT NOT NULL,
  monto            NUMERIC(14,2) NOT NULL,

  PRIMARY KEY (id_liquidacion, paso),
  CONSTRAINT chk_casc_paso_rango  CHECK (paso BETWEEN 1 AND 8),
  CONSTRAINT chk_casc_concepto_ne CHECK (btrim(concepto) <> '')
);

-- ── 3) LIQUIDACION_SOCIO (fila de 9G congelada; columnas separadas, D-9H-12) ─
CREATE TABLE liquidacion_socio (
  id_liquidacion        BIGINT NOT NULL
                        REFERENCES liquidaciones_periodo(id_liquidacion) ON DELETE RESTRICT,
  id_socio              BIGINT NOT NULL
                        REFERENCES socios(id_socio) ON DELETE RESTRICT,
  saldo_bruto           NUMERIC(14,2) NOT NULL,   -- paso 9 (matriz)
  gastos_d              NUMERIC(14,2) NOT NULL,   -- componente D (<= 0)
  gastos_e              NUMERIC(14,2) NOT NULL,   -- componente E (<= 0)
  saldo_final           NUMERIC(14,2) NOT NULL,   -- paso 11, de 9G — NO mezclar
  desembolsado_periodo  NUMERIC(14,2) NOT NULL,   -- crédito 9H, columna aparte

  PRIMARY KEY (id_liquidacion, id_socio),
  CONSTRAINT chk_socio_saldo_final_coherente
      CHECK (saldo_final = saldo_bruto + gastos_d + gastos_e),
  CONSTRAINT chk_socio_d_no_positivo          CHECK (gastos_d <= 0),
  CONSTRAINT chk_socio_e_no_positivo          CHECK (gastos_e <= 0),
  CONSTRAINT chk_socio_desembolso_no_negativo CHECK (desembolsado_periodo >= 0)
);

-- ── 4) MOVIMIENTOS_SOCIO (mayor append-only: retiros, ajustes, reversas) ─────
CREATE TABLE movimientos_socio (
  id_movimiento            BIGSERIAL PRIMARY KEY,
  id_socio                 BIGINT NOT NULL REFERENCES socios(id_socio) ON DELETE RESTRICT,
  fecha                    DATE NOT NULL,
  tipo                     TEXT NOT NULL,
  monto                    NUMERIC(14,2) NOT NULL,   -- con signo: + haber, − debe
  moneda                   TEXT NOT NULL DEFAULT 'ARS',
  periodo                  DATE,
  medio_pago               TEXT,
  comentario               TEXT,
  id_movimiento_revertido  BIGINT,                   -- FK compuesta de mismo-socio (abajo)
  creado_por               TEXT NOT NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_mov_tipo CHECK (tipo IN
      ('retiro','adelanto','ajuste_manual','retribucion_operativo','ajuste_arranque','reversa')),
  CONSTRAINT chk_mov_moneda_ars       CHECK (moneda = 'ARS'),
  CONSTRAINT chk_mov_monto_no_cero    CHECK (monto <> 0),
  CONSTRAINT chk_mov_creado_por_ne    CHECK (btrim(creado_por) <> ''),
  CONSTRAINT chk_mov_medio_ne         CHECK (medio_pago IS NULL OR btrim(medio_pago) <> ''),
  CONSTRAINT chk_mov_comentario_ne    CHECK (comentario IS NULL OR btrim(comentario) <> ''),
  CONSTRAINT chk_mov_periodo_dia1     CHECK (periodo IS NULL OR EXTRACT(DAY FROM periodo) = 1),
  CONSTRAINT chk_mov_signo_debe       CHECK (tipo NOT IN ('retiro','adelanto') OR monto < 0),
  CONSTRAINT chk_mov_retribucion_positiva CHECK (tipo <> 'retribucion_operativo' OR monto > 0),
  CONSTRAINT chk_mov_periodo_requerido CHECK (
      tipo NOT IN ('retribucion_operativo','ajuste_arranque') OR periodo IS NOT NULL),
  CONSTRAINT chk_mov_comentario_obligatorio CHECK (
      tipo NOT IN ('adelanto','ajuste_manual','retribucion_operativo','ajuste_arranque','reversa')
      OR (comentario IS NOT NULL AND btrim(comentario) <> '')),
  CONSTRAINT chk_mov_reversa_link CHECK (
      (tipo = 'reversa' AND id_movimiento_revertido IS NOT NULL)
      OR (tipo <> 'reversa' AND id_movimiento_revertido IS NULL)),
  CONSTRAINT chk_mov_no_auto_reversa CHECK (
      id_movimiento_revertido IS NULL OR id_movimiento_revertido <> id_movimiento),
  -- target de las FK compuestas de mismo-socio (D-9H-22)
  CONSTRAINT uq_mov_id_socio UNIQUE (id_movimiento, id_socio),
  -- la reversa pertenece al MISMO socio que el movimiento original (MATCH SIMPLE:
  -- si id_movimiento_revertido es NULL, no se chequea)
  CONSTRAINT fk_mov_reversa_mismo_socio
      FOREIGN KEY (id_movimiento_revertido, id_socio)
      REFERENCES movimientos_socio (id_movimiento, id_socio) ON DELETE RESTRICT
);
CREATE INDEX idx_mov_socio        ON movimientos_socio (id_socio);
CREATE INDEX idx_mov_periodo_tipo ON movimientos_socio (periodo, tipo) WHERE periodo IS NOT NULL;
-- una sola reversa por movimiento (D-9H-17)
CREATE UNIQUE INDEX uq_mov_reversa_unica
  ON movimientos_socio (id_movimiento_revertido) WHERE id_movimiento_revertido IS NOT NULL;

-- ── 5) REVALUACIONES (ARS→USD: valuación fechada; NO re-contabiliza) ─────────
CREATE TABLE revaluaciones (
  id_revaluacion     BIGSERIAL PRIMARY KEY,
  id_socio           BIGINT NOT NULL REFERENCES socios(id_socio) ON DELETE RESTRICT,
  fecha              DATE NOT NULL,
  tipo_cambio        NUMERIC(14,4) NOT NULL,   -- ARS por USD
  monto_ars          NUMERIC(14,2) NOT NULL,   -- saldo/tramo ARS valuado (NO se mueve)
  monto_usd          NUMERIC(14,2) NOT NULL,   -- = ROUND(monto_ars / tipo_cambio, 2)
  alcance            TEXT NOT NULL,            -- 'total' | 'parcial'
  id_movimiento_origen BIGINT,                 -- NULL=valuación; no-NULL=conversión (D-9H-19)
  comentario         TEXT,
  creado_por         TEXT NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_reval_tc_pos        CHECK (tipo_cambio > 0),
  CONSTRAINT chk_reval_ars_pos       CHECK (monto_ars > 0),
  CONSTRAINT chk_reval_usd_pos       CHECK (monto_usd > 0),
  CONSTRAINT chk_reval_alcance       CHECK (alcance IN ('total','parcial')),
  CONSTRAINT chk_reval_creado_por_ne CHECK (btrim(creado_por) <> ''),
  CONSTRAINT chk_reval_comentario_ne CHECK (comentario IS NULL OR btrim(comentario) <> ''),
  CONSTRAINT chk_reval_usd_coherente CHECK (monto_usd = ROUND(monto_ars / tipo_cambio, 2)),
  -- la conversión pertenece al MISMO socio que el movimiento ligado (MATCH SIMPLE:
  -- si id_movimiento_origen es NULL, no se chequea ⇒ valuación total permitida)
  CONSTRAINT fk_reval_origen_mismo_socio
      FOREIGN KEY (id_movimiento_origen, id_socio)
      REFERENCES movimientos_socio (id_movimiento, id_socio) ON DELETE RESTRICT
);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C6 — Inmutabilidad 9H — trigger y triggers
-- ══════════════════════════════════════════════════════════════════════════
-- ── C6. Inmutabilidad 9H — función de trigger + triggers anti UPDATE/DELETE/TRUNCATE ──
CREATE OR REPLACE FUNCTION public.trg_9h_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  RAISE EXCEPTION '9H append-only: % no permitido sobre % (capa inmutable, D-9H-15)',
                  TG_OP, TG_TABLE_NAME;
END
$function$
;

DO $mk_triggers$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['liquidaciones_periodo','liquidacion_cascada','liquidacion_socio',
                           'movimientos_socio','revaluaciones'] LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%s_no_upd_del BEFORE UPDATE OR DELETE ON %I '
      'FOR EACH ROW EXECUTE FUNCTION trg_9h_inmutable()', t, t);
    EXECUTE format(
      'CREATE TRIGGER trg_%s_no_truncate BEFORE TRUNCATE ON %I '
      'FOR EACH STATEMENT EXECUTE FUNCTION trg_9h_inmutable()', t, t);
  END LOOP;
END
$mk_triggers$;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C7 — Seam de titularidad (9C)
-- ══════════════════════════════════════════════════════════════════════════
-- ── C7. Seam de titularidad (9C) ──
CREATE OR REPLACE FUNCTION public.resolver_beneficiario(p_id_cabana bigint, p_fecha date)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
  -- p_fecha se ignora en el MVP (seam D-9C-18): hoy devuelve el beneficiario
  -- estable; el dia que haya titularidad por rango, se cambia SOLO este cuerpo.
  SELECT id_socio_beneficiario
  FROM cabanas
  WHERE id_cabana = p_id_cabana;
$function$
;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C8 — Matriz de participación y reparto (9E)
-- ══════════════════════════════════════════════════════════════════════════
-- ── C8. Matriz de participación y reparto (9E) ──
CREATE OR REPLACE FUNCTION public.matriz_participacion(p_periodo date)
 RETURNS TABLE(id_socio bigint, valor_socio numeric, valor_pool numeric, participacion numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH mes AS (
    SELECT daterange(
             date_trunc('month', p_periodo)::date,
             (date_trunc('month', p_periodo) + INTERVAL '1 month')::date,
             '[)'
           ) AS rango,
           date_trunc('month', p_periodo)::date AS inicio
  ),
  -- cabañas que CUBREN el mes completo (regla D-9D-06), con su beneficiario via seam
  participantes AS (
    SELECT resolver_beneficiario(c.id_cabana, m.inicio) AS id_socio,
           c.valor_relativo
    FROM activaciones_operativas a
    JOIN cabanas c ON c.id_cabana = a.id_cabana
    CROSS JOIN mes m
    WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)') @> m.rango
  ),
  por_socio AS (
    SELECT id_socio, SUM(valor_relativo) AS valor_socio
    FROM participantes
    GROUP BY id_socio
  ),
  total AS (
    SELECT SUM(valor_socio) AS valor_pool FROM por_socio
  )
  SELECT s.id_socio,
         s.valor_socio,
         t.valor_pool,
         (s.valor_socio / t.valor_pool) AS participacion
  FROM por_socio s
  CROSS JOIN total t
  WHERE t.valor_pool > 0
  ORDER BY participacion DESC, s.id_socio;
$function$
;

CREATE OR REPLACE FUNCTION public.repartir_por_matriz(p_periodo date, p_monto numeric)
 RETURNS TABLE(id_socio bigint, participacion numeric, monto_asignado numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH base AS (
    SELECT m.id_socio, m.participacion,
           ROUND(p_monto * m.participacion, 2) AS monto_base
    FROM matriz_participacion(p_periodo) m
  ),
  resid AS (
    SELECT p_monto - COALESCE(SUM(monto_base), 0) AS residual FROM base
  ),
  -- ganador del residual: mayor participacion; si Rodrigo esta en el empate, Rodrigo;
  -- si no, menor id_socio entre los de mayor participacion (D-9E-08)
  ganador AS (
    SELECT b.id_socio
    FROM base b
    JOIN socios s ON s.id_socio = b.id_socio
    ORDER BY b.participacion DESC, (s.nombre = 'Rodrigo') DESC, b.id_socio ASC
    LIMIT 1
  )
  SELECT b.id_socio,
         b.participacion,
         b.monto_base
           + CASE WHEN b.id_socio = (SELECT id_socio FROM ganador)
                  THEN (SELECT residual FROM resid) ELSE 0 END AS monto_asignado
  FROM base b
  ORDER BY b.participacion DESC, b.id_socio;
$function$
;

CREATE OR REPLACE FUNCTION public.detalle_participacion(p_periodo date)
 RETURNS TABLE(id_cabana bigint, cabana text, valor_relativo numeric, id_socio bigint, beneficiario text, participa boolean)
 LANGUAGE sql
 STABLE
AS $function$
  WITH mes AS (
    SELECT daterange(
             date_trunc('month', p_periodo)::date,
             (date_trunc('month', p_periodo) + INTERVAL '1 month')::date,
             '[)'
           ) AS rango,
           date_trunc('month', p_periodo)::date AS inicio
  )
  SELECT c.id_cabana,
         c.nombre,
         c.valor_relativo,
         resolver_beneficiario(c.id_cabana, m.inicio) AS id_socio,
         s.nombre AS beneficiario,
         EXISTS (
           SELECT 1 FROM activaciones_operativas a
           WHERE a.id_cabana = c.id_cabana
             AND daterange(a.fecha_desde, a.fecha_hasta, '[)') @> m.rango
         ) AS participa
  FROM cabanas c
  CROSS JOIN mes m
  JOIN socios s ON s.id_socio = resolver_beneficiario(c.id_cabana, m.inicio)
  ORDER BY c.id_cabana;
$function$
;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C9 — Cascada de liquidación read-only (9G)
-- ══════════════════════════════════════════════════════════════════════════
-- ── C9. Cascada de liquidación read-only (9G) ──
CREATE OR REPLACE FUNCTION public.cascada_periodo(p_periodo date, p_pct_operativo numeric)
 RETURNS TABLE(paso smallint, concepto text, id_socio bigint, socio text, monto numeric)
 LANGUAGE sql
 STABLE
AS $function$
WITH params AS (
  SELECT date_trunc('month', p_periodo)::date AS mes,
         (p_pct_operativo IS NULL
          OR p_pct_operativo < 0 OR p_pct_operativo > 1) AS pct_invalido
),
hay_pool AS (
  SELECT EXISTS (SELECT 1 FROM params pr
                 CROSS JOIN LATERAL matriz_participacion(pr.mes)) AS ok
),
ing AS (  -- caja percibida del mes (D-9G-02 / D-9G-03)
  SELECT COALESCE(SUM(p.monto_recibido) FILTER (WHERE p.tipo IN ('sena','saldo')), 0) AS p1,
         COALESCE(SUM(p.monto_recibido) FILTER (WHERE p.tipo = 'extra'), 0)           AS p6
  FROM params pr
  LEFT JOIN pagos p
    ON p.estado::text = 'confirmado'
   AND date_trunc('month', p.created_at)::date = pr.mes
),
gas AS (
  SELECT COALESCE(SUM(g.monto) FILTER (WHERE g.clase = 'A'), 0) AS ga,
         COALESCE(SUM(g.monto) FILTER (WHERE g.clase = 'C'), 0) AS gc
  FROM params pr
  LEFT JOIN gastos_internos g ON g.periodo = pr.mes
),
calc AS (  -- D-9G-06: con pool vacío, A y C no se restan (se reportan aparte)
  SELECT i.p1,
         CASE WHEN hp.ok THEN -g.ga ELSE 0 END AS p2,
         i.p1 - CASE WHEN hp.ok THEN g.ga ELSE 0 END AS p3,
         -ROUND(GREATEST(i.p1 - CASE WHEN hp.ok THEN g.ga ELSE 0 END, 0)
                * p_pct_operativo, 2) AS p4,
         i.p6,
         CASE WHEN hp.ok THEN -g.gc ELSE 0 END AS p7
  FROM ing i CROSS JOIN gas g CROSS JOIN hay_pool hp
),
calc2 AS (SELECT c.*, c.p3 + c.p4 AS p5 FROM calc c),
calc3 AS (SELECT c.*, c.p5 + c.p6 + c.p7 AS p8 FROM calc2 c),
-- incidencias E: 100% al beneficiario (seam 9C), independiente de activación
inc_e AS (
  SELECT resolver_beneficiario(g.id_cabana, pr.mes) AS id_socio, SUM(g.monto) AS monto
  FROM params pr
  JOIN gastos_internos g ON g.periodo = pr.mes AND g.clase = 'E'
  GROUP BY 1
),
-- incidencias D: zona -> cabañas ACTIVAS de la zona en el mes -> valor_relativo
-- con residual interno (D-9G-05: ROUND por cabaña; residual a mayor
-- valor_relativo, empate a menor id_cabana) -> seam -> socio
d_cab AS (
  SELECT g.id_gasto, g.monto AS monto_gasto, c.id_cabana, c.valor_relativo
  FROM params pr
  JOIN gastos_internos g ON g.periodo = pr.mes AND g.clase = 'D'
  JOIN cabana_zona cz ON cz.id_zona = g.id_zona
  JOIN cabanas c ON c.id_cabana = cz.id_cabana
  WHERE EXISTS (SELECT 1 FROM activaciones_operativas a
                 WHERE a.id_cabana = c.id_cabana
                   AND daterange(a.fecha_desde, a.fecha_hasta, '[)')
                       @> daterange(pr.mes, (pr.mes + INTERVAL '1 month')::date, '[)'))
),
d_pesos AS (
  SELECT dc.id_gasto, dc.monto_gasto, dc.id_cabana,
         ROUND(dc.monto_gasto * dc.valor_relativo
               / SUM(dc.valor_relativo) OVER (PARTITION BY dc.id_gasto), 2) AS monto_base,
         ROW_NUMBER() OVER (PARTITION BY dc.id_gasto
                            ORDER BY dc.valor_relativo DESC, dc.id_cabana ASC) AS rk
  FROM d_cab dc
),
d_resid AS (
  SELECT dp.id_gasto, MAX(dp.monto_gasto) - SUM(dp.monto_base) AS residual
  FROM d_pesos dp GROUP BY dp.id_gasto
),
d_final AS (
  SELECT dp.id_gasto, dp.id_cabana,
         dp.monto_base + CASE WHEN dp.rk = 1 THEN dr.residual ELSE 0 END AS monto_cab
  FROM d_pesos dp JOIN d_resid dr ON dr.id_gasto = dp.id_gasto
),
inc_d AS (
  SELECT resolver_beneficiario(df.id_cabana, pr.mes) AS id_socio, SUM(df.monto_cab) AS monto
  FROM d_final df CROSS JOIN params pr
  GROUP BY 1
),
inc_de AS (
  SELECT x.id_socio, SUM(x.monto) AS monto
  FROM (SELECT * FROM inc_d UNION ALL SELECT * FROM inc_e) x
  GROUP BY x.id_socio
),
p9 AS (
  SELECT r.id_socio, r.monto_asignado
  FROM calc3 c CROSS JOIN params pr
  CROSS JOIN LATERAL repartir_por_matriz(pr.mes, c.p8) r
)
-- guard explícito (D-9G-01)
SELECT 0::smallint, 'PARAMETRO_INVALIDO_PCT_OPERATIVO'::text,
       NULL::bigint, NULL::text, p_pct_operativo
FROM params pr WHERE pr.pct_invalido

UNION ALL  -- pasos 1 a 8 (agregados, id_socio NULL)
SELECT v.paso, v.concepto, NULL::bigint, NULL::text, v.monto
FROM calc3 c CROSS JOIN params pr
CROSS JOIN LATERAL (VALUES
  (1::smallint, 'ingreso_operativo_sena_saldo_confirmados', c.p1),
  (2::smallint, 'gastos_clase_A',                           c.p2),
  (3::smallint, 'base_operativa',                           c.p3),
  (4::smallint, 'retribucion_operativo_sobre_base_positiva',c.p4),
  (5::smallint, 'resultado_post_operativo',                 c.p5),
  (6::smallint, 'ingresos_extra_post_operativo',            c.p6),
  (7::smallint, 'gastos_clase_C',                           c.p7),
  (8::smallint, 'base_de_ganancia',                         c.p8)
) v(paso, concepto, monto)
WHERE NOT pr.pct_invalido

UNION ALL  -- paso 9: reparto por matriz (residual D-9E-08 dentro de repartir)
SELECT 9::smallint, 'reparto_por_matriz', p9.id_socio, s.nombre, p9.monto_asignado
FROM p9 JOIN socios s ON s.id_socio = p9.id_socio
CROSS JOIN params pr WHERE NOT pr.pct_invalido

UNION ALL  -- paso 10: incidencias D+E netas por socio (negativas)
SELECT 10::smallint, 'incidencias_clases_D_E', i.id_socio, s.nombre, -i.monto
FROM inc_de i JOIN socios s ON s.id_socio = i.id_socio
CROSS JOIN params pr WHERE NOT pr.pct_invalido

UNION ALL  -- paso 11: saldo final = paso 9 + paso 10 (universo D-9G-08)
SELECT 11::smallint, 'saldo_final_socio', u.id_socio, s.nombre,
       COALESCE(p9b.monto_asignado, 0) - COALESCE(de.monto, 0)
FROM (SELECT p9.id_socio FROM p9
      UNION SELECT inc_de.id_socio FROM inc_de) u
JOIN socios s ON s.id_socio = u.id_socio
LEFT JOIN p9 p9b ON p9b.id_socio = u.id_socio
LEFT JOIN inc_de de ON de.id_socio = u.id_socio
CROSS JOIN params pr WHERE NOT pr.pct_invalido

ORDER BY 1, 3 NULLS FIRST;
$function$
;

CREATE OR REPLACE FUNCTION public.saldo_socios_periodo(p_periodo date, p_pct_operativo numeric)
 RETURNS TABLE(id_socio bigint, socio text, saldo_bruto numeric, gastos_d numeric, gastos_e numeric, saldo_final numeric, desembolsado_periodo numeric)
 LANGUAGE sql
 STABLE
AS $function$
WITH params AS (
  SELECT date_trunc('month', p_periodo)::date AS mes,
         (p_pct_operativo IS NULL
          OR p_pct_operativo < 0 OR p_pct_operativo > 1) AS pct_invalido
),
hay_pool AS (
  SELECT EXISTS (SELECT 1 FROM params pr
                 CROSS JOIN LATERAL matriz_participacion(pr.mes)) AS ok
),
ing AS (
  SELECT COALESCE(SUM(p.monto_recibido) FILTER (WHERE p.tipo IN ('sena','saldo')), 0) AS p1,
         COALESCE(SUM(p.monto_recibido) FILTER (WHERE p.tipo = 'extra'), 0)           AS p6
  FROM params pr
  LEFT JOIN pagos p
    ON p.estado::text = 'confirmado'
   AND date_trunc('month', p.created_at)::date = pr.mes
),
gas AS (
  SELECT COALESCE(SUM(g.monto) FILTER (WHERE g.clase = 'A'), 0) AS ga,
         COALESCE(SUM(g.monto) FILTER (WHERE g.clase = 'C'), 0) AS gc
  FROM params pr
  LEFT JOIN gastos_internos g ON g.periodo = pr.mes
),
calc AS (
  SELECT (i.p1 - CASE WHEN hp.ok THEN g.ga ELSE 0 END)
         - ROUND(GREATEST(i.p1 - CASE WHEN hp.ok THEN g.ga ELSE 0 END, 0)
                 * p_pct_operativo, 2)
         + i.p6
         - CASE WHEN hp.ok THEN g.gc ELSE 0 END AS p8
  FROM ing i CROSS JOIN gas g CROSS JOIN hay_pool hp
),
inc_e AS (
  SELECT resolver_beneficiario(g.id_cabana, pr.mes) AS id_socio, SUM(g.monto) AS monto
  FROM params pr
  JOIN gastos_internos g ON g.periodo = pr.mes AND g.clase = 'E'
  GROUP BY 1
),
d_cab AS (
  SELECT g.id_gasto, g.monto AS monto_gasto, c.id_cabana, c.valor_relativo
  FROM params pr
  JOIN gastos_internos g ON g.periodo = pr.mes AND g.clase = 'D'
  JOIN cabana_zona cz ON cz.id_zona = g.id_zona
  JOIN cabanas c ON c.id_cabana = cz.id_cabana
  WHERE EXISTS (SELECT 1 FROM activaciones_operativas a
                 WHERE a.id_cabana = c.id_cabana
                   AND daterange(a.fecha_desde, a.fecha_hasta, '[)')
                       @> daterange(pr.mes, (pr.mes + INTERVAL '1 month')::date, '[)'))
),
d_pesos AS (
  SELECT dc.id_gasto, dc.monto_gasto, dc.id_cabana,
         ROUND(dc.monto_gasto * dc.valor_relativo
               / SUM(dc.valor_relativo) OVER (PARTITION BY dc.id_gasto), 2) AS monto_base,
         ROW_NUMBER() OVER (PARTITION BY dc.id_gasto
                            ORDER BY dc.valor_relativo DESC, dc.id_cabana ASC) AS rk
  FROM d_cab dc
),
d_resid AS (
  SELECT dp.id_gasto, MAX(dp.monto_gasto) - SUM(dp.monto_base) AS residual
  FROM d_pesos dp GROUP BY dp.id_gasto
),
d_final AS (
  SELECT dp.id_gasto, dp.id_cabana,
         dp.monto_base + CASE WHEN dp.rk = 1 THEN dr.residual ELSE 0 END AS monto_cab
  FROM d_pesos dp JOIN d_resid dr ON dr.id_gasto = dp.id_gasto
),
inc_d AS (
  SELECT resolver_beneficiario(df.id_cabana, pr.mes) AS id_socio, SUM(df.monto_cab) AS monto
  FROM d_final df CROSS JOIN params pr
  GROUP BY 1
),
p9 AS (
  SELECT r.id_socio, r.monto_asignado
  FROM calc c CROSS JOIN params pr
  CROSS JOIN LATERAL repartir_por_matriz(pr.mes, c.p8) r
),
universo AS (
  SELECT p9.id_socio FROM p9
  UNION SELECT inc_d.id_socio FROM inc_d
  UNION SELECT inc_e.id_socio FROM inc_e
)
SELECT NULL::bigint, 'PARAMETRO_INVALIDO_PCT_OPERATIVO'::text,
       NULL::numeric, NULL::numeric, NULL::numeric, NULL::numeric, NULL::numeric
FROM params pr WHERE pr.pct_invalido

UNION ALL
SELECT u.id_socio, s.nombre,
       COALESCE(p9b.monto_asignado, 0)                AS saldo_bruto,
       -COALESCE(d.monto, 0)                          AS gastos_d,
       -COALESCE(e.monto, 0)                          AS gastos_e,
       COALESCE(p9b.monto_asignado, 0)
         - COALESCE(d.monto, 0) - COALESCE(e.monto, 0) AS saldo_final,
       COALESCE((SELECT SUM(g.monto) FROM gastos_internos g CROSS JOIN params pr2
                  WHERE g.periodo = pr2.mes
                    AND g.pagador_tipo = 'socio'
                    AND g.id_socio_pagador = u.id_socio), 0) AS desembolsado_periodo
FROM universo u
JOIN socios s ON s.id_socio = u.id_socio
LEFT JOIN p9 p9b ON p9b.id_socio = u.id_socio
LEFT JOIN inc_d d ON d.id_socio = u.id_socio
LEFT JOIN inc_e e ON e.id_socio = u.id_socio
CROSS JOIN params pr WHERE NOT pr.pct_invalido

ORDER BY 1 NULLS FIRST;
$function$
;

CREATE OR REPLACE FUNCTION public.incidencia_gasto(p_id_gasto bigint)
 RETURNS TABLE(destino text, id_socio bigint, socio text, monto numeric, regla text)
 LANGUAGE sql
 STABLE
AS $function$
WITH g AS (
  SELECT gi.id_gasto, gi.clase, gi.periodo, gi.monto, gi.id_zona, gi.id_cabana
  FROM gastos_internos gi WHERE gi.id_gasto = p_id_gasto
),
hay_pool AS (
  SELECT EXISTS (SELECT 1 FROM g
                 CROSS JOIN LATERAL matriz_participacion(g.periodo)) AS ok
),
d_cab AS (
  SELECT g.monto AS monto_gasto, c.id_cabana, c.valor_relativo, g.periodo
  FROM g
  JOIN cabana_zona cz ON cz.id_zona = g.id_zona
  JOIN cabanas c ON c.id_cabana = cz.id_cabana
  WHERE g.clase = 'D'
    AND EXISTS (SELECT 1 FROM activaciones_operativas a
                 WHERE a.id_cabana = c.id_cabana
                   AND daterange(a.fecha_desde, a.fecha_hasta, '[)')
                       @> daterange(g.periodo, (g.periodo + INTERVAL '1 month')::date, '[)'))
),
d_pesos AS (
  SELECT dc.monto_gasto, dc.id_cabana, dc.periodo,
         ROUND(dc.monto_gasto * dc.valor_relativo
               / SUM(dc.valor_relativo) OVER (), 2) AS monto_base,
         ROW_NUMBER() OVER (ORDER BY dc.valor_relativo DESC, dc.id_cabana ASC) AS rk
  FROM d_cab dc
),
d_final AS (
  SELECT dp.id_cabana, dp.periodo,
         dp.monto_base
           + CASE WHEN dp.rk = 1
                  THEN (SELECT MAX(x.monto_gasto) - SUM(x.monto_base) FROM d_pesos x)
                  ELSE 0 END AS monto_cab
  FROM d_pesos dp
)
-- A: estructural, una fila al pool pre-operativo (solo si hay pool)
SELECT 'pool_pre_operativo'::text, NULL::bigint, NULL::text, g.monto,
       'clase A: entra al pool antes del % operativo; absorción efectiva '
       || 'operativo/beneficiarios depende del período completo (GREATEST paso 4); '
       || 'ver cascada_periodo'::text
FROM g CROSS JOIN hay_pool hp
WHERE g.clase = 'A' AND hp.ok

UNION ALL  -- C: exacto por matriz del período (§4.2)
SELECT 'socio'::text, r.id_socio, s.nombre, r.monto_asignado,
       'clase C: equivalente a deduccion post-matriz (§4.2); reparto exacto '
       || 'por matriz del período (residual D-9E-08)'::text
FROM g
CROSS JOIN LATERAL repartir_por_matriz(g.periodo, g.monto) r
JOIN socios s ON s.id_socio = r.id_socio
WHERE g.clase = 'C'

UNION ALL  -- D: zona -> activas -> valor_relativo -> seam
SELECT 'socio'::text, resolver_beneficiario(df.id_cabana, df.periodo), s.nombre,
       SUM(df.monto_cab),
       'clase D: zona repartida entre cabañas activas del período por '
       || 'valor_relativo (residual D-9G-05) hacia el beneficiario (seam 9C)'::text
FROM d_final df
JOIN socios s ON s.id_socio = resolver_beneficiario(df.id_cabana, df.periodo)
GROUP BY resolver_beneficiario(df.id_cabana, df.periodo), s.nombre

UNION ALL  -- E: 100% al beneficiario de la cabaña
SELECT 'socio'::text, resolver_beneficiario(g.id_cabana, g.periodo), s.nombre, g.monto,
       'clase E: 100% al beneficiario de la cabaña (seam 9C), '
       || 'independiente de la activación'::text
FROM g
JOIN socios s ON s.id_socio = resolver_beneficiario(g.id_cabana, g.periodo)
WHERE g.clase = 'E'

ORDER BY 2 NULLS FIRST;
$function$
;

CREATE OR REPLACE FUNCTION public.reporte_overrides_periodo(p_periodo date)
 RETURNS TABLE(id_gasto bigint, clase text, clase_sugerida text, etiqueta text, monto numeric, comentario text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT g.id_gasto, g.clase, g.clase_sugerida, g.etiqueta, g.monto, g.comentario
  FROM gastos_internos g
  WHERE g.periodo = date_trunc('month', p_periodo)::date
    AND g.clase IS DISTINCT FROM g.clase_sugerida
  ORDER BY g.id_gasto;
$function$
;

CREATE OR REPLACE FUNCTION public.reporte_5_vs_fiscal_periodo(p_periodo date)
 RETURNS TABLE(periodo date, total_extra_confirmado numeric, total_fiscal_monotributo numeric, diferencia numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH params AS (SELECT date_trunc('month', p_periodo)::date AS mes)
  SELECT pr.mes,
         COALESCE((SELECT SUM(p.monto_recibido) FROM pagos p
                    WHERE p.tipo = 'extra' AND p.estado::text = 'confirmado'
                      AND date_trunc('month', p.created_at)::date = pr.mes), 0),
         COALESCE((SELECT SUM(g.monto) FROM gastos_internos g
                    WHERE g.periodo = pr.mes
                      AND lower(btrim(g.etiqueta)) = 'monotributo'), 0),
         COALESCE((SELECT SUM(p.monto_recibido) FROM pagos p
                    WHERE p.tipo = 'extra' AND p.estado::text = 'confirmado'
                      AND date_trunc('month', p.created_at)::date = pr.mes), 0)
         - COALESCE((SELECT SUM(g.monto) FROM gastos_internos g
                      WHERE g.periodo = pr.mes
                        AND lower(btrim(g.etiqueta)) = 'monotributo'), 0)
  FROM params pr;
$function$
;

CREATE OR REPLACE FUNCTION public.gastos_sin_incidencia_periodo(p_periodo date)
 RETURNS TABLE(id_gasto bigint, clase text, etiqueta text, monto numeric, motivo text)
 LANGUAGE sql
 STABLE
AS $function$
  WITH params AS (SELECT date_trunc('month', p_periodo)::date AS mes)
  SELECT g.id_gasto, g.clase, g.etiqueta, g.monto, 'pool_vacio'::text
  FROM gastos_internos g CROSS JOIN params pr
  WHERE g.periodo = pr.mes AND g.clase IN ('A','C')
    AND NOT EXISTS (SELECT 1 FROM matriz_participacion(pr.mes))

  UNION ALL
  SELECT g.id_gasto, g.clase, g.etiqueta, g.monto, 'zona_sin_activas'::text
  FROM gastos_internos g CROSS JOIN params pr
  WHERE g.periodo = pr.mes AND g.clase = 'D'
    AND NOT EXISTS (
      SELECT 1
      FROM cabana_zona cz
      JOIN activaciones_operativas a ON a.id_cabana = cz.id_cabana
      WHERE cz.id_zona = g.id_zona
        AND daterange(a.fecha_desde, a.fecha_hasta, '[)')
            @> daterange(pr.mes, (pr.mes + INTERVAL '1 month')::date, '[)'))

  ORDER BY 1;
$function$
;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C10 — Cuenta corriente 9H — funciones
-- ══════════════════════════════════════════════════════════════════════════
-- ── C10. Cuenta corriente 9H — funciones (4 lectura + 5 escritura append-only) ──
CREATE OR REPLACE FUNCTION public.liquidacion_vigente(p_periodo date)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
  SELECT lp.id_liquidacion
  FROM liquidaciones_periodo lp
  WHERE lp.periodo = date_trunc('month', p_periodo)::date
    AND NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s
                    WHERE s.id_liquidacion_supersede = lp.id_liquidacion);
$function$
;

CREATE OR REPLACE FUNCTION public.saldo_corriente_socio(p_id_socio bigint)
 RETURNS TABLE(orden smallint, componente text, monto numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH vig AS (
    SELECT lp.id_liquidacion FROM liquidaciones_periodo lp
    WHERE NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s WHERE s.id_liquidacion_supersede = lp.id_liquidacion)
  ),
  liq AS (
    SELECT COALESCE(SUM(ls.saldo_final),0)          AS res,
           COALESCE(SUM(ls.desembolsado_periodo),0) AS reemb
    FROM liquidacion_socio ls JOIN vig ON vig.id_liquidacion = ls.id_liquidacion
    WHERE ls.id_socio = p_id_socio
  ),
  mov AS (SELECT COALESCE(SUM(monto),0) AS m FROM movimientos_socio WHERE id_socio = p_id_socio)
  SELECT 1::smallint,'resultado_liquidacion', (SELECT res FROM liq)
  UNION ALL SELECT 2,'reembolso_desembolso',  (SELECT reemb FROM liq)
  UNION ALL SELECT 3,'movimientos',           (SELECT m FROM mov)
  UNION ALL SELECT 4,'saldo_vivo',            (SELECT res+reemb FROM liq) + (SELECT m FROM mov);
$function$
;

CREATE OR REPLACE FUNCTION public.mayor_socio(p_id_socio bigint)
 RETURNS TABLE(fecha date, tipo text, referencia text, monto numeric, saldo_acumulado numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH vig AS (
    SELECT lp.id_liquidacion, lp.periodo FROM liquidaciones_periodo lp
    WHERE NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s WHERE s.id_liquidacion_supersede = lp.id_liquidacion)
  ),
  asientos AS (
    SELECT v.periodo AS fecha, 'liquidacion'::text AS tipo, 'liq#'||ls.id_liquidacion AS referencia,
           ls.saldo_final AS monto, 1 AS sub
    FROM liquidacion_socio ls JOIN vig v ON v.id_liquidacion = ls.id_liquidacion
    WHERE ls.id_socio = p_id_socio
    UNION ALL
    SELECT v.periodo, 'reembolso_desembolso', 'liq#'||ls.id_liquidacion, ls.desembolsado_periodo, 2
    FROM liquidacion_socio ls JOIN vig v ON v.id_liquidacion = ls.id_liquidacion
    WHERE ls.id_socio = p_id_socio AND ls.desembolsado_periodo <> 0
    UNION ALL
    SELECT m.fecha, m.tipo, 'mov#'||m.id_movimiento, m.monto, 3
    FROM movimientos_socio m WHERE m.id_socio = p_id_socio
  )
  SELECT fecha, tipo, referencia, monto,
         SUM(monto) OVER (ORDER BY fecha, sub, referencia ROWS UNBOUNDED PRECEDING) AS saldo_acumulado
  FROM asientos
  ORDER BY fecha, sub, referencia;
$function$
;

CREATE OR REPLACE FUNCTION public.reporte_retribucion_operativo_periodo(p_periodo date)
 RETURNS TABLE(periodo date, calculado numeric, asignado numeric, diferencia numeric, estado text)
 LANGUAGE sql
 STABLE
AS $function$
  WITH per AS (SELECT date_trunc('month', p_periodo)::date AS p),
  calc AS (  -- paso 4 está negativo (deducción); lo a asignar es su magnitud
    SELECT COALESCE(-(SELECT lc.monto FROM liquidacion_cascada lc
                      WHERE lc.id_liquidacion = liquidacion_vigente((SELECT p FROM per)) AND lc.paso = 4), 0) AS m
  ),
  asig AS (  -- neto: asignaciones del período + reversas de esas asignaciones
    SELECT COALESCE(SUM(eff.monto),0) AS m FROM (
      SELECT mo.monto FROM movimientos_socio mo
        WHERE mo.tipo='retribucion_operativo' AND mo.periodo = (SELECT p FROM per)
      UNION ALL
      SELECT r.monto FROM movimientos_socio r JOIN movimientos_socio o ON o.id_movimiento = r.id_movimiento_revertido
        WHERE r.tipo='reversa' AND o.tipo='retribucion_operativo' AND o.periodo = (SELECT p FROM per)
    ) eff
  )
  SELECT (SELECT p FROM per), (SELECT m FROM calc), (SELECT m FROM asig),
         (SELECT m FROM calc) - (SELECT m FROM asig),
         CASE WHEN (SELECT m FROM calc) = 0 THEN 'SIN_CALCULADO'
              WHEN (SELECT m FROM asig) = 0 THEN 'PENDIENTE'
              WHEN (SELECT m FROM calc) = (SELECT m FROM asig) THEN 'CONCILIADO'
              WHEN (SELECT m FROM asig) < (SELECT m FROM calc) THEN 'PARCIAL'
              ELSE 'EXCEDIDO' END;
$function$
;

CREATE OR REPLACE FUNCTION public.registrar_snapshot_periodo(p_periodo date, p_pct numeric, p_creado_por text, p_supersede_id bigint DEFAULT NULL::bigint, p_comentario text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_periodo DATE := date_trunc('month', p_periodo)::date;
        v_cola BIGINT; v_id BIGINT; v_n_cascada INTEGER; v_n_socios INTEGER; v_socios_total INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(919001, hashtext(v_periodo::text));  -- lock por período
  IF p_pct IS NULL OR p_pct < 0 OR p_pct > 1 THEN
    RAISE EXCEPTION '9H snapshot: pct_operativo invalido (% fuera de [0,1])', p_pct;
  END IF;
  IF p_pct <> ROUND(p_pct, 4) THEN                                       -- D-9H-36
    RAISE EXCEPTION '9H snapshot: pct_operativo excede 4 decimales (%)', p_pct;
  END IF;
  v_cola := liquidacion_vigente(v_periodo);
  IF v_cola IS NULL THEN
    IF p_supersede_id IS NOT NULL THEN
      RAISE EXCEPTION '9H snapshot: el período % no tiene foto vigente; p_supersede_id debe ser NULL', v_periodo;
    END IF;
  ELSE
    IF p_supersede_id IS NULL OR p_supersede_id <> v_cola THEN
      RAISE EXCEPTION '9H snapshot: el período % ya tiene foto vigente (id=%); para re-snapshot pasar p_supersede_id=% (la cola actual)', v_periodo, v_cola, v_cola;
    END IF;
    IF p_comentario IS NULL OR btrim(p_comentario) = '' THEN
      RAISE EXCEPTION '9H snapshot: re-snapshot exige comentario (D-9H-24)';
    END IF;
  END IF;

  INSERT INTO liquidaciones_periodo (periodo, pct_operativo, id_liquidacion_supersede, creado_por, comentario)
  VALUES (v_periodo, p_pct, p_supersede_id, p_creado_por, p_comentario)
  RETURNING id_liquidacion INTO v_id;

  INSERT INTO liquidacion_cascada (id_liquidacion, paso, concepto, monto)
  SELECT v_id, paso, concepto, monto FROM cascada_periodo(v_periodo, p_pct)
  WHERE paso BETWEEN 1 AND 8;  -- excluye el guard paso=0
  GET DIAGNOSTICS v_n_cascada = ROW_COUNT;                              -- D-9H-35
  IF v_n_cascada <> 8 THEN
    RAISE EXCEPTION '9H snapshot: cascada incompleta para % (% pasos insertados, esperados 8)', v_periodo, v_n_cascada;
  END IF;

  INSERT INTO liquidacion_socio (id_liquidacion, id_socio, saldo_bruto, gastos_d, gastos_e, saldo_final, desembolsado_periodo)
  SELECT v_id, id_socio, saldo_bruto, gastos_d, gastos_e, saldo_final, desembolsado_periodo
  FROM saldo_socios_periodo(v_periodo, p_pct)
  WHERE id_socio IS NOT NULL;  -- junio: 0 filas, permitido (D-9H-27)
  GET DIAGNOSTICS v_n_socios = ROW_COUNT;                               -- D-9H-37
  SELECT COUNT(*) INTO v_socios_total FROM socios;
  IF v_n_socios <> 0 AND v_n_socios <> v_socios_total THEN
    RAISE EXCEPTION '9H snapshot: liquidacion_socio incompleta para % (% filas, esperadas 0 o %)',
      v_periodo, v_n_socios, v_socios_total;
  END IF;

  RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION public.registrar_retiro(p_id_socio bigint, p_fecha date, p_monto numeric, p_medio_pago text, p_creado_por text, p_comentario text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_saldo NUMERIC; v_id BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(919002, p_id_socio::int);  -- lock por socio
  IF p_monto IS NULL OR p_monto <= 0 THEN
    RAISE EXCEPTION '9H retiro: monto debe ser positivo (magnitud a retirar)';
  END IF;
  IF p_monto <> ROUND(p_monto, 2) THEN                                   -- D-9H-36
    RAISE EXCEPTION '9H retiro: monto excede 2 decimales (%)', p_monto;
  END IF;
  v_saldo := (
    SELECT COALESCE(SUM(ls.saldo_final + ls.desembolsado_periodo),0)
    FROM liquidacion_socio ls JOIN liquidaciones_periodo lp ON lp.id_liquidacion = ls.id_liquidacion
    WHERE ls.id_socio = p_id_socio
      AND NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s WHERE s.id_liquidacion_supersede = lp.id_liquidacion)
  ) + (SELECT COALESCE(SUM(monto),0) FROM movimientos_socio WHERE id_socio = p_id_socio);
  IF v_saldo - p_monto < 0 THEN
    RAISE EXCEPTION '9H retiro: saldo insuficiente (vivo=%, retiro=%). Usar adelanto/ajuste_manual para saldo negativo', v_saldo, p_monto;
  END IF;
  INSERT INTO movimientos_socio (id_socio, fecha, tipo, monto, medio_pago, comentario, creado_por)
  VALUES (p_id_socio, p_fecha, 'retiro', -p_monto, p_medio_pago, p_comentario, p_creado_por)
  RETURNING id_movimiento INTO v_id;
  RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION public.registrar_movimiento_manual(p_id_socio bigint, p_fecha date, p_tipo text, p_monto numeric, p_creado_por text, p_comentario text, p_periodo date DEFAULT NULL::date, p_medio_pago text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_id BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(919002, p_id_socio::int);
  IF p_tipo NOT IN ('adelanto','ajuste_manual','retribucion_operativo','ajuste_arranque') THEN
    RAISE EXCEPTION '9H mov manual: tipo % no permitido aquí (retiro/reversa tienen función propia)', p_tipo;
  END IF;
  IF p_monto <> ROUND(p_monto, 2) THEN                                   -- D-9H-36
    RAISE EXCEPTION '9H mov manual: monto excede 2 decimales (%)', p_monto;
  END IF;
  INSERT INTO movimientos_socio (id_socio, fecha, tipo, monto, periodo, medio_pago, comentario, creado_por)
  VALUES (p_id_socio, p_fecha, p_tipo, p_monto,
          CASE WHEN p_periodo IS NULL THEN NULL ELSE date_trunc('month',p_periodo)::date END,
          p_medio_pago, p_comentario, p_creado_por)
  RETURNING id_movimiento INTO v_id;
  RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION public.registrar_reversa(p_id_movimiento_revertido bigint, p_fecha date, p_creado_por text, p_comentario text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_socio BIGINT; v_monto NUMERIC; v_id BIGINT;
BEGIN
  SELECT id_socio, monto INTO v_socio, v_monto FROM movimientos_socio WHERE id_movimiento = p_id_movimiento_revertido;
  IF NOT FOUND THEN
    RAISE EXCEPTION '9H reversa: movimiento original % inexistente', p_id_movimiento_revertido;
  END IF;
  PERFORM pg_advisory_xact_lock(919002, v_socio::int);  -- lock por socio del original
  INSERT INTO movimientos_socio (id_socio, fecha, tipo, monto, comentario, creado_por, id_movimiento_revertido)
  VALUES (v_socio, p_fecha, 'reversa', -v_monto, p_comentario, p_creado_por, p_id_movimiento_revertido)
  RETURNING id_movimiento INTO v_id;
  RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION public.registrar_revaluacion(p_id_socio bigint, p_fecha date, p_tipo_cambio numeric, p_monto_ars numeric, p_alcance text, p_creado_por text, p_id_movimiento_origen bigint DEFAULT NULL::bigint, p_comentario text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_usd NUMERIC; v_tope NUMERIC; v_convertido NUMERIC; v_id BIGINT; v_tipo_origen TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(919002, p_id_socio::int);
  IF p_tipo_cambio IS NULL OR p_tipo_cambio <= 0 THEN RAISE EXCEPTION '9H reval: tipo_cambio debe ser > 0'; END IF;
  IF p_monto_ars   IS NULL OR p_monto_ars   <= 0 THEN RAISE EXCEPTION '9H reval: monto_ars debe ser > 0'; END IF;
  IF p_alcance NOT IN ('total','parcial') THEN RAISE EXCEPTION '9H reval: alcance invalido (%)', p_alcance; END IF;
  IF p_monto_ars <> ROUND(p_monto_ars, 2) THEN                           -- D-9H-36
    RAISE EXCEPTION '9H reval: monto_ars excede 2 decimales (%)', p_monto_ars;
  END IF;
  p_tipo_cambio := ROUND(p_tipo_cambio, 4);  -- D-9H-36: redondeo explícito; alinea con NUMERIC(14,4) y el CHECK USD

  IF p_id_movimiento_origen IS NOT NULL THEN  -- conversión ligada (D-9H-29/34)
    SELECT tipo, ABS(monto) INTO v_tipo_origen, v_tope FROM movimientos_socio
      WHERE id_movimiento = p_id_movimiento_origen AND id_socio = p_id_socio;
    IF NOT FOUND THEN
      RAISE EXCEPTION '9H reval: movimiento origen % no pertenece al socio % (o no existe)', p_id_movimiento_origen, p_id_socio;
    END IF;
    IF v_tipo_origen NOT IN ('retiro','adelanto') THEN                   -- D-9H-34
      RAISE EXCEPTION '9H reval: conversión solo se liga a retiro/adelanto (origen % es %)', p_id_movimiento_origen, v_tipo_origen;
    END IF;
    v_convertido := (SELECT COALESCE(SUM(monto_ars),0) FROM revaluaciones WHERE id_movimiento_origen = p_id_movimiento_origen);
    IF v_convertido + p_monto_ars > v_tope THEN
      RAISE EXCEPTION '9H reval: conversión excede el movimiento (ya convertido=%, nuevo=%, tope=%)', v_convertido, p_monto_ars, v_tope;
    END IF;
  END IF;

  v_usd := ROUND(p_monto_ars / p_tipo_cambio, 2);  -- D-9H-33: interno, no input
  INSERT INTO revaluaciones (id_socio, fecha, tipo_cambio, monto_ars, monto_usd, alcance, id_movimiento_origen, comentario, creado_por)
  VALUES (p_id_socio, p_fecha, p_tipo_cambio, p_monto_ars, v_usd, p_alcance, p_id_movimiento_origen, p_comentario, p_creado_por)
  RETURNING id_revaluacion INTO v_id;
  RETURN v_id;
END $function$
;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C11 — Helper de cobranza atómica (9B)
-- ══════════════════════════════════════════════════════════════════════════
-- ── C11. Helper de cobranza atómica (9B, D-9B-19) ──
CREATE OR REPLACE FUNCTION public.abortar_si_falla(resultado jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF (resultado->>'ok')::BOOLEAN IS TRUE
     AND resultado->>'estado' = 'confirmado'
     AND (resultado->>'warning') IS NULL
  THEN
    RETURN resultado;
  END IF;
  RAISE EXCEPTION 'cobranza_revertida: pago no confirmado (ok=%, estado=%, error=%, warning=%)',
    COALESCE(resultado->>'ok',      'null'),
    COALESCE(resultado->>'estado',  'null'),
    COALESCE(resultado->>'error',   'sin_error'),
    COALESCE(resultado->>'warning', 'sin_warning')
    USING ERRCODE = 'P0001';
END;
$function$
;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C12 — Hardening — REVOKE
-- ══════════════════════════════════════════════════════════════════════════
-- ── C12. Hardening — REVOKE total a PUBLIC/anon/authenticated/service_role ──
-- Tablas (9):
REVOKE ALL ON TABLE public.zonas, public.cabana_zona, public.activaciones_operativas,
                    public.gastos_internos, public.liquidaciones_periodo,
                    public.liquidacion_cascada, public.liquidacion_socio,
                    public.movimientos_socio, public.revaluaciones
  FROM PUBLIC, anon, authenticated, service_role;
-- Secuencias (6):
REVOKE ALL ON SEQUENCE public.zonas_id_zona_seq,
                       public.activaciones_operativas_id_activacion_seq,
                       public.gastos_internos_id_gasto_seq,
                       public.liquidaciones_periodo_id_liquidacion_seq,
                       public.movimientos_socio_id_movimiento_seq,
                       public.revaluaciones_id_revaluacion_seq
  FROM PUBLIC, anon, authenticated, service_role;
-- Funciones (21, incluye trg_9h_inmutable y abortar_si_falla):
REVOKE EXECUTE ON FUNCTION public.abortar_si_falla(resultado jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.cascada_periodo(p_periodo date, p_pct_operativo numeric) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.detalle_participacion(p_periodo date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.gastos_sin_incidencia_periodo(p_periodo date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.incidencia_gasto(p_id_gasto bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.liquidacion_vigente(p_periodo date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.matriz_participacion(p_periodo date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.mayor_socio(p_id_socio bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.registrar_movimiento_manual(p_id_socio bigint, p_fecha date, p_tipo text, p_monto numeric, p_creado_por text, p_comentario text, p_periodo date, p_medio_pago text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.registrar_retiro(p_id_socio bigint, p_fecha date, p_monto numeric, p_medio_pago text, p_creado_por text, p_comentario text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.registrar_revaluacion(p_id_socio bigint, p_fecha date, p_tipo_cambio numeric, p_monto_ars numeric, p_alcance text, p_creado_por text, p_id_movimiento_origen bigint, p_comentario text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.registrar_reversa(p_id_movimiento_revertido bigint, p_fecha date, p_creado_por text, p_comentario text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.registrar_snapshot_periodo(p_periodo date, p_pct numeric, p_creado_por text, p_supersede_id bigint, p_comentario text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.repartir_por_matriz(p_periodo date, p_monto numeric) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.reporte_5_vs_fiscal_periodo(p_periodo date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.reporte_overrides_periodo(p_periodo date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.reporte_retribucion_operativo_periodo(p_periodo date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.resolver_beneficiario(p_id_cabana bigint, p_fecha date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.saldo_corriente_socio(p_id_socio bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.saldo_socios_periodo(p_periodo date, p_pct_operativo numeric) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.trg_9h_inmutable() FROM PUBLIC, anon, authenticated, service_role;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C13 — Seeds estructurales reales
-- ══════════════════════════════════════════════════════════════════════════
-- ── C13. Seeds estructurales reales (por nombre; NO datos operativos) ──
-- C13.1 Marcador de entorno (seed de BOOTSTRAP para DEV nuevo; cada entorno setea el suyo: dev/test/ops)
INSERT INTO configuracion_general (clave, valor, descripcion, categoria, editable)
VALUES ('ambiente', 'dev',
        'Marcador de entorno para identidad de Carril B. Valor por-entorno: dev/test/ops. Default dev para bootstrap del canónico.', 'infra', FALSE)
ON CONFLICT (clave) DO NOTHING;

-- C13.2 Zonas (estructural: grandes/chicas)
INSERT INTO zonas (nombre, descripcion) VALUES
  ('grandes', 'Zona de cabañas grandes (seed MVP Carril B)'),
  ('chicas',  'Zona de cabañas chicas (seed MVP Carril B)')
ON CONFLICT (nombre) DO NOTHING;

-- C13.3 Beneficiarios + valor_relativo (backfill POR NOMBRE de cabaña y socio)
UPDATE cabanas c
SET valor_relativo = v.valrel, id_socio_beneficiario = s.id_socio
FROM (VALUES
    ('Arrebol',100,'Franco'),('Madre Selva',100,'Rodrigo'),('Bamboo',100,'Remo'),
    ('Guatemala',78,'Franco'),('Tokio',78,'Remo')
) AS v(cab_nombre, valrel, socio_nombre)
JOIN socios s ON s.nombre = v.socio_nombre
WHERE c.nombre = v.cab_nombre;

-- C13.4 NOT NULL en cabanas (recién acá: requiere backfill previo de C13.3)
ALTER TABLE cabanas ALTER COLUMN valor_relativo        SET NOT NULL;
ALTER TABLE cabanas ALTER COLUMN id_socio_beneficiario SET NOT NULL;

-- C13.5 Pertenencias cabana_zona (POR NOMBRE)
INSERT INTO cabana_zona (id_cabana, id_zona)
SELECT c.id_cabana, z.id_zona
FROM (VALUES
    ('Arrebol','grandes'),('Madre Selva','grandes'),('Bamboo','grandes'),
    ('Guatemala','chicas'),('Tokio','chicas')
) AS m(cab_nombre, zona_nombre)
JOIN cabanas c ON c.nombre = m.cab_nombre
JOIN zonas   z ON z.nombre = m.zona_nombre
ON CONFLICT (id_cabana, id_zona) DO NOTHING;

-- C13.6 Pool de activaciones (D-9D-10; abiertas, fecha_hasta NULL)
INSERT INTO activaciones_operativas (id_cabana, fecha_desde, fecha_hasta, creado_por, comentario)
SELECT c.id_cabana, v.desde, NULL, 'seed_canonico', v.coment
FROM (VALUES
    ('Bamboo',      DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Madre Selva', DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Arrebol',     DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Tokio',       DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Guatemala',   DATE '2026-11-01', 'Desactivada jul-oct 2026 inclusive; activa desde nov (D-9D-10)')
) AS v(cab_nombre, desde, coment)
JOIN cabanas c ON c.nombre = v.cab_nombre
WHERE NOT EXISTS (SELECT 1 FROM activaciones_operativas a WHERE a.id_cabana = c.id_cabana);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE C14 — Verificación de seeds y consistencia
-- ══════════════════════════════════════════════════════════════════════════
-- ── C14. Verificación de seeds y consistencia (asserts; no modifica) ──
DO $verif_carril_b$
DECLARE
  v_zonas int; v_cabzona int; v_nulls int; v_activ int;
  v_seam_match int; v_seam_total int; v_jul numeric; v_nov numeric; v_reparto numeric;
  v_exec_abiertos int; v_tab_grants int; v_seq_grants int;
BEGIN
  SELECT count(*) INTO v_zonas FROM zonas;
  IF v_zonas <> 2 THEN RAISE EXCEPTION 'C14 zonas=% (esperado 2)', v_zonas; END IF;
  SELECT count(*) INTO v_cabzona FROM cabana_zona;
  IF v_cabzona <> 5 THEN RAISE EXCEPTION 'C14 cabana_zona=% (esperado 5)', v_cabzona; END IF;
  SELECT count(*) INTO v_nulls FROM cabanas WHERE valor_relativo IS NULL OR id_socio_beneficiario IS NULL;
  IF v_nulls <> 0 THEN RAISE EXCEPTION 'C14 cabanas con beneficiario/valor NULL=% (esperado 0)', v_nulls; END IF;
  SELECT count(*) INTO v_activ FROM activaciones_operativas;
  IF v_activ <> 5 THEN RAISE EXCEPTION 'C14 activaciones=% (esperado 5)', v_activ; END IF;

  SELECT count(*) INTO v_seam_match FROM cabanas c WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01') = c.id_socio_beneficiario;
  SELECT count(*) INTO v_seam_total FROM cabanas;
  IF v_seam_match <> v_seam_total OR v_seam_total <> 5 THEN RAISE EXCEPTION 'C14 seam=%/% (esperado 5/5)', v_seam_match, v_seam_total; END IF;

  SELECT max(valor_pool) INTO v_jul FROM matriz_participacion(DATE '2026-07-01');
  IF v_jul IS DISTINCT FROM 378.00 THEN RAISE EXCEPTION 'C14 matriz julio pool=% (esperado 378.00)', v_jul; END IF;
  SELECT max(valor_pool) INTO v_nov FROM matriz_participacion(DATE '2026-11-01');
  IF v_nov IS DISTINCT FROM 456.00 THEN RAISE EXCEPTION 'C14 matriz noviembre pool=% (esperado 456.00)', v_nov; END IF;

  SELECT sum(monto_asignado) INTO v_reparto FROM repartir_por_matriz(DATE '2026-07-01', 100000);
  IF v_reparto IS DISTINCT FROM 100000.00 THEN RAISE EXCEPTION 'C14 reparto Σ=% (esperado 100000.00)', v_reparto; END IF;

  -- Hardening: 0 exposición a PUBLIC/Data API en tablas, secuencias y funciones del Carril B
  SELECT count(*) INTO v_tab_grants FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) a
    WHERE n.nspname='public' AND c.relkind='r'
      AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos','liquidaciones_periodo','liquidacion_cascada','liquidacion_socio','movimientos_socio','revaluaciones')
      AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_tab_grants <> 0 THEN RAISE EXCEPTION 'C14 hardening tablas: % grants Data API/PUBLIC (esperado 0)', v_tab_grants; END IF;

  SELECT count(*) INTO v_seq_grants FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) a
    WHERE n.nspname='public' AND c.relkind='S'
      AND c.relname IN ('zonas_id_zona_seq','activaciones_operativas_id_activacion_seq','gastos_internos_id_gasto_seq','liquidaciones_periodo_id_liquidacion_seq','movimientos_socio_id_movimiento_seq','revaluaciones_id_revaluacion_seq')
      AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_seq_grants <> 0 THEN RAISE EXCEPTION 'C14 hardening secuencias: % grants Data API/PUBLIC (esperado 0)', v_seq_grants; END IF;

  SELECT count(*) INTO v_exec_abiertos FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    CROSS JOIN LATERAL aclexplode(p.proacl) a
    WHERE n.nspname='public'
      AND p.proname IN ('resolver_beneficiario','matriz_participacion','repartir_por_matriz','detalle_participacion','cascada_periodo','saldo_socios_periodo','incidencia_gasto','reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo','liquidacion_vigente','saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo','registrar_snapshot_periodo','registrar_retiro','registrar_movimiento_manual','registrar_reversa','registrar_revaluacion','trg_9h_inmutable','abortar_si_falla')
      AND a.privilege_type='EXECUTE'
      AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_exec_abiertos <> 0 THEN RAISE EXCEPTION 'C14 hardening funciones: % EXECUTE a Data API/PUBLIC (esperado 0)', v_exec_abiertos; END IF;

  RAISE NOTICE 'PARTE C OK: zonas=2, cabana_zona=5, beneficiarios sin NULL, activaciones=5, seam 5/5, matriz 378/456, reparto Σ=100000.00, hardening tablas/secuencias/funciones sin exposición.';
END
$verif_carril_b$;
