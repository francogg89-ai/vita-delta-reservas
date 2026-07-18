#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ==============================================================================
# verificador_a07.py  --  Vita Delta Reservas / Motor de Horarios B1.3
# ------------------------------------------------------------------------------
# Verificador READ-ONLY del workflow n8n `portal-a07-crear-reserva`.
#
# Compara TRES exports y exige PARIDAD FUNCIONAL entre ellos:
#     1) OPS ya modificado (o el CANDIDATO sanitizado, como referencia)
#     2) TEMPLATE canonico del repo
#     3) TEST vivo (fuente de la logica funcional correcta)
#
# Que verifica (exit != 0 ante CUALQUIERA de estas condiciones):
#   - Cantidad REAL de nodos: debe ser identica en los tres.
#   - Nombres de nodo ORIGINALES unicos y nombres NORMALIZADOS unicos.
#     Cualquier colision introducida por norm_node_name (p. ej. un duplicado
#     con sufijo) se detecta y falla.
#   - Igualdad de tipo, typeVersion y parametros funcionales (jsCode incluido).
#   - Igualdad de los campos de conducta de nodo cuando existan:
#       onError, alwaysOutputData, disabled, retryOnFail, maxTries,
#       waitBetweenTries, executeOnce.
#   - Presencia de credencial en los seis nodos PostgreSQL y que su flavor
#     (test/ops) corresponda al ambiente del workflow.
#   - Igualdad de settings.executionOrder y settings.binaryMode.
#   - Igualdad de conexiones.
#   - Presencia de la conducta de gap-errors (el fix) en router1_crear y
#     router3_confirmar.
#
# Que informa SIN afectar el exit code:
#   - `active` de cada workflow, como ESTADO DE DESPLIEGUE (los versionables
#     estan inactivos; los vivos, activos).
#
# HMAC (importante):
#   - El literal del fallback del ternario `const SECRET = ... : '<literal>'`
#     en `validar_firma_ts_rol` es un DUMMY SINTETICO de longitud fija, SIN
#     valor operativo, presente solo en los exports de trabajo para preservar
#     longitud. Los artefactos versionables lo reemplazan por el placeholder
#     __PEGAR_SECRETO_O_USAR_VARIABLE__.
#   - El verificador NORMALIZA ese literal EXCLUSIVAMENTE en el ternario de
#     `validar_firma_ts_rol` (no lo compara ni lo imprime). NO clasifica ningun
#     literal como "secreto real" por su longitud, y NO aplica ese enmascarado
#     a ningun otro nodo ni a ninguna otra linea.
#
# Uso:
#     python3 verificador_a07.py \
#         portal-a07-crear-reserva__OPS.json \
#         portal-a07-crear-reserva__TEMPLATE.json \
#         portal-a07-crear-reserva__TEST.json
#
#   Sin argumentos usa estos nombres por defecto en el directorio actual:
#     OPS_MOD  = portal-a07-crear-reserva__OPS__CANDIDATO_SANITIZADO.json
#     TEMPLATE = portal-a07-crear-reserva__TEMPLATE.json
#     TEST     = portal-a07-crear-reserva__TEST.json
#
#   Self-tests negativos (no requieren red; usan los tres archivos como base):
#     python3 verificador_a07.py --self-test [OPS.json TEMPLATE.json TEST.json]
#
# Solo lee archivos. No escribe nada. No toca red, n8n, Supabase ni git.
# ==============================================================================

import sys
import os
import json
import re
import copy

# ------------------------------------------------------------------------------
# Utilidades base
# ------------------------------------------------------------------------------

def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def node_by_name(wf, name):
    for n in wf.get("nodes", []):
        if n.get("name") == name:
            return n
    return None


# ------------------------------------------------------------------------------
# Normalizacion de nombres y flavor (AMBIENTAL / COSMETICO)
# ------------------------------------------------------------------------------
# TEST agrega un unico sufijo "1" a casi todos los nodos (artefacto de la
# duplicacion en n8n). OPS y el TEMPLATE usan los nombres limpios.
# El nodo de aviso y varios comentarios de cabecera llevan el flavor __TEST/__OPS.

FLAVOR_RE = re.compile(r"__(TEST|OPS)")


def strip_flavor(s):
    """Colapsa __TEST/__OPS a __FLAVOR (marcador de ambiente)."""
    if s is None:
        return None
    return FLAVOR_RE.sub("__FLAVOR", s)


