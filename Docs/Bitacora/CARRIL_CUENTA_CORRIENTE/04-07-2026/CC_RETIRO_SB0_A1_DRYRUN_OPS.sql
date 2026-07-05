-- ============================================================================
-- CC_RETIRO_SB0_A1_DRYRUN_OPS.sql  --  Bloque A / A1: DRY-RUN del SB0 en OPS (BEGIN...ROLLBACK).
--
-- Espeja EXACTAMENTE CC_RETIRO_SB0_A_FK_ID_SOCIO_TEST.sql (mismos preflights, backfill,
-- postchecks, nombres de constraint y normalizacion lower(btrim(nombre))), con TRES diferencias:
--   1. Gate anti-entorno invertido a OPS-only (aborta si ambiente != 'ops').
--   2. COMMIT -> ROLLBACK: la columna + constraints + backfill se crean y se REVIERTEN.
--   3. Se agrega prueba de NO-PERSISTENCIA post-rollback como ULTIMO result set.
--
-- NO consume secuencia: no toca movimientos_socio/portal_idempotencia_cc; ADD COLUMN (bigint
-- plano, sin serial/default), UPDATE y ADD CONSTRAINT no usan nextval. NO hace COMMIT.
--
-- COMO LEER EL RESULTADO:
--   - Panel de MENSAJES/NOTICES: las pruebas de backfill (equivalentes a TEST) via RAISE NOTICE;
--     si algun assert falla -> RAISE EXCEPTION, el script corta y la tx queda abortada (nada persiste).
--   - ULTIMO RESULT SET (tabla): 4 chequeos de NO-PERSISTENCIA; los 4 deben dar PASS.
--   Correr el script COMPLETO (sin seleccion) en el SQL Editor (L-8A-01).
-- ============================================================================

BEGIN;

-- ---- Gate anti-entorno: OPS-only (aborta si ambiente != 'ops') --------------
DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE ambiente=% (esperado ops) -- abortado, sin cambios', COALESCE(v_amb, '(null)');
  END IF;
END $gate$;

-- ---- Preflight 1: fail-fast si SB0 ya fue aplicado (total o parcial) --------
DO $drift$
DECLARE
  v_pu   oid := to_regclass('public.portal_usuarios');
  v_col  boolean;
  v_cons text;
BEGIN
  IF v_pu IS NULL THEN
    RAISE EXCEPTION 'portal_usuarios ausente -- entorno no valido para SB0';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_attribute
     WHERE attrelid = v_pu AND attname = 'id_socio' AND NOT attisdropped
  ) INTO v_col;

  SELECT string_agg(conname, ', ' ORDER BY conname) INTO v_cons
    FROM pg_constraint
   WHERE conrelid = v_pu
     AND conname IN ('fk_portal_usuarios_id_socio',
                     'uq_portal_usuarios_id_socio',
                     'chk_portal_usuarios_socio_rol');

  IF v_col OR v_cons IS NOT NULL THEN
    RAISE EXCEPTION 'DRIFT: SB0 ya aplicado o parcial (columna id_socio=%, constraints=[%]) -- abortado, sin cambios',
      v_col, COALESCE(v_cons, 'ninguna');
  END IF;
END $drift$;

-- ---- Preflight 2: socios sin nombres normalizados ambiguos ------------------
DO $pre$
DECLARE v_list text;
BEGIN
  SELECT string_agg(n || ' (x' || c || ')', ', ' ORDER BY n) INTO v_list
    FROM (
      SELECT lower(btrim(nombre)) AS n, count(*) AS c
        FROM socios
       GROUP BY lower(btrim(nombre))
      HAVING count(*) > 1
    ) d;
  IF v_list IS NOT NULL THEN
    RAISE EXCEPTION 'Ambiguedad en socios: nombres normalizados duplicados -> %', v_list;
  END IF;
END $pre$;

-- ---- 1) Columna nullable + FK RESTRICT -------------------------------------
ALTER TABLE public.portal_usuarios
  ADD COLUMN id_socio bigint;

ALTER TABLE public.portal_usuarios
  ADD CONSTRAINT fk_portal_usuarios_id_socio
  FOREIGN KEY (id_socio) REFERENCES public.socios(id_socio) ON DELETE RESTRICT;

-- ---- 2) Backfill server-side (solo rol=socio, match case-insensitive) -------
UPDATE public.portal_usuarios pu
   SET id_socio = s.id_socio
  FROM public.socios s
 WHERE pu.rol = 'socio'
   AND lower(btrim(pu.nombre)) = lower(btrim(s.nombre));

-- ---- 3) Asserts fail-closed (equivalentes a TEST; RAISE aborta la tx) -------
DO $post$
DECLARE
  v_sinmatch text;
  v_colis    int;
  v_nonsoc   int;
