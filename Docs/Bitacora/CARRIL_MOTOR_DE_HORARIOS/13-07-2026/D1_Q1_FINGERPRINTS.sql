-- ====================================================================================
-- D1_Q1_FINGERPRINTS.sql
-- Bloque B1.3-consolidacion-canonica * D1 * los 11 objetos de S8
-- TEST unicamente. 100% LECTURA. Autocontenido: trae su propio gate y su propia
-- transaccion READ ONLY. No se puede ejecutar esta Q sin el gate: el archivo ES la Q.
-- Repo de referencia: HEAD 07fea85802bc4fccbff1236813593762aefe58d9
-- ====================================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog, public;

DO $gate$
DECLARE
  v_amb text := (
    SELECT valor
    FROM public.configuracion_general
    WHERE clave = 'ambiente'
  );
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION
      'GATE D1: ambiente=% (esperado test). Abortando.',
      COALESCE(v_amb, '<null>');
  END IF;
END
$gate$;

-- Q1 -- LOS 11 OBJETOS DE S8 (11 filas).
--   Receta canonica: md5(pg_get_functiondef(oid)). Sin normalizacion previa.
--   OBJETO #5: b4e48e49123a4c189609d0adc21730f5 es el hash de la FUNCION TRIGGER
--   public.trg_guard_vigencias(), NO de una definicion de trigger. Las dos instancias
--   (trg_vig_guard / trg_vig_guard_detalle) se miden en Q4 con pg_get_triggerdef();
--   esas definiciones NO tienen baseline en S8.
WITH baseline(n, sig, rol_en_b13, fp_base) AS (
  VALUES
    ( 1, 'public.resolver_horario(bigint,date)',                                            'wrapper - INTACTO',           '1bd96c89e587b15582fd7b2e29ae7e18'),
    ( 2, 'public._resolver_horario(bigint,date,boolean)',                                   'interno - reemplazado (sem)', '7e5bfa21b39d90b674c1a83d76b71b1d'),
    ( 3, 'public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)',              'helper - reemplazado (sem)',  'c684340c893d8668dc2d74c7564106a8'),
    ( 4, 'public.crear_vigencia_horario(jsonb)',                                            'guard - reemplazado (sem)',   '1a7d0d2d3507019563cedd376997780d'),
    ( 5, 'public.trg_guard_vigencias()',                                                    'trigger-fn - reemplazada',    'b4e48e49123a4c189609d0adc21730f5'),
    ( 6, 'public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)',  'nuevo (B)',                   '5c5ef50eff10db716d17305dcbd54669'),
    ( 7, 'public.crear_prereserva(jsonb)',                                                  'parcheado (C)',               '62fefb63ef64e443ea2697645cd4e0a8'),
    ( 8, 'public.confirmar_reserva(jsonb)',                                                 'parcheado (D)',               'e6ac8ddce8a12a9c48ecc1aa128b311c'),
    ( 9, 'public.crear_reserva_con_horario_pactado(jsonb)',                                 'nuevo (E) - DB-only',         '93c1700f5940b0e53095e08635e159d0'),
    (10, 'public.crear_override_horario_puntual(jsonb)',                                    'nuevo (F) - DB-only',         '33d7ac8ad5f80b72a0266fb4eb4f7f4d'),
    (11, 'public.obtener_disponibilidad_rango(date,date,bigint)',                           'ODR - INTACTO (pin)',         '37009a32154f93b80520500c0f15b46b')
),
res AS (SELECT b.*, to_regprocedure(b.sig) AS rp FROM baseline b)
SELECT
  'Q1_FINGERPRINTS'                                             AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  r.n                                                           AS nro,
  r.sig                                                         AS firma_esperada,
  r.rol_en_b13                                                  AS rol,
  r.rp::oid                                                     AS oid,
  CASE WHEN r.rp IS NULL THEN NULL
       ELSE format('%I.%I(%s)', ns.nspname, p.proname,
                   pg_get_function_identity_arguments(p.oid)) END AS firma_resuelta,
  pg_get_function_identity_arguments(r.rp)                      AS args_identidad,
  pg_get_function_arguments(r.rp)                               AS args_completos,
  pg_get_function_result(r.rp)                                  AS retorno,
  pg_get_userbyid(p.proowner)                                   AS owner,
  l.lanname                                                     AS lenguaje,
  p.prokind                                                     AS prokind,
  CASE p.provolatile WHEN 'i' THEN 'IMMUTABLE'
                     WHEN 's' THEN 'STABLE'
                     WHEN 'v' THEN 'VOLATILE' END               AS volatilidad,
  p.prosecdef                                                   AS prosecdef,
  CASE WHEN p.prosecdef THEN 'SECURITY DEFINER'
       ELSE 'SECURITY INVOKER' END                              AS security_mode,
  p.proisstrict                                                 AS proisstrict,
  p.proleakproof                                                AS proleakproof,
  CASE p.proparallel WHEN 's' THEN 'SAFE'
                     WHEN 'r' THEN 'RESTRICTED'
                     WHEN 'u' THEN 'UNSAFE' END                 AS parallel,
  COALESCE(array_to_string(p.proconfig, ' | '), '<null>')       AS proconfig,
  COALESCE(p.proacl::text,
           '<null> (= ACL por defecto: EXECUTE a PUBLIC)')      AS proacl,
  COALESCE(obj_description(r.rp::oid, 'pg_proc'), '<sin comentario>') AS comentario,
  r.fp_base                                                     AS fingerprint_baseline_s8,
  md5(pg_get_functiondef(r.rp))                                 AS fingerprint_actual,
  octet_length(pg_get_functiondef(r.rp))                        AS bytes_functiondef,
  CASE
    WHEN r.rp IS NULL                                   THEN 'AUSENTE'
    WHEN md5(pg_get_functiondef(r.rp)) = r.fp_base      THEN 'COINCIDE'
    ELSE 'DIFIERE'
  END                                                           AS veredicto
FROM res r
LEFT JOIN pg_proc      p  ON p.oid  = r.rp::oid
LEFT JOIN pg_language  l  ON l.oid  = p.prolang
LEFT JOIN pg_namespace ns ON ns.oid = p.pronamespace
ORDER BY r.n;

COMMIT;
