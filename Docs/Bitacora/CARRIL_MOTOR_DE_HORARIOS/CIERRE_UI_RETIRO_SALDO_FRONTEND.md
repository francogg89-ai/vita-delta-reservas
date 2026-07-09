# CIERRE — Portal Operativo · UI del retiro ("Retirar saldo") · frontend-only

- **Frente:** Portal Operativo Interno — pantalla de escritura del retiro de saldo (socio).
- **Tipo:** **frontend-only** (backend/gateway/wrapper de A29 ya cerrados en OPS; este frente expone la UI).
- **Repo:** `github.com/francogg89-ai/vita-delta-reservas` · `main` @ HEAD `142ec4d` (canónico **v1.12.0**).
- **Estado:** **CERRADO FUNCIONALMENTE EN TEST** (piloto real por Franco, 2026-07-09).
- **Canónico:** **NO se bumpea** — el frente no toca SQL/gateway/n8n. Sigue en **v1.12.0**.
- **Acción de gateway consumida:** `cuenta_corriente.retirar` (A29) · **ESCRITURA, socio-only**.
- **Lectura companion:** `cuenta_corriente.al_dia` (A27/L1) para saldo, reconsulta post-éxito y verificación post-incierto.

---

## 1. Resumen ejecutivo

Se expuso en el Portal Operativo la pantalla **"Retirar saldo"**, que permite a un **socio logueado** registrar un retiro de dinero contra su **saldo vivo**, con confirmación previa, prevalidación de monto, manejo de errores de negocio (saldo insuficiente), y tratamiento explícito de `estado_incierto` sin doble retiro. El frente es **100% presentación**: el backend, el gateway y el wrapper del retiro ya estaban cerrados en OPS, y A02 ya exponía la acción para socios; sólo faltaba la UI, su entrada de menú y su ruta.

El circuito **UI → Vercel TEST → `portal-api` → A29 → wrapper n8n → DB** quedó verificado extremo a extremo con retiros reales en TEST, asientos correctos en `movimientos_socio`, idempotencia sin duplicados y saldo L1 actualizado. Validado con `tsc --noEmit --strict` (EXIT 0) y `npm run build` (EXIT 0).

---

## 2. Alcance real cerrado

**Incluido (frontend):**
- Pantalla de escritura del retiro con formulario → resumen → confirmación.
- Entrada de presentación en el registry (grupo `socios`, orden 30) y ruta `/socios/retirar`.
- Botón de acceso desde la pantalla L1 `CuentaCorriente.tsx` (gateado por `acciones` de A02).
- Tipo de contrato de la respuesta de A29 en el frontend.
- Prevalidación cliente (espejo del gateway), bloqueo duro por sobre-retiro y por saldo ≤ 0, fail-closed si no se identifica el saldo propio.
- Manejo de `saldo_insuficiente` (con `detail`), `payload_invalido`, `conflicto`, familia B y `estado_incierto`.

**Explícitamente FUERA (no tocado):**
- Backend, gateway `portal-api`, wrappers n8n, SQL, Supabase, TEST/OPS a nivel de datos/estructura, bootstrap kit, canónico `6B_SCHEMA_SQL.md`, git remoto.
- L3 histórico, primera foto real OPS / cierre asistido, reembolsos, Mercado Pago, web pública, bot.

---

## 3. Archivos frontend modificados

Todo bajo `Apps/portal-operativo/src/`:

| Archivo | Cambio |
|---|---|
| `screens/RetirarSaldo.tsx` | **Nuevo.** Pantalla de escritura del retiro (form → resumen → confirmar; estados de éxito/error/incierto; fail-closed de saldo). |
| `lib/contratos.ts` | **+tipo** `RegistrarRetiroData { id_movimiento: number; idempotente: boolean }` (forma exacta del `data` de éxito de A29). |
| `lib/actionRegistry.ts` | **+entrada** `cuenta_corriente.retirar` → `{ grupo:'socios', orden:30, ruta:'/socios/retirar', label:'Retirar saldo' }` (sólo presentación). |
| `app/rutas.tsx` | **+import** de `RetirarSaldo` y **+entrada** en `PANTALLAS` (`'cuenta_corriente.retirar' → RetirarSaldo`). |
| `screens/CuentaCorriente.tsx` | **+botón** "Retirar saldo" (link a `/socios/retirar`) en el header, visible sólo si `contexto.acciones` incluye la acción. |

