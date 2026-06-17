# RUNSHEET — Carril C / Slice 1 / Bloque 3 — Cablear A03 a `portal-api` (TEST)

**Objetivo:** agregar A03 al CATALOG de `portal-api` y validar el camino **completo** vía el
gateway (`login → JWT → portal-api → CATALOG → HMAC → wrapper n8n → revalidación → reads →
render → envelope`). Es la extensión quirúrgica final del Edge Function.

**Entorno:** TEST (`vita-delta-test`). **OPS y `6B_SCHEMA_SQL.md` intocables.**
**Artefactos:** `C_SLICE1_B3_portal-api_index.ts` → `supabase/functions/portal-api/index.ts` ·
`C_SLICE1_B3_smoke_a03_via_portal.ps1`.

**Único cambio vs Bloque 1A:** una línea en el CATALOG —
`'calendario.limpieza': { handler:'n8n', roles:['jenny','vicky','socio'], webhook:'portal-a03-limpieza', validate: payloadVacio }`.
Todo el resto (preflight, dispatch n8n, validación de envelope, validadores) ya estaba desde 1A.

> El key `calendario.limpieza` **coincide con `EXPECTED_ACTION`** del wrapper (action binding), y
> el webhook `portal-a03-limpieza` se une con `N8N_BASE_URL` → `…/webhook/portal-a03-limpieza`.

---

## Precondición

El wrapper `portal-a03-limpieza` debe estar **activo** en n8n TEST con su secreto cargado (Bloque
2, ya verificado 7/7). Si lo desactivaste, reactivalo.

## Pasos

### 1 — Deploy de `portal-api`
Reemplazá `index.ts` por `C_SLICE1_B3_portal-api_index.ts` y deployá. **L-C-06:** si lo hacés por
Dashboard, re-apagá "Verify JWT with legacy secret" (verify_jwt OFF) después del deploy.
(No hay env vars nuevas: `VITA_AMBIENTE` y `N8N_BASE_URL` ya están desde 1A.)

### 2 — Smokes vía portal-api
En `C_SLICE1_B3_smoke_a03_via_portal.ps1`, pegá `ANON_KEY` y los 3 passwords. Corré:

```
powershell -ExecutionPolicy Bypass -File .\C_SLICE1_B3_smoke_a03_via_portal.ps1
```

Esperado (por cada usuario jenny / vicky / franco):

| Chequeo | Esperado |
|---|---|
| `sesion.contexto` → acciones | incluye **`calendario.limpieza`** (A03 ya visible) |
| `calendario.limpieza` → ok | `ok:true` |
| `calendario.limpieza` → formato | `formato=html` |
| `calendario.limpieza` → html | `html_len > 0` (HTML real) |

Y un caso final: **sin JWT → `no_autorizado`**.

Los tres roles dan `ok:true` (A03 habilita jenny/vicky/socio). El caso `rol_no_permitido` ya se
probó **directo al wrapper** en Bloque 2 (rol intruso); vía gateway no aplica para A03.

> **Hito alcanzado:** Jenny entra al portal y ve su calendario de limpieza de punta a punta — el
> "menor slice operable" del diseño (Slice 0 + A03).

---

## Criterio de cierre de Bloque 3 (y de A03)

- 3/3 usuarios: `acciones` incluye `calendario.limpieza`, y `calendario.limpieza` da `ok:true
  formato=html` con HTML real.
- sin JWT → `no_autorizado`.

Con eso, **A03 queda cerrada de punta a punta** (gateway + wrapper + datos). Es la primera acción
real del portal funcionando completa.

---

## Después de A03 (resto de Slice 1)

A03 fue el camino más largo (incluyó toda la infra del gateway en 1A + el primer wrapper). Las que
siguen reusan todo eso y son más cortas:

- **A04** (calendario operativo 4 meses): wrapper casi gemelo de A03 (misma estructura, ventana 120
  días, render con montos → roles `{vicky,socio}`). Acá aparece el otro hito: **Jenny→A04
  `rol_no_permitido`** (rebota en el gateway por el CATALOG).
- **A06 / A12** (prereservas / saldos): wrappers que devuelven `data:{filas}` (JSON), no HTML.
- **A05** (detalle por id_reserva): wrapper con `validate: payloadIdReserva` (el validador estricto
  ya está en el gateway) + la query compuesta con `saldo_real` (D-C-40).

Cierre formal al final de Slice 1: `C_SLICE1_CIERRE.md` + deltas a satélites (D-C-36…D-C-40 + las
del action binding y L-C-10, con `count==1` y EOL por archivo). **No se toca OPS ni el canónico.**

Pegame la salida del smoke. Si está 3/3 + no_autorizado, **A03 cerrada**.
