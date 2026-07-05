-- =====================================================================
-- HORARIOS_GUARD_S1_ROLLBACK_TEST.sql
-- Rollback de S1: quita la barrera (constraint trigger + trigger-fn). ALCANCE: SOLO TEST.
-- Deja intactos los validadores S0 (son de otro sub-bloque) y el resolver R0.
-- Correr el script COMPLETO (L-8A-01).
-- =====================================================================

BEGIN;

DO $gate$
DECLARE v_amb text := (SELECT valor FROM configuracion_general WHERE clave = 'ambiente');
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ROLLBACK S1 abortado: ambiente=% (esperado test).', v_amb;
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'ROLLBACK S1 abortado: schema=% (esperado public).', current_schema();
  END IF;
  RAISE NOTICE 'ROLLBACK S1: ambiente=test OK, quitando trigger + trigger-fn.';
END
$gate$;

DROP TRIGGER IF EXISTS trg_ov_guard ON overrides_operativos;
DROP FUNCTION IF EXISTS public.trg_guard_overrides();

COMMIT;

-- ---- Confirmacion: trigger y trigger-fn ausentes; validadores S0 intactos ----
SELECT
  NOT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
    WHERE c.relname='overrides_operativos' AND t.tgname='trg_ov_guard' AND NOT t.tgisinternal
  )                                                                     AS trigger_ausente,
  to_regprocedure('public.trg_guard_overrides()') IS NULL              AS trigger_fn_ausente,
  to_regprocedure('public.validar_estado_override(bigint,date)') IS NOT NULL AS validadores_s0_intactos;
