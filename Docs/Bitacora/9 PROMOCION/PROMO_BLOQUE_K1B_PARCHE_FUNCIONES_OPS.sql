-- ============================================================================
-- PROMO_BLOQUE_K1B_PARCHE_FUNCIONES_OPS.sql
-- Alineación de las 4 funciones de Carril B en OPS a la definición CANÓNICA de TEST.
-- Diferencia probada 100% cosmética (comentarios/formato + 1 alias redundante en
-- detalle_participacion que no altera la salida en RETURNS TABLE). Cero cambio lógico.
-- Objetivo: paridad K1 byte a byte + adoptar los comentarios documentados de TEST.
--
-- Transacción única. Gates: ambiente='ops' + huellas def actuales OPS (no pisar
-- algo inesperado). DROP sin CASCADE (orden inverso) + CREATE (orden de dependencia)
-- con la definición EXACTA de TEST + REVOKE EXECUTE. Asserts de atributos, huella
-- destino (=TEST) y funcionales. Verificación posterior read-only. Reversión: ver
-- companion PROMO_BLOQUE_K1B_REVERT_FUNCIONES_OPS.sql (sin CASCADE).
--
-- Correr en OPS con NADA seleccionado.
-- ============================================================================

BEGIN;

-- ── Gate 1: ambiente debe ser 'ops' ─────────────────────────────────────────
DO $gate_amb$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE ambiente: este parche es solo para OPS; encontrado ambiente=%', COALESCE(v_amb,'(null)');
  END IF;
END
$gate_amb$;

-- ── Gate 2: huellas def ACTUALES de OPS — abortar si no son las esperadas ────
--    (protege contra pisar una versión modificada fuera de banda)
DO $gate_hash$
DECLARE h text;
BEGIN
  SELECT md5(replace(pg_get_functiondef(p.oid), E'\r','')) INTO h
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='resolver_beneficiario'
      AND pg_get_function_identity_arguments(p.oid)='p_id_cabana bigint, p_fecha date';
  IF h IS DISTINCT FROM '608e48f4168ee73da9215317312efbd1' THEN
    RAISE EXCEPTION 'GATE huella resolver_beneficiario: actual % != esperada OPS 608e48f4168ee73da9215317312efbd1', COALESCE(h,'(ausente)');
  END IF;

  SELECT md5(replace(pg_get_functiondef(p.oid), E'\r','')) INTO h
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='matriz_participacion'
      AND pg_get_function_identity_arguments(p.oid)='p_periodo date';
  IF h IS DISTINCT FROM '1dfe6f6ab6f67def77ec5587cbbe8680' THEN
    RAISE EXCEPTION 'GATE huella matriz_participacion: actual % != esperada OPS 1dfe6f6ab6f67def77ec5587cbbe8680', COALESCE(h,'(ausente)');
  END IF;

  SELECT md5(replace(pg_get_functiondef(p.oid), E'\r','')) INTO h
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='repartir_por_matriz'
      AND pg_get_function_identity_arguments(p.oid)='p_periodo date, p_monto numeric';
  IF h IS DISTINCT FROM '4d3aacf4c57d36d85d9e35e551350e91' THEN
    RAISE EXCEPTION 'GATE huella repartir_por_matriz: actual % != esperada OPS 4d3aacf4c57d36d85d9e35e551350e91', COALESCE(h,'(ausente)');
  END IF;

  SELECT md5(replace(pg_get_functiondef(p.oid), E'\r','')) INTO h
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='detalle_participacion'
      AND pg_get_function_identity_arguments(p.oid)='p_periodo date';
  IF h IS DISTINCT FROM '3fd7c76e32f998830021f1badb6e7b7b' THEN
    RAISE EXCEPTION 'GATE huella detalle_participacion: actual % != esperada OPS 3fd7c76e32f998830021f1badb6e7b7b', COALESCE(h,'(ausente)');
  END IF;

  RAISE NOTICE 'Gate huellas OPS: las 4 funciones están en el estado pre-parche esperado.';
END
$gate_hash$;