def norm_node_name(name):
    """Nombre canonico de nodo: quita UN unico sufijo '1' y colapsa el flavor.
    OPS/TEMPLATE no terminan en '1'; TEST agrega exactamente uno."""
    if name is None:
        return None
    n = name
    if n.endswith("1"):
        n = n[:-1]
    return strip_flavor(n)


# ------------------------------------------------------------------------------
# Normalizacion del jsCode (AMBIENTAL) -> deja SOLO la logica funcional
# ------------------------------------------------------------------------------
# IMPORTANTE: no existe ninguna regex amplia del tipo r":\s*'[^']*'\s*;" aplicada
# sobre todo el jsCode. El unico enmascarado de literal es el fallback del
# ternario SECRET y SOLO dentro de `validar_firma_ts_rol`.

# Refs internas que en TEST llevan sufijo "1":  $('NodeName1') -> $('NodeName')
_REF_SUFFIX_RE = re.compile(r"\$\('([^']+?)1'\)")

# Prefijo de idempotencia embebido en `Code: derivar`:  portal_test_a07_ / portal_ops_a07_
_IDEM_PREFIX_RE = re.compile(r"portal_(?:test|ops)_a07_")

# Ternario del SECRET en `validar_firma_ts_rol`. Captura el prefijo hasta el
# fallback y el `;` final, y reemplaza SOLO el literal del fallback. No depende
# de la longitud del literal (placeholder de 33 o dummy de 64: da igual).
_SECRET_TERNARY_RE = re.compile(
    r"(const\s+SECRET\s*=\s*[^;]*?\?[^;]*?:\s*)'[^']*'(\s*;)", re.DOTALL
)

VALIDAR_FIRMA = "validar_firma_ts_rol"


def norm_expr_string(s):
    """Normaliza lo ambiental de CUALQUIER string de parametro: referencias a
    nodos con sufijo '1' y flavor __TEST/__OPS. NO enmascara literales."""
    if not isinstance(s, str):
        return s
    s = _REF_SUFFIX_RE.sub(lambda m: "$('%s')" % m.group(1), s)
    s = strip_flavor(s)
    return s


