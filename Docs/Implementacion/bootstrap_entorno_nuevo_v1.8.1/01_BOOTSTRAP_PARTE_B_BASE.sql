-- ============================================================================
-- BOOTSTRAP ENTORNO NUEVO v1.8.1 — 01: PARTE B (SCHEMA BASE) · DDL EJECUTABLE
-- Fuente: 6B_SCHEMA_SQL.md v1.8.1, PARTE B, Bloques 1→23 (EXTRACCIÓN LITERAL).
--   Solo el DDL de cada bloque. NO incluye los fences de "Verificación post-
--   ejecución", "Test funcional", "Monitoreo" ni "Rollback" del canónico (esos
--   no se ejecutan en bootstrap). La verificación de cierre vive en
--   01_VERIFY_PARTE_B_BASE.sql (fila-veredicto).
-- ----------------------------------------------------------------------------
-- ESTADO DE ENTRADA: 00_PRECHECK == BASE_VACIA_OK (proyecto nuevo/vacío).
-- USO: SQL Editor del PROYECTO NUEVO (confirmar Project Ref por URL; nunca OPS).
--   Se puede pegar el archivo COMPLETO, o por SECCIONES delimitadas con
--   "-- ═══ BLOQUE N ═══", una a la vez con NADA seleccionado (L-8A-01).
-- ALCANCE: NO toca el Carril B (zonas, activaciones, 9H, seam, matriz, cascada,
--   ni el marcador ambiente='dev'). Todo eso es 02_BOOTSTRAP_PARTE_C_CARRIL_B.sql.
-- HARDENING: el Bloque 23 (REVOKE EXECUTE sobre las 13 funciones del motor) cierra
--   el gap por el que un bootstrap fresco las dejaba PUBLIC-ejecutables (NULL-acl).
--   Es REVOKE directo por firma, sin gate de ambiente: en Parte B el marcador
--   'ambiente' todavía no existe (lo siembra C13.1). Idempotente DENTRO del flujo
--   de bootstrap nuevo/vacío; NO habilita a correr este archivo sobre OPS existente.
-- ============================================================================


-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 1 — Extensiones
-- ══════════════════════════════════════════════════════════════════════════
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 2 — Enums
-- ══════════════════════════════════════════════════════════════════════════
CREATE TYPE estado_prereserva_enum AS ENUM (
  'pendiente_pago',
  'pago_en_revision',
  'vencida',
  'convertida',
  'cancelada_por_cliente',
  'cancelada_por_bloqueo',
  'conflicto_pendiente'
);

CREATE TYPE estado_reserva_enum AS ENUM (
  'confirmada',
  'activa',
  'completada',
  'cancelada',
  'cancelada_con_cargo',
  'conflicto_pendiente'
);

CREATE TYPE estado_pago_enum AS ENUM (
  'pendiente',
  'en_revision',
  'confirmado',
  'rechazado',
  'reembolsado'
);

CREATE TYPE nivel_log_enum AS ENUM (
  'info',
  'warning',
  'error'
);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 3 — Tablas catálogo
-- ══════════════════════════════════════════════════════════════════════════
-- ── CABAÑAS ───────────────────────────────────────────────
CREATE TABLE cabanas (
  id_cabana       BIGSERIAL PRIMARY KEY,
  nombre          TEXT NOT NULL,
  tipo            TEXT NOT NULL,
  capacidad_base  INTEGER NOT NULL,
  capacidad_max   INTEGER NOT NULL,
  activa          BOOLEAN NOT NULL DEFAULT TRUE,
  orden_limpieza  INTEGER,
  descripcion     TEXT,
  fotos_urls      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_cabanas_nombre UNIQUE (nombre),
  CONSTRAINT chk_cabanas_capacidad_logica CHECK (capacidad_base <= capacidad_max),
  CONSTRAINT chk_cabanas_capacidad_positiva CHECK (capacidad_base >= 1 AND capacidad_max >= 1)
);

-- ── HUÉSPEDES (con telefono_normalizado nuevo en v1.1) ────
CREATE TABLE huespedes (
  id_huesped              BIGSERIAL PRIMARY KEY,
  nombre                  TEXT NOT NULL,
  apellido                TEXT,
  dni                     TEXT,
  telefono                TEXT,
  telefono_normalizado    TEXT,
  email                   TEXT,
  canal_preferido         TEXT,
  primera_reserva_fecha   DATE,
  total_reservas          INTEGER NOT NULL DEFAULT 0,
  notas_internas          TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_huespedes_contacto_minimo CHECK (telefono IS NOT NULL OR email IS NOT NULL)
);

CREATE UNIQUE INDEX uq_huespedes_dni
  ON huespedes(dni) WHERE dni IS NOT NULL;

CREATE UNIQUE INDEX uq_huespedes_telefono_normalizado
  ON huespedes(telefono_normalizado) WHERE telefono_normalizado IS NOT NULL;

CREATE UNIQUE INDEX uq_huespedes_email
  ON huespedes(LOWER(email)) WHERE email IS NOT NULL;

-- ── FERIADOS ──────────────────────────────────────────────
CREATE TABLE feriados (
  fecha     DATE PRIMARY KEY,
  nombre    TEXT NOT NULL,
  tipo      TEXT,
  activo    BOOLEAN NOT NULL DEFAULT TRUE
);

-- ── TARIFAS ───────────────────────────────────────────────
CREATE TABLE tarifas (
  id_tarifa      BIGSERIAL PRIMARY KEY,
  tipo_cabana    TEXT NOT NULL,
  concepto       TEXT NOT NULL,
  precio         NUMERIC(12,2) NOT NULL,
  descripcion    TEXT,
  activa         BOOLEAN NOT NULL DEFAULT TRUE,
  valida_desde   DATE,
  valida_hasta   DATE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_tarifas_precio CHECK (precio >= 0)
);

CREATE UNIQUE INDEX uq_tarifas_concepto_vigente
  ON tarifas(tipo_cabana, concepto, valida_desde) WHERE activa = TRUE;

-- ── TEMPORADAS ────────────────────────────────────────────
CREATE TABLE temporadas (
  id_temporada     BIGSERIAL PRIMARY KEY,
  nombre           TEXT NOT NULL,
  fecha_desde      DATE NOT NULL,
  fecha_hasta      DATE NOT NULL,
  multiplicador    NUMERIC(5,3) NOT NULL,
  activa           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_temporadas_multiplicador CHECK (multiplicador > 0),
  CONSTRAINT chk_temporadas_fechas CHECK (fecha_hasta > fecha_desde)
);

-- ── SOCIOS ────────────────────────────────────────────────
CREATE TABLE socios (
  id_socio                BIGSERIAL PRIMARY KEY,
  nombre                  TEXT NOT NULL,
  porcentaje_utilidades   NUMERIC(5,2) NOT NULL,
  whatsapp                TEXT,
  activo                  BOOLEAN NOT NULL DEFAULT TRUE,

  CONSTRAINT chk_socios_porcentaje CHECK (porcentaje_utilidades >= 0 AND porcentaje_utilidades <= 100)
);

-- ── CUENTAS_COBRO ─────────────────────────────────────────
CREATE TABLE cuentas_cobro (
  id_cuenta      BIGSERIAL PRIMARY KEY,
  alias          TEXT NOT NULL,
  medio          TEXT NOT NULL,
  detalle        TEXT,
  titular        TEXT,
  activa         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_cuentas_medio CHECK (medio IN ('transferencia_bancaria', 'transferencia_mp', 'cripto', 'efectivo'))
);

