-- ============================================================================
-- EXT_SNAPSHOT_02_TRIGGERS_OPS.sql   (Run 2/6  --  ESCRIBE DDL, transaccional)
-- 6 triggers de inmutabilidad (3 tablas x 2) reusando trg_9h_inmutable().
-- OPS-only (gate). Si el gate falla, ROLLBACK.
-- PROMOCION ESTRUCTURAL OPS: DDL-only, sin datos, 0 nextval. El primer cierre
-- real (congelar un mes con detalle) es un write controlado POSTERIOR, fuera de aca.
-- ============================================================================
BEGIN;
DO $gate$ BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave='ambiente') IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE OPS-only: ambiente actual = %', COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(sin clave)');
  END IF;
END $gate$;

DO $mk$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['liquidacion_participacion','liquidacion_gasto','liquidacion_incidencia'] LOOP
    EXECUTE format('CREATE TRIGGER trg_%s_no_upd_del BEFORE UPDATE OR DELETE ON %I '
                   'FOR EACH ROW EXECUTE FUNCTION trg_9h_inmutable()', t, t);
    EXECUTE format('CREATE TRIGGER trg_%s_no_truncate BEFORE TRUNCATE ON %I '
                   'FOR EACH STATEMENT EXECUTE FUNCTION trg_9h_inmutable()', t, t);
  END LOOP;
END $mk$;
COMMIT;
