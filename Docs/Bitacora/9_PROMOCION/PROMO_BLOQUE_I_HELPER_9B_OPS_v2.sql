-- ============================================================================
-- PROMO_BLOQUE_I_HELPER_9B_OPS_v2.sql
-- Promoción a OPS — BLOQUE I (helper 9B: public.abortar_si_falla(jsonb)).
-- Último artefacto SQL de la promoción coordinada (después: J hardening de
-- cierre, K paridad/smokes, L workflow 3b, M bump canónico, N cierre).
--
-- v2 vs v1: SOLO se refuerza el GATE para hacer cumplir el orden de promoción
-- (registrar_pago por firma exacta + 9H completo + 9G intacto + helper ausente).
-- El cuerpo del helper, el COMMENT, el REVOKE y la verificación posterior quedan
-- IDÉNTICOS a v1 (validado VERDE). No cambia la lógica del helper.
--
-- Qué es: helper de la Fase 9B/3b (D-9B-19). Recibe el jsonb que devuelve
-- registrar_pago() y, si el pago NO quedó confirmado, lanza P0001 para forzar
-- rollback bajo queryBatching:transaction. Éxito = ok:true ∧ estado='confirmado'
-- ∧ warning IS NULL (D-8B-15). Aditivo: no toca tablas ni registrar_pago().
--
-- Cuerpo VERBATIM del volcado de TEST (pg_get_functiondef + obj_description).
-- Adaptaciones de deployment (no tocan la lógica):
--   1) CREATE OR REPLACE → DROP + CREATE separados (L-9F-03: OR REPLACE puede
--      gatillar inyección espuria de RLS en Supabase).
--   2) Fin de línea normalizado a \n (el volcado traía \r\n del editor).
-- Se reañaden COMMENT (no lo emite pg_get_functiondef) y REVOKE (estado aplicado,
-- no parte del cuerpo) con el texto/contrato exactos del cierre 9B.
--
-- ESTRUCTURA: BEGIN → gate → DROP+CREATE+COMMENT+REVOKE → asserts → COMMIT →
-- verificación read-only → reversión sin CASCADE.
-- Correr con NADA seleccionado (L-8A-01).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- GATE PROMO v2 (REFORZADO) — hace cumplir el ORDEN de promoción: el helper va
-- último, solo si el Carril B (9G+9H completos) ya está en OPS.
--   (1) registrar_pago(jsonb) por firma exacta;
--   (2) 9H completo: 5 tablas + trg_9h_inmutable() + 9 funciones;
--   (3) 9G intacto: 6 funciones;
--   (4) helper ausente.
-- ----------------------------------------------------------------------------
DO $promogate$
DECLARE
  v_amb text; v_cab int; v_soc int;
  v_regpago oid;
  v_9h_tab int; v_9h_trgfn int; v_9h_fns int; v_9g int; v_helper int;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave='ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE I: marcador ambiente=% (esperado ops).', COALESCE(v_amb,'<ausente>'); END IF;

  SELECT count(*) INTO v_cab FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
   WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana=e.id AND c.nombre=e.nom);
  SELECT count(*) INTO v_soc FROM (VALUES ('Franco'),('Rodrigo'),('Remo')) e(nom)
   WHERE (SELECT count(*) FROM socios s WHERE s.nombre=e.nom)=1;
  IF v_cab<>5 OR v_soc<>3 THEN RAISE EXCEPTION 'GATE I: identidad (cabañas=%/5, socios=%/3).', v_cab, v_soc; END IF;

  -- (1) registrar_pago(jsonb) por FIRMA EXACTA (la función cuyo resultado procesa el helper)
  v_regpago := to_regprocedure('public.registrar_pago(jsonb)');
  IF v_regpago IS NULL THEN
    RAISE EXCEPTION 'GATE I: registrar_pago(jsonb) ausente (firma exacta; base OPS incompleta).'; END IF;

  -- (2) 9H COMPLETO: 5 tablas + trg_9h_inmutable() + 9 funciones
  SELECT count(*) INTO v_9h_tab FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r'
     AND c.relname IN ('liquidaciones_periodo','liquidacion_cascada','liquidacion_socio','movimientos_socio','revaluaciones');
  SELECT count(*) INTO v_9h_trgfn FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='trg_9h_inmutable';
  SELECT count(*) INTO v_9h_fns FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('liquidacion_vigente','saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo',
                       'registrar_snapshot_periodo','registrar_retiro','registrar_movimiento_manual','registrar_reversa','registrar_revaluacion');
  IF v_9h_tab<>5 OR v_9h_trgfn<>1 OR v_9h_fns<>9 THEN
    RAISE EXCEPTION 'GATE I: 9H incompleto (tablas=%/5, trg_fn=%/1, funciones=%/9; correr G y H antes).', v_9h_tab, v_9h_trgfn, v_9h_fns; END IF;

  -- (3) 9G INTACTO: 6 funciones
  SELECT count(*) INTO v_9g FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
     AND p.proname IN ('cascada_periodo','saldo_socios_periodo','incidencia_gasto',
                       'reporte_overrides_periodo','reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo');
  IF v_9g<>6 THEN RAISE EXCEPTION 'GATE I: funciones 9G=% (esperado 6).', v_9g; END IF;

  -- (4) helper ausente — guard de re-ejecución
  SELECT count(*) INTO v_helper FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='abortar_si_falla';
  IF v_helper<>0 THEN RAISE EXCEPTION 'GATE I: helper abortar_si_falla ya presente (=%). I no se re-ejecuta.', v_helper; END IF;

  RAISE NOTICE 'GATE I v2 OK — OPS; registrar_pago(jsonb) + 9G(6) + 9H(5 tablas, trg, 9 fns); helper ausente.';
