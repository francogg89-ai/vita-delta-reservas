-- ============================================================================
-- BOOTSTRAP ENTORNO NUEVO v1.12.0 — 03: PARTE D (PORTAL) · DDL EJECUTABLE
-- Fuente: 6B_SCHEMA_SQL.md v1.12.0 (EXTRACCION LITERAL R2 desde PARTE D).
--   Portal v1.12.0: 3 tablas (portal_usuarios + id_socio, portal_idempotencia,
--   portal_idempotencia_cc), 2 funciones (portal_cargar_gasto_interno,
--   portal_registrar_retiro), hardening D4 y auto-test D5 extendido. Solo
--   estructura: NO siembra portal_usuarios, ni Auth, ni secretos. Extraccion R2.
-- USO: correr DESPUES de 02. El veredicto vive en 03_VERIFY_FINAL_ENTORNO.sql.
-- ============================================================================



-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE D1 — Tabla portal_usuarios
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE public.portal_usuarios (
  user_id     uuid        PRIMARY KEY
                          REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre      text        NOT NULL,
  rol         text        NOT NULL,
  activo      boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  id_socio    bigint,
  CONSTRAINT uq_portal_usuarios_nombre     UNIQUE (nombre),
  CONSTRAINT uq_portal_usuarios_id_socio   UNIQUE (id_socio),
  CONSTRAINT fk_portal_usuarios_id_socio
    FOREIGN KEY (id_socio) REFERENCES public.socios(id_socio) ON DELETE RESTRICT,
  CONSTRAINT chk_portal_usuarios_rol       CHECK (rol IN ('jenny','vicky','socio')),
  CONSTRAINT chk_portal_usuarios_nombre_ne CHECK (length(btrim(nombre)) > 0),
  CONSTRAINT chk_portal_usuarios_socio_rol CHECK ((rol = 'socio') = (id_socio IS NOT NULL))
);

COMMENT ON TABLE public.portal_usuarios IS
  'Carril C / Slice 0: mapeo identidad(auth.users)->rol del Portal Operativo Interno. Interna: sin acceso por Data API (D-C-34); la lee solo la Edge Function portal-api vía service_role.';
COMMENT ON COLUMN public.portal_usuarios.nombre IS
  'Identificador de persona (vicky/franco/rodrigo/remo/jenny) usado como creado_por/validado_por (D-C-22), no el rol.';

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE D2 — Tabla portal_idempotencia
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE public.portal_idempotencia (
  id_registro      bigserial   PRIMARY KEY,
  action           text        NOT NULL,
  actor            text        NOT NULL,
  rol              text        NOT NULL,
  source_event     text        NOT NULL,
  nonce            text        NOT NULL,
  idempotency_key  text        NOT NULL,
  payload_norm     jsonb       NOT NULL,
  id_gasto         bigint      NOT NULL,
  estado           text        NOT NULL DEFAULT 'ok',
  request_ts       bigint,
  created_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_portal_idempotencia_nonce      UNIQUE (nonce),
  CONSTRAINT uq_portal_idempotencia_action_key UNIQUE (action, idempotency_key),
  CONSTRAINT fk_portal_idempotencia_gasto
    FOREIGN KEY (id_gasto) REFERENCES public.gastos_internos(id_gasto) ON DELETE RESTRICT,
  CONSTRAINT chk_portal_idempotencia_action_ne CHECK (length(btrim(action)) > 0),
  CONSTRAINT chk_portal_idempotencia_actor_ne  CHECK (length(btrim(actor)) > 0),
  CONSTRAINT chk_portal_idempotencia_source_ne CHECK (length(btrim(source_event)) > 0),
  CONSTRAINT chk_portal_idempotencia_nonce_ne  CHECK (length(btrim(nonce)) > 0),
  CONSTRAINT chk_portal_idempotencia_idem_ne   CHECK (length(btrim(idempotency_key)) > 0),
  CONSTRAINT chk_portal_idempotencia_rol       CHECK (rol IN ('vicky','socio')),
  CONSTRAINT chk_portal_idempotencia_estado    CHECK (estado = 'ok')
);

COMMENT ON TABLE public.portal_idempotencia IS
  'Carril C / Slice 3b (D-C-55): infra canonica del portal (PARTE D, consolidada en v1.9.0). nonce UNIQUE = anti-replay (P-C-9); (action,idempotency_key) UNIQUE = idempotencia de negocio; payload_norm + actor = deteccion de conflicto; source_event/actor/action = traza que NO cabe en gastos_internos. Interna: sin Data API (D-C-34); la toca solo n8n via postgres.';

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE D2-bis — Tabla portal_idempotencia_cc (retiro desde saldo vivo, v1.11.0)
-- ══════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE D3 — Función portal_cargar_gasto_interno
-- ══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.portal_cargar_gasto_interno(jsonb);

