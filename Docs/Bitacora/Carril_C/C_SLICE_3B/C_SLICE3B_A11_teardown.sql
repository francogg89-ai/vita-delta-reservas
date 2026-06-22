-- ============================================================================
-- VITA DELTA · CARRIL C · SLICE 3b · A11 — TEARDOWN SMOKE (TEST-only)
-- ----------------------------------------------------------------------------
-- Limpia, en TEST, los datos que dejan los smokes de A11 (gastos cargados +
-- su traza de idempotencia). NO toca el canonico, NO toca OPS, NO toca el
-- fixture 9F (ids 30-34, creado_por='seed_9f_validacion') ni ningun dato real.
--
-- MARCADOR: el smoke usa idempotency_key con prefijo 'smoke-a11-'. La traza
--   vive en portal_idempotencia (idempotency_key LIKE 'smoke-a11-%') y apunta
--   al gasto por id_gasto. gastos_internos NO tiene columna source_event (esa
--   columna es de portal_idempotencia), asi que el gasto smoke se identifica
--   SOLO por el id_gasto que trae su traza.
--
-- ORDEN FK-SAFE (obligatorio): la FK fk_portal_idempotencia_gasto es RESTRICT
--   (portal_idempotencia.id_gasto -> gastos_internos.id_gasto). NO se puede
--   borrar un gasto mientras su traza lo referencia. Por eso se borra PRIMERO
--   la traza y DESPUES el gasto, en UN solo statement: el CTE data-modifying
--   'borradas' borra las trazas y devuelve sus id_gasto por RETURNING; el
--   DELETE principal consume ese RETURNING para borrar los gastos. La
--   dependencia de datos (IN (SELECT id_gasto FROM borradas)) fuerza que la
--   traza ya este borrada cuando se evalua la FK RESTRICT del gasto. (Patron
--   validado: borra exactamente los smoke y deja intacto el dato real.)
--
-- ATOMICIDAD = GARANTIA DE COMPLETITUD: todo va dentro de BEGIN/COMMIT. Gasto y
--   traza se insertan atomicos en la funcion (no hay gasto sin traza). Si el
--   DELETE del gasto fallara, la transaccion entera revierte y las trazas NO se
--   borran -> el veredicto veria trazas_smoke > 0 (FAIL). Por lo tanto
--   trazas_smoke_restantes = 0 implica que tanto las trazas COMO sus gastos se
--   borraron de forma consistente. No hace falta (ni se puede) marcar el gasto
--   por separado.
--
-- RE-EJECUCION: idempotente. Si no hay smoke, borra 0 y el veredicto da PASS.
--
-- COMO CORRER: SQL Editor de Supabase del proyecto TEST, con NADA seleccionado
--   (L-8A-01), todo el archivo de una. El RAISE del gate aborta TODA la
--   transaccion si el ambiente no es 'test'. Resultado esperado: una fila de
--   veredicto en PASS (0 trazas smoke restantes). El conteo de lo que se va a
--   borrar sale por NOTICE (pestana de mensajes).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. GATE DE ENTORNO (ambiente='test' es la verdad; cabanas 1-5 es sanity)
--    Identico al gate del DDL de A11. Si no es TEST, aborta sin borrar nada.
-- ----------------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb        text;
  v_cab        int;
  v_pre_trazas bigint;
  v_pre_gastos bigint;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE 3b/A11 teardown: ambiente=% (esperado test). Abortado para no tocar OPS.',
      COALESCE(v_amb, '<ausente>');
  END IF;

  SELECT count(*) INTO v_cab
  FROM (VALUES (1,'Bamboo'),(2,'Madre Selva'),(3,'Arrebol'),(4,'Guatemala'),(5,'Tokio')) e(id,nom)
  WHERE EXISTS (SELECT 1 FROM cabanas c WHERE c.id_cabana = e.id AND c.nombre = e.nom);
  IF v_cab <> 5 THEN
    RAISE EXCEPTION 'GATE 3b/A11 teardown: identidad de cabanas no coincide (% de 5). DB inesperada.', v_cab;
  END IF;

  -- Pre-conteo informativo (sale por NOTICE; no condiciona el borrado).
  -- trazas smoke por marcador; gastos a borrar = los referenciados por esas trazas.
  SELECT count(*) INTO v_pre_trazas
  FROM public.portal_idempotencia WHERE idempotency_key LIKE 'smoke-a11-%';
  SELECT count(*) INTO v_pre_gastos
  FROM public.gastos_internos g
  WHERE g.id_gasto IN (
    SELECT pi.id_gasto FROM public.portal_idempotencia pi
    WHERE pi.idempotency_key LIKE 'smoke-a11-%' AND pi.id_gasto IS NOT NULL
  );
  RAISE NOTICE 'A11 teardown: a borrar -> trazas smoke=%, gastos smoke=%', v_pre_trazas, v_pre_gastos;
END
$gate$;

-- ----------------------------------------------------------------------------
-- 2. BORRADO FK-SAFE POR MARCADOR (traza primero via CTE, luego el gasto)
--    Un solo statement. 'borradas' borra las trazas smoke y devuelve sus
--    id_gasto; el DELETE principal borra esos gastos. El WHERE id_gasto IS NOT
--    NULL es defensivo (la traza siempre trae id_gasto en alta nueva).
-- ----------------------------------------------------------------------------
WITH borradas AS (
  DELETE FROM public.portal_idempotencia
  WHERE idempotency_key LIKE 'smoke-a11-%'
  RETURNING id_gasto
)
DELETE FROM public.gastos_internos
WHERE id_gasto IN (SELECT id_gasto FROM borradas WHERE id_gasto IS NOT NULL);

-- ----------------------------------------------------------------------------
-- 3. VEREDICTO: 0 trazas smoke restantes (gate de PASS/FAIL). Por la atomicidad
--    de la transaccion, esto implica que sus gastos tambien se borraron. El
--    conteo del fixture 9F es informativo (debe seguir intacto).
-- ----------------------------------------------------------------------------
SELECT
  jsonb_build_object(
    'trazas_smoke_restantes',
      (SELECT count(*) FROM public.portal_idempotencia WHERE idempotency_key LIKE 'smoke-a11-%'),
    'fixture_9f_intacto',
      (SELECT count(*) FROM public.gastos_internos WHERE creado_por = 'seed_9f_validacion')
  ) AS detalle,
  CASE
    WHEN (SELECT count(*) FROM public.portal_idempotencia WHERE idempotency_key LIKE 'smoke-a11-%') = 0
    THEN 'PASS'
    ELSE 'FAIL'
  END AS veredicto;

COMMIT;
