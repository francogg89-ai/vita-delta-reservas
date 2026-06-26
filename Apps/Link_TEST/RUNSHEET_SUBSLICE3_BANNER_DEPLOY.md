# RUNSHEET — Sub-slice 3 · Bloque Banner TEST + Deploy Vercel

**Carril:** C — Portal Operativo Interno (frontend). **Entorno:** TEST.
**Alcance de este runsheet:** aplicar el bloque *banner de ambiente* (fix menor de frontend) + publicar el deploy TEST en Vercel y pasar los 7 gates.
**No toca:** backend, gateway `portal-api`, wrappers n8n, OPS, canónico (v1.8.1), W10 ni el contrato. Solo: frontend (banner), `vercel.json` (fallback SPA) y config de deploy.
**Regla dura:** **no se comparte el link ni arranca el piloto hasta tener los 7 gates en verde** (§4).

---

## 0. Qué cambia (bloque banner)

4 archivos (`+89 / −1`), verificado en clon limpio con `typecheck` + `build` **EXIT 0** (120 módulos = 118 + 2 nuevos):

| Archivo | Acción | Qué hace |
|---|---|---|
| `src/lib/ambiente.ts` | nuevo | Discrimina ambiente por `VITE_SUPABASE_URL`: contiene el ref TEST `bdskhhbmcksskkzqkcdp` → `'test'`; cualquier otra cosa → `'desconocido'` (defensivo). Sin `VITE_AMBIENTE` (una sola fuente de verdad). |
| `src/app/BannerAmbiente.tsx` | nuevo | Barra fija arriba de todo (visible **pre-login**) + setea el **título de pestaña**. `'test'` → amarillo "AMBIENTE DE PRUEBA · TEST". `'desconocido'` → rojo "AMBIENTE NO RECONOCIDO - NO OPERAR". |
| `src/App.tsx` | editado | Monta `<BannerAmbiente/>` y compensa la barra con `pt-8` sin romper el `min-h-full` de las pantallas. |
| `vercel.json` | nuevo | Framework Vite + **fallback SPA** (todas las rutas → `/index.html`), para que el deep-link/refresh de rutas (ej. `/cobranzas/registrar`) no tire 404. |

**Mecánica clave:** el banner sale del **mismo dato** que apunta el build a TEST. Si el banner del deploy está **amarillo**, es prueba visual de que la env var apunta a TEST (gate #3 ⟺ gate #4). Si sale **rojo**, la env var falta o está mal → arreglar en Vercel (§4, gate #4).

---

## 1. Aplicar el cambio (elegí una vía)

**Vía A — patch (recomendada):** desde la raíz del repo,
```
git apply banner_subslice3.patch
```
**Vía B — manual:** copiá los 4 archivos provistos a sus rutas (`ambiente.ts` → `src/lib/`, `BannerAmbiente.tsx` → `src/app/`, `App.tsx` reemplaza el existente, `vercel.json` → raíz de `Apps/portal-operativo/`).

## 2. Verificar local (gate #1)

```
cd Apps/portal-operativo
npm ci            # si no instalaste deps en esta máquina
npm run typecheck # EXIT 0
npm run build     # EXIT 0  (debe decir ~120 modules transformed)
```
Si querés ver el banner en local: `npm run dev` con un `.env` que tenga `VITE_SUPABASE_URL=https://bdskhhbmcksskkzqkcdp.supabase.co` → barra **amarilla**. Sin `.env` → barra **roja** (fail-safe, esperado).

## 3. Commit

Commiteá los 4 archivos. Sugerencia de mensaje: `feat(portal): banner ambiente TEST por URL + fallback SPA (sub-slice 3)`.

---

## 4. Deploy en Vercel + los 7 gates

**Setup Vercel (una vez):**
1. New Project → Import el repo `francogg89-ai/vita-delta-reservas`.
2. **Root Directory: `Apps/portal-operativo`** ← lo más importante (es un subdirectorio del repo).
3. Framework Preset: **Vite** (auto; `vercel.json` lo pinea igual). Build: `npm run build`. Output: `dist`. (Todo ya está en `vercel.json`.)
4. **Environment Variables** (Production):
   - `VITE_SUPABASE_URL` = `https://bdskhhbmcksskkzqkcdp.supabase.co`
   - `VITE_SUPABASE_ANON_KEY` = *(la anon/publishable de TEST — pegala vos en el panel; no va al repo ni a este runsheet)*
5. Deploy. (Si cambiás una env var después, **redeployá**: Vite inyecta la env en build-time.)

> **Sin tocar Supabase Auth:** el login es solo email/password con usuarios ya creados (Auto Confirm). No hace falta agregar el dominio del deploy como Site URL / Redirect URL. (Eso recién importaría si más adelante usás recovery o magic links.)

**Checklist de gates (todos en verde antes de compartir):**

- [ ] **Gate #1 — typecheck + build EXIT 0** (ya verificado en clon; reconfirmar local, §2).
- [ ] **Gate #2 — deploy TEST publicado** (Vercel da una URL `*.vercel.app`).
- [ ] **Gate #3 — banner visible** = barra **amarilla** "AMBIENTE DE PRUEBA · TEST" arriba, en el deploy.
- [ ] **Gate #4 — env apunta a TEST** (`…bdskhhbmcksskkzqkcdp.supabase.co`). *Prueba visual:* si el banner es amarillo, la URL es la de TEST; si es **rojo**, la env falta/está mal → corregir y redeployar.
- [ ] **Gate #5 — incógnito sin login = nada operativo.** Abrí la URL en incógnito → ves login + banner, y **ningún** menú/saldo/dato. (Por diseño: todo lo operativo cuelga de la sesión autenticada.)
- [ ] **Gate #6 — login mínimo por rol.** jenny → solo "Calendario de limpieza". vicky → menú completo. socio (franco/rodrigo) → menú completo. *(Asegurate de tener seteadas las contraseñas de rodrigo/remo en el dashboard de Supabase — nunca se logueó nadie con ellas.)*
- [ ] **Gate #7 — sin secretos.** Repo escaneado: **0** `service_role`, 0 claves `eyJ…`, 0 valores de HMAC, sin `.env` real trackeado. En el host: solo las 2 `VITE_*` (browser-safe). No pegar la anon key en chat/logs/instrucciones (en el panel de Vercel está bien).

---

## 5. Recién con los 7 gates en verde

Pasame la **URL del deploy** y te entrego (siguiente bloque): **instrucciones cortas por rol** (Jenny / Vicky / socios) con el link real, y confirmamos el **tracker de feedback** (ya provisto, `.xlsx`). Ahí sí se comparte el link y arranca la sesión guiada.

**Alternativa documentada (solo si Vercel trabara algo):** Cloudflare Pages → conectar repo, Root directory `Apps/portal-operativo`, build `npm run build`, output `dist`, mismas 2 env vars, y agregar `public/_redirects` con una línea `/* /index.html 200` (CF Pages no lee `vercel.json`).

---

## Recordatorio de fuente de verdad

A10 en el frontend = **`cobranza.registrar_cobro`** (B5 / Sub-slice 2), ya en el repo. No se reabre el contrato viejo ni se vuelve a `registrar_saldo`.
