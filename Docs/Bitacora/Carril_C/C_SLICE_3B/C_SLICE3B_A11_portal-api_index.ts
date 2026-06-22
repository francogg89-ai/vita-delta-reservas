// supabase/functions/portal-api/index.ts
// ============================================================================
// Carril C / Portal Operativo Interno — Edge Function "portal-api" (gateway/BFF).
// Slice 1, Bloque 1A — infraestructura común del gateway.
//
// Decisiones:
//   D-C-13 (Edge Fn = frontera de confianza), D-C-14 (identidad por portal_usuarios),
//   D-C-15 (gateway único action+payload + revalidación n8n), D-C-18 (error envelope
//   uniforme + payload mínimo), D-C-22 (nombre = persona), D-C-29 (HMAC-SHA256 sobre
//   bytes literales del body), D-C-30 (JWT vía getUser), D-C-31 (allowlist constante
//   versionada; una acción aparece SOLO al cablearse), D-C-34 (portal_usuarios solo
//   server-side), D-C-35 (HTTP 200 + envelope para resultados manejados; 5xx solo
//   para fallos inesperados).
//   Slice 1: D-C-36 (lecturas vía wrappers n8n firmados), D-C-37 (VITA_AMBIENTE +
//   N8N_BASE_URL en preflight duro; ambiente_esperado sale de VITA_AMBIENTE),
//   D-C-38 (contratos de salida), D-C-39 (allowlist doble: gateway + wrapper),
//   D-C-40 (A05-detalle; id_reserva validado).
//
// Bloque 1A NO agrega ninguna acción n8n al CATALOG (D-C-31): solo deja lista la
// infraestructura común (preflight de las dos env vars nuevas, dispatch genérico a
// n8n con validación estricta del envelope de vuelta, y los validadores de payload).
// El CATALOG sigue con sesion.contexto únicamente; A03 se cablea recién en Bloque 3.
//
// IMPORTANTE — verify_jwt = false (en config.toml): la validación del JWT se hace
// EN el handler con getUser, para devolver SIEMPRE el envelope uniforme, incluso si
// el JWT falta / es inválido / está expirado.
// ============================================================================

// jsr es el specifier actual de Supabase; "npm:@supabase/supabase-js@2" es equivalente.
import { createClient } from 'jsr:@supabase/supabase-js@2';

// ---------------------------------------------------------------------------
// Tipos de catálogo / allowlist versionada (D-C-31). Unión discriminada por handler:
//   'edge' → se resuelve en la Edge Function (hoy: solo sesion.contexto).
//   'n8n'  → se rutea a un wrapper n8n firmado (HMAC); requiere webhook + validate.
// Una acción aparece acá SOLO cuando está wired. Slice 1 / Bloque 1A: sin acciones n8n.
// Para crecer: agregar entrada por acción { handler:'n8n', roles, webhook, validate }.
// ---------------------------------------------------------------------------
type Rol = 'jenny' | 'vicky' | 'socio';

type PayloadValidation = { ok: true; value: unknown } | { ok: false; message: string };
export type PayloadValidator = (payload: unknown) => PayloadValidation;

type CatalogEntry =
  | { handler: 'edge'; roles: Rol[] }
  | { handler: 'n8n'; roles: Rol[]; webhook: string; validate: PayloadValidator; injectActor?: boolean; isWrite?: boolean; needsIdempotencyKey?: boolean };

// ---------------------------------------------------------------------------
// Validadores de payload (D-C-18: payload mínimo en el gateway, ANTES de firmar; el
// wrapper revalida antes del Postgres node — D-C-39/40). Exportados para reuso/tests.
// ---------------------------------------------------------------------------

// Acciones sin parámetros (A03/A04/A06/A12): acepta {} / cualquier objeto y NO
// reenvía nada del payload del cliente al wrapper.
export const payloadVacio: PayloadValidator = () => ({ ok: true, value: {} });

// A05 (D-C-40): id_reserva entero positivo ESTRICTO. Solo number (no strings, ni
// siquiera numéricos); rechaza arrays / objetos / decimales / booleanos / vacío.
// Devuelve un payload whitelisteado { id_reserva } (descarta claves extra). Así el
// Postgres node nunca recibe algo que dispare un cast error crudo.
export const payloadIdReserva: PayloadValidator = (payload) => {
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
    return { ok: false, message: 'payload inválido: se esperaba un objeto con id_reserva' };
  }
  const raw = (payload as Record<string, unknown>).id_reserva;
  // isSafeInteger: rechaza decimales, NaN/Infinity y enteros fuera del rango seguro de
  // JS (un id que no se representa exacto no se confía, aunque BIGINT lo permita).
  if (typeof raw !== 'number' || !Number.isSafeInteger(raw) || raw <= 0) {
    return { ok: false, message: 'id_reserva debe ser un entero positivo' };
  }
  return { ok: true, value: { id_reserva: raw } };
};

