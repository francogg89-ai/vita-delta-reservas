# Plan de Cierre 6B — Alineación de DEV con v1.7.1

# Mini-pendiente: actualizar `obtener_disponibilidad_rango()`

**Versión:** 1.1
**Fecha:** Mayo 2026
**Estado:** Aprobado para ejecución de Pasos 0-3 (read-only). Paso 4 y siguientes a confirmar con Franco después de la lectura de resultados.
**Tipo:** Cierre final de Etapa 6B (no inicio de 6C).
**Entorno objetivo:** Supabase DEV.
**Documento base:** `6B_SCHEMA_SQL.md v1.7.1`, Sección Bloque 12.

---

## CHANGELOG

### v1.1 — ajustes de seguridad pre-ejecución

Tres ajustes pedidos por Franco. Cero cambios en el SQL canónico de la función.

1. **Paso 2:** agregada query 2.1.b con `pg_get_viewdef` para detectar vistas que mencionan la función. Razón: las vistas dependen de funciones a través de `pg_rewrite`, no de forma directa en `pg_depend`, por lo que la query original (renombrada a 2.1.a) podía no listarlas con claridad. Nota técnica agregada en Sección 2 y en el Paso 2.
2. **Fallback Paso F-2 (nuevo):** verificación previa de si otras vistas dependen de `vista_disponibilidad`. Antes de recrear la vista temporalmente, hay que confirmar que no rompemos algo aguas abajo. Reenumeración de los pasos del fallback (los antiguos F-2 a F-5 ahora son F-3 a F-6, y la verificación final pasa a F-7).
3. **`DROP VIEW vista_disponibilidad` directo desclasificado como opción del fallback.** Se documenta como "último recurso desaconsejado" en una sección separada con advertencias explícitas. El procedimiento normal del fallback preserva siempre la vista en estructura.

### v1.0 — borrador inicial

Estructura completa, contexto, análisis de dependencias, SQL canónico v1.7.1, procedimiento paso a paso, fallback, rollback, criterios de éxito y freno.

---

## 0. RESUMEN EJECUTIVO

DEV está alineado con `6B_SCHEMA_SQL.md v1.7` (incluye hotfix de `crear_prereserva` con D47 y la clave `hora_checkout_domingo` en `configuracion_general`). Falta un último ajuste para alinear con v1.7.1: actualizar `obtener_disponibilidad_rango()` para que `hora_checkout_base` devuelva `16:00` los domingos (D47 a nivel de lectura).

Una vez aplicado este cambio, DEV queda 100% alineado con v1.7.1 y se puede arrancar 6C limpio con W0.

**Cambio puntual:** 1 línea en el cuerpo de la función.

**Antes:**

```sql
TIME '10:00' AS hora_checkout_base
```

**Después:**

```sql
CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '16:00' ELSE TIME '10:00' END AS hora_checkout_base
```

Todo lo demás (firma, columnas, lógica) se mantiene idéntico.

---

## 1. CONTEXTO

### Por qué este cambio

- D47 (regla operativa de Vita Delta): los huéspedes que se van un domingo tienen check-out a las 16:00 por la última lancha colectiva.
- `crear_prereserva()` ya aplica D47 desde v1.7 — las pre-reservas con `fecha_out` domingo se crean con `hora_checkout = 16:00`.
- Pero `obtener_disponibilidad_rango()` todavía devuelve `10:00` para todos los días, incluyendo domingos.
- Resultado: hay inconsistencia entre lo que la base de datos calcula (16:00) y lo que las vistas y W1 reportarán (10:00).
- W1 va a leer disponibilidad y el bot futuro va a usar ese dato. Hay que cerrarlo antes de W1.

### Por qué tratarlo como cierre de 6B

- Es alineación de schema/función SQL en DEV, no reescritura de workflows n8n.
- Lo declaró pendiente el propio cierre de 6B (`ESTADO_VITA_DELTA_ACTUAL.md`).
- Hasta cerrarlo, "DEV está 100% alineado con v1.7.1" no es cierto.

---

## 2. ANÁLISIS DE DEPENDENCIAS

Antes de tocar la función, hay que saber qué objetos en DEV dependen de ella. La regla operativa Supabase es: **no usar `DROP ... CASCADE`** sin saber qué se rompe (`DECISIONES_NO_REABRIR.md` + `Lecciones_Aprendidas.md`).

