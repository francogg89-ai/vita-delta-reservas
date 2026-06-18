-- ============================================================================
-- PROMO_BLOQUE_G_9H_ESTRUCTURA_OPS.sql
-- Promoción del Carril B a OPS — BLOQUE G (9H: ESTRUCTURA, capa con estado).
-- Etapa PROMO. Depende de B1(9C), C(9D), D(9E), E(9F), F(9G) VERDE en OPS.
-- Contenido: 5 tablas append-only + índices de cadena/supersesión/reversa/mayor
-- + FK compuestas (mismo período / mismo socio) + función trg_9h_inmutable()
-- + 10 triggers anti UPDATE/DELETE/TRUNCATE + REVOKE (tablas, 3 secuencias, fn).
--
-- DDL de estructura VERBATIM de 9H_BLOQUE_B1_v3.sql (fuente autoritativa de la
-- sesión 9H). ÚNICO cambio respecto del original: se reemplaza su gate de TEST
-- (ambiente='test', que prohíbe correr en OPS) por el gate PROMO de abajo
-- (ambiente='ops' + identidad + cadena 9C→9G + ausencia 9H). La lógica de
-- estructura NO se altera.
--
-- SIN fixture, SIN INSERT a liquidaciones/cascada/socio/movimientos/revaluaciones
-- (D-9H/promoción: OPS arranca con las 5 tablas VACÍAS y las 3 secuencias en 1).
-- La inmutabilidad por triggers se valida en harness (INSERT→UPDATE/DELETE/
-- TRUNCATE→ROLLBACK); el bloque OPS verifica que los 10 triggers EXISTEN.
-- NO toca 9C/9D/9E/9F/9G ni helper 9B ni la legacy `gastos`.
--
-- ESTRUCTURA: BEGIN → gate → DDL verbatim → asserts → COMMIT → verificación
-- read-only posterior → reversión sin DROP ... CASCADE.
-- Correr con NADA seleccionado (L-8A-01).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- GATE PROMO — marcador ops + identidad + cadena 9C→9G presente + 9H ausente.
-- (Reemplaza el gate de TEST del archivo original.)
-- ----------------------------------------------------------------------------
DO $promogate$
DECLARE
  v_amb text; v_cab int; v_soc int;
  v_9c int; v_9d int; v_9e int; v_9f int; v_9g int;
  v_9h_tab int; v_9h_fn int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE G: marcador ambiente=% (esperado ops).', COALESCE(v_amb,'<ausente>'); END IF;

  SELECT count(*) INTO v_cab FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
   WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  SELECT count(*) INTO v_soc FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
   WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1;
  IF v_cab<>5 OR v_soc<>3 THEN RAISE EXCEPTION 'GATE G: identidad (cabañas=%/5, socios=%/3).', v_cab, v_soc; END IF;

  -- Cadena 9C→9G presente (orden de la promoción)
  SELECT count(*) INTO v_9c FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='resolver_beneficiario';
  SELECT count(*) INTO v_9d FROM activaciones_operativas;
  SELECT count(*) INTO v_9e FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('matriz_participacion','repartir_por_matriz','detalle_participacion');
  SELECT count(*) INTO v_9f FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r' AND c.relname='gastos_internos';
  SELECT count(*) INTO v_9g FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                       'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo');
  IF v_9c<>1 THEN RAISE EXCEPTION 'GATE G: seam 9C ausente (correr B1).'; END IF;
  IF v_9d<>5 THEN RAISE EXCEPTION 'GATE G: activaciones 9D=% (esperado 5; correr C).', v_9d; END IF;
  IF v_9e<>3 THEN RAISE EXCEPTION 'GATE G: funciones 9E=% (esperado 3; correr D).', v_9e; END IF;
  IF v_9f<>1 THEN RAISE EXCEPTION 'GATE G: tabla 9F ausente (correr E).'; END IF;
  IF v_9g<>6 THEN RAISE EXCEPTION 'GATE G: funciones 9G=% (esperado 6; correr F).', v_9g; END IF;

  -- 9H ausente — guard de re-ejecución (ninguna de las 5 tablas, ni la fn trigger)
  SELECT count(*) INTO v_9h_tab FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r'
     AND c.relname IN ('liquidaciones_periodo','liquidacion_cascada','liquidacion_socio',
                       'movimientos_socio','revaluaciones');
  SELECT count(*) INTO v_9h_fn FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='trg_9h_inmutable';
  IF v_9h_tab<>0 OR v_9h_fn<>0 THEN
    RAISE EXCEPTION 'GATE G: 9H ya presente (tablas=%, fn=%). G no se re-ejecuta.', v_9h_tab, v_9h_fn; END IF;

  RAISE NOTICE 'GATE G OK — OPS post-9G; 9H ausente.';
