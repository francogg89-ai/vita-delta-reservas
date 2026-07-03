-- ============================================================================
-- S0_1_pct_config_TEST.sql
-- Sub-bloque 0.1 (frente "pct_operativo -> configuracion_general") -- TEST ONLY.
--
-- QUE HACE (persistente, una sola transaccion):
--   1. GATE anti-OPS: aborta y revierte si configuracion_general('ambiente') != 'test'.
--   2. Helper pct_operativo_vigente() : lee la clave con VALIDACION FUERTE y errores
--      controlados (nada de cast crudo que explote). Reusable por A27/A28 y el retiro.
--   3. Seed idempotente de la clave 'pct_operativo' (ON CONFLICT DO NOTHING; no pisa
--      un valor editado por operacion).
--   4. Verificacion fuerte (Ajuste A): clave existe / no vacia / decimal valido /
--      en [0,1] / == 0.25 solo si es el seed inicial / el helper devuelve ese valor.
--
-- CONSUMIDORES (proximos pasos, NO en este archivo):
--   - S0.2: A27/A28 cambian  cuenta_corriente_viva(NULL, 0.25)
--                       ->   cuenta_corriente_viva(NULL, pct_operativo_vigente())
--   - Sub-bloque 1: registrar_retiro_desde_saldo_vivo() llama pct_operativo_vigente()
--
-- EJECUCION: Supabase SQL Editor del proyecto TEST, NADA seleccionado (corre todo).
-- ROLLBACK: ver runsheet (S0_RUNSHEET.md). Es aditivo: DROP FUNCTION + DELETE de la clave.
-- ============================================================================

BEGIN;

-- -- 1. GATE anti-OPS (dentro de la tx: si no es test, aborta y revierte todo) --
DO $gate$
BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave = 'ambiente')
       IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'S0.1 ABORTADO: ambiente != test (este script es TEST-only)';
  END IF;
END $gate$;

-- -- 2. Helper: pct_operativo_vigente() con validacion fuerte y error controlado --
--     SECURITY INVOKER + REVOKE espejando el patron de cuenta_corriente_viva (v1.10.0).
--     Errores parseables por prefijo (L-9H-04): [pct_config_ausente] / [pct_config_invalido].
--     En Supabase SQL Editor se usa DROP + CREATE (no CREATE OR REPLACE) para evitar
--     la inyeccion espuria de RLS del editor.
DROP FUNCTION IF EXISTS public.pct_operativo_vigente();

CREATE FUNCTION public.pct_operativo_vigente()
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $fn$
DECLARE
  v_txt text;
  v_num numeric;
BEGIN
  SELECT valor INTO v_txt
    FROM configuracion_general
   WHERE clave = 'pct_operativo';

  IF NOT FOUND THEN
    RAISE EXCEPTION '[pct_config_ausente] falta la clave pct_operativo en configuracion_general';
  END IF;

  IF v_txt IS NULL THEN
    RAISE EXCEPTION '[pct_config_invalido] pct_operativo es NULL';
  END IF;

  v_txt := btrim(v_txt);

  IF v_txt = '' THEN
    RAISE EXCEPTION '[pct_config_invalido] pct_operativo vacio';
  END IF;

  -- decimal valido: digitos, opcionalmente punto + digitos ([.] evita depender de
  -- standard_conforming_strings). Rechaza texto, notacion cientifica, coma, signos.
  IF v_txt !~ '^[0-9]+([.][0-9]+)?$' THEN
    RAISE EXCEPTION '[pct_config_invalido] pct_operativo no es decimal valido: %', v_txt;
  END IF;

  v_num := v_txt::numeric;

  IF v_num < 0 OR v_num > 1 THEN
    RAISE EXCEPTION '[pct_config_invalido] pct_operativo fuera de [0,1]: %', v_num;
  END IF;

  RETURN v_num;
END
$fn$;

REVOKE ALL ON FUNCTION public.pct_operativo_vigente()
  FROM PUBLIC, anon, authenticated, service_role;

