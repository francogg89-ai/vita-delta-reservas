# RUNSHEET — Harness de QA (SB-UI-6-FIX2)

## ⚠️ El puerto 5173 lo comparten `npm run dev` y `npm run qa`

Los dos usan **5173 con `strictPort`**. Si el server de desarrollo está levantado, `npm run qa` **no
arranca** (no busca otro puerto: falla). **Bajá el otro primero.**

---

## Puesta a punto

```powershell
npm ci                          # esbuild y playwright son devDependencies DIRECTAS
npx playwright install chromium # único paso externo permitido
```

Después de `npm ci` no hace falta tocar ningún manifest.

**Portabilidad Windows:** ningún script del harness invoca `grep`, `sed`, `mkdir -p`, `||` ni
utilidad Unix alguna. Todo es API de Node (`readdirSync` recursivo, `mkdirSync({recursive:true})`,
esbuild por su API JS). Los scripts npm no usan encadenamiento de shell (`&&`, `||`, `;`).
**`qa:higiene` H5 verifica esto automáticamente** y falla si alguien reintroduce una dependencia
POSIX.

---

## Los diez comandos operativos

```powershell
npm run build            # 1. requisito de qa:higiene (necesita dist/)
npm run typecheck        # 2. TS de producción                     -> EXIT 0
npm run typecheck:qa     # 3. TS sobre qa/ + src/                  -> EXIT 0
npm run qa:probes        # 4. 205 aserciones de dominio y vista    -> EXIT 0
npm run qa:higiene       # 5. 10 checks: el harness no llega a prod-> EXIT 0
npm run qa:build         # 6. el harness compila                   -> EXIT 0
npm run qa:mutacion      # 7. mutation gate de useAction (autónomo)-> EXIT 0

npm run qa               # 8. levanta el harness visual en :5173
npm run qa:estructural   # 9. 41 aserciones: CONTENEDOR REAL en Chromium
npm run qa:responsive    # 10. 375/768/1280 + H-1 y H-2 medidos
```

Los dos últimos necesitan el harness levantado (otra terminal). `qa:mutacion` **es autónomo**:
levanta su propio servidor en el 5199, no pelea por el 5173. Si tu Chromium está en otro lado:
`$env:QA_CHROME = "C:\ruta\chrome.exe"`.

**Artefactos generados** (`dist-qa/`, `qa/screenshots/`) están en `.gitignore`. Después de correr
toda la suite, `git status --short` no muestra nada nuevo.

---

## Qué prueba cada uno

### `qa:probes` — 205 aserciones, sin vitest ni jest

Runner mínimo propio. Compila los **módulos reales** con esbuild y los ejecuta con
`renderToStaticMarkup`. Se prueba el código que se despliega, no una reimplementación.

- **B — estados:** E1/E2/E3 · INCONSISTENTE T1–T7 · piso que invalida la selección · modo degradado.
- **C — A31:** normal · `sin_datos:true` con retiros y **saldo vivo concreto** · I1 rota · I2 rota ·
  desordenados · repetidos (que además disparan `orden_evolucion`) · identidad de gastos rota ·
  pre-piso · piso divergente con `Object.freeze` (prueba de no-mutación).
- **D — A30:** porcentajes y valores relativos sin `$` · ID congelado + nombre vivo · E2 sin detalle
  fino ni falsos vacíos · E3 sin secciones inexistentes · matriz vacía legítima · movimientos por
  fecha vs conciliación por período · comprobantes válidos · `javascript:`/`data:`/`vbscript:`/
  relativas/inválidas **sin `href`** · correlación por `id_gasto` · procedencia · cruce de día UTC→AR.
- **E — `HistoricoVista` RENDERIZADA:** fail-closed · A31 loading/error/data · A30
  inactivo/loading/error/data · **anti-flash** (data de julio + mes aplicado agosto +
  `fotoPendiente:true` → Cargando y **cero** inconsistencia; al soltar el pendiente → aparece) ·
  `fotoPendiente` gana sobre error y sobre data vieja · T1–T7 → ErrorCard con **cero cifras y cero
  secciones** · `seleccionFueraDePiso` · `reiniciadoPorPiso` · selector y botón
  habilitados/deshabilitados. *El retry se invoca a mano acá (prueba el callback, no el botón); el
  **clic real** está en `qa:estructural` F9.*
