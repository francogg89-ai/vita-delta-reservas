-- ============================================================================
-- CC_RETIRO_SB0_B_VERIFY_TEST.sql
-- Frente: Cuenta Corriente ESCRITURA (retiros desde saldo vivo)
-- Verificacion del Sub-bloque 0: ESTRUCTURAL + PRUEBAS NEGATIVAS EFIMERAS.
-- NO es read-only: incluye UPDATEs de prueba que SIEMPRE se revierten
-- (savepoint interno de plpgsql por bloque BEGIN/EXCEPTION + ROLLBACK final).
-- Garantia de CERO RESIDUO.
-- Entorno: TEST unicamente (gate anti-OPS propio por configuracion_general('ambiente')='test').
-- Correr el script COMPLETO (sin seleccion) en el SQL Editor de Supabase (L-8A-01).
-- ----------------------------------------------------------------------------
-- NOTA D5: esta verificacion REEMPLAZA, para el estado SB0, la cobertura de
-- portal_usuarios del auto-test D5 canonico. D5 asume UNA sola FK en
-- portal_usuarios (la resuelve sin conname); tras SB0 hay DOS FKs, por lo que
-- D5 queda PENDIENTE de extension en el cierre v1.11.0 y NO debe usarse sin
-- adaptar como verificacion post-SB0.
-- ============================================================================

BEGIN;

-- ---- Gate anti-OPS propio (solo TEST) -------------------------------------
DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE ambiente=% (esperado test) -- abortado, sin cambios', COALESCE(v_amb, '(null)');
  END IF;
END $gate$;

-- ===========================================================================
-- PARTE 1 -- Verificacion estructural (por catalogo, PG16/PG17-agnostica).
-- FKs resueltas por conrelid/confrelid/columna local/confdeltype (no por nombre).
-- ===========================================================================
DO $estruct$
DECLARE
  v_pu     oid := to_regclass('public.portal_usuarios');
  v_socios oid := to_regclass('public.socios');
  v_auth   oid := to_regclass('auth.users');
  r        record;
  v_n      int;
  v_txt    text;
