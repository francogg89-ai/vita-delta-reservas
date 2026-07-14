-- ====================================================================================
-- D1_Q3_ACL.sql
-- Bloque B1.3-consolidacion-canonica * D1 * ACL expandida
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

-- Q3 -- ACL EXPANDIDA (N filas).
--   aclexplode(COALESCE(proacl, acldefault('f', proowner))): cuando proacl IS NULL,
--   PostgreSQL aplica el ACL por defecto (EXECUTE a PUBLIC), que es exactamente lo que
--   el hardening REVOKEa. Sin el COALESCE, un objeto sin hardening se veria como
--   "sin grants" -> falso verde.
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
r AS (SELECT o.n, o.sig, to_regprocedure(o.sig) AS rp FROM objs o)
SELECT
  'Q3_ACL'                                                            AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  r.n                                                                 AS nro,
  r.sig                                                               AS firma,
  CASE WHEN a.grantee = 0 THEN 'PUBLIC'
       ELSE COALESCE(pg_get_userbyid(a.grantee), '<oid ' || a.grantee || '>') END AS grantee,
  pg_get_userbyid(a.grantor)                                          AS grantor,
  a.privilege_type                                                    AS privilegio,
  a.is_grantable                                                      AS grantable,
  CASE
    WHEN a.grantee = 0 AND a.privilege_type = 'EXECUTE'
      THEN '>>> EXECUTE A PUBLIC -- REVISAR HARDENING <<<'
    WHEN COALESCE(pg_get_userbyid(a.grantee),'') IN ('anon','authenticated','service_role')
         AND a.privilege_type = 'EXECUTE'
      THEN '>>> EXECUTE A ROL DATA API -- REVISAR HARDENING <<<'
    ELSE 'ok'
  END                                                                 AS veredicto
FROM r
JOIN pg_proc p ON p.oid = r.rp::oid
CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
ORDER BY r.n, grantee, a.privilege_type;

COMMIT;
