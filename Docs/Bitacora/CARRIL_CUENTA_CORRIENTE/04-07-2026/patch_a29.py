#!/usr/bin/env python3
# -*- coding: ascii -*-
# Patcher A28_TEST -> A29_TEST (portal-api). ADITIVO. Cada edicion: str_replace con
# assert count==1 (ancla unica). Al final: prueba de reversa GLOBAL (aplicar inversas
# y recuperar A28 byte-identico) => garantiza que no se toco nada mas.
import sys, io

SRC = "portal-api_A28_TEST_index.ts"
DST = "portal-api_A29_TEST_index.ts"

with io.open(SRC, "r", encoding="utf-8", newline="") as f:
    original = f.read()

PATCHES = []  # (label, old, new)

# --------------------------------------------------------------------------
# PATCH 0 - banner de provenance en el header (traza A29, naturaleza aditiva)
# --------------------------------------------------------------------------
PATCHES.append(("00_header_banner",
"""// ============================================================================

// jsr es el specifier actual de Supabase; "npm:@supabase/supabase-js@2" es equivalente.""",
"""// ============================================================================
//
// A29 (Cuenta corriente socios / RETIRO desde saldo vivo) -- derivado de A28_TEST por patcher.
//   Accion nueva 'cuenta_corriente.retirar' (ESCRITURA, socio-only) -> wrapper n8n portal-a29-retiro__TEST
//   -> portal_registrar_retiro(jsonb) (SB1). Cambios ADITIVOS: nuevo validator payloadRegistrarRetiro;
//   nuevo flag injectSocioIdentity (inyecta id_socio+user_id server-side, SOLO A29); id_socio/user_id
//   sumados a CONTROL_TOPLEVEL_PROHIBIDAS (rebotan payload_invalido si vienen del cliente); saldo_insuficiente
//   sumado al allowlist con detail SANITIZADO { saldo_disponible, monto_solicitado } (D-A29-3). Ninguna
//   accion previa cambia su sobre firmado (los flags nuevos quedan undefined para el resto).
// ============================================================================

// jsr es el specifier actual de Supabase; "npm:@supabase/supabase-js@2" es equivalente."""))

# --------------------------------------------------------------------------
# PATCH 1 - CatalogEntry: sumar injectSocioIdentity?: boolean a la variante n8n
# --------------------------------------------------------------------------
PATCHES.append(("01_catalogentry_flag",
"""  | { handler: 'n8n'; roles: Rol[]; webhook: string; validate: PayloadValidator; injectActor?: boolean; isWrite?: boolean; needsIdempotencyKey?: boolean };""",
"""  | { handler: 'n8n'; roles: Rol[]; webhook: string; validate: PayloadValidator; injectActor?: boolean; isWrite?: boolean; needsIdempotencyKey?: boolean; injectSocioIdentity?: boolean };"""))

