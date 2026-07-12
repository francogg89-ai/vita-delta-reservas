-- ============================================================================
-- B3 -- Motor de Precios v2 : Funciones del motor
-- ----------------------------------------------------------------------------
-- Naturaleza : funciones nuevas, TEST-only, gated, IDEMPOTENTE (DROP+CREATE).
-- NO toca    : estructura B2A/B2B, crear_prereserva, gateway/portal, OPS,
--              hardening legacy. No incluye B3.1 (override de capacidad)
--              ni precios_cotizar_disponibles.
-- Requisitos : B2A (fingerprint da52a16c045689523a5f1f113f513a87) + B2B.
--
-- DECISIONES CODIFICADAS:
--   D-PR-09  ordinal continuo a traves del borde de temporada
--   D-PR-10  noches de evento no cuentan ni reinician el ordinal
--   D-PR-17  UN solo override por noche (absoluto > porcentual > especificidad
--            > created_at DESC > id DESC). Sin apilamiento.
--   D-PR-18  extra persona sobre TODAS las noches (estandar + evento)
--   D-PR-19  sena redondeada al $1.000; saldo absorbe la diferencia
--   D-PR-20  evento activo sin paquete para el perfil -> derivar (online)
--
-- REGLAS TECNICAS:
--   * obtener_disponibilidad_rango(desde, hasta): `hasta` es EXCLUSIVE.
--     Se llama con (fecha_in, fecha_out) TAL CUAL. Nunca fecha_out - 1.
--   * paquetes_evento.fecha_in/fecha_out se interpreta como [fecha_in, fecha_out).
--   * Noche vendible <=> estado IN ('disponible','checkout_disponible').
--   * Cotizacion: SIN locks, SIN FOR UPDATE, SIN escrituras operativas.
--     Unico writer: precios_cotizar_congelar -> solo cotizaciones_precio.
--   * Dinero sale como STRING (invariante de dinero del proyecto).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- GATE ANTI-AMBIENTE (TEST-only)
-- ---------------------------------------------------------------------------
DO $gate$
DECLARE v_amb TEXT; v_esperado TEXT := 'test';
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS NULL THEN
    RAISE EXCEPTION 'B3 abortado: no existe configuracion_general(ambiente).';
  END IF;
  IF v_amb IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'B3 abortado: ambiente=% (esperado %). TEST-only.', v_amb, v_esperado;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind='r' AND relname='tarifas_motor') THEN
    RAISE EXCEPTION 'B3 abortado: B2A no aplicado.';
  END IF;
  IF (SELECT COUNT(*) FROM tarifas_motor WHERE vigente_hasta IS NULL) = 0 THEN
    RAISE EXCEPTION 'B3 abortado: B2B no aplicado (grilla vacia).';
  END IF;
END
$gate$;

