-- ====================================================================================
-- D1_Q5_DEPEND.sql
-- Bloque B1.3-consolidacion-canonica * D1 * dependencias pg_depend
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

-- Q5 -- DEPENDENCIAS pg_depend (N filas), en ambas direcciones.
--
--   LIMITACION EXPLICITA -- NO ES EXHAUSTIVO:
--     PostgreSQL NO registra en pg_depend las referencias que ocurren dentro del CUERPO
--     de una funcion PL/pgSQL, ni las de SQL dinamico (EXECUTE). pg_depend captura
--     dependencias de la SIGNATURA (tipos de argumento y de retorno), del lenguaje,
--     del schema, y de objetos referenciados por funciones SQL parseadas.
--     => Este bloque sirve para dependencias ESTRUCTURALES, no para logica de negocio.
--     => Los candidatos de callers estan en Q6 (heuristica por texto), no aca.
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
r AS (SELECT o.n, o.sig, to_regprocedure(o.sig)::oid AS oid FROM objs o WHERE to_regprocedure(o.sig) IS NOT NULL)
SELECT
  'Q5_DEPEND'                                                        AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  r.n                                                                AS nro,
  r.sig                                                              AS firma,
  'DEPENDE_DE'                                                       AS direccion,
  pg_describe_object(d.refclassid, d.refobjid, d.refobjsubid)        AS objeto_relacionado,
  d.deptype                                                          AS deptype
FROM r
JOIN pg_depend d ON d.classid = 'pg_proc'::regclass AND d.objid = r.oid
WHERE d.refclassid <> 'pg_type'::regclass OR d.deptype <> 'n'
UNION ALL
SELECT
  'Q5_DEPEND'                                                        AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente'),
  current_setting('transaction_read_only'),
  r.n,
  r.sig,
  'ES_USADO_POR'                                                     AS direccion,
  pg_describe_object(d.classid, d.objid, d.objsubid)                 AS objeto_relacionado,
  d.deptype                                                          AS deptype
FROM r
JOIN pg_depend d ON d.refclassid = 'pg_proc'::regclass AND d.refobjid = r.oid
ORDER BY 4, 6, 7;

COMMIT;
