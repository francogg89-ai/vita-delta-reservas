-- =====================================================================
-- B1.3-A - ROLLBACK del artefacto A (vigencias semanales)
-- Restaura el estado post-B1.2-core / B1.1 BYTE-IDENTICO:
--   interno _resolver_horario(bigint,date,boolean) = B1.2-core (fp 566ea522...),
--   helper 7-param (fp 871fcde5...), cabecera vigencias_horario_base 4-col (B1.1),
--   guard crear_vigencia_horario(jsonb) B1.1, trigger trg_vig_guard B1.1.
--   Elimina vigencias_horario_detalle, la cabecera sin-horas, el helper jsonb,
--   el guard semanal y la barrera de completitud. El WRAPPER no se toca (fp 1bd96c89...).
-- ALCANCE: TEST-only. Transaccion unica. Doble lock (10,0)->(919010). Sin CASCADE.
--   Los datos de vigencia semanal (cabecera+detalle) se PIERDEN (shape incompatible).
-- Ejecutar en Supabase SQL Editor SIN texto seleccionado (script entero).
-- =====================================================================

BEGIN;

SELECT pg_advisory_xact_lock(10, 0);
SELECT pg_advisory_xact_lock(919010);

-- ---- GATE: estado esperado = A aplicado ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  v_wrap text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ROLLBACK B1.3-A: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'ROLLBACK B1.3-A: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regclass('public.vigencias_horario_detalle') IS NULL THEN
    RAISE EXCEPTION 'ROLLBACK B1.3-A: no existe vigencias_horario_detalle (A no aplicado?). Abortando.';
  END IF;
  IF to_regprocedure('public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'ROLLBACK B1.3-A: no existe helper jsonb (A no aplicado?). Abortando.';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='vigencias_horario_base' AND column_name='hora_checkin_default') THEN
    RAISE EXCEPTION 'ROLLBACK B1.3-A: la cabecera ya tiene shape 4-col (A no aplicado?). Abortando.';
  END IF;
  v_wrap := md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure));
  IF v_wrap IS DISTINCT FROM '1bd96c89e587b15582fd7b2e29ae7e18' THEN
    RAISE EXCEPTION 'ROLLBACK B1.3-A: wrapper fp=% (esperado 1bd96c89...). Abortando.', v_wrap;
  END IF;
  RAISE NOTICE 'GATE OK: A aplicado (detalle+helper jsonb presentes, cabecera sin horas viejas, wrapper intacto).';
END
$gate$;

CREATE TEMP TABLE _rb_meta(k text, v text) ON COMMIT DROP;
INSERT INTO _rb_meta VALUES ('wrapper_pre', md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure)));

-- ---- Derribo de los objetos de A (orden: triggers -> guard -> helper -> tablas) ----
DROP TRIGGER IF EXISTS trg_vig_guard_detalle ON public.vigencias_horario_detalle;
DROP TRIGGER IF EXISTS trg_vig_guard ON public.vigencias_horario_base;
DROP FUNCTION IF EXISTS public.trg_guard_vigencias();
DROP FUNCTION public.crear_vigencia_horario(jsonb);
DROP FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb);
DROP TABLE public.vigencias_horario_detalle;
DROP TABLE public.vigencias_horario_base;

