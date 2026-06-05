# Lecciones Operativas — Vita Delta

## Sobre PostgreSQL / Supabase

### `NOW()` y transacciones implícitas
PostgreSQL `NOW()` retorna timestamp de inicio de transacción, no del statement.
Cuando varios statements en la misma pestaña del SQL Editor corren juntos,
Supabase los envuelve en una transacción implícita.

**Implicación:** para validar triggers BEFORE UPDATE de updated_at,
ejecutar INSERT y UPDATE en runs separados (transacciones distintas).

### Pop-up destructive de Supabase
Solo se dispara con palabras textuales INSERT/UPDATE/DELETE/DROP/ALTER en SQL.
NO se dispara con `SELECT funcion(...)` aunque la función internamente escriba.

### configuracion_general NO tiene created_at
Solo tiene updated_at. No usar created_at en queries sobre esa tabla.

*Origen: Bloque 19 / 2026-05-24*

---

## Sobre Setup y Limpieza

### Re-ejecutar setups después de errores
Statements exitosos previos quedan commiteados. Reducir la pestaña a solo
lo faltante antes de re-correr.

### Verificación de "no modificación" de un registro
Usar `updated_at = created_at` en vez de `updated_at > NOW() - INTERVAL N`.
La segunda fórmula puede dar falsos positivos si el registro se creó dentro
de la ventana de tiempo.

### Tests de error pueden dejar residuos parciales
Las funciones que tocan múltiples tablas (ej. crear_prereserva escribe
en huespedes ANTES de validar cabaña) pueden dejar registros aunque el
test falle con error controlado. Limpiar contemplando TODAS las tablas
que la función toca, no solo el output esperado.

*Origen: Bloque 19 / 2026-05-24*

---

## Sobre Display de Resultados en Supabase

### SQL Editor muestra solo el último SELECT
Cuando hay múltiples statements separados por `;`, solo se ve el resultado
del último SELECT. Para ver varios resultados: usar `UNION ALL` con columna
identificadora (`test`, `momento`, `caso`).

*Origen: Bloque 19 / 2026-05-24*

---

## Modelo de daterange `[)` y check-in/check-out

El schema usa rangos exclusivos en checkout: `daterange(fecha_checkin, fecha_checkout, '[)')`.
Esto significa que `fecha_checkout` NO está dentro del rango ocupado.

*Origen: Bloque 20 / 2026-05-24*

### Implicación operativa positiva: ocupación máxima sin gaps

Una cabaña puede tener reservas consecutivas como:
- Reserva A: 5-6 jun (cubre día 5)
- Reserva B: 6-7 jun (cubre día 6)
- Reserva C: 7-8 jun (cubre día 7)

Los 3 rangos NO se solapan porque cada uno cierra antes de empezar el siguiente.
Operativamente: cliente A hace checkout a las 10am del día 6, cliente B hace
checkin a las 13:00 del mismo día 6 (3 horas para limpieza por Jennifer).

*Origen: Bloque 20 / 2026-05-24*

### Protección estructural: EXCLUDE constraint

El constraint `exc_reservas_no_overlap` usa el operador `&&` de daterange.
Detecta automáticamente solapamientos reales y aborta el INSERT con
`exclusion_violation` (código 23P01). Imposible de eludir incluso con bugs
en lógica de aplicación.

Validado empíricamente en Bloque 20 (Fase 3).

---

## Sobre `orden_limpieza` y operativa de limpieza

El campo `cabanas.orden_limpieza` define un orden default sugerido para
la rutina de limpieza diaria de Jennifer. No es regla rígida.

### Orden default (Vita Delta)
1. Bamboo
2. Madre Selva
3. Arrebol
4. Guatemala
5. Tokio

### Pero en la práctica, Jennifer prioriza dinámicamente según:
- Hora de checkout efectiva (`vista_limpieza_semana`)
- Cantidad de personas (cabañas grandes 5p > chicas 2p en tiempo)
- Mascotas (requieren más limpieza)
- Hora de check-in del entrante del mismo día
- Notas especiales de la reserva

### Para cambiar el orden default

```sql
UPDATE cabanas SET orden_limpieza = 3 WHERE nombre = 'Bamboo';
UPDATE cabanas SET orden_limpieza = 1 WHERE nombre = 'Tokio';
```

---

## Bug crítico de Supabase Dashboard con CREATE OR REPLACE FUNCTION

Cuando se ejecuta un `CREATE OR REPLACE FUNCTION` en el SQL Editor de Supabase
con una función PL/pgSQL que contiene variables locales con prefijo `v_`,
Supabase puede detectar incorrectamente esas variables como **nombres de tabla**
e intentar agregar automáticamente al final del SQL:

```sql
ALTER TABLE v_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE v_existente ENABLE ROW LEVEL SECURITY;
-- source: dashboard
```

Esto trunca el SQL original a mitad y causa errores tipo:
`ERROR 42601: unterminated dollar-quoted string`

### Workaround validado

Usar `DROP FUNCTION` seguido de `CREATE FUNCTION` (sin `OR REPLACE`) en runs
separados:

```sql
-- Paso 1: DROP en su propio Run
DROP FUNCTION IF EXISTS mi_funcion(jsonb);
```

```sql
-- Paso 2: CREATE en su propio Run
CREATE FUNCTION mi_funcion(payload JSONB) RETURNS JSONB ... AS $$
DECLARE
  v_config JSONB;  -- ← Supabase ya no lo confunde con tabla
  ...
```

Supabase no activa el feature de auto-RLS cuando hay un DROP previo, porque
entiende que estás reemplazando una función existente.

Origen: Hotfix v1.7 (Fase 3, post-cierre), reemplazo de `crear_prereserva`
con la regla de `hora_checkout_domingo`.

---

## Gotchas de la integración n8n ↔ Supabase

Estas lecciones surgieron durante la Etapa 6C (Reescritura de Workflows n8n contra Supabase DEV).
Aplican a n8n cloud + pooler transaccional de Supabase.
Bitácora detallada: `Docs/Bitacora/6C_EJECUCION.md`.

### L-6C-01 — Configurar SSL con "Ignore SSL Issues" en n8n cloud

**Cuándo aparece:** al testear una credencial PostgreSQL en n8n cloud contra el pooler de Supabase con SSL en `Require`.

**Síntoma:** "Couldn't connect with these settings — self-signed certificate in certificate chain".

**Por qué pasa:** el cliente PostgreSQL de n8n cloud no tiene precargada la cadena de CA de Supabase. Trata el certificado del pooler (que es legítimo) como self-signed.

**Solución:**
- Activar toggle "Ignore SSL Issues (Insecure)" en la credencial.
- Mantener SSL en `Require` (no cambiar a `Disable`).

**Importante:**
- El tráfico TLS sigue cifrado. Solo se desactiva la validación de CA.
- El nombre del toggle dice "Insecure" pero el riesgo real (MITM en canal n8n.cloud ↔ Supabase) es muy bajo. Trade-off aceptado para DEV.
- Si en el futuro se migra a n8n self-hosted con control sobre las CAs cargadas, evaluar pasar a `Verify (CA)` con el certificado de Supabase cargado.

**Descubierto:** 2026-05-25, durante W0.A.

---

### L-6C-02 — Formato del User en credencial PostgreSQL contra el pooler de Supabase

**Cuándo aplica:** al crear cualquier credencial PostgreSQL en n8n que apunte al pooler transaccional de Supabase.

**Detalle:** el usuario PostgreSQL del pooler **no es** `postgres` sino `postgres.<project_id>` (con punto y el project ID concatenado).

Ejemplo: para el proyecto DEV con ID `jqfvtblscxbzlmlcwadi`, el user es `postgres.jqfvtblscxbzlmlcwadi`.

**Diferencia con la conexión directa:**
- Pooler transaccional (puerto 6543): `postgres.<project_id>`.
- Conexión directa (puerto 5432): solo `postgres`.

Si se copia un connection string sin verificar puerto y usuario, es fácil confundir las dos variantes y obtener errores de autenticación opacos.

**Solución:** copiar el `user` exacto desde Supabase Dashboard → Connect → Direct → Transaction pooler.

**Descubierto:** 2026-05-25, durante W0.A.

---

### L-6C-03 — Query Parameters de n8n no permiten enviar NULL real al driver de PostgreSQL

**Cuándo aparece:** al definir Query Parameters de un nodo Postgres con expresiones que pueden evaluar a vacío o null (típicamente parámetros opcionales tipo `id_cabana` que pueden ser "todas las cabañas" = NULL).

**Síntomas observados:**

| Valor en JS | Cómo lo manda n8n | Error en PostgreSQL |
|---|---|---|
| Number `17` | `"17"` | OK |
| String `"abc"` | `"abc"` | OK como texto |
| **String vacío `""`** | **Omitido** de la lista de parámetros | `there is no parameter $N` |
| `null` | `"null"` (string literal con la palabra) | `invalid input syntax for type bigint: "null"` |

**Causa raíz:** los Query Parameters de n8n en formato string-con-comas (`={{ $a }},={{ $b }},={{ $c }}`) stringifican los valores antes de mandarlos al driver. No hay forma de pasar un NULL real desde una expression.

**Workaround estándar (convención `0 = todas`):**

