-- ============================================================================

-- VITA DELTA · ETAPA 9H · BLOQUE B.1 v3 — DDL DE ESTRUCTURA (capa con estado)

-- ----------------------------------------------------------------------------

-- Entorno objetivo : TEST (vita-delta-test, cabañas 1-5). NO correr en OPS.

-- Naturaleza       : WRITE (DDL). Seleccionar TODO y ejecutar como un único run.

--                    Gate DO primer statement (L-9G-02); DDL transaccional.

-- Crea             : 5 tablas + índices (cadena, reversa, mayor) + función e

--                    triggers de inmutabilidad + REVOKE de tablas, secuencias

--                    y función de trigger.

-- Inmutabilidad    : triggers anti UPDATE/DELETE/TRUNCATE (D-9H-15). Sin UPDATE

--                    legítimo: supersede y reversa son INSERT.

-- Pertenencia socio: FK compuestas de mismo-socio en reversa y conversión (D-9H-22).

-- Seguridad        : REVOKE PUBLIC + 3 roles en tablas, 3 secuencias y la función

--                    de trigger (D-9H-16, D-9H-21). RLS off por paridad; policies

--                    /exposición a la promoción.

-- Cambios vs v2    : teardown sin CASCADE; +REVOKE función trigger; FK compuestas

--                    de socio + UNIQUE(id_movimiento,id_socio); (saco FK simples).

-- Limpieza banco 9H: por TEARDOWN (DROP), no por DELETE (bloque aparte abajo).

-- ============================================================================



-- GATE programático de ambiente (primer statement; aborta el run si no es TEST)

DO $gate$

BEGIN

  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),

              '(ausente)') <> 'test' THEN

    RAISE EXCEPTION '9H GATE (B.1 v3): ambiente distinto de test — abortado';

  END IF;

END

$gate$;



-- ── 1) LIQUIDACIONES_PERIODO (cabecera + cadena append-only) ─────────────────

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



-- ── INMUTABILIDAD (D-9H-15): función + triggers anti UPDATE/DELETE/TRUNCATE ──

CREATE FUNCTION trg_9h_inmutable() RETURNS trigger

LANGUAGE plpgsql AS $$

BEGIN

  RAISE EXCEPTION '9H append-only: % no permitido sobre % (capa inmutable, D-9H-15)',

                  TG_OP, TG_TABLE_NAME;

END

$$;



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



-- ── SEGURIDAD (D-9H-16 / D-9H-21): tablas, secuencias y función de trigger ───

REVOKE ALL ON TABLE liquidaciones_periodo, liquidacion_cascada, liquidacion_socio,

                    movimientos_socio, revaluaciones

  FROM PUBLIC, anon, authenticated, service_role;



REVOKE ALL ON FUNCTION trg_9h_inmutable()

  FROM PUBLIC, anon, authenticated, service_role;



DO $revoke_seq$

DECLARE s text;

BEGIN

  FOREACH s IN ARRAY ARRAY[

      pg_get_serial_sequence('public.liquidaciones_periodo','id_liquidacion'),

      pg_get_serial_sequence('public.movimientos_socio','id_movimiento'),

      pg_get_serial_sequence('public.revaluaciones','id_revaluacion')

  ] LOOP

    EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM PUBLIC, anon, authenticated, service_role', s);

  END LOOP;

END

$revoke_seq$;