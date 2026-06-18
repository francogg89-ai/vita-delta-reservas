-- ============================================================================
-- PROMO_BLOQUE_B1_9C_OPS.sql
-- Promoción del Carril B a OPS — BLOQUE B1 (solo 9C).
-- Etapa PROMO. Decisiones D-PROMO-01..06. NO toca 9D/9E/9F/9G/9H ni helper 9B.
--
-- Contenido de B1 (9C): marcador ambiente='ops' · columnas valor_relativo e
-- id_socio_beneficiario en cabanas (nullable→backfill→NOT NULL) · zonas ·
-- cabana_zona · seam resolver_beneficiario · hardening (REVOKE + asserts en cero).
--
-- ESTRUCTURA: BEGIN → gate inicial (identidad ESTRUCTURAL de OPS, NO current_user,
-- NO marcador porque aún no existe) → prechecks → DDL/seed real → hardening →
-- asserts finales → COMMIT → verificación read-only posterior → reversión
-- conceptual SIN DROP ... CASCADE.
--
-- Todo lo destructivo/condicional aborta la transacción entera vía RAISE: o entra
-- 9C completo y consistente, o no entra nada.
--
-- Cómo correr: con NADA seleccionado en el SQL Editor (L-8A-01). Las cabañas reales
-- de OPS son ids 1-5; el seed se resuelve POR NOMBRE, no por id literal.
-- Valores reales (D-PROMO-02, = canónicos de 9C §2.1):
--   Arrebol→Franco(100) · Madre Selva→Rodrigo(100) · Bamboo→Remo(100)
--   Guatemala→Franco(78) · Tokio→Remo(78)
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. GATE INICIAL — identidad ESTRUCTURAL de OPS pre-promoción.
--    Sin current_user (L-7E-01) y sin marcador (aún no existe). Si algo no calza,
--    RAISE aborta TODA la transacción. Captura además la huella de cabanas.activa
--    en una variable transaccional para el assert final.
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE
  v_cab_real      int;
  v_soc_real      int;
  v_placeholder   int;
  v_col_carrilb   int;
  v_tbl_carrilb   int;
  v_fn_carrilb    int;
  v_fn_helper     int;
  v_marcador      int;
  v_excl_named    int;
  v_excl_total    int;
  v_activa_md5    text;
