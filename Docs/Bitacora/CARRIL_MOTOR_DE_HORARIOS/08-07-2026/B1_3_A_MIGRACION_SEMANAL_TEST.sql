-- =====================================================================
-- B1.3-A - Motor de Horarios / Vigencias Semanales
-- Artefacto A (aislado): MIGRACION de la capa de vigencia default/domingo
--   -> vigencias semanales completas (7 dias x 2 bordes).
-- ---------------------------------------------------------------------
-- SUPERSEDE (solo la capa de vigencia; conserva TODO lo demas de B1.2-core):
--   (1) tabla vigencias_horario_base (4 col hora) -> cabecera (sin horas)
--       + vigencias_horario_detalle (7 filas por vigencia, 1 por dia_semana).
--   (2) public._resolver_horario(bigint,date,boolean) [INTERNO]: DROP+CREATE.
--       Unico cambio de cuerpo vs B1.2-core: Paso A (capa vigencia). Dos lookups:
--       cabecera que cubre la fecha; luego detalle por EXTRACT(DOW). Fail-closed
--       'vigencia_incompleta' si hay cabecera vigente pero falta el detalle del
--       dia. Sin cabecera => config (fallback). Pasos B/C (override) y ventana
--       IDENTICOS. Origen de vigencia UNIFORME 'vigencia' (se retira vigencia_domingo).
--   (3) public.vigencias_conflictos_comprometidos(...) [HELPER]: firma nueva
--       (date,date,boolean,jsonb). p_dias = {"0":{hora_checkin,hora_checkout},...,"6":{}}.
--       LATERAL sigue llamando public._resolver_horario(...,false) (CIEGO). INV-1 vivo.
--   (4) public.crear_vigencia_horario(jsonb) [GUARD]: DROP+CREATE. Payload semanal
--       (cabecera + dias, 7 claves 0-6 obligatorias). INSERT cabecera + 7 detalle, atomico.
--   (5) public.trg_guard_vigencias() + trg_vig_guard: barrera diferida G1 + completitud
--       exacta de 7 filas. Dispara sobre detalle (horas) y cabecera (rango/activo).
-- ALCANCE DE COMPLETITUD (A) — explicito para el cierre:
--   * el guard crear_vigencia_horario SIEMPRE inserta las 7 filas (0-6) en la misma tx;
--   * la barrera diferida (trg_vig_guard sobre cabecera + trg_vig_guard_detalle sobre
--     detalle) REVALIDA completitud + G1 en INSERT/UPDATE;
--   * NO cubre DELETE de detalle: es INERTE por diseno;
--   * las tablas son owner-only (sin grants a anon/authenticated/service_role), asi que
--     un borrado destructivo solo es posible por mutacion manual del owner;
--   * si esa mutacion dejara una vigencia ACTIVA con <7 filas, el resolver responde
--     FAIL-CLOSED con error=vigencia_incompleta para el dia faltante (nunca cae a config);
--   * DELETE, desactivacion y lifecycle de vigencias quedan FUERA de A.
--   La barrera NO garantiza completitud ante cualquier mutacion: no cubre DELETE.
-- NO TOCA:
--   * public.resolver_horario(bigint,date) [WRAPPER]: intacto => fingerprint SOBREVIVE.
--   * ODR, vista_disponibilidad, S0/S1/S2/S3, crear_prereserva/confirmar_reserva.
--   * validador de gap congelado, reserva pactada, guard puntual: son artefactos aparte.
-- ---------------------------------------------------------------------
-- ALCANCE: TEST-only. Transaccion unica. Doble lock (10,0)->(919010). Sin CASCADE.
--   Datos de vigencia en TEST: DESCARTABLES (shape 4-col incompatible; se pierden).
--   NO acuna D-/L- (cierre formal aparte). NO realinea gates/smokes/docs B1.1/S0-S3
--   ni la deuda cascade 58d75c1b->1bd96c89 (eso es el cierre de B1.3).
-- Ejecutar en Supabase SQL Editor SIN texto seleccionado (script entero).
-- =====================================================================

BEGIN;

-- ---- Doble lock (orden estricto, nunca al reves) ----
SELECT pg_advisory_xact_lock(10, 0);
SELECT pg_advisory_xact_lock(919010);

