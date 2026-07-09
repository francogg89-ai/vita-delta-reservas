-- =====================================================================
-- B1.3-C - PATCH de crear_prereserva(jsonb): cablea validar_gap_bordes_congelados
-- =====================================================================
-- Inserta el gate de gap de turno (Modelo alfa) DESPUES de validar_disponibilidad
-- y del calculo de horas finales, ANTES del INSERT en pre_reservas. Excl NULL/NULL
-- (la candidata aun no existe): aplica a TODOS los canales.
--
-- Tecnica: patch DINAMICO sobre la definicion viva (pg_get_functiondef), inmune a
-- divergencia entre .sql y el estado desplegado. El validador se inserta como un
-- sub-bloque con DECLARE local (no toca el DECLARE global). La recreacion usa
-- DROP + CREATE (no CREATE OR REPLACE: evita la inyeccion espuria de RLS observada
-- en Supabase) y RE-APLICA el REVOKE owner-only, porque un DROP deja proacl=NULL
-- (=> PUBLIC ejecutaria, regresion que el hardening del motor corrige).
--
-- Gates fail-closed (abortan sin tocar nada):
--   * ambiente == 'test' (antes de cualquier DROP).
--   * crear_prereserva == fingerprint baseline exacto (d92a438e...).
--   * validar_gap_bordes_congelados presente == fingerprint exacto (5c5ef50e...).
--   * anchor unico, sin cablear previamente, sin marcador [B1.3-C].
-- Postchecks: ACL owner-only (sin EXECUTE a PUBLIC/anon/authenticated/service_role)
--   y orden estructural lock(10,0) < lock(1,..) < validar_disponibilidad < gap < INSERT.
--
-- NO toca confirmar_reserva. Reversible por B1_3_C_ROLLBACK_TEST.sql.
-- Ejecutar el script ENTERO en el SQL Editor.
-- =====================================================================

BEGIN;

DO $c$
DECLARE
  c_fp_base  CONSTANT text := 'd92a438eb4f11decac981cc65f2a5e53';  -- crear_prereserva baseline (TEST/PG17)
  c_fp_valid CONSTANT text := '5c5ef50eff10db716d17305dcbd54669';  -- validar_gap_bordes_congelados (TEST/PG17)
  c_anchor   CONSTANT text := '  v_expira_en := NOW() + (v_expiracion_minutos || '' minutes'')::INTERVAL;';
  v_fp_act   text;
  v_fp_val   text;
  v_def      text;
  v_new      text;
  v_create   text;
  v_bloque   text;
  v_ocurr    int;
  p_l10 int; p_l1 int; p_disp int; p_gap int; p_ins int;
  v_amb text;
