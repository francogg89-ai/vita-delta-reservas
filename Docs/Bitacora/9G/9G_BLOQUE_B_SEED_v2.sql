-- ============================================================================
-- VITA DELTA · ETAPA 9G · BLOQUE B v2 — SEED DE PAGOS DE LABORATORIO
--                                        (gates reforzados pre-insert)
-- ----------------------------------------------------------------------------
-- Entorno objetivo : TEST (vita-delta-test). NO correr en OPS. NO viaja a OPS.
-- Naturaleza       : ÚNICO write de la etapa 9G (excepción de laboratorio
--                    aprobada: INSERT directo, sin registrar_pago()).
-- Marcador         : source_event LIKE 'seed\_9g\_%' ESCAPE '\' (el '_' es
--                    comodín de LIKE; siempre escapado). Borrable completo
--                    con el DELETE del apéndice.
-- ADVERTENCIA DECLARADA (va a cierre como D-9G-13): los 5 pagos seed alteran
-- los saldos derivados de las reservas 5/6/7/10 en TEST mientras existan.
-- Son fixture técnico para alimentar la cascada y reproducir el ejemplo
-- numérico validado. Se borran por marcador al cierre de 9G.
--
-- Cómo correr (TRES selecciones separadas):
--   RUN 0 — pre-chequeo read-only. Evalúa cada gate por separado.
--           Esperado: VEREDICTO 'APTO PARA RUN 1' con FALLO=0.
--           Si algún gate falla acá, FRENAR y reportar (no correr RUN 1).
--   RUN 1 — INSERT gateado (re-valida TODOS los gates de RUN 0 en el WHERE,
--           en forma atómica). Esperado: 5 filas RETURNING.
--           'INSERT 0 0' = algún gate no pasó entre RUN 0 y RUN 1 → FRENAR.
--   RUN 2 — verificación post-seed read-only. Esperado: VEREDICTO VERDE.
--
-- Foto pineada (Bloque A, 2026-06-11): 26 pagos reales, todos confirmados,
-- created_at solo en 2026-05 y 2026-06; mayo p1=530.000/p6=0; junio
-- p1=1.345.000/p6=15.150; sin reembolso/ajuste; reservas 5,6,7,10 confirmadas.
-- Qué siembra: julio p1=$670.200 + p6=$8.500; noviembre p1=$251.000
-- (estadía de julio cobrada en noviembre: demuestra D-9G-03 caja percibida).
-- Agosto queda sin pagos a propósito (mes sin ingreso para el Bloque D).
-- ============================================================================


-- ████████████████████████████████ RUN 0 ████████████████████████████████████
-- PRE-CHEQUEO DIAGNÓSTICO (read-only). Un OK por gate. Seleccionar y ejecutar.

