# CIERRE — A26 `disponibilidad.cabana` + calendario de rango A07/A08 → promoción a OPS

**Fecha:** 2026-07-01 · **Estado:** 🟢 CERRADO (con pendientes trackeados, canónico diferido a propósito).

## Alcance

Cierra la **feature A26 completa**, end-to-end:

1. **Backend — A26 `disponibilidad.cabana`** (read action, construida y validada en **TEST**): lectura pura sobre `obtener_disponibilidad_rango`, guardrail de UX para los date-pickers de A07/A08.
2. **Frontend — calendario de rango en A07/A08** (Bloque C, mergeado a `main`): grilla mensual custom backed por A26.
3. **Promoción a OPS** — **OPS-A** (wrapper `portal-a26-disponibilidad__OPS`) + **OPS-B** (A26 en el gateway `portal-api` OPS).

**NO cubre / queda fuera a propósito:** bump de canónico (A26 no agrega estructura → cero impacto canónico); los guards de fechas pasadas del motor de horarios (**B2/B3**) y su canonización — trackeados abajo, se cierran/canonizan en el frente de horarios.

---

## Qué se hizo y resultado

### Backend A26 (TEST) — Opción B, sin DDL
- Wrapper n8n firmado `portal-a26-disponibilidad` + entrada de gateway TEST, revalidando HMAC/`ts`/rol/action-binding/ambiente. **Lectura pura**, sin `injectActor` ni `isWrite`, **sin funciones nuevas ni DDL** (canónico intacto): reusa `obtener_disponibilidad_rango`.
- **Arquitectura Opción B:** un **CTE gate** con `CROSS JOIN LATERAL` hace que `obtener_disponibilidad_rango` **no se ejecute** cuando la cabaña es inválida/inactiva (CTE vacía → la set-returning function queda `never executed`, verificado por `EXPLAIN ANALYZE`). Evita el patrón `alwaysOutputData` propagando ítems vacíos.
- **Contrato:** `data:{dias:[{fecha:'YYYY-MM-DD', estado, id_cabana, hora_checkin_base, hora_checkout_base}]}`, **una fila por noche en `[fecha_desde, fecha_hasta)`** (excluye `fecha_hasta`); `estado ∈ {disponible, checkout_disponible, ocupada, bloqueada}`; cabaña inválida/inactiva → `no_encontrado`; payload inválido → `payload_invalido`. Validator reject-unknown `{id_cabana, fecha_desde, fecha_hasta}`, `id_cabana` entero positivo, `hasta > desde`, span ≤ 366. Roles `vicky/socio`.

### Frontend — calendario de rango en A07/A08 (mergeado a `main`)
- Componente **custom** `CalendarioRango` (grilla mensual), **sin dependencia nueva** (deps siguen en 4). Colorea por estado; `ocupada`/`bloqueada` no seleccionables; `checkout_disponible` seleccionable solo como check-in; rango que cruza una noche ocupada no confirmable. Autoridad del backend; el frontend previene.
- Fecha "hoy" en **zona AR** vía `Intl.DateTimeFormat('en-CA',{timeZone:'America/Argentina/Buenos_Aires'})` (espeja `fecha_hoy_ar()`); navegación de mes por aritmética UTC. `toISOString` sería incorrecto cerca de medianoche AR.
- Validado: `tsc --noEmit --strict` EXIT 0, `npm run build` EXIT 0, **22/22** en harness de lógica pura.

### OPS-A — wrapper A26 a OPS
- `portal-a26-disponibilidad__OPS` (path `__OPS`, credencial OPS, HMAC OPS). Solo cambios de entorno; lógica/SQL/render/HMAC-placeholder intactos. El wrapper A26 **no tiene candado TEST-only** (`verificar_acceso` compara `ambiente_esperado` vs `leer_ambiente`, no literal `!=='test'`).
- **Smoke directo (OPS, read-only): PASS=13 FAIL=0 SKIP=2** (T5/T6 ocupación/checkout como SKIP permitido). Cero escrituras.

