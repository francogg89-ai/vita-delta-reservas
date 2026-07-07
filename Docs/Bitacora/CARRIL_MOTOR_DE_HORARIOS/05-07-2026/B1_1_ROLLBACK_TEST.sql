-- =====================================================================
-- B1.1 - Motor de Horarios / Carril B1 (vigencias de horario base)
-- Artefacto 5/5: ROLLBACK (bajas ordenadas, SIN DROP CASCADE)
-- -----------------------------------------------------------------------
-- Revierte por completo B1.1. Orden que respeta dependencias sin CASCADE:
--   1) trigger trg_vig_guard  (depende de la tabla y de la trigger-fn)
--   2) trigger-fn trg_guard_vigencias()
--   3) funcion crear_vigencia_horario(jsonb)
--   4) helper vigencias_conflictos_comprometidos(...)
--   5) tabla vigencias_horario_base  -> arrastra PK, 6 CHECK, EXCLUDE, indice
--      y la SECUENCIA OWNED (BIGSERIAL) automaticamente, SIN CASCADE.
-- NO toca btree_gist (B1.1 nunca la creo; es load-bearing de reservas/bloqueos).
-- NO toca resolver_horario, OPS, portal-api, frontend, n8n, Vercel, canonico
--   ni configuracion_general.
-- =====================================================================

-- ---- GATE anti-ambiente ----
DO $gate$
DECLARE v_amb TEXT;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE B1.1-RB: ambiente=% (esperado test). Abortando.', v_amb;
  END IF;
  IF current_schema() <> 'public' THEN
    RAISE EXCEPTION 'GATE B1.1-RB: schema=% (esperado public). Abortando.', current_schema();
  END IF;
END
$gate$;

-- ---- Bajas ordenadas (SIN CASCADE) ----
DROP TRIGGER  IF EXISTS trg_vig_guard ON public.vigencias_horario_base;
DROP FUNCTION IF EXISTS public.trg_guard_vigencias();
DROP FUNCTION IF EXISTS public.crear_vigencia_horario(jsonb);
DROP FUNCTION IF EXISTS public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time);
DROP TABLE    IF EXISTS public.vigencias_horario_base;   -- arrastra secuencia OWNED, CHECKs, EXCLUDE, indice, PK

-- =====================================================================
-- POSTCHECK (read-only). Ecosistema intacto + objetos B1.1 inexistentes.
-- =====================================================================
SELECT
  -- resolver/ODR intactos (fingerprints TEST post-R0)
  (md5(pg_get_functiondef('resolver_horario(bigint,date)'::regprocedure)) = '58d75c1b6b812ee2d2c9751ddcb0cd4d') AS resolver_fp_ok,
  (md5(pg_get_functiondef('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure)) = '37009a32154f93b80520500c0f15b46b') AS odr_fp_ok,
  -- objetos B1.1 removidos
  (to_regclass('public.vigencias_horario_base') IS NULL) AS tabla_removida,
  (to_regclass('public.vigencias_horario_base_id_vigencia_seq') IS NULL) AS secuencia_removida,
  (to_regprocedure('public.crear_vigencia_horario(jsonb)') IS NULL) AS funcion_removida,
  (to_regprocedure('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)') IS NULL) AS helper_removido,
  (to_regprocedure('public.trg_guard_vigencias()') IS NULL) AS trgfn_removida,
  (NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_vig_guard')) AS trigger_removido,
  -- btree_gist intacta (load-bearing; B1.1 nunca la toco)
  (EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gist')) AS btree_gist_presente,
  -- veredicto
  CASE WHEN
        md5(pg_get_functiondef('resolver_horario(bigint,date)'::regprocedure)) = '58d75c1b6b812ee2d2c9751ddcb0cd4d'
    AND md5(pg_get_functiondef('obtener_disponibilidad_rango(date,date,bigint)'::regprocedure)) = '37009a32154f93b80520500c0f15b46b'
    AND to_regclass('public.vigencias_horario_base') IS NULL
    AND to_regclass('public.vigencias_horario_base_id_vigencia_seq') IS NULL
    AND to_regprocedure('public.crear_vigencia_horario(jsonb)') IS NULL
    AND to_regprocedure('public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)') IS NULL
    AND to_regprocedure('public.trg_guard_vigencias()') IS NULL
    AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_vig_guard')
    AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gist')
       THEN 'PASS' ELSE 'FAIL' END AS veredicto_rollback;
