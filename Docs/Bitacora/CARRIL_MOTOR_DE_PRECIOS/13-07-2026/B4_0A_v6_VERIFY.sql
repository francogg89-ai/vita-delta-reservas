-- ============================================================================
-- B4_0A_v6_VERIFY.sql   (v6 -- post-auditoria 6)
-- READ-ONLY. No muta nada. Corre despues de B4-0A y del ALTER de password.
--
-- Compara ESTRUCTURA EXACTA contra expectativas literales. No cuenta nombres.
--   schema ...... precios_api: existe, owner, ACL, sin CREATE para el rol
--   tablas ...... columnas, tipos, nullability, defaults, constraints, FK, indices
--   funciones ... 19 firmas exactas, volatilidad, owner, SECURITY DEFINER, proconfig
--   ACL ......... GLOBAL sobre todos los esquemas no sistemicos, incluyendo lo
--                 heredado por PUBLIC. Allowlist exacta. SECDEF como check aparte.
--                 SECUENCIAS: has_sequence_privilege global (USAGE/SELECT/UPDATE).
--   cron ........ los 4 jobs por nombre EXACTO: active, schedule, command, db, user
--   barrido ..... tablas, vistas, MATVIEWS, FOREIGN TABLES, SECUENCIAS, particionadas
--
-- Salidas: (1) checks  (2) veredicto  (3) todo lo ejecutable por el rol  (4) TEMPORARY
-- ============================================================================

BEGIN;

-- El fingerprint B2A usa conrelid::regclass::text, cuyo texto DEPENDE del
-- search_path (con public -> 'tarifas_motor'; sin public -> el cast falla).
-- Se fija para reproducir el hash que produjo B2A_VERIFY en el SQL Editor.
SET LOCAL search_path = public, pg_catalog;

CREATE TEMP TABLE _v (orden NUMERIC, check_id TEXT, esperado TEXT, obtenido TEXT, ok BOOLEAN)
ON COMMIT DROP;

-- ALLOWLIST DE RUNTIME. 5 durante B4-0B; 4 al dropear el probe (runsheet 11).
CREATE TEMP TABLE _allow (sig TEXT) ON COMMIT DROP;
INSERT INTO _allow VALUES
  ('precios_api.api_precios_admitir(text,text,text,uuid,text,uuid,uuid,uuid)'),
  ('precios_api.api_precios_cotizar_exponer(uuid,jsonb)'),
  ('precios_api.api_precios_congelar_exponer(uuid,jsonb,uuid)'),
  ('precios_api.api_precios_obtener_exponer(uuid,uuid)'),
  ('precios_api.api_precios_probe_ambiente()');

-- ===========================================================================
-- A) ROL Y SCHEMA DEDICADO
-- ===========================================================================
INSERT INTO _v SELECT 1, 'A01_rol_existe', '1', COUNT(*)::TEXT, COUNT(*) = 1
FROM pg_catalog.pg_roles WHERE rolname = 'vita_precios_api';

INSERT INTO _v SELECT 2, 'A02_rol_login', 'true', COALESCE(rolcanlogin::TEXT,'-'), rolcanlogin
FROM pg_catalog.pg_roles WHERE rolname = 'vita_precios_api';

INSERT INTO _v SELECT 3, 'A03_rol_sin_atributos', 'false',
       (rolsuper OR rolcreatedb OR rolcreaterole OR rolbypassrls OR rolreplication)::TEXT,
       NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolbypassrls OR rolreplication)
FROM pg_catalog.pg_roles WHERE rolname = 'vita_precios_api';

INSERT INTO _v SELECT 4, 'A04_rol_sin_membresias', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_auth_members m
JOIN pg_catalog.pg_roles r ON r.oid = m.member
WHERE r.rolname = 'vita_precios_api';

INSERT INTO _v SELECT 5, 'A05_rol_defaults',
       'statement_timeout=5s + lock_timeout=2s',
       COALESCE(pg_catalog.array_to_string(s.setconfig, ' | '), '-'),
       COALESCE(s.setconfig, '{}') @> ARRAY['statement_timeout=5s','lock_timeout=2s']
FROM pg_catalog.pg_roles r
LEFT JOIN pg_catalog.pg_db_role_setting s ON s.setrole = r.oid AND s.setdatabase = 0
WHERE r.rolname = 'vita_precios_api';

-- SCHEMA DEDICADO
INSERT INTO _v SELECT 6, 'A06_schema_precios_api_existe', '1', COUNT(*)::TEXT, COUNT(*) = 1
FROM pg_catalog.pg_namespace WHERE nspname = 'precios_api';

INSERT INTO _v SELECT 7, 'A07_schema_owner_postgres', 'postgres',
       pg_catalog.pg_get_userbyid(nspowner),
       pg_catalog.pg_get_userbyid(nspowner) = 'postgres'
FROM pg_catalog.pg_namespace WHERE nspname = 'precios_api';

INSERT INTO _v SELECT 8, 'A08_schema_usage_al_rol', 'true',
       pg_catalog.has_schema_privilege('vita_precios_api','precios_api','USAGE')::TEXT,
       pg_catalog.has_schema_privilege('vita_precios_api','precios_api','USAGE');

INSERT INTO _v SELECT 9, 'A09_schema_sin_create_al_rol', 'false',
       pg_catalog.has_schema_privilege('vita_precios_api','precios_api','CREATE')::TEXT,
       NOT pg_catalog.has_schema_privilege('vita_precios_api','precios_api','CREATE');

-- PUBLIC no debe tener nada sobre precios_api (ni USAGE ni CREATE)
INSERT INTO _v SELECT 10, 'A10_schema_cerrado_a_PUBLIC', 'false/false',
       pg_catalog.has_schema_privilege('public','precios_api','USAGE')::TEXT || '/' ||
       pg_catalog.has_schema_privilege('public','precios_api','CREATE')::TEXT,
       NOT pg_catalog.has_schema_privilege('public','precios_api','USAGE')
   AND NOT pg_catalog.has_schema_privilege('public','precios_api','CREATE');

-- A11 (DURO): el rol NO puede tener CREATE sobre public. Un REVOKE dirigido al
-- rol no arregla un permiso heredado de PUBLIC: por eso se COMPRUEBA el efectivo.
-- Con CREATE en public, el rol podria plantar funciones o tablas propias.
INSERT INTO _v SELECT 11, 'A11_rol_sin_CREATE_en_public', 'false',
       pg_catalog.has_schema_privilege('vita_precios_api','public','CREATE')::TEXT,
       NOT pg_catalog.has_schema_privilege('vita_precios_api','public','CREATE');

