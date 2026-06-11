-- ============================================================================
-- VITA DELTA · ETAPA 9G · BLOQUE C v2 — LAS 6 FUNCIONES READ-ONLY DE LA CASCADA
-- ----------------------------------------------------------------------------
-- Entorno objetivo : TEST (vita-delta-test). Promoción a OPS: junto con el
--                    paquete contable completo (decisión vigente).
-- Naturaleza       : solo DDL de funciones (DROP / CREATE / REVOKE). Ninguna
--                    función escribe: todas LANGUAGE sql STABLE SECURITY INVOKER.
-- Disciplina       : DROP y CREATE en RUNS SEPARADOS (quirk del SQL Editor:
--                    CREATE OR REPLACE sobre función existente inyecta RLS
--                    espuria). REVOKE de PUBLIC/anon/authenticated/service_role.
-- Convenciones     : p_periodo se normaliza a inicio de mes en TODAS.
--                    Caja percibida (D-9G-03): mes calendario de created_at,
--                    date_trunc en timezone de sesión (UTC en Supabase).
--                    Signos en cascada: ingresos +, gastos/retribución −,
--                    GREATEST(base,0) SOLO en paso 4 (D-9G-07).
--                    D-9G-06: incidencia no derivable NO se resta (pool vacío
--                    para A/C; zona sin activas para D) y se reporta aparte.
--                    Guard pct (D-9G-01): fila explícita, nunca 0 filas mudas.
-- v2: cada run arranca con gate programático de ambiente (DO + RAISE
--     EXCEPTION si <> test). Lógica de funciones SIN cambios vs v1.
-- Orden de runs    :
--   C.1-R1 DROP cascada_periodo + saldo_socios_periodo
--   C.1-R2 CREATE cascada_periodo
--   C.1-R3 CREATE saldo_socios_periodo
--   C.1-R4 REVOKE de ambas
--   C.2-R1 DROP incidencia_gasto + 3 reportes
--   C.2-R2 CREATE incidencia_gasto
--   C.2-R3 CREATE reporte_overrides_periodo
--   C.2-R4 CREATE reporte_5_vs_fiscal_periodo
--   C.2-R5 CREATE gastos_sin_incidencia_periodo
--   C.2-R6 REVOKE de las cuatro
-- La validación numérica completa es el Bloque D (archivo aparte).
-- ============================================================================


-- ████████████████████████████ C.1-R1 · DROP ████████████████████████████████

-- GATE programático de ambiente (v2): primer statement del run; si el
-- proyecto no es TEST, RAISE EXCEPTION y el resto de la selección no se aplica.
DO $gate$
BEGIN
  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
              '(ausente)') <> 'test' THEN
    RAISE EXCEPTION '9G GATE (%): ambiente distinto de test — abortado', 'C.1-R1';
  END IF;
END
$gate$;

DROP FUNCTION IF EXISTS public.cascada_periodo(DATE, NUMERIC);
DROP FUNCTION IF EXISTS public.saldo_socios_periodo(DATE, NUMERIC);

-- ████████████████████████ C.1-R2 · cascada_periodo █████████████████████████
-- Cascada de liquidación de 11 pasos (read-only, deriva, no persiste).
-- Salida: pasos 1-8 una fila c/u (id_socio NULL); pasos 9/10/11 fila por socio.
-- Guard: pct NULL o fuera de [0,1] => UNA fila paso=0 con el valor recibido
-- en monto. Pool vacío: pasos 1-8 salen igual; 9 sin filas; 10/11 solo si hay
-- incidencias derivables (E siempre lo es; D exige zona con activas).

-- GATE programático de ambiente (v2): primer statement del run; si el
-- proyecto no es TEST, RAISE EXCEPTION y el resto de la selección no se aplica.
DO $gate$
BEGIN
  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
              '(ausente)') <> 'test' THEN
    RAISE EXCEPTION '9G GATE (%): ambiente distinto de test — abortado', 'C.1-R2';
  END IF;
END
$gate$;

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

-- ██████████████████████ C.1-R3 · saldo_socios_periodo ██████████████████████
-- Vista por socio del mismo período: saldo_bruto (paso 9), gastos_d/gastos_e
-- (negativos), saldo_final = bruto + d + e, y desembolsado_periodo
-- (informativo D-9G-09: lo que el socio pagó de su bolsillo en el período;
-- NO es deuda ni neteo). Universo D-9G-08: matriz ∪ incidencias D/E.
-- Guard pct: fila con socio='PARAMETRO_INVALIDO_PCT_OPERATIVO' y montos NULL.

-- GATE programático de ambiente (v2): primer statement del run; si el
-- proyecto no es TEST, RAISE EXCEPTION y el resto de la selección no se aplica.
DO $gate$
BEGIN
  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
              '(ausente)') <> 'test' THEN
    RAISE EXCEPTION '9G GATE (%): ambiente distinto de test — abortado', 'C.1-R3';
  END IF;
END
$gate$;

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

-- ████████████████████████████ C.1-R4 · REVOKE ██████████████████████████████

-- GATE programático de ambiente (v2): primer statement del run; si el
-- proyecto no es TEST, RAISE EXCEPTION y el resto de la selección no se aplica.
DO $gate$
BEGIN
  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
              '(ausente)') <> 'test' THEN
    RAISE EXCEPTION '9G GATE (%): ambiente distinto de test — abortado', 'C.1-R4';
  END IF;
END
$gate$;