### Dependencias conocidas según el schema canónico

| Objeto dependiente | Cómo depende | Riesgo si se rompe |
|---|---|---|
| `vista_disponibilidad` | `SELECT * FROM obtener_disponibilidad_rango(CURRENT_DATE, (CURRENT_DATE + 60)::DATE, NULL)` | Alto. Es la vista de lectura principal. |
| (potencial) workflows n8n que consulten la función | Aún ninguno apunta a DEV. | Bajo en este momento. |
| (potencial) callers ad-hoc desde SQL Editor | Bajo. Solo afecta sesiones interactivas. | Bajo. |

### Verificación de dependencias antes de tocar

Antes de ejecutar el cambio, correr en Supabase SQL Editor las dos queries del Paso 2 del procedimiento (Sección 5):

- **2.1.a** — `pg_depend` para detectar dependencias estructurales (funciones, triggers).
- **2.1.b** — `pg_get_viewdef` para detectar vistas que mencionan la función.

**Nota técnica:** las vistas dependen de funciones a través de `pg_rewrite` (regla `_RETURN`), no de forma directa en `pg_depend`. Por eso la verificación con `pg_get_viewdef` es complementaria y necesaria.

**Esperado:** `vista_disponibilidad` debe aparecer en 2.1.b como vista que usa la función. Si aparece algo más que no figura en el schema canónico, investigar antes de avanzar.

---

## 3. ESTRATEGIA: CAMINO PRINCIPAL CON FALLBACK

### Camino principal — `CREATE OR REPLACE FUNCTION`

Es la opción natural y la más segura. `CREATE OR REPLACE` no destruye dependencias: reemplaza el cuerpo de la función preservando los objetos que dependen de ella.

**Condición de uso:** la firma de la función no cambia (mismos parámetros, mismas columnas de retorno, mismos tipos). En este caso, la firma se mantiene 100% — solo cambia una expresión interna.

### Camino de fallback — si Supabase Dashboard interfiere

El bug conocido (`Lecciones_Aprendidas.md`) es que Supabase Dashboard a veces inyecta `ALTER TABLE ENABLE RLS` sobre variables locales con prefijo `v_`, truncando el SQL.

**Importante:** el cuerpo de `obtener_disponibilidad_rango()` **no usa variables locales con prefijo `v_`** (es una función con `RETURN QUERY` directa, sin `DECLARE`). El bug es **menos probable** que en `crear_prereserva()`. Pero conviene tener el fallback listo igual.

Si `CREATE OR REPLACE` falla por la interferencia del Dashboard:

- **NO usar `DROP FUNCTION ... CASCADE`.** Eliminaría `vista_disponibilidad` silenciosamente.
- **NO usar `DROP FUNCTION` simple sin CASCADE.** PostgreSQL lo va a rechazar con error de dependencia (lo cual es bueno: nos avisa).
- Aplicar el patrón: salvar SQL de las dependencias → DROP de la función → recrear función → recrear dependencias.

Detalle del fallback en Sección 6.

---

## 4. SQL CANÓNICO A APLICAR (v1.7.1)

Bloque completo. Esto es lo que la función debe quedar después del cambio. Está tomado del schema canónico Bloque 12 con la única diferencia respecto a v1.7: la línea de `hora_checkout_base`.