1. En Build Input mantener el parámetro siempre con valor numérico explícito. Reservar el valor `0` para significar "sin filtro" / "todas".
2. En la query SQL convertir `0` a NULL con `NULLIF($N::TYPE, 0)`:
```sql
   SELECT * FROM funcion(
     $1::DATE,
     $2::DATE,
     NULLIF($3::BIGINT, 0)  -- 0 → NULL
   );
```
3. En Build Response convertir de vuelta `0` a `null` para que el contrato externo del workflow sea NULL = todas las cabañas (la convención `0` es solo interna al transport n8n → Postgres):
```javascript
   const idCabanaOut = (idCabanaInput === 0 || idCabanaInput === '0') ? null : idCabanaInput;
```

**Aplicar en cualquier workflow futuro con parámetros opcionales.** Si en el futuro algún parámetro tiene un valor de negocio que podría ser `0` real, elegir otro sentinela (ej. `-1`) para "sin filtro".

**Descubierto:** 2026-05-25, durante W1 Test 2.

---

### L-6C-04 — Resultados vacíos detienen el workflow por default

**Cuándo aparece:** un nodo (típicamente Postgres) ejecuta sin error pero devuelve 0 filas. El workflow se detiene en ese nodo y los nodos siguientes (Build Response, etc.) no se ejecutan.

**Síntoma:** mensaje "No output data returned — n8n stops executing the workflow when a node has no output data."

**Por qué importa:** un workflow de lectura debe poder responder explícitamente "no hay resultados" sin romper. Si el workflow se corta antes del Build Response, el caller no recibe respuesta estructurada (recibe vacío o un error opaco).

**Solución:**

1. En el nodo que puede devolver vacío (típicamente el Postgres) → pestaña Settings → activar **"Always Output Data"**. Cuando devuelve 0 filas, n8n inyecta un único item con `json` vacío `{}` para que el flujo continúe.
2. En el nodo Code downstream que procesa las filas → agregar filter defensivo para que el item vacío inyectado no cuente como una fila real:
```javascript
   const dias = items
     .map(item => item.json)
     .filter(d => d && Object.keys(d).length > 0);
```

**Aplicar en todo workflow de lectura (W1, W7) y en cualquier escritura que pueda devolver 0 filas afectadas como caso de negocio (no como error).**

**Descubierto:** 2026-05-25, durante W1 Tests 3 y 4.

---

### L-6C-05 — Serialización de tipos PostgreSQL en JSON desde n8n

**Cuándo aplica:** al procesar el output de cualquier nodo Postgres en n8n.

**Detalle:** el driver PostgreSQL de n8n serializa algunos tipos de forma que conviene tener presente:

| Tipo PostgreSQL | Cómo llega al JSON de n8n |
|---|---|
| `BIGINT` | **String** (ej. `"17"`, no `17`). El driver lo trata como string porque los enteros de 64 bits pueden exceder el rango seguro de Number de JavaScript (`2^53`). |
| `DATE` | String ISO con timestamp UTC `"2026-06-07T00:00:00.000Z"`. La parte de fecha es correcta; el tiempo `00:00` UTC es un artefacto del cast a `Date` JS. |
| `TIME` | String `"HH:MM:SS"` (sin zona, sin milisegundos). Formato natural. |
| `TIMESTAMP WITH TIME ZONE` | String ISO con zona (ej. `"2026-06-07T16:00:00.000Z"` para UTC). |
| `BOOLEAN` | Boolean nativo (`true`/`false`). |
| `JSONB` | Object/Array nativos. |
| `NULL` | `null`. |

**Implicancias prácticas:**

- Al comparar `id_cabana` recibido con un id literal: tratarlos como strings o convertir con `parseInt()` explícitamente. Ejemplo: `if (String(dia.id_cabana) === '17')` o `if (parseInt(dia.id_cabana, 10) === 17)`.
- Al comparar fechas: extraer solo la parte de fecha del string ISO. Ejemplo: `dia.fecha.substring(0, 10) === '2026-06-07'`.

**No es un bug.** Es comportamiento estándar del driver de PostgreSQL para Node.js (`node-postgres`). Documentado para que no sorprenda en W2+.

**Descubierto:** 2026-05-25, durante validación de W1.

---

### L-6C-06 — Payload JSONB grande vía `JSON.stringify` en queryReplacement funciona limpio

**Cuándo aplica:** al invocar funciones SQL que reciben un único parámetro JSONB (típicamente funciones de escritura tipo `crear_prereserva(jsonb)`, `registrar_pago(jsonb)`, `confirmar_reserva(jsonb)`, etc.).

**Contexto:** después de descubrir las limitaciones de Query Parameters con valores vacíos/null en L-6C-03, surgía la duda de si el patrón de mandar un payload JSONB grande como string serializado iba a tener problemas similares.

**Resultado empírico (W2, 5 tests pasados a la primera):**

Patrón usado:

```sql
SELECT crear_prereserva($1::jsonb) AS resultado;
```

Con queryReplacement:
={{ JSON.stringify($json.payload) }}

**Funciona limpio**, sin omisión de parámetros ni errores de serialización, aun con payloads de 15+ campos incluyendo objetos anidados (ej. `huesped: { nombre, telefono, email }`), valores numéricos, booleanos, strings con caracteres especiales, y campos opcionales en `null`.

**Conclusión:**

El problema documentado en L-6C-03 era **el valor vacío específico**, no el tamaño ni el tipo del parámetro. Un string JSON serializado, por más grande que sea, **nunca es "vacío"** desde la perspectiva de n8n (siempre tiene comillas, llaves, contenido). Por eso n8n no lo omite y PostgreSQL lo recibe como string para castear a `jsonb`.

**Aplicar este patrón en todos los workflows de escritura que sigan (W3, W4, W5, W6).**

**Detalles del patrón estándar para funciones JSONB:**

1. En `Build Payload` construir el objeto `payload` como literal JS y exponerlo:
```javascript
   return [{ json: { payload, idempotency_key, source_event, input } }];
```
2. En el Postgres node:
   - Query: `SELECT funcion_nombre($1::jsonb) AS resultado;`
   - queryReplacement: `={{ JSON.stringify($json.payload) }}`
3. En `Build Response` leer la respuesta: `items[0].json.resultado` y mapear su `ok`/`error` al wrapper externo.

**No requiere ningún workaround.** Es el camino estándar para funciones write con payload JSONB.

**Descubierto:** 2026-05-25, durante W2 Tests 1–5.

---

## Lecciones del Hardening — Etapa 6D

Estas lecciones surgieron durante la sesión 2026-05-26 (bloques H1-H6-bis del hardening estructural).
Aplican al diseño de cambios sobre funciones write y vistas en Supabase.
Bitácora detallada: `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### L-6D-01 — Schema canónico no es fuente de verdad para cuerpos reales

**Cuándo aplica:** al diseñar cambios sobre funciones o vistas existentes en Supabase, donde se tiene un schema canónico documentado (ej. `6B_SCHEMA_SQL.md v1.7.1`).

**Detalle:** el schema canónico documenta la **intención** del diseño, no necesariamente refleja el cuerpo real de los objetos en DEV. Las funciones y vistas pueden haber evolucionado por hotfixes, ajustes de alineación o ediciones puntuales no reflejadas en el canónico.

**Divergencias detectadas durante 6D:**

1. `registrar_pago` (H2): el cuerpo real tenía líneas de log con `COALESCE(v_validado_por, 'registrar_pago')` para `modificado_por`, cast `::nivel_log_enum` explícito, y un campo `es_automatico` en el JSONB del log, ninguno documentado en el schema canónico.
2. `crear_prereserva` (H4): `canal_pago_esperado` es opcional en DEV (no aparece en el check de obligatorios), pero el schema canónico lo describía como obligatorio.
3. `crear_prereserva` (H4): `v_ninos` está declarado como BOOLEAN en DEV, pero el schema canónico lo declaraba TEXT.

**Solución (flujo snapshot-first):**

Antes de proponer cualquier cambio sobre una función o vista existente, capturar su cuerpo real:

```sql
-- Para funciones
SELECT pg_get_functiondef('nombre_funcion(jsonb)'::regprocedure);