-- ── PLANTILLAS_MENSAJES ───────────────────────────────────
CREATE TABLE plantillas_mensajes (
  id_plantilla   BIGSERIAL PRIMARY KEY,
  codigo         TEXT NOT NULL,
  nombre         TEXT NOT NULL,
  canal          TEXT NOT NULL,
  destinatario   TEXT NOT NULL,
  contenido      TEXT NOT NULL,
  variables      TEXT,
  activa         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_plantillas_codigo UNIQUE (codigo),
  CONSTRAINT chk_plantillas_canal CHECK (canal IN ('whatsapp', 'instagram', 'todos')),
  CONSTRAINT chk_plantillas_destinatario CHECK (destinatario IN ('huesped', 'equipo', 'limpieza', 'franco'))
);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 4 — Tablas de configuración
-- ══════════════════════════════════════════════════════════════════════════
-- ── CONFIGURACION_GENERAL ─────────────────────────────────
CREATE TABLE configuracion_general (
  clave              TEXT PRIMARY KEY,
  valor              TEXT NOT NULL,
  tipo_valor         TEXT,
  descripcion        TEXT,
  categoria          TEXT,
  editable           BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── EVENTOS_ESPECIALES ────────────────────────────────────
CREATE TABLE eventos_especiales (
  id_evento          BIGSERIAL PRIMARY KEY,
  nombre             TEXT NOT NULL,
  fecha_desde        DATE NOT NULL,
  fecha_hasta        DATE NOT NULL,
  modo_precio        TEXT,
  reglas_especiales  JSONB,
  activa             BOOLEAN NOT NULL DEFAULT TRUE,
  source_event       TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_eventos_fechas CHECK (fecha_hasta >= fecha_desde)
);

-- ── PAQUETES_EVENTO ───────────────────────────────────────
CREATE TABLE paquetes_evento (
  id_paquete       BIGSERIAL PRIMARY KEY,
  id_evento        BIGINT NOT NULL REFERENCES eventos_especiales(id_evento) ON DELETE CASCADE,
  tipo_cabana      TEXT NOT NULL,
  nombre_paquete   TEXT NOT NULL,
  fecha_in         DATE,
  fecha_out        DATE,
  precio_total     NUMERIC(12,2) NOT NULL DEFAULT 0,
  personas_max     INTEGER,
  incluye          TEXT,
  notas            TEXT,
  activo           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── DESCUENTOS ────────────────────────────────────────────
CREATE TABLE descuentos (
  id_descuento          BIGSERIAL PRIMARY KEY,
  nombre                TEXT NOT NULL,
  tipo                  TEXT NOT NULL,
  valor                 NUMERIC(12,2) NOT NULL,
  aplica_a              TEXT NOT NULL,
  aplica_sobre          TEXT NOT NULL,
  fecha_desde           DATE,
  fecha_hasta           DATE,
  codigo                TEXT,
  usos_maximos          INTEGER,
  usos_actuales         INTEGER NOT NULL DEFAULT 0,
  minimo_noches         INTEGER,
  monto_minimo          NUMERIC(12,2),
  prioridad             INTEGER NOT NULL DEFAULT 100,
  combinable            BOOLEAN NOT NULL DEFAULT FALSE,
  requiere_aprobacion   BOOLEAN NOT NULL DEFAULT FALSE,
  activo                BOOLEAN NOT NULL DEFAULT TRUE,
  source_event          TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_descuentos_valor_positivo CHECK (valor > 0),
  CONSTRAINT chk_descuentos_tipo CHECK (tipo IN ('porcentaje', 'monto_fijo', 'noche_gratis')),
  CONSTRAINT chk_descuentos_aplica_a CHECK (aplica_a IN ('todas', 'grande', 'chica')),
  CONSTRAINT chk_descuentos_aplica_sobre CHECK (aplica_sobre IN ('alojamiento', 'extras', 'total')),
  CONSTRAINT chk_descuentos_fechas CHECK (
    (fecha_desde IS NULL OR fecha_hasta IS NULL) OR (fecha_hasta >= fecha_desde)
  )
);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 5 — Tablas dependientes nivel 1
-- ══════════════════════════════════════════════════════════════════════════
-- ── CONSULTAS ─────────────────────────────────────────────
CREATE TABLE consultas (
  id_consulta             BIGSERIAL PRIMARY KEY,
  canal                   TEXT NOT NULL,
  id_contacto_externo     TEXT NOT NULL,
  id_huesped              BIGINT REFERENCES huespedes(id_huesped) ON DELETE SET NULL,
  estado_conversacion     TEXT NOT NULL DEFAULT 'nueva',
  id_cabana_tentativa     BIGINT REFERENCES cabanas(id_cabana) ON DELETE SET NULL,
  fecha_in_tentativa      DATE,
  fecha_out_tentativa     DATE,
  personas_tentativa      INTEGER,
  ultimo_mensaje_at       TIMESTAMPTZ,
  contexto_json           JSONB,
  tokens_json             JSONB,
  motivo_derivacion       TEXT,
  source_event            TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_consultas_canal CHECK (canal IN ('whatsapp', 'instagram', 'web', 'manual')),
  CONSTRAINT chk_consultas_estado CHECK (
    estado_conversacion IN ('nueva', 'en_progreso', 'derivada_humano', 'cerrada', 'descartada')
  )
);

CREATE INDEX idx_consultas_estado ON consultas(estado_conversacion);
CREATE INDEX idx_consultas_huesped ON consultas(id_huesped);
CREATE INDEX idx_consultas_contacto_externo ON consultas(id_contacto_externo);

-- ── OVERRIDES_OPERATIVOS ──────────────────────────────────
-- NOTA DE TRAZABILIDAD (v1.1):
-- 'escalonamiento_umbral_checkins_dia' es el rename oficial cerrado en Etapa 2 v1.3 y Etapa 5A v1.1.
-- Reemplaza a las antiguas claves 'escalonamiento_umbral_checkout' y 'escalonamiento_umbral_checkin'.
-- No cambiar este nombre sin actualizar primero esa documentación.
CREATE TABLE overrides_operativos (
  id_override     BIGSERIAL PRIMARY KEY,
  fecha_desde     DATE NOT NULL,
  fecha_hasta     DATE,
  id_cabana       BIGINT REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  tipo_override   TEXT NOT NULL,
  valor           TEXT NOT NULL,
  motivo          TEXT NOT NULL,
  creado_por      TEXT NOT NULL,
  activo          BOOLEAN NOT NULL DEFAULT TRUE,
  source_event    TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_overrides_tipo CHECK (
    tipo_override IN (
      'escalonamiento_activo',
      'escalonamiento_umbral_checkins_dia',  -- ver nota de trazabilidad arriba
      'hora_checkin',
      'hora_checkout',
      'checkin_flexible',
      'checkout_flexible',
      'minimo_noches',
      'disponibilidad_bloqueada'
    )
  ),
  CONSTRAINT chk_overrides_fechas CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);

CREATE INDEX idx_overrides_activo_fechas ON overrides_operativos(activo, fecha_desde, fecha_hasta);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 6 — Tablas transaccionales
-- ══════════════════════════════════════════════════════════════════════════
-- ── PRE_RESERVAS (con campos nuevos v1.1) ─────────────────
CREATE TABLE pre_reservas (
  id_pre_reserva         BIGSERIAL PRIMARY KEY,
  id_consulta            BIGINT REFERENCES consultas(id_consulta) ON DELETE SET NULL,
  id_cabana              BIGINT NOT NULL REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  id_huesped             BIGINT NOT NULL REFERENCES huespedes(id_huesped) ON DELETE RESTRICT,
  fecha_in               DATE NOT NULL,
  fecha_out              DATE NOT NULL,
  hora_checkin           TIME NOT NULL,
  hora_checkout          TIME NOT NULL,
  personas               INTEGER NOT NULL,
  monto_total            NUMERIC(12,2) NOT NULL,
  monto_sena             NUMERIC(12,2) NOT NULL,
  estado                 estado_prereserva_enum NOT NULL DEFAULT 'pendiente_pago',
  expira_en              TIMESTAMPTZ NOT NULL,
  canal_pago_esperado    TEXT NOT NULL,
  canal_origen           TEXT NOT NULL,
  intentos_pago          INTEGER NOT NULL DEFAULT 0,
  referencia_mp          TEXT,
  notas                  TEXT,
  source_event           TEXT NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Campos operativos (D16)
  mascotas               BOOLEAN NOT NULL DEFAULT FALSE,
  detalle_mascotas       TEXT,
  ninos                  TEXT,
  notas_reserva          TEXT,

  -- Idempotencia (v1.1)
  idempotency_key        TEXT,

  CONSTRAINT chk_pre_reservas_fechas CHECK (fecha_out > fecha_in),
  CONSTRAINT chk_pre_reservas_personas CHECK (personas >= 1),
  CONSTRAINT chk_pre_reservas_monto_total CHECK (monto_total > 0),
  CONSTRAINT chk_pre_reservas_sena_logica CHECK (monto_sena >= 0 AND monto_sena <= monto_total),
  CONSTRAINT chk_pre_reservas_canal_origen CHECK (
    canal_origen IN ('whatsapp', 'instagram', 'web', 'manual')
  ),
  CONSTRAINT chk_pre_reservas_canal_pago CHECK (
    canal_pago_esperado IN ('transferencia_bancaria', 'transferencia_mp', 'mp_link', 'cripto', 'efectivo')
  )
);

CREATE INDEX idx_pre_reservas_estado ON pre_reservas(estado);
CREATE INDEX idx_pre_reservas_cabana_fechas ON pre_reservas(id_cabana, fecha_in, fecha_out);
CREATE INDEX idx_pre_reservas_expira ON pre_reservas(expira_en) WHERE estado = 'pendiente_pago';
CREATE INDEX idx_pre_reservas_huesped ON pre_reservas(id_huesped);

-- Índice parcial para idempotency (v1.1, decisión D26)
CREATE UNIQUE INDEX uq_prereservas_idempotency_activa
  ON pre_reservas(idempotency_key)
  WHERE idempotency_key IS NOT NULL
    AND estado IN ('pendiente_pago', 'pago_en_revision');

-- ── RESERVAS (con campos operativos v1.1) ─────────────────
CREATE TABLE reservas (
  id_reserva              BIGSERIAL PRIMARY KEY,
  id_pre_reserva          BIGINT REFERENCES pre_reservas(id_pre_reserva) ON DELETE SET NULL,
  id_cabana               BIGINT NOT NULL REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  id_huesped              BIGINT NOT NULL REFERENCES huespedes(id_huesped) ON DELETE RESTRICT,
  fecha_checkin           DATE NOT NULL,
  fecha_checkout          DATE NOT NULL,
  hora_checkin            TIME NOT NULL,
  hora_checkout           TIME NOT NULL,
  personas                INTEGER NOT NULL,
  estado                  estado_reserva_enum NOT NULL DEFAULT 'confirmada',
  canal_origen            TEXT NOT NULL,
  id_tarifa_aplicada      BIGINT REFERENCES tarifas(id_tarifa) ON DELETE SET NULL,
  monto_total             NUMERIC(12,2) NOT NULL,
  monto_sena              NUMERIC(12,2) NOT NULL,
  monto_saldo             NUMERIC(12,2) NOT NULL,
  encargado_semana        TEXT,
  notas                   TEXT,
  created_by              TEXT,
  source_event            TEXT NOT NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Campos operativos (D17 — preservan info al confirmar)
  mascotas                BOOLEAN NOT NULL DEFAULT FALSE,
  detalle_mascotas        TEXT,
  ninos                   TEXT,
  notas_reserva           TEXT,

  CONSTRAINT chk_reservas_fechas CHECK (fecha_checkout > fecha_checkin),
  CONSTRAINT chk_reservas_personas CHECK (personas >= 1),
  CONSTRAINT chk_reservas_monto_total CHECK (monto_total > 0),
  CONSTRAINT chk_reservas_saldo_logica CHECK (monto_saldo >= 0 AND monto_saldo <= monto_total),
  CONSTRAINT chk_reservas_canal_origen CHECK (
    canal_origen IN ('whatsapp', 'instagram', 'web', 'manual', 'airbnb', 'booking')
  )
);

CREATE INDEX idx_reservas_estado ON reservas(estado);
CREATE INDEX idx_reservas_cabana_fechas ON reservas(id_cabana, fecha_checkin, fecha_checkout);
CREATE INDEX idx_reservas_huesped ON reservas(id_huesped);
CREATE INDEX idx_reservas_fecha_checkin ON reservas(fecha_checkin);

-- ── PAGOS (cambios v1.1: id_prereserva nullable + CHECK) ──
CREATE TABLE pagos (
  id_pago               BIGSERIAL PRIMARY KEY,
  id_prereserva         BIGINT REFERENCES pre_reservas(id_pre_reserva) ON DELETE RESTRICT,
  id_reserva            BIGINT REFERENCES reservas(id_reserva) ON DELETE SET NULL,
  tipo                  TEXT NOT NULL,
  medio_pago            TEXT NOT NULL,
  proveedor             TEXT,
  cuenta_destino        TEXT,
  monto_esperado        NUMERIC(12,2) NOT NULL,
  monto_recibido        NUMERIC(12,2) NOT NULL,
  moneda                TEXT NOT NULL DEFAULT 'ARS',
  estado                estado_pago_enum NOT NULL DEFAULT 'pendiente',
  es_automatico         BOOLEAN NOT NULL DEFAULT FALSE,
  comprobante_url       TEXT,
  referencia_externa    TEXT,
  tx_hash               TEXT,
  validado_por          TEXT,
  validado_en           TIMESTAMPTZ,
  motivo_rechazo        TEXT,
  notas                 TEXT,
  source_event          TEXT NOT NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_pagos_tipo CHECK (tipo IN ('sena', 'saldo', 'extra', 'reembolso', 'ajuste')),
  CONSTRAINT chk_pagos_medio CHECK (
    medio_pago IN ('transferencia_bancaria', 'transferencia_mp', 'mp_link', 'cripto', 'efectivo')
  ),
  CONSTRAINT chk_pagos_monto_recibido CHECK (monto_recibido >= 0),
  CONSTRAINT chk_pagos_monto_esperado CHECK (monto_esperado > 0),
  -- Cambio v1.1: al menos una de las dos referencias debe existir
  CONSTRAINT chk_pagos_referencia_minima CHECK (id_prereserva IS NOT NULL OR id_reserva IS NOT NULL)
);

CREATE INDEX idx_pagos_prereserva ON pagos(id_prereserva) WHERE id_prereserva IS NOT NULL;
CREATE INDEX idx_pagos_reserva ON pagos(id_reserva) WHERE id_reserva IS NOT NULL;
CREATE INDEX idx_pagos_estado ON pagos(estado);

-- ── BLOQUEOS ──────────────────────────────────────────────
CREATE TABLE bloqueos (
  id_bloqueo      BIGSERIAL PRIMARY KEY,
  id_cabana       BIGINT REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  fecha_desde     DATE NOT NULL,
  fecha_hasta     DATE NOT NULL,
  motivo          TEXT NOT NULL,
  descripcion     TEXT,
  creado_por      TEXT NOT NULL,
  activo          BOOLEAN NOT NULL DEFAULT TRUE,
  source_event    TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_bloqueos_fechas CHECK (fecha_hasta > fecha_desde),
  CONSTRAINT chk_bloqueos_motivo CHECK (
    motivo IN ('mantenimiento', 'uso_propio', 'tormenta', 'overbooking', 'otro')
  )
);

CREATE INDEX idx_bloqueos_activo_fechas ON bloqueos(activo, fecha_desde, fecha_hasta) WHERE activo = TRUE;

-- ── GASTOS ────────────────────────────────────────────────
CREATE TABLE gastos (
  id_gasto         BIGSERIAL PRIMARY KEY,
  fecha            DATE NOT NULL,
  categoria        TEXT NOT NULL,
  descripcion      TEXT NOT NULL,
  monto            NUMERIC(12,2) NOT NULL,
  id_cabana        BIGINT REFERENCES cabanas(id_cabana) ON DELETE SET NULL,
  pagado_por       TEXT NOT NULL,
  reembolsable     BOOLEAN NOT NULL DEFAULT FALSE,
  comprobante_url  TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_gastos_fecha ON gastos(fecha);
CREATE INDEX idx_gastos_categoria ON gastos(categoria);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 7 — Tabla de auditoría
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE log_cambios (
  id_log              BIGSERIAL PRIMARY KEY,
  fecha_hora          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  tabla_afectada      TEXT NOT NULL,
  id_registro         TEXT,
  campo_modificado    TEXT,
  valor_anterior      TEXT,
  valor_nuevo         TEXT,
  modificado_por      TEXT NOT NULL,
  source_event        TEXT NOT NULL,
  nivel               nivel_log_enum NOT NULL DEFAULT 'info',
  detalle             JSONB
);

CREATE INDEX idx_log_cambios_fecha ON log_cambios(fecha_hora DESC);
CREATE INDEX idx_log_cambios_tabla ON log_cambios(tabla_afectada);
CREATE INDEX idx_log_cambios_nivel ON log_cambios(nivel) WHERE nivel != 'info';
CREATE INDEX idx_log_cambios_detalle_gin ON log_cambios USING GIN(detalle);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 8 — Constraints EXCLUDE
-- ══════════════════════════════════════════════════════════════════════════
-- No-overlap en reservas confirmadas/activas
ALTER TABLE reservas
  ADD CONSTRAINT exc_reservas_no_overlap
  EXCLUDE USING gist (
    id_cabana WITH =,
    daterange(fecha_checkin, fecha_checkout, '[)') WITH &&
  ) WHERE (estado IN ('confirmada', 'activa'));

-- No-overlap en bloqueos activos sobre cabaña específica
-- (bloqueos totales con id_cabana NULL se validan en crear_bloqueo)
ALTER TABLE bloqueos
  ADD CONSTRAINT exc_bloqueos_no_overlap
  EXCLUDE USING gist (
    id_cabana WITH =,
    daterange(fecha_desde, fecha_hasta, '[)') WITH &&
  ) WHERE (activo = TRUE AND id_cabana IS NOT NULL);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 9 — Función normalizar_telefono + columna + trigger
-- ══════════════════════════════════════════════════════════════════════════
-- ── Helper: normalizar_telefono ──────────────────────────
-- IMMUTABLE: para que pueda usarse en índices funcionales si hace falta.
-- Reglas:
--   - NULL/'' → NULL
--   - quitar espacios, guiones, paréntesis, puntos
--   - '00' inicial → '+'
--   - colapsar múltiples '+' consecutivos a uno solo
--   - no asumir +54 automático (Vita Delta puede recibir extranjeros)
CREATE OR REPLACE FUNCTION normalizar_telefono(input TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  IF input IS NULL OR TRIM(input) = '' THEN
    RETURN NULL;
  END IF;

  -- Quitar espacios, guiones, paréntesis, puntos
  v_clean := REGEXP_REPLACE(input, '[\s\-\(\)\.]', '', 'g');

  -- Si empieza con '00', reemplazar por '+'
  IF v_clean LIKE '00%' THEN
    v_clean := '+' || SUBSTRING(v_clean FROM 3);
  END IF;

  -- Colapsar múltiples '+' a uno solo (solo válido al inicio)
  -- Primero: quitar todos los '+' excepto el primero
  IF v_clean LIKE '+%' THEN
    v_clean := '+' || REGEXP_REPLACE(SUBSTRING(v_clean FROM 2), '[^0-9]', '', 'g');
  ELSE
    -- Sin '+', dejar solo dígitos
    v_clean := REGEXP_REPLACE(v_clean, '[^0-9]', '', 'g');
  END IF;

  -- Si quedó vacío después de limpiar, retornar NULL
  IF v_clean = '' OR v_clean = '+' THEN
    RETURN NULL;
  END IF;

  RETURN v_clean;
END;
$$;

-- ── Trigger function para mantener telefono_normalizado ──
CREATE OR REPLACE FUNCTION set_telefono_normalizado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.telefono_normalizado := normalizar_telefono(NEW.telefono);
  RETURN NEW;
END;
$$;

-- ── Trigger en huespedes ─────────────────────────────────
CREATE TRIGGER trg_huespedes_telefono_norm
  BEFORE INSERT OR UPDATE OF telefono ON huespedes
  FOR EACH ROW EXECUTE FUNCTION set_telefono_normalizado();

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 10 — Función upsert_huesped
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION upsert_huesped(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_nombre            TEXT;
  v_apellido          TEXT;
  v_dni               TEXT;
  v_telefono_raw      TEXT;
  v_telefono_norm     TEXT;
  v_email_raw         TEXT;
  v_email_norm        TEXT;
  v_canal_preferido   TEXT;
  v_huesped           huespedes%ROWTYPE;
  v_huesped_existente huespedes%ROWTYPE;
  v_found_by          TEXT;
  v_constraint_name   TEXT;
BEGIN
  -- Extraer y limpiar campos del payload (NULL si vienen vacíos)
  v_nombre          := NULLIF(TRIM(payload->>'nombre'), '');
  v_apellido        := NULLIF(TRIM(payload->>'apellido'), '');
  v_dni             := NULLIF(TRIM(payload->>'dni'), '');
  v_telefono_raw    := NULLIF(TRIM(payload->>'telefono'), '');
  v_email_raw       := NULLIF(TRIM(payload->>'email'), '');
  v_canal_preferido := NULLIF(TRIM(payload->>'canal_preferido'), '');

  -- Normalizar teléfono usando el helper
  v_telefono_norm := normalizar_telefono(v_telefono_raw);

  -- Normalizar email
  IF v_email_raw IS NOT NULL THEN
    v_email_norm := LOWER(v_email_raw);
  END IF;

  -- 1. Buscar por telefono_normalizado
  IF v_telefono_norm IS NOT NULL THEN
    SELECT * INTO v_huesped
    FROM huespedes
    WHERE telefono_normalizado = v_telefono_norm
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
      v_found_by := 'telefono';
    END IF;
  END IF;

  -- 2. Si no encontró por teléfono, buscar por email normalizado
  IF v_huesped.id_huesped IS NULL AND v_email_norm IS NOT NULL THEN
    SELECT * INTO v_huesped
    FROM huespedes
    WHERE LOWER(email) = v_email_norm
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
      v_found_by := 'email';
    END IF;
  END IF;

  -- 3. Si encontró: UPDATE selectivo (solo campos con valor real)
  IF v_huesped.id_huesped IS NOT NULL THEN
    BEGIN
      UPDATE huespedes SET
        nombre          = COALESCE(v_nombre, nombre),
        apellido        = COALESCE(v_apellido, apellido),
        dni             = COALESCE(v_dni, dni),
        telefono        = COALESCE(v_telefono_raw, telefono),
        -- telefono_normalizado se actualiza por trigger al modificar telefono
        email           = COALESCE(v_email_norm, email),
        canal_preferido = COALESCE(v_canal_preferido, canal_preferido),
        updated_at      = NOW()
      WHERE id_huesped = v_huesped.id_huesped;

    EXCEPTION
      WHEN unique_violation THEN
        -- Caso raro: el UPDATE intenta poner un DNI/email/telefono que ya pertenece a OTRO huésped.
        -- Devolver error controlado.
        GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
        RETURN jsonb_build_object(
          'ok',         false,
          'error',      'huesped_duplicado',
          'conflicto',  CASE
                          WHEN v_constraint_name LIKE '%dni%' THEN 'dni'
                          WHEN v_constraint_name LIKE '%email%' THEN 'email'
                          WHEN v_constraint_name LIKE '%telefono%' THEN 'telefono'
                          ELSE 'desconocido'
                        END,
          'detalle',    jsonb_build_object('constraint', v_constraint_name)
        );
    END;

    RETURN jsonb_build_object(
      'ok',             true,
      'modo',           'update',
      'id_huesped',     v_huesped.id_huesped,
      'encontrado_por', v_found_by
    );
  END IF;

  -- 4. CREATE — validar contacto mínimo
  IF v_telefono_norm IS NULL AND v_email_norm IS NULL THEN
    RETURN jsonb_build_object(
      'ok',     false,
      'error',  'contacto_requerido',
      'motivo', 'Debe venir al menos telefono o email'
    );
  END IF;

  -- 5. INSERT con manejo diferenciado de unique_violation
  BEGIN
    INSERT INTO huespedes (
      nombre, apellido, dni, telefono, email, canal_preferido
    ) VALUES (
      COALESCE(v_nombre, 'Sin nombre'),
      v_apellido,
      v_dni,
      v_telefono_raw,
      v_email_norm,
      v_canal_preferido
    )
    RETURNING * INTO v_huesped;

  EXCEPTION
    WHEN unique_violation THEN
      -- Captura el nombre del constraint que falló
      GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;

      -- Caso A: conflicto por DNI → ERROR CONTROLADO (D36)
      -- DNI duplicado con datos distintos es ambiguo. No fusionar silenciosamente.
      IF v_constraint_name LIKE '%dni%' THEN
        SELECT * INTO v_huesped_existente
        FROM huespedes WHERE dni = v_dni LIMIT 1;

        RETURN jsonb_build_object(
          'ok',                    false,
          'error',                 'huesped_duplicado',
          'conflicto',             'dni',
          'id_huesped_existente',  v_huesped_existente.id_huesped,
          'detalle',               jsonb_build_object(
            'nombre',           v_huesped_existente.nombre,
            'apellido',         v_huesped_existente.apellido,
            'telefono_parcial', RIGHT(v_huesped_existente.telefono_normalizado, 4),
            'email_parcial',    SPLIT_PART(v_huesped_existente.email, '@', 2)
          ),
          'motivo',                'DNI duplicado con datos distintos. Revisar manualmente.'
        );
      END IF;

      -- Caso B: conflicto por teléfono normalizado → RECUPERACIÓN SILENCIOSA (D36)
      -- Carrera típica: dos requests simultáneos para el mismo huésped.
      IF v_constraint_name LIKE '%telefono%' THEN
        SELECT * INTO v_huesped
        FROM huespedes WHERE telefono_normalizado = v_telefono_norm LIMIT 1;

        IF FOUND THEN
          RETURN jsonb_build_object(
            'ok',             true,
            'modo',           'recovered_from_unique_violation',
            'id_huesped',     v_huesped.id_huesped,
            'encontrado_por', 'telefono'
          );
        END IF;
      END IF;

      -- Caso C: conflicto por email → RECUPERACIÓN SILENCIOSA (D36)
      IF v_constraint_name LIKE '%email%' THEN
        SELECT * INTO v_huesped
        FROM huespedes WHERE LOWER(email) = v_email_norm LIMIT 1;

        IF FOUND THEN
          RETURN jsonb_build_object(
            'ok',             true,
            'modo',           'recovered_from_unique_violation',
            'id_huesped',     v_huesped.id_huesped,
            'encontrado_por', 'email'
          );
        END IF;
      END IF;

      -- Si no entró en ningún caso conocido o no se encontró el match esperado:
      -- error técnico controlado, no error crudo.
      RETURN jsonb_build_object(
        'ok',         false,
        'error',      'huesped_conflicto_inesperado',
        'detalle',    jsonb_build_object('constraint', v_constraint_name)
      );
  END;

  RETURN jsonb_build_object(
    'ok',             true,
    'modo',           'create',
    'id_huesped',     v_huesped.id_huesped,
    'encontrado_por', NULL
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 11 — Función validar_disponibilidad
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION validar_disponibilidad(
  p_id_cabana       BIGINT,
  p_fecha_in        DATE,
  p_fecha_out       DATE,
  p_excluir_prereserva BIGINT DEFAULT NULL  -- para excluir la propia al confirmar
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
-- ADVERTENCIA (v1.5 - Obs G):
-- Esta función usa SELECT ... FOR UPDATE internamente.
-- DEBE llamarse desde transacciones que ya tomaron pg_advisory_xact_lock(10, 0).
-- En flujos críticos, llamarla sin lock global puede causar deadlocks (40P01).
DECLARE
  v_cabana          cabanas%ROWTYPE;
  v_conflictos      JSONB := '[]'::JSONB;
  v_tiene_conflicto BOOLEAN := FALSE;
BEGIN
  -- Validar argumentos básicos
  IF p_fecha_out <= p_fecha_in THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas');
  END IF;

  IF p_id_cabana IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'id_cabana_requerido');
  END IF;

  -- Verificar cabaña existe y activa
  SELECT * INTO v_cabana FROM cabanas WHERE id_cabana = p_id_cabana FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_existe');
  END IF;

  IF NOT v_cabana.activa THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_inactiva');
  END IF;

  -- Conflicto con reservas (confirmada o activa)
  IF EXISTS (
    SELECT 1 FROM reservas
    WHERE id_cabana = p_id_cabana
      AND estado IN ('confirmada', 'activa')
      AND daterange(fecha_checkin, fecha_checkout, '[)')
          && daterange(p_fecha_in, p_fecha_out, '[)')
    FOR UPDATE
  ) THEN
    v_conflictos := v_conflictos || jsonb_build_array(
      jsonb_build_object('fuente', 'reservas')
    );
    v_tiene_conflicto := TRUE;
  END IF;

  -- Conflicto con pre_reservas vigentes (excluyendo la propia si aplica)
  IF EXISTS (
    SELECT 1 FROM pre_reservas
    WHERE id_cabana = p_id_cabana
      AND (p_excluir_prereserva IS NULL OR id_pre_reserva != p_excluir_prereserva)
      AND (
        (estado = 'pendiente_pago' AND expira_en > NOW())
        OR estado = 'pago_en_revision'
      )
      AND daterange(fecha_in, fecha_out, '[)')
          && daterange(p_fecha_in, p_fecha_out, '[)')
    FOR UPDATE
  ) THEN
    v_conflictos := v_conflictos || jsonb_build_array(
      jsonb_build_object('fuente', 'pre_reservas')
    );
    v_tiene_conflicto := TRUE;
  END IF;

  -- Conflicto con bloqueos activos (específicos o totales)
  IF EXISTS (
    SELECT 1 FROM bloqueos
    WHERE activo = TRUE
      AND (id_cabana = p_id_cabana OR id_cabana IS NULL)
      AND daterange(fecha_desde, fecha_hasta, '[)')
          && daterange(p_fecha_in, p_fecha_out, '[)')
    FOR UPDATE
  ) THEN
    v_conflictos := v_conflictos || jsonb_build_array(
      jsonb_build_object('fuente', 'bloqueos')
    );
    v_tiene_conflicto := TRUE;
  END IF;

  IF v_tiene_conflicto THEN
    RETURN jsonb_build_object(
      'ok',         true,
      'disponible', false,
      'conflictos', v_conflictos
    );
  ELSE
    RETURN jsonb_build_object(
      'ok',         true,
      'disponible', true
    );
  END IF;
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 12 — Función obtener_disponibilidad_rango
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION obtener_disponibilidad_rango(
  p_fecha_desde   DATE,
  p_fecha_hasta   DATE,
  p_id_cabana     BIGINT DEFAULT NULL
)
RETURNS TABLE (
  id_cabana              BIGINT,
  fecha                  DATE,
  estado                 TEXT,
  tipo_dia               TEXT,
  temporada              TEXT,
  hora_checkin_base      TIME,
  hora_checkout_base     TIME,
  id_reserva_activa      BIGINT,
  id_prereserva_activa   BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH dias AS (
    SELECT generate_series(p_fecha_desde, p_fecha_hasta - INTERVAL '1 day', '1 day')::DATE AS d
  ),
  cabanas_activas AS (
    SELECT c.id_cabana, c.nombre
    FROM cabanas c
    WHERE c.activa = TRUE
      AND (p_id_cabana IS NULL OR c.id_cabana = p_id_cabana)
  ),
  matriz AS (
    SELECT ca.id_cabana, d.d AS fecha
    FROM cabanas_activas ca
    CROSS JOIN dias d
  )
  SELECT
    m.id_cabana,
    m.fecha,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM bloqueos b
        WHERE b.activo = TRUE
          AND (b.id_cabana = m.id_cabana OR b.id_cabana IS NULL)
          AND m.fecha >= b.fecha_desde
          AND m.fecha < b.fecha_hasta
      ) THEN 'bloqueada'
      WHEN EXISTS (
        SELECT 1 FROM reservas r
        WHERE r.id_cabana = m.id_cabana
          AND r.estado IN ('confirmada', 'activa')
          AND m.fecha >= r.fecha_checkin
          AND m.fecha < r.fecha_checkout
      ) THEN 'ocupada'
      WHEN EXISTS (
        SELECT 1 FROM pre_reservas pr
        WHERE pr.id_cabana = m.id_cabana
          AND (
            (pr.estado = 'pendiente_pago' AND pr.expira_en > NOW())
            OR pr.estado = 'pago_en_revision'
          )
          AND m.fecha >= pr.fecha_in
          AND m.fecha < pr.fecha_out
      ) THEN 'ocupada'
      WHEN EXISTS (
        SELECT 1 FROM reservas r
        WHERE r.id_cabana = m.id_cabana
          AND r.estado IN ('confirmada', 'activa', 'completada')
          AND r.fecha_checkout = m.fecha
      ) THEN 'checkout_disponible'
      ELSE 'disponible'
    END AS estado,
    CASE
      WHEN EXISTS (SELECT 1 FROM feriados f WHERE f.fecha = m.fecha AND f.activo = TRUE) THEN 'feriado'
      WHEN EXTRACT(DOW FROM m.fecha) IN (5, 6) THEN 'finde'
      ELSE 'semana'
    END AS tipo_dia,
    (
      SELECT t.nombre FROM temporadas t
      WHERE t.activa = TRUE
        AND m.fecha BETWEEN t.fecha_desde AND t.fecha_hasta
      LIMIT 1
    ) AS temporada,
    -- Hora base (sin escalonamiento — el escalonamiento lo aplica n8n)
    CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '18:00' ELSE TIME '13:00' END AS hora_checkin_base,
    CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '16:00' ELSE TIME '10:00' END AS hora_checkout_base,  -- v1.7.1 (D47)
    (
      SELECT r.id_reserva FROM reservas r
      WHERE r.id_cabana = m.id_cabana
        AND r.estado IN ('confirmada', 'activa')
        AND m.fecha >= r.fecha_checkin
        AND m.fecha < r.fecha_checkout
      LIMIT 1
    ) AS id_reserva_activa,
    (
      SELECT pr.id_pre_reserva FROM pre_reservas pr
      WHERE pr.id_cabana = m.id_cabana
        AND (
          (pr.estado = 'pendiente_pago' AND pr.expira_en > NOW())
          OR pr.estado = 'pago_en_revision'
        )
        AND m.fecha >= pr.fecha_in
        AND m.fecha < pr.fecha_out
      LIMIT 1
    ) AS id_prereserva_activa
  FROM matriz m;
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 13 — Función crear_prereserva (puerta única)
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION crear_prereserva(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_huesped_payload      JSONB;
  v_id_consulta          BIGINT;
  v_id_cabana            BIGINT;
  v_fecha_in             DATE;
  v_fecha_out            DATE;
  v_personas             INTEGER;
  v_monto_total          NUMERIC(12,2);
  v_monto_sena           NUMERIC(12,2);
  v_canal_origen         TEXT;
  v_canal_pago_esperado  TEXT;
  v_source_event         TEXT;
  v_idempotency_key      TEXT;
  v_notas                TEXT;
  v_mascotas             BOOLEAN;
  v_detalle_mascotas     TEXT;
  v_ninos                TEXT;
  v_notas_reserva        TEXT;
  v_hora_checkin_sol     TIME;
  v_hora_checkout_sol    TIME;
  v_hora_checkin_final   TIME;
  v_hora_checkout_final  TIME;
  v_hora_checkin_min     TIME;
  v_hora_checkin_max     TIME;
  v_hora_checkout_min    TIME;
  v_hora_checkout_max    TIME;
  v_expiracion_minutos   INTEGER;
  v_expira_en            TIMESTAMPTZ;
  v_estado_inicial       estado_prereserva_enum;
  v_id_huesped           BIGINT;
  v_id_pre_reserva       BIGINT;
  v_config               JSONB;
  v_claves_faltantes     TEXT[];
  v_cabana               cabanas%ROWTYPE;
  v_disponibilidad       JSONB;
  v_existente            pre_reservas%ROWTYPE;
  v_upsert_result        JSONB;
BEGIN
  -- ─── 1. Extraer payload y validar ──────────────────────
  -- (v1.7.2) Extract defensivo unificado: todos los campos derivados de
  -- payload->>'...' pasan por NULLIF(TRIM(...),'') antes del cast. Excepción:
  -- v_huesped_payload usa payload->'huesped' (operador JSONB, no texto), no
  -- aplica patrón. La normalización interna del huésped vive en upsert_huesped().
  v_huesped_payload     := payload->'huesped';
  v_id_consulta         := NULLIF(TRIM(payload->>'id_consulta'), '')::BIGINT;
  v_id_cabana           := NULLIF(TRIM(payload->>'id_cabana'), '')::BIGINT;
  v_fecha_in            := NULLIF(TRIM(payload->>'fecha_in'), '')::DATE;
  v_fecha_out           := NULLIF(TRIM(payload->>'fecha_out'), '')::DATE;
  v_personas            := NULLIF(TRIM(payload->>'personas'), '')::INTEGER;
  v_monto_total         := NULLIF(TRIM(payload->>'monto_total'), '')::NUMERIC(12,2);
  v_monto_sena          := NULLIF(TRIM(payload->>'monto_sena'), '')::NUMERIC(12,2);
  v_canal_origen        := NULLIF(TRIM(payload->>'canal_origen'), '');
  v_canal_pago_esperado := NULLIF(TRIM(payload->>'canal_pago_esperado'), '');
  v_source_event        := NULLIF(TRIM(payload->>'source_event'), '');
  v_idempotency_key     := NULLIF(TRIM(payload->>'idempotency_key'), '');
  v_notas               := NULLIF(TRIM(payload->>'notas'), '');
  v_mascotas            := COALESCE(NULLIF(TRIM(payload->>'mascotas'), '')::BOOLEAN, FALSE);
  v_detalle_mascotas    := NULLIF(TRIM(payload->>'detalle_mascotas'), '');
  v_ninos               := NULLIF(TRIM(payload->>'ninos'), '');
  v_notas_reserva       := NULLIF(TRIM(payload->>'notas_reserva'), '');
  v_hora_checkin_sol    := NULLIF(TRIM(payload->>'hora_checkin_solicitada'), '')::TIME;
  v_hora_checkout_sol   := NULLIF(TRIM(payload->>'hora_checkout_solicitada'), '')::TIME;

  IF v_id_cabana IS NULL OR v_fecha_in IS NULL OR v_fecha_out IS NULL
     OR v_personas IS NULL OR v_canal_origen IS NULL OR v_source_event IS NULL
     OR v_canal_pago_esperado IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  IF v_monto_total IS NULL OR v_monto_sena IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'precio_requerido',
                              'motivo', 'monto_total y monto_sena son obligatorios');
  END IF;

  IF v_fecha_out <= v_fecha_in THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas');
  END IF;

  IF v_huesped_payload IS NULL OR NULLIF(TRIM(v_huesped_payload->>'nombre'), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_nombre_requerido',
                              'motivo', 'El payload del huésped debe traer un nombre no vacío.');
  END IF;

  IF NULLIF(v_huesped_payload->>'telefono', '') IS NULL
     AND NULLIF(v_huesped_payload->>'email', '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_contacto_requerido',
                              'motivo', 'El payload del huésped debe traer al menos telefono o email.');
  END IF;

  -- ─── 1.bis Setear contexto para triggers de log ──
  PERFORM set_config('app.modificado_por', 'crear_prereserva', true);
  PERFORM set_config('app.source_event',   v_source_event,    true);

  -- ─── 2. Leer configuración relevante ───────────────────
  SELECT jsonb_object_agg(clave, valor)
  INTO v_config
  FROM configuracion_general
  WHERE clave IN (
    'hora_checkin_default', 'hora_checkin_domingo',
    'hora_checkin_max_cliente', 'hora_checkout_min_cliente',
    'hora_checkout_default', 'hora_checkout_domingo',
    'prereserva_expiracion_minutos'
  );

  v_expiracion_minutos := COALESCE((v_config->>'prereserva_expiracion_minutos')::INTEGER, 60);

  v_claves_faltantes := ARRAY[]::TEXT[];
  IF v_config->>'hora_checkin_default'         IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_default'); END IF;
  IF v_config->>'hora_checkin_domingo'         IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_domingo'); END IF;
  IF v_config->>'hora_checkin_max_cliente'     IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_max_cliente'); END IF;
  IF v_config->>'hora_checkout_min_cliente'    IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_min_cliente'); END IF;
  IF v_config->>'hora_checkout_default'        IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_default'); END IF;
  IF v_config->>'hora_checkout_domingo'        IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_domingo'); END IF;
  IF v_config->>'prereserva_expiracion_minutos' IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'prereserva_expiracion_minutos'); END IF;

  -- ─── 3. Pre-check idempotencia ──
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existente
    FROM pre_reservas
    WHERE idempotency_key = v_idempotency_key
      AND estado IN ('pendiente_pago', 'pago_en_revision')
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'ok',               true,
        'idempotent_match', true,
        'id_pre_reserva',   v_existente.id_pre_reserva,
        'id_huesped',       v_existente.id_huesped,
        'estado',           v_existente.estado::TEXT,
        'expira_en',        v_existente.expira_en,
        'recovery_path',    'pre_lock'
      );
    END IF;
  END IF;

  -- ─── 4. Resolver huésped ──────
  v_upsert_result := upsert_huesped(v_huesped_payload);
  IF NOT (v_upsert_result->>'ok')::BOOLEAN THEN
    RETURN v_upsert_result;
  END IF;
  v_id_huesped := (v_upsert_result->>'id_huesped')::BIGINT;

  -- ─── 5. Locks ──
  PERFORM pg_advisory_xact_lock(10, 0);
  PERFORM pg_advisory_xact_lock(1, v_id_cabana::INTEGER);

  -- ─── 5.bis Double-check idempotencia ──
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existente
    FROM pre_reservas
    WHERE idempotency_key = v_idempotency_key
      AND estado IN ('pendiente_pago', 'pago_en_revision')
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'ok',               true,
        'idempotent_match', true,
        'id_pre_reserva',   v_existente.id_pre_reserva,
        'id_huesped',       v_existente.id_huesped,
        'estado',           v_existente.estado::TEXT,
        'expira_en',        v_existente.expira_en,
        'recovery_path',    'post_lock'
      );
    END IF;
  END IF;

  -- ─── 6. Validar cabaña ──
  SELECT * INTO v_cabana FROM cabanas WHERE id_cabana = v_id_cabana;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_existe');
  END IF;

  IF NOT v_cabana.activa THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_inactiva');
  END IF;

  IF v_personas > v_cabana.capacidad_max THEN
    RETURN jsonb_build_object('ok', false, 'error', 'excede_capacidad',
                              'capacidad_max', v_cabana.capacidad_max);
  END IF;

  -- ─── 7. Validar disponibilidad ──
  v_disponibilidad := validar_disponibilidad(v_id_cabana, v_fecha_in, v_fecha_out, NULL);

  IF NOT (v_disponibilidad->>'ok')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', v_disponibilidad->>'error');
  END IF;

  IF NOT (v_disponibilidad->>'disponible')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_disponible',
                              'conflictos', v_disponibilidad->'conflictos');
  END IF;

  -- ─── 8. Calcular horarios finales (v1.7) ──
  v_hora_checkin_min := CASE
    WHEN EXTRACT(DOW FROM v_fecha_in) = 0
      THEN COALESCE((v_config->>'hora_checkin_domingo')::TIME, TIME '18:00')
    ELSE
      COALESCE((v_config->>'hora_checkin_default')::TIME, TIME '13:00')
  END;
  v_hora_checkin_max := COALESCE((v_config->>'hora_checkin_max_cliente')::TIME, TIME '22:00');

  v_hora_checkout_min := COALESCE((v_config->>'hora_checkout_min_cliente')::TIME, TIME '07:00');

  v_hora_checkout_max := CASE
    WHEN EXTRACT(DOW FROM v_fecha_out) = 0
      THEN COALESCE((v_config->>'hora_checkout_domingo')::TIME, TIME '16:00')
    ELSE
      COALESCE((v_config->>'hora_checkout_default')::TIME, TIME '10:00')
  END;

  IF v_hora_checkin_sol IS NULL THEN
    v_hora_checkin_final := v_hora_checkin_min;
  ELSE
    IF v_hora_checkin_sol < v_hora_checkin_min OR v_hora_checkin_sol > v_hora_checkin_max THEN
      RETURN jsonb_build_object(
        'ok', false, 'error', 'hora_fuera_de_rango',
        'campo', 'hora_checkin',
        'minimo', v_hora_checkin_min, 'maximo', v_hora_checkin_max
      );
    END IF;
    v_hora_checkin_final := v_hora_checkin_sol;
  END IF;

  IF v_hora_checkout_sol IS NULL THEN
    v_hora_checkout_final := v_hora_checkout_max;
  ELSE
    IF v_hora_checkout_sol < v_hora_checkout_min OR v_hora_checkout_sol > v_hora_checkout_max THEN
      RETURN jsonb_build_object(
        'ok', false, 'error', 'hora_fuera_de_rango',
        'campo', 'hora_checkout',
        'minimo', v_hora_checkout_min, 'maximo', v_hora_checkout_max
      );
    END IF;
    v_hora_checkout_final := v_hora_checkout_sol;
  END IF;

  v_expira_en := NOW() + (v_expiracion_minutos || ' minutes')::INTERVAL;
  v_estado_inicial := 'pendiente_pago';

  -- ─── 9. INSERT con manejo defensivo ──
  BEGIN
    INSERT INTO pre_reservas (
      id_consulta, id_cabana, id_huesped,
      fecha_in, fecha_out, hora_checkin, hora_checkout,
      personas, monto_total, monto_sena, estado, expira_en,
      canal_pago_esperado, canal_origen, intentos_pago,
      notas, source_event,
      mascotas, detalle_mascotas, ninos, notas_reserva,
      idempotency_key
    ) VALUES (
      v_id_consulta, v_id_cabana, v_id_huesped,
      v_fecha_in, v_fecha_out, v_hora_checkin_final, v_hora_checkout_final,
      v_personas, v_monto_total, v_monto_sena, v_estado_inicial, v_expira_en,
      v_canal_pago_esperado, v_canal_origen, 0,
      v_notas, v_source_event,
      v_mascotas, v_detalle_mascotas, v_ninos, v_notas_reserva,
      v_idempotency_key
    )
    RETURNING id_pre_reserva INTO v_id_pre_reserva;

  EXCEPTION
    WHEN unique_violation THEN
      IF v_idempotency_key IS NOT NULL THEN
        SELECT * INTO v_existente
        FROM pre_reservas
        WHERE idempotency_key = v_idempotency_key
          AND estado IN ('pendiente_pago', 'pago_en_revision')
        LIMIT 1;

        IF FOUND THEN
          RETURN jsonb_build_object(
            'ok',               true,
            'idempotent_match', true,
            'id_pre_reserva',   v_existente.id_pre_reserva,
            'id_huesped',       v_existente.id_huesped,
            'estado',           v_existente.estado::TEXT,
            'expira_en',        v_existente.expira_en,
            'recovery_path',    'unique_violation'
          );
        END IF;
      END IF;

      RETURN jsonb_build_object('ok', false, 'error', 'unique_violation_inesperado');
  END;

  -- ─── 10. Log de creación ──
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'pre_reservas',
    v_id_pre_reserva::TEXT,
    'crear_prereserva',
    v_source_event,
    'info',
    jsonb_build_object(
      'evento',       'prereserva_creada',
      'id_cabana',    v_id_cabana,
      'id_huesped',   v_id_huesped,
      'fecha_in',     v_fecha_in,
      'fecha_out',    v_fecha_out,
      'monto_total',  v_monto_total,
      'monto_sena',   v_monto_sena,
      'canal_origen', v_canal_origen
    )
  );

  -- ─── 11. Warning de config faltante ──
  IF cardinality(v_claves_faltantes) > 0 THEN
    INSERT INTO log_cambios (
      tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
    ) VALUES (
      'configuracion_general',
      'sistema',
      'crear_prereserva',
      v_source_event,
      'warning',
      jsonb_build_object(
        'evento',           'claves_config_faltantes',
        'claves_faltantes', v_claves_faltantes,
        'motivo',           'crear_prereserva usó valores default para estas claves'
      )
    );
  END IF;

  -- ─── 12. Retorno exitoso ──
  RETURN jsonb_build_object(
    'ok',               true,
    'idempotent_match', false,
    'id_pre_reserva',   v_id_pre_reserva,
    'id_huesped',       v_id_huesped,
    'estado',           v_estado_inicial::TEXT,
    'expira_en',        v_expira_en,
    'hora_checkin',     v_hora_checkin_final,
    'hora_checkout',    v_hora_checkout_final,
    'recovery_path',    NULL
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 14 — Función confirmar_reserva
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION confirmar_reserva(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_pre_reserva              BIGINT;
  v_permitir_pago_en_revision   BOOLEAN;
  v_validado_por                TEXT;
  v_encargado_semana            TEXT;
  v_created_by                  TEXT;
  v_source_event                TEXT;
  v_pre                         pre_reservas%ROWTYPE;
  v_pago                        pagos%ROWTYPE;
  v_id_pago_a_confirmar         BIGINT;
  v_disponibilidad              JSONB;
  v_id_reserva                  BIGINT;
  v_huesped                     huespedes%ROWTYPE;
BEGIN
  -- ─── 1. Extraer payload (v1.7.2 — extract defensivo unificado) ──
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en BIGINT y BOOLEAN
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  v_id_pre_reserva            := NULLIF(TRIM(payload->>'id_pre_reserva'), '')::BIGINT;
  v_permitir_pago_en_revision := COALESCE(NULLIF(TRIM(payload->>'permitir_pago_en_revision'), '')::BOOLEAN, FALSE);
  v_validado_por              := NULLIF(TRIM(payload->>'validado_por'), '');
  v_encargado_semana          := NULLIF(TRIM(payload->>'encargado_semana'), '');
  v_created_by                := NULLIF(TRIM(payload->>'created_by'), '');
  v_source_event              := NULLIF(TRIM(payload->>'source_event'), '');

  IF v_id_pre_reserva IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  -- ─── 1.bis Setear contexto para triggers de log (D38, v1.2) ──
  PERFORM set_config('app.modificado_por', 'confirmar_reserva', true);
  PERFORM set_config('app.source_event',   v_source_event,      true);

  -- ─── 1.ter Lock GLOBAL de disponibilidad (v1.5) ──
  -- INVARIANTE DE LOCKS: tomar SIEMPRE primero el lock global antes de cualquier otro.
  PERFORM pg_advisory_xact_lock(10, 0);

  -- ─── 2. Bloquear y leer pre-reserva (row lock, después del global) ──
  SELECT * INTO v_pre FROM pre_reservas
  WHERE id_pre_reserva = v_id_pre_reserva
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'prereserva_no_existe');
  END IF;

  IF v_pre.estado NOT IN ('pendiente_pago', 'pago_en_revision') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estado_invalido',
                              'estado_actual', v_pre.estado::TEXT);
  END IF;

  -- ─── 3. Lock por cabaña (con cast a INTEGER — corrección v1.6) ──
  -- NOTA TÉCNICA (v1.6): cast explícito a INTEGER. PostgreSQL no provee
  -- pg_advisory_xact_lock(integer, bigint). Ver Sección 15 del documento.
  PERFORM pg_advisory_xact_lock(1, v_pre.id_cabana::INTEGER);

  -- ─── 4. Verificar pago asociado ────────────────────────
  -- Camino estricto: requiere al menos un pago 'confirmado'
  SELECT * INTO v_pago FROM pagos
  WHERE id_prereserva = v_id_pre_reserva
    AND estado = 'confirmado'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    -- Sin pago confirmado, ¿podemos usar camino combinado?
    IF v_permitir_pago_en_revision AND v_validado_por IS NOT NULL THEN
      SELECT * INTO v_pago FROM pagos
      WHERE id_prereserva = v_id_pre_reserva
        AND estado = 'en_revision'
      ORDER BY created_at DESC
      LIMIT 1
      FOR UPDATE;

      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'sin_pago_asociado');
      END IF;

      v_id_pago_a_confirmar := v_pago.id_pago;
    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'sin_pago_confirmado',
                                'motivo', 'No hay pago confirmado y no se permitió usar pago en revisión');
    END IF;
  END IF;

  -- ─── 5. Revalidar disponibilidad excluyendo esta pre-reserva ──
  v_disponibilidad := validar_disponibilidad(
    v_pre.id_cabana, v_pre.fecha_in, v_pre.fecha_out, v_id_pre_reserva
  );

  IF NOT (v_disponibilidad->>'ok')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', v_disponibilidad->>'error');
  END IF;

  IF NOT (v_disponibilidad->>'disponible')::BOOLEAN THEN
    -- Conflicto detectado al confirmar — alguien metió bloqueo o reserva
    UPDATE pre_reservas SET estado = 'conflicto_pendiente', updated_at = NOW()
    WHERE id_pre_reserva = v_id_pre_reserva;

    RETURN jsonb_build_object('ok', false, 'error', 'conflicto_al_confirmar',
                              'conflictos', v_disponibilidad->'conflictos');
  END IF;

  -- ─── 6. INSERT en reservas (con captura defensiva de EXCLUDE) ──
  BEGIN
    INSERT INTO reservas (
      id_pre_reserva, id_cabana, id_huesped,
      fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
      personas, estado, canal_origen,
      monto_total, monto_sena, monto_saldo,
      encargado_semana, created_by, source_event,
      mascotas, detalle_mascotas, ninos, notas_reserva
    ) VALUES (
      v_id_pre_reserva, v_pre.id_cabana, v_pre.id_huesped,
      v_pre.fecha_in, v_pre.fecha_out, v_pre.hora_checkin, v_pre.hora_checkout,
      v_pre.personas, 'confirmada', v_pre.canal_origen,
      v_pre.monto_total, v_pre.monto_sena, (v_pre.monto_total - v_pre.monto_sena),
      v_encargado_semana, v_created_by, v_source_event,
      v_pre.mascotas, v_pre.detalle_mascotas, v_pre.ninos, v_pre.notas_reserva
    )
    RETURNING id_reserva INTO v_id_reserva;

  EXCEPTION
    WHEN exclusion_violation THEN
      -- Defensivo: no debería pasar por la revalidación + lock, pero por las dudas
      RETURN jsonb_build_object('ok', false, 'error', 'no_disponible',
                                'motivo', 'EXCLUDE constraint detectó conflicto');
  END;

  -- ─── 7. Marcar pre-reserva como convertida ────────────
  UPDATE pre_reservas
  SET estado = 'convertida', updated_at = NOW()
  WHERE id_pre_reserva = v_id_pre_reserva;

  -- ─── 8. Asociar pago con la nueva reserva ────────────
  UPDATE pagos
  SET id_reserva = v_id_reserva,
      updated_at = NOW()
  WHERE id_prereserva = v_id_pre_reserva;

  -- ─── 9. Si camino combinado: confirmar el pago en_revision ───
  IF v_id_pago_a_confirmar IS NOT NULL THEN
    UPDATE pagos
    SET estado       = 'confirmado',
        validado_por = v_validado_por,
        validado_en  = NOW(),
        updated_at   = NOW()
    WHERE id_pago = v_id_pago_a_confirmar;
  END IF;

  -- ─── 10. Actualizar huésped: total_reservas y primera_reserva_fecha ──
  UPDATE huespedes
  SET total_reservas        = total_reservas + 1,
      primera_reserva_fecha = COALESCE(primera_reserva_fecha, v_pre.fecha_in),
      updated_at            = NOW()
  WHERE id_huesped = v_pre.id_huesped;

  -- ─── 11. Log de creación ────────────────────────────
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'reservas',
    v_id_reserva::TEXT,
    'confirmar_reserva',
    v_source_event,
    'info',
    jsonb_build_object(
      'evento',         'reserva_confirmada',
      'id_reserva',     v_id_reserva,
      'id_pre_reserva', v_id_pre_reserva,
      'id_huesped',     v_pre.id_huesped,
      'id_cabana',      v_pre.id_cabana,
      'camino',         CASE WHEN v_id_pago_a_confirmar IS NOT NULL THEN 'combinado' ELSE 'estricto' END
    )
  );

  RETURN jsonb_build_object(
    'ok',             true,
    'id_reserva',     v_id_reserva,
    'id_pre_reserva', v_id_pre_reserva,
    'id_huesped',     v_pre.id_huesped
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 15 — Función cancelar_prereserva
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION cancelar_prereserva(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_pre_reserva     BIGINT;
  v_motivo             TEXT;
  v_descripcion        TEXT;
  v_source_event       TEXT;
  v_pre                pre_reservas%ROWTYPE;
  v_estado_nuevo       estado_prereserva_enum;
  v_estado_anterior    estado_prereserva_enum;
  v_pagos_count        INTEGER;
  v_pagos_ids          BIGINT[];
BEGIN
  -- 1. Extraer payload (v1.7.2 — extract defensivo unificado)
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en BIGINT
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  v_id_pre_reserva := NULLIF(TRIM(payload->>'id_pre_reserva'), '')::BIGINT;
  v_motivo         := NULLIF(TRIM(payload->>'motivo'), '');
  v_descripcion    := NULLIF(TRIM(payload->>'descripcion'), '');
  v_source_event   := NULLIF(TRIM(payload->>'source_event'), '');

  IF v_id_pre_reserva IS NULL OR v_motivo IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  -- 1.bis Setear contexto para triggers de log (D38, v1.2)
  PERFORM set_config('app.modificado_por', 'cancelar_prereserva', true);
  PERFORM set_config('app.source_event',   v_source_event,        true);

  -- 1.ter Lock global de disponibilidad (D46, v1.4, Q1)
  -- Esta función NO toma lock por cabaña porque solo libera disponibilidad.
  PERFORM pg_advisory_xact_lock(10, 0);

  -- 2. Mapear motivo a estado
  CASE v_motivo
    WHEN 'cliente' THEN v_estado_nuevo := 'cancelada_por_cliente';
    WHEN 'bloqueo' THEN v_estado_nuevo := 'cancelada_por_bloqueo';
    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'motivo_invalido',
                                'motivos_validos', jsonb_build_array('cliente', 'bloqueo'));
  END CASE;

  -- 3. Bloquear pre-reserva
  SELECT * INTO v_pre FROM pre_reservas
  WHERE id_pre_reserva = v_id_pre_reserva
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'prereserva_no_existe');
  END IF;

  IF v_pre.estado NOT IN ('pendiente_pago', 'pago_en_revision') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estado_no_cancelable',
                              'estado_actual', v_pre.estado::TEXT);
  END IF;

  v_estado_anterior := v_pre.estado;

  -- 4. Cancelar
  UPDATE pre_reservas
  SET estado = v_estado_nuevo, updated_at = NOW()
  WHERE id_pre_reserva = v_id_pre_reserva;

  -- 5. Contar pagos asociados (NO tocarlos)
  SELECT COUNT(*), COALESCE(array_agg(id_pago), ARRAY[]::BIGINT[])
  INTO v_pagos_count, v_pagos_ids
  FROM pagos
  WHERE id_prereserva = v_id_pre_reserva;

  -- 6. Log
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'pre_reservas', v_id_pre_reserva::TEXT, 'cancelar_prereserva',
    v_source_event, 'info',
    jsonb_build_object(
      'evento',           'prereserva_cancelada',
      'id_pre_reserva',   v_id_pre_reserva,
      'estado_anterior',  v_estado_anterior::TEXT,
      'estado_nuevo',     v_estado_nuevo::TEXT,
      'motivo',           v_motivo,
      'descripcion',      v_descripcion,
      'pagos_asociados',  v_pagos_count
    )
  );

  RETURN jsonb_build_object(
    'ok',                    true,
    'id_pre_reserva',        v_id_pre_reserva,
    'estado_anterior',       v_estado_anterior::TEXT,
    'estado_nuevo',          v_estado_nuevo::TEXT,
    'pagos_asociados_count', v_pagos_count,
    'pagos_asociados_ids',   to_jsonb(v_pagos_ids)
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 16 — Función crear_bloqueo
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION crear_bloqueo(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_cabana            BIGINT;
  v_fecha_desde          DATE;
  v_fecha_hasta          DATE;
  v_motivo               TEXT;
  v_descripcion          TEXT;
  v_creado_por           TEXT;
  v_source_event         TEXT;
  v_id_bloqueo           BIGINT;
  v_reservas_ids         BIGINT[];
  v_prereservas_ids      BIGINT[];
  v_bloqueos_ids         BIGINT[];
BEGIN
  -- 1. Extraer payload (v1.7.2 — extract defensivo unificado)
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en BIGINT y DATE
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  --
  -- Caso especial v_id_cabana: null significa "bloqueo total" (válido).
  -- Tanto null como "" como "   " se interpretan como bloqueo total.
  v_id_cabana    := NULLIF(TRIM(payload->>'id_cabana'), '')::BIGINT;
  v_fecha_desde  := NULLIF(TRIM(payload->>'fecha_desde'), '')::DATE;
  v_fecha_hasta  := NULLIF(TRIM(payload->>'fecha_hasta'), '')::DATE;
  v_motivo       := NULLIF(TRIM(payload->>'motivo'), '');
  v_descripcion  := NULLIF(TRIM(payload->>'descripcion'), '');
  v_creado_por   := NULLIF(TRIM(payload->>'creado_por'), '');
  v_source_event := NULLIF(TRIM(payload->>'source_event'), '');

  IF v_fecha_desde IS NULL OR v_fecha_hasta IS NULL
     OR v_motivo IS NULL OR v_creado_por IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  IF v_fecha_hasta <= v_fecha_desde THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas');
  END IF;

  IF v_motivo NOT IN ('mantenimiento', 'uso_propio', 'tormenta', 'overbooking', 'otro') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'motivo_invalido');
  END IF;

  -- 2. Locks (INVARIANTE DE LOCKS v1.5: SIEMPRE primero el global)
  PERFORM pg_advisory_xact_lock(10, 0);

  IF v_id_cabana IS NOT NULL THEN
    -- Bloqueo específico: tomar también lock por cabaña con cast a INTEGER (v1.6)
    PERFORM pg_advisory_xact_lock(1, v_id_cabana::INTEGER);

    -- Verificar cabaña existe
    IF NOT EXISTS (SELECT 1 FROM cabanas WHERE id_cabana = v_id_cabana) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_existe');
    END IF;

    -- 3.A.1 Verificar conflicto con reservas confirmadas/activas en esta cabaña
    SELECT COALESCE(array_agg(id_reserva), ARRAY[]::BIGINT[])
    INTO v_reservas_ids
    FROM reservas
    WHERE id_cabana = v_id_cabana
      AND estado IN ('confirmada', 'activa')
      AND daterange(fecha_checkin, fecha_checkout, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_reservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'conflicto_con_reserva',
        'reservas_en_conflicto', to_jsonb(v_reservas_ids)
      );
    END IF;

    -- 3.A.2 Verificar conflicto con pre-reservas vigentes en esta cabaña
    SELECT COALESCE(array_agg(id_pre_reserva), ARRAY[]::BIGINT[])
    INTO v_prereservas_ids
    FROM pre_reservas
    WHERE id_cabana = v_id_cabana
      AND (
        (estado = 'pendiente_pago' AND expira_en > NOW())
        OR estado = 'pago_en_revision'
      )
      AND daterange(fecha_in, fecha_out, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_prereservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                       false,
        'error',                    'conflicto_con_prereserva',
        'prereservas_en_conflicto', to_jsonb(v_prereservas_ids),
        'motivo',                   'Hay pre-reservas vigentes en el rango. Cancelarlas antes de bloquear.'
      );
    END IF;

    -- 3.A.3 Verificar bloqueos solapados (específico vs específico o específico vs total)
    SELECT COALESCE(array_agg(id_bloqueo), ARRAY[]::BIGINT[])
    INTO v_bloqueos_ids
    FROM bloqueos
    WHERE activo = TRUE
      AND (id_cabana = v_id_cabana OR id_cabana IS NULL)
      AND daterange(fecha_desde, fecha_hasta, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_bloqueos_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'bloqueo_solapado',
        'bloqueos_en_conflicto', to_jsonb(v_bloqueos_ids),
        'motivo',                'Ya hay un bloqueo activo (específico o total) en el rango'
      );
    END IF;

  ELSE
    -- Bloqueo total (id_cabana IS NULL)
    -- 3.B.1 Verificar conflicto con reservas en cualquier cabaña
    SELECT COALESCE(array_agg(id_reserva), ARRAY[]::BIGINT[])
    INTO v_reservas_ids
    FROM reservas
    WHERE estado IN ('confirmada', 'activa')
      AND daterange(fecha_checkin, fecha_checkout, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_reservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'conflicto_con_reserva',
        'motivo',                'Hay reservas confirmadas en el rango. Resolver antes de bloquear el complejo.',
        'reservas_en_conflicto', to_jsonb(v_reservas_ids)
      );
    END IF;

    -- 3.B.2 Verificar conflicto con pre-reservas vigentes en cualquier cabaña
    SELECT COALESCE(array_agg(id_pre_reserva), ARRAY[]::BIGINT[])
    INTO v_prereservas_ids
    FROM pre_reservas
    WHERE (
        (estado = 'pendiente_pago' AND expira_en > NOW())
        OR estado = 'pago_en_revision'
      )
      AND daterange(fecha_in, fecha_out, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_prereservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                       false,
        'error',                    'conflicto_con_prereserva',
        'prereservas_en_conflicto', to_jsonb(v_prereservas_ids),
        'motivo',                   'Hay pre-reservas vigentes en el rango. Cancelarlas antes de bloquear el complejo.'
      );
    END IF;

    -- 3.B.3 Verificar bloqueos solapados (total vs total o total vs específico existente)
    SELECT COALESCE(array_agg(id_bloqueo), ARRAY[]::BIGINT[])
    INTO v_bloqueos_ids
    FROM bloqueos
    WHERE activo = TRUE
      AND daterange(fecha_desde, fecha_hasta, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_bloqueos_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'bloqueo_solapado',
        'bloqueos_en_conflicto', to_jsonb(v_bloqueos_ids),
        'motivo',                'Ya hay bloqueos activos en el rango (totales o específicos)'
      );
    END IF;
  END IF;

  -- 4. INSERT con captura defensiva de exclusion_violation
  BEGIN
    INSERT INTO bloqueos (
      id_cabana, fecha_desde, fecha_hasta, motivo, descripcion,
      creado_por, activo, source_event
    ) VALUES (
      v_id_cabana, v_fecha_desde, v_fecha_hasta, v_motivo, v_descripcion,
      v_creado_por, TRUE, v_source_event
    )
    RETURNING id_bloqueo INTO v_id_bloqueo;

  EXCEPTION
    WHEN exclusion_violation THEN
      RETURN jsonb_build_object('ok', false, 'error', 'bloqueo_solapado',
                                'motivo', 'EXCLUDE detectó conflicto residual');
  END;

  -- 5. Log
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'bloqueos', v_id_bloqueo::TEXT, v_creado_por, v_source_event, 'info',
    jsonb_build_object(
      'evento',       'bloqueo_creado',
      'id_bloqueo',   v_id_bloqueo,
      'id_cabana',    v_id_cabana,
      'fecha_desde',  v_fecha_desde,
      'fecha_hasta',  v_fecha_hasta,
      'motivo',       v_motivo,
      'tipo_bloqueo', CASE WHEN v_id_cabana IS NULL THEN 'total' ELSE 'cabana_especifica' END
    )
  );

  RETURN jsonb_build_object(
    'ok',           true,
    'id_bloqueo',   v_id_bloqueo,
    'id_cabana',    v_id_cabana,
    'tipo_bloqueo', CASE WHEN v_id_cabana IS NULL THEN 'total' ELSE 'cabana_especifica' END
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 17 — Función registrar_pago
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION registrar_pago(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_pre_reserva     BIGINT;
  v_id_reserva         BIGINT;
  v_tipo               TEXT;
  v_medio_pago         TEXT;
  v_monto_esperado     NUMERIC(12,2);
  v_monto_recibido     NUMERIC(12,2);
  v_moneda             TEXT;
  v_es_automatico      BOOLEAN;
  v_estado_inicial     TEXT;
  v_comprobante_url    TEXT;
  v_referencia_externa TEXT;
  v_tx_hash            TEXT;
  v_validado_por       TEXT;
  v_notas              TEXT;
  v_proveedor          TEXT;
  v_cuenta_destino     TEXT;
  v_source_event       TEXT;
  v_estado_final       estado_pago_enum;
  v_id_pago            BIGINT;
  v_validado_en        TIMESTAMPTZ;
  v_prereserva_estado  estado_prereserva_enum;
  v_prereserva_no_activa BOOLEAN := FALSE;
  v_warning            TEXT;
BEGIN
  -- 1. Extraer payload (v1.7.2 — extract defensivo unificado)
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en numéricos y booleanos
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  v_id_pre_reserva     := NULLIF(TRIM(payload->>'id_pre_reserva'), '')::BIGINT;
  v_id_reserva         := NULLIF(TRIM(payload->>'id_reserva'), '')::BIGINT;
  v_tipo               := NULLIF(TRIM(payload->>'tipo'), '');
  v_medio_pago         := NULLIF(TRIM(payload->>'medio_pago'), '');
  v_monto_esperado     := NULLIF(TRIM(payload->>'monto_esperado'), '')::NUMERIC(12,2);
  v_monto_recibido     := NULLIF(TRIM(payload->>'monto_recibido'), '')::NUMERIC(12,2);
  v_moneda             := COALESCE(NULLIF(TRIM(payload->>'moneda'), ''), 'ARS');
  v_es_automatico      := COALESCE(NULLIF(TRIM(payload->>'es_automatico'), '')::BOOLEAN, FALSE);
  v_estado_inicial     := NULLIF(TRIM(payload->>'estado_inicial'), '');
  v_comprobante_url    := NULLIF(TRIM(payload->>'comprobante_url'), '');
  v_referencia_externa := NULLIF(TRIM(payload->>'referencia_externa'), '');
  v_tx_hash            := NULLIF(TRIM(payload->>'tx_hash'), '');
  v_validado_por       := NULLIF(TRIM(payload->>'validado_por'), '');
  v_notas              := NULLIF(TRIM(payload->>'notas'), '');
  v_proveedor          := NULLIF(TRIM(payload->>'proveedor'), '');
  v_cuenta_destino     := NULLIF(TRIM(payload->>'cuenta_destino'), '');
  v_source_event       := NULLIF(TRIM(payload->>'source_event'), '');

  -- 1.bis Setear contexto para triggers de log (D38, v1.2)
  IF v_source_event IS NOT NULL THEN
    PERFORM set_config('app.modificado_por', 'registrar_pago', true);
    PERFORM set_config('app.source_event',   v_source_event,   true);
  END IF;

  -- 2. Validaciones
  IF v_id_pre_reserva IS NULL AND v_id_reserva IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'referencia_requerida',
                              'motivo', 'Debe venir id_pre_reserva o id_reserva');
  END IF;

  IF v_tipo IS NULL OR v_medio_pago IS NULL OR v_monto_esperado IS NULL
     OR v_monto_recibido IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  -- 3. Verificar pre-reserva o reserva existe + capturar estado de la pre-reserva (v1.3)
  IF v_id_pre_reserva IS NOT NULL THEN
    SELECT estado INTO v_prereserva_estado
    FROM pre_reservas
    WHERE id_pre_reserva = v_id_pre_reserva;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'prereserva_no_existe');
    END IF;

    -- v1.3 (P2): detectar pre-reserva en estado terminal
    IF v_prereserva_estado IN (
      'vencida',
      'cancelada_por_cliente',
      'cancelada_por_bloqueo',
      'conflicto_pendiente'
    ) THEN
      v_prereserva_no_activa := TRUE;
      v_warning              := 'prereserva_no_activa';
    END IF;
  END IF;

  IF v_id_reserva IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM reservas WHERE id_reserva = v_id_reserva) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'reserva_no_existe');
    END IF;
  END IF;

  -- 4. Determinar estado del pago
  IF v_prereserva_no_activa THEN
    v_estado_final := 'en_revision';
    v_validado_en  := NULL;
  ELSIF v_estado_inicial = 'confirmado' AND v_monto_recibido = v_monto_esperado THEN
    v_estado_final := 'confirmado';
    v_validado_en  := NOW();
    IF v_validado_por IS NULL THEN
      v_validado_por := 'sistema_auto';
    END IF;
  ELSE
    v_estado_final := 'en_revision';
    v_validado_en  := NULL;
  END IF;

  -- 5. INSERT
  INSERT INTO pagos (
    id_prereserva, id_reserva, tipo, medio_pago, proveedor, cuenta_destino,
    monto_esperado, monto_recibido, moneda, estado, es_automatico,
    comprobante_url, referencia_externa, tx_hash,
    validado_por, validado_en, notas, source_event
  ) VALUES (
    v_id_pre_reserva, v_id_reserva, v_tipo, v_medio_pago, v_proveedor, v_cuenta_destino,
    v_monto_esperado, v_monto_recibido, v_moneda, v_estado_final, v_es_automatico,
    v_comprobante_url, v_referencia_externa, v_tx_hash,
    v_validado_por, v_validado_en, v_notas, v_source_event
  )
  RETURNING id_pago INTO v_id_pago;

  -- 6. Promover pre-reserva de pendiente_pago → pago_en_revision SOLO si está activa
  IF v_id_pre_reserva IS NOT NULL AND NOT v_prereserva_no_activa THEN
    UPDATE pre_reservas
    SET estado = 'pago_en_revision', updated_at = NOW()
    WHERE id_pre_reserva = v_id_pre_reserva
      AND estado = 'pendiente_pago';
  END IF;

  -- 7. Log
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'pagos', v_id_pago::TEXT, COALESCE(v_validado_por, 'registrar_pago'),
    v_source_event,
    CASE WHEN v_prereserva_no_activa THEN 'warning'::nivel_log_enum ELSE 'info'::nivel_log_enum END,
    jsonb_build_object(
      'evento',             'pago_registrado',
      'id_pago',            v_id_pago,
      'id_pre_reserva',     v_id_pre_reserva,
      'id_reserva',         v_id_reserva,
      'tipo',               v_tipo,
      'medio_pago',         v_medio_pago,
      'monto_esperado',     v_monto_esperado,
      'monto_recibido',     v_monto_recibido,
      'estado',             v_estado_final::TEXT,
      'es_automatico',      v_es_automatico,
      'warning',            v_warning,
      'prereserva_estado',  CASE WHEN v_prereserva_no_activa
                                 THEN v_prereserva_estado::TEXT
                                 ELSE NULL END
    )
  );

  -- 8. Retorno
  IF v_prereserva_no_activa THEN
    RETURN jsonb_build_object(
      'ok',                 true,
      'id_pago',            v_id_pago,
      'estado',             v_estado_final::TEXT,
      'warning',            'prereserva_no_activa',
      'prereserva_estado',  v_prereserva_estado::TEXT
    );
  ELSE
    RETURN jsonb_build_object(
      'ok',      true,
      'id_pago', v_id_pago,
      'estado',  v_estado_final::TEXT
    );
  END IF;
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 18 — Función expirar_prereservas_vencidas
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION expirar_prereservas_vencidas()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count       INTEGER;
  v_pre         RECORD;