```sql
CREATE OR REPLACE FUNCTION obtener_disponibilidad_rango(
  p_fecha_desde   DATE,
  p_fecha_hasta   DATE,
  p_id_cabana     BIGINT DEFAULT NULL
)
RETURNS TABLE (
  id_cabana              BIGINT,
  fecha                  DATE,
  estado                 TEXT,
  tipo_dia               TEXT,
  temporada              TEXT,
  hora_checkin_base      TIME,
  hora_checkout_base     TIME,
  id_reserva_activa      BIGINT,
  id_prereserva_activa   BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH dias AS (
    SELECT generate_series(p_fecha_desde, p_fecha_hasta - INTERVAL '1 day', '1 day')::DATE AS d
  ),
  cabanas_activas AS (
    SELECT c.id_cabana, c.nombre
    FROM cabanas c
    WHERE c.activa = TRUE
      AND (p_id_cabana IS NULL OR c.id_cabana = p_id_cabana)
  ),
  matriz AS (
    SELECT ca.id_cabana, d.d AS fecha
    FROM cabanas_activas ca
    CROSS JOIN dias d
  )
  SELECT
    m.id_cabana,
    m.fecha,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM bloqueos b
        WHERE b.activo = TRUE
          AND (b.id_cabana = m.id_cabana OR b.id_cabana IS NULL)
          AND m.fecha >= b.fecha_desde
          AND m.fecha < b.fecha_hasta
      ) THEN 'bloqueada'
      WHEN EXISTS (
        SELECT 1 FROM reservas r
        WHERE r.id_cabana = m.id_cabana
          AND r.estado IN ('confirmada', 'activa')
          AND m.fecha >= r.fecha_checkin
          AND m.fecha < r.fecha_checkout
      ) THEN 'ocupada'
      WHEN EXISTS (
        SELECT 1 FROM pre_reservas pr
        WHERE pr.id_cabana = m.id_cabana
          AND (
            (pr.estado = 'pendiente_pago' AND pr.expira_en > NOW())
            OR pr.estado = 'pago_en_revision'
          )
          AND m.fecha >= pr.fecha_in
          AND m.fecha < pr.fecha_out
      ) THEN 'ocupada'
      WHEN EXISTS (
        SELECT 1 FROM reservas r
        WHERE r.id_cabana = m.id_cabana
          AND r.estado IN ('confirmada', 'activa', 'completada')
          AND r.fecha_checkout = m.fecha
      ) THEN 'checkout_disponible'
      ELSE 'disponible'
    END AS estado,
    CASE
      WHEN EXISTS (SELECT 1 FROM feriados f WHERE f.fecha = m.fecha AND f.activo = TRUE) THEN 'feriado'
      WHEN EXTRACT(DOW FROM m.fecha) IN (5, 6) THEN 'finde'
      ELSE 'semana'
    END AS tipo_dia,
    (
      SELECT t.nombre FROM temporadas t
      WHERE t.activa = TRUE
        AND m.fecha BETWEEN t.fecha_desde AND t.fecha_hasta
      LIMIT 1
    ) AS temporada,
    -- Hora base (sin escalonamiento — el escalonamiento lo aplica n8n)
    CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '18:00' ELSE TIME '13:00' END AS hora_checkin_base,
    -- v1.7.1 (D47): checkout dominical 16:00 alineado con la regla de crear_prereserva
    CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '16:00' ELSE TIME '10:00' END AS hora_checkout_base,
    (
      SELECT r.id_reserva FROM reservas r
      WHERE r.id_cabana = m.id_cabana
        AND r.estado IN ('confirmada', 'activa')
        AND m.fecha >= r.fecha_checkin
        AND m.fecha < r.fecha_checkout
      LIMIT 1
    ) AS id_reserva_activa,
    (
      SELECT pr.id_pre_reserva FROM pre_reservas pr
      WHERE pr.id_cabana = m.id_cabana
        AND (
          (pr.estado = 'pendiente_pago' AND pr.expira_en > NOW())
          OR pr.estado = 'pago_en_revision'
        )
        AND m.fecha >= pr.fecha_in
        AND m.fecha < pr.fecha_out
      LIMIT 1
    ) AS id_prereserva_activa
  FROM matriz m;
END;
$$;
```

> **Verificación de consistencia con el schema canónico:** este SQL debe ser idéntico a `6B_SCHEMA_SQL.md v1.7.1`, Bloque 12. Si encontrás cualquier diferencia distinta a la línea marcada como `v1.7.1 (D47)`, pará y comparamos antes de ejecutar.

---

## 5. PROCEDIMIENTO PASO A PASO

### Paso 0 — Pre-condiciones

- [ ] Verificar que estás en el proyecto Supabase **DEV**, no TEST ni PROD.
- [ ] Verificar que no hay nadie más operando contra DEV en este momento (chequeo informal: no es producción, basta con avisar).
- [ ] Tener este documento abierto.
- [ ] Tener `6B_SCHEMA_SQL.md v1.7.1` accesible para comparar.
- [ ] Tener `Docs/Bitacora/6B_EJECUCION_DEV.md` accesible para bitacorear.

### Paso 1 — Snapshot defensivo de la función actual