-- Para vistas
SELECT pg_get_viewdef('nombre_vista'::regclass, true);
```

Reconstruir cualquier `CREATE OR REPLACE` desde el cuerpo real, no desde el schema canónico. Documentar las divergencias detectadas para decidir si conviene actualizar el schema canónico.

**Descubierto:** 2026-05-26, durante H2 (extract de `registrar_pago` no coincidía con schema canónico v1.7.1).

---

### L-6D-02 — PostgreSQL normaliza expresiones al persistir vistas y funciones

**Cuándo aplica:** al verificar el cuerpo de una vista o función después de un `CREATE OR REPLACE`, comparándolo contra lo que escribimos.

**Detalle:** PostgreSQL al persistir el objeto reescribe ciertas expresiones a su forma canónica interna. Esto puede sorprender si esperás byte-equivalencia entre lo que pegaste y lo que `pg_get_viewdef` devuelve.

**Normalizaciones observadas durante 6D:**

| Lo que escribís | Cómo lo persiste PostgreSQL |
|---|---|
| `TRIM(x)` | `TRIM(BOTH FROM x)` |
| `'12 months'::interval` | `'1 year'::interval` |
| `'1 month'::interval` | `'1 mon'::interval` |

**Implicancias prácticas:**

- No son cambios funcionales. Son sintaxis equivalentes.
- Para facilitar verificaciones futuras (`pg_get_viewdef` o `pg_get_functiondef` comparados con el código fuente), conviene escribir directamente la forma normalizada. Ej. escribir `'1 mon'::interval` en lugar de `'1 month'::interval` ahorra confusión post-deploy.
- Si pegás SQL desde un schema canónico viejo con la forma no normalizada, el cuerpo persistido va a verse "distinto" aunque sea idéntico funcionalmente.

**Descubierto:** 2026-05-26, durante H5 (vista_ocupacion) y H6 (TRIM en concatenación de nombre).

---

### L-6D-03 — Patrón canónico de extract defensivo para funciones write

**Cuándo aplica:** al diseñar o auditar funciones PL/pgSQL que reciben un parámetro `jsonb` con campos del cual extraen valores.

**Patrón canónico:**

```sql
v_campo := NULLIF(TRIM(payload->>'campo'), '')::TIPO;
```

**Qué cubre:**

- Strings vacíos (`""`) → NULL real (no string vacío que pasaría las validaciones `IS NULL`).
- Whitespace puro (`"   "`) → NULL real.
- Errores crudos de cast en BIGINT, DATE, INTEGER, NUMERIC, TIME, BOOLEAN cuando llegan strings vacíos o whitespace.

**Qué NO cubre:**

- Tipos inválidos no vacíos (ej. `id_cabana="abc"` con cast a BIGINT). Siguen rompiendo con error crudo de PostgreSQL. Queda como hardening adicional opcional pre-PROD.

**Cambio observable consistente al aplicar el patrón:**

Cuando un campo obligatorio llega con whitespace (`"   "`), la función rebota con `payload_invalido` en vez de errores específicos del dominio. Por ejemplo, antes del fix `motivo: "   "` en `cancelar_prereserva` devolvía `motivo_invalido` (con lista de motivos válidos); después del fix devuelve `payload_invalido` antes de llegar al check de enum.

Esto es **consistente** con la semántica del patrón: whitespace en obligatorio = valor ausente = `payload_invalido`. Aceptado por consistencia con los demás errores estructurales.

**Aplicado en las 5 funciones write críticas del schema durante 6D:** `registrar_pago` (H2), `confirmar_reserva` (H3), `crear_prereserva` (H4), `cancelar_prereserva` (H4-bis), `crear_bloqueo` (H4-ter). Total: 56 asignaciones unificadas al patrón. `upsert_huesped` ya cumplía el patrón desde antes.

**Descubierto:** 2026-05-26, durante H1 (decisiones previas) y aplicado en H2-H4-ter.

---

### L-6D-04 — Diseño de tests no destructivos en funciones write con operaciones tempranas en tablas

**Cuándo aplica:** al diseñar tests sobre funciones que modifican múltiples tablas, donde algunas modificaciones ocurren temprano en el flujo (antes de validaciones específicas).

**Detalle:** algunas funciones write (notablemente `crear_prereserva`) tienen operaciones que tocan tablas en pasos tempranos del flujo. Específicamente, `crear_prereserva` llama a `upsert_huesped` en sección 4, **antes** de validar la cabaña en sección 6. Cualquier test que pase las validaciones tempranas y llegue al paso 4 va a crear o actualizar un huésped, aunque el test "rebote" después con `cabana_no_existe` u otro error de validación tardía.

**Implicación para diseño de tests:**

1. Identificar el **orden exacto de validaciones y operaciones** de la función. La fuente es el cuerpo real (`pg_get_functiondef`), no el schema canónico.
2. Identificar la **última validación que rebota antes de la primera operación de escritura**. Esa es la frontera segura para tests no destructivos.
3. Diseñar tests que rebotan en o antes de esa frontera.

**Ejemplo concreto (`crear_prereserva`):**

Orden de validaciones y operaciones:

1. Extract de payload (paso 1) — puede romper con cast crudo si no hay defensa.
2. Validación obligatorios → `payload_invalido`.
3. Validación montos → `precio_requerido`.
4. Validación fechas → `fechas_invalidas`.
5. Validación nombre huésped → `huesped_nombre_requerido`.
6. Validación contacto huésped → `huesped_contacto_requerido` ← **última frontera antes de tocar tablas.**
7. `upsert_huesped()` (paso 4) ← **primer punto donde la función modifica DB.**
8. Locks (paso 5).
9. Validación cabaña (paso 6) → `cabana_no_existe`, `cabana_inactiva`, `excede_capacidad`.

Para tests no destructivos de campos opcionales con whitespace, una estrategia segura y simple es enviar un huésped inválido por nombre (`{nombre: "", telefono: "+..."}`), que rebota en `huesped_nombre_requerido`, antes de llegar a `upsert_huesped`.

**Verificación empírica:** comparar `SELECT COUNT(*) FROM huespedes` antes y después de los tests para confirmar que ningún test creó filas.

**Descubierto:** 2026-05-26, durante H4 (diseño de tests para `crear_prereserva`).

---

### L-6D-05 — Verificación de dependencias antes de `CREATE OR REPLACE VIEW`

**Cuándo aplica:** al modificar una vista existente con `CREATE OR REPLACE VIEW`.

**Reglas de PostgreSQL para `CREATE OR REPLACE VIEW`:**

- Permite cambiar el cuerpo de la vista.
- NO permite eliminar columnas existentes, ni cambiar su tipo, ni renombrarlas.
- Permite agregar columnas al final del SELECT.

**Riesgo a verificar:** si otra vista, función u objeto público depende de la vista que vas a modificar, un cambio que altere estructura de columnas puede romper el dependiente. Aún sin cambios de estructura, conviene tener visibilidad del grafo antes de tocar.

**Query de verificación:**

```sql
SELECT
  dependent_obj.relname AS objeto_dependiente,
  CASE dependent_obj.relkind
    WHEN 'v' THEN 'vista'
    WHEN 'm' THEN 'materialized view'
    WHEN 'r' THEN 'tabla'
    WHEN 'i' THEN 'indice'
    WHEN 'f' THEN 'foreign table'
    ELSE 'otro'
  END AS tipo_descripcion
FROM pg_depend d
JOIN pg_rewrite r ON r.oid = d.objid
JOIN pg_class dependent_obj ON dependent_obj.oid = r.ev_class
JOIN pg_class source_obj ON source_obj.oid = d.refobjid
WHERE source_obj.relname = 'nombre_vista'
  AND dependent_obj.relname != 'nombre_vista'
ORDER BY dependent_obj.relname;
```

**Criterios:**

- 0 filas → vía libre.
- Solo objetos internos PostgreSQL → revisar y seguir.
- Vista pública o función operativa dependiente → freno y revisar impacto.

**Validado empíricamente durante 6D:** las 4 vistas modificadas (`vista_ocupacion`, `vista_calendario`, `vista_limpieza_semana`, `vista_prereservas_activas`) tenían 0 dependientes según esta query. `CREATE OR REPLACE VIEW` fue seguro en todos los casos.

**Descubierto:** 2026-05-26, durante H5 (preparación de fix de `vista_ocupacion`).

---

## Lecciones del Hardening — Etapa 6D (continuación: H7)

Estas lecciones surgieron durante la sesión 2026-05-27 (bloque H7 del hardening — tests de concurrencia C-1 a C-6). Aplican al diseño y ejecución de tests de concurrencia, y al uso correcto del contrato real de funciones write secundarias. Bitácora detallada: `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` sección H7.

### L-6D-06 — Mecánica operativa para tests de concurrencia en Supabase SQL Editor

**Cuándo aplica:** al ejecutar tests que requieren dos conexiones SQL independientes corriendo en paralelo (típicamente con `pg_sleep` en una y otra lanzada poco después), donde el objetivo es validar locks, serialización o detección de race conditions.

**Detalle:** el SQL Editor de Supabase no permite por defecto ejecutar dos queries simultáneamente desde la misma sesión de navegador. El botón "+" interno del editor que abre "New Query" comparte un único runner del lado del cliente; el segundo Run queda en cola hasta que el primero termina. Esto invalida la mecánica del plan original "abrir dos pestañas SQL Editor" cuando hay `pg_sleep` largo en una de ellas.

**Solución validada empíricamente:** abrir **dos tabs separadas del navegador**, cada una con su propio `https://supabase.com/...` cargado. Cada tab mantiene su propia conexión WebSocket al backend, lo que permite paralelismo real. Confirmado en H7 con PIDs distintos en ambas tabs (`pg_backend_pid()` retorna IDs diferentes) y solapamiento temporal de ejecución.

**Mini-test de validación previo a cualquier sesión crítica:**

```sql
-- Ejecutar simultáneo en dos tabs distintas
WITH
inicio AS MATERIALIZED (
  SELECT clock_timestamp() AS ts_inicio, pg_backend_pid() AS pid
),
sleep AS MATERIALIZED (
  SELECT pg_sleep(5) AS done
)
SELECT
  inicio.pid,
  inicio.ts_inicio,
  clock_timestamp() AS ts_fin,
  clock_timestamp() - inicio.ts_inicio AS elapsed
FROM inicio, sleep;
```

Si ambas tabs devuelven `elapsed ≈ 5s` con PIDs distintos y los rangos de `ts_inicio` y `ts_fin` se solapan, hay paralelismo real. Si una tab termina ~10s después de la otra, no hay paralelismo y la mecánica no sirve.

**CTEs encadenadas con `MATERIALIZED` quedan como patrón aprobado para estos tests.** Para garantizar orden de ejecución dentro de cada tab cuando hay `pg_sleep` en transacción, las CTEs deben tener dependencias explícitas (`FROM cte_anterior`), no solo `MATERIALIZED`. El optimizador puede reordenar CTEs independientes; con `FROM` explícito no puede.

