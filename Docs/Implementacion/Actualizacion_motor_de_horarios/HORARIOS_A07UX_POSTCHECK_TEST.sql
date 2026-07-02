-- =====================================================================
-- HORARIOS_A07UX_POSTCHECK_TEST.sql
-- Mini-bloque UX A07. Verificacion final (read-only). SOLO TEST.
-- Correr COMPLETO (nada seleccionado) despues del TEARDOWN.
-- Salida esperada: estado='POSTCHECK_OK' con las 3 columnas en 0.
--   overrides_smoke   : el fixture ya no existe (motivo='smoke_a07_ovr_e2268a33').
--   prereservas_smoke : el HARD corta antes del INSERT (source_event A07 derivado).
--   huespedes_smoke   : el HARD corta antes de upsert_huesped (nombre 'SMOKE_A07_OVR').
-- =====================================================================
SELECT CASE WHEN (a = 0 AND b = 0 AND c = 0) THEN 'POSTCHECK_OK' ELSE 'POSTCHECK_FAIL' END AS estado,
       a AS overrides_smoke,
       b AS prereservas_smoke,
       c AS huespedes_smoke
FROM (
  SELECT
    (SELECT count(*) FROM overrides_operativos
       WHERE motivo = 'smoke_a07_ovr_e2268a33')                                               AS a,
    (SELECT count(*) FROM pre_reservas
       WHERE source_event LIKE 'portal\_test\_a07\_%\_2027-06-15\_2027-06-17\_%' ESCAPE '\') AS b,
    (SELECT count(*) FROM huespedes
       WHERE nombre = 'SMOKE_A07_OVR')                                          AS c
) x;
