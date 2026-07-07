-- ============================================================================
-- L3_05a_DDL_FUNCIONES_OPS.sql   (ESCRIBE DDL; transaccional; gate OPS)
-- Crea las 2 funciones de lectura L3 sobre la foto congelada 9H:
--   * cuenta_corriente_historico(p_mes date)      -> jsonb (detalle de un mes)
--   * cuenta_corriente_historico_acumulados()     -> jsonb (acumulados globales)
-- Patron: DROP FUNCTION + CREATE FUNCTION + REVOKE EXECUTE (L-CC-07).
-- Ambas: LANGUAGE sql, STABLE, SECURITY INVOKER, SET search_path fijo.
-- Solo LECTURA de fotos vigentes; NO escriben; NO tocan L1/L2/retiros.
-- OPS-only (gate). Si el gate falla, ROLLBACK: no crea/reemplaza nada.
-- Cuerpos IDENTICOS a la version TEST (funciones agnosticas al ambiente); solo
-- cambia el gate. En OPS greenfield estas funciones devuelven sin_foto/sin_datos
-- hasta el primer cierre real (validado por el smoke L3_05b).
--
-- Convencion de signos (fiel a la foto congelada, sin transformar):
--   ingresos (paso1/paso6) positivos; gastos (paso2 clase A, paso7 clase C,
--   gastos_d/gastos_e de socios clases D/E) NEGATIVOS (deducciones); utilidad
--   (paso8 base_de_ganancia) neta con su signo; retiros con su signo (negativo).
-- ============================================================================
BEGIN;
DO $gate$ BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave='ambiente') IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE OPS-only: ambiente actual = %', COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(sin clave)');
  END IF;
END $gate$;

