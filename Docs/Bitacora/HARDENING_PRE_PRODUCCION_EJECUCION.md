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

## H7 — Tests de concurrencia

**Fecha de apertura:** 2026-05-27
**Estado:** En curso (C-1 cerrado; C-2, C-5, C-3, C-4, C-6 pendientes)
**Objeto del bloque:** validar empíricamente bajo concurrencia real las funciones write críticas y la invariante de locks v1.5.
**Schema:** v1.7.2 (sin cambios en H7 — los tests son de validación, no modifican funciones)

### Plan aprobado

6 tests en este orden con frenos especiales por regresión:

| Orden | Test | Funciones | Tipo |
|---|---|---|---|
| 1 | C-1 | `crear_prereserva` + `crear_bloqueo total` | Principal |
| 2 | C-2 | `cancelar_prereserva` + `crear_bloqueo total` | Principal |
| 3 | C-5 | `confirmar_reserva` + `cancelar_prereserva` | Legacy v1.5 (regresión) |
| 4 | C-3 | `confirmar_reserva` + `crear_bloqueo específico` | Principal |
| 5 | C-4 | Doble `confirmar_reserva` | Principal |
| 6 | C-6 | Doble `crear_prereserva` + `idempotency_key` | Legacy idempotencia |

**Frenos especiales:** `40P01` en C-5 bloquea C-3/C-4/C-6. `40P01` en C-3 bloquea C-4/C-6. Cualquier `40P01` en otro test = freno duro.

**Convención `source_event`:** `test_H7_C{N}_{ROL}` con `{ROL}` = `A`, `B`, `FIXTURE`, `FIXTURE_PR`, `FIXTURE_PAGO`.

### Snapshot pre-H7

Validado en 6 piezas read-only. Resumen:

| Pieza | Verificación | Resultado |
|---|---|---|
| 0 | Transacción persistente en SQL Editor con `pg_sleep(5)` | OK, elapsed 5.005s |
| 1 | Conteos baseline (pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, log_cambios=11) | OK |
| 2 | 5 cabañas activas IDs 17-21 con `capacidad_max` correcto | OK |
| 3 | 0 residuos previos `test_H7_%` | OK |
| 4 | 6 rangos H7 sin cruces con reservas/pre-reservas/bloqueos existentes | OK |
| 5 | Cuerpos reales de `crear_prereserva`, `confirmar_reserva`, `cancelar_prereserva`, `crear_bloqueo` (pg_get_functiondef) | Invariante v1.5 vigente |
| 6 | Distribución por estado conforme con `ESTADO_ACTUAL_VITA_DELTA.md` | OK |

### Hallazgos detectados durante snapshot (pre-tests)

1. **`bloqueos.activo` BOOLEAN, no enum `estado`.** Diverge del patrón de `reservas`/`pre_reservas`/`pagos`. Candidato L-6D-06. Impacto: filtros y queries de validación deben usar `activo = TRUE` y `CASE WHEN activo THEN 'activo' ELSE 'inactivo' END`, no `estado::text`.
2. **`cabanas.capacidad_max`, no `capacidad_maxima`.** Catch de Franco en Pieza 2. Hallazgo operativo menor; confirmar si existe divergencia documental en H8.
3. **`confirmar_reserva` retorna `estado_invalido`, no `estado_no_confirmable`** cuando la pre-reserva ya está en estado terminal. Expected de C-4 ajustado.
4. **`crear_prereserva` ejecuta `upsert_huesped` ANTES del lock global (sección 4 del cuerpo real, antes de sección 5).** Implica que tests que pasan validaciones de huésped pueden crear huésped antes de rebotar por lock o validaciones tardías. Relevante para C-6.

### C-1 — `crear_prereserva` + `crear_bloqueo total`

**Objetivo:** validar que el lock global `(10, 0)` serializa correctamente: que B (`crear_bloqueo total`) espera al COMMIT de A (`crear_prereserva`) y luego rebota con `conflicto_con_prereserva`.

**Setup:** sin fixtures. Cabaña 17 (Bamboo). Rango pre-reserva 2027-03-01 → 2027-03-03. Rango bloqueo 2027-03-01 → 2027-03-05. Huésped sintético `Test H7 C1` con teléfono `+5491400000001`.

#### Intento fallido (primera corrida)

- A ejecutada desde SQL Editor, B intentada desde **otra pestaña interna del mismo SQL Editor (botón "+")**.
- El SQL Editor de Supabase no permitió disparar B mientras A corría: comparten runner único.
- B se disparó recién después del COMMIT de A. `B.elapsed = 0.004s`. **No hubo concurrencia real.**
- Datos creados como residuo: pre-reserva 27, huésped 36, 1 log. Limpiados antes de re-ejecutar.

#### Corrección aplicada

- Diagnóstico: `telefono_normalizado` preserva el prefijo `+` (`+5491400000001`, no `5491400000001`). Cleanup inicial fallaba en el filtro de huésped. Corregido a `WHERE telefono = '+5491400000001'`.
- Mecánica de paralelismo: cambiar a **dos tabs separadas del navegador**, cada una con su propia sesión del SQL Editor. Validado con mini-test trivial (`pg_sleep(5)` simultáneo en ambas tabs) que dio PIDs distintos (359653 vs 359654) y solapamiento temporal real.

