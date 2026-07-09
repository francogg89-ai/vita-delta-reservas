# ESTADO ACTUAL — COMPLEJO VITA DELTA

## Resumen ejecutivo

El sistema de reservas de Complejo Vita Delta tiene **backend Supabase DEV completo (6B v1.7.3 con hardening estructural y de concurrencia aplicados) + workflows n8n operativos (6C) + Etapa 6D cerrada (2026-05-27) + Etapa 7A de correcciones pre-TEST/pre-OPS cerrada (2026-05-28) + entorno TEST levantado, paritario y operativo (7B, cerrada 2026-05-28) + validación funcional ampliada sobre TEST (7C, cerrada 2026-05-28) + limpieza/reset de TEST (7D, cerrada 2026-05-28) + endurecimiento de permisos Data API en DEV (7E, cerrada 2026-05-28) + entorno OPS de operación real interna levantado, paritario, seguro y conectado a n8n (8A, cerrada 2026-05-29) + capa de carga interna de reservas (Form Trigger n8n) validada en TEST y con primera reserva real cargada en OPS (8B, cerrada 2026-05-30) + calendarios visuales por evento (HTML operativo + HTML limpieza + Sheet de resguardo, derivados de solo lectura) validados en TEST y operativos en OPS (8C, cerrada 2026-06-01; HTML activos y en uso real por el equipo) + capa de bloqueos operativos (Form Trigger n8n) validada en TEST y operativa en OPS (8D, cerrada 2026-06-04). **Con 8D se cierra la Etapa 8 completa (operación real interna): 8A entorno + 8B reservas + 8C calendarios + 8D bloqueos**. Posteriormente se cerró la **sub-etapa 8C-bis** (alerta por reserva próxima por mail, recoge el item 3.1 de pre-producción): un sub-workflow que, al confirmarse una reserva con check-in en [hoy, hoy+7], avisa por correo al equipo operativo (Franco, Rodrigo) y a Jennifer, invocado en rama lateral desde 8B; validado en TEST con envío real y publicado/activo en OPS (cerrada 2026-06-04). Los workflows n8n fueron validados contra DEV en Etapa 6C (40 tests funcionales + verificaciones cruzadas) y contra TEST en Etapa 7B (smokes happy path 8/8) y 7C (validación funcional ampliada de caminos no-felices); en TEST se validó además la cadena transaccional completa W2→W3→W4 end-to-end. Hardening estructural y de concurrencia validados en DEV: 101 tests de hardening + 6 tests de concurrencia real + 9 tests funcionales y 4 estructurales de 7A. Posteriormente se construyó la **contabilidad operativa interna (Carril B, 9C→9H + helper 9B)**, cerrada en TEST y **promovida a OPS** por DDL (junio 2026), con el canónico **bumpeado a v1.8.0** y paridad estructural TEST↔OPS certificada por huella (ver `PROMOCION_CARRIL_B_OPS_CIERRE.md`).

**Etapa actual:** Frente Cuenta Corriente de socios — **snapshot mensual con detalle fino congelado + L3 histórico** (backend) / **canónico v1.12.0** — **cerrada 2026-07-07** (estructural). Cierre de la capa de **congelado + lectura histórica**, en dos bloques aditivos sobre la foto 9H. **Bloque 1 (extensión del snapshot):** `registrar_snapshot_periodo` extendida para congelar —en la misma txn/`pg_advisory_xact_lock` que cascada+socios— el detalle fino que P-CC-2 exige (participación por cabaña, gastos = foto fiel de `gastos_internos`, incidencias por gasto), vía **3 tablas append-only** (`liquidacion_participacion`/`liquidacion_gasto`/`liquidacion_incidencia`; PKs compuestas, 0 secuencias) con **inmutabilidad/REVOKE/supersesión idénticas a 9H** (el ARRAY de C6 pasa a **8 tablas / 16 triggers**); matriz y nombres derivados; `id_gasto` copiado **sin FK** (foto autocontenida). **Bloque 2 (L3):** **2 funciones read-only** —`cuenta_corriente_historico(date)` y `cuenta_corriente_historico_acumulados()`— sobre la foto vigente (`liquidacion_vigente`, nunca superseded), `search_path` fijo, `STABLE`/`SECURITY INVOKER`, revocadas de los 3 roles Data API + `PUBLIC`; una sola construcción cubre foto-con-detalle y pre-extensión (detalle vacío → `[]`); el piso no se doble-filtra (`saldo_corriente_socio` verbatim, piso solo como check en `meta`). **Promovido a OPS solo estructura:** greenfield en datos (L3 devuelve `sin_foto`/`sin_datos`), la **primera foto real** es paso controlado posterior. Validación: harness PostgreSQL 16.14 + `pglast`; TEST funcional (extensión Run 05 rollback-first 11/11; L3 verify 14/14 por función + contrato sobre 3 fotos pre-extensión + rollback-first con foto efímera con detalle); OPS estructural (extensión `04_VERIFY` T1=5/T2=19/T3=7 + 6 triggers + 0 grants; L3 verify 14/14 + smoke greenfield 6/6). Canónico `6B_SCHEMA_SQL.md` **bumpeado a v1.12.0** (3 tablas + 6 triggers + snapshot extendido + 2 funciones L3 + hardening C12/C14; **conteos vigentes 35/38/16**; aditivo). **Decisiones D-CC-23…39; lecciones L-CC-13…19.** Pendientes del frente: **primera foto real OPS** y **cierre asistido** (P-L3-01/P-L3-02); exponer CC/L3 en el portal; **reembolsos** (remanente P-CC-2). Cierres: `EXT_SNAPSHOT_BLOQUE1_CIERRE.md`, `L3_HISTORICO_BLOQUE2_CIERRE.md`.

**Etapa previa:** Frente Cuenta Corriente de socios — **escritura / retiro desde saldo vivo** (backend + gateway) / **promoción coordinada a OPS + canónico v1.11.0** — **cerrada 2026-07-05**. Se construyó la **capa de escritura** de la cuenta corriente: un socio puede **retirar contra su saldo vivo** desde el portal. Cadena por bloques: **SB0** (columna `portal_usuarios.id_socio` + FK a `socios` `ON DELETE RESTRICT` + `UNIQUE` + `CHECK` bicondicional `rol↔id_socio`, backfill por `lower(btrim(nombre))`) → **SB1** (tabla `portal_idempotencia_cc` `REVOKE`-all + `registrar_retiro_desde_saldo_vivo(...)`, que valida contra `cuenta_corriente_viva` y RAISE `VD001`/`saldo_insuficiente` **antes** del INSERT, + wrapper `portal_registrar_retiro(jsonb)` con binding de identidad e idempotencia) → **A29 gateway** (acción `cuenta_corriente.retirar` **socio-only**, flag `injectSocioIdentity` que inyecta `id_socio`+`user_id` server-side y **rechaza** los del cliente top-level y en payload, `monto` string, `saldo_insuficiente` con `detail` sanitizado) + wrapper n8n firmado `portal-a29-retiro__OPS`. **Promovido a OPS** bloque por bloque (A: SB0 · B: SB1 · C: gateway + wrapper **re-derivados sobre la base OPS** · D: smoke **negative-only**), con **anti-OPS estricto**: el smoke OPS **no** hace happy-path, **no** hace retiro real y **no** consume secuencias (todos los casos son rechazos o `saldo_insuficiente`, que corta antes del INSERT), verificado en la DB con `portal_idempotencia_cc` **vacía** y su secuencia **sin usar**. Canónico `6B_SCHEMA_SQL.md` **bumpeado a v1.11.0** (SB0 en `portal_usuarios` + `portal_idempotencia_cc` + `registrar_retiro_desde_saldo_vivo` en PARTE C + `portal_registrar_retiro` en PARTE D + **D5 extendido a la 2ª FK**; aditivo). Validación por bloque: SB0 `A2_VERIFY` 10/10; SB1 `VERIFY` 23/23 (estructura + 7 negativos + guardas 0-write/0-nextval); gateway `tsc`/`esbuild` limpios (delta 0); wrapper `node --check` 5/5; smoke OPS **32 PASS/0 FAIL** + PART B DB 8/8. **La UI del Portal Operativo para el retiro (botón/pantalla "Retirar saldo") queda PENDIENTE como frente posterior** (backend y gateway listos; sin frontend en este cierre). **Decisiones D-CC-15…22; lección L-CC-12** (no se acuñó L-CC-13: el falso positivo de `node --check` async ya es **L-C-27**). Pendientes del frente: **P-CC-1/L3** (histórico), **P-CC-5** (pct periodizado), **snapshot mensual** y la **UI del retiro**. Cierre: `CIERRE_RETIRO_SALDO_VIVO_OPS.md`.

**Etapa previa:** Sub-bloque 0 — `pct` operativo a `configuracion_general` + canónico v1.10.1 — **cerrada 2026-07-03**. El porcentaje operativo (`0.25`), que **hardcodeaban los wrappers A27/A28** (interino desde el cierre L1/L2), pasó a la clave `pct_operativo` de `configuracion_general` (`tipo_valor='numeric'`, `editable=false`), leída por el helper `pct_operativo_vigente()` — validación fuerte (existe / no NULL / no vacía / decimal por regex `[.]` / rango `[0,1]`), errores parseables `[pct_config_ausente]`/`[pct_config_invalido]`, **sin fallback silencioso** (D-CC-14). **A27/A28 leen el helper**; cambio **output-neutral** verificado por identidad SQL determinística + hash SHA256 pre/post del webhook directo, **idéntico en TEST (`7a4385…`) y OPS (`7e075a…`)** — promovido a OPS 2026-07-03. Canónico `6B_SCHEMA_SQL.md` **bumpeado a v1.10.1** (helper en PARTE C + seed `pct_operativo` en C13; aditivo). Secuencia S0.1→S0.2→S0.3→S0.4. **El bootstrap kit sigue pineado a `bootstrap_entorno_nuevo_v1.9.0/` como deuda consciente (P-CC-4)**: rezagado respecto de v1.10.1 (le faltan las funciones CC de v1.10.0 y el helper+seed de v1.10.1); se regenera al cierre del frente completo de cuenta corriente (escritura/retiros + snapshot + L3), salvo necesidad de crear un entorno nuevo antes. Pendientes del frente: **P-CC-2** (escritura/retiros + snapshot mensual = cascada completa), **P-CC-1/L3** (histórico), **P-CC-5** (pct periodizado / vigencia futura). **Decisiones D-CC-13/14; lecciones L-CC-09/10/11.** Cierre: `S0_CIERRE.md`.

