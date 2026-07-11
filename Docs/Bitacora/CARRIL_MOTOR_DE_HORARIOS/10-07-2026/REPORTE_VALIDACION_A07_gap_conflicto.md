# REPORTE DE VALIDACIÓN OFFLINE — A07 gap → conflicto (con prefijo de contrato)

**Frente:** `B1.3-cierre-integracion-TEST` · mapeo de gaps de turno a `conflicto` con message prefijado.
**Repo:** `github.com/francogg89-ai/vita-delta-reservas` · **HEAD baseline:** `9b013f2` (rama `main`).
**Alcance:** EXACTAMENTE 2 archivos. Gateway, canónico, bootstrap, E/F, OPS **NO se tocan**.
**Estado:** artefactos generados y validados offline. **Hard stop** — Franco ejecuta en TEST.

---

## 0. Discriminador aprobado (recordatorio del contrato)

A07 devuelve `code:'conflicto'`, `detail:null` para ambos gaps, con `message` = **prefijo estable + frase humana**:

- `checkin_pisa_checkout_anterior` → `gap_checkin: El check-in queda demasiado cerca del checkout anterior. Elegí un horario de entrada más tarde.`
- `checkout_pisa_checkin_posterior` → `gap_checkout: El check-out queda demasiado cerca del check-in posterior. Elegí un horario de salida más temprano.`

`CrearReserva.tsx` discrimina **solo** dentro de la rama `error.code === 'conflicto'` con `startsWith('gap_checkin:')` / `startsWith('gap_checkout:')` (NO `includes()`), y muestra **solo la frase humana** (strip del prefijo). Todo otro `conflicto`, incluido `no_disponible`, conserva EXACTO el texto histórico `Sin disponibilidad en ese rango (se solapa con una reserva, pre-reserva o bloqueo).` Como cualquier `conflicto` sin prefijo cae al texto histórico, **ningún código crudo del SP puede llegar al usuario**.

---

## 1. Archivos y anclas

| Archivo | Nodo/función | Ancla (`count==1` verificado) |
|---|---|---|
| `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json` | `router1_crear` | `  if (conflicto.includes(e)) return { ... 'sin disponibilidad en el rango' ... };` |
| idem | `router3_confirmar` | `if (e === 'conflicto_al_confirmar' || e === 'no_disponible') return [{ json: { recheck:false, envelope: {` |
| `Apps/portal-operativo/src/screens/CrearReserva.tsx` | `textoErrorReserva()` | bloque completo `if (error.code === 'conflicto') { return '...'; }` |

En ambos routers las ramas de gap se insertan **antes** del check al que caerían (genérico de `conflicto` en router1; default `estado_incierto` en router3), **sin** agregar los gaps al array `['no_disponible']`.

---

## 2. Hashes (SHA-256)

| Archivo | Baseline (HEAD `9b013f2`) | Parcheado |
|---|---|---|
| A07 template | `abee1d0c58e12b8b4ccb5d57b923fc17ffbde3dce4ebbd98b13bf18978609d26` | `3188bceb777b38dcc12d5aa8475cdb40fe89cb189257644c3b4a738c87cd6def` |
| CrearReserva.tsx | `cf411e1710bf98b863b64c6980c2dce88fba17881a85e70dacc85d9cb50f1db2` | `f0ce620b62188689ad434cacbdf8ba2f1601870deca3fd84cd93d9d75da5acb6` |

Cada patcher tiene el baseline y el hash parcheado **embebidos**: aborta si el archivo de entrada difiere del baseline (deriva) y verifica que su salida sea exactamente el hash parcheado. Resultado 100% reproducible.

---

## 3. Matriz de validación — resultados

### A. Estructural A07 — OK
```
JSON parseable: OK
router1_crear count : 1
router3_confirmar count: 1
router1_crear   : gap_checkin:=1  gap_checkout:=1  token_in=1  token_out=1
router3_confirmar: gap_checkin:=1  gap_checkout:=1  token_in=1  token_out=1
node --check router1 (jsCode como cuerpo de función): EXIT 0
node --check router3 (jsCode como cuerpo de función): EXIT 0
```
**Scope del diff (deep-compare vs HEAD):** claves top-level iguales · `connections` idénticas · `settings` idénticas · mismos nombres de nodos · **únicos nodos que difieren: `router1_crear`, `router3_confirmar`**, y en cada uno el único campo que cambia es `parameters.jsCode` (`id`/`type`/`position` idénticos). Diff crudo = 2 líneas (216 y 360, ambas `jsCode`). Sin cambios de IDs, conexiones, webhook, queries ni credentials placeholders.

