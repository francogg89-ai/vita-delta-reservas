#!/usr/bin/env python3
# ============================================================================
# S0_2_patch_wrappers.py  --  Sub-bloque 0.2
#
# Cambia en los 4 wrappers A27/A28 (TEMPLATE + OPS) el pct hardcodeado 0.25 por
# la lectura desde configuracion_general via el helper pct_operativo_vigente()
# (creado en S0.1). Edicion de TEXTO plano sobre el archivo (NO re-serializa el
# JSON) -> diff minimo, solo cambia la llamada. Ancla count==1 por archivo +
# prueba de reversa (revertir el cambio debe devolver el original byte a byte) +
# chequeo de que el resultado sigue siendo JSON valido.
#
# Los TEMPLATE quedan listos para TEST (y canonizacion S0.4); los __OPS quedan
# listos para el re-import en la promocion OPS (S0.3). NO toca deployments vivos:
# solo edita archivos del repo.
#
# USO: correr desde la RAIZ de un clon fresco del repo:
#   python3 S0_2_patch_wrappers.py
# Salida: "TODOS OK" (exit 0) o "FALLA(S)" (exit 1) sin dejar nada garantizado.
# ============================================================================

import json
import os
import sys

# (path relativo a la raiz del repo, ancla vieja, texto nuevo)
EDITS = [
    ("Workflows/n8n/Supabase/portal-a27-cuenta-corriente__TEMPLATE.json",
     "cuenta_corriente_viva(NULL, 0.25)",
     "cuenta_corriente_viva(NULL, pct_operativo_vigente())"),
    ("Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/portal-a27-cuenta-corriente__OPS.json",
     "cuenta_corriente_viva(NULL, 0.25)",
     "cuenta_corriente_viva(NULL, pct_operativo_vigente())"),
    ("Workflows/n8n/Supabase/portal-a28-cuenta-corriente-detalle__TEMPLATE.json",
     "cuenta_corriente_detalle(($1::jsonb ->> 'mes')::date, 0.25)",
     "cuenta_corriente_detalle(($1::jsonb ->> 'mes')::date, pct_operativo_vigente())"),
    ("Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/portal-a28-cuenta-corriente-detalle__OPS.json",
     "cuenta_corriente_detalle(($1::jsonb ->> 'mes')::date, 0.25)",
     "cuenta_corriente_detalle(($1::jsonb ->> 'mes')::date, pct_operativo_vigente())"),
]


def main():
    errs = 0
    for path, old, new in EDITS:
        if not os.path.exists(path):
            print("FALLA: no existe %s (corres desde la raiz del repo?)" % path)
            errs += 1
            continue

        # newline='' preserva el EOL exacto del archivo (no traduce)
        with open(path, "r", encoding="utf-8", newline="") as f:
            orig = f.read()

        n_old = orig.count(old)
        if n_old != 1:
            print("FALLA count==1: la ancla aparece %d veces en %s" % (n_old, path))
            errs += 1
            continue

        if new in orig:
            print("FALLA: el texto nuevo ya esta presente en %s (ya parcheado?)" % path)
            errs += 1
            continue

        patched = orig.replace(old, new)

        # prueba de reversa (identidad): revertir el unico cambio debe reconstruir el original
        if patched.replace(new, old) != orig:
            print("FALLA prueba de reversa en %s (el diff no es minimo/limpio)" % path)
            errs += 1
            continue

        # el resultado debe seguir siendo JSON valido (para que el import no rompa)
        try:
            json.loads(patched)
        except Exception as e:
            print("FALLA: JSON invalido tras el parche en %s: %s" % (path, e))
            errs += 1
            continue

        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(patched)
        print("OK: %s -- 1 cambio, JSON valido, reversa == original" % path)

    if errs:
        print("\n%d FALLA(S). No se garantiza nada; revisa antes de continuar." % errs)
        sys.exit(1)
    print("\nTODOS OK: 4 wrappers parcheados (A27/A28 TEMPLATE + OPS).")
    print("TEMPLATE -> TEST / canonizacion (S0.4) ; __OPS -> re-import en promocion OPS (S0.3).")


if __name__ == "__main__":
    main()
