Ajustes pendientes sobre 6B_SCHEMA_SQL.md
Documento base actual: Docs/Implementacion/6B_SCHEMA_SQL.md v1.6.1
Estado: Pendientes documentales detectados durante ejecución en Supabase DEV
Objetivo: Acumular ajustes documentales menores para aplicar en una sola versión posterior al cierre de Fase 3, evitando bumps de versión sucesivos durante la ejecución.

Este archivo NO reemplaza al schema canónico.
No contiene SQL ejecutable obligatorio.
Sirve como lista de pendientes para actualizar 6B_SCHEMA_SQL.md de forma ordenada al finalizar la ejecución de Fase 3.


Criterio de inclusión
Un hallazgo va a este archivo si cumple las tres condiciones:

Es puramente documental (no requiere cambios en SQL ejecutable, schema, funciones, triggers ni tests).
No afecta la ejecución de los bloques pendientes (no genera riesgo de error en runtime).
Puede esperar al cierre de Fase 3 sin generar confusión durante la ejecución.

Si un hallazgo afecta la ejecución de un bloque pendiente (por ejemplo, un bug en runtime), va directo a un patch del schema (v1.6.x) sin pasar por este archivo.
Los hallazgos "descartados" (que no se incorporan al schema canónico) NO van a este archivo. Su lugar natural es la bitácora del bloque donde aparecieron y/o el archivo de lecciones operativas (operacional/).

PENDIENTE 1 — Nota técnica sobre NOW() y triggers set_updated_at
Detectado en: Bloque 19 — Triggers automáticos
Tipo: Documental
Impacto: Medio para validación; nulo para funcionalidad
Estado: Pendiente de incorporar al Bloque 19 del schema canónico
Hallazgo
En PostgreSQL, NOW() retorna el timestamp de inicio de transacción. En Supabase SQL Editor, cuando varios statements se ejecutan juntos en una misma pestaña, pueden correr dentro de una transacción implícita.
Esto puede hacer que un test de updated_at muestre:
created_at = updated_at
aunque el trigger BEFORE UPDATE se haya disparado correctamente.
Decisión preliminar
Agregar una nota técnica dentro del Bloque 19, antes (o dentro) de la sección "Verificación post-ejecución".
Texto sugerido para integrar al schema
markdown### Nota técnica: validación correcta de triggers `set_updated_at` en Supabase

**Comportamiento de `NOW()` en transacciones implícitas.**

En PostgreSQL, `NOW()` es alias de `transaction_timestamp()` y retorna el timestamp de **inicio de transacción**, no del momento de ejecución del statement individual. En Supabase SQL Editor, múltiples statements ejecutados en la misma pestaña corren dentro de una **transacción implícita única**, por lo que todas las llamadas a `NOW()` dentro de esa sesión retornan el mismo valor al microsegundo.

**Consecuencia operativa:** si se valida el trigger `set_updated_at` ejecutando en una misma pestaña:

```sql
INSERT INTO huespedes (nombre, telefono) VALUES ('Test', '+5491100000099');
SELECT created_at, updated_at FROM huespedes WHERE telefono_normalizado = '+5491100000099';
UPDATE huespedes SET nombre = 'Test_modificado' WHERE telefono_normalizado = '+5491100000099';
SELECT created_at, updated_at FROM huespedes WHERE telefono_normalizado = '+5491100000099';
```

el resultado mostrará `created_at = updated_at` al microsegundo, lo cual puede sugerir erróneamente que el trigger no se disparó. **El trigger SÍ se disparó**: simplemente `NOW()` devolvió el mismo valor en el INSERT y en el UPDATE porque ambos corrieron dentro de la misma transacción implícita.

**Patrón correcto para validar funcionalmente el trigger:** ejecutar INSERT y UPDATE en **runs separados** (transacciones distintas).

**Run 1 — INSERT** (cerrar la ejecución para que la transacción se cierre):

```sql
INSERT INTO huespedes (nombre, telefono) VALUES ('Test', '+5491100000099');
```

**Run 2 — UPDATE + verificación** (nueva transacción):

```sql
UPDATE huespedes SET nombre = 'Test_modificado'
WHERE telefono_normalizado = '+5491100000099';

SELECT
  (updated_at > created_at)                                AS trigger_funciono,
  EXTRACT(EPOCH FROM (updated_at - created_at))::INTEGER   AS segundos_dif
FROM huespedes
WHERE telefono_normalizado = '+5491100000099';
```

**Resultado esperado:** `trigger_funciono: true`, `segundos_dif >= 1` (la diferencia depende del tiempo transcurrido entre runs; no es por race condition sino simplemente para que el delta sea visible).

**Alcance:** esta nota aplica a todos los triggers `set_updated_at` del Bloque 19 (9 tablas con campo `updated_at`). No es un bug del schema; es una característica del modelo transaccional de PostgreSQL combinada con el comportamiento del SQL Editor de Supabase.
Origen
Detectado durante la ejecución real del Bloque 19 en DEV. El test 19.3 inicial mostró updated_at_avanzo: false con timestamps idénticos al microsegundo, lo cual sugirió erróneamente que el trigger no se disparaba. El test 19.3-bis (en transacciones separadas) confirmó funcionamiento correcto con segundos_diferencia: 29. Documentado en bitácora del Bloque 19.

Pendientes futuros
Espacio reservado para hallazgos de Fase 3 (Bloques 20-22) que cumplan el criterio de inclusión arriba.

Plan de integración
Al cerrar Fase 3:

Revisar este archivo y consolidar los pendientes acumulados.
Generar versión nueva del schema (probablemente v1.7) integrando todos los pendientes documentales en un solo bump.
Una vez integrados al schema canónico, archivar este archivo o limpiarlo dejando solo el registro histórico de qué se integró y cuándo.