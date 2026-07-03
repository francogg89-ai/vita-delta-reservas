#!/usr/bin/env python3
# ============================================================================
# S0_4A_patch_canonico.py  --  Sub-bloque 0.4-A (cierre) -- canonico v1.10.0 -> v1.10.1
#
# Edita Docs/Implementacion/6B_SCHEMA_SQL.md (7 ediciones, todas aditivas):
#   1. Campo **Version:** 1.10.0 -> 1.10.1
#   2. Marcador "Canonico vigente: v1.10.0" -> v1.10.1
#   3. Frase v1.10.1 en el parrafo de estado
#   4. Nueva seccion "## RESUMEN DE CAMBIOS v1.10.0 -> v1.10.1" (newest-first)
#   5. Funcion pct_operativo_vigente() en PARTE C (antes de cuenta_corriente_viva)
#   6. REVOKE del helper en la seccion agrupada de hardening de la PARTE C
#   7. Seed pct_operativo en C13 (tras el marcador ambiente)
#
# El CUERPO del helper (RETURNS..$fn$) es BYTE-IDENTICO al deployado en TEST/OPS
# (S0.1/S0.3); solo cambia CREATE -> CREATE OR REPLACE + comentario de cabecera y
# el REVOKE va agrupado (estilo canonico, L-CC-07: objeto identico). Las funciones
# CC (viva/detalle) YA estan en el canonico desde v1.10.0.
#
# Anclas count==1 + prueba de reversa por edicion + EOL preservado. El SQL insertado
# es ASCII (paridad con lo deployado); la prosa del changelog usa acentos (estilo doc).
#
# USO: desde la raiz de un clon fresco: python3 S0_4A_patch_canonico.py
# ============================================================================

import sys

PATH = "Docs/Implementacion/6B_SCHEMA_SQL.md"

# ---- piezas nuevas ---------------------------------------------------------

HELPER_BLOCK = """-- pct_operativo_vigente -- pct operativo unico vigente desde configuracion_general (clave pct_operativo),
-- con validacion fuerte y errores parseables; SIN fallback silencioso (D-CC-13/D-CC-14). Lo consumen las
-- funciones de cuenta corriente (viva/detalle) y el futuro frente de escritura/retiros (P-CC-2).
CREATE OR REPLACE FUNCTION public.pct_operativo_vigente()
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $fn$
DECLARE
  v_txt text;
  v_num numeric;
BEGIN
  SELECT valor INTO v_txt
    FROM configuracion_general
   WHERE clave = 'pct_operativo';

  IF NOT FOUND THEN
    RAISE EXCEPTION '[pct_config_ausente] falta la clave pct_operativo en configuracion_general';
  END IF;

  IF v_txt IS NULL THEN
    RAISE EXCEPTION '[pct_config_invalido] pct_operativo es NULL';
  END IF;

  v_txt := btrim(v_txt);

  IF v_txt = '' THEN
    RAISE EXCEPTION '[pct_config_invalido] pct_operativo vacio';
  END IF;

  -- decimal valido: digitos, opcionalmente punto + digitos ([.] evita depender de
  -- standard_conforming_strings). Rechaza texto, notacion cientifica, coma, signos.
  IF v_txt !~ '^[0-9]+([.][0-9]+)?$' THEN
    RAISE EXCEPTION '[pct_config_invalido] pct_operativo no es decimal valido: %', v_txt;
  END IF;

  v_num := v_txt::numeric;

  IF v_num < 0 OR v_num > 1 THEN
    RAISE EXCEPTION '[pct_config_invalido] pct_operativo fuera de [0,1]: %', v_num;
  END IF;

  RETURN v_num;
END
$fn$;

"""

HELPER_REVOKE = ("REVOKE EXECUTE ON FUNCTION public.pct_operativo_vigente()"
                 " FROM PUBLIC, anon, authenticated, service_role;")

SEED_BLOCK = """
-- C13.1-bis pct operativo (contabilidad, D-NEG-01); tipada + no editable (D-CC-13; guardrail hasta P-CC-5)
INSERT INTO configuracion_general (clave, valor, tipo_valor, descripcion, categoria, editable)
VALUES ('pct_operativo', '0.25', 'numeric',
        'Porcentaje operativo sobre ingreso cobrado neto de gastos operativos (D-NEG-01); '
        'usado en el reparto de la cuenta corriente (L1/L2/retiro) y persistido en cada snapshot. '
        'editable=false: no cambiar en operacion hasta el bloque de pct_operativo periodizado / vigencia futura.',
        'contabilidad', FALSE)
ON CONFLICT (clave) DO NOTHING;"""

