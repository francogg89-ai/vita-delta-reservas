# Cierre — Frontend Sub-slice 2 (Portal Operativo Interno · Carril C): las 4 escrituras

**Carril:** C — Portal Operativo Interno (frontend).
**Entorno:** TEST (`vita-delta-test`). **No se tocó backend, gateway `portal-api`, wrapper n8n, OPS, el canónico (`6B_SCHEMA_SQL.md` v1.8.1) ni W10.**
**Fecha de cierre:** 2026-06-25.
**Base:** `FRONTEND_SUBSLICE0_CIERRE.md` (shell) · `FRONTEND_SUBSLICE1_CIERRE.md` (8 lecturas) · `CONTRATO_FRONTEND_PORTAL_v1.md` + `…_CIERRE.md`.
**Fuentes de este cierre:** runsheets de bloque `RUNSHEET_B1.md`, `RUNSHEET_B2.md`, `RUNSHEET_B2_FIX.md`, `RUNSHEET_B3.md`, `RUNSHEET_B4.md`; `B5_RUNSHEET_QA.md`; contrato `A10MP_CIERRE.md`; el código fuente de las pantallas; y la QA TEST de B5 (corrida OK por Franco, 2026-06-25).
**Stack:** React 18 + Vite 5 + TypeScript strict + Tailwind 3 + Supabase JS (solo auth/sesión) + `callPortal` + `react-router-dom` v6.

---

## 1. Alcance cerrado

Sobre los **cimientos de escritura** (B1), las **4 pantallas de escritura** del portal — las únicas escrituras del Carril C frontend. Cada una consume un wrapper n8n firmado vía el gateway `portal-api` (envelope `{ok,data}`), ramificando por `body.ok`, con `estado_incierto` → reconsulta de la lectura companion (nunca retry ciego).

| Acción | Bloque | Pantalla | Transporte de `idempotency_key` | Particularidad |
|---|---|---|---|---|
| A08 `bloqueo.crear_manual` | B2 | `CrearBloqueo.tsx` | `none` | Guard por solapamiento (lo valida el backend); `id_cabana` obligatorio (bloqueo total no se expone). |
| A07 `reserva.crear_manual` | B3 | `CrearReserva.tsx` | `none` (idempotencia derivada por el wrapper → `idempotent_match`) | Seña `0` = auto 50%; medio default transferencia; contacto teléfono **o** email. |
| A11 `cargar.gasto_interno` | B4 | `CargarGasto.tsx` | `sibling` (top-level) | Form con condicionales por clase A/C/D/E y por pagador (caja/socio); coherencia por construcción. |
| A10-MP `cobranza.registrar_cobro` | B5 | `RegistrarCobro.tsx` | `payload` (key **dentro** del payload) | Cobranza multi-porción (efectivo / transferencia bancaria·mp / otros) + recargo 5%; bloqueo de sobrepago. |

**B5 usa exclusivamente `cobranza.registrar_cobro`.** El endpoint viejo **W10 `cobranza.registrar_saldo` queda deprecated-in-place**: sigue desplegado y validado en backend, pero **desaparece del frontend** porque su entrada del registry se renombró a `registrar_cobro` (tolerancia-forward: una acción que A02 emite pero sin entrada en el registry se ignora). **Sin tocar backend.**

---

## 2. Bloques (resumen de entrega)

