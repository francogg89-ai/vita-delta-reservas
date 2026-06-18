-- ============================================================================
-- PROMO_BLOQUE_J_HARDENING_SWEEP_OPS.sql
-- Promoción a OPS — BLOQUE J: barrido global de SEGURIDAD / HARDENING / EXPOSICIÓN.
-- 100% READ-ONLY. Sin writes, sin fixtures, sin datos de prueba.
--
-- Objetivo: confirmar que toda la promoción del Carril B (9C→9H) + helper 9B
-- no abrió ninguna superficie hacia la Data API. NO valida paridad OPS↔TEST ni
-- corre smokes funcionales (eso es K).
--
-- Inventario del carril:
--   20 funciones: resolver_beneficiario (9C) · matriz_participacion,
--   repartir_por_matriz, detalle_participacion (9E) · cascada_periodo,
--   saldo_socios_periodo, incidencia_gasto, reporte_overrides_periodo,
--   reporte_5_vs_fiscal_periodo, gastos_sin_incidencia_periodo (9G) ·
--   liquidacion_vigente, saldo_corriente_socio, mayor_socio,
--   reporte_retribucion_operativo_periodo, registrar_snapshot_periodo,
--   registrar_retiro, registrar_movimiento_manual, registrar_reversa,
--   registrar_revaluacion (9H) · abortar_si_falla (helper 9B).
--   + trg_9h_inmutable (función de trigger).
--   9 tablas: zonas, cabana_zona (9C) · activaciones_operativas (9D) ·
--   gastos_internos (9F) · liquidaciones_periodo, liquidacion_cascada,
--   liquidacion_socio, movimientos_socio, revaluaciones (9H).
--   Secuencias del carril: las auto-dependientes de esas tablas.
--
-- Criterio "función abierta" (= baseline A-bis, L-8A-02): proacl IS NULL
-- (PUBLIC ejecutable) O concede EXECUTE a PUBLIC/anon/authenticated/service_role.
-- "Propias" = excluye funciones de extensiones (btree_gist) por pg_depend deptype='e'.
--
-- Correr con NADA seleccionado (L-8A-01). Es read-only: COMMIT/ROLLBACK indistinto.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- GATE (read-only) — ops + identidad + carril COMPLETO (21 fns + 9 tablas).
-- (Que el barrido tenga sentido: se corre sobre la promoción terminada.)
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE v_amb text; v_cab int; v_soc int; v_fns int; v_tab int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE J: ambiente=% (esperado ops).', COALESCE(v_amb,'<ausente>'); END IF;

  SELECT count(*) INTO v_cab FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
   WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  SELECT count(*) INTO v_soc FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
   WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1;
  IF v_cab<>5 OR v_soc<>3 THEN RAISE EXCEPTION 'GATE J: identidad (cabañas=%/5, socios=%/3).', v_cab, v_soc; END IF;

  SELECT count(*) INTO v_fns FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN (
     'resolver_beneficiario','matriz_participacion','repartir_por_matriz','detalle_participacion',
     'cascada_periodo','saldo_socios_periodo','incidencia_gasto','reporte_overrides_periodo',
     'reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo','liquidacion_vigente','saldo_corriente_socio',
     'mayor_socio','reporte_retribucion_operativo_periodo','registrar_snapshot_periodo','registrar_retiro',
     'registrar_movimiento_manual','registrar_reversa','registrar_revaluacion','abortar_si_falla','trg_9h_inmutable');
  SELECT count(*) INTO v_tab FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r' AND c.relname IN (
     'zonas','cabana_zona','activaciones_operativas','gastos_internos','liquidaciones_periodo',
     'liquidacion_cascada','liquidacion_socio','movimientos_socio','revaluaciones');
  IF v_fns<>21 THEN RAISE EXCEPTION 'GATE J: carril incompleto (funciones+trg=%/21).', v_fns; END IF;
  IF v_tab<>9  THEN RAISE EXCEPTION 'GATE J: carril incompleto (tablas=%/9).', v_tab; END IF;

  RAISE NOTICE 'GATE J OK — OPS; carril completo (21 fns, 9 tablas). Barrido read-only.';
END
$gate$;

-- ============================================================================
-- BARRIDO DE SEGURIDAD (read-only). Emite tabla de veredictos.
-- ============================================================================
WITH dataapi AS (
  SELECT array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL) AS oids),
carril_fns(nom) AS (VALUES
  ('resolver_beneficiario'),('matriz_participacion'),('repartir_por_matriz'),('detalle_participacion'),
  ('cascada_periodo'),('saldo_socios_periodo'),('incidencia_gasto'),('reporte_overrides_periodo'),
  ('reporte_5_vs_fiscal_periodo'),('gastos_sin_incidencia_periodo'),('liquidacion_vigente'),('saldo_corriente_socio'),
  ('mayor_socio'),('reporte_retribucion_operativo_periodo'),('registrar_snapshot_periodo'),('registrar_retiro'),
  ('registrar_movimiento_manual'),('registrar_reversa'),('registrar_revaluacion'),('abortar_si_falla'),('trg_9h_inmutable')),