def _walk_norm_strings(obj):
    """Aplica norm_expr_string a todos los strings de una estructura anidada."""
    if isinstance(obj, dict):
        return {k: _walk_norm_strings(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_walk_norm_strings(v) for v in obj]
    if isinstance(obj, str):
        return norm_expr_string(obj)
    return obj


def norm_jscode(code, node_name=None):
    """Normaliza SOLO lo ambiental del codigo; conserva la logica intacta.
    El enmascarado del fallback SECRET se aplica UNICAMENTE si el nodo es
    `validar_firma_ts_rol` (acotado al ternario)."""
    if code is None:
        return None
    c = code
    # 1) refs internas con sufijo 1 -> sin sufijo
    c = _REF_SUFFIX_RE.sub(lambda m: "$('%s')" % m.group(1), c)
    # 2) prefijo de idempotencia -> token fijo
    c = _IDEM_PREFIX_RE.sub("portal_FLAVOR_a07_", c)
    # 3) fallback del SECRET -> token fijo, SOLO en validar_firma_ts_rol
    if norm_node_name(node_name) == VALIDAR_FIRMA:
        c = _SECRET_TERNARY_RE.sub(r"\1'__SECRET_NORMALIZED__'\2", c)
    # 4) flavor en comentarios de cabecera
    c = strip_flavor(c)
    # 5) fin de linea: colapsar CRLF y quitar newline final
    c = c.replace("\r\n", "\n").rstrip("\n")
    return c


# ------------------------------------------------------------------------------
# Normalizacion de parametros por tipo de nodo (AMBIENTAL)
# ------------------------------------------------------------------------------

def norm_webhook_params(p):
    q = copy.deepcopy(p)
    if "path" in q:
        q["path"] = strip_flavor(q["path"])
    return q


def norm_aviso_params(p):
    q = copy.deepcopy(p)
    wid = q.get("workflowId")
    if isinstance(wid, dict):
        if "value" in wid:
            wid["value"] = "WID_FLAVOR"
        if "cachedResultUrl" in wid:
            wid["cachedResultUrl"] = "/workflow/WID_FLAVOR"
        wid.pop("cachedResultName", None)  # cosmetico; puede faltar en un ambiente
    return q


def norm_if_8cbis_params(p):
    """El UUID interno de la condicion es cosmetico; se neutraliza."""
    q = copy.deepcopy(p)
    conds = q.get("conditions")
    if isinstance(conds, dict):
        for c in conds.get("conditions", []):
            if isinstance(c, dict) and "id" in c:
                c["id"] = "COND_ID_NORMALIZED"
    return q


def norm_respond_params(p):
    """El default de respondWith es 'firstIncomingItem'; se explicita para que un
    export que lo omite y un template que lo declara sean equivalentes."""
    q = copy.deepcopy(p)
    q.setdefault("respondWith", "firstIncomingItem")
    return q


def canonical_params(node):
    """Parametros FUNCIONALES del nodo (con lo ambiental normalizado)."""
    ntype = node.get("type")
    params = node.get("parameters") or {}
    q = copy.deepcopy(params)

    if "jsCode" in q:
        q["jsCode"] = norm_jscode(q["jsCode"], node.get("name"))

    if ntype == "n8n-nodes-base.webhook":
        q = norm_webhook_params(q)
    elif ntype == "n8n-nodes-base.executeWorkflow":
        q = norm_aviso_params(q)
    elif ntype == "n8n-nodes-base.if":
        q = norm_if_8cbis_params(q)
    elif ntype == "n8n-nodes-base.respondToWebhook":
        q = norm_respond_params(q)

    # Normaliza refs/flavor en el resto de strings (queryReplacement, workflowInputs,
    # etc.). Idempotente sobre jsCode ya normalizado. NO enmascara literales.
    q = _walk_norm_strings(q)
    return q


# ------------------------------------------------------------------------------
# Campos de conducta de nodo (requisito: compararlos cuando existan)
# ------------------------------------------------------------------------------

NODE_BEHAVIOR_FIELDS = [
    "onError", "alwaysOutputData", "disabled",
    "retryOnFail", "maxTries", "waitBetweenTries", "executeOnce",
]
_ABSENT = "<ABSENT>"


def node_behavior(node):
    """Firma de conducta: valor por campo, o <ABSENT> si no esta.
    Comparar estas firmas detecta agregado, quitado o cambio de cualquiera."""
    return {f: node.get(f, _ABSENT) for f in NODE_BEHAVIOR_FIELDS}


# ------------------------------------------------------------------------------
# Forma canonica del workflow completo (con deteccion de colisiones)
# ------------------------------------------------------------------------------

def canonical_edges(wf):
    """Conjunto de aristas con nombres de nodo normalizados."""
    E = set()
    for src, cmap in (wf.get("connections") or {}).items():
        for ctype, arr in cmap.items():
            for out_i, lst in enumerate(arr or []):
                for c in (lst or []):
                    E.add((
                        norm_node_name(src),
                        ctype,
                        out_i,
                        norm_node_name(c.get("node")),
                        c.get("type"),
                        c.get("index", 0),
                    ))
    return E


def canonical_workflow(wf):
    """Devuelve un dict con la forma canonica y metadatos de integridad:
       nodes         : nombre_norm -> {type, typeVersion, params, behavior}
       edges         : conjunto de aristas normalizadas
       collisions    : lista de (nombre_norm, nombre_original) que colisionaron
       dup_original  : lista de nombres ORIGINALES duplicados
       n_nodes       : cantidad real de nodos
       wf            : referencia al workflow crudo
    """
    orig_names = [n.get("name") for n in wf.get("nodes", [])]
    dup_original = sorted({x for x in orig_names if orig_names.count(x) > 1})

    nodes = {}
    collisions = []
    for n in wf.get("nodes", []):
        key = norm_node_name(n.get("name"))
        if key in nodes:
            collisions.append((key, n.get("name")))
        nodes[key] = {
            "type": n.get("type"),
            "typeVersion": n.get("typeVersion"),
            "params": canonical_params(n),
            "behavior": node_behavior(n),
        }
    return {
        "nodes": nodes,
        "edges": canonical_edges(wf),
        "collisions": collisions,
        "dup_original": dup_original,
        "n_nodes": len(orig_names),
        "wf": wf,
    }


# ------------------------------------------------------------------------------
# Comparacion + reporte (con paths JSON y salvaguarda de impresion)
# ------------------------------------------------------------------------------

def _short(v):
    s = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
    # Salvaguarda de LEGIBILIDAD (no es clasificacion de secreto): truncar
    # literales muy largos en la salida. No cambia el resultado de la comparacion.
    s = re.sub(r"'[^']{48,}'", "'<literal-largo>'", s)
    s = re.sub(r"\"[^\"]{48,}\"", "\"<literal-largo>\"", s)
    if len(s) > 160:
        s = s[:157] + "..."
    return s


def diff_json(path, a, b, out):
    """Diff recursivo estructural. Acumula (path, detalle) en out."""
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a.keys()) | set(b.keys())):
            if k not in a:
                out.append((path + "." + k, "solo en B: %s" % _short(b[k])))
            elif k not in b:
                out.append((path + "." + k, "solo en A: %s" % _short(a[k])))
            else:
                diff_json(path + "." + k, a[k], b[k], out)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append((path, "longitud de lista distinta: A=%d B=%d" % (len(a), len(b))))
        for i in range(min(len(a), len(b))):
            diff_json(path + "[%d]" % i, a[i], b[i], out)
    else:
        if a != b:
            out.append((path, "A=%s | B=%s" % (_short(a), _short(b))))


