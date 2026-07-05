-- =====================================================================
-- HORARIOS_GUARD_S1_TRIGGER_TEST.sql
-- Sub-bloque S1 del guard de overrides horarios: la BARRERA DB.
-- ALCANCE: SOLO TEST. NO ejecutar en OPS. NO tocar canonico/gateway/frontend/workflows.
-- Sin acuñar D-*/L-*.
--
-- Contenido:
--   1) trg_guard_overrides()  -- trigger-fn: lock (10,0) + logica OLD/NEW + validadores S0 + RAISE parseable
--   2) CONSTRAINT TRIGGER trg_ov_guard AFTER INSERT OR UPDATE OR DELETE ... DEFERRABLE INITIALLY DEFERRED
--
-- NO incluye crear_override_horario ni crear_paquete_dia_especial (S2/S3).
-- Reemplaza el pedido original de BEFORE por deferred-AFTER: en BEFORE el resolver no ve el
--   estado final del paquete y obligaria a duplicar la precedencia del resolver (drift que R0
--   corrigio). El trigger NO reimplementa el resolver: delega en los validadores S0.
-- Metodo: CREATE OR REPLACE FUNCTION + DROP TRIGGER IF EXISTS + CREATE CONSTRAINT TRIGGER
--   (idempotente; auto-RLS OFF en TEST => sin bug Dashboard, L-CC-07).
-- Correr el script COMPLETO (sin seleccion parcial; L-8A-01).
-- =====================================================================

BEGIN;

