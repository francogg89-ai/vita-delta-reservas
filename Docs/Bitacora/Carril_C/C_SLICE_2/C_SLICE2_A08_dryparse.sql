-- ============================================================================
-- C_SLICE2_A08 — DRY-PARSE SQL (read-only). Valida que la query de escritura del
-- wrapper A08 parsea y que crear_bloqueo(jsonb) existe con la firma esperada.
-- NO ejecuta escritura: PREPARE solo parsea/planifica (la ejecucion seria EXECUTE,
-- que no se hace). Correr en TEST antes de activar el wrapper.
-- ============================================================================
PREPARE a08_dryparse AS SELECT crear_bloqueo($1::jsonb) AS resultado;
DEALLOCATE a08_dryparse;

PREPARE a08_amb AS SELECT valor FROM configuracion_general WHERE clave = 'ambiente';
DEALLOCATE a08_amb;

SELECT 'dry-parse A08 OK (crear_bloqueo + leer_ambiente parsean)' AS resultado;