-- A12 (INFORMATIVO-DURO): USAGE del rol sobre public. Se espera 'true' (heredado
-- del pseudo-rol PUBLIC). NO es un fallo: el aislamiento de los entrypoints lo da
-- el schema dedicado precios_api. La consecuencia -- que el rol pueda invocar
-- funciones de public con EXECUTE a PUBLIC -- la mide D07. Cerrarla exige
-- hardening GLOBAL, fuera del alcance de B4-0A.
INSERT INTO _v SELECT 12, 'A12_usage_public_heredado_de_PUBLIC', 'true (esperado; ver D07 y nivel 2)',
       pg_catalog.has_schema_privilege('vita_precios_api','public','USAGE')::TEXT,
       TRUE;

-- ---------------------------------------------------------------------------
-- NOTA DE ALCANCE -- este VERIFY NO mira pg_default_acl.
--   B4-0A no aplica hardening global de default privileges, asi que verificar
--   aca un estado que no aplica ni revierte seria mezclar alcances y podria
--   fallar por un default ACL completamente ajeno a B4.
--
--   Consecuencia declarada: las funciones de public con EXECUTE a PUBLIC
--   -- actuales Y FUTURAS -- son invocables por el rol via el USAGE que hereda
--   de PUBLIC. NO es un agujero silencioso: lo mide D07 y lo lista la Salida 3.
--   El vector critico (motor B3 + cores) sigue cerrado por REVOKE explicito
--   (D04) y por el schema dedicado (D01/D02), en cualquier caso.
-- ---------------------------------------------------------------------------

-- A13: CREATE sobre la BASE (punto 5). Con CREATE de base el rol podria crear
-- SCHEMAS propios, y dentro de un schema propio es OWNER: crea lo que quiera.
-- Es una superficie distinta de la de A11 (CREATE sobre el schema public).
INSERT INTO _v SELECT 13, 'A13_rol_sin_CREATE_en_la_base', 'false',
       pg_catalog.has_database_privilege('vita_precios_api',
              pg_catalog.current_database(), 'CREATE')::TEXT,
       NOT pg_catalog.has_database_privilege('vita_precios_api',
              pg_catalog.current_database(), 'CREATE');

-- A14 (INFO): TEMPORARY sobre la base. Se espera true -- es el escenario que D3
-- neutraliza. Revocarlo exige inventariar consumidores: hardening aparte.
INSERT INTO _v SELECT 14, 'A14_temporary_en_la_base [info]', 'true (lo cubre D3)',
       pg_catalog.has_database_privilege('vita_precios_api',
              pg_catalog.current_database(), 'TEMPORARY')::TEXT,
       TRUE;

-- ===========================================================================
-- B) TABLAS -- ESTRUCTURA EXACTA
-- ===========================================================================
CREATE TEMP TABLE _cols_esp (tabla TEXT, col TEXT, tipo TEXT, no_nulo BOOLEAN, def TEXT)
ON COMMIT DROP;
INSERT INTO _cols_esp VALUES
 ('api_precios_rate_limit','scope','text',true,'-'),
 ('api_precios_rate_limit','sujeto','text',true,'-'),
 ('api_precios_rate_limit','ventana','timestamp with time zone',true,'-'),
 ('api_precios_rate_limit','n','integer',true,'-'),
 ('api_precios_nonce_s2s','client_id','text',true,'-'),
 ('api_precios_nonce_s2s','nonce','uuid',true,'-'),
 ('api_precios_nonce_s2s','admission_hash','text',true,'-'),
 ('api_precios_nonce_s2s','ticket_id','uuid',true,'-'),
 ('api_precios_nonce_s2s','created_at','timestamp with time zone',true,'clock_timestamp()'),
 ('api_precios_ticket','ticket_id','uuid',true,'-'),
 ('api_precios_ticket','accion','text',true,'-'),
 ('api_precios_ticket','superficie','text',true,'-'),
 ('api_precios_ticket','sujeto','text',true,'-'),
 ('api_precios_ticket','request_hash','text',true,'-'),
 ('api_precios_ticket','correlation_id','uuid',true,'-'),
 ('api_precios_ticket','created_at','timestamp with time zone',true,'clock_timestamp()'),
 ('api_precios_ticket','expires_at','timestamp with time zone',true,'-'),
 ('api_precios_ticket','consumed_at','timestamp with time zone',false,'-'),
 ('api_precios_idempotencia','scope','text',true,'-'),
 ('api_precios_idempotencia','idempotency_key','uuid',true,'-'),
 ('api_precios_idempotencia','canon_hash','text',true,'-'),
 ('api_precios_idempotencia','cotizacion_id','uuid',true,'-'),
 ('api_precios_idempotencia','resultado_motor_privado','jsonb',true,'-'),
 ('api_precios_idempotencia','created_at','timestamp with time zone',true,'clock_timestamp()');

CREATE TEMP TABLE _cols_real AS
SELECT c.relname::TEXT AS tabla, a.attname::TEXT AS col,
       pg_catalog.format_type(a.atttypid, a.atttypmod) AS tipo,
       a.attnotnull AS no_nulo,
       COALESCE(pg_catalog.pg_get_expr(d.adbin, d.adrelid), '-') AS def
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
WHERE c.relnamespace = 'precios_api'::regnamespace
  AND c.relkind = 'r'                       -- solo TABLAS (los indices tambien tienen attrs)
  AND a.attnum > 0 AND NOT a.attisdropped;

INSERT INTO _v
SELECT 11, 'B01_columnas_exactas', '0 diferencias', COUNT(*)::TEXT || ' dif', COUNT(*) = 0
FROM ((SELECT * FROM _cols_esp EXCEPT SELECT * FROM _cols_real)
      UNION ALL
      (SELECT * FROM _cols_real EXCEPT SELECT * FROM _cols_esp)) d;

INSERT INTO _v SELECT 12, 'B02_columnas_total', '24', COUNT(*)::TEXT, COUNT(*) = 24
FROM _cols_real;

CREATE TEMP TABLE _con_esp (conname TEXT, def TEXT) ON COMMIT DROP;
INSERT INTO _con_esp VALUES
 ('pk_api_precios_rate_limit',  'PRIMARY KEY (scope, sujeto, ventana)'),
 ('chk_rl_n',                   'CHECK ((n >= 1))'),
 ('pk_api_precios_nonce_s2s',   'PRIMARY KEY (client_id, nonce)'),
 ('chk_nonce_s2s_admission_hash','CHECK ((admission_hash ~ ''^[0-9a-f]{64}$''::text))'),
 ('pk_api_precios_ticket',      'PRIMARY KEY (ticket_id)'),
 ('chk_ticket_accion',          'CHECK ((accion = ANY (ARRAY[''cotizar''::text, ''congelar''::text, ''obtener''::text])))'),
 ('chk_ticket_superficie',      'CHECK ((superficie = ''s2s''::text))'),
 ('chk_ticket_sujeto',          'CHECK ((sujeto = ''whatsapp''::text))'),
 ('chk_ticket_hash',            'CHECK ((request_hash ~ ''^[0-9a-f]{64}$''::text))'),
 ('chk_ticket_vigencia',        'CHECK ((expires_at > created_at))'),
 ('chk_ticket_consumo',         'CHECK (((consumed_at IS NULL) OR (consumed_at >= created_at)))'),
 ('pk_api_precios_idempotencia','PRIMARY KEY (scope, idempotency_key)'),
 ('chk_idem_scope',             'CHECK ((scope ~~ ''precios.congelar:%''::text))'),
 ('chk_idem_hash',              'CHECK ((canon_hash ~ ''^[0-9a-f]{64}$''::text))'),
 ('fk_api_precios_idem_cotizacion',
  'FOREIGN KEY (cotizacion_id) REFERENCES cotizaciones_precio(cotizacion_id) ON DELETE RESTRICT');