Patrón aplicado en H7 a partir de C-2:

```sql
BEGIN;
WITH
t_pre AS MATERIALIZED (
  SELECT clock_timestamp() AS ts_pre, pg_backend_pid() AS pid
),
ejecucion AS MATERIALIZED (
  SELECT t_pre.ts_pre, t_pre.pid, mi_funcion(...) AS resultado
  FROM t_pre
),
sleep AS MATERIALIZED (
  SELECT ejecucion.ts_pre, ejecucion.pid, ejecucion.resultado,
         pg_sleep(8) AS done
  FROM ejecucion
)
SELECT ... FROM sleep;
COMMIT;
```

**Output unificado en una sola fila.** Supabase SQL Editor muestra solo el resultado del último SELECT (regla operativa documentada en sección anterior). Con el patrón de arriba, toda la información del test (timestamps, PID, JSON de retorno, elapsed) cabe en una sola fila del último SELECT, sin perder evidencia.

**Alternativa si dos tabs no logran paralelismo:** ventana incógnita o segundo navegador (cada uno con sesión separada), o `psql` local contra el pooler de Supabase. Validar siempre primero con el mini-test antes de empezar tests críticos.

**Descubierto:** 2026-05-27, durante el intento fallido de C-1 (botón "+" interno serializó ambas pestañas) y resuelto inmediatamente con dos tabs del navegador (PIDs 359653 vs 359654, solapamiento confirmado).

---

### L-6D-07 — Contrato real de `registrar_pago` para producir pago `confirmado` directo

**Cuándo aplica:** al construir fixtures multipaso que requieren pre-reserva con pago confirmado asociado, por ejemplo para tests de `confirmar_reserva` por camino estricto.

**Detalle:** `registrar_pago` por defecto inserta pagos en estado `en_revision`. Para que un pago quede `confirmado` directo en el INSERT (sin requerir confirmación manual posterior), el payload debe cumplir simultáneamente:

1. `estado_inicial = 'confirmado'` (explícito en el payload).
2. `monto_recibido = monto_esperado` (montos coincidentes).
3. Pre-reserva referenciada debe estar en estado activo (no en estados terminales como `cancelada_por_cliente`, `vencida`, `cancelada_por_bloqueo`, `conflicto_pendiente`).

Si falta `estado_inicial='confirmado'` o los montos no coinciden, el pago cae al flujo `en_revision`. Si la pre-reserva no está activa, la función puede rebotar según validaciones internas.

**`es_automatico=true` por sí solo NO es suficiente.** El flag `es_automatico` se persiste en el INSERT pero no afecta el cálculo de `v_estado_final`. La condición es solamente `estado_inicial='confirmado' AND monto_recibido=monto_esperado`.

**Comportamiento adicional:** `registrar_pago` siempre promueve la pre-reserva de `pendiente_pago` → `pago_en_revision` (sección 6 del cuerpo) cuando la pre-reserva está activa, **independiente del estado final del pago resultante**. Esto significa que un pago `confirmado` directo deja la pre-reserva en `pago_en_revision`, no en un estado nuevo. `confirmar_reserva` acepta `pre.estado IN ('pendiente_pago', 'pago_en_revision')`, así que es funcional.

**Campo correcto del payload:** `referencia_externa`, no `referencia` (este último no es campo válido y se ignora silenciosamente sin error).

**`modificado_por` del log explícito de `registrar_pago`** se calcula como `COALESCE(v_validado_por, 'registrar_pago')`. Si el payload trae `validado_por='X'`, el log queda con `modif_por='X'`. Si no trae `validado_por`, el log queda con `modif_por='registrar_pago'`. Útil para distinguir fixtures de tests reales en auditoría.

**Descubierto:** 2026-05-27, durante el primer intento fallido de C-5 (fixture quedó en `en_revision` porque el payload no traía `estado_inicial='confirmado'`). Diagnóstico tras leer `pg_get_functiondef('registrar_pago(jsonb)')`. Aplicado en re-ejecución de C-5 y en fixtures de C-3 y C-4.

---

### L-6D-08 — Trigger `trg_log_*_estado` solo dispara en UPDATE OF estado

**Cuándo aplica:** al diseñar tests que validan el doble logging documentado en `CLAUDE.md` (trigger automático + log explícito de función), o al estimar el número esperado de logs en `log_cambios` post-test.

**Detalle:** los triggers de logging automático sobre `pre_reservas`, `reservas` y `pagos` están definidos como `AFTER UPDATE OF estado` (no como `AFTER UPDATE` genérico ni como `AFTER INSERT`). Esto significa:

- INSERT no dispara trigger (los logs en INSERT vienen del bloque explícito de la función, no del trigger).
- UPDATE de cualquier columna que NO sea `estado` no dispara trigger. Ejemplo: el `UPDATE pagos SET id_reserva = ...` que hace `confirmar_reserva` en sección 8 (asociación del pago con la reserva recién creada) NO genera log automático.
- Solo UPDATE de la columna `estado` específicamente dispara el trigger.

**Confirmación empírica en H7:**

- C-1 (solo INSERT de pre-reserva) → 1 log explícito, 0 logs de trigger.
- C-2 (INSERT pre-reserva fixture + UPDATE estado pre-reserva por cancelación + INSERT bloqueo) → 4 logs: 1 explícito de fixture + 1 trigger por UPDATE estado + 1 explícito de cancelación + 1 explícito de bloqueo.
- C-5 (INSERT pre-reserva + INSERT pago + UPDATE estado pre-reserva por pago + UPDATE estado pre-reserva por confirmación + INSERT reserva + UPDATE id_reserva en pago) → 5 logs: 1 explícito pre-reserva + 1 trigger UPDATE pre-reserva (por pago) + 1 explícito pago + 1 trigger UPDATE pre-reserva (por confirmación) + 1 explícito reserva. **El UPDATE de `id_reserva` en pagos NO genera log.**

**Implicación para diseño de tests:** el conteo esperado de logs depende de cuántas transiciones de estado ocurran, no de cuántos UPDATE haya en general. Para estimar logs esperados, contar solamente:

1. Logs explícitos de cada función write involucrada.
2. UPDATE OF estado en tablas con trigger (`pre_reservas`, `reservas`, `pagos`).

**Tablas SIN trigger automático de estado:** `bloqueos` (su columna de estado es `activo` BOOLEAN, no `estado` enum), `huespedes`, `pagos` en UPDATE de campos distintos a `estado`. Cualquier UPDATE en estas tablas o columnas no genera log automático.

**Descubierto:** 2026-05-27, durante validaciones post-test de C-2 (4 logs, no 3 como inicialmente estimado) y C-5 (5 logs, no 6, porque el UPDATE de id_reserva en pagos no disparó trigger).

---

### L-6D-09 — Naming real de tablas y columnas confirmado empíricamente

**Cuándo aplica:** al diseñar queries de snapshot, validación o cleanup; al estimar expected outputs de funciones write; al armar fixtures multipaso.

**Detalle:** algunos nombres reales del schema DEV difieren de la intuición o de cómo aparecen documentados informalmente. Confirmados empíricamente durante H7:

| Objeto | Naming real | Naming asumido erróneamente |
|---|---|---|
| `cabanas.capacidad_max` | columna real | `capacidad_maxima` |
| `bloqueos.activo` | BOOLEAN | `bloqueos.estado` enum |
| Error de `confirmar_reserva` con pre-reserva en estado terminal | `estado_invalido` | `estado_no_confirmable` |
| `huespedes.telefono_normalizado` | preserva el `+` del prefijo internacional | normalización que remueve el `+` |
| Campo del payload de `registrar_pago` para referencia | `referencia_externa` | `referencia` |

**Implicaciones prácticas:**

- Queries de validación de bloqueos deben usar `activo = TRUE` y `CASE WHEN activo THEN 'activo' ELSE 'inactivo' END`, no `estado::text`. La tabla `bloqueos` no sigue el patrón enum de `reservas` / `pre_reservas` / `pagos`.
- Cleanup de huéspedes sintéticos debe filtrar por `telefono = '+549...'` (con `+`), no por `telefono_normalizado` sin `+`.
- Expected del rebote de `confirmar_reserva` cuando la pre-reserva ya está en estado terminal: `error='estado_invalido'`, no `'estado_no_confirmable'` ni `'prereserva_no_confirmable'`.
- Para tests donde necesites `capacidad_max` (validación de excede_capacidad), usar ese nombre real.

**Para verificar nombres reales antes de diseñar queries:**

```sql
-- Columnas de una tabla
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'nombre_tabla'
ORDER BY ordinal_position;

-- Cuerpo real de una función para ver errores que retorna
SELECT pg_get_functiondef('nombre_funcion(jsonb)'::regprocedure);
```

**Origen de la divergencia:** algunas de estas diferencias provienen de la evolución natural del schema (decisiones tomadas durante 6B que no quedaron reflejadas uniformemente en la documentación canónica). Otras son convenciones vigentes observadas en DEV (`telefono_normalizado` preserva el `+`; no consta como decisión explícita documentada, pero es el comportamiento real). El bump documental del canónico a v1.7.2 en H8 deberá revisar estos nombres reales y corregir cualquier divergencia documental confirmada.