#### Resultado exitoso (segunda corrida)

| Métrica | Tab A | Tab B |
|---|---|---|
| `pid` | 359724 | 359727 |
| `ts_pre` | 12:00:17.942 | 12:00:19.651 |
| `ts_post` | 12:00:25.963 | 12:00:25.968 |
| `elapsed` | 8.021s | **6.317s** |
| `resultado.ok` | `true` | `false` |
| Output relevante | id_pre_reserva=28, recovery_path=null | `error=conflicto_con_prereserva`, prereservas_en_conflicto=[28] |

**Lectura del lock global:** B arrancó a las 19.651 (1.7s después de A), quedó esperando el lock global tomado por A, lo recibió al COMMIT de A a las 25.963, procesó y devolvió a las 25.968. B esperó **6.317 segundos** ≈ exactamente el tiempo que faltaba para que A liberara el lock. Sin deadlock, sin race, sin falsos positivos. B vio el estado post-COMMIT de A (pre-reserva 28 vigente).

#### Validación post-test

- `prereserva_creada_C1_A` = 1 (id 28, cab 17, pendiente_pago) ✅
- `bloqueo_NO_creado_C1_B` = 0 ✅
- `huesped_sintetico_C1` = 1 (id 37) ✅
- `logs_C1` = 1 (`evento=prereserva_creada`, nivel `info`, src `test_H7_C1_A`, modif `crear_prereserva`) ✅

#### Cleanup

DELETE en orden FK-seguro: logs → bloqueos → pre_reservas → huésped huérfano. Filtro `source_event LIKE 'test_H7_C1_%'` + huésped por `telefono = '+5491400000001'` con guarda `NOT EXISTS`.

#### Estado final post-cleanup

Baseline restaurado: pagos=1, pre_reservas=2, reservas=1, huespedes=2, bloqueos=2, log_cambios=11. Residuos `test_H7_C1_%` = 0. Huésped sintético = 0.

**C-1 cerrado ✅**

### Aprendizajes para C-2 a C-6

Aplicar a todos los tests siguientes:

1. **Mecánica de paralelismo:** dos tabs **separadas del navegador**, no la "+" interna del SQL Editor. Validar con mini-test de `pg_sleep(5)` + `pg_backend_pid()` antes de la primera ejecución de cada sesión que use concurrencia.
2. **Cleanup de huéspedes:** usar `WHERE telefono = '+5491XXXXXXXXX'` (con `+`), no `telefono_normalizado` sin `+`.
3. **Filtro de bloqueos:** `activo = TRUE` y `CASE WHEN activo THEN 'activo' ELSE 'inactivo' END`, no `estado::text`.
4. **Expected de errores en `confirmar_reserva` con estado terminal:** `estado_invalido` (no `estado_no_confirmable`).
5. **Métrica clave de éxito de lock:** B debe esperar aproximadamente el tiempo restante del sleep de A; en esta mecánica, típicamente ≥5s si se lanza ~2s después. Si B retorna en <1s, el lock no serializó → freno.
6. **Verificación adicional con PIDs:** incluir `pg_backend_pid()` en las CTEs de cada pestaña para confirmar sesiones distintas.
7. **`upsert_huesped` antes del lock en `crear_prereserva`:** los fixtures de C-6 pueden crear huésped antes del detector de idempotencia; aceptable y consistente con el comportamiento documentado en L-6D-04.

---

### C-2 — `cancelar_prereserva` + `crear_bloqueo total`

**Objetivo:** validar que el lock global serializa cancelación + bloqueo, y que B procesa **viendo el estado post-COMMIT** de A (sin falso positivo de `conflicto_con_prereserva`).

**Setup:** cabaña 18 (Madre Selva). Pre-reserva fixture 2027-04-01 → 2027-04-03 con `source_event='test_H7_C2_FIXTURE'`. Bloqueo total 2027-04-01 → 2027-04-05. Huésped sintético `Test H7 C2` con `+5491400000002`.

**Ajuste técnico aplicado:** CTEs encadenadas explícitamente (`ejecucion FROM t_pre`, `sleep FROM ejecucion`) para garantizar orden de evaluación. C-2 en adelante usa el patrón. C-1 retroactivamente queda validado por su `elapsed` empírico, pero a partir de C-2 el orden no depende del optimizador.

#### Resultado

| Métrica | Tab A | Tab B |
|---|---|---|
| `pid` | 360865 | 360876 |
| `ts_pre` | 12:18:31.301 | 12:18:32.983 |
| `ts_post` | 12:18:39.309 | 12:18:39.319 |
| `elapsed` | 8.008s | **6.336s** |
| `resultado.ok` | `true` | `true` |
| Output relevante | id_pre_reserva=29, estado_nuevo=`cancelada_por_cliente`, pagos_asociados=0 | id_bloqueo=8, tipo=`total`, activo=true |

**Lectura del lock global:** B arrancó 1.682s después de A. Quedó esperando el lock global 6.336s hasta el COMMIT de A. Procesó 10ms después del COMMIT, vio la pre-reserva ya cancelada, no encontró conflicto y creó el bloqueo. Sin deadlock, sin falso positivo.

