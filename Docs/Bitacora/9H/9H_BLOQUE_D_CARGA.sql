-- ============================================================================
-- VITA DELTA · ETAPA 9H · BLOQUE D — CARGA REAL/CONTROLADA (persiste en TEST)
-- ============================================================================
-- Carga el estado mínimo para que Bloque E valide: snapshots jul/ago/nov @0.25,
-- un re-snapshot de julio (ejerce la cadena), un retiro y una conversión ligada.
-- D PERSISTE (COMMIT). E valida sobre lo persistido. Todo en TEST.
--
-- Condiciones (D-9H-38..; carril B):
--   1. PREFLIGHT duro: aborta si CUALQUIERA de las 5 tablas 9H ya tiene filas
--      (D no debe correrse dos veces; la capa es inmutable -> sin re-corrida segura).
--   2. IDs capturados en variables desde las funciones (C.3 ya avanzó secuencias;
--      NO se asume id_liquidacion=1, etc.).
--   3. Marcador creado_por='seed_9h_d' en snapshots, movimiento y revaluación.
--      OJO: el marcador TRAZA las filas; NO sirve para DELETE (triggers de
--      inmutabilidad frenan DELETE/TRUNCATE). Limpieza solo por DROP (ver teardown).
--   4. ASSERT pre-COMMIT: aborta si la estructura cargada no es exactamente la
--      esperada (D persiste; mejor revertir que commitear una carga defectuosa).
--   5. Teardown por DROP ordenado, sin CASCADE, documentado al pie SIN EJECUTAR.
-- Gate de ambiente: aborta si != test (L-9G-02).
-- Validado: harness PostgreSQL 16.14 (corrida limpia + preflight en 2da corrida + canónicos al centavo).
-- Resultado esperado en Supabase: COMMIT, luego la tabla de post-verificación.
-- ============================================================================
BEGIN;

-- ── GATE DE AMBIENTE ──
DO $gate$ BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave='ambiente') IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION '9H Bloque D abortado: ambiente != test';
  END IF;
END $gate$;

-- ── PREFLIGHT DURO: las 5 tablas deben estar vacías ──
DO $preflight$ BEGIN
  IF EXISTS (SELECT 1 FROM liquidaciones_periodo)
     OR EXISTS (SELECT 1 FROM liquidacion_cascada)
     OR EXISTS (SELECT 1 FROM liquidacion_socio)
     OR EXISTS (SELECT 1 FROM movimientos_socio)
     OR EXISTS (SELECT 1 FROM revaluaciones) THEN
    RAISE EXCEPTION '9H Bloque D abortado: ya hay filas en la capa 9H. D persiste y no debe correrse dos veces; la limpieza es solo por DROP (capa inmutable, D-9H-20).';
  END IF;
END $preflight$;

-- ── CARGA con captura de IDs ──
DO $carga$
DECLARE v_jul bigint; v_ago bigint; v_nov bigint; v_rejul bigint; v_retiro bigint; v_reval bigint;
BEGIN
  v_jul    := registrar_snapshot_periodo('2026-07-01',0.25,'seed_9h_d');
  v_ago    := registrar_snapshot_periodo('2026-08-01',0.25,'seed_9h_d');
  v_nov    := registrar_snapshot_periodo('2026-11-01',0.25,'seed_9h_d');
  v_rejul  := registrar_snapshot_periodo('2026-07-01',0.25,'seed_9h_d', v_jul, 're-snapshot D: ejerce la cadena de julio');
  v_retiro := registrar_retiro(2,'2026-09-01',50000,'transferencia','seed_9h_d','retiro D — Rodrigo');
  v_reval  := registrar_revaluacion(2,'2026-09-02',1000,30000,'parcial','seed_9h_d', v_retiro, 'conversión D ligada al retiro');
  RAISE NOTICE 'D cargado | snapshots: jul=% ago=% nov=% | re-snap jul=% (cola vigente) | retiro=% | reval=%',
    v_jul, v_ago, v_nov, v_rejul, v_retiro, v_reval;
END $carga$;