// A07 (Slice 2) — Validador del payload de creación manual de reserva. ESPEJO EXACTO
// de la validación de negocio del wrapper (validar_firma_ts_rol): reject-unknown,
// fecha YMD real (round-trip UTC), hora en rango, contacto con dígitos/email válidos,
// enums y montos. Doble allowlist (D-C-39): el gateway valida ANTES de firmar; el
// wrapper revalida antes del Postgres. `actor` NO es clave del payload: viaja en el
// sobre, inyectado server-side. Devuelve el payload whitelisteado (sin claves extra).
const ENUM_PAGO_GW = ['transferencia_bancaria', 'transferencia_mp', 'mp_link', 'cripto', 'efectivo'];
const EMAIL_RE_GW = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAXLEN_GW = 1000;
const ENUM_MOTIVO_GW = ['mantenimiento', 'uso_propio', 'tormenta', 'overbooking', 'otro'];
// A10 (Slice 2): medio_pago de registro de saldo (ENUM_MEDIO_A10, D-C-50). NO incluye
// mp_link (A10 es carga manual de saldo ya cobrado, no link de pago) — distinto de
// ENUM_PAGO_GW. MONTO_MAX_A10_GW = tope de NUMERIC(12,2).
const ENUM_MEDIO_A10_GW = ['efectivo', 'transferencia_bancaria', 'transferencia_mp', 'cripto'];
const MONTO_MAX_A10_GW = 9999999999.99;
function isYMD_GW(s: unknown): s is string {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const Y = +s.slice(0, 4), M = +s.slice(5, 7), D = +s.slice(8, 10);
  if (M < 1 || M > 12 || D < 1 || D > 31) return false;
  const dt = new Date(Date.UTC(Y, M - 1, D));
  return dt.getUTCFullYear() === Y && dt.getUTCMonth() === M - 1 && dt.getUTCDate() === D;
}
function isHMS_GW(s: unknown): s is string {
  if (typeof s !== 'string' || !/^\d{2}:\d{2}(:\d{2})?$/.test(s)) return false;
  const h = +s.slice(0, 2), m = +s.slice(3, 5), sec = s.length > 5 ? +s.slice(6, 8) : 0;
  return h >= 0 && h <= 23 && m >= 0 && m <= 59 && sec >= 0 && sec <= 59;
}
export const payloadCrearManual: PayloadValidator = (payload) => {
  const bad = (message: string): PayloadValidation => ({ ok: false, message });
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return bad('payload inválido: se esperaba un objeto');
  const p = payload as Record<string, unknown>;
  const PERMITIDAS = ['id_cabana', 'fecha_in', 'fecha_out', 'personas', 'monto_total', 'monto_sena',
    'canal_pago_esperado', 'medio_pago', 'huesped', 'mascotas', 'detalle_mascotas', 'ninos', 'notas',
    'notas_reserva', 'hora_checkin_solicitada', 'hora_checkout_solicitada'];
  for (const k of Object.keys(p)) if (!PERMITIDAS.includes(k)) return bad(`clave no permitida en payload: ${k}`);
  const isStr = (v: unknown): v is string => typeof v === 'string';
  const okLen = (v: string) => v.length <= MAXLEN_GW;

  if (typeof p.id_cabana !== 'number' || !Number.isSafeInteger(p.id_cabana) || p.id_cabana <= 0) return bad('id_cabana debe ser entero positivo');
  if (!isYMD_GW(p.fecha_in) || !isYMD_GW(p.fecha_out)) return bad('fecha_in/fecha_out deben ser YYYY-MM-DD válidas');
  if (!(p.fecha_in < p.fecha_out)) return bad('fecha_out debe ser posterior a fecha_in');
  if (typeof p.personas !== 'number' || !Number.isSafeInteger(p.personas) || p.personas < 1) return bad('personas debe ser entero >= 1');
  if (typeof p.monto_total !== 'number' || !Number.isFinite(p.monto_total) || p.monto_total <= 0) return bad('monto_total inválido');
  if (typeof p.monto_sena !== 'number' || !Number.isFinite(p.monto_sena) || p.monto_sena < 0 || p.monto_sena > p.monto_total) return bad('monto_sena inválido (0 <= seña <= total)');
  if (!ENUM_PAGO_GW.includes(p.canal_pago_esperado as string)) return bad('canal_pago_esperado inválido');
  if (!ENUM_PAGO_GW.includes(p.medio_pago as string)) return bad('medio_pago inválido');

  const h = p.huesped;
  if (typeof h !== 'object' || h === null || Array.isArray(h)) return bad('huesped inválido');
  const hh = h as Record<string, unknown>;
  for (const k of Object.keys(hh)) if (!['nombre', 'telefono', 'email'].includes(k)) return bad(`clave no permitida en huesped: ${k}`);
  if (!isStr(hh.nombre) || hh.nombre.trim() === '' || !okLen(hh.nombre)) return bad('huesped.nombre inválido');
  let telVal: string | null = null;
  let emaVal: string | null = null;
  if (hh.telefono !== undefined && hh.telefono !== null) {
    if (!isStr(hh.telefono) || !okLen(hh.telefono)) return bad('huesped.telefono inválido');
    const t = hh.telefono.trim();
    if (t !== '') { if (t.replace(/\D/g, '').length < 6) return bad('huesped.telefono sin dígitos suficientes'); telVal = t; }
  }
  if (hh.email !== undefined && hh.email !== null) {
    if (!isStr(hh.email) || !okLen(hh.email)) return bad('huesped.email inválido');
    const e = hh.email.trim();
    if (e !== '') { if (!EMAIL_RE_GW.test(e)) return bad('huesped.email inválido'); emaVal = e; }
  }
  if (telVal === null && emaVal === null) return bad('huesped requiere teléfono (>=6 dígitos) o email');

  for (const k of ['detalle_mascotas', 'ninos', 'notas', 'notas_reserva']) {
    const val = p[k];
    if (val !== undefined && val !== null && (!isStr(val) || !okLen(val))) return bad(`${k} inválido`);
  }
  if (p.mascotas !== undefined && p.mascotas !== null && typeof p.mascotas !== 'boolean') return bad('mascotas debe ser booleano');
  if (p.hora_checkin_solicitada !== undefined && p.hora_checkin_solicitada !== null && !isHMS_GW(p.hora_checkin_solicitada)) return bad('hora_checkin_solicitada inválida');
  if (p.hora_checkout_solicitada !== undefined && p.hora_checkout_solicitada !== null && !isHMS_GW(p.hora_checkout_solicitada)) return bad('hora_checkout_solicitada inválida');

  const value = {
    id_cabana: p.id_cabana, fecha_in: p.fecha_in, fecha_out: p.fecha_out, personas: p.personas,
    monto_total: p.monto_total, monto_sena: p.monto_sena,
    canal_pago_esperado: p.canal_pago_esperado, medio_pago: p.medio_pago,
    mascotas: p.mascotas === true,
    detalle_mascotas: (p.detalle_mascotas != null ? p.detalle_mascotas : null),
    ninos: (p.ninos != null ? p.ninos : null),
    notas: (p.notas != null ? p.notas : null),
    notas_reserva: (p.notas_reserva != null ? p.notas_reserva : null),
    hora_checkin_solicitada: (p.hora_checkin_solicitada != null ? p.hora_checkin_solicitada : null),
    hora_checkout_solicitada: (p.hora_checkout_solicitada != null ? p.hora_checkout_solicitada : null),
    huesped: { nombre: (hh.nombre as string).trim(), telefono: telVal, email: emaVal },
  };
  return { ok: true, value };
};

// A08 (Slice 2) — Validador del payload de creación manual de bloqueo. ESPEJO EXACTO
// del wrapper (validar_firma_ts_rol A08): reject-unknown, id_cabana OBLIGATORIO (entero
// positivo; bloqueo total NO se expone en el portal, decisión 8D), fechas YMD reales con
// hasta > desde, motivo en enum, descripción opcional. `actor` NO es clave del payload:
// viaja en el sobre, inyectado server-side, y el wrapper lo usa como creado_por.
export const payloadCrearBloqueo: PayloadValidator = (payload) => {
  const bad = (message: string): PayloadValidation => ({ ok: false, message });
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return bad('payload inválido: se esperaba un objeto');
  const p = payload as Record<string, unknown>;
  const PERMITIDAS = ['id_cabana', 'fecha_desde', 'fecha_hasta', 'motivo', 'descripcion'];
  for (const k of Object.keys(p)) if (!PERMITIDAS.includes(k)) return bad(`clave no permitida en payload: ${k}`);
  const isStr = (v: unknown): v is string => typeof v === 'string';
  const okLen = (v: string) => v.length <= MAXLEN_GW;

  if (typeof p.id_cabana !== 'number' || !Number.isSafeInteger(p.id_cabana) || p.id_cabana <= 0) return bad('id_cabana debe ser entero positivo (bloqueo total no se expone)');
  if (!isYMD_GW(p.fecha_desde) || !isYMD_GW(p.fecha_hasta)) return bad('fecha_desde/fecha_hasta deben ser YYYY-MM-DD válidas');
  if (!(p.fecha_desde < p.fecha_hasta)) return bad('fecha_hasta debe ser posterior a fecha_desde');
  if (!ENUM_MOTIVO_GW.includes(p.motivo as string)) return bad('motivo inválido');
  if (p.descripcion !== undefined && p.descripcion !== null && (!isStr(p.descripcion) || !okLen(p.descripcion))) return bad('descripcion inválida');

  const value = {
    id_cabana: p.id_cabana, fecha_desde: p.fecha_desde, fecha_hasta: p.fecha_hasta,
    motivo: p.motivo, descripcion: (p.descripcion != null ? p.descripcion : null),
  };
  return { ok: true, value };
};