BEGIN
  -- (a) Cabañas 1-5 reales por id+nombre
  SELECT count(*) INTO v_cab_real
  FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
  WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  IF v_cab_real <> 5 THEN
    RAISE EXCEPTION 'GATE B1: identidad de cabañas no coincide (% de 5). No parece OPS.', v_cab_real;
  END IF;

  -- (b) Socios reales Franco/Rodrigo/Remo (1 c/u) y sin placeholder 'Socio 3'
  SELECT count(*) INTO v_soc_real
  FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
  WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1;
  SELECT count(*) INTO v_placeholder FROM socios WHERE nombre='Socio 3';
  IF v_soc_real <> 3 OR v_placeholder <> 0 THEN
    RAISE EXCEPTION 'GATE B1: socios reales=% (esperado 3), placeholder Socio 3=% (esperado 0). Prereq L-9C-01.',
      v_soc_real, v_placeholder;
  END IF;

  -- (c) Ausencia de Carril B (columnas, tablas, funciones) — guard de re-ejecución
  SELECT count(*) INTO v_col_carrilb FROM information_schema.columns
   WHERE table_schema='public' AND table_name='cabanas'
     AND column_name IN ('valor_relativo','id_socio_beneficiario');
  SELECT count(*) INTO v_tbl_carrilb FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r'
     AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos',
                       'liquidaciones_periodo','liquidacion_cascada','liquidacion_socio',
                       'movimientos_socio','revaluaciones');
  SELECT count(*) INTO v_fn_carrilb FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('resolver_beneficiario','matriz_participacion','repartir_por_matriz',
                       'detalle_participacion','cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                       'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo',
                       'liquidacion_vigente','saldo_corriente_socio','mayor_socio',
                       'reporte_retribucion_operativo_periodo','registrar_snapshot_periodo','registrar_retiro',
                       'registrar_movimiento_manual','registrar_reversa','registrar_revaluacion',
                       'trg_9h_inmutable');
  IF v_col_carrilb <> 0 OR v_tbl_carrilb <> 0 OR v_fn_carrilb <> 0 THEN
    RAISE EXCEPTION 'GATE B1: ya hay objetos de Carril B (cols=%, tablas=%, fns=%). B1 no se re-ejecuta sobre un OPS ya promovido.',
      v_col_carrilb, v_tbl_carrilb, v_fn_carrilb;
  END IF;

  -- (d) Ausencia del helper 9B (no lo crea B1, pero su presencia indicaría estado inesperado)
  SELECT count(*) INTO v_fn_helper FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='abortar_si_falla';
  IF v_fn_helper <> 0 THEN
    RAISE EXCEPTION 'GATE B1: helper abortar_si_falla ya presente (=%). Estado inesperado; revisar antes de B1.', v_fn_helper;
  END IF;

  -- (e) Ausencia del marcador ambiente (lo crea B1; si ya existe, B1 no es el primer paso)
  SELECT count(*) INTO v_marcador FROM configuracion_general WHERE clave='ambiente';
  IF v_marcador <> 0 THEN
    RAISE EXCEPTION 'GATE B1: marcador configuracion_general(ambiente) ya existe (=%). B1 es quien lo siembra.', v_marcador;
  END IF;

  -- (f) EXCLUDE de base por NOMBRE (D-PROMO refuerzo): exc_reservas_no_overlap + exc_bloqueos_no_overlap,
  --     y total en public = 2 (ningún extra inesperado).
  SELECT count(*) INTO v_excl_named FROM pg_constraint
   WHERE contype='x' AND conname IN ('exc_reservas_no_overlap','exc_bloqueos_no_overlap');
  SELECT count(*) INTO v_excl_total FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
   WHERE con.contype='x' AND n.nspname='public';
  IF v_excl_named <> 2 OR v_excl_total <> 2 THEN
    RAISE EXCEPTION 'GATE B1: EXCLUDE de base nombradas=% (esperado 2), EXCLUDE total public=% (esperado 2).',
      v_excl_named, v_excl_total;
  END IF;

  -- (g) Captura del fingerprint de cabanas.activa (transaccional) para el assert final
  SELECT md5(string_agg(id_cabana::text||':'||activa::text, ',' ORDER BY id_cabana))
    INTO v_activa_md5 FROM cabanas;
  PERFORM set_config('promo.b1_activa_baseline', v_activa_md5, true);  -- true = local a la transacción

  RAISE NOTICE 'GATE B1 OK — OPS pre-promoción confirmado. Baseline activa=%', v_activa_md5;
END
$gate$;

-- ----------------------------------------------------------------------------
-- 2. PRECHECKS adicionales (read-only, dentro de la tx) — btree_gist disponible
--    (necesario para 9D más adelante; acá solo se confirma para no sorprender).
-- ----------------------------------------------------------------------------
DO $pre$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='btree_gist') THEN
    RAISE EXCEPTION 'PRECHECK B1: extensión btree_gist ausente (base de paridad 8A).';
  END IF;
END
$pre$;

-- ----------------------------------------------------------------------------
-- 3. DDL / SEED REAL (9C). Orden: marcador → columnas nullable → tablas →
--    seed zonas + backfill + pertenencias → NOT NULL → seam.
-- ----------------------------------------------------------------------------

-- 3.1 Marcador de ambiente (D-9C-19 / D-PROMO): se siembra 'ops' (en TEST es 'test')
INSERT INTO configuracion_general (clave, valor, descripcion, categoria, editable)
VALUES ('ambiente', 'ops',
        'Marcador de entorno para gates de Carril B (D-9C-19 / PROMO)', 'infra', FALSE);

-- 3.2 Columnas en cabanas — agregadas NULLABLE (NOT NULL se aplica tras el backfill)
ALTER TABLE cabanas
  ADD COLUMN valor_relativo NUMERIC(6,2)
    CONSTRAINT chk_cabanas_valor_relativo_positivo CHECK (valor_relativo > 0);