### OPS-B — A26 en el gateway OPS
- Diff **100% aditivo** (+38 líneas, 0 borrados): `const SPAN_MAX_A26_GW = 366;` + `payloadDisponibilidadCabana` (**extraído verbatim del gateway TEST**) **antes** del CATALOG (sin temporal-dead-zone); entrada `'disponibilidad.cabana' → portal-a26-disponibilidad__OPS`. Las **14 actions previas intactas**; CORS/HMAC/JWT/`Deno.serve` sin tocar; CATALOG OPS 14→15.
- Validación: `esbuild` EXIT 0 (sintaxis) + `tsc --noEmit --strict` EXIT 0 sobre snippet autocontenido (tipos + TDZ).
- **Smoke gateway (OPS, read-only): PASS=15 FAIL=0** (vicky/socio ok `dias=5`; jenny→`rol_no_permitido`; sin JWT→`no_autorizado`; action→`accion_desconocida`; cabaña 999999→`no_encontrado`; invertido/span>366/`id_cabana` 0·neg·string/clave desconocida/falta `fecha_hasta`/array→`payload_invalido`; META allowlist limpia). Cero escrituras. **Grilla OPS des-rota.**

---

## Decisiones acuñadas (no reabrir)

**Backend A26**
- **D-C-74** — A26 `disponibilidad.cabana` = **lectura pura** sobre `obtener_disponibilidad_rango`, guardrail UX de A07/A08; **sin DDL, canónico intacto** (SELECT/CTE inline en el wrapper). Roles `vicky/socio` (jenny no).
- **D-C-75** — **Opción B**: CTE gate + `CROSS JOIN LATERAL` para que `obtener_disponibilidad_rango` **no se ejecute** con cabaña inválida/inactiva (verificado `EXPLAIN ANALYZE` = `never executed`). No usar `alwaysOutputData` en el precheck.
- **D-C-76** — Contrato A26: una fila por **noche** en `[fecha_desde, fecha_hasta)` (excluye `fecha_hasta`); `estado ∈ {disponible, checkout_disponible, ocupada, bloqueada}`; inválida→`no_encontrado`, payload malo→`payload_invalido`. Validator reject-unknown `{id_cabana, fecha_desde, fecha_hasta}`, `id_cabana` entero positivo seguro, span ≤ 366.
- **D-C-77** — `hora_checkin_base`/`hora_checkout_base` viajan en el contrato pero **no se usan** en esta etapa (sin validación de recambio/horaria); reservados para el frente de horarios.

**Frontend (calendario A07/A08)**
- **D-FE-31** — Calendario de rango **custom** (Opción B): grilla mensual propia, **sin dependencia nueva** (descarta input nativo y react-day-picker), fechas como strings YMD, backed por A26. Autoridad del backend; el frontend previene selección inválida.
- **D-FE-32** — Fecha "hoy" en **zona AR** vía `Intl.DateTimeFormat('en-CA',{timeZone:'America/Argentina/Buenos_Aires'})` (espeja `fecha_hoy_ar()`); **`toISOString` es incorrecto cerca de medianoche AR**; navegación/aritmética de mes por UTC.
- **D-FE-33** — A08 **espeja el backend exactamente** (asimétrico con A07, subordinado a D-FE-23): A07 bloquea `fecha_in < hoyAR`; A08 bloquea `fecha_hasta <= hoyAR` (min = mañanaAR) pero **permite `fecha_desde` pasada** (bloquearla sería más estricto que el backend → violaría D-FE-23). Half-open `[desde,hasta)`; checkout tope en la primera noche ocupada (back-to-back); cross-month valida **todas** las noches del rango.
- **D-FE-34** — Guard anti-stale del efecto de merge (`if idCabana===null return; if data.dias.some(d=>d.id_cabana!==idCabana) return`), **verificado seguro** leyendo `obtener_disponibilidad_rango`: la matriz (`cabanas_activas CROSS JOIN dias`) estampa `id_cabana` en **cada** noche (nunca null para cabaña válida); el `number|null` del contrato es solo padding de cabaña inválida → `no_encontrado`, nunca un `dia`.