// A10 (Slice 2) — Validador del payload de registro de saldo. ESPEJO EXACTO de la capa
// de payload de coreValidate del wrapper A10 (a10_validator_core.mjs, líneas 83-116):
// reject-unknown, id_reserva entero positivo estricto, monto number finito >0 con ≤2
// decimales dentro de NUMERIC(12,2), medio_pago en ENUM_MEDIO_A10 (sin mp_link),
// idempotency_key 8-64 [A-Za-z0-9_-], notas opcional. `actor` NO es clave del payload:
// viaja en el sobre, inyectado server-side (injectActor), y el wrapper lo usa como
// validado_por. Doble allowlist (D-C-39): el gateway valida ANTES de firmar; el wrapper
// revalida antes del Postgres. Devuelve el payload whitelisteado (sin claves extra).
export const payloadRegistrarSaldo: PayloadValidator = (payload) => {
  const bad = (message: string): PayloadValidation => ({ ok: false, message });
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return bad('payload inválido: se esperaba un objeto');
  const p = payload as Record<string, unknown>;
  const PERMITIDAS = ['id_reserva', 'monto', 'medio_pago', 'idempotency_key', 'notas'];
  for (const k of Object.keys(p)) if (!PERMITIDAS.includes(k)) return bad(`clave no permitida en payload: ${k}`);
  const isStr = (v: unknown): v is string => typeof v === 'string';

  if (typeof p.id_reserva !== 'number' || !Number.isSafeInteger(p.id_reserva) || p.id_reserva <= 0) return bad('id_reserva debe ser entero positivo');

  const monto = p.monto;
  if (typeof monto !== 'number' || !Number.isFinite(monto) || monto <= 0) return bad('monto debe ser número positivo finito');
  const cents = Math.round(monto * 100);
  if (Math.abs(monto * 100 - cents) > 1e-6) return bad('monto admite máximo 2 decimales');
  if (cents <= 0 || monto > MONTO_MAX_A10_GW) return bad('monto fuera de rango');

  if (!ENUM_MEDIO_A10_GW.includes(p.medio_pago as string)) return bad('medio_pago inválido');

  const key = p.idempotency_key;
  if (!isStr(key) || key.length < 8 || key.length > 64 || !/^[A-Za-z0-9_-]+$/.test(key)) return bad('idempotency_key inválida');

  if (p.notas !== undefined && p.notas !== null && (!isStr(p.notas) || p.notas.length > MAXLEN_GW)) return bad('notas inválida');

  const value = {
    id_reserva: p.id_reserva, monto, medio_pago: p.medio_pago, idempotency_key: key,
    notas: (p.notas != null ? p.notas : null),
  };
  return { ok: true, value };
};

// A24 (Slice 3a) — historico.reservas (buscador operativo de reservas, LECTURA). ESPEJO EXACTO
// del paso 9 del wrapper (validar_firma_ts_rol): reject-unknown, tipos/enum/fechas, defaults,
// y clamp de fecha_desde al floor 2026-07-01 (D-C-11/20: recorta, no rechaza). Devuelve el
// payload NORMALIZADO/whitelisteado (los 7 campos), que es lo que se firma y se manda al wrapper
// (v.value en el handler). El wrapper revalida idempotentemente (2da defensa, D-C-39). Lectura:
// SIN actor (no injectActor), SIN isWrite. Reusa isYMD_GW y MAXLEN_GW.
const FLOOR_A24_GW = '2026-07-01';
const ENUM_ESTADO_RESERVA_GW = ['confirmada', 'activa', 'completada', 'cancelada', 'cancelada_con_cargo', 'conflicto_pendiente'];
export const payloadHistoricoReservas: PayloadValidator = (payload) => {
  const bad = (message: string): PayloadValidation => ({ ok: false, message });
  // payload no-objeto -> rechazo (NO se coerciona a {}); ausente/null lo normaliza el handler a {}.
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return bad('payload inválido: se esperaba un objeto');
  const p = payload as Record<string, unknown>;
  const PERMITIDAS = ['fecha_desde', 'fecha_hasta', 'id_cabana', 'estado', 'texto', 'limit', 'offset'];
  for (const k of Object.keys(p)) if (!PERMITIDAS.includes(k)) return bad(`clave no permitida en payload: ${k}`);

  // fecha_desde: opcional; YMD real; clamp al floor (nunca < floor). Default = floor.
  let fecha_desde = FLOOR_A24_GW;
  if (p.fecha_desde !== undefined && p.fecha_desde !== null) {
    if (!isYMD_GW(p.fecha_desde)) return bad('fecha_desde inválida (YYYY-MM-DD)');
    fecha_desde = (p.fecha_desde as string) < FLOOR_A24_GW ? FLOOR_A24_GW : (p.fecha_desde as string);
  }

  // fecha_hasta: opcional; YMD real y >= fecha_desde; default null (sin cota: buscador operativo).
  let fecha_hasta: string | null = null;
  if (p.fecha_hasta !== undefined && p.fecha_hasta !== null) {
    if (!isYMD_GW(p.fecha_hasta)) return bad('fecha_hasta inválida (YYYY-MM-DD)');
    if ((p.fecha_hasta as string) < fecha_desde) return bad('fecha_hasta no puede ser anterior a fecha_desde');
    fecha_hasta = p.fecha_hasta as string;
  }

  // id_cabana: opcional; entero > 0; default null = todas (sin sentinela externa).
  let id_cabana: number | null = null;
  if (p.id_cabana !== undefined && p.id_cabana !== null) {
    const c = p.id_cabana;
    if (typeof c !== 'number' || !Number.isSafeInteger(c) || c <= 0) return bad('id_cabana debe ser un entero positivo');
    id_cabana = c;
  }

  // estado: opcional; en el enum estado_reserva_enum; default null = todos.
  let estado: string | null = null;
  if (p.estado !== undefined && p.estado !== null) {
    if (typeof p.estado !== 'string' || !ENUM_ESTADO_RESERVA_GW.includes(p.estado)) return bad('estado fuera del enum');
    estado = p.estado;
  }

  // texto: opcional; string no vacío <= 1000; default null.
  let texto: string | null = null;
  if (p.texto !== undefined && p.texto !== null) {
    if (typeof p.texto !== 'string' || p.texto.length > MAXLEN_GW) return bad('texto inválido (máx 1000)');
    const t = p.texto.trim();
    if (t !== '') texto = t;
  }

  // limit: opcional; entero; clamp [1,200]; default 50.
  let limit = 50;
  if (p.limit !== undefined && p.limit !== null) {
    if (typeof p.limit !== 'number' || !Number.isSafeInteger(p.limit)) return bad('limit debe ser un entero');
    limit = Math.min(Math.max(p.limit, 1), 200);
  }

  // offset: opcional; entero >= 0; default 0.
  let offset = 0;
  if (p.offset !== undefined && p.offset !== null) {
    if (typeof p.offset !== 'number' || !Number.isSafeInteger(p.offset) || p.offset < 0) return bad('offset debe ser un entero >= 0');
    offset = p.offset;
  }

  return { ok: true, value: { fecha_desde, fecha_hasta, id_cabana, estado, texto, limit, offset } };
};

