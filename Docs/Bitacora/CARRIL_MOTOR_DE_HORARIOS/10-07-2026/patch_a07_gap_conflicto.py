#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
patch_a07_gap_conflicto.py

Mapea los dos errores de gap de turno a code:'conflicto' con message prefijado
(gap_checkin: / gap_checkout:) dentro del workflow A07, tocando UNICAMENTE los
nodos router1_crear y router3_confirmar. NO agrega los gaps al array generico de
no_disponible: usa ramas 'if' especificas por codigo. Todo lo demas del template
(IDs, conexiones, queries, webhook, credentials placeholders) queda intacto.

Determinista y fail-closed:
  - aborta si el archivo derivo del baseline validado (hash != BASELINE);
  - detecta si el patch ya esta aplicado (marcador 'gap_checkin:') y no reescribe;
  - exige count==1 por cada ancla;
  - verifica el resultado (parse JSON + estructura + hash de salida) EN MEMORIA
    y solo escribe si todo pasa (all-or-nothing).

Ejecutar desde la raiz del repo:
    python3 patch_a07_gap_conflicto.py
"""
import hashlib
import json
import sys

RUTA = "Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json"

BASELINE_SHA256 = "abee1d0c58e12b8b4ccb5d57b923fc17ffbde3dce4ebbd98b13bf18978609d26"
ESPERADO_SHA256 = "3188bceb777b38dcc12d5aa8475cdb40fe89cb189257644c3b4a738c87cd6def"

# --- Mensajes de contrato (prefijo estable + frase humana, con acentos). UTF-8 literal. ---
MSG_CHECKIN = ("gap_checkin: El check-in queda demasiado cerca del checkout anterior. "
               "Elegí un horario de entrada más tarde.")
MSG_CHECKOUT = ("gap_checkout: El check-out queda demasiado cerca del check-in posterior. "
                "Elegí un horario de salida más temprano.")

# --- router1_crear: ramas de gap ANTES del check generico de conflicto (indent 2 espacios) ---
R1_OLD = ("  if (conflicto.includes(e)) return { ok:false, error: { code:'conflicto', "
          "message:'sin disponibilidad en el rango', detail:null } };")
R1_GAP_IN = ("  if (e === 'checkin_pisa_checkout_anterior') return { ok:false, error: { "
             "code:'conflicto', message:'" + MSG_CHECKIN + "', detail:null } };")
R1_GAP_OUT = ("  if (e === 'checkout_pisa_checkin_posterior') return { ok:false, error: { "
              "code:'conflicto', message:'" + MSG_CHECKOUT + "', detail:null } };")
R1_NEW = R1_GAP_IN + "\n" + R1_GAP_OUT + "\n" + R1_OLD

# --- router3_confirmar: ramas de gap ANTES del branch conflicto_al_confirmar (sin indent) ---
R3_OLD = ("if (e === 'conflicto_al_confirmar' || e === 'no_disponible') return "
          "[{ json: { recheck:false, envelope: {")
R3_GAP_IN = ("if (e === 'checkin_pisa_checkout_anterior') return [{ json: { recheck:false, "
             "envelope: { ok:false, error: { code:'conflicto', message:'" + MSG_CHECKIN + "', "
             "detail:null } } } }];")
R3_GAP_OUT = ("if (e === 'checkout_pisa_checkin_posterior') return [{ json: { recheck:false, "
              "envelope: { ok:false, error: { code:'conflicto', message:'" + MSG_CHECKOUT + "', "
              "detail:null } } } }];")
R3_NEW = R3_GAP_IN + "\n" + R3_GAP_OUT + "\n" + R3_OLD

MARCADOR = "gap_checkin:"


def esc(s: str) -> str:
    """String decodificado -> su forma JSON-escapada (sin comillas), UTF-8 literal."""
    return json.dumps(s, ensure_ascii=False)[1:-1]


def abort(msg: str, code: int = 1):
    print("ABORTA: " + msg)
    sys.exit(code)


def reemplazo_unico(raw: str, old: str, new: str, etiqueta: str) -> str:
    old_e, new_e = esc(old), esc(new)
    n = raw.count(old_e)
    if n != 1:
        abort("ancla %s: se esperaba count==1, se encontro %d (deriva o ya aplicado)"
              % (etiqueta, n))
    return raw.replace(old_e, new_e, 1)


def main():
    data = open(RUTA, "rb").read()
    sha_in = hashlib.sha256(data).hexdigest()
    raw = data.decode("utf-8")

    # 1) Ya aplicado -> no reescribe.
    if MARCADOR in raw:
        print("Patch ya aplicado (marcador '%s' presente). Sin cambios." % MARCADOR)
        print("sha256 actual: " + sha_in)
        sys.exit(0)

    # 2) Gate anti-deriva.
    if sha_in != BASELINE_SHA256:
        abort("hash de entrada != baseline validado.\n  esperado: %s\n  actual:   %s"
              % (BASELINE_SHA256, sha_in))

    # 3) Aplicar (en memoria).
    nuevo = reemplazo_unico(raw, R1_OLD, R1_NEW, "router1_crear")
    nuevo = reemplazo_unico(nuevo, R3_OLD, R3_NEW, "router3_confirmar")

    # 4) Verificacion estructural en memoria (all-or-nothing).
    d = json.loads(nuevo)  # parse OK
    nombres = [n.get("name") for n in d["nodes"]]
    if nombres.count("router1_crear") != 1:
        abort("router1_crear debe aparecer exactamente 1 vez")
    if nombres.count("router3_confirmar") != 1:
        abort("router3_confirmar debe aparecer exactamente 1 vez")

    def code_of(nm):
        return [n["parameters"]["jsCode"] for n in d["nodes"] if n.get("name") == nm][0]

    c1, c3 = code_of("router1_crear"), code_of("router3_confirmar")
    for nm, c in (("router1_crear", c1), ("router3_confirmar", c3)):
        if c.count("gap_checkin:") != 1:
            abort("%s: 'gap_checkin:' debe aparecer exactamente 1 vez" % nm)
        if c.count("gap_checkout:") != 1:
            abort("%s: 'gap_checkout:' debe aparecer exactamente 1 vez" % nm)
        if c.count("checkin_pisa_checkout_anterior") != 1:
            abort("%s: token checkin_pisa_checkout_anterior debe aparecer 1 vez" % nm)
        if c.count("checkout_pisa_checkin_posterior") != 1:
            abort("%s: token checkout_pisa_checkin_posterior debe aparecer 1 vez" % nm)
    # Mappings preexistentes intactos.
    if "const conflicto = ['no_disponible'];" not in c1:
        abort("router1_crear: array conflicto=[no_disponible] no debe cambiar")
    if "datos de reserva rechazados: " not in c1:
        abort("router1_crear: rama payload_invalido no debe cambiar")
    if "conflicto de disponibilidad al confirmar" not in c3:
        abort("router3_confirmar: mensaje conflicto historico no debe cambiar")
    if "res.estado_actual === 'convertida'" not in c3:
        abort("router3_confirmar: rama recheck (convertida) no debe cambiar")

    sha_out = hashlib.sha256(nuevo.encode("utf-8")).hexdigest()
    if ESPERADO_SHA256 != "__RELLENAR_TRAS_DEV__" and sha_out != ESPERADO_SHA256:
        abort("hash de salida != esperado.\n  esperado: %s\n  actual:   %s"
              % (ESPERADO_SHA256, sha_out))

    # 5) Escribir (LF, UTF-8, sin alterar EOL final).
    open(RUTA, "wb").write(nuevo.encode("utf-8"))
    print("OK. Patch A07 aplicado.")
    print("  sha256 in : " + sha_in)
    print("  sha256 out: " + sha_out)


if __name__ == "__main__":
    main()
