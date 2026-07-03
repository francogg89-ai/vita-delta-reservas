-- =====================================================================
-- HORARIOS_DISPONIBILIDAD_RANGO_B_VERIFICACION_TEST.sql
-- B) Verificacion PRE/POST de la integracion (archivo A). SOLO TEST. READ-ONLY.
--    No escribe, no consume, no DDL. No toca OPS/canonico/gateway/frontend/etc.
--
-- ORDEN DE USO:
--   1) Corré [PRE] ANTES de aplicar A. gate_ok debe ser TRUE. Si no, PARAR.
--   2) Aplicá A (HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql).
--   3) Corré [POST-A], [POST-B], [POST-C1], [POST-C2] DESPUES de A.
--   Si el editor de Supabase solo muestra el ultimo resultado, corré cada
--   bloque SELECCIONANDOLO por separado.
-- =====================================================================


-- ═════════════════════════════════════════════════════════════════════
-- [PRE] Gate manual (mismas 6 condiciones que el gate embebido de A).
--       Correr ANTES de A. gate_ok debe ser TRUE.
-- ═════════════════════════════════════════════════════════════════════
SELECT
  ((SELECT valor FROM configuracion_general WHERE clave='ambiente') = 'test')                       AS c1_ambiente_test,
  (current_schema() = 'public')                                                                     AS c2_schema_public,
  (to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)') IS NOT NULL)            AS c3_odr_existe,
  (to_regprocedure('public.resolver_horario(bigint,date)') IS NOT NULL)                             AS c4_resolver_existe,
  (md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')))
     = 'f8d6bbf533c775349642e7ed34d5ea8c')                                                          AS c5_fp_odr_baseline,
  (md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')))
     = '759662b4afaed7af426917aa3717b34c')                                                          AS c6_fp_resolver_baseline,
  (    (SELECT valor FROM configuracion_general WHERE clave='ambiente') = 'test'
   AND current_schema() = 'public'
   AND to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)') IS NOT NULL
   AND to_regprocedure('public.resolver_horario(bigint,date)') IS NOT NULL
   AND md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')))
         = 'f8d6bbf533c775349642e7ed34d5ea8c'
   AND md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')))
         = '759662b4afaed7af426917aa3717b34c'
  )                                                                                                  AS gate_ok;


-- =====================================================================
-- (APLICAR AQUI: HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql)
-- =====================================================================


