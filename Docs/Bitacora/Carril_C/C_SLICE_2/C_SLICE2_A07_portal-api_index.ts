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
  | { handler: 'n8n'; roles: Rol[]; webhook: string; validate: PayloadValidator; injectActor?: boolean; isWrite?: boolean };

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
  // A07 (Slice 2) — Crear reserva manual. PRIMERA ESCRITURA vía gateway. Wrapper n8n
  // firmado (portal-a07-crear-reserva__TEST). SOLO vicky/socio (D-C-39): jenny rebota
  // con rol_no_permitido EN EL GATEWAY antes de firmar. validate: payloadCrearManual
  // (espejo del wrapper). injectActor: el actor (persona) se inyecta server-side desde
  // portal_usuarios.nombre, NUNCA del frontend. isWrite: ante dispatch no confiable se
  // devuelve estado_incierto (no error_entorno), porque la escritura pudo aplicarse.
  // El key DEBE coincidir con EXPECTED_ACTION del wrapper (action binding, D-C-41).
  'reserva.crear_manual': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a07-crear-reserva__TEST', validate: payloadCrearManual, injectActor: true, isWrite: true },
};

const ROLES_VALIDOS: ReadonlySet<Rol> = new Set<Rol>(['jenny', 'vicky', 'socio']);

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
export async function buildSignedEnvelope(
  hmacSecret: string,
  action: string,
  payload: unknown,
  rol: Rol,
  ambienteEsperado: string,
  actor?: string,
): Promise<{ body: string; signatureHeader: string }> {
  const envelope: Record<string, unknown> = {
    action,
    payload,
    rol,
    ambiente_esperado: ambienteEsperado, // sale de VITA_AMBIENTE (D-C-37), nunca del payload del frontend
    ts: Date.now(),                       // epoch ms (D-C-29)
    nonce: crypto.randomUUID(),           // uuid  (D-C-29)
  };
  // A07: el actor (persona) va DENTRO del sobre firmado, inyectado server-side. Solo se
  // agrega cuando la acción lo requiere (injectActor); los reads no lo incluyen.
  if (actor !== undefined) envelope.actor = actor;
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
): Promise<Response> {
  const { body, signatureHeader } = await buildSignedEnvelope(env.hmac, action, payload, rol, env.ambiente, actor);
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

    // Entrada { action, payload }.
    let action: string;
    let payload: unknown;
    try {
      const raw = await req.json();
      action = raw?.action;
      payload = raw?.payload ?? {};
      if (typeof action !== 'string' || action.length === 0) {
        return fail('payload_invalido', 'falta "action"');
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

    // handler === 'n8n' (D-C-36): payload mínimo (D-C-18/39/40) → [actor] → firma → ruteo.
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
    return await dispatchN8n(env, action, entry.webhook, v.value, rol, actor, entry.isWrite === true);
  } catch (e) {
    console.error('portal-api: excepción no controlada:', e instanceof Error ? e.message : String(e));
    return crash('excepcion');
  }
});
