// ============================================================================
// A07.1 — CHECK 3: Test de hashing SHA-256 en n8n Cloud
// Carril C / Portal Operativo Interno — Slice 2 / A07.
//
// NATURALEZA: NO toca la base. Solo computa hashes en el Code node y los
//   compara contra vectores de referencia calculados con `crypto` de Node.
//
// DÓNDE EJECUTAR: pegar TAL CUAL en un Code node de n8n (modo "Run Once for All
//   Items"), en un workflow de prueba descartable en la instancia TEST. No
//   requiere input. Ejecutar y leer la salida.
//
// QUÉ PRUEBA (los 3 supuestos que querés validar antes de tocar el wrapper):
//   (1) Disponibilidad de runtime: que `require('crypto')` esté permitido en el
//       sandbox del Code node de ESTA instancia de n8n Cloud. Si está bloqueado
//       (NODE_FUNCTION_ALLOW_BUILTIN restringido) → falla acá, NO en el wrapper.
//   (2) Determinismo: el mismo input produce el mismo hash en dos corridas
//       internas (corre el cómputo dos veces y compara).
//   (3) Vector esperado: contact_hash / payload_hash12 / idem coinciden EXACTO
//       con los calculados fuera de n8n. Si difieren, la canonicalización del
//       Code node no es idéntica → hay que alinearla antes de usarla.
//
// CRITERIO DE PASO: el objeto de salida debe traer veredicto_ok = true.
//   Si crypto no está disponible o algún hash no matchea → veredicto_ok = false
//   y se FRENA (no se construye el wrapper hasta resolver el hashing).
//
// IMPORTANTE: este nodo usa un FIXTURE SINTÉTICO FIJO (sin PII real). La función
//   de hashing definida acá (sha256hex + canonicalización) es EXACTAMENTE la que
//   el wrapper A07.2 va a reusar para derivar contact_hash / payload_hash / idem.
// ============================================================================

// ---- Vectores de referencia (calculados con crypto de Node, fuera de n8n) ----
const EXPECTED = {
  contact_hash:   '247269094ba8b76e3d43b027d48e39371ec72c162af3de1b408e833fc0491ef6',
  payload_hash12: 'dee3c866744b',
  idem:           'portal_test_a07_1_2027-03-01_2027-03-03_247269094ba8b76e3d43b027d48e39371ec72c162af3de1b408e833fc0491ef6_dee3c866744b',
};

// ---- Carga defensiva de crypto: detecta si el builtin está permitido ----
let crypto = null;
let crypto_disponible = false;
let crypto_error = null;
try {
  crypto = require('crypto');
  // probe real: si createHash no existe o tira, lo marcamos
  crypto.createHash('sha256').update('probe', 'utf8').digest('hex');
  crypto_disponible = true;
} catch (e) {
  crypto_error = (e && e.message) ? e.message : String(e);
}

// ---- Helpers de hashing (LA función que reusará el wrapper) ----
function sha256hex(s) {
  return crypto.createHash('sha256').update(String(s), 'utf8').digest('hex');
}

// Canonicalización del payload de negocio: ORDEN FIJO explícito (no Object.keys),
// JSON compacto. Montos ya vienen como string con 2 decimales; horarios null si
// ausentes. Esto garantiza que el mismo negocio reproduzca el mismo hash.
const ORDEN_NEGOCIO = [
  'id_cabana', 'fecha_in', 'fecha_out', 'personas',
  'monto_total', 'monto_sena', 'canal_pago_esperado', 'medio_pago',
  'hora_checkin_solicitada', 'hora_checkout_solicitada', 'mascotas', 'ninos',
];
function canonNegocio(n) {
  return JSON.stringify(ORDEN_NEGOCIO.map((k) => [k, n[k]]));
}

// ---- Fixture sintético FIJO (sin PII real) ----
const contacto_norm = '5490000000007'; // teléfono normalizado: solo dígitos
const negocio = {
  id_cabana: 1,
  fecha_in: '2027-03-01',
  fecha_out: '2027-03-03',
  personas: 2,
  monto_total: '100000.00',
  monto_sena: '50000.00',
  canal_pago_esperado: 'transferencia_mp',
  medio_pago: 'transferencia_mp',
  hora_checkin_solicitada: null,
  hora_checkout_solicitada: null,
  mascotas: false,
  ninos: null,
};

let out;
if (!crypto_disponible) {
  out = {
    check: 'A07.1 / hashing',
    crypto_disponible: false,
    crypto_error,
    api_usada: "require('crypto') — NO disponible en este sandbox",
    veredicto_ok: false,
    nota: "El builtin crypto no está permitido en el Code node. FRENAR: reevaluar estrategia de hashing antes del wrapper.",
  };
} else {
  // Corrida 1
  const contact_hash_1 = sha256hex(contacto_norm);
  const canon_1 = canonNegocio(negocio);
  const payload_hash_full_1 = sha256hex(canon_1);
  const payload_hash12_1 = payload_hash_full_1.slice(0, 12);
  const idem_1 = `portal_test_a07_${negocio.id_cabana}_${negocio.fecha_in}_${negocio.fecha_out}_${contact_hash_1}_${payload_hash12_1}`;

  // Corrida 2 (mismo input) — prueba de determinismo intra-runtime
  const contact_hash_2 = sha256hex(contacto_norm);
  const payload_hash12_2 = sha256hex(canonNegocio(negocio)).slice(0, 12);
  const idem_2 = `portal_test_a07_${negocio.id_cabana}_${negocio.fecha_in}_${negocio.fecha_out}_${contact_hash_2}_${payload_hash12_2}`;

  const determinista =
    contact_hash_1 === contact_hash_2 &&
    payload_hash12_1 === payload_hash12_2 &&
    idem_1 === idem_2;

  const match_contact = contact_hash_1 === EXPECTED.contact_hash;
  const match_payload = payload_hash12_1 === EXPECTED.payload_hash12;
  const match_idem = idem_1 === EXPECTED.idem;

  out = {
    check: 'A07.1 / hashing',
    crypto_disponible: true,
    api_usada: "require('crypto').createHash('sha256')",
    canon_string: canon_1,
    contact_hash: contact_hash_1,
    payload_hash12: payload_hash12_1,
    idem: idem_1,
    idem_length: idem_1.length,
    determinista,
    match_contact_hash: match_contact,
    match_payload_hash12: match_payload,
    match_idem: match_idem,
    veredicto_ok: crypto_disponible && determinista && match_contact && match_payload && match_idem,
  };
}

return [{ json: out }];
