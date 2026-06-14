-- ============================================================================
-- PROMO_BLOQUE_C_9D_OPS.sql
-- Promoción del Carril B a OPS — BLOQUE C (solo 9D).
-- Etapa PROMO. Depende de B1 (9C) ya commiteado y VERDE en OPS.
-- Contenido: tabla activaciones_operativas (CHECK + EXCLUDE gist + índice) +
-- carga del POOL REAL (D-9D-10). NO toca 9C/9E/9F/9G/9H ni helper 9B.
--
-- Pool real (D-9D-10, fechas reales — las mismas de TEST):
--   Bamboo / Madre Selva / Arrebol / Tokio : desde 2026-07-01 (fecha_hasta NULL = abierta)
--   Guatemala : desde 2026-11-01 (desactivada jul-oct 2026 inclusive)
--
-- ESTRUCTURA: BEGIN → gate (ahora PRIMARIO por marcador ambiente='ops' + identidad
-- estructural + 9C presente + ausencia 9D) → prechecks → DDL + seed → hardening →
-- smoke EXCLUDE (savepoint, sin residuo) → asserts → COMMIT → verificación
-- read-only posterior → reversión sin DROP ... CASCADE.
--
-- Observación incorporada (revisión B1): los checks de EXCLUDE filtran por
-- schema + tabla + nombre, no solo por nombre/total.
--
-- Correr con NADA seleccionado (L-8A-01). Pool resuelto POR NOMBRE.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. GATE — primario por marcador ambiente='ops' (creado en B1) + identidad
--    estructural + 9C presente + 9D ausente. RAISE aborta toda la transacción.
--    Captura fingerprint de cabanas.activa para el assert final.
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb         text;
  v_cab_real    int;
  v_soc_real    int;
  v_9c_cols     int;
  v_9c_zonas    int;
  v_9c_seam     int;
  v_9d_tabla    int;
  v_btree       int;
  v_activa_md5  text;
BEGIN
  -- (a) Marcador de ambiente = 'ops' (gate primario; ya existe tras B1)
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE C: marcador ambiente=% (esperado ops). 9D solo corre en OPS tras B1.', COALESCE(v_amb,'<ausente>');
  END IF;

  -- (b) Identidad estructural (defensa en profundidad, L-7E-01)
  SELECT count(*) INTO v_cab_real FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
   WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  SELECT count(*) INTO v_soc_real FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
   WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1;
  IF v_cab_real <> 5 OR v_soc_real <> 3 THEN
    RAISE EXCEPTION 'GATE C: identidad no coincide (cabañas=%/5, socios=%/3).', v_cab_real, v_soc_real;
  END IF;

  -- (c) 9C presente (B1): columnas, zonas, seam
  SELECT count(*) INTO v_9c_cols FROM information_schema.columns
   WHERE table_schema='public' AND table_name='cabanas'
     AND column_name IN ('valor_relativo','id_socio_beneficiario');
  SELECT count(*) INTO v_9c_zonas FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r' AND c.relname='zonas';
  SELECT count(*) INTO v_9c_seam FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='resolver_beneficiario';
  IF v_9c_cols <> 2 OR v_9c_zonas <> 1 OR v_9c_seam <> 1 THEN
    RAISE EXCEPTION 'GATE C: 9C incompleto (cols=%, zonas=%, seam=%). Correr B1 primero.', v_9c_cols, v_9c_zonas, v_9c_seam;
  END IF;

  -- (d) Ausencia de 9D — guard de re-ejecución
  SELECT count(*) INTO v_9d_tabla FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r' AND c.relname='activaciones_operativas';
  IF v_9d_tabla <> 0 THEN
    RAISE EXCEPTION 'GATE C: activaciones_operativas ya existe. C no se re-ejecuta.';
  END IF;

  -- (e) btree_gist disponible (necesario para el EXCLUDE gist)
  SELECT count(*) INTO v_btree FROM pg_extension WHERE extname='btree_gist';
  IF v_btree <> 1 THEN RAISE EXCEPTION 'GATE C: btree_gist ausente; el EXCLUDE gist no se puede crear.'; END IF;

  -- (f) Fingerprint de cabanas.activa (transaccional)
  SELECT md5(string_agg(id_cabana::text||':'||activa::text, ',' ORDER BY id_cabana)) INTO v_activa_md5 FROM cabanas;
  PERFORM set_config('promo.c_activa_baseline', v_activa_md5, true);

  RAISE NOTICE 'GATE C OK — OPS con 9C presente. Baseline activa=%', v_activa_md5;
END
$gate$;

