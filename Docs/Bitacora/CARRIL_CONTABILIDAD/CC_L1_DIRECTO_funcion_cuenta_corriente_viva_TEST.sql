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