`git status --short` del cierre: exactamente estos 5 archivos, nada fuera de `Apps/portal-operativo/src/`.

---

## 4. Decisiones D-FE (candidatas a acuñar en este cierre)

Máximo D-FE existente en el repo: **D-FE-36**. Este cierre propone acuñar **D-FE-37 … D-FE-45**.

- **D-FE-37 — Fail-closed de saldo propio.** L1 (`cuenta_corriente.al_dia`) devuelve TODOS los socios y el cliente no recibe `id_socio`; la fila propia se identifica por **nombre normalizado** (`lower(btrim(contexto.nombre)) === lower(btrim(fila.socio))`, invariante SB0). Si no hay match **único** (0 o >1) o el saldo llega `null`, **no hay formulario ni submit**; mensaje "No pudimos verificar tu saldo disponible. Reintentá o avisá al administrador." No se permite retiro a ciegas para una operación de plata real.
- **D-FE-38 — Confirmación previa de dos fases** dentro del componente (formulario → resumen → "Confirmar retiro"), sin librerías; estado en React.
- **D-FE-39 — Prevalidación `monto ≤ saldo` con bloqueo duro** (botón "Continuar" `disabled`) cuando el saldo propio está identificado, y **bloqueo si `saldo ≤ 0`** ("No tenés saldo disponible para retirar"). El backend sigue siendo la autoridad final (VD001); la prevalidación es sólo UX.
- **D-FE-40 — Doble punto de entrada** (ítem de menú `socios`/30 + botón desde `CuentaCorriente.tsx`), con **visibilidad decidida por A02/`acciones`, sin hardcodear rol** en el frontend. La ruta la protege además `RutaProtegida`.
- **D-FE-41 — Sin borrador persistente** en el form del retiro (form corto y sensible; nada de `sessionStorage`).
- **D-FE-42 — `medio_pago`: allowlist en cliente** (`efectivo` → "Efectivo", `transferencia_bancaria` → "Transferencia bancaria"), validado por pertenencia al set real, no sólo "no vacío".
- **D-FE-43 — Tarjeta de éxito:** muestra `id_movimiento`, monto, medio, marca "ya estaba registrado" si `idempotente:true`, y el **saldo reconsultado** de L1; el saldo se muestra con **prioridad de `ccError` antes que la fila** (ver §6) para no pintar valores stale.
- **D-FE-44 — `estado_incierto`:** acción **primaria "Verificar saldo"** que sólo hace `refetch` de L1 (sin reintento automático bajo ningún caso); acción **secundaria "Reintentar este mismo retiro"** que reusa la **misma** `idempotency_key` (`{reintento:true}`, no duplica si ya se registró), deshabilitada sin `ultimoPayload` o mientras `enviando`; y **flag `saldoVerificadoTrasIncierto`** que impide mostrar cualquier saldo hasta que haya una verificación **posterior al intento**.
- **D-FE-45 — Contrato de payload:** `monto` viaja como **STRING** (`form.monto.trim()`), **nunca** `Number(monto)`; `idempotency_key` viaja como **sibling** del payload (transporte `'sibling'` de `useEnviar`). Reafirmación frontend de D-A29-1 / D-CC-20 (monto textual por precisión de plata).

Se reutiliza (no se reacuña) **D-FE-23** (validación cliente espeja el gateway, nunca más estricta) y **D-FE-20/21** (ciclo de idempotency_key en `useEnviar` y bloqueo duro por sobre-monto).

