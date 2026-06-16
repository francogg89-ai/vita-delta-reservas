// supabase/functions/portal-api/index.ts
// ============================================================================
// Carril C / Portal Operativo Interno — Edge Function "portal-api" (gateway/BFF).
// Slice 0, Fase B. Frontera de confianza del portal.
//
// Decisiones:
//   D-C-13 (Edge Fn = frontera de confianza), D-C-14 (identidad por portal_usuarios),
//   D-C-15 (gateway único action+payload + revalidación n8n), D-C-18 (error envelope
//   uniforme), D-C-22 (nombre = persona), D-C-29 (HMAC-SHA256 sobre bytes literales
//   del body), D-C-30 (JWT vía getUser), D-C-31 (allowlist constante versionada),
//   D-C-34 (portal_usuarios solo server-side), D-C-35 (HTTP 200 + envelope para
//   resultados manejados; 5xx solo para fallos inesperados).
//
// IMPORTANTE — verify_jwt = false (en config.toml): la validación del JWT se hace
// EN el handler con getUser, para devolver SIEMPRE el envelope uniforme, incluso si
// el JWT falta / es inválido / está expirado. (Doblemente requerido por la migración
// de API keys de Supabase: con las keys nuevas hay que autorizar en código.)
//
// Slice 0 solo cablea sesion.contexto (A02): se resuelve íntegro acá y NO toca n8n.
// El helper de firma HMAC queda listo; el ruteo real a n8n se ejercita en Fase C.
// ============================================================================

// jsr es el specifier actual de Supabase; "npm:@supabase/supabase-js@2" es equivalente.
import { createClient } from 'jsr:@supabase/supabase-js@2';

// ---------------------------------------------------------------------------
// Catálogo / allowlist versionada (D-C-31).
// Una acción aparece acá SOLO cuando está wired/implementada. Slice 0: sesion.contexto.
// Para crecer: agregar entrada { roles, handler } por acción, junto con su dispatch.
// ---------------------------------------------------------------------------
type Rol = 'jenny' | 'vicky' | 'socio';
type Handler = 'edge' | 'n8n';

const CATALOG: Record<string, { roles: Rol[]; handler: Handler }> = {
  'sesion.contexto': { roles: ['jenny', 'vicky', 'socio'], handler: 'edge' },
};

const ROLES_VALIDOS: ReadonlySet<Rol> = new Set<Rol>(['jenny', 'vicky', 'socio']);

// ---------------------------------------------------------------------------
// Envelope uniforme (D-C-18) + CORS.
// D-C-35: HTTP 200 + envelope para resultados manejados; 5xx solo para fallos inesperados.
// ---------------------------------------------------------------------------
const CORS: Record<string, string> = {
  // Slice 0: '*'. Restringir al origin del portal en la pasada de hardening (P-C-4).
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
// Resolución defensiva de env vars (Condición B). Soporta el sistema NUEVO de keys
// (SUPABASE_SECRET_KEYS, dict por nombre 'default') y la LEGACY (SUPABASE_SERVICE_ROLE_KEY).
// Falla RUIDOSO si falta algo; nunca silencioso.
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

interface Env { url: string; secretKey: string; hmac: string; }
function resolveEnv(): { env?: Env; missing: string[] } {
  const url = Deno.env.get('SUPABASE_URL');
  const secretKey = pickSecretByName(Deno.env.get('SUPABASE_SECRET_KEYS'))
    ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const hmac = Deno.env.get('VITA_HMAC_SECRET');
  const missing: string[] = [];
  if (!url) missing.push('SUPABASE_URL');
  if (!secretKey) missing.push('SUPABASE_SECRET_KEYS[default] | SUPABASE_SERVICE_ROLE_KEY');
  if (!hmac) missing.push('VITA_HMAC_SECRET');
  if (missing.length) return { missing };
  return { env: { url: url as string, secretKey: secretKey as string, hmac: hmac as string }, missing: [] };
}

// ---------------------------------------------------------------------------
// HMAC (D-C-29): firma de los BYTES LITERALES del body. Listo para Fase C.
// Slice 0 NO lo ejercita (sesion.contexto no toca n8n). Exportadas para reuso/tests.
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

// Construye el sobre firmado + la firma. Se firma EXACTAMENTE lo que se envía:
// el string `body` se transmite tal cual a n8n, y n8n recomputa el HMAC sobre su
// raw body (Webhook node con "Raw Body" ON). ts/nonce/ambiente_esperado van DENTRO.
export async function buildSignedEnvelope(
  hmacSecret: string,
  action: string,
  payload: unknown,
  rol: Rol,
  ambienteEsperado: string,
): Promise<{ body: string; signatureHeader: string }> {
  const body = JSON.stringify({
    action,
    payload,
    rol,
    ambiente_esperado: ambienteEsperado,
    ts: Date.now(),               // epoch ms (D-C-29)
    nonce: crypto.randomUUID(),   // uuid  (D-C-29)
  });
  const sig = await hmacSha256Hex(hmacSecret, body);
  return { body, signatureHeader: `sha256=${sig}` };
}

// ---------------------------------------------------------------------------
// Handler. Orden D-C-18: JWT → lookup portal_usuarios → catálogo → allowlist →
// payload mínimo → dispatch.
// ---------------------------------------------------------------------------
Deno.serve(async (req: Request) => {
  try {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
    if (req.method !== 'POST') return fail('payload_invalido', 'método no soportado; usar POST');

    // Preflight de configuración (Condición B): ruidoso, no silencioso.
    const { env, missing } = resolveEnv();
    if (!env) {
      console.error('portal-api: faltan env vars:', missing.join(', '));
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

    // Allowlist rol×action (D-C-15/18). El gateway impone; n8n revalida (Fase C+).
    if (!entry.roles.includes(rol)) {
      return fail('rol_no_permitido', `rol ${rol} no habilitado para ${action}`);
    }

    // -------- Dispatch --------
    if (action === 'sesion.contexto') {
      // A02: se resuelve acá; NO toca n8n. acciones = lo permitido para el rol
      // (la base del menú). (payload se ignora; no requiere validación.)
      void payload;
      const acciones = Object.keys(CATALOG).filter((a) => CATALOG[a].roles.includes(rol));
      return ok({ nombre: pu.nombre, rol, acciones });
    }

    // Acciones backend (handler:'n8n') se cablean desde Slice 1+ con
    // buildSignedEnvelope() y el ruteo HMAC. En Slice 0 ninguna lo es.
    return crash(`accion sin dispatch en Slice 0: ${action}`);
  } catch (e) {
    console.error('portal-api: excepción no controlada:', e instanceof Error ? e.message : String(e));
    return crash('excepcion');
  }
});