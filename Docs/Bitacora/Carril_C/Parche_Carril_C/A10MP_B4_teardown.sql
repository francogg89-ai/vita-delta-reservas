-- ============================================================================
-- VITA DELTA · CARRIL C · A10-MP · BLOQUE 4 — TEARDOWN SMOKE (TEST-only)
-- Borra fixtures + pagos de cobro de los smokes. FK-safe, anti-OPS, idempotente.
-- NO toca canonico, NO toca OPS, NO toca datos reales.
-- MARCADORES: cobros 'portal_test_a10mp_res%'; sena/reservas 'seed_a10mp_%'; huesped 9910000.
-- ORDEN FK-SAFE: pagos (cobro + sena) -> reservas -> huesped. pagos.id_reserva es ON DELETE
--   SET NULL, pero igual borramos pagos primero para limpieza total. reservas.id_huesped es
--   RESTRICT -> el huesped se borra al final.
-- COMO CORRER: SQL Editor de TEST, NADA seleccionado, todo el archivo.
-- ============================================================================
BEGIN;

DO $gate$
DECLARE v_amb text; v_cab int; v_cobros bigint; v_seed bigint;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE A10-MP teardown: ambiente=% (esperado test). Abortado para no tocar OPS.', COALESCE(v_amb,'<ausente>');
  END IF;
  SELECT count(*) INTO v_cab FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
  WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  IF v_cab <> 5 THEN RAISE EXCEPTION 'GATE A10-MP teardown: identidad cabanas % de 5.', v_cab; END IF;
  SELECT count(*) INTO v_cobros FROM pagos WHERE source_event LIKE 'portal_test_a10mp_res%';
  SELECT count(*) INTO v_seed   FROM reservas WHERE source_event LIKE 'seed_a10mp_%';
  RAISE NOTICE 'A10-MP teardown: a borrar -> cobros=%, reservas_seed=%', v_cobros, v_seed;
END $gate$;

DELETE FROM pagos    WHERE source_event LIKE 'portal_test_a10mp_res%';
DELETE FROM pagos    WHERE source_event LIKE 'seed_a10mp_%';
DELETE FROM reservas WHERE source_event LIKE 'seed_a10mp_%';
DELETE FROM huespedes WHERE id_huesped = 9910000;

SELECT jsonb_build_object(
  'cobros_restantes',   (SELECT count(*) FROM pagos WHERE source_event LIKE 'portal_test_a10mp_res%'),
  'seed_restante',      (SELECT count(*) FROM reservas WHERE source_event LIKE 'seed_a10mp_%'),
  'huesped_restante',   (SELECT count(*) FROM huespedes WHERE id_huesped=9910000)
) AS detalle,
CASE WHEN (SELECT count(*) FROM pagos WHERE source_event LIKE 'portal_test_a10mp_res%')=0
      AND (SELECT count(*) FROM reservas WHERE source_event LIKE 'seed_a10mp_%')=0
     THEN 'PASS' ELSE 'FAIL' END AS veredicto;

COMMIT;
