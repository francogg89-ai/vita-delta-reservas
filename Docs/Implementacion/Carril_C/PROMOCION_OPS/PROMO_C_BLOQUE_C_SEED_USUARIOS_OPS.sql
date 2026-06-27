-- ============================================================================
-- PROMO_C_BLOQUE_C_SEED_USUARIOS_OPS.sql
-- Carril C / Portal Operativo Interno — PROMOCIÓN COORDINADA A OPS — BLOQUE C (paso 2 de 2).
-- Siembra los 5 usuarios reales en portal_usuarios (OPS), mapeando email -> rol.
-- Decisiones: D-C-22 (nombre = persona), D-C-32 (seed por email, sin UUIDs).
--
-- ┌────────────────────────────────────────────────────────────────────────┐
-- │ PRERREQUISITO (Bloque C, paso 1 — RUNSHEET MANUAL):                      │
-- │ Los 5 usuarios YA creados en Supabase Auth de OPS con estos emails y     │
-- │ "Auto Confirm User" ON. Este script NO crea usuarios de Auth ni toca     │
-- │ contraseñas: solo resuelve user_id POR EMAIL contra auth.users.          │
-- └────────────────────────────────────────────────────────────────────────┘
--
-- ┌────────────────────────────────────────────────────────────────────────┐
-- │ ANTES DE CORRER — REEMPLAZÁ LOS 5 EMAILS EN UN (1) SOLO LUGAR:           │
-- │ el INSERT a la tabla temporal _seed_usuarios (sección 2, marcado         │
-- │ <<< REEMPLAZAR EMAIL >>>). Todos los guards y el seed leen de ahí.       │
-- │ Usá EXACTAMENTE los mismos emails que cargaste en Auth OPS (paso 1).     │
-- │ NO commitees este archivo con los emails reales (son PII): el repo       │
-- │ conserva la versión con __PEGAR_*; los emails reales viven solo en tu    │
-- │ copia de ejecución (mismo criterio que el secreto HMAC).                 │
-- └────────────────────────────────────────────────────────────────────────┘
--
-- MAPEO FIJO (no se reemplaza — identificadores del sistema, D-C-22):
--   email_franco  -> nombre 'franco'  -> rol 'socio'
--   email_rodrigo -> nombre 'rodrigo' -> rol 'socio'
--   email_remo    -> nombre 'remo'    -> rol 'socio'
--   email_vicky   -> nombre 'vicky'   -> rol 'vicky'
--   email_jenny   -> nombre 'jenny'   -> rol 'jenny'
--
-- GUARDS (abortan SIN insertar nada — todo en UNA transacción):
--   · ambiente='ops' (discriminador fuerte).
--   · placeholders sin reemplazar (prefijo __PEGAR) -> aborta.
--   · email duplicado en la lista -> aborta.
--   · algún email no existe en auth.users (no creado / typo) -> aborta listándolos.
--   · algún email matchea >1 usuario Auth -> aborta.
--   · portal_usuarios ya tiene filas (inesperado tras Bloque B) -> aborta.
--   · post-seed: conteo/roles distintos de 5/3/1/1 -> aborta (rollback).
--
-- La tabla temporal _seed_usuarios es de SESIÓN (ON COMMIT DROP): no toca el
-- schema persistente de OPS, se borra sola al COMMIT. NO toca n8n, gateway ni
-- Vercel. NO expone contraseñas (no las lee).
-- RESULTADO ESPERADO: 5 filas (3 socio + 1 vicky + 1 jenny), todas activas,
--   user_id únicos resueltos por email; veredicto en PASS, TOTAL VERDE.
--
-- CÓMO CORRER: SQL Editor de Supabase del proyecto OPS (lpiatqztudxiwdlcoasv),
--   con NADA seleccionado (L-8A-01), todo el archivo de una.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. GATE DE ENTORNO (ambiente='ops').
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE C: ambiente=% (esperado ops). Abortado: este seed es solo para OPS.',
      COALESCE(v_amb, '<ausente>');
  END IF;
END
$gate$;

-- ----------------------------------------------------------------------------
-- 2. DATOS DEL SEED EN UNA TABLA TEMPORAL (único lugar de reemplazo de emails).
--    ON COMMIT DROP: vive solo en esta transacción; no persiste en OPS.
-- ----------------------------------------------------------------------------
CREATE TEMP TABLE _seed_usuarios (email text, nombre text, rol text) ON COMMIT DROP;

