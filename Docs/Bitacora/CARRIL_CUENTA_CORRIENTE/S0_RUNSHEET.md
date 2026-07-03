# Runsheet — Sub-bloque 0: `pct_operativo` → `configuracion_general`

Frente **Carril A / Retiro** — paso previo. Mueve el `0.25` hardcodeado a una clave de
config leída con validación fuerte, **sin fallback silencioso**. Cierra completo
**TEST → smokes → OPS → cierre** antes de arrancar Sub-bloque 1 (retiro).

> División de trabajo: Claude genera y valida; **Franco ejecuta** (SQL Editor, n8n, git).
> Un paso por vez: correr, reportar, verificar, seguir.

## Mapa del Sub-bloque 0

| Paso | Qué | Dónde | Estado |
|---|---|---|---|
| **S0.1** | seed `pct_operativo` + helper `pct_operativo_vigente()` + verificación fuerte | TEST (SQL Editor) | **artefacto listo (este)** |
| S0.2 | A27/A28: `cuenta_corriente_viva(NULL, 0.25)` → `(NULL, pct_operativo_vigente())` + snapshot pre/post + smoke | TEST | siguiente turno (depende de S0.1 verde) |
| S0.3 | Promoción OPS: seed + helper + re-import A27/A28 `__OPS` + smoke `__OPS` | OPS | tras TEST verde |
| S0.4 | Cierre: bump canónico **v1.10.1** + bootstrap kit + satélites + `D-*`/`L-*` | canónico | tras OPS verde |

---

## Alcance y NO-alcance de S0.1 (aclaración conceptual)

**S0.1 resuelve:**
- Una **fuente única validada** para el porcentaje operativo **vigente actual** (`pct_operativo` + `pct_operativo_vigente()`).
- La **eliminación del hardcode `0.25`**: deja A27/A28/retiro preparados para leer desde configuración.

**S0.1 NO resuelve** (queda para un bloque posterior):
- La **historización / vigencia por período** del porcentaje operativo.

### Pendiente explícito — "pct operativo periodizado / vigencia futura"

Hoy `cuenta_corriente_viva(hasta, pct)` re-deriva **todos** los meses con un **único** pct. Consecuencia: cambiar el valor de `pct_operativo` **recalcularía retroactivamente** todos los meses no congelados en la vista viva (L1/L2/retiro).

**Requisito futuro:** un cambio de porcentaje (bajar / subir / eliminar) debe aplicar **hacia adelante desde ese momento/período**, **sin** recalcular meses anteriores.

**Bloque posterior necesario** (antes de cambiar el porcentaje real en operación):
- `pct_operativo` **periodizado**: tabla de vigencias (`[periodo_desde, pct]`) o función `pct_operativo_para_periodo(p_periodo date)`.
- `cuenta_corriente_viva`/`detalle` pasan a resolver el pct **por período** internamente (cada mes con su pct vigente), en vez de recibir un único pct → cambio a las funciones canónicas de lectura, con su propio frente + bump.
- Compatibilidad forward: `pct_operativo_vigente()` = "el vigente hoy" (= `pct_operativo_para_periodo(hoy)`); el retiro, que reusa `cuenta_corriente_viva`, hereda la periodización **sin cambios propios**.

**Guardrail aplicado:** `pct_operativo` **nace con `editable=false`** (y `tipo_valor='numeric'`); **no debe cambiarse en operación** hasta implementar el bloque posterior de `pct_operativo` periodizado / vigencia futura. Un cambio recomputaría retroactivamente todo lo no congelado (solo lo congelado por snapshot queda inmune). Nota honesta: `editable` es una **convención** — el motor no la fuerza (no hay trigger que bloquee un `UPDATE`) —, así que el flag lo señala explícito pero la disciplina operativa sigue siendo no tocar el valor.

Se formaliza en el cierre (S0.4) como candidato en `Pendiente_pre_produccion.md` (familia `P-CC-*`), **no** como algo resuelto por S0.1.

---

## S0.1 — seed + helper + verificación (ejecutable ahora, TEST)

