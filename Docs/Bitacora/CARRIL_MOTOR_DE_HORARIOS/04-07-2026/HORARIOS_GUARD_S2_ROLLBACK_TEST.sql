-- =====================================================================
-- HORARIOS_GUARD_S2_ROLLBACK_TEST.sql
-- Rollback de S2: elimina SOLO crear_override_horario(jsonb). ALCANCE: SOLO TEST.
-- Deja intactos R0 (resolver), S0 (validadores) y S1 (trg_guard_overrides + trg_ov_guard).
-- Correr el script COMPLETO (L-8A-01).
-- =====================================================================

BEGIN;

DO $gate$
DECLARE v_amb text := (SELECT valor FROM configuracion_general WHERE clave='ambiente');
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN RAISE EXCEPTION 'ROLLBACK S2 abortado: ambiente=% (esperado test).', v_amb; END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN RAISE EXCEPTION 'ROLLBACK S2 abortado: schema=%.', current_schema(); END IF;
  RAISE NOTICE 'ROLLBACK S2: ambiente=test OK, quitando crear_override_horario(jsonb).';
END
$gate$;

DROP FUNCTION IF EXISTS public.crear_override_horario(jsonb);

COMMIT;

-- ---- Confirmacion: la funcion se fue; R0/S0/S1 intactos ----
SELECT
  to_regprocedure('public.crear_override_horario(jsonb)') IS NULL               AS funcion_ausente,
  to_regprocedure('public.validar_estado_override(bigint,date)') IS NOT NULL    AS validadores_s0_intactos,
  to_regprocedure('public.trg_guard_overrides()') IS NOT NULL                   AS trigger_fn_s1_intacta,
  EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
          WHERE c.relname='overrides_operativos' AND t.tgname='trg_ov_guard' AND NOT t.tgisinternal) AS constraint_trigger_s1_intacto,
  md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)'))) = '58d75c1b6b812ee2d2c9751ddcb0cd4d' AS resolver_r0_intacto;
