-- ============================================================================
-- L3_03_VALIDACION_PRE_EXTENSION_TEST.sql   (READ-ONLY; una sola sentencia)
-- Corre cuenta_corriente_historico() contra CADA foto vigente y asevera el
-- CONTRATO JSON. NO escribe. WITH ... SELECT. Sin BEGIN/DO/DDL/DML.
--
-- v2 (contrato reforzado):
--   * keys_ok:   existen TODAS las claves top-level obligatorias (14).
--   * arrays_ok: las 8 secciones-array son realmente arrays (jsonb_typeof=array),
--                incluida gastos_sin_incidencia.
--   * retrib_ok: retribucion_operativo presente y NO nulo (objeto) -- hay foto.
--   * secciones_ok: en pre-extension, participacion/gastos/incidencias/
--                matriz_por_socio/gastos_sin_incidencia son [] (len 0); en foto
--                con detalle, participacion y matriz_por_socio no vacias.
--   * movimientos: solo se exige presencia + tipo array (puede ser [] legitimo).
--
-- En TEST (solo vigentes pre-extension) todas las filas: clase=PRE_EXTENSION,
-- detalle_disponible=false, motivo=foto_pre_extension, sub-checks true, estado=OK.
-- Dinamico: recorre la vigencia real, no hardcodea meses.
-- ============================================================================
WITH
req_keys AS (
  SELECT ARRAY['sin_foto','detalle_disponible','detalle_motivo','periodo','cabecera',
               'cascada','socios','participacion','gastos','incidencias','movimientos',
               'matriz_por_socio','gastos_sin_incidencia','retribucion_operativo']::text[] AS k
),
arr_secs AS (
  SELECT ARRAY['cascada','socios','participacion','gastos','incidencias','movimientos',
               'matriz_por_socio','gastos_sin_incidencia']::text[] AS s
),
vig AS (
  SELECT lp.id_liquidacion, lp.periodo
  FROM liquidaciones_periodo lp
  WHERE NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s
                    WHERE s.id_liquidacion_supersede = lp.id_liquidacion)
),
r AS (SELECT v.id_liquidacion, v.periodo, cuenta_corriente_historico(v.periodo) AS j FROM vig v),
x AS (
  SELECT id_liquidacion, periodo,
    (j->>'sin_foto')::boolean               AS sin_foto,
    (j->>'detalle_disponible')::boolean     AS disp,
    j->>'detalle_motivo'                     AS motivo,
    (j#>>'{cabecera,id_liquidacion}')::bigint AS cab_id,
    jsonb_array_length(j->'cascada')         AS n_casc,
    jsonb_array_length(j->'socios')          AS n_soc,
    jsonb_array_length(j->'movimientos')     AS n_mov,
    jsonb_array_length(j->'participacion')   AS n_part,
    jsonb_array_length(j->'gastos')          AS n_gas,
    jsonb_array_length(j->'incidencias')     AS n_inc,
    jsonb_array_length(j->'matriz_por_socio')AS n_mat,
    jsonb_array_length(j->'gastos_sin_incidencia') AS n_gsi,
    (j ?& (SELECT k FROM req_keys))          AS keys_ok,
    (SELECT bool_and(jsonb_typeof(j->sec) = 'array')
       FROM unnest((SELECT s FROM arr_secs)) AS sec) AS arrays_ok,
    (j ? 'retribucion_operativo' AND jsonb_typeof(j->'retribucion_operativo') = 'object') AS retrib_ok,
    (j ? 'movimientos' AND jsonb_typeof(j->'movimientos') = 'array')                       AS mov_ok
  FROM r
)
SELECT
  periodo,
  id_liquidacion AS id_vigente,
  (CASE WHEN n_part = 0 THEN 'PRE_EXTENSION' ELSE 'CON_DETALLE' END) AS clase,
  disp   AS detalle_disponible,
  motivo AS detalle_motivo,
  keys_ok, arrays_ok, retrib_ok, mov_ok,
  (CASE WHEN n_part = 0
        THEN (n_gas = 0 AND n_inc = 0 AND n_mat = 0 AND n_gsi = 0)   -- pre-ext: 5 vacias
        ELSE (n_part > 0 AND n_mat > 0) END) AS secciones_ok,
  (CASE
     WHEN NOT keys_ok   THEN 'REVISAR (faltan claves top-level)'
     WHEN NOT arrays_ok THEN 'REVISAR (alguna seccion no es array)'
     WHEN NOT mov_ok    THEN 'REVISAR (movimientos ausente/no-array)'
     WHEN NOT retrib_ok THEN 'REVISAR (retribucion_operativo ausente/no-objeto)'
     WHEN sin_foto      THEN 'REVISAR (sin_foto en una vigente?)'
     WHEN cab_id IS DISTINCT FROM id_liquidacion THEN 'REVISAR (cabecera<>vigente)'
     WHEN n_casc <> 8 OR n_soc = 0 THEN 'REVISAR (cascada<>8 o socios vacio)'
     WHEN n_part = 0 THEN
       CASE WHEN disp = false AND motivo = 'foto_pre_extension'
                 AND n_gas = 0 AND n_inc = 0 AND n_mat = 0 AND n_gsi = 0
            THEN 'OK' ELSE 'REVISAR (detalle fino no vacio o flags mal)' END
     ELSE
       CASE WHEN disp = true AND motivo IS NULL AND n_part > 0 AND n_mat > 0
            THEN 'OK' ELSE 'REVISAR (detalle incompleto)' END
   END) AS estado
FROM x
ORDER BY periodo;