-- ═════════════════════════════════════════════════════════════════════
-- [POST-A] Verificacion integral post-apply (1 fila). todo_ok debe ser TRUE.
--   Cubre: fingerprint after (difiere), ACL/owner/secdef/volatile preservados,
--   firma + 9 columnas iguales, resolver presente con fingerprint igual,
--   CROSS JOIN LATERAL presente, CASE viejos ausentes, extraccion nueva presente,
--   y existencia de vista_disponibilidad (su EJECUCION se prueba en [POST-B]).
-- ═════════════════════════════════════════════════════════════════════
SELECT
  md5(pg_get_functiondef(p.oid))                                                    AS fingerprint_after,
  (md5(pg_get_functiondef(p.oid)) <> 'f8d6bbf533c775349642e7ed34d5ea8c')            AS fp_difiere_baseline,

  -- ACL / atributos preservados (CREATE OR REPLACE no debe alterarlos)
  (p.prosecdef = false)                                                             AS security_invoker_ok,      -- secdef=false
  (pg_get_userbyid(p.proowner) = 'postgres')                                        AS owner_postgres_ok,
  (COALESCE(array_to_string(p.proacl, ', '), '') = 'postgres=X/postgres')           AS acl_owner_only_ok,
  (p.provolatile = 'v')                                                             AS volatile_ok,

  -- Firma + 9 columnas identicas (texto canonico de PostgreSQL)
  (pg_get_function_arguments(p.oid)
     = 'p_fecha_desde date, p_fecha_hasta date, p_id_cabana bigint DEFAULT NULL::bigint') AS args_iguales,
  (pg_get_function_result(p.oid)
     = 'TABLE(id_cabana bigint, fecha date, estado text, tipo_dia text, temporada text, hora_checkin_base time without time zone, hora_checkout_base time without time zone, id_reserva_activa bigint, id_prereserva_activa bigint)') AS columnas_iguales,

  -- Dependencia dura intacta
  (md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')))
     = '759662b4afaed7af426917aa3717b34c')                                          AS resolver_fp_igual,

  -- Deltas presentes / hardcode ausente (sobre prosrc)
  (strpos(p.prosrc, 'CROSS JOIN LATERAL (SELECT resolver_horario(m.id_cabana, m.fecha) AS rh) hr') > 0) AS has_cross_join_lateral,
  (    strpos(p.prosrc, '18:00') = 0 AND strpos(p.prosrc, '13:00') = 0
   AND strpos(p.prosrc, '16:00') = 0 AND strpos(p.prosrc, '10:00') = 0)             AS case_viejos_ausentes,
  (strpos(p.prosrc, '(hr.rh->>''hora_checkin'')::TIME')  > 0)                       AS has_extract_checkin,
  (strpos(p.prosrc, '(hr.rh->>''hora_checkout'')::TIME') > 0)                       AS has_extract_checkout,

  -- Vista dependiente existe (su ejecucion se prueba en [POST-B])
  (to_regclass('public.vista_disponibilidad') IS NOT NULL)                          AS vista_existe,

  -- Veredicto agregado
  (    md5(pg_get_functiondef(p.oid)) <> 'f8d6bbf533c775349642e7ed34d5ea8c'
   AND p.prosecdef = false
   AND pg_get_userbyid(p.proowner) = 'postgres'
   AND COALESCE(array_to_string(p.proacl, ', '), '') = 'postgres=X/postgres'
   AND p.provolatile = 'v'
   AND pg_get_function_arguments(p.oid) = 'p_fecha_desde date, p_fecha_hasta date, p_id_cabana bigint DEFAULT NULL::bigint'
   AND pg_get_function_result(p.oid) = 'TABLE(id_cabana bigint, fecha date, estado text, tipo_dia text, temporada text, hora_checkin_base time without time zone, hora_checkout_base time without time zone, id_reserva_activa bigint, id_prereserva_activa bigint)'
   AND md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)'))) = '759662b4afaed7af426917aa3717b34c'
   AND strpos(p.prosrc, 'CROSS JOIN LATERAL (SELECT resolver_horario(m.id_cabana, m.fecha) AS rh) hr') > 0
   AND strpos(p.prosrc, '18:00') = 0 AND strpos(p.prosrc, '13:00') = 0
   AND strpos(p.prosrc, '16:00') = 0 AND strpos(p.prosrc, '10:00') = 0
   AND strpos(p.prosrc, '(hr.rh->>''hora_checkin'')::TIME')  > 0
   AND strpos(p.prosrc, '(hr.rh->>''hora_checkout'')::TIME') > 0
   AND to_regclass('public.vista_disponibilidad') IS NOT NULL
  )                                                                                 AS todo_ok
FROM pg_proc p
WHERE p.oid = to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)');


-- ═════════════════════════════════════════════════════════════════════
-- [POST-B] vista_disponibilidad SIGUE VALIDA (ejecuta sin error post-cambio).
--   Read-only, trae a lo sumo 1 fila. Si tira error, la vista se rompio.
-- ═════════════════════════════════════════════════════════════════════
SELECT * FROM vista_disponibilidad LIMIT 1;


-- ═════════════════════════════════════════════════════════════════════
-- [POST-C1] Prueba minima read-only: ODR con CABANA CONCRETA (id_cabana=1).
--   Debe devolver 1 fila por noche del rango, con horas resueltas por el motor
--   (en dias sin override valido: 13:00/10:00 habil, 18:00/16:00 domingo).
-- ═════════════════════════════════════════════════════════════════════
SELECT id_cabana, fecha, estado, tipo_dia, hora_checkin_base, hora_checkout_base
FROM obtener_disponibilidad_rango(fecha_hoy_ar(), fecha_hoy_ar() + 4, 1)
ORDER BY fecha;


-- ═════════════════════════════════════════════════════════════════════
-- [POST-C2] Prueba minima read-only: ODR con p_id_cabana=NULL (TODAS las
--   cabanas activas; modo consumido por vista_disponibilidad y W1).
-- ═════════════════════════════════════════════════════════════════════
SELECT id_cabana, fecha, estado, hora_checkin_base, hora_checkout_base
FROM obtener_disponibilidad_rango(fecha_hoy_ar(), fecha_hoy_ar() + 2, NULL)
ORDER BY id_cabana, fecha;
