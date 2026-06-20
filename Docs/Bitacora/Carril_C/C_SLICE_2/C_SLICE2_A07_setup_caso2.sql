-- ============================================================================
-- C_SLICE2_A07 — SETUP CASO 2 (RETRY PARCIAL). Correr en TEST DESPUES del gate
-- residual (Bloque 2 = 0) y ANTES del smoke funcional (Bloque 3).
--
-- Crea un estado PARCIAL real del fixture PARCIAL: prereserva ACTIVA + seña
-- CONFIRMADA con el idem/source_event determinístico, pero SIN confirmar la
-- reserva. Asi, cuando el wrapper reciba el sobre PARCIAL, debe RESUMIR:
--   PG-0 no encuentra reserva -> PG-1 crear_prereserva idempotent (prereserva
--   existe) -> PG-2 reusa la seña (n=1, n_conf=1) -> PG-3 confirma -> reserva.
-- Resultado esperado del POST PARCIAL: ok:true, data.idempotent_match:false,
-- SIN duplicar la seña (COUNT pagos seña = 1).
--
-- ESCRIBE (prereserva + seña). Cubierto por el namespace portal_test_a07_% y el
-- teardown FK-safe (Bloque 5).
-- ============================================================================
DO $$
DECLARE
  v_idem TEXT := 'portal_test_a07_2_2027-04-05_2027-04-07_2c7b4d4c511af40434f803e5884d1fc7abd8d1678d96af630c9879385e19686e_c842a0a7e4d3';
  v_pre  JSONB;
  v_pago JSONB;
  v_id_pre BIGINT;
  v_amb  TEXT;
BEGIN
  -- Guard anti-OPS: abortar (rollback total) si este NO es el entorno TEST.
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'ABORT anti-OPS: configuracion_general.ambiente=% (esperado ''test''). Ninguna escritura ejecutada.', COALESCE(v_amb, '<null>');
  END IF;

  v_pre := crear_prereserva(jsonb_build_object(
    'id_cabana', 2, 'fecha_in', '2027-04-05', 'fecha_out', '2027-04-07', 'personas', 2,
    'canal_origen', 'manual', 'canal_pago_esperado', 'transferencia_mp',
    'monto_total', 120000, 'monto_sena', 60000,
    'source_event', v_idem, 'idempotency_key', v_idem,
    'huesped', jsonb_build_object('nombre', 'PORTAL TEST A07 PARCIAL', 'telefono', '+5490000000702')
  ));
  IF NOT (v_pre->>'ok')::boolean THEN
    RAISE EXCEPTION 'setup caso2: crear_prereserva fallo: %', v_pre;
  END IF;
  v_id_pre := (v_pre->>'id_pre_reserva')::bigint;

  v_pago := registrar_pago(jsonb_build_object(
    'id_pre_reserva', v_id_pre, 'tipo', 'sena', 'medio_pago', 'transferencia_mp',
    'monto_esperado', 60000, 'monto_recibido', 60000, 'estado_inicial', 'confirmado',
    'validado_por', 'vicky', 'source_event', v_idem
  ));
  IF (v_pago->>'estado') <> 'confirmado' THEN
    RAISE EXCEPTION 'setup caso2: registrar_pago no quedo confirmado: %', v_pago;
  END IF;

  RAISE NOTICE 'Setup Caso 2 OK: id_pre=% (prereserva activa + seña confirmada, sin reserva)', v_id_pre;
END $$;

-- Verificacion del setup (esperado: prereserva_activa=1, sena_confirmada=1, reservas=0).
WITH k AS (SELECT 'portal_test_a07_2_2027-04-05_2027-04-07_2c7b4d4c511af40434f803e5884d1fc7abd8d1678d96af630c9879385e19686e_c842a0a7e4d3'::text AS idem)
SELECT 'prereserva_activa' AS chk, count(*) AS n
  FROM pre_reservas, k WHERE idempotency_key = k.idem AND estado IN ('pendiente_pago','pago_en_revision')
UNION ALL
SELECT 'sena_confirmada', count(*)
  FROM pagos, k WHERE source_event = k.idem AND tipo='sena' AND estado='confirmado'
UNION ALL
SELECT 'reservas', count(*)
  FROM reservas, k WHERE source_event = k.idem;
