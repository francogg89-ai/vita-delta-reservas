-- =====================================================================
-- B1.1 - Motor de Horarios / Carril B1 (vigencias de horario base)
-- Artefacto 1/5: DDL de vigencias_horario_base
-- -----------------------------------------------------------------------
-- ALCANCE: TEST-only e INERTE. NO toca resolver_horario, OPS, portal-api,
--   frontend, wrappers n8n, Vercel, canonico ni configuracion_general.
-- METODO: alta limpia (CREATE TABLE). El resolver NO lee esta tabla en B1.1
--   (eso es B1.2); una vigencia existe pero NO cambia ninguna hora resuelta.
-- HARDENING: REVOKE ALL sobre tabla y secuencia + REVOKE EXECUTE en las
--   funciones (artefactos 2/3). Espejo Bloque 23.
-- NO-SOLAPAMIENTO: EXCLUDE de RANGO PURO (global-only) => GiST nativo
--   (range_ops); NO requiere btree_gist (verificado en harness PG16).
-- =====================================================================

-- ---- GATE anti-ambiente + ecosistema esperado ----
DO $gate$
DECLARE
  v_amb TEXT;
  v_res TEXT;
  v_odr TEXT;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE B1.1-DDL: ambiente=% (esperado test). Abortando.', v_amb;
  END IF;
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'GATE B1.1-DDL: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  IF to_regprocedure('resolver_horario(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.1-DDL: no existe resolver_horario(bigint,date). Abortando.';
  END IF;
  IF to_regprocedure('obtener_disponibilidad_rango(date,date,bigint)') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.1-DDL: no existe obtener_disponibilidad_rango(date,date,bigint). Abortando.';
  END IF;
  v_res := md5(pg_get_functiondef('resolver_horario(bigint,date)'::regprocedure));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'GATE B1.1-DDL: fingerprint resolver=% (esperado 58d75c1b6b812ee2d2c9751ddcb0cd4d, post-R0). Abortando.', v_res;
  END IF;
  v_odr := md5(pg_get_functiondef('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE B1.1-DDL: fingerprint ODR=% (esperado 37009a32154f93b80520500c0f15b46b). Abortando.', v_odr;
  END IF;
  IF to_regprocedure('validar_estado_override(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.1-DDL: faltan validadores S0. Abortando.';
  END IF;
  IF to_regclass('public.vigencias_horario_base') IS NOT NULL THEN
    RAISE EXCEPTION 'GATE B1.1-DDL: vigencias_horario_base ya existe. Abortando (alta limpia).';
  END IF;
END
$gate$;

-- ---- Tabla ----
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
-- VERIFICACION (read-only; no muta). Grants robustos con has_*_privilege
-- (proacl/relacl NULL NO implica 0 permisos: PUBLIC puede tener default).
-- =====================================================================
WITH roles(r) AS (VALUES ('anon'),('authenticated'),('service_role'),('public')),
priv_tabla AS (
  SELECT r,
    has_table_privilege(r, 'public.vigencias_horario_base', 'SELECT')     AS s,
    has_table_privilege(r, 'public.vigencias_horario_base', 'INSERT')     AS i,
    has_table_privilege(r, 'public.vigencias_horario_base', 'UPDATE')     AS u,
    has_table_privilege(r, 'public.vigencias_horario_base', 'DELETE')     AS d
  FROM roles
),
priv_seq AS (
  SELECT r,
    has_sequence_privilege(r, 'public.vigencias_horario_base_id_vigencia_seq', 'USAGE')  AS us,
    has_sequence_privilege(r, 'public.vigencias_horario_base_id_vigencia_seq', 'SELECT') AS se,
    has_sequence_privilege(r, 'public.vigencias_horario_base_id_vigencia_seq', 'UPDATE') AS up
  FROM roles
),
chks AS (
  SELECT count(*) AS n FROM pg_constraint
  WHERE conrelid = 'public.vigencias_horario_base'::regclass AND contype = 'c'
),
excl AS (
  SELECT count(*) AS n FROM pg_constraint
  WHERE conrelid = 'public.vigencias_horario_base'::regclass AND conname = 'exc_vigencias_no_overlap'
)
SELECT
  (SELECT count(*) FROM priv_tabla WHERE s OR i OR u OR d) AS grants_tabla_no_cero,
  (SELECT count(*) FROM priv_seq   WHERE us OR se OR up)   AS grants_seq_no_cero,
  (SELECT n FROM chks)  AS checks_creados_esperado_6,
  (SELECT n FROM excl)  AS exclude_creado_esperado_1,
  CASE WHEN (SELECT count(*) FROM priv_tabla WHERE s OR i OR u OR d) = 0
        AND (SELECT count(*) FROM priv_seq   WHERE us OR se OR up)   = 0
        AND (SELECT n FROM chks) = 6
        AND (SELECT n FROM excl) = 1
       THEN 'PASS' ELSE 'FAIL' END AS veredicto_ddl;
