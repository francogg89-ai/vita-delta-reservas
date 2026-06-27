-- ============================================================================
-- PROMO_C_BLOQUE_A_SNAPSHOT_OPS.sql
-- Carril C / Portal Operativo Interno — PROMOCIÓN COORDINADA A OPS — BLOQUE A.
-- Snapshot baseline READ-ONLY de OPS. Calca el método del Carril B
-- (PROMO_BLOQUE_A_BIS_SNAPSHOT_v2.sql): un único SELECT, un único result set,
-- gate de identidad por SEED + discriminador de ambiente, fila TOTAL VERDE/FRENAR.
--
-- ESTE BLOQUE NO MODIFICA OPS. Estrictamente read-only:
--   · SIN DDL (ni tablas temporales).
--   · SIN INSERT / UPDATE / DELETE.
--   · SIN secuencias consumidas (ningún nextval; ningún INSERT que dispare SERIAL).
--   · SIN tocar n8n, Vercel ni Auth (no lee auth.users; eso es del Bloque C).
--   · SIN secretos en el output (el marcador 'ambiente' NO es secreto).
--
-- PROPÓSITO:
--   (1) GATE de aptitud: confirmar que se está corriendo contra OPS (no TEST/DEV)
--       y que OPS está LIBRE de la infra del portal (que el Carril C va a crear).
--   (2) BASELINE: fingerprint de contexto/hardening para comparar post-promoción.
--   (3) CATÁLOGO REAL de cabañas OPS (ajuste obligatorio del plan): dump read-only
--       de id/nombre/tipo/capacidades, para que el frontend OPS use el catálogo
--       REAL derivado de OPS (P-FE-01) — NUNCA hardcodeado desde memoria ni asumido
--       igual a TEST. Las cabañas se relevan acá; el Bloque G consume este resultado.
--
-- GATES DUROS (cuentan para FALLO ⇒ FRENAR):
--   A. Identidad/ambiente: cabañas 1-5 reales, total=5, socios Franco/Rodrigo/Remo,
--      placeholder ausente, marcador 'ambiente' presente, y VALOR='ops' (discriminador
--      fuerte de entorno: si el valor no es 'ops', FRENA aunque el seed coincida).
--   B. Ausencia de infra del portal: portal_usuarios, portal_idempotencia y la función
--      portal_cargar_gasto_interno NO deben existir todavía en OPS.
--
-- INFO (no frena): contexto Carril B (debe estar presente: confirma OPS post-9H),
--   salud operativa, hardening baseline (grants Data API, funciones abiertas a EXECUTE
--   contemplando proacl NULL ⇒ PUBLIC ejecuta; excluye funciones de extensión), y el
--   catálogo real de cabañas.
--
-- HABILITA: el DDL del Bloque B (infra del portal) SÓLO con la fila TOTAL en VERDE.
-- ============================================================================
WITH
  cab AS (SELECT id_cabana, nombre, tipo, capacidad_base, capacidad_max, activa FROM cabanas),
  dataapi AS (  -- OIDs de los roles Data API; 0 = PUBLIC
    SELECT array_remove(ARRAY[
      0::oid,
      (SELECT oid FROM pg_roles WHERE rolname='anon'),
      (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
      (SELECT oid FROM pg_roles WHERE rolname='service_role')
    ], NULL) AS oids
  ),
  m AS (
    SELECT
      -- A. Identidad por seed -------------------------------------------------
      (SELECT count(*) FROM cab) AS cab_total,
      (SELECT count(*) FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
        WHERE EXISTS (SELECT 1 FROM cab c WHERE c.id_cabana=e.id AND c.nombre=e.nom)) AS cab_real,
      (SELECT count(*) FROM socios) AS soc_total,
      (SELECT count(*) FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
        WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1) AS soc_real,
      (SELECT count(*) FROM socios WHERE nombre='Socio 3') AS soc_placeholder,
      -- A. Discriminador de ambiente (marcador canónico) ---------------------
      (SELECT count(*) FROM configuracion_general WHERE clave='ambiente') AS amb_present,
      (SELECT valor FROM configuracion_general WHERE clave='ambiente') AS amb_valor,
      -- B. Ausencia de infra del portal (Carril C la creará) -----------------
      (to_regclass('public.portal_usuarios')      IS NULL) AS pu_ausente,
      (to_regclass('public.portal_idempotencia')  IS NULL) AS pi_ausente,
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='portal_cargar_gasto_interno') AS pf_count,
      -- C. Contexto Carril B (INFO — debe estar presente en OPS post-9H) ------
      (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relkind='r'
          AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos',
                            'liquidaciones_periodo','liquidacion_cascada','liquidacion_socio',
                            'movimientos_socio','revaluaciones')) AS tbl_carrilb,
      (SELECT count(*) FROM information_schema.columns
        WHERE table_schema='public' AND table_name='cabanas'
          AND column_name IN ('valor_relativo','id_socio_beneficiario')) AS col_carrilb,
      -- D. Salud operativa (INFO) --------------------------------------------
      (SELECT count(*) FROM reservas) AS reservas_n,
      (SELECT count(*) FROM bloqueos) AS bloqueos_n,
      (SELECT count(*) FROM pagos)    AS pagos_n,
      (SELECT (to_regclass('cron.job') IS NOT NULL)) AS cron_present,
      -- E. Hardening baseline (INFO — fingerprint para comparar post-promoción)
      (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        CROSS JOIN LATERAL aclexplode(c.relacl) acl, dataapi
        WHERE n.nspname='public' AND c.relkind='r'
          AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
          AND acl.grantee = ANY (dataapi.oids)) AS grants_tbl_dataapi,
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.prokind='f'
          AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')
          AND (
            p.proacl IS NULL
            OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a, dataapi
                       WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY (dataapi.oids))
          )) AS fn_exec_abiertas,
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.prokind='f'
          AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')) AS fn_propias_total,
      (SELECT md5(string_agg(id_cabana::text||':'||activa::text, ',' ORDER BY id_cabana)) FROM cab) AS activa_md5
  )
