-- ============================================================================
-- PROMO_BLOQUE_K2_SMOKES_READONLY_OPS.sql
-- Promoción — BLOQUE K2: smokes NO invasivos + pool real. SOLO OPS. READ-ONLY.
--
-- NO ejecuta funciones de escritura de 9H (ni bajo ROLLBACK): nextval no es
-- transaccional y consumiría secuencias reales. Preserva las tablas 9H vacías
-- y las secuencias sin uso para que la primera liquidación real arranque en 1.
--
-- Prueba (todo read-only, sobre datos reales de OPS):
--   · funciones de lectura corren sin error y con la forma esperada;
--   · helper abortar_si_falla con 4 JSON sintéticos (no toca datos);
--   · resolver_beneficiario en las 5 cabañas;
--   · matriz/reparto/detalle (9E); cascada/reportes (9G) read-only;
--   · pool real 9D: julio = 4 cabañas, noviembre = 5;
--   · invariante post-promoción: tablas 9H vacías + secuencias en 1.
--
-- Correr con NADA seleccionado (L-8A-01).
-- ============================================================================

-- ── GATE (read-only) — ops + carril completo ────────────────────────────────
DO $gate$
DECLARE v_amb text; v_cab int; v_soc int; v_fns int; v_tab int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN RAISE EXCEPTION 'GATE K2: ambiente=% (esperado ops).', COALESCE(v_amb,'<ausente>'); END IF;
  SELECT count(*) INTO v_cab FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
   WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  SELECT count(*) INTO v_soc FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom) WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1;
  IF v_cab<>5 OR v_soc<>3 THEN RAISE EXCEPTION 'GATE K2: identidad (cabañas=%/5, socios=%/3).', v_cab, v_soc; END IF;
  SELECT count(*) INTO v_fns FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('resolver_beneficiario','matriz_participacion','repartir_por_matriz','detalle_participacion',
     'cascada_periodo','saldo_socios_periodo','incidencia_gasto','reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
     'gastos_sin_incidencia_periodo','liquidacion_vigente','saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo','abortar_si_falla');
  IF v_fns<>15 THEN RAISE EXCEPTION 'GATE K2: faltan funciones de lectura/helper (=%/15).', v_fns; END IF;
  RAISE NOTICE 'GATE K2 OK — OPS; carril presente. Smokes read-only.';
END
$gate$;

-- ── HELPER abortar_si_falla — 4 JSON sintéticos (read-only) ──────────────────
DO $helper$
DECLARE r jsonb; ok1 bool; g2 bool:=false; g3 bool:=false; g4 bool:=false;
BEGIN
  r := abortar_si_falla('{"ok":true,"estado":"confirmado","probe":1}'::jsonb);  -- éxito → devuelve jsonb
  ok1 := (r->>'probe')='1';
  BEGIN PERFORM abortar_si_falla('{"ok":false,"estado":"en_revision"}'::jsonb);
    EXCEPTION WHEN sqlstate 'P0001' THEN g2:=true; END;
  BEGIN PERFORM abortar_si_falla('{"ok":true,"estado":"en_revision"}'::jsonb);
    EXCEPTION WHEN sqlstate 'P0001' THEN g3:=true; END;
  BEGIN PERFORM abortar_si_falla('{"ok":true,"estado":"confirmado","warning":"x"}'::jsonb);
    EXCEPTION WHEN sqlstate 'P0001' THEN g4:=true; END;
  IF NOT (ok1 AND g2 AND g3 AND g4) THEN
    RAISE EXCEPTION 'K2 HELPER: contrato roto (exito=%, g_false=%, g_revision=%, g_warning=%).', ok1, g2, g3, g4; END IF;
  RAISE NOTICE 'K2 HELPER OK — 4/4 (exito devuelve jsonb; 3 abortan P0001).';
END
$helper$;

