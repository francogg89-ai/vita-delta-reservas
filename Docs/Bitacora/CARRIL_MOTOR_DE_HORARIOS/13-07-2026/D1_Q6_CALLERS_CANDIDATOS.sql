-- ====================================================================================
-- D1_Q6_CALLERS_CANDIDATOS.sql
-- Bloque B1.3-consolidacion-canonica * D1 * candidatos de callers por texto (heuristica)
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
      'GATE D1: ambiente=% (esperado test). Abortando.',
      COALESCE(v_amb, '<null>');
  END IF;
END
$gate$;

-- Q6 -- CANDIDATOS DE CALLERS POR TEXTO (N filas). HEURISTICA, NO AUTORIDAD.
--
--   ADVERTENCIA -- ESTE BLOQUE NO ES UNA AUTORIDAD DEL GRAFO DE LLAMADAS:
--     * Es una busqueda por TEXTO, no un analisis semantico.
--     * Puede encontrar COMENTARIOS, STRINGS literales o identificadores casuales que
--       contengan el nombre sin ser una invocacion.
--     * NO resuelve overloads por firma: si hay dos funciones con el mismo proname y
--       distintos argumentos, este bloque no distingue a cual se llama.
--     * Puede OMITIR invocaciones via SQL dinamico (EXECUTE 'SELECT ' || nombre),
--       nombres construidos en runtime, o invocaciones indirectas (regprocedure en una
--       variable, triggers apuntando por oid, etc.).
--   Cada match viene con su VENTANA DE CONTEXTO. La clasificacion final es manual.
--
--   Universo barrido: pg_get_functiondef() de TODAS las funciones/procedimientos de
--   public (superset de prosrc: incluye header y clausulas SET) + pg_views + pg_matviews.
--   Word-boundary \m..\M para no matchear substrings. Auto-referencias excluidas.
WITH targets(n, nombre, sig) AS (
  VALUES
    ( 1,'resolver_horario',                  'public.resolver_horario(bigint,date)'),
    ( 2,'_resolver_horario',                 'public._resolver_horario(bigint,date,boolean)'),
    ( 3,'vigencias_conflictos_comprometidos','public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)'),
    ( 4,'crear_vigencia_horario',            'public.crear_vigencia_horario(jsonb)'),
    ( 5,'trg_guard_vigencias',               'public.trg_guard_vigencias()'),
    ( 6,'validar_gap_bordes_congelados',     'public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)'),
    ( 7,'crear_prereserva',                  'public.crear_prereserva(jsonb)'),
    ( 8,'confirmar_reserva',                 'public.confirmar_reserva(jsonb)'),
    ( 9,'crear_reserva_con_horario_pactado', 'public.crear_reserva_con_horario_pactado(jsonb)'),
    (10,'crear_override_horario_puntual',    'public.crear_override_horario_puntual(jsonb)'),
    (11,'obtener_disponibilidad_rango',      'public.obtener_disponibilidad_rango(date,date,bigint)')
),
funcs AS (
  SELECT p.oid AS oid,
         format('%I.%I(%s)', n.nspname, p.proname,
                pg_get_function_identity_arguments(p.oid)) AS objeto,
         'funcion'::text                                   AS tipo,
         pg_get_functiondef(p.oid)                         AS cuerpo
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind IN ('f','p')
),
vistas AS (
  SELECT NULL::oid, format('%I.%I', schemaname, viewname), 'vista'::text, definition
  FROM pg_views WHERE schemaname = 'public'
  UNION ALL
  SELECT NULL::oid, format('%I.%I', schemaname, matviewname), 'matview'::text, definition
  FROM pg_matviews WHERE schemaname = 'public'
),
universo AS (SELECT * FROM funcs UNION ALL SELECT * FROM vistas)
SELECT
  'Q6_CALLERS_CANDIDATOS'                                           AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  t.n                                                               AS nro,
  t.sig                                                             AS objeto_buscado,
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
WHERE u.oid IS DISTINCT FROM to_regprocedure(t.sig)::oid
ORDER BY t.n, u.objeto, m.ord;

COMMIT;