END
$promogate$;

-- ============================================================================
-- DDL DE ESTRUCTURA 9H — VERBATIM de 9H_BLOQUE_B1_v3.sql (sin su gate de TEST).
-- ============================================================================
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

-- ----------------------------------------------------------------------------
-- ASSERTS FINALES (DO + RAISE). Estructura completa, tablas vacías, hardening.
-- ----------------------------------------------------------------------------
DO $assert$
DECLARE
  v_tab int; v_cols_total int;
  v_c_liq int; v_c_casc int; v_c_socio int; v_c_mov int; v_c_reval int;
  v_constr int; v_chk int; v_fk int; v_uq int; v_pk int;
  v_clave int; v_idx int; v_fn int; v_trg int;
  v_filas int; v_seq_called int; v_grants_tab int; v_grants_seq int; v_fn_open int;
  v_excl int;
  v_dataapi oid[];
BEGIN
  v_dataapi := array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL);

  -- G1: 5 tablas presentes
  SELECT count(*) INTO v_tab FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r'
     AND c.relname IN ('liquidaciones_periodo','liquidacion_cascada','liquidacion_socio','movimientos_socio','revaluaciones');
  IF v_tab<>5 THEN RAISE EXCEPTION 'ASSERT G1: tablas 9H=% (esperado 5).', v_tab; END IF;

  -- G2: columnas por tabla (7/4/7/12/11 = 41)
  SELECT count(*) FILTER (WHERE table_name='liquidaciones_periodo'),
         count(*) FILTER (WHERE table_name='liquidacion_cascada'),
         count(*) FILTER (WHERE table_name='liquidacion_socio'),
         count(*) FILTER (WHERE table_name='movimientos_socio'),
         count(*) FILTER (WHERE table_name='revaluaciones'),
         count(*)
    INTO v_c_liq, v_c_casc, v_c_socio, v_c_mov, v_c_reval, v_cols_total
    FROM information_schema.columns
   WHERE table_schema='public'
     AND table_name IN ('liquidaciones_periodo','liquidacion_cascada','liquidacion_socio','movimientos_socio','revaluaciones');
  IF v_c_liq<>7 OR v_c_casc<>4 OR v_c_socio<>7 OR v_c_mov<>12 OR v_c_reval<>11 THEN
    RAISE EXCEPTION 'ASSERT G2: columnas liq=%/casc=%/socio=%/mov=%/reval=% (esperado 7/4/7/12/11).',
      v_c_liq, v_c_casc, v_c_socio, v_c_mov, v_c_reval; END IF;

  -- G3: constraints totales por tipo (46 = 31 CHECK + 8 FK + 2 UNIQUE + 5 PK)
  SELECT count(*),
         count(*) FILTER (WHERE contype='c'),
         count(*) FILTER (WHERE contype='f'),
         count(*) FILTER (WHERE contype='u'),
         count(*) FILTER (WHERE contype='p')
    INTO v_constr, v_chk, v_fk, v_uq, v_pk
    FROM pg_constraint
   WHERE conrelid IN ('liquidaciones_periodo'::regclass,'liquidacion_cascada'::regclass,
                      'liquidacion_socio'::regclass,'movimientos_socio'::regclass,'revaluaciones'::regclass);
  IF v_constr<>46 OR v_chk<>31 OR v_fk<>8 OR v_uq<>2 OR v_pk<>5 THEN
    RAISE EXCEPTION 'ASSERT G3: constraints tot=%/chk=%/fk=%/uq=%/pk=% (esperado 46/31/8/2/5).',
      v_constr, v_chk, v_fk, v_uq, v_pk; END IF;

  -- G4: constraints CRÍTICAS por nombre (FK compuestas + supersesión + coherencias + reversa-link)
  SELECT count(*) INTO v_clave FROM pg_constraint
   WHERE conname IN ('fk_liq_supersede_mismo_periodo','fk_mov_reversa_mismo_socio','fk_reval_origen_mismo_socio',
                     'uq_liq_id_periodo','uq_mov_id_socio','chk_socio_saldo_final_coherente',
                     'chk_reval_usd_coherente','chk_mov_reversa_link');
  IF v_clave<>8 THEN RAISE EXCEPTION 'ASSERT G4: constraints clave por nombre=% (esperado 8).', v_clave; END IF;

  -- G5: 5 índices standalone (cadena/supersesión/reversa/mayor) por nombre
  SELECT count(*) INTO v_idx FROM pg_class WHERE relkind='i'
     AND relname IN ('uq_liq_una_raiz_por_periodo','uq_liq_sin_fork','idx_mov_socio','idx_mov_periodo_tipo','uq_mov_reversa_unica');
  IF v_idx<>5 THEN RAISE EXCEPTION 'ASSERT G5: índices standalone por nombre=% (esperado 5).', v_idx; END IF;

  -- G6: función trg_9h_inmutable presente
  SELECT count(*) INTO v_fn FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='trg_9h_inmutable';
  IF v_fn<>1 THEN RAISE EXCEPTION 'ASSERT G6: trg_9h_inmutable=% (esperado 1).', v_fn; END IF;

  -- G7: 10 triggers de inmutabilidad (no internos) sobre las 5 tablas
  SELECT count(*) INTO v_trg FROM pg_trigger tg
   WHERE NOT tg.tgisinternal
     AND tg.tgrelid IN ('liquidaciones_periodo'::regclass,'liquidacion_cascada'::regclass,
                        'liquidacion_socio'::regclass,'movimientos_socio'::regclass,'revaluaciones'::regclass);
  IF v_trg<>10 THEN RAISE EXCEPTION 'ASSERT G7: triggers de inmutabilidad=% (esperado 10).', v_trg; END IF;

  -- G8: las 5 tablas VACÍAS (sin fixture)
  SELECT (SELECT count(*) FROM liquidaciones_periodo)+(SELECT count(*) FROM liquidacion_cascada)
        +(SELECT count(*) FROM liquidacion_socio)+(SELECT count(*) FROM movimientos_socio)
        +(SELECT count(*) FROM revaluaciones) INTO v_filas;
  IF v_filas<>0 THEN RAISE EXCEPTION 'ASSERT G8: filas en tablas 9H=% (esperado 0, sin fixture).', v_filas; END IF;

  -- G9: 3 secuencias sin usar (is_called=false) — OPS arranca en 1
  -- (se lee is_called desde la relación de secuencia; pg_sequences no lo expone)
  SELECT (SELECT is_called FROM liquidaciones_periodo_id_liquidacion_seq)::int
       + (SELECT is_called FROM movimientos_socio_id_movimiento_seq)::int
       + (SELECT is_called FROM revaluaciones_id_revaluacion_seq)::int
    INTO v_seq_called;
  IF v_seq_called<>0 THEN RAISE EXCEPTION 'ASSERT G9: secuencias ya usadas=% (esperado 0).', v_seq_called; END IF;

  -- G10 (hardening): 0 grants Data API/PUBLIC en las 5 tablas
  SELECT count(*) INTO v_grants_tab FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) acl
   WHERE n.nspname='public'
     AND c.relname IN ('liquidaciones_periodo','liquidacion_cascada','liquidacion_socio','movimientos_socio','revaluaciones')
     AND acl.grantee = ANY (v_dataapi);
  IF v_grants_tab<>0 THEN RAISE EXCEPTION 'ASSERT G10: grants Data API/PUBLIC en tablas=% (esperado 0).', v_grants_tab; END IF;

  -- G11 (hardening): 0 grants en las 3 secuencias
  SELECT count(*) INTO v_grants_seq FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) acl
   WHERE n.nspname='public' AND c.relkind='S'
     AND c.relname IN ('liquidaciones_periodo_id_liquidacion_seq','movimientos_socio_id_movimiento_seq','revaluaciones_id_revaluacion_seq')
     AND acl.grantee = ANY (v_dataapi);
  IF v_grants_seq<>0 THEN RAISE EXCEPTION 'ASSERT G11: grants Data API/PUBLIC en secuencias=% (esperado 0).', v_grants_seq; END IF;

  -- G12 (hardening): trg_9h_inmutable sin EXECUTE para Data API/PUBLIC
  SELECT count(*) INTO v_fn_open FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='trg_9h_inmutable'
     AND (p.proacl IS NULL
          OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY (v_dataapi)));
  IF v_fn_open<>0 THEN RAISE EXCEPTION 'ASSERT G12: trg_9h_inmutable abierta a EXECUTE=% (esperado 0).', v_fn_open; END IF;

  -- G13 (aislamiento): 9H no agrega EXCLUDE ⇒ EXCLUDE en public sigue = 3
  SELECT count(*) INTO v_excl FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
   WHERE con.contype='x' AND n.nspname='public';
  IF v_excl<>3 THEN RAISE EXCEPTION 'ASSERT G13: EXCLUDE en public=% (esperado 3).', v_excl; END IF;

  RAISE NOTICE 'ASSERTS G OK — 9H estructura completa, tablas vacías, hardening. Listo para COMMIT.';
