# 6C_CIERRE.md — Cierre formal de Etapa 6C

**Etapa:** 6C — Reescritura de workflows n8n contra Supabase DEV
**Fecha de apertura:** 2026-05-25 (post-cierre de 6B v1.7.1)
**Fecha de cierre:** 2026-05-26
**Estado:** ✅ CERRADA
**Documento canónico de referencia:** este archivo.

---

## Resumen ejecutivo

Etapa 6C consistió en construir, validar y documentar los workflows n8n que operan contra el schema Supabase DEV definido en 6B v1.7.1. El alcance fue **8 workflows manuales determinísticos** (W0 a W7) que cubren los principales contratos del schema: smoke test, consulta de disponibilidad, las 4 funciones write críticas, una función de creación de bloqueos, y las 6 vistas operativas.

**Todos los workflows están operativos en DEV con tests aprobados.** El patrón de trabajo (verificación read-only de contrato real → diseño → JSON importable → tests ordenados → exportación → sanitización → bitácora) quedó establecido y es reutilizable para futuras integraciones.

La etapa no es una API productiva final. Es una **validación operativa controlada** del puente n8n ↔ Supabase con workflows manuales. Los consumidores reales (webhook de MercadoPago, bot conversacional, frontend, Cowork de socios) son etapas posteriores que usarán estos workflows como base.

---

## Alcance ejecutado

### Workflows cerrados

| # | Workflow | Función / vista | Modo | Tests | Cierre |
|---|---|---|---|---|---|
| W0 | smoke test | conexión Supabase | Postgres node | 1 query | 2026-05-25 |
| W1 | consultar disponibilidad | `obtener_disponibilidad_rango(date, date, bigint)` | parameter binding | 4 tests | 2026-05-25 |
| W2 | crear pre-reserva | `crear_prereserva(jsonb)` | JSONB | 5 tests | 2026-05-25 |
| W3 | registrar pago | `registrar_pago(jsonb)` | JSONB | 4 tests | 2026-05-25 |
| W4 | confirmar reserva | `confirmar_reserva(jsonb)` | JSONB | 5 tests | 2026-05-26 |
| W5 | cancelar pre-reserva | `cancelar_prereserva(jsonb)` | JSONB | 6 tests + W1 cruzado | 2026-05-26 |
| W6 | crear bloqueo | `crear_bloqueo(jsonb)` | JSONB | 8 tests + 2 W1 cruzados | 2026-05-26 |
| W7 | vistas operativas | 6 vistas read-only | query dinámica + IF | 7 tests | 2026-05-26 |

**Total: 8 workflows operativos, 40 tests funcionales aprobados, 3 verificaciones cruzadas end-to-end con W1.**

### Pre-fase: alineación 6B v1.7.1

Antes de abrir 6C, se ejecutó el cierre formal de 6B v1.7.1 (actualización de `obtener_disponibilidad_rango()` para aplicar la regla del check-out dominical en `hora_checkout_base`). Documentado en `BITACORA_ENTRADA_CIERRE_6B_v1.7.1.md`. **DEV quedó 100% alineado con el schema canónico antes de abrir 6C.**

---

## Convenciones consolidadas durante la etapa

### Naming de workflows

```
vita_w{NN}_{nombre_corto}_supabase
```

Ejemplos: `vita_w01_consultar_disponibilidad_supabase`, `vita_w07_vistas_operativas_supabase`.

### Naming de templates en el repo

```
Workflows/n8n/supabase/{nombre_workflow}.template.json
```

### Source events

Convención fija para 6C: `n8n_w{NN}_{nombre_corto}_manual`. No incluye el ambiente (DEV/TEST/PROD) — la trazabilidad de ambiente queda en el `id_evento_dev` cuando aplica.

### Estructura de wrapper externo

Todos los workflows usan un wrapper consistente alrededor del JSONB devuelto por la función SQL:

```json
{
  "ok": true/false,
  "workflow": "vita_wNN_nombre_supabase",
  "source_event": "n8n_wNN_nombre_manual",
  "idempotency_key": "..." | null (solo W2),
  "id_evento_dev": "..." (cuando aplica trazabilidad de prueba),
  "vista": "..." (solo W7),
  "error": null | "codigo",
  "warning": null | "codigo" (solo W3),
  "result": <JSONB completo de la función>,
  "executed_at": "ISO timestamp"
}
```

