#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VERIFICADOR_H3_v5.py — estrictamente READ-ONLY e independiente del sistema operativo.

No escribe ningun archivo, no borra, no mueve, no commitea, no toca red, no
modifica la configuracion de Git, no hace reset ni normaliza el clone.

Uso:
    python3 "Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/A07 en paridad y sanitizado/VERIFICADOR_H3_v5.py" --repo .

Exit 0 si todo pasa, 1 si algo falla.

------------------------------------------------------------------------------
POR QUE SE MIDEN BLOBS Y NO EL WORKING TREE
------------------------------------------------------------------------------
En Windows, `core.autocrlf=true` transforma LF -> CRLF durante el checkout. El
working tree queda legitimamente distinto del objeto Git y `git diff` sigue
limpio, porque la conversion es parte del contrato. Medir bytes del working tree
produce hashes que dependen del sistema operativo: la v4 canonica da
68babb23... en LF y 11a7f884... en CRLF, siendo el mismo objeto.

Por eso, para TODO archivo ya versionado, este verificador mide los bytes del
objeto Git via `git cat-file blob HEAD:<ruta>` y nunca el working tree.

Unica excepcion deliberada: las tres altas de H3, que todavia estan en estado
`??` y por lo tanto no tienen blob en HEAD. Esas se miden del working tree, que
es exactamente donde viven.

