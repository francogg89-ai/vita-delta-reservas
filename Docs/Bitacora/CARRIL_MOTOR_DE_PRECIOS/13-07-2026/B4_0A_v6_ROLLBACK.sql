-- ============================================================================
-- B4_0A_v6_ROLLBACK.sql   (v6 -- post-auditoria 6)
--
-- ROLLBACK DE LOS OBJETOS DE B4, CON HARDENING DE B3 PERSISTENTE.
--
-- NO deja la base "exactamente como estaba". Elimina todo lo que B4-0A creo:
--   4 jobs pg_cron | 19 funciones | 4 tablas | el schema precios_api | el rol
-- y CONSERVA, deliberadamente, UNA SOLA COSA:
--
--   el REVOKE defensivo de la seccion 9.bis sobre las 13 precios_*.
--
-- Por que se conserva: ese REVOKE deja al motor B3 owner-only, que es el estado
-- CORRECTO segun el propio B3. Revertirlo devolveria EXECUTE a PUBLIC y reabriria
-- el agujero (cualquier rol que herede de PUBLIC podria llamar al motor directo).
-- Si B3 ya lo tenia aplicado, el REVOKE fue no-op y no hay nada que revertir.
-- No altera prosrc: el fingerprint de B3 sigue intacto.
--
-- LO QUE ESTE ROLLBACK **NO** TOCA:
--   pg_default_acl. B4-0A no aplica hardening global de default privileges, asi
--   que no hay nada de eso que revertir. Este script no lo aplica ni lo deshace,
--   y su VERIFY no lo mira: seria mezclar alcances.
--
-- GATE TEST-ONLY: la PRIMERA operacion exige configuracion_general('ambiente')='test'.
-- Si falta la tabla, falta la clave, o el valor no es 'test' -> aborta ANTES de
-- tocar cron, funciones, tablas, schema o rol.
--
-- IDEMPOTENTE: corre aunque B4-0A haya fallado a la mitad, y aunque pg_cron no
-- exista. Termina con un VERIFY de rollback.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0) GATE ANTI-AMBIENTE -- PRIMERA OPERACION. Antes de mutar nada.
--    Fuera de transaccion porque el paso 1 (cron) tambien lo esta; si el gate
--    falla, se levanta la excepcion y no se ejecuta ninguna sentencia posterior.
-- ---------------------------------------------------------------------------
DO $gate$
DECLARE v_amb TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'configuracion_general'
  ) THEN
    RAISE EXCEPTION 'ROLLBACK abortado: no existe public.configuracion_general. No se puede probar que esto sea TEST.';
  END IF;

  SELECT cg.valor INTO v_amb
    FROM public.configuracion_general cg
   WHERE cg.clave = 'ambiente';

  IF v_amb IS NULL THEN
    RAISE EXCEPTION 'ROLLBACK abortado: no existe la clave configuracion_general(ambiente).';
  END IF;
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ROLLBACK abortado: ambiente=% (esperado test). Artefacto TEST-only.', v_amb;
  END IF;
END
$gate$;

-- ---------------------------------------------------------------------------
-- 1) JOBS pg_cron -- por NOMBRE EXACTO. Nunca LIKE.
--    Tolerante a: pg_cron ausente, esquema cron ausente, job inexistente.
-- ---------------------------------------------------------------------------
DO $cron$
DECLARE
  c_jobs CONSTANT TEXT[] := ARRAY['b4_purga_ticket','b4_purga_nonce_s2s',
                                  'b4_purga_rate_limit','b4_purga_idempotencia'];
  v_job  TEXT;
  v_n    INTEGER := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron no instalado: no hay jobs que desprogramar. Continuo.';
    RETURN;
  END IF;

  -- firma EXACTA (pg_cron tiene sobrecargas: unschedule(bigint) ademas de (text))
  IF pg_catalog.to_regprocedure('cron.unschedule(text)') IS NULL THEN
    RAISE NOTICE 'no existe cron.unschedule(text) con esa firma. No desprogramo. Continuo.';
    RETURN;
  END IF;

  -- y la tabla: to_regclass devuelve NULL en vez de fallar
  IF pg_catalog.to_regclass('cron.job') IS NULL THEN
    RAISE NOTICE 'no existe cron.job. No desprogramo. Continuo.';
    RETURN;
  END IF;

  FOREACH v_job IN ARRAY c_jobs LOOP
    BEGIN
      IF EXISTS (SELECT 1 FROM cron.job j WHERE j.jobname = v_job) THEN
        PERFORM cron.unschedule(v_job);
        v_n := v_n + 1;
        RAISE NOTICE 'unschedule: %', v_job;
      ELSE
        RAISE NOTICE 'no existia: %', v_job;
      END IF;
    EXCEPTION WHEN undefined_table OR invalid_schema_name OR undefined_function THEN
      RAISE NOTICE 'cron no disponible al desprogramar %. Continuo.', v_job;
    END;
  END LOOP;

  RAISE NOTICE 'jobs desprogramados: %', v_n;