### Estructura del workflow

| Patrón | Workflows |
|---|---|
| **5 nodos lineal**: Manual Trigger → Build Input → Build Payload → Postgres → Build Response | W2, W3, W4, W5, W6 |
| **4 nodos lineal**: Manual Trigger → Build Input → Postgres → Build Response | W1 |
| **6 nodos con ramificación IF**: Manual Trigger → Build Input → Build Query → IF → (true → Build Response \| false → Postgres → Build Response) | W7 |

### Convención de "todas las cabañas"

**Diferente entre W1 y W6**, documentado:

- **W1** (`obtener_disponibilidad_rango`): `id_cabana = 0` significa "todas". La función usa `NULLIF($N::TYPE, 0)` para mapear a NULL.
- **W6** (`crear_bloqueo`): `id_cabana = null` significa "todas". La función no trata 0 como caso especial — `0` resultaría en `cabana_no_existe`.

Esto **NO es un bug**, es una diferencia de contrato entre funciones. Cada función define su propia semántica. Se verifica siempre el contrato real antes de asumir.

### Normalización defensiva en Build Payload

Patrón establecido a partir de W3: aplicar `nv()` (función que convierte `""` o `undefined` a `null`) a **todos los campos del payload, incluidos los obligatorios**.

Razón: las funciones SQL del schema actual no aplican uniformemente `NULLIF(TRIM(...))` a los campos obligatorios de texto. Mandar `""` desde n8n puede pasar la validación inicial (`v_campo IS NULL` falla porque `""` no es NULL) y chocar contra CHECK constraints, generando errores crudos de Postgres en vez de JSONB estructurado.

Mientras el **hardening SQL no se aplique** (ver Pendientes), la defensa queda en n8n.

### Idempotencia

Distinta según función SQL:

| Función | Idempotencia |
|---|---|
| `crear_prereserva` | Sí, con `idempotency_key` + `idempotent_match=true` en la respuesta |
| `registrar_pago` | No (deduplicación es responsabilidad del caller — webhook MP) |
| `confirmar_reserva` | No (re-ejecutar devuelve `estado_invalido` con `estado_actual`) |
| `cancelar_prereserva` | No (re-ejecutar devuelve `estado_no_cancelable` con `estado_actual`) |
| `crear_bloqueo` | No (re-ejecutar devuelve `bloqueo_solapado` con `bloqueos_en_conflicto`) |

Esto refleja que `crear_prereserva` es la única **puerta única** crítica donde una re-ejecución accidental (ej. doble click del usuario) debe resolverse silenciosamente. Las demás funciones tienen estados que hacen la idempotencia menos crítica — pero el caller siempre tiene contexto (ID previo + estado actual) para reaccionar.

---

## Patrón de trabajo establecido

Cada workflow nuevo siguió la misma secuencia:

1. **Verificación read-only de firma** con `pg_get_function_result` o `information_schema.columns` (para vistas).
2. **Inspección del cuerpo de la función** con `pg_get_functiondef`, o de la definición de la vista con `pg_views`.
3. **Verificación de CHECK constraints** o EXCLUDE constraints si aplica.
4. **Diseño en chat** con aprobación explícita de decisiones.
5. **JSON importable** generado (sin sanitizar, con credential ID real para que Franco lo importe directo).
6. **Tests ordenados** (no destructivos primero, destructivos al final).
7. **Verificación cruzada con W1** cuando aplica (W5, W6).
8. **Franco exporta el workflow** desde n8n con sus IDs reales.
9. **Claude sanitiza** el export (credenciales, IDs internos, valores de tests) y produce el template del repo.
10. **Bitácora detallada** con tabla de tests aprobados, decisiones, observaciones menores.
11. **Lecciones aprendidas** o bloques en `Pendiente_pre_produccion.md` si hay gotchas o hallazgos.

Esta secuencia se cumplió en los 8 workflows. Es la base reutilizable para integraciones futuras.

---

## Gotchas y lecciones aprendidas — Catálogo 6C

