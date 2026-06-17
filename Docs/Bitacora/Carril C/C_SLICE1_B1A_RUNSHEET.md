# RUNSHEET — Carril C / Slice 1 / Bloque 1A — Gateway: infraestructura común

**Objetivo:** desplegar la infraestructura común del gateway (preflight de las dos env
vars nuevas + dispatch genérico a n8n con validación estricta del envelope + validadores
de payload). **NO se agrega A03 al CATALOG** (D-C-31): `sesion.contexto.acciones` debe
seguir devolviendo solo `["sesion.contexto"]`.

**Entorno:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`). **OPS no se toca.**
**Artefacto:** `C_SLICE1_B1A_portal-api_index.ts` → `supabase/functions/portal-api/index.ts`.

---

## Orden de ejecución (CRÍTICO)

El preflight es **global y duro**: si faltan `VITA_AMBIENTE` o `N8N_BASE_URL`, **toda**
acción (incluida `sesion.contexto`) responde 5xx. Por eso **primero las secrets, después
el deploy**. Si invertís el orden, vas a ver un falso "todo roto" hasta setear las vars.

### Paso 1 — Setear las dos secrets nuevas en TEST (ANTES del deploy)

Dashboard → Project Settings → Edge Functions → Secrets (o `supabase secrets set`):

- `VITA_AMBIENTE=test`
- `N8N_BASE_URL=https://federicosecchi.app.n8n.cloud/webhook`
  (base de **producción** de los webhooks, sin slash final — el código normaliza igual;
  ojo: los wrappers van a usar la URL `/webhook/...`, no `/webhook-test/...`, así que en
  Bloque 2/3 el workflow tiene que estar **publicado/activo**.)

**No tocar** `VITA_HMAC_SECRET` (ya seteado y rotado 2026-06-16), `SUPABASE_URL` ni la
secret key.

### Paso 2 — Deploy del `index.ts` nuevo

- Por Dashboard editor **o** CLI (`supabase functions deploy portal-api`).
- **L-C-06:** si lo editás/deployás por el **Dashboard**, se reactiva "Verify JWT with
  legacy secret". **Re-apagalo** (verify_jwt OFF) después del deploy, o usá CLI +
  `config.toml` (`verify_jwt=false`), que no se resetea.

### Paso 3 — No-regresión de `sesion.contexto` (debe quedar IDÉNTICO a Slice 0)

Reusá el tooling de smokes de Slice 0 (mismas llamadas a `…/functions/v1/portal-api`).
Esperado:

| # | Caso | Esperado |
|---|---|---|
| 1 | Vicky (JWT válido) | `{ok:true,data:{nombre:"vicky",rol:"vicky",acciones:["sesion.contexto"]}}` ← **acciones SOLO sesion.contexto** (A03 NO visible: confirma el split) |
| 2 | Franco | `…rol:"socio"…` (acciones: `["sesion.contexto"]`) |
| 3 | Jenny | `…rol:"jenny"…` (acciones: `["sesion.contexto"]`) |
| 4 | sin JWT | `{ok:false,error:{code:"no_autorizado"}}` |
| 5 | JWT basura | `{ok:false,error:{code:"no_autorizado"}}` |
| 6 | acción desconocida | `{ok:false,error:{code:"accion_desconocida"}}` |

### Paso 4 — Sanity del preflight (recomendado)

- Si **cualquier** llamada responde **HTTP 5xx** con `error_interno` y el log dice
  `env vars faltantes/inválidas: …`, falta setear una secret del Paso 1 (o `VITA_AMBIENTE`
  no es exactamente `test`/`ops`). Corregir y re-testear.

---

## Criterio de cierre de Bloque 1A

- **6/6** smokes verdes, idénticos a Slice 0.
- `acciones === ["sesion.contexto"]` en los tres roles (prueba de que A03 **no** quedó
  visible antes de tiempo).
- Sin 5xx por preflight con las secrets seteadas.

Si todo eso da, avanzamos al **Bloque 2** (wrapper `portal-a03-limpieza`). El dispatch a
n8n queda en el código pero **no se ejercita** todavía (no hay acción n8n en el CATALOG):
se prueba recién con A03 cableada en el Bloque 3.

**Si algo difiere del esperado, no avanzar — reportar y verificamos.**
