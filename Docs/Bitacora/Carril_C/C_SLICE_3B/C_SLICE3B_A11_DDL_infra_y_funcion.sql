-- ============================================================================
-- VITA DELTA · CARRIL C · SLICE 3b · A11 — DDL INFRA + FUNCION (TEST-only)
-- ----------------------------------------------------------------------------
-- Crea, en TEST, la infraestructura de idempotencia/anti-replay del portal y la
-- funcion de carga de gasto interno. TODO fuera del canonico (6B_SCHEMA_SQL.md
-- NO se toca) y fuera de OPS. Materializa D-C-55 + microcorrecciones.
--
-- QUE HACE (un solo run, transaccional):
--   1. Gate de entorno DURO: configuracion_general('ambiente')='test' + sanity
--      de cabanas 1-5 (L-7B-01: ids 1-5 son identicos TEST/OPS, no discriminan;
--      el discriminador real es el marcador 'ambiente').
--   2. CREATE TABLE IF NOT EXISTS portal_idempotencia — infra del portal,
--      precedente portal_usuarios (D-C-34). Sirve a la vez de: store anti-replay
--      de nonce (P-C-9), store de idempotencia de negocio (UNIQUE(action,key)) y
--      traza/source_event (que NO cabe en gastos_internos: no tiene la columna).
--   3. DROP + CREATE (sin OR REPLACE, L-9F-03) de portal_cargar_gasto_interno:
--      en UNA transaccion valida nonce, valida idempotency_key, compara
--      payload_norm + actor, e inserta en gastos_internos. Las 18 constraints de
--      gastos_internos son el gate de coherencia autoritativo.
--   4. Hardening D-C-34: REVOKE a PUBLIC/anon/authenticated/service_role sobre la
--      tabla, la secuencia y la funcion. La toca solo el nodo Postgres de n8n como owner
--      (postgres), igual que las funciones del motor (que estan revocadas de esos
--      4 roles y n8n igual las ejecuta). NO se expone al Data API.
--   5. Assert duro de cierre Data API + verificacion estructural (veredicto).
--
-- RE-EJECUCION: la tabla es CREATE IF NOT EXISTS (re-correr no la pisa ni borra
-- datos de smoke); la funcion es DROP+CREATE (re-correr la re-despliega). Para
-- CAMBIAR el ESQUEMA de la tabla hay que DROP TABLE consciente y separado primero
-- (es infra TEST-only, sin datos reales).
--
-- COMO CORRER: SQL Editor de Supabase del proyecto TEST, con NADA seleccionado
-- (L-8A-01), todo el archivo de una. Si algo no calza, RAISE aborta TODA la
-- transaccion: o entra completa y consistente, o no entra nada.
-- Resultado esperado: una tabla de veredicto, toda en PASS.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. GATE DE ENTORNO (ambiente='test' es la verdad; cabanas 1-5 es sanity)
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb text;
  v_cab int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE 3b/A11: ambiente=% (esperado test). Abortado para no tocar OPS.',
      COALESCE(v_amb, '<ausente>');
  END IF;

  SELECT count(*) INTO v_cab
  FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
  WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana = e.id AND c.nombre = e.nom);
  IF v_cab <> 5 THEN
    RAISE EXCEPTION 'GATE 3b/A11: identidad de cabanas no coincide (% de 5). DB inesperada.', v_cab;
  END IF;
END
$gate$;

