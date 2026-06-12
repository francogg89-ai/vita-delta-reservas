-- ============================================================================
-- VITA DELTA · ETAPA 9H · BLOQUE C v3 — FUNCIONES C.1 (lectura) + C.2 (escritura)
-- ============================================================================
-- Reemplaza a la v2. Ajuste único sobre v2:
--   D-9H-37  registrar_snapshot_periodo valida filas de liquidacion_socio:
--            0 permitido (períodos sin matriz, p.ej. junio); si hay filas, deben
--            ser exactamente (SELECT COUNT(*) FROM socios). Evita congelar foto
--            con 1-2 socios por regresión de saldo_socios_periodo.
-- Acumula además: D-9H-32 (advisory locks), D-9H-33 (monto_usd interno),
--   D-9H-34 (conversión solo a retiro/adelanto), D-9H-35 (cascada == 8 filas),
--   D-9H-36 (escala monetaria: ARS rechaza sub-centavo, TC redondeado a 4, pct ≤4 dec).
-- Gate   : aborta si ambiente != 'test' (L-9G-02).
-- Patrón : DROP + CREATE separados, sin OR REPLACE (L-9F-03). REVOKE 4 roles al pie.
-- Validado: harness PostgreSQL 16.14 — canónico + 14 smokes v1 + 11 smokes v2/v3, todo PASS.
-- Resultado esperado en Supabase: "Success. No rows returned"
-- ============================================================================
SET client_min_messages = warning;

DO $gate$
BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave = 'ambiente') IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION '9H Bloque C abortado: ambiente != test';
  END IF;
END $gate$;

-- DROP en orden seguro (dependientes -> base; idempotente; firmas idénticas a v1/v2)
DROP FUNCTION IF EXISTS reporte_retribucion_operativo_periodo(DATE);
DROP FUNCTION IF EXISTS registrar_snapshot_periodo(DATE,NUMERIC,TEXT,BIGINT,TEXT);
DROP FUNCTION IF EXISTS liquidacion_vigente(DATE);
DROP FUNCTION IF EXISTS saldo_corriente_socio(BIGINT);
DROP FUNCTION IF EXISTS mayor_socio(BIGINT);
DROP FUNCTION IF EXISTS registrar_retiro(BIGINT,DATE,NUMERIC,TEXT,TEXT,TEXT);
DROP FUNCTION IF EXISTS registrar_movimiento_manual(BIGINT,DATE,TEXT,NUMERIC,TEXT,TEXT,DATE,TEXT);
DROP FUNCTION IF EXISTS registrar_reversa(BIGINT,DATE,TEXT,TEXT);
DROP FUNCTION IF EXISTS registrar_revaluacion(BIGINT,DATE,NUMERIC,NUMERIC,TEXT,TEXT,BIGINT,TEXT);

-- ─────────────────────────── C.1 — LECTURA ──────────────────────────────────

-- liquidacion_vigente: id de la COLA de la cadena del período (foto vigente) o NULL
CREATE FUNCTION liquidacion_vigente(p_periodo DATE)
RETURNS BIGINT LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT lp.id_liquidacion
  FROM liquidaciones_periodo lp
  WHERE lp.periodo = date_trunc('month', p_periodo)::date
    AND NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s
                    WHERE s.id_liquidacion_supersede = lp.id_liquidacion);
$$;

-- saldo_corriente_socio: la fórmula D-9H-12 DESGLOSADA (auditoría ve las 3 fuentes)
CREATE FUNCTION saldo_corriente_socio(p_id_socio BIGINT)
RETURNS TABLE (orden SMALLINT, componente TEXT, monto NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER AS $$
  WITH vig AS (
    SELECT lp.id_liquidacion FROM liquidaciones_periodo lp
    WHERE NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s WHERE s.id_liquidacion_supersede = lp.id_liquidacion)
  ),
  liq AS (
    SELECT COALESCE(SUM(ls.saldo_final),0)          AS res,
           COALESCE(SUM(ls.desembolsado_periodo),0) AS reemb
    FROM liquidacion_socio ls JOIN vig ON vig.id_liquidacion = ls.id_liquidacion
    WHERE ls.id_socio = p_id_socio
  ),
  mov AS (SELECT COALESCE(SUM(monto),0) AS m FROM movimientos_socio WHERE id_socio = p_id_socio)
  SELECT 1::smallint,'resultado_liquidacion', (SELECT res FROM liq)
  UNION ALL SELECT 2,'reembolso_desembolso',  (SELECT reemb FROM liq)
  UNION ALL SELECT 3,'movimientos',           (SELECT m FROM mov)
  UNION ALL SELECT 4,'saldo_vivo',            (SELECT res+reemb FROM liq) + (SELECT m FROM mov);