**Archivo:** `S0_1_pct_config_TEST.sql`
**Dónde:** SQL Editor del proyecto **TEST** (`bdskhhbmcksskkzqkcdp`), **nada seleccionado** (corre todo).
**Qué hace:** gate anti-OPS → `DROP+CREATE pct_operativo_vigente()` (validación fuerte, `REVOKE` espejo de `cuenta_corriente_viva`) → seed idempotente de `pct_operativo='0.25'` → verificación (Ajuste A) → fila de reporte. Todo en una transacción; si `ambiente != test`, aborta y no persiste nada.

**Validación previa hecha por Claude (evidencia):**
- `pglast`: 8 statements, sin error de sintaxis.
- Corrida real en PostgreSQL 16 con fixture: seed inicial `filas_insertadas=1`, re-run `=0`; el helper devuelve `[pct_config_invalido]`/`[pct_config_ausente]` (controlado, **nunca** cast crudo) ante `abc` / `2` / `0,25` / `1e-1` / vacío / ausente; re-run con `0.30` no exige `0.25`; gate con `ambiente=ops` aborta sin cambiar nada.

**Resultado esperado en TEST:**
```
NOTICE:  S0.1 OK: pct_operativo=0.25 tipo=numeric editable=f (filas_insertadas=1) ; pct_operativo_vigente()=0.25
 estado  | valor_txt | tipo_valor | editable | pct_vigente | ambiente
---------+-----------+------------+----------+-------------+----------
 S0.1_OK | 0.25      | numeric    | f        |        0.25 | test
```
(Si ya existía la clave: `filas_insertadas=0`, resto igual.)

**Qué reportar:** la fila `S0.1_OK` + el NOTICE. Con eso verifico y paso a S0.2.

**Rollback de S0.1** (aditivo, limpio):
```sql
BEGIN;
DO $$ BEGIN IF (SELECT valor FROM configuracion_general WHERE clave='ambiente')
  IS DISTINCT FROM 'test' THEN RAISE EXCEPTION 'rollback S0.1: ambiente != test'; END IF; END $$;
DROP FUNCTION IF EXISTS public.pct_operativo_vigente();
DELETE FROM configuracion_general WHERE clave='pct_operativo';
COMMIT;
```
> No hagas el rollback si S0.2 ya cambió A27/A28 a usar el helper (romperías las lecturas). Orden inverso: primero revertir wrappers, después S0.1.

---

## S0.2 — A27/A28 a config (artefactos listos; Ajuste B)

Tres artefactos (validados por Claude: patcher corrido en scratch, SQL con pglast + lógica en PG, smoke ASCII/LF modelado sobre el OPS verificado):

1. **`S0_2_identidad_pct_TEST.sql`** — prueba determinística (independiente de los datos) de que `cuenta_corriente_viva`/`detalle` con `pct_operativo_vigente()` **≡** con `0.25`. Es la base numérica del cambio.
2. **`S0_2_patch_wrappers.py`** — patcher (anclas `count==1` + prueba de reversa + JSON válido, EOL preservado) sobre los 4 wrappers (`portal-a27/a28 __TEMPLATE.json` y `__OPS.json`): cambia **solo** la llamada `…(NULL, 0.25)` / `…, 0.25)` → `…pct_operativo_vigente()`. El `0.25` del comentario queda intacto.
3. **`S0_2_smoke_directo_TEST.ps1`** — lee A27+A28 directo al webhook TEST (sin sufijo, L-CC-06), firma HMAC. **Falla dura (`exit 1`)** si A27 o A28 no dan `ok:true` (imprime el código y **no** emite hash); si ambas dan `ok:true`, recién ahí emite `HASH_S0.2` determinístico (pre vs post) y `SMOKE_S0.2_OK`. GUARD anti-OPS.

**Orden de ejecución (TEST):**
1. Correr **`S0_2_identidad_pct_TEST.sql`** (SQL Editor TEST, nada seleccionado). Esperado: `S0.2_IDENTIDAD_OK` + NOTICE `viva y detalle identicos`.
2. Editar `Secret` en **`S0_2_smoke_directo_TEST.ps1`** y correrlo → esperar `SMOKE_S0.2_OK` y **anotar `HASH_S0.2` (PRE)**. (Si algo no da `ok:true`, el smoke corta con `exit 1` y no hay hash.)
3. En un **clon fresco**, desde la raíz: `python3 S0_2_patch_wrappers.py` → `TODOS OK` (4 wrappers).
4. **Re-importar** en n8n TEST los `portal-a27/a28 __TEMPLATE.json` parcheados (o editar la línea del nodo SQL en la UI: `0.25` → `pct_operativo_vigente()`). Activar.
5. Correr **`S0_2_smoke_directo_TEST.ps1`** de nuevo → `SMOKE_S0.2_OK` + **`HASH_S0.2` (POST)**.

