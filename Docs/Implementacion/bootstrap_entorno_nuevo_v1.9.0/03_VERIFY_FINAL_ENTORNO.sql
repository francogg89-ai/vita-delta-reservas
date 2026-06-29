-- ============================================================================
-- BOOTSTRAP ENTORNO NUEVO v1.9.0 — 03_VERIFY: VEREDICTO FINAL DEL ENTORNO (RO)
-- Verificación ESTRICTA de la capa Carril C / portal (espejo read-only de D5):
--   estructura — existencia de los 4 objetos; FK de portal_usuarios.user_id
--   EXACTA contra auth.users(id) ON DELETE CASCADE y FK de portal_idempotencia.id_gasto contra
--   gastos_internos(id_gasto) ON DELETE RESTRICT (por conrelid/confrelid y
--   columnas, no por nombre); CHECK de rol {jenny,vicky,socio}; UNIQUEs por
--   conjunto de columnas exacto (nombre; nonce; action,idempotency_key); firma de
--   la función (RETURNS jsonb, SECURITY INVOKER, plpgsql) — y hardening D-C-34 por
--   ACL real vía aclexplode, que cubre SELECT/INSERT/UPDATE/DELETE/TRUNCATE/
--   REFERENCES/TRIGGER y MAINTAIN (PG17) sin depender de la versión, más el estado
--   de RLS/policies. 100% read-only.
-- ----------------------------------------------------------------------------
-- USO: SQL Editor del PROYECTO NUEVO, NADA seleccionado. Correr DESPUÉS de D5
--   (fin de 03_BOOTSTRAP_PARTE_D_PORTAL.sql). Es el gate FINAL del entorno, tras
--   01_VERIFY (Parte B) y 02_VERIFY (Parte C). QUERY 1 = fila-veredicto;
--   QUERY 2 = ACL de los objetos del portal (informativo).
-- VEREDICTO: ENTORNO_COMPLETO_OK | ENTORNO_INCOMPLETO.
-- NO DEPENDE DE DATOS NI DE AMBIENTE: solo lee catálogos y ACL; seguro de correr
--   contra cualquier entorno. En un bootstrap nuevo las tablas nacen vacías (la
--   Parte D no siembra); esa vaciedad es el estado esperado, no un invariante, por
--   eso NO se chequean conteos de filas. La trampa proacl IS NULL ⇒ PUBLIC ejecuta
--   queda contemplada (se exige proacl NO nula y cero EXECUTE a roles Data API).
--   Requiere el schema auth y los roles del Data API de Supabase.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 1 — VEREDICTO FINAL DEL ENTORNO (una fila)
-- ────────────────────────────────────────────────────────────────────────────
WITH o AS (
  SELECT to_regclass('public.portal_usuarios')                        AS pu,
         to_regclass('public.portal_idempotencia')                    AS pi,
         to_regclass('public.portal_idempotencia_id_registro_seq')    AS seq,
         to_regprocedure('public.portal_cargar_gasto_interno(jsonb)') AS fn,
         to_regclass('auth.users')                                    AS au,
         to_regclass('public.gastos_internos')                        AS gi
),
chk AS (
  SELECT
    (o.pu IS NOT NULL)  AS e_pu,
    (o.pi IS NOT NULL)  AS e_pi,
    (o.seq IS NOT NULL) AS e_seq,
    (o.fn IS NOT NULL)  AS e_fn,
    COALESCE((SELECT con.confrelid=o.au AND con.confdeltype='c'
                AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid  AND a.attnum=con.conkey[1])='user_id'
                AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1])='id'
                AND cardinality(con.conkey)=1
              FROM pg_constraint con WHERE con.conrelid=o.pu AND con.contype='f'), false) AS fk_pu_ok,
    COALESCE((SELECT con.confrelid=o.gi AND con.confdeltype='r'
                AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid  AND a.attnum=con.conkey[1])='id_gasto'
                AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1])='id_gasto'
                AND cardinality(con.conkey)=1
              FROM pg_constraint con WHERE con.conrelid=o.pi AND con.contype='f' AND con.conname='fk_portal_idempotencia_gasto'), false) AS fk_pi_ok,
    COALESCE((SELECT pg_get_constraintdef(con.oid) ILIKE '%jenny%'
                 AND pg_get_constraintdef(con.oid) ILIKE '%vicky%'
                 AND pg_get_constraintdef(con.oid) ILIKE '%socio%'
              FROM pg_constraint con WHERE con.conrelid=o.pu AND con.contype='c' AND con.conname='chk_portal_usuarios_rol'), false) AS chk_rol_ok,
    COALESCE((SELECT (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                        FROM unnest(con.conkey) AS ck(attnum) JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum)=ARRAY['nombre']
              FROM pg_constraint con WHERE con.conrelid=o.pu AND con.contype='u' AND con.conname='uq_portal_usuarios_nombre'), false) AS uq_nombre_ok,
    COALESCE((SELECT (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                        FROM unnest(con.conkey) AS ck(attnum) JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum)=ARRAY['nonce']
              FROM pg_constraint con WHERE con.conrelid=o.pi AND con.contype='u' AND con.conname='uq_portal_idempotencia_nonce'), false) AS uq_nonce_ok,
    COALESCE((SELECT (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                        FROM unnest(con.conkey) AS ck(attnum) JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum)=ARRAY['action','idempotency_key']
              FROM pg_constraint con WHERE con.conrelid=o.pi AND con.contype='u' AND con.conname='uq_portal_idempotencia_action_key'), false) AS uq_actkey_ok,
    COALESCE((SELECT p.prorettype='jsonb'::regtype AND NOT p.prosecdef AND l.lanname='plpgsql'
              FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=o.fn), false) AS fn_firma_ok,
    (o.pu IS NOT NULL
     AND COALESCE((SELECT count(*) FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
                    WHERE c.oid=o.pu AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
                      AND NOT (a.grantee<>0 AND pg_get_userbyid(a.grantee)='service_role' AND a.privilege_type='SELECT')),0)=0
     AND COALESCE((SELECT count(*) FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
                    WHERE c.oid=o.pu AND a.grantee<>0 AND pg_get_userbyid(a.grantee)='service_role' AND a.privilege_type='SELECT'),0)=1) AS pu_acl_ok,
    (o.pi IS NOT NULL
     AND COALESCE((SELECT count(*) FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
                    WHERE c.oid=o.pi AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))),0)=0) AS pi_acl_ok,
    (o.seq IS NOT NULL
     AND COALESCE((SELECT count(*) FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
                    WHERE c.oid=o.seq AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))),0)=0) AS seq_acl_ok,
    (o.fn IS NOT NULL
     AND (SELECT proacl FROM pg_proc WHERE oid=o.fn) IS NOT NULL
     AND COALESCE((SELECT count(*) FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
                    WHERE p.oid=o.fn AND a.privilege_type='EXECUTE'
                      AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))),0)=0) AS fn_acl_ok,
    (o.pu IS NOT NULL AND o.pi IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_class WHERE oid IN (o.pu,o.pi) AND (relrowsecurity OR relforcerowsecurity))
     AND NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid IN (o.pu,o.pi))) AS rls_ok
  FROM o
)
SELECT
  (CASE WHEN e_pu THEN 1 ELSE 0 END + CASE WHEN e_pi THEN 1 ELSE 0 END
   + CASE WHEN e_seq THEN 1 ELSE 0 END + CASE WHEN e_fn THEN 1 ELSE 0 END) AS portal_objetos,    -- esperado 4
  CASE WHEN fk_pu_ok    THEN 'OK' ELSE 'FALLA' END  AS fk_usuarios_auth,    -- user_id->auth.users(id) ON DELETE CASCADE
  CASE WHEN fk_pi_ok    THEN 'OK' ELSE 'FALLA' END  AS fk_idem_gasto,       -- id_gasto->gastos_internos(id_gasto) RESTRICT
  CASE WHEN chk_rol_ok  THEN 'OK' ELSE 'FALLA' END  AS check_rol,           -- {jenny,vicky,socio}
  CASE WHEN uq_nombre_ok AND uq_nonce_ok AND uq_actkey_ok THEN 'OK' ELSE 'FALLA' END AS uniques,
  CASE WHEN fn_firma_ok THEN 'OK' ELSE 'FALLA' END  AS func_firma,          -- jsonb + INVOKER + plpgsql
  CASE WHEN pu_acl_ok   THEN 'OK' ELSE 'FALLA' END  AS pu_acl,              -- solo service_role:SELECT
  CASE WHEN pi_acl_ok   THEN 'OK' ELSE 'FALLA' END  AS pi_acl,              -- sin Data API
  CASE WHEN seq_acl_ok  THEN 'OK' ELSE 'FALLA' END  AS seq_acl,             -- sin Data API
  CASE WHEN fn_acl_ok   THEN 'OK' ELSE 'FALLA' END  AS fn_acl,              -- proacl no null + sin Data API
  CASE WHEN rls_ok      THEN 'OK' ELSE 'FALLA' END  AS rls_policies,        -- RLS off, 0 policies
  CASE WHEN e_pu AND e_pi AND e_seq AND e_fn AND fk_pu_ok AND fk_pi_ok AND chk_rol_ok
        AND uq_nombre_ok AND uq_nonce_ok AND uq_actkey_ok AND fn_firma_ok
        AND pu_acl_ok AND pi_acl_ok AND seq_acl_ok AND fn_acl_ok AND rls_ok
       THEN 'ENTORNO_COMPLETO_OK'
       ELSE 'ENTORNO_INCOMPLETO -> revisar la columna en FALLA'
  END AS veredicto
FROM chk;


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 2 — ACL de los objetos del portal (read-only; informativo)
-- ----------------------------------------------------------------------------
-- ESPERADO: la ÚNICA fila con un rol Data API es service_role=SELECT sobre
-- portal_usuarios. portal_idempotencia y su secuencia NO deben aparecer. La
-- función queda cubierta por la columna fn_acl de la QUERY 1.
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
  AND c.relname IN ('portal_usuarios','portal_idempotencia','portal_idempotencia_id_registro_seq')
  AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
GROUP BY c.relkind, c.relname, a.grantee
ORDER BY c.relname, rol;