Antes de tocar nada, guardar el SQL de la función actual en DEV (v1.7) por si hay que revertir:

```sql
SELECT pg_get_functiondef(p.oid) AS funcion_actual
FROM pg_proc p
WHERE p.proname = 'obtener_disponibilidad_rango';
```

**Acción:** copiar el resultado completo y guardarlo en local (por ejemplo, en `Docs/Bitacora/snapshots/obtener_disponibilidad_rango_v1.7_pre_actualizacion.sql`). No commitear secrets ni datos reales, solo el SQL de la función.

### Paso 2 — Snapshot de dependencias

```sql
-- 2.1.a Listar dependientes vía pg_depend (puede no mostrar vistas con claridad)
SELECT DISTINCT
  d.objid::regclass AS objeto_dependiente,
  d.deptype         AS tipo
FROM pg_depend d
JOIN pg_proc p ON p.oid = d.refobjid
WHERE p.proname = 'obtener_disponibilidad_rango'
  AND d.deptype IN ('n', 'a');
```

**Nota técnica:** las vistas en PostgreSQL dependen de funciones a través de `pg_rewrite` (la regla `_RETURN` de la vista), no directamente. Por eso `pg_depend` puede no listarlas de forma evidente cuando el `refobjid` apunta a la función. Por seguridad, complementar con la verificación directa de 2.1.b.

```sql
-- 2.1.b Verificación directa: buscar vistas cuyo SQL menciona la función
SELECT
  c.relname                                                AS vista,
  pg_get_viewdef(c.oid, true) ILIKE '%obtener_disponibilidad_rango%' AS usa_funcion
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'v'  -- v = view
  AND n.nspname = 'public'
ORDER BY c.relname;
```

**Acción:** anotar en bitácora la lista de vistas con `usa_funcion = true`. Como mínimo debe figurar `vista_disponibilidad`. Si aparece alguna otra que no figura en el schema canónico (Bloque 20), investigar antes de avanzar.

```sql
-- 2.2 Snapshot del SQL de vista_disponibilidad por si hay que recrearla
SELECT pg_get_viewdef('vista_disponibilidad'::regclass, true) AS sql_vista_disponibilidad;
```

**Acción:** copiar el resultado y guardarlo en local. Solo usar si entramos al fallback.

### Paso 3 — Baseline funcional (cómo se comporta hoy)

```sql
-- Antes del cambio: el checkout dominical debería dar 10:00 (estado actual DEV)
SELECT fecha,
       EXTRACT(DOW FROM fecha) AS dow,
       hora_checkin_base,
       hora_checkout_base
FROM obtener_disponibilidad_rango(
  '2026-06-07'::DATE,  -- domingo
  '2026-06-09'::DATE,  -- exclusive
  17                   -- Bamboo, primera cabaña real del seed
)
ORDER BY fecha;
```

**Esperado antes del cambio:**

| fecha | dow | hora_checkin_base | hora_checkout_base |
|---|---|---|---|
| 2026-06-07 | 0 (domingo) | 18:00 | **10:00** ← inconsistencia D47 |
| 2026-06-08 | 1 (lunes) | 13:00 | 10:00 |

**Acción:** confirmar visualmente que el estado actual es ese. Si los valores ya están en `16:00` los domingos, el cambio ya está aplicado y no hay nada que hacer (pero entonces hay un problema de documentación: revisar).

### Paso 4 — Aplicar el cambio (camino principal)

Pegar en el SQL Editor el bloque SQL completo de la Sección 4 de este documento.

Ejecutar como una sola transacción implícita (un Run del SQL Editor).

**Comportamiento esperado:**
- Sin errores.
- Mensaje "CREATE FUNCTION" o equivalente.
- `vista_disponibilidad` se mantiene intacta (sigue existiendo, sigue siendo consultable).

**Si aparece error de sintaxis tipo `unterminated dollar-quoted string`** o algo que sugiera el bug del Supabase Dashboard:
- Parar inmediatamente.
- **NO** intentar `DROP CASCADE`.
- Pasar al fallback (Sección 6).

**Si aparece error de dependencia** (ej. "cannot change return type of existing function"):
- Parar inmediatamente.
- Esto indica que la firma cambió o que estamos comparando contra una versión distinta. Comparar el SQL aplicado contra el snapshot del Paso 1 antes de cualquier otra acción.