---

## 5. `monto` string y transporte sibling de `idempotency_key`

**`monto` como STRING (D-FE-45 / D-A29-1 / D-CC-20).** El gateway `payloadRegistrarRetiro` y el wrapper n8n exigen `monto` **string**, regex `^[0-9]{1,12}(\.[0-9]{1,2})?$` y `Number(monto) > 0`. La UI:
- valida en cliente con **esa misma regex** (espejo, nunca más estricta);
- construye el payload con `monto: form.monto.trim()` (string), **jamás** `Number(...)`;
- la guarda dura de `submit()` reusa `formValido`, que exige `montoT !== '' && MONTO_RE.test && >0 && !sobreRetiro && medio ∈ allowlist`.

Esto difiere a propósito de A10/A11 (que mandan `monto` numérico) y fue el punto de mayor riesgo de transcripción; quedó corregido y verificado (los asientos en TEST muestran `−10000.00`, `−3452.37`, coherentes con el envío textual).

**`idempotency_key` sibling.** Se usa `useEnviar('cuenta_corriente.retirar', 'sibling')`: la key viaja **fuera** del payload (tercer argumento de `callPortal`), igual que A11. `useEnviar` genera **key nueva por submit** y sólo reusa la retenida cuando se pide `{reintento:true}` tras `estado_incierto`. La evidencia TEST confirma **dos keys distintas** para los dos retiros del piloto y **cero duplicados** por `(action, key, actor)`.

---

## 6. UX final

- **Fail-closed de saldo (D-FE-37):** sin match único de la fila propia (o saldo `null`) ⇒ banner de error + "Reintentar", **sin form ni submit**. Precedencia de la pantalla: éxito → error/incierto → (L1 loading → L1 error → sin-match/saldo-null → saldo ≤ 0 → form/confirmar).
- **Confirmación previa (D-FE-38):** el "Confirmar retiro" sólo aparece tras revisar el resumen (monto + medio + comentario + saldo actual + saldo estimado). El estimado se rotula como estimación; el saldo definitivo se confirma al registrar.
- **Prevalidación `monto ≤ saldo` (D-FE-39):** "Continuar" queda `disabled` mientras el form es inválido (incluido sobre-retiro); el motivo se muestra en vivo por campo (`montoErr` de formato/sobre-retiro; `medioErr` cuando el monto ya es válido y falta medio). `saldo ≤ 0` bloquea con mensaje de sin fondos.
- **`estado_incierto` (D-FE-44):** primaria **"Verificar saldo"** (`refetch` L1, sin reintento automático); secundaria **"Reintentar este mismo retiro"** (misma key, con copy "usa la misma clave de operación; no crea un retiro nuevo si ya se registró", deshabilitada sin `ultimoPayload` o `enviando`); "Volver a editar" resetea key y flag.
- **Prevención de saldo stale (D-FE-43/44):**
  - *En éxito:* el saldo reconsultado se muestra con orden `!reconsultado || ccLoading` → `ccError` → `filaPropia` → neutro. Como `useAction` **conserva `data` viejo** cuando un `refetch` falla, chequear `ccError` **antes** que la fila evita mostrar un saldo anterior al retiro.
  - *En incierto:* el saldo del banner sólo aparece si hubo una verificación **posterior al intento** (`saldoVerificadoTrasIncierto === true`) y `!ccLoading && !ccError && saldo != null` → "Saldo verificado: $X". Antes de verificar: "Todavía no verificamos el saldo después del intento." El flag vuelve a `false` en todo submit nuevo, reintento, editar o reset.
- **Anti-doble-submit:** `useEnviar` (ignora envío en vuelo + ciclo de key) + `BotonSubmit disabled={enviando}` + `portal_idempotencia_cc` (anti-replay) + la barrera humana de la confirmación.

---

## 7. Validaciones técnicas

