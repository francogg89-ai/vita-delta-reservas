-- =====================================================================
-- B1.3-D - ROLLBACK (reverse patch) de confirmar_reserva(jsonb)
-- =====================================================================
-- Quita el sub-bloque [B1.3-D:BEGIN..END] insertado por el patch y recrea la
-- funcion con DROP + CREATE, re-aplicando el REVOKE owner-only. Aborta si el
-- ambiente no es 'test' (antes de cualquier DROP). Verifica que la definicion
-- restaurada coincide EXACTAMENTE con el fingerprint baseline (6cbc9102...):
-- si no coincide, aborta sin tocar nada.
-- Ejecutar el script ENTERO. Solo si se quiere revertir D.
-- =====================================================================

BEGIN;

DO $d$
DECLARE
  c_fp_base CONSTANT text := '6cbc9102d0aa75dbf56af826f0ba1b3d';  -- baseline a restaurar (TEST/PG17)
  c_anchor  CONSTANT text := E'  BEGIN\n    INSERT INTO reservas (';
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
    RAISE EXCEPTION 'D-RB: ambiente=% (esperado test). Abortando.', COALESCE(v_amb, '<null>');
  END IF;

  IF to_regprocedure('public.confirmar_reserva(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'D-RB: confirmar_reserva(jsonb) no existe. Abortando.';
  END IF;

  v_def := pg_get_functiondef('public.confirmar_reserva(jsonb)'::regprocedure);
  IF position('[B1.3-D' in v_def) = 0 THEN
    RAISE EXCEPTION 'D-RB: confirmar_reserva no tiene el bloque [B1.3-D]; nada que revertir. Abortando.';
  END IF;

  -- Reconstruir el bloque EXACTO insertado por el patch (mismo texto).
  v_bloque :=
    '  -- [B1.3-D:BEGIN] Gate de gap de turno (Modelo alfa) al confirmar: horas congeladas' || E'\n' ||
    '  -- de la pre-reserva vs vecinos. Excluye la propia pre-reserva (evita auto-conflicto).' || E'\n' ||
    '  DECLARE'                                                                                 || E'\n' ||
    '    v_gap_res JSONB;'                                                                      || E'\n' ||
    '  BEGIN'                                                                                    || E'\n' ||
    '    v_gap_res := public.validar_gap_bordes_congelados('                                    || E'\n' ||
    '      v_pre.id_cabana, v_pre.fecha_in, v_pre.hora_checkin, v_pre.fecha_out, v_pre.hora_checkout, NULL, v_id_pre_reserva);' || E'\n' ||
    '    IF NOT COALESCE((v_gap_res->>''ok'')::BOOLEAN, FALSE) THEN'                            || E'\n' ||
    '      RETURN v_gap_res;'                                                                   || E'\n' ||
    '    END IF;'                                                                                || E'\n' ||
    '  END;'                                                                                     || E'\n' ||
    '  -- [B1.3-D:END]'                                                                          || E'\n';

  v_ocurr := (length(v_def) - length(replace(v_def, v_bloque || c_anchor, ''))) / NULLIF(length(v_bloque || c_anchor), 0);
  IF v_ocurr <> 1 THEN
    RAISE EXCEPTION 'D-RB: patron (bloque+anchor) aparece % vez/veces (esperado 1). Abortando.', v_ocurr;
  END IF;

  -- Quitar el bloque, dejando el anchor.
  v_base := replace(v_def, v_bloque || c_anchor, c_anchor);
  v_create := replace(v_base, 'CREATE OR REPLACE FUNCTION public.confirmar_reserva',
                              'CREATE FUNCTION public.confirmar_reserva');

  EXECUTE 'DROP FUNCTION public.confirmar_reserva(jsonb)';
  EXECUTE v_create;
  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.confirmar_reserva(jsonb) FROM PUBLIC, anon, authenticated, service_role';

  -- POSTCHECK ACL: owner-only (el rollback tambien hace DROP+CREATE => re-REVOKE + guard).
  DECLARE
    r text; v_bad int := 0;
  BEGIN
    FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
      IF has_function_privilege(r, 'public.confirmar_reserva(jsonb)', 'EXECUTE') THEN
        v_bad := v_bad + 1;
      END IF;
    END LOOP;
    IF v_bad <> 0 THEN
      RAISE EXCEPTION 'D-RB-ACL: privilegios EXECUTE indebidos = % (PUBLIC/anon/authenticated/service_role). Abortando.', v_bad;
    END IF;
  END;

  -- Postcheck: sin validador y fingerprint == baseline.
  v_def := pg_get_functiondef('public.confirmar_reserva(jsonb)'::regprocedure);
  IF position('validar_gap_bordes_congelados' in v_def) > 0 THEN
    RAISE EXCEPTION 'D-RB: la definicion restaurada aun referencia el validador. Abortando.';
  END IF;
  v_fp_new := md5(v_def);
  IF v_fp_new <> c_fp_base THEN
    RAISE EXCEPTION 'D-RB: fingerprint restaurado = % (esperado baseline %). NO coincide.', v_fp_new, c_fp_base;
  END IF;

  RAISE NOTICE 'D revertido. confirmar_reserva restaurado al baseline (fingerprint = %).', v_fp_new;
END $d$;

COMMIT;

SELECT md5(pg_get_functiondef('public.confirmar_reserva(jsonb)'::regprocedure)) AS confirmar_reserva_fp_restaurado;
