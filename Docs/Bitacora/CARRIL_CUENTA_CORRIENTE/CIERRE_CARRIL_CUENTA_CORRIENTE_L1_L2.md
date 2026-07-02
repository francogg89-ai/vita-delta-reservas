# Cierre — Frente Cuenta Corriente de Socios (lecturas L1 + L2)

Acta de cierre del frente de **lecturas** de la cuenta corriente de socios, expuesto en el
portal operativo interno. Estado: **completo y verde en TEST**; listo para promoción a OPS.

> Este documento es el **acta** (Bloque 1). Los `D-CC-*`/`L-CC-*` que siguen son **candidatos
> propuestos**: se acuñan formalmente y se propagan a los satélites recién en el Bloque 4
> (canonización), pegado a la promoción a OPS. El canónico `6B_SCHEMA_SQL.md` se bumpea una
> sola vez, en esa promoción coordinada.

---

## 1. Qué es este frente

Exponer, como **lecturas read-only** en el portal, la cuenta corriente de cada socio, aplicando
el motor contable del Carril B (ya promovido a OPS y canónico). **No se construyó contabilidad
nueva: se expuso un motor existente**, con el mismo patrón que las lecturas A24/A25/A13.

Tres lecturas planeadas: **L1** (al día), **L2** (drill-down), **L3** (histórico). Este frente
cierra **L1 y L2**. L3 queda diferido (depende de las fotos congeladas, que son el frente de
escritura siguiente).

- **L1 — `cuenta_corriente.al_dia` (A27):** saldo acumulado en vivo por socio desde el piso
  contable, con desglose (meses previos / mes en curso provisorio / reembolsos / movimientos /
  saldo al día).
- **L2 — `cuenta_corriente.detalle` (A28):** drill-down de un mes elegido — cascada de 11 pasos,
  matriz de participación (por socio + por cabaña) e incidencias por gasto.

Visibilidad: **socio-only**, transparencia total entre los tres socios (cada uno ve a los tres).

---

## 2. Arquitectura (cuatro capas, patrón A24/A25)

1. **SQL (función-lectura):** toda la lógica vive en una función versionada, `STABLE`,
   `SECURITY INVOKER`, revocada de `PUBLIC/anon/authenticated/service_role`. Se prueba "directo"
   en TEST idéntica a como la llamará el wrapper.
2. **n8n (wrapper firmado):** webhook → `validar_firma_ts_rol` (HMAC-SHA256 sobre el body crudo +
   ts 300s + allowlist de rol + action binding) → `leer_ambiente` → `verificar_acceso` → nodo
   Postgres (corre como owner) → render del sobre `{ok, data}`.
3. **Gateway `portal-api`:** una entrada aditiva en el `CATALOG` por acción; A02 deriva el menú
   filtrando el CATALOG por rol (`Object.keys(CATALOG).filter(a => CATALOG[a].roles.includes(rol))`),
   así `roles:['socio']` hace que la acción aparezca sola para socios, sin tocar A02.
4. **Frontend (React/Vite):** registro en `actionRegistry.ts` (grupo "Socios"), ruta derivada,
   pantalla que consume la acción vía `useAction`/`callPortal`.

---

## 3. Artefactos generados

Guardados en la bitácora del carril (carpeta `Docs/Bitacora/CARRIL_CONTABILIDAD/`; Franco la
referenció como `CARRIL_CUENTA_CORRIENTE` — conviene reconciliar el nombre). El workflow A27
también quedó en `Workflows/n8n/Supabase/`.

**SQL (environment-agnostic; corren igual en OPS):**
- `CC_L1_DIRECTO_funcion_cuenta_corriente_viva_TEST.sql` — función `cuenta_corriente_viva(p_hasta_fecha date, p_pct_operativo numeric)`.
- `CC_L1_DIRECTO_prueba_1grid_cuenta_corriente_viva_TEST.sql` — prueba read-only en 1 grilla.
- `CC_L2_DIRECTO_funcion_cuenta_corriente_detalle_TEST.sql` — función `cuenta_corriente_detalle(p_mes date, p_pct_operativo numeric)` → jsonb.
- `CC_L2_DIRECTO_prueba_1grid_cuenta_corriente_detalle_TEST.sql` — prueba read-only en 1 grilla.

**n8n (variantes TEST; las OPS se generan en el Bloque 2 con webhook `__OPS`):**
- `portal-a27-cuenta-corriente__TEMPLATE.json`
- `portal-a28-cuenta-corriente-detalle__TEMPLATE.json`

**Gateway (deltas TEST; los OPS se generan en el Bloque 2 sobre el gateway OPS A26):**
- `portal-api_A27_TEST_index.ts` (delta A27: entrada `cuenta_corriente.al_dia`).
- `portal-api_A28_TEST_index.ts` (delta A28: validador `payloadCuentaCorrienteDetalle` + entrada `cuenta_corriente.detalle`).

**Smokes read-only:**
- `CC_L1_A27_smoke_directo.ps1`, `CC_L2_A28_smoke_directo.ps1`.

