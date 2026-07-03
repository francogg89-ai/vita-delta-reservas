-- ============================================================================
-- S0_3_pct_config_OPS.sql  --  Sub-bloque 0.3 (promocion OPS) -- OPS ONLY.
--
-- Espejo EXACTO de S0_1_pct_config_TEST.sql, con el gate INVERTIDO: solo corre si
-- configuracion_general('ambiente') = 'ops'. Deja en OPS la clave 'pct_operativo'
-- (editable=false, tipo_valor='numeric') y el helper pct_operativo_vigente() con la
-- MISMA definicion que en TEST.
--
-- ORDEN EN LA PROMOCION OPS: este script va ANTES de re-importar los wrappers
-- A27/A28 __OPS parcheados (los wrappers leen pct_operativo_vigente(); la clave y el
-- helper tienen que existir primero).
--
-- EJECUCION: Supabase SQL Editor del proyecto OPS, NADA seleccionado (corre todo).
-- ROLLBACK: ver runsheet (S0_RUNSHEET.md, seccion S0.3).
-- ============================================================================

BEGIN;

-- -- 1. GATE OPS (si no es ops, aborta y revierte todo) --
DO $gate$
BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave = 'ambiente')
       IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'S0.3 ABORTADO: ambiente != ops (este script es OPS-only)';
  END IF;
END $gate$;

-- -- 2. Helper pct_operativo_vigente() -- DEFINICION IDENTICA A TEST (S0.1) --
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

-- -- 3. Seed idempotente + 4. Verificacion fuerte (identica a S0.1) --
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

  SELECT valor, tipo_valor, editable INTO v_txt, v_tipo, v_editable
    FROM configuracion_general WHERE clave = 'pct_operativo';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'S0.3 FALLA: la clave pct_operativo no quedo cargada';
  END IF;

  IF v_txt IS NULL OR btrim(v_txt) = '' THEN
    RAISE EXCEPTION 'S0.3 FALLA: pct_operativo vacio';
  END IF;
  v_txt := btrim(v_txt);

  IF v_txt !~ '^[0-9]+([.][0-9]+)?$' THEN
    RAISE EXCEPTION 'S0.3 FALLA: pct_operativo no es decimal valido: %', v_txt;
  END IF;

  v_num := v_txt::numeric;
  IF v_num < 0 OR v_num > 1 THEN
    RAISE EXCEPTION 'S0.3 FALLA: pct_operativo fuera de [0,1]: %', v_num;
  END IF;

  IF v_rows = 1 AND v_num <> 0.25 THEN
    RAISE EXCEPTION 'S0.3 FALLA: seed inicial esperaba 0.25, cargo %', v_num;
  END IF;
  IF v_rows = 1 AND v_editable IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'S0.3 FALLA: seed inicial esperaba editable=false, cargo %', v_editable;
  END IF;
  IF v_rows = 1 AND v_tipo IS DISTINCT FROM 'numeric' THEN
    RAISE EXCEPTION 'S0.3 FALLA: seed inicial esperaba tipo_valor=numeric, cargo %', v_tipo;
  END IF;

  IF public.pct_operativo_vigente() <> v_num THEN
    RAISE EXCEPTION 'S0.3 FALLA: pct_operativo_vigente()=% distinto de valor almacenado %',
                    public.pct_operativo_vigente(), v_num;
  END IF;

  RAISE NOTICE 'S0.3 OK: pct_operativo=% tipo=% editable=% (filas_insertadas=%) ; pct_operativo_vigente()=%',
               v_num, v_tipo, v_editable, v_rows, public.pct_operativo_vigente();
END
$verify$;

-- -- Reporte final (fila visible en el editor) --
SELECT 'S0.3_OK'                        AS estado,
       cg.valor                         AS valor_txt,
       cg.tipo_valor                    AS tipo_valor,
       cg.editable                      AS editable,
       public.pct_operativo_vigente()   AS pct_vigente,
       (SELECT valor FROM configuracion_general WHERE clave = 'ambiente') AS ambiente
FROM configuracion_general cg
WHERE cg.clave = 'pct_operativo';

COMMIT;