- **`tsc --noEmit --strict`** sobre el clone → **EXIT 0** (tsconfig con `strict`, `noUnusedLocals`, `noUnusedParameters`).
- **`npm run build`** (`tsc && vite build`) → **EXIT 0**, 127 módulos (126 baseline + 1 pantalla nueva).
- **Alcance:** `git status --short` acotado a `Apps/portal-operativo/src/` (5 archivos), nada fuera.
- **Vercel TEST:** deploy OK; login, aparición de la acción para socio, render de saldo, registro de retiros, actualización de L1, sin errores de UI.

---

## 8. Verificación DB (TEST) — piloto real 2026-07-09

**`portal_idempotencia_cc` (dos retiros del piloto UI + smoke previo):**
- id_registro 8 → key `c7399199…`, actor `franco`, rol `socio`, `id_movimiento` 14, 19:43:56.
- id_registro 7 → key `37485f33…`, actor `franco`, rol `socio`, `id_movimiento` 13, 19:38:33.
- id_registro 6 → key `smoke-a29gw-f1-retiro`, `id_movimiento` 12, 2026-07-04 (smoke A29, separado del piloto).

**Asientos en `movimientos_socio` (unión con idempotencia + socio):**
- `id_movimiento` 14 → `tipo='retiro'`, `monto=−10000.00`, `medio_pago='efectivo'`, `creado_por='franco'`, `socio='Franco'`, `comentario=null`.
- `id_movimiento` 13 → `tipo='retiro'`, `monto=−3452.37`, `medio_pago='efectivo'`, `creado_por='franco'`, `socio='Franco'`, `comentario=null`.

**Saldo vivo (`cuenta_corriente_viva`):** Franco `saldo_al_dia=90000.00` con `movimientos=−13452.38`. Verificación aritmética: `−161547.62 + 265000.00 − 13452.38 = 90000.00` ✓, y `−10000.00 − 3452.37 − 0.01 = −13452.38` ✓ (los dos del piloto + el smoke).

**Duplicados por `(action, idempotency_key, actor)`:** **0 filas** ⇒ sin doble retiro por retry/doble submit.

**Nota:** el primer intento de query contra `movimientos_socio` falló por pedir `source_event`, **columna inexistente** en esa tabla (columnas reales: `id_movimiento, id_socio, fecha, tipo, monto, moneda, periodo, medio_pago, comentario, id_movimiento_revertido, creado_por, created_at`). Es un error de la query de verificación, no del frente.

**Conclusión de la auditoría:** circuito UI→gateway→A29→wrapper→DB funcional; asientos correctos y firmados por el actor; idempotencia sin duplicados; L1 refleja el saldo actualizado; smoke separado y trazable.

---

## 9. Riesgos

**Cerrados / mitigados:**
- **Saldo stale en éxito e incierto (era el bug más sutil):** cerrado con la prioridad `ccError`-antes-que-fila en éxito y el flag `saldoVerificadoTrasIncierto` en incierto (D-FE-43/44).
- **`monto` numérico por inercia (A10/A11):** cerrado; se envía string trim con regex espejo; verificado en los asientos TEST.
- **Doble retiro por doble-submit/retry:** cerrado; keys distintas por submit, reintento sólo mismo-key, 0 duplicados en TEST.
- **Fuga de saldo ajeno / retiro a ciegas:** cerrado con fail-closed por match único (D-FE-37); empíricamente `franco`/`Franco` matcheó bajo normalización y mostró el saldo propio.
- **Visibilidad por rol hardcodeada:** evitada; menú y botón siguen `acciones` de A02.

