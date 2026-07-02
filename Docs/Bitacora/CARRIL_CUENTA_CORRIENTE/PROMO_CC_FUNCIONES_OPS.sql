-- ============================================================================
-- PROMO_CC_FUNCIONES_OPS.sql   --   ENTORNO: OPS
-- Promocion a OPS de las 2 funciones de lectura de la cuenta corriente (L1 + L2).
-- DDL environment-agnostic: IDENTICO al validado en TEST. Read-only (STABLE,
-- SECURITY INVOKER, revocadas de PUBLIC/anon/authenticated/service_role).
-- Idempotente (DROP+CREATE); re-ejecutable sin dano. No escribe datos, no consume
-- secuencias. Correr en el SQL Editor de OPS con NADA seleccionado.
--
-- ANTES DE EJECUTAR: confirma que estas en el proyecto OPS. El PRE-CHECK de abajo
-- (seleccionalo solo y corrilo) debe devolver 'ops'.
-- ============================================================================

-- PRE-CHECK (seleccionar esta linea y ejecutar; debe decir 'ops'):
SELECT valor AS ambiente_actual FROM configuracion_general WHERE clave = 'ambiente';

-- ============================ L1 ============================
-- ============================================================================
-- CC_L1_DIRECTO_funcion_cuenta_corriente_viva   --   ENTORNO: TEST
-- Frente: Cuenta corriente de socios (lecturas read-only) - Bloque L1 "directo".
-- ----------------------------------------------------------------------------
-- QUE HACE
--   Devuelve, por socio, el saldo de cuenta corriente ACUMULADO EN VIVO desde el
--   piso contable (2026-07-01, D-NEG-02) hasta p_hasta_fecha (default = hoy AR).
--   Suma mes a mes la salida de saldo_socios_periodo(mes, pct), separando:
--     - liquidacion_meses_previos : Sigma saldo_final de jul..(mes_actual-1), en vivo
--     - liquidacion_mes_en_curso  : saldo_final del mes en curso (PROVISORIO: el mes no termino)
--     - reembolsos_acumulados     : Sigma desembolsado_periodo (plata que puso un socio; NO es ganancia)
--     - movimientos               : Sigma movimientos_socio con signo (retiros/adelantos/ajustes)
--   saldo_al_dia = suma de las cuatro. Es la MISMA formula del saldo vivo de 9H:
--   Sigma saldo_final + Sigma desembolsado + Sigma movimientos (coherente con
--   saldo_corriente_socio y con el tope de registrar_retiro).
--
-- POR QUE ACUMULA Y NO SE REINICIA
--   La cuenta corriente crece desde julio como un saldo bancario; el reparto anual
--   (jun-2027) es exactamente este acumulado al 30-jun-2027. El pool estacional se
--   respeta: cada mes reparte con SU matriz (verano con Guatemala, resto sin ella).
--
-- READ-ONLY PURO
--   STABLE, SECURITY INVOKER, no escribe, no consume secuencias, no toca fotos (9H).
--   Cuando exista el frente de congelado, los meses previos se leeran de la foto y
--   solo el mes en curso quedara en vivo: cambio localizado, no reescritura.
--
-- DEPENDENCIAS (todas canonicas v1.9.0)
--   saldo_socios_periodo(date,numeric), movimientos_socio, socios.
--   NO usa fecha_hoy_ar() a proposito (ese helper es TEST-only del motor de horarios):
--   usa la expresion timezone inline para no acoplar este frente a esa promocion.
--
-- GUARD DE pct
--   Si p_pct_operativo es NULL o esta fuera de [0,1], devuelve UNA fila marcadora
--   (id_socio NULL, socio 'PARAMETRO_INVALIDO_PCT_OPERATIVO'), mismo patron que
--   cascada_periodo / saldo_socios_periodo (2da defensa; el gateway ya valida
--   antes de firmar). El default NULL fuerza pct explicito (no se hardcodea 0.25).
--
-- FLOOR 2026-07-01 (D-NEG-02)
--   Se respeta naturalmente: la serie de meses ARRANCA en el piso; nunca hay meses
--   previos que sumar. Si p_hasta_fecha < piso, la serie es vacia -> 0 filas.
-- ============================================================================

DROP FUNCTION IF EXISTS public.cuenta_corriente_viva(date, numeric);

