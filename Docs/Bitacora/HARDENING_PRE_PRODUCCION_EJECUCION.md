# Hardening Pre-Producción — Bitácora de Ejecución

**Etapa:** Opción A — Hardening pre-producción de Vita Delta Reservas
**Fecha de apertura:** 2026-05-26
**Estado:** En curso
**Documento canónico de referencia:** este archivo.

## Resumen ejecutivo

Esta etapa consolida 4 frentes de hardening sobre Supabase DEV antes de
levantar entorno TEST, según la recomendación documentada en
`6C_CIERRE.md`:

1. **Hardening SQL de funciones write** — normalización defensiva de
   campos derivados de `payload->>'...'` para evitar errores crudos de
   PostgreSQL ante strings vacíos o whitespace.
2. **Fix de `vista_ocupacion`** — corregir 25 vs 24 meses por edge case
   del `generate_series`.
3. **Fix cosmético de concatenaciones nombre + apellido** — eliminar
   espacios colgando en `vista_calendario` y `vista_limpieza_semana`,
   y normalizar huéspedes existentes en DEV.
4. **Tests de concurrencia C-1 a C-4** — ejecutar los 4 tests con
   `pg_sleep` documentados en `6B_PLAN_FASES.md` Sección 6.8.

**Schema:** v1.7.1 → v1.7.2 al cierre de los bloques que efectivamente
modifiquen el cuerpo de funciones o vistas.

**Alcance NO cubierto:**
- Entorno TEST.
- Workflows n8n (los `nv()` defensivos quedan como defensa en profundidad).
- Validación de tipos inválidos no vacíos (`monto="abc"`, `boolean="blabla"`).
- Reabrir contratos JSONB, lógica de negocio, locks, idempotencia.
- MercadoPago, WhatsApp, bot conversacional, web pública, RLS, tarifas
  reales, feriados.

---

## H1 — Decisiones previas

**Fecha:** 2026-05-26
**Estado:** Cerrado ✅

### Decisiones aprobadas por Franco

| # | Decisión | Aprobada |
|---|---|---|
| D-H1-1 | **TRIM agresivo en obligatorios.** Strings con solo whitespace (`"   "`) deben tratarse como vacíos y rebotar con `payload_invalido` igual que `""`. | Sí |
| D-H1-2 | **TRIM también en opcionales** donde ya exista `NULLIF`. Patrón uniforme en todo el extract, no tipo-dependiente. | Sí |
| D-H1-3 | **Bump documental a `6B_SCHEMA_SQL.md v1.7.2`** porque se modifican bodies de funciones y al menos una vista, aunque no cambie estructura de tablas. | Sí |

### Ajustes adicionales al plan original

1. **No cambiar obligatoriedad de campos.** El hardening normaliza
   valores vacíos/whitespace, no convierte opcionales en obligatorios
   ni viceversa.
2. **Máxima prudencia en `crear_prereserva` (Bloque H4).** Antes de
   proponer SQL final, mostrar extract actual exacto, diff mínimo
   propuesto y confirmación de que no se toca locks, horarios,
   idempotencia, validación de disponibilidad ni handler de
   `unique_violation`.
3. **Orden de ejecución aprobado:** H2 → H3 → H4 → H5 → H6 → cierre
   documental parcial → H7 (tests de concurrencia) solo cuando los
   parches previos estén estables y con plan de limpieza explícito.
4. **No actualizar documentos diciendo "hardening cerrado"** hasta
   tener ejecutados y verificados todos los bloques que decidamos
   cerrar.
5. **No tocar workflows n8n.** Los `nv()` quedan como defensa en
   profundidad.

### Patrón canónico aprobado

```sql
v_campo := NULLIF(TRIM(payload->>'campo'), '')::TIPO;
```

Aplica a funciones SQL con payload JSONB en el extract.
NO aplica a vistas (H5, H6 — sin payload).
Este patrón cubre strings vacíos y whitespace antes del cast. No
reemplaza validaciones específicas para valores inválidos no vacíos.

### Flujo de trabajo estándar (snapshot-first, a partir de H3)

A partir del Bloque H3, todo cambio sobre función existente se hace así:

1. **Pieza 1 — Snapshot:** Claude pasa solo la query
   `pg_get_functiondef()` o `pg_get_viewdef()`. Franco ejecuta y
   devuelve el cuerpo real.
2. **Diseño desde cuerpo real:** Claude reconstruye el `CREATE OR
   REPLACE` desde el resultado de la Pieza 1, no desde el schema
   canónico. Único cambio permitido: el bloque del extract.
3. **Aprobación:** Franco revisa el diff y aprueba.
4. **Sanity pre-cambio, ejecución, verificación de registro, tests,
   sanity post.**

Razón: el schema canónico `6B_SCHEMA_SQL.md` puede divergir del cuerpo
real en DEV. Documentado en H2-L1.

---

## H2 — Hardening de `registrar_pago`

**Fecha:** 2026-05-26
**Estado:** Cerrado ✅
**Función afectada:** `registrar_pago(jsonb)`
**Versión schema:** v1.7.1 → v1.7.2

### Cambio aplicado

Sección "1. Extraer payload" reemplazada por extract defensivo unificado.
Todos los campos derivados de `payload->>'...'` pasan por
`NULLIF(TRIM(...),'')` antes del cast. Patrón aplicado al bloque de
extracción del payload, cubriendo 17 variables derivadas de
`payload->>'...'`.

### Resto de la función

Idéntico al cuerpo real pre-cambio (Pieza 1):
- DECLARE con 23 variables.
- Sección 1.bis (`set_config` para triggers D38) con guarda `IF v_source_event IS NOT NULL`.
- Sección 2 (validaciones `referencia_requerida` + `payload_invalido`).
- Sección 3 (verificación existencia + detección estado terminal v1.3).
- Sección 4 (decisión de `v_estado_final` con 3 ramas).
- Sección 5 (INSERT en pagos con 18 columnas).
- Sección 6 (UPDATE condicional con doble guarda).
- Sección 7 (INSERT `log_cambios` preservando `COALESCE(v_validado_por, 'registrar_pago')`,
  cast a `nivel_log_enum` y campo `es_automatico`).
- Sección 8 (RETURN con guarda `v_prereserva_no_activa`).

### Verificación

| Pieza | Resultado |
|---|---|
| 1 — Snapshot pre-cambio | Cuerpo real capturado |
| 2 — Sanity check pre | pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, logs=11 |
| 3-bis — CREATE OR REPLACE | Success. No rows returned |
| 4 — Registro | `registrar_pago | v | 1` |
| 5 — 15 tests | 15/15 ok=true |
| 6 — Sanity check post | Conteos idénticos a Pieza 2; `logs_de_tests=0` |