$$;

-- mayor_socio: libro mayor línea por línea con saldo acumulado
CREATE FUNCTION mayor_socio(p_id_socio BIGINT)
RETURNS TABLE (fecha DATE, tipo TEXT, referencia TEXT, monto NUMERIC, saldo_acumulado NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER AS $$
  WITH vig AS (
    SELECT lp.id_liquidacion, lp.periodo FROM liquidaciones_periodo lp
    WHERE NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s WHERE s.id_liquidacion_supersede = lp.id_liquidacion)
  ),
  asientos AS (
    SELECT v.periodo AS fecha, 'liquidacion'::text AS tipo, 'liq#'||ls.id_liquidacion AS referencia,
           ls.saldo_final AS monto, 1 AS sub
    FROM liquidacion_socio ls JOIN vig v ON v.id_liquidacion = ls.id_liquidacion
    WHERE ls.id_socio = p_id_socio
    UNION ALL
    SELECT v.periodo, 'reembolso_desembolso', 'liq#'||ls.id_liquidacion, ls.desembolsado_periodo, 2
    FROM liquidacion_socio ls JOIN vig v ON v.id_liquidacion = ls.id_liquidacion
    WHERE ls.id_socio = p_id_socio AND ls.desembolsado_periodo <> 0
    UNION ALL
    SELECT m.fecha, m.tipo, 'mov#'||m.id_movimiento, m.monto, 3
    FROM movimientos_socio m WHERE m.id_socio = p_id_socio
  )
  SELECT fecha, tipo, referencia, monto,
         SUM(monto) OVER (ORDER BY fecha, sub, referencia ROWS UNBOUNDED PRECEDING) AS saldo_acumulado
  FROM asientos
  ORDER BY fecha, sub, referencia;
$$;

-- reporte_retribucion_operativo_periodo: calculado (paso 4) vs asignado (neto) — D-9H-14
CREATE FUNCTION reporte_retribucion_operativo_periodo(p_periodo DATE)
RETURNS TABLE (periodo DATE, calculado NUMERIC, asignado NUMERIC, diferencia NUMERIC, estado TEXT)
LANGUAGE sql STABLE SECURITY INVOKER AS $$
  WITH per AS (SELECT date_trunc('month', p_periodo)::date AS p),
  calc AS (  -- paso 4 está negativo (deducción); lo a asignar es su magnitud
    SELECT COALESCE(-(SELECT lc.monto FROM liquidacion_cascada lc
                      WHERE lc.id_liquidacion = liquidacion_vigente((SELECT p FROM per)) AND lc.paso = 4), 0) AS m
  ),
  asig AS (  -- neto: asignaciones del período + reversas de esas asignaciones
    SELECT COALESCE(SUM(eff.monto),0) AS m FROM (
      SELECT mo.monto FROM movimientos_socio mo
        WHERE mo.tipo='retribucion_operativo' AND mo.periodo = (SELECT p FROM per)
      UNION ALL
      SELECT r.monto FROM movimientos_socio r JOIN movimientos_socio o ON o.id_movimiento = r.id_movimiento_revertido
        WHERE r.tipo='reversa' AND o.tipo='retribucion_operativo' AND o.periodo = (SELECT p FROM per)
    ) eff
  )
  SELECT (SELECT p FROM per), (SELECT m FROM calc), (SELECT m FROM asig),
         (SELECT m FROM calc) - (SELECT m FROM asig),
         CASE WHEN (SELECT m FROM calc) = 0 THEN 'SIN_CALCULADO'
              WHEN (SELECT m FROM asig) = 0 THEN 'PENDIENTE'
              WHEN (SELECT m FROM calc) = (SELECT m FROM asig) THEN 'CONCILIADO'
              WHEN (SELECT m FROM asig) < (SELECT m FROM calc) THEN 'PARCIAL'
              ELSE 'EXCEDIDO' END;
