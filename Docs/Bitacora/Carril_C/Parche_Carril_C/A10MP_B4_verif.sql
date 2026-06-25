-- ============================================================================
-- VITA DELTA · CARRIL C · A10-MP · BLOQUE 4 — VERIFICACION (TEST-only, read-mostly)
-- Corre DESPUES del smoke DIRECTO. Verifica: (1) lineas por caso (medio/traza/nota),
-- (2) las TRES separaciones contables sobre el cobro con transferencia+recargo, y
-- (3) el ROLLBACK atomico via abortar_si_falla (determinista, en transaccion revertida).
-- Marcador de cobro: source_event 'portal_test_a10mp_res<id>_%'. No escribe (salvo la probe
-- de rollback, que se revierte). Anti-OPS por gate. COMO CORRER: SQL Editor TEST, todo el archivo.
-- ============================================================================
BEGIN;

DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN RAISE EXCEPTION 'GATE verif: ambiente=% (esperado test).', COALESCE(v_amb,'<ausente>'); END IF;
END $gate$;

-- ---- (1) LINEAS POR CASO (medio_pago, traza de otros, nota del operador) ----
-- Helper inline: lineas de cobro de una reserva (por prefijo de source_event).
-- 9910002 transferencia bancaria (+recargo) ; 9910003 transferencia mp ; 9910006 otros ; 9910012 nota.
SELECT 'lineas_por_caso' AS seccion, jsonb_build_object(
  '9910002_tiene_saldo_transf_bancaria', EXISTS (SELECT 1 FROM pagos WHERE source_event LIKE 'portal_test_a10mp_res9910002\_%' AND tipo='saldo' AND medio_pago='transferencia_bancaria'),
  '9910002_tiene_extra_recargo',         EXISTS (SELECT 1 FROM pagos WHERE source_event LIKE 'portal_test_a10mp_res9910002\_%' AND tipo='extra' AND medio_pago='transferencia_bancaria' AND notas LIKE 'recargo_5_saldo_transferencia%'),
  '9910003_tiene_transferencia_mp',      EXISTS (SELECT 1 FROM pagos WHERE source_event LIKE 'portal_test_a10mp_res9910003\_%' AND medio_pago='transferencia_mp'),
  '9910006_otros_como_efectivo_traza',   EXISTS (SELECT 1 FROM pagos WHERE source_event LIKE 'portal_test_a10mp_res9910006\_%' AND tipo='saldo' AND medio_pago='efectivo' AND notas LIKE 'medio_original=otros;%'),
  '9910012_nota_operador_persistida',    EXISTS (SELECT 1 FROM pagos WHERE source_event LIKE 'portal_test_a10mp_res9910012\_%' AND tipo='saldo' AND notas LIKE '%nota_operador=%'),
  '9910012_extra_sin_nota_operador',     NOT EXISTS (SELECT 1 FROM pagos WHERE source_event LIKE 'portal_test_a10mp_res9910012\_%' AND tipo='extra' AND notas LIKE '%nota_operador=%')
) AS detalle;

-- ---- (2) SEPARACION CONTABLE sobre 9910002 (transferencia + recargo) ----
-- A12 base / 25% base = SUM(sena+saldo) ; A25 caja = SUM(sena+saldo+extra) ; saldo = monto_total - base.
-- Asserts: extra>0 ; A25 - base = extra ; saldo = monto_total - base (extra NO baja saldo) ; base = 25% base.
WITH r AS (SELECT monto_total FROM reservas WHERE id_reserva=9910002),
agg AS (
  SELECT
    COALESCE(SUM(monto_recibido) FILTER (WHERE estado='confirmado' AND tipo IN ('sena','saldo')),0) AS base_a12_y_25,
    COALESCE(SUM(monto_recibido) FILTER (WHERE estado='confirmado' AND tipo IN ('sena','saldo','extra','ajuste','reembolso')),0) AS caja_a25,
    COALESCE(SUM(monto_recibido) FILTER (WHERE estado='confirmado' AND tipo='extra'),0) AS extra_total
  FROM pagos WHERE id_reserva=9910002
)
SELECT 'separacion_contable_9910002' AS seccion,
  jsonb_build_object(
    'monto_total',(SELECT monto_total FROM r),
    'base_a12_y_25',(SELECT base_a12_y_25 FROM agg),
    'caja_a25',(SELECT caja_a25 FROM agg),
    'extra_total',(SELECT extra_total FROM agg),
    'saldo_real_A12',(SELECT monto_total FROM r)-(SELECT base_a12_y_25 FROM agg)
  ) AS detalle,
  CASE WHEN
        (SELECT extra_total FROM agg) > 0
    AND (SELECT caja_a25 FROM agg) - (SELECT base_a12_y_25 FROM agg) = (SELECT extra_total FROM agg)   -- A25 incluye extra
    AND (SELECT caja_a25 FROM agg) > (SELECT base_a12_y_25 FROM agg)                                    -- A25 > base 25% (extra aparte)
  THEN 'PASS' ELSE 'FAIL (corriste el smoke directo con transferencia en 9910002?)' END AS veredicto_contable;
-- Interpretacion: saldo_real usa base (sena+saldo) -> el extra NO bajo saldo (A12 ok).
-- caja_a25 = base + extra -> el extra SI es caja percibida (A25 ok).
-- 25% base = base (sena+saldo), NO incluye extra (distribucion ok).

-- ---- (3) ROLLBACK ATOMICO (abortar_si_falla -> P0001 -> revierte TODAS las lineas) ----
DO $rb$
DECLARE
  v_se text := 'portal_test_a10mp_res_rollback_probe';
  v_raised boolean := false; v_sqlstate text := ''; v_count int;
BEGIN
  DELETE FROM pagos WHERE source_event = v_se;  -- limpiar resto previo
  BEGIN
    -- branch F con 2 lineas: la 1ra valida (9910001), la 2da con reserva inexistente -> registrar_pago
    -- devuelve ok:false -> abortar_si_falla lanza P0001 -> la sub-transaccion revierte AMBAS.
    PERFORM public.abortar_si_falla(public.registrar_pago(l.value))
    FROM jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('id_reserva',9910001,'tipo','saldo','medio_pago','efectivo','monto_esperado',1000,'monto_recibido',1000,'moneda','ARS','estado_inicial','confirmado','validado_por','rb_probe','source_event',v_se,'notas','linea_valida'),
      jsonb_build_object('id_reserva',99999999,'tipo','saldo','medio_pago','efectivo','monto_esperado',1000,'monto_recibido',1000,'moneda','ARS','estado_inicial','confirmado','validado_por','rb_probe','source_event',v_se,'notas','reserva_inexistente')
    ) AS l;
  EXCEPTION WHEN others THEN
    v_raised := true; v_sqlstate := SQLSTATE;
  END;
  SELECT count(*) INTO v_count FROM pagos WHERE source_event = v_se;
  RAISE NOTICE 'ROLLBACK TEST: raised=% sqlstate=% pagos_persistidos=% (esperado: raised=true, sqlstate=P0001, pagos=0)', v_raised, v_sqlstate, v_count;
  IF NOT (v_raised AND v_count = 0) THEN
    RAISE EXCEPTION 'ROLLBACK TEST FAIL: raised=% pagos=% (la atomicidad no se cumplio)', v_raised, v_count;
  END IF;
  DELETE FROM pagos WHERE source_event = v_se;  -- defensivo (no deberia haber nada)
END $rb$;

SELECT 'rollback_test' AS seccion, 'PASS (ver NOTICE: raised=true, P0001, 0 pagos)'::text AS veredicto;

COMMIT;
