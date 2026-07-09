-- =====================================================================
-- B1.3-E - crear_reserva_con_horario_pactado(jsonb)  [FUNCION NUEVA]
-- =====================================================================
-- Reserva ADMINISTRATIVA Modelo alfa: crea una reserva confirmada directa con horas
-- pactadas (congeladas), sin pre-reserva y sin pago. Es SOLO para horario pactado:
-- exige al menos un borde pactado (hora_checkin_pactada o hora_checkout_pactada). El
-- borde que no venga pactado se resuelve con resolver_horario. Valida ventana fisica
-- [07:00,22:00], fecha no pasada, disponibilidad y gap de turno. Acepta y persiste
-- campos operativos opcionales (notas, mascotas, detalle_mascotas, ninos, notas_reserva,
-- created_by, encargado_semana). Actualiza el huesped igual que confirmar_reserva.
-- source_event: si no viene se fija interno; si viene distinto, falla. El motivo tecnico
-- es CONSTANTE y va SOLO a log_cambios.detalle (nunca a reservas.notas_reserva; ahi solo
-- va la nota operativa del payload). No calcula tarifa, no registra pago, no implementa
-- idempotencia, no crea overrides. Errores de validacion alineados con crear_prereserva.
--
-- Instalacion fail-closed (transaccional; si algo falla, ROLLBACK total):
--   GATE 0  ambiente == 'test'.
--   GATE 1  validar_gap_bordes_congelados presente == fingerprint (5c5ef50e...).
--   GATE 2  resolver_horario (wrapper) presente == fingerprint (1bd96c89...).
--   GATE 3  _resolver_horario (interno semanal) presente == fingerprint (7e5bfa21...).
--   GATE 4  la funcion NO existe aun (no re-instalar por encima; usar rollback primero).
-- Creacion con CREATE (no CREATE OR REPLACE) + REVOKE owner-only + postcheck ACL.
-- NO toca crear_prereserva ni confirmar_reserva. Reversible por B1_3_E_ROLLBACK_TEST.sql.
-- Ejecutar el script ENTERO en el SQL Editor.
-- =====================================================================

BEGIN;

DO $gate$
DECLARE
  c_fp_valid CONSTANT text := '5c5ef50eff10db716d17305dcbd54669';  -- validar_gap_bordes_congelados
  c_fp_wrap  CONSTANT text := '1bd96c89e587b15582fd7b2e29ae7e18';  -- resolver_horario (wrapper)
  c_fp_int   CONSTANT text := '7e5bfa21b39d90b674c1a83d76b71b1d';  -- _resolver_horario (interno semanal)
  v_amb text;
