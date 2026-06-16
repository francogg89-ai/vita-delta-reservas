-- ============================================================================
-- RECONSTRUCCIÓN DE DEV — F5: HARDENING DE FUNCIONES DEL MOTOR (REVOKE EXECUTE)
-- Proyecto: VITA_DELTA_DEV · DEV_REF: wsrdzjmvnzxidjlovlja
-- ----------------------------------------------------------------------------
-- QUÉ HACE: revoca EXECUTE a PUBLIC/anon/authenticated/service_role sobre las
--   13 funciones del MOTOR (base), que un bootstrap fresco de v1.8.0 deja
--   PUBLIC-ejecutables por la NULL-acl. Lleva DEV a paridad con OPS/TEST.
--   Es el mismo REVOKE de 7E (D-7E-01) y de 8A Opción B (OPS). NO es rediseño.
--
-- ALCANCE: solo las 13 funciones del proyecto (por nombre). EXCLUYE extensiones
--   (btree_gist) — no se tocan por substring ni por ALL FUNCTIONS. Idempotente.
--
-- GATE: por marcador configuracion_general('ambiente') = 'dev'. Si el entorno no
--   es DEV (p. ej. OPS='ops'), aborta dentro de la transacción SIN cambios.
--   Reemplaza al gate por ID de cabaña (1-5 ya no discrimina; L-7E-01).
--
-- USO: SQL Editor del proyecto DEV nuevo, cada parte por separado, NADA
--   seleccionado. Parte 1 y 3 son read-only; Parte 2 es transaccional.
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- PARTE 1 — Diagnóstico (read-only). Debería listar las 13 con proacl NULL.
-- ────────────────────────────────────────────────────────────────────────────
SELECT p.oid::regprocedure AS funcion,
       (p.proacl IS NULL)  AS proacl_null_public_ejecuta
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'cancelar_prereserva','confirmar_reserva','crear_bloqueo','crear_prereserva',
    'expirar_prereservas_vencidas','log_cambio_estado','normalizar_telefono',
    'obtener_disponibilidad_rango','registrar_pago','set_telefono_normalizado',
    'set_updated_at','upsert_huesped','validar_disponibilidad')
ORDER BY 1;


-- ────────────────────────────────────────────────────────────────────────────
-- PARTE 2 — REVOKE transaccional con gate por ambiente='dev'.
-- ────────────────────────────────────────────────────────────────────────────
BEGIN;

DO $hardening_motor$
DECLARE
  v_amb   text;
  v_count int := 0;
  r       record;
BEGIN
  -- Gate de entorno (fuerte): solo DEV.
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'dev' THEN
    RAISE EXCEPTION 'GATE ambiente=% (esperado dev) — abortado, sin cambios', COALESCE(v_amb, '(null)');
  END IF;

  -- REVOKE por firma real, solo las 13 del proyecto (excluye extensiones).
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.objid = p.oid AND d.classid = 'pg_proc'::regclass AND d.deptype = 'e')
      AND p.proname IN (
        'cancelar_prereserva','confirmar_reserva','crear_bloqueo','crear_prereserva',
        'expirar_prereservas_vencidas','log_cambio_estado','normalizar_telefono',
        'obtener_disponibilidad_rango','registrar_pago','set_telefono_normalizado',
        'set_updated_at','upsert_huesped','validar_disponibilidad')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role', r.sig);
    v_count := v_count + 1;
  END LOOP;

  RAISE NOTICE 'Hardening motor OK (gate ambiente=dev): REVOKE EXECUTE aplicado a % funciones.', v_count;
END
$hardening_motor$;

COMMIT;


-- ────────────────────────────────────────────────────────────────────────────
-- PARTE 3 — Post-check (read-only). Esperado: funciones_expuestas_post = 0.
-- Misma lógica que S1 (NULL-acl + EXECUTE explícito a PUBLIC/API; excluye extensiones).
-- ────────────────────────────────────────────────────────────────────────────
SELECT count(*) AS funciones_expuestas_post
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND NOT EXISTS (SELECT 1 FROM pg_depend d
                  WHERE d.objid = p.oid AND d.classid = 'pg_proc'::regclass AND d.deptype = 'e')
  AND (
    p.proacl IS NULL
    OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
               WHERE a.privilege_type = 'EXECUTE'
                 AND (a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role')))
  );
