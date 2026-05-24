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