-- =====================================================================
-- (1) Cabecera 4-col (B1.1 DDL, verbatim)
-- =====================================================================
CREATE TABLE public.vigencias_horario_base (
  id_vigencia           BIGSERIAL PRIMARY KEY,
  fecha_desde           DATE NOT NULL,
  fecha_hasta           DATE,
  abierta               BOOLEAN NOT NULL DEFAULT FALSE,
  hora_checkin_default  TIME NOT NULL,
  hora_checkin_domingo  TIME NOT NULL,
  hora_checkout_default TIME NOT NULL,
  hora_checkout_domingo TIME NOT NULL,
  motivo                TEXT NOT NULL,
  creado_por            TEXT NOT NULL,
  activo                BOOLEAN NOT NULL DEFAULT TRUE,
  source_event          TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Vigencia: sin fin explicito (abierta) o rango cerrado inclusivo. NO
  -- fecha_hasta NULL = para siempre (respeta R0). Bordes inclusivos (espejo
  -- overrides: fecha_desde <= p_fecha <= fecha_hasta).
  CONSTRAINT chk_vigencias_abierta CHECK (
    (abierta AND fecha_hasta IS NULL)
    OR (NOT abierta AND fecha_hasta IS NOT NULL AND fecha_hasta >= fecha_desde)
  ),
  -- G2: turno pegado >= 2h para la base resultante (default y domingo).
  CONSTRAINT chk_vigencias_gap CHECK (
    (hora_checkin_default - hora_checkout_default) >= INTERVAL '2 hours'
    AND (hora_checkin_domingo - hora_checkout_domingo) >= INTERVAL '2 hours'
  ),
  -- Ventana cliente [07:00, 22:00] en las 4 horas.
  CONSTRAINT chk_vigencias_ventana CHECK (
    hora_checkin_default  BETWEEN TIME '07:00' AND TIME '22:00'
    AND hora_checkin_domingo  BETWEEN TIME '07:00' AND TIME '22:00'
    AND hora_checkout_default BETWEEN TIME '07:00' AND TIME '22:00'
    AND hora_checkout_domingo BETWEEN TIME '07:00' AND TIME '22:00'
  ),
  -- Auditoria minima de creacion: sin blancos.
  CONSTRAINT chk_vigencias_motivo      CHECK (btrim(motivo) <> ''),
  CONSTRAINT chk_vigencias_creado_por  CHECK (btrim(creado_por) <> ''),
  CONSTRAINT chk_vigencias_source_event CHECK (source_event IS NULL OR btrim(source_event) <> ''),

  -- No-solapamiento entre vigencias ACTIVAS (global-only, rango puro).
  -- Rango inclusivo cerrado o abierto (borde superior NULL = sin fin).
  CONSTRAINT exc_vigencias_no_overlap EXCLUDE USING gist (
    (CASE WHEN abierta THEN daterange(fecha_desde, NULL)
          ELSE daterange(fecha_desde, fecha_hasta, '[]') END) WITH &&
  ) WHERE (activo)
);

-- ---- Hardening: REVOKE ALL sobre tabla y secuencia ----
REVOKE ALL ON TABLE    public.vigencias_horario_base                    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE public.vigencias_horario_base_id_vigencia_seq    FROM PUBLIC, anon, authenticated, service_role;

-- ---- Comentario ----
COMMENT ON TABLE public.vigencias_horario_base IS
  'B1.1 motor horarios. Capa de vigencias de horario base, global-only, bordes inclusivos (espejo overrides). abierta=true => sin fin explicito (NO fecha_hasta NULL=para siempre, respeta R0). Reemplaza la base completa (default+domingo x checkin+checkout) para las fechas que cubre. INERTE hasta B1.2: el resolver NO la lee todavia. Precedencia futura: config(fallback)->vigencia->override global->override cabana. No-solapamiento por exc_vigencias_no_overlap (GiST rango puro, sin btree_gist). G2/ventana/auditoria por CHECK. G1 por funcion sancionada + trigger diferido trg_vig_guard. B1.1 - TEST-only inerte.';

