-- ============================================================================
-- BOOTSTRAP ENTORNO NUEVO v1.12.0 — 03_VERIFY: VEREDICTO FINAL DEL ENTORNO (RO)
-- Verificacion ESTRICTA de la capa Carril C / portal v1.12.0 (espejo RO de D5
--   extendido): existencia de los objetos (portal_usuarios + id_socio,
--   portal_idempotencia, portal_idempotencia_cc, sus secuencias,
--   portal_cargar_gasto_interno, portal_registrar_retiro); las DOS FKs de
--   portal_usuarios verificadas POR COLUMNA (user_id->auth.users(id) CASCADE ;
--   id_socio->socios(id_socio) RESTRICT); UNIQUE/CHECK de id_socio; FK de
--   portal_idempotencia_cc (id_movimiento->movimientos_socio RESTRICT); CHECK de
--   rol {jenny,vicky,socio}; firmas de las 2 funciones (jsonb+INVOKER+plpgsql);
--   hardening por ACL real (aclexplode) y estado RLS/policies. 100% read-only.
-- ----------------------------------------------------------------------------
-- USO: SQL Editor del PROYECTO NUEVO, NADA seleccionado. Correr DESPUES de D5.
--   Gate FINAL del entorno, tras 01_VERIFY (Parte B) y 02_VERIFY (Parte C).
-- VEREDICTO: ENTORNO_COMPLETO_OK | ENTORNO_INCOMPLETO.
-- NO DEPENDE DE DATOS NI AMBIENTE. Requiere schema auth y roles Data API.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 1 — VEREDICTO FINAL DEL ENTORNO (una fila)
-- ────────────────────────────────────────────────────────────────────────────
WITH o AS (
  SELECT to_regclass('public.portal_usuarios')                          AS pu,
         to_regclass('public.portal_idempotencia')                      AS pi,
         to_regclass('public.portal_idempotencia_cc')                   AS picc,
         to_regclass('public.portal_idempotencia_id_registro_seq')      AS seq,
         to_regclass('public.portal_idempotencia_cc_id_registro_seq')   AS seqcc,
         to_regprocedure('public.portal_cargar_gasto_interno(jsonb)')   AS fn,
         to_regprocedure('public.portal_registrar_retiro(jsonb)')       AS fnr,
         to_regclass('auth.users')                                      AS au,
         to_regclass('public.gastos_internos')                          AS gi,
         to_regclass('public.socios')                                   AS soc,
         to_regclass('public.movimientos_socio')                        AS mov
),
chk AS (
  SELECT
    (o.pu IS NOT NULL)   AS e_pu,
    (o.pi IS NOT NULL)   AS e_pi,
    (o.picc IS NOT NULL) AS e_picc,
    (o.seq IS NOT NULL)  AS e_seq,
    (o.seqcc IS NOT NULL) AS e_seqcc,
    (o.fn IS NOT NULL)   AS e_fn,
    (o.fnr IS NOT NULL)  AS e_fnr,
    -- FK portal_usuarios.user_id -> auth.users(id) ON DELETE CASCADE (por columna)
    COALESCE((SELECT bool_or(
                con.confrelid=o.au AND con.confdeltype='c'
                AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid  AND a.attnum=con.conkey[1])='user_id'
                AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1])='id'
                AND cardinality(con.conkey)=1)
              FROM pg_constraint con WHERE con.conrelid=o.pu AND con.contype='f'), false) AS fk_pu_auth_ok,
    -- FK portal_usuarios.id_socio -> socios(id_socio) ON DELETE RESTRICT (por nombre+columna)
    COALESCE((SELECT con.confrelid=o.soc AND con.confdeltype='r'
                AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid  AND a.attnum=con.conkey[1])='id_socio'
                AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1])='id_socio'
                AND cardinality(con.conkey)=1
              FROM pg_constraint con WHERE con.conrelid=o.pu AND con.contype='f' AND con.conname='fk_portal_usuarios_id_socio'), false) AS fk_pu_socio_ok,
    -- UNIQUE id_socio
    COALESCE((SELECT (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                        FROM unnest(con.conkey) AS ck(attnum) JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum)=ARRAY['id_socio']
              FROM pg_constraint con WHERE con.conrelid=o.pu AND con.contype='u' AND con.conname='uq_portal_usuarios_id_socio'), false) AS uq_socio_ok,
    -- CHECK bicondicional rol<->id_socio
    COALESCE((SELECT pg_get_constraintdef(con.oid) ILIKE '%socio%' AND pg_get_constraintdef(con.oid) ILIKE '%id_socio%'
              FROM pg_constraint con WHERE con.conrelid=o.pu AND con.contype='c' AND con.conname='chk_portal_usuarios_socio_rol'), false) AS chk_socio_ok,
    -- FK portal_idempotencia.id_gasto -> gastos_internos(id_gasto) RESTRICT
    COALESCE((SELECT con.confrelid=o.gi AND con.confdeltype='r'
                AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid  AND a.attnum=con.conkey[1])='id_gasto'
                AND cardinality(con.conkey)=1
              FROM pg_constraint con WHERE con.conrelid=o.pi AND con.contype='f' AND con.conname='fk_portal_idempotencia_gasto'), false) AS fk_pi_ok,
    -- FK portal_idempotencia_cc.id_movimiento -> movimientos_socio(id_movimiento) RESTRICT
    COALESCE((SELECT con.confrelid=o.mov AND con.confdeltype='r'
                AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid  AND a.attnum=con.conkey[1])='id_movimiento'
                AND cardinality(con.conkey)=1
              FROM pg_constraint con WHERE con.conrelid=o.picc AND con.contype='f' AND con.conname='fk_portal_idem_cc_mov'), false) AS fk_picc_ok,
    -- CHECK rol {jenny,vicky,socio}
    COALESCE((SELECT pg_get_constraintdef(con.oid) ILIKE '%jenny%'
                 AND pg_get_constraintdef(con.oid) ILIKE '%vicky%'
                 AND pg_get_constraintdef(con.oid) ILIKE '%socio%'
              FROM pg_constraint con WHERE con.conrelid=o.pu AND con.contype='c' AND con.conname='chk_portal_usuarios_rol'), false) AS chk_rol_ok,
    -- UNIQUEs de portal_idempotencia + portal_idempotencia_cc
    COALESCE((SELECT count(*) FROM pg_constraint con WHERE con.contype='u'
                AND con.conname IN ('uq_portal_usuarios_nombre','uq_portal_idempotencia_nonce',
                  'uq_portal_idempotencia_action_key','uq_portal_idem_cc_nonce','uq_portal_idem_cc_action_key')),0)=5 AS uniques_ok,
    -- Firmas de las 2 funciones (jsonb + INVOKER + plpgsql)
    COALESCE((SELECT p.prorettype='jsonb'::regtype AND NOT p.prosecdef AND l.lanname='plpgsql'
              FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=o.fn), false) AS fn_firma_ok,
    COALESCE((SELECT p.prorettype='jsonb'::regtype AND NOT p.prosecdef AND l.lanname='plpgsql'
              FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=o.fnr), false) AS fnr_firma_ok,
    -- ACL: portal_usuarios = solo service_role:SELECT
    (o.pu IS NOT NULL
     AND COALESCE((SELECT count(*) FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
                    WHERE c.oid=o.pu AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
                      AND NOT (a.grantee<>0 AND pg_get_userbyid(a.grantee)='service_role' AND a.privilege_type='SELECT')),0)=0
     AND COALESCE((SELECT count(*) FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
                    WHERE c.oid=o.pu AND a.grantee<>0 AND pg_get_userbyid(a.grantee)='service_role' AND a.privilege_type='SELECT'),0)=1) AS pu_acl_ok,
    -- ACL: portal_idempotencia / portal_idempotencia_cc / secuencias = sin Data API
    (COALESCE((SELECT count(*) FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
                WHERE c.oid IN (o.pi,o.picc,o.seq,o.seqcc)
                  AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))),0)=0) AS idem_acl_ok,
    -- ACL: funciones = proacl no null + sin Data API EXECUTE
    (o.fn IS NOT NULL AND o.fnr IS NOT NULL
     AND (SELECT proacl FROM pg_proc WHERE oid=o.fn) IS NOT NULL
     AND (SELECT proacl FROM pg_proc WHERE oid=o.fnr) IS NOT NULL
     AND COALESCE((SELECT count(*) FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
                    WHERE p.oid IN (o.fn,o.fnr) AND a.privilege_type='EXECUTE'
                      AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))),0)=0) AS fn_acl_ok,
    -- RLS off + 0 policies en las 3 tablas del portal
    (o.pu IS NOT NULL AND o.pi IS NOT NULL AND o.picc IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_class WHERE oid IN (o.pu,o.pi,o.picc) AND (relrowsecurity OR relforcerowsecurity))
     AND NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid IN (o.pu,o.pi,o.picc))) AS rls_ok
  FROM o
)
SELECT
  (CASE WHEN e_pu THEN 1 ELSE 0 END + CASE WHEN e_pi THEN 1 ELSE 0 END
   + CASE WHEN e_picc THEN 1 ELSE 0 END + CASE WHEN e_fn THEN 1 ELSE 0 END
   + CASE WHEN e_fnr THEN 1 ELSE 0 END)                       AS portal_objetos_core,  -- esperado 5
  CASE WHEN fk_pu_auth_ok  THEN 'OK' ELSE 'FALLA' END  AS fk_usuarios_auth,   -- user_id->auth.users(id) CASCADE
  CASE WHEN fk_pu_socio_ok THEN 'OK' ELSE 'FALLA' END  AS fk_usuarios_socio,  -- id_socio->socios(id_socio) RESTRICT
  CASE WHEN uq_socio_ok    THEN 'OK' ELSE 'FALLA' END  AS uq_id_socio,
  CASE WHEN chk_socio_ok   THEN 'OK' ELSE 'FALLA' END  AS chk_socio_rol,      -- bicondicional
  CASE WHEN fk_pi_ok       THEN 'OK' ELSE 'FALLA' END  AS fk_idem_gasto,      -- id_gasto->gastos_internos RESTRICT
  CASE WHEN fk_picc_ok     THEN 'OK' ELSE 'FALLA' END  AS fk_idemcc_mov,      -- id_movimiento->movimientos_socio RESTRICT
  CASE WHEN chk_rol_ok     THEN 'OK' ELSE 'FALLA' END  AS check_rol,          -- {jenny,vicky,socio}
  CASE WHEN uniques_ok     THEN 'OK' ELSE 'FALLA' END  AS uniques,            -- 5 UNIQUEs
  CASE WHEN fn_firma_ok AND fnr_firma_ok THEN 'OK' ELSE 'FALLA' END AS func_firmas,  -- jsonb+INVOKER+plpgsql x2
  CASE WHEN pu_acl_ok      THEN 'OK' ELSE 'FALLA' END  AS pu_acl,             -- solo service_role:SELECT
  CASE WHEN idem_acl_ok    THEN 'OK' ELSE 'FALLA' END  AS idem_acl,           -- pi/picc/seqs sin Data API
  CASE WHEN fn_acl_ok      THEN 'OK' ELSE 'FALLA' END  AS fn_acl,             -- proacl no null + sin Data API
  CASE WHEN rls_ok         THEN 'OK' ELSE 'FALLA' END  AS rls_policies,       -- RLS off, 0 policies
  CASE WHEN e_pu AND e_pi AND e_picc AND e_seq AND e_seqcc AND e_fn AND e_fnr
        AND fk_pu_auth_ok AND fk_pu_socio_ok AND uq_socio_ok AND chk_socio_ok
        AND fk_pi_ok AND fk_picc_ok AND chk_rol_ok AND uniques_ok
        AND fn_firma_ok AND fnr_firma_ok
        AND pu_acl_ok AND idem_acl_ok AND fn_acl_ok AND rls_ok
       THEN 'ENTORNO_COMPLETO_OK'
       ELSE 'ENTORNO_INCOMPLETO -> revisar la columna en FALLA'
  END AS veredicto