- **B1 — cimientos** (`RUNSHEET_B1.md`): 9 archivos (7 nuevos: `useEnviar.ts`, `erroresEscritura.ts`, `estilos.ts`, `Campo.tsx`, `BotonSubmit.tsx`, `TarjetaExito.tsx`, `Banner.tsx`; 2 modificados: `contratos.ts` +4 tipos de respuesta, `constantes.ts` +catálogos). `typecheck`/`build` EXIT 0; **107 módulos** (= baseline: los cimientos aún no entran al bundle hasta que una pantalla los importa).
- **B2 — A08** (`RUNSHEET_B2.md`): 3 archivos (`useEnviar.ts` patch + `CrearBloqueo.tsx` + `rutas.tsx`). EXIT 0; **115 módulos**. **+ B2_FIX** (`RUNSHEET_B2_FIX.md`): bug de `useEnviar` bajo React.StrictMode (ref `montado` quedaba en `false` permanente → spinner eterno, sin tarjeta ni banner). Fix de 1 línea (re-setear `montado.current = true` en el cuerpo del efecto). EXIT 0; 115 módulos. Re-test TEST OK.
- **B3 — A07** (`RUNSHEET_B3.md`, v3): `CrearReserva.tsx` + `rutas.tsx`. EXIT 0; **116 módulos**. *Nota:* la **estabilidad del alta OK** dependió de un fix de **backend/n8n** (forma del envelope del `Respond to Webhook` y/o timeout `N8N_TIMEOUT_MS=10s`, diagnosticado en `RUNSHEET_B3` Parte A) — **fuera del scope frontend y no documentado en estos runsheets** (acción de backend de Franco). B3 figura cerrado por la línea base de `RUNSHEET_B4` ("B1+B2+B3, todos cerrados").
- **B4 — A11** (`RUNSHEET_B4.md`): `CargarGasto.tsx` + `rutas.tsx`. EXIT 0; **117 módulos**.
- **B5 — A10-MP** (`B5_RUNSHEET_QA.md` + esta conversación): **1 nuevo** (`RegistrarCobro.tsx`) + **6 modificados** (`contratos.ts`, `constantes.ts`, `actionRegistry.ts`, `rutas.tsx`, `PlaceholderView.tsx`, `CobranzaSaldos.tsx`). EXIT 0; **118 módulos** (JS ~452 kB). **QA TEST OK** (todos los casos, ver §6).

---

## 3. Decisiones lockeadas durante el sub-slice 2 (🔒 no reabrir)

**Asignadas en los runsheets B1-B4** (pendientes de propagar a `DECISIONES_NO_REABRIR.md`, ver §8):

- **D-FE-19** — `useEnviar`: hook único de escritura (anti-doble-click, transporte por acción, `estadoIncierto` flag, guard de unmount, sin localStorage/sessionStorage).
- **D-FE-20** — ciclo de `idempotency_key`: key nueva por submit; `reintento` reusa la retenida; `reset()` la suelta; **reset-on-edit** (editar tras error/incierto suelta la key → próximo submit = key nueva).
- **D-FE-21** — bloqueo duro anti-sobrepago (A10): mostrar saldo vivo, deshabilitar submit si `suma_saldo > saldo_real` o saldo ≤ 0, re-render del saldo al éxito, reconsultar A05/A12 ante `conflicto`. **Materializado en B5.**
- **D-FE-22** — `estado_incierto` como flag aparte + banner con **acción companion** (verificar la lectura) + **Reintentar** (misma key).
- **D-FE-23** — validación cliente = **espejo del validador del gateway**, nunca más estricta.
- **D-FE-24** — catálogos TEST confirmados por snapshot (`SOCIOS_TEST`/`ZONAS_TEST`/`CABANAS_TEST`); pre-OPS sigue bajo P-FE-01/05.
- **D-FE-25** — tarjeta de éxito con acciones + **dos familias de error** (A: `message` del backend / B: mensaje genérico).
- **D-FE-26** — seña `0` = auto 50% (A07): el frontend convierte antes de enviar y **nunca manda `monto_sena: 0`** (0 = auto; una seña real $0 sería otra decisión).

**Nuevas de B5** (descripción; el **ID D-FE se asigna en la propagación**, §8 / pieza 2, partiendo del último en el repo = D-FE-18):

- **Registry reemplaza `cobranza.registrar_saldo` por `cobranza.registrar_cobro`** (mismo label "Registrar cobro", grupo `cobranzas`, orden 20, ruta `/cobranzas/registrar`).
- **Tolerancia-forward para ocultar W10 en el frontend** sin tocar backend (acción emitida por A02 sin entrada en el registry = ignorada).
- **Tipado estricto `SubtipoTransferencia = 'bancaria' | 'mp'`** compartido (`contratos.ts` → `constantes.ts`, `import type`, sin ciclo).
- **Separación visual saldo / extra / total**: `suma_saldo` baja el saldo; el **recargo (extra) se muestra pero NO baja** el saldo estimado (espeja la contabilidad D-C-68).
- **Deep-link A12 → A10**: botón "Cobrar" por fila en `CobranzaSaldos` → `/cobranzas/registrar?id_reserva=ID` (solo navegación; la pantalla destino revalida estado/saldo con `reserva.detalle`).

