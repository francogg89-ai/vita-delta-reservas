-- ============================================================================
-- CC_L2_DIRECTO_funcion_cuenta_corriente_detalle   --   ENTORNO: TEST
-- Frente Cuenta corriente de socios / L2 "drill-down" - bloque directo.
-- ----------------------------------------------------------------------------
-- QUE HACE
--   Para un mes dado, devuelve UN jsonb con el desglose completo del "por que":
--     * cascada               : los 11 pasos de cascada_periodo(mes, pct)
--                               (1-8 agregados con id_socio null; 9-11 por socio).
--     * matriz                : participacion por socio (matriz_participacion + nombre).
--     * matriz_cabanas         : detalle por cabana (detalle_participacion): valor_relativo,
--                               beneficiario y si participa (cubre el mes completo) ese mes.
--     * incidencias            : por gasto del mes, a quien le pega y con que regla
--                               (gastos_internos del periodo x incidencia_gasto).
--     * gastos_sin_incidencia  : gastos que NO inciden (pool vacio, motivo).
--   Es SOLO composicion de funciones canonicas ya existentes (exponer, no construir).
--
-- READ-ONLY: STABLE, SECURITY INVOKER, no escribe, no consume secuencias, no toca fotos.
--
-- DEPENDENCIAS (canonicas): cascada_periodo, matriz_participacion, detalle_participacion,
--   incidencia_gasto, gastos_sin_incidencia_periodo, gastos_internos, socios.
--
-- PARAMETROS
--   p_mes           : mes a desglosar; se trunca a primer dia. NULL => mes actual AR
--                     (expresion timezone inline; NO fecha_hoy_ar(), para no acoplar al
--                     motor de horarios, igual que en L1). El floor contable NO se aplica aca
--                     (la cascada trabaja el mes crudo); el wrapper valida mes in [piso, actual].
--   p_pct_operativo : requerido; guard [0,1]. Si invalido devuelve
--                     { "mes": ..., "error": "PARAMETRO_INVALIDO_PCT_OPERATIVO" } (2da defensa;
--                     el wrapper hardcodea 0.25). El default NULL fuerza pct explicito.
--
-- FORMA jsonb (exito):
--   { "mes":"YYYY-MM-01",
--     "cascada":[{paso,concepto,id_socio,socio,monto}],
--     "matriz":[{id_socio,socio,valor_socio,valor_pool,participacion}],
--     "matriz_cabanas":[{id_cabana,cabana,valor_relativo,id_socio,beneficiario,participa}],
--     "incidencias":[{id_gasto,clase,etiqueta,monto,destino,id_socio,socio,monto_incidido,regla}],
--     "gastos_sin_incidencia":[{id_gasto,clase,etiqueta,monto,motivo}] }
--   Secciones vacias => [] (nunca null).
-- ============================================================================

DROP FUNCTION IF EXISTS public.cuenta_corriente_detalle(date, numeric);

CREATE FUNCTION public.cuenta_corriente_detalle(
  p_mes           date    DEFAULT NULL,
  p_pct_operativo numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
  WITH params AS (
    SELECT date_trunc('month',
             COALESCE(p_mes, (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date)
           )::date AS mes,
           (p_pct_operativo IS NULL
            OR p_pct_operativo < 0
            OR p_pct_operativo > 1) AS pct_invalido
  )
  SELECT CASE WHEN pr.pct_invalido THEN
      jsonb_build_object('mes', pr.mes, 'error', 'PARAMETRO_INVALIDO_PCT_OPERATIVO')
    ELSE
      jsonb_build_object(
        'mes', pr.mes,
        'cascada', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'paso', c.paso, 'concepto', c.concepto,
                   'id_socio', c.id_socio, 'socio', c.socio, 'monto', c.monto)
                 ORDER BY c.paso, c.id_socio NULLS FIRST)
          FROM cascada_periodo(pr.mes, p_pct_operativo) c), '[]'::jsonb),
        'matriz', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_socio', m.id_socio, 'socio', s.nombre,
                   'valor_socio', m.valor_socio, 'valor_pool', m.valor_pool,
                   'participacion', m.participacion)
                 ORDER BY m.participacion DESC, m.id_socio)
          FROM matriz_participacion(pr.mes) m
          JOIN socios s ON s.id_socio = m.id_socio), '[]'::jsonb),
        'matriz_cabanas', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_cabana', d.id_cabana, 'cabana', d.cabana,
                   'valor_relativo', d.valor_relativo, 'id_socio', d.id_socio,
                   'beneficiario', d.beneficiario, 'participa', d.participa)
                 ORDER BY d.id_cabana)
          FROM detalle_participacion(pr.mes) d), '[]'::jsonb),
        'incidencias', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_gasto', g.id_gasto, 'clase', g.clase, 'etiqueta', g.etiqueta,
                   'monto', g.monto, 'destino', i.destino, 'id_socio', i.id_socio,
                   'socio', i.socio, 'monto_incidido', i.monto, 'regla', i.regla)
                 ORDER BY g.id_gasto, i.id_socio NULLS FIRST)
          FROM gastos_internos g
          CROSS JOIN LATERAL incidencia_gasto(g.id_gasto) i
          WHERE g.periodo = pr.mes), '[]'::jsonb),
        'gastos_sin_incidencia', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id_gasto', x.id_gasto, 'clase', x.clase, 'etiqueta', x.etiqueta,
                   'monto', x.monto, 'motivo', x.motivo)
                 ORDER BY x.id_gasto)
          FROM gastos_sin_incidencia_periodo(pr.mes) x), '[]'::jsonb)
      )
  END
  FROM params pr;
$function$;

-- Hardening (mismo criterio que Carril B / L1): solo el owner ejecuta.
REVOKE EXECUTE ON FUNCTION public.cuenta_corriente_detalle(date, numeric)
  FROM PUBLIC, anon, authenticated, service_role;