INSERT INTO _seed_usuarios (email, nombre, rol) VALUES
  ('__PEGAR_EMAIL_FRANCO',  'franco',  'socio'),  -- <<< REEMPLAZAR EMAIL >>>
  ('__PEGAR_EMAIL_RODRIGO', 'rodrigo', 'socio'),  -- <<< REEMPLAZAR EMAIL >>>
  ('__PEGAR_EMAIL_REMO',    'remo',    'socio'),  -- <<< REEMPLAZAR EMAIL >>>
  ('__PEGAR_EMAIL_VICKY',   'vicky',   'vicky'),  -- <<< REEMPLAZAR EMAIL >>>
  ('__PEGAR_EMAIL_JENNY',   'jenny',   'jenny');  -- <<< REEMPLAZAR EMAIL >>>

-- ----------------------------------------------------------------------------
-- 3. PRECONDICIONES (todas leen de _seed_usuarios; un solo paso de diagnóstico).
-- ----------------------------------------------------------------------------
DO $pre$
DECLARE
  v_ph      text;
  v_dup     text;
  v_falta   text;
  v_dupauth text;
  v_filas   int;
BEGIN
  -- (a) placeholders sin reemplazar
  SELECT string_agg(email, ', ') INTO v_ph
  FROM _seed_usuarios
  WHERE email LIKE '\_\_PEGAR%' ESCAPE '\';
  IF v_ph IS NOT NULL THEN
    RAISE EXCEPTION 'GATE C: placeholders de email sin reemplazar: %. Pegá los emails reales (paso 1) y re-corré.', v_ph;
  END IF;

  -- (b) duplicados en la lista
  SELECT string_agg(email, ', ') INTO v_dup
  FROM (SELECT email FROM _seed_usuarios GROUP BY email HAVING count(*) > 1) x;
  IF v_dup IS NOT NULL THEN
    RAISE EXCEPTION 'GATE C: email repetido en la lista del seed: %. Cada persona debe tener un email distinto.', v_dup;
  END IF;

  -- (c) los 5 existen en auth.users
  SELECT string_agg(s.email, ', ' ORDER BY s.email) INTO v_falta
  FROM _seed_usuarios s
  WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.email = s.email);
  IF v_falta IS NOT NULL THEN
    RAISE EXCEPTION 'GATE C: faltan en Auth OPS estos emails: %. Creálos primero (runsheet paso 1) y re-corré.', v_falta;
  END IF;

  -- (d) ninguno matchea >1 usuario en auth.users
  SELECT string_agg(email, ', ') INTO v_dupauth
  FROM (
    SELECT s.email
    FROM _seed_usuarios s
    JOIN auth.users u ON u.email = s.email
    GROUP BY s.email HAVING count(*) > 1
  ) x;
  IF v_dupauth IS NOT NULL THEN
    RAISE EXCEPTION 'GATE C: estos emails matchean >1 usuario en Auth OPS: %. Resolvé el duplicado en Auth antes de sembrar.', v_dupauth;
  END IF;

  -- (e) portal_usuarios vacía (estado esperado tras Bloque B)
  SELECT count(*) INTO v_filas FROM public.portal_usuarios;
  IF v_filas <> 0 THEN
    RAISE EXCEPTION 'GATE C: portal_usuarios ya tiene % fila(s) (esperado 0 tras Bloque B). Filas inesperadas — revisá/limpiá conscientemente antes de sembrar.', v_filas;
  END IF;
END
$pre$;

-- ----------------------------------------------------------------------------
-- 4. SEED: resuelve user_id por email (JOIN auth.users). Sin WHERE NOT EXISTS:
--    el guard (e) ya garantizó tabla vacía -> siembra exactamente las 5 filas.
-- ----------------------------------------------------------------------------
INSERT INTO public.portal_usuarios (user_id, nombre, rol)
SELECT u.id, s.nombre, s.rol
FROM _seed_usuarios s
JOIN auth.users u ON u.email = s.email;