# --------------------------------------------------------------------------
# PATCH 2 - insertar validator payloadRegistrarRetiro ANTES del comentario A13
#   (queda en la seccion de validadores, muy por encima del CATALOG; usa MAXLEN_GW ya definido)
# --------------------------------------------------------------------------
NEW_VALIDATOR = """// A29 (Cuenta corriente / RETIRO desde saldo vivo) -- cuenta_corriente.retirar (ESCRITURA, socio-only).
// ESPEJO de la capa de payload del wrapper portal-a29-retiro (validar_firma_ts_rol) y del contrato de
// portal_registrar_retiro (SB1): reject-control + whitelist (monto, medio_pago, comentario) + reject-unknown.
// monto es STRING por precision de plata (D-A29-1): regex ^[0-9]{1,12}(\\.[0-9]{1,2})?$ (<=12 enteros, <=2
// decimales, sin signo) y > 0; viaja como string y la funcion lo valida textualmente igual (doble allowlist,
// D-C-39) -> sin floats en el camino. medio_pago MVP {efectivo, transferencia_bancaria}. comentario opcional:
// trim + '' -> null (ajuste obligatorio 3; nunca rebota recien por constraint SQL). Los campos de control
// (actor/rol/nonce/source_event/creado_por/request_ts/idempotency_key/id_socio/user_id) se RECHAZAN en payload
// (fail-fast); el reject-unknown igual los bouncearia. id_socio/user_id ademas los inyecta el gateway server-side
// (injectSocioIdentity), NUNCA el cliente. Devuelve el payload whitelisteado { monto, medio_pago, comentario }.
const CONTROL_EN_PAYLOAD_A29 = ['actor', 'rol', 'nonce', 'source_event', 'creado_por', 'request_ts', 'idempotency_key', 'id_socio', 'user_id'];
const MEDIOS_RETIRO_GW = ['efectivo', 'transferencia_bancaria'];
const MONTO_RETIRO_RE_GW = /^[0-9]{1,12}(\\.[0-9]{1,2})?$/;
export const payloadRegistrarRetiro: PayloadValidator = (payload) => {
  const bad = (message: string): PayloadValidation => ({ ok: false, message });
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return bad('payload invalido: se esperaba un objeto');
  const p = payload as Record<string, unknown>;
  // Rechazo explicito de control en payload (fail-fast); el reject-unknown de abajo igual los bouncearia.
  for (const k of CONTROL_EN_PAYLOAD_A29) if (k in p) return bad(`campo de control no permitido en payload: ${k}`);
  const PERMITIDAS = ['monto', 'medio_pago', 'comentario'];
  for (const k of Object.keys(p)) if (!PERMITIDAS.includes(k)) return bad(`clave no permitida en payload: ${k}`);

  // monto STRING (D-A29-1): <=12 enteros, <=2 decimales, > 0. Espejo textual del wrapper SQL.
  if (typeof p.monto !== 'string' || !MONTO_RETIRO_RE_GW.test(p.monto) || Number(p.monto) <= 0) {
    return bad('monto invalido: string entero o con hasta 2 decimales (max 12 enteros), > 0');
  }
  if (typeof p.medio_pago !== 'string' || !MEDIOS_RETIRO_GW.includes(p.medio_pago)) {
    return bad('medio_pago invalido (efectivo | transferencia_bancaria)');
  }
  if (p.comentario != null && (typeof p.comentario !== 'string' || (p.comentario as string).length > MAXLEN_GW)) {
    return bad('comentario invalido');
  }

  // comentario: trim + '' -> null (ajuste 3). Nunca se deja rebotar por constraint SQL.
  const comentarioTrim = (p.comentario != null ? (p.comentario as string).trim() : '');
  const value = {
    monto: p.monto,
    medio_pago: p.medio_pago,
    comentario: (comentarioTrim !== '' ? comentarioTrim : null),
  };
  return { ok: true, value };
};

"""
PATCHES.append(("02_validator_insert",
"""// A13 (Slice 3b) -- gastos.listado (gastos internos por periodo contable, LECTURA; companion de A11).""",
NEW_VALIDATOR + """// A13 (Slice 3b) -- gastos.listado (gastos internos por periodo contable, LECTURA; companion de A11)."""))

# --------------------------------------------------------------------------
# PATCH 3 - entrada A29 en el CATALOG (despues de cobranza.registrar_cobro, antes del cierre })
# --------------------------------------------------------------------------
PATCHES.append(("03_catalog_entry",
"""  'cobranza.registrar_cobro': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a10mp-registrar-cobro__TEST', validate: payloadRegistrarCobro, injectActor: true, isWrite: true },
};""",
"""  'cobranza.registrar_cobro': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a10mp-registrar-cobro__TEST', validate: payloadRegistrarCobro, injectActor: true, isWrite: true },

  // A29 (Cuenta corriente socios / RETIRO desde saldo vivo) -- cuenta_corriente.retirar (ESCRITURA, socio-only).
  // Wrapper n8n firmado (portal-a29-retiro__TEST) -> portal_registrar_retiro(jsonb) (SB1). SOLO socio: vicky/jenny
  // rebotan rol_no_permitido EN EL GATEWAY antes de firmar. validate: payloadRegistrarRetiro (espejo del wrapper +
  // contrato SQL). injectActor: actor=persona server-side (portal_usuarios.nombre). injectSocioIdentity (NUEVO):
  // inyecta id_socio (portal_usuarios.id_socio, FK SB0) + user_id (uid del JWT) server-side; el cliente NO puede
  // mandarlos. isWrite: ante dispatch no confiable, estado_incierto. needsIdempotencyKey (D-C-57): key sibling
  // exigida/validada (IDEM_RE_GW) y top-level en el sobre. saldo_insuficiente/conflicto/payload_invalido los mapea
  // el wrapper SQL; todos allowlisted. El key DEBE coincidir con EXPECTED_ACTION del wrapper (D-C-41).
  'cuenta_corriente.retirar': { handler: 'n8n', roles: ['socio'], webhook: 'portal-a29-retiro__TEST', validate: payloadRegistrarRetiro, injectActor: true, injectSocioIdentity: true, isWrite: true, needsIdempotencyKey: true },
};"""))

