# KICKOFF — Portal Operativo · UI de Histórico y Acumulados de Cuenta Corriente

> Documento de arranque autosuficiente para una **conversación nueva**. Basado en el **estado
> comprobado del repo** (clone fresco de `main`), no solo en lo conversado. Pegá/adjuntá esto al
> abrir el chat nuevo. Enfoque **exclusivo**: la UI que consume A30/A31 en TEST.

---

## 0. Método de trabajo (no negociable)

- Respondé **siempre en español rioplatense con voseo**.
- **Vos (Claude)** diseñás, inspeccionás, validás y generás artefactos. **Franco** ejecuta despliegues,
  comandos y cambios de infraestructura.
- **No** tocás OPS. **No** desplegás. **No** hacés `git push`. **No** modificás servicios. **No**
  ejecutás nada en Supabase/n8n/Vercel/TEST/OPS.
- **Un sub-bloque por vez.** Ciclo: (1) diagnóstico → (2) propuesta → (3) auditoría/aprobación de
  Franco → (4) generación de artefactos → (5) ejecución por Franco → (6) evidencias → (7) cierre.
- **Frenás al final de cada sub-bloque.** No avanzás por tu cuenta al siguiente.
- **No generás implementación antes de aprobar arquitectura y contrato de UI.**
- Clone fresco antes de tocar nada; `main` como autoridad; edits quirúrgicos; nunca reescribir
  archivos enteros; validar localmente (tsc/typecheck) antes de que Franco ejecute.

---

## 1. Contexto del proyecto

**Complejo Vita Delta** — lodge de 5 cabañas (Bamboo, Madre Selva, Arrebol, Guatemala, Tokio) en el
Delta de Tigre. Se construye **Vita Delta Reservas**: sistema de reservas, contabilidad y operación.

- **Socios:** Franco (tech lead), Rodrigo, Remo. **Staff operativo:** Vicky (operaciones/reservas),
  Jenny (limpieza).
- **Stack:** Supabase/PostgreSQL 17.6 (fuente de verdad), n8n Cloud (orquestación), Edge Function
  gateway `portal-api` (BFF TypeScript, `verify_jwt` OFF), frontend **React 18 / Vite 5 / TypeScript
  strict / Tailwind 3** en Vercel. Repo: `github.com/francogg89-ai/vita-delta-reservas`.
- **Entornos:** TEST (`bdskhhbmcksskkzqkcdp`) y OPS (`lpiatqztudxiwdlcoasv`).
- **Portal Operativo:** app interna donde el equipo consulta y opera. El frontend vive en
  `Apps/portal-operativo/`.

**Este bloque** = la **UI** que expone al socio el **histórico mensual (A30)** y los **acumulados
(A31)** de la cuenta corriente, ya disponibles como lecturas read-only en el gateway TEST (Bloque 0
cerrado). Orden acordado: **(1) diseñar+implementar UI en TEST → (2) validar contra A30/A31 → (3)
cerrar el bloque UI → (4) recién después promover gateway+wrappers+frontend a OPS.**

---

## 2. Estado real verificado del repo (clone fresco)

- **Clone fresco** de `github.com/francogg89-ai/vita-delta-reservas`, branch **`main`** (autoridad).
- **HEAD:** `9ff6db7321b23bfc2d00de9d4d9df5ebd0fc915a`
- **Último commit:** `feat(portal): expose L3 account history reads in TEST` — Franco Guglianone,
  **2026-07-11 12:24:49 -0300**.
- **Estado:** limpio (sin cambios locales).
- **Inspección:** 2026-07-11 15:25 UTC (clone fresco, no un clone viejo ni archivos temporales).

**Ubicación real de los artefactos del Bloque 0** (verificada por nombre y hash):

- Los **7 artefactos técnicos** están en `Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/10-07-2026/`
  (gateway, 2 wrappers, 3 smokes, oracle). **Los 7 hashes coinciden exacto con el acta de cierre.**
- El **acta** `CC_L3_BLOQUE0_CIERRE.md` y las **evidencias** `CC_L3_BLOQUE0_EVIDENCIAS_EJECUCION_TEST.md`
  (esta última la creó Franco) están en `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/11-07-2026/`.
- Nota: acta/evidencias quedaron bajo la carpeta de **otro carril** (Motor de Horarios) distinto al
  de los artefactos (Cuenta Corriente). No es error de contenido, es una ubicación cruzada a tener
  presente al buscar.

**Discrepancias reales encontradas** (ver §10 y el mensaje que acompaña este kickoff): el acta
commiteada difiere byte-a-byte de la copia generada en la sesión de cierre (Franco la ajustó al
commitear); **la autoridad es la versión del repo**.

---

## 3. Estado cerrado del Bloque 0 (read-only L3)

Desplegado y **verde en TEST** (ejecutado por Franco):

- **Gateway** `portal-api` (TEST) con el diff aditivo A31 (2 validators + 2 entradas de CATALOG
  socio-only). Hash `07f316b8ec9bc335f908ca08f927ff6192924827b600df73132aa2bbcb081a8c` (baseline A29
  `bc38a056…`).
- **Wrappers n8n** activos: `portal-a30-cuenta-corriente-historico__TEST` (`09909f51…`) y
  `portal-a31-cuenta-corriente-historico-acumulados__TEST` (`1e498ea8…`).
