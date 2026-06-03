# 8C_EJECUCION.md — Bitácora de ejecución de Etapa 8C

# Calendarios visuales por evento (HTML operativo + HTML limpieza + Sheet de resguardo)

**Documento base de diseño:** `Docs/Arquitectura/ARQUITECTURA_ETAPA_8C_CALENDARIOS_VISUALES.md v1.3`.
**Entorno objetivo:** Supabase TEST (proyecto `vita-delta-test`) + n8n cloud (`federicosecchi.app.n8n.cloud`).
**Schema canónico:** `6B_SCHEMA_SQL.md v1.7.3` (no modificado por 8C: los calendarios son de solo lectura).
**Bitácora previa relacionada:** `Docs/Bitacora/8B_CIERRE.md` (Etapa 8B cerrada el 2026-05-30; dejó el punto de extensión post-`confirmar_reserva`).
**Documento de cierre:** `Docs/Bitacora/8C_CIERRE.md`.

---

## Propósito de este documento

Registrar la ejecución de los tres bloques de la Etapa 8C, uno por uno, con:

- Fecha de implementación.
- Resultado de validación funcional en TEST.
- Decisiones tomadas durante la implementación.
- Gotchas operativos descubiertos.
- Referencia a los workflows y artefactos exportados.

Cada entrada se cierra cuando el bloque está implementado, validado en TEST y los criterios del documento de diseño se cumplieron. 8C cierra con validación completa en TEST; el smoke read-only en OPS queda como actividad posterior (ver `8C_CIERRE.md` §8).

---

## Convenciones de la bitácora

- **Una entrada por bloque.** Bloque 1 (HTML operativo), Bloque 2 (HTML limpieza), Bloque 3 (Sheet de resguardo).
- **Estado posible:** `EN PROGRESO`, `OK`, `BLOQUEADO`, `DIFERIDO`.
- **Formato de fechas:** ISO 8601 (`YYYY-MM-DD`).
- **Validación:** marcar cada caso con ✅ / ❌ / ⏭ (no ejecutado).
- **Decisiones operativas y gotchas:** se anotan al final de cada entrada y, si son reutilizables, se replican en `Docs/Operacional/Lecciones_Aprendidas.md` (L-8C-XX) y `Docs/Operacional/DECISIONES_NO_REABRIR.md` (D-8C-XX).
- **Restricción transversal:** ningún workflow de 8C escribe en tablas transaccionales ni invoca funciones del motor. La única escritura de toda la etapa es la del Bloque 3 sobre su Google Sheet de resguardo.

---

## Estado general de la etapa

| Bloque | Tipo | Workflow | Estado | Fecha cierre |
|---|---|---|---|---|
| 1 — HTML operativo | Ventana en vivo (n8n+Webhook) | `vita_w8c_html_operativo__TEST` (`8vFm5cb4vrhwMCi5`) | ✅ OK | 2026-05-31 |
| 2 — HTML limpieza | Ventana en vivo (n8n+Webhook) | `vita_w8c_html_limpieza__TEST` (`OcLCHBVfatqr8ljs`) | ✅ OK | 2026-05-31 |
| 3 — Sheet de resguardo | Foto estática (n8n+HTTP a Sheets) | `vita_w8c_sheet_resguardo__TEST` (`ufvxuLE9C2JiCUpi`) | ✅ OK | 2026-06-01 |
| 4 — 8C-bis (alerta) | — | — | DIFERIDO | (posterior, doc propio) |

**Aclaración de naturaleza de los bloques:** los Bloques 1 y 2 son **ventanas en vivo** — el workflow se dispara al abrir la URL del Webhook, lee Supabase en ese instante y devuelve el HTML del estado actual. No requieren ningún disparo externo ni repintado tras una reserva. El Bloque 3 es la excepción: una **foto estática** en un Google Sheet que se regenera por ejecución (hoy manual). El punto de extensión de 8B aplica solo al repintado del resguardo (y a 8C-bis), no a los HTML.

---

## Verificación read-only previa (común a los tres bloques)