- **G — coherencia de los fixtures:** clase↔alcance (D=zona, E=cabaña) · la `regla` de la incidencia
  sigue a la clase · `sin_incidencia` consistente con las dos tablas · integridad referencial de
  `id_gasto` · identidad del desglose A31. **Existe porque F20 quedó contradictorio dos veces**; y
  al escribirlo cazó un tercer fixture roto (F9 tenía el gasto #42 en `incidencias` **y** en
  `gastos_sin_incidencia`).

### `qa:estructural` — 41 aserciones, CONTENEDOR REAL en Chromium

Lo que vive en `HistoricoCuentaCorriente` (token de petición, anti-doble-request, `enabled` de
hooks) **no se puede probar con `renderToStaticMarkup`**: vive en `useEffect` y en callbacks, que
en SSR no corren. Así que se monta de verdad:

```
HistoricoCuentaCorriente REAL   <- token de petición, anti-doble-request, enabled
useAction REAL                  <- reqId, cleanup, descarte de respuestas viejas
callPortal REAL                 <- envelope ok/error, PortalApiError
window.fetch                    <- LO ÚNICO falso (qa/stubs/red.ts)
```

Stubbear `useAction` habría tirado a la basura justamente la lógica a probar.

- **F1** `enabled`: A30 **no sale** mientras A31 está en vuelo; cuando A31 responde, el mes por
  defecto se auto-aplica y A30 sale **una** vez con `{mes:"2026-07-01"}`.
- **F2** anti-doble-request: **5 clicks** durante la petición → **una** sola llamada.
- **F3** **cleanup** de StrictMode/unmount: dos peticiones A31 en vuelo a la vez pertenecen a **dos
  instancias distintas** del hook; la de la instancia muerta se descarta por el `activo=false` de
  **su** cleanup. *Esto no prueba `reqId`* — cada instancia tiene el suyo (es un `useRef`).
- **F7** **`reqId`**: descarte out-of-order en **una misma instancia**, sin StrictMode. Request 1 =
  F2 (anómalo, 600ms) → `refetch` en vuelo → request 2 = F1 (normal, 50ms). La vieja llega después
  y **no pisa** a la nueva.
- **F4** el par `(loading:true, fotoPendiente:false)` es **inalcanzable**: 11 muestras durante el
  vuelo, **cero** huecos.
- **F5** retry de **A31**: Reintentar dispara **una petición nueva** (contada en la red).
- **F6** degradado: con A31 caída el selector sigue usable y A30 funciona igual.
- **F8** **fail-closed en el contenedor**: se le saca la acción a la sesión (`?acciones=solo-a30` /
  `solo-a31` / `ninguna`). En los tres: banner, **selector ausente**, cero cifras, **cero llamadas
  A30 y cero A31**. Con `ambas`, todo funciona. *Renderizar la vista con `faltaAccion:true` era
  asumir la conclusión.*
- **F9** retry de **A30 con CLIC en el botón real**: A31 OK, A30 `ok:false` → ErrorCard → el
  servidor se recupera → **clic** → exactamente **una** petición A30 adicional → la foto aparece.

### `qa:mutacion` — ¿la prueba de F7 sirve, o pasaría igual con el código roto?

Autónomo (server propio en el 5199). Verifica el SHA-256 de `src/hooks/useAction.ts`, **deriva** los
mutantes del original y los inyecta **en memoria** con un plugin de Vite: **no escribe un solo
archivo y no toca `src/`**.

Las dos guardas de `useAction` son `if (!activo || myId !== reqId.current) return;` — cleanup y
reqId. Resultado medido:

| variante | `detalle_motivo` final | veredicto |
|---|---|---|
| ORIGINAL | `null` (F1) | pasa ✅ |
| **sin-reqId** (queda `!activo`) | `null` | **SOBREVIVE** |
| **sin-activo** (queda `reqId`) | `null` | **SOBREVIVE** |
| **sin-ninguna** | `foto_pre_extension` | **CAZADO** ✅ |

**Las dos guardas son redundantes entre sí.** React ejecuta el cleanup del efecto anterior **antes**
de re-correrlo, así que `activo=false` ya descarta la respuesta vieja — incluso en una misma
instancia con `refetch` en vuelo. `myId !== reqId.current` es defensa en profundidad, no el
mecanismo activo. La prueba **no es decorativa** (caza al hook sin ninguna guarda), pero decir que
"prueba el `reqId`" sería falso.

### `qa:higiene` — 10 checks, el harness no puede llegar a producción

Canario `__VITA_QA_FIXTURE_DO_NOT_SHIP__` ausente de `dist/` · `src/` no importa `qa/` · el grafo
de `src/main.tsx` (118 módulos) no toca `qa/` · `vite.config.ts` no menciona `qa/` · **H5:
portabilidad** (ningún script usa Unix ni `execSync`) · **H6: `esbuild` y `playwright` son
devDependencies directas**.

### `qa:responsive` — Chromium real, no simulación

375/768/1280, detalle cerrado y abierto: `scrollWidth === clientWidth` · nada desborda · ningún
texto se encima · **scroll no tautológico** (se mide `overflowX` computado, se **asigna**
`scrollLeft`, se comprueba que **cambió**, y se restaura — un wrapper bloqueado no pasa) · select y
botón usables · menú mobile cerrado/abierto/`aria-expanded`/navegar-cierra-drawer. Además **mide
H-2** (selecciona F20, abre el detalle, localiza Gastos congelados, mide filas y % oculto, guarda
screenshot).

### `qa` — harness visual

Monta el `AppShell` **real** y sustituye solo el árbol de rutas. Barra QA (overlay fijo, fuera del
`<main>`: no contamina la medición): A30 F1–F9 + **F20** · A31 F10–F18 · estados
`data`/`loading`/`error`/`inactivo` · `mesApplied` · flags `faltaAccion`, `fotoPendiente`,
`seleccionFueraDePiso`, `reiniciadoPorPiso`.

Query params:

| param | qué monta |
|---|---|
| *(nada)* | `HistoricoVista` (vista pura) con props de la barra QA |
| `?contenedor=1` | `HistoricoCuentaCorriente` **real** |
| `?host=requid` | host de una sola instancia de `useAction`, **sin StrictMode** |
| `?acciones=ambas\|solo-a30\|solo-a31\|ninguna` | acciones de la sesión (fail-closed) |

**Cero llamadas de red.** `vite.qa.config.ts` inyecta `VITE_SUPABASE_URL = https://harness-qa.invalid`
a propósito: si alguien cableara una llamada por error, revienta contra `.invalid` — nunca contra
TEST ni OPS.

### Smoke manual

`qa/SMOKE_MANUAL.md` — descubribilidad del deslizamiento horizontal. 3 personas, teléfono real.
No automatizable.

---

## Hallazgos abiertos (medidos, pendientes de decisión de producción)

`qa:responsive` los reporta como `·HALL` y **no** los cuenta como falla, para que la suite siga
sirviendo de gate de regresión.

- **H-1 — el drawer mobile empuja en vez de superponerse.** `position: static` + `shrink-0`: al
  abrirse comprime el `<main>` a 119px (71px útiles tras el `p-6`). Un importe como `$ 3.800.000,00`
  mide 135px con `shrink-0`: no entra ni puede encoger → la página desborda **+149px**. **No es de
  A30/A31**: le pasa a cualquier pantalla del portal.
- **H-2 — filas inutilizables en mobile.** Gastos congelados con F20, 375px: la peor fila mide
  **279px** con **16px** de contenido visible (**94% vacío**), **3 de 9** columnas a la vista,
  **72% de la tabla oculta**. La altura la genera contenido que el socio **no puede ver**.
