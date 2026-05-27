# Ajustes pendientes sobre 6B_SCHEMA_SQL.md — RESUELTOS

**Documento base original:** `Docs/Implementacion/6B_SCHEMA_SQL.md v1.6.1`  
**Documento canónico actual:** `Docs/Implementacion/6B_SCHEMA_SQL.md v1.7.1`  
**Estado:** Cerrado / archivado  
**Motivo:** Fase 3 cerrada. Los ajustes relevantes fueron evaluados durante la consolidación del schema hasta `v1.7.1`.

> Este archivo queda como registro histórico de pendientes documentales detectados durante la ejecución DEV.  
> No contiene pendientes activos.  
> No reemplaza al schema canónico.

---

## Propósito original del archivo

Este archivo fue creado durante la ejecución de la Etapa 6B para acumular ajustes documentales menores sobre `6B_SCHEMA_SQL.md`, evitando generar bumps sucesivos de versión por cada hallazgo no bloqueante.

El criterio original era:

- hallazgos puramente documentales;
- sin impacto en SQL ejecutable;
- sin impacto en ejecución de bloques pendientes;
- acumulables hasta el cierre de Fase 3.

Una vez cerrada Fase 3 y consolidado el schema hasta `6B_SCHEMA_SQL.md v1.7.1`, este archivo deja de ser una lista activa de pendientes y pasa a funcionar como registro histórico.

---

## Resultado final

Los hallazgos relevantes fueron revisados durante la consolidación posterior a la ejecución DEV.

El schema canónico vigente quedó en: `Docs/Implementacion/6B_SCHEMA_SQL.md v1.7.1`.

Esta versión incorpora los cambios funcionales y documentales necesarios detectados durante la ejecución, incluyendo:

- correcciones de locks y cast `::INTEGER`;
- regla operativa `hora_checkout_domingo = 16:00`;
- alineación de `obtener_disponibilidad_rango()` con D47;
- advertencias operativas sobre modificación de funciones en Supabase Dashboard;
- advertencias sobre `DROP FUNCTION` y dependencias.

---

## Pendiente evaluado — Nota técnica sobre `NOW()` y triggers `set_updated_at`

**Detectado en:** Bloque 19 — Triggers automáticos  
**Tipo:** Documental / aprendizaje operativo  
**Impacto:** Medio para validación; nulo para funcionalidad  
**Estado:** Evaluado post-Fase 3  
**Decisión:** Mantener como lección operativa / referencia de testing. No bloquea `6B_SCHEMA_SQL.md v1.7.1`.

### Hallazgo

Durante la validación de los triggers `set_updated_at`, se observó que un test podía mostrar:

`created_at = updated_at`

aunque el trigger `BEFORE UPDATE` se hubiera disparado correctamente.

### Diagnóstico

En PostgreSQL, `NOW()` es alias de `transaction_timestamp()` y retorna el timestamp de inicio de la transacción, no el instante exacto de cada statement individual.

En Supabase SQL Editor, múltiples statements ejecutados en la misma pestaña pueden correr dentro de una transacción implícita única. Por eso, si se ejecuta un `INSERT` y luego un `UPDATE` dentro del mismo run, ambos pueden recibir exactamente el mismo valor de `NOW()`.

Esto puede hacer parecer que el trigger `updated_at` no funcionó, cuando en realidad sí se disparó.

### Patrón correcto de validación

Para validar funcionalmente un trigger `set_updated_at`, ejecutar el `INSERT` y el `UPDATE` en runs separados.

**Run 1 — INSERT**

`INSERT INTO huespedes (nombre, telefono) VALUES ('Test', '+5491100000099');`

**Run 2 — UPDATE + verificación**

`UPDATE huespedes SET nombre = 'Test_modificado' WHERE telefono_normalizado = '+5491100000099';`

Luego verificar:

`SELECT (updated_at > created_at) AS trigger_funciono, EXTRACT(EPOCH FROM (updated_at - created_at))::INTEGER AS segundos_dif FROM huespedes WHERE telefono_normalizado = '+5491100000099';`

**Resultado esperado:**

- `trigger_funciono = true`
- `segundos_dif >= 1`

### Conclusión

No es un bug del schema. Es una característica normal del modelo transaccional de PostgreSQL combinada con el comportamiento del SQL Editor de Supabase.

Este aprendizaje queda registrado como referencia operativa para futuras ejecuciones en TEST/PROD o recreaciones de DEV.

---

## Pendientes activos

No quedan pendientes activos en este archivo.

Cualquier nuevo ajuste sobre `6B_SCHEMA_SQL.md` debe tratarse según su naturaleza:

1. **Bug o cambio SQL real:** generar nueva versión del schema.
2. **Nota documental menor:** evaluar si va al schema, a bitácora o a lecciones operativas.
3. **Pendiente productivo:** registrar en `Pendiente_pre_produccion.md`.
4. **Hallazgo de ejecución:** registrar en `Docs/Bitacora/6B_EJECUCION_DEV.md`.

---

## Estado final

Este archivo queda archivado como registro histórico.

No requiere acción adicional salvo que en el futuro se quiera mover a una carpeta de archivados, por ejemplo:

`Docs/Implementacion/Archivados/6B_SCHEMA_SQL_AJUSTES_PENDIENTES_RESUELTOS.md`

Mientras permanezca en su ubicación actual, debe entenderse como archivo cerrado, no como lista activa de tareas.