WITH reales AS (
  SELECT * FROM pagos WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\'
),
checks AS (

SELECT 0.01::numeric AS orden, 'GATE-PRE'::text AS seccion,
       'G1: ambiente'::text AS chequeo, 'test'::text AS esperado,
       COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(ausente)') AS obtenido,
       CASE WHEN (SELECT valor FROM configuracion_general WHERE clave='ambiente')='test'
            THEN 'OK' ELSE 'FALLO' END AS estado

UNION ALL
SELECT 0.02, 'GATE-PRE', 'G2: marcador seed_9g_ ausente', '0',
       (SELECT COUNT(*)::text FROM pagos WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\'),
       CASE WHEN (SELECT COUNT(*) FROM pagos WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\')=0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 0.03, 'GATE-PRE', 'G3: reservas destino 5,6,7,10 confirmadas', '4',
       (SELECT COUNT(*)::text FROM reservas
         WHERE id_reserva IN (5,6,7,10) AND estado::text='confirmada'),
       CASE WHEN (SELECT COUNT(*) FROM reservas
                   WHERE id_reserva IN (5,6,7,10) AND estado::text='confirmada')=4
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 0.04, 'GATE-PRE', 'G4: foto intacta — pagos reales: total / confirmados / reembolso+ajuste',
       '26 / 26 / 0',
       (SELECT COUNT(*)::text || ' / ' ||
               COUNT(*) FILTER (WHERE estado::text='confirmado')::text || ' / ' ||
               COUNT(*) FILTER (WHERE tipo IN ('reembolso','ajuste'))::text
          FROM reales),
       CASE WHEN (SELECT COUNT(*) FROM reales)=26
             AND (SELECT COUNT(*) FILTER (WHERE estado::text='confirmado') FROM reales)=26
             AND (SELECT COUNT(*) FILTER (WHERE tipo IN ('reembolso','ajuste')) FROM reales)=0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 0.05, 'GATE-PRE', 'G5: foto intacta — suma global sena+saldo confirmados (reales)',
       '1875000.00',
       (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                AND estado::text='confirmado'),0)::numeric(14,2)::text FROM reales),
       CASE WHEN (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                AND estado::text='confirmado'),0) FROM reales)=1875000.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 0.06, 'GATE-PRE', 'G6: foto intacta — suma global extra confirmados (reales)',
       '15150.00',
       (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo='extra'
                AND estado::text='confirmado'),0)::numeric(14,2)::text FROM reales),
       CASE WHEN (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo='extra'
                AND estado::text='confirmado'),0) FROM reales)=15150.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 0.07, 'GATE-PRE', 'G7: ningún pago real fuera de 2026-05 / 2026-06 (jul/ago/nov limpios)',
       '0',
       (SELECT COUNT(*)::text FROM reales
         WHERE to_char(date_trunc('month', created_at),'YYYY-MM') NOT IN ('2026-05','2026-06')),
       CASE WHEN (SELECT COUNT(*) FROM reales
                   WHERE to_char(date_trunc('month', created_at),'YYYY-MM')
                         NOT IN ('2026-05','2026-06'))=0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 0.08, 'GATE-PRE', 'G8: pin mayo (reales confirmados)', 'p1=530000.00 · p6=0.00',
       (SELECT 'p1=' || COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                  AND estado::text='confirmado'),0)::numeric(14,2)::text
            || ' · p6=' || COALESCE(SUM(monto_recibido) FILTER (WHERE tipo='extra'
                  AND estado::text='confirmado'),0)::numeric(14,2)::text
          FROM reales WHERE to_char(date_trunc('month', created_at),'YYYY-MM')='2026-05'),
       CASE WHEN (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                    AND estado::text='confirmado'),0) FROM reales
                   WHERE to_char(date_trunc('month', created_at),'YYYY-MM')='2026-05')=530000.00
             AND (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo='extra'
                    AND estado::text='confirmado'),0) FROM reales
                   WHERE to_char(date_trunc('month', created_at),'YYYY-MM')='2026-05')=0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 0.09, 'GATE-PRE', 'G9: pin junio (reales confirmados)', 'p1=1345000.00 · p6=15150.00',
       (SELECT 'p1=' || COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                  AND estado::text='confirmado'),0)::numeric(14,2)::text
            || ' · p6=' || COALESCE(SUM(monto_recibido) FILTER (WHERE tipo='extra'
                  AND estado::text='confirmado'),0)::numeric(14,2)::text
          FROM reales WHERE to_char(date_trunc('month', created_at),'YYYY-MM')='2026-06'),
       CASE WHEN (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                    AND estado::text='confirmado'),0) FROM reales
                   WHERE to_char(date_trunc('month', created_at),'YYYY-MM')='2026-06')=1345000.00
             AND (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo='extra'
                    AND estado::text='confirmado'),0) FROM reales
                   WHERE to_char(date_trunc('month', created_at),'YYYY-MM')='2026-06')=15150.00
            THEN 'OK' ELSE 'FALLO' END
)
SELECT ROUND(orden,3) AS orden, seccion, chequeo, esperado, obtenido, estado FROM checks
UNION ALL
SELECT 99.99, 'VEREDICTO', 'pre-chequeo de gates', 'FALLO=0',
       'FALLO=' || v.f::text || ' · OK=' || v.k::text,
       CASE WHEN v.f=0 THEN 'APTO PARA RUN 1'
            ELSE 'FRENAR - NO correr RUN 1, reportar' END
FROM (SELECT COUNT(*) FILTER (WHERE estado='FALLO') AS f,
             COUNT(*) FILTER (WHERE estado='OK') AS k FROM checks) v
ORDER BY 1;

-- ████████████████████████████ FIN RUN 0 ████████████████████████████████████


-- ████████████████████████████████ RUN 1 ████████████████████████████████████
-- INSERT gateado: re-valida G1..G9 atómicamente en el WHERE. Esperado: 5 filas.

INSERT INTO pagos
  (id_reserva, tipo, medio_pago, monto_esperado, monto_recibido, moneda,
   estado, validado_por, validado_en, notas, source_event, created_at, updated_at)
SELECT
  v.id_reserva, v.tipo, v.medio, v.monto, v.monto, 'ARS',
  'confirmado', 'seed_9g', v.creado,
  'FIXTURE TECNICO 9G (D-9G-13): monto NO consistente con el saldo de la reserva a propósito; '
  || 'distorsiona saldos derivados mientras exista; borrar por marcador seed_9g_; NO viaja a OPS',
  v.se, v.creado, v.creado