REVOKE ALL ON FUNCTION public.cascada_periodo(DATE, NUMERIC)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.saldo_socios_periodo(DATE, NUMERIC)
  FROM PUBLIC, anon, authenticated, service_role;


-- ████████████████████████████ C.2-R1 · DROP ████████████████████████████████

-- GATE programático de ambiente (v2): primer statement del run; si el
-- proyecto no es TEST, RAISE EXCEPTION y el resto de la selección no se aplica.
DO $gate$
BEGIN
  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
              '(ausente)') <> 'test' THEN
    RAISE EXCEPTION '9G GATE (%): ambiente distinto de test — abortado', 'C.2-R1';
  END IF;
END
$gate$;

DROP FUNCTION IF EXISTS public.incidencia_gasto(BIGINT);
DROP FUNCTION IF EXISTS public.reporte_overrides_periodo(DATE);
DROP FUNCTION IF EXISTS public.reporte_5_vs_fiscal_periodo(DATE);
DROP FUNCTION IF EXISTS public.gastos_sin_incidencia_periodo(DATE);

-- ████████████████████████ C.2-R2 · incidencia_gasto ████████████████████████
-- Incidencia ESTRUCTURAL de un gasto puntual. Firma SIN pct (ajuste aprobado):
--  A: 1 fila destino='pool_pre_operativo', monto completo — la absorción
--     efectiva operativo/beneficiarios depende del período entero
--     (GREATEST paso 4); verla en cascada_periodo. Pool del período vacío
--     => 0 filas (D-9G-06; aparece en gastos_sin_incidencia_periodo).
--  C: filas por socio, reparto exacto por matriz del período (equivalencia
--     §4.2; centavos vía repartir_por_matriz / D-9E-08). Pool vacío => 0 filas.
--  D: filas por socio, zona -> activas -> valor_relativo (residual D-9G-05)
--     -> seam. Zona sin activas en el período => 0 filas.
--  E: 1 fila al beneficiario de la cabaña (seam), siempre derivable.
-- Montos en magnitud positiva (cómo "cae" el gasto). Gasto inexistente => 0 filas.

-- GATE programático de ambiente (v2): primer statement del run; si el
-- proyecto no es TEST, RAISE EXCEPTION y el resto de la selección no se aplica.
DO $gate$
BEGIN
  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
              '(ausente)') <> 'test' THEN
    RAISE EXCEPTION '9G GATE (%): ambiente distinto de test — abortado', 'C.2-R2';
  END IF;
END
$gate$;

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

-- █████████████████████ C.2-R3 · reporte_overrides_periodo ██████████████████
-- Gastos del período donde el operador pisó la sugerencia (clase distinta de
-- clase_sugerida) o cargó sin sugerencia (clase_sugerida NULL). D-9F: el
-- override es legítimo; este reporte lo hace visible, no lo bloquea.

-- GATE programático de ambiente (v2): primer statement del run; si el
-- proyecto no es TEST, RAISE EXCEPTION y el resto de la selección no se aplica.
DO $gate$
BEGIN
  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
              '(ausente)') <> 'test' THEN
    RAISE EXCEPTION '9G GATE (%): ambiente distinto de test — abortado', 'C.2-R3';
  END IF;
END
$gate$;

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

-- ████████████████████ C.2-R4 · reporte_5_vs_fiscal_periodo █████████████████
-- Compara el 5% post-operativo percibido (pagos tipo extra confirmados del
-- mes) contra el costo fiscal etiquetado 'monotributo' (lower/btrim, patrón
-- D-9F-09) del mismo período. Siempre 1 fila (ceros si no hay datos).

-- GATE programático de ambiente (v2): primer statement del run; si el
-- proyecto no es TEST, RAISE EXCEPTION y el resto de la selección no se aplica.
DO $gate$
BEGIN
  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
              '(ausente)') <> 'test' THEN
    RAISE EXCEPTION '9G GATE (%): ambiente distinto de test — abortado', 'C.2-R4';
  END IF;
END
$gate$;

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

-- ███████████████████ C.2-R5 · gastos_sin_incidencia_periodo ████████████████
-- Gastos del período SIN incidencia derivable (D-9G-06): la cascada NO los
-- resta y este reporte los expone. A/C con pool vacío => 'pool_vacio';
-- D con zona sin cabañas activas en el período => 'zona_sin_activas'.
-- E nunca aparece (siempre derivable por seam).

-- GATE programático de ambiente (v2): primer statement del run; si el
-- proyecto no es TEST, RAISE EXCEPTION y el resto de la selección no se aplica.
DO $gate$
BEGIN
  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
              '(ausente)') <> 'test' THEN
    RAISE EXCEPTION '9G GATE (%): ambiente distinto de test — abortado', 'C.2-R5';
  END IF;
END
$gate$;

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

-- ████████████████████████████ C.2-R6 · REVOKE ██████████████████████████████

-- GATE programático de ambiente (v2): primer statement del run; si el
-- proyecto no es TEST, RAISE EXCEPTION y el resto de la selección no se aplica.
DO $gate$
BEGIN
  IF COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
              '(ausente)') <> 'test' THEN
    RAISE EXCEPTION '9G GATE (%): ambiente distinto de test — abortado', 'C.2-R6';
  END IF;
END
$gate$;

REVOKE ALL ON FUNCTION public.incidencia_gasto(BIGINT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.reporte_overrides_periodo(DATE)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.reporte_5_vs_fiscal_periodo(DATE)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.gastos_sin_incidencia_periodo(DATE)
  FROM PUBLIC, anon, authenticated, service_role;