BEGIN
  v_count := 0;

  -- Setear contexto una sola vez al inicio (D38, v1.2)
  -- El trigger trg_log_pre_reservas_estado leerá estas variables al hacer el UPDATE.
  PERFORM set_config('app.modificado_por', 'expirar_prereservas_vencidas', true);
  PERFORM set_config('app.source_event',   'cron_expirar_prereservas',    true);

  FOR v_pre IN
    SELECT id_pre_reserva, id_huesped, id_cabana, fecha_in, fecha_out
    FROM pre_reservas
    WHERE estado = 'pendiente_pago'
      AND expira_en <= NOW()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE pre_reservas
    SET estado = 'vencida', updated_at = NOW()
    WHERE id_pre_reserva = v_pre.id_pre_reserva;

    INSERT INTO log_cambios (
      tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
    ) VALUES (
      'pre_reservas', v_pre.id_pre_reserva::TEXT, 'pg_cron',
      'cron_expirar_prereservas', 'info',
      jsonb_build_object(
        'evento',         'prereserva_vencida',
        'id_pre_reserva', v_pre.id_pre_reserva,
        'id_huesped',     v_pre.id_huesped,
        'id_cabana',      v_pre.id_cabana
      )
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 19 — Triggers automáticos
-- ══════════════════════════════════════════════════════════════════════════
-- ─── Función genérica para updated_at ─────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

-- ─── Función genérica de log de cambio de estado ──────
CREATE OR REPLACE FUNCTION log_cambio_estado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    INSERT INTO log_cambios (
      tabla_afectada, id_registro, campo_modificado,
      valor_anterior, valor_nuevo, modificado_por, source_event, nivel
    ) VALUES (
      TG_TABLE_NAME,
      (SELECT row_to_json(NEW)->>(TG_ARGV[0]))::TEXT,
      'estado',
      OLD.estado::TEXT,
      NEW.estado::TEXT,
      COALESCE(current_setting('app.modificado_por', TRUE), 'trigger_auto'),
      COALESCE(current_setting('app.source_event', TRUE), 'estado_change'),
      'info'
    );
  END IF;
  RETURN NEW;
END;
$$;

-- ─── Triggers updated_at ──────────────────────────────
CREATE TRIGGER trg_pre_reservas_updated_at BEFORE UPDATE ON pre_reservas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_reservas_updated_at BEFORE UPDATE ON reservas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pagos_updated_at BEFORE UPDATE ON pagos
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_huespedes_updated_at BEFORE UPDATE ON huespedes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_consultas_updated_at BEFORE UPDATE ON consultas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_descuentos_updated_at BEFORE UPDATE ON descuentos
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_eventos_updated_at BEFORE UPDATE ON eventos_especiales
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_tarifas_updated_at BEFORE UPDATE ON tarifas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_config_updated_at BEFORE UPDATE ON configuracion_general
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ─── Triggers de log de cambio de estado ──────────────
-- (Se pasa el nombre del campo PK como argumento del trigger)
CREATE TRIGGER trg_log_pre_reservas_estado
  AFTER UPDATE OF estado ON pre_reservas
  FOR EACH ROW EXECUTE FUNCTION log_cambio_estado('id_pre_reserva');

CREATE TRIGGER trg_log_reservas_estado
  AFTER UPDATE OF estado ON reservas
  FOR EACH ROW EXECUTE FUNCTION log_cambio_estado('id_reserva');

CREATE TRIGGER trg_log_pagos_estado
  AFTER UPDATE OF estado ON pagos
  FOR EACH ROW EXECUTE FUNCTION log_cambio_estado('id_pago');

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 20 — Vistas SQL
-- ══════════════════════════════════════════════════════════════════════════
-- ─── V1. vista_disponibilidad ──────────────────────────
-- v1.7.3 (D-7A-03): horizonte configurable vía configuracion_general
-- con fallback 120. Rango exclusivo [CURRENT_DATE, CURRENT_DATE + N).
-- Forma persistida (pg_get_viewdef): 9 columnas explícitas; PostgreSQL
-- absorbe el cast ::DATE redundante sobre CURRENT_DATE + INTEGER.
CREATE OR REPLACE VIEW vista_disponibilidad AS
SELECT id_cabana,
    fecha,
    estado,
    tipo_dia,
    temporada,
    hora_checkin_base,
    hora_checkout_base,
    id_reserva_activa,
    id_prereserva_activa
   FROM obtener_disponibilidad_rango(CURRENT_DATE, CURRENT_DATE + COALESCE(( SELECT configuracion_general.valor::integer AS valor
           FROM configuracion_general
          WHERE configuracion_general.clave = 'horizonte_disponibilidad_dias'::text), 120), NULL::bigint);

-- ─── V2. vista_calendario ──────────────────────────────
-- Calendario operativo de reservas activas/confirmadas dentro del horizonte.
-- v1.7.2 (H6): TRIM aplicado a la concatenación nombre + apellido para
-- evitar espacio colgando cuando apellido es NULL o vacío.
-- v1.7.3 (D-7A-03): horizonte configurable vía configuracion_general con
-- fallback 120. Filtro inclusivo <= (operador sin cambios respecto a v1.7.2).
CREATE OR REPLACE VIEW vista_calendario AS
SELECT c.id_cabana,
    c.nombre AS cabana,
    r.id_reserva,
    r.fecha_checkin,
    r.fecha_checkout,
    r.hora_checkin,
    r.hora_checkout,
    r.personas,
    r.estado AS estado_reserva,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped_nombre,
    h.telefono AS huesped_telefono,
    r.monto_total,
    r.monto_saldo,
    r.encargado_semana
   FROM reservas r
     JOIN cabanas c ON c.id_cabana = r.id_cabana
     JOIN huespedes h ON h.id_huesped = r.id_huesped
  WHERE (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum])) AND r.fecha_checkout >= CURRENT_DATE AND r.fecha_checkin <= (CURRENT_DATE + COALESCE(( SELECT configuracion_general.valor::integer AS valor
           FROM configuracion_general
          WHERE configuracion_general.clave = 'horizonte_disponibilidad_dias'::text), 120))
  ORDER BY r.fecha_checkin, c.id_cabana;