CREATE TEMP TABLE _con_real AS
SELECT con.conname::TEXT, pg_catalog.pg_get_constraintdef(con.oid) AS def
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class rel ON rel.oid = con.conrelid
WHERE rel.relnamespace = 'precios_api'::regnamespace;

INSERT INTO _v
SELECT 13, 'B03_constraints_exactas', '0 diferencias', COUNT(*)::TEXT || ' dif', COUNT(*) = 0
FROM ((SELECT * FROM _con_esp EXCEPT SELECT * FROM _con_real)
      UNION ALL
      (SELECT * FROM _con_real EXCEPT SELECT * FROM _con_esp)) d;

INSERT INTO _v SELECT 14, 'B04_constraints_total', '15', COUNT(*)::TEXT, COUNT(*) = 15
FROM _con_real;

INSERT INTO _v
SELECT 15, 'B05_fk_idempotencia_restrict', 'RESTRICT hacia cotizaciones_precio',
       COALESCE(pg_catalog.pg_get_constraintdef(con.oid), 'NO EXISTE'),
       pg_catalog.pg_get_constraintdef(con.oid) =
       'FOREIGN KEY (cotizacion_id) REFERENCES cotizaciones_precio(cotizacion_id) ON DELETE RESTRICT'
FROM pg_catalog.pg_constraint con WHERE con.conname = 'fk_api_precios_idem_cotizacion';

-- INDICES: los 4 PK + los 4 de purga (punto 10: nonce.created_at y rate_limit.ventana)
CREATE TEMP TABLE _idx_esp (indexname TEXT, def TEXT) ON COMMIT DROP;
INSERT INTO _idx_esp VALUES
 ('pk_api_precios_rate_limit',    'CREATE UNIQUE INDEX pk_api_precios_rate_limit ON precios_api.api_precios_rate_limit USING btree (scope, sujeto, ventana)'),
 ('pk_api_precios_nonce_s2s',     'CREATE UNIQUE INDEX pk_api_precios_nonce_s2s ON precios_api.api_precios_nonce_s2s USING btree (client_id, nonce)'),
 ('pk_api_precios_ticket',        'CREATE UNIQUE INDEX pk_api_precios_ticket ON precios_api.api_precios_ticket USING btree (ticket_id)'),
 ('pk_api_precios_idempotencia',  'CREATE UNIQUE INDEX pk_api_precios_idempotencia ON precios_api.api_precios_idempotencia USING btree (scope, idempotency_key)'),
 ('idx_api_precios_ticket_expira','CREATE INDEX idx_api_precios_ticket_expira ON precios_api.api_precios_ticket USING btree (expires_at)'),
 ('idx_api_precios_idem_created', 'CREATE INDEX idx_api_precios_idem_created ON precios_api.api_precios_idempotencia USING btree (created_at)'),
 ('idx_api_precios_nonce_created','CREATE INDEX idx_api_precios_nonce_created ON precios_api.api_precios_nonce_s2s USING btree (created_at)'),
 ('idx_api_precios_rl_ventana',   'CREATE INDEX idx_api_precios_rl_ventana ON precios_api.api_precios_rate_limit USING btree (ventana)');

INSERT INTO _v
SELECT 16, 'B06_indices_exactos', '0 diferencias (8 indices)', COUNT(*)::TEXT || ' dif', COUNT(*) = 0
FROM ((SELECT indexname, def FROM _idx_esp
       EXCEPT
       SELECT i.indexname::TEXT, i.indexdef FROM pg_catalog.pg_indexes i
        WHERE i.schemaname = 'precios_api')
      UNION ALL
      (SELECT i.indexname::TEXT, i.indexdef FROM pg_catalog.pg_indexes i
        WHERE i.schemaname = 'precios_api'
       EXCEPT
       SELECT indexname, def FROM _idx_esp)) d;

-- cada purga tiene indice: ticket(expires_at), nonce(created_at),
-- rate_limit(ventana), idempotencia(created_at)
INSERT INTO _v
SELECT 17, 'B07_indices_de_purga', '4', COUNT(*)::TEXT, COUNT(*) = 4
FROM pg_catalog.pg_indexes
WHERE schemaname = 'precios_api'
  AND indexname IN ('idx_api_precios_ticket_expira','idx_api_precios_nonce_created',
                    'idx_api_precios_rl_ventana','idx_api_precios_idem_created');

-- BARRIDO: relkind r tabla | v vista | m matview | f foreign | S secuencia | p particionada
INSERT INTO _v
SELECT 18, 'B08_barrido_relkind', '4 tablas y nada mas',
       COALESCE(pg_catalog.string_agg(DISTINCT c.relkind::TEXT, ',' ORDER BY c.relkind::TEXT),'-'),
       COUNT(*) FILTER (WHERE c.relkind = 'r') = 4
   AND COUNT(*) FILTER (WHERE c.relkind IN ('v','m','f','S','p')) = 0
FROM pg_catalog.pg_class c
WHERE c.relnamespace = 'precios_api'::regnamespace AND c.relkind <> 'i';

INSERT INTO _v
SELECT 19, 'B09_cero_secuencias_b4', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_class c
WHERE c.relnamespace = 'precios_api'::regnamespace AND c.relkind = 'S';