**Criterio de éxito S0.2:** (a) identidad SQL OK; (b) `HASH_S0.2` **idéntico** pre/post; (c) el smoke imprime `SMOKE_S0.2_OK` en ambas corridas (falla dura si A27/A28 no dan `ok:true`). Los `__OPS.json` quedan parcheados para el re-import de S0.3.

---

## S0.3 — Promoción OPS (Ajuste B: "lo mismo para OPS" + rollback)

A27/A28 están **vivos en OPS** con `0.25` hardcodeado. Runsheet propio (patrón `PROMO_CC_OPS`):
1. **Snapshot pre-OPS** (read-only): baseline A27/A28 `__OPS` por socio.
2. **Seed + helper en OPS** (SQL Editor OPS `lpiatqztudxiwdlcoasv`): versión OPS del S0.1 (gate `ambiente=ops`; `CREATE OR REPLACE` en el canónico, `DROP+CREATE` si se corre suelto).
3. **Re-import wrappers OPS**: `portal-a27-cuenta-corriente__OPS.json` / `portal-a28-...__OPS.json` ya parcheados (leen `pct_operativo_vigente()`). Import from File, activar.
4. **Smoke `__OPS`** (GUARD OPS): números **idénticos** al snapshot pre-OPS.
5. **Rollback OPS claro**: re-importar la versión previa de `portal-a27/a28__OPS.json` (con `0.25` hardcodeado) — reversible sin tocar SQL. El seed/helper quedan (inocuos); si se quisiera revertir, DROP del helper + DELETE de la clave **después** de revertir los wrappers.

Orden inquebrantable: **seed+helper → wrappers → smoke**. La clave debe existir en OPS **antes** de que los wrappers la lean (sin fallback → si falta, marcador/error visible, no cálculo silencioso).

---

## S0.4 — Cierre (canónico / bootstrap)

- **Bump v1.10.0 → v1.10.1** (aditivo): PARTE B suma la clave `pct_operativo` al seed de `configuracion_general` (conteo de claves +1; precedente `horizonte_disponibilidad_dias`, D-7A-03); PARTE C suma la función `pct_operativo_vigente()`.
- **Bootstrap kit** (`bootstrap_entorno_nuevo_v1.9.0` → nueva rev): agregar la clave al seed y la función; **`03_VERIFY_FINAL_ENTORNO.sql`** suma la aserción de existencia+validez de `pct_operativo` y de la función.
- **Wrappers A27/A28**: viven fuera del canónico (v1.10.0 lo dice explícito); se versionan sus JSON `__OPS`.
- **Pendiente `P-CC-*` (formalizar)**: "pct operativo periodizado / vigencia futura" — S0.1 resuelve la fuente única vigente, **no** la vigencia por período; ver sección "Alcance y NO-alcance de S0.1". Debe cerrarse antes de cambiar el porcentaje real en operación.
- **`D-*`/`L-*`**: candidatos (no acuñar hasta el cierre): pct a config sin fallback; helper con validación fuerte + errores parseables; regex `[.]` setting-independiente. Propagación a los 6 satélites en un pase.

---

## Riesgos / rollback (Sub-bloque 0)

| Riesgo | Mitigación | Rollback |
|---|---|---|
| Clave faltante en el entorno (sin fallback) rompe lecturas | Seed **antes** de S0.2/S0.3; verificador de existencia | Re-seed idempotente; mientras falta: error controlado visible |
| Valor cargado inválido por operación | Helper valida formato+rango, error parseable | Corregir el valor; el helper no explota |
| S0.3 edita wrappers **vivos en OPS** | Snapshot idéntico pre/post + GUARD OPS en smoke | Re-import wrapper previo (`0.25` hardcodeado) |
| `CREATE OR REPLACE` en SQL Editor (RLS espuria) | En TEST/OPS sueltos: `DROP+CREATE`; canónico: `CREATE OR REPLACE` | N/A |