BEGIN
  -- (a) todo rol=socio debe mapear
  SELECT string_agg(nombre, ', ' ORDER BY nombre) INTO v_sinmatch
    FROM public.portal_usuarios
   WHERE rol = 'socio' AND id_socio IS NULL;
  IF v_sinmatch IS NOT NULL THEN
    RAISE EXCEPTION 'Backfill incompleto: portal_usuarios rol=socio sin match en socios -> %', v_sinmatch;
  END IF;

  -- (b) ningun id_socio asignado a 2+ filas (violaria UNIQUE)
  SELECT count(*) INTO v_colis
    FROM (
      SELECT id_socio FROM public.portal_usuarios
       WHERE id_socio IS NOT NULL
       GROUP BY id_socio HAVING count(*) > 1
    ) d;
  IF v_colis > 0 THEN
    RAISE EXCEPTION 'Colision: % id_socio asignados a mas de una fila portal_usuarios', v_colis;
  END IF;

  -- (c) ningun no-socio con id_socio
  SELECT count(*) INTO v_nonsoc
    FROM public.portal_usuarios
   WHERE rol <> 'socio' AND id_socio IS NOT NULL;
  IF v_nonsoc > 0 THEN
    RAISE EXCEPTION 'Invariante roto: % filas no-socio con id_socio', v_nonsoc;
  END IF;

  RAISE NOTICE 'Backfill OK: mapeo 1:1 rol=socio, sin colisiones, sin id_socio en no-socios';
END $post$;

-- ---- 4) Constraints permanentes --------------------------------------------
ALTER TABLE public.portal_usuarios
  ADD CONSTRAINT uq_portal_usuarios_id_socio UNIQUE (id_socio);

ALTER TABLE public.portal_usuarios
  ADD CONSTRAINT chk_portal_usuarios_socio_rol
  CHECK ((rol = 'socio') = (id_socio IS NOT NULL));

-- ---- 5) Prueba DENTRO de la transaccion (RAISE NOTICE; se revierte con ROLLBACK) --
-- Confirma que la columna + las 3 constraints EXISTEN y cuantos socios quedaron mapeados,
-- justo antes de revertir. El resultado va al panel de mensajes (no persiste).
DO $proof$
DECLARE
  v_pu   oid := to_regclass('public.portal_usuarios');
  v_col  boolean;
  v_cons int;
  v_map  int;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_attribute
     WHERE attrelid = v_pu AND attname = 'id_socio' AND NOT attisdropped
  ) INTO v_col;
  SELECT count(*) INTO v_cons
    FROM pg_constraint
   WHERE conrelid = v_pu
     AND conname IN ('fk_portal_usuarios_id_socio',
                     'uq_portal_usuarios_id_socio',
                     'chk_portal_usuarios_socio_rol');
  SELECT count(id_socio) INTO v_map
    FROM public.portal_usuarios WHERE rol = 'socio';

  IF NOT v_col OR v_cons <> 3 THEN
    RAISE EXCEPTION 'DRY-RUN proof fallo: columna=% constraints=%/3', v_col, v_cons;
  END IF;
  RAISE NOTICE 'DRY-RUN OK (dentro de la tx): columna id_socio creada, %/3 constraints creadas, % socios mapeados. Ahora se revierte (ROLLBACK).',
    v_cons, v_map;
END $proof$;

-- ---- ROLLBACK: nada de lo anterior persiste --------------------------------
ROLLBACK;

-- ---- 6) Prueba de NO-PERSISTENCIA post-rollback (ULTIMO result set) ---------
-- Fuera de la transaccion revertida: la columna y las 3 constraints deben estar AUSENTES.
WITH checks(orden, chequeo, esperado, obtenido) AS (
  VALUES
    (1, 'columna id_socio NO persiste tras rollback',
        '0',
        (SELECT count(*)::text FROM pg_attribute
          WHERE attrelid = 'public.portal_usuarios'::regclass
            AND attname = 'id_socio' AND NOT attisdropped)),
    (2, 'FK fk_portal_usuarios_id_socio NO persiste',
        '0',
        (SELECT count(*)::text FROM pg_constraint
          WHERE conrelid = 'public.portal_usuarios'::regclass
            AND conname = 'fk_portal_usuarios_id_socio')),
    (3, 'UNIQUE uq_portal_usuarios_id_socio NO persiste',
        '0',
        (SELECT count(*)::text FROM pg_constraint
          WHERE conrelid = 'public.portal_usuarios'::regclass
            AND conname = 'uq_portal_usuarios_id_socio')),
    (4, 'CHECK chk_portal_usuarios_socio_rol NO persiste',
        '0',
        (SELECT count(*)::text FROM pg_constraint
          WHERE conrelid = 'public.portal_usuarios'::regclass
            AND conname = 'chk_portal_usuarios_socio_rol'))
)
SELECT orden,
       chequeo,
       esperado,
       obtenido,
       CASE WHEN esperado = obtenido THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM checks
ORDER BY orden;