| ID | Tema | Descripción resumida | Mitigación aplicada |
|---|---|---|---|
| L-6C-01 | SSL con Supabase pooler | Conexión Postgres node falla por SSL strict | "Ignore SSL Issues: ON" en la credencial vita_supabase_dev |
| L-6C-02 | (reservado) | — | — |
| L-6C-03 | Query Parameters n8n + NULL | n8n no soporta NULL real en Query Parameters: strings vacíos se omiten, `null` se serializa como `"null"` literal | Convención `id_cabana=0 = todas` + `NULLIF($N::TYPE, 0)` en función SQL (W1) |
| L-6C-04 | Resultados vacíos detienen flujo | Postgres node con result vacío detiene la ejecución | `Always Output Data: ON` en el nodo + filter defensivo en Code downstream |
| L-6C-05 | Tipos serializados como strings | BIGINT serializa como string en JSON, DATE como ISO timestamp | Documentado en bitácora W1; no requiere fix, solo conciencia operativa |
| L-6C-06 | JSONB stringify funciona limpio | `={{ JSON.stringify($json.payload) }}` en queryReplacement funciona sin problemas para JSONB | Patrón establecido en W2-W6, contrapunto a L-6C-03 |
| L-6C-07 | Normalización defensiva en obligatorios | Funciones SQL no aplican uniformemente `NULLIF` a campos obligatorios → strings vacíos chocan contra CHECK constraints | `nv()` aplicado a TODOS los campos en Build Payload de W3-W6. Hardening SQL pendiente. |
| L-6C-08 | Convención "todas las cabañas" | W1 usa `id_cabana=0`, W6 usa `id_cabana=null`. Diferencia de contrato, no bug | Documentado en código de cada Build Payload con comentario explícito |
| L-6C-09 | IF node para validación temprana | Si la validación detecta error antes de Postgres, hay que ramificar para no ejecutar query inválida | Patrón aplicado en W7 con nodo IF + flag `__validation_error` |

**Total: 8 lecciones nuevas catalogadas** (excluyendo L-6C-02 reservado para histórico). Todas documentadas en `Docs/Operacional/Lecciones_Aprendidas.md` con detalle y mitigación.

---

## Hallazgos pendientes generados durante 6C

Todos documentados en `Docs/Operacional/Pendiente_pre_produccion.md`:

### 1. Hardening de validación SQL en funciones write

**Origen:** W3 (registrar_pago).
**Prioridad:** alta antes de TEST/PROD.

Las funciones write del schema no aplican uniformemente `NULLIF(TRIM(...))` a los campos obligatorios de texto. Esto permite que strings vacíos pasen la validación inicial y choquen contra CHECK constraints, generando errores crudos.

**Funciones a auditar:**
- `registrar_pago()` — confirmado: aplica a `tipo` y `medio_pago`.
- `crear_prereserva()` — revisar campos distintos a `huesped.nombre`.
- `confirmar_reserva()` — revisar al re-auditar.
- `cancelar_prereserva()` — revisar al re-auditar.
- `crear_bloqueo()` — revisar al re-auditar.
- `upsert_huesped()` — revisar campos obligatorios.

**Fix patrón:**

```sql
v_campo := NULLIF(TRIM(payload->>'campo'), '');
```

Pattern de referencia: `crear_prereserva()` v1.7 ya lo aplica al nombre del huésped.

### 2. `vista_ocupacion` devuelve 25 meses en vez de 24

**Origen:** W7 (vistas operativas), Test 4.
**Prioridad:** baja (micro-imprecisión, no rompe lógica).

`generate_series` con paso temporal incluye ambos extremos → 25 meses × 5 cabañas = 125 filas.

**Fix patrón:**

```sql
-- En la definición de vista_ocupacion
generate_series(
  date_trunc('month', CURRENT_DATE) - '1 year'::interval,
  date_trunc('month', CURRENT_DATE) + '1 year'::interval - '1 mon'::interval,
  '1 mon'
)
```

### 3. Espacio colgando en concatenación nombre + apellido

**Origen:** W7, Test 3.
**Prioridad:** muy baja (cosmético).

`vista_calendario` y `vista_limpieza_semana` concatenan `nombre || ' ' || COALESCE(apellido, '')`. Si `apellido = ""`, queda espacio al final.

**Fix patrón:**

```sql
TRIM(nombre || ' ' || COALESCE(apellido, ''))
```