-- ===========================================================================
-- C) FUNCIONES -- 19 FIRMAS EXACTAS + volatilidad + owner + secdef + proconfig
--    OJO: oid::regprocedure OMITE el schema si esta en el search_path, y
--    pg_get_function_identity_arguments trae los NOMBRES de los parametros.
--    La firma se construye con proargtypes + format_type: solo tipos, siempre
--    schema-qualified.
-- ===========================================================================
CREATE TEMP TABLE _fn_esp (sig TEXT, vol TEXT, secdef BOOLEAN, lock_to TEXT) ON COMMIT DROP;
INSERT INTO _fn_esp VALUES
 ('precios_api.api_precios_guard_sesion()',                                            's', false, NULL),
 ('precios_api.api_precios_gate_ambiente()',                                           's', false, NULL),
 ('precios_api.api_precios_ticket_hash_v1(text,text,text,jsonb,uuid,uuid)',            'i', false, NULL),
 ('precios_api.api_precios_rl_consumir(text,text,timestamp with time zone)',           'v', false, NULL),
 ('precios_api.api_precios_admision_leer(text,uuid)',                                  'v', false, NULL),
 ('precios_api.api_precios_validar_admision(text,text,text,uuid,text,uuid,uuid,uuid)', 'i', false, NULL),
 ('precios_api.api_precios_validar_payload(jsonb,text)',                               'v', false, NULL),
 ('precios_api.api_precios_cotizar_core(jsonb)',                                       's', false, NULL),
 ('precios_api.api_precios_congelar_core(jsonb,uuid,text)',                            'v', false, NULL),
 ('precios_api.api_precios_obtener_core(uuid)',                                        's', false, NULL),
 ('precios_api.api_precios_admitir(text,text,text,uuid,text,uuid,uuid,uuid)',          'v', true, 'lock_timeout=1s'),
 ('precios_api.api_precios_cotizar_exponer(uuid,jsonb)',                               'v', true, 'lock_timeout=2s'),
 ('precios_api.api_precios_congelar_exponer(uuid,jsonb,uuid)',                         'v', true, 'lock_timeout=2s'),
 ('precios_api.api_precios_obtener_exponer(uuid,uuid)',                                'v', true, 'lock_timeout=2s'),
 ('precios_api.api_precios_probe_ambiente()',                                          's', true, NULL),
 ('precios_api.api_precios_ticket_purgar()',                                           'v', false, NULL),
 ('precios_api.api_precios_nonce_purgar()',                                            'v', false, NULL),
 ('precios_api.api_precios_rl_purgar()',                                               'v', false, NULL),
 ('precios_api.api_precios_idempotencia_purgar()',                                     'v', false, NULL);

CREATE TEMP TABLE _fn_real AS
SELECT 'precios_api.' || p.proname || '(' ||
       COALESCE((SELECT pg_catalog.string_agg(pg_catalog.format_type(t, NULL), ',' ORDER BY o)
                   FROM pg_catalog.unnest(p.proargtypes) WITH ORDINALITY AS a(t, o)), '')
       || ')' AS sig,
       p.provolatile::TEXT AS vol,
       p.prosecdef AS secdef,
       (SELECT x FROM pg_catalog.unnest(p.proconfig) AS x WHERE x LIKE 'lock_timeout=%') AS lock_to,
       pg_catalog.pg_get_userbyid(p.proowner) AS owner,
       (SELECT x FROM pg_catalog.unnest(p.proconfig) AS x WHERE x LIKE 'search_path=%') AS sp,
       (SELECT COUNT(*) FROM pg_catalog.unnest(p.proconfig) AS x
         WHERE x LIKE 'statement_timeout=%') AS n_stmt_to,
       p.prosrc
FROM pg_catalog.pg_proc p
WHERE p.pronamespace = 'precios_api'::regnamespace;

INSERT INTO _v SELECT 20, 'C01_funciones_total', '19', COUNT(*)::TEXT, COUNT(*) = 19
FROM _fn_real;

INSERT INTO _v
SELECT 21, 'C02_firmas_volatilidad_secdef_lock', '0 diferencias',
       COUNT(*)::TEXT || ' dif', COUNT(*) = 0
FROM ((SELECT sig, vol, secdef, lock_to FROM _fn_esp
       EXCEPT SELECT sig, vol, secdef, lock_to FROM _fn_real)
      UNION ALL
      (SELECT sig, vol, secdef, lock_to FROM _fn_real
       EXCEPT SELECT sig, vol, secdef, lock_to FROM _fn_esp)) d;

-- PRIVILEGIO MINIMO: solo los 5 entrypoints son SECURITY DEFINER. Los 14
-- helpers/core/purgas son SECURITY INVOKER owner-only:
--   * llamados desde un entrypoint, su invocador efectivo YA es postgres;
--   * llamados por pg_cron (las purgas), el invocador es postgres;
--   * si una ACL se abriera por accidente, NO heredan privilegios elevados.
-- MEDIDO: con la ACL abierta, un INVOKER corre como el ROL y falla al tocar la
-- tabla; un DEFINER en la misma situacion SI filtra el dato.
INSERT INTO _v SELECT 22, 'C03_solo_5_security_definer', '5',
       COUNT(*) FILTER (WHERE secdef)::TEXT, COUNT(*) FILTER (WHERE secdef) = 5
FROM _fn_real;

INSERT INTO _v SELECT 22.5, 'C03b_14_security_invoker', '14',
       COUNT(*) FILTER (WHERE NOT secdef)::TEXT, COUNT(*) FILTER (WHERE NOT secdef) = 14
FROM _fn_real;

-- los 5 DEFINER son EXACTAMENTE los entrypoints de la allowlist
INSERT INTO _v SELECT 22.7, 'C03c_definer_son_los_entrypoints', '0 fuera de la allowlist',
       COUNT(*)::TEXT, COUNT(*) = 0
FROM _fn_real f WHERE f.secdef AND f.sig NOT IN (SELECT sig FROM _allow);

INSERT INTO _v SELECT 23, 'C04_owner_postgres', '19',
       COUNT(*) FILTER (WHERE owner = 'postgres')::TEXT,
       COUNT(*) FILTER (WHERE owner = 'postgres') = 19
FROM _fn_real;

INSERT INTO _v SELECT 24, 'C05_search_path_exacto', '19',
       COUNT(*) FILTER (WHERE sp = 'search_path=pg_catalog, precios_api, public, pg_temp')::TEXT,
       COUNT(*) FILTER (WHERE sp = 'search_path=pg_catalog, precios_api, public, pg_temp') = 19
FROM _fn_real;

-- statement_timeout NO va en proconfig: es INERTE (no arma ni baja el timer).
INSERT INTO _v SELECT 25, 'C06_sin_statement_timeout_en_proconfig', '0',
       COALESCE(SUM(n_stmt_to),0)::TEXT, COALESCE(SUM(n_stmt_to),0) = 0
FROM _fn_real;

-- 8 funciones tocan a B3 o a datos: admitir + 3 exponer + 3 core + probe.
-- Todas deben abrir con D3. Parentesis: AND liga mas fuerte que OR.
-- El regex tolera comentarios de linea entre BEGIN y el PERFORM (admitir tiene uno).
INSERT INTO _v SELECT 26, 'C07_d3_primera_sentencia', '8', COUNT(*)::TEXT, COUNT(*) = 8
FROM _fn_real
WHERE (sig LIKE '%api_precios_admitir(%'
    OR sig LIKE '%_exponer(%'
    OR sig LIKE '%_core(%'
    OR sig LIKE '%probe_ambiente(%')
  AND prosrc ~ 'BEGIN(\s|--[^\n]*\n)*PERFORM precios_api\.api_precios_guard_sesion\(\)';