END
$cron$;

BEGIN;

-- ---------------------------------------------------------------------------
-- 2) FUNCIONES -- orden inverso de dependencias. IF EXISTS: idempotente.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS precios_api.api_precios_cotizar_exponer(UUID, JSONB);
DROP FUNCTION IF EXISTS precios_api.api_precios_congelar_exponer(UUID, JSONB, UUID);
DROP FUNCTION IF EXISTS precios_api.api_precios_obtener_exponer(UUID, UUID);
DROP FUNCTION IF EXISTS precios_api.api_precios_admitir(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID, UUID);
DROP FUNCTION IF EXISTS precios_api.api_precios_probe_ambiente();

DROP FUNCTION IF EXISTS precios_api.api_precios_cotizar_core(JSONB);
DROP FUNCTION IF EXISTS precios_api.api_precios_congelar_core(JSONB, UUID, TEXT);
DROP FUNCTION IF EXISTS precios_api.api_precios_obtener_core(UUID);

DROP FUNCTION IF EXISTS precios_api.api_precios_validar_payload(JSONB, TEXT);
DROP FUNCTION IF EXISTS precios_api.api_precios_validar_admision(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID, UUID);
DROP FUNCTION IF EXISTS precios_api.api_precios_rl_consumir(TEXT, TEXT, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS precios_api.api_precios_admision_leer(TEXT, UUID);
DROP FUNCTION IF EXISTS precios_api.api_precios_ticket_hash_v1(TEXT, TEXT, TEXT, JSONB, UUID, UUID);

DROP FUNCTION IF EXISTS precios_api.api_precios_ticket_purgar();
DROP FUNCTION IF EXISTS precios_api.api_precios_nonce_purgar();
DROP FUNCTION IF EXISTS precios_api.api_precios_rl_purgar();
DROP FUNCTION IF EXISTS precios_api.api_precios_idempotencia_purgar();

DROP FUNCTION IF EXISTS precios_api.api_precios_gate_ambiente();
DROP FUNCTION IF EXISTS precios_api.api_precios_guard_sesion();

-- ---------------------------------------------------------------------------
-- 3) TABLAS
--    api_precios_idempotencia tiene FK -> public.cotizaciones_precio ON DELETE
--    RESTRICT. Dropear la HIJA no toca a la PADRE. Orden: hija primero.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS precios_api.api_precios_idempotencia;
DROP TABLE IF EXISTS precios_api.api_precios_ticket;
DROP TABLE IF EXISTS precios_api.api_precios_nonce_s2s;
DROP TABLE IF EXISTS precios_api.api_precios_rate_limit;

-- ---------------------------------------------------------------------------
-- 4) SCHEMA DEDICADO
--    Sin CASCADE a proposito: si quedara algo adentro que B4-0A no creo, el DROP
--    falla y hay que mirarlo. Un CASCADE borraria en silencio objetos ajenos.
-- ---------------------------------------------------------------------------
DROP SCHEMA IF EXISTS precios_api;

-- ---------------------------------------------------------------------------
-- 5) ROL -- DENTRO DE LA MISMA TRANSACCION.
--
--    ANTES estaba despues del COMMIT: si el DROP SCHEMA fallaba (por un objeto
--    inesperado adentro), la transaccion revertia PERO el script seguia y
--    borraba el rol igual -> quedaban los objetos de B4 vivos y SIN dueno de
--    referencia. Estado peor que el de partida.
--
--    Ahora todo esta en la misma transaccion: si el DROP SCHEMA falla, se
--    revierte TODO y el rol PERMANECE. O se va todo junto, o no se va nada.
--
--    DROP OWNED BY revoca los GRANTs recibidos (USAGE en precios_api, los
--    EXECUTE). Sin eso, DROP ROLE falla por dependencias. El rol no es OWNER
--    de ningun objeto.
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

COMMIT;

-- ---------------------------------------------------------------------------
-- 6) VERIFY DE ROLLBACK
--    search_path con public: el fingerprint B2A usa conrelid::regclass::text,
--    cuyo texto depende del search_path (sin public, el cast falla).
-- ---------------------------------------------------------------------------
BEGIN;

SET LOCAL search_path = public, pg_catalog;

CREATE TEMP TABLE _r (orden NUMERIC, check_id TEXT, esperado TEXT, obtenido TEXT, ok BOOLEAN)
ON COMMIT DROP;

INSERT INTO _r SELECT 1, 'R01_sin_rol', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_roles WHERE rolname = 'vita_precios_api';

INSERT INTO _r SELECT 2, 'R02_sin_schema_precios_api', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_namespace WHERE nspname = 'precios_api';

INSERT INTO _r SELECT 3, 'R03_sin_funciones_b4', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('precios_api','public') AND p.proname LIKE 'api\_precios\_%';

-- todos los relkind
INSERT INTO _r SELECT 4, 'R04_sin_objetos_b4', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('precios_api','public') AND c.relname LIKE 'api\_precios\_%';

-- R05: jobs de B4. SIN referencia ESTATICA a cron.job.
--   MEDIDO: una consulta que nombra cron.job dentro de un CASE falla en PARSEO
--   con 42P01 (UndefinedTable) aunque la rama NUNCA se ejecute -- PostgreSQL
--   analiza toda la consulta antes de correrla. La promesa "este rollback corre
--   aunque pg_cron no exista" seria FALSA.
--   Solucion: to_regclass (devuelve NULL, no falla) + EXECUTE dinamico.
DO $r05$
DECLARE v_n INTEGER;
BEGIN
  IF pg_catalog.to_regclass('cron.job') IS NULL THEN
    INSERT INTO _r VALUES (5, 'R05_sin_jobs_b4', '0', '0 (cron.job no existe)', TRUE);
    RETURN;
  END IF;

  EXECUTE $q$ SELECT COUNT(*) FROM cron.job
               WHERE jobname IN ('b4_purga_ticket','b4_purga_nonce_s2s',
                                 'b4_purga_rate_limit','b4_purga_idempotencia') $q$
    INTO v_n;

  INSERT INTO _r VALUES (5, 'R05_sin_jobs_b4', '0', v_n::TEXT, v_n = 0);
EXCEPTION WHEN OTHERS THEN
  -- Un error INESPERADO es un FALLO, no un pase libre. Antes esto insertaba TRUE
  -- ("no evaluable"), lo que convertia cualquier error en PASS y enmascaraba jobs
  -- que hubieran quedado vivos. La matriz correcta es:
  --   cron.job ausente          -> PASS  (se resuelve arriba, con to_regclass)
  --   consulta OK, 0 jobs       -> PASS
  --   consulta OK, quedan jobs  -> FAIL
  --   error inesperado          -> FAIL  <- esto
  INSERT INTO _r VALUES (5, 'R05_sin_jobs_b4', '0',
                         'ERROR al evaluar cron.job: ' || SQLERRM, FALSE);
END
$r05$;

-- ---- NO-REGRESION ----
INSERT INTO _r SELECT 6, 'R06_b3_13_funciones', '13', COUNT(*)::TEXT, COUNT(*) = 13
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%';

INSERT INTO _r
SELECT 7, 'R07_b3_fingerprint_intacto', '098f2fe7916e11ffa78cff37622b9064', fp,
       fp = '098f2fe7916e11ffa78cff37622b9064'
FROM (SELECT pg_catalog.md5(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.replace(prosrc, pg_catalog.chr(13), '')),
               '' ORDER BY proname)) AS fp
      FROM pg_catalog.pg_proc
      WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%') x;

INSERT INTO _r SELECT 8, 'R08_b2a_7_tablas', '7', COUNT(*)::TEXT, COUNT(*) = 7
FROM pg_catalog.pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
  AND c.relname IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia',
                    'noches_alta_demanda','overrides_precio','cotizaciones_precio',
                    'precios_auditoria');

INSERT INTO _r SELECT 9, 'R09_b2b_32_tarifas', '32', COUNT(*)::TEXT, COUNT(*) = 32
FROM public.tarifas_motor WHERE vigente_hasta IS NULL;

INSERT INTO _r SELECT 10, 'R10_temporadas_8', '8', COUNT(*)::TEXT, COUNT(*) = 8
FROM public.temporada_vigencia;

-- ---- FINGERPRINTS DE UPSTREAM: la prueba de que B4 no toco B2A/B2B ----
-- Mismos algoritmos de B2A_VERIFY / B2B_VERIFY. El conteo no alcanza.
INSERT INTO _r
SELECT 10.1, 'R10a_b2a_estructural_intacto', 'da52a16c045689523a5f1f113f513a87', fp,
       fp = 'da52a16c045689523a5f1f113f513a87'
FROM (
  WITH cols AS (
    SELECT 'C|'||table_name||'|'||column_name||'|'||data_type||'|'||is_nullable||'|'||COALESCE(column_default,'') AS line
    FROM information_schema.columns
    WHERE table_name IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                         'overrides_precio','cotizaciones_precio','precios_auditoria')
       OR (table_name='cabanas'      AND column_name='perfil_tarifario')
       OR (table_name='reservas'     AND column_name IN ('precio_source','precio_motivo','precio_snapshot','capacidad_override','cotizacion_id'))
       OR (table_name='pre_reservas' AND column_name='cotizacion_id')),
  cons AS (
    SELECT 'K|'||conrelid::regclass::text||'|'||conname||'|'||pg_get_constraintdef(oid) AS line
    FROM pg_constraint
    WHERE conrelid::regclass::text IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                                       'overrides_precio','cotizaciones_precio','precios_auditoria')
       OR conname IN ('cabanas_perfil_tarifario_fkey','chk_reservas_precio_source',
                      'reservas_cotizacion_id_fkey','pre_reservas_cotizacion_id_fkey')),
  idx AS (
    SELECT 'I|'||tablename||'|'||indexname||'|'||indexdef AS line
    FROM pg_indexes
    WHERE tablename IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                        'overrides_precio','cotizaciones_precio','precios_auditoria')
       OR indexname='idx_paquetes_evento_id_evento'),
  todo AS (SELECT line FROM cols UNION ALL SELECT line FROM cons UNION ALL SELECT line FROM idx)
  SELECT md5(string_agg(line, E'\n' ORDER BY line)) AS fp FROM todo) x;

INSERT INTO _r
SELECT 10.2, 'R10b_b2b_datos_intacto', '6d1653748d68ee9b62aa20aba5f3333d', fp,
       fp = '6d1653748d68ee9b62aa20aba5f3333d'
FROM (
  WITH tar AS (
    SELECT 'T|'||perfil||'|'||temporada_clave||'|'||concepto||'|'||precio::TEXT AS line
    FROM tarifas_motor WHERE vigente_hasta IS NULL),
  tmp AS (
    SELECT 'S|'||temporada_clave||'|'||anio::TEXT||'|'||fecha_in::TEXT||'|'||fecha_out_excl::TEXT AS line
    FROM temporada_vigencia),
  todo AS (SELECT line FROM tar UNION ALL SELECT line FROM tmp)
  SELECT md5(string_agg(line, E'\n' ORDER BY line)) AS fp FROM todo) x;

INSERT INTO _r SELECT 11, 'R11_cotizaciones_precio_intacta', 'existe',
       CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_class
                          WHERE relnamespace = 'public'::regnamespace
                            AND relname = 'cotizaciones_precio')
            THEN 'existe' ELSE 'NO EXISTE' END,
       EXISTS (SELECT 1 FROM pg_catalog.pg_class
                WHERE relnamespace = 'public'::regnamespace
                  AND relname = 'cotizaciones_precio');

-- ---- EL UNICO HARDENING QUE SE CONSERVA (no es residuo: es lo correcto) ----
-- Solo 9.bis. B4-0A no aplica hardening global, asi que no hay mas nada que mirar.
INSERT INTO _r
SELECT 12, 'R12_b3_sigue_owner_only', '0 con EXECUTE a PUBLIC', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname LIKE 'precios\_%'
  AND pg_catalog.has_function_privilege('public', p.oid, 'EXECUTE');

SELECT check_id, esperado, obtenido,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM _r ORDER BY orden;

SELECT COUNT(*) FILTER (WHERE ok)     AS pass,
       COUNT(*) FILTER (WHERE NOT ok) AS fail,
       CASE WHEN COUNT(*) FILTER (WHERE NOT ok) = 0
            THEN 'ROLLBACK B4-0A OK (conserva SOLO el REVOKE owner-only de B3)'
            ELSE 'ROLLBACK B4-0A CON FALLAS' END AS veredicto
FROM _r;

COMMIT;
