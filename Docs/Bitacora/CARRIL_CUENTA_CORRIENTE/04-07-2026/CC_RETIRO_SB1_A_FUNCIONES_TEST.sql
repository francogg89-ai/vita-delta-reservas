-- ============================================================================
-- CC_RETIRO_SB1_A_FUNCIONES_TEST.sql
-- Frente: Cuenta Corriente ESCRITURA (retiros desde saldo vivo)
-- Sub-bloque 1: tabla portal_idempotencia_cc + funcion de negocio
--   registrar_retiro_desde_saldo_vivo + wrapper portal_registrar_retiro(jsonb).
-- Entorno: TEST unicamente (gate anti-OPS por configuracion_general('ambiente')='test').
-- Naturaleza: migracion ATOMICA. Preflight fail-fast (sin IF NOT EXISTS, sin
--   CREATE OR REPLACE): si algo ya existe, ABORTA sin cambios. Si cualquier paso
--   falla, ROLLBACK total.
-- Correr el script COMPLETO (sin seleccion) en el SQL Editor de Supabase (L-8A-01).
-- ----------------------------------------------------------------------------
-- Convencion de errores de dominio (clase SQLSTATE 'VD' = Vita Delta):
--   VD001 = saldo insuficiente ; VD002 = argumento invalido de negocio.
--   El wrapper mapea VD001->saldo_insuficiente y VD002->payload_invalido por
--   SQLSTATE (sin parsear mensajes).
-- NOTA D5: el D5 canonico de la PARTE D valida portal_usuarios/portal_idempotencia,
--   no estos objetos nuevos; su extension va en el cierre v1.11.0. La verificacion
--   de este sub-bloque es CC_RETIRO_SB1_B_VERIFY_TEST.sql.
-- ============================================================================

BEGIN;

-- ---- Gate anti-OPS (solo TEST) --------------------------------------------
DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE ambiente=% (esperado test) -- abortado, sin cambios', COALESCE(v_amb, '(null)');
  END IF;
END $gate$;

-- ---- Preflight 1: prerrequisitos presentes (SB0 aplicado, motor CC vivo) ---
DO $prereq$
DECLARE
  v_pu_id_socio boolean;
BEGIN
  IF to_regclass('public.socios')            IS NULL THEN RAISE EXCEPTION 'prereq: socios ausente'; END IF;
  IF to_regclass('public.movimientos_socio') IS NULL THEN RAISE EXCEPTION 'prereq: movimientos_socio ausente'; END IF;
  IF to_regclass('public.portal_usuarios')   IS NULL THEN RAISE EXCEPTION 'prereq: portal_usuarios ausente'; END IF;
  IF to_regprocedure('public.cuenta_corriente_viva(date, numeric)') IS NULL THEN
    RAISE EXCEPTION 'prereq: cuenta_corriente_viva(date,numeric) ausente'; END IF;
  IF to_regprocedure('public.pct_operativo_vigente()') IS NULL THEN
    RAISE EXCEPTION 'prereq: pct_operativo_vigente() ausente'; END IF;
  SELECT EXISTS (SELECT 1 FROM pg_attribute
                  WHERE attrelid = 'public.portal_usuarios'::regclass
                    AND attname = 'id_socio' AND NOT attisdropped) INTO v_pu_id_socio;
  IF NOT v_pu_id_socio THEN
    RAISE EXCEPTION 'prereq: portal_usuarios.id_socio ausente -- SB0 no aplicado';
  END IF;
END $prereq$;

-- ---- Preflight 2: fail-fast si SB1 ya fue aplicado (total o parcial) -------
DO $drift$
DECLARE
  v_tbl  oid  := to_regclass('public.portal_idempotencia_cc');
  v_seq  oid  := to_regclass('public.portal_idempotencia_cc_id_registro_seq');
  v_f1   oid  := to_regprocedure('public.registrar_retiro_desde_saldo_vivo(bigint, numeric, text, text, text)');
  v_f2   oid  := to_regprocedure('public.portal_registrar_retiro(jsonb)');
  v_cons text;
