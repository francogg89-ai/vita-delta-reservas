# C_SLICE1_B4_RUNSHEET — Wrapper `portal-a04-operativo` (TEST)

**Carril C / Portal Operativo Interno · Slice 1 · Bloque 4**
Construir, activar y probar (smoke directo) el wrapper n8n del **calendario operativo (120 días, con montos)**. Defensa en profundidad: este bloque valida el wrapper **sin** pasar por el gateway. El cableado en `portal-api` / CATALOG es el **Bloque 5** — **acá no se toca `portal-api`**.

- **Action congelada:** `calendario.operativo` (sin sufijo de horizonte).
- **Roles del wrapper:** `vicky`, `socio`. **Jenny excluida** (su rebote desde el gateway es el hito de B5).
- **Ambiente:** TEST exclusivamente. **OPS y `6B_SCHEMA_SQL.md` intocables.**
- **Artefactos del bloque:** `portal-a04-operativo__TEMPLATE.json`, `C_SLICE1_B4_smoke_a04_directo.ps1`, este runsheet.

---

## 0. Precondiciones

1. **Variable de n8n `VITA_HMAC_SECRET` seteada** (Settings → Variables) con el secreto HMAC de TEST.
   - El template **NO** trae el secreto: el nodo lee `$vars.VITA_HMAC_SECRET` y, si la Variable falta, **aborta** por assert duro (`SECRET.startsWith('__PEGAR_')`, L-C-10). **No pegar el secreto en el nodo.**
2. **Credencial Postgres de TEST** disponible en n8n (la misma que usa A03, p. ej. `vita_supabase_test`). El template trae el placeholder `vita_supabase_test (reemplazar al importar)` en los 5 nodos Postgres.
3. n8n Cloud accesible: `https://federicosecchi.app.n8n.cloud`.

---

## 1. Importar, cablear y activar el wrapper

1. **Importar** `portal-a04-operativo__TEMPLATE.json` como workflow nuevo en n8n (TEST). Queda `active:false`.
2. **Asignar la credencial Postgres de TEST** en los **5 nodos Postgres**: `leer_ambiente`, `PG: leer grilla`, `PG: leer detalle`, `PG: leer bloqueos`, `PG: leer salidas`. (El placeholder no resuelve solo; hay que seleccionar la credencial real en cada nodo.)
3. **Verificar la Variable** `VITA_HMAC_SECRET` (paso 0.1). Si no existe o quedó vacía, el nodo `validar_firma_ts_rol` tirará el error de assert al ejecutar — eso es deliberado.
4. **Guardar y activar** el workflow (toggle Active). El Webhook queda en producción en:
   `https://federicosecchi.app.n8n.cloud/webhook/portal-a04-operativo`

> **Nota sobre el Webhook:** está en `responseMode: responseNode` + `Raw Body` activado. El raw body se preserva byte a byte para recomputar el HMAC (D-C-29). No cambiar esas opciones.

---

## 2. Smoke directo al wrapper (8 casos)

1. Abrir `C_SLICE1_B4_smoke_a04_directo.ps1`.
2. En el bloque **CONFIG**: dejar `$BaseUrl` y `$Webhook` como están; **pegar en `$Secret` el MISMO valor** que la Variable `VITA_HMAC_SECRET`.
   - El probe firma localmente las pruebas con ese secreto. Si no coincide con la Variable de n8n, los casos de firma válida darán `firma_invalida` (señal de desincronización, no de bug del wrapper).
3. Ejecutar el script (PowerShell). Imprime, por caso, el veredicto parseado del envelope: `ok:true | formato=html | html_len=N` o `ok:false | error.code=...`.
4. **Borrar el secreto de `$Secret`** antes de cualquier commit (no se commitea el secreto).

### Resultado esperado

| # | Caso (rol / variación)                | Envelope esperado | Veredicto que imprime el probe |
|---|---------------------------------------|-------------------|--------------------------------|
| 1 | vicky, firma válida, ambiente test    | `ok:true`         | `formato=html`, `html_len>0`   |
| 2 | socio, firma válida, ambiente test    | `ok:true`         | `formato=html`, `html_len>0`   |
| 3 | jenny (rol válido, no habilitado A04) | `ok:false`        | `rol_no_permitido`             |
| 4 | intruso (rol inexistente)             | `ok:false`        | `rol_no_permitido`             |
| 5 | firma inválida (secreto equivocado)   | `ok:false`        | `firma_invalida`               |
| 6 | ts viejo (−10 min)                    | `ok:false`        | `ts_fuera_de_ventana`          |
| 7 | ambiente cruzado (`ops` → wrapper TEST)| `ok:false`       | `ambiente_incorrecto` (detail `esperado=ops real=test`) |
| 8 | action incorrecta (`calendario.limpieza`) | `ok:false`    | `accion_desconocida`           |