$$;

-- ─────────────────────────── C.2 — ESCRITURA ────────────────────────────────

-- registrar_snapshot_periodo: congela 9G. Re-snapshot explícito (D-9H-24): si ya
-- hay vigente, exige p_supersede_id = cola actual + comentario. Lock por período
-- (D-9H-32). pct validado y nunca congela paso 0 (D-9H-26). Junio: 0 filas socio OK.
CREATE FUNCTION registrar_snapshot_periodo(
    p_periodo DATE, p_pct NUMERIC, p_creado_por TEXT,
    p_supersede_id BIGINT DEFAULT NULL, p_comentario TEXT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql VOLATILE SECURITY INVOKER AS $$
DECLARE v_periodo DATE := date_trunc('month', p_periodo)::date;
        v_cola BIGINT; v_id BIGINT; v_n_cascada INTEGER; v_n_socios INTEGER; v_socios_total INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(919001, hashtext(v_periodo::text));  -- lock por período
  IF p_pct IS NULL OR p_pct < 0 OR p_pct > 1 THEN
    RAISE EXCEPTION '9H snapshot: pct_operativo invalido (% fuera de [0,1])', p_pct;
  END IF;
  IF p_pct <> ROUND(p_pct, 4) THEN                                       -- D-9H-36
    RAISE EXCEPTION '9H snapshot: pct_operativo excede 4 decimales (%)', p_pct;
  END IF;
  v_cola := liquidacion_vigente(v_periodo);
  IF v_cola IS NULL THEN
    IF p_supersede_id IS NOT NULL THEN
      RAISE EXCEPTION '9H snapshot: el período % no tiene foto vigente; p_supersede_id debe ser NULL', v_periodo;
    END IF;
  ELSE
    IF p_supersede_id IS NULL OR p_supersede_id <> v_cola THEN
      RAISE EXCEPTION '9H snapshot: el período % ya tiene foto vigente (id=%); para re-snapshot pasar p_supersede_id=% (la cola actual)', v_periodo, v_cola, v_cola;
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

  RETURN v_id;
END $$;

-- registrar_retiro: monto POSITIVO (magnitud); guarda -monto. Guard saldo<0 (D-9H-25).
-- Lock por socio antes de leer saldo e insertar (D-9H-32).
CREATE FUNCTION registrar_retiro(
    p_id_socio BIGINT, p_fecha DATE, p_monto NUMERIC, p_medio_pago TEXT,
    p_creado_por TEXT, p_comentario TEXT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql VOLATILE SECURITY INVOKER AS $$
DECLARE v_saldo NUMERIC; v_id BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(919002, p_id_socio::int);  -- lock por socio
  IF p_monto IS NULL OR p_monto <= 0 THEN
    RAISE EXCEPTION '9H retiro: monto debe ser positivo (magnitud a retirar)';
  END IF;
  IF p_monto <> ROUND(p_monto, 2) THEN                                   -- D-9H-36
    RAISE EXCEPTION '9H retiro: monto excede 2 decimales (%)', p_monto;
  END IF;
  v_saldo := (
    SELECT COALESCE(SUM(ls.saldo_final + ls.desembolsado_periodo),0)
    FROM liquidacion_socio ls JOIN liquidaciones_periodo lp ON lp.id_liquidacion = ls.id_liquidacion
    WHERE ls.id_socio = p_id_socio
      AND NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s WHERE s.id_liquidacion_supersede = lp.id_liquidacion)
  ) + (SELECT COALESCE(SUM(monto),0) FROM movimientos_socio WHERE id_socio = p_id_socio);
  IF v_saldo - p_monto < 0 THEN
    RAISE EXCEPTION '9H retiro: saldo insuficiente (vivo=%, retiro=%). Usar adelanto/ajuste_manual para saldo negativo', v_saldo, p_monto;
  END IF;
  INSERT INTO movimientos_socio (id_socio, fecha, tipo, monto, medio_pago, comentario, creado_por)
  VALUES (p_id_socio, p_fecha, 'retiro', -p_monto, p_medio_pago, p_comentario, p_creado_por)
  RETURNING id_movimiento INTO v_id;
  RETURN v_id;
END $$;

-- registrar_movimiento_manual: adelanto/ajuste_manual/retribucion_operativo/ajuste_arranque.
-- Sin guard de saldo (adelanto/ajuste_manual son la vía explícita a negativo, D-9H-07).
-- Lock por socio (D-9H-32). Los CHECK de tabla son el backstop de signo/comentario/período.
CREATE FUNCTION registrar_movimiento_manual(
    p_id_socio BIGINT, p_fecha DATE, p_tipo TEXT, p_monto NUMERIC,
    p_creado_por TEXT, p_comentario TEXT, p_periodo DATE DEFAULT NULL, p_medio_pago TEXT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql VOLATILE SECURITY INVOKER AS $$
DECLARE v_id BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(919002, p_id_socio::int);
  IF p_tipo NOT IN ('adelanto','ajuste_manual','retribucion_operativo','ajuste_arranque') THEN
    RAISE EXCEPTION '9H mov manual: tipo % no permitido aquí (retiro/reversa tienen función propia)', p_tipo;
  END IF;
  IF p_monto <> ROUND(p_monto, 2) THEN                                   -- D-9H-36
    RAISE EXCEPTION '9H mov manual: monto excede 2 decimales (%)', p_monto;
  END IF;
  INSERT INTO movimientos_socio (id_socio, fecha, tipo, monto, periodo, medio_pago, comentario, creado_por)
  VALUES (p_id_socio, p_fecha, p_tipo, p_monto,
          CASE WHEN p_periodo IS NULL THEN NULL ELSE date_trunc('month',p_periodo)::date END,
          p_medio_pago, p_comentario, p_creado_por)
  RETURNING id_movimiento INTO v_id;
  RETURN v_id;
END $$;

-- registrar_reversa: recibe SOLO id original + fecha + comentario + creado_por.
-- Calcula monto opuesto (D-9H-28). Mismo socio ya estructural; índice impide doble.
CREATE FUNCTION registrar_reversa(
    p_id_movimiento_revertido BIGINT, p_fecha DATE, p_creado_por TEXT, p_comentario TEXT)
RETURNS BIGINT LANGUAGE plpgsql VOLATILE SECURITY INVOKER AS $$
DECLARE v_socio BIGINT; v_monto NUMERIC; v_id BIGINT;
BEGIN
  SELECT id_socio, monto INTO v_socio, v_monto FROM movimientos_socio WHERE id_movimiento = p_id_movimiento_revertido;
  IF NOT FOUND THEN
    RAISE EXCEPTION '9H reversa: movimiento original % inexistente', p_id_movimiento_revertido;
  END IF;
  PERFORM pg_advisory_xact_lock(919002, v_socio::int);  -- lock por socio del original
  INSERT INTO movimientos_socio (id_socio, fecha, tipo, monto, comentario, creado_por, id_movimiento_revertido)
  VALUES (v_socio, p_fecha, 'reversa', -v_monto, p_comentario, p_creado_por, p_id_movimiento_revertido)
  RETURNING id_movimiento INTO v_id;
  RETURN v_id;
END $$;

-- registrar_revaluacion: calcula monto_usd interno (D-9H-33). Valuación (origen NULL)
-- o conversión ligada con tope acumulado (D-9H-29). Lock por socio. NO toca el mayor.
CREATE FUNCTION registrar_revaluacion(
    p_id_socio BIGINT, p_fecha DATE, p_tipo_cambio NUMERIC, p_monto_ars NUMERIC,
    p_alcance TEXT, p_creado_por TEXT, p_id_movimiento_origen BIGINT DEFAULT NULL, p_comentario TEXT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql VOLATILE SECURITY INVOKER AS $$
DECLARE v_usd NUMERIC; v_tope NUMERIC; v_convertido NUMERIC; v_id BIGINT; v_tipo_origen TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(919002, p_id_socio::int);
  IF p_tipo_cambio IS NULL OR p_tipo_cambio <= 0 THEN RAISE EXCEPTION '9H reval: tipo_cambio debe ser > 0'; END IF;
  IF p_monto_ars   IS NULL OR p_monto_ars   <= 0 THEN RAISE EXCEPTION '9H reval: monto_ars debe ser > 0'; END IF;
  IF p_alcance NOT IN ('total','parcial') THEN RAISE EXCEPTION '9H reval: alcance invalido (%)', p_alcance; END IF;
  IF p_monto_ars <> ROUND(p_monto_ars, 2) THEN                           -- D-9H-36
    RAISE EXCEPTION '9H reval: monto_ars excede 2 decimales (%)', p_monto_ars;
  END IF;
  p_tipo_cambio := ROUND(p_tipo_cambio, 4);  -- D-9H-36: redondeo explícito; alinea con NUMERIC(14,4) y el CHECK USD

  IF p_id_movimiento_origen IS NOT NULL THEN  -- conversión ligada (D-9H-29/34)
    SELECT tipo, ABS(monto) INTO v_tipo_origen, v_tope FROM movimientos_socio
      WHERE id_movimiento = p_id_movimiento_origen AND id_socio = p_id_socio;
    IF NOT FOUND THEN
      RAISE EXCEPTION '9H reval: movimiento origen % no pertenece al socio % (o no existe)', p_id_movimiento_origen, p_id_socio;
    END IF;
    IF v_tipo_origen NOT IN ('retiro','adelanto') THEN                   -- D-9H-34
      RAISE EXCEPTION '9H reval: conversión solo se liga a retiro/adelanto (origen % es %)', p_id_movimiento_origen, v_tipo_origen;
    END IF;
    v_convertido := (SELECT COALESCE(SUM(monto_ars),0) FROM revaluaciones WHERE id_movimiento_origen = p_id_movimiento_origen);
    IF v_convertido + p_monto_ars > v_tope THEN
      RAISE EXCEPTION '9H reval: conversión excede el movimiento (ya convertido=%, nuevo=%, tope=%)', v_convertido, p_monto_ars, v_tope;
    END IF;
  END IF;

  v_usd := ROUND(p_monto_ars / p_tipo_cambio, 2);  -- D-9H-33: interno, no input
  INSERT INTO revaluaciones (id_socio, fecha, tipo_cambio, monto_ars, monto_usd, alcance, id_movimiento_origen, comentario, creado_por)
  VALUES (p_id_socio, p_fecha, p_tipo_cambio, p_monto_ars, v_usd, p_alcance, p_id_movimiento_origen, p_comentario, p_creado_por)
  RETURNING id_revaluacion INTO v_id;
  RETURN v_id;
END $$;

-- ── REVOKE de los 4 roles (paridad 9G): solo el owner ejecuta ────────────────
DO $revoke$
DECLARE fn TEXT;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'liquidacion_vigente(DATE)',
    'saldo_corriente_socio(BIGINT)',
    'mayor_socio(BIGINT)',
    'reporte_retribucion_operativo_periodo(DATE)',
    'registrar_snapshot_periodo(DATE,NUMERIC,TEXT,BIGINT,TEXT)',
    'registrar_retiro(BIGINT,DATE,NUMERIC,TEXT,TEXT,TEXT)',
    'registrar_movimiento_manual(BIGINT,DATE,TEXT,NUMERIC,TEXT,TEXT,DATE,TEXT)',
    'registrar_reversa(BIGINT,DATE,TEXT,TEXT)',
    'registrar_revaluacion(BIGINT,DATE,NUMERIC,NUMERIC,TEXT,TEXT,BIGINT,TEXT)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role', fn);
  END LOOP;
END $revoke$;
