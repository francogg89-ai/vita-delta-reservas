-- ============================================================================
-- portal-a29-retiro__GW_verify_OPS.sql  (companion de portal-a29-retiro__GW_smoke_OPS.ps1)
-- Corre en el SQL Editor de Supabase OPS (owner: acceso a portal_idempotencia_cc y
-- movimientos_socio, que son REVOKE-all y el smoke PS NO puede consultar).
--
-- READ-ONLY. El smoke OPS es NEGATIVE-ONLY: no hay retiro real. Este verify confirma
-- empiricamente 0 escrituras y 0 avance de secuencia.
--
-- Recordatorio L-8A-01: el SQL Editor ejecuta SOLO el texto SELECCIONADO; con nada
-- seleccionado corre todo y muestra el ULTIMO result set. Seleccionar el SELECT de cada PART.
--
-- PART A  (BASELINE): correr ANTES y DESPUES del smoke. Los dos snapshots deben ser IDENTICOS
--         (mov_filas, mov_max_id, mov_seq_last, idem_filas, idem_seq_last) -> 0 filas nuevas y
--         secuencias sin avance. idem_seq_last debe ser NULL (secuencia nunca usada).
-- PART B  (POSTCHECK): correr DESPUES del smoke. Checklist; todos deben dar PASS con esperado '0'
--         (o 'true' para la secuencia idem). Marcador de keys: 'smoke-a29gw-%'. La invariante
--         central: un retiro EXITOSO siempre inserta en portal_idempotencia_cc (idempotencia).
--         Si idem_cc esta vacia y su secuencia nunca se uso, NINGUN retiro se concreto.
-- ============================================================================

-- ---- Gate anti-entorno: OPS-only ------------------------------------------
DO $gate$
DECLARE v_amb text;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS DISTINCT FROM 'ops' THEN
    RAISE EXCEPTION 'GATE ambiente=% (esperado ops) -- abortado', COALESCE(v_amb, '(null)');
  END IF;
END $gate$;


-- ============================ PART A -- BASELINE ============================
-- Seleccionar y ejecutar SOLO este SELECT ANTES del smoke y OTRA VEZ DESPUES; comparar.
SELECT
  (SELECT count(*)         FROM public.movimientos_socio)               AS mov_filas,
  (SELECT max(id_movimiento) FROM public.movimientos_socio)            AS mov_max_id,
  pg_sequence_last_value(pg_get_serial_sequence('public.movimientos_socio','id_movimiento')::regclass) AS mov_seq_last,
  (SELECT count(*)         FROM public.portal_idempotencia_cc)          AS idem_filas,
  pg_sequence_last_value('public.portal_idempotencia_cc_id_registro_seq'::regclass) AS idem_seq_last;


-- ============================ PART B -- POSTCHECK ===========================
-- Seleccionar y ejecutar SOLO este SELECT DESPUES del smoke.
-- Cada fila: chequeo + esperado + obtenido + PASS/FAIL. NEGATIVE-ONLY => todo 0.
WITH
idem AS (
  SELECT idempotency_key
    FROM public.portal_idempotencia_cc
   WHERE idempotency_key LIKE 'smoke-a29gw-%'
),
checks(orden, chequeo, esperado, obtenido) AS (
  VALUES
    (1, 'idem_cc total filas (retiro exitoso SIEMPRE inserta aca; vacia = 0 retiros)',
        '0',
        (SELECT count(*)::text FROM public.portal_idempotencia_cc)),
    (2, 'idem_cc filas con marcador smoke (smoke-a29gw-%)',
        '0',
        (SELECT count(*)::text FROM idem)),
    (3, 'idem_cc K_SALDO ausente (saldo_insuficiente NO quema la key)',
        '0',
        (SELECT count(*)::text FROM idem WHERE idempotency_key = 'smoke-a29gw-saldo-insuf')),
    (4, 'idem_cc K_AJENO ausente (rechazo pre-dispatch)',
        '0',
        (SELECT count(*)::text FROM idem WHERE idempotency_key = 'smoke-a29gw-ajeno-payload')),
    (5, 'idem_cc K_SEC ausente (rechazos pre-dispatch)',
        '0',
        (SELECT count(*)::text FROM idem WHERE idempotency_key = 'smoke-a29gw-sec-reject')),
    (6, 'idem_cc secuencia NUNCA usada (last_value IS NULL => 0 nextval)',
        'true',
        (pg_sequence_last_value('public.portal_idempotencia_cc_id_registro_seq'::regclass) IS NULL)::text),
    (7, 'movimientos_socio: 0 retiros de smoke (comentario marcador)',
        '0',
        (SELECT count(*)::text FROM public.movimientos_socio
          WHERE tipo = 'retiro' AND comentario = 'A29 smoke gw OPS')),
    (8, 'movimientos_socio: 0 filas con marcador smoke en comentario (defensivo)',
        '0',
        (SELECT count(*)::text FROM public.movimientos_socio
          WHERE comentario LIKE '%smoke-a29%'))
)
SELECT
  orden,
  chequeo,
  esperado,
  obtenido,
  CASE WHEN esperado = obtenido THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM checks
ORDER BY orden;
