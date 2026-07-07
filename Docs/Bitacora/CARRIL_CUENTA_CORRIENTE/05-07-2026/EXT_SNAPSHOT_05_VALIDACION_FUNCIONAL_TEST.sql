-- ============================================================================
-- EXT_SNAPSHOT_05_VALIDACION_FUNCIONAL_TEST.sql   (Run 5/6  --  ESCRIBE en TEST)
-- Re-snapshotea un mes con foto vigente usando la funcion extendida y valida
-- que el detalle congelado (T1/T2/T3) coincide con las funciones vivas.
-- TEST-only (gate). NO borra gastos. Mes objetivo: cambiar DATE '2026-07-01' si hace falta.
-- Correr con NADA seleccionado. El ultimo SELECT es el veredicto.
-- ============================================================================
DO $gate$ BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave='ambiente') IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE TEST-only: ambiente actual = %', COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(sin clave)');
  END IF;
END $gate$;

DROP TABLE IF EXISTS _ext_val;
CREATE TEMP TABLE _ext_val (mes date, id_previo bigint, id_nuevo bigint) ON COMMIT PRESERVE ROWS;
INSERT INTO _ext_val (mes, id_previo) VALUES (DATE '2026-07-01', liquidacion_vigente(DATE '2026-07-01'));
UPDATE _ext_val SET id_nuevo = registrar_snapshot_periodo(
         mes, pct_operativo_vigente(), 'validacion_ext', id_previo, 'validacion extension detalle fino')
 WHERE mes = DATE '2026-07-01';

