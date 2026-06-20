#!/usr/bin/env python3
# Extiende el gateway A07 (portal-api) con A08: constante ENUM_MOTIVO_GW, validador
# payloadCrearBloqueo (espejo del wrapper) y entrada de CATALOG 'bloqueo.crear_manual'.
# Reusa toda la infra A07 (buildSignedEnvelope con actor, dispatchN8n isWrite->estado_incierto,
# actorCoherente). 3 inserciones quirurgicas, count==1, LF preservado.
SRC = '/home/claude/gw/C_SLICE2_A07_portal-api_index.ts'
OUT = '/home/claude/gw/C_SLICE2_A08_portal-api_index.ts'

s = open(SRC, 'r', encoding='utf-8', newline='').read()
assert '\r\n' not in s, 'esperaba LF puro'

def replace_once(text, anchor, replacement, label):
    n = text.count(anchor)
    assert n == 1, f'[{label}] anchor aparece {n} veces (esperaba 1)'
    return text.replace(anchor, replacement)

# --- 1) Constante ENUM_MOTIVO_GW, junto a las demas constantes GW ---
anchor1 = "const MAXLEN_GW = 1000;\n"
repl1 = ("const MAXLEN_GW = 1000;\n"
         "const ENUM_MOTIVO_GW = ['mantenimiento', 'uso_propio', 'tormenta', 'overbooking', 'otro'];\n")
s = replace_once(s, anchor1, repl1, 'const ENUM_MOTIVO_GW')

# --- 2) Validador payloadCrearBloqueo, justo despues de payloadCrearManual ---
anchor2 = (
"    huesped: { nombre: (hh.nombre as string).trim(), telefono: telVal, email: emaVal },\n"
"  };\n"
"  return { ok: true, value };\n"
"};\n"
)
validador_a08 = (
"    huesped: { nombre: (hh.nombre as string).trim(), telefono: telVal, email: emaVal },\n"
"  };\n"
"  return { ok: true, value };\n"
"};\n"
"\n"
"// A08 (Slice 2) — Validador del payload de creación manual de bloqueo. ESPEJO EXACTO\n"
"// del wrapper (validar_firma_ts_rol A08): reject-unknown, id_cabana OBLIGATORIO (entero\n"
"// positivo; bloqueo total NO se expone en el portal, decisión 8D), fechas YMD reales con\n"
"// hasta > desde, motivo en enum, descripción opcional. `actor` NO es clave del payload:\n"
"// viaja en el sobre, inyectado server-side, y el wrapper lo usa como creado_por.\n"
"export const payloadCrearBloqueo: PayloadValidator = (payload) => {\n"
"  const bad = (message: string): PayloadValidation => ({ ok: false, message });\n"
"  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return bad('payload inválido: se esperaba un objeto');\n"
"  const p = payload as Record<string, unknown>;\n"
"  const PERMITIDAS = ['id_cabana', 'fecha_desde', 'fecha_hasta', 'motivo', 'descripcion'];\n"
"  for (const k of Object.keys(p)) if (!PERMITIDAS.includes(k)) return bad(`clave no permitida en payload: ${k}`);\n"
"  const isStr = (v: unknown): v is string => typeof v === 'string';\n"
"  const okLen = (v: string) => v.length <= MAXLEN_GW;\n"
"\n"
"  if (typeof p.id_cabana !== 'number' || !Number.isSafeInteger(p.id_cabana) || p.id_cabana <= 0) return bad('id_cabana debe ser entero positivo (bloqueo total no se expone)');\n"
"  if (!isYMD_GW(p.fecha_desde) || !isYMD_GW(p.fecha_hasta)) return bad('fecha_desde/fecha_hasta deben ser YYYY-MM-DD válidas');\n"
"  if (!(p.fecha_desde < p.fecha_hasta)) return bad('fecha_hasta debe ser posterior a fecha_desde');\n"
"  if (!ENUM_MOTIVO_GW.includes(p.motivo as string)) return bad('motivo inválido');\n"
"  if (p.descripcion !== undefined && p.descripcion !== null && (!isStr(p.descripcion) || !okLen(p.descripcion))) return bad('descripcion inválida');\n"
"\n"
"  const value = {\n"
"    id_cabana: p.id_cabana, fecha_desde: p.fecha_desde, fecha_hasta: p.fecha_hasta,\n"
"    motivo: p.motivo, descripcion: (p.descripcion != null ? p.descripcion : null),\n"
"  };\n"
"  return { ok: true, value };\n"
"};\n"
)
s = replace_once(s, anchor2, validador_a08, 'payloadCrearBloqueo')

# --- 3) Entrada de CATALOG 'bloqueo.crear_manual', despues de la de A07 ---
anchor3 = "  'reserva.crear_manual': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a07-crear-reserva__TEST', validate: payloadCrearManual, injectActor: true, isWrite: true },\n"
repl3 = (
anchor3 +
"  // A08 (Slice 2) — Crear bloqueo manual. Wrapper n8n firmado\n"
"  // (portal-a08-crear-bloqueo__TEST). SOLO vicky/socio (D-C-39): jenny rebota con\n"
"  // rol_no_permitido EN EL GATEWAY antes de firmar. validate: payloadCrearBloqueo (espejo\n"
"  // del wrapper). injectActor: el actor (persona) se inyecta server-side desde\n"
"  // portal_usuarios.nombre y el wrapper lo usa como creado_por. isWrite: ante dispatch no\n"
"  // confiable, estado_incierto. id_cabana OBLIGATORIO (bloqueo total no se expone, 8D).\n"
"  // El key DEBE coincidir con EXPECTED_ACTION del wrapper (action binding, D-C-41).\n"
"  'bloqueo.crear_manual': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a08-crear-bloqueo__TEST', validate: payloadCrearBloqueo, injectActor: true, isWrite: true },\n"
)
s = replace_once(s, anchor3, repl3, 'CATALOG bloqueo.crear_manual')

assert '\r\n' not in s, 'se introdujo CRLF'
open(OUT, 'w', encoding='utf-8', newline='').write(s)

# Asserts de contenido
assert s.count('payloadCrearBloqueo') == 3, 'payloadCrearBloqueo deberia aparecer 3x (decl export, CATALOG, +1 en comentario? revisar)'
assert "'bloqueo.crear_manual':" in s
assert "ENUM_MOTIVO_GW" in s
print('OK: gateway A08 generado')
print('lineas:', s.count(chr(10)))
print('payloadCrearBloqueo apariciones:', s.count('payloadCrearBloqueo'))
