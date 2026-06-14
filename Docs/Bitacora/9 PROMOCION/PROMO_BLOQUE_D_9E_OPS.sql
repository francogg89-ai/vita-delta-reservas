-- ============================================================================
-- PROMO_BLOQUE_D_9E_OPS.sql
-- Promoción del Carril B a OPS — BLOQUE D (solo 9E).
-- Etapa PROMO. Depende de B1 (9C) y C (9D) ya commiteados y VERDE en OPS.
-- Contenido: 3 funciones READ-ONLY (matriz_participacion, repartir_por_matriz,
-- detalle_participacion). SIN tablas, SIN seed, SIN EXCLUDE, SIN writes de datos.
-- NO toca 9C/9D/9F/9G/9H ni helper 9B.
--
-- Bodies verbatim de 9E_CIERRE.md §7. Centavo residual D-9E-08 (validado abajo
-- contra el pool real: julio→Remo, noviembre→Franco, jamás Rodrigo fuera de empate).
--
-- ESTRUCTURA: BEGIN → gate (marcador ops + identidad + 9C + 9D presentes + 9E
-- ausente) → prechecks → DDL (3 funciones) → hardening (REVOKE EXECUTE) →
-- asserts funcionales contra el pool real → COMMIT → verificación read-only
-- posterior → reversión sin DROP ... CASCADE.
--
-- Correr con NADA seleccionado (L-8A-01).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. GATE — marcador ops + identidad estructural + 9C y 9D presentes + 9E ausente.
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb        text;
  v_cab_real   int;
  v_soc_real   int;
  v_9c_seam    int;
  v_9d_filas   int;
  v_9e_fns     int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE D: marcador ambiente=% (esperado ops).', COALESCE(v_amb,'<ausente>');
  END IF;

  SELECT count(*) INTO v_cab_real FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
   WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  SELECT count(*) INTO v_soc_real FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
   WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1;
  IF v_cab_real <> 5 OR v_soc_real <> 3 THEN
    RAISE EXCEPTION 'GATE D: identidad no coincide (cabañas=%/5, socios=%/3).', v_cab_real, v_soc_real;
  END IF;

  -- 9C (seam) y 9D (pool con 5 activaciones) presentes — 9E los consume
  SELECT count(*) INTO v_9c_seam FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='resolver_beneficiario';
  SELECT count(*) INTO v_9d_filas FROM activaciones_operativas;
  IF v_9c_seam <> 1 THEN RAISE EXCEPTION 'GATE D: seam resolver_beneficiario ausente (correr B1).'; END IF;
  IF v_9d_filas <> 5 THEN RAISE EXCEPTION 'GATE D: activaciones=% (esperado 5; correr C).', v_9d_filas; END IF;

  -- Ausencia de las 3 funciones 9E — guard de re-ejecución
  SELECT count(*) INTO v_9e_fns FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('matriz_participacion','repartir_por_matriz','detalle_participacion');
  IF v_9e_fns <> 0 THEN
    RAISE EXCEPTION 'GATE D: funciones 9E ya presentes (=%). D no se re-ejecuta.', v_9e_fns; END IF;

  RAISE NOTICE 'GATE D OK — OPS con 9C+9D presentes; 9E ausente.';
END
$gate$;