- **Smokes:** A31 directo **24/0**, A30 directo **34/0**, gateway end-to-end **50/0** (todos exit 0).
- **Oracle de no-mutación:** `OK: 0 mutacion` (forma 7/7/2/2 + counts + max_ids + table_hashes +
  sequences idénticos).
- **Decisiones acuñadas** (candidatas, propagación a satélites diferida a OPS): **D-CC-40 … D-CC-49**;
  **hallazgos L-CC-20 … L-CC-26**. (Detalle en el acta.)
- Datos reales de TEST al cierre: 3 fotos vigentes (`2026-07-01`, `2026-08-01`, `2026-11-01`), todas
  **pre-extensión**; 3 socios; piso `2026-07-01`.

**El backend/gateway/wrappers de L3 quedan CONGELADOS. Esta UI no los toca.**

---

## 4. Arquitectura actual del Portal (verificada en el repo)

Frontend en `Apps/portal-operativo/`. React 18.3, Vite 5.4, TypeScript 5.5 (strict), Tailwind 3.4,
`react-router-dom` 6.30, `@supabase/supabase-js` 2.45. Scripts: `dev` (vite), **`build` (`tsc && vite
build`)**, `preview`, **`typecheck` (`tsc --noEmit`)**. **No hay framework de tests** (no vitest/jest);
la QA es **manual por runsheet** (`Apps/portal-operativo/B5_RUNSHEET_QA.md`). Deploy Vercel: framework
vite, `outputDirectory: dist`, rewrites SPA (todo → `/index.html`).

**Estructura `src/`:**

- `app/` — `AppShell.tsx`, `Menu.tsx`, `Home.tsx`, `RutaProtegida.tsx`, `rutas.tsx`,
  `BannerAmbiente.tsx`, `PlaceholderView.tsx`.
- `auth/` — `AuthProvider.tsx`, `LoginScreen.tsx`, `useAuth.ts`.
- `hooks/` — `useAction.ts` (lecturas), `useEnviar.ts` (escrituras), `useBorradorPersistente.ts`.
- `lib/` — `callPortal.ts` (cliente gateway), `actionRegistry.ts`, `contratos.ts`, `formato.ts`,
  `fecha.ts`, `periodo.ts`, `constantes.ts`, `types.ts`, `ambiente.ts`, `erroresEscritura.ts`,
  `supabase.ts`, `disponibilidad.ts`.
- `screens/` — pantallas por acción. Cuenta Corriente actual: **`CuentaCorriente.tsx` (A27
  al_dia)**, **`CuentaCorrienteDetalle.tsx` (A28 detalle)**, **`RetirarSaldo.tsx` (A29 retirar)**.
- `ui/` — reutilizables: `Cargando.tsx` (loading), `ErrorCard.tsx`, `Vacio.tsx` (vacío),
  `DataTable.tsx`, `Money.tsx`, `Fecha.tsx`, `BotonSubmit.tsx`, `Campo.tsx`, `Banner.tsx`,
  `EstadoBadge.tsx`, `TarjetaExito.tsx`, `Paginador.tsx`, `CalendarioRango.tsx`, `estilos.ts`.

**Patrones cerrados (D-FE-\*) que la UI DEBE respetar:**

- **`callPortal` (D-FE-10):** único cliente. Manda `Authorization: Bearer <jwt>` + `apikey` (anon) +
  `Content-Type`. **Ramifica SIEMPRE por `body.ok`, nunca por status HTTP (D-FE-04):** el gateway
  responde **HTTP 200 + envelope** para todo resultado manejado (incluido `no_autorizado`); el único
  no-200 es 500 (crash → `error_interno`). El frontend **nunca** calcula HMAC ni manda campos de
  control (actor/rol/nonce). Tira `PortalApiError` en cualquier no-éxito.
- **`useAction` (D-FE-13):** único hook de lectura. `{ data, loading, error, refetch }`. Re-dispara al
  cambiar `action`/`payload`(serializado)/`enabled`. `enabled:false` → no dispara. Patrón de filtros
  **draft → applied** (la pantalla mantiene el borrador; al "Buscar" hace `setApplied(draft)`). Guard
  anti-doble-request y anti-out-of-order por `reqId` (ya resuelto). El **"vacío" lo decide la
  PANTALLA** (`filas.length===0 → <Vacio/>`), no el hook.
- **`ACTION_REGISTRY` (D-FE-09) + `rutas.tsx` (D-FE-12):** el menú y las rutas se **derivan** del
  registry (presentación-only: `label`/`grupo`/`orden`/`ruta` por acción). `construirMenu` intersecta
  `acciones` de `sesion.contexto` (A02, única autoridad de visibilidad) con el registry. Acción en
  `acciones` **sin** entrada en registry → se ignora (tolerancia forward, D-FE-01). Grupo CC =
  **`'socios'`** (A27 orden 10, A28 orden 20, A29 orden 30).
- **`RutaProtegida` (D-FE-17):** guard por rol; si la `action` no está en `contexto.acciones`,
  redirige a `/` con aviso. Defensa en profundidad; el backend igual rebotaría `rol_no_permitido`.
- **`SesionContexto` = `{ nombre, rol, acciones: string[] }`** (de A02). El bootstrap consume
  `sesion.contexto` en `AuthProvider`.
