-- ============================================================================
-- PROMO_C_BLOQUE_B_INFRA_OPS.sql
-- Carril C / Portal Operativo Interno — PROMOCIÓN COORDINADA A OPS — BLOQUE B.
-- DDL de la infra del portal en OPS. Reúne en UN solo run transaccional las tres
-- piezas que en TEST se crearon en dos archivos (Slice 0 + Slice 3b):
--   · portal_usuarios                     (identidad auth.users -> rol; D-C-14/22/34)
--   · portal_idempotencia                 (anti-replay nonce + idempotencia; P-C-9, D-C-55)
--   · portal_cargar_gasto_interno(jsonb)  (carga atómica de gasto; A11)
--
-- ESTE BLOQUE CREA ESTRUCTURA. NO siembra datos. Condiciones del plan:
--   · DDL ÚNICAMENTE de esas 3 piezas. SIN seeds reales (las tablas nacen vacías).
--   · SIN tocar Auth (declara la FK a auth.users, pero NO crea/modifica usuarios).
--   · SIN tocar n8n, Vercel ni el gateway.
--   · Gate anti-entorno DENTRO del script (ambiente='ops' es el discriminador
--     fuerte; L-7B-01: los ids de cabaña 1-5 son idénticos TEST/OPS y NO discriminan).
--   · Transacción ATÓMICA: o entran las 3 completas y consistentes, o no entra nada.
--   · Asserts de grants/RLS/hardening (D-C-34) que ABORTAN si algo queda expuesto.
--   · Rollback claro (teardown consciente al pie, comentado).
--
-- HARDENING D-C-34 — asimetría deliberada entre las dos tablas (igual que TEST):
--   · portal_usuarios:     service_role SÍ tiene SELECT (la lee la Edge Function
--                          portal-api). REVOKE a PUBLIC/anon/authenticated/service_role,
--                          luego GRANT SELECT solo a service_role.
--   · portal_idempotencia: NADIE del Data API la toca. La usa solo n8n vía postgres
--                          (owner), igual que las funciones del motor. REVOKE total
--                          a los 4 roles sobre tabla + secuencia + función; sin GRANT.
--
-- PRECONDICIÓN (verificada en Bloque A, VERDE): ambiente='ops'; cabañas 1-5 reales;
--   gastos_internos presente (Carril B promovido, FK destino de portal_idempotencia);
--   las 3 piezas AUSENTES. Este script reconfirma con su propio gate + guard.
--
-- CÓMO CORRER: SQL Editor de Supabase del proyecto OPS (lpiatqztudxiwdlcoasv), con
--   NADA seleccionado (L-8A-01), todo el archivo de una. Si algo no calza, RAISE
--   aborta TODA la transacción. Resultado esperado: tabla de veredicto, todo PASS,
--   y la fila TOTAL en VERDE.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. GATE DE ENTORNO (ambiente='ops') + SANITY + GUARD DE NO-CLOBBER DE LAS 3
--    ambiente='ops' es la verdad; cabañas 1-5 es sanity de "DB Vita Delta real".
--    El guard aborta si CUALQUIERA de las 3 piezas ya existe: una promoción no
--    debe entrar sobre estado parcial. Para recrear: teardown consciente primero.
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb   text;
  v_cab   int;
  v_pu    int;
  v_pi    int;
  v_fn    int;
BEGIN
  -- (a) Marcador de ambiente: discriminador fuerte TEST/DEV/OPS.
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE B: ambiente=% (esperado ops). Abortado: este script es solo para OPS.',
      COALESCE(v_amb, '<ausente>');
  END IF;

  -- (b) Sanity: ¿es una DB Vita Delta real? (cabañas 1-5 por id+nombre).
  SELECT count(*) INTO v_cab
  FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
  WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana = e.id AND c.nombre = e.nom);
  IF v_cab <> 5 THEN
    RAISE EXCEPTION 'GATE B: identidad de cabañas no coincide (% de 5). DB inesperada.', v_cab;
  END IF;

  -- (c) Prerrequisito de FK: gastos_internos debe existir (Carril B promovido).
  IF to_regclass('public.gastos_internos') IS NULL THEN
    RAISE EXCEPTION 'GATE B: gastos_internos ausente — la FK de portal_idempotencia no podría crearse. Abortado.';
  END IF;

  -- (d) Guard de no-clobber: ninguna de las 3 piezas debe existir aún.
  SELECT count(*) INTO v_pu FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r' AND c.relname='portal_usuarios';
  SELECT count(*) INTO v_pi FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r' AND c.relname='portal_idempotencia';
  SELECT count(*) INTO v_fn FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='portal_cargar_gasto_interno';
  IF v_pu <> 0 OR v_pi <> 0 OR v_fn <> 0 THEN
    RAISE EXCEPTION 'GATE B: infra del portal ya existe (portal_usuarios=%, portal_idempotencia=%, funcion=%). Para recrear, teardown consciente y separado primero.',
      v_pu, v_pi, v_fn;
  END IF;
