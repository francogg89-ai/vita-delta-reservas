-- ============================================================================
-- C_SLICE0_A2_SEED_portal_usuarios.sql
-- Carril C / Portal Operativo Interno — Slice 0, Fase A (paso 2 de 2).
-- Siembra los 5 usuarios del portal en portal_usuarios (TEST).
-- Decisiones: D-C-22 (nombre = persona), D-C-32 (seed por email).
--
-- PRERREQUISITO: los 5 usuarios YA creados en Supabase Auth TEST con estos
-- emails y "Auto Confirm" ON (ver runsheet §1). Este bloque NO crea usuarios de
-- Auth; solo mapea user_id -> rol resolviendo POR EMAIL contra auth.users.
--
-- El SQL contiene emails operativos de TEST (no secretos); NO contiene UUIDs ni
-- passwords. El user_id se resuelve en runtime.
--
-- CÓMO CORRER: SQL Editor TEST, NADA seleccionado, todo de una. Precondición
-- auto-validante (L-9E-02): si falta algún email en auth.users, RAISE lista
-- cuáles y aborta sin insertar nada. Re-ejecutable: si ya hay filas, no re-siembra.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. GATE DE ENTORNO (mismo criterio que A1).
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE A2: ambiente=% (esperado test). Abortado.', COALESCE(v_amb, '<ausente>');
  END IF;
END
$gate$;

-- ----------------------------------------------------------------------------
-- 2. PRECONDICIÓN AUTO-VALIDANTE: los 5 emails existen en auth.users.
--    Si falta alguno (usuario no creado o typo), RAISE con la lista y aborta.
-- ----------------------------------------------------------------------------
DO $pre$
DECLARE v_faltan text;
BEGIN
  SELECT string_agg(m.email, ', ' ORDER BY m.email) INTO v_faltan
  FROM (VALUES
    ('franco@vitadelta.test'),
    ('rodrigo@vitadelta.test'),
    ('remo@vitadelta.test'),
    ('vicky@vitadelta.test'),
    ('jenny@vitadelta.test')
  ) AS m(email)
  WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.email = m.email);

  IF v_faltan IS NOT NULL THEN
    RAISE EXCEPTION 'GATE A2: faltan en Auth TEST estos emails: %. Creálos primero (runsheet §1) y re-corré.', v_faltan;
  END IF;
END
$pre$;

-- ----------------------------------------------------------------------------
-- 3. SEED: mapeo email -> nombre -> rol, resolviendo user_id contra auth.users.
--    Guard anti re-seed: si la tabla ya tiene filas, no inserta (idempotente).
-- ----------------------------------------------------------------------------
INSERT INTO public.portal_usuarios (user_id, nombre, rol)
SELECT u.id, m.nombre, m.rol
FROM (VALUES
  ('franco@vitadelta.test',  'franco',  'socio'),
  ('rodrigo@vitadelta.test', 'rodrigo', 'socio'),
  ('remo@vitadelta.test',    'remo',    'socio'),
  ('vicky@vitadelta.test',   'vicky',   'vicky'),
  ('jenny@vitadelta.test',   'jenny',   'jenny')
) AS m(email, nombre, rol)
JOIN auth.users u ON u.email = m.email
WHERE NOT EXISTS (SELECT 1 FROM public.portal_usuarios);

-- ----------------------------------------------------------------------------
-- 4. VERIFICACIÓN DE DATOS (filas de veredicto). Último SELECT => UNION ALL.
-- ----------------------------------------------------------------------------
SELECT * FROM (
  SELECT 1 AS ord, 'total_filas' AS chequeo,
    CASE WHEN (SELECT count(*) FROM public.portal_usuarios)=5 THEN 'PASS' ELSE 'FALLO' END AS veredicto,
    (SELECT count(*)::text FROM public.portal_usuarios) AS detalle
  UNION ALL
  SELECT 2, 'socios_3',
    CASE WHEN (SELECT count(*) FROM public.portal_usuarios WHERE rol='socio')=3 THEN 'PASS' ELSE 'FALLO' END,
    'franco/rodrigo/remo'
  UNION ALL
  SELECT 3, 'vicky_1',
    CASE WHEN (SELECT count(*) FROM public.portal_usuarios WHERE rol='vicky')=1 THEN 'PASS' ELSE 'FALLO' END,
    'rol vicky'
  UNION ALL
  SELECT 4, 'jenny_1',
    CASE WHEN (SELECT count(*) FROM public.portal_usuarios WHERE rol='jenny')=1 THEN 'PASS' ELSE 'FALLO' END,
    'rol jenny'
  UNION ALL
  SELECT 5, 'todos_activos',
    CASE WHEN (SELECT count(*) FROM public.portal_usuarios WHERE activo)=5 THEN 'PASS' ELSE 'FALLO' END,
    'activo = true'
  UNION ALL
  SELECT 6, 'user_id_unicos',
    CASE WHEN (SELECT count(DISTINCT user_id) FROM public.portal_usuarios)=5 THEN 'PASS' ELSE 'FALLO' END,
    'sin colisión de user_id'
) v ORDER BY ord;

COMMIT;

-- Vista nominal (opcional; correr aislado para verla, el Editor muestra 1 SELECT):
--   SELECT nombre, rol, activo, user_id FROM public.portal_usuarios ORDER BY rol, nombre;