- **Moneda/fecha/negativos:** `Money` (montos en **pesos**, nunca /100 — **L-FE-02**; negativos en
  **rojo** `text-red-600`). `formatARS` (Intl es-AR ARS), `formatFecha` (`YYYY-MM-DD → dd/mm/aaaa`,
  sin `Date` para no correr zona). Floor: `FLOOR_CONTABLE = '2026-07-01'`, `FLOOR_MES = '2026-07'`.
- **Tokens Tailwind (usar estos, no inventar):** `ink` #10211f (texto/títulos), `river` (DEFAULT
  #0f6e7d, `dark` #0a4e58, `light` #e6f1f2), `sand` #e9e3d6 (bordes), `mist` #f4f6f5 (fondo), `reed`
  #5d7a6e (texto secundario). Fuente Inter.
- **Contrato frontend:** `Docs/Implementacion/Carril_C/PORTAL_FRONTEND/CONTRATO_FRONTEND_PORTAL_v1.md`
  (viven ahí **D-FE-01 … D-FE-45** y **L-FE-01 … L-FE-12**, cerradas).

**Template directo para esta UI:** `CuentaCorrienteDetalle.tsx` (A28) es el molde del **histórico**
(selector de mes → `payload={mes}` → `useAction` → `loading/error/data` → `<Tarjeta>` + `DataTable`/
`Money`/`Vacio`). `CuentaCorriente.tsx` (A27) es el molde del **acumulados** (carga al ingresar, sin
payload, tabla + estados). **La diferencia crítica que ninguno de los dos tiene: A30 debe distinguir
los 3 estados (foto completa / pre-extensión / sin foto).**

**Duplicación gateway (a tener presente):** `Docs/Supabase/index.ts` (hash `3a8e4503…`) es la versión
**OPS** del gateway y **NO** incluye las adiciones L3 (son TEST-only). El gateway **TEST** desplegado
es el snapshot `portal-api_A31_TEST_index.ts` (`07f316b8…`). **No confundas ni edites `Docs/Supabase/
index.ts` en este bloque.**

---

## 5. Contratos exactos de A30/A31 (invariantes NO negociables)

### Seguridad y visibilidad (ambas acciones)

- A30 y A31 son **`socio-only`**. Franco, Rodrigo y Remo ven el **conjunto completo** de la cuenta
  corriente societaria (dato compartido, no self-only).
- **Vicky y Jenny no ven ni pueden invocar** estas acciones.
- La UI **no inventa self-only**. El frontend **no decide permisos**: consume `acciones` de
  `sesion.contexto`, pero **debe ocultar correctamente** la navegación no autorizada (vía registry ∩
  `acciones` + `RutaProtegida`). Sin JWT → `no_autorizado`; rol no permitido → `rol_no_permitido`
  (HTTP 200 + envelope; ramificar por `body.ok`).

### A30 — Histórico mensual · `cuenta_corriente.historico`

Payload exacto:

```json
{ "mes": "YYYY-MM-01" }
```

Reglas: única clave permitida `mes`; fecha real; **día obligatorio `01`**; piso `2026-07-01`. **Un mes
sin foto NO es error** (`sin_foto:true` es `ok:true`); `detalle_disponible:false` tampoco es error.
Las fotos persistidas actuales de TEST son **pre-extensión**.

Contrato top-level de **14 claves**:

```
sin_foto · detalle_disponible · detalle_motivo · periodo · cabecera · cascada · socios ·
participacion · gastos · incidencias · movimientos · matriz_por_socio · gastos_sin_incidencia ·
retribucion_operativo
```

**3 estados que la UI DEBE distinguir (y nunca mostrar "error"/"no encontrado" en los casos 2 y 3):**

1. **Foto vigente con detalle completo.**
2. **Foto pre-extensión:** `sin_foto:false`, `detalle_disponible:false`,
   `detalle_motivo:'foto_pre_extension'`; **cabecera, cascada, socios y retribución disponibles**;
   detalle fino vacío (`participacion`/`gastos`/`incidencias`/`matriz_por_socio`/`gastos_sin_incidencia`
   = `[]`).
3. **Mes sin foto:** `sin_foto:true`, `detalle_disponible:false`, `detalle_motivo:'sin_foto_vigente'`;
   **cabecera y retribución `null`**; secciones vacías.

### A31 — Acumulados · `cuenta_corriente.historico_acumulados`

Payload: `{}` (también acepta **omitido** o **`null`**; el gateway lo normaliza a `{}`).

Contrato top-level de **6 claves**:

```
sin_datos · piso · totales · evolucion · saldos_por_socio · meta
```

Reglas: `sin_datos:true` es `ok:true`; `evolucion` **ordenada por período ascendente**;
`meta.fotos_vigentes == evolucion.length`. **No** asumir cantidades fijas de períodos ni socios; **no**
hardcodear meses; **no** hardcodear que septiembre siempre será un mes sin foto (hoy `2026-09` lo es,
pero se deriva del dato).

### Naturaleza frozen/live

L3 **mezcla**: información **congelada** de la foto mensual + **movimientos/retiros vivos** del libro
mayor (los `movimientos` se leen en vivo filtrados a la ventana `[mes, mes+1)`; el resto viene de las
tablas de liquidación congeladas). **La UI debe entender y comunicar esta mezcla**: no presentar todo
el histórico como si fuera completamente congelado.