-- -- 3. Seed idempotente + 4. Verificacion fuerte (Ajuste A) --
DO $verify$
DECLARE
  v_rows     int;
  v_txt      text;
  v_num      numeric;
  v_tipo     text;
  v_editable boolean;
BEGIN
  INSERT INTO configuracion_general (clave, valor, tipo_valor, descripcion, categoria, editable)
  VALUES ('pct_operativo', '0.25', 'numeric',
          'Porcentaje operativo sobre ingreso cobrado neto de gastos operativos (D-NEG-01); '
          'usado en el reparto de la cuenta corriente (L1/L2/retiro) y persistido en cada snapshot. '
          'editable=false: no cambiar en operacion hasta el bloque de pct_operativo periodizado / vigencia futura.',
          'contabilidad', false)
  ON CONFLICT (clave) DO NOTHING;   -- no pisa valor/tipo_valor/editable ya existentes

  GET DIAGNOSTICS v_rows = ROW_COUNT;   -- 1 = seed inicial ; 0 = ya existia

  -- (a) clave existe
  SELECT valor, tipo_valor, editable INTO v_txt, v_tipo, v_editable
    FROM configuracion_general WHERE clave = 'pct_operativo';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'S0.1 FALLA: la clave pct_operativo no quedo cargada';
  END IF;

  -- (b) no vacia
  IF v_txt IS NULL OR btrim(v_txt) = '' THEN
    RAISE EXCEPTION 'S0.1 FALLA: pct_operativo vacio';
  END IF;
  v_txt := btrim(v_txt);

  -- (c) decimal valido
  IF v_txt !~ '^[0-9]+([.][0-9]+)?$' THEN
    RAISE EXCEPTION 'S0.1 FALLA: pct_operativo no es decimal valido: %', v_txt;
  END IF;

  -- (d) rango [0,1]
  v_num := v_txt::numeric;
  IF v_num < 0 OR v_num > 1 THEN
    RAISE EXCEPTION 'S0.1 FALLA: pct_operativo fuera de [0,1]: %', v_num;
  END IF;

  -- (e) SOLO en el seed inicial (en re-runs no se exige, por si el % / flags fueron
  --     cambiados legitimamente por operacion): valor 0.25, editable=false, tipo numeric
  IF v_rows = 1 AND v_num <> 0.25 THEN
    RAISE EXCEPTION 'S0.1 FALLA: seed inicial esperaba 0.25, cargo %', v_num;
  END IF;
  IF v_rows = 1 AND v_editable IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'S0.1 FALLA: seed inicial esperaba editable=false, cargo %', v_editable;
  END IF;
  IF v_rows = 1 AND v_tipo IS DISTINCT FROM 'numeric' THEN
    RAISE EXCEPTION 'S0.1 FALLA: seed inicial esperaba tipo_valor=numeric, cargo %', v_tipo;
  END IF;

  -- (f) el helper devuelve exactamente el valor almacenado (prueba de que funciona)
  IF public.pct_operativo_vigente() <> v_num THEN
    RAISE EXCEPTION 'S0.1 FALLA: pct_operativo_vigente()=% distinto de valor almacenado %',
                    public.pct_operativo_vigente(), v_num;
  END IF;

  RAISE NOTICE 'S0.1 OK: pct_operativo=% tipo=% editable=% (filas_insertadas=%) ; pct_operativo_vigente()=%',
               v_num, v_tipo, v_editable, v_rows, public.pct_operativo_vigente();
END
$verify$;

-- -- Reporte final (fila visible en el editor) --
SELECT 'S0.1_OK'                        AS estado,
       cg.valor                         AS valor_txt,
       cg.tipo_valor                    AS tipo_valor,
       cg.editable                      AS editable,
       public.pct_operativo_vigente()   AS pct_vigente,
       (SELECT valor FROM configuracion_general WHERE clave = 'ambiente') AS ambiente
FROM configuracion_general cg
WHERE cg.clave = 'pct_operativo';

COMMIT;