FROM chk;


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 2 — ACL de los objetos del portal (read-only; informativo)
-- ----------------------------------------------------------------------------
-- ESPERADO: la UNICA fila con rol Data API es service_role=SELECT sobre
-- portal_usuarios. portal_idempotencia / portal_idempotencia_cc / secuencias NO
-- deben aparecer. Las funciones quedan cubiertas por fn_acl de la QUERY 1.
-- ────────────────────────────────────────────────────────────────────────────
SELECT
  CASE c.relkind WHEN 'r' THEN 'tabla' WHEN 'S' THEN 'secuencia' ELSE c.relkind::text END AS tipo,
  c.relname                                          AS objeto,
  COALESCE(pg_get_userbyid(a.grantee),'PUBLIC')      AS rol,
  string_agg(DISTINCT a.privilege_type, ',' ORDER BY a.privilege_type) AS privs
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
CROSS JOIN LATERAL aclexplode(c.relacl) a
WHERE n.nspname='public'
  AND c.relname IN ('portal_usuarios','portal_idempotencia','portal_idempotencia_cc',
    'portal_idempotencia_id_registro_seq','portal_idempotencia_cc_id_registro_seq')
  AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
GROUP BY c.relkind, c.relname, a.grantee
ORDER BY c.relname, rol;
