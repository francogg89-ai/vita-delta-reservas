# 8C_CIERRE.md — Cierre formal Etapa 8C

**Etapa:** 8C — Calendarios visuales por evento (operativo + limpieza + resguardo)
**Estado:** ✅ Cerrada (tres bloques principales validados en TEST)
**Fecha de cierre:** 2026-06-01
**Entorno de validación:** TEST (`vita-delta-test`) — batería funcional completa con datos sembrados
**Entorno de operación:** OPS (`vita-delta-ops`) — smoke read-only NO ejecutado todavía (ver §8)
**Documento de diseño:** `ARQUITECTURA_ETAPA_8C_CALENDARIOS_VISUALES.md v1.3`
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3`
**Autores:** Franco (titular) + Claude (arquitecto)
**Decisiones registradas:** D-8C-01 a D-8C-23 (+ sub-decisiones 06b/12b/13b/14b/19b)

---

## 1. Resumen ejecutivo

La Etapa 8C construyó los **calendarios visuales por evento**: dos vistas HTML servidas
por n8n Cloud y un Google Sheet de resguardo, todos **derivados de solo lectura** desde
Supabase como fuente de verdad. Ningún componente de 8C escribe en las tablas
transaccionales ni invoca funciones del motor: son lecturas (`SELECT` sobre vistas y
tablas) que se presentan de tres formas distintas según el público.

- **Calendario operativo** (Franco/Rodrigo/Vicky/Remo): grilla día×cabaña de 120 días
  autodesplazante, con reservas confirmadas/activas, bloqueos, montos, horarios y
  teléfono. Navegación por pestañas de mes. Es una **ventana en vivo**: se arma de cero
  en cada visita a la URL, siempre refleja el estado del momento.
- **Calendario de limpieza** (Jennifer): grilla de 7 días, contrato reducido **sin
  montos**, con mascotas y notas operativas. También ventana en vivo.
- **Sheet de resguardo**: el operativo volcado a un Google Sheet como respaldo offline
  consultable. A diferencia de los HTML, es una **foto estática** que se regenera por
  ejecución (hoy manual).

Cada bloque se diseñó con verificación read-only de los contratos reales contra TEST
antes de construir, y se **validó íntegramente en TEST** con batería sembrada (reservas
vía 8B, bloqueos vía W6 `__TEST`). Los tres workflows quedan **inactivos** y apuntando a
TEST; el smoke read-only en OPS queda pendiente (§8), por la misma prudencia de no
promover a producción sin un paso de verificación explícito.

El diseño se desarrolló incrementalmente (v1.0 → v1.3) y la lógica de pintado vive en la
capa de presentación (nodos Code), nunca en el motor: 8C **no toca schema ni funciones
SQL**.

---

## 2. Qué se construyó

- **Workflow operativo (TEST):** `vita_w8c_html_operativo__TEST` (id `8vFm5cb4vrhwMCi5`,
  6 nodos), validado, inactivo.
- **Workflow limpieza (TEST):** `vita_w8c_html_limpieza__TEST` (id `OcLCHBVfatqr8ljs`,
  7 nodos), validado, inactivo.
- **Workflow resguardo (TEST):** `vita_w8c_sheet_resguardo__TEST` (id `ufvxuLE9C2JiCUpi`,
  8 nodos), validado, inactivo.
- **Workflow auxiliar de prueba:** `vita_w8c_test_escritura_sheet__TEST` (id
  `hZ7RkrgiDv1VJXQW`) — validó el permiso de escritura OAuth sobre el Sheet; se puede
  conservar como referencia o borrar.
- **Templates sanitizados (GitHub):** `vita_w8c_html_operativo__TEMPLATE.json` y
  `vita_w8c_sheet_resguardo__TEMPLATE.json` (sin instanceId, sin ids de credenciales, sin
  webhookId, sin ID real del Sheet; placeholders). Limpieza pendiente de sanitizar si se
  sube.

### 2.1 Topología — HTML operativo

```
Webhook GET /w8c-op-test (Basic Auth propia, responseMode: responseNode)
  → Postgres: vista_disponibilidad (grilla 120 días, rango exclusive [hoy, hoy+120))
  → Postgres: vista_calendario (detalle por intersección de rango)
  → Postgres: bloqueos (activos, intersección)
  → Postgres: reservas+huespedes (salidas, incluye 'completada')
  → Code: render HTML (cálculo de color + grilla 3 filas/cabaña + pestañas por mes + rama de error)
  → Respond to Webhook (text/html; charset=utf-8, status 200/503)
