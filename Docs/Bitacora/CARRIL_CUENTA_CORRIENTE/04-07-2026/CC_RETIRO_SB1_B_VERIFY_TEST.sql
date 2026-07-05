-- ============================================================================
-- CC_RETIRO_SB1_B_VERIFY_TEST.sql
-- Frente: Cuenta Corriente ESCRITURA (retiros desde saldo vivo)
-- Verificacion del Sub-bloque 1: ESTRUCTURAL + PRUEBAS FUNCIONALES EFIMERAS.
-- NO es read-only: siembra un credito y ejecuta retiros de prueba. TODO se
-- revierte (ROLLBACK final). Garantia de CERO RESIDUO.
-- Entorno: TEST unicamente (gate anti-OPS propio por configuracion_general('ambiente')='test').
-- Correr el script COMPLETO (sin seleccion) en el SQL Editor de Supabase (L-8A-01).
-- Semantica de resultado: si NINGUN bloque lanza EXCEPTION, el script llega al
--   SELECT final 'SB1 VERIFY OK'. Cualquier fallo aborta con un mensaje T# claro.
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
-- PARTE 1 -- Estructural (catalogo / aclexplode; PG16/PG17-agnostica)
-- ===========================================================================
DO $estruct$
DECLARE
  v_tbl  oid := to_regclass('public.portal_idempotencia_cc');
  v_seq  oid := to_regclass('public.portal_idempotencia_cc_id_registro_seq');
  v_mov  oid := to_regclass('public.movimientos_socio');
  v_f1   oid := to_regprocedure('public.registrar_retiro_desde_saldo_vivo(bigint, numeric, text, text, text)');
  v_f2   oid := to_regprocedure('public.portal_registrar_retiro(jsonb)');
  r      record;
  v_n    int;
  v_txt  text;
  v_col  text;