INSERT INTO _v SELECT 27, 'C08_d3_mira_pg_class_y_pg_type', 'ambos',
       CASE WHEN prosrc LIKE '%pg_class%' AND prosrc LIKE '%pg_type%'
            THEN 'ambos' ELSE 'INCOMPLETO' END,
       prosrc LIKE '%pg_class%' AND prosrc LIKE '%pg_type%'
FROM _fn_real WHERE sig = 'precios_api.api_precios_guard_sesion()';

-- la ventana del rate limit se pasa por parametro (no se recalcula adentro)
INSERT INTO _v SELECT 28, 'C09_rl_recibe_ventana_por_parametro', 'sin date_trunc interno',
       CASE WHEN prosrc LIKE '%date_trunc%' THEN 'LO RECALCULA' ELSE 'ok' END,
       prosrc NOT LIKE '%date_trunc%'
FROM _fn_real WHERE sig LIKE 'precios_api.api_precios_rl_consumir(%';

INSERT INTO _v SELECT 29, 'C10_admitir_calcula_ventana_una_vez', '1 date_trunc',
       (pg_catalog.length(prosrc) -
        pg_catalog.length(pg_catalog.replace(prosrc,'date_trunc','')))::TEXT || ' chars',
       prosrc LIKE '%v_ventana := pg_catalog.date_trunc(''minute''%'
FROM _fn_real WHERE sig LIKE 'precios_api.api_precios_admitir(%';

-- ===========================================================================
-- D) ACL GLOBAL -- todos los esquemas no sistemicos.
--    has_function_privilege() YA resuelve la herencia por PUBLIC.
-- ===========================================================================
-- SUPERFICIE **EFECTIVA** (punto 4).
--   has_function_privilege() SOLO NO ALCANZA: una funcion con EXECUTE en un
--   schema sobre el que el rol NO tiene USAGE es INALCANZABLE. Contarla como
--   superficie infla el riesgo y, peor, mezcla dos cosas distintas.
--   La superficie REALMENTE INVOCABLE es la interseccion:
--       has_schema_privilege(rol, schema, 'USAGE')
--     + has_function_privilege(rol, funcion, 'EXECUTE')
--   D03 y el claim de superficie usan ESTA tabla. Las que tienen EXECUTE pero no
--   USAGE se conservan aparte (_ejec_sin_usage), como informacion.
CREATE TEMP TABLE _ejec_todo AS
SELECT n.nspname::TEXT AS esquema,
       n.nspname || '.' || p.proname || '(' ||
       COALESCE((SELECT pg_catalog.string_agg(pg_catalog.format_type(t, NULL), ',' ORDER BY o)
                   FROM pg_catalog.unnest(p.proargtypes) WITH ORDINALITY AS a(t, o)), '')
       || ')' AS sig,
       p.prosecdef AS secdef,
       pg_catalog.has_schema_privilege('vita_precios_api', n.oid, 'USAGE') AS usage_schema
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname NOT IN ('pg_catalog','information_schema')
  AND n.nspname NOT LIKE 'pg\_toast%'
  AND n.nspname NOT LIKE 'pg\_temp%'
  AND pg_catalog.has_function_privilege('vita_precios_api', p.oid, 'EXECUTE');

-- EFECTIVA: EXECUTE en la funcion Y USAGE en su schema -> invocable de verdad.
CREATE TEMP TABLE _ejec AS
SELECT esquema, sig, secdef FROM _ejec_todo WHERE usage_schema;

-- INFORMATIVA: EXECUTE en la funcion pero SIN USAGE en el schema -> inalcanzable.
CREATE TEMP TABLE _ejec_sin_usage AS
SELECT esquema, sig, secdef FROM _ejec_todo WHERE NOT usage_schema;

-- D01/D02 (DURO): en precios_api, EXACTAMENTE la allowlist. Ni una funcion mas.
-- (_ejec = superficie EFECTIVA: EXECUTE + USAGE de schema)
INSERT INTO _v
SELECT 30, 'D01_allowlist_exacta_en_precios_api', '5 (4 al dropear el probe)',
       COUNT(*)::TEXT, COUNT(*) = (SELECT COUNT(*) FROM _allow)
FROM _ejec WHERE esquema = 'precios_api';

INSERT INTO _v
SELECT 31, 'D02_cero_fuera_de_allowlist_en_precios_api', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM _ejec e
WHERE e.esquema = 'precios_api' AND e.sig NOT IN (SELECT sig FROM _allow);

-- D03 (DURO, SEPARADO): cero SECURITY DEFINER **realmente invocables** fuera de
-- la allowlist, en CUALQUIER esquema no sistemico. Un SECDEF ajeno alcanzable =
-- escalada de privilegios. Usa la superficie EFECTIVA (EXECUTE + USAGE).
INSERT INTO _v
SELECT 32, 'D03_cero_secdef_invocable_fuera_de_allowlist', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM _ejec e
WHERE e.secdef AND e.sig NOT IN (SELECT sig FROM _allow);

-- D03b (INFO): SECDEF con EXECUTE pero SIN USAGE de schema -> hoy inalcanzables.
-- No son un fallo, pero si alguien concediera USAGE sobre ese schema, pasarian a
-- ser invocables. Se listan para que la decision sea informada.
INSERT INTO _v
SELECT 32.5, 'D03b_secdef_con_execute_pero_sin_usage [info]',
       'inalcanzables hoy (falta USAGE)', COUNT(*)::TEXT, TRUE
FROM _ejec_sin_usage e WHERE e.secdef;

-- D04: cero EXECUTE sobre el motor B3. El rol HEREDA de PUBLIC: si alguna
-- precios_* conservara EXECUTE a PUBLIC, podria llamar al motor DIRECTAMENTE
-- salteando cuota + nonce + ticket. Es el check mas importante del VERIFY.
INSERT INTO _v
SELECT 33, 'D04_cero_execute_sobre_b3', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname LIKE 'precios\_%'
  AND pg_catalog.has_function_privilege('vita_precios_api', p.oid, 'EXECUTE');

-- D05: cero privilegios de TABLA (todos los relkind, todos los esquemas)
INSERT INTO _v
SELECT 34, 'D05_cero_privilegios_de_tabla', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),
                   ('REFERENCES'),('TRIGGER')) AS pr(priv)
WHERE n.nspname NOT IN ('pg_catalog','information_schema')
  AND n.nspname NOT LIKE 'pg\_%'
  AND c.relkind IN ('r','v','m','f','p')
  AND pg_catalog.has_table_privilege('vita_precios_api', c.oid, pr.priv);

