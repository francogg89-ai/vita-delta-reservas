-- ============================================================================
-- B2A -- Motor de Precios v2 : Estructura + Hardening + Seeds minimos
-- ----------------------------------------------------------------------------
-- Naturaleza : ADITIVO, TEST-only, gated anti-ambiente, IDEMPOTENTE (re-ejecutable).
-- NO toca    : funciones de motor, crear_prereserva, grillas masivas, hardening
--              legacy, OPS. Solo estructura + hardening + seeds minimos.
-- Frente     : Motor de Precios v2 (B2A). Canonico de partida: 6B_SCHEMA_SQL v1.12.0.
-- Ejecutar   : una sola transaccion. Si el gate falla, no aplica nada.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- GATE ANTI-AMBIENTE  (TEST-only)
--   El valor esperado esta hardcodeado a 'test'. NO cambiar a 'ops'/'prod':
--   la promocion a OPS es un paso coordinado posterior, no este artefacto.
--   Confirmar que configuracion_general('ambiente') en TEST == 'test'.
-- ---------------------------------------------------------------------------
DO $gate$
DECLARE
  v_amb      TEXT;
  v_esperado TEXT := 'test';
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  IF v_amb IS NULL THEN
    RAISE EXCEPTION 'B2A abortado: no existe configuracion_general(ambiente).';
  END IF;
  IF v_amb IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'B2A abortado: ambiente=% (esperado %). Migracion TEST-only.', v_amb, v_esperado;
  END IF;
END
$gate$;

-- ===========================================================================
-- 1) perfiles_tarifarios  (+ seed minimo indispensable)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS perfiles_tarifarios (
  perfil             TEXT        PRIMARY KEY,
  descripcion        TEXT,
  personas_incluidas INTEGER     NOT NULL,
  activo             BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_perfiles_incluidas CHECK (personas_incluidas >= 1)
);

INSERT INTO perfiles_tarifarios (perfil, descripcion, personas_incluidas) VALUES
  ('grande', 'Cabanas grandes', 4),
  ('chica',  'Cabanas chicas',  3)
ON CONFLICT (perfil) DO NOTHING;

DROP TRIGGER IF EXISTS trg_perfiles_tarifarios_updated_at ON perfiles_tarifarios;
CREATE TRIGGER trg_perfiles_tarifarios_updated_at
  BEFORE UPDATE ON perfiles_tarifarios
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================================================
-- 2) cabanas.perfil_tarifario  (columna aditiva + backfill + FK)
--    El backfill usa el FK como red: si alguna cabana tuviera un tipo sin
--    perfil mapeado, la migracion aborta (falla ruidosa, no NULL silencioso).
-- ===========================================================================
ALTER TABLE cabanas ADD COLUMN IF NOT EXISTS perfil_tarifario TEXT;

UPDATE cabanas SET perfil_tarifario = tipo WHERE perfil_tarifario IS NULL;

DO $fk_cab$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'cabanas_perfil_tarifario_fkey') THEN
    ALTER TABLE cabanas
      ADD CONSTRAINT cabanas_perfil_tarifario_fkey
      FOREIGN KEY (perfil_tarifario) REFERENCES perfiles_tarifarios(perfil);
  END IF;
END
$fk_cab$;

