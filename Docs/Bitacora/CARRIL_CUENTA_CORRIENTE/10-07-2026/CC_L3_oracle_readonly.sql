-- ============================================================================
-- CC_L3_oracle_readonly.sql
-- Frente Cuenta corriente de socios / L3 - Bloque 0 (exposicion read-only A30/A31).
-- ORACLE de NO-MUTACION: prueba que exponer/leer historico + acumulados NO altera ninguna
-- tabla, fila, ID ni secuencia relevante (incluye deteccion de UPDATEs via hash de contenido).
--
-- Es SOLO LECTURA: no crea tablas, no inserta, no usa DDL, funciones temporales ni SQL dinamico.
-- Toma un "fingerprint" (jsonb) del estado ANTES de correr los smokes, y otro DESPUES; se comparan
-- con diff automatico sobre CUATRO secciones: counts, max_ids, table_hashes, sequences.
--
-- Uso (Supabase SQL Editor de TEST; ejecuta el texto SELECCIONADO, o todo si no hay seleccion):
--   1) Correr PARTE A ANTES de los smokes. Copiar el valor de la columna 'fingerprint'.
--   2) Correr los smokes (directos A30/A31 y/o gateway).
--   3) Pegar ese valor en el marcador de PARTE B y correr PARTE B. Leer 'veredicto'.
--
-- IMPORTANTE (operativo): correr en una ventana SIN otras escrituras concurrentes en TEST.
--   Un snapshot/retiro/gasto legitimo de OTRO proceso entre A y B daria un FALSO POSITIVO
--   (mutacion), que NO seria culpa de las lecturas L3.
--
-- ---- ALCANCE EXACTO DEL FINGERPRINT ----
-- Tablas relevantes (7): liquidaciones_periodo, liquidacion_cascada, liquidacion_socio,
--   liquidacion_participacion, liquidacion_gasto, liquidacion_incidencia, movimientos_socio.
-- counts: count(*) de las 7 tablas.
-- table_hashes: md5(jsonb_agg(to_jsonb(fila) ORDER BY PK)) de las 7 tablas -> detecta UPDATEs a
--   cualquier columna (contenido completo, orden determinista por PK). PKs usadas:
--     liquidaciones_periodo(id_liquidacion); liquidacion_cascada(id_liquidacion,paso);
--     liquidacion_socio(id_liquidacion,id_socio); liquidacion_participacion(id_liquidacion,id_cabana);
--     liquidacion_gasto(id_liquidacion,id_gasto); liquidacion_incidencia(id_liquidacion,id_gasto,seq);
--     movimientos_socio(id_movimiento).
-- max_ids: max() de las 2 columnas BIGSERIAL de una sola columna
--   (liquidaciones_periodo.id_liquidacion, movimientos_socio.id_movimiento).
-- sequences: last_value de las 2 secuencias reales, descubiertas dinamicamente con
--   pg_get_serial_sequence (NO asumidas). Las 5 tablas de PK compuesta no aportan secuencia
--   (pg_get_serial_sequence -> NULL -> excluidas). NOTA: pg_sequences NO expone is_called;
--   se captura unicamente last_value.
-- ============================================================================


-- =====================================================================
-- PARTE A -- BEFORE  (correr ANTES de los smokes; copiar 'fingerprint')
-- =====================================================================
SELECT jsonb_build_object(
  'counts', jsonb_build_object(
    'liquidaciones_periodo',     (SELECT count(*) FROM liquidaciones_periodo),
    'liquidacion_cascada',       (SELECT count(*) FROM liquidacion_cascada),
    'liquidacion_socio',         (SELECT count(*) FROM liquidacion_socio),
    'liquidacion_participacion', (SELECT count(*) FROM liquidacion_participacion),
    'liquidacion_gasto',         (SELECT count(*) FROM liquidacion_gasto),
    'liquidacion_incidencia',    (SELECT count(*) FROM liquidacion_incidencia),
    'movimientos_socio',         (SELECT count(*) FROM movimientos_socio)
  ),
  'table_hashes', jsonb_build_object(
    'liquidaciones_periodo',     (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion)::text, '[]')) FROM liquidaciones_periodo t),
    'liquidacion_cascada',       (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion, t.paso)::text, '[]')) FROM liquidacion_cascada t),
    'liquidacion_socio',         (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion, t.id_socio)::text, '[]')) FROM liquidacion_socio t),
    'liquidacion_participacion', (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion, t.id_cabana)::text, '[]')) FROM liquidacion_participacion t),
    'liquidacion_gasto',         (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion, t.id_gasto)::text, '[]')) FROM liquidacion_gasto t),
    'liquidacion_incidencia',    (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion, t.id_gasto, t.seq)::text, '[]')) FROM liquidacion_incidencia t),
    'movimientos_socio',         (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_movimiento)::text, '[]')) FROM movimientos_socio t)
  ),
  'max_ids', jsonb_build_object(
    'liquidaciones_periodo.id_liquidacion', (SELECT COALESCE(max(id_liquidacion),0)::text FROM liquidaciones_periodo),
    'movimientos_socio.id_movimiento',      (SELECT COALESCE(max(id_movimiento),0)::text  FROM movimientos_socio)
  ),
  'sequences', COALESCE((
    SELECT jsonb_object_agg(x.name, jsonb_build_object('last_value', x.last_value))
    FROM (
      SELECT (d.fqn)::regclass::text AS name,
             sq.last_value           AS last_value
      FROM (VALUES
        (pg_get_serial_sequence('liquidaciones_periodo','id_liquidacion')),
        (pg_get_serial_sequence('movimientos_socio','id_movimiento'))
      ) AS d(fqn)
      JOIN pg_sequences sq
        ON format('%I.%I', sq.schemaname, sq.sequencename)::regclass = (d.fqn)::regclass
      WHERE d.fqn IS NOT NULL
    ) x
  ), '{}'::jsonb),
  'captured_at', now()
) AS fingerprint;