-- ---------------------------------------------------------------------------
-- L3-detalle: foto de UN mes (resuelve la vigente via liquidacion_vigente).
-- 3 casos: (A) foto con detalle, (B) foto pre-extension, (C) sin foto vigente.
-- La rama "foto existe" resuelve A y B con la MISMA construccion: las secciones
-- de detalle fino salen [] solas cuando la foto es pre-extension (tablas de
-- detalle vacias para ese id). detalle_disponible/detalle_motivo se derivan de
-- la cardinalidad de participacion (0 filas <=> pre-extension).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.cuenta_corriente_historico(date);
CREATE FUNCTION public.cuenta_corriente_historico(p_mes date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
  WITH resolved AS (
    SELECT date_trunc('month', p_mes)::date AS mes,
           liquidacion_vigente(date_trunc('month', p_mes)::date) AS id_liq
  ),
  info AS (
    SELECT r.mes, r.id_liq,
           (r.id_liq IS NULL) AS sin_foto,
           COALESCE((SELECT count(*) FROM liquidacion_participacion pa
                     WHERE pa.id_liquidacion = r.id_liq), 0) AS n_part
    FROM resolved r
  )
  SELECT CASE
    WHEN i.sin_foto THEN
      jsonb_build_object(
        'sin_foto', true,
        'detalle_disponible', false,
        'detalle_motivo', 'sin_foto_vigente',
        'periodo', i.mes,
        'cabecera', NULL,
        'cascada', '[]'::jsonb,
        'socios', '[]'::jsonb,
        'participacion', '[]'::jsonb,
        'gastos', '[]'::jsonb,
        'incidencias', '[]'::jsonb,
        'movimientos', '[]'::jsonb,
        'matriz_por_socio', '[]'::jsonb,
        'gastos_sin_incidencia', '[]'::jsonb,
        'retribucion_operativo', NULL
      )
    ELSE
      jsonb_build_object(
        'sin_foto', false,
        'detalle_disponible', (i.n_part > 0),
        'detalle_motivo', CASE WHEN i.n_part > 0 THEN NULL ELSE 'foto_pre_extension' END,
        'periodo', i.mes,
        'cabecera', (
          SELECT jsonb_build_object(
                   'id_liquidacion', lp.id_liquidacion,
                   'periodo', lp.periodo,
                   'pct_operativo', lp.pct_operativo,
                   'creado_por', lp.creado_por,
                   'created_at', lp.created_at,
                   'comentario', lp.comentario,
                   'linaje', jsonb_build_object(
                     'es_raiz', (lp.id_liquidacion_supersede IS NULL),
                     'id_liquidacion_supersede', lp.id_liquidacion_supersede))
          FROM liquidaciones_periodo lp WHERE lp.id_liquidacion = i.id_liq),
        -- cascada: presente para toda foto (tabla original 9G/9H)
        'cascada', COALESCE((
          SELECT jsonb_agg(jsonb_build_object('paso', c.paso, 'concepto', c.concepto, 'monto', c.monto)
                 ORDER BY c.paso)
          FROM liquidacion_cascada c WHERE c.id_liquidacion = i.id_liq), '[]'::jsonb),
        -- socios: presente para toda foto (tabla original 9H)
        'socios', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_socio', ls.id_socio, 'socio', s.nombre,
                   'saldo_bruto', ls.saldo_bruto, 'gastos_d', ls.gastos_d, 'gastos_e', ls.gastos_e,
                   'saldo_final', ls.saldo_final, 'desembolsado_periodo', ls.desembolsado_periodo)
                 ORDER BY ls.id_socio)
          FROM liquidacion_socio ls JOIN socios s ON s.id_socio = ls.id_socio
          WHERE ls.id_liquidacion = i.id_liq), '[]'::jsonb),
        -- participacion (detalle fino): [] si pre-extension
        'participacion', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_cabana', pa.id_cabana, 'cabana', cb.nombre,
                   'valor_relativo', pa.valor_relativo, 'id_socio_beneficiario', pa.id_socio_beneficiario,
                   'beneficiario', sb.nombre, 'participa', pa.participa)
                 ORDER BY pa.id_cabana)
          FROM liquidacion_participacion pa
          JOIN cabanas cb ON cb.id_cabana = pa.id_cabana
          JOIN socios sb ON sb.id_socio = pa.id_socio_beneficiario
          WHERE pa.id_liquidacion = i.id_liq), '[]'::jsonb),
        -- gastos (detalle fino): [] si pre-extension
        'gastos', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_gasto', g.id_gasto, 'fecha', g.fecha, 'clase', g.clase,
                   'clase_sugerida', g.clase_sugerida, 'etiqueta', g.etiqueta, 'monto', g.monto,
                   'moneda', g.moneda, 'id_zona', g.id_zona, 'id_cabana', g.id_cabana,
                   'pagador_tipo', g.pagador_tipo, 'id_socio_pagador', g.id_socio_pagador,
                   'medio_pago', g.medio_pago, 'comentario', g.comentario, 'comprobante_url', g.comprobante_url,
                   'creado_por', g.creado_por, 'created_at', g.created_at,
                   'sin_incidencia', g.sin_incidencia, 'motivo_sin_incidencia', g.motivo_sin_incidencia)
                 ORDER BY g.id_gasto)
          FROM liquidacion_gasto g WHERE g.id_liquidacion = i.id_liq), '[]'::jsonb),
        -- incidencias (detalle fino): respeta seq congelado
        'incidencias', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_gasto', ic.id_gasto, 'seq', ic.seq, 'destino', ic.destino,
                   'id_socio', ic.id_socio, 'socio', si.nombre,
                   'monto_incidido', ic.monto_incidido, 'regla', ic.regla)
                 ORDER BY ic.id_gasto, ic.seq)
          FROM liquidacion_incidencia ic LEFT JOIN socios si ON si.id_socio = ic.id_socio
          WHERE ic.id_liquidacion = i.id_liq), '[]'::jsonb),
        -- movimientos del mes: LECTURA VIVA del mayor, ventaneada por fecha
        -- [mes, mes+1 mes); NO forma parte de la foto congelada (mayor aparte).
        'movimientos', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_movimiento', m.id_movimiento, 'id_socio', m.id_socio, 'socio', sm.nombre,
                   'fecha', m.fecha, 'tipo', m.tipo, 'monto', m.monto,
                   'medio_pago', m.medio_pago, 'comentario', m.comentario, 'periodo', m.periodo)
                 ORDER BY m.fecha, m.id_movimiento)
          FROM movimientos_socio m JOIN socios sm ON sm.id_socio = m.id_socio
          WHERE m.fecha >= i.mes AND m.fecha < (i.mes + INTERVAL '1 month')), '[]'::jsonb),
        -- matriz_por_socio: DERIVADA de participacion (no reimplementa vivas)
        'matriz_por_socio', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_socio', x.id_socio, 'socio', s.nombre,
                   'valor_socio', x.valor_socio, 'valor_pool', x.pool,
                   'participacion', CASE WHEN x.pool > 0 THEN round(x.valor_socio / x.pool, 4) ELSE 0 END)
                 ORDER BY x.valor_socio DESC, x.id_socio)
          FROM (
            SELECT pa.id_socio_beneficiario AS id_socio,
                   SUM(pa.valor_relativo) AS valor_socio,
                   SUM(SUM(pa.valor_relativo)) OVER () AS pool
            FROM liquidacion_participacion pa
            WHERE pa.id_liquidacion = i.id_liq AND pa.participa = true
            GROUP BY pa.id_socio_beneficiario
          ) x
          JOIN socios s ON s.id_socio = x.id_socio), '[]'::jsonb),
        -- gastos_sin_incidencia: DERIVADO (filtro sobre liquidacion_gasto)
        'gastos_sin_incidencia', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_gasto', g.id_gasto, 'clase', g.clase, 'etiqueta', g.etiqueta,
                   'monto', g.monto, 'motivo', g.motivo_sin_incidencia)
                 ORDER BY g.id_gasto)
          FROM liquidacion_gasto g WHERE g.id_liquidacion = i.id_liq AND g.sin_incidencia = true), '[]'::jsonb),
        -- retribucion_operativo: conciliacion del paso 4 (presente en A y B)
        'retribucion_operativo', (
          SELECT jsonb_build_object(
                   'periodo', rr.periodo, 'calculado', rr.calculado, 'asignado', rr.asignado,
                   'diferencia', rr.diferencia, 'estado', rr.estado)
          FROM reporte_retribucion_operativo_periodo(i.mes) rr)
      )
  END
  FROM info i;