-- ─── V3. vista_prereservas_activas ─────────────────────
-- v1.7.2 (H6-bis): TRIM aplicado a la concatenación nombre + apellido.
CREATE OR REPLACE VIEW vista_prereservas_activas AS
SELECT pr.id_pre_reserva,
    c.nombre AS cabana,
    pr.id_cabana,
    pr.fecha_in,
    pr.fecha_out,
    pr.personas,
    pr.estado,
    pr.expira_en,
    EXTRACT(epoch FROM pr.expira_en - now()) / 60::numeric AS minutos_para_vencer,
    pr.monto_total,
    pr.monto_sena,
    pr.canal_origen,
    pr.canal_pago_esperado,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped_nombre,
    h.telefono AS huesped_telefono
   FROM pre_reservas pr
     JOIN cabanas c ON c.id_cabana = pr.id_cabana
     JOIN huespedes h ON h.id_huesped = pr.id_huesped
  WHERE (pr.estado = ANY (ARRAY['pendiente_pago'::estado_prereserva_enum, 'pago_en_revision'::estado_prereserva_enum])) AND pr.expira_en > now()
  ORDER BY pr.expira_en;

-- ─── V4. vista_ocupacion ───────────────────────────────
-- Ocupación por cabaña y mes (últimos 12 meses y próximos 12).
-- v1.7.2 (H5): rango ajustado a 24 meses exactos restando '1 mon'::interval
-- al límite superior del generate_series para evitar el edge case que generaba
-- 25 puntos (= 25 meses × cabaña).
CREATE OR REPLACE VIEW vista_ocupacion AS
 WITH meses AS (
         SELECT generate_series(date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) - '1 year'::interval, date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) + '1 year'::interval - '1 mon'::interval, '1 mon'::interval)::date AS inicio_mes
        ), matriz AS (
         SELECT c.id_cabana,
            c.nombre AS cabana,
            m.inicio_mes,
            (m.inicio_mes + '1 mon'::interval - '1 day'::interval)::date AS fin_mes
           FROM cabanas c
             CROSS JOIN meses m
          WHERE c.activa = true
        )
 SELECT id_cabana,
    cabana,
    inicio_mes,
    fin_mes,
    COALESCE(( SELECT sum(LEAST(r.fecha_checkout, (mx.fin_mes + '1 day'::interval)::date) - GREATEST(r.fecha_checkin, mx.inicio_mes)) AS sum
           FROM reservas r
          WHERE r.id_cabana = mx.id_cabana AND (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum, 'completada'::estado_reserva_enum])) AND r.fecha_checkin < (mx.fin_mes + '1 day'::interval)::date AND r.fecha_checkout > mx.inicio_mes), 0::bigint) AS noches_ocupadas,
    EXTRACT(day FROM fin_mes + '1 day'::interval - inicio_mes::timestamp without time zone)::integer AS dias_del_mes
   FROM matriz mx
  ORDER BY id_cabana, inicio_mes;

