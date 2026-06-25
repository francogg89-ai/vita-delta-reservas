# RUNSHEET — Sub-slice 2 / Bloque B3 (A07 `reserva.crear_manual`) — v3

**Carril:** C — Portal Operativo Interno (frontend). **Entorno:** TEST. **Cero backend / n8n / OPS / canónico.**
**B3 sigue ABIERTO.** Este entregable trae: (1) **diagnóstico** del alta A07 (es backend, no frontend), y (2) **patch de UX** de `CrearReserva.tsx` (seña auto-50%, default transferencia, validación de email). No se avanza a B4 hasta tener **alta OK estable**.

---

## PARTE A — Diagnóstico del alta A07 ("No se pudo confirmar la reserva.")

**El frontend NO es la causa.** `useEnviar`/`callPortal` muestran "No se pudo confirmar la reserva." porque **el gateway devuelve `estado_incierto`**; el frontend lo refleja fielmente. Lo confirmé leyendo la fuente viva del gateway (`portal-api/index.ts`):

- A07 está marcada `isWrite: true`. Para `isWrite`, el gateway devuelve **`estado_incierto`** cada vez que su dispatch a n8n **no es confiable**. Eso pasa en **exactamente estas 5 ramas** de `dispatchN8n`, y **cada una loguea un `console.error` específico para `reserva.crear_manual`**:
  1. `fetch` lanza (timeout > **10 s** / red) → log: `fallo de red/timeout hacia n8n (reserva.crear_manual)`
  2. n8n responde HTTP no-2xx → log: `n8n devolvió status XXX en reserva.crear_manual`
  3. el body de n8n no es JSON → log: `respuesta de n8n no es JSON (reserva.crear_manual)`
  4. el envelope tiene **forma inválida** → log: `envelope con forma inválida desde n8n (reserva.crear_manual)`
  5. error con código fuera de la allowlist → log: `n8n devolvió código no permitido '...' en reserva.crear_manual`
- El timeout es `N8N_TIMEOUT_MS = 10000` (10 s, con `AbortController`). En éxito real el gateway hace `ok(parsed.data)` solo si `parsed.ok === true` **y** el envelope valida.

**Por qué empezó tras publicar el workflow + es intermitente** → los dos sospechosos principales son:
- **Rama 4 (forma del envelope):** el `Respond to Webhook` del workflow **publicado** está devolviendo algo distinto al envelope exacto `{ "ok": true, "data": { ... } }` (clásico de n8n: devuelve el array de items `[{json:...}]` o un objeto envuelto, si el nodo Respond quedó en otro modo que el del template). Esto daría `estado_incierto` **consistente**.
- **Rama 1 (timeout):** el workflow publicado a veces tarda **> 10 s** (cold start / un nodo lento) → `estado_incierto` **intermitente**.

### Qué necesito que verifiques (determinístico, sin adivinar)

1. **Logs del Edge Function `portal-api`** (Supabase → Edge Functions → portal-api → Logs): buscá la línea `console.error` para `reserva.crear_manual` en un intento que dio `estado_incierto`. **Esa línea nombra la rama exacta** (1 a 5). Es el dato que cierra el diagnóstico.
2. **Ejecución del workflow A07 en n8n:** ¿completa? ¿cuánto tarda (vs 10 s)? ¿qué emite el **último nodo `Respond to Webhook`**? Debe ser **exactamente** `{ "ok": true, "data": { ... } }`. Compará el nodo Respond del workflow **publicado** contra `portal-a07-crear-reserva__TEMPLATE.json` (modo de respuesta + Response Body).
3. **¿La reserva queda creada cuando aparece `estado_incierto`?** Mirá A04/A24:
   - **Sí** → la escritura commitea pero el gateway no la pudo confirmar (timeout o forma, post-commit). Para el operador: `estado_incierto` → **Reintentar** → debería volver `idempotent_match` (alta confirmada, el wrapper dedupea).
   - **No** → el wrapper falla antes del commit → el problema está dentro del workflow.
4. **(Opcional) DevTools → Network**, request `portal-api`: si tarda **~10 s** y recién ahí da `estado_incierto` = timeout (rama 1); si da `estado_incierto` **rápido** = forma/HTTP (rama 2/4).