**Etapa previa:** Frente Cuenta Corriente de socios — lecturas L1 + L2 en el portal / **promoción coordinada a OPS + canónico v1.10.0** — **cerrada 2026-07-02**. Se expuso, como **lecturas read-only socio-only** en el Portal Operativo, la cuenta corriente de cada socio, **componiendo el motor del Carril B** ya promovido (no se construyó contabilidad nueva; mismo patrón que A24/A25/A13). Dos lecturas: **L1 `cuenta_corriente.al_dia` (A27)** — saldo acumulado en vivo por socio desde el piso 2026-07-01, con desglose (meses previos / mes en curso provisorio / reembolsos / movimientos / saldo al día), función `cuenta_corriente_viva(p_hasta_fecha, p_pct_operativo)` — y **L2 `cuenta_corriente.detalle` (A28)** — drill-down de un mes (cascada de 11 pasos + matriz por socio/cabaña + incidencias por gasto), función `cuenta_corriente_detalle(p_mes, p_pct_operativo)` que devuelve **un jsonb compuesto**. Ambas `STABLE`/`SECURITY INVOKER`, revocadas de PUBLIC/anon/authenticated/service_role; el `pct` (0.25) lo **hardcodea el wrapper** (interino, destino `configuracion_general`), no viaja en el request. **A27 es la primera acción socio-only** del sistema (`roles:['socio']`): ni vicky ni jenny la ven; A02 la deriva del CATALOG sin cambios. Cadena por acción: función SQL → wrapper n8n firmado (HMAC + `ts` + rol + action binding + ambiente) → gateway `portal-api` → pantalla React (`useAction`). **Promovido a OPS** en un paquete coordinado (funciones `CREATE OR REPLACE` → 2 workflows con webhook `__OPS` → gateway sobre el OPS A26), verificado en vivo en las dos pantallas de OPS; el frontend viajó en `main` (Vercel). Canónico `6B_SCHEMA_SQL.md` **bumpeado a v1.10.0** (las 2 funciones + `REVOKE` en la PARTE C; bump aditivo). Validación: L1 reconciliación ×3 + A27 smoke 11/11; L2 directo 6/6 + A28 smoke 15/15; frontend `tsc`+`build` EXIT 0; smokes directos read-only **verdes contra TEST y OPS** (guard OPS `__OPS`/ambiente antes de firmar). **Decisiones D-CC-01…12; lecciones L-CC-01…08.** Pendientes del frente: **L3 (histórico)** diferido (depende del congelado, el frente de escritura siguiente), **`pct` → `configuracion_general`**, y **regenerar el bootstrap kit a v1.10.0** (hoy pineado a v1.9.0; bajo riesgo, son lecturas). Cierre: `CIERRE_CARRIL_CUENTA_CORRIENTE_L1_L2.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **promoción coordinada a OPS + canónico/kit v1.9.0** — **cerrada 2026-06-29**. El Carril C completo (gateway `portal-api`, los 13 wrappers n8n y el frontend) quedó **promovido a OPS** en una operación coordinada bloque por bloque (Bloques A→H, junio 2026), **por DDL y sin copiar datos de TEST**, y el canónico `6B_SCHEMA_SQL.md` se **bumpeó a v1.9.0** (Bloque I) incorporando las 3 estructuras internas del portal (`portal_usuarios`, `portal_idempotencia`, `portal_cargar_gasto_interno(jsonb)`) como **PARTE D** + §25 conceptual. **Paridad estructural TEST↔OPS del portal certificada por fingerprint** (huella `TOTAL_PORTAL` idéntica: `dee953e867aed06a9c65836bac14e8f7`) y **smokes read-only end-to-end por rol 14/14** contra el gateway de OPS (anti-OPS respetado: cero escrituras, cero consumo de secuencias del negocio). Los 13 wrappers `__OPS` se validaron con **escrituras reales** (cobro multi-porción A10-MP + alta A07; el aviso 8C-bis disparó con `entorno=ops`). Hallazgo del Bloque E: un **candado anti-OPS `TEST-only` hardcodeado** en `verificar_acceso` de A10-MP/W10 (discriminaba por literal `!== 'test'`), **removido de A10-MP** y **conservado a propósito en W10** (deprecated, nunca invocado). Incidente de datos del Bloque G (autofill del navegador + dedup por email) resuelto con corrección de datos + **defensa doble capa** en el frontend. Banner de ambiente resuelto para OPS (sin banner, **P-FE-09**); CORS por env var (`CORS_ALLOW_ORIGIN`, nunca `'*'`, **P-C-7**). El **bootstrap kit** se regeneró pineado a `bootstrap_entorno_nuevo_v1.9.0/` (9 archivos) con verificación estricta del entorno; el kit `v1.8.1/` se **retiró del árbol** (decisión de limpieza del cierre; queda en el historial de git). **Decisiones D-PROMO-C-01…14; lecciones L-PROMO-C-01…08.** Deuda **D-C-64…70** (A10-MP) saldada en el ledger. **W10** queda deprecated-in-place (**no es deuda**). Próxima etapa: operación del portal sobre OPS; en frentes separados, **Mercado Pago** (pagos autónomos) y la **web pública**. Cierre: `PROMOCION_CARRIL_C_OPS_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Aviso 8C-bis enganchado al alta por el portal (A07)** — **cerrado en TEST 2026-06-26**. Hallazgo (2026-06-26): el aviso por mail 8C-bis (alerta al confirmar una reserva con check-in en `[hoy, hoy+7]`) se disparaba **solo desde el form de 8B** (PUNTO EXTENSION 8C → Call); el wrapper **A07 del portal no lo invocaba** → un alta por el portal no avisaba. Se agregó al wrapper A07 una **rama lateral no bloqueante** (espejo del patrón de 8B) que llama al sub-workflow `vita_w8cbis_alerta` por `executeWorkflow`, **sin lógica nueva de mail** (el sub-workflow es autocontenido: re-lee la reserva, decide la ventana, manda). **+2 nodos, +1 conexión** sobre el A07 vivo (los 22 nodos originales byte-idénticos): un **gate** (`if`) que solo deja pasar la confirmación fresca (`envelope.ok===true && idempotent_match===false` → un reintento idempotente no manda mail repetido) y un **`Call`** (`executeWorkflow`) con `onError: continueRegularOutput`, **Wait ON** (no OFF: OFF puede abortar el sub-workflow) y **hoja sin salida**, con el fan-out colgando de `router3_confirmar` y la **rama principal conectada primero**. **Garantía de no-afectación por configuración** (no async puro): `onError` + hoja + rama principal primero → `respondToWebhook` emite en su rama; si el aviso falla, la reserva responde `ok:true` igual. El `entorno` se resuelve desde **`leer_ambiente.valor`** (marcador canónico, sin hardcode → la promoción a OPS no requiere flip); input al sub-workflow `{id_reserva, id_pre_reserva, entorno, source:'a07_portal', operador}`. Validado end-to-end en TEST: **5 gates verdes** (alta en ventana → mail; reintento idempotente → sin segundo mail; fuera de ventana → sin mail; aviso pineado para fallar → A07 `ok:true`; input verificado en la ejecución). **Decisiones D-C-71…73; lecciones L-C-24/25.** **Sin cambios en backend del motor, gateway `portal-api`, OPS, `6B_SCHEMA_SQL.md` v1.8.1, W10 ni el contrato** (el sub-workflow 8C-bis se reusa tal cual; es una rama de side-effect del wrapper A07). **No promovido a OPS.** Próxima etapa: **promoción coordinada del Carril C a OPS** (el `Call` apunta al 8C-bis OPS, `entorno` resuelto a `'ops'`; P-FE-01 catálogo real, P-C-7 CORS, P-FE-09 banner, GRANTs/seed real). Cierre: `AVISO_8CBIS_PORTAL_A07_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Frontend TEST · sub-slice 3 (publicación TEST + piloto operativo)** — **cerrado 2026-06-26**. Con las 8 lecturas + 4 escrituras ya construidas y validadas por bloque, el sub-slice 3 **publicó el portal en un link TEST real** y corrió un **piloto operativo controlado** con los usuarios reales en sus roles. Deploy: **build estático** (`vite build` → `dist/`) en **Vercel** (Root Directory `Apps/portal-operativo`, fallback SPA por `vercel.json`, sin `base`), cableado a Supabase/`portal-api` de **TEST** por las dos env vars browser-safe (`VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY`; nunca `service_role`), **D-FE-30**. Precondición bloqueante cumplida: un **banner de ambiente** fijo "AMBIENTE DE PRUEBA · TEST" visible **pre-login** + título de pestaña diferenciado, derivado de la URL del build (ref TEST `bdskhhbmcksskkzqkcdp`; estado defensivo `'desconocido'` para lo no reconocido; sin `VITE_AMBIENTE`, una sola fuente de verdad), **D-FE-29**. Los **7 gates** pasaron en verde (typecheck+build EXIT 0; deploy publicado; banner amarillo visible; env a TEST; incógnito sin login = solo login+banner, nada operativo; login Jenny/Vicky/socio OK; **sin `service_role`/HMAC/secretos** en frontend, repo, logs ni instrucciones). Se entregaron **instrucciones cortas por rol** (Jenny / Vicky / socios; explícito "es TEST, no cargar datos reales de huéspedes, reportar en el tracker") y un **tracker de feedback** (planilla con severidad/estado). **Resultado del piloto: OK — los usuarios reales operaron sin asistencia y entendieron el flujo; cero blockers y sin fixes menores de frontend pendientes.** Solo **decisiones D-FE-29/30 y lecciones L-FE-08/09**; el único pendiente nuevo es de OPS: **P-FE-09** (extender el reconocimiento del banner al ref de OPS al promover). **Sin cambios en backend, gateway `portal-api`, wrapper n8n, OPS, `6B_SCHEMA_SQL.md` v1.8.1, W10 ni el contrato** (solo deploy/banner/`vercel.json` + documentación del piloto). A10 en el frontend sigue siendo **`cobranza.registrar_cobro`** (B5), no se reabrió. Con esto cierra la **Etapa 2 (Frontend TEST)** del Carril C. Próxima etapa: **preparar la promoción coordinada del Carril C a OPS** (P-FE-01 catálogo real, P-C-7 CORS al origin real, GRANTs/seed real, P-FE-09 banner; sin resolverlos acá). Cierre: `FRONTEND_SUBSLICE3_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Frontend TEST · sub-slice 2 (las 4 escrituras)** — **cerrado 2026-06-25**. Sobre los **cimientos de escritura** (B1: `useEnviar`, átomos `Campo`/`BotonSubmit`/`TarjetaExito`/`Banner`, familias de error, tipos de respuesta y catálogos TEST) se construyeron las **4 pantallas de escritura** del portal: **A08** `bloqueo.crear_manual` (B2, sin key, guard por solapamiento), **A07** `reserva.crear_manual` (B3, sin key, idempotencia derivada → `idempotent_match`; seña `0`=auto 50%, D-FE-26), **A11** `cargar.gasto_interno` (B4, key **sibling**, condicionales por clase A/C/D/E y pagador) y **A10-MP** `cobranza.registrar_cobro` (B5, key **en payload**, cobranza multi-porción efectivo/transferencia bancaria·mp/otros + recargo 5%, **bloqueo de sobrepago** D-FE-21). **B5 usa solo `cobranza.registrar_cobro`**; **W10 `cobranza.registrar_saldo` queda deprecated-in-place** y desaparece del frontend por **tolerancia-forward** (rename de la entrada del registry, D-FE-27), **sin tocar backend**. Patrón de escritura común: `useEnviar` con transporte de `idempotency_key` por acción y ciclo key-nueva/reintento-reusa/reset-on-edit (D-FE-19/20), `estado_incierto` como flag con reconsulta de la lectura companion (D-FE-22), validación cliente espejo del gateway (D-FE-23), tarjeta de éxito + dos familias de error (D-FE-25). Se corrigió un bug de `useEnviar` bajo **React.StrictMode** (el ref `montado` quedaba en `false`; L-FE-03). Validado por bloque con `typecheck`+`build` **EXIT 0** (módulos 107→115→116→117→118); **B5 con QA TEST OK por rol** (jenny no ve/no accede + gateway `rol_no_permitido`; vicky/socio cobran) **y funcional** (efectivo / transferencia bancaria / MP / otros / mixto / saldada / sobrepago bloqueado en UI / conflicto por saldo stale / retry idempotente / edición = key nueva). **Decisiones D-FE-19…28; lecciones L-FE-03…07.** **Sin cambios en backend, gateway `portal-api`, wrapper n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1** (las escrituras consumen el gateway vía `action`; el contrato A10-MP backend ya estaba cerrado y validado en TEST — `A10MP_CIERRE.md`). Pendientes: el **deep-link "Ver detalle" A12→A05 por `?id_reserva`** quedó **no implementado** (en B5 solo se hizo el deep-link A12→A10); **P-FE-02** (anti-sobrecobro) cubierto para el **portal interno A10-MP**, con web pública / Mercado Pago / flujo autónomo aún pendientes. Próxima etapa: **sub-slice 3 — QA/UAT por rol** (pruebas sobre TEST con Jenny / Vicky / socios); recién después se evalúa la **promoción coordinada del Carril C a OPS**. En paralelo, fuera del portal interno, quedan el **frente de pagos autónomos** (MP Checkout Pro, en diseño) y las **UX diferidas** (`Pendiente_pre_produccion.md`, p. ej. P-FE-08 "Ver detalle"). Cierre: `FRONTEND_SUBSLICE2_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Frontend TEST · sub-slice 1 (las 8 lecturas)** — **cerrado 2026-06-24**. Sobre el shell del sub-slice 0 se construyeron las **8 pantallas de lectura** del portal (cero escrituras): **A03/A04** calendarios (HTML en `<iframe srcDoc>` `sandbox="allow-same-origin"` sin `allow-scripts`; A04 apila meses vía shim CSS + autosize, D-FE-14), **A05** detalle de reserva (buscador + pagos + notas), **A06** prereservas activas, **A12** saldos a cobrar (con columna `Reserva #id`), **A24** histórico de reservas (filtros nativos check-in/cabaña/estado/texto + paginación server-side), **A25** ingresos cobrados y **A13** gastos (selector de mes con floor 2026-07-01 + agregados + paginación). Stack: **React 18 + Vite + TypeScript estricto + Tailwind 3 + Supabase JS solo auth/sesión + `callPortal`**; router `react-router-dom` v6 con la URL como fuente (D-FE-12), hook único **`useAction`** (D-FE-13), **`DataTable`/`Paginador`** compartidos con paginación `limit`/`offset` (A24/A25 por `total`, A13 por `Σ por_clase.n`, D-FE-15), filtros con floor y `CABANAS_TEST` **solo TEST** (→ **P-FE-01**, D-FE-16), **`RutaProtegida`** por `action` (D-FE-17) y componentes de presentación en `src/ui/` (`Money` nunca /100, D-FE-18). Durante la integración se aplicó un **parche de consistencia A04/A12** en el backend n8n (A04 recomputa `saldo_real` con el criterio de A12; display clampeado a `$0`; notas operativas; **D-C-61/62/63**) y se resolvió la visibilidad de notas (visibles para vicky/socio, no jenny ni web pública). Validado en local contra TEST con evidencia visual y **por rol** (jenny solo ve el calendario de limpieza; vicky/socios ven todo); build verificado (`tsc` + `vite build` exit 0). **Lecciones L-FE-01/02**. **Sin cambios en OPS ni `6B_SCHEMA_SQL.md` v1.8.1** (las pantallas consumen `portal-api` vía `action`; el único toque de backend fue el parche A04/A12 sobre el wrapper n8n de TEST). Pendientes: **P-FE-01** (catálogo de cabañas antes de OPS), **P-FE-02** (anti-sobrecobro en A10/web/MP) y UX diferidas (ver `Pendiente_pre_produccion.md`). Próxima etapa: **pantallas de ESCRITURA** (A07/A08/A10/A11). Cierre: `FRONTEND_SUBSLICE1_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Frontend TEST · sub-slice 0 (shell)** — **validado en TEST 2026-06-23**. Primer **código de frontend** del Carril C: el **shell del Portal Operativo** (`apps/portal-operativo/`; React + Vite + TypeScript estricto + Tailwind, Supabase JS **solo** para auth/sesión, `callPortal` propio con `fetch` que **ramifica por `body.ok`**). Cubre **login/logout + persistencia/autorefresh** de sesión, llamada de bootstrap a **`sesion.contexto`** (A02) → estado `{nombre,rol,acciones}`, **menú por rol armado desde `acciones`** (no hardcodeado, D-FE-09), **placeholder por acción** y **`no_autorizado` → re-login**; cero pantallas reales todavía. Validado en local contra TEST con **evidencia visual**: franco (Socio) y vicky (Operación) → menú completo (12 ítems / 5 grupos), jenny (Limpieza) → **solo** Calendario de limpieza (la exclusión económica **D-C-03** se sostiene **desde el backend** vía `acciones`); login, error de credenciales, logout y **persistencia tras refresh** OK; **consola sin errores de app** (el ruido trazaba a una extensión del navegador, **L-FE-01**). Build verificado (`tsc` + `vite build` exit 0). **Decisiones D-FE-09/10/11; lección L-FE-01.** **Sin cambios en backend, n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1**: el frontend solo consume `portal-api` vía `action`; Claude escribió la fuente y Franco la ejecutó/probó (regla de ejecución intacta). Pendiente: **P-C-7** (CORS al origin real; hoy `*` no bloquea `localhost:5173`). Próxima etapa: **sub-slice 1 — pantallas de lectura** (A03/A04 render del HTML temporal; A05/A06/A12/A24/A25/A13 JSON estructurado; router). Cierre: `FRONTEND_SUBSLICE0_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Contrato Frontend ↔ Portal v1** — **aprobado 2026-06-22**. La **especificación de consumo del gateway `portal-api` desde el navegador** (API reference del portal): cubre las **13 acciones** realmente construidas y verificadas en TEST (CATALOG 13 = 1 Edge + 8 lecturas + 4 escrituras), reflejando el **gateway real de Slice 3b** (no la documentación). Reglas estructurales: **transporte dual de `idempotency_key`** (A10 dentro de `payload`; A11 sibling top-level; A07 sin key —el wrapper deriva idempotencia interna, `idempotent_match` en la respuesta—; A08 sin key, guard por `conflicto`); **calendarios A03/A04 = HTML temporal** `data:{formato:"html",html}` (contrato JSON formal = P-C-3, post-MVP); **ramificación por `body.ok`, no por status HTTP** (HTTP 200 + envelope para todo resultado manejado; solo 500 = crash de infra; **no hay 401**); **`estado_incierto` en escritura → reconsulta de la lectura companion**, nunca retry ciego; **errores en dos familias** (alcanzables por frontend / canal n8n "no debería pasar"); menú por rol vía `sesion.contexto`. **Decisiones D-FE-01…08** (namespace propio, no se mezcla con `D-C-XX`). **Sin cambios en backend, n8n, OPS ni `6B_SCHEMA_SQL.md` v1.8.1**: solo diseño/documento. Pendientes anotados: CORS al origin del portal (**P-C-7**, hoy `*`), origin del frontend TEST (`<ORIGIN_PORTAL_TEST>`), valor real de la anon key, preparación/reset de TEST para UAT (etapa separada). Próxima etapa: **Frontend TEST** (sub-slices: shell de auth + `sesion.contexto` + menú por rol → pantallas de lectura → pantallas de escritura → QA/UAT por rol). Documento: `CONTRATO_FRONTEND_PORTAL_v1.md` (`Docs/Implementacion/Carril_C/Portal_Frontend/`). Cierre: `CONTRATO_FRONTEND_PORTAL_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Slice 3b (gastos: A11 carga + A13 listado)** — **cerrada en TEST 2026-06-22**. El **gasto interno** del portal, con dos acciones companion sobre `gastos_internos`, cada una por **wrapper n8n directo y por gateway** `portal-api` (JWT): **A11** `cargar.gasto_interno` —la **primera escritura no-idempotente** del portal— carga un gasto detrás de un guard de **dos capas en UNA transacción** dentro de `portal_cargar_gasto_interno` (capa 1 anti-replay de `nonce` con `UNIQUE(nonce)`, el `nonce` **derivado de la firma HMAC** del sobre, nunca del cliente; capa 2 idempotencia de negocio `UNIQUE(action,idempotency_key)` con comparación de `payload_norm`+`actor`: mismo → `ok` idempotente; payload distinto → `payload_mismatch`; actor distinto → `actor_mismatch`); el `actor` y el `source_event` los **deriva la función** server-side, las **18 constraints** de `gastos_internos` son el gate de coherencia, y el `idempotency_key` viaja **sibling de `payload`** firmado **top-level** vía un param **opcional aditivo** que deja byte-idénticos los sobres de las 11 acciones previas (D-C-57); vicky/socio. **A13** `gastos.listado` —lectura companion por **período contable**— es `SELECT` inline (universo filtrado completo en SQL, agregados en centavos y paginación en el render), **sin** `injectActor` ni `isWrite`: los bordes de período se **truncan a primer día de mes** antes del clamp y del check (D-C-59), con `periodo_hasta` híbrido, y el **gateway espeja esa semántica mensual** (D-C-60) incluida la precisión `null == omitido` (paridad con el wrapper directo; A25 mantiene su semántica estricta de `null`, **D-C-54 sin reabrir**); vicky/socio. La **infra de idempotencia** (`portal_idempotencia` —`UNIQUE(nonce)` anti-replay + `UNIQUE(action,idempotency_key)` + FK RESTRICT a `gastos_internos` + 7 CHECK— y `portal_cargar_gasto_interno`) es **TEST-only, FUERA del canónico** (precedente `portal_usuarios`, D-C-34); `gastos_internos` se usa tal cual (sin `source_event`, sin DDL). El gateway `portal-api` impone **allowlist doble** (D-C-39) + **action binding** (D-C-41); su CATALOG quedó con **13 entradas** (1 Edge + 8 lecturas + 4 escrituras). Validación empírica **por capa**, los cuatro caminos: A11 directo **38/38** (seguridad con `secWrites=0` + funcional con replay/retry/doble-click/conflictos: `nonce_replay`/`payload_mismatch`/`actor_mismatch`) + gateway **24/24** (spoof de control en payload y top-level + regresión `conflicto`≠`estado_incierto`) + teardown FK-safe (0 residuos, fixture 9F intacto); A13 directo **32/32** + gateway **34/34** con **cruce al centavo** (`total_gastos=335000.00`, `n=5`, particiones que cierran) y la **paridad ejecutable gateway↔wrapper 24/24** (GP mismo-mes + P-null `null==omitido`). **Cumple P-C-9 en TEST** (store anti-replay de `nonce` materializado en `portal_idempotencia`; su aplicación en OPS viaja en la promoción coordinada). **Decisiones D-C-55/56/57/58/59/60; lecciones L-C-20/21/22/23.** **OPS intacto; `6B_SCHEMA_SQL.md` v1.8.1 sin cambios** (A13 `SELECT` inline; A11 sin DDL canónico, la infra de idempotencia vive fuera; `portal_usuarios`/`portal_idempotencia` siguen TEST-only). Próxima etapa: **promoción coordinada del Carril C a OPS** (cuando cierren todas las slices del MVP) o slices societarias siguientes (A14–A23, post-MVP). Cierre: `C_SLICE3B_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Slice 3a (lecturas nuevas)** — **cerrada 2026-06-20**. Las **dos primeras lecturas nuevas** del portal sobre **TEST** (las de Slice 1 eran *reuse*): A24 `historico.reservas` (buscador operativo de reservas; floor inferior **duro** 2026-07-01 que el gateway recorta —no rechaza— e impuesto además en SQL con `GREATEST`; `fecha_hasta` default `null` = sin cota → incluye futuras; `id_cabana`/`estado` ausente o `null` = todas/todos **sin sentinela**; `saldo_real` por la **CTE de A12** desde `reservas.id_pre_reserva` —puede ser negativo (sobrecobro)—; devuelve `id_cabana` + `cabana`; sin DNI ni notas; vicky/socio) y A25 `ingresos.cobrados_periodo` (caja percibida por período; `total_cobrado` **solo `sena`+`saldo` confirmados**, bucket por mes de `created_at`; **suma sobre `pagos`** —incluye el residuo, `cabana` por LEFT JOIN—; `otros_movimientos` extra/ajuste/reembolso **informativo, jamás sumado**; `periodo_hasta` **híbrido** —omitido→hoy sin check de inversión (con floor futuro, hoy da vacío `ok:true`); explícito→YMD y `≥ periodo_desde` tras el clamp, sino `payload_invalido`—; `filas` paginada (agregados del universo completo); vicky/socio). Cada acción es un **wrapper n8n firmado** que revalida cinco dimensiones (HMAC sobre raw body + `ts` ±300 s + rol + **action binding** + `ambiente`), escrita como **`SELECT` inline** (sin funciones nuevas, sin DDL, canónico intacto); **no** lleva `injectActor` ni `isWrite` (lecturas). El gateway `portal-api` impone **allowlist doble** (D-C-39) + **action binding** (D-C-41); su CATALOG quedó con **11 entradas** (1 Edge + 7 lecturas + 3 escrituras). En A25, el validador `payloadIngresosPeriodo` **preserva la ausencia real de `periodo_hasta`** (omitido no va en el `value` firmado → el wrapper defaultea a hoy) para **no cambiar la semántica entre gateway y directo**. Validación empírica **por capa**, cruzando los agregados contra el snapshot read-only S8/S9 **al centavo**: A24 directo **26/26** + gateway **23/23**; A25 directo **26/26** + gateway **24/24** (`total_cobrado=921200`; por_mes julio 670200 / nov 251000; por_medio efectivo 300200 / transferencia 621000; extra 8500 separado; cuadre cerrado; **regresiones del híbrido en verde**: default `{}` vacío + `periodo_hasta` omitido **preservado**, inversión explícita y `null` explícito → `payload_invalido`). **Decisiones D-C-52/53/54; lecciones L-C-18/19.** **OPS intacto; `6B_SCHEMA_SQL.md` v1.8.1 sin cambios** (A24/A25 son `SELECT` inline; `portal_usuarios` sigue TEST-only). Próxima etapa: **Slice 3b** (gastos A11 `cargar.gasto_interno` / A13 `gastos.listado`; A11 = primera escritura candidata a **no-idempotente sin guard** → ahí entra el store de `nonce` P-C-9). Cierre: `C_SLICE3A_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Slice 2 (escrituras reuse)** — **cerrada 2026-06-20**. Las **tres primeras escrituras operativas** del portal sobre **TEST**: A07 `reserva.crear_manual` (crea reserva reusando `crear_prereserva`/`registrar_pago`/`confirmar_reserva` de 8B; vicky/socio), A08 `bloqueo.crear_manual` (reusa `crear_bloqueo` de 8D, `id_cabana` obligatorio —bloqueo total no se expone, 8D—; vicky/socio) y A10 `cobranza.registrar_saldo` (registra un pago `tipo='saldo'` reusando `registrar_pago`/`abortar_si_falla` de 9B; vicky/socio). Cada acción es un **wrapper n8n firmado** que revalida cinco dimensiones (HMAC sobre raw body + `ts` ±300 s + rol + **action binding** + `ambiente`), **inyecta el actor server-side** desde el JWT (`actorCoherente`; nunca del payload → el reject-unknown bloquea el spoof) y reusa funciones del motor existentes, sin invocar los webhooks viejos (8B/8D/W09). El gateway `portal-api` impone **allowlist doble** (D-C-39) + **action binding** (D-C-41) y, por ser escrituras, lleva `isWrite` (dispatch no confiable → `estado_incierto`, no `error_entorno`); su CATALOG quedó con **9 entradas** (1 Edge + 5 lecturas + 3 escrituras). Hitos: primera escritura vía gateway (A07, actor inyectado verificado en base), primer write transaccional con lock (A10: `pg_advisory_xact_lock` por `id_reserva` + dos sentencias con snapshot fresco que impiden el doble cobro, D-C-50), modelo de error de dos capas (etiquetas internas → allowlist, sin códigos crudos, D-C-51). Validación empírica **por capa** (batería directa + batería vía gateway por acción), con el **assert de regresión obligatorio de A10 corrido end-to-end** (SOBREPAGO → `conflicto`, nunca `estado_incierto`): A10 gateway **9/9** precheck + **9/9** smoke + verif con actor inyectado (vicky/franco) + gate post limpio; A10 directo **33/0** seguridad + **11/0** funcional + **7/0** concurrencia (no-sobrepago demostrado); A07/A08 cerrados previamente (directo + gateway), incorporados por referencia a sus runsheets. **Decisiones D-C-50/51; lecciones L-C-16/17** (A07/A08 no agregaron). **OPS intacto; `6B_SCHEMA_SQL.md` v1.8.1 sin cambios** (las tres escrituras reusan funciones del motor; `portal_usuarios` sigue TEST-only). **W09 sigue INACTIVO** hasta decisión posterior; el wrapper A10 directo queda **ACTIVO** (el gateway lo necesita para despachar). Próxima etapa: **Slice 3a** (lecturas nuevas A24/A25) / **Slice 3b** (gastos A11/A13). Cierre: `C_SLICE2_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Slice 1 (lecturas reuse)** — **cerrada 2026-06-18**. Las **cinco primeras lecturas operativas** del portal sobre **TEST**: A03 `calendario.limpieza` (HTML; jenny/vicky/socio), A04 `calendario.operativo` (HTML 120 días con montos; vicky/socio), A05 `reserva.detalle` (JSON `data:{reserva,pagos}`, primera acción con payload `id_reserva` vía `queryReplacement`; vicky/socio), A06 `prereservas.activas` y A12 `cobranza.saldos` (JSON `data:{filas}`; vicky/socio). Cada acción es un **wrapper n8n firmado** que revalida cinco dimensiones (HMAC sobre raw body + `ts` ±300 s + rol + **action binding** + `ambiente`) y reusa lógica/vistas/queries existentes, sin invocar los webhooks viejos (D-C-36). El gateway `portal-api` impone **allowlist doble** (CATALOG + wrapper, D-C-39) y **action binding** (key == `EXPECTED_ACTION`, D-C-41); su CATALOG quedó con **6 entradas** (1 Edge + 5 n8n). Hitos: primer `rol_no_permitido` real (jenny rebota en el gateway antes de firmar, sin tocar n8n), primera acción con payload (A05), primeros contratos JSON de lista (`filas:[]` ≠ `no_encontrado`, D-C-47). Validación empírica **por bloque** (smoke directo por wrapper + smoke vía gateway por cableado), 11 bloques; A12 ejerció el camino poblado con 3 saldos reales en TEST. **Decisiones D-C-36…D-C-49; lecciones L-C-10…15.** **OPS intacto; `6B_SCHEMA_SQL.md` v1.8.1 sin cambios** (las cinco lecturas son read-only sobre el schema existente; `portal_usuarios` sigue TEST-only). Próxima etapa: **Slice 2** (escrituras reuse A07/A08/A10). Cierre: `C_SLICE1_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / **Slice 0 (espina de seguridad)** — **cerrada 2026-06-16**. Primera **construcción** del Carril C sobre **TEST**: la frontera de confianza completa del portal, end-to-end. Tres piezas en TEST: (a) tabla **`portal_usuarios`** (identidad→rol `jenny`/`vicky`/`socio`, interna: REVOKE a `anon`/`authenticated`, SELECT solo a `service_role`, invisible al Data API — D-C-34; 5 usuarios sembrados por email vía Supabase Auth); (b) Edge Function **`portal-api`** (gateway/BFF, `verify_jwt=false`, flujo JWT→`getUser`→lookup rol→allowlist rol×action→dispatch; `sesion.contexto` resuelta íntegra sin n8n; helper HMAC listo pero aún sin acción que lo use); (c) workflow n8n **`portal-probe-ambiente`** que **revalida** HMAC sobre el **raw body** + ventana `ts` ±300 s + `configuracion_general('ambiente')` (segunda defensa). Validación empírica: **6/6 smokes** de `portal-api` (rol por usuario; sin-JWT / JWT inválido → `no_autorizado`; acción desconocida → `accion_desconocida`) y **4/4 casos** del probe (firma válida + ambiente test → `ok`; firma mala → `firma_invalida`; ts viejo → `ts_fuera_de_ventana`; `ambiente_esperado=ops` contra TEST → `ambiente_incorrecto`, **OPS intacto**). El caso 1 del probe cerró la salvedad de D-C-29: el HMAC sobre **bytes literales** validó byte a byte en n8n (sin fallback de JSON canónico). **Decisiones D-C-29…D-C-35; lecciones L-C-05…09.** **OPS intacto; `6B_SCHEMA_SQL.md` v1.8.1 sin cambios** (`portal_usuarios` es TEST-only, no entra al canónico hasta una eventual promoción coordinada). Secreto `VITA_HMAC_SECRET` de TEST **rotado** 2026-06-16. Próxima etapa: **Slice 1** (lecturas reuse A03/A04/A05/A06/A12). Cierre: `C_SLICE0_CIERRE.md`.

