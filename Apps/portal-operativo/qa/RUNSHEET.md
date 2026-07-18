# RUNSHEET — Harness de QA (SB-UI-6.1)

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
npm run qa:probes        # 4. 248 aserciones de dominio y vista    -> EXIT 0
npm run qa:higiene       # 5. 10 checks: el harness no llega a prod-> EXIT 0
npm run qa:build         # 6. el harness compila                   -> EXIT 0
npm run qa:mutacion      # 7. mutation gate de useAction (autónomo)-> EXIT 0

npm run qa               # 8. levanta el harness visual en :5173
npm run qa:estructural   # 9. 41 aserciones: CONTENEDOR REAL en Chromium
npm run qa:responsive    # 10. 375/768/1280 + H-1 y H-2 como ASERCIONES DURAS
```

Los dos últimos necesitan el harness levantado (otra terminal). `qa:mutacion` **es autónomo**:
levanta su propio servidor en el 5199, no pelea por el 5173. Si tu Chromium está en otro lado:
`$env:QA_CHROME = "C:\ruta\chrome.exe"`.

**Artefactos generados** (`dist-qa/`, `qa/screenshots/`) están en `.gitignore`. Después de correr
toda la suite, `git status --short` no muestra nada nuevo.

---

## Qué prueba cada uno

### `qa:probes` — 248 aserciones, sin vitest ni jest

**Gate de pureza (SB-UI-6-FIX3):** antes de ejecutar, inspecciona el metafile del bundle y **aborta
si aparece Supabase** (`@supabase/supabase-js`, `src/lib/supabase.ts`, `createClient`,
`RealtimeClient`). Los probes son puros (`renderToStaticMarkup` sobre módulos, sin red): no tienen
por qué tocar Supabase. Si alguien importara algo de `callPortal` como **valor** (p.ej. `new
PortalApiError(...)`), el grafo arrastraría `callPortal → supabase → createClient → RealtimeClient`,
y en **Node 20** (sin WebSocket nativo) el bundle revienta al cargarse. La regla: `import type` para
los tipos de `callPortal`, y objetos casteados para los errores de prueba.

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
- **H — card mobile de gastos (SB-UI-6.1):** el componente productivo real `GastoCardMobile` (exportado, no una copia): #id_gasto congelado, monto, etiqueta, fecha, clase, alcance con IDs crudos, **Pagador** y **Incidencia** en filas separadas (quién pagó ≠ a quién se imputó, el motivo sin incidencia sale por `incidenciaGasto`), procedencia, comentario, clase sugerida, nullables, y comprobante SEGURO (http/https con `target`+`rel`; `javascript:`/`data:`/`vbscript:`/relativa/`ftp:` → sin `<a>` + aviso). **Integración:** ContenidoFoto rinde una card por gasto, IDs sin faltantes ni duplicados, y texto largo (etiqueta/comentario) completo sin pérdida.

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
botón usables.

**H-1 (ASERCIÓN DURA).** El drawer mobile es un overlay anclado al área de contenido (no al viewport:
no tapa el header ni la hamburguesa). Se afirma, en 375px: se **abre** con la hamburguesa;
`aria-expanded="true"` abierto; **screenshot con el drawer REALMENTE ABIERTO, antes de cerrar**;
`Math.abs(mainAbierto − mainCerrado) ≤ 1` (no comprime el `<main>` ni lo ensancha); la página no
desborda; el aside abierto es `position: fixed|absolute`; se **cierra con el mismo control** →
`display:none`, sin geometría, `aria-expanded="false"`; **navegar también cierra**. En tablet/desktop:
aside estático de **256px** con tolerancia explícita (±2px).

**H-2 (ASERCIÓN DURA).** *Gastos congelados* con F20, en 375/768/1280: **exclusividad** dura
`tablaVis !== cardsVis` (mobile → cards y tabla no visible; tablet/desktop → tabla y cero cards);
la representación visible es la **esperada** por breakpoint; **cardinalidad** en mobile (una card por
gasto: cantidad e IDs de card == filas fuente, sin faltantes ni duplicados — una mutación que rinda
solo el primer gasto falla); **vacío vertical por UNIÓN** de intervalos de texto legibles fusionados
(no `bot−top`: un hueco grande entre líneas cuenta como vacío) con umbrales explícitos (alto ≥ 120px
Y vacío ≥ 100px); `documentElement.scrollWidth === clientWidth` en los tres viewports. Para el
**desborde horizontal** se distingue la representación: las **cards** quedan completas dentro del
viewport (izquierda y derecha); la **tabla** puede ser más ancha que el área visible y se desplaza
**dentro de su wrapper `overflow-x-auto`** (comportamiento productivo de DataTable) — no se exige que
las filas entren, sino que el **wrapper** quede dentro del viewport, con `overflowX` auto|scroll y, si
la tabla excede, **scroll horizontal interno funcional** (no tautológico: se asigna `scrollLeft`, se
verifica que cambió y se restaura). Screenshot de la representación **efectivamente medida** por
viewport. El solapamiento horizontal útil (`overlapX ≥ 16px` y ≥ 25% del ancho de la línea) evita que
un sliver marginal cuente la línea completa como visible.

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

`qa/SMOKE_MANUAL.md` — tarea humana sobre la **card mobile** de gastos: *"Necesito saber cuánto salió
la reparación de la bomba y quién la pagó."* La persona debe hallar gasto, monto y **Pagador** sin
scroll horizontal, zoom ni rotación, y distinguir **Pagador** de **Incidencia**. 3 personas, teléfono
real. **PENDIENTE de ejecución humana — no declarado ejecutado.**

---

## Hallazgos: H-1 y H-2 RESUELTOS y enforzados como aserciones duras (gate final `{}`)

En SB-UI-6.1, H-1 y H-2 dejaron de ser hallazgos abiertos y pasaron a **aserciones duras** de
`qa:responsive` (cuentan en `fallos`, no en un listado aparte). El gate de hallazgos ahora exige el
**set vacío `{}`**: la maquinaria de `·HALL` se conserva como tripwire para que cualquier hallazgo
NUEVO e inesperado rompa el gate por "SOBRAN", pero no debe quedar ninguno abierto.

- **H-1 (resuelto).** El drawer mobile ya no es `static + shrink-0` (que comprimía el `<main>` a
  ~119px y desbordaba la página). Ahora es un overlay anclado al área de contenido: no comprime el
  `<main>`, no tapa la hamburguesa (que sigue abriendo y cerrando), navegar cierra, y cerrado queda
  `display:none`. Enforzado por las aserciones duras de H-1 descritas arriba.
- **H-2 (resuelto).** *Gastos congelados* ya no usa la tabla de 9 columnas en mobile (que ocultaba el
  ~72% y dejaba filas ~94% vacías). Ahora en mobile es **una card por gasto** (la tabla se conserva en
  tablet/desktop). Enforzado por las aserciones duras de H-2 (exclusividad, cardinalidad, vacío por
  unión; la página nunca desborda a lo ancho; cards dentro del viewport; la tabla se desplaza dentro
  de su wrapper con scroll interno funcional).