-- ----------------------------------------------------------------------------
-- 2. PRECHECK — EXCLUDE de base por schema+tabla+nombre (estado de partida).
-- ----------------------------------------------------------------------------
DO $pre$
DECLARE v_excl_base int;
BEGIN
  SELECT count(*) INTO v_excl_base
  FROM pg_constraint con
  JOIN pg_namespace n ON n.oid=con.connamespace
  JOIN pg_class t ON t.oid=con.conrelid
  WHERE con.contype='x' AND n.nspname='public'
    AND ( (con.conname='exc_reservas_no_overlap' AND t.relname='reservas')
       OR (con.conname='exc_bloqueos_no_overlap' AND t.relname='bloqueos') );
  IF v_excl_base <> 2 THEN
    RAISE EXCEPTION 'PRECHECK C: EXCLUDE de base por schema+tabla+nombre=% (esperado 2).', v_excl_base;
  END IF;
END
$pre$;

-- ----------------------------------------------------------------------------
-- 3. DDL + SEED REAL (9D).
-- ----------------------------------------------------------------------------

-- 3.1 Tabla activaciones_operativas (D-9D-01..05): rango [) + EXCLUDE gist por cabaña
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

-- 3.2 Carga del POOL REAL (D-9D-10) — idempotente, por nombre
INSERT INTO activaciones_operativas (id_cabana, fecha_desde, fecha_hasta, creado_por, comentario)
SELECT c.id_cabana, v.desde, NULL, 'promo_9d', v.coment
FROM (VALUES
    ('Bamboo',      DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Madre Selva', DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Arrebol',     DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Tokio',       DATE '2026-07-01', 'Pool inicial desde inicio de contabilidad formal (D-9D-10)'),
    ('Guatemala',   DATE '2026-11-01', 'Desactivada jul-oct 2026 inclusive; activa desde nov (D-9D-10)')
) AS v(cab_nombre, desde, coment)
JOIN cabanas c ON c.nombre = v.cab_nombre
WHERE NOT EXISTS (SELECT 1 FROM activaciones_operativas a WHERE a.id_cabana = c.id_cabana);

-- ----------------------------------------------------------------------------
-- 4. HARDENING (misma transacción, antes del COMMIT).
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE activaciones_operativas FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE activaciones_operativas_id_activacion_seq FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. SMOKE del EXCLUDE (savepoint interno, sin residuo): un solapamiento sobre
--    la activación abierta de Bamboo debe ser rechazado con 23P01. Si NO se
--    rechaza, se aborta toda la transacción (garantía estructural rota).
-- ----------------------------------------------------------------------------
DO $smoke$
BEGIN
  BEGIN
    INSERT INTO activaciones_operativas (id_cabana, fecha_desde, fecha_hasta, creado_por)
    VALUES ((SELECT id_cabana FROM cabanas WHERE nombre='Bamboo'), DATE '2026-08-01', NULL, 'smoke_overlap');
    RAISE EXCEPTION 'SMOKE C: el solapamiento NO fue rechazado — garantía EXCLUDE rota.';
  EXCEPTION
    WHEN exclusion_violation THEN
      RAISE NOTICE 'SMOKE C OK — solapamiento rechazado (23P01). Sin residuo (rollback a savepoint).';
  END;
END
$smoke$;

-- ----------------------------------------------------------------------------
-- 6. ASSERTS FINALES (DO + RAISE).
-- ----------------------------------------------------------------------------
DO $assert$
DECLARE
  v_filas        int;
  v_abiertas     int;
  v_guate        date;
  v_jul          int;
  v_oct          int;
  v_nov          int;
  v_excl_activ   int;   -- exc_activaciones por schema+tabla+nombre
  v_excl_total   int;   -- total EXCLUDE en public (debe ser 3 ahora)
  v_idx          int;
  v_grants_tbl   int;
  v_grants_seq   int;
  v_activa_now   text;
  v_dataapi      oid[];
BEGIN
  v_dataapi := array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL);

  -- C1: 5 activaciones, todas abiertas (fecha_hasta NULL)
  SELECT count(*) INTO v_filas FROM activaciones_operativas;
  SELECT count(*) INTO v_abiertas FROM activaciones_operativas WHERE fecha_hasta IS NULL;
  IF v_filas <> 5 OR v_abiertas <> 5 THEN
    RAISE EXCEPTION 'ASSERT C1: filas=% (esp 5), abiertas=% (esp 5).', v_filas, v_abiertas; END IF;

  -- C2: Guatemala desde 2026-11-01; las otras 4 desde 2026-07-01
  SELECT a.fecha_desde INTO v_guate FROM activaciones_operativas a
    JOIN cabanas c ON c.id_cabana=a.id_cabana WHERE c.nombre='Guatemala';
  IF v_guate <> DATE '2026-11-01' THEN
    RAISE EXCEPTION 'ASSERT C2: Guatemala fecha_desde=% (esperado 2026-11-01).', v_guate; END IF;

  -- C3: pool por mes vía daterange @> mes — jul=4, oct=4, nov=5
  SELECT count(*) INTO v_jul FROM activaciones_operativas a
    WHERE daterange(a.fecha_desde,a.fecha_hasta,'[)') @> daterange(DATE '2026-07-01',DATE '2026-08-01','[)');
  SELECT count(*) INTO v_oct FROM activaciones_operativas a
    WHERE daterange(a.fecha_desde,a.fecha_hasta,'[)') @> daterange(DATE '2026-10-01',DATE '2026-11-01','[)');
  SELECT count(*) INTO v_nov FROM activaciones_operativas a
    WHERE daterange(a.fecha_desde,a.fecha_hasta,'[)') @> daterange(DATE '2026-11-01',DATE '2026-12-01','[)');
  IF v_jul <> 4 OR v_oct <> 4 OR v_nov <> 5 THEN
    RAISE EXCEPTION 'ASSERT C3: pool jul=%/oct=%/nov=% (esperado 4/4/5).', v_jul, v_oct, v_nov; END IF;

  -- C4 (EXCLUDE por schema+tabla+nombre): exc_activaciones_no_overlap en activaciones_operativas
  SELECT count(*) INTO v_excl_activ FROM pg_constraint con
    JOIN pg_namespace n ON n.oid=con.connamespace JOIN pg_class t ON t.oid=con.conrelid
   WHERE con.contype='x' AND n.nspname='public'
     AND con.conname='exc_activaciones_no_overlap' AND t.relname='activaciones_operativas';
  IF v_excl_activ <> 1 THEN
    RAISE EXCEPTION 'ASSERT C4: EXCLUDE de activaciones por schema+tabla+nombre=% (esperado 1).', v_excl_activ; END IF;

  -- C5: EXCLUDE total en public pasó de 2 a 3 (las 2 base + activaciones)
  SELECT count(*) INTO v_excl_total FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
   WHERE con.contype='x' AND n.nspname='public';
  IF v_excl_total <> 3 THEN
    RAISE EXCEPTION 'ASSERT C5: EXCLUDE en public=% (esperado 3).', v_excl_total; END IF;

  -- C6: índice por cabaña presente
  SELECT count(*) INTO v_idx FROM pg_class WHERE relname='idx_activaciones_cabana' AND relkind='i';
  IF v_idx <> 1 THEN RAISE EXCEPTION 'ASSERT C6: índice idx_activaciones_cabana=% (esperado 1).', v_idx; END IF;

  -- C7 (hardening): 0 grants Data API/PUBLIC en la tabla nueva
  SELECT count(*) INTO v_grants_tbl FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) acl
   WHERE n.nspname='public' AND c.relname='activaciones_operativas' AND acl.grantee = ANY (v_dataapi);
  IF v_grants_tbl <> 0 THEN RAISE EXCEPTION 'ASSERT C7: grants Data API/PUBLIC en tabla=% (esperado 0).', v_grants_tbl; END IF;

  -- C8 (hardening): 0 grants en la secuencia
  SELECT count(*) INTO v_grants_seq FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) acl
   WHERE n.nspname='public' AND c.relname='activaciones_operativas_id_activacion_seq' AND acl.grantee = ANY (v_dataapi);
  IF v_grants_seq <> 0 THEN RAISE EXCEPTION 'ASSERT C8: grants en secuencia=% (esperado 0).', v_grants_seq; END IF;

  -- C9: cabanas.activa SIN cambios respecto del baseline del gate
  SELECT md5(string_agg(id_cabana::text||':'||activa::text, ',' ORDER BY id_cabana)) INTO v_activa_now FROM cabanas;
  IF v_activa_now <> current_setting('promo.c_activa_baseline') THEN
    RAISE EXCEPTION 'ASSERT C9: cabanas.activa cambió (now=% vs baseline=%).',
      v_activa_now, current_setting('promo.c_activa_baseline'); END IF;

  RAISE NOTICE 'ASSERTS C OK — 9D consistente. Listo para COMMIT.';
