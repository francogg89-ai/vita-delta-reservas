-- ============================================================================
-- PROMO_BLOQUE_H_9H_FUNCIONES_OPS.sql
-- Promoción del Carril B a OPS — BLOQUE H (9H: las 9 FUNCIONES).
-- Etapa PROMO. Depende de B1(9C), C(9D), D(9E), E(9F), F(9G) y G(9H estructura)
-- VERDE en OPS.
-- Contenido: 4 funciones de LECTURA (STABLE) + 5 de ESCRITURA (VOLATILE, solo
-- INSERT a las tablas append-only de 9H) + REVOKE EXECUTE de las 9.
--   Lectura : liquidacion_vigente, saldo_corriente_socio, mayor_socio,
--             reporte_retribucion_operativo_periodo.
--   Escritura: registrar_snapshot_periodo (congela 9G: cascada_periodo +
--             saldo_socios_periodo), registrar_retiro, registrar_movimiento_manual,
--             registrar_reversa, registrar_revaluacion.
--
-- Funciones VERBATIM de 9H_BLOQUE_C_FUNCIONES_v3.sql (fuente autoritativa de la
-- sesión 9H). ÚNICO cambio respecto del original: se reemplaza su gate de TEST
-- (ambiente='test') por el gate PROMO de abajo (ops + identidad + cadena 9C→9G
-- + 9H estructura presente + 9H funciones ausentes). Los cuerpos no se tocan.
--
-- IMPORTANTE — patrón con funciones de escritura: este bloque SOLO crea las
-- funciones; NO las ejecuta. Por eso las tablas siguen VACÍAS y las 3 secuencias
-- en 1 tras correrlo (crear una función no la corre). El comportamiento funcional
-- de las 5 de escritura (que registrar_snapshot congela 9G, que registrar_retiro
-- guarda el saldo, reversa de mismo-signo, tope de conversión, etc.) se valida en
-- HARNESS bajo ROLLBACK — NO en OPS: ejecutarlas con commit insertaría datos
-- reales y con rollback avanzaría las secuencias reales (nextval no-transaccional).
-- El bloque OPS verifica que las 9 EXISTEN con la firma exacta y están sin EXECUTE.
-- NO toca 9C/9D/9E/9F/9G ni helper 9B ni la legacy `gastos`.
--
-- ESTRUCTURA: BEGIN → gate → DROP+CREATE verbatim (9) + REVOKE → asserts →
-- COMMIT → verificación read-only → reversión sin CASCADE.
-- Correr con NADA seleccionado (L-8A-01).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- GATE PROMO — ops + identidad + cadena 9C→9G + 9H estructura + 9H fns ausentes.
-- (Reemplaza el gate de TEST del archivo original.)
-- ----------------------------------------------------------------------------
DO $promogate$
DECLARE
  v_amb text; v_cab int; v_soc int;
  v_9c int; v_9d int; v_9e int; v_9f int; v_9g int;
  v_9h_tab int; v_9h_trgfn int; v_9h_fns int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE H: marcador ambiente=% (esperado ops).', COALESCE(v_amb,'<ausente>'); END IF;

  SELECT count(*) INTO v_cab FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
   WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  SELECT count(*) INTO v_soc FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
   WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1;
  IF v_cab<>5 OR v_soc<>3 THEN RAISE EXCEPTION 'GATE H: identidad (cabañas=%/5, socios=%/3).', v_cab, v_soc; END IF;

  -- Cadena 9C→9G presente
  SELECT count(*) INTO v_9c FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='resolver_beneficiario';
  SELECT count(*) INTO v_9d FROM activaciones_operativas;
  SELECT count(*) INTO v_9e FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('matriz_participacion','repartir_por_matriz','detalle_participacion');
  SELECT count(*) INTO v_9f FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r' AND c.relname='gastos_internos';
  SELECT count(*) INTO v_9g FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                       'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo');
  IF v_9c<>1 THEN RAISE EXCEPTION 'GATE H: seam 9C ausente.'; END IF;
  IF v_9d<>5 THEN RAISE EXCEPTION 'GATE H: activaciones 9D=% (esperado 5).', v_9d; END IF;
  IF v_9e<>3 THEN RAISE EXCEPTION 'GATE H: funciones 9E=% (esperado 3).', v_9e; END IF;
  IF v_9f<>1 THEN RAISE EXCEPTION 'GATE H: tabla 9F ausente.'; END IF;
  IF v_9g<>6 THEN RAISE EXCEPTION 'GATE H: funciones 9G=% (esperado 6).', v_9g; END IF;

  -- 9H ESTRUCTURA presente (dependencia: H necesita G) — 5 tablas + fn trigger
  SELECT count(*) INTO v_9h_tab FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r'
     AND c.relname IN ('liquidaciones_periodo','liquidacion_cascada','liquidacion_socio','movimientos_socio','revaluaciones');
  SELECT count(*) INTO v_9h_trgfn FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='trg_9h_inmutable';
  IF v_9h_tab<>5 OR v_9h_trgfn<>1 THEN
    RAISE EXCEPTION 'GATE H: 9H estructura incompleta (tablas=%/5, trg_fn=%/1; correr G).', v_9h_tab, v_9h_trgfn; END IF;

  -- 9H FUNCIONES ausentes — guard de re-ejecución (las 9 nominadas; NO trg_9h_inmutable)
  SELECT count(*) INTO v_9h_fns FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('liquidacion_vigente','saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo',
                       'registrar_snapshot_periodo','registrar_retiro','registrar_movimiento_manual',
                       'registrar_reversa','registrar_revaluacion');
  IF v_9h_fns<>0 THEN RAISE EXCEPTION 'GATE H: funciones 9H ya presentes (=%). H no se re-ejecuta.', v_9h_fns; END IF;

  RAISE NOTICE 'GATE H OK — OPS post-9G estructura; 9H funciones ausentes.';
