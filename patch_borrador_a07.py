#!/usr/bin/env python3
# Patcher: Persistencia de borrador para A07 (frontend TEST). Idempotente.
# Corre desde la raiz del repo. Crea el hook y aplica 4 ediciones ancladas
# (count==1 + prueba de identidad por reverse-replace) sobre CrearReserva.tsx.
import sys, os

BASE = "Apps/portal-operativo/src"
HOOK = os.path.join(BASE, "hooks/useBorradorPersistente.ts")
A07  = os.path.join(BASE, "screens/CrearReserva.tsx")

HOOK_CONTENT = 'import { useCallback, useEffect, useState, type Dispatch, type SetStateAction } from \'react\';\nimport { AMBIENTE } from \'../lib/ambiente\';\n\n// Persistencia de borrador de formularios sobre sessionStorage (nativo, sin dependencias).\n//\n// Que resuelve: cuando una pantalla-formulario se desmonta y remonta -navegacion interna\n// del portal (AppShell sobrevive al cambio de ruta pero la pantalla no), remonte del arbol,\n// o recarga por descarte de la pestana en el celular-, el estado `useState` del form vuelve\n// a su valor inicial y se pierde lo tipeado. Este hook restaura el form al montar y lo guarda\n// en cada cambio, para que sobreviva a cualquiera de esos caminos sin depender de cual ocurra.\n//\n// Que guarda: SOLO el estado del form (el `valor`). Nunca errores, resultado, estado incierto,\n// JWT, sesion ni nada de auth: eso vive en otros estados y no se toca.\n//\n// Ciclo de vida de la clave (la decide la pantalla, no el hook):\n//   - restaura al montar (lazy init);\n//   - persiste en cada cambio del `valor`;\n//   - NO limpia al desmontar -> por eso la navegacion interna del portal no borra el borrador;\n//   - la pantalla llama `limpiar()` en el exito y en "crear otra".\n//\n// sessionStorage (no localStorage): sobrevive a la recarga/descarte de la MISMA pestana, pero\n// se borra al cerrarla -> minimo residuo de datos personales del huesped. Ademas TTL de 24h:\n// un borrador mas viejo se descarta al restaurar (defensa para pestanas que quedan abiertas dias).\n\nconst TTL_MS = 24 * 60 * 60 * 1000; // 24h\n\ninterface Sobre<T> {\n  t: number; // epoch ms del ultimo guardado (para el TTL)\n  v: Partial<T>; // snapshot del form\n}\n\nfunction claveDe(id: string): string {\n  // Ej.: id \'a07-crear-reserva:v1\' -> \'vd:test:draft:a07-crear-reserva:v1\'.\n  // Versionada (la version va dentro del id) y por ambiente: un cambio de forma del form se\n  // resuelve bumpeando el sufijo :vN en la pantalla, sin migrar borradores viejos.\n  return `vd:${AMBIENTE}:draft:${id}`;\n}\n\nfunction leer<T>(clave: string): Partial<T> | null {\n  try {\n    const raw = sessionStorage.getItem(clave);\n    if (raw === null) return null;\n    const sobre = JSON.parse(raw) as { t?: unknown; v?: Partial<T> };\n    if (typeof sobre.t !== \'number\' || Date.now() - sobre.t > TTL_MS) {\n      try { sessionStorage.removeItem(clave); } catch { /* noop */ }\n      return null; // vencido o corrupto\n    }\n    return sobre.v ?? null;\n  } catch {\n    return null; // JSON invalido o storage inaccesible (modo privado, deshabilitado)\n  }\n}\n\nexport interface UseBorradorResult<T> {\n  valor: T;\n  setValor: Dispatch<SetStateAction<T>>;\n  /** Borra el borrador de ESTE formulario (exito, "crear otra"). Referencia estable. */\n  limpiar: () => void;\n}\n\n/**\n * Borrador persistente para un formulario. Reutilizable: cada pantalla pasa su propio `id`\n * (con version, ej. \'a07-crear-reserva:v1\') y su objeto `inicial`. Conviene que `inicial` sea\n * una constante de modulo (estable entre renders).\n */\nexport function useBorradorPersistente<T extends object>(\n  id: string,\n  inicial: T,\n): UseBorradorResult<T> {\n  const clave = claveDe(id);\n\n  // Lazy init: restaura una sola vez, en el primer render (sin flash de vacio). Merge sobre\n  // `inicial`: si el form gano un campo nuevo sin bumpear version, no queda `undefined` en un\n  // input controlado; los campos guardados pisan a los iniciales.\n  const [valor, setValor] = useState<T>(() => {\n    const restaurado = leer<T>(clave);\n    return restaurado ? ({ ...inicial, ...restaurado } as T) : inicial;\n  });\n\n  // Persiste en cada cambio. Sin cleanup: al desmontar NO se borra, asi la navegacion interna\n  // del portal conserva el borrador (se restaura al volver).\n  useEffect(() => {\n    const sobre: Sobre<T> = { t: Date.now(), v: valor };\n    try { sessionStorage.setItem(clave, JSON.stringify(sobre)); } catch { /* noop */ }\n  }, [clave, valor]);\n\n  const limpiar = useCallback(() => {\n    try { sessionStorage.removeItem(clave); } catch { /* noop */ }\n  }, [clave]);\n\n  return { valor, setValor, limpiar };\n}\n\n/**\n * Barrido de TODOS los borradores del ambiente actual. Pensado para el logout (evitar que en\n * un dispositivo compartido el proximo operador vea un borrador ajeno). Todavia SIN cablear:\n * se conecta en el mini-bloque de logout. Exportada aca por cohesion del hook.\n */\nexport function limpiarBorradores(): void {\n  try {\n    const prefijo = `vd:${AMBIENTE}:draft:`;\n    for (const k of Object.keys(sessionStorage)) {\n      if (k.startsWith(prefijo)) sessionStorage.removeItem(k);\n    }\n  } catch { /* noop */ }\n}\n'

