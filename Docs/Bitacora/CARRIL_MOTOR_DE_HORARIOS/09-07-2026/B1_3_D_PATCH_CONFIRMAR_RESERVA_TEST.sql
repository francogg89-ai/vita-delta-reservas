-- =====================================================================
-- B1.3-D - PATCH de confirmar_reserva(jsonb): cablea validar_gap_bordes_congelados
-- =====================================================================
-- Inserta el gate de gap de turno (Modelo alfa) DESPUES de validar_disponibilidad
-- y ANTES del INSERT en reservas. Usa las horas CONGELADAS de la propia pre-reserva
-- (v_pre.hora_checkin / v_pre.hora_checkout) y EXCLUYE esa pre-reserva
-- (p_excluir_prereserva = v_id_pre_reserva) para no auto-conflictuar al confirmarla.
--
-- Tecnica: patch DINAMICO sobre la definicion viva (pg_get_functiondef), inmune a
-- divergencia entre .sql y el estado desplegado. El validador se inserta como un
-- sub-bloque con DECLARE local (no toca el DECLARE global). Recreacion con
-- DROP + CREATE (no CREATE OR REPLACE: evita la inyeccion espuria de RLS de
-- Supabase) y RE-APLICA el REVOKE owner-only (un DROP deja proacl=NULL => PUBLIC).
--
-- Gates fail-closed (abortan sin tocar nada):
--   * ambiente == 'test' (antes de cualquier DROP).
--   * confirmar_reserva == fingerprint baseline exacto (6cbc9102...).
--   * validar_gap_bordes_congelados presente == fingerprint exacto (5c5ef50e...).
--   * anchor unico, sin cablear previamente, sin marcador [B1.3-D].
-- Postchecks: ACL owner-only (sin EXECUTE a PUBLIC/anon/authenticated/service_role)
--   y orden estructural lock(10,0) < lock(1,..) < validar_disponibilidad < gap < INSERT.
--
-- NO toca crear_prereserva (queda post-C). Reversible por B1_3_D_ROLLBACK_TEST.sql.
-- Ejecutar el script ENTERO en el SQL Editor.
-- =====================================================================

BEGIN;

DO $d$
DECLARE
  c_fp_base  CONSTANT text := '6cbc9102d0aa75dbf56af826f0ba1b3d';  -- confirmar_reserva baseline (TEST/PG17)
  c_fp_valid CONSTANT text := '5c5ef50eff10db716d17305dcbd54669';  -- validar_gap_bordes_congelados (TEST/PG17)
  c_ref      CONSTANT text := 'INSERT INTO reservas';  -- referencia estable (el INSERT ejecutable)
  v_fp_act   text;
  v_fp_val   text;
  v_def      text;
  v_new      text;
  v_create   text;
  v_bloque   text;
  v_ocurr    int;
  v_amb      text;
  p_l10 int; p_l1 int; p_disp int; p_gap int; p_ins int;