CREATE FUNCTION public.portal_cargar_gasto_interno(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
AS $fn$
DECLARE
  c_action       CONSTANT text := 'cargar.gasto_interno';
  -- control (inyectado server-side por el gateway; confiable)
  v_actor        text;
  v_rol          text;
  v_nonce        text;
  v_idem         text;
  v_req_ts       bigint;
  v_source       text;
  -- negocio
  v_fecha        date;
  v_periodo      date;
  v_periodo_raw  text;
  v_clase        text;
  v_clase_sug    text;
  v_etiqueta     text;
  v_monto        numeric(12,2);
  v_id_zona      bigint;
  v_id_cabana    bigint;
  v_pagador      text;
  v_id_socio     bigint;
  v_medio        text;
  v_comentario   text;
  v_comprob      text;
  v_payload_norm jsonb;
  -- idempotencia / salida
  v_id_gasto     bigint;
  v_ex_actor     text;
  v_ex_payload   jsonb;
  v_ex_gasto     bigint;
  v_sqlstate     text;
  v_constraint   text;
BEGIN
  -- 1) Control inyectado por el gateway -------------------------------------
  v_actor := NULLIF(btrim(p_payload->>'actor'), '');
  v_rol   := NULLIF(btrim(p_payload->>'rol'), '');
  v_nonce := NULLIF(btrim(p_payload->>'nonce'), '');
  v_idem  := NULLIF(btrim(p_payload->>'idempotency_key'), '');
  v_req_ts := CASE WHEN (p_payload->>'request_ts') ~ '^\d+$'
                   THEN (p_payload->>'request_ts')::bigint ELSE NULL END;

  -- actor/rol/nonce ausentes = falla de cableado del gateway, no del cliente
  IF v_actor IS NULL OR v_rol IS NULL OR v_nonce IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'error_interno',
      'message', 'faltan campos de control inyectados por el gateway',
      'detail', jsonb_build_object('actor', v_actor IS NOT NULL,
                                   'rol',   v_rol   IS NOT NULL,
                                   'nonce', v_nonce IS NOT NULL)));
  END IF;

  IF v_rol NOT IN ('vicky', 'socio') THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'rol_no_permitido',
      'message', 'rol fuera del allowlist de cargar.gasto_interno',
      'detail', jsonb_build_object('rol', v_rol)));
  END IF;

  -- idempotency_key la provee el cliente -> payload_invalido si falta
  IF v_idem IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'payload_invalido',
      'message', 'idempotency_key requerida',
      'detail', jsonb_build_object('campo', 'idempotency_key')));
  END IF;

  v_source := 'portal_a11_' || v_idem;  -- microcorreccion 3

  -- 2) Negocio: extraccion + casts en sub-bloque (data_exception -> payload_invalido)
  BEGIN
    v_fecha := NULLIF(btrim(p_payload->>'fecha'), '')::date;
    IF v_fecha IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
        'code', 'payload_invalido', 'message', 'fecha requerida (YYYY-MM-DD)',
        'detail', jsonb_build_object('campo', 'fecha')));
    END IF;

    -- periodo: default = primer dia del mes de fecha; si explicito, dia 1 (D-C-55 / decision 4)
    v_periodo_raw := NULLIF(btrim(p_payload->>'periodo'), '');
    IF v_periodo_raw IS NULL THEN
      v_periodo := date_trunc('month', v_fecha)::date;
    ELSE
      v_periodo := v_periodo_raw::date;
      IF EXTRACT(DAY FROM v_periodo) <> 1 THEN
        RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
          'code', 'payload_invalido',
          'message', 'periodo debe ser el primer dia del mes (dia 1)',
          'detail', jsonb_build_object('campo', 'periodo',
                                       'valor', to_char(v_periodo, 'YYYY-MM-DD'))));
      END IF;
    END IF;

    v_clase      := NULLIF(btrim(p_payload->>'clase'), '');
    v_clase_sug  := NULLIF(btrim(p_payload->>'clase_sugerida'), '');
    v_etiqueta   := NULLIF(btrim(p_payload->>'etiqueta'), '');
    v_monto      := NULLIF(btrim(p_payload->>'monto'), '')::numeric(12,2);
    v_id_zona    := NULLIF(btrim(p_payload->>'id_zona'), '')::bigint;
    v_id_cabana  := NULLIF(btrim(p_payload->>'id_cabana'), '')::bigint;
    v_pagador    := NULLIF(btrim(p_payload->>'pagador_tipo'), '');
    v_id_socio   := NULLIF(btrim(p_payload->>'id_socio_pagador'), '')::bigint;
    v_medio      := NULLIF(btrim(p_payload->>'medio_pago'), '');
    v_comentario := NULLIF(btrim(p_payload->>'comentario'), '');
    v_comprob    := NULLIF(btrim(p_payload->>'comprobante_url'), '');
  EXCEPTION
    WHEN data_exception THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
      RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
        'code', 'payload_invalido',
        'message', 'formato invalido en algun campo (fecha/periodo/monto/ids)',
        'detail', jsonb_build_object('sqlstate', v_sqlstate)));
  END;

  -- payload_norm canonico: SOLO campos de negocio (lo que define el gasto)
  v_payload_norm := jsonb_build_object(
    'fecha',            to_char(v_fecha, 'YYYY-MM-DD'),
    'periodo',          to_char(v_periodo, 'YYYY-MM-DD'),
    'clase',            v_clase,
    'clase_sugerida',   v_clase_sug,
    'etiqueta',         v_etiqueta,
    'monto',            v_monto,
    'id_zona',          v_id_zona,
    'id_cabana',        v_id_cabana,
    'pagador_tipo',     v_pagador,
    'id_socio_pagador', v_id_socio,
    'medio_pago',       v_medio,
    'comentario',       v_comentario,
    'comprobante_url',  v_comprob);

  -- 3) Serializa primeros intentos concurrentes con la misma (action,key).
  --    Sobrecarga de DOS enteros (integer,integer): usa el espacio de 64 bits con
  --    una clave por dominio (action / idempotency_key); evita castear un hash de
  --    32 bits a bigint. hashtext() devuelve integer -> calza con (integer,integer).
  PERFORM pg_advisory_xact_lock(hashtext(c_action), hashtext(v_idem));

  -- 3a) Anti-replay por nonce (P-C-9) -> conflicto / nonce_replay
  IF EXISTS (SELECT 1 FROM public.portal_idempotencia WHERE nonce = v_nonce) THEN
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'conflicto', 'message', 'nonce ya utilizado',
      'detail', jsonb_build_object('reason', 'nonce_replay')));
  END IF;

  -- 3b) Idempotencia de negocio (action,key): payload_norm + actor (microcorr. 2)
  SELECT actor, payload_norm, id_gasto
    INTO v_ex_actor, v_ex_payload, v_ex_gasto
    FROM public.portal_idempotencia
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
      'id_gasto', v_ex_gasto, 'idempotente', true));
  END IF;

  -- 4) Alta nueva: INSERT gasto + INSERT traza en el MISMO sub-bloque.
  --    gastos_internos no tiene UNIQUE de negocio -> no puede dar unique_violation;
  --    por eso un unique_violation aqui viene siempre de portal_idempotencia, y el
  --    savepoint revierte AMBOS inserts (no queda gasto huerfano).
  BEGIN
    INSERT INTO public.gastos_internos
      (fecha, periodo, clase, clase_sugerida, etiqueta, monto,
       id_zona, id_cabana, pagador_tipo, id_socio_pagador,
       medio_pago, comentario, comprobante_url, creado_por)
    VALUES
      (v_fecha, v_periodo, v_clase, v_clase_sug, v_etiqueta, v_monto,
       v_id_zona, v_id_cabana, v_pagador, v_id_socio,
       v_medio, v_comentario, v_comprob, v_actor)
    RETURNING id_gasto INTO v_id_gasto;

    INSERT INTO public.portal_idempotencia
      (action, actor, rol, source_event, nonce, idempotency_key,
       payload_norm, id_gasto, request_ts)
    VALUES
      (c_action, v_actor, v_rol, v_source, v_nonce, v_idem,
       v_payload_norm, v_id_gasto, v_req_ts);
  EXCEPTION
    WHEN check_violation OR foreign_key_violation OR not_null_violation THEN
      -- viene del INSERT del gasto: las 18 constraints de gastos_internos
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE,
                              v_constraint = CONSTRAINT_NAME;
      RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
        'code', 'payload_invalido',
        'message', 'el gasto viola una regla de coherencia de gastos_internos',
        'detail', jsonb_build_object('sqlstate', v_sqlstate, 'constraint', v_constraint)));
    WHEN unique_violation THEN
      -- viene de portal_idempotencia (carrera que el lock deberia evitar; backstop)
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      IF v_constraint ILIKE '%nonce%' THEN
        RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
          'code', 'conflicto', 'message', 'nonce ya utilizado',
          'detail', jsonb_build_object('reason', 'nonce_replay')));
      END IF;
      SELECT actor, payload_norm, id_gasto
        INTO v_ex_actor, v_ex_payload, v_ex_gasto
        FROM public.portal_idempotencia
       WHERE action = c_action AND idempotency_key = v_idem;
      IF v_ex_payload IS DISTINCT FROM v_payload_norm
         OR v_ex_actor IS DISTINCT FROM v_actor THEN
        RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
          'code', 'conflicto', 'message', 'idempotency_key en conflicto',
          'detail', jsonb_build_object('reason', 'idem_conflict_post_insert')));
      END IF;
      RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
        'id_gasto', v_ex_gasto, 'idempotente', true));
  END;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id_gasto', v_id_gasto, 'idempotente', false));

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
    RETURN jsonb_build_object('ok', false, 'error', jsonb_build_object(
      'code', 'error_interno', 'message', 'error interno no esperado',
      'detail', jsonb_build_object('sqlstate', v_sqlstate)));
