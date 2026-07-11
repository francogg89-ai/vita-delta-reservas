#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
patch_crear_reserva_gap_conflicto.py

Ajuste minimo de textoErrorReserva() en CrearReserva.tsx. Discrimina EXCLUSIVAMENTE
dentro de la rama error.code === 'conflicto' con startsWith('gap_checkin:') /
startsWith('gap_checkout:') y muestra SOLO la frase humana (strip del prefijo).
Todo otro conflicto, incluido no_disponible, conserva EXACTO el texto historico.

No usa includes() para los prefijos (evita matches accidentales). No toca useEnviar,
mensajeUsuario, contratos, action registry ni otros componentes. Ancla sobre el
BLOQUE COMPLETO actual del if (error.code === 'conflicto'), no sobre una linea suelta.

Determinista y fail-closed:
  - aborta si el archivo derivo del baseline validado (hash != BASELINE);
  - detecta si el patch ya esta aplicado (marcador 'gap_checkin:') y no reescribe;
  - exige count==1 del bloque ancla;
  - verifica el resultado en memoria y solo escribe si todo pasa.

Ejecutar desde la raiz del repo:
    python3 patch_crear_reserva_gap_conflicto.py
"""
import hashlib
import sys

RUTA = "Apps/portal-operativo/src/screens/CrearReserva.tsx"

BASELINE_SHA256 = "cf411e1710bf98b863b64c6980c2dce88fba17881a85e70dacc85d9cb50f1db2"
ESPERADO_SHA256 = "f0ce620b62188689ad434cacbdf8ba2f1601870deca3fd84cd93d9d75da5acb6"

TEXTO_HIST = ("Sin disponibilidad en ese rango (se solapa con una reserva, "
              "pre-reserva o bloqueo).")

# Bloque ancla EXACTO (3 lineas, indent tal cual el archivo).
OLD = (
    "  if (error.code === 'conflicto') {\n"
    "    return '" + TEXTO_HIST + "';\n"
    "  }"
)

# Bloque nuevo: dos ramas startsWith con strip de prefijo + fallback historico intacto.
NEW = (
    "  if (error.code === 'conflicto') {\n"
    "    if (error.message.startsWith('gap_checkin:')) "
    "return error.message.slice('gap_checkin:'.length).trim();\n"
    "    if (error.message.startsWith('gap_checkout:')) "
    "return error.message.slice('gap_checkout:'.length).trim();\n"
    "    return '" + TEXTO_HIST + "';\n"
    "  }"
)

MARCADOR = "gap_checkin:"


def abort(msg: str, code: int = 1):
    print("ABORTA: " + msg)
    sys.exit(code)


def main():
    data = open(RUTA, "rb").read()
    sha_in = hashlib.sha256(data).hexdigest()
    raw = data.decode("utf-8")

    if MARCADOR in raw:
        print("Patch ya aplicado (marcador '%s' presente). Sin cambios." % MARCADOR)
        print("sha256 actual: " + sha_in)
        sys.exit(0)

    if sha_in != BASELINE_SHA256:
        abort("hash de entrada != baseline validado.\n  esperado: %s\n  actual:   %s"
              % (BASELINE_SHA256, sha_in))

    n = raw.count(OLD)
    if n != 1:
        abort("bloque ancla del if(conflicto): se esperaba count==1, se encontro %d" % n)

    nuevo = raw.replace(OLD, NEW, 1)

    # Verificacion en memoria (all-or-nothing).
    if nuevo.count("startsWith('gap_checkin:')") != 1:
        abort("debe haber exactamente 1 startsWith('gap_checkin:')")
    if nuevo.count("startsWith('gap_checkout:')") != 1:
        abort("debe haber exactamente 1 startsWith('gap_checkout:')")
    if nuevo.count(TEXTO_HIST) != 1:
        abort("el texto historico de conflicto debe seguir presente exactamente 1 vez")
    # No se introdujo includes() para los prefijos de gap.
    if "includes('gap_checkin:')" in nuevo or "includes('gap_checkout:')" in nuevo:
        abort("no debe usarse includes() para los prefijos de gap")
    # Ramas preexistentes intactas.
    if "error.message.includes('fecha_in_pasada')" not in nuevo:
        abort("la rama payload_invalido/fecha_in_pasada no debe cambiar")
    if "return mensajeUsuario(error);" not in nuevo:
        abort("el fallback mensajeUsuario no debe cambiar")

    sha_out = hashlib.sha256(nuevo.encode("utf-8")).hexdigest()
    if ESPERADO_SHA256 != "__RELLENAR_TRAS_DEV__" and sha_out != ESPERADO_SHA256:
        abort("hash de salida != esperado.\n  esperado: %s\n  actual:   %s"
              % (ESPERADO_SHA256, sha_out))

    open(RUTA, "wb").write(nuevo.encode("utf-8"))
    print("OK. Patch frontend aplicado.")
    print("  sha256 in : " + sha_in)
    print("  sha256 out: " + sha_out)


if __name__ == "__main__":
    main()