# --------------------------------------------------------------------------
# PATCH 4 - CONTROL_TOPLEVEL_PROHIBIDAS: sumar id_socio, user_id (+ nota en comentario)
# --------------------------------------------------------------------------
PATCHES.append(("04_control_toplevel",
"""// idempotency_key NO est\u00e1 ac\u00e1: es sibling leg\u00edtimo de payload (gobernado por needsIdempotencyKey).
// No afecta requests leg\u00edtimos previos (que nunca traen estos campos) -> sus sobres quedan byte-id\u00e9nticos.
const CONTROL_TOPLEVEL_PROHIBIDAS = ['actor', 'rol', 'nonce', 'source_event', 'creado_por', 'request_ts'];""",
"""// idempotency_key NO est\u00e1 ac\u00e1: es sibling leg\u00edtimo de payload (gobernado por needsIdempotencyKey).
// A29: id_socio/user_id se suman ac\u00e1 -- los inyecta el gateway (injectSocioIdentity); un cliente que los
// mande TOP-LEVEL rebota payload_invalido. (Dentro de payload los rechaza cada validator; ver A29.)
// No afecta requests leg\u00edtimos previos (que nunca traen estos campos) -> sus sobres quedan byte-id\u00e9nticos.
const CONTROL_TOPLEVEL_PROHIBIDAS = ['actor', 'rol', 'nonce', 'source_event', 'creado_por', 'request_ts', 'id_socio', 'user_id'];"""))

# --------------------------------------------------------------------------
# PATCH 5a - buildSignedEnvelope: sumar params idSocio?/userId?
# --------------------------------------------------------------------------
PATCHES.append(("05a_bse_signature",
"""  ambienteEsperado: string,
  actor?: string,
  idempotencyKey?: string,
): Promise<{ body: string; signatureHeader: string }> {""",
"""  ambienteEsperado: string,
  actor?: string,
  idempotencyKey?: string,
  idSocio?: number,
  userId?: string,
): Promise<{ body: string; signatureHeader: string }> {"""))

# --------------------------------------------------------------------------
# PATCH 5b - buildSignedEnvelope: inyeccion de id_socio/user_id (analogo a actor)
# --------------------------------------------------------------------------
PATCHES.append(("05b_bse_injection",
"""  if (idempotencyKey !== undefined) envelope.idempotency_key = idempotencyKey;
  const body = JSON.stringify(envelope);""",
"""  if (idempotencyKey !== undefined) envelope.idempotency_key = idempotencyKey;
  // A29 (injectSocioIdentity): id_socio + user_id inyectados server-side, top-level en el sobre firmado
  // (el wrapper portal-a29-retiro los lee de body.id_socio/body.user_id). Solo A29 los pasa; para toda
  // otra accion quedan undefined -> el sobre NO los agrega -> byte-identico al previo.
  if (idSocio !== undefined) envelope.id_socio = idSocio;
  if (userId !== undefined) envelope.user_id = userId;
  const body = JSON.stringify(envelope);"""))

# --------------------------------------------------------------------------
# PATCH 6 - CODIGOS_ERROR_PERMITIDOS: sumar saldo_insuficiente
# --------------------------------------------------------------------------
PATCHES.append(("06_error_allowlist",
"""  'firma_invalida', 'ts_fuera_de_ventana', 'raw_body_ausente', 'ambiente_incorrecto',
]);""",
"""  'firma_invalida', 'ts_fuera_de_ventana', 'raw_body_ausente', 'ambiente_incorrecto',
  'saldo_insuficiente',
]);"""))

# --------------------------------------------------------------------------
# PATCH 7 - dispatchN8n: sumar params idSocio?/userId? y pasarlos a buildSignedEnvelope
# --------------------------------------------------------------------------
PATCHES.append(("07_dispatch_signature",
"""  actor?: string,
  isWrite = false,
  idempotencyKey?: string,
): Promise<Response> {
  const { body, signatureHeader } = await buildSignedEnvelope(env.hmac, action, payload, rol, env.ambiente, actor, idempotencyKey);""",
"""  actor?: string,
  isWrite = false,
  idempotencyKey?: string,
  idSocio?: number,
  userId?: string,
): Promise<Response> {
  const { body, signatureHeader } = await buildSignedEnvelope(env.hmac, action, payload, rol, env.ambiente, actor, idempotencyKey, idSocio, userId);"""))

# --------------------------------------------------------------------------
# PATCH 8 - dispatchN8n: excepcion acotada de detail para saldo_insuficiente (D-A29-3)
# --------------------------------------------------------------------------
PATCHES.append(("08_detail_exception",
"""  const rawMsg = (err as { message?: unknown }).message;
  const message = typeof rawMsg === 'string' && rawMsg.length > 0 ? rawMsg : 'error en el backend';
  return fail(err.code, message, null);
}""",
"""  const rawMsg = (err as { message?: unknown }).message;
  const message = typeof rawMsg === 'string' && rawMsg.length > 0 ? rawMsg : 'error en el backend';
  // A29 (D-A29-3): UNICA excepcion al detail:null. Para saldo_insuficiente se propaga un detail SANITIZADO
  // con SOLO { saldo_disponible, monto_solicitado }, y solo si AMBOS son numeros finitos (reconstruido,
  // nunca el detail crudo del wrapper). Cualquier otra forma -> detail:null. El resto de los codigos sigue
  // con detail:null (no se filtra nada interno).
  if (err.code === 'saldo_insuficiente') {
    const d = (err as { detail?: unknown }).detail;
    if (d && typeof d === 'object' && !Array.isArray(d)) {
      const sd = (d as Record<string, unknown>).saldo_disponible;
      const ms = (d as Record<string, unknown>).monto_solicitado;
      if (typeof sd === 'number' && Number.isFinite(sd) && typeof ms === 'number' && Number.isFinite(ms)) {
        return fail(err.code, message, { saldo_disponible: sd, monto_solicitado: ms });
      }
    }
    return fail(err.code, message, null);
  }
  return fail(err.code, message, null);
}"""))

