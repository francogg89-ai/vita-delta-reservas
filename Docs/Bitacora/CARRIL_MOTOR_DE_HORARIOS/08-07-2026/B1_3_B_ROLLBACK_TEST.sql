-- =====================================================================
-- B1.3-B - ROLLBACK del artefacto B
-- Elimina public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint).
-- No toca reservas/pre_reservas ni el motor semanal. Transaccion unica. Lock (10,0).
-- Ejecutar el script entero en SQL Editor.
-- =====================================================================

BEGIN;

SELECT pg_advisory_xact_lock(10, 0);

-- ---- GATE: la funcion debe existir (B aplicado) ----
DO $gate$
DECLARE v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ROLLBACK B1.3-B: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'ROLLBACK B1.3-B: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)') IS NULL THEN
    RAISE EXCEPTION 'ROLLBACK B1.3-B: la funcion no existe (B no aplicado?). Abortando.';
  END IF;
  RAISE NOTICE 'GATE OK: validar_gap_bordes_congelados presente.';
END
$gate$;

DROP FUNCTION public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint);

-- ---- POSTCHECK ----
DO $post$
BEGIN
  IF to_regprocedure('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'POST-RB-B: la funcion sigue existiendo.';
  END IF;
  RAISE NOTICE 'POSTCHECK-RB-B OK: funcion eliminada.';
END
$post$;

COMMIT;

-- ---- REPORTE ----
SELECT
  'B1.3-B ROLLBACK aplicado (TEST)' AS estado,
  (to_regprocedure('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)') IS NULL) AS funcion_eliminada;