Antes de construir, se verificaron los contratos reales contra TEST (lectura):

- **6 vistas** disponibles (paridad con OPS): `vista_calendario`, `vista_calendario_semanal`, `vista_disponibilidad`, `vista_limpieza_semana`, `vista_ocupacion`, `vista_prereservas_activas`.
- **Tabla `bloqueos`:** `id_bloqueo`, `id_cabana` (nullable), `fecha_desde`, `fecha_hasta`, `motivo` (CHECK: mantenimiento/uso_propio/tormenta/overbooking/otro), `descripcion`, `creado_por`, `activo`, `source_event`, `created_at`.
- **Bloqueo total `id_cabana IS NULL`** queda **fuera** del EXCLUDE `exc_bloqueos_no_overlap` (que solo cubre específicos): el pintado se evalúa con `EXISTS`, sin asumir unicidad por celda.
- **`vista_calendario` filtra solo `confirmada`/`activa`** (no `completada`): motivó una 4ta query de salidas sobre `reservas`+`huespedes` que incluye `completada`, para no perder el recambio de una saliente ya completada.
- **`crear_bloqueo(payload jsonb) → jsonb`** confirmada; W6 `__TEST` (`vita_w06_crear_bloqueo_supabase__TEST`, id `aK21K0f3vPSTbTTM`) confirmado como vía de siembra de bloqueos para las baterías.

---

## Bloque 1 — HTML operativo

**Estado:** ✅ OK — 2026-05-31.

### Estructura del workflow

```
Webhook GET /w8c-op-test (Basic Auth nativo, responseMode: responseNode)
  → Postgres: vista_disponibilidad (grilla 120 días, rango exclusive [hoy, hoy+120))
  → Postgres: vista_calendario (detalle por intersección de rango)
  → Postgres: bloqueos (activos, intersección)
  → Postgres: reservas+huespedes (salidas, incluye 'completada')
  → Code: render HTML (color + grilla 3 filas/cabaña + pestañas por mes + rama de error)
  → Respond to Webhook (text/html; charset=utf-8, status 200/503)
```

- Nodos: Webhook v2.1, 4× Postgres v2.6 (`vita_supabase_test`, solo `SELECT`, `onError: continueRegularOutput` + `alwaysOutputData`), Code v2, Respond to Webhook v1.5.
- Mecanismo de Basic Auth verificado (no asumido): Webhook v2.1 soporta `authentication: basicAuth` nativo con credencial `httpBasicAuth`; respuesta HTML vía `responseMode: responseNode` + Respond to Webhook `respondWith: text` + header `Content-Type` explícito. Distinto del Form Trigger de 8B.

### Decisiones de diseño y correcciones durante la ejecución

- **Fix de salida:** el día de check-in mostraba además la hora de salida (`13:00–10:00`). Corregido (Opción 1): entrada = `huésped · Np · horaIN`; check-out sin recambio = `Sale <nombre> · <hora>`; intermedios verdes lisos.
- **Pestañas por mes:** agregada navegación por mes (mes actual activo por defecto, JS mínimo de mostrar/ocultar). Aprobada. El artefacto pasó de v2 a v3 (`code_node_render_v3_pestanias.js`).
- **Incidencia de credenciales (L-8C-01):** al crear vía SDK, n8n auto-asignó los 4 Postgres a `vita_supabase_dev` (entorno equivocado). Corregido a mano a `vita_supabase_test`.

### Validación funcional (batería sembrada)

| Caso | Resultado |
|---|---|
| Verde entrada sin hora de salida | ✅ |
| Verde día de salida sin recambio ("Sale X · hora") | ✅ |
| Verde multi-día (intermedios lisos) | ✅ |
| Rojo recambio de huéspedes (datos del entrante) | ✅ |
| Rojo inicio bloqueo + checkout ("Sale Remo / Inicio bloqueo · mantenimiento") | ✅ |
| Rojo fin bloqueo + checkin ("Fin bloqueo / Entra Juan Kazka") | ✅ |
| Cadena de rojos consecutivos (Tokio 11-12-13) | ✅ |
| Gris específico (Arrebol 18-20; el 21 ya no gris = exclusive) | ✅ |
| Gris total (5 cabañas 25-26) | ✅ |
| Pestañas por mes (mes actual activo, navegación) | ✅ |