### Caminos de corrección (BACKEND — tu decisión; yo no toco n8n/Edge directo)

- Si es **rama 4 (forma):** corregir el nodo `Respond to Webhook` del workflow publicado para emitir el envelope exacto (igual al template). **Es el más probable "después de publicar".**
- Si es **rama 1 (latencia):** calentar/optimizar el workflow; o, si A07 legítimamente necesita > 10 s, **subir `N8N_TIMEOUT_MS`** en el gateway — ese cambio sí es un deliverable de código que te puedo preparar, pero **reabre un artefacto de backend cerrado**, así que solo si lo decidís.

La UX de `estado_incierto` del frontend es correcta y el reintento es seguro (dedupea). Cuando el wrapper responda en tiempo y forma, el **alta OK de A07 será estable**. **Pasame el dato del punto 1 (y si querés, 2/3) y te confirmo la rama y el fix.**

---

## PARTE B — Patch de UX de `CrearReserva.tsx` (v3)

Cambios pedidos, todos en `CrearReserva.tsx` (no toca backend ni alcance):

1. **Seña con default `0` = auto 50%.**
   - `monto_sena` arranca en `'0'`. Helper: **"0 = calcular 50% automaticamente."**
   - Validación: `0` o vacío → **automático** (válido); `>0` → exacto y **≤ total**; negativo/no numérico → "Sena invalida.".
   - **Antes de enviar** el frontend convierte: `senaInput = (vacío ? 0 : Number)`, `monto_sena = senaInput > 0 ? senaInput : round(total/2, 2 dec)`. **Nunca manda `monto_sena: 0`** (0 = auto; una seña real $0 sería otra decisión).
   - Ej.: total 200000, seña 0 → payload `monto_sena: 100000`. Seña 50000 → `50000`.
2. **Medio de pago default `transferencia_bancaria`.** Se quitó la opción vacía "Elegí un medio"; Vicky/socio lo cambian solo si hace falta.
3. **Email (se mantiene v2):** email vacío → OK si hay teléfono válido; email no vacío → debe ser válido aunque el teléfono lo sea ("El email cargado no es valido."); regla de contacto "Indica un telefono valido o un email valido.".
4. **"Ver detalle":** sigue fuera de B3 (lo sumamos en B5 con el deep-link A12→A10 / A05 por `id_reserva`).

### Aplicar y verificar

```
# desde la raíz del repo
tar -xzf portal-operativo-b3-a07-reserva-v3.tar.gz   # reemplaza CrearReserva.tsx (+ rutas.tsx)
cd Apps/portal-operativo
npm run typecheck   # EXIT 0
npm run build       # EXIT 0
```
**Mi corrida:** typecheck EXIT 0; build EXIT 0, `✓ 116 modules`.

### Pruebas (vicky/socio; las 6 tuyas + las de seña/medio)

| Caso | Esperado |
|---|---|
| Alta OK (cuando A07 responda bien) | tarjeta "Reserva creada #id" + spinner apagado |
| Re-alta idéntica | "ya existía: no se duplicó" (`idempotent_match`) |
| Mismo rango, dato distinto | `conflicto` "Sin disponibilidad…" |
| Personas sobre capacidad | `payload_invalido` (mensaje del motor) |
| **Seña = 0** + total 200000 | payload `monto_sena: 100000` (verificá en la reserva creada) |
| **Seña = 50000** + total 200000 | payload `monto_sena: 50000` |
| **Seña = 300000** + total 200000 | error "La sena no puede superar el total.", **sin request** |
| **Medio de pago al cargar** | viene **Transferencia bancaria** seleccionado |
| Email inválido + teléfono válido | error inline en Email, **sin request** |
| jenny | no ve "Crear reserva" ni entra por URL |

> **Aclaración importante:** el alta OK estable depende de **Parte A** (que A07 responda con el envelope correcto en < 10 s). El patch de UX (Parte B) es independiente y se puede testear ya en validación/`conflicto`, pero **B3 no cierra** hasta que el alta OK sea estable.

---

## Estado

- **B3 ABIERTO.** Bloqueado por el diagnóstico del alta (Parte A, backend).
- No se avanza a **B4 — A11** hasta que A07 tenga alta OK estable.
