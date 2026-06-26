# Cierre — Aviso 8C-bis enganchado al alta por el portal (A07) · TEST

**Estado:** ✅ **CERRADO Y VALIDADO EN TEST (2026-06-26).** El alta de reservas por el Portal Operativo Interno (A07 `reserva.crear_manual`) ahora dispara el aviso por mail 8C-bis, reusando el sub-workflow existente sin lógica nueva de mail. Validado end-to-end en TEST: los **5 gates** del runsheet en verde, incluido el de no-afectación de la reserva. **No toca** backend del motor, gateway `portal-api`, OPS, el canónico (`6B_SCHEMA_SQL.md` v1.8.1), W10 ni el contrato frontend. **Numeración oficial de decisiones de este cierre: D-C-71…73.** **No promovido a OPS** (es la etapa siguiente, Punto 2).

**Decisiones registradas:** D-C-71 · D-C-72 · D-C-73 🔒. **Lecciones:** L-C-24 · L-C-25 📝. **Propagación a satélites:** pendiente como paso coordinado (ver §8).

---

## 1. Objetivo

Que el alta de una reserva **por el portal** dispare el mismo aviso por mail que ya disparaba el form de carga 8B, reusando el sub-workflow `vita_w8cbis_alerta` (validado y activo en OPS desde 8C-bis), **sin lógica nueva de mail** y **sin afectar la respuesta de la reserva** si el aviso falla.

## 2. Hallazgo (2026-06-26)

El aviso 8C-bis (mail al confirmar una reserva con check-in en `[hoy, hoy+7]`) se disparaba **solo desde el form de 8B** (nodo "PUNTO EXTENSION 8C → Call `vita_w8cbis_alerta__OPS`"). El **wrapper A07 del portal NO lo invocaba**: su flujo `Webhook → firma → acceso → PG-0 precheck → PG-1 crear_prereserva → PG-2 lock_pago → PG-3 confirmar → PG-4 recheck → render → Respond` no tenía rama de aviso. Confirmado contra el **export vivo** del A07 TEST (no contra el template): set de nodos + conexiones idénticos al template, sin rama de mail. Consecuencia: al crear reservas por el portal en OPS, no saldría el mail.

## 3. Diseño implementado

Rama lateral no bloqueante en el wrapper A07, **espejo del PUNTO EXTENSION 8C del 8B**. El sub-workflow 8C-bis es **autocontenido**: re-lee la reserva por `id_reserva` (read-only), decide la ventana `[hoy, hoy+7]` (TZ America/Argentina/Buenos_Aires) y manda (o no) los dos mails (operativo + limpieza). Por eso A07 **solo lo dispara**, sin armar mail.

**+2 nodos, +1 conexión** sobre el A07 vivo (los 22 nodos originales quedaron byte-idénticos, verificado por hash):

- **`IF aviso 8C-bis (alta nueva)`** (`if` v2.2) — gate. Una condición booleana null-safe: `($json.envelope?.ok === true) && ($json.envelope?.data?.idempotent_match === false)`.
- **`Call 'vita_w8cbis_alerta__TEST' (aviso)`** (`executeWorkflow` v1.3) — dispara el sub-workflow. `onError: continueRegularOutput`, **Wait for Sub-Workflow Completion = ON/default**, **hoja sin salida**. Input: `{ id_reserva, id_pre_reserva, entorno, source:'a07_portal', operador }`.

Fan-out (lo único que se tocó del grafo): `router3_confirmar` sale a **dos** destinos, en orden — primero `IF3 recheck` (rama principal, intacta), después el gate (rama lateral). El gate `true` → `Call`; `false` → sin salida. El `Call` es hoja.

```
router3_confirmar ─[0]→ IF3 recheck → … → Code: render → Respond   (principal, primero)
                  └[1]→ IF aviso 8C-bis ─(true)→ Call 8C-bis (hoja) (lateral, después)
```

El envelope de éxito **fresco** nace solo en `router3_confirmar` (`res.ok===true`, `idempotent_match:false`); el camino de recheck (`router4_recheck`) siempre marca `idempotent_match:true` → no avisa.

## 4. Garantía de no-afectación de la reserva (por configuración)

La respuesta de la reserva no puede romperse ni contaminarse por el aviso. Cuatro mecanismos en simultáneo:

1. **`onError: continueRegularOutput`** en el `Call`: una excepción del sub-workflow no marca la ejecución como fallida.
2. **Hoja lateral**: el `Call` no tiene conexión de salida → su output nunca llega a `Code: render` ni a `Respond`.
3. **Rama principal conectada primero** (`router3_confirmar` índice 0 → `IF3 recheck`): n8n v1 recorre la rama de respuesta antes que la lateral; `respondToWebhook` emite el HTTP 200 en su propia rama.
4. **Gate**: solo la confirmación fresca llega al `Call`; errores, conflictos y reintentos idempotentes dan `false` (la expresión es null-safe — no rompe ni con el item de recheck sin `envelope`).

**`Wait OFF` se evaluó y se descartó**: la opción "continuar sin esperar (apagado)" puede **abortar** el sub-workflow antes de completar (comportamiento documentado de n8n + regresiones por versión) → el mail podría no salir. La garantía de no-afectación **no depende de async puro**: la dan `onError` + hoja + rama principal primero. Es el mismo patrón del 8B (Wait ON + onError + hoja), ya validado en producción.

## 5. Validación en TEST (5 gates verdes)

1. **Alta en ventana** → A07 `{ok:true, data:{…, idempotent_match:false}}` + llegan los 2 mails (operativo + limpieza) a `francogg89@gmail.com`. ✅
2. **Reintento idempotente** del mismo alta → `{ok:true, data:{…, idempotent_match:true}}` + **sin** segundo mail (el `Call` no se ejecuta; lo filtra el gate). ✅
3. **Alta fuera de ventana** → `{ok:true}` + **sin** mail (el `Call` dispara, pero el 8C-bis decide "fuera de ventana"). ✅
4. **No-afectación** — aviso pineado para fallar → A07 igual `{ok:true}`; aviso lento (Wait temporal en 8C-bis) → respuesta no acoplada; en la ejecución, `Respond` recibe input de `Code: render` y el `Call` es terminal. ✅
5. **Input al sub-workflow** verificado en la ejecución: `{ id_reserva, id_pre_reserva, entorno:"test" (=leer_ambiente.valor), source:"a07_portal", operador }`. ✅

## 6. Decisiones (D-C-71…73) 🔒

> **Nota de numeración.** Las decisiones **D-C-64…70 están bloqueadas en `A10MP_CIERRE.md`** (A10-MP); su propagación a `DECISIONES_NO_REABRIR.md` quedó pendiente (cierre de propagación de A10-MP, no de esta etapa). Este cierre arranca en **D-C-71** para no colisionar.

- **D-C-71** — **El alta por el portal (A07) dispara el aviso 8C-bis por rama lateral en el wrapper, reusando el sub-workflow existente.** Solución al hallazgo: rama lateral no bloqueante en A07 que llama `vita_w8cbis_alerta` por `executeWorkflow`, espejo del PUNTO EXTENSION 8C del 8B, **sin lógica nueva de mail** (el sub-workflow es autocontenido). El fan-out cuelga de `router3_confirmar`. Se descartó **para esta etapa** el "punto común" (outbox a nivel DB / trigger sobre `reservas` que cubriría cualquier vía de alta) por tocar el canónico (guardrail) y ser un cambio de modelo mayor; queda como pendiente futuro (su propia conversación de diseño).
- **D-C-72** — **Gate anti-duplicado + entorno por marcador canónico + source.** El `Call` se gatea: dispara solo en confirmación fresca (`envelope.ok===true && envelope.data.idempotent_match===false`); el camino de recheck/idempotente (`router4_recheck`, siempre `idempotent_match:true`) no avisa → un reintento idempotente no manda mail repetido. El `entorno` se resuelve desde **`leer_ambiente.valor`** (`configuracion_general('ambiente')`, ya en el flujo), no hardcodeado → el wrapper se autoidentifica y la promoción a OPS no requiere flip manual. Input: `{id_reserva, id_pre_reserva, entorno, source:'a07_portal', operador}` (operador = actor inyectado del JWT vía `Code: derivar`).
- **D-C-73** — **No-afectación de la reserva por configuración (no por async puro); Wait ON, no OFF.** `Wait for Sub-Workflow Completion` queda en **ON/default** (igual que el 8B): OFF puede abortar el sub-workflow antes de completar (n8n) → el mail podría no salir. La garantía de que el aviso no rompe ni contamina la respuesta la dan `onError: continueRegularOutput` + el `Call` como hoja + la rama principal conectada primero (`respondToWebhook` emite en su rama). Probado por configuración y por el Gate 4 del runsheet.

