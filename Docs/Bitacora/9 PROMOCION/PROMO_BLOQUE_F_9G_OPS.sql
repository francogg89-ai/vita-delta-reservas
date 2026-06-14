-- ============================================================================
-- PROMO_BLOQUE_F_9G_OPS.sql
-- Promoción del Carril B a OPS — BLOQUE F (solo 9G).
-- Etapa PROMO. Depende de B1(9C), C(9D), D(9E), E(9F) commiteados y VERDE en OPS.
-- Contenido: 6 funciones READ-ONLY de la cascada de liquidación de 11 pasos.
-- SIN tablas, SIN seed, SIN writes de datos operativos. Bodies VERBATIM de
-- 9G_BLOQUE_C_FUNCIONES_v2.sql. NO toca 9C/9D/9E/9F/9H ni helper 9B.
--
-- Nota sobre datos: en OPS estas funciones leen los `pagos` REALES y un
-- `gastos_internos` VACÍO (sin fixture). La validación numérica del ejemplo
-- canónico (julio @0.25 → base de ganancia 456.150, etc.) se hizo en TEST y se
-- re-validó en harness con datos sintéticos; acá los asserts son INVARIANTES
-- INDEPENDIENTES DE LOS MONTOS (guard de pct, conservación Σ paso9 = paso8,
-- pool de julio activo / junio vacío, normalización de período) + que las
-- funciones corren sin error contra los datos reales.
--
-- ESTRUCTURA: BEGIN → gate → DDL (6 funciones) → hardening → asserts → COMMIT →
-- verificación read-only posterior → reversión sin DROP ... CASCADE.
-- Correr con NADA seleccionado (L-8A-01).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. GATE — marcador ops + identidad + 9C/9D/9E/9F presentes (orden) + 9G ausente.
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb text; v_cab int; v_soc int; v_seam int; v_act int; v_9e int; v_9f int; v_9g int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE F: marcador ambiente=% (esperado ops).', COALESCE(v_amb,'<ausente>'); END IF;

  SELECT count(*) INTO v_cab FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
   WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  SELECT count(*) INTO v_soc FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
   WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1;
  IF v_cab<>5 OR v_soc<>3 THEN RAISE EXCEPTION 'GATE F: identidad (cabañas=%/5, socios=%/3).', v_cab, v_soc; END IF;

  -- Cadena 9C→9F presente (orden de la promoción)
  SELECT count(*) INTO v_seam FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='resolver_beneficiario';
  SELECT count(*) INTO v_act FROM activaciones_operativas;
  SELECT count(*) INTO v_9e FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('matriz_participacion','repartir_por_matriz','detalle_participacion');
  SELECT count(*) INTO v_9f FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r' AND c.relname='gastos_internos';
  IF v_seam<>1 THEN RAISE EXCEPTION 'GATE F: seam 9C ausente (correr B1).'; END IF;
  IF v_act<>5  THEN RAISE EXCEPTION 'GATE F: activaciones 9D=% (esperado 5; correr C).', v_act; END IF;
  IF v_9e<>3   THEN RAISE EXCEPTION 'GATE F: funciones 9E=% (esperado 3; correr D).', v_9e; END IF;
  IF v_9f<>1   THEN RAISE EXCEPTION 'GATE F: tabla 9F gastos_internos ausente (correr E).'; END IF;

  -- 9G ausente — guard de re-ejecución
  SELECT count(*) INTO v_9g FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                       'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo');
  IF v_9g<>0 THEN RAISE EXCEPTION 'GATE F: funciones 9G ya presentes (=%). F no se re-ejecuta.', v_9g; END IF;

  RAISE NOTICE 'GATE F OK — OPS post-9F; 9G ausente.';
END
$gate$;

-- ----------------------------------------------------------------------------
-- 2. DDL — 6 funciones read-only (VERBATIM 9G §C v2). LANGUAGE sql, sin variables
--    v_ (sin riesgo Dashboard). DROP IF EXISTS por idempotencia, sin CASCADE.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.cascada_periodo(DATE, NUMERIC);
DROP FUNCTION IF EXISTS public.saldo_socios_periodo(DATE, NUMERIC);
DROP FUNCTION IF EXISTS public.incidencia_gasto(BIGINT);
DROP FUNCTION IF EXISTS public.reporte_overrides_periodo(DATE);
DROP FUNCTION IF EXISTS public.reporte_5_vs_fiscal_periodo(DATE);
DROP FUNCTION IF EXISTS public.gastos_sin_incidencia_periodo(DATE);