-- =====================================================================
-- (2) Interno B1.2-core (verbatim: DROP IF EXISTS semanal + CREATE + REVOKE + COMMENT)
-- =====================================================================
DROP FUNCTION IF EXISTS public._resolver_horario(bigint,date,boolean);
CREATE FUNCTION public._resolver_horario(p_id_cabana BIGINT, p_fecha DATE, p_incluir_vigencias BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY INVOKER AS $fn$
DECLARE
  v_config JSONB; v_ventana_min TIME; v_ventana_max TIME;
  v_es_domingo BOOLEAN := (EXTRACT(DOW FROM p_fecha) = 0);
  v_tipo TEXT; v_base TIME; v_origen TEXT;
  v_ovr_id BIGINT; v_ovr_valor TEXT; v_ovr_cabana BOOLEAN;
  v_hora TIME; v_res JSONB := '{}'::JSONB;
  v_vig_ci_def TIME; v_vig_ci_dom TIME; v_vig_co_def TIME; v_vig_co_dom TIME;
  v_vig_found BOOLEAN := FALSE;
BEGIN
  SELECT jsonb_object_agg(clave, valor) INTO v_config FROM public.configuracion_general
  WHERE clave IN ('hora_checkin_default','hora_checkin_domingo','hora_checkout_default','hora_checkout_domingo','hora_checkin_max_cliente','hora_checkout_min_cliente');
  v_ventana_min := COALESCE((v_config->>'hora_checkout_min_cliente')::TIME, TIME '07:00');
  v_ventana_max := COALESCE((v_config->>'hora_checkin_max_cliente')::TIME, TIME '22:00');
  -- Capa vigencia (solo si flag). A lo sumo 1 activa cubre la fecha (garantia EXCLUDE).
  IF p_incluir_vigencias THEN
    SELECT hora_checkin_default, hora_checkin_domingo, hora_checkout_default, hora_checkout_domingo
      INTO v_vig_ci_def, v_vig_ci_dom, v_vig_co_def, v_vig_co_dom
    FROM public.vigencias_horario_base
    WHERE activo AND (CASE WHEN abierta THEN daterange(fecha_desde,NULL) ELSE daterange(fecha_desde,fecha_hasta,'[]') END) @> p_fecha
    LIMIT 1;
    v_vig_found := FOUND;
  END IF;
  FOREACH v_tipo IN ARRAY ARRAY['hora_checkin','hora_checkout'] LOOP
    -- Paso A: base = vigencia (si cubre) ELSE config
    IF v_vig_found THEN
      IF v_es_domingo THEN
        v_base := CASE v_tipo WHEN 'hora_checkin' THEN v_vig_ci_dom ELSE v_vig_co_dom END; v_origen := 'vigencia_domingo';
      ELSE
        v_base := CASE v_tipo WHEN 'hora_checkin' THEN v_vig_ci_def ELSE v_vig_co_def END; v_origen := 'vigencia';
      END IF;
    ELSE
      IF v_es_domingo THEN
        v_base := COALESCE((v_config->>(v_tipo||'_domingo'))::TIME, CASE v_tipo WHEN 'hora_checkin' THEN TIME '18:00' ELSE TIME '16:00' END); v_origen := 'patron_domingo';
      ELSE
        v_base := COALESCE((v_config->>(v_tipo||'_default'))::TIME, CASE v_tipo WHEN 'hora_checkin' THEN TIME '13:00' ELSE TIME '10:00' END); v_origen := 'base';
      END IF;
    END IF;
    -- Paso B: override ganador (IDENTICO R0)
    SELECT id_override, valor, (id_cabana IS NOT NULL) INTO v_ovr_id, v_ovr_valor, v_ovr_cabana
    FROM public.overrides_operativos WHERE activo AND tipo_override = v_tipo
      AND fecha_desde <= p_fecha AND p_fecha <= COALESCE(fecha_hasta, fecha_desde)
      AND (id_cabana = p_id_cabana OR id_cabana IS NULL)
    ORDER BY (id_cabana IS NOT NULL) DESC, created_at DESC, id_override DESC LIMIT 1;
    -- Paso C: override o base (IDENTICO R0)
    IF v_ovr_valor IS NOT NULL THEN
      IF v_ovr_valor !~ '^\d{2}:\d{2}(:\d{2})?$' THEN
        RETURN jsonb_build_object('ok',false,'error','override_hora_invalido','causa','formato_invalido','tipo_override',v_tipo,'id_override',v_ovr_id,'valor',v_ovr_valor,'ventana_min',v_ventana_min,'ventana_max',v_ventana_max); END IF;
      BEGIN v_hora := v_ovr_valor::TIME; EXCEPTION WHEN data_exception THEN
        RETURN jsonb_build_object('ok',false,'error','override_hora_invalido','causa','cast_invalido','tipo_override',v_tipo,'id_override',v_ovr_id,'valor',v_ovr_valor,'ventana_min',v_ventana_min,'ventana_max',v_ventana_max); END;
      IF v_hora < v_ventana_min OR v_hora > v_ventana_max THEN
        RETURN jsonb_build_object('ok',false,'error','override_hora_invalido','causa','fuera_de_ventana','tipo_override',v_tipo,'id_override',v_ovr_id,'valor',v_ovr_valor,'ventana_min',v_ventana_min,'ventana_max',v_ventana_max); END IF;
      v_origen := CASE WHEN v_ovr_cabana THEN 'override_cabana' ELSE 'override_global' END;
    ELSE v_hora := v_base; END IF;
    IF v_tipo = 'hora_checkin' THEN v_res := v_res || jsonb_build_object('hora_checkin',v_hora,'origen_checkin',v_origen);
    ELSE v_res := v_res || jsonb_build_object('hora_checkout',v_hora,'origen_checkout',v_origen); END IF;
  END LOOP;
  RETURN jsonb_build_object('ok',true) || v_res;
END; $fn$;

REVOKE EXECUTE ON FUNCTION public._resolver_horario(bigint,date,boolean) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public._resolver_horario(bigint,date,boolean) IS
  'B1.2-core INTERNO owner-only. Concentra la precedencia config(fallback)->vigencia->override_global->override_cabana, por tipo. Flag p_incluir_vigencias: true=capa base es la vigencia que cubre la fecha (si hay) o config; false=siempre config (ciego, byte-identico a R0 para fechas sin vigencia; para provenance G1). Lookup de vigencia una sola vez (global; EXCLUDE garantiza <=1 activa por fecha; el @> resuelve por el indice GiST exc_vigencias_no_overlap, confirmado por EXPLAIN del smoke de perf). Override (Paso B/C) y ventana anti-typo 07:00-22:00 identicos a R0. Origenes: base|patron_domingo (config), vigencia|vigencia_domingo, override_global|override_cabana. Devuelve {ok:true,hora_checkin,hora_checkout,origen_checkin,origen_checkout} o {ok:false,error:override_hora_invalido,causa:...}. read-only. El wrapper resolver_horario delega con true; el helper vigencias_conflictos_comprometidos con false. B1.2-core - TEST.';

-- =====================================================================
-- (3) Helper 7-param B1.2-core (verbatim: CREATE + REVOKE + COMMENT)
-- =====================================================================
CREATE FUNCTION public.vigencias_conflictos_comprometidos(
  p_fecha_desde DATE, p_fecha_hasta DATE, p_abierta BOOLEAN,
  p_ci_def TIME, p_ci_dom TIME, p_co_def TIME, p_co_dom TIME
) RETURNS jsonb
LANGUAGE sql
STABLE
AS $help$
  WITH comprometidos AS (
    -- Reservas vivas: un lado por fila (checkout y checkin)
    SELECT 'reserva'::text AS tipo, id_reserva AS id, id_cabana, fecha_checkout AS fecha, 'checkout'::text AS lado, hora_checkout AS frozen
      FROM public.reservas WHERE estado IN ('confirmada','activa','completada')
    UNION ALL
    SELECT 'reserva', id_reserva, id_cabana, fecha_checkin, 'checkin', hora_checkin
      FROM public.reservas WHERE estado IN ('confirmada','activa','completada')
    UNION ALL
    -- Pre-reservas vigentes (misma definicion que S0)
    SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_out, 'checkout', hora_checkout
      FROM public.pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'
    UNION ALL
    SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_in, 'checkin', hora_checkin
      FROM public.pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'
  ),
  en_rango AS (
    SELECT * FROM comprometidos
    WHERE fecha >= p_fecha_desde AND (p_abierta OR fecha <= p_fecha_hasta)
  ),
  eval AS (
    SELECT c.tipo, c.id, c.id_cabana, c.fecha, c.lado, c.frozen,
      COALESCE((r.res->>'ok')::boolean, false) AS resolver_ok,
      (r.res->>'origen_checkin')  AS ori_ci,
      (r.res->>'origen_checkout') AS ori_co,
      CASE WHEN EXTRACT(DOW FROM c.fecha) = 0 THEN p_ci_dom ELSE p_ci_def END AS vig_ci,
      CASE WHEN EXTRACT(DOW FROM c.fecha) = 0 THEN p_co_dom ELSE p_co_def END AS vig_co
    FROM en_rango c
    CROSS JOIN LATERAL (SELECT public._resolver_horario(c.id_cabana, c.fecha, false) AS res) r
  ),
  viol AS (
    SELECT tipo, id, id_cabana, fecha, lado,
      CASE WHEN NOT resolver_ok THEN 'resolver_horario_invalido' ELSE 'turno_pegado' END AS motivo
    FROM eval
    WHERE
      -- FAIL-CLOSED: si el resolver no puede determinar provenance (ok<>true),
      -- no se puede verificar que la base no gobierne => conflicto explicito.
      NOT resolver_ok
      -- lado='checkout' (E sale): protege una llegada futura (vig_ci) donde la base gobierna el checkin
      OR (resolver_ok AND lado = 'checkout' AND ori_ci IN ('base','patron_domingo') AND (vig_ci - frozen) < INTERVAL '2 hours')
      -- lado='checkin' (E entra): protege una salida futura (vig_co) donde la base gobierna el checkout
      OR (resolver_ok AND lado = 'checkin'  AND ori_co IN ('base','patron_domingo') AND (frozen - vig_co) < INTERVAL '2 hours')
  )
  SELECT COALESCE(
    jsonb_agg(jsonb_build_object('fecha', fecha, 'id_cabana', id_cabana, 'tipo', tipo, 'id', id, 'lado', lado, 'motivo', motivo)
              ORDER BY fecha, id_cabana, id),
    '[]'::jsonb)
  FROM viol;
$help$;

REVOKE EXECUTE ON FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time) IS
  'B1.2-core helper G1 compartido (crear_vigencia_horario + trg_vig_guard). Evalua una vigencia PROSPECTIVA contra comprometidos vivos, SOLO donde la BASE gobierna. Provenance via origen de public._resolver_horario(...,false) [CIEGO: nunca ve vigencias; INV-1 anti-autorreferencia, resuelve la DEUDA DURA B1.1]. Turno pegado >=2h. FAIL-CLOSED: si el resolver devuelve ok<>true, conflicto motivo=resolver_horario_invalido. B1.2-core - TEST.';