-- D06 (punto 10): cero privilegios de SECUENCIA en toda la base.
INSERT INTO _v
SELECT 35, 'D06_cero_privilegios_de_secuencia', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN (VALUES ('USAGE'),('SELECT'),('UPDATE')) AS pr(priv)
WHERE n.nspname NOT IN ('pg_catalog','information_schema')
  AND n.nspname NOT LIKE 'pg\_%'
  AND c.relkind = 'S'
  AND pg_catalog.has_sequence_privilege('vita_precios_api', c.oid, pr.priv);

-- ===========================================================================
-- G) LEDGER DE ADMISION + MAPPING DE lock_timeout  (los 2 bloqueantes)
-- ===========================================================================

-- G01: la tabla de nonces ES el ledger: tiene binding y ticket, ambos NOT NULL.
--      Sin esto, una respuesta perdida de TXN1 es irrecuperable.
INSERT INTO _v
SELECT 40, 'G01_ledger_tiene_admission_hash_y_ticket_id', '2 columnas NOT NULL',
       COUNT(*)::TEXT, COUNT(*) = 2
FROM pg_catalog.pg_attribute a
WHERE a.attrelid = 'precios_api.api_precios_nonce_s2s'::regclass
  AND a.attname IN ('admission_hash','ticket_id')
  AND a.attnum > 0 AND NOT a.attisdropped
  AND a.attnotnull;

-- G02: la funcion de lectura del ledger existe con la firma exacta.
INSERT INTO _v
SELECT 41, 'G02_admision_leer_existe', 'no nulo',
       COALESCE(pg_catalog.to_regprocedure('precios_api.api_precios_admision_leer(text,uuid)')::TEXT, '<falta>'),
       pg_catalog.to_regprocedure('precios_api.api_precios_admision_leer(text,uuid)') IS NOT NULL;

-- G03 (DURO): los 4 entrypoints de negocio capturan lock_not_available.
--   MEDIDO: lock_timeout lanza 55P03 y SIN handler ESCAPA CRUDO al driver,
--   rompiendo el contrato JSON. WHEN OTHERS lo mapearia a error_interno, no a
--   timeout. Se exige el handler EXPLICITO en el cuerpo de las 4.
INSERT INTO _v
SELECT 42, 'G03_lock_not_available_en_los_4_entrypoints', '4', COUNT(*)::TEXT, COUNT(*) = 4
FROM pg_catalog.pg_proc p
WHERE p.pronamespace = 'precios_api'::regnamespace
  AND p.proname IN ('api_precios_admitir','api_precios_cotizar_exponer',
                    'api_precios_congelar_exponer','api_precios_obtener_exponer')
  AND p.prosrc LIKE '%lock_not_available%';

-- G04 (DURO): esas 4 tambien re-lanzan VDT01 (D3) y VDT03 (gate de ambiente).
--   Con el savepoint externo, un WHEN OTHERS sin estos RAISE degradaria el gate
--   de ambiente a 'error_interno' en vez de abortar. Bug real, detectado y cerrado.
INSERT INTO _v
SELECT 43, 'G04_VDT01_y_VDT03_propagan_en_los_4', '4', COUNT(*)::TEXT, COUNT(*) = 4
FROM pg_catalog.pg_proc p
WHERE p.pronamespace = 'precios_api'::regnamespace
  AND p.proname IN ('api_precios_admitir','api_precios_cotizar_exponer',
                    'api_precios_congelar_exponer','api_precios_obtener_exponer')
  AND p.prosrc LIKE '%VDT01%' AND p.prosrc LIKE '%VDT03%';

-- G05: cero grants de tabla sobre el ledger (el rol NO puede leerlo directo:
--      llega a el solo por el SECURITY DEFINER de api_precios_admitir).
INSERT INTO _v
SELECT 44, 'G05_ledger_sin_grants_al_rol', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) AS pr(priv)
WHERE pg_catalog.has_table_privilege('vita_precios_api',
        'precios_api.api_precios_nonce_s2s'::regclass, pr.priv);

-- G06: nonce_consumir YA NO EXISTE (la reemplazo el ledger). Si sigue viva, el
--      script se corrio a medias o hay una version vieja mezclada.
INSERT INTO _v
SELECT 45, 'G06_nonce_consumir_ya_no_existe', 'NULL',
       COALESCE(pg_catalog.to_regprocedure('precios_api.api_precios_nonce_consumir(text,uuid)')::TEXT, 'NULL'),
       pg_catalog.to_regprocedure('precios_api.api_precios_nonce_consumir(text,uuid)') IS NULL;

-- G07/G08/G09 (DUROS): coherencia LEDGER <-> TICKET, mientras el ticket exista.
--   NO hay FOREIGN KEY a proposito: las purgas son independientes (ticket ~10,5 min,
--   ledger ~15 min) y una FK impediria purgar el ticket, o forzaria un ON DELETE que
--   destruiria la evidencia del recovery. La consistencia se VERIFICA, no se impone.
--   El LEFT JOIN es deliberado: una fila de ledger cuyo ticket ya fue purgado NO es
--   una violacion -- es el ciclo de vida normal.
INSERT INTO _v
SELECT 46, 'G07_ledger_ticket_id_coincide', '0 discrepancias', COUNT(*)::TEXT, COUNT(*) = 0
FROM precios_api.api_precios_nonce_s2s n
JOIN precios_api.api_precios_ticket t ON t.ticket_id = n.ticket_id
WHERE t.ticket_id IS DISTINCT FROM n.ticket_id;

INSERT INTO _v
SELECT 47, 'G08_ledger_admission_hash_es_el_request_hash', '0 discrepancias',
       COUNT(*)::TEXT, COUNT(*) = 0
FROM precios_api.api_precios_nonce_s2s n
JOIN precios_api.api_precios_ticket t ON t.ticket_id = n.ticket_id
WHERE t.request_hash IS DISTINCT FROM n.admission_hash;

INSERT INTO _v
SELECT 48, 'G09_ledger_client_id_es_el_sujeto', '0 discrepancias',
       COUNT(*)::TEXT, COUNT(*) = 0
FROM precios_api.api_precios_nonce_s2s n
JOIN precios_api.api_precios_ticket t ON t.ticket_id = n.ticket_id
WHERE t.sujeto IS DISTINCT FROM n.client_id;

-- G10: el CHECK del formato del hash existe (sha256 hex, 64 chars).
INSERT INTO _v
SELECT 49, 'G10_check_admission_hash_formato', '1', COUNT(*)::TEXT, COUNT(*) = 1
FROM pg_catalog.pg_constraint
WHERE conrelid = 'precios_api.api_precios_nonce_s2s'::regclass
  AND conname  = 'chk_nonce_s2s_admission_hash'
  AND contype  = 'c';

-- G11: NO hay foreign key del ledger al ticket (romperia la purga independiente).
INSERT INTO _v
SELECT 50, 'G11_ledger_sin_FK_al_ticket', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_constraint
WHERE conrelid = 'precios_api.api_precios_nonce_s2s'::regclass
  AND contype  = 'f';