```

### 2.2 Topología — HTML limpieza

```
Webhook GET /w8c-limp-test (Basic Auth propia y separada, responseMode: responseNode)
  → Postgres: vista_disponibilidad (7 días)
  → Postgres: vista_calendario (detalle SIN montos)
  → Postgres: bloqueos
  → Postgres: reservas+huespedes (salidas, incluye 'completada')
  → Postgres: vista_limpieza_semana (mascotas/notas/personas)
  → Code: render HTML (grilla 7 días, paleta con amarillo, sin montos, cruce de mascotas/notas)
  → Respond to Webhook (text/html; charset=utf-8)
```

### 2.3 Topología — Sheet de resguardo

```
Trigger manual ("Regenerar resguardo")
  → 4× Postgres (las mismas lecturas del operativo: grilla/detalle/bloqueos/salidas)
  → Code: armar matriz (grilla cabañas×días, meses apilados, CON montos)
  → HTTP Request: Sheet clear (POST values/A1:AZ1000:clear, cred OAuth Google)
  → HTTP Request: Sheet update (PUT values/A1, USER_ENTERED, body = matriz del Code)
```

- Los nodos Postgres usan `Continue On Fail` + `Always Output Data`; el nodo Code
  centraliza la decisión (render normal o HTML/aviso de error controlado).
- Escape HTML universal de todo dato (huésped, teléfono, notas, motivo) en los dos HTML.
- Comparación de fechas normalizada a `YYYY-MM-DD` (`ymd()`) — robusta a timestamps.

---

## 3. Decisiones registradas (D-8C-01 a D-8C-23)

| ID | Decisión |
|---|---|
| D-8C-01 | Dos calendarios internos derivados de solo lectura desde Supabase (fuente de verdad), sin tocar schema |
| D-8C-02 | Operativo: grilla día×cabaña 120 días autodesplazante |
| D-8C-03 | Cruce `vista_disponibilidad` (estado) × `vista_calendario` (detalle) por `id_reserva_activa = id_reserva` |
| D-8C-04 | Operativo muestra confirmadas/activas + bloqueos; NO pre-reservas; con montos/horarios/teléfono |
| D-8C-05 | Formato: HTML servido por n8n + Basic Auth (principal) + Sheet repintado (resguardo) |
| D-8C-06 | Limpieza: `vista_limpieza_semana`, 7 días; cabaña/fecha/movimiento/hora/personas/teléfono/mascotas/notas; NO montos |
| D-8C-06b | Teléfono y notas en limpieza = decisión operativa explícita; notas solo info operativa, nunca comercial |
| D-8C-09 | Orden de construcción: 1) HTML operativo, 2) HTML limpieza, 3) Sheet resguardo; 8C-bis posterior |
| D-8C-12b | Día de salida sin recambio = verde (operativo): convención visual que NO altera el modelo `[)` |
| D-8C-13b | `fecha_out`/`fecha_hasta` exclusive como invariante técnica intacta |
| D-8C-14 | El color se calcula en la capa de presentación; no se lee 1:1 del campo `estado` |
| D-8C-14b | Render: salida incluye `confirmada`/`activa`/`completada`; bloqueo con `EXISTS` sin unicidad; motivo gris = `bloqueos.motivo` |
| D-8C-17 | Celda roja bietápica (sale→entra), datos comerciales del que entra |
| D-8C-19b | "Última regeneración / actualización" visible en el Sheet de resguardo |
| D-8C-20 | Acceso: URLs y Basic Auth separados por público (operativo / limpieza), contraseñas fuertes, sin credenciales en URL, no reutilizar la del formulario 8B |
| D-8C-21 | Alerta por reserva próxima = Bloque 4 opcional (8C-bis), posterior; dispara desde `confirmar_reserva` OK si check-in ∈ [hoy, hoy+7]; no toca schema |
| D-8C-22 | Resguardo vía n8n + HTTP a la API REST de Sheets, **NO Apps Script** (argumento reforzado: reintroducirlo para el resguardo empeora la arquitectura sin beneficio) |
| D-8C-23 | Formato resguardo: grilla con meses apilados (sin pestañas en Sheets, por robustez), sin colores, clear+write; disparo manual, workflow autónomo para invocación futura desde 8B |

---

## 4. Hallazgos de la verificación read-only (TEST)

La verificación de contratos reales antes de construir reveló cosas que ajustaron el
diseño:

1. **`vista_calendario` filtra solo `confirmada`/`activa`** (no `completada`): para no
   perder el recambio de una saliente ya completada, se agregó una 4ta query de salidas
   sobre `reservas`+`huespedes` que incluye `completada` (D-8C-14b).
2. **Bloqueo total `id_cabana IS NULL` está fuera del EXCLUDE** `exc_bloqueos_no_overlap`
   (que solo cubre específicos): el pintado se evalúa con `EXISTS`, sin asumir unicidad
   por celda; un total puede solaparse con un específico o con otro total (D-8C-14b).
3. **`vista_limpieza_semana` no trae montos de origen**: el contrato de limpieza se
   respeta seleccionando columnas seguras; doble barrera (query + render).
4. **El mecanismo de Basic Auth del Webhook es nativo** (`authentication: basicAuth` con
   credencial `httpBasicAuth`), distinto del Form Trigger de 8B; respuesta HTML vía
   `responseMode: responseNode` + Respond to Webhook `respondWith: text` + header
   `Content-Type` explícito.
5. **El nodo nativo de Google Sheets (ResourceMapper) no vuelca bien una grilla
   arbitraria**: para la grilla con celdas multilínea se usó HTTP Request contra la API
   REST de Sheets (D-8C-22, L-8C-03).
6. **Las fechas de Postgres pueden llegar como timestamp completo** (`...T00:00:00.000Z`):
   se normalizan a `YYYY-MM-DD` antes de comparar/etiquetar (L-8C-02).

---

## 5. Lógica de color (capa de presentación)

**Operativo** — prioridad **rojo > gris > verde > blanco**:

| Color | Significado |
|---|---|
| Rojo | Dos eventos de transición: recambio de huéspedes, o borde de bloqueo + movimiento |
| Gris | Bloqueo (específico por cabaña o total `id_cabana IS NULL` expandido a las 5) |
| Verde | Ocupación (incl. día de entrada y día de salida sin recambio, con "Sale X · hora") |
| Blanco | Libre |

**Limpieza** — prioridad **rojo > gris > amarillo > verde > blanco** (difiere del operativo
a propósito: la salida es amarilla porque = hay que limpiar):

| Color | Significado |
|---|---|
| Rojo | Salida + entrada el mismo día (atención) |
| Gris | Bloqueo |
| Amarillo | Salida (check-out, hay que limpiar) |
| Verde | Entrada u ocupado intermedio (mismo tono) |
| Blanco | Sin movimiento |

Convención visual del día de entrada/salida (operativo): entrada muestra
`huésped · Np · horaIN` (sin hora de salida); el día de check-out muestra
`Sale <nombre> · <hora>`; días intermedios verdes lisos. La celda roja es bietápica
(Sale arriba / Entra abajo, en líneas separadas), con datos comerciales del que entra.

---

## 6. Validación en TEST — ✅ completa

Batería sembrada con reservas (vía 8B) y bloqueos (vía W6 `__TEST`).

**Operativo:**

| Caso | Resultado |
|---|---|
| Verde entrada sin hora de salida | ✅ "jose roberto · 2p · 13:00" |
| Verde día de salida sin recambio | ✅ "Sale jose · 10:00" |
| Verde multi-día (intermedios lisos) | ✅ |
| Rojo recambio de huéspedes | ✅ "Sale X / Entra Y", pagos del entrante |
| Rojo inicio bloqueo + checkout | ✅ "Sale Remo / Inicio bloqueo · mantenimiento" |
| Rojo fin bloqueo + checkin | ✅ "Fin bloqueo / Entra Juan Kazka" |
| Cadena de rojos consecutivos | ✅ Tokio 11-12-13 |
| Gris específico (una cabaña) | ✅ Arrebol 18-20; el 21 ya no gris (exclusive) |
| Gris total (las 5 cabañas) | ✅ 25-26 en las 5 |
| Pestañas por mes | ✅ mes actual activo, navegación correcta |

**Limpieza:**

| Caso | Resultado |
|---|---|
| Entrada verde con teléfono/nota | ✅ |
| Salida amarilla | ✅ "Sale jose · 10:00" |
| Recambio rojo | ✅ "Sale Natalín / Entra Jose Alberto" |
| Bloqueo gris | ✅ |
| Mascotas y notas (cruce con limpieza) | ✅ 🐾 / 📝 |
| Encabezados de día correctos | ✅ "Lun 01/06 … Dom 07/06" tras fix de fechas |
| **Sin ningún monto** | ✅ verificado (ni "$", ni "saldo", ni montos) |

**Resguardo:**

| Caso | Resultado |
|---|---|
| Test de escritura previo (permiso OAuth) | ✅ celda A1 escrita |
| Corrida completa clear+write | ✅ grilla por meses, montos, recambios, bloqueos |
| Marca de "Última actualización" visible | ✅ |

Prioridad de colores, `fecha_hasta` exclusive, celda roja bietápica y contrato de
privacidad de limpieza, todos confirmados.

---

## 7. Lo que NO se hizo en 8C (alcance respetado)

- **Smoke read-only en OPS:** pendiente (§8). Los tres workflows apuntan a TEST.
- **Activación de los workflows:** quedan inactivos hasta el smoke OPS y la decisión de
  puesta en producción.
- **8C-bis — Alerta por reserva próxima:** explícitamente **fuera del alcance de este
  cierre**. Es trabajo posterior independiente (§10), con su propio documento; no reabre
  este cierre.
- **Disparo automático del resguardo desde 8B:** el workflow del resguardo es autónomo y
  está preparado para que el punto de extensión post-`confirmar_reserva` lo invoque, pero
  ese enganche no se construyó (va junto con 8C-bis cuando se trabaje ese punto). Nota:
  los HTML operativo y limpieza NO requieren disparo — son ventanas en vivo que se
  arman al abrir la URL.
- **Autoajuste de ancho de columnas del Sheet:** mejora opcional menor; el formato va por
  otra API y el ancho fijado a mano se conserva entre regeneraciones (clear+write solo
  toca valores).
- **Modificación de schema o funciones SQL:** la verificación no reveló necesidad; 8C es
  solo presentación.
- **Bot conversacional, WhatsApp, frontend propio, PROD:** fuera de alcance.

---

## 8. Smoke OPS — 🟡 PENDIENTE

A diferencia de 8B (que cerró con smoke OPS exitoso), 8C cierra con **validación
funcional completa en TEST pero sin smoke en OPS todavía**. Los tres workflows están
construidos y validados contra TEST, e inactivos.

El smoke OPS de 8C sería de **solo lectura**: derivar los tres workflows a OPS (apuntando
a la credencial OPS y, en el resguardo, a un Sheet de OPS), abrir los endpoints y
verificar que la reserva real id 1 (Tokio, Paula Lugo, 06→07 jun) y cualquier dato real
se vean correctos. Como 8C no escribe en tablas transaccionales, el riesgo del smoke es
mínimo (los HTML son read-only; el resguardo solo escribe en su Sheet).

Este paso queda como primer ítem de los próximos pasos (§10). El cierre de 8C se firma
con los tres bloques validados en TEST; la promoción a OPS es una actividad separada y
posterior, coherente con la prudencia de verificar antes de promover.

---

## 9. Artefactos entregados

- `ARQUITECTURA_ETAPA_8C_CALENDARIOS_VISUALES.md` v1.3 — documento de diseño.
- `vita_w8c_html_operativo__TEST` (id `8vFm5cb4vrhwMCi5`) — workflow operativo validado.
- `vita_w8c_html_limpieza__TEST` (id `OcLCHBVfatqr8ljs`) — workflow limpieza validado.
- `vita_w8c_sheet_resguardo__TEST` (id `ufvxuLE9C2JiCUpi`) — workflow resguardo validado.
- `vita_w8c_test_escritura_sheet__TEST` (id `hZ7RkrgiDv1VJXQW`) — auxiliar de prueba OAuth.
- Nodos Code versionados: `code_node_render_v3_pestanias.js` (operativo),
  `code_node_limpieza_v3_fix_fechas.js` (limpieza), `code_node_resguardo_v1.js` (resguardo).
- Templates sanitizados: `vita_w8c_html_operativo__TEMPLATE.json`,
  `vita_w8c_sheet_resguardo__TEMPLATE.json`.
- `8C_CIERRE.md` — este documento.

---

## 10. Próximos pasos (post-8C)

1. **Smoke read-only en OPS** de los tres calendarios (§8): derivar a OPS, verificar con
   datos reales, decidir activación.
2. **8C-bis — Alerta por reserva próxima** (trabajo independiente, documento propio):
   dispara post-`confirmar_reserva` si el check-in cae en [hoy, hoy+7]; notificación
   interna a Rodrigo y Jennifer. Canal a decidir entre **mail** (con regla de
   notificación en cada celular) o **Telegram** (notificación push vía bot, n8n nativo) —
   no requiere esperar la decisión de WhatsApp, que es comunicación externa con huéspedes.
   Engancha en el punto de extensión de 8B, junto con el disparo automático del resguardo.
3. **Disparo automático del resguardo** desde el punto de extensión de 8B (Forma A: 8B
   invoca el workflow del resguardo), a abordar junto con 8C-bis.
4. **8D — Bloqueos operativos** (capa de uso real de bloqueos) + cierre de Etapa 8.

---

*Fin del cierre formal de 8C. Tres calendarios construidos y validados en TEST: operativo
(grilla 120 días con pestañas), limpieza (7 días sin montos para Jennifer) y resguardo
(Sheet repintado). Todos derivados de solo lectura desde Supabase, sin tocar schema ni
motor. Etapa 8C cerrada en TEST; smoke OPS y 8C-bis quedan como trabajos posteriores
independientes que no reabren este cierre.*
