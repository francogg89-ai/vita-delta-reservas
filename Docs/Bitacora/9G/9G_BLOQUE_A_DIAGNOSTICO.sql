-- ============================================================================
-- VITA DELTA · ETAPA 9G · BLOQUE A — GATE + DIAGNÓSTICO READ-ONLY
-- ----------------------------------------------------------------------------
-- Entorno objetivo : TEST (vita-delta-test, cabañas 1-5). NO correr en OPS.
-- Naturaleza       : 100% read-only (solo SELECT). Sin DDL, sin writes.
-- Cómo correr      : seleccionar TODO el archivo y ejecutar como un único run.
--                    La salida es una sola tabla; leer la fila VEREDICTO (99.99).
-- Propósito        :
--   1) Gate duro de entorno e identidad (ambiente 'test', cabañas 1-5, socios).
--   2) Verificar base 9C/9D/9E/9F presente, ejecutando y sin regresión.
--   3) Snapshot autoritativo de `pagos` (estructura de datos real, vista previa
--      de caja percibida por mes = pasos 1 y 6, candidatas para el seed 9G).
--   4) Confirmar ausencia de funciones 9G y de marcador seed_9g_.
--   5) Fijar baselines (md5 cabanas.activa, conteos) para el Bloque E.
-- Estados de fila  : OK / FALLO (bloquea) / ATENCION (no bloquea) / INFO.
-- Decisiones marco : D-9G-02 (filtro pagos), D-9G-03 (caja percibida),
--                    D-9F-17 (fixture), D-9E-08 (residual), D-9D-10 (pool).
-- Lecciones aplicadas: L-9C-02 (cast ::text), L-9C-03 (conrelid),
--                    L-9B-03 (sin coma+JOIN), L-9B-04 (created_at).
-- Nota LIKE        : el marcador usa LIKE con ESCAPE porque '_' es comodín:
--                    source_event LIKE 'seed\_9g\_%' ESCAPE '\'.
-- ============================================================================

