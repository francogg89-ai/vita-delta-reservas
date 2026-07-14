# MATRIZ DE COBERTURA — SB-UI-6-FIX2

Tres categorías, y la tercera existe a propósito. **SB-UI-6 afirmó cobertura que no tenía**: decía
cubrir "fail-closed", "loading/error/retry" y "anti-flash" cuando en realidad solo probaba
`clasificarFoto`. Esta matriz lo separa de forma que no se pueda volver a hacer.

**AUTO** = prueba **automatizada y reproducible**: un comando, un veredicto, sin criterio humano.
**No quiere decir "corre en CI": no hay CI.** Alguien tiene que correr los comandos del RUNSHEET.
**MANUAL** = procedimiento humano documentado. **NO CUBIERTO** = declarado, con el motivo.

---

## Estados estructurales

| Qué | Cómo | Dónde |
|---|---|---|
| fail-closed (falta A30 y/o A31) | **AUTO** — en la vista (`probes` E1) **y en el contenedor real** (`estructural` F8: se le saca la acción a la sesión y se verifica que **no sale ni una llamada**) | `probes` E1 · `estructural` F8 |
| A31 loading / error / data | **AUTO** — "Cargando acumulados…", ErrorCard, cifras | `probes` E2 |
| A31 retry | **AUTO** — el callback se invoca; y en el contenedor real dispara **una petición nueva contada en la red** | `probes` E4 · `estructural` F5 |
| A30 inactivo / loading / error / data | **AUTO** — "Elegí un mes", "Cargando la foto…", ErrorCard, foto | `probes` E3 |
| A30 retry | **AUTO** — `probes` E4 invoca el callback (prueba el cableado, no el botón); `estructural` **F9 hace CLIC en el botón real** y cuenta **una** petición A30 adicional | `probes` E4 · `estructural` F9 |
| E1 / E2 / E3 | **AUTO** | `probes` B1 · D3 · D4 |
| INCONSISTENTE T1–T7 | **AUTO** — una variante por invariante; cada una → ErrorCard con **cero cifras y cero secciones** | `probes` B2 · E7 |
| cambio de mes sin flash de datos stale | **AUTO** — data de julio + mes aplicado agosto + `fotoPendiente:true` → Cargando y **cero** inconsistencia; al soltar el pendiente → **sí** aparece | `probes` E5 |
| `fotoPendiente` gana sobre error y sobre data vieja | **AUTO** | `probes` E6 |
| piso que invalida la selección | **AUTO** — selector y botón deshabilitados, cero cifras | `probes` B3 · E8 |
| `reiniciadoPorPiso` | **AUTO** — avisa sin tumbar la foto | `probes` E9 |
| modo degradado con A31 caída | **AUTO** — el selector sigue usable (plan local) y A30 funciona igual | `probes` B4 · `estructural` F6 |
| selector y botón habilitados/deshabilitados | **AUTO** — detector por atributo `disabled=""`, no por subcadena (las clases Tailwind `disabled:*` daban falso positivo) | `probes` E10 |

## Contenedor (`HistoricoCuentaCorriente`)

Corre **de verdad** en Chromium. Solo `window.fetch` es falso: `useAction` y `callPortal` son los
reales.

### Los tres mecanismos son distintos y se prueban por separado

SB-UI-6-FIX los mezclaba bajo la etiqueta "token de petición". No son lo mismo:

| mecanismo | dónde vive | qué protege | cómo se prueba |
|---|---|---|---|
| **cleanup** (`activo=false`) | `useAction`, return del `useEffect` | la respuesta de una instancia **desmontada** o de una corrida superada | **AUTO** — `estructural` **F3**: StrictMode monta/desmonta/remonta, dos A31 en vuelo a la vez, **dos instancias distintas** |
| **`reqId`** (`myId !== reqId.current`) | `useAction`, `useRef` por instancia | respuestas **out-of-order** dentro de **una misma** instancia | **AUTO** — `estructural` **F7**: una instancia sin StrictMode, `refetch` en vuelo, fixtures distinguibles |
| **token `PeticionFoto.seq`** | `HistoricoCuentaCorriente` | concilia **petición ↔ lectura** para el anti-flash | **AUTO parcial** — ver abajo |

**Hallazgo del mutation gate** (`npm run qa:mutacion`): **cleanup y `reqId` son redundantes entre
sí.** Borrando `myId !== reqId.current` la prueba **pasa igual**; borrando `!activo` también. Solo
borrando **las dos** la respuesta vieja pisa a la nueva. React ejecuta el cleanup del efecto anterior
**antes** de re-correrlo, así que `activo=false` ya cubre el caso — incluso con `refetch` en vuelo en
una misma instancia. **`reqId` es defensa en profundidad, no el mecanismo activo.** F7 prueba el
*descarte*, no que lo haga `reqId`.