-- ----------------------------------------------------------------------------
-- 2. DDL — 3 funciones read-only (verbatim 9E §7). LANGUAGE sql, sin variables v_
--    (sin riesgo de interferencia del Dashboard). DROP IF EXISTS por idempotencia.
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS matriz_participacion(DATE);
CREATE FUNCTION matriz_participacion(p_periodo DATE)
RETURNS TABLE (id_socio BIGINT, valor_socio NUMERIC, valor_pool NUMERIC, participacion NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER
AS $fn$
  WITH mes AS (
    SELECT daterange(date_trunc('month', p_periodo)::date,
                     (date_trunc('month', p_periodo) + INTERVAL '1 month')::date, '[)') AS rango,
           date_trunc('month', p_periodo)::date AS inicio
  ),
  participantes AS (
    SELECT resolver_beneficiario(c.id_cabana, m.inicio) AS id_socio, c.valor_relativo
    FROM activaciones_operativas a
    JOIN cabanas c ON c.id_cabana = a.id_cabana
    CROSS JOIN mes m
    WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)') @> m.rango
  ),
  por_socio AS (SELECT id_socio, SUM(valor_relativo) AS valor_socio FROM participantes GROUP BY id_socio),
  total AS (SELECT SUM(valor_socio) AS valor_pool FROM por_socio)
  SELECT s.id_socio, s.valor_socio, t.valor_pool, (s.valor_socio / t.valor_pool) AS participacion
  FROM por_socio s CROSS JOIN total t
  WHERE t.valor_pool > 0
  ORDER BY participacion DESC, s.id_socio;
$fn$;

