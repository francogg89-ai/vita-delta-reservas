-- ============================================================================
-- B4_0A_VERIFY.sql -- Verificacion read-only de B4-0A. No muta nada.
-- Correr DESPUES de B4_0A_ROL_TABLAS_FUNCIONES.sql y del ALTER de password.
-- Salida: tabla de checks (PASS/FAIL) + tabla informativa de TEMPORARY.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _v (orden INT, check_id TEXT, esperado TEXT, obtenido TEXT, ok BOOLEAN) ON COMMIT DROP;

-- ---------------------------------------------------------------------------
-- ROL
-- ---------------------------------------------------------------------------
INSERT INTO _v SELECT 1, 'V01_rol_existe', '1', COUNT(*)::TEXT, COUNT(*) = 1
FROM pg_catalog.pg_roles WHERE rolname = 'vita_precios_api';

-- LOGIN debe ser TRUE *despues* del ALTER manual del runsheet (paso 3).
-- Si da FAIL: falta correr el ALTER ... LOGIN PASSWORD.
INSERT INTO _v SELECT 2, 'V02_rol_login', 'true', rolcanlogin::TEXT, rolcanlogin
FROM pg_catalog.pg_roles WHERE rolname = 'vita_precios_api';

INSERT INTO _v SELECT 3, 'V03_rol_sin_atributos', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_roles
WHERE rolname = 'vita_precios_api'
  AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolbypassrls OR rolreplication);

INSERT INTO _v SELECT 4, 'V04_rol_sin_membresias', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_auth_members m
JOIN pg_catalog.pg_roles r ON r.oid = m.member
WHERE r.rolname = 'vita_precios_api';

INSERT INTO _v SELECT 5, 'V05_rol_usage_public', 'true',
       pg_catalog.has_schema_privilege('vita_precios_api','public','USAGE')::TEXT,
       pg_catalog.has_schema_privilege('vita_precios_api','public','USAGE');

INSERT INTO _v SELECT 6, 'V06_rol_sin_create_public', 'false',
       pg_catalog.has_schema_privilege('vita_precios_api','public','CREATE')::TEXT,
       NOT pg_catalog.has_schema_privilege('vita_precios_api','public','CREATE');

INSERT INTO _v SELECT 7, 'V07_rol_defaults', 'statement_timeout=5s + lock_timeout=2s', '2 de 2',
       (SELECT COUNT(*) FROM pg_catalog.unnest(
              (SELECT rolconfig FROM pg_catalog.pg_roles WHERE rolname='vita_precios_api')
            ) AS x WHERE x IN ('statement_timeout=5s','lock_timeout=2s')) = 2;

-- ---------------------------------------------------------------------------
-- TABLAS
-- ---------------------------------------------------------------------------
INSERT INTO _v SELECT 8, 'V08_tablas_b4', '4', COUNT(*)::TEXT, COUNT(*) = 4
FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND c.relname IN ('api_precios_rate_limit','api_precios_nonce_s2s',
                    'api_precios_ticket','api_precios_idempotencia');

INSERT INTO _v SELECT 9, 'V09_constraints_ticket', '7', COUNT(*)::TEXT, COUNT(*) = 7
FROM pg_catalog.pg_constraint
WHERE conrelid = 'public.api_precios_ticket'::regclass
  AND conname IN ('pk_api_precios_ticket','chk_ticket_accion','chk_ticket_superficie',
                  'chk_ticket_sujeto','chk_ticket_hash','chk_ticket_vigencia','chk_ticket_consumo');

INSERT INTO _v SELECT 10, 'V10_ticket_s2s_only', 'true', 'CHECK superficie=s2s + sujeto=whatsapp',
       EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
                WHERE conrelid='public.api_precios_ticket'::regclass AND conname='chk_ticket_superficie')
   AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
                WHERE conrelid='public.api_precios_ticket'::regclass AND conname='chk_ticket_sujeto');

INSERT INTO _v SELECT 11, 'V11_tablas_b4_sin_data_api', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_class c, pg_catalog.unnest(ARRAY['PUBLIC','anon','authenticated','service_role','vita_precios_api']) g(rol),
     pg_catalog.unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p(priv)
WHERE c.relname IN ('api_precios_rate_limit','api_precios_nonce_s2s','api_precios_ticket','api_precios_idempotencia')
  AND c.relnamespace = 'public'::regnamespace
  AND g.rol <> 'PUBLIC'
  AND pg_catalog.has_table_privilege(g.rol, c.oid, p.priv);

-- ---------------------------------------------------------------------------
-- FUNCIONES
-- ---------------------------------------------------------------------------
INSERT INTO _v SELECT 12, 'V12_funciones_b4', '19', COUNT(*)::TEXT, COUNT(*) = 19
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'api_precios_%';

INSERT INTO _v SELECT 13, 'V13_todas_definer', '19', COUNT(*)::TEXT, COUNT(*) = 19
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'api_precios_%' AND prosecdef;

INSERT INTO _v SELECT 14, 'V14_owner_postgres', '19', COUNT(*)::TEXT, COUNT(*) = 19
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'api_precios_%'
  AND r.rolname = 'postgres';

