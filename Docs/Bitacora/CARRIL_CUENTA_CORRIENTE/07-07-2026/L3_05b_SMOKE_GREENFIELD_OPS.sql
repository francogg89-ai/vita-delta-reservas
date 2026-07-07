-- ============================================================================
-- L3_05b_SMOKE_GREENFIELD_OPS.sql   (READ-ONLY; una sola sentencia)
-- Smoke de OPS greenfield: con 0 fotos, L3 debe devolver sin_foto / sin_datos.
-- NO escribe. WITH ... SELECT. Sin BEGIN/DO/DDL/DML. Grilla unica.
--
-- La verificacion estructural de las 2 funciones en OPS es el mismo artefacto
-- L3_02_VERIF_ESTRUCTURAL_FUNCIONES.sql (agnostico al ambiente): correrlo en OPS
-- despues del DDL. Este 5b cubre la parte especifica de greenfield.
--
-- v2: agrega el check explicito de que retribucion_operativo sale NULL (jsonb
-- null) en el caso sin_foto.
--
-- Esperado en OPS greenfield (total_fotos=0, vigentes=0):
--   * detalle de cualquier mes -> sin_foto=true, detalle_disponible=false,
--     motivo=sin_foto_vigente, cabecera=null, retribucion_operativo=null,
--     todas las secciones [].
--   * acumulados -> sin_datos=true, fotos_vigentes=0, evolucion=[], totales en 0.
-- Nota: si OPS ya NO fuera greenfield (hubo un cierre real), estas filas daran
-- REVISAR; es correcto -- el smoke asume greenfield.
-- ============================================================================
WITH
det AS (SELECT cuenta_corriente_historico(DATE '2027-01-01') AS j),
acu AS (SELECT cuenta_corriente_historico_acumulados() AS a),
filas(orden, item, esperado, actual, estado) AS (
  -- (0) sanity: realmente greenfield?
  SELECT 0, 'estado_fotos',
         'total_fotos=0 y vigentes=0 (greenfield)',
         'total_fotos=' || (SELECT count(*) FROM liquidaciones_periodo)::text ||
         ' | vigentes=' || (SELECT count(*) FROM liquidaciones_periodo lp
                            WHERE NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s
                                              WHERE s.id_liquidacion_supersede = lp.id_liquidacion))::text,
         (CASE WHEN (SELECT count(*) FROM liquidaciones_periodo) = 0 THEN 'OK' ELSE 'REVISAR (no greenfield)' END)

  -- (1) detalle sin foto
  UNION ALL
  SELECT 1, 'detalle_sin_foto (2027-01)',
         'sin_foto=true, detalle_disponible=false, motivo=sin_foto_vigente, cabecera=null',
         'sin_foto=' || ((SELECT j->>'sin_foto' FROM det)) ||
         ' | disp=' || ((SELECT j->>'detalle_disponible' FROM det)) ||
         ' | motivo=' || COALESCE((SELECT j->>'detalle_motivo' FROM det), '(null)') ||
         ' | cabecera=' || (SELECT CASE WHEN j->'cabecera' = 'null'::jsonb OR (j->'cabecera') IS NULL THEN 'null' ELSE 'no-null' END FROM det),
         (SELECT CASE WHEN (j->>'sin_foto')::boolean = true
                       AND (j->>'detalle_disponible')::boolean = false
                       AND j->>'detalle_motivo' = 'sin_foto_vigente'
                       AND (j->'cabecera' = 'null'::jsonb OR (j->'cabecera') IS NULL)
                      THEN 'OK' ELSE 'REVISAR' END FROM det)

  -- (2) detalle: retribucion_operativo NULL en sin_foto
  UNION ALL
  SELECT 2, 'detalle_retribucion_null',
         'retribucion_operativo = null (jsonb null) cuando sin_foto',
         (SELECT 'presente=' || (j ? 'retribucion_operativo')::text ||
                 ' | jsonb_typeof=' || COALESCE(jsonb_typeof(j->'retribucion_operativo'),'(clave ausente)') FROM det),
         (SELECT CASE WHEN (j ? 'retribucion_operativo')
                       AND jsonb_typeof(j->'retribucion_operativo') = 'null'
                      THEN 'OK' ELSE 'REVISAR' END FROM det)

  -- (3) detalle: todas las secciones vacias
  UNION ALL
  SELECT 3, 'detalle_secciones_vacias',
         'cascada/socios/participacion/gastos/incidencias/movimientos/matriz/gastos_sin_incidencia = []',
         (SELECT 'casc=' || jsonb_array_length(j->'cascada') || ' soc=' || jsonb_array_length(j->'socios') ||
                 ' part=' || jsonb_array_length(j->'participacion') || ' gas=' || jsonb_array_length(j->'gastos') ||
                 ' inc=' || jsonb_array_length(j->'incidencias') || ' mov=' || jsonb_array_length(j->'movimientos') ||
                 ' mat=' || jsonb_array_length(j->'matriz_por_socio') ||
                 ' gsi=' || jsonb_array_length(j->'gastos_sin_incidencia') FROM det),
         (SELECT CASE WHEN jsonb_array_length(j->'cascada') = 0 AND jsonb_array_length(j->'socios') = 0
                       AND jsonb_array_length(j->'participacion') = 0 AND jsonb_array_length(j->'gastos') = 0
                       AND jsonb_array_length(j->'incidencias') = 0 AND jsonb_array_length(j->'movimientos') = 0
                       AND jsonb_array_length(j->'matriz_por_socio') = 0 AND jsonb_array_length(j->'gastos_sin_incidencia') = 0
                      THEN 'OK' ELSE 'REVISAR' END FROM det)

  -- (4) acumulados greenfield
  UNION ALL
  SELECT 4, 'acumulados_greenfield',
         'sin_datos=true, fotos_vigentes=0, evolucion=[], utilidad=0, ingresos=0, retiros=0',
         (SELECT 'sin_datos=' || (a->>'sin_datos') ||
                 ' | fotos_vigentes=' || (a#>>'{meta,fotos_vigentes}') ||
                 ' | n_evo=' || jsonb_array_length(a->'evolucion') ||
                 ' | utilidad=' || (a#>>'{totales,utilidad_acumulada}') ||
                 ' | ingresos=' || (a#>>'{totales,ingresos_acumulados}') ||
                 ' | retiros=' || (a#>>'{totales,retiros_acumulados}') FROM acu),
         (SELECT CASE WHEN (a->>'sin_datos')::boolean = true
                       AND (a#>>'{meta,fotos_vigentes}')::int = 0
                       AND jsonb_array_length(a->'evolucion') = 0
                       AND (a#>>'{totales,utilidad_acumulada}')::numeric = 0
                       AND (a#>>'{totales,ingresos_acumulados}')::numeric = 0
                       AND (a#>>'{totales,retiros_acumulados}')::numeric = 0
                      THEN 'OK' ELSE 'REVISAR' END FROM acu)

  -- (5) acumulados: piso sin anomalias (siempre debe valer, greenfield o no)
  UNION ALL
  SELECT 5, 'acumulados_piso',
         'fotos_pre_piso=0 y movimientos_pre_piso=0',
         (SELECT 'fotos_pre_piso=' || (a#>>'{meta,fotos_pre_piso}') ||
                 ' | movimientos_pre_piso=' || (a#>>'{meta,movimientos_pre_piso}') FROM acu),
         (SELECT CASE WHEN (a#>>'{meta,fotos_pre_piso}')::int = 0
                       AND (a#>>'{meta,movimientos_pre_piso}')::int = 0
                      THEN 'OK' ELSE 'REVISAR' END FROM acu)
)
SELECT item, esperado, actual, estado
FROM filas
ORDER BY orden;