Prioridad **rojo > gris > verde > blanco** y `fecha_hasta` exclusive confirmadas. Rama de error: HTML 503 sin stack/queries/credenciales.

### Artefactos exportados

- Workflow `vita_w8c_html_operativo__TEST` (id `8vFm5cb4vrhwMCi5`, inactivo).
- Nodo Code v3: `code_node_render_v3_pestanias.js`.
- Template sanitizado para GitHub: `vita_w8c_html_operativo__TEMPLATE.json` (sin instanceId/ids de credenciales/webhookId; placeholders `CRED_BASIC_AUTH_OPERATIVO`/`CRED_POSTGRES_TEST`).

### Conclusión Bloque 1

Calendario operativo funcionando como ventana en vivo. Aprobado por Franco. Inactivo hasta smoke OPS.

---

## Bloque 2 — HTML limpieza

**Estado:** ✅ OK — 2026-05-31.

### Estructura del workflow

```
Webhook GET /w8c-limp-test (Basic Auth propia y separada, responseMode: responseNode)
  → Postgres: vista_disponibilidad (7 días)
  → Postgres: vista_calendario (detalle SIN montos)
  → Postgres: bloqueos
  → Postgres: reservas+huespedes (salidas, incluye 'completada')
  → Postgres: vista_limpieza_semana (mascotas/notas/personas)
  → Code: render HTML (grilla 7 días, paleta con amarillo, cruce de mascotas/notas)
  → Respond to Webhook (text/html; charset=utf-8)
```

- 7 nodos: Webhook v2.1, 5× Postgres v2.6 (`vita_supabase_test`, solo `SELECT`), Code v2, Respond to Webhook v1.5.

### Decisiones de diseño

- **Camino 2:** motor del operativo filtrado (grilla, ocupación, colores) + cruce con `vista_limpieza_semana` para mascotas/notas. Elegido sobre camino 1 (sin mascotas/notas) y camino 3 (vista de limpieza con intermedios blancos). Da el contrato completo de limpieza reutilizando el motor validado del operativo.
- **Paleta de limpieza** (distinta del operativo a propósito): rojo (salida+entrada) > gris (bloqueo) > **amarillo (salida = hay que limpiar)** > verde (entrada u ocupado intermedio) > blanco. El amarillo para salida es la diferencia clave con el operativo (donde la salida sin recambio es verde).
- **Contrato de privacidad (doble barrera):** la query de detalle NO selecciona `monto_total`/`monto_saldo`, y el render no los muestra. Notas operativas para Jennifer = decisión explícita (D-8C-06b); las notas visibles solo llevan info operativa, nunca comercial.
- Basic Auth **propia y separada** del operativo y del formulario 8B (D-8C-20). La credencial quedó como "vista calendario limpieza".

### Correcciones durante la ejecución

- **Incidencia de credenciales (refuerza L-8C-01):** n8n auto-asignó los 5 Postgres a `vita_supabase_dev` Y el Webhook a la credencial Basic Auth del formulario 8B (`Formulario-reservas`). Corregido a mano: 5 Postgres → `vita_supabase_test`; Webhook → credencial Basic Auth nueva y exclusiva de limpieza.
- **Fix de fechas (L-8C-02):** las fechas llegaban de Postgres como timestamp completo (`2026-06-01T00:00:00.000Z`); la etiqueta del día esperaba `YYYY-MM-DD` y salía `undefined ...T00:00:00.000Z/06`. Corregido con función `ymd()` que normaliza a `YYYY-MM-DD` (`slice(0,10)`) aplicada en todos los puntos de lectura de fechas (días, predicados, bloqueos, cruce, etiqueta). Riesgo latente equivalente anotado para el operativo (no observado, no urgente). Artefacto resultante: `code_node_limpieza_v3_fix_fechas.js`.

### Validación funcional (batería sembrada, próximos 7 días)

