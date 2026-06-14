-- ============================================================================
-- PARCHE_TEST_LIMPIEZA_ACL_TABLAS.sql   (SOLO TEST — NO correr en OPS)
-- Quita los grants residuales Dxtm (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) que el
-- ALTER DEFAULT PRIVILEGES de Supabase dejó en anon/authenticated/service_role
-- sobre las 4 tablas tempranas de Carril B en TEST. Deja TEST tan hardened como
-- OPS (que ya está limpio). Read-only sobre datos; solo cambia ACL.
--
-- Transacción única. Gate ambiente='test' (anti-OPS). Verificación de que las
-- tablas existen y de que HAY grants residuales (si no, no hay nada que limpiar).
-- REVOKE ALL a PUBLIC/anon/authenticated/service_role. Assert posterior: 0 grants
-- Data API/PUBLIC. Correr en TEST con NADA seleccionado.
-- ============================================================================

BEGIN;

-- ── Gate: ambiente debe ser 'test' (jamás OPS) ──────────────────────────────
DO $gate$
DECLARE v_amb text; v_faltan int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE ambiente: este parche es SOLO para TEST; encontrado ambiente=%', COALESCE(v_amb,'(null)');
  END IF;

  -- las 4 tablas deben existir
  SELECT 4 - count(*) INTO v_faltan
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r'
      AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos');
  IF v_faltan <> 0 THEN
    RAISE EXCEPTION 'GATE tablas: faltan % de las 4 tablas tempranas en TEST', v_faltan;
  END IF;
END
$gate$;

-- ── Verificación previa: ¿hay grants residuales a Data API/PUBLIC? ───────────
DO $pre$
DECLARE v_grants int;
BEGIN
  SELECT count(*) INTO v_grants
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) a
    WHERE n.nspname='public' AND c.relkind='r'
      AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos')
      AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_grants = 0 THEN
    RAISE EXCEPTION 'PRE: no hay grants residuales a PUBLIC/Data API en las 4 tablas — TEST ya está limpio, nada que hacer.';
  END IF;
  RAISE NOTICE 'PRE: % grants residuales a PUBLIC/Data API detectados; procediendo al REVOKE ALL.', v_grants;
END
$pre$;

-- ── REVOKE ALL (saca arwdDxtm a PUBLIC y a los 3 roles Data API) ─────────────
REVOKE ALL ON TABLE public.zonas                   FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.cabana_zona             FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.activaciones_operativas FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.gastos_internos         FROM PUBLIC, anon, authenticated, service_role;

-- ── Assert posterior: 0 grants Data API/PUBLIC en las 4 tablas ──────────────
DO $post$
DECLARE v_grants int;
BEGIN
  SELECT count(*) INTO v_grants
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) a
    WHERE n.nspname='public' AND c.relkind='r'
      AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos')
      AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_grants <> 0 THEN
    RAISE EXCEPTION 'POST: aún quedan % grants a PUBLIC/Data API (esperado 0)', v_grants;
  END IF;
  RAISE NOTICE 'POST OK: 0 grants a PUBLIC/Data API en las 4 tablas. TEST alineado a OPS.';
END
$post$;

COMMIT;

-- ── Verificación posterior (read-only) ──────────────────────────────────────
SELECT c.relname AS tabla, COALESCE(c.relacl::text,'NULL') AS relacl
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r'
  AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos')
ORDER BY c.relname;

-- Reversión conceptual: innecesaria (quitar grants residuales es solo hardening).
-- Si se quisiera restaurar el estado Supabase-default, se re-otorgarían con GRANT,
-- pero no se recomienda (sería un retroceso de seguridad).