### Paso 5 — Verificación post-aplicación

#### 5.1 La función fue actualizada

```sql
SELECT pg_get_functiondef(p.oid) LIKE '%CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME ''16:00''%' AS regla_d47_aplicada
FROM pg_proc p
WHERE p.proname = 'obtener_disponibilidad_rango';
```

**Esperado:** `regla_d47_aplicada = true`.

#### 5.2 La vista sigue existiendo y funcionando

```sql
SELECT COUNT(*) AS filas_vista
FROM vista_disponibilidad;
```

**Esperado:** debe devolver una cantidad > 0 (5 cabañas × 60 días = 300 si seed está completo). Si devuelve 0, hay un problema. Si devuelve error tipo "vista no existe", la dependencia se rompió — revisar.

#### 5.3 Comportamiento dominical correcto en la función

```sql
SELECT fecha,
       EXTRACT(DOW FROM fecha) AS dow,
       hora_checkin_base,
       hora_checkout_base
FROM obtener_disponibilidad_rango(
  '2026-06-07'::DATE,
  '2026-06-09'::DATE,
  17
)
ORDER BY fecha;
```

**Esperado después del cambio:**

| fecha | dow | hora_checkin_base | hora_checkout_base |
|---|---|---|---|
| 2026-06-07 | 0 (domingo) | 18:00 | **16:00** ← ya alineado D47 |
| 2026-06-08 | 1 (lunes) | 13:00 | 10:00 |

#### 5.4 Comportamiento dominical correcto en la vista

```sql
SELECT fecha,
       EXTRACT(DOW FROM fecha) AS dow,
       hora_checkout_base
FROM vista_disponibilidad
WHERE EXTRACT(DOW FROM fecha) = 0
LIMIT 5;
```

**Esperado:** todas las filas con `hora_checkout_base = 16:00:00`.

#### 5.5 Las otras vistas siguen funcionando (chequeo de no-regresión)

```sql
-- Verificación rápida de que las demás vistas siguen accesibles
SELECT 'vista_disponibilidad' AS vista, COUNT(*) AS filas FROM vista_disponibilidad
UNION ALL SELECT 'vista_calendario', COUNT(*) FROM vista_calendario
UNION ALL SELECT 'vista_prereservas_activas', COUNT(*) FROM vista_prereservas_activas
UNION ALL SELECT 'vista_ocupacion', COUNT(*) FROM vista_ocupacion
UNION ALL SELECT 'vista_calendario_semanal', COUNT(*) FROM vista_calendario_semanal
UNION ALL SELECT 'vista_limpieza_semana', COUNT(*) FROM vista_limpieza_semana;
```

**Esperado:** 6 filas, todas con COUNT >= 0 sin error.

### Paso 6 — Bitacorear

Agregar a `Docs/Bitacora/6B_EJECUCION_DEV.md` una entrada con:

- Fecha y hora de ejecución.
- Resultado: OK / ERROR.
- Camino usado: principal (`CREATE OR REPLACE`) o fallback.
- Resultado de cada verificación del Paso 5 (5.1 a 5.5).
- Referencia al snapshot guardado en Paso 1.
- Confirmación: "DEV alineado con `6B_SCHEMA_SQL.md v1.7.1`".

### Paso 7 — Actualizar documentación de estado

En `ESTADO_VITA_DELTA_ACTUAL.md`, cambiar:

- "DEV está alineado con v1.7. Pendiente alineación final con v1.7.1..." → "DEV alineado con v1.7.1 (`obtener_disponibilidad_rango()` actualizada el [fecha])."
- Quitar la sección "Mini-pendiente de alineación a ejecutar..." o moverla a histórico cerrado.

---

## 6. FALLBACK — SI EL CAMINO PRINCIPAL FALLA

**Solo usar si `CREATE OR REPLACE` del Paso 4 falla técnicamente.** No usar por preferencia.

### Diagnóstico previo

Antes de entrar al fallback, leer atentamente el error:

| Síntoma del error | Significado | Acción |
|---|---|---|
| `unterminated dollar-quoted string` | Probablemente bug Dashboard | Usar fallback |
| `cannot change return type of existing function` | Firma distinta | NO usar fallback. Comparar SQL. |
| `function ... already exists with different argument types` | Firma distinta | NO usar fallback. Comparar SQL. |
| `permission denied` | Permisos | NO es problema de schema. Revisar usuario. |
| Cualquier otro error | Investigar | NO continuar a ciegas. |

