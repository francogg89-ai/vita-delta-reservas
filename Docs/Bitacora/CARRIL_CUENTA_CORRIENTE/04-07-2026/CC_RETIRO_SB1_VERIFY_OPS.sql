-- ============================================================================
-- CC_RETIRO_SB1_VERIFY_OPS.sql  --  Bloque B / SB1: VERIFY estructural + negativos en OPS.
--
-- CONDICIONES (no negociables): solo estructura + negativos que CORTAN antes de cualquier
-- INSERT. NO happy-path, NO retiro real, NO nextval. Sin BEGIN...ROLLBACK: usa auto-commit +
-- temp tables ON COMMIT PRESERVE ROWS (una sola sesion en el SQL Editor). Los negativos se
-- ejecutan llamando portal_registrar_retiro (devuelve envelope de error, no escribe).
--
-- PRUEBA DE 0-ESCRITURA / 0-SECUENCIA: se toma un snapshot ANTES y DESPUES de
--   count(movimientos_socio), count(portal_idempotencia_cc) y el last_value de AMBAS secuencias
--   (pg_sequence_last_value). El checklist final exige count_antes == count_despues y
--   seq_antes IS NOT DISTINCT FROM seq_despues -> 0 filas nuevas y 0 nextval. Como el INSERT en
--   movimientos_socio/portal_idempotencia_cc es lo unico que avanza esas secuencias, si algun
--   negativo hubiera escrito, la guarda lo detecta (FAIL). Los negativos N1..N7 cortan ANTES del
--   INSERT (validacion / identidad / saldo_insuficiente VD001 antes del INSERT), por construccion.
--
-- ULTIMO result set = checklist (estructura + negativos + 0-delta). Correr completo (L-8A-01).
-- ============================================================================

-- ---- Gate anti-entorno: OPS-only ------------------------------------------
DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE ambiente=% (esperado ops) -- abortado', COALESCE(v_amb, '(null)');
  END IF;
END $gate$;

-- ---- Temp tables (solo pg_temp de la sesion; DROP calificado; PRESERVE ROWS) --
DROP TABLE IF EXISTS pg_temp._b_snap;
DROP TABLE IF EXISTS pg_temp._b_neg;
CREATE TEMP TABLE _b_snap (
  fase text, mov bigint, idem bigint, seq_mov bigint, seq_idem bigint
) ON COMMIT PRESERVE ROWS;
CREATE TEMP TABLE _b_neg (
  orden int, caso text, esperado text, code text
) ON COMMIT PRESERVE ROWS;

-- ---- Snapshot ANTES --------------------------------------------------------
INSERT INTO _b_snap
SELECT 'antes',
       (SELECT count(*) FROM public.movimientos_socio),
       (SELECT count(*) FROM public.portal_idempotencia_cc),
       pg_sequence_last_value(pg_get_serial_sequence('public.movimientos_socio','id_movimiento')::regclass),
       pg_sequence_last_value('public.portal_idempotencia_cc_id_registro_seq'::regclass);

-- ---- Negativos: llamar portal_registrar_retiro y guardar el error.code -----
-- Identidad de franco (id_socio) via subquery. Ningun negativo llega al INSERT.
-- N1: payload vacio -> control ausente -> error_interno (corta en el 1er check).
INSERT INTO _b_neg
SELECT 1, 'N1 payload vacio (control ausente)', 'error_interno',
       (public.portal_registrar_retiro('{}'::jsonb) -> 'error' ->> 'code');

-- N2: rol != socio -> rol_no_permitido (corta antes de identidad).
INSERT INTO _b_neg
SELECT 2, 'N2 rol=vicky -> rol_no_permitido', 'rol_no_permitido',
       (public.portal_registrar_retiro(jsonb_build_object(
          'actor','franco','rol','vicky','nonce','b-verify-n2',
          'idempotency_key','b-verify-n2',
          'id_socio',(SELECT id_socio FROM public.portal_usuarios WHERE lower(btrim(nombre)) = 'franco'),
          'monto','1.00','medio_pago','efectivo'
       )) -> 'error' ->> 'code');

-- N3: sin idempotency_key -> payload_invalido (corta antes de identidad).
INSERT INTO _b_neg
SELECT 3, 'N3 sin idempotency_key -> payload_invalido', 'payload_invalido',
       (public.portal_registrar_retiro(jsonb_build_object(
          'actor','franco','rol','socio','nonce','b-verify-n3',
          'id_socio',(SELECT id_socio FROM public.portal_usuarios WHERE lower(btrim(nombre)) = 'franco'),
          'monto','1.00','medio_pago','efectivo'
       )) -> 'error' ->> 'code');