#### Validación post-test

- `fixture_cancelada_C2` = 1 (id 29, estado `cancelada_por_cliente`) ✅
- `bloqueo_creado_C2_B` = 1 (id 8, total, motivo `uso_propio`, activo) ✅
- `huesped_C2` = 1 (id 38) ✅
- `logs_C2` = **4** (detalle abajo) ✅

#### Doble logging confirmado empíricamente

Los 4 logs en orden:

| # | `src` | `tabla` | `evento` | `modif_por` | Origen |
|---|---|---|---|---|---|
| 1 | `test_H7_C2_FIXTURE` | `pre_reservas` | `prereserva_creada` | `crear_prereserva` | log explícito de `crear_prereserva` al crear fixture (INSERT) |
| 2 | `test_H7_C2_A` | `pre_reservas` | **`null`** | `cancelar_prereserva` | log automático del trigger `trg_log_*_estado` por UPDATE de estado |
| 3 | `test_H7_C2_A` | `pre_reservas` | `prereserva_cancelada` | `cancelar_prereserva` | log explícito de `cancelar_prereserva` (evento de negocio) |
| 4 | `test_H7_C2_B` | `bloqueos` | `bloqueo_creado` | `test_H7` | log explícito de `crear_bloqueo`. `modif_por` viene del `creado_por` del payload |

**Confirma el patrón documentado en `CLAUDE.md`:** doble log en transiciones de estado de `pre_reservas`/`reservas`/`pagos` (trigger técnico + función semántica), ambos heredando `source_event` vía `set_config('app.source_event', ...)`. Decisión D38 vigente.

**Implicación para tests siguientes:** los UPDATE de estado generan log dual. Esperar logs adicionales en C-5/C-3/C-4 según número de transiciones.

#### Cleanup y estado final

DELETE en orden FK-seguro. Baseline restaurado: pagos=1, pre_reservas=2, reservas=1, huespedes=2, bloqueos=2, log_cambios=11. Residuos `test_H7_C2_%` = 0.

**C-2 cerrado ✅**

---

### C-5 (legacy v1.5) — `confirmar_reserva` + `cancelar_prereserva`

**Objetivo:** validar empíricamente que la corrección estructural de v1.5 (lock global SIEMPRE antes de cualquier FOR UPDATE) elimina el deadlock cruzado que existía pre-v1.5 entre `confirmar_reserva` y `cancelar_prereserva` sobre la misma pre-reserva.

**Test crítico de regresión.** Si aparecía `40P01` → bloqueaba C-3, C-4, C-6.

**Setup:** cabaña 19 (Arrebol). Pre-reserva fixture 31 con rango 2027-05-01 → 2027-05-03 (`source_event='test_H7_C5_FIXTURE_PR'`). Pago fixture id=14, sena, confirmado directo (`source_event='test_H7_C5_FIXTURE_PAGO'`). Huésped sintético `+5491400000005`.

#### Desvío en primer intento — fixture mal armado

Primera corrida del fixture: pago quedó en estado `en_revision` (no `confirmado`). A retornó `sin_pago_confirmado` y B canceló normalmente. **El lock global funcionó correctamente** (B esperó 7.037s) pero el test no validó el camino crítico de v1.5 porque A no llegó al UPDATE de estado a `convertida`.

Diagnóstico tras leer `pg_get_functiondef('registrar_pago(jsonb)')`: la rama "pago confirmado directo" requiere **`payload.estado_inicial = 'confirmado'`** Y `monto_recibido = monto_esperado`. Sin `estado_inicial`, cae al default `en_revision`. Hallazgo no documentado en el snapshot inicial porque `registrar_pago` no es de las 4 funciones críticas con lock global. Limpieza dirigida de residuos y re-ejecución con payload corregido.

**Hallazgos del cuerpo real de `registrar_pago` (relevantes para C-3, C-4):**

1. Para pago `confirmado` directo: `estado_inicial='confirmado'` + `monto_recibido=monto_esperado` + pre-reserva activa.
2. `registrar_pago` promueve la pre-reserva de `pendiente_pago` → `pago_en_revision` siempre que esté activa, independiente del estado del pago resultante.
3. `modificado_por` del log explícito = `COALESCE(validado_por, 'registrar_pago')`. Si payload trae `validado_por='X'`, log queda con `modif_por='X'`.
4. Campo correcto: `referencia_externa`, no `referencia`.

#### Resultado de la corrida válida

| Métrica | Tab A | Tab B |
|---|---|---|
| `pid` | 376612 | 376614 |
| `ts_pre` | 17:16:23.799 | 17:16:25.527 |
| `ts_post` | 17:16:31.835 | 17:16:31.838 |
| `elapsed` | 8.035s | **6.310s** |
| `resultado.ok` | `true` | `false` |
| Output relevante | id_reserva=9, id_pre_reserva=31, id_huesped=40 | `error=estado_no_cancelable`, `estado_actual=convertida` |