**Etapa previa:** Reconstrucción de DEV desde v1.8.0 — **cerrada 2026-06-15**. DEV se reconstruyó **desde cero** en un proyecto Supabase **nuevo** (`VITA_DELTA_DEV`, `DEV_REF=wsrdzjmvnzxidjlovlja`, sa-east-1, PostgreSQL 17.6), bootstrappeando el canónico `6B_SCHEMA_SQL.md v1.8.0` (Parte B + Parte C), **creado cerrado como OPS** (Data API ON, "Automatically expose new tables" OFF, "Enable automatic RLS" OFF) y **sin copiar datos** de OPS/TEST. Validado al bootstrap: base con paridad 8A (2 ext, 4 enums, 20 tablas, 6 vistas, 13 funciones del motor, 13 triggers, 2 EXCLUDE; seed 5/3/10/1/1/1; 2 jobs `pg_cron`) y Carril B completo (9 tablas, 21 funciones, 10 triggers de inmutabilidad, 6 secuencias; seam 5/5; matriz julio=378 / noviembre=456; reparto Σ exacto; `ambiente='dev'`; secuencias en 1). **Hallazgo:** un bootstrap fresco de v1.8.0 deja las **13 funciones del motor PUBLIC-ejecutables** (NULL-acl) porque PARTE B no incorpora el REVOKE del motor (solo C12 endurece el Carril B); se aplicó el REVOKE (espejo de 7E/8A, gate `ambiente='dev'`) → **0 expuestas**. Registrado como **gap del canónico** y **canonizado en v1.8.1** (Bloque 23). **D-RDEV-01..06 / L-RDEV-01..04**. **OPS y TEST intactos**; **DEV viejo conservado congelado**. Cierre: `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md`.

**Etapa previa:** Carril C — Portal Operativo Interno / Backend-API (diseño) — **cerrada 2026-06-15**. Etapa de **diseño puro** del backend/API del Portal Operativo Interno: catálogo cerrado de **25 acciones** (A01–A25) por módulo/rol, **matriz rol×endpoint** (`jenny`/`vicky`/`socio`), **modelo mínimo de identidad y frontera de confianza** (Supabase Auth + tabla `portal_usuarios` + una **Edge Function `portal-api`** como gateway/BFF que firma **HMAC** a n8n y valida `configuracion_general('ambiente')`; el navegador nunca llama directo a n8n para acciones sensibles), **andamiaje de contrato** con respuesta `{ok,data}` y **contrato de error uniforme**, **alcance MVP por slices** (Slice 0 espina de seguridad → 1 lecturas reuse → 2 escrituras reuse → 3a histórico+ingresos → 3b gastos; menor operable = Slice 0 + A03) y **estrategia de pruebas en TEST** (escrituras aislables/reversibles, sin contaminar el arranque contable de julio, bordes de rol/HMAC/ambiente/idempotencia). Identidad = persona, no rol (`creado_por`=`vicky`/`franco`/`rodrigo`/`remo`). **Decisiones D-C-01…D-C-28; lecciones L-C-01…04.** **NADA construido** (sin workflows, sin Edge Function, sin código, sin `portal_usuarios`); **OPS intacto**; **schema intacto** (`6B_SCHEMA_SQL.md` **v1.8.0 sin cambios, sin bump** — Carril C no introduce DDL). Carril **independiente del Carril B**; no reabre 9C→9H. Cierre: `CARRIL_C_BACKEND_API_DISENO_CIERRE.md`. **Próxima etapa: construcción de Slice 0 sobre TEST** (`KICKOFF_CARRIL_C_SLICE_0_TEST.md`).