> Todos responden **HTTP 200**: el verdadero veredicto va en el envelope (`ok` + `error.code`), no en el status. Por eso el probe parsea el JSON y no se conforma con el 200 (punto 9 de la aprobación).

---

## 3. Auditoría del render (obligatoria antes de cerrar B4 · punto 8)

Revisar el nodo `Code: render envelope`. Debe cumplir **todo**:

- **Solo montos a nivel reserva:** `monto_total` y `monto_saldo`, formateados por `money()` (formato es-AR). **Aceptable** según D-C-03 (Vicky/socios ven montos de reserva/pago).
- **NO** reparto por socio. **NO** cascada. **NO** mayor / cuenta corriente. **NO** datos societarios. (El render no consulta ni imprime ninguna de esas dimensiones; las 4 queries son grilla/detalle/bloqueos/salidas.)
- **NO** raw SQL ni error crudo de Postgres/n8n al cliente: si alguna lectura falla, `safeAll` lo detecta y el render devuelve `error_interno` limpio (ver §4).
- **Escaping (`esc()`) en TODO texto dinámico** que entra al HTML:
  - huésped (`huesped_nombre`, también `primerNombre(...)` al salir),
  - teléfono (`huesped_telefono`),
  - personas (`personas`),
  - motivo de bloqueo (`motivo`),
  - nombre de cabaña (`cab.nombre`).
  - Horas vía `hhmm()` (recorta `HH:MM`, sin metacaracteres). Montos vía `money()` (numéricos). Ambos seguros.
- **`descripcion` de bloqueo:** se **lee** en la query (`SELECT ... descripcion ...`) pero **NO se renderiza** (el HTML solo usa `motivo`). No entra al DOM, así que no hay superficie de inyección por ese campo. Si en el futuro se decide mostrarla, hay que envolverla en `esc()`.

---

## 4. Notas de diseño (deltas vs el template A03)

- **`onError: continueRegularOutput` en los 5 nodos Postgres** (las 4 lecturas + `leer_ambiente`). **Hardening explícito respecto del template A03**, que lo había perdido. Restaura el criterio de 8C §2.3 (Continue On Fail): si una query falla, el nodo emite un item en vez de cortar el workflow, y entonces:
  - en las 4 lecturas → `safeAll` lo ve y el render arma `error_interno` limpio (sirve a los puntos 8 y 9);
  - en `leer_ambiente` → `verificar_acceso` lee `real=null` y degrada a `ambiente_incorrecto`, en vez de colgar.
  El camino feliz no cambia: `onError` solo actúa ante excepción.
- **Respond = `respondWith: firstIncomingItem` + `responseCode: 200`** (explícito). Garantiza que el **body sea el JSON del item** (el envelope), no un 200 vacío (punto 9). Tanto el branch de éxito (render) como el de rechazo (`verificar_acceso` vía IF rama false) terminan en este nodo.
- **`ymd()` en el render** (L-8C-02): normaliza `date|timestamp` a `YYYY-MM-DD` antes de comparar/derivar. Robustez sobre verbatim; el output visual no cambia (punto 5).
- **Sin HTML de error (código muerto eliminado):** el branch de error devuelve el envelope `error_interno` directo; no quedó ningún `html` de error rondando.
- **Secreto:** el wrapper **nunca** tiene el secreto hardcodeado. Vive en la Variable de n8n; el template solo trae el placeholder sanitizado `__PEGAR_SECRETO_O_USAR_VARIABLE__`, capturado por el assert de prefijo.

---

## 5. Criterio de cierre del Bloque B4

✅ **B4 queda validado cuando los 8 casos dan exactamente el veredicto esperado** de la tabla de §2:

- 1 y 2 → `ok:true`, `formato=html`, `html_len>0`;
- 3 y 4 → `rol_no_permitido`;
- 5 → `firma_invalida`; 6 → `ts_fuera_de_ventana`; 7 → `ambiente_incorrecto`; 8 → `accion_desconocida`;
- y la **auditoría del render (§3) pasa** (solo montos de reserva, escaping completo, sin societario/SQL crudo).

Con eso, el wrapper está probado de punta a punta de forma aislada. **Siguiente: Bloque B5** — cablear `calendario.operativo` en `portal-api` / CATALOG (`roles:['vicky','socio']`, `webhook:'portal-a04-operativo'`, `validate: payloadVacio`) y smoke vía gateway, donde **jenny debe rebotar con `rol_no_permitido` desde el gateway, antes de firmar** (hito de B5).

### Qué NO se toca en B4
- `portal-api` / CATALOG (es B5).
- OPS y `6B_SCHEMA_SQL.md` (canónico).
- Los documentos satélite (se actualizan recién en el cierre formal del Slice 1, que además espera A05/A06/A12 — A04 sola no cierra el slice).