CREATE FUNCTION public.cascada_periodo(p_periodo DATE, p_pct_operativo NUMERIC)
RETURNS TABLE (paso SMALLINT, concepto TEXT, id_socio BIGINT, socio TEXT, monto NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER AS $$
WITH params AS (
  SELECT date_trunc('month', p_periodo)::date AS mes,
         (p_pct_operativo IS NULL
          OR p_pct_operativo < 0 OR p_pct_operativo > 1) AS pct_invalido
),
hay_pool AS (
  SELECT EXISTS (SELECT 1 FROM params pr
                 CROSS JOIN LATERAL matriz_participacion(pr.mes)) AS ok
),
ing AS (  -- caja percibida del mes (D-9G-02 / D-9G-03)
  SELECT COALESCE(SUM(p.monto_recibido) FILTER (WHERE p.tipo IN ('sena','saldo')), 0) AS p1,
         COALESCE(SUM(p.monto_recibido) FILTER (WHERE p.tipo = 'extra'), 0)           AS p6
  FROM params pr
  LEFT JOIN pagos p
    ON p.estado::text = 'confirmado'
   AND date_trunc('month', p.created_at)::date = pr.mes
),
gas AS (
  SELECT COALESCE(SUM(g.monto) FILTER (WHERE g.clase = 'A'), 0) AS ga,
         COALESCE(SUM(g.monto) FILTER (WHERE g.clase = 'C'), 0) AS gc
  FROM params pr
  LEFT JOIN gastos_internos g ON g.periodo = pr.mes
),
calc AS (  -- D-9G-06: con pool vacío, A y C no se restan (se reportan aparte)
  SELECT i.p1,
         CASE WHEN hp.ok THEN -g.ga ELSE 0 END AS p2,
         i.p1 - CASE WHEN hp.ok THEN g.ga ELSE 0 END AS p3,
         -ROUND(GREATEST(i.p1 - CASE WHEN hp.ok THEN g.ga ELSE 0 END, 0)
                * p_pct_operativo, 2) AS p4,
         i.p6,
         CASE WHEN hp.ok THEN -g.gc ELSE 0 END AS p7
  FROM ing i CROSS JOIN gas g CROSS JOIN hay_pool hp
),
calc2 AS (SELECT c.*, c.p3 + c.p4 AS p5 FROM calc c),
calc3 AS (SELECT c.*, c.p5 + c.p6 + c.p7 AS p8 FROM calc2 c),
-- incidencias E: 100% al beneficiario (seam 9C), independiente de activación
inc_e AS (
  SELECT resolver_beneficiario(g.id_cabana, pr.mes) AS id_socio, SUM(g.monto) AS monto
  FROM params pr
  JOIN gastos_internos g ON g.periodo = pr.mes AND g.clase = 'E'
  GROUP BY 1
),
-- incidencias D: zona -> cabañas ACTIVAS de la zona en el mes -> valor_relativo
-- con residual interno (D-9G-05: ROUND por cabaña; residual a mayor
-- valor_relativo, empate a menor id_cabana) -> seam -> socio
d_cab AS (
  SELECT g.id_gasto, g.monto AS monto_gasto, c.id_cabana, c.valor_relativo
  FROM params pr
  JOIN gastos_internos g ON g.periodo = pr.mes AND g.clase = 'D'
  JOIN cabana_zona cz ON cz.id_zona = g.id_zona
  JOIN cabanas c ON c.id_cabana = cz.id_cabana
  WHERE EXISTS (SELECT 1 FROM activaciones_operativas a
                 WHERE a.id_cabana = c.id_cabana
                   AND daterange(a.fecha_desde, a.fecha_hasta, '[)')
                       @> daterange(pr.mes, (pr.mes + INTERVAL '1 month')::date, '[)'))
),
d_pesos AS (
  SELECT dc.id_gasto, dc.monto_gasto, dc.id_cabana,
         ROUND(dc.monto_gasto * dc.valor_relativo
               / SUM(dc.valor_relativo) OVER (PARTITION BY dc.id_gasto), 2) AS monto_base,
         ROW_NUMBER() OVER (PARTITION BY dc.id_gasto
                            ORDER BY dc.valor_relativo DESC, dc.id_cabana ASC) AS rk
  FROM d_cab dc
),
d_resid AS (
  SELECT dp.id_gasto, MAX(dp.monto_gasto) - SUM(dp.monto_base) AS residual
  FROM d_pesos dp GROUP BY dp.id_gasto
),
d_final AS (
  SELECT dp.id_gasto, dp.id_cabana,
         dp.monto_base + CASE WHEN dp.rk = 1 THEN dr.residual ELSE 0 END AS monto_cab
  FROM d_pesos dp JOIN d_resid dr ON dr.id_gasto = dp.id_gasto
),
inc_d AS (
  SELECT resolver_beneficiario(df.id_cabana, pr.mes) AS id_socio, SUM(df.monto_cab) AS monto
  FROM d_final df CROSS JOIN params pr
  GROUP BY 1
),
inc_de AS (
  SELECT x.id_socio, SUM(x.monto) AS monto
  FROM (SELECT * FROM inc_d UNION ALL SELECT * FROM inc_e) x
  GROUP BY x.id_socio
),
p9 AS (
  SELECT r.id_socio, r.monto_asignado
  FROM calc3 c CROSS JOIN params pr
  CROSS JOIN LATERAL repartir_por_matriz(pr.mes, c.p8) r
)
-- guard explícito (D-9G-01)
SELECT 0::smallint, 'PARAMETRO_INVALIDO_PCT_OPERATIVO'::text,
       NULL::bigint, NULL::text, p_pct_operativo
FROM params pr WHERE pr.pct_invalido

UNION ALL  -- pasos 1 a 8 (agregados, id_socio NULL)
SELECT v.paso, v.concepto, NULL::bigint, NULL::text, v.monto
FROM calc3 c CROSS JOIN params pr
CROSS JOIN LATERAL (VALUES
  (1::smallint, 'ingreso_operativo_sena_saldo_confirmados', c.p1),
  (2::smallint, 'gastos_clase_A',                           c.p2),
  (3::smallint, 'base_operativa',                           c.p3),
  (4::smallint, 'retribucion_operativo_sobre_base_positiva',c.p4),
  (5::smallint, 'resultado_post_operativo',                 c.p5),
  (6::smallint, 'ingresos_extra_post_operativo',            c.p6),
  (7::smallint, 'gastos_clase_C',                           c.p7),
  (8::smallint, 'base_de_ganancia',                         c.p8)
) v(paso, concepto, monto)
WHERE NOT pr.pct_invalido

UNION ALL  -- paso 9: reparto por matriz (residual D-9E-08 dentro de repartir)
SELECT 9::smallint, 'reparto_por_matriz', p9.id_socio, s.nombre, p9.monto_asignado
FROM p9 JOIN socios s ON s.id_socio = p9.id_socio
CROSS JOIN params pr WHERE NOT pr.pct_invalido

UNION ALL  -- paso 10: incidencias D+E netas por socio (negativas)
SELECT 10::smallint, 'incidencias_clases_D_E', i.id_socio, s.nombre, -i.monto
FROM inc_de i JOIN socios s ON s.id_socio = i.id_socio
CROSS JOIN params pr WHERE NOT pr.pct_invalido

UNION ALL  -- paso 11: saldo final = paso 9 + paso 10 (universo D-9G-08)
SELECT 11::smallint, 'saldo_final_socio', u.id_socio, s.nombre,
       COALESCE(p9b.monto_asignado, 0) - COALESCE(de.monto, 0)
FROM (SELECT p9.id_socio FROM p9
      UNION SELECT inc_de.id_socio FROM inc_de) u
JOIN socios s ON s.id_socio = u.id_socio
LEFT JOIN p9 p9b ON p9b.id_socio = u.id_socio
LEFT JOIN inc_de de ON de.id_socio = u.id_socio
CROSS JOIN params pr WHERE NOT pr.pct_invalido

ORDER BY 1, 3 NULLS FIRST;
$$;

CREATE FUNCTION public.saldo_socios_periodo(p_periodo DATE, p_pct_operativo NUMERIC)
RETURNS TABLE (id_socio BIGINT, socio TEXT, saldo_bruto NUMERIC, gastos_d NUMERIC,
               gastos_e NUMERIC, saldo_final NUMERIC, desembolsado_periodo NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER AS $$
WITH params AS (
  SELECT date_trunc('month', p_periodo)::date AS mes,
         (p_pct_operativo IS NULL
          OR p_pct_operativo < 0 OR p_pct_operativo > 1) AS pct_invalido
),
hay_pool AS (
  SELECT EXISTS (SELECT 1 FROM params pr
                 CROSS JOIN LATERAL matriz_participacion(pr.mes)) AS ok
),
ing AS (
  SELECT COALESCE(SUM(p.monto_recibido) FILTER (WHERE p.tipo IN ('sena','saldo')), 0) AS p1,
         COALESCE(SUM(p.monto_recibido) FILTER (WHERE p.tipo = 'extra'), 0)           AS p6
  FROM params pr
  LEFT JOIN pagos p
    ON p.estado::text = 'confirmado'
   AND date_trunc('month', p.created_at)::date = pr.mes
),
gas AS (
  SELECT COALESCE(SUM(g.monto) FILTER (WHERE g.clase = 'A'), 0) AS ga,
         COALESCE(SUM(g.monto) FILTER (WHERE g.clase = 'C'), 0) AS gc
  FROM params pr
  LEFT JOIN gastos_internos g ON g.periodo = pr.mes
),
calc AS (
  SELECT (i.p1 - CASE WHEN hp.ok THEN g.ga ELSE 0 END)
         - ROUND(GREATEST(i.p1 - CASE WHEN hp.ok THEN g.ga ELSE 0 END, 0)
                 * p_pct_operativo, 2)
         + i.p6
         - CASE WHEN hp.ok THEN g.gc ELSE 0 END AS p8
  FROM ing i CROSS JOIN gas g CROSS JOIN hay_pool hp
),
inc_e AS (
  SELECT resolver_beneficiario(g.id_cabana, pr.mes) AS id_socio, SUM(g.monto) AS monto
  FROM params pr
  JOIN gastos_internos g ON g.periodo = pr.mes AND g.clase = 'E'
  GROUP BY 1
),
d_cab AS (
  SELECT g.id_gasto, g.monto AS monto_gasto, c.id_cabana, c.valor_relativo
  FROM params pr
  JOIN gastos_internos g ON g.periodo = pr.mes AND g.clase = 'D'
  JOIN cabana_zona cz ON cz.id_zona = g.id_zona
  JOIN cabanas c ON c.id_cabana = cz.id_cabana
  WHERE EXISTS (SELECT 1 FROM activaciones_operativas a
                 WHERE a.id_cabana = c.id_cabana
                   AND daterange(a.fecha_desde, a.fecha_hasta, '[)')
                       @> daterange(pr.mes, (pr.mes + INTERVAL '1 month')::date, '[)'))
),
d_pesos AS (
  SELECT dc.id_gasto, dc.monto_gasto, dc.id_cabana,
         ROUND(dc.monto_gasto * dc.valor_relativo
               / SUM(dc.valor_relativo) OVER (PARTITION BY dc.id_gasto), 2) AS monto_base,
         ROW_NUMBER() OVER (PARTITION BY dc.id_gasto
                            ORDER BY dc.valor_relativo DESC, dc.id_cabana ASC) AS rk
  FROM d_cab dc
),
d_resid AS (
  SELECT dp.id_gasto, MAX(dp.monto_gasto) - SUM(dp.monto_base) AS residual
  FROM d_pesos dp GROUP BY dp.id_gasto
),
d_final AS (
  SELECT dp.id_gasto, dp.id_cabana,
         dp.monto_base + CASE WHEN dp.rk = 1 THEN dr.residual ELSE 0 END AS monto_cab
  FROM d_pesos dp JOIN d_resid dr ON dr.id_gasto = dp.id_gasto
),
inc_d AS (
  SELECT resolver_beneficiario(df.id_cabana, pr.mes) AS id_socio, SUM(df.monto_cab) AS monto
  FROM d_final df CROSS JOIN params pr
  GROUP BY 1
),
p9 AS (
  SELECT r.id_socio, r.monto_asignado
  FROM calc c CROSS JOIN params pr
  CROSS JOIN LATERAL repartir_por_matriz(pr.mes, c.p8) r
),
universo AS (
  SELECT p9.id_socio FROM p9
  UNION SELECT inc_d.id_socio FROM inc_d
  UNION SELECT inc_e.id_socio FROM inc_e
)
SELECT NULL::bigint, 'PARAMETRO_INVALIDO_PCT_OPERATIVO'::text,
       NULL::numeric, NULL::numeric, NULL::numeric, NULL::numeric, NULL::numeric
FROM params pr WHERE pr.pct_invalido

UNION ALL
SELECT u.id_socio, s.nombre,
       COALESCE(p9b.monto_asignado, 0)                AS saldo_bruto,
       -COALESCE(d.monto, 0)                          AS gastos_d,
       -COALESCE(e.monto, 0)                          AS gastos_e,
       COALESCE(p9b.monto_asignado, 0)
         - COALESCE(d.monto, 0) - COALESCE(e.monto, 0) AS saldo_final,
       COALESCE((SELECT SUM(g.monto) FROM gastos_internos g CROSS JOIN params pr2
                  WHERE g.periodo = pr2.mes
                    AND g.pagador_tipo = 'socio'
                    AND g.id_socio_pagador = u.id_socio), 0) AS desembolsado_periodo
FROM universo u
JOIN socios s ON s.id_socio = u.id_socio
LEFT JOIN p9 p9b ON p9b.id_socio = u.id_socio
LEFT JOIN inc_d d ON d.id_socio = u.id_socio
LEFT JOIN inc_e e ON e.id_socio = u.id_socio
CROSS JOIN params pr WHERE NOT pr.pct_invalido

ORDER BY 1 NULLS FIRST;
$$;

CREATE FUNCTION public.incidencia_gasto(p_id_gasto BIGINT)
RETURNS TABLE (destino TEXT, id_socio BIGINT, socio TEXT, monto NUMERIC, regla TEXT)
LANGUAGE sql STABLE SECURITY INVOKER AS $$
WITH g AS (
  SELECT gi.id_gasto, gi.clase, gi.periodo, gi.monto, gi.id_zona, gi.id_cabana
  FROM gastos_internos gi WHERE gi.id_gasto = p_id_gasto
),
hay_pool AS (
  SELECT EXISTS (SELECT 1 FROM g
                 CROSS JOIN LATERAL matriz_participacion(g.periodo)) AS ok
),
d_cab AS (
  SELECT g.monto AS monto_gasto, c.id_cabana, c.valor_relativo, g.periodo
  FROM g
  JOIN cabana_zona cz ON cz.id_zona = g.id_zona
  JOIN cabanas c ON c.id_cabana = cz.id_cabana
  WHERE g.clase = 'D'
    AND EXISTS (SELECT 1 FROM activaciones_operativas a
                 WHERE a.id_cabana = c.id_cabana
                   AND daterange(a.fecha_desde, a.fecha_hasta, '[)')
                       @> daterange(g.periodo, (g.periodo + INTERVAL '1 month')::date, '[)'))
),
d_pesos AS (
  SELECT dc.monto_gasto, dc.id_cabana, dc.periodo,
         ROUND(dc.monto_gasto * dc.valor_relativo
               / SUM(dc.valor_relativo) OVER (), 2) AS monto_base,
         ROW_NUMBER() OVER (ORDER BY dc.valor_relativo DESC, dc.id_cabana ASC) AS rk
  FROM d_cab dc
),
d_final AS (
  SELECT dp.id_cabana, dp.periodo,
         dp.monto_base
           + CASE WHEN dp.rk = 1
                  THEN (SELECT MAX(x.monto_gasto) - SUM(x.monto_base) FROM d_pesos x)
                  ELSE 0 END AS monto_cab
  FROM d_pesos dp
)
-- A: estructural, una fila al pool pre-operativo (solo si hay pool)
SELECT 'pool_pre_operativo'::text, NULL::bigint, NULL::text, g.monto,
       'clase A: entra al pool antes del % operativo; absorción efectiva '
       || 'operativo/beneficiarios depende del período completo (GREATEST paso 4); '
       || 'ver cascada_periodo'::text
FROM g CROSS JOIN hay_pool hp
WHERE g.clase = 'A' AND hp.ok

UNION ALL  -- C: exacto por matriz del período (§4.2)
SELECT 'socio'::text, r.id_socio, s.nombre, r.monto_asignado,
       'clase C: equivalente a deduccion post-matriz (§4.2); reparto exacto '
       || 'por matriz del período (residual D-9E-08)'::text
FROM g
CROSS JOIN LATERAL repartir_por_matriz(g.periodo, g.monto) r
JOIN socios s ON s.id_socio = r.id_socio
WHERE g.clase = 'C'

UNION ALL  -- D: zona -> activas -> valor_relativo -> seam
SELECT 'socio'::text, resolver_beneficiario(df.id_cabana, df.periodo), s.nombre,
       SUM(df.monto_cab),
       'clase D: zona repartida entre cabañas activas del período por '
       || 'valor_relativo (residual D-9G-05) hacia el beneficiario (seam 9C)'::text
FROM d_final df
JOIN socios s ON s.id_socio = resolver_beneficiario(df.id_cabana, df.periodo)
GROUP BY resolver_beneficiario(df.id_cabana, df.periodo), s.nombre

UNION ALL  -- E: 100% al beneficiario de la cabaña
SELECT 'socio'::text, resolver_beneficiario(g.id_cabana, g.periodo), s.nombre, g.monto,
       'clase E: 100% al beneficiario de la cabaña (seam 9C), '
       || 'independiente de la activación'::text
FROM g
JOIN socios s ON s.id_socio = resolver_beneficiario(g.id_cabana, g.periodo)
WHERE g.clase = 'E'

ORDER BY 2 NULLS FIRST;
$$;

CREATE FUNCTION public.reporte_overrides_periodo(p_periodo DATE)
RETURNS TABLE (id_gasto BIGINT, clase TEXT, clase_sugerida TEXT, etiqueta TEXT,
               monto NUMERIC, comentario TEXT)
LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT g.id_gasto, g.clase, g.clase_sugerida, g.etiqueta, g.monto, g.comentario
  FROM gastos_internos g
  WHERE g.periodo = date_trunc('month', p_periodo)::date
    AND g.clase IS DISTINCT FROM g.clase_sugerida
  ORDER BY g.id_gasto;
$$;

CREATE FUNCTION public.reporte_5_vs_fiscal_periodo(p_periodo DATE)
RETURNS TABLE (periodo DATE, total_extra_confirmado NUMERIC,
               total_fiscal_monotributo NUMERIC, diferencia NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER AS $$
  WITH params AS (SELECT date_trunc('month', p_periodo)::date AS mes)
  SELECT pr.mes,
         COALESCE((SELECT SUM(p.monto_recibido) FROM pagos p
                    WHERE p.tipo = 'extra' AND p.estado::text = 'confirmado'
                      AND date_trunc('month', p.created_at)::date = pr.mes), 0),
         COALESCE((SELECT SUM(g.monto) FROM gastos_internos g
                    WHERE g.periodo = pr.mes
                      AND lower(btrim(g.etiqueta)) = 'monotributo'), 0),
         COALESCE((SELECT SUM(p.monto_recibido) FROM pagos p
                    WHERE p.tipo = 'extra' AND p.estado::text = 'confirmado'
                      AND date_trunc('month', p.created_at)::date = pr.mes), 0)
         - COALESCE((SELECT SUM(g.monto) FROM gastos_internos g
                      WHERE g.periodo = pr.mes
                        AND lower(btrim(g.etiqueta)) = 'monotributo'), 0)
  FROM params pr;
$$;

CREATE FUNCTION public.gastos_sin_incidencia_periodo(p_periodo DATE)
RETURNS TABLE (id_gasto BIGINT, clase TEXT, etiqueta TEXT, monto NUMERIC, motivo TEXT)
LANGUAGE sql STABLE SECURITY INVOKER AS $$
  WITH params AS (SELECT date_trunc('month', p_periodo)::date AS mes)
  SELECT g.id_gasto, g.clase, g.etiqueta, g.monto, 'pool_vacio'::text
  FROM gastos_internos g CROSS JOIN params pr
  WHERE g.periodo = pr.mes AND g.clase IN ('A','C')
    AND NOT EXISTS (SELECT 1 FROM matriz_participacion(pr.mes))

  UNION ALL
  SELECT g.id_gasto, g.clase, g.etiqueta, g.monto, 'zona_sin_activas'::text
  FROM gastos_internos g CROSS JOIN params pr
  WHERE g.periodo = pr.mes AND g.clase = 'D'
    AND NOT EXISTS (
      SELECT 1
      FROM cabana_zona cz
      JOIN activaciones_operativas a ON a.id_cabana = cz.id_cabana
      WHERE cz.id_zona = g.id_zona
        AND daterange(a.fecha_desde, a.fecha_hasta, '[)')
            @> daterange(pr.mes, (pr.mes + INTERVAL '1 month')::date, '[)'))

  ORDER BY 1;
$$;


-- ----------------------------------------------------------------------------
-- 3. HARDENING — REVOKE EXECUTE de las 6 a PUBLIC + roles Data API.
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.cascada_periodo(DATE, NUMERIC)              FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.saldo_socios_periodo(DATE, NUMERIC)         FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.incidencia_gasto(BIGINT)                    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.reporte_overrides_periodo(DATE)             FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.reporte_5_vs_fiscal_periodo(DATE)           FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.gastos_sin_incidencia_periodo(DATE)         FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. ASSERTS — invariantes independientes de los montos + corridas sin error
--    contra los datos reales de OPS (pool de julio activo / junio vacío; gastos
--    internos vacío). La validación numérica del canónico es harness/TEST.
-- ----------------------------------------------------------------------------
DO $assert$
DECLARE
  v_fns         int;
  v_exec_open   int;
  v_g15 int; v_gnull int; v_gneg int;
  v_p9_jul int; v_p9_jul_sum numeric; v_p8_jul numeric;
  v_p9_jun int;
  v_norm15 numeric; v_norm01 numeric;
  v_pasos18 int;
  v_ss_jul int; v_ss_incoh int;
  v_inc0 int; v_ovr0 int; v_fis1 int; v_sin0 int;
  v_excl int;
  v_dataapi oid[];
BEGIN
  v_dataapi := array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL);

  -- F1: 6 funciones presentes
  SELECT count(*) INTO v_fns FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                       'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo');
  IF v_fns <> 6 THEN RAISE EXCEPTION 'ASSERT F1: funciones 9G=% (esperado 6).', v_fns; END IF;

  -- F2 (hardening): 0 funciones 9G abiertas a EXECUTE para PUBLIC/Data API
  SELECT count(*) INTO v_exec_open FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                       'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo')
     AND (p.proacl IS NULL
          OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                     WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY (v_dataapi)));
  IF v_exec_open <> 0 THEN RAISE EXCEPTION 'ASSERT F2: funciones 9G abiertas a EXECUTE=% (esperado 0).', v_exec_open; END IF;

  -- F3 (guard pct, D-9G-01): pct inválido => exactamente 1 fila paso=0
  SELECT count(*) INTO v_g15   FROM cascada_periodo('2026-07-01', 1.5)  WHERE paso=0;
  SELECT count(*) INTO v_gnull FROM cascada_periodo('2026-07-01', NULL) WHERE paso=0;
  SELECT count(*) INTO v_gneg  FROM cascada_periodo('2026-07-01', -0.1) WHERE paso=0;
  IF v_g15<>1 OR v_gnull<>1 OR v_gneg<>1 THEN
    RAISE EXCEPTION 'ASSERT F3: guard pct (1.5=%, NULL=%, -0.1=%) esperado 1/1/1.', v_g15, v_gnull, v_gneg; END IF;

  -- F4 (conservación): julio pool activo => paso 9 con 3 socios y Σ(paso9)=paso8
  SELECT count(*), COALESCE(sum(monto),0) INTO v_p9_jul, v_p9_jul_sum
    FROM cascada_periodo('2026-07-01', 0.25) WHERE paso=9;
  SELECT monto INTO v_p8_jul FROM cascada_periodo('2026-07-01', 0.25) WHERE paso=8;
  IF v_p9_jul <> 3 THEN RAISE EXCEPTION 'ASSERT F4a: paso9 julio filas=% (esperado 3).', v_p9_jul; END IF;
  IF v_p9_jul_sum <> v_p8_jul THEN
    RAISE EXCEPTION 'ASSERT F4b: Σ paso9=% != paso8=% (conservación rota).', v_p9_jul_sum, v_p8_jul; END IF;

  -- F5 (pool vacío): junio sin pool => paso 9 con 0 filas
  SELECT count(*) INTO v_p9_jun FROM cascada_periodo('2026-06-01', 0.25) WHERE paso=9;
  IF v_p9_jun <> 0 THEN RAISE EXCEPTION 'ASSERT F5: paso9 junio filas=% (esperado 0, pool vacío).', v_p9_jun; END IF;

  -- F6 (normalización de período): día 15 ≡ día 1
  SELECT COALESCE(sum(monto),0) INTO v_norm15 FROM cascada_periodo('2026-07-15', 0.25) WHERE paso=9;
  SELECT COALESCE(sum(monto),0) INTO v_norm01 FROM cascada_periodo('2026-07-01', 0.25) WHERE paso=9;
  IF v_norm15 <> v_norm01 THEN RAISE EXCEPTION 'ASSERT F6: normalización falló (día15=% vs día1=%).', v_norm15, v_norm01; END IF;

  -- F7: pasos 1-8 siempre presentes (8 filas)
  SELECT count(*) INTO v_pasos18 FROM cascada_periodo('2026-07-01', 0.25) WHERE paso BETWEEN 1 AND 8;
  IF v_pasos18 <> 8 THEN RAISE EXCEPTION 'ASSERT F7: pasos 1-8=% (esperado 8).', v_pasos18; END IF;

  -- F8: saldo_socios_periodo julio => 3 socios; coherencia saldo_final=bruto+d+e (todas)
  SELECT count(*),
         count(*) FILTER (WHERE saldo_final <> saldo_bruto + gastos_d + gastos_e)
    INTO v_ss_jul, v_ss_incoh FROM saldo_socios_periodo('2026-07-01', 0.25);
  IF v_ss_jul <> 3 THEN RAISE EXCEPTION 'ASSERT F8a: saldo_socios julio filas=% (esperado 3).', v_ss_jul; END IF;
  IF v_ss_incoh <> 0 THEN RAISE EXCEPTION 'ASSERT F8b: % filas con saldo_final != bruto+d+e.', v_ss_incoh; END IF;

  -- F9: incidencia_gasto de un id inexistente => 0 filas (gastos_internos vacío en OPS)
  SELECT count(*) INTO v_inc0 FROM incidencia_gasto(999999999);
  IF v_inc0 <> 0 THEN RAISE EXCEPTION 'ASSERT F9: incidencia_gasto(inexistente) filas=% (esperado 0).', v_inc0; END IF;

  -- F10: reporte_overrides_periodo => 0 filas (gastos vacío)
  SELECT count(*) INTO v_ovr0 FROM reporte_overrides_periodo('2026-07-01');
  IF v_ovr0 <> 0 THEN RAISE EXCEPTION 'ASSERT F10: overrides julio filas=% (esperado 0).', v_ovr0; END IF;

  -- F11: reporte_5_vs_fiscal_periodo => siempre exactamente 1 fila
  SELECT count(*) INTO v_fis1 FROM reporte_5_vs_fiscal_periodo('2026-07-01');
  IF v_fis1 <> 1 THEN RAISE EXCEPTION 'ASSERT F11: 5_vs_fiscal julio filas=% (esperado 1).', v_fis1; END IF;

  -- F12: gastos_sin_incidencia_periodo => 0 filas (gastos vacío)
  SELECT count(*) INTO v_sin0 FROM gastos_sin_incidencia_periodo('2026-07-01');
  IF v_sin0 <> 0 THEN RAISE EXCEPTION 'ASSERT F12: sin_incidencia julio filas=% (esperado 0).', v_sin0; END IF;

  -- F13 (aislamiento): 9G es read-only => EXCLUDE en public sigue = 3
  SELECT count(*) INTO v_excl FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
   WHERE con.contype='x' AND n.nspname='public';
  IF v_excl <> 3 THEN RAISE EXCEPTION 'ASSERT F13: EXCLUDE en public=% (esperado 3).', v_excl; END IF;

  RAISE NOTICE 'ASSERTS F OK — 9G consistente (6 funciones, guard, conservación, hardening). Listo para COMMIT.';
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
        AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                          'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo')) AS fns,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace, dataapi
      WHERE n.nspname='public' AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
            'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo')
        AND (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
             WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY (dataapi.oids)))) AS exec_open,
    (SELECT count(*) FROM cascada_periodo('2026-07-01', 1.5) WHERE paso=0) AS guard,
    (SELECT count(*) FROM cascada_periodo('2026-07-01', 0.25) WHERE paso=9) AS p9_jul,
    ((SELECT COALESCE(sum(monto),0) FROM cascada_periodo('2026-07-01',0.25) WHERE paso=9)
      = (SELECT monto FROM cascada_periodo('2026-07-01',0.25) WHERE paso=8)) AS conserva,
    (SELECT count(*) FROM cascada_periodo('2026-06-01', 0.25) WHERE paso=9) AS p9_jun,
    (SELECT count(*) FROM saldo_socios_periodo('2026-07-01',0.25)) AS ss_jul,
    (SELECT count(*) FROM reporte_5_vs_fiscal_periodo('2026-07-01')) AS fis,
    (SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE con.contype='x' AND n.nspname='public') AS excl
)
SELECT v.orden, v.chequeo, v.obtenido, v.esperado,
       CASE WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (1,'6 funciones 9G presentes', m.fns::text,'6',(m.fns=6)),
  (2,'Funciones 9G abiertas a EXECUTE', m.exec_open::text,'0',(m.exec_open=0)),
  (3,'Guard pct inválido (1 fila paso=0)', m.guard::text,'1',(m.guard=1)),
  (4,'Cascada julio: paso 9 (3 socios)', m.p9_jul::text,'3',(m.p9_jul=3)),
  (5,'Conservación Σ paso9 = paso8 (julio)', m.conserva::text,'true',(m.conserva)),
  (6,'Cascada junio: paso 9 (pool vacío)', m.p9_jun::text,'0',(m.p9_jun=0)),
  (7,'saldo_socios julio (3 socios)', m.ss_jul::text,'3',(m.ss_jul=3)),
  (8,'reporte_5_vs_fiscal (1 fila)', m.fis::text,'1',(m.fis=1)),
  (9,'EXCLUDE public (9G no agrega)', m.excl::text,'3',(m.excl=3))
) AS v(orden, chequeo, obtenido, esperado, ok)
UNION ALL
SELECT 999,'TOTAL F (9G)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES
     (m.fns=6),(m.exec_open=0),(m.guard=1),(m.p9_jul=3),(m.conserva),(m.p9_jun=0),(m.ss_jul=3),(m.fis=1),(m.excl=3)
   ) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES
     (m.fns=6),(m.exec_open=0),(m.guard=1),(m.p9_jul=3),(m.conserva),(m.p9_jun=0),(m.ss_jul=3),(m.fis=1),(m.excl=3)
   ) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;

-- ============================================================================
-- 6. REVERSIÓN CONCEPTUAL (NO ejecutar; sin DROP ... CASCADE).
--    Solo funciones; nada depende de ellas todavía (9H las consumirá, pero aún
--    no existe). DROP directo, sin CASCADE.
-- ----------------------------------------------------------------------------
-- BEGIN;
--   DROP FUNCTION IF EXISTS public.gastos_sin_incidencia_periodo(DATE);
--   DROP FUNCTION IF EXISTS public.reporte_5_vs_fiscal_periodo(DATE);
--   DROP FUNCTION IF EXISTS public.reporte_overrides_periodo(DATE);
--   DROP FUNCTION IF EXISTS public.incidencia_gasto(BIGINT);
--   DROP FUNCTION IF EXISTS public.saldo_socios_periodo(DATE, NUMERIC);
--   DROP FUNCTION IF EXISTS public.cascada_periodo(DATE, NUMERIC);
-- COMMIT;
-- ============================================================================