-- =====================================================================
-- PARTE B -- AFTER + DIFF  (correr DESPUES de los smokes)
--   Pegar el fingerprint de PARTE A donde dice PEGAR_FINGERPRINT_BEFORE.
--   'captured_at' se ignora en la comparacion (cambia por diseno).
--   Veredicto OK: 0 mutacion SOLO si (1) la FORMA de ambos fingerprints es 7/7/2/2
--   (counts=7, table_hashes=7, max_ids=2, sequences=2) Y (2) las 4 secciones son identicas.
--   Si falta una seccion o la forma no es 7/7/2/2 -> FALLA de cobertura, aunque before==after
--   (evita el falso verde de dos {} vacios que no descubrieron las secuencias). Columnas
--   before_shape_ok / after_shape_ok / *_key_counts documentan la forma observada.
-- =====================================================================
WITH before AS (
  SELECT
    -- >>>>>>>>>> PEGAR_FINGERPRINT_BEFORE (reemplazar el objeto de ejemplo) <<<<<<<<<<
    '{"counts":{},"table_hashes":{},"max_ids":{},"sequences":{},"captured_at":null}'::jsonb
    AS fp
),
after AS (
  SELECT jsonb_build_object(
    'counts', jsonb_build_object(
      'liquidaciones_periodo',     (SELECT count(*) FROM liquidaciones_periodo),
      'liquidacion_cascada',       (SELECT count(*) FROM liquidacion_cascada),
      'liquidacion_socio',         (SELECT count(*) FROM liquidacion_socio),
      'liquidacion_participacion', (SELECT count(*) FROM liquidacion_participacion),
      'liquidacion_gasto',         (SELECT count(*) FROM liquidacion_gasto),
      'liquidacion_incidencia',    (SELECT count(*) FROM liquidacion_incidencia),
      'movimientos_socio',         (SELECT count(*) FROM movimientos_socio)
    ),
    'table_hashes', jsonb_build_object(
      'liquidaciones_periodo',     (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion)::text, '[]')) FROM liquidaciones_periodo t),
      'liquidacion_cascada',       (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion, t.paso)::text, '[]')) FROM liquidacion_cascada t),
      'liquidacion_socio',         (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion, t.id_socio)::text, '[]')) FROM liquidacion_socio t),
      'liquidacion_participacion', (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion, t.id_cabana)::text, '[]')) FROM liquidacion_participacion t),
      'liquidacion_gasto',         (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion, t.id_gasto)::text, '[]')) FROM liquidacion_gasto t),
      'liquidacion_incidencia',    (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_liquidacion, t.id_gasto, t.seq)::text, '[]')) FROM liquidacion_incidencia t),
      'movimientos_socio',         (SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id_movimiento)::text, '[]')) FROM movimientos_socio t)
    ),
    'max_ids', jsonb_build_object(
      'liquidaciones_periodo.id_liquidacion', (SELECT COALESCE(max(id_liquidacion),0)::text FROM liquidaciones_periodo),
      'movimientos_socio.id_movimiento',      (SELECT COALESCE(max(id_movimiento),0)::text  FROM movimientos_socio)
    ),
    'sequences', COALESCE((
      SELECT jsonb_object_agg(x.name, jsonb_build_object('last_value', x.last_value))
      FROM (
        SELECT (d.fqn)::regclass::text AS name,
               sq.last_value           AS last_value
        FROM (VALUES
          (pg_get_serial_sequence('liquidaciones_periodo','id_liquidacion')),
          (pg_get_serial_sequence('movimientos_socio','id_movimiento'))
        ) AS d(fqn)
        JOIN pg_sequences sq
          ON format('%I.%I', sq.schemaname, sq.sequencename)::regclass = (d.fqn)::regclass
        WHERE d.fqn IS NOT NULL
      ) x
    ), '{}'::jsonb),
    'captured_at', now()
  ) AS fp
),
strip AS (
  SELECT (SELECT fp - 'captured_at' FROM before) AS b,
         (SELECT fp - 'captured_at' FROM after)  AS a
),
shape AS (
  -- NOTA: PostgreSQL no tiene jsonb_object_length. Se cuentan las claves con jsonb_object_keys
  -- (guardado por jsonb_typeof='object'; una seccion ausente/no-objeto -> -1, nunca aprueba forma).
  SELECT b, a,
    CASE WHEN jsonb_typeof(b->'counts')='object'       THEN (SELECT count(*)::int FROM jsonb_object_keys(b->'counts'))       ELSE -1 END AS b_counts_n,
    CASE WHEN jsonb_typeof(b->'table_hashes')='object' THEN (SELECT count(*)::int FROM jsonb_object_keys(b->'table_hashes')) ELSE -1 END AS b_thash_n,
    CASE WHEN jsonb_typeof(b->'max_ids')='object'      THEN (SELECT count(*)::int FROM jsonb_object_keys(b->'max_ids'))      ELSE -1 END AS b_maxid_n,
    CASE WHEN jsonb_typeof(b->'sequences')='object'    THEN (SELECT count(*)::int FROM jsonb_object_keys(b->'sequences'))    ELSE -1 END AS b_seq_n,
    CASE WHEN jsonb_typeof(a->'counts')='object'       THEN (SELECT count(*)::int FROM jsonb_object_keys(a->'counts'))       ELSE -1 END AS a_counts_n,
    CASE WHEN jsonb_typeof(a->'table_hashes')='object' THEN (SELECT count(*)::int FROM jsonb_object_keys(a->'table_hashes')) ELSE -1 END AS a_thash_n,
    CASE WHEN jsonb_typeof(a->'max_ids')='object'      THEN (SELECT count(*)::int FROM jsonb_object_keys(a->'max_ids'))      ELSE -1 END AS a_maxid_n,
    CASE WHEN jsonb_typeof(a->'sequences')='object'    THEN (SELECT count(*)::int FROM jsonb_object_keys(a->'sequences'))    ELSE -1 END AS a_seq_n
  FROM strip
)
SELECT
  CASE
    WHEN NOT ( b_counts_n = 7 AND b_thash_n = 7 AND b_maxid_n = 2 AND b_seq_n = 2
           AND a_counts_n = 7 AND a_thash_n = 7 AND a_maxid_n = 2 AND a_seq_n = 2 )
      THEN 'FALLA: cobertura incompleta del fingerprint (forma != 7/7/2/2 en before y/o after)'
    WHEN (b->'counts') = (a->'counts')
     AND (b->'max_ids') = (a->'max_ids')
     AND (b->'table_hashes') = (a->'table_hashes')
     AND (b->'sequences') = (a->'sequences')
      THEN 'OK: 0 mutacion (forma 7/7/2/2 valida + counts + max_ids + table_hashes + sequences identicos)'
    ELSE 'FALLA: MUTACION DETECTADA (revisar delta por seccion)'
  END AS veredicto,
  ( b_counts_n = 7 AND b_thash_n = 7 AND b_maxid_n = 2 AND b_seq_n = 2 ) AS before_shape_ok,
  ( a_counts_n = 7 AND a_thash_n = 7 AND a_maxid_n = 2 AND a_seq_n = 2 ) AS after_shape_ok,
  (b->'counts')       = (a->'counts')       AS counts_iguales,
  (b->'max_ids')      = (a->'max_ids')      AS max_ids_iguales,
  (b->'table_hashes') = (a->'table_hashes') AS table_hashes_iguales,
  (b->'sequences')    = (a->'sequences')    AS sequences_iguales,
  jsonb_build_object('counts', b_counts_n, 'table_hashes', b_thash_n, 'max_ids', b_maxid_n, 'sequences', b_seq_n) AS before_key_counts,
  jsonb_build_object('counts', a_counts_n, 'table_hashes', a_thash_n, 'max_ids', a_maxid_n, 'sequences', a_seq_n) AS after_key_counts,
  b AS before_sin_captured_at,
  a AS after_sin_captured_at
FROM shape;