// A25 (Slice 3a) — ingresos.cobrados_periodo (caja percibida, LECTURA). Espejo del paso 9 del
// wrapper portal-a25-ingresos. Floor 2026-07-01 (D-NEG-02) clampea periodo_desde. periodo_hasta
// es HIBRIDO: si el cliente lo OMITE, el value NO incluye la clave (el wrapper aplica el default
// "hoy" sin tratarlo como explicito y SIN check de inversion). Si viene EXPLICITO: YMD valido y,
// tras el clamp, >= periodo_desde; null/no-string/mal formado/invertido -> payload_invalido. Esto
// preserva exactamente la semantica del wrapper directo. Reusa isYMD_GW y el floor de Carril B.
const FLOOR_A25_GW = FLOOR_A24_GW; // mismo floor Carril B (2026-07-01, D-NEG-02)
export const payloadIngresosPeriodo: PayloadValidator = (payload) => {
  const bad = (message: string): PayloadValidation => ({ ok: false, message });
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return bad('payload inválido: se esperaba un objeto');
  const p = payload as Record<string, unknown>;
  const PERMITIDAS = ['periodo_desde', 'periodo_hasta', 'limit', 'offset'];
  for (const k of Object.keys(p)) if (!PERMITIDAS.includes(k)) return bad(`clave no permitida en payload: ${k}`);

  // periodo_desde: opcional; YMD; clamp al floor. Default = floor.
  let periodo_desde = FLOOR_A25_GW;
  if (p.periodo_desde !== undefined && p.periodo_desde !== null) {
    if (!isYMD_GW(p.periodo_desde)) return bad('periodo_desde inválida (YYYY-MM-DD)');
    periodo_desde = (p.periodo_desde as string) < FLOOR_A25_GW ? FLOOR_A25_GW : (p.periodo_desde as string);
  }

  const value: Record<string, unknown> = { periodo_desde };

  // periodo_hasta: SOLO si la clave esta PRESENTE (explicito). Omitida (undefined) -> NO se
  // incluye en value (el wrapper defaultea a hoy, sin check). Presente null/no-string/mal
  // formado -> payload_invalido. Presente valida pero invertida tras el clamp -> payload_invalido.
  if (p.periodo_hasta !== undefined) {
    if (!isYMD_GW(p.periodo_hasta)) return bad('periodo_hasta inválida (YYYY-MM-DD)');
    if ((p.periodo_hasta as string) < periodo_desde) return bad('periodo_hasta no puede ser anterior a periodo_desde');
    value.periodo_hasta = p.periodo_hasta;
  }

  // limit: opcional; entero; clamp [1,200]; default 50.
  let limit = 50;
  if (p.limit !== undefined && p.limit !== null) {
    if (typeof p.limit !== 'number' || !Number.isSafeInteger(p.limit)) return bad('limit debe ser un entero');
    limit = Math.min(Math.max(p.limit, 1), 200);
  }
  value.limit = limit;

  // offset: opcional; entero >= 0; default 0.
  let offset = 0;
  if (p.offset !== undefined && p.offset !== null) {
    if (typeof p.offset !== 'number' || !Number.isSafeInteger(p.offset) || p.offset < 0) return bad('offset debe ser un entero >= 0');
    offset = p.offset;
  }
  value.offset = offset;

  return { ok: true, value };
};

// A11 (Slice 3b) — cargar.gasto_interno (PRIMERA ESCRITURA NO-IDEMPOTENTE, D-C-55/56/57). ESPEJO
// EXACTO del paso 10 del wrapper (validar_firma_ts_rol): reject-unknown sobre las 13 claves de
// negocio + tipos + 2 enums (clase, pagador_tipo). La COHERENCIA (clase×zona/cabaña, pagador,
// comentario obligatorio, horas de trabajo → socio, periodo día 1) NO se replica acá: la deciden
// las 18 constraints de gastos_internos dentro de la función (D-C-55), que mapea toda violación a
// payload_invalido con detail.constraint. Devuelve el payload NORMALIZADO/whitelisteado (los 13
// campos, igual que el payloadWL del wrapper), que es lo que se firma y viaja en envelope.payload.
// Reusa isYMD_GW y MAXLEN_GW.
//
// idempotency_key NO es clave del payload (D-C-57): viaja SIBLING de payload (frontend→gateway) y
// top-level en el sobre firmado (gateway→wrapper); el handler lo lee/valida aparte con IDEM_RE_GW.
// actor/rol los inyecta el gateway server-side (injectActor + JWT), NUNCA el frontend. Por eso este
// validador RECHAZA explícitamente (fail-fast, mensaje claro) los campos de control DENTRO del
// payload — además del reject-unknown genérico, que igual los bouncearía: actor, rol, nonce,
// source_event, creado_por, request_ts, idempotency_key en payload -> payload_invalido.
const IDEM_RE_GW = /^[A-Za-z0-9_-]{8,64}$/;
const ENUM_CLASE_GW = ['A', 'C', 'D', 'E'];
const ENUM_PAGADOR_GW = ['socio', 'caja'];
const CONTROL_EN_PAYLOAD_A11 = ['actor', 'rol', 'nonce', 'source_event', 'creado_por', 'request_ts', 'idempotency_key'];
export const payloadCargarGastoInterno: PayloadValidator = (payload) => {
  const bad = (message: string): PayloadValidation => ({ ok: false, message });
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return bad('payload inválido: se esperaba un objeto');
  const p = payload as Record<string, unknown>;
  // Rechazo explícito de control en payload (fail-fast); el reject-unknown de abajo igual los bouncearía.
  for (const k of CONTROL_EN_PAYLOAD_A11) if (k in p) return bad(`campo de control no permitido en payload: ${k}`);
  const PERMITIDAS = ['fecha', 'periodo', 'clase', 'clase_sugerida', 'etiqueta', 'monto',
    'id_zona', 'id_cabana', 'pagador_tipo', 'id_socio_pagador', 'medio_pago', 'comentario', 'comprobante_url'];
  for (const k of Object.keys(p)) if (!PERMITIDAS.includes(k)) return bad(`clave no permitida en payload: ${k}`);

  const isStr = (v: unknown): v is string => typeof v === 'string';
  const okLen = (v: string) => v.length <= MAXLEN_GW;
  const isPosInt = (v: unknown): v is number => typeof v === 'number' && Number.isSafeInteger(v) && v > 0;

  // Espejo EXACTO del wrapper: opcionales con `!= null` (null y ausente se tratan igual -> null en WL).
  if (!isYMD_GW(p.fecha)) return bad('fecha inválida (YYYY-MM-DD)');
  if (p.periodo != null && !isYMD_GW(p.periodo)) return bad('periodo inválido (YYYY-MM-DD)');
  if (!isStr(p.clase) || !ENUM_CLASE_GW.includes(p.clase as string)) return bad('clase inválida');
  if (p.clase_sugerida != null && (!isStr(p.clase_sugerida) || !ENUM_CLASE_GW.includes(p.clase_sugerida as string))) return bad('clase_sugerida inválida');
  if (!isStr(p.etiqueta) || (p.etiqueta as string).trim() === '' || !okLen(p.etiqueta as string)) return bad('etiqueta inválida');
  if (typeof p.monto !== 'number' || !Number.isFinite(p.monto) || p.monto <= 0) return bad('monto debe ser número positivo finito');
  if (p.id_zona != null && !isPosInt(p.id_zona)) return bad('id_zona debe ser entero positivo');
  if (p.id_cabana != null && !isPosInt(p.id_cabana)) return bad('id_cabana debe ser entero positivo');
  if (!isStr(p.pagador_tipo) || !ENUM_PAGADOR_GW.includes(p.pagador_tipo as string)) return bad('pagador_tipo inválido');
  if (p.id_socio_pagador != null && !isPosInt(p.id_socio_pagador)) return bad('id_socio_pagador debe ser entero positivo');
  for (const k of ['medio_pago', 'comentario', 'comprobante_url']) {
    const val = p[k];
    if (val != null && (!isStr(val) || !okLen(val))) return bad(`${k} inválido`);
  }

  const value = {
    fecha: p.fecha,
    periodo: (p.periodo != null ? p.periodo : null),
    clase: p.clase,
    clase_sugerida: (p.clase_sugerida != null ? p.clase_sugerida : null),
    etiqueta: (p.etiqueta as string).trim(),
    monto: p.monto,
    id_zona: (p.id_zona != null ? p.id_zona : null),
    id_cabana: (p.id_cabana != null ? p.id_cabana : null),
    pagador_tipo: p.pagador_tipo,
    id_socio_pagador: (p.id_socio_pagador != null ? p.id_socio_pagador : null),
    medio_pago: (p.medio_pago != null ? (p.medio_pago as string).trim() : null),
    comentario: (p.comentario != null ? (p.comentario as string).trim() : null),
    comprobante_url: (p.comprobante_url != null ? (p.comprobante_url as string).trim() : null),
  };
  return { ok: true, value };
};