-- =====================================================================
-- (4) Guard crear_vigencia_horario B1.1 (verbatim: CREATE + REVOKE + COMMENT)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.crear_vigencia_horario(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
AS $fn$
DECLARE
  v_hora_re    TEXT := '^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$';
  v_fecha_desde DATE;
  v_fecha_hasta DATE;
  v_abierta    BOOLEAN;
  v_ci_def_s   TEXT; v_ci_dom_s TEXT; v_co_def_s TEXT; v_co_dom_s TEXT;
  v_ci_def     TIME; v_ci_dom TIME; v_co_def TIME; v_co_dom TIME;
  v_motivo     TEXT; v_creado_por TEXT; v_source TEXT;
  v_solapadas  BIGINT[];
  v_conf       jsonb;
  v_id         BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(919010);

  -- V1 payload objeto
  IF payload IS NULL OR jsonb_typeof(payload) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'payload no es objeto jsonb');
  END IF;

  -- V2 claves prohibidas (las asigna la DB)
  IF payload ? 'id_vigencia' OR payload ? 'created_at' OR payload ? 'activo' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'id_vigencia/created_at/activo no son parametros; los asigna la DB');
  END IF;

  -- V3 requeridos presentes y NO en blanco (idiom NULLIF(btrim()))
  v_motivo     := NULLIF(btrim(payload->>'motivo'), '');
  v_creado_por := NULLIF(btrim(payload->>'creado_por'), '');
  v_ci_def_s   := NULLIF(btrim(payload->>'hora_checkin_default'), '');
  v_ci_dom_s   := NULLIF(btrim(payload->>'hora_checkin_domingo'), '');
  v_co_def_s   := NULLIF(btrim(payload->>'hora_checkout_default'), '');
  v_co_dom_s   := NULLIF(btrim(payload->>'hora_checkout_domingo'), '');
  IF NULLIF(btrim(payload->>'fecha_desde'), '') IS NULL
     OR v_ci_def_s IS NULL OR v_ci_dom_s IS NULL OR v_co_def_s IS NULL OR v_co_dom_s IS NULL
     OR v_motivo IS NULL OR v_creado_por IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'faltan requeridos o vienen en blanco: fecha_desde, 4 horas, motivo, creado_por');
  END IF;
  -- source_event opcional: blanco -> NULL (coaccion; la puerta nunca produce blanco)
  v_source := NULLIF(btrim(payload->>'source_event'), '');

  -- V4 consistencia abierta <-> fecha_hasta (abierta debe ser boolean si viene)
  IF payload ? 'abierta' AND jsonb_typeof(payload->'abierta') <> 'boolean' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'abierta debe ser booleano');
  END IF;
  v_abierta := COALESCE((payload->>'abierta')::boolean, false);
  IF v_abierta AND NULLIF(btrim(payload->>'fecha_hasta'), '') IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'abierta_inconsistente', 'detalle', 'abierta=true no admite fecha_hasta');
  END IF;
  IF NOT v_abierta AND NULLIF(btrim(payload->>'fecha_hasta'), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'abierta_inconsistente', 'detalle', 'abierta=false requiere fecha_hasta');
  END IF;

  -- V5 cast fechas
  BEGIN
    v_fecha_desde := (btrim(payload->>'fecha_desde'))::date;
    IF NOT v_abierta THEN v_fecha_hasta := (btrim(payload->>'fecha_hasta'))::date; END IF;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'cast de fecha fallido');
  END;

  -- V6 formato + cast horas
  IF v_ci_def_s !~ v_hora_re OR v_ci_dom_s !~ v_hora_re OR v_co_def_s !~ v_hora_re OR v_co_dom_s !~ v_hora_re THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'formato de hora invalido (HH:MM[:SS])');
  END IF;
  BEGIN
    v_ci_def := v_ci_def_s::time; v_ci_dom := v_ci_dom_s::time;
    v_co_def := v_co_def_s::time; v_co_dom := v_co_dom_s::time;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'cast de hora fallido');
  END;

  -- V7 fechas coherentes + no pasado (regla "desde ahora", solo en la puerta)
  IF NOT v_abierta AND v_fecha_hasta < v_fecha_desde THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas', 'detalle', 'fecha_hasta < fecha_desde');
  END IF;
  IF v_fecha_desde < CURRENT_DATE THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas', 'detalle', 'fecha_desde en el pasado; S4 es desde ahora o futuro, no reescritura historica');
  END IF;

  -- V8 ventana [07:00, 22:00]
  IF v_ci_def NOT BETWEEN TIME '07:00' AND TIME '22:00' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'hora_fuera_de_ventana', 'campo', 'hora_checkin_default', 'valor', v_ci_def, 'detalle', 'fuera de [07:00,22:00]');
  END IF;
  IF v_ci_dom NOT BETWEEN TIME '07:00' AND TIME '22:00' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'hora_fuera_de_ventana', 'campo', 'hora_checkin_domingo', 'valor', v_ci_dom, 'detalle', 'fuera de [07:00,22:00]');
  END IF;
  IF v_co_def NOT BETWEEN TIME '07:00' AND TIME '22:00' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'hora_fuera_de_ventana', 'campo', 'hora_checkout_default', 'valor', v_co_def, 'detalle', 'fuera de [07:00,22:00]');
  END IF;
  IF v_co_dom NOT BETWEEN TIME '07:00' AND TIME '22:00' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'hora_fuera_de_ventana', 'campo', 'hora_checkout_domingo', 'valor', v_co_dom, 'detalle', 'fuera de [07:00,22:00]');
  END IF;

  -- V9 G2 gap >= 2h (default y domingo)
  IF (v_ci_def - v_co_def) < INTERVAL '2 hours' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'gap_insuficiente', 'par', 'default', 'detalle', 'checkin - checkout < 2h');
  END IF;
  IF (v_ci_dom - v_co_dom) < INTERVAL '2 hours' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'gap_insuficiente', 'par', 'domingo', 'detalle', 'checkin - checkout < 2h');
  END IF;

  -- V10 no solapamiento (pre-check; exc_vigencias_no_overlap es la red)
  SELECT array_agg(id_vigencia ORDER BY id_vigencia) INTO v_solapadas
  FROM public.vigencias_horario_base
  WHERE activo
    AND (CASE WHEN abierta THEN daterange(fecha_desde, NULL) ELSE daterange(fecha_desde, fecha_hasta, '[]') END)
        && (CASE WHEN v_abierta THEN daterange(v_fecha_desde, NULL) ELSE daterange(v_fecha_desde, v_fecha_hasta, '[]') END);
  IF v_solapadas IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vigencia_solapada', 'detalle', 'solapa vigencia(s) activa(s)', 'ids_conflicto', to_jsonb(v_solapadas));
  END IF;

  -- V11 G1-targeted (helper; trg_vig_guard es la red diferida). Fail-closed:
  -- si el resolver no pudo determinar provenance, el helper marca el conflicto.
  v_conf := public.vigencias_conflictos_comprometidos(v_fecha_desde, v_fecha_hasta, v_abierta, v_ci_def, v_ci_dom, v_co_def, v_co_dom);
  IF jsonb_array_length(v_conf) > 0 THEN
    IF v_conf @> '[{"motivo":"resolver_horario_invalido"}]'::jsonb THEN
      RETURN jsonb_build_object('ok', false, 'error', 'resolver_horario_invalido',
        'detalle', 'resolver_horario devolvio ok<>true para un comprometido en rango; no se puede verificar provenance (fail-closed)', 'conflictos', v_conf);
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'base_pisa_comprometido', 'detalle', 'turno pegado <2h contra comprometido donde la base gobierna', 'conflictos', v_conf);
  END IF;

  -- Persistencia (ultimo paso; el trigger diferido revalida G1 en commit)
  INSERT INTO public.vigencias_horario_base
    (fecha_desde, fecha_hasta, abierta,
     hora_checkin_default, hora_checkin_domingo, hora_checkout_default, hora_checkout_domingo,
     motivo, creado_por, source_event)
  VALUES
    (v_fecha_desde, v_fecha_hasta, v_abierta,
     v_ci_def, v_ci_dom, v_co_def, v_co_dom,
     v_motivo, v_creado_por, v_source)
  RETURNING id_vigencia INTO v_id;

  RETURN jsonb_build_object(
    'ok', true,
    'id_vigencia', v_id,
    'fecha_desde', v_fecha_desde,
    'fecha_hasta', v_fecha_hasta,
    'abierta', v_abierta,
    'horas', jsonb_build_object(
      'checkin_default', v_ci_def, 'checkin_domingo', v_ci_dom,
      'checkout_default', v_co_def, 'checkout_domingo', v_co_dom),
    'creado_por', v_creado_por,
    'source_event', v_source,
    'created_at', now()
  );
