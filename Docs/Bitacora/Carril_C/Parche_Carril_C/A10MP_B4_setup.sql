-- ============================================================================
-- VITA DELTA · CARRIL C · A10-MP · BLOQUE 4 — SETUP DE FIXTURES (TEST-only)
-- Crea reservas con saldo para los smokes de cobranza multi-porcion. Self-cleaning,
-- anti-OPS por configuracion_general('ambiente'). NO toca canonico, NO toca OPS.
--
-- saldo_real = monto_total - SUM(sena+saldo confirmados) (logica A12 / D-C-49). Cada
-- fixture: monto_total = saldo + 30000, con UNA sena confirmada de 30000 -> saldo_real = saldo.
-- MARCADORES de teardown: reservas/sena con source_event 'seed_a10mp_%'; los pagos de cobro
-- de los smokes con 'portal_test_a10mp_res%'; el huesped fixture id 9910000.
--
-- RESERVAS (id : saldo): DIRECTO 9910001..9910016 ; GATEWAY 9910051..9910055.
--
-- EXCEPCION TEST-ONLY CONTROLADA: este setup INSERTA reservas en estado 'confirmada'
--   directamente (no via crear_prereserva+confirmar_reserva), para fabricar fixtures de
--   cobranza con saldo. Esta protegido por el gate anti-OPS (ambiente='test' + cabanas 1-5):
--   NO corre en OPS, NO toca el canonico. Las fechas se ESCALONAN para no violar el EXCLUDE
--   USING gist de reservas (id_cabana =, daterange(checkin,checkout,'[)') &&) WHERE estado IN
--   ('confirmada','activa'): cada fixture toma un rango unico [base+3k, base+3k+2) (paso 3,
--   estadia 2 -> 1 dia de gap), en anio lejano (2030) para no colisionar con reservas reales.
-- COMO CORRER: SQL Editor de TEST, NADA seleccionado (L-8A-01), todo el archivo.
-- ============================================================================
BEGIN;

-- 1) GATE anti-OPS (ambiente='test' es la verdad; cabanas 1-5 sanity).
DO $gate$
DECLARE v_amb text; v_cab int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE A10-MP setup: ambiente=% (esperado test). Abortado para no tocar OPS.', COALESCE(v_amb,'<ausente>');
  END IF;
  SELECT count(*) INTO v_cab FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
  WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  IF v_cab <> 5 THEN RAISE EXCEPTION 'GATE A10-MP setup: identidad cabanas % de 5. DB inesperada.', v_cab; END IF;
END $gate$;

-- 2) SELF-CLEAN previo (FK-safe: cobros -> sena -> reservas -> huesped).
DELETE FROM pagos    WHERE source_event LIKE 'portal_test_a10mp_res%';
DELETE FROM pagos    WHERE source_event LIKE 'seed_a10mp_%';
DELETE FROM reservas WHERE source_event LIKE 'seed_a10mp_%';
DELETE FROM huespedes WHERE id_huesped = 9910000;

-- 3) Huesped fixture.
INSERT INTO huespedes (id_huesped, nombre, apellido, email, created_at, updated_at)
VALUES (9910000, 'Seed', 'A10MP', 'seed_a10mp@vitadelta.test', NOW(), NOW());

-- 4) Reservas. Fechas ESCALONADAS y no solapadas (ver header): cada fixture toma
--    [base+rn*3, base+rn*3+2) con base=2030-08-01. Cabana ciclica 1..5 (irrelevante para el
--    solapamiento: ningun par comparte fechas). rn = orden por id_reserva, 0-based.
WITH fix(id_reserva, saldo) AS (VALUES
  (9910001::bigint, 60000::numeric), (9910002, 100000), (9910003, 100000), (9910004, 100000),
  (9910005, 100000), (9910006, 100000), (9910007, 100000), (9910008, 100000),
  (9910009, 100000), (9910010, 100000), (9910011, 100000), (9910012, 100000),
  (9910013, 100000), (9910014, 100000), (9910015, 100000), (9910016, 70000),
  (9910051, 100000), (9910052, 100000), (9910053, 70000), (9910054, 100000), (9910055, 100000)
),
ordered AS (
  SELECT id_reserva, saldo, (ROW_NUMBER() OVER (ORDER BY id_reserva) - 1)::int AS rn FROM fix
)
INSERT INTO reservas (id_reserva, id_cabana, id_huesped, fecha_checkin, fecha_checkout,
  hora_checkin, hora_checkout, personas, estado, canal_origen, monto_total, monto_sena, monto_saldo, source_event)
SELECT o.id_reserva, 1 + (o.id_reserva % 5), 9910000,
  (DATE '2030-08-01' + (o.rn * 3)),
  (DATE '2030-08-01' + (o.rn * 3) + 2),
  TIME '14:00', TIME '10:00', 2, 'confirmada', 'manual', o.saldo + 30000, 30000, o.saldo,
  'seed_a10mp_' || o.id_reserva
FROM ordered o;

-- 5) Sena confirmada por reserva (30000) -> saldo_real = saldo objetivo.
WITH fix(id_reserva) AS (VALUES
  (9910001::bigint),(9910002),(9910003),(9910004),(9910005),(9910006),(9910007),(9910008),
  (9910009),(9910010),(9910011),(9910012),(9910013),(9910014),(9910015),(9910016),
  (9910051),(9910052),(9910053),(9910054),(9910055)
)
INSERT INTO pagos (id_reserva, tipo, medio_pago, monto_esperado, monto_recibido, moneda, estado, validado_por, source_event)
SELECT f.id_reserva, 'sena', 'efectivo', 30000, 30000, 'ARS', 'confirmado', 'seed_a10mp', 'seed_a10mp_sena_' || f.id_reserva
FROM fix f;

-- 6) Veredicto.
SELECT jsonb_build_object(
  'reservas_creadas', (SELECT count(*) FROM reservas WHERE source_event LIKE 'seed_a10mp_%'),
  'senas_creadas',    (SELECT count(*) FROM pagos WHERE source_event LIKE 'seed_a10mp_sena_%'),
  'saldo_9910001',    (SELECT monto_total - 30000 FROM reservas WHERE id_reserva=9910001),
  'saldo_9910016',    (SELECT monto_total - 30000 FROM reservas WHERE id_reserva=9910016)
) AS detalle,
CASE WHEN (SELECT count(*) FROM reservas WHERE source_event LIKE 'seed_a10mp_%')=21 THEN 'PASS' ELSE 'FAIL' END AS veredicto;

COMMIT;