BEGIN
  IF v_tbl IS NOT NULL THEN RAISE EXCEPTION 'DRIFT: portal_idempotencia_cc ya existe -- abortado, sin cambios'; END IF;
  IF v_seq IS NOT NULL THEN RAISE EXCEPTION 'DRIFT: secuencia portal_idempotencia_cc_id_registro_seq ya existe -- abortado'; END IF;
  IF v_f1  IS NOT NULL THEN RAISE EXCEPTION 'DRIFT: registrar_retiro_desde_saldo_vivo ya existe -- abortado'; END IF;
  IF v_f2  IS NOT NULL THEN RAISE EXCEPTION 'DRIFT: portal_registrar_retiro(jsonb) ya existe -- abortado'; END IF;

  SELECT string_agg(conname, ', ' ORDER BY conname) INTO v_cons
    FROM pg_constraint
   WHERE conname IN ('uq_portal_idem_cc_nonce','uq_portal_idem_cc_action_key','fk_portal_idem_cc_mov',
                     'chk_portal_idem_cc_action_ne','chk_portal_idem_cc_actor_ne','chk_portal_idem_cc_source_ne',
                     'chk_portal_idem_cc_nonce_ne','chk_portal_idem_cc_idem_ne','chk_portal_idem_cc_rol',
                     'chk_portal_idem_cc_estado');
  IF v_cons IS NOT NULL THEN
    RAISE EXCEPTION 'DRIFT: constraints con nombre conflictivo ya existen: % -- abortado', v_cons;
  END IF;
END $drift$;

-- ===========================================================================
-- 1) TABLA portal_idempotencia_cc  (espejo de portal_idempotencia; FK a
--    movimientos_socio; rol socio-only). CREATE TABLE (no IF NOT EXISTS).
-- ===========================================================================
CREATE TABLE public.portal_idempotencia_cc (
  id_registro      bigserial   PRIMARY KEY,
  action           text        NOT NULL,
  actor            text        NOT NULL,
  rol              text        NOT NULL,
  source_event     text        NOT NULL,
  nonce            text        NOT NULL,
  idempotency_key  text        NOT NULL,
  payload_norm     jsonb       NOT NULL,
  id_movimiento    bigint      NOT NULL,
  estado           text        NOT NULL DEFAULT 'ok',
  request_ts       bigint,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_portal_idem_cc_nonce      UNIQUE (nonce),
  CONSTRAINT uq_portal_idem_cc_action_key UNIQUE (action, idempotency_key),
  CONSTRAINT fk_portal_idem_cc_mov
    FOREIGN KEY (id_movimiento) REFERENCES public.movimientos_socio(id_movimiento) ON DELETE RESTRICT,
  CONSTRAINT chk_portal_idem_cc_action_ne CHECK (length(btrim(action)) > 0),
  CONSTRAINT chk_portal_idem_cc_actor_ne  CHECK (length(btrim(actor)) > 0),
  CONSTRAINT chk_portal_idem_cc_source_ne CHECK (length(btrim(source_event)) > 0),
  CONSTRAINT chk_portal_idem_cc_nonce_ne  CHECK (length(btrim(nonce)) > 0),
  CONSTRAINT chk_portal_idem_cc_idem_ne   CHECK (length(btrim(idempotency_key)) > 0),
  CONSTRAINT chk_portal_idem_cc_rol       CHECK (rol = 'socio'),
  CONSTRAINT chk_portal_idem_cc_estado    CHECK (estado = 'ok')
);

COMMENT ON TABLE public.portal_idempotencia_cc IS
  'Cuenta Corriente / escritura (retiros). Espejo de portal_idempotencia pero FK a movimientos_socio y rol socio-only. nonce UNIQUE=anti-replay; (action,idempotency_key) UNIQUE=idempotencia de negocio; payload_norm+actor=deteccion de conflicto. Interna: sin Data API; la opera solo n8n via postgres.';

