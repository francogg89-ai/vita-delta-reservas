-- ============================================================================
-- C_SLICE0_A1_DDL_portal_usuarios.sql
-- Carril C / Portal Operativo Interno — Slice 0, Fase A (paso 1 de 2).
-- Crea la tabla portal_usuarios (identidad auth.users -> rol del portal) en TEST.
-- Decisiones: D-C-14 (identidad por tabla), D-C-22 (nombre = persona),
--             D-C-32 (seed por email), D-C-34 (interna, no vía Data API).
--
-- QUÉ HACE:
--   1. Gate de entorno DURO: configuracion_general('ambiente') = 'test'
--      (único discriminador fiable TEST vs OPS, L-7B-01: los ids de cabaña 1-5
--       son idénticos en ambos y NO discriminan).
--   2. Guard de re-ejecución: aborta si portal_usuarios ya existe (no la pisa).
--   3. CREATE TABLE portal_usuarios + FK a auth.users + CHECK de rol.
--   4. Hardening D-C-34: REVOKE a PUBLIC/anon/authenticated; GRANT SELECT solo
--      a service_role (lector server-side de la Edge Function portal-api).
--      El navegador (anon / authenticated) NO la puede leer por Data API.
--   5. Assert duro de seguridad + verificación estructural (filas de veredicto).
--
-- NO siembra datos: el seed es A2 y va DESPUÉS de crear los 5 usuarios de Auth
-- (ver runsheet). Esta tabla nace VACÍA.
--
-- CÓMO CORRER: SQL Editor de Supabase del proyecto TEST, con NADA seleccionado
-- (L-8A-01), todo el archivo de una. Si algo no calza, RAISE aborta TODA la
-- transacción: o entra completa y consistente, o no entra nada.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1 + 2. GATE DE ENTORNO + GUARD DE RE-EJECUCIÓN
--        ambiente='test' es la verdad; cabañas 1-5 es sanity de "DB real".
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb     text;
  v_cab     int;
  v_exists  int;
BEGIN
  -- (a) Marcador de ambiente: discriminador real TEST/OPS.
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE A1: ambiente=% (esperado test). Abortado para no tocar OPS.',
      COALESCE(v_amb, '<ausente>');
  END IF;

  -- (b) Sanity: ¿es una DB Vita Delta real? (cabañas 1-5 por id+nombre).
  SELECT count(*) INTO v_cab
  FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
  WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana = e.id AND c.nombre = e.nom);
  IF v_cab <> 5 THEN
    RAISE EXCEPTION 'GATE A1: identidad de cabañas no coincide (% de 5). DB inesperada.', v_cab;
  END IF;

  -- (c) Guard de re-ejecución: no clobbear una tabla existente.
  SELECT count(*) INTO v_exists
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname = 'portal_usuarios';
  IF v_exists <> 0 THEN
    RAISE EXCEPTION 'GATE A1: portal_usuarios ya existe. Para recrear, DROP consciente y separado (runsheet), luego re-corré.';
  END IF;
END
$gate$;

-- ----------------------------------------------------------------------------
-- 3. CREATE TABLE portal_usuarios
--    user_id : FK a auth.users (patrón Supabase profiles), ON DELETE CASCADE.
--    nombre  : identificador de PERSONA (D-C-22), TEXT libre UNIQUE.
--              (sin CHECK enumerado: los creado_por/validado_por aguas abajo solo
--               exigen no-vacío, no una lista cerrada — verificado en el schema.)
--    rol     : set CERRADO de política {jenny,vicky,socio} (D-C-14), con CHECK.
--    activo  : baja lógica; inactivo => la Edge Function devuelve no_autorizado.
-- ----------------------------------------------------------------------------
CREATE TABLE public.portal_usuarios (
  user_id     uuid        PRIMARY KEY
                          REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre      text        NOT NULL,
  rol         text        NOT NULL,
  activo      boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_portal_usuarios_nombre     UNIQUE (nombre),
  CONSTRAINT chk_portal_usuarios_rol       CHECK (rol IN ('jenny','vicky','socio')),
  CONSTRAINT chk_portal_usuarios_nombre_ne CHECK (length(btrim(nombre)) > 0)
);

COMMENT ON TABLE public.portal_usuarios IS
  'Carril C / Slice 0: mapeo identidad(auth.users)->rol del Portal Operativo Interno. Interna: sin acceso por Data API (D-C-34); la lee solo la Edge Function portal-api vía service_role.';
COMMENT ON COLUMN public.portal_usuarios.nombre IS
  'Identificador de persona (vicky/franco/rodrigo/remo/jenny) usado como creado_por/validado_por (D-C-22), no el rol.';

-- ----------------------------------------------------------------------------
-- 4. HARDENING D-C-34 — invisible al Data API del navegador.
--    Supabase, por ALTER DEFAULT PRIVILEGES, puede dejar grants residuales a los
--    roles del Data API en tablas recién creadas (L-PROMO). Por eso REVOKE
--    explícito a anon/authenticated/PUBLIC, y GRANT explícito (determinístico) de
--    SOLO SELECT a service_role (lector server-side de la Edge Function).
-- ----------------------------------------------------------------------------
REVOKE ALL    ON public.portal_usuarios FROM PUBLIC;
REVOKE ALL    ON public.portal_usuarios FROM anon;
REVOKE ALL    ON public.portal_usuarios FROM authenticated;
REVOKE ALL    ON public.portal_usuarios FROM service_role;
GRANT  SELECT ON public.portal_usuarios TO   service_role;

