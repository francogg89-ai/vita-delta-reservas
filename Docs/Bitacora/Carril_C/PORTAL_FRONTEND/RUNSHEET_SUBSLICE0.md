# RUNSHEET — Sub-slice 0 (Frontend TEST) · ejecución local

**Proyecto:** Vita Delta Reservas — Carril C / Portal Operativo Interno
**Etapa 2 — Frontend TEST · Sub-slice 0:** shell de auth + `sesion.contexto` + menú por rol.
**Quién ejecuta:** Franco (Claude solo entrega los archivos; no corre comandos ni deploya).
**Ambiente:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`).

---

## 0. Prerrequisitos

- **Node 18+** (recomendado LTS 20) y **npm**. Verificá: `node -v`.
- Las **identidades TEST sembradas** con sus contraseñas: `vicky@vitadelta.test`, `franco@vitadelta.test`, `jenny@vitadelta.test` (alcanzan para cubrir los 3 roles).
  - Si no tenés las contraseñas a mano, reseteálas desde el **dashboard de Supabase Auth (proyecto TEST)** → Authentication → Users. (Eso lo hacés vos; no es algo que toque Claude.)
- La **anon key (publishable) de TEST**: dashboard de Supabase TEST → Project Settings → API → `anon` `public`. Es browser-safe.

---

## 1. Colocar los archivos

Extraé el contenido en `apps/portal-operativo/` dentro del repo (estructura completa en §6). El árbol queda:

```
apps/portal-operativo/
  package.json  index.html  vite.config.ts  tsconfig.json
  postcss.config.js  tailwind.config.js  .gitignore  .env.example
  README.md  RUNSHEET_SUBSLICE0.md
  src/...
```

---

## 2. Instalar dependencias

```bash
cd apps/portal-operativo
npm install
```

> Nota: `npm audit` reporta 2 vulnerabilidades en dependencias **de desarrollo** transitivas (cadena de esbuild/vite). No afectan el runtime del navegador ni TEST. Si querés las miramos en una pasada de hardening; **no** corras `npm audit fix --force` (rompe versiones pineadas).

---

## 3. Configurar el entorno

```bash
cp .env.example .env
```

Editá `.env` y completá la anon key (la URL ya viene apuntando a TEST):

```
VITE_SUPABASE_URL=https://bdskhhbmcksskkzqkcdp.supabase.co
VITE_SUPABASE_ANON_KEY=<pegá-acá-la-anon-key-de-TEST>
```

> `.env` está en `.gitignore` y **no** se comitea. La anon key es publishable, pero igual va por entorno.

---

## 4. Levantar en local

```bash
npm run dev
```

Abrí **http://localhost:5173**. Deberías ver la pantalla de login (wordmark "Vita Delta" + "Portal operativo").

---

## 5. Verificación end-to-end (lo que valida el sub-slice 0)

Corré estos casos y anotá el resultado. El menú se arma con `acciones` de `sesion.contexto`, así que esto valida el acuerdo backend↔frontend por rol.

### 5.1 Menú por rol

| Login | Menú esperado |
|---|---|
| `jenny@vitadelta.test` | **Solo** grupo **Calendarios** → "Calendario de limpieza". **Cero** Reservas/Bloqueos/Cobranzas/Económico. |
| `vicky@vitadelta.test` | **Todos** los grupos: Calendarios (limpieza + operativo), Reservas (detalle, pre-reservas, histórico, crear), Bloqueos (crear), Cobranzas (saldos, registrar), Económico (ingresos, gastos, cargar). 12 ítems. |
| `franco@vitadelta.test` (socio) | Idéntico a vicky (acceso total a las 13 en el MVP). |

- Click en cualquier ítem → pantalla **placeholder** ("Esta pantalla todavía no está construida… sub-slice 1/2"). Es lo esperado: no hay pantallas reales todavía.

### 5.2 Sesión

- **Salir** (botón arriba a la derecha) → vuelve a login.
- **Refrescá el navegador** estando logueado → seguís logueado (persistencia de sesión). El menú se rearma solo.

### 5.3 Errores de acceso

- **Contraseña incorrecta** → mensaje "Email o contraseña incorrectos." (no rompe).
- (Opcional) Un usuario de Supabase **sin fila en `portal_usuarios`** → "No tenés acceso al portal. Contactá al administrador." Esto ejercita el `no_autorizado` del contrato (§4). Si no tenés un usuario así a mano, lo salteamos.

---

## 6. Estructura entregada

```
apps/portal-operativo/
├─ package.json            # deps pineadas (React 18, Vite 5, Tailwind 3, Supabase JS 2)
├─ index.html              # root + fuente Inter
├─ vite.config.ts          # plugin React, puerto 5173
├─ tsconfig.json           # TS estricto (typecheck de src)
├─ postcss.config.js       # tailwind + autoprefixer
├─ tailwind.config.js      # paleta delta/río + Inter
├─ .gitignore              # ignora node_modules / dist / .env (conserva .env.example)
├─ .env.example            # URL TEST + placeholder de anon key
├─ README.md
├─ RUNSHEET_SUBSLICE0.md   # este archivo
└─ src/
   ├─ main.tsx             # entry point
   ├─ App.tsx              # raíz: enruta por estado de auth (cargando/anónimo/autenticado/error)
   ├─ index.css            # directivas Tailwind + base
   ├─ vite-env.d.ts        # tipado de import.meta.env
   ├─ lib/
   │  ├─ types.ts          # Rol, SesionContexto, PortalErrorShape
   │  ├─ supabase.ts       # cliente Supabase (SOLO auth/sesión)
   │  ├─ callPortal.ts     # cliente único contra portal-api (fetch + body.ok)
   │  └─ actionRegistry.ts # presentación por acción + construirMenu (D-FE-09)
   ├─ auth/
   │  ├─ AuthProvider.tsx  # sesión + carga de sesion.contexto + no_autorizado → re-login
   │  ├─ useAuth.ts        # hook
   │  └─ LoginScreen.tsx   # login email+password
   └─ app/
      ├─ AppShell.tsx      # layout header + nav + contenido
      ├─ Menu.tsx          # menú agrupado desde acciones
      └─ PlaceholderView.tsx # stub por acción
```

---

## 7. Qué pegar de vuelta

Para cerrar el sub-slice 0 necesito de tu corrida:

1. Por cada rol (jenny / vicky / franco): el menú que se renderizó (grupos + ítems). Screenshot vale.
2. Si algo no coincide con la tabla de §5.1, pegámelo: es señal de divergencia backend↔registry (D-FE-09 lo tolera, pero quiero verlo).
3. Cualquier error en la consola del navegador (F12 → Console) o en la terminal de `npm run dev`.
4. Confirmación de que Salir / refresh / contraseña incorrecta se comportan como en §5.2–5.3.

Con eso registro el cierre de sub-slice 0 (y formalizo D-FE-10 / D-FE-11) y armo el kickoff del sub-slice 1.

---

## 8. Notas / límites

- **CORS:** hoy el gateway responde `Access-Control-Allow-Origin: *`, así que `http://localhost:5173` no se bloquea. La restricción real del origin es **P-C-7** (pre-producción), no de este sub-slice.
- **Build de producción:** `npm run build` (typecheck + bundle). Ya está verificado que cierra; lo vas a necesitar recién al hostear.
- **Sin cambios** en backend, n8n, OPS ni `6B_SCHEMA_SQL.md`. No se reabrió `CONTRATO_FRONTEND_PORTAL_v1.md`.