-- ===========================================================================
-- 3) tarifas_motor  (grilla versionada -- sin seed en B2A, va en B2B)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS tarifas_motor (
  id              BIGSERIAL     PRIMARY KEY,
  perfil          TEXT          NOT NULL REFERENCES perfiles_tarifarios(perfil),
  temporada_clave TEXT          NOT NULL,
  concepto        TEXT          NOT NULL,
  precio          NUMERIC(12,2) NOT NULL,
  vigente_desde   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  vigente_hasta   TIMESTAMPTZ,
  created_by      TEXT          NOT NULL,
  source_event    TEXT          NOT NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_tarifas_motor_temporada CHECK (temporada_clave IN ('alta','baja')),
  CONSTRAINT chk_tarifas_motor_concepto  CHECK (concepto IN (
    'semana_noche_1','semana_noche_2','semana_noche_3','semana_noche_4',
    'semana_noche_5plus','alta_demanda_noche_1','alta_demanda_noche_2',
    'alta_demanda_noche_3plus')),
  CONSTRAINT chk_tarifas_motor_precio_pos CHECK (precio > 0),
  CONSTRAINT chk_tarifas_motor_vigencia   CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_tarifas_motor_vigente
  ON tarifas_motor (perfil, temporada_clave, concepto)
  WHERE vigente_hasta IS NULL;

CREATE INDEX IF NOT EXISTS idx_tarifas_motor_lookup
  ON tarifas_motor (perfil, temporada_clave, concepto);

-- ===========================================================================
-- 4) temporada_vigencia  (materializacion standalone -- sin seed en B2A)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS temporada_vigencia (
  id              BIGSERIAL   PRIMARY KEY,
  temporada_clave TEXT        NOT NULL,
  anio            INTEGER     NOT NULL,
  fecha_in        DATE        NOT NULL,
  fecha_out_excl  DATE        NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_temporada_vigencia_clave CHECK (temporada_clave IN ('alta','baja')),
  CONSTRAINT chk_temporada_vigencia_rango CHECK (fecha_out_excl > fecha_in),
  CONSTRAINT uq_temporada_vigencia_anio   UNIQUE (temporada_clave, anio)
);

CREATE INDEX IF NOT EXISTS idx_temporada_vigencia_fechas
  ON temporada_vigencia (fecha_in, fecha_out_excl);

-- ===========================================================================
-- 5) noches_alta_demanda
-- ===========================================================================
CREATE TABLE IF NOT EXISTS noches_alta_demanda (
  fecha        DATE        PRIMARY KEY,
  origen       TEXT        NOT NULL,
  activo       BOOLEAN     NOT NULL DEFAULT TRUE,
  nombre       TEXT,
  created_by   TEXT        NOT NULL,
  source_event TEXT        NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_nad_origen CHECK (origen IN ('manual','importado','sugerido'))
);

DROP TRIGGER IF EXISTS trg_noches_alta_demanda_updated_at ON noches_alta_demanda;
CREATE TRIGGER trg_noches_alta_demanda_updated_at
  BEFORE UPDATE ON noches_alta_demanda
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================================================
-- 6) overrides_precio
-- ===========================================================================
CREATE TABLE IF NOT EXISTS overrides_precio (
  id             BIGSERIAL     PRIMARY KEY,
  tipo           TEXT          NOT NULL,
  perfil         TEXT          REFERENCES perfiles_tarifarios(perfil),  -- NULL = todos
  tipo_noche     TEXT          NOT NULL,
  fecha_in       DATE          NOT NULL,
  fecha_out_excl DATE          NOT NULL,
  valor          NUMERIC(12,2) NOT NULL,
  activo         BOOLEAN       NOT NULL DEFAULT TRUE,
  motivo         TEXT,
  created_by     TEXT          NOT NULL,
  source_event   TEXT          NOT NULL,
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_overrides_tipo      CHECK (tipo IN ('porcentual','absoluto')),
  CONSTRAINT chk_overrides_tiponoche CHECK (tipo_noche IN ('semana','alta_demanda','todas')),
  CONSTRAINT chk_overrides_rango     CHECK (fecha_out_excl > fecha_in),
  CONSTRAINT chk_overrides_valor     CHECK (
    (tipo = 'absoluto'   AND valor > 0) OR
    (tipo = 'porcentual' AND valor > -100))
);

CREATE INDEX IF NOT EXISTS idx_overrides_activos
  ON overrides_precio (fecha_in, fecha_out_excl)
  WHERE activo;