BEGIN
  -- Lock global (mismo orden que el motor).
  PERFORM pg_advisory_xact_lock(10, 0);

  -- ── GATE 0: ambiente test (fail-closed ANTES de cualquier DROP) ──
  v_amb := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  IF COALESCE(v_amb, '') <> 'test' THEN
    RAISE EXCEPTION 'C-GATE: ambiente=% (esperado test). Abortando.', COALESCE(v_amb, '<null>');
  END IF;

  -- ── GATE 1: fingerprint exacto del baseline ──
  IF to_regprocedure('public.crear_prereserva(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'C-GATE: crear_prereserva(jsonb) no existe. Abortando.';
  END IF;
  v_fp_act := md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure));
  IF v_fp_act <> c_fp_base THEN
    RAISE EXCEPTION 'C-GATE: fingerprint de crear_prereserva = % (esperado baseline %). Abortando.', v_fp_act, c_fp_base;
  END IF;

  -- ── GATE 2: validador gap presente con fingerprint exacto ──
  IF to_regprocedure('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)') IS NULL THEN
    RAISE EXCEPTION 'C-GATE: validar_gap_bordes_congelados ausente (B no aplicado). Abortando.';
  END IF;
  v_fp_val := md5(pg_get_functiondef('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)'::regprocedure));
  IF v_fp_val <> c_fp_valid THEN
    RAISE EXCEPTION 'C-GATE: fingerprint del validador gap = % (esperado %). Abortando.', v_fp_val, c_fp_valid;
  END IF;

  -- ── Leer definicion viva ──
  v_def := pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure);

  -- ── Verificaciones de patcheo (fail-closed) ──
  IF position('validar_gap_bordes_congelados' in v_def) > 0 THEN
    RAISE EXCEPTION 'C-PATCH: crear_prereserva ya referencia el validador gap (idempotencia). Abortando.';
  END IF;
  IF position('[B1.3-C' in v_def) > 0 THEN
    RAISE EXCEPTION 'C-PATCH: marcador [B1.3-C] ya presente. Abortando.';
  END IF;
  v_ocurr := (length(v_def) - length(replace(v_def, c_anchor, ''))) / NULLIF(length(c_anchor), 0);
  IF v_ocurr <> 1 THEN
    RAISE EXCEPTION 'C-PATCH: el anchor aparece % vez/veces (esperado 1). Abortando.', v_ocurr;
  END IF;

  -- ── Bloque a insertar: sub-bloque con DECLARE local (no toca el DECLARE global) ──
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

  -- ── Insertar el bloque ANTES del anchor ──
  v_new := replace(v_def, c_anchor, v_bloque || c_anchor);

  -- ── DROP + CREATE (evita bug RLS de CREATE OR REPLACE en Supabase) ──
  v_create := replace(v_new, 'CREATE OR REPLACE FUNCTION public.crear_prereserva',
                             'CREATE FUNCTION public.crear_prereserva');
  EXECUTE 'DROP FUNCTION public.crear_prereserva(jsonb)';
  EXECUTE v_create;

  -- ── Re-aplicar hardening owner-only (DROP dejo proacl=NULL => PUBLIC ejecuta) ──
  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.crear_prereserva(jsonb) FROM PUBLIC, anon, authenticated, service_role';

  -- ── POSTCHECK ACL: owner-only (sin EXECUTE indebido) ──
  DECLARE
    r text; v_bad int := 0;
  BEGIN
    FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
      IF has_function_privilege(r, 'public.crear_prereserva(jsonb)', 'EXECUTE') THEN
        v_bad := v_bad + 1;
      END IF;
    END LOOP;
    IF v_bad <> 0 THEN
      RAISE EXCEPTION 'C-POST-ACL: privilegios EXECUTE indebidos = % (PUBLIC/anon/authenticated/service_role). Abortando.', v_bad;
    END IF;
  END;

  -- ── POSTCHECK estructural: posiciones ejecutables estrictamente crecientes ──
  v_def := pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure);
  p_l10  := position('PERFORM pg_advisory_xact_lock(10, 0)' in v_def);
  p_l1   := position('PERFORM pg_advisory_xact_lock(1,'     in v_def);
  p_disp := position('validar_disponibilidad('              in v_def);
  p_gap  := position('public.validar_gap_bordes_congelados(' in v_def);
  p_ins  := position('INSERT INTO pre_reservas'             in v_def);
  IF NOT (p_l10 > 0 AND p_l10 < p_l1 AND p_l1 < p_disp AND p_disp < p_gap AND p_gap < p_ins) THEN
    RAISE EXCEPTION 'C-POST: orden estructural incorrecto (lock10=%, lock1=%, disp=%, gap=%, ins=%). Abortando.',
      p_l10, p_l1, p_disp, p_gap, p_ins;
  END IF;

  RAISE NOTICE 'C aplicado. ACL owner-only OK. Orden OK: lock(10,0)=% < lock(1,..)=% < validar_disponibilidad=% < gap=% < INSERT=%',
    p_l10, p_l1, p_disp, p_gap, p_ins;
  RAISE NOTICE 'crear_prereserva fingerprint nuevo (local) = %', md5(v_def);
END $c$;

COMMIT;

-- Fingerprint nuevo para anotar como baseline post-C.
SELECT md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure)) AS crear_prereserva_fp_post_c;