-- ---- GATE 1: estado esperado post-B1.2-core ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
  v_int text; v_wrap text; v_help text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE B1.3-A: ambiente=% (esperado test). Abortando.', COALESCE(v_amb,'<null>');
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'GATE B1.3-A: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  -- Partida B1.2-core (fingerprints Supabase/PG17; en harness PG16 se ajustan).
  v_int := md5(pg_get_functiondef('public._resolver_horario(bigint,date,boolean)'::regprocedure));
  IF v_int IS DISTINCT FROM '566ea522351a6b4e57b6dd770124814b' THEN
    RAISE EXCEPTION 'GATE B1.3-A: interno fp=% (esperado 566ea522..., B1.2-core). Abortando.', v_int;
  END IF;
  v_wrap := md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure));
  IF v_wrap IS DISTINCT FROM '1bd96c89e587b15582fd7b2e29ae7e18' THEN
    RAISE EXCEPTION 'GATE B1.3-A: wrapper fp=% (esperado 1bd96c89..., B1.2-core). Abortando.', v_wrap;
  END IF;
  v_help := md5(pg_get_functiondef('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)'::regprocedure));
  IF v_help IS DISTINCT FROM '871fcde54be66b47c3e303e73b893c24' THEN
    RAISE EXCEPTION 'GATE B1.3-A: helper fp=% (esperado 871fcde5..., B1.2-core). Abortando.', v_help;
  END IF;
  -- Cabecera 4-col presente (estado pre-A); detalle ausente.
  IF to_regclass('public.vigencias_horario_base') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.3-A: falta vigencias_horario_base. Abortando.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='vigencias_horario_base' AND column_name='hora_checkin_default') THEN
    RAISE EXCEPTION 'GATE B1.3-A: vigencias_horario_base no tiene shape 4-col (estado inesperado; correr rollback). Abortando.';
  END IF;
  IF to_regclass('public.vigencias_horario_detalle') IS NOT NULL THEN
    RAISE EXCEPTION 'GATE B1.3-A: vigencias_horario_detalle ya existe (estado inesperado; correr rollback). Abortando.';
  END IF;
  IF to_regprocedure('public.crear_vigencia_horario(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.3-A: falta crear_vigencia_horario (B1.1). Abortando.';
  END IF;
  IF to_regprocedure('public.trg_guard_vigencias()') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.3-A: falta trg_guard_vigencias (B1.1). Abortando.';
  END IF;
  RAISE NOTICE 'GATE 1 OK: ambiente=test, schema=public, B1.2-core (interno/wrapper/helper), cabecera 4-col presente, detalle ausente.';
END
$gate$;

-- ---- Captura pre (para postchecks de invariancia; sin hardcodear) ----
CREATE TEMP TABLE _mig_meta(k text, v text) ON COMMIT DROP;
INSERT INTO _mig_meta VALUES
  ('wrapper_pre', md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure))),
  ('odr_pre',     md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure))),
  ('vista_pre',   (SELECT count(*)::text FROM public.vista_disponibilidad));

-- =====================================================================
-- (1) DDL: cabecera (sin horas) + detalle (7 dias)
-- =====================================================================
DROP TABLE IF EXISTS public.vigencias_horario_detalle;
DROP TABLE public.vigencias_horario_base;

CREATE TABLE public.vigencias_horario_base (
  id_vigencia   BIGSERIAL PRIMARY KEY,
  fecha_desde   DATE NOT NULL,
  fecha_hasta   DATE,
  abierta       BOOLEAN NOT NULL DEFAULT FALSE,
  motivo        TEXT NOT NULL,
  creado_por    TEXT NOT NULL,
  activo        BOOLEAN NOT NULL DEFAULT TRUE,
  source_event  TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_vigencias_abierta CHECK (
    (abierta AND fecha_hasta IS NULL)
    OR (NOT abierta AND fecha_hasta IS NOT NULL AND fecha_hasta >= fecha_desde)),
  CONSTRAINT chk_vigencias_motivo       CHECK (btrim(motivo) <> ''),
  CONSTRAINT chk_vigencias_creado_por   CHECK (btrim(creado_por) <> ''),
  CONSTRAINT chk_vigencias_source_event CHECK (source_event IS NULL OR btrim(source_event) <> ''),
  CONSTRAINT exc_vigencias_no_overlap EXCLUDE USING gist (
    (CASE WHEN abierta THEN daterange(fecha_desde, NULL)
          ELSE daterange(fecha_desde, fecha_hasta, '[]') END) WITH &&
  ) WHERE (activo)
);

CREATE TABLE public.vigencias_horario_detalle (
  id_vigencia   BIGINT   NOT NULL REFERENCES public.vigencias_horario_base(id_vigencia) ON DELETE CASCADE,
  dia_semana    SMALLINT NOT NULL,
  hora_checkin  TIME     NOT NULL,
  hora_checkout TIME     NOT NULL,
  CONSTRAINT pk_vig_detalle PRIMARY KEY (id_vigencia, dia_semana),
  CONSTRAINT chk_vig_det_dow     CHECK (dia_semana BETWEEN 0 AND 6),
  CONSTRAINT chk_vig_det_gap     CHECK ((hora_checkin - hora_checkout) >= INTERVAL '2 hours'),
  CONSTRAINT chk_vig_det_ventana CHECK (
    hora_checkin  BETWEEN TIME '07:00' AND TIME '22:00'
    AND hora_checkout BETWEEN TIME '07:00' AND TIME '22:00')
);

