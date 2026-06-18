-- ============================================================================
-- PROMO_BLOQUE_A_BIS_SNAPSHOT_v2.sql   (SUPERSEDE de PROMO_BLOQUE_A_SNAPSHOT.sql)
-- Snapshot read-only de OPS, v2 con hardening (A-bis). SIN writes. SIN DDL.
-- Un único SELECT, un único result set. Gate de identidad por SEED (L-7E-01).
-- Habilita DDL solo con A (evidencia) + A-bis ambos en VERDE.
--
-- Ajustes sobre v1 (pedidos en revisión):
--  (1) Grants de tabla a Data API ahora INCLUYEN PUBLIC (via aclexplode, grantee=0).
--  (2) NUEVO baseline de EXECUTE sobre funciones propias, contemplando la trampa
--      de PostgreSQL: proacl NULL ⇒ PUBLIC tiene EXECUTE por DEFAULT (función ABIERTA).
--      Excluye funciones de extensión (btree_gist instala 188 en public — L-8A-02).
--  (3) EXCLUDE filtrado a schema public y a las tablas de base (reservas/bloqueos),
--      evitando falsos FRENAR por objetos de otros schemas (auth/storage/cron/…).
-- ============================================================================
WITH
  cab AS (SELECT id_cabana, nombre, activa FROM cabanas),
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
      -- A. Identidad por seed
      (SELECT count(*) FROM cab) AS cab_total,
      (SELECT count(*) FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
        WHERE EXISTS (SELECT 1 FROM cab c WHERE c.id_cabana=e.id AND c.nombre=e.nom)) AS cab_real,
      -- B. Socios reales
      (SELECT count(*) FROM socios) AS soc_total,
      (SELECT count(*) FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
        WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1) AS soc_real,
      (SELECT count(*) FROM socios WHERE nombre='Socio 3') AS soc_placeholder,
      -- C. Paridad base
      (SELECT count(*) FROM configuracion_general) AS cfg_count,
      -- (3) EXCLUDE en public sobre las tablas de base esperadas (reservas/bloqueos)
      (SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
        WHERE con.contype='x' AND n.nspname='public'
          AND con.conrelid::regclass::text IN ('reservas','bloqueos')) AS excl_base_ok,
      -- (3) EXCLUDE total en public (debe ser exactamente 2 ⇒ ningún extra inesperado)
      (SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
        WHERE con.contype='x' AND n.nspname='public') AS excl_public_total,
      -- D. Ausencia Carril B — columnas 9C
      (SELECT count(*) FROM information_schema.columns
        WHERE table_schema='public' AND table_name='cabanas'
          AND column_name IN ('valor_relativo','id_socio_beneficiario')) AS col_carrilb,
      -- D. tablas (9)
      (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relkind='r'
          AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos',
                            'liquidaciones_periodo','liquidacion_cascada','liquidacion_socio',
                            'movimientos_socio','revaluaciones')) AS tbl_carrilb,
      -- D. funciones (19)
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.prokind='f'
          AND p.proname IN ('resolver_beneficiario','matriz_participacion','repartir_por_matriz',
                            'detalle_participacion','cascada_periodo','saldo_socios_periodo',
                            'incidencia_gasto','reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                            'gastos_sin_incidencia_periodo','liquidacion_vigente','saldo_corriente_socio',
                            'mayor_socio','reporte_retribucion_operativo_periodo','registrar_snapshot_periodo',
                            'registrar_retiro','registrar_movimiento_manual','registrar_reversa',
                            'registrar_revaluacion')) AS fn_carrilb,
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='trg_9h_inmutable') AS fn_inmut,
      (SELECT count(*) FROM pg_trigger t
        WHERE NOT t.tgisinternal
          AND t.tgrelid::regclass::text = ANY (ARRAY['liquidaciones_periodo','liquidacion_cascada',
            'liquidacion_socio','movimientos_socio','revaluaciones'])) AS trg_inmut,
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='abortar_si_falla') AS fn_helper,
      (SELECT count(*) FROM configuracion_general WHERE clave='ambiente') AS cfg_ambiente,
      (SELECT count(*) FROM pg_constraint WHERE conname='exc_activaciones_no_overlap') AS excl_activ,
      -- E. Salud operativa
      (SELECT count(*) FROM reservas) AS reservas_n,
      (SELECT count(*) FROM bloqueos) AS bloqueos_n,
      (SELECT count(*) FROM pagos) AS pagos_n,
      (SELECT (to_regclass('cron.job') IS NOT NULL)) AS cron_present,
      -- F.(1) Grants de TABLA a Data API INCLUYENDO PUBLIC (aclexplode; relacl NULL ⇒ sin grants)
      (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        CROSS JOIN LATERAL aclexplode(c.relacl) acl, dataapi
        WHERE n.nspname='public' AND c.relkind='r'
          AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
          AND acl.grantee = ANY (dataapi.oids)) AS grants_tbl_dataapi,
      -- F.(2) Funciones propias ABIERTAS a EXECUTE para PUBLIC/Data API.
      --       proacl NULL ⇒ PUBLIC tiene EXECUTE por default ⇒ ABIERTA (se cuenta).
      --       Excluye funciones de extensión (deptype='e').
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.prokind='f'
          AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')
          AND (
            p.proacl IS NULL
            OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a, dataapi
                       WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY (dataapi.oids))
          )) AS fn_exec_abiertas,
      -- F. fingerprint
      (SELECT md5(string_agg(id_cabana::text||':'||activa::text, ',' ORDER BY id_cabana)) FROM cab) AS activa_md5,
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.prokind='f'
          AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')) AS fn_propias_total
  )