### Tests aprobados

**Strings vacíos en obligatorios → `payload_invalido`:**
- T1 (`tipo`), T3 (`medio_pago`), T5 (`source_event`), T7 (`monto_esperado`), T9 (`monto_recibido`).

**Whitespace puro en obligatorios → `payload_invalido`:**
- T2 (`tipo`), T4 (`medio_pago`), T6 (`source_event`), T8 (`monto_esperado`), T10 (`monto_recibido`).

**Strings vacíos/whitespace en `id_pre_reserva` con `id_reserva=null` → `referencia_requerida`:**
- T11, T12 — valida que `NULLIF(TRIM(...),'')::BIGINT` convierte correctamente a NULL antes de evaluar referencia.

**Vacíos/whitespace en `es_automatico` (opcional) → cae a default `false` sin romper:**
- T13, T14 — confirma que el cast a BOOLEAN no rompe con `""` ni `"   "`.

**Regresión funcional:**
- T15 — payload bien formado con `id_pre_reserva` inexistente devuelve `prereserva_no_existe`.

### Hallazgos generados

**H2-L1 (Lección crítica):** el schema canónico `6B_SCHEMA_SQL.md v1.7.1`
tiene diferencias menores con el cuerpo real en DEV (líneas de log y
return). Para todo cambio futuro en funciones existentes, la fuente de
verdad es `pg_get_functiondef()` de DEV, no el schema canónico.

**H2-L2 (Observación operativa):** DEV se limpió entre el cierre de 6C
(2026-05-26) y la apertura del hardening. Conteos pre-H2:
pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2.
Los IDs del cierre de 6C ya no existen en DEV.

**H2-L3 (Flujo de trabajo):** a partir del Bloque H3 se aplica el patrón
snapshot-first. Documentado en H1.

### Alcance NO cubierto por H2

- Validación de tipos inválidos no vacíos. Casos como
  `monto_esperado="abc"`, `id_pre_reserva="abc"`, `es_automatico="blabla"`
  todavía pueden producir error de cast crudo. Queda fuera del alcance
  del hardening por strings/whitespace. Decisión posterior si se
  considera necesario.

### Patrón canónico establecido

```sql
v_campo := NULLIF(TRIM(payload->>'campo'), '')::TIPO;
```

Aplica a funciones SQL con payload JSONB en el extract.
NO aplica a vistas (H5, H6 — sin payload).
Este patrón cubre strings vacíos y whitespace antes del cast. No
reemplaza validaciones específicas para valores inválidos no vacíos.

---

## H3 — Hardening de `confirmar_reserva`

**Fecha:** 2026-05-26
**Estado:** Cerrado ✅
**Función afectada:** `confirmar_reserva(jsonb)`
**Versión schema:** v1.7.2

### Cambio aplicado

Sección "1. Extraer payload" reemplazada por extract defensivo unificado.
Patrón aplicado al bloque de extracción del payload, cubriendo 6 variables
derivadas de `payload->>'...'`: `v_id_pre_reserva`, `v_permitir_pago_en_revision`,
`v_validado_por`, `v_encargado_semana`, `v_created_by`, `v_source_event`.

Vulnerabilidades cerradas:
- **Casts duros**: `id_pre_reserva` (BIGINT) y `permitir_pago_en_revision`
  (BOOLEAN) ya no rompen con string vacío o whitespace; rebotan controlado.
- **NULLIF sin TRIM**: `validado_por`, `encargado_semana`, `created_by` y
  `source_event` ahora normalizan whitespace además de vacío.

### Resto de la función

Idéntico al cuerpo real pre-cambio (Pieza 1):
- DECLARE con 12 variables.
- Validación `payload_invalido` sobre `v_id_pre_reserva` y `v_source_event`.
- Sección 1.bis (`set_config` D38, sin guarda — se ejecuta siempre).
- Sección 1.ter (lock global `pg_advisory_xact_lock(10, 0)` — invariante v1.5).
- Sección 2 (`SELECT FOR UPDATE pre_reservas` + validación de estado).
- Sección 3 (lock por cabaña con cast `::INTEGER` — corrección v1.6).
- Sección 4 (búsqueda de pago confirmado + camino combinado con
  `sin_pago_asociado` y `sin_pago_confirmado`).
- Sección 5 (`validar_disponibilidad` + manejo de `conflicto_al_confirmar`
  con UPDATE a `conflicto_pendiente`).
- Sección 6 (INSERT reservas con captura de `exclusion_violation`).
- Sección 7 (UPDATE pre-reserva a `convertida`).
- Sección 8 (UPDATE pago asociando `id_reserva`).
- Sección 9 (UPDATE pago a `confirmado` si camino combinado).
- Sección 10 (UPDATE huésped: `total_reservas` y `primera_reserva_fecha`).
- Sección 11 (INSERT `log_cambios` con `evento='reserva_confirmada'` y campo `camino`).
- RETURN final con 4 campos: `ok`, `id_reserva`, `id_pre_reserva`, `id_huesped`.

### Verificación

| Pieza | Resultado |
|---|---|
| 1 — Snapshot pre-cambio | Cuerpo real capturado |
| 2 — Sanity check pre | pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, logs=11 |
| 3-bis — CREATE OR REPLACE | Success. No rows returned |
| 4 — Registro | `confirmar_reserva | v | 1` |
| 5 — 11 tests | 11/11 ok=true |
| 6 — Sanity check post | Conteos idénticos a Pieza 2; `logs_de_tests=0` |

### Tests aprobados

**Obligatorios con string vacío → `payload_invalido`:**
- T1 (`id_pre_reserva=""`), T3 (`source_event=""`).

**Obligatorios con whitespace puro → `payload_invalido`:**
- T2 (`id_pre_reserva="   "`), T4 (`source_event="   "`).

**Obligatorio explícitamente null → `payload_invalido`:**
- T5 (`id_pre_reserva=null`).

**Cast BOOLEAN robusto (`permitir_pago_en_revision` vacío/whitespace):**
- T6, T7 — confirma que el cast no rompe con `""` ni `"   "`, cae al default `FALSE` y rebota en `prereserva_no_existe`.

**Regresión funcional:**
- T8 — payload bien formado con `id_pre_reserva` inexistente devuelve `prereserva_no_existe`.

**Opcionales de texto con whitespace (no rompen, llegan a `prereserva_no_existe`):**
- T9 (`validado_por="   "` con `permitir_pago_en_revision=true`),
  T10 (`encargado_semana="   "`),
  T11 (`created_by="   "`).

### Cambio semántico observable en camino combinado

