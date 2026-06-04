# 8D_CIERRE.md — Cierre formal Etapa 8D

**Etapa:** 8D — Capa de bloqueos operativos (Form Trigger n8n)
**Estado:** ✅ Cerrada (validada en TEST + operativa en OPS)
**Fecha de cierre:** 2026-06-04
**Entorno de validación:** TEST (`vita-delta-test`) — batería funcional completa
**Entorno de operación:** OPS (`vita-delta-ops`) — workflow `__OPS` activo y en uso real
**Documento de diseño:** `ARQUITECTURA_ETAPA_8D_BLOQUEOS_OPERATIVOS.md v1.1`
**Contrato verificado:** `crear_bloqueo(payload jsonb)` — read-only contra TEST (2026-06-03)
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3`
**Autores:** Franco (titular) + Claude (arquitecto)
**Decisiones registradas:** D-8D-01 a D-8D-09

---

## 1. Resumen ejecutivo

La Etapa 8D construyó la **capa de bloqueos operativos**: un formulario n8n (Form Trigger,
Basic Auth, usable desde celular) con el que Franco, Rodrigo, Vicky o Remo crean un bloqueo
de una cabaña en **una sola acción**, sin tocar SQL ni el workflow `w06` por dentro. El
bloqueo creado aparece automáticamente en gris en los calendarios de 8C.

Es la subetapa más simple de la Etapa 8: una sola llamada a `crear_bloqueo()`, sin cadena,
sin pagos, sin compensación. El operador elige cabaña por nombre, fechas (modelo `[)`),
motivo y descripción opcional, y recibe un resultado único en lenguaje humano: bloqueo
creado (con el rango expresado como "último día inclusive" + "se libera el…"), o un mensaje
claro de por qué no se pudo.

El motor `crear_bloqueo` valida todo (cabaña, fechas, motivo, y los tres tipos de
conflicto: reserva, pre-reserva, bloqueo solapado), por lo que el formulario es solo capa
de UX y mensajería; la barrera real es la función SQL. 8D **no modificó el schema**.

Se diseñó (verificación read-only del contrato → diseño aprobado v1.1), se validó en TEST
con batería funcional, y se promovió a OPS donde el workflow `__OPS` quedó **activo y en
uso real** (primer bloqueo real ya creado). Con 8D, **la Etapa 8 (operación real interna)
queda completa**: el equipo puede cargar reservas (8B), ver el estado (8C) y crear bloqueos
(8D), todo autoservicio sobre OPS.

---

## 2. Qué se construyó

- **Workflow TEST:** `vita_w8d_bloqueo__TEST` (id `GIfBlI6xCnrkH2Y4`, 9 nodos), validado.
- **Workflow OPS:** `vita_w8d_bloqueo__OPS` (9 nodos), **activo y en uso real**. Path
  `w8d-bloqueo-ops`, credencial `vita_supabase_ops`, Basic Auth propia, `TEST_OPS = 'ops'`.
- **Template sanitizado (GitHub):** `vita_w8d_bloqueo__TEMPLATE.json` (sin instanceId, sin
  ids de credenciales, sin webhookId, sin versionId; placeholders `CRED_POSTGRES_OPS`,
  `CRED_BASIC_AUTH_BLOQUEO`, `PATH_PLACEHOLDER`; conserva `TEST_OPS = 'ops'`).

### 2.1 Topología del workflow

```
Form Bloqueo (Form Trigger, Basic Auth, responseMode: lastNode, timezone BA)
  → Validar y Normalizar (Code: mapeo cabaña→id, operador→string, motivo→string,
                          source_event, fechas; valida capa)
  → IF validacion capa
       ├─ true  → Build Payload (Code: jsonb) → PG: crear_bloqueo (executeQuery,
       │           Continue On Fail + Always Output Data) → Normalize (Code: envelope)
       │           → Build Response (Code: mensaje humano) → Form Ending (completion)
       └─ false → Error Capa (Code: arma envelope de entrada) → Build Response → Form Ending
```

Las dos ramas del IF convergen en Build Response, que decide el mensaje final según el
envelope (éxito / conflicto / entrada / técnico) y termina en Form Ending.

### 2.2 Campos del formulario

| Campo | Control | Notas |
|---|---|---|
| Cabaña | Desplegable (Bamboo/Madre Selva/Arrebol/Guatemala/Tokio) | nombre → id (1-5). Sin opción "TODAS" |
| Fecha desde | Date | inclusive |
| Fecha hasta / liberación | Date | exclusive: ese día YA NO queda bloqueado |
| Motivo | Desplegable (5 etiquetas) | → string del CHECK |
| Descripción | Textarea | opcional |
| Creado por | Desplegable (Franco/Rodrigo/Vicky/Remo) | trazabilidad |

---

## 3. Contrato real verificado (read-only TEST) y hallazgos

`crear_bloqueo(payload jsonb) → jsonb`. Payload con 7 claves (`id_cabana` opcional,
`fecha_desde`/`fecha_hasta`/`motivo`/`creado_por`/`source_event` obligatorias,
`descripcion` opcional), patrón defensivo `NULLIF(TRIM(...))`.

**Éxito:** `{ ok: true, id_bloqueo, id_cabana, tipo_bloqueo }`.
**Errores:** `payload_invalido`, `fechas_invalidas`, `motivo_invalido`, `cabana_no_existe`
(entrada); `conflicto_con_reserva`, `conflicto_con_prereserva`, `bloqueo_solapado`
(conflicto).

Hallazgos clave de la verificación:
1. **La función valida TODO** → el formulario es solo UX + mensajería.
2. **Un bloqueo NO convive con reservas:** rechaza si hay reserva confirmada/activa o
   pre-reserva vigente solapada.
3. **Concurrencia resuelta** en la función (`pg_advisory_xact_lock` global + por cabaña).
4. **Triple protección de solapamiento:** chequeo en función + EXCLUDE constraint (parcial:
   solo `activo AND id_cabana NOT NULL`) + `EXCEPTION WHEN exclusion_violation`.
5. **Tabla `bloqueos`:** 10 columnas; `id_cabana`/`descripcion` nullables; CHECK de fechas
   y de motivo. El bloqueo total (`id_cabana IS NULL`) está soportado por la función pero
   NO se expone en el formulario (D-8D-03).

---

## 4. Manejo de errores (dos familias)

**Familia A — Conflictos (mensaje unificado, D-8D-04/05):** los tres conflictos
(`conflicto_con_reserva`, `conflicto_con_prereserva`, `bloqueo_solapado`) →
"Esas fechas no están disponibles para bloquear. Revisá el calendario." Sin distinguir
tipo, sin exponer IDs ni datos de reservas.

**Familia B — Errores de entrada (diferenciados):**
- `fechas_invalidas` → "La fecha 'hasta / liberación' tiene que ser posterior a la 'desde'."
- `cabana_no_existe` → "La cabaña seleccionada no es válida."
- `motivo_invalido` → "El motivo seleccionado no es válido."
- `payload_invalido` → "Faltan datos obligatorios…"

**Técnico** (nodo Postgres falló, vía Continue On Fail): "No se pudo registrar el bloqueo
por un problema técnico. Reintentá en unos minutos."

**Éxito (lenguaje humano, D-8D-08):** "Guatemala bloqueada desde el 20/06 hasta el 21/06
inclusive. Se libera el 22/06. (Motivo: Uso propio. N° 5.)" — el "último día inclusive" se
calcula como `fecha_hasta − 1` solo para el texto, sin alterar el dato (`[)`).

---

## 5. Decisiones registradas (D-8D-01 a D-8D-09)

| ID | Decisión |
|---|---|
| D-8D-01 | 8D = Form Trigger que llama a `crear_bloqueo()` en una acción; el motor valida, la capa es UX |
| D-8D-02 | Una cabaña por vez; varias cabañas = varias cargas separadas |
| D-8D-03 | NO se expone el bloqueo total (`id_cabana IS NULL`); no se usa en la práctica; el motor lo sigue soportando |
| D-8D-04 | Mensajes de conflicto unificados (Familia A); errores de entrada diferenciados (Familia B) |
| D-8D-05 | El mensaje de conflicto NO expone IDs ni datos de reservas/pre-reservas |
| D-8D-06 | `source_event` = `n8n_<marcador>_w8d_bloqueo_<operador>_manual`, operador en minúscula sin espacios |
| D-8D-07 | Basic Auth propia de 8D, separada de 8B y 8C |
| D-8D-08 | `fecha_hasta` exclusive; campo "Fecha hasta / liberación" + ayuda + mensaje de éxito en lenguaje humano |
| D-8D-09 | 8D SOLO CREA bloqueos; no hay edición ni baja desde el formulario; corregir/levantar requiere intervención manual controlada (`activo=false` vía SQL aprobado). Riesgo aceptado para el MVP |

---

## 6. Validación

### 6.1 En TEST — ✅ completa

| Caso | Resultado |
|---|---|
| Bloqueo válido en cabaña libre | ✅ creado, aparece gris en calendario 8C |
| `fecha_hasta <= fecha_desde` | ✅ rebote "hasta posterior a desde" |
| Conflicto con otro bloqueo | ✅ mensaje unificado "no disponibles" |
| Conflicto con reserva confirmada/activa | ✅ mensaje unificado |
| Cada motivo del CHECK | ✅ persiste el string correcto |
| Mensaje de éxito en lenguaje humano | ✅ último día inclusive + día de liberación |
| Verificación `[)` | ✅ el día `fecha_hasta` NO queda bloqueado |
| Trazabilidad | ✅ `creado_por` y `source_event` correctos |

### 6.2 En OPS — ✅ workflow activo, primer bloqueo real creado

El workflow `__OPS` quedó construido, con los ajustes de promoción aplicados (credencial
`vita_supabase_ops`, `TEST_OPS = 'ops'`, path `w8d-bloqueo-ops`, Basic Auth propia) y
**activado (Publish)**. Se creó un primer bloqueo real desde el formulario OPS, verificado
en el calendario operativo de OPS.

---

## 7. Incidencias resueltas durante la ejecución

1. **Auto-asignación de credenciales (L-8C-01, recurrente):** al crear vía SDK, n8n asignó
   el Postgres a `vita_supabase_dev` y el Form Trigger a la Basic Auth del formulario 8B
   (`Formulario-reservas`). Corregido a mano en TEST y OPS.
2. **Interpolación del payload en el nodo Postgres (L-8D-01):** la primera prueba devolvió
   "Problema técnico". Causa real: NO era la interpolación de la query (que funcionó), sino
   que el nodo Postgres devuelve el jsonb **envuelto en la columna `resultado`**
   (`SELECT crear_bloqueo(...) AS resultado`), y el nodo Normalize leía `item.ok` en vez de
   `item.resultado.ok`, clasificando un éxito como error técnico. Corregido desenvolviendo
   la columna: `const item = raw.resultado !== undefined ? raw.resultado : raw;`. El bloqueo
   en realidad se había creado bien en todos los intentos (la base nunca falló).
3. **`source_event` con marcador 'test' en un bloqueo OPS temprano:** un bloqueo real se
   creó antes de cambiar `TEST_OPS` a `'ops'`, quedando etiquetado `n8n_test_...`. Decisión:
   se acepta como está (un solo registro; corregirlo implicaría escritura directa a OPS sin
   beneficio proporcional, y el `log_cambios` asociado quedaría con la etiqueta vieja igual).
   Los bloqueos siguientes quedan bien etiquetados.

---

## 8. Lo que NO se hizo en 8D (alcance respetado)

- **Bloqueo total del complejo:** soportado por el motor, NO expuesto (D-8D-03).
- **Selección múltiple de cabañas:** una por vez (D-8D-02).
- **Edición / baja de bloqueos:** 8D solo crea (D-8D-09). Levantar o corregir un bloqueo
  requiere intervención manual controlada (`activo=false` vía SQL). Riesgo documentado.
- **Modificación de schema o de `crear_bloqueo`:** la función se usa tal cual.

---

## 9. Artefactos entregados

- `ARQUITECTURA_ETAPA_8D_BLOQUEOS_OPERATIVOS.md v1.1` — diseño aprobado.
- `vita_w8d_bloqueo__TEST` (id `GIfBlI6xCnrkH2Y4`) — workflow validado.
- `vita_w8d_bloqueo__OPS` — workflow productivo, activo.
- `vita_w8d_bloqueo__TEMPLATE.json` — template sanitizado para GitHub.
- `8D_CIERRE.md` — este documento.

---

## 10. Lecciones (para `Lecciones_Aprendidas.md`)

- **L-8D-01:** El nodo Postgres de n8n devuelve el resultado de una función
  `SELECT funcion(...) AS resultado` **envuelto en la columna** (`item.resultado`), no en la
  raíz del item. Los nodos Code que consumen ese resultado deben desenvolver la columna
  antes de leer sus campos. Un envelope de "éxito" leído en el nivel equivocado se confunde
  con error técnico.
- **L-8D-02:** Para pasar un payload JSON a una función SQL desde el nodo Postgres, la
  interpolación `'{{ JSON.stringify($json.payload) }}'::jsonb` funciona, pero la query
  parametrizada (`$1::jsonb` + Query Parameters) es más robusta ante comillas y caracteres
  especiales. Recomendada para entradas con texto libre (descripción).
- **L-8D-03 (refuerza L-8C-01):** Al promover un workflow a OPS, además de la credencial hay
  que revisar marcadores de entorno embebidos en el código (ej. `TEST_OPS`), el `path` del
  trigger (para no colisionar con TEST) y la Basic Auth. Un marcador de entorno olvidado no
  rompe nada funcional pero ensucia la trazabilidad.

---

## 11. Cierre de la Etapa 8 completa

Con 8D cerrada, **la Etapa 8 (operación real interna) queda completa**:

| Subetapa | Descripción | Estado |
|---|---|---|
| 8A | Levantamiento del entorno OPS | ✅ Cerrada |
| 8B | Capa de carga interna de reservas (formulario) | ✅ Cerrada |
| 8C | Calendarios visuales por evento (operativo + limpieza + resguardo) | ✅ Cerrada (TEST + OPS) |
| 8D | Capa de bloqueos operativos (formulario) | ✅ Cerrada (TEST + OPS) |

El equipo opera el complejo con tres acciones autoservicio sobre OPS: **cargar reservas,
ver el estado y crear bloqueos**. El sistema sostiene la operación diaria sobre Supabase
como fuente de verdad, sin planillas manuales.

**Pendientes que NO son de la Etapa 8** (trabajos posteriores independientes):
- **8C-bis** — Alerta por reserva próxima (notificación a Rodrigo y Jennifer por mail o
  Telegram). Documento propio; no reabre cierres.
- **Edición/baja de bloqueos** — si se vuelve necesaria (hoy es manual, D-8D-09).
- **Apertura al exterior** (etapas futuras grandes): PROD público, web de reservas, bot
  conversacional (Claude API), WhatsApp/Instagram (Meta API), webhook MercadoPago real.
- Residual de permisos de tabla en DEV (hallazgo A5 / pendiente 1.7).

*Fin del cierre formal de 8D. Formulario de bloqueos construido, validado en TEST y
operativo en OPS. Con esta subetapa se cierra la Etapa 8: la operación real interna del
complejo (reservas, calendarios y bloqueos) funciona de punta a punta sobre Supabase + n8n.*
