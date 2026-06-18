# RUNSHEET — Carril C / Slice 1 / Bloque 5 — Cablear A04 a `portal-api` (TEST)

**Objetivo:** agregar **A04** al CATALOG de `portal-api` y validar el camino **completo** vía el gateway (`login → JWT → portal-api → CATALOG → HMAC → wrapper n8n → revalidación → reads → render → envelope con montos`). Es la segunda mitad del cableado de A04 (la primera fue B4, el wrapper directo).

**Entorno:** TEST (`vita-delta-test`). **OPS y `6B_SCHEMA_SQL.md` intocables.**
**Artefactos:** `C_SLICE1_B5_portal-api_index.ts` → `supabase/functions/portal-api/index.ts` · `C_SLICE1_B5_smoke_a04_via_portal.ps1`.

**Único cambio vs B3:** una línea en el CATALOG —
`'calendario.operativo': { handler:'n8n', roles:['vicky','socio'], webhook:'portal-a04-operativo', validate: payloadVacio }`.
Todo el resto (preflight, dispatch n8n, validación de envelope, validadores) ya estaba. El diff contra B3 es exactamente ese bloque (entrada + comentario); nada más se tocó.

> El key `calendario.operativo` **coincide con `EXPECTED_ACTION`** del wrapper (action binding, D-C-41), y el webhook `portal-a04-operativo` se une con `N8N_BASE_URL` → `…/webhook/portal-a04-operativo`.
> **Diferencia clave con A03:** A04 habilita **solo `vicky`/`socio`** (D-C-39). Jenny no ve económicos: cuando pide `calendario.operativo`, el gateway la rebota con `rol_no_permitido` en la allowlist (línea ~392), **antes de firmar** y sin tocar n8n.

---

## Precondición

El wrapper `portal-a04-operativo` debe estar **activo** en n8n TEST con su secreto cargado en el nodo `validar_firma_ts_rol` (Bloque 4, ya verificado 8/8 directo al wrapper). Si lo desactivaste, reactivalo.

## Pasos

### 1 — Deploy de `portal-api`
Reemplazá `index.ts` por `C_SLICE1_B5_portal-api_index.ts` y deployá. **L-C-06:** si lo hacés por Dashboard, re-apagá "Verify JWT with legacy secret" (verify_jwt OFF) después del deploy.
(No hay env vars nuevas: `VITA_AMBIENTE`, `N8N_BASE_URL` y `VITA_HMAC_SECRET` ya están desde 1A/B3.)

### 2 — Smokes vía portal-api
En `C_SLICE1_B5_smoke_a04_via_portal.ps1`, pegá `ANON_KEY` (la publishable key de TEST; copiala del smoke B3) y, si cambiaron, los passwords. Corré:

```
powershell -ExecutionPolicy Bypass -File .\C_SLICE1_B5_smoke_a04_via_portal.ps1
```

Esperado, **por rol** (el smoke es role-aware):

| Usuario | `sesion.contexto` → acciones | `calendario.operativo` |
|---|---|---|
| **vicky** (vicky) | **incluye** `calendario.operativo` | `ok:true`, `formato=html`, `html_len>0` (con montos) |
| **franco** (socio) | **incluye** `calendario.operativo` | `ok:true`, `formato=html`, `html_len>0` (con montos) |
| **jenny** (jenny) | **NO incluye** `calendario.operativo` | `ok:false`, `error.code=rol_no_permitido` |

Y un caso final: **sin JWT → `no_autorizado`**.

> **Hito alcanzado:** la otra mitad del par de hitos del diseño. En B3 fue "Jenny **entra** a su calendario de limpieza"; acá es "Jenny **NO entra** al operativo: rebota con `rol_no_permitido` desde el gateway, antes de firmar". Vicky y los socios sí ven el operativo completo con montos. Notá que el menú de jenny (`sesion.contexto`) tampoco ofrece la acción — el gateway expone solo lo permitido por rol.

---

## Criterio de cierre de Bloque 5 (y de A04)

- **vicky** y **franco (socio):** `sesion.contexto` incluye `calendario.operativo`, y `calendario.operativo` da `ok:true formato=html` con HTML real (con montos).
- **jenny:** `sesion.contexto` **no** incluye `calendario.operativo`, y `calendario.operativo` da `rol_no_permitido` (rebote en el gateway).
- **sin JWT → `no_autorizado`**.

Con eso, **A04 queda cerrada de punta a punta** (gateway + wrapper + datos), con la separación económica `{vicky, socio}` vs `jenny` validada en el camino real.

---

## Después de A04 (resto de Slice 1)

A04 reusó toda la infra (gateway de 1A + patrón de wrapper de A03). Lo que sigue, por el mismo molde:

- **A06 / A12** (prereservas / saldos): wrappers que devuelven `data:{filas}` (JSON), no HTML.
- **A05** (detalle por id_reserva): wrapper con `validate: payloadIdReserva` (el validador estricto ya está en el gateway) + la query compuesta con `saldo_real` (D-C-40).

**Cierre formal al final de Slice 1:** `C_SLICE1_CIERRE.md` + deltas a satélites (`DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, etc.), con `count==1` por anclaje y EOL por archivo. Ahí entran las decisiones de A04 (D-C-39 doble allowlist aplicada a `{vicky,socio}`, D-C-41 action binding) y la **lección Modo B** (n8n Cloud sin Variables → secreto HMAC pegado en el nodo, template commiteado sanitizado). **No se toca OPS ni el canónico.**

Pegame la salida del smoke. Si vicky/socio dan `ok:true html`, jenny `rol_no_permitido` (y sin la acción en el menú) y sin-JWT `no_autorizado`, **A04 cerrada**.