END
$gate$;

-- ----------------------------------------------------------------------------
-- 2. CREATE TABLE portal_usuarios (identidad auth.users -> rol del portal)
--    user_id : FK a auth.users (patrón Supabase profiles), ON DELETE CASCADE.
--    nombre  : identificador de PERSONA (D-C-22), TEXT libre UNIQUE.
--    rol     : set CERRADO de política {jenny,vicky,socio} (D-C-14), con CHECK.
--    activo  : baja lógica; inactivo => la Edge Function devuelve no_autorizado.
-- ----------------------------------------------------------------------------
CREATE TABLE public.portal_usuarios (
  user_id     uuid        PRIMARY KEY
                          REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre      text        NOT NULL,
  rol         text        NOT NULL,
  activo      boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_portal_usuarios_nombre     UNIQUE (nombre),
  CONSTRAINT chk_portal_usuarios_rol       CHECK (rol IN ('jenny','vicky','socio')),
  CONSTRAINT chk_portal_usuarios_nombre_ne CHECK (length(btrim(nombre)) > 0)
);

COMMENT ON TABLE public.portal_usuarios IS
  'Carril C / Slice 0: mapeo identidad(auth.users)->rol del Portal Operativo Interno. Interna: sin acceso por Data API (D-C-34); la lee solo la Edge Function portal-api vía service_role.';
COMMENT ON COLUMN public.portal_usuarios.nombre IS
  'Identificador de persona (vicky/franco/rodrigo/remo/jenny) usado como creado_por/validado_por (D-C-22), no el rol.';

-- HARDENING D-C-34 (portal_usuarios): invisible al Data API; service_role lee.
REVOKE ALL    ON public.portal_usuarios FROM PUBLIC;
REVOKE ALL    ON public.portal_usuarios FROM anon;
REVOKE ALL    ON public.portal_usuarios FROM authenticated;
REVOKE ALL    ON public.portal_usuarios FROM service_role;
GRANT  SELECT ON public.portal_usuarios TO   service_role;

-- ----------------------------------------------------------------------------
-- 3. CREATE TABLE portal_idempotencia (anti-replay nonce + idempotencia negocio)
--    Una fila = una escritura A11 committeada, con su traza.
--    nonce        : UNIQUE global (anti-replay, P-C-9).
--    (action,key) : UNIQUE compuesta (idempotencia de negocio).
--    payload_norm : jsonb canónico de campos de NEGOCIO (comparación de conflicto).
--    id_gasto     : FK a gastos_internos RESTRICT.
-- ----------------------------------------------------------------------------
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
  'Carril C / Slice 3b (D-C-55): infra TEST-only del portal. nonce UNIQUE = anti-replay (P-C-9); (action,idempotency_key) UNIQUE = idempotencia de negocio; payload_norm + actor = deteccion de conflicto; source_event/actor/action = traza que NO cabe en gastos_internos. Interna: sin Data API (D-C-34); la toca solo n8n via postgres.';

-- ----------------------------------------------------------------------------
-- 4. FUNCION portal_cargar_gasto_interno (DROP + CREATE, L-9F-03)
--    Cuerpo IDÉNTICO a TEST: lógica pura sin referencias a ambiente. Contrato:
--    {ok:true,data:{id_gasto,idempotente}} | {ok:false,error:{code,message,detail}}.
--    Orden atómico: advisory lock (action,key) -> anti-replay nonce -> idempotencia
--    (payload_norm + actor) -> INSERT gasto + INSERT traza (mismo sub-bloque con
--    savepoint: si la traza choca, revierte TAMBIÉN el gasto -> sin huérfano).
-- ----------------------------------------------------------------------------
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
  'Carril C / Slice 3b (D-C-55): carga atomica de gasto interno con nonce anti-replay (P-C-9) + idempotency_key de cliente + comparacion payload_norm/actor. TEST-only, fuera del canonico.';

-- ----------------------------------------------------------------------------
-- 5. HARDENING D-C-34 (portal_idempotencia): invisible al Data API. La toca solo
--    n8n (postgres owner). NO se otorga nada a service_role (a diferencia de
--    portal_usuarios). Cubre tabla + secuencia bigserial + función.
-- ----------------------------------------------------------------------------
REVOKE ALL     ON public.portal_idempotencia                 FROM PUBLIC;
REVOKE ALL     ON public.portal_idempotencia                 FROM anon;
REVOKE ALL     ON public.portal_idempotencia                 FROM authenticated;
REVOKE ALL     ON public.portal_idempotencia                 FROM service_role;
REVOKE ALL     ON SEQUENCE public.portal_idempotencia_id_registro_seq FROM PUBLIC;
REVOKE ALL     ON SEQUENCE public.portal_idempotencia_id_registro_seq FROM anon;
REVOKE ALL     ON SEQUENCE public.portal_idempotencia_id_registro_seq FROM authenticated;
REVOKE ALL     ON SEQUENCE public.portal_idempotencia_id_registro_seq FROM service_role;
REVOKE EXECUTE ON FUNCTION public.portal_cargar_gasto_interno(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.portal_cargar_gasto_interno(jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.portal_cargar_gasto_interno(jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.portal_cargar_gasto_interno(jsonb) FROM service_role;

-- ----------------------------------------------------------------------------
-- 6. ASSERT DURO COMBINADO D-C-34. Si algo queda expuesto al Data API, ABORTA.
-- ----------------------------------------------------------------------------
DO $assert$
BEGIN
  -- portal_usuarios: anon/auth NO leen; service_role SÍ lee; service_role NO escribe.
  IF has_table_privilege('anon',          'public.portal_usuarios', 'SELECT')
  OR has_table_privilege('authenticated', 'public.portal_usuarios', 'SELECT') THEN
    RAISE EXCEPTION 'ASSERT B: portal_usuarios accesible por anon/authenticated — VIOLA D-C-34. Abortado.';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.portal_usuarios', 'SELECT') THEN
    RAISE EXCEPTION 'ASSERT B: service_role no puede leer portal_usuarios — la Edge Function no resolvería rol. Abortado.';
  END IF;
  IF has_table_privilege('service_role', 'public.portal_usuarios', 'INSERT')
  OR has_table_privilege('service_role', 'public.portal_usuarios', 'UPDATE')
  OR has_table_privilege('service_role', 'public.portal_usuarios', 'DELETE') THEN
    RAISE EXCEPTION 'ASSERT B: service_role puede ESCRIBIR portal_usuarios — VIOLA D-C-34 (solo lectura). Abortado.';
  END IF;

  -- portal_idempotencia: tabla + función + secuencia cerradas a los 3 roles Data API.
  IF has_table_privilege('anon',          'public.portal_idempotencia', 'SELECT')
  OR has_table_privilege('authenticated', 'public.portal_idempotencia', 'SELECT')
  OR has_table_privilege('service_role',  'public.portal_idempotencia', 'SELECT') THEN
    RAISE EXCEPTION 'ASSERT B: portal_idempotencia accesible por un rol Data API — VIOLA D-C-34. Abortado.';
  END IF;
  IF has_function_privilege('anon',          'public.portal_cargar_gasto_interno(jsonb)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.portal_cargar_gasto_interno(jsonb)', 'EXECUTE')
  OR has_function_privilege('service_role',  'public.portal_cargar_gasto_interno(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'ASSERT B: portal_cargar_gasto_interno ejecutable por un rol Data API — VIOLA D-C-34. Abortado.';
  END IF;
  IF has_sequence_privilege('anon',          'public.portal_idempotencia_id_registro_seq', 'USAGE')
  OR has_sequence_privilege('anon',          'public.portal_idempotencia_id_registro_seq', 'SELECT')
  OR has_sequence_privilege('anon',          'public.portal_idempotencia_id_registro_seq', 'UPDATE')
  OR has_sequence_privilege('authenticated', 'public.portal_idempotencia_id_registro_seq', 'USAGE')
  OR has_sequence_privilege('authenticated', 'public.portal_idempotencia_id_registro_seq', 'SELECT')
  OR has_sequence_privilege('authenticated', 'public.portal_idempotencia_id_registro_seq', 'UPDATE')
  OR has_sequence_privilege('service_role',  'public.portal_idempotencia_id_registro_seq', 'USAGE')
  OR has_sequence_privilege('service_role',  'public.portal_idempotencia_id_registro_seq', 'SELECT')
  OR has_sequence_privilege('service_role',  'public.portal_idempotencia_id_registro_seq', 'UPDATE') THEN
    RAISE EXCEPTION 'ASSERT B: secuencia portal_idempotencia_id_registro_seq accesible por un rol Data API — VIOLA D-C-34. Abortado.';
  END IF;
END
$assert$;

-- ----------------------------------------------------------------------------
-- 7. VERIFICACIÓN ESTRUCTURAL COMBINADA (único SELECT final + fila TOTAL).
--    El SQL Editor muestra el último SELECT; todo PASS y TOTAL VERDE = Bloque B OK.
-- ----------------------------------------------------------------------------
WITH v(ord, chequeo, veredicto, detalle) AS (
  VALUES
  -- portal_usuarios
  (1,  'pu_tabla_existe',
       CASE WHEN to_regclass('public.portal_usuarios') IS NOT NULL THEN 'PASS' ELSE 'FALLO' END,
       'public.portal_usuarios'),
  (2,  'pu_fk_auth_users',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid
                          JOIN pg_namespace n ON n.oid=c.relnamespace
                          WHERE n.nspname='public' AND c.relname='portal_usuarios' AND con.contype='f')
            THEN 'PASS' ELSE 'FALLO' END,
       'FK user_id -> auth.users'),
  (3,  'pu_check_rol',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_portal_usuarios_rol')
            THEN 'PASS' ELSE 'FALLO' END,
       'rol IN (jenny,vicky,socio)'),
  (4,  'pu_anon_no_select',
       CASE WHEN NOT has_table_privilege('anon','public.portal_usuarios','SELECT') THEN 'PASS' ELSE 'FALLO' END,
       'anon NO puede SELECT'),
  (5,  'pu_authenticated_no_select',
       CASE WHEN NOT has_table_privilege('authenticated','public.portal_usuarios','SELECT') THEN 'PASS' ELSE 'FALLO' END,
       'authenticated NO puede SELECT'),
  (6,  'pu_service_role_select',
       CASE WHEN has_table_privilege('service_role','public.portal_usuarios','SELECT') THEN 'PASS' ELSE 'FALLO' END,
       'service_role SÍ puede SELECT (lector Edge Fn)'),
  (7,  'pu_service_role_no_write',
       CASE WHEN NOT has_table_privilege('service_role','public.portal_usuarios','INSERT')
             AND NOT has_table_privilege('service_role','public.portal_usuarios','UPDATE')
             AND NOT has_table_privilege('service_role','public.portal_usuarios','DELETE')
            THEN 'PASS' ELSE 'FALLO' END,
       'service_role NO escribe en runtime'),
  (8,  'pu_tabla_vacia',
       CASE WHEN (SELECT count(*) FROM public.portal_usuarios)=0 THEN 'PASS' ELSE 'FALLO' END,
       'nace vacía (seed = Bloque C)'),
  -- portal_idempotencia + función
  (9,  'pi_tabla_existe',
       CASE WHEN to_regclass('public.portal_idempotencia') IS NOT NULL THEN 'PASS' ELSE 'FALLO' END,
       'public.portal_idempotencia'),
  (10, 'pi_uq_nonce',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_portal_idempotencia_nonce') THEN 'PASS' ELSE 'FALLO' END,
       'UNIQUE(nonce) anti-replay'),
  (11, 'pi_uq_action_key',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_portal_idempotencia_action_key') THEN 'PASS' ELSE 'FALLO' END,
       'UNIQUE(action,idempotency_key)'),
  (12, 'pi_fk_gasto_restrict',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint
                          WHERE conname='fk_portal_idempotencia_gasto' AND contype='f' AND confdeltype='r')
            THEN 'PASS' ELSE 'FALLO' END,
       'FK id_gasto -> gastos_internos ON DELETE RESTRICT'),
  (13, 'fn_existe',
       CASE WHEN to_regprocedure('public.portal_cargar_gasto_interno(jsonb)') IS NOT NULL THEN 'PASS' ELSE 'FALLO' END,
       'portal_cargar_gasto_interno(jsonb)'),
  (14, 'pi_tabla_cerrada_data_api',
       CASE WHEN NOT has_table_privilege('anon','public.portal_idempotencia','SELECT')
             AND NOT has_table_privilege('authenticated','public.portal_idempotencia','SELECT')
             AND NOT has_table_privilege('service_role','public.portal_idempotencia','SELECT')
            THEN 'PASS' ELSE 'FALLO' END,
       'tabla cerrada a los 3 roles Data API'),
  (15, 'fn_cerrada_data_api',
       CASE WHEN NOT has_function_privilege('anon','public.portal_cargar_gasto_interno(jsonb)','EXECUTE')
             AND NOT has_function_privilege('authenticated','public.portal_cargar_gasto_interno(jsonb)','EXECUTE')
             AND NOT has_function_privilege('service_role','public.portal_cargar_gasto_interno(jsonb)','EXECUTE')
            THEN 'PASS' ELSE 'FALLO' END,
       'función cerrada a los 3 roles Data API'),
  (16, 'pi_secuencia_cerrada_data_api',
       CASE WHEN NOT has_sequence_privilege('anon','public.portal_idempotencia_id_registro_seq','USAGE')
             AND NOT has_sequence_privilege('anon','public.portal_idempotencia_id_registro_seq','SELECT')
             AND NOT has_sequence_privilege('anon','public.portal_idempotencia_id_registro_seq','UPDATE')
             AND NOT has_sequence_privilege('authenticated','public.portal_idempotencia_id_registro_seq','USAGE')
             AND NOT has_sequence_privilege('authenticated','public.portal_idempotencia_id_registro_seq','SELECT')
             AND NOT has_sequence_privilege('authenticated','public.portal_idempotencia_id_registro_seq','UPDATE')
             AND NOT has_sequence_privilege('service_role','public.portal_idempotencia_id_registro_seq','USAGE')
             AND NOT has_sequence_privilege('service_role','public.portal_idempotencia_id_registro_seq','SELECT')
             AND NOT has_sequence_privilege('service_role','public.portal_idempotencia_id_registro_seq','UPDATE')
            THEN 'PASS' ELSE 'FALLO' END,
       'secuencia cerrada a los 3 roles Data API'),
  (17, 'pi_tabla_vacia',
       CASE WHEN (SELECT count(*) FROM public.portal_idempotencia)=0 THEN 'PASS' ELSE 'FALLO' END,
       'nace vacía (sin seed)'),
  -- ambiente
  (18, 'ambiente_ops',
       CASE WHEN (SELECT valor FROM configuracion_general WHERE clave='ambiente')='ops' THEN 'PASS' ELSE 'FALLO' END,
       'ambiente = ops')
)
SELECT ord, chequeo, veredicto, detalle FROM v
UNION ALL
SELECT 999, 'TOTAL',
  CASE WHEN (SELECT count(*) FROM v WHERE veredicto='FALLO')=0 THEN 'VERDE' ELSE 'FRENAR' END,
  (SELECT count(*)||' FALLO de 18' FROM v WHERE veredicto='FALLO')
ORDER BY ord;

COMMIT;

-- ============================================================================
-- TEARDOWN CONSCIENTE (NO ejecutar salvo que quieras recrear de cero la infra).
-- Descomentar, seleccionar SOLO estas líneas y correr. Gate ambiente='ops'.
-- Orden: función -> portal_idempotencia -> portal_usuarios (las 3 son hoja entre
-- sí; la secuencia se borra con su tabla). portal_idempotencia tiene FK SALIENTE a
-- gastos_internos (no impide dropear portal_idempotencia; sí protegería el gasto).
--   BEGIN;
--   DO $g$ DECLARE v text; BEGIN
--     SELECT valor INTO v FROM configuracion_general WHERE clave='ambiente';
--     IF v IS DISTINCT FROM 'ops' THEN RAISE EXCEPTION 'TEARDOWN: ambiente=% no es ops.', v; END IF;
--   END $g$;
--   DROP FUNCTION IF EXISTS public.portal_cargar_gasto_interno(jsonb);
--   DROP TABLE    IF EXISTS public.portal_idempotencia;
--   DROP TABLE    IF EXISTS public.portal_usuarios;
--   COMMIT;
-- ============================================================================
