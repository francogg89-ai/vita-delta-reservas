-- ============================================================================
-- BOOTSTRAP ENTORNO NUEVO v1.9.0 — 03: PARTE D (PORTAL OPERATIVO INTERNO) · DDL
-- Fuente: 6B_SCHEMA_SQL.md v1.9.0, PARTE D, Bloques D1→D5 (EXTRACCIÓN LITERAL).
--   Capa de base de datos del Carril C / portal: tablas portal_usuarios y
--   portal_idempotencia + función portal_cargar_gasto_interno(jsonb) + hardening.
--   Cierra con D5, un bloque DO de asserts (auto-test): su veredicto sale por el
--   panel de NOTICE, no como fila (L-RDEV-04). La fila-veredicto final del
--   entorno vive en 03_VERIFY_FINAL_ENTORNO.sql.
-- ----------------------------------------------------------------------------
-- ESTADO DE ENTRADA: 02_VERIFY == PARTE_C_OK. Corre DESPUÉS de la Parte C
--   (la FK de portal_idempotencia apunta a gastos_internos).
-- PRERREQUISITOS: proyecto Supabase (usa el schema auth para la FK de
--   portal_usuarios y los roles anon/authenticated/service_role del Data API en
--   el hardening). No requiere extensiones adicionales.
-- USO: SQL Editor del PROYECTO NUEVO (confirmar Project Ref por URL; nunca OPS).
--   Pegar el archivo COMPLETO o por SECCIONES "-- ═══ BLOQUE DN ═══", una a la
--   vez con NADA seleccionado (L-8A-01).
-- ----------------------------------------------------------------------------
-- SOLO ESTRUCTURA: NO siembra nada (sin seed de portal_usuarios, sin usuarios de
--   auth, sin secretos, sin URLs, sin Project ID, sin datos reales, sin marcador
--   de ambiente). Las tablas nacen VACÍAS. El seed de portal_usuarios y los
--   secretos del gateway viven FUERA de este kit y del canónico.
-- BASE CERTIFICADA: la estructura parte de la certificada por el Bloque H
--   (TOTAL_PORTAL = dee953e867aed06a9c65836bac14e8f7); el único delta intencional
--   son dos comentarios SQL actualizados al estatus canónico (portal_idempotencia
--   y la función). Por ese delta de comentarios, este bootstrap NO reproduce
--   byte-idéntico esa huella.
-- ============================================================================


-- ═══ BLOQUE D1 — Tabla portal_usuarios ═════════════════════════════════════
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


-- ═══ BLOQUE D2 — Tabla portal_idempotencia ═════════════════════════════════
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


-- ═══ BLOQUE D3 — Función portal_cargar_gasto_interno(jsonb) ════════════════
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


-- ═══ BLOQUE D4 — Hardening (REVOKE/GRANT) ══════════════════════════════════
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
-- Único GRANT de runtime: service_role LEE portal_usuarios (no escribe).
GRANT  SELECT  ON public.portal_usuarios TO service_role;


-- ═══ BLOQUE D5 — Verificación estructural y de hardening (auto-test) ═══════
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
  v_pu   oid := to_regclass('public.portal_usuarios');
  v_pi   oid := to_regclass('public.portal_idempotencia');
  v_seq  oid := to_regclass('public.portal_idempotencia_id_registro_seq');
  v_fn   oid := to_regprocedure('public.portal_cargar_gasto_interno(jsonb)');
  v_auth oid := to_regclass('auth.users');
  v_gas  oid := to_regclass('public.gastos_internos');
  r      record;
  v_n    integer;
  v_txt  text;
