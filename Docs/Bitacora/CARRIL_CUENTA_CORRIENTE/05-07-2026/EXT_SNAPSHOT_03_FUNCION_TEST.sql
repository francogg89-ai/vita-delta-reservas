-- ============================================================================
-- EXT_SNAPSHOT_03_FUNCION_TEST.sql   (Run 3/6  --  ESCRIBE, transaccional)
-- Reemplaza registrar_snapshot_periodo por DROP FUNCTION + CREATE (no CREATE OR
-- REPLACE, L-CC-07) y REVOKE EXECUTE explicito (no reabrir EXECUTE por default).
-- Cuerpo original byte-exacto (fold ASCII de 3 acentos) + extension P-CC-2.
-- TEST-only (gate). Transaccional: si el gate falla, ROLLBACK (no dropea).
-- ============================================================================
BEGIN;
DO $gate$ BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave='ambiente') IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE TEST-only: ambiente actual = %', COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(sin clave)');
  END IF;
END $gate$;

DROP FUNCTION IF EXISTS public.registrar_snapshot_periodo(date,numeric,text,bigint,text);

CREATE FUNCTION public.registrar_snapshot_periodo(p_periodo date, p_pct numeric, p_creado_por text, p_supersede_id bigint DEFAULT NULL::bigint, p_comentario text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_periodo DATE := date_trunc('month', p_periodo)::date;
        v_cola BIGINT; v_id BIGINT; v_n_cascada INTEGER; v_n_socios INTEGER; v_socios_total INTEGER;
        v_n_part INTEGER; v_cabanas_total INTEGER; v_n_gasto INTEGER; v_gastos_total INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(919001, hashtext(v_periodo::text));  -- lock por periodo
  IF p_pct IS NULL OR p_pct < 0 OR p_pct > 1 THEN
    RAISE EXCEPTION '9H snapshot: pct_operativo invalido (% fuera de [0,1])', p_pct;
  END IF;
  IF p_pct <> ROUND(p_pct, 4) THEN                                       -- D-9H-36
    RAISE EXCEPTION '9H snapshot: pct_operativo excede 4 decimales (%)', p_pct;
  END IF;
  v_cola := liquidacion_vigente(v_periodo);
  IF v_cola IS NULL THEN
    IF p_supersede_id IS NOT NULL THEN
      RAISE EXCEPTION '9H snapshot: el periodo % no tiene foto vigente; p_supersede_id debe ser NULL', v_periodo;
    END IF;
  ELSE
    IF p_supersede_id IS NULL OR p_supersede_id <> v_cola THEN
      RAISE EXCEPTION '9H snapshot: el periodo % ya tiene foto vigente (id=%); para re-snapshot pasar p_supersede_id=% (la cola actual)', v_periodo, v_cola, v_cola;
    END IF;
    IF p_comentario IS NULL OR btrim(p_comentario) = '' THEN
      RAISE EXCEPTION '9H snapshot: re-snapshot exige comentario (D-9H-24)';
    END IF;
  END IF;

  INSERT INTO liquidaciones_periodo (periodo, pct_operativo, id_liquidacion_supersede, creado_por, comentario)
  VALUES (v_periodo, p_pct, p_supersede_id, p_creado_por, p_comentario)
  RETURNING id_liquidacion INTO v_id;

  INSERT INTO liquidacion_cascada (id_liquidacion, paso, concepto, monto)
  SELECT v_id, paso, concepto, monto FROM cascada_periodo(v_periodo, p_pct)
  WHERE paso BETWEEN 1 AND 8;  -- excluye el guard paso=0
  GET DIAGNOSTICS v_n_cascada = ROW_COUNT;                              -- D-9H-35
  IF v_n_cascada <> 8 THEN
    RAISE EXCEPTION '9H snapshot: cascada incompleta para % (% pasos insertados, esperados 8)', v_periodo, v_n_cascada;
  END IF;

  INSERT INTO liquidacion_socio (id_liquidacion, id_socio, saldo_bruto, gastos_d, gastos_e, saldo_final, desembolsado_periodo)
  SELECT v_id, id_socio, saldo_bruto, gastos_d, gastos_e, saldo_final, desembolsado_periodo
  FROM saldo_socios_periodo(v_periodo, p_pct)
  WHERE id_socio IS NOT NULL;  -- junio: 0 filas, permitido (D-9H-27)
  GET DIAGNOSTICS v_n_socios = ROW_COUNT;                               -- D-9H-37
  SELECT COUNT(*) INTO v_socios_total FROM socios;
  IF v_n_socios <> 0 AND v_n_socios <> v_socios_total THEN
    RAISE EXCEPTION '9H snapshot: liquidacion_socio incompleta para % (% filas, esperadas 0 o %)',
      v_periodo, v_n_socios, v_socios_total;
  END IF;

  -- ===================== EXTENSION P-CC-2: detalle fino congelado (D-CC-23..30) =====================
  -- T1: participacion por cabana <- detalle_participacion (ground truth; matriz por socio deriva de aca)
  INSERT INTO liquidacion_participacion (id_liquidacion, id_cabana, valor_relativo, id_socio_beneficiario, participa)
  SELECT v_id, dp.id_cabana, dp.valor_relativo, dp.id_socio, dp.participa
  FROM detalle_participacion(v_periodo) dp;
  GET DIAGNOSTICS v_n_part = ROW_COUNT;
  SELECT COUNT(*) INTO v_cabanas_total FROM cabanas;
  IF v_n_part <> v_cabanas_total THEN
    RAISE EXCEPTION '9H snapshot: liquidacion_participacion incompleta para % (% filas, esperadas %)',
      v_periodo, v_n_part, v_cabanas_total;
  END IF;

  -- T2: gasto por gasto <- gastos_internos + LEFT JOIN gastos_sin_incidencia (sin_incidencia/motivo CONGELADOS)
  INSERT INTO liquidacion_gasto (id_liquidacion, id_gasto, fecha, clase, clase_sugerida, etiqueta, monto, moneda,
                                 id_zona, id_cabana, pagador_tipo, id_socio_pagador, medio_pago, comentario,
                                 comprobante_url, creado_por, created_at, sin_incidencia, motivo_sin_incidencia)
  SELECT v_id, g.id_gasto, g.fecha, g.clase, g.clase_sugerida, g.etiqueta, g.monto, g.moneda,
         g.id_zona, g.id_cabana, g.pagador_tipo, g.id_socio_pagador, g.medio_pago, g.comentario,
         g.comprobante_url, g.creado_por, g.created_at,
         (sic.id_gasto IS NOT NULL) AS sin_incidencia, sic.motivo
  FROM gastos_internos g
  LEFT JOIN gastos_sin_incidencia_periodo(v_periodo) sic ON sic.id_gasto = g.id_gasto
  WHERE g.periodo = v_periodo;
  GET DIAGNOSTICS v_n_gasto = ROW_COUNT;
  SELECT COUNT(*) INTO v_gastos_total FROM gastos_internos WHERE periodo = v_periodo;
  IF v_n_gasto <> v_gastos_total THEN
    RAISE EXCEPTION '9H snapshot: liquidacion_gasto incompleta para % (% filas, esperadas %)',
      v_periodo, v_n_gasto, v_gastos_total;
  END IF;

  -- T3: incidencia por gasto <- incidencia_gasto (regla CONGELADA); seq por gasto; sin-incidencia => 0 filas
  INSERT INTO liquidacion_incidencia (id_liquidacion, id_gasto, seq, destino, id_socio, monto_incidido, regla)
  SELECT v_id, g.id_gasto,
         (ROW_NUMBER() OVER (PARTITION BY g.id_gasto ORDER BY i.id_socio NULLS FIRST))::smallint AS seq,
         i.destino, i.id_socio, i.monto, i.regla
  FROM gastos_internos g
  CROSS JOIN LATERAL incidencia_gasto(g.id_gasto) i
  WHERE g.periodo = v_periodo;
  -- (T3 sin guard de cantidad fija: varia por clase; la coherencia sin_incidencia<->vacuidad se valida aparte)
  -- ==================================================================================================

  RETURN v_id;
END $function$
;

-- REVOKE EXECUTE explicito tras recrear (condicion Franco #1)
REVOKE EXECUTE ON FUNCTION public.registrar_snapshot_periodo(date,numeric,text,bigint,text) FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