| Caso | Resultado |
|---|---|
| Entrada verde con teléfono/nota | ✅ |
| Salida amarilla ("Sale jose · 10:00") | ✅ |
| Recambio rojo (Guatemala "Sale Natalín / Entra Jose Alberto") | ✅ |
| Bloqueo gris | ✅ |
| Mascotas y notas (cruce con `vista_limpieza_semana`, 🐾/📝) | ✅ |
| Encabezados de día correctos ("Lun 01/06 … Dom 07/06") tras fix de fechas | ✅ |
| **Sin ningún monto** (contrato de privacidad) | ✅ verificado |

### Artefactos exportados

- Workflow `vita_w8c_html_limpieza__TEST` (id `OcLCHBVfatqr8ljs`, inactivo).
- Nodo Code v3: `code_node_limpieza_v3_fix_fechas.js`.
- Template sanitizado para GitHub: pendiente de exportar si se sube (Franco lo pasará).

### Conclusión Bloque 2

Calendario de limpieza funcionando como ventana en vivo, sin montos, con mascotas/notas. Aprobado por Franco. Inactivo hasta smoke OPS.

---

## Bloque 3 — Sheet de resguardo

**Estado:** ✅ OK — 2026-06-01.

### Objetivo

Volcar el calendario operativo (CON montos) a un Google Sheet como respaldo offline consultable, por si el endpoint HTML / n8n no están disponibles.

### Estructura del workflow

```
Trigger manual ("Regenerar resguardo")
  → 4× Postgres (mismas lecturas del operativo: grilla/detalle/bloqueos/salidas, vita_supabase_test)
  → Code: armar matriz (grilla cabañas×días, meses apilados, CON montos)
  → HTTP Request: Sheet clear (POST values/A1:AZ1000:clear, cred OAuth Google)
  → HTTP Request: Sheet update (PUT values/A1, USER_ENTERED, body = matriz del Code)
```

- 8 nodos. Sheet destino: "Calendario Resguardo", ID `17WgfMbNKo9RAIh09FiZNgqMqqqnL1xDMQ47XMAH_sP0`. Credencial OAuth: "Google Sheets — VISTA" (id `2fDnnceDNtgignH0`).

### Decisiones de diseño

- **Contenido:** el operativo volcado a Sheets (CON montos), no el de limpieza.
- **Disparo:** manual por ahora; workflow autónomo, preparado para que 8B lo invoque post-`confirmar_reserva` a futuro (Forma A: 8B llama al resguardo).
- **Formato (D-8C-23):** grilla cabañas×días con **meses apilados verticalmente** en una sola hoja. Se evaluó y descartó pestañas-por-mes (una hoja por mes) por fragilidad: manejar creación/limpieza dinámica de hojas agrega riesgo en la pieza que debe ser más confiable. Apilar meses (scroll vertical) es más robusto.
- **Sin colores (D-8C-23):** priorizar datos completos y legibles; pintar fondos en Sheets va por otra API (`batchUpdate` con formato) y es costoso/frágil.
- **Estrategia clear + write:** POST `values:clear` sobre `A1:AZ1000` + PUT `values:update` desde `A1`, para reflejar el estado actual sin residuos.
- **NO Apps Script (D-8C-22):** el resguardo se escribe desde n8n vía HTTP a la API REST de Sheets. Reintroducir Apps Script (jubilado en 6A) para el resguardo —la pieza de menor criticidad— empeoraría la arquitectura sin beneficio. La lógica vive en un solo lugar (n8n), versionable y trazable.

### Decisión técnica clave (camino A vs B) — L-8C-03

El nodo nativo `n8n-nodes-base.googleSheets` v4.7 está orientado a **columnas nombradas** (ResourceMapper) y no vuelca bien una **grilla arbitraria con celdas multilínea y encabezados de mes intercalados**. Dos caminos: (A) HTTP Request v4.4 contra la API REST de Sheets (`values:update`/`values:clear`), que acepta matriz cruda desde un rango; (B) replantear a filas planas, que el nodo nativo soporta naturalmente. **Se eligió camino A** para conservar la grilla (prioridad: que sea casi igual de legible que el operativo). El HTTP usa `authentication: predefinedCredentialType` + `nodeCredentialType: googleSheetsOAuth2Api`, reutilizando la credencial OAuth existente.