END
$fn$;

-- ---- Hardening REVOKE (espejo Bloque 23) ----
REVOKE EXECUTE ON FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.crear_vigencia_horario(jsonb) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.crear_vigencia_horario(jsonb) IS
  'B1.1 guard vigencias. Puerta sancionada: alta de UNA vigencia de horario base global. Toma pg_advisory_xact_lock(919010); parsea/valida (NULLIF(btrim())); pre-chequea ventana/gap/solapamiento/G1 (G1 via helper vigencias_conflictos_comprometidos con provenance de resolver_horario, sin reimplementar precedencia; fail-closed si el resolver devuelve ok<>true); INSERT; {ok:true} persiste, {ok:false} no inserta (no consume secuencia). Errores parseables: payload_invalido, abierta_inconsistente, fechas_invalidas, hora_fuera_de_ventana, gap_insuficiente, vigencia_solapada, base_pisa_comprometido, resolver_horario_invalido. Regla no-pasado (fecha_desde>=CURRENT_DATE) SOLO aca (non-immutable, sin red DB). id_vigencia/created_at/activo NO son parametros. NO toca resolver_horario (fingerprint 58d75c1b intacto). El trigger diferido trg_vig_guard revalida G1 en commit. B1.1 - TEST-only inerte.';

-- =====================================================================
-- (5) Trigger trg_vig_guard B1.1 (verbatim: fn + constraint trigger + REVOKE + COMMENTs)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.trg_guard_vigencias()
RETURNS trigger
LANGUAGE plpgsql
AS $trg$
DECLARE
  v_conf jsonb;
  v_err  TEXT;
