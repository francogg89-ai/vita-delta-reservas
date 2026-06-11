-- ============================================================================
-- VITA DELTA · ETAPA 9G · BLOQUE E — NO-REGRESIÓN CONSOLIDADA FINAL
-- ----------------------------------------------------------------------------
-- Entorno objetivo : TEST. 100% read-only. Correr completo como una selección.
-- Propósito        : evidencia de cierre — después de toda la actividad de 9G
--                    (seed B + DDL C + validación D):
--   · 9C / 9D / 9E / 9F intactos, re-pineados contra los valores del Bloque A
--   · Estado final 9G: 6 funciones presentes con props y REVOKE; seed íntegro
--   · Baselines duros: md5 cabanas.activa, EXCLUDE global, conteos
--   Único delta esperado vs Bloque A: pagos 26 -> 31 (los 5 del seed B).
-- Veredicto        : fila 99.99; VERDE habilita 9G_CIERRE.md.
-- ============================================================================

WITH checks AS (

-- ===========================================================================
-- SECCIÓN 1 — GATE
-- ===========================================================================
SELECT 1.01::numeric AS orden, 'GATE'::text AS seccion,
       'ambiente'::text AS chequeo, 'test'::text AS esperado,
       COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
                '(ausente)')::text AS obtenido,
       CASE WHEN (SELECT valor FROM configuracion_general WHERE clave = 'ambiente') = 'test'
            THEN 'OK' ELSE 'FALLO' END::text AS estado