REVOKE ALL ON TABLE    public.vigencias_horario_base                 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE public.vigencias_horario_base_id_vigencia_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE    public.vigencias_horario_detalle              FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE public.vigencias_horario_base IS
  'B1.3 motor horarios. Cabecera de vigencia semanal (evoluciona B1.1: sin las 4 horas default/domingo). Rango cerrado inclusivo o abierta (sin fin). No-solapamiento entre activas por exc_vigencias_no_overlap (GiST rango puro). Las 7 horas x dia viven en vigencias_horario_detalle. Completitud de 7 filas (0-6): el guard la crea siempre y la barrera diferida trg_vig_guard la REVALIDA en INSERT/UPDATE (NO en DELETE de detalle, inerte por diseno; ver ALCANCE DE COMPLETITUD en la cabecera del artefacto). Tabla owner-only. B1.3-A - TEST.';
COMMENT ON TABLE public.vigencias_horario_detalle IS
  'B1.3 motor horarios. Detalle por dia de semana (EXTRACT(DOW): 0=domingo..6=sabado). El guard crear_vigencia_horario inserta exactamente 7 filas por vigencia; la barrera diferida revalida completitud en INSERT/UPDATE, NO en DELETE (inerte por diseno). Tabla owner-only: un borrado destructivo manual que deje una vigencia activa con <7 filas hace que el resolver falle cerrado con vigencia_incompleta (no cae a config). gap>=2h y ventana [07:00,22:00] por CHECK. FK ON DELETE CASCADE. B1.3-A - TEST.';