Después del fix, `validado_por: "   "` con `permitir_pago_en_revision: true`
se normaliza a NULL, lo que hace que la condición
`IF v_permitir_pago_en_revision AND v_validado_por IS NOT NULL` evalúe a
FALSE y la función rebote con `sin_pago_confirmado` en vez de aceptar
`"   "` como nombre de validador.

**Este comportamiento no se testea destructivamente en H3** porque
requeriría una pre-reserva real en `pago_en_revision` con pago asociado.
La validación que hacemos es estática:

1. El extract normaliza `"   "` a NULL (validado por T9 — pasa sin error
   de cast y rebota en `prereserva_no_existe`).
2. La condición `v_validado_por IS NOT NULL` en la sección 4 está intacta.

Conclusión por análisis estático: con `validado_por` normalizado a NULL,
la rama combinada queda inalcanzable, exactamente como debería rebotar
la función. Si se necesita validación empírica del flujo combinado
completo, se puede hacer en una sesión cruzada post-hardening con plan
de limpieza explícito.

### Hallazgos generados

Ninguno nuevo. El bloque consolida la aplicación del patrón canónico
establecido en H2.

### Alcance NO cubierto por H3

Idéntico a H2: validación de tipos inválidos no vacíos
(`id_pre_reserva="abc"`, `permitir_pago_en_revision="blabla"`) sigue
fuera del alcance del hardening por strings/whitespace.

---

## H4 — Hardening de `crear_prereserva`

**Fecha:** 2026-05-26
**Estado:** Cerrado ✅
**Función afectada:** `crear_prereserva(jsonb)`
**Versión schema:** v1.7.2

### Cambio aplicado

Subsección de extract dentro del bloque "1. Extraer payload y validar"
reemplazada por extract defensivo unificado. El bloque tiene 19
asignaciones derivadas del payload, de las cuales **18 cambian** al
patrón `NULLIF(TRIM(...),'')` y **1 queda intacta**: `v_huesped_payload`,
porque usa el operador JSONB `payload->'huesped'` (no `payload->>'...'`)
y devuelve un sub-objeto, no texto. La normalización interna del huésped
vive en `upsert_huesped()`, que ya aplica el patrón canónico desde antes
del hardening.

Vulnerabilidades cerradas:
- **Casts duros que rompían con vacío/whitespace**: `id_cabana` (BIGINT),
  `fecha_in` y `fecha_out` (DATE), `personas` (INTEGER), `mascotas` y
  `ninos` (BOOLEAN), `hora_checkin_solicitada` y `hora_checkout_solicitada`
  (TIME). Todos pasan ahora por `NULLIF(TRIM(...),'')` antes del cast.
- **Obligatorios de texto sin normalización**: `canal_origen` y
  `source_event` ahora normalizan `""` y whitespace a NULL real antes
  del check `IS NULL`.
- **Montos con NULLIF sin TRIM**: `monto_total` y `monto_sena` ahora
  cubren whitespace además de vacío.
- **Opcionales de texto con NULLIF sin TRIM**: `idempotency_key`, `notas`,
  `detalle_mascotas`, `notas_reserva`, `canal_pago_esperado`, `id_consulta`
  unificados al patrón.

### Resto de la función

Idéntico al cuerpo real pre-cambio (Pieza 1):
- DECLARE con 36 variables.
- Validaciones posteriores en sección 1: `payload_invalido`,
  `precio_requerido`, `fechas_invalidas`, `huesped_nombre_requerido`,
  `huesped_contacto_requerido`.
- Sección 1.bis (`set_config` D38).
- Sección 2 (carga agrupada de `configuracion_general` + detección de
  claves faltantes para warning).
- Sección 3 (pre-check idempotencia con `recovery_path='pre_lock'`).
- Sección 4 (`upsert_huesped` con propagación de error).
- Sección 5 (locks: global `pg_advisory_xact_lock(10,0)` + por cabaña
  `pg_advisory_xact_lock(1, v_id_cabana::INTEGER)`).
- Sección 5.bis (double-check idempotencia con `recovery_path='post_lock'`).
- Sección 6 (validación cabaña: `cabana_no_existe`, `cabana_inactiva`,
  `excede_capacidad`).
- Sección 7 (`validar_disponibilidad` + `no_disponible`).
- Sección 8 (cálculo de horarios finales v1.7 con regla de domingo en
  `hora_checkin` y `hora_checkout`).
- Sección 9 (INSERT pre_reservas + handler `unique_violation` con
  `recovery_path='unique_violation'` + fallback `unique_violation_inesperado`).
- Sección 10 (log de creación con `evento='prereserva_creada'`).
- Sección 11 (warning compacto de claves config faltantes).
- Sección 12 (RETURN exitoso con 9 campos).

### Confirmación de contratos preservados

- **`canal_pago_esperado` opcional**: confirmado en el cuerpo real de DEV.
  No aparece en el check de obligatorios `IF v_id_cabana IS NULL OR ...`.
  El hardening lo normaliza con el patrón canónico pero no lo agrega al
  check. Esto difiere del schema canónico `6B_SCHEMA_SQL.md v1.7.1`, que
  lo incluía como obligatorio — nueva instancia de la lección H2-L1.
- **`v_ninos` es BOOLEAN en DEV**, no TEXT como decía el schema canónico.
  Confirmado en el cuerpo real. El hardening respeta el tipo real.

### Verificación

| Pieza | Resultado |
|---|---|
| 1 — Snapshot pre-cambio | Cuerpo real capturado |
| 2 — Sanity check pre | pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, logs=11 |
| 3-bis — CREATE OR REPLACE | Success. No rows returned |
| 4 — Registro | `crear_prereserva | v | 1` |
| 5 — 31 tests | 31/31 ok=true |
| 6 — Sanity check post | Conteos idénticos a Pieza 2; `huespedes_post=2`; `logs_de_tests=0` |

### Tests aprobados

**Obligatorios con vacío y whitespace → `payload_invalido` (T1-T12):**
- T1, T2: `id_cabana` (BIGINT) — confirma cast defensivo.
- T3, T4: `fecha_in` (DATE) — confirma cast defensivo.
- T5, T6: `fecha_out` (DATE) — confirma cast defensivo.
- T7, T8: `personas` (INTEGER) — confirma cast defensivo.
- T9, T10: `canal_origen` (TEXT obligatorio).
- T11, T12: `source_event` (TEXT obligatorio).

**Montos con vacío/whitespace → `precio_requerido` (T13-T16):**
- T13, T14: `monto_total` (NUMERIC con NULLIF previo).
- T15, T16: `monto_sena` (NUMERIC con NULLIF previo).