DROP TRIGGER IF EXISTS trg_overrides_precio_updated_at ON overrides_precio;
CREATE TRIGGER trg_overrides_precio_updated_at
  BEFORE UPDATE ON overrides_precio
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================================================
-- 7) cotizaciones_precio  (congelamiento web/bot -- escrita via conexion privilegiada)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS cotizaciones_precio (
  cotizacion_id UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  id_cabana     BIGINT        NOT NULL REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  perfil        TEXT          NOT NULL,           -- snapshot (sin FK, preserva valor historico)
  fecha_in      DATE          NOT NULL,
  fecha_out     DATE          NOT NULL,
  personas      INTEGER       NOT NULL,
  canal         TEXT          NOT NULL,
  precio_total  NUMERIC(12,2) NOT NULL,
  monto_sena    NUMERIC(12,2) NOT NULL,
  monto_saldo   NUMERIC(12,2) NOT NULL,
  precio_source TEXT          NOT NULL,
  snapshot      JSONB         NOT NULL,
  expires_at    TIMESTAMPTZ   NOT NULL,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_cotiz_fechas        CHECK (fecha_out > fecha_in),
  CONSTRAINT chk_cotiz_personas      CHECK (personas >= 1),
  CONSTRAINT chk_cotiz_canal         CHECK (canal IN ('web','whatsapp','bot','portal')),
  CONSTRAINT chk_cotiz_source        CHECK (precio_source IN ('motor_estandar','evento_especial','manual_override','mixto')),
  CONSTRAINT chk_cotiz_total_pos     CHECK (precio_total > 0),
  CONSTRAINT chk_cotiz_sena_nonneg   CHECK (monto_sena >= 0),
  CONSTRAINT chk_cotiz_saldo_nonneg  CHECK (monto_saldo >= 0),
  CONSTRAINT chk_cotiz_expira        CHECK (expires_at > created_at)
);

CREATE INDEX IF NOT EXISTS idx_cotizaciones_expira
  ON cotizaciones_precio (expires_at);

-- ===========================================================================
-- 8) Infra de auditoria de pricing : trigger propio + tabla append-only
--    trg_precios_inmutable() : namespace propio de pricing (NO reusa 9H).
--    Es infra de auditoria, no funcion de motor.
-- ===========================================================================
CREATE OR REPLACE FUNCTION trg_precios_inmutable()
RETURNS trigger
LANGUAGE plpgsql
AS $imm$
BEGIN
  RAISE EXCEPTION 'precios_auditoria es append-only: operacion % no permitida', TG_OP;
END
$imm$;

REVOKE EXECUTE ON FUNCTION trg_precios_inmutable() FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS precios_auditoria (
  id           BIGSERIAL   PRIMARY KEY,
  entidad      TEXT        NOT NULL,
  entidad_id   TEXT,
  accion       TEXT        NOT NULL,
  actor        TEXT        NOT NULL,
  source_event TEXT        NOT NULL,
  diff         JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_precios_auditoria_entidad CHECK (entidad IN (
    'tarifa_motor','override','noche_alta_demanda','evento','paquete','config','reserva'))
);

CREATE INDEX IF NOT EXISTS idx_precios_auditoria_entidad
  ON precios_auditoria (entidad, entidad_id);
CREATE INDEX IF NOT EXISTS idx_precios_auditoria_created
  ON precios_auditoria (created_at);

DROP TRIGGER IF EXISTS trg_precios_auditoria_inmutable ON precios_auditoria;
CREATE TRIGGER trg_precios_auditoria_inmutable
  BEFORE UPDATE OR DELETE ON precios_auditoria
  FOR EACH ROW EXECUTE FUNCTION trg_precios_inmutable();

-- ===========================================================================
-- 9) Columnas aditivas en reservas
--    reservas.cotizacion_id : link directo y durable a la cotizacion.
--    Justificacion: reservas.id_pre_reserva es NULLABLE y ON DELETE SET NULL,
--    por lo que la cadena reserva->pre_reserva->cotizacion no es estable
--    (NULL en reservas manuales; se rompe si se borra la pre-reserva).
-- ===========================================================================
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS precio_source      TEXT;
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS precio_motivo      TEXT;
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS precio_snapshot    JSONB;
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS capacidad_override BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS cotizacion_id      UUID;