-- ---------------- VEREDICTO ----------------
SELECT * FROM (
  SELECT 1 AS n, 'T1_count == cabanas'::text AS chk,
    CASE WHEN (SELECT count(*) FROM liquidacion_participacion WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val))
            = (SELECT count(*) FROM cabanas) THEN 'PASS' ELSE 'FAIL' END AS res
  UNION ALL
  SELECT 2, 'T1 == detalle_participacion (fila a fila)',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM (SELECT id_cabana,valor_relativo,id_socio_beneficiario,participa
                     FROM liquidacion_participacion WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val)) f
      FULL JOIN (SELECT id_cabana,valor_relativo,id_socio AS id_socio_beneficiario,participa
                 FROM detalle_participacion((SELECT mes FROM _ext_val))) v USING (id_cabana)
      WHERE f.valor_relativo IS DISTINCT FROM v.valor_relativo
         OR f.id_socio_beneficiario IS DISTINCT FROM v.id_socio_beneficiario
         OR f.participa IS DISTINCT FROM v.participa
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 3, 'T2_count == gastos del mes',
    CASE WHEN (SELECT count(*) FROM liquidacion_gasto WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val))
            = (SELECT count(*) FROM gastos_internos WHERE periodo=(SELECT mes FROM _ext_val)) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 4, 'T2 columnas == gastos_internos (fila a fila)',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM (SELECT id_gasto,fecha,clase,clase_sugerida,etiqueta,monto,moneda,id_zona,id_cabana,
                            pagador_tipo,id_socio_pagador,medio_pago,comentario,comprobante_url,creado_por,created_at
                     FROM liquidacion_gasto WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val)) f
      FULL JOIN (SELECT id_gasto,fecha,clase,clase_sugerida,etiqueta,monto::numeric(14,2) AS monto,moneda,id_zona,id_cabana,
                        pagador_tipo,id_socio_pagador,medio_pago,comentario,comprobante_url,creado_por,created_at
                 FROM gastos_internos WHERE periodo=(SELECT mes FROM _ext_val)) g USING (id_gasto)
      WHERE f.fecha IS DISTINCT FROM g.fecha OR f.clase IS DISTINCT FROM g.clase
         OR f.clase_sugerida IS DISTINCT FROM g.clase_sugerida OR f.etiqueta IS DISTINCT FROM g.etiqueta
         OR f.monto IS DISTINCT FROM g.monto OR f.moneda IS DISTINCT FROM g.moneda
         OR f.id_zona IS DISTINCT FROM g.id_zona OR f.id_cabana IS DISTINCT FROM g.id_cabana
         OR f.pagador_tipo IS DISTINCT FROM g.pagador_tipo OR f.id_socio_pagador IS DISTINCT FROM g.id_socio_pagador
         OR f.medio_pago IS DISTINCT FROM g.medio_pago OR f.comentario IS DISTINCT FROM g.comentario
         OR f.comprobante_url IS DISTINCT FROM g.comprobante_url OR f.creado_por IS DISTINCT FROM g.creado_por
         OR f.created_at IS DISTINCT FROM g.created_at
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 5, 'sin_incidencia(T2) == gastos_sin_incidencia_periodo',
    CASE WHEN (SELECT count(*) FROM (
         SELECT id_gasto FROM liquidacion_gasto
          WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val) AND sin_incidencia
         EXCEPT SELECT id_gasto FROM gastos_sin_incidencia_periodo((SELECT mes FROM _ext_val))) a) = 0
     AND (SELECT count(*) FROM (
         SELECT id_gasto FROM gastos_sin_incidencia_periodo((SELECT mes FROM _ext_val))
         EXCEPT SELECT id_gasto FROM liquidacion_gasto
          WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val) AND sin_incidencia) b) = 0
    THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 6, 'motivo_sin_incidencia(T2) == motivo vivo',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM liquidacion_gasto lg
      JOIN gastos_sin_incidencia_periodo((SELECT mes FROM _ext_val)) s ON s.id_gasto=lg.id_gasto
      WHERE lg.id_liquidacion=(SELECT id_nuevo FROM _ext_val)
        AND lg.motivo_sin_incidencia IS DISTINCT FROM s.motivo
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 7, 'sin_incidencia(T2)==true  <=>  0 filas en T3',
    CASE WHEN (SELECT count(*) FROM (
         SELECT id_gasto FROM liquidacion_gasto
          WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val) AND sin_incidencia
         EXCEPT
         SELECT g.id_gasto FROM liquidacion_gasto g
          WHERE g.id_liquidacion=(SELECT id_nuevo FROM _ext_val)
            AND NOT EXISTS (SELECT 1 FROM liquidacion_incidencia i
                            WHERE i.id_liquidacion=g.id_liquidacion AND i.id_gasto=g.id_gasto)) x) = 0
     AND (SELECT count(*) FROM (
         SELECT g.id_gasto FROM liquidacion_gasto g
          WHERE g.id_liquidacion=(SELECT id_nuevo FROM _ext_val)
            AND NOT EXISTS (SELECT 1 FROM liquidacion_incidencia i
                            WHERE i.id_liquidacion=g.id_liquidacion AND i.id_gasto=g.id_gasto)
         EXCEPT
         SELECT id_gasto FROM liquidacion_gasto
          WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val) AND sin_incidencia) y) = 0
    THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 8, 'T3 == incidencia_gasto por gasto (destino,socio,monto,regla)',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM (
        SELECT id_gasto,destino,id_socio,monto_incidido,regla
        FROM liquidacion_incidencia WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val)) f
      FULL JOIN (
        SELECT g.id_gasto, i.destino, i.id_socio, i.monto AS monto_incidido, i.regla
        FROM gastos_internos g CROSS JOIN LATERAL incidencia_gasto(g.id_gasto) i
        WHERE g.periodo=(SELECT mes FROM _ext_val)) v
      ON f.id_gasto=v.id_gasto AND f.destino=v.destino
         AND f.id_socio IS NOT DISTINCT FROM v.id_socio
      WHERE f.monto_incidido IS DISTINCT FROM v.monto_incidido
         OR f.regla IS DISTINCT FROM v.regla
         OR (f.id_gasto IS NULL) <> (v.id_gasto IS NULL)
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 9, 'matriz por socio DERIVADA de T1 == matriz_participacion',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM (
        SELECT id_socio_beneficiario AS id_socio,
               SUM(valor_relativo) AS valor_socio,
               SUM(valor_relativo)/NULLIF((SELECT SUM(valor_relativo) FROM liquidacion_participacion
                     WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val) AND participa),0) AS participacion
        FROM liquidacion_participacion
        WHERE id_liquidacion=(SELECT id_nuevo FROM _ext_val) AND participa
        GROUP BY id_socio_beneficiario) d
      FULL JOIN (SELECT id_socio, valor_socio, participacion
                 FROM matriz_participacion((SELECT mes FROM _ext_val))) v USING (id_socio)
      WHERE d.valor_socio IS DISTINCT FROM v.valor_socio
         OR round(d.participacion,10) IS DISTINCT FROM round(v.participacion,10)
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 10, 'foto PREVIA (superseded) sin detalle (pre-extension tolerada)',
    CASE WHEN (SELECT count(*) FROM liquidacion_participacion WHERE id_liquidacion=(SELECT id_previo FROM _ext_val))=0
          AND (SELECT count(*) FROM liquidacion_gasto        WHERE id_liquidacion=(SELECT id_previo FROM _ext_val))=0
          AND (SELECT count(*) FROM liquidacion_incidencia   WHERE id_liquidacion=(SELECT id_previo FROM _ext_val))=0
    THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 11, 'supersesion: id_nuevo es vigente y != id_previo',
    CASE WHEN (SELECT id_nuevo FROM _ext_val) = liquidacion_vigente((SELECT mes FROM _ext_val))
          AND (SELECT id_nuevo FROM _ext_val) <> (SELECT id_previo FROM _ext_val)
    THEN 'PASS' ELSE 'FAIL' END
) q ORDER BY n;