END
$promogate$;

-- ============================================================================
-- FUNCIONES 9H — VERBATIM de 9H_BLOQUE_C_FUNCIONES_v3.sql (sin su gate de TEST).
-- ============================================================================
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

-- ----------------------------------------------------------------------------
-- ASSERTS FINALES — 9 firmas exactas, volatilidad, security invoker, REVOKE,
-- tablas vacías, secuencias en 1, aislamiento de 9G.
-- ----------------------------------------------------------------------------
DO $assert$
DECLARE
  v_sig int; v_stable int; v_volatile int; v_secdef int; v_open int;
  v_filas int; v_seq_called int; v_9g int; v_excl int;
  v_dataapi oid[];
  v_firmas text[] := ARRAY[
    'public.liquidacion_vigente(date)',
    'public.saldo_corriente_socio(bigint)',
    'public.mayor_socio(bigint)',
    'public.reporte_retribucion_operativo_periodo(date)',
    'public.registrar_snapshot_periodo(date,numeric,text,bigint,text)',
    'public.registrar_retiro(bigint,date,numeric,text,text,text)',
    'public.registrar_movimiento_manual(bigint,date,text,numeric,text,text,date,text)',
    'public.registrar_reversa(bigint,date,text,text)',
    'public.registrar_revaluacion(bigint,date,numeric,numeric,text,text,bigint,text)'];
  v_lectura text[] := ARRAY['liquidacion_vigente','saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo'];
  v_escritura text[] := ARRAY['registrar_snapshot_periodo','registrar_retiro','registrar_movimiento_manual','registrar_reversa','registrar_revaluacion'];
  f text;