def diff_jscode(node_name, code_a, code_b, out):
    """Diff linea a linea del jsCode NORMALIZADO."""
    la = (code_a or "").split("\n")
    lb = (code_b or "").split("\n")
    n = max(len(la), len(lb))
    for i in range(n):
        xa = la[i] if i < len(la) else "<sin linea>"
        xb = lb[i] if i < len(lb) else "<sin linea>"
        if xa != xb:
            out.append((
                "nodes[%s].parameters.jsCode:L%d" % (node_name, i + 1),
                "A=%s | B=%s" % (_short(xa), _short(xb)),
            ))


def compare(ca, cb, label_a, label_b):
    """Compara dos formas canonicas. Devuelve lista de diferencias funcionales."""
    nodes_a, edges_a = ca["nodes"], ca["edges"]
    nodes_b, edges_b = cb["nodes"], cb["edges"]
    diffs = []

    only_a = sorted(set(nodes_a) - set(nodes_b))
    only_b = sorted(set(nodes_b) - set(nodes_a))
    for k in only_a:
        diffs.append(("nodes[%s]" % k, "presente solo en %s" % label_a))
    for k in only_b:
        diffs.append(("nodes[%s]" % k, "presente solo en %s" % label_b))

    for k in sorted(set(nodes_a) & set(nodes_b)):
        na, nb = nodes_a[k], nodes_b[k]
        if na["type"] != nb["type"]:
            diffs.append(("nodes[%s].type" % k, "A=%s | B=%s" % (na["type"], nb["type"])))
        if na["typeVersion"] != nb["typeVersion"]:
            diffs.append(("nodes[%s].typeVersion" % k,
                          "A=%s | B=%s" % (na["typeVersion"], nb["typeVersion"])))

        # Campos de conducta (onError, disabled, etc.)
        for f in NODE_BEHAVIOR_FIELDS:
            if na["behavior"][f] != nb["behavior"][f]:
                diffs.append(("nodes[%s].%s" % (k, f),
                              "A=%s | B=%s" % (_short(na["behavior"][f]),
                                               _short(nb["behavior"][f]))))

        pa = dict(na["params"]); pb = dict(nb["params"])
        ca_code = pa.pop("jsCode", None)
        cb_code = pb.pop("jsCode", None)
        if (ca_code is None) != (cb_code is None):
            diffs.append(("nodes[%s].parameters.jsCode" % k, "presencia de jsCode difiere"))
        elif ca_code is not None:
            diff_jscode(k, ca_code, cb_code, diffs)
        diff_json("nodes[%s].parameters" % k, pa, pb, diffs)

    e_only_a = sorted(edges_a - edges_b)
    e_only_b = sorted(edges_b - edges_a)
    for e in e_only_a:
        diffs.append(("connections", "arista solo en %s: %s" % (label_a, e)))
    for e in e_only_b:
        diffs.append(("connections", "arista solo en %s: %s" % (label_b, e)))

    return diffs


# ------------------------------------------------------------------------------
# Chequeos por-workflow (integridad estructural, creds, settings, active)
# ------------------------------------------------------------------------------

def flavor_of(wf):
    """Ambiente del workflow: 'test' | 'ops' | None (por name o webhook path)."""
    name = wf.get("name", "") or ""
    if name.endswith("__OPS"):
        return "ops"
    if name.endswith("__TEST"):
        return "test"
    for n in wf.get("nodes", []):
        if n.get("type") == "n8n-nodes-base.webhook":
            p = (n.get("parameters") or {}).get("path", "") or ""
            if p.endswith("__OPS"):
                return "ops"
            if p.endswith("__TEST"):
                return "test"
    return None


PG_TYPE = "n8n-nodes-base.postgres"
PG_EXPECTED = 6
SETTINGS_KEYS = ["executionOrder", "binaryMode"]


