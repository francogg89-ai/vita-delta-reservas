-- ============================================================================
-- B4_0A_v6_ROL_TABLAS_FUNCIONES.sql   (v6 -- post-auditoria 6)
-- Motor de Precios v2 -- Bloque B4 -- Fase 0A
-- Rol PG dedicado + schema dedicado + 4 tablas + 19 funciones + 4 jobs pg_cron.
-- TEST unicamente.
--
-- SCHEMA DEDICADO precios_api  (cambio estructural respecto de v2):
--   Todos los objetos de B4 (19 funciones + 4 tablas) viven en el schema
--   precios_api. El rol recibe USAGE EXPLICITO sobre precios_api.
--
--   ATENCION -- lo que SI conserva sobre public: el rol HEREDA el USAGE que el
--   pseudo-rol PUBLIC tiene sobre el schema public. B4-0A **no se lo quita** (eso
--   exige REVOKE USAGE ON SCHEMA public FROM PUBLIC, que es GLOBAL). Por lo tanto
--   PUEDE invocar funciones de public que tengan EXECUTE a PUBLIC.
--   Lo que NO puede: llamar al motor B3 (revocado en 1.ter), tocar una sola tabla
--   (cero grants), ni alcanzar un SECURITY DEFINER ajeno (gate 1.quater + D03).
--   La superficie residual la MIDE el VERIFY: D07 + Salida 3.
--   Motivo: en public, PostgreSQL concede EXECUTE a PUBLIC sobre funciones nuevas
--   por defecto; una migracion futura podria sumar una funcion ejecutable por el
--   rol sin tocar B4. Con el schema dedicado, una funcion nueva ejecutable por el
--   rol solo puede nacer si postgres la crea EN precios_api a proposito.
--   Las funciones internas schema-qualifican public.* y corren con la identidad
--   efectiva del entrypoint que las llama (postgres).
--   NOTA: el aislamiento TOTAL ('rol sin usage en public') exige ademas
--   REVOKE USAGE ON SCHEMA public FROM PUBLIC, que es una decision GLOBAL del
--   proyecto -> queda documentada en el runsheet como hardening opcional (nivel 2),
--   NO se aplica aca porque su impacto excede B4.
--
-- INSTALACION FRESH-ONLY. Aborta si existe cualquier residuo de B4.
-- Si hay residuos: correr B4_0A_v6_ROLLBACK.sql primero.
--
-- PREFLIGHT DEL UPSTREAM: antes de crear el rol, exige que B3/B2A/B2B esten
--   exactamente como se espera (13 funciones, fingerprint, 7 tablas, 32 tarifas,
--   8 temporadas continuas). Si algo no coincide, aborta antes de mutar.
--
-- TIEMPO: toda decision temporal de seguridad usa clock_timestamp(), NUNCA now().
--   now() = transaction_timestamp() queda CONGELADO al inicio de la transaccion.
--   VERIFICADO: una TXN2 abierta mientras el ticket vivia consume el ticket
--   DESPUES de su expiracion real si se compara contra now(). Explotable.
--
-- RATE LIMIT: la ventana se calcula UNA sola vez en api_precios_admitir y se pasa
--   a los dos consumos (global y sujeto). Sin esto, las dos llamadas podrian caer
--   en minutos distintos si clock_timestamp() cruza el borde entre ambas.
--
-- CONSUME el motor B3. NO lo modifica (salvo el REVOKE defensivo de 9.bis, que
-- refuerza su owner-only y no altera prosrc: el fingerprint queda intacto).
--
-- PASSWORD: este archivo NO crea ni contiene password. El rol nace NOLOGIN.
-- ============================================================================

BEGIN;

-- ===========================================================================
-- 0) GATE ANTI-AMBIENTE
-- ===========================================================================
DO $gate$
DECLARE v_amb TEXT;
BEGIN
  SELECT cg.valor INTO v_amb FROM public.configuracion_general cg WHERE cg.clave = 'ambiente';
  IF v_amb IS NULL THEN
    RAISE EXCEPTION 'B4-0A abortado: no existe configuracion_general(ambiente).';
  END IF;
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'B4-0A abortado: ambiente=% (esperado test). Artefacto TEST-only.', v_amb;
  END IF;
END
$gate$;

-- ===========================================================================
-- 0.bis) GATE ANTI-RESIDUOS -- FRESH-ONLY.
--   No reutiliza NADA silenciosamente. Si hay residuo, aborta y pide rollback.
--   Cubre TODOS los relkind: tabla, vista, matview, foreign table, secuencia,
--   indice, particionada.
-- ===========================================================================
DO $residuos$
DECLARE
  v_rol INTEGER;
  v_obj INTEGER;
  v_fun INTEGER;
  v_job INTEGER;
  v_det TEXT := '';
BEGIN
  SELECT COUNT(*) INTO v_rol FROM pg_catalog.pg_roles WHERE rolname = 'vita_precios_api';

  -- objetos B4 en el schema dedicado precios_api (si existe) Y por las dudas en
  -- public (por si una version previa los dejo ahi). Cualquiera de los dos = residuo.
  SELECT COUNT(*) INTO v_obj
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname IN ('precios_api','public')
     AND c.relname LIKE 'api\_precios\_%';

  SELECT COUNT(*) INTO v_fun
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('precios_api','public')
     AND p.proname LIKE 'api\_precios\_%';

  -- el propio schema precios_api es un residuo si ya existe
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'precios_api') THEN
    v_det := v_det || ' schema_precios_api=1;';
  END IF;

  BEGIN
    SELECT COUNT(*) INTO v_job
      FROM cron.job j
     WHERE j.jobname IN ('b4_purga_ticket','b4_purga_nonce_s2s',
                         'b4_purga_rate_limit','b4_purga_idempotencia');
  EXCEPTION WHEN undefined_table OR invalid_schema_name THEN
    v_job := 0;   -- si cron.job no existe, el preflight de 0.ter frena igual
  END;

  IF v_rol > 0 THEN v_det := v_det || ' rol=1;'; END IF;
  IF v_obj > 0 THEN v_det := v_det || ' objetos_api_precios=' || v_obj || ';'; END IF;
  IF v_fun > 0 THEN v_det := v_det || ' funciones_api_precios=' || v_fun || ';'; END IF;
  IF v_job > 0 THEN v_det := v_det || ' jobs_b4=' || v_job || ';'; END IF;

  IF v_det <> '' THEN
    RAISE EXCEPTION 'B4-0A abortado: instalacion FRESH-ONLY y hay residuos ->%. Corre B4_0A_v6_ROLLBACK.sql primero.', v_det;
  END IF;
END
$residuos$;

-- ===========================================================================
-- 0.ter) PREFLIGHT pg_cron -- por FIRMA EXACTA, no por nombre.
--   pg_cron trae sobrecargas (p.ej. unschedule(bigint) ademas de unschedule(text)).
--   Buscar "cualquier proname='schedule'" NO prueba que exista LA firma que B4-0A
--   va a invocar. to_regprocedure resuelve la firma exacta o devuelve NULL.
--   Si falta cualquier pieza, aborta ANTES de crear un solo objeto.
-- ===========================================================================
DO $preflight$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron') THEN
    RAISE EXCEPTION 'B4-0A abortado: la extension pg_cron no esta instalada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'cron' AND c.relname = 'job'
  ) THEN
    RAISE EXCEPTION 'B4-0A abortado: no existe la tabla cron.job.';
  END IF;

  -- firmas EXACTAS de las dos funciones que se usan (schedule aca, unschedule en el rollback)
  IF pg_catalog.to_regprocedure('cron.schedule(text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'B4-0A abortado: no existe cron.schedule(text,text,text) con esa firma exacta.';
  END IF;

  IF pg_catalog.to_regprocedure('cron.unschedule(text)') IS NULL THEN
    RAISE EXCEPTION 'B4-0A abortado: no existe cron.unschedule(text) con esa firma exacta (la necesita el rollback).';
  END IF;
END
$preflight$;

-- ===========================================================================
-- 0.quater) PREFLIGHT DEL UPSTREAM -- POR FINGERPRINT, no por conteo.
--
--   Los conteos (13 funciones, 7 tablas, 32 tarifas, 8 temporadas) se CONSERVAN,
--   pero como DIAGNOSTICO: dicen que fallo, no alcanzan para probar que el motor
--   es el esperado. La prueba son los tres fingerprints canonicos:
--
--     B2A estructural  da52a16c045689523a5f1f113f513a87   (124 lineas)
--     B2B datos        6d1653748d68ee9b62aa20aba5f3333d   (40 lineas)
--     B3 normalizado   098f2fe7916e11ffa78cff37622b9064
--
--   Los algoritmos de B2A y B2B son LOS MISMOS de B2A_VERIFY.sql / B2B_VERIFY.sql,
--   reproducidos literalmente. Si algo no coincide, aborta antes de mutar.
--
--   SEARCH_PATH: el fingerprint B2A usa conrelid::regclass::text, cuyo resultado
--   DEPENDE del search_path (con public -> 'tarifas_motor'; sin public -> el cast
--   falla con UndefinedTable). Se fija explicitamente para que el hash reproduzca
--   el que produjo B2A_VERIFY en el SQL Editor. VERIFICADO en harness.
-- ===========================================================================
SET LOCAL search_path = public, pg_catalog;

DO $upstream$
DECLARE
  v_n_b3    INTEGER;
  v_n_b2a   INTEGER;
  v_n_tar   INTEGER;
  v_n_temp  INTEGER;
  v_gaps    INTEGER;
  v_fp_b3   TEXT;
  v_fp_b2a  TEXT;
  v_fp_b2b  TEXT;
  v_ln_b2a  INTEGER;
  v_ln_b2b  INTEGER;
BEGIN
  -- ---- DIAGNOSTICO: conteos (no sustituyen al fingerprint) ----
  SELECT COUNT(*) INTO v_n_b3
    FROM pg_catalog.pg_proc
   WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%';
  IF v_n_b3 <> 13 THEN
    RAISE EXCEPTION 'B4-0A abortado [diag]: B3 tiene % funciones precios_* (esperado 13).', v_n_b3;
  END IF;

  SELECT COUNT(*) INTO v_n_b2a
    FROM pg_catalog.pg_class c
   WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
     AND c.relname IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia',
                       'noches_alta_demanda','overrides_precio','cotizaciones_precio',
                       'precios_auditoria');
  IF v_n_b2a <> 7 THEN
    RAISE EXCEPTION 'B4-0A abortado [diag]: B2A tiene %/7 tablas.', v_n_b2a;
  END IF;

  SELECT COUNT(*) INTO v_n_tar FROM public.tarifas_motor WHERE vigente_hasta IS NULL;
  IF v_n_tar <> 32 THEN
    RAISE EXCEPTION 'B4-0A abortado [diag]: % tarifas vigentes (esperado 32).', v_n_tar;
  END IF;

  SELECT COUNT(*) INTO v_n_temp FROM public.temporada_vigencia;
  IF v_n_temp <> 8 THEN
    RAISE EXCEPTION 'B4-0A abortado [diag]: % temporadas (esperado 8).', v_n_temp;
  END IF;

  SELECT COUNT(*) INTO v_gaps
  FROM (SELECT fecha_in, LAG(fecha_out_excl) OVER (ORDER BY fecha_in) AS prev_out
          FROM public.temporada_vigencia) t
  WHERE prev_out IS NOT NULL AND prev_out IS DISTINCT FROM fecha_in;
  IF v_gaps > 0 THEN
    RAISE EXCEPTION 'B4-0A abortado [diag]: % discontinuidades en temporadas.', v_gaps;
  END IF;

  -- ---- PRUEBA 1: fingerprint B3 normalizado (CRLF -> LF) ----
  SELECT pg_catalog.md5(pg_catalog.string_agg(
           pg_catalog.md5(pg_catalog.replace(prosrc, pg_catalog.chr(13), '')),
           '' ORDER BY proname))
    INTO v_fp_b3
    FROM pg_catalog.pg_proc
   WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%';

  IF v_fp_b3 IS DISTINCT FROM '098f2fe7916e11ffa78cff37622b9064' THEN
    RAISE EXCEPTION 'B4-0A abortado: fingerprint B3 = % (esperado 098f2fe7916e11ffa78cff37622b9064).', v_fp_b3;
  END IF;

  -- ---- PRUEBA 2: fingerprint estructural B2A (algoritmo de B2A_VERIFY) ----
  WITH cols AS (
    SELECT 'C|'||table_name||'|'||column_name||'|'||data_type||'|'||is_nullable||'|'||COALESCE(column_default,'') AS line
    FROM information_schema.columns
    WHERE table_name IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                         'overrides_precio','cotizaciones_precio','precios_auditoria')
       OR (table_name='cabanas'      AND column_name='perfil_tarifario')
       OR (table_name='reservas'     AND column_name IN ('precio_source','precio_motivo','precio_snapshot','capacidad_override','cotizacion_id'))
       OR (table_name='pre_reservas' AND column_name='cotizacion_id')
  ),
  cons AS (
    SELECT 'K|'||conrelid::regclass::text||'|'||conname||'|'||pg_get_constraintdef(oid) AS line
    FROM pg_constraint
    WHERE conrelid::regclass::text IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                                       'overrides_precio','cotizaciones_precio','precios_auditoria')
       OR conname IN ('cabanas_perfil_tarifario_fkey','chk_reservas_precio_source',
                      'reservas_cotizacion_id_fkey','pre_reservas_cotizacion_id_fkey')
  ),
  idx AS (
    SELECT 'I|'||tablename||'|'||indexname||'|'||indexdef AS line
    FROM pg_indexes
    WHERE tablename IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                        'overrides_precio','cotizaciones_precio','precios_auditoria')
       OR indexname='idx_paquetes_evento_id_evento'
  ),
  todo AS (SELECT line FROM cols UNION ALL SELECT line FROM cons UNION ALL SELECT line FROM idx)
  SELECT md5(string_agg(line, E'\n' ORDER BY line)), COUNT(*)
    INTO v_fp_b2a, v_ln_b2a
  FROM todo;

  IF v_fp_b2a IS DISTINCT FROM 'da52a16c045689523a5f1f113f513a87' THEN
    RAISE EXCEPTION 'B4-0A abortado: fingerprint estructural B2A = % (% lineas; esperado da52a16c045689523a5f1f113f513a87, 124 lineas).',
      v_fp_b2a, v_ln_b2a;
  END IF;

  -- ---- PRUEBA 3: fingerprint de datos B2B (algoritmo de B2B_VERIFY) ----
  WITH tar AS (
    SELECT 'T|'||perfil||'|'||temporada_clave||'|'||concepto||'|'||precio::TEXT AS line
    FROM tarifas_motor WHERE vigente_hasta IS NULL
  ),
  tmp AS (
    SELECT 'S|'||temporada_clave||'|'||anio::TEXT||'|'||fecha_in::TEXT||'|'||fecha_out_excl::TEXT AS line
    FROM temporada_vigencia
  ),
  todo AS (SELECT line FROM tar UNION ALL SELECT line FROM tmp)
  SELECT md5(string_agg(line, E'\n' ORDER BY line)), COUNT(*)
    INTO v_fp_b2b, v_ln_b2b
  FROM todo;

  IF v_fp_b2b IS DISTINCT FROM '6d1653748d68ee9b62aa20aba5f3333d' THEN
    RAISE EXCEPTION 'B4-0A abortado: fingerprint de datos B2B = % (% lineas; esperado 6d1653748d68ee9b62aa20aba5f3333d, 40 lineas).',
      v_fp_b2b, v_ln_b2b;
  END IF;

  RAISE NOTICE 'Preflight upstream OK -- B2A=% B2B=% B3=%', v_fp_b2a, v_fp_b2b, v_fp_b3;
END
$upstream$;

-- ===========================================================================
-- 1) ROL DEDICADO + SCHEMA DEDICADO
-- ===========================================================================
CREATE ROLE vita_precios_api NOLOGIN;

-- Fallback de sesion para la conexion legitima de la Edge.
-- NO es cota dura: un caller con la credencial puede hacer SET statement_timeout = 0.
-- La defensa server-side real son las cotas estructurales del wrapper.
ALTER ROLE vita_precios_api SET statement_timeout = '5s';
ALTER ROLE vita_precios_api SET lock_timeout      = '2s';

-- SCHEMA DEDICADO. owner=postgres. Cerrado a PUBLIC. USAGE solo para el rol.
-- Aisla los entrypoints de B4 de los default privileges globales de public.
CREATE SCHEMA precios_api AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA precios_api FROM PUBLIC;
GRANT USAGE ON SCHEMA precios_api TO vita_precios_api;   -- USAGE, no CREATE

-- El rol NO recibe un GRANT USAGE sobre public: no lo necesita, sus entrypoints estan en
-- precios_api, y esos 5 entrypoints (SECURITY DEFINER, owner postgres) alcanzan
-- public.* schema-qualified corriendo como su owner, no como el rol.
-- (Nota: el rol puede conservar el USAGE que herede del pseudo-rol PUBLIC sobre
--  public; eliminarlo del todo es el hardening nivel 2 del runsheet, global.)

-- ---------------------------------------------------------------------------
-- 1.bis) CHECKS DUROS DE CREACION -- el rol no debe poder crear NADA.
--
--   Dos superficies distintas, las dos heredables de PUBLIC:
--     a) CREATE sobre el SCHEMA public -> podria plantar funciones o tablas ahi.
--     b) CREATE sobre la BASE          -> podria plantar SCHEMAS propios, y
--        dentro de un schema propio es owner: crea lo que quiera.
--
--   Un REVOKE dirigido al rol NO arregla un permiso heredado de PUBLIC (medido:
--   REVOKE ... FROM vita_precios_api deja has_*_privilege en true si viene de
--   PUBLIC). Por eso se COMPRUEBA EL EFECTIVO, no se asume. Si alguno da true,
--   aborta TODA la transaccion antes de crear un solo objeto de B4.
-- ---------------------------------------------------------------------------
DO $create_gate$
BEGIN
  IF pg_catalog.has_schema_privilege('vita_precios_api', 'public', 'CREATE') THEN
    RAISE EXCEPTION
      'B4-0A abortado: el rol tiene CREATE sobre el schema public (heredado de PUBLIC). '
      'Corregir con: REVOKE CREATE ON SCHEMA public FROM PUBLIC; y volver a correr.';
  END IF;

  IF pg_catalog.has_database_privilege('vita_precios_api',
                                       pg_catalog.current_database(), 'CREATE') THEN
    RAISE EXCEPTION
      'B4-0A abortado: el rol tiene CREATE sobre la base % (podria crear schemas propios). '
      'Corregir con: REVOKE CREATE ON DATABASE % FROM PUBLIC; y volver a correr.',
      pg_catalog.current_database(), pg_catalog.current_database();
  END IF;
END
$create_gate$;

-- ---------------------------------------------------------------------------
-- 1.ter) DEFENSA EN PROFUNDIDAD SOBRE EL MOTOR B3
--
-- El rol HEREDA de PUBLIC. Si alguna de las 13 precios_* conservara EXECUTE a
-- PUBLIC, vita_precios_api lo heredaria y podria llamar al motor DIRECTAMENTE,
-- salteando la admision entera (cuota + nonce + ticket). Un REVOKE dirigido al
-- rol NO alcanza: hay que revocarlo de PUBLIC.
--
-- SE ADELANTA (antes era 9.bis, al final): el gate ACL de 1.quater mide la
-- superficie del rol, y las 13 precios_* no deben contar. Primero se cierran,
-- despues se mide.
-- IDEMPOTENTE: B3 ya deberia tenerlo. Si cambia algo, es que habia un agujero.
-- NO altera prosrc -> el fingerprint de B3 queda INTACTO (se calcula sobre el
-- cuerpo, no sobre la ACL). Este REVOKE NO se revierte en el rollback.
-- ---------------------------------------------------------------------------
DO $b3$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_catalog.pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND p.proname LIKE 'precios\_%'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || r.sig ||
            ' FROM PUBLIC, anon, authenticated, service_role, vita_precios_api';
  END LOOP;
END
$b3$;

-- ---------------------------------------------------------------------------
-- 1.quater) GATE ACL PRECOMMIT -- la superficie del rol, ANTES de crear objetos.
--
--   No esperar al VERIFY posterior para descubrir una incompatibilidad del estado
--   REAL de TEST. Si el rol ya nace con superficie ajena, B4-0A no debe instalar
--   nada: aborta y dice EXACTAMENTE que encontro.
--
--   Se mide la superficie EFECTIVA (invocable de verdad):
--       has_schema_privilege(rol, schema, 'USAGE')
--     + has_function_privilege(rol, funcion, 'EXECUTE')
--   Una funcion con EXECUTE en un schema sin USAGE es INALCANZABLE: no cuenta.
--
--   En este punto precios_api existe pero esta VACIO -> todo lo que aparezca es
--   ajeno a B4 por definicion.
-- ---------------------------------------------------------------------------
DO $acl_gate$
DECLARE
  v_n   INTEGER;
  v_det TEXT;
BEGIN
  -- (a) cero SECURITY DEFINER externo REALMENTE INVOCABLE
  SELECT COUNT(*), pg_catalog.string_agg(x.sig, ', ' ORDER BY x.sig)
    INTO v_n, v_det
  FROM (
    SELECT n.nspname || '.' || p.proname || '(' ||
           COALESCE(pg_catalog.pg_get_function_identity_arguments(p.oid), '') || ')' AS sig
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prosecdef
      AND n.nspname NOT IN ('pg_catalog','information_schema')
      AND n.nspname NOT LIKE 'pg\_toast%'
      AND n.nspname NOT LIKE 'pg\_temp%'
      AND pg_catalog.has_schema_privilege('vita_precios_api', n.oid, 'USAGE')
      AND pg_catalog.has_function_privilege('vita_precios_api', p.oid, 'EXECUTE')
    LIMIT 20
  ) x;

  IF v_n > 0 THEN
    RAISE EXCEPTION
      'B4-0A abortado: el rol puede INVOCAR % funcion(es) SECURITY DEFINER ajena(s) a B4 -> escalada de privilegios. '
      'Primeras: %. Revocalas de PUBLIC (REVOKE EXECUTE ON FUNCTION ... FROM PUBLIC) y volve a correr.',
      v_n, v_det;
  END IF;

  -- (b) cero privilegios de TABLA en toda la base
  SELECT COUNT(*) INTO v_n
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),
                     ('TRUNCATE'),('REFERENCES'),('TRIGGER')) AS pr(priv)
  WHERE c.relkind IN ('r','p','v','m','f')
    AND n.nspname NOT IN ('pg_catalog','information_schema')
    AND n.nspname NOT LIKE 'pg\_%'
    AND pg_catalog.has_table_privilege('vita_precios_api', c.oid, pr.priv);

  IF v_n > 0 THEN
    RAISE EXCEPTION
      'B4-0A abortado: el rol tiene % privilegio(s) de TABLA. Debe tener CERO: escribe solo via SECURITY DEFINER.', v_n;
  END IF;

  -- (c) cero privilegios de SECUENCIA
  SELECT COUNT(*) INTO v_n
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN (VALUES ('USAGE'),('SELECT'),('UPDATE')) AS pr(priv)
  WHERE c.relkind = 'S'
    AND n.nspname NOT IN ('pg_catalog','information_schema')
    AND n.nspname NOT LIKE 'pg\_%'
    AND pg_catalog.has_sequence_privilege('vita_precios_api', c.oid, pr.priv);

  IF v_n > 0 THEN
    RAISE EXCEPTION
      'B4-0A abortado: el rol tiene % privilegio(s) de SECUENCIA. Debe tener CERO.', v_n;
  END IF;

  RAISE NOTICE 'Gate ACL precommit OK -- cero SECDEF invocable ajeno, cero tablas, cero secuencias.';
END
$acl_gate$;

-- ===========================================================================
-- 2) TABLAS  (4).  CERO secuencias.  DDL schema-qualified. Fresh-only.
-- ===========================================================================

CREATE TABLE precios_api.api_precios_rate_limit (
  scope   TEXT        NOT NULL,
  sujeto  TEXT        NOT NULL,
  ventana TIMESTAMPTZ NOT NULL,
  n       INTEGER     NOT NULL,
  CONSTRAINT pk_api_precios_rate_limit PRIMARY KEY (scope, sujeto, ventana),
  CONSTRAINT chk_rl_n CHECK (n >= 1)
);

-- LEDGER DE ADMISION (era: tabla de nonces).
--
--   Resuelve la RESPUESTA PERDIDA de TXN1: si PostgreSQL commitea pero la Edge
--   pierde la respuesta (timeout de red, crash, pooler), el ticket existe y el
--   nonce quedo consumido, pero la Edge NO conoce el ticket_id. El rol no puede
--   leer la tabla de tickets. Sin ledger, ese estado es AMBIGUO E IRRECUPERABLE.
--
--   Con ledger, el nonce ES la identidad durable de la admision:
--     (client_id, nonce)  -> admission_hash  (el binding)
--                         -> ticket_id       (el ticket que produjo)
--
--   Reintentar con el MISMO nonce y el MISMO binding devuelve el MISMO ticket_id,
--   sin volver a cobrar cuota y sin volver a consumir nonce.
--   Con binding distinto -> nonce_replay (conflicto real).
--
--   admission_hash ES el request_hash del ticket (mismo api_precios_ticket_hash_v1):
--   un solo canon, no dos. NO incluye correlation_id: un reintento con otro
--   correlation_id sigue siendo el MISMO request logico.
CREATE TABLE precios_api.api_precios_nonce_s2s (
  client_id      TEXT        NOT NULL,
  nonce          UUID        NOT NULL,
  admission_hash TEXT        NOT NULL,
  ticket_id      UUID        NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CONSTRAINT pk_api_precios_nonce_s2s PRIMARY KEY (client_id, nonce),
  -- el hash es sha256 en hex: 64 caracteres [0-9a-f]. Si algun dia alguien mete
  -- otra cosa (un canon distinto, un truncado, un texto), el INSERT revienta aca
  -- en vez de romper el binding del recovery en silencio.
  CONSTRAINT chk_nonce_s2s_admission_hash CHECK (admission_hash ~ '^[0-9a-f]{64}$')
);

-- SIN FOREIGN KEY a api_precios_ticket, a proposito: las purgas son INDEPENDIENTES
-- (ticket ~10,5 min, ledger ~15 min). Una FK impediria purgar el ticket mientras el
-- ledger lo referencia, o forzaria un ON DELETE que destruiria la evidencia del
-- recovery. La consistencia se verifica, no se impone: VERIFY G07/G08/G09.

-- superficie/sujeto con CHECK S2S-only: F3 aplicada ESTRUCTURALMENTE.
CREATE TABLE precios_api.api_precios_ticket (
  ticket_id      UUID        NOT NULL,
  accion         TEXT        NOT NULL,
  superficie     TEXT        NOT NULL,
  sujeto         TEXT        NOT NULL,
  request_hash   TEXT        NOT NULL,
  correlation_id UUID        NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  expires_at     TIMESTAMPTZ NOT NULL,
  consumed_at    TIMESTAMPTZ,
  CONSTRAINT pk_api_precios_ticket   PRIMARY KEY (ticket_id),
  CONSTRAINT chk_ticket_accion       CHECK (accion IN ('cotizar','congelar','obtener')),
  CONSTRAINT chk_ticket_superficie   CHECK (superficie = 's2s'),
  CONSTRAINT chk_ticket_sujeto       CHECK (sujeto = 'whatsapp'),
  CONSTRAINT chk_ticket_hash         CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT chk_ticket_vigencia     CHECK (expires_at > created_at),
  CONSTRAINT chk_ticket_consumo      CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);

-- SOLO congelamientos EXITOSOS. cotizacion_id NOT NULL: la fila existe si hubo escritura.
CREATE TABLE precios_api.api_precios_idempotencia (
  scope                   TEXT        NOT NULL,
  idempotency_key         UUID        NOT NULL,
  canon_hash              TEXT        NOT NULL,
  cotizacion_id           UUID        NOT NULL,
  resultado_motor_privado JSONB       NOT NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CONSTRAINT pk_api_precios_idempotencia PRIMARY KEY (scope, idempotency_key),
  CONSTRAINT fk_api_precios_idem_cotizacion
    FOREIGN KEY (cotizacion_id)
    REFERENCES public.cotizaciones_precio(cotizacion_id) ON DELETE RESTRICT,
  CONSTRAINT chk_idem_scope CHECK (scope LIKE 'precios.congelar:%'),
  CONSTRAINT chk_idem_hash  CHECK (canon_hash ~ '^[0-9a-f]{64}$')
);

-- Indices que sostienen las 4 purgas. Cada purga filtra por una columna temporal;
-- sin indice, cada corrida es un seq scan. Con volumenes chicos el costo es bajo,
-- pero el indice de expira/created ya existe para el ticket y la idempotencia, y
-- se agregan los dos que faltaban para que las 4 purgas usen indice.
CREATE INDEX idx_api_precios_ticket_expira ON precios_api.api_precios_ticket (expires_at);
CREATE INDEX idx_api_precios_idem_created  ON precios_api.api_precios_idempotencia (created_at);
CREATE INDEX idx_api_precios_nonce_created ON precios_api.api_precios_nonce_s2s (created_at);
CREATE INDEX idx_api_precios_rl_ventana    ON precios_api.api_precios_rate_limit (ventana);

-- El rol NO tiene privilegios de tabla. Las escribe el entrypoint SECURITY DEFINER,
-- que corre como postgres; los helpers INVOKER heredan esa identidad efectiva.
REVOKE ALL ON TABLE
  precios_api.api_precios_rate_limit, precios_api.api_precios_nonce_s2s,
  precios_api.api_precios_ticket, precios_api.api_precios_idempotencia
  FROM PUBLIC, anon, authenticated, service_role, vita_precios_api;

-- ===========================================================================
-- 3) HELPERS OWNER-ONLY
-- ===========================================================================

-- 3.1 D3 -- GUARD DE SESION LIMPIA. Primera sentencia de admitir, *_exponer y *_core.
--     Protege a B3, que NO se puede modificar: tiene search_path sin pg_temp y
--     referencias sin schema-qualify -> una relacion temporal homonima lo envenena
--     aun llamado desde un entrypoint SECURITY DEFINER (verificado).
--     pg_class OR pg_type: pg_class es ciego a ENUM/DOMAIN/RANGE/MULTIRANGE
--     (typrelid=0); pg_type es ciego a TEMP SEQUENCE. Hacen falta los dos.
--     DISCARD ALL limpia AMBOS -> sin falso positivo permanente.
CREATE FUNCTION precios_api.api_precios_guard_sesion()
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
BEGIN
  IF pg_catalog.pg_my_temp_schema() <> 0
     AND (
       EXISTS (SELECT 1 FROM pg_catalog.pg_class c
                WHERE c.relnamespace = pg_catalog.pg_my_temp_schema())
       OR
       EXISTS (SELECT 1 FROM pg_catalog.pg_type t
                WHERE t.typnamespace = pg_catalog.pg_my_temp_schema())
     )
  THEN
    RAISE EXCEPTION 'sesion_contaminada' USING ERRCODE = 'VDT01';
  END IF;
END
$$;

-- 3.2 gate de ambiente
CREATE FUNCTION precios_api.api_precios_gate_ambiente()
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
DECLARE v_amb TEXT;
BEGIN
  SELECT cg.valor INTO v_amb
    FROM public.configuracion_general cg
   WHERE cg.clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ambiente_no_admitido' USING ERRCODE = 'VDT03';
  END IF;
END
$$;

-- 3.3 CANON DEL TICKET -- una sola implementacion, 4 llamadores.
--     jsonb::text es canonico -> el hash de TXN1 (payload TEXT->jsonb) coincide
--     con el de TXN2 (payload JSONB). Verificado.
CREATE FUNCTION precios_api.api_precios_ticket_hash_v1(
  p_accion        TEXT,
  p_superficie    TEXT,
  p_sujeto        TEXT,
  p_payload       JSONB,
  p_idem_key      UUID,
  p_cotizacion_id UUID
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
  SELECT pg_catalog.encode(
           pg_catalog.sha256(
             (pg_catalog.jsonb_build_object(
                'v',             'b4tk1',
                'accion',        p_accion,
                'superficie',    p_superficie,
                'sujeto',        p_sujeto,
                'payload',       COALESCE(p_payload, 'null'::jsonb),
                'idem_key',      COALESCE(p_idem_key::TEXT, ''),
                'cotizacion_id', COALESCE(p_cotizacion_id::TEXT, '')
              ))::TEXT::BYTEA
           ), 'hex')
$$;

-- 3.4 RATE LIMIT ATOMICO. El limite se deriva del scope DENTRO de SQL.
--     ON CONFLICT DO UPDATE ... WHERE n < limite -> sin fila en RETURNING = DENEGADO.
--     Verificado: 100 concurrentes / limite 60 -> 60 admitidas, contador final 60.
--     Los scopes _web quedan DEFINIDOS pero NO alcanzables: validar_admision
--     rechaza superficie <> 's2s' (F3).
--     LA VENTANA VIENE POR PARAMETRO: admitir la calcula UNA vez y la pasa a los
--     dos consumos (global y sujeto), para que caigan en el MISMO minuto aunque
--     clock_timestamp() cruce el borde entre ambas llamadas.
CREATE FUNCTION precios_api.api_precios_rl_consumir(p_scope TEXT, p_sujeto TEXT, p_ventana TIMESTAMPTZ)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
DECLARE
  v_lim INTEGER;
  v_n   INTEGER;
BEGIN
  v_lim := CASE p_scope
             -- ---- CUOTA DE INTENTOS: se cobra en TODA invocacion de admitir ----
             --   (admision nueva, recovery y replay-con-binding-distinto)
             --   Es la unica cota que frena un REPLAY MASIVO: el recovery no
             --   consume cuota logica, asi que sin esta cubeta un atacante podria
             --   repetir la misma solicitud valida indefinidamente (parse + SHA-256
             --   + SELECT + conexion) sin tocar ningun limite.
             --   Dimensionado: por encima de la suma de las logicas + margen de
             --   reintentos legitimos.
             --     global: 600 + 120 + 1200 = 1920  -> 2400 (+25%)
             --     s2s   : 300 +  60 +  600 =  960  -> 1200 (+25%)
             --     web   :  60 +  10 +  120 =  190  ->  240 (+26%)
             WHEN 'admision_intento_global' THEN 2400
             WHEN 'admision_intento_s2s'    THEN 1200
             WHEN 'admision_intento_web'    THEN 240
             -- ---- CUOTA LOGICA: solo al CREAR una admision nueva ----
             WHEN 'cotizar_global'  THEN 600
             WHEN 'congelar_global' THEN 120
             WHEN 'obtener_global'  THEN 1200
             WHEN 'cotizar_s2s'     THEN 300
             WHEN 'congelar_s2s'    THEN 60
             WHEN 'obtener_s2s'     THEN 600
             WHEN 'cotizar_web'     THEN 60
             WHEN 'congelar_web'    THEN 10
             WHEN 'obtener_web'     THEN 120
             ELSE NULL
           END;

  IF v_lim IS NULL THEN
    RAISE EXCEPTION 'scope_desconocido' USING ERRCODE = 'VDT02';
  END IF;

  INSERT INTO precios_api.api_precios_rate_limit AS rl (scope, sujeto, ventana, n)
  VALUES (p_scope, p_sujeto, p_ventana, 1)
  ON CONFLICT ON CONSTRAINT pk_api_precios_rate_limit DO UPDATE
     SET n = rl.n + 1
   WHERE rl.n < v_lim
  RETURNING rl.n INTO v_n;

  RETURN v_n IS NOT NULL;
END
$$;

-- 3.5 NONCE S2S -- consumo unico. unique_violation acotada a la constraint EXACTA.
-- LEDGER: lee la admision previa de un (client_id, nonce). NULL si no hay.
--   Se separa de la escritura a proposito: el FAST PATH de admitir lo consulta
--   ANTES de cobrar cuota, para que un recovery NO vuelva a cobrar.
CREATE FUNCTION precios_api.api_precios_admision_leer(p_client_id TEXT, p_nonce UUID)
RETURNS TABLE (admission_hash TEXT, ticket_id UUID, ticket_estado TEXT)
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT n.admission_hash,
         n.ticket_id,
         CASE
           WHEN t.ticket_id   IS NULL                                THEN 'inexistente'
           WHEN t.consumed_at IS NOT NULL                            THEN 'consumido'
           WHEN t.expires_at  <= pg_catalog.clock_timestamp()        THEN 'vencido'
           ELSE 'libre'
         END::TEXT
    FROM precios_api.api_precios_nonce_s2s n
    LEFT JOIN precios_api.api_precios_ticket t ON t.ticket_id = n.ticket_id
   WHERE n.client_id = p_client_id
     AND n.nonce     = p_nonce;
END
$$;

-- 3.6 VALIDACION ESCALAR MINIMA (pre-admision). Barata: enums + regex.
--     Combinaciones por accion:
--       cotizar  : exige payload          / prohibe idem_key y cotizacion_id
--       congelar : exige payload+idem_key / prohibe cotizacion_id
--       obtener  : exige cotizacion_id    / prohibe payload e idem_key
--     correlation_id es OBLIGATORIO y se valida ANTES de cobrar cuota: si faltara,
--     el INSERT del ticket (NOT NULL) reventaria DESPUES de cobrar y saldria como
--     error_interno.
CREATE FUNCTION precios_api.api_precios_validar_admision(
  p_accion         TEXT,
  p_superficie     TEXT,
  p_sujeto         TEXT,
  p_nonce          UUID,
  p_payload_txt    TEXT,
  p_idem_key       UUID,
  p_cotizacion_id  UUID,
  p_correlation_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
BEGIN
  IF p_accion IS NULL OR p_accion NOT IN ('cotizar','congelar','obtener') THEN
    RETURN 'accion_invalida';
  END IF;

  -- F3 estructural: B4-0A nace S2S-only. 'web' no se acepta hasta B4-0C.
  IF p_superficie IS DISTINCT FROM 's2s' THEN
    RETURN 'superficie_invalida';
  END IF;
  IF p_sujeto IS DISTINCT FROM 'whatsapp' THEN
    RETURN 'sujeto_invalido';
  END IF;

  IF p_nonce IS NULL THEN
    RETURN 'nonce_requerido';
  END IF;

  IF p_correlation_id IS NULL THEN
    RETURN 'correlation_id_requerido';
  END IF;

  IF p_accion = 'cotizar' THEN
    IF p_payload_txt IS NULL       THEN RETURN 'payload_requerido';         END IF;
    IF p_idem_key IS NOT NULL      THEN RETURN 'idem_key_no_admitida';      END IF;
    IF p_cotizacion_id IS NOT NULL THEN RETURN 'cotizacion_id_no_admitida'; END IF;

  ELSIF p_accion = 'congelar' THEN
    IF p_payload_txt IS NULL       THEN RETURN 'payload_requerido';         END IF;
    IF p_idem_key IS NULL          THEN RETURN 'idem_key_requerida';        END IF;
    -- UUID v4 RFC 4122 (version + variante). El cast a UUID no valida la version.
    IF p_idem_key::TEXT !~* '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
      RETURN 'idem_key_no_v4';
    END IF;
    IF p_cotizacion_id IS NOT NULL THEN RETURN 'cotizacion_id_no_admitida'; END IF;

  ELSE  -- obtener
    IF p_cotizacion_id IS NULL     THEN RETURN 'cotizacion_id_requerida';   END IF;
    IF p_payload_txt IS NOT NULL   THEN RETURN 'payload_no_admitido';       END IF;
    IF p_idem_key IS NOT NULL      THEN RETURN 'idem_key_no_admitida';      END IF;
  END IF;

  RETURN NULL;
END
$$;

-- 3.7 VALIDACION PROFUNDA DEL PAYLOAD (post-ticket).  VOLATILE: usa clock_timestamp().
--
--   NINGUN formato invalido puede terminar en error_interno. TODO cast peligroso va
--   dentro de un bloque que captura data_exception (clase 22: 22P02 sintaxis,
--   22003 out of range, 22008 datetime overflow).
--
--   TIPOS EXIGIDOS EXPLICITAMENTE:
--     - fechas: jsonb_typeof = 'string'. Un JSON null pasa el operador `?` y castea
--       a SQL NULL (VERIFICADO): sin este check el motor recibia fechas NULL.
--     - numeros: jsonb_typeof = 'number' + INTEGRALIDAD (trunc) + RANGO, todo sobre
--       NUMERIC ANTES de castear. VERIFICADO: 1.5 -> 22P02; 1e100 / 1e10 -> 22003.
--       Sin esto salian como error_interno en vez de payload_invalido.
--
--   COTAS ESTRUCTURALES (defensa server-side real de computo, no el statement_timeout):
--     span <= 30 noches | horizonte <= hoy_ART + 540 | fecha_in >= hoy_ART | personas 1..20
--
--   reject-unknown: 'modo' y 'canal' NO son claves admitidas.
--     -> modo='online' se FUERZA server-side; canal se DERIVA de la superficie.
CREATE FUNCTION precios_api.api_precios_validar_payload(p_payload JSONB, p_canal TEXT)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
DECLARE
  c_permitidas CONSTANT TEXT[]  := ARRAY['id_cabana','fecha_in','fecha_out','personas'];
  c_span_max   CONSTANT INTEGER := 30;
  c_horiz_max  CONSTANT INTEGER := 540;
  c_pers_max   CONSTANT INTEGER := 20;
  c_cab_max    CONSTANT NUMERIC := 2147483647;   -- cota anti-overflow previa al cast
  v_k      TEXT;
  v_num    NUMERIC;
  v_s_in   TEXT;
  v_s_out  TEXT;
  v_hoy    DATE;
  v_cab    BIGINT;
  v_in     DATE;
  v_out    DATE;
  v_pers   INTEGER;
  v_activa BOOLEAN;
BEGIN
  IF p_payload IS NULL OR pg_catalog.jsonb_typeof(p_payload) <> 'object' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'payload');
  END IF;

  -- reject-unknown (allowlist estricta)
  FOR v_k IN SELECT pg_catalog.jsonb_object_keys(p_payload) LOOP
    IF NOT (v_k = ANY (c_permitidas)) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', v_k);
    END IF;
  END LOOP;

  -- todas presentes
  FOREACH v_k IN ARRAY c_permitidas LOOP
    IF NOT (p_payload ? v_k) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', v_k);
    END IF;
  END LOOP;

  -- ---------- id_cabana: number + integral + rango, ANTES de castear ----------
  IF pg_catalog.jsonb_typeof(p_payload->'id_cabana') <> 'number' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'id_cabana');
  END IF;
  BEGIN
    v_num := (p_payload->>'id_cabana')::NUMERIC;
  EXCEPTION WHEN data_exception THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'id_cabana');
  END;
  IF v_num IS NULL
     OR v_num <> pg_catalog.trunc(v_num)       -- fracciones: 1.5
     OR v_num < 1 OR v_num > c_cab_max         -- overflow: 1e100
  THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'id_cabana');
  END IF;
  v_cab := v_num::BIGINT;

  -- ---------- personas: number + integral + rango ----------
  IF pg_catalog.jsonb_typeof(p_payload->'personas') <> 'number' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'personas');
  END IF;
  BEGIN
    v_num := (p_payload->>'personas')::NUMERIC;
  EXCEPTION WHEN data_exception THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'personas');
  END;
  IF v_num IS NULL
     OR v_num <> pg_catalog.trunc(v_num)
     OR v_num < 1 OR v_num > c_pers_max        -- 1e10 rebota por RANGO, no por cast
  THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'personas');
  END IF;
  v_pers := v_num::INTEGER;

  -- ---------- fecha_in: STRING (no null, no number, no bool) + YMD exacto ----------
  IF pg_catalog.jsonb_typeof(p_payload->'fecha_in') <> 'string' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_in');
  END IF;
  v_s_in := p_payload->>'fecha_in';
  IF v_s_in !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_in');
  END IF;
  BEGIN
    v_in := v_s_in::DATE;                       -- 2026-02-31 revienta aca
  EXCEPTION WHEN data_exception THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_in');
  END;
  IF pg_catalog.to_char(v_in, 'YYYY-MM-DD') IS DISTINCT FROM v_s_in THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_in');
  END IF;

  -- ---------- fecha_out: idem ----------
  IF pg_catalog.jsonb_typeof(p_payload->'fecha_out') <> 'string' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_out');
  END IF;
  v_s_out := p_payload->>'fecha_out';
  IF v_s_out !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_out');
  END IF;
  BEGIN
    v_out := v_s_out::DATE;
  EXCEPTION WHEN data_exception THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_out');
  END;
  IF pg_catalog.to_char(v_out, 'YYYY-MM-DD') IS DISTINCT FROM v_s_out THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_out');
  END IF;

  -- fecha_out es EXCLUSIVE
  IF v_out <= v_in THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_out');
  END IF;

  -- COTA ESTRUCTURAL 1: span
  IF (v_out - v_in) > c_span_max THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'span');
  END IF;

  -- COTAS 2/3: ventana temporal, en horario de Argentina. clock_timestamp(), no now().
  v_hoy := (pg_catalog.clock_timestamp() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF v_in < v_hoy THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_in_pasada');
  END IF;
  IF v_out > (v_hoy + c_horiz_max) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'horizonte');
  END IF;

  -- cabana existente y activa
  SELECT cb.activa INTO v_activa
    FROM public.cabanas cb
   WHERE cb.id_cabana = v_cab;
  IF NOT FOUND OR v_activa IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'id_cabana');
  END IF;

  -- normalizado: canal DERIVADO, modo FORZADO
  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'payload', pg_catalog.jsonb_build_object(
      'id_cabana', v_cab,
      'fecha_in',  pg_catalog.to_char(v_in,  'YYYY-MM-DD'),
      'fecha_out', pg_catalog.to_char(v_out, 'YYYY-MM-DD'),
      'personas',  v_pers,
      'canal',     p_canal,
      'modo',      'online'
    ));
END
$$;

-- ===========================================================================
-- 4) CORE OWNER-ONLY -- SIN GRANT AL ROL.
--    Unica puerta al motor: los *_exponer, que siempre pagan admision.
-- ===========================================================================

CREATE FUNCTION precios_api.api_precios_cotizar_core(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
BEGIN
  PERFORM precios_api.api_precios_guard_sesion();
  PERFORM precios_api.api_precios_gate_ambiente();
  RETURN public.precios_cotizar(p_payload);
END
$$;

CREATE FUNCTION precios_api.api_precios_obtener_core(p_cotizacion_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
BEGIN
  PERFORM precios_api.api_precios_guard_sesion();
  PERFORM precios_api.api_precios_gate_ambiente();
  RETURN public.precios_cotizacion_obtener(p_cotizacion_id);
END
$$;

-- congelar -- unico writer de negocio.
--   POLITICA: la key se consume SOLO si congelada=true.
--   CARRERA: la resuelve el UNIQUE. El EXCEPTION revierte tambien el INSERT que
--     precios_cotizar_congelar hizo en cotizaciones_precio -> cero huerfanas.
--   unique_violation acotada a pk_api_precios_idempotencia: cualquier otra se RELANZA.
--   VIGENCIA: contra cotizaciones_precio (fuente de verdad) y con clock_timestamp().
CREATE FUNCTION precios_api.api_precios_congelar_core(p_payload JSONB, p_idem_key UUID, p_scope TEXT)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
DECLARE
  v_canon TEXT;
  v_hash  TEXT;
  v_row   RECORD;
  v_q     JSONB;
  v_cid   UUID;
  v_exp   TIMESTAMPTZ;
  v_con   TEXT;
BEGIN
  PERFORM precios_api.api_precios_guard_sesion();
  PERFORM precios_api.api_precios_gate_ambiente();

  -- canon de NEGOCIO (distinto del canon del ticket)
  v_canon := 'b4v1|' || (p_payload->>'id_cabana')
                     || '|' || (p_payload->>'fecha_in')
                     || '|' || (p_payload->>'fecha_out')
                     || '|' || (p_payload->>'personas')
                     || '|' || (p_payload->>'canal')
                     || '|online';
  v_hash := pg_catalog.encode(pg_catalog.sha256(v_canon::BYTEA), 'hex');

  -- FAST PATH (no decide: el UNIQUE sigue siendo la red)
  SELECT i.canon_hash, i.cotizacion_id, i.resultado_motor_privado
    INTO v_row
    FROM precios_api.api_precios_idempotencia i
   WHERE i.scope = p_scope AND i.idempotency_key = p_idem_key;

  IF FOUND THEN
    IF v_row.canon_hash IS DISTINCT FROM v_hash THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'conflicto');
    END IF;
    -- vigencia contra la FUENTE DE VERDAD, no contra el snapshot congelado.
    SELECT cp.expires_at INTO v_exp
      FROM public.cotizaciones_precio cp
     WHERE cp.cotizacion_id = v_row.cotizacion_id;
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'via', 'replay',
      'vigente', (v_exp > pg_catalog.clock_timestamp()),
      'motor', v_row.resultado_motor_privado);
  END IF;

  -- SLOW PATH
  BEGIN
    v_q := public.precios_cotizar_congelar(p_payload);

    -- sin efecto de escritura -> NO se consume la key
    IF COALESCE((v_q->>'congelada')::BOOLEAN, FALSE) IS NOT TRUE THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'via', 'nuevo',
                                           'vigente', FALSE, 'motor', v_q);
    END IF;

    v_cid := (v_q->>'cotizacion_id')::UUID;

    INSERT INTO precios_api.api_precios_idempotencia
      (scope, idempotency_key, canon_hash, cotizacion_id, resultado_motor_privado)
    VALUES (p_scope, p_idem_key, v_hash, v_cid, v_q);

  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
    IF v_con IS DISTINCT FROM 'pk_api_precios_idempotencia' THEN
      RAISE;
    END IF;

    -- perdi la carrera. El rollback al savepoint ya revirtio MI INSERT en
    -- cotizaciones_precio. Leo la fila del ganador (ya commiteada).
    SELECT i.canon_hash, i.cotizacion_id, i.resultado_motor_privado
      INTO v_row
      FROM precios_api.api_precios_idempotencia i
     WHERE i.scope = p_scope AND i.idempotency_key = p_idem_key;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'idempotencia_inconsistente' USING ERRCODE = 'VDT04';
    END IF;
    IF v_row.canon_hash IS DISTINCT FROM v_hash THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'conflicto');
    END IF;
    SELECT cp.expires_at INTO v_exp
      FROM public.cotizaciones_precio cp
     WHERE cp.cotizacion_id = v_row.cotizacion_id;
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'via', 'replay',
      'vigente', (v_exp > pg_catalog.clock_timestamp()),
      'motor', v_row.resultado_motor_privado);
  END;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'via', 'nuevo',
    'vigente', ((v_q->>'expires_at')::TIMESTAMPTZ > pg_catalog.clock_timestamp()),
    'motor', v_q);
END
$$;

-- ===========================================================================
-- 5) ADMISION (TXN 1) -- la unica funcion que emite tickets.
--    proconfig: lock_timeout 1s (COTA DURA: se reimpone aunque el caller haga
--    SET lock_timeout=0 -- verificado).
--    statement_timeout NO va en proconfig: es INERTE (no arma ni baja el timer --
--    verificado en ambos sentidos). Lo impone la Edge con SET LOCAL.
-- ===========================================================================
CREATE FUNCTION precios_api.api_precios_admitir(
  p_accion         TEXT,
  p_superficie     TEXT,
  p_sujeto         TEXT,
  p_nonce          UUID,
  p_payload_txt    TEXT,
  p_idem_key       UUID,
  p_cotizacion_id  UUID,
  p_correlation_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, precios_api, public, pg_temp
SET lock_timeout = '1s'
AS $$
DECLARE
  v_err       TEXT;
  v_payload   JSONB;
  v_hash      TEXT;
  v_tid       UUID;
  v_ventana   TIMESTAMPTZ;
  v_state     TEXT;
  v_con       TEXT;
  v_prev      RECORD;
BEGIN
  -- D3: PRIMERA sentencia, FUERA del savepoint. VDT01 debe propagar crudo para
  -- que la Edge recicle la conexion.
  PERFORM precios_api.api_precios_guard_sesion();

  -- =========================================================================
  -- SAVEPOINT EXTERNO -- cubre TODO el cuerpo.
  --
  --   MOTIVO: lock_timeout lanza SQLSTATE 55P03 (lock_not_available). MEDIDO:
  --   sin handler ESCAPA CRUDO al driver y rompe el contrato JSON. Antes las
  --   cuotas y el nonce estaban FUERA de todo bloque EXCEPTION.
  --
  --   Al revertir al savepoint, un lock timeout deja el estado LIMPIO:
  --   sin cuota parcial, sin fila de ledger, sin ticket.
  -- =========================================================================
  BEGIN
    PERFORM precios_api.api_precios_gate_ambiente();

    -- 1) validacion escalar (incluye correlation_id NOT NULL: ANTES de cobrar)
    v_err := precios_api.api_precios_validar_admision(
               p_accion, p_superficie, p_sujeto, p_nonce,
               p_payload_txt, p_idem_key, p_cotizacion_id, p_correlation_id);
    IF v_err IS NOT NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'admision_invalida', 'campo', v_err);
    END IF;

    -- 2) tamano: O(1), antes de cualquier trabajo caro.
    IF p_payload_txt IS NOT NULL AND pg_catalog.octet_length(p_payload_txt) > 8192 THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'admision_invalida',
                                           'campo', 'payload_size');
    END IF;

    -- 3) parse + HASH. El hash ES el binding de admision: hay que calcularlo
    --    ANTES de consultar el ledger. Acotado a 8 KB por el paso 2.
    IF p_payload_txt IS NULL THEN
      v_payload := NULL;
    ELSE
      v_payload := p_payload_txt::JSONB;     -- puede lanzar invalid_text_representation
      IF pg_catalog.jsonb_typeof(v_payload) <> 'object' THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'admision_invalida',
                                             'campo', 'payload_tipo');
      END IF;
    END IF;

    v_hash := precios_api.api_precios_ticket_hash_v1(
                p_accion, p_superficie, p_sujeto, v_payload, p_idem_key, p_cotizacion_id);

    -- VENTANA UNICA para las CUATRO cubetas: se calcula una sola vez para que
    -- todas caigan en el mismo minuto aunque el reloj cruce el borde entre ellas.
    v_ventana := pg_catalog.date_trunc('minute', pg_catalog.clock_timestamp());

    -- =======================================================================
    -- CUOTA DE INTENTOS -- se cobra en TODA invocacion: nueva, recovery y replay.
    --
    --   Es la unica cota que frena el REPLAY MASIVO. El recovery NO consume la
    --   cuota logica de la operacion (esa es su razon de ser), asi que sin esta
    --   cubeta un atacante podria repetir la misma solicitud valida un millon de
    --   veces -- parse + SHA-256 + SELECT + conexion -- sin tocar ningun limite.
    --
    --   Va ANTES del advisory lock: un flood se rechaza barato, sin serializarse.
    -- =======================================================================
    IF NOT precios_api.api_precios_rl_consumir(
             'admision_intento_global', '_global', v_ventana) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'rate_limited',
                                           'cubeta', 'intento_global');
    END IF;

    IF NOT precios_api.api_precios_rl_consumir(
             'admision_intento_' || p_superficie, p_sujeto, v_ventana) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'rate_limited',
                                           'cubeta', 'intento_sujeto');
    END IF;

    -- =======================================================================
    -- SERIALIZACION POR (client_id, nonce) -- advisory lock de TRANSACCION.
    --
    --   SIN ESTO (bug medido en v5): dos admisiones concurrentes del MISMO nonce
    --   pasaban las dos por el fast path (ninguna ve la fila no-commiteada de la
    --   otra), las dos cobraban la cuota LOGICA, y la perdedora devolvia
    --   'recovery' con sus cuotas ya persistidas -> cuota cobrada DOS VECES por
    --   UNA sola admision.
    --
    --   Con el lock, la segunda ESPERA al commit de la primera y despues lee un
    --   ledger que YA tiene la fila -> recovery limpio, sin cuota logica.
    --
    --   Se libera solo al COMMIT/ROLLBACK (xact): no hace falta soltarlo a mano.
    --   MEDIDO: respeta lock_timeout -> 55P03 -> lo capta el savepoint externo
    --   -> {ok:false, error:'timeout'} y el savepoint revierte TODO, incluida la
    --   cuota de intentos. "Sin mutaciones", como debe ser.
    --
    --   Una colision de hash entre dos (client_id, nonce) distintos solo los
    --   serializa de mas: es una perdida de paralelismo, nunca de correccion.
    -- =======================================================================
    PERFORM pg_catalog.pg_advisory_xact_lock(
              pg_catalog.hashtextextended(p_sujeto || '|' || p_nonce::TEXT, 0));

    -- =======================================================================
    -- LECTURA DEL LEDGER -- ya serializada. Aca no hay carrera posible.
    --     mismo binding    -> RECOVERY: mismo ticket_id, sin cuota LOGICA.
    --     binding distinto -> nonce_replay, sin cuota LOGICA.
    --   Los dos ya pagaron la cuota de INTENTOS, arriba.
    -- =======================================================================
    SELECT * INTO v_prev
      FROM precios_api.api_precios_admision_leer(p_sujeto, p_nonce);

    IF FOUND THEN
      IF v_prev.admission_hash IS DISTINCT FROM v_hash THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'nonce_replay');
      END IF;
      RETURN pg_catalog.jsonb_build_object(
               'ok', true, 'via', 'recovery',
               'ticket_id', v_prev.ticket_id,
               'ticket_estado', v_prev.ticket_estado);
    END IF;

    -- =======================================================================
    -- ADMISION NUEVA -- unico camino que paga la cuota LOGICA.
    --
    --   El sub-savepoint envuelve cuota logica + ledger + ticket: si el UNIQUE
    --   saltara igual (colision de advisory, o un camino no previsto), revierte
    --   TAMBIEN las cuotas logicas -> el recovery de esa rama tampoco las cobra.
    --   Con el advisory lock esto no deberia dispararse nunca; queda como red.
    --
    --   Si la cuota logica RECHAZA, no se escribe el ledger -> el nonce queda
    --   LIBRE (un rate_limited no debe quemar el nonce del cliente).
    -- =======================================================================
    BEGIN
      IF NOT precios_api.api_precios_rl_consumir(p_accion || '_global', '_global', v_ventana) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'rate_limited', 'cubeta', 'global');
      END IF;

      IF NOT precios_api.api_precios_rl_consumir(p_accion || '_' || p_superficie, p_sujeto, v_ventana) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'rate_limited', 'cubeta', 'sujeto');
      END IF;

      v_tid := pg_catalog.gen_random_uuid();

      INSERT INTO precios_api.api_precios_nonce_s2s
        (client_id, nonce, admission_hash, ticket_id, created_at)
      VALUES
        (p_sujeto, p_nonce, v_hash, v_tid, pg_catalog.clock_timestamp());

      INSERT INTO precios_api.api_precios_ticket
        (ticket_id, accion, superficie, sujeto, request_hash, correlation_id,
         created_at, expires_at)
      VALUES
        (v_tid, p_accion, p_superficie, p_sujeto, v_hash, p_correlation_id,
         pg_catalog.clock_timestamp(),
         pg_catalog.clock_timestamp() + INTERVAL '30 seconds');

    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
      IF v_con IS DISTINCT FROM 'pk_api_precios_nonce_s2s' THEN
        RAISE;
      END IF;

      -- RED DE SEGURIDAD (no deberia alcanzarse con el advisory lock). El
      -- savepoint ya revirtio las cuotas logicas de esta rama.
      SELECT * INTO v_prev
        FROM precios_api.api_precios_admision_leer(p_sujeto, p_nonce);

      IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'nonce_replay');
      END IF;
      IF v_prev.admission_hash IS DISTINCT FROM v_hash THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'nonce_replay');
      END IF;

      RETURN pg_catalog.jsonb_build_object(
               'ok', true, 'via', 'recovery',
               'ticket_id', v_prev.ticket_id,
               'ticket_estado', v_prev.ticket_estado);
    END;

  EXCEPTION
    WHEN SQLSTATE 'VDT01' THEN
      RAISE;                    -- D3: sesion envenenada -> la Edge recicla la conexion
    WHEN SQLSTATE 'VDT03' THEN
      RAISE;                    -- gate de ambiente: ABORTA, no se degrada a error_interno
    WHEN lock_not_available THEN
      -- 55P03. El savepoint ya revirtio: sin cuota parcial, sin ledger, sin ticket.
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN query_canceled THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN invalid_text_representation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'admision_invalida',
                                           'campo', 'payload_json');
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME;
      RAISE LOG 'B4 rutina=api_precios_admitir corr=% sqlstate=% constraint=%',
                p_correlation_id, v_state, COALESCE(v_con, '-');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
  END;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'via', 'nuevo', 'ticket_id', v_tid);
END
$$;

-- ===========================================================================
-- 6) EJECUCION (TXN 2) -- 3 entrypoints con ticket.
--    Sin ticket valido no se llega a ningun core.
--    correlation_id NO viaja por firma: se lee de la fila del ticket.
--    TODA comparacion temporal con clock_timestamp(): now() esta CONGELADO al
--    inicio de la transaccion y permitiria consumir un ticket YA EXPIRADO.
-- ===========================================================================

CREATE FUNCTION precios_api.api_precios_cotizar_exponer(p_ticket UUID, p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, precios_api, public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_sup TEXT; v_suj TEXT; v_ht TEXT; v_corr UUID;
  v_hc TEXT; v_canal TEXT; v_v JSONB; v_res JSONB;
  v_state TEXT; v_con TEXT;
BEGIN
  PERFORM precios_api.api_precios_guard_sesion();    -- D3, FUERA del savepoint

  -- =========================================================================
  -- SAVEPOINT EXTERNO -- cubre el UPDATE del ticket, el binding y el core.
  --   El UPDATE puede chocar un lock (55P03 lock_not_available). MEDIDO: sin
  --   handler escapa crudo y rompe el contrato JSON. Al revertir al savepoint,
  --   el ticket queda LIBRE: se puede reintentar con el mismo ticket_id.
  -- =========================================================================
  BEGIN
    PERFORM precios_api.api_precios_gate_ambiente();

    -- consumo atomico single-use
    UPDATE precios_api.api_precios_ticket t
       SET consumed_at = pg_catalog.clock_timestamp()
     WHERE t.ticket_id   = p_ticket
       AND t.consumed_at IS NULL
       AND t.expires_at  > pg_catalog.clock_timestamp()
       AND t.accion      = 'cotizar'
    RETURNING t.superficie, t.sujeto, t.request_hash, t.correlation_id
         INTO v_sup, v_suj, v_ht, v_corr;

    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
    END IF;

    -- binding. Mismatch -> el ticket YA quedo consumido: SE QUEMA.
    v_hc := precios_api.api_precios_ticket_hash_v1('cotizar', v_sup, v_suj, p_payload, NULL, NULL);
    IF v_hc IS DISTINCT FROM v_ht THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
    END IF;

    v_canal := CASE WHEN v_sup = 's2s' AND v_suj = 'whatsapp' THEN 'whatsapp'
                    WHEN v_sup = 'web' THEN 'web' ELSE NULL END;
    IF v_canal IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
    END IF;

    v_v := precios_api.api_precios_validar_payload(p_payload, v_canal);
    IF COALESCE((v_v->>'ok')::BOOLEAN, FALSE) IS NOT TRUE THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'payload_invalido',
                                           'campo', v_v->>'campo');
    END IF;

    v_res := precios_api.api_precios_cotizar_core(v_v->'payload');

  EXCEPTION
    WHEN SQLSTATE 'VDT01' THEN
      RAISE;   -- rollback de TXN2 -> ticket libre -> la Edge recicla y reintenta 1 vez
    WHEN SQLSTATE 'VDT03' THEN
      RAISE;   -- gate de ambiente: ABORTA, no se degrada a error_interno
    WHEN lock_not_available THEN
      -- 55P03: el savepoint revirtio el UPDATE -> el TICKET SIGUE LIBRE.
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN query_canceled THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME;
      RAISE LOG 'B4 rutina=api_precios_cotizar_exponer corr=% sqlstate=% constraint=%',
                v_corr, v_state, COALESCE(v_con, '-');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
  END;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'via', 'nuevo', 'motor', v_res);
END
$$;

CREATE FUNCTION precios_api.api_precios_congelar_exponer(p_ticket UUID, p_payload JSONB, p_idem_key UUID)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, precios_api, public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_sup TEXT; v_suj TEXT; v_ht TEXT; v_corr UUID;
  v_hc TEXT; v_canal TEXT; v_v JSONB; v_res JSONB;
  v_state TEXT; v_con TEXT;
BEGIN
  PERFORM precios_api.api_precios_guard_sesion();    -- D3, FUERA del savepoint

  -- SAVEPOINT EXTERNO: cubre el UPDATE del ticket (55P03) + binding + core.
  BEGIN
    PERFORM precios_api.api_precios_gate_ambiente();

    UPDATE precios_api.api_precios_ticket t
       SET consumed_at = pg_catalog.clock_timestamp()
     WHERE t.ticket_id   = p_ticket
       AND t.consumed_at IS NULL
       AND t.expires_at  > pg_catalog.clock_timestamp()
       AND t.accion      = 'congelar'
    RETURNING t.superficie, t.sujeto, t.request_hash, t.correlation_id
         INTO v_sup, v_suj, v_ht, v_corr;

    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
    END IF;

    -- el idem_key ENTRA al canon del ticket
    v_hc := precios_api.api_precios_ticket_hash_v1('congelar', v_sup, v_suj, p_payload, p_idem_key, NULL);
    IF v_hc IS DISTINCT FROM v_ht THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
    END IF;

    v_canal := CASE WHEN v_sup = 's2s' AND v_suj = 'whatsapp' THEN 'whatsapp'
                    WHEN v_sup = 'web' THEN 'web' ELSE NULL END;
    IF v_canal IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
    END IF;

    v_v := precios_api.api_precios_validar_payload(p_payload, v_canal);
    IF COALESCE((v_v->>'ok')::BOOLEAN, FALSE) IS NOT TRUE THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'payload_invalido',
                                           'campo', v_v->>'campo');
    END IF;

    v_res := precios_api.api_precios_congelar_core(
               v_v->'payload', p_idem_key, 'precios.congelar:' || v_canal);

  EXCEPTION
    WHEN SQLSTATE 'VDT01' THEN
      RAISE;                    -- D3: sesion envenenada -> la Edge recicla la conexion
    WHEN SQLSTATE 'VDT03' THEN
      RAISE;                    -- gate de ambiente: ABORTA, no se degrada a error_interno
    WHEN lock_not_available THEN
      -- 55P03: savepoint revertido -> el TICKET SIGUE LIBRE.
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN query_canceled THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME;
      RAISE LOG 'B4 rutina=api_precios_congelar_exponer corr=% sqlstate=% constraint=%',
                v_corr, v_state, COALESCE(v_con, '-');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
  END;

  RETURN v_res;
END
$$;

CREATE FUNCTION precios_api.api_precios_obtener_exponer(p_ticket UUID, p_cotizacion_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, precios_api, public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_sup TEXT; v_suj TEXT; v_ht TEXT; v_corr UUID;
  v_hc TEXT; v_res JSONB;
  v_state TEXT; v_con TEXT;
BEGIN
  PERFORM precios_api.api_precios_guard_sesion();    -- D3, FUERA del savepoint

  -- SAVEPOINT EXTERNO: cubre el UPDATE del ticket (55P03) + binding + core.
  BEGIN
    PERFORM precios_api.api_precios_gate_ambiente();

    UPDATE precios_api.api_precios_ticket t
       SET consumed_at = pg_catalog.clock_timestamp()
     WHERE t.ticket_id   = p_ticket
       AND t.consumed_at IS NULL
       AND t.expires_at  > pg_catalog.clock_timestamp()
       AND t.accion      = 'obtener'
    RETURNING t.superficie, t.sujeto, t.request_hash, t.correlation_id
         INTO v_sup, v_suj, v_ht, v_corr;

    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
    END IF;

    -- el cotizacion_id ENTRA al canon del ticket
    v_hc := precios_api.api_precios_ticket_hash_v1('obtener', v_sup, v_suj, NULL, NULL, p_cotizacion_id);
    IF v_hc IS DISTINCT FROM v_ht THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
    END IF;

    v_res := precios_api.api_precios_obtener_core(p_cotizacion_id);

  EXCEPTION
    WHEN SQLSTATE 'VDT01' THEN
      RAISE;                    -- D3: sesion envenenada -> la Edge recicla la conexion
    WHEN SQLSTATE 'VDT03' THEN
      RAISE;                    -- gate de ambiente: ABORTA, no se degrada a error_interno
    WHEN lock_not_available THEN
      -- 55P03: savepoint revertido -> el TICKET SIGUE LIBRE.
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN query_canceled THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME;
      RAISE LOG 'B4 rutina=api_precios_obtener_exponer corr=% sqlstate=% constraint=%',
                v_corr, v_state, COALESCE(v_con, '-');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
  END;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'via', 'nuevo', 'motor', v_res);
END
$$;

-- ===========================================================================
-- 7) PROBE TEMPORAL -- solo para B4-0B. Lee de verdad, schema-qualified.
--    Se REVOCA y se DROPEA al cerrar B4-0B (runsheet, paso 10).
-- ===========================================================================
CREATE FUNCTION precios_api.api_precios_probe_ambiente()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
DECLARE v_amb TEXT;
BEGIN
  PERFORM precios_api.api_precios_guard_sesion();
  SELECT cg.valor INTO v_amb
    FROM public.configuracion_general cg
   WHERE cg.clave = 'ambiente';
  RETURN v_amb;
END
$$;

-- ===========================================================================
-- 8) PURGAS OWNER-ONLY  (4).  Sin D3: las corre pg_cron (sesion limpia) o postgres;
--    el rol NO puede ejecutarlas. Son ademas el vehiculo del smoke D1/D2 aislado
--    (no llaman a B3). Gate de ambiente DENTRO de cada una.
--    clock_timestamp(): una purga es una decision temporal.
-- ===========================================================================
CREATE FUNCTION precios_api.api_precios_ticket_purgar()
RETURNS INTEGER
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
DECLARE v_n INTEGER;
BEGIN
  PERFORM precios_api.api_precios_gate_ambiente();
  DELETE FROM precios_api.api_precios_ticket
   WHERE expires_at < pg_catalog.clock_timestamp() - INTERVAL '5 minutes';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$$;

CREATE FUNCTION precios_api.api_precios_nonce_purgar()
RETURNS INTEGER
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
DECLARE v_n INTEGER;
BEGIN
  PERFORM precios_api.api_precios_gate_ambiente();
  DELETE FROM precios_api.api_precios_nonce_s2s
   WHERE created_at < pg_catalog.clock_timestamp() - INTERVAL '10 minutes';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$$;

CREATE FUNCTION precios_api.api_precios_rl_purgar()
RETURNS INTEGER
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
DECLARE v_n INTEGER;
BEGIN
  PERFORM precios_api.api_precios_gate_ambiente();
  DELETE FROM precios_api.api_precios_rate_limit
   WHERE ventana < pg_catalog.clock_timestamp() - INTERVAL '1 hour';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$$;

CREATE FUNCTION precios_api.api_precios_idempotencia_purgar()
RETURNS INTEGER
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, precios_api, public, pg_temp
AS $$
DECLARE v_n INTEGER;
BEGIN
  PERFORM precios_api.api_precios_gate_ambiente();
  DELETE FROM precios_api.api_precios_idempotencia
   WHERE created_at < pg_catalog.clock_timestamp() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$$;

-- ===========================================================================
-- 9) ACL FINAL
--    Runtime del rol: 4 EXECUTE (+1 temporal de probe). CERO privilegios de tabla.
--    El rol esta EXPLICITAMENTE nombrado en los REVOKE: sin EXECUTE sobre el core,
--    NO PUEDE saltear la admision.
-- ===========================================================================
REVOKE EXECUTE ON FUNCTION
  precios_api.api_precios_guard_sesion(),
  precios_api.api_precios_gate_ambiente(),
  precios_api.api_precios_ticket_hash_v1(TEXT, TEXT, TEXT, JSONB, UUID, UUID),
  precios_api.api_precios_rl_consumir(TEXT, TEXT, TIMESTAMPTZ),
  precios_api.api_precios_admision_leer(TEXT, UUID),
  precios_api.api_precios_validar_admision(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID, UUID),
  precios_api.api_precios_validar_payload(JSONB, TEXT),
  precios_api.api_precios_cotizar_core(JSONB),
  precios_api.api_precios_congelar_core(JSONB, UUID, TEXT),
  precios_api.api_precios_obtener_core(UUID),
  precios_api.api_precios_ticket_purgar(),
  precios_api.api_precios_nonce_purgar(),
  precios_api.api_precios_rl_purgar(),
  precios_api.api_precios_idempotencia_purgar()
  FROM PUBLIC, anon, authenticated, service_role, vita_precios_api;

REVOKE EXECUTE ON FUNCTION
  precios_api.api_precios_admitir(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID, UUID),
  precios_api.api_precios_cotizar_exponer(UUID, JSONB),
  precios_api.api_precios_congelar_exponer(UUID, JSONB, UUID),
  precios_api.api_precios_obtener_exponer(UUID, UUID),
  precios_api.api_precios_probe_ambiente()
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
  precios_api.api_precios_admitir(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID, UUID),
  precios_api.api_precios_cotizar_exponer(UUID, JSONB),
  precios_api.api_precios_congelar_exponer(UUID, JSONB, UUID),
  precios_api.api_precios_obtener_exponer(UUID, UUID),
  precios_api.api_precios_probe_ambiente()
  TO vita_precios_api;


-- ---------------------------------------------------------------------------
-- NOTA DE ALCANCE -- B4-0A NO aplica hardening global de default privileges.
--
-- Existe un hardening posible sobre las funciones FUTURAS de todo el proyecto
-- (dejar de conceder EXECUTE a PUBLIC por defecto). NO forma parte de B4-0A y
-- este script NO lo ejecuta, por decision explicita.
--
-- Motivo: es un cambio GLOBAL y PERSISTENTE, con efectos MEDIDOS fuera de B4
-- (funciones futuras de todo el proyecto; migraciones que dependan del EXECUTE
-- implicito; roles anon/authenticated/authenticator, que pierden acceso a toda
-- funcion nueva expuesta por PostgREST si dependian de PUBLIC; CREATE TYPE ...
-- AS RANGE para no-superusers; extensiones y scripts futuros), y el rollback de
-- B4-0A NO lo revierte. Un cambio de ese alcance no puede viajar dentro de un
-- bloque cuyo rollback no lo deshace. Se trata en un bloque de hardening
-- INDEPENDIENTE, todavia por disenar y auditar.
--
-- El aislamiento de B4-0A se apoya en cuatro cosas que SI son suyas y SI se
-- revierten con su rollback:
--     1. schema dedicado precios_api (owner postgres, cerrado a PUBLIC);
--     2. REVOKE owner-only sobre las 13 precios_* de B3 (seccion 9.bis);
--     3. cero SECURITY DEFINER invocable fuera de la allowlist (VERIFY D03);
--     4. ACL exacta de los 5 entrypoints (VERIFY D01/D02).
--
-- Consecuencia declarada (no oculta): via el USAGE que el rol hereda de PUBLIC
-- sobre public, puede invocar funciones de public que tengan EXECUTE a PUBLIC,
-- actuales y futuras. Lo mide el VERIFY en D07 y lo lista su Salida 3.
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- 10) JOBS pg_cron  (4).  DENTRO de la transaccion, ANTES del unico COMMIT.
--     cron.schedule() = INSERT en cron.job + señal al bgworker, SIN commit interno
--     documentado -> participa de la transaccion del caller. Si algo falla, el
--     rollback deshace TAMBIEN los jobs (verificado con el harness).
--     ADVERTENCIA HONESTA: no se puede garantizar desde el harness que la version
--     de pg_cron de Supabase respete esto en todos los casos. Si resultara hacer
--     un commit interno, el estado podria quedar parcial -> el runsheet trae el
--     rollback compensatorio. Por eso NO se afirma atomicidad absoluta.
--
--     Se verifican las 4 firmas con to_regprocedure ANTES de programar: si alguna
--     no existe, aborta y el rollback global limpia todo.
--     Nombres EXACTOS (nunca LIKE). El gate 0.bis garantizo que no preexisten.
--     Retenciones maximas reales:
--       ticket        30 s  + 5 min elegibilidad + 5 min cron  ~= 10,5 min
--       nonce         10 min                     + 5 min cron  ~= 15 min
--       rate_limit    60 min                     + 10 min cron ~= 70 min
--       idempotencia  24 h                       + 1 h cron    ~= 25 h
--     NO hay watchdog de backends: retirado por decision explicita.
-- ===========================================================================
DO $jobs$
BEGIN
  -- firmas exactas antes de programar
  IF to_regprocedure('precios_api.api_precios_ticket_purgar()')       IS NULL
  OR to_regprocedure('precios_api.api_precios_nonce_purgar()')        IS NULL
  OR to_regprocedure('precios_api.api_precios_rl_purgar()')           IS NULL
  OR to_regprocedure('precios_api.api_precios_idempotencia_purgar()') IS NULL THEN
    RAISE EXCEPTION 'B4-0A abortado: falta alguna funcion de purga antes de programar los jobs.';
  END IF;

  PERFORM cron.schedule('b4_purga_ticket',       '*/5 * * * *',  'SELECT precios_api.api_precios_ticket_purgar();');
  PERFORM cron.schedule('b4_purga_nonce_s2s',    '*/5 * * * *',  'SELECT precios_api.api_precios_nonce_purgar();');
  PERFORM cron.schedule('b4_purga_rate_limit',   '*/10 * * * *', 'SELECT precios_api.api_precios_rl_purgar();');
  PERFORM cron.schedule('b4_purga_idempotencia', '0 * * * *',    'SELECT precios_api.api_precios_idempotencia_purgar();');
END
$jobs$;

COMMIT;

-- ============================================================================
-- FIN B4-0A.
-- Siguiente: el ALTER de password (runsheet paso 2) y despues B4_0A_v6_VERIFY.sql.
-- ============================================================================