Resultado esperado: identico con core.autocrlf=true y con core.autocrlf=false.
------------------------------------------------------------------------------
"""
import argparse
import collections
import hashlib
import os
import subprocess
import sys

BASE = "Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/"
DIR_H3 = BASE + "A07 en paridad y sanitizado/"
V5 = DIR_H3 + "H3_MATRIZ_CASCADE_REPO_157_ARCHIVOS_v5.md"
VERIF = DIR_H3 + "VERIFICADOR_H3_v5.py"
CIERRE = DIR_H3 + "H3_CIERRE_INVENTARIO_CARRIL.md"
ALTAS = [CIERRE, V5, VERIF]

V4 = BASE + "13-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md"
V3 = BASE + "14-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md"
D13 = BASE + "13-07-2026/"
D14 = BASE + "14-07-2026/"
SEDE = "Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json"
CANON = "Docs/Implementacion/6B_SCHEMA_SQL.md"
RUNSHEETS = (BASE + "HORARIOS_B2_RUNSHEET (1).md", BASE + "HORARIOS_B2_RUNSHEET (2).md")

RAMA = "main"
HEAD_BASE = "07fea85802bc4fccbff1236813593762aefe58d9"
HEAD_CORTE = "b058de456afd186f91d6ff7e5666978ef4b4df64"
GATE_D2 = "82f28dfdab4acbb5ae6a4391a80e657d871765d5"

SHA_V4 = "68babb238033a985199e6eab8fbbd766fe55b4640dfdf95fc630bb096901b093"
SHA_V3 = "51cc22524b29e4438f73e0e4cd32e67fc8c6576f4fbb2ffb2b4e2916657dca7c"
SHA_V5 = "ffa04f9d13c31776c378e3cdd33936d47287ec125e73caa8e1c74c76b67cdcfb"
SHA_SEDE = "3208b0687e4ef878eb74378173ded2bc5c634cac55ca08f336096de04eaa8fcd"
BLOB_2C99 = "bd731c6817370148023118c8a5de290a4db05858"
SHA_2C99 = "2c99db28866a4e9e7e0ec586e5a18fd443a4b91b64b704fcaa833cbe31a981c3"
BLOB_SEDE = "49bf96a4b12e8aea8ea2c2115670006db8a10126"

CAMPOS_PROY = ["ruta", "estado", "autoridad_actual", "dominio_autoridad",
               "estado_script", "accion_v1_13", "superado_por"]
SHA_PROY_DELTA = "e35ea95da60049d6e4a0a28904354fe0d470c45c28c1d60ff622cc1646353861"
SHA_PROY_TOTAL = "966e5394f362689e7009ed1b9238270d643b12c091e5b930b474520c6574837c"

CONTEOS = {
    "estado": {"VIGENTE": 99, "HISTORICO": 28, "SUPERADO": 19,
               "DUPLICADO": 6, "CONTAMINACION": 3, "COLISION_DIVERGENTE": 2},
    "autoridad_actual": {"NO": 144, "SI": 12, "PARCIAL": 1},
    "accion_v1_13": {"CITAR": 72, "ARCHIVAR": 37, "ARCHIVAR_EVIDENCIA": 30,
                     "CONSOLIDAR": 12, "PRESERVAR_APP": 3, "RECLASIFICAR": 3},
    "estado_script": {"NO_APLICA": 71, "EJECUTABLE": 71,
                      "NO_EJECUTABLE_GATE_OBSOLETO": 15},
}

ABIERTOS = ("PENDIENTE_D2", "PENDIENTE_H1", "BLOQUEADO_H1", "CANDIDATO_REPO_HASTA_D2")

DIVERGENTES = {
    "14-07-2026/D2_RUNBOOK.md":
        ("SUPERADO", "ARCHIVAR", "13-07-2026/D2_RUNBOOK.md"),
    "14-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md":
        ("SUPERADO", "ARCHIVAR_EVIDENCIA", "13-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md"),
}

MUTANTES = ("CREATE", "DROP", "ALTER", "INSERT", "UPDATE", "DELETE", "TRUNCATE",
            "GRANT", "REVOKE", "MERGE", "COPY", "VACUUM", "REINDEX", "REFRESH")

FALLOS, OKS = [], []
GIT_RC = []          # (comando, rc) de TODOS los comandos git ejecutados


def chk(cond, msg, detalle=""):
    linea = msg + (("  ->  " + detalle) if detalle else "")
    (OKS if cond else FALLOS).append(linea)
    print(("  [OK]    " if cond else "  [FALLA] ") + linea)
    return bool(cond)


# ---------------------------------------------------------------- capa Git
def git_raw(*args):
    """Ejecuta git en modo BINARIO. Registra y verifica el return code.

    Devuelve (stdout_bytes, rc). Nunca escribe archivos: solo pipes.
    """
    r = subprocess.run(("git",) + args, capture_output=True)
    GIT_RC.append((" ".join(args[:3]), r.returncode))
    if r.returncode != 0:
        chk(False, "git %s  ->  rc=%d" % (" ".join(args[:4]), r.returncode),
            r.stderr.decode("utf-8", "replace").strip()[:140])
    return r.stdout, r.returncode


def git(*args):
    """Igual que git_raw pero devuelve texto ya decodificado y sin bordes."""
    out, rc = git_raw(*args)
    return out.decode("utf-8", "surrogateescape").strip(), rc


def git_config(clave):
    """Lectura informativa de configuracion. rc=1 significa 'no definida', no error:
    por eso NO se registra en la verificacion obligatoria de return codes."""
    r = subprocess.run(("git", "config", "--get", clave), capture_output=True)
    return r.stdout.decode("utf-8", "replace").strip()


def blob(path, rev="HEAD"):
    """Bytes CANONICOS del objeto Git. Independiente de core.autocrlf."""
    out, rc = git_raw("cat-file", "blob", "%s:%s" % (rev, path))
    if rc != 0:
        return b""
    return out


def sha_blob(path, rev="HEAD"):
    return hashlib.sha256(blob(path, rev)).hexdigest()


def md5_blob(path, rev="HEAD"):
    return hashlib.md5(blob(path, rev)).hexdigest()


def sha_wt(path):
    """Bytes REALES del working tree. Solo para las 3 altas, que no tienen blob."""
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def sha256_todo_el_arbol():
    """sha256 del contenido de TODOS los blobs de HEAD, en una sola pasada."""
    out, rc = git_raw("ls-tree", "-r", "HEAD")
    if rc != 0:
        return {}
    entradas = []
    for linea in out.decode("utf-8", "surrogateescape").split("\n"):
        if not linea.strip():
            continue
        meta, ruta = linea.split("\t", 1)
        campos = meta.split()
        if campos[1] == "blob":
            entradas.append((campos[2], ruta))
    if not entradas:
        return {}
    pedido = ("\n".join(s for s, _ in entradas) + "\n").encode()
    p = subprocess.run(("git", "cat-file", "--batch"), input=pedido, capture_output=True)
    GIT_RC.append(("cat-file --batch", p.returncode))
    chk(p.returncode == 0, "git cat-file --batch sobre %d blobs  ->  rc=%d"
        % (len(entradas), p.returncode))
    if p.returncode != 0:
        return {}
    data, i, res = p.stdout, 0, {}
    for _sha, ruta in entradas:
        j = data.index(b"\n", i)
        tam = int(data[i:j].split()[2])
        res[ruta] = hashlib.sha256(data[j + 1:j + 1 + tam]).hexdigest()
        i = j + 1 + tam + 1
    return res


# ---------------------------------------------------------------- matriz
def parse_bytes(raw, origen):
    lineas = raw.decode("utf-8").replace("\r\n", "\n").split("\n")
    h = None
    for i, l in enumerate(lineas):
        if l.startswith("|") and "autoridad_actual" in l and "accion_v1_13" in l and "ruta" in l:
            h = i
            break
    if h is None:
        raise SystemExit("cabecera de tabla no encontrada en " + origen)
    cols = [c.strip() for c in lineas[h].strip().strip("|").split("|")]
    filas, i = [], h + 2
    while i < len(lineas) and lineas[i].startswith("|"):
        filas.append(lineas[i])
        i += 1
    return cols, filas


def cell(fila, cols, nombre):
    c = [x.strip() for x in fila.strip().strip("|").split("|")]
    return c[cols.index(nombre)].strip().strip("`").strip("*").strip()


def proyeccion(filas, cols):
    return sorted("|".join(cell(f, cols, c) for c in CAMPOS_PROY) for f in filas)


def sha_proy(p):
    return hashlib.sha256(("\n".join(p) + "\n").encode("utf-8")).hexdigest()


def sin_comentarios(txt):
    out, i, n = [], 0, len(txt)
    while i < n:
        if txt.startswith("--", i):
            j = txt.find("\n", i)
            i = n if j < 0 else j
        elif txt.startswith("/*", i):
            j = txt.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(txt[i])
            i += 1
    return "".join(out)


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    a = ap.parse_args()
    os.chdir(a.repo)

    print("=" * 79)
    print("VERIFICADOR H3 v5  ·  READ-ONLY  ·  independiente del sistema operativo")
    print("=" * 79)
    print("Archivos versionados: se miden los BLOBS de Git (canonicos, LF).")
    print("Las 3 altas de H3 (estado ??): se mide el working tree, que es donde viven.")

    # -------------------------------------------------------------- 1
    print("\n1. Contexto git")
    autocrlf = git_config("core.autocrlf")
    eol = git_config("core.eol")
    print("     core.autocrlf = %s   core.eol = %s   (informativo: no debe afectar el resultado)"
          % (autocrlf or "(sin definir)", eol or "(sin definir)"))
    rama, _ = git("rev-parse", "--abbrev-ref", "HEAD")
    chk(rama == RAMA, "rama actual == %s" % RAMA, rama)
    head, _ = git("rev-parse", "HEAD")
    chk(head == HEAD_CORTE, "HEAD exacto == b058de4", head)
    _, rc = git("merge-base", "--is-ancestor", GATE_D2, "HEAD")
    chk(rc == 0, "gate D2: 82f28df es ancestro de HEAD")

    # -------------------------------------------------------------- 2
    print("\n2. Conjunto exacto de cambios del arbol")
    st, _ = git("status", "--porcelain")
    entradas = [l for l in st.split("\n") if l.strip()]
    estados = [l[:2].strip() for l in entradas]
    rutas = [l[3:].strip().strip('"') for l in entradas]
    chk(len(entradas) == 3, "exactamente 3 entradas en git status", str(len(entradas)))
    chk(all(e == "??" for e in estados), "las 3 entradas tienen estado '??' (altas)",
        " ".join(estados))
    chk(sorted(rutas) == sorted(ALTAS), "el conjunto de cambios == las 3 altas esperadas",
        " | ".join(sorted(rutas)))
    ajenos = [r for r in rutas if r not in ALTAS]
    chk(not ajenos, "cero cambios ajenos a H3", ", ".join(ajenos))

    # -------------------------------------------------------------- 3
    print("\n3. Las 3 altas — bytes REALES del working tree (no tienen blob en HEAD)")
    for p in ALTAS:
        nom = p.split("/")[-1]
        if not chk(os.path.isfile(p), "existe: %s" % nom):
            continue
        with open(p, "rb") as fh:
            raw = fh.read()
        chk(raw[:3] != b"\xef\xbb\xbf", "%s · UTF-8 sin BOM" % nom)
        chk(b"\r" not in raw, "%s · LF puro (cero CR)" % nom,
            "" if b"\r" not in raw else "%d CR" % raw.count(b"\r"))
        chk(raw.endswith(b"\n"), "%s · termina en newline" % nom)
        try:
            raw.decode("utf-8")
            chk(True, "%s · decodifica como UTF-8" % nom)
        except UnicodeDecodeError as e:
            chk(False, "%s · decodifica como UTF-8" % nom, str(e))
    chk(sha_wt(V5) == SHA_V5, "v5 · sha256 del working tree == el fijado aca", sha_wt(V5))

    # -------------------------------------------------------------- 4
    print("\n4. v3 y v4 intactas — medidas por BLOB Git")
    s4, s3 = sha_blob(V4), sha_blob(V3)
    chk(s4 == SHA_V4, "v4 (13-07) blob byte-identico", s4)
    chk(s3 == SHA_V3, "v3 (14-07) blob byte-identico", s3)
    b4 = blob(V4)
    chk(b"\r\n" not in b4, "el blob de la v4 es LF puro (el working tree puede no serlo)")
    crlf = hashlib.sha256(b4.replace(b"\n", b"\r\n")).hexdigest()
    print("     nota: ese mismo blob en CRLF daria %s" % crlf)
    print("           es el valor que aparece si se mide el working tree smudged.")

    # -------------------------------------------------------------- 5
    print("\n5. Estructura de la tabla de datos")
    with open(V5, "rb") as fh:
        cols5, rows5 = parse_bytes(fh.read(), V5)
    cols4, rows4 = parse_bytes(b4, V4)
    chk(len(rows5) == 157, "157 filas de datos", str(len(rows5)))
    chk(len(cols5) == 15 and cols5 == cols4, "15 columnas, identicas a las de la v4")
    nums = [cell(r, cols5, "#") for r in rows5]
    chk(nums == [str(i) for i in range(1, 158)], "numeracion contigua 1..157 sin huecos")
    malas = [n for n, r in zip(nums, rows5) if len(r.strip().strip("|").split("|")) != 15]
    chk(not malas, "las 157 filas tienen 15 celdas", ", ".join(malas[:5]))
    rutas_m = [cell(r, cols5, "ruta") for r in rows5]
    dups = [r for r, c in collections.Counter(rutas_m).items() if c > 1]
    chk(not dups, "sin rutas repetidas en la matriz", ", ".join(dups[:3]))

    # -------------------------------------------------------------- 6
    print("\n6. Filas 1..107 heredadas de la v4")
    difs = [i + 1 for i in range(107) if rows5[i] != rows4[i]]
    chk(difs == [70], "unica fila alterada respecto de la v4: la 70", str(difs))
    f70 = rows5[69]
    esperado70 = {"estado": "HISTORICO", "autoridad_actual": "NO",
                  "dominio_autoridad": "NINGUNO", "fragmento_autoritativo": "—",
                  "estado_script": "NO_APLICA", "accion_v1_13": "ARCHIVAR_EVIDENCIA",
                  "referencia_viva": "Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json"}
    for k, v in esperado70.items():
        chk(cell(f70, cols5, k) == v, "fila 70 · %s == %s" % (k, v), cell(f70, cols5, k))
    mot70 = cell(f70, cols5, "motivo")
    for h in ("3188bceb", "3208b068", "93641838"):
        chk(h in mot70, "fila 70 · motivo distingue el artefacto %s..." % h)
    chk("Solo la sede canonica vigente tiene autoridad" in mot70,
        "fila 70 · motivo atribuye autoridad SOLO a la sede canonica")
    chk("ninguno de los dos primeros es autoridad" not in mot70,
        "fila 70 · sin la frase que le negaba autoridad a la sede")

    # -------------------------------------------------------------- 7
    print("\n7. Cero filas abiertas")
    for tok in ABIERTOS:
        hits = [cell(r, cols5, "#") for r in rows5
                if tok in cell(r, cols5, "autoridad_actual")
                or tok in cell(r, cols5, "accion_v1_13")]
        chk(not hits, "sin %s en columnas de clasificacion" % tok, ", ".join(hits))

    # -------------------------------------------------------------- 8
    print("\n8. Filas 108..157 == delta medido 07fea85 -> b058de4")
    old, _ = git("ls-tree", "-r", "--name-only", HEAD_BASE, "--", BASE)
    new, _ = git("ls-tree", "-r", "--name-only", HEAD_CORTE, "--", BASE)
    old = set(x for x in old.split("\n") if x.strip())
    new = set(x for x in new.split("\n") if x.strip())
    chk(len(old) == 107, "107 archivos versionados en 07fea85", str(len(old)))
    chk(len(new) == 157, "157 archivos versionados en b058de4", str(len(new)))
    chk(not (old - new), "0 archivos eliminados entre ambos HEAD", str(len(old - new)))
    delta = sorted(new - old)
    chk(len(delta) == 50, "50 archivos en el delta", str(len(delta)))
    chk(sorted(rutas_m[107:]) == sorted(x[len(BASE):] for x in delta),
        "las 50 rutas de las filas 108..157 == el delta del arbol")

    print("\n8.1 sha256 declarado vs BLOB de cada uno de los 50")
    malos = []
    for r in rows5[107:]:
        ru = cell(r, cols5, "ruta")
        real = sha_blob(BASE + ru)[:12]
        if cell(r, cols5, "sha256") != real:
            malos.append("%s decl=%s blob=%s" % (ru, cell(r, cols5, "sha256"), real))
    chk(not malos, "los 50 prefijos sha256 coinciden con el blob Git", "; ".join(malos[:3]))

    # -------------------------------------------------------------- 9
    print("\n9. Clasificacion individual — proyeccion fijada por SHA-256")
    print("     campos: " + "|".join(CAMPOS_PROY))
    pd, pt = proyeccion(rows5[107:], cols5), proyeccion(rows5, cols5)
    chk(len(pd) == 50, "proyeccion del delta: 50 lineas", str(len(pd)))
    chk(sha_proy(pd) == SHA_PROY_DELTA, "sha256 proyeccion filas 108..157", sha_proy(pd))
    chk(len(pt) == 157, "proyeccion total: 157 lineas", str(len(pt)))
    chk(sha_proy(pt) == SHA_PROY_TOTAL, "sha256 proyeccion filas 1..157", sha_proy(pt))
    chk(len(set(pt)) == 157, "las 157 lineas de proyeccion son distintas entre si",
        str(len(set(pt))))

    # -------------------------------------------------------------- 10
    print("\n10. Conteos EXACTOS por valor")
    for columna, esperado in CONTEOS.items():
        real = collections.Counter(cell(r, cols5, columna) for r in rows5)
        chk(dict(real) == esperado, "%s · distribucion exacta" % columna,
            " · ".join("%s=%d" % kv for kv in sorted(real.items(), key=lambda x: -x[1])))
        chk(sum(real.values()) == 157, "%s · suma 157" % columna, str(sum(real.values())))
    cons = [r for r in rows5 if cell(r, cols5, "accion_v1_13") == "CONSOLIDAR"]
    chk(all(int(cell(r, cols5, "#")) <= 107 for r in cons),
        "los 12 CONSOLIDAR estan todos en las filas 1..107")

    # -------------------------------------------------------------- 11
    print("\n11. Los 7 nombres compartidos 13-07 / 14-07 — por BLOB")
    n13 = set(x[len(D13):] for x in new if x.startswith(D13) and "/" not in x[len(D13):])
    n14 = set(x[len(D14):] for x in new if x.startswith(D14) and "/" not in x[len(D14):])
    compartidos = sorted(n13 & n14)
    chk(len(compartidos) == 7, "7 nombres compartidos (derivados de git ls-tree)",
        str(len(compartidos)))
    doc5 = open(V5, encoding="utf-8").read()
    ident, diver = [], []
    for n in compartidos:
        sa, sb = sha_blob(D13 + n), sha_blob(D14 + n)
        (ident if sa == sb else diver).append(n)
        chk(sa in doc5 and sb in doc5,
            "%s · ambos SHA-256 COMPLETOS de blob declarados en la v5" % n[:40])
    chk(len(ident) == 5, "5 IDENTICO", ", ".join(x[:26] for x in ident))
    chk(sorted(diver) == sorted(k.split("/")[1] for k in DIVERGENTES), "2 DIVERGENTE",
        ", ".join(diver))
    for n in ident:
        r = next(x for x in rows5[107:] if cell(x, cols5, "ruta") == "14-07-2026/" + n)
        chk(cell(r, cols5, "estado") == "DUPLICADO"
            and cell(r, cols5, "accion_v1_13") == "ARCHIVAR"
            and cell(r, cols5, "superado_por") == "13-07-2026/" + n,
            "14-07/%s -> DUPLICADO / ARCHIVAR / superado_por correcto" % n[:34])
    for ruta, (est, acc, sup) in DIVERGENTES.items():
        r = next(x for x in rows5[107:] if cell(x, cols5, "ruta") == ruta)
        chk(cell(r, cols5, "estado") == est, "%s · estado == %s" % (ruta[:38], est),
            cell(r, cols5, "estado"))
        chk(cell(r, cols5, "accion_v1_13") == acc, "%s · accion == %s" % (ruta[:38], acc),
            cell(r, cols5, "accion_v1_13"))
        chk(cell(r, cols5, "superado_por") == sup, "%s · superado_por correcto" % ruta[:38],
            cell(r, cols5, "superado_por"))

    # -------------------------------------------------------------- 12
    print("\n12. Runsheets B2 en colision — MD5 y SHA-256 de blob")
    for p in RUNSHEETS:
        s, m = sha_blob(p), md5_blob(p)
        chk(s in doc5 and m in doc5,
            "%s · MD5 y SHA-256 completos declarados" % p.split("/")[-1],
            "md5=%s sha=%s" % (m[:10], s[:10]))

    # -------------------------------------------------------------- 13
    print("\n13. Addendum de procedencia 2c99db28")
    for tok, et in ((SHA_2C99, "sha256 completo del contenido historico"),
                    (BLOB_2C99, "blob SHA-1 historico"),
                    (SHA_SEDE, "sha256 completo del sustituto"),
                    (BLOB_SEDE, "blob SHA-1 del sustituto"),
                    ("9ff6db7", "commit inicial de vigencia"),
                    ("a2a5893", "ultimo commit donde estuvo presente"),
                    ("b058de4", "commit de sustitucion")):
        chk(tok in doc5, "addendum declara %s" % et)
    bl, _ = git("rev-parse", "a2a5893:" + SEDE)
    chk(bl == BLOB_2C99, "blob a2a5893:sede == bd731c68...", bl)
    chk(sha_blob(SEDE) == SHA_SEDE, "sede canonica hoy (blob) == 3208b068...", sha_blob(SEDE))
    chk(hashlib.sha256(blob(SEDE, "a2a5893")).hexdigest() == SHA_2C99,
        "el blob de la sede en a2a5893 hashea a 2c99db28...")
    arbol = sha256_todo_el_arbol()
    chk(len(arbol) > 0, "sha256 de los %d blobs de HEAD calculado en una pasada" % len(arbol))
    presentes = [p for p, h in arbol.items() if h == SHA_2C99]
    chk(not presentes, "2c99db28 NO esta en ningun blob de HEAD", ", ".join(presentes))
    chk("FALSO NEGATIVO" in doc5 or "falso negativo" in doc5,
        "la v5 califica el NO LOCALIZADO como falso negativo de alcance")
    chk("no era verdadero como afirmación global" in doc5.lower(),
        "la v5 niega la validez global del NO LOCALIZADO")

    # -------------------------------------------------------------- 14
    print("\n14. Prueba read-only de los .sql del delta — sobre BLOBS")
    sqls = [x for x in delta if x.endswith(".sql")]
    chk(len(sqls) == 23, "23 archivos .sql en el delta (21 unicos + 2 duplicados)", str(len(sqls)))
    chk(len([r for r in rows5[107:] if cell(r, cols5, "ruta").endswith(".sql")]) == 23,
        "23 filas .sql en la matriz")
    total_mut, sin_ro, sin_gate = 0, [], []
    for f in sqls:
        txt = blob(f).decode("utf-8")
        for ln in sin_comentarios(txt).split("\n"):
            s = ln.strip().upper()
            if any(s.startswith(m + " ") for m in MUTANTES):
                total_mut += 1
        if "BEGIN TRANSACTION READ ONLY" not in txt:
            sin_ro.append(os.path.basename(f))
        if "configuracion_general" not in txt:
            sin_gate.append(os.path.basename(f))
    chk(total_mut == 0, "cero sentencias DDL/DML no comentadas en los 23 .sql", str(total_mut))
    chk(not sin_ro, "los 23 abren BEGIN TRANSACTION READ ONLY", ", ".join(sin_ro))
    chk(not sin_gate, "los 23 traen gate propio sobre configuracion_general", ", ".join(sin_gate))

    # -------------------------------------------------------------- 15
    print("\n15. Intocables")
    for p in (CANON, SEDE, V3, V4):
        d, _ = git("diff", "--name-only", "HEAD", "--", p)
        chk(not d.strip(), "sin modificar: %s" % p, d)
    for pref in ("Docs/Operacional/", "bootstrap_entorno_nuevo_v1.12.0/"):
        d, _ = git("diff", "--name-only", "HEAD", "--", pref)
        chk(not d.strip(), "sin modificar: %s" % pref, d)

    # -------------------------------------------------------------- 16
    print("\n16. Return code de TODOS los comandos git ejecutados")
    malos_rc = [c for c, rc in GIT_RC if rc != 0]
    chk(not malos_rc, "los %d comandos git devolvieron rc=0" % len(GIT_RC),
        ", ".join(malos_rc[:4]))

    print("\n" + "=" * 79)
    print("OK: %d   FALLAS: %d" % (len(OKS), len(FALLOS)))
    if FALLOS:
        print("\nFALLAS:")
        for f in FALLOS:
            print("  - " + f)
    print("=" * 79)
    return 1 if FALLOS else 0


if __name__ == "__main__":
    sys.exit(main())