END;
$fn$;

COMMENT ON FUNCTION public.portal_cargar_gasto_interno(jsonb) IS
  'Carril C / Slice 3b (D-C-55): carga atomica de gasto interno con nonce anti-replay (P-C-9) + idempotency_key de cliente + comparacion payload_norm/actor. Consolidada en el canonico (PARTE D, v1.9.0).';

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE D3-bis — Función portal_registrar_retiro (retiro desde saldo vivo, v1.11.0)
-- ══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.portal_registrar_retiro(jsonb);

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

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE D4 — Hardening — REVOKE/GRANT
-- ══════════════════════════════════════════════════════════════════════════
-- ── D4. Hardening — REVOKE total a los 4 roles (tablas + secuencia + función),
-- luego GRANT SELECT a service_role SOLO en portal_usuarios (asimetría D-C-34:
-- la Edge Function portal-api la lee vía service_role; portal_idempotencia la
-- toca solo n8n vía postgres/owner, sin acceso por Data API). El estado final de
-- ACL es el certificado por el Bloque H; el orden de las sentencias no lo altera.
-- Tablas:
REVOKE ALL     ON public.portal_usuarios     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL     ON public.portal_idempotencia FROM PUBLIC, anon, authenticated, service_role;
-- Secuencia (bigserial de portal_idempotencia):
REVOKE ALL     ON SEQUENCE public.portal_idempotencia_id_registro_seq FROM PUBLIC, anon, authenticated, service_role;
-- Función:
REVOKE EXECUTE ON FUNCTION public.portal_cargar_gasto_interno(jsonb)  FROM PUBLIC, anon, authenticated, service_role;
-- Retiro desde saldo vivo (v1.11.0): tabla + secuencia + wrapper (sin Data API):
REVOKE ALL     ON public.portal_idempotencia_cc FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL     ON SEQUENCE public.portal_idempotencia_cc_id_registro_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.portal_registrar_retiro(jsonb) FROM PUBLIC, anon, authenticated, service_role;
-- Único GRANT de runtime: service_role LEE portal_usuarios (no escribe).
GRANT  SELECT  ON public.portal_usuarios TO service_role;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE D5 — Verificación estructural y de hardening
-- ══════════════════════════════════════════════════════════════════════════
-- ── D5. Verificación estructural y de hardening (asserts; no modifica) ──
-- Verificación ESTRICTA: estructura (existencia + FKs validadas contra la tabla y
-- columna EXACTAS por conrelid/confrelid, no por nombre + CHECK/UNIQUE en la
-- relación correcta y por conjunto de columnas + firma de la función) y hardening
-- por ACL real vía aclexplode, que enumera lo realmente concedido y cubre TODOS los
-- privilegios de tabla —SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER y
-- MAINTAIN en PG17— sin depender de la versión, más el estado de RLS/policies.
-- NO depende de datos, usuarios reales ni del marcador de ambiente: es segura de
-- correr contra cualquier entorno. En un bootstrap nuevo las tablas nacen vacías
-- (la PARTE D no siembra); esa vaciedad es el estado esperado, NO un invariante, y
-- por eso D5 NO chequea conteos de filas.
DO $verif_portal$
DECLARE
  v_pu    oid := to_regclass('public.portal_usuarios');
  v_pi    oid := to_regclass('public.portal_idempotencia');
  v_seq   oid := to_regclass('public.portal_idempotencia_id_registro_seq');
  v_fn    oid := to_regprocedure('public.portal_cargar_gasto_interno(jsonb)');
  v_pcc   oid := to_regclass('public.portal_idempotencia_cc');
  v_pccs  oid := to_regclass('public.portal_idempotencia_cc_id_registro_seq');
  v_fret  oid := to_regprocedure('public.registrar_retiro_desde_saldo_vivo(bigint, numeric, text, text, text)');
  v_fwrap oid := to_regprocedure('public.portal_registrar_retiro(jsonb)');
  v_auth  oid := to_regclass('auth.users');
  v_gas   oid := to_regclass('public.gastos_internos');
  v_soc   oid := to_regclass('public.socios');
  v_mov   oid := to_regclass('public.movimientos_socio');
  r       record;
  v_n     integer;
  v_txt   text;