-- ─── V5. vista_calendario_semanal (Sistema 3) ──────────
-- Próximos 7 días con todos los movimientos operativos
CREATE OR REPLACE VIEW vista_calendario_semanal AS
SELECT
  c.id_cabana,
  c.nombre AS cabana,
  d.fecha,
  -- Estado del día
  CASE
    WHEN EXISTS (
      SELECT 1 FROM bloqueos b
      WHERE b.activo = TRUE
        AND (b.id_cabana = c.id_cabana OR b.id_cabana IS NULL)
        AND d.fecha >= b.fecha_desde AND d.fecha < b.fecha_hasta
    ) THEN 'bloqueada'
    WHEN EXISTS (
      SELECT 1 FROM reservas r
      WHERE r.id_cabana = c.id_cabana
        AND r.estado IN ('confirmada', 'activa')
        AND d.fecha >= r.fecha_checkin AND d.fecha < r.fecha_checkout
    ) THEN 'ocupada'
    ELSE 'libre'
  END AS estado,
  -- ID de reserva si hay una activa este día
  (SELECT r.id_reserva FROM reservas r
   WHERE r.id_cabana = c.id_cabana
     AND r.estado IN ('confirmada', 'activa')
     AND d.fecha >= r.fecha_checkin AND d.fecha < r.fecha_checkout
   LIMIT 1) AS id_reserva,
  -- Si entra alguien este día
  (SELECT r.id_reserva FROM reservas r
   WHERE r.id_cabana = c.id_cabana
     AND r.estado IN ('confirmada', 'activa')
     AND r.fecha_checkin = d.fecha
   LIMIT 1) AS reserva_entrante,
  -- Si sale alguien este día
  (SELECT r.id_reserva FROM reservas r
   WHERE r.id_cabana = c.id_cabana
     AND r.estado IN ('confirmada', 'activa', 'completada')
     AND r.fecha_checkout = d.fecha
   LIMIT 1) AS reserva_saliente