**Promoción a OPS**
- **D-PROMO-A26-01** — A26 a OPS por el **patrón Carril C** (wrapper `__OPS` + entrada de CATALOG en el gateway OPS), **sin DDL ni bump de canónico** (A26 no agrega estructura; reusa `obtener_disponibilidad_rango` canónica).
- **D-PROMO-A26-02** — Wrapper OPS `portal-a26-disponibilidad__OPS`: path `__OPS`, credencial OPS, HMAC OPS. El wrapper A26 **no** lleva candado TEST-only (`verificar_acceso` compara `ambiente_esperado` vs `leer_ambiente`; contrasta con A10-MP, que tenía `!=='test'` — D-PROMO-C-04).
- **D-PROMO-A26-03** — Gateway OPS: `disponibilidad.cabana → portal-a26-disponibilidad__OPS`, validator `payloadDisponibilidadCabana` **extraído verbatim** del gateway TEST, **antes del CATALOG** (sin TDZ). Diff **100% aditivo** (+38, 0 borrados); 14 actions previas intactas; CORS/HMAC/JWT/`Deno.serve` sin tocar; CATALOG 14→15.
- **D-PROMO-A26-04** — Smokes OPS **read-only** con **guard anti-OPS (exit 3) antes de login** (D-PROMO-C-10); secretos por **env var** (nunca hardcodeados ni impresos — el smoke directo de TEST tenía el HMAC pegado; en OPS por env); T10 invertido (manda `ambiente_esperado='test'` para forzar `ambiente_incorrecto` en OPS). Resultado: directo **13/0/2**, gateway **15/0**.
- **D-PROMO-A26-05** *(contingencia)* — OPS Vercel **auto-deploya desde `main`** → el calendario (Bloque C) llegó a OPS **antes** que A26 → grilla rota en OPS; se priorizó OPS-A/B para des-romper. **Excepción a D-FE-23 aceptada temporalmente** (frontend OPS más estricto que backend OPS en fechas pasadas) hasta que B2/B3 aterricen en OPS. Sin rollback de Vercel.
- **D-PROMO-A26-06** — **Canonización de los guards de horarios (B2/B3) diferida** hasta el cierre del frente motor de horarios **completo** (evita bumps repetidos sobre `crear_prereserva`/`crear_bloqueo` aún en evolución — Bloque 3 `overrides_operativos`/override manual, recambio horario). B2/B3 a OPS = cambio **out-of-band tracked** (patrón v1.8.1). **La excepción D-FE-23 se cierra al aterrizar B2/B3 en OPS, independiente del canónico.**

## Lecciones

- **L-C-26** — `CROSS JOIN LATERAL` con dependencia de una CTE hace que Postgres **saltee** la set-returning function cuando la CTE está vacía (`EXPLAIN ANALYZE` → `never executed`): gate de disponibilidad sin ejecutar `obtener_disponibilidad_rango` para cabaña inválida. Pariente del anti-`alwaysOutputData`.
- **L-C-27** — `node --check` sobre nodos n8n con `await` top-level da **falso positivo** si se valida como script plano; hay que envolver el cuerpo en `async function` (modelo de ejecución de n8n).
- **L-FE-10** — El guard anti-stale de un efecto que mergea datos asíncronos debe verificarse **contra la fuente** (aquí `obtener_disponibilidad_rango` estampa `id_cabana` por noche) antes de confiar en un `some(d=>d.x!==y)`; el `number|null` del contrato era solo padding de cabaña inválida, no un caso real.
- **L-PROMO-A26-01** — Un Edge Function **Deno** (`jsr:` + `Deno.*`) **no valida con `tsc` completo** sin `deno` instalado; validar tipos/TDZ por **snippet autocontenido** (tipos + validator + CATALOG) + **`esbuild`** de sintaxis sobre el archivo entero + orden textual del validator.
- **L-PROMO-A26-02** — Convención de sufijos **asimétrica**: en OPS **todos** los wrappers llevan `__OPS` (lecturas y escrituras); en TEST las lecturas van **sin** sufijo. Verificar contra el gateway OPS real, no asumir.

## No-impacto verificado