// Coherencia rol↔actor (server-side, ANTES de firmar): el rol gobierna la allowlist;
// el actor (persona) gobierna validado_por/created_by aguas abajo (D-C-22). vicky es
// rol y persona; socio agrupa a franco/rodrigo/remo. jenny no llega (rebota por rol).
export function actorCoherente(rol: Rol, nombre: string): boolean {
  if (rol === 'vicky') return nombre === 'vicky';
  if (rol === 'socio') return nombre === 'franco' || nombre === 'rodrigo' || nombre === 'remo';
  return false;
}

const CATALOG: Record<string, CatalogEntry> = {
  'sesion.contexto': { handler: 'edge', roles: ['jenny', 'vicky', 'socio'] },
  // A03 (Slice 1 / Bloque 3) — Calendario de limpieza. Wrapper n8n firmado
  // (portal-a03-limpieza), 3 roles (D-C-39), sin parametros (validate: payloadVacio).
  // El key DEBE coincidir con EXPECTED_ACTION del wrapper (action binding).
  'calendario.limpieza': { handler: 'n8n', roles: ['jenny', 'vicky', 'socio'], webhook: 'portal-a03-limpieza', validate: payloadVacio },
  // A04 (Slice 1 / Bloque 5) — Calendario operativo (120 días, con montos). Wrapper n8n
  // firmado (portal-a04-operativo). SOLO vicky/socio (D-C-39): jenny NO ve económicos →
  // rebota con rol_no_permitido EN EL GATEWAY (allowlist, línea ~392), antes de firmar y
  // sin tocar n8n. El key DEBE coincidir con EXPECTED_ACTION del wrapper (action binding,
  // D-C-41). validate: payloadVacio (acción sin parámetros).
  'calendario.operativo': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a04-operativo', validate: payloadVacio },
  // A05 (Slice 1 / Bloque 7) — Detalle de reserva por id. Wrapper n8n firmado
  // (portal-a05-detalle). SOLO vicky/socio (D-C-39): incluye montos → jenny excluida
  // (D-C-03), rebota con rol_no_permitido EN EL GATEWAY antes de firmar. PRIMERA acción con
  // payload: validate: payloadIdReserva (D-C-40, id entero positivo estricto; un payload
  // inválido se rechaza acá ANTES de firmar, no toca n8n). Action binding D-C-41/42; contrato
  // JSON data:{reserva,pagos} (D-C-43); lectura join directo, no vista_calendario (D-C-44).
  'reserva.detalle': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a05-detalle', validate: payloadIdReserva },
  // A06 (Slice 1 / Bloque 9) — Prereservas activas (lista). Wrapper n8n firmado
  // (portal-a06-prereservas). SOLO vicky/socio (D-C-39): muestra montos de prereserva →
  // jenny excluida (D-C-03), rebota con rol_no_permitido EN EL GATEWAY antes de firmar.
  // Sin parámetros (validate: payloadVacio). Lee vista_prereservas_activas (reuse, D-C-46);
  // contrato JSON data:{filas}, lista vacía => filas:[] con ok:true (D-C-47). Action binding
  // D-C-41/45 (key == EXPECTED_ACTION del wrapper).
  'prereservas.activas': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a06-prereservas', validate: payloadVacio },
  // A12 (Slice 1 / Bloque 11) — Saldos de cobranza (lista). Wrapper n8n firmado
  // (portal-a12-saldos). SOLO vicky/socio (D-C-39): muestra montos/estado de cobranza →
  // jenny excluida (D-C-03), rebota con rol_no_permitido EN EL GATEWAY antes de firmar.
  // Sin parámetros (validate: payloadVacio). Reusa la lógica de vita_w09_listado_saldos
  // (D-C-49): reservas confirmada/activa con saldo_real>0, saldo calculado por pagos
  // confirmados (D-C-40/D-9B-05). Contrato JSON data:{filas}, lista vacía => filas:[] con
  // ok:true (D-C-47). Action binding D-C-41/48 (key == EXPECTED_ACTION del wrapper).
  'cobranza.saldos': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a12-saldos', validate: payloadVacio },
  // A24 (Slice 3a) — Histórico/buscador operativo de reservas. Wrapper n8n firmado
  // (portal-a24-historico-reservas). SOLO vicky/socio (D-C-39): incluye montos/saldo →
  // jenny excluida (D-C-03), rebota con rol_no_permitido EN EL GATEWAY antes de firmar.
  // validate: payloadHistoricoReservas (espejo del wrapper; devuelve el payload NORMALIZADO
  // que se firma — fecha_desde clampeada al floor 2026-07-01, D-C-11/20). LECTURA: sin
  // injectActor, sin isWrite. Floor inferior duro; puede incluir futuras; NO liquidación ni
  // Carril B; NO reemplaza A04. El key DEBE coincidir con EXPECTED_ACTION del wrapper (D-C-41).
  'historico.reservas': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a24-historico-reservas', validate: payloadHistoricoReservas },
  // A25 (Slice 3a) — Caja percibida por periodo (ingresos cobrados). Wrapper n8n firmado
  // (portal-a25-ingresos). SOLO vicky/socio (D-C-27): jenny excluida, rebota con
  // rol_no_permitido EN EL GATEWAY antes de firmar. validate: payloadIngresosPeriodo, que
  // PRESERVA la ausencia de periodo_hasta (omitido NO va en value -> el wrapper defaultea a
  // hoy sin check de inversion; explicito -> YMD y, tras el clamp al floor, >= periodo_desde).
  // LECTURA: sin injectActor, sin isWrite. El key DEBE coincidir con EXPECTED_ACTION (D-C-41).
  'ingresos.cobrados_periodo': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a25-ingresos', validate: payloadIngresosPeriodo },
  // A07 (Slice 2) — Crear reserva manual. PRIMERA ESCRITURA vía gateway. Wrapper n8n
  // firmado (portal-a07-crear-reserva__TEST). SOLO vicky/socio (D-C-39): jenny rebota
  // con rol_no_permitido EN EL GATEWAY antes de firmar. validate: payloadCrearManual
  // (espejo del wrapper). injectActor: el actor (persona) se inyecta server-side desde
  // portal_usuarios.nombre, NUNCA del frontend. isWrite: ante dispatch no confiable se
  // devuelve estado_incierto (no error_entorno), porque la escritura pudo aplicarse.
  // El key DEBE coincidir con EXPECTED_ACTION del wrapper (action binding, D-C-41).
  'reserva.crear_manual': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a07-crear-reserva__TEST', validate: payloadCrearManual, injectActor: true, isWrite: true },
  // A08 (Slice 2) — Crear bloqueo manual. Wrapper n8n firmado
  // (portal-a08-crear-bloqueo__TEST). SOLO vicky/socio (D-C-39): jenny rebota con
  // rol_no_permitido EN EL GATEWAY antes de firmar. validate: payloadCrearBloqueo (espejo
  // del wrapper). injectActor: el actor (persona) se inyecta server-side desde
  // portal_usuarios.nombre y el wrapper lo usa como creado_por. isWrite: ante dispatch no
  // confiable, estado_incierto. id_cabana OBLIGATORIO (bloqueo total no se expone, 8D).
  // El key DEBE coincidir con EXPECTED_ACTION del wrapper (action binding, D-C-41).
  'bloqueo.crear_manual': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a08-crear-bloqueo__TEST', validate: payloadCrearBloqueo, injectActor: true, isWrite: true },
  // A10 (Slice 2) — Registrar pago de saldo. Wrapper n8n firmado
  // (portal-a10-registrar-saldo__TEST). SOLO vicky/socio (D-C-39): jenny rebota con
  // rol_no_permitido EN EL GATEWAY antes de firmar. validate: payloadRegistrarSaldo
  // (espejo del wrapper, capa de payload). injectActor: el actor (persona) se inyecta
  // server-side desde portal_usuarios.nombre y el wrapper lo usa como validado_por,
  // NUNCA del frontend. isWrite: ante dispatch no confiable, estado_incierto. El wrapper
  // mapea excede_saldo/idempotency_mismatch/estado_no_cobrable/saldo_ya_cancelado →
  // conflicto, reserva_no_existe → no_encontrado, P0001 → error_interno (D-C-51); todos
  // allowlisted. El key DEBE coincidir con EXPECTED_ACTION del wrapper (action binding, D-C-41).
  'cobranza.registrar_saldo': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a10-registrar-saldo__TEST', validate: payloadRegistrarSaldo, injectActor: true, isWrite: true },
  // A11 (Slice 3b) — Cargar gasto interno. PRIMERA ESCRITURA NO-IDEMPOTENTE del Carril C. Wrapper
  // n8n firmado (portal-a11-cargar-gasto-interno__TEST). SOLO vicky/socio (D-C-03): jenny rebota
  // con rol_no_permitido EN EL GATEWAY antes de firmar. validate: payloadCargarGastoInterno (espejo
  // del paso 10 del wrapper). injectActor: el actor (persona) se inyecta server-side desde
  // portal_usuarios.nombre y la función lo usa como creado_por, NUNCA del frontend. isWrite: ante
  // dispatch no confiable, estado_incierto. needsIdempotencyKey (D-C-57): el gateway exige y valida
  // idempotency_key (IDEM_RE_GW, sibling de payload), la firma top-level en el sobre y la pasa al
  // wrapper; éste deriva el nonce de la firma (D-C-56). El wrapper/función mapean nonce_replay/
  // payload_mismatch/actor_mismatch -> conflicto, constraint -> payload_invalido; todos allowlisted.
  // El key DEBE coincidir con EXPECTED_ACTION del wrapper (action binding, D-C-41).
  'cargar.gasto_interno': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a11-cargar-gasto-interno__TEST', validate: payloadCargarGastoInterno, injectActor: true, isWrite: true, needsIdempotencyKey: true },
};

