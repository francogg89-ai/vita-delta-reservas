# RUNSHEET — Harness de QA (SB-UI-6)

## ⚠️ El puerto 5173 lo comparten `npm run dev` y `npm run qa`

Los dos usan **5173 con `strictPort`**. Si el server de desarrollo está levantado, `npm run qa` **no
arranca** (no busca otro puerto: falla). **Bajá el otro primero.**

---

## Los cinco comandos

```bash
npm run build          # requisito de qa:higiene (necesita dist/)

npm run typecheck:qa   # TS sobre qa/ + src/            -> EXIT 0
npm run qa:probes      # 145 aserciones de dominio      -> EXIT 0
npm run qa:higiene     # el harness NO llega a producción -> EXIT 0
npm run qa             # levanta el harness visual en :5173
npm run qa:responsive  # Chromium 375/768/1280 (necesita el harness levantado)
```

`qa:responsive` necesita playwright, que **no es dependencia del proyecto** (no entra al bundle ni
al deploy):

```bash
npm i -D playwright && npx playwright install chromium
```

Si falta, el script te lo dice y sale con código 2 en vez de reventar.

---

## Qué prueba cada uno

### `qa:probes` — 145 aserciones, sin vitest ni jest

Runner mínimo propio. Compila los **módulos reales** con esbuild y los ejecuta en Node con
`renderToStaticMarkup`. Lo que se prueba es el código que se despliega, no una reimplementación.

- **B — estados estructurales:** E1/E2/E3 · INCONSISTENTE T1–T7 · piso que invalida la selección ·
  modo degradado con A31 caída · anti-flash (la foto nunca se clasifica contra el mes equivocado).
- **C — A31:** normal · `sin_datos:true` con retiros y saldos vivos · I1 rota · I2 rota · períodos
  desordenados · períodos repetidos sin deduplicar · identidad de gastos rota · fotos y movimientos
  pre-piso · piso divergente con `Object.freeze` (prueba de no-mutación).
- **D — A30:** porcentajes y valores relativos sin `$` · ID congelado + nombre vivo · E2 sin detalle
  fino ni falsos vacíos · E3 sin secciones inexistentes · matriz vacía legítima · movimientos por
  fecha vs conciliación por período · comprobantes http/https válidos · `javascript:` / `data:` /
  `vbscript:` / `file:` / `ftp:` / relativas / inválidas **sin `href`** · correlación por `id_gasto` ·
  procedencia congelada · cruce de día UTC→Argentina.

### `qa:higiene` — el harness no puede llegar a producción

- El canario `__VITA_QA_FIXTURE_DO_NOT_SHIP__` **no** aparece en `dist/assets/*`.
- Ningún módulo de `src/` referencia `qa/`.
- El grafo de `src/main.tsx` (118 módulos) no toca `qa/`.
- `vite.config.ts` (producción) no menciona `qa/`; el harness tiene su propio `vite.qa.config.ts`.

**Por qué no puede filtrarse:** `npm run build` parte de `index.html` en la raíz, que solo alcanza
`src/`. El harness tiene entry, config y tsconfig propios.

### `qa:responsive` — Chromium real, no simulación

Levanta el harness, abre el **`AppShell` de verdad** (header, drawer mobile, `<main class="min-w-0">`)
y mide en 375 / 768 / 1280, con el detalle fino **cerrado y abierto**:

`documentElement.scrollWidth === clientWidth` · ningún elemento desborda · ningún texto se encima ·
cada tabla ancha scrollea **dentro** de su contenedor · select y botón usables · menú mobile
cerrado por defecto · abierto al tocar la hamburguesa (con `aria-expanded`) · navegar cierra el drawer.

### `qa` — harness visual

Monta el `AppShell` **real** y le sustituye solo el árbol de rutas (que arrastraría todas las
pantallas y la red). La **barra QA** de abajo permite combinar en vivo:

- **A30:** F1–F9 + **F20** (peor caso visual) · estado `data` / `loading` / `error` / `inactivo`
- **A31:** F10–F18 · estado `data` / `loading` / `error`
- flags: `faltaAccion` (fail-closed) · `fotoPendiente` · `seleccionFueraDePiso` · `reiniciadoPorPiso`

La barra es un **overlay fijo, fuera del `<main>`**: no contamina la medición de responsive.

**El harness no hace una sola llamada de red.** `vite.qa.config.ts` inyecta
`VITE_SUPABASE_URL = https://harness-qa.invalid` a propósito: si alguien cableara una llamada por
error, revienta contra `.invalid` — nunca contra TEST ni OPS.

### Smoke manual

`qa/SMOKE_MANUAL.md` — descubribilidad del deslizamiento horizontal. Necesita 3 personas y un
teléfono real. No es automatizable.

---

## Hallazgos abiertos (medidos, pendientes de decisión)

`qa:responsive` los reporta como `·HALL` y **no** los cuenta como falla, para que la suite siga
sirviendo de gate de regresión.

- **H-1 — el drawer mobile empuja en vez de superponerse.** Es `position: static` + `shrink-0`: al
  abrirse comprime el `<main>` a 119px (71px útiles tras el `p-6`). Un importe como `$ 3.800.000,00`
  mide 135px con `shrink-0`: no entra ni puede encoger → la página desborda +149px. **No es un
  problema de A30/A31**: le pasa a cualquier pantalla del portal.
- **H-2 — filas inutilizables en mobile.** Tabla *Gastos congelados* con F20, 375px: la primera fila
  mide **279px de alto** con **16px de contenido visible** (**94% de espacio vacío**), 3 de 9 columnas
  a la vista y **72% de la tabla oculta**. La altura la genera contenido que el usuario **no puede
  ver**. Esto responde la decisión 1: **sí hay inutilización concreta.**