-- =====================================================================
-- (2) INTERNO public._resolver_horario  (Paso A semanal + vigencia_incompleta)
-- =====================================================================
DROP FUNCTION public._resolver_horario(bigint,date,boolean);
CREATE FUNCTION public._resolver_horario(p_id_cabana BIGINT, p_fecha DATE, p_incluir_vigencias BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY INVOKER AS $A_fn$
DECLARE
  v_config JSONB; v_ventana_min TIME; v_ventana_max TIME;
  v_es_domingo BOOLEAN := (EXTRACT(DOW FROM p_fecha) = 0);
  v_tipo TEXT; v_base TIME; v_origen TEXT;
  v_ovr_id BIGINT; v_ovr_valor TEXT; v_ovr_cabana BOOLEAN;
  v_hora TIME; v_res JSONB := '{}'::JSONB;
  v_vig_id BIGINT; v_vig_ci TIME; v_vig_co TIME;
  v_vig_found BOOLEAN := FALSE;
BEGIN
  SELECT jsonb_object_agg(clave, valor) INTO v_config FROM public.configuracion_general
  WHERE clave IN ('hora_checkin_default','hora_checkin_domingo','hora_checkout_default','hora_checkout_domingo','hora_checkin_max_cliente','hora_checkout_min_cliente');
  v_ventana_min := COALESCE((v_config->>'hora_checkout_min_cliente')::TIME, TIME '07:00');
  v_ventana_max := COALESCE((v_config->>'hora_checkin_max_cliente')::TIME, TIME '22:00');
  -- Paso A (capa vigencia, solo si flag). Dos lookups: cabecera, luego detalle por DOW.
  IF p_incluir_vigencias THEN
    SELECT id_vigencia INTO v_vig_id
    FROM public.vigencias_horario_base
    WHERE activo AND (CASE WHEN abierta THEN daterange(fecha_desde,NULL) ELSE daterange(fecha_desde,fecha_hasta,'[]') END) @> p_fecha
    LIMIT 1;
    IF FOUND THEN
      SELECT hora_checkin, hora_checkout INTO v_vig_ci, v_vig_co
      FROM public.vigencias_horario_detalle
      WHERE id_vigencia = v_vig_id AND dia_semana = EXTRACT(DOW FROM p_fecha)::int
      LIMIT 1;
      IF FOUND THEN
        v_vig_found := TRUE;
      ELSE
        -- Cabecera vigente pero falta el detalle del dia => FAIL-CLOSED (no cae a config).
        RETURN jsonb_build_object('ok', false, 'error', 'vigencia_incompleta',
          'id_vigencia', v_vig_id, 'dia_semana', EXTRACT(DOW FROM p_fecha)::int, 'fecha', p_fecha);
      END IF;
    END IF;
  END IF;
  FOREACH v_tipo IN ARRAY ARRAY['hora_checkin','hora_checkout'] LOOP
    -- Paso A: base = vigencia (uniforme) si cubre, ELSE config (base/patron_domingo).
    IF v_vig_found THEN
      v_base := CASE v_tipo WHEN 'hora_checkin' THEN v_vig_ci ELSE v_vig_co END; v_origen := 'vigencia';
    ELSE
      IF v_es_domingo THEN
        v_base := COALESCE((v_config->>(v_tipo||'_domingo'))::TIME, CASE v_tipo WHEN 'hora_checkin' THEN TIME '18:00' ELSE TIME '16:00' END); v_origen := 'patron_domingo';
      ELSE
        v_base := COALESCE((v_config->>(v_tipo||'_default'))::TIME, CASE v_tipo WHEN 'hora_checkin' THEN TIME '13:00' ELSE TIME '10:00' END); v_origen := 'base';
      END IF;
    END IF;
    -- Paso B: override ganador (IDENTICO B1.2-core/R0)
    SELECT id_override, valor, (id_cabana IS NOT NULL) INTO v_ovr_id, v_ovr_valor, v_ovr_cabana
    FROM public.overrides_operativos WHERE activo AND tipo_override = v_tipo
      AND fecha_desde <= p_fecha AND p_fecha <= COALESCE(fecha_hasta, fecha_desde)
      AND (id_cabana = p_id_cabana OR id_cabana IS NULL)
    ORDER BY (id_cabana IS NOT NULL) DESC, created_at DESC, id_override DESC LIMIT 1;
    -- Paso C: override o base (IDENTICO B1.2-core/R0)
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
END; $A_fn$;

REVOKE EXECUTE ON FUNCTION public._resolver_horario(bigint,date,boolean) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public._resolver_horario(bigint,date,boolean) IS
  'B1.3-A INTERNO owner-only. Precedencia config(fallback)->vigencia(semanal)->override_global->override_cabana, por tipo. Paso A (capa vigencia): dos lookups (cabecera que cubre la fecha; detalle por EXTRACT(DOW)). Fail-closed error=vigencia_incompleta si hay cabecera vigente pero falta el detalle del dia (NO cae a config). Sin cabecera => config. Origen de vigencia UNIFORME vigencia (se retira vigencia_domingo; config sigue emitiendo base/patron_domingo). Flag p_incluir_vigencias: true=capa vigencia|config (wrapper); false=siempre config (ciego, para provenance G1; INV-1). Override (B/C) y ventana [07:00,22:00] IDENTICOS a B1.2-core. B1.3-A - TEST.';

-- =====================================================================
-- (WRAPPER public.resolver_horario NO SE TOCA: su fingerprint SOBREVIVE.
--  Su cuerpo (pass-through a _resolver_horario(...,true)) es independiente
--  de la forma de la vigencia; el interno recreado mantiene la firma.)
-- =====================================================================

-- =====================================================================
-- (3) HELPER public.vigencias_conflictos_comprometidos  (firma nueva jsonb)
-- =====================================================================
DROP FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time);
CREATE FUNCTION public.vigencias_conflictos_comprometidos(
  p_fecha_desde DATE, p_fecha_hasta DATE, p_abierta BOOLEAN, p_dias jsonb
) RETURNS jsonb LANGUAGE sql STABLE AS $A_help$
  WITH comprometidos AS (
    SELECT 'reserva'::text AS tipo, id_reserva AS id, id_cabana, fecha_checkout AS fecha, 'checkout'::text AS lado, hora_checkout AS frozen
      FROM public.reservas WHERE estado IN ('confirmada','activa','completada')
    UNION ALL
    SELECT 'reserva', id_reserva, id_cabana, fecha_checkin, 'checkin', hora_checkin
      FROM public.reservas WHERE estado IN ('confirmada','activa','completada')
    UNION ALL
    SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_out, 'checkout', hora_checkout
      FROM public.pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'
    UNION ALL
    SELECT 'pre_reserva', id_pre_reserva, id_cabana, fecha_in, 'checkin', hora_checkin
      FROM public.pre_reservas WHERE (estado = 'pendiente_pago' AND expira_en > NOW()) OR estado = 'pago_en_revision'
  ),
  en_rango AS (SELECT * FROM comprometidos WHERE fecha >= p_fecha_desde AND (p_abierta OR fecha <= p_fecha_hasta)),
  eval AS (
    SELECT c.tipo, c.id, c.id_cabana, c.fecha, c.lado, c.frozen,
      COALESCE((r.res->>'ok')::boolean, false) AS resolver_ok,
      (r.res->>'origen_checkin')  AS ori_ci, (r.res->>'origen_checkout') AS ori_co,
      (p_dias -> (EXTRACT(DOW FROM c.fecha)::int::text) ->> 'hora_checkin')::time  AS vig_ci,
      (p_dias -> (EXTRACT(DOW FROM c.fecha)::int::text) ->> 'hora_checkout')::time AS vig_co
    FROM en_rango c CROSS JOIN LATERAL (SELECT public._resolver_horario(c.id_cabana, c.fecha, false) AS res) r
  ),
  viol AS (
    SELECT tipo, id, id_cabana, fecha, lado,
      CASE WHEN NOT resolver_ok THEN 'resolver_horario_invalido' ELSE 'turno_pegado' END AS motivo
    FROM eval WHERE NOT resolver_ok
      OR (resolver_ok AND lado = 'checkout' AND ori_ci IN ('base','patron_domingo') AND (vig_ci - frozen) < INTERVAL '2 hours')
      OR (resolver_ok AND lado = 'checkin'  AND ori_co IN ('base','patron_domingo') AND (frozen - vig_co) < INTERVAL '2 hours')
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('fecha', fecha, 'id_cabana', id_cabana, 'tipo', tipo, 'id', id, 'lado', lado, 'motivo', motivo) ORDER BY fecha, id_cabana, id), '[]'::jsonb)
  FROM viol;