END
$promogate$;

-- ============================================================================
-- HELPER abortar_si_falla — cuerpo VERBATIM de TEST (CREATE OR REPLACE→DROP+CREATE)
-- ============================================================================
DROP FUNCTION IF EXISTS public.abortar_si_falla(jsonb);

CREATE FUNCTION public.abortar_si_falla(resultado jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Éxito SOLO si ok:true Y estado='confirmado' Y sin warning.
  IF (resultado->>'ok')::BOOLEAN IS TRUE
     AND resultado->>'estado' = 'confirmado'
     AND (resultado->>'warning') IS NULL
  THEN
    RETURN resultado;
  END IF;

  RAISE EXCEPTION 'cobranza_revertida: pago no confirmado (ok=%, estado=%, error=%, warning=%)',
    COALESCE(resultado->>'ok',      'null'),
    COALESCE(resultado->>'estado',  'null'),
    COALESCE(resultado->>'error',   'sin_error'),
    COALESCE(resultado->>'warning', 'sin_warning')
    USING ERRCODE = 'P0001';
END;
$function$;

COMMENT ON FUNCTION public.abortar_si_falla(jsonb) IS
'Etapa 9B/3b (D-9B-19): convierte un pago no confirmado de registrar_pago() en excepción P0001 para forzar rollback bajo queryBatching:transaction. Exito = ok:true + estado=confirmado + warning IS NULL (D-8B-15). Aditivo, no toca tablas ni registrar_pago().';

-- ── SEGURIDAD (paridad carril): solo el owner ejecuta ────────────────────────
REVOKE ALL ON FUNCTION public.abortar_si_falla(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- ASSERTS FINALES — firma exacta, retorno, search_path, security invoker,
-- REVOKE, COMMENT.
-- ----------------------------------------------------------------------------
DO $assert$
DECLARE
  v_sig oid; v_ret int; v_sp int; v_secdef int; v_open int; v_comment int;
  v_dataapi oid[];
BEGIN
  v_dataapi := array_remove(ARRAY[0::oid,
    (SELECT oid FROM pg_roles WHERE rolname='anon'),
    (SELECT oid FROM pg_roles WHERE rolname='authenticated'),
    (SELECT oid FROM pg_roles WHERE rolname='service_role')], NULL);

  -- I1: firma exacta abortar_si_falla(jsonb) presente
  v_sig := to_regprocedure('public.abortar_si_falla(jsonb)');
  IF v_sig IS NULL THEN RAISE EXCEPTION 'ASSERT I1: helper abortar_si_falla(jsonb) ausente.'; END IF;

  -- I2: retorna jsonb
  SELECT count(*) INTO v_ret FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='abortar_si_falla' AND p.prorettype='jsonb'::regtype;
  IF v_ret<>1 THEN RAISE EXCEPTION 'ASSERT I2: retorno no es jsonb (=%).', v_ret; END IF;

  -- I3: search_path = public, pg_temp (proconfig)
  SELECT count(*) INTO v_sp FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='abortar_si_falla'
     AND p.proconfig IS NOT NULL
     AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c
                 WHERE c LIKE 'search_path=%' AND c LIKE '%public%' AND c LIKE '%pg_temp%');
  IF v_sp<>1 THEN RAISE EXCEPTION 'ASSERT I3: search_path no fijado a public,pg_temp.'; END IF;

  -- I4: SECURITY INVOKER (prosecdef=false)
  SELECT count(*) INTO v_secdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='abortar_si_falla' AND p.prosecdef IS TRUE;
  IF v_secdef<>0 THEN RAISE EXCEPTION 'ASSERT I4: helper SECURITY DEFINER (esperado INVOKER).'; END IF;

  -- I5 (hardening): sin EXECUTE para Data API/PUBLIC
  SELECT count(*) INTO v_open FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='abortar_si_falla'
     AND (p.proacl IS NULL
          OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY(v_dataapi)));
  IF v_open<>0 THEN RAISE EXCEPTION 'ASSERT I5: helper abierto a EXECUTE=% (esperado 0).', v_open; END IF;

  -- I6: COMMENT presente
  SELECT count(*) INTO v_comment FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='abortar_si_falla'
     AND obj_description(p.oid,'pg_proc') IS NOT NULL;
  IF v_comment<>1 THEN RAISE EXCEPTION 'ASSERT I6: COMMENT ausente.'; END IF;

  RAISE NOTICE 'ASSERTS I OK — helper firma/retorno/search_path/INVOKER/sin-EXECUTE/COMMENT. Listo para COMMIT.';
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
m AS (
  SELECT
    (CASE WHEN to_regprocedure('public.abortar_si_falla(jsonb)') IS NOT NULL THEN 1 ELSE 0 END) AS sig,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
       AND p.proname='abortar_si_falla' AND p.prorettype='jsonb'::regtype) AS ret_jsonb,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
       AND p.proname='abortar_si_falla' AND p.proconfig IS NOT NULL
       AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%' AND c LIKE '%public%' AND c LIKE '%pg_temp%')) AS sp,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace, dataapi WHERE n.nspname='public'
       AND p.proname='abortar_si_falla'
       AND (p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.privilege_type='EXECUTE' AND a.grantee = ANY(dataapi.oids)))) AS open_exec,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
       AND p.proname='abortar_si_falla' AND obj_description(p.oid,'pg_proc') IS NOT NULL) AS comment_ok
)
SELECT v.orden, v.chequeo, v.obtenido, v.esperado, CASE WHEN v.ok THEN 'OK' ELSE 'FRENAR' END AS veredicto
FROM m, LATERAL (VALUES
  (1,'helper abortar_si_falla(jsonb)', m.sig::text,'1',(m.sig=1)),
  (2,'retorna jsonb', m.ret_jsonb::text,'1',(m.ret_jsonb=1)),
  (3,'search_path=public,pg_temp', m.sp::text,'1',(m.sp=1)),
  (4,'abierto a EXECUTE (Data API/PUBLIC)', m.open_exec::text,'0',(m.open_exec=0)),
  (5,'COMMENT presente', m.comment_ok::text,'1',(m.comment_ok=1))
) AS v(orden, chequeo, obtenido, esperado, ok)
UNION ALL
SELECT 999,'TOTAL I (helper 9B)',
  (SELECT count(*)::text FROM m, LATERAL (VALUES (m.sig=1),(m.ret_jsonb=1),(m.sp=1),(m.open_exec=0),(m.comment_ok=1)) t(ok) WHERE NOT t.ok)||' FALLO','0 FALLO',
  CASE WHEN (SELECT count(*) FROM m, LATERAL (VALUES (m.sig=1),(m.ret_jsonb=1),(m.sp=1),(m.open_exec=0),(m.comment_ok=1)) t(ok) WHERE NOT t.ok)=0 THEN 'VERDE' ELSE 'FRENAR' END
FROM m
ORDER BY 1;

-- ============================================================================
-- REVERSIÓN CONCEPTUAL (NO ejecutar; sin CASCADE). Función suelta y aditiva.
-- ----------------------------------------------------------------------------
-- BEGIN;
--   DROP FUNCTION IF EXISTS public.abortar_si_falla(jsonb);
-- COMMIT;
-- ============================================================================