-- ── VERDICTO (read-only) — formas de salida + pool real + invariante 9H ──────
WITH m AS (
  SELECT
    -- resolver_beneficiario: 5/5 = id_socio_beneficiario
    (SELECT count(*) FROM cabanas c WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01') = c.id_socio_beneficiario) AS seam_ok,
    -- pool 9D
    (SELECT count(*) FROM activaciones_operativas) AS act_total,
    (SELECT count(DISTINCT id_cabana) FROM activaciones_operativas WHERE daterange(fecha_desde, fecha_hasta, '[)') @> DATE '2026-07-01') AS act_jul,
    (SELECT count(DISTINCT id_cabana) FROM activaciones_operativas WHERE daterange(fecha_desde, fecha_hasta, '[)') @> DATE '2026-11-01') AS act_nov,
    -- matriz 9E
    (SELECT count(*) FROM matriz_participacion(DATE '2026-07-01')) AS mat_jul_socios,
    (SELECT count(*) FROM matriz_participacion(DATE '2026-11-01')) AS mat_nov_socios,
    (SELECT round(sum(participacion),6) FROM matriz_participacion(DATE '2026-07-01')) AS mat_jul_sumpart,
    (SELECT max(valor_pool) FROM matriz_participacion(DATE '2026-07-01')) AS mat_jul_pool,
    (SELECT max(valor_pool) FROM matriz_participacion(DATE '2026-11-01')) AS mat_nov_pool,
    -- reparto 9E: Σ = monto exacto
    (SELECT sum(monto_asignado) FROM repartir_por_matriz(DATE '2026-07-01', 100000)) AS rep_suma,
    (SELECT count(*) FROM repartir_por_matriz(DATE '2026-07-01', 100000)) AS rep_filas,
    -- detalle 9E: 5 cabañas; participa true jul=4 / nov=5
    (SELECT count(*) FROM detalle_participacion(DATE '2026-07-01')) AS det_jul_filas,
    (SELECT count(*) FILTER (WHERE participa) FROM detalle_participacion(DATE '2026-07-01')) AS det_jul_participa,
    (SELECT count(*) FILTER (WHERE participa) FROM detalle_participacion(DATE '2026-11-01')) AS det_nov_participa,
    -- cascada/reportes 9G (corren sobre ingreso real; forma)
    (SELECT count(*) FILTER (WHERE paso BETWEEN 1 AND 8) FROM cascada_periodo(DATE '2026-07-01', 0.25)) AS casc_jul_pasos,
    (SELECT count(*) FROM saldo_socios_periodo(DATE '2026-07-01', 0.25)) AS saldo_jul_socios,
    (SELECT count(*) FROM reporte_5_vs_fiscal_periodo(DATE '2026-07-01')) AS r5_filas,
    (SELECT count(*) FROM reporte_overrides_periodo(DATE '2026-07-01')) AS rov_filas,
    (SELECT count(*) FROM gastos_sin_incidencia_periodo(DATE '2026-07-01')) AS gsi_filas,
    (SELECT count(*) FROM incidencia_gasto(1)) AS inc_filas,
    -- 9H lectura (corren sin error sobre tablas vacías; forma)
    (SELECT count(*) FROM saldo_corriente_socio(1)) AS h_saldo_filas,
    (SELECT count(*) FROM mayor_socio(1)) AS h_mayor_filas,
    (SELECT count(*) FROM reporte_retribucion_operativo_periodo(DATE '2026-07-01')) AS h_repo_filas,
    (SELECT (liquidacion_vigente(DATE '2026-07-01') IS NULL)) AS h_vigente_null,
    -- invariante post-promoción: 9H vacío + secuencias en 1
    ((SELECT count(*) FROM liquidaciones_periodo)+(SELECT count(*) FROM liquidacion_cascada)+(SELECT count(*) FROM liquidacion_socio)
      +(SELECT count(*) FROM movimientos_socio)+(SELECT count(*) FROM revaluaciones)) AS h_filas,
    ((SELECT is_called FROM liquidaciones_periodo_id_liquidacion_seq)::int+(SELECT is_called FROM movimientos_socio_id_movimiento_seq)::int
      +(SELECT is_called FROM revaluaciones_id_revaluacion_seq)::int) AS h_seq_called
)
SELECT v.orden, v.chequeo, v.obtenido, v.esperado, CASE WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (1,'seam resolver_beneficiario (5/5 cabañas)',     m.seam_ok::text,'5',(m.seam_ok=5)),
  (2,'9D activaciones totales',                       m.act_total::text,'5',(m.act_total=5)),
  (3,'9D pool julio (cabañas activas)',               m.act_jul::text,'4',(m.act_jul=4)),
  (4,'9D pool noviembre (cabañas activas)',           m.act_nov::text,'5',(m.act_nov=5)),
  (5,'matriz julio (socios)',                         m.mat_jul_socios::text,'3',(m.mat_jul_socios=3)),
  (6,'matriz noviembre (socios)',                     m.mat_nov_socios::text,'3',(m.mat_nov_socios=3)),
  (7,'matriz julio Σ participacion = 1',              m.mat_jul_sumpart::text,'1.000000',(m.mat_jul_sumpart=1)),
  (8,'reparto julio Σ = monto (100000)',              m.rep_suma::text,'100000',(m.rep_suma=100000)),
  (9,'reparto julio filas (socios)',                  m.rep_filas::text,'3',(m.rep_filas=3)),
  (10,'detalle julio (todas las cabañas)',            m.det_jul_filas::text,'5',(m.det_jul_filas=5)),
  (11,'detalle julio participa=true',                 m.det_jul_participa::text,'4',(m.det_jul_participa=4)),
  (12,'detalle noviembre participa=true',             m.det_nov_participa::text,'5',(m.det_nov_participa=5)),
  (13,'cascada julio (pasos 1-8)',                    m.casc_jul_pasos::text,'8',(m.casc_jul_pasos=8)),
  (14,'saldo_socios julio (socios)',                  m.saldo_jul_socios::text,'3',(m.saldo_jul_socios=3)),
  (15,'reporte_5_vs_fiscal (1 fila)',                 m.r5_filas::text,'1',(m.r5_filas=1)),
  (16,'9H lectura liquidacion_vigente = NULL (limpio)', m.h_vigente_null::text,'true',(m.h_vigente_null IS TRUE)),
  (17,'INVARIANTE 9H: tablas vacías',                 m.h_filas::text,'0',(m.h_filas=0)),
  (18,'INVARIANTE 9H: secuencias en 1',               m.h_seq_called::text,'0',(m.h_seq_called=0)),
  -- informativos (corren sin error; forma libre)
  (19,'(info) matriz pool jul / nov',  m.mat_jul_pool::text||' / '||m.mat_nov_pool::text,'(info)',true),
  (20,'(info) reportes 9G corren (rov/gsi/inc)', m.rov_filas::text||'/'||m.gsi_filas::text||'/'||m.inc_filas::text,'(info)',true),
  (21,'(info) 9H lectura corren (saldo/mayor/repo)', m.h_saldo_filas::text||'/'||m.h_mayor_filas::text||'/'||m.h_repo_filas::text,'(info)',true)
) AS v(orden, chequeo, obtenido, esperado, ok)
UNION ALL
SELECT 999,'TOTAL K2 (smokes read-only)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES
     (m.seam_ok=5),(m.act_total=5),(m.act_jul=4),(m.act_nov=5),(m.mat_jul_socios=3),(m.mat_nov_socios=3),
     (m.mat_jul_sumpart=1),(m.rep_suma=100000),(m.rep_filas=3),(m.det_jul_filas=5),(m.det_jul_participa=4),
     (m.det_nov_participa=5),(m.casc_jul_pasos=8),(m.saldo_jul_socios=3),(m.r5_filas=1),(m.h_vigente_null IS TRUE),
     (m.h_filas=0),(m.h_seq_called=0)
   ) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES
     (m.seam_ok=5),(m.act_total=5),(m.act_jul=4),(m.act_nov=5),(m.mat_jul_socios=3),(m.mat_nov_socios=3),
     (m.mat_jul_sumpart=1),(m.rep_suma=100000),(m.rep_filas=3),(m.det_jul_filas=5),(m.det_jul_participa=4),
     (m.det_nov_participa=5),(m.casc_jul_pasos=8),(m.saldo_jul_socios=3),(m.r5_filas=1),(m.h_vigente_null IS TRUE),
     (m.h_filas=0),(m.h_seq_called=0)
   ) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;