const ROLES_VALIDOS: ReadonlySet<Rol> = new Set<Rol>(['jenny', 'vicky', 'socio']);

// D-C-57 / microcorrección: campos de control que el frontend NUNCA puede mandar TOP-LEVEL del
// request, para NINGUNA acción (defense-in-depth, fail-loud). actor/rol los inyecta el gateway
// desde el JWT; nonce/request_ts son server-side; source_event/creado_por los deriva la función.
// idempotency_key NO está acá: es sibling legítimo de payload (gobernado por needsIdempotencyKey).
// No afecta requests legítimos previos (que nunca traen estos campos) -> sus sobres quedan byte-idénticos.
const CONTROL_TOPLEVEL_PROHIBIDAS = ['actor', 'rol', 'nonce', 'source_event', 'creado_por', 'request_ts'];

// ---------------------------------------------------------------------------
// Envelope uniforme (D-C-18) + CORS.
// D-C-35: HTTP 200 + envelope para resultados manejados; 5xx solo para fallos inesperados.
// ---------------------------------------------------------------------------
const CORS: Record<string, string> = {
  // Slice 1: '*'. Restringir al origin del portal en la pasada de hardening (P-C-4).
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}
function ok(data: unknown): Response { return json(200, { ok: true, data }); }
function fail(code: string, message: string, detail: unknown = null): Response {
  return json(200, { ok: false, error: { code, message, detail } });
}
function crash(detail: unknown): Response {
  return json(500, { ok: false, error: { code: 'error_interno', message: 'error interno', detail } });
}

// ---------------------------------------------------------------------------
// Resolución defensiva de env vars (L-C-09). Soporta el sistema NUEVO de keys
// (SUPABASE_SECRET_KEYS, dict por nombre 'default') y la LEGACY (SUPABASE_SERVICE_ROLE_KEY).
// Falla RUIDOSO si falta algo; nunca silencioso.
// Slice 1 (D-C-37): suma VITA_AMBIENTE ∈ {test,ops} y N8N_BASE_URL al preflight duro.
//   - Preflight GLOBAL: si falta cualquiera de las dos, TODA acción (incluida
//     sesion.contexto, que no toca n8n) responde 5xx ruidoso. Es deliberado: un
//     gateway mal configurado no debe servir nada a medias.
// ---------------------------------------------------------------------------
function pickSecretByName(raw: string | undefined, name = 'default'): string | undefined {
  if (!raw) return undefined;
  try {
    const obj = JSON.parse(raw);
    // forma dict: { "default": "sb_secret_..." }
    if (obj && typeof obj === 'object' && !Array.isArray(obj) && typeof obj[name] === 'string') return obj[name];
    // forma array: [{ name, api_key|key|secret }]
    if (Array.isArray(obj)) {
      const hit = obj.find((k: { name?: string }) => k?.name === name) ?? obj[0];
      return hit?.api_key ?? hit?.key ?? hit?.secret ?? undefined;
    }
    // dict con un único valor string, sin 'default'
    const vals = Object.values(obj).filter((v) => typeof v === 'string') as string[];
    if (vals.length === 1) return vals[0];
  } catch {
    // raw no era JSON: podría ser ya la key plana
    if (raw.startsWith('sb_secret_') || raw.startsWith('ey')) return raw;
  }
  return undefined;
}

interface Env { url: string; secretKey: string; hmac: string; ambiente: string; n8nBaseUrl: string; }
function resolveEnv(): { env?: Env; missing: string[] } {
  const url = Deno.env.get('SUPABASE_URL');
  const secretKey = pickSecretByName(Deno.env.get('SUPABASE_SECRET_KEYS'))
    ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const hmac = Deno.env.get('VITA_HMAC_SECRET');
  const ambiente = Deno.env.get('VITA_AMBIENTE');
  const n8nBaseUrl = Deno.env.get('N8N_BASE_URL');

  const missing: string[] = [];
  if (!url) missing.push('SUPABASE_URL');
  if (!secretKey) missing.push('SUPABASE_SECRET_KEYS[default] | SUPABASE_SERVICE_ROLE_KEY');
  if (!hmac) missing.push('VITA_HMAC_SECRET');
  if (!ambiente) missing.push('VITA_AMBIENTE');
  else if (ambiente !== 'test' && ambiente !== 'ops') missing.push("VITA_AMBIENTE (valor inválido; debe ser 'test' u 'ops')");
  if (!n8nBaseUrl) missing.push('N8N_BASE_URL');

  if (missing.length) return { missing };
  return {
    env: {
      url: url as string,
      secretKey: secretKey as string,
      hmac: hmac as string,
      ambiente: ambiente as string,
      n8nBaseUrl: n8nBaseUrl as string,
    },
    missing: [],
  };
}

