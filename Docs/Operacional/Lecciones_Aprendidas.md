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