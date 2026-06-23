# CONTRATO FRONTEND ↔ PORTAL — v1

**Proyecto:** Vita Delta Reservas — Carril C / Portal Operativo Interno
**Documento:** especificación de consumo del gateway `portal-api` desde el navegador (API reference del portal).
**Fecha:** 2026-06-22.
**Ambiente:** **TEST** (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`, IDs de cabaña 1–5, `configuracion_general.ambiente='test'`).
**Backend pin:** Carril C **Slice 3b cerrado** (A11 carga de gasto + A13 listado). Gateway `portal-api` con **CATALOG 13**.
**Alcance:** **13 acciones** realmente construidas y verificadas en TEST.
**Fuera de alcance:** acciones diseñadas y no construidas (A09, A14–A23); OPS; implementación del frontend; contrato JSON formal de calendarios (P-C-3); `6B_SCHEMA_SQL.md`.

> **Regla de autoridad de este documento:** ante cualquier diferencia entre este contrato y el comportamiento del gateway desplegado, **manda el gateway vigente** (`C_SLICE3B_A13_portal-api_index.ts`). Este documento lo refleja, no lo reemplaza. Las divergencias detectadas durante su redacción están en §14.

---

## 1. Decisiones de contrato (D-FE) 🔒

> Decisiones establecidas por este contrato. Namespace `D-FE-XX` (no se mezcla con `D-C-XX`, que queda para el backend de Carril C). Las lecciones del frontend usarán `L-FE-XX` (todavía no hay; nacen al construir).

- **D-FE-01 — Alcance = CATALOG 13.** El contrato cubre exactamente las 13 acciones construidas y verificadas en TEST. Las acciones futuras se listan sin contrato detallado (§12). El frontend **pinea** la versión del contrato que implementa.
- **D-FE-02 — Transporte dual de `idempotency_key`.** No es uniforme entre escrituras:
  - **A10** `cobranza.registrar_saldo`: la key viaja **dentro de `payload`** (`payload.idempotency_key`).
  - **A11** `cargar.gasto_interno`: la key viaja **top-level, sibling de `payload`**.
  - **A07** `reserva.crear_manual`: el frontend **no** manda key (el wrapper deriva idempotencia interna para `crear_prereserva`).
  - **A08** `bloqueo.crear_manual`: **sin** key; se apoya en `conflicto`/solapamiento.
  El frontend respeta el transporte **por acción**; no lo uniforma.
- **D-FE-03 — Calendarios A03/A04 = HTML temporal.** Devuelven `data:{ formato:"html", html }`. El frontend **renderiza ese HTML** (contenedor/iframe), no lo re-pinta como datos estructurados. El contrato JSON formal de calendarios es **P-C-3**, post-MVP.
- **D-FE-04 — Ramificación por `body.ok`, no por status HTTP.** `portal-api` responde **HTTP 200 + envelope** para todo resultado manejado (incluido `no_autorizado`). El único no-200 es **500** (crash de infra → `error_interno`). El frontend decide éxito/error por **`body.ok`**. **No** se documenta 401 como contrato normal.
- **D-FE-05 — Taxonomía de errores en dos familias.** (a) **alcanzables por el frontend**; (b) **canal gateway↔n8n / "no debería pasar"**. La familia (b) se trata como bug de backend (contactar admin / no reintentar a ciegas). Detalle en §8.
- **D-FE-06 — Ante `estado_incierto` en escritura, no reintentar a ciegas.** El frontend **reconsulta la lectura companion** (o muestra verificación manual) antes de cualquier reintento. Companion por acción en §9.
- **D-FE-07 — La `idempotency_key` la genera el frontend, por intento de submit.** Mismo submit (retry de red/UI) → **misma** key. Nuevo submit intencional → **nueva** key. Regex `^[A-Za-z0-9_-]{8,64}$`. Aplica a A10 (en payload) y A11 (sibling).
- **D-FE-08 — Namespace.** Decisiones de contrato/frontend = `D-FE-XX`; lecciones = `L-FE-XX`. No se mezclan con `D-C-XX`.

---

## 2. Arquitectura de consumo desde el navegador

```
Frontend (navegador)
  → Supabase Auth            (login → JWT de sesión)
  → portal-api (Edge Fn)     (valida JWT → lookup portal_usuarios → rol → allowlist → firma HMAC)
  → wrappers n8n firmados    (revalidan 5 dimensiones: HMAC · ts ±300s · rol · action binding · ambiente)
  → Supabase / PostgreSQL    (fuente de verdad)
```

Reglas invariantes:

- El frontend **siempre** llama a `portal-api` con un `action`. **Nunca** llama a n8n directo ni conoce los webhooks.
- El frontend **nunca** calcula HMAC.
- El frontend **nunca** toca tablas de Supabase directamente.
- El frontend **nunca** manda `actor`, `creado_por`, `source_event`, `nonce`, `rol`, `request_ts` ni ningún campo de control (ni en `payload` ni top-level). `portal-api` inyecta el `actor` desde el JWT/`portal_usuarios`, server-side.
- La `idempotency_key` **sí** la manda el frontend, en la posición que corresponda a la acción (D-FE-02), y **no** es un campo de control prohibido.

---

## 3. Endpoint y transporte

| Ítem | Valor |
|---|---|
| **URL (TEST)** | `https://bdskhhbmcksskkzqkcdp.supabase.co/functions/v1/portal-api` |
| **Método** | `POST` (cualquier otro → `payload_invalido`) |
| **`Content-Type`** | `application/json` |
| **`Authorization`** | `Bearer <jwt>` — access token de la sesión de Supabase Auth |
| **`apikey`** | `<ANON_KEY_TEST>` — clave **anon/publishable** del proyecto TEST (segura para el navegador; el gateway de Supabase la exige para rutear a la Edge Function) |

- Si usás el cliente **Supabase JS** (`supabase.functions.invoke('portal-api', { body })`), ambos headers (`apikey` + `Authorization`) se setean solos a partir de la sesión.
- Con `fetch` plano: agregá `apikey` manualmente y tomá el JWT de `supabase.auth.getSession()`.
- **No** poner en el navegador la `secret`/`service_role` ni el `VITA_HMAC_SECRET`: viven solo en el gateway.

### CORS

- Estado actual: `Access-Control-Allow-Origin: *`. Headers permitidos: `authorization, x-client-info, apikey, content-type`. Métodos: `POST, OPTIONS`.
- **Pendiente P-C-7:** restringir el origin al del Portal Operativo antes de exponerlo fuera de TEST. Origin TEST = `<ORIGIN_PORTAL_TEST>` (placeholder; ej. **no vinculante** de desarrollo local: `http://localhost:5173`). No bloqueante para construir el frontend en TEST mientras el ACAO sea `*`.

---

## 4. Autenticación y sesión

La autenticación es **Supabase Auth** (esto es lo que el diseño original llamó "A01"; **no** es una acción de catálogo, es la capa de auth).

Flujo:

1. **Login** con Supabase Auth (email + password de las identidades del portal en TEST, ej. `vicky@vitadelta.test`, `franco@vitadelta.test`, `jenny@vitadelta.test`).
2. Se obtiene un **JWT de sesión** (`access_token`).
3. Toda llamada a `portal-api` incluye `Authorization: Bearer <jwt>` (+ `apikey`).
4. **Refresh** de sesión: lo maneja Supabase Auth; renovar el `access_token` antes de que expire.
5. **Logout:** cerrar la sesión de Supabase Auth y descartar el token.
6. **Sesión vencida:** el siguiente request responde `no_autorizado` (HTTP 200 + envelope) → el frontend manda a re-login.

**Primera llamada tras el login: `sesion.contexto` (A02)** — devuelve `{ nombre, rol, acciones }`, donde `acciones` es la lista de `action` que el rol puede invocar = **base del menú**.

Comportamiento esperado:

| Situación | Respuesta del gateway | Qué hace el frontend |
|---|---|---|
| Sin JWT / JWT inválido / expirado | `{ ok:false, error:{ code:"no_autorizado" } }` (HTTP 200) | re-login |
| Usuario válido pero **sin fila** en `portal_usuarios` o `activo=false` | `no_autorizado` | re-login / avisar que no tiene acceso al portal |
| Rol existe pero **no habilitado** para la acción | `rol_no_permitido` | ocultar/deshabilitar esa acción para el rol |
| `action` no reconocida | `accion_desconocida` | error de programación del frontend; corregir |

> No hay 401. Auth y autorización se entregan como envelope con HTTP 200 (D-FE-04).

---

## 5. Sobre de request

Forma general:

```json
{
  "action": "nombre.accion",
  "payload": { },
  "idempotency_key": "solo-A11-top-level"
}
```

Reglas:

- **`action`** — requerido, string no vacío. Si falta → `payload_invalido` ("falta action").
- **`payload`** — objeto. Si se omite, el gateway lo normaliza a `{}`. Para acciones sin parámetros se manda `{}`. **No-objeto** (string/array/número) → `payload_invalido` (no se coerciona).
- **`idempotency_key`** (top-level) — **solo legítima para A11** (`needsIdempotencyKey`). Regex `^[A-Za-z0-9_-]{8,64}$`. Para el resto de acciones el gateway no la lee del sobre. **Atención:** la key de **A10 NO va acá** — va dentro de `payload` (D-FE-02).
- **REJECT-UNKNOWN por acción:** cada acción declara sus claves permitidas; una clave extra en `payload` → `payload_invalido` (`clave no permitida en payload: <k>`).
- **Campos de control prohibidos** (top-level, para **toda** acción): `actor`, `rol`, `nonce`, `source_event`, `creado_por`, `request_ts`. Cualquiera de ellos → `payload_invalido`. (La `idempotency_key` **no** está prohibida.) En A11 estos campos también se rechazan **dentro** del payload (y ahí se suma `idempotency_key`, que en A11 debe ir sibling, no en payload).

---

## 6. Modelo de respuesta

Éxito:

```json
{ "ok": true, "data": { } }
```

Error:

```json
{ "ok": false, "error": { "code": "codigo", "message": "...", "detail": null } }
```

- **`ok`** es la única señal de éxito/error. El frontend ramifica por `body.ok` (D-FE-04), **no** por status HTTP.
- **HTTP status:** 200 para todo resultado manejado (éxito y error). **500** solo para crash de infra (envelope con `code:"error_interno"`).
- **`detail`** suele ser `null` para errores que vienen de n8n. Excepción útil: en A11, una violación de constraint llega como `payload_invalido` con `detail.constraint` (nombre de la constraint), aprovechable para mensajes específicos.
- **`message`** es texto curado; para errores de infraestructura el gateway impone el texto (no se confía en el del backend).

---

## 7. Catálogo de acciones (13)

Tabla maestra:

| Cód | `action` | Tipo | Roles | `idempotency_key` |
|---|---|---|---|---|
| A02 | `sesion.contexto` | Edge | jenny · vicky · socio | — |
| A03 | `calendario.limpieza` | lectura | jenny · vicky · socio | — |
| A04 | `calendario.operativo` | lectura | vicky · socio | — |
| A05 | `reserva.detalle` | lectura | vicky · socio | — |
| A06 | `prereservas.activas` | lectura | vicky · socio | — |
| A12 | `cobranza.saldos` | lectura | vicky · socio | — |
| A24 | `historico.reservas` | lectura | vicky · socio | — |
| A25 | `ingresos.cobrados_periodo` | lectura | vicky · socio | — |
| A13 | `gastos.listado` | lectura | vicky · socio | — |
| A07 | `reserva.crear_manual` | escritura | vicky · socio | no (key interna del wrapper) |
| A08 | `bloqueo.crear_manual` | escritura | vicky · socio | no (guard por conflicto) |
| A10 | `cobranza.registrar_saldo` | escritura | vicky · socio | **sí — en `payload`** |
| A11 | `cargar.gasto_interno` | escritura | vicky · socio | **sí — sibling de `payload`** |

Convenciones de los detalles: campos marcados con `?` son opcionales; en las lecturas, **ausente o `null` = sin filtro**, salvo donde se indique (A25 trata `null` distinto de omitido — ver A25). Floor contable duro = **2026-07-01** (D-NEG-02).

---

### A02 · `sesion.contexto` (Edge · lectura de contexto)

- **Roles:** jenny, vicky, socio.
- **`idempotency_key`:** no.
- **Payload:** `{}` (se ignora).
- **Response `data`:** `{ nombre: string, rol: "jenny"|"vicky"|"socio", acciones: string[] }`. `acciones` = los `action` permitidos para el rol (base del menú).
- **Errores:** `no_autorizado`.
- **UX:** llamarla apenas hay sesión; construir el menú con `acciones`.

---

### A03 · `calendario.limpieza` (lectura · HTML temporal)

- **Roles:** jenny, vicky, socio (la única lectura que ve jenny).
- **`idempotency_key`:** no.
- **Payload:** `{}`.
- **Response `data`:** `{ formato: "html", html: string }`. HTML completo con todo el texto dinámico **escapado**. **Render directo** (no parsear como datos). Contrato temporal (D-FE-03); JSON formal = P-C-3.
- **Errores:** `no_autorizado`.
- **UX:** inyectar `html` en un contenedor/iframe.

---

### A04 · `calendario.operativo` (lectura · HTML temporal)

- **Roles:** vicky, socio (jenny → `rol_no_permitido`).
- **`idempotency_key`:** no.
- **Payload:** `{}`.
- **Response `data`:** `{ formato: "html", html: string }`. Calendario operativo de 120 días, con montos. Render directo.
- **Errores:** `rol_no_permitido`, `no_autorizado`.
- **UX:** render directo del HTML. Jenny no debe ver esta acción.

---

### A05 · `reserva.detalle` (lectura · objeto)

- **Roles:** vicky, socio.
- **`idempotency_key`:** no.
- **Payload:**

| Campo | Tipo | Req | Reglas |
|---|---|---|---|
| `id_reserva` | number | sí | entero positivo estricto (safe integer, > 0); no strings, ni decimales |

REJECT-UNKNOWN (claves extra → `payload_invalido`).

- **Response `data`:** `{ reserva: {...}, pagos: [...] }`.
  - `reserva`: `id_reserva`, `cabana`, `fecha_checkin`, `fecha_checkout`, `hora_checkin`, `hora_checkout`, `personas`, `estado`, `huesped_nombre`, `huesped_telefono`, `huesped_email`, `monto_total`, `saldo_real` (recomputado desde pagos confirmados seña/saldo). Montos numéricos crudos.
  - `pagos`: líneas de pago confirmadas.
  - **Privacidad:** nombre/teléfono/email; **sin** DNI ni notas internas.
- **Errores:** `payload_invalido` (id inválido), `no_encontrado` (0 filas), `rol_no_permitido`, `no_autorizado`.
- **UX:** acción-objeto → `no_encontrado` significa "no existe esa reserva".

---

### A06 · `prereservas.activas` (lectura · lista)

- **Roles:** vicky, socio.
- **`idempotency_key`:** no.
- **Payload:** `{}`.
- **Response `data`:** `{ filas: [...] }`. Pre-reservas vigentes (`ORDER BY expira_en, id_pre_reserva`). **Lista vacía → `filas:[]` con `ok:true`** (nunca `no_encontrado`).
- **Errores:** `rol_no_permitido`, `no_autorizado`.
- **UX:** lista; vacío es resultado válido.

---

### A12 · `cobranza.saldos` (lectura · lista)

- **Roles:** vicky, socio.
- **`idempotency_key`:** no.
- **Payload:** `{}`.
- **Response `data`:** `{ filas: [...] }`. Reservas `confirmada`/`activa` con `saldo_real > 0`. `saldo_real = monto_total − SUM(pagos confirmados seña/saldo)`. Huésped nombre/teléfono/email. **Lista vacía → `filas:[]` con `ok:true`**.
- **Errores:** `rol_no_permitido`, `no_autorizado`.
- **UX:** lista de saldos a cobrar.

---

### A24 · `historico.reservas` (lectura · buscador operativo paginado)

- **Roles:** vicky, socio.
- **`idempotency_key`:** no.
- **Payload (todos opcionales, REJECT-UNKNOWN):**

| Campo | Tipo | Default | Reglas |
|---|---|---|---|
| `fecha_desde` | string `YYYY-MM-DD` | floor `2026-07-01` | se **clampea** al floor (no rechaza) |
| `fecha_hasta` | string `YYYY-MM-DD` | `null` (sin cota) | `>= fecha_desde` |
| `id_cabana` | number | `null` (todas) | entero > 0 |
| `estado` | string | `null` (todos) | enum: `confirmada`, `activa`, `completada`, `cancelada`, `cancelada_con_cargo`, `conflicto_pendiente` |
| `texto` | string | — | ILIKE sobre nombre/apellido/teléfono/email; trim; vacío = sin filtro |
| `limit` | number | 50 | entero; clamp [1, 200] |
| `offset` | number | 0 | entero >= 0 |

- **Response `data`:** `{ filas: [...], limit, offset, total }`. `filas` incluye `id_cabana` **y** `cabana`, montos numéricos, `saldo_real` (puede ser **negativo**). `total` = universo filtrado (`COUNT(*) OVER()`). Privacidad: nombre/teléfono/email; sin DNI ni notas internas.
- **Errores:** `payload_invalido`, `rol_no_permitido`, `no_autorizado`.
- **UX:** buscador paginado. **No** es histórico contable: puede incluir reservas futuras y **no** sirve para liquidación ni reemplaza el calendario A04.

---

### A25 · `ingresos.cobrados_periodo` (lectura · caja percibida)

- **Roles:** vicky, socio.
- **`idempotency_key`:** no.
- **Payload (opcionales, REJECT-UNKNOWN):**

| Campo | Tipo | Default | Reglas |
|---|---|---|---|
| `periodo_desde` | string `YYYY-MM-DD` | floor `2026-07-01` | se clampea al floor |
| `periodo_hasta` | string `YYYY-MM-DD` | **hoy** (si se **omite**) | **híbrido estricto:** omitido → default hoy (sin check de inversión); explícito **string** → YMD válido y, tras el clamp, `>= periodo_desde`; **`null`/no-string/mal formado → `payload_invalido`** |
| `limit` | number | 50 | clamp [1, 200] |
| `offset` | number | 0 | entero >= 0 |

> Diferencia con A13: en A25, `periodo_hasta: null` **rebota** (`payload_invalido`). En A13, `null` se trata como omitido. No uniformar.

- **Response `data`:** `{ periodo_desde, periodo_hasta, total_cobrado, total, por_tipo:[...], por_medio:[...], por_mes:[...], otros_movimientos:{ por_tipo:[...] }, filas:[...], limit, offset }`.
  - `total_cobrado` = **solo seña + saldo confirmados** (en centavos).
  - `otros_movimientos` (extra/ajuste/reembolso) es **informativo**: no suma, no neto.
  - Bucket por **mes de `created_at`**. Agregados sobre el universo completo; `filas` paginada.
  - Cuadres: `Σ por_medio = Σ por_tipo = total_cobrado` **siempre**; `Σ filas = total_cobrado` **solo con página completa**.
- **Errores:** `payload_invalido`, `rol_no_permitido`, `no_autorizado`.
- **UX:** reporte de ingresos por período (caja percibida = plata que entró, por fecha de pago).

---

### A13 · `gastos.listado` (lectura · gastos por período contable)

- **Roles:** vicky, socio.
- **`idempotency_key`:** no.
- **Payload (opcionales, REJECT-UNKNOWN):**

| Campo | Tipo | Default | Reglas |
|---|---|---|---|
| `periodo_desde` | string `YYYY-MM-DD` | floor `2026-07-01` | se **trunca a primer día de mes**, luego clampa al floor |
| `periodo_hasta` | string `YYYY-MM-DD` | **mes actual** (si se omite **o** es `null`) | **híbrido laxo:** omitido **o `null`** → default mes actual (sin check); string → YMD, truncado a mes, tras el clamp `>= periodo_desde` a nivel mes; **otro tipo/mal formado → `payload_invalido`** |
| `clase` | string | sin filtro | enum `A`, `C`, `D`, `E` |
| `id_zona` | number | sin filtro | entero > 0 |
| `id_cabana` | number | sin filtro | entero > 0 |
| `pagador_tipo` | string | sin filtro | enum `socio`, `caja` |
| `q` | string | sin filtro | trim 1..120; ILIKE sobre `etiqueta` + `comentario` |
| `limit` | number | 50 | clamp [1, 200] |
| `offset` | number | 0 | entero >= 0 |

- **Response `data`:** `{ periodo_desde, periodo_hasta, total_gastos, por_clase:[...], filas:[...], limit, offset }`.
  - `total_gastos` = `SUM(monto)` (en centavos). `por_clase` = `[{ clase, monto, n }]`.
  - `filas`: 20 columnas por fila (incluye `moneda`, default `ARS`); IDs BIGINT → **número**; `socio_pagador_nombre`/`zona`/`cabana` por LEFT JOIN.
  - **Vacío → `total_gastos:0, por_clase:[], filas:[]`, `ok:true`**.
- **Errores:** `payload_invalido`, `rol_no_permitido`, `no_autorizado`.
- **UX:** reporte de gastos por **período contable** (eje = día 1 del mes). El `periodo` contable ≠ fecha de pago.

---

### A07 · `reserva.crear_manual` (escritura)

- **Roles:** vicky, socio.
- **`idempotency_key`:** **el frontend no la manda.** El wrapper deriva idempotencia interna para `crear_prereserva`; la respuesta trae `idempotent_match` para indicar si fue un re-hit idempotente.
- **Payload (REJECT-UNKNOWN):**

| Campo | Tipo | Req | Reglas |
|---|---|---|---|
| `id_cabana` | number | sí | entero > 0 |
| `fecha_in` | string `YYYY-MM-DD` | sí | **inclusive** |
| `fecha_out` | string `YYYY-MM-DD` | sí | **exclusive**; `> fecha_in` |
| `personas` | number | sí | entero >= 1 |
| `monto_total` | number | sí | > 0 finito |
| `monto_sena` | number | sí | `0 <= seña <= total` |
| `canal_pago_esperado` | string | sí | enum: `transferencia_bancaria`, `transferencia_mp`, `mp_link`, `cripto`, `efectivo` |
| `medio_pago` | string | sí | mismo enum que `canal_pago_esperado` |
| `huesped` | object | sí | `{ nombre (req, no vacío), telefono?, email? }` — requiere **teléfono (>=6 dígitos) o email válido**. REJECT-UNKNOWN dentro de `huesped` |
| `mascotas` | boolean | no | default `false` |
| `detalle_mascotas` | string | no | |
| `ninos` | string | no | |
| `notas` | string | no | |
| `notas_reserva` | string | no | |
| `hora_checkin_solicitada` | string `HH:MM[:SS]` | no | |
| `hora_checkout_solicitada` | string `HH:MM[:SS]` | no | |

- **Response `data`:** `{ id_reserva, id_pre_reserva, id_huesped, idempotent_match }`. `idempotent_match:true` ⇒ el submit cayó sobre una reserva ya existente (no se duplicó).
- **Errores:** `payload_invalido`, `conflicto` (solapamiento/no disponible), `rol_no_permitido`, `no_autorizado`, `estado_incierto`.
- **UX:** ante `estado_incierto`, **no** reintentar a ciegas → reconsultar (A24/A05/A04). `actor`/`creado_por`/`rol`/`source_event`/`nonce` los inyecta el backend.

---

### A08 · `bloqueo.crear_manual` (escritura)

- **Roles:** vicky, socio.
- **`idempotency_key`:** **no** (sin key; guard natural por solapamiento → `conflicto`).
- **Payload (REJECT-UNKNOWN):**

| Campo | Tipo | Req | Reglas |
|---|---|---|---|
| `id_cabana` | number | **sí** | entero > 0. **El bloqueo total no se expone en el portal** (decisión 8D): `id_cabana` es obligatorio |
| `fecha_desde` | string `YYYY-MM-DD` | sí | |
| `fecha_hasta` | string `YYYY-MM-DD` | sí | `> fecha_desde` |
| `motivo` | string | sí | enum: `mantenimiento`, `uso_propio`, `tormenta`, `overbooking`, `otro` |
| `descripcion` | string | no | |

- **Response `data`:** `{ id_bloqueo, id_cabana, tipo_bloqueo }`.
- **Errores:** `payload_invalido`, `conflicto` (solapa con otro bloqueo/reserva), `rol_no_permitido`, `no_autorizado`, `estado_incierto`.
- **UX:** `conflicto` = el rango se solapa. Sin key: un doble-submit del mismo rango rebota `conflicto`; ante `estado_incierto`, reconsultar (A24) antes de reintentar.

---

### A10 · `cobranza.registrar_saldo` (escritura · idempotente)

- **Roles:** vicky, socio.
- **`idempotency_key`:** **sí, DENTRO de `payload`** (`payload.idempotency_key`).
- **Payload (REJECT-UNKNOWN):**

| Campo | Tipo | Req | Reglas |
|---|---|---|---|
| `id_reserva` | number | sí | entero > 0 |
| `monto` | number | sí | > 0 finito; máx 2 decimales; `<= 9999999999.99` |
| `medio_pago` | string | sí | enum: `efectivo`, `transferencia_bancaria`, `transferencia_mp`, `cripto` (**sin `mp_link`** — es carga de saldo ya cobrado) |
| `idempotency_key` | string | sí | `^[A-Za-z0-9_-]{8,64}$` — **va acá, en el payload** |
| `notas` | string | no | |

- **Response `data`:** `{ id_pago, saldo_real_actual, ... }`. `saldo_real_actual` = saldo recomputado post-commit. En re-hit idempotente exacto, `id_pago` apunta al pago ya existente.
- **Errores:** `payload_invalido`; `conflicto` (`excede_saldo`, `idempotency_mismatch`, `estado_no_cobrable`, `saldo_ya_cancelado`); `no_encontrado` (la reserva no existe); `rol_no_permitido`; `no_autorizado`; `estado_incierto`; `error_interno`.
- **Idempotencia:** misma key + mismos campos exactos (`id_reserva`+`tipo='saldo'`+`medio_pago`+`monto`+actor) → **idempotente** (devuelve el pago existente). Misma key + algún campo distinto → `idempotency_mismatch` → `conflicto`.
- **UX:** ante `conflicto` mostrar el `message` (sobrepago/mismatch). Ante `estado_incierto`, reconsultar (A12/A05) antes de reintentar.

---

### A11 · `cargar.gasto_interno` (escritura · idempotente, key sibling)

- **Roles:** vicky, socio.
- **`idempotency_key`:** **sí, TOP-LEVEL (sibling de `payload`).** No va dentro del payload. Regex `^[A-Za-z0-9_-]{8,64}$`.
- **Payload (13 claves, REJECT-UNKNOWN; campos de control rechazados también dentro del payload):**

| Campo | Tipo | Req | Reglas |
|---|---|---|---|
| `fecha` | string `YYYY-MM-DD` | sí | |
| `periodo` | string `YYYY-MM-DD` | no | día 1 del mes; si se omite, lo deriva la función (primer día del mes de `fecha`) |
| `clase` | string | sí | enum `A`, `C`, `D`, `E` |
| `clase_sugerida` | string | no | enum `A`, `C`, `D`, `E` |
| `etiqueta` | string | sí | no vacío |
| `monto` | number | sí | > 0 finito → `numeric(12,2)` |
| `id_zona` | number | no | entero > 0 |
| `id_cabana` | number | no | entero > 0 |
| `pagador_tipo` | string | sí | enum `socio`, `caja` |
| `id_socio_pagador` | number | no | entero > 0 |
| `medio_pago` | string | no | |
| `comentario` | string | no | |
| `comprobante_url` | string | no | |

> **Coherencia de negocio** (clase × zona/cabaña, pagador, comentario obligatorio según clase, horas de trabajo → socio, período día 1, etc.) la imponen las **18 constraints** de `gastos_internos`. Una violación llega como `payload_invalido` con **`detail.constraint`** (nombre de la constraint) → aprovechable para mensajes específicos.

- **Response `data`:** contiene al menos `id_gasto` (el gasto creado; en re-hit idempotente vuelve el **mismo** `id_gasto`).
- **Errores:** `payload_invalido` (incluye violaciones de constraint con `detail.constraint`); `conflicto` (`nonce_replay`/`payload_mismatch`/`actor_mismatch` — todos llegan como `conflicto`); `rol_no_permitido` (jenny); `no_autorizado`; `estado_incierto`.
- **Idempotencia:** misma key + mismo payload + mismo actor → **idempotente** (mismo `id_gasto`); misma key + payload distinto → `conflicto`; misma key + actor distinto → `conflicto`. El **anti-replay de `nonce`** es server-side (el `nonce` se deriva de la firma HMAC); el frontend **no lo ve ni lo calcula**.
- **UX:** ante `conflicto`, mostrar el `message`. Ante `estado_incierto`, reconsultar (A13) antes de reintentar.

---

## 8. Errores y tratamiento UX

El gateway solo deja pasar códigos de una allowlist; cualquier otro (ej. un SQLSTATE crudo) se enmascara como `error_entorno`. Se agrupan en dos familias.

### Familia A — alcanzables por el frontend

| Código | Significado | Cuándo aparece | Tratamiento sugerido |
|---|---|---|---|
| `no_autorizado` | sin sesión válida o sin acceso al portal | JWT ausente/inválido/expirado; usuario sin `portal_usuarios` o `activo=false` | **re-login** |
| `rol_no_permitido` | el rol no está habilitado para la acción | jenny pide algo económico; o acción fuera del rol | ocultar/deshabilitar la acción para ese rol |
| `accion_desconocida` | `action` no existe en el CATALOG | bug del frontend (typo / acción futura) | corregir el frontend |
| `payload_invalido` | falla de forma/validación del request | campo faltante, tipo erróneo, clave no permitida, campo de control, key inválida, constraint (A11) | mostrar **validación** (usar `message` / `detail.constraint`); **no** reintentar igual |
| `no_encontrado` | objeto inexistente | A05/A10 con `id_reserva` que no existe | mensaje "no existe"; refrescar la lista de origen |
| `conflicto` | choque de estado/negocio | solapamiento (A07/A08), sobrepago/mismatch (A10), nonce/payload/actor mismatch (A11) | mostrar el `message`; **no** reintentar el mismo submit a ciegas |
| `estado_incierto` | escritura cuyo resultado no se pudo confirmar | timeout/red/respuesta no confiable hacia n8n en una escritura | **reconsultar la lectura companion** (§9) antes de reintentar; **no** reenvío automático |
| `error_interno` | error interno controlado | excepción manejada (ej. P0001 de A10) | reintento manual acotado; si persiste, contactar admin |

### Familia B — canal gateway↔n8n / "no debería pasar"

El frontend no firma ni manda `ts`/`nonce`, así que **no gatilla** estos códigos en operación normal. Si aparecen, es un problema de configuración del backend.

`firma_invalida` · `ts_fuera_de_ventana` · `raw_body_ausente` · `ambiente_incorrecto` · `error_entorno`

→ Tratamiento: mensaje genérico de "error del sistema, reintentá más tarde / contactá al administrador". **No** reintentar a ciegas; **no** tratar como validación del usuario.

> Regla clave (D-FE-06): en **escrituras**, ante `estado_incierto`, el frontend **no reintenta a ciegas**; reconsulta la lectura correspondiente o muestra un mensaje de verificación manual.

---

## 9. Idempotencia de escrituras

| Acción | `idempotency_key` | Dónde viaja | Quién la genera | Companion para reconsultar ante incertidumbre |
|---|---|---|---|---|
| A07 `reserva.crear_manual` | no (interna del wrapper) | — | wrapper (server) | A24 / A05 / A04 |
| A08 `bloqueo.crear_manual` | no | — | — (guard por solapamiento) | A24 |
| A10 `cobranza.registrar_saldo` | sí | **`payload.idempotency_key`** | frontend | A12 / A05 |
| A11 `cargar.gasto_interno` | sí | **top-level (sibling de `payload`)** | frontend | A13 |

Para A10 y A11 (D-FE-07):

- **Cuándo se genera:** por **intento de submit**.
- **Retry del mismo submit** (timeout/red/UI): **reusar la misma key**.
- **Nuevo submit intencional:** **nueva key**.
- **Regex:** `^[A-Za-z0-9_-]{8,64}$`.
- **Semántica:** misma key + mismo payload + mismo actor → **idempotente** (misma respuesta/ID); misma key + payload distinto → **conflicto** (`payload_mismatch` / `idempotency_mismatch`); misma key + actor distinto → **conflicto** (`actor_mismatch`).
- **A11** además tiene anti-replay de `nonce`, pero **el frontend no lo ve ni lo calcula** (lo deriva el backend de la firma HMAC).

---

## 10. Visibilidad por rol

| Acción | jenny | vicky | socio |
|---|:---:|:---:|:---:|
| A02 `sesion.contexto` | ✓ | ✓ | ✓ |
| A03 `calendario.limpieza` | ✓ | ✓ | ✓ |
| A04 `calendario.operativo` | — | ✓ | ✓ |
| A05 `reserva.detalle` | — | ✓ | ✓ |
| A06 `prereservas.activas` | — | ✓ | ✓ |
| A12 `cobranza.saldos` | — | ✓ | ✓ |
| A24 `historico.reservas` | — | ✓ | ✓ |
| A25 `ingresos.cobrados_periodo` | — | ✓ | ✓ |
| A13 `gastos.listado` | — | ✓ | ✓ |
| A07 `reserva.crear_manual` | — | ✓ | ✓ |
| A08 `bloqueo.crear_manual` | — | ✓ | ✓ |
| A10 `cobranza.registrar_saldo` | — | ✓ | ✓ |
| A11 `cargar.gasto_interno` | — | ✓ | ✓ |

- **jenny** (limpieza): ve **solo** `sesion.contexto` + `calendario.limpieza`. **Cero contenido económico.** Cualquier otra acción → `rol_no_permitido`.
- **vicky** (operación): todas las lecturas y todas las escrituras del CATALOG 13.
- **socio** (Franco/Rodrigo/Remo): igual que vicky en el MVP construido (acceso total a lo operativo/económico de las 13). La contabilidad societaria (A14–A23) es futura y solo socio.

Agrupación funcional mínima (sugerida; layout detallado va en Etapa 2):

- **Inicio / sesión:** A02.
- **Calendarios:** A03 (todos), A04 (vicky/socio).
- **Reservas:** A05, A06, A24, A07.
- **Bloqueos:** A08.
- **Cobranzas:** A12, A10.
- **Económico / período:** A25 (ingresos), A13 (gastos), A11 (cargar gasto).

> El menú no se hardcodea: se arma con `acciones` de `sesion.contexto`, que ya viene filtrado por rol.

---

## 11. Convenciones de datos

- **Fechas:** `YYYY-MM-DD`. **Horas:** `HH:MM[:SS]`.
- **`fecha_in` inclusive / `fecha_out` exclusive** (reservas); rangos de bloqueo `fecha_desde`/`fecha_hasta`.
- **`periodo`** (gastos): primer día de mes. La fecha de pago ≠ período contable.
- **Floor contable duro:** `2026-07-01`. Aplica a `fecha_desde` (A24), `periodo_desde` (A25, A13). Nada anterior se muestra/liquida.
- **`periodo_hasta`:** **A25 estricto** (`null` → `payload_invalido`); **A13 laxo** (`null` = omitido). No uniformar.
- **Montos:** números en pesos. Los agregados de A25 (`total_cobrado`) y A13 (`total_gastos`) se calculan en **centavos** (sin float drift); el contrato los entrega como número.
- **IDs:** BIGINT del dominio (`id_reserva`, `id_cabana`, `id_pago`, `id_gasto`, etc.) se normalizan a **número** en el contrato (están muy por debajo de 2^53). El frontend los trata como `number`.
- **`id_cabana` en TEST = 1–5.** **No** asumir IDs portables entre TEST y OPS.
- **Listas vacías → `ok:true`** con la lista en `[]` (A06, A12, A24.filas, A25.filas, A13.filas). `no_encontrado` queda para acciones-objeto (A05; A10 si la reserva no existe).
- **Gate de ambiente:** TEST. El gateway sale de `VITA_AMBIENTE`, no del payload.

---

## 12. Acciones futuras / no implementadas

No tienen contrato detallado en v1. **Marca:** `No implementado en CATALOG 13. Fuera de contrato v1.`

- **A01 — Autenticación del portal.** No es una acción de catálogo: es la capa **Supabase Auth** (§4).
- **A09 — Editar / levantar bloqueo.** No existe hoy (8D solo crea). Capa futura.
- **A14–A18 — Lecturas societarias** (saldo socios, participación, cuenta corriente/mayor, etc.). Post-MVP, solo rol socio.
- **A19–A23 — Escrituras societarias** (snapshot de liquidación, etc.). Post-MVP, solo rol socio.
- **Contrato JSON formal de calendarios (P-C-3).** Hoy A03/A04 son HTML temporal (D-FE-03).

---

## 13. Versionado del contrato

- `CONTRATO_FRONTEND_PORTAL_v1.md` corresponde a **CATALOG 13** (Carril C Slice 3b cerrado, TEST).
- Si entra una acción nueva, o cambia un payload/response/forma de error, se emite **v1.1** (cambio compatible/aditivo) o **v2** (cambio que rompe), según impacto.
- El frontend **pinea** la versión del contrato que implementa (D-FE-01).

---

## 14. Hallazgos / pendientes

Registrados sin parchear (el gateway vigente manda):

1. **CORS abierto (`*`) — P-C-7.** Restringir al origin del portal antes de exponer fuera de TEST. **Nota:** el comentario inline del código cita "(P-C-4)", pero P-C-4 es otro ítem (hardening post-MVP: rate-limiting / rotación HMAC / refresh fino). El pendiente real de CORS es **P-C-7** (`Pendiente_pre_produccion.md`). Comentario de código stale; sin impacto funcional.
2. **Origin del frontend TEST sin decidir.** Placeholder `<ORIGIN_PORTAL_TEST>`; `http://localhost:5173` es solo ejemplo no vinculante de desarrollo local.
3. **`apikey` (anon) requerida además del JWT.** Confirmado en los smokes (header `apikey` = anon de TEST). Es publishable (browser-safe); documentar su valor real al construir, no se hardcodea acá.
4. **Transporte dual de `idempotency_key` (A10 en payload / A11 sibling).** Es la trampa principal del contrato (D-FE-02). Dos ejemplos de escritura en §15 lo cubren.
5. **A03/A04 devuelven HTML, no JSON estructurado** (D-FE-03). Migración a JSON = P-C-3 (post-MVP).
6. **Sin 401.** Todo error es HTTP 200 + envelope; solo 500 = crash de infra (D-FE-04).
7. **`estado_incierto` requiere reconsulta, no retry ciego** (D-FE-06). Companion por acción en §9.
8. **Necesidades para Etapa 2 (Frontend TEST):** preparación/reset controlado de TEST para UAT (seeds QA por rol) es **etapa separada**; este contrato solo deja anotado el requisito. OPS intacto.

---

## 15. Ejemplos por familia

Helper neutro (fetch). El stack se fija en Etapa 2; esto es ilustrativo.

```js
async function callPortal(action, payload = {}, extra = {}) {
  const res = await fetch(
    "https://bdskhhbmcksskkzqkcdp.supabase.co/functions/v1/portal-api",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": ANON_KEY_TEST,            // anon/publishable de TEST
        "Authorization": "Bearer " + jwt,   // access_token de Supabase Auth
      },
      body: JSON.stringify({ action, payload, ...extra }),
    }
  );
  const body = await res.json();   // HTTP 200 para todo resultado manejado
  if (!body.ok) {                  // ramificar por body.ok, NO por res.status
    throw body.error;             // { code, message, detail }
  }
  return body.data;
}
```

**(1) Lectura simple — A06 `prereservas.activas`**

```json
// request
{ "action": "prereservas.activas", "payload": {} }
// response
{ "ok": true, "data": { "filas": [] } }   // lista vacía es válida
```

**(2) Lectura con filtros — A24 `historico.reservas`**

```json
// request
{
  "action": "historico.reservas",
  "payload": { "fecha_desde": "2026-07-01", "id_cabana": 3, "estado": "activa", "limit": 20, "offset": 0 }
}
// response
{ "ok": true, "data": { "filas": [ /* ... */ ], "limit": 20, "offset": 0, "total": 7 } }
```

**(3) Escritura A10 — `cobranza.registrar_saldo` (key DENTRO de payload)**

```json
// request
{
  "action": "cobranza.registrar_saldo",
  "payload": {
    "id_reserva": 12,
    "monto": 45000,
    "medio_pago": "transferencia_bancaria",
    "idempotency_key": "cob-20260622-12-a1B2c3D4",
    "notas": "saldo final"
  }
}
// response
{ "ok": true, "data": { "id_pago": 88, "saldo_real_actual": 0 } }
```

**(4) Escritura A11 — `cargar.gasto_interno` (key SIBLING de payload)**

```json
// request
{
  "action": "cargar.gasto_interno",
  "payload": {
    "fecha": "2026-08-15",
    "clase": "C",
    "etiqueta": "Gas envasado",
    "monto": 25000,
    "pagador_tipo": "caja",
    "id_cabana": 4
  },
  "idempotency_key": "gas-20260622-a1B2c3D4e5"
}
// response
{ "ok": true, "data": { "id_gasto": 41 } }
```

**(5) Error típico — `rol_no_permitido` (jenny pide A04)**

```json
// request (JWT de jenny)
{ "action": "calendario.operativo", "payload": {} }
// response (HTTP 200)
{ "ok": false, "error": { "code": "rol_no_permitido", "message": "rol jenny no habilitado para calendario.operativo", "detail": null } }
```

---

*Fin de `CONTRATO_FRONTEND_PORTAL_v1.md` — v1 / CATALOG 13 / TEST. Refleja el gateway `portal-api` de Slice 3b. No modifica backend, n8n, OPS ni el canónico.*