END
$assert$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN READ-ONLY POSTERIOR (fuera de la transacción).
-- ============================================================================
WITH dataapi AS (
  SELECT array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL) AS oids),
m AS (
  SELECT
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'
       AND c.relname IN ('liquidaciones_periodo','liquidacion_cascada','liquidacion_socio','movimientos_socio','revaluaciones')) AS tab,
    (SELECT count(*) FROM information_schema.columns WHERE table_schema='public'
       AND table_name IN ('liquidaciones_periodo','liquidacion_cascada','liquidacion_socio','movimientos_socio','revaluaciones')) AS cols,
    (SELECT count(*) FROM pg_constraint WHERE conrelid IN ('liquidaciones_periodo'::regclass,'liquidacion_cascada'::regclass,
       'liquidacion_socio'::regclass,'movimientos_socio'::regclass,'revaluaciones'::regclass)) AS constr,
    (SELECT count(*) FROM pg_constraint WHERE contype='f' AND conrelid IN ('liquidaciones_periodo'::regclass,'liquidacion_cascada'::regclass,
       'liquidacion_socio'::regclass,'movimientos_socio'::regclass,'revaluaciones'::regclass)) AS fk,
    (SELECT count(*) FROM pg_class WHERE relkind='i'
       AND relname IN ('uq_liq_una_raiz_por_periodo','uq_liq_sin_fork','idx_mov_socio','idx_mov_periodo_tipo','uq_mov_reversa_unica')) AS idx,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='trg_9h_inmutable') AS fn,
    (SELECT count(*) FROM pg_trigger tg WHERE NOT tg.tgisinternal AND tg.tgrelid IN ('liquidaciones_periodo'::regclass,
       'liquidacion_cascada'::regclass,'liquidacion_socio'::regclass,'movimientos_socio'::regclass,'revaluaciones'::regclass)) AS trg,
    ((SELECT count(*) FROM liquidaciones_periodo)+(SELECT count(*) FROM liquidacion_cascada)+(SELECT count(*) FROM liquidacion_socio)
      +(SELECT count(*) FROM movimientos_socio)+(SELECT count(*) FROM revaluaciones)) AS filas,
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) acl, dataapi
       WHERE n.nspname='public' AND acl.grantee = ANY (dataapi.oids)
         AND ((c.relkind='r' AND c.relname IN ('liquidaciones_periodo','liquidacion_cascada','liquidacion_socio','movimientos_socio','revaluaciones'))
           OR (c.relkind='S' AND c.relname IN ('liquidaciones_periodo_id_liquidacion_seq','movimientos_socio_id_movimiento_seq','revaluaciones_id_revaluacion_seq')))) AS grants,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace, dataapi WHERE n.nspname='public' AND p.proname='trg_9h_inmutable'
       AND (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY (dataapi.oids)))) AS fn_open,
    (SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE con.contype='x' AND n.nspname='public') AS excl
)
SELECT v.orden, v.chequeo, v.obtenido, v.esperado,
       CASE WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (1,'5 tablas 9H presentes', m.tab::text,'5',(m.tab=5)),
  (2,'columnas totales (7+4+7+12+11)', m.cols::text,'41',(m.cols=41)),
  (3,'constraints totales', m.constr::text,'46',(m.constr=46)),
  (4,'FK (incluye 3 compuestas)', m.fk::text,'8',(m.fk=8)),
  (5,'índices standalone (cadena/reversa/mayor)', m.idx::text,'5',(m.idx=5)),
  (6,'función trg_9h_inmutable', m.fn::text,'1',(m.fn=1)),
  (7,'triggers de inmutabilidad', m.trg::text,'10',(m.trg=10)),
  (8,'tablas vacías (sin fixture)', m.filas::text,'0',(m.filas=0)),
  (9,'grants Data API/PUBLIC (tablas+secuencias)', m.grants::text,'0',(m.grants=0)),
  (10,'trg_9h_inmutable abierta a EXECUTE', m.fn_open::text,'0',(m.fn_open=0)),
  (11,'EXCLUDE public (9H no agrega)', m.excl::text,'3',(m.excl=3))
) AS v(orden, chequeo, obtenido, esperado, ok)
UNION ALL
SELECT 999,'TOTAL G (9H estructura)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES
     (m.tab=5),(m.cols=41),(m.constr=46),(m.fk=8),(m.idx=5),(m.fn=1),(m.trg=10),(m.filas=0),(m.grants=0),(m.fn_open=0),(m.excl=3)
   ) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES
     (m.tab=5),(m.cols=41),(m.constr=46),(m.fk=8),(m.idx=5),(m.fn=1),(m.trg=10),(m.filas=0),(m.grants=0),(m.fn_open=0),(m.excl=3)
   ) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;

-- ============================================================================
-- REVERSIÓN CONCEPTUAL (NO ejecutar; sin DROP ... CASCADE).
--    Orden FK-respetuoso (dependientes primero); la fn al final. Los triggers
--    de inmutabilidad bloquean DML (UPDATE/DELETE/TRUNCATE), NO el DROP TABLE.
-- ----------------------------------------------------------------------------
-- BEGIN;
--   DROP TABLE IF EXISTS revaluaciones;          -- refiere a movimientos_socio
--   DROP TABLE IF EXISTS movimientos_socio;
--   DROP TABLE IF EXISTS liquidacion_socio;
--   DROP TABLE IF EXISTS liquidacion_cascada;
--   DROP TABLE IF EXISTS liquidaciones_periodo;
--   DROP FUNCTION IF EXISTS trg_9h_inmutable();
-- COMMIT;
-- ============================================================================
