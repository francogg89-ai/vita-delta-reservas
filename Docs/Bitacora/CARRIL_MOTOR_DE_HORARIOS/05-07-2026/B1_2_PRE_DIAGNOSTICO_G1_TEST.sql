-- =====================================================================
-- B1.2-pre - Integracion de vigencias en resolver_horario
-- Artefacto 1/2: DIAGNOSTICO DE PRECONDICION G1 (read-only)
-- -----------------------------------------------------------------------
-- OBJETIVO: visibilidad. Antes de cablear el resolver (B1.2-core), listar
--   toda vigencia ACTIVA que pisaria un comprometido vivo bajo el regimen
--   base/config. Reusa el helper de B1.1 (vigencias_conflictos_comprometidos)
--   con el resolver R0 actual, que es ciego a vigencias por naturaleza.
-- LECTURA DE LA SALIDA:
--   * 0 filas de conflicto (veredicto CAMINO_LIBRE) => habilita B1.2-core.
--   * >=1 conflicto (veredicto STOP) => resolver (desactivar/ajustar vigencia
--     o booking) ANTES de B1.2-core. El gate transaccional embebido en core
--     re-chequea esto; este diagnostico NO lo reemplaza (solo da el detalle).
-- ALCANCE: read-only. NO muta, NO consume secuencia, NO toca resolver_horario,
--   OPS, portal-api, frontend, wrappers n8n, Vercel, canonico ni config.
-- =====================================================================

-- ---- GATE anti-ambiente + estado B1.1 esperado (read-only) ----
DO $gate$
DECLARE v_amb TEXT; v_res TEXT; v_odr TEXT;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE B1.2-pre-diag: ambiente=% (esperado test). Abortando.', v_amb;
  END IF;
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'GATE B1.2-pre-diag: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  v_res := md5(pg_get_functiondef('resolver_horario(bigint,date)'::regprocedure));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'GATE B1.2-pre-diag: fingerprint resolver=% (esperado 58d75c1b6b812ee2d2c9751ddcb0cd4d, estado B1.1/R0). Abortando.', v_res;
  END IF;
  v_odr := md5(pg_get_functiondef('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE B1.2-pre-diag: fingerprint ODR=% (esperado 37009a32154f93b80520500c0f15b46b). Abortando.', v_odr;
  END IF;
  IF to_regclass('public.vigencias_horario_base') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.2-pre-diag: falta vigencias_horario_base (B1.1 no instalado). Abortando.';
  END IF;
  IF to_regprocedure('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.2-pre-diag: falta helper vigencias_conflictos_comprometidos (B1.1). Abortando.';
  END IF;
END
$gate$;

-- =====================================================================
-- DIAGNOSTICO: cada vigencia ACTIVA evaluada por el helper G1 contra
-- comprometidos vivos. Salida consolidada (un solo result set):
--   filas DETALLE por cada vigencia con conflicto + una fila VEREDICTO final.
-- =====================================================================
WITH activas AS (
  SELECT id_vigencia, fecha_desde, fecha_hasta, abierta,
         hora_checkin_default, hora_checkin_domingo, hora_checkout_default, hora_checkout_domingo
  FROM public.vigencias_horario_base
  WHERE activo
),
evaluadas AS (
  SELECT a.id_vigencia, a.fecha_desde, a.fecha_hasta, a.abierta,
         public.vigencias_conflictos_comprometidos(
           a.fecha_desde, a.fecha_hasta, a.abierta,
           a.hora_checkin_default, a.hora_checkin_domingo,
           a.hora_checkout_default, a.hora_checkout_domingo) AS conflictos
  FROM activas a
),
con_conflicto AS (
  SELECT * FROM evaluadas WHERE jsonb_array_length(conflictos) > 0
)
SELECT * FROM (
  SELECT
    1 AS orden,
    'DETALLE'::text                                   AS tipo,
    id_vigencia::text                                 AS id_vigencia,
    'rango=' || fecha_desde::text || '..' ||
      COALESCE(fecha_hasta::text, '(abierta)')        AS rango,
    jsonb_array_length(conflictos)::text              AS n_conflictos,
    conflictos::text                                  AS conflictos
  FROM con_conflicto
  UNION ALL
  SELECT
    2 AS orden,
    'VEREDICTO'::text                                 AS tipo,
    NULL                                              AS id_vigencia,
    'vigencias_activas=' || (SELECT count(*) FROM activas)::text        AS rango,
    'con_conflicto=' || (SELECT count(*) FROM con_conflicto)::text      AS n_conflictos,
    CASE WHEN (SELECT count(*) FROM con_conflicto) = 0
         THEN 'CAMINO_LIBRE (habilita B1.2-core)'
         ELSE 'STOP (resolver conflictos antes de B1.2-core)' END       AS conflictos
) q
ORDER BY orden, id_vigencia;