### Procedimiento de fallback

Solo si el diagnóstico apunta al bug del Dashboard. El patrón validado en Hotfix v1.7 fue `DROP + CREATE` en runs separados. Pero `crear_prereserva()` no tenía vistas dependientes. **`obtener_disponibilidad_rango()` SÍ las tiene**, así que el patrón se ajusta:

#### Paso F-1 — Confirmar que tenemos el snapshot de la vista

Verificar que el resultado del Paso 2.2 está guardado localmente. Si no, **volver al Paso 2.2 y guardarlo antes de avanzar**.

#### Paso F-2 — Verificar si otras vistas dependen de `vista_disponibilidad`

Antes de recrear `vista_disponibilidad` temporalmente, hay que saber si alguna otra vista la consulta. Si es así, recrearla temporalmente vacía rompe esa otra vista.

```sql
-- ¿Alguna vista usa vista_disponibilidad?
SELECT
  c.relname AS vista_que_usa_vista_disponibilidad,
  pg_get_viewdef(c.oid, true) ILIKE '%vista_disponibilidad%' AS la_usa
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'v'
  AND n.nspname = 'public'
  AND c.relname <> 'vista_disponibilidad'
ORDER BY c.relname;
```

**Resultados esperados según el schema canónico:**
- Las 5 vistas restantes (`vista_calendario`, `vista_prereservas_activas`, `vista_ocupacion`, `vista_calendario_semanal`, `vista_limpieza_semana`) **no consultan** `vista_disponibilidad`. Consultan directamente `reservas`, `pre_reservas`, `bloqueos`, `cabanas`, etc.
- Entonces la columna `la_usa` debe dar `false` para todas.

**Si alguna vista da `la_usa = true`:**
- Parar.
- Esa vista se rompería al recrear `vista_disponibilidad` temporalmente vacía.
- Hay que agregar al procedimiento un snapshot de esa vista también, y recrearla al final junto con `vista_disponibilidad`.
- **No continuar con el fallback hasta tener resuelto este punto.**

#### Paso F-3 — Recrear `vista_disponibilidad` con estructura vacía temporal

Esta es la opción segura: preserva la vista (no la elimina), solo la vacía temporalmente, y mantiene su estructura de columnas. Eso evita que algo más en el medio falle por vista ausente o por columnas desconocidas.

```sql
-- Vista temporal con la misma estructura pero sin filas y sin depender de la función
CREATE OR REPLACE VIEW vista_disponibilidad AS
SELECT
  NULL::BIGINT AS id_cabana,
  NULL::DATE   AS fecha,
  NULL::TEXT   AS estado,
  NULL::TEXT   AS tipo_dia,
  NULL::TEXT   AS temporada,
  NULL::TIME   AS hora_checkin_base,
  NULL::TIME   AS hora_checkout_base,
  NULL::BIGINT AS id_reserva_activa,
  NULL::BIGINT AS id_prereserva_activa
WHERE FALSE;
```

**Verificación rápida:**

```sql
SELECT COUNT(*) AS filas FROM vista_disponibilidad;
-- Esperado: 0
```

#### Paso F-4 — DROP de la función (ahora sin dependencias)

```sql
DROP FUNCTION IF EXISTS obtener_disponibilidad_rango(DATE, DATE, BIGINT);
```

**Esperado:** "DROP FUNCTION". Si dice "cannot drop function ... because other objects depend on it", el Paso F-3 no se aplicó correctamente o hay alguna dependencia no detectada en los Pasos 2.1.a/b. Volver atrás y revisar.

#### Paso F-5 — CREATE de la función v1.7.1 (run separado)

Ejecutar el bloque SQL de la Sección 4 de este documento, pero usando `CREATE FUNCTION` en vez de `CREATE OR REPLACE FUNCTION`. Esto evita que el Dashboard active el feature problemático (mismo workaround que el hotfix v1.7).

#### Paso F-6 — Recrear `vista_disponibilidad` con su definición original

Usando el snapshot guardado en Paso 2.2:

```sql
CREATE OR REPLACE VIEW vista_disponibilidad AS
SELECT *
FROM obtener_disponibilidad_rango(
  CURRENT_DATE,
  (CURRENT_DATE + 60)::DATE,
  NULL
);
```

(SQL exacto según el schema canónico Bloque 20. Si el snapshot del Paso 2.2 muestra una variante distinta — por ejemplo con horizonte configurable de `Pendiente_pre_produccion.md` punto 1.1 — usar esa variante para no perder configuración de DEV.)

#### Paso F-7 — Verificaciones del Paso 5

Ejecutar todas las verificaciones del Paso 5 normal. Idéntico criterio de éxito.

---

### Último recurso: `DROP VIEW` directo (DESACONSEJADO)

Esto se documenta solo para que quede registrado como camino conocido, pero **no es la opción recomendada** del fallback. El procedimiento normal del fallback (F-3 a F-7) preserva siempre la vista en estructura.

```sql
-- Último recurso, NO usar salvo necesidad extrema
-- DROP VIEW vista_disponibilidad;
```

Solo considerarlo si:

- F-3 falla por algún motivo no documentado.
- Y se confirmó previamente (en el Paso F-2) que ninguna otra vista depende de `vista_disponibilidad`.
- Y se tiene el snapshot del Paso 2.2 listo para recrearla inmediatamente después.

Riesgo conocido: durante el intervalo entre el DROP y el CREATE, cualquier query que mencione `vista_disponibilidad` va a fallar con "relation does not exist". Si hay workflows n8n apuntando a DEV ya activos (que no es el caso en 6C todavía), esto los rompe.

**Preferir siempre F-3 a F-7 sobre este camino.**

---

## 7. ROLLBACK

Si por algún motivo hay que revertir el cambio:

```sql
-- Restaurar la función a su versión v1.7 desde el snapshot del Paso 1
-- Pegar el SQL guardado en Docs/Bitacora/snapshots/obtener_disponibilidad_rango_v1.7_pre_actualizacion.sql
```

`CREATE OR REPLACE FUNCTION` con el SQL viejo debería funcionar sin problemas porque la firma no cambia.

Verificar con el query 5.3 que `hora_checkout_base` vuelve a `10:00` los domingos.

Bitacorear el rollback con motivo explícito.

---

## 8. CRITERIOS DE ÉXITO

DEV queda alineado con `6B_SCHEMA_SQL.md v1.7.1` cuando:

- [ ] `obtener_disponibilidad_rango()` devuelve `16:00` para `hora_checkout_base` los domingos.
- [ ] `vista_disponibilidad` refleja el mismo comportamiento.
- [ ] Las otras 5 vistas siguen funcionando sin error.
- [ ] No quedan referencias a "pendiente de alineación" en `ESTADO_VITA_DELTA_ACTUAL.md`.
- [ ] La bitácora tiene la entrada cerrada con OK.

---

## 9. CRITERIOS DE FRENO

Parar y consultar si:

- Aparece un error técnico que no encaja con los síntomas conocidos del bug Dashboard.
- Una verificación post-aplicación devuelve un resultado inesperado (ej. la función actualizada pero la vista sigue mostrando 10:00 — eso indicaría que la vista no se está recalculando, que es muy raro porque las vistas SQL no son materializadas y se evalúan en tiempo real, pero si pasa hay algo más).
- Se detecta un objeto dependiente en el Paso 2.1 que no figura documentado en el schema canónico.
- El snapshot del Paso 1 muestra que la función actual no coincide con v1.7 (significa que DEV está en un estado distinto al esperado y hay que entender qué pasó antes de tocar).

---

## 10. POST-CIERRE: PRÓXIMO PASO

Una vez ejecutado y bitacoreado:

1. Actualizar `ESTADO_VITA_DELTA_ACTUAL.md` (Paso 7 del procedimiento).
2. Cerrar formalmente la Etapa 6B.
3. Arrancar 6C con W0 — Smoke test n8n ↔ Supabase, siguiendo `6C_REESCRITURA_WORKFLOWS_SUPABASE.md v1.2`.

---

*Documento generado como parte del proceso de cierre de la Etapa 6B del sistema Complejo Vita Delta.*
*Versión 1.1 — aprobado para ejecución de Pasos 0-3 (read-only).*