BEGIN
  IF v_tbl IS NULL THEN RAISE EXCEPTION 'V: portal_idempotencia_cc ausente'; END IF;
  IF v_seq IS NULL THEN RAISE EXCEPTION 'V: secuencia portal_idempotencia_cc_id_registro_seq ausente'; END IF;
  IF v_mov IS NULL THEN RAISE EXCEPTION 'V: movimientos_socio ausente'; END IF;
  IF v_f1  IS NULL THEN RAISE EXCEPTION 'V: registrar_retiro_desde_saldo_vivo ausente'; END IF;
  IF v_f2  IS NULL THEN RAISE EXCEPTION 'V: portal_registrar_retiro(jsonb) ausente'; END IF;

  -- (1) columnas esperadas (nombre + tipo de las criticas)
  FOR v_col IN SELECT unnest(ARRAY['id_registro','action','actor','rol','source_event','nonce',
                                   'idempotency_key','payload_norm','id_movimiento','estado',
                                   'request_ts','created_at'])
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid=v_tbl AND attname=v_col AND NOT attisdropped) THEN
      RAISE EXCEPTION 'V: falta columna portal_idempotencia_cc.%', v_col;
    END IF;
  END LOOP;
  SELECT atttypid::regtype::text INTO v_txt FROM pg_attribute WHERE attrelid=v_tbl AND attname='id_movimiento';
  IF v_txt <> 'bigint' THEN RAISE EXCEPTION 'V: id_movimiento no es bigint (%)', v_txt; END IF;
  SELECT atttypid::regtype::text INTO v_txt FROM pg_attribute WHERE attrelid=v_tbl AND attname='payload_norm';
  IF v_txt <> 'jsonb' THEN RAISE EXCEPTION 'V: payload_norm no es jsonb (%)', v_txt; END IF;

  -- (2) FK fk_portal_idem_cc_mov -> movimientos_socio(id_movimiento) ON DELETE RESTRICT
  SELECT con.confrelid, con.confdeltype, cardinality(con.conkey) AS ncols,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid  AND a.attnum=con.conkey[1])  AS lcol,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1]) AS rcol
    INTO r
    FROM pg_constraint con
   WHERE con.conrelid=v_tbl AND con.contype='f' AND con.conname='fk_portal_idem_cc_mov';
  IF NOT FOUND THEN RAISE EXCEPTION 'V: falta FK fk_portal_idem_cc_mov'; END IF;
  IF r.confrelid IS DISTINCT FROM v_mov OR r.lcol<>'id_movimiento' OR r.rcol<>'id_movimiento'
     OR r.ncols<>1 OR r.confdeltype<>'r' THEN
    RAISE EXCEPTION 'V: FK no es id_movimiento -> movimientos_socio(id_movimiento) ON DELETE RESTRICT [ref=%,lcol=%,rcol=%,del=%]',
      r.confrelid::regclass, r.lcol, r.rcol, r.confdeltype;
  END IF;

  -- (3) UNIQUEs por conjunto exacto de columnas
  IF NOT EXISTS (SELECT 1 FROM pg_constraint con
                  WHERE con.conrelid=v_tbl AND con.contype='u' AND con.conname='uq_portal_idem_cc_nonce'
                    AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                           FROM unnest(con.conkey) AS ck(attnum)
                           JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['nonce']) THEN
    RAISE EXCEPTION 'V: uq_portal_idem_cc_nonce no es UNIQUE(nonce)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint con
                  WHERE con.conrelid=v_tbl AND con.contype='u' AND con.conname='uq_portal_idem_cc_action_key'
                    AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                           FROM unnest(con.conkey) AS ck(attnum)
                           JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['action','idempotency_key']) THEN
    RAISE EXCEPTION 'V: uq_portal_idem_cc_action_key no es UNIQUE(action,idempotency_key)';
  END IF;

  -- (4) CHECKs esperados presentes; rol restringido a socio; estado a ok
  FOR v_col IN SELECT unnest(ARRAY['chk_portal_idem_cc_action_ne','chk_portal_idem_cc_actor_ne',
                                   'chk_portal_idem_cc_source_ne','chk_portal_idem_cc_nonce_ne',
                                   'chk_portal_idem_cc_idem_ne','chk_portal_idem_cc_rol','chk_portal_idem_cc_estado'])
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid=v_tbl AND contype='c' AND conname=v_col) THEN
      RAISE EXCEPTION 'V: falta CHECK %', v_col;
    END IF;
  END LOOP;
  SELECT pg_get_constraintdef(oid) INTO v_txt FROM pg_constraint WHERE conrelid=v_tbl AND conname='chk_portal_idem_cc_rol';
  IF v_txt NOT ILIKE '%socio%' THEN RAISE EXCEPTION 'V: chk_portal_idem_cc_rol no restringe a socio: %', v_txt; END IF;
  SELECT pg_get_constraintdef(oid) INTO v_txt FROM pg_constraint WHERE conrelid=v_tbl AND conname='chk_portal_idem_cc_estado';
  IF v_txt NOT ILIKE '%ok%' THEN RAISE EXCEPTION 'V: chk_portal_idem_cc_estado no restringe a ok: %', v_txt; END IF;

  -- (5) ACL tabla + secuencia: cero privilegios Data API / PUBLIC
  SELECT count(*) INTO v_n FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
   WHERE c.oid=v_tbl AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_n>0 THEN RAISE EXCEPTION 'V: portal_idempotencia_cc con privilegios Data API (%)', v_n; END IF;
  SELECT count(*) INTO v_n FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
   WHERE c.oid=v_seq AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_n>0 THEN RAISE EXCEPTION 'V: secuencia con privilegios Data API (%)', v_n; END IF;

  -- (6) Firmas de funciones: RETURNS + SECURITY INVOKER + plpgsql + search_path
  SELECT p.prorettype, p.prosecdef, l.lanname,
         EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig,'{}')) e WHERE e LIKE 'search_path=%') AS has_sp
    INTO r FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=v_f1;
  IF r.prorettype IS DISTINCT FROM 'bigint'::regtype THEN RAISE EXCEPTION 'V: negocio no RETURNS bigint'; END IF;
  IF r.prosecdef THEN RAISE EXCEPTION 'V: negocio no es SECURITY INVOKER'; END IF;
  IF r.lanname<>'plpgsql' THEN RAISE EXCEPTION 'V: negocio no es plpgsql'; END IF;
  IF NOT r.has_sp THEN RAISE EXCEPTION 'V: negocio sin SET search_path'; END IF;

  SELECT p.prorettype, p.prosecdef, l.lanname,
         EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig,'{}')) e WHERE e LIKE 'search_path=%') AS has_sp
    INTO r FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=v_f2;
  IF r.prorettype IS DISTINCT FROM 'jsonb'::regtype THEN RAISE EXCEPTION 'V: wrapper no RETURNS jsonb'; END IF;
  IF r.prosecdef THEN RAISE EXCEPTION 'V: wrapper no es SECURITY INVOKER'; END IF;
  IF r.lanname<>'plpgsql' THEN RAISE EXCEPTION 'V: wrapper no es plpgsql'; END IF;
  IF NOT r.has_sp THEN RAISE EXCEPTION 'V: wrapper sin SET search_path'; END IF;

  -- (7) EXECUTE ACL de ambas funciones: proacl no nula (si nula, PUBLIC ejecuta)
  --     + cero EXECUTE para Data API / PUBLIC.
  IF (SELECT proacl FROM pg_proc WHERE oid=v_f1) IS NULL THEN RAISE EXCEPTION 'V: negocio proacl NULL (PUBLIC ejecuta)'; END IF;
  IF (SELECT proacl FROM pg_proc WHERE oid=v_f2) IS NULL THEN RAISE EXCEPTION 'V: wrapper proacl NULL (PUBLIC ejecuta)'; END IF;
  SELECT count(*) INTO v_n FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
   WHERE p.oid=v_f1 AND a.privilege_type='EXECUTE'
     AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_n>0 THEN RAISE EXCEPTION 'V: negocio con EXECUTE Data API (%)', v_n; END IF;
  SELECT count(*) INTO v_n FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
   WHERE p.oid=v_f2 AND a.privilege_type='EXECUTE'
     AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_n>0 THEN RAISE EXCEPTION 'V: wrapper con EXECUTE Data API (%)', v_n; END IF;

  RAISE NOTICE 'PARTE 1 OK: tabla/columnas/FK/UNIQUEs/CHECKs/secuencia/ACL + firmas y EXECUTE ACL de ambas funciones';
