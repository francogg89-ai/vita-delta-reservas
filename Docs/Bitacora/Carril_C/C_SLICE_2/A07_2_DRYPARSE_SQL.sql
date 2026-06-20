-- ============================================================================
-- A07.2 — DRY-PARSE NO DESTRUCTIVO de las 5 queries del wrapper
-- portal-a07-crear-reserva__TEST. Correr en TEST (vita-delta-test).
--
-- Qué hace: PREPARE valida SINTAXIS + existencia de funciones/columnas + plan,
-- SIN ejecutar. Las funciones VOLATILE (crear_prereserva, registrar_pago,
-- confirmar_reserva), el advisory lock y los agregados NO corren en PREPARE
-- (corren recién en EXECUTE, que acá NO se hace). DEALLOCATE limpia al final.
-- NO escribe filas, NO toma locks, NO modifica nada.
--
-- Cómo correr: pegar TODO en el SQL Editor de Supabase (TEST) o en un único
-- nodo Postgres de n8n con la credencial vita_supabase_test. Si alguna query
-- tiene un error de sintaxis o referencia una columna/función inexistente, el
-- PREPARE correspondiente falla y el nombre del statement (a07_pgN) indica cuál.
-- Resultado esperado si todo parsea: la última SELECT devuelve 5 filas 'ok'.
-- ============================================================================

-- PG-0 / PG-4 (recheck RESERVA por idempotency_key) — idénticas.
PREPARE a07_pg0 (text) AS
WITH hit AS (
  SELECT r.id_reserva, r.id_pre_reserva, r.id_huesped
  FROM reservas r
  JOIN pre_reservas pr ON pr.id_pre_reserva = r.id_pre_reserva
  WHERE pr.idempotency_key = $1
)
SELECT (SELECT count(*) FROM hit)::int                               AS n,
       (SELECT id_reserva     FROM hit ORDER BY id_reserva LIMIT 1)  AS id_reserva,
       (SELECT id_pre_reserva FROM hit ORDER BY id_reserva LIMIT 1)  AS id_pre_reserva,
       (SELECT id_huesped     FROM hit ORDER BY id_reserva LIMIT 1)  AS id_huesped;

-- PG-1 (crear_prereserva)
PREPARE a07_pg1 (jsonb) AS
SELECT crear_prereserva($1) AS resultado;

-- PG-2 (lock + precheck seña + registro condicional, un solo parámetro JSON)
PREPARE a07_pg2 (jsonb) AS
WITH args AS (
  SELECT ($1)->>'idem'             AS idem,
         (($1)->>'id_pre')::bigint AS id_pre,
         ($1)->>'sev'              AS sev,
         ($1)->'payload2'          AS payload2
),
lk AS MATERIALIZED (
  SELECT pg_advisory_xact_lock(hashtextextended((SELECT idem FROM args), 0::bigint))
),
ex AS (
  SELECT count(p.id_pago)::int                                              AS n,
         count(p.id_pago) FILTER (WHERE p.estado='confirmado')::int         AS n_conf,
         (array_agg(p.id_pago ORDER BY p.id_pago)
            FILTER (WHERE p.estado='confirmado'))[1]                        AS id_pago_conf
  FROM lk
  CROSS JOIN args a
  LEFT JOIN pagos p
    ON p.id_prereserva = a.id_pre AND p.tipo='sena' AND p.source_event = a.sev
)
SELECT ex.n, ex.n_conf, ex.id_pago_conf,
       CASE WHEN ex.n = 0 THEN registrar_pago((SELECT payload2 FROM args)) ELSE NULL END AS resultado_registro
FROM ex;

-- PG-3 (confirmar_reserva)
PREPARE a07_pg3 (jsonb) AS
SELECT confirmar_reserva($1) AS resultado;

-- Si llegaste hasta acá sin error, las 5 queries parsean y planifican OK.
SELECT 'a07_pg0 (=PG-0/PG-4)' AS stmt, 'ok' AS parse
UNION ALL SELECT 'a07_pg1 (crear_prereserva)',  'ok'
UNION ALL SELECT 'a07_pg2 (lock+pago)',         'ok'
UNION ALL SELECT 'a07_pg3 (confirmar_reserva)', 'ok'
UNION ALL SELECT '(PG-4 = misma query que a07_pg0)', 'ok';

DEALLOCATE a07_pg0;
DEALLOCATE a07_pg1;
DEALLOCATE a07_pg2;
DEALLOCATE a07_pg3;

-- ----------------------------------------------------------------------------
-- (Opcional) Pre-check read-only de columnas/funciones clave, por si querés
-- confirmarlas explícitamente además del PREPARE. No escribe nada.
-- ----------------------------------------------------------------------------
-- SELECT
--   to_regclass('public.pagos')                              AS tabla_pagos,
--   (SELECT count(*) FROM information_schema.columns
--      WHERE table_name='pagos'
--        AND column_name IN ('id_pago','id_prereserva','estado','tipo','source_event')) AS cols_pagos_ok,  -- esperado 5
--   to_regprocedure('public.crear_prereserva(jsonb)')        AS fn_crear,
--   to_regprocedure('public.registrar_pago(jsonb)')          AS fn_pago,
--   to_regprocedure('public.confirmar_reserva(jsonb)')       AS fn_confirmar;