**Descubierto:** 2026-05-27, durante diferentes momentos de H7:
- `capacidad_max`: Pieza 2 del snapshot inicial (Franco lo detectó al ajustar la query).
- `bloqueos.activo`: Pieza 4 del snapshot (error `column b.estado does not exist`).
- `estado_invalido`: Pieza 5b del snapshot (lectura de `pg_get_functiondef('confirmar_reserva(jsonb)')`).
- `telefono_normalizado` con `+`: cleanup del primer intento fallido de C-1.
- `referencia_externa`: lectura de `pg_get_functiondef('registrar_pago(jsonb)')` durante diagnóstico de C-5.



## Gotchas del levantamiento de entornos paralelos en Supabase

Estas lecciones surgieron durante la Etapa 7B (Levantamiento del entorno TEST como
proyecto Supabase independiente, paritario y aislado de DEV).
Bitácora detallada: `7B_CIERRE.md`.

### L-7B-01 — `current_database()` no discrimina ambiente entre proyectos Supabase

**Cuándo aplica:** al diseñar smoke tests, scripts de validación o chequeos
defensivos que intenten confirmar contra qué ambiente Supabase se está conectando
una credencial (DEV, TEST, OPS, PROD).

**Síntoma:** una query como `SELECT current_database()` devuelve `postgres` en
todos los proyectos Supabase, independientemente del ambiente. Si el chequeo
asume nombres distintos por ambiente (ej. `vita_delta_dev`, `vita_delta_test`),
el smoke no discrimina y puede dar una falsa sensación de seguridad.

**Por qué pasa:** Supabase crea todos los proyectos con la misma base de datos
de aplicación llamada literalmente `postgres`. El nombre del proyecto Supabase
(visible en el dashboard como `vita-delta-dev`, `vita-delta-test`, etc.) es
metadata del servicio, no del cluster PostgreSQL subyacente. Adentro de la base,
no hay distinción de nombre entre proyectos.

**Discriminadores válidos para chequear ambiente:**

| Discriminador | Cómo se ve | Notas |
|---|---|---|
| `current_user` por pooler | `postgres.<project_ref>` | Trae el project_ref real. Útil pero el `current_user` adentro de la sesión es a veces `postgres` pelado según contexto de pool. |
| `inet_server_addr()` | IP del servidor Supabase | Distintos proyectos → distintas IPs/IPv6. Robusto pero menos legible. |
| **Lectura de datos del seed propio del ambiente** | Ej. `SELECT count(*) FROM cabanas WHERE id_cabana IN (1,2,3,4,5)` | **Lo más robusto:** si el seed de TEST tiene IDs 1-5 y el de DEV tiene 17-21, la query confirma ambiente sin ambigüedad. |

**Patrón recomendado para smoke de ambiente:**

```sql
-- En vez de:
SELECT current_database();  -- siempre "postgres", inservible

-- Usar combinación de discriminadores:
SELECT
  current_user AS usuario,
  inet_server_addr()::text AS server_ip,
  (SELECT array_agg(id_cabana ORDER BY id_cabana)
   FROM cabanas) AS cabana_ids_seed;
```

**Implicación para diseño de smokes:** al diseñar un W0 smoke que verifique
ambiente correctamente, no incluir `current_database()` como "chequeo de
ambiente" — incluirlo solo como confirmación de conectividad. El chequeo real
de ambiente debe usar uno de los discriminadores válidos.

**Descubierto:** 2026-05-28, durante 7B-4. El W0 inicial verificaba
`current_database()` esperando distinguir TEST de DEV; al ejecutarlo contra TEST
devolvió `postgres`, igual que en DEV. Resolución: confirmación de ambiente por
convergencia (credencial al ref de TEST + lectura de los IDs 1-5 del seed
propios de TEST + IDs de secuencia arrancando en 1).

---

### L-7B-02 — "Nacer cerrado" solo aplica al snapshot pre-objetos

**Cuándo aplica:** al crear un nuevo proyecto Supabase con la intención de que
nazca con permisos Data API cerrados (anon/authenticated/service_role sin acceso
a tablas/funciones), y al asumir que mantener "Automatically expose new tables"
destildado es suficiente.

**Síntoma:** el snapshot inicial del proyecto (antes de crear cualquier objeto)
confirma que los roles Data API no tienen grants útiles. Pero después de
ejecutar el schema (CREATE TABLE, CREATE FUNCTION), una verificación de grants
muestra:

- `Dxtm` residual (TRUNCATE/REFERENCES/TRIGGER) sobre tablas/vistas para
  `anon`/`authenticated`/`service_role`. No incluye SELECT/INSERT/UPDATE/DELETE,
  pero aparece.
- `EXECUTE` para `PUBLIC` sobre todas las funciones del proyecto.

**Por qué pasa:** los defaults de PostgreSQL aplican grants automáticos al
*crear* cada objeto, no al snapshot del cluster vacío:

- Para funciones, PostgreSQL aplica `GRANT EXECUTE ... TO PUBLIC` por default
  en cada `CREATE FUNCTION`, independiente de la configuración del proyecto
  Supabase.
- Para tablas/vistas, Supabase aplica `GRANT TRUNCATE, REFERENCES, TRIGGER`
  (`Dxtm`) a `anon`/`authenticated`/`service_role` como default operativo
  post-cambio del 30/05/2026 (no documentado oficialmente pero observado
  empíricamente).

El toggle "Automatically expose new tables to Data API" solo controla la
exposición vía PostgREST/Data API; no controla los grants subyacentes que
PostgreSQL aplica al crear cada objeto.

**Implicación práctica:**

1. **Para funciones nuevas:** ejecutar `REVOKE EXECUTE` explícito como parte
   del workflow de creación. Patrón:

```sql
CREATE OR REPLACE FUNCTION mi_funcion(...) RETURNS ... AS $$ ... $$;
REVOKE EXECUTE ON FUNCTION mi_funcion(...) FROM PUBLIC, anon, authenticated, service_role;
```

   El owner (`postgres`) conserva su capacidad de ejecutar por ownership,
   independiente del REVOKE.

2. **Para tablas/vistas:** decidir explícitamente si el `Dxtm` residual se
   acepta o se revoca. En 7B se decidió aceptarlo (no incluye SELECT/escritura,
   no habilita Data API, revocarlo no cierra riesgo real). Documentar la
   decisión.

3. **Para nuevos proyectos Supabase (OPS, PROD):** no asumir que el snapshot
   inicial de "cerrado" se mantiene tras ejecutar el schema. Re-verificar
   grants después de cada bloque DDL importante.

**Patrón de verificación post-DDL:**

```sql
-- Grants Data API sobre funciones del proyecto (G3)
SELECT g.grantee, g.routine_name, g.privilege_type
FROM information_schema.role_routine_grants g
WHERE g.routine_schema = 'public'
  AND g.grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
  AND g.routine_name IN (<lista de funciones del proyecto>);
-- Si devuelve filas: hay grants que normalizar.
```

**Implicación para n8n por pooler:** el REVOKE EXECUTE a PUBLIC y roles Data
API **no rompe la invocación de funciones desde n8n**, porque n8n entra al
pooler como `postgres` (owner) y ejecuta funciones por ownership, no por grant
EXECUTE. Confirmar con `current_user` del pooler antes de hacer el REVOKE.

**Descubierto:** 2026-05-28, durante 7B-GRANTS. El diagnóstico post-creación de
schema en TEST mostró EXECUTE-PUBLIC sobre las 13 funciones del proyecto, a
pesar de que el snapshot pre-objetos (7B-1) había confirmado que TEST nacía
cerrado. Esto motivó el bloque de normalización (REVOKE EXECUTE) y la regla
operativa D-7B-05.

---

### L-7B-03 — Contar triggers reales con `pg_trigger`, no con `information_schema.triggers`

**Cuándo aplica:** al armar scripts de paridad estructural entre ambientes,
snapshots de schema, o verificaciones de "cantidad de triggers" tras un
deploy/replicación.

**Síntoma:** un script de paridad que compara TEST vs DEV reporta que TEST
tiene **más triggers** que DEV (ej. DEV: 13 triggers, TEST: 18 triggers), a
pesar de haber ejecutado el mismo schema canónico en ambos. La diferencia es
sospechosa porque toda la otra estructura (tablas, vistas, funciones,
constraints) está paritaria 1:1.

**Por qué pasa:** `information_schema.triggers` es una vista del estándar SQL
que **multiplica una fila por cada evento** definido en el trigger. Un trigger
declarado como `AFTER INSERT OR UPDATE OR DELETE` aparece como 3 filas en
`information_schema.triggers`, no como 1.

Si el conteo se hace con `SELECT count(*) FROM information_schema.triggers ...`,
los triggers multi-evento inflan el conteo. La cantidad varía según cómo cada
trigger se definió, no según cuántos triggers reales existen.

**Patrón correcto:** usar `pg_trigger` directamente, que tiene **una fila por
trigger** independiente de la cantidad de eventos:

```sql
SELECT count(*) AS triggers_proyecto
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE NOT t.tgisinternal           -- excluir triggers internos del sistema
  AND n.nspname = 'public'          -- solo schema del proyecto
  AND c.relname NOT LIKE 'pg_%';    -- defensivo, excluir tablas del catálogo
```

**Diferencias clave:**

| Aspecto | `information_schema.triggers` | `pg_trigger` |
|---|---|---|
| Filas por trigger multi-evento | N (una por evento) | 1 |
| Incluye triggers internos del sistema | Sí (sin filtro disponible) | Filtrable con `NOT tgisinternal` |
| Portabilidad SQL estándar | Sí | No (específico de PostgreSQL) |
| Útil para conteos reales | No | Sí |

