# S0_CIERRE.md — Sub-bloque 0: `pct_operativo` a `configuracion_general`

**Fecha de cierre:** 2026-07-03
**Canónico:** `6B_SCHEMA_SQL.md` v1.10.0 → **v1.10.1** (aditivo)
**Frente:** Cuenta Corriente de socios — preparación del frente de escritura (retiros)
**Alcance:** mover el porcentaje operativo (`0.25`) de estar hardcodeado en los wrappers A27/A28 a una clave parametrizada de `configuracion_general` (nace con `editable=false` como guardrail, ver P-CC-5), leída por un helper con validación fuerte y **sin fallback silencioso**. Cambio **output-neutral** verificado en TEST y OPS.

---

## 1. Qué se hizo

`pct_operativo` (0.25) estaba hardcodeado en el SQL de A27/A28 (D-CC-03). Se lo movió a `configuracion_general` y se creó `pct_operativo_vigente()`, que lo lee y valida. A27/A28 (y el futuro frente de retiros) pasan a leer el helper en lugar del literal. El cambio no altera ningún número: se verificó por identidad SQL determinística y por hash pre/post del webhook directo, idéntico en TEST y OPS.

**Sub-etapas:** S0.1 (seed + helper en TEST) → S0.2 (wrappers a helper en TEST) → S0.3 (promoción a OPS) → **S0.4 (este cierre: canónico + D/L + satélites)**.

---

## 2. Evidencia (verde en TEST y OPS)

**S0.1 — seed + helper (TEST):**
```
S0.1_OK | 0.25 | numeric | false | 0.25 | test
```

**S0.2 — wrappers a helper (TEST):**
- Identidad SQL: `S0.2_IDENTIDAD_OK | 0.25 | test` (viva y detalle con `pct_operativo_vigente()` ≡ con `0.25`).
- Patcher: 4 wrappers (A27/A28 TEMPLATE+OPS), 1 cambio c/u, JSON válido, reversa == original, EOL LF preservado.
- Hash directo **pre == post**: `7a438553ae42c1bb7c06ac3d74bcd71fe2675c9fb86745c2338016fb212e85e6` (`SMOKE_S0.2_OK` en ambas corridas; A27/A28 `ok:true`).

**S0.3 — promoción OPS:**
```
S0.3_OK | 0.25 | numeric | f | 0.25 | ops
```
- Hash directo **pre == post**: `7e075aa9c21fdb7c906b960db844bdd70a794eedf83bcb76b56d60683a19c9e0` (`SMOKE_S0.3_OK` en ambas; A27/A28 `ok:true`).

**Cadena de validación (todos los artefactos):** pglast → harness PostgreSQL local → TEST → OPS. El cuerpo del helper es **byte-idéntico** en TEST, OPS y canónico.

---

## 3. Decisiones acuñadas

- **D-CC-13** — `pct_operativo` movido a `configuracion_general` (clave `pct_operativo`=`0.25`, `tipo_valor='numeric'`, `editable=false`), leído por `pct_operativo_vigente()` **sin fallback silencioso**. Lo consumen A27/A28 (acciones `cuenta_corriente.al_dia`/`cuenta_corriente.detalle`) y el futuro frente de escritura/retiros. `editable=false` es guardrail hasta el bloque de pct periodizado (P-CC-5): cambiarlo hoy re-liquidaría retroactivamente meses pasados.
- **D-CC-14** — El helper valida **fail-fast** con errores parseables (`[pct_config_ausente]`/`[pct_config_invalido]`), **no** `COALESCE` a un default. Divergencia deliberada con el patrón histórico de `configuracion_general` (los horarios usan `COALESCE` a hardcoded, Bloque 13/D-7A): un `pct` mal cargado corrompería el **reparto de plata**, así que se prefiere abortar visible a calcular con un valor silenciosamente incorrecto.

## 4. Lecciones acuñadas

- **L-CC-09** — Regex de decimal `^[0-9]+([.][0-9]+)?$` con clase de caracter `[.]` en vez de `\.`, para no depender de `standard_conforming_strings`; rechaza texto, coma, notación científica y signos.
- **L-CC-10** — Cambiar la **fuente** de un parámetro (hardcoded → config) se verifica **output-neutral** con doble prueba: (a) identidad SQL determinística (la función con el helper ≡ con el literal, independiente de los datos) + (b) hash SHA256 pre/post del webhook directo. Hash idéntico pre/post ⇒ el edit del wrapper es neutral por construcción (S0.2 TEST `7a4385…`; S0.3 OPS `7e075a…`).
- **L-CC-11** — pglast valida sintaxis pero **no** semántica; para PL/pgSQL y SQL embebido se requiere un harness real en PostgreSQL local (o equivalente). Ya detectó bugs que pglast no agarraba: un `SELECT cg.valor` sin `FROM` y un comentario faltante en el cuerpo de una función (ambos en S0.3). Refuerza la cadena pglast → PG local → TEST → OPS: nunca saltear niveles.