CREATE FUNCTION public.cuenta_corriente_viva(
  p_hasta_fecha   date    DEFAULT NULL,   -- NULL = hoy AR (America/Argentina/Buenos_Aires)
  p_pct_operativo numeric DEFAULT NULL    -- requerido; guard [0,1]
)
RETURNS TABLE(
  id_socio                  bigint,
  socio                     text,
  liquidacion_meses_previos numeric,
  liquidacion_mes_en_curso  numeric,
  reembolsos_acumulados     numeric,
  movimientos               numeric,
  saldo_al_dia              numeric
)
LANGUAGE sql
STABLE
AS $function$
  WITH params AS (
    SELECT
      DATE '2026-07-01' AS piso_contable,                              -- D-NEG-02
      COALESCE(p_hasta_fecha,
               (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date) AS hasta_efectiva,
      date_trunc('month',
        COALESCE(p_hasta_fecha,
                 (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date)
      )::date AS mes_actual,
      (p_pct_operativo IS NULL
       OR p_pct_operativo < 0
       OR p_pct_operativo > 1) AS pct_invalido
  ),
  meses AS (
    SELECT gs::date AS mes, pr.mes_actual
    FROM params pr
    CROSS JOIN LATERAL generate_series(
      pr.piso_contable::timestamp, pr.mes_actual::timestamp, INTERVAL '1 month'
    ) AS gs
    WHERE NOT pr.pct_invalido
  ),
  por_mes AS (
    SELECT m.mes,
           (m.mes = m.mes_actual) AS es_en_curso,
           s.id_socio,
           s.saldo_final,
           s.desembolsado_periodo
    FROM meses m
    CROSS JOIN LATERAL saldo_socios_periodo(m.mes, p_pct_operativo) s
    WHERE s.id_socio IS NOT NULL
  ),
  agg AS (
    SELECT id_socio,
           COALESCE(SUM(saldo_final) FILTER (WHERE NOT es_en_curso), 0) AS liq_previos,
           COALESCE(SUM(saldo_final) FILTER (WHERE es_en_curso), 0)     AS liq_en_curso,
           COALESCE(SUM(desembolsado_periodo), 0)                       AS reembolsos
    FROM por_mes
    GROUP BY id_socio
  ),
  mov AS (
    -- ventana as-of: solo movimientos dentro del rango contable [piso, hasta_efectiva].
    -- Coincide con "todos" en el caso de produccion (hasta = hoy) y da vacio limpio si hasta < piso.
    SELECT m.id_socio, COALESCE(SUM(m.monto), 0) AS movimientos
    FROM movimientos_socio m
    CROSS JOIN params pr
    WHERE NOT pr.pct_invalido
      AND m.fecha >= pr.piso_contable
      AND m.fecha <= pr.hasta_efectiva
    GROUP BY m.id_socio
  ),
  universo AS (
    SELECT id_socio FROM agg
    UNION
    SELECT id_socio FROM mov
  )
  -- Guard pct invalido: fila marcadora unica (id_socio NULL)
  SELECT NULL::bigint,
         'PARAMETRO_INVALIDO_PCT_OPERATIVO'::text,
         NULL::numeric, NULL::numeric, NULL::numeric, NULL::numeric, NULL::numeric
  FROM params pr
  WHERE pr.pct_invalido

  UNION ALL

  SELECT u.id_socio,
         s.nombre,
         COALESCE(a.liq_previos, 0),
         COALESCE(a.liq_en_curso, 0),
         COALESCE(a.reembolsos, 0),
         COALESCE(mv.movimientos, 0),
         COALESCE(a.liq_previos, 0)
           + COALESCE(a.liq_en_curso, 0)
           + COALESCE(a.reembolsos, 0)
           + COALESCE(mv.movimientos, 0)
  FROM universo u
  JOIN socios s    ON s.id_socio = u.id_socio
  LEFT JOIN agg a  ON a.id_socio = u.id_socio
  LEFT JOIN mov mv ON mv.id_socio = u.id_socio
  CROSS JOIN params pr
  WHERE NOT pr.pct_invalido

  ORDER BY 1 NULLS FIRST;   -- posicional: evita colision con el parametro OUT id_socio en el UNION
$function$;

-- Hardening (mismo criterio que Carril B C12): solo el owner ejecuta. El nodo
-- Postgres del wrapper corre como owner y puede leer las funciones/tablas revocadas.
REVOKE EXECUTE ON FUNCTION public.cuenta_corriente_viva(date, numeric)
  FROM PUBLIC, anon, authenticated, service_role;


-- ============================ L2 ============================
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
