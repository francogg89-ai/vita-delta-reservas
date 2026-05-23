# Contrato técnico — `db_crear_huesped v1.1`

## 1. Nombre del workflow

`db_crear_huesped v1.1`

---

## 2. Estado

| Entorno | Estado |
|---|---|
| DEV | validado |
| TEST | validado |
| PROD | pendiente |
| Template GitHub | sanitizado y listo — `Workflows/n8n/db_crear_huesped.template.json` |

---

## 3. Propósito

Crea o actualiza un huésped en la hoja `HUÉSPEDES` y devuelve su `id_huesped`.

**Hace:**
- Valida que `nombre` y `telefono` vengan en el input.
- Normaliza teléfono y email antes de buscar.
- Deduplica: busca primero por teléfono normalizado, luego por email como fallback.
- Si no encuentra huésped existente → crea fila nueva.
- Si encuentra huésped existente → actualiza solo los campos con valor real.
- Si encontró por email y el teléfono existente estaba vacío → lo completa.
- Escribe `LOG_CAMBIOS` en todos los casos: creación, actualización y error de input.
- Devuelve `id_huesped`, `modo` (`creado`/`actualizado`) y datos básicos del huésped.

---

## 4. Fuera de alcance

Este workflow **no**:

- Toca `PRE_RESERVAS`.
- Toca `RESERVAS`.
- Toca `PAGOS`.
- Toca `DISPONIBILIDAD_CACHE`.
- Toca el calendario operativo.
- Confirma reservas.
- Calcula precios.
- Actualiza `primera_reserva_fecha` — eso es responsabilidad de `db_confirmar_reserva`.
- Actualiza `total_reservas` — eso es responsabilidad de `db_confirmar_reserva`.
- Envía notificaciones por WhatsApp ni por ningún otro canal.
- Usa IA.

---

## 5. Triggers

| Trigger | Uso |
|---|---|
| Manual Trigger | Pruebas desde n8n. Pasar input via pin data — el workflow no tiene datos de prueba hardcodeados. |
| When Executed by Another Workflow | Llamado como subworkflow desde `db_crear_prereserva v3`. |

Ambos triggers conectan al mismo nodo `Resolver Input`. La lógica ejecutada es idéntica en ambos casos.

---

## 6. Input esperado

```json
{
  "nombre": "Juan",
  "apellido": "García",
  "dni": "12345678",
  "telefono": "+5491112345678",
  "email": "juan@email.com",
  "canal_preferido": "whatsapp",
  "notas_internas": "Tiene perro labrador",
  "source_event": "web_reserva"
}
```

| Campo | Tipo | Obligatorio | Descripcion |
|---|---|---|---|
| `nombre` | string | **Si** | Nombre del huesped. |
| `apellido` | string | No | Apellido. |
| `dni` | string | No | Sin puntos ni guiones. |
| `telefono` | string | **Si** | Clave principal de deduplicacion. Se normaliza antes de buscar. |
| `email` | string | No | Clave secundaria de deduplicacion. Se normaliza antes de buscar. |
| `canal_preferido` | string | No | Valores validos: `whatsapp`, `instagram`, `web`, `manual`. Default: `whatsapp`. |
| `notas_internas` | string | No | Texto libre. Perfil permanente del huesped (ej: "Siempre trae perro"). |
| `source_event` | string | No | Origen del evento. Default: `manual`. |

---

## 7. Normalización de datos

El workflow normaliza teléfono y email **antes de buscar y antes de guardar**.

**Teléfono:**
- Quita espacios, guiones, paréntesis y puntos.
- `0054...` → `+54...`
- `54...` (sin `+`) → `+54...`
- Ejemplo: `0054 11 1234-5678` → `+541112345678`

**Email:**
- `trim` + lowercase.
- Ejemplo: `  Juan@EMAIL.com ` → `juan@email.com`

---

## 8. Regla de deduplicación

La búsqueda sigue este orden estricto:

1. Busca en `HUÉSPEDES` por `telefono` normalizado.
2. Si no encuentra y hay `email` en el input, busca por `email` normalizado.
3. Si encuentra por `email` y el teléfono existente en la hoja está vacío → completa el teléfono con el valor del input.
4. Si no encuentra nada → **modo CREATE**: crea huésped nuevo con `id_huesped = max + 1`.
5. Si encuentra → **modo UPDATE**: actualiza solo los campos que vienen con valor real en el input.
6. Nunca borra datos existentes con campos vacíos o nulos — un campo que no viene en el input no pisa el valor guardado.

---

## 9. Output exitoso — modo creado