-- ===========================================================================
-- SECCIÓN 2 — 9C INTACTO
-- ===========================================================================
UNION ALL
SELECT 2.01, '9C', 'seed: valor relativo + beneficiario por cabaña (5/5)',
       '5',
       (SELECT COUNT(*)::text
          FROM cabanas c
          JOIN socios s ON s.id_socio = c.id_socio_beneficiario
          JOIN (VALUES ('Arrebol',     100::numeric, 'Franco'::text),
                       ('Madre Selva', 100,          'Rodrigo'),
                       ('Bamboo',      100,          'Remo'),
                       ('Guatemala',    78,          'Franco'),
                       ('Tokio',        78,          'Remo')
               ) v(nom, vr, ben)
            ON v.nom = c.nombre AND c.valor_relativo = v.vr AND s.nombre = v.ben),
       CASE WHEN (SELECT COUNT(*)
          FROM cabanas c
          JOIN socios s ON s.id_socio = c.id_socio_beneficiario
          JOIN (VALUES ('Arrebol',     100::numeric, 'Franco'::text),
                       ('Madre Selva', 100,          'Rodrigo'),
                       ('Bamboo',      100,          'Remo'),
                       ('Guatemala',    78,          'Franco'),
                       ('Tokio',        78,          'Remo')
               ) v(nom, vr, ben)
            ON v.nom = c.nombre AND c.valor_relativo = v.vr AND s.nombre = v.ben) = 5
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.02, '9C', 'zonas=2, pertenencias=5; seam coherente y fecha-independiente (5 y 5)',
       '2 · 5 · 5 y 5',
       (SELECT (SELECT COUNT(*) FROM zonas WHERE nombre IN ('grandes','chicas'))::text || ' · ' ||
               (SELECT COUNT(*) FROM cabana_zona)::text || ' · ' ||
               (SELECT COUNT(*) FROM cabanas c
                 WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01')
                       = c.id_socio_beneficiario)::text || ' y ' ||
               (SELECT COUNT(*) FROM cabanas c
                 WHERE resolver_beneficiario(c.id_cabana, DATE '2031-01-01')
                       = c.id_socio_beneficiario)::text),
       CASE WHEN (SELECT COUNT(*) FROM zonas WHERE nombre IN ('grandes','chicas')) = 2
             AND (SELECT COUNT(*) FROM cabana_zona) = 5
             AND (SELECT COUNT(*) FROM cabanas c
                   WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01')
                         = c.id_socio_beneficiario) = 5
             AND (SELECT COUNT(*) FROM cabanas c
                   WHERE resolver_beneficiario(c.id_cabana, DATE '2031-01-01')
                         = c.id_socio_beneficiario) = 5
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 3 — 9D INTACTO
-- ===========================================================================
UNION ALL
SELECT 3.01, '9D', 'activaciones: 5/5 abiertas, composición D-9D-10 (5 coincidencias)',
       '5 / 5 / 5',
       (SELECT (SELECT COUNT(*) FROM activaciones_operativas)::text || ' / ' ||
               (SELECT COUNT(*) FROM activaciones_operativas
                 WHERE fecha_hasta IS NULL)::text || ' / ' ||
               (SELECT COUNT(*)
                  FROM activaciones_operativas a
                  JOIN cabanas c ON c.id_cabana = a.id_cabana
                  JOIN (VALUES ('Bamboo',      DATE '2026-07-01'),
                               ('Madre Selva', DATE '2026-07-01'),
                               ('Arrebol',     DATE '2026-07-01'),
                               ('Tokio',       DATE '2026-07-01'),
                               ('Guatemala',   DATE '2026-11-01')
                       ) v(nom, d)
                    ON v.nom = c.nombre AND a.fecha_desde = v.d
                       AND a.fecha_hasta IS NULL)::text),
       CASE WHEN (SELECT COUNT(*) FROM activaciones_operativas) = 5
             AND (SELECT COUNT(*) FROM activaciones_operativas WHERE fecha_hasta IS NULL) = 5
             AND (SELECT COUNT(*)
                  FROM activaciones_operativas a
                  JOIN cabanas c ON c.id_cabana = a.id_cabana
                  JOIN (VALUES ('Bamboo',      DATE '2026-07-01'),
                               ('Madre Selva', DATE '2026-07-01'),
                               ('Arrebol',     DATE '2026-07-01'),
                               ('Tokio',       DATE '2026-07-01'),
                               ('Guatemala',   DATE '2026-11-01')
                       ) v(nom, d)
                    ON v.nom = c.nombre AND a.fecha_desde = v.d
                       AND a.fecha_hasta IS NULL) = 5
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.02, '9D', 'pool por mes jul/oct/nov',
       '4 | 4 | 5',
       (SELECT COUNT(*)::text FROM activaciones_operativas a
         WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)')
               @> daterange(DATE '2026-07-01', DATE '2026-08-01', '[)'))
       || ' | ' ||
       (SELECT COUNT(*)::text FROM activaciones_operativas a
         WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)')
               @> daterange(DATE '2026-10-01', DATE '2026-11-01', '[)'))
       || ' | ' ||
       (SELECT COUNT(*)::text FROM activaciones_operativas a
         WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)')
               @> daterange(DATE '2026-11-01', DATE '2026-12-01', '[)')),
       CASE WHEN (SELECT COUNT(*) FROM activaciones_operativas a
                   WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)')
                         @> daterange(DATE '2026-07-01', DATE '2026-08-01', '[)')) = 4
             AND (SELECT COUNT(*) FROM activaciones_operativas a
                   WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)')
                         @> daterange(DATE '2026-10-01', DATE '2026-11-01', '[)')) = 4
             AND (SELECT COUNT(*) FROM activaciones_operativas a
                   WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)')
                         @> daterange(DATE '2026-11-01', DATE '2026-12-01', '[)')) = 5
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 4 — 9E INTACTO (presencia + ejecución)
-- ===========================================================================
UNION ALL
SELECT 4.01, '9E', 'las 3 funciones con STABLE + INVOKER; matriz jul/nov/jun; reparto exacto',
       '3 · 378/456/0 filas-jun · suma 100000.01',
       (SELECT (SELECT COUNT(*) FROM pg_proc
                 WHERE pronamespace = 'public'::regnamespace
                   AND proname IN ('matriz_participacion','repartir_por_matriz',
                                   'detalle_participacion')
                   AND provolatile::text = 's' AND NOT prosecdef)::text || ' · ' ||
               (SELECT MAX(valor_pool) FROM matriz_participacion(DATE '2026-07-01'))
                 ::numeric(6,0)::text || '/' ||
               (SELECT MAX(valor_pool) FROM matriz_participacion(DATE '2026-11-01'))
                 ::numeric(6,0)::text || '/' ||
               (SELECT COUNT(*) FROM matriz_participacion(DATE '2026-06-01'))::text
                 || ' filas-jun · suma ' ||
               (SELECT SUM(monto_asignado)
                  FROM repartir_por_matriz(DATE '2026-07-01', 100000.01))::text),
       CASE WHEN (SELECT COUNT(*) FROM pg_proc
                   WHERE pronamespace = 'public'::regnamespace
                     AND proname IN ('matriz_participacion','repartir_por_matriz',
                                     'detalle_participacion')
                     AND provolatile::text = 's' AND NOT prosecdef) = 3
             AND (SELECT MAX(valor_pool) FROM matriz_participacion(DATE '2026-07-01')) = 378
             AND (SELECT MAX(valor_pool) FROM matriz_participacion(DATE '2026-11-01')) = 456
             AND (SELECT COUNT(*) FROM matriz_participacion(DATE '2026-06-01')) = 0
             AND (SELECT SUM(monto_asignado)
                    FROM repartir_por_matriz(DATE '2026-07-01', 100000.01)) = 100000.01
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 5 — 9F INTACTO
-- ===========================================================================
UNION ALL
SELECT 5.01, '9F', 'gastos_internos: 17 col, 18 constraints, índice, fixture 5/0/30-34',
       '17 · 18 · 1 · 5/0/30-34',
       (SELECT (SELECT COUNT(*) FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'gastos_internos')::text
               || ' · ' ||
               (SELECT COUNT(*) FROM pg_constraint
                 WHERE conrelid = 'public.gastos_internos'::regclass)::text || ' · ' ||
               (SELECT COUNT(*) FROM pg_indexes
                 WHERE schemaname = 'public' AND tablename = 'gastos_internos'
                   AND indexname = 'idx_gastos_internos_periodo_clase')::text || ' · ' ||
               (SELECT COUNT(*) FILTER (WHERE creado_por = 'seed_9f_validacion')::text
                       || '/' || COUNT(*) FILTER (WHERE creado_por <> 'seed_9f_validacion')::text
                       || '/' || MIN(id_gasto)::text || '-' || MAX(id_gasto)::text
                  FROM gastos_internos)),
       CASE WHEN (SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'gastos_internos') = 17
             AND (SELECT COUNT(*) FROM pg_constraint
                   WHERE conrelid = 'public.gastos_internos'::regclass) = 18
             AND (SELECT COUNT(*) FROM pg_indexes
                   WHERE schemaname = 'public' AND tablename = 'gastos_internos'
                     AND indexname = 'idx_gastos_internos_periodo_clase') = 1
             AND (SELECT COUNT(*) FILTER (WHERE creado_por = 'seed_9f_validacion')
                    FROM gastos_internos) = 5
             AND (SELECT COUNT(*) FILTER (WHERE creado_por <> 'seed_9f_validacion')
                    FROM gastos_internos) = 0
             AND (SELECT MIN(id_gasto) FROM gastos_internos) = 30
             AND (SELECT MAX(id_gasto) FROM gastos_internos) = 34
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 5.02, '9F', 'legacy gastos: 0 filas, 10 col, secuencia virgen; secuencia internos',
       '0 · 10 · virgen · internos=34',
       (SELECT (SELECT COUNT(*) FROM gastos)::text || ' · ' ||
               (SELECT COUNT(*) FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'gastos')::text || ' · ' ||
               (SELECT CASE WHEN last_value IS NULL THEN 'virgen'
                            ELSE 'usada=' || last_value::text END
                  FROM pg_sequences
                 WHERE schemaname = 'public' AND sequencename = 'gastos_id_gasto_seq')
               || ' · internos=' ||
               (SELECT COALESCE(last_value::text,'?') FROM pg_sequences
                 WHERE schemaname = 'public'
                   AND sequencename = 'gastos_internos_id_gasto_seq')),
       CASE WHEN (SELECT COUNT(*) FROM gastos) = 0
             AND (SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'gastos') = 10
             AND (SELECT last_value IS NULL FROM pg_sequences
                   WHERE schemaname = 'public' AND sequencename = 'gastos_id_gasto_seq')
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 6 — ESTADO FINAL 9G
-- ===========================================================================
UNION ALL
SELECT 6.01, '9G', 'las 6 funciones presentes (STABLE + INVOKER) y REVOKE efectivo',
       '6 · 0 con EXECUTE de roles app',
       (SELECT (SELECT COUNT(*) FROM pg_proc
                 WHERE pronamespace = 'public'::regnamespace
                   AND proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                                   'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                                   'gastos_sin_incidencia_periodo')
                   AND provolatile::text = 's' AND NOT prosecdef)::text || ' · ' ||
               (SELECT COUNT(*) FROM pg_proc p
                 WHERE p.pronamespace = 'public'::regnamespace
                   AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                                     'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                                     'gastos_sin_incidencia_periodo')
                   AND (has_function_privilege('anon', p.oid, 'EXECUTE')
                     OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
                     OR has_function_privilege('service_role', p.oid, 'EXECUTE')))::text
               || ' con EXECUTE de roles app'),
       CASE WHEN (SELECT COUNT(*) FROM pg_proc
                   WHERE pronamespace = 'public'::regnamespace
                     AND proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                                     'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                                     'gastos_sin_incidencia_periodo')
                     AND provolatile::text = 's' AND NOT prosecdef) = 6
             AND (SELECT COUNT(*) FROM pg_proc p
                   WHERE p.pronamespace = 'public'::regnamespace
                     AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                                       'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                                       'gastos_sin_incidencia_periodo')
                     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
                       OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
                       OR has_function_privilege('service_role', p.oid, 'EXECUTE'))) = 0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 6.02, '9G', 'seed íntegro: 5 marcadas, composición exacta, evento compartido',
       '5 · 5 · 2',
       (SELECT (SELECT COUNT(*) FROM pagos
                 WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\')::text || ' · ' ||
               (SELECT COUNT(*)
                  FROM pagos p
                  JOIN (VALUES
                      ('seed_9g_p1_sena_jul',        'sena',  200000.00::numeric, '2026-07',  5::bigint),
                      ('seed_9g_p2_saldo_jul',       'saldo', 300200.00,          '2026-07',  6),
                      ('seed_9g_ev_saldo_extra_jul', 'saldo', 170000.00,          '2026-07',  7),
                      ('seed_9g_ev_saldo_extra_jul', 'extra',   8500.00,          '2026-07',  7),
                      ('seed_9g_p5_saldo_nov',       'saldo', 251000.00,          '2026-11', 10)
                       ) v(se, tipo, monto, mes, id_reserva)
                    ON  v.se = p.source_event AND v.tipo = p.tipo
                    AND v.monto = p.monto_recibido AND v.monto = p.monto_esperado
                    AND v.mes = to_char(date_trunc('month', p.created_at), 'YYYY-MM')
                    AND v.id_reserva = p.id_reserva
                 WHERE p.estado::text = 'confirmado' AND p.validado_por = 'seed_9g')::text
               || ' · ' ||
               (SELECT COUNT(*) FROM pagos
                 WHERE source_event = 'seed_9g_ev_saldo_extra_jul')::text),
       CASE WHEN (SELECT COUNT(*) FROM pagos
                   WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\') = 5
             AND (SELECT COUNT(*)
                  FROM pagos p
                  JOIN (VALUES
                      ('seed_9g_p1_sena_jul',        'sena',  200000.00::numeric, '2026-07',  5::bigint),
                      ('seed_9g_p2_saldo_jul',       'saldo', 300200.00,          '2026-07',  6),
                      ('seed_9g_ev_saldo_extra_jul', 'saldo', 170000.00,          '2026-07',  7),
                      ('seed_9g_ev_saldo_extra_jul', 'extra',   8500.00,          '2026-07',  7),
                      ('seed_9g_p5_saldo_nov',       'saldo', 251000.00,          '2026-11', 10)
                       ) v(se, tipo, monto, mes, id_reserva)
                    ON  v.se = p.source_event AND v.tipo = p.tipo
                    AND v.monto = p.monto_recibido AND v.monto = p.monto_esperado
                    AND v.mes = to_char(date_trunc('month', p.created_at), 'YYYY-MM')
                    AND v.id_reserva = p.id_reserva
                 WHERE p.estado::text = 'confirmado' AND p.validado_por = 'seed_9g') = 5
             AND (SELECT COUNT(*) FROM pagos
                   WHERE source_event = 'seed_9g_ev_saldo_extra_jul') = 2
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 6.03, '9G', 'caja percibida pineada: mayo/junio (reales) + julio/noviembre (seed) + agosto vacío',
       '530000.00/0.00 · 1345000.00/15150.00 · 670200.00/8500.00 · 251000.00/0.00 · (sin filas)',
       (SELECT string_agg(COALESCE(m.txt, '(sin filas)'), ' · ' ORDER BY m.ord)
          FROM (
            SELECT v.ord, (
              SELECT SUM(p.monto_recibido) FILTER (WHERE p.tipo IN ('sena','saldo')
                       AND p.estado::text = 'confirmado')::numeric(14,2)::text
                     || '/' ||
                     COALESCE(SUM(p.monto_recibido) FILTER (WHERE p.tipo = 'extra'
                       AND p.estado::text = 'confirmado'), 0)::numeric(14,2)::text
                FROM pagos p
               WHERE date_trunc('month', p.created_at)::date = v.mes
               HAVING COUNT(*) > 0
            ) AS txt
            FROM (VALUES (1, DATE '2026-05-01'), (2, DATE '2026-06-01'),
                         (3, DATE '2026-07-01'), (4, DATE '2026-11-01'),
                         (5, DATE '2026-08-01')) v(ord, mes)
          ) m),
       CASE WHEN (SELECT string_agg(COALESCE(m.txt, '(sin filas)'), ' · ' ORDER BY m.ord)
          FROM (
            SELECT v.ord, (
              SELECT SUM(p.monto_recibido) FILTER (WHERE p.tipo IN ('sena','saldo')
                       AND p.estado::text = 'confirmado')::numeric(14,2)::text
                     || '/' ||
                     COALESCE(SUM(p.monto_recibido) FILTER (WHERE p.tipo = 'extra'
                       AND p.estado::text = 'confirmado'), 0)::numeric(14,2)::text
                FROM pagos p
               WHERE date_trunc('month', p.created_at)::date = v.mes
               HAVING COUNT(*) > 0
            ) AS txt
            FROM (VALUES (1, DATE '2026-05-01'), (2, DATE '2026-06-01'),
                         (3, DATE '2026-07-01'), (4, DATE '2026-11-01'),
                         (5, DATE '2026-08-01')) v(ord, mes)
          ) m)
          = '530000.00/0.00 · 1345000.00/15150.00 · 670200.00/8500.00 · 251000.00/0.00 · (sin filas)'
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 7 — BASELINES DUROS (vs Bloque A)
-- ===========================================================================
UNION ALL
SELECT 7.01, 'BASELINE', 'md5 cabanas.activa idéntico al Bloque A',
       '90e55df2e433c09ee57c06eaa753c618',
       (SELECT md5(string_agg(id_cabana::text || ':' || activa::text, '|' ORDER BY id_cabana))
          FROM cabanas),
       CASE WHEN (SELECT md5(string_agg(id_cabana::text || ':' || activa::text, '|'
                                        ORDER BY id_cabana)) FROM cabanas)
                 = '90e55df2e433c09ee57c06eaa753c618'
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 7.02, 'BASELINE', 'EXCLUDE global y conteos (delta esperado SOLO en pagos: 26->31)',
       'EXCLUDE=3 · zonas=2 · cz=5 · act=5 · gi=5 · legacy=0 · pagos=31 · reservas=13',
       (SELECT 'EXCLUDE=' || (SELECT COUNT(*) FROM pg_constraint
                 WHERE contype = 'x' AND connamespace = 'public'::regnamespace)::text ||
               ' · zonas=' || (SELECT COUNT(*) FROM zonas)::text ||
               ' · cz=' || (SELECT COUNT(*) FROM cabana_zona)::text ||
               ' · act=' || (SELECT COUNT(*) FROM activaciones_operativas)::text ||
               ' · gi=' || (SELECT COUNT(*) FROM gastos_internos)::text ||
               ' · legacy=' || (SELECT COUNT(*) FROM gastos)::text ||
               ' · pagos=' || (SELECT COUNT(*) FROM pagos)::text ||
               ' · reservas=' || (SELECT COUNT(*) FROM reservas)::text),
       CASE WHEN (SELECT COUNT(*) FROM pg_constraint
                   WHERE contype = 'x' AND connamespace = 'public'::regnamespace) = 3
             AND (SELECT COUNT(*) FROM zonas) = 2
             AND (SELECT COUNT(*) FROM cabana_zona) = 5
             AND (SELECT COUNT(*) FROM activaciones_operativas) = 5
             AND (SELECT COUNT(*) FROM gastos_internos) = 5
             AND (SELECT COUNT(*) FROM gastos) = 0
             AND (SELECT COUNT(*) FROM pagos) = 31
             AND (SELECT COUNT(*) FROM reservas) = 13
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 7.03, 'BASELINE', 'secuencia de pagos (INFO para el cierre)',
       'INFO',
       (SELECT COALESCE(last_value::text, '(nunca usada)') FROM pg_sequences
         WHERE schemaname = 'public' AND sequencename = 'pagos_id_pago_seq'),
       'INFO'
)

SELECT ROUND(orden, 3) AS orden, seccion, chequeo, esperado, obtenido, estado
FROM checks
UNION ALL
SELECT 99.99, 'VEREDICTO', 'no-regresión consolidada de la etapa 9G',
       'FALLO=0',
       'FALLO=' || v.f::text || ' · OK=' || v.k::text || ' · INFO=' || v.i::text,
       CASE WHEN v.f = 0
            THEN 'VERDE - etapa 9G apta para cierre formal (9G_CIERRE.md)'
            ELSE 'FRENAR - revisar FALLOs' END
FROM (SELECT COUNT(*) FILTER (WHERE estado = 'FALLO')  AS f,
             COUNT(*) FILTER (WHERE estado = 'OK')     AS k,
             COUNT(*) FILTER (WHERE estado = 'INFO')   AS i
        FROM checks) v
ORDER BY 1;