-- ── ASSERT PRE-COMMIT: estructura mínima esperada (D persiste -> abortar si no cuadra) ──
-- Solo estructura (conteos, marcador, fotos, vigencia). Los canónicos al centavo son Bloque E.
DO $assert_d$
DECLARE v_raiz_jul bigint; v_vig_jul bigint;
BEGIN
  IF (SELECT COUNT(*) FROM liquidaciones_periodo) <> 4 THEN RAISE EXCEPTION 'assert D: liquidaciones_periodo=% (esperado 4)', (SELECT COUNT(*) FROM liquidaciones_periodo); END IF;
  IF (SELECT COUNT(*) FROM liquidacion_cascada)   <> 32 THEN RAISE EXCEPTION 'assert D: liquidacion_cascada=% (esperado 32)', (SELECT COUNT(*) FROM liquidacion_cascada); END IF;
  IF (SELECT COUNT(*) FROM liquidacion_socio)     <> 12 THEN RAISE EXCEPTION 'assert D: liquidacion_socio=% (esperado 12)', (SELECT COUNT(*) FROM liquidacion_socio); END IF;
  IF (SELECT COUNT(*) FROM movimientos_socio)     <> 1  THEN RAISE EXCEPTION 'assert D: movimientos_socio=% (esperado 1)', (SELECT COUNT(*) FROM movimientos_socio); END IF;
  IF (SELECT COUNT(*) FROM revaluaciones)         <> 1  THEN RAISE EXCEPTION 'assert D: revaluaciones=% (esperado 1)', (SELECT COUNT(*) FROM revaluaciones); END IF;
  -- marcador presente donde corresponde
  IF (SELECT COUNT(*) FROM liquidaciones_periodo WHERE creado_por='seed_9h_d') <> 4 THEN RAISE EXCEPTION 'assert D: no todas las liquidaciones tienen marcador seed_9h_d'; END IF;
  IF (SELECT COUNT(*) FROM movimientos_socio      WHERE creado_por='seed_9h_d') <> 1 THEN RAISE EXCEPTION 'assert D: el movimiento no tiene marcador seed_9h_d'; END IF;
  IF (SELECT COUNT(*) FROM revaluaciones          WHERE creado_por='seed_9h_d') <> 1 THEN RAISE EXCEPTION 'assert D: la revaluacion no tiene marcador seed_9h_d'; END IF;
  -- fotos por período
  IF (SELECT COUNT(*) FROM liquidaciones_periodo WHERE periodo='2026-07-01') <> 2 THEN RAISE EXCEPTION 'assert D: julio tiene % fotos (esperado 2)', (SELECT COUNT(*) FROM liquidaciones_periodo WHERE periodo='2026-07-01'); END IF;
  IF (SELECT COUNT(*) FROM liquidaciones_periodo WHERE periodo='2026-08-01') <> 1 THEN RAISE EXCEPTION 'assert D: agosto tiene % fotos (esperado 1)', (SELECT COUNT(*) FROM liquidaciones_periodo WHERE periodo='2026-08-01'); END IF;
  IF (SELECT COUNT(*) FROM liquidaciones_periodo WHERE periodo='2026-11-01') <> 1 THEN RAISE EXCEPTION 'assert D: noviembre tiene % fotos (esperado 1)', (SELECT COUNT(*) FROM liquidaciones_periodo WHERE periodo='2026-11-01'); END IF;
  -- cada foto: 8 pasos de cascada y 3 filas de socio
  IF EXISTS (SELECT 1 FROM liquidaciones_periodo lp
             WHERE (SELECT COUNT(*) FROM liquidacion_cascada WHERE id_liquidacion=lp.id_liquidacion) <> 8)
     THEN RAISE EXCEPTION 'assert D: alguna foto no tiene 8 pasos de cascada'; END IF;
  IF EXISTS (SELECT 1 FROM liquidaciones_periodo lp
             WHERE (SELECT COUNT(*) FROM liquidacion_socio WHERE id_liquidacion=lp.id_liquidacion) <> 3)
     THEN RAISE EXCEPTION 'assert D: alguna foto no tiene 3 filas de socio'; END IF;
  -- vigencia de julio = re-snapshot (no la raíz)
  SELECT id_liquidacion INTO v_raiz_jul FROM liquidaciones_periodo WHERE periodo='2026-07-01' AND id_liquidacion_supersede IS NULL;
  v_vig_jul := liquidacion_vigente('2026-07-01');
  IF v_vig_jul IS NULL          THEN RAISE EXCEPTION 'assert D: vigente julio es NULL'; END IF;
  IF v_vig_jul = v_raiz_jul     THEN RAISE EXCEPTION 'assert D: vigente julio es la raíz (id=%); debería ser el re-snapshot', v_raiz_jul; END IF;
  IF (SELECT id_liquidacion_supersede FROM liquidaciones_periodo WHERE id_liquidacion=v_vig_jul) <> v_raiz_jul
     THEN RAISE EXCEPTION 'assert D: el vigente julio no supersede a la raíz'; END IF;
  RAISE NOTICE 'assert D: estructura OK (4 fotos, 32 casc, 12 soc, 1 mov, 1 reval, marcador completo, julio vigente=re-snapshot id=%)', v_vig_jul;