```json
{
  "ok": true,
  "modo": "creado",
  "id_huesped": 5,
  "nombre": "Juan",
  "apellido": "García",
  "telefono": "+5491112345678",
  "email": "juan@email.com",
  "encontrado_por": null,
  "source_event": "web_reserva"
}
```

---

## 10. Output exitoso — modo actualizado

```json
{
  "ok": true,
  "modo": "actualizado",
  "id_huesped": 3,
  "nombre": "Juan",
  "apellido": "García",
  "telefono": "+5491112345678",
  "email": "juan@email.com",
  "encontrado_por": "telefono",
  "source_event": "web_reserva"
}
```

`encontrado_por` puede ser `"telefono"`, `"email"` o `null` (si es creación).

---

## 11. Output de error — input inválido

Ocurre si falta `nombre` o `telefono`. **No escribe nada en `HUÉSPEDES`**, pero sí escribe en `LOG_CAMBIOS` con `nivel = warning`.

```json
{
  "ok": false,
  "error": "input_invalido",
  "detalle": [
    "nombre es obligatorio",
    "telefono es obligatorio"
  ]
}
```

---

## 12. Hojas que lee

| Hoja | Proposito | Puede estar vacia |
|---|---|---|
| `HUÉSPEDES` | Buscar huesped existente por telefono o email. Calcular `max(id_huesped)`. | Si |

---

## 13. Hojas que escribe

| Hoja | Operacion | Cuando |
|---|---|---|
| `HUÉSPEDES` | Append 1 fila | Modo CREATE: telefono y email no encontrados |
| `HUÉSPEDES` | Update row por `id_huesped` | Modo UPDATE: huesped encontrado |
| `LOG_CAMBIOS` | Append 1 fila | Siempre — creacion, actualizacion y `input_invalido` |

---

## 14. Columnas de HUÉSPEDES afectadas

### En creación — 12 columnas

| Campo | Valor escrito |
|---|---|
| `id_huesped` | `max(id_huesped) + 1` |
| `nombre` | Del input |
| `apellido` | Del input o vacío |
| `dni` | Del input o vacío |
| `telefono` | Del input normalizado |
| `email` | Del input normalizado o vacío |
| `canal_preferido` | Del input o `whatsapp` |
| `primera_reserva_fecha` | Vacío — lo completa `db_confirmar_reserva` |
| `total_reservas` | `0` — lo actualiza `db_confirmar_reserva` |
| `notas_internas` | Del input o vacío |
| `created_at` | Timestamp de ejecucion |
| `updated_at` | Timestamp de ejecucion |

### En actualización — máximo 9 columnas

Solo se actualizan los campos que vengan con valor real en el input. Si un campo no viene o viene vacío, el valor existente en la hoja **no se toca**.

| Campo | Condicion |
|---|---|
| `nombre` | Si viene con valor |
| `apellido` | Si viene con valor |
| `dni` | Si viene con valor |
| `telefono` | Solo si encontro por email Y el telefono existente estaba vacio |
| `email` | Si viene con valor |
| `canal_preferido` | Si viene con valor |
| `notas_internas` | Si viene con valor |
| `updated_at` | Siempre — timestamp de ejecucion |
| `id_huesped` | Campo de matching — no se modifica |

### En actualización — nunca se tocan

| Campo | Razon |
|---|---|
| `created_at` | Timestamp original de creacion. Inmutable. |
| `primera_reserva_fecha` | Responsabilidad de `db_confirmar_reserva`. |
| `total_reservas` | Responsabilidad de `db_confirmar_reserva`. |

---

## 15. LOG_CAMBIOS generado

| Caso | `campo_modificado` | `nivel` | Notas |
|---|---|---|---|
| Creacion exitosa | `created` | `info` | Detalle incluye `modo`, `id_huesped`, `nombre`, `telefono` |
| Actualizacion exitosa | `updated` | `info` | Detalle incluye `modo`, `id_huesped`, `nombre`, `telefono`, `encontrado_por` |
| Input invalido | `validacion_input` | `warning` | Detalle incluye `error` y array `detalle` con campos faltantes |

El log de `input_invalido` se escribe **siempre**, incluso si no se tocó ninguna hoja de datos. Permite auditar llamadas mal formadas desde formularios o bots.

---

## 16. Concurrencia

**`id_huesped` se calcula como `max(id_huesped) + 1`.**

Esto puede generar IDs duplicados si dos ejecuciones corren en paralelo y leen el mismo max antes de que alguna escriba.

**Configuracion requerida:** `Max Concurrency = 1` en Settings del workflow.