BEGIN
  PERFORM pg_advisory_xact_lock(10, 0);

  v_amb := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  IF COALESCE(v_amb, '') <> 'test' THEN
    RAISE EXCEPTION 'E-GATE: ambiente=% (esperado test). Abortando.', COALESCE(v_amb, '<null>');
  END IF;

  IF to_regprocedure('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)') IS NULL THEN
    RAISE EXCEPTION 'E-GATE: validar_gap_bordes_congelados ausente (B no aplicado). Abortando.';
  END IF;
  IF md5(pg_get_functiondef('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)'::regprocedure)) <> c_fp_valid THEN
    RAISE EXCEPTION 'E-GATE: fingerprint del validador gap distinto del esperado. Abortando.';
  END IF;

  IF to_regprocedure('public.resolver_horario(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'E-GATE: resolver_horario (wrapper) ausente. Abortando.';
  END IF;
  IF md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure)) <> c_fp_wrap THEN
    RAISE EXCEPTION 'E-GATE: fingerprint del wrapper resolver_horario distinto del esperado (post-A). Abortando.';
  END IF;

  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NULL THEN
    RAISE EXCEPTION 'E-GATE: _resolver_horario (interno) ausente. Abortando.';
  END IF;
  IF md5(pg_get_functiondef('public._resolver_horario(bigint,date,boolean)'::regprocedure)) <> c_fp_int THEN
    RAISE EXCEPTION 'E-GATE: fingerprint del interno _resolver_horario distinto del esperado (post-A). Abortando.';
  END IF;

  IF to_regprocedure('public.crear_reserva_con_horario_pactado(jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'E-GATE: crear_reserva_con_horario_pactado ya existe. Usar rollback antes de reinstalar. Abortando.';
  END IF;
END $gate$;

CREATE FUNCTION public.crear_reserva_con_horario_pactado(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $fn$
DECLARE
  c_source_event  CONSTANT text := 'reserva_manual_horario_pactado';
  c_motivo        CONSTANT text := 'Horario especial pactado al crear reserva manual';
  c_vent_min      CONSTANT time := TIME '07:00';
  c_vent_max      CONSTANT time := TIME '22:00';
  v_id_cabana     bigint;
  v_fecha_in      date;
  v_fecha_out     date;
  v_personas      integer;
  v_monto_total   numeric(12,2);
  v_monto_sena    numeric(12,2);
  v_source_event  text;
  v_huesped       jsonb;
  v_hci_pactada   text;
  v_hco_pactada   text;
  v_hora_checkin  time;
  v_hora_checkout time;
  v_cabana        public.cabanas%ROWTYPE;
  -- campos operativos opcionales
  v_notas            text;
  v_mascotas         boolean;
  v_detalle_mascotas text;
  v_ninos            text;
  v_notas_reserva    text;
  v_created_by       text;
  v_encargado_semana text;
  v_res_h         jsonb;
  v_upsert        jsonb;
  v_id_huesped    bigint;
  v_disp          jsonb;
  v_gap           jsonb;
  v_id_reserva    bigint;
BEGIN
  -- ── 1. Extraer payload ──
  v_id_cabana    := (payload->>'id_cabana')::bigint;
  v_fecha_in     := (payload->>'fecha_in')::date;
  v_fecha_out    := (payload->>'fecha_out')::date;
  v_personas     := (payload->>'personas')::integer;
  v_monto_total  := (payload->>'monto_total')::numeric(12,2);
  v_monto_sena   := COALESCE((payload->>'monto_sena')::numeric(12,2), 0);
  v_source_event := COALESCE(payload->>'source_event', c_source_event);  -- si no viene, interno
  v_huesped      := payload->'huesped';
  v_hci_pactada  := payload->>'hora_checkin_pactada';
  v_hco_pactada  := payload->>'hora_checkout_pactada';
  -- operativos (opcionales)
  v_notas            := payload->>'notas';
  v_mascotas         := COALESCE((payload->>'mascotas')::boolean, false);
  v_detalle_mascotas := payload->>'detalle_mascotas';
  v_ninos            := payload->>'ninos';
  v_notas_reserva    := payload->>'notas_reserva';   -- nota operativa; NUNCA el motivo tecnico
  v_created_by       := payload->>'created_by';
  v_encargado_semana := payload->>'encargado_semana';

  -- ── 2. Validaciones de payload (errores parseables, alineados con crear_prereserva) ──
  IF v_id_cabana IS NULL OR v_fecha_in IS NULL OR v_fecha_out IS NULL OR v_personas IS NULL
     OR v_monto_total IS NULL OR v_huesped IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_incompleto');
  END IF;

  -- source_event: ausente => interno; presente y distinto => invalido.
  IF v_source_event <> c_source_event THEN
    RETURN jsonb_build_object('ok', false, 'error', 'source_event_invalido',
                              'esperado', c_source_event, 'recibido', v_source_event);
  END IF;

  -- Funcion SOLO para horario pactado: exige al menos un borde pactado.
  IF v_hci_pactada IS NULL AND v_hco_pactada IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'horario_pactado_requerido');
  END IF;

  IF v_fecha_out <= v_fecha_in THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas');
  END IF;

  -- Guard temporal: rechazar fecha_in pasada (mismo criterio que crear_prereserva).
  IF v_fecha_in < fecha_hoy_ar() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fecha_in_pasada',
                              'campo', 'fecha_in', 'minimo', fecha_hoy_ar(), 'recibido', v_fecha_in);
  END IF;

  IF v_personas < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'personas_invalidas');
  END IF;
  IF v_monto_total <= 0 OR v_monto_sena < 0 OR v_monto_sena > v_monto_total THEN
    RETURN jsonb_build_object('ok', false, 'error', 'montos_invalidos');
  END IF;

  -- Huesped: nombre y contacto minimo (mismos errores que crear_prereserva).
  IF v_huesped IS NULL OR NULLIF(TRIM(v_huesped->>'nombre'), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_nombre_requerido',
                              'motivo', 'El payload del huésped debe traer un nombre no vacío.');
  END IF;
  IF NULLIF(v_huesped->>'telefono', '') IS NULL AND NULLIF(v_huesped->>'email', '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_contacto_requerido',
                              'motivo', 'El payload del huésped debe traer al menos telefono o email.');
  END IF;

  -- Cabaña existente / activa / capacidad (mismos errores que crear_prereserva).
  SELECT * INTO v_cabana FROM public.cabanas WHERE id_cabana = v_id_cabana;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_existe');
  END IF;
  IF NOT v_cabana.activa THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_inactiva');
  END IF;
  IF v_personas > v_cabana.capacidad_max THEN
    RETURN jsonb_build_object('ok', false, 'error', 'excede_capacidad',
                              'capacidad_max', v_cabana.capacidad_max);
  END IF;

  -- Contexto de auditoria (patron del sistema).
  PERFORM set_config('app.modificado_por', 'crear_reserva_con_horario_pactado', true);
  PERFORM set_config('app.source_event',   c_source_event,                       true);

  -- ── 3. Locks: global y luego por cabaña ──
  PERFORM pg_advisory_xact_lock(10, 0);
  PERFORM pg_advisory_xact_lock(1, v_id_cabana::INTEGER);

  -- ── 4. Resolver horas: pactadas si vienen, sino con resolver_horario ──
  IF v_hci_pactada IS NOT NULL THEN
    v_hora_checkin := v_hci_pactada::time;
  ELSE
    v_res_h := public.resolver_horario(v_id_cabana, v_fecha_in);
    IF NOT COALESCE((v_res_h->>'ok')::boolean, false) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'horario_no_resoluble', 'borde', 'checkin');
    END IF;
    v_hora_checkin := (v_res_h->>'hora_checkin')::time;
  END IF;

  IF v_hco_pactada IS NOT NULL THEN
    v_hora_checkout := v_hco_pactada::time;
  ELSE
    v_res_h := public.resolver_horario(v_id_cabana, v_fecha_out);
    IF NOT COALESCE((v_res_h->>'ok')::boolean, false) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'horario_no_resoluble', 'borde', 'checkout');
    END IF;
    v_hora_checkout := (v_res_h->>'hora_checkout')::time;
  END IF;

  -- ── 5. Ventana fisica [07:00, 22:00] (inclusive) ──
  IF v_hora_checkin < c_vent_min OR v_hora_checkin > c_vent_max
     OR v_hora_checkout < c_vent_min OR v_hora_checkout > c_vent_max THEN
    RETURN jsonb_build_object('ok', false, 'error', 'hora_fuera_de_ventana_fisica',
                              'ventana', jsonb_build_object('min', c_vent_min::text, 'max', c_vent_max::text),
                              'hora_checkin', v_hora_checkin::text, 'hora_checkout', v_hora_checkout::text);
  END IF;

  -- ── 6. Disponibilidad (sin exclusion: reserva nueva) ──
  v_disp := public.validar_disponibilidad(v_id_cabana, v_fecha_in, v_fecha_out, NULL);
  IF NOT COALESCE((v_disp->>'ok')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'disponibilidad_no_evaluable', 'detalle', v_disp);
  END IF;
  IF NOT COALESCE((v_disp->>'disponible')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_disponible', 'conflictos', v_disp->'conflictos');
  END IF;

  -- ── 7. Gap de turno (horas congeladas; sin exclusiones: reserva nueva) ──
  v_gap := public.validar_gap_bordes_congelados(
    v_id_cabana, v_fecha_in, v_hora_checkin, v_fecha_out, v_hora_checkout, NULL, NULL);
  IF NOT COALESCE((v_gap->>'ok')::boolean, false) THEN
    RETURN v_gap;
  END IF;

  -- ── 8. Huesped (upsert; retorno parseable) ──
  v_upsert := public.upsert_huesped(v_huesped);
  IF NOT COALESCE((v_upsert->>'ok')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_no_creado', 'detalle', v_upsert);
  END IF;
  v_id_huesped := (v_upsert->>'id_huesped')::bigint;

  -- ── 9. INSERT reserva confirmada directa (id_pre_reserva NULL, operativos, source_event fijo) ──
  --      Captura defensiva de exclusion_violation => no_disponible (como confirmar_reserva).
  BEGIN
    INSERT INTO reservas (
      id_pre_reserva, id_cabana, id_huesped,
      fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
      personas, estado, canal_origen,
      monto_total, monto_sena, monto_saldo,
      encargado_semana, created_by, source_event,
      mascotas, detalle_mascotas, ninos, notas, notas_reserva
    ) VALUES (
      NULL, v_id_cabana, v_id_huesped,
      v_fecha_in, v_fecha_out, v_hora_checkin, v_hora_checkout,
      v_personas, 'confirmada', 'manual',
      v_monto_total, v_monto_sena, (v_monto_total - v_monto_sena),
      v_encargado_semana, v_created_by, c_source_event,
      v_mascotas, v_detalle_mascotas, v_ninos, v_notas, v_notas_reserva
    )
    RETURNING id_reserva INTO v_id_reserva;
  EXCEPTION
    WHEN exclusion_violation THEN
      RETURN jsonb_build_object('ok', false, 'error', 'no_disponible',
                                'motivo', 'EXCLUDE constraint detectó conflicto');
  END;

  -- ── 10. Actualizar huesped (mismo update que confirmar_reserva) ──
  UPDATE huespedes
  SET total_reservas        = total_reservas + 1,
      primera_reserva_fecha = COALESCE(primera_reserva_fecha, v_fecha_in),
      updated_at            = NOW()
  WHERE id_huesped = v_id_huesped;

  -- ── 11. Log con motivo CONSTANTE (solo en log_cambios.detalle) ──
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'reservas', v_id_reserva::text, 'crear_reserva_con_horario_pactado', c_source_event, 'info',
    jsonb_build_object(
      'evento',         'reserva_manual_horario_pactado',
      'id_reserva',     v_id_reserva,
      'id_huesped',     v_id_huesped,
      'id_cabana',      v_id_cabana,
      'fecha_checkin',  v_fecha_in,
      'fecha_checkout', v_fecha_out,
      'hora_checkin',   v_hora_checkin::text,
      'hora_checkout',  v_hora_checkout::text,
      'motivo',         c_motivo
    )
  );

  RETURN jsonb_build_object('ok', true, 'id_reserva', v_id_reserva, 'id_huesped', v_id_huesped);
END;
$fn$;

-- Hardening owner-only.
REVOKE EXECUTE ON FUNCTION public.crear_reserva_con_horario_pactado(jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- POSTCHECK ACL: owner-only.
DO $post$
DECLARE r text; v_bad int := 0;
BEGIN
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r, 'public.crear_reserva_con_horario_pactado(jsonb)', 'EXECUTE') THEN
      v_bad := v_bad + 1;
    END IF;
  END LOOP;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'E-POST-ACL: privilegios EXECUTE indebidos = %. Abortando.', v_bad;
  END IF;
  RAISE NOTICE 'E instalada. ACL owner-only OK.';
END $post$;

COMMIT;

SELECT md5(pg_get_functiondef('public.crear_reserva_con_horario_pactado(jsonb)'::regprocedure)) AS crear_reserva_pactada_fp;