END $assert_d$;

COMMIT;

-- ════════════════ POST-VERIFICACIÓN (read-only; resumen estructural) ════════════════
-- Qué quedó cargado (filas, marcador, fotos, saldo vivo). La validación al CENTAVO
-- contra los canónicos es Bloque E, separado.
WITH filas AS (
  SELECT '1·tabla·liquidaciones_periodo' orden, 'filas / con marcador' item,
         COUNT(*)||' / '||COUNT(*) FILTER (WHERE creado_por='seed_9h_d') valor FROM liquidaciones_periodo
  UNION ALL SELECT '1·tabla·liquidacion_cascada','filas',           COUNT(*)::text FROM liquidacion_cascada
  UNION ALL SELECT '1·tabla·liquidacion_socio','filas',             COUNT(*)::text FROM liquidacion_socio
  UNION ALL SELECT '1·tabla·movimientos_socio','filas / con marcador', COUNT(*)||' / '||COUNT(*) FILTER (WHERE creado_por='seed_9h_d') FROM movimientos_socio
  UNION ALL SELECT '1·tabla·revaluaciones','filas / con marcador',   COUNT(*)||' / '||COUNT(*) FILTER (WHERE creado_por='seed_9h_d') FROM revaluaciones
),
fotos AS (
  SELECT '2·foto·'||to_char(lp.periodo,'YYYY-MM')||'·id'||lp.id_liquidacion orden,
         'vigente / casc / soc / supersede' item,
         (lp.id_liquidacion = liquidacion_vigente(lp.periodo))::text||' / '
         ||(SELECT COUNT(*) FROM liquidacion_cascada WHERE id_liquidacion=lp.id_liquidacion)||' / '
         ||(SELECT COUNT(*) FROM liquidacion_socio   WHERE id_liquidacion=lp.id_liquidacion)||' / '
         ||COALESCE(lp.id_liquidacion_supersede::text,'(raíz)') valor
  FROM liquidaciones_periodo lp
),
saldos AS (
  SELECT '3·saldo·'||s.nombre||'·'||sc.componente orden, 'monto' item, sc.monto::text valor
  FROM (VALUES (1),(2),(3)) v(id) JOIN socios s ON s.id_socio=v.id,
       LATERAL saldo_corriente_socio(s.id_socio) sc
)
SELECT orden, item, valor FROM filas
UNION ALL SELECT orden, item, valor FROM fotos
UNION ALL SELECT orden, item, valor FROM saldos
ORDER BY orden;

-- ════════════════════════════════════════════════════════════════════════════
-- TEARDOWN — DOCUMENTADO, **NO EJECUTAR**
-- ════════════════════════════════════════════════════════════════════════════
-- La capa 9H es append-only e inmutable. El marcador 'seed_9h_d' permite TRAZAR
-- las filas de D, pero NO borrarlas: los triggers trg_9h_inmutable frenan DELETE y
-- TRUNCATE. La ÚNICA limpieza es el DROP ordenado de las 5 tablas + la función de
-- trigger, SIN CASCADE (D-9H-20). Orden (dependientes -> padres):
--
--   DROP TABLE revaluaciones;
--   DROP TABLE movimientos_socio;
--   DROP TABLE liquidacion_socio;
--   DROP TABLE liquidacion_cascada;
--   DROP TABLE liquidaciones_periodo;
--   DROP FUNCTION trg_9h_inmutable();
--
-- Las secuencias BIGSERIAL son owned by sus columnas: se eliminan junto con sus
-- tablas. Los triggers se eliminan junto con sus tablas. Esto recrea 9H limpio
-- (p.ej. al resetear TEST, o como parte de la promoción a OPS que parte de cero).
-- No usar CASCADE: el orden explícito documenta y respeta las dependencias.
-- ════════════════════════════════════════════════════════════════════════════
