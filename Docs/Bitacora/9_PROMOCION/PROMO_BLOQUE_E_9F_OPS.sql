-- ============================================================================
-- PROMO_BLOQUE_E_9F_OPS.sql
-- Promoción del Carril B a OPS — BLOQUE E (solo 9F: ESTRUCTURA).
-- Etapa PROMO. Depende de B1 (9C), C (9D) y D (9E) commiteados y VERDE en OPS.
-- Contenido: tabla gastos_internos (17 columnas + 18 constraints + índice).
-- NO incluye el fixture de laboratorio (5 gastos ids 30-34, D-9F-17): la
-- promoción recrea ESTRUCTURA, no copia datos de TEST. La tabla queda VACÍA y
-- la secuencia en 1 (OPS arranca prístino, sin gap de smokes).
-- NO toca la legacy `gastos` (D-9F-01: queda intacta), ni 9C/9D/9E/9G/9H ni 9B.
--
-- DDL verbatim de 9F_CIERRE.md §6. Las constraints (14 CHECK + 3 FK + PK) hacen
-- estructuralmente imposibles las incoherencias del §7.4 del conceptual; su
-- COMPORTAMIENTO se validó en harness con smokes negativos (no se ejecutan acá
-- para no consumir la secuencia ni ensuciar OPS — esos smokes fueron Bloque C de
-- 9F en TEST; el DDL es idéntico). Acá se verifica su EXISTENCIA por nombre.
--
-- ESTRUCTURA: BEGIN → gate → prechecks (captura legacy + fingerprint) → DDL →
-- hardening → asserts → COMMIT → verificación read-only posterior → reversión
-- sin DROP ... CASCADE. Correr con NADA seleccionado (L-8A-01).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. GATE — marcador ops + identidad + 9C/9D/9E presentes (orden) + 9F ausente.
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb       text;
  v_cab_real  int;
  v_soc_real  int;
  v_9c_zonas  int;
  v_9d_filas  int;
  v_9e_fns    int;
  v_9f_tabla  int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE E: marcador ambiente=% (esperado ops).', COALESCE(v_amb,'<ausente>'); END IF;

  SELECT count(*) INTO v_cab_real FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
   WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  SELECT count(*) INTO v_soc_real FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
   WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1;
  IF v_cab_real <> 5 OR v_soc_real <> 3 THEN
    RAISE EXCEPTION 'GATE E: identidad no coincide (cabañas=%/5, socios=%/3).', v_cab_real, v_soc_real; END IF;

  -- 9C (zonas: dependencia real de la FK), 9D y 9E (orden de la promoción)
  SELECT count(*) INTO v_9c_zonas FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r' AND c.relname='zonas';
  SELECT count(*) INTO v_9d_filas FROM activaciones_operativas;
  SELECT count(*) INTO v_9e_fns FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('matriz_participacion','repartir_por_matriz','detalle_participacion');
  IF v_9c_zonas <> 1 THEN RAISE EXCEPTION 'GATE E: zonas (9C) ausente — correr B1.'; END IF;
  IF v_9d_filas <> 5 THEN RAISE EXCEPTION 'GATE E: activaciones (9D)=% (esperado 5) — correr C.', v_9d_filas; END IF;
  IF v_9e_fns  <> 3 THEN RAISE EXCEPTION 'GATE E: funciones 9E=% (esperado 3) — correr D.', v_9e_fns; END IF;

  -- 9F ausente — guard de re-ejecución
  SELECT count(*) INTO v_9f_tabla FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r' AND c.relname='gastos_internos';
  IF v_9f_tabla <> 0 THEN RAISE EXCEPTION 'GATE E: gastos_internos ya existe. E no se re-ejecuta.'; END IF;

  RAISE NOTICE 'GATE E OK — OPS post-9E; gastos_internos ausente.';
END
$gate$;

-- ----------------------------------------------------------------------------
-- 2. PRECHECK — captura del estado de la legacy `gastos` (D-9F-01: no se toca)
--    y del fingerprint de cabanas.activa (9F no toca cabanas).
-- ----------------------------------------------------------------------------
DO $pre$
DECLARE v_legacy int; v_md5 text;
BEGIN
  IF to_regclass('public.gastos') IS NULL THEN
    RAISE EXCEPTION 'PRECHECK E: la legacy `gastos` no existe (esperada por paridad 8A).'; END IF;
  EXECUTE 'SELECT count(*) FROM gastos' INTO v_legacy;
  PERFORM set_config('promo.e_legacy_gastos', v_legacy::text, true);
  SELECT md5(string_agg(id_cabana::text||':'||activa::text, ',' ORDER BY id_cabana)) INTO v_md5 FROM cabanas;
  PERFORM set_config('promo.e_activa_baseline', v_md5, true);
  RAISE NOTICE 'PRECHECK E OK — legacy gastos filas=%, baseline activa=%', v_legacy, v_md5;
END
$pre$;

