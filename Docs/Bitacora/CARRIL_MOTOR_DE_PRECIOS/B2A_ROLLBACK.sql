-- ============================================================================
-- B2A_ROLLBACK -- Reversion limpia de B2A (aditivo)
-- ----------------------------------------------------------------------------
-- TEST-only, gated, idempotente. SEGURO solo ANTES de poblar datos de pricing
-- y antes de que existan FKs poblados (es decir, inmediatamente post-B2A,
-- pre-B2B). Revierte tablas nuevas, columnas aditivas, config keys, trigger
-- y el indice correctivo. NO toca funciones de motor ni datos legacy.
-- ============================================================================

BEGIN;

DO $gate$
DECLARE v_amb TEXT; v_esperado TEXT := 'test';
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'ROLLBACK B2A abortado: ambiente=% (esperado %). TEST-only.', v_amb, v_esperado;
  END IF;
END
$gate$;

-- 1) Columnas aditivas que referencian tablas nuevas (drop de columna = drop de su FK/CHECK)
ALTER TABLE reservas     DROP COLUMN IF EXISTS cotizacion_id;
ALTER TABLE reservas     DROP COLUMN IF EXISTS capacidad_override;
ALTER TABLE reservas     DROP COLUMN IF EXISTS precio_snapshot;
ALTER TABLE reservas     DROP COLUMN IF EXISTS precio_motivo;
ALTER TABLE reservas     DROP COLUMN IF EXISTS precio_source;
ALTER TABLE pre_reservas DROP COLUMN IF EXISTS cotizacion_id;
ALTER TABLE cabanas      DROP COLUMN IF EXISTS perfil_tarifario;

-- 2) Tablas nuevas (orden por dependencia: perfiles_tarifarios ultima)
DROP TABLE IF EXISTS cotizaciones_precio;
DROP TABLE IF EXISTS precios_auditoria;        -- drop de tabla elimina su trigger
DROP TABLE IF EXISTS temporada_vigencia;
DROP TABLE IF EXISTS noches_alta_demanda;
DROP TABLE IF EXISTS tarifas_motor;
DROP TABLE IF EXISTS overrides_precio;
DROP TABLE IF EXISTS perfiles_tarifarios;

-- 3) Funcion de auditoria propia
DROP FUNCTION IF EXISTS trg_precios_inmutable();

-- 4) Indice correctivo (benigno; se remueve para revertir por completo)
DROP INDEX IF EXISTS idx_paquetes_evento_id_evento;

-- 5) Config keys de pricing
DELETE FROM configuracion_general WHERE clave LIKE 'precio_%';

COMMIT;
