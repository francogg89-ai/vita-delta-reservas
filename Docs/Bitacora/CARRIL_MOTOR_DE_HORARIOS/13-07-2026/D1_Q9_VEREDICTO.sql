-- ====================================================================================
-- D1_Q9_VEREDICTO.sql
-- Bloque B1.3-consolidacion-canonica * D1 * veredicto integral + apto_para_freeze
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

-- Q9 -- VEREDICTO INTEGRAL (1 fila). Corre TODOS los chequeos y emite apto_para_freeze.
--
--   apto_para_freeze = true SOLO si TODO lo siguiente se cumple:
--     * 11/11 objetos presentes
--     * 11/11 fingerprints coincidentes con S8
--     * cero overloads sobrantes
--     * cero EXECUTE a PUBLIC
--     * cero privilegios efectivos de anon/authenticated/service_role
--     * exactamente 2 triggers, con nombre/tabla/trigger-fn/constraint/deferrable/
--       initially-deferred/enabled correctos
--     * S3 ausente en DB y sin callers DB
--     * H4 no ambiguo
--
--   GATE EXTERNO (no verificable desde la DB): ausencia de S3 en repo y en Workflows.
--   Se verifica con git grep, fuera de este artefacto.
WITH base(n, sig, fp_base) AS (
  VALUES
    ( 1,'public.resolver_horario(bigint,date)',                                           '1bd96c89e587b15582fd7b2e29ae7e18'),
    ( 2,'public._resolver_horario(bigint,date,boolean)',                                  '7e5bfa21b39d90b674c1a83d76b71b1d'),
    ( 3,'public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)',             'c684340c893d8668dc2d74c7564106a8'),
    ( 4,'public.crear_vigencia_horario(jsonb)',                                           '1a7d0d2d3507019563cedd376997780d'),
    ( 5,'public.trg_guard_vigencias()',                                                   'b4e48e49123a4c189609d0adc21730f5'),
    ( 6,'public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)', '5c5ef50eff10db716d17305dcbd54669'),
    ( 7,'public.crear_prereserva(jsonb)',                                                 '62fefb63ef64e443ea2697645cd4e0a8'),
    ( 8,'public.confirmar_reserva(jsonb)',                                                'e6ac8ddce8a12a9c48ecc1aa128b311c'),
    ( 9,'public.crear_reserva_con_horario_pactado(jsonb)',                                '93c1700f5940b0e53095e08635e159d0'),
    (10,'public.crear_override_horario_puntual(jsonb)',                                   '33d7ac8ad5f80b72a0266fb4eb4f7f4d'),
    (11,'public.obtener_disponibilidad_rango(date,date,bigint)',                          '37009a32154f93b80520500c0f15b46b')
),
obj AS (
  SELECT b.n, b.sig, b.fp_base, to_regprocedure(b.sig) AS rp,
         CASE WHEN to_regprocedure(b.sig) IS NULL THEN NULL
              ELSE md5(pg_get_functiondef(to_regprocedure(b.sig))) END AS fp_now
  FROM base b
),
chk_obj AS (
  SELECT count(*)                                                         AS esperados,
         count(*) FILTER (WHERE rp IS NOT NULL)                           AS presentes,
         count(*) FILTER (WHERE rp IS NULL)                               AS ausentes,
         count(*) FILTER (WHERE fp_now = fp_base)                         AS fp_coinciden,
         count(*) FILTER (WHERE rp IS NOT NULL AND fp_now IS DISTINCT FROM fp_base) AS fp_difieren,
         string_agg(sig, ' | ') FILTER (WHERE rp IS NULL)                 AS lista_ausentes,
         string_agg(sig || ' [vivo=' || fp_now || ' esperado=' || fp_base || ']', ' | ')
           FILTER (WHERE rp IS NOT NULL AND fp_now IS DISTINCT FROM fp_base) AS lista_fp_difieren
  FROM obj
),
sobrantes AS (
  SELECT format('%I.%I(%s)', n.nspname, p.proname,
                pg_get_function_identity_arguments(p.oid)) AS firma
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
    'resolver_horario', '_resolver_horario', 'vigencias_conflictos_comprometidos',
    'crear_vigencia_horario', 'trg_guard_vigencias', 'validar_gap_bordes_congelados',
    'crear_prereserva', 'confirmar_reserva', 'crear_reserva_con_horario_pactado',
    'crear_override_horario_puntual', 'obtener_disponibilidad_rango',
    'crear_paquete_dia_especial'
    )
    AND NOT EXISTS (SELECT 1 FROM obj o WHERE o.rp::oid = p.oid)
),
chk_ovl AS (
  SELECT count(*) AS n_sobrantes, string_agg(firma, ' | ') AS lista FROM sobrantes
),
acl_pub AS (
  SELECT DISTINCT o.sig
  FROM obj o
  JOIN pg_proc p ON p.oid = o.rp::oid
  CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
  WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'
),
chk_pub AS (SELECT count(*) AS n, string_agg(sig, ' | ') AS lista FROM acl_pub),
priv_eff AS (
  SELECT o.sig, ro.rolname
  FROM obj o
  CROSS JOIN (VALUES ('anon'),('authenticated'),('service_role')) AS ro(rolname)
  WHERE o.rp IS NOT NULL
    AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ro.rolname)
    AND has_function_privilege(ro.rolname, o.rp::oid, 'EXECUTE')
),
chk_priv AS (
  SELECT count(*) AS n, string_agg(sig || ' -> ' || rolname, ' | ') AS lista FROM priv_eff
),
trg AS (
  SELECT t.tgname, ns.nspname AS schema, c.relname AS tabla,
         (p.oid = to_regprocedure('public.trg_guard_vigencias()')::oid) AS fn_ok,
         (t.tgconstraint <> 0) AS es_constraint,
         t.tgdeferrable AS es_deferrable, t.tginitdeferred AS init_deferred,
         (t.tgenabled = 'O') AS enabled_origin
  FROM pg_trigger t
  JOIN pg_class     c  ON c.oid  = t.tgrelid
  JOIN pg_namespace ns ON ns.oid = c.relnamespace
  JOIN pg_proc      p  ON p.oid  = t.tgfoid
  WHERE NOT t.tgisinternal
    AND (p.oid = to_regprocedure('public.trg_guard_vigencias()')::oid
         OR t.tgname IN ('trg_vig_guard','trg_vig_guard_detalle'))
),
chk_trg AS (
  SELECT
    count(*) AS n_total,
    COALESCE(bool_or(tgname='trg_vig_guard' AND schema='public'
                     AND tabla='vigencias_horario_base' AND fn_ok AND es_constraint
                     AND es_deferrable AND init_deferred AND enabled_origin), false) AS base_ok,
    COALESCE(bool_or(tgname='trg_vig_guard_detalle' AND schema='public'
                     AND tabla='vigencias_horario_detalle' AND fn_ok AND es_constraint
                     AND es_deferrable AND init_deferred AND enabled_origin), false) AS detalle_ok,
    COALESCE(string_agg(tgname || ' @ ' || schema || '.' || tabla
             || ' [fn_guard=' || fn_ok || ' constraint=' || es_constraint
             || ' deferrable=' || es_deferrable || ' init_deferred=' || init_deferred
             || ' enabled=' || enabled_origin || ']', ' ; '), '<ninguno>') AS detalle
  FROM trg
),
s3 AS (
  SELECT
    (to_regprocedure('public.crear_paquete_dia_especial(jsonb)') IS NULL) AS regproc_null,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE p.proname='crear_paquete_dia_especial') AS filas,
    (SELECT count(*) FROM (
        SELECT pg_get_functiondef(p.oid) AS cuerpo
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.prokind IN ('f','p')
        UNION ALL SELECT definition FROM pg_views    WHERE schemaname='public'
        UNION ALL SELECT definition FROM pg_matviews WHERE schemaname='public'
     ) x WHERE x.cuerpo ~ '\mcrear_paquete_dia_especial\M') AS callers_db
),
h4 AS (
  SELECT
    (d.def IS NOT NULL)                                                 AS presente,
    (d.def LIKE '%[B1.3-D:BEGIN]%')                                     AS tiene_bloque,
    (d.def ~ '--\s*\[B1\.3-D:END\]\s*\n\s*BEGIN\s*\n\s*INSERT INTO reservas') AS es_0807,
    (d.def ~ '--\s*\[B1\.3-D:END\]\s*\n[ \t]*INSERT INTO reservas')             AS es_0907
  FROM (SELECT CASE WHEN to_regprocedure('public.confirmar_reserva(jsonb)') IS NULL THEN NULL
                    ELSE pg_get_functiondef(to_regprocedure('public.confirmar_reserva(jsonb)'))
               END AS def) d
),
chk_h4 AS (
  SELECT
    CASE
      WHEN NOT presente               THEN '>>> confirmar_reserva AUSENTE <<<'
      WHEN NOT tiene_bloque           THEN '>>> BLOQUE D AUSENTE <<<'
      WHEN es_0807 AND NOT es_0907    THEN 'variante 08-07 (anchor literal)'
      WHEN es_0907 AND NOT es_0807    THEN 'variante 09-07 (anchor regex)'
      ELSE '>>> AMBIGUO <<<'
    END AS veredicto,
    COALESCE(presente AND tiene_bloque AND (es_0807 <> es_0907), false) AS no_ambiguo
  FROM h4
)
SELECT
  'Q9_VEREDICTO_INTEGRAL'                                   AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  o.esperados                                               AS objetos_esperados,
  o.presentes                                               AS objetos_presentes,
  o.ausentes                                                AS objetos_ausentes,
  o.fp_coinciden                                            AS fingerprints_coinciden,
  o.fp_difieren                                             AS fingerprints_difieren,
  COALESCE(o.lista_ausentes, '<ninguno>')                   AS detalle_ausentes,
  COALESCE(o.lista_fp_difieren, '<ninguno>')                AS detalle_fp_difieren,
  ov.n_sobrantes                                            AS overloads_sobrantes,
  COALESCE(ov.lista, '<ninguno>')                           AS detalle_overloads,
  pu.n                                                      AS execute_a_public,
  COALESCE(pu.lista, '<ninguno>')                           AS detalle_execute_public,
  pr.n                                                      AS priv_efectivos_data_api,
  COALESCE(pr.lista, '<ninguno>')                           AS detalle_priv_efectivos,
  tg.n_total                                                AS triggers_total,
  tg.base_ok                                                AS trg_vig_guard_ok,
  tg.detalle_ok                                             AS trg_vig_guard_detalle_ok,
  tg.detalle                                                AS detalle_triggers,
  s.regproc_null                                            AS s3_regproc_null,
  s.filas                                                   AS s3_filas_pg_proc,
  s.callers_db                                              AS s3_callers_db,
  h.veredicto                                               AS h4_veredicto,
  h.no_ambiguo                                              AS h4_no_ambiguo,
  (    o.presentes    = 11
   AND o.fp_coinciden = 11
   AND ov.n_sobrantes = 0
   AND pu.n           = 0
   AND pr.n           = 0
   AND tg.n_total     = 2
   AND tg.base_ok
   AND tg.detalle_ok
   AND s.regproc_null
   AND s.filas        = 0
   AND s.callers_db   = 0
   AND h.no_ambiguo
  )                                                         AS apto_para_freeze,
  COALESCE(NULLIF(array_to_string(ARRAY[
    CASE WHEN o.presentes    <> 11 THEN 'objetos presentes ' || o.presentes || '/11' END,
    CASE WHEN o.fp_coinciden <> 11 THEN 'fingerprints coinciden ' || o.fp_coinciden || '/11' END,
    CASE WHEN ov.n_sobrantes >  0  THEN 'overloads sobrantes: ' || ov.n_sobrantes END,
    CASE WHEN pu.n           >  0  THEN 'EXECUTE a PUBLIC en ' || pu.n || ' objeto(s)' END,
    CASE WHEN pr.n           >  0  THEN 'privilegios efectivos anon/auth/service: ' || pr.n END,
    CASE WHEN tg.n_total     <> 2  THEN 'triggers ' || tg.n_total || ' (esperado 2)' END,
    CASE WHEN NOT tg.base_ok       THEN 'trg_vig_guard mal configurado o ausente' END,
    CASE WHEN NOT tg.detalle_ok    THEN 'trg_vig_guard_detalle mal configurado o ausente' END,
    CASE WHEN NOT s.regproc_null OR s.filas > 0 THEN 'S3 presente en DB' END,
    CASE WHEN s.callers_db   >  0  THEN 'S3 con callers DB: ' || s.callers_db END,
    CASE WHEN NOT h.no_ambiguo     THEN 'H4 sin resolver: ' || h.veredicto END
  ], ' | '), ''), '<ninguno -- todos los criterios DB se cumplen>')  AS motivos_de_bloqueo,
  'GATE EXTERNO pendiente: ausencia de S3 en repo y Workflows (git grep)' AS nota_gate_externo
FROM chk_obj o, chk_ovl ov, chk_pub pu, chk_priv pr, chk_trg tg, s3 s, chk_h4 h;

COMMIT;
