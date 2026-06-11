-- ============================================================================
-- VITA DELTA · ETAPA 9G · BLOQUE D — VALIDACIÓN NUMÉRICA READ-ONLY
-- ----------------------------------------------------------------------------
-- Entorno objetivo : TEST. 100% read-only (solo SELECT y llamadas a funciones
--                    STABLE). Correr completo como una única selección.
-- Propósito        : reproducir en TEST la batería validada en el harness:
--   · Julio @0.25  = ejemplo canónico de diseño (11 pasos al centavo)
--   · Agosto @0.25 = mes sin ingreso + incidencia E de cabaña desactivada
--   · Nov @0.25    = empate de matriz (residual D-9E-08 a Franco) + gasto D
--   · Junio @0.25  = ANOMALÍA DE ARRANQUE real: ingreso con pool vacío
--                    (consecuencia documentada de D-9G-03)
--   · Extremos pct=0 y pct=1 (D-9G-07: signo sin clamps bajo el paso 4)
--   · Guards de parámetro inválido (D-9G-01)
--   · saldo_socios_periodo + coherencia cruzada paso 11 = saldo_final
--   · incidencia_gasto sobre el fixture 9F completo (ids 30-34)
--   · Los 3 reportes
--   · No-regresión (seed intacto, reales intactos, md5, EXCLUDE)
-- Veredicto        : fila 99.99; VERDE si FALLO=0.
-- ============================================================================