DROP FUNCTION IF EXISTS repartir_por_matriz(DATE, NUMERIC);
CREATE FUNCTION repartir_por_matriz(p_periodo DATE, p_monto NUMERIC)
RETURNS TABLE (id_socio BIGINT, participacion NUMERIC, monto_asignado NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER
AS $fn$
  WITH base AS (
    SELECT m.id_socio, m.participacion, ROUND(p_monto * m.participacion, 2) AS monto_base
    FROM matriz_participacion(p_periodo) m
  ),
  resid AS (SELECT p_monto - COALESCE(SUM(monto_base),0) AS residual FROM base),
  ganador AS (
    SELECT b.id_socio FROM base b JOIN socios s ON s.id_socio = b.id_socio
    ORDER BY b.participacion DESC, (s.nombre = 'Rodrigo') DESC, b.id_socio ASC LIMIT 1
  )
  SELECT b.id_socio, b.participacion,
         b.monto_base + CASE WHEN b.id_socio = (SELECT id_socio FROM ganador)
                             THEN (SELECT residual FROM resid) ELSE 0 END AS monto_asignado
  FROM base b
  ORDER BY b.participacion DESC, b.id_socio;
$fn$;

DROP FUNCTION IF EXISTS detalle_participacion(DATE);
CREATE FUNCTION detalle_participacion(p_periodo DATE)
RETURNS TABLE (id_cabana BIGINT, cabana TEXT, valor_relativo NUMERIC,
               id_socio BIGINT, beneficiario TEXT, participa BOOLEAN)
LANGUAGE sql STABLE SECURITY INVOKER
AS $fn$
  WITH mes AS (
    SELECT daterange(date_trunc('month', p_periodo)::date,
                     (date_trunc('month', p_periodo) + INTERVAL '1 month')::date, '[)') AS rango,
           date_trunc('month', p_periodo)::date AS inicio
  )
  SELECT c.id_cabana, c.nombre, c.valor_relativo,
         resolver_beneficiario(c.id_cabana, m.inicio) AS id_socio, s.nombre,
         EXISTS (SELECT 1 FROM activaciones_operativas a
                 WHERE a.id_cabana = c.id_cabana
                   AND daterange(a.fecha_desde, a.fecha_hasta, '[)') @> m.rango) AS participa
  FROM cabanas c CROSS JOIN mes m
  JOIN socios s ON s.id_socio = resolver_beneficiario(c.id_cabana, m.inicio)
  ORDER BY c.id_cabana;
$fn$;

-- ----------------------------------------------------------------------------
-- 3. HARDENING — REVOKE EXECUTE de las 3 funciones a PUBLIC + roles Data API.
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION matriz_participacion(DATE)            FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION repartir_por_matriz(DATE, NUMERIC)    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION detalle_participacion(DATE)           FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. ASSERTS FUNCIONALES (contra el pool real de OPS) + hardening + aislamiento.
-- ----------------------------------------------------------------------------
DO $assert$
DECLARE
  v_jul_n        int;
  v_jul_sum      numeric;
  v_jul_pool     numeric;
  v_nov_n        int;
  v_nov_sum      numeric;
  v_nov_pool     numeric;
  v_jun_n        int;
  v_sum_jul_rep  numeric;
  v_sum_nov_rep  numeric;
  v_gana_jul     text;
  v_gana_jul_cnt int;
  v_gana_nov     text;
  v_gana_nov_cnt int;
  v_det_jul_n    int;
  v_det_jul_part int;
  v_det_jul_guate boolean;
  v_det_nov_part int;
  v_exec_abiertas int;
  v_excl_total   int;
  v_dataapi      oid[];
BEGIN
  v_dataapi := array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL);

  -- D1: matriz julio — 3 socios, pool 378, suma 1
  SELECT count(*), round(sum(participacion),6), max(valor_pool)
    INTO v_jul_n, v_jul_sum, v_jul_pool FROM matriz_participacion('2026-07-01');
  IF v_jul_n <> 3 OR v_jul_sum <> 1.000000 OR v_jul_pool <> 378 THEN
    RAISE EXCEPTION 'ASSERT D1: julio n=%, suma=%, pool=% (esperado 3/1/378).', v_jul_n, v_jul_sum, v_jul_pool; END IF;

  -- D2: matriz noviembre — 3 socios, pool 456, suma 1
  SELECT count(*), round(sum(participacion),6), max(valor_pool)
    INTO v_nov_n, v_nov_sum, v_nov_pool FROM matriz_participacion('2026-11-01');
  IF v_nov_n <> 3 OR v_nov_sum <> 1.000000 OR v_nov_pool <> 456 THEN
    RAISE EXCEPTION 'ASSERT D2: noviembre n=%, suma=%, pool=% (esperado 3/1/456).', v_nov_n, v_nov_sum, v_nov_pool; END IF;

  -- D3: junio — pool vacío ⇒ 0 filas (sin división por cero)
  SELECT count(*) INTO v_jun_n FROM matriz_participacion('2026-06-01');
  IF v_jun_n <> 0 THEN RAISE EXCEPTION 'ASSERT D3: junio filas=% (esperado 0, pool vacío).', v_jun_n; END IF;

  -- D4: reparto exacto Σ = monto (julio y noviembre)
  SELECT sum(monto_asignado) INTO v_sum_jul_rep FROM repartir_por_matriz('2026-07-01', 100000.00);
  SELECT sum(monto_asignado) INTO v_sum_nov_rep FROM repartir_por_matriz('2026-11-01', 12345.67);
  IF v_sum_jul_rep <> 100000.00 THEN RAISE EXCEPTION 'ASSERT D4a: Σ julio=% (esperado 100000.00).', v_sum_jul_rep; END IF;
  IF v_sum_nov_rep <> 12345.67 THEN RAISE EXCEPTION 'ASSERT D4b: Σ noviembre=% (esperado 12345.67).', v_sum_nov_rep; END IF;

  -- D5 (D-9E-08): residual de julio $100.000 → Remo (mayor participación, sin empate)
  SELECT s.nombre, count(*) OVER () INTO v_gana_jul, v_gana_jul_cnt
  FROM repartir_por_matriz('2026-07-01', 100000.00) r JOIN socios s ON s.id_socio=r.id_socio
  WHERE r.monto_asignado <> round(100000.00 * r.participacion, 2);
  IF v_gana_jul IS DISTINCT FROM 'Remo' OR v_gana_jul_cnt <> 1 THEN
    RAISE EXCEPTION 'ASSERT D5: residual julio fue a % (cnt %); esperado Remo (1).', v_gana_jul, v_gana_jul_cnt; END IF;

  -- D6 (D-9E-08): residual de noviembre $12.345,67 → Franco (empate, menor id), NO Rodrigo
  SELECT s.nombre, count(*) OVER () INTO v_gana_nov, v_gana_nov_cnt
  FROM repartir_por_matriz('2026-11-01', 12345.67) r JOIN socios s ON s.id_socio=r.id_socio
  WHERE r.monto_asignado <> round(12345.67 * r.participacion, 2);
  IF v_gana_nov IS DISTINCT FROM 'Franco' OR v_gana_nov_cnt <> 1 THEN
    RAISE EXCEPTION 'ASSERT D6: residual noviembre fue a % (cnt %); esperado Franco (1), nunca Rodrigo.', v_gana_nov, v_gana_nov_cnt; END IF;

  -- D7: detalle julio — 5 cabañas, 4 participan, Guatemala NO participa
  SELECT count(*), count(*) FILTER (WHERE participa),
         bool_or(participa) FILTER (WHERE cabana='Guatemala')
    INTO v_det_jul_n, v_det_jul_part, v_det_jul_guate FROM detalle_participacion('2026-07-01');
  IF v_det_jul_n <> 5 OR v_det_jul_part <> 4 OR v_det_jul_guate <> false THEN
    RAISE EXCEPTION 'ASSERT D7: detalle julio n=%, participan=%, Guatemala=% (esperado 5/4/false).',
      v_det_jul_n, v_det_jul_part, v_det_jul_guate; END IF;

  -- D8: detalle noviembre — 5 participan
  SELECT count(*) FILTER (WHERE participa) INTO v_det_nov_part FROM detalle_participacion('2026-11-01');
  IF v_det_nov_part <> 5 THEN RAISE EXCEPTION 'ASSERT D8: detalle noviembre participan=% (esperado 5).', v_det_nov_part; END IF;

  -- D9 (hardening): 0 funciones 9E abiertas a EXECUTE para PUBLIC/Data API (proacl NULL = abierto)
  SELECT count(*) INTO v_exec_abiertas FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('matriz_participacion','repartir_por_matriz','detalle_participacion')
     AND (p.proacl IS NULL
          OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                     WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY (v_dataapi)));
  IF v_exec_abiertas <> 0 THEN
    RAISE EXCEPTION 'ASSERT D9: funciones 9E abiertas a EXECUTE=% (esperado 0).', v_exec_abiertas; END IF;

  -- D10 (aislamiento): 9E es read-only ⇒ EXCLUDE en public sigue = 3 (no agrega)
  SELECT count(*) INTO v_excl_total FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
   WHERE con.contype='x' AND n.nspname='public';
  IF v_excl_total <> 3 THEN RAISE EXCEPTION 'ASSERT D10: EXCLUDE en public=% (esperado 3; 9E no agrega).', v_excl_total; END IF;

  RAISE NOTICE 'ASSERTS D OK — 9E consistente (matriz/reparto/detalle + residual D-9E-08). Listo para COMMIT.';