**Opcionales con vacío/whitespace, huésped inválido como red de seguridad
→ `huesped_nombre_requerido` (T17-T28):**
- T17, T18: `mascotas` (BOOLEAN) — confirma cast defensivo.
- T19, T20: `ninos` (BOOLEAN) — confirma cast defensivo.
- T21: `canal_pago_esperado` (TEXT opcional).
- T22: `idempotency_key` (TEXT opcional).
- T23: `notas` (TEXT opcional).
- T24: `detalle_mascotas` (TEXT opcional).
- T25: `notas_reserva` (TEXT opcional).
- T26: `id_consulta` (BIGINT opcional) — confirma cast defensivo.
- T27: `hora_checkin_solicitada` (TIME opcional) — confirma cast defensivo.
- T28: `hora_checkout_solicitada` (TIME opcional) — confirma cast defensivo.

**Validaciones del sub-objeto huésped intactas (T29-T31):**
- T29: `huesped.nombre=""` → `huesped_nombre_requerido`.
- T30: `huesped.nombre="   "` → `huesped_nombre_requerido` (validación
  con `NULLIF(TRIM(...))` que ya existía).
- T31: huésped sin telefono ni email → `huesped_contacto_requerido`.

### Red de seguridad validada empíricamente

`huespedes_post=2 = huespedes_pre=2` confirma que la estrategia de
huésped inválido (`{nombre: "", telefono: "..."}`) bloqueó el avance a
`upsert_huesped` en todos los tests T17-T28. Cero filas creadas o
modificadas en `huespedes`.

### Análisis del orden de validaciones de la función

Para diseñar tests no destructivos correctamente fue crítico entender el
orden de ejecución de las validaciones dentro de la función:

1. Extract (paso 1) — puede romper con cast crudo si no hay defensa.
2. Validación obligatorios → `payload_invalido`.
3. Validación montos → `precio_requerido`.
4. Validación fechas → `fechas_invalidas`.
5. Validación nombre huésped → `huesped_nombre_requerido` ← última frontera
   antes de tocar tablas.
6. Validación contacto huésped → `huesped_contacto_requerido`.
7. `upsert_huesped` (paso 4) ← primer punto donde la función modifica DB.
8. Locks (paso 5).
9. Validación cabaña (paso 6) → `cabana_no_existe`, `cabana_inactiva`,
   `excede_capacidad`.

Lección: cualquier test que llegue al paso 5 o más allá habría modificado
`huespedes`. La estrategia "huésped inválido + cabaña inexistente" no
sirve porque rebota en `huesped_nombre_requerido` antes que en
`cabana_no_existe`. La estrategia correcta es "huésped inválido + payload
modificado": permite testear que el extract no rompe y rebotar limpio en
la validación 1.w.

### Hallazgos generados

**H4-L1 (Lección de orden de validaciones):** para diseñar tests no
destructivos en funciones con `upsert_huesped` u operaciones que tocan
DB en etapas tempranas, identificar la última validación antes de la
primera operación de escritura es crítico. En `crear_prereserva` esa
frontera es `huesped_nombre_requerido` (paso 1.w), justo antes de
`upsert_huesped` (paso 4).

**H4-L2 (Divergencias con schema canónico, instancia 2):** además de las
divergencias detectadas en H2, `crear_prereserva` muestra dos más:
- `canal_pago_esperado` es opcional en DEV pero el schema canónico lo
  describía como obligatorio.
- `v_ninos` es BOOLEAN en DEV pero el schema canónico lo declaraba TEXT.

Refuerza la lección H2-L1: schema canónico no es fuente de verdad para
el cuerpo real de funciones. Documentar estas divergencias para revisar
en una sesión futura si conviene reescribir el schema canónico desde DEV
o dejar el esquema canónico como diseño y crear un schema observado.

### Alcance NO cubierto por H4

Idéntico a H2 y H3: validación de tipos inválidos no vacíos
(`id_cabana="abc"`, `mascotas="blabla"`, `fecha_in="no-es-fecha"`) sigue
fuera del alcance del hardening por strings/whitespace.

### Cierre del frente de hardening de funciones write

Con H2 (`registrar_pago`), H3 (`confirmar_reserva`) y H4 (`crear_prereserva`)
las 3 funciones write más críticas tienen extract defensivo unificado.
Patrón canónico aplicado consistentemente.

**Pendiente NO ejecutado por estar fuera del alcance original:**
`cancelar_prereserva` y `crear_bloqueo` también son funciones write con
extract de payload, pero no se incluyeron en H2-H4 por scope de la sesión.
Pueden agregarse como H4-bis si Franco lo solicita antes de avanzar a H5.

---

## H4-bis — Hardening de `cancelar_prereserva`

**Fecha:** 2026-05-26
**Estado:** Cerrado ✅
**Función afectada:** `cancelar_prereserva(jsonb)`
**Versión schema:** v1.7.2

### Cambio aplicado

Bloque "1. Extraer payload" reemplazado por extract defensivo unificado.
Patrón aplicado al bloque de extracción del payload, cubriendo 4
variables derivadas de `payload->>'...'`: `v_id_pre_reserva`, `v_motivo`,
`v_descripcion`, `v_source_event`.

Vulnerabilidades cerradas:
- **Cast duro**: `id_pre_reserva` (BIGINT) ya no rompe con string vacío
  o whitespace; rebota controlado.
- **Obligatorios de texto sin normalización**: `motivo` y `source_event`
  ahora normalizan `""` y whitespace a NULL real antes del check `IS NULL`.
- **NULLIF sin TRIM**: `descripcion` ahora cubre whitespace además de vacío.

### Resto de la función

Idéntico al cuerpo real pre-cambio (Pieza 1):
- DECLARE con 9 variables.
- Validación `payload_invalido` sobre `v_id_pre_reserva`, `v_motivo`, `v_source_event`.
- Sección 1.bis (`set_config` D38).
- Sección 1.ter (lock global `pg_advisory_xact_lock(10, 0)` — sin lock
  por cabaña por diseño: la función solo libera disponibilidad).
- Sección 2 (CASE de mapeo motivo→estado: `cliente` →
  `cancelada_por_cliente`, `bloqueo` → `cancelada_por_bloqueo`,
  ELSE → `motivo_invalido` con lista de motivos válidos).
- Sección 3 (`SELECT FOR UPDATE pre_reservas` + `prereserva_no_existe`
  + `estado_no_cancelable`).
- Sección 4 (UPDATE pre-reserva a estado nuevo).
- Sección 5 (conteo de pagos asociados, sin tocarlos).
- Sección 6 (INSERT `log_cambios` con `evento='prereserva_cancelada'`).
- RETURN final con 6 campos: `ok`, `id_pre_reserva`, `estado_anterior`,
  `estado_nuevo`, `pagos_asociados_count`, `pagos_asociados_ids`.