-- ----------------------------------------------------------------------------
-- 5a. ASSERT DURO DE SEGURIDAD (D-C-34). Si el navegador pudiera leer, o si el
--     gateway no pudiera, ABORTA (rollback). has_table_privilege da el privilegio
--     EFECTIVO (cubre PUBLIC + herencia), que es justo lo que importa.
-- ----------------------------------------------------------------------------
DO $assert$
BEGIN
  IF has_table_privilege('anon',          'public.portal_usuarios', 'SELECT')
  OR has_table_privilege('authenticated', 'public.portal_usuarios', 'SELECT') THEN
    RAISE EXCEPTION 'ASSERT A1: portal_usuarios accesible por anon/authenticated — VIOLA D-C-34. Abortado.';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.portal_usuarios', 'SELECT') THEN
    RAISE EXCEPTION 'ASSERT A1: service_role no puede leer portal_usuarios — la Edge Function no podría resolver rol. Abortado.';
  END IF;
END
$assert$;

-- ----------------------------------------------------------------------------
-- 5b. VERIFICACIÓN ESTRUCTURAL (filas de veredicto legibles). El SQL Editor
--     muestra el último SELECT: UNION ALL con ord/chequeo/veredicto/detalle.
-- ----------------------------------------------------------------------------
SELECT * FROM (
  SELECT 1 AS ord, 'tabla_existe' AS chequeo,
    CASE WHEN EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                      WHERE n.nspname='public' AND c.relname='portal_usuarios' AND c.relkind='r')
         THEN 'PASS' ELSE 'FALLO' END AS veredicto,
    'public.portal_usuarios' AS detalle
  UNION ALL
  SELECT 2, 'fk_auth_users',
    CASE WHEN EXISTS (SELECT 1 FROM pg_constraint con
                      JOIN pg_class c ON c.oid=con.conrelid
                      JOIN pg_namespace n ON n.oid=c.relnamespace
                      WHERE n.nspname='public' AND c.relname='portal_usuarios' AND con.contype='f')
         THEN 'PASS' ELSE 'FALLO' END,
    'FK user_id -> auth.users'
  UNION ALL
  SELECT 3, 'check_rol',
    CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_portal_usuarios_rol')
         THEN 'PASS' ELSE 'FALLO' END,
    'rol IN (jenny,vicky,socio)'
  UNION ALL
  SELECT 4, 'anon_no_select',
    CASE WHEN NOT has_table_privilege('anon','public.portal_usuarios','SELECT')
         THEN 'PASS' ELSE 'FALLO' END,
    'anon NO puede SELECT (Data API ciego)'
  UNION ALL
  SELECT 5, 'authenticated_no_select',
    CASE WHEN NOT has_table_privilege('authenticated','public.portal_usuarios','SELECT')
         THEN 'PASS' ELSE 'FALLO' END,
    'authenticated NO puede SELECT (navegador ciego)'
  UNION ALL
  SELECT 6, 'service_role_select',
    CASE WHEN has_table_privilege('service_role','public.portal_usuarios','SELECT')
         THEN 'PASS' ELSE 'FALLO' END,
    'service_role SÍ puede SELECT (lector Edge Fn)'
  UNION ALL
  SELECT 7, 'service_role_no_write',
    CASE WHEN NOT has_table_privilege('service_role','public.portal_usuarios','INSERT')
          AND NOT has_table_privilege('service_role','public.portal_usuarios','UPDATE')
          AND NOT has_table_privilege('service_role','public.portal_usuarios','DELETE')
         THEN 'PASS' ELSE 'FALLO' END,
    'service_role NO escribe en runtime'
  UNION ALL
  SELECT 8, 'tabla_vacia',
    CASE WHEN (SELECT count(*) FROM public.portal_usuarios)=0 THEN 'PASS' ELSE 'FALLO' END,
    'nace vacía (seed = A2)'
  UNION ALL
  SELECT 9, 'ambiente',
    CASE WHEN (SELECT valor FROM configuracion_general WHERE clave='ambiente')='test'
         THEN 'PASS' ELSE 'FALLO' END,
    'ambiente = test'
) v ORDER BY ord;

COMMIT;

-- ============================================================================
-- TEARDOWN CONSCIENTE (NO ejecutar salvo que quieras recrear de cero).
-- Descomentar, seleccionar SOLO estas líneas y correr. portal_usuarios no tiene
-- dependientes (es hoja); por eso DROP simple, sin CASCADE.
--   BEGIN;
--   DO $g$ DECLARE v text; BEGIN
--     SELECT valor INTO v FROM configuracion_general WHERE clave='ambiente';
--     IF v IS DISTINCT FROM 'test' THEN RAISE EXCEPTION 'TEARDOWN: ambiente=% no es test.', v; END IF;
--   END $g$;
--   DROP TABLE IF EXISTS public.portal_usuarios;
--   COMMIT;
-- ============================================================================