**Etapa previa:** Promoción del Carril B a OPS + canónico **v1.8.0** — **cerrada 2026-06-14**. El Carril B completo (9C→9H + helper 9B) fue **promovido a OPS** en una operación coordinada bloque por bloque (junio 2026), **por DDL y sin copiar datos de TEST**: 9 tablas + 2 columnas en `cabanas` + 21 funciones + 10 triggers de inmutabilidad + 6 secuencias + marcador `ambiente='ops'`. **Paridad estructural TEST↔OPS certificada por huella** (`TOTAL_CARRIL`, 31 objetos, idéntica: `f5187092083451ceb5b182334bdb4a17`), **cero exposición** a la Data API (REVOKE total sobre tablas/secuencias/funciones, sin RLS), **smokes read-only 18/18** en OPS (tablas 9H vacías + secuencias en 1: la primera liquidación real arranca en 1) y el **workflow de cobranza posterior** (`vita_w09_cobranza_posterior`, 14 nodos) + listado de saldos **andando en OPS**. El canónico `6B_SCHEMA_SQL.md` quedó **bumpeado a v1.8.0** (sección 24 conceptual + PARTE C ejecutable C0–C14 con cuerpos post-K1 + changelog), **autocontenido** y verificado en bootstrap fresco (9 tablas, 21 funciones, 10 triggers, seam 5/5, matriz 378/456, reparto Σ exacto). Decisiones de promoción **D-PROMO-01..13** (en `DECISIONES_NO_REABRIR.md`); lecciones **L-PROMO-01..08** (en `Lecciones_Aprendidas.md`). **DEV quedó fuera del alcance** de esta promoción; **se reconstruyó posteriormente desde cero a partir de v1.8.0** (cerrada 2026-06-15; ver `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md`). Cierre: `PROMOCION_CARRIL_B_OPS_CIERRE.md`. No reabre 9C→9H (conservan su numeración `D-9x`).

**Etapa previa:** 9C→9H / Carril B — **contabilidad operativa interna completa (capa derivada 9C–9G + capa con estado 9H). Cerrada y validada en TEST** (9F 2026-06-10; 9G 2026-06-11; 9H 2026-06-12); luego **promovido a OPS** (junio 2026; promoción coordinada única por DDL, sin copiar datos de TEST — ver `PROMOCION_CARRIL_B_OPS_CIERRE.md`). En seis sub-etapas aditivas se construyó: **9C** — catálogo enriquecido (`cabanas.valor_relativo` NUMERIC(6,2) + `cabanas.id_socio_beneficiario` NOT NULL FK RESTRICT), `zonas` + `cabana_zona` (grandes/chicas) y el seam `resolver_beneficiario(id_cabana, fecha)` (fecha incluida e ignorada en el MVP: la costura de la titularidad temporal futura), más el marcador `configuracion_general('ambiente','test')` como gate anti-OPS (D-9C-19) y el prerequisito `Socio 3`→`Remo` (D-9C-21). **9D** — tabla `activaciones_operativas` (rangos `[)` DATE con EXCLUDE gist por cabaña; `fecha_hasta NULL` = abierta; desactivar = hueco) y pool real D-9D-10: Bamboo/Madre Selva/Arrebol/Tokio desde 2026-07-01, **Guatemala desde 2026-11-01**. **9E** — funciones read-only `matriz_participacion` / `repartir_por_matriz` / `detalle_participacion` (matriz derivada, jamás persistida; "cubre el mes completo" vía `@>`; centavo residual D-9E-08: mayor participación, empate del máximo a Rodrigo si está, sino menor id). **9F** — tabla `gastos_internos` (17 columnas, 18 constraints nombradas; la clase A/C/D/E define momento de cascada y alcance por CHECK; `clase_sugerida` + override derivado con comentario obligatorio; `periodo` normalizado a día 1; pagador socio|caja; la `gastos` legacy quedó congelada e intacta — D-9F-01) con fixture técnico de 5 gastos (ids 30–34). **9G** — la **cascada de liquidación read-only de 11 pasos** en seis funciones `LANGUAGE sql STABLE SECURITY INVOKER` (`cascada_periodo`, `saldo_socios_periodo`, `incidencia_gasto`, `reporte_overrides_periodo`, `reporte_5_vs_fiscal_periodo`, `gastos_sin_incidencia_periodo`), que derivan la liquidación mensual completa **sin persistir nada**: % operativo como parámetro explícito con guard de inválido (D-9G-01), **criterio de caja percibida** (D-9G-03: período = mes de `created_at`; devengado descartado; cobros pre-arranque quedan visibles y sin repartir), `GREATEST(base,0)` solo en el paso 4 (D-9G-07: signo sin clamps debajo), incidencia no derivable reportada sin restar (D-9G-06), expansión D por activas de zona con residual interno (D-9G-05), `desembolsado_periodo` informativo (D-9G-09: desembolso ≠ incidencia, la compensación es 9H). Validación 9G en cinco bloques verdes: A diagnóstico (28 OK; foto de 26 pagos reales), B v2 seed de 5 pagos —único write de la etapa— con 9 gates que pinearon la foto (RUN 0 diagnóstico + WHERE atómico), C v2 DDL en 10 runs con gate `DO+RAISE` de ambiente, **D 40/40** reproduciendo el ejemplo canónico al centavo (julio @0.25: base de ganancia $456.150; Remo $154.800,80; Franco/Rodrigo $120.674,60; agosto: E patrimonial de Guatemala desactivada → Franco −$180.000; noviembre: empate de matriz a Franco por menor id + D de zona; junio: **anomalía de arranque real**, $1.345.000 percibidos con pool vacío y pasos 9–11 sin filas), y E no-regresión 13/13. Los fixtures 9F+9G quedan como **banco conjunto de laboratorio hasta 9H** (D-9G-13: fixture técnico, no datos reales; distorsionan saldos derivados de las reservas 5/6/7/10 mientras existan; **no viajan a OPS**; DELETEs documentados sin ejecutar). **9H** — la **capa con estado** (cuenta corriente interna): cinco tablas append-only (`liquidaciones_periodo`, `liquidacion_cascada`, `liquidacion_socio`, `movimientos_socio`, `revaluaciones`) con inmutabilidad por 10 triggers y cadena de supersesión lineal (re-snapshot sin borrar; una raíz y una sola vigente por período), más nueve funciones (cuatro de lectura `STABLE` + cinco de escritura solo-INSERT con advisory locks) que **congelan** la foto de 9G, llevan el **mayor de movimientos** (retiros/ajustes/reversas/retribución operativa) y la **revaluación ARS→USD**; el **saldo vivo es derivado** (D-9H-12: `saldo_final + desembolsado_periodo + Σ movimientos`, nunca almacenado; columnas separadas, suma solo en la función). Validación 9H en seis bloques verdes (A0 + B estructura + C funciones + C.3 smokes 20/20 + D carga + E 38 OK), reproduciendo al centavo los canónicos de 9G una vez congelados (julio/agosto/noviembre) y los saldos vivos finales (Franco $24.158,16 · Rodrigo $351.957,49 · Remo $213.284,35), con el mayor de Rodrigo cerrando en $351.957,49 (retiro de $50.000 adentro) y la revaluación de $30.000 → US$30,00 ligada al retiro sin alterar el saldo vivo. La capa es inmutable: limpieza por **teardown DROP** (D-9H-20), nunca DELETE. Decisiones D-9C-14..21 / D-9D-01..10 / D-9E-01..08 / D-9F-01..21 / D-9G-01..14 / D-9H-01..38; lecciones L-9C-01..03, L-9D-01, L-9E-01, L-9F-01..04, L-9G-01..04, L-9H-01..04. Cierres: `9C_CIERRE.md`, `9D_CIERRE.md`, `9E_CIERRE.md`, `9F_CIERRE.md`, `9G_CIERRE.md`, `9H_CIERRE.md`. La promoción a OPS y el bump del canónico a **v1.8.0** se completaron (junio 2026; GRANTs/RLS cerrados sin exposición — ver `PROMOCION_CARRIL_B_OPS_CIERRE.md`). Las dos decisiones de negocio que quedaban servidas se cerraron (2026-06-14): **% operativo = 25%** (sobre ingresos cobrados del período menos gastos operativos) e **inicio contable del Carril B = 2026-07-01** (sin arrastre ni liquidación de meses anteriores; pre-julio fuera de alcance) — ver D-NEG-01 / D-NEG-02 en `DECISIONES_NO_REABRIR.md`.

**Etapa previa:** 9B / Fase 3b — Cobranza posterior multi-porción. **Cerrada y validada en TEST** (2026-06-07); **no promovida a OPS** (promoción diferida con aprobación explícita). Es la primera fase de la Etapa 9 que **escribe pagos** (9A diagnóstico y 3a-v2 listado eran read-only). Se construyó la capa de cobranza del saldo posterior a la confirmación: formulario n8n (Basic Auth, `active=false`) con hasta **tres porciones simultáneas** (efectivo / transferencia bancaria o MP / "otros" en equivalente ARS) y **recargo 5% interno** sobre la porción de transferencia, registrado como línea `tipo='extra'` separada, marcada `recargo_5_saldo_transferencia`, que **no reduce** el saldo de alojamiento (el saldo baja solo por líneas `tipo IN ('sena','saldo')`). Núcleo transaccional **todo-o-nada** (D-9B-19): `queryBatching: transaction` + helper SQL `public.abortar_si_falla(jsonb)` (aditivo, creado **solo en TEST**) que convierte cualquier pago no confirmado en excepción P0001 y revierte el evento completo; éxito operativo = `ok=true AND estado='confirmado' AND warning IS NULL` (coherente con D-8B-15). La cadena (N1 form → N2 saldo real → N3 validación + armado de `lineas[]` + `source_event` único → N4 resumen → N4.5 expansión a N ítems → N5 registro transaccional `abortar_si_falla(registrar_pago(...))` → N6 verificación posterior con recálculo de saldo desde la base → N6b control → N7 éxito / N8a error transaccional / N8b error de verificación / N9 error de negocio) se generó con script Python y **verificador estructural (34 controles, 34/34)**; Franco la importó manualmente (Claude no operó la instancia). Validación TEST: batería de 9 smokes + pago parcial + **rollback multi-línea** (0 pagos tras abort, verificado por `source_event`). El recargo 5% se comportó correctamente en los tres casos con transferencia ($8.500 sobre $170.000 / $5.000 sobre $100.000 / $1.650 sobre $33.000). Incidencias resueltas: bug de SQL en N6 (mezcla coma+`LEFT JOIN` → `invalid reference to FROM-clause entry`; corregido y blindado con un control del verificador) y aclaración `created_at`/`updated_at` vs `fecha_hora` en `pagos`. **Comportamiento conocido aceptado:** doble-mensaje N8b→N8a ante rollback (con `onError: continueErrorOutput` el nodo transaccional dispara ambas salidas; cosmético, integridad intacta; se intentó un Filter N5.5 y se revirtió). Decisiones: D-9B-19 + comportamiento conocido (resto del bloque 9B en `DECISIONES_NO_REABRIR.md`). Lecciones L-9B-01 a L-9B-05. Helper en TEST: `public.abortar_si_falla(jsonb)`. Artefactos: `cobranza_posterior_3b.json`, `generar_3b.py`, `verificar_3b.py`, templates sanitizados `vita_w09_cobranza_posterior__TEMPLATE.json` y `vita_w09_listado_saldos__TEMPLATE.json`. Documento de cierre: `9B_CIERRE.md`. No reabre 8B/8C/8D/8C-bis ni el diagnóstico 9A.