No ejecutar en paralelo. Para produccion con alta concurrencia, migrar a UUID o base de datos relacional con secuencias.

---

## 17. Casos de prueba

| # | Caso | Input | Resultado esperado |
|---|---|---|---|
| 1 | Huesped nuevo completo | Todos los campos | `modo: creado`, 12 columnas en HUÉSPEDES, LOG info |
| 2 | Huesped nuevo minimo | Solo `nombre` + `telefono` | `modo: creado`, campos opcionales vacios, `total_reservas: 0` |
| 3 | Mismo telefono, segunda vez | Telefono existente + email nuevo | `modo: actualizado`, mismo `id_huesped`, email actualizado, `encontrado_por: telefono` |
| 4 | Email existente como fallback | Email ya registrado + telefono diferente | `modo: actualizado`, `encontrado_por: email`, telefono completado si estaba vacio |
| 5 | Telefono con formato sucio | `0054 11 1234-5678` | Normalizado a `+541112345678`, busca/crea correctamente |
| 6 | Input vacio | `{}` | `input_invalido`, LOG warning, no toca HUÉSPEDES |
| 7 | Update parcial | Telefono existente + solo apellido nuevo | Solo `apellido` y `updated_at` cambian, resto intacto |

---

## 18. Variables del template

Reemplazar estos valores en el template antes de importar en n8n:

| Variable | Que poner |
|---|---|
| `__SHEETS_ID__` | ID del Google Sheet del entorno (DEV, TEST o PROD) |
| `__ENTORNO__` | Nombre del entorno (ej: `VITA_DELTA_DEV`) |
| `__CREDENTIAL_ID__` | ID de la credencial OAuth de Google Sheets en la instancia n8n |
| `__CREDENTIAL_NAME__` | Nombre de la credencial OAuth en la instancia n8n |
| `__WORKFLOW_ID__` | ID asignado por n8n al importar |
| `__WORKFLOW_VERSION_ID__` | Version ID asignado por n8n al importar |
| `__N8N_INSTANCE_ID__` | Instance ID de la instancia n8n |

El SHEETS_ID esta en la URL del Sheet:
```
https://docs.google.com/spreadsheets/d/__SHEETS_ID__/edit
```

---

## 19. Relacion con otros workflows

| Workflow | Relacion |
|---|---|
| `db_crear_prereserva v3` | Llama a `db_crear_huesped` como subworkflow. Recibe `id_huesped` en el output y lo incluye en la PRE_RESERVA. |
| `db_confirmar_reserva` | No llama a este workflow. Pero es responsable de actualizar `primera_reserva_fecha` y `total_reservas` en HUÉSPEDES cuando una reserva se confirma. |

**Flujo esperado:**

```
Formulario web / bot
  → db_crear_huesped        crea o actualiza huesped → devuelve id_huesped
  → db_crear_prereserva     usa id_huesped para crear PRE_RESERVA
  → db_registrar_pago       registra pago
  → db_confirmar_reserva    confirma reserva + actualiza primera_reserva_fecha y total_reservas
```

---

## 20. Garantías del workflow

Al finalizar exitosamente, este workflow garantiza:

- **No duplica por telefono:** si el telefono normalizado ya existe, actualiza en lugar de crear.
- **Reduce duplicados por email:** si el email ya existe y el telefono no se encontró, actualiza el huésped existente.
- **No borra datos existentes:** un campo que no viene en el input no pisa el valor guardado en la hoja.
- **Deja auditoría:** toda ejecución — exitosa o fallida por input inválido — escribe en `LOG_CAMBIOS`.
- **No afecta reservas ni disponibilidad:** no toca PRE_RESERVAS, RESERVAS, PAGOS, DISPONIBILIDAD_CACHE ni el calendario operativo.
- **`primera_reserva_fecha` y `total_reservas` quedan intactos:** se inicializan en vacío/0 en la creación y no se modifican en la actualización. Solo `db_confirmar_reserva` los actualiza.

### Deudas técnicas conocidas

| Deuda | Severidad | Nota |
|---|---|---|
| `id_huesped = max + 1` con posible race condition | Media | Mitigado con Max Concurrency = 1. Solucion definitiva: UUID o DB relacional. |
| Normalizacion de telefono minima | Baja | No valida largo, codigo de area ni formato internacional mas alla de `+54`. Suficiente para v1. |
| Sin validacion de formato de email | Baja | Solo normaliza, no valida. Un email mal formado se guarda igual. |
| Sin merge de huespedes duplicados | Media | Si el mismo huesped existe con dos telefonos distintos, quedaran dos filas. No hay mecanismo de merge en v1. |
