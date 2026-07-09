-- =====================================================================
-- B1.3-E - ROLLBACK de crear_reserva_con_horario_pactado(jsonb)
-- =====================================================================
-- Elimina la funcion creada por B1_3_E_CREAR_RESERVA_PACTADA_TEST.sql. Aborta si el
-- ambiente no es 'test' (antes de cualquier DROP) o si la funcion no existe.
-- No toca crear_prereserva ni confirmar_reserva. Ejecutar el script ENTERO.
-- =====================================================================

BEGIN;

DO $rb$
DECLARE v_amb text;
BEGIN
  PERFORM pg_advisory_xact_lock(10, 0);

  v_amb := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  IF COALESCE(v_amb, '') <> 'test' THEN
    RAISE EXCEPTION 'E-RB: ambiente=% (esperado test). Abortando.', COALESCE(v_amb, '<null>');
  END IF;

  IF to_regprocedure('public.crear_reserva_con_horario_pactado(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'E-RB: crear_reserva_con_horario_pactado no existe; nada que revertir. Abortando.';
  END IF;
END $rb$;

DROP FUNCTION public.crear_reserva_con_horario_pactado(jsonb);

COMMIT;

SELECT to_regprocedure('public.crear_reserva_con_horario_pactado(jsonb)') IS NULL AS funcion_eliminada;