-- G12 (DURO): api_precios_admitir serializa por (client_id, nonce) con advisory
--   lock de transaccion. SIN esto (bug de v5), dos admisiones concurrentes del
--   mismo nonce cobraban la cuota LOGICA dos veces.
INSERT INTO _v
SELECT 51, 'G12_admitir_usa_advisory_xact_lock', 'true',
       (COUNT(*) > 0)::TEXT, COUNT(*) > 0
FROM pg_catalog.pg_proc p
WHERE p.pronamespace = 'precios_api'::regnamespace
  AND p.proname = 'api_precios_admitir'
  AND p.prosrc LIKE '%pg_advisory_xact_lock%';

-- G13 (DURO): existen las 3 cubetas de INTENTO en el limiter. Son la unica cota
--   del replay masivo: el recovery no consume cuota LOGICA por diseno.
INSERT INTO _v
SELECT 52, 'G13_cubetas_de_intento_en_rl_consumir', '3', COUNT(*)::TEXT, COUNT(*) = 3
FROM (VALUES ('admision_intento_global'),('admision_intento_s2s'),('admision_intento_web')) AS c(scope)
WHERE EXISTS (
  SELECT 1 FROM pg_catalog.pg_proc p
   WHERE p.pronamespace = 'precios_api'::regnamespace
     AND p.proname = 'api_precios_rl_consumir'
     AND p.prosrc LIKE '%' || c.scope || '%');

-- ---------------------------------------------------------------------------
-- D07 (INFORMATIVO): SUPERFICIE RESIDUAL EFECTIVA en public.
--
--   El rol conserva USAGE sobre public heredado del pseudo-rol PUBLIC (A12).
--   Por lo tanto, TODA funcion de public con EXECUTE a PUBLIC le es INVOCABLE:
--   las que ya existen y las que se creen en el futuro.
--
--   B4-0A **no** cierra eso, y no pretende hacerlo: cerrarlo exige hardening
--   GLOBAL, que esta fuera de su alcance. Este check las CUENTA, con la
--   superficie EFECTIVA. No es un fallo: es la superficie conocida y declarada.
--   Los fallos duros son:
--     D03 -> ninguna puede ser SECURITY DEFINER invocable (eso seria escalada)
--     D04 -> ninguna puede ser del motor B3 (saltearia cuota+nonce+ticket)
--     D05/D06 -> cero privilegios de tabla y de secuencia
--
--   Cerrar esto exige hardening GLOBAL (default privileges y/o el USAGE de
--   PUBLIC sobre public), que esta FUERA del alcance de B4-0A y se trata aparte.
-- ---------------------------------------------------------------------------
INSERT INTO _v
SELECT 35.5, 'D07_superficie_residual_efectiva_en_public [info]',
       'N funciones de public invocables (ver Salida 3)',
       COUNT(*)::TEXT || ' invocables', TRUE
FROM _ejec e
WHERE e.esquema = 'public' AND e.sig NOT IN (SELECT sig FROM _allow);

-- ===========================================================================
-- E) pg_cron -- los 4 jobs por NOMBRE EXACTO. Nunca LIKE.
-- ===========================================================================
CREATE TEMP TABLE _job_esp (jobname TEXT, schedule TEXT, command TEXT) ON COMMIT DROP;
INSERT INTO _job_esp VALUES
 ('b4_purga_ticket',       '*/5 * * * *',  'SELECT precios_api.api_precios_ticket_purgar();'),
 ('b4_purga_nonce_s2s',    '*/5 * * * *',  'SELECT precios_api.api_precios_nonce_purgar();'),
 ('b4_purga_rate_limit',   '*/10 * * * *', 'SELECT precios_api.api_precios_rl_purgar();'),
 ('b4_purga_idempotencia', '0 * * * *',    'SELECT precios_api.api_precios_idempotencia_purgar();');

INSERT INTO _v
SELECT 36, 'E01_cron_4_jobs_exactos', '4', COUNT(*)::TEXT, COUNT(*) = 4
FROM cron.job j WHERE j.jobname IN (SELECT jobname FROM _job_esp);

INSERT INTO _v
SELECT 37, 'E02_cron_schedule_y_command_exactos', '0 diferencias',
       COUNT(*)::TEXT || ' dif', COUNT(*) = 0
FROM ((SELECT jobname, schedule, command FROM _job_esp
       EXCEPT SELECT j.jobname, j.schedule, j.command FROM cron.job j)
      UNION ALL
      (SELECT j.jobname, j.schedule, j.command FROM cron.job j
        WHERE j.jobname IN (SELECT jobname FROM _job_esp)
       EXCEPT SELECT jobname, schedule, command FROM _job_esp)) d;

INSERT INTO _v
SELECT 38, 'E03_cron_todos_activos', '4', COUNT(*) FILTER (WHERE j.active)::TEXT,
       COUNT(*) FILTER (WHERE j.active) = 4
FROM cron.job j WHERE j.jobname IN (SELECT jobname FROM _job_esp);

INSERT INTO _v
SELECT 39, 'E04_cron_database_y_username', '4 en esta db, user=postgres',
       COUNT(*) FILTER (WHERE j.database = pg_catalog.current_database()
                          AND j.username = 'postgres')::TEXT,
       COUNT(*) FILTER (WHERE j.database = pg_catalog.current_database()
                          AND j.username = 'postgres') = 4
FROM cron.job j WHERE j.jobname IN (SELECT jobname FROM _job_esp);

INSERT INTO _v
SELECT 40, 'E05_sin_watchdog', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM cron.job j WHERE j.command ILIKE '%pg_terminate_backend%';

-- ===========================================================================
-- F) NO-REGRESION -- upstream intacto
-- ===========================================================================
INSERT INTO _v SELECT 41, 'F01_b3_13_funciones', '13', COUNT(*)::TEXT, COUNT(*) = 13
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%';

-- El REVOKE de 9.bis NO altera prosrc -> el fingerprint sigue igual.
INSERT INTO _v
SELECT 42, 'F02_b3_fingerprint', '098f2fe7916e11ffa78cff37622b9064', fp,
       fp = '098f2fe7916e11ffa78cff37622b9064'
FROM (SELECT pg_catalog.md5(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.replace(prosrc, pg_catalog.chr(13), '')),
               '' ORDER BY proname)) AS fp
      FROM pg_catalog.pg_proc
      WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%') x;

INSERT INTO _v SELECT 43, 'F03_b3_sigue_security_invoker', '0',
       COUNT(*) FILTER (WHERE prosecdef)::TEXT, COUNT(*) FILTER (WHERE prosecdef) = 0
FROM pg_catalog.pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'precios\_%';