**Frontend (ya commiteado en `main`):**
- `Apps/portal-operativo/src/lib/contratos.ts` (tipos L1 + L2).
- `Apps/portal-operativo/src/lib/actionRegistry.ts` (grupo "Socios" + 2 entradas).
- `Apps/portal-operativo/src/app/rutas.tsx` (imports + PANTALLAS).
- `Apps/portal-operativo/src/screens/CuentaCorriente.tsx` (L1).
- `Apps/portal-operativo/src/screens/CuentaCorrienteDetalle.tsx` (L2).

---

## 4. Contrato de las acciones

**A27 `cuenta_corriente.al_dia`** — `roles:['socio']`, `validate: payloadVacio`. Payload `{}`.
Respuesta: `{ ok, data:{ filas:[{ id_socio, socio, liquidacion_meses_previos,
liquidacion_mes_en_curso, reembolsos_acumulados, movimientos, saldo_al_dia }] } }`.

**A28 `cuenta_corriente.detalle`** — `roles:['socio']`, `validate: payloadCuentaCorrienteDetalle`.
Payload `{ mes: 'YYYY-MM-01' }` (obligatorio, YMD, >= piso). Respuesta: `{ ok, data:{ mes,
cascada[], matriz[], matriz_cabanas[], incidencias[], gastos_sin_incidencia[] } }`.

En ambos, el `pct` (0.25) lo **hardcodea el wrapper** (interino; destino `configuracion_general`);
no viaja en el request. El nodo Postgres corre como owner; las funciones están revocadas.

---

## 5. Decisiones candidatas (`D-CC-*`, a acuñar en el Bloque 4)

- **D-CC-01** — La cuenta corriente **acumula en vivo desde el piso 2026-07-01** y NO se reinicia
  mensualmente; el reparto anual (jun-2027) es la suma de los 12 meses. El pool estacional se
  respeta: cada mes reparte con su propia matriz.
- **D-CC-02** — Visibilidad **socio-only**, transparencia total entre los tres socios. La función
  devuelve las filas de los tres sin importar cuál socio llame (sin `injectActor`).
- **D-CC-03** — El **% operativo (0.25)** viaja hardcodeado en el wrapper (interino; destino
  `configuracion_general`), no en el request. Toma 0 en meses de pérdida (nunca absorbe pérdidas):
  comportamiento nativo del motor (`GREATEST(base,0)*pct`).
- **D-CC-04** — L1 usa **expresión timezone inline** (`now() AT TIME ZONE
  'America/Argentina/Buenos_Aires'`), NO `fecha_hoy_ar()`, para no acoplar el frente a la promoción
  del motor de horarios (ese helper es TEST-only).
- **D-CC-05** — En L1 los **movimientos se ventanean por fecha** (`fecha` en `[piso, hasta]`):
  semántica as-of correcta y borde pre-piso limpio (0 filas).
- **D-CC-06** — L2 se expone como **un jsonb compuesto** (una función que compone las funciones del
  motor), NO tres endpoints separados.
- **D-CC-07** — A27 es la **primera acción socio-only** del sistema (`roles:['socio']`): la cuenta
  corriente es reparto de socios, no economía operativa (ni vicky ni jenny la ven).
- **D-CC-08** — L1 usa **payload vacío** (`payloadVacio`); L2 usa **payload `{mes}`** validado con
  el validador nuevo `payloadCuentaCorrienteDetalle` (obligatorio, YMD, >= piso).
- **D-CC-09** — La columna del frontend se mantiene **"Movimientos"** (no "Retiros"), porque el
  backend suma todos los tipos de `movimientos_socio` (retiro/adelanto/ajuste/...), no solo retiros.
- **D-CC-10** — El frontend tiene un **grupo propio "Socios"** (separado de "Económico", que ve
  vicky).
- **D-CC-11** — **L3 (histórico) queda diferido**: lee las fotos congeladas, que no existen hasta
  el frente de escritura (congelado). Recomendación asentada: hacer congelado antes que L3.

## 6. Lecciones candidatas (`L-CC-*`, a acuñar en el Bloque 4)

- **L-CC-01** — En funciones `RETURNS TABLE` con `UNION`, el `ORDER BY` **por nombre de columna**
  colisiona con el parámetro OUT homónimo; hay que ordenar **por posición** (`ORDER BY 1`). Solo se
  detecta ejecutando en PostgreSQL real (pglast parsea igual).
- **L-CC-02** — Sin ventana de fecha, un saldo "al día X" arrastra movimientos posteriores y el
  borde pre-piso devuelve filas espurias. Ventanear por `fecha` lo corrige. Cazado en PG real.
- **L-CC-03** — El **SQL Editor de Supabase** ejecuta todos los `SELECT` de un script pero **solo
  muestra el resultado del último** → las pruebas se consolidan en **una sola grilla**.
- **L-CC-04** — "destructive query / Success. No rows returned" en Supabase es normal: lo dispara
  el `DROP FUNCTION`, no es error.
- **L-CC-05** — Para funciones que devuelven jsonb: `COALESCE(jsonb_agg(...), '[]'::jsonb)` para que
  las secciones vacías sean `[]` (no null), y `jsonb_agg(... ORDER BY ...)` para el orden interno.