| Qué | Cómo | Dónde |
|---|---|---|
| `enabled` de hooks | **AUTO** — A30 no sale mientras A31 vuela; al responder A31, el mes por defecto se auto-aplica y A30 sale **una** vez | `estructural` F1 |
| anti-doble-request | **AUTO** — 5 clicks durante la petición → **una** llamada | `estructural` F2 |
| cleanup de unmount / corrida superada | **AUTO** | `estructural` F3 |
| `useAction.reqId` (descarte out-of-order) | **AUTO** — con **mutation gate** que verifica que la prueba no es decorativa | `estructural` F7 · `qa:mutacion` |
| **token del contenedor** — pendiente sincronizado | **AUTO** — F4: 11 muestras durante el vuelo, cero huecos | `estructural` F4 |
| **token del contenedor** — anti-flash | **AUTO** — la foto vieja no se clasifica contra el mes nuevo | `probes` E5 |
| **token del contenedor** — round-trip | **AUTO** — se pide agosto, el servidor responde agosto, la vista lo concilia | `estructural` F1 |
| **token del contenedor** — descarte out-of-order de **A30** | **NO CUBIERTO** — ver abajo | — |
| fail-closed **en el contenedor** | **AUTO** — se le saca la acción a la sesión: banner, selector ausente, cero cifras, **cero llamadas A30 y A31** | `estructural` F8 |

## A31

| Qué | Cómo | Dónde |
|---|---|---|
| normal | **AUTO** | `probes` C1 |
| `sin_datos:true` con retiros y saldos vivos | **AUTO** — se afirma el **saldo vivo concreto** (−$ 233.333,00 × 6 celdas), no solo el nombre del socio | `probes` C2 |
| I1 rota | **AUTO** | `probes` C3 |
| I2 rota | **AUTO** | `probes` C4 |
| períodos desordenados | **AUTO** — se ordena una **copia**; el original no se muta | `probes` C5 |
| períodos repetidos sin deduplicar | **AUTO** — y **además** disparan `orden_evolucion` (07,08,08 no es estrictamente creciente) | `probes` C6 |
| identidad de gastos rota | **AUTO** — los **dos** números se muestran | `probes` C7 |
| fotos y movimientos pre-piso | **AUTO** | `probes` C8 |
| piso divergente | **AUTO** — con `Object.freeze`: si `analizarAcumulados` mutara, tira `TypeError` | `probes` C9 |

## A30

| Qué | Cómo | Dónde |
|---|---|---|
| porcentajes y valores relativos sin `$` | **AUTO** | `probes` D1 |
| nombres vivos con IDs congelados | **AUTO** — F9 renombra el catálogo | `probes` D2 |
| E2 sin detalle fino ni falsos vacíos | **AUTO** | `probes` D3 |
| E3 sin secciones inexistentes | **AUTO** | `probes` D4 |
| matriz vacía legítima | **AUTO** | `probes` D5 |
| movimientos por fecha vs conciliación por período | **AUTO** | `probes` D6 |
| comprobantes HTTP/HTTPS válidos | **AUTO** — `target=_blank` + `rel=noopener noreferrer` | `probes` D7 |
| `javascript:` / `data:` / `vbscript:` / relativas / inválidas | **AUTO** — 10 payloads, **cero** `<a>` en toda la tabla | `probes` D8 |
| correlación de `id_gasto` | **AUTO** — las 3 tablas | `probes` D9 |
| procedencia congelada | **AUTO** | `probes` D10 |
| cruce de día UTC→Argentina | **AUTO** | `probes` D11 |

## Responsive

375 / 768 / 1280, detalle cerrado **y** abierto.

| Qué | Cómo | Dónde |
|---|---|---|
| `documentElement.scrollWidth === clientWidth` | **AUTO** | `responsive` |
| ningún elemento desborda / ningún texto se encima | **AUTO** | `responsive` |
| cada tabla ancha con scroll interno | **AUTO** — **no tautológico**: se lee `overflowX` computado, se **asigna** `scrollLeft`, se comprueba que **cambió**, y se restaura | `responsive` |
| select y botón utilizables | **AUTO** | `responsive` |
| menú mobile cerrado / abierto / navegar lo cierra | **AUTO** — con `aria-expanded` | `responsive` |

## Coherencia de los fixtures

Existe porque los fixtures mintieron **tres veces**: F20 con `id_zona`/`id_cabana` cruzados contra la
clase, F20 con las `regla` cruzadas contra la clase, y F9 con el gasto #42 en `incidencias` **y** en
`gastos_sin_incidencia`. Un fixture incoherente hace que 205 aserciones prueben una fantasía.

| Qué | Cómo | Dónde |
|---|---|---|
| clase ↔ alcance (D=zona, E=cabaña) | **AUTO** — los 24 gastos de todos los fixtures | `probes` G1 |
| la `regla` de la incidencia sigue a la clase | **AUTO** | `probes` G2 |
| `sin_incidencia` consistente con las dos tablas | **AUTO** — un gasto no puede estar en `incidencias` **y** en `gastos_sin_incidencia` | `probes` G3 |
| integridad referencial de `id_gasto` | **AUTO** | `probes` G4 |
| identidad del desglose A31 | **AUTO** — excluye F16, que la rompe **a propósito** | `probes` G5 |

