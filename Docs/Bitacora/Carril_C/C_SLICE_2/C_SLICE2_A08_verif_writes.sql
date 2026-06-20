-- ============================================================================
-- C_SLICE2_A08 — BLOQUE 4: VERIFICACION DE ESCRITURAS (read-only). Correr tras
-- el smoke funcional. Cada fixture se identifica por su source_event exacto
-- (determinístico). Esperado:
--   B_FELIZ    = 1  (camino feliz creo el bloqueo)
--   B_SOLAPA   = 0  (rebote bloqueo_solapado -> conflicto, no escribe)
--   B_CABANA99 = 0  (cabana_no_existe -> payload_invalido, no escribe)
--   TOTAL_NS   = 1  (el retro-POST de B_FELIZ NO duplico: sigue habiendo 1)
-- ============================================================================
SELECT 'B_FELIZ'    AS fixture, COUNT(*) AS n_bloqueos
  FROM bloqueos WHERE source_event = 'portal_test_a08_cab1_2027-09-01_2027-09-05_e94b425e607d'
UNION ALL
SELECT 'B_SOLAPA'   AS fixture, COUNT(*)
  FROM bloqueos WHERE source_event = 'portal_test_a08_cab1_2027-09-03_2027-09-07_6b376e54cabd'
UNION ALL
SELECT 'B_CABANA99' AS fixture, COUNT(*)
  FROM bloqueos WHERE source_event = 'portal_test_a08_cab99_2027-09-10_2027-09-12_e31714741c8b'
UNION ALL
SELECT 'TOTAL_NS'   AS fixture, COUNT(*)
  FROM bloqueos WHERE source_event LIKE 'portal_test_a08_%';
