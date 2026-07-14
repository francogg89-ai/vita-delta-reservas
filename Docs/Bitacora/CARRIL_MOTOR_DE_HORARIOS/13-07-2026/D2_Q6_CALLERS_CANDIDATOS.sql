-- ====================================================================================
-- D2_Q6_CALLERS_CANDIDATOS.sql
-- Bloque B1.3-consolidacion-canonica * D2 * candidatos de callers por texto (heuristica)
-- ALCANCE: objetos del carril Motor de Horarios que quedaron FUERA del pin de 11 de S8.
-- TEST unicamente. 100% LECTURA. Autocontenido: trae su propio gate y su propia
-- transaccion READ ONLY. No se puede ejecutar esta Q sin el gate: el archivo ES la Q.
-- Repo de referencia: HEAD 07fea85802bc4fccbff1236813593762aefe58d9
-- ====================================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog, public;

DO $gate$
DECLARE
  v_amb text := (
    SELECT valor
    FROM public.configuracion_general
    WHERE clave = 'ambiente'
  );
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION
      'GATE D2: ambiente=% (esperado test). Abortando.',
      COALESCE(v_amb, '<null>');
  END IF;
END
$gate$;

-- Q6 -- CANDIDATOS DE CALLERS POR TEXTO (N filas). HEURISTICA, NO AUTORIDAD.
--
--   ADVERTENCIA (identica a la de D1 Q6):
--     * Busqueda por TEXTO, no analisis semantico.
--     * Puede encontrar COMENTARIOS, STRINGS o identificadores casuales.
--     * NO resuelve overloads por firma.
--     * Puede OMITIR SQL dinamico (EXECUTE 'SELECT ' || nombre) e invocaciones indirectas.
--   Cada match trae su VENTANA DE CONTEXTO. La clasificacion final es manual.
WITH targets(nombre) AS (
  VALUES
    ('validar_estado_horario_final'),
    ('validar_no_eventos_comprometidos'),
    ('validar_estado_override'),
    ('trg_guard_overrides'),
    ('crear_override_horario'),
    ('crear_bloqueo'),
    ('fecha_hoy_ar')
),
funcs AS (
  SELECT p.oid AS oid,
         format('%I.%I(%s)', n.nspname, p.proname,
                pg_get_function_identity_arguments(p.oid)) AS objeto,
         'funcion'::text                                   AS tipo,
         p.proname                                         AS pron,
         pg_get_functiondef(p.oid)                         AS cuerpo
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind IN ('f','p')
),
vistas AS (
  SELECT NULL::oid, format('%I.%I', schemaname, viewname), 'vista'::text, NULL::name, definition
  FROM pg_views WHERE schemaname = 'public'
  UNION ALL
  SELECT NULL::oid, format('%I.%I', schemaname, matviewname), 'matview'::text, NULL::name, definition
  FROM pg_matviews WHERE schemaname = 'public'
),
universo AS (SELECT * FROM funcs UNION ALL SELECT * FROM vistas)
SELECT
  'D2_Q6_CALLERS_CANDIDATOS'                                        AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  t.nombre                                                          AS objeto_buscado,
  u.objeto                                                          AS candidato,
  u.tipo                                                            AS tipo_candidato,
  m.ord                                                             AS ocurrencia,
  regexp_replace(
    COALESCE(m.g[1],'') || ' >>>' || m.g[2] || '<<< ' || COALESCE(m.g[3],''),
    '\s+', ' ', 'g')                                               AS ventana_contexto,
  CASE
    WHEN COALESCE(m.g[1],'') ~ '--'      THEN 'pista: posible COMENTARIO'
    WHEN COALESCE(m.g[3],'') ~ '^\s*\(' THEN 'pista: posible INVOCACION'
    ELSE 'pista: mencion suelta -- clasificar a mano'
  END                                                               AS pista_heuristica
FROM targets t
JOIN universo u ON u.cuerpo ~ ('\m' || t.nombre || '\M')
CROSS JOIN LATERAL (
  SELECT row_number() OVER () AS ord, mm AS g
  FROM regexp_matches(
         u.cuerpo,
         '([^\n]{0,70})(\m' || t.nombre || '\M)([^\n]{0,70})',
         'g') AS mm
) m
WHERE u.pron IS DISTINCT FROM t.nombre
ORDER BY t.nombre, u.objeto, m.ord;

COMMIT;
