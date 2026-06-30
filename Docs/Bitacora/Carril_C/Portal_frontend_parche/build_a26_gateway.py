#!/usr/bin/env python3
# build_a26_gateway.py
# Bloque B (Carril C) - Expone A26 disponibilidad.cabana en el CATALOG del portal-api (TEST).
#
# Base: index.ts TEST ACTUAL (A10MP_B2_portal-api_index.ts; 13 acciones n8n, sin __OPS).
# Inserta EXACTAMENTE dos cosas, con diff minimo y anclado (count==1):
#   1) el validador payloadDisponibilidadCabana (ESPEJO del wrapper portal-a26-disponibilidad;
#      reusa el helper isYMD_GW ya existente), justo antes de `const CATALOG`;
#   2) la entrada CATALOG 'disponibilidad.cabana' (LECTURA pura: sin injectActor, sin isWrite,
#      sin needsIdempotencyKey; webhook SIN sufijo = convencion de lecturas A05/A12/A24/A25),
#      justo despues de la ultima lectura ('gastos.listado'), antes de las escrituras.
#
# NO toca: dispatchN8n, auth/JWT, CORS, env, ni ninguna otra accion. NO toca OPS, frontend,
# A07/A08, SQL ni canonico. Salida: portal-api_A26_TEST_index.ts.
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else 'portal-api_TEST_base.ts'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'portal-api_A26_TEST_index.ts'

with open(SRC, 'r', encoding='utf-8') as f:
    s = f.read()

# ---------------------------------------------------------------------------
# 1) Validador (espejo EXACTO de la validacion de negocio del wrapper Bloque A).
# ---------------------------------------------------------------------------
VALIDATOR = (
    "// A26 (Bloque B) -- disponibilidad.cabana (LECTURA pura, guardrail UX de A07/A08). ESPEJO\n"
    "// EXACTO de la validacion de negocio del wrapper portal-a26-disponibilidad\n"
    "// (validar_firma_ts_rol): reject-unknown sobre {id_cabana, fecha_desde, fecha_hasta};\n"
    "// id_cabana entero positivo seguro OBLIGATORIO (el bloqueo total NO se expone en el portal);\n"
    "// fecha_desde/fecha_hasta YMD reales (isYMD_GW) con hasta > desde (intervalo [) exclusive);\n"
    "// span (hasta - desde) <= 366 dias (cota tecnica Bloque 0). Doble allowlist (D-C-39/40): el\n"
    "// gateway valida ANTES de firmar; el wrapper revalida antes del Postgres. Sin actor (lectura).\n"
    "// Devuelve el payload whitelisteado { id_cabana, fecha_desde, fecha_hasta } (descarta extras).\n"
    "const SPAN_MAX_A26_GW = 366;\n"
    "export const payloadDisponibilidadCabana: PayloadValidator = (payload) => {\n"
    "  const bad = (message: string): PayloadValidation => ({ ok: false, message });\n"
    "  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return bad('payload invalido: se esperaba un objeto');\n"
    "  const p = payload as Record<string, unknown>;\n"
    "  const PERMITIDAS = ['id_cabana', 'fecha_desde', 'fecha_hasta'];\n"
    "  for (const k of Object.keys(p)) if (!PERMITIDAS.includes(k)) return bad(`clave no permitida en payload: ${k}`);\n"
    "\n"
    "  // id_cabana: entero positivo seguro OBLIGATORIO (mismo criterio que payloadIdReserva).\n"
    "  const idc = p.id_cabana;\n"
    "  if (typeof idc !== 'number' || !Number.isSafeInteger(idc) || idc <= 0) return bad('id_cabana debe ser un entero positivo');\n"
    "\n"
    "  // fechas: YMD reales OBLIGATORIAS; hasta > desde (lexicografico == cronologico para YMD).\n"
    "  if (!isYMD_GW(p.fecha_desde)) return bad('fecha_desde invalida (YYYY-MM-DD)');\n"
    "  if (!isYMD_GW(p.fecha_hasta)) return bad('fecha_hasta invalida (YYYY-MM-DD)');\n"
    "  const desde = p.fecha_desde as string;\n"
    "  const hasta = p.fecha_hasta as string;\n"
    "  if (!(desde < hasta)) return bad('fecha_hasta debe ser posterior a fecha_desde');\n"
    "\n"
    "  // span (hasta - desde) en dias <= 366 (no limita el futuro a 120; es cota anti-abuso).\n"
    "  const MS_DIA = 86400000;\n"
    "  const dDesde = Date.UTC(+desde.slice(0, 4), +desde.slice(5, 7) - 1, +desde.slice(8, 10));\n"
    "  const dHasta = Date.UTC(+hasta.slice(0, 4), +hasta.slice(5, 7) - 1, +hasta.slice(8, 10));\n"
    "  const span = Math.round((dHasta - dDesde) / MS_DIA);\n"
    "  if (span > SPAN_MAX_A26_GW) return bad(`rango demasiado amplio (maximo ${SPAN_MAX_A26_GW} dias)`);\n"
    "\n"
    "  return { ok: true, value: { id_cabana: idc, fecha_desde: desde, fecha_hasta: hasta } };\n"
    "};\n"
)