---

## 6. Objetivo funcional de la nueva UI

Una experiencia clara para los socios que, como mínimo, permita:

1. Ver un **resumen acumulado**.
2. Ver **evolución por período**.
3. Ver **saldos por socio**.
4. **Elegir un mes histórico**.
5. **Consultar la foto** de ese mes.
6. **Entender** si: hay foto completa / hay foto pre-extensión / no hay foto vigente.
7. Ver claramente **qué datos son históricos congelados y cuáles son movimientos vivos**.
8. **Navegar sin confundir**: Cuenta Corriente al día (A27) · detalle mensual **vivo** (A28) ·
   histórico **congelado** (A30) · acumulados históricos (A31) · retiro (A29).

**No des por decidido el layout exacto sin inspeccionar primero el frontend real** (ya inspeccionado
en §4; igual, confirmá contra el repo en el SB1).

---

## 7. Alcance y fuera de alcance

**Alcance (TEST-only):** diseño de UI · implementación frontend · integración contra gateway TEST ·
pruebas de roles · pruebas de estados funcionales · responsive · build · QA · documentación y cierre
del bloque UI.

**Fuera de alcance:** promoción a OPS · modificar A30/A31 · modificar funciones SQL · snapshots
nuevos · cierres mensuales · supersesión · retiros · Mercado Pago · canonicalización · bootstrap ·
schema/GRANT · cambios contables · rediseño de todo el portal (salvo necesidad **bloqueante
demostrada**).

**Si encontrás que hace falta tocar backend/gateway/wrappers para que la UI funcione: tratalo como
potencial blocker y demostralo. No lo asumas ni lo implementes.**

---

## 8. Decisiones ya cerradas (NO reabrir)

- **Contrato L3 (Bloque 0):** D-CC-40 (visibilidad colectiva socio-only), D-CC-41 (read-only),
  D-CC-42 (payload mensual `YYYY-MM-01` exacto), D-CC-43 (payload vacío estricto A31), D-CC-44
  (`sin_foto`/`sin_datos` = éxito), D-CC-45 (naturaleza frozen/live), D-CC-46 (detalle fino solo con
  `n_part>0`), D-CC-47 (`error_entorno` nunca `estado_incierto` para estas lecturas), D-CC-48
  (exposición aditiva patrón A29), D-CC-49 (ausencia deliberada de UI/OPS/canónico/bootstrap en el
  Bloque 0 — **esta UI es el bloque siguiente**).
- **Frontend (cerradas):** **D-FE-01 … D-FE-45**, **L-FE-01 … L-FE-12**. Clave: D-FE-01 (pin de
  contrato; acciones futuras sin contrato detallado), D-FE-04 (ramificar por `body.ok`), D-FE-09
  (registry presentación-only; A02 única autoridad de visibilidad), D-FE-10 (`callPortal` único),
  D-FE-12 (rutas derivadas), D-FE-13 (`useAction` único), D-FE-17 (`RutaProtegida`), L-FE-02 (pesos,
  nunca /100).
- **Negocio:** D-NEG-02 (piso contable `2026-07-01`, sin períodos previos ni carryover).

---

## 9. Decisiones pendientes de UI (encuadrar como candidatas D-FE-46+)

Encuadrar (no necesariamente decidir en el SB1) al menos:

- ¿Una **nueva pantalla** o una **sección** dentro de Cuenta Corriente? ¿Histórico y Acumulados como
  **dos ítems de menú** (siguiendo A27/A28/A29 en grupo `'socios'`) o **una sola pantalla** con
  acumulados arriba + selector de mes que carga la foto?
- **Si se adopta una pantalla combinada** (decisión explícita del SB-UI-1): definir **qué acción actúa
  como autoridad de navegación / route guard** (`RutaProtegida` toma una sola `action`) y **cómo se
  garantiza que la sesión tenga disponibles tanto A30 como A31** antes de realizar ambas lecturas. **No**
  inventar una acción sintética de backend ni alterar A02: ambas acciones ya llegan en
  `sesion.contexto.acciones` para el socio, así que la garantía es **verificar la presencia de ambas** en
  `acciones` (ambas socio-only → o están las dos o no está ninguna).
- **Naming visible** para usuarios (ej. "Histórico", "Acumulados", "Histórico mensual").
- ¿A31 carga **al ingresar** (patrón A27) o **bajo demanda**?
- **Selector de período**: control (dropdown `<select>` como A28 / input `type=month`), y **fuente de
  los períodos seleccionables** (¿todos los meses desde el piso, como A28? ¿o solo los de
  `evolucion` de A31? ¿o ambos, con manejo de "sin foto"?).
- **Comportamiento ante meses sin foto** y ante **fotos pre-extensión** (mensajes claros, no "error").
- **Orden y jerarquía** de: totales · evolución · socios · cascada · movimientos · gastos ·
  incidencias · matriz · retribución operativa.
- Qué va **colapsado vs expandido**.
- Representación de **montos negativos** (ya: `Money` rojo) y **formato de moneda/fechas** (ya:
  `formatARS`/`formatFecha`).
- **Responsive** para celular; **loading/retry/errores**; **accesibilidad**; **consistencia** con la
  UI actual.