// ---------------------------------------------------------------------------
// HMAC (D-C-29): firma de los BYTES LITERALES del body. Exportadas para reuso/tests.
// ---------------------------------------------------------------------------
export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Construye el sobre firmado + la firma. Se firma EXACTAMENTE lo que se envía: el
// string `body` se transmite tal cual a n8n, y n8n recomputa el HMAC sobre su raw
// body (Webhook node con "Raw Body" ON, leído como binario — L-C-05). ts/nonce/
// ambiente_esperado van DENTRO del body firmado.
// D-C-57 (A11): `idempotencyKey` opcional. Cuando está presente, se emite `idempotency_key`
// TOP-LEVEL en el sobre (lo que el wrapper A11 lee de body.idempotency_key). Cuando es undefined
// (todas las acciones previas), el sobre queda BYTE-IDÉNTICO al actual (la clave no se agrega).
// D-C-56 sin cambios: el `nonce` genérico sigue siendo crypto.randomUUID() e INERTE para A11 (el
// wrapper deriva su propio nonce de la firma recomputada y nunca lee body.nonce).
export async function buildSignedEnvelope(
  hmacSecret: string,
  action: string,
  payload: unknown,
  rol: Rol,
  ambienteEsperado: string,
  actor?: string,
  idempotencyKey?: string,
): Promise<{ body: string; signatureHeader: string }> {
  const envelope: Record<string, unknown> = {
    action,
    payload,
    rol,
    ambiente_esperado: ambienteEsperado, // sale de VITA_AMBIENTE (D-C-37), nunca del payload del frontend
    ts: Date.now(),                       // epoch ms (D-C-29)
    nonce: crypto.randomUUID(),           // uuid  (D-C-29). INERTE para A11 (D-C-56).
  };
  // A07: el actor (persona) va DENTRO del sobre firmado, inyectado server-side. Solo se
  // agrega cuando la acción lo requiere (injectActor); los reads no lo incluyen.
  if (actor !== undefined) envelope.actor = actor;
  // D-C-57: idempotency_key top-level, solo si la acción lo provee (needsIdempotencyKey). Para
  // todo caller que no lo pase, la clave NO se agrega -> sobre byte-idéntico al previo.
  if (idempotencyKey !== undefined) envelope.idempotency_key = idempotencyKey;
  const body = JSON.stringify(envelope);
  const sig = await hmacSha256Hex(hmacSecret, body);
  return { body, signatureHeader: `sha256=${sig}` };
}

// ---------------------------------------------------------------------------
// Dispatch a n8n (D-C-36/37). Firma → POST → VALIDACIÓN ESTRICTA del envelope de
// vuelta → passthrough o error controlado. NUNCA filtra detalle interno (detail:null).
// Toda falla de backend es un resultado MANEJADO → HTTP 200 + envelope (D-C-35), no
// 5xx. Read-only: sin auto-retry (D-C-25); el frontend decide reintentar.
// ---------------------------------------------------------------------------
const N8N_TIMEOUT_MS = 10000;

// Códigos de error que un wrapper n8n tiene PERMITIDO propagar al frontend: los base
// de D-C-18 + los del patrón de revalidación Fase C. Cualquier otro código (p.ej. un
// SQLSTATE crudo de Postgres como '42P01') se trata como respuesta inválida del backend
// y se enmascara, para no filtrar errores crudos al navegador (D-C-18).
const CODIGOS_ERROR_PERMITIDOS: ReadonlySet<string> = new Set<string>([
  'payload_invalido', 'no_autorizado', 'rol_no_permitido', 'accion_desconocida',
  'no_encontrado', 'conflicto', 'error_entorno', 'error_interno', 'estado_incierto',
  'firma_invalida', 'ts_fuera_de_ventana', 'raw_body_ausente', 'ambiente_incorrecto',
]);

// Códigos de INFRAESTRUCTURA: el gateway IMPONE el message y nunca conserva el del
// wrapper. Son los más propensos a arrastrar texto crudo de Postgres / n8n / runtime,
// así que el gateway es la última barrera (no confía en el wrapper en estos casos).
// El resto de los códigos permitidos sí puede conservar su message curado (si es string).
// Texto fijo de estado_incierto (D-C aprobada): el gateway lo IMPONE tanto cuando el
// wrapper devuelve estado_incierto como cuando un dispatch de escritura no es confiable.
const MENSAJE_ESTADO_INCIERTO = 'no se pudo confirmar el estado de la operación; verificá la reserva antes de reintentar';

const MENSAJE_FIJO_POR_CODIGO: Record<string, string> = {
  error_entorno: 'respuesta inválida del backend',
  error_interno: 'error interno',
  estado_incierto: MENSAJE_ESTADO_INCIERTO,
};

// Valida la FORMA del envelope (no su semántica): ok boolean; en éxito, data presente;
// en error, error.code string no vacío. Rechaza cualquier otra cosa.
function esEnvelopeValido(x: unknown): x is { ok: boolean; data?: unknown; error?: { code: string; message?: unknown } } {
  if (typeof x !== 'object' || x === null || Array.isArray(x)) return false;
  const o = x as Record<string, unknown>;
  if (typeof o.ok !== 'boolean') return false;
  if (o.ok === true) return 'data' in o;
  const err = o.error;
  if (typeof err !== 'object' || err === null) return false;
  const code = (err as Record<string, unknown>).code;
  return typeof code === 'string' && code.length > 0;
}

async function dispatchN8n(
  env: Env,
  action: string,
  webhook: string,
  payload: unknown,
  rol: Rol,
  actor?: string,
  isWrite = false,
  idempotencyKey?: string,
): Promise<Response> {
  const { body, signatureHeader } = await buildSignedEnvelope(env.hmac, action, payload, rol, env.ambiente, actor, idempotencyKey);
  // Normaliza el join base/webhook (tolera trailing slash en N8N_BASE_URL y leading en webhook).
  const url = `${env.n8nBaseUrl.replace(/\/+$/, '')}/${webhook.replace(/^\/+/, '')}`;

  // Falla NO confiable del dispatch (timeout/red/HTTP/JSON/forma/código desconocido). En
  // ESCRITURA (isWrite) el estado puede ser desconocido tras enviar el request: se devuelve
  // estado_incierto con mensaje fijo y detail:null (ajuste A07). Sin auto-retry (D-C-25).
  const noConfiable = (lecturaMsg: string): Response =>
    isWrite ? fail('estado_incierto', MENSAJE_ESTADO_INCIERTO, null)
            : fail('error_entorno', lecturaMsg, null);

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), N8N_TIMEOUT_MS);
  let res: Response;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Vita-Signature': signatureHeader },
      body, // bytes exactos firmados; Deno fetch transmite el string como UTF-8 verbatim
      signal: ctrl.signal,
    });
  } catch (e) {
    console.error(`portal-api: fallo de red/timeout hacia n8n (${action}):`, e instanceof Error ? e.message : String(e));
    return noConfiable('el backend no respondió');
  } finally {
    clearTimeout(timer);
  }

  if (!res.ok) {
    console.error(`portal-api: n8n devolvió status ${res.status} en ${action}`);
    return noConfiable('respuesta inesperada del backend');
  }

  let parsed: unknown;
  try {
    parsed = await res.json();
  } catch {
    console.error(`portal-api: respuesta de n8n no es JSON (${action})`);
    return noConfiable('respuesta inválida del backend');
  }

  // 1) Forma del envelope.
  if (!esEnvelopeValido(parsed)) {
    console.error(`portal-api: envelope con forma inválida desde n8n (${action})`);
    return noConfiable('respuesta inválida del backend');
  }

  // 2) Éxito: se RECONSTRUYE el envelope desde data (descarta cualquier clave extra que
  // n8n pudiera agregar al tope; nunca se reenvía el objeto crudo).
  if (parsed.ok === true) {
    return ok(parsed.data);
  }

  // 3) Error: validación de SEMÁNTICA. Solo se propagan códigos de la allowlist; un
  // código crudo (SQLSTATE de Postgres, etc.) se enmascara como error_entorno para no
  // filtrar el error interno. Para los códigos de infraestructura (error_entorno/
  // error_interno) el gateway IMPONE el message; el resto conserva su message curado si
  // es string. detail:null siempre para errores que vienen de n8n en Slice 1 (D-C-18).
  const err = parsed.error ?? { code: '' };
  if (!CODIGOS_ERROR_PERMITIDOS.has(err.code)) {
    console.error(`portal-api: n8n devolvió código no permitido '${err.code}' en ${action}`);
    return noConfiable(MENSAJE_FIJO_POR_CODIGO.error_entorno);
  }
  const fijo = MENSAJE_FIJO_POR_CODIGO[err.code];
  if (fijo !== undefined) {
    // error_entorno / error_interno: message impuesto por el gateway (última barrera);
    // nunca se confía en el message del wrapper para errores de infraestructura.
    return fail(err.code, fijo, null);
  }
  const rawMsg = (err as { message?: unknown }).message;
  const message = typeof rawMsg === 'string' && rawMsg.length > 0 ? rawMsg : 'error en el backend';
  return fail(err.code, message, null);
}

