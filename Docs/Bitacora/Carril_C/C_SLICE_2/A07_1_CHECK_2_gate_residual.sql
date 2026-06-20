-- ============================================================================
-- A07.1 — CHECK 2: Gate de residual pre-smoke (precondición dura de escritura)
-- Carril C / Portal Operativo Interno — Slice 2 / A07.
--
-- NATURALEZA: 100% READ-ONLY. Solo cuenta filas con el sentinel del namespace.
-- DÓNDE EJECUTAR: indistinto (SQL Editor TEST o nodo Postgres). Mide ESTADO de
--   la base, no de la credencial, así que el SQL Editor de TEST sirve.
--
-- CRITERIO DE PASO (D-C-59):
--   - Las 4 columnas deben dar 0, y veredicto_gate_ok debe ser TRUE.
--   - Si CUALQUIER conteo > 0 → ABORTO del smoke. NO se ejecuta teardown ciego.
--     Se analiza de dónde salió el residual portal_test_a07_% ANTES de escribir.
--   - Snapshot pre = 0 es precondición DURA de cualquier escritura del smoke,
--     no un nice-to-have.
--
-- Cubre las mismas 4 fuentes que el teardown (FK-safe): pagos, reservas,
-- pre_reservas (por source_event O idempotency_key) y log_cambios.
-- ============================================================================

SELECT
  (SELECT count(*) FROM pagos
     WHERE source_event LIKE 'portal_test_a07_%')                       AS residual_pagos,
  (SELECT count(*) FROM reservas
     WHERE source_event LIKE 'portal_test_a07_%')                       AS residual_reservas,
  (SELECT count(*) FROM pre_reservas
     WHERE source_event   LIKE 'portal_test_a07_%'
        OR idempotency_key LIKE 'portal_test_a07_%')                    AS residual_pre_reservas,
  (SELECT count(*) FROM log_cambios
     WHERE source_event LIKE 'portal_test_a07_%')                       AS residual_logs,
  -- Veredicto agregado: TRUE solo si las 4 fuentes están en 0.
  (    (SELECT count(*) FROM pagos        WHERE source_event LIKE 'portal_test_a07_%') = 0
   AND (SELECT count(*) FROM reservas     WHERE source_event LIKE 'portal_test_a07_%') = 0
   AND (SELECT count(*) FROM pre_reservas WHERE source_event   LIKE 'portal_test_a07_%'
                                             OR idempotency_key LIKE 'portal_test_a07_%') = 0
   AND (SELECT count(*) FROM log_cambios  WHERE source_event LIKE 'portal_test_a07_%') = 0
  )                                                                     AS veredicto_gate_ok;