- **Prevención de dobles requests** (ya cubierta por `useAction`/`reqId`) y **caching o ausencia
  deliberada** de caching.
- **Riesgo de mezclar A28 (detalle vivo) y A30 (foto congelada)**; **riesgo de presentar movimientos
  vivos como congelados**.
- Comportamiento cuando **cambian los períodos disponibles** y cuando **A31 devuelve `sin_datos:true`**.
- **Testabilidad de todos los estados sin depender del dataset actual** (derivar de A31, no
  hardcodear).

---

## 10. Riesgos y trampas

1. **Confundir A28 y A30.** A28 (`detalle`) recomputa el mes **vivo**; A30 (`historico`) devuelve la
   **foto congelada** + movimientos vivos. Mismo `{mes}`, semántica distinta. La UI debe dejar claro
   cuál es cuál y por qué difieren.
2. **Presentar movimientos vivos como congelados.** Los `movimientos` de A30 son en vivo (ventana
   mensual); el resto es foto. Etiquetar/separar.
3. **Los 3 estados de A30.** No mostrar "error"/"no encontrado" para pre-extensión ni para sin-foto.
   Distinguir por `sin_foto` + `detalle_disponible` + `detalle_motivo`.
4. **Hardcodear meses / septiembre / cantidades.** Derivar del dato (A31 `evolucion`, floor).
5. **Self-only accidental / visibilidad hardcodeada.** Visibilidad = A02 `acciones` ∩ registry +
   `RutaProtegida`. Nunca por rol hardcodeado ni self-only.
6. **Romper el pin de contrato (D-FE-01).** Implementar A30/A31 amplía lo que el frontend soporta:
   documentarlo como extensión del contrato, sin romper la tolerancia forward.
7. **Editar el gateway OPS (`Docs/Supabase/index.ts`) por error.** La UI corre contra el gateway
   **TEST** (`07f316b8…`); OPS es otro paso, futuro.
8. **Potencial blocker de backend.** Si algo de la UI requiere tocar backend/gateway/wrappers,
   **demostralo como blocker**; no lo implementes en este bloque.
9. **`ramificar por HTTP status`.** Prohibido: todo se decide por `body.ok` (D-FE-04).
10. **Ramp de estados en el hook.** Recordar: el "vacío" lo decide la pantalla, no `useAction`.

---

## 11. Archivos reales candidatos a leer / modificar

**Leer (referencia, no tocar salvo indicado):**

- `Apps/portal-operativo/src/screens/CuentaCorrienteDetalle.tsx` (A28 — molde del histórico).
- `Apps/portal-operativo/src/screens/CuentaCorriente.tsx` (A27 — molde de acumulados).
- `Apps/portal-operativo/src/screens/RetirarSaldo.tsx` (A29 — referencia de escritura socio-only).
- `Apps/portal-operativo/src/lib/callPortal.ts`, `src/hooks/useAction.ts`.
- `Apps/portal-operativo/src/lib/actionRegistry.ts`, `src/app/rutas.tsx`, `src/app/RutaProtegida.tsx`,
  `src/app/Menu.tsx`, `src/app/AppShell.tsx`, `src/app/Home.tsx`.
- `Apps/portal-operativo/src/lib/contratos.ts`, `src/lib/types.ts`, `src/lib/constantes.ts`,
  `src/lib/periodo.ts`, `src/lib/formato.ts`, `src/ui/Money.tsx`, `src/ui/DataTable.tsx`,
  `src/ui/Cargando.tsx`, `src/ui/ErrorCard.tsx`, `src/ui/Vacio.tsx`.
- `Apps/portal-operativo/src/auth/AuthProvider.tsx`, `src/auth/useAuth.ts`.
- `Apps/portal-operativo/tailwind.config.js`, `package.json`, `vercel.json`,
  `Apps/portal-operativo/B5_RUNSHEET_QA.md`.
- `Docs/Implementacion/Carril_C/PORTAL_FRONTEND/CONTRATO_FRONTEND_PORTAL_v1.md` (contrato + D-FE/L-FE).
- `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/11-07-2026/CC_L3_BLOQUE0_CIERRE.md` y
  `…/CC_L3_BLOQUE0_EVIDENCIAS_EJECUCION_TEST.md` (contrato L3 + evidencias).
- Los contratos SQL de A30/A31 en el snapshot: `Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/10-07-2026/`
  (wrappers) y el gateway `portal-api_A31_TEST_index.ts` (validadores/CATALOG). Referencia del shape;
  **no editar**.

**Candidatos reales a modificar (para la UI):** el número de entradas/rutas/componentes es
**condicional** a la arquitectura que se apruebe en SB-UI-1 (una pantalla combinada vs dos pantallas).

- `Apps/portal-operativo/src/lib/actionRegistry.ts` — **una o dos entradas** (`cuenta_corriente.historico`
  y/o `cuenta_corriente.historico_acumulados`) en el grupo `'socios'` (label/orden/ruta), **según la
  arquitectura aprobada**. Presentación-only.
- `Apps/portal-operativo/src/app/rutas.tsx` — **una o dos rutas/componentes** en `PANTALLAS`
  (action → componente) + imports, **según la arquitectura aprobada**.
