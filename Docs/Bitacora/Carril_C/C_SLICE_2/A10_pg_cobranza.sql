-- ============================================================================
-- C_SLICE2 / A10 -- Nodo PG_cobranza (St1 + St2, queryBatching: transaction)
-- $1 = sql_payload jsonb (server-side, armado por el nodo 'derivar').
-- Devuelve la columna 'resultado' (jsonb INTERNO; el render lo mapea a la allowlist).
-- Saldo BYTE-ALINEADO a A12 (D-C-49 / L-C-14): mismos CTE reserva_por_prereserva +
-- pagos_reserva_normalizados + FILTER-en-SUM. saldo_real = monto_total - total_pagado_confirmado.
-- Anti-OPS: este nodo solo se invoca en TEST; el wrapper valido ambiente en verificar_acceso.
-- ============================================================================

-- St1 -- Lock transaccional por id_reserva (advisory xact; namespaced; se libera en COMMIT/ROLLBACK).
SELECT pg_advisory_xact_lock( hashtext('a10_cobranza_saldo:' || (($1::jsonb)->>'id_reserva')) );

-- St2 -- Idempotencia (con control de mismatch) -> recalculo de saldo in-txn -> registro atomico.
WITH
  existing AS (                                    -- (1) pago previo con el MISMO source_event
    SELECT id_pago, estado, id_reserva, tipo, medio_pago, monto_recibido, validado_por
    FROM pagos
    WHERE source_event = ($1::jsonb)->>'source_event'
    ORDER BY id_pago
    LIMIT 1
  ),
  r AS (                                           -- (2) reserva objetivo
    SELECT estado, monto_total
    FROM reservas
    WHERE id_reserva = (($1::jsonb)->>'id_reserva')::bigint
  ),
  reserva_por_prereserva AS (                      -- (3) mapeo prereserva->reserva (D-C-49/L-C-14)
    SELECT id_pre_reserva, MIN(id_reserva) AS id_reserva   --     CTE agrupada + MIN (NO escalar)
    FROM reservas
    WHERE id_pre_reserva IS NOT NULL
    GROUP BY id_pre_reserva
  ),
  pagos_reserva_normalizados AS (                  -- (4) pagos normalizados al reserva (igual que A12)
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
    -- A) Idempotencia PRIMERO: ya existe un pago con este source_event.
    WHEN EXISTS (SELECT 1 FROM existing) THEN
      CASE
        WHEN (SELECT id_reserva     FROM existing) = (($1::jsonb)->>'id_reserva')::bigint
         AND (SELECT tipo           FROM existing) = 'saldo'
         AND (SELECT medio_pago     FROM existing) = ($1::jsonb)->>'medio_pago'
         AND (SELECT monto_recibido FROM existing) = (($1::jsonb)->>'monto_recibido')::numeric
         AND (SELECT validado_por   FROM existing) = ($1::jsonb)->>'validado_por'
        THEN jsonb_build_object(
               'ok', true, 'idempotent_match', true,
               'id_pago', (SELECT id_pago FROM existing),
               'estado_pago', (SELECT estado::text FROM existing))
        ELSE jsonb_build_object('ok', false, 'error', 'idempotency_mismatch')
      END
    -- B) Reserva inexistente.
    WHEN NOT EXISTS (SELECT 1 FROM r) THEN
      jsonb_build_object('ok', false, 'error', 'reserva_no_existe')
    -- C) Estado no cobrable (solo confirmada/activa).
    WHEN (SELECT estado::text FROM r) NOT IN ('confirmada', 'activa') THEN
      jsonb_build_object('ok', false, 'error', 'estado_no_cobrable',
        'estado_reserva', (SELECT estado::text FROM r))
    -- D) Saldo ya cancelado.
    WHEN (SELECT saldo_real FROM sr) <= 0 THEN
      jsonb_build_object('ok', false, 'error', 'saldo_ya_cancelado',
        'saldo_real', (SELECT saldo_real FROM sr))
    -- E) Sobrepago.
    WHEN (($1::jsonb)->>'monto_recibido')::numeric > (SELECT saldo_real FROM sr) THEN
      jsonb_build_object('ok', false, 'error', 'excede_saldo',
        'saldo_real', (SELECT saldo_real FROM sr))
    -- F) Alta valida y nueva: registrar + red de seguridad atomica (abortar_si_falla, D-9B-19).
    ELSE
      abortar_si_falla( registrar_pago($1::jsonb) )
      || jsonb_build_object('idempotent_match', false, 'saldo_real_previo', (SELECT saldo_real FROM sr))
  END AS resultado;