BEGIN
  -- ── existencia ──
  IF v_pu   IS NULL THEN RAISE EXCEPTION 'D5: portal_usuarios ausente'; END IF;
  IF v_pi   IS NULL THEN RAISE EXCEPTION 'D5: portal_idempotencia ausente'; END IF;
  IF v_seq  IS NULL THEN RAISE EXCEPTION 'D5: secuencia portal_idempotencia_id_registro_seq ausente'; END IF;
  IF v_fn   IS NULL THEN RAISE EXCEPTION 'D5: portal_cargar_gasto_interno(jsonb) ausente'; END IF;
  IF v_auth IS NULL THEN RAISE EXCEPTION 'D5: auth.users ausente — se requiere proyecto Supabase'; END IF;
  IF v_gas  IS NULL THEN RAISE EXCEPTION 'D5: gastos_internos ausente — la PARTE D corre DESPUES de la PARTE C'; END IF;

  -- ── FK portal_usuarios.user_id -> auth.users(id) ON DELETE CASCADE, exacta, 1 columna ──
  SELECT con.confrelid, con.confdeltype,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.conrelid  AND a.attnum=con.conkey[1])  AS lcol,
         (SELECT a.attname FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1]) AS rcol,
         cardinality(con.conkey) AS ncols
    INTO r
    FROM pg_constraint con
   WHERE con.conrelid=v_pu AND con.contype='f';
  IF NOT FOUND THEN RAISE EXCEPTION 'D5: portal_usuarios sin FK'; END IF;
  IF r.confrelid IS DISTINCT FROM v_auth OR r.lcol<>'user_id' OR r.rcol<>'id'
     OR r.ncols<>1 OR r.confdeltype<>'c' THEN
    RAISE EXCEPTION 'D5: FK de portal_usuarios no es exactamente user_id -> auth.users(id) ON DELETE CASCADE [ref=%, lcol=%, rcol=%, ncols=%, del=%]',
      r.confrelid::regclass, r.lcol, r.rcol, r.ncols, r.confdeltype;
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

  -- ── CHECK de rol en la relación correcta + dominio {jenny,vicky,socio} ──
  SELECT pg_get_constraintdef(con.oid) INTO v_txt
    FROM pg_constraint con
   WHERE con.conrelid=v_pu AND con.contype='c' AND con.conname='chk_portal_usuarios_rol';
  IF v_txt IS NULL THEN RAISE EXCEPTION 'D5: falta CHECK chk_portal_usuarios_rol en portal_usuarios'; END IF;
  IF v_txt NOT ILIKE '%jenny%' OR v_txt NOT ILIKE '%vicky%' OR v_txt NOT ILIKE '%socio%' THEN
    RAISE EXCEPTION 'D5: CHECK de rol no restringe a {jenny,vicky,socio}: %', v_txt;
  END IF;

  -- ── UNIQUEs en la relación correcta, por conjunto de columnas exacto ──
  IF NOT EXISTS (SELECT 1 FROM pg_constraint con
                  WHERE con.conrelid=v_pu AND con.contype='u' AND con.conname='uq_portal_usuarios_nombre'
                    AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
                           FROM unnest(con.conkey) AS ck(attnum)
                           JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=ck.attnum) = ARRAY['nombre']) THEN
    RAISE EXCEPTION 'D5: uq_portal_usuarios_nombre no es UNIQUE(nombre) en portal_usuarios';
  END IF;
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

  -- ── firma de la función: RETURNS jsonb + SECURITY INVOKER + plpgsql ──
  SELECT p.prorettype, p.prosecdef, l.lanname INTO r
    FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=v_fn;
  IF r.prorettype IS DISTINCT FROM 'jsonb'::regtype THEN RAISE EXCEPTION 'D5: la función no RETURNS jsonb'; END IF;
  IF r.prosecdef THEN RAISE EXCEPTION 'D5: la función no es SECURITY INVOKER'; END IF;
  IF r.lanname<>'plpgsql' THEN RAISE EXCEPTION 'D5: la función no es plpgsql'; END IF;

  -- ── hardening por ACL real (aclexplode cubre TODOS los privilegios incl. MAINTAIN) ──
  -- portal_usuarios: la ÚNICA concesión a un rol Data API/PUBLIC debe ser (service_role, SELECT)
  SELECT count(*) INTO v_n
    FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
   WHERE c.oid=v_pu
     AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
     AND NOT (a.grantee<>0 AND pg_get_userbyid(a.grantee)='service_role' AND a.privilege_type='SELECT');
  IF v_n>0 THEN RAISE EXCEPTION 'D5: portal_usuarios con privilegios Data API distintos de service_role:SELECT (%)', v_n; END IF;
  IF NOT has_table_privilege('service_role','public.portal_usuarios','SELECT') THEN
    RAISE EXCEPTION 'D5: service_role no puede leer portal_usuarios'; END IF;

  -- portal_idempotencia: cero privilegios Data API/PUBLIC
  SELECT count(*) INTO v_n
    FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
   WHERE c.oid=v_pi AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_n>0 THEN RAISE EXCEPTION 'D5: portal_idempotencia con privilegios Data API (%)', v_n; END IF;

  -- secuencia: cero privilegios Data API/PUBLIC
  SELECT count(*) INTO v_n
    FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
   WHERE c.oid=v_seq AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_n>0 THEN RAISE EXCEPTION 'D5: secuencia con privilegios Data API (%)', v_n; END IF;

  -- función: proacl NO nula (si fuera nula, PUBLIC ejecuta) + cero EXECUTE Data API/PUBLIC
  IF (SELECT proacl FROM pg_proc WHERE oid=v_fn) IS NULL THEN
    RAISE EXCEPTION 'D5: proacl de la función es NULL (PUBLIC ejecuta) — falta REVOKE';
  END IF;
  SELECT count(*) INTO v_n
    FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
   WHERE p.oid=v_fn AND a.privilege_type='EXECUTE'
     AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
  IF v_n>0 THEN RAISE EXCEPTION 'D5: función ejecutable por rol Data API (%)', v_n; END IF;

  -- ── RLS/policies: estado canónico = RLS off + force off + 0 policies ──
  IF EXISTS (SELECT 1 FROM pg_class WHERE oid IN (v_pu,v_pi) AND (relrowsecurity OR relforcerowsecurity)) THEN
    RAISE EXCEPTION 'D5: RLS habilitada en una tabla del portal (esperado off)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polrelid IN (v_pu,v_pi)) THEN
    RAISE EXCEPTION 'D5: hay policies sobre el portal (esperado 0)';
  END IF;

  RAISE NOTICE 'PARTE D OK: estructura exacta (FK user_id->auth.users(id) CASCADE; FK id_gasto->gastos_internos(id_gasto) RESTRICT; CHECK rol {jenny,vicky,socio}; UNIQUEs nonce y (action,idempotency_key); funcion RETURNS jsonb SECURITY INVOKER) + hardening D-C-34 por ACL real incl. MAINTAIN (portal_usuarios solo service_role:SELECT; portal_idempotencia/secuencia/funcion sin Data API; proacl no nula; RLS off, 0 policies). Sin chequear datos ni ambiente.';
END
$verif_portal$;