BEGIN
  IF v_pu     IS NULL THEN RAISE EXCEPTION 'V: portal_usuarios ausente'; END IF;
  IF v_socios IS NULL THEN RAISE EXCEPTION 'V: socios ausente'; END IF;
  IF v_auth   IS NULL THEN RAISE EXCEPTION 'V: auth.users ausente -- se requiere proyecto Supabase'; END IF;

  -- (1) columna id_socio: existe, tipo bigint, nullable
  SELECT a.atttypid::regtype::text AS typ, a.attnotnull AS notnull
    INTO r
    FROM pg_attribute a
   WHERE a.attrelid = v_pu AND a.attname = 'id_socio' AND NOT a.attisdropped;
  IF NOT FOUND THEN RAISE EXCEPTION 'V: falta columna portal_usuarios.id_socio'; END IF;
  IF r.typ <> 'bigint' THEN RAISE EXCEPTION 'V: id_socio no es bigint (es %)', r.typ; END IF;
  IF r.notnull THEN RAISE EXCEPTION 'V: id_socio debe ser nullable, esta como NOT NULL'; END IF;

  -- (2) portal_usuarios debe tener EXACTAMENTE 2 FKs
  SELECT count(*) INTO v_n FROM pg_constraint WHERE conrelid = v_pu AND contype = 'f';
  IF v_n <> 2 THEN RAISE EXCEPTION 'V: portal_usuarios debe tener 2 FKs, tiene %', v_n; END IF;

  -- (3) FK nueva por columna local id_socio -> socios(id_socio) ON DELETE RESTRICT
  SELECT con.conname, con.confrelid, con.confdeltype, cardinality(con.conkey) AS ncols,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1]) AS rcol
    INTO r
    FROM pg_constraint con
   WHERE con.conrelid = v_pu AND con.contype = 'f'
     AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid AND a.attnum=con.conkey[1]) = 'id_socio';
  IF NOT FOUND THEN RAISE EXCEPTION 'V: no hay FK sobre columna local id_socio'; END IF;
  IF r.conname <> 'fk_portal_usuarios_id_socio' THEN
    RAISE EXCEPTION 'V: FK de id_socio con nombre inesperado: %', r.conname;
  END IF;
  IF r.confrelid IS DISTINCT FROM v_socios OR r.rcol <> 'id_socio' OR r.ncols <> 1 OR r.confdeltype <> 'r' THEN
    RAISE EXCEPTION 'V: FK id_socio no es -> socios(id_socio) ON DELETE RESTRICT [ref=%, rcol=%, ncols=%, del=%]',
      r.confrelid::regclass, r.rcol, r.ncols, r.confdeltype;
  END IF;

  -- (4) FK existente por columna local user_id -> auth.users(id) ON DELETE CASCADE (intacta)
  SELECT con.confrelid, con.confdeltype, cardinality(con.conkey) AS ncols,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1]) AS rcol
    INTO r
    FROM pg_constraint con
   WHERE con.conrelid = v_pu AND con.contype = 'f'
     AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid AND a.attnum=con.conkey[1]) = 'user_id';
  IF NOT FOUND THEN RAISE EXCEPTION 'V: no hay FK sobre columna local user_id'; END IF;
  IF r.confrelid IS DISTINCT FROM v_auth OR r.rcol <> 'id' OR r.ncols <> 1 OR r.confdeltype <> 'c' THEN
    RAISE EXCEPTION 'V: FK user_id no es -> auth.users(id) ON DELETE CASCADE [ref=%, rcol=%, ncols=%, del=%]',
      r.confrelid::regclass, r.rcol, r.ncols, r.confdeltype;
  END IF;

  -- (5) UNIQUE(id_socio) exacta, por conjunto de columnas
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint con
     WHERE con.conrelid = v_pu AND con.contype = 'u' AND con.conname = 'uq_portal_usuarios_id_socio'
       AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
              FROM unnest(con.conkey) AS ck(attnum)
              JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['id_socio']
  ) THEN RAISE EXCEPTION 'V: uq_portal_usuarios_id_socio no es UNIQUE(id_socio)'; END IF;

  -- (6) UNIQUE(nombre) existente, intacta
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint con
     WHERE con.conrelid = v_pu AND con.contype = 'u' AND con.conname = 'uq_portal_usuarios_nombre'
       AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
              FROM unnest(con.conkey) AS ck(attnum)
              JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['nombre']
  ) THEN RAISE EXCEPTION 'V: uq_portal_usuarios_nombre (existente) no es UNIQUE(nombre) o falta'; END IF;

  -- (7) CHECK bicondicional presente y con la forma esperada
  SELECT pg_get_constraintdef(con.oid) INTO v_txt
    FROM pg_constraint con
   WHERE con.conrelid = v_pu AND con.contype = 'c' AND con.conname = 'chk_portal_usuarios_socio_rol';
  IF v_txt IS NULL THEN RAISE EXCEPTION 'V: falta CHECK chk_portal_usuarios_socio_rol'; END IF;
  IF v_txt NOT ILIKE '%id_socio%' OR v_txt NOT ILIKE '%is not null%' OR v_txt NOT ILIKE '%socio%' THEN
    RAISE EXCEPTION 'V: CHECK bicondicional con forma inesperada: %', v_txt;
  END IF;

  -- (8) ACL: unica concesion Data API/PUBLIC = (service_role, SELECT); y service_role LEE
  --     (aclexplode: cubre TODOS los privilegios incl. MAINTAIN de PG17, sin depender de version)
  SELECT count(*) INTO v_n
    FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
   WHERE c.oid = v_pu
     AND (a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
     AND NOT (a.grantee <> 0 AND pg_get_userbyid(a.grantee) = 'service_role' AND a.privilege_type = 'SELECT');
  IF v_n > 0 THEN
    RAISE EXCEPTION 'V: portal_usuarios con privilegios Data API distintos de service_role:SELECT (%)', v_n;
  END IF;
  IF NOT has_table_privilege('service_role','public.portal_usuarios','SELECT') THEN
    RAISE EXCEPTION 'V: service_role no puede leer portal_usuarios';
  END IF;

  RAISE NOTICE 'PARTE 1 OK: columna, 2 FKs, 2 UNIQUE, CHECK y ACL (service_role:SELECT) verificados';
END $estruct$;

-- ===========================================================================
-- PARTE 2 -- Datos: mapeo 1:1 real (no hardcodea "3 socios")
-- ===========================================================================
DO $datos$
DECLARE v_sinmatch int; v_nonsoc int; v_colis int;
BEGIN
  SELECT count(*) INTO v_sinmatch FROM public.portal_usuarios WHERE rol = 'socio' AND id_socio IS NULL;
  IF v_sinmatch > 0 THEN RAISE EXCEPTION 'V-datos: % filas rol=socio sin id_socio', v_sinmatch; END IF;

  SELECT count(*) INTO v_nonsoc FROM public.portal_usuarios WHERE rol <> 'socio' AND id_socio IS NOT NULL;
  IF v_nonsoc > 0 THEN RAISE EXCEPTION 'V-datos: % filas no-socio con id_socio', v_nonsoc; END IF;

  SELECT count(*) INTO v_colis
    FROM (SELECT id_socio FROM public.portal_usuarios
           WHERE id_socio IS NOT NULL GROUP BY id_socio HAVING count(*) > 1) d;
  IF v_colis > 0 THEN RAISE EXCEPTION 'V-datos: % id_socio duplicados', v_colis; END IF;

  RAISE NOTICE 'PARTE 2 OK: mapeo 1:1 (rol=socio<->socios), sin id_socio en no-socios, sin duplicados';
END $datos$;

-- ===========================================================================
-- PARTE 3 -- Pruebas negativas EFIMERAS (cada UPDATE se revierte solo via
--            savepoint interno del bloque BEGIN/EXCEPTION de plpgsql).
-- ===========================================================================

-- NEG1: setear id_socio en una fila NO-socio debe violar el CHECK
DO $neg1$
DECLARE v_uid uuid; v_sid bigint; v_fired boolean := false;
BEGIN
  SELECT user_id INTO v_uid FROM public.portal_usuarios WHERE rol <> 'socio' LIMIT 1;
  SELECT id_socio INTO v_sid FROM public.socios LIMIT 1;
  IF v_uid IS NULL OR v_sid IS NULL THEN
    RAISE NOTICE 'NEG1 SKIP: faltan filas (no-socio y/o socios) para la prueba';
    RETURN;
  END IF;
  BEGIN
    UPDATE public.portal_usuarios SET id_socio = v_sid WHERE user_id = v_uid;
  EXCEPTION WHEN check_violation THEN
    v_fired := true;
  END;
  IF NOT v_fired THEN
    RAISE EXCEPTION 'NEG1 FALLO: setear id_socio en no-socio NO violo el CHECK';
  END IF;
  RAISE NOTICE 'NEG1 PASS: CHECK bloquea id_socio en fila no-socio';
END $neg1$;

-- NEG2: duplicar un id_socio en dos filas socio debe violar UNIQUE
DO $neg2$
DECLARE v_a uuid; v_b uuid; v_sid_a bigint; v_fired boolean := false;
BEGIN
  SELECT user_id, id_socio INTO v_a, v_sid_a
    FROM public.portal_usuarios WHERE rol = 'socio' AND id_socio IS NOT NULL
    ORDER BY id_socio LIMIT 1;
  SELECT user_id INTO v_b
    FROM public.portal_usuarios
   WHERE rol = 'socio' AND id_socio IS NOT NULL AND id_socio <> v_sid_a
   ORDER BY id_socio LIMIT 1;
  IF v_a IS NULL OR v_b IS NULL THEN
    RAISE NOTICE 'NEG2 SKIP: se necesitan >=2 socios con id_socio distinto';
    RETURN;
  END IF;
  BEGIN
    UPDATE public.portal_usuarios SET id_socio = v_sid_a WHERE user_id = v_b;
  EXCEPTION WHEN unique_violation THEN
    v_fired := true;
  END;
  IF NOT v_fired THEN
    RAISE EXCEPTION 'NEG2 FALLO: id_socio duplicado NO violo UNIQUE';
  END IF;
  RAISE NOTICE 'NEG2 PASS: UNIQUE bloquea id_socio duplicado';
END $neg2$;

-- NEG3: dejar rol=socio con id_socio NULL debe violar el CHECK
DO $neg3$
DECLARE v_uid uuid; v_fired boolean := false;
BEGIN
  SELECT user_id INTO v_uid FROM public.portal_usuarios WHERE rol = 'socio' AND id_socio IS NOT NULL LIMIT 1;
  IF v_uid IS NULL THEN
    RAISE NOTICE 'NEG3 SKIP: no hay fila rol=socio con id_socio';
    RETURN;
  END IF;
  BEGIN
    UPDATE public.portal_usuarios SET id_socio = NULL WHERE user_id = v_uid;
  EXCEPTION WHEN check_violation THEN
    v_fired := true;
  END;
  IF NOT v_fired THEN
    RAISE EXCEPTION 'NEG3 FALLO: rol=socio con id_socio NULL NO violo el CHECK';
  END IF;
  RAISE NOTICE 'NEG3 PASS: CHECK exige id_socio cuando rol=socio';
END $neg3$;

-- ---- Veredicto visible (ultima result set antes del ROLLBACK) -------------
SELECT 'SB0 VERIFY OK: estructura + datos + 3 pruebas negativas (cero residuo)' AS resultado;

ROLLBACK;