FROM (VALUES
  (5::bigint,  'sena',  'transferencia_bancaria', 200000.00::numeric(12,2),
   TIMESTAMPTZ '2026-07-02 11:00:00-03', 'seed_9g_p1_sena_jul'),
  (6,          'saldo', 'efectivo',               300200.00,
   TIMESTAMPTZ '2026-07-08 16:30:00-03', 'seed_9g_p2_saldo_jul'),
  (7,          'saldo', 'transferencia_bancaria', 170000.00,
   TIMESTAMPTZ '2026-07-15 10:00:00-03', 'seed_9g_ev_saldo_extra_jul'),
  (7,          'extra', 'transferencia_bancaria',   8500.00,
   TIMESTAMPTZ '2026-07-15 10:00:00-03', 'seed_9g_ev_saldo_extra_jul'),
  (10,         'saldo', 'transferencia_bancaria', 251000.00,
   TIMESTAMPTZ '2026-11-05 09:00:00-03', 'seed_9g_p5_saldo_nov')
) AS v(id_reserva, tipo, medio, monto, creado, se)
WHERE
  -- G1: ambiente test
  (SELECT valor FROM configuracion_general WHERE clave='ambiente') = 'test'
  -- G2: marcador 9G ausente (idempotencia; cubre tambien "sin seed en jul/ago/nov")
  AND NOT EXISTS (SELECT 1 FROM pagos WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\')
  -- G3: reservas destino confirmadas
  AND (SELECT COUNT(*) FROM reservas
        WHERE id_reserva IN (5,6,7,10) AND estado::text='confirmada') = 4
  -- G4: foto intacta — 26 reales, todos confirmados, sin reembolso/ajuste
  AND (SELECT COUNT(*) FROM pagos
        WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\') = 26
  AND (SELECT COUNT(*) FROM pagos
        WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\'
          AND estado::text='confirmado') = 26
  AND (SELECT COUNT(*) FROM pagos
        WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\'
          AND tipo IN ('reembolso','ajuste')) = 0
  -- G5: suma global sena+saldo confirmados (reales)
  AND (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
          AND estado::text='confirmado'),0) FROM pagos
        WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\') = 1875000.00
  -- G6: suma global extra confirmados (reales)
  AND (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo='extra'
          AND estado::text='confirmado'),0) FROM pagos
        WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\') = 15150.00
  -- G7: ningún pago real fuera de 2026-05 / 2026-06
  AND (SELECT COUNT(*) FROM pagos
        WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\'
          AND to_char(date_trunc('month', created_at),'YYYY-MM')
              NOT IN ('2026-05','2026-06')) = 0
  -- G8: pin mayo
  AND (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
          AND estado::text='confirmado'),0) FROM pagos
        WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\'
          AND to_char(date_trunc('month', created_at),'YYYY-MM')='2026-05') = 530000.00
  AND (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo='extra'
          AND estado::text='confirmado'),0) FROM pagos
        WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\'
          AND to_char(date_trunc('month', created_at),'YYYY-MM')='2026-05') = 0
  -- G9: pin junio
  AND (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
          AND estado::text='confirmado'),0) FROM pagos
        WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\'
          AND to_char(date_trunc('month', created_at),'YYYY-MM')='2026-06') = 1345000.00
  AND (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo='extra'
          AND estado::text='confirmado'),0) FROM pagos
        WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\'
          AND to_char(date_trunc('month', created_at),'YYYY-MM')='2026-06') = 15150.00
RETURNING id_pago, id_reserva, tipo, monto_recibido, created_at::date AS fecha_caja, source_event;

-- ████████████████████████████ FIN RUN 1 ████████████████████████████████████


-- ████████████████████████████████ RUN 2 ████████████████████████████████████
-- Verificación post-seed (100% read-only). Pegar la salida completa.