---

## 4. Lecciones (🔒)

**De `RUNSHEET_B2_FIX.md`** (pendiente de propagar a `Lecciones_Aprendidas.md`, ver §8):

- **L-FE-03** — el patrón "mounted ref" (`useRef(true)` + efecto que solo limpia) **se rompe bajo React.StrictMode en dev**: el doble-invoke (montar → cleanup → montar) deja el ref en `false` permanente porque el cuerpo del efecto no lo re-setea. Fix: setear `ref.current = true` en el cuerpo del efecto. Alternativa válida: flag local por corrida del efecto (lo que ya hace `useAction`, por eso las lecturas no lo sufrían).

**De B5** (descripción; el **ID L-FE se asigna en la propagación**, §8 / pieza 3, partiendo del último en el repo = L-FE-02):

- El **retry de `estado_incierto` NO debe generar key nueva**: reusa la misma (`enviar(payload, {reintento:true})`). *Hallazgo señalado:* en B4 (`CargarGasto`) el botón de reintento llama `submit()` (genera key nueva) mientras el banner sugiere que reusa la clave — posible inconsistencia a revisar; **B5 lo hace correctamente** y no copia ese patrón.
- **Editar** montos/medio/otros/notas tras un error/incierto **debe soltar la key** (`reset()`) → próximo submit = key nueva.
- **Deep-link de lectura a escritura manteniendo la validación en destino**: el origen (A12) solo navega; el destino (A10) revalida estado/saldo. Evita acoplar el origen a la forma del payload de destino.
- El **recargo se muestra pero no baja el saldo** (`extra` ≠ `saldo`; D-C-68): el cálculo en vivo no lo resta del saldo estimado.
- B5 confirmó que **el frontend puede reemplazar un endpoint deprecated (W10) por uno nuevo sin tocar backend** (rename de la entrada del registry + tolerancia-forward).

---

## 5. Mapa del código del sub-slice 2

**Cimientos (B1):** `hooks/useEnviar.ts`, `lib/erroresEscritura.ts`, `ui/estilos.ts`, `ui/Campo.tsx`, `ui/BotonSubmit.tsx`, `ui/TarjetaExito.tsx`, `ui/Banner.tsx`; +tipos de respuesta en `lib/contratos.ts`; +catálogos en `lib/constantes.ts`.
**Pantallas:** `screens/CrearBloqueo.tsx` (A08), `screens/CrearReserva.tsx` (A07), `screens/CargarGasto.tsx` (A11), `screens/RegistrarCobro.tsx` (A10-MP).
**Cableado:** `app/rutas.tsx` (las 4 escrituras en `PANTALLAS`), `app/PlaceholderView.tsx` (set `ESCRITURAS`), `lib/actionRegistry.ts` (entrada `cobranza.registrar_cobro`).
**Deep-link (B5):** `screens/CobranzaSaldos.tsx` (columna "Cobrar"; A12 era read-only, ahora suma navegación, sin tocar su endpoint).

`callPortal.ts`, `useAction.ts` y las pantallas/atoms de lectura no se tocaron (salvo el deep-link en `CobranzaSaldos.tsx`).

---

## 6. Validaciones y QA

- **Por bloque:** `typecheck` (`tsc --noEmit`) + `build` (`tsc && vite build`) **EXIT 0** en cada entrega. Progresión de módulos: **107 → 115 → 116 → 117 → 118**.
- **B5 — QA TEST OK** (`B5_RUNSHEET_QA.md`, corrida por Franco 2026-06-25):
  - **Por rol:** jenny no ve "Registrar cobro" ni accede por URL (RutaProtegida; defensa en profundidad: gateway `rol_no_permitido`); vicky y socio cobran.
  - **Funcional:** solo efectivo · transferencia bancaria · transferencia MP · otros con origen/descripción · mixto · cobro que salda · sobrepago bloqueado en UI · conflicto por saldo stale → "Verificar reserva" · retry idempotente · edición tras error/incierto = key nueva. Todos OK.
  - **Payload:** `action` siempre `cobranza.registrar_cobro`, **nunca** `cobranza.registrar_saldo`; sin campos de control; `origen_otros`/`descripcion_otros` solo si `monto_otros > 0`; `idempotency_key` dentro del payload.
  - **Visual:** mobile-first; resumen con `suma_saldo`/recargo/total/saldo estimado; el recargo no baja el saldo; success card con el `response.data`.