BEGIN
  v_dataapi := array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL);

  -- H1: las 9 firmas EXACTAS resuelven (to_regprocedure NULL si no existe la firma)
  v_sig := 0;
  FOREACH f IN ARRAY v_firmas LOOP
    IF to_regprocedure(f) IS NOT NULL THEN v_sig := v_sig+1; END IF;
  END LOOP;
  IF v_sig<>9 THEN RAISE EXCEPTION 'ASSERT H1: firmas 9H exactas resueltas=% (esperado 9).', v_sig; END IF;

  -- H2: 4 lectura STABLE + 5 escritura VOLATILE
  SELECT count(*) INTO v_stable FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname = ANY(v_lectura) AND p.provolatile='s';
  SELECT count(*) INTO v_volatile FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname = ANY(v_escritura) AND p.provolatile='v';
  IF v_stable<>4 OR v_volatile<>5 THEN
    RAISE EXCEPTION 'ASSERT H2: volatilidad lectura_STABLE=%/4, escritura_VOLATILE=%/5.', v_stable, v_volatile; END IF;

  -- H3: las 9 SECURITY INVOKER (prosecdef=false)
  SELECT count(*) INTO v_secdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname = ANY(v_lectura||v_escritura) AND p.prosecdef IS TRUE;
  IF v_secdef<>0 THEN RAISE EXCEPTION 'ASSERT H3: funciones SECURITY DEFINER=% (esperado 0, todas INVOKER).', v_secdef; END IF;

  -- H4 (hardening): 0 de las 9 abiertas a EXECUTE para Data API/PUBLIC
  SELECT count(*) INTO v_open FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname = ANY(v_lectura||v_escritura)
     AND (p.proacl IS NULL
          OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY(v_dataapi)));
  IF v_open<>0 THEN RAISE EXCEPTION 'ASSERT H4: funciones 9H abiertas a EXECUTE=% (esperado 0).', v_open; END IF;

  -- H5: tablas 9H siguen VACÍAS (crear funciones no las ejecuta)
  SELECT (SELECT count(*) FROM liquidaciones_periodo)+(SELECT count(*) FROM liquidacion_cascada)
        +(SELECT count(*) FROM liquidacion_socio)+(SELECT count(*) FROM movimientos_socio)
        +(SELECT count(*) FROM revaluaciones) INTO v_filas;
  IF v_filas<>0 THEN RAISE EXCEPTION 'ASSERT H5: filas en tablas 9H=% (esperado 0; el bloque no ejecuta funciones).', v_filas; END IF;

  -- H6: 3 secuencias siguen en 1 (is_called=false)
  SELECT (SELECT is_called FROM liquidaciones_periodo_id_liquidacion_seq)::int
       + (SELECT is_called FROM movimientos_socio_id_movimiento_seq)::int
       + (SELECT is_called FROM revaluaciones_id_revaluacion_seq)::int INTO v_seq_called;
  IF v_seq_called<>0 THEN RAISE EXCEPTION 'ASSERT H6: secuencias ya usadas=% (esperado 0).', v_seq_called; END IF;

  -- H7 (aislamiento): 9G sigue con 6 funciones (el DROP del bloque solo toca las 9 de 9H)
  SELECT count(*) INTO v_9g FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                       'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo');
  IF v_9g<>6 THEN RAISE EXCEPTION 'ASSERT H7: funciones 9G=% (esperado 6; aislamiento roto).', v_9g; END IF;

  -- H8 (aislamiento): EXCLUDE public sigue = 3
  SELECT count(*) INTO v_excl FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace
   WHERE con.contype='x' AND n.nspname='public';
  IF v_excl<>3 THEN RAISE EXCEPTION 'ASSERT H8: EXCLUDE en public=% (esperado 3).', v_excl; END IF;

  RAISE NOTICE 'ASSERTS H OK — 9 funciones (firmas exactas, INVOKER, sin EXECUTE), tablas vacías, 9G intacto. Listo para COMMIT.';
END
$assert$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN READ-ONLY POSTERIOR (fuera de la transacción).
-- ============================================================================
WITH dataapi AS (
  SELECT array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL) AS oids),
fr AS (SELECT unnest(ARRAY[
    'public.liquidacion_vigente(date)','public.saldo_corriente_socio(bigint)','public.mayor_socio(bigint)',
    'public.reporte_retribucion_operativo_periodo(date)','public.registrar_snapshot_periodo(date,numeric,text,bigint,text)',
    'public.registrar_retiro(bigint,date,numeric,text,text,text)',
    'public.registrar_movimiento_manual(bigint,date,text,numeric,text,text,date,text)',
    'public.registrar_reversa(bigint,date,text,text)',
    'public.registrar_revaluacion(bigint,date,numeric,numeric,text,text,bigint,text)']) AS sig),