ANCHOR_VAL = "const CATALOG: Record<string, CatalogEntry> = {"
assert s.count(ANCHOR_VAL) == 1, "ancla de const CATALOG no unica"
s = s.replace(ANCHOR_VAL, VALIDATOR + "\n" + ANCHOR_VAL, 1)

# ---------------------------------------------------------------------------
# 2) Entrada CATALOG (lectura pura, webhook sin sufijo) tras la ultima lectura.
# ---------------------------------------------------------------------------
ANCHOR_ENTRY = "  'gastos.listado': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a13-gastos-listado', validate: payloadGastosListado },"
assert s.count(ANCHOR_ENTRY) == 1, "ancla de 'gastos.listado' no unica"

ENTRY_BLOCK = (
    ANCHOR_ENTRY + "\n"
    "  // A26 (Bloque B) -- Disponibilidad por cabana (LECTURA pura; guardrail UX para los date\n"
    "  // pickers de A07/A08). Wrapper n8n firmado (portal-a26-disponibilidad; SIN sufijo:\n"
    "  // convencion de lecturas A05/A12/A24/A25). SOLO vicky/socio (D-C-39): jenny no opera\n"
    "  // reservas -> rebota con rol_no_permitido EN EL GATEWAY antes de firmar. validate:\n"
    "  // payloadDisponibilidadCabana (espejo del wrapper). LECTURA: sin injectActor, sin isWrite,\n"
    "  // sin needsIdempotencyKey -> dispatch no confiable = error_entorno (no estado_incierto).\n"
    "  // La compuerta SQL del wrapper garantiza que obtener_disponibilidad_rango NO se evalua para\n"
    "  // cabana inexistente/inactiva (Bloque A, Function Scan never executed). El key DEBE coincidir\n"
    "  // con EXPECTED_ACTION del wrapper (action binding, D-C-41).\n"
    "  'disponibilidad.cabana': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a26-disponibilidad', validate: payloadDisponibilidadCabana },"
)
s = s.replace(ANCHOR_ENTRY, ENTRY_BLOCK, 1)

# ---------------------------------------------------------------------------
# Sanity post-insercion.
# ---------------------------------------------------------------------------
assert s.count("export const payloadDisponibilidadCabana") == 1, "validador no insertado/duplicado"
assert s.count("'disponibilidad.cabana':") == 1, "entrada CATALOG no insertada/duplicada"
assert s.count("validate: payloadDisponibilidadCabana") == 1, "la entrada CATALOG no referencia el validador"

with open(OUT, 'w', encoding='utf-8') as f:
    f.write(s)

print("OK ->", OUT)
print("payloadDisponibilidadCabana refs:", s.count("payloadDisponibilidadCabana"))
print("'disponibilidad.cabana' refs:", s.count("'disponibilidad.cabana':"))