CHANGELOG_SECTION = """## RESUMEN DE CAMBIOS v1.10.0 \u2192 v1.10.1

Bump menor **aditivo** que mueve el porcentaje operativo (`0.25`) de estar hardcodeado en los wrappers A27/A28 a una clave de `configuracion_general`, le\u00edda por un helper con validaci\u00f3n fuerte y **sin fallback silencioso**:

- **Nueva funci\u00f3n `pct_operativo_vigente()`** (PARTE C, antes de `cuenta_corriente_viva`): lee la clave `pct_operativo` y la valida (existe / no NULL / no vac\u00eda / decimal por regex `^[0-9]+([.][0-9]+)?$` / rango `[0,1]`), abortando con errores parseables `[pct_config_ausente]` / `[pct_config_invalido]`. Sin `COALESCE` a un default (D-CC-14): un pct mal cargado corromper\u00eda el reparto de plata, mejor abortar visible. `REVOKE EXECUTE` en la secci\u00f3n de hardening de la PARTE C.
- **Nueva clave de seed `pct_operativo`** en `configuracion_general` (C13): `valor='0.25'`, `tipo_valor='numeric'`, `editable=false` (D-CC-13; primera clave con `tipo_valor` poblado). `editable=false` es guardrail hasta el bloque de pct periodizado (P-CC-5): cambiarlo hoy re-liquidar\u00eda retroactivamente meses pasados.
- **Wrappers A27/A28** (viven fuera del can\u00f3nico): pasan a leer `cuenta_corriente_viva(NULL, pct_operativo_vigente())` y `cuenta_corriente_detalle(<mes>, pct_operativo_vigente())` en lugar del `0.25` hardcodeado. Cambio **output-neutral** verificado por doble prueba (identidad SQL determin\u00edstica + hash SHA256 pre/post del webhook directo), id\u00e9ntico en TEST y OPS (S0.2/S0.3, L-CC-10). Promovido a OPS el 2026-07-03; el can\u00f3nico se bumpea una sola vez al cierre.

**Nota \u2014 bootstrap kit (deuda consciente P-CC-4):** el kit sigue en `bootstrap_entorno_nuevo_v1.9.0/`, rezagado respecto de este can\u00f3nico. La deuda acumulada incluye v1.10.0 (`cuenta_corriente_viva`, `cuenta_corriente_detalle` + su `REVOKE`) y v1.10.1 (`pct_operativo_vigente()` + `REVOKE` + seed `pct_operativo`). Se regenerar\u00e1 al cierre del frente completo de cuenta corriente (escritura/retiros + snapshot mensual + L3), salvo necesidad real de crear un entorno nuevo antes.

"""

MARKER_SENTENCE = (" **v1.10.1 mueve el porcentaje operativo a `configuracion_general`** "
                   "(clave `pct_operativo`, D-CC-13) y agrega el helper `pct_operativo_vigente()` "
                   "a la PARTE C; los wrappers A27/A28 pasan a leer el pct desde config (aditivo, "
                   "output-neutral verificado por hash TEST=OPS, promovido a OPS 2026-07-03).")

# ---- ediciones: (label, old, new) -- new puede contener old (insercion) ----

EDITS = [
    ("1. campo Version",
     "**Versi\u00f3n:** 1.10.0",
     "**Versi\u00f3n:** 1.10.1"),

    ("2. marcador Canonico vigente",
     "Can\u00f3nico vigente: **`6B_SCHEMA_SQL.md v1.10.0`**",
     "Can\u00f3nico vigente: **`6B_SCHEMA_SQL.md v1.10.1`**"),

    ("3. frase v1.10.1 en parrafo de estado",
     "de julio 2026. La base (Partes A y B) refleja el estado alineado DEV/TEST/OPS de v1.7.3",
     "de julio 2026." + MARKER_SENTENCE + " La base (Partes A y B) refleja el estado alineado DEV/TEST/OPS de v1.7.3"),

    ("4. seccion changelog v1.10.0->v1.10.1",
     "## RESUMEN DE CAMBIOS v1.9.0 \u2192 v1.10.0",
     CHANGELOG_SECTION + "## RESUMEN DE CAMBIOS v1.9.0 \u2192 v1.10.0"),

    ("5. funcion helper en PARTE C",
     "-- cuenta_corriente_viva -- saldo de cuenta corriente ACUMULADO EN VIVO por socio desde el piso",
     HELPER_BLOCK + "-- cuenta_corriente_viva -- saldo de cuenta corriente ACUMULADO EN VIVO por socio desde el piso"),

    ("6. REVOKE del helper (agrupado)",
     "REVOKE EXECUTE ON FUNCTION public.cuenta_corriente_viva(p_hasta_fecha date, p_pct_operativo numeric) FROM PUBLIC, anon, authenticated, service_role;",
     "REVOKE EXECUTE ON FUNCTION public.cuenta_corriente_viva(p_hasta_fecha date, p_pct_operativo numeric) FROM PUBLIC, anon, authenticated, service_role;\n" + HELPER_REVOKE),

    ("7. seed pct_operativo en C13",
     "VALUES ('ambiente', 'dev',\n"
     "        'Marcador de entorno para identidad de Carril B. Valor por-entorno: dev/test/ops. Default dev para bootstrap del can\u00f3nico.', 'infra', FALSE)\n"
     "ON CONFLICT (clave) DO NOTHING;",
     "VALUES ('ambiente', 'dev',\n"
     "        'Marcador de entorno para identidad de Carril B. Valor por-entorno: dev/test/ops. Default dev para bootstrap del can\u00f3nico.', 'infra', FALSE)\n"
     "ON CONFLICT (clave) DO NOTHING;" + SEED_BLOCK),
]


def main():
    with open(PATH, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    orig = text

    for label, old, new in EDITS:
        n = text.count(old)
        if n != 1:
            print("FALLA count==1: '%s' -> ancla aparece %d veces" % (label, n))
            sys.exit(1)
        if new in text:
            print("FALLA: '%s' -> el texto nuevo ya esta presente (ya parcheado?)" % label)
            sys.exit(1)
        before = text
        text = before.replace(old, new)
        # prueba de reversa: revertir esta unica edicion reconstruye el estado previo
        if text.replace(new, old) != before:
            print("FALLA prueba de reversa: '%s'" % label)
            sys.exit(1)
        print("OK: %s" % label)

    if text == orig:
        print("FALLA: sin cambios netos")
        sys.exit(1)

    with open(PATH, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print("\nTODOS OK: 6B_SCHEMA_SQL.md v1.10.0 -> v1.10.1 (7 ediciones aditivas).")


if __name__ == "__main__":
    main()
