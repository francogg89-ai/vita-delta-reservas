-- ====================================================================================
-- D1_Q2_OVERLOADS.sql
-- Bloque B1.3-consolidacion-canonica * D1 * overloads residuales
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

-- Q2 -- OVERLOADS RESIDUALES (N filas).
--   Busca por proname TODAS las firmas vivas del carril, sin asumir argumentos.
--   Motivo: B1_3_A ejecuta
--     DROP FUNCTION public.vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)
--   (la firma de siete argumentos, de B1.1).
--
--   Si ese DROP no corrio, queda un overload historico residual. Los callers B1.3 que
--   pasan jsonb resuelven inequivocamente la firma nueva; deben buscarse callers legacy
--   que todavia invoquen la firma de siete argumentos.
--
--   La comparacion es por OID, no por texto: regprocedure::text OMITE el schema cuando
--   el objeto es visible en el search_path, y cualquier match textual contra 'public.x(...)'
--   fallaria siempre.
SELECT
  'Q2_OVERLOADS'                                       AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  p.oid                                                AS oid,
  n.nspname                                            AS schema,
  p.proname                                            AS nombre,
  format('%I.%I(%s)', n.nspname, p.proname,
         pg_get_function_identity_arguments(p.oid))    AS firma_viva,
  pg_get_function_result(p.oid)                        AS retorno,
  pg_get_userbyid(p.proowner)                          AS owner,
  p.prokind                                            AS prokind,
  md5(pg_get_functiondef(p.oid))                       AS fingerprint,
  CASE WHEN EXISTS (
         SELECT 1 FROM unnest(ARRAY[
    to_regprocedure('public.resolver_horario(bigint,date)'),
           to_regprocedure('public._resolver_horario(bigint,date,boolean)'),
           to_regprocedure('public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)'),
           to_regprocedure('public.crear_vigencia_horario(jsonb)'),
           to_regprocedure('public.trg_guard_vigencias()'),
           to_regprocedure('public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)'),
           to_regprocedure('public.crear_prereserva(jsonb)'),
           to_regprocedure('public.confirmar_reserva(jsonb)'),
           to_regprocedure('public.crear_reserva_con_horario_pactado(jsonb)'),
           to_regprocedure('public.crear_override_horario_puntual(jsonb)'),
           to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')
         ]) AS e(o)
         WHERE e.o::oid = p.oid
       )
       THEN 'ESPERADO (esta en Q1)'
       ELSE '>>> SOBRANTE / OVERLOAD RESIDUAL <<<'
  END                                                  AS veredicto
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
ORDER BY p.proname, p.oid;

COMMIT;