def check_pg_credentials(wf):
    """Presencia de credencial en los 6 nodos PostgreSQL y flavor == ambiente.
    Devuelve (flavor, [problemas])."""
    flavor = flavor_of(wf)
    problems = []
    pg = [n for n in wf.get("nodes", []) if n.get("type") == PG_TYPE]
    if len(pg) != PG_EXPECTED:
        problems.append("cantidad de nodos PostgreSQL = %d (esperado %d)" % (len(pg), PG_EXPECTED))
    for n in pg:
        nm = n.get("name")
        creds = (n.get("credentials") or {}).get("postgres")
        if not creds or not creds.get("name"):
            problems.append("nodes[%s]: sin credencial postgres asignada" % nm)
            continue
        cname = creds.get("name", "")
        m = re.search(r"vita_supabase_(test|ops)", cname)
        if not m:
            problems.append("nodes[%s]: credencial sin flavor reconocible" % nm)
        elif flavor and m.group(1) != flavor:
            problems.append("nodes[%s]: credencial flavor '%s' != ambiente '%s'"
                            % (nm, m.group(1), flavor))
    return flavor, problems


def settings_signature(wf):
    s = wf.get("settings") or {}
    return {k: s.get(k, _ABSENT) for k in SETTINGS_KEYS}


# ------------------------------------------------------------------------------
# Chequeo de conducta requerida (el fix: gap-errors presentes)
# ------------------------------------------------------------------------------

REQUIRED_TOKENS = {
    "router1_crear": [
        "checkin_pisa_checkout_anterior", "checkout_pisa_checkin_posterior",
        "gap_checkin", "gap_checkout", "override_hora_invalido", "fecha_in_pasada",
    ],
    "router3_confirmar": [
        "checkin_pisa_checkout_anterior", "checkout_pisa_checkin_posterior",
        "gap_checkin", "gap_checkout",
    ],
}


def check_required_behavior(cworkflow):
    """Verifica que la conducta de gap-errors este presente. Devuelve [faltantes]."""
    nodes = cworkflow["nodes"]
    missing = []
    for nname, tokens in REQUIRED_TOKENS.items():
        node = nodes.get(nname)
        if not node:
            missing.append((nname, "NODO AUSENTE"))
            continue
        code = node["params"].get("jsCode", "") or ""
        for t in tokens:
            if t not in code:
                missing.append((nname, "falta token: %s" % t))
    return missing


# ------------------------------------------------------------------------------
# Evaluacion completa (orquestador) -> (exit_code, texto_reporte)
# ------------------------------------------------------------------------------

