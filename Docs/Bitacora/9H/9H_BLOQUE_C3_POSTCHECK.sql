-- ============================================================================
-- VITA DELTA · 9H · BLOQUE C.3 — POSTCHECK (read-only)
-- Correr DESPUÉS de 9H_BLOQUE_C3_SMOKES.sql. Confirma que el ROLLBACK no dejó
-- FILAS: las 5 tablas 9H quedan sin filas persistidas.
-- NOTA: las secuencias BIGSERIAL pueden haber avanzado (nextval no hace rollback).
-- Eso es por diseño, no tiene significado contable y no se resetea. Se muestran
-- como INFO, no afectan el veredicto.
-- ============================================================================
WITH conteos AS (
  SELECT 'liquidaciones_periodo' tabla, COUNT(*) filas FROM liquidaciones_periodo
  UNION ALL SELECT 'liquidacion_cascada', COUNT(*) FROM liquidacion_cascada
  UNION ALL SELECT 'liquidacion_socio',   COUNT(*) FROM liquidacion_socio
  UNION ALL SELECT 'movimientos_socio',   COUNT(*) FROM movimientos_socio
  UNION ALL SELECT 'revaluaciones',       COUNT(*) FROM revaluaciones
),
secuencias AS (
  SELECT 'liquidaciones_periodo.id_liquidacion' col, pg_sequence_last_value(pg_get_serial_sequence('public.liquidaciones_periodo','id_liquidacion')::regclass) lv
  UNION ALL SELECT 'movimientos_socio.id_movimiento', pg_sequence_last_value(pg_get_serial_sequence('public.movimientos_socio','id_movimiento')::regclass)
  UNION ALL SELECT 'revaluaciones.id_revaluacion',    pg_sequence_last_value(pg_get_serial_sequence('public.revaluaciones','id_revaluacion')::regclass)
)
SELECT '1·tabla·'||tabla AS orden, filas::text AS valor,
       CASE WHEN filas=0 THEN 'OK sin filas persistidas' ELSE 'FALLO hay filas' END estado
FROM conteos
UNION ALL
SELECT '2·seq·'||col, COALESCE(lv::text,'intacta'),
       'INFO secuencia (avance sin significado contable)'
FROM secuencias
UNION ALL
SELECT '9·VEREDICTO', (SELECT SUM(filas) FROM conteos)::text,
       CASE WHEN (SELECT SUM(filas) FROM conteos)=0
            THEN 'VERDE - C.3 no dejó filas persistidas; las secuencias pueden haber avanzado por diseño y no se resetean'
            ELSE 'ROJO - hay filas residuales' END
ORDER BY orden;