FROM cabanas c
CROSS JOIN generate_series(CURRENT_DATE, (CURRENT_DATE + 6)::DATE, '1 day') AS d(fecha)
WHERE c.activa = TRUE
ORDER BY d.fecha, c.id_cabana;

-- ─── V6. vista_limpieza_semana (Sistema 4 — Jennifer) ──
-- Check-ins y check-outs de los próximos 7 días con horas declaradas.
-- v1.7.2 (H6): TRIM aplicado a la concatenación nombre + apellido en
-- ambas partes del UNION ALL (checkout y checkin).
CREATE OR REPLACE VIEW vista_limpieza_semana AS
 SELECT r.fecha_checkout AS fecha_movimiento,
    'checkout'::text AS tipo_movimiento,
    c.nombre AS cabana,
    c.id_cabana,
    r.id_reserva,
    r.hora_checkout AS hora,
    r.personas,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped,
    h.telefono AS huesped_telefono,
    r.mascotas,
    r.detalle_mascotas,
    r.notas_reserva
   FROM reservas r
     JOIN cabanas c ON c.id_cabana = r.id_cabana
     JOIN huespedes h ON h.id_huesped = r.id_huesped
  WHERE (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum, 'completada'::estado_reserva_enum])) AND r.fecha_checkout >= CURRENT_DATE AND r.fecha_checkout <= (CURRENT_DATE + 7)
