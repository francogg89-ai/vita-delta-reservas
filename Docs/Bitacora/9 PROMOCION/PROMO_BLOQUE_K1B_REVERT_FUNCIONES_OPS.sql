-- ============================================================================
-- PROMO_BLOQUE_K1B_REVERT_FUNCIONES_OPS.sql  (REVERT del parche K1B)
-- Restaura los cuerpos OPS pre-parche de las 4 funciones de Carril B.
-- Solo revierte formato/comentarios (las versiones son lógicamente idénticas).
-- Transacción única. Gate ambiente='ops' + gate huellas actuales = TEST (estado
-- post-parche; aborta si no se aplicó el parche). DROP sin CASCADE + CREATE OPS
-- + REVOKE EXECUTE + asserts (huella destino = OPS). Correr en OPS, nada seleccionado.
-- ============================================================================

BEGIN;

DO $gate_amb$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE ambiente: revert solo para OPS; encontrado ambiente=%', COALESCE(v_amb,'(null)');
  END IF;
END
$gate_amb$;

-- Gate huellas: deben estar en estado POST-parche (=TEST) para revertir
DO $gate_hash$
DECLARE h text;
BEGIN
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO h FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='resolver_beneficiario' AND pg_get_function_identity_arguments(p.oid)='p_id_cabana bigint, p_fecha date';
  IF h IS DISTINCT FROM 'e0f9daaaae4ac90766b2f87f148391fa' THEN RAISE EXCEPTION 'GATE revert resolver: actual % no es el estado post-parche TEST', COALESCE(h,'(ausente)'); END IF;
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO h FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='matriz_participacion' AND pg_get_function_identity_arguments(p.oid)='p_periodo date';
  IF h IS DISTINCT FROM 'a8260e228fffe68a74e1c1f6e3d4d0c6' THEN RAISE EXCEPTION 'GATE revert matriz: actual % no es post-parche TEST', COALESCE(h,'(ausente)'); END IF;
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO h FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='repartir_por_matriz' AND pg_get_function_identity_arguments(p.oid)='p_periodo date, p_monto numeric';
  IF h IS DISTINCT FROM '4084c9f79a354e77f4d48c197ce60ae8' THEN RAISE EXCEPTION 'GATE revert repartir: actual % no es post-parche TEST', COALESCE(h,'(ausente)'); END IF;
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO h FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='detalle_participacion' AND pg_get_function_identity_arguments(p.oid)='p_periodo date';
  IF h IS DISTINCT FROM 'a7e8e096b4ed91dda28d03abdb356e56' THEN RAISE EXCEPTION 'GATE revert detalle: actual % no es post-parche TEST', COALESCE(h,'(ausente)'); END IF;
END
$gate_hash$;

DROP FUNCTION public.detalle_participacion(date);
DROP FUNCTION public.repartir_por_matriz(date, numeric);
DROP FUNCTION public.matriz_participacion(date);
DROP FUNCTION public.resolver_beneficiario(bigint, date);

-- (1/4) resolver_beneficiario (OPS pre-parche)
CREATE FUNCTION public.resolver_beneficiario(p_id_cabana bigint, p_fecha date)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
  -- p_fecha se ignora en el MVP (seam): hoy devuelve el beneficiario estable.
  SELECT id_socio_beneficiario FROM cabanas WHERE id_cabana = p_id_cabana;
$function$;

-- (2/4) matriz_participacion (OPS pre-parche)
CREATE FUNCTION public.matriz_participacion(p_periodo date)
 RETURNS TABLE(id_socio bigint, valor_socio numeric, valor_pool numeric, participacion numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH mes AS (
    SELECT daterange(date_trunc('month', p_periodo)::date,
                     (date_trunc('month', p_periodo) + INTERVAL '1 month')::date, '[)') AS rango,
           date_trunc('month', p_periodo)::date AS inicio
  ),
  participantes AS (
    SELECT resolver_beneficiario(c.id_cabana, m.inicio) AS id_socio, c.valor_relativo
    FROM activaciones_operativas a
    JOIN cabanas c ON c.id_cabana = a.id_cabana
    CROSS JOIN mes m
    WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)') @> m.rango
  ),
  por_socio AS (SELECT id_socio, SUM(valor_relativo) AS valor_socio FROM participantes GROUP BY id_socio),
  total AS (SELECT SUM(valor_socio) AS valor_pool FROM por_socio)
  SELECT s.id_socio, s.valor_socio, t.valor_pool, (s.valor_socio / t.valor_pool) AS participacion
  FROM por_socio s CROSS JOIN total t
  WHERE t.valor_pool > 0
  ORDER BY participacion DESC, s.id_socio;