- `Apps/portal-operativo/src/lib/contratos.ts` — **agregar los tipos de AMBAS acciones, siempre** (14
  claves de A30 + 6 de A31 + sub-tipos). Hoy NO existen. (Independiente de si la UI es 1 o 2 pantallas.)
- **Nuevos** componentes de pantalla en `src/screens/` (**uno o dos** según la decisión de SB-UI-1) y,
  si hace falta, sub-componentes reutilizables en `src/ui/`.
- Posible doc de contrato de UI / QA runsheet nuevo del bloque, y el acta de cierre del bloque UI.

---

## 12. Plan por sub-bloques (secuenciales dentro de esta conversación; frenar en cada gate)

**Todos los sub-bloques se trabajan secuencialmente dentro de esta conversación.** Se frena al
finalizar cada uno (gate) y no se avanza sin aprobación de Franco. Solo se prepara un handoff a otra
conversación si la longitud o el contexto lo requieren expresamente. Los SB-UI-1 … SB-UI-7 son la
secuencia de trabajo, **no** siete conversaciones separadas.

- **SB-UI-1 — Diagnóstico + contrato y arquitectura de UI (solo diseño, sin código).** Confirmar el
  estado del repo; decidir §9 (**pantalla combinada vs dos pantallas**, naming, carga, selector, fuente
  de períodos, jerarquía) y —si se adopta pantalla combinada— **qué acción es la autoridad de
  navegación / route guard y cómo se garantiza que la sesión tenga A30 y A31 disponibles antes de ambas
  lecturas (sin acción sintética de backend ni tocar A02)**; decidir la **arquitectura de
  fixtures/harness de QA** (§§15-16). Fijar el contrato de presentación de A30/A31 y el árbol de
  componentes. **Gate: aprobación de Franco antes de generar artefactos.**
- **SB-UI-2 — Tipos + registry + rutas + esqueleto.** `contratos.ts` (**tipos de ambas acciones,
  siempre**), `actionRegistry.ts` (**una o dos entradas** según SB-UI-1), `rutas.tsx` (**una o dos
  `PANTALLAS`** según SB-UI-1), esqueleto de pantalla(s) con estados vacíos. `typecheck` local. **Gate.**
- **SB-UI-3 — Acumulados (A31).** Pantalla/sección: resumen (totales), evolución (ordenada), saldos por
  socio; estados loading/error/`sin_datos`. **Gate.**
- **SB-UI-4 — Histórico (A30) con los 3 estados.** Selector de mes; foto completa; pre-extensión;
  sin-foto; separación frozen/live de movimientos. **Gate.**
- **SB-UI-5 — Responsive + estados + accesibilidad + consistencia.** Mobile, retry, foco/labels,
  tokens. **Gate.**
- **SB-UI-6 — QA + build.** Matriz de pruebas (§15) por roles y estados; `build` + `typecheck` verdes;
  runsheet de QA. **Gate.**
- **SB-UI-7 — Cierre del bloque UI.** Acta, decisiones D-FE-46+/L-FE-13+, inventario, evidencias.

(El ordenamiento SB-3/SB-4 puede invertirse si en el SB-1 se decide una sola pantalla combinada.)

---

## 13. Gates de aprobación

En cada sub-bloque: **diseño → aprobación explícita de Franco → generación de artefactos → ejecución
por Franco (dev/build/typecheck/deploy TEST) → evidencias → auditoría de Claude → cierre.** No se
genera implementación antes de aprobar arquitectura y contrato de UI (SB-1). Claude valida localmente
(`tsc --noEmit`) lo validable; Franco corre `npm run build`/deploy.

---

## 14. Criterios de aceptación funcionales

- Los 8 objetivos de §6 cumplidos.
- **A30**: los 3 estados renderizan correctamente y **ninguno** aparece como error/no-encontrado;
  `periodo` round-trip; frozen/live claramente separados.
- **A31**: resumen + evolución (ascendente) + saldos por socio; `sin_datos:true` como estado vacío
  válido; `meta.fotos_vigentes == evolucion.length` respetado en lo que se muestre.
- **Visibilidad**: socio ve Histórico/Acumulados; Vicky/Jenny **no** los ven ni pueden navegar a sus
  rutas; sin JWT no accede.
- **Consistencia**: usa `callPortal`/`useAction`/`Money`/`Vacio`/`ErrorCard`/`Cargando`/`DataTable`,
  tokens Tailwind y `formatARS`/`formatFecha`; ramifica por `body.ok`.
- `build` (`tsc && vite build`) y `typecheck` **verdes**.
- Sin hardcodeo de meses/cantidades; testable sobre cualquier dataset.

---

## 15. Matriz de pruebas (obligatoria)

Se distinguen **dos modos**, porque el **dataset persistido actual de TEST** ofrece acumulados con
datos, tres fotos vigentes **pre-extensión**, meses sin foto, **ninguna foto con detalle completo** y
`sin_datos:false`. Los estados que ese dataset **no** ofrece se prueban con **fixtures locales**, sin
alterar datos, crear snapshots ni tocar backend (todo eso está fuera de alcance).

**15.a — E2E real contra TEST (obligatorio):**