-- ---------------------------------------------------------------------------
-- DROP previo (idempotencia; nunca CREATE OR REPLACE -- patron del proyecto)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS precios_cotizacion_obtener(UUID);
DROP FUNCTION IF EXISTS precios_cotizar_congelar(JSONB);
DROP FUNCTION IF EXISTS precios_cotizar(JSONB);
DROP FUNCTION IF EXISTS precios_disponibilidad_noches(BIGINT, DATE, DATE);
DROP FUNCTION IF EXISTS precios_extra_persona(TEXT, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS precios_eventos_interseccion(TEXT, DATE, DATE);
DROP FUNCTION IF EXISTS precios_precio_noche(TEXT, DATE, TEXT, TEXT);
DROP FUNCTION IF EXISTS precios_asignar_ordinales(DATE, DATE, DATE[]);
DROP FUNCTION IF EXISTS precios_clasificar_noche(DATE);
DROP FUNCTION IF EXISTS precios_resolver_temporada(DATE);
DROP FUNCTION IF EXISTS precios_money(NUMERIC);
DROP FUNCTION IF EXISTS precios_redondear(NUMERIC, NUMERIC);
DROP FUNCTION IF EXISTS precios_config(TEXT);

-- ===========================================================================
-- H0. precios_config -- lectura de configuracion de pricing
-- ===========================================================================
CREATE FUNCTION precios_config(p_clave TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT cg.valor FROM configuracion_general cg WHERE cg.clave = p_clave;
$$;

-- ===========================================================================
-- H1. precios_redondear -- redondeo al multiplo de base (D-PR-08)
-- ===========================================================================
CREATE FUNCTION precios_redondear(p_monto NUMERIC, p_base NUMERIC DEFAULT 1000)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ROUND(p_monto / p_base) * p_base;
$$;

-- ===========================================================================
-- H2. precios_money -- dinero como STRING entero (invariante de dinero)
-- ===========================================================================
CREATE FUNCTION precios_money(p_monto NUMERIC)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ROUND(COALESCE(p_monto, 0))::TEXT;
$$;

-- ===========================================================================
-- H3. precios_resolver_temporada -- NULL si no resuelve (-> temporada_no_resuelta)
-- ===========================================================================
CREATE FUNCTION precios_resolver_temporada(p_fecha DATE)
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT tv.temporada_clave
  FROM temporada_vigencia tv
  WHERE p_fecha >= tv.fecha_in AND p_fecha < tv.fecha_out_excl
  ORDER BY tv.fecha_in
  LIMIT 1;
$$;

-- ===========================================================================
-- H4. precios_clasificar_noche -- viernes(5)/sabado(6) o marca manual activa
-- ===========================================================================
CREATE FUNCTION precios_clasificar_noche(p_fecha DATE)
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
    WHEN EXTRACT(DOW FROM p_fecha) IN (5, 6) THEN 'alta_demanda'
    WHEN EXISTS (SELECT 1 FROM noches_alta_demanda n
                 WHERE n.fecha = p_fecha AND n.activo) THEN 'alta_demanda'
    ELSE 'semana'
  END;
$$;

-- ===========================================================================
-- H5. precios_asignar_ordinales -- EL CORAZON del motor (D-PR-09 / D-PR-10)
--   Dos contadores acumulados independientes (semana / alta_demanda).
--   Las noches de evento: tipo='evento', ordinal NULL, NO incrementan ningun
--   contador y NO lo reinician.
--   El contador NO se reinicia al cruzar el borde de temporada.
-- ===========================================================================
CREATE FUNCTION precios_asignar_ordinales(
  p_fecha_in DATE,
  p_fecha_out DATE,
  p_noches_evento DATE[] DEFAULT '{}'::DATE[]
)
RETURNS TABLE (fecha DATE, tipo TEXT, ordinal INTEGER, concepto TEXT)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_fecha      DATE;
  v_tipo       TEXT;
  v_cnt_semana INTEGER := 0;
  v_cnt_alta   INTEGER := 0;
BEGIN
  FOR v_fecha IN
    SELECT d::DATE FROM generate_series(p_fecha_in, p_fecha_out - 1, INTERVAL '1 day') d
  LOOP
    -- Noche de evento: fuera de ambos contadores, sin reiniciarlos (D-PR-10)
    IF v_fecha = ANY (p_noches_evento) THEN
      fecha := v_fecha; tipo := 'evento'; ordinal := NULL; concepto := NULL;
      RETURN NEXT;
      CONTINUE;
    END IF;

    v_tipo := precios_clasificar_noche(v_fecha);

    IF v_tipo = 'semana' THEN
      v_cnt_semana := v_cnt_semana + 1;
      ordinal  := v_cnt_semana;
      concepto := CASE WHEN v_cnt_semana >= 5 THEN 'semana_noche_5plus'
                       ELSE 'semana_noche_' || v_cnt_semana::TEXT END;
    ELSE
      v_cnt_alta := v_cnt_alta + 1;
      ordinal  := v_cnt_alta;
      concepto := CASE WHEN v_cnt_alta >= 3 THEN 'alta_demanda_noche_3plus'
                       ELSE 'alta_demanda_noche_' || v_cnt_alta::TEXT END;
    END IF;

    fecha := v_fecha; tipo := v_tipo;
    RETURN NEXT;
  END LOOP;
END
$$;

-- ===========================================================================
-- H6. precios_precio_noche -- grilla vigente -> UN override -> redondeo
--   Errores: temporada_no_resuelta | tarifa_incompleta  (nunca $0)
--   Precedencia de override (D-PR-17): absoluto > porcentual;
--   perfil explicito > NULL; tipo_noche explicito > 'todas';
--   created_at DESC; id DESC.  UNO SOLO. Sin apilamiento.
-- ===========================================================================
CREATE FUNCTION precios_precio_noche(
  p_perfil     TEXT,
  p_fecha      DATE,
  p_tipo_noche TEXT,
  p_concepto   TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_temp   TEXT;
  v_base   NUMERIC;
  v_precio NUMERIC;
  v_rbase  NUMERIC;
  v_ov_id     BIGINT;
  v_ov_tipo   TEXT;
  v_ov_valor  NUMERIC;
BEGIN
  v_temp := precios_resolver_temporada(p_fecha);
  IF v_temp IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'temporada_no_resuelta',
                              'fecha', p_fecha);
  END IF;

  SELECT t.precio INTO v_base
  FROM tarifas_motor t
  WHERE t.perfil = p_perfil
    AND t.temporada_clave = v_temp
    AND t.concepto = p_concepto
    AND t.vigente_hasta IS NULL;

  IF v_base IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'tarifa_incompleta',
                              'perfil', p_perfil, 'temporada', v_temp,
                              'concepto', p_concepto, 'fecha', p_fecha);
  END IF;

  -- UN solo override (D-PR-17)
  SELECT o.id, o.tipo, o.valor
    INTO v_ov_id, v_ov_tipo, v_ov_valor
  FROM overrides_precio o
  WHERE o.activo
    AND p_fecha >= o.fecha_in
    AND p_fecha <  o.fecha_out_excl
    AND (o.perfil = p_perfil OR o.perfil IS NULL)
    AND (o.tipo_noche = p_tipo_noche OR o.tipo_noche = 'todas')
  ORDER BY
    (o.tipo = 'absoluto')      DESC,   -- 1) absoluto gana a porcentual
    (o.perfil IS NOT NULL)     DESC,   -- 2) perfil explicito gana a NULL
    (o.tipo_noche <> 'todas')  DESC,   -- 3) tipo_noche explicito gana a 'todas'
    o.created_at               DESC,   -- 4) mas reciente
    o.id                       DESC    -- 5) id mayor
  LIMIT 1;

  IF v_ov_id IS NULL THEN
    v_precio := v_base;
  ELSIF v_ov_tipo = 'absoluto' THEN
    v_precio := v_ov_valor;
  ELSE
    v_precio := v_base * (1 + v_ov_valor / 100.0);
  END IF;

  v_rbase  := COALESCE(precios_config('precio_redondeo_base')::NUMERIC, 1000);
  v_precio := precios_redondear(v_precio, v_rbase);

  RETURN jsonb_build_object(
    'ok', true,
    'precio', v_precio,
    'base', v_base,
    'temporada', v_temp,
    'override_id', v_ov_id,
    'override_tipo', v_ov_tipo
  );
END
$$;

-- ===========================================================================
-- H7. precios_eventos_interseccion -- paquetes que intersectan la estadia
--   Regla: si un paquete intersecta, la estadia DEBE contenerlo completo.
--   Si no -> evento_parcial_no_vendible (no se aplica NINGUN paquete).
--   D-PR-20: evento activo que intersecta sin paquete valido para el perfil
--   -> flag evento_sin_paquete_perfil.
--   paquetes_evento.fecha_in/fecha_out = [fecha_in, fecha_out).
--   Paquetes con fechas NULL se IGNORAN (dato incompleto).
-- ===========================================================================
CREATE FUNCTION precios_eventos_interseccion(
  p_perfil    TEXT,
  p_fecha_in  DATE,
  p_fecha_out DATE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_pq            RECORD;
  v_paquetes      JSONB   := '[]'::JSONB;
  v_noches        DATE[]  := '{}'::DATE[];
  v_parcial       JSONB   := NULL;
  v_sin_paquete   BOOLEAN := FALSE;
  v_rbase         NUMERIC;
  v_personas_max  INTEGER := NULL;
BEGIN
  v_rbase := COALESCE(precios_config('precio_redondeo_base')::NUMERIC, 1000);

  FOR v_pq IN
    SELECT pq.id_paquete, pq.id_evento, pq.nombre_paquete,
           pq.fecha_in, pq.fecha_out, pq.precio_total, pq.personas_max,
           e.nombre AS evento_nombre
    FROM paquetes_evento pq
    JOIN eventos_especiales e ON e.id_evento = pq.id_evento
    WHERE pq.activo = TRUE
      AND e.activa  = TRUE
      AND pq.tipo_cabana = p_perfil
      AND pq.fecha_in  IS NOT NULL
      AND pq.fecha_out IS NOT NULL
      AND pq.fecha_in  <  p_fecha_out      -- interseccion de [in,out)
      AND pq.fecha_out >  p_fecha_in
    ORDER BY pq.fecha_in, pq.id_paquete
  LOOP
    -- La estadia debe CONTENER el paquete completo
    IF v_pq.fecha_in < p_fecha_in OR v_pq.fecha_out > p_fecha_out THEN
      v_parcial := jsonb_build_object(
        'id_paquete', v_pq.id_paquete,
        'id_evento', v_pq.id_evento,
        'evento', v_pq.evento_nombre,
        'paquete', v_pq.nombre_paquete,
        'fecha_in', v_pq.fecha_in,
        'fecha_out', v_pq.fecha_out);
      EXIT;
    END IF;

    v_paquetes := v_paquetes || jsonb_build_object(
      'id_evento',   v_pq.id_evento,
      'id_paquete',  v_pq.id_paquete,
      'evento',      v_pq.evento_nombre,
      'paquete',     v_pq.nombre_paquete,
      'fecha_in',    v_pq.fecha_in,
      'fecha_out',   v_pq.fecha_out,
      'noches',      (v_pq.fecha_out - v_pq.fecha_in),
      'precio',      precios_money(precios_redondear(v_pq.precio_total, v_rbase)),
      'personas_max', v_pq.personas_max);

    v_noches := v_noches || ARRAY(
      SELECT d::DATE FROM generate_series(v_pq.fecha_in, v_pq.fecha_out - 1, INTERVAL '1 day') d);

    IF v_pq.personas_max IS NOT NULL THEN
      v_personas_max := LEAST(COALESCE(v_personas_max, v_pq.personas_max), v_pq.personas_max);
    END IF;
  END LOOP;

  -- Parcialidad: no se aplica NINGUN paquete (se cotiza estandar + restriccion)
  IF v_parcial IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'evento_parcial_no_vendible',
      'paquete_requerido', v_parcial);
  END IF;

  -- D-PR-20: evento activo que intersecta pero sin paquete valido para el perfil
  -- eventos_especiales.fecha_hasta se interpreta INCLUSIVE (metadata del evento)
  SELECT EXISTS (
    SELECT 1
    FROM eventos_especiales e
    WHERE e.activa = TRUE
      AND e.fecha_desde < p_fecha_out
      AND (e.fecha_hasta + 1) > p_fecha_in
      AND NOT EXISTS (
        SELECT 1 FROM paquetes_evento pq
        WHERE pq.id_evento = e.id_evento
          AND pq.activo = TRUE
          AND pq.tipo_cabana = p_perfil
          AND pq.fecha_in  IS NOT NULL
          AND pq.fecha_out IS NOT NULL
          AND pq.fecha_in  <  p_fecha_out
          AND pq.fecha_out >  p_fecha_in
      )
  ) INTO v_sin_paquete;

  RETURN jsonb_build_object(
    'ok', true,
    'paquetes', v_paquetes,
    'noches_evento', to_jsonb(v_noches),
    'noches_evento_count', COALESCE(array_length(v_noches, 1), 0),
    'personas_max', v_personas_max,
    'evento_sin_paquete_perfil', v_sin_paquete);
END
$$;

-- ===========================================================================
-- H8. precios_extra_persona -- D-PR-18: TODAS las noches (estandar + evento)
--   extras = LEAST(GREATEST(personas - incluidas, 0), 1)   -- maximo 1 extra
-- ===========================================================================
CREATE FUNCTION precios_extra_persona(
  p_perfil       TEXT,
  p_personas     INTEGER,
  p_noches_count INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_incluidas INTEGER;
  v_activo    BOOLEAN;
  v_monto     NUMERIC;
  v_extras    INTEGER;
BEGIN
  SELECT pt.personas_incluidas INTO v_incluidas
  FROM perfiles_tarifarios pt WHERE pt.perfil = p_perfil;

  IF v_incluidas IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'perfil_desconocido', 'perfil', p_perfil);
  END IF;

  v_activo := (COALESCE(precios_config('precio_extra_persona_activo'), 'false') = 'true');
  v_monto  := COALESCE(precios_config('precio_extra_persona_monto')::NUMERIC, 0);

  IF NOT v_activo THEN
    RETURN jsonb_build_object('ok', true, 'activo', false, 'extras', 0,
                              'total', 0::NUMERIC, 'personas_incluidas', v_incluidas);
  END IF;

  v_extras := LEAST(GREATEST(p_personas - v_incluidas, 0), 1);

  RETURN jsonb_build_object(
    'ok', true,
    'activo', true,
    'extras', v_extras,
    'monto_unitario', v_monto,
    'noches', p_noches_count,
    'total', (v_extras::NUMERIC * v_monto * p_noches_count::NUMERIC),
    'personas_incluidas', v_incluidas);
END
$$;

-- ===========================================================================
-- H9. precios_disponibilidad_noches -- READ-ONLY, sin locks
--   obtener_disponibilidad_rango(p_fecha_in, p_fecha_out) -- `hasta` EXCLUSIVE
--   Noche vendible <=> estado IN ('disponible','checkout_disponible')
-- ===========================================================================
CREATE FUNCTION precios_disponibilidad_noches(
  p_id_cabana BIGINT,
  p_fecha_in  DATE,
  p_fecha_out DATE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_total     INTEGER;
  v_vendibles INTEGER;
  v_no        JSONB;
BEGIN
  SELECT COUNT(*)::INTEGER,
         COUNT(*) FILTER (WHERE d.estado IN ('disponible','checkout_disponible'))::INTEGER,
         COALESCE(jsonb_agg(jsonb_build_object('fecha', d.fecha, 'estado', d.estado)
                            ORDER BY d.fecha)
                  FILTER (WHERE d.estado NOT IN ('disponible','checkout_disponible')),
                  '[]'::JSONB)
    INTO v_total, v_vendibles, v_no
  FROM obtener_disponibilidad_rango(p_fecha_in, p_fecha_out, p_id_cabana) d;

  RETURN jsonb_build_object(
    'disponible', (v_total > 0 AND v_total = v_vendibles),
    'noches_total', v_total,
    'noches_vendibles', v_vendibles,
    'noches_no_vendibles', v_no);
END
$$;

-- ===========================================================================
-- C1. precios_cotizar(jsonb) -- ORQUESTADOR. READ-ONLY (no escribe, no lockea)
-- ---------------------------------------------------------------------------
-- Entrada : {id_cabana, fecha_in, fecha_out, personas, canal?, modo?}
--           canal: web|whatsapp|bot|portal (default 'web')
--           modo : online|manual           (default 'online')
-- Salida  : contrato completo (montos como STRING).
--
-- Categorias de error:
--   A) ok=false                       : payload_invalido, perfil_desconocido,
--                                       temporada_no_resuelta, tarifa_incompleta
--   B) ok=true, reservable_online=false: no_disponible, evento_parcial_no_vendible,
--                                       bloque_finde_obligatorio, estadia_larga_derivar,
--                                       excede_capacidad, evento_sin_paquete_perfil
--   C) warnings                       : capacidad_max_override, recargo_extra_persona,
--                                       cargo_saldo_transferencia_mp
--   En modo=manual, los motivos de (B) se degradan a warnings, EXCEPTO
--   no_disponible (la disponibilidad real nunca se pisa).
-- ===========================================================================
CREATE FUNCTION precios_cotizar(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_id_cabana BIGINT;
  v_fin       DATE;
  v_fout      DATE;
  v_personas  INTEGER;
  v_canal     TEXT;
  v_modo      TEXT;
  v_manual    BOOLEAN;

  v_perfil    TEXT;
  v_cap_max   INTEGER;
  v_noches    INTEGER;

  v_ev             JSONB;
  v_noches_evento  DATE[] := '{}'::DATE[];
  v_paquetes       JSONB  := '[]'::JSONB;
  v_ev_parcial     JSONB  := NULL;
  v_ev_sin_paq     BOOLEAN := FALSE;
  v_pq_personas_max INTEGER := NULL;

  v_n         RECORD;
  v_pn        JSONB;
  v_p_noche   NUMERIC;
  v_sub_std   NUMERIC := 0;
  v_sub_ev    NUMERIC := 0;
  v_desg_noches JSONB := '[]'::JSONB;

  v_extra     JSONB;
  v_extra_tot NUMERIC := 0;

  v_disp      JSONB;
  v_disponible BOOLEAN;

  v_rbase     NUMERIC;
  v_total     NUMERIC;
  v_sena_pct  NUMERIC;
  v_sena      NUMERIC;
  v_saldo     NUMERIC;
  v_pct_transf NUMERIC;
  v_cargo_mp  NUMERIC;

  v_bloque_activo BOOLEAN;
  v_umbral    INTEGER;
  v_viola_finde BOOLEAN := FALSE;
  v_f         DATE;
  v_f_in      BOOLEAN;
  v_s_in      BOOLEAN;

  v_restricciones JSONB := '[]'::JSONB;
  v_warnings      JSONB := '[]'::JSONB;
  v_motivo    TEXT := NULL;
  v_reservable BOOLEAN := TRUE;
  v_source    TEXT;
  v_std_count INTEGER := 0;
BEGIN
  ---------------------------------------------------------------------------
  -- 1) Validacion de payload
  ---------------------------------------------------------------------------
  BEGIN
    v_id_cabana := (p_payload->>'id_cabana')::BIGINT;
    v_fin       := (p_payload->>'fecha_in')::DATE;
    v_fout      := (p_payload->>'fecha_out')::DATE;
    v_personas  := (p_payload->>'personas')::INTEGER;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido',
                              'detalle', 'tipos invalidos en id_cabana/fecha_in/fecha_out/personas');
  END;

  v_canal := COALESCE(p_payload->>'canal', 'web');
  v_modo  := COALESCE(p_payload->>'modo', 'online');
  v_manual := (v_modo = 'manual');

  IF v_id_cabana IS NULL OR v_fin IS NULL OR v_fout IS NULL OR v_personas IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido',
                              'detalle', 'faltan campos obligatorios');
  END IF;
  IF v_fout <= v_fin THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido',
                              'detalle', 'fecha_out debe ser mayor a fecha_in (fecha_out exclusive)');
  END IF;
  IF v_personas < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido',
                              'detalle', 'personas debe ser >= 1');
  END IF;
  IF v_modo NOT IN ('online','manual') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'modo invalido');
  END IF;
  IF v_canal NOT IN ('web','whatsapp','bot','portal') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'canal invalido');
  END IF;

  ---------------------------------------------------------------------------
  -- 2) Cabana -> perfil tarifario
  ---------------------------------------------------------------------------
  SELECT c.perfil_tarifario, c.capacidad_max
    INTO v_perfil, v_cap_max
  FROM cabanas c WHERE c.id_cabana = v_id_cabana AND c.activa = TRUE;

  IF v_perfil IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'perfil_desconocido',
                              'id_cabana', v_id_cabana,
                              'detalle', 'cabana inexistente/inactiva o sin perfil_tarifario');
  END IF;

  v_noches := (v_fout - v_fin);

  ---------------------------------------------------------------------------
  -- 3) Eventos especiales
  ---------------------------------------------------------------------------
  v_ev := precios_eventos_interseccion(v_perfil, v_fin, v_fout);

  IF NOT (v_ev->>'ok')::BOOLEAN THEN
    -- evento_parcial_no_vendible: no se aplica ningun paquete; se cotiza estandar
    v_ev_parcial := v_ev->'paquete_requerido';
    v_restricciones := v_restricciones || jsonb_build_object(
      'codigo', 'evento_parcial_no_vendible',
      'detalle', 'La estadia intersecta un paquete de evento sin incluirlo completo.',
      'paquete_requerido', v_ev_parcial);
    IF v_manual THEN
      v_warnings := v_warnings || jsonb_build_object('codigo', 'evento_parcial_no_vendible',
                                                     'paquete_requerido', v_ev_parcial);
    ELSE
      v_reservable := FALSE;
      v_motivo := COALESCE(v_motivo, 'evento_parcial_no_vendible');
    END IF;
  ELSE
    v_paquetes   := v_ev->'paquetes';
    v_ev_sin_paq := COALESCE((v_ev->>'evento_sin_paquete_perfil')::BOOLEAN, FALSE);
    IF (v_ev->>'noches_evento_count')::INTEGER > 0 THEN
      SELECT ARRAY(SELECT (jsonb_array_elements_text(v_ev->'noches_evento'))::DATE)
        INTO v_noches_evento;
    END IF;
    IF (v_ev->'personas_max') IS NOT NULL AND jsonb_typeof(v_ev->'personas_max') = 'number' THEN
      v_pq_personas_max := (v_ev->>'personas_max')::INTEGER;
    END IF;

    -- D-PR-20: evento activo sin paquete para el perfil
    IF v_ev_sin_paq THEN
      IF v_manual THEN
        v_warnings := v_warnings || jsonb_build_object('codigo', 'evento_sin_paquete_perfil',
          'detalle', 'Hay evento activo en esas fechas sin paquete para este perfil. Cotizado con motor estandar (referencia).');
      ELSE
        v_reservable := FALSE;
        v_motivo := COALESCE(v_motivo, 'evento_sin_paquete_perfil');
        v_restricciones := v_restricciones || jsonb_build_object('codigo', 'evento_sin_paquete_perfil',
          'detalle', 'Evento activo sin paquete para el perfil: deriva a humano.');
      END IF;
    END IF;
  END IF;

  -- Subtotal de paquetes aplicados
  SELECT COALESCE(SUM((p->>'precio')::NUMERIC), 0) INTO v_sub_ev
  FROM jsonb_array_elements(v_paquetes) p;

  ---------------------------------------------------------------------------
  -- 4) Ordinales + precio de noches estandar
  ---------------------------------------------------------------------------
  FOR v_n IN
    SELECT * FROM precios_asignar_ordinales(v_fin, v_fout, v_noches_evento) ORDER BY fecha
  LOOP
    IF v_n.tipo = 'evento' THEN
      CONTINUE;  -- ya contabilizada en el paquete
    END IF;

    v_pn := precios_precio_noche(v_perfil, v_n.fecha, v_n.tipo, v_n.concepto);

    IF NOT (v_pn->>'ok')::BOOLEAN THEN
      -- Errores duros (categoria A): tarifa_incompleta / temporada_no_resuelta
      RETURN jsonb_build_object('ok', false,
        'error', v_pn->>'error',
        'detalle', v_pn,
        'id_cabana', v_id_cabana, 'perfil_tarifario', v_perfil);
    END IF;

    v_p_noche  := (v_pn->>'precio')::NUMERIC;
    v_sub_std  := v_sub_std + v_p_noche;
    v_std_count := v_std_count + 1;

    v_desg_noches := v_desg_noches || jsonb_build_object(
      'fecha',     v_n.fecha,
      'tipo',      v_n.tipo,
      'ordinal',   v_n.ordinal,
      'concepto',  v_n.concepto,
      'temporada', v_pn->>'temporada',
      'precio',    precios_money(v_p_noche),
      'override_id', v_pn->'override_id');
  END LOOP;

  ---------------------------------------------------------------------------
  -- 5) Extra persona (D-PR-18: sobre TODAS las noches)
  ---------------------------------------------------------------------------
  v_extra := precios_extra_persona(v_perfil, v_personas, v_noches);
  IF NOT (v_extra->>'ok')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', v_extra->>'error', 'detalle', v_extra);
  END IF;
  v_extra_tot := (v_extra->>'total')::NUMERIC;

  IF COALESCE((v_extra->>'extras')::INTEGER, 0) > 0 THEN
    v_warnings := v_warnings || jsonb_build_object(
      'codigo', 'recargo_extra_persona',
      'detalle', 'Se aplica recargo por persona extra por noche.',
      'extras', (v_extra->>'extras')::INTEGER,
      'monto_unitario', precios_money((v_extra->>'monto_unitario')::NUMERIC),
      'total', precios_money(v_extra_tot));
  END IF;

  ---------------------------------------------------------------------------
  -- 6) Disponibilidad (READ-ONLY, sin locks)
  ---------------------------------------------------------------------------
  v_disp := precios_disponibilidad_noches(v_id_cabana, v_fin, v_fout);
  v_disponible := COALESCE((v_disp->>'disponible')::BOOLEAN, FALSE);

  IF NOT v_disponible THEN
    -- R1: la disponibilidad real NUNCA se pisa (ni en manual)
    v_reservable := FALSE;
    v_motivo := COALESCE(v_motivo, 'no_disponible');
    v_restricciones := v_restricciones || jsonb_build_object(
      'codigo', 'no_disponible',
      'noches_no_vendibles', v_disp->'noches_no_vendibles');
  END IF;

  ---------------------------------------------------------------------------
  -- 7) Reglas de venta R3/R4/R5
  ---------------------------------------------------------------------------
  -- R3: bloque viernes+sabado en temporada alta (switch)
  v_bloque_activo := (COALESCE(precios_config('precio_bloque_finde_alta_activo'),'false') = 'true');
  IF v_bloque_activo THEN
    FOR v_f IN
      SELECT d::DATE FROM generate_series(v_fin - 1, v_fout - 1, INTERVAL '1 day') d
      WHERE EXTRACT(DOW FROM d) = 5           -- viernes ancla
    LOOP
      -- exento si el viernes o el sabado son noche de paquete de evento (R2 domina)
      IF v_f = ANY (v_noches_evento) OR (v_f + 1) = ANY (v_noches_evento) THEN
        CONTINUE;
      END IF;
      IF precios_resolver_temporada(v_f) IS DISTINCT FROM 'alta' THEN
        CONTINUE;
      END IF;
      v_f_in := (v_f  >= v_fin AND v_f  < v_fout);
      v_s_in := ((v_f + 1) >= v_fin AND (v_f + 1) < v_fout);
      IF v_f_in <> v_s_in THEN
        v_viola_finde := TRUE;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  IF v_viola_finde THEN
    v_restricciones := v_restricciones || jsonb_build_object(
      'codigo', 'bloque_finde_obligatorio',
      'detalle', 'En temporada alta, viernes y sabado se venden juntos.');
    IF v_manual THEN
      v_warnings := v_warnings || jsonb_build_object('codigo', 'bloque_finde_obligatorio');
    ELSE
      v_reservable := FALSE;
      v_motivo := COALESCE(v_motivo, 'bloque_finde_obligatorio');
    END IF;
  END IF;

  -- R4: estadia larga
  v_umbral := COALESCE(precios_config('precio_estadia_larga_umbral_noches')::INTEGER, 10);
  IF v_noches >= v_umbral THEN
    v_restricciones := v_restricciones || jsonb_build_object(
      'codigo', 'estadia_larga_derivar',
      'detalle', 'Para estadias largas coordina el equipo.',
      'noches', v_noches, 'umbral', v_umbral);
    IF v_manual THEN
      v_warnings := v_warnings || jsonb_build_object('codigo', 'estadia_larga_derivar', 'noches', v_noches);
    ELSE
      v_reservable := FALSE;
      v_motivo := COALESCE(v_motivo, 'estadia_larga_derivar');
    END IF;
  END IF;

  -- R5: capacidad maxima  (enforcement real de la escritura: B3.1)
  IF v_personas > v_cap_max THEN
    IF v_manual THEN
      v_warnings := v_warnings || jsonb_build_object(
        'codigo', 'capacidad_max_override',
        'detalle', 'Personas por encima de la capacidad maxima: requiere override explicito y motivo.',
        'personas', v_personas, 'capacidad_max', v_cap_max);
    ELSE
      v_reservable := FALSE;
      v_motivo := COALESCE(v_motivo, 'excede_capacidad');
      v_restricciones := v_restricciones || jsonb_build_object(
        'codigo', 'excede_capacidad',
        'personas', v_personas, 'capacidad_max', v_cap_max);
    END IF;
  END IF;

  -- Paquete con personas_max excedido
  IF v_pq_personas_max IS NOT NULL AND v_personas > v_pq_personas_max THEN
    v_restricciones := v_restricciones || jsonb_build_object(
      'codigo', 'evento_personas_max_excedido',
      'personas', v_personas, 'personas_max_paquete', v_pq_personas_max);
    IF v_manual THEN
      v_warnings := v_warnings || jsonb_build_object('codigo', 'evento_personas_max_excedido');
    ELSE
      v_reservable := FALSE;
      v_motivo := COALESCE(v_motivo, 'evento_personas_max_excedido');
    END IF;
  END IF;

  ---------------------------------------------------------------------------
  -- 8) Dinero (D-PR-08 / D-PR-19)
  ---------------------------------------------------------------------------
  v_rbase := COALESCE(precios_config('precio_redondeo_base')::NUMERIC, 1000);
  v_total := v_sub_std + v_sub_ev + v_extra_tot;

  v_sena_pct := COALESCE(precios_config('precio_sena_pct_default')::NUMERIC, 50);
  v_sena  := precios_redondear(v_total * v_sena_pct / 100.0, v_rbase);
  v_saldo := v_total - v_sena;                       -- el saldo absorbe la diferencia

  v_pct_transf := COALESCE(precios_config('precio_recargo_saldo_transferencia_pct')::NUMERIC, 5);
  v_cargo_mp   := ROUND(v_saldo * v_pct_transf / 100.0);   -- al peso (alineado A10-MP)

  IF v_cargo_mp > 0 THEN
    v_warnings := v_warnings || jsonb_build_object(
      'codigo', 'cargo_saldo_transferencia_mp',
      'detalle', 'El saldo en efectivo no tiene recargo. Por transferencia/MP se cobra un extra, aparte del alojamiento.',
      'pct', v_pct_transf,
      'monto_estimado', precios_money(v_cargo_mp));
  END IF;

  ---------------------------------------------------------------------------
  -- 9) precio_source
  ---------------------------------------------------------------------------
  IF jsonb_array_length(v_paquetes) > 0 AND v_std_count = 0 THEN
    v_source := 'evento_especial';
  ELSIF jsonb_array_length(v_paquetes) > 0 THEN
    v_source := 'mixto';
  ELSE
    v_source := 'motor_estandar';
  END IF;

  ---------------------------------------------------------------------------
  -- 10) Salida
  ---------------------------------------------------------------------------
  RETURN jsonb_build_object(
    'ok', true,
    'disponible', v_disponible,
    'reservable_online', (CASE WHEN v_manual THEN NULL ELSE v_reservable END),
    'motivo_no_reservable', (CASE WHEN v_manual THEN NULL ELSE v_motivo END),
    'modo', v_modo,
    'canal', v_canal,
    'id_cabana', v_id_cabana,
    'perfil_tarifario', v_perfil,
    'capacidad_max', v_cap_max,
    'fecha_in', v_fin,
    'fecha_out', v_fout,
    'personas', v_personas,
    'noches_count', v_noches,
    'precio_total', precios_money(v_total),
    'monto_sena', precios_money(v_sena),
    'monto_saldo', precios_money(v_saldo),
    'extra_persona_total', precios_money(v_extra_tot),
    'cargo_saldo_transferencia_mp', precios_money(v_cargo_mp),
    'precio_source', v_source,
    'desglose_noches', v_desg_noches,
    'desglose_eventos', v_paquetes,
    'restricciones', v_restricciones,
    'warnings', v_warnings,
    'cotizacion_id', NULL,
    'expires_at', NULL
  );
END
$$;

-- ===========================================================================
-- C2. precios_cotizar_congelar(jsonb) -- UNICO writer del path de cotizacion.
--   Escribe SOLO en cotizaciones_precio. Sin locks, sin FOR UPDATE, sin
--   pre-reservas, sin tocar disponibilidad. Solo congela lo vendible online.
-- ===========================================================================
CREATE FUNCTION precios_cotizar_congelar(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_q   JSONB;
  v_ttl INTEGER;
  v_exp TIMESTAMPTZ;
  v_id  UUID;
BEGIN
  v_q := precios_cotizar(p_payload);

  IF NOT (v_q->>'ok')::BOOLEAN THEN
    RETURN v_q;
  END IF;

  IF NOT COALESCE((v_q->>'disponible')::BOOLEAN, FALSE)
     OR NOT COALESCE((v_q->>'reservable_online')::BOOLEAN, FALSE) THEN
    RETURN v_q || jsonb_build_object('congelada', false,
      'detalle_congelamiento', 'No se congela una cotizacion no vendible online.');
  END IF;

  v_ttl := COALESCE(precios_config('precio_cotizacion_ttl_minutos')::INTEGER, 30);
  v_exp := NOW() + (v_ttl::TEXT || ' minutes')::INTERVAL;

  INSERT INTO cotizaciones_precio (
    id_cabana, perfil, fecha_in, fecha_out, personas, canal,
    precio_total, monto_sena, monto_saldo, precio_source, snapshot, expires_at)
  VALUES (
    (v_q->>'id_cabana')::BIGINT,
    v_q->>'perfil_tarifario',
    (v_q->>'fecha_in')::DATE,
    (v_q->>'fecha_out')::DATE,
    (v_q->>'personas')::INTEGER,
    v_q->>'canal',
    (v_q->>'precio_total')::NUMERIC,
    (v_q->>'monto_sena')::NUMERIC,
    (v_q->>'monto_saldo')::NUMERIC,
    v_q->>'precio_source',
    v_q,
    v_exp)
  RETURNING cotizacion_id INTO v_id;

  RETURN v_q || jsonb_build_object(
    'cotizacion_id', v_id,
    'expires_at', v_exp,
    'congelada', true,
    'ttl_minutos', v_ttl);
END
$$;

-- ===========================================================================
-- C3. precios_cotizacion_obtener(uuid) -- lectura de cotizacion congelada
-- ===========================================================================
CREATE FUNCTION precios_cotizacion_obtener(p_cotizacion_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE v RECORD;
BEGIN
  SELECT * INTO v FROM cotizaciones_precio c WHERE c.cotizacion_id = p_cotizacion_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cotizacion_no_encontrada',
                              'cotizacion_id', p_cotizacion_id);
  END IF;

  IF v.expires_at <= NOW() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cotizacion_vencida',
                              'cotizacion_id', p_cotizacion_id,
                              'expires_at', v.expires_at);
  END IF;

  RETURN v.snapshot || jsonb_build_object(
    'cotizacion_id', v.cotizacion_id,
    'expires_at', v.expires_at,
    'vigente', true);
END
$$;

-- ===========================================================================
-- HARDENING: owner-only (patron confirmado en B1.1). Sin Data API.
-- ===========================================================================
REVOKE EXECUTE ON FUNCTION precios_config(TEXT)                              FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_redondear(NUMERIC, NUMERIC)               FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_money(NUMERIC)                            FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_resolver_temporada(DATE)                  FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_clasificar_noche(DATE)                    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_asignar_ordinales(DATE, DATE, DATE[])     FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_precio_noche(TEXT, DATE, TEXT, TEXT)      FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_eventos_interseccion(TEXT, DATE, DATE)    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_extra_persona(TEXT, INTEGER, INTEGER)     FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_disponibilidad_noches(BIGINT, DATE, DATE) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_cotizar(JSONB)                            FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_cotizar_congelar(JSONB)                   FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION precios_cotizacion_obtener(UUID)                  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

-- ============================================================================
-- FIN B3. Correr B3_VERIFY.sql y B3_SMOKES.sql a continuacion.
-- ============================================================================