m AS (
  SELECT
    (SELECT count(*) FROM fr WHERE to_regprocedure(fr.sig) IS NOT NULL) AS sig,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
       AND p.proname IN ('liquidacion_vigente','saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo') AND p.provolatile='s') AS lect_stable,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
       AND p.proname IN ('registrar_snapshot_periodo','registrar_retiro','registrar_movimiento_manual','registrar_reversa','registrar_revaluacion') AND p.provolatile='v') AS esc_vol,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace, dataapi WHERE n.nspname='public'
       AND p.proname IN ('liquidacion_vigente','saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo',
                         'registrar_snapshot_periodo','registrar_retiro','registrar_movimiento_manual','registrar_reversa','registrar_revaluacion')
       AND (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY(dataapi.oids)))) AS open_exec,
    ((SELECT count(*) FROM liquidaciones_periodo)+(SELECT count(*) FROM liquidacion_cascada)+(SELECT count(*) FROM liquidacion_socio)
      +(SELECT count(*) FROM movimientos_socio)+(SELECT count(*) FROM revaluaciones)) AS filas,
    ((SELECT is_called FROM liquidaciones_periodo_id_liquidacion_seq)::int+(SELECT is_called FROM movimientos_socio_id_movimiento_seq)::int
      +(SELECT is_called FROM revaluaciones_id_revaluacion_seq)::int) AS seq_called,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f'
       AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto','reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo')) AS g9,
    (SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE con.contype='x' AND n.nspname='public') AS excl
)
SELECT v.orden, v.chequeo, v.obtenido, v.esperado, CASE WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (1,'9 funciones 9H (firmas exactas)', m.sig::text,'9',(m.sig=9)),
  (2,'lectura STABLE', m.lect_stable::text,'4',(m.lect_stable=4)),
  (3,'escritura VOLATILE', m.esc_vol::text,'5',(m.esc_vol=5)),
  (4,'funciones 9H abiertas a EXECUTE', m.open_exec::text,'0',(m.open_exec=0)),
  (5,'tablas 9H vacías (no se ejecutaron)', m.filas::text,'0',(m.filas=0)),
  (6,'secuencias en 1 (is_called=false)', m.seq_called::text,'0',(m.seq_called=0)),
  (7,'9G intacto (6 funciones)', m.g9::text,'6',(m.g9=6)),
  (8,'EXCLUDE public', m.excl::text,'3',(m.excl=3))
) AS v(orden, chequeo, obtenido, esperado, ok)
UNION ALL
SELECT 999,'TOTAL H (9H funciones)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES (m.sig=9),(m.lect_stable=4),(m.esc_vol=5),(m.open_exec=0),(m.filas=0),(m.seq_called=0),(m.g9=6),(m.excl=3)) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES (m.sig=9),(m.lect_stable=4),(m.esc_vol=5),(m.open_exec=0),(m.filas=0),(m.seq_called=0),(m.g9=6),(m.excl=3)) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;

-- ============================================================================
-- REVERSIÓN CONCEPTUAL (NO ejecutar; sin CASCADE). Las 9 son funciones sueltas;
-- se eliminan sin afectar tablas (9H estructura) ni 9G.
-- ----------------------------------------------------------------------------
-- BEGIN;
--   DROP FUNCTION IF EXISTS registrar_revaluacion(BIGINT,DATE,NUMERIC,NUMERIC,TEXT,TEXT,BIGINT,TEXT);
--   DROP FUNCTION IF EXISTS registrar_reversa(BIGINT,DATE,TEXT,TEXT);
--   DROP FUNCTION IF EXISTS registrar_movimiento_manual(BIGINT,DATE,TEXT,NUMERIC,TEXT,TEXT,DATE,TEXT);
--   DROP FUNCTION IF EXISTS registrar_retiro(BIGINT,DATE,NUMERIC,TEXT,TEXT,TEXT);
--   DROP FUNCTION IF EXISTS registrar_snapshot_periodo(DATE,NUMERIC,TEXT,BIGINT,TEXT);
--   DROP FUNCTION IF EXISTS reporte_retribucion_operativo_periodo(DATE);
--   DROP FUNCTION IF EXISTS mayor_socio(BIGINT);
--   DROP FUNCTION IF EXISTS saldo_corriente_socio(BIGINT);
--   DROP FUNCTION IF EXISTS liquidacion_vigente(DATE);
-- COMMIT;
-- ============================================================================