---

## 5. Canónico v1.10.1 (aditivo)

Aplicado por `S0_4A_patch_canonico.py` (7 ediciones, anclas `count==1` + prueba de reversa, EOL preservado). Las funciones CC (`cuenta_corriente_viva`/`detalle`) ya estaban desde v1.10.0; v1.10.1 agrega:

- **PARTE C** — `pct_operativo_vigente()` (`CREATE OR REPLACE`, estilo canónico L-CC-07; cuerpo byte-idéntico al deployado) antes de `cuenta_corriente_viva`, con su `REVOKE EXECUTE` en la sección de hardening agrupada.
- **C13** — seed `pct_operativo` (`'0.25'`, `tipo_valor='numeric'`, `editable=false`, `ON CONFLICT DO NOTHING`) junto al marcador `ambiente`. Primera clave de `configuracion_general` con `tipo_valor` poblado.
- **Cabecera + changelog** — versión a v1.10.1, frase en el párrafo de estado, sección `## RESUMEN DE CAMBIOS v1.10.0 → v1.10.1`.

**Nota de nombres:** existe además una **columna** `pct_operativo` en `liquidaciones_periodo` (el pct **congelado** de cada snapshot). No colisiona con la **clave** de config (el pct **vivo**): namespaces distintos.

---

## 6. Wrappers A27/A28 (housekeeping del commit)

Los 4 JSON de wrappers quedaron **parcheados** por el patcher de S0.2 (leen `pct_operativo_vigente()`) y **promovidos** (TEST re-importado en S0.2, OPS re-importado en S0.3). Deben entrar en el commit de S0.4 para que git refleje lo vivo en n8n:
- `Workflows/n8n/Supabase/portal-a27-cuenta-corriente__TEMPLATE.json`
- `Workflows/n8n/Supabase/portal-a28-cuenta-corriente-detalle__TEMPLATE.json`
- `Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/portal-a27-cuenta-corriente__OPS.json`
- `Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/portal-a28-cuenta-corriente-detalle__OPS.json`

---

## 7. Deuda consciente y pendientes (se aplican en S0.4-B)

- **P-CC-3 — CERRADO.** `pct_operativo` movido a `configuracion_general` (este cierre).
- **P-CC-4 — NO se cierra; deuda consciente.** Redacción:
  > **P-CC-4 — Regenerar el bootstrap kit (deuda consciente).** El canónico está en **v1.10.1** pero el kit sigue en `bootstrap_entorno_nuevo_v1.9.0/`, rezagado. Deuda acumulada: **v1.10.0** (`cuenta_corriente_viva`, `cuenta_corriente_detalle` + su `REVOKE`) y **v1.10.1** (`pct_operativo_vigente()` + su `REVOKE` + seed `pct_operativo`). **Timing:** regenerar cuando cierre el frente completo de cuenta corriente (escritura/retiros + snapshot mensual + L3), a la versión final del canónico. **Riesgo aceptado y acotado mientras no se cree un entorno nuevo desde el kit.** Si hubiera que bootstrappear antes del cierre completo, se debe aplicar el kit `v1.9.0` y luego completar manualmente, desde el canónico vigente, las funciones CC, el helper y el seed faltantes.
- **P-CC-2 — refinamiento (foto mensual).** La foto mensual/snapshot no es solo saldos por socio; debe congelar la **cascada completa del mes** — ingresos, gastos, pasos de cascada, matriz/incidencias y resultado por socio. Es histórico/auditoría, **no** condición para retirar.
- **P-CC-5 — NUEVO.** `pct_operativo` periodizado / vigencia futura: cualquier cambio de porcentaje debe aplicar **hacia adelante**, sin recalcular retroactivamente meses anteriores (tabla de vigencias o `pct_operativo_para_periodo(p_periodo date)`; `cuenta_corriente_viva/detalle` resolverían el pct por período internamente). Hasta tener ese bloque, `pct_operativo` queda `editable=false` y **no debe cambiarse en operación**.

---

## 8. Próximo paso

- **S0.4-B** — patchers de satélites (DECISIONES +D-CC-13/14; Lecciones +L-CC-09/10/11; Pendiente: cerrar P-CC-3, reescribir P-CC-4, refinar P-CC-2, nuevo P-CC-5, sección CERRADO 2026-07-03; ESTADO_ACTUAL; CLAUDE.md; README n8n) + prompt de kickoff.
- **Luego:** frente de escritura/retiros (P-CC-2) — diseño ya avanzado (validación contra saldo vivo, `registrar_retiro_desde_saldo_vivo` + `portal_registrar_retiro`, `portal_idempotencia_cc`, gateway A29).