-- ── DROP (orden inverso de dependencia), SIN CASCADE ────────────────────────
DROP FUNCTION public.detalle_participacion(date);
DROP FUNCTION public.repartir_por_matriz(date, numeric);
DROP FUNCTION public.matriz_participacion(date);
DROP FUNCTION public.resolver_beneficiario(bigint, date);

-- ── CREATE (orden de dependencia) con la definición EXACTA de TEST ───────────
-- (1/4) resolver_beneficiario
CREATE FUNCTION public.resolver_beneficiario(p_id_cabana bigint, p_fecha date)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
  -- p_fecha se ignora en el MVP (seam D-9C-18): hoy devuelve el beneficiario
  -- estable; el dia que haya titularidad por rango, se cambia SOLO este cuerpo.
  SELECT id_socio_beneficiario
  FROM cabanas
  WHERE id_cabana = p_id_cabana;
$function$;

-- (2/4) matriz_participacion
CREATE FUNCTION public.matriz_participacion(p_periodo date)
 RETURNS TABLE(id_socio bigint, valor_socio numeric, valor_pool numeric, participacion numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH mes AS (
    SELECT daterange(
             date_trunc('month', p_periodo)::date,
             (date_trunc('month', p_periodo) + INTERVAL '1 month')::date,
             '[)'
           ) AS rango,
           date_trunc('month', p_periodo)::date AS inicio
  ),
  -- cabañas que CUBREN el mes completo (regla D-9D-06), con su beneficiario via seam
  participantes AS (
    SELECT resolver_beneficiario(c.id_cabana, m.inicio) AS id_socio,
           c.valor_relativo
    FROM activaciones_operativas a
    JOIN cabanas c ON c.id_cabana = a.id_cabana
    CROSS JOIN mes m
    WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)') @> m.rango
  ),
  por_socio AS (
    SELECT id_socio, SUM(valor_relativo) AS valor_socio
    FROM participantes
    GROUP BY id_socio
  ),
  total AS (
    SELECT SUM(valor_socio) AS valor_pool FROM por_socio
  )
  SELECT s.id_socio,
         s.valor_socio,
         t.valor_pool,
         (s.valor_socio / t.valor_pool) AS participacion
  FROM por_socio s
  CROSS JOIN total t
  WHERE t.valor_pool > 0
  ORDER BY participacion DESC, s.id_socio;
$function$;