**Lectura del lock global:** B arrancó a las 25.527 (1.7s después de A, mientras A dormía). Quedó esperando el lock global tomado por A. Lo recibió 3ms después del COMMIT de A. Validó estado de pre-reserva: ya estaba `convertida` (UPDATE persistido por A). Rebotó con `estado_no_cancelable`. **Sin `40P01`. Sin race. Sin falso positivo.**

**Corrección estructural v1.5 vigente en DEV:** B tomó el lock global antes de cualquier otro lock; nunca quedó con un row lock que A necesitara, ni viceversa. La invariante de orden "lock global SIEMPRE primero, antes de FOR UPDATE" elimina la posibilidad estructural del cruce.

#### Validación post-test

- `prereserva_convertida_C5` = 1 (id 31, estado `convertida`) ✅
- `reserva_creada_C5_A` = 1 (id 9, cab 19, estado `confirmada`, monto_saldo=50000, encargado=`Franco`) ✅
- `pago_asociado_a_reserva_C5` = 1 (pago 14 con `id_reserva=9` poblado por `confirmar_reserva` sección 8, estado sigue `confirmado`) ✅
- `bloqueo_NO_creado_C5` = 0 ✅
- `huesped_C5` = 1 (id 40, `total_reservas=1`, `primera_reserva_fecha=2027-05-01`) ✅
- `logs_C5` = **5** ✅

#### Desglose de los 5 logs

| # | `src` | `tabla` | `evento` | `modif_por` | Origen |
|---|---|---|---|---|---|
| 1 | FIXTURE_PR | pre_reservas | `prereserva_creada` | `crear_prereserva` | INSERT pre-reserva (log explícito) |
| 2 | FIXTURE_PAGO | pre_reservas | `null` | `registrar_pago` | trigger automático: UPDATE estado → `pago_en_revision` |
| 3 | FIXTURE_PAGO | pagos | `pago_registrado` | `test_H7` | INSERT pago (log explícito; `modif_por` viene de `validado_por`) |
| 4 | C5_A | pre_reservas | `null` | `confirmar_reserva` | trigger automático: UPDATE estado → `convertida` |
| 5 | C5_A | reservas | `reserva_confirmada` | `confirmar_reserva` | INSERT reserva (log explícito) con `camino='estricto'` |

**Hallazgo confirmado empíricamente:** el trigger `trg_log_*_estado` sobre `pagos` NO dispara en UPDATE de `id_reserva` (asociación post-confirmación). Solo dispara en UPDATE OF estado. Consistente con el contrato documentado en `ESTADO_ACTUAL_VITA_DELTA.md`: *"3 triggers AFTER UPDATE OF estado para log automático de transiciones"*.

**B no genera logs:** rebota en sección 3 de `cancelar_prereserva` antes del log explícito de sección 6, y antes de cualquier UPDATE → ningún trigger.

#### Cleanup y estado final

DELETE FK-seguro en orden: logs → pagos → reservas → pre_reservas → huésped huérfano. Filtro `source_event LIKE 'test_H7_C5_%'`. Baseline restaurado: pagos=1, pre_reservas=2, reservas=1, huespedes=2, bloqueos=2, log_cambios=11, residuos=0.

**C-5 cerrado ✅**

#### Implicaciones para C-3, C-4

- C-3 y C-4 también requieren pre-reserva confirmable: usar mismo patrón de fixture (`estado_inicial='confirmado'` + monto_recibido=monto_esperado).
- `B.elapsed` esperado para C-3 y C-4: similar (5-7s) si lock global serializa.
- Freno especial **`40P01` en C-3 bloquea C-4 y C-6** sigue vigente.

#### Aprendizajes adicionales (más allá de los ya documentados)

1. **Para fixtures multipaso, leer cuerpos reales de TODAS las funciones write involucradas**, no solo las críticas de concurrencia. Snapshot inicial de H7 capturó solo las 4 con lock global; faltó `registrar_pago` que era requisito para C-5/C-3/C-4.
2. **Trigger `trg_log_*_estado` sobre `pagos` no dispara en UPDATE de `id_reserva`** (solo en UPDATE OF estado). Confirma contrato AFTER UPDATE OF estado.
3. **Corrección estructural v1.5 (lock global primero) confirmada bajo concurrencia real.** Cierre retroactivo del bug documentado en `6B_SCHEMA_SQL.md` Sección RESUMEN v1.4 → v1.5.

---

### C-3 — `confirmar_reserva` + `crear_bloqueo` específico (lock global + lock por cabaña)

**Objetivo:** validar que la combinación lock global (10,0) + lock por cabaña (1, id_cabana) serializa correctamente cuando ambas pestañas necesitan ambos locks sobre la misma cabaña. C-3 prueba la superficie de concurrencia más densa de H7: A toma 4 locks distintos (global, cabaña, FOR UPDATE pre-reserva, FOR UPDATE pago), B intenta 2 (global + cabaña).

**Freno especial:** `40P01` en C-3 → bloquea C-4 y C-6. Resultado: sin deadlock, freno liberado.

**Setup:** cabaña 20 (Guatemala, chica). Pre-reserva fixture 32 con rango 2027-06-01 → 2027-06-03. Pago fixture 15 sena confirmado directo. Huésped sintético 41, `+5491400000003`.

