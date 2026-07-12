-- ============================================================================
-- B3_ROLLBACK -- Reversion de B3 (solo funciones)
-- TEST-only, gated, idempotente. Dropea las 13 funciones del motor.
-- NO toca estructura (B2A), grilla (B2B), reservas, gateway ni OPS.
-- Las cotizaciones congeladas persisten (son datos); borrarlas es opcional.
-- ============================================================================
BEGIN;

DO $gate$
DECLARE v_amb TEXT; v_esperado TEXT := 'test';
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'ROLLBACK B3 abortado: ambiente=% (esperado %). TEST-only.', v_amb, v_esperado;
  END IF;
END
$gate$;

DROP FUNCTION IF EXISTS precios_cotizacion_obtener(UUID);
DROP FUNCTION IF EXISTS precios_cotizar_congelar(JSONB);
DROP FUNCTION IF EXISTS precios_cotizar(JSONB);
DROP FUNCTION IF EXISTS precios_disponibilidad_noches(BIGINT, DATE, DATE);
DROP FUNCTION IF EXISTS precios_extra_persona(TEXT, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS precios_eventos_interseccion(TEXT, DATE, DATE);
DROP FUNCTION IF EXISTS precios_precio_noche(TEXT, DATE, TEXT, TEXT);
DROP FUNCTION IF EXISTS precios_asignar_ordinales(DATE, DATE, DATE[]);
DROP FUNCTION IF EXISTS precios_clasificar_noche(DATE);
DROP FUNCTION IF EXISTS precios_resolver_temporada(DATE);
DROP FUNCTION IF EXISTS precios_money(NUMERIC);
DROP FUNCTION IF EXISTS precios_redondear(NUMERIC, NUMERIC);
DROP FUNCTION IF EXISTS precios_config(TEXT);

COMMIT;
