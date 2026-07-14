-- ====================================================================================
-- D2_Q7_VEREDICTO.sql
-- Bloque B1.3-consolidacion-canonica * D2 * veredicto integral
-- ALCANCE: objetos del carril Motor de Horarios que quedaron FUERA del pin de 11 de S8.
-- TEST unicamente. 100% LECTURA. Autocontenido: trae su propio gate y su propia
-- transaccion READ ONLY. No se puede ejecutar esta Q sin el gate: el archivo ES la Q.
-- Repo de referencia: HEAD 07fea85802bc4fccbff1236813593762aefe58d9
--
-- v2 -- CORRIGE DOS FALSOS VERDES, reproducidos en harness PG 17.10:
--   (1) La presencia se calculaba por PRONAME. Con crear_bloqueo(text) vivo y
--       crear_bloqueo(jsonb) ausente, Q7 informaba: presentes=7, ausentes=0,
--       overloads_extra=0. Verde completo sobre una firma inexistente.
--       AHORA la unidad de verdad es la FIRMA, no el nombre.
--   (2) trg_ov_guard_ok omitia eventos, momento y nivel de fila. Un trigger que solo
--       respondia a INSERT (sin UPDATE ni DELETE) daba ok=true.
--       AHORA replica el predicado completo de Q4 y ademas exige NOT TRUNCATE.
--   (3) Un rol de la Data API inexistente NO se omitia en silencio: ABORTABA la Q entera.
--         psql:D2_Q7_VEREDICTO.sql:262: ERROR:  role "anon" does not exist
--       Causa: has_function_privilege(NOMBRE, ...) lanza ERROR si el rol no existe, y un
--       guard "WHERE EXISTS (...) AND has_function_privilege(...)" NO protege: Postgres no
--       garantiza el orden de evaluacion de los predicados de un WHERE.
--       AHORA: JOIN contra pg_roles + OID. Ademas se reporta el rol ausente.
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
      'GATE D2: ambiente=% (esperado test). Abortando.',
      COALESCE(v_amb, '<null>');
  END IF;
END
$gate$;

