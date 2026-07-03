#!/usr/bin/env python3
# Mini-fix: preservar la seleccion del calendario (fecha_in/fecha_out) al remontar A07 con
# borrador restaurado. El efecto de cambio de cabana en CalendarioRango salta el primer montaje.
# Frontend-only. Idempotente. Corre desde la raiz del repo.
import sys, os

A = "Apps/portal-operativo/src/ui/CalendarioRango.tsx"

EDITS = [
    ("import useRef", "import { useEffect, useState } from 'react';", "import { useEffect, useRef, useState } from 'react';"),
    ("skip primer montaje", "  // Cambio de cabana: reinicia cache, vista y seleccion (la disponibilidad es por cabana).\n  useEffect(() => {\n    setCacheState({ cabana: idCabana, dias: new Map() });\n    setVisibleYm(ymDe(desde || hoy));\n    if (desde || hasta) onChange('', '');\n    // Intencional: solo reacciona al cambio de cabana. Incluir desde/hasta/onChange reiniciaria\n    // la seleccion en cada click. (No hay eslint en el build; se documenta el porque.)\n  }, [idCabana]); // eslint-disable-line react-hooks/exhaustive-deps", "  // Cabana anterior para distinguir el PRIMER montaje de un cambio real de cabana.\n  const idCabanaAnterior = useRef<number | null>(idCabana);\n\n  // Cambio de cabana: reinicia cache, vista y seleccion (la disponibilidad es por cabana).\n  useEffect(() => {\n    // Primer montaje: idCabanaAnterior.current === idCabana -> NO limpia, porque A07 puede venir\n    // con fecha_in/fecha_out restaurados desde el borrador persistente. Solo reacciona al cambio\n    // REAL de cabana despues del montaje.\n    if (idCabanaAnterior.current === idCabana) return;\n    idCabanaAnterior.current = idCabana;\n\n    setCacheState({ cabana: idCabana, dias: new Map() });\n    setVisibleYm(ymDe(desde || hoy));\n    if (desde || hasta) onChange('', '');\n    // Intencional: solo reacciona al cambio de cabana. Incluir desde/hasta/onChange reiniciaria\n    // la seleccion en cada click. (No hay eslint en el build; se documenta el porque.)\n  }, [idCabana]); // eslint-disable-line react-hooks/exhaustive-deps"),
]

def die(m): print("ABORTO:", m); sys.exit(1)

if not os.path.exists(A): die(f"No existe {A}. Corre desde la raiz del repo.")
txt = open(A, encoding="utf-8").read()
if "\r\n" in txt: die("CalendarioRango.tsx tiene CRLF; se esperaba LF puro.")

for label, old, new in EDITS:
    if new in txt:
        print(f"OK  '{label}' ya aplicada (idempotente).")
        continue
    n = txt.count(old)
    if n != 1: die(f"'{label}': ancla aparece {n} veces (se esperaba 1).")
    nuevo = txt.replace(old, new, 1)
    if nuevo.replace(new, old, 1) != txt: die(f"'{label}': la prueba de reverse-replace fallo.")
    txt = nuevo
    print(f"OK  '{label}' aplicada (count==1, reverse-replace verificado).")

with open(A, "w", encoding="utf-8", newline="\n") as f:
    f.write(txt)
print("LISTO. CalendarioRango.tsx parcheado.")