$A_help$;

REVOKE EXECUTE ON FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb) IS
  'B1.3-A helper G1 compartido (crear_vigencia_horario + trg_vig_guard). Evalua una vigencia semanal PROSPECTIVA (p_dias={"0":{hora_checkin,hora_checkout},..,"6":{}}) contra comprometidos vivos, SOLO donde la BASE gobierna. Provenance via origen de public._resolver_horario(...,false) [CIEGO: nunca ve vigencias; INV-1]. vig_ci/vig_co por EXTRACT(DOW) de la fecha del comprometido. Turno pegado >=2h. FAIL-CLOSED: resolver ok<>true => motivo=resolver_horario_invalido. B1.3-A - TEST.';

-- =====================================================================
-- (4) GUARD public.crear_vigencia_horario  (payload semanal)
-- =====================================================================
DROP FUNCTION public.crear_vigencia_horario(jsonb);
CREATE FUNCTION public.crear_vigencia_horario(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER AS $A_guard$
DECLARE
  v_hora_re TEXT := '^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$';
  v_fecha_desde DATE; v_fecha_hasta DATE; v_abierta BOOLEAN;
  v_motivo TEXT; v_creado_por TEXT; v_source TEXT;
  v_dias jsonb; v_dow INT; v_ci_s TEXT; v_co_s TEXT; v_ci TIME; v_co TIME;
  v_solapadas BIGINT[]; v_conf jsonb; v_id BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(919010);

  -- V1 payload objeto
  IF payload IS NULL OR jsonb_typeof(payload) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'payload no es objeto jsonb'); END IF;
  -- V2 claves prohibidas
  IF payload ? 'id_vigencia' OR payload ? 'created_at' OR payload ? 'activo' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'id_vigencia/created_at/activo no son parametros; los asigna la DB'); END IF;
  -- V3 requeridos
  v_motivo := NULLIF(btrim(payload->>'motivo'), ''); v_creado_por := NULLIF(btrim(payload->>'creado_por'), '');
  IF NULLIF(btrim(payload->>'fecha_desde'), '') IS NULL OR v_motivo IS NULL OR v_creado_por IS NULL
     OR NOT (payload ? 'dias') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'faltan requeridos: fecha_desde, motivo, creado_por, dias'); END IF;
  v_source := NULLIF(btrim(payload->>'source_event'), '');
  -- V4 abierta boolean si viene
  IF payload ? 'abierta' AND jsonb_typeof(payload->'abierta') <> 'boolean' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'abierta debe ser booleano'); END IF;
  v_abierta := COALESCE((payload->>'abierta')::boolean, false);
  IF v_abierta AND NULLIF(btrim(payload->>'fecha_hasta'), '') IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'abierta_inconsistente', 'detalle', 'abierta=true no admite fecha_hasta'); END IF;
  IF NOT v_abierta AND NULLIF(btrim(payload->>'fecha_hasta'), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'abierta_inconsistente', 'detalle', 'abierta=false requiere fecha_hasta'); END IF;
  -- V5 cast fechas
  BEGIN
    v_fecha_desde := (btrim(payload->>'fecha_desde'))::date;
    IF NOT v_abierta THEN v_fecha_hasta := (btrim(payload->>'fecha_hasta'))::date; END IF;
  EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido', 'detalle', 'cast de fecha fallido'); END;
  -- V6 fechas coherentes + no pasado
  IF NOT v_abierta AND v_fecha_hasta < v_fecha_desde THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas', 'detalle', 'fecha_hasta < fecha_desde'); END IF;
  IF v_fecha_desde < CURRENT_DATE THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas', 'detalle', 'fecha_desde en el pasado'); END IF;
  -- V7 dias: objeto con EXACTAMENTE 7 claves 0-6, cada una hora_checkin/hora_checkout validas, ventana y gap.
  v_dias := payload->'dias';
  IF jsonb_typeof(v_dias) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'dias_invalido', 'detalle', 'dias debe ser objeto keyed por dia_semana 0-6'); END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(v_dias)) <> 7 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'dias_incompleto', 'detalle', 'dias debe tener exactamente 7 claves (0-6)'); END IF;
  FOR v_dow IN 0..6 LOOP
    IF NOT (v_dias ? v_dow::text) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'dias_incompleto', 'detalle', 'falta el dia', 'dia_semana', v_dow); END IF;
    v_ci_s := NULLIF(btrim(v_dias->v_dow::text->>'hora_checkin'), '');
    v_co_s := NULLIF(btrim(v_dias->v_dow::text->>'hora_checkout'), '');
    IF v_ci_s IS NULL OR v_co_s IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'dias_invalido', 'detalle', 'hora_checkin/hora_checkout requeridas', 'dia_semana', v_dow); END IF;
    IF v_ci_s !~ v_hora_re OR v_co_s !~ v_hora_re THEN
      RETURN jsonb_build_object('ok', false, 'error', 'dias_invalido', 'detalle', 'formato de hora invalido (HH:MM[:SS])', 'dia_semana', v_dow); END IF;
    BEGIN v_ci := v_ci_s::time; v_co := v_co_s::time;
    EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok', false, 'error', 'dias_invalido', 'detalle', 'cast de hora fallido', 'dia_semana', v_dow); END;
    IF v_ci NOT BETWEEN TIME '07:00' AND TIME '22:00' OR v_co NOT BETWEEN TIME '07:00' AND TIME '22:00' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'hora_fuera_de_ventana', 'dia_semana', v_dow, 'detalle', 'fuera de [07:00,22:00]'); END IF;
    IF (v_ci - v_co) < INTERVAL '2 hours' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'gap_insuficiente', 'dia_semana', v_dow, 'detalle', 'checkin - checkout < 2h'); END IF;
  END LOOP;
  -- V8 no solapamiento (pre-check; exc_vigencias_no_overlap es la red)
  SELECT array_agg(id_vigencia ORDER BY id_vigencia) INTO v_solapadas FROM public.vigencias_horario_base
  WHERE activo AND (CASE WHEN abierta THEN daterange(fecha_desde, NULL) ELSE daterange(fecha_desde, fecha_hasta, '[]') END)
        && (CASE WHEN v_abierta THEN daterange(v_fecha_desde, NULL) ELSE daterange(v_fecha_desde, v_fecha_hasta, '[]') END);
  IF v_solapadas IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vigencia_solapada', 'detalle', 'solapa vigencia(s) activa(s)', 'ids_conflicto', to_jsonb(v_solapadas)); END IF;
  -- V9 G1-targeted (helper con p_dias; trg_vig_guard es la red diferida)
  v_conf := public.vigencias_conflictos_comprometidos(v_fecha_desde, v_fecha_hasta, v_abierta, v_dias);
  IF jsonb_array_length(v_conf) > 0 THEN
    IF v_conf @> '[{"motivo":"resolver_horario_invalido"}]'::jsonb THEN
      RETURN jsonb_build_object('ok', false, 'error', 'resolver_horario_invalido', 'detalle', 'resolver ok<>true para un comprometido en rango (fail-closed)', 'conflictos', v_conf); END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'base_pisa_comprometido', 'detalle', 'turno pegado <2h contra comprometido donde la base gobierna', 'conflictos', v_conf); END IF;
  -- Persistencia: cabecera + 7 detalle (atomico; el trigger diferido revalida completitud + G1)
  INSERT INTO public.vigencias_horario_base (fecha_desde, fecha_hasta, abierta, motivo, creado_por, source_event)
  VALUES (v_fecha_desde, v_fecha_hasta, v_abierta, v_motivo, v_creado_por, v_source)
  RETURNING id_vigencia INTO v_id;
  FOR v_dow IN 0..6 LOOP
    INSERT INTO public.vigencias_horario_detalle (id_vigencia, dia_semana, hora_checkin, hora_checkout)
    VALUES (v_id, v_dow, (v_dias->v_dow::text->>'hora_checkin')::time, (v_dias->v_dow::text->>'hora_checkout')::time);
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'id_vigencia', v_id, 'fecha_desde', v_fecha_desde, 'fecha_hasta', v_fecha_hasta,
    'abierta', v_abierta, 'dias', v_dias, 'creado_por', v_creado_por, 'source_event', v_source, 'created_at', now());