def evaluate(wf_ops, wf_tpl, wf_test, labels=("OPS_MOD", "TEMPLATE", "TEST"),
             names=None):
    """Corre TODOS los chequeos. Devuelve (exit_code:int, reporte:str)."""
    out = []
    def emit(s=""):
        out.append(s)

    fail = False
    c_ops = canonical_workflow(wf_ops)
    c_tpl = canonical_workflow(wf_tpl)
    c_test = canonical_workflow(wf_test)
    trip = [
        (labels[0], wf_ops, c_ops),
        (labels[1], wf_tpl, c_tpl),
        (labels[2], wf_test, c_test),
    ]
    names = names or {labels[0]: "(ops)", labels[1]: "(template)", labels[2]: "(test)"}

    emit("=" * 72)
    emit("VERIFICADOR A07  --  paridad funcional (read-only)")
    emit("=" * 72)
    for lab, wf, c in trip:
        emit("  %-8s : %s  (%d nodos)" % (lab, names.get(lab, ""), c["n_nodes"]))
    emit("")

    # --- 1) Integridad estructural: cantidad de nodos identica ---
    counts = {lab: c["n_nodes"] for lab, _, c in trip}
    if len(set(counts.values())) != 1:
        fail = True
        emit("[FALLA ESTRUCTURA] cantidad de nodos difiere: %s"
             % ", ".join("%s=%d" % (l, n) for l, n in counts.items()))

    # --- 1b) Nombres originales unicos + normalizados unicos (sin colisiones) ---
    for lab, wf, c in trip:
        if c["dup_original"]:
            fail = True
            emit("[FALLA ESTRUCTURA] %s: nombres de nodo ORIGINALES duplicados: %s"
                 % (lab, c["dup_original"]))
        if c["collisions"]:
            fail = True
            emit("[FALLA ESTRUCTURA] %s: colision de nombres NORMALIZADOS: %s"
                 % (lab, [k for k, _ in c["collisions"]]))
        if len(c["nodes"]) != c["n_nodes"]:
            fail = True
            emit("[FALLA ESTRUCTURA] %s: %d nodos -> %d nombres normalizados (colapso)"
                 % (lab, c["n_nodes"], len(c["nodes"])))
    if not fail:
        emit("[ESTRUCTURA] OK: %d nodos, nombres originales y normalizados unicos en los tres."
             % counts[labels[0]])

    # --- 2) active como ESTADO DE DESPLIEGUE (informativo; no afecta exit) ---
    emit("[DESPLIEGUE] active: " + ", ".join("%s=%s" % (lab, wf.get("active"))
                                             for lab, wf, _ in trip)
         + "   (informativo; versionables inactivos / vivos activos)")

    # --- 3) settings.executionOrder + settings.binaryMode iguales ---
    sigs = {lab: settings_signature(wf) for lab, wf, _ in trip}
    base_sig = sigs[labels[0]]
    settings_ok = True
    for lab in labels[1:]:
        if sigs[lab] != base_sig:
            fail = True
            settings_ok = False
            emit("[FALLA SETTINGS] %s.settings %s != %s.settings %s"
                 % (lab, sigs[lab], labels[0], base_sig))
    if settings_ok:
        emit("[SETTINGS] OK: %s en los tres." % base_sig)

    # --- 4) Credenciales PG: presencia en los 6 nodos + flavor == ambiente ---
    for lab, wf, _ in trip:
        flavor, probs = check_pg_credentials(wf)
        if probs:
            fail = True
            emit("[FALLA CREDENCIALES] %s (ambiente=%s):" % (lab, flavor))
            for p in probs:
                emit("   - " + p)
        else:
            emit("[CREDENCIALES] %s OK: 6 nodos PostgreSQL con credencial flavor '%s'."
                 % (lab, flavor))

    # --- 5) Nota HMAC (dummy sintetico; sin clasificacion por longitud) ---
    emit("[HMAC] El fallback del ternario en validar_firma_ts_rol es un DUMMY")
    emit("       SINTETICO de longitud fija, SIN valor operativo (solo preserva")
    emit("       longitud en los exports de trabajo). Se normaliza acotado a ese")
    emit("       ternario; no se compara ni se imprime. Los artefactos versionables")
    emit("       usan __PEGAR_SECRETO_O_USAR_VARIABLE__.")

    # --- 6) Conducta requerida (el fix: gap-errors) ---
    for lab, _, c in trip:
        miss = check_required_behavior(c)
        if miss:
            fail = True
            emit("[FALLA CONDUCTA] %s no maneja los gap-errors requeridos:" % lab)
            for nn, det in miss:
                emit("   - nodes[%s]: %s" % (nn, det))
    if not any(check_required_behavior(c) for _, _, c in trip):
        emit("[CONDUCTA] OK: gap-errors presentes en router1_crear y router3_confirmar (los tres).")

    emit("")

    # --- 7) Comparaciones cruzadas (funcional) ---
    pairs = [
        (c_ops, c_test, labels[0], labels[2]),
        (c_tpl, c_test, labels[1], labels[2]),
        (c_ops, c_tpl, labels[0], labels[1]),
    ]
    total_diffs = 0
    for ca, cb, la, lb in pairs:
        diffs = compare(ca, cb, la, lb)
        emit("-" * 72)
        emit("COMPARACION  %s  vs  %s" % (la, lb))
        emit("-" * 72)
        if not diffs:
            emit("  OK  --  sin diferencias funcionales.")
        else:
            total_diffs += len(diffs)
            for pth, det in diffs:
                emit("  DIFF  %s" % pth)
                emit("        %s" % det)
        emit("")
    if total_diffs:
        fail = True

    emit("=" * 72)
    ok = not fail
    if ok:
        emit("RESULTADO: PARIDAD FUNCIONAL CONFIRMADA  (exit 0)")
    else:
        emit("RESULTADO: DIFERENCIAS / FALLAS DETECTADAS  (exit 1)")
        emit("   diffs funcionales: %d" % total_diffs)
    emit("=" * 72)
    return (0 if ok else 1), "\n".join(out)


# ------------------------------------------------------------------------------
# Self-tests NEGATIVOS (exit 0 debe ser imposible ante cada mutacion)
# ------------------------------------------------------------------------------

def _find_node(wf, norm_target):
    for n in wf.get("nodes", []):
        if norm_node_name(n.get("name")) == norm_target:
            return n
    return None