-- N4: identidad valida + monto invalido -> payload_invalido (corta antes del savepoint).
INSERT INTO _b_neg
SELECT 4, 'N4 monto invalido -> payload_invalido', 'payload_invalido',
       (public.portal_registrar_retiro(jsonb_build_object(
          'actor','franco','rol','socio','nonce','b-verify-n4',
          'idempotency_key','b-verify-n4',
          'id_socio',(SELECT id_socio FROM public.portal_usuarios WHERE lower(btrim(nombre)) = 'franco'),
          'monto','no-es-monto','medio_pago','efectivo'
       )) -> 'error' ->> 'code');

-- N5: identidad valida + medio invalido -> payload_invalido (corta antes del savepoint).
INSERT INTO _b_neg
SELECT 5, 'N5 medio_pago invalido -> payload_invalido', 'payload_invalido',
       (public.portal_registrar_retiro(jsonb_build_object(
          'actor','franco','rol','socio','nonce','b-verify-n5',
          'idempotency_key','b-verify-n5',
          'id_socio',(SELECT id_socio FROM public.portal_usuarios WHERE lower(btrim(nombre)) = 'franco'),
          'monto','1.00','medio_pago','tarjeta'
       )) -> 'error' ->> 'code');

-- N6: id_socio de franco con actor=rodrigo -> identidad inconsistente -> error_interno
--     (corta en el binding de identidad, antes de validar monto/saldo).
INSERT INTO _b_neg
SELECT 6, 'N6 id_socio ajeno al actor -> error_interno', 'error_interno',
       (public.portal_registrar_retiro(jsonb_build_object(
          'actor','rodrigo','rol','socio','nonce','b-verify-n6',
          'idempotency_key','b-verify-n6',
          'id_socio',(SELECT id_socio FROM public.portal_usuarios WHERE lower(btrim(nombre)) = 'franco'),
          'monto','1.00','medio_pago','efectivo'
       )) -> 'error' ->> 'code');

-- N7: identidad valida + monto ENORME -> saldo_insuficiente (VD001 ANTES del INSERT).
INSERT INTO _b_neg
SELECT 7, 'N7 monto > saldo -> saldo_insuficiente (VD001 pre-INSERT)', 'saldo_insuficiente',
       (public.portal_registrar_retiro(jsonb_build_object(
          'actor','franco','rol','socio','nonce','b-verify-n7',
          'idempotency_key','b-verify-n7',
          'id_socio',(SELECT id_socio FROM public.portal_usuarios WHERE lower(btrim(nombre)) = 'franco'),
          'monto','999999999999','medio_pago','efectivo'
       )) -> 'error' ->> 'code');

-- ---- Snapshot DESPUES ------------------------------------------------------
INSERT INTO _b_snap
SELECT 'despues',
       (SELECT count(*) FROM public.movimientos_socio),
       (SELECT count(*) FROM public.portal_idempotencia_cc),
       pg_sequence_last_value(pg_get_serial_sequence('public.movimientos_socio','id_movimiento')::regclass),
       pg_sequence_last_value('public.portal_idempotencia_cc_id_registro_seq'::regclass);