### B. Harness `router1_crear` — 17/17 PASS
Ejecuta el `jsCode` real del template parcheado con mocks n8n (`$json`, `$('Code: derivar')`).
- `checkin_pisa_checkout_anterior` → `conflicto` + message exacto con prefijo `gap_checkin:` · `detail:null`
- `checkout_pisa_checkin_posterior` → `conflicto` + message exacto con prefijo `gap_checkout:`
- `no_disponible` → `conflicto` + `'sin disponibilidad en el rango'` (intacto)
- `fecha_in_pasada` → `payload_invalido` `'datos de reserva rechazados: fecha_in_pasada'` (intacto)
- `excede_capacidad` → `payload_invalido` (intacto)
- desconocido → `error_interno`
- éxito → `continuar:true`, `pg2_args` presente, `payload2.id_pre_reserva` e `idem`/`sev` conservados

### C. Harness `router3_confirmar` — 18/18 PASS
Camino que `crear_prereserva` normalmente NO alcanza (aislado). Mocks `$('router1_crear')` + `$('Code: derivar')`.
- ambos gaps → `conflicto` con prefijo correcto · `detail:null`
- `no_disponible` y `conflicto_al_confirmar` → `conflicto` `'conflicto de disponibilidad al confirmar'` (intacto)
- `estado_invalido` + `estado_actual:'convertida'` → `recheck:true` (sin envelope)
- desconocido → `estado_incierto`, `detail.ids_creados.id_pre_reserva` conservado
- éxito → `envelope.ok:true`, `data.id_reserva`, `idempotent_match:false`

### D. Gateway TEST — pendiente (lo ejecuta Franco)
Caso feliz · gap check-in · gap check-out · `no_disponible` · payload inválido. Para ambos gaps: `ok:false` · `error.code==='conflicto'` · NO `error_interno` · NO `estado_incierto` · NO `error_entorno` · message con su prefijo · envelope válido.

### E. Frontend — build + harness OK
```
tsc --noEmit (strict:true, noEmit:true): EXIT 0
npm run build (tsc && vite build): EXIT 0  (127 módulos, build OK)
```
Harness `textoErrorReserva` (función real extraída del `.tsx` parcheado) — **10/10 PASS**:
- `gap_checkin:` → SOLO la frase humana de check-in; NO muestra el prefijo ni el código crudo
- `gap_checkout:` → SOLO la frase humana de check-out; NO muestra el prefijo ni el código crudo
- `no_disponible` (message `'sin disponibilidad en el rango'`) → texto histórico
- `'conflicto de disponibilidad al confirmar'` → texto histórico
- `payload_invalido`/`fecha_in_pasada` → mensaje intacto
- otro código → cae a `mensajeUsuario` (fallback intacto)

Validación en UI viva (banner, tono `aviso`, que los gaps NO disparen el banner `estadoIncierto`, caso feliz crea) → la ejecuta Franco (E en TEST).

### F. Calendario/ODR — pendiente (lo ejecuta Franco)
Reserva rechazada por gap NO aparece · reserva feliz sí · re-pin read-only del ODR (`37009a32`) sin regresión.

---

## 4. Meta-validaciones de los patchers

| Prueba | Resultado |
|---|---|
| **Idempotencia** | Re-run sobre archivos ya parcheados → `Patch ya aplicado`, EXIT 0, sin cambios. |
| **Reproducibilidad** | Reset a HEAD → re-run → hashes de salida **idénticos** a los esperados; assertion de hash de salida pasó. |
| **Fail-closed (deriva)** | Ancla de `router1` alterada → `ABORTA: hash de entrada != baseline`, EXIT 1, **hash idéntico pre/post (no escribió)**. |

---

## 5. Clasificación legacy (sin parchear; recordatorio del diagnóstico)