BEGIN
  -- ── existencia (4 objetos v1.9.0 + portal_idempotencia_cc/secuencia + 2 funciones v1.11.0) ──
  IF v_pu    IS NULL THEN RAISE EXCEPTION 'D5: portal_usuarios ausente'; END IF;
  IF v_pi    IS NULL THEN RAISE EXCEPTION 'D5: portal_idempotencia ausente'; END IF;
  IF v_seq   IS NULL THEN RAISE EXCEPTION 'D5: secuencia portal_idempotencia_id_registro_seq ausente'; END IF;
  IF v_fn    IS NULL THEN RAISE EXCEPTION 'D5: portal_cargar_gasto_interno(jsonb) ausente'; END IF;
  IF v_pcc   IS NULL THEN RAISE EXCEPTION 'D5: portal_idempotencia_cc ausente (v1.11.0)'; END IF;
  IF v_pccs  IS NULL THEN RAISE EXCEPTION 'D5: secuencia portal_idempotencia_cc_id_registro_seq ausente (v1.11.0)'; END IF;
  IF v_fret  IS NULL THEN RAISE EXCEPTION 'D5: registrar_retiro_desde_saldo_vivo(bigint,numeric,text,text,text) ausente (v1.11.0)'; END IF;
  IF v_fwrap IS NULL THEN RAISE EXCEPTION 'D5: portal_registrar_retiro(jsonb) ausente (v1.11.0)'; END IF;
  IF v_auth  IS NULL THEN RAISE EXCEPTION 'D5: auth.users ausente — se requiere proyecto Supabase'; END IF;
  IF v_gas   IS NULL THEN RAISE EXCEPTION 'D5: gastos_internos ausente — la PARTE D corre DESPUES de la PARTE C'; END IF;
  IF v_soc   IS NULL THEN RAISE EXCEPTION 'D5: socios ausente — la PARTE D corre DESPUES de la PARTE C'; END IF;
  IF v_mov   IS NULL THEN RAISE EXCEPTION 'D5: movimientos_socio ausente — la PARTE D corre DESPUES de la PARTE C'; END IF;

  -- ══ portal_usuarios: DOS FKs (v1.11.0). Se validan POR COLUMNA (conkey), NO asumiendo una sola. ══
  -- FK en user_id -> auth.users(id) ON DELETE CASCADE, exacta, 1 columna
  SELECT con.confrelid, con.confdeltype, cardinality(con.conkey) AS ncols,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1]) AS rcol
    INTO r
    FROM pg_constraint con
   WHERE con.conrelid=v_pu AND con.contype='f'
     AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid AND a.attnum=con.conkey[1]) = 'user_id';
  IF NOT FOUND THEN RAISE EXCEPTION 'D5: portal_usuarios sin FK en user_id'; END IF;
  IF r.confrelid IS DISTINCT FROM v_auth OR r.rcol<>'id' OR r.ncols<>1 OR r.confdeltype<>'c' THEN
    RAISE EXCEPTION 'D5: FK user_id no es exactamente -> auth.users(id) ON DELETE CASCADE [ref=%, rcol=%, ncols=%, del=%]',
      r.confrelid::regclass, r.rcol, r.ncols, r.confdeltype;
  END IF;

  -- FK en id_socio -> socios(id_socio) ON DELETE RESTRICT, exacta, 1 columna (SB0)
  SELECT con.confrelid, con.confdeltype, cardinality(con.conkey) AS ncols,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1]) AS rcol
    INTO r
    FROM pg_constraint con
   WHERE con.conrelid=v_pu AND con.contype='f'
     AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid AND a.attnum=con.conkey[1]) = 'id_socio';
  IF NOT FOUND THEN RAISE EXCEPTION 'D5: portal_usuarios sin FK en id_socio (SB0/v1.11.0)'; END IF;
  IF r.confrelid IS DISTINCT FROM v_soc OR r.rcol<>'id_socio' OR r.ncols<>1 OR r.confdeltype<>'r' THEN
    RAISE EXCEPTION 'D5: FK id_socio no es exactamente -> socios(id_socio) ON DELETE RESTRICT [ref=%, rcol=%, ncols=%, del=%]',
      r.confrelid::regclass, r.rcol, r.ncols, r.confdeltype;
  END IF;

  -- ── FK portal_idempotencia.id_gasto -> gastos_internos(id_gasto) ON DELETE RESTRICT ──
  SELECT con.confrelid, con.confdeltype,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid  AND a.attnum=con.conkey[1])  AS lcol,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1]) AS rcol,
         cardinality(con.conkey) AS ncols
    INTO r
    FROM pg_constraint con
   WHERE con.conrelid=v_pi AND con.contype='f' AND con.conname='fk_portal_idempotencia_gasto';
  IF NOT FOUND THEN RAISE EXCEPTION 'D5: falta FK fk_portal_idempotencia_gasto'; END IF;
  IF r.confrelid IS DISTINCT FROM v_gas OR r.lcol<>'id_gasto' OR r.rcol<>'id_gasto'
     OR r.ncols<>1 OR r.confdeltype<>'r' THEN
    RAISE EXCEPTION 'D5: FK id_gasto no es exactamente -> gastos_internos(id_gasto) ON DELETE RESTRICT [ref=%, lcol=%, rcol=%, del=%]',
      r.confrelid::regclass, r.lcol, r.rcol, r.confdeltype;
  END IF;

  -- ── FK portal_idempotencia_cc.id_movimiento -> movimientos_socio(id_movimiento) RESTRICT (v1.11.0) ──
  SELECT con.confrelid, con.confdeltype,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid  AND a.attnum=con.conkey[1])  AS lcol,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1]) AS rcol,
         cardinality(con.conkey) AS ncols
    INTO r
    FROM pg_constraint con
   WHERE con.conrelid=v_pcc AND con.contype='f' AND con.conname='fk_portal_idem_cc_mov';
  IF NOT FOUND THEN RAISE EXCEPTION 'D5: falta FK fk_portal_idem_cc_mov (v1.11.0)'; END IF;
  IF r.confrelid IS DISTINCT FROM v_mov OR r.lcol<>'id_movimiento' OR r.rcol<>'id_movimiento'
     OR r.ncols<>1 OR r.confdeltype<>'r' THEN
    RAISE EXCEPTION 'D5: FK id_movimiento no es exactamente -> movimientos_socio(id_movimiento) ON DELETE RESTRICT [ref=%, lcol=%, rcol=%, del=%]',
      r.confrelid::regclass, r.lcol, r.rcol, r.confdeltype;
  END IF;

  -- ── CHECK de rol en portal_usuarios + dominio {jenny,vicky,socio} ──
  SELECT pg_get_constraintdef(con.oid) INTO v_txt
    FROM pg_constraint con
   WHERE con.conrelid=v_pu AND con.contype='c' AND con.conname='chk_portal_usuarios_rol';
  IF v_txt IS NULL THEN RAISE EXCEPTION 'D5: falta CHECK chk_portal_usuarios_rol en portal_usuarios'; END IF;
  IF v_txt NOT ILIKE '%jenny%' OR v_txt NOT ILIKE '%vicky%' OR v_txt NOT ILIKE '%socio%' THEN
    RAISE EXCEPTION 'D5: CHECK de rol no restringe a {jenny,vicky,socio}: %', v_txt;
  END IF;

  -- ── CHECK bicondicional rol<->id_socio en portal_usuarios (SB0/v1.11.0) ──
  SELECT pg_get_constraintdef(con.oid) INTO v_txt
    FROM pg_constraint con
   WHERE con.conrelid=v_pu AND con.contype='c' AND con.conname='chk_portal_usuarios_socio_rol';
  IF v_txt IS NULL THEN RAISE EXCEPTION 'D5: falta CHECK chk_portal_usuarios_socio_rol en portal_usuarios (SB0/v1.11.0)'; END IF;
  IF v_txt NOT ILIKE '%id_socio%' OR v_txt NOT ILIKE '%socio%' THEN
    RAISE EXCEPTION 'D5: chk_portal_usuarios_socio_rol no relaciona rol e id_socio: %', v_txt;
  END IF;

  -- ── CHECK rol socio-only en portal_idempotencia_cc (v1.11.0) ──
  SELECT pg_get_constraintdef(con.oid) INTO v_txt
    FROM pg_constraint con
   WHERE con.conrelid=v_pcc AND con.contype='c' AND con.conname='chk_portal_idem_cc_rol';
  IF v_txt IS NULL THEN RAISE EXCEPTION 'D5: falta CHECK chk_portal_idem_cc_rol en portal_idempotencia_cc (v1.11.0)'; END IF;
  -- socio-only estricto: a diferencia de portal_idempotencia (vicky|socio), aca NO se admite vicky/jenny
  IF v_txt NOT ILIKE '%socio%' OR v_txt ILIKE '%vicky%' OR v_txt ILIKE '%jenny%' THEN
    RAISE EXCEPTION 'D5: chk_portal_idem_cc_rol no es socio-only (esperado rol = ''socio''): %', v_txt;
  END IF;

  -- ══ UNIQUEs por conjunto de columnas exacto ══
  -- portal_usuarios: nombre ; id_socio (SB0)
  IF NOT EXISTS (SELECT 1 FROM pg_constraint con
                  WHERE con.conrelid=v_pu AND con.contype='u' AND con.conname='uq_portal_usuarios_nombre'
                    AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                           FROM unnest(con.conkey) AS ck(attnum)
                           JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['nombre']) THEN
    RAISE EXCEPTION 'D5: uq_portal_usuarios_nombre no es UNIQUE(nombre) en portal_usuarios';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint con
                  WHERE con.conrelid=v_pu AND con.contype='u' AND con.conname='uq_portal_usuarios_id_socio'
                    AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                           FROM unnest(con.conkey) AS ck(attnum)
                           JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['id_socio']) THEN
    RAISE EXCEPTION 'D5: uq_portal_usuarios_id_socio no es UNIQUE(id_socio) en portal_usuarios (SB0/v1.11.0)';
  END IF;
  -- portal_idempotencia: nonce ; (action,idempotency_key)
  IF NOT EXISTS (SELECT 1 FROM pg_constraint con
                  WHERE con.conrelid=v_pi AND con.contype='u' AND con.conname='uq_portal_idempotencia_nonce'
                    AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                           FROM unnest(con.conkey) AS ck(attnum)
                           JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['nonce']) THEN
    RAISE EXCEPTION 'D5: uq_portal_idempotencia_nonce no es UNIQUE(nonce)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint con
                  WHERE con.conrelid=v_pi AND con.contype='u' AND con.conname='uq_portal_idempotencia_action_key'
                    AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                           FROM unnest(con.conkey) AS ck(attnum)
                           JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['action','idempotency_key']) THEN
    RAISE EXCEPTION 'D5: uq_portal_idempotencia_action_key no es UNIQUE(action,idempotency_key)';
  END IF;
  -- portal_idempotencia_cc: nonce ; (action,idempotency_key) (v1.11.0)
  IF NOT EXISTS (SELECT 1 FROM pg_constraint con
                  WHERE con.conrelid=v_pcc AND con.contype='u' AND con.conname='uq_portal_idem_cc_nonce'
                    AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                           FROM unnest(con.conkey) AS ck(attnum)
                           JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['nonce']) THEN
    RAISE EXCEPTION 'D5: uq_portal_idem_cc_nonce no es UNIQUE(nonce) (v1.11.0)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint con
                  WHERE con.conrelid=v_pcc AND con.contype='u' AND con.conname='uq_portal_idem_cc_action_key'
                    AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                           FROM unnest(con.conkey) AS ck(attnum)
                           JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['action','idempotency_key']) THEN
    RAISE EXCEPTION 'D5: uq_portal_idem_cc_action_key no es UNIQUE(action,idempotency_key) (v1.11.0)';
  END IF;

  -- ══ firmas de funciones (RETURNS + SECURITY INVOKER + plpgsql) ══
  -- portal_cargar_gasto_interno -> jsonb
  SELECT p.prorettype, p.prosecdef, l.lanname INTO r
    FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=v_fn;
  IF r.prorettype IS DISTINCT FROM 'jsonb'::regtype THEN RAISE EXCEPTION 'D5: portal_cargar_gasto_interno no RETURNS jsonb'; END IF;
  IF r.prosecdef THEN RAISE EXCEPTION 'D5: portal_cargar_gasto_interno no es SECURITY INVOKER'; END IF;
  IF r.lanname<>'plpgsql' THEN RAISE EXCEPTION 'D5: portal_cargar_gasto_interno no es plpgsql'; END IF;
  -- portal_registrar_retiro -> jsonb (v1.11.0)
  SELECT p.prorettype, p.prosecdef, l.lanname INTO r
    FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=v_fwrap;
  IF r.prorettype IS DISTINCT FROM 'jsonb'::regtype THEN RAISE EXCEPTION 'D5: portal_registrar_retiro no RETURNS jsonb'; END IF;
  IF r.prosecdef THEN RAISE EXCEPTION 'D5: portal_registrar_retiro no es SECURITY INVOKER'; END IF;
  IF r.lanname<>'plpgsql' THEN RAISE EXCEPTION 'D5: portal_registrar_retiro no es plpgsql'; END IF;
  -- registrar_retiro_desde_saldo_vivo -> bigint (v1.11.0)
  SELECT p.prorettype, p.prosecdef, l.lanname INTO r
    FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=v_fret;
  IF r.prorettype IS DISTINCT FROM 'bigint'::regtype THEN RAISE EXCEPTION 'D5: registrar_retiro_desde_saldo_vivo no RETURNS bigint'; END IF;
  IF r.prosecdef THEN RAISE EXCEPTION 'D5: registrar_retiro_desde_saldo_vivo no es SECURITY INVOKER'; END IF;
  IF r.lanname<>'plpgsql' THEN RAISE EXCEPTION 'D5: registrar_retiro_desde_saldo_vivo no es plpgsql'; END IF;

  -- ══ hardening por ACL real (aclexplode; cubre TODOS los privilegios incl. MAINTAIN) ══
  -- portal_usuarios: la ÚNICA concesión Data API/PUBLIC debe ser (service_role, SELECT)
  SELECT count(*) INTO v_n
    FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
   WHERE c.oid=v_pu
     AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
     AND NOT (a.grantee<>0 AND pg_get_userbyid(a.grantee)='service_role' AND a.privilege_type='SELECT');
  IF v_n>0 THEN RAISE EXCEPTION 'D5: portal_usuarios con privilegios Data API distintos de service_role:SELECT (%)', v_n; END IF;
  IF NOT has_table_privilege('service_role','public.portal_usuarios','SELECT') THEN
    RAISE EXCEPTION 'D5: service_role no puede leer portal_usuarios'; END IF;

  -- portal_idempotencia + portal_idempotencia_cc + ambas secuencias: CERO privilegios Data API/PUBLIC
  FOR r IN SELECT unnest(ARRAY[v_pi, v_pcc, v_seq, v_pccs]) AS oid LOOP
    SELECT count(*) INTO v_n
      FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
     WHERE c.oid=r.oid AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
    IF v_n>0 THEN RAISE EXCEPTION 'D5: % con privilegios Data API (%)', r.oid::regclass, v_n; END IF;
  END LOOP;

  -- funciones (las 3): proacl NO nula (si nula, PUBLIC ejecuta) + CERO EXECUTE Data API/PUBLIC
  FOR r IN SELECT unnest(ARRAY[v_fn, v_fret, v_fwrap]) AS oid LOOP
    IF (SELECT proacl FROM pg_proc WHERE oid=r.oid) IS NULL THEN
      RAISE EXCEPTION 'D5: proacl de % es NULL (PUBLIC ejecuta) — falta REVOKE', r.oid::regprocedure;
    END IF;
    SELECT count(*) INTO v_n
      FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
     WHERE p.oid=r.oid AND a.privilege_type='EXECUTE'
       AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
    IF v_n>0 THEN RAISE EXCEPTION 'D5: % ejecutable por rol Data API (%)', r.oid::regprocedure, v_n; END IF;
  END LOOP;

  -- ── RLS/policies: estado canónico = RLS off + 0 policies en las 3 tablas del portal ──
  IF EXISTS (SELECT 1 FROM pg_class WHERE oid IN (v_pu,v_pi,v_pcc) AND (relrowsecurity OR relforcerowsecurity)) THEN
    RAISE EXCEPTION 'D5: RLS habilitada en una tabla del portal (esperado off)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polrelid IN (v_pu,v_pi,v_pcc)) THEN
    RAISE EXCEPTION 'D5: hay policies sobre el portal (esperado 0)';
  END IF;

  RAISE NOTICE 'PARTE D OK (v1.11.0): portal_usuarios 2 FKs (user_id->auth.users(id) CASCADE; id_socio->socios(id_socio) RESTRICT) + UNIQUE(id_socio) + CHECK bicondicional rol<->id_socio; portal_idempotencia_cc (FK id_movimiento->movimientos_socio RESTRICT; UNIQUEs nonce y (action,idempotency_key); CHECK rol=socio); 2 funciones nuevas (registrar_retiro_desde_saldo_vivo->bigint; portal_registrar_retiro->jsonb; SECURITY INVOKER) + hardening por ACL real incl. MAINTAIN (portal_usuarios solo service_role:SELECT; idempotencias/secuencias/funciones sin Data API; proacl no nula; RLS off, 0 policies). Sin chequear datos ni ambiente.';
END
$verif_portal$;