-- ===========================================================================
-- CHECKLIST FINAL (ULTIMO result set): estructura + negativos + 0-delta
-- ===========================================================================
WITH
pu AS (SELECT 'public.portal_idempotencia_cc'::regclass AS cc),
estruct(orden, seccion, chequeo, esperado, obtenido) AS (
  VALUES
    (1, 'estructura', 'tabla portal_idempotencia_cc existe',
        '1', (SELECT count(*)::text FROM pg_class WHERE oid = 'public.portal_idempotencia_cc'::regclass)),
    (2, 'estructura', 'FK fk_portal_idem_cc_mov -> movimientos_socio ON DELETE RESTRICT',
        '1', (SELECT count(*)::text FROM pg_constraint
                WHERE conrelid='public.portal_idempotencia_cc'::regclass
                  AND conname='fk_portal_idem_cc_mov' AND contype='f'
                  AND confrelid='public.movimientos_socio'::regclass AND confdeltype='r')),
    (3, 'estructura', 'UNIQUE uq_portal_idem_cc_nonce',
        '1', (SELECT count(*)::text FROM pg_constraint
                WHERE conrelid='public.portal_idempotencia_cc'::regclass
                  AND conname='uq_portal_idem_cc_nonce' AND contype='u')),
    (4, 'estructura', 'UNIQUE uq_portal_idem_cc_action_key',
        '1', (SELECT count(*)::text FROM pg_constraint
                WHERE conrelid='public.portal_idempotencia_cc'::regclass
                  AND conname='uq_portal_idem_cc_action_key' AND contype='u')),
    (5, 'estructura', 'CHECK chk_portal_idem_cc_rol (rol=socio)',
        '1', (SELECT count(*)::text FROM pg_constraint
                WHERE conrelid='public.portal_idempotencia_cc'::regclass
                  AND conname='chk_portal_idem_cc_rol' AND contype='c')),
    (6, 'estructura', 'ACL tabla: anon SIN SELECT (REVOKE-all)',
        'false', has_table_privilege('anon','public.portal_idempotencia_cc','SELECT')::text),
    (7, 'estructura', 'ACL tabla: service_role SIN SELECT (REVOKE-all)',
        'false', has_table_privilege('service_role','public.portal_idempotencia_cc','SELECT')::text),
    (8, 'estructura', 'ACL tabla: authenticated SIN INSERT (REVOKE-all)',
        'false', has_table_privilege('authenticated','public.portal_idempotencia_cc','INSERT')::text),
    (9, 'estructura', 'funcion registrar_retiro_desde_saldo_vivo(bigint,numeric,text,text,text)',
        '1', (SELECT count(*)::text FROM pg_proc
                WHERE oid = 'public.registrar_retiro_desde_saldo_vivo(bigint,numeric,text,text,text)'::regprocedure)),
    (10,'estructura', 'funcion portal_registrar_retiro(jsonb)',
        '1', (SELECT count(*)::text FROM pg_proc
                WHERE oid = 'public.portal_registrar_retiro(jsonb)'::regprocedure)),
    (11,'estructura', 'ambas funciones con SET search_path',
        '2', (SELECT count(*)::text FROM pg_proc
                WHERE oid IN ('public.registrar_retiro_desde_saldo_vivo(bigint,numeric,text,text,text)'::regprocedure,
                              'public.portal_registrar_retiro(jsonb)'::regprocedure)
                  AND proconfig IS NOT NULL
                  AND array_to_string(proconfig,',') LIKE '%search_path%')),
    (12,'estructura', 'EXECUTE de portal_registrar_retiro revocado a PUBLIC',
        'false', has_function_privilege('public','public.portal_registrar_retiro(jsonb)','EXECUTE')::text)
),
negs(orden, seccion, chequeo, esperado, obtenido) AS (
  SELECT orden + 100, 'negativo', caso, esperado, COALESCE(code,'(sin code)')
    FROM _b_neg
),
delta(orden, seccion, chequeo, esperado, obtenido) AS (
  SELECT 201, 'guarda 0-write', 'movimientos_socio: 0 filas nuevas', 'igual',
         CASE WHEN (SELECT mov FROM _b_snap WHERE fase='antes') = (SELECT mov FROM _b_snap WHERE fase='despues')
              THEN 'igual' ELSE 'DISTINTO' END
  UNION ALL
  SELECT 202, 'guarda 0-write', 'portal_idempotencia_cc: 0 filas nuevas', 'igual',
         CASE WHEN (SELECT idem FROM _b_snap WHERE fase='antes') = (SELECT idem FROM _b_snap WHERE fase='despues')
              THEN 'igual' ELSE 'DISTINTO' END
  UNION ALL
  SELECT 203, 'guarda 0-nextval', 'secuencia movimientos_socio: sin avance', 'igual',
         CASE WHEN (SELECT seq_mov FROM _b_snap WHERE fase='antes') IS NOT DISTINCT FROM (SELECT seq_mov FROM _b_snap WHERE fase='despues')
              THEN 'igual' ELSE 'DISTINTO' END
  UNION ALL
  SELECT 204, 'guarda 0-nextval', 'secuencia portal_idempotencia_cc: sin avance', 'igual',
         CASE WHEN (SELECT seq_idem FROM _b_snap WHERE fase='antes') IS NOT DISTINCT FROM (SELECT seq_idem FROM _b_snap WHERE fase='despues')
              THEN 'igual' ELSE 'DISTINTO' END
),
todo AS (
  SELECT * FROM estruct
  UNION ALL SELECT * FROM negs
  UNION ALL SELECT * FROM delta
)
SELECT orden, seccion, chequeo, esperado, obtenido,
       CASE WHEN esperado = obtenido THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM todo
ORDER BY orden;