EDITS = [
    ("import hook",        "import { useEnviar } from '../hooks/useEnviar';\n", "import { useEnviar } from '../hooks/useEnviar';\nimport { useBorradorPersistente } from '../hooks/useBorradorPersistente';\n"),
    ("form -> hook",       '  const [form, setForm] = useState<FormReserva>(INICIAL);\n', "  const { valor: form, setValor: setForm, limpiar: limpiarBorrador } =\n    useBorradorPersistente<FormReserva>('a07-crear-reserva:v1', INICIAL);\n"),
    ("clean on success",   "  const { enviar, enviando, resultado, error, estadoIncierto, reset } =\n    useEnviar<CrearReservaData>('reserva.crear_manual', 'none');\n", "  const { enviar, enviando, resultado, error, estadoIncierto, reset } =\n    useEnviar<CrearReservaData>('reserva.crear_manual', 'none');\n\n  // Al confirmarse la reserva, el borrador deja de tener sentido: se limpia. `limpiarBorrador`\n  // tiene referencia estable (useCallback en el hook), asi el efecto solo corre al cambiar `resultado`.\n  useEffect(() => {\n    if (resultado) limpiarBorrador();\n  }, [resultado, limpiarBorrador]);\n"),
    ("clean on 'otra'",    '  function otra() {\n    reset();\n    setForm(INICIAL);\n    setErrores({});\n  }\n', '  function otra() {\n    limpiarBorrador();\n    reset();\n    setForm(INICIAL);\n    setErrores({});\n  }\n'),
]

def die(m): print("ABORTO:", m); sys.exit(1)

if not os.path.isdir(BASE): die(f"No existe {BASE}. Corre desde la raiz del repo.")

# 1) Hook (crear; si existe, exigir identico -> re-run seguro)
if os.path.exists(HOOK):
    if open(HOOK, encoding="utf-8").read() != HOOK_CONTENT:
        die(f"{HOOK} existe con contenido distinto.")
    print(f"OK  hook ya presente (identico): {HOOK}")
else:
    os.makedirs(os.path.dirname(HOOK), exist_ok=True)
    with open(HOOK, "w", encoding="utf-8", newline="\n") as f:
        f.write(HOOK_CONTENT)
    print(f"OK  hook creado: {HOOK}")

# 2) Ediciones ancladas en A07
if not os.path.exists(A07): die(f"No existe {A07}.")
txt = open(A07, encoding="utf-8").read()
if "\r\n" in txt: die("A07 tiene CRLF; se esperaba LF puro.")

for label, old, new in EDITS:
    if new in txt:
        print(f"OK  '{label}' ya aplicada (idempotente).")
        continue
    n = txt.count(old)
    if n != 1: die(f"'{label}': ancla aparece {n} veces (se esperaba 1).")
    nuevo = txt.replace(old, new, 1)
    # Prueba de identidad: revertir new->old reproduce el original (ancla unica, edicion reversible)
    if nuevo.replace(new, old, 1) != txt: die(f"'{label}': la prueba de reverse-replace fallo.")
    txt = nuevo
    print(f"OK  '{label}' aplicada (count==1, reverse-replace verificado).")

with open(A07, "w", encoding="utf-8", newline="\n") as f:
    f.write(txt)
print("LISTO. Hook + 4 ediciones aplicadas.")
