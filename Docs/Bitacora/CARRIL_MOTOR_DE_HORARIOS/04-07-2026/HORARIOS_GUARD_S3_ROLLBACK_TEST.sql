-- =====================================================================
-- HORARIOS_GUARD_S3_ROLLBACK_TEST.sql
-- Revierte SOLO S3: elimina crear_paquete_dia_especial(jsonb).
-- NO toca R0 (resolver), S0 (validadores), S1 (trg_guard_overrides + trg_ov_guard) ni S2
-- (crear_override_horario). ALCANCE: SOLO TEST. Correr el script COMPLETO (L-8A-01).
-- =====================================================================

BEGIN;

DO $gate$
DECLARE v_amb text := (SELECT valor FROM configuracion_general WHERE clave='ambiente');
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN RAISE EXCEPTION 'ROLLBACK S3 abortado: ambiente=% (esperado test).', v_amb; END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN RAISE EXCEPTION 'ROLLBACK S3 abortado: schema=%.', current_schema(); END IF;
  RAISE NOTICE 'ROLLBACK S3 GATE OK.';
END
$gate$;

DROP FUNCTION IF EXISTS public.crear_paquete_dia_especial(jsonb);

DO $verify$
DECLARE v_faltan text := '';
BEGIN
  IF to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK S3 FALLA: crear_paquete_dia_especial sigue presente.';
  END IF;
  -- R0 / S0 / S1 / S2 deben seguir intactos
  IF to_regprocedure('public.resolver_horario(bigint,date)') IS NULL THEN v_faltan := v_faltan || 'resolver_horario '; END IF;
  IF to_regprocedure('public.validar_estado_horario_final(bigint,date)') IS NULL THEN v_faltan := v_faltan || 'validar_estado_horario_final '; END IF;
  IF to_regprocedure('public.validar_no_eventos_comprometidos(bigint,date)') IS NULL THEN v_faltan := v_faltan || 'validar_no_eventos_comprometidos '; END IF;
  IF to_regprocedure('public.validar_estado_override(bigint,date)') IS NULL THEN v_faltan := v_faltan || 'validar_estado_override '; END IF;
  IF to_regprocedure('public.trg_guard_overrides()') IS NULL THEN v_faltan := v_faltan || 'trg_guard_overrides '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                 WHERE c.relname='overrides_operativos' AND t.tgname='trg_ov_guard' AND NOT t.tgisinternal) THEN
    v_faltan := v_faltan || 'trg_ov_guard ';
  END IF;
  IF to_regprocedure('public.crear_override_horario(jsonb)') IS NULL THEN v_faltan := v_faltan || 'crear_override_horario '; END IF;
  IF v_faltan <> '' THEN
    RAISE EXCEPTION 'ROLLBACK S3 FALLA: el rollback afecto dependencias R0/S0/S1/S2: %', v_faltan;
  END IF;
  RAISE NOTICE 'ROLLBACK S3 OK: crear_paquete_dia_especial eliminada; R0/S0/S1/S2 intactos.';
END
$verify$;

COMMIT;

-- ---- Confirmacion (fila-veredicto) ----
SELECT
  to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL AS s3_ausente,
  to_regprocedure('public.resolver_horario(bigint,date)') IS NOT NULL AS r0_ok,
  to_regprocedure('public.validar_estado_override(bigint,date)') IS NOT NULL AS s0_ok,
  to_regprocedure('public.trg_guard_overrides()') IS NOT NULL AS s1_fn_ok,
  EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
          WHERE c.relname='overrides_operativos' AND t.tgname='trg_ov_guard' AND NOT t.tgisinternal) AS s1_trg_ok,
  to_regprocedure('public.crear_override_horario(jsonb)') IS NOT NULL AS s2_ok;
