-- ============================================================================
-- B4_0A_ROLLBACK.sql -- Reversion TOTAL de B4-0A.
--
-- Deja la base exactamente como estaba antes de B4-0A:
-- sin rol, sin tablas api_precios_*, sin funciones api_precios_*, sin jobs b4_*.
--
-- NO revierte el REVOKE defensivo sobre las 13 precios_* (seccion 9.bis de B4-0A):
-- ese REVOKE es el estado CORRECTO segun B3 (owner-only) y revertirlo REABRIRIA
-- un agujero. Si B3 ya lo tenia, el REVOKE fue no-op y no hay nada que revertir.
--
-- IDEMPOTENTE: se puede correr aunque B4-0A haya fallado a la mitad.
-- Termina con un VERIFY de rollback.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) JOBS pg_cron  (fuera de transaccion: cron.unschedule commitea aparte)
--    Tolerante: no falla si el job no existe.
-- ---------------------------------------------------------------------------
DO $cron$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT jobname FROM cron.job WHERE jobname LIKE 'b4_%' LOOP
    PERFORM cron.unschedule(r.jobname);
    RAISE NOTICE 'unschedule: %', r.jobname;
  END LOOP;
END
$cron$;

BEGIN;

-- ---------------------------------------------------------------------------
-- 2) FUNCIONES -- orden inverso de dependencias.
--    IF EXISTS en todas: idempotente.
-- ---------------------------------------------------------------------------

-- 2.1 expuestas (nadie las llama desde SQL)
DROP FUNCTION IF EXISTS api_precios_cotizar_exponer(UUID, JSONB);
DROP FUNCTION IF EXISTS api_precios_congelar_exponer(UUID, JSONB, UUID);
DROP FUNCTION IF EXISTS api_precios_obtener_exponer(UUID, UUID);
DROP FUNCTION IF EXISTS api_precios_admitir(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID, UUID);
DROP FUNCTION IF EXISTS api_precios_probe_ambiente();

-- 2.2 core (los llamaban los *_exponer, ya dropeados)
DROP FUNCTION IF EXISTS api_precios_cotizar_core(JSONB);
DROP FUNCTION IF EXISTS api_precios_congelar_core(JSONB, UUID, TEXT);
DROP FUNCTION IF EXISTS api_precios_obtener_core(UUID);

-- 2.3 validadores y consumidores (los llamaban admitir/exponer/core)
DROP FUNCTION IF EXISTS api_precios_validar_payload(JSONB, TEXT);
DROP FUNCTION IF EXISTS api_precios_validar_admision(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID);
DROP FUNCTION IF EXISTS api_precios_rl_consumir(TEXT, TEXT);
DROP FUNCTION IF EXISTS api_precios_nonce_consumir(TEXT, UUID);
DROP FUNCTION IF EXISTS api_precios_ticket_hash_v1(TEXT, TEXT, TEXT, JSONB, UUID, UUID);

-- 2.4 purgas (las llamaba cron, ya desprogramado)
DROP FUNCTION IF EXISTS api_precios_ticket_purgar();
DROP FUNCTION IF EXISTS api_precios_nonce_purgar();
DROP FUNCTION IF EXISTS api_precios_rl_purgar();
DROP FUNCTION IF EXISTS api_precios_idempotencia_purgar();

-- 2.5 guards (los llamaba todo lo anterior: van ULTIMOS)
DROP FUNCTION IF EXISTS api_precios_gate_ambiente();
DROP FUNCTION IF EXISTS api_precios_guard_sesion();

-- ---------------------------------------------------------------------------
-- 3) TABLAS
--    api_precios_idempotencia tiene FK -> cotizaciones_precio ON DELETE RESTRICT.
--    Dropear la tabla HIJA no afecta a la PADRE: cotizaciones_precio queda intacta.
--    Orden: primero la hija (idempotencia), despues el resto.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS api_precios_idempotencia;
DROP TABLE IF EXISTS api_precios_ticket;
DROP TABLE IF EXISTS api_precios_nonce_s2s;
DROP TABLE IF EXISTS api_precios_rate_limit;