O atacar el problema raíz en `upsert_huesped` con `NULLIF(TRIM(apellido), '')` antes de insertar.

---

## Tests cruzados diferidos para futuras sesiones

Los siguientes casos quedaron documentados pero no ejecutados en 6C:

| Caso | Origen | Razón del diferimiento |
|---|---|---|
| Caso v1.3 (pago tardío sobre pre-reserva terminal) | W3 | Requiere pre-reserva en estado terminal — combinación post-W5 |
| Pago automático confirmado (`estado_inicial="confirmado"`) | W3 | Es el camino del webhook MP futuro, no aplica probarlo manualmente |
| `conflicto_al_confirmar` de W4 | W4 | Requiere reproducir condición de carrera entre creación y confirmación |
| Cancelación con motivo `"bloqueo"` | W5 | Funcionalmente equivalente a `"cliente"`, solo cambia el estado_nuevo |
| Cancelación con pagos asociados | W5 | Requiere W2+W3+W5, queda como cruzado |
| Bloqueo total con conflicto | W6 | Estructuralmente equivalente al modo específico |
| Bloqueo solapado total vs específico | W6 | Requiere coordinación de orden con Test 8 |
| Cancelación con pre-reserva en `pago_en_revision` | W5 | Variante del happy path |
| Expiración natural de pre-reserva (cron) | W2 | Infraestructura existe (job pg_cron cada 5 min); no se forzó esperar 60 min |

Estos tests son razonables de agrupar en una sesión futura corta de "pruebas cruzadas pre-TEST" que valide combinaciones específicas.

---

## Estado de DEV al cierre de 6C

| Recurso | ID | Estado | Origen |
|---|---|---|---|
| Pre-reserva | 25 | `convertida` (terminal) | Creada en W2, confirmada en W4 |
| Pre-reserva | 26 | `cancelada_por_cliente` (terminal) | Creada en W2 como pre-requisito de W5, cancelada en W5 |
| Pago | 11 | `confirmado`, validado por `rodrigo_manual` | Creado en W3, confirmado en W4 |
| Reserva | 8 | `confirmada`, cabaña 17 (Bamboo), 10-13 jul 2026, `monto_saldo=100000` | Creada en W4 |
| Huésped | 34 | `total_reservas=1`, `primera_reserva_fecha=2026-07-10` | Creado en W2, contador actualizado en W4 |
| Huésped | 35 | `total_reservas=0` | Creado en W2 (pre-requisito W5), pre-reserva cancelada |
| Bloqueo | 6 | activo, cabaña 19 (Arrebol), 15-18 sep 2026, motivo `mantenimiento` | Creado en W6 |
| Bloqueo | 7 | activo, **total** (id_cabana=NULL), 20-22 nov 2026, motivo `tormenta` | Creado en W6 |

**Bloqueos pre-existentes en DEV** (IDs 1-5): origen probable seed/pruebas tempranas, no creados en 6C. Documentados como curiosidad, no interfieren.

**Ciclo de vida de pre-reservas validado en sus 3 caminos:**

| Camino | Workflows aplicados | Estado terminal | Ejemplo |
|---|---|---|---|
| Confirmación | W2 → W3 → W4 | `convertida` | Pre-reserva 25 |
| Cancelación cliente | W2 → W5 | `cancelada_por_cliente` | Pre-reserva 26 |
| Expiración automática | W2 → cron pg_cron | `vencida` | No probado en 6C (infraestructura existe) |

---

## Entregables del repo generados durante 6C

### Templates de workflows

```
Workflows/n8n/supabase/
├── vita_w00_smoke_test_supabase.template.json
├── vita_w01_consultar_disponibilidad_supabase.template.json
├── vita_w02_crear_prereserva_supabase.template.json
├── vita_w03_registrar_pago_supabase.template.json
├── vita_w04_confirmar_reserva_supabase.template.json
├── vita_w05_cancelar_prereserva_supabase.template.json
├── vita_w06_crear_bloqueo_supabase.template.json
├── vita_w07_vistas_operativas_supabase.template.json
└── README.md
```

### Bitácora

`Docs/Bitacora/6C_EJECUCION.md` con 8 entradas (W0-W7), cada una con verificación previa, decisiones, tabla de tests, observaciones y estado final.

### Lecciones aprendidas

