-- ============================================================================
-- CC_RETIRO_SB0_A_FK_ID_SOCIO_TEST.sql
-- Frente: Cuenta Corriente ESCRITURA (retiros desde saldo vivo)
-- Sub-bloque 0 del retiro: FK portal_usuarios.id_socio -> socios(id_socio) + backfill
-- Entorno: TEST unicamente (gate anti-OPS por configuracion_general('ambiente')='test').
-- Naturaleza: migracion ATOMICA y FAIL-CLOSED. Si cualquier assert falla, ROLLBACK total.
-- No usa IF NOT EXISTS en ningun lado: el drift se ABORTA, no se esconde.
-- Correr el script COMPLETO (sin seleccion) en el SQL Editor de Supabase (L-8A-01).
-- ----------------------------------------------------------------------------
-- NOTA D5: el auto-test D5 de la PARTE D canonica asume UNA sola FK en
-- portal_usuarios (la resuelve sin conname). Tras SB0 hay DOS FKs (user_id e
-- id_socio); por eso D5 queda PENDIENTE de extension en el cierre v1.11.0 y NO
-- debe usarse sin adaptar como verificacion post-SB0. La verificacion valida de
-- este sub-bloque es CC_RETIRO_SB0_B_VERIFY_TEST.sql.
-- ============================================================================

BEGIN;

-- ---- Gate anti-OPS (solo TEST) --------------------------------------------
DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE ambiente=% (esperado test) -- abortado, sin cambios', COALESCE(v_amb, '(null)');
  END IF;
END $gate$;

-- ---- Preflight 1: fail-fast si SB0 ya fue aplicado (total o parcial) -------
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

-- ---- Preflight 2: socios sin nombres normalizados ambiguos ----------------
-- (evita que el backfill elija arbitrariamente; lista los conflictos, no solo el conteo)
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

-- ---- 1) Columna nullable + FK RESTRICT ------------------------------------
-- (nullable: los NULL de las filas no-socio pasan la FK; RESTRICT: consistente con
--  todas las FKs a socios y compatible con el bicondicional -- SET NULL lo romperia)
ALTER TABLE public.portal_usuarios
  ADD COLUMN id_socio bigint;

ALTER TABLE public.portal_usuarios
  ADD CONSTRAINT fk_portal_usuarios_id_socio
  FOREIGN KEY (id_socio) REFERENCES public.socios(id_socio) ON DELETE RESTRICT;

-- ---- 2) Backfill server-side (solo rol=socio, match case-insensitive) ------
UPDATE public.portal_usuarios pu
   SET id_socio = s.id_socio
  FROM public.socios s
 WHERE pu.rol = 'socio'
   AND lower(btrim(pu.nombre)) = lower(btrim(s.nombre));

-- ---- 3) Asserts fail-closed (condicion real bidireccional, no "3 socios") --
DO $post$
DECLARE
  v_sinmatch text;
  v_colis    int;
  v_nonsoc   int;
BEGIN
  -- (a) todo rol=socio debe mapear: si no, listar los nombres que no matchearon
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

  -- (c) ningun no-socio con id_socio (la otra mitad del bicondicional)
  SELECT count(*) INTO v_nonsoc
    FROM public.portal_usuarios
   WHERE rol <> 'socio' AND id_socio IS NOT NULL;
  IF v_nonsoc > 0 THEN
    RAISE EXCEPTION 'Invariante roto: % filas no-socio con id_socio', v_nonsoc;
  END IF;

  RAISE NOTICE 'Backfill OK: mapeo 1:1 rol=socio, sin colisiones, sin id_socio en no-socios';
END $post$;

-- ---- 4) Constraints permanentes -------------------------------------------
ALTER TABLE public.portal_usuarios
  ADD CONSTRAINT uq_portal_usuarios_id_socio UNIQUE (id_socio);

ALTER TABLE public.portal_usuarios
  ADD CONSTRAINT chk_portal_usuarios_socio_rol
  CHECK ((rol = 'socio') = (id_socio IS NOT NULL));

-- ---- Confirmacion visible (ultima result set antes del COMMIT) ------------
SELECT rol,
       count(*)        AS filas,
       count(id_socio) AS con_id_socio
  FROM public.portal_usuarios
 GROUP BY rol
 ORDER BY rol;

COMMIT;