END
$assert$;

COMMIT;

-- ============================================================================
-- 7. VERIFICACIÓN READ-ONLY POSTERIOR (fuera de la transacción).
-- ============================================================================
WITH dataapi AS (
  SELECT array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL) AS oids),
m AS (
  SELECT
    (SELECT count(*) FROM activaciones_operativas) AS filas,
    (SELECT count(*) FROM activaciones_operativas WHERE fecha_hasta IS NULL) AS abiertas,
    (SELECT a.fecha_desde::text FROM activaciones_operativas a JOIN cabanas c ON c.id_cabana=a.id_cabana WHERE c.nombre='Guatemala') AS guate,
    (SELECT count(*) FROM activaciones_operativas a WHERE daterange(a.fecha_desde,a.fecha_hasta,'[)') @> daterange(DATE '2026-07-01',DATE '2026-08-01','[)')) AS jul,
    (SELECT count(*) FROM activaciones_operativas a WHERE daterange(a.fecha_desde,a.fecha_hasta,'[)') @> daterange(DATE '2026-11-01',DATE '2026-12-01','[)')) AS nov,
    (SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace JOIN pg_class t ON t.oid=con.conrelid
      WHERE con.contype='x' AND n.nspname='public' AND con.conname='exc_activaciones_no_overlap' AND t.relname='activaciones_operativas') AS excl_activ,
    (SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE con.contype='x' AND n.nspname='public') AS excl_total,
    (SELECT count(*) FROM pg_class WHERE relname='idx_activaciones_cabana' AND relkind='i') AS idx,
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) acl, dataapi
      WHERE n.nspname='public' AND c.relname='activaciones_operativas' AND acl.grantee = ANY (dataapi.oids)) AS grants_tbl,
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) acl, dataapi
      WHERE n.nspname='public' AND c.relname='activaciones_operativas_id_activacion_seq' AND acl.grantee = ANY (dataapi.oids)) AS grants_seq,
    (SELECT md5(string_agg(id_cabana::text||':'||activa::text, ',' ORDER BY id_cabana)) FROM cabanas) AS activa_md5
)
SELECT v.orden, v.chequeo, v.obtenido, v.esperado,
       CASE WHEN v.veredicto='INFO' THEN 'INFO' WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (1,'Activaciones cargadas (todas abiertas)', m.filas||'/'||m.abiertas,'5/5',(m.filas=5 AND m.abiertas=5),'CHK'),
  (2,'Guatemala desde 2026-11-01', m.guate,'2026-11-01',(m.guate='2026-11-01'),'CHK'),
  (3,'Pool por mes: julio', m.jul::text,'4',(m.jul=4),'CHK'),
  (4,'Pool por mes: noviembre', m.nov::text,'5',(m.nov=5),'CHK'),
  (5,'EXCLUDE activaciones (schema+tabla+nombre)', m.excl_activ::text,'1',(m.excl_activ=1),'CHK'),
  (6,'EXCLUDE total en public (2 base + 9D)', m.excl_total::text,'3',(m.excl_total=3),'CHK'),
  (7,'Índice idx_activaciones_cabana', m.idx::text,'1',(m.idx=1),'CHK'),
  (8,'Grants Data API/PUBLIC en tabla nueva', m.grants_tbl::text,'0',(m.grants_tbl=0),'CHK'),
  (9,'Grants en secuencia', m.grants_seq::text,'0',(m.grants_seq=0),'CHK'),
  (10,'Fingerprint cabanas.activa (vs A-bis 0b4e3cb47324…)', left(m.activa_md5,12)||'…','(INFO)',true,'INFO')
) AS v(orden, chequeo, obtenido, esperado, ok, veredicto)
UNION ALL
SELECT 999,'TOTAL C (9D)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES
     (m.filas=5 AND m.abiertas=5),(m.guate='2026-11-01'),(m.jul=4),(m.nov=5),
     (m.excl_activ=1),(m.excl_total=3),(m.idx=1),(m.grants_tbl=0),(m.grants_seq=0)
   ) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES
     (m.filas=5 AND m.abiertas=5),(m.guate='2026-11-01'),(m.jul=4),(m.nov=5),
     (m.excl_activ=1),(m.excl_total=3),(m.idx=1),(m.grants_tbl=0),(m.grants_seq=0)
   ) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;

-- ============================================================================
-- 8. REVERSIÓN CONCEPTUAL (NO ejecutar; sin DROP ... CASCADE).
--    Una sola tabla; su DROP arrastra índice, secuencia, EXCLUDE, CHECK y FK
--    propios (objetos dependientes DE la tabla, no externos). No hay nada que
--    dependa de activaciones_operativas en 9C, así que no se requiere CASCADE.
-- ----------------------------------------------------------------------------
-- BEGIN;
--   DROP TABLE IF EXISTS activaciones_operativas;   -- sin CASCADE
-- COMMIT;
-- ============================================================================