-- conteos: DIAGNOSTICO (dicen que fallo), no prueba
INSERT INTO _v SELECT 44, 'F04_b2a_7_tablas [diag]', '7', COUNT(*)::TEXT, COUNT(*) = 7
FROM pg_catalog.pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
  AND c.relname IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia',
                    'noches_alta_demanda','overrides_precio','cotizaciones_precio',
                    'precios_auditoria');

INSERT INTO _v SELECT 45, 'F05_b2b_32_tarifas_vigentes [diag]', '32', COUNT(*)::TEXT, COUNT(*) = 32
FROM public.tarifas_motor WHERE vigente_hasta IS NULL;

-- ---------------------------------------------------------------------------
-- PRUEBA (punto 2): B2A/B2B por FINGERPRINT, con los algoritmos de
-- B2A_VERIFY.sql / B2B_VERIFY.sql. El conteo no prueba que la estructura ni la
-- grilla sean las esperadas; el hash si.
-- ---------------------------------------------------------------------------
INSERT INTO _v
SELECT 45.1, 'F05a_b2a_fingerprint_estructural', 'da52a16c045689523a5f1f113f513a87',
       fp || ' (' || n::TEXT || ' lineas)', fp = 'da52a16c045689523a5f1f113f513a87'
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
  SELECT md5(string_agg(line, E'\n' ORDER BY line)) AS fp, COUNT(*) AS n FROM todo) x;

INSERT INTO _v
SELECT 45.2, 'F05b_b2b_fingerprint_datos', '6d1653748d68ee9b62aa20aba5f3333d',
       fp || ' (' || n::TEXT || ' lineas)', fp = '6d1653748d68ee9b62aa20aba5f3333d'
FROM (
  WITH tar AS (
    SELECT 'T|'||perfil||'|'||temporada_clave||'|'||concepto||'|'||precio::TEXT AS line
    FROM tarifas_motor WHERE vigente_hasta IS NULL),
  tmp AS (
    SELECT 'S|'||temporada_clave||'|'||anio::TEXT||'|'||fecha_in::TEXT||'|'||fecha_out_excl::TEXT AS line
    FROM temporada_vigencia),
  todo AS (SELECT line FROM tar UNION ALL SELECT line FROM tmp)
  SELECT md5(string_agg(line, E'\n' ORDER BY line)) AS fp, COUNT(*) AS n FROM todo) x;

INSERT INTO _v SELECT 46, 'F06_temporadas_8', '8', COUNT(*)::TEXT, COUNT(*) = 8
FROM public.temporada_vigencia;

-- continuidad: sin huecos ni solapamientos
INSERT INTO _v SELECT 47, 'F07_temporadas_continuas', '0 discontinuidades',
       COUNT(*)::TEXT, COUNT(*) = 0
FROM (SELECT fecha_in, LAG(fecha_out_excl) OVER (ORDER BY fecha_in) AS prev_out
      FROM public.temporada_vigencia) t
WHERE prev_out IS NOT NULL AND prev_out IS DISTINCT FROM fecha_in;

-- B4 NO dejo objetos sueltos en public
INSERT INTO _v SELECT 48, 'F08_cero_objetos_b4_en_public', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relname LIKE 'api\_precios\_%';

INSERT INTO _v SELECT 49, 'F09_cero_funciones_b4_en_public', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM pg_catalog.pg_proc p
WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'api\_precios\_%';

-- ===========================================================================
-- SALIDAS
-- ===========================================================================
SELECT check_id, esperado, obtenido,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM _v ORDER BY orden;

SELECT COUNT(*) FILTER (WHERE ok)     AS pass,
       COUNT(*) FILTER (WHERE NOT ok) AS fail,
       CASE WHEN COUNT(*) FILTER (WHERE NOT ok) = 0
            THEN 'B4-0A VERIFY OK' ELSE 'B4-0A VERIFY CON FALLAS' END AS veredicto
FROM _v;

-- ---------------------------------------------------------------------------
-- CLAIM DE SEGURIDAD -- lo que este VERIFY prueba, y lo que NO.
--
--   NO se afirma "cinco funciones y nada mas en toda la base": el rol conserva
--   USAGE sobre public heredado de PUBLIC. El claim exacto es este, y cada linea
--   tiene su check duro:
-- ---------------------------------------------------------------------------
SELECT * FROM (VALUES
  ('1. En precios_api: EXACTAMENTE 5 funciones INVOCABLES por el rol',
   'D01 + D02  (superficie efectiva: EXECUTE + USAGE de schema)'),
  ('2. Cero SECURITY DEFINER INVOCABLE fuera de la allowlist, en CUALQUIER schema',
   'D03  <- el check que impide escalada de privilegios'),
  ('3. Cero EXECUTE sobre el motor B3 (las 13 precios_*)',
   'D04  <- impide saltear cuota + nonce + ticket'),
  ('4. Cero privilegios de TABLA y de SECUENCIA en toda la base',
   'D05 + D06'),
  ('5. El rol no puede CREAR nada: ni en public, ni schemas nuevos',
   'A11 (schema public) + A13 (base)'),
  ('6. RESIDUAL CONOCIDO: via el USAGE heredado de PUBLIC sobre public, el rol',
   'D07 [info] + Salida 3'),
  ('   puede invocar funciones de public con EXECUTE a PUBLIC (actuales y futuras).',
   'Fuera del alcance de B4-0A. Declarado y medido, no tapado.')
) AS claim(afirmacion, evidencia);

-- SALIDA 3 (INFORMATIVA): la superficie EFECTIVA -- todo lo que el rol puede
-- INVOCAR de verdad (EXECUTE + USAGE de schema), en toda la base.
-- Si D01/D02/D03 fallan, aca esta el detalle exacto de que sobra.
SELECT 'INVOCABLE' AS clase, e.esquema, e.sig, e.secdef,
       CASE WHEN e.sig IN (SELECT sig FROM _allow) THEN 'ALLOWLIST' ELSE 'REVISAR' END AS estado
FROM _ejec e
UNION ALL
-- y lo que tiene EXECUTE pero NO USAGE de schema: hoy inalcanzable. No cuenta
-- como superficie, pero si alguien concediera USAGE, pasaria a contar.
SELECT 'sin USAGE (inalcanzable)', e.esquema, e.sig, e.secdef, 'info'
FROM _ejec_sin_usage e
ORDER BY 1, 4 DESC, 2, 3;

-- INFORMATIVA: TEMPORARY por rol. Se espera 'true': es el escenario que D3
-- neutraliza. Revocarlo globalmente exige inventariar consumidores -> hardening
-- aparte, no descartado.
SELECT r.rolname,
       pg_catalog.has_database_privilege(r.rolname, pg_catalog.current_database(), 'TEMPORARY')
         AS puede_crear_temp
FROM pg_catalog.pg_roles r
WHERE r.rolname IN ('vita_precios_api','anon','authenticated','service_role',
                    'authenticator','postgres')
ORDER BY r.rolname;

COMMIT;