$function$;

-- (3/4) repartir_por_matriz (OPS pre-parche)
CREATE FUNCTION public.repartir_por_matriz(p_periodo date, p_monto numeric)
 RETURNS TABLE(id_socio bigint, participacion numeric, monto_asignado numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH base AS (
    SELECT m.id_socio, m.participacion, ROUND(p_monto * m.participacion, 2) AS monto_base
    FROM matriz_participacion(p_periodo) m
  ),
  resid AS (SELECT p_monto - COALESCE(SUM(monto_base),0) AS residual FROM base),
  ganador AS (
    SELECT b.id_socio FROM base b JOIN socios s ON s.id_socio = b.id_socio
    ORDER BY b.participacion DESC, (s.nombre = 'Rodrigo') DESC, b.id_socio ASC LIMIT 1
  )
  SELECT b.id_socio, b.participacion,
         b.monto_base + CASE WHEN b.id_socio = (SELECT id_socio FROM ganador)
                             THEN (SELECT residual FROM resid) ELSE 0 END AS monto_asignado
  FROM base b
  ORDER BY b.participacion DESC, b.id_socio;
$function$;

-- (4/4) detalle_participacion (OPS pre-parche)
CREATE FUNCTION public.detalle_participacion(p_periodo date)
 RETURNS TABLE(id_cabana bigint, cabana text, valor_relativo numeric, id_socio bigint, beneficiario text, participa boolean)
 LANGUAGE sql
 STABLE
AS $function$
  WITH mes AS (
    SELECT daterange(date_trunc('month', p_periodo)::date,
                     (date_trunc('month', p_periodo) + INTERVAL '1 month')::date, '[)') AS rango,
           date_trunc('month', p_periodo)::date AS inicio
  )
  SELECT c.id_cabana, c.nombre, c.valor_relativo,
         resolver_beneficiario(c.id_cabana, m.inicio) AS id_socio, s.nombre,
         EXISTS (SELECT 1 FROM activaciones_operativas a
                 WHERE a.id_cabana = c.id_cabana
                   AND daterange(a.fecha_desde, a.fecha_hasta, '[)') @> m.rango) AS participa
  FROM cabanas c CROSS JOIN mes m
  JOIN socios s ON s.id_socio = resolver_beneficiario(c.id_cabana, m.inicio)
  ORDER BY c.id_cabana;
$function$;

REVOKE EXECUTE ON FUNCTION public.resolver_beneficiario(bigint, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.matriz_participacion(date)          FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.repartir_por_matriz(date, numeric)  FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.detalle_participacion(date)         FROM PUBLIC, anon, authenticated, service_role;

DO $rev$
DECLARE v_def text;
BEGIN
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='resolver_beneficiario';
  IF v_def <> '608e48f4168ee73da9215317312efbd1' THEN RAISE EXCEPTION 'REVERT huella resolver: % != OPS 608e48f4', v_def; END IF;
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='matriz_participacion';
  IF v_def <> '1dfe6f6ab6f67def77ec5587cbbe8680' THEN RAISE EXCEPTION 'REVERT huella matriz: % != OPS 1dfe6f6a', v_def; END IF;
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='repartir_por_matriz';
  IF v_def <> '4d3aacf4c57d36d85d9e35e551350e91' THEN RAISE EXCEPTION 'REVERT huella repartir: % != OPS 4d3aacf4', v_def; END IF;
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='detalle_participacion';
  IF v_def <> '3fd7c76e32f998830021f1badb6e7b7b' THEN RAISE EXCEPTION 'REVERT huella detalle: % != OPS 3fd7c76e', v_def; END IF;
  RAISE NOTICE 'Revert OK: las 4 funciones volvieron a las huellas OPS pre-parche.';
END
$rev$;

COMMIT;