-- ----------------------------------------------------------------------------
-- 3. DDL (9F) — tabla gastos_internos (verbatim 9F §6) + índice. SIN INSERT.
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 4. HARDENING — REVOKE sobre tabla + secuencia, a PUBLIC + roles Data API.
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE gastos_internos FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE gastos_internos_id_gasto_seq FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. ASSERTS FINALES (DO + RAISE).
-- ----------------------------------------------------------------------------
DO $assert$
DECLARE
  v_cols        int;
  v_constr      int;
  v_fk          int;
  v_chk         int;
  v_idx         int;
  v_filas       int;
  v_seq_last    bigint;
  v_seq_called  boolean;
  v_clave_chks  int;
  v_grants_tbl  int;
  v_grants_seq  int;
  v_legacy_now  int;
  v_activa_now  text;
  v_excl_total  int;
  v_dataapi     oid[];
BEGIN
  v_dataapi := array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL);

  -- E1: 17 columnas
  SELECT count(*) INTO v_cols FROM information_schema.columns
   WHERE table_schema='public' AND table_name='gastos_internos';
  IF v_cols <> 17 THEN RAISE EXCEPTION 'ASSERT E1: columnas=% (esperado 17).', v_cols; END IF;

  -- E2: 18 constraints en la tabla (14 CHECK + 3 FK + 1 PK)
  SELECT count(*) INTO v_constr FROM pg_constraint WHERE conrelid='gastos_internos'::regclass;
  SELECT count(*) INTO v_fk  FROM pg_constraint WHERE conrelid='gastos_internos'::regclass AND contype='f';
  SELECT count(*) INTO v_chk FROM pg_constraint WHERE conrelid='gastos_internos'::regclass AND contype='c';
  IF v_constr <> 18 OR v_fk <> 3 OR v_chk <> 14 THEN
    RAISE EXCEPTION 'ASSERT E2: constraints total=%/fk=%/chk=% (esperado 18/3/14).', v_constr, v_fk, v_chk; END IF;

  -- E3: constraints clave presentes por nombre (las que blindan §7.4 del conceptual)
  SELECT count(*) INTO v_clave_chks FROM pg_constraint
   WHERE conrelid='gastos_internos'::regclass
     AND conname IN ('chk_gastos_internos_alcance_por_clase','chk_gastos_internos_pagador_consistente',
                     'chk_gastos_internos_periodo_normalizado','chk_gastos_internos_comentario_requerido',
                     'chk_gastos_internos_horas_pagador_socio','chk_gastos_internos_moneda',
                     'fk_gastos_internos_zona','fk_gastos_internos_cabana','fk_gastos_internos_socio_pagador');
  IF v_clave_chks <> 9 THEN RAISE EXCEPTION 'ASSERT E3: constraints clave por nombre=% (esperado 9).', v_clave_chks; END IF;

  -- E4: índice presente
  SELECT count(*) INTO v_idx FROM pg_class WHERE relname='idx_gastos_internos_periodo_clase' AND relkind='i';
  IF v_idx <> 1 THEN RAISE EXCEPTION 'ASSERT E4: índice=% (esperado 1).', v_idx; END IF;

  -- E5: tabla VACÍA (sin fixture, D-9F-17) y secuencia sin usar (OPS prístino)
  SELECT count(*) INTO v_filas FROM gastos_internos;
  SELECT last_value, is_called INTO v_seq_last, v_seq_called FROM gastos_internos_id_gasto_seq;
  IF v_filas <> 0 THEN RAISE EXCEPTION 'ASSERT E5a: gastos_internos tiene % filas (esperado 0, sin fixture).', v_filas; END IF;
  IF v_seq_called THEN RAISE EXCEPTION 'ASSERT E5b: secuencia ya usada (is_called=true); OPS debe arrancar en 1.'; END IF;

  -- E6 (hardening): 0 grants Data API/PUBLIC en tabla y secuencia
  SELECT count(*) INTO v_grants_tbl FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) acl
   WHERE n.nspname='public' AND c.relname='gastos_internos' AND acl.grantee = ANY (v_dataapi);
  SELECT count(*) INTO v_grants_seq FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) acl
   WHERE n.nspname='public' AND c.relname='gastos_internos_id_gasto_seq' AND acl.grantee = ANY (v_dataapi);
  IF v_grants_tbl <> 0 OR v_grants_seq <> 0 THEN
    RAISE EXCEPTION 'ASSERT E6: grants Data API/PUBLIC tabla=%/secuencia=% (esperado 0/0).', v_grants_tbl, v_grants_seq; END IF;

  -- E7 (D-9F-01): la legacy `gastos` quedó intacta (mismo conteo que el precheck)
  EXECUTE 'SELECT count(*) FROM gastos' INTO v_legacy_now;
  IF v_legacy_now::text IS DISTINCT FROM current_setting('promo.e_legacy_gastos') THEN
    RAISE EXCEPTION 'ASSERT E7: legacy gastos cambió (now=% vs baseline=%).',
      v_legacy_now, current_setting('promo.e_legacy_gastos'); END IF;

  -- E8: cabanas.activa SIN cambios (9F no toca cabanas)
  SELECT md5(string_agg(id_cabana::text||':'||activa::text, ',' ORDER BY id_cabana)) INTO v_activa_now FROM cabanas;
  IF v_activa_now <> current_setting('promo.e_activa_baseline') THEN
    RAISE EXCEPTION 'ASSERT E8: cabanas.activa cambió.'; END IF;

  -- E9 (aislamiento): 9F no agrega EXCLUDE ⇒ EXCLUDE en public sigue = 3
  SELECT count(*) INTO v_excl_total FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
   WHERE con.contype='x' AND n.nspname='public';
  IF v_excl_total <> 3 THEN RAISE EXCEPTION 'ASSERT E9: EXCLUDE en public=% (esperado 3).', v_excl_total; END IF;

  RAISE NOTICE 'ASSERTS E OK — 9F estructura consistente, tabla vacía, legacy intacta. Listo para COMMIT.';