Los cuatro son `manualTrigger` (solo "Execute" en el editor), **sin webhook**, `active:false/null` en el template → **históricos / dev-harness**, ninguno es caller operativo por HTTP. **A07 es el único workflow ruteado por gateway que llama a `crear_prereserva`/`confirmar_reserva`**; A10-MP llama a `registrar_pago(`, no a `confirmar_reserva`.

**Deuda explícita (no en este bloque):** hoy no existe path async vivo que confirme fuera de A07 (frente MercadoPago diferido, D-MP-01..11). Cuando ese frente se implemente, su workflow de auto-confirm necesitará el mismo mapeo gap → `conflicto`. **Salvedad:** el `active` del template es un snapshot; confirmá en n8n vivo antes de OPS que ninguno esté activo con trigger HTTP.

---

## 6. Riesgos

1. **Pin al baseline:** los patchers están clavados a HEAD `9b013f2` (hashes §2). Si el clone fresco trae estos dos archivos distintos, **el patcher aborta a propósito** — avisá y regenero contra el nuevo HEAD.
2. **Acoplamiento por prefijo:** el frontend depende de los prefijos `gap_checkin:` / `gap_checkout:` que emite A07. Son constantes de contrato; si se cambian, hay que cambiarlos en ambos lados. Documentado en ambos artefactos.
3. **router3 por gateway:** casi no se dispara vía A07 sincrónico (crear corta antes); la cobertura de router3-gap es el harness aislado C, no el gateway.
4. **Re-import del template:** debe **reemplazar** el A07 vivo en TEST (mismo webhook `portal-a07-crear-reserva__TEST`), no crear uno nuevo.
5. **Deuda MP:** el futuro auto-confirm async necesitará el mismo mapeo (§5).

---

## 7. Runbook para ejecutar en TEST (en orden)

> No ejecuté nada en n8n/Vercel/Supabase/git/OPS. Todo lo de abajo lo corrés vos.

1. **Clone fresco** de `main` HEAD.
2. **Aplicar patchers** desde la raíz del repo:
   ```bash
   python3 patch_a07_gap_conflicto.py
   python3 patch_crear_reserva_gap_conflicto.py
   ```
   (Si alguno aborta por hash, el clone difiere del baseline: avisame.)
3. **Verificar hashes** (deben coincidir con §2):
   ```bash
   sha256sum Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json \
             Apps/portal-operativo/src/screens/CrearReserva.tsx
   ```
4. **Validaciones estáticas** (reproducir A/B/C/E):
   ```bash
   # node --check (envolviendo el jsCode como cuerpo de función, modelo n8n)
   node harness_router1_crear.mjs   <ruta_clone>/Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json
   node harness_router3_confirmar.mjs <ruta_clone>/Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json
   node harness_texto_error_reserva.mjs <ruta_clone>/Apps/portal-operativo/src/screens/CrearReserva.tsx
   cd Apps/portal-operativo && npx tsc --noEmit && npm run build
   ```
5. **Deploy:**
   - **n8n:** importá el A07 parcheado **reemplazando** el workflow vivo en TEST (webhook `portal-a07-crear-reserva__TEST`; no crear uno nuevo). **Gateway NO se toca.**
   - **Frontend:** commit + push de `CrearReserva.tsx` a `main` (Vercel auto-deploy).
6. **Pruebas en vivo:** matriz **D** (gateway), **E** (UI), **F** (calendario/ODR).
7. **Cierre TEST** y **hard stop**. No consolides canónico/bootstrap ni acuñes D-/L- acá.

---

## 8. Entregables (en este paquete)

| Archivo | Qué es |
|---|---|
| `patch_a07_gap_conflicto.py` | Patcher A07 (2 routers), determinista/fail-closed. |
| `patch_crear_reserva_gap_conflicto.py` | Patcher frontend (`textoErrorReserva`). |
| `portal-a07-crear-reserva__TEMPLATE.PATCHED.json` | Template A07 resultante (= salida del patcher, hash §2). |
| `CrearReserva.PATCHED.tsx` | Screen resultante (= salida del patcher, hash §2). |
| `harness_router1_crear.mjs` | Harness B (ejecuta jsCode real). |
| `harness_router3_confirmar.mjs` | Harness C (ejecuta jsCode real, camino aislado). |
| `harness_texto_error_reserva.mjs` | Harness frontend (ejecuta función real). |
| `REPORTE_VALIDACION_A07_gap_conflicto.md` | Este reporte. |
