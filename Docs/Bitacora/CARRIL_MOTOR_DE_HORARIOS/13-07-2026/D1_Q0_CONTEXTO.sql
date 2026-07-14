-- ====================================================================================
-- D1_Q0_CONTEXTO.sql
-- Bloque B1.3-consolidacion-canonica * D1 * contexto de ejecucion
-- TEST unicamente. 100% LECTURA. Autocontenido: trae su propio gate y su propia
-- transaccion READ ONLY. No se puede ejecutar esta Q sin el gate: el archivo ES la Q.
-- Repo de referencia: HEAD 07fea85802bc4fccbff1236813593762aefe58d9
-- ====================================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog, public;

DO $gate$
DECLARE
  v_amb text := (
    SELECT valor
    FROM public.configuracion_general
    WHERE clave = 'ambiente'
  );
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION
      'GATE D1: ambiente=% (esperado test). Abortando.',
      COALESCE(v_amb, '<null>');
  END IF;
END
$gate$;

-- Q0 -- CONTEXTO DE EJECUCION (1 fila).
SELECT
  'Q0_CONTEXTO'                                                              AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  current_database()                                                         AS database,
  current_user                                                               AS usuario_actual,
  session_user                                                               AS usuario_sesion,
  version()                                                                  AS pg_version,
  current_setting('server_version_num')                                      AS pg_version_num,
  current_setting('search_path')                                             AS search_path,
  current_setting('TimeZone')                                                AS timezone,
  now()                                                                      AS txn_start_ts,
  clock_timestamp()                                                          AS wall_clock_ts,
  inet_server_addr()::text                                                   AS server_addr;

COMMIT;
