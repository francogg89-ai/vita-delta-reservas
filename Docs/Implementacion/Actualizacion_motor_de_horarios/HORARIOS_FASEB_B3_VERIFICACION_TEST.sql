-- =====================================================================
-- HORARIOS_FASEB_B3_VERIFICACION_TEST.sql  (v3)
-- Fase B / Bloque 3 - Verificacion de la integracion resolver_horario()
--   en crear_prereserva. SOLO TEST. Read-only (no escribe, no consume).
-- Correr [PRE] ANTES de aplicar; [POST-*] DESPUES. Nada seleccionado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- [PRE] Gate manual (las mismas 3 guardas ejecutables que trae embebidas el
--   SQL de integracion). gate_ok debe ser TRUE. Si no, PARAR.
-- ---------------------------------------------------------------------
SELECT
  md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure))            AS fingerprint_baseline,
  md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure))
      = 'f258ad9b6e4cd0f7dcb7318e5724f0ce'                                            AS coincide_baseline,
  (SELECT valor FROM configuracion_general WHERE clave='ambiente')                    AS ambiente,
  current_schema()                                                                    AS schema_actual,
  (   md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure))
        = 'f258ad9b6e4cd0f7dcb7318e5724f0ce'
   AND (SELECT valor FROM configuracion_general WHERE clave='ambiente') = 'test'
   AND current_schema() = 'public'
  )                                                                                    AS gate_ok;

-- =====================================================================
-- (APLICAR AQUI HORARIOS_FASEB_B3_INTEGRACION_CREAR_PRERESERVA_TEST.sql)
-- =====================================================================

-- ---------------------------------------------------------------------
-- [POST-1] Fingerprint after - debe DIFERIR del baseline. Anotar el valor:
--   es el nuevo baseline del motor de horarios para TEST/OPS.
-- ---------------------------------------------------------------------
SELECT md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure)) AS fingerprint_after,
       md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure))
         <> 'f258ad9b6e4cd0f7dcb7318e5724f0ce'                                  AS difiere_del_baseline;

-- ---------------------------------------------------------------------
-- [POST-2] ACL / atributos - CREATE OR REPLACE debe PRESERVAR el hardening.
--   Esperado: security_definer=false, owner=postgres, {postgres=X/postgres}.
-- ---------------------------------------------------------------------
SELECT p.oid::regprocedure                            AS funcion,
       p.prosecdef                                    AS security_definer,
       pg_get_userbyid(p.proowner)                    AS owner,
       COALESCE(array_to_string(p.proacl, ', '),
                '(default: PUBLIC EXECUTE)')           AS proacl_raw
FROM pg_proc p
WHERE p.oid = 'public.crear_prereserva(jsonb)'::regprocedure;

-- ---------------------------------------------------------------------
-- [POST-3] Chequeo estructural sobre prosrc (en-editor, sin diff externo).
--   TODAS las columnas deben dar TRUE. (prosrc es el CUERPO, no la firma; la
--   calificacion public. de D5 no afecta estos checks.)
-- ---------------------------------------------------------------------
SELECT
  position('resolver_horario(v_id_cabana, v_fecha_in)'  IN prosrc) > 0 AS d2_call_in,
  position('resolver_horario(v_id_cabana, v_fecha_out)' IN prosrc) > 0 AS d2_call_out,
  (length(prosrc) - length(replace(prosrc, '''borde''', '')))
     / length('''borde''')          = 2                              AS d2_borde_x2,
  (length(prosrc) - length(replace(prosrc, '''fecha_resolver''', '')))
     / length('''fecha_resolver''') = 2                              AS d2_fecha_resolver_x2,
  (length(prosrc) - length(replace(prosrc, 'IS NOT TRUE THEN', '')))
     / length('IS NOT TRUE THEN')   = 2                              AS d2_failclosed_x2,
  position('v_res_in' IN prosrc)  > 0                                AS d1_decl_in,
  position('v_res_out' IN prosrc) > 0                                AS d1_decl_out,
  position('(v_res_in->>''hora_checkin'')::TIME'   IN prosrc) > 0    AS d3_extract_in,
  position('(v_res_out->>''hora_checkout'')::TIME' IN prosrc) > 0    AS d4_extract_out,
  position('WHEN EXTRACT(DOW FROM v_fecha_in) = 0'  IN prosrc) = 0   AS d3_sin_case_in,
  position('WHEN EXTRACT(DOW FROM v_fecha_out) = 0' IN prosrc) = 0   AS d4_sin_case_out,
  position('hora_checkin_max_cliente'')::TIME, TIME ''22:00'  IN prosrc) > 0 AS bound_max_22,
  position('hora_checkout_min_cliente'')::TIME, TIME ''07:00' IN prosrc) > 0 AS bound_min_07,
  position('fecha_in_pasada' IN prosrc)         > 0                  AS guard_intacto,
  position('validar_disponibilidad' IN prosrc)  > 0                  AS disp_intacta
FROM pg_proc
WHERE oid = 'public.crear_prereserva(jsonb)'::regprocedure;