### Verificación previa (test de escritura) — L-8C-05

Antes de construir el workflow completo (8 nodos), se creó un workflow mínimo (`vita_w8c_test_escritura_sheet__TEST`, id `hZ7RkrgiDv1VJXQW`) con un solo HTTP PUT que escribió una celda de prueba en `A1`. Resultado: ✅ escribió correctamente → confirmó que la credencial "Google Sheets — VISTA" tiene permiso de escritura sobre el Sheet y que el camino A funciona. Validó el supuesto más riesgoso (permiso OAuth) antes de invertir en el workflow completo.

### Correcciones durante la ejecución

- **Incidencia de credenciales (L-8C-01):** los 4 Postgres se auto-asignaron a `vita_supabase_dev` → corregidos a `vita_supabase_test`.
- **HTTP sin auto-credencial (L-8C-04):** n8n informó que los 2 nodos HTTP Request fueron "skipped during credential auto-assignment". Se asignó manualmente "Google Sheets — VISTA" a ambos.
- **Referencia del body:** el nodo `Sheet: update` lee el body del nodo Code por nombre (`$("Code: armar matriz").item.json.body`) para que la respuesta del clear intermedio no lo pise.

### Validación funcional

| Caso | Resultado |
|---|---|
| Test de escritura previo (permiso OAuth) | ✅ celda A1 escrita |
| Corrida completa clear+write | ✅ grilla por meses, montos, recambios, bloqueos |
| Marca de "Última actualización" visible (D-8C-19b) | ✅ |

Detalle menor observado: el ancho de columnas no se autoajusta al contenido. No se corrige (el formato va por otra API; el ancho ajustado a mano se conserva entre regeneraciones porque clear+write solo toca valores). Queda como mejora opcional.

### Artefactos exportados

- Workflow `vita_w8c_sheet_resguardo__TEST` (id `ufvxuLE9C2JiCUpi`, inactivo).
- Workflow auxiliar `vita_w8c_test_escritura_sheet__TEST` (id `hZ7RkrgiDv1VJXQW`) — se puede conservar como referencia o borrar.
- Nodo Code: `code_node_resguardo_v1.js`.
- Template sanitizado para GitHub: `vita_w8c_sheet_resguardo__TEMPLATE.json` (sin instanceId/ids de credenciales; ID del Sheet → `SHEET_ID_PLACEHOLDER`; placeholders `CRED_POSTGRES_TEST`/`CRED_GOOGLE_SHEETS`).

### Conclusión Bloque 3

Resguardo funcionando como foto estática regenerable. Aprobado por Franco. Inactivo.

---

## Cierre de la etapa

Los tres bloques principales de 8C quedaron **implementados y validados en TEST**. El smoke read-only en OPS y la alerta 8C-bis quedan como trabajos posteriores independientes (ver `8C_CIERRE.md` §8 y §10). Decisiones D-8C-01 a D-8C-23; lecciones L-8C-01 a L-8C-05.

**Lecciones replicadas a `Lecciones_Aprendidas.md`:**
- L-8C-01 — n8n auto-empareja credenciales por nombre al crear/importar y puede caer en el entorno equivocado.
- L-8C-02 — las fechas de Postgres pueden llegar como timestamp completo; normalizar con `slice(0,10)`.
- L-8C-03 — para grilla arbitraria en Sheets usar HTTP a la API REST, no el nodo nativo.
- L-8C-04 — los nodos HTTP Request no reciben auto-asignación de credencial.
- L-8C-05 — validar el supuesto técnico más riesgoso con un workflow mínimo antes de construir el completo.

**Decisiones replicadas a `DECISIONES_NO_REABRIR.md`:** D-8C-22 (resguardo vía HTTP, no Apps Script) y D-8C-23 (formato del resguardo).

*Fin de la bitácora de ejecución de 8C.*