**Residuales (no bloqueantes del cierre TEST):**
- **Piloto acotado:** se ejercitó socio `franco`, medio `efectivo`, `comentario=null`, montos válidos. **No** se ejercitaron en vivo: medio `transferencia_bancaria`, `comentario` no nulo, rechazo `saldo_insuficiente` (VD001) real, `estado_incierto` real (difícil de forzar), fail-closed por nombre no-matcheado real, y bloqueo por `saldo ≤ 0` real. Todos validados por diseño/harness; recomendable ejercitar algunos en el piloto OPS (ver §10).
- **Dependencia del invariante de nombres SB0:** el fail-closed asume `socios.nombre` ≡ `portal_usuarios.nombre` bajo `lower(btrim())`. Si a futuro un socio tuviera nombres divergentes más allá de mayúsculas/espacios, la pantalla bloquearía (fail-closed, con mensaje claro) en vez de permitir retiro erróneo — comportamiento deseado, pero conviene tenerlo presente al alta de socios.
- **Flicker mínimo de "Actualizando saldo":** el `refetch` post-éxito corre en `useEffect` (post-paint); se mitigó con el ref `reconsultado` para no mostrar el saldo previo, a costa de un frame de "Actualizando…". Aceptado.

---

## 10. Próximo paso recomendado (OPS / piloto real)

1. **Promoción a OPS del frontend:** aplicar los 5 archivos y desplegar el portal de OPS (git add/commit/push + Vercel), igual que en TEST. Sin cambios de backend (A29 ya está en OPS).
2. **Piloto OPS acotado con un socio real**, ejercitando de forma controlada los caminos no cubiertos en TEST:
   - un retiro por **`transferencia_bancaria`** y otro con **`comentario`** no nulo;
   - un **sobre-retiro intencional** (monto > saldo) para ver el bloqueo duro y, si se envía saldo justo y otro proceso lo consume, el rechazo `saldo_insuficiente` real con `detail`;
   - opcional: un socio distinto de `franco` (rodrigo/remo) para confirmar el match de nombre en OPS.
3. **Verificación DB OPS** con las mismas queries (idempotencia, unión con `movimientos_socio`, duplicados por `(action,key,actor)`, saldo vivo), y separación clara de cualquier smoke previo.
4. **No** avanzar L3 / primera foto real / cierre asistido / reembolsos / MP: siguen siendo frentes aparte.

---

## 11. Satélites a actualizar (propuesta — NO aplicar todavía)

Pendiente de tu pedido explícito para tocarlos:

- **`Docs/Operacional/DECISIONES_NO_REABRIR.md`** — acuñar **D-FE-37 … D-FE-45** (§4).
- **`ESTADO_ACTUAL_VITA_DELTA.md`** — marcar el frente "Portal Operativo · UI del retiro" como **cerrado en TEST** (y listo para promoción a OPS).
- **`Pendiente_pre_produccion.md`** — mover la "UI del retiro" de pendiente a cerrada (dejar como pendiente sólo la promoción/piloto OPS si se quiere trackear).
- **`Lecciones_Aprendidas.md`** — candidata **L-FE**: *"`useAction` conserva `data` tras un `refetch` fallido; para operaciones sensibles, gatear las lecturas companion por `ccError`/`ccLoading` con la prioridad correcta y, en flujos de reintento, exigir un flag de verificación **posterior al intento** antes de mostrar el dato — nunca el valor cargado al montar."*
- **`CLAUDE.md`** / **`README.md`** — actualizar el estado del frente si listan frentes/estado.
- **Canónico `6B_SCHEMA_SQL.md`** — **NO se toca** (frente frontend-only, sin SQL). Permanece en **v1.12.0**.

---

## Ritual de cierre (pendiente de ejecución por Franco)

1. Colocar este documento en el repo (sugerido: `Docs/Bitacora/CIERRE_UI_RETIRO_SALDO_FRONTEND.md`).
2. Promoción del frontend a OPS + piloto OPS (§10).
3. Tras el piloto OPS: aplicar satélites (§11) y acuñar D-FE-37…45.

**Este cierre NO incluye:** cambios de código, aplicación de satélites, patchers, ni toques a backend/gateway/n8n/Supabase/canónico/bootstrap/git remoto.