#### Resultado

| Métrica | Tab A | Tab B |
|---|---|---|
| `pid` | 377364 | 377366 |
| `ts_pre` | 17:27:14.637 | 17:27:16.127 |
| `ts_post` | 17:27:22.663 | 17:27:22.667 |
| `elapsed` | 8.026s | **6.539s** |
| `resultado.ok` | `true` | `false` |
| Output relevante | id_reserva=10, id_pre_reserva=32, id_huesped=41 | `error=conflicto_con_reserva`, `reservas_en_conflicto=[10]` |

**Lectura:** B arrancó 1.490s después de A. Quedó esperando el lock global tomado por A. Lo recibió 1ms después del COMMIT de A. Tomó lock por cabaña (libre porque A ya commiteó). Chequeo rama 3.A.1 de `crear_bloqueo` (bloqueo específico → reservas activas en cab 20 con overlap) encontró la reserva 10 recién creada por A. Rebotó con `conflicto_con_reserva`, devolviendo el id 10 (el que acababa de generar A). **Visibilidad limpia post-COMMIT: B no vio snapshot intermedio.**

#### Validación post-test

- `prereserva_convertida_C3` = 1 (id 32, estado `convertida`) ✅
- `reserva_creada_C3_A` = 1 (id 10, cab 20, monto_saldo=50000, encargado=`Franco`) ✅
- `pago_asociado_a_reserva_C3` = 1 (pago 15 con `id_reserva=10` poblado, estado `confirmado`) ✅
- `bloqueo_NO_creado_C3_B` = 0 ✅
- `huesped_C3` = 1 (id 41, `total_reservas=1`, `primera_reserva_fecha=2027-06-01`) ✅
- `logs_C3` = **5** (mismo patrón que C-5) ✅

#### Desglose de los 5 logs

Idéntico al patrón consolidado en C-5:

| # | `src` | `tabla` | `evento` | `modif_por` |
|---|---|---|---|---|
| 1 | FIXTURE_PR | pre_reservas | `prereserva_creada` | `crear_prereserva` |
| 2 | FIXTURE_PAGO | pre_reservas | `null` | `registrar_pago` (trigger) |
| 3 | FIXTURE_PAGO | pagos | `pago_registrado` | `test_H7` |
| 4 | C3_A | pre_reservas | `null` | `confirmar_reserva` (trigger) |
| 5 | C3_A | reservas | `reserva_confirmada` | `confirmar_reserva` |

B no generó logs: `crear_bloqueo` rebotó en sección 3.A.1 antes del INSERT y antes del log explícito de sección 5.

#### Cleanup y estado final

DELETE FK-seguro en orden: logs → pagos → reservas → bloqueos (defensivo) → pre_reservas → huésped huérfano. Baseline restaurado: pagos=1, pre_reservas=2, reservas=1, huespedes=2, bloqueos=2, log_cambios=11, residuos=0.

**C-3 cerrado ✅**

#### Validación adicional confirmada por C-3

- **Lock global + lock por cabaña actúan en cadena correcta.** El doble lock advisory documentado en `6B_SCHEMA_SQL.md` (Capa 0 + Capa 1) funciona bajo concurrencia real con 4 locks en flight simultáneos en A.
- **EXCLUDE constraint sobre reservas no fue necesario.** El chequeo aplicativo de `crear_bloqueo` rebotó antes del INSERT. El EXCLUDE queda como red de seguridad estructural, pero la lógica aplicativa la protege primero. Consistente con principio de defensa en profundidad.
- **Cabañas chicas (capacidad 2-4) operan idénticamente bajo concurrencia que grandes.** No hay paths diferenciados por tipo de cabaña.

#### Implicaciones para C-4 y C-6

- C-4 (doble `confirmar_reserva` sobre misma pre-reserva): toma exactamente los mismos locks que C-3 Tab A, dos veces. Cab 21 (Tokio).
- C-6 (doble `crear_prereserva` con `idempotency_key`): patrón distinto, prueba el detector de idempotencia en sus 3 ramas (`pre_lock`, `post_lock`, `unique_violation`).

---

### C-4 — Doble `confirmar_reserva` sobre la misma pre-reserva

**Objetivo:** validar que dos invocaciones simultáneas de `confirmar_reserva` sobre la misma pre-reserva resultan en **una sola reserva creada**. La segunda debe rebotar con `estado_invalido` y `estado_actual="convertida"` (verificado contra cuerpo real de `confirmar_reserva` sección 2).

**Test crítico de doble booking.** Es el escenario más realista en producción: webhook MercadoPago confirmando un pago al mismo tiempo que Vicky confirma manualmente desde WhatsApp, o dos clicks duplicados sobre el mismo botón.

**Freno especial:** `40P01` en C-4 (heredado de C-3) → bloquearía C-6. Resultado: sin deadlock, C-6 desbloqueado.

**Setup:** cabaña 21 (Tokio, chica). Pre-reserva fixture 33 con rango 2027-07-01 → 2027-07-03. Pago fixture 16 sena confirmado directo. Huésped sintético 42, `+5491400000004`.

**Defensa diagnóstica:** Tab A usa `encargado_semana='Franco'`, Tab B usa `'Rodrigo'`. Si por race condition se crearan dos reservas, quedarían diferenciadas por encargado distinto.

#### Resultado

| Métrica | Tab A | Tab B |
|---|---|---|
| `pid` | 377996 | 377997 |
| `ts_pre` | 17:37:03.572 | 17:37:05.545 |
| `ts_post` | 17:37:11.601 | 17:37:11.603 |
| `elapsed` | 8.028s | **6.058s** |
| `resultado.ok` | `true` | `false` |
| Output relevante | id_reserva=11, id_pre_reserva=33, id_huesped=42 | `error=estado_invalido`, `estado_actual=convertida` |

**Lectura del lock global y FOR UPDATE:** B esperó al COMMIT de A. Cuando obtuvo el lock global y tomó FOR UPDATE sobre pre_reserva 33, la fila ya estaba en estado `convertida` (UPDATE persistido por A). La validación de sección 2 `estado IN ('pendiente_pago', 'pago_en_revision')` rebotó con `estado_invalido`. **Sin race, sin deadlock, sin doble booking.**

#### Validación post-test — crítica

- **`reservas_creadas_C4` = 1** (id 11, encargado=`Franco`, source=`test_H7_C4_A`) ← **no hubo doble booking**
- `prereserva_convertida_C4` = 1 (id 33, estado `convertida`) ✅
- `pago_asociado_a_reserva_C4` = 1 (pago 16 con `id_reserva=11`, estado `confirmado`) ✅
- `bloqueo_NO_creado_C4` = 0 ✅
- `huesped_C4` = 1 (id 42, `total_reservas=1`, `primera_reserva_fecha=2027-07-01`) ✅
- `logs_C4` = 5 (patrón idéntico a C-5/C-3) ✅

Tab B con `encargado='Rodrigo'` no dejó huella en `reservas`. Confirma que el FOR UPDATE sobre la pre-reserva + validación de estado sirve como barrera estructural contra confirmación duplicada.

#### Desglose de logs (idéntico a C-5/C-3)

| # | `src` | `tabla` | `evento` | `modif_por` |
|---|---|---|---|---|
| 1 | FIXTURE_PR | pre_reservas | `prereserva_creada` | `crear_prereserva` |
| 2 | FIXTURE_PAGO | pre_reservas | `null` | `registrar_pago` (trigger) |
| 3 | FIXTURE_PAGO | pagos | `pago_registrado` | `test_H7` |
| 4 | C4_A | pre_reservas | `null` | `confirmar_reserva` (trigger) |
| 5 | C4_A | reservas | `reserva_confirmada` | `confirmar_reserva` |

B no generó logs: rebotó en sección 2 antes de cualquier UPDATE y antes del log explícito de sección 11.

#### Cleanup y estado final

DELETE FK-seguro en orden. Baseline restaurado: pagos=1, pre_reservas=2, reservas=1, huespedes=2, bloqueos=2, log_cambios=11, residuos=0.

**C-4 cerrado ✅**

#### Implicancias operativas

- **El sistema está protegido contra doble booking por confirmación concurrente.** El patrón "lock global → FOR UPDATE pre-reserva → validación de estado" es estructuralmente seguro.
- **Combinado con C-3:** el mismo patrón también protege contra bloqueo + confirmación simultáneos.
- **Próximo:** C-6 (idempotencia en `crear_prereserva`). Último test de H7.

---

### C-6 — Doble `crear_prereserva` con misma `idempotency_key` (legacy idempotencia)

**Objetivo:** validar que bajo concurrencia real la idempotencia de `crear_prereserva` evita duplicados (una sola pre-reserva creada), y observar empíricamente cuál rama del detector se activa en B (`pre_lock` / `post_lock` / `unique_violation`).

**Diferencia con tests anteriores:** ambas pestañas ejecutan `crear_prereserva` con la misma `idempotency_key='test_H7_C6_idem_001'`. Distintos huéspedes (`+5491400000006` para A, `+5491400000007` para B) para permitir diagnóstico de en qué rama detectó B.

**Setup:** cabaña 17 (Bamboo, reutilizada después de C-1). Rango 2027-08-01 → 2027-08-03 (lejos de C-1). Sin fixture previo.

#### Resultado

| Métrica | Tab A | Tab B |
|---|---|---|
| `pid` | 378627 | 378629 |
| `ts_pre` | 17:46:56.363 | 17:46:58.177 |
| `ts_post` | 17:47:04.394 | 17:47:04.396 |
| `elapsed` | 8.030s | **6.218s** |
| `resultado.ok` | `true` | `true` |
| Output relevante | id_pre_reserva=34, id_huesped=43, recovery_path=null | **idempotent_match=true, id_pre_reserva=34 (igual A), id_huesped=43 (igual A), recovery_path=`post_lock`** |

**Sin doble booking.** B retornó los IDs de A con `idempotent_match=true`.

#### Rama empírica observada: `post_lock`

Línea de tiempo reconstruida:
17:46:56.36x  A: pre-check idem (sec 3) → no existe key → avanza
A: upsert_huesped (sec 4) → crea huésped 43
A: locks (sec 5) → toma lock global + cabaña
A: double-check idem (sec 5.bis) → no existe → avanza
A: INSERT pre-reserva 34 (sec 9)
A: log + retorno + pg_sleep(8)
[LOCK GLOBAL TOMADO POR A, pre-reserva 34 NO commiteada aún]
17:46:58.17x  B: pre-check idem (sec 3) →
NO ve pre-reserva 34 porque A no commiteó (READ COMMITTED)
→ avanza
B: upsert_huesped (sec 4) → crea huésped 44 (telefono distinto)
B: locks (sec 5) → intenta lock global → ESPERA
17:47:04.394  A: COMMIT → libera lock global, persiste pre-reserva 34
17:47:04.39x  B: obtiene lock global → toma lock cabaña
B: double-check idem (sec 5.bis) →
AHORA ve pre-reserva 34 → retorna con
recovery_path='post_lock', idempotent_match=true,
id_pre_reserva=34, id_huesped=43
17:47:04.396  B: COMMIT

**Por qué `post_lock` y no `pre_lock`:** B llegó al pre-check (sec 3) ANTES del COMMIT de A. Postgres en READ COMMITTED (default) no expone filas de transacciones no commiteadas, así que B no vio la pre-reserva 34 en el pre-check. Avanzó hasta el lock global, esperó al COMMIT, y el double-check post-lock sí la encontró.

**Confirma que la sección 5.bis (double-check post-lock) es necesaria.** Sin esa sección, B hubiera avanzado al INSERT con `idempotency_key` duplicada → dependería del handler `WHEN unique_violation` de sección 9. El double-check captura el caso antes y permite un retorno limpio con `recovery_path='post_lock'`.

#### Validación post-test

- `prereservas_con_idempotency_key` = 1 (solo la de A, id=34, source=`test_H7_C6_A`) ✅
- `prereservas_source_C6` = 1 (B no creó pre-reserva con su `source_event`) ✅
- `huespedes_C6` = 2 (huésped 43 creado por A, huésped 44 huérfano creado por B antes del lock) ✅
- `logs_C6` = 1 (solo `prereserva_creada` de A; B no genera log porque retorna en sec 5.bis antes del log explícito de sec 10)

**Huésped 44 huérfano:** B ejecutó `upsert_huesped` antes del lock global, creando el huésped con su teléfono distinto. Es residuo esperado y consistente con la documentación L-6D-04 (`upsert_huesped` se ejecuta antes del lock en `crear_prereserva`). El cleanup dirigido por `NOT EXISTS` sobre `pre_reservas` y `reservas` lo borra correctamente.

#### Cleanup y estado final

DELETE FK-seguro: logs → pre_reservas → huéspedes huérfanos (43 y 44, ambos sin pre-reservas asociadas tras borrar la pre-reserva 34). Baseline restaurado: pagos=1, pre_reservas=2, reservas=1, huespedes=2, bloqueos=2, log_cambios=11, residuos=0.

**C-6 cerrado ✅**

#### Hallazgos confirmados

1. **Idempotencia funciona bajo concurrencia real.** Una sola pre-reserva creada a pesar de invocación simultánea con misma key.
2. **Rama observada empíricamente: `post_lock`.** Con `pg_sleep(8)` en A y lanzamiento de B a ~2s, este es el caso típico: B llega al pre-check antes del COMMIT de A pero al lock después.
3. **Sección 5.bis (double-check post-lock) está vigente y es necesaria.** Es la que atrapa el caso `post_lock`.
4. **Rama `pre_lock` NO observada en este test.** Para gatillarla habría que lanzar B después del COMMIT de A (sin `pg_sleep` o con timing distinto). Queda como observación: no hubo cobertura empírica de `pre_lock` ni `unique_violation` en H7, pero ambas ramas están en el cuerpo real de la función y son alcanzables por diseño.
5. **Huésped huérfano post-test es comportamiento esperado.** `upsert_huesped` antes del lock crea el huésped antes del detector de idempotencia post-lock. Para producción, considerar si conviene mover `upsert_huesped` después del lock global o agregar un pre-check más estricto. Va a Features_Futuras.md como item opcional de optimización (no es bug, es trade-off documentado).

---

### Cierre H7

**Fecha de cierre:** 2026-05-27
**Estado:** Cerrado ✅
**Tests ejecutados:** C-1, C-2, C-5, C-3, C-4, C-6 — 6 de 6 aprobados.
**Deadlocks:** 0.
**Races / doble bookings / falsos positivos:** 0.
**Residuos en DEV:** 0.

#### Matriz consolidada

| Test | Funciones | Cab | Rango | A.elapsed | B.elapsed | B.error/match | Status |
|---|---|---|---|---|---|---|---|
| C-1 | crear_prereserva + crear_bloqueo total | 17 | 2027-03 | 8.021s | 6.317s | conflicto_con_prereserva | ✅ |
| C-2 | cancelar_prereserva + crear_bloqueo total | 18 | 2027-04 | 8.008s | 6.336s | B ok=true | ✅ |
| C-5 | confirmar_reserva + cancelar_prereserva | 19 | 2027-05 | 8.035s | 6.310s | estado_no_cancelable | ✅ |
| C-3 | confirmar_reserva + crear_bloqueo específico | 20 | 2027-06 | 8.026s | 6.539s | conflicto_con_reserva | ✅ |
| C-4 | Doble confirmar_reserva | 21 | 2027-07 | 8.028s | 6.058s | estado_invalido | ✅ |
| C-6 | Doble crear_prereserva idempotency | 17 | 2027-08 | 8.030s | 6.218s | idempotent_match (post_lock) | ✅ |

#### Confirmaciones estructurales

1. **Invariante de locks v1.5 vigente en DEV.** El orden "lock global SIEMPRE primero antes de cualquier FOR UPDATE / lock por cabaña" funciona correctamente bajo concurrencia real. Cero deadlocks `40P01` en 12 ejecuciones cruzadas.

2. **Lock global serializa correctamente.** `B.elapsed` consistente entre 6.06s y 6.54s, con `B.ts_post ≈ A.ts_post`. La pestaña B siempre esperó al COMMIT de A y procesó viendo el estado post-COMMIT.

3. **EXCLUDE constraints no fueron necesarios.** Los chequeos aplicativos rebotaron antes del INSERT en todos los casos. EXCLUDE queda como red de seguridad estructural sin disparar.

4. **Visibilidad post-COMMIT consistente.** B siempre vio los cambios de A después del COMMIT (estado de pre-reserva, reserva nueva, etc.). Sin lecturas de snapshot intermedio.

5. **Idempotencia de `crear_prereserva` funcional.** Sección 5.bis (double-check post-lock) atrapó el caso bajo concurrencia, devolviendo retorno limpio con `recovery_path='post_lock'`.

6. **Doble logging confirmado en todas las funciones write.** Trigger automático `trg_log_*_estado` + log explícito de la función. Patrón D38 vigente.

#### Hallazgos para H8

Acumulados durante H7:

1. `bloqueos.activo` BOOLEAN (no enum `estado`) — divergencia de patrón con `reservas`/`pre_reservas`/`pagos`. Candidato L-6D-06.
2. `cabanas.capacidad_max` (no `capacidad_maxima`) — divergencia documental.
3. `confirmar_reserva` retorna `estado_invalido` (no `estado_no_confirmable`) cuando estado terminal — corregido en expected de C-4.
4. `telefono_normalizado` preserva el `+` del prefijo internacional — corregido en cleanups subsiguientes.
5. SQL Editor "+" interno comparte runner; dos tabs separadas del navegador permiten paralelismo real — candidato L-6D-06 (mecánica de tests de concurrencia).
6. Mini-test de PIDs con `pg_sleep(5)` valida paralelismo antes de ejecutar tests críticos — patrón operativo recomendado.
7. CTEs encadenadas (`MATERIALIZED` + `FROM`) requeridas para tests con `pg_sleep` dentro de transacción — patrón aplicado de C-2 en adelante.
8. `registrar_pago` requiere `estado_inicial='confirmado'` Y `monto_recibido=monto_esperado` para producir pago `confirmado` directo. Sin esos parámetros, default es `en_revision`. Hallazgo crítico para fixtures.
9. `modificado_por` del log de `registrar_pago` = `COALESCE(validado_por, 'registrar_pago')`. Si payload trae `validado_por`, ese valor queda en el log.
10. Trigger `trg_log_*_estado` sobre `pagos` solo dispara en UPDATE OF estado, no en UPDATE de `id_reserva` (confirmado en C-5).
11. `crear_prereserva` ejecuta `upsert_huesped` antes del lock global. Bajo concurrencia con idempotencia (C-6), B puede crear huésped huérfano que queda para cleanup. Consistente con L-6D-04.
12. `recovery_path='pre_lock'` no fue gatillado empíricamente en H7. Para cobertura completa de las 3 ramas requeriría test adicional con timing distinto. No bloqueante.

#### Decisiones cerradas durante H7 (candidato D-HARD-07 en adelante)

- **D-H7-1:** mantener nomenclatura consolidada C-1 a C-6 (de `Pendiente_pre_produccion.md`) + legacy C-5/C-6 (del plan 6B original).
- **D-H7-2:** convención `source_event='test_H7_C{N}_{ROL}'` para todos los recursos creados.
- **D-H7-3:** cleanup por test con filtro específico `LIKE 'test_H7_C{N}_%'`, no cleanup global al final.
- **D-H7-4:** mecánica de paralelismo: dos tabs separadas del navegador + CTEs encadenadas con MATERIALIZED + `clock_timestamp()` + `pg_backend_pid()` para medición empírica.
- **D-H7-5:** freno duro ante cualquier `40P01`. Frenos especiales en C-5 (bloquea C-3/C-4/C-6) y C-3 (bloquea C-4/C-6) no se activaron.

#### Schema

Sin cambios estructurales. H7 fue test de validación, no modificó funciones ni vistas. DEV permanece en v1.7.2 (bumped en H2-H6-bis).

**H7 cerrado ✅**

**Etapa 6D — H1 a H7 cerrados. Solo queda H8.**