def _mut_set_field(base_ops, norm_target, field, value):
    w = copy.deepcopy(base_ops)
    n = _find_node(w, norm_target)
    assert n is not None, "nodo %s no encontrado" % norm_target
    n[field] = value
    return w


def _mut_settings(base_ops, key, value):
    w = copy.deepcopy(base_ops)
    w.setdefault("settings", {})[key] = value
    return w


def _mut_add_node_distinct(base_ops):
    w = copy.deepcopy(base_ops)
    dup = copy.deepcopy(w["nodes"][0])
    dup["name"] = dup["name"] + "_DUP_TEST_ONLY"
    w["nodes"].append(dup)
    return w


def _mut_add_node_collision(base_ops):
    w = copy.deepcopy(base_ops)
    src = _find_node(w, "router1_crear")
    assert src is not None
    dup = copy.deepcopy(src)
    dup["name"] = "router1_crear1"  # normaliza a 'router1_crear' -> colision
    w["nodes"].append(dup)
    return w


def _mut_wrong_cred_flavor(base_ops):
    w = copy.deepcopy(base_ops)
    fl = flavor_of(w)
    opp = "test" if fl == "ops" else "ops"
    for n in w["nodes"]:
        if n.get("type") == PG_TYPE:
            n.setdefault("credentials", {}).setdefault("postgres", {})
            n["credentials"]["postgres"]["name"] = "vita_supabase_%s (reemplazar al importar)" % opp
            return w
    raise AssertionError("no hay nodo PostgreSQL para mutar")


def _mut_change_router_message(base_ops):
    """Cambio funcional de un literal de mensaje en router1_crear.
    Con la regex amplia eliminada, este cambio DEBE aparecer como diff."""
    w = copy.deepcopy(base_ops)
    n = _find_node(w, "router1_crear")
    assert n is not None
    c = n["parameters"]["jsCode"]
    needle = "sin disponibilidad en el rango"
    assert needle in c, "no se encontro el literal a mutar"
    n["parameters"]["jsCode"] = c.replace(needle, "MENSAJE_FUNCIONAL_CAMBIADO")
    return w


def _mut_change_router_errorcode(base_ops):
    """Cambio funcional de un codigo de error en router1_crear."""
    w = copy.deepcopy(base_ops)
    n = _find_node(w, "router1_crear")
    assert n is not None
    c = n["parameters"]["jsCode"]
    needle = "code:'payload_invalido'"
    assert needle in c, "no se encontro el code a mutar"
    n["parameters"]["jsCode"] = c.replace(needle, "code:'codigo_alterado'")
    return w


def _mut_only_hmac_dummy(base_ops):
    """Cambia SOLO el literal del fallback SECRET por otro literal de 64 chars.
    NO debe producir diff funcional (se normaliza) y NO debe ser tratado como
    'secreto real' (positivo, valida el enmascarado acotado y sin longitud)."""
    w = copy.deepcopy(base_ops)
    n = _find_node(w, VALIDAR_FIRMA)
    assert n is not None
    c = n["parameters"]["jsCode"]
    other = "z" * 64
    c2 = _SECRET_TERNARY_RE.sub(r"\1'" + other + r"'\2", c)
    assert c2 != c, "no se pudo alterar el fallback SECRET"
    n["parameters"]["jsCode"] = c2
    return w