BEGIN
  -- Valida G1 SOLO si la fila resultante queda ACTIVA. Desactivacion
  -- (NEW.activo=false) => inerte para G1 (la fila deja de gobernar).
  IF NEW.activo IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  v_conf := public.vigencias_conflictos_comprometidos(
    NEW.fecha_desde, NEW.fecha_hasta, NEW.abierta,
    NEW.hora_checkin_default, NEW.hora_checkin_domingo,
    NEW.hora_checkout_default, NEW.hora_checkout_domingo);

  IF jsonb_array_length(v_conf) > 0 THEN
    -- fail-closed: distingue resolver invalido de turno pegado
    IF v_conf @> '[{"motivo":"resolver_horario_invalido"}]'::jsonb THEN
      v_err := 'resolver_horario_invalido';
    ELSE
      v_err := 'base_pisa_comprometido';
    END IF;
    RAISE EXCEPTION 'guard_vigencias: %', v_err
      USING ERRCODE = '45000',
            DETAIL = jsonb_build_object(
              'error', v_err,
              'tg_op', TG_OP,
              'id_vigencia', NEW.id_vigencia,
              'conflictos', v_conf)::text;
  END IF;

  RETURN NEW;
END
$trg$;

-- ---- Constraint trigger diferido ----
DROP TRIGGER IF EXISTS trg_vig_guard ON public.vigencias_horario_base;
CREATE CONSTRAINT TRIGGER trg_vig_guard
  AFTER INSERT OR UPDATE ON public.vigencias_horario_base
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_guard_vigencias();