WITH
-- ---------------------------------------------------------------------------
-- Normalización de pagos (patrón 9A): cada pago atribuido a lo sumo a una
-- reserva vía COALESCE(id_reserva, reserva alcanzada por id_prereserva).
-- ---------------------------------------------------------------------------
pagos_norm AS (
  SELECT p.id_pago,
         p.tipo,
         p.estado::text                                   AS estado_pago,
         p.medio_pago,
         p.monto_recibido,
         p.created_at,
         p.source_event,
         p.id_reserva,
         p.id_prereserva,
         COALESCE(p.id_reserva, rv.id_reserva)            AS id_reserva_atribuida
  FROM pagos p
  LEFT JOIN reservas rv ON rv.id_pre_reserva = p.id_prereserva
),
cobrado_por_reserva AS (
  SELECT id_reserva_atribuida AS id_reserva,
         SUM(monto_recibido)  AS cobrado,
         COUNT(*)             AS n_pagos
  FROM pagos_norm
  WHERE tipo IN ('sena','saldo')
    AND estado_pago = 'confirmado'
    AND id_reserva_atribuida IS NOT NULL
  GROUP BY 1
),
checks AS (

-- ===========================================================================
-- SECCIÓN 1 — GATE DE ENTORNO E IDENTIDAD
-- ===========================================================================
SELECT 1.01::numeric AS orden, 'GATE'::text AS seccion,
       'marcador de ambiente (9C)'::text AS chequeo,
       'test'::text AS esperado,
       COALESCE((SELECT valor FROM configuracion_general WHERE clave = 'ambiente'),
                '(ausente)')::text AS obtenido,
       CASE WHEN (SELECT valor FROM configuracion_general WHERE clave = 'ambiente') = 'test'
            THEN 'OK' ELSE 'FALLO' END::text AS estado

UNION ALL
SELECT 1.02, 'GATE', 'cabañas: cantidad e ids (identidad TEST)',
       '5 filas, ids 1-5',
       (SELECT COUNT(*)::text || ' filas, ids ' || MIN(id_cabana)::text || '-' || MAX(id_cabana)::text
          FROM cabanas),
       CASE WHEN (SELECT COUNT(*) FROM cabanas) = 5
             AND (SELECT MIN(id_cabana) FROM cabanas) = 1
             AND (SELECT MAX(id_cabana) FROM cabanas) = 5
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 1.03, 'GATE', 'cabañas: los 5 nombres esperados',
       '5',
       (SELECT COUNT(*)::text FROM cabanas
         WHERE nombre IN ('Bamboo','Madre Selva','Arrebol','Guatemala','Tokio')),
       CASE WHEN (SELECT COUNT(*) FROM cabanas
                   WHERE nombre IN ('Bamboo','Madre Selva','Arrebol','Guatemala','Tokio')) = 5
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 1.04, 'GATE', 'socios: Franco/Rodrigo/Remo exactamente una vez c/u',
       'Franco=1, Remo=1, Rodrigo=1',
       COALESCE((SELECT string_agg(nombre || '=' || n::text, ', ' ORDER BY nombre)
                   FROM (SELECT nombre, COUNT(*) AS n
                           FROM socios
                          WHERE nombre IN ('Franco','Rodrigo','Remo')
                          GROUP BY nombre) s), '(ninguno)'),
       CASE WHEN (SELECT COUNT(*)
                    FROM (SELECT nombre FROM socios
                           WHERE nombre IN ('Franco','Rodrigo','Remo')
                           GROUP BY nombre HAVING COUNT(*) = 1) u) = 3
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 1.05, 'GATE', 'ids de socios (supuesto S1, resolución siempre por nombre)',
       'INFO',
       (SELECT string_agg(nombre || '=' || id_socio::text, ', ' ORDER BY id_socio) FROM socios),
       'INFO'

-- ===========================================================================
-- SECCIÓN 2 — BASE 9C (catálogo enriquecido, zonas, seam)
-- ===========================================================================
UNION ALL
SELECT 2.01, '9C', 'columnas valor_relativo / id_socio_beneficiario NOT NULL',
       '2',
       (SELECT COUNT(*)::text FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'cabanas'
           AND column_name IN ('valor_relativo','id_socio_beneficiario')
           AND is_nullable = 'NO'),
       CASE WHEN (SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'cabanas'
                     AND column_name IN ('valor_relativo','id_socio_beneficiario')
                     AND is_nullable = 'NO') = 2
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.02, '9C', 'seed: valor relativo + beneficiario por cabaña',
       '5 coincidencias',
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
SELECT 2.03, '9C', 'zonas (grandes, chicas) y pertenencias cabana_zona',
       'zonas=2, pertenencias=5, correctas=5',
       'zonas=' || (SELECT COUNT(*)::text FROM zonas WHERE nombre IN ('grandes','chicas'))
       || ', pertenencias=' || (SELECT COUNT(*)::text FROM cabana_zona)
       || ', correctas=' ||
       (SELECT COUNT(*)::text
          FROM cabana_zona cz
          JOIN cabanas c ON c.id_cabana = cz.id_cabana
          JOIN zonas   z ON z.id_zona   = cz.id_zona
          JOIN (VALUES ('Arrebol','grandes'),('Madre Selva','grandes'),('Bamboo','grandes'),
                       ('Guatemala','chicas'),('Tokio','chicas')
               ) v(nom, zon) ON v.nom = c.nombre AND v.zon = z.nombre),
       CASE WHEN (SELECT COUNT(*) FROM zonas WHERE nombre IN ('grandes','chicas')) = 2
             AND (SELECT COUNT(*) FROM cabana_zona) = 5
             AND (SELECT COUNT(*)
                    FROM cabana_zona cz
                    JOIN cabanas c ON c.id_cabana = cz.id_cabana
                    JOIN zonas   z ON z.id_zona   = cz.id_zona
                    JOIN (VALUES ('Arrebol','grandes'),('Madre Selva','grandes'),('Bamboo','grandes'),
                                 ('Guatemala','chicas'),('Tokio','chicas')
                         ) v(nom, zon) ON v.nom = c.nombre AND v.zon = z.nombre) = 5
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.04, '9C', 'seam resolver_beneficiario: presencia + STABLE + INVOKER + retorno bigint',
       '1',
       (SELECT COUNT(*)::text FROM pg_proc
         WHERE pronamespace = 'public'::regnamespace
           AND proname = 'resolver_beneficiario'
           AND provolatile::text = 's'
           AND NOT prosecdef
           AND prorettype = 'bigint'::regtype),
       CASE WHEN (SELECT COUNT(*) FROM pg_proc
                   WHERE pronamespace = 'public'::regnamespace
                     AND proname = 'resolver_beneficiario'
                     AND provolatile::text = 's'
                     AND NOT prosecdef
                     AND prorettype = 'bigint'::regtype) = 1
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.05, '9C', 'seam: coherente (=id_socio_beneficiario) y fecha-independiente',
       '5 y 5',
       (SELECT COUNT(*)::text FROM cabanas c
         WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01') = c.id_socio_beneficiario)
       || ' y ' ||
       (SELECT COUNT(*)::text FROM cabanas c
         WHERE resolver_beneficiario(c.id_cabana, DATE '2031-01-01') = c.id_socio_beneficiario),
       CASE WHEN (SELECT COUNT(*) FROM cabanas c
                   WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01') = c.id_socio_beneficiario) = 5
             AND (SELECT COUNT(*) FROM cabanas c
                   WHERE resolver_beneficiario(c.id_cabana, DATE '2031-01-01') = c.id_socio_beneficiario) = 5
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 3 — 9D (activación operativa por rango)
-- ===========================================================================
UNION ALL
SELECT 3.01, '9D', 'activaciones_operativas: 5 filas, todas abiertas (fecha_hasta NULL)',
       '5 / 5 abiertas',
       (SELECT COUNT(*)::text || ' / ' ||
               COUNT(*) FILTER (WHERE fecha_hasta IS NULL)::text || ' abiertas'
          FROM activaciones_operativas),
       CASE WHEN (SELECT COUNT(*) FROM activaciones_operativas) = 5
             AND (SELECT COUNT(*) FILTER (WHERE fecha_hasta IS NULL)
                    FROM activaciones_operativas) = 5
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.02, '9D', 'composición D-9D-10 (4 desde 2026-07-01; Guatemala desde 2026-11-01)',
       '5 coincidencias',
       (SELECT COUNT(*)::text
          FROM activaciones_operativas a
          JOIN cabanas c ON c.id_cabana = a.id_cabana
          JOIN (VALUES ('Bamboo',      DATE '2026-07-01'),
                       ('Madre Selva', DATE '2026-07-01'),
                       ('Arrebol',     DATE '2026-07-01'),
                       ('Tokio',       DATE '2026-07-01'),
                       ('Guatemala',   DATE '2026-11-01')
               ) v(nom, d)
            ON v.nom = c.nombre AND a.fecha_desde = v.d AND a.fecha_hasta IS NULL),
       CASE WHEN (SELECT COUNT(*)
          FROM activaciones_operativas a
          JOIN cabanas c ON c.id_cabana = a.id_cabana
          JOIN (VALUES ('Bamboo',      DATE '2026-07-01'),
                       ('Madre Selva', DATE '2026-07-01'),
                       ('Arrebol',     DATE '2026-07-01'),
                       ('Tokio',       DATE '2026-07-01'),
                       ('Guatemala',   DATE '2026-11-01')
               ) v(nom, d)
            ON v.nom = c.nombre AND a.fecha_desde = v.d AND a.fecha_hasta IS NULL) = 5
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.03, '9D', 'EXCLUDE global en public (reservas + bloqueos + activaciones)',
       '3',
       (SELECT COUNT(*)::text FROM pg_constraint
         WHERE contype = 'x' AND connamespace = 'public'::regnamespace),
       CASE WHEN (SELECT COUNT(*) FROM pg_constraint
                   WHERE contype = 'x' AND connamespace = 'public'::regnamespace) = 3
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.04, '9D', 'pool por mes via daterange @> mes (jul / oct / nov 2026)',
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
-- SECCIÓN 4 — 9E (matriz, reparto, detalle: presencia + EJECUCIÓN)
-- ===========================================================================
UNION ALL
SELECT 4.01, '9E', 'las 3 funciones presentes con STABLE + SECURITY INVOKER',
       '3',
       (SELECT COUNT(*)::text FROM pg_proc
         WHERE pronamespace = 'public'::regnamespace
           AND proname IN ('matriz_participacion','repartir_por_matriz','detalle_participacion')
           AND provolatile::text = 's'
           AND NOT prosecdef),
       CASE WHEN (SELECT COUNT(*) FROM pg_proc
                   WHERE pronamespace = 'public'::regnamespace
                     AND proname IN ('matriz_participacion','repartir_por_matriz','detalle_participacion')
                     AND provolatile::text = 's'
                     AND NOT prosecdef) = 3
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 4.02, '9E', 'matriz julio 2026 (pasando dia 15: prueba normalización)',
       '3 filas, pool=378, suma part.=1',
       (SELECT COUNT(*)::text || ' filas, pool=' || MAX(valor_pool)::text
               || ', suma=' || ROUND(SUM(participacion), 6)::text
          FROM matriz_participacion(DATE '2026-07-15')),
       CASE WHEN (SELECT COUNT(*) FROM matriz_participacion(DATE '2026-07-15')) = 3
             AND (SELECT MAX(valor_pool) FROM matriz_participacion(DATE '2026-07-15')) = 378
             AND ABS((SELECT SUM(participacion) FROM matriz_participacion(DATE '2026-07-15')) - 1)
                 < 0.000001
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 4.03, '9E', 'matriz noviembre 2026 + empate en el máximo (Franco=Remo=178)',
       '3 filas, pool=456, empatados=2',
       (SELECT COUNT(*)::text || ' filas, pool=' || MAX(valor_pool)::text || ', empatados=' ||
               COUNT(*) FILTER (WHERE valor_socio = 178)::text
          FROM matriz_participacion(DATE '2026-11-01')),
       CASE WHEN (SELECT COUNT(*) FROM matriz_participacion(DATE '2026-11-01')) = 3
             AND (SELECT MAX(valor_pool) FROM matriz_participacion(DATE '2026-11-01')) = 456
             AND (SELECT COUNT(*) FILTER (WHERE valor_socio = 178)
                    FROM matriz_participacion(DATE '2026-11-01')) = 2
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 4.04, '9E', 'matriz junio 2026: pool vacío => 0 filas (D-9E-06)',
       '0',
       (SELECT COUNT(*)::text FROM matriz_participacion(DATE '2026-06-01')),
       CASE WHEN (SELECT COUNT(*) FROM matriz_participacion(DATE '2026-06-01')) = 0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 4.05, '9E', 'repartir_por_matriz(jul, 100000.01): suma exacta al centavo',
       '100000.01',
       (SELECT SUM(monto_asignado)::text
          FROM repartir_por_matriz(DATE '2026-07-01', 100000.01)),
       CASE WHEN (SELECT SUM(monto_asignado)
                    FROM repartir_por_matriz(DATE '2026-07-01', 100000.01)) = 100000.01
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 4.06, '9E', 'repartir_por_matriz(jul, 100000.01): detalle (residual D-9E-08)',
       'INFO',
       (SELECT string_agg(s.nombre || '=' || r.monto_asignado::text, ' | '
                          ORDER BY r.monto_asignado DESC, s.nombre)
          FROM repartir_por_matriz(DATE '2026-07-01', 100000.01) r
          JOIN socios s ON s.id_socio = r.id_socio),
       'INFO'

UNION ALL
SELECT 4.07, '9E', 'detalle_participacion julio: 4 participan, Guatemala no',
       'participan=4, fuera=Guatemala',
       (SELECT 'participan=' || COUNT(*) FILTER (WHERE participa)::text
               || ', fuera=' ||
               COALESCE(string_agg(cabana, ',') FILTER (WHERE NOT participa), '(ninguna)')
          FROM detalle_participacion(DATE '2026-07-01')),
       CASE WHEN (SELECT COUNT(*) FILTER (WHERE participa)
                    FROM detalle_participacion(DATE '2026-07-01')) = 4
             AND (SELECT COUNT(*) FILTER (WHERE NOT participa AND cabana = 'Guatemala')
                    FROM detalle_participacion(DATE '2026-07-01')) = 1
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 5 — 9F (gastos_internos + fixture + legacy intacta)
-- ===========================================================================
UNION ALL
SELECT 5.01, '9F', 'gastos_internos: 17 columnas y 18 constraints (por conrelid)',
       '17 col; c=14,f=3,p=1',
       (SELECT COUNT(*)::text FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'gastos_internos')
       || ' col; ' ||
       (SELECT string_agg(t || '=' || n::text, ',' ORDER BY t)
          FROM (SELECT contype::text AS t, COUNT(*) AS n
                  FROM pg_constraint
                 WHERE conrelid = 'public.gastos_internos'::regclass
                 GROUP BY contype) x),
       CASE WHEN (SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'gastos_internos') = 17
             AND (SELECT COUNT(*) FROM pg_constraint
                   WHERE conrelid = 'public.gastos_internos'::regclass) = 18
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 5.02, '9F', 'índice idx_gastos_internos_periodo_clase presente',
       '1',
       (SELECT COUNT(*)::text FROM pg_indexes
         WHERE schemaname = 'public' AND tablename = 'gastos_internos'
           AND indexname = 'idx_gastos_internos_periodo_clase'),
       CASE WHEN (SELECT COUNT(*) FROM pg_indexes
                   WHERE schemaname = 'public' AND tablename = 'gastos_internos'
                     AND indexname = 'idx_gastos_internos_periodo_clase') = 1
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 5.03, '9F', 'fixture: 5 marcadas seed_9f_validacion, 0 ajenas, ids 30-34',
       '5 / 0 / 30-34',
       (SELECT COUNT(*) FILTER (WHERE creado_por = 'seed_9f_validacion')::text
               || ' / ' ||
               COUNT(*) FILTER (WHERE creado_por <> 'seed_9f_validacion')::text
               || ' / ' ||
               COALESCE(MIN(id_gasto) FILTER (WHERE creado_por = 'seed_9f_validacion')::text,'-')
               || '-' ||
               COALESCE(MAX(id_gasto) FILTER (WHERE creado_por = 'seed_9f_validacion')::text,'-')
          FROM gastos_internos),
       CASE WHEN (SELECT COUNT(*) FILTER (WHERE creado_por = 'seed_9f_validacion')
                    FROM gastos_internos) = 5
             AND (SELECT COUNT(*) FILTER (WHERE creado_por <> 'seed_9f_validacion')
                    FROM gastos_internos) = 0
             AND (SELECT MIN(id_gasto) FROM gastos_internos
                   WHERE creado_por = 'seed_9f_validacion') = 30
             AND (SELECT MAX(id_gasto) FROM gastos_internos
                   WHERE creado_por = 'seed_9f_validacion') = 34
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 5.04, '9F', 'fixture: composición exacta (clase/etiqueta/periodo/monto/pagador/alcance)',
       '5 coincidencias',
       (SELECT COUNT(*)::text
          FROM gastos_internos g
          LEFT JOIN socios  sp ON sp.id_socio  = g.id_socio_pagador
          LEFT JOIN zonas   z  ON z.id_zona    = g.id_zona
          LEFT JOIN cabanas cb ON cb.id_cabana = g.id_cabana
          JOIN (VALUES
              ('A','insumos de limpieza', DATE '2026-07-01',  40000.00::numeric,'caja',  NULL::text, NULL::text, NULL::text),
              ('C','monotributo',         DATE '2026-07-01',  25000.00,         'socio', 'Franco',   NULL,       NULL),
              ('D','jardin',              DATE '2026-11-01',  30000.00,         'caja',  NULL,       'chicas',   NULL),
              ('E','termotanque',         DATE '2026-08-01', 180000.00,         'socio', 'Rodrigo',  NULL,       'Guatemala'),
              ('E','horas de trabajo',    DATE '2026-07-01',  60000.00,         'socio', 'Rodrigo',  NULL,       'Tokio')
               ) v(clase, etiqueta, periodo, monto, ptipo, psocio, vzona, vcab)
            ON  v.clase    = g.clase
            AND v.etiqueta = g.etiqueta
            AND v.periodo  = g.periodo
            AND v.monto    = g.monto
            AND v.ptipo    = g.pagador_tipo
            AND v.psocio IS NOT DISTINCT FROM sp.nombre
            AND v.vzona  IS NOT DISTINCT FROM z.nombre
            AND v.vcab   IS NOT DISTINCT FROM cb.nombre
         WHERE g.creado_por = 'seed_9f_validacion'),
       CASE WHEN (SELECT COUNT(*)
          FROM gastos_internos g
          LEFT JOIN socios  sp ON sp.id_socio  = g.id_socio_pagador
          LEFT JOIN zonas   z  ON z.id_zona    = g.id_zona
          LEFT JOIN cabanas cb ON cb.id_cabana = g.id_cabana
          JOIN (VALUES
              ('A','insumos de limpieza', DATE '2026-07-01',  40000.00::numeric,'caja',  NULL::text, NULL::text, NULL::text),
              ('C','monotributo',         DATE '2026-07-01',  25000.00,         'socio', 'Franco',   NULL,       NULL),
              ('D','jardin',              DATE '2026-11-01',  30000.00,         'caja',  NULL,       'chicas',   NULL),
              ('E','termotanque',         DATE '2026-08-01', 180000.00,         'socio', 'Rodrigo',  NULL,       'Guatemala'),
              ('E','horas de trabajo',    DATE '2026-07-01',  60000.00,         'socio', 'Rodrigo',  NULL,       'Tokio')
               ) v(clase, etiqueta, periodo, monto, ptipo, psocio, vzona, vcab)
            ON  v.clase    = g.clase
            AND v.etiqueta = g.etiqueta
            AND v.periodo  = g.periodo
            AND v.monto    = g.monto
            AND v.ptipo    = g.pagador_tipo
            AND v.psocio IS NOT DISTINCT FROM sp.nombre
            AND v.vzona  IS NOT DISTINCT FROM z.nombre
            AND v.vcab   IS NOT DISTINCT FROM cb.nombre
         WHERE g.creado_por = 'seed_9f_validacion') = 5
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 5.05, '9F', 'secuencia gastos_internos (cierre 9F: last_value=34)',
       '34',
       (SELECT COALESCE(last_value::text, '(nunca usada)')
          FROM pg_sequences
         WHERE schemaname = 'public'
           AND sequencename = 'gastos_internos_id_gasto_seq'),
       'INFO'

UNION ALL
SELECT 5.06, '9F', 'gastos legacy: 0 filas, 10 columnas, secuencia nunca usada',
       '0 filas, 10 col, virgen',
       (SELECT COUNT(*)::text FROM gastos) || ' filas, ' ||
       (SELECT COUNT(*)::text FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'gastos') || ' col, ' ||
       (SELECT CASE WHEN last_value IS NULL THEN 'virgen' ELSE 'usada=' || last_value::text END
          FROM pg_sequences
         WHERE schemaname = 'public' AND sequencename = 'gastos_id_gasto_seq'),
       CASE WHEN (SELECT COUNT(*) FROM gastos) = 0
             AND (SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'gastos') = 10
             AND (SELECT last_value IS NULL FROM pg_sequences
                   WHERE schemaname = 'public' AND sequencename = 'gastos_id_gasto_seq')
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 6 — SNAPSHOT DE `pagos` (la incógnita que este bloque resuelve)
-- ===========================================================================
UNION ALL
SELECT 6.01, 'PAGOS', 'marcador seed_9g_ ausente (LIKE escapado: _ es comodín)',
       '0',
       (SELECT COUNT(*)::text FROM pagos
         WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\'),
       CASE WHEN (SELECT COUNT(*) FROM pagos
                   WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\') = 0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 6.02, 'PAGOS', 'total de filas en pagos',
       'INFO (estimado ~25)',
       (SELECT COUNT(*)::text FROM pagos),
       'INFO'

UNION ALL
SELECT 6.03, 'PAGOS', 'rango de created_at (L-9B-04)',
       'INFO',
       (SELECT MIN(created_at)::date::text || ' a ' || MAX(created_at)::date::text FROM pagos),
       'INFO'

UNION ALL
-- 6.04.x — desglose tipo × estado (multi-fila)
SELECT 6.04 + (ROW_NUMBER() OVER (ORDER BY t.tipo, t.est)) / 1000.0,
       'PAGOS', 'desglose tipo / estado', '—',
       t.tipo || ' / ' || t.est || ' : n=' || t.n::text
              || ' · $ ' || t.s::numeric(14,2)::text,
       'INFO'
FROM (SELECT tipo, estado::text AS est, COUNT(*) AS n,
             COALESCE(SUM(monto_recibido),0) AS s
        FROM pagos GROUP BY tipo, estado) t

UNION ALL
-- 6.05.x — VISTA PREVIA CAJA PERCIBIDA (D-9G-03): paso 1 y paso 6 por mes
SELECT 6.05 + (ROW_NUMBER() OVER (ORDER BY m.mes)) / 1000.0,
       'PAGOS', 'caja percibida: paso1/paso6 por mes de created_at', '—',
       m.mes
       || ' -> paso1 $ ' || COALESCE(m.p1,0)::numeric(14,2)::text
       || ' · paso6 $ '  || COALESCE(m.p6,0)::numeric(14,2)::text
       || ' · filas='    || m.n::text,
       'INFO'
FROM (SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS mes,
             COUNT(*) AS n,
             SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                                           AND estado::text = 'confirmado') AS p1,
             SUM(monto_recibido) FILTER (WHERE tipo = 'extra'
                                           AND estado::text = 'confirmado') AS p6
        FROM pagos GROUP BY 1) m

UNION ALL
SELECT 6.06, 'PAGOS', 'tipos reembolso/ajuste (fuera del MVP de cascada, D-9G-02)',
       '0',
       (SELECT COUNT(*)::text FROM pagos WHERE tipo IN ('reembolso','ajuste')),
       CASE WHEN (SELECT COUNT(*) FROM pagos WHERE tipo IN ('reembolso','ajuste')) = 0
            THEN 'OK' ELSE 'ATENCION' END

UNION ALL
SELECT 6.07, 'PAGOS', 'pagos en estados no confirmados',
       '0',
       (SELECT COUNT(*)::text FROM pagos WHERE estado::text <> 'confirmado'),
       CASE WHEN (SELECT COUNT(*) FROM pagos WHERE estado::text <> 'confirmado') = 0
            THEN 'OK' ELSE 'ATENCION' END

UNION ALL
SELECT 6.08, 'PAGOS', 'atribución a reserva (patrón 9A)',
       'INFO',
       (SELECT 'directa=' || COUNT(*) FILTER (WHERE id_reserva IS NOT NULL)::text
            || ' · via_prereserva=' || COUNT(*) FILTER (WHERE id_reserva IS NULL
                                            AND id_reserva_atribuida IS NOT NULL)::text
            || ' · sin_atribucion=' || COUNT(*) FILTER (WHERE id_reserva_atribuida IS NULL)::text
          FROM pagos_norm),
       'INFO'

UNION ALL
SELECT 6.09, 'PAGOS', 'confirmados sena/saldo SIN reserva atribuible (entran igual al paso 1 por caja percibida)',
       'INFO (estimado: 1 por $100000)',
       (SELECT 'n=' || COUNT(*)::text || ' · $ ' || COALESCE(SUM(monto_recibido),0)::numeric(14,2)::text
          FROM pagos_norm
         WHERE id_reserva_atribuida IS NULL
           AND tipo IN ('sena','saldo') AND estado_pago = 'confirmado'),
       'INFO'

UNION ALL
SELECT 6.10, 'PAGOS', 'cuadre global: facturado (reservas confirmadas) vs cobrado sena+saldo confirmado',
       'INFO',
       (SELECT 'reservas_conf=' ||
               (SELECT COUNT(*) FROM reservas WHERE estado::text = 'confirmada')::text
            || ' · facturado $ ' ||
               (SELECT COALESCE(SUM(monto_total),0) FROM reservas
                 WHERE estado::text = 'confirmada')::numeric(14,2)::text
            || ' · cobrado $ ' ||
               (SELECT COALESCE(SUM(monto_recibido),0) FROM pagos
                 WHERE tipo IN ('sena','saldo')
                   AND estado::text = 'confirmado')::numeric(14,2)::text),
       'INFO'

UNION ALL
-- 6.50.x — candidatas para colgar el seed 9G (todas las reservas, con saldo real)
SELECT 6.50 + (ROW_NUMBER() OVER (ORDER BY r.id_reserva)) / 1000.0,
       'PAGOS', 'candidatas seed: reserva / cabaña / estadía / saldo real', '—',
       'id=' || r.id_reserva::text
       || ' · ' || c.nombre
       || ' · ' || r.fecha_checkin::text || '->' || r.fecha_checkout::text
       || ' · ' || r.estado::text
       || ' · total $ ' || r.monto_total::numeric(14,2)::text
       || ' · cobrado $ ' || COALESCE(cb.cobrado,0)::numeric(14,2)::text
       || ' · saldo $ ' || (r.monto_total - COALESCE(cb.cobrado,0))::numeric(14,2)::text
       || CASE WHEN r.monto_total - COALESCE(cb.cobrado,0) = 0 THEN ' [SALDADA]' ELSE '' END,
       'INFO'
FROM reservas r
JOIN cabanas c ON c.id_cabana = r.id_cabana
LEFT JOIN cobrado_por_reserva cb ON cb.id_reserva = r.id_reserva

-- ===========================================================================
-- SECCIÓN 7 — FUNCIONES 9G AUSENTES
-- ===========================================================================
UNION ALL
SELECT 7.01, '9G', 'las 6 funciones de 9G ausentes al inicio',
       '0',
       (SELECT COUNT(*)::text FROM pg_proc
         WHERE pronamespace = 'public'::regnamespace
           AND proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                           'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                           'gastos_sin_incidencia_periodo')),
       CASE WHEN (SELECT COUNT(*) FROM pg_proc
                   WHERE pronamespace = 'public'::regnamespace
                     AND proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                                     'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo',
                                     'gastos_sin_incidencia_periodo')) = 0
            THEN 'OK' ELSE 'FALLO' END

-- ===========================================================================
-- SECCIÓN 8 — BASELINES PARA NO-REGRESIÓN (Bloque E compara contra esto)
-- ===========================================================================
UNION ALL
SELECT 8.01, 'BASELINE', 'md5 de cabanas.activa (formula 9G: id:activa ordenado)',
       'INFO',
       (SELECT md5(string_agg(id_cabana::text || ':' || activa::text, '|' ORDER BY id_cabana))
          FROM cabanas),
       'INFO'

UNION ALL
SELECT 8.02, 'BASELINE', 'valores de cabanas.activa',
       'INFO',
       (SELECT string_agg(nombre || '=' || activa::text, ', ' ORDER BY id_cabana) FROM cabanas),
       'INFO'

UNION ALL
SELECT 8.03, 'BASELINE', 'conteos de referencia',
       'INFO',
       'zonas=' || (SELECT COUNT(*)::text FROM zonas)
       || ' · cabana_zona=' || (SELECT COUNT(*)::text FROM cabana_zona)
       || ' · activaciones=' || (SELECT COUNT(*)::text FROM activaciones_operativas)
       || ' · gastos_internos=' || (SELECT COUNT(*)::text FROM gastos_internos)
       || ' · gastos_legacy=' || (SELECT COUNT(*)::text FROM gastos)
       || ' · pagos=' || (SELECT COUNT(*)::text FROM pagos)
       || ' · reservas=' || (SELECT COUNT(*)::text FROM reservas),
       'INFO'
)

-- ===========================================================================
-- SALIDA + VEREDICTO
-- ===========================================================================
SELECT ROUND(orden, 3) AS orden, seccion, chequeo, esperado, obtenido, estado
FROM checks

UNION ALL
SELECT 99.99, 'VEREDICTO', 'resultado global del Bloque A',
       'FALLO=0',
       'FALLO=' || v.f::text || ' · ATENCION=' || v.a::text
       || ' · OK=' || v.k::text || ' · INFO=' || v.i::text,
       CASE WHEN v.f = 0 THEN 'VERDE - apto para diseñar Bloque B (seed)'
            ELSE 'FRENAR - revisar FALLOs antes de seguir' END
FROM (SELECT COUNT(*) FILTER (WHERE estado = 'FALLO')    AS f,
             COUNT(*) FILTER (WHERE estado = 'ATENCION') AS a,
             COUNT(*) FILTER (WHERE estado = 'OK')       AS k,
             COUNT(*) FILTER (WHERE estado = 'INFO')     AS i
        FROM checks) v

ORDER BY 1;