-- ----------------------------------------------------------------------------
-- 5. VERIFICACIÓN POST-SEED (aborta si el conteo no cierra -> rollback).
-- ----------------------------------------------------------------------------
DO $post$
DECLARE v_n int; v_soc int; v_vic int; v_jen int; v_act int; v_uid int;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE rol='socio'),
         count(*) FILTER (WHERE rol='vicky'),
         count(*) FILTER (WHERE rol='jenny'),
         count(*) FILTER (WHERE activo),
         count(DISTINCT user_id)
    INTO v_n, v_soc, v_vic, v_jen, v_act, v_uid
  FROM public.portal_usuarios;

  IF v_n <> 5 OR v_soc <> 3 OR v_vic <> 1 OR v_jen <> 1 OR v_act <> 5 OR v_uid <> 5 THEN
    RAISE EXCEPTION 'GATE C (post-seed): conteo inesperado (filas=%, socio=%, vicky=%, jenny=%, activos=%, user_id_unicos=%). Esperado 5/3/1/1/5/5. Abortado.',
      v_n, v_soc, v_vic, v_jen, v_act, v_uid;
  END IF;
END
$post$;

-- ----------------------------------------------------------------------------
-- 6. VEREDICTO LEGIBLE (último SELECT => lo muestra el Editor). + fila TOTAL.
-- ----------------------------------------------------------------------------
WITH v(ord, chequeo, veredicto, detalle) AS (
  VALUES
  (1, 'total_filas',
      CASE WHEN (SELECT count(*) FROM public.portal_usuarios)=5 THEN 'PASS' ELSE 'FALLO' END,
      (SELECT count(*)::text FROM public.portal_usuarios)),
  (2, 'socios_3',
      CASE WHEN (SELECT count(*) FROM public.portal_usuarios WHERE rol='socio')=3 THEN 'PASS' ELSE 'FALLO' END,
      'franco/rodrigo/remo'),
  (3, 'vicky_1',
      CASE WHEN (SELECT count(*) FROM public.portal_usuarios WHERE rol='vicky')=1 THEN 'PASS' ELSE 'FALLO' END,
      'rol vicky'),
  (4, 'jenny_1',
      CASE WHEN (SELECT count(*) FROM public.portal_usuarios WHERE rol='jenny')=1 THEN 'PASS' ELSE 'FALLO' END,
      'rol jenny'),
  (5, 'todos_activos',
      CASE WHEN (SELECT count(*) FROM public.portal_usuarios WHERE activo)=5 THEN 'PASS' ELSE 'FALLO' END,
      'activo = true'),
  (6, 'user_id_unicos',
      CASE WHEN (SELECT count(DISTINCT user_id) FROM public.portal_usuarios)=5 THEN 'PASS' ELSE 'FALLO' END,
      'sin colisión de user_id'),
  (7, 'ambiente_ops',
      CASE WHEN (SELECT valor FROM configuracion_general WHERE clave='ambiente')='ops' THEN 'PASS' ELSE 'FALLO' END,
      'ambiente = ops')
)
SELECT ord, chequeo, veredicto, detalle FROM v
UNION ALL
SELECT 999, 'TOTAL',
  CASE WHEN (SELECT count(*) FROM v WHERE veredicto='FALLO')=0 THEN 'VERDE' ELSE 'FRENAR' END,
  (SELECT count(*)||' FALLO de 7' FROM v WHERE veredicto='FALLO')
ORDER BY ord;

COMMIT;

-- Vista nominal (opcional; correr aislado — el Editor muestra 1 SELECT):
--   SELECT nombre, rol, activo, user_id FROM public.portal_usuarios ORDER BY rol, nombre;
--
-- ============================================================================
-- TEARDOWN CONSCIENTE DEL SEED (NO ejecutar salvo que quieras re-sembrar).
-- Borra SOLO las filas (no la tabla; la estructura es del Bloque B). Gate ops.
--   BEGIN;
--   DO $g$ DECLARE v text; BEGIN
--     SELECT valor INTO v FROM configuracion_general WHERE clave='ambiente';
--     IF v IS DISTINCT FROM 'ops' THEN RAISE EXCEPTION 'TEARDOWN: ambiente=% no es ops.', v; END IF;
--   END $g$;
--   DELETE FROM public.portal_usuarios;
--   COMMIT;
-- ============================================================================
