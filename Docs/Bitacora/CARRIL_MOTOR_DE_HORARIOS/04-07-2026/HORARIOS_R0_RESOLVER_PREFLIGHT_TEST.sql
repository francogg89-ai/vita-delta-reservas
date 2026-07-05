-- =====================================================================
-- HORARIOS_R0_RESOLVER_PREFLIGHT_TEST.sql
-- Pre-bloque R0 (correccion de drift del resolver) : PREFLIGHT READ-ONLY.
-- ALCANCE: SOLO TEST. NO ejecutar en OPS. NO modifica NADA (solo SELECT).
-- Objetivo: evidenciar que modificar resolver_horario() por CREATE OR REPLACE
--   (misma firma, cambio de cuerpo) NO rompe obtener_disponibilidad_rango ni
--   crear_prereserva, y que no hay dependientes duros que bloqueen.
-- Correr el script COMPLETO (sin seleccion parcial; ver L-8A-01).
-- Las 3 consultas devuelven resultados; el editor muestra el ultimo set.
-- =====================================================================

-- 1) Dependientes DUROS de resolver_horario en pg_depend.
--    Esperado: 0 filas. Las llamadas funcion->funcion en PL/pgSQL NO generan
--    pg_depend (el cuerpo es texto opaco al rastreador), asi que ni siquiera un
--    DROP sin CASCADE quedaria bloqueado; y CREATE OR REPLACE ni siquiera dropea.
SELECT
  d.classid::regclass AS objeto_clase,
  d.objid             AS objeto_id,
  d.deptype           AS tipo_dependencia,
  pg_describe_object(d.classid, d.objid, d.objsubid) AS objeto_descripcion
FROM pg_depend d
WHERE d.refobjid = to_regprocedure('public.resolver_horario(bigint,date)')
  AND d.deptype NOT IN ('i', 'p');   -- excluye internas/pinned

-- 2) Callers que referencian resolver_horario POR NOMBRE (resolucion en runtime).
--    Esperado: obtener_disponibilidad_rango = true; crear_prereserva = true en TEST
--    (integracion FASEB_B3 aplicada). Como la firma (bigint,date)->jsonb NO cambia y
--    el OID se preserva con CREATE OR REPLACE, ambos siguen llamando al MISMO objeto.
SELECT
  p.proname AS funcion,
  (pg_get_functiondef(p.oid) ILIKE '%resolver_horario%') AS llama_resolver_horario
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('obtener_disponibilidad_rango', 'crear_prereserva')
ORDER BY p.proname;

-- 3) Fingerprints ACTUALES (evidencia pre-fix). Esperado exacto:
--    resolver = 759662b4afaed7af426917aa3717b34c
--    ODR      = 37009a32154f93b80520500c0f15b46b
SELECT
  md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')))                       AS resolver_fp_actual,
  md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')))       AS odr_fp_actual,
  (md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')))
      = '759662b4afaed7af426917aa3717b34c')                                                               AS resolver_fp_ok,
  (md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')))
      = '37009a32154f93b80520500c0f15b46b')                                                               AS odr_fp_ok;