UNION ALL
 SELECT r.fecha_checkin AS fecha_movimiento,
    'checkin'::text AS tipo_movimiento,
    c.nombre AS cabana,
    c.id_cabana,
    r.id_reserva,
    r.hora_checkin AS hora,
    r.personas,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped,
    h.telefono AS huesped_telefono,
    r.mascotas,
    r.detalle_mascotas,
    r.notas_reserva
   FROM reservas r
     JOIN cabanas c ON c.id_cabana = r.id_cabana
     JOIN huespedes h ON h.id_huesped = r.id_huesped
  WHERE (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum])) AND r.fecha_checkin >= CURRENT_DATE AND r.fecha_checkin <= (CURRENT_DATE + 7)
  ORDER BY 1, 6;

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 21 — Datos seed mínimos
-- ══════════════════════════════════════════════════════════════════════════
-- ─── CABAÑAS (datos reales — v1.2: capacidades corregidas) ───
-- Grandes: capacidad_base 3, capacidad_max 5
-- Chicas:  capacidad_base 2, capacidad_max 4
INSERT INTO cabanas (nombre, tipo, capacidad_base, capacidad_max, activa, orden_limpieza) VALUES
  ('Bamboo',       'grande', 3, 5, TRUE, 1),
  ('Madre Selva',  'grande', 3, 5, TRUE, 2),
  ('Arrebol',      'grande', 3, 5, TRUE, 3),
  ('Guatemala',    'chica',  2, 4, TRUE, 4),
  ('Tokio',        'chica',  2, 4, TRUE, 5);