| # | Escenario | Esperado |
|---|---|---|
| 1 | **socio autorizado** (Franco/Rodrigo/Remo) | Ve Histórico y Acumulados en menú; navega y carga OK |
| 2 | **Vicky excluida** | No ve los ítems en el menú; navegación directa a la ruta **bloqueada por `RutaProtegida`** (redirige); la pantalla **no monta** y **no dispara** A30/A31 |
| 3 | **Jenny excluida** | Ídem Vicky |
| 4a | **sin sesión / JWT** | Se muestra la **pantalla de login** (`LoginScreen` vía `AuthProvider`); la UI protegida **no** se renderiza ni dispara A30/A31 |
| 4b | **sesión inválida / expirada** (token vencido durante la sesión) | Comportamiento **ya establecido por el portal** ante `no_autorizado` (reautenticación / cierre de sesión / error controlado, según el frontend real); **no** inventar comportamiento nuevo. El `no_autorizado` del gateway ya quedó probado en el smoke del Bloque 0 |
| 5 | **foto pre-extensión** (ej. `2026-07-01`) | Estado 2: cabecera/cascada/socios/retribución; detalle fino vacío; **no** "error" |
| 6 | **mes sin foto** (derivado, ej. `2026-09-01`) | Estado 3: `sin_foto:true`; secciones vacías; cabecera/retribución null; **no** "no encontrado" |
| 7 | **acumulados con datos** | Resumen + evolución ascendente + saldos por socio |
| 8 | **loading real** | `Cargando` visible durante el fetch; sin flash de datos viejos indebido |
| 9 | **error de transporte** (navegador **offline** / request **bloqueado** vía DevTools) | Fallo de `fetch` **sin envelope** (**no** es `error_entorno`); la UI muestra el componente de error/retry; al recuperar conectividad, **retry funciona** |
| 10 | **responsive** | Celular: legible, sin overflow, tablas/cards adaptadas |

(Los meses de los casos 5/6 se **derivan** de A31 `evolucion`/floor, no se hardcodean.)

**15.b — QA determinística de presentación con fixtures locales (obligatoria):** para los estados que
el dataset actual **no** ofrece. Los fixtures **reproducen exactamente los contratos TypeScript de
A30/A31** y prueban **únicamente el renderizado**.

| # | Estado (fixture) | Esperado |
|---|---|---|
| F1 | **foto con detalle completo** (`detalle_disponible:true`, `detalle_motivo:null`, detalle fino poblado) | Estado 1: participación/gastos/incidencias/matriz completos |
| F2 | **acumulados `sin_datos:true`** | Estado vacío claro (no error) |
| F3 | **loading controlado** | `Cargando` en un estado determinista |
| F4 | **envelope `error_entorno`** (el gateway responde `{ok:false, error:{code:'error_entorno'}}`; distinto del fallo de transporte de 15.a) | `ErrorCard` con retry |
| F5 | **envelope `error_interno`** (envelope con `code:'error_interno'`) | `ErrorCard` con mensaje adecuado |
| F6 | **shapes límite** (los que haga falta cubrir) | Render robusto sin romper |

**Reglas de los fixtures (no negociables):** viven **solo en el entorno local/QA**; **no** se envían a
Supabase; **no** modifican n8n, gateway ni funciones SQL; **no** se habilitan en el build productivo;
**reproducen exactamente** los contratos TS de A30/A31; prueban **únicamente** el comportamiento de
renderizado. La **arquitectura concreta** de fixtures/harness se decide en **SB-UI-1** (no se
implementa en este kickoff).

---

## 16. Evidencias que Franco deberá devolver

- Salida de `npm run build` y `npm run typecheck` (verdes).
- **E2E real (TEST):**
  - capturas por **estado real**: pre-extensión, mes sin foto, acumulados con datos, loading real;
  - **sin sesión** → **pantalla de login**; la UI protegida no monta ni dispara A30/A31;
  - **sesión inválida / expirada** → **comportamiento real del portal** ante `no_autorizado` (si puede
    probarse de forma segura), sin inventar comportamiento nuevo;
  - **Vicky / Jenny** → **ausencia de request A30/A31** (DevTools) o, como mínimo, **redirección
    inmediata** y **ausencia de renderizado** de la pantalla;
  - **error de transporte** (navegador offline / request bloqueado vía DevTools) → componente de
    error/retry visible; al recuperar conectividad, **retry funciona**;
  - verificación **responsive** (celular).
  - **No** se piden capturas reales de TEST de **foto completa** ni de **`sin_datos:true`** (el dataset
    no los ofrece).
- **Fixtures / harness:** evidencia de la QA determinística para **foto con detalle completo**,
  **`sin_datos:true`**, **loading controlado**, **envelope `error_entorno`** y **envelope
  `error_interno`** (salida del harness / capturas del render con fixtures locales).
- **Evidencia heredada del Bloque 0 (NO se re-testea apagando servicios):** el envelope real
  `error_entorno` ya observado en el smoke del gateway. **No** se recrea desactivando wrappers,
  cambiando `N8N_BASE_URL` ni alterando infraestructura:

  ```json
  {
    "ok": false,
    "error": {
      "code": "error_entorno",
      "message": "respuesta inesperada del backend",
      "detail": null
    }
  }
  ```

- Resultado de la **matriz §15** (15.a **y** 15.b) — runsheet de QA completado.
- (Si aplica) el diff real aplicado en TEST/Vercel preview.

---