-- ---- Hardening + comentarios ----
REVOKE EXECUTE ON FUNCTION public.trg_guard_vigencias() FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.trg_guard_vigencias() IS
  'B1.1 guard vigencias. Trigger-fn de la barrera diferida G1 sobre vigencias_horario_base. Valida G1 SOLO si NEW.activo (desactivacion inerte). Delega en vigencias_conflictos_comprometidos (helper compartido; provenance via resolver_horario, fail-closed si el resolver devuelve ok<>true). RAISE ERRCODE 45000 con DETAIL jsonb {error,tg_op,id_vigencia,conflictos}; error distingue base_pisa_comprometido de resolver_horario_invalido. G2/ventana/auditoria/overlap ya son declarativos (CHECK/EXCLUDE). Cubre INSERT/UPDATE; DELETE inerte en B1.1. DEUDA DURA B1.2: revisar autorreferencia, nuevo origen vigencia, y semantica de DELETE/desactivacion antes de cablear el resolver.';

COMMENT ON TRIGGER trg_vig_guard ON public.vigencias_horario_base IS
  'B1.1 guard vigencias. Valida el estado G1 FINAL en el commit, no un NEW aislado. DEFERRABLE INITIALLY DEFERRED. Forzable en tests con SET CONSTRAINTS trg_vig_guard IMMEDIATE. AFTER INSERT OR UPDATE (DELETE inerte en B1.1). B1.1 - TEST-only inerte.';