COMMIT;

-- ---------------------------------------------------------------------------
-- 4) ROL
--    DROP OWNED BY revoca los GRANTs que se le otorgaron (USAGE en public, EXECUTE).
--    Sin esto, DROP ROLE falla con "role cannot be dropped because some objects
--    depend on it". El rol no es OWNER de nada (todo es de postgres), asi que
--    DROP OWNED BY no borra ningun objeto.
-- ---------------------------------------------------------------------------
DO $rol$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'vita_precios_api') THEN
    EXECUTE 'DROP OWNED BY vita_precios_api';
    EXECUTE 'DROP ROLE vita_precios_api';
    RAISE NOTICE 'rol vita_precios_api eliminado';
  ELSE
    RAISE NOTICE 'rol vita_precios_api no existia';
  END IF;
END
$rol$;

-- ---------------------------------------------------------------------------
-- 5) VERIFY DE ROLLBACK
-- ---------------------------------------------------------------------------
BEGIN;

CREATE TEMP TABLE _r (orden INT, check_id TEXT, esperado TEXT, obtenido TEXT, ok BOOLEAN) ON COMMIT DROP;

INSERT INTO _r SELECT 1, 'R01_sin_rol', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_roles WHERE rolname = 'vita_precios_api';

INSERT INTO _r SELECT 2, 'R02_sin_funciones_b4', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'api_precios_%';

INSERT INTO _r SELECT 3, 'R03_sin_tablas_b4', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_class
WHERE relnamespace = 'public'::regnamespace AND relname LIKE 'api_precios_%';

INSERT INTO _r SELECT 4, 'R04_sin_jobs_b4', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM cron.job WHERE jobname LIKE 'b4_%';

-- NO-REGRESION: B3 y B2A deben quedar EXACTAMENTE como antes.
INSERT INTO _r SELECT 5, 'R05_b3_13_funciones', '13', COUNT(*)::TEXT, COUNT(*) = 13
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%';

INSERT INTO _r
SELECT 6, 'R06_b3_fingerprint', '098f2fe7916e11ffa78cff37622b9064', fp,
       fp = '098f2fe7916e11ffa78cff37622b9064'
FROM (
  SELECT pg_catalog.md5(pg_catalog.string_agg(
           pg_catalog.md5(pg_catalog.replace(prosrc, pg_catalog.chr(13), '')),
           '' ORDER BY proname)) AS fp
  FROM pg_catalog.pg_proc
  WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%'
) x;

INSERT INTO _r SELECT 7, 'R07_b2a_7_tablas', '7', COUNT(*)::TEXT, COUNT(*) = 7
FROM pg_catalog.pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
  AND c.relname IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia',
                    'noches_alta_demanda','overrides_precio','cotizaciones_precio','precios_auditoria');

INSERT INTO _r SELECT 8, 'R08_b2b_32_tarifas', '32', COUNT(*)::TEXT, COUNT(*) = 32
FROM tarifas_motor WHERE vigente_hasta IS NULL;

INSERT INTO _r SELECT 9, 'R09_temporadas_8', '8', COUNT(*)::TEXT, COUNT(*) = 8
FROM temporada_vigencia;

-- cotizaciones_precio NO fue tocada por el DROP de la tabla hija
INSERT INTO _r SELECT 10, 'R10_cotizaciones_intacta', 'existe', 'existe',
       EXISTS (SELECT 1 FROM pg_catalog.pg_class
                WHERE relnamespace = 'public'::regnamespace AND relname = 'cotizaciones_precio');

SELECT check_id, esperado, obtenido,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM _r ORDER BY orden;

SELECT COUNT(*) FILTER (WHERE ok)     AS pass,
       COUNT(*) FILTER (WHERE NOT ok) AS fail,
       CASE WHEN COUNT(*) FILTER (WHERE NOT ok) = 0
            THEN 'ROLLBACK B4-0A OK' ELSE 'ROLLBACK B4-0A CON FALLAS' END AS veredicto
FROM _r;

COMMIT;