def self_test(paths):
    ops = load(paths[0]); tpl = load(paths[1]); test = load(paths[2])

    lines = []
    def log(s=""):
        lines.append(s)

    log("=" * 72)
    log("SELF-TESTS  --  exit 0 debe ser IMPOSIBLE ante cada mutacion")
    log("=" * 72)
    log("Base: OPS=%s | TEMPLATE=%s | TEST=%s" % tuple(os.path.basename(p) for p in paths))
    log("")

    results = []  # (nombre, esperado, obtenido, ok)

    def run_case(name, mutated_ops, expect_fail, extra_check=None):
        code, report = evaluate(mutated_ops, tpl, test)
        got_fail = (code != 0)
        ok = (got_fail == expect_fail)
        if ok and extra_check is not None:
            ok = extra_check(report)
        results.append((name, expect_fail, got_fail, ok))
        log("[%s] %-46s esperado_falla=%s  obtuvo_falla=%s  exit=%d"
            % ("PASS" if ok else "FALLO", name, expect_fail, got_fail, code))

    # 0) POSITIVO: trio limpio -> NO falla
    run_case("POSITIVO trio limpio", ops, False)

    # Campos de conducta (requisito 4): cada cambio -> falla
    run_case("onError modificado",
             _mut_set_field(ops, "PG-1 crear_prereserva", "onError", "stopWorkflow"), True)
    run_case("alwaysOutputData modificado",
             _mut_set_field(ops, "PG-1 crear_prereserva", "alwaysOutputData", False), True)
    run_case("disabled agregado",
             _mut_set_field(ops, "router1_crear", "disabled", True), True)
    run_case("retryOnFail agregado",
             _mut_set_field(ops, "PG-1 crear_prereserva", "retryOnFail", True), True)
    run_case("maxTries agregado",
             _mut_set_field(ops, "PG-1 crear_prereserva", "maxTries", 5), True)
    run_case("waitBetweenTries agregado",
             _mut_set_field(ops, "PG-1 crear_prereserva", "waitBetweenTries", 1000), True)
    run_case("executeOnce agregado",
             _mut_set_field(ops, "router1_crear", "executeOnce", True), True)

    # settings (requisito 6): cada cambio -> falla
    run_case("settings.executionOrder modificado",
             _mut_settings(ops, "executionOrder", "v0"), True)
    run_case("settings.binaryMode modificado",
             _mut_settings(ops, "binaryMode", "filesystem"), True)

    # cantidad de nodos / colisiones (requisitos 1,2,3): -> falla
    run_case("nodo duplicado (cantidad)",
             _mut_add_node_distinct(ops), True)
    run_case("colision por norm_node_name (sufijo 1)",
             _mut_add_node_collision(ops), True)

    # credenciales PG (requisito 5): flavor equivocado -> falla
    run_case("credencial PG con flavor equivocado",
             _mut_wrong_cred_flavor(ops), True)

    # cambios funcionales en jsCode que la regex amplia podia ocultar -> falla
    run_case("cambio funcional de mensaje en router1",
             _mut_change_router_message(ops), True)
    run_case("cambio funcional de code en router1",
             _mut_change_router_errorcode(ops), True)

    # HMAC acotado y sin longitud (positivo): cambiar SOLO el dummy -> NO falla
    def _no_secret_language(report):
        low = report.lower()
        bad = ("secreto real" in low) or ("rotar" in low) or ("rotá" in low) \
              or ("advertencia seguridad" in low)
        return not bad
    run_case("HMAC: cambiar solo el dummy (no debe fallar ni marcar secreto)",
             _mut_only_hmac_dummy(ops), False, extra_check=_no_secret_language)

    log("")
    total = len(results)
    passed = sum(1 for _, _, _, ok in results if ok)
    log("-" * 72)
    log("SELF-TESTS: %d/%d correctos." % (passed, total))
    all_ok = (passed == total)
    log("RESULTADO SELF-TESTS: %s  (exit %d)"
        % ("TODOS OK" if all_ok else "HAY FALLOS", 0 if all_ok else 1))
    log("=" * 72)
    print("\n".join(lines))
    return 0 if all_ok else 1


# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

DEFAULTS = (
    "portal-a07-crear-reserva__OPS__CANDIDATO_SANITIZADO.json",
    "portal-a07-crear-reserva__TEMPLATE.json",
    "portal-a07-crear-reserva__TEST.json",
)


def _resolve_paths(args):
    if len(args) == 3:
        return tuple(args)
    if len(args) == 0:
        return DEFAULTS
    return None


def main():
    args = sys.argv[1:]

    if args and args[0] == "--self-test":
        paths = _resolve_paths(args[1:])
        if paths is None:
            print("Uso: python3 verificador_a07.py --self-test [OPS.json TEMPLATE.json TEST.json]")
            return 2
        for p in paths:
            if not os.path.isfile(p):
                print("ERROR: no existe el archivo: %s" % p)
                return 2
        return self_test(paths)

    paths = _resolve_paths(args)
    if paths is None:
        print("Uso: python3 verificador_a07.py [OPS.json TEMPLATE.json TEST.json]")
        print("     python3 verificador_a07.py --self-test [OPS.json TEMPLATE.json TEST.json]")
        return 2
    for p in paths:
        if not os.path.isfile(p):
            print("ERROR: no existe el archivo: %s" % p)
            return 2

    wf_ops = load(paths[0]); wf_tpl = load(paths[1]); wf_test = load(paths[2])
    names = {"OPS_MOD": paths[0], "TEMPLATE": paths[1], "TEST": paths[2]}
    code, report = evaluate(wf_ops, wf_tpl, wf_test, names=names)
    print(report)
    return code


if __name__ == "__main__":
    sys.exit(main())