## Higiene

| Qué | Cómo |
|---|---|
| el harness no llega a producción | **AUTO** — canario ausente de `dist/`, `src/` no importa `qa/`, el grafo de `src/main.tsx` no lo toca |
| portabilidad Windows | **AUTO** — H5: ningún script usa Unix ni `execSync`; ningún script npm usa `&&`/`||`/`;` |
| reproducibilidad | **AUTO** — H6: `esbuild` y `playwright` son devDependencies **directas** (ya lo son desde SB-UI-6-FIX; `qa:probes` y `qa:mutacion` dependen de ellas, no de una transitiva de vite) |
| los artefactos generados no ensucian git | **AUTO** — `dist-qa/` y `qa/screenshots/` en `.gitignore`; el patcher lo gatea |

---

## MANUAL

| Qué | Por qué no se automatiza | Dónde |
|---|---|---|
| **descubribilidad del scroll horizontal** | La pregunta no es si la tabla scrollea (scrollea: está medido), sino si un ser humano **se da cuenta**. Está medido que no hay affordance ninguna: sin sombra, sin gradiente, sin aviso; la barra son 2px y en touch es overlay (invisible en reposo). La única pista es una columna cortada al medio. | `qa/SMOKE_MANUAL.md` — 3 personas, teléfono real |

---

## NO CUBIERTO — declarado, no disimulado

| Qué | Por qué | Qué hacer en su lugar |
|---|---|---|
| **El gateway responde lo que el harness supone.** Los fixtures son la interpretación del contrato SQL; nadie garantiza que A30/A31 en TEST devuelvan exactamente esa forma. | El harness intercepta `fetch`: **por diseño no toca la red**. Un fixture que mienta pasa igual. | **Smoke TEST concreto** (abajo). Es la única forma de cerrar esta brecha. |
| **Descarte out-of-order de A30 desde la UI.** | **No es alcanzable.** El anti-doble-request deshabilita el botón mientras la petición vuela (medido en F2), así que un humano no puede encimar dos peticiones A30. El token del contenedor es defensa en profundidad para un solapamiento que la UI ya previene. **Lo que sí está cubierto del token: pendiente sincronizado (F4), anti-flash (E5) y round-trip (F1).** | Nada. Afirmar que está cubierto sería falso; el escenario no existe. Si en algún momento se agrega un camino que dispare A30 sin pasar por el botón (un auto-refresh, un polling), hay que volver acá. |
| **`AuthProvider` real** (login, expiración de sesión, `reintentarContexto`). | El harness inyecta un `AuthContext` falso. Fuera del alcance de A30/A31. | Cubierto por el carril de auth, no por este bloque. |
| **Comportamiento de StrictMode en el build de producción.** El harness corre en dev, donde React duplica los efectos (A31 sale ×2). En producción sale ×1. | No es un bug, es dev. Pero el conteo del harness **no es el de producción**. | Anotado en `estructural` F1. Si hiciera falta, se mide contra `npm run build` servido estático. |
| **Rendimiento con fotos grandes** (cientos de gastos). | No estaba en el alcance. Los fixtures tienen 1–10 gastos. | Pendiente si aparece el caso real. |
| **iOS Safari / Android Chrome reales.** El responsive se mide en Chromium con emulación de touch. | Chromium emulado ≠ WebKit real. El scroll de overflow y las barras difieren. | El smoke manual se hace en **teléfono real**, que cubre parcialmente esto. |

### Smoke TEST concreto (para la primera brecha)

Con el portal apuntando a TEST, sesión de socio, en el navegador:

1. Consultar **2026-07** (mes con foto vigente) → debe verse E1 con las 6 secciones.
2. En DevTools → Network → la respuesta de `cuenta_corriente.historico`: verificar contra
   `qa/fixtures.ts` (F1) que las **claves** coinciden — `sin_foto`, `detalle_disponible`,
   `detalle_motivo`, `periodo`, `cabecera{periodo,pct_operativo,linaje}`, `retribucion_operativo{periodo,calculado,asignado,estado}`,
   `gastos[]{id_gasto,clase,id_zona,id_cabana,pagador_tipo,comprobante_url,creado_por,created_at}`.
3. Verificar que `pct_operativo` llega como **fracción** (`0.25`), no como `25`.
4. Consultar un mes **anterior a la extensión** → debe dar E2 (`foto_pre_extension`), sin detalle fino.
5. Consultar un mes **sin foto** → debe dar E3 (`sin_foto_vigente`), con `cabecera:null` y
   `retribucion_operativo:null`.
6. `cuenta_corriente.historico_acumulados`: verificar `gastos_desglose{a_paso2,c_paso7,d_e_socios}`
   y que **suman** `gastos_acumulados`.

Cualquier divergencia entre lo que devuelve TEST y lo que asume `qa/fixtures.ts` es un fixture
mentiroso, y todas las 197 aserciones que dependan de él están probando una fantasía.