### Verificación

| Pieza | Resultado |
|---|---|
| 1 — Snapshot pre-cambio | Cuerpo real capturado |
| 2 — Sanity check pre | pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, logs=11 |
| 3-bis — CREATE OR REPLACE | Success. No rows returned |
| 4 — Registro | `cancelar_prereserva | v | 1` |
| 5 — 9 tests | 9/9 ok=true |
| 6 — Sanity check post | Conteos idénticos a Pieza 2; `logs_de_tests=0` |

### Tests aprobados

**Obligatorios con vacío y whitespace → `payload_invalido`:**
- T1 (`id_pre_reserva=""`), T2 (`id_pre_reserva="   "`).
- T3 (`motivo=""`), **T4 (`motivo="   "`)** ← cambio observable validado.
- T5 (`source_event=""`), T6 (`source_event="   "`).

**Opcional con whitespace → no rompe, llega a `prereserva_no_existe`:**
- T7 (`descripcion="   "`).

**Validación de motivo no en enum intacta → `motivo_invalido`:**
- T8 (`motivo="fantasma"`) — devuelve `motivo_invalido` con
  `motivos_validos: ["cliente", "bloqueo"]`.

**Regresión funcional:**
- T9 — payload bien formado con `id_pre_reserva` inexistente devuelve
  `prereserva_no_existe`.

### Cambio observable validado

Antes del fix, `motivo: "   "` con resto válido habría devuelto
`motivo_invalido` (porque pasaba la validación `IS NULL` y caía al
`ELSE` del CASE). Después del fix, `NULLIF(TRIM(...),'')` lo convierte
a NULL y rebota antes del CASE con `payload_invalido`. T4 valida este
cambio. Es consistente con el patrón H2/H3/H4: whitespace en campo
obligatorio equivale a valor ausente.

`motivo_invalido` sigue activo para valores no-vacíos fuera de enum
(validado por T8 con `motivo: "fantasma"`).

### Observación operativa sobre locks

Los tests T7, T8, T9 pasan la validación inicial de payload y por lo
tanto llegan a tomar el lock global (`pg_advisory_xact_lock(10, 0)`)
antes de rebotar en `motivo_invalido` o `prereserva_no_existe`. No
modifican tablas. El lock es `advisory_xact_lock`, se libera al cierre
de la transacción. Comportamiento esperado, no requiere acción.

### Hallazgos generados

Ninguno nuevo. El bloque consolida la aplicación del patrón canónico
sobre la función de cancelación. **No se detectaron divergencias con el
schema canónico** (a diferencia de H2 y H4): el cuerpo real coincide
con `6B_SCHEMA_SQL.md v1.7.1`.

### Alcance NO cubierto por H4-bis

Idéntico a H2, H3 y H4: validación de tipos inválidos no vacíos
(`id_pre_reserva="abc"`) sigue fuera del alcance del hardening por
strings/whitespace.

---

## H4-ter — Hardening de `crear_bloqueo`

**Fecha:** 2026-05-26
**Estado:** Cerrado ✅
**Función afectada:** `crear_bloqueo(jsonb)`
**Versión schema:** v1.7.2

### Cambio aplicado

Bloque "1. Extraer payload" reemplazado por extract defensivo unificado.
Patrón aplicado al bloque de extracción del payload, cubriendo 7
variables derivadas de `payload->>'...'`: `v_id_cabana`, `v_fecha_desde`,
`v_fecha_hasta`, `v_motivo`, `v_descripcion`, `v_creado_por`, `v_source_event`.

Vulnerabilidades cerradas:
- **Casts duros**: `fecha_desde` y `fecha_hasta` (DATE) ya no rompen con
  vacío/whitespace; rebotan controlado en validación.
- **Cast semi-duro `id_cabana`** (BIGINT): antes `NULLIF` cubría `""` pero
  no `"   "`. Ahora `NULLIF(TRIM(...))` cubre ambos.
- **Obligatorios de texto sin normalización**: `motivo`, `creado_por`,
  `source_event` ahora normalizan `""` y whitespace a NULL real.
- **NULLIF sin TRIM**: `descripcion` ahora cubre whitespace además de vacío.

### Caso especial — `id_cabana` con semántica de NULL válido

A diferencia de las otras funciones write, en `crear_bloqueo` `id_cabana=null`
significa "bloqueo total" (válido, no error). El patrón canónico mantiene
esa semántica:
- `id_cabana: null` → bloqueo total.
- `id_cabana: ""` → bloqueo total (ya era así antes del cambio).
- `id_cabana: "   "` → bloqueo total (cambio observable nuevo).
- `id_cabana: 17` → bloqueo específico.

Aceptado por consistencia con el patrón. El contrato actual ya
interpretaba `""` como bloqueo total por el `NULLIF` previo; el cambio
solo amplía el alcance para incluir whitespace puro.

### Resto de la función

Idéntico al cuerpo real pre-cambio (Pieza 1):
- DECLARE con 11 variables.
- Validación `payload_invalido` (5 obligatorios — `v_id_cabana` NO incluido
  por diseño, dado que NULL es semánticamente válido).
- Validación `fechas_invalidas` (`v_fecha_hasta <= v_fecha_desde`).
- Validación `motivo_invalido` por enum cerrado (`mantenimiento`,
  `uso_propio`, `tormenta`, `overbooking`, `otro`).
- Sección 2 (lock global + lock por cabaña condicional con cast `::INTEGER`).
- Sección 3.A — rama bloqueo específico (`v_id_cabana IS NOT NULL`):
  `cabana_no_existe`, `conflicto_con_reserva`, `conflicto_con_prereserva`,
  `bloqueo_solapado`.
- Sección 3.B — rama bloqueo total (`v_id_cabana IS NULL`):
  `conflicto_con_reserva`, `conflicto_con_prereserva`, `bloqueo_solapado`.
- Sección 4 (INSERT en `bloqueos` con handler `exclusion_violation` que
  devuelve `bloqueo_solapado` con `motivo: 'EXCLUDE detectó conflicto residual'`).
- Sección 5 (INSERT `log_cambios` con `tipo_bloqueo` CASE — `'total'` o
  `'cabana_especifica'`).
- RETURN final con 4 campos: `ok`, `id_bloqueo`, `id_cabana`, `tipo_bloqueo`.

### Verificación

| Pieza | Resultado |
|---|---|
| 1 — Snapshot pre-cambio | Cuerpo real capturado |
| 2 — Sanity check pre | pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, logs=11 |
| 3-bis — CREATE OR REPLACE | Success. No rows returned |
| 4 — Registro | `crear_bloqueo | v | 1` |
| 5 — 17 tests | 17/17 ok=true |
| 6 — Sanity check post | Conteos sin desviación; `bloqueos_post=2`; `logs_de_tests=0` |