- **Cero DDL / canónico intacto (v1.9.0):** A26 reusa `obtener_disponibilidad_rango`; no agrega tablas/funciones/estructura. La promoción OPS-A/B es routing + transporte.
- **Sin tocar otras actions:** las 14 actions previas del gateway OPS quedaron byte-idénticas; CORS/HMAC/JWT/`Deno.serve` intactos.
- **Anti-OPS:** todos los smokes read-only; cero escrituras, cero consumo de secuencias.

---

## Pendientes trackeados (no bloqueantes de este cierre)

1. **Excepción D-FE-23 — VIVA temporalmente.** Frontend OPS bloquea fechas pasadas; backend OPS aún no (B2/B3 solo en TEST). **Se cierra al aterrizar B2/B3 en OPS** (independiente del canónico).
2. **B2/B3 a OPS — en curso por Franco, en paralelo.** Dos piezas ya validadas en TEST: (a) **SQL** (B2: `fecha_hoy_ar()` + guards `fecha_in_pasada`/`rango_pasado` en `crear_prereserva`/`crear_bloqueo`, 3 funciones `CREATE OR REPLACE`, environment-agnostic, corre en OPS tal cual); (b) **string en `payloadInv`** por wrapper (B3: A07 `router1_crear` += `'fecha_in_pasada'`; A08 `router_bloqueo` += `'rango_pasado'`, por edición directa de nodo, sin re-import → sin tocar HMAC/credenciales). Estado resultante: guards **out-of-band tracked** (vivos TEST+OPS, canónico aún v1.9.0). Pre-flight recomendado: **huella** de `crear_prereserva`/`crear_bloqueo` OPS == canónico v1.9.0 (sin drift) antes de reemplazar.
3. **Canonización — diferida al cierre del frente de horarios completo.** Un solo bump (v1.9.0 → v1.9.1+) que capture la forma **final** de `crear_prereserva`/`crear_bloqueo` + `fecha_hoy_ar()` + los bloques restantes del motor (overrides/override manual/recambio), con regeneración del bootstrap y cierre formal del frente (acuñar `D-HOR-*`/`L-HOR-*`, verificar huella TEST=OPS).
4. **Smoke visual read-only de OPS-B — pendiente de confirmación de Franco** (A07/A08: elegir cabaña → grilla; cambio rápido de cabaña sin contaminación; sin reservas/bloqueos reales).

---

## Propagación a satélites (bloques listos para pegar)

### → `Docs/Operacional/ESTADO_ACTUAL_VITA_DELTA.md` (nueva **Etapa actual**; la de v1.9.0 pasa a **Etapa previa**)