// ---------------------------------------------------------------------------
// Handler. Orden D-C-18: JWT → lookup portal_usuarios → catálogo → allowlist →
// payload mínimo → dispatch.
// ---------------------------------------------------------------------------
Deno.serve(async (req: Request) => {
  try {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
    if (req.method !== 'POST') return fail('payload_invalido', 'método no soportado; usar POST');

    // Preflight de configuración (D-C-37): ruidoso, no silencioso. Global.
    const { env, missing } = resolveEnv();
    if (!env) {
      console.error('portal-api: env vars faltantes/inválidas:', missing.join(', '));
      return crash({ missing });
    }

    // Entrada { action, payload, idempotency_key? }. idempotency_key es SIBLING de payload (D-C-57),
    // legítimo solo para acciones con needsIdempotencyKey (A11); para el resto no se lee al sobre.
    let action: string;
    let payload: unknown;
    let idemRaw: unknown;
    try {
      const raw = await req.json();
      action = raw?.action;
      payload = raw?.payload ?? {};
      idemRaw = (raw && typeof raw === 'object') ? (raw as Record<string, unknown>).idempotency_key : undefined;
      if (typeof action !== 'string' || action.length === 0) {
        return fail('payload_invalido', 'falta "action"');
      }
      // Guard global (defense-in-depth): los campos de control NUNCA pueden venir TOP-LEVEL del
      // frontend, para ninguna acción. No afecta requests legítimos (no traen estos campos), así que
      // el sobre de acciones previas queda igual. idempotency_key NO está acá (sibling legítimo).
      if (raw && typeof raw === 'object') {
        for (const k of CONTROL_TOPLEVEL_PROHIBIDAS) {
          if (Object.prototype.hasOwnProperty.call(raw, k)) {
            return fail('payload_invalido', `campo de control no permitido en el request: ${k}`);
          }
        }
      }
    } catch {
      return fail('payload_invalido', 'body JSON inválido');
    }

    // JWT de Authorization: Bearer <jwt>.
    const authz = req.headers.get('Authorization') ?? '';
    const jwt = authz.toLowerCase().startsWith('bearer ') ? authz.slice(7).trim() : '';
    if (jwt.length === 0) return fail('no_autorizado', 'falta token de sesión');

    // Cliente admin server-side (secret key). Bypassa RLS y tiene SELECT en
    // portal_usuarios (D-C-34). La key vive SOLO acá, nunca en el navegador.
    const admin = createClient(env.url, env.secretKey, { auth: { persistSession: false } });

    // Validación de JWT vía getUser (D-C-30): firma + expiración + revocación.
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user) return fail('no_autorizado', 'sesión inválida o expirada');
    const uid = userData.user.id;

    // Lookup de identidad/rol (server-side).
    const { data: pu, error: puErr } = await admin
      .from('portal_usuarios')
      .select('nombre, rol, activo')
      .eq('user_id', uid)
      .maybeSingle();
    if (puErr) {
      console.error('portal-api: error leyendo portal_usuarios:', puErr.message);
      return crash('lookup');
    }
    if (!pu || pu.activo !== true) return fail('no_autorizado', 'usuario sin acceso al portal');

    const rol = pu.rol as Rol;
    if (!ROLES_VALIDOS.has(rol)) {
      console.error('portal-api: rol inesperado en fila:', rol);
      return crash('rol');
    }

    // Catálogo.
    const entry = CATALOG[action];
    if (!entry) return fail('accion_desconocida', `acción no reconocida: ${action}`);

    // Allowlist rol×action (D-C-15/39). El gateway impone; n8n revalida (segunda defensa).
    if (!entry.roles.includes(rol)) {
      return fail('rol_no_permitido', `rol ${rol} no habilitado para ${action}`);
    }

    // -------- Dispatch --------
    if (entry.handler === 'edge') {
      if (action === 'sesion.contexto') {
        // A02: se resuelve acá; NO toca n8n. acciones = lo permitido para el rol
        // (la base del menú). (payload se ignora; no requiere validación.)
        void payload;
        const acciones = Object.keys(CATALOG).filter((a) => CATALOG[a].roles.includes(rol));
        return ok({ nombre: pu.nombre, rol, acciones });
      }
      return crash(`acción edge sin dispatch: ${action}`);
    }

    // handler === 'n8n' (D-C-36): payload mínimo (D-C-18/39/40) → [actor] → [idempotency_key] → firma → ruteo.
    const v = entry.validate(payload);
    if (!v.ok) return fail('payload_invalido', v.message);
    // A07: inyección de actor server-side ANTES de firmar. El actor sale de
    // portal_usuarios.nombre (D-C-34), NUNCA del frontend, y debe ser coherente con el
    // rol (ajuste A07: vicky→vicky; socio→franco/rodrigo/remo). Si la fila no cuadra, NO
    // se firma hacia n8n: error conservador (inconsistencia de datos, no flujo normal).
    let actor: string | undefined;
    if (entry.injectActor) {
      if (!actorCoherente(rol, pu.nombre)) {
        console.error(`portal-api: actor incoherente con rol (rol=${rol}, nombre=${pu.nombre}) en ${action}`);
        return crash('actor_rol');
      }
      actor = pu.nombre;
    }
    // A11 (D-C-57): idempotency_key es SIBLING de payload (no va en el payload de negocio). El gateway
    // lo valida fail-fast (IDEM_RE_GW, misma regla que el wrapper, doble allowlist D-C-39) ANTES de
    // firmar, y lo pasa para que el sobre lo lleve top-level. Acciones sin needsIdempotencyKey -> undefined.
    let idempotencyKey: string | undefined;
    if (entry.needsIdempotencyKey) {
      if (typeof idemRaw === 'string' && IDEM_RE_GW.test(idemRaw)) {
        idempotencyKey = idemRaw;
      } else {
        return fail('payload_invalido', 'idempotency_key inválida (8-64 [A-Za-z0-9_-], sibling de payload)');
      }
    }
    return await dispatchN8n(env, action, entry.webhook, v.value, rol, actor, entry.isWrite === true, idempotencyKey);
  } catch (e) {
    console.error('portal-api: excepción no controlada:', e instanceof Error ? e.message : String(e));
    return crash('excepcion');
  }
});
