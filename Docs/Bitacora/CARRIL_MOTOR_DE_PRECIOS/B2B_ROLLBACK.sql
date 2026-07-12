-- ============================================================================
-- B2B_ROLLBACK -- Reversion del seed B2B (solo datos)
-- ----------------------------------------------------------------------------
-- TEST-only, gated, idempotente. QUIRURGICO: borra unicamente las filas
-- sembradas por B2B, identificadas por source_event='b2b:seed_inicial'.
-- NO toca estructura (el fingerprint B2A queda intacto).
-- NO toca reservas, pre_reservas, funciones, gateway ni OPS.
--
-- SEGURO solo mientras no existan cotizaciones/reservas apoyadas en estas
-- tarifas. Si el portal ya versiono precios (filas con otro source_event),
-- esas NO se tocan: este rollback revierte el seed, no la grilla completa.
-- ============================================================================

BEGIN;

DO $gate$
DECLARE v_amb TEXT; v_esperado TEXT := 'test';
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'ROLLBACK B2B abortado: ambiente=% (esperado %). TEST-only.', v_amb, v_esperado;
  END IF;
END
$gate$;

-- 1) Tarifas sembradas por B2B (identificadas por source_event; no toca otras versiones)
DELETE FROM tarifas_motor
WHERE source_event = 'b2b:seed_inicial'
  AND created_by   = 'seed_b2b';

-- 2) Temporadas sembradas por B2B (las 8 filas de la cobertura 2026-2030)
DELETE FROM temporada_vigencia
WHERE (temporada_clave, anio) IN (
  ('baja',2026),('alta',2026),('baja',2027),('alta',2027),
  ('baja',2028),('alta',2028),('baja',2029),('alta',2029)
);

COMMIT;
