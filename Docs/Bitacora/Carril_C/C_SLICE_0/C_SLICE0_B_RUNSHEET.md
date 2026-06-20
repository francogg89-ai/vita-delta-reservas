# Runsheet — Carril C / Slice 0 / Fase B: Edge Function `portal-api` (TEST)

**Entorno:** Supabase **TEST**. OPS no se toca.
**Objetivo:** desplegar `portal-api` en TEST con `verify_jwt = false`, secreto HMAC seteado, y dejar `sesion.contexto` (A02) verde por rol.
**Decisiones:** D-C-13/14/15/18/22/29/30/31/34 + **D-C-35** (HTTP 200 + envelope para resultados manejados).
**Artefacto:** `C_SLICE0_B_portal-api_index.ts` → colocar como `supabase/functions/portal-api/index.ts`.

Prerrequisito: Fase A verde (tabla `portal_usuarios` sembrada con los 5 usuarios en Auth TEST).

---

## 0. Generar y setear el secreto HMAC (TEST)

Generá un secreto de alta entropía **localmente** (no lo pegues en el chat ni en el repo):
```bash
openssl rand -hex 32
```
Seteálo como secret de la Edge Function en el proyecto TEST. Dos opciones:
- **CLI:** `supabase secrets set VITA_HMAC_SECRET="<valor>" --project-ref <REF_TEST>`
- **Dashboard:** Edge Functions → Secrets → Add new secret → `VITA_HMAC_SECRET`.

> `SUPABASE_URL` y la secret key (`SUPABASE_SECRET_KEYS` / `SUPABASE_SERVICE_ROLE_KEY`) ya vienen **auto-inyectadas**; no las setés vos. El código resuelve la secret key de forma defensiva (nueva o legacy) y aborta ruidoso si falta algo.

---

## 1. `config.toml` — `verify_jwt = false`

**Mergeá** este bloque en tu `supabase/config.toml` (no reemplaces el archivo entero):
```toml
[functions.portal-api]
verify_jwt = false
```
Por qué: con `verify_jwt = true` la plataforma rechaza JWT ausente/inválido **antes** del handler, con su propio 401 — rompe el envelope uniforme (D-C-18). Además, con las API keys nuevas de Supabase, el camino soportado es `verify_jwt = false` + autorizar en código. La validación real del JWT la hace `portal-api` con `getUser`.

---

## 2. Deploy a TEST

```bash
supabase functions deploy portal-api --project-ref <REF_TEST>
```
Con el bloque de `config.toml` presente, `verify_jwt=false` se respeta. (Equivalente por flag: `supabase functions deploy portal-api --no-verify-jwt --project-ref <REF_TEST>`.)

Si preferís sin CLI: Dashboard → Edge Functions → crear `portal-api`, pegar el `index.ts`, y desactivar "Verify JWT" en la config de la función.

---

## 3. Obtener un JWT de prueba (password grant)

Necesitás la **publishable/anon key** del proyecto TEST (Dashboard → Project Settings → API keys). Llamémosla `PUBKEY` (sirve `sb_publishable_...` o la anon legacy). Y la password que pusiste a cada usuario en Fase A.

```bash
export SUPABASE_URL="https://<REF_TEST>.supabase.co"
export PUBKEY="<publishable_o_anon_key>"

# JWT de Vicky (repetir cambiando email/password para franco, rodrigo, remo, jenny)
export JWT_VICKY=$(curl -s "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $PUBKEY" -H "Content-Type: application/json" \
  -d '{"email":"vicky@vitadelta.test","password":"<password-de-vicky>"}' | jq -r .access_token)

echo "$JWT_VICKY" | cut -c1-20   # sanity: arranca con "ey..."
```
Las passwords van inline en tu terminal, **no** al repo.

---

## 4. Smokes de `sesion.contexto`

Plantilla:
```bash
curl -s -X POST "$SUPABASE_URL/functions/v1/portal-api" \
  -H "apikey: $PUBKEY" \
  -H "Authorization: Bearer $JWT_VICKY" \
  -H "Content-Type: application/json" \
  -d '{"action":"sesion.contexto","payload":{}}' | jq .
```

| # | Caso | Cómo | Esperado |
|---|------|------|----------|
| 1 | Vicky OK | JWT de vicky | `ok:true`, `data.rol="vicky"`, `data.nombre="vicky"`, `data.acciones=["sesion.contexto"]` |
| 2 | Socio OK | JWT de franco | `ok:true`, `data.rol="socio"`, `data.nombre="franco"` |
| 3 | Jenny OK | JWT de jenny | `ok:true`, `data.rol="jenny"`, `data.nombre="jenny"` |
| 4 | Sin JWT | omitir el header `Authorization` (dejar `apikey`) | `ok:false`, `error.code="no_autorizado"` |
| 5 | JWT basura | `Authorization: Bearer abc.def.ghi` | `ok:false`, `error.code="no_autorizado"` |
| 6 | Acción desconocida | `-d '{"action":"foo.bar"}'` con JWT válido | `ok:false`, `error.code="accion_desconocida"` |
| 7 | (Opcional) Usuario inactivo | en SQL Editor TEST: `UPDATE portal_usuarios SET activo=false WHERE nombre='jenny';` → llamar con JWT de jenny → luego revertir a `true` | `ok:false`, `error.code="no_autorizado"` |

Notas:
- **`rol_no_permitido` no es testeable en Slice 0**: la única acción habilita los 3 roles. Aparecerá como caso real en Slice 1, cuando entre una acción restringida por rol (ej. A04, sin jenny).
- Objetivo: casos 1–6 verdes (7 opcional). Eso cierra el primer vertical end-to-end `login → JWT → gateway → rol → set de acciones`, sin tocar n8n.

---

## 5. Nota diagnóstica (la única cosa a vigilar)

El handler valida el JWT con un cliente creado con la **secret key** (`getUser`). Es lo esperable y la secret key nunca sale del runtime. **Si** un login válido (caso 1/2/3) devolviera `no_autorizado` pese a un JWT correcto, el sospechoso es que `getUser` rechace la secret key como `apikey` en tu estado de migración. Diagnóstico y fix listos: pasamos `getUser` a un cliente con la **publishable key** (resolviendo `SUPABASE_PUBLISHABLE_KEYS[default]` / `SUPABASE_ANON_KEY`) y dejamos la secret key solo para el read de `portal_usuarios`. Es un cambio chico; lo aplico apenas el smoke lo muestre. No es fallo silencioso: el caso 1 lo revela de una.

---

## 6. Qué NO va al repo
- El valor de `VITA_HMAC_SECRET`.
- Las passwords de los usuarios y los JWT generados.
- `PUBKEY` / secret keys / connection strings.

Sí van al repo: `supabase/functions/portal-api/index.ts` y el bloque de `config.toml` (sin secretos).

---

## Al terminar
Pasame las salidas de los casos 1–6. Con eso cerrado, **Fase C — patrón de validación n8n**: workflow que revalida **HMAC (raw body) + rol + `configuracion_general('ambiente')`** y el **probe de ambiente** que prueba el muro TEST≠OPS firmando `ambiente_esperado='ops'` contra el workflow TEST (rechaza, sin tocar OPS). Ahí se ejercita por primera vez la firma HMAC end-to-end y confirmamos la fidelidad del raw body.