-- (3/4) repartir_por_matriz
CREATE FUNCTION public.repartir_por_matriz(p_periodo date, p_monto numeric)
 RETURNS TABLE(id_socio bigint, participacion numeric, monto_asignado numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH base AS (
    SELECT m.id_socio, m.participacion,
           ROUND(p_monto * m.participacion, 2) AS monto_base
    FROM matriz_participacion(p_periodo) m
  ),
  resid AS (
    SELECT p_monto - COALESCE(SUM(monto_base), 0) AS residual FROM base
  ),
  -- ganador del residual: mayor participacion; si Rodrigo esta en el empate, Rodrigo;
  -- si no, menor id_socio entre los de mayor participacion (D-9E-08)
  ganador AS (
    SELECT b.id_socio
    FROM base b
    JOIN socios s ON s.id_socio = b.id_socio
    ORDER BY b.participacion DESC, (s.nombre = 'Rodrigo') DESC, b.id_socio ASC
    LIMIT 1
  )
  SELECT b.id_socio,
         b.participacion,
         b.monto_base
           + CASE WHEN b.id_socio = (SELECT id_socio FROM ganador)
                  THEN (SELECT residual FROM resid) ELSE 0 END AS monto_asignado
  FROM base b
  ORDER BY b.participacion DESC, b.id_socio;
$function$;

-- (4/4) detalle_participacion
CREATE FUNCTION public.detalle_participacion(p_periodo date)
 RETURNS TABLE(id_cabana bigint, cabana text, valor_relativo numeric, id_socio bigint, beneficiario text, participa boolean)
 LANGUAGE sql
 STABLE
AS $function$
  WITH mes AS (
    SELECT daterange(
             date_trunc('month', p_periodo)::date,
             (date_trunc('month', p_periodo) + INTERVAL '1 month')::date,
             '[)'
           ) AS rango,
           date_trunc('month', p_periodo)::date AS inicio
  )
  SELECT c.id_cabana,
         c.nombre,
         c.valor_relativo,
         resolver_beneficiario(c.id_cabana, m.inicio) AS id_socio,
         s.nombre AS beneficiario,
         EXISTS (
           SELECT 1 FROM activaciones_operativas a
           WHERE a.id_cabana = c.id_cabana
             AND daterange(a.fecha_desde, a.fecha_hasta, '[)') @> m.rango
         ) AS participa
  FROM cabanas c
  CROSS JOIN mes m
  JOIN socios s ON s.id_socio = resolver_beneficiario(c.id_cabana, m.inicio)
  ORDER BY c.id_cabana;
$function$;

-- ── REVOKE EXECUTE (hardening: fuera de Data API y PUBLIC) ───────────────────
REVOKE EXECUTE ON FUNCTION public.resolver_beneficiario(bigint, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.matriz_participacion(date)          FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.repartir_por_matriz(date, numeric)  FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.detalle_participacion(date)         FROM PUBLIC, anon, authenticated, service_role;

-- ── Asserts: atributos + huella destino (=TEST) + funcionales ───────────────
DO $asserts$
DECLARE
  r RECORD;
  v_def text;
  v_exec_abiertos int;
  v_seam_match int; v_seam_total int;
  v_jul_pool numeric; v_nov_pool numeric;
  v_reparto_sum numeric; v_reparto_naive numeric;
  v_det_jul_part int; v_det_jul_tot int; v_det_nov_part int;
BEGIN
  -- (A) atributos por función: STABLE + INVOKER + sin EXECUTE a Data API/PUBLIC
  FOR r IN
    SELECT p.oid, p.proname, p.provolatile, p.prosecdef,
           pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('resolver_beneficiario','matriz_participacion','repartir_por_matriz','detalle_participacion')
  LOOP
    IF r.provolatile <> 's' THEN
      RAISE EXCEPTION 'ASSERT volatilidad: % no es STABLE (provolatile=%)', r.proname, r.provolatile;
    END IF;
    IF r.prosecdef THEN
      RAISE EXCEPTION 'ASSERT security: % es SECURITY DEFINER (esperado INVOKER)', r.proname;
    END IF;
    SELECT count(*) INTO v_exec_abiertos
      FROM aclexplode((SELECT proacl FROM pg_proc WHERE oid=r.oid)) a
      WHERE a.privilege_type='EXECUTE'
        AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'));
    IF v_exec_abiertos <> 0 THEN
      RAISE EXCEPTION 'ASSERT ACL: % tiene % EXECUTE a PUBLIC/Data API (esperado 0)', r.proname, v_exec_abiertos;
    END IF;
  END LOOP;

  -- (B) huella def DESTINO = TEST (byte a byte tras normalizar CR)
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='resolver_beneficiario' AND pg_get_function_identity_arguments(p.oid)='p_id_cabana bigint, p_fecha date';
  IF v_def <> 'e0f9daaaae4ac90766b2f87f148391fa' THEN RAISE EXCEPTION 'ASSERT huella resolver: % != TEST e0f9daaaae4ac90766b2f87f148391fa', v_def; END IF;
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='matriz_participacion' AND pg_get_function_identity_arguments(p.oid)='p_periodo date';
  IF v_def <> 'a8260e228fffe68a74e1c1f6e3d4d0c6' THEN RAISE EXCEPTION 'ASSERT huella matriz: % != TEST a8260e228fffe68a74e1c1f6e3d4d0c6', v_def; END IF;
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='repartir_por_matriz' AND pg_get_function_identity_arguments(p.oid)='p_periodo date, p_monto numeric';
  IF v_def <> '4084c9f79a354e77f4d48c197ce60ae8' THEN RAISE EXCEPTION 'ASSERT huella repartir: % != TEST 4084c9f79a354e77f4d48c197ce60ae8', v_def; END IF;
  SELECT md5(replace(pg_get_functiondef(p.oid),E'\r','')) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='detalle_participacion' AND pg_get_function_identity_arguments(p.oid)='p_periodo date';
  IF v_def <> 'a7e8e096b4ed91dda28d03abdb356e56' THEN RAISE EXCEPTION 'ASSERT huella detalle: % != TEST a7e8e096b4ed91dda28d03abdb356e56', v_def; END IF;

  -- (C) funcionales mínimos (idénticos a los verificados pre-parche)
  SELECT count(*) INTO v_seam_match FROM cabanas c WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01') = c.id_socio_beneficiario;
  SELECT count(*) INTO v_seam_total FROM cabanas;
  IF v_seam_match <> v_seam_total OR v_seam_total <> 5 THEN
    RAISE EXCEPTION 'ASSERT seam: match=% total=% (esperado 5/5)', v_seam_match, v_seam_total;
  END IF;

  SELECT max(valor_pool) INTO v_jul_pool FROM matriz_participacion(DATE '2026-07-01');
  IF v_jul_pool IS DISTINCT FROM 378.00 THEN RAISE EXCEPTION 'ASSERT matriz julio pool=% (esperado 378.00)', v_jul_pool; END IF;
  SELECT max(valor_pool) INTO v_nov_pool FROM matriz_participacion(DATE '2026-11-01');
  IF v_nov_pool IS DISTINCT FROM 456.00 THEN RAISE EXCEPTION 'ASSERT matriz noviembre pool=% (esperado 456.00)', v_nov_pool; END IF;

  SELECT sum(monto_asignado) INTO v_reparto_sum FROM repartir_por_matriz(DATE '2026-07-01', 100000);
  SELECT sum(round(100000*participacion,2)) INTO v_reparto_naive FROM matriz_participacion(DATE '2026-07-01');
  IF v_reparto_sum IS DISTINCT FROM 100000.00 THEN RAISE EXCEPTION 'ASSERT reparto suma=% (esperado 100000.00 exacto)', v_reparto_sum; END IF;
  IF v_reparto_naive = 100000.00 THEN RAISE EXCEPTION 'ASSERT reparto: naive=100000.00 — no habría residual que validar (esperado != 100000)'; END IF;

  SELECT count(*) FILTER (WHERE participa), count(*) INTO v_det_jul_part, v_det_jul_tot FROM detalle_participacion(DATE '2026-07-01');
  IF v_det_jul_part <> 4 OR v_det_jul_tot <> 5 THEN RAISE EXCEPTION 'ASSERT detalle julio: participa=% total=% (esperado 4/5)', v_det_jul_part, v_det_jul_tot; END IF;
  SELECT count(*) FILTER (WHERE participa) INTO v_det_nov_part FROM detalle_participacion(DATE '2026-11-01');
  IF v_det_nov_part <> 5 THEN RAISE EXCEPTION 'ASSERT detalle noviembre: participa=% (esperado 5)', v_det_nov_part; END IF;

  RAISE NOTICE 'Asserts OK: atributos STABLE/INVOKER/sin-EXECUTE, huellas = TEST, funcionales seam 5/5, matriz 378/456, reparto Σ=100000.00 (residual real), detalle 4/5 y 5.';
END
$asserts$;

COMMIT;

-- ── Verificación posterior (read-only; fuera de la transacción) ─────────────
SELECT
  p.proname AS funcion,
  pg_get_function_identity_arguments(p.oid) AS firma,
  CASE p.provolatile WHEN 's' THEN 'STABLE' ELSE p.provolatile::text END AS volatilidad,
  CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END AS security,
  COALESCE(p.proacl::text,'NULL') AS acl,
  md5(replace(pg_get_functiondef(p.oid),E'\r','')) AS huella_def
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('resolver_beneficiario','matriz_participacion','repartir_por_matriz','detalle_participacion')
ORDER BY p.proname;

-- ── Reversión conceptual (sin CASCADE) ──────────────────────────────────────
-- Las 4 funciones son lógicamente idénticas antes/después; revertir solo restaura
-- el formato/comentarios previos de OPS. Para revertir: correr el companion
-- PROMO_BLOQUE_K1B_REVERT_FUNCIONES_OPS.sql (DROP sin CASCADE + CREATE con los
-- cuerpos OPS pre-parche; huellas destino 608e48f4 / 1dfe6f6a / 4d3aacf4 / 3fd7c76e).