carril_tabs(nom) AS (VALUES
  ('zonas'),('cabana_zona'),('activaciones_operativas'),('gastos_internos'),('liquidaciones_periodo'),
  ('liquidacion_cascada'),('liquidacion_socio'),('movimientos_socio'),('revaluaciones')),
-- secuencias auto-dependientes de las tablas del carril
carril_seqs AS (
  SELECT s.oid, s.relacl FROM pg_class s
  JOIN pg_depend d ON d.objid=s.oid AND d.deptype='a'
  JOIN pg_class t ON t.oid=d.refobjid
  JOIN pg_namespace nt ON nt.oid=t.relnamespace
  WHERE s.relkind='S' AND nt.nspname='public' AND t.relname IN (SELECT nom FROM carril_tabs)),
m AS (
  SELECT
    -- (1) carril fns + trg presentes
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname IN (SELECT nom FROM carril_fns)) AS fns_presentes,
    -- (2) carril fns + trg abiertas a EXECUTE
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace, dataapi
       WHERE n.nspname='public' AND p.proname IN (SELECT nom FROM carril_fns)
         AND (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
              WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY(dataapi.oids)))) AS fns_abiertas,
    -- (3) carril tablas presentes
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public' AND c.relkind='r' AND c.relname IN (SELECT nom FROM carril_tabs)) AS tabs_presentes,
    -- (4) carril tablas con grants Data API/PUBLIC
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
       CROSS JOIN LATERAL aclexplode(c.relacl) acl, dataapi
       WHERE n.nspname='public' AND c.relkind='r' AND c.relname IN (SELECT nom FROM carril_tabs)
         AND acl.grantee = ANY(dataapi.oids)) AS tabs_grants,
    -- (5) carril secuencias: total y con grants
    (SELECT count(*) FROM carril_seqs) AS seqs_total,
    (SELECT count(*) FROM carril_seqs cs CROSS JOIN LATERAL aclexplode(cs.relacl) acl, dataapi
       WHERE acl.grantee = ANY(dataapi.oids)) AS seqs_grants,
    -- (6) carril tablas con RLS habilitado
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public' AND c.relkind='r' AND c.relname IN (SELECT nom FROM carril_tabs)
         AND c.relrowsecurity IS TRUE) AS tabs_rls,
    -- (7) policies sobre tablas del carril
    (SELECT count(*) FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
       JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public' AND c.relname IN (SELECT nom FROM carril_tabs)) AS tabs_policies,
    -- (8) baseline GLOBAL: funciones propias (no-extensión) abiertas a EXECUTE
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace, dataapi
       WHERE n.nspname='public'
         AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')
         AND (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
              WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY(dataapi.oids)))) AS global_fns_abiertas,
    -- informativo: total de funciones propias (no-extensión)
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public'
         AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')) AS global_fns_propias
)
SELECT v.orden, v.chequeo, v.obtenido, v.esperado, CASE WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (1,'carril: 20 funciones + trg presentes',         m.fns_presentes::text,'21',(m.fns_presentes=21)),
  (2,'carril: funciones abiertas a EXECUTE',          m.fns_abiertas::text,'0',(m.fns_abiertas=0)),
  (3,'carril: 9 tablas presentes',                    m.tabs_presentes::text,'9',(m.tabs_presentes=9)),
  (4,'carril: tablas con grants Data API/PUBLIC',     m.tabs_grants::text,'0',(m.tabs_grants=0)),
  (5,'carril: secuencias con grants Data API/PUBLIC', m.seqs_grants::text,'0',(m.seqs_grants=0)),
  (6,'carril: tablas con RLS habilitado',             m.tabs_rls::text,'0',(m.tabs_rls=0)),
  (7,'carril: policies sobre tablas del carril',      m.tabs_policies::text,'0',(m.tabs_policies=0)),
  (8,'GLOBAL: funciones propias abiertas a EXECUTE',  m.global_fns_abiertas::text,'0',(m.global_fns_abiertas=0)),
  (9,'(info) secuencias del carril halladas',         m.seqs_total::text,'(info)',true),
  (10,'(info) funciones propias totales (excl. ext.)', m.global_fns_propias::text,'(info)',true)
) AS v(orden, chequeo, obtenido, esperado, ok)
UNION ALL
SELECT 999,'TOTAL J (hardening sweep)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES
     (m.fns_presentes=21),(m.fns_abiertas=0),(m.tabs_presentes=9),(m.tabs_grants=0),
     (m.seqs_grants=0),(m.tabs_rls=0),(m.tabs_policies=0),(m.global_fns_abiertas=0)
   ) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES
     (m.fns_presentes=21),(m.fns_abiertas=0),(m.tabs_presentes=9),(m.tabs_grants=0),
     (m.seqs_grants=0),(m.tabs_rls=0),(m.tabs_policies=0),(m.global_fns_abiertas=0)
   ) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;