WITH percibida AS (
  SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS mes,
         COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                                                AND estado::text = 'confirmado'), 0) AS p1,
         COALESCE(SUM(monto_recibido) FILTER (WHERE tipo = 'extra'
                                                AND estado::text = 'confirmado'), 0) AS p6
  FROM pagos
  GROUP BY 1
),
checks AS (

SELECT 1.01::numeric AS orden, 'SEED'::text AS seccion,
       'pagos marcados seed_9g_ (LIKE escapado)'::text AS chequeo,
       '5'::text AS esperado,
       (SELECT COUNT(*)::text FROM pagos
         WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\') AS obtenido,
       CASE WHEN (SELECT COUNT(*) FROM pagos
                   WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\') = 5
            THEN 'OK' ELSE 'FALLO' END AS estado

UNION ALL
SELECT 1.02, 'SEED', 'composición exacta de los 5 (tipo/monto/mes/reserva/estado/validador)',
       '5 coincidencias',
       (SELECT COUNT(*)::text
          FROM pagos p
          JOIN (VALUES
              ('seed_9g_p1_sena_jul',        'sena',  200000.00::numeric, '2026-07',  5::bigint),
              ('seed_9g_p2_saldo_jul',       'saldo', 300200.00,          '2026-07',  6),
              ('seed_9g_ev_saldo_extra_jul', 'saldo', 170000.00,          '2026-07',  7),
              ('seed_9g_ev_saldo_extra_jul', 'extra',   8500.00,          '2026-07',  7),
              ('seed_9g_p5_saldo_nov',       'saldo', 251000.00,          '2026-11', 10)
               ) v(se, tipo, monto, mes, id_reserva)
            ON  v.se         = p.source_event
            AND v.tipo       = p.tipo
            AND v.monto      = p.monto_recibido
            AND v.monto      = p.monto_esperado
            AND v.mes        = to_char(date_trunc('month', p.created_at), 'YYYY-MM')
            AND v.id_reserva = p.id_reserva
         WHERE p.estado::text = 'confirmado'
           AND p.validado_por = 'seed_9g'),
       CASE WHEN (SELECT COUNT(*)
          FROM pagos p
          JOIN (VALUES
              ('seed_9g_p1_sena_jul',        'sena',  200000.00::numeric, '2026-07',  5::bigint),
              ('seed_9g_p2_saldo_jul',       'saldo', 300200.00,          '2026-07',  6),
              ('seed_9g_ev_saldo_extra_jul', 'saldo', 170000.00,          '2026-07',  7),
              ('seed_9g_ev_saldo_extra_jul', 'extra',   8500.00,          '2026-07',  7),
              ('seed_9g_p5_saldo_nov',       'saldo', 251000.00,          '2026-11', 10)
               ) v(se, tipo, monto, mes, id_reserva)
            ON  v.se         = p.source_event
            AND v.tipo       = p.tipo
            AND v.monto      = p.monto_recibido
            AND v.monto      = p.monto_esperado
            AND v.mes        = to_char(date_trunc('month', p.created_at), 'YYYY-MM')
            AND v.id_reserva = p.id_reserva
         WHERE p.estado::text = 'confirmado'
           AND p.validado_por = 'seed_9g') = 5
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 1.03, 'SEED', 'source_event compartido saldo+extra (espejo caso 5 de 3b)',
       '2 filas (1 saldo + 1 extra)',
       (SELECT COUNT(*)::text || ' filas (' ||
               COUNT(*) FILTER (WHERE tipo = 'saldo')::text || ' saldo + ' ||
               COUNT(*) FILTER (WHERE tipo = 'extra')::text || ' extra)'
          FROM pagos WHERE source_event = 'seed_9g_ev_saldo_extra_jul'),
       CASE WHEN (SELECT COUNT(*) FILTER (WHERE tipo = 'saldo') FROM pagos
                   WHERE source_event = 'seed_9g_ev_saldo_extra_jul') = 1
             AND (SELECT COUNT(*) FILTER (WHERE tipo = 'extra') FROM pagos
                   WHERE source_event = 'seed_9g_ev_saldo_extra_jul') = 1
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.01, 'NO-REGRESION', 'total de filas en pagos',
       '31 (26 reales + 5 seed)',
       (SELECT COUNT(*)::text FROM pagos),
       CASE WHEN (SELECT COUNT(*) FROM pagos) = 31 THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 2.02, 'NO-REGRESION', 'pagos reales intactos (no marcados): cantidad y suma sena+saldo confirmados',
       '26 · $ 1875000.00',
       (SELECT COUNT(*)::text || ' · $ ' ||
               COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                                                      AND estado::text = 'confirmado'), 0)
               ::numeric(14,2)::text
          FROM pagos
         WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\'),
       CASE WHEN (SELECT COUNT(*) FROM pagos
                   WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\') = 26
             AND (SELECT COALESCE(SUM(monto_recibido) FILTER (WHERE tipo IN ('sena','saldo')
                                                                AND estado::text = 'confirmado'), 0)
                    FROM pagos
                   WHERE source_event NOT LIKE 'seed\_9g\_%' ESCAPE '\') = 1875000.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.01, 'PERCIBIDA', 'caja percibida 2026-05 (intacta)',
       'paso1 $ 530000.00 · paso6 $ 0.00',
       (SELECT 'paso1 $ ' || p1::numeric(14,2)::text || ' · paso6 $ ' || p6::numeric(14,2)::text
          FROM percibida WHERE mes = '2026-05'),
       CASE WHEN (SELECT p1 FROM percibida WHERE mes = '2026-05') = 530000.00
             AND (SELECT p6 FROM percibida WHERE mes = '2026-05') = 0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.02, 'PERCIBIDA', 'caja percibida 2026-06 (intacta)',
       'paso1 $ 1345000.00 · paso6 $ 15150.00',
       (SELECT 'paso1 $ ' || p1::numeric(14,2)::text || ' · paso6 $ ' || p6::numeric(14,2)::text
          FROM percibida WHERE mes = '2026-06'),
       CASE WHEN (SELECT p1 FROM percibida WHERE mes = '2026-06') = 1345000.00
             AND (SELECT p6 FROM percibida WHERE mes = '2026-06') = 15150.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.03, 'PERCIBIDA', 'caja percibida 2026-07 = ejemplo numérico validado',
       'paso1 $ 670200.00 · paso6 $ 8500.00',
       COALESCE((SELECT 'paso1 $ ' || p1::numeric(14,2)::text || ' · paso6 $ ' || p6::numeric(14,2)::text
          FROM percibida WHERE mes = '2026-07'), '(sin filas)'),
       CASE WHEN (SELECT p1 FROM percibida WHERE mes = '2026-07') = 670200.00
             AND (SELECT p6 FROM percibida WHERE mes = '2026-07') = 8500.00
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.04, 'PERCIBIDA', 'caja percibida 2026-11 = saldo de estadía julio cobrado en noviembre (D-9G-03)',
       'paso1 $ 251000.00 · paso6 $ 0.00',
       COALESCE((SELECT 'paso1 $ ' || p1::numeric(14,2)::text || ' · paso6 $ ' || p6::numeric(14,2)::text
          FROM percibida WHERE mes = '2026-11'), '(sin filas)'),
       CASE WHEN (SELECT p1 FROM percibida WHERE mes = '2026-11') = 251000.00
             AND (SELECT p6 FROM percibida WHERE mes = '2026-11') = 0
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 3.05, 'PERCIBIDA', 'agosto 2026 sin pagos (a propósito: mes sin ingreso para Bloque D)',
       '0 filas',
       COALESCE((SELECT 'p1 $ ' || p1::text || ' · p6 $ ' || p6::text
                   FROM percibida WHERE mes = '2026-08'), '0 filas'),
       CASE WHEN NOT EXISTS (SELECT 1 FROM percibida WHERE mes = '2026-08')
            THEN 'OK' ELSE 'FALLO' END

UNION ALL
SELECT 4.01, 'BASELINE', 'secuencia de pagos (referencia para el cierre)',
       'INFO',
       (SELECT COALESCE(last_value::text, '(nunca usada)') FROM pg_sequences
         WHERE schemaname = 'public' AND sequencename = 'pagos_id_pago_seq'),
       'INFO'
)
SELECT ROUND(orden, 3) AS orden, seccion, chequeo, esperado, obtenido, estado
FROM checks
UNION ALL
SELECT 99.99, 'VEREDICTO', 'resultado del Bloque B',
       'FALLO=0',
       'FALLO=' || v.f::text || ' · OK=' || v.k::text || ' · INFO=' || v.i::text,
       CASE WHEN v.f = 0 THEN 'VERDE - apto para Bloque C (funciones)'
            ELSE 'FRENAR - revisar antes de seguir' END
FROM (SELECT COUNT(*) FILTER (WHERE estado = 'FALLO') AS f,
             COUNT(*) FILTER (WHERE estado = 'OK')    AS k,
             COUNT(*) FILTER (WHERE estado = 'INFO')  AS i
        FROM checks) v
ORDER BY 1;

-- ████████████████████████████ FIN RUN 2 ████████████████████████████████████


-- ============================================================================
-- APÉNDICE — LIMPIEZA (NO ejecutar ahora; se corre al cierre de 9G o ante
-- necesidad de reset). Borra exclusivamente el seed por marcador:
--
--   DELETE FROM pagos WHERE source_event LIKE 'seed\_9g\_%' ESCAPE '\';
--
-- Sin reset de secuencia (D-9F-21: los huecos de id son aceptables).
-- ============================================================================
