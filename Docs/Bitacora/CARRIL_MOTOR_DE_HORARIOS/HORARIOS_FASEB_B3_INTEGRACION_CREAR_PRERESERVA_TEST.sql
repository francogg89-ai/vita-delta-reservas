-- =====================================================================
-- HORARIOS_FASEB_B3_INTEGRACION_CREAR_PRERESERVA_TEST.sql  (v3)
-- Fase B / Bloque 3 - Integracion de resolver_horario() en crear_prereserva.
-- ALCANCE: SOLO TEST (ref bdskhhbmcksskkzqkcdp). NO ejecutar en OPS.
-- Metodo: CREATE OR REPLACE (NO drop) - preserva ACL Bloque 23, COMMENT y
--   ownership (precedente B2). NO crea funciones nuevas (resolver ya existe).
--   Firma CALIFICADA public.crear_prereserva (v3): sin ambiguedad de search_path.
-- GATE ANTI-OPS DURO, dentro de BEGIN..COMMIT. Chequea (ejecutable):
--   (1) configuracion_general.ambiente = 'test';
--   (2) current_schema() = 'public';
--   (3) public.crear_prereserva(jsonb) existe;
--   (4) fingerprint baseline = f258ad9b6e4cd0f7dcb7318e5724f0ce.
--   Si cualquiera falla, RAISE aborta la tx => el CREATE OR REPLACE NO corre.
--   El CREATE en si es el de B2 + 4 deltas: si el gate pasa en TEST, corre igual.
-- Deltas: D1 DECLARE +v_res_in/+v_res_out; D2 bloque 3.5 (dos llamadas al
--   resolver, fail-closed, RETURN enriquecido borde+fecha_resolver, antes de
--   upsert_huesped); D3/D4 base check-in/out <- resolver (reemplazan las CASE);
--   D5 firma calificada public.
--   Bounds 22:00/07:00, guard fecha_in_pasada, locks, double-check idempotencia,
--   validar_disponibilidad, EXCLUDE, INSERTs y retorno exitoso: SIN cambios.
-- Ejecutar el script COMPLETO, con NADA seleccionado (L-8A-01).
-- =====================================================================

BEGIN;

-- ---- GATE ANTI-OPS (ambiente + schema + existencia + fingerprint) ----
DO $gate$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM configuracion_general
                 WHERE clave = 'ambiente' AND valor = 'test') THEN
    RAISE EXCEPTION 'ABORT B3: configuracion_general.ambiente <> ''test'' (o clave ausente). Aplicar SOLO en TEST.';
  END IF;
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'ABORT B3: current_schema() = % (esperado public).', current_schema();
  END IF;
  IF to_regprocedure('public.crear_prereserva(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'ABORT B3: public.crear_prereserva(jsonb) no existe en el schema public.';
  END IF;
  IF md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure))
       <> 'f258ad9b6e4cd0f7dcb7318e5724f0ce' THEN
    RAISE EXCEPTION 'ABORT B3: fingerprint baseline distinto de f258ad9b... El cuerpo vivo no es la base asumida; PARAR.';
  END IF;
END
$gate$;

