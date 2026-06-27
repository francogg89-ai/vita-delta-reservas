# Bloque D — Runsheet: deploy del gateway `portal-api` a OPS

**Etapa:** Promoción coordinada del Carril C a OPS — Bloque D.
**Tipo:** deploy de **Edge Function** (NO es SQL). No hay un archivo SQL que correr.
**Artefacto a desplegar:** `portal-api_OPS_index.ts` (derivado de `A10MP_B2_portal-api_index.ts`).
**Proyecto:** Supabase **OPS** (`lpiatqztudxiwdlcoasv`).
**Quién ejecuta:** Franco (Dashboard / CLI de Supabase). Claude no toca OPS.

> **Qué pegás / corrés en este bloque:** (1) el contenido de `portal-api_OPS_index.ts` como código de la función `portal-api`; (2) las env vars/secrets de OPS (en el panel de secrets, valores reales que vos tenés, nunca acá); (3) el smoke de `sesion.contexto`. No se corre ninguna acción n8n vía gateway en este bloque.

---

## 0. Qué se despliega y qué NO cambió (resumen del diff)

El gateway OPS es el de TEST con **dos cambios, ninguno de lógica de negocio**:

| Cambió | Detalle |
|--------|---------|
| **CORS** | `Access-Control-Allow-Origin` pasa de `'*'` hardcodeado a `Deno.env.get('CORS_ALLOW_ORIGIN') ?? ''`. Validado en `resolveEnv` (preflight): si falta, el POST hace crash ruidoso y el header queda `''` (nunca `'*'`). |
| **13 webhooks** | El CATALOG apunta a los wrappers `__OPS` (8 lecturas + 5 escrituras). `sesion.contexto` es `edge`, no tiene webhook. |

**NO cambió (paridad lógica del catálogo, verificado):**
- Las **14 actions** (mismas keys), los **roles** por acción, los **validators**, los flags `isWrite`/`injectActor`/`needsIdempotencyKey`.
- La **semántica de errores** (envelope, allowlist de códigos, `estado_incierto`/`error_entorno`).
- La **firma HMAC** y la construcción del sobre.
- **W10** (`cobranza.registrar_saldo`) sigue **deprecated-in-place** por paridad (el frontend no la llama).

Validación previa a la entrega: `tsc --strict` EXIT 0, `esbuild` EXIT 0, catálogo lógico idéntico a TEST en las 14 entradas.

---

## 1. Env vars / secrets de OPS (configurar ANTES del deploy)

En el panel de **Edge Functions → Secrets** del proyecto OPS. **Ninguno de estos valores va al repo ni a este runsheet** (acá van solo los nombres y de dónde sale cada uno).

| Secret | Valor (de dónde sale) | Notas |
|--------|------------------------|-------|
| `SUPABASE_URL` | URL del proyecto OPS | la del proyecto `lpiatqztudxiwdlcoasv`. |
| `SUPABASE_SECRET_KEYS` **o** `SUPABASE_SERVICE_ROLE_KEY` | secret/service key de OPS | el gateway resuelve el nuevo formato `{"default":"sb_secret_..."}` o el legacy. **Distinta de la de TEST.** |
| `VITA_HMAC_SECRET` | **secreto HMAC NUEVO, generado para OPS** | mismo nombre que TEST, **valor distinto** (D-C-33, P-C-8). Tiene que coincidir con el que vas a poner en los 13 wrappers `__OPS` (Bloque E). Generá uno fuerte y guardalo en tu gestor. |
| `VITA_AMBIENTE` | `ops` | literal `ops`. El gateway valida que sea `test` u `ops`; con `ops` se autoidentifica. |
| `N8N_BASE_URL` | base de los webhooks de n8n OPS | p. ej. `https://federicosecchi.app.n8n.cloud/webhook` (la base sobre la que cuelgan los `portal-aXX__OPS`). Verificá si es `/webhook` (producción) o `/webhook-test` según cómo publiques los wrappers en el Bloque E. |
| `CORS_ALLOW_ORIGIN` | **origin real del portal OPS en Vercel** | p. ej. `https://<tu-deploy-ops>.vercel.app`. **Obligatoria**: sin esto el gateway no sirve. Un solo origin, sin barra final. |

> **Generar el HMAC de OPS:** cualquier secreto aleatorio fuerte (p. ej. 32+ bytes base64/hex). **Nunca** reutilices el de TEST ni lo pegues en docs/repo. El mismo valor va acá y en los 13 wrappers del Bloque E (placeholder `__PEGAR_` en los templates).

---

## 2. Deploy de la función

Según cómo venís desplegando (Dashboard o CLI). El **nombre de la función debe ser `portal-api`** (el frontend le pega por ese path).

**Opción A — Dashboard:** Edge Functions → `portal-api` → editar/crear → pegar el contenido de `portal-api_OPS_index.ts` → Deploy. Confirmá que `verify_jwt` esté **OFF** (el gateway valida el JWT internamente vía `getUser`, D-C-30).

**Opción B — CLI:** colocás el archivo en `supabase/functions/portal-api/index.ts` y corrés tu comando habitual de deploy de funciones apuntando al proyecto OPS. (No incluyo el comando exacto para no asumir tu setup de CLI/linkeo; usá el mismo flujo con el que desplegaste el gateway en TEST, cambiando el proyecto a OPS.)

> **Dependencia:** el import es `jsr:@supabase/supabase-js@2` (igual que TEST). No requiere `import_map` extra si tu deploy de TEST ya lo resolvía así.