- **Contrato A10-MP** (`A10MP_CIERRE.md`, backend): cerrado y validado en TEST — smoke directo **40/40**, gateway **13/13**, SQL **6/6**, rollback atómico **PASS**, teardown **0 residual**; CATALOG **14**; roles `vicky`/`socio`; jenny → `rol_no_permitido`. El frontend B5 lo consume **sin tocarlo**.

---

## 7. Pendientes / no implementado (honesto, sin inventar)

- **"Ver detalle" A12 → A05 NO implementado.** `RUNSHEET_B4` §7 anticipó para B5 el deep-link A12 → A05 por `?id_reserva` y que A05 (`ReservaDetalle`) leyera ese query param. En este B5 se implementó **solo** el deep-link A12 → A10 (cobro): verificado que `ReservaDetalle` sigue con id-input manual (no usa `useSearchParams`) y `CobranzaSaldos` solo tiene el botón "Cobrar" (no "Ver detalle"). Queda **pendiente** como ítem de UX (no es una escritura).
- **P-FE-02 (anti-sobrecobro).** La parte de **A10 en el portal interno** queda cubierta por el bloqueo de UI de B5 + el anti-sobrepago HARD del backend. La **web pública / Mercado Pago / flujo autónomo del cliente** siguen pendientes (otro frente). Se afina al propagar (§8 / pieza 5); **no se cierran pendientes de otro frente**.
- **A07 alta-OK estable** dependió de un fix de **backend/n8n** (envelope del `Respond` / timeout, `RUNSHEET_B3` Parte A) **no documentado en los runsheets frontend**.
- **D-FE-19..26 + las decisiones nuevas de B5, y L-FE-03 + las lecciones de B5, NO están propagadas** a los satélites todavía — es la propagación pendiente de §8.

---

## 8. Propagación a satélites — plan a ejecutar (pieza por pieza, Franco pasa los archivos; nada se commitea hasta auditoría)

EOL verificado con `git ls-files --eol`: los 4 satélites están en **LF** (sin `.gitattributes`/`autocrlf`). Se editan en **LF estricto**, con anclas `count==1`. (La nota previa de CRLF/mixto provenía de copias viejas de `/mnt/project`, descartadas.)

- **Pieza 2 — `DECISIONES_NO_REABRIR.md`:** propagar **D-FE-19..26** (de los runsheets) + las **nuevas de B5** (registry rename + tolerancia-forward, separación visual saldo/extra/total). Las de idempotencia/sobrepago/retry/reset ya están cubiertas por D-FE-19..26. IDs nuevos sin colisionar (último en el repo = **D-FE-18**). Solo decisiones estables; sin sobre-documentar detalles menores.
- **Pieza 3 — `Lecciones_Aprendidas.md`:** **L-FE-03** (StrictMode) + lecciones de B5 (retry sin key nueva, reset-on-edit, deep-link con validación en destino, recargo no baja saldo, reemplazo de endpoint deprecated sin tocar backend). Sin duplicar decisiones. Último en el repo = **L-FE-02**.
- **Pieza 4 — `ESTADO_ACTUAL_VITA_DELTA.md`:** frontend de "sub-slice 1 cerrada / próximas escrituras" → **"sub-slice 2 (4 escrituras) cerrada en TEST"**; mencionar B1-B5; dejar claro que **OPS no fue tocado** y el canónico sigue v1.8.1.
- **Pieza 5 — `Pendiente_pre_produccion.md`:** actualizar **P-FE-02** con precisión (A10-MP del portal interno cubierto; web/MP/autónomo pendientes); agregar el "Ver detalle" pendiente; **no cerrar pendientes de otro frente**.

---

## 9. Estado y próximo paso

**Sub-slice 2 frontend (las 4 escrituras) cerrada en TEST**, build verde en todos los bloques, QA por rol y funcional de B5 OK. **OPS, canónico (`6B_SCHEMA_SQL.md` v1.8.1), backend, gateway, wrapper n8n y W10 intactos.** Próximo: ejecutar la propagación a satélites (§8) **pieza por pieza**, tras la auditoría de este cierre.
