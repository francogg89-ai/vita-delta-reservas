# RUNSHEET QA — B5 · Cobranza multi-porción (A10-MP)

**Proyecto:** Vita Delta Reservas — Carril C / Portal Operativo Interno
**Bloque:** B5 (sub-slice 2, escritura final) — pantalla `RegistrarCobro` sobre `cobranza.registrar_cobro` (A10-MP).
**Quién ejecuta:** Franco. Claude entrega archivos + este runsheet; no corre comandos, no deploya, no toca Supabase/n8n/OPS.
**Ambiente:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`). **Solo TEST.**
**Estado:** B1+B2+B3 aprobados a nivel implementación (auditoría externa). Cierre formal de B5 pendiente hasta correr esta QA en TEST.

---

## 1. Archivos modificados

Ruta base: `Apps/portal-operativo/src/`. Total: **1 nuevo + 6 modificados**. Todos LF. No se tocó ningún otro archivo.

| Archivo | Bloque | Cambio |
|---|---|---|
| `screens/RegistrarCobro.tsx` | B2 | **NUEVO.** Pantalla de cobranza multi-porción: entrada por `?id_reserva=` o id manual, header + saldo desde `reserva.detalle` (A05), form efectivo/transferencia(bancaria·mp)/otros/notas, resumen en vivo, bloqueo de sobrepago, manejo de `estado_incierto` con retry idempotente. |
| `lib/contratos.ts` | B1 | `SubtipoTransferencia` (`'bancaria'\|'mp'`), `RegistrarCobroDetalle`, `RegistrarCobroData` (forma exacta del `response.data`, cierre §4.5). `RegistrarSaldoData` marcado **deprecated** (sin borrar). |
| `lib/constantes.ts` | B1 | `SUBTIPOS_TRANSFERENCIA` (bancaria/mp), tipado con `SubtipoTransferencia`. |
| `lib/actionRegistry.ts` | B2 | Entrada `cobranza.registrar_saldo` → `cobranza.registrar_cobro` (label "Registrar cobro", grupo `cobranzas`, orden 20, ruta `/cobranzas/registrar` intactos). |
| `app/rutas.tsx` | B2 | Import de `RegistrarCobro` + `PANTALLAS['cobranza.registrar_cobro']`. |
| `app/PlaceholderView.tsx` | B2 | Set `ESCRITURAS`: `registrar_saldo` → `registrar_cobro` (cosmético; la pantalla real ya no pasa por el placeholder). |
| `screens/CobranzaSaldos.tsx` | B3 | Columna/acción **"Cobrar"** por fila → deep-link `/cobranzas/registrar?id_reserva=ID`. Solo navegación. |

---

## 2. Qué NO se tocó

- **Backend** (funciones SQL, tablas, enums).
- **Gateway** `portal-api` (Edge Function, CATALOG).
- **Wrapper n8n** firmado HMAC.
- **OPS** (`vita-delta-ops`).
- **Canónico** `6B_SCHEMA_SQL.md`.
- **W10** `cobranza.registrar_saldo`: sigue desplegado / deprecated-in-place en backend. En el frontend queda **solo como tipo deprecated + comentarios**, con **cero** llamadas de runtime. B5 usa exclusivamente `cobranza.registrar_cobro`.

---

## 3. Comandos (los corre Franco)

Prerrequisitos: **Node 18+** (LTS 20 recomendado) y **npm**. Verificá: `node -v`.

```bash
cd Apps/portal-operativo
cp .env.example .env    # si no lo tenés ya
```

Editá `.env` (la URL ya apunta a TEST; completá la anon key):

```
VITE_SUPABASE_URL=https://bdskhhbmcksskkzqkcdp.supabase.co
VITE_SUPABASE_ANON_KEY=<anon key (publishable) de TEST>
```

```bash
npm ci
npm run typecheck    # esperado EXIT 0
npm run build        # esperado EXIT 0
npm run dev          # abrí el localhost que imprime, corriendo contra TEST
```

> **Evidencia local (Claude, clon fresco contra remoto `f078b80` + B5):** `typecheck` EXIT 0, `build` EXIT 0, 118 módulos (JS ~452 kB). EOL LF preservado en los 7 archivos.

**Identidades TEST** (cubren los 3 roles): `vicky@vitadelta.test` (rol `vicky`), `franco@vitadelta.test` (rol `socio`), `jenny@vitadelta.test` (rol `jenny`). Si no tenés las contraseñas, reseteálas desde Supabase Auth TEST → Authentication → Users (eso lo hacés vos).

**Datos de prueba:** necesitás al menos **una reserva en estado `confirmada` o `activa` con `saldo_real > 0`** en TEST (cobrable). Para cubrir casos negativos, tené a mano también una con `saldo_real = 0` o estado no cobrable. La forma más rápida de entrar a la pantalla: login → **"Saldos a cobrar"** (A12) → botón **Cobrar** de una fila (eso, de paso, prueba el deep-link de B3).

---

## 4. QA manual por rol

| Rol | Identidad | Esperado |
|---|---|---|
| **jenny** | `jenny@vitadelta.test` | **NO** ve "Registrar cobro" en el menú. Navegar directo a `/cobranzas/registrar` → `RutaProtegida` redirige a `/`. Tampoco ve "Saldos a cobrar" (no tiene A12) ni el botón "Cobrar". *Defensa en profundidad:* si se forzara el POST, el gateway responde `rol_no_permitido`. |
| **vicky** | `vicky@vitadelta.test` | Ve el ítem, entra, ve header (cabaña · #id · huésped · estado) + saldo, y **cobra OK**. |
| **socio** | `franco@vitadelta.test` | Igual que vicky: ve, entra y **cobra OK**. |

---

## 5. QA funcional (con `vicky` o `socio`)

Entrá a una reserva cobrable (vía A12 → **Cobrar**, o tipeando el id). Regla contable a verificar en todos los casos: **`suma_saldo = efectivo + transferencia + otros` baja el saldo; el recargo (`extra`) NO baja el saldo.** Es decir `saldo_real_actual = saldo_anterior − suma_saldo`.

1. **Solo efectivo.** Cargá efectivo ≤ saldo. → Cobra. `suma_extra=0`, `total_cobrado=suma_saldo`, saldo baja por el efectivo. En `detalle`: `transferencia=0`, `subtipo_transferencia=null`, `recargo=0`.
2. **Transferencia bancaria.** Cargá transferencia = X, subtipo **Bancaria**. → `recargo = round(X*0.05)`, `total_cobrado = X + recargo`, **saldo baja X** (no X+recargo). `detalle.subtipo_transferencia='bancaria'`. *Ej.: X=40000 → recargo 2000, total 42000, saldo baja 40000.*
3. **Transferencia MP.** Igual que (2) con subtipo **Mercado Pago**. → `detalle.subtipo_transferencia='mp'`.
4. **Otros con origen/descripción.** Cargá monto en "otros" > 0. → Aparecen los campos **Origen** y **Descripción** (obligatorios). Cobra; `otros` baja saldo como efectivo-equivalente; el `detalle.otros` refleja el monto. Probar además: otros > 0 **sin** origen/descripción → al "Registrar cobro" marca error en esos campos y **no** envía.
5. **Mixto.** Efectivo + transferencia + otros a la vez. → `suma_saldo` = suma de las tres; recargo **solo** sobre la transferencia; `cant_lineas` coherente.
6. **Cobro que salda.** `suma_saldo = saldo_real`. → `saldada:true`, card "Cobro registrado · saldo saldado", **no** aparece "Seguir cobrando esta reserva".
7. **Sobrepago bloqueado en UI.** `suma_saldo > saldo_real`. → Botón **"Registrar cobro" deshabilitado** + aviso rojo en vivo ("La suma aplicada a saldo … supera el saldo pendiente …"). **No se envía nada.**
8. **Conflicto por saldo stale.** Abrí el cobro de una reserva con saldo (no envíes). En otra pestaña, cobrá una parte de **esa misma** reserva (baja el saldo real). Volvé a la primera pestaña (saldo en pantalla quedó viejo) y cargá un cobro cuya suma supere el saldo real **actual** → al enviar, el backend rebota **conflicto** (`excede_saldo`). → Banner aviso "No se pudo registrar el cobro." + botón **"Verificar reserva"**. Tocalo → refetch del saldo; si ahora la suma supera el saldo, se activa el bloqueo de UI del caso (7).
9. **Retry idempotente.** El dedup del backend es `source_event = f(id_reserva, idempotency_key)`; el botón "Reintentar este cobro" usa `enviar(payloadGuardado, {reintento:true})` → **misma key**. Si llegás a ver `estado_incierto` (difícil de forzar en TEST normal): "Reintentar" → si ya se había aplicado, vuelve `idempotent_match:true` y **no duplica**. En happy-path, `idempotent_match:false`. El dedup en sí ya está cubierto por el smoke del cierre A10-MP (40/40).
10. **Edición tras error/incierto = submit nuevo / key nueva.** Partí de un error manejado con el form visible (usá el conflicto del caso 8). Tras el banner, **editá cualquier monto/medio/otros/notas** → el banner se limpia y la key retenida se suelta. Volvé a "Registrar cobro" → en DevTools (§6), el `idempotency_key` del nuevo request es **distinto** al del intento anterior.

---

## 6. Checks de payload (DevTools → Network)

Abrí DevTools → **Network**; al "Registrar cobro" se dispara un request al gateway (`portal-api` / functions). Inspeccioná el **body** del request:

- [ ] `action` = `cobranza.registrar_cobro` **siempre**.
- [ ] **Nunca** `cobranza.registrar_saldo`.
- [ ] **No** viajan campos de control: `actor`, `rol`, `nonce`, `source_event`, `creado_por`, `request_ts`.
- [ ] `origen_otros` / `descripcion_otros` viajan **solo** si `monto_otros > 0`.
- [ ] `idempotency_key` viaja **dentro del payload** (no en header ni fuera).

Forma esperada del payload (ejemplo, sin "otros"):

```json
{
  "id_reserva": 123,
  "monto_efectivo": 0,
  "monto_transferencia": 40000,
  "monto_otros": 0,
  "subtipo_transferencia": "bancaria",
  "idempotency_key": "abc_12345678"
}
```

Con "otros" > 0 se agregan `origen_otros` y `descripcion_otros`; `notas` aparece solo si cargaste texto.

---

## 7. Checks visuales

- [ ] **Mobile-first:** en viewport angosto (DevTools device mode) los controles son full-width y no disparan zoom de iOS al enfocar; el layout queda legible.
- [ ] **Resumen en vivo** muestra: *Aplicado a saldo* (`suma_saldo`), *Recargo 5% (sobre transferencia)*, *Total a cobrar* (`total_cobrado`), *Saldo estimado después*.
- [ ] **No resta el recargo del saldo:** *Saldo estimado después* = `saldo_real − suma_saldo`. Probalo con transferencia: el recargo **no** baja el estimado.
- [ ] **Success card** muestra el `response.data`: `suma_saldo`, `suma_extra`, `total_cobrado`, `saldo_anterior`, `saldo_real_actual`, `saldada`, `cant_lineas`, `detalle{efectivo, transferencia, subtipo_transferencia, otros, recargo}` e `idempotent_match` (con nota "ya estaba registrado, no se duplicó" si es `true`).

---

## Gate de cierre

B5 se cierra formalmente **recién cuando esta QA corre OK en TEST**. Ahí se propagan los satélites (`DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `Pendiente_pre_produccion.md`) en una conversación de cierre aparte, respetando la regla de una etapa por conversación y satélites solo en cierre formal.