**Etapa 9 / Carril B — base conceptual (aprobada 2026-06-09; la capa derivada YA está implementada en 9C→9G, ver "Etapa actual"):** existe `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md v0.8`, **aprobado por Franco como base conceptual** (2026-06-09) para la futura etapa de diseño de schema de la contabilidad global interna. Define: cascada de liquidación en 11 pasos (ingresos → gastos Clase A → resultado operativo base → % operativo 25%/futuro ~12,5% → saldo beneficiarios → +recargos 5% → gastos Clase C → base de ganancia → reparto por matriz dinámica → gastos Clase D/E → saldo final por socio); cuatro clases de gasto A/C/D/E donde **la clase define momento de cascada y alcance juntos** (A/C generales, D zona/sector, E cabaña); **matriz dinámica por disposición** (valor relativo por cabaña, titularidad por socio, activación por período — se deriva, no se guarda); tres ejes de estado de cabaña independientes (bloqueo / activación operativa / titularidad patrimonial); estructura de gasto con clase elegida + sugerida y **override trazable** (comentario obligatorio, sin permisos duros en el MVP); tratamiento del 5% como entrada post-operativa y monotributo como gasto Clase C **sin neteo/fondo fiscal**. **Es conceptual puro: sin SQL, sin schema, sin nombres de tabla definitivos, sin funciones, sin workflows, sin tocar el canónico ni OPS.** De los cuatro pendientes que dejó para la etapa de schema: centavo residual **resuelto** (D-9E-08 / D-9G-05), valuación de hora de socio **resuelta como manual** (D-9C-03 / 9F), átomo de la matriz **resuelto: mes calendario** (9E/9G); titularidad por período tiene la costura lista (`resolver_beneficiario(id, fecha)`) y su tabla temporal queda para el futuro. `socios.porcentaje_utilidades` (33,33/33,34/33,33) queda como **legado** — superado para el reparto operativo dinámico, sin reemplazo formal aún. **Satélites propagados con el cierre de 9G** (2026-06-11) y nuevamente **con el cierre de 9H** (2026-06-12): el Carril B completo (9C→9H) quedó reflejado en este documento, `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `Pendiente_pre_produccion.md`, `CLAUDE.md` y `6B_SCHEMA_SQL.md` (este último **sin bump**: el bump consolidado del canónico se hace en la promoción coordinada a OPS).

**Etapa previa:** 8C-bis — Alerta por reserva próxima (sub-etapa, mail). Cerrada, validada en TEST con envío real y **publicada/activa en OPS** (2026-06-04). Recoge el item 3.1 de `Pendiente_pre_produccion.md` (notificación a Jennifer / equipo) y D-8C-21. Es un **sub-workflow independiente** (`vita_w8cbis_alerta__OPS`, id `fHzMFj7pGMKuYEOb`, 13 nodos) invocado desde el formulario de carga 8B mediante Execute Workflow **en rama lateral**: cuando se confirma una reserva con `fecha_checkin ∈ [hoy, hoy+7]` (TZ America/Argentina/Buenos_Aires), envía un mail de aviso al equipo operativo (Franco + Rodrigo) y a Jennifer (limpieza). **Garantía estructural:** si el mail falla, la reserva confirmada NO se ve afectada — el PUNTO EXTENSION de 8B alimenta `Build Response` (item original) y el Call (sub-workflow) en paralelo, y el Call queda como hoja sin salida; validado end-to-end en TEST con el Call pineado para fallar. **Privacidad por construcción** (D-8Cbis-05): el mail solo informa cabaña/entrada/salida y enlaza al calendario correspondiente; NO incluye montos, huésped, teléfono ni notas. **Solo lectura:** consulta una reserva por `id_reserva` (`SELECT` sobre `reservas`+`cabanas`, sin join a `huespedes`); no invoca funciones del motor ni escribe (D-8Cbis-04). Canal = mail (D-8Cbis-01, no Telegram/WhatsApp); remitente temporal = Gmail personal de Franco, migrable sin rediseño (D-8Cbis-09). Validación TEST: 6 casos de lógica con pin data (dentro/fuera de ventana, bordes hoy y hoy+7, id inexistente, entrada inválida) + envío real confirmado + aislamiento de la rama lateral demostrado. **Promovido a OPS:** sub-workflow con credencial `vita_supabase_ops`, bloque `ops` con destinatarios reales, URLs reales de calendario; enganche publicado y activo en el formulario de producción `vita_w8b_carga_reserva__OPS` (Call con `entorno: "ops"`). La **primera ejecución real** quedará registrada con la próxima reserva en ventana (Franco decidió no forzar prueba: el formulario ya opera con reservas reales). Hallazgos: el `\t` invisible heredado en un destinatario (L-8Cbis-02) y la diferencia draft vs. `activeVersion` al publicar (L-8Cbis-03), ambos detectados por lectura del JSON y resueltos antes del cierre. Decisiones D-8Cbis-01 a D-8Cbis-10; lecciones L-8Cbis-01 a L-8Cbis-03. Workflows: `vita_w8cbis_alerta__TEST` (id `TdTlv9ZhswwzijF2`) y `vita_w8cbis_alerta__OPS` (id `fHzMFj7pGMKuYEOb`, activo). Documento de cierre: `8C-bis_CIERRE.md`. No reabre los cierres de 8B, 8C ni 8D.

**Etapa previa:** 8D — Capa de bloqueos operativos (Form Trigger n8n). Cerrada, validada en TEST y **operativa en OPS** (2026-06-04). **Con 8D se cierra la Etapa 8 completa** (operación real interna: 8A entorno + 8B reservas + 8C calendarios + 8D bloqueos). Se construyó un formulario n8n (Basic Auth propia, usable desde celular) con el que Franco/Rodrigo/Vicky/Remo crean un bloqueo de una cabaña en **una sola acción**, invocando `crear_bloqueo()` (sin cadena, sin pagos, sin compensación; sin INSERT directo; sin tocar schema). El bloqueo aparece automáticamente en gris en los calendarios de 8C. Antes de construir se verificó read-only el contrato real de `crear_bloqueo`: la función valida TODO (cabaña, fechas, motivo, y los tres tipos de conflicto: reserva confirmada/activa, pre-reserva vigente, bloqueo solapado) → el formulario es solo UX + mensajería; un bloqueo NO convive con reservas (las rechaza); concurrencia ya resuelta en la función (`pg_advisory_xact_lock`); triple protección de solapamiento (chequeo + EXCLUDE parcial + `EXCEPTION`). Campos: cabaña (desplegable, nombre→id 1-5, **sin opción TODAS** — D-8D-03), fecha desde, fecha hasta/liberación (modelo `[)`, exclusive), motivo (5 valores del CHECK), descripción opcional, creado por. Manejo de errores en dos familias: conflictos unificados ("esas fechas no están disponibles", sin exponer IDs — D-8D-04/05) y errores de entrada diferenciados; mensaje de éxito en lenguaje humano (último día inclusive + día de liberación — D-8D-08). Validación funcional completa en TEST (bloqueo válido, fechas mal, conflictos, cada motivo, trazabilidad, verificación `[)`). **Promovido a OPS:** workflow `vita_w8d_bloqueo__OPS` activo y en uso real (credencial `vita_supabase_ops`, `TEST_OPS='ops'`, path `w8d-bloqueo-ops`, Basic Auth propia), primer bloqueo real creado. Incidencia resuelta clave (L-8D-01): el "Problema técnico" inicial era el nodo Normalize leyendo `item.ok` en vez de `item.resultado.ok` (el nodo Postgres envuelve el resultado de la función en la columna `resultado`); la base nunca falló. **8D SOLO CREA bloqueos**: corregir o levantar uno requiere intervención manual controlada (D-8D-09). Workflows: `vita_w8d_bloqueo__TEST` (id `GIfBlI6xCnrkH2Y4`, 9 nodos) y `vita_w8d_bloqueo__OPS` (activo). Decisiones D-8D-01 a D-8D-09; lecciones L-8D-01 a L-8D-03. Artefactos: workflows `__TEST`/`__OPS` + template sanitizado `vita_w8d_bloqueo__TEMPLATE.json`. Documento de diseño: `ARQUITECTURA_ETAPA_8D_BLOQUEOS_OPERATIVOS.md v1.1`. Documento de cierre: `8D_CIERRE.md`. Bitácora de ejecución: `8D_EJECUCION.md`.

**Etapa previa:** 8C — Calendarios visuales por evento. Cerrada en TEST (2026-06-01) y **operativa en OPS** (smoke posterior ejecutado: HTML operativo y limpieza activados en producción, en uso por el equipo). Se construyeron **tres calendarios derivados de solo lectura** desde Supabase (fuente de verdad), sin tocar schema ni funciones del motor: (1) **HTML operativo** (Franco/Rodrigo/Vicky/Remo) — grilla día×cabaña de 120 días autodesplazante con pestañas por mes, reservas confirmadas/activas + bloqueos, montos/horarios/teléfono; ventana en vivo que se arma en cada visita a la URL; (2) **HTML limpieza** (Jennifer) — grilla de 7 días, contrato reducido **sin montos**, con mascotas y notas operativas; (3) **Sheet de resguardo** — el operativo volcado a un Google Sheet como respaldo offline (foto estática regenerable, hoy por disparo manual). Los HTML se sirven por n8n Cloud con Basic Auth **separada por público** (operativo y limpieza con credenciales propias distintas, ninguna reutiliza la del formulario 8B — D-8C-20); el resguardo se escribe vía HTTP a la API REST de Google Sheets (NO Apps Script — D-8C-22). Lógica de pintado en capa de presentación: operativo **rojo > gris > verde > blanco**; limpieza **rojo > gris > amarillo (salida) > verde > blanco** (amarillo porque salida = hay que limpiar). Precisiones de render: detección de salida incluye `confirmada`/`activa`/`completada` (4ta query sobre `reservas`, ya que `vista_calendario` filtra solo confirmada/activa); bloqueo evaluado con `EXISTS` sin asumir unicidad (los totales `id_cabana IS NULL` quedan fuera del EXCLUDE); fechas normalizadas a `YYYY-MM-DD` (robustez ante timestamps). Validación funcional completa en TEST con batería sembrada y luego promoción y uso real en OPS. Workflows OPS activos (operativo y limpieza); resguardo manual. **8C-bis (alerta por reserva próxima): trabajo posterior independiente** con documento propio (no reabre el cierre); notificación a Rodrigo y Jennifer por mail o Telegram, canal a decidir. Decisiones D-8C-01 a D-8C-23. Documento de diseño: `ARQUITECTURA_ETAPA_8C_CALENDARIOS_VISUALES.md v1.3`. Documento de cierre: `8C_CIERRE.md`.

**Etapa previa:** 8B — Capa de carga interna de reservas (Form Trigger n8n). Cerrada (2026-05-30). Se construyó un formulario n8n usable desde celular (Basic Auth, `Respond When = Workflow Finishes`, `Form Ending`) que permite a Franco/Vicky/Rodrigo/Remo cargar una reserva ya cerrada en **una sola acción**, encadenando las tres puertas del motor `crear_prereserva()` → `registrar_pago()` → `confirmar_reserva()` sin INSERT directo. El operador elige cabaña por nombre (mapeo a IDs reales 1-5), carga monto total y seña (vacía/0 → 50% automático; valor explícito → se respeta), y recibe un resultado único (confirmada / error de negocio claro / revisión manual). Antes de implementar se verificaron contra OPS (read-only) los contratos reales de las 4 funciones, los CHECK de `canal_origen`/`canal_pago_esperado`/`medio_pago`/`tipo` (no son enums sino TEXT con CHECK), y la constraint **parcial** de `idempotency_key`. Hallazgos que corrigieron el diseño: `crear_prereserva` ya valida cabaña/capacidad (la capa solo hace UX temprana); `ok:true` de `registrar_pago` no garantiza pago confirmado (verificación estricta de estado + warning); `cancelar_prereserva` expone `pagos_asociados_count` para decidir el mensaje de compensación (nunca decir "revertido" si quedó pago). Validación funcional completa en TEST (happy path en ambos caminos de seña, colisión, idempotencia, validaciones de capa, compensación con pago). **Smoke OPS exitoso = primer write real del sistema:** reserva id 1 (Tokio, Paula Lugo, 06→07 jun 2026, total 150000, seña 75000, saldo 75000, `created_by`/`validado_por` = vicky, `source_event` `n8n_ops_w8b_carga_vicky_manual`). Trazabilidad multiusuario verificada en producción. Punto de extensión para el repintado de calendario (8C) marcado pero NO construido. Decisiones D-8B-01 a D-8B-21 (D-8B-12 revisada: nombre+apellido en campo único). Artefactos: workflows `__TEST`/`__OPS`/`__TEMPLATE` (sanitizado). Pendiente operativo: activar el workflow `__OPS` para uso por URL sin ejecución manual. Documento de cierre: `8B_CIERRE.md`.

**Etapa previa:** 8A — Levantamiento del entorno OPS (operación real interna). Cerrada (2026-05-29). Se creó `vita-delta-ops` (`OPS_REF=lpiatqztudxiwdlcoasv`, sa-east-1, Free tier, PostgreSQL 17.6) como tercer entorno de la estrategia DEV → TEST → OPS → PROD y **primer entorno de operación real interna** (D-8-09). Schema reconstruido desde el canónico `6B_SCHEMA_SQL.md v1.7.3` en 7 tandas (4.1-4.7), con **paridad estructural P01-P10 10/10** (2 extensiones, 4 enums, 20 tablas, 6 vistas, 13 funciones, 13 triggers, 2 EXCLUDE, 38 CHECK, 15 FK, 27 índices). Seeds reales sembrados: 5 cabañas (IDs **1-5**), 3 socios (Franco 33.33 / Rodrigo 33.34 / Remo 33.33), 10 claves de `configuracion_general` (horizonte 120), 1 cuenta de cobro real y activa (alias playario), 1 temporada baseline, 1 plantilla. Seguridad: **OPS nació más cerrado que TEST** gracias al switch "Automatically expose new tables = OFF" desde la creación — 0 funciones con EXECUTE a Data API y 0 grants RW a roles Data API sobre tablas; el `REVOKE EXECUTE` idempotente se aplicó igual como barrera explícita (Opción B). Default privileges cerrado sin ejecución (D-8-13): los defaults del rol `postgres` conceden solo `Dxtm` inocuo; los 21 defaults amplios son del rol de plataforma `supabase_admin` y no se tocan. `pg_cron` activo con 2 jobs y una corrida real `succeeded` verificada. Credencial n8n `vita_supabase_ops` creada, probada y verificada por identidad (lee las 5 cabañas reales de OPS). Verificación consolidada 17/17. Smoke de cierre solo lectura (D-8-12): el primer write real será una reserva real por 8B. Decisiones D-8-09, D-8-13 (+ confirmación de cumplimiento de D-8-03). DEV/TEST/PROD no se tocaron. Documento de cierre: `8A_CIERRE.md`.

**Etapa previa:** 7E — Endurecimiento de permisos Data API en DEV. Cerrada (2026-05-28). Se aplicó a DEV el `REVOKE EXECUTE` sobre las 13 funciones del proyecto a `PUBLIC`/`anon`/`authenticated`/`service_role`, en paridad con el modelo de TEST (7B-GRANTS), por el método de cuatro bloques separados (snapshot read-only → cambio transaccional `BEGIN/COMMIT` con re-gate anti-error-de-entorno por identidad exacta de cabañas DEV 17-21 → verificación posterior → cierre documental). Owner `postgres` intacto y ejecutando por ownership (n8n no afectado); 0 fugas de EXECUTE verificadas; schema v1.7.3 sin cambios (201 funciones / 6 vistas / 19 triggers). De las 201 funciones de `public`, solo 13 son del proyecto (las otras 188 son de `btree_gist`, owner `supabase_admin`, no se tocaron). El hallazgo A5 (residual amplio de permisos de tabla a roles Data API en DEV: SELECT/escritura completos, más amplio que el `Dxtm` de TEST) quedó **fuera de alcance por decisión** (Opción 1 — 7E estricta) y se registró como pendiente nuevo `Pendiente_pre_produccion.md` 1.7. Decisiones D-7E-01, D-7E-02. DEV es el único entorno tocado; TEST/OPS/PROD intactos. Documento de cierre: `7E_CIERRE.md`.

**Etapa previa:** 7D — Limpieza/reset del entorno TEST. Cerrada (2026-05-28). Se diseñó y ejecutó un bloque dedicado de reset con SQL explícito y aprobado, en tres partes separadas (snapshot read-only → limpieza transaccional atómica → verificación posterior), con doble gate anti-error-de-entorno por identidad exacta de las 5 cabañas TEST. Se vaciaron las 6 tablas transaccionales con datos (`pagos`, `reservas`, `pre_reservas`, `bloqueos`, `huespedes`, `log_cambios`) vía `DELETE` en orden seguro por FKs, sin `DROP/TRUNCATE ... CASCADE`, y se resetearon sus secuencias a 1. El seed estructural (11 tablas), el cron, las funciones/vistas/triggers, los grants y los workflows `__TEST` quedaron intactos. **TEST quedó como entorno limpio.** Decisiones D-7D-01 (reset de secuencias) y D-7D-02 (vaciado de `log_cambios` con evidencia documentada). DEV/OPS/PROD no se tocaron; schema canónico v1.7.3 sin modificar. Documento de cierre: `7D_CIERRE.md`.

**Etapa previa:** 7C — Validación funcional ampliada sobre TEST. Cerrada (2026-05-28). Se ejecutaron sistemáticamente los caminos no-felices de los 8 workflows `__TEST` (errores controlados, edge cases, validaciones defensivas, condiciones de borde) que 7B dejó fuera de alcance. Resultado: **54 verificaciones conformes (48 casos funcionales del Grupo A + 6 verificaciones transversales TR-01/TR-02), 0 fallos inesperados, 1 mutación no planificada pero válida y comprendida (bloqueo id 2)**. Idempotencia: ramas `post_lock` (H7) y `pre_lock` (7C) cubiertas empíricamente; `unique_violation` queda como opcional no bloqueante. DEV no se tocó durante 7C; el schema canónico v1.7.3 no se modificó.

**No es producción pública.** DEV, TEST y OPS son entornos separados: DEV (desarrollo), TEST (pruebas funcionales completas) y OPS (operación real interna, recién levantado en 8A — datos reales, sin consumidores externos automáticos todavía). Falta integración con consumidores reales (webhook MP, bot, frontend) y el entorno PROD público. El endurecimiento de DEV en EXECUTE sobre funciones quedó en paridad con TEST en 7E; resta solo el residual amplio de permisos de tabla a roles Data API en DEV (hallazgo A5, pendiente 1.7), fuera de alcance por decisión — OPS nació sin ese problema. La validación funcional ampliada sobre TEST quedó cubierta en 7C.

---

## Etapas de DISEÑO completadas

### Etapa 1 — Arquitectura base ✅ Cerrada
- Objetivo general del sistema.
- Herramientas elegidas: inicialmente Google Sheets + n8n + Apps Script, posteriormente migrado a Supabase.
- Modelo de datos lógico.
- Flujo CONSULTAS → PRE_RESERVAS → RESERVAS.
- Principios de consistencia.
- Migrabilidad a Supabase (que terminó ocurriendo).

### Etapa 2 — Motor de disponibilidad ✅ Cerrada
- Reglas de check-in / check-out base.
- Domingo como primer día con check-in 18:00.
- Escalonamiento operativo por carga de limpieza.
- Overrides operativos.
- Race conditions y revalidación antes de confirmar.

### Etapa 3 — Motor de precios ✅ Cerrada
- `fecha_in` inclusive / `fecha_out` exclusive.
- Tipos de cabaña, temporadas, multiplicadores.
- TARIFAS, jerarquía de cálculo.
- Feriados, estadías largas, personas extra, descuentos.
- Seña y saldo.
- EVENTOS_ESPECIALES (Año Nuevo fuera del motor estándar).

### Etapa 4A — Motor de Reservas Determinístico ✅ Cerrada (diseño)
- Estados de pre-reserva, reserva, pago.
- Locks y secuenciamiento.
- Idempotencia.
- Revalidación post-lock.

### Etapa 4B — Bot Conversacional con IA ✅ Cerrada (diseño)
- Reglas para que la IA no ejecute lógica crítica.
- Llamadas a workflows determinísticos cuando la IA necesite operar.
- Prompt base, caching, edge cases.

### Etapa 5 — Implementación vertical mínima ✅ Cerrada (diseño)

### Etapa 6A — Decisión de migración ✅ Cerrada
- Análisis: Google Sheets + Apps Script alcanzaban límites operativos.
- Decisión: migrar a Supabase/PostgreSQL.

### Etapa 6B — Migración a Supabase ✅ Cerrada (diseño + implementación)
- Schema completo en PostgreSQL.
- Plan de fases de ejecución.
- Schema canónico de referencia: `6B_SCHEMA_SQL.md v1.7.2` (bump documental ejecutado en H8 Frente A; ver sección "Schema canónico actual" abajo).

### Etapa 6C — Reescritura de workflows n8n contra Supabase DEV ✅ Cerrada
- 8 workflows manuales operativos en DEV.
- Documento de cierre formal: `6C_CIERRE.md`.

### Etapa 6D — Hardening pre-producción ✅ Cerrada
- 10 bloques cerrados: H1, H2, H3, H4, H4-bis, H4-ter, H5, H6, H6-bis (hardening estructural) + H7 (tests de concurrencia).
- 1 bloque pendiente: H8 (cierre documental, sin SQL).
- Documento de cierre formal: `6C_CIERRE.md`.

---

## Fases de IMPLEMENTACIÓN en Supabase DEV

**Bloques 1-22 ejecutados.** Fases 0, 1, 2 y 3 cerradas.

### Fase 1 — Schema base ✅ Cerrada
**Bloques 1-8 ejecutados:** extensiones (pg_cron, btree_gist), 6 enums, 20 tablas, todas las constraints, índices, 2 EXCLUDE constraints estructurales (uno sobre reservas, uno sobre bloqueos).

### Fase 2 — Funciones y triggers ✅ Cerrada
**Bloques 9-19 ejecutados:** 12 funciones operativas + 13 triggers automáticos.

Funciones operativas validadas end-to-end:
- `normalizar_telefono()` + trigger
- `upsert_huesped()`
- `validar_disponibilidad()`
- `obtener_disponibilidad_rango()`
- `crear_prereserva()` — **PUERTA ÚNICA** para crear pre-reservas
- `confirmar_reserva()` — ambos caminos: estricto + combinado
- `cancelar_prereserva()`
- `crear_bloqueo()` — específico + total
- `registrar_pago()` — incluyendo caso v1.3
- `expirar_prereservas_vencidas()`

Triggers:
- 1 trigger para normalización de teléfono.
- 9 triggers `BEFORE UPDATE` para `updated_at`.
- 3 triggers `AFTER UPDATE OF estado` para log automático de transiciones.

### Fase 3 — Vistas + seed operativo + pg_cron ✅ Cerrada
**Bloques 20-22 ejecutados.**

**6 vistas operativas creadas:**
- `vista_disponibilidad` (60 días forward).
- `vista_calendario` (60 días forward).
- `vista_prereservas_activas` (cronómetro en vivo).
- `vista_ocupacion` (24 meses exactos desde hardening H5).
- `vista_calendario_semanal` (7 días forward).
- `vista_limpieza_semana` (7 días forward).

**Seed operativo cargado en DEV:**
- 5 cabañas reales: Bamboo (id=17), Madre Selva (id=18), Arrebol (id=19), Guatemala (id=20), Tokio (id=21).
- 3 socios: Franco, Rodrigo, Remo.
- 1 cuenta de cobro activa cargada en DEV (datos reales omitidos por seguridad documental).
- 10 claves de configuración (incluyendo `hora_checkout_domingo` agregada por hotfix v1.7).
- 1 temporada baseline DEV (multiplicador neutro, no productiva).
- 1 plantilla de mensaje.

**2 jobs pg_cron activos:**
- `expirar_prereservas` (cada 5 min) — validado end-to-end procesando pre-reserva real.
- `cleanup_cron_history` (día 1 de cada mes a las 03:00 UTC).

### Hotfix v1.7 — Regla `hora_checkout_domingo` ✅ Aplicado en DEV
Implementa la regla operativa de check-out dominical a las 16:00 (por última lancha colectiva). Función `crear_prereserva` actualizada. 4 tests funcionales validados.

### Alineación 6B v1.7.1 ✅ Aplicada en DEV
**Pre-etapa 6C, 2026-05-25.**

Actualización de `obtener_disponibilidad_rango()` para aplicar el CASE de domingo en `hora_checkout_base`. Ejecutado con `CREATE OR REPLACE FUNCTION` sin pop-up destructivo. 5 verificaciones OK post-deploy.

**Nota histórica:** al cierre de esta alineación, DEV quedó 100% alineado con schema canónico v1.7.1. Posteriormente, durante Etapa 6D, DEV avanzó a v1.7.2 con la aplicación del hardening H2-H6-bis. La actualización del schema canónico a v1.7.2 se ejecutó posteriormente en H8 Frente A.

Documentación: `BITACORA_ENTRADA_CIERRE_6B_v1.7.1.md`.

### Etapa 6C — Reescritura de workflows n8n contra Supabase DEV ✅ Cerrada
**2026-05-25 a 2026-05-26.**

**8 workflows operativos en DEV** con 40 tests funcionales aprobados y 3 verificaciones cruzadas end-to-end:

| Workflow | Función / vista | Tests |
|---|---|---|
| W0 — smoke test | conexión Supabase | 1 query |
| W1 — consultar disponibilidad | `obtener_disponibilidad_rango(date, date, bigint)` | 4 tests
| W2 — crear pre-reserva | `crear_prereserva(jsonb)` | 5 tests |
| W3 — registrar pago | `registrar_pago(jsonb)` | 4 tests |
| W4 — confirmar reserva | `confirmar_reserva(jsonb)` | 5 tests |
| W5 — cancelar pre-reserva | `cancelar_prereserva(jsonb)` | 6 tests + 1 cruzado |
| W6 — crear bloqueo | `crear_bloqueo(jsonb)` | 8 tests + 2 cruzados |
| W7 — vistas operativas | 6 vistas read-only | 7 tests |

**Patrón establecido y reutilizable:**
Manual Trigger → Build Input → Build Payload/Query → Postgres → Build Response

Excepción: W7 incorpora nodo IF para ramificación de validación temprana.

**Convenciones consolidadas:**
- Naming workflows: `vita_w{NN}_{nombre}_supabase`.
- Templates en repo: `Workflows/n8n/supabase/<nombre>.template.json`.
- Source events: `n8n_w{NN}_{nombre}_manual`.
- Wrapper externo unificado con `ok`, `workflow`, `source_event`, `error`, `result`, `executed_at`.
- Normalización defensiva con `nv()` en Build Payload (workaround del bug de validación SQL).
- Verificación cruzada con W1 obligatoria para workflows que modifican disponibilidad.

**Documento de cierre formal:** `6C_CIERRE.md`.

### Etapa 6D — Hardening pre-producción 🚧 H1-H7 cerrados · H8 en curso

**Sesiones 2026-05-26 y 2026-05-27.** Cerrado el frente estructural (H1-H6-bis) y la validación de concurrencia (H7); pendiente cierre documental (H8).

**Bloques cerrados:**

| Bloque | Descripción | Tests |
|---|---|---|
| H1 | Decisiones previas (patrón canónico, TRIM agresivo) | n/a |
| H2 | Hardening `registrar_pago` (extract defensivo) | 15/15 |
| H3 | Hardening `confirmar_reserva` (extract defensivo) | 11/11 |
| H4 | Hardening `crear_prereserva` (extract defensivo) | 31/31 |
| H4-bis | Hardening `cancelar_prereserva` (extract defensivo) | 9/9 |
| H4-ter | Hardening `crear_bloqueo` (extract defensivo) | 17/17 |
| H5 | Fix `vista_ocupacion` (rango 25→24 meses) | 7/7 |
| H6 | Fix `vista_calendario` + `vista_limpieza_semana` (TRIM) | 7/7 |
| H6-bis | Fix `vista_prereservas_activas` (TRIM) | 5/5 |
| H7 | Tests de concurrencia C-1, C-2, C-5, C-3, C-4, C-6 | 6/6 |

**Resumen:**
- 5 funciones write con patrón `NULLIF(TRIM(...),'')` aplicado en sus extracts de payload.
- 4 vistas corregidas (1 de rango, 3 cosméticas).
- 101 tests de hardening estructural con `ok=true`.
- 6 tests de concurrencia real en DEV, todos aprobados (sin deadlocks, sin races, sin doble booking).
- Cero side effects persistentes post-cleanup: conteos finales idénticos a baseline pre-H7 (pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, logs=11).
- Schema bumped a **v1.7.2** durante H2-H6-bis (documentado en bitácora). H7 no introdujo cambios estructurales.

**Bloques pendientes:**

| Bloque | Descripción | Estado |
|---|---|---|
| H8 | Actualización documental y cierre formal de Etapa 6D | ⏳ Pendiente |

**Bitácora de ejecución:** `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` (H1-H7 documentados). Documento de cierre formal `6D_CIERRE.md`: pendiente en H8.

---

### Etapa 7B — Levantamiento del entorno TEST ✅ Cerrada

**Sesión 2026-05-28.** Cerró el segundo entorno de la estrategia DEV → TEST → OPS → PROD.

**Lo que se construyó:**
- Proyecto Supabase TEST (`vita-delta-test`, sa-east-1, Free tier).
- Schema reconstruido desde el canónico v1.7.3 (no clon de DEV). **Paridad estructural demostrada 10/10** vs DEV: extensiones, enums, tablas (20), vistas (6), funciones del proyecto (13), triggers (13), EXCLUDE (2), CHECK (38), FK (15), índices únicos (27).
- Seeds del Bloque 21 cargados: 5 cabañas, 3 socios, 10 claves de `configuracion_general`, 1 cuenta de cobro, 1 temporada baseline, 1 plantilla.
- `pg_cron` activo en TEST: `expirar_prereservas` (cada 5 min) con ejecuciones reales verificadas (`status=succeeded`); `cleanup_cron_history` (mensual).
- Permisos Data API normalizados: REVOKE EXECUTE sobre las 13 funciones a `PUBLIC`/`anon`/`authenticated`/`service_role`; `Dxtm` residual documentado como aceptado; sin grants Data API útiles para roles no-owner. Owner `postgres` intacto (n8n entra como owner por pooler).
- 8 workflows n8n importados con sufijo `__TEST` y credencial propia `vita_supabase_test`; smokes happy path 8/8.
- Cadena transaccional end-to-end **W2 → W3 → W4 validada** (pre-reserva → pago `en_revision` → reserva confirmada por camino combinado), más verificación cruzada con W1 que confirmó la transición de estado en el motor de disponibilidad.

**IDs de cabaña en TEST:** `1=Bamboo, 2=Madre Selva, 3=Arrebol, 4=Guatemala, 5=Tokio`. **No coinciden con DEV (17-21).** Los IDs no son portables; cada workflow debe usar los del ambiente al que apunta. Lo portable es la estructura lógica de los workflows, no los valores de input.

**Aislamiento:** TEST quedó separado por credencial propia (`vita_supabase_test`), workflows `__TEST` distintos (objetos nuevos en n8n, no modificaciones de los de DEV), y marcadores de ambiente en `source_event` (`n8n_test_w0X_..._manual`) e `idempotency_key` de W2 (`manual_test_...`) que se persisten en tablas y permiten trazabilidad inequívoca DEV vs TEST. DEV intacto durante toda la etapa.

**Datos de prueba en TEST tras el cierre:** pre-reserva 1 (`cancelada_por_cliente`), pre-reserva 2 (`convertida`), reserva 1 (`confirmada`), pago 1 (`confirmado`), bloqueo 1 (Arrebol activo). Conservados como evidencia/fixtures, no limpiados. Reseteo eventual de TEST se diseñará como bloque específico SQL aprobado.

**Alcance del cierre:** happy paths como evidencia suficiente. Casos de error (cabaña inexistente, solapamientos, payloads inválidos, normalización defensiva en campos vacíos, etc.) quedan como pendiente: validación funcional ampliada sobre TEST (ver `Pendiente_pre_produccion.md` 6.4).

**Documento de cierre formal:** `7B_CIERRE.md`.

---

## Estado actual de DEV (post-7A, intacto durante 7B)

**Esta es la fuente vigente del estado de DEV.** Los conteos son los mismos al cierre de 7B: 7B no modificó DEV. La única actividad en DEV durante 7B fueron consultas read-only de diagnóstico (paridad estructural y verificación del rol de conexión n8n).

| Recurso | Conteo | Detalle |
|---|---|---|
| Pre-reservas | 7 | 2 de baseline 6D (`convertida`, `cancelada_por_cliente`) + 5 de tests 7A (todas `cancelada_por_cliente`, terminales) |
| Pagos | 1 | `confirmado` |
| Reservas | 1 | `confirmada`, cabaña 17, 10-13 jul 2026 (`ninos=NULL` tras limpieza 7A) |
| Huéspedes | 3 | id 34, 35 (baseline, `apellido=NULL`) + id 45 ("Test 7A", de tests 7A) |
| Bloqueos | 2 | activos |
| Logs | 26 | en `log_cambios` (+15 vs baseline 7A: 5 creaciones + 5 cancelaciones + 5 transiciones de estado) |
| Filas con `ninos='false'` | 0 | limpieza puntual 7A (pre_reservas 25, 26; reserva 8 → NULL) |
| `configuracion_general` | 10 | incluye `horizonte_disponibilidad_dias=120` |
| `vista_disponibilidad` / `vista_calendario` | horizonte 120 | configurable vía `configuracion_general`, fallback 120 |

Los recursos de tests 7A están en estados terminales (canceladas) y no afectan disponibilidad ni operación. Las pre-reservas y el huésped de test se conservan como evidencia, no se borraron físicamente.

**Estado de DEV al cierre de H7 (histórico, pre-7A):** pre-reservas=2, pagos=1, reservas=1, huéspedes=2, bloqueos=2, logs=11. Conteos idénticos al baseline pre-H7 — confirmó cero side effects persistentes post-cleanup de la sesión de concurrencia (6 tests con fixtures multipaso, todos limpiados).

**Nota:** DEV fue limpiado entre el cierre de 6C y el inicio de 6D (huéspedes de 35→2, pre-reservas de 26→2). Esa limpieza no fue parte del hardening; quedó como contexto operativo.

---

## Estado actual de TEST al cierre de Etapa 7B

**Entorno TEST: proyecto Supabase independiente, alineado funcionalmente con el canónico v1.7.3.**

| Recurso | Conteo | Detalle |
|---|---|---|
| Pre-reservas | 2 | id 1 `cancelada_por_cliente` (ciclo W2→W5); id 2 `convertida` (cadena W2→W3→W4) |
| Pagos | 1 | id 1 `confirmado` (camino combinado de W4 desde pago `en_revision`) |
| Reservas | 1 | id 1 `confirmada`, cabaña 1 (Bamboo), 10-13 jul 2026 |
| Huéspedes | 1 | id 1 "Juan Pérez Test" (reutilizado vía upsert) |
| Bloqueos | 1 | id 1 activo, cabaña 3 (Arrebol), 20-22 nov 2026, motivo `tormenta` |
| Logs | varios | con `source_event` marcado `n8n_test_w0X_..._manual` |
| `configuracion_general` | 10 | idéntica a DEV (sembrada desde el canónico) |
| Horizonte de vistas | 120 | igual que DEV |
| Jobs `pg_cron` | 2 | `expirar_prereservas` (cada 5 min, ejecuciones reales verificadas), `cleanup_cron_history` (mensual) |

**IDs de cabaña:** `1=Bamboo, 2=Madre Selva, 3=Arrebol, 4=Guatemala, 5=Tokio`. **No coinciden con DEV (17-21).**

Datos de prueba conservados como evidencia/fixtures, no limpiados. Reseteo eventual de TEST se diseñará como bloque SQL aprobado separado, no se improvisa.

---

## Estado actual de OPS al cierre de Etapa 8A

> **Nota (junio 2026):** esta ficha es el snapshot **histórico al cierre de 8A**. OPS fue **extendido luego con el Carril B** en la promoción de junio 2026 (+9 tablas, +21 funciones, +10 triggers de inmutabilidad, +6 secuencias, +2 columnas en `cabanas`, +marcador `ambiente`), todo cerrado al Data API. Los conteos de abajo reflejan 8A, no el estado post-promoción. Ver `PROMOCION_CARRIL_B_OPS_CIERRE.md`.

**Entorno OPS (`vita-delta-ops`): proyecto Supabase independiente, primer entorno de operación real interna, paritario con el canónico v1.7.3, seguro y conectado a n8n.**

**Ficha:** `OPS_REF=lpiatqztudxiwdlcoasv` · sa-east-1 (São Paulo) · Free tier · PostgreSQL 17.6 · pooler `aws-1-sa-east-1.pooler.supabase.com:6543` · credencial n8n `vita_supabase_ops` · modelo Opción A (n8n como `postgres` por pooler, sin consumidores Data API, RLS postergado).

**Estructura (paridad P01-P10 10/10 vs canónico):** 2 extensiones (btree_gist, pg_cron), 4 enums, 20 tablas, 6 vistas, 13 funciones propias, 13 triggers, 2 EXCLUDE, 38 CHECK, 15 FK, 27 índices.

| Recurso | Conteo | Detalle |
|---|---|---|
| Cabañas | 5 | IDs **1-5**: Bamboo=1, Madre Selva=2, Arrebol=3, Guatemala=4, Tokio=5 (grandes 3/5, chicas 2/4) |
| Socios | 3 | Franco 33.33, Rodrigo 33.34, Remo 33.33 (suma 100.00) |
| `configuracion_general` | 10 | incluye `horizonte_disponibilidad_dias=120` |
| Cuentas de cobro | 1 | real y **activa**: alias playario, transferencia_mp, titular Franco Guaglianone |
| Temporadas | 1 | baseline "Baseline OPS 2026-2028" (neutra, no productiva) |
| Plantillas | 1 | `prereserva_creada` |
| Reservas / pre-reservas / pagos / huéspedes | 1 c/u | **primer write real (8B):** reserva id 1 (Tokio, Paula Lugo, 06→07 jun 2026), pre-reserva convertida, pago seña confirmado, huésped Paula Lugo. Bloqueos: 0 |
| Jobs `pg_cron` | 2 | `expirar_prereservas` (cada 5 min, 1 corrida real `succeeded` verificada), `cleanup_cron_history` (mensual) |
| Horizonte de vistas | 120 | con 5 cabañas: `vista_disponibilidad`=600 filas, `vista_ocupacion`=120, `vista_calendario_semanal`=35; vistas de reservas en 0 (sin reservas) |

**IDs de cabaña en OPS:** `1-5`. Coinciden con TEST por casualidad (ambos nacieron limpios con secuencia desde 1), pero son entornos separados — los workflows `__OPS` usan los IDs reales de OPS. En el form de carga de 8B la cabaña se elige por **nombre**, no por ID (D-8-10).

**Seguridad:** 0 funciones con EXECUTE a roles Data API, 0 grants SELECT/INSERT/UPDATE/DELETE a roles Data API sobre tablas, residual solo `Dxtm` inocuo. OPS nació más cerrado que TEST (switch correcto desde el día cero); el REVOKE EXECUTE se aplicó igual como barrera explícita (Opción B). Default privileges del rol `postgres` conceden solo `Dxtm` inocuo → objetos futuros nacen cerrados (D-8-13).

**Verificación consolidada (Bloque 9):** 17/17 checks OK.

---

## Estado histórico de DEV al cierre de 6C

**Este estado es histórico. No refleja el estado actual post-limpieza y post-hardening.** La fuente vigente es la sección anterior ("Estado actual de DEV al cierre de H7").

| Recurso | ID | Estado |
|---|---|---|
| Pre-reserva | 25 | `convertida` (terminal) |
| Pre-reserva | 26 | `cancelada_por_cliente` (terminal) |
| Pago | 11 | `confirmado`, asociado a reserva 8 |
| Reserva | 8 | `confirmada`, cabaña 17, 10-13 jul 2026 |
| Huésped | 34 | `total_reservas=1`, `primera_reserva_fecha=2026-07-10` |
| Huésped | 35 | `total_reservas=0` |
| Bloqueo | 6 | activo, cabaña 19, 15-18 sep 2026, motivo `mantenimiento` |
| Bloqueo | 7 | activo, **total**, 20-22 nov 2026, motivo `tormenta` |
| Bloqueos | 1-5 | activos (origen pre-6C, no creados en esta etapa) |

---

## Schema canónico actual

**Schema canónico vigente:** `6B_SCHEMA_SQL.md v1.12.0` — incorpora el **Carril B** (sección 24 conceptual + PARTE C ejecutable) y el **Carril C / Portal Operativo Interno** (PARTE D: `portal_usuarios`, `portal_idempotencia`, `portal_cargar_gasto_interno(jsonb)` + §25 conceptual), ambos promovidos a OPS en junio 2026 (ver `PROMOCION_CARRIL_B_OPS_CIERRE.md` y `PROMOCION_CARRIL_C_OPS_CIERRE.md`). v1.8.1 había canonizado el hardening del motor (Bloque 23). El núcleo refleja el estado real de DEV post-hardening (6D) y post-correcciones pre-TEST/pre-OPS (7A). DEV **se reconstruyó desde v1.8.0** (cerrada 2026-06-15, proyecto nuevo `wsrdzjmvnzxidjlovlja`, creado cerrado como OPS); ya no está sobre v1.7.3 (ver `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md`).

**Backup histórico:** `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.2_PRE_PREOPS.md` (estado pre-7A) y `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md` (estado pre-6D), ambos con banner explícito de archivo no canónico, conservados para auditoría/rollback.

**Lo que el bump v1.7.3 documentó (Etapa 7A):**

1. `crear_prereserva`: variable `v_ninos` de `BOOLEAN` a `TEXT`, extract sin cast a BOOLEAN (`NULLIF(TRIM(payload->>'ninos'), '')`). Resuelve el hallazgo de tipo `ninos`.
2. `crear_prereserva`: `canal_pago_esperado` agregado al IF de obligatorios → rebota `payload_invalido` para ausente/vacío/whitespace. Resuelve el hallazgo de `canal_pago_esperado`.
3. `vista_disponibilidad` y `vista_calendario`: horizonte configurable vía `configuracion_general.horizonte_disponibilidad_dias` con fallback 120 (antes hardcoded 60). Forma persistida adoptada.
4. Seed del Bloque 21: clave `horizonte_disponibilidad_dias` agregada (conteo `configuracion_general` 9 → 10).

**Lo que documentó el bump previo v1.7.2 (Etapa 6D):**

1. Patrón defensivo `NULLIF(TRIM(...), '')` en los extracts de payload de las 5 funciones write críticas (`registrar_pago`, `confirmar_reserva`, `crear_prereserva`, `cancelar_prereserva`, `crear_bloqueo`).
2. Fix de rango en `vista_ocupacion` (24 meses exactos).
3. Fix cosmético de `TRIM` en concatenación nombre + apellido en `vista_calendario`, `vista_limpieza_semana` y `vista_prereservas_activas`.
4. Correcciones documentales de alineación con DEV real.
5. Forma persistida de las vistas adoptada (`pg_get_viewdef()`) para garantizar match byte-exacto contra DEV.

**Hallazgos del changelog v1.7.2 — todos resueltos en v1.7.3 (Etapa 7A):**

- ✅ Alineación de tipo `ninos`: resuelto (D-7A-02).
- ✅ Contrato de `canal_pago_esperado`: resuelto (D-7A-01).

**Observación liviana abierta (no bloqueante):** `tipo_valor` sin poblar en las 10 claves de `configuracion_general`. Ver `Pendiente_pre_produccion.md` sección 1.4. A evaluar antes del dashboard OPS.

**El canónico v1.7.3 no crea schema paralelo. Es la única fuente de verdad documental del schema.**

**TEST también está alineado funcionalmente con v1.7.3** — su schema se reconstruyó desde el canónico en Etapa 7B, con paridad estructural 10/10 demostrada vs DEV (ver `7B_CIERRE.md` sección 5).

**`abortar_si_falla(jsonb)` (helper 9B) — promovida a OPS e incorporada al canónico v1.8.0 (PARTE C).** Era aditiva (no toca tablas, enums ni `registrar_pago()`); viajó a OPS en la promoción coordinada del Carril B (junio 2026) creada como **último objeto**, con `search_path` fijo y `REVOKE EXECUTE` (D-PROMO-10). Su DDL original está documentada en `9B_CIERRE.md` §3.

**Carril B (9C→9H) — promovido a OPS e incorporado al canónico v1.8.0:** columnas `cabanas.valor_relativo` y `cabanas.id_socio_beneficiario`; tablas `zonas`, `cabana_zona`, `activaciones_operativas`, `gastos_internos`, `liquidaciones_periodo`, `liquidacion_cascada`, `liquidacion_socio`, `movimientos_socio` y `revaluaciones`; la clave `configuracion_general('ambiente')`; la función `trg_9h_inmutable()` con sus 10 triggers; y las funciones de 9C, 9E, 9G y 9H. **Todo esto vive ahora en OPS** (paridad estructural TEST↔OPS por huella `TOTAL_CARRIL`) y **forma parte del canónico v1.8.0** (sección 24 + PARTE C). La `gastos` legacy **se conserva/congela** (D-9F-01); el Carril B opera sobre `gastos_internos`. Los GRANTs/RLS quedaron **cerrados sin exposición** (D-PROMO-07). Los fixtures de laboratorio (`seed_9f_validacion`, pagos `seed_9g_%`, carga `seed_9h_d`) no son schema y **no viajaron**. Ver `PROMOCION_CARRIL_B_OPS_CIERRE.md`.

---

## Próxima etapa — opciones disponibles

Con 6D, 7A, 7B, 7C, 7D, 7E, **8A, 8B, 8C, 8D cerradas, la Etapa 8 (operación real interna) está completa** y **8C-bis** (alerta por reserva próxima) quedó cerrada y activa en OPS. La **Etapa 9 / Carril A** tiene 9A y 9B/3b cerradas en TEST, y el **Carril B / contabilidad operativa interna quedó promovido a OPS** (9C→9H + helper 9B; canónico v1.8.0). El equipo opera el complejo con tres acciones autoservicio sobre OPS (cargar reservas, ver el estado, crear bloqueos). Las siguientes son **opciones disponibles** a priorizar por Franco (orden sugerido, no comprometidas en este documento):

* **✅ Promoción coordinada del Carril B a OPS — hecha (junio 2026).** Todo el Carril B (9C/9D/9E/9F/9G/9H + `abortar_si_falla(jsonb)` + workflow 3b `__OPS`) fue promovido a OPS por DDL, con bump único del canónico a **v1.8.0**, marcador `'ambiente'='ops'`, GRANTs/RLS cerrados sin exposición y paridad estructural TEST↔OPS por huella. Ver `PROMOCION_CARRIL_B_OPS_CIERRE.md`.

- **✅ Decisiones de negocio del Carril B — cerradas (2026-06-14):** **% operativo = 25%** (sobre los ingresos cobrados del período, después de restar gastos operativos/Carril B; las funciones lo reciben por parámetro, D-9G-01) e **inicio contable = 2026-07-01** (períodos anteriores fuera de alcance: no se liquidan ni arrastran) — D-NEG-01 / D-NEG-02. La liquidación del `extra` (5%) ya estaba **resuelta por diseño**: ingreso post-operativo, paso 6 de la cascada (conceptual §4.3 / D-9G-02), comparado contra el monotributo sin netear (reporte 5-vs-fiscal).
- **Resto de la arquitectura global de contabilidad:** caja por lugar, conversión / tabla de ahorro de monedas, cancelaciones con cargo, AFIP/ARCA/IVA/facturación (carril fiscal, separado por diseño). El bump del canónico (`6B_SCHEMA_SQL.md`) a v1.8.0 ya llegó con la promoción del Carril B; el resto es conversación aparte.
- **Edición / baja de bloqueos:** hoy 8D solo crea (D-8D-09); levantar o corregir un bloqueo es manual (`activo=false` vía SQL). Si se vuelve frecuente, sería una capa posterior con su propio formulario.
- **Apertura al exterior (etapas futuras grandes, sobre TEST primero):** webhook MercadoPago real, bot conversacional (Claude API), web pública de reservas, WhatsApp/Instagram (Meta API), y eventualmente el entorno PROD público. Es el salto más ambicioso del proyecto; no es un "último pasito".
- **Residual de permisos de tabla en DEV (hallazgo A5 / pendiente 1.7):** decidir si se revoca el set amplio sobre tablas/vistas/secuencias a roles Data API en DEV, o se acepta y documenta como definitivo. No urgente (sin consumidores Data API activos). OPS ya nació sin ese problema. Ver `Pendiente_pre_produccion.md` 1.7.

No avanzar a PROD público, MercadoPago real, bot o frontend público sin decisión explícita.

---

## Pendientes técnicos abiertos

**Items cerrados en Etapa 6D:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Hardening de validación SQL en funciones write | ✅ Cerrado | H2, H3, H4, H4-bis, H4-ter |
| Fix `vista_ocupacion` 25→24 meses | ✅ Cerrado | H5 |
| Espacio colgando en concatenación nombre+apellido | ✅ Cerrado | H6, H6-bis |
| Tests de concurrencia C-1 a C-6 | ✅ Cerrado | H7 |
| Bump documental del schema canónico a v1.7.2 | ✅ Cerrado | H8 Frente A |

**Items cerrados en Etapa 7A:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Horizonte de `vista_disponibilidad`/`vista_calendario` configurable (60→120) | ✅ Cerrado | PreOPS-A6 (D-7A-03) |
| Alineación de tipo `ninos` (función vs columnas) | ✅ Cerrado | Patch `crear_prereserva` v1.7.3 (D-7A-02) |
| Contrato de `canal_pago_esperado` (validación manual) | ✅ Cerrado | Patch `crear_prereserva` v1.7.3 (D-7A-01) |

**Items cerrados en Etapa 7B:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Levantamiento del entorno TEST (proyecto Supabase independiente) | ✅ Cerrado | 7B-1 (D-7B-01) |
| Paridad estructural TEST vs DEV (schema v1.7.3) | ✅ Cerrado | 7B-2 (paridad 10/10) |
| Seeds mínimos en TEST | ✅ Cerrado | 7B-3 |
| `pg_cron` activo en TEST con ejecuciones reales | ✅ Cerrado | 7B-3-cron |
| Permisos Data API normalizados en TEST (REVOKE EXECUTE) | ✅ Cerrado | 7B-GRANTS (D-7B-03, D-7B-05) |
| Workflows `__TEST` importados y validados (happy path 8/8) | ✅ Cerrado | 7B-4 (D-7B-04) |
| Cadena transaccional end-to-end W2→W3→W4 en TEST | ✅ Cerrado | 7B-4 |

**Items cerrados en Etapa 7C:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Validación funcional ampliada sobre TEST (casos no-felices) | ✅ Cerrado | 7C-1 a 7C-6 (48 funcionales + 6 transversales) |
| Cobertura empírica de rama `pre_lock` de idempotencia | ✅ Cerrado | 7C-5 (A-W2-15) |

**Items cerrados en Etapa 7D:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Diseño y ejecución del bloque de limpieza/reset de TEST | ✅ Cerrado | 7D Bloques A/B/C (D-7D-01, D-7D-02) |
| Reset de secuencias a 1 en tablas vaciadas de TEST | ✅ Cerrado | 7D Bloque B (D-7D-01) |
| Vaciado de `log_cambios` en TEST con evidencia documentada | ✅ Cerrado | 7D Bloque B (D-7D-02) |

**Items cerrados en Etapa 7E:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Endurecimiento de permisos Data API en DEV (REVOKE EXECUTE sobre 13 funciones) | ✅ Cerrado | 7E Bloques A/B/C (D-7E-01, D-7E-02) |
| Paridad DEV↔TEST en EXECUTE sobre funciones del proyecto | ✅ Cerrado | 7E Bloque C (0 fugas, owner intacto) |

**Items cerrados en Etapa 8A:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Creación del entorno OPS (proyecto Supabase independiente) | ✅ Cerrado | 8A Bloques 1-2 |
| Replicación del schema desde canónico v1.7.3 (paridad P01-P10 10/10) | ✅ Cerrado | 8A Bloque 4 (tandas 4.1-4.7) |
| Seeds reales mínimos en OPS (5 cabañas, 3 socios, cuenta de cobro, config) | ✅ Cerrado | 8A Bloque 5 |
| Grants mínimos en OPS (REVOKE EXECUTE idempotente; OPS nació cerrado) | ✅ Cerrado | 8A Bloque 6 (confirmación D-8-03) |
| Default privileges de OPS (objetos futuros nacen cerrados, sin ejecución) | ✅ Cerrado | 8A Bloque 7 (D-8-13) |
| `pg_cron` activo en OPS con corrida real verificada | ✅ Cerrado | 8A Bloque 8 |
| Verificación consolidada del entorno OPS (17/17) | ✅ Cerrado | 8A Bloque 9 |
| Credencial n8n `vita_supabase_ops` creada y verificada por identidad | ✅ Cerrado | 8A Bloques 10-11 |

**Items pendientes:**

1. **`tipo_valor` sin poblar en `configuracion_general`** — observación de 7A (PreOPS-A6). Las 10 claves tienen `tipo_valor=NULL`. No bloqueante; evaluar antes del dashboard OPS si se usa para render de inputs. Ver `Pendiente_pre_produccion.md` 1.4.
2. **Validación de tipos inválidos no vacíos** — surgido durante hardening. Casos como `id_cabana="abc"` o `fecha_in="no-es-fecha"` siguen rompiendo con error crudo. Fuera del alcance del hardening por strings/whitespace.
3. **Cobertura empírica de rama `unique_violation` de idempotencia** — opcional, no bloqueante. H7 observó la rama `post_lock` (C-6) y 7C observó la rama `pre_lock` (A-W2-15). Resta solo `unique_violation`, que requiere un cruce concurrente en ventana estrechísima, no reproducible de forma simple. Queda como cobertura opcional pre-PROD si se considera necesario. Ver `Pendiente_pre_produccion.md` 6.3.
4. **RLS configurado** — pendiente histórico, decisión postergada hasta tener frontend público.
5. **Tarifas reales cargadas** — pendiente histórico.
6. **Feriados productivos cargados** — pendiente histórico.
7. **Endurecimiento de permisos en DEV (EXECUTE sobre funciones)** — ✅ **Cerrado en Etapa 7E** (2026-05-28). Se aplicó a DEV el REVOKE EXECUTE sobre las 13 funciones del proyecto a PUBLIC/anon/authenticated/service_role, en paridad con TEST. Owner `postgres` intacto, n8n no afectado, 0 fugas verificadas. Decisiones D-7E-01, D-7E-02. Ver `7E_CIERRE.md`. **Queda abierto el residual asociado:** permisos amplios de tabla a roles Data API en DEV (hallazgo A5), fuera de alcance de 7E por decisión, registrado como pendiente `Pendiente_pre_produccion.md` 1.7.
8. **Validación funcional ampliada sobre TEST** — ✅ **Cerrada en Etapa 7C** (2026-05-28). Batería de casos no-felices ejecutada: 48 casos funcionales + 6 verificaciones transversales, 0 fallos inesperados. Ver `7C_CIERRE.md`.
9. **Diseño del bloque de limpieza/reset de TEST** — ✅ **Cerrado en Etapa 7D** (2026-05-28). Se diseñó y ejecutó el bloque dedicado de reset (snapshot → limpieza atómica → verificación), dejando TEST como entorno limpio: schema v1.7.3 + seed estructural + cron + grants + workflows `__TEST`, sin datos transaccionales. Decisiones D-7D-01 y D-7D-02. Ver `7D_CIERRE.md` y `Pendiente_pre_produccion.md` 6.5.
10. **Residual amplio de permisos de tabla a roles Data API en DEV** — pendiente activo abierto en Etapa 7E. Los roles `anon`/`authenticated`/`service_role` tienen SELECT/escritura completos sobre todas las tablas/vistas de DEV (hallazgo A5, 480 grants), más amplio que el `Dxtm` de TEST. Fuera de alcance de 7E por decisión (Opción 1). A decidir en etapa futura: revocar para alinear con TEST o aceptar y documentar como definitivo. No urgente (sin consumidores Data API activos en DEV). Ver `Pendiente_pre_produccion.md` 1.7 y `7E_CIERRE.md` sección 8.

---

## Lo que NO es Vita Delta hoy

- **No es PROD público.** OPS sí es operación real interna, pero todavía no hay entorno PROD público ni consumidores externos abiertos.
- **No tiene web pública lanzada.** El `index.html` del repo es un prototipo viejo, no la web final.
- **No tiene RLS configurado para frontend público.** Decisión postergada hasta tener consumidores Data API reales.
- **No tiene tarifas reales definitivas cargadas.**
- **No tiene feriados productivos cargados.**
- **No tiene MercadoPago automático, bot ni frontend público conectados.**
- **El Carril B contable no tiene aún carga operativa real** (gastos, snapshots y movimientos reales). La capa ya está **promovida a OPS** (junio 2026, canónico v1.8.0) y sus reglas de negocio están **cerradas** (% operativo 25%, inicio contable 2026-07-01 — D-NEG-01/02); lo que falta es operarla a partir de julio 2026.

---

## Documentación viva del proyecto

- `6B_SCHEMA_SQL.md v1.12.0` — schema canónico SQL vigente (incorpora el Carril B y el Carril C / Portal Operativo Interno como capa real: PARTE D + §25). Backups históricos archivados.
- `PROMOCION_CARRIL_B_OPS_CIERRE.md` — cierre de la promoción del Carril B a OPS + canónico v1.8.0 (junio 2026).
- `PROMOCION_CARRIL_C_OPS_CIERRE.md` — cierre de la promoción del Carril C (Portal Operativo Interno) a OPS + canónico v1.9.0 + bootstrap kit v1.9.0 (2026-06-29).
- `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md` — cierre de la reconstrucción de DEV desde v1.8.0 (proyecto nuevo `wsrdzjmvnzxidjlovlja`, creado cerrado como OPS; 2026-06-15).
- `Docs/Implementacion/bootstrap_entorno_nuevo_v1.12.0/` — juego repetible (9 archivos) para levantar un entorno de cero desde el canónico v1.12.0 (precheck → bootstrap Parte B → verify → bootstrap Parte C/Carril B → verify → bootstrap Parte D/Portal → verify final estricto + `README_EJECUCION_BOOTSTRAP.md`); extracción literal del canónico (**regla R2**: primer fence `sql` por bloque), **paritario con el canónico vigente v1.12.0** (regenerar en cada bump), validado de punta a punta contra un PostgreSQL 16.14 limpio con stubs Supabase (aún no ejecutado sobre un Supabase real; pendiente separado). El paso de verificación final es estricto (FKs por tabla/columna incl. ON DELETE CASCADE/RESTRICT, CHECK/UNIQUE por relación, firma de función, hardening por ACL real vía `aclexplode`, RLS off + 0 policies). **El kit anterior `bootstrap_entorno_nuevo_v1.9.0/` se retiró del árbol** (limpieza del cierre de Bloque C, para evitar doble fuente ejecutable; queda en el historial de git). Solo sobre base vacía; no correr sobre un entorno poblado (el precheck lo gatea).
- `6B_PLAN_FASES.md` — plan ejecutado, conservado como referencia. Sección 6.8 es fuente para H7.
- `ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md` — arquitectura consolidada de migración.
- `6C_CIERRE.md` — documento formal de cierre de etapa 6C.
- `7A_CIERRE.md` — documento formal de cierre de Etapa 7A (correcciones pre-TEST/pre-OPS).
- `7B_CIERRE.md` — documento formal de cierre de Etapa 7B (levantamiento del entorno TEST).
- `7C_CIERRE.md` — documento formal de cierre de Etapa 7C (validación funcional ampliada sobre TEST).
- `7D_CIERRE.md` — documento formal de cierre de Etapa 7D (limpieza/reset del entorno TEST).
- `7E_CIERRE.md` — documento formal de cierre de Etapa 7E (endurecimiento de permisos Data API en DEV).
- `ARQUITECTURA_ETAPA_8_ARRANQUE_OPS.md` — documento de diseño de la Etapa 8 (arranque OPS operativo desde cero; subetapas 8A entorno, 8B carga, 8C calendarios, 8D bloqueos).
- `8A_CIERRE.md` — documento formal de cierre de Etapa 8A (levantamiento del entorno OPS de operación real interna).
- `ARQUITECTURA_ETAPA_8B_CAPA_CARGA.md v3.5` — documento de diseño de la Etapa 8B (capa de carga interna; verificación de contratos contra OPS, decisiones D-8B-01 a D-8B-21).
- `8B_CIERRE.md` — documento formal de cierre de Etapa 8B (capa de carga validada en TEST + smoke OPS con primera reserva real).
- `Workflows/n8n/8B/vita_w8b_carga_reserva__TEST.json` / `__OPS.json` / `__TEMPLATE.json` — workflows de 8B (TEST validado, OPS productivo, template sanitizado reutilizable).
- `ARQUITECTURA_ETAPA_8C_CALENDARIOS_VISUALES.md v1.3` — documento de diseño de la Etapa 8C (calendarios visuales por evento; tres bloques + 8C-bis posterior; decisiones D-8C-01 a D-8C-23).
- `8C_CIERRE.md` — documento formal de cierre de Etapa 8C (tres calendarios validados en TEST; smoke OPS y 8C-bis como trabajos posteriores independientes).
- `Workflows/n8n/8C/vita_w8c_html_operativo__TEST.json` / `vita_w8c_html_limpieza__TEST.json` / `vita_w8c_sheet_resguardo__TEST.json` — workflows de 8C (los tres validados en TEST, inactivos).
- `Workflows/n8n/8C/vita_w8c_html_operativo__TEMPLATE.json` / `vita_w8c_sheet_resguardo__TEMPLATE.json` — templates sanitizados de 8C para GitHub.
- `ARQUITECTURA_ETAPA_8D_BLOQUEOS_OPERATIVOS.md v1.1` — documento de diseño de la Etapa 8D (capa de bloqueos operativos; formulario que invoca `crear_bloqueo`; decisiones D-8D-01 a D-8D-09).
- `8D_CIERRE.md` — documento formal de cierre de Etapa 8D (validada en TEST + operativa en OPS; incluye el cierre de la Etapa 8 completa).
- `8D_EJECUCION.md` — bitácora de ejecución de la Etapa 8D (verificación read-only del contrato, construcción del workflow, incidencias resueltas, validación TEST y promoción a OPS).
- `Workflows/n8n/8D/vita_w8d_bloqueo__TEST.json` (id `GIfBlI6xCnrkH2Y4`, validado) / `vita_w8d_bloqueo__OPS.json` (activo en producción) / `vita_w8d_bloqueo__TEMPLATE.json` (sanitizado para GitHub).
- `8C-bis_CIERRE.md` — documento formal de cierre de la sub-etapa 8C-bis (alerta por reserva próxima por mail; recoge el item 3.1; validada en TEST con envío real + publicada/activa en OPS; decisiones D-8Cbis-01 a D-8Cbis-10; lecciones L-8Cbis-01 a L-8Cbis-03).
- `Workflows/n8n/8Cbis/vita_w8cbis_alerta__TEST.json` (id `TdTlv9ZhswwzijF2`, validado con envío real) / `vita_w8cbis_alerta__OPS.json` (id `fHzMFj7pGMKuYEOb`, activo en producción).
- `Docs/Bitacora/6B_EJECUCION_DEV.md` — bitácora bloque por bloque de 6B.
- `Docs/Bitacora/6C_EJECUCION.md` — bitácora workflow por workflow de 6C.
- `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` — bitácora bloque por bloque de Etapa 6D (H1-H7 cerrados; H8 en curso).
- `Docs/Operacional/Lecciones_Aprendidas.md` — gotchas operativos (incluye L-6C-01 a L-6C-09 + nuevas lecciones de hardening pendientes de agregar).
- `Pendiente_pre_produccion.md` — pendientes de deploy productivo (items A1-A3 marcados como cerrados; A4 pendiente).
- `DECISIONES_NO_REABRIR.md` — decisiones cerradas no reabribles (incluye decisiones de hardening pendientes de agregar).
- Documentos de arquitectura de Etapas 1-5 (referencia histórica).
- `Workflows/n8n/supabase/*.template.json` — 8 templates sanitizados de 6C.
- `9B_CIERRE.md` — cierre de cobranza posterior multi-porción / Fase 3b.
- `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md` — base conceptual de contabilidad operativa interna.
- `9C_CIERRE.md` — catálogo enriquecido, zonas y seam.
- `9D_CIERRE.md` — activación operativa por rango.
- `9E_CIERRE.md` — matriz dinámica y reparto.
- `9F_CIERRE.md` — gasto interno rediseñado.
- `9G_CIERRE.md` — cascada de liquidación read-only.
- `9H_CIERRE.md` — cuenta corriente interna / capa con estado; cierre del Carril B.