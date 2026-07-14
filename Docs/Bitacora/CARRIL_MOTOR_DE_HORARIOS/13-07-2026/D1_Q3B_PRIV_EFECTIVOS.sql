-- ====================================================================================
-- D1_Q3B_PRIV_EFECTIVOS.sql
-- Bloque B1.3-consolidacion-canonica * D1 * privilegios efectivos anon/authenticated/service_role
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

-- Q3-BIS -- PRIVILEGIOS EFECTIVOS de los 3 roles de la Data API (11 x 3 = 33 filas).
--   has_function_privilege resuelve herencia y PUBLIC: es la verdad operativa,
--   mas fuerte que leer proacl a ojo.
WITH objs(n, sig) AS (
  VALUES
    ( 1,'public.resolver_horario(bigint,date)'),
    ( 2,'public._resolver_horario(bigint,date,boolean)'),
    ( 3,'public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)'),
    ( 4,'public.crear_vigencia_horario(jsonb)'),
    ( 5,'public.trg_guard_vigencias()'),
    ( 6,'public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)'),
    ( 7,'public.crear_prereserva(jsonb)'),
    ( 8,'public.confirmar_reserva(jsonb)'),
    ( 9,'public.crear_reserva_con_horario_pactado(jsonb)'),
    (10,'public.crear_override_horario_puntual(jsonb)'),
    (11,'public.obtener_disponibilidad_rango(date,date,bigint)')
),
roles(rolname) AS (VALUES ('anon'),('authenticated'),('service_role'))
SELECT
  'Q3B_PRIV_EFECTIVOS'                                      AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  o.n                                                       AS nro,
  o.sig                                                     AS firma,
  ro.rolname                                                AS rol,
  CASE
    WHEN to_regprocedure(o.sig) IS NULL THEN NULL
    WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ro.rolname) THEN NULL
    ELSE has_function_privilege(ro.rolname, to_regprocedure(o.sig)::oid, 'EXECUTE')
  END                                                       AS puede_ejecutar,
  CASE
    WHEN to_regprocedure(o.sig) IS NULL THEN 'OBJETO AUSENTE'
    WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ro.rolname) THEN 'ROL INEXISTENTE'
    WHEN has_function_privilege(ro.rolname, to_regprocedure(o.sig)::oid, 'EXECUTE')
      THEN '>>> EXPUESTA -- REVISAR <<<'
    ELSE 'ok (revocada)'
  END                                                       AS veredicto
FROM objs o CROSS JOIN roles ro
ORDER BY o.n, ro.rolname;

COMMIT;