### Tests aprobados

**Obligatorios con vacío y whitespace → `payload_invalido`:**
- T1, T2: `fecha_desde` (DATE) — confirma cast defensivo.
- T3, T4: `fecha_hasta` (DATE) — confirma cast defensivo.
- T5, T6: `motivo` (TEXT obligatorio) — T6 valida cambio observable.
- T7, T8: `creado_por` (TEXT obligatorio) — T8 valida cambio observable.
- T9, T10: `source_event` (TEXT obligatorio).

**`id_cabana` con valores especiales → `fechas_invalidas` (red de seguridad):**
- T11 (`id_cabana=""`): cast defensivo OK, semántica de bloqueo total preservada.
- T12 (`id_cabana="   "`): cambio observable validado — se normaliza a NULL.
- T13 (`id_cabana=null`): semántica de bloqueo total intacta.

**Opcional con whitespace → no rompe:**
- T14 (`descripcion="   "`) → `fechas_invalidas`.

**Validación de motivo no en enum intacta → `motivo_invalido`:**
- T15 (`motivo="fantasma"`) — confirma que valores no-vacíos fuera de enum
  siguen rebotando con `motivo_invalido`.

**Cabaña inexistente sin riesgo destructivo:**
- T16 (`id_cabana=99999` + fechas invertidas) → `fechas_invalidas` —
  variante segura: rebota antes del lock por cabaña y antes de
  `cabana_no_existe`, sin tocar locks ni tablas.

**Regresión funcional:**
- T17 — payload bien formado + fechas invertidas → `fechas_invalidas` —
  demuestra que el extract recorre limpio hasta la validación cronológica.

### Cambios observables validados

1. **`motivo: "   "` → `payload_invalido`** (T6).
   Antes pasaba la validación `IS NULL` (era string no-NULL) y caía al
   check de enum devolviendo `motivo_invalido`. Después rebota antes
   con `payload_invalido`. Consistente con H4-bis y patrón canónico.

2. **`creado_por: "   "` → `payload_invalido`** (T8).
   Antes era aceptado como nombre del creador y guardado literal en
   `bloqueos.creado_por` + usado como `modificado_por` del log. Después
   rebota controlado. Mejora de robustez.

3. **`id_cabana: "   "` → bloqueo total** (T12).
   Antes habría roto el cast a BIGINT con error crudo. Después se
   normaliza a NULL y conserva la semántica de bloqueo total. Aceptado
   por consistencia con el patrón: whitespace ≡ vacío ≡ NULL. El
   contrato ya interpretaba `""` igual.

### Observación operativa sobre locks

Los tests T11-T16 pasan la validación inicial de payload y por lo tanto
llegan a tomar el lock global (`pg_advisory_xact_lock(10, 0)`) antes de
rebotar en `fechas_invalidas` o `motivo_invalido`. T16 además NO toma
lock por cabaña porque rebota en `fechas_invalidas` antes del bloque
`IF v_id_cabana IS NOT NULL`. Todos los locks son `advisory_xact_lock`,
se liberan al cierre de la transacción. Sin modificación de tablas.

### Hallazgos generados

Ninguno nuevo. **No se detectaron divergencias con el schema canónico**
(consistente con H4-bis y a diferencia de H2 y H4): el cuerpo real
coincide con `6B_SCHEMA_SQL.md v1.7.1`.

### Alcance NO cubierto por H4-ter

Idéntico al resto del frente: validación de tipos inválidos no vacíos
(`fecha_desde="no-es-fecha"`, `id_cabana="abc"`) sigue fuera del alcance
del hardening por strings/whitespace.

---

## H5 — Fix de `vista_ocupacion`

**Fecha:** 2026-05-26
**Estado:** Cerrado ✅
**Objeto afectado:** `vista_ocupacion` (vista)
**Versión schema:** v1.7.2

### Cambio aplicado

Una sola línea modificada en el CTE `meses` de la vista: al límite
superior del `generate_series` se le resta `'1 mon'::interval`.

**Antes:**
```sql
generate_series(
  date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) - '1 year'::interval,
  date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) + '1 year'::interval,
  '1 mon'::interval
)
```

**Después:**
```sql
generate_series(
  date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) - '1 year'::interval,
  date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) + '1 year'::interval - '1 mon'::interval,
  '1 mon'::interval
)
```

### Razón del cambio

`generate_series` con paso temporal incluye ambos extremos, generando
25 puntos en lugar de los 24 esperados (12 meses pasados + 12 meses
futuros). El resultado era 25 meses × 5 cabañas = 125 filas, en lugar
de 24 × 5 = 120. Reportado como hallazgo durante 6C — implementación
de W7 (vistas operativas), Test 4.

### Resto de la vista

Idéntica al cuerpo real pre-cambio (Pieza 1):
- CTE `meses` salvo la línea modificada del límite superior.
- CTE `matriz` (CROSS JOIN cabanas × meses, filtro `c.activa = TRUE`).
- SELECT principal con 6 columnas: `id_cabana`, `cabana`, `inicio_mes`,
  `fin_mes`, `noches_ocupadas`, `dias_del_mes`.
- Subquery de cálculo de `noches_ocupadas` con `LEAST`/`GREATEST` y
  filtro de estados `('confirmada', 'activa', 'completada')`.
- Cálculo de `dias_del_mes` con `EXTRACT(DAY FROM ...)`.
- `ORDER BY id_cabana, inicio_mes`.

### Verificación

| Pieza | Resultado |
|---|---|
| 1 — Snapshot pre-cambio | Cuerpo real capturado |
| 2 — Sanity check pre | pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, logs=11 |
| 2-bis — Verificación de dependencias | 0 filas (vista sin dependientes) |
| 3 — CREATE OR REPLACE VIEW | Success. No rows returned |
| 4 — Registro + comparación de cuerpo | Vista registrada; cuerpo post-cambio byte-idéntico al pre-cambio salvo `- '1 mon'::interval` agregado |
| 5 — 7 verificaciones | 7/7 ok=true |
| 6 — Sanity check post | Conteos idénticos a Pieza 2 (`logs_post=11=logs_pre`) |

### Tests aprobados

| # | Verificación | Real | Esperado |
|---|---|---|---|
| H5-T1 | Total de filas | 120 | 120 |
| H5-T2 | Meses distintos | 24 | 24 |
| H5-T3 | Cabañas distintas | 5 | 5 |
| H5-T4a | min(inicio_mes) a fecha 2026-05-26 | 2025-05-01 | 2025-05-01 |
| H5-T4b | max(inicio_mes) a fecha 2026-05-26 | 2027-04-01 | 2027-04-01 |
| H5-T5 | noches_ocupadas cabaña 17, julio 2026 (spot check con reserva 8) | 3 | 3 |
| H5-T6 | Estructura de columnas | 6 columnas en orden correcto | idem |