-- ----------------------------------------------------------------------------
-- 2. TABLA INFRA portal_idempotencia
--    Una fila = una escritura A11 efectivamente committeada, con su traza.
--    nonce            : UNIQUE global (anti-replay, P-C-9).
--    (action,key)     : UNIQUE compuesta (idempotencia de negocio; microcorr. 1).
--    payload_norm     : jsonb canonico de los campos de NEGOCIO (comparacion C).
--    source_event     : determinístico por accion logica = 'portal_a11_'||key (microcorr. 3).
--    id_gasto         : FK a gastos_internos RESTRICT (paridad del schema).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.portal_idempotencia (
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
-- 3. FUNCION portal_cargar_gasto_interno (DROP + CREATE, L-9F-03)
--    Contrato: {ok:true,data:{id_gasto,idempotente}} | {ok:false,error:{code,message,detail}}.
--    Orden atomico: advisory lock por (action,key) -> anti-replay nonce ->
--    idempotencia (payload_norm + actor) -> INSERT gasto + INSERT traza (mismo
--    sub-bloque: si la traza choca por UNIQUE, el savepoint revierte TAMBIEN el
--    gasto -> nunca queda gasto huerfano).
-- ----------------------------------------------------------------------------
-- CONTRATO DE CAMPOS (para el wrapper directo y el gateway):
--   CONTROL server-side (los inyecta el wrapper directo / el gateway, NUNCA el
--   cliente): actor, rol, nonce, request_ts.
--   DERIVADOS dentro de la funcion (no se leen del payload -> inherentemente
--   seguros): source_event = 'portal_a11_'||idempotency_key ; creado_por = actor.
--   CLIENTE: idempotency_key + campos de negocio (fecha, periodo [opcional],
--   clase, clase_sugerida, etiqueta, monto, id_zona, id_cabana, pagador_tipo,
--   id_socio_pagador, medio_pago, comentario, comprobante_url).
--   CAMINO DIRECTO (sin gateway): el wrapper n8n DEBE generar/inyectar el nonce
--   antes de llamar a esta funcion. El payload del cliente NO puede traer nonce,
--   actor, rol, source_event, creado_por ni request_ts: el wrapper arma el jsonb
--   tomando SOLO los campos de negocio del cliente + idempotency_key, y agrega el
--   control server-side por encima.
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
-- 4. HARDENING D-C-34 — invisible al Data API. La toca solo n8n (postgres owner),
--    igual que las funciones del motor (revocadas de los 4 roles y aun ejecutables
--    por n8n). NO se otorga nada a service_role (a diferencia de portal_usuarios,
--    que SI la lee la Edge Function; esta tabla no la lee la Edge Function).
-- ----------------------------------------------------------------------------
REVOKE ALL     ON public.portal_idempotencia                 FROM PUBLIC;
REVOKE ALL     ON public.portal_idempotencia                 FROM anon;
REVOKE ALL     ON public.portal_idempotencia                 FROM authenticated;
REVOKE ALL     ON public.portal_idempotencia                 FROM service_role;
-- secuencia de la bigserial (portal_idempotencia_id_registro_seq): cerrarla tambien.
-- El owner (postgres = la conexion de n8n) conserva nextval; los 4 roles del Data API no.
REVOKE ALL     ON SEQUENCE public.portal_idempotencia_id_registro_seq FROM PUBLIC;
REVOKE ALL     ON SEQUENCE public.portal_idempotencia_id_registro_seq FROM anon;
REVOKE ALL     ON SEQUENCE public.portal_idempotencia_id_registro_seq FROM authenticated;
REVOKE ALL     ON SEQUENCE public.portal_idempotencia_id_registro_seq FROM service_role;
REVOKE EXECUTE ON FUNCTION public.portal_cargar_gasto_interno(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.portal_cargar_gasto_interno(jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.portal_cargar_gasto_interno(jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.portal_cargar_gasto_interno(jsonb) FROM service_role;

-- ----------------------------------------------------------------------------
-- 5a. ASSERT DURO: ni la tabla ni la funcion accesibles por el Data API.
-- ----------------------------------------------------------------------------
DO $assert$
BEGIN
  IF has_table_privilege('anon',          'public.portal_idempotencia', 'SELECT')
  OR has_table_privilege('authenticated', 'public.portal_idempotencia', 'SELECT')
  OR has_table_privilege('service_role',  'public.portal_idempotencia', 'SELECT') THEN
    RAISE EXCEPTION 'ASSERT 3b/A11: portal_idempotencia accesible por un rol Data API — VIOLA D-C-34. Abortado.';
  END IF;
  IF has_function_privilege('anon',          'public.portal_cargar_gasto_interno(jsonb)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.portal_cargar_gasto_interno(jsonb)', 'EXECUTE')
  OR has_function_privilege('service_role',  'public.portal_cargar_gasto_interno(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'ASSERT 3b/A11: portal_cargar_gasto_interno ejecutable por un rol Data API — VIOLA D-C-34. Abortado.';
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
    RAISE EXCEPTION 'ASSERT 3b/A11: secuencia portal_idempotencia_id_registro_seq accesible por un rol Data API — VIOLA D-C-34. Abortado.';
  END IF;
END
$assert$;

-- ----------------------------------------------------------------------------
-- 5b. VERIFICACION ESTRUCTURAL (veredicto). El editor muestra el ultimo SELECT.
-- ----------------------------------------------------------------------------
SELECT * FROM (
  SELECT 1 AS ord, 'tabla_portal_idempotencia'::text AS chequeo,
    CASE WHEN to_regclass('public.portal_idempotencia') IS NOT NULL THEN 'PASS' ELSE 'FALLO' END::text AS veredicto
  UNION ALL
  SELECT 2, 'uq_nonce',
    CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_portal_idempotencia_nonce') THEN 'PASS' ELSE 'FALLO' END
  UNION ALL
  SELECT 3, 'uq_action_idempotency_key',
    CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_portal_idempotencia_action_key') THEN 'PASS' ELSE 'FALLO' END
  UNION ALL
  SELECT 4, 'fk_id_gasto_a_gastos_internos',
    CASE WHEN EXISTS (SELECT 1 FROM pg_constraint
                       WHERE conname='fk_portal_idempotencia_gasto' AND contype='f' AND confdeltype='r') THEN 'PASS' ELSE 'FALLO' END
  UNION ALL
  SELECT 5, 'funcion_portal_cargar_gasto_interno',
    CASE WHEN to_regprocedure('public.portal_cargar_gasto_interno(jsonb)') IS NOT NULL THEN 'PASS' ELSE 'FALLO' END
  UNION ALL
  SELECT 6, 'tabla_cerrada_data_api',
    CASE WHEN NOT has_table_privilege('anon','public.portal_idempotencia','SELECT')
          AND NOT has_table_privilege('authenticated','public.portal_idempotencia','SELECT')
          AND NOT has_table_privilege('service_role','public.portal_idempotencia','SELECT') THEN 'PASS' ELSE 'FALLO' END
  UNION ALL
  SELECT 7, 'funcion_cerrada_data_api',
    CASE WHEN NOT has_function_privilege('anon','public.portal_cargar_gasto_interno(jsonb)','EXECUTE')
          AND NOT has_function_privilege('authenticated','public.portal_cargar_gasto_interno(jsonb)','EXECUTE')
          AND NOT has_function_privilege('service_role','public.portal_cargar_gasto_interno(jsonb)','EXECUTE') THEN 'PASS' ELSE 'FALLO' END
  UNION ALL
  SELECT 8, 'secuencia_cerrada_data_api',
    CASE WHEN NOT has_sequence_privilege('anon','public.portal_idempotencia_id_registro_seq','USAGE')
          AND NOT has_sequence_privilege('anon','public.portal_idempotencia_id_registro_seq','SELECT')
          AND NOT has_sequence_privilege('anon','public.portal_idempotencia_id_registro_seq','UPDATE')
          AND NOT has_sequence_privilege('authenticated','public.portal_idempotencia_id_registro_seq','USAGE')
          AND NOT has_sequence_privilege('authenticated','public.portal_idempotencia_id_registro_seq','SELECT')
          AND NOT has_sequence_privilege('authenticated','public.portal_idempotencia_id_registro_seq','UPDATE')
          AND NOT has_sequence_privilege('service_role','public.portal_idempotencia_id_registro_seq','USAGE')
          AND NOT has_sequence_privilege('service_role','public.portal_idempotencia_id_registro_seq','SELECT')
          AND NOT has_sequence_privilege('service_role','public.portal_idempotencia_id_registro_seq','UPDATE') THEN 'PASS' ELSE 'FALLO' END
) v
ORDER BY ord;

COMMIT;