BEGIN
  -- Lock global (mismo orden que el motor).
  PERFORM pg_advisory_xact_lock(10, 0);

  -- ── GATE 0: ambiente test (fail-closed ANTES de cualquier DROP) ──
  v_amb := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  IF COALESCE(v_amb, '') <> 'test' THEN
    RAISE EXCEPTION 'D-GATE: ambiente=% (esperado test). Abortando.', COALESCE(v_amb, '<null>');
  END IF;

  -- ── GATE 1: fingerprint exacto del baseline ──
  IF to_regprocedure('public.confirmar_reserva(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'D-GATE: confirmar_reserva(jsonb) no existe. Abortando.';
  END IF;
  v_fp_act := md5(pg_get_functiondef('public.confirmar_reserva(jsonb)'::regprocedure));
  IF v_fp_act <> c_fp_base THEN
    RAISE EXCEPTION 'D-GATE: fingerprint de confirmar_reserva = % (esperado baseline %). Abortando.', v_fp_act, c_fp_base;
  END IF;

  -- ── GATE 2: validador gap presente con fingerprint exacto ──
  IF to_regprocedure('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)') IS NULL THEN
    RAISE EXCEPTION 'D-GATE: validar_gap_bordes_congelados ausente (B no aplicado). Abortando.';
  END IF;
  v_fp_val := md5(pg_get_functiondef('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)'::regprocedure));
  IF v_fp_val <> c_fp_valid THEN
    RAISE EXCEPTION 'D-GATE: fingerprint del validador gap = % (esperado %). Abortando.', v_fp_val, c_fp_valid;
  END IF;

  -- ── Leer definicion viva ──
  v_def := pg_get_functiondef('public.confirmar_reserva(jsonb)'::regprocedure);

  -- ── Verificaciones de patcheo (fail-closed) ──
  IF position('validar_gap_bordes_congelados' in v_def) > 0 THEN
    RAISE EXCEPTION 'D-PATCH: confirmar_reserva ya referencia el validador gap (idempotencia). Abortando.';
  END IF;
  IF position('[B1.3-D' in v_def) > 0 THEN
    RAISE EXCEPTION 'D-PATCH: marcador [B1.3-D] ya presente. Abortando.';
  END IF;
  -- Anclamos sobre el INSERT ejecutable (inicio de linea, tras indentacion): robusto ante
  -- indentacion y sin depender de un BEGIN local. La regex exige que entre el salto de linea
  -- y el INSERT solo haya whitespace (no '--'), excluyendo apariciones en comentarios.
  v_ocurr := (SELECT count(*) FROM regexp_matches(v_def, E'\\n[ \\t]*INSERT INTO reservas', 'g'));
  IF v_ocurr <> 1 THEN
    RAISE EXCEPTION 'D-PATCH: el INSERT ejecutable aparece % vez/veces (esperado 1). Abortando.', v_ocurr;
  END IF;

  -- ── Bloque a insertar: sub-bloque con DECLARE local (no toca el DECLARE global) ──
  -- Excluye la propia pre-reserva (v_id_pre_reserva); p_excluir_reserva NULL.
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

  -- ── Insertar el bloque como lineas completas ANTES de la linea del INSERT ──
  -- Queda tras validar_disponibilidad y antes del INSERT, preservando la indentacion REAL
  -- del INSERT (capturada en el grupo 2). No usa 'g': el patron ya es unico (verificado arriba).
  v_new := regexp_replace(v_def, E'(\\n)([ \\t]*)(INSERT INTO reservas)', E'\\1' || v_bloque || E'\\2\\3');

  -- ── DROP + CREATE (evita bug RLS de CREATE OR REPLACE en Supabase) ──
  v_create := replace(v_new, 'CREATE OR REPLACE FUNCTION public.confirmar_reserva',
                             'CREATE FUNCTION public.confirmar_reserva');
  EXECUTE 'DROP FUNCTION public.confirmar_reserva(jsonb)';
  EXECUTE v_create;

  -- ── Re-aplicar hardening owner-only (DROP dejo proacl=NULL => PUBLIC ejecuta) ──
  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.confirmar_reserva(jsonb) FROM PUBLIC, anon, authenticated, service_role';

  -- ── POSTCHECK ACL: owner-only (sin EXECUTE indebido) ──
  DECLARE
    r text; v_bad int := 0;
  BEGIN
    FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
      IF has_function_privilege(r, 'public.confirmar_reserva(jsonb)', 'EXECUTE') THEN
        v_bad := v_bad + 1;
      END IF;
    END LOOP;
    IF v_bad <> 0 THEN
      RAISE EXCEPTION 'D-POST-ACL: privilegios EXECUTE indebidos = % (PUBLIC/anon/authenticated/service_role). Abortando.', v_bad;
    END IF;
  END;

  -- ── POSTCHECK estructural: posiciones ejecutables estrictamente crecientes ──
  v_def := pg_get_functiondef('public.confirmar_reserva(jsonb)'::regprocedure);
  p_l10  := position('PERFORM pg_advisory_xact_lock(10, 0)' in v_def);
  p_l1   := position('PERFORM pg_advisory_xact_lock(1,'     in v_def);
  p_disp := position('validar_disponibilidad('              in v_def);
  p_gap  := position('public.validar_gap_bordes_congelados(' in v_def);
  p_ins  := position('INSERT INTO reservas'                 in v_def);
  IF NOT (p_l10 > 0 AND p_l10 < p_l1 AND p_l1 < p_disp AND p_disp < p_gap AND p_gap < p_ins) THEN
    RAISE EXCEPTION 'D-POST: orden estructural incorrecto (lock10=%, lock1=%, disp=%, gap=%, ins=%). Abortando.',
      p_l10, p_l1, p_disp, p_gap, p_ins;
  END IF;

  RAISE NOTICE 'D aplicado. ACL owner-only OK. Orden OK: lock(10,0)=% < lock(1,..)=% < validar_disponibilidad=% < gap=% < INSERT=%',
    p_l10, p_l1, p_disp, p_gap, p_ins;
  RAISE NOTICE 'confirmar_reserva fingerprint nuevo (local) = %', md5(v_def);
END $d$;

COMMIT;

-- Fingerprint nuevo para anotar como baseline post-D.
SELECT md5(pg_get_functiondef('public.confirmar_reserva(jsonb)'::regprocedure)) AS confirmar_reserva_fp_post_d;
