-- ============================================================================
-- B2B -- Motor de Precios v2 : Seeds de pricing
-- ----------------------------------------------------------------------------
-- Naturaleza : SOLO DATOS, aditivo, TEST-only, gated anti-ambiente, IDEMPOTENTE.
-- Toca       : temporada_vigencia (8 filas) + tarifas_motor (32 celdas vigentes).
-- NO toca    : estructura, reservas, pre_reservas, funciones de motor,
--              gateway/portal, hardening legacy, OPS.
-- Requisito  : B2A aplicado (fingerprint estructural da52a16c045689523a5f1f113f513a87).
--
-- VERSIONADO: cada celda se siembra SOLO si no existe ya una fila vigente para
-- (perfil, temporada_clave, concepto). Re-correr no duplica ni pisa versiones
-- posteriores creadas por portal. B2B es seed inicial, NO reset de grilla.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- GATE ANTI-AMBIENTE (TEST-only)
-- ---------------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb      TEXT;
  v_esperado TEXT := 'test';
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS NULL THEN
    RAISE EXCEPTION 'B2B abortado: no existe configuracion_general(ambiente).';
  END IF;
  IF v_amb IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'B2B abortado: ambiente=% (esperado %). Seed TEST-only.', v_amb, v_esperado;
  END IF;
END
$gate$;

-- ---------------------------------------------------------------------------
-- PRE-CHECK: B2A debe estar aplicado (tablas destino existen)
-- ---------------------------------------------------------------------------
DO $pre$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind='r' AND relname='tarifas_motor')
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind='r' AND relname='temporada_vigencia')
     OR NOT EXISTS (SELECT 1 FROM perfiles_tarifarios WHERE perfil IN ('grande','chica')) THEN
    RAISE EXCEPTION 'B2B abortado: B2A no esta aplicado (faltan tablas/perfiles de pricing).';
  END IF;
END
$pre$;

-- ===========================================================================
-- 1) temporada_vigencia -- 8 filas, cobertura continua 2026-03-15 -> 2030-03-15
--    D-PR-16: convencion anio = ANIO DE INICIO (alta 2026 = nov-2026 -> mar-2027).
--    Fin exclusive: cada fecha_out_excl == fecha_in de la fila siguiente.
--    Idempotente por UNIQUE (temporada_clave, anio).
-- ===========================================================================
INSERT INTO temporada_vigencia (temporada_clave, anio, fecha_in, fecha_out_excl) VALUES
  ('baja', 2026, DATE '2026-03-15', DATE '2026-11-15'),
  ('alta', 2026, DATE '2026-11-15', DATE '2027-03-15'),
  ('baja', 2027, DATE '2027-03-15', DATE '2027-11-15'),
  ('alta', 2027, DATE '2027-11-15', DATE '2028-03-15'),
  ('baja', 2028, DATE '2028-03-15', DATE '2028-11-15'),
  ('alta', 2028, DATE '2028-11-15', DATE '2029-03-15'),
  ('baja', 2029, DATE '2029-03-15', DATE '2029-11-15'),
  ('alta', 2029, DATE '2029-11-15', DATE '2030-03-15')
ON CONFLICT (temporada_clave, anio) DO NOTHING;

-- ===========================================================================
-- 2) tarifas_motor -- 4 grillas x 8 conceptos = 32 celdas vigentes
--    Precios confirmados por Franco. Todos > 0 y multiplos de $1.000.
--    Insert version-aware: solo siembra la celda si NO hay fila vigente.
-- ===========================================================================
WITH grilla (perfil, temporada_clave, concepto, precio) AS (
  VALUES
    -- ---------------- GRANDE / ALTA ----------------
    ('grande','alta','semana_noche_1',           165000::NUMERIC(12,2)),
    ('grande','alta','semana_noche_2',           130000),
    ('grande','alta','semana_noche_3',           105000),
    ('grande','alta','semana_noche_4',           105000),
    ('grande','alta','semana_noche_5plus',       105000),
    ('grande','alta','alta_demanda_noche_1',     255000),
    ('grande','alta','alta_demanda_noche_2',     130000),
    ('grande','alta','alta_demanda_noche_3plus', 190000),
    -- ---------------- GRANDE / BAJA ----------------
    ('grande','baja','semana_noche_1',           130000),
    ('grande','baja','semana_noche_2',           100000),
    ('grande','baja','semana_noche_3',            80000),
    ('grande','baja','semana_noche_4',            80000),
    ('grande','baja','semana_noche_5plus',        80000),
    ('grande','baja','alta_demanda_noche_1',     180000),
    ('grande','baja','alta_demanda_noche_2',     120000),
    ('grande','baja','alta_demanda_noche_3plus', 150000),
    -- ---------------- CHICA / ALTA -----------------
    ('chica','alta','semana_noche_1',            140000),
    ('chica','alta','semana_noche_2',            110000),
    ('chica','alta','semana_noche_3',             90000),
    ('chica','alta','semana_noche_4',             90000),
    ('chica','alta','semana_noche_5plus',         90000),
    ('chica','alta','alta_demanda_noche_1',      220000),
    ('chica','alta','alta_demanda_noche_2',      115000),
    ('chica','alta','alta_demanda_noche_3plus',  165000),
    -- ---------------- CHICA / BAJA -----------------
    ('chica','baja','semana_noche_1',            110000),
    ('chica','baja','semana_noche_2',             90000),
    ('chica','baja','semana_noche_3',             70000),
    ('chica','baja','semana_noche_4',             70000),
    ('chica','baja','semana_noche_5plus',         70000),
    ('chica','baja','alta_demanda_noche_1',      150000),
    ('chica','baja','alta_demanda_noche_2',      100000),
    ('chica','baja','alta_demanda_noche_3plus',  125000)
)
INSERT INTO tarifas_motor (perfil, temporada_clave, concepto, precio, created_by, source_event)
SELECT g.perfil, g.temporada_clave, g.concepto, g.precio, 'seed_b2b', 'b2b:seed_inicial'
FROM grilla g
WHERE NOT EXISTS (
  SELECT 1 FROM tarifas_motor t
  WHERE t.perfil          = g.perfil
    AND t.temporada_clave = g.temporada_clave
    AND t.concepto        = g.concepto
    AND t.vigente_hasta IS NULL          -- ya hay version vigente -> no pisar
);

COMMIT;

-- ============================================================================
-- FIN B2B. Correr B2B_VERIFY.sql y B2B_SMOKES.sql a continuacion.
-- ============================================================================