END
$A_guard$;

REVOKE EXECUTE ON FUNCTION public.crear_vigencia_horario(jsonb) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.crear_vigencia_horario(jsonb) IS
  'B1.3-A guard vigencias semanales. Puerta sancionada: alta de UNA vigencia semanal. Toma pg_advisory_xact_lock(919010); parsea/valida cabecera + dias (objeto keyed por dia_semana 0-6, EXACTAMENTE 7 claves; formato/ventana/gap por dia); pre-chequea solapamiento y G1 (helper con p_dias, fail-closed); INSERT cabecera + 7 detalle (atomico). Errores: payload_invalido, abierta_inconsistente, fechas_invalidas, dias_invalido, dias_incompleto, hora_fuera_de_ventana, gap_insuficiente, vigencia_solapada, base_pisa_comprometido, resolver_horario_invalido. Regla no-pasado SOLO aca. La barrera diferida trg_vig_guard revalida completitud (7 filas) + G1 en commit. B1.3-A - TEST.';

-- =====================================================================
-- (5) TRIGGER barrera diferida: G1 + completitud exacta de 7 filas
-- =====================================================================
DROP TRIGGER IF EXISTS trg_vig_guard ON public.vigencias_horario_base;
DROP FUNCTION public.trg_guard_vigencias();
CREATE FUNCTION public.trg_guard_vigencias()
RETURNS trigger LANGUAGE plpgsql AS $A_trg$
DECLARE
  v_id BIGINT; v_activo BOOLEAN; v_fd DATE; v_fh DATE; v_ab BOOLEAN;
  v_n INT; v_dias jsonb; v_dows int[]; v_conf jsonb; v_err TEXT;