INSERT INTO _v SELECT 15, 'V15_search_path_exacto', '19', COUNT(*)::TEXT, COUNT(*) = 19
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'api_precios_%'
  AND 'search_path=pg_catalog, public, pg_temp' = ANY (proconfig);

-- lock_timeout: COTA DURA (se reimpone aunque el caller haga SET lock_timeout=0)
INSERT INTO _v SELECT 16, 'V16_lock_timeout_admitir', '1s', 'proconfig',
       EXISTS (SELECT 1 FROM pg_catalog.pg_proc
                WHERE pronamespace='public'::regnamespace AND proname='api_precios_admitir'
                  AND 'lock_timeout=1s' = ANY (proconfig));

INSERT INTO _v SELECT 17, 'V17_lock_timeout_exponer', '3', COUNT(*)::TEXT, COUNT(*) = 3
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'api_precios_%_exponer'
  AND 'lock_timeout=2s' = ANY (proconfig);

-- statement_timeout NO va en proconfig: es INERTE (no arma ni baja el timer).
-- Lo impone la Edge con SET LOCAL. Este check verifica que NO este.
INSERT INTO _v SELECT 18, 'V18_sin_statement_timeout_proconfig', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc, pg_catalog.unnest(proconfig) AS cfg
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'api_precios_%'
  AND cfg LIKE 'statement_timeout=%';

INSERT INTO _v SELECT 19, 'V19_core_stable', '2', COUNT(*)::TEXT, COUNT(*) = 2
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('api_precios_cotizar_core','api_precios_obtener_core')
  AND provolatile = 's';

-- D3 como PRIMERA sentencia ejecutable de admitir + 3 exponer + 3 core
INSERT INTO _v SELECT 20, 'V20_d3_primera_sentencia', '7', COUNT(*)::TEXT, COUNT(*) = 7
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('api_precios_admitir',
                  'api_precios_cotizar_exponer','api_precios_congelar_exponer','api_precios_obtener_exponer',
                  'api_precios_cotizar_core','api_precios_congelar_core','api_precios_obtener_core')
  AND pg_catalog.substring(
        pg_catalog.regexp_replace(prosrc, '(--[^\n]*\n|\s+)', ' ', 'g'),
        'BEGIN\s+(PERFORM\s+public\.api_precios_guard_sesion\(\);)') IS NOT NULL;

-- D3 cubre pg_class Y pg_type (pg_class es ciego a ENUM/DOMAIN/RANGE; pg_type a SEQUENCE)
INSERT INTO _v SELECT 21, 'V21_d3_class_y_type', 'true', 'pg_class + pg_type',
       (SELECT prosrc LIKE '%pg_catalog.pg_class%' AND prosrc LIKE '%pg_catalog.pg_type%'
          FROM pg_catalog.pg_proc
         WHERE pronamespace='public'::regnamespace AND proname='api_precios_guard_sesion');

-- ---------------------------------------------------------------------------
-- ACL
-- ---------------------------------------------------------------------------
-- El rol ejecuta EXACTAMENTE 5: admitir + 3 exponer + probe (temporal).
INSERT INTO _v SELECT 22, 'V22_rol_execute_exactas_5', '5', COUNT(*)::TEXT, COUNT(*) = 5
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'api_precios_%'
  AND pg_catalog.has_function_privilege('vita_precios_api', oid, 'EXECUTE');

INSERT INTO _v SELECT 23, 'V23_rol_execute_son_las_correctas', '5', COUNT(*)::TEXT, COUNT(*) = 5
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('api_precios_admitir','api_precios_cotizar_exponer',
                  'api_precios_congelar_exponer','api_precios_obtener_exponer',
                  'api_precios_probe_ambiente')
  AND pg_catalog.has_function_privilege('vita_precios_api', oid, 'EXECUTE');

-- Sin EXECUTE sobre core/helpers/purgas: NO puede saltear la admision.
INSERT INTO _v SELECT 24, 'V24_rol_sin_core_ni_helpers', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('api_precios_cotizar_core','api_precios_congelar_core','api_precios_obtener_core',
                  'api_precios_rl_consumir','api_precios_nonce_consumir','api_precios_guard_sesion',
                  'api_precios_gate_ambiente','api_precios_ticket_hash_v1',
                  'api_precios_validar_admision','api_precios_validar_payload',
                  'api_precios_ticket_purgar','api_precios_nonce_purgar',
                  'api_precios_rl_purgar','api_precios_idempotencia_purgar')
  AND pg_catalog.has_function_privilege('vita_precios_api', oid, 'EXECUTE');

INSERT INTO _v SELECT 25, 'V25_rol_sin_motor_b3', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%'
  AND pg_catalog.has_function_privilege('vita_precios_api', oid, 'EXECUTE');

INSERT INTO _v SELECT 26, 'V26_b4_sin_data_api', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc p, pg_catalog.unnest(ARRAY['anon','authenticated','service_role']) g(rol)
WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'api_precios_%'
  AND pg_catalog.has_function_privilege(g.rol, p.oid, 'EXECUTE');