WITH
jul   AS (SELECT * FROM cascada_periodo(DATE '2026-07-01', 0.25)),
jul15 AS (SELECT * FROM cascada_periodo(DATE '2026-07-15', 0.25)),
ago   AS (SELECT * FROM cascada_periodo(DATE '2026-08-01', 0.25)),
nov   AS (SELECT * FROM cascada_periodo(DATE '2026-11-01', 0.25)),
jun   AS (SELECT * FROM cascada_periodo(DATE '2026-06-01', 0.25)),
jul0  AS (SELECT * FROM cascada_periodo(DATE '2026-07-01', 0.0)),
jul1  AS (SELECT * FROM cascada_periodo(DATE '2026-07-01', 1.0)),
sjul  AS (SELECT * FROM saldo_socios_periodo(DATE '2026-07-01', 0.25)),
sago  AS (SELECT * FROM saldo_socios_periodo(DATE '2026-08-01', 0.25)),
checks AS (

-- ===========================================================================
-- SECCIÓN 1 — PRESENCIA Y PERMISOS
-- ===========================================================================
SELECT 1.01::numeric AS orden, 'PRESENCIA'::text AS seccion,
       'las 6 funciones 9G con STABLE + SECURITY INVOKER'::text AS chequeo,
       '6'::text AS esperado,
       (SELECT COUNT(*)::text FROM pg_proc
         WHERE pronamespace = 'public'::regnamespace
           AND proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                           'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                           'gastos_sin_incidencia_periodo')
           AND provolatile::text = 's' AND NOT prosecdef) AS obtenido,
       CASE WHEN (SELECT COUNT(*) FROM pg_proc
                   WHERE pronamespace = 'public'::regnamespace
                     AND proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                                     'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                                     'gastos_sin_incidencia_periodo')
                     AND provolatile::text = 's' AND NOT prosecdef) = 6
            THEN 'OK' ELSE 'FALLO' END AS estado

UNION ALL
SELECT 1.02, 'PRESENCIA', 'REVOKE efectivo: anon/authenticated/service_role sin EXECUTE',
       '0',
       (SELECT COUNT(*)::text FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace
           AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                             'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                             'gastos_sin_incidencia_periodo')
           AND (has_function_privilege('anon', p.oid, 'EXECUTE')
             OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
             OR has_function_privilege('service_role', p.oid, 'EXECUTE'))),
       CASE WHEN (SELECT COUNT(*) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace
           AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                             'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                             'gastos_sin_incidencia_periodo')
           AND (has_function_privilege('anon', p.oid, 'EXECUTE')
             OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
             OR has_function_privilege('service_role', p.oid, 'EXECUTE'))) = 0
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 2 — JULIO @0.25 (ejemplo canónico del diseño)
-- ===========================================================================
UNION ALL
SELECT 2.01, 'JULIO', 'pasos 1-8 (agregados, en orden)',
       '670200.00 | -40000.00 | 630200.00 | -157550.00 | 472650.00 | 8500.00 | -25000.00 | 456150.00',
       (SELECT string_agg(monto::numeric(14,2)::text, ' | ' ORDER BY paso)
          FROM jul WHERE id_socio IS NULL),
       CASE WHEN (SELECT string_agg(monto::numeric(14,2)::text, ' | ' ORDER BY paso)
          FROM jul WHERE id_socio IS NULL)
          = '670200.00 | -40000.00 | 630200.00 | -157550.00 | 472650.00 | 8500.00 | -25000.00 | 456150.00'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.02, 'JULIO', 'paso 9: reparto por matriz (residual a Remo, mayor participación)',
       'Franco=120674.60 | Remo=214800.80 | Rodrigo=120674.60',
       (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM jul WHERE paso = 9),
       CASE WHEN (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM jul WHERE paso = 9)
          = 'Franco=120674.60 | Remo=214800.80 | Rodrigo=120674.60'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.03, 'JULIO', 'paso 10: incidencias D+E (solo Remo: E horas Tokio)',
       'Remo=-60000.00',
       (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM jul WHERE paso = 10),
       CASE WHEN (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM jul WHERE paso = 10) = 'Remo=-60000.00'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.04, 'JULIO', 'paso 11: saldo final por socio',
       'Franco=120674.60 | Remo=154800.80 | Rodrigo=120674.60',
       (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM jul WHERE paso = 11),
       CASE WHEN (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM jul WHERE paso = 11)
          = 'Franco=120674.60 | Remo=154800.80 | Rodrigo=120674.60'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.05, 'JULIO', 'conservación: suma paso 9 = paso 8',
       'iguales',
       (SELECT (SELECT SUM(monto) FROM jul WHERE paso = 9)::numeric(14,2)::text || ' vs ' ||
               (SELECT monto FROM jul WHERE paso = 8)::numeric(14,2)::text),
       CASE WHEN (SELECT SUM(monto) FROM jul WHERE paso = 9)
              = (SELECT monto FROM jul WHERE paso = 8)
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.06, 'JULIO', 'normalización: cascada(día 15) idéntica a cascada(día 1)',
       '0 diferencias',
       (SELECT COUNT(*)::text FROM
          ((SELECT * FROM jul15 EXCEPT SELECT * FROM jul)
           UNION ALL
           (SELECT * FROM jul EXCEPT SELECT * FROM jul15)) x),
       CASE WHEN (SELECT COUNT(*) FROM
          ((SELECT * FROM jul15 EXCEPT SELECT * FROM jul)
           UNION ALL
           (SELECT * FROM jul EXCEPT SELECT * FROM jul15)) x) = 0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.07, 'JULIO', 'total de filas (8 agregadas + 3 + 1 + 3 por socio)',
       '15',
       (SELECT COUNT(*)::text FROM jul),
       CASE WHEN (SELECT COUNT(*) FROM jul) = 15 THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 3 — AGOSTO @0.25 (sin ingreso; E de cabaña desactivada incide)
-- ===========================================================================
UNION ALL
SELECT 3.01, 'AGOSTO', 'pasos 1-8 todos en 0',
       '8 pasos, suma abs = 0',
       (SELECT COUNT(*)::text || ' pasos, suma abs = ' ||
               COALESCE(SUM(ABS(monto)),0)::numeric(14,2)::text
          FROM ago WHERE id_socio IS NULL),
       CASE WHEN (SELECT COUNT(*) FROM ago WHERE id_socio IS NULL) = 8
             AND (SELECT COALESCE(SUM(ABS(monto)),0) FROM ago WHERE id_socio IS NULL) = 0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.02, 'AGOSTO', 'paso 9: 3 filas en 0.00 (pool 378 sigue vigente)',
       '3 filas, suma 0.00',
       (SELECT COUNT(*)::text || ' filas, suma ' || COALESCE(SUM(monto),0)::numeric(14,2)::text
          FROM ago WHERE paso = 9),
       CASE WHEN (SELECT COUNT(*) FROM ago WHERE paso = 9) = 3
             AND (SELECT COALESCE(SUM(monto),0) FROM ago WHERE paso = 9) = 0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.03, 'AGOSTO', 'paso 11: Guatemala desactivada incide igual (E al seam)',
       'Franco=-180000.00 | Remo=0.00 | Rodrigo=0.00',
       (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM ago WHERE paso = 11),
       CASE WHEN (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM ago WHERE paso = 11)
          = 'Franco=-180000.00 | Remo=0.00 | Rodrigo=0.00'
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 4 — NOVIEMBRE @0.25 (empate de matriz + gasto D de zona)
-- ===========================================================================
UNION ALL
SELECT 4.01, 'NOVIEMBRE', 'pasos 1-8 (agregados, en orden)',
       '251000.00 | 0.00 | 251000.00 | -62750.00 | 188250.00 | 0.00 | 0.00 | 188250.00',
       (SELECT string_agg(monto::numeric(14,2)::text, ' | ' ORDER BY paso)
          FROM nov WHERE id_socio IS NULL),
       CASE WHEN (SELECT string_agg(monto::numeric(14,2)::text, ' | ' ORDER BY paso)
          FROM nov WHERE id_socio IS NULL)
          = '251000.00 | 0.00 | 251000.00 | -62750.00 | 188250.00 | 0.00 | 0.00 | 188250.00'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 4.02, 'NOVIEMBRE', 'paso 9: empate Franco=Remo => residual 0.01 a Franco (menor id, D-9E-08, NO Rodrigo)',
       'Franco=73483.56 | Remo=73483.55 | Rodrigo=41282.89',
       (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM nov WHERE paso = 9),
       CASE WHEN (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM nov WHERE paso = 9)
          = 'Franco=73483.56 | Remo=73483.55 | Rodrigo=41282.89'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 4.03, 'NOVIEMBRE', 'paso 10: D jardin chicas repartido entre activas (Guatemala+Tokio)',
       'Franco=-15000.00 | Remo=-15000.00',
       (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM nov WHERE paso = 10),
       CASE WHEN (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM nov WHERE paso = 10) = 'Franco=-15000.00 | Remo=-15000.00'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 4.04, 'NOVIEMBRE', 'paso 11: saldo final por socio',
       'Franco=58483.56 | Remo=58483.55 | Rodrigo=41282.89',
       (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM nov WHERE paso = 11),
       CASE WHEN (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM nov WHERE paso = 11)
          = 'Franco=58483.56 | Remo=58483.55 | Rodrigo=41282.89'
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 5 — JUNIO @0.25 (anomalía de arranque real: D-9G-03)
-- ===========================================================================
UNION ALL
SELECT 5.01, 'JUNIO', 'pasos 1-8: ingreso real con pool vacío (no se reparte)',
       '1345000.00 | 0.00 | 1345000.00 | -336250.00 | 1008750.00 | 15150.00 | 0.00 | 1023900.00',
       (SELECT string_agg(monto::numeric(14,2)::text, ' | ' ORDER BY paso)
          FROM jun WHERE id_socio IS NULL),
       CASE WHEN (SELECT string_agg(monto::numeric(14,2)::text, ' | ' ORDER BY paso)
          FROM jun WHERE id_socio IS NULL)
          = '1345000.00 | 0.00 | 1345000.00 | -336250.00 | 1008750.00 | 15150.00 | 0.00 | 1023900.00'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 5.02, 'JUNIO', 'pasos 9-11 sin filas (total filas del período = 8)',
       '8',
       (SELECT COUNT(*)::text FROM jun),
       CASE WHEN (SELECT COUNT(*) FROM jun) = 8 THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 6 — EXTREMOS DE PCT (D-9G-07) Y GUARDS (D-9G-01)
-- ===========================================================================
UNION ALL
SELECT 6.01, 'EXTREMOS', 'pct=0: operativo cobra 0; paso 8 = 613700',
       'paso4=0.00 · paso8=613700.00',
       (SELECT 'paso4=' || (SELECT monto FROM jul0 WHERE paso = 4)::numeric(14,2)::text ||
               ' · paso8=' || (SELECT monto FROM jul0 WHERE paso = 8)::numeric(14,2)::text),
       CASE WHEN (SELECT monto FROM jul0 WHERE paso = 4) = 0
             AND (SELECT monto FROM jul0 WHERE paso = 8) = 613700.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 6.02, 'EXTREMOS', 'pct=1: base de ganancia NEGATIVA repartida con signo (sin clamps bajo paso 4)',
       'paso8=-16500.00 · Franco=-4365.08 | Remo=-7769.84 | Rodrigo=-4365.08',
       (SELECT 'paso8=' || (SELECT monto FROM jul1 WHERE paso = 8)::numeric(14,2)::text || ' · ' ||
               (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
                  FROM jul1 WHERE paso = 9)),
       CASE WHEN (SELECT monto FROM jul1 WHERE paso = 8) = -16500.00
             AND (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
                    FROM jul1 WHERE paso = 9)
                 = 'Franco=-4365.08 | Remo=-7769.84 | Rodrigo=-4365.08'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 6.03, 'EXTREMOS', 'pct=1: paso 11 Remo arrastra además la E (saldo muy negativo visible)',
       'Remo=-67769.84',
       (SELECT 'Remo=' || (SELECT monto FROM jul1 WHERE paso = 11 AND socio = 'Remo')
               ::numeric(14,2)::text),
       CASE WHEN (SELECT monto FROM jul1 WHERE paso = 11 AND socio = 'Remo') = -67769.84
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 6.04, 'GUARDS', 'cascada(jul, 1.5): UNA fila paso=0 con el valor recibido',
       '1 fila · paso 0 · monto 1.5',
       (SELECT COUNT(*)::text || ' fila · paso ' || MIN(paso)::text || ' · monto ' ||
               MIN(monto)::text
          FROM cascada_periodo(DATE '2026-07-01', 1.5)
         WHERE concepto = 'PARAMETRO_INVALIDO_PCT_OPERATIVO'),
       CASE WHEN (SELECT COUNT(*) FROM cascada_periodo(DATE '2026-07-01', 1.5)) = 1
             AND (SELECT MIN(monto) FROM cascada_periodo(DATE '2026-07-01', 1.5)
                   WHERE paso = 0) = 1.5
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 6.05, 'GUARDS', 'cascada(jul, NULL): UNA fila paso=0 con monto NULL',
       '1 fila · monto NULL',
       (SELECT COUNT(*)::text || ' fila · monto ' ||
               COALESCE(MIN(monto)::text, 'NULL')
          FROM cascada_periodo(DATE '2026-07-01', NULL) WHERE paso = 0),
       CASE WHEN (SELECT COUNT(*) FROM cascada_periodo(DATE '2026-07-01', NULL)) = 1
             AND (SELECT MIN(monto) FROM cascada_periodo(DATE '2026-07-01', NULL)
                   WHERE paso = 0) IS NULL
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 6.06, 'GUARDS', 'saldo_socios(jul, -0.1): UNA fila marcada, montos NULL',
       '1 fila marcada',
       (SELECT COUNT(*)::text || ' fila' ||
               CASE WHEN MIN(socio) = 'PARAMETRO_INVALIDO_PCT_OPERATIVO'
                    THEN ' marcada' ELSE ' SIN marcar' END
          FROM saldo_socios_periodo(DATE '2026-07-01', -0.1)),
       CASE WHEN (SELECT COUNT(*) FROM saldo_socios_periodo(DATE '2026-07-01', -0.1)) = 1
             AND (SELECT MIN(socio) FROM saldo_socios_periodo(DATE '2026-07-01', -0.1))
                 = 'PARAMETRO_INVALIDO_PCT_OPERATIVO'
             AND (SELECT MIN(saldo_final) FROM saldo_socios_periodo(DATE '2026-07-01', -0.1))
                 IS NULL
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 7 — SALDO_SOCIOS_PERIODO Y COHERENCIA CRUZADA
-- ===========================================================================
UNION ALL
SELECT 7.01, 'SALDOS', 'julio: tabla completa por socio (bruto/d/e/final/desembolsado D-9G-09)',
       'Franco: 120674.60/0.00/0.00/120674.60/25000.00 || Remo: 214800.80/0.00/-60000.00/154800.80/0.00 || Rodrigo: 120674.60/0.00/0.00/120674.60/60000.00',
       (SELECT string_agg(socio || ': ' || saldo_bruto::numeric(14,2)::text
                || '/' || gastos_d::numeric(14,2)::text
                || '/' || gastos_e::numeric(14,2)::text
                || '/' || saldo_final::numeric(14,2)::text
                || '/' || desembolsado_periodo::numeric(14,2)::text, ' || ' ORDER BY socio)
          FROM sjul),
       CASE WHEN (SELECT string_agg(socio || ': ' || saldo_bruto::numeric(14,2)::text
                || '/' || gastos_d::numeric(14,2)::text
                || '/' || gastos_e::numeric(14,2)::text
                || '/' || saldo_final::numeric(14,2)::text
                || '/' || desembolsado_periodo::numeric(14,2)::text, ' || ' ORDER BY socio)
          FROM sjul)
          = 'Franco: 120674.60/0.00/0.00/120674.60/25000.00 || Remo: 214800.80/0.00/-60000.00/154800.80/0.00 || Rodrigo: 120674.60/0.00/0.00/120674.60/60000.00'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 7.02, 'SALDOS', 'agosto: Franco absorbe E; Rodrigo desembolsó el termotanque (informativo)',
       'Franco final=-180000.00 · Rodrigo desemb=180000.00',
       (SELECT 'Franco final=' ||
               (SELECT saldo_final FROM sago WHERE socio = 'Franco')::numeric(14,2)::text ||
               ' · Rodrigo desemb=' ||
               (SELECT desembolsado_periodo FROM sago WHERE socio = 'Rodrigo')::numeric(14,2)::text),
       CASE WHEN (SELECT saldo_final FROM sago WHERE socio = 'Franco') = -180000.00
             AND (SELECT desembolsado_periodo FROM sago WHERE socio = 'Rodrigo') = 180000.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 7.03, 'SALDOS', 'junio: 0 filas (pool vacío y sin incidencias: caso legítimo)',
       '0',
       (SELECT COUNT(*)::text FROM saldo_socios_periodo(DATE '2026-06-01', 0.25)),
       CASE WHEN (SELECT COUNT(*) FROM saldo_socios_periodo(DATE '2026-06-01', 0.25)) = 0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 7.04, 'SALDOS', 'coherencia cruzada: paso 11 = saldo_final en jul/ago/nov',
       '0 discrepancias',
       (SELECT COUNT(*)::text FROM (
          SELECT 1 AS x
          FROM (VALUES (DATE '2026-07-01'), (DATE '2026-08-01'), (DATE '2026-11-01')) m(mes)
          CROSS JOIN LATERAL cascada_periodo(m.mes, 0.25) c
          JOIN LATERAL saldo_socios_periodo(m.mes, 0.25) s ON s.id_socio = c.id_socio
          WHERE c.paso = 11 AND c.monto <> s.saldo_final) d),
       CASE WHEN (SELECT COUNT(*) FROM (
          SELECT 1 AS x
          FROM (VALUES (DATE '2026-07-01'), (DATE '2026-08-01'), (DATE '2026-11-01')) m(mes)
          CROSS JOIN LATERAL cascada_periodo(m.mes, 0.25) c
          JOIN LATERAL saldo_socios_periodo(m.mes, 0.25) s ON s.id_socio = c.id_socio
          WHERE c.paso = 11 AND c.monto <> s.saldo_final) d) = 0
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 8 — INCIDENCIA_GASTO SOBRE EL FIXTURE 9F (ids 30-34)
-- ===========================================================================
UNION ALL
SELECT 8.01, 'INCIDENCIA', 'id 30 (A insumos jul): 1 fila estructural al pool, sin pct',
       'pool_pre_operativo $40000.00',
       (SELECT string_agg(destino || ' $' || monto::numeric(14,2)::text, ' | ')
          FROM incidencia_gasto(30)),
       CASE WHEN (SELECT COUNT(*) FROM incidencia_gasto(30)) = 1
             AND (SELECT MIN(destino) FROM incidencia_gasto(30)) = 'pool_pre_operativo'
             AND (SELECT MIN(monto) FROM incidencia_gasto(30)) = 40000.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 8.02, 'INCIDENCIA', 'id 31 (C monotributo jul): exacto por matriz, residual NEGATIVO a Remo',
       'Franco=6613.76 | Remo=11772.48 | Rodrigo=6613.76 (suma 25000.00)',
       (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
               || ' (suma ' || SUM(monto)::numeric(14,2)::text || ')'
          FROM incidencia_gasto(31)),
       CASE WHEN (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
                    FROM incidencia_gasto(31))
                 = 'Franco=6613.76 | Remo=11772.48 | Rodrigo=6613.76'
             AND (SELECT SUM(monto) FROM incidencia_gasto(31)) = 25000.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 8.03, 'INCIDENCIA', 'id 32 (D jardin nov, zona chicas): activas Guatemala+Tokio por valor_relativo',
       'Franco=15000.00 | Remo=15000.00',
       (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM incidencia_gasto(32)),
       CASE WHEN (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ' ORDER BY socio)
          FROM incidencia_gasto(32)) = 'Franco=15000.00 | Remo=15000.00'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 8.04, 'INCIDENCIA', 'id 33 (E termotanque ago, Guatemala) e id 34 (E horas jul, Tokio)',
       '33: Franco=180000.00 · 34: Remo=60000.00',
       (SELECT '33: ' || (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ')
                            FROM incidencia_gasto(33)) ||
               ' · 34: ' || (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ')
                            FROM incidencia_gasto(34))),
       CASE WHEN (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ')
                    FROM incidencia_gasto(33)) = 'Franco=180000.00'
             AND (SELECT string_agg(socio || '=' || monto::numeric(14,2)::text, ' | ')
                    FROM incidencia_gasto(34)) = 'Remo=60000.00'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 8.05, 'INCIDENCIA', 'id 9999 (inexistente): 0 filas',
       '0',
       (SELECT COUNT(*)::text FROM incidencia_gasto(9999)),
       CASE WHEN (SELECT COUNT(*) FROM incidencia_gasto(9999)) = 0
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 9 — LOS 3 REPORTES
-- ===========================================================================
UNION ALL
SELECT 9.01, 'REPORTES', 'overrides: jul={34 sin sugerencia} · nov={32 D pisa C} · ago={}',
       'jul=34 · nov=32 · ago=(ninguno)',
       (SELECT 'jul=' || COALESCE((SELECT string_agg(id_gasto::text, ',' ORDER BY id_gasto)
                                     FROM reporte_overrides_periodo(DATE '2026-07-01')), '(ninguno)') ||
               ' · nov=' || COALESCE((SELECT string_agg(id_gasto::text, ',' ORDER BY id_gasto)
                                     FROM reporte_overrides_periodo(DATE '2026-11-01')), '(ninguno)') ||
               ' · ago=' || COALESCE((SELECT string_agg(id_gasto::text, ',' ORDER BY id_gasto)
                                     FROM reporte_overrides_periodo(DATE '2026-08-01')), '(ninguno)')),
       CASE WHEN (SELECT string_agg(id_gasto::text, ',')
                    FROM reporte_overrides_periodo(DATE '2026-07-01')) = '34'
             AND (SELECT string_agg(id_gasto::text, ',')
                    FROM reporte_overrides_periodo(DATE '2026-11-01')) = '32'
             AND NOT EXISTS (SELECT 1 FROM reporte_overrides_periodo(DATE '2026-08-01'))
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 9.02, 'REPORTES', '5 vs fiscal julio: extra 8500 vs monotributo 25000',
       '8500.00 / 25000.00 / -16500.00',
       (SELECT total_extra_confirmado::numeric(14,2)::text || ' / ' ||
               total_fiscal_monotributo::numeric(14,2)::text || ' / ' ||
               diferencia::numeric(14,2)::text
          FROM reporte_5_vs_fiscal_periodo(DATE '2026-07-01')),
       CASE WHEN (SELECT total_extra_confirmado FROM reporte_5_vs_fiscal_periodo(DATE '2026-07-01')) = 8500.00
             AND (SELECT total_fiscal_monotributo FROM reporte_5_vs_fiscal_periodo(DATE '2026-07-01')) = 25000.00
             AND (SELECT diferencia FROM reporte_5_vs_fiscal_periodo(DATE '2026-07-01')) = -16500.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 9.03, 'REPORTES', '5 vs fiscal septiembre: 1 fila en ceros (mes sin datos)',
       '0.00 / 0.00 / 0.00',
       (SELECT total_extra_confirmado::numeric(14,2)::text || ' / ' ||
               total_fiscal_monotributo::numeric(14,2)::text || ' / ' ||
               diferencia::numeric(14,2)::text
          FROM reporte_5_vs_fiscal_periodo(DATE '2026-09-01')),
       CASE WHEN (SELECT COUNT(*) FROM reporte_5_vs_fiscal_periodo(DATE '2026-09-01')) = 1
             AND (SELECT diferencia FROM reporte_5_vs_fiscal_periodo(DATE '2026-09-01')) = 0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 9.04, 'REPORTES', 'sin_incidencia jul/ago/nov: 0 filas (todo derivable con datos actuales)',
       '0 / 0 / 0',
       (SELECT (SELECT COUNT(*) FROM gastos_sin_incidencia_periodo(DATE '2026-07-01'))::text || ' / ' ||
               (SELECT COUNT(*) FROM gastos_sin_incidencia_periodo(DATE '2026-08-01'))::text || ' / ' ||
               (SELECT COUNT(*) FROM gastos_sin_incidencia_periodo(DATE '2026-11-01'))::text),
       CASE WHEN (SELECT COUNT(*) FROM gastos_sin_incidencia_periodo(DATE '2026-07-01')) = 0
             AND (SELECT COUNT(*) FROM gastos_sin_incidencia_periodo(DATE '2026-08-01')) = 0
             AND (SELECT COUNT(*) FROM gastos_sin_incidencia_periodo(DATE '2026-11-01')) = 0
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 10 — NO-REGRESIÓN
-- ===========================================================================
UNION ALL
SELECT 10.01, 'NO-REGRESION', 'seed 9G intacto: 5 marcadas; reales 26 con $1.875.000',
       '5 · 26 · 1875000.00',
       (SELECT (SELECT COUNT(*) FROM pagos
                 WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\')::text || ' · ' ||
               (SELECT COUNT(*) FROM pagos
                 WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\')::text || ' · ' ||
               (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                        AND estado::text = 'confirmado'),0) FROM pagos
                 WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\')::numeric(14,2)::text),
       CASE WHEN (SELECT COUNT(*) FROM pagos
                   WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\') = 5
             AND (SELECT COUNT(*) FROM pagos
                   WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\') = 26
             AND (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                      AND estado::text = 'confirmado'),0) FROM pagos
                   WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\') = 1875000.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 10.02, 'NO-REGRESION', 'md5 cabanas.activa = baseline 9F/9G (las funciones no tocaron nada)',
       '90e55df2e433c09ee57c06eaa753c618',
       (SELECT md5(string_agg(id_cabana::text || ':' || activa::text, '|' ORDER BY id_cabana))
          FROM cabanas),
       CASE WHEN (SELECT md5(string_agg(id_cabana::text || ':' || activa::text, '|' ORDER BY id_cabana))
          FROM cabanas) = '90e55df2e433c09ee57c06eaa753c618'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 10.03, 'NO-REGRESION', 'EXCLUDE global = 3 · gastos_internos = 5 (fixture, 0 ajenas)',
       '3 · 5 / 0',
       (SELECT (SELECT COUNT(*) FROM pg_constraint
                 WHERE contype = 'x' AND connamespace = 'public'::regnamespace)::text || ' · ' ||
               (SELECT COUNT(*) FILTER (WHERE creado_por = 'seed_9f_validacion')::text || ' / ' ||
                       COUNT(*) FILTER (WHERE creado_por <> 'seed_9f_validacion')::text
                  FROM gastos_internos)),
       CASE WHEN (SELECT COUNT(*) FROM pg_constraint
                   WHERE contype = 'x' AND connamespace = 'public'::regnamespace) = 3
             AND (SELECT COUNT(*) FILTER (WHERE creado_por = 'seed_9f_validacion')
                    FROM gastos_internos) = 5
             AND (SELECT COUNT(*) FILTER (WHERE creado_por <> 'seed_9f_validacion')
                    FROM gastos_internos) = 0
            THEN 'OK' ELSE 'FALLO' END
)

SELECT ROUND(orden, 3) AS orden, seccion, chequeo, esperado, obtenido, estado
FROM checks
UNION ALL
SELECT 99.99, 'VEREDICTO', 'resultado global del Bloque D',
       'FALLO=0',
       'FALLO=' || v.f::text || ' · OK=' || v.k::text,
       CASE WHEN v.f = 0
            THEN 'VERDE - cascada validada; apto para Bloque E (no-regresion) y cierre'
            ELSE 'FRENAR - revisar FALLOs' END
FROM (SELECT COUNT(*) FILTER (WHERE estado = 'FALLO') AS f,
             COUNT(*) FILTER (WHERE estado = 'OK')    AS k
        FROM checks) v
ORDER BY 1;