SELECT v.orden, v.seccion, v.chequeo, v.obtenido, v.esperado,
       CASE WHEN v.veredicto='INFO' THEN 'INFO' WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (10,'A. Identidad (gate seed)','Cabañas 1-5 reales presentes', m.cab_real||' de 5','5',(m.cab_real=5),'CHK'),
  (11,'A. Identidad (gate seed)','Total de cabañas', m.cab_total::text,'5',(m.cab_total=5),'CHK'),
  (20,'B. Socios (prereq L-9C-01)','Franco/Rodrigo/Remo presentes', m.soc_real||' de 3','3',(m.soc_real=3),'CHK'),
  (21,'B. Socios (prereq L-9C-01)','Placeholder "Socio 3" ausente', m.soc_placeholder::text,'0',(m.soc_placeholder=0),'CHK'),
  (22,'B. Socios (prereq L-9C-01)','Total de socios', m.soc_total::text,'3',(m.soc_total=3),'CHK'),
  (30,'C. Paridad de base','Claves configuracion_general', m.cfg_count::text,'>=10 (INFO)',true,'INFO'),
  (31,'C. Paridad de base','EXCLUDE base en reservas+bloqueos', m.excl_base_ok::text,'2',(m.excl_base_ok=2),'CHK'),
  (32,'C. Paridad de base','EXCLUDE total en schema public (sin extras)', m.excl_public_total::text,'2',(m.excl_public_total=2),'CHK'),
  (40,'D. Ausencia Carril B','Columnas 9C en cabanas', m.col_carrilb::text,'0',(m.col_carrilb=0),'CHK'),
  (41,'D. Ausencia Carril B','Tablas Carril B (9C/9D/9F/9H)', m.tbl_carrilb||' de 9','0',(m.tbl_carrilb=0),'CHK'),
  (42,'D. Ausencia Carril B','Funciones Carril B (9C/9E/9G/9H)', m.fn_carrilb||' de 19','0',(m.fn_carrilb=0),'CHK'),
  (43,'D. Ausencia Carril B','Función trigger inmutabilidad 9H', m.fn_inmut::text,'0',(m.fn_inmut=0),'CHK'),
  (44,'D. Ausencia Carril B','Triggers de inmutabilidad 9H', m.trg_inmut::text,'0',(m.trg_inmut=0),'CHK'),
  (45,'D. Ausencia Carril B','Helper abortar_si_falla (9B)', m.fn_helper::text,'0',(m.fn_helper=0),'CHK'),
  (46,'D. Ausencia Carril B','Marcador ambiente en config', m.cfg_ambiente::text,'0',(m.cfg_ambiente=0),'CHK'),
  (47,'D. Ausencia Carril B','EXCLUDE exc_activaciones_no_overlap', m.excl_activ::text,'0',(m.excl_activ=0),'CHK'),
  (50,'E. Salud operativa','Reservas cargadas', m.reservas_n::text,'>=1 (INFO)',(m.reservas_n>=1),'INFO'),
  (51,'E. Salud operativa','Bloqueos cargados', m.bloqueos_n::text,'(INFO)',true,'INFO'),
  (52,'E. Salud operativa','Pagos registrados', m.pagos_n::text,'(INFO)',true,'INFO'),
  (53,'E. Salud operativa','pg_cron instalado', m.cron_present::text,'true (INFO)',m.cron_present,'INFO'),
  (60,'F. Hardening baseline','Grants Data API+PUBLIC (S/I/U/D) en tablas base', m.grants_tbl_dataapi::text,'0',(m.grants_tbl_dataapi=0),'CHK'),
  (62,'F. Hardening baseline','Funciones propias ABIERTAS a EXECUTE (PUBLIC/DataAPI)', m.fn_exec_abiertas||' de '||m.fn_propias_total,'0',(m.fn_exec_abiertas=0),'CHK'),
  (63,'F. Hardening baseline','Funciones propias (excl. extensiones) — INFO', m.fn_propias_total::text,'(INFO)',true,'INFO'),
  (61,'F. Hardening baseline','Fingerprint md5 de cabanas.activa', left(m.activa_md5,12)||'…','(baseline INFO)',true,'INFO')
) AS v(orden, seccion, chequeo, obtenido, esperado, ok, veredicto)
UNION ALL
SELECT 999,'TOTAL','FALLO=0 ⇒ OPS apto para iniciar la promoción (A-bis)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES
     (m.cab_real=5),(m.cab_total=5),(m.soc_real=3),(m.soc_placeholder=0),(m.soc_total=3),
     (m.excl_base_ok=2),(m.excl_public_total=2),(m.col_carrilb=0),(m.tbl_carrilb=0),(m.fn_carrilb=0),
     (m.fn_inmut=0),(m.trg_inmut=0),(m.fn_helper=0),(m.cfg_ambiente=0),(m.excl_activ=0),
     (m.grants_tbl_dataapi=0),(m.fn_exec_abiertas=0)
   ) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES
     (m.cab_real=5),(m.cab_total=5),(m.soc_real=3),(m.soc_placeholder=0),(m.soc_total=3),
     (m.excl_base_ok=2),(m.excl_public_total=2),(m.col_carrilb=0),(m.tbl_carrilb=0),(m.fn_carrilb=0),
     (m.fn_inmut=0),(m.trg_inmut=0),(m.fn_helper=0),(m.cfg_ambiente=0),(m.excl_activ=0),
     (m.grants_tbl_dataapi=0),(m.fn_exec_abiertas=0)
   ) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;