BEGIN
  v_id := NEW.id_vigencia;   -- presente en cabecera y detalle
  SELECT activo, fecha_desde, fecha_hasta, abierta
    INTO v_activo, v_fd, v_fh, v_ab
  FROM public.vigencias_horario_base WHERE id_vigencia = v_id;
  IF NOT FOUND THEN RETURN NEW; END IF;         -- cabecera ausente => inerte
  IF v_activo IS NOT TRUE THEN RETURN NEW; END IF; -- desactivada => inerte

  -- Completitud: exactamente 7 filas, dias 0-6 distintos.
  SELECT count(*), array_agg(dia_semana ORDER BY dia_semana),
         jsonb_object_agg(dia_semana::text, jsonb_build_object('hora_checkin', hora_checkin, 'hora_checkout', hora_checkout))
    INTO v_n, v_dows, v_dias
  FROM public.vigencias_horario_detalle WHERE id_vigencia = v_id;
  IF v_n <> 7 OR v_dows IS DISTINCT FROM ARRAY[0,1,2,3,4,5,6] THEN
    RAISE EXCEPTION 'guard_vigencias: vigencia_incompleta' USING ERRCODE = '45000',
      DETAIL = jsonb_build_object('error','vigencia_incompleta','id_vigencia',v_id,'filas',v_n,'dias',COALESCE(to_jsonb(v_dows),'null'::jsonb))::text;
  END IF;

  -- G1: la vigencia (ya completa) no pisa comprometidos donde la base gobierna.
  v_conf := public.vigencias_conflictos_comprometidos(v_fd, v_fh, v_ab, v_dias);
  IF jsonb_array_length(v_conf) > 0 THEN
    IF v_conf @> '[{"motivo":"resolver_horario_invalido"}]'::jsonb THEN v_err := 'resolver_horario_invalido';
    ELSE v_err := 'base_pisa_comprometido'; END IF;
    RAISE EXCEPTION 'guard_vigencias: %', v_err USING ERRCODE = '45000',
      DETAIL = jsonb_build_object('error', v_err, 'tg_op', TG_OP, 'id_vigencia', v_id, 'conflictos', v_conf)::text;
  END IF;

  RETURN NEW;
END
$A_trg$;

-- Dispara sobre detalle (cambios de horas) y cabecera (rango/activo). Diferido:
-- la deferral garantiza que al commit existan las 7 filas insertadas por el guard.
CREATE CONSTRAINT TRIGGER trg_vig_guard
  AFTER INSERT OR UPDATE ON public.vigencias_horario_base
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.trg_guard_vigencias();
CREATE CONSTRAINT TRIGGER trg_vig_guard_detalle
  AFTER INSERT OR UPDATE ON public.vigencias_horario_detalle
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.trg_guard_vigencias();

REVOKE EXECUTE ON FUNCTION public.trg_guard_vigencias() FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.trg_guard_vigencias() IS
  'B1.3-A barrera diferida vigencias semanales. Trigger-fn compartida por trg_vig_guard (cabecera) y trg_vig_guard_detalle (detalle). Resuelve id_vigencia de NEW; si la cabecera no existe o NO activo => inerte. Valida COMPLETITUD (exactamente 7 filas, dias 0-6) y G1 (helper vigencias_conflictos_comprometidos con p_dias del detalle; provenance ciega, fail-closed) SOLO en INSERT/UPDATE. RAISE ERRCODE 45000 con DETAIL jsonb; error in {vigencia_incompleta, base_pisa_comprometido, resolver_horario_invalido}. DELETE de detalle INERTE por diseno: no revalida ante borrados destructivos manuales; la garantia contra un detalle faltante recae en el resolver, que responde vigencia_incompleta. Desactivacion/lifecycle FUERA de A. B1.3-A - TEST.';
COMMENT ON TRIGGER trg_vig_guard ON public.vigencias_horario_base IS
  'B1.3-A barrera diferida (cabecera). Valida completitud+G1 del estado FINAL en commit. DEFERRABLE INITIALLY DEFERRED. B1.3-A - TEST.';