`Docs/Operacional/Lecciones_Aprendidas.md` con bloques L-6C-01 a L-6C-09.

### Pendientes pre-producción

`Pendiente_pre_produccion.md` con 3 items nuevos:
- Hardening de validación SQL en funciones write.
- Fix de `vista_ocupacion` (25 vs 24 meses).
- Fix cosmético de concatenación `nombre + apellido` en vistas.

---

## Decisiones cerradas durante 6C — NO REABRIR

1. **Templates en el repo, no exports crudos.** Sanitización con placeholders (`__CREDENTIAL_ID__`, `__WORKFLOW_VERSION_ID__`, etc.) es obligatoria.
2. **`Build Input` de templates con valores del happy path**, no del último test ejecutado.
3. **Normalización defensiva con `nv()` en Build Payload** para todos los obligatorios, hasta que hardening SQL se aplique.
4. **`source_event` no incluye ambiente.** La trazabilidad de ambiente queda en `id_evento_dev` cuando aplica.
5. **W1 usa `id_cabana=0=todas`, W6 usa `id_cabana=null=total`.** Diferencia de contrato, no se unifica.
6. **W7 es paramétrico** (un solo workflow para 6 vistas), no se divide en W7a-W7e hasta que existan consumidores reales.
7. **Idempotencia solo donde la función SQL la implementa.** No agregar idempotencia client-side artificial.
8. **Tests cruzados con W1** son obligatorios para workflows que modifican disponibilidad (W5 cancelación, W6 bloqueo).

---

## Próxima etapa — Por decidir

Con 6C cerrado, las opciones inmediatas son:

### Opción A — Hardening pre-producción

Ejecutar los items de `Pendiente_pre_produccion.md`:
- NULLIF + TRIM en funciones write.
- Fix de `vista_ocupacion`.
- Fix cosmético de concatenaciones.

**Ventaja:** cierra deudas técnicas conocidas antes de TEST/PROD.
**Costo:** sesión corta de SQL (1-2 horas), poco riesgo.

### Opción B — Entorno TEST

Replicar DEV en un proyecto Supabase separado para empezar a integrar consumidores reales.

**Ventaja:** habilita pruebas con webhook MP, frontend, etc., sin riesgo a datos reales.
**Costo:** sesión media (2-3 horas) — duplicar schema, seeds, credenciales, ajustar workflows n8n para parametrizar ambiente.

### Opción C — Webhook MercadoPago

Workflow operativo real que invoca W3 (registrar_pago) tras un webhook de MP.

**Ventaja:** primer flujo productivo end-to-end.
**Costo:** sesión larga (3-4 horas) — diseño del webhook, deduplicación de `payment_id`, manejo de estados, integración con W4 si el monto matchea.

### Opción D — Bot conversacional (Etapa 4B implementación)

Lo que originalmente venía después del motor de reservas.

**Ventaja:** habilita el canal principal de consultas (Instagram + WhatsApp).
**Costo:** sesión larga, depende de definiciones de Etapa 4B y de tener Meta API conectada.

**Decisión recomendada:** **A primero, después B.** Cerrar deudas técnicas conocidas antes de complicar el sistema con nuevos consumidores. Una vez con DEV limpio y TEST levantado, las opciones C y D pueden avanzarse con seguridad operativa.

---

## Resumen del cierre

**Etapa 6C cerrada formalmente al 2026-05-26.**

- ✅ 8 workflows operativos en DEV.
- ✅ 40 tests funcionales aprobados.
- ✅ 3 verificaciones cruzadas end-to-end.
- ✅ 9 lecciones aprendidas catalogadas.
- ✅ 3 pendientes pre-producción identificados y documentados.
- ✅ Patrón de trabajo establecido y reutilizable.
- ✅ Templates sanitizados en repo.
- ✅ Bitácora detallada por workflow.

La etapa demostró que el contrato n8n ↔ Supabase funciona limpio para los flujos críticos del negocio, con tiempos de respuesta razonables y trazabilidad completa vía `source_event` + `log_cambios`. Está listo para que en etapas futuras se incorporen consumidores reales (webhook MP, bot, frontend) sin reabrir decisiones arquitecturales.

---

*Documento de cierre formal generado el 2026-05-26.*
*Próxima sesión arranca con decisión de etapa (A / B / C / D).*