-- ---- POSTCHECKS intra-tx ----
DO $post$
DECLARE v_int text; v_help text; v_wrap_pre text; v_wrap_post text;
BEGIN
  v_int := md5(pg_get_functiondef('public._resolver_horario(bigint,date,boolean)'::regprocedure));
  IF v_int IS DISTINCT FROM '566ea522351a6b4e57b6dd770124814b' THEN
    RAISE EXCEPTION 'POST-RB: interno fp=% (esperado 566ea522..., B1.2-core). Rollback no byte-identico.', v_int;
  END IF;
  v_help := md5(pg_get_functiondef('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)'::regprocedure));
  IF v_help IS DISTINCT FROM '871fcde54be66b47c3e303e73b893c24' THEN
    RAISE EXCEPTION 'POST-RB: helper fp=% (esperado 871fcde5..., B1.2-core). Rollback no byte-identico.', v_help;
  END IF;
  SELECT v INTO v_wrap_pre FROM _rb_meta WHERE k='wrapper_pre';
  v_wrap_post := md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure));
  IF v_wrap_post IS DISTINCT FROM v_wrap_pre THEN
    RAISE EXCEPTION 'POST-RB: wrapper cambio (pre=%, post=%). No debe tocarse.', v_wrap_pre, v_wrap_post;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='vigencias_horario_base' AND column_name='hora_checkin_default') THEN
    RAISE EXCEPTION 'POST-RB: la cabecera no volvio a shape 4-col.';
  END IF;
  IF to_regclass('public.vigencias_horario_detalle') IS NOT NULL THEN
    RAISE EXCEPTION 'POST-RB: vigencias_horario_detalle sigue existiendo.';
  END IF;
  IF to_regprocedure('public.crear_vigencia_horario(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'POST-RB: falta guard B1.1.';
  END IF;
  RAISE NOTICE 'POSTCHECKS-RB OK: interno/helper == B1.2-core (byte-identico), wrapper intacto, cabecera 4-col, detalle ausente, guard B1.1 presente.';
END
$post$;

COMMIT;

-- ---- REPORTE (read-only; ULTIMO) ----
SELECT
  'B1.3-A ROLLBACK aplicado (TEST)'                                                          AS estado,
  md5(pg_get_functiondef('public._resolver_horario(bigint,date,boolean)'::regprocedure))     AS interno_fp,
  md5(pg_get_functiondef('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)'::regprocedure)) AS helper_fp,
  md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure))              AS wrapper_fp_intacto,
  (to_regclass('public.vigencias_horario_detalle') IS NULL)                                  AS detalle_eliminado;
