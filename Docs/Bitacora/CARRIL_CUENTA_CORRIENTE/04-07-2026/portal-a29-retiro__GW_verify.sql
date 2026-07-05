-- ============================================================================
-- portal-a29-retiro__GW_verify.sql  (companion de portal-a29-retiro__GW_smoke.ps1)
-- Corre en el SQL Editor de Supabase TEST (owner: acceso a portal_idempotencia_cc y
-- movimientos_socio, que son REVOKE-all y el smoke PS NO puede consultar).
--
-- Recordatorio L-8A-01: el SQL Editor ejecuta SOLO el texto SELECCIONADO; con nada
-- seleccionado corre todo el archivo y muestra el ULTIMO result set. Para PART A,
-- seleccionar su SELECT. Para PART B, seleccionar su SELECT (o correr todo y mirar el ultimo).
--
-- PART A  (PRECHECK, correr ANTES del smoke): id_socio + saldo vivo del socio (franco).
--         F1 (monto 0.01) requiere saldo_vivo >= 0.01. Si es menor, elegir otro socio.
-- PART B  (POSTCHECK, correr DESPUES del smoke): checklist de estado en la DB.
--         Marcador de keys: 'smoke-a29gw-%'. Esperado tras un smoke en verde:
--           - EXACTAMENTE 1 fila en portal_idempotencia_cc (K_F1); K_SALDO/ajeno/spoof = 0.
--           - EXACTAMENTE 1 retiro en movimientos_socio (monto -0.01, comentario 'A29 smoke gw').
--         (append-only: ese unico retiro no se puede borrar; re-correr el smoke es idempotente.)
-- ============================================================================


-- ============================ PART A -- PRECHECK ============================
-- Seleccionar y ejecutar SOLO este SELECT antes de correr el smoke.
SELECT
  pu.nombre,
  pu.rol,
  pu.id_socio,
  ccv.saldo_al_dia                         AS saldo_vivo,
  (ccv.saldo_al_dia >= 0.01)               AS f1_puede_escribir
FROM public.portal_usuarios pu
LEFT JOIN public.cuenta_corriente_viva(NULL, public.pct_operativo_vigente()) ccv
       ON ccv.id_socio = pu.id_socio
WHERE pu.nombre = 'franco';


-- ============================ PART B -- POSTCHECK ===========================
-- Seleccionar y ejecutar SOLO este SELECT despues de correr el smoke.
-- Cada fila: chequeo + esperado + obtenido + PASS/FAIL.
WITH
idem AS (
  SELECT idempotency_key, id_movimiento
    FROM public.portal_idempotencia_cc
   WHERE idempotency_key LIKE 'smoke-a29gw-%'
),
movs AS (
  SELECT m.*
    FROM public.movimientos_socio m
   WHERE m.id_movimiento IN (SELECT id_movimiento FROM idem)
),
movs_coment AS (
  SELECT *
    FROM public.movimientos_socio
   WHERE tipo = 'retiro' AND comentario = 'A29 smoke gw'
),
checks(orden, chequeo, esperado, obtenido) AS (
  VALUES
    (1, 'idem_cc filas smoke (total)',
        '1',
        (SELECT count(*)::text FROM idem)),
    (2, 'idem_cc fila K_F1 presente',
        '1',
        (SELECT count(*)::text FROM idem WHERE idempotency_key = 'smoke-a29gw-f1-retiro')),
    (3, 'idem_cc K_SALDO ausente (saldo_insuficiente NO quema key)',
        '0',
        (SELECT count(*)::text FROM idem WHERE idempotency_key = 'smoke-a29gw-saldo-insuf')),
    (4, 'idem_cc K_AJENO ausente (rechazo pre-dispatch)',
        '0',
        (SELECT count(*)::text FROM idem WHERE idempotency_key = 'smoke-a29gw-ajeno-payload')),
    (5, 'idem_cc K_SEC ausente (rechazos pre-dispatch)',
        '0',
        (SELECT count(*)::text FROM idem WHERE idempotency_key = 'smoke-a29gw-sec-reject')),
    (6, 'movimientos ligados a idem_cc smoke (total)',
        '1',
        (SELECT count(*)::text FROM movs)),
    (7, 'retiro K_F1: es tipo=retiro con monto -0.01',
        '1',
        (SELECT count(*)::text FROM movs WHERE tipo = 'retiro' AND monto = -0.01)),
    (8, 'movimientos por comentario A29 smoke gw (total)',
        '1',
        (SELECT count(*)::text FROM movs_coment)),
    (9, 'retiro K_F1: creado_por = franco',
        '1',
        (SELECT count(*)::text FROM movs WHERE creado_por = 'franco'))
)
SELECT
  orden,
  chequeo,
  esperado,
  obtenido,
  CASE WHEN esperado = obtenido THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM checks
ORDER BY orden;
