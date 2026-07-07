-- =====================================================================
-- B1.2-core - Motor de Horarios / Carril B1 (integracion de vigencias)
-- Artefacto 1/4: MIGRACION
-- ---------------------------------------------------------------------
-- Cablea vigencias_horario_base en el resolver:
--   (1) public._resolver_horario(bigint,date,boolean) [INTERNO, owner-only]:
--       refactor de R0. Unico cambio de cuerpo vs R0 es el Paso A (capa base):
--       lee la vigencia que cubre la fecha (si el flag lo pide) en vez de config.
--       flag true  = capa base es vigencia-si-cubre-si-no-config (produccion);
--       flag false = siempre config (ciego, byte-identico a R0; para el helper G1).
--   (2) public.resolver_horario(bigint,date) [WRAPPER sql, owner-only]:
--       DROP+CREATE; pass-through a public._resolver_horario(...,true). Firma
--       intacta => fingerprint del ODR intacto. DROP no bloqueado; vista preservada.
--   (3) public.vigencias_conflictos_comprometidos(...) [HELPER]: DROP+CREATE;
--       su LATERAL llama public._resolver_horario(...,false) (ciego). INV-1:
--       la provenance G1 nunca ve vigencias (resuelve la DEUDA DURA B1.2).
-- PRECEDENCIA: config(fallback) -> vigencia -> override_global -> override_cabana,
--   por tipo (checkin/checkout). Con 0 vigencias activas == R0 (solo cambia el fp).
-- ---------------------------------------------------------------------
-- ALCANCE: TEST-only. NO OPS, portal-api, frontend, wrappers n8n, Vercel,
--   canonico, lifecycle ni cascade. REPORTA el fingerprint nuevo del wrapper
--   pero NO actualiza gates/smokes/docs B1.1/S0/S1/S2/S3 (eso es B1.2-cascade).
-- Transaccion unica. Doble lock (10,0)->(919010). Sin CASCADE. REVOKE inmediato.
-- Ejecutar en Supabase SQL Editor SIN texto seleccionado (script entero).
-- =====================================================================

BEGIN;

-- ---- Doble lock (orden estricto, nunca al reves) ----
SELECT pg_advisory_xact_lock(10, 0);
SELECT pg_advisory_xact_lock(919010);