COMMENT ON TRIGGER trg_vig_guard_detalle ON public.vigencias_horario_detalle IS
  'B1.3-A barrera diferida (detalle). Necesaria para que insertar/actualizar horas revalide completitud+G1 (la deferral asegura las 7 filas al commit). B1.3-A - TEST.';

-- ---- POSTCHECKS intra-tx ----
DO $post$
DECLARE
  r text; v_wrap_pre text; v_wrap_post text; v_odr_pre text; v_odr_post text;
  v_vista_pre bigint; v_vista_post bigint; v_probe jsonb;
BEGIN
  -- owner-only (interno/helper/guard/trigger-fn), incl. PUBLIC
  FOREACH r IN ARRAY ARRAY['public','anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r, 'public._resolver_horario(bigint,date,boolean)', 'EXECUTE') THEN
      RAISE EXCEPTION 'POST: interno EXECUTE concedido a %.', r; END IF;
    IF has_function_privilege(r, 'public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)', 'EXECUTE') THEN
      RAISE EXCEPTION 'POST: helper EXECUTE concedido a %.', r; END IF;
    IF has_function_privilege(r, 'public.crear_vigencia_horario(jsonb)', 'EXECUTE') THEN
      RAISE EXCEPTION 'POST: guard EXECUTE concedido a %.', r; END IF;
    IF has_function_privilege(r, 'public.trg_guard_vigencias()', 'EXECUTE') THEN
      RAISE EXCEPTION 'POST: trigger-fn EXECUTE concedido a %.', r; END IF;
  END LOOP;
  -- WRAPPER intacto (post == pre): confirma que A NO lo toco (fingerprint sobrevive)
  SELECT v INTO v_wrap_pre FROM _mig_meta WHERE k='wrapper_pre';
  v_wrap_post := md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure));
  IF v_wrap_post IS DISTINCT FROM v_wrap_pre THEN
    RAISE EXCEPTION 'POST: wrapper fingerprint cambio (pre=%, post=%). A no debe tocar el wrapper.', v_wrap_pre, v_wrap_post; END IF;
  -- ODR intacto (post == pre)
  SELECT v INTO v_odr_pre FROM _mig_meta WHERE k='odr_pre';
  v_odr_post := md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  IF v_odr_post IS DISTINCT FROM v_odr_pre THEN
    RAISE EXCEPTION 'POST: ODR fingerprint cambio (pre=%, post=%).', v_odr_pre, v_odr_post; END IF;
  -- vista conteo intacto y > 0
  SELECT v::bigint INTO v_vista_pre FROM _mig_meta WHERE k='vista_pre';
  SELECT count(*) INTO v_vista_post FROM public.vista_disponibilidad;
  IF v_vista_post = 0 THEN RAISE EXCEPTION 'POST: vista_disponibilidad 0 filas (cadena rota).'; END IF;
  IF v_vista_post IS DISTINCT FROM v_vista_pre THEN
    RAISE EXCEPTION 'POST: conteo vista cambio (pre=%, post=%).', v_vista_pre, v_vista_post; END IF;
  -- cabecera sin las 4 columnas viejas; detalle presente
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='vigencias_horario_base' AND column_name='hora_checkin_default') THEN
    RAISE EXCEPTION 'POST: la cabecera aun tiene columnas de hora viejas.'; END IF;
  IF to_regclass('public.vigencias_horario_detalle') IS NULL THEN
    RAISE EXCEPTION 'POST: falta vigencias_horario_detalle.'; END IF;
  -- sanity resolver: fecha sin vigencia => config, ok=true
  v_probe := public.resolver_horario((SELECT MIN(id_cabana) FROM public.cabanas), CURRENT_DATE + 400);
  IF COALESCE((v_probe->>'ok')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'POST: resolver sanity fallo: %', v_probe; END IF;
  RAISE NOTICE 'POSTCHECKS OK: owner-only; wrapper intacto (==pre); ODR intacto; vista=% (==pre); cabecera sin horas viejas; detalle presente; resolver ok.', v_vista_post;
END
$post$;

COMMIT;

-- ---- REPORTE (autocommit, read-only; ULTIMO => se muestra) ----
SELECT
  'B1.3-A aplicado (TEST)'                                                                    AS estado,
  md5(pg_get_functiondef('public.resolver_horario(bigint,date)'::regprocedure))              AS wrapper_fp_intacto,
  md5(pg_get_functiondef('public._resolver_horario(bigint,date,boolean)'::regprocedure))      AS interno_fp_nuevo,
  md5(pg_get_functiondef('public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)'::regprocedure)) AS helper_fp_nuevo,
  md5(pg_get_functiondef('public.crear_vigencia_horario(jsonb)'::regprocedure))              AS guard_fp_nuevo,
  md5(pg_get_functiondef('public.trg_guard_vigencias()'::regprocedure))                       AS trg_fp_nuevo,
  md5(pg_get_functiondef('public.obtener_disponibilidad_rango(date,date,bigint)'::regprocedure)) AS odr_fp_intacto;