## 7. Lecciones (L-C-24…25) 📝

- **L-C-24** — **`executeWorkflow` con "Wait = OFF" puede abortar el sub-workflow; para un side-effect best-effort que SÍ debe ejecutarse, Wait ON + onError + hoja es el patrón correcto.** OFF se describe como "continuar sin esperar", pero en la práctica puede abortar el sub-workflow cuando el padre sigue de largo. La no-afectación de la respuesta NO depende de async puro: `respondToWebhook` emite en su propia rama y `onError: continueRegularOutput` + nodo hoja aíslan la falla y el resultado del aviso.
- **L-C-25** — **Verificar live-vs-template antes de anclar una inserción quirúrgica en un wrapper.** El export vivo del A07 difería del `__TEMPLATE` solo en cosas benignas (secreto HMAC real embebido, `Respond` sin `respondWith` usando el default, `webhookId`), con topología idéntica. Un diff nodo a nodo (set + hash de params + conexiones) confirmó el punto de inserción intacto y habilitó construir sobre la realidad viva. Ante sospecha de drift (acá, un "fix de estabilidad" mencionado pero no en el template), diffear el vivo contra el repo y construir sobre el vivo.

## 8. Propagación a satélites (pendiente — paso coordinado)

Igual que A10-MP, la propagación queda como paso coordinado, a ejecutar tras aprobar el texto de las decisiones:

- `ESTADO_ACTUAL_VITA_DELTA.md` — nueva "Etapa actual" (aviso 8C-bis en alta por portal), demoviendo sub-slice 3 a "Etapa previa".
- `CLAUDE.md` — contexto/etapa.
- `DECISIONES_NO_REABRIR.md` — sección nueva con D-C-71…73 (+ nota sobre D-C-64…70 en A10-MP).
- `Lecciones_Aprendidas.md` — L-C-24, L-C-25 en la sección Carril C — Backend/API.
- `Pendiente_pre_produccion.md` — actualizar §3.1: el aviso 8C-bis ahora cubre también el alta por portal (A07), no solo 8B.
- `6B_SCHEMA_SQL.md` — **sin cambios** (no hay DDL).

## 9. Qué NO se tocó

Backend del motor (funciones `crear_prereserva`/`registrar_pago`/`confirmar_reserva`/`crear_bloqueo`), gateway `portal-api`, OPS, canónico `6B_SCHEMA_SQL.md` v1.8.1, W10, el sub-workflow 8C-bis (se reusa tal cual), el contrato frontend, y los 22 nodos originales del A07 (byte-idénticos). El cambio es una rama de side-effect del wrapper A07; la respuesta de A07 no cambió de forma.

## 10. Próxima etapa — promoción del Carril C a OPS (Punto 2)

Recién con estos gates verdes en TEST se planifica la promoción coordinada a OPS: el `Call` apunta al 8C-bis **OPS** (`fHzMFj7pGMKuYEOb`) con `entorno` resuelto a `'ops'` por el `leer_ambiente` del wrapper OPS; más P-FE-01 (catálogo real), P-C-7 (CORS al origin real), P-FE-09 (banner OPS), GRANTs/seed real de `portal_usuarios`, P-C-9 en OPS. **No se toca OPS hasta cerrar TEST.**

## 11. Artefactos

- `portal-a07-crear-reserva__TEST.con_aviso_8cbis.json` — wrapper modificado (import directo, sobre el export vivo).
- `portal-a07-crear-reserva__TEMPLATE.json` — template sanitizado actualizado (placeholders de cred/secreto/8cbis-id).
- `A07_aviso_8cbis__2_nodos_snippet.json` — snippet limpio de los 2 nodos (sin secreto), para paste quirúrgico.
- `RUNSHEET_A07_AVISO_8CBIS_TEST.md` — import + pre-flight + 5 gates + rollback.
- Sub-workflow reusado: `vita_w8cbis_alerta__TEST` (id `TdTlv9ZhswwzijF2`) / `__OPS` (id `fHzMFj7pGMKuYEOb`).
