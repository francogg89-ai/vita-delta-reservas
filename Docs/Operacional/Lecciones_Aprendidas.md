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

## Sobre Display de Resultados en Supabase

### SQL Editor muestra solo el último SELECT
Cuando hay múltiples statements separados por `;`, solo se ve el resultado
del último SELECT. Para ver varios resultados: usar `UNION ALL` con columna
identificadora (`test`, `momento`, `caso`).

*Origen: Bloque 19 / 2026-05-24*

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
\`\`\`sql
UPDATE cabanas SET orden_limpieza = 3 WHERE nombre = 'Bamboo';
UPDATE cabanas SET orden_limpieza = 1 WHERE nombre = 'Tokio';
\`\`\`

## Bug crítico de Supabase Dashboard con CREATE OR REPLACE FUNCTION

Cuando se ejecuta un `CREATE OR REPLACE FUNCTION` en el SQL Editor de Supabase
con una función PL/pgSQL que contiene variables locales con prefijo `v_`,
Supabase puede detectar incorrectamente esas variables como **nombres de tabla**
e intentar agregar automáticamente al final del SQL:

\`\`\`sql
ALTER TABLE v_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE v_existente ENABLE ROW LEVEL SECURITY;
-- source: dashboard
\`\`\`

Esto trunca el SQL original a mitad y causa errores tipo:
`ERROR 42601: unterminated dollar-quoted string`

### Workaround validado

Usar `DROP FUNCTION` seguido de `CREATE FUNCTION` (sin `OR REPLACE`) en runs
separados:

\`\`\`sql
-- Paso 1: DROP en su propio Run
DROP FUNCTION IF EXISTS mi_funcion(jsonb);
\`\`\`

\`\`\`sql
-- Paso 2: CREATE en su propio Run
CREATE FUNCTION mi_funcion(payload JSONB) RETURNS JSONB ... AS $$
DECLARE
  v_config JSONB;  -- ← Supabase ya no lo confunde con tabla
  ...
\`\`\`

Supabase no activa el feature de auto-RLS cuando hay un DROP previo, porque
entiende que estás reemplazando una función existente.

Origen: Hotfix v1.7 (Fase 3, post-cierre), reemplazo de `crear_prereserva`
con la regla de `hora_checkout_domingo`.

Bloque para Lecciones_Aprendidas.md — Gotchas de la integración n8n ↔ Supabase

Cómo usar este archivo: copiar el bloque de abajo y agregarlo a Docs/Operacional/Lecciones_Aprendidas.md respetando el formato de las entradas previas. Si el archivo no tiene una sección "n8n ↔ Supabase", crearla en un lugar lógico.


Bloque a agregar
markdown## Integración n8n cloud ↔ Supabase

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

Notas para el mantenedor del archivo

Las lecciones están numeradas con prefijo L-6C-NN para distinguirlas de lecciones de etapas anteriores (Etapa 6B usaría L-6B-NN).
Si Lecciones_Aprendidas.md ya tiene su propio sistema de numeración o categorización, adaptar los headers manteniendo el contenido.
L-6C-01 a L-6C-04 son gotchas accionables (problema → solución). L-6C-05 es informativa (no hay un bug que solucionar, solo entender el comportamiento).
Los IDs (L-6C-01, etc.) son útiles para referenciar desde código o bitácora más adelante (ej. en comentarios del JSON del workflow: // Workaround L-6C-03).

Generado como parte del cierre de W1 — 2026-05-25.