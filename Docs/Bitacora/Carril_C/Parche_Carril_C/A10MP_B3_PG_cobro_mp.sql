-- A10-MP -- PG_cobro_mp (St1 + St2, queryBatching: transaction). $1 = sql_payload jsonb (de derivar).
-- Generaliza el PG_cobranza de W10 (A10). B3.1: idempotencia por FIRMA CANONICA DE LINEAS (tipo+
-- medio_pago+monto_recibido+notas), comparada como MULTISET (arrays de texto ordenados, order-independent).
-- La firma ESPERADA se deriva de sql_payload.lineas y la EXISTENTE de pagos, ambas con la MISMA
-- normalizacion EN SQL (sin render JS->SQL): asi un replay con misma key pero medio/traza distintos
-- (bancaria vs mp, efectivo vs otros, descripcion_otros distinta) da idempotency_mismatch, no match.
-- Saldo BYTE-ALINEADO a A12. Branch F registra TODAS las lineas via CTE MATERIALIZED (abortar_si_falla
-- por linea -> rollback atomico si una falla, D-9B-19). NO toca registrar_pago/tablas/enums: solo invoca.

-- St1 -- Lock transaccional por id_reserva (advisory xact; se libera en COMMIT/ROLLBACK).
SELECT pg_advisory_xact_lock( hashtext('a10mp_cobro_saldo:' || (($1::jsonb)->>'id_reserva')) );

-- St2 -- Idempotencia (firma canonica de lineas) -> saldo in-txn -> alta multi-linea atomica.
WITH
  existing_arr AS (                                -- (1) firma de las lineas YA registradas (source_event)
    SELECT COALESCE(array_agg(obj::text ORDER BY obj::text), ARRAY[]::text[]) AS a
    FROM (
      SELECT jsonb_build_object(
               't',  tipo,
               'm',  medio_pago,
               'mr', to_char(monto_recibido, 'FM999999999990.00'),
               'n',  COALESCE(notas, '')
             ) AS obj
      FROM pagos
      WHERE source_event = ($1::jsonb)->>'source_event'
    ) e
  ),
  expected_arr AS (                                -- (1b) firma de las lineas ENTRANTES (MISMA normalizacion)
    SELECT COALESCE(array_agg(obj::text ORDER BY obj::text), ARRAY[]::text[]) AS a
    FROM (
      SELECT jsonb_build_object(
               't',  l->>'tipo',
               'm',  l->>'medio_pago',
               'mr', to_char((l->>'monto_recibido')::numeric, 'FM999999999990.00'),
               'n',  COALESCE(l->>'notas', '')
             ) AS obj
      FROM jsonb_array_elements( ($1::jsonb)->'lineas' ) AS l
    ) x
  ),
  r AS (                                           -- (2) reserva objetivo
    SELECT estado, monto_total
    FROM reservas
    WHERE id_reserva = (($1::jsonb)->>'id_reserva')::bigint
  ),
  reserva_por_prereserva AS (                      -- (3) mapeo prereserva->reserva (D-C-49/L-C-14)
    SELECT id_pre_reserva, MIN(id_reserva) AS id_reserva
    FROM reservas
    WHERE id_pre_reserva IS NOT NULL
    GROUP BY id_pre_reserva
  ),
  pagos_reserva_normalizados AS (                  -- (4) pagos normalizados (igual que A12)
    SELECT p.estado, p.tipo, p.monto_recibido,
           COALESCE(p.id_reserva, rpp.id_reserva) AS id_reserva_normalizado
    FROM pagos p
    LEFT JOIN reserva_por_prereserva rpp ON rpp.id_pre_reserva = p.id_prereserva
  ),
  pagado AS (                                      -- (5) total confirmado (sena+saldo) del objetivo
    SELECT COALESCE(SUM(prn.monto_recibido) FILTER (
             WHERE prn.estado = 'confirmado' AND prn.tipo IN ('sena', 'saldo')), 0) AS total_pagado_confirmado
    FROM pagos_reserva_normalizados prn
    WHERE prn.id_reserva_normalizado = (($1::jsonb)->>'id_reserva')::bigint
  ),
  sr AS (                                          -- (6) saldo vivo (NUNCA reservas.monto_saldo)
    SELECT (SELECT monto_total FROM r) - (SELECT total_pagado_confirmado FROM pagado) AS saldo_real
  )
SELECT
  CASE
    -- A) Idempotencia PRIMERO: ya hay lineas con este source_event. Compara FIRMA CANONICA (multiset).
    WHEN cardinality((SELECT a FROM existing_arr)) > 0 THEN
      CASE
        WHEN (SELECT a FROM existing_arr) = (SELECT a FROM expected_arr)
        THEN jsonb_build_object('ok', true, 'idempotent_match', true)
        ELSE jsonb_build_object('ok', false, 'error', 'idempotency_mismatch')
      END
    -- B) Reserva inexistente.
    WHEN NOT EXISTS (SELECT 1 FROM r) THEN
      jsonb_build_object('ok', false, 'error', 'reserva_no_existe')
    -- C) Estado no cobrable (solo confirmada/activa).
    WHEN (SELECT estado::text FROM r) NOT IN ('confirmada', 'activa') THEN
      jsonb_build_object('ok', false, 'error', 'estado_no_cobrable', 'estado_reserva', (SELECT estado::text FROM r))
    -- D) Saldo ya cancelado.
    WHEN (SELECT saldo_real FROM sr) <= 0 THEN
      jsonb_build_object('ok', false, 'error', 'saldo_ya_cancelado', 'saldo_real', (SELECT saldo_real FROM sr))
    -- E) Sobrepago: la SUMA de saldo supera el saldo_real.
    WHEN (($1::jsonb)->>'suma_saldo')::numeric > (SELECT saldo_real FROM sr) THEN
      jsonb_build_object('ok', false, 'error', 'excede_saldo', 'saldo_real', (SELECT saldo_real FROM sr))
    -- F) Alta valida y nueva: registrar TODAS las lineas, atomico (abortar_si_falla por linea, D-9B-19).
    ELSE
      ( WITH _ins AS MATERIALIZED (
          SELECT public.abortar_si_falla( public.registrar_pago( l.value ) ) AS res
          FROM jsonb_array_elements( ($1::jsonb)->'lineas' ) AS l
        )
        SELECT jsonb_build_object(
          'ok', true,
          'idempotent_match', false,
          'cant_lineas', (SELECT count(*) FROM _ins),
          'saldo_real_previo', (SELECT saldo_real FROM sr)
        ) )
  END AS resultado;