### Cambios observables

- `SELECT COUNT(*) FROM vista_ocupacion` ahora devuelve 120 en lugar
  de 125.
- Los cálculos de `noches_ocupadas` por mes/cabaña son **idénticos** a
  los previos — el mes "extra" eliminado tenía `noches_ocupadas=0`
  en todos los casos al no haber reservas tan lejanas en el futuro.
- Estructura de columnas y orden de resultados sin cambios.

### Spot check de reserva conocida

T5 confirma que la **reserva 8** del cierre de 6C (cabaña 17, 10-13 jul
2026) sigue vigente en DEV y la vista la procesa correctamente: julio
2026 muestra `noches_ocupadas=3`. Esto valida que la lógica de
`LEAST`/`GREATEST` para calcular noches por mes funciona intacta.

### Hallazgos generados

Ninguno. **No hubo divergencias entre el cuerpo real y `pg_get_viewdef`
post-CREATE** — PostgreSQL preservó exactamente la forma que escribimos,
lo cual facilita verificaciones futuras con `pg_get_viewdef`.

### Verificación de dependencias

`pg_depend` + `pg_rewrite` confirmaron que `vista_ocupacion` no tiene
vistas, funciones u otros objetos públicos que dependan de ella.
`CREATE OR REPLACE VIEW` fue seguro sin riesgo de romper consumidores.

### Alcance NO cubierto por H5

No aplica el patrón canónico de hardening (`NULLIF(TRIM(...))`) porque
las vistas no tienen extract de payload. El fix de H5 es estrictamente
sobre el rango del `generate_series`.

---

## H6 — Fix cosmético de concatenación nombre + apellido

**Fecha:** 2026-05-26
**Estado:** Cerrado ✅
**Objetos afectados:** `vista_calendario`, `vista_limpieza_semana`
**Versión schema:** v1.7.2

### Cambio aplicado — Parte 6.1 (vistas)

**`vista_calendario`** (1 cambio):
```diff
- (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text) AS huesped_nombre
+ TRIM((h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped_nombre
```

**`vista_limpieza_semana`** (2 cambios idénticos, uno por rama del UNION ALL):
```diff
- (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text) AS huesped
+ TRIM((h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped
```

PostgreSQL normaliza `TRIM(x)` a `TRIM(BOTH FROM x)` al persistir la
vista. Sintaxis equivalente, sin diferencia funcional. Confirmado en
Pieza 4.

### Razón del cambio

Las dos vistas concatenaban `nombre || ' ' || COALESCE(apellido, '')`.
Cuando `apellido` era NULL o `''`, el resultado era `"Juan Pérez Test "`
(con espacio al final). Reportado durante 6C en Test 3 de W7.

El `TRIM` aplicado al resultado completo cubre los 4 casos:
- `apellido = NULL` → `"Juan "` → TRIM → `"Juan"` ✅
- `apellido = ""` → `"Juan "` → TRIM → `"Juan"` ✅
- `apellido = "   "` → `"Juan    "` → TRIM → `"Juan"` ✅
- `apellido = "Pérez"` → `"Juan Pérez"` → TRIM → `"Juan Pérez"` ✅

### Parte 6.2 (UPDATE de huéspedes) — NO ejecutada

Opción A confirmada: salteamos el UPDATE de huéspedes porque DEV actual
ya tiene `apellido = NULL` en los dos huéspedes existentes (id 34 y 35),
no string vacío. El problema cosmético tenía raíz en huéspedes
pre-existentes que ya no están en DEV (limpieza entre cierre de 6C y
apertura del hardening).

`upsert_huesped()` ya aplica `NULLIF(TRIM(apellido), '')` desde antes
del hardening, por lo que huéspedes futuros no van a tener el problema.
El `TRIM` en las vistas actúa como defensa adicional para cualquier
edge case.

### Resto de las vistas

Idéntico al cuerpo real pre-cambio:

**vista_calendario**:
- 14 columnas en orden intacto.
- JOINs reservas + cabanas + huespedes.
- WHERE: `estado IN (confirmada, activa)`, fecha_checkout >= hoy,
  fecha_checkin <= hoy+60.
- ORDER BY fecha_checkin, id_cabana.

**vista_limpieza_semana**:
- 12 columnas por rama, en orden intacto.
- Estructura UNION ALL (rama checkout + rama checkin).
- WHERE checkout: estados confirmada/activa/completada,
  fecha_checkout en [hoy, hoy+7].
- WHERE checkin: estados confirmada/activa,
  fecha_checkin en [hoy, hoy+7].
- ORDER BY fecha_movimiento, hora.

### Verificación

| Pieza | Resultado |
|---|---|
| 1 — Snapshots de las dos vistas | Cuerpos reales capturados |
| 2 — Sanity check pre | pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, logs=11, vista_calendario_pre=1, vista_limpieza_pre=0 |
| 2-bis — Verificación de dependencias | 0 filas (ninguna vista depende) |
| 3a — CREATE OR REPLACE vista_calendario | Success. No rows returned |
| 3b — CREATE OR REPLACE vista_limpieza_semana | Success. No rows returned |
| 4 — Registro + comparación de cuerpos | Ambas vistas registradas; cuerpos post-cambio con `TRIM(BOTH FROM ...)` en las 3 posiciones esperadas (1 en vista_calendario, 2 en vista_limpieza_semana) |
| 5 — 7 verificaciones | 7/7 ok=true |
| 6 — Sanity check post | Conteos idénticos a Pieza 2 |

### Tests aprobados

| # | Verificación | Real | Esperado |
|---|---|---|---|
| H6-T1 | vista_calendario: filas con espacios colgando | 0 | 0 |
| H6-T2 | vista_calendario: huesped_nombre de reserva 8 | `"Juan Pérez Test" (len=15)` | `"Juan Pérez Test" (len=15)` |
| H6-T3 | vista_limpieza_semana: filas con espacios colgando o vacía | 0 | 0 |
| H6-T4 | vista_calendario: estructura de columnas (14) | exacta | exacta |
| H6-T5 | vista_limpieza_semana: estructura de columnas (12) | exacta | exacta |
| H6-T6 | vista_calendario: conteo | 1 | 1 |
| H6-T7 | vista_limpieza_semana: conteo | 0 | 0 |

### Cambio observable validado

T2 confirma el cambio exacto buscado:
- **Antes del fix:** `"Juan Pérez Test "` con 16 caracteres (espacio
  colgando, documentado en 6C Test 3 de W7).
