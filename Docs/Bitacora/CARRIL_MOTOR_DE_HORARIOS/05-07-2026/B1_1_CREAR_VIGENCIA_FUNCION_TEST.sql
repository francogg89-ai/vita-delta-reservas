-- =====================================================================
-- B1.1 - Motor de Horarios / Carril B1 (vigencias de horario base)
-- Artefacto 2/5: helper G1 compartido + crear_vigencia_horario (puerta sancionada)
-- -----------------------------------------------------------------------
-- ORDEN DE CARGA: DESPUES de 1/5 (DDL). El trigger (3/5) reutiliza el helper
--   de este artefacto => cargar 2/5 antes que 3/5.
-- ALCANCE: TEST-only e INERTE. NO toca resolver_horario, OPS, portal-api,
--   frontend, wrappers n8n, Vercel, canonico ni configuracion_general.
-- -----------------------------------------------------------------------
-- DEUDA DURA B1.2 (registrada): el helper vigencias_conflictos_comprometidos
--   usa resolver_horario SOLO para PROVENANCE (saber donde gobierna la base vs
--   un override) mientras el resolver TODAVIA NO lee vigencias. Antes de cablear
--   el resolver en B1.2 este helper (y el trigger que lo usa) DEBE revisarse:
--   (a) no volverse autorreferencial (resolver -> vigencias -> resolver);
--   (b) no malinterpretar un nuevo origen 'vigencia' que el resolver empezara a
--       emitir (hoy solo distingue base/patron_domingo/override_global/override_cabana).
-- =====================================================================

-- ---- GATE anti-ambiente + ecosistema esperado ----
DO $gate$
DECLARE v_amb TEXT; v_res TEXT; v_odr TEXT;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE B1.1-FN: ambiente=% (esperado test). Abortando.', v_amb;
  END IF;
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'GATE B1.1-FN: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  v_res := md5(pg_get_functiondef('resolver_horario(bigint,date)'::regprocedure));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'GATE B1.1-FN: fingerprint resolver=% (esperado 58d75c1b6b812ee2d2c9751ddcb0cd4d, post-R0). Abortando.', v_res;
  END IF;
  v_odr := md5(pg_get_functiondef('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE B1.1-FN: fingerprint ODR=% (esperado 37009a32154f93b80520500c0f15b46b). Abortando.', v_odr;
  END IF;
  IF to_regclass('public.vigencias_horario_base') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.1-FN: falta vigencias_horario_base. Corre el artefacto 1/5 primero. Abortando.';
  END IF;
END
$gate$;

-- =====================================================================
-- HELPER G1 (compartido por crear_vigencia_horario y trg_guard_vigencias).
-- Evalua una vigencia PROSPECTIVA (parametros, NO lee la tabla) contra los
-- comprometidos vivos, SOLO donde la BASE gobierna (provenance via resolver).
-- Devuelve array jsonb de conflictos ([] si no hay). Sin reimplementar la
-- precedencia del resolver: solo lee origen_checkin/origen_checkout.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.vigencias_conflictos_comprometidos(
  p_fecha_desde DATE, p_fecha_hasta DATE, p_abierta BOOLEAN,
  p_ci_def TIME, p_ci_dom TIME, p_co_def TIME, p_co_dom TIME
) RETURNS jsonb
LANGUAGE sql
STABLE
AS $help$
  WITH comprometidos AS (
    -- Reservas vivas: un lado por fila (checkout y checkin)
    SELECT 'reserva'::text AS tipo, id_reserva AS id, id_cabana, fecha_checkout AS fecha, 'checkout'::text AS lado, hora_checkout AS frozen
      FROM reservas WHERE estado IN ('confirmada','activa','completada')
    UNION ALL
    SELECT 'reserva', id_reserva, id_cabana, fecha_checkin, 'checkin', hora_checkin
      FROM reservas WHERE estado IN ('confirmada','activa','completada')
    UNION ALL
    -- Pre-reservas vigentes (misma definicion que S0)
    SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_out, 'checkout', hora_checkout
      FROM pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'
    UNION ALL
    SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_in, 'checkin', hora_checkin
      FROM pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'
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
    CROSS JOIN LATERAL (SELECT resolver_horario(c.id_cabana, c.fecha) AS res) r
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

COMMENT ON FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time) IS
  'B1.1 helper G1 compartido (crear_vigencia_horario + trg_vig_guard). Evalua una vigencia PROSPECTIVA contra comprometidos vivos (reservas confirmada/activa/completada; pre_reservas pendiente_pago vigente | pago_en_revision), SOLO donde la BASE gobierna (provenance via origen_checkin/origen_checkout de resolver_horario, sin reimplementar precedencia). Turno pegado >=2h contra la hora congelada. FAIL-CLOSED: si resolver_horario devuelve ok<>true para alguna fecha/cabana en rango, emite conflicto motivo=resolver_horario_invalido (nunca fail-open). Devuelve array jsonb de conflictos con motivo por entrada. DEUDA DURA B1.2: revisar por autorreferencia y nuevo origen vigencia antes de cablear el resolver.';

-- =====================================================================
-- PUERTA SANCIONADA crear_vigencia_horario(jsonb)
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
-- VERIFICACION grants robustos (has_function_privilege; proacl NULL NO
-- implica 0 permisos). EXECUTE debe ser FALSE para los 4 roles.
-- =====================================================================
WITH roles(r) AS (VALUES ('anon'),('authenticated'),('service_role'),('public')),
priv AS (
  SELECT r,
    has_function_privilege(r, 'public.crear_vigencia_horario(jsonb)', 'EXECUTE') AS ex_fn,
    has_function_privilege(r, 'public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)', 'EXECUTE') AS ex_help
  FROM roles
)
SELECT
  (SELECT count(*) FROM priv WHERE ex_fn)   AS grants_funcion_no_cero,
  (SELECT count(*) FROM priv WHERE ex_help) AS grants_helper_no_cero,
  (to_regprocedure('public.crear_vigencia_horario(jsonb)') IS NOT NULL) AS funcion_existe,
  (to_regprocedure('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)') IS NOT NULL) AS helper_existe,
  CASE WHEN (SELECT count(*) FROM priv WHERE ex_fn) = 0
        AND (SELECT count(*) FROM priv WHERE ex_help) = 0
        AND to_regprocedure('public.crear_vigencia_horario(jsonb)') IS NOT NULL
        AND to_regprocedure('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)') IS NOT NULL
       THEN 'PASS' ELSE 'FAIL' END AS veredicto_fn;