# --------------------------------------------------------------------------
# PATCH 9 - lookup portal_usuarios: sumar id_socio al select
# --------------------------------------------------------------------------
PATCHES.append(("09_select_id_socio",
"""      .select('nombre, rol, activo')
      .eq('user_id', uid)""",
"""      .select('nombre, rol, activo, id_socio')
      .eq('user_id', uid)"""))

# --------------------------------------------------------------------------
# PATCH 10 - handler: derivar idSocio/userId (injectSocioIdentity) y pasarlos al dispatch
# --------------------------------------------------------------------------
PATCHES.append(("10_handler_inject",
"""        return fail('payload_invalido', 'idempotency_key inv\u00e1lida (8-64 [A-Za-z0-9_-], sibling de payload)');
      }
    }
    return await dispatchN8n(env, action, entry.webhook, v.value, rol, actor, entry.isWrite === true, idempotencyKey);""",
"""        return fail('payload_invalido', 'idempotency_key inv\u00e1lida (8-64 [A-Za-z0-9_-], sibling de payload)');
      }
    }
    // A29 (injectSocioIdentity): identidad de socio inyectada server-side ANTES de firmar. id_socio sale de
    // portal_usuarios.id_socio (FK SB0) y user_id del JWT (uid) -- NUNCA del cliente. Un socio post-SB0 SIEMPRE
    // tiene id_socio (CHECK chk_portal_usuarios_socio_rol); si faltara, es inconsistencia de datos y NO se firma
    // (fail-closed, como actorCoherente). Solo A29 setea el flag -> el resto de las acciones queda sin cambios.
    let idSocio: number | undefined;
    let userId: string | undefined;
    if (entry.injectSocioIdentity) {
      if (pu.id_socio == null) {
        console.error(`portal-api: socio sin id_socio (rol=${rol}, nombre=${pu.nombre}) en ${action}`);
        return crash('id_socio_ausente');
      }
      idSocio = pu.id_socio as number;
      userId = uid;
    }
    return await dispatchN8n(env, action, entry.webhook, v.value, rol, actor, entry.isWrite === true, idempotencyKey, idSocio, userId);"""))

# ==========================================================================
# Aplicacion con assert count==1
# ==========================================================================
text = original
applied = []
for label, old, new in PATCHES:
    n = text.count(old)
    if n != 1:
        sys.stderr.write("FALLO ancla '%s': count=%d (esperado 1)\n" % (label, n))
        # ayuda a diagnosticar
        head = old.splitlines()[0] if old.splitlines() else old[:60]
        sys.stderr.write("  primera linea del ancla: %r\n" % head)
        sys.exit(2)
    text = text.replace(old, new, 1)
    applied.append((label, old, new))
    print("OK  %-22s count==1 aplicado" % label)

# ==========================================================================
# Prueba de reversa GLOBAL: aplicar las inversas (new->old) en orden inverso
# y confirmar que se recupera A28 byte-identico. Garantiza cero cambios colaterales.
# ==========================================================================
rev = text
for label, old, new in reversed(applied):
    m = rev.count(new)
    if m != 1:
        sys.stderr.write("FALLO reversa '%s': count(new)=%d (esperado 1)\n" % (label, m))
        sys.exit(3)
    rev = rev.replace(new, old, 1)

if rev != original:
    sys.stderr.write("FALLO prueba de reversa: A28 reconstruido NO es byte-identico al original\n")
    sys.exit(4)
print("OK  prueba de reversa GLOBAL: A28 reconstruido byte-identico (cero cambios colaterales)")

with io.open(DST, "w", encoding="utf-8", newline="") as f:
    f.write(text)

# Reporte
print("---")
print("origen  : %s (%d lineas)" % (SRC, original.count(chr(10)) + 1))
print("destino : %s (%d lineas)" % (DST, text.count(chr(10)) + 1))
print("delta   : +%d lineas" % (text.count(chr(10)) - original.count(chr(10))))
print("patches : %d aplicados, todos count==1, reversa OK" % len(applied))
