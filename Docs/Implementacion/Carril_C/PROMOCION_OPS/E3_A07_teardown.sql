-- ============================================================================
-- E3_A07_teardown.sql
-- Cleanup de UNA reserva creada por el smoke de escritura REAL de A07 en OPS.
-- El aviso 8C-bis NO escribe en DB (solo manda mail), así que no hay nada que
-- limpiar por ese lado. Solo se borran pago(s) + reserva + pre_reserva.
--
-- USO: reemplazá <ID_RESERVA> por el id_reserva que devolvió el smoke
-- (envelope.data.id_reserva) y corré TODO el archivo en el SQL Editor de OPS.
-- Gate ambiente='ops'. Transacción atómica. Orden de borrado respeta las FK
-- (pagos primero por el RESTRICT pagos.id_prereserva -> pre_reservas).
-- ============================================================================
BEGIN;

DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'TEARDOWN A07: ambiente=% no es ops. Abortado.', COALESCE(v_amb,'<ausente>');
  END IF;
END
$gate$;

DO $teardown$
DECLARE
  v_idr bigint := <ID_RESERVA>;   -- <<< REEMPLAZAR por el id_reserva del smoke
  v_idp bigint;
  v_pagos int;
BEGIN
  IF v_idr IS NULL THEN
    RAISE EXCEPTION 'TEARDOWN A07: id_reserva no especificado.';
  END IF;

  SELECT id_pre_reserva INTO v_idp FROM reservas WHERE id_reserva = v_idr;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TEARDOWN A07: no existe reserva id=% (¿id incorrecto o ya borrada?).', v_idr;
  END IF;

  DELETE FROM pagos
   WHERE id_reserva = v_idr
      OR (v_idp IS NOT NULL AND id_prereserva = v_idp);
  GET DIAGNOSTICS v_pagos = ROW_COUNT;

  DELETE FROM reservas WHERE id_reserva = v_idr;

  IF v_idp IS NOT NULL THEN
    DELETE FROM pre_reservas WHERE id_pre_reserva = v_idp;
  END IF;

  RAISE NOTICE 'Teardown OK: reserva % borrada, pre_reserva %, % pago(s).', v_idr, v_idp, v_pagos;
END
$teardown$;

COMMIT;