## 17. Artefactos esperados (los genera Claude; los ejecuta Franco)

- Componente(s) de pantalla nuevo(s) (`src/screens/…`) — **uno o dos** según SB-UI-1.
- Adiciones a `contratos.ts` (tipos de **ambas** acciones A30/A31).
- Diffs quirúrgicos de `actionRegistry.ts` (**una o dos entradas**) y `rutas.tsx` (**una o dos
  `PANTALLAS`**), según la arquitectura aprobada.
- **Fixtures/harness de QA local** (contratos TS exactos de A30/A31; solo render; fuera del build
  productivo; no se envían a Supabase ni tocan backend/n8n/SQL).
- (Si hace falta) sub-componentes `src/ui/…`.
- Runsheet de QA del bloque + acta de cierre del bloque UI.

---

## 18. Condiciones para declarar el bloque UI CERRADO

- **E2E real (TEST) verde** para: socio ve / Vicky-Jenny excluidas (**guard bloquea; sin request
  A30/A31**) / **sin sesión → pantalla de login** (la UI protegida no monta) / **sesión inválida-
  expirada** según el comportamiento real del portal (si es probable de forma segura) / foto
  pre-extensión / mes sin foto / acumulados con datos / loading real / **error de transporte con
  retry** (offline o request bloqueado) / responsive.
- **QA con fixtures verde** para los estados que el dataset no ofrece: **foto con detalle completo**,
  **`sin_datos:true`**, loading controlado, **envelope `error_entorno`**, **envelope `error_interno`**
  y shapes límite — con fixtures que **no** se envían a Supabase, **no** tocan backend/n8n/SQL y **no**
  entran al build productivo.
- Los 3 estados de A30 y los estados de A31 renderizan correctamente; ninguno como error/no-encontrado.
- `build` + `typecheck` verdes.
- Sin confusión A28/A30; frozen/live claramente distinguidos.
- Sin hardcodeo de meses/cantidades.
- Acta de cierre + evidencias (E2E **y** fixtures, incl. el envelope `error_entorno` **heredado del
  Bloque 0**) + decisiones D-FE-46+/L-FE-13+ acuñadas (propagación a satélites/OPS diferida).

---

## 19. Próximo paso posterior (solo mencionado, no diseñar)

Después de cerrar el bloque UI: **promoción integral a OPS** — gateway (adiciones L3), wrappers A30/A31
y frontend, coordinada, con verificación de fingerprint estructural TEST↔OPS y propagación a satélites/
canónico. **No se diseña ni se arranca en este bloque.**

---

## 20. Archivos a subir a la conversación nueva

Lista priorizada completa (el kickoff es autosuficiente; no depende de ningún mensaje externo). Si la
nueva conversación tiene acceso al repo completo, los adjuntos P2/P3 sirven como **pin explícito de
autoridad**, pero **igual debe inspeccionarse el clone fresco** de `main`.

**P1 — imprescindibles (contrato + integración + molde):**

- `Apps/portal-operativo/src/screens/CuentaCorrienteDetalle.tsx`
- `Apps/portal-operativo/src/screens/CuentaCorriente.tsx`
- `Apps/portal-operativo/src/lib/callPortal.ts`
- `Apps/portal-operativo/src/hooks/useAction.ts`
- `Apps/portal-operativo/src/lib/actionRegistry.ts`
- `Apps/portal-operativo/src/app/rutas.tsx`
- `Apps/portal-operativo/src/app/RutaProtegida.tsx`
- `Apps/portal-operativo/src/lib/contratos.ts`
- `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/11-07-2026/CC_L3_BLOQUE0_CIERRE.md`
- este kickoff corregido.

**P2 — importantes (estilo, formato, sesión, QA):**

- `Apps/portal-operativo/src/ui/Money.tsx`
- `Apps/portal-operativo/src/lib/formato.ts`
- `Apps/portal-operativo/src/lib/periodo.ts`
- `Apps/portal-operativo/src/lib/constantes.ts`
- `Apps/portal-operativo/src/ui/DataTable.tsx`
- `Apps/portal-operativo/src/ui/Cargando.tsx`
- `Apps/portal-operativo/src/ui/ErrorCard.tsx`
- `Apps/portal-operativo/src/ui/Vacio.tsx`
- `Apps/portal-operativo/src/lib/types.ts`
- `Apps/portal-operativo/src/auth/AuthProvider.tsx`
- `Apps/portal-operativo/src/app/Menu.tsx`
- `Apps/portal-operativo/tailwind.config.js`
- `Apps/portal-operativo/package.json`
- `Apps/portal-operativo/vercel.json`
- `Apps/portal-operativo/B5_RUNSHEET_QA.md`
- `Docs/Implementacion/Carril_C/PORTAL_FRONTEND/CONTRATO_FRONTEND_PORTAL_v1.md`

**P3 — referencia contractual del shape de A30/A31 (no editar):**

- `Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/10-07-2026/portal-a30-cuenta-corriente-historico__TEST.json`
- `Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/10-07-2026/portal-a31-cuenta-corriente-historico-acumulados__TEST.json`
- `Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/10-07-2026/portal-api_A31_TEST_index.ts`
- `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/11-07-2026/CC_L3_BLOQUE0_EVIDENCIAS_EJECUCION_TEST.md`