$function$;

REVOKE EXECUTE ON FUNCTION public.cuenta_corriente_historico(date) FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- L3-acumulados: agregados globales sobre TODAS las fotos vigentes + mayor.
-- Reutiliza saldo_corriente_socio VERBATIM (sin filtro de piso; suma todos los
-- movimientos). El piso NO se doble-filtra; se expone como check en meta.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.cuenta_corriente_historico_acumulados();
CREATE FUNCTION public.cuenta_corriente_historico_acumulados()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
  WITH piso AS (SELECT DATE '2026-07-01' AS d),   -- D-NEG-02 (piso contable)
  vig AS (
    SELECT lp.id_liquidacion, lp.periodo
    FROM liquidaciones_periodo lp
    WHERE NOT EXISTS (SELECT 1 FROM liquidaciones_periodo s
                      WHERE s.id_liquidacion_supersede = lp.id_liquidacion)
  ),
  casc AS (SELECT v.id_liquidacion, c.paso, c.monto
           FROM vig v JOIN liquidacion_cascada c ON c.id_liquidacion = v.id_liquidacion),
  soc AS (SELECT v.id_liquidacion, ls.saldo_bruto, ls.gastos_d, ls.gastos_e
          FROM vig v JOIN liquidacion_socio ls ON ls.id_liquidacion = v.id_liquidacion),
  evo AS (
    SELECT v.periodo, v.id_liquidacion,
      COALESCE((SELECT SUM(c.monto) FROM casc c WHERE c.id_liquidacion = v.id_liquidacion AND c.paso IN (1,6)),0) AS ingresos,
      COALESCE((SELECT SUM(c.monto) FROM casc c WHERE c.id_liquidacion = v.id_liquidacion AND c.paso IN (2,7)),0)
        + COALESCE((SELECT SUM(x.gastos_d + x.gastos_e) FROM soc x WHERE x.id_liquidacion = v.id_liquidacion),0) AS gastos,
      COALESCE((SELECT SUM(c.monto) FROM casc c WHERE c.id_liquidacion = v.id_liquidacion AND c.paso = 8),0) AS utilidad,
      COALESCE((SELECT SUM(x.saldo_bruto) FROM soc x WHERE x.id_liquidacion = v.id_liquidacion),0) AS repartos,
      COALESCE((SELECT SUM(m.monto) FROM movimientos_socio m
                WHERE m.tipo = 'retiro' AND m.fecha >= v.periodo AND m.fecha < (v.periodo + INTERVAL '1 month')),0) AS retiros_mes
    FROM vig v
  )
  SELECT jsonb_build_object(
    'sin_datos', (SELECT count(*) FROM vig) = 0,
    'piso', (SELECT d FROM piso),
    'totales', jsonb_build_object(
      'ingresos_acumulados', COALESCE((SELECT SUM(ingresos) FROM evo),0),
      'gastos_acumulados',
        COALESCE((SELECT SUM(monto) FROM casc WHERE paso IN (2,7)),0)
        + COALESCE((SELECT SUM(gastos_d + gastos_e) FROM soc),0),
      'gastos_desglose', jsonb_build_object(
        'a_paso2',    COALESCE((SELECT SUM(monto) FROM casc WHERE paso = 2),0),
        'c_paso7',    COALESCE((SELECT SUM(monto) FROM casc WHERE paso = 7),0),
        'd_e_socios', COALESCE((SELECT SUM(gastos_d + gastos_e) FROM soc),0)
      ),
      'utilidad_acumulada',  COALESCE((SELECT SUM(monto) FROM casc WHERE paso = 8),0),
      'repartos_acumulados', COALESCE((SELECT SUM(saldo_bruto) FROM soc),0),
      'retiros_acumulados',  COALESCE((SELECT SUM(monto) FROM movimientos_socio WHERE tipo = 'retiro'),0)
    ),
    'evolucion', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'periodo', e.periodo, 'id_liquidacion', e.id_liquidacion,
               'ingresos', e.ingresos, 'gastos', e.gastos, 'utilidad', e.utilidad,
               'repartos', e.repartos, 'retiros_mes', e.retiros_mes)
             ORDER BY e.periodo)
      FROM evo e), '[]'::jsonb),
    'saldos_por_socio', COALESCE((
      SELECT jsonb_agg(x.obj ORDER BY x.id_socio)
      FROM (
        SELECT s.id_socio,
          jsonb_build_object(
            'id_socio', s.id_socio, 'socio', s.nombre,
            'resultado_liquidacion', MAX(sc.monto) FILTER (WHERE sc.orden = 1),
            'reembolso_desembolso',  MAX(sc.monto) FILTER (WHERE sc.orden = 2),
            'movimientos',           MAX(sc.monto) FILTER (WHERE sc.orden = 3),
            'saldo_vivo',            MAX(sc.monto) FILTER (WHERE sc.orden = 4)) AS obj
        FROM socios s
        CROSS JOIN LATERAL saldo_corriente_socio(s.id_socio) sc
        GROUP BY s.id_socio, s.nombre
      ) x), '[]'::jsonb),
    'meta', jsonb_build_object(
      'fotos_vigentes', (SELECT count(*) FROM vig),
      'fotos_pre_piso', (SELECT count(*) FROM vig WHERE periodo < (SELECT d FROM piso)),
      'movimientos_pre_piso', (SELECT count(*) FROM movimientos_socio WHERE fecha < (SELECT d FROM piso))
    )
  );
$function$;

REVOKE EXECUTE ON FUNCTION public.cuenta_corriente_historico_acumulados() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
