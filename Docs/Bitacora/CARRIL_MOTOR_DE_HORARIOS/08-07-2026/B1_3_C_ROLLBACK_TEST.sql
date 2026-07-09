-- =====================================================================
-- B1.3-C - ROLLBACK (reverse patch) de crear_prereserva(jsonb)
-- =====================================================================
-- Quita el sub-bloque [B1.3-C:BEGIN..END] insertado por el patch y recrea la
-- funcion con DROP + CREATE, re-aplicando el REVOKE owner-only. Aborta si el
-- ambiente no es 'test' (antes de cualquier DROP). Verifica que la definicion
-- restaurada coincide EXACTAMENTE con el fingerprint baseline (d92a438e...):
-- si no coincide, aborta sin tocar nada.
-- Ejecutar el script ENTERO. Solo si se quiere revertir C.
-- =====================================================================

BEGIN;

DO $c$
DECLARE
  c_fp_base CONSTANT text := 'd92a438eb4f11decac981cc65f2a5e53';  -- baseline a restaurar (TEST/PG17)
  c_anchor  CONSTANT text := '  v_expira_en := NOW() + (v_expiracion_minutos || '' minutes'')::INTERVAL;';
  v_def     text;
  v_base    text;
  v_create  text;
  v_bloque  text;
  v_ocurr   int;
  v_fp_new  text;
  v_amb     text;
BEGIN
  PERFORM pg_advisory_xact_lock(10, 0);

  -- ── GATE 0: ambiente test (fail-closed ANTES de cualquier DROP) ──
  v_amb := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  IF COALESCE(v_amb, '') <> 'test' THEN
    RAISE EXCEPTION 'C-RB: ambiente=% (esperado test). Abortando.', COALESCE(v_amb, '<null>');
  END IF;

  IF to_regprocedure('public.crear_prereserva(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'C-RB: crear_prereserva(jsonb) no existe. Abortando.';
  END IF;

  v_def := pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure);
  IF position('[B1.3-C' in v_def) = 0 THEN
    RAISE EXCEPTION 'C-RB: crear_prereserva no tiene el bloque [B1.3-C]; nada que revertir. Abortando.';
  END IF;

  -- Reconstruir el bloque EXACTO insertado por el patch (mismo texto).
  v_bloque :=
    '  -- [B1.3-C:BEGIN] Gate de gap de turno (Modelo alfa) contra horas congeladas de vecinos.' || E'\n' ||
    '  -- Excl NULL/NULL: la pre-reserva candidata aun no existe; aplica a TODOS los canales.'   || E'\n' ||
    '  -- Va tras validar_disponibilidad y el calculo de horas finales, antes del INSERT.'       || E'\n' ||
    '  DECLARE'                                                                                   || E'\n' ||
    '    v_gap_res JSONB;'                                                                        || E'\n' ||
    '  BEGIN'                                                                                      || E'\n' ||
    '    v_gap_res := public.validar_gap_bordes_congelados('                                      || E'\n' ||
    '      v_id_cabana, v_fecha_in, v_hora_checkin_final, v_fecha_out, v_hora_checkout_final, NULL, NULL);' || E'\n' ||
    '    IF NOT COALESCE((v_gap_res->>''ok'')::BOOLEAN, FALSE) THEN'                              || E'\n' ||
    '      RETURN v_gap_res;'                                                                     || E'\n' ||
    '    END IF;'                                                                                  || E'\n' ||
    '  END;'                                                                                       || E'\n' ||
    '  -- [B1.3-C:END]'                                                                            || E'\n';

  v_ocurr := (length(v_def) - length(replace(v_def, v_bloque || c_anchor, ''))) / NULLIF(length(v_bloque || c_anchor), 0);
  IF v_ocurr <> 1 THEN
    RAISE EXCEPTION 'C-RB: patron (bloque+anchor) aparece % vez/veces (esperado 1). Abortando.', v_ocurr;
  END IF;

  -- Quitar el bloque, dejando el anchor.
  v_base := replace(v_def, v_bloque || c_anchor, c_anchor);

  -- Verificar restauracion exacta ANTES de recrear (fail-closed).
  v_create := replace(v_base, 'CREATE OR REPLACE FUNCTION public.crear_prereserva',
                              'CREATE FUNCTION public.crear_prereserva');

  EXECUTE 'DROP FUNCTION public.crear_prereserva(jsonb)';
  EXECUTE v_create;
  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.crear_prereserva(jsonb) FROM PUBLIC, anon, authenticated, service_role';

  -- Postcheck: sin validador y fingerprint == baseline.
  v_def := pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure);
  IF position('validar_gap_bordes_congelados' in v_def) > 0 THEN
    RAISE EXCEPTION 'C-RB: la definicion restaurada aun referencia el validador. Abortando.';
  END IF;
  v_fp_new := md5(v_def);
  IF v_fp_new <> c_fp_base THEN
    RAISE EXCEPTION 'C-RB: fingerprint restaurado = % (esperado baseline %). NO coincide.', v_fp_new, c_fp_base;
  END IF;

  RAISE NOTICE 'C revertido. crear_prereserva restaurado al baseline (fingerprint = %).', v_fp_new;
END $c$;

COMMIT;

SELECT md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure)) AS crear_prereserva_fp_restaurado;
