-- ====================================================================================
-- D1_Q8_CUERPOS.sql
-- Bloque B1.3-consolidacion-canonica * D1 * cuerpos completos pg_get_functiondef
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

-- Q8 -- CUERPOS COMPLETOS pg_get_functiondef() de los 11 (11 filas).
--   EXPORTAR A CSV desde el editor. No copiar a mano.
--   Necesarios para (a) resolver H4 y (b) consolidar el canonico v1.13.0 desde el VIVO,
--   no desde los artefactos del repo.
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
)
SELECT
  'Q8_CUERPOS'                                          AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  o.n                                                   AS nro,
  o.sig                                                 AS firma,
  md5(pg_get_functiondef(to_regprocedure(o.sig)))       AS fingerprint,
  octet_length(pg_get_functiondef(to_regprocedure(o.sig))) AS bytes,
  length(pg_get_functiondef(to_regprocedure(o.sig)))    AS caracteres,
  pg_get_functiondef(to_regprocedure(o.sig))            AS functiondef_completo
FROM objs o
WHERE to_regprocedure(o.sig) IS NOT NULL
ORDER BY o.n;

COMMIT;