-- ---- Hardening tabla + secuencia (interna, sin Data API) -------------------
REVOKE ALL ON public.portal_idempotencia_cc FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE public.portal_idempotencia_cc_id_registro_seq FROM PUBLIC, anon, authenticated, service_role;

-- ===========================================================================
-- 2) FUNCION DE NEGOCIO registrar_retiro_desde_saldo_vivo
--    Valida contra el saldo VIVO (identico a L1/A27) + validaciones defensivas
--    (segura aun llamada directa por SQL autorizado). SIN p_fecha (hoy AR).
-- ===========================================================================
CREATE FUNCTION public.registrar_retiro_desde_saldo_vivo(
  p_id_socio    bigint,
  p_monto       numeric,
  p_medio_pago  text,
  p_creado_por  text,
  p_comentario  text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_saldo numeric;
  v_id    bigint;
  v_hoy   date := (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
BEGIN
  -- Validaciones defensivas de negocio (VD002 = argumento invalido).
  IF p_id_socio IS NULL THEN
    RAISE EXCEPTION 'retiro: p_id_socio nulo' USING ERRCODE = 'VD002';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.socios WHERE id_socio = p_id_socio) THEN
    RAISE EXCEPTION 'retiro: socio % inexistente', p_id_socio USING ERRCODE = 'VD002';
  END IF;
  IF p_monto IS NULL THEN
    RAISE EXCEPTION 'retiro: p_monto nulo' USING ERRCODE = 'VD002';
  END IF;
  IF p_monto <= 0 THEN
    RAISE EXCEPTION 'retiro: monto debe ser positivo (magnitud), recibido %', p_monto USING ERRCODE = 'VD002';
  END IF;
  IF p_monto <> ROUND(p_monto, 2) THEN
    RAISE EXCEPTION 'retiro: monto excede 2 decimales (%)', p_monto USING ERRCODE = 'VD002';
  END IF;
  IF p_medio_pago IS NULL OR p_medio_pago NOT IN ('efectivo','transferencia_bancaria') THEN
    RAISE EXCEPTION 'retiro: medio_pago invalido (%)', COALESCE(p_medio_pago, '(null)') USING ERRCODE = 'VD002';
  END IF;
  IF p_creado_por IS NULL OR btrim(p_creado_por) = '' THEN
    RAISE EXCEPTION 'retiro: creado_por vacio' USING ERRCODE = 'VD002';
  END IF;

  -- Lock por socio (mismo namespace que las escrituras 9H).
  PERFORM pg_advisory_xact_lock(919002, p_id_socio::int);

  -- Saldo VIVO: identico a L1/A27 (misma fuente de pct, mismo hasta = hoy AR).
  SELECT saldo_al_dia INTO v_saldo
    FROM public.cuenta_corriente_viva(NULL, public.pct_operativo_vigente())
   WHERE id_socio = p_id_socio;

  IF NOT FOUND THEN
    -- Controlado: socio sin actividad contable => saldo 0 => no puede retirar.
    RAISE EXCEPTION 'saldo insuficiente (vivo=0, retiro=%)', p_monto USING ERRCODE = 'VD001';
  END IF;
  IF v_saldo - p_monto < 0 THEN
    RAISE EXCEPTION 'saldo insuficiente (vivo=%, retiro=%)', v_saldo, p_monto USING ERRCODE = 'VD001';
  END IF;

  -- Asiento append-only: entra magnitud positiva, se guarda NEGATIVA (chk_mov_signo_debe).
  INSERT INTO public.movimientos_socio (id_socio, fecha, tipo, monto, medio_pago, comentario, creado_por)
  VALUES (p_id_socio, v_hoy, 'retiro', -p_monto, p_medio_pago, p_comentario, p_creado_por)
  RETURNING id_movimiento INTO v_id;

  RETURN v_id;
END
$fn$;

COMMENT ON FUNCTION public.registrar_retiro_desde_saldo_vivo(bigint, numeric, text, text, text) IS
  'Cuenta Corriente / retiro desde saldo VIVO. Lock por socio (919002), valida contra cuenta_corriente_viva(NULL, pct_operativo_vigente()) (identico a L1), inserta retiro append-only con monto NEGATIVO. Errores de dominio: VD001=saldo insuficiente, VD002=argumento invalido. NO reemplaza registrar_retiro (que valida snapshots congelados).';

-- ===========================================================================
-- 3) WRAPPER portal_registrar_retiro(jsonb)  (espeja portal_cargar_gasto_interno)
--    Control inyectado por el gateway (actor/rol/id_socio/nonce, confiable) +
--    idempotency_key del cliente. Vinculo de identidad fuerte id_socio<->actor.
-- ===========================================================================
CREATE FUNCTION public.portal_registrar_retiro(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  c_action       CONSTANT text := 'cuenta_corriente.retirar';
  v_actor        text;
  v_rol          text;
  v_id_socio     bigint;
  v_user_id      uuid;
  v_nonce        text;
  v_idem         text;
  v_req_ts       bigint;
  v_source       text;
  v_monto_raw    text;
  v_monto        numeric(14,2);
  v_medio        text;
  v_comentario   text;
  v_payload_norm jsonb;
  v_pu_user      uuid;
  v_id_mov       bigint;
  v_ex_actor     text;
  v_ex_payload   jsonb;
  v_ex_mov       bigint;
  v_saldo_disp   numeric;
  v_sqlstate     text;
  v_constraint   text;
  v_msg          text;
BEGIN
  -- 1) Control inyectado por el gateway --------------------------------------
  v_actor    := NULLIF(btrim(p_payload->>'actor'), '');
  v_rol      := NULLIF(btrim(p_payload->>'rol'), '');
  v_nonce    := NULLIF(btrim(p_payload->>'nonce'), '');
  v_idem     := NULLIF(btrim(p_payload->>'idempotency_key'), '');
  v_id_socio := CASE WHEN (p_payload->>'id_socio') ~ '^\d+$' THEN (p_payload->>'id_socio')::bigint ELSE NULL END;
  v_user_id  := CASE WHEN (p_payload->>'user_id') ~ '^[0-9a-fA-F-]{36}$' THEN (p_payload->>'user_id')::uuid ELSE NULL END;
  v_req_ts   := CASE WHEN (p_payload->>'request_ts') ~ '^\d+$' THEN (p_payload->>'request_ts')::bigint ELSE NULL END;

  -- actor/rol/nonce/id_socio ausentes = falla de cableado del gateway.
  IF v_actor IS NULL OR v_rol IS NULL OR v_nonce IS NULL OR v_id_socio IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'error_interno',
      'message', 'faltan campos de control inyectados por el gateway',
      'detail', jsonb_build_object('actor', v_actor IS NOT NULL, 'rol', v_rol IS NOT NULL,
                                   'nonce', v_nonce IS NOT NULL, 'id_socio', v_id_socio IS NOT NULL)));
  END IF;

  IF v_rol <> 'socio' THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'rol_no_permitido',
      'message', 'rol fuera del allowlist de cuenta_corriente.retirar',
      'detail', jsonb_build_object('rol', v_rol)));
  END IF;

  IF v_idem IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'payload_invalido',
      'message', 'idempotency_key requerida',
      'detail', jsonb_build_object('campo', 'idempotency_key')));
  END IF;

  -- 1a) VINCULO DE IDENTIDAD: id_socio DEBE pertenecer al actor. Evita que un bug
  --     de gateway (mandar otro id_socio) retire sobre otro socio.
  SELECT user_id INTO v_pu_user
    FROM public.portal_usuarios
   WHERE id_socio = v_id_socio
     AND rol = 'socio'
     AND activo IS TRUE
     AND lower(btrim(nombre)) = lower(btrim(v_actor));
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'error_interno',
      'message', 'identidad inconsistente: id_socio no corresponde al actor',
      'detail', jsonb_build_object('reason', 'identity_mismatch')));
  END IF;
  -- Si el gateway inyecto user_id, exigir que sea la MISMA fila (binding fuerte).
  IF v_user_id IS NOT NULL AND v_user_id IS DISTINCT FROM v_pu_user THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'error_interno',
      'message', 'identidad inconsistente: user_id no corresponde al id_socio/actor',
      'detail', jsonb_build_object('reason', 'user_id_mismatch')));
  END IF;

  v_source := 'portal_a29_' || v_idem;

  -- 2) Negocio: extraccion + validacion (payload_invalido) --------------------
  v_monto_raw  := NULLIF(btrim(p_payload->>'monto'), '');
  v_medio      := NULLIF(btrim(p_payload->>'medio_pago'), '');
  v_comentario := NULLIF(btrim(p_payload->>'comentario'), '');

  -- monto: entero o hasta 2 decimales, sin signo. La validacion TEXTUAL evita el
  -- redondeo silencioso de numeric(14,2) (p.ej. 100.999 NO debe pasar como 101.00).
  IF v_monto_raw IS NULL OR v_monto_raw !~ '^[0-9]+([.][0-9]{1,2})?$' THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'payload_invalido',
      'message', 'monto invalido: entero o hasta 2 decimales, sin signo',
      'detail', jsonb_build_object('campo', 'monto', 'valor', p_payload->>'monto')));
  END IF;
  v_monto := v_monto_raw::numeric(14,2);
  IF v_monto <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'payload_invalido',
      'message', 'monto debe ser mayor a 0',
      'detail', jsonb_build_object('campo', 'monto', 'valor', v_monto)));
  END IF;

  IF v_medio IS NULL OR v_medio NOT IN ('efectivo','transferencia_bancaria') THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'payload_invalido',
      'message', 'medio_pago invalido (MVP: efectivo | transferencia_bancaria)',
      'detail', jsonb_build_object('campo', 'medio_pago', 'valor', v_medio)));
  END IF;

  -- payload_norm canonico: SOLO campos de negocio (define el retiro).
  v_payload_norm := jsonb_build_object(
    'id_socio',   v_id_socio,
    'monto',      v_monto,
    'medio_pago', v_medio,
    'comentario', v_comentario);

  -- 3) Serializa concurrentes con la misma (action,key). hashtext -> (integer,integer).
  PERFORM pg_advisory_xact_lock(hashtext(c_action), hashtext(v_idem));

  -- 3a) Anti-replay por nonce.
  IF EXISTS (SELECT 1 FROM public.portal_idempotencia_cc WHERE nonce = v_nonce) THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'conflicto', 'message', 'nonce ya utilizado',
      'detail', jsonb_build_object('reason', 'nonce_replay')));
  END IF;

  -- 3b) Idempotencia de negocio (action,key): payload_norm + actor.
  SELECT actor, payload_norm, id_movimiento
    INTO v_ex_actor, v_ex_payload, v_ex_mov
    FROM public.portal_idempotencia_cc
   WHERE action = c_action AND idempotency_key = v_idem;
  IF FOUND THEN
    IF v_ex_payload IS DISTINCT FROM v_payload_norm THEN
      RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
        'code', 'conflicto', 'message', 'idempotency_key reutilizada con distinto payload',
        'detail', jsonb_build_object('reason', 'payload_mismatch')));
    END IF;
    IF v_ex_actor IS DISTINCT FROM v_actor THEN
      RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
        'code', 'conflicto', 'message', 'idempotency_key reutilizada con distinto actor',
        'detail', jsonb_build_object('reason', 'actor_mismatch')));
    END IF;
    RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'id_movimiento', v_ex_mov, 'idempotente', true));
  END IF;

  -- 4) Alta nueva: negocio + traza en el MISMO sub-bloque (savepoint).
  BEGIN
    v_id_mov := public.registrar_retiro_desde_saldo_vivo(
                  v_id_socio, v_monto, v_medio, v_actor, v_comentario);

    INSERT INTO public.portal_idempotencia_cc
      (action, actor, rol, source_event, nonce, idempotency_key, payload_norm, id_movimiento, request_ts)
    VALUES
      (c_action, v_actor, v_rol, v_source, v_nonce, v_idem, v_payload_norm, v_id_mov, v_req_ts);
  EXCEPTION
    WHEN SQLSTATE 'VD001' THEN
      -- saldo insuficiente: la key NO se quema (savepoint revierte; no hay fila en _cc).
      -- D5: recien ACA (identidad ya validada arriba) revelamos saldo_disponible.
      SELECT COALESCE(saldo_al_dia, 0) INTO v_saldo_disp
        FROM public.cuenta_corriente_viva(NULL, public.pct_operativo_vigente())
       WHERE id_socio = v_id_socio;
      RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
        'code', 'saldo_insuficiente', 'message', 'saldo insuficiente para el retiro',
        'detail', jsonb_build_object('saldo_disponible', COALESCE(v_saldo_disp, 0),
                                     'monto_solicitado', v_monto)));
    WHEN SQLSTATE 'VD002' THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
        'code', 'payload_invalido', 'message', 'argumento de negocio invalido',
        'detail', jsonb_build_object('reason', v_msg)));
    WHEN check_violation OR foreign_key_violation OR not_null_violation THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_constraint = CONSTRAINT_NAME;
      RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
        'code', 'payload_invalido', 'message', 'el retiro viola una regla de movimientos_socio',
        'detail', jsonb_build_object('sqlstate', v_sqlstate, 'constraint', v_constraint)));
    WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      IF v_constraint ILIKE '%nonce%' THEN
        RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
          'code', 'conflicto', 'message', 'nonce ya utilizado',
          'detail', jsonb_build_object('reason', 'nonce_replay')));
      END IF;
      SELECT actor, payload_norm, id_movimiento
        INTO v_ex_actor, v_ex_payload, v_ex_mov
        FROM public.portal_idempotencia_cc
       WHERE action = c_action AND idempotency_key = v_idem;
      IF v_ex_payload IS DISTINCT FROM v_payload_norm OR v_ex_actor IS DISTINCT FROM v_actor THEN
        RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
          'code', 'conflicto', 'message', 'idempotency_key en conflicto',
          'detail', jsonb_build_object('reason', 'idem_conflict_post_insert')));
      END IF;
      RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
        'id_movimiento', v_ex_mov, 'idempotente', true));
  END;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id_movimiento', v_id_mov, 'idempotente', false));

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'error_interno', 'message', 'error interno no esperado',
      'detail', jsonb_build_object('sqlstate', v_sqlstate)));