-- ============================ REPORTE (único result set) =====================
-- Parte 1: checks (CHK = gate duro; INFO = relevamiento).
SELECT v.orden, v.seccion, v.chequeo, v.obtenido, v.esperado,
       CASE WHEN v.veredicto='INFO' THEN 'INFO' WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  -- A. Identidad / ambiente (gate duro) --------------------------------------
  (10,'A. Identidad (gate seed)','Cabañas 1-5 reales presentes', m.cab_real||' de 5','5',(m.cab_real=5),'CHK'),
  (11,'A. Identidad (gate seed)','Total de cabañas', m.cab_total::text,'5',(m.cab_total=5),'CHK'),
  (12,'A. Identidad (gate seed)','Socios Franco/Rodrigo/Remo presentes', m.soc_real||' de 3','3',(m.soc_real=3),'CHK'),
  (13,'A. Identidad (gate seed)','Placeholder "Socio 3" ausente', m.soc_placeholder::text,'0',(m.soc_placeholder=0),'CHK'),
  (14,'A. Identidad (gate seed)','Total de socios', m.soc_total::text,'3',(m.soc_total=3),'CHK'),
  (15,'A. Ambiente (discriminador)','Marcador "ambiente" presente', m.amb_present::text,'1',(m.amb_present=1),'CHK'),
  (16,'A. Ambiente (discriminador)','Valor del marcador = ops (entorno correcto)', COALESCE(m.amb_valor,'(ausente)'),'ops',COALESCE((m.amb_valor='ops'),false),'CHK'),
  (17,'A. Ambiente (discriminador)','Valor real del marcador (transparencia)', COALESCE(m.amb_valor,'(ausente)'),'(INFO)',true,'INFO'),
  -- B. Ausencia de infra del portal (gate duro) ------------------------------
  (20,'B. Infra portal ausente','portal_usuarios NO existe aún', CASE WHEN m.pu_ausente THEN 'ausente' ELSE 'PRESENTE' END,'ausente',m.pu_ausente,'CHK'),
  (21,'B. Infra portal ausente','portal_idempotencia NO existe aún', CASE WHEN m.pi_ausente THEN 'ausente' ELSE 'PRESENTE' END,'ausente',m.pi_ausente,'CHK'),
  (22,'B. Infra portal ausente','portal_cargar_gasto_interno NO existe aún', m.pf_count||' func','0',(m.pf_count=0),'CHK'),
  -- C. Contexto Carril B (INFO — confirma OPS post-9H) -----------------------
  (30,'C. Contexto Carril B','Tablas Carril B presentes (post-9H)', m.tbl_carrilb||' de 9','9 (INFO)',(m.tbl_carrilb=9),'INFO'),
  (31,'C. Contexto Carril B','Columnas Carril B en cabanas', m.col_carrilb||' de 2','2 (INFO)',(m.col_carrilb=2),'INFO'),
  -- D. Salud operativa (INFO) ------------------------------------------------
  (40,'D. Salud operativa','Reservas cargadas', m.reservas_n::text,'(INFO)',true,'INFO'),
  (41,'D. Salud operativa','Bloqueos cargados', m.bloqueos_n::text,'(INFO)',true,'INFO'),
  (42,'D. Salud operativa','Pagos registrados', m.pagos_n::text,'(INFO)',true,'INFO'),
  (43,'D. Salud operativa','pg_cron instalado', m.cron_present::text,'true (INFO)',m.cron_present,'INFO'),
  -- E. Hardening baseline (INFO — fingerprint pre-promoción) -----------------
  (50,'E. Hardening baseline','Grants Data API+PUBLIC (S/I/U/D) en tablas', m.grants_tbl_dataapi::text,'0 (baseline INFO)',true,'INFO'),
  (51,'E. Hardening baseline','Funciones propias ABIERTAS a EXECUTE', m.fn_exec_abiertas||' de '||m.fn_propias_total,'(baseline INFO)',true,'INFO'),
  (52,'E. Hardening baseline','Funciones propias (excl. extensiones)', m.fn_propias_total::text,'(INFO)',true,'INFO'),
  (53,'E. Hardening baseline','Fingerprint md5 de cabanas.activa', left(m.activa_md5,12)||'…','(baseline INFO)',true,'INFO')
) AS v(orden, seccion, chequeo, obtenido, esperado, ok, veredicto)