-- ---- Integracion (CREATE OR REPLACE, cuerpo = base + deltas) ----
CREATE OR REPLACE FUNCTION public.crear_prereserva(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_huesped_payload      JSONB;
  v_id_consulta          BIGINT;
  v_id_cabana            BIGINT;
  v_fecha_in             DATE;
  v_fecha_out            DATE;
  v_personas             INTEGER;
  v_monto_total          NUMERIC(12,2);
  v_monto_sena           NUMERIC(12,2);
  v_canal_origen         TEXT;
  v_canal_pago_esperado  TEXT;
  v_source_event         TEXT;
  v_idempotency_key      TEXT;
  v_notas                TEXT;
  v_mascotas             BOOLEAN;
  v_detalle_mascotas     TEXT;
  v_ninos                TEXT;
  v_notas_reserva        TEXT;
  v_hora_checkin_sol     TIME;
  v_hora_checkout_sol    TIME;
  v_hora_checkin_final   TIME;
  v_hora_checkout_final  TIME;
  v_hora_checkin_min     TIME;
  v_hora_checkin_max     TIME;
  v_hora_checkout_min    TIME;
  v_hora_checkout_max    TIME;
  v_expiracion_minutos   INTEGER;
  v_expira_en            TIMESTAMPTZ;
  v_estado_inicial       estado_prereserva_enum;
  v_id_huesped           BIGINT;
  v_id_pre_reserva       BIGINT;
  v_config               JSONB;
  v_claves_faltantes     TEXT[];
  v_cabana               cabanas%ROWTYPE;
  v_disponibilidad       JSONB;
  v_existente            pre_reservas%ROWTYPE;
  v_upsert_result        JSONB;
  v_res_in               JSONB;
  v_res_out              JSONB;
BEGIN
  -- ─── 1. Extraer payload y validar ──────────────────────
  -- (v1.7.2) Extract defensivo unificado: todos los campos derivados de
  -- payload->>'...' pasan por NULLIF(TRIM(...),'') antes del cast. Excepción:
  -- v_huesped_payload usa payload->'huesped' (operador JSONB, no texto), no
  -- aplica patrón. La normalización interna del huésped vive en upsert_huesped().
  v_huesped_payload     := payload->'huesped';
  v_id_consulta         := NULLIF(TRIM(payload->>'id_consulta'), '')::BIGINT;
  v_id_cabana           := NULLIF(TRIM(payload->>'id_cabana'), '')::BIGINT;
  v_fecha_in            := NULLIF(TRIM(payload->>'fecha_in'), '')::DATE;
  v_fecha_out           := NULLIF(TRIM(payload->>'fecha_out'), '')::DATE;
  v_personas            := NULLIF(TRIM(payload->>'personas'), '')::INTEGER;
  v_monto_total         := NULLIF(TRIM(payload->>'monto_total'), '')::NUMERIC(12,2);
  v_monto_sena          := NULLIF(TRIM(payload->>'monto_sena'), '')::NUMERIC(12,2);
  v_canal_origen        := NULLIF(TRIM(payload->>'canal_origen'), '');
  v_canal_pago_esperado := NULLIF(TRIM(payload->>'canal_pago_esperado'), '');
  v_source_event        := NULLIF(TRIM(payload->>'source_event'), '');
  v_idempotency_key     := NULLIF(TRIM(payload->>'idempotency_key'), '');
  v_notas               := NULLIF(TRIM(payload->>'notas'), '');
  v_mascotas            := COALESCE(NULLIF(TRIM(payload->>'mascotas'), '')::BOOLEAN, FALSE);
  v_detalle_mascotas    := NULLIF(TRIM(payload->>'detalle_mascotas'), '');
  v_ninos               := NULLIF(TRIM(payload->>'ninos'), '');
  v_notas_reserva       := NULLIF(TRIM(payload->>'notas_reserva'), '');
  v_hora_checkin_sol    := NULLIF(TRIM(payload->>'hora_checkin_solicitada'), '')::TIME;
  v_hora_checkout_sol   := NULLIF(TRIM(payload->>'hora_checkout_solicitada'), '')::TIME;

  IF v_id_cabana IS NULL OR v_fecha_in IS NULL OR v_fecha_out IS NULL
     OR v_personas IS NULL OR v_canal_origen IS NULL OR v_source_event IS NULL
     OR v_canal_pago_esperado IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  IF v_monto_total IS NULL OR v_monto_sena IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'precio_requerido',
                              'motivo', 'monto_total y monto_sena son obligatorios');
  END IF;

  IF v_fecha_out <= v_fecha_in THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas');
  END IF;

  -- Guard temporal (Bloque 2 / motor de horarios): rechazar fecha_in pasada
  -- en zona horaria Argentina. fecha_in = hoy_ar permitido (comparador '<').
  IF v_fecha_in < fecha_hoy_ar() THEN
    RETURN jsonb_build_object(
      'ok', false, 'error', 'fecha_in_pasada',
      'campo', 'fecha_in', 'minimo', fecha_hoy_ar(), 'recibido', v_fecha_in
    );
  END IF;

  IF v_huesped_payload IS NULL OR NULLIF(TRIM(v_huesped_payload->>'nombre'), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_nombre_requerido',
                              'motivo', 'El payload del huésped debe traer un nombre no vacío.');
  END IF;

  IF NULLIF(v_huesped_payload->>'telefono', '') IS NULL
     AND NULLIF(v_huesped_payload->>'email', '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_contacto_requerido',
                              'motivo', 'El payload del huésped debe traer al menos telefono o email.');
  END IF;

  -- ─── 1.bis Setear contexto para triggers de log ──
  PERFORM set_config('app.modificado_por', 'crear_prereserva', true);
  PERFORM set_config('app.source_event',   v_source_event,    true);

  -- ─── 2. Leer configuración relevante ───────────────────
  SELECT jsonb_object_agg(clave, valor)
  INTO v_config
  FROM configuracion_general
  WHERE clave IN (
    'hora_checkin_default', 'hora_checkin_domingo',
    'hora_checkin_max_cliente', 'hora_checkout_min_cliente',
    'hora_checkout_default', 'hora_checkout_domingo',
    'prereserva_expiracion_minutos'
  );

  v_expiracion_minutos := COALESCE((v_config->>'prereserva_expiracion_minutos')::INTEGER, 60);

  v_claves_faltantes := ARRAY[]::TEXT[];
  IF v_config->>'hora_checkin_default'         IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_default'); END IF;
  IF v_config->>'hora_checkin_domingo'         IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_domingo'); END IF;
  IF v_config->>'hora_checkin_max_cliente'     IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_max_cliente'); END IF;
  IF v_config->>'hora_checkout_min_cliente'    IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_min_cliente'); END IF;
  IF v_config->>'hora_checkout_default'        IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_default'); END IF;
  IF v_config->>'hora_checkout_domingo'        IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_domingo'); END IF;
  IF v_config->>'prereserva_expiracion_minutos' IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'prereserva_expiracion_minutos'); END IF;

  -- ─── 3. Pre-check idempotencia ──
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existente
    FROM pre_reservas
    WHERE idempotency_key = v_idempotency_key
      AND estado IN ('pendiente_pago', 'pago_en_revision')
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'ok',               true,
        'idempotent_match', true,
        'id_pre_reserva',   v_existente.id_pre_reserva,
        'id_huesped',       v_existente.id_huesped,
        'estado',           v_existente.estado::TEXT,
        'expira_en',        v_existente.expira_en,
        'recovery_path',    'pre_lock'
      );
    END IF;
  END IF;

  -- ─── 3.5 Resolver horario base (motor formal de horarios) ──
  -- Cablea resolver_horario() como fuente de la base check-in/check-out.
  -- Se ejecuta DESPUES del pre-check de idempotencia y ANTES de
  -- upsert_huesped: un override invalido (HARD) rebota como rechazo puro
  -- sin consumir id_huesped ni id_pre_reserva (secuencias no-transaccionales).
  -- fail-closed ante ok ausente (NULL => false). Por contrato el resolver
  -- siempre devuelve ok booleano; un ok fuera de contrato (no booleano)
  -- haria fallar el cast ::BOOLEAN, no un rebote silencioso. El error se
  -- enriquece con borde (que fecha disparo) y fecha_resolver: las 8 claves.
  v_res_in := resolver_horario(v_id_cabana, v_fecha_in);
  IF COALESCE((v_res_in->>'ok')::BOOLEAN, false) IS NOT TRUE THEN
    RETURN v_res_in || jsonb_build_object('borde', 'fecha_in', 'fecha_resolver', v_fecha_in);
  END IF;

  v_res_out := resolver_horario(v_id_cabana, v_fecha_out);
  IF COALESCE((v_res_out->>'ok')::BOOLEAN, false) IS NOT TRUE THEN
    RETURN v_res_out || jsonb_build_object('borde', 'fecha_out', 'fecha_resolver', v_fecha_out);
  END IF;

  -- ─── 4. Resolver huésped ──────
  v_upsert_result := upsert_huesped(v_huesped_payload);
  IF NOT (v_upsert_result->>'ok')::BOOLEAN THEN
    RETURN v_upsert_result;
  END IF;
  v_id_huesped := (v_upsert_result->>'id_huesped')::BIGINT;

  -- ─── 5. Locks ──
  PERFORM pg_advisory_xact_lock(10, 0);
  PERFORM pg_advisory_xact_lock(1, v_id_cabana::INTEGER);

  -- ─── 5.bis Double-check idempotencia ──
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existente
    FROM pre_reservas
    WHERE idempotency_key = v_idempotency_key
      AND estado IN ('pendiente_pago', 'pago_en_revision')
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'ok',               true,
        'idempotent_match', true,
        'id_pre_reserva',   v_existente.id_pre_reserva,
        'id_huesped',       v_existente.id_huesped,
        'estado',           v_existente.estado::TEXT,
        'expira_en',        v_existente.expira_en,
        'recovery_path',    'post_lock'
      );
    END IF;
  END IF;

  -- ─── 6. Validar cabaña ──
  SELECT * INTO v_cabana FROM cabanas WHERE id_cabana = v_id_cabana;
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

  -- ─── 7. Validar disponibilidad ──
  v_disponibilidad := validar_disponibilidad(v_id_cabana, v_fecha_in, v_fecha_out, NULL);

  IF NOT (v_disponibilidad->>'ok')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', v_disponibilidad->>'error');
  END IF;

  IF NOT (v_disponibilidad->>'disponible')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_disponible',
                              'conflictos', v_disponibilidad->'conflictos');
  END IF;

  -- ─── 8. Calcular horarios finales (v1.7) ──
  v_hora_checkin_min := (v_res_in->>'hora_checkin')::TIME;
  v_hora_checkin_max := COALESCE((v_config->>'hora_checkin_max_cliente')::TIME, TIME '22:00');

  v_hora_checkout_min := COALESCE((v_config->>'hora_checkout_min_cliente')::TIME, TIME '07:00');

  v_hora_checkout_max := (v_res_out->>'hora_checkout')::TIME;

  IF v_hora_checkin_sol IS NULL THEN
    v_hora_checkin_final := v_hora_checkin_min;
  ELSE
    IF v_hora_checkin_sol < v_hora_checkin_min OR v_hora_checkin_sol > v_hora_checkin_max THEN
      RETURN jsonb_build_object(
        'ok', false, 'error', 'hora_fuera_de_rango',
        'campo', 'hora_checkin',
        'minimo', v_hora_checkin_min, 'maximo', v_hora_checkin_max
      );
    END IF;
    v_hora_checkin_final := v_hora_checkin_sol;
  END IF;

  IF v_hora_checkout_sol IS NULL THEN
    v_hora_checkout_final := v_hora_checkout_max;
  ELSE
    IF v_hora_checkout_sol < v_hora_checkout_min OR v_hora_checkout_sol > v_hora_checkout_max THEN
      RETURN jsonb_build_object(
        'ok', false, 'error', 'hora_fuera_de_rango',
        'campo', 'hora_checkout',
        'minimo', v_hora_checkout_min, 'maximo', v_hora_checkout_max
      );
    END IF;
    v_hora_checkout_final := v_hora_checkout_sol;
  END IF;

  v_expira_en := NOW() + (v_expiracion_minutos || ' minutes')::INTERVAL;
  v_estado_inicial := 'pendiente_pago';

  -- ─── 9. INSERT con manejo defensivo ──
  BEGIN
    INSERT INTO pre_reservas (
      id_consulta, id_cabana, id_huesped,
      fecha_in, fecha_out, hora_checkin, hora_checkout,
      personas, monto_total, monto_sena, estado, expira_en,
      canal_pago_esperado, canal_origen, intentos_pago,
      notas, source_event,
      mascotas, detalle_mascotas, ninos, notas_reserva,
      idempotency_key
    ) VALUES (
      v_id_consulta, v_id_cabana, v_id_huesped,
      v_fecha_in, v_fecha_out, v_hora_checkin_final, v_hora_checkout_final,
      v_personas, v_monto_total, v_monto_sena, v_estado_inicial, v_expira_en,
      v_canal_pago_esperado, v_canal_origen, 0,
      v_notas, v_source_event,
      v_mascotas, v_detalle_mascotas, v_ninos, v_notas_reserva,
      v_idempotency_key
    )
    RETURNING id_pre_reserva INTO v_id_pre_reserva;

  EXCEPTION
    WHEN unique_violation THEN
      IF v_idempotency_key IS NOT NULL THEN
        SELECT * INTO v_existente
        FROM pre_reservas
        WHERE idempotency_key = v_idempotency_key
          AND estado IN ('pendiente_pago', 'pago_en_revision')
        LIMIT 1;

        IF FOUND THEN
          RETURN jsonb_build_object(
            'ok',               true,
            'idempotent_match', true,
            'id_pre_reserva',   v_existente.id_pre_reserva,
            'id_huesped',       v_existente.id_huesped,
            'estado',           v_existente.estado::TEXT,
            'expira_en',        v_existente.expira_en,
            'recovery_path',    'unique_violation'
          );
        END IF;
      END IF;

      RETURN jsonb_build_object('ok', false, 'error', 'unique_violation_inesperado');
  END;

  -- ─── 10. Log de creación ──
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'pre_reservas',
    v_id_pre_reserva::TEXT,
    'crear_prereserva',
    v_source_event,
    'info',
    jsonb_build_object(
      'evento',       'prereserva_creada',
      'id_cabana',    v_id_cabana,
      'id_huesped',   v_id_huesped,
      'fecha_in',     v_fecha_in,
      'fecha_out',    v_fecha_out,
      'monto_total',  v_monto_total,
      'monto_sena',   v_monto_sena,
      'canal_origen', v_canal_origen
    )
  );

  -- ─── 11. Warning de config faltante ──
  IF cardinality(v_claves_faltantes) > 0 THEN
    INSERT INTO log_cambios (
      tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
    ) VALUES (
      'configuracion_general',
      'sistema',
      'crear_prereserva',
      v_source_event,
      'warning',
      jsonb_build_object(
        'evento',           'claves_config_faltantes',
        'claves_faltantes', v_claves_faltantes,
        'motivo',           'crear_prereserva usó valores default para estas claves'
      )
    );
  END IF;

  -- ─── 12. Retorno exitoso ──
  RETURN jsonb_build_object(
    'ok',               true,
    'idempotent_match', false,
    'id_pre_reserva',   v_id_pre_reserva,
    'id_huesped',       v_id_huesped,
    'estado',           v_estado_inicial::TEXT,
    'expira_en',        v_expira_en,
    'hora_checkin',     v_hora_checkin_final,
    'hora_checkout',    v_hora_checkout_final,
    'recovery_path',    NULL
  );
END;
$$;

COMMIT;
