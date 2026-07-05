-- ============================================================================
-- CC_RETIRO_SB0_A2_VERIFY_OPS.sql  --  Bloque A / A2: VERIFY estructural post-COMMIT del SB0 en OPS.
--
-- READ-ONLY: solo SELECT + gate. Sin DDL, sin escrituras (ni intentos rechazados), sin nextval.
-- Estructural: columna, ambas FKs (destino + accion), UNIQUE, CHECK, ACL Data API, y backfill 1:1.
-- La conducta del CHECK (bloquea id_socio en fila no-socio) ya quedo probada en TEST (NEG1); aca
-- se verifica su EXISTENCIA/definicion, no se reintenta un write en OPS.
-- ULTIMO result set = checklist; los 10 chequeos deben dar PASS. Correr completo (L-8A-01).
-- ============================================================================

-- ---- Gate anti-entorno: OPS-only (aborta si ambiente != 'ops') --------------
DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE ambiente=% (esperado ops) -- abortado', COALESCE(v_amb, '(null)');
  END IF;
END $gate$;

-- ---- Checklist estructural (ULTIMO result set) -----------------------------
WITH checks(orden, chequeo, esperado, obtenido) AS (
  VALUES
    (1, 'columna id_socio existe y es bigint',
        'bigint',
        COALESCE((SELECT atttypid::regtype::text FROM pg_attribute
                   WHERE attrelid = 'public.portal_usuarios'::regclass
                     AND attname = 'id_socio' AND NOT attisdropped), '(ausente)')),
    (2, 'columna id_socio es nullable (NOT attnotnull)',
        'true',
        COALESCE((SELECT (NOT attnotnull)::text FROM pg_attribute
                   WHERE attrelid = 'public.portal_usuarios'::regclass
                     AND attname = 'id_socio' AND NOT attisdropped), '(ausente)')),
    (3, 'FK fk_portal_usuarios_id_socio -> socios(id_socio) ON DELETE RESTRICT',
        '1',
        (SELECT count(*)::text FROM pg_constraint
          WHERE conrelid = 'public.portal_usuarios'::regclass
            AND conname = 'fk_portal_usuarios_id_socio'
            AND contype = 'f'
            AND confrelid = 'public.socios'::regclass
            AND confdeltype = 'r'
            AND cardinality(conkey) = 1)),
    (4, 'FKs totales en portal_usuarios (user_id + id_socio)',
        '2',
        (SELECT count(*)::text FROM pg_constraint
          WHERE conrelid = 'public.portal_usuarios'::regclass AND contype = 'f')),
    (5, 'UNIQUE uq_portal_usuarios_id_socio presente',
        '1',
        (SELECT count(*)::text FROM pg_constraint
          WHERE conrelid = 'public.portal_usuarios'::regclass
            AND conname = 'uq_portal_usuarios_id_socio' AND contype = 'u')),
    (6, 'CHECK chk_portal_usuarios_socio_rol presente',
        '1',
        (SELECT count(*)::text FROM pg_constraint
          WHERE conrelid = 'public.portal_usuarios'::regclass
            AND conname = 'chk_portal_usuarios_socio_rol' AND contype = 'c')),
    (7, 'backfill: rol=socio SIN id_socio',
        '0',
        (SELECT count(*)::text FROM public.portal_usuarios
          WHERE rol = 'socio' AND id_socio IS NULL)),
    (8, 'backfill: no-socios CON id_socio',
        '0',
        (SELECT count(*)::text FROM public.portal_usuarios
          WHERE rol <> 'socio' AND id_socio IS NOT NULL)),
    (9, 'backfill: id_socio duplicados (colision UNIQUE)',
        '0',
        (SELECT count(*)::text FROM (
           SELECT id_socio FROM public.portal_usuarios
            WHERE id_socio IS NOT NULL
            GROUP BY id_socio HAVING count(*) > 1) d)),
    (10, 'ACL Data API: service_role tiene SELECT',
        'true',
        has_table_privilege('service_role', 'public.portal_usuarios', 'SELECT')::text)
)
SELECT orden,
       chequeo,
       esperado,
       obtenido,
       CASE WHEN esperado = obtenido THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM checks
ORDER BY orden;