-- ─── SOCIOS (tercer socio: Remo — D-PROMO v1.8.0) ─────
INSERT INTO socios (nombre, porcentaje_utilidades, activo) VALUES
  ('Franco',   33.33, TRUE),
  ('Rodrigo',  33.33, TRUE),
  ('Remo',     33.34, TRUE);  -- Tercer socio real (D-PROMO v1.8.0; antes placeholder 'Socio 3')

-- ─── CONFIGURACION_GENERAL (mínima para que funcione) ──
INSERT INTO configuracion_general (clave, valor, descripcion, categoria) VALUES
  ('hora_checkin_default',         '13:00', 'Check-in estándar',                'horarios'),
  ('hora_checkout_default',        '10:00', 'Check-out estándar',               'horarios'),
  ('hora_checkin_domingo',         '18:00', 'Check-in cuando domingo es primer día', 'horarios'),
  ('hora_checkout_domingo',        '16:00', 'Check-out cuando domingo es último día (vs default 10:00)', 'horarios'),  -- v1.7 (D47)
  ('hora_checkin_max_cliente',     '22:00', 'Hora máxima que puede elegir el cliente', 'horarios'),
  ('hora_checkout_min_cliente',    '07:00', 'Hora mínima que puede elegir el cliente', 'horarios'),
  ('escalonamiento_activo',        'true',  'Master switch del escalonamiento', 'escalonamiento'),
  ('escalonamiento_umbral_checkins_dia', '3', 'Check-ins simultáneos sin escalonar', 'escalonamiento'),
  ('prereserva_expiracion_minutos', '60',    'TTL default de pre-reservas',      'prereservas'),
  ('horizonte_disponibilidad_dias', '120',   'Horizonte forward en días para vista_disponibilidad y vista_calendario', 'disponibilidad');  -- v1.7.3 (D-7A-03)

-- ─── CUENTA_COBRO (PLACEHOLDER inactiva) ─────────────
INSERT INTO cuentas_cobro (alias, medio, detalle, titular, activa) VALUES
  ('Cuenta principal', 'transferencia_mp', 'CBU/Alias pendiente de cargar', 'Vita Delta', FALSE);  -- PLACEHOLDER

-- ─── TEMPORADA BASELINE (solo para DEV — NO ES PRODUCTIVA) ──
INSERT INTO temporadas (nombre, fecha_desde, fecha_hasta, multiplicador, activa) VALUES
  ('Baseline DEV 2026-2028', '2026-01-01', '2028-12-31', 1.000, TRUE);

-- ─── PLANTILLA MÍNIMA ────────────────────────────────
INSERT INTO plantillas_mensajes (codigo, nombre, canal, destinatario, contenido, activa) VALUES
  ('prereserva_creada', 'Pre-reserva creada — confirmación al huésped',
   'whatsapp', 'huesped',
   'Hola {{nombre_huesped}}, te confirmo la pre-reserva de {{cabana}} del {{fecha_in}} al {{fecha_out}}. El monto total es ${{monto_total}} y la seña ${{monto_sena}}. Tenés {{expiracion_minutos}} minutos para pagar la seña. Cualquier duda, escribime.',
   TRUE);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 22 — Schedule pg_cron
-- ══════════════════════════════════════════════════════════════════════════
-- Job 1: expirar pre-reservas cada 5 minutos
SELECT cron.schedule(
  'expirar_prereservas',
  '*/5 * * * *',
  $$SELECT expirar_prereservas_vencidas();$$
);

-- Job 2: limpieza mensual del historial de cron
SELECT cron.schedule(
  'cleanup_cron_history',
  '0 3 1 * *',  -- día 1 de cada mes a las 03:00 UTC
  $$DELETE FROM cron.job_run_details WHERE end_time < NOW() - INTERVAL '30 days';$$
);

-- ══════════════════════════════════════════════════════════════════════════
-- BLOQUE 23 — Hardening de funciones del motor (REVOKE EXECUTE)
-- ══════════════════════════════════════════════════════════════════════════
-- ── Bloque 23. Hardening del motor — REVOKE EXECUTE a PUBLIC/anon/authenticated/service_role ──
-- 13 funciones del motor (firma por tipo; sin sobrecargas):
REVOKE EXECUTE ON FUNCTION public.normalizar_telefono(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.set_telefono_normalizado() FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.upsert_huesped(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.validar_disponibilidad(bigint, date, date, bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.obtener_disponibilidad_rango(date, date, bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.crear_prereserva(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.confirmar_reserva(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.cancelar_prereserva(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.crear_bloqueo(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.registrar_pago(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.expirar_prereservas_vencidas() FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.log_cambio_estado() FROM PUBLIC, anon, authenticated, service_role;
