-- =====================================================================
-- B1.1 - Motor de Horarios / Carril B1 (vigencias de horario base)
-- Artefacto 3/5: guard diferido trg_vig_guard (barrera G1, red no-evitable)
-- -----------------------------------------------------------------------
-- ORDEN DE CARGA: DESPUES de 1/5 (DDL) y 2/5 (helper + funcion). Reutiliza
--   el helper vigencias_conflictos_comprometidos del artefacto 2/5.
-- ROL: analogo conceptual a S1 (trg_ov_guard). La funcion valida ANTES de
--   escribir; este trigger REVALIDA el estado final G1 en el COMMIT.
--   G2/ventana/auditoria/overlap ya son declarativos (CHECK/EXCLUDE); este
--   trigger cubre SOLO G1 (dinamico: depende de comprometidos + provenance).
-- ALCANCE en B1.1: INSERT y UPDATE. DELETE NO cubierto (inerte: el resolver
--   no lee la tabla). Valida G1 SOLO si NEW.activo (desactivacion inerte).
-- -----------------------------------------------------------------------
-- DEUDA DURA B1.2 (registrada): trg_guard_vigencias usa resolver_horario
--   (via el helper) para PROVENANCE mientras el resolver aun NO lee vigencias.
--   Antes de cablear el resolver en B1.2, revisar/ajustar el trigger+helper
--   para (a) no volverse autorreferencial y (b) no malinterpretar un nuevo
--   origen 'vigencia'. Ademas revisar semantica de DELETE y de desactivacion
--   (activo->false), que en B1.2 revierten base->config con implicancias G1.
-- =====================================================================

-- ---- GATE anti-ambiente + ecosistema esperado ----
DO $gate$
DECLARE v_amb TEXT; v_res TEXT;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE B1.1-TRG: ambiente=% (esperado test). Abortando.', v_amb;
  END IF;
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'GATE B1.1-TRG: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  v_res := md5(pg_get_functiondef('resolver_horario(bigint,date)'::regprocedure));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'GATE B1.1-TRG: fingerprint resolver=% (esperado 58d75c1b6b812ee2d2c9751ddcb0cd4d). Abortando.', v_res;
  END IF;
  IF to_regclass('public.vigencias_horario_base') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.1-TRG: falta vigencias_horario_base (artefacto 1/5). Abortando.';
  END IF;
  IF to_regprocedure('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)') IS NULL THEN
    RAISE EXCEPTION 'GATE B1.1-TRG: falta helper vigencias_conflictos_comprometidos (artefacto 2/5). Abortando.';
  END IF;
END
$gate$;

-- ---- Trigger-fn: barrera diferida G1 ----
CREATE OR REPLACE FUNCTION public.trg_guard_vigencias()
RETURNS trigger
LANGUAGE plpgsql
AS $trg$
DECLARE
  v_conf jsonb;
  v_err  TEXT;
BEGIN
  -- Valida G1 SOLO si la fila resultante queda ACTIVA. Desactivacion
  -- (NEW.activo=false) => inerte para G1 (la fila deja de gobernar).
  IF NEW.activo IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  v_conf := public.vigencias_conflictos_comprometidos(
    NEW.fecha_desde, NEW.fecha_hasta, NEW.abierta,
    NEW.hora_checkin_default, NEW.hora_checkin_domingo,
    NEW.hora_checkout_default, NEW.hora_checkout_domingo);

  IF jsonb_array_length(v_conf) > 0 THEN
    -- fail-closed: distingue resolver invalido de turno pegado
    IF v_conf @> '[{"motivo":"resolver_horario_invalido"}]'::jsonb THEN
      v_err := 'resolver_horario_invalido';
    ELSE
      v_err := 'base_pisa_comprometido';
    END IF;
    RAISE EXCEPTION 'guard_vigencias: %', v_err
      USING ERRCODE = '45000',
            DETAIL = jsonb_build_object(
              'error', v_err,
              'tg_op', TG_OP,
              'id_vigencia', NEW.id_vigencia,
              'conflictos', v_conf)::text;
  END IF;

  RETURN NEW;
END
$trg$;

-- ---- Constraint trigger diferido ----
DROP TRIGGER IF EXISTS trg_vig_guard ON public.vigencias_horario_base;
CREATE CONSTRAINT TRIGGER trg_vig_guard
  AFTER INSERT OR UPDATE ON public.vigencias_horario_base
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_guard_vigencias();

-- ---- Hardening + comentarios ----
REVOKE EXECUTE ON FUNCTION public.trg_guard_vigencias() FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.trg_guard_vigencias() IS
  'B1.1 guard vigencias. Trigger-fn de la barrera diferida G1 sobre vigencias_horario_base. Valida G1 SOLO si NEW.activo (desactivacion inerte). Delega en vigencias_conflictos_comprometidos (helper compartido; provenance via resolver_horario, fail-closed si el resolver devuelve ok<>true). RAISE ERRCODE 45000 con DETAIL jsonb {error,tg_op,id_vigencia,conflictos}; error distingue base_pisa_comprometido de resolver_horario_invalido. G2/ventana/auditoria/overlap ya son declarativos (CHECK/EXCLUDE). Cubre INSERT/UPDATE; DELETE inerte en B1.1. DEUDA DURA B1.2: revisar autorreferencia, nuevo origen vigencia, y semantica de DELETE/desactivacion antes de cablear el resolver.';

COMMENT ON TRIGGER trg_vig_guard ON public.vigencias_horario_base IS
  'B1.1 guard vigencias. Valida el estado G1 FINAL en el commit, no un NEW aislado. DEFERRABLE INITIALLY DEFERRED. Forzable en tests con SET CONSTRAINTS trg_vig_guard IMMEDIATE. AFTER INSERT OR UPDATE (DELETE inerte en B1.1). B1.1 - TEST-only inerte.';

-- =====================================================================
-- VERIFICACION (read-only)
-- =====================================================================
WITH t AS (
  SELECT tg.tgname, tg.tgdeferrable, tg.tginitdeferred, tg.tgtype, tg.tgenabled
  FROM pg_trigger tg
  JOIN pg_class c ON c.oid = tg.tgrelid
  WHERE c.relname = 'vigencias_horario_base' AND tg.tgname = 'trg_vig_guard' AND NOT tg.tgisinternal
)
SELECT
  (SELECT count(*) FROM t) AS trigger_existe_esperado_1,
  (SELECT bool_and(tgdeferrable AND tginitdeferred) FROM t) AS deferrable_initially_deferred,
  -- tgtype bit 0 = ROW; INSERT(4)|UPDATE(16); DELETE(8) NO debe estar
  (SELECT bool_and((tgtype & 4) <> 0 AND (tgtype & 16) <> 0 AND (tgtype & 8) = 0) FROM t) AS eventos_ins_upd_sin_del,
  (SELECT has_function_privilege('public','public.trg_guard_vigencias()','EXECUTE')) AS grants_trgfn_public,
  CASE WHEN (SELECT count(*) FROM t) = 1
        AND (SELECT bool_and(tgdeferrable AND tginitdeferred) FROM t)
        AND (SELECT bool_and((tgtype & 4) <> 0 AND (tgtype & 16) <> 0 AND (tgtype & 8) = 0) FROM t)
        AND NOT (SELECT has_function_privilege('public','public.trg_guard_vigencias()','EXECUTE'))
       THEN 'PASS' ELSE 'FAIL' END AS veredicto_trg;
