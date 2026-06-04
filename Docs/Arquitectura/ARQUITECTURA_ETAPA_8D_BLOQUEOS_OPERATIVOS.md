# ARQUITECTURA ETAPA 8D — CAPA DE BLOQUEOS OPERATIVOS

**Etapa:** 8D — Capa de bloqueos operativos (Form Trigger n8n)
**Estado del documento:** diseño para aprobar (v1.0)
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3`
**Contrato verificado:** `crear_bloqueo(payload jsonb)` — read-only contra TEST (2026-06-03)
**Patrón base:** Etapa 8B (capa de carga), simplificado a una sola función
**Autores:** Franco (titular) + Claude (arquitecto)

---

## 0. Encuadre y cómo leer este documento

8D es la última subetapa de la Etapa 8 (operación real interna). Cierra el set de
acciones operativas autoservicio del equipo: **cargar reservas (8B)**, **ver el estado
(8C)** y ahora **crear bloqueos (8D)**. Es deliberadamente la más simple de las tres:
una sola llamada a `crear_bloqueo()`, sin cadena, sin pagos, sin compensación.

Este documento es **diseño para aprobar**. No se construye nada hasta el OK de Franco.
La verificación read-only del contrato ya está hecha (sección 2). Sigue la metodología:
verificación → diseño → validación en TEST → promoción a OPS.

---

## 1. Objetivo y alcance de 8D

### 1.1 Qué resuelve 8D

Un formulario n8n usable desde celular (Basic Auth) con el que Franco, Rodrigo, Vicky o
Remo crean un bloqueo de una cabaña en **una sola acción**, sin tocar SQL ni el workflow
`w06` por dentro. El operador elige cabaña por nombre, fechas, motivo y descripción
opcional, y recibe un resultado único: bloqueo creado, o un mensaje claro de por qué no
se pudo (fechas mal, o fechas no disponibles).

El bloqueo creado aparece automáticamente en gris en los calendarios de 8C (que son
ventanas en vivo y lo leen de la tabla `bloqueos`).

### 1.2 Qué queda explícitamente FUERA de 8D

- **Bloqueo total del complejo (`id_cabana IS NULL`):** el motor lo soporta, pero NO se
  expone en el formulario. Decisión operativa: nunca se usó en la práctica; si hiciera
  falta, se cubre con cargas individuales de las 5 cabañas. (Ver 9, decisión D-8D-03.)
- **Selección múltiple de varias cabañas:** una cabaña por vez. Varias cabañas = varias
  cargas separadas. Evita errores parciales y compensaciones.
- **Edición / desactivación de bloqueos existentes:** 8D solo crea. Modificar o levantar
  un bloqueo (`activo=false`) queda fuera de alcance (no hay función de "desbloquear" en
  el contrato; sería otra etapa o un manejo manual).
- **Mostrar datos de las reservas/pre-reservas en conflicto:** por decisión, el mensaje
  de conflicto NO expone IDs ni datos (D-8D-05).

### 1.3 Principios heredados que enmarcan 8D (🔒 no se reabren)

- RESERVAS / motor SQL es la fuente de verdad; el formulario es solo UX.
- Toda escritura pasa por la función `crear_bloqueo()`; sin INSERT directo a `bloqueos`.
- Modelo daterange `[)`: `fecha_desde` inclusive, `fecha_hasta` exclusive.
- TEST antes de OPS; OPS solo con smoke controlado al final.
- `source_event` obligatorio para trazabilidad.

---

## 2. Contrato real verificado (✅ read-only contra TEST, 2026-06-03)

### 2.1 `crear_bloqueo(payload jsonb) → jsonb`

**Claves del payload** (extraídas con patrón `NULLIF(TRIM(payload->>'campo'), '')`):

| Clave | Obligatoria | Tipo destino | Notas |
|---|---|---|---|
| `id_cabana` | No | BIGINT | null/vacío = bloqueo total (NO se usa en 8D) |
| `fecha_desde` | **Sí** | DATE | |
| `fecha_hasta` | **Sí** | DATE | exclusive; debe ser `> fecha_desde` |
| `motivo` | **Sí** | TEXT | CHECK: mantenimiento/uso_propio/tormenta/overbooking/otro |
| `descripcion` | No | TEXT | libre |
| `creado_por` | **Sí** | TEXT | operador |
| `source_event` | **Sí** | TEXT | trazabilidad |

**Respuesta de éxito:**
```json
{ "ok": true, "id_bloqueo": N, "id_cabana": N, "tipo_bloqueo": "cabana_especifica" }
```

**Respuestas de error** (`ok: false` + `error`):

| `error` | Causa | Naturaleza |
|---|---|---|
| `payload_invalido` | falta una clave obligatoria | entrada |
| `fechas_invalidas` | `fecha_hasta <= fecha_desde` | entrada |
| `motivo_invalido` | motivo fuera del CHECK | entrada |
| `cabana_no_existe` | la cabaña no existe en `cabanas` | entrada |
| `conflicto_con_reserva` | reserva confirmada/activa solapada | conflicto |
| `conflicto_con_prereserva` | pre-reserva vigente solapada | conflicto |
| `bloqueo_solapado` | bloqueo activo solapado (incl. EXCLUDE residual) | conflicto |

### 2.2 Hallazgos clave del contrato

1. **La función valida TODO** (cabaña, fechas, motivo, y los tres tipos de conflicto). El
   formulario NO replica validaciones críticas: es UX + mensajes. La barrera real es el
   motor (mismo principio que 8B con la capacidad).
2. **Un bloqueo NO convive con reservas:** si hay reserva confirmada/activa o pre-reserva
   vigente solapada, la función RECHAZA el bloqueo. No coexisten.
3. **Concurrencia ya resuelta:** `pg_advisory_xact_lock(10,0)` global + lock por cabaña.
   El formulario no maneja concurrencia.
4. **Triple protección de solapamiento entre bloqueos:** chequeo en la función + EXCLUDE
   constraint (`exc_bloqueos_no_overlap`, parcial: solo `activo AND id_cabana NOT NULL`) +
   `EXCEPTION WHEN exclusion_violation` para residuales.
5. **Tabla `bloqueos`:** 10 columnas; `id_cabana` y `descripcion` nullables; `activo`
   default true; `created_at` default now(). CHECK de fechas y de motivo presentes.

### 2.3 Cabañas (IDs reales) — mapeo nombre → id

Igual que 8B/8C. En TEST y OPS los IDs son 1-5:

| id_cabana | nombre |
|---|---|
| 1 | Bamboo |
| 2 | Madre Selva |
| 3 | Arrebol |
| 4 | Guatemala |
| 5 | Tokio |

(En DEV son 17-21, pero 8D se valida en TEST y se promueve a OPS, ambos 1-5.)

---

## 3. Diseño del formulario (Form Trigger)

### 3.1 Campos, tipos y controles

| Campo | Control | Obligatorio | Notas |
|---|---|---|---|
| Cabaña | Desplegable (5 nombres reales) | Sí | nombre → id en el workflow. Sin opción "TODAS" |
| Fecha desde | Date | Sí | inclusive |
| Fecha hasta | Date | Sí | exclusive (el día "hasta" NO queda bloqueado) |
| Motivo | Desplegable (5 valores) | Sí | etiquetas amigables → string del CHECK |
| Descripción | Texto libre | No | detalle opcional |
| Creado por | Desplegable (Franco/Rodrigo/Vicky/Remo) | Sí | trazabilidad |

### 3.2 Desplegable de motivo (etiqueta visible → valor persistido)

| Etiqueta visible | Persiste (CHECK) |
|---|---|
| Mantenimiento | `mantenimiento` |
| Uso propio | `uso_propio` |
| Tormenta / clima | `tormenta` |
| Overbooking | `overbooking` |
| Otro | `otro` |

### 3.3 Nota sobre el modelo `[)` en el formulario

`fecha_hasta` es exclusive: si el operador quiere bloquear del 10 al 15 inclusive, debe
poner hasta = 16. Esto es consistente con cómo funcionan las reservas en todo el sistema.
El formulario incluirá una ayuda breve junto al campo "Fecha hasta" aclarando que es el
día de "liberación" (no queda bloqueado), para evitar el error de un día de menos. (Es
una ayuda de texto, no una validación; la validación de fechas la hace el motor.)

### 3.4 Selector de operador y `source_event`

- **`creado_por`** = etiqueta del desplegable, normalizada a minúscula sin espacios:
  `franco` / `rodrigo` / `vicky` / `remo`.
- **`source_event`** (convención análoga a 8B, 🔒):
  `<marcador>_w8d_bloqueo_<operador>_manual`.
  - TEST: `n8n_test_w8d_bloqueo_<operador>_manual`
  - OPS: `n8n_ops_w8d_bloqueo_<operador>_manual`
  - Ejemplo OPS: `n8n_ops_w8d_bloqueo_franco_manual`.
- La normalización (etiqueta → string) la hace n8n en el nodo de validación.

### 3.5 Protección / acceso

Form Trigger con **Basic Auth propia de 8D** (credencial separada, no reutiliza la de los
calendarios 8C ni la del formulario 8B — coherente con D-8C-20). Contraseña fuerte. URL no
pública (se comparte solo con el equipo que carga bloqueos).

---

## 4. Diseño del workflow

### 4.1 Topología de nodos

```
Form Trigger (Basic Auth, Workflow Finishes, timezone BA)
  → Validar/Normalizar Input (mapeo cabaña→id, operador→string,
                              motivo→string, source_event, fechas)
  → IF validación de capa OK
       → [no → Build Response (error de entrada) → Form Ending]
  → Build Payload (jsonb para crear_bloqueo)
  → Postgres: crear_bloqueo (Continue On Fail + Always Output Data)
  → Normalize (envelope: ok / error / detalle)
  → Build Response (decide el mensaje según resultado)
  → Form Ending (form operation=completion)
```

Mucho más corto que 8B: **un solo nodo Postgres**, sin cadena ni compensación. El patrón
de envelope normalizada (distinguir error técnico de error de negocio) se mantiene, igual
que el `Continue On Fail` + `Always Output Data` en el nodo Postgres.

### 4.2 Validación de capa (UX temprana, mínima)

El motor valida todo, así que la capa hace solo UX para no ir a la base con algo
obviamente mal:
- Cabaña presente y mapea a un id (desplegable cerrado, no debería fallar).
- Fechas presentes; `fecha_hasta > fecha_desde` (rebote temprano amable; el motor también
  lo valida con `fechas_invalidas`).
- Operador presente.

NO se valida solapamiento ni existencia de cabaña en la capa: eso es del motor.

### 4.3 Mapeo cabaña-nombre → `id_cabana`

Mapa fijo con los IDs reales del entorno: `Bamboo→1, Madre Selva→2, Arrebol→3,
Guatemala→4, Tokio→5`. El operador elige el nombre; n8n resuelve el id.

### 4.4 Construcción del payload

```json
{
  "id_cabana":    "<id mapeado>",
  "fecha_desde":  "<YYYY-MM-DD>",
  "fecha_hasta":  "<YYYY-MM-DD>",
  "motivo":       "<valor CHECK>",
  "descripcion":  "<texto o vacío>",
  "creado_por":   "<operador normalizado>",
  "source_event": "n8n_<marcador>_w8d_bloqueo_<operador>_manual"
}
```

Todo como strings; la función castea con su patrón defensivo `NULLIF(TRIM(...))`.

---

## 5. Manejo de errores y resultado único

### 5.1 Agrupación de mensajes (🔒 decisión de Franco)

Los 7 errores de la función se agrupan en **dos familias** para el operador:

**Familia A — Conflictos de disponibilidad (mensaje unificado):**
`conflicto_con_reserva`, `conflicto_con_prereserva`, `bloqueo_solapado` →
> "Esas fechas no están disponibles para bloquear. Revisá el calendario."

Sin distinguir el tipo de conflicto, sin mostrar IDs ni datos de reservas (D-8D-05).

**Familia B — Errores de entrada (mensajes claros, diferenciados):**
- `fechas_invalidas` → "La fecha 'hasta' tiene que ser posterior a la fecha 'desde'."
- `cabana_no_existe` → "La cabaña seleccionada no es válida." (no debería pasar; es desplegable)
- `motivo_invalido` → "El motivo seleccionado no es válido." (no debería pasar)
- `payload_invalido` → "Faltan datos obligatorios. Completá cabaña, fechas, motivo y operador."

**Error técnico** (Postgres caído, etc., detectado por la rama de Continue On Fail):
> "No se pudo registrar el bloqueo por un problema técnico. Reintentá en unos minutos."

### 5.2 Resultado de éxito

> "Bloqueo creado: <Cabaña> del <desde> al <hasta> (motivo: <motivo>). N° <id_bloqueo>."

Con `fecha_hasta` mostrada como el día de liberación (consistente con `[)`).

### 5.3 Taxonomía técnica vs negocio

Igual que 8B: el nodo Normalize tras Postgres arma un envelope
(`ok`/`error`/`detalle`) que distingue:
- **Error de negocio:** `ok:false` con un `error` conocido → mensaje de Familia A o B.
- **Error técnico:** el nodo Postgres falló (Continue On Fail lo captura) → mensaje técnico
  genérico, sin stack ni datos internos.

---

## 6. Plan de validación

### 6.1 Batería funcional en TEST (🔒 antes de OPS)

| Caso | Esperado |
|---|---|
| Bloqueo válido en cabaña libre | ✅ creado, aparece gris en calendario 8C |
| `fecha_hasta <= fecha_desde` | rebote "hasta posterior a desde" |
| Bloqueo solapado con otro bloqueo | mensaje unificado "no disponibles" |
| Bloqueo sobre cabaña con reserva confirmada/activa | mensaje unificado "no disponibles" |
| Bloqueo sobre cabaña con pre-reserva vigente | mensaje unificado "no disponibles" |
| Cada motivo del CHECK | persiste el string correcto |
| Descripción vacía | bloqueo creado con `descripcion` NULL |
| Trazabilidad | `creado_por` y `source_event` correctos en `bloqueos` y `log_cambios` |
| Verificación `[)` | el día `fecha_hasta` NO queda bloqueado |

Los conflictos se montan sembrando primero una reserva (vía 8B `__TEST`), una pre-reserva,
o un bloqueo previo (vía este mismo formulario o W6 `__TEST`).

### 6.2 Smoke controlado en OPS (al final)

Derivar `__OPS` (credencial OPS, path propio, Basic Auth propia), y crear **un bloqueo
real mínimo** que el equipo realmente necesite (no ficticio), verificando que aparece en
el calendario operativo de OPS. A diferencia de los HTML de 8C, 8D **escribe**, así que el
smoke OPS es un write real → se hace con un bloqueo genuino, no de prueba.

---

## 7. Restricciones fuertes (qué NO se toca en 8D)

- No se modifica el schema ni la función `crear_bloqueo` (8D la usa tal cual).
- No INSERT directo a `bloqueos`.
- No se expone el bloqueo total ni la selección múltiple.
- No se construye edición/baja de bloqueos.
- No se toca OPS hasta el smoke final; validación en TEST primero.

---

## 8. Decisiones (D-8D-XX) — a formalizar en el cierre

- **D-8D-01** — 8D = Form Trigger que llama a `crear_bloqueo()` en una acción; el motor
  valida, la capa es UX.
- **D-8D-02** — Una cabaña por vez; varias cabañas = varias cargas.
- **D-8D-03** — NO se expone el bloqueo total (`id_cabana IS NULL`) en el formulario: no
  se usa en la práctica; si hiciera falta, 5 cargas individuales. El motor lo sigue
  soportando.
- **D-8D-04** — Mensajes de conflicto unificados (Familia A); errores de entrada
  diferenciados (Familia B).
- **D-8D-05** — El mensaje de conflicto NO expone IDs ni datos de reservas/pre-reservas.
- **D-8D-06** — `source_event` = `n8n_<marcador>_w8d_bloqueo_<operador>_manual`, operador
  en minúscula sin espacios.
- **D-8D-07** — Basic Auth propia de 8D, separada de 8B y 8C.
- **D-8D-08** — `fecha_hasta` exclusive; ayuda de texto en el form, validación en el motor.

---

## 9. Resumen: qué queda cerrado y qué queda abierto

**Cerrado en el diseño:** contrato verificado, alcance (una cabaña, sin total, sin
múltiple, solo crear), campos del formulario, manejo de errores (2 familias), source_event,
plan de validación.

**Abierto (a ejecutar tras aprobación):** construir el workflow en TEST, validar la
batería 6.1, derivar a OPS y smoke con bloqueo real, documentar cierre `8D_CIERRE.md`.

*Fin del documento de diseño de 8D (v1.0, para aprobar).*
