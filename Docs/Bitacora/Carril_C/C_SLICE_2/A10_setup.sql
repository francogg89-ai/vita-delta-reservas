-- ============================================================================
-- C_SLICE2 / A10 -- SETUP de fixtures (TEST ONLY). Guard anti-OPS + SELF-CLEANING + INSERTs.
-- IDEMPOTENTE: al inicio limpia el namespace 'portal_test_a10_%' (orden FK-safe, igual que
-- teardown) y recien despues inserta. Re-correrlo NO duplica senas (pagos.source_event no es UNIQUE).
-- NOTA: INSERT directo de fixtures (no via el motor). Ids explicitos 9900000+ para que los smokes
-- los referencien de forma deterministica. Fechas 2099 (sinteticas, sin overlap operativo).
-- saldo_real = monto_total - SUM(pagos confirmados sena+saldo). Cada reserva trae su sena confirmada.
-- ============================================================================
DO $a10_setup$
DECLARE
  v_amb TEXT;
BEGIN
  -- ---- GUARD ANTI-OPS (obligatorio) ----
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ANTI-OPS: ambiente=% (se esperaba test). SETUP A10 abortado.', v_amb;
  END IF;

  -- ---- SELF-CLEANING (idempotente): borrar residual del namespace en orden FK-safe ----
  DELETE FROM log_cambios WHERE source_event LIKE 'portal_test_a10_%';
  DELETE FROM pagos       WHERE source_event LIKE 'portal_test_a10_%';
  DELETE FROM reservas    WHERE source_event LIKE 'portal_test_a10_%';
  DELETE FROM huespedes   WHERE nombre LIKE 'PORTAL TEST A10%';

  -- ---- Huesped centinela ----
  INSERT INTO huespedes (id_huesped, nombre, apellido, telefono, notas_internas)
  VALUES (9900000, 'PORTAL TEST A10', 'Centinela', '+540000000000', 'fixture A10 - borrar con teardown');

  -- ---- Reservas fixture (id_cabana 1..5 existen en TEST) ----
  INSERT INTO reservas
    (id_reserva, id_cabana, id_huesped, fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
     personas, estado, canal_origen, monto_total, monto_sena, monto_saldo, source_event, mascotas)
  VALUES
    (9900001, 1, 9900000, DATE '2099-01-10', DATE '2099-01-12', TIME '14:00', TIME '10:00', 2, 'confirmada', 'manual', 100000, 30000, 70000, 'portal_test_a10_setup_res_9900001', FALSE),
    (9900002, 2, 9900000, DATE '2099-01-13', DATE '2099-01-15', TIME '14:00', TIME '10:00', 2, 'confirmada', 'manual', 100000, 30000, 70000, 'portal_test_a10_setup_res_9900002', FALSE),
    (9900003, 3, 9900000, DATE '2099-01-16', DATE '2099-01-18', TIME '14:00', TIME '10:00', 2, 'activa',     'manual', 120000, 20000, 100000,'portal_test_a10_setup_res_9900003', FALSE),
    (9900004, 4, 9900000, DATE '2099-01-19', DATE '2099-01-21', TIME '14:00', TIME '10:00', 2, 'cancelada',  'manual', 90000,  30000, 60000, 'portal_test_a10_setup_res_9900004', FALSE),
    (9900005, 5, 9900000, DATE '2099-01-22', DATE '2099-01-24', TIME '14:00', TIME '10:00', 2, 'confirmada', 'manual', 80000,  80000, 0,     'portal_test_a10_setup_res_9900005', FALSE),
    (9900006, 1, 9900000, DATE '2099-02-10', DATE '2099-02-12', TIME '14:00', TIME '10:00', 2, 'confirmada', 'manual', 100000, 30000, 70000, 'portal_test_a10_setup_res_9900006', FALSE),
    (9900007, 2, 9900000, DATE '2099-02-13', DATE '2099-02-15', TIME '14:00', TIME '10:00', 2, 'confirmada', 'manual', 100000, 10000, 90000, 'portal_test_a10_setup_res_9900007', FALSE);

  -- ---- Senas confirmadas (definen el saldo_real) ----
  INSERT INTO pagos
    (id_reserva, tipo, medio_pago, monto_esperado, monto_recibido, estado, es_automatico, validado_por, source_event)
  VALUES
    (9900001, 'sena', 'transferencia_bancaria', 30000, 30000, 'confirmado', FALSE, 'sistema_auto', 'portal_test_a10_setup_sena_9900001'),
    (9900002, 'sena', 'transferencia_bancaria', 30000, 30000, 'confirmado', FALSE, 'sistema_auto', 'portal_test_a10_setup_sena_9900002'),
    (9900003, 'sena', 'transferencia_bancaria', 20000, 20000, 'confirmado', FALSE, 'sistema_auto', 'portal_test_a10_setup_sena_9900003'),
    (9900004, 'sena', 'transferencia_bancaria', 30000, 30000, 'confirmado', FALSE, 'sistema_auto', 'portal_test_a10_setup_sena_9900004'),
    (9900005, 'sena', 'transferencia_bancaria', 80000, 80000, 'confirmado', FALSE, 'sistema_auto', 'portal_test_a10_setup_sena_9900005'),
    (9900006, 'sena', 'transferencia_bancaria', 30000, 30000, 'confirmado', FALSE, 'sistema_auto', 'portal_test_a10_setup_sena_9900006'),
    (9900007, 'sena', 'transferencia_bancaria', 10000, 10000, 'confirmado', FALSE, 'sistema_auto', 'portal_test_a10_setup_sena_9900007');

  RAISE NOTICE 'SETUP A10 OK (self-cleaning). Fixtures 9900001..9900007. saldo_real -> 9900001:70000 9900002:70000 9900003:100000(activa) 9900004:60000(cancelada) 9900005:0(saldada) 9900006:70000(retry-race) 9900007:90000(over-race)';
END
$a10_setup$;

-- Mapa de fixtures (para capturar ids en los smokes):
SELECT id_reserva, estado::text AS estado, monto_total, source_event
FROM reservas WHERE source_event LIKE 'portal_test_a10_setup_res%'
ORDER BY id_reserva;