---

## 3. Preflight — probar SOLO `sesion.contexto`

En este bloque **solo** se valida que el gateway arranca y resuelve identidad. **Ninguna acción n8n.**

### 3.1 Preflight de configuración (env completa)
Hacé un POST cualquiera con JWT válido. Si falta alguna env (incluida `CORS_ALLOW_ORIGIN`), el gateway responde **HTTP 500** con `{ ok:false, error:{ code:'error_interno', detail:{ missing:[...] } } }` y loguea la lista. Eso confirma el preflight duro. Corregí las que falten y redesplegá.

### 3.2 Smoke de `sesion.contexto` por los 3 roles
Necesitás un **JWT de OPS** por cada rol (login real de los usuarios sembrados en el Bloque C). Con cada JWT, POST al gateway:

```
POST https://<PROJECT_REF_OPS>.supabase.co/functions/v1/portal-api
Headers:
  Authorization: Bearer <JWT_DEL_USUARIO_OPS>
  apikey: <ANON_KEY_OPS>
  Content-Type: application/json
Body:
  { "action": "sesion.contexto", "payload": {} }
```

Esperado por rol (lo resuelve el gateway leyendo `portal_usuarios` por service_role, **sin tocar n8n**):
- [ ] **socio** (franco/rodrigo/remo): `ok:true`, `data` con rol `socio` y el menú completo.
- [ ] **vicky**: `ok:true`, rol `vicky`, menú operativo (sin contabilidad societaria).
- [ ] **jenny**: `ok:true`, rol `jenny`, menú mínimo (solo calendario de limpieza).
- [ ] **JWT inválido/ausente** → `ok:false`, `no_autorizado`.
- [ ] **OPTIONS** (preflight CORS del browser) desde el origin del portal → responde con `Access-Control-Allow-Origin` = tu `CORS_ALLOW_ORIGIN` (no `*`, no vacío).

### 3.3 Gate defensivo — confirmar que una acción n8n NO toca el motor (opcional pero recomendado)
Como los wrappers `__OPS` todavía no existen (son del Bloque E), invocar una acción n8n debe fallar **controladamente**:

```
Body: { "action": "calendario.limpieza", "payload": {} }   // lectura n8n
```
Esperado: `ok:false`, `error_entorno` ("respuesta inesperada del backend" / "el backend no respondió"). El `fetch` al webhook `portal-a03-limpieza__OPS` da 404 (aún no existe) → el gateway devuelve error controlado **sin tocar Postgres**. Una escritura (p. ej. `reserva.crear_manual`) daría `estado_incierto`. **Esto es lo esperado en el Bloque D**; se resuelve al importar los wrappers en el Bloque E.

---

## 4. Criterio de cierre del Bloque D

- [ ] Las 6 env/secrets de OPS configuradas (HMAC nuevo, `VITA_AMBIENTE='ops'`, `CORS_ALLOW_ORIGIN` con el origin real).
- [ ] `portal-api` desplegado en OPS con `verify_jwt` OFF.
- [ ] Preflight de config OK (no faltan env).
- [ ] `sesion.contexto` responde correcto por socio/vicky/jenny + rebota JWT inválido.
- [ ] OPTIONS responde con el origin real (no `*`).
- [ ] (Opcional) acción n8n da `error_entorno`/`estado_incierto` sin tocar motor.

Con esto, el gateway OPS está vivo y discrimina identidad. **Recién entonces** se abre el Bloque E (importar los 13 wrappers `__OPS`).

---

## 5. Rollback

| Escenario | Acción |
|-----------|--------|
| **El deploy quedó mal / querés volver atrás** | Re-desplegar la versión anterior de `portal-api` en OPS, o eliminar la función. Como ningún wrapper `__OPS` existe aún y el frontend OPS no está publicado (Bloque G), nada del sistema real depende todavía de este gateway. |
| **Una env quedó con valor incorrecto** | Corregir el secret en el panel y redesplegar/reiniciar la función. Los secrets se rotan en el panel, nunca en el repo. |
| **Sospecha sobre el HMAC** | Rotar `VITA_HMAC_SECRET` en OPS (y mantener el mismo valor para los wrappers del Bloque E). Como todavía no hay wrappers, rotarlo ahora es gratis. |
| **CORS bloquea el portal** | Verificá que `CORS_ALLOW_ORIGIN` sea exactamente el origin de Vercel (esquema + host, sin path ni barra final). Corregí y redesplegá. |

> El Bloque D **no toca** Supabase (tablas/datos), n8n ni el motor. Solo despliega la Edge Function y configura sus secrets. Por eso el rollback es simplemente re-desplegar o borrar la función.

---

## 6. Formato de ejecución (lo que me pediste aclarar)

- **No hay archivo SQL** en este bloque.
- **Archivo a desplegar:** `portal-api_OPS_index.ts`, **completo**, como código de la función `portal-api` (pegás todo el archivo, no por partes).
- **Secrets:** se cargan en el panel de OPS (6 valores), no en código.
- **Smokes:** los POST de la sección 3 los hacés con tu cliente HTTP habitual (curl/Postman/script), con JWT real de OPS.

Cuando lo tengas desplegado, pasame el resultado de los smokes de `sesion.contexto` (los 3 roles + el rebote de JWT inválido). Con eso cerrado, sigo con el **Bloque E** (los 13 wrappers `__OPS` firmados con el HMAC de OPS).