ALTER TABLE cabanas
  ADD COLUMN id_socio_beneficiario BIGINT
    CONSTRAINT fk_cabanas_socio_beneficiario
      REFERENCES socios(id_socio) ON DELETE RESTRICT;

-- 3.3 zonas (D-9C-16)
CREATE TABLE zonas (
  id_zona      BIGSERIAL PRIMARY KEY,
  nombre       TEXT NOT NULL,
  descripcion  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_zonas_nombre UNIQUE (nombre),
  CONSTRAINT chk_zonas_nombre_no_vacio CHECK (length(trim(nombre)) > 0)
);

-- 3.4 cabana_zona (D-9C-17) — M2M, PK compuesta, FK CASCADE/RESTRICT + índice inverso
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

-- 3.5 Seed de zonas (estructural real: grandes/chicas)
INSERT INTO zonas (nombre, descripcion) VALUES
  ('grandes', 'Zona de cabañas grandes (seed MVP Carril B)'),
  ('chicas',  'Zona de cabañas chicas (seed MVP Carril B)')
ON CONFLICT (nombre) DO NOTHING;

-- 3.6 Backfill de cabanas — POR NOMBRE, valores reales (D-PROMO-02)
UPDATE cabanas c
SET valor_relativo = v.valrel, id_socio_beneficiario = s.id_socio
FROM (VALUES
    ('Arrebol',100,'Franco'),('Madre Selva',100,'Rodrigo'),('Bamboo',100,'Remo'),
    ('Guatemala',78,'Franco'),('Tokio',78,'Remo')
) AS v(cab_nombre, valrel, socio_nombre)
JOIN socios s ON s.nombre = v.socio_nombre
WHERE c.nombre = v.cab_nombre;

-- 3.7 Pertenencias cabana_zona — POR NOMBRE
INSERT INTO cabana_zona (id_cabana, id_zona)
SELECT c.id_cabana, z.id_zona
FROM (VALUES
    ('Arrebol','grandes'),('Madre Selva','grandes'),('Bamboo','grandes'),
    ('Guatemala','chicas'),('Tokio','chicas')
) AS m(cab_nombre, zona_nombre)
JOIN cabanas c ON c.nombre = m.cab_nombre
JOIN zonas   z ON z.nombre = m.zona_nombre
ON CONFLICT (id_cabana, id_zona) DO NOTHING;

-- 3.8 Endurecimiento NOT NULL (post-backfill)
ALTER TABLE cabanas ALTER COLUMN valor_relativo        SET NOT NULL;
ALTER TABLE cabanas ALTER COLUMN id_socio_beneficiario SET NOT NULL;

-- 3.9 Seam resolver_beneficiario (D-9C-18). CREATE desde cero (no existe en OPS);
--     DROP IF EXISTS por idempotencia, sin CASCADE. Sin variables v_ (sin riesgo Dashboard).
DROP FUNCTION IF EXISTS resolver_beneficiario(BIGINT, DATE);
CREATE FUNCTION resolver_beneficiario(p_id_cabana BIGINT, p_fecha DATE)
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $fn$
  -- p_fecha se ignora en el MVP (seam): hoy devuelve el beneficiario estable.
  SELECT id_socio_beneficiario FROM cabanas WHERE id_cabana = p_id_cabana;
$fn$;

-- ----------------------------------------------------------------------------
-- 4. HARDENING (dentro de la MISMA transacción, antes del COMMIT).
--    REVOKE sobre tablas nuevas, sobre la secuencia de zonas y EXECUTE sobre el
--    seam, a PUBLIC + anon + authenticated + service_role.
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE zonas       FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE cabana_zona FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE zonas_id_zona_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION resolver_beneficiario(BIGINT, DATE) FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. ASSERTS FINALES (DO + RAISE). Cualquier fallo revierte TODO (nada se commitea).
-- ----------------------------------------------------------------------------
DO $assert$
DECLARE
  v_cols_notnull   int;
  v_nulls          int;
  v_zonas          int;
  v_cz             int;
  v_seed_ok        int;
  v_seam_ok        int;
  v_seam_fecha_ok  int;
  v_marcador       int;
  v_activa_now     text;
  v_grants_tbl     int;
  v_grants_seq     int;
  v_exec_seam      int;
  v_excl_public    int;
  v_dataapi        oid[];