END
$assert$;

COMMIT;

-- ============================================================================
-- 6. VERIFICACIÓN READ-ONLY POSTERIOR (fuera de la transacción).
-- ============================================================================
WITH dataapi AS (
  SELECT array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL) AS oids),
m AS (
  SELECT
    (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='gastos_internos') AS cols,
    (SELECT count(*) FROM pg_constraint WHERE conrelid='gastos_internos'::regclass) AS constr,
    (SELECT count(*) FROM pg_constraint WHERE conrelid='gastos_internos'::regclass AND contype='f') AS fk,
    (SELECT count(*) FROM pg_constraint WHERE conrelid='gastos_internos'::regclass AND contype='c') AS chk,
    (SELECT count(*) FROM pg_class WHERE relname='idx_gastos_internos_periodo_clase' AND relkind='i') AS idx,
    (SELECT count(*) FROM gastos_internos) AS filas,
    (SELECT is_called FROM gastos_internos_id_gasto_seq) AS seq_called,
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) acl, dataapi
      WHERE n.nspname='public' AND c.relname='gastos_internos' AND acl.grantee = ANY (dataapi.oids)) AS grants_tbl,
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) acl, dataapi
      WHERE n.nspname='public' AND c.relname='gastos_internos_id_gasto_seq' AND acl.grantee = ANY (dataapi.oids)) AS grants_seq,
    (SELECT count(*) FROM gastos) AS legacy,
    (SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE con.contype='x' AND n.nspname='public') AS excl_total
)
SELECT v.orden, v.chequeo, v.obtenido, v.esperado,
       CASE WHEN v.veredicto='INFO' THEN 'INFO' WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (1,'gastos_internos: columnas', m.cols::text,'17',(m.cols=17),'CHK'),
  (2,'constraints totales', m.constr::text,'18',(m.constr=18),'CHK'),
  (3,'FK / CHECK', m.fk||' / '||m.chk,'3 / 14',(m.fk=3 AND m.chk=14),'CHK'),
  (4,'índice periodo+clase', m.idx::text,'1',(m.idx=1),'CHK'),
  (5,'tabla vacía (sin fixture)', m.filas::text,'0',(m.filas=0),'CHK'),
  (6,'secuencia sin usar (arranca en 1)', m.seq_called::text,'false',(m.seq_called=false),'CHK'),
  (7,'grants Data API/PUBLIC en tabla', m.grants_tbl::text,'0',(m.grants_tbl=0),'CHK'),
  (8,'grants en secuencia', m.grants_seq::text,'0',(m.grants_seq=0),'CHK'),
  (9,'legacy gastos intacta (filas)', m.legacy::text,'0',(m.legacy=0),'CHK'),
  (10,'EXCLUDE public (9F no agrega)', m.excl_total::text,'3',(m.excl_total=3),'CHK')
) AS v(orden, chequeo, obtenido, esperado, ok, veredicto)
UNION ALL
SELECT 999,'TOTAL E (9F estructura)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES
     (m.cols=17),(m.constr=18),(m.fk=3 AND m.chk=14),(m.idx=1),(m.filas=0),(m.seq_called=false),
     (m.grants_tbl=0),(m.grants_seq=0),(m.legacy=0),(m.excl_total=3)
   ) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES
     (m.cols=17),(m.constr=18),(m.fk=3 AND m.chk=14),(m.idx=1),(m.filas=0),(m.seq_called=false),
     (m.grants_tbl=0),(m.grants_seq=0),(m.legacy=0),(m.excl_total=3)
   ) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;

-- ============================================================================
-- 7. REVERSIÓN CONCEPTUAL (NO ejecutar; sin DROP ... CASCADE).
--    Una tabla; su DROP arrastra índice, secuencia, FKs y CHECKs propios.
--    La legacy `gastos` NO se toca. Nada depende de gastos_internos todavía
--    (9G la leerá, pero aún no existe).
-- ----------------------------------------------------------------------------
-- BEGIN;
--   DROP TABLE IF EXISTS gastos_internos;   -- sin CASCADE
-- COMMIT;
-- ============================================================================
