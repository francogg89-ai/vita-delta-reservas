# ARQUITECTURA ETAPA 8B — CAPA DE CARGA INTERNA DE RESERVAS

**Estado:** ✅ Etapa cerrada. Diseño implementado, validado en TEST (batería de la sección 7.1 completa) y con **smoke OPS exitoso** (primera reserva real, id 1). Cierre formal en `8B_CIERRE.md`.
**Tipo:** Documento de diseño. **No contiene SQL ni configuración de workflows (JSON de n8n).**
**Fecha de redacción:** 2026-05-30.
**Versión:** v3.5 (smoke OPS exitoso con la primera reserva real; etapa 100% cerrada. Cierre formal en `8B_CIERRE.md`. Sobre v3.4).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3`.
**Entorno objetivo de operación:** OPS (`vita-delta-ops`, operación real interna, 8A cerrada).
**Entorno de validación funcional:** TEST (`vita-delta-test`).

---

## 0. Encuadre y cómo leer este documento

Este documento sigue la misma convención de la Etapa 8:

- **🔒 CERRADO** — decisión ya tomada (en este documento o heredada). No se reabre salvo contradicción crítica.
- **🟡 A VALIDAR** — decisión de diseño propuesta que necesita confirmación antes de implementar.
- **✅ VERIFICADO CONTRA OPS** — confirmado contra el contrato vivo de OPS en la verificación read-only del 2026-05-30 (sección 2). Ya no es supuesto.

**Cambio de estado respecto de v1/v2:** la sección 2 ya **no** es un plan de verificación pendiente; es el **registro de los hallazgos reales** leídos de OPS. Los contratos de función, los IDs de cabaña, los enums, la configuración y —de forma decisiva— la constraint de `idempotency_key` fueron leídos del contrato vivo. En v3.1 se cerraron los pendientes menores de diseño (convención de `source_event`, `encargado_semana`, motivo de compensación, desplegables TEXT-libre) y en v3.2 se completó el checklist manual de n8n (sección 9.4, incluida la credencial `vita_supabase_ops`). **No quedan pendientes previos a la implementación**; el siguiente paso es el plan de implementación por bloques.

Este documento **no genera SQL ni JSON de workflow**. Es diseño. La implementación arranca recién tras el checklist de n8n y por bloques.

---

## 1. Objetivo y alcance de 8B

### 1.1 Qué resuelve 8B

8B construye **una capa de carga interna**: un **formulario n8n (Form Trigger)**, usable desde celular, que permite a Vicky, Franco, Rodrigo o Remo cargar **una reserva ya cerrada** (cliente identificado + seña confirmada por WhatsApp) en **una sola acción**.

Detrás del formulario, n8n orquesta en secuencia las tres puertas del motor:

```
crear_prereserva()  →  registrar_pago()  →  confirmar_reserva()
```

El operador no ve tres pasos: completa los datos, dispara una acción y recibe **un solo resultado** — "Reserva confirmada ✅" o un error de negocio comprensible.

### 1.2 Qué queda explícitamente FUERA de 8B

- **Calendarios visuales** (operativo y de limpieza): son **8C**. En 8B solo se deja **marcado el punto de extensión** donde en el futuro engancha el repintado (sección 6). **No se construye repintado.**
- **Bloqueos operativos de uso real:** son **8D**.
- **MercadoPago real / webhook MP:** etapa futura.
- **Bot conversacional:** etapa futura.
- **Tarifas reales:** fuera de alcance; el monto lo ingresa el operador (D-8-04).
- **Frontend de carga "de verdad" / pantalla propia:** norte a mediano plazo (Etapa 8 §1.4), no este MVP.
- **RLS / cierre del residual A5 en DEV:** no se tocan (Opción A se mantiene).
- **Modificación de schema o de funciones SQL:** no se tocan salvo hallazgo crítico aprobado (sección 8).
- **Carga de reservas pasadas o ya iniciadas:** fuera del flujo normal de 8B; requieren decisión manual explícita (sección 3.1, nota de fechas; consistente con D-8-01, arranque sin backfill).

### 1.3 Principios heredados que enmarcan 8B (🔒 no se reabren)

- **El encadenado vive en n8n, no en el motor.** Las tres funciones siguen separadas en Supabase; lo que protege locks, idempotencia y revalidación es justamente esa separación (D-8-05, Etapa 8 §4.2).
- **Puertas únicas, sin INSERT directo.** Toda reserva pasa por `confirmar_reserva()`; toda pre-reserva por `crear_prereserva()`. No hay INSERT/UPDATE manual a `reservas`/`pre_reservas`/`pagos`/`bloqueos`.
- **Camino estricto.** Como la seña llega ya confirmada por WhatsApp, la confirmación usa el camino estricto (pago ya `confirmado`), no el combinado (D-8-02, Etapa 8 §2.1 y §4.3).
- **Opción A.** n8n entra como `postgres` por el pooler. El Form Trigger habla con n8n; n8n habla con Supabase. No aparece ningún consumidor Data API. Sin RLS, sin tocar A5 (Etapa 8 §4.7).
- **RESERVAS es la fuente final de verdad.** Cualquier salida (incluido el futuro calendario) es lectura derivada.
- **Aislamiento por ambiente.** Workflows con sufijo `__OPS`, credencial `vita_supabase_ops`, marcadores de ambiente en `source_event`. La validación funcional completa se hace en TEST con los `__TEST`.

---

## 2. Contratos reales verificados contra OPS (✅ read-only, 2026-05-30)

Verificación ejecutada en OPS, solo lectura (sin escritura, sin ejecución de funciones). Gate de entorno confirmado: 5 cabañas reales (Bamboo, Madre Selva, Arrebol, Guatemala, Tokio). Lo que sigue es el contrato **vivo**, no el canónico.

### 2.1 `crear_prereserva(payload jsonb)` — ✅

**Obligatorios** (rebotan `payload_invalido` si faltan): `id_cabana`, `fecha_in`, `fecha_out`, `personas`, `canal_origen`, `canal_pago_esperado`, `source_event`. Además: `monto_total` y `monto_sena` (rebotan `precio_requerido`), `huesped.nombre` no vacío (`huesped_nombre_requerido`), y `huesped.telefono` o `huesped.email` (`huesped_contacto_requerido`). `fecha_out > fecha_in` o rebota `fechas_invalidas`.

**Opcionales:** `idempotency_key`, `id_consulta`, `notas`, `notas_reserva`, `mascotas` (default FALSE), `detalle_mascotas`, `ninos` (TEXT), `hora_checkin_solicitada`/`hora_checkout_solicitada` (TIME; si se omiten, la función aplica defaults + regla domingo).

**✅ HALLAZGO 1 — `crear_prereserva` valida cabaña y capacidad (más de lo que decía el canónico).** El cuerpo real incluye, tras los locks:
- `cabana_no_existe` si el `id_cabana` no existe.
- `cabana_inactiva` si `cabanas.activa = false`.
- **`excede_capacidad`** (con `capacidad_max`) si `personas > capacidad_max`.

Esto significa que la validación de capacidad/cabaña es **defensa de integridad garantizada por el motor**, no algo que dependa de la capa. (Ver impacto en 3.2.)

**Idempotencia (triple chequeo):** la función chequea `idempotency_key` en tres puntos — pre-lock (`recovery_path='pre_lock'`), post-lock (`'post_lock'`) y en el `EXCEPTION WHEN unique_violation` (`'unique_violation'`) —, siempre filtrando `estado IN ('pendiente_pago','pago_en_revision')`. Si hay match, devuelve `ok:true, idempotent_match:true` con el `id_pre_reserva` existente.

**Otros estados de error observados:** `no_disponible` (con `conflictos`), `hora_fuera_de_rango`, `unique_violation_inesperado`.

**Devuelve (éxito):** `id_pre_reserva`, `id_huesped`, `estado` (`pendiente_pago`), `expira_en`, `hora_checkin`, `hora_checkout`, `idempotent_match`, `recovery_path`. **`id_pre_reserva` encadena con el paso 2.**

### 2.2 `registrar_pago(payload jsonb)` — ✅

**Obligatorios** (rebotan `payload_invalido`): `tipo`, `medio_pago`, `monto_esperado`, `monto_recibido`, `source_event`. Además, al menos uno de `id_pre_reserva` / `id_reserva` (si faltan ambos → `referencia_requerida`).

**Campo de referencia externa confirmado: `referencia_externa`** (no `referencia`). Otros opcionales: `moneda` (default ARS), `es_automatico` (default FALSE), `estado_inicial`, `comprobante_url`, `tx_hash`, `validado_por`, `notas`, `proveedor`, `cuenta_destino`.

**Decisión de estado del pago (cuerpo real, paso 4):**
- Si la pre-reserva está en estado **terminal** (`vencida`, `cancelada_por_cliente`, `cancelada_por_bloqueo`, `conflicto_pendiente`) → el pago se registra **forzado a `en_revision`**, con `warning='prereserva_no_activa'`, y **devuelve `ok:true`** igual.
- Si `estado_inicial='confirmado'` **Y** `monto_recibido = monto_esperado` → pago **`confirmado`** con `validado_en=NOW()`. **Si `validado_por` viene NULL, la función lo fuerza a `'sistema_auto'`.**
- En cualquier otro caso → `en_revision`.

**✅ HALLAZGO 2 — `ok:true` de `registrar_pago` NO garantiza pago `confirmado`.** Si la pre-reserva no estuviera activa, devuelve `ok:true` pero con `estado='en_revision'` y `warning='prereserva_no_activa'`. La cadena de 8B debe verificar el `estado` y la ausencia de `warning`, no solo `ok` (ver 4.6).

**✅ HALLAZGO derivado — trazabilidad del operador en el pago.** Como `validado_por` NULL se convierte en `'sistema_auto'`, para que el operador quede trazado en el pago hay que mandar **`validado_por=<operador>` explícito** en el paso 2 (ver 2.6).

**Promoción de pre-reserva:** si la pre-reserva estaba `pendiente_pago` y está activa, la función la promueve a `pago_en_revision`. (En el flujo estricto de 8B esto es transitorio: `confirmar_reserva` la lleva a `convertida` enseguida.)

**Devuelve (éxito normal):** `id_pago`, `estado` (esperado `confirmado`). **Devuelve (caso anómalo):** `id_pago`, `estado` (`en_revision`), `warning`, `prereserva_estado`.

### 2.3 `confirmar_reserva(payload jsonb)` — ✅

**Obligatorios** (rebotan `payload_invalido`): `id_pre_reserva`, `source_event`. **Opcionales:** `permitir_pago_en_revision` (default FALSE), `validado_por`, `encargado_semana`, `created_by`.

**Camino estricto (cuerpo real):**
- Locks: global → row lock de la pre-reserva → lock por cabaña (orden invariante).
- La pre-reserva debe estar en `pendiente_pago`/`pago_en_revision`; si no → `estado_invalido`.
- Busca un pago asociado en `estado='confirmado'`. Con `permitir_pago_en_revision=FALSE` (lo que usa 8B) y sin pago confirmado → **`sin_pago_confirmado`**.
- Revalida disponibilidad excluyendo la propia pre-reserva. Conflicto → marca `conflicto_pendiente` y devuelve **`conflicto_al_confirmar`** (con `conflictos`). EXCLUDE defensivo → **`no_disponible`**.
- INSERT en `reservas` con estado `confirmada` y **`monto_saldo = monto_total − monto_sena`** (derivado por la función). Marca pre-reserva `convertida`, asocia el pago a la reserva, actualiza el huésped.
- Persiste **`created_by`** y **`encargado_semana`** en `reservas`.

**Devuelve (éxito):** `id_reserva`, `id_pre_reserva`, `id_huesped`.

**Confirmación del manejo pago/seña/saldo:** el pago confirmado corresponde a la **seña** (paso 2: `monto_esperado=monto_recibido=seña`); el **saldo** lo deriva `confirmar_reserva` como `monto_total − monto_sena`. La capa nunca calcula ni manda el saldo.

### 2.4 `cancelar_prereserva(payload jsonb)` — ✅

**Obligatorios** (rebotan `payload_invalido`): `id_pre_reserva`, `motivo`, `source_event`. Opcional: `descripcion`.

- **Motivos válidos:** `cliente` (→ `cancelada_por_cliente`) y `bloqueo` (→ `cancelada_por_bloqueo`). Otro → `motivo_invalido`.
- **Estados cancelables:** solo `pendiente_pago` / `pago_en_revision`. Otro → `estado_no_cancelable` (con `estado_actual`).
- **Cuenta los pagos pero NO los toca.**
- **✅ HALLAZGO 3 — devuelve `pagos_asociados_count` y `pagos_asociados_ids`** (además de `id_pre_reserva`, `estado_anterior`, `estado_nuevo`). Esto se usa directamente en la lógica de compensación (ver 5.3): el `count` decide el mensaje sin tener que consultar `pagos` aparte.

### 2.5 Cabañas, enums y configuración — ✅

**Cabañas (IDs reales de OPS, confirmados):**

| id_cabana | nombre | tipo | cap_base | cap_max | activa | orden_limpieza |
|---|---|---|---|---|---|---|
| 1 | Bamboo | grande | 3 | 5 | true | 1 |
| 2 | Madre Selva | grande | 3 | 5 | true | 2 |
| 3 | Arrebol | grande | 3 | 5 | true | 3 |
| 4 | Guatemala | chica | 2 | 4 | true | 4 |
| 5 | Tokio | chica | 2 | 4 | true | 5 |

El mapa nombre→id del workflow (sección 4.4) se construye con estos valores. `orden_limpieza` existe (relevante para 8C, no para 8B).

**Enums (confirmados):**
- `estado_pago_enum`: `pendiente, en_revision, confirmado, rechazado, reembolsado` (la función solo produce `confirmado`/`en_revision`).
- `estado_prereserva_enum`: `pendiente_pago, pago_en_revision, vencida, convertida, cancelada_por_cliente, cancelada_por_bloqueo, conflicto_pendiente`.
- `estado_reserva_enum`: `confirmada, activa, completada, cancelada, cancelada_con_cargo, conflicto_pendiente`.
- `nivel_log_enum`: `info, warning, error`.

**✅ HALLAZGO 4 — `medio_pago`, `canal_origen`, `canal_pago_esperado` y `tipo` de pago NO son enums; son columnas TEXT libre.** El schema no impone valores. Consecuencia: los desplegables del formulario se mantienen cerrados por UX, pero el conjunto de opciones lo define el proyecto (ver 3.6), no el schema.

**Configuración (10 claves, confirmadas):** `prereserva_expiracion_minutos=60` (ventana amplísima frente a la cadena de segundos → sin riesgo de expiración entre pasos), horarios completos (check-in 13:00 / domingo 18:00; check-out 10:00 / domingo 16:00; rangos cliente), `horizonte_disponibilidad_dias=120`. `tipo_valor` en NULL en las 10 (esperado, PreOPS-A6, no bloquea). Como los horarios están, el form **omite** `hora_checkin_solicitada`/`hora_checkout_solicitada` y la función aplica defaults.

### 2.6 Mapeo verificado: campo de form → campo de función

| Campo del form | Paso 1 `crear_prereserva` | Paso 2 `registrar_pago` | Paso 3 `confirmar_reserva` |
|---|---|---|---|
| cabaña (nombre) → id | `id_cabana` (mapeado, 1-5) | — | — (heredado) |
| fecha_in / fecha_out | `fecha_in` / `fecha_out` | — | — |
| personas | `personas` | — | — |
| nombre y apellido (campo único) / teléfono / email | `huesped.{nombre (completo), telefono, email}` (apellido vacío) | — | — |
| canal_origen | `canal_origen` (TEXT) | — | — |
| canal_pago_esperado | `canal_pago_esperado` (TEXT) | — | — |
| medio_pago | — | `medio_pago` (TEXT), `tipo='sena'` | — |
| monto_total | `monto_total` | — | (deriva saldo) |
| seña | `monto_sena` | `monto_esperado`=`monto_recibido`=seña | (deriva saldo) |
| referencia de pago | — | `referencia_externa` | — |
| notas | `notas` / `notas_reserva` | `notas` (opcional) | — |
| niños (texto) | `ninos` | — | — |
| **operador / cargado_por** | `source_event` (embebido) | **`validado_por`** (explícito, sino → 'sistema_auto') | **`created_by`** + `source_event` |

### 2.7 Mapeo de `operador` / `cargado_por` (✅ resuelto por contrato real)

- **`crear_prereserva`:** no expone `created_by`; el operador viaja en **`source_event`** (que la función propaga a los triggers de log vía `set_config`).
- **`registrar_pago`:** **`validado_por=<operador>` explícito** (obligatorio para no perder la traza: NULL se convierte en `'sistema_auto'`).
- **`confirmar_reserva`:** **`created_by=<operador>`** (se persiste en `reservas.created_by`). **`encargado_semana` se deja vacío en 8B** (🔒): es el rol rotativo de la semana, distinto de quién carga; no se mezcla con la trazabilidad de carga, que ya queda cubierta por `operador`/`source_event`/`validado_por`/`created_by`.

**Convención de `source_event` (🔒 cerrada):** `n8n_ops_w8b_carga_<operador>_manual`, con `<operador>` **normalizado en minúscula y sin espacios**: `franco`, `vicky`, `rodrigo`, `remo`. Ejemplo: `n8n_ops_w8b_carga_vicky_manual`. La normalización del operador (etiqueta visible del desplegable → string del `source_event`) la hace n8n en el nodo de validación.

---

## 3. Diseño del formulario (Form Trigger)

Principio de diseño (🔒): **uso operativo real desde celular, minimizando texto libre. El formulario tiene que ser difícil de cargar mal.** Todo campo con opciones conocidas es selector; fechas con date picker; montos numéricos; texto libre solo para datos naturalmente variables.

### 3.1 Campos, tipos y controles

| Campo (etiqueta visible) | Tipo de control | Obligatorio | Valores / reglas |
|---|---|---|---|
| **Operador** (¿Quién carga?) | Desplegable | sí | Franco / Vicky / Rodrigo / Remo |
| **Cabaña** | Desplegable | sí | Bamboo / Madre Selva / Arrebol / Guatemala / Tokio (n8n mapea a `id_cabana` 1-5) |
| **Fecha de entrada** | Date picker | sí | hoy o futura (flujo normal); fechas pasadas → fuera de flujo normal (ver nota) |
| **Fecha de salida** | Date picker | sí | `> fecha_in` |
| **Personas** | Numérico restringido o desplegable | sí | entero ≥ 1; UX: acotar a capacidad (sección 3.2) |
| **Nombre y apellido** | Texto corto | sí | campo único; se persiste completo en `huesped.nombre` (apellido vacío). Dato variable |
| **Teléfono** | Texto corto | sí (al menos teléfono o email) | dato variable; la función normaliza al persistir |
| **Email** | Texto corto | condicional | si no hay teléfono, exigir email |
| **Canal de origen** | Desplegable | sí | opciones del proyecto (sección 3.6 — TEXT libre, no enum) |
| **Canal de pago esperado** | Desplegable | sí | opciones del proyecto (sección 3.6) |
| **Medio de pago (seña)** | Desplegable | sí | opciones del proyecto (sección 3.6) |
| **Monto total** | Numérico | sí | > 0 |
| **Seña** | Numérico | no (si vacía, n8n calcula 50%) | editable; texto de ayuda "dejá vacío para 50% automático" (sección 3.3) |
| **Referencia de pago** | Texto corto | no | → `referencia_externa` |
| **Niños** | Texto corto | no | campo `ninos` es TEXT |
| **Notas** | Texto largo | no | → `notas` / `notas_reserva` |

**El operador nunca ve ni escribe:** IDs de cabaña, estados internos, `idempotency_key`, `source_event`. Todo eso lo arma n8n. El nombre del huésped se carga en **un único campo "Nombre y apellido"** (obligatorio), que se persiste completo en `huesped.nombre` con `apellido` vacío; `crear_prereserva` solo exige `nombre` no vacío + un contacto, así que esto es válido (decisión de v3.3, reemplaza el apellido separado de D-8B-12).

**Nota sobre fechas (🔒):** `fecha_in >= hoy` es la regla del **flujo normal** (hoy o futura, `fecha_out > fecha_in`), no una regla rígida absoluta. **Reservas ya iniciadas o con fechas pasadas quedan FUERA del flujo normal** y requieren decisión explícita / carga manual, no por este formulario (consistente con D-8-01: arranque sin backfill).

### 3.2 Validaciones en origen vs en el workflow

n8n Form Trigger tiene validación limitada. Estrategia en dos capas:

- **En el formulario (lo que n8n permita):** requeridos, numérico para montos/personas, date para fechas, desplegables cerrados para lo enumerable, email con formato. Reglas de fecha si están disponibles. (Capacidades reales del Form Trigger → checklist de n8n, sección 9.4.)
- **En el workflow:** lo que el form no garantice. En particular:
  - **Capacidad y cabaña:** ✅ **ya las valida `crear_prereserva`** (`cabana_no_existe`, `cabana_inactiva`, `excede_capacidad`). Por lo tanto la validación de capacidad en n8n **NO es la defensa de integridad** — esa la da el motor. Se mantiene en n8n **solo como mejora de UX temprana** (mensaje claro antes de disparar la cadena, leyendo `cabanas.capacidad_max` por SELECT read-only). Si se omitiera, el motor igual protege.
  - **Coherencia de fechas:** `fecha_out > fecha_in` siempre; `fecha_in >= hoy` como regla del flujo normal (fecha pasada → mensaje de "fuera de flujo normal, decisión manual").
  - **Seña ≤ total** (sección 3.3).

### 3.3 Seña 50% sugerida y editable; saldo derivado

- **Variante A (🔒):** "Seña" puede dejarse **vacía**; si no se completa, **n8n calcula 50% del total**. Si se escribe un valor, se respeta.
- **Claridad en celular (🔒):** texto de ayuda visible "dejá vacío para 50% automático".
- **Saldo:** no se carga; lo deriva `confirmar_reserva` (`monto_total − monto_sena`). Mostrarlo es solo UX informativa.
- **Validación:** `0 < seña <= total`; rebote claro si la supera.

### 3.4 Selector de operador

🔒 Desplegable **obligatorio** (Franco / Vicky / Rodrigo / Remo), identidad autodeclarada, sin login individual en el MVP. Alimenta la trazabilidad de 2.7.

### 3.5 Protección / acceso del formulario

**Preferencia (🔒, orden de prioridad):**
1. **Basic Auth o mecanismo equivalente** sobre el Form Trigger, si la instancia de n8n lo ofrece. Opción preferida.
2. **Si no está disponible:** link **solo interno** + **no publicar** la URL + **rotación si se filtra** (regenerar el Form Trigger). Documentado como limitación operativa.

El formulario solo crea reservas (no borra ni expone datos masivos); el daño potencial de un acceso indebido es acotado, pero igual se protege. La capacidad real de autenticación se confirma en el checklist de n8n (9.4).

### 3.6 Opciones de los desplegables TEXT-libre (🔒 cerradas)

`medio_pago`, `canal_origen` y `canal_pago_esperado` son **TEXT libre** en el schema (Hallazgo 4): no hay valores impuestos. Se usan desplegables cerrados igual (UX, evita typos y problemas de mayúsculas). **Criterio (🔒):** la **etiqueta visible** es amigable; el **string persistido** es simple, en minúscula, sin acentos y estable para futuros reportes. El nodo de validación de n8n mapea etiqueta → string persistido.

**`canal_origen`:**

| Etiqueta visible | String persistido |
|---|---|
| WhatsApp | `whatsapp` |
| Instagram | `instagram` |
| Directo | `directo` |
| Referido | `referido` |
| Airbnb | `airbnb` |
| Booking | `booking` |
| Otro | `otro` |

**`canal_pago_esperado`:**

| Etiqueta visible | String persistido |
|---|---|
| Transferencia | `transferencia` |
| Efectivo | `efectivo` |
| MercadoPago | `mercadopago` |
| Otro | `otro` |

**`medio_pago`:**

| Etiqueta visible | String persistido |
|---|---|
| Transferencia | `transferencia` |
| Efectivo | `efectivo` |
| MercadoPago | `mercadopago` |
| Otro | `otro` |

---

## 4. Diseño del workflow de encadenado

### 4.1 Topología de nodos (patrón canónico 6C extendido)

```
Form Trigger (8B)
  → Validar/Normalizar Input (Code)        // mapeo cabaña→id, fechas, seña, capacidad-UX, normalización teléfono p/ key
  → Build Payload P1 (Code)
  → Postgres: crear_prereserva()
  → ¿ok? ───no──→ Build Response (error de negocio claro)            [FIN]
       │ sí
  → Build Payload P2 (Code, usa id_pre_reserva)
  → Postgres: registrar_pago()
  → ¿ok && estado=='confirmado' && sin warning? ──no──→ Compensación → Build Response (parcial/revisión manual)   [FIN]
       │ sí
  → Build Payload P3 (Code, usa id_pre_reserva)
  → Postgres: confirmar_reserva()
  → ¿ok? ───no──→ Compensación → Build Response (parcial/revisión manual)   [FIN]
       │ sí
  → [PUNTO DE EXTENSIÓN 8C: aquí enganchará el repintado — NO se construye en 8B]
  → Build Response ("Reserva confirmada ✅", id_reserva)              [FIN]
```

Convenciones heredadas: `Always Output Data: ON` + filtro defensivo downstream (L-6C-04); `Ignore SSL Issues: ON` en la credencial (L-6C-01); normalización defensiva `nv()`/`NULLIF(TRIM())` en los Build Payload (L-6D-03); `={{ JSON.stringify($json.payload) }}` para el JSONB (L-6C-06).

### 4.2 Construcción de payloads paso a paso

- **P1 (`crear_prereserva`):** `huesped` (objeto anidado: `nombre` completo del campo único, `telefono`, `email`; `apellido` vacío), `id_cabana` mapeado, fechas, personas, `monto_total`, `monto_sena`, `canal_origen`, `canal_pago_esperado`, `source_event`, `idempotency_key` (4.3), opcionales (`notas`, `ninos`). Vacíos van como `""` y la función los normaliza.
- **P2 (`registrar_pago`):** `id_pre_reserva` de P1; `tipo='sena'`, `monto_esperado=monto_recibido=seña`, `estado_inicial='confirmado'`, `medio_pago`, `referencia_externa` (si vino), **`validado_por=<operador>` explícito**, `source_event`.
- **P3 (`confirmar_reserva`):** `id_pre_reserva`; `permitir_pago_en_revision=FALSE` (estricto), `created_by=<operador>`, **`encargado_semana` vacío en 8B** (🔒, ver 2.7), `source_event`.

### 4.3 `idempotency_key` — ✅ fórmula cerrada (Opción A)

**✅ HALLAZGO 5 (decisivo) — la constraint es PARCIAL.** El índice real es:
```
uq_prereservas_idempotency_activa  UNIQUE (idempotency_key)
WHERE idempotency_key IS NOT NULL AND estado IN ('pendiente_pago','pago_en_revision')
```
La unicidad solo rige sobre pre-reservas **activas**. Una reserva cancelada/vencida sale del subconjunto del índice, así que **una recarga legítima con la misma cabaña/fechas/teléfono no choca** (genera una pre-reserva nueva sin `unique_violation`).

**Fórmula final (🔒 cerrada, Opción A):**
```
ops_8b_<id_cabana>_<fecha_in>_<fecha_out>_<telefono_normalizado>
```
Ejemplo: `ops_8b_1_2026-08-01_2026-08-03_5491155667788`.

- Estable ante reintento de la misma carga → `crear_prereserva` devuelve `idempotent_match` sin duplicar.
- Discrimina cargas distintas.
- **Opción B descartada** para el MVP: ya no hace falta (la constraint parcial resuelve el caso de recarga tras cancelación) y habría reducido idempotencia ante reintentos tardíos (key con fecha de carga cambia al día siguiente).

**Limitación de n8n (nota):** el Form Trigger no expone un submission ID estable que sobreviva a reintentos (cada envío es una ejecución nueva). Por eso la key se deriva de los datos, no de un ID de n8n.

**Caso límite (reenvío post-confirmación):** si el primer intento ya confirmó (pre-reserva `convertida`), el `idempotent_match` no la encuentra y el segundo intento choca con las fechas ocupadas → rebote de colisión claro (5.2). Aceptable; el mensaje debe dejar claro que "ya estaba cargada".

### 4.4 Normalización del teléfono para la key (nota de implementación)

El `telefono_normalizado` de la key lo construye **n8n**, antes de llamar a las funciones. La función `normalizar_telefono()` de Supabase normaliza el teléfono al persistir el huésped, pero la key se arma en n8n, así que n8n debe normalizar de forma **estable y consistente** (no necesariamente igual a la función SQL):

- **Mínimo requerido:** quitar espacios, guiones, paréntesis y `+`, dejando **solo dígitos**.
- **Ejemplo:** `+54 9 11 5566-7788` → `5491155667788`.
- **Criterio:** no hace falta normalización telefónica perfecta (no se busca E.164 canónico); hace falta **consistencia** — que el mismo teléfono tipeado igual produzca siempre la misma key. La normalización se aplica en el nodo de validación, una vez, y el resultado se reutiliza para la key.

### 4.5 Mapeo cabaña-nombre → `id_cabana` (✅ valores reales)

Mapa fijo con los IDs reales de OPS: `Bamboo→1, Madre Selva→2, Arrebol→3, Guatemala→4, Tokio→5`. El operador elige el nombre; n8n resuelve el ID. (Si el nombre no matchea —no debería, es desplegable cerrado—, rebote claro.)

### 4.6 Verificación del resultado de cada paso (✅ Hallazgo 2 aplicado)

- **Tras P1 (`crear_prereserva`):** continuar solo si `ok===true`. Capturar `id_pre_reserva` (sea de creación o de `idempotent_match`).
- **Tras P2 (`registrar_pago`) — NO basta `ok:true`:** continuar solo si **`ok===true` Y `estado==='confirmado'` Y no viene `warning`** (en particular `warning!=='prereserva_no_activa'`). Si `ok:true` pero `estado==='en_revision'` o viene warning → **caso anómalo con pago registrado** → no es éxito normal → va a compensación/revisión manual (5.3). En el flujo normal (pre-reserva recién creada, activa) el pago nace `confirmado`, así que esta rama anómala no debería dispararse; es defensa.
- **Tras P3 (`confirmar_reserva`):** continuar solo si `ok===true`. Si no → compensación (5.3).

### 4.7 `source_event` y trazabilidad por paso

Cada paso manda `source_event = n8n_ops_w8b_carga_<operador>_manual` (🔒 convención cerrada, operador en minúscula sin espacios: `franco`/`vicky`/`rodrigo`/`remo`). Sumado a `validado_por` (pago) y `created_by` (reserva), deja la operación trazable por operador en `reservas`, `pagos`, `pre_reservas` y `log_cambios`.

---

## 5. Manejo de errores y estados intermedios

### 5.1 Taxonomía: error de negocio vs error técnico

- **Error de negocio:** `ok:false` con `error` conocido (`payload_invalido`, `precio_requerido`, `fechas_invalidas`, `huesped_nombre_requerido`, `huesped_contacto_requerido`, `cabana_no_existe`, `cabana_inactiva`, `excede_capacidad`, `hora_fuera_de_rango`, `no_disponible`, `conflicto_al_confirmar`, `sin_pago_confirmado`, `estado_invalido`, `estado_no_cancelable`, `motivo_invalido`). Se traduce a frase clara.
- **Error técnico:** falla de conexión, timeout, excepción cruda → "error técnico, reintentá o avisá a Franco", sin volcar stack.

**Mapa de mensajes (🟡 a refinar):**
- `no_disponible` / `conflicto_al_confirmar` → "Esa cabaña ya está ocupada en esas fechas."
- `excede_capacidad` → "Esa cabaña admite hasta N personas." (usar `capacidad_max` devuelto)
- `cabana_inactiva` → "Esa cabaña no está disponible para cargar."
- `huesped_contacto_requerido` → "Falta teléfono o email del huésped."
- `precio_requerido` → "Faltan el monto total o la seña."
- fecha pasada (rebote de la capa) → "Las reservas ya iniciadas o con fechas pasadas no se cargan por acá; requieren decisión manual."
- **estado parcial con pago** (5.3) → mensaje de **revisión manual que menciona el pago**.

### 5.2 Colisión de disponibilidad → mensaje claro (🔒 UX)

El motor impide el doble-booking (locks H7 + EXCLUDE). 8B traduce `no_disponible` / `conflicto_al_confirmar` a: **"Esa cabaña ya está ocupada en esas fechas."** Sin tecnicismos.

### 5.3 Política ante fallo parcial — 🔒 compensación activa (✅ Hallazgo 3 aplicado)

Si `crear_prereserva()` tuvo éxito (existe `id_pre_reserva`) pero **falla `registrar_pago()` o `confirmar_reserva()`** (incluido el caso anómalo de 4.6: `ok:true` con `estado='en_revision'`/`warning`), el workflow **intenta cancelar la pre-reserva** vía `cancelar_prereserva()` si sigue cancelable (`pendiente_pago`/`pago_en_revision`). **Parámetros de la cancelación de compensación (🔒 cerrados):** `motivo='cliente'` (valor permitido por el contrato real) + `descripcion='rollback_8b_fallo_cadena'`. La `descripcion` distingue inequívocamente esta cancelación técnica de rollback de una cancelación normal solicitada por el cliente (queda registrada en el log de `cancelar_prereserva`).

**Decisión del mensaje según `pagos_asociados_count` (que devuelve `cancelar_prereserva`):**

- **`pagos_asociados_count === 0`** → no quedó dinero registrado → puede comunicarse **reversión limpia**: error claro del paso que falló + "la carga se revirtió, podés reintentar".
- **`pagos_asociados_count > 0`** → quedó pago registrado (el `cancelar_prereserva` no lo toca) → **revisión manual explícita mencionando el/los pago/s**, con `id_prereserva` e `id_pago` (de `pagos_asociados_ids`):
  > "⚠️ Se registró un pago, pero no se pudo confirmar la reserva. La pre-reserva #<id> quedó cancelada pero **el/los pago/s siguen registrados** (#<ids>). **Requiere revisión manual.** Avisá a Franco con esos números."

- **Si la compensación falla o no corresponde** (pre-reserva ya no cancelable, o `cancelar_prereserva` devuelve error): **estado parcial explícito** con `id_prereserva` (e `id_pago` si se conoce del paso 2), marcando **revisión manual**. No se ocultan estados intermedios.

**Regla de comunicación (🔒):** el workflow solo dice **"revertido"** cuando `pagos_asociados_count === 0`. Si quedó cualquier pago registrado, el mensaje es **siempre** revisión manual, nunca reversión limpia.

✅ Verificado contra el contrato real: `cancelar_prereserva` cuenta los pagos y no los toca, y los expone en `pagos_asociados_count`/`pagos_asociados_ids` — la decisión del mensaje se toma con ese dato, sin consulta adicional.

### 5.4 Resultado único al operador

- **Éxito:** "Reserva confirmada ✅" + `id_reserva` (opcional: cabaña, fechas, saldo como confirmación).
- **Error de negocio:** frase clara (5.1).
- **Estado parcial sin pago (`count=0`):** mensaje de reversión + reintento.
- **Estado parcial con pago (`count>0`) o anómalo:** revisión manual con `id_prereserva` (e `id_pago`), mencionando el pago (5.3).

---

## 6. Punto de extensión para 8C (sin construir)

### 6.1 Dónde engancha el repintado

🔒 En la topología (4.1), **inmediatamente después de que `confirmar_reserva()` devuelve `ok:true`**, antes del Build Response final. Es el "evento final que en el futuro disparará el repintado" (Etapa 8 §5.2, D-8-07/D-8-08). En 8B queda como **nodo placeholder / comentario explícito** ("AQUÍ engancha el repintado de 8C"), sin lógica de repintado.

### 6.2 Qué NO se hace en 8B

- No se construye repintado (ni por evento ni manual).
- No se decide Sheet vs HTML (es 8C §5.6).
- No se tocan `vista_calendario` ni `vista_limpieza_semana`.
- No se construye el workflow manual de repintado/reparación (es 8C §5.4).

---

## 7. Plan de validación

### 7.1 Batería funcional completa en TEST (🔒 antes que OPS)

En **TEST** con workflows `__TEST` y credencial `vita_supabase_test`, antes de tocar OPS.

**Happy path:** carga válida → pre-reserva creada → pago `sena` confirmado → reserva `confirmada`. Verificar `monto_saldo = total − seña`, `created_by`, `validado_por`, `source_event`, transición de disponibilidad (cruzada con W1).

**Caminos no-felices (estilo 7C):**
- Obligatorios faltantes (cabaña, fechas, personas, montos, contacto, nombre y apellido) → mensajes claros.
- `fecha_out <= fecha_in` → claro; `fecha_in` pasada → "fuera de flujo normal, decisión manual".
- `personas > capacidad_max` → `excede_capacidad` (del motor) + mensaje UX.
- `cabana_inactiva` (si se fuerza en TEST) → mensaje claro.
- Seña > total → rebote claro. Seña vacía → n8n calcula 50% (Variante A).
- **Colisión:** segunda carga sobre misma cabaña/fechas → "ya está ocupada".
- **Idempotencia:** reenvío misma key antes de confirmar → `idempotent_match` sin duplicar. Reenvío tras confirmar → colisión clara. **Recarga tras cancelación → genera pre-reserva nueva** (constraint parcial confirmada).
- **Paso 2 anómalo:** forzar `registrar_pago` sobre pre-reserva no activa → `ok:true` + `estado='en_revision'` + `warning` → la cadena lo trata como anómalo (no éxito) y va a revisión manual.
- **Fallo parcial + compensación:** fallo en paso 2 sin pago → `count=0` → reversión limpia. Fallo en paso 3 con pago confirmado → `count>0` → revisión manual mencionando el pago. Compensación no aplicable → estado parcial con `id_prereserva`.

### 7.2 Smoke mínimo controlado en OPS (🔒 D-8-12)

Solo tras TEST verde: cargar **una reserva real futura válida** (no inventada) por la capa de 8B — **primer write real en OPS**. Verificar `confirmada`, saldo correcto, trazabilidad. Sin pruebas destructivas. Repintado no se verifica acá (es 8C).

---

## 8. Restricciones fuertes (qué NO se toca en 8B)

- **No se modifica el schema de OPS** salvo hallazgo crítico con aprobación explícita. (La verificación de la sección 2 **no** reveló necesidad de cambios: el motor soporta el flujo de 8B tal cual.)
- **No se modifican las funciones SQL** salvo necesidad crítica demostrada y aprobada.
- **No se escribe en OPS durante el diseño.** La verificación de la sección 2 fue read-only.
- **No se tocan DEV ni TEST como entornos** más allá de usar TEST para la batería funcional. No se toca el residual A5 de DEV, ni RLS, ni Data API. Opción A se mantiene.
- **No se mezcla 8B con 8C/8D.** Solo se marca el punto de extensión del repintado.
- **No se genera SQL ni JSON de workflow** hasta completar el checklist de n8n y pasar a implementación por bloques.

---

## 9. Decisiones (D-8B-XX) y pendientes

### 9.1 Decisiones cerradas (a formalizar como D-8B-XX en el cierre)

- **D-8B-01** — Capa = Form Trigger n8n que encadena `crear_prereserva → registrar_pago → confirmar_reserva` en una acción, camino estricto.
- **D-8B-02** — Formulario para celular, mínimo texto libre: desplegables/date/numérico; texto libre solo para nombre y apellido (campo único)/teléfono/email/notas/niños.
- **D-8B-03** — `operador`/`cargado_por` = desplegable obligatorio (Franco/Vicky/Rodrigo/Remo), autodeclarado, sin login en el MVP.
- **D-8B-04** — Trazabilidad por contrato real (✅): operador en `source_event` (`n8n_ops_w8b_carga_<operador>_manual`) + **`validado_por` explícito** en `registrar_pago` (NULL → `'sistema_auto'`) + `created_by` en `confirmar_reserva`.
- **D-8B-05** — Pago = seña: `tipo='sena'`, `monto_esperado=monto_recibido=seña`, `estado_inicial='confirmado'`. Saldo derivado por `confirmar_reserva` (`total − seña`). ✅ verificado.
- **D-8B-06** — `idempotency_key` = **Opción A cerrada** (✅): `ops_8b_<id_cabana>_<fecha_in>_<fecha_out>_<telefono_normalizado>`. Habilitada por la constraint **parcial** `uq_prereservas_idempotency_activa`. Opción B descartada.
- **D-8B-07** — Fallo parcial → compensación activa. Mensaje según `pagos_asociados_count` de `cancelar_prereserva`: `0` → reversión limpia; `>0` → revisión manual mencionando pago/s (con `pagos_asociados_ids`). Nunca "revertido" si quedó pago. El caso anómalo del paso 2 (Hallazgo 2) también va a revisión manual.
- **D-8B-08** — Colisión → mensaje de negocio claro, nunca error técnico crudo.
- **D-8B-09** — En 8B solo se marca el punto de extensión del repintado (post-`confirmar_reserva` ok). No se construye repintado.
- **D-8B-10** — Form Trigger protegido: preferencia Basic Auth o equivalente; si no, link interno + no publicar + rotación si se filtra.
- **D-8B-11** — Fechas: flujo normal hoy/futuro y `fecha_out > fecha_in`; pasadas o ya iniciadas → fuera del flujo normal, decisión manual (consistente con D-8-01).
- **D-8B-12** — (Revisada en v3.3) Nombre del huésped en **un único campo "Nombre y apellido"** obligatorio, persistido completo en `huesped.nombre` con `apellido` vacío. Reemplaza la decisión previa de apellido obligatorio separado (la función no lo usa estructuralmente y el campo único es más simple y robusto para el operador). Motivada por validación en TEST.
- **D-8B-13** — Seña Variante A: vacía → 50% automático; escrita → se respeta. Texto de ayuda "dejá vacío para 50% automático".
- **D-8B-14** — Validación funcional completa en TEST; smoke mínimo controlado en OPS con reserva real futura (primer write real).
- **D-8B-15** — Verificación del resultado por paso (✅ Hallazgo 2): tras `registrar_pago`, exigir `ok===true && estado==='confirmado' && sin warning`; no basta `ok:true`.
- **D-8B-16** — Capacidad/cabaña: ✅ las valida `crear_prereserva` (`cabana_no_existe`/`cabana_inactiva`/`excede_capacidad`). La validación en n8n queda como **UX temprana**, no como defensa de integridad.
- **D-8B-17** — Normalización del teléfono para la key se hace en n8n, estable y consistente: solo dígitos (quitar espacios, guiones, paréntesis, `+`). No requiere E.164 perfecto.
- **D-8B-18** — Convención de `source_event` cerrada: `n8n_ops_w8b_carga_<operador>_manual`, con `<operador>` en minúscula sin espacios (`franco`/`vicky`/`rodrigo`/`remo`).
- **D-8B-19** — `encargado_semana` se deja **vacío** en 8B. No se mezcla "quién cargó" (cubierto por `operador`/`source_event`/`validado_por`/`created_by`) con el rol rotativo de la semana.
- **D-8B-20** — Cancelación de compensación: `motivo='cliente'` + `descripcion='rollback_8b_fallo_cadena'` (uso técnico de un motivo permitido por el contrato real, con descripción que lo distingue de una cancelación normal del cliente).
- **D-8B-21** — Desplegables TEXT-libre cerrados (etiqueta visible → string persistido en minúscula, sin acentos): `canal_origen` {whatsapp, instagram, directo, referido, airbnb, booking, otro}; `canal_pago_esperado` {transferencia, efectivo, mercadopago, otro}; `medio_pago` {transferencia, efectivo, mercadopago, otro}.

### 9.2 Pendientes a validar antes de implementar (🟡)

Todos los pendientes menores de diseño quedaron cerrados (ver 9.1, D-8B-18 a D-8B-21). El único paso previo a implementación que resta es el **checklist manual de n8n** (sección 9.4), que no es verificable por SQL y depende de la inspección de la instancia.

**Cerrados en v3 (hallazgos OPS):** fórmula de `idempotency_key` → Opción A (D-8B-06); capacidad validada en la capa → la valida el motor (D-8B-16).
**Cerrados en v3.1 (pendientes menores 9.2):** convención de `source_event` (D-8B-18); `encargado_semana` vacío (D-8B-19); motivo de compensación (D-8B-20); desplegables TEXT-libre (D-8B-21).

### 9.3 Verificaciones contra OPS — ✅ COMPLETADAS (read-only, 2026-05-30)

- Contratos reales de las 4 funciones (`pg_get_functiondef`) ✅
- IDs reales de cabaña (1-5) + capacidades + activa + orden_limpieza ✅
- Enums (estados de pre-reserva/reserva/pago, nivel_log) ✅ · `medio_pago`/`canal_origen`/`canal_pago_esperado`/`tipo` son TEXT libre, no enums ✅
- `configuracion_general` (expiración 60', horarios, horizonte 120) ✅
- Constraint de `idempotency_key`: **parcial** sobre estados activos ✅

### 9.4 Checklist manual de n8n — ✅ COMPLETADO (2026-05-30)

Verificado en la instancia (`federicosecchi.app.n8n.cloud`). Sin bloqueos para implementar.

**1. Versión**
- n8n: **2.21.8**
- Form Trigger node: **2.5**

**2. Protección (🔒 cerrada)**
- `Basic Auth` disponible en el Form Trigger → **se usa Basic Auth** como protección mínima.
- **No** usar URL abierta sin autenticación.
- **No** usar `IP Allowlist` por ahora: los celulares salen con IP móvil/dinámica (NAT de carrier, cambio wifi↔datos) y una allowlist rompería el uso real. Basic Auth es la protección adecuada para este caso.

**3. Tipos de campo disponibles (confirmados)**
Text Input · Email · Number · Password · Radio Buttons · Textarea · Checkboxes · Custom HTML · Date · Dropdown · Hidden Field · File.
Para 8B **alcanzan**: Dropdown (operador, cabaña, canales, medio de pago), Date (fechas), Number (montos, personas), Email, Text Input (nombre y apellido como campo único, teléfono, referencia, niños), Textarea (notas).

**4. Atributos / validaciones confirmados**
`Custom Field Name` · `Placeholder` · `Default Value` · `Required Field`.
**Min/max numérico y fecha mínima nativa NO quedaron confirmados.** Si no existen, se validan en el **nodo de validación del workflow** (ya previsto en 3.2: `personas`, `seña ≤ total`, `fecha_in >= hoy`). No es bloqueo: la capacidad además la garantiza el motor (`excede_capacidad`).

**5. Respuesta al operador (🔒 cerrada)**
- `Respond When = Workflow Finishes` → el operador ve el **resultado real de la cadena**, no un acuse de envío prematuro (coherente con 5.4). Como la cadena es de segundos y `prereserva_expiracion_minutos=60`, no hay riesgo de timing.
- Usar **`Form Ending`** para mostrar el resultado final.
- **Todas** las ramas del workflow deben terminar en una respuesta visible: éxito, error de negocio, revisión manual o error técnico (ninguna rama queda colgada; entronca con `Always Output Data: ON` + filtro defensivo, L-6C-04).

**6. Zona horaria (🔒 decisión de implementación)**
Fijar **`America/Argentina/Buenos_Aires`** (UTC-3) y usarla de forma **consistente** para: validación de `fecha_in >= hoy`; armado del componente `<fecha_in>` de la `idempotency_key`; interpretación de las fechas del formulario; y los CASE de domingo de `crear_prereserva`. Objetivo: evitar corrimientos de un día cerca de medianoche por desajuste de zona entre n8n y Supabase. Revisar/usar `Use Workflow Timezone`.

**7. Otras options**
`Button Label` y `Form Path` para UX (se definen en implementación). `Ignore Bots` ON es inocuo. `Append n8n Attribution` cosmético.

**8. Credencial `vita_supabase_ops` — ✅ confirmada**
Visible y seleccionable en n8n (vista en un nodo Postgres / Postgres Trigger). **Aclaración:** esta verificación solo confirma **disponibilidad** de la credencial; en implementación se debe elegir el **nodo Postgres correcto** para ejecutar las llamadas SQL (no el Trigger).

---

## 10. Resumen: qué queda cerrado y qué queda abierto

| Punto | Estado |
|---|---|
| Form Trigger n8n, una acción, encadena las 3 funciones, camino estricto | 🔒 Cerrado |
| Formulario para celular, mínimo texto libre | 🔒 Cerrado |
| Operador = desplegable obligatorio, autodeclarado | 🔒 Cerrado |
| Nombre y apellido en campo único (persiste en huesped.nombre) | 🔒 Cerrado (v3.3) |
| Fechas: flujo normal hoy/futuro; pasadas → decisión manual | 🔒 Cerrado |
| Seña Variante A (vacía → 50%; escrita → respeta) | 🔒 Cerrado |
| Pago = seña; saldo derivado por la función | 🔒 Cerrado · ✅ verificado |
| Capacidad/cabaña la valida el motor; n8n solo UX | 🔒 Cerrado · ✅ verificado |
| `idempotency_key` Opción A (constraint parcial) | 🔒 Cerrado · ✅ verificado |
| Normalización de teléfono para la key (solo dígitos, en n8n) | 🔒 Cerrado |
| Verificación de resultado por paso (no basta `ok:true` en pago) | 🔒 Cerrado · ✅ verificado |
| Fallo parcial → compensación + mensaje según `pagos_asociados_count` | 🔒 Cerrado · ✅ verificado |
| Colisión → mensaje claro | 🔒 Cerrado |
| Punto de extensión 8C marcado, repintado NO construido | 🔒 Cerrado |
| Protección Form Trigger = Basic Auth (✅ disponible y elegida); sin IP Allowlist | 🔒 Cerrado · ✅ verificado |
| Validación completa en TEST, smoke mínimo en OPS | 🔒 Cerrado |
| Contratos / IDs / enums / config / constraint verificados | ✅ Completado |
| Opciones desplegables TEXT-libre; `source_event`; motivo compensación; `encargado_semana` vacío | 🔒 Cerrados (D-8B-18 a D-8B-21) |
| Checklist de n8n (versión 2.21.8 / FT 2.5, auth, tipos, validaciones, Workflow Finishes, credencial) | ✅ Completado |

---

*Fin del documento de diseño de la Etapa 8B (v3.4). Diseño implementado y validado en TEST (batería de la sección 7.1 completa): happy path en ambos caminos de seña, colisión, idempotencia, validaciones de capa y compensación con pago. Workflows `__TEST`, `__OPS` y `__TEMPLATE` generados. El smoke en OPS queda pendiente de la primera reserva real. El cierre formal de la etapa, con todas las decisiones y resultados, está en `8B_CIERRE.md`.*