BEGIN
  v_dataapi := array_remove(ARRAY[
    0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL);

  -- A1: ambas columnas existen y son NOT NULL
  SELECT count(*) INTO v_cols_notnull FROM information_schema.columns
   WHERE table_schema='public' AND table_name='cabanas'
     AND column_name IN ('valor_relativo','id_socio_beneficiario') AND is_nullable='NO';
  IF v_cols_notnull <> 2 THEN RAISE EXCEPTION 'ASSERT A1: columnas NOT NULL=% (esperado 2).', v_cols_notnull; END IF;

  -- A2: sin NULLs en las columnas nuevas
  SELECT count(*) INTO v_nulls FROM cabanas WHERE valor_relativo IS NULL OR id_socio_beneficiario IS NULL;
  IF v_nulls <> 0 THEN RAISE EXCEPTION 'ASSERT A2: hay % cabañas con NULL en columnas nuevas.', v_nulls; END IF;

  -- A3/A4: zonas=2, cabana_zona=5
  SELECT count(*) INTO v_zonas FROM zonas;
  SELECT count(*) INTO v_cz FROM cabana_zona;
  IF v_zonas <> 2 THEN RAISE EXCEPTION 'ASSERT A3: zonas=% (esperado 2).', v_zonas; END IF;
  IF v_cz <> 5 THEN RAISE EXCEPTION 'ASSERT A4: cabana_zona=% (esperado 5).', v_cz; END IF;

  -- A5: las 5 cabañas con valor + beneficiario esperados (por nombre)
  SELECT count(*) INTO v_seed_ok
  FROM (VALUES ('Arrebol',100,'Franco'),('Madre Selva',100,'Rodrigo'),('Bamboo',100,'Remo'),
               ('Guatemala',78,'Franco'),('Tokio',78,'Remo')) e(nom,val,ben)
  JOIN cabanas c ON c.nombre=e.nom
  JOIN socios  s ON s.id_socio=c.id_socio_beneficiario
  WHERE c.valor_relativo=e.val AND s.nombre=e.ben;
  IF v_seed_ok <> 5 THEN RAISE EXCEPTION 'ASSERT A5: filas de seed correctas=% (esperado 5).', v_seed_ok; END IF;

  -- A6: seam resuelve al beneficiario para las 5, e independiente de la fecha
  SELECT count(*) INTO v_seam_ok FROM cabanas c
   WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01') = c.id_socio_beneficiario;
  SELECT count(*) INTO v_seam_fecha_ok FROM cabanas c
   WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01')
       = resolver_beneficiario(c.id_cabana, DATE '2030-12-31');
  IF v_seam_ok <> 5 OR v_seam_fecha_ok <> 5 THEN
    RAISE EXCEPTION 'ASSERT A6: seam ok=%/5, fecha-indep=%/5.', v_seam_ok, v_seam_fecha_ok; END IF;

  -- A7: marcador ambiente='ops'
  SELECT count(*) INTO v_marcador FROM configuracion_general WHERE clave='ambiente' AND valor='ops';
  IF v_marcador <> 1 THEN RAISE EXCEPTION 'ASSERT A7: marcador ambiente=ops presente=% (esperado 1).', v_marcador; END IF;

  -- A8: cabanas.activa SIN cambios respecto del baseline capturado en el gate
  SELECT md5(string_agg(id_cabana::text||':'||activa::text, ',' ORDER BY id_cabana)) INTO v_activa_now FROM cabanas;
  IF v_activa_now <> current_setting('promo.b1_activa_baseline') THEN
    RAISE EXCEPTION 'ASSERT A8: cabanas.activa cambió (now=% vs baseline=%).',
      v_activa_now, current_setting('promo.b1_activa_baseline'); END IF;

  -- A9 (hardening): 0 grants Data API/PUBLIC en tablas nuevas
  SELECT count(*) INTO v_grants_tbl FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) acl
   WHERE n.nspname='public' AND c.relname IN ('zonas','cabana_zona')
     AND acl.grantee = ANY (v_dataapi);
  IF v_grants_tbl <> 0 THEN RAISE EXCEPTION 'ASSERT A9: grants Data API/PUBLIC en tablas nuevas=% (esperado 0).', v_grants_tbl; END IF;

  -- A10 (hardening): 0 grants en la secuencia zonas_id_zona_seq
  SELECT count(*) INTO v_grants_seq FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) acl
   WHERE n.nspname='public' AND c.relname='zonas_id_zona_seq' AND acl.grantee = ANY (v_dataapi);
  IF v_grants_seq <> 0 THEN RAISE EXCEPTION 'ASSERT A10: grants en zonas_id_zona_seq=% (esperado 0).', v_grants_seq; END IF;

  -- A11 (hardening): seam SIN EXECUTE a Data API/PUBLIC (contempla proacl NULL = abierto)
  SELECT count(*) INTO v_exec_seam FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='resolver_beneficiario'
     AND (p.proacl IS NULL
          OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                     WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY (v_dataapi)));
  IF v_exec_seam <> 0 THEN RAISE EXCEPTION 'ASSERT A11: seam abierto a EXECUTE Data API/PUBLIC (=%).', v_exec_seam; END IF;

  -- A12: 9C NO introduce EXCLUDE/rangos — EXCLUDE en public sigue = 2 (es 9D quien suma)
  SELECT count(*) INTO v_excl_public FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
   WHERE con.contype='x' AND n.nspname='public';
  IF v_excl_public <> 2 THEN RAISE EXCEPTION 'ASSERT A12: EXCLUDE en public=% (esperado 2; 9C no agrega).', v_excl_public; END IF;

  RAISE NOTICE 'ASSERTS B1 OK — 9C consistente. Listo para COMMIT.';
END
$assert$;

COMMIT;

-- ============================================================================
-- 6. VERIFICACIÓN READ-ONLY POSTERIOR (fuera de la transacción).
--    Es el result set que muestra el SQL Editor. Devolvé esta tabla.
-- ============================================================================
WITH dataapi AS (
  SELECT array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL) AS oids),
m AS (
  SELECT
    (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='cabanas'
        AND column_name IN ('valor_relativo','id_socio_beneficiario') AND is_nullable='NO') AS cols_nn,
    (SELECT count(*) FROM cabanas WHERE valor_relativo IS NULL OR id_socio_beneficiario IS NULL) AS nulls,
    (SELECT count(*) FROM zonas) AS zonas,
    (SELECT count(*) FROM cabana_zona) AS cz,
    (SELECT count(*) FROM (VALUES ('Arrebol',100,'Franco'),('Madre Selva',100,'Rodrigo'),
        ('Bamboo',100,'Remo'),('Guatemala',78,'Franco'),('Tokio',78,'Remo')) e(nom,val,ben)
      JOIN cabanas c ON c.nombre=e.nom JOIN socios s ON s.id_socio=c.id_socio_beneficiario
      WHERE c.valor_relativo=e.val AND s.nombre=e.ben) AS seed_ok,
    (SELECT count(*) FROM cabanas c WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01')=c.id_socio_beneficiario) AS seam_ok,
    (SELECT valor FROM configuracion_general WHERE clave='ambiente') AS marcador,
    (SELECT md5(string_agg(id_cabana::text||':'||activa::text, ',' ORDER BY id_cabana)) FROM cabanas) AS activa_md5,
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
       CROSS JOIN LATERAL aclexplode(c.relacl) acl, dataapi
      WHERE n.nspname='public' AND c.relname IN ('zonas','cabana_zona') AND acl.grantee = ANY (dataapi.oids)) AS grants_tbl,
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
       CROSS JOIN LATERAL aclexplode(c.relacl) acl, dataapi
      WHERE n.nspname='public' AND c.relname='zonas_id_zona_seq' AND acl.grantee = ANY (dataapi.oids)) AS grants_seq,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace, dataapi
      WHERE n.nspname='public' AND p.proname='resolver_beneficiario'
        AND (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
             WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY (dataapi.oids)))) AS exec_seam,
    (SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
      WHERE con.contype='x' AND n.nspname='public') AS excl_public
)
SELECT v.orden, v.chequeo, v.obtenido, v.esperado,
       CASE WHEN v.veredicto='INFO' THEN 'INFO' WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (1,'Columnas valor_relativo + beneficiario NOT NULL', m.cols_nn::text,'2',(m.cols_nn=2),'CHK'),
  (2,'Sin NULLs en columnas nuevas', m.nulls::text,'0',(m.nulls=0),'CHK'),
  (3,'zonas (grandes/chicas)', m.zonas::text,'2',(m.zonas=2),'CHK'),
  (4,'cabana_zona (pertenencias)', m.cz::text,'5',(m.cz=5),'CHK'),
  (5,'Seed real correcto (valor+beneficiario)', m.seed_ok::text,'5',(m.seed_ok=5),'CHK'),
  (6,'Seam resuelve beneficiario', m.seam_ok::text,'5',(m.seam_ok=5),'CHK'),
  (7,'Marcador ambiente', m.marcador,'ops',(m.marcador='ops'),'CHK'),
  (8,'Grants Data API/PUBLIC en tablas nuevas', m.grants_tbl::text,'0',(m.grants_tbl=0),'CHK'),
  (9,'Grants en secuencia zonas_id_zona_seq', m.grants_seq::text,'0',(m.grants_seq=0),'CHK'),
  (10,'Seam abierto a EXECUTE Data API/PUBLIC', m.exec_seam::text,'0',(m.exec_seam=0),'CHK'),
  (11,'EXCLUDE en public (9C no agrega)', m.excl_public::text,'2',(m.excl_public=2),'CHK'),
  (12,'Fingerprint cabanas.activa (comparar vs A-bis 0b4e3cb47324…)', left(m.activa_md5,12)||'…','(INFO)',true,'INFO')
) AS v(orden, chequeo, obtenido, esperado, ok, veredicto)
UNION ALL
SELECT 999,'TOTAL B1 (9C)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES
     (m.cols_nn=2),(m.nulls=0),(m.zonas=2),(m.cz=5),(m.seed_ok=5),(m.seam_ok=5),
     (m.marcador='ops'),(m.grants_tbl=0),(m.grants_seq=0),(m.exec_seam=0),(m.excl_public=2)
   ) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES
     (m.cols_nn=2),(m.nulls=0),(m.zonas=2),(m.cz=5),(m.seed_ok=5),(m.seam_ok=5),
     (m.marcador='ops'),(m.grants_tbl=0),(m.grants_seq=0),(m.exec_seam=0),(m.excl_public=2)
   ) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;

-- ============================================================================
-- 7. REVERSIÓN CONCEPTUAL (NO ejecutar; sin DROP ... CASCADE).
--    Orden por dependencias: seam → cabana_zona → zonas → columnas → marcador.
--    Cada DROP es directo (sin CASCADE); como en OPS estos objetos no tienen
--    dependientes externos, ningún DROP necesita CASCADE. Revisar dependencias
--    antes de correr (D-PROMO: prod real).
-- ----------------------------------------------------------------------------
-- BEGIN;
--   DROP FUNCTION IF EXISTS resolver_beneficiario(BIGINT, DATE);   -- sin CASCADE
--   DROP INDEX  IF EXISTS idx_cabana_zona_id_zona;
--   DROP TABLE  IF EXISTS cabana_zona;                              -- antes que zonas (FK)
--   DROP TABLE  IF EXISTS zonas;                                    -- arrastra zonas_id_zona_seq
--   ALTER TABLE cabanas DROP COLUMN IF EXISTS id_socio_beneficiario; -- arrastra su FK
--   ALTER TABLE cabanas DROP COLUMN IF EXISTS valor_relativo;        -- arrastra su CHECK
--   DELETE FROM configuracion_general WHERE clave='ambiente';
-- COMMIT;
-- ============================================================================