END;
$fn$;

COMMENT ON FUNCTION public.portal_registrar_retiro(jsonb) IS
  'Cuenta Corriente / wrapper de retiro (accion cuenta_corriente.retirar). Espeja portal_cargar_gasto_interno: control inyectado por el gateway (actor/rol/id_socio/nonce, confiable) + idempotency_key del cliente. Vincula identidad id_socio<->actor via portal_usuarios. Lock hashtext(action,key), anti-replay nonce, idempotencia (action,key) en portal_idempotencia_cc, alta+traza en savepoint. Contrato {ok,data|error}. Codigos: error_interno, rol_no_permitido, payload_invalido, saldo_insuficiente, conflicto.';

-- ---- Hardening EXECUTE de ambas funciones (sin Data API) -------------------
REVOKE EXECUTE ON FUNCTION public.registrar_retiro_desde_saldo_vivo(bigint, numeric, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.portal_registrar_retiro(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

-- ---- Confirmacion visible (ultima result set antes del COMMIT) ------------
SELECT
  to_regclass('public.portal_idempotencia_cc') IS NOT NULL AS tabla_ok,
  to_regclass('public.portal_idempotencia_cc_id_registro_seq') IS NOT NULL AS secuencia_ok,
  to_regprocedure('public.registrar_retiro_desde_saldo_vivo(bigint, numeric, text, text, text)') IS NOT NULL AS negocio_ok,
  to_regprocedure('public.portal_registrar_retiro(jsonb)') IS NOT NULL AS wrapper_ok;

COMMIT;