-- Q7 -- VEREDICTO INTEGRAL D2 (1 fila).
--   NO emite apto_para_freeze: ese booleano pertenece al pin de 11 (D1/Q9).
--   Este bloque responde: que hay, con que FIRMA EXACTA, y con que hashes.
WITH esperadas(pron, firma_esperada) AS (
  VALUES
    ('validar_estado_horario_final',     'public.validar_estado_horario_final(bigint,date)'),
    ('validar_no_eventos_comprometidos', 'public.validar_no_eventos_comprometidos(bigint,date)'),
    ('validar_estado_override',          'public.validar_estado_override(bigint,date)'),
    ('trg_guard_overrides',              'public.trg_guard_overrides()'),
    ('crear_override_horario',           'public.crear_override_horario(jsonb)'),
    ('crear_bloqueo',                    'public.crear_bloqueo(jsonb)'),
    ('fecha_hoy_ar',                     'public.fecha_hoy_ar()')
),
-- OID de cada firma esperada. NULL si esa FIRMA EXACTA no existe.
esp AS (
  SELECT e.pron,
         e.firma_esperada,
         to_regprocedure(e.firma_esperada)::oid AS oid_esperado
  FROM esperadas e
),
-- Todas las firmas VIVAS de esos pronames: captura overloads Y firmas cambiadas.
vivas AS (
  SELECT p.oid,
         p.proname,
         format('%I.%I(%s)', n.nspname, p.proname,
                pg_get_function_identity_arguments(p.oid))                        AS firma,
         octet_length(pg_get_functiondef(p.oid))
           - octet_length(replace(pg_get_functiondef(p.oid), chr(13), ''))        AS cr
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'validar_estado_horario_final',
      'validar_no_eventos_comprometidos',
      'validar_estado_override',
      'trg_guard_overrides',
      'crear_override_horario',
      'crear_bloqueo',
      'fecha_hoy_ar'
    )
),
-- Firmas vivas que NO corresponden a ninguna firma esperada existente.
-- Cubre los dos casos: la firma cambio, o hay un overload que sobra.
distintas AS (
  SELECT v.firma, v.proname
  FROM vivas v
  WHERE NOT EXISTS (
    SELECT 1 FROM esp e
    WHERE e.oid_esperado IS NOT NULL
      AND e.oid_esperado = v.oid
  )
),
-- Overloads: pronames con mas de una firma viva.
ovl AS (
  SELECT v.proname,
         count(*)                                   AS n_firmas,
         string_agg(v.firma, ' , ' ORDER BY v.oid)  AS firmas
  FROM vivas v
  GROUP BY v.proname
  HAVING count(*) > 1
),
acl_pub AS (
  SELECT DISTINCT v.firma
  FROM vivas v
  JOIN pg_proc p ON p.oid = v.oid
  CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
  WHERE a.grantee = 0
    AND a.privilege_type = 'EXECUTE'
),
roles_api(rolname) AS (
  VALUES ('anon'), ('authenticated'), ('service_role')
),
-- Roles de la Data API que NO EXISTEN. No se omiten en silencio.
roles_ausentes AS (
  SELECT r.rolname
  FROM roles_api r
  WHERE NOT EXISTS (SELECT 1 FROM pg_roles pr WHERE pr.rolname = r.rolname)
),
-- Privilegios EFECTIVOS.
--   OJO: has_function_privilege(NOMBRE, ...) lanza ERROR si el rol no existe, y un
--   guard "WHERE EXISTS (...) AND has_function_privilege(...)" NO protege: Postgres no
--   garantiza el orden de evaluacion de los predicados de un WHERE. Comprobado en
--   harness PG 17.10: sin el rol anon, esa forma aborta la Q entera.
--   SOLUCION: JOIN contra pg_roles y pasar el OID. El OID viene de la propia tabla,
--   asi que por construccion existe y la llamada no puede fallar.
priv_eff AS (
  SELECT v.firma, pr.rolname
  FROM vivas v
  JOIN pg_roles pr
    ON pr.rolname IN ('anon', 'authenticated', 'service_role')
  WHERE has_function_privilege(pr.oid, v.oid, 'EXECUTE')
),
-- TRIGGER: predicado COMPLETO. Identico al de Q4 + NOT TRUNCATE.
--   bitmask tgtype: 1=ROW  2=BEFORE  4=INSERT  8=DELETE  16=UPDATE  32=TRUNCATE  64=INSTEAD
trg_esp AS (
  SELECT t.oid,
         md5(pg_get_triggerdef(t.oid, true)) AS fp_triggerdef,
         (
               t.tgname       = 'trg_ov_guard'
           AND ns.nspname     = 'public'
           AND c.relname      = 'overrides_operativos'
           AND p.oid          = to_regprocedure('public.trg_guard_overrides()')::oid
           AND t.tgconstraint <> 0            -- CONSTRAINT TRIGGER
           AND t.tgdeferrable                 -- DEFERRABLE
           AND t.tginitdeferred               -- INITIALLY DEFERRED
           AND t.tgenabled    = 'O'           -- enabled (origin)
           AND (t.tgtype::int &  4) <> 0      -- INSERT
           AND (t.tgtype::int &  8) <> 0      -- DELETE
           AND (t.tgtype::int & 16) <> 0      -- UPDATE
           AND (t.tgtype::int & 32) =  0      -- NOT TRUNCATE
           AND (t.tgtype::int &  1) <> 0      -- FOR EACH ROW
           AND (t.tgtype::int &  2) =  0      -- AFTER (no BEFORE)
           AND (t.tgtype::int & 64) =  0      -- no INSTEAD OF
         ) AS cumple_todo
  FROM pg_trigger t
  JOIN pg_class     c  ON c.oid  = t.tgrelid
  JOIN pg_namespace ns ON ns.oid = c.relnamespace
  JOIN pg_proc      p  ON p.oid  = t.tgfoid
  WHERE NOT t.tgisinternal
    AND t.tgname   = 'trg_ov_guard'
    AND ns.nspname = 'public'
),
-- Triggers en overrides_operativos que NO son trg_ov_guard.
trg_otros AS (
  SELECT t.tgname,
         format('%I.%I()', pn.nspname, p.proname) AS trigger_fn
  FROM pg_trigger t
  JOIN pg_class     c  ON c.oid  = t.tgrelid
  JOIN pg_namespace ns ON ns.oid = c.relnamespace AND ns.nspname = 'public'
  JOIN pg_proc      p  ON p.oid  = t.tgfoid
  JOIN pg_namespace pn ON pn.oid = p.pronamespace
  WHERE NOT t.tgisinternal
    AND c.relname = 'overrides_operativos'
    AND t.tgname <> 'trg_ov_guard'
),
m AS (
  SELECT
    (SELECT count(DISTINCT proname) FROM vivas)                    AS objetos_nombre_presentes,
    (SELECT count(*) FROM esp WHERE oid_esperado IS NOT NULL)      AS firmas_esperadas_presentes,
    (SELECT count(*) FROM esp WHERE oid_esperado IS NULL)          AS firmas_esperadas_ausentes,
    (SELECT count(*) FROM distintas)                               AS firmas_distintas_de_esperada,
    (SELECT COALESCE(sum(n_firmas - 1), 0) FROM ovl)               AS overloads_extra,
    (SELECT count(*) FROM vivas)                                   AS firmas_vivas_totales,
    (SELECT count(*) FROM acl_pub)                                 AS execute_a_public,
    (SELECT count(*) FROM priv_eff)                                AS priv_efectivos_data_api,
    (SELECT count(*) FROM roles_ausentes)                          AS roles_data_api_ausentes,
    (SELECT count(*) FROM trg_esp)                                 AS trg_ov_guard_filas,
    (SELECT count(*) FROM trg_otros)                               AS otros_triggers_en_overrides,
    (SELECT count(*) FROM vivas WHERE cr > 0)                      AS objetos_con_cr,
    (SELECT COALESCE(sum(cr), 0) FROM vivas)                       AS cr_totales
)
SELECT
  'D2_Q7_VEREDICTO'                                                          AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente')  AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,

  -- ---- PRESENCIA POR FIRMA, no por nombre ----
  m.objetos_nombre_presentes                                                 AS objetos_nombre_presentes,
  m.firmas_esperadas_presentes                                               AS firmas_esperadas_presentes,
  m.firmas_esperadas_ausentes                                                AS firmas_esperadas_ausentes,
  COALESCE((SELECT string_agg(firma_esperada, ' | ' ORDER BY pron)
              FROM esp WHERE oid_esperado IS NULL), '<ninguna>')             AS detalle_firmas_esperadas_ausentes,
  m.firmas_distintas_de_esperada                                             AS firmas_distintas_de_esperada,
  COALESCE((SELECT string_agg(firma, ' | ' ORDER BY proname, firma)
              FROM distintas), '<ninguna>')                                  AS detalle_firmas_distintas,
  m.overloads_extra                                                          AS overloads_extra,
  COALESCE((SELECT string_agg(proname || ' [' || n_firmas || ']: ' || firmas, ' | ' ORDER BY proname)
              FROM ovl), '<ninguno>')                                        AS detalle_overloads,
  m.firmas_vivas_totales                                                     AS firmas_vivas_totales,

  -- ---- ACL ----
  m.execute_a_public                                                         AS execute_a_public,
  COALESCE((SELECT string_agg(firma, ' | ' ORDER BY firma) FROM acl_pub),
           '<ninguno>')                                                      AS detalle_execute_public,
  m.priv_efectivos_data_api                                                  AS priv_efectivos_data_api,
  COALESCE((SELECT string_agg(firma || ' -> ' || rolname, ' | ' ORDER BY firma, rolname)
              FROM priv_eff), '<ninguno>')                                   AS detalle_priv_efectivos,
  m.roles_data_api_ausentes                                                  AS roles_data_api_ausentes,
  COALESCE((SELECT string_agg(rolname, ' | ' ORDER BY rolname) FROM roles_ausentes),
           '<ninguno -- los 3 existen>')                                     AS detalle_roles_data_api_ausentes,

  -- ---- TRIGGER trg_ov_guard ----
  m.trg_ov_guard_filas                                                       AS trg_ov_guard_filas,
  -- true SOLO si hay EXACTAMENTE UNA fila y cumple TODAS las propiedades.
  (m.trg_ov_guard_filas = 1
   AND COALESCE((SELECT bool_and(cumple_todo) FROM trg_esp), false))         AS trg_ov_guard_ok,
  m.otros_triggers_en_overrides                                              AS otros_triggers_en_overrides,
  COALESCE((SELECT string_agg(tgname || ' -> ' || trigger_fn, ' | ' ORDER BY tgname)
              FROM trg_otros), '<ninguno>')                                  AS detalle_otros_triggers,
  COALESCE((SELECT string_agg(fp_triggerdef, ' | ' ORDER BY oid) FROM trg_esp),
           '<ausente>')                                                      AS fingerprint_triggerdef_trg_ov_guard,

  -- ---- EOL (opcion C) ----
  m.objetos_con_cr                                                           AS objetos_con_cr,
  m.cr_totales                                                               AS cr_totales,
  COALESCE((SELECT string_agg(proname || '=' || cr, ' | ' ORDER BY proname)
              FROM vivas WHERE cr > 0), '<ninguno -- todos LF puro>')        AS detalle_cr,

  -- ---- OBSERVACIONES ----
  COALESCE(NULLIF(array_to_string(ARRAY[
    CASE WHEN m.firmas_esperadas_ausentes > 0
      THEN 'FIRMAS ESPERADAS AUSENTES (' || m.firmas_esperadas_ausentes || '): '
           || (SELECT string_agg(firma_esperada, ' , ' ORDER BY pron)
                 FROM esp WHERE oid_esperado IS NULL) END,
    CASE WHEN m.firmas_distintas_de_esperada > 0
      THEN 'FIRMAS VIVAS DISTINTAS DE LA ESPERADA (' || m.firmas_distintas_de_esperada || '): '
           || (SELECT string_agg(firma, ' , ' ORDER BY proname, firma) FROM distintas) END,
    CASE WHEN m.overloads_extra > 0
      THEN 'OVERLOADS EXTRA (' || m.overloads_extra || '): '
           || (SELECT string_agg(proname, ' , ' ORDER BY proname) FROM ovl) END,
    CASE WHEN m.execute_a_public > 0
      THEN 'EXECUTE A PUBLIC en ' || m.execute_a_public || ' objeto(s)' END,
    CASE WHEN m.priv_efectivos_data_api > 0
      THEN 'PRIVILEGIOS EFECTIVOS data API: ' || m.priv_efectivos_data_api END,
    CASE WHEN m.roles_data_api_ausentes > 0
      THEN 'ROLES DATA API AUSENTES (' || m.roles_data_api_ausentes || '): '
           || (SELECT string_agg(rolname, ' , ' ORDER BY rolname) FROM roles_ausentes)
           || ' -- los privilegios efectivos NO los cubren' END,
    CASE WHEN m.trg_ov_guard_filas = 0
      THEN 'trg_ov_guard AUSENTE' END,
    CASE WHEN m.trg_ov_guard_filas > 1
      THEN 'trg_ov_guard DUPLICADO (' || m.trg_ov_guard_filas || ' filas) -- ambiguo' END,
    CASE WHEN m.trg_ov_guard_filas = 1
              AND NOT COALESCE((SELECT bool_and(cumple_todo) FROM trg_esp), false)
      THEN 'trg_ov_guard PRESENTE PERO MAL CONFIGURADO -- ver Q4: eventos / momento / nivel / constraint / deferrable / enabled' END,
    CASE WHEN m.otros_triggers_en_overrides > 0
      THEN 'OTROS TRIGGERS en overrides_operativos (' || m.otros_triggers_en_overrides || '): '
           || (SELECT string_agg(tgname, ' , ' ORDER BY tgname) FROM trg_otros) END
  ], ' || '), ''), '<ninguna -- todo consistente>')                          AS observaciones
FROM m;

COMMIT;