-- ---- GATE anti-OPS + dependencias S0 ----
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM configuracion_general WHERE clave = 'ambiente');
  v_res text;
  v_odr text;
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE S1: ambiente=% (esperado test). Abortando.', v_amb;
  END IF;
  IF current_schema() IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'GATE S1: schema=% (esperado public). Abortando.', current_schema();
  END IF;
  v_res := md5(pg_get_functiondef(to_regprocedure('public.resolver_horario(bigint,date)')));
  IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
    RAISE EXCEPTION 'GATE S1: fingerprint resolver=% (esperado 58d75c1b6b812ee2d2c9751ddcb0cd4d, post-R0). Abortando.', v_res;
  END IF;
  v_odr := md5(pg_get_functiondef(to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')));
  IF v_odr IS DISTINCT FROM '37009a32154f93b80520500c0f15b46b' THEN
    RAISE EXCEPTION 'GATE S1: fingerprint ODR=% (esperado 37009a32154f93b80520500c0f15b46b). Abortando.', v_odr;
  END IF;
  IF to_regprocedure('public.validar_estado_horario_final(bigint,date)') IS NULL
     OR to_regprocedure('public.validar_no_eventos_comprometidos(bigint,date)') IS NULL
     OR to_regprocedure('public.validar_estado_override(bigint,date)') IS NULL THEN
    RAISE EXCEPTION 'GATE S1: faltan validadores S0. Corre HORARIOS_GUARD_S0_VALIDADORES_TEST.sql primero. Abortando.';
  END IF;
  RAISE NOTICE 'GATE S1 OK: ambiente=test, schema=public, resolver=58d75c1b, ODR=37009a32, validadores S0 presentes.';
END
$gate$;

-- =====================================================================
-- trigger-fn: barrera diferida. Toma el lock global (10,0) PRIMERO; computa el conjunto
--   afectado desde OLD/NEW segun operacion (con deteccion de cambio efectivo); delega la
--   validacion en validar_estado_override (validadores S0); RAISE parseable con DETAIL jsonb.
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_guard_overrides()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_old_applies boolean := false;
  v_new_applies boolean := false;
  v_old_id      text := NULL;
  v_new_id      text := NULL;
  rec           record;
  v_verd        jsonb;
BEGIN
  -- Capa 0: lock global de disponibilidad SIEMPRE primero (invariante, como crear_bloqueo).
  PERFORM pg_advisory_xact_lock(10, 0);

  -- Deteccion de cambio efectivo + lado activo por operacion (accesos OLD/NEW seguros por rama).
  IF TG_OP = 'INSERT' THEN
    v_new_applies := NEW.activo;
    IF NOT v_new_applies THEN RETURN NULL; END IF;             -- insert inactivo: sin efecto horario
    v_new_id := NEW.id_override::text;
  ELSIF TG_OP = 'DELETE' THEN
    v_old_applies := OLD.activo;
    IF NOT v_old_applies THEN RETURN NULL; END IF;             -- delete inactivo: sin efecto horario
    v_old_id := OLD.id_override::text;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Skip SOLO si el cambio se limita a columnas NO efectivas para el resolver.
    -- "Efectiva" = toda columna que el resolver lee para APLICABILIDAD (id_cabana, fecha_desde,
    -- fecha_hasta, tipo_override, activo), VALOR (valor), o PRECEDENCIA. El desempate del resolver es
    --   ORDER BY (id_cabana IS NOT NULL) DESC, created_at DESC, id_override DESC
    -- => created_at e id_override SON efectivas (pueden cambiar el override ganador y el horario
    --    efectivo sin tocar ninguna otra columna). NO son metadata inocua.
    -- Unicas columnas inertes (pueden cambiar en un skip): motivo, creado_por, source_event.
    -- INVARIANTE: si el resolver pasa a leer otra columna, agregarla aca.
    IF NOT (
         OLD.activo       IS DISTINCT FROM NEW.activo
      OR OLD.tipo_override IS DISTINCT FROM NEW.tipo_override
      OR OLD.valor         IS DISTINCT FROM NEW.valor
      OR OLD.fecha_desde   IS DISTINCT FROM NEW.fecha_desde
      OR OLD.fecha_hasta   IS DISTINCT FROM NEW.fecha_hasta
      OR OLD.id_cabana     IS DISTINCT FROM NEW.id_cabana
      OR OLD.created_at    IS DISTINCT FROM NEW.created_at    -- desempate del resolver (created_at DESC)
      OR OLD.id_override   IS DISTINCT FROM NEW.id_override   -- ultimo desempate del resolver (id_override DESC, PK)
    ) THEN
      RETURN NULL;
    END IF;
    v_old_applies := OLD.activo;   -- lado OLD cuenta si estaba activo
    v_new_applies := NEW.activo;   -- lado NEW cuenta si queda activo
    v_old_id := OLD.id_override::text;
    v_new_id := NEW.id_override::text;
  END IF;

  -- Conjunto afectado (id_cabana, fecha):
  --   applied_set(OLD) si v_old_applies  UNION  applied_set(NEW) si v_new_applies.
  --   applied_set = (esa cabaña, o todas las activas si id_cabana IS NULL)
  --                 x [fecha_desde, COALESCE(fecha_hasta, fecha_desde)]  (semantica R0: NULL = solo fecha_desde).
  FOR rec IN
    WITH src AS (
      SELECT OLD.id_cabana AS id_cabana, OLD.fecha_desde AS fd, OLD.fecha_hasta AS fh WHERE v_old_applies
      UNION ALL
      SELECT NEW.id_cabana AS id_cabana, NEW.fecha_desde AS fd, NEW.fecha_hasta AS fh WHERE v_new_applies
    )
    SELECT DISTINCT c.id_cabana AS id_cabana, g::date AS fecha
    FROM src
    JOIN cabanas c ON (src.id_cabana IS NULL AND c.activa) OR (c.id_cabana = src.id_cabana)
    CROSS JOIN LATERAL generate_series(src.fd, COALESCE(src.fh, src.fd), interval '1 day') AS g
  LOOP
    v_verd := validar_estado_override(rec.id_cabana, rec.fecha);
    IF NOT (v_verd->>'ok')::boolean THEN
      RAISE EXCEPTION 'guard_overrides: %', (v_verd->>'error')
        USING ERRCODE = '45000',
              DETAIL = jsonb_build_object(
                'error',             v_verd->>'error',
                'id_cabana',         rec.id_cabana,
                'fecha',             rec.fecha,
                'tg_op',             TG_OP,
                'id_override_old',   v_old_id,
                'id_override_new',   v_new_id,
                'detalle_validador', v_verd
              )::text;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;

-- Hardening: la trigger-fn no se invoca directo; REVOKE de todos modos por higiene.
REVOKE EXECUTE ON FUNCTION public.trg_guard_overrides() FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.trg_guard_overrides() IS
  'S1 guard horarios. Trigger-fn de la barrera diferida sobre overrides_operativos. Toma pg_advisory_xact_lock(10,0) primero; computa (id_cabana,fecha) afectados desde OLD/NEW segun INSERT/UPDATE/DELETE (skip de insert/delete inactivo y de UPDATE que solo toca columnas inertes motivo/creado_por/source_event); delega en validar_estado_override (S0, sin reimplementar el resolver); RAISE ERRCODE 45000 con DETAIL jsonb {error,id_cabana,fecha,tg_op,id_override_old,id_override_new,detalle_validador}. NOTA: created_at e id_override son columnas EFECTIVAS (desempate del resolver: ORDER BY (id_cabana IS NOT NULL) DESC, created_at DESC, id_override DESC), no metadata; un UPDATE de cualquiera de ellas se valida. Fase B - guard overrides.';

-- ---- Constraint trigger diferido (idempotente) ----
DROP TRIGGER IF EXISTS trg_ov_guard ON overrides_operativos;
CREATE CONSTRAINT TRIGGER trg_ov_guard
  AFTER INSERT OR UPDATE OR DELETE ON overrides_operativos
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION trg_guard_overrides();

COMMENT ON TRIGGER trg_ov_guard ON overrides_operativos IS
  'S1 guard horarios. Valida el estado efectivo FINAL (paquete completo) en el commit, no un NEW aislado. DEFERRABLE INITIALLY DEFERRED. Forzable en tests con SET CONSTRAINTS trg_ov_guard IMMEDIATE. Fase B - guard overrides.';

COMMIT;

-- ---- Confirmacion ----
SELECT
  to_regprocedure('public.trg_guard_overrides()') IS NOT NULL AS trigger_fn_ok,
  EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'overrides_operativos' AND t.tgname = 'trg_ov_guard' AND NOT t.tgisinternal
  ) AS constraint_trigger_ok;