DO $chk_res$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_reservas_precio_source') THEN
    ALTER TABLE reservas
      ADD CONSTRAINT chk_reservas_precio_source
      CHECK (precio_source IS NULL OR precio_source IN
             ('motor_estandar','evento_especial','manual_override','mixto'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reservas_cotizacion_id_fkey') THEN
    ALTER TABLE reservas
      ADD CONSTRAINT reservas_cotizacion_id_fkey
      FOREIGN KEY (cotizacion_id) REFERENCES cotizaciones_precio(cotizacion_id) ON DELETE SET NULL;
  END IF;
END
$chk_res$;

-- ===========================================================================
-- 10) pre_reservas.cotizacion_id  (trazabilidad web/bot)
-- ===========================================================================
ALTER TABLE pre_reservas ADD COLUMN IF NOT EXISTS cotizacion_id UUID;

DO $fk_pre$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pre_reservas_cotizacion_id_fkey') THEN
    ALTER TABLE pre_reservas
      ADD CONSTRAINT pre_reservas_cotizacion_id_fkey
      FOREIGN KEY (cotizacion_id) REFERENCES cotizaciones_precio(cotizacion_id) ON DELETE SET NULL;
  END IF;
END
$fk_pre$;

-- ===========================================================================
-- 11) Config keys de pricing  (infraestructura minima -- defaults)
-- ===========================================================================
INSERT INTO configuracion_general (clave, valor, tipo_valor, descripcion, categoria, editable) VALUES
  ('precio_bloque_finde_alta_activo',        'true',  'boolean', 'Bloque vie+sab obligatorio en temporada alta (canales automaticos)', 'pricing', TRUE),
  ('precio_extra_persona_activo',            'true',  'boolean', 'Activa el cargo por persona extra',                                 'pricing', TRUE),
  ('precio_extra_persona_monto',             '20000', 'integer', 'Monto por persona extra por noche (ARS)',                           'pricing', TRUE),
  ('precio_sena_pct_default',                '50',    'integer', 'Porcentaje de sena por defecto',                                    'pricing', TRUE),
  ('precio_recargo_saldo_transferencia_pct', '5',     'integer', 'Recargo por saldo via transferencia/MP (cargo separado)',           'pricing', TRUE),
  ('precio_estadia_larga_umbral_noches',     '10',    'integer', 'Umbral de noches para derivar a humano (reservable_online=false)',  'pricing', TRUE),
  ('precio_redondeo_base',                   '1000',  'integer', 'Base de redondeo por linea (ARS) -- tecnico',                       'pricing', FALSE),
  ('precio_cotizacion_ttl_minutos',          '30',    'integer', 'TTL de cotizacion congelada en minutos -- tecnico',                 'pricing', FALSE)
ON CONFLICT (clave) DO NOTHING;

-- ===========================================================================
-- 11-bis) Indice correctivo sobre tabla legacy (aditivo)
--   paquetes_evento.id_evento no tenia indice (FK sin indice, riesgo B1.1 #4).
--   Corrige lookups/cascada del motor de eventos. No es hardening legacy.
-- ===========================================================================
CREATE INDEX IF NOT EXISTS idx_paquetes_evento_id_evento
  ON paquetes_evento (id_evento);

-- ===========================================================================
-- 12) HARDENING : REVOKE ALL en tablas nuevas + secuencias (anti Data API)
--     RLS queda OFF (consistente con el principio schema-wide del canonico).
-- ===========================================================================
REVOKE ALL ON TABLE
  perfiles_tarifarios, tarifas_motor, temporada_vigencia, noches_alta_demanda,
  overrides_precio, cotizaciones_precio, precios_auditoria
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON SEQUENCE
  tarifas_motor_id_seq, temporada_vigencia_id_seq,
  overrides_precio_id_seq, precios_auditoria_id_seq
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

-- ============================================================================
-- FIN B2A. Correr B2A_VERIFY.sql y B2A_SMOKES.sql a continuacion.
-- ============================================================================