-- ---- GATE 1: estado esperado ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  v_res text;
  v_odr text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE B1.2-core: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'GATE B1.2-core: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  v_res := md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'GATE B1.2-core: resolver fp=% (esperado 58d75c1b6b812ee2d2c9751ddcb0cd4d, R0/B1.1). Abortando.', v_res;
  END IF;
  v_odr := md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE B1.2-core: ODR fp=% (esperado 37009a32154f93b80520500c0f15b46b). Abortando.', v_odr;
  END IF;
  IF to_regclass('public.vigencias_horario_base') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.2-core: falta public.vigencias_horario_base (B1.1). Abortando.';
  END IF;
  IF to_regprocedure('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.2-core: falta helper (B1.1). Abortando.';
  END IF;
  IF to_regprocedure('public.crear_vigencia_horario(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.2-core: falta puerta crear_vigencia_horario (B1.1). Abortando.';
  END IF;
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'GATE B1.2-core: public._resolver_horario ya existe (estado inesperado; correr rollback). Abortando.';
  END IF;
  RAISE NOTICE 'GATE 1 OK: ambiente=test, schema=public, resolver=R0/B1.1, ODR intacto, B1.1 presente, interno ausente.';
END
$gate$;

-- ---- GATE 2: precondicion G1 (0 conflictos comprometidos con vigencias activas) ----
DO $g1$
DECLARE v_row RECORD; v_conf jsonb; v_tot int := 0;
BEGIN
  FOR v_row IN
    SELECT id_vigencia, fecha_desde, fecha_hasta, abierta,
           hora_checkin_default, hora_checkin_domingo, hora_checkout_default, hora_checkout_domingo
    FROM public.vigencias_horario_base WHERE activo
  LOOP
    v_conf := public.vigencias_conflictos_comprometidos(
      v_row.fecha_desde, v_row.fecha_hasta, v_row.abierta,
      v_row.hora_checkin_default, v_row.hora_checkin_domingo,
      v_row.hora_checkout_default, v_row.hora_checkout_domingo);
    IF jsonb_array_length(v_conf) > 0 THEN
      v_tot := v_tot + jsonb_array_length(v_conf);
      RAISE WARNING 'GATE 2 G1: vigencia id=% con % conflicto(s): %', v_row.id_vigencia, jsonb_array_length(v_conf), v_conf;
    END IF;
  END LOOP;
  IF v_tot > 0 THEN
    RAISE EXCEPTION 'GATE 2 G1: % conflicto(s) base-pisa-comprometido con vigencias activas. Abortando (fail-closed).', v_tot;
  END IF;
  RAISE NOTICE 'GATE 2 OK: G1 sin conflictos.';
END
$g1$;

-- =====================================================================
-- (1) INTERNO public._resolver_horario  (refactor R0; Paso A = vigencia|config)
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
-- (2) WRAPPER public.resolver_horario  (DROP+CREATE, sql pass-through true)
-- =====================================================================
DROP FUNCTION public.resolver_horario(bigint,date);
CREATE FUNCTION public.resolver_horario(p_id_cabana BIGINT, p_fecha DATE)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $wrap$
  SELECT public._resolver_horario(p_id_cabana, p_fecha, true)
$wrap$;

REVOKE EXECUTE ON FUNCTION public.resolver_horario(bigint,date) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.resolver_horario(bigint,date) IS
  'B1.2-core WRAPPER publico owner-only (vigencia-aware). Pass-through: delega en public._resolver_horario(id_cabana,fecha,true). Reemplaza a R0 (config/override). Con 0 vigencias activas el resultado es identico a R0 (solo cambia el fingerprint de esta funcion). Firma y contrato de retorno intactos => ODR y vista_disponibilidad no se tocan. B1.2-core - TEST. La actualizacion de gates/smokes/docs por el fingerprint nuevo es B1.2-cascade.';

-- =====================================================================
-- (3) HELPER public.vigencias_conflictos_comprometidos  (DROP+CREATE, LATERAL->interno ciego)
-- =====================================================================
DROP FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time);
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

-- ---- POSTCHECKS intra-tx ----
DO $post$
DECLARE r text; v_res_fp text; v_odr_fp text; v_int_fp text; v_vista int;
BEGIN
  IF to_regprocedure('public._resolver_horario(bigint,date,boolean)') IS NULL THEN
    RAISE EXCEPTION 'POST: public._resolver_horario ausente.';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r, 'public._resolver_horario(bigint,date,boolean)', 'EXECUTE') THEN
      RAISE EXCEPTION 'POST: interno EXECUTE concedido a % (esperado owner-only).', r;
    END IF;
    IF has_function_privilege(r, 'public.resolver_horario(bigint,date)', 'EXECUTE') THEN
      RAISE EXCEPTION 'POST: wrapper EXECUTE concedido a % (esperado owner-only).', r;
    END IF;
    IF has_function_privilege(r, 'public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)', 'EXECUTE') THEN
      RAISE EXCEPTION 'POST: helper EXECUTE concedido a % (esperado owner-only).', r;
    END IF;
  END LOOP;
  v_res_fp := md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure));
  IF v_res_fp = '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'POST: wrapper fingerprint sigue en R0 (no se aplico).';
  END IF;
  v_odr_fp := md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  IF v_odr_fp IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'POST: ODR fingerprint cambio a % (esperado 37009a32... intacto).', v_odr_fp;
  END IF;
  SELECT count(*) INTO v_vista FROM public.vista_disponibilidad;
  IF v_vista = 0 THEN
    RAISE EXCEPTION 'POST: vista_disponibilidad devolvio 0 filas (cadena rota).';
  END IF;
  v_int_fp := md5(pg_get_functiondef('public._resolver_horario(bigint,date,boolean)'::regprocedure));
  RAISE NOTICE 'POSTCHECKS OK: interno/wrapper/helper owner-only; wrapper_fp=% (!=R0); interno_fp=%; ODR intacto; vista=% filas.', v_res_fp, v_int_fp, v_vista;
END
$post$;

COMMIT;

-- ---- REPORTE (autocommit, read-only; ULTIMO => se muestra) ----
SELECT
  'B1.2-core aplicado (TEST)'                                                              AS estado,
  md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure))           AS wrapper_fp_nuevo,
  md5(pg_get_functiondef('public._resolver_horario(bigint,date,boolean)'::regprocedure))   AS interno_fp,
  md5(pg_get_functiondef('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)'::regprocedure)) AS helper_fp_nuevo,
  md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure)) AS odr_fp_intacto,
  (SELECT count(*) FROM public.vista_disponibilidad)                                       AS vista_filas;