UNION ALL
-- Parte 2: catálogo REAL de cabañas OPS (ajuste obligatorio — insumo del Bloque G).
-- Una fila INFO por cabaña: id real (SERIAL de OPS), nombre, tipo y capacidades.
-- El frontend OPS debe construir su catálogo a partir de ESTO, no de CABANAS_TEST.
SELECT (200 + row_number() OVER (ORDER BY id_cabana))::int,
       'G. Catálogo real cabañas (OPS)',
       'Cabaña: '||nombre,
       'id='||id_cabana||' · '||nombre||' · tipo='||tipo||' · base='||capacidad_base||' · max='||capacidad_max||' · activa='||activa,
       '(catálogo real → P-FE-01)',
       'INFO'
FROM cab

UNION ALL
-- Parte 3: TOTAL. Cuenta los 10 gates DUROS que fallan ⇒ VERDE/FRENAR.
SELECT 999,'TOTAL','FALLO=0 ⇒ OPS apto para iniciar la promoción del Carril C (Bloque A)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES
     (m.cab_real=5),(m.cab_total=5),(m.soc_real=3),(m.soc_placeholder=0),(m.soc_total=3),
     (m.amb_present=1),(COALESCE((m.amb_valor='ops'),false)),
     (m.pu_ausente),(m.pi_ausente),(m.pf_count=0)
   ) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES
     (m.cab_real=5),(m.cab_total=5),(m.soc_real=3),(m.soc_placeholder=0),(m.soc_total=3),
     (m.amb_present=1),(COALESCE((m.amb_valor='ops'),false)),
     (m.pu_ausente),(m.pi_ausente),(m.pf_count=0)
   ) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;