> **Etapa actual:** A26 `disponibilidad.cabana` + **calendario de rango en A07/A08** — **construida en TEST y promovida a OPS** — **cerrada 2026-07-01**. Nueva **lectura pura** del portal (`disponibilidad.cabana`, guardrail UX de los date-pickers de A07/A08): wrapper n8n firmado que **reusa `obtener_disponibilidad_rango`** (sin funciones nuevas, **sin DDL, canónico v1.9.0 intacto**), con arquitectura **Opción B** (CTE gate + `CROSS JOIN LATERAL` → la set-returning function queda `never executed` con cabaña inválida/inactiva, verificado por `EXPLAIN ANALYZE`); contrato de una fila por **noche** en `[fecha_desde, fecha_hasta)`, `estado ∈ {disponible, checkout_disponible, ocupada, bloqueada}`, inválida→`no_encontrado`; roles vicky/socio. En el **frontend** (mergeado a `main`) se cableó un **calendario de rango custom** (`CalendarioRango`, grilla mensual, **sin dependencia nueva**) en A07/A08: colorea por estado, no deja seleccionar `ocupada`/`bloqueada`, tope de checkout en la primera noche ocupada (back-to-back); fecha "hoy" en **zona AR** vía `Intl.DateTimeFormat('en-CA',…AR)` (espeja `fecha_hoy_ar()`; `toISOString` sería incorrecto cerca de medianoche); A08 **espeja el backend exactamente** (asimétrico con A07 y subordinado a **D-FE-23**: permite `fecha_desde` pasada, bloquea `fecha_hasta <= hoyAR`). Promoción a OPS en dos bloques: **OPS-A** wrapper `portal-a26-disponibilidad__OPS` (path/credencial/HMAC OPS, **sin candado TEST-only**) — **smoke directo 13/0/2**; **OPS-B** A26 en el gateway `portal-api` OPS, diff **100% aditivo** (+38, 0 borrados; validator `payloadDisponibilidadCabana` **verbatim** del gateway TEST, antes del CATALOG; 14 actions previas intactas; CORS/HMAC/JWT/`Deno.serve` sin tocar; CATALOG 14→15; `esbuild` + `tsc --strict` snippet EXIT 0) — **smoke gateway 15/0**. Con OPS-B la **grilla de A07/A08 en OPS quedó des-rota**. **Contingencia:** OPS Vercel auto-deploya desde `main` → el calendario llegó a OPS antes que A26 (grilla rota) → se priorizó OPS-A/B; **excepción a D-FE-23 aceptada temporalmente** (frontend OPS más estricto que backend en fechas pasadas) **hasta que B2/B3 aterricen en OPS**. Smokes OPS read-only con **guard anti-OPS (exit 3)** y secretos por env (el smoke directo de TEST tenía el HMAC hardcodeado). **Decisiones D-C-74…77, D-FE-31…34, D-PROMO-A26-01…06; lecciones L-C-26/27, L-FE-10, L-PROMO-A26-01/02.** **Sin cambios en el canónico `6B_SCHEMA_SQL.md` v1.9.0** (A26 no agrega estructura), sin tocar otras actions ni escrituras. **Pendientes trackeados:** (1) excepción D-FE-23 viva hasta B2/B3 en OPS; (2) **B2/B3 a OPS en paralelo** (SQL de guards `fecha_hoy_ar()`/`fecha_in_pasada`/`rango_pasado` + string en `payloadInv` de A07/A08 — out-of-band tracked, patrón v1.8.1); (3) **canonización diferida** al cierre del frente de horarios completo (un solo bump con la forma final de `crear_prereserva`/`crear_bloqueo`); (4) smoke visual de OPS-B pendiente de confirmación. Cierre: `A26_CALENDARIO_PROMOCION_OPS_CIERRE.md`. Próxima etapa: **motor de horarios** (continuar el frente; B2/B3 a OPS cierran D-FE-23; canonizar al final).

### → `Docs/Operacional/DECISIONES_NO_REABRIR.md` (agregar al final del bloque de decisiones)

*(Insertar el bloque **D-C-74…77**, **D-FE-31…34** y **D-PROMO-A26-01…06** tal como figura arriba en "Decisiones acuñadas", en el formato `- **D-ID** — texto.`)*

### → `Docs/Operacional/Lecciones_Aprendidas.md` (agregar al final)

*(Insertar **L-C-26/27**, **L-FE-10**, **L-PROMO-A26-01/02** tal como figura arriba en "Lecciones", en el formato `- **L-ID** — texto.`)*

---

## Artefactos

- **OPS-A:** `portal-a26-disponibilidad__OPS.json`, `A26_smoke_directo_OPS.ps1`, `A26_smoke_oracle_OPS.sql`, `A26_OPS_A_RUNSHEET.md`.
- **OPS-B:** `portal-api_OPS_index_A26.ts`, `A26_GW_smoke_OPS.ps1`, `A26_OPS_B_RUNSHEET.md`.
- **Frontend (en `main`):** `src/lib/fecha.ts`, `src/lib/disponibilidad.ts`, `src/ui/CalendarioRango.tsx` (+ edits en `contratos.ts`, `CrearReserva.tsx`, `CrearBloqueo.tsx`).

## Kickoff próxima etapa

**Frente motor de horarios** — continuar donde estaba (Bloque 3: `overrides_operativos` + override manual; recambio horario). **En paralelo**, Franco promueve **B2/B3 a OPS** (cierra la excepción D-FE-23). **Al cerrar el frente completo**, un solo bump de canónico (v1.9.0 → v1.9.1+) con la forma final de `crear_prereserva`/`crear_bloqueo` + `fecha_hoy_ar()`, regeneración del bootstrap y cierre formal del frente. La feature **A26 + calendario** queda **cerrada y en OPS**; no se reabre.
