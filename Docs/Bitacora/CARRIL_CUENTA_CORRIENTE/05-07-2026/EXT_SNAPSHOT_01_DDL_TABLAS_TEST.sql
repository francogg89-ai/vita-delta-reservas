-- ============================================================================
-- EXT_SNAPSHOT_01_DDL_TABLAS_TEST.sql   (Run 1/6  --  ESCRIBE DDL, transaccional)
-- Crea las 3 tablas append-only del detalle fino + CHECKs minimos + REVOKE.
-- TEST-only (gate). Si el gate falla, ROLLBACK: no crea nada.
-- ============================================================================
BEGIN;
DO $gate$ BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave='ambiente') IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE TEST-only: ambiente actual = %', COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(sin clave)');
  END IF;
END $gate$;

-- T1: participacion por cabana (ground truth; matriz por socio deriva de aca)
CREATE TABLE liquidacion_participacion (
  id_liquidacion        BIGINT   NOT NULL REFERENCES liquidaciones_periodo(id_liquidacion) ON DELETE RESTRICT,
  id_cabana             BIGINT   NOT NULL REFERENCES cabanas(id_cabana)                     ON DELETE RESTRICT,
  valor_relativo        NUMERIC  NOT NULL,
  id_socio_beneficiario BIGINT   NOT NULL REFERENCES socios(id_socio)                       ON DELETE RESTRICT,
  participa             BOOLEAN  NOT NULL,
  PRIMARY KEY (id_liquidacion, id_cabana),
  CONSTRAINT chk_lpart_valor_pos CHECK (valor_relativo > 0)
);

-- T2: gasto por gasto (foto fiel de gastos_internos; id_gasto COPIADO sin FK, D-CC-30) + sin_incidencia/motivo
CREATE TABLE liquidacion_gasto (
  id_liquidacion        BIGINT        NOT NULL REFERENCES liquidaciones_periodo(id_liquidacion) ON DELETE RESTRICT,
  id_gasto              BIGINT        NOT NULL,
  fecha                 DATE          NOT NULL,
  clase                 TEXT          NOT NULL,
  clase_sugerida        TEXT,
  etiqueta              TEXT          NOT NULL,
  monto                 NUMERIC(14,2) NOT NULL,
  moneda                TEXT          NOT NULL,
  id_zona               BIGINT        REFERENCES zonas(id_zona)     ON DELETE RESTRICT,
  id_cabana             BIGINT        REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  pagador_tipo          TEXT          NOT NULL,
  id_socio_pagador      BIGINT        REFERENCES socios(id_socio)   ON DELETE RESTRICT,
  medio_pago            TEXT,
  comentario            TEXT,
  comprobante_url       TEXT,
  creado_por            TEXT          NOT NULL,
  created_at            TIMESTAMPTZ   NOT NULL,
  sin_incidencia        BOOLEAN       NOT NULL,
  motivo_sin_incidencia TEXT,
  PRIMARY KEY (id_liquidacion, id_gasto),
  CONSTRAINT chk_lgasto_clase         CHECK (clase IN ('A','C','D','E')),
  CONSTRAINT chk_lgasto_monto_pos     CHECK (monto > 0),
  CONSTRAINT chk_lgasto_moneda        CHECK (moneda = 'ARS'),
  CONSTRAINT chk_lgasto_pagador_tipo  CHECK (pagador_tipo IN ('socio','caja')),
  CONSTRAINT chk_lgasto_pagador_cons  CHECK (
       (pagador_tipo='socio' AND id_socio_pagador IS NOT NULL)
    OR (pagador_tipo='caja'  AND id_socio_pagador IS NULL)),
  CONSTRAINT chk_lgasto_alcance_clase CHECK (
       (clase='D' AND id_zona IS NOT NULL AND id_cabana IS NULL)
    OR (clase='E' AND id_cabana IS NOT NULL AND id_zona IS NULL)
    OR (clase IN ('A','C') AND id_zona IS NULL AND id_cabana IS NULL)),
  CONSTRAINT chk_lgasto_sin_incidencia_coherente CHECK (
       sin_incidencia = (motivo_sin_incidencia IS NOT NULL)),
  CONSTRAINT chk_lgasto_clase_sug     CHECK (clase_sugerida IS NULL OR clase_sugerida IN ('A','C','D','E')),
  CONSTRAINT chk_lgasto_motivo_dom    CHECK (motivo_sin_incidencia IS NULL
                                             OR motivo_sin_incidencia IN ('pool_vacio','zona_sin_activas'))
);

-- T3: incidencia por gasto (regla congelada); FK compuesta a T2 (ambas tablas congeladas)
CREATE TABLE liquidacion_incidencia (
  id_liquidacion  BIGINT        NOT NULL,
  id_gasto        BIGINT        NOT NULL,
  seq             SMALLINT      NOT NULL,
  destino         TEXT          NOT NULL,
  id_socio        BIGINT        REFERENCES socios(id_socio) ON DELETE RESTRICT,
  monto_incidido  NUMERIC(14,2) NOT NULL,
  regla           TEXT          NOT NULL,
  PRIMARY KEY (id_liquidacion, id_gasto, seq),
  CONSTRAINT fk_linc_gasto FOREIGN KEY (id_liquidacion, id_gasto)
      REFERENCES liquidacion_gasto (id_liquidacion, id_gasto) ON DELETE RESTRICT,
  CONSTRAINT chk_linc_seq_pos        CHECK (seq > 0),
  CONSTRAINT chk_linc_destino        CHECK (destino IN ('pool_pre_operativo','socio')),
  CONSTRAINT chk_linc_monto_centavos CHECK (monto_incidido = ROUND(monto_incidido, 2)),
  CONSTRAINT chk_linc_destino_socio  CHECK (
       (destino='socio' AND id_socio IS NOT NULL)
    OR (destino='pool_pre_operativo' AND id_socio IS NULL))
);

-- REVOKE (0 Data API; sin secuencias que revocar: PKs compuestas)
REVOKE ALL ON TABLE liquidacion_participacion FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE liquidacion_gasto         FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE liquidacion_incidencia    FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