- **L-CC-06** — **El gateway OPS usa sufijo `__OPS` en TODOS los webhooks** (lecturas y escrituras);
  TEST usa sin sufijo en lecturas y `__TEST` en escrituras. Las variantes OPS de los workflows y los
  deltas del gateway OPS deben apuntar a `portal-aXX-...__OPS`.
- **L-CC-07** — A02 deriva el menú del CATALOG; agregar la entrada con `roles:['socio']` hace que la
  acción aparezca sola para socios y que la ruta quede protegida, sin tocar A02.

---

## 7. Estado de validación (TEST)

- **L1 directo:** reconciliación (función == Σ mes a mes de `saldo_socios_periodo` + Σ movimientos
  ventaneados) **PASS ×3**; guard y bordes OK. Ejecutado contra PostgreSQL 16.
- **A27 wrapper:** smoke directo **11/11 PASS** (socio-only con vicky rebotando; seguridad;
  funcional con `saldo_al_dia` = suma de las 4 columnas). Gateway TEST deployado.
- **L2 directo:** prueba 1grid **6/6 PASS** (6 claves, guard, cascada consistente: paso8=Σpaso9,
  paso11=paso9+paso10, Σincidido=monto del gasto). Ejecutado contra PostgreSQL 16.
- **A28 wrapper:** smoke directo **15/15 PASS** (socio-only; 4 casos de `{mes}` → payload_invalido;
  `data.mes` round-trip; 6 secciones; cascada no vacía). Gateway TEST deployado.
- **Frontend:** `tsc --noEmit` estricto **exit 0** + `npm run build` **exit 0**. Verificado en vivo
  contra TEST logueado como socio (L1 y L2 renderizan con datos reales).

Números de referencia (TEST, julio-2026 @ 25%): Franco −143.492,07 · Rodrigo 171.507,93 · Remo
55.884,14 (suma 83.900,00).

---

## 8. Relevamiento OPS (para el Bloque 2)

- **Gateway OPS actual:** `portal-api_OPS_index_A26.ts` (A26; **no** tiene A27/A28). Tiene
  `payloadVacio`, `isYMD_GW` y la entrada A26 (ancla para insertar A27). El delta OPS se aplica
  sobre **este** archivo, no sobre el de TEST.
- **Webhooks OPS con sufijo `__OPS`** (ver L-CC-06): las entradas A27/A28 del CATALOG OPS deben
  apuntar a `portal-a27-cuenta-corriente__OPS` y `portal-a28-cuenta-corriente-detalle__OPS`, y los
  workflows OPS deben tener esas rutas.
- **Funciones del motor (Carril B) en OPS:** presentes (promovidas junio 2026, canónicas):
  `cascada_periodo`, `matriz_participacion`, `detalle_participacion`, `incidencia_gasto`,
  `gastos_sin_incidencia_periodo`, `saldo_socios_periodo`, `movimientos_socio`, `socios`, etc.
- **Falta en OPS:** las 2 funciones nuevas (`cuenta_corriente_viva`, `cuenta_corriente_detalle`),
  los 2 workflows (con ruta `__OPS`), y las 2 entradas del gateway OPS.
- **Frontend:** L1 + L2 **ya commiteados en `main`** (Vercel ya los sirve; ocultos en OPS hasta que
  el gateway OPS tenga las acciones). No hay merge pendiente del frontend.

---

## 9. Pendientes

- **L3 (histórico mes a mes)** — diferido; depende de las fotos (frente de escritura).
- **Frente de escritura: congelado + retiros/reembolsos** — snapshot de fin de mes (respetando "IA
  propone, humanos aprueban") + exposición de retiros. Es el frente siguiente.
- **pct → `configuracion_general`** — mover el 0.25 hardcodeado a una clave editable (cambio de una
  línea en cada wrapper), cuando se decida.

---

## 10. Plan de promoción a OPS (bloques)

1. **Bloque 1 — Cierre + relevamiento OPS** (este documento). ✔
2. **Bloque 2 — Backend a OPS:** las 2 funciones SQL (corren en OPS tal cual) + los 2 workflows OPS
   (con webhook `__OPS`) + el delta del gateway OPS (sobre A26, entradas a `__OPS`) + smokes
   read-only contra OPS.
3. **Bloque 3 — Verificación end-to-end:** smoke vía gateway OPS (con auth, como socio) y chequeo
   en vivo de las dos pantallas en OPS (el frontend ya está en `main`).
4. **Bloque 4 — Canonización + satélites:** bump de `6B_SCHEMA_SQL.md` (las 2 funciones con sus
   REVOKE) + actualización de los seis satélites + acuñar los `D-CC-*`/`L-CC-*` definitivos, en un
   solo pase coordinado.

**Orden seguro** (para no romper el grid): funciones → workflows → gateway OPS. Como A02 arma el
menú del CATALOG, hasta que el gateway OPS no tenga las acciones nuevas quedan ocultas; al deployarlo
se "prenden" y ya encuentran los workflows.