END $estruct$;

-- ===========================================================================
-- PARTE 2+3 -- Setup + pruebas funcionales EFIMERAS (un solo bloque comparte estado)
-- ===========================================================================
DO $func$
DECLARE
  v_s1 bigint; v_s2 bigint; v_actor1 text; v_actor2 text;
  v_Snow numeric; v_Sfinal numeric;
  v_over numeric(14,2); v_A numeric(14,2); v_amt8 numeric(14,2);
  v_key text; v_key6 text; v_key8 text; v_key9 text;
  v_res jsonb; v_pl jsonb; v_pl2 jsonb; v_pn8 jsonb;
  v_mov bigint; v_num numeric; v_cnt int; v_cb int; v_ca int;
  v_hoy date := (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
BEGIN
  -- setup: dos socios con mapeo activo en portal_usuarios
  SELECT id_socio, nombre INTO v_s1, v_actor1 FROM public.portal_usuarios
   WHERE rol='socio' AND activo IS TRUE ORDER BY id_socio LIMIT 1;
  SELECT id_socio, nombre INTO v_s2, v_actor2 FROM public.portal_usuarios
   WHERE rol='socio' AND activo IS TRUE AND id_socio <> v_s1 ORDER BY id_socio LIMIT 1;
  IF v_s1 IS NULL OR v_s2 IS NULL THEN
    RAISE EXCEPTION 'setup: se requieren >=2 socios con portal_usuarios activo';
  END IF;

  -- credito controlado para tener saldo positivo conocido (ajuste_manual +1.000.000)
  INSERT INTO public.movimientos_socio (id_socio, fecha, tipo, monto, comentario, creado_por)
  VALUES (v_s1, v_hoy, 'ajuste_manual', 1000000.00, 'verify seed credit', 'verify');

  ------------------------------------------------------------------ T1: retiro exitoso, monto negativo
  v_pl := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
          'nonce',gen_random_uuid()::text,'idempotency_key',gen_random_uuid()::text,
          'monto','100.00','medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl);
  IF NOT (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T1 FALLO: retiro exitoso devolvio %', v_res; END IF;
  v_mov := (v_res->'data'->>'id_movimiento')::bigint;
  SELECT monto INTO v_num FROM public.movimientos_socio WHERE id_movimiento=v_mov;
  IF v_num <> -100.00 THEN RAISE EXCEPTION 'T1 FALLO: monto esperado -100.00, got %', v_num; END IF;
  IF (v_res->'data'->>'idempotente')::boolean THEN RAISE EXCEPTION 'T1 FALLO: idempotente debe ser false'; END IF;
  RAISE NOTICE 'T1 PASS: retiro exitoso, movimiento %=% (negativo)', v_mov, v_num;

  ------------------------------------------------------------------ T2: saldo_insuficiente con detail
  SELECT saldo_al_dia INTO v_Snow FROM public.cuenta_corriente_viva(NULL, public.pct_operativo_vigente()) WHERE id_socio=v_s1;
  v_over := (v_Snow + 1000)::numeric(14,2);
  v_pl := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
          'nonce',gen_random_uuid()::text,'idempotency_key',gen_random_uuid()::text,
          'monto',trim(to_char(v_over,'FM999999999999990.00')),'medio_pago','transferencia_bancaria');
  v_res := public.portal_registrar_retiro(v_pl);
  IF (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T2 FALLO: deberia ser saldo_insuficiente, got %', v_res; END IF;
  IF v_res->'error'->>'code' <> 'saldo_insuficiente' THEN RAISE EXCEPTION 'T2 FALLO: code % esperado saldo_insuficiente', v_res->'error'->>'code'; END IF;
  IF (v_res->'error'->'detail'->'saldo_disponible') IS NULL OR (v_res->'error'->'detail'->'monto_solicitado') IS NULL THEN
    RAISE EXCEPTION 'T2 FALLO: falta saldo_disponible/monto_solicitado en detail: %', v_res->'error'->'detail'; END IF;
  RAISE NOTICE 'T2 PASS: saldo_insuficiente, detail=%', v_res->'error'->'detail';

  ------------------------------------------------------------------ T3: >2 decimales NO se redondea
  SELECT count(*) INTO v_cb FROM public.movimientos_socio WHERE id_socio=v_s1 AND tipo='retiro';
  v_pl := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
          'nonce',gen_random_uuid()::text,'idempotency_key',gen_random_uuid()::text,
          'monto','100.999','medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl);
  IF (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T3 FALLO: 100.999 NO debe pasar (redondeo), got %', v_res; END IF;
  IF v_res->'error'->>'code' <> 'payload_invalido' THEN RAISE EXCEPTION 'T3 FALLO: code % esperado payload_invalido', v_res->'error'->>'code'; END IF;
  SELECT count(*) INTO v_ca FROM public.movimientos_socio WHERE id_socio=v_s1 AND tipo='retiro';
  IF v_ca <> v_cb THEN RAISE EXCEPTION 'T3 FALLO: se creo un movimiento (redondeo silencioso!)'; END IF;
  RAISE NOTICE 'T3 PASS: 100.999 rechazado payload_invalido, sin movimiento (no redondeo)';

  ------------------------------------------------------------------ T4: medio invalido
  v_pl := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
          'nonce',gen_random_uuid()::text,'idempotency_key',gen_random_uuid()::text,
          'monto','100.00','medio_pago','transferencia_mp');
  v_res := public.portal_registrar_retiro(v_pl);
  IF (v_res->>'ok')::boolean OR v_res->'error'->>'code' <> 'payload_invalido' THEN
    RAISE EXCEPTION 'T4 FALLO: medio invalido esperado payload_invalido, got %', v_res; END IF;
  RAISE NOTICE 'T4 PASS: medio invalido -> payload_invalido';

  ------------------------------------------------------------------ T5: actor/id_socio mismatch
  v_pl := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s2,
          'nonce',gen_random_uuid()::text,'idempotency_key',gen_random_uuid()::text,
          'monto','100.00','medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl);
  IF (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T5 FALLO: mismatch deberia rechazar, got %', v_res; END IF;
  IF v_res->'error'->>'code' <> 'error_interno' OR v_res->'error'->'detail'->>'reason' <> 'identity_mismatch' THEN
    RAISE EXCEPTION 'T5 FALLO: esperado error_interno/identity_mismatch, got %', v_res->'error'; END IF;
  RAISE NOTICE 'T5 PASS: actor/id_socio mismatch -> error_interno/identity_mismatch';

  ------------------------------------------------------------------ T6: idempotencia retry (mismo key/payload/actor, nonce nuevo)
  v_key6 := gen_random_uuid()::text;
  v_pl := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
          'nonce',gen_random_uuid()::text,'idempotency_key',v_key6,
          'monto','100.00','medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl);
  IF NOT (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T6 FALLO call1: %', v_res; END IF;
  v_mov := (v_res->'data'->>'id_movimiento')::bigint;
  SELECT count(*) INTO v_cb FROM public.movimientos_socio WHERE id_socio=v_s1 AND tipo='retiro';
  v_pl2 := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
           'nonce',gen_random_uuid()::text,'idempotency_key',v_key6,
           'monto','100.00','medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl2);
  IF NOT (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T6 FALLO retry: %', v_res; END IF;
  IF NOT (v_res->'data'->>'idempotente')::boolean THEN RAISE EXCEPTION 'T6 FALLO: retry no marco idempotente'; END IF;
  IF (v_res->'data'->>'id_movimiento')::bigint <> v_mov THEN RAISE EXCEPTION 'T6 FALLO: id_movimiento distinto en retry'; END IF;
  SELECT count(*) INTO v_ca FROM public.movimientos_socio WHERE id_socio=v_s1 AND tipo='retiro';
  IF v_ca <> v_cb THEN RAISE EXCEPTION 'T6 FALLO: retry creo un segundo movimiento'; END IF;
  RAISE NOTICE 'T6 PASS: retry mismo key -> mismo id_movimiento %, idempotente, sin doble asiento', v_mov;

  ------------------------------------------------------------------ T7: payload mismatch (mismo key T6, distinto monto)
  v_pl := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
          'nonce',gen_random_uuid()::text,'idempotency_key',v_key6,
          'monto','200.00','medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl);
  IF (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T7 FALLO: payload distinto deberia dar conflicto, got %', v_res; END IF;
  IF v_res->'error'->>'code' <> 'conflicto' OR v_res->'error'->'detail'->>'reason' <> 'payload_mismatch' THEN
    RAISE EXCEPTION 'T7 FALLO: esperado conflicto/payload_mismatch, got %', v_res->'error'; END IF;
  RAISE NOTICE 'T7 PASS: mismo key distinto payload -> conflicto/payload_mismatch';

  ------------------------------------------------------------------ T8: actor mismatch (pre-seed; backstop bajo identity binding)
  v_key8 := gen_random_uuid()::text;
  v_amt8 := 100.00::numeric(14,2);
  v_pn8  := jsonb_build_object('id_socio',v_s1,'monto',v_amt8,'medio_pago','efectivo','comentario',NULL);
  INSERT INTO public.portal_idempotencia_cc
    (action, actor, rol, source_event, nonce, idempotency_key, payload_norm, id_movimiento)
  VALUES ('cuenta_corriente.retirar','actor_falso','socio','seed_t8',gen_random_uuid()::text,v_key8,v_pn8,v_mov);
  v_pl := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
          'nonce',gen_random_uuid()::text,'idempotency_key',v_key8,
          'monto','100.00','medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl);
  IF (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T8 FALLO: actor distinto deberia dar conflicto, got %', v_res; END IF;
  IF v_res->'error'->>'code' <> 'conflicto' OR v_res->'error'->'detail'->>'reason' <> 'actor_mismatch' THEN
    RAISE EXCEPTION 'T8 FALLO: esperado conflicto/actor_mismatch, got %', v_res->'error'; END IF;
  RAISE NOTICE 'T8 PASS: mismo key/payload distinto actor -> conflicto/actor_mismatch';

  ------------------------------------------------------------------ T9: saldo_insuficiente NO quema la key
  v_key9 := gen_random_uuid()::text;
  SELECT saldo_al_dia INTO v_Snow FROM public.cuenta_corriente_viva(NULL, public.pct_operativo_vigente()) WHERE id_socio=v_s1;
  v_over := (v_Snow + 1000)::numeric(14,2);
  v_pl := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
          'nonce',gen_random_uuid()::text,'idempotency_key',v_key9,
          'monto',trim(to_char(v_over,'FM999999999999990.00')),'medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl);
  IF v_res->'error'->>'code' <> 'saldo_insuficiente' THEN RAISE EXCEPTION 'T9 FALLO call1: esperado saldo_insuficiente, got %', v_res; END IF;
  SELECT count(*) INTO v_cnt FROM public.portal_idempotencia_cc WHERE action='cuenta_corriente.retirar' AND idempotency_key=v_key9;
  IF v_cnt <> 0 THEN RAISE EXCEPTION 'T9 FALLO: la key se quemo (fila en _cc)'; END IF;
  v_pl2 := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
           'nonce',gen_random_uuid()::text,'idempotency_key',v_key9,
           'monto','100.00','medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl2);
  IF NOT (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T9 FALLO call2: esperado exito con key libre, got %', v_res; END IF;
  IF (v_res->'data'->>'idempotente')::boolean THEN RAISE EXCEPTION 'T9 FALLO: call2 no deberia ser idempotente'; END IF;
  RAISE NOTICE 'T9 PASS: saldo_insuficiente no quema la key; retry con misma key exitoso';

  ------------------------------------------------------------------ T10: concurrencia secuencial (2 retiros; 1 OK + 1 saldo_insuficiente)
  SELECT saldo_al_dia INTO v_Snow FROM public.cuenta_corriente_viva(NULL, public.pct_operativo_vigente()) WHERE id_socio=v_s1;
  v_A := ROUND(v_Snow * 0.7, 2)::numeric(14,2);
  SELECT count(*) INTO v_cb FROM public.movimientos_socio WHERE id_socio=v_s1 AND tipo='retiro';
  v_pl := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
          'nonce',gen_random_uuid()::text,'idempotency_key',gen_random_uuid()::text,
          'monto',trim(to_char(v_A,'FM999999999999990.00')),'medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl);
  IF NOT (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T10 FALLO retiro1: esperado OK (A<S), got %', v_res; END IF;
  v_pl2 := jsonb_build_object('actor',v_actor1,'rol','socio','id_socio',v_s1,
           'nonce',gen_random_uuid()::text,'idempotency_key',gen_random_uuid()::text,
           'monto',trim(to_char(v_A,'FM999999999999990.00')),'medio_pago','efectivo');
  v_res := public.portal_registrar_retiro(v_pl2);
  IF (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'T10 FALLO retiro2: esperado saldo_insuficiente (A+B>S), got %', v_res; END IF;
  IF v_res->'error'->>'code' <> 'saldo_insuficiente' THEN RAISE EXCEPTION 'T10 FALLO retiro2 code: %', v_res->'error'->>'code'; END IF;
  SELECT count(*) INTO v_ca FROM public.movimientos_socio WHERE id_socio=v_s1 AND tipo='retiro';
  IF v_ca - v_cb <> 1 THEN RAISE EXCEPTION 'T10 FALLO: esperado 1 movimiento nuevo, got %', v_ca - v_cb; END IF;
  SELECT saldo_al_dia INTO v_Sfinal FROM public.cuenta_corriente_viva(NULL, public.pct_operativo_vigente()) WHERE id_socio=v_s1;
  IF v_Sfinal < 0 THEN RAISE EXCEPTION 'T10 FALLO: saldo final negativo %', v_Sfinal; END IF;
  RAISE NOTICE 'T10 PASS: secuencial -> 1 OK + 1 saldo_insuficiente, 1 movimiento, saldo final % (>=0)', v_Sfinal;

  RAISE NOTICE 'PARTE 2+3 OK: 10/10 pruebas funcionales verdes';
END $func$;

-- ---- Veredicto visible (ultima result set antes del ROLLBACK) -------------
SELECT 'SB1 VERIFY OK: estructura + 10 pruebas funcionales (cero residuo)' AS resultado;

ROLLBACK;