-- Barrido: el rol no tiene NINGUN privilegio sobre NINGUNA tabla de public.
INSERT INTO _v SELECT 27, 'V27_rol_cero_privilegios_tabla', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_class c, pg_catalog.unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p(priv)
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v')
  AND pg_catalog.has_table_privilege('vita_precios_api', c.oid, p.priv);

-- ---------------------------------------------------------------------------
-- CRON  (4 jobs. NO hay watchdog: retirado por decision explicita.)
-- ---------------------------------------------------------------------------
INSERT INTO _v SELECT 28, 'V28_cron_4_jobs', '4', COUNT(*)::TEXT, COUNT(*) = 4
FROM cron.job WHERE jobname LIKE 'b4_purga_%';

INSERT INTO _v SELECT 29, 'V29_cron_activos', '4', COUNT(*)::TEXT, COUNT(*) = 4
FROM cron.job WHERE jobname LIKE 'b4_purga_%' AND active;

INSERT INTO _v SELECT 30, 'V30_cron_schedules', '4', COUNT(*)::TEXT, COUNT(*) = 4
FROM cron.job
WHERE (jobname, schedule) IN (
  ('b4_purga_ticket','*/5 * * * *'), ('b4_purga_nonce_s2s','*/5 * * * *'),
  ('b4_purga_rate_limit','*/10 * * * *'), ('b4_purga_idempotencia','0 * * * *'));

INSERT INTO _v SELECT 31, 'V31_sin_watchdog', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM cron.job WHERE command ILIKE '%pg_terminate_backend%';

-- ---------------------------------------------------------------------------
-- NO-REGRESION  (B4 es ADITIVO: B2A y B3 quedan intactos)
-- ---------------------------------------------------------------------------
INSERT INTO _v SELECT 32, 'V32_b3_13_funciones', '13', COUNT(*)::TEXT, COUNT(*) = 13
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%';

INSERT INTO _v
SELECT 33, 'V33_b3_fingerprint', '098f2fe7916e11ffa78cff37622b9064', fp,
       fp = '098f2fe7916e11ffa78cff37622b9064'
FROM (
  SELECT pg_catalog.md5(pg_catalog.string_agg(
           pg_catalog.md5(pg_catalog.replace(prosrc, pg_catalog.chr(13), '')),
           '' ORDER BY proname)) AS fp
  FROM pg_catalog.pg_proc
  WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%'
) x;

INSERT INTO _v SELECT 34, 'V34_b3_sin_definer', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%' AND prosecdef;

INSERT INTO _v SELECT 35, 'V35_b3_acl_intacta', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc p, pg_catalog.unnest(ARRAY['anon','authenticated','service_role']) g(rol)
WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'precios\_%'
  AND pg_catalog.has_function_privilege(g.rol, p.oid, 'EXECUTE');

INSERT INTO _v SELECT 36, 'V36_b2a_7_tablas', '7', COUNT(*)::TEXT, COUNT(*) = 7
FROM pg_catalog.pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
  AND c.relname IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia',
                    'noches_alta_demanda','overrides_precio','cotizaciones_precio','precios_auditoria');

INSERT INTO _v SELECT 37, 'V37_b2b_32_tarifas', '32', COUNT(*)::TEXT, COUNT(*) = 32
FROM tarifas_motor WHERE vigente_hasta IS NULL;

INSERT INTO _v SELECT 38, 'V38_temporadas_8', '8', COUNT(*)::TEXT, COUNT(*) = 8
FROM temporada_vigencia;

-- continuidad real: cada fecha_out_excl == fecha_in de la siguiente
INSERT INTO _v SELECT 39, 'V39_temporadas_continuas', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM (
  SELECT tv.fecha_out_excl,
         LEAD(tv.fecha_in) OVER (ORDER BY tv.fecha_in) AS sig
  FROM temporada_vigencia tv
) x
WHERE sig IS NOT NULL AND sig <> fecha_out_excl;

-- ---------------------------------------------------------------------------
-- SALIDA
-- ---------------------------------------------------------------------------
SELECT check_id, esperado, obtenido,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM _v ORDER BY orden;

SELECT COUNT(*) FILTER (WHERE ok)     AS pass,
       COUNT(*) FILTER (WHERE NOT ok) AS fail,
       CASE WHEN COUNT(*) FILTER (WHERE NOT ok) = 0
            THEN 'B4-0A VERIFY OK' ELSE 'B4-0A VERIFY CON FALLAS' END AS veredicto
FROM _v;

-- INFORMATIVO (no es criterio de FAIL): privilegio TEMPORARY sobre la base.
-- Se espera TRUE en varios roles: es el escenario que D1+D2+D3 neutralizan.
-- La revocacion global de TEMPORARY a PUBLIC queda como hardening SEPARADO,
-- fuera del alcance de B4 (requiere inventariar todos los consumidores).
SELECT r.rolname,
       pg_catalog.has_database_privilege(r.rolname, pg_catalog.current_database(), 'TEMPORARY') AS temporary
FROM pg_catalog.pg_roles r
WHERE r.rolname IN ('postgres','vita_precios_api','anon','authenticated','service_role','authenticator')
ORDER BY r.rolname;

COMMIT;