- **Después del fix:** `"Juan Pérez Test"` con 15 caracteres. ✅

### Particularidad de PostgreSQL — normalización de TRIM

PostgreSQL al persistir la vista normaliza `TRIM(x)` a su sintaxis
SQL-estándar completa: `TRIM(BOTH FROM x)`. Ambas son equivalentes
funcionalmente. Esto se vio en la Pieza 4 al comparar el cuerpo
post-cambio. **Nota para H7 y futuras comparaciones de cuerpo:** si
escribimos `TRIM(...)`, el resultado persistido será `TRIM(BOTH FROM ...)`.
No es un cambio funcional, es una normalización de sintaxis.

### Hallazgos generados

**H6-L1 (Observación operativa):** la limpieza de DEV entre el cierre
de 6C y la apertura del hardening eliminó los huéspedes con
`apellido = ""` que originaban el problema cosmético. La Parte 6.2 del
plan (UPDATE de normalización) quedó sin filas que tocar. El fix de
vistas se mantiene igualmente como defensa estructural — cualquier
huésped futuro con `apellido` problemático será procesado correctamente
sin espacios colgando.

### Verificación de dependencias

`pg_depend` + `pg_rewrite` confirmaron que ni `vista_calendario` ni
`vista_limpieza_semana` tienen vistas, funciones u otros objetos
públicos dependientes. `CREATE OR REPLACE VIEW` fue seguro en ambas.

### Alcance NO cubierto por H6

- No se modifica `upsert_huesped()` (ya cumple el patrón canónico).
- No se ejecuta UPDATE sobre `huespedes` (no hay filas que normalizar).
- No se modifican otras vistas que pudieran tener concatenaciones
  similares — `vista_prereservas_activas` también concatena nombre +
  apellido. Si se considera necesario aplicarle el mismo fix, queda
  como pendiente menor opcional pre-PROD.

---

## H6-bis — Fix de `vista_prereservas_activas`

**Fecha:** 2026-05-26
**Estado:** Cerrado ✅
**Objeto afectado:** `vista_prereservas_activas`
**Versión schema:** v1.7.2

### Cambio aplicado

Una sola línea modificada: la columna `huesped_nombre` ahora aplica
`TRIM(...)` sobre la concatenación de nombre + apellido.

**Antes:**
```sql
(h.nombre || ' '::text) || COALESCE(h.apellido, ''::text) AS huesped_nombre
```

**Después:**
```sql
TRIM((h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped_nombre
```

PostgreSQL normalizó al persistir a `TRIM(BOTH FROM ...)` — sintaxis
SQL-estándar equivalente. Comportamiento consistente con H6.

### Razón del cambio

Mismo bug cosmético detectado en H6 sobre `vista_calendario` y
`vista_limpieza_semana`. Por consistencia se aplica el mismo fix a
`vista_prereservas_activas`, que también concatena nombre + apellido
sin TRIM. Cerramos la categoría completa de vistas afectadas antes de
avanzar a TEST/PROD.

### Resto de la vista

Idéntica al cuerpo real pre-cambio (Pieza 1):
- 15 columnas en orden intacto: `id_pre_reserva`, `cabana`, `id_cabana`,
  `fecha_in`, `fecha_out`, `personas`, `estado`, `expira_en`,
  `minutos_para_vencer`, `monto_total`, `monto_sena`, `canal_origen`,
  `canal_pago_esperado`, `huesped_nombre`, `huesped_telefono`.
- JOINs (`pre_reservas` + `cabanas` + `huespedes`).
- Cálculo dinámico `minutos_para_vencer` con `EXTRACT(epoch FROM ...)`.
- Filtros: `estado IN ('pendiente_pago', 'pago_en_revision')` Y
  `expira_en > NOW()`.
- `ORDER BY pr.expira_en`.

### Verificación

| Pieza | Resultado |
|---|---|
| 1 — Snapshot pre-cambio | Cuerpo real capturado |
| 2 — Sanity check pre | pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, logs=11, vista_prereservas_activas_pre=0 |
| 2-bis — Verificación de dependencias | 0 filas |
| 3 — CREATE OR REPLACE VIEW | Success. No rows returned |
| 4 — Registro + comparación de cuerpo | Vista registrada; `TRIM(BOTH FROM ...)` agregado en `huesped_nombre`; resto del cuerpo intacto |
| 5 — 5 verificaciones | 5/5 ok=true |
| 6 — Sanity check post | Conteos idénticos a Pieza 2 |

### Tests aprobados

| # | Verificación | Real | Esperado |
|---|---|---|---|
| H6bis-T1 | Sin espacios colgando (o vista vacía) | 0 | 0 |
| H6bis-T2 | Estructura de 15 columnas | exacta | exacta |
| H6bis-T3 | Conteo de filas | 0 | 0 |
| H6bis-T4 | Ninguna fila termina en espacio | 0 | 0 |
| H6bis-T5 | Filtro de estados consistente (cruzado con pre_reservas) | 0 | 0 |

### Observación operativa — vista vacía

`vista_prereservas_activas_pre = 0` confirmó la predicción: las 2
pre-reservas existentes en DEV están en estados terminales
(`convertida` e `cancelada_por_cliente`) según el cierre de 6C, por lo
que ninguna cumple el filtro de la vista. Los tests T1, T3, T4 son
vacuamente verdaderos; T2 verifica estructura; T5 verifica filtro
mediante consulta cruzada que también devuelve 0. La vista quedó
preparada para cuando aparezcan pre-reservas activas reales.

### Hallazgos generados

Ninguno nuevo. **No hubo divergencias entre cuerpo real y schema
canónico** — coincidencia exacta, consistente con H4-bis, H4-ter, H5 y
H6 (a diferencia de H2 y H4).

### Cierre del frente de hardening de vistas

Con H5, H6 y H6-bis cerrados, las 3 vistas afectadas por bugs reportados
quedan corregidas:

| Vista | Bloque | Corrección |
|---|---|---|
| `vista_ocupacion` | H5 | Rango de 25 → 24 meses |
| `vista_calendario` | H6 | TRIM en concatenación de nombre |
| `vista_limpieza_semana` | H6 | TRIM en concatenación de nombre (ambas ramas UNION ALL) |
| `vista_prereservas_activas` | H6-bis | TRIM en concatenación de nombre |

**Frente de hardening de vistas: CERRADO.**

### Alcance NO cubierto por H6-bis

No se aplicó UPDATE sobre `huespedes` (mismo razonamiento que H6:
no hay filas con `apellido = ''`). Las otras 2 vistas operativas
(`vista_disponibilidad` y `vista_calendario_semanal`) no concatenan
nombre + apellido, no requieren fix.

---