**Cuándo SÍ usar `information_schema.triggers`:** si necesitás un detalle
desglosado por evento (ej. "qué triggers escuchan INSERT" vs "qué triggers
escuchan UPDATE"). Para conteos agregados, usar `pg_trigger`.

**Implicación para scripts de paridad estructural:** revisar todas las
queries de conteo (triggers, índices, constraints, etc.) y verificar que cada
una use el catálogo correcto. PostgreSQL tiene catálogos paralelos
(`pg_*` vs `information_schema.*`) con semánticas distintas; los `pg_*` suelen
ser más precisos para conteos reales.

**Descubierto:** 2026-05-28, durante 7B-2 Tanda 4A. La verificación post-deploy
de funciones + triggers reportó "2 triggers" cuando se esperaba 1 (el trigger
recién creado `trg_huespedes_set_telefono_normalizado` escucha INSERT y UPDATE,
generando 2 filas en `information_schema.triggers`). Al revisar con
`pg_trigger WHERE NOT tgisinternal`, el conteo real fue 1. Aplicado en
todas las verificaciones posteriores de 7B-2 (Tandas 4B y 5) y en el cierre
de paridad 10/10 vs DEV.
## Lecciones de la validación funcional ampliada — Etapa 7C

Reglas firmes derivadas de la ejecución de la Etapa 7C (validación funcional
ampliada de los 8 workflows `__TEST` sobre TEST, cerrada 2026-05-28). Todas
verificadas empíricamente caso por caso contra el cuerpo SQL real de las
funciones (`6B_SCHEMA_SQL.md v1.7.3`).

### L-7C-01 — Rango invertido en `obtener_disponibilidad_rango` devuelve set vacío, no error

`obtener_disponibilidad_rango` invocada con `fecha_desde > fecha_hasta` (ej.
15-jul → 10-jul) devuelve un set vacío. A través de W1, el wrapper resultante es
`ok:true, total_dias:0, dias:[]` — no es error ni falla el Postgres node. El
workflow degrada con gracia ante rango invertido. Implicación: un consumidor no
puede asumir que un rango inválido rebota con error; debe interpretar
`total_dias:0` como "sin disponibilidad en ese rango", que es el mismo resultado
que un rango válido totalmente ocupado.

**Verificado:** 2026-05-28, caso A-W1-02.

### L-7C-02 — El horizonte de disponibilidad vive en las vistas, no en la función

`obtener_disponibilidad_rango` NO recorta por horizonte: entrega cualquier rango
futuro solicitado (verificado con jun-2027, más de 120 días adelante, `ok:true`
con días normales). El horizonte de 120 días configurable
(`horizonte_disponibilidad_dias`) aplica únicamente a las **vistas**
(`vista_disponibilidad`, `vista_calendario`). Implicación: W1 (vía función) y W7
sobre `vista_disponibilidad` tienen alcances temporales distintos por diseño; no
es inconsistencia.

**Verificado:** 2026-05-28, casos A-W1-03 (función, sin recorte) vs A-W7-03
(vista, 600 filas = 5 cabañas × 120 días).

### L-7C-03 — Fecha mal formada genera error crudo del Postgres node, sin wrapper

Una fecha mal formada (ej. `fecha_in:"no-es-fecha"`) hace fallar el cast
`$1::DATE` en el nodo Postgres de W1 con `invalid input syntax for type date`,
antes de llegar a Build Response. No produce wrapper controlado. Confirma el
pendiente histórico de validación de tipos inválidos no-vacíos: la defensa por
`NULLIF(TRIM())` cubre vacíos/whitespace, no valores no-vacíos mal tipados.

**Verificado:** 2026-05-28, caso A-W1-06.

### L-7C-04 — Pago sobre pre-reserva `convertida` no dispara `prereserva_no_activa`

`registrar_pago` solo marca `warning:'prereserva_no_activa'` cuando la pre-reserva
está en uno de los estados terminales listados explícitamente en la función:
`vencida`, `cancelada_por_cliente`, `cancelada_por_bloqueo`, `conflicto_pendiente`.
El estado `convertida` **no está en esa lista**, por lo que un pago sobre una
pre-reserva convertida se inserta como `en_revision`, `ok:true`, **sin warning** y
sin promover la pre-reserva (el UPDATE de promoción solo aplica a
`pendiente_pago`). La guía operativa de asociar pagos tardíos a `id_reserva` en
ese caso es documental, no enforzada por la función.

**Verificado:** 2026-05-28, caso A-W3-05 (sin transición de estado confirmada en
TR-02, query 5-bis).

### L-7C-05 — `id_cabana:0` en W6 no es bloqueo total; el patrón `0=todas` es exclusivo de W1

En `crear_bloqueo`/W6, el bloqueo total se solicita con `id_cabana:null`. Un
`id_cabana:0` NO se interpreta como total: la función busca la cabaña 0, que no
existe, y rebota con `cabana_no_existe`. El patrón `0=todas` (workaround del
límite de Query Parameters de n8n, ver L-6C-03) aplica **solo a W1**
(`NULLIF($3::BIGINT, 0)`), no a W6. El Build Payload de W6 ya documenta esto y usa
`nv()` para mandar `null` explícito ante vacío/undefined.

**Verificado:** 2026-05-28, caso A-W6-04.

### L-7C-06 — `log_cambios` usa `fecha_hora`; las tablas transaccionales usan `created_at`

Divergencia de naming de columna de timestamp: `log_cambios.fecha_hora`
(`TIMESTAMPTZ NOT NULL DEFAULT NOW()`) vs `pre_reservas.created_at`,
`pagos.created_at`, `bloqueos.created_at`. Una query de auditoría que filtre
`log_cambios` por `created_at` falla con `column "created_at" does not exist`. A
tener presente al escribir queries de auditoría que cruzan logs y tablas
transaccionales.

**Verificado:** 2026-05-28, durante TR-01 (la query 1 falló inicialmente por usar
`created_at` sobre `log_cambios`; corregida a `fecha_hora`).

## Lección del endurecimiento de permisos en DEV — Etapa 7E

### L-7E-01 — El SQL Editor del Dashboard conecta como `postgres`, no por pooler; usar el seed como discriminador de ambiente

Cuando se ejecuta SQL desde el SQL Editor del Dashboard de Supabase, la conexión
entra como `postgres` directo (no por el pooler), por lo que `current_user`
devuelve `postgres` y **no** el patrón `postgres.<project_ref>` que sí aparece
cuando se entra por el pooler (como hace n8n). En consecuencia, `current_user`
no sirve como discriminador de ambiente en ese contexto — es la misma raíz que
L-7B-01 (`current_database()` siempre es `postgres`).

El discriminador fuerte y confiable es la **identidad del seed**: los IDs y
nombres exactos de las 5 cabañas (DEV 17-21, TEST 1-5). En 7E ese veredicto por
`(id_cabana, nombre)` se usó como gate inequívoco en los tres momentos críticos:
el snapshot (A0), el re-gate dentro de la transacción del cambio (Bloque B, con
`RAISE EXCEPTION` que revierte todo si no coincide) y la verificación posterior
(C1).

Corolario operativo: cualquier bloque de cambio en un entorno Supabase debe
gatear por identidad de seed, no por `current_user`/`current_database`, y —si es
destructivo o de endurecimiento— envolver el cambio en `BEGIN/COMMIT` con el
re-gate adentro para que un error de ambiente revierta sin efecto parcial.

**Verificado:** 2026-05-28, Etapa 7E (snapshot A0 con `current_user=postgres`
pese a ser DEV; gate por cabañas 17-21 → `ENTORNO_DEV_OK`).

## Lecciones del levantamiento del entorno OPS — Etapa 8A

### L-8A-01 — El SQL Editor de Supabase ejecuta solo lo seleccionado

Si hay texto resaltado en el panel del SQL Editor, el botón "Run" ejecuta
**únicamente esa porción**, no el script completo. Esto causó varios falsos
"0 filas" / "no rows returned" al inicio del Bloque 4, cuando en realidad la
consulta entera no se había corrido. Regla operativa: para ejecutar un bloque
completo, correr con **nada seleccionado**. Si se quiere correr solo una parte,
seleccionarla a propósito y ser consciente de que el resto no corre.

**Verificado:** 2026-05-29, Bloque 4 (tandas de schema).

### L-8A-02 — El conteo de funciones debe excluir las de extensiones

`btree_gist` instala **188 funciones** en el schema `public`. Un conteo ingenuo
de funciones de `public` da 201 (188 + 13 del proyecto) en vez de las 13 reales.
Para contar solo las funciones propias, excluir las que dependen de una extensión:

```sql
SELECT count(*) FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.prokind='f'
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e');
```

`pg_cron`, en cambio, instala sus funciones en el schema `cron` (no en `public`),
por lo que no contamina el conteo de `public`. El único que mete ruido en `public`
es `btree_gist`.

**Verificado:** 2026-05-29, Tanda 4.5d / P05. El conteo sin filtro daba 201;
con el filtro `deptype='e'`, daba 13 (confirmado también por `funciones_propias`).

### L-8A-03 — Conteo de enums por catálogo, no por sufijo de nombre

Contar enums con `typname LIKE '%_enum'` es frágil (puede colisionar o perder
casos). El conteo correcto filtra por namespace y tipo de catálogo:

```sql
SELECT count(*) FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
WHERE n.nspname='public' AND t.typtype='e';
```

**Verificado:** 2026-05-29, Tanda 4.1 / P02 (4 enums).

### L-8A-04 — "Run without RLS" es esperado y correcto al crear objetos con RLS automático OFF

Al crear tablas/triggers en un proyecto con "Enable automatic RLS" en OFF, el SQL
Editor puede mostrar un aviso tipo "Run without RLS". Es **esperado y correcto** en
este modelo (Opción A, RLS postergado). Aceptar y continuar; no es un error ni una
señal de mala configuración.

**Verificado:** 2026-05-29, Bloque 4.

### L-8A-05 — Verificaciones grandes: evitar `UNION ALL` con comentarios intercalados entre ramas

Una verificación armada como muchas ramas de `SELECT ... UNION ALL SELECT ...` con
comentarios `--` intercalados **entre** las ramas es frágil y puede romper con
`syntax error at or near ")"` según cómo se procesen los saltos de línea. El
patrón robusto es **una sola consulta con subqueries escalares por columna**
(`SELECT (SELECT count(*) ...) AS a, (SELECT count(*) ...) AS b, ...`), que
devuelve una sola fila, es más legible y no depende de la posición de comentarios.

**Verificado:** 2026-05-29, Bloque 9 (la v1 con UNION ALL falló en la línea del
primer comentario intercalado; la v2 con subqueries escalares corrió limpia).

### L-8A-06 — `current_database()` no distingue ambiente; usar datos del seed (consistente con L-7B-01)

Igual que en TEST, `current_database()` devuelve `postgres` en OPS. Para confirmar
que una conexión (ej. la credencial n8n `vita_supabase_ops`) apunta realmente a OPS
y no a DEV/TEST, el discriminador confiable es la **identidad del seed**: leer las
5 cabañas y verificar sus nombres reales (Bamboo, Madre Selva, Arrebol, Guatemala,
Tokio). La verificación de identidad del Bloque 10 se hizo así (convergencia de
datos), no por `current_database()`.

**Verificado:** 2026-05-29, Bloque 10 (query de identidad por la credencial n8n).

### L-8A-07 — OPS nació más cerrado que TEST gracias al switch correcto desde el día cero

A diferencia de TEST/DEV —donde el default de PostgreSQL concedía EXECUTE-PUBLIC y
hubo que revocarlo (D-7B-05, D-7E-01)—, OPS se creó con "Automatically expose new
tables = OFF" desde el inicio. Resultado: las 13 funciones nacieron con `proacl`
NULL (solo owner) y las tablas con solo `Dxtm` inocuo para roles Data API, sin
necesidad de remediación. El REVOKE EXECUTE se aplicó igual como barrera explícita
(Opción B), pero fue idempotente (no había nada que quitar).

**Corolario para PROD:** crear el proyecto con los mismos switches (Data API ON,
exponer tablas nuevas OFF, RLS automático OFF) para nacer cerrado desde el día cero,
en vez de endurecer después.

**Verificado:** 2026-05-29, Bloque 6 (diagnóstico: 0 EXECUTE a Data API, 0 grants
RW a roles Data API antes de cualquier REVOKE).

## Lecciones de la capa de carga interna — Etapa 8B

### L-8B-01 — "TEXT libre" no significa sin restricción: verificar CHECK constraints
Que una columna sea TEXT (no enum) no implica que acepte cualquier valor. En OPS,
`canal_origen`, `canal_pago_esperado`, `medio_pago` y `tipo` son TEXT pero con
`CHECK` que restringe los valores permitidos. Asumir "TEXT libre" llevó a un primer
mapa de desplegables con valores (`directo`, `referido`, `airbnb`, `booking`,
`otro`, `transferencia`, `mercadopago`) que el CHECK habría rechazado en runtime.

**Implicación:** antes de fijar valores que se persisten en columnas TEXT, leer los
`CHECK` reales con `pg_get_constraintdef` sobre `pg_constraint`. Los valores válidos
de `canal_origen` en `pre_reservas` son `whatsapp/instagram/web/manual`; los de
`canal_pago_esperado`/`medio_pago` son `transferencia_bancaria/transferencia_mp/
mp_link/cripto/efectivo`. El dato operativo fino que no entra en el CHECK (Airbnb,
Booking, etc.) se preserva en un campo libre (`notas`).

**Verificado:** 2026-05-30, verificación read-only de CHECK contra OPS.

### L-8B-02 — `pre_reservas.canal_origen` es más restrictivo que `reservas.canal_origen`
El CHECK de `reservas.canal_origen` acepta `airbnb` y `booking`, pero el de
`pre_reservas.canal_origen` NO. Como la cadena de carga crea primero la pre-reserva
y `confirmar_reserva` copia ese valor a `reservas`, **manda el CHECK más restrictivo
(el de `pre_reservas`)**. Persistir `airbnb` habría rebotado en el paso 1 aunque
`reservas` lo aceptara.

**Implicación:** cuando un valor atraviesa varias tablas en cadena, el conjunto de
valores válidos es la intersección de todos los CHECK del camino, no el de la tabla
final.

**Verificado:** 2026-05-30, CHECK de ambas tablas leídos contra OPS.

### L-8B-03 — `ok:true` de `registrar_pago` no garantiza pago `confirmado`
Si la pre-reserva está en estado terminal, `registrar_pago` registra el pago
forzado a `en_revision`, con `warning='prereserva_no_activa'`, y **devuelve
`ok:true` igual**. Un encadenado que verifique solo `ok` puede avanzar creyendo que
hay un pago confirmado cuando no lo hay.

**Implicación:** tras `registrar_pago`, en un flujo de camino estricto, verificar
`ok===true && estado==='confirmado' && sin warning`. No basta `ok`.

**Verificado:** 2026-05-30, cuerpo real de `registrar_pago` (`pg_get_functiondef`) +
test en TEST (caso anómalo).

### L-8B-04 — La constraint de `idempotency_key` es PARCIAL (solo estados activos)
`uq_prereservas_idempotency_activa` es un índice único parcial con
`WHERE idempotency_key IS NOT NULL AND estado IN ('pendiente_pago','pago_en_revision')`.
Por eso una pre-reserva cancelada/vencida sale del subconjunto único, y una recarga
legítima con la misma cabaña/fechas/contacto no choca (no da `unique_violation`).
Esto habilitó usar una `idempotency_key` determinística por datos sin temor a falsos
bloqueos tras cancelación.

**Implicación:** antes de diseñar una key determinística, verificar si la unicidad
que la respalda es total o parcial — decide si la fórmula es viable.

**Verificado:** 2026-05-30, `pg_indexes` + `pg_index.indpred` contra OPS.

### L-8B-05 — n8n Form Trigger: campo Number vacío puede llegar como `0`, no como `""`
El primer test de la seña falló ("La seña debe ser mayor a 0") porque un campo
Number dejado vacío llegó como `0`/`"0"`, no como cadena vacía, y la validación
`>0` lo rechazó. Para una semántica "vacío → default", tratar `0`, `""`, `null` y
`undefined` todos como "vacío" leyendo el valor crudo (sin pasarlo por un normalizador
que convierta `"0"` en un valor truthy), y validar `>0` solo para valores genuinos.

**Implicación:** en validaciones de campos Number de n8n, no asumir que vacío = `""`;
contemplar `0` explícitamente según la semántica deseada.

**Verificado:** 2026-05-30, primer happy path en TEST (bug) + corrección v4.

### L-8B-06 — Form Ending es un nodo aparte (`form` operation `completion`), no una propiedad del trigger
Para mostrar un resultado final al operador con `Respond When = Workflow Finishes`,
el patrón robusto es un nodo `n8n-nodes-base.form` con `operation: "completion"` al
final de cada rama, no una propiedad del Form Trigger. Con ramas mutuamente
excluyentes por IF, se muestra el Form Ending de la rama ejecutada. La lógica de
decisión del mensaje puede centralizarse en un Code node previo (Build Response) que
emite `completionTitle`/`completionMessage`, y el Form Ending solo los renderiza.

**Verificado:** 2026-05-30, documentación oficial de n8n + workflow validado en TEST.

### L-8B-07 — Enriquecer el contexto paso a paso en cadenas multi-función de n8n
En un encadenado donde cada función devuelve IDs distintos (`crear_prereserva` da
`id_pre_reserva`, `registrar_pago` da `id_pago`, `confirmar_reserva` da `id_reserva`),
no depender de que cada paso reciba todos los IDs en su respuesta. Mantener un objeto
`ctx` que se va enriqueciendo (clonado entre nodos para no mutar referencias) y del
que cada Build Payload lee lo que necesita. Evita el bug de que un paso posterior se
quede sin un ID que su función de origen no devolvió.

**Verificado:** 2026-05-30, diseño v2 del workflow (corrección de bug detectado en v1).

## Lecciones de los calendarios visuales — Etapa 8C

### L-8C-01 — n8n auto-empareja credenciales por nombre al crear/importar y puede caer en el entorno equivocado
Al crear o importar un workflow vía SDK, n8n intenta auto-asignar credenciales por
nombre y puede asignar el entorno equivocado o una credencial ajena. En 8C ocurrió
repetidamente: los nodos Postgres quedaron auto-asignados a `vita_supabase_dev`
(entorno equivocado) en los tres workflows, y en el de limpieza el Webhook quedó con
la credencial Basic Auth del formulario 8B (`Formulario-reservas`) en vez de una
propia.

**Implicación:** verificar y corregir SIEMPRE las credenciales asignadas tras
crear/importar un workflow, antes de cualquier ejecución. Nunca asumir que el
auto-emparejamiento puso la correcta. Especialmente crítico cuando hay varios
entornos (DEV/TEST/OPS) con credenciales de nombre parecido.

**Verificado:** 2026-05-31 / 2026-06-01, creación de los 3 workflows de 8C vía SDK.

### L-8C-02 — Las fechas de Postgres pueden llegar como timestamp completo, no como `YYYY-MM-DD`
En el workflow de limpieza, las fechas llegaron del nodo Postgres como timestamp
completo (`2026-06-01T00:00:00.000Z`), no como fecha simple. Una función que esperaba
`YYYY-MM-DD` y hacía `split('-')` produjo encabezados rotos (`undefined ...T00:00:00.000Z/06`).

**Implicación:** normalizar toda fecha a `YYYY-MM-DD` con `String(v).slice(0,10)`
antes de comparar, parsear o etiquetar, en cualquier nodo Code que reciba fechas de
Postgres. No asumir el formato de salida. (El operativo no lo manifestó porque su uso
de fechas toleraba el formato, pero el riesgo era latente.)

**Verificado:** 2026-06-01, bug observado y corregido en el render de limpieza.

### L-8C-03 — Para grilla arbitraria en Google Sheets desde n8n, usar HTTP a la API REST, no el nodo nativo
El nodo nativo `n8n-nodes-base.googleSheets` (v4.7) está orientado a datos tabulares
con columnas nombradas (ResourceMapper) y no vuelca bien una grilla arbitraria con
celdas multilínea y encabezados intercalados. Para eso conviene un nodo HTTP Request
contra la API REST de Sheets (`values:update`/`values:clear`), que acepta una matriz
cruda desde un rango, con `authentication: predefinedCredentialType` +
`nodeCredentialType: googleSheetsOAuth2Api` (reutiliza la credencial OAuth existente).

**Implicación:** elegir el mecanismo según la forma del dato — nodo nativo para filas
homogéneas con columnas fijas; HTTP a la API REST para grillas/matrices arbitrarias.

**Verificado:** 2026-06-01, construcción del Sheet de resguardo (Bloque 3 de 8C).

### L-8C-04 — Los nodos HTTP Request no reciben auto-asignación de credencial al crear vía SDK
Complemento de L-8C-01: al crear un workflow vía SDK, n8n informa explícitamente que
los nodos HTTP Request fueron "skipped during credential auto-assignment" y que sus
credenciales deben configurarse manualmente. Hay que asignarles la credencial a mano
siempre (en 8C, la credencial OAuth de Google Sheets a los dos nodos HTTP del resguardo).

**Verificado:** 2026-06-01, creación del workflow de resguardo y del test de escritura.

### L-8C-05 — Validar el supuesto técnico más riesgoso con un workflow mínimo antes de construir el completo
Antes de construir el workflow de resguardo (8 nodos), se creó un workflow mínimo de
un solo nodo HTTP que escribió una celda de prueba en el Sheet, para validar el único
supuesto incierto: que la credencial OAuth tuviera permiso de escritura sobre el Sheet.
Confirmado eso, el workflow completo se construyó con confianza. Si hubiera fallado por
permisos, se habría detectado sin haber invertido en los 8 nodos.

**Implicación:** ante un supuesto técnico riesgoso y aislable (permisos, conectividad,
formato de respuesta de una API externa), construir primero una prueba mínima que
valide solo ese supuesto, antes de invertir en el artefacto completo.

**Verificado:** 2026-06-01, test `vita_w8c_test_escritura_sheet__TEST` previo al resguardo.

## Lecciones de la capa de bloqueos — Etapa 8D

### L-8D-01 — El nodo Postgres devuelve el resultado de una función envuelto en la columna
Cuando un nodo Postgres ejecuta `SELECT mi_funcion(...) AS resultado`, el JSON que devuelve
la función llega **dentro de la columna** (`item.resultado`), no en la raíz del item. Un
nodo Code posterior que lea `item.ok` no encuentra nada y, si usa esa ausencia para
detectar "error técnico", clasifica un éxito como fallo.

**Síntoma real en 8D:** el formulario mostraba "Problema técnico" aunque el bloqueo se
creaba bien en la base (la función devolvía `ok: true`). El bug estaba en el nodo Normalize,
que leía `item.ok` en vez de `item.resultado.ok`.

**Implicación:** al consumir el output de un nodo Postgres que llama una función vía
`SELECT funcion(...) AS alias`, desenvolver la columna antes de leer sus campos:
`const item = raw && raw.alias !== undefined ? raw.alias : raw;`. La base puede estar
funcionando perfecto aunque la UI muestre error — verificar el OUTPUT del nodo Postgres
(no solo el mensaje final) antes de concluir que "el motor falló".

**Verificado:** 2026-06-04, bug observado y corregido en el Normalize de 8D.

### L-8D-02 — Pasar JSON a una función SQL: interpolación funciona, parametrizado es más robusto
Para pasar un payload JSON a una función desde el nodo Postgres, la interpolación
`'{{ JSON.stringify($json.payload) }}'::jsonb` funciona en la mayoría de los casos, pero la
query parametrizada (`SELECT funcion($1::jsonb)` + Query Parameters con
`{{ JSON.stringify($json.payload) }}`) es más robusta ante comillas simples y caracteres
especiales en el contenido (ej. una descripción con apóstrofo). Recomendada cuando el
payload incluye texto libre.

**Nota:** la query interpolada NO se puede probar pegándola en el SQL Editor de Supabase
(las `{{ }}` son sintaxis de n8n, no SQL); la prueba real es ejecutar el workflow desde n8n.

**Verificado:** 2026-06-04, nodo `PG: crear_bloqueo` de 8D.

### L-8D-03 — Al promover a OPS, revisar marcadores de entorno embebidos en el código (no solo credenciales)
Al duplicar un workflow para OPS, además de cambiar la credencial Postgres hay que revisar:
(a) marcadores de entorno embebidos en nodos Code (en 8D, la constante `TEST_OPS = 'test'`
que arma el `source_event` — si no se cambia a `'ops'`, los registros reales quedan
etiquetados "test"); (b) el `path` del trigger (para no colisionar con el workflow de TEST
en la misma instancia); (c) la Basic Auth (propia de OPS).

**Consecuencia de olvidar el marcador:** no rompe nada funcional (el bloqueo se crea bien),
pero ensucia la trazabilidad (un registro real con `source_event` "test"). Corregirlo
después implica escritura directa a OPS y el `log_cambios` asociado queda con la etiqueta
vieja igual, así que conviene revisarlo ANTES de la primera ejecución en OPS.

**Verificado:** 2026-06-04, promoción de 8D a OPS (un bloqueo temprano quedó con marcador
'test', aceptado como está; los siguientes correctos).

## Lecciones de la alerta por reserva próxima — Sub-etapa 8C-bis

### L-8Cbis-01 — Execute Workflow emite el output del sub-workflow, no el item original
Cuando un nodo Execute Workflow (Call) se conecta en serie hacia un nodo posterior, ese
nodo recibe **el output del sub-workflow invocado**, no el item que venía fluyendo en el
workflow padre. En 8C-bis, conectar el Call hacia `Build Response` habría hecho que la
pantalla de confirmación del operador dependiera del resultado de la notificación (o se
rompiera si el sub-workflow no devolvía la forma esperada). Solución: **rama lateral** — el
nodo previo (PUNTO EXTENSION) alimenta `Build Response` y el Call en paralelo desde la
misma salida, y el Call queda como hoja sin salida. Así la respuesta al operador usa el
item original y es indiferente a lo que pase en el aviso.

**Verificado:** validación end-to-end en TEST con el Call pineado para fallar →
`Build Response` igual emitió "✅ Reserva confirmada" con los datos correctos.

### L-8Cbis-02 — Copy-paste de mails puede arrastrar un carácter de tabulación invisible
Al pegar una dirección de correo dentro de un array en un nodo Code, quedó un `\t`
(tabulación) pegado al inicio del string (`'\trodrigo...@gmail.com'`). El `.join(',')`
posterior produjo un destinatario con tabulación al frente, que un servidor SMTP rechaza
silenciosamente. No es visible en la UI a simple vista. **Regla:** al adaptar
destinatarios/strings sensibles entre entornos, inspeccionar el JSON real del nodo (no solo
la vista del editor) para detectar whitespace espurio; o aplicar `.trim()` defensivo a cada
dirección antes de usarla.

**Verificado:** 2026-06-04, detectado por lectura del JSON del workflow OPS y corregido
antes de la primera ejecución real.

### L-8Cbis-03 — En n8n, un cambio guardado no entra en producción hasta "Publish"
Editar y guardar un workflow deja el cambio en la versión de trabajo (draft), pero la
versión que se ejecuta en producción es la **publicada** (`activeVersion`). Tras cargar el
mail real de Jennifer y guardar, la `activeVersion` todavía tenía el destinatario anterior;
una reserva real habría notificado al destinatario viejo hasta pulsar "Publish". **Regla:**
después de un cambio que debe impactar producción, confirmar que la `activeVersion` refleja
el cambio (o re-leer el workflow por MCP), no solo que está guardado.

**Verificado:** 2026-06-04, diferencia draft vs. `activeVersion` detectada por lectura del
workflow OPS; se confirmó la publicación antes del cierre.
