-- ============================================================================
-- B4_0A_ROL_TABLAS_FUNCIONES.sql
-- Motor de Precios v2 -- Bloque B4 -- Fase 0A
-- Rol PG dedicado + 4 tablas de infraestructura + 19 funciones + 4 jobs pg_cron
--
-- CONSUME el motor B3. NO lo modifica. Las 13 precios_* quedan intactas
-- (fingerprint normalizado 098f2fe7916e11ffa78cff37622b9064).
-- La estructura B2A queda intacta (da52a16c045689523a5f1f113f513a87):
-- las 4 tablas de B4 son NUEVAS y no entran en la lista del fingerprint.
--
-- AMBIENTE: TEST unicamente. Gate transaccional al inicio.
-- PASSWORD: este archivo NO crea ni contiene password. El rol nace NOLOGIN.
--           El ALTER de password se ejecuta a mano (ver B4_0A_RUNSHEET.md).
--
-- Ejecutar entero. Es transaccional salvo la seccion de pg_cron (ver 10).
-- ============================================================================

BEGIN;

-- ===========================================================================
-- 0) GATE ANTI-AMBIENTE  (transaccional: aborta todo si no es TEST)
-- ===========================================================================
DO $gate$
DECLARE
  v_amb      TEXT;
  v_esperado TEXT := 'test';
BEGIN
  SELECT valor INTO v_amb FROM public.configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS NULL THEN
    RAISE EXCEPTION 'B4-0A abortado: no existe configuracion_general(ambiente).';
  END IF;
  IF v_amb IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'B4-0A abortado: ambiente=% (esperado %). Este artefacto es TEST-only.',
                    v_amb, v_esperado;
  END IF;
END
$gate$;

-- ===========================================================================
-- 1) ROL DEDICADO -- NOLOGIN, sin password, sin privilegios propios
--    El ALTER ... LOGIN PASSWORD se ejecuta fuera del repo (runsheet, paso 3).
--    NOLOGIN es fail-safe: si el ALTER no se corre, el rol no puede conectarse.
-- ===========================================================================
DO $rol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'vita_precios_api') THEN
    CREATE ROLE vita_precios_api NOLOGIN;
  END IF;
END
$rol$;

-- Fallback de sesion para la conexion legitima de la Edge.
-- NO es una cota dura: un caller con la credencial puede hacer SET statement_timeout = 0.
-- La defensa server-side real son las cotas estructurales del wrapper (span/horizonte/personas).
ALTER ROLE vita_precios_api SET statement_timeout = '5s';
ALTER ROLE vita_precios_api SET lock_timeout      = '2s';

-- USAGE es imprescindible: sin el, el rol no puede invocar NINGUNA funcion de public.
-- USAGE sobre un schema NO da acceso a sus objetos: cada objeto conserva su propia ACL.
GRANT USAGE ON SCHEMA public TO vita_precios_api;
-- El rol no debe poder crear objetos en public.
REVOKE CREATE ON SCHEMA public FROM vita_precios_api;

-- ===========================================================================
-- 2) TABLAS DE INFRAESTRUCTURA B4  (4)
--    PKs compuestas / simples. CERO secuencias (no tocan el hardening B2A).
-- ===========================================================================

-- 2.1 rate limit -- ventana fija de 60s, contador condicional
CREATE TABLE IF NOT EXISTS api_precios_rate_limit (
  scope   TEXT        NOT NULL,
  sujeto  TEXT        NOT NULL,
  ventana TIMESTAMPTZ NOT NULL,
  n       INTEGER     NOT NULL,
  CONSTRAINT pk_api_precios_rate_limit PRIMARY KEY (scope, sujeto, ventana),
  CONSTRAINT chk_rl_n CHECK (n >= 1)
);

-- 2.2 nonce S2S -- consumo unico. El UNIQUE (la PK) ES el anti-replay.
CREATE TABLE IF NOT EXISTS api_precios_nonce_s2s (
  client_id  TEXT        NOT NULL,
  nonce      UUID        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_api_precios_nonce_s2s PRIMARY KEY (client_id, nonce)
);

-- 2.3 ticket single-use -- emitido en TXN1 (admision), consumido en TXN2 (ejecucion).
--     superficie/sujeto con CHECK S2S-only: F3 aplicada ESTRUCTURALMENTE.
CREATE TABLE IF NOT EXISTS api_precios_ticket (
  ticket_id      UUID        NOT NULL,
  accion         TEXT        NOT NULL,
  superficie     TEXT        NOT NULL,
  sujeto         TEXT        NOT NULL,
  request_hash   TEXT        NOT NULL,
  correlation_id UUID        NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at     TIMESTAMPTZ NOT NULL,
  consumed_at    TIMESTAMPTZ,
  CONSTRAINT pk_api_precios_ticket   PRIMARY KEY (ticket_id),
  CONSTRAINT chk_ticket_accion       CHECK (accion IN ('cotizar','congelar','obtener')),
  CONSTRAINT chk_ticket_superficie   CHECK (superficie = 's2s'),
  CONSTRAINT chk_ticket_sujeto       CHECK (sujeto = 'whatsapp'),
  CONSTRAINT chk_ticket_hash         CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT chk_ticket_vigencia     CHECK (expires_at > created_at),
  CONSTRAINT chk_ticket_consumo      CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);

-- 2.4 idempotencia de congelar -- SOLO congelamientos EXITOSOS.
--     cotizacion_id NOT NULL es consistente: la fila existe solo si hubo escritura.
CREATE TABLE IF NOT EXISTS api_precios_idempotencia (
  scope                   TEXT        NOT NULL,
  idempotency_key         UUID        NOT NULL,
  canon_hash              TEXT        NOT NULL,
  cotizacion_id           UUID        NOT NULL
                            REFERENCES cotizaciones_precio(cotizacion_id) ON DELETE RESTRICT,
  resultado_motor_privado JSONB       NOT NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_api_precios_idempotencia PRIMARY KEY (scope, idempotency_key),
  CONSTRAINT chk_idem_scope CHECK (scope LIKE 'precios.congelar:%'),
  CONSTRAINT chk_idem_hash  CHECK (canon_hash ~ '^[0-9a-f]{64}$')
);

CREATE INDEX IF NOT EXISTS idx_api_precios_ticket_expira
  ON api_precios_ticket (expires_at);
CREATE INDEX IF NOT EXISTS idx_api_precios_idem_created
  ON api_precios_idempotencia (created_at);

-- Hardening anti Data API + anti rol: el rol NO tiene privilegios de tabla.
-- Las escribe el SECURITY DEFINER corriendo como postgres.
REVOKE ALL ON TABLE
  api_precios_rate_limit, api_precios_nonce_s2s,
  api_precios_ticket, api_precios_idempotencia
  FROM PUBLIC, anon, authenticated, service_role, vita_precios_api;

-- ===========================================================================
-- 3) HELPERS OWNER-ONLY
-- ===========================================================================

-- 3.1 D3 -- GUARD DE SESION LIMPIA.
--     Primera sentencia ejecutable de los 3 *_exponer, de admitir y de los 3 core.
--     Protege a B3, que NO se puede modificar: B3 tiene search_path sin pg_temp y
--     referencias sin schema-qualify, por lo que una relacion temporal homonima
--     lo envenena aun llamado desde un SECURITY DEFINER (verificado en harness).
--     pg_class OR pg_type: pg_class es ciego a ENUM/DOMAIN/RANGE (typrelid=0);
--     pg_type es ciego a TEMP SEQUENCE. Hacen falta los dos (verificado).
--     DISCARD ALL limpia AMBOS catalogos -> no hay falso positivo permanente.
DROP FUNCTION IF EXISTS api_precios_guard_sesion();
CREATE FUNCTION api_precios_guard_sesion()
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF pg_catalog.pg_my_temp_schema() <> 0
     AND (
       EXISTS (SELECT 1 FROM pg_catalog.pg_class c
                WHERE c.relnamespace = pg_catalog.pg_my_temp_schema())
       OR
       EXISTS (SELECT 1 FROM pg_catalog.pg_type t
                WHERE t.typnamespace = pg_catalog.pg_my_temp_schema())
     )
  THEN
    RAISE EXCEPTION 'sesion_contaminada' USING ERRCODE = 'VDT01';
  END IF;
END
$$;

-- 3.2 gate de ambiente -- schema-qualified, una sola fuente de verdad
DROP FUNCTION IF EXISTS api_precios_gate_ambiente();
CREATE FUNCTION api_precios_gate_ambiente()
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE v_amb TEXT;
BEGIN
  SELECT cg.valor INTO v_amb
    FROM public.configuracion_general cg
   WHERE cg.clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ambiente_no_admitido' USING ERRCODE = 'VDT03';
  END IF;
END
$$;

-- 3.3 CANON DEL TICKET -- una sola implementacion, 4 llamadores.
--     jsonb::text es canonico (orden de claves y whitespace normalizados por jsonb)
--     -> el hash de TXN1 (payload TEXT->jsonb) coincide con el de TXN2 (payload JSONB).
--     Verificado en harness.
DROP FUNCTION IF EXISTS api_precios_ticket_hash_v1(TEXT, TEXT, TEXT, JSONB, UUID, UUID);
CREATE FUNCTION api_precios_ticket_hash_v1(
  p_accion        TEXT,
  p_superficie    TEXT,
  p_sujeto        TEXT,
  p_payload       JSONB,
  p_idem_key      UUID,
  p_cotizacion_id UUID
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT pg_catalog.encode(
           pg_catalog.sha256(
             (pg_catalog.jsonb_build_object(
                'v',             'b4tk1',
                'accion',        p_accion,
                'superficie',    p_superficie,
                'sujeto',        p_sujeto,
                'payload',       COALESCE(p_payload, 'null'::jsonb),
                'idem_key',      COALESCE(p_idem_key::TEXT, ''),
                'cotizacion_id', COALESCE(p_cotizacion_id::TEXT, '')
              ))::TEXT::BYTEA
           ), 'hex')
$$;

-- 3.4 RATE LIMIT ATOMICO.
--     El limite se deriva del scope DENTRO de SQL. Ningun numero llega de la Edge.
--     ON CONFLICT DO UPDATE ... WHERE n < limite  -> sin fila en RETURNING = DENEGADO.
--     Verificado: 100 concurrentes / limite 60 -> 60 admitidas, contador final 60 (no 100).
--     Los scopes _web quedan DEFINIDOS pero NO son alcanzables: api_precios_admitir
--     rechaza superficie <> 's2s' (F3). Se activan con un artefacto aditivo si B4-0C
--     demuestra una IP no falsificable.
DROP FUNCTION IF EXISTS api_precios_rl_consumir(TEXT, TEXT);
CREATE FUNCTION api_precios_rl_consumir(p_scope TEXT, p_sujeto TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_lim INTEGER;
  v_n   INTEGER;
BEGIN
  v_lim := CASE p_scope
             WHEN 'cotizar_global'  THEN 600
             WHEN 'congelar_global' THEN 120
             WHEN 'obtener_global'  THEN 1200
             WHEN 'cotizar_s2s'     THEN 300
             WHEN 'congelar_s2s'    THEN 60
             WHEN 'obtener_s2s'     THEN 600
             WHEN 'cotizar_web'     THEN 60
             WHEN 'congelar_web'    THEN 10
             WHEN 'obtener_web'     THEN 120
             ELSE NULL
           END;

  IF v_lim IS NULL THEN
    RAISE EXCEPTION 'scope_desconocido' USING ERRCODE = 'VDT02';
  END IF;

  INSERT INTO public.api_precios_rate_limit AS rl (scope, sujeto, ventana, n)
  VALUES (p_scope, p_sujeto, pg_catalog.date_trunc('minute', pg_catalog.now()), 1)
  ON CONFLICT ON CONSTRAINT pk_api_precios_rate_limit DO UPDATE
     SET n = rl.n + 1
   WHERE rl.n < v_lim
  RETURNING rl.n INTO v_n;

  RETURN v_n IS NOT NULL;
END
$$;

-- 3.5 NONCE S2S -- consumo unico.
--     unique_violation acotada a la constraint EXACTA: cualquier otra se relanza.
DROP FUNCTION IF EXISTS api_precios_nonce_consumir(TEXT, UUID);
CREATE FUNCTION api_precios_nonce_consumir(p_client_id TEXT, p_nonce UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE v_con TEXT;
BEGIN
  BEGIN
    INSERT INTO public.api_precios_nonce_s2s (client_id, nonce)
    VALUES (p_client_id, p_nonce);
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
    IF v_con IS DISTINCT FROM 'pk_api_precios_nonce_s2s' THEN
      RAISE;
    END IF;
    RETURN FALSE;
  END;
  RETURN TRUE;
END
$$;

-- 3.6 VALIDACION ESCALAR MINIMA (pre-admision).
--     Barata: enums + regex sobre strings cortos. NO parsea el payload.
--     Combinaciones por accion:
--       cotizar  : exige payload         / prohibe idem_key y cotizacion_id
--       congelar : exige payload+idem_key/ prohibe cotizacion_id
--       obtener  : exige cotizacion_id   / prohibe payload e idem_key
--     Devuelve NULL si OK, o el codigo de error.
DROP FUNCTION IF EXISTS api_precios_validar_admision(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID);
CREATE FUNCTION api_precios_validar_admision(
  p_accion        TEXT,
  p_superficie    TEXT,
  p_sujeto        TEXT,
  p_nonce         UUID,
  p_payload_txt   TEXT,
  p_idem_key      UUID,
  p_cotizacion_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF p_accion IS NULL OR p_accion NOT IN ('cotizar','congelar','obtener') THEN
    RETURN 'accion_invalida';
  END IF;

  -- F3 estructural: B4-0A nace S2S-only. 'web' no se acepta hasta B4-0C.
  IF p_superficie IS DISTINCT FROM 's2s' THEN
    RETURN 'superficie_invalida';
  END IF;
  IF p_sujeto IS DISTINCT FROM 'whatsapp' THEN
    RETURN 'sujeto_invalido';
  END IF;

  IF p_nonce IS NULL THEN
    RETURN 'nonce_requerido';
  END IF;

  IF p_accion = 'cotizar' THEN
    IF p_payload_txt IS NULL   THEN RETURN 'payload_requerido';       END IF;
    IF p_idem_key IS NOT NULL  THEN RETURN 'idem_key_no_admitida';    END IF;
    IF p_cotizacion_id IS NOT NULL THEN RETURN 'cotizacion_id_no_admitida'; END IF;

  ELSIF p_accion = 'congelar' THEN
    IF p_payload_txt IS NULL   THEN RETURN 'payload_requerido';       END IF;
    IF p_idem_key IS NULL      THEN RETURN 'idem_key_requerida';      END IF;
    -- UUID v4 RFC 4122 (version + variante). El cast a UUID no valida la version.
    IF p_idem_key::TEXT !~* '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
      RETURN 'idem_key_no_v4';
    END IF;
    IF p_cotizacion_id IS NOT NULL THEN RETURN 'cotizacion_id_no_admitida'; END IF;

  ELSE  -- obtener
    IF p_cotizacion_id IS NULL   THEN RETURN 'cotizacion_id_requerida'; END IF;
    IF p_payload_txt IS NOT NULL THEN RETURN 'payload_no_admitido';     END IF;
    IF p_idem_key IS NOT NULL    THEN RETURN 'idem_key_no_admitida';    END IF;
  END IF;

  RETURN NULL;
END
$$;

-- 3.7 VALIDACION PROFUNDA DEL PAYLOAD (post-ticket).
--     Cotas ESTRUCTURALES: son la defensa server-side real de computo.
--       span <= 30 noches | horizonte <= hoy_ART + 540 | fecha_in >= hoy_ART | personas 1..20
--     reject-unknown: 'modo' y 'canal' NO son claves admitidas.
--       -> modo='online' se FUERZA server-side; canal se DERIVA de la superficie.
--     Fecha "hoy" en America/Argentina/Buenos_Aires (nunca UTC).
--     Devuelve {ok:true, payload:<normalizado>} o {ok:false, campo:<...>}.
DROP FUNCTION IF EXISTS api_precios_validar_payload(JSONB, TEXT);
CREATE FUNCTION api_precios_validar_payload(p_payload JSONB, p_canal TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  c_permitidas CONSTANT TEXT[] := ARRAY['id_cabana','fecha_in','fecha_out','personas'];
  c_span_max   CONSTANT INTEGER := 30;
  c_horiz_max  CONSTANT INTEGER := 540;
  c_pers_max   CONSTANT INTEGER := 20;
  v_k      TEXT;
  v_hoy    DATE;
  v_cab    BIGINT;
  v_in     DATE;
  v_out    DATE;
  v_pers   INTEGER;
  v_activa BOOLEAN;
BEGIN
  IF p_payload IS NULL OR pg_catalog.jsonb_typeof(p_payload) <> 'object' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'payload');
  END IF;

  -- reject-unknown (allowlist estricta de claves)
  FOR v_k IN SELECT pg_catalog.jsonb_object_keys(p_payload) LOOP
    IF NOT (v_k = ANY (c_permitidas)) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', v_k);
    END IF;
  END LOOP;

  FOREACH v_k IN ARRAY c_permitidas LOOP
    IF NOT (p_payload ? v_k) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', v_k);
    END IF;
  END LOOP;

  -- id_cabana
  IF pg_catalog.jsonb_typeof(p_payload->'id_cabana') <> 'number' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'id_cabana');
  END IF;
  v_cab := (p_payload->>'id_cabana')::BIGINT;
  IF v_cab < 1 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'id_cabana');
  END IF;

  -- personas
  IF pg_catalog.jsonb_typeof(p_payload->'personas') <> 'number' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'personas');
  END IF;
  v_pers := (p_payload->>'personas')::INTEGER;
  IF v_pers < 1 OR v_pers > c_pers_max THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'personas');
  END IF;

  -- fechas: YMD real con round-trip
  BEGIN
    v_in  := (p_payload->>'fecha_in')::DATE;
    v_out := (p_payload->>'fecha_out')::DATE;
  EXCEPTION WHEN OTHERS THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha');
  END;

  IF pg_catalog.to_char(v_in,  'YYYY-MM-DD') IS DISTINCT FROM (p_payload->>'fecha_in')
     OR pg_catalog.to_char(v_out, 'YYYY-MM-DD') IS DISTINCT FROM (p_payload->>'fecha_out') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_formato');
  END IF;

  -- fecha_out es EXCLUSIVE
  IF v_out <= v_in THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_out');
  END IF;

  -- COTA ESTRUCTURAL 1: span
  IF (v_out - v_in) > c_span_max THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'span');
  END IF;

  -- COTA ESTRUCTURAL 2/3: ventana temporal, en horario de Argentina
  v_hoy := (pg_catalog.now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF v_in < v_hoy THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'fecha_in_pasada');
  END IF;
  IF v_out > (v_hoy + c_horiz_max) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'horizonte');
  END IF;

  -- cabana existente y activa
  SELECT cb.activa INTO v_activa
    FROM public.cabanas cb
   WHERE cb.id_cabana = v_cab;
  IF NOT FOUND OR v_activa IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'campo', 'id_cabana');
  END IF;

  -- normalizado: canal DERIVADO, modo FORZADO
  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'payload', pg_catalog.jsonb_build_object(
      'id_cabana', v_cab,
      'fecha_in',  pg_catalog.to_char(v_in,  'YYYY-MM-DD'),
      'fecha_out', pg_catalog.to_char(v_out, 'YYYY-MM-DD'),
      'personas',  v_pers,
      'canal',     p_canal,
      'modo',      'online'
    ));
END
$$;

-- ===========================================================================
-- 4) CORE OWNER-ONLY -- SIN GRANT AL ROL.
--    Unica puerta al motor: los *_exponer, que siempre pagan admision.
-- ===========================================================================

-- 4.1 cotizar -- STABLE. CERO MUTACION. Aca vive el oraculo puro de negocio.
DROP FUNCTION IF EXISTS api_precios_cotizar_core(JSONB);
CREATE FUNCTION api_precios_cotizar_core(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  PERFORM public.api_precios_guard_sesion();
  PERFORM public.api_precios_gate_ambiente();
  RETURN public.precios_cotizar(p_payload);
END
$$;

-- 4.2 obtener -- STABLE.
DROP FUNCTION IF EXISTS api_precios_obtener_core(UUID);
CREATE FUNCTION api_precios_obtener_core(p_cotizacion_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  PERFORM public.api_precios_guard_sesion();
  PERFORM public.api_precios_gate_ambiente();
  RETURN public.precios_cotizacion_obtener(p_cotizacion_id);
END
$$;

-- 4.3 congelar -- unico writer de negocio. Idempotencia por efecto de escritura.
--     POLITICA: la key se consume SOLO si congelada=true.
--       congelada=false u ok=false -> NO hay fila de idempotencia (no hubo escritura).
--       error tecnico              -> el savepoint revierte todo; la key NO se consume.
--     CARRERA: la resuelve el UNIQUE. El bloque EXCEPTION revierte tambien el INSERT
--       que precios_cotizar_congelar hizo en cotizaciones_precio -> cero huerfanas.
--     unique_violation acotada a pk_api_precios_idempotencia: cualquier otra se RELANZA
--       (un unique de cotizaciones_precio jamas debe leerse como replay).
DROP FUNCTION IF EXISTS api_precios_congelar_core(JSONB, UUID, TEXT);
CREATE FUNCTION api_precios_congelar_core(p_payload JSONB, p_idem_key UUID, p_scope TEXT)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_canon TEXT;
  v_hash  TEXT;
  v_row   RECORD;
  v_q     JSONB;
  v_cid   UUID;
  v_exp   TIMESTAMPTZ;
  v_con   TEXT;
BEGIN
  PERFORM public.api_precios_guard_sesion();
  PERFORM public.api_precios_gate_ambiente();

  -- canon de NEGOCIO (distinto del canon del ticket)
  v_canon := 'b4v1|' || (p_payload->>'id_cabana')
                     || '|' || (p_payload->>'fecha_in')
                     || '|' || (p_payload->>'fecha_out')
                     || '|' || (p_payload->>'personas')
                     || '|' || (p_payload->>'canal')
                     || '|online';
  v_hash := pg_catalog.encode(pg_catalog.sha256(v_canon::BYTEA), 'hex');

  -- FAST PATH (no decide: el UNIQUE sigue siendo la red)
  SELECT i.canon_hash, i.cotizacion_id, i.resultado_motor_privado
    INTO v_row
    FROM public.api_precios_idempotencia i
   WHERE i.scope = p_scope AND i.idempotency_key = p_idem_key;

  IF FOUND THEN
    IF v_row.canon_hash IS DISTINCT FROM v_hash THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'conflicto');
    END IF;
    -- vigencia contra la FUENTE DE VERDAD (cotizaciones_precio), NO contra el snapshot
    -- congelado: el snapshot guarda el expires_at del momento del congelamiento y podria
    -- quedar stale. PG es la autoridad del reloj y del expires_at.
    SELECT cp.expires_at INTO v_exp
      FROM public.cotizaciones_precio cp
     WHERE cp.cotizacion_id = v_row.cotizacion_id;
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'via', 'replay',
      'vigente', (v_exp > pg_catalog.now()),
      'motor', v_row.resultado_motor_privado);
  END IF;

  -- SLOW PATH
  BEGIN
    v_q := public.precios_cotizar_congelar(p_payload);

    -- sin efecto de escritura -> NO se consume la key
    IF COALESCE((v_q->>'congelada')::BOOLEAN, FALSE) IS NOT TRUE THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'via', 'nuevo',
                                           'vigente', FALSE, 'motor', v_q);
    END IF;

    v_cid := (v_q->>'cotizacion_id')::UUID;

    INSERT INTO public.api_precios_idempotencia
      (scope, idempotency_key, canon_hash, cotizacion_id, resultado_motor_privado)
    VALUES (p_scope, p_idem_key, v_hash, v_cid, v_q);

  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
    IF v_con IS DISTINCT FROM 'pk_api_precios_idempotencia' THEN
      RAISE;
    END IF;

    -- perdi la carrera. El rollback al savepoint ya revirtio MI INSERT en
    -- cotizaciones_precio. Leo la fila del ganador (ya commiteada: el UNIQUE espero).
    SELECT i.canon_hash, i.cotizacion_id, i.resultado_motor_privado
      INTO v_row
      FROM public.api_precios_idempotencia i
     WHERE i.scope = p_scope AND i.idempotency_key = p_idem_key;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'idempotencia_inconsistente' USING ERRCODE = 'VDT04';
    END IF;
    IF v_row.canon_hash IS DISTINCT FROM v_hash THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'conflicto');
    END IF;
    SELECT cp.expires_at INTO v_exp
      FROM public.cotizaciones_precio cp
     WHERE cp.cotizacion_id = v_row.cotizacion_id;
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'via', 'replay',
      'vigente', (v_exp > pg_catalog.now()),
      'motor', v_row.resultado_motor_privado);
  END;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'via', 'nuevo',
    'vigente', ((v_q->>'expires_at')::TIMESTAMPTZ > pg_catalog.now()),
    'motor', v_q);
END
$$;

-- ===========================================================================
-- 5) ADMISION (TXN 1) -- la unica funcion que emite tickets.
--    proconfig: lock_timeout 1s (COTA DURA: se reimpone aunque el caller haga
--    SET lock_timeout=0 -- verificado en harness).
--    statement_timeout NO va en proconfig: es INERTE (no arma ni baja el timer;
--    verificado). Lo impone la Edge con SET LOCAL dentro de la transaccion.
-- ===========================================================================
DROP FUNCTION IF EXISTS api_precios_admitir(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID, UUID);
CREATE FUNCTION api_precios_admitir(
  p_accion         TEXT,
  p_superficie     TEXT,
  p_sujeto         TEXT,
  p_nonce          UUID,
  p_payload_txt    TEXT,
  p_idem_key       UUID,
  p_cotizacion_id  UUID,
  p_correlation_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
SET lock_timeout = '1s'
AS $$
DECLARE
  v_err     TEXT;
  v_payload JSONB;
  v_hash    TEXT;
  v_tid     UUID;
  v_state   TEXT;
  v_con     TEXT;
BEGIN
  -- 1) D3   (primera sentencia ejecutable)
  PERFORM public.api_precios_guard_sesion();
  -- 2) ambiente
  PERFORM public.api_precios_gate_ambiente();

  -- 3) validacion escalar minima (barata; no parsea el payload)
  v_err := public.api_precios_validar_admision(
             p_accion, p_superficie, p_sujeto, p_nonce,
             p_payload_txt, p_idem_key, p_cotizacion_id);
  IF v_err IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'admision_invalida', 'campo', v_err);
  END IF;

  -- ===== ADMISION: FUERA de todo savepoint =====
  -- 4) cuota GLOBAL primero  (orden de locks fijo: global -> sujeto -> nonce)
  IF NOT public.api_precios_rl_consumir(p_accion || '_global', '_global') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'rate_limited', 'cubeta', 'global');
  END IF;

  -- 5) cuota SUJETO  (la global YA quedo consumida)
  IF NOT public.api_precios_rl_consumir(p_accion || '_' || p_superficie, p_sujeto) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'rate_limited', 'cubeta', 'sujeto');
  END IF;

  -- 6) NONCE  (un replay CONSUME cuota: decision explicita)
  IF NOT public.api_precios_nonce_consumir(p_sujeto, p_nonce) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'nonce_replay');
  END IF;

  -- ===== SUBBLOQUE: solo parse/hash/ticket. Revertirlo NO devuelve cuota ni nonce =====
  BEGIN
    -- tamano DESPUES de cobrar: el sobredimensionado paga.
    -- NO es un limite de transporte frente a acceso directo a PG (el parametro ya viajo);
    -- evita el parse jsonb, el hash y el ticket. El limite de transporte lo impone la Edge.
    IF p_payload_txt IS NOT NULL AND pg_catalog.octet_length(p_payload_txt) > 8192 THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'admision_invalida',
                                           'campo', 'payload_size');
    END IF;

    IF p_payload_txt IS NULL THEN
      v_payload := NULL;
    ELSE
      v_payload := p_payload_txt::JSONB;     -- puede lanzar invalid_text_representation
      IF pg_catalog.jsonb_typeof(v_payload) <> 'object' THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'admision_invalida',
                                             'campo', 'payload_tipo');
      END IF;
    END IF;

    v_hash := public.api_precios_ticket_hash_v1(
                p_accion, p_superficie, p_sujeto, v_payload, p_idem_key, p_cotizacion_id);
    v_tid  := pg_catalog.gen_random_uuid();

    INSERT INTO public.api_precios_ticket
      (ticket_id, accion, superficie, sujeto, request_hash, correlation_id, expires_at)
    VALUES
      (v_tid, p_accion, p_superficie, p_sujeto, v_hash, p_correlation_id,
       pg_catalog.now() + INTERVAL '30 seconds');

  EXCEPTION
    WHEN SQLSTATE 'VDT01' THEN
      RAISE;
    WHEN invalid_text_representation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'admision_invalida',
                                           'campo', 'payload_json');
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME;
      RAISE LOG 'B4 rutina=api_precios_admitir corr=% sqlstate=% constraint=%',
                p_correlation_id, v_state, COALESCE(v_con, '-');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
  END;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'ticket_id', v_tid);
END
$$;

-- ===========================================================================
-- 6) EJECUCION (TXN 2) -- 3 entrypoints con ticket.
--    Sin ticket valido no se llega a ningun core.
--    correlation_id NO viaja por firma: se lee de la fila del ticket
--    (no puede diferir del de admision).
-- ===========================================================================

-- 6.1 cotizar
DROP FUNCTION IF EXISTS api_precios_cotizar_exponer(UUID, JSONB);
CREATE FUNCTION api_precios_cotizar_exponer(p_ticket UUID, p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_sup TEXT; v_suj TEXT; v_ht TEXT; v_corr UUID;
  v_hc TEXT; v_canal TEXT; v_v JSONB; v_res JSONB;
  v_state TEXT; v_con TEXT;
BEGIN
  PERFORM public.api_precios_guard_sesion();    -- D3, FUERA del subbloque
  PERFORM public.api_precios_gate_ambiente();

  -- consumo atomico single-use, FUERA del subbloque
  UPDATE public.api_precios_ticket t
     SET consumed_at = pg_catalog.now()
   WHERE t.ticket_id   = p_ticket
     AND t.consumed_at IS NULL
     AND t.expires_at  > pg_catalog.now()
     AND t.accion      = 'cotizar'
  RETURNING t.superficie, t.sujeto, t.request_hash, t.correlation_id
       INTO v_sup, v_suj, v_ht, v_corr;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
  END IF;

  -- binding. Mismatch -> el ticket YA quedo consumido: SE QUEMA.
  v_hc := public.api_precios_ticket_hash_v1('cotizar', v_sup, v_suj, p_payload, NULL, NULL);
  IF v_hc IS DISTINCT FROM v_ht THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
  END IF;

  v_canal := CASE WHEN v_sup = 's2s' AND v_suj = 'whatsapp' THEN 'whatsapp'
                  WHEN v_sup = 'web' THEN 'web' ELSE NULL END;
  IF v_canal IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
  END IF;

  -- ===== SUBBLOQUE PROTEGIDO: validacion profunda + core =====
  BEGIN
    v_v := public.api_precios_validar_payload(p_payload, v_canal);
    IF COALESCE((v_v->>'ok')::BOOLEAN, FALSE) IS NOT TRUE THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'payload_invalido',
                                           'campo', v_v->>'campo');
    END IF;

    v_res := public.api_precios_cotizar_core(v_v->'payload');

  EXCEPTION
    WHEN SQLSTATE 'VDT01' THEN
      RAISE;   -- rollback de TXN2 -> el ticket VUELVE a estar libre -> la Edge recicla y reintenta 1 vez
    WHEN query_canceled THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME;
      RAISE LOG 'B4 rutina=api_precios_cotizar_exponer corr=% sqlstate=% constraint=%',
                v_corr, v_state, COALESCE(v_con, '-');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
  END;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'via', 'nuevo', 'motor', v_res);
END
$$;

-- 6.2 congelar
DROP FUNCTION IF EXISTS api_precios_congelar_exponer(UUID, JSONB, UUID);
CREATE FUNCTION api_precios_congelar_exponer(p_ticket UUID, p_payload JSONB, p_idem_key UUID)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_sup TEXT; v_suj TEXT; v_ht TEXT; v_corr UUID;
  v_hc TEXT; v_canal TEXT; v_v JSONB; v_res JSONB;
  v_state TEXT; v_con TEXT;
BEGIN
  PERFORM public.api_precios_guard_sesion();
  PERFORM public.api_precios_gate_ambiente();

  UPDATE public.api_precios_ticket t
     SET consumed_at = pg_catalog.now()
   WHERE t.ticket_id   = p_ticket
     AND t.consumed_at IS NULL
     AND t.expires_at  > pg_catalog.now()
     AND t.accion      = 'congelar'
  RETURNING t.superficie, t.sujeto, t.request_hash, t.correlation_id
       INTO v_sup, v_suj, v_ht, v_corr;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
  END IF;

  -- el idem_key ENTRA al canon del ticket
  v_hc := public.api_precios_ticket_hash_v1('congelar', v_sup, v_suj, p_payload, p_idem_key, NULL);
  IF v_hc IS DISTINCT FROM v_ht THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
  END IF;

  v_canal := CASE WHEN v_sup = 's2s' AND v_suj = 'whatsapp' THEN 'whatsapp'
                  WHEN v_sup = 'web' THEN 'web' ELSE NULL END;
  IF v_canal IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
  END IF;

  BEGIN
    v_v := public.api_precios_validar_payload(p_payload, v_canal);
    IF COALESCE((v_v->>'ok')::BOOLEAN, FALSE) IS NOT TRUE THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'payload_invalido',
                                           'campo', v_v->>'campo');
    END IF;

    v_res := public.api_precios_congelar_core(
               v_v->'payload', p_idem_key, 'precios.congelar:' || v_canal);

  EXCEPTION
    WHEN SQLSTATE 'VDT01' THEN
      RAISE;
    WHEN query_canceled THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME;
      RAISE LOG 'B4 rutina=api_precios_congelar_exponer corr=% sqlstate=% constraint=%',
                v_corr, v_state, COALESCE(v_con, '-');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
  END;

  RETURN v_res;
END
$$;

-- 6.3 obtener
DROP FUNCTION IF EXISTS api_precios_obtener_exponer(UUID, UUID);
CREATE FUNCTION api_precios_obtener_exponer(p_ticket UUID, p_cotizacion_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_sup TEXT; v_suj TEXT; v_ht TEXT; v_corr UUID;
  v_hc TEXT; v_res JSONB;
  v_state TEXT; v_con TEXT;
BEGIN
  PERFORM public.api_precios_guard_sesion();
  PERFORM public.api_precios_gate_ambiente();

  UPDATE public.api_precios_ticket t
     SET consumed_at = pg_catalog.now()
   WHERE t.ticket_id   = p_ticket
     AND t.consumed_at IS NULL
     AND t.expires_at  > pg_catalog.now()
     AND t.accion      = 'obtener'
  RETURNING t.superficie, t.sujeto, t.request_hash, t.correlation_id
       INTO v_sup, v_suj, v_ht, v_corr;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
  END IF;

  -- el cotizacion_id ENTRA al canon del ticket
  v_hc := public.api_precios_ticket_hash_v1('obtener', v_sup, v_suj, NULL, NULL, p_cotizacion_id);
  IF v_hc IS DISTINCT FROM v_ht THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'ticket_invalido');
  END IF;

  BEGIN
    v_res := public.api_precios_obtener_core(p_cotizacion_id);
  EXCEPTION
    WHEN SQLSTATE 'VDT01' THEN
      RAISE;
    WHEN query_canceled THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'timeout');
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME;
      RAISE LOG 'B4 rutina=api_precios_obtener_exponer corr=% sqlstate=% constraint=%',
                v_corr, v_state, COALESCE(v_con, '-');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'error_interno');
  END;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'via', 'nuevo', 'motor', v_res);
END
$$;

-- ===========================================================================
-- 7) PROBE TEMPORAL -- solo para B4-0B (G4). Lee de verdad, schema-qualified.
--    Se REVOCA y se DROPEA al cerrar B4-0B (runsheet, paso 8).
-- ===========================================================================
DROP FUNCTION IF EXISTS api_precios_probe_ambiente();
CREATE FUNCTION api_precios_probe_ambiente()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE v_amb TEXT;
BEGIN
  PERFORM public.api_precios_guard_sesion();
  SELECT cg.valor INTO v_amb
    FROM public.configuracion_general cg
   WHERE cg.clave = 'ambiente';
  RETURN v_amb;
END
$$;

-- ===========================================================================
-- 8) PURGAS OWNER-ONLY  (4).  Sin D3: las corre pg_cron (sesion limpia) o postgres;
--    el rol NO puede ejecutarlas. Son ademas el vehiculo del smoke T4 (D1/D2 aislado:
--    no llaman a B3).
--    Gate de ambiente DENTRO de cada una: si el objeto se promoviera por error, aborta.
-- ===========================================================================
DROP FUNCTION IF EXISTS api_precios_ticket_purgar();
CREATE FUNCTION api_precios_ticket_purgar()
RETURNS INTEGER
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE v_n INTEGER;
BEGIN
  PERFORM public.api_precios_gate_ambiente();
  DELETE FROM public.api_precios_ticket
   WHERE expires_at < pg_catalog.now() - INTERVAL '5 minutes';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$$;

DROP FUNCTION IF EXISTS api_precios_nonce_purgar();
CREATE FUNCTION api_precios_nonce_purgar()
RETURNS INTEGER
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE v_n INTEGER;
BEGIN
  PERFORM public.api_precios_gate_ambiente();
  DELETE FROM public.api_precios_nonce_s2s
   WHERE created_at < pg_catalog.now() - INTERVAL '10 minutes';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$$;

DROP FUNCTION IF EXISTS api_precios_rl_purgar();
CREATE FUNCTION api_precios_rl_purgar()
RETURNS INTEGER
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE v_n INTEGER;
BEGIN
  PERFORM public.api_precios_gate_ambiente();
  DELETE FROM public.api_precios_rate_limit
   WHERE ventana < pg_catalog.now() - INTERVAL '1 hour';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$$;

DROP FUNCTION IF EXISTS api_precios_idempotencia_purgar();
CREATE FUNCTION api_precios_idempotencia_purgar()
RETURNS INTEGER
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE v_n INTEGER;
BEGIN
  PERFORM public.api_precios_gate_ambiente();
  DELETE FROM public.api_precios_idempotencia
   WHERE created_at < pg_catalog.now() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$$;

-- ===========================================================================
-- 9) ACL FINAL
--    Runtime del rol: 4 EXECUTE (+1 temporal de probe). CERO privilegios de tabla.
--    El rol esta EXPLICITAMENTE nombrado en los REVOKE de core/helpers/purgas:
--    sin EXECUTE sobre el core, NO PUEDE saltear la admision.
-- ===========================================================================
REVOKE EXECUTE ON FUNCTION
  api_precios_guard_sesion(),
  api_precios_gate_ambiente(),
  api_precios_ticket_hash_v1(TEXT, TEXT, TEXT, JSONB, UUID, UUID),
  api_precios_rl_consumir(TEXT, TEXT),
  api_precios_nonce_consumir(TEXT, UUID),
  api_precios_validar_admision(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID),
  api_precios_validar_payload(JSONB, TEXT),
  api_precios_cotizar_core(JSONB),
  api_precios_congelar_core(JSONB, UUID, TEXT),
  api_precios_obtener_core(UUID),
  api_precios_ticket_purgar(),
  api_precios_nonce_purgar(),
  api_precios_rl_purgar(),
  api_precios_idempotencia_purgar()
  FROM PUBLIC, anon, authenticated, service_role, vita_precios_api;

REVOKE EXECUTE ON FUNCTION
  api_precios_admitir(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID, UUID),
  api_precios_cotizar_exponer(UUID, JSONB),
  api_precios_congelar_exponer(UUID, JSONB, UUID),
  api_precios_obtener_exponer(UUID, UUID),
  api_precios_probe_ambiente()
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
  api_precios_admitir(TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID, UUID),
  api_precios_cotizar_exponer(UUID, JSONB),
  api_precios_congelar_exponer(UUID, JSONB, UUID),
  api_precios_obtener_exponer(UUID, UUID),
  api_precios_probe_ambiente()
  TO vita_precios_api;

-- ---------------------------------------------------------------------------
-- 9.bis) DEFENSA EN PROFUNDIDAD SOBRE EL MOTOR B3
--
-- El rol HEREDA de PUBLIC. Si alguna de las 13 precios_* conservara EXECUTE
-- a PUBLIC, vita_precios_api lo heredaria y podria llamar al motor DIRECTAMENTE,
-- salteando la admision entera (cuota + nonce + ticket). Un REVOKE dirigido al
-- rol NO alcanza: hay que revocarlo de PUBLIC.
--
-- Este REVOKE es IDEMPOTENTE: B3 ya deberia tenerlo aplicado. Si cambia algo,
-- es que habia un agujero.
-- NO altera prosrc -> el fingerprint de B3 (098f2fe7916e11ffa78cff37622b9064)
-- queda INTACTO. El fingerprint se calcula sobre el cuerpo, no sobre la ACL.
-- ---------------------------------------------------------------------------
DO $b3$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_catalog.pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND p.proname LIKE 'precios\_%'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || r.sig ||
            ' FROM PUBLIC, anon, authenticated, service_role, vita_precios_api';
  END LOOP;
END
$b3$;

COMMIT;

-- ===========================================================================
-- 10) JOBS pg_cron  (4).  FUERA de la transaccion: cron.schedule commitea aparte.
--     Retenciones maximas reales (TTL + peor caso de cadencia):
--       ticket        30 s  + 5 min elegibilidad + 5 min cron  ~= 10,5 min
--       nonce         10 min                     + 5 min cron  ~= 15 min
--       rate_limit    60 min                     + 10 min cron ~= 70 min
--       idempotencia  24 h                       + 1 h cron    ~= 25 h
--     NO hay watchdog de backends: retirado por decision explicita.
-- ===========================================================================
DO $cron$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT jobname FROM cron.job WHERE jobname LIKE 'b4_purga_%' LOOP
    PERFORM cron.unschedule(r.jobname);
  END LOOP;
END
$cron$;

SELECT cron.schedule('b4_purga_ticket',       '*/5 * * * *',  'SELECT public.api_precios_ticket_purgar();');
SELECT cron.schedule('b4_purga_nonce_s2s',    '*/5 * * * *',  'SELECT public.api_precios_nonce_purgar();');
SELECT cron.schedule('b4_purga_rate_limit',   '*/10 * * * *', 'SELECT public.api_precios_rl_purgar();');
SELECT cron.schedule('b4_purga_idempotencia', '0 * * * *',    'SELECT public.api_precios_idempotencia_purgar();');

-- ============================================================================
-- FIN B4-0A.
-- Siguiente: el ALTER de password (runsheet paso 3) y despues B4_0A_VERIFY.sql.
-- ============================================================================
