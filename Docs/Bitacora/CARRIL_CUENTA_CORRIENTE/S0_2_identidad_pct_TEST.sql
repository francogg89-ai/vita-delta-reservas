-- ============================================================================
-- S0_2_identidad_pct_TEST.sql  --  Sub-bloque 0.2 (prueba de identidad, TEST ONLY)
--
-- Prueba DETERMINISTICA (independiente de los datos) de que leer el pct via
-- pct_operativo_vigente() produce EXACTAMENTE la misma salida que el literal 0.25,
-- tanto en cuenta_corriente_viva (L1) como en cuenta_corriente_detalle (L2).
-- Es la base numerica del cambio de wrappers: si esto es identico, el edit de
-- A27/A28 es output-neutral por construccion.
--
-- Read-only: no escribe nada. Requiere que S0.1 ya haya creado pct_operativo_vigente().
-- EJECUCION: SQL Editor del proyecto TEST, NADA seleccionado.
-- ============================================================================

BEGIN;

-- GATE anti-OPS
DO $gate$
BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave = 'ambiente')
       IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'S0.2 identidad ABORTADO: ambiente != test (TEST-only)';
  END IF;
END $gate$;

DO $idv$
DECLARE
  v_diff int;
  v_mes  date := date_trunc('month',
                   (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date)::date;
BEGIN
  -- (1) cuenta_corriente_viva: helper vs 0.25, diferencia simetrica (EXCEPT en ambos sentidos)
  SELECT count(*) INTO v_diff FROM (
      (SELECT * FROM cuenta_corriente_viva(NULL, 0.25)
       EXCEPT
       SELECT * FROM cuenta_corriente_viva(NULL, public.pct_operativo_vigente()))
      UNION ALL
      (SELECT * FROM cuenta_corriente_viva(NULL, public.pct_operativo_vigente())
       EXCEPT
       SELECT * FROM cuenta_corriente_viva(NULL, 0.25))
  ) d;
  IF v_diff <> 0 THEN
    RAISE EXCEPTION 'S0.2 FALLA: cuenta_corriente_viva difiere entre helper y 0.25 (% filas)', v_diff;
  END IF;

  -- (2) cuenta_corriente_detalle: igualdad jsonb para el mes en curso
  IF cuenta_corriente_detalle(v_mes, 0.25)
       IS DISTINCT FROM cuenta_corriente_detalle(v_mes, public.pct_operativo_vigente()) THEN
    RAISE EXCEPTION 'S0.2 FALLA: cuenta_corriente_detalle difiere entre helper y 0.25 (mes %)', v_mes;
  END IF;

  RAISE NOTICE 'S0.2 IDENTIDAD OK: viva y detalle identicos con pct_operativo_vigente()=% vs 0.25 (mes=%)',
               public.pct_operativo_vigente(), v_mes;
END $idv$;

SELECT 'S0.2_IDENTIDAD_OK'              AS estado,
       public.pct_operativo_vigente()   AS pct_vigente,
       (SELECT valor FROM configuracion_general WHERE clave = 'ambiente') AS ambiente;

COMMIT;