END
$assert$;

COMMIT;

-- ============================================================================
-- 5. VERIFICACIÓN READ-ONLY POSTERIOR (fuera de la transacción).
-- ============================================================================
WITH dataapi AS (
  SELECT array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL) AS oids),
m AS (
  SELECT
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.prokind='f'
        AND p.proname IN ('matriz_participacion','repartir_por_matriz','detalle_participacion')) AS fns,
    (SELECT round(sum(participacion),6) FROM matriz_participacion('2026-07-01')) AS jul_sum,
    (SELECT round(sum(participacion),6) FROM matriz_participacion('2026-11-01')) AS nov_sum,
    (SELECT count(*) FROM matriz_participacion('2026-06-01')) AS jun_n,
    (SELECT sum(monto_asignado) FROM repartir_por_matriz('2026-07-01',100000.00)) AS jul_rep,
    (SELECT sum(monto_asignado) FROM repartir_por_matriz('2026-11-01',12345.67)) AS nov_rep,
    (SELECT s.nombre FROM repartir_por_matriz('2026-07-01',100000.00) r JOIN socios s ON s.id_socio=r.id_socio
      WHERE r.monto_asignado <> round(100000.00*r.participacion,2)) AS gana_jul,
    (SELECT s.nombre FROM repartir_por_matriz('2026-11-01',12345.67) r JOIN socios s ON s.id_socio=r.id_socio
      WHERE r.monto_asignado <> round(12345.67*r.participacion,2)) AS gana_nov,
    (SELECT count(*) FILTER (WHERE participa) FROM detalle_participacion('2026-07-01')) AS det_jul,
    (SELECT count(*) FILTER (WHERE participa) FROM detalle_participacion('2026-11-01')) AS det_nov,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace, dataapi
      WHERE n.nspname='public' AND p.proname IN ('matriz_participacion','repartir_por_matriz','detalle_participacion')
        AND (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
             WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY (dataapi.oids)))) AS exec_abiertas,
    (SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
      WHERE con.contype='x' AND n.nspname='public') AS excl_total
)
SELECT v.orden, v.chequeo, v.obtenido, v.esperado,
       CASE WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (1,'3 funciones 9E presentes', m.fns::text,'3',(m.fns=3)),
  (2,'Matriz julio suma 1', m.jul_sum::text,'1.000000',(m.jul_sum=1.000000)),
  (3,'Matriz noviembre suma 1', m.nov_sum::text,'1.000000',(m.nov_sum=1.000000)),
  (4,'Junio (pool vacío) 0 filas', m.jun_n::text,'0',(m.jun_n=0)),
  (5,'Reparto julio Σ=monto', m.jul_rep::text,'100000.00',(m.jul_rep=100000.00)),
  (6,'Reparto noviembre Σ=monto', m.nov_rep::text,'12345.67',(m.nov_rep=12345.67)),
  (7,'Residual julio → Remo (D-9E-08)', m.gana_jul,'Remo',(m.gana_jul='Remo')),
  (8,'Residual noviembre → Franco (D-9E-08)', m.gana_nov,'Franco',(m.gana_nov='Franco')),
  (9,'Detalle julio: participan', m.det_jul::text,'4',(m.det_jul=4)),
  (10,'Detalle noviembre: participan', m.det_nov::text,'5',(m.det_nov=5)),
  (11,'Funciones 9E abiertas a EXECUTE', m.exec_abiertas::text,'0',(m.exec_abiertas=0)),
  (12,'EXCLUDE public (9E no agrega)', m.excl_total::text,'3',(m.excl_total=3))
) AS v(orden, chequeo, obtenido, esperado, ok)
UNION ALL
SELECT 999,'TOTAL D (9E)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES
     (m.fns=3),(m.jul_sum=1.000000),(m.nov_sum=1.000000),(m.jun_n=0),(m.jul_rep=100000.00),(m.nov_rep=12345.67),
     (m.gana_jul='Remo'),(m.gana_nov='Franco'),(m.det_jul=4),(m.det_nov=5),(m.exec_abiertas=0),(m.excl_total=3)
   ) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES
     (m.fns=3),(m.jul_sum=1.000000),(m.nov_sum=1.000000),(m.jun_n=0),(m.jul_rep=100000.00),(m.nov_rep=12345.67),
     (m.gana_jul='Remo'),(m.gana_nov='Franco'),(m.det_jul=4),(m.det_nov=5),(m.exec_abiertas=0),(m.excl_total=3)
   ) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;

-- ============================================================================
-- 6. REVERSIÓN CONCEPTUAL (NO ejecutar; sin DROP ... CASCADE).
--    Solo funciones; ningún objeto depende de ellas todavía (9G las consumirá,
--    pero 9G aún no está). DROP directo, sin CASCADE.
-- ----------------------------------------------------------------------------
-- BEGIN;
--   DROP FUNCTION IF EXISTS detalle_participacion(DATE);
--   DROP FUNCTION IF EXISTS repartir_por_matriz(DATE, NUMERIC);
--   DROP FUNCTION IF EXISTS matriz_participacion(DATE);
-- COMMIT;
-- ============================================================================
