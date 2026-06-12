# 6B_SCHEMA_SQL.md
# Schema PostgreSQL — Vita Delta Reservas

**Versión:** 1.7.3
**Fecha:** Mayo 2026
**Estado:** `6B_SCHEMA_SQL.md v1.7.3` refleja el estado real de DEV tras la Etapa 6D (hardening, cerrada formalmente el 2026-05-27) y la Etapa 7A (correcciones pre-TEST/pre-OPS, cerrada el 2026-05-28). DEV está alineado funcionalmente con v1.7.3.
**Proyecto:** Sistema de gestión y automatización — Complejo Vita Delta
**Autores:** Franco (titular) + Claude (arquitecto)
**Depende de:** ARQUITECTURA_ETAPA_6A_DECISION_MIGRACION.md v1.1
**Sucesora directa de:** ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md v1.1

> **IMPORTANTE:** El SQL de la Parte B se ejecuta bloque por bloque siguiendo `Docs/Implementacion/6B_PLAN_FASES.md`. Los Bloques 1-22 ya fueron ejecutados y verificados en Supabase DEV. Sobre ese estado, durante Etapa 6D se aplicó el hardening estructural H2-H6-bis y se validó concurrencia en H7; Etapa 6D quedó cerrada formalmente el 2026-05-27. Durante Etapa 7A se aplicaron correcciones pre-TEST/pre-OPS: patch de `crear_prereserva`, limpieza legacy de `ninos='false'` y horizonte configurable para `vista_disponibilidad`/`vista_calendario`. v1.7.3 refleja el estado funcional de DEV post-7A, adoptando cuerpos persistidos reales vía `pg_get_functiondef()` / `pg_get_viewdef()` donde aplica.
> **NOTA DE SANITIZACIÓN:** Este documento fue revisado para subir a GitHub. No contiene Project ID, Project URL, passwords, connection strings, anon keys, service role keys, JWTs ni datos reales de huéspedes. Los teléfonos en tests funcionales son sintéticos. Las credenciales reales del proyecto Supabase deben vivir fuera del repositorio.
> **NOTA — Carril B / contabilidad operativa interna (9C→9H), sin bump del canónico:** El Carril B (sub-etapas 9C a 9H) fue construido y validado **solo en TEST** como capa **aditiva y no canónica**: nuevas columnas en `cabanas` (`valor_relativo`, `id_socio_beneficiario`), tablas `zonas`/`cabana_zona`/`activaciones_operativas`/`gastos_internos` y las cinco tablas con estado de la cuenta corriente (`liquidaciones_periodo`/`liquidacion_cascada`/`liquidacion_socio`/`movimientos_socio`/`revaluaciones`), más el marcador `configuracion_general('ambiente')`, los triggers de inmutabilidad y las funciones de matriz, cascada y cuenta corriente. **Estos objetos no existen en DEV ni en OPS y no forman parte de este canónico.** La versión se mantiene **deliberadamente en v1.7.3**: el bump consolidado que incorpore el Carril B se hará **recién en la promoción coordinada a OPS** (un único DDL, sin copiar datos de TEST), no en este momento. Cierres formales: `9B_CIERRE.md`, `9C_CIERRE.md` … `9H_CIERRE.md`.

---

## RESUMEN DE CAMBIOS v1.7.2 → v1.7.3

Bump documental que refleja las correcciones aplicadas y validadas en DEV durante la **Etapa 7A — Correcciones pre-TEST / pre-OPS** (2026-05-28). Resolvió los pendientes 1.1, 1.2 y 1.3 de `Pendiente_pre_produccion.md`. Decisiones D-7A-01, D-7A-02, D-7A-03. Cierre formal en `7A_CIERRE.md`.

### a) Patch en `crear_prereserva` (Bloque 13)

Tres cambios quirúrgicos, validados con 9 tests funcionales en DEV:

1. **`v_ninos` de `BOOLEAN` a `TEXT`** (D-7A-02). El extract pasó de `COALESCE(NULLIF(TRIM(payload->>'ninos'), '')::BOOLEAN, FALSE)` a `NULLIF(TRIM(payload->>'ninos'), '')`. Alinea la variable con las columnas `pre_reservas.ninos` y `reservas.ninos` (que ya eran `TEXT`). Semántica: `NULL` = no informado; texto libre = detalle operativo. Elimina el residuo `"false"` que generaba el cast implícito BOOLEAN→TEXT.

2. **`canal_pago_esperado` agregado al IF de obligatorios** (D-7A-01). Si llega ausente, vacío o whitespace, la función rebota con `payload_invalido` controlado (antes el INSERT fallaba con error crudo de constraint `NOT NULL`). La columna sigue `TEXT NOT NULL` y el CHECK de 5 valores se mantiene. Validación de valores no-NULL fuera del CHECK queda fuera de alcance (sigue rebotando por constraint).

3. Sin otros cambios en el cuerpo: firma, retorno, locks, idempotencia, validación de cabaña/disponibilidad, cálculo de horarios (regla D47 dominical intacta), INSERT y logs sin tocar.

### b) Horizonte configurable en vistas (Bloque 20, D-7A-03)

`vista_disponibilidad` y `vista_calendario` leen el horizonte forward desde `configuracion_general.horizonte_disponibilidad_dias` con fallback `120` por `COALESCE` (antes hardcoded `CURRENT_DATE + 60`). Validado con 4 tests (1 empírico + 3 estructurales/no-regresión):

- `vista_disponibilidad`: rango exclusivo `[CURRENT_DATE, CURRENT_DATE + N)`. Con N=120: 120 días distintos, `MAX(fecha) = CURRENT_DATE + 119`, 600 filas (120 × 5 cabañas). Forma persistida adoptada (9 columnas explícitas; PostgreSQL absorbe el cast `::DATE` redundante).
- `vista_calendario`: filtro inclusivo `<= (CURRENT_DATE + N)`. El operador `<=` se mantuvo sin cambios.

### c) Seed (Bloque 21)

Clave `horizonte_disponibilidad_dias` agregada al seed (`categoria='disponibilidad'`, valor `120`). El conteo esperado de `configuracion_general` pasa de 9 a 10. La clave ya existía en DEV antes de 7A (origen probable: ejecución histórica intermedia); el seed la documenta para que TEST/PROD nazcan con ella.

### d) Limpieza puntual de datos legacy (no es decisión)

Los 3 registros con `ninos='false'` (pre_reservas 25, 26; reserva 8) fueron migrados a `NULL`. Limpieza puntual, documentada en `7A_CIERRE.md`, sin número de decisión.

### Lo que NO cambió

- Funciones distintas de `crear_prereserva`: `normalizar_telefono`, `upsert_huesped`, `validar_disponibilidad`, `obtener_disponibilidad_rango`, `confirmar_reserva`, `cancelar_prereserva`, `crear_bloqueo`, `registrar_pago`, `expirar_prereservas_vencidas`.
- Vistas distintas de `vista_disponibilidad` y `vista_calendario`.
- Tablas, constraints (incluido `chk_pre_reservas_canal_pago` y el `NOT NULL` de `canal_pago_esperado`), EXCLUDE, triggers, schedules pg_cron.
- Diseño de locks, motor de precios, RLS, workflows n8n.
- Decisiones D1-D47 ni D-HARD-01 a D-HARD-11.

### Estado en Supabase DEV

- Bloques 1-22 ejecutados. v1.7.2 aplicado (hardening 6D). Etapa 6D cerrada el 2026-05-27.
- Patch `crear_prereserva` v1.7.3 aplicado vía `CREATE OR REPLACE FUNCTION` (camino limpio, sin bug del Dashboard). Verificado con `pg_get_functiondef`.
- Vistas `vista_disponibilidad` y `vista_calendario` actualizadas vía `CREATE OR REPLACE VIEW`. Verificadas con `pg_get_viewdef`.
- DEV alineado funcionalmente con v1.7.3.

### Observación liviana abierta (no bloqueante)

- **`tipo_valor` sin poblar:** las 10 claves de `configuracion_general` tienen `tipo_valor=NULL`. No afecta funcionamiento (los casts son explícitos). A evaluar antes del dashboard OPS. Ver `Pendiente_pre_produccion.md` 1.4.

### Backup de v1.7.2

Copia archivada del estado pre-7A en `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.2_PRE_PREOPS.md`.

---

## RESUMEN DE CAMBIOS v1.7.1 → v1.7.2

Bump documental que refleja el estado real de DEV tras la aplicación de Etapa 6D — Hardening pre-producción. Etapa 6D incluye los bloques estructurales H2-H6-bis (que sí modificaron SQL en DEV) y H7 (tests de concurrencia, sin cambios SQL). El cierre formal de Etapa 6D queda diferido al cierre del Frente B de H8.

### a) Cambios derivados del hardening H2-H6-bis

**Funciones write críticas (Bloques 13-17):** los cuerpos persistidos en DEV fueron capturados vía `pg_get_functiondef()` y reflejados en este canónico. Patrón defensivo `NULLIF(TRIM(...), '')` aplicado en los extracts de payload de las 5 funciones write críticas: `registrar_pago`, `confirmar_reserva`, `crear_prereserva`, `cancelar_prereserva` y `crear_bloqueo`. El patrón:

- normaliza `""` y whitespace puro (`"   "`) a NULL real antes del cast;
- evita errores crudos de cast en numéricos, booleanos, DATE, TIME y BIGINT cuando llegan strings vacíos o whitespace;
- mantiene el contrato: las validaciones siguen rebotando con `payload_invalido` cuando un campo obligatorio queda NULL.

Excepción documentada inline en `crear_prereserva`: `v_huesped_payload` usa `payload->'huesped'` (operador JSONB anidado, no derivado de `payload->>'...'`); su normalización vive en `upsert_huesped()` y no aplica el patrón canónico.

**Caso especial `crear_bloqueo` con `id_cabana`:** el patrón mantiene la semántica de "NULL = bloqueo total" — `id_cabana: null`, `""` y `"   "` se interpretan como bloqueo total. `id_cabana: 17` (o cualquier ID válido) implica bloqueo específico.

**`crear_prereserva` — `canal_pago_esperado`:** el extract aplica el patrón canónico `NULLIF(TRIM(...), '')`, pero el campo continúa requerido a nivel schema porque `pre_reservas.canal_pago_esperado` es `TEXT NOT NULL`. Si llega ausente, vacío o whitespace, la variable queda NULL y el INSERT puede fallar por constraint `NOT NULL`; evaluar en Frente B si corresponde restaurar validación manual controlada o hacer nullable la columna.

**`vista_ocupacion` (Bloque 20, V4) — fix de rango:** ajustada para devolver exactamente 24 meses. El límite superior del `generate_series` ahora resta `'1 mon'::interval` para evitar el edge case que generaba 25 puntos = 25 meses × cabaña.

**`vista_calendario`, `vista_limpieza_semana` y `vista_prereservas_activas` (Bloque 20) — fix cosmético:** TRIM aplicado a la concatenación nombre + apellido para evitar espacios colgando cuando `apellido` es NULL o vacío. En `vista_limpieza_semana` el TRIM se aplica en 2 ocurrencias (una por cada parte del UNION ALL).

**Validación empírica (H7, sin cambios SQL):** 6 tests de concurrencia ejecutados sobre las funciones write críticas validaron empíricamente la invariante de locks v1.5 (lock global SIEMPRE primero) bajo paralelismo real. Resultado: 6/6 aprobados, cero deadlocks `40P01`, cero races, cero doble booking. Detalle en `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` sección H7.

### b) Correcciones documentales de alineación con DEV real

Durante la captura de snapshots para el bump v1.7.2 se identificaron divergencias entre el cuerpo persistido en DEV y la descripción narrativa previa del canónico. Estas correcciones no son cambios de hardening — son alineación de la documentación con la realidad observada:

- **`registrar_pago` (Bloque 17) — log explícito:** el `modificado_por` del log se calcula como `COALESCE(v_validado_por, 'registrar_pago')`. El cast del campo `nivel` es explícito: `'warning'::nivel_log_enum` o `'info'::nivel_log_enum` según corresponda. Estos detalles ahora quedan documentados en el cuerpo.
- **`confirmar_reserva` (Bloque 14) — error sobre pre-reserva en estado terminal:** la función retorna `error='estado_invalido'` con un campo adicional `estado_actual` que indica el estado real de la pre-reserva. v1.7.2 documenta este contrato tal como existe en DEV.
- **`crear_prereserva` (Bloque 13) — variable `v_ninos`:** DEV real declara y usa `v_ninos` como `BOOLEAN`. El canónico v1.7.1 lo documentaba como `TEXT`. v1.7.2 refleja el tipo real de la variable. Hallazgo lateral: las columnas `pre_reservas.ninos` y `reservas.ninos` son `TEXT`. La desalineación de tipo entre función y columnas queda documentada como pendiente liviano a evaluar antes de TEST/PROD (ver Frente B de H8); no es freno del bump documental.

### c) Nota técnica — forma persistida de las vistas

Las vistas actualizadas en este bump se reflejan en la forma persistida por PostgreSQL vía `pg_get_viewdef()` para facilitar futuras comparaciones. PostgreSQL normaliza ciertas expresiones al persistir (por ejemplo `TRIM(x)` → `TRIM(BOTH FROM x)`, `'1 month'::interval` → `'1 mon'::interval`, `'12 months'::interval` → `'1 year'::interval`, `date_trunc('month', x)` con casts explícitos de tipo). Las diferencias textuales contra la forma humana son equivalentes funcionales; el canónico adopta la forma persistida para garantizar match byte-exacto contra DEV.

### Lo que NO cambió

- Tablas de catálogo y transaccionales (Bloques 3-6) — la documentación de columnas ya estaba alineada con DEV en v1.7.1 (verificado durante el bump: `cabanas.capacidad_max`, `bloqueos.activo BOOLEAN NOT NULL DEFAULT true`).
- Funciones no afectadas por el hardening: `normalizar_telefono`, `upsert_huesped`, `validar_disponibilidad`, `obtener_disponibilidad_rango`, `expirar_prereservas_vencidas`.
- Vistas no afectadas: `vista_disponibilidad`, `vista_calendario_semanal`.
- Constraints EXCLUDE (Bloque 8).
- Triggers automáticos (Bloque 19).
- Seed mínimo (Bloque 21).
- Schedules de pg_cron (Bloque 22).
- Diseño de locks (D46, invariante v1.5, cast v1.6 con `::INTEGER`).
- Motor de precios, RLS, workflows n8n, tests funcionales documentados.
- Decisiones D1-D47 ni decisiones de hardening D-HARD-01 a D-HARD-11.

### Estado en Supabase DEV

- Bloques 1-22 ejecutados.
- v1.7.1 aplicado completamente (incluye `obtener_disponibilidad_rango()` alineado con D47).
- Hardening H2-H6-bis aplicado en DEV (Etapa 6D, sesión 2026-05-26).
- Tests de concurrencia H7 aprobados en DEV (sesión 2026-05-27, 6/6 aprobados).
- **Pendiente:** cierre formal de Etapa 6D vía `6D_CIERRE.md` (Frente B de H8).

### Hallazgos no resueltos en este bump

> **Nota (actualización v1.7.3):** los dos hallazgos listados abajo fueron **resueltos en la Etapa 7A** (bump v1.7.3, 2026-05-28). `ninos` → D-7A-02 (variable `TEXT`); `canal_pago_esperado` → D-7A-01 (restaurada validación manual). Se conserva el texto original para no alterar la historia del changelog. Ver el changelog `v1.7.2 → v1.7.3` arriba.

- **Alineación de tipo `ninos`:** función `crear_prereserva` declara `v_ninos BOOLEAN`, columnas `pre_reservas.ninos` y `reservas.ninos` son `TEXT`. Cast implícito BOOLEAN→TEXT en PostgreSQL al INSERT produce el valor textual `"false"` (observado empíricamente en los 3 registros existentes en DEV). Funcionalmente inocuo hoy. Queda como item liviano para evaluación pre-TEST/PROD durante Frente B de H8, agregado a `Pendiente_pre_produccion.md`. No es freno del bump documental.
- **Contrato de `canal_pago_esperado`:** el campo ya no está en la validación manual post-extract de `crear_prereserva`, pero la columna `pre_reservas.canal_pago_esperado` sigue siendo `TEXT NOT NULL`. Evaluar antes de TEST/PROD si se restaura validación manual con `payload_invalido` o si se decide nullable a nivel schema.

### Backup de v1.7.1

Se conserva copia archivada del estado pre-bump en `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md` con banner explícito de archivo histórico. Esa copia preserva el cuerpo íntegro de v1.7.1 para auditoría y rollback documental.

---

## RESUMEN DE CAMBIOS v1.7 → v1.7.1

Versión patch-level con un cambio SQL real menor + dos ajustes documentales. Sin tocar locks, EXCLUDE, motor de precios, RLS, workflows ni funciones no afectadas.

### Cambio SQL — `obtener_disponibilidad_rango()` (Bloque 12)

El SELECT interno de la función devolvía `TIME '10:00' AS hora_checkout_base` hardcodeado, lo cual quedó inconsistente con la regla D47 introducida en v1.7 (checkout máximo 16:00 si `fecha_out` es domingo).

**Cambio aplicado:**

```sql
-- Antes (v1.7):
TIME '10:00' AS hora_checkout_base,

-- Después (v1.7.1):
CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '16:00' ELSE TIME '10:00' END AS hora_checkout_base,
```

**Por qué importa:**

- `vista_disponibilidad` se construye sobre `obtener_disponibilidad_rango`. Sin este ajuste, la vista mostraría `hora_checkout_base = 10:00` también para domingos, contradiciendo la regla operativa real.
- Cuando se implemente `consultar_disponibilidad_precio()` (pendiente, ver D40), probablemente consumirá `obtener_disponibilidad_rango`. La inconsistencia en domingos llegaría hasta el cliente final.
- La función `crear_prereserva` ya aplica D47 correctamente desde v1.7. Este cambio alinea la vista de disponibilidad con la regla operativa, manteniendo coherencia entre las dos fuentes.

### Ajustes documentales

1. **Sección 15 (Nota operativa Supabase Dashboard):** advertencia agregada sobre `DROP FUNCTION` y dependencias. Si una función está siendo usada por triggers, vistas u otros objetos, `DROP FUNCTION` puede fallar por dependencias. **No usar `DROP ... CASCADE`** sin revisar impacto. El workaround `DROP + CREATE` se validó únicamente para `crear_prereserva` (función transaccional autónoma, sin triggers ni vistas dependientes). Para funciones con dependencias, evaluar caso por caso.

2. **Sección 16 (Utilidad operativa):** frase "antes del máximo 10:00" actualizada a "antes del máximo permitido —10:00 en días normales o 16:00 si `fecha_out` es domingo—". Mantiene compatibilidad con D47.

### Alineación de DEV con v1.7.1

Para alinear DEV con v1.7.1, se debe actualizar `obtener_disponibilidad_rango()` manteniendo la misma firma `(p_fecha_desde DATE, p_fecha_hasta DATE, p_id_cabana BIGINT DEFAULT NULL)`.

La opción natural es `CREATE OR REPLACE FUNCTION`. **Si el Supabase Dashboard vuelve a interferir con la ejecución** (ver hallazgo documentado en Sección 15 durante v1.7), **no usar `DROP ... CASCADE`** porque la función probablemente esté siendo usada por `vista_disponibilidad`. En ese caso, evaluar un workaround específico que preserve las dependencias.

Verificación post-actualización en DEV:

```sql
-- Verificar que la función fue actualizada
SELECT pg_get_functiondef(p.oid) LIKE '%CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN%' AS regla_d47_aplicada
FROM pg_proc p
WHERE p.proname = 'obtener_disponibilidad_rango';

-- Verificar comportamiento contra un domingo conocido
SELECT fecha, hora_checkout_base
FROM obtener_disponibilidad_rango(
  '2026-06-07'::DATE,  -- domingo
  '2026-06-08'::DATE,
  1                    -- cualquier id_cabana válido
)
WHERE EXTRACT(DOW FROM fecha) = 0;
-- Esperado: hora_checkout_base = 16:00:00
```

### Lo que NO cambió

- Schema, tablas, enums, vistas, triggers, EXCLUDE, pg_cron, seed.
- Diseño de locks (D46, invariante v1.5, cast v1.6).
- Funciones no afectadas: `crear_prereserva` (ya aplicaba D47 desde v1.7), `confirmar_reserva`, `cancelar_prereserva`, `crear_bloqueo`, `registrar_pago`, `expirar_prereservas_vencidas`, `upsert_huesped`, `validar_disponibilidad`, `normalizar_telefono`.
- Tests, decisiones D1-D47, motor de precios, RLS, workflows.

### Estado en Supabase DEV

- Bloques 1-22 ejecutados.
- v1.7 aplicado completamente (incluye `crear_prereserva` con D47 y `hora_checkout_domingo` en seed).
- **Pendiente:** actualizar `obtener_disponibilidad_rango()` para alinearse con v1.7.1.

---

## RESUMEN DE CAMBIOS v1.6.1 → v1.7

Versión que incorpora un cambio funcional real (regla de checkout dominical) y una nota operativa documental detectada durante ejecución. Cero cambios en locks, EXCLUDE, motor de precios, RLS, workflows.

### Cambio funcional — `hora_checkout_domingo` (D47)

Vita Delta tiene checkout dominical a las 16:00 por logística de lancha colectiva. Hasta v1.6.1, el sistema usaba `hora_checkout_default` (10:00) para todos los días, con un TODO en `crear_prereserva` que dejaba la lógica de "último día de bloque" para etapa futura. La regla operativa concreta del complejo es más simple que ese TODO genérico: **si `fecha_out` es domingo, el checkout máximo es 16:00**.

**Regla final:**
- Check-in domingo: 18:00 (ya existía).
- Check-out domingo: 16:00 (nuevo en v1.7).
- Check-out otros días: 10:00 (sin cambios).

**Las dos reglas son independientes.** El check-in dominical aplica cuando `fecha_in` es domingo; el check-out dominical aplica cuando `fecha_out` es domingo. Una pre-reserva puede tener una, la otra, ambas, o ninguna.

### Cambios aplicados

1. **Bloque 13 (`crear_prereserva`):**
   - La lectura agrupada de `configuracion_general` ahora incluye `hora_checkout_domingo`.
   - El chequeo de claves faltantes incluye `hora_checkout_domingo`.
   - `v_hora_checkout_max` se calcula con `CASE WHEN EXTRACT(DOW FROM v_fecha_out) = 0` (domingo en PostgreSQL es DOW = 0).
   - TODO anterior eliminado (queda resuelto por v1.7).

2. **Bloque 21 (seed):**
   - Agregada clave `hora_checkout_domingo` con valor `'16:00'`.
   - Eliminada clave `hora_checkout_ultimo_dia_bloque` (no se usa en ninguna función; queda como deuda futura si se implementa lógica específica para feriados o último día de bloque).
   - Conteo de `configuracion_general` se mantiene en **9 claves** (una entra, una sale).

3. **Sección 16 (Horarios):**
   - Reglas dominicales documentadas explícitamente para checkin y checkout, indicando que son independientes.
   - Aclaración: feriados y "último día de bloque" quedan fuera de alcance automático por ahora (resolución manual con el cliente si surge el caso).

4. **Sección 15 (Notas técnicas de PostgreSQL/Supabase):**
   - Agregada nota operativa sobre comportamiento observado del Supabase Dashboard al modificar funciones con `CREATE OR REPLACE FUNCTION`, y workaround `DROP + CREATE` en runs separados.

5. **Tabla de decisiones:** D47 agregada — "Checkout dominical a las 16:00 como regla operativa de Vita Delta".

### Lo que NO cambió

- Schema, constraints, EXCLUDE, tablas, enums, vistas, triggers, pg_cron.
- Diseño de locks (D46) e invariante de orden (v1.5).
- Cast `::INTEGER` en advisory locks (v1.6).
- Narrativa de Sección 10 alineada con SQL real (v1.6.1).
- Funciones no afectadas: `upsert_huesped`, `validar_disponibilidad`, `obtener_disponibilidad_rango`, `confirmar_reserva` (hereda `hora_checkout` correctamente desde la pre-reserva sin requerir cambios), `cancelar_prereserva`, `crear_bloqueo`, `registrar_pago`, `expirar_prereservas_vencidas`.
- Tests, motor de precios, RLS, workflows.

### Estado en Supabase DEV

- Bloques 1-22 ejecutados y bitacoreados.
- Hotfix `hora_checkout_domingo` aplicado en DEV y verificado durante Fase 3.
- DEV está alineado con v1.7. Para próximas recreaciones de DEV, ejecución de TEST y ejecución de PROD, este documento es la fuente de verdad.

---

## RESUMEN DE CAMBIOS v1.6 → v1.6.1

Versión de **corrección documental pura**. Patch-level, no minor bump, porque **no toca SQL ejecutable, schema, funciones ni tests**. Solo alinea la narrativa con el SQL real.

### Por qué importa

La descripción conceptual de algunas funciones en Sección 10 quedó desactualizada respecto al SQL real después de las correcciones de v1.5 (invariante de orden de locks) y v1.6 (cast `::INTEGER`). En particular, las narrativas de `confirmar_reserva` (10.6) y `cancelar_prereserva` (10.7) describían el SELECT FOR UPDATE como primer paso y el lock global después.

**Eso contradice directamente la invariante de locks v1.5**, que exige tomar `pg_advisory_xact_lock(10, 0)` antes de CUALQUIER otro lock — incluido `SELECT ... FOR UPDATE`. Si alguien leyera solo la Sección 10 (sin mirar el SQL ejecutable) para entender el flujo o implementar una variante, internalizaría el orden incorrecto: justo el patrón que generaba deadlocks `40P01` entre `confirmar_reserva` y `cancelar_prereserva` antes de la corrección de v1.5.

v1.6.1 cierra esa inconsistencia documental.

### Cambios aplicados

1. **Sección 10.6 (`confirmar_reserva`) — orden de locks corregido en la narrativa:**
   - Antes (v1.6): "Lockear pre-reserva con FOR UPDATE → tomar locks de disponibilidad".
   - Ahora (v1.6.1): "Setear contexto → tomar lock global `(10, 0)` ANTES del FOR UPDATE → lockear pre-reserva con FOR UPDATE → tomar lock por cabaña `(1, v_pre.id_cabana::INTEGER)`".

2. **Sección 10.7 (`cancelar_prereserva`) — orden de locks corregido en la narrativa:**
   - Antes (v1.6): "Lockear pre-reserva con FOR UPDATE → tomar lock global".
   - Ahora (v1.6.1): "Setear contexto → tomar lock global `(10, 0)` ANTES del FOR UPDATE → mapear motivo → lockear pre-reserva con FOR UPDATE".

3. **Menciones conceptuales del lock por cabaña unificadas con cast** `::INTEGER` en Sección 10 (10.5, 10.6, 10.7, 10.8). Antes algunas decían `pg_advisory_xact_lock(1, id_cabana)` sin cast en texto descriptivo; ahora todas usan el patrón consistente con el SQL ejecutable y con la nota técnica de Sección 15.

### Lo que NO cambió

- **Cero cambios en SQL ejecutable.** Bloques 13, 14, 15, 16 y resto siguen exactamente como en v1.6.
- Schema, constraints, EXCLUDE, tablas, enums, vistas, triggers, pg_cron, seed.
- Diseño de locks (D46 sigue vigente).
- Invariante de orden de locks v1.5.
- Cast `::INTEGER` en SQL ejecutable v1.6.
- Tests, decisiones D1-D46, bitácora del Bloque 13.

### Estado en Supabase DEV (al momento de generar v1.6.1)

Idéntico a v1.6:
- Bloque 13 ejecutado y verificado en DEV (corregido vía `CREATE OR REPLACE` durante ejecución real).
- Bloques 14-22 pendientes de ejecución. Nacen correctos desde v1.6 / v1.6.1 (idéntico SQL).

---

## RESUMEN DE CAMBIOS v1.5 → v1.6

Versión quirúrgica que corrige un bug detectado durante la ejecución real del Bloque 13 en Supabase DEV. Cero cambios de schema, cero features nuevas, cero cambios de diseño de locks.

### Bug detectado en DEV

Durante la ejecución del Bloque 13 (`crear_prereserva`) en Supabase DEV con PostgreSQL 17.6, la función falló en runtime con:

```
ERROR 42883: function pg_advisory_xact_lock(integer, bigint) does not exist
HINT: No function matches the given name and argument types.
QUERY: SELECT pg_advisory_xact_lock(1, v_id_cabana)
CONTEXT: PL/pgSQL function crear_prereserva(jsonb) line 178 at PERFORM
```

### Causa raíz

PostgreSQL provee solo dos sobrecargas de `pg_advisory_xact_lock`:

- `pg_advisory_xact_lock(bigint)` — 1 argumento.
- `pg_advisory_xact_lock(integer, integer)` — 2 argumentos del mismo tipo.

**No existe** la variante `(integer, bigint)`. El lock global `pg_advisory_xact_lock(10, 0)` funciona porque ambos literales se infieren como `integer`. El lock por cabaña `pg_advisory_xact_lock(1, v_id_cabana)` falla porque `v_id_cabana` está declarada como `BIGINT` (consistente con `id_cabana` que es `BIGSERIAL` en `cabanas`).

### Corrección aplicada en v1.6

Cast explícito a `INTEGER` en el segundo argumento del lock por cabaña, en las 3 funciones afectadas:

| Bloque | Función | Línea afectada | Cambio |
|---|---|---|---|
| 13 | `crear_prereserva` | `PERFORM pg_advisory_xact_lock(1, v_id_cabana)` | → `... v_id_cabana::INTEGER` |
| 14 | `confirmar_reserva` | `PERFORM pg_advisory_xact_lock(1, v_pre.id_cabana)` | → `... v_pre.id_cabana::INTEGER` |
| 16 | `crear_bloqueo` | `PERFORM pg_advisory_xact_lock(1, v_id_cabana)` | → `... v_id_cabana::INTEGER` |

El cast es seguro porque `id_cabana` en Vita Delta nunca va a superar el rango `INTEGER` (~2.1 mil millones), y `pg_advisory_xact_lock` usa el segundo argumento como identificador de lock, no como dato de negocio.

### Nota técnica agregada en Sección 15

Se documenta el por qué del cast para que cualquiera que rehaga el schema desde cero no se tope con el mismo error.

### Estado en Supabase DEV (al momento de generar v1.6)

- **Bloque 13** ya fue ejecutado y corregido vía `CREATE OR REPLACE FUNCTION` en DEV. Verificado con los 9 checks del bloque (T-PR-1 a T-PR-9). Bitácora commiteada en `Docs/Bitacora/6B_EJECUCION_DEV.md`.
- **Bloques 14, 15, 16, 17, 18, 19, 20, 21, 22** todavía NO fueron ejecutados. Cuando se ejecuten desde v1.6, nacen correctos.
- **No se re-ejecuta el Bloque 13.** El documento v1.6 queda como fuente de verdad para próximos bloques, recreación futura de DEV, ejecución en TEST y ejecución futura en PROD.

### Lo que NO cambió respecto a v1.5

- Schema, constraints, EXCLUDE, tablas, enums, vistas, triggers, pg_cron, seed.
- Diseño de locks (D46 sigue vigente: lock global `(10, 0)` antes que cualquier otro lock).
- Invariante de orden de locks (v1.5).
- `upsert_huesped`, `validar_disponibilidad`, `obtener_disponibilidad_rango`, `cancelar_prereserva`, `registrar_pago`, `expirar_prereservas_vencidas` (no toman lock por cabaña).
- Tests (los tests del Bloque 13 ya quedaron documentados como pasados en bitácora; los demás se ejecutan tal cual).
- Decisiones D1-D46 (sin agregar D47; v1.6 es corrección de implementación, no decisión nueva).

---

## RESUMEN DE CAMBIOS v1.4 → v1.5

Versión quirúrgica enfocada en cerrar el último hueco de concurrencia detectado. Cero cambios de schema, cero features nuevas, cero motor de precios.

### Problema detectado en v1.4

En `confirmar_reserva()` el orden de locks era:

```
1. SELECT ... FOR UPDATE sobre pre_reservas    -- row lock
2. pg_advisory_xact_lock(10, 0)                -- global
3. pg_advisory_xact_lock(1, v_pre.id_cabana)   -- por cabaña
```

`SELECT ... FOR UPDATE` toma un row-level lock que PostgreSQL incluye en su grafo de detección de deadlocks. Si `cancelar_prereserva` (que en v1.4 toma global PRIMERO y después FOR UPDATE) corría en paralelo sobre la misma pre-reserva, podía generarse un deadlock cruzado:

| T+ | `confirmar_reserva` (A) | `cancelar_prereserva` (B) |
|---|---|---|
| 0 | toma row lock de pre_reserva X | — |
| 1 | — | toma lock global (10, 0) |
| 2 | espera global (lo tiene B) | espera row lock de X (lo tiene A) |

PostgreSQL detecta el deadlock en ~1s y aborta una transacción. No corrompe datos pero genera errores ruidosos al operador.

### Solución v1.5 — Invariante de locks fortalecida

La invariante anterior decía: "lock global antes del lock por cabaña". La invariante de v1.5 dice:

> **Todo lock — advisory, row-level (`SELECT ... FOR UPDATE`), o table-level — debe tomarse después del lock global `pg_advisory_xact_lock(10, 0)`.**

Orden generalizado:

```
1. PERFORM pg_advisory_xact_lock(10, 0);   -- SIEMPRE primero
2. SELECT ... FOR UPDATE (si aplica)       -- row locks después
3. PERFORM pg_advisory_xact_lock(1, X);    -- por cabaña si aplica
4. Validaciones
5. INSERT/UPDATE
```

### Cambios aplicados

1. **Bloque 14 (`confirmar_reserva`):** se reordenan los locks. El lock global pasa a ser lo PRIMERO que se hace después de extraer y validar el payload, antes del `SELECT ... FOR UPDATE` de la pre-reserva. El lock por cabaña sigue siendo después del SELECT (necesita `v_pre.id_cabana`). **El contrato del payload NO cambia.**

2. **Comentario inline de invariante actualizado en las 4 funciones críticas** (`crear_prereserva`, `confirmar_reserva`, `cancelar_prereserva`, `crear_bloqueo`). Texto unificado que aclara: "antes de cualquier lock — advisory, FOR UPDATE o table-level".

3. **Sección 15** actualizada con la invariante fortalecida.

4. **Sección 9 (Capa 0)** actualizada con la invariante fortalecida.

5. **Comentario en `validar_disponibilidad()` (Observación G):** se agrega advertencia explícita de que la función usa `SELECT ... FOR UPDATE` internamente y debe llamarse SOLO desde funciones que ya tomaron `pg_advisory_xact_lock(10, 0)`. Si alguien la llama en un flujo crítico sin lock global previo, puede reintroducir problemas de concurrencia.

6. **Limpieza documental:** referencias históricas a `LOCK TABLE` en D1, D25, dudas resueltas y resúmenes anteriores marcadas como "reemplazada por D46 en v1.4". Sin borrar historial.

### Lo que NO cambió respecto a v1.4

- Schema, constraints, EXCLUDE, tablas, enums, vistas.
- `upsert_huesped`, `obtener_disponibilidad_rango`.
- `crear_prereserva`, `cancelar_prereserva`, `crear_bloqueo` (ya tenían el orden correcto en v1.4).
- `registrar_pago`, `expirar_prereservas_vencidas` (siguen sin tomar lock global).
- Triggers, pg_cron, seed.
- Sin nueva decisión en la tabla de decisiones (es una corrección de implementación de D46, no una decisión nueva).

---

## RESUMEN DE CAMBIOS v1.3 → v1.4

Versión quirúrgica enfocada exclusivamente en concurrencia. Cero cambios de schema, cero features nuevas, cero motor de precios. Toda la modificación se concentra en la estrategia de locks.

### Problema detectado en v1.3

La mezcla de `pg_advisory_xact_lock(1, id_cabana)` y `LOCK TABLE` no se coordinaba entre sí. Dos mecanismos independientes de PostgreSQL pueden intercalarse y producir:
- Pre-reserva vigente y bloqueo total solapados.
- Bloqueo específico y bloqueo total solapados.
- Falsos conflictos operativos cuando una cancelación corre en paralelo con un bloqueo.

### Solución v1.4 — Capa 0: Lock global de disponibilidad

Se introduce un **advisory lock global** que toda función que afecte disponibilidad debe tomar PRIMERO, antes de cualquier lock por cabaña. Convención obligatoria:

| Namespace | Key | Uso |
|---|---|---|
| `10` | `0` | **Lock global de disponibilidad** (siempre primero) |
| `1` | `id_cabana` | Lock específico por cabaña (siempre después del global) |

### Orden obligatorio en funciones críticas

```
1. pg_advisory_xact_lock(10, 0)         -- SIEMPRE primero
2. pg_advisory_xact_lock(1, id_cabana)  -- Si aplica, después del global
3. Validaciones (validar_disponibilidad, etc.)
4. INSERT/UPDATE
```

Romper este orden puede causar deadlocks. La invariante se documenta como comentario inline obligatorio en cada función afectada.

### Cambios aplicados

1. **Sección 9 (Estrategia anti-double-booking):** se agrega "Capa 0 — Lock global" antes de las 4 capas existentes. Las capas se renumeran a Capa 0, 1, 2, 3, 4, 5.

2. **Sección 15 (Advisory locks):** redefinida con la nueva convención. Documentada la invariante de orden.

3. **Bloque 13 (`crear_prereserva`):** toma primero `pg_advisory_xact_lock(10, 0)`, después `pg_advisory_xact_lock(1, v_id_cabana)`. La idempotencia post-lock (v1.3) se mantiene; ahora corre después de ambos locks.

4. **Bloque 14 (`confirmar_reserva`):** toma primero el lock global, después el lock por cabaña.

5. **Bloque 15 (`cancelar_prereserva`):** Q1 confirmado — lock global obligatorio agregado, aunque no haya lock por cabaña. Evita falsos conflictos cuando un bloqueo paralelo evalúa la pre-reserva durante su cancelación.

6. **Bloque 16 (`crear_bloqueo`):** Q5 confirmado — **se quita `LOCK TABLE`**. Se reemplaza por `pg_advisory_xact_lock(10, 0)` al inicio. Si es específico, después toma `pg_advisory_xact_lock(1, v_id_cabana)`. Las validaciones manuales se mantienen como antes.

7. **Tabla de decisiones:** D46 agregada — "Advisory lock global de disponibilidad para serializar operaciones críticas".

### Funciones que NO toman lock global (Q2 y Q3 confirmados)

- **`registrar_pago()`** — Q3: no afecta disponibilidad efectiva. El ajuste P2 de v1.3 ya cubre pagos sobre pre-reservas terminales con warning. Serializar pagos con disponibilidad sería sobre-bloqueo.
- **`expirar_prereservas_vencidas()`** — Q2: solo procesa pre-reservas que ya no bloquean disponibilidad lógica (`expira_en <= NOW()`). Usa `FOR UPDATE SKIP LOCKED`. Tomar lock global serializaría el cron contra todo el sistema cada 5 minutos.

### Lo que NO cambió respecto a v1.3

- Schema, constraints, EXCLUDE, tablas, enums, vistas.
- `upsert_huesped`, `validar_disponibilidad`, `obtener_disponibilidad_rango`.
- `normalizar_telefono`, triggers, pg_cron, seed.
- Las validaciones manuales en `crear_bloqueo` (siguen presentes; ahora son seguras porque el lock global garantiza serialización).
- Lógica de idempotencia (los 3 caminos `recovery_path` se mantienen, pero ahora corren después de ambos locks).
- Validación de huésped (nombre/contacto), P2 sobre pagos, todo el resto de v1.3.

---

## RESUMEN DE CAMBIOS v1.2 → v1.3

Versión quirúrgica con 5 ajustes finales antes de ejecutar. No se rediseña arquitectura. Todos los cambios se concentran en `crear_prereserva()` y `registrar_pago()`.

### Ajustes en `crear_prereserva()`

1. **Double-check de idempotencia después del advisory lock (P3 / Ajuste crítico 1).** Cierra el agujero "lost-update-by-availability": si entre el chequeo inicial sin lock y la toma del lock otro request creó la pre-reserva con la misma `idempotency_key`, este request ya no devuelve `no_disponible` falso. Re-chequea después del lock y devuelve la existente con `recovery_path:'post_lock'`.

2. **Validación explícita de nombre y contacto del huésped (P1 / Ajuste crítico 2).** Antes de llamar a `upsert_huesped`, valida que venga `TRIM(huesped.nombre)` no vacío y al menos uno entre `telefono` o `email`. Errores nuevos: `huesped_nombre_requerido`, `huesped_contacto_requerido`. `upsert_huesped` queda flexible para otros callers (bot, consultas).

3. **Estructura de retorno unificada con `recovery_path` (P3 / Observación D).** Reemplaza los flags `recovered_after_lock:true` y `recovered:true` por un único campo `recovery_path` con 3 valores: `pre_lock`, `post_lock`, `unique_violation`. Para creación normal: `idempotent_match:false`, `recovery_path:null`.

### Ajustes en `registrar_pago()`

4. **Pago sobre pre-reserva no activa: forzar `en_revision` + warning (P2 / Ajuste menor 4).** Si la pre-reserva referenciada está en estados terminales (`vencida`, `cancelada_por_cliente`, `cancelada_por_bloqueo`, `conflicto_pendiente`):
   - El pago se registra forzosamente en estado `en_revision` (ignora `estado_inicial='confirmado'` del payload).
   - **No** reactiva la pre-reserva.
   - **No** modifica el estado de la pre-reserva.
   - Devuelve `warning:'prereserva_no_activa'` + `prereserva_estado` en el JSON.
   - Registra log nivel `warning` en `log_cambios`.

### Ajustes de documentación (sin SQL)

5. **Aclaración sobre config inválida en Bloque 13 (Ajuste menor 3).** Se documenta que `COALESCE` cubre solo claves ausentes, no valores mal escritos o no casteables (ej. `hora_checkin_default = 'no_es_hora'` arrojaría error técnico). Se confirma que es aceptable para v1.3 porque la edición de `configuracion_general` se hace con cuidado o futuras UIs validadas.

6. **Aclaración operativa sobre pagos tardíos en pre-reservas convertidas (P2 nota extra).** Se documenta como criterio que si una pre-reserva está `convertida`, el pago tardío debería asociarse preferentemente a `id_reserva`. No se implementa lógica adicional; queda como guía operativa para n8n.

### Lo que NO cambió respecto a v1.2

- Arquitectura general, schema, constraints, EXCLUDE.
- `upsert_huesped`, `validar_disponibilidad`, `obtener_disponibilidad_rango`.
- `confirmar_reserva`, `cancelar_prereserva`, `crear_bloqueo`, `expirar_prereservas_vencidas`.
- Triggers, vistas, pg_cron.
- Seed.

---

## RESUMEN DE CAMBIOS v1.1 → v1.2

Versión quirúrgica con 9 ajustes pedidos por Franco + 3 observaciones menores de Claude. No se rediseña arquitectura ni se agregan features fuera de alcance.

### Correcciones de seed

1. **Capacidades de cabañas corregidas** en Bloque 21. Las grandes (Bamboo, Madre Selva, Arrebol) tienen `capacidad_base=3, capacidad_max=5`. Las chicas (Guatemala, Tokio) tienen `capacidad_base=2, capacidad_max=4`. Error de carga de v1.1.

### Funciones — endurecimiento de validaciones

2. **`crear_bloqueo()` ahora valida conflictos con pre-reservas vigentes** antes de crear el bloqueo (específico o total). Estados verificados: `pendiente_pago` con `expira_en > NOW()` y `pago_en_revision`. Devuelve `error='conflicto_con_prereserva'` con lista de IDs si hay conflicto.

3. **`crear_bloqueo()` ahora valida bloqueos solapados manualmente** para las 3 combinaciones que el EXCLUDE no cubre: total vs total, total vs específico, específico vs total. Devuelve `error='bloqueo_solapado'` con lista de IDs si hay conflicto.

4. **`crear_prereserva()` idempotencia robusta:** cuando el INSERT falla por `unique_violation` por `idempotency_key`, ahora busca la pre-reserva activa con esa key y devuelve `ok:true, idempotent_match:true, ...` en vez de error técnico. Solo si no encuentra match devuelve error.

5. **`upsert_huesped()` maneja `unique_violation` de forma diferenciada:**
   - Conflicto por `telefono_normalizado` o `email`: recuperación silenciosa. Vuelve a buscar y devuelve `modo='recovered_from_unique_violation'` con el huésped existente.
   - Conflicto por `DNI`: devuelve `error='huesped_duplicado'` con `conflicto='dni'` y `id_huesped_existente` para revisión humana.

### Funciones — uso de configuración

6. **`crear_prereserva()` lee horarios y expiración desde `configuracion_general`** vía 1 SELECT agrupado en JSONB. Fallback con `COALESCE` a valores hardcodeados si faltan claves. Log warning compacto (1 fila con lista de claves faltantes, no 1 por clave) si hay claves ausentes.

### Funciones — contexto de logs

7. **4 funciones ahora setean `app.modificado_por` y `app.source_event`** vía `set_config(..., true)` antes de UPDATEs de estado, para que los triggers de log automático tengan contexto preciso en lugar de `trigger_auto` / `estado_change`:
   - `confirmar_reserva()`
   - `cancelar_prereserva()`
   - `registrar_pago()`
   - `expirar_prereservas_vencidas()` (set una vez al inicio del loop)

### Documentación

8. **Sección nueva en Parte A:** "Semántica de `pago_en_revision` en pre-reservas". Aclara los dos sub-casos (pago recibido pendiente de validar / pago confirmado pendiente de conversión) y que en ambos casos la pre-reserva ya no expira por TTL.

9. **Sección 18 (motor de precios) reforzada:** `consultar_disponibilidad_precio` pasa de "candidato fuerte a migrar" a **pieza obligatoria** antes de la web pública. Tono de decisión cerrada, no idea vaga.

### Observaciones menores aplicadas

- **Obs A** — Convención de nombres con punto (`app.modificado_por`) confirmada como compatible con `set_config`.
- **Obs B** — Documentado que el bloqueo total depende de la validación manual + `LOCK TABLE`, no hay defensa estructural (porque el EXCLUDE no aplica con `id_cabana IS NULL`). *Nota v1.5: `LOCK TABLE` fue reemplazado por el advisory lock global `(10, 0)` en v1.4 (D46). El bloqueo total sigue dependiendo del lock global + validaciones manuales, no del schema.*
- **Obs C** — Tests funcionales de Bloques 10 y 13 ahora usan teléfonos distintos para poder correrse en secuencia.

### Lo que NO cambió respecto a v1.1

- Toda la arquitectura general.
- Schema de tablas (excepto seed de cabañas).
- Constraints (excepto los chequeos manuales agregados en `crear_bloqueo`).
- Estrategia anti-double-booking (Capas 1-4).
- Convención de advisory locks.
- Triggers (excepto que ahora reciben contexto preciso).
- Vistas SQL.
- Schedule de pg_cron.

---

## RESUMEN DE CAMBIOS v1.0 → v1.1

Esta versión incorpora 17 ajustes derivados de la revisión técnica de Franco y de las observaciones críticas de Claude. Cambios principales:

### Estructura de tablas

1. **`pagos.id_prereserva` ahora es nullable.** Constraint `CHECK (id_prereserva IS NOT NULL OR id_reserva IS NOT NULL)` garantiza que toda fila tiene al menos una referencia. Permite pagos asociados directamente a reservas administrativas sin pre-reserva previa.

2. **`huespedes.telefono_normalizado` agregada como columna.** Mantenida por trigger `BEFORE INSERT/UPDATE` invocando `normalizar_telefono()`. El índice único de teléfono se mueve de `telefono` raw a `telefono_normalizado`.

3. **`pre_reservas.idempotency_key` agregada como columna opcional.** Índice único parcial sobre estados activos (`pendiente_pago`, `pago_en_revision`). Previene duplicados por doble click, reintentos de red o timeouts.

### Funciones transaccionales nuevas

4. **`crear_prereserva(payload JSONB)` agregada.** Función almacenada que es la puerta única para crear pre-reservas. Resuelve huésped vía `upsert_huesped`, toma advisory lock por cabaña, valida disponibilidad, inserta. Soporta `idempotency_key`.

5. **`confirmar_reserva(payload JSONB)` agregada.** Verifica pre-reserva, revalida disponibilidad, valida pago, crea reserva, copia campos operativos, actualiza huésped. Soporta `permitir_pago_en_revision`.

6. **`cancelar_prereserva(payload JSONB)` agregada.** Cancela con motivo y devuelve cantidad de pagos asociados.

7. **`crear_bloqueo(payload JSONB)` agregada.** Rechaza bloqueos que pisen reservas confirmadas/activas. Para bloqueo total usa `LOCK TABLE` simple. *Nota v1.5: `LOCK TABLE` fue reemplazado en v1.4 por advisory lock global `(10, 0)` (D46).*

8. **`registrar_pago(payload JSONB)` agregada.** Cubre pagos manuales, MercadoPago, transferencia, cripto, efectivo. No exige `monto_recibido = monto_esperado`.

9. **`normalizar_telefono(input TEXT)` agregada como helper IMMUTABLE.**

### Funciones documentadas como futuras (no implementadas)

10. **`cancelar_reserva()`** queda documentada como función futura por su complejidad (reembolsos, cargos, decisiones comerciales).

11. **`modificar_reserva()`** queda documentada como función futura.

### Triggers y manejo de errores

12. **Triggers AFTER INSERT eliminados del diseño.** Los logs de creación se hacen DENTRO de las funciones críticas (no como triggers genéricos). Triggers conservados: solo `updated_at` y cambios de estado.

13. **Manejo controlado de `exclusion_violation` (23P01)** en todas las funciones que insertan en `reservas`. Devuelven JSONB con error semántico en lugar de fallar abruptamente.

### Advisory locks

14. **Convención de advisory locks documentada.** Namespace `1` para operaciones por cabaña específica. Bloqueo total usa `LOCK TABLE EXCLUSIVE` (decisión D1 — camino simple). *Nota v1.5: reemplazado en v1.4 por D46 (advisory lock global `(10, 0)`). `LOCK TABLE` ya no se usa.*

### Correcciones puntuales

15. **`vista_disponibilidad`** ahora castea correctamente `CURRENT_DATE + 60` (era bug con INTERVAL).

16. **Comentarios inline sobre `tipo_override`** explican trazabilidad a Etapa 2 v1.3 y Etapa 5A v1.1.

17. **Seed inicial** marca placeholders explícitamente: `Socio 3` como placeholder, cuenta de cobro inactiva, tarifas/feriados no productivos, temporada baseline solo para evitar gaps en DEV.

### Secciones nuevas en Parte A

- **Carga manual segura**
- **El escalonamiento es feature apagable**
- **Horarios: lo que pide el cliente y lo que ve el equipo**
- **Motor de precios — decisión transitoria**
- **Contabilidad futura — contemplada, no implementada**
- **Advisory locks — convención**

---

## ÍNDICE

### PARTE A — Diseño explicado

1. Resumen ejecutivo del schema
2. Convenciones globales
3. Extensiones PostgreSQL necesarias
4. Enums definidos
5. Catálogo de tablas
6. Relaciones entre tablas
7. Constraints CHECK consolidados
8. Constraints UNIQUE consolidados
9. Estrategia anti-double-booking
10. Funciones críticas
11. Triggers automáticos
12. Vistas SQL
13. División de responsabilidades n8n / PostgreSQL
14. Uso de pg_cron
15. Advisory locks — convención
16. Horarios: lo que pide el cliente y lo que ve el equipo
17. El escalonamiento es feature apagable
18. Semántica de `pago_en_revision` en pre-reservas *(nuevo en v1.2)*
19. Motor de precios — decisión transitoria y pieza obligatoria futura
20. Carga manual segura
21. Contabilidad futura — contemplada, no implementada
22. Decisiones tomadas y registradas
23. Dudas que quedaron resueltas

### PARTE B — SQL ejecutable propuesto para revisión

- Bloque 1. Extensiones
- Bloque 2. Enums
- Bloque 3. Tablas catálogo
- Bloque 4. Tablas de configuración
- Bloque 5. Tablas dependientes nivel 1
- Bloque 6. Tablas transaccionales
- Bloque 7. Tabla de auditoría
- Bloque 8. Constraints EXCLUDE
- Bloque 9. Función `normalizar_telefono` + columna `telefono_normalizado` + trigger
- Bloque 10. Función `upsert_huesped`
- Bloque 11. Función `validar_disponibilidad`
- Bloque 12. Función `obtener_disponibilidad_rango`
- Bloque 13. Función `crear_prereserva`
- Bloque 14. Función `confirmar_reserva`
- Bloque 15. Función `cancelar_prereserva`
- Bloque 16. Función `crear_bloqueo`
- Bloque 17. Función `registrar_pago`
- Bloque 18. Función `expirar_prereservas_vencidas`
- Bloque 19. Triggers automáticos
- Bloque 20. Vistas SQL
- Bloque 21. Datos seed mínimos
- Bloque 22. Schedule de pg_cron

---

# PARTE A — DISEÑO EXPLICADO

## 1. RESUMEN EJECUTIVO DEL SCHEMA

El schema implementa el modelo de datos cerrado en Etapa 5A sobre PostgreSQL, con las siguientes diferencias estructurales respecto al modelo en Sheets:

**Cambios significativos respecto a Sheets:**

- `DISPONIBILIDAD_CACHE` deja de ser tabla. Se reemplaza por funciones SQL y una vista.
- Constraint de exclusión (`EXCLUDE USING gist`) garantiza estructuralmente que no puede haber double booking en `reservas` y `bloqueos`.
- 8 funciones almacenadas en PostgreSQL encapsulan lógica crítica antes dispersa en n8n.
- Triggers automáticos manejan `updated_at` y logs de cambios de estado.
- Pre-reservas se crean exclusivamente vía `crear_prereserva()` con advisory lock; nunca por INSERT directo.

**Tablas totales:** 20 tablas.

**Vistas SQL:** 6 vistas operativas (incluyendo dos nuevas para los Sistemas 3 y 4 mencionados por Franco).

**Funciones:** 9 funciones críticas (8 transaccionales + 1 helper IMMUTABLE para normalización de teléfono).

**Principios rectores:**

- PostgreSQL es responsable de la verdad y la integridad.
- n8n es responsable de la orquestación y la comunicación externa.
- Las tablas críticas no se editan directamente; toda escritura pasa por funciones almacenadas.
- Los errores esperables se devuelven como JSONB controlado, no como excepciones crudas de PostgreSQL.

---

## 2. CONVENCIONES GLOBALES

### Naming

| Elemento | Convención | Ejemplo |
|---|---|---|
| Tabla | `lowercase_snake_case`, plural | `pre_reservas`, `cabanas` |
| Columna | `lowercase_snake_case` | `fecha_checkin`, `id_huesped` |
| Foreign key | `id_<entidad_singular>` | `id_cabana`, `id_huesped` |
| Primary key | `id_<entidad_singular>` | `id_pre_reserva` |
| CHECK | `chk_<tabla>_<descripcion>` | `chk_pre_reservas_fechas_validas` |
| UNIQUE | `uq_<tabla>_<columnas>` | `uq_cabanas_nombre` |
| EXCLUDE | `exc_<tabla>_<descripcion>` | `exc_reservas_no_overlap` |
| Index | `idx_<tabla>_<columnas>` | `idx_reservas_fecha_checkin` |
| Enum type | `<nombre>_enum` | `estado_reserva_enum` |
| Function | `<verbo>_<objeto>` | `crear_prereserva`, `upsert_huesped` |
| View | `vista_<descripcion>` | `vista_calendario_semanal` |
| Trigger | `trg_<tabla>_<evento>` | `trg_pre_reservas_updated_at` |

### Tipos PostgreSQL

| Tipo lógico | Tipo PostgreSQL | Notas |
|---|---|---|
| ID autoincremental | `BIGSERIAL PRIMARY KEY` | |
| Fecha (sin hora) | `DATE` | Formato YYYY-MM-DD |
| Hora (sin fecha) | `TIME` | Formato HH:MM:SS |
| Timestamp con zona | `TIMESTAMPTZ` | Almacena UTC, convierte en consulta |
| Booleano | `BOOLEAN` | TRUE/FALSE |
| Monto | `NUMERIC(12,2)` | Margen para decimales, comisiones |
| Decimal de precisión | `NUMERIC(5,3)` | Multiplicadores de temporada |
| Porcentaje | `NUMERIC(5,2)` | 0.00 a 100.00 |
| Texto corto/largo | `TEXT` | Sin distinción de longitud |
| JSON estructurado | `JSONB` | Para campos JSON internos |
| Rango de fechas | `daterange` | Para constraint de no-overlap |

### Convenciones de valores

- Booleanos: `TRUE`/`FALSE` nativos.
- Fechas: ISO `YYYY-MM-DD`.
- Timestamps: ISO 8601 con `Z` o `+00:00` (UTC).
- Strings vacíos: usar `NULL`, nunca `''`.
- Montos: NUMERIC con 2 decimales.

### Convención de payload de funciones

Todas las funciones transaccionales reciben un único parámetro `payload JSONB` y devuelven un `JSONB` con estructura mínima:

```
{
  "ok":     boolean,
  "error":  string | null,
  "motivo": string | null,
  ... datos específicos de la función
}
```

Cuando `ok=false`, hay un `error` semántico (ej: `cabana_invalida`, `no_disponible`, `precio_requerido`). Cuando `ok=true`, hay datos útiles para n8n (ej: `id_pre_reserva`, `id_reserva`).

---

## 3. EXTENSIONES POSTGRESQL NECESARIAS

| Extensión | Propósito | Estado en Supabase Free |
|---|---|---|
| `btree_gist` | Combina índices btree con gist. Necesaria para `EXCLUDE` con `id_cabana WITH =, daterange WITH &&`. | Disponible. |
| `pg_cron` | Ejecutar funciones SQL en intervalo. | Disponible en free tier (todas las plans). |

**Notas operacionales sobre pg_cron en Supabase free:**

- Habilitado en todos los planes.
- Intervalo mínimo: 1 minuto.
- Todo schedule corre en UTC.
- Historial en `cron.job_run_details` crece indefinidamente. Se incluye job mensual de limpieza.
- Si la función dura más que el intervalo, pg_cron lanza la siguiente ejecución igual. Se mitiga aumentando intervalo o usando advisory lock.
- En free tier, si el proyecto se pausa por inactividad (más de 7 días), los crons no corren. No problema para Vita Delta (uso diario).

---

## 4. ENUMS DEFINIDOS

Siguiendo el criterio aprobado, solo enums para estados estables. Para el resto, `TEXT` (con `CHECK` cuando aplica).

### Enums (4 tipos)

| Enum | Valores | Justificación |
|---|---|---|
| `estado_prereserva_enum` | `pendiente_pago`, `pago_en_revision`, `vencida`, `convertida`, `cancelada_por_cliente`, `cancelada_por_bloqueo`, `conflicto_pendiente` | Estados estables del ciclo de vida de pre-reserva. |
| `estado_reserva_enum` | `confirmada`, `activa`, `completada`, `cancelada`, `cancelada_con_cargo`, `conflicto_pendiente` | Estados estables del ciclo de vida de reserva. |
| `estado_pago_enum` | `pendiente`, `en_revision`, `confirmado`, `rechazado`, `reembolsado` | Estados estables de pago. |
| `nivel_log_enum` | `info`, `warning`, `error` | Niveles estándar de logging. |

### Campos TEXT con CHECK (listas cerradas)

| Tabla | Columna | Valores permitidos |
|---|---|---|
| `consultas` | `canal` | `whatsapp`, `instagram`, `web`, `manual` |
| `consultas` | `estado_conversacion` | `nueva`, `en_progreso`, `derivada_humano`, `cerrada`, `descartada` |
| `pre_reservas` | `canal_origen` | `whatsapp`, `instagram`, `web`, `manual` |
| `pre_reservas` | `canal_pago_esperado` | `transferencia_bancaria`, `transferencia_mp`, `mp_link`, `cripto`, `efectivo` |
| `reservas` | `canal_origen` | `whatsapp`, `instagram`, `web`, `manual`, `airbnb`, `booking` |
| `pagos` | `tipo` | `sena`, `saldo`, `extra`, `reembolso`, `ajuste` |
| `pagos` | `medio_pago` | `transferencia_bancaria`, `transferencia_mp`, `mp_link`, `cripto`, `efectivo` |
| `bloqueos` | `motivo` | `mantenimiento`, `uso_propio`, `tormenta`, `overbooking`, `otro` |
| `overrides_operativos` | `tipo_override` | Lista de Etapa 2 v1.3 (ver comentario inline en SQL) |
| `descuentos` | `tipo` | `porcentaje`, `monto_fijo`, `noche_gratis` |
| `descuentos` | `aplica_a` | `todas`, `grande`, `chica` |
| `descuentos` | `aplica_sobre` | `alojamiento`, `extras`, `total` |
| `plantillas_mensajes` | `canal` | `whatsapp`, `instagram`, `todos` |
| `plantillas_mensajes` | `destinatario` | `huesped`, `equipo`, `limpieza`, `franco` |
| `cuentas_cobro` | `medio` | `transferencia_bancaria`, `transferencia_mp`, `cripto`, `efectivo` |

### Campos TEXT libres (sin CHECK)

- `cabanas.tipo` (admite agregar tipos futuros sin migrar).
- `tarifas.concepto` (motor de precios decide qué consume).
- `feriados.tipo` (orientativos: nacional/provincial/local/puente/especial).
- `gastos.categoria` (orientativos: limpieza/mantenimiento/servicios/etc.).
- `source_event` (todas las tablas — evoluciona).
- `created_by`, `modificado_por` (TEXT libre, sin tabla usuarios).
- `notas`, `descripcion`, `motivo`, `nombre`.


---

## 5. CATÁLOGO DE TABLAS

20 tablas en total. Ordenadas por dependencias.

### Grupo 1 — Catálogo (sin dependencias entre sí)

| # | Tabla | Origen Sheets | Cambios |
|---|---|---|---|
| 1 | `cabanas` | CABAÑAS | Sin `bloqueada`/`motivo_bloqueo` (se reemplaza por `bloqueos`). |
| 2 | `huespedes` | HUÉSPEDES | **+1 columna:** `telefono_normalizado` (mantenida por trigger). |
| 3 | `feriados` | FERIADOS | Sin cambio. |
| 4 | `tarifas` | TARIFAS | Sin cambio. |
| 5 | `temporadas` | TEMPORADAS | Sin cambio. |
| 6 | `socios` | SOCIOS | Sin cambio. |
| 7 | `cuentas_cobro` | CUENTAS_COBRO | Sin cambio. |
| 8 | `plantillas_mensajes` | PLANTILLAS_MENSAJES | Sin cambio. |

### Grupo 2 — Configuración

| # | Tabla | Origen Sheets | Cambios |
|---|---|---|---|
| 9 | `configuracion_general` | CONFIGURACION_GENERAL | Sin cambio. |
| 10 | `eventos_especiales` | EVENTOS_ESPECIALES | Sin cambio. |
| 11 | `paquetes_evento` | PAQUETES_EVENTO | FK obligatoria a `eventos_especiales`. |
| 12 | `descuentos` | DESCUENTOS | Sin cambio. |

### Grupo 3 — Transaccional

| # | Tabla | Origen Sheets | Cambios |
|---|---|---|---|
| 13 | `consultas` | CONSULTAS | Sin cambio. |
| 14 | `pre_reservas` | PRE_RESERVAS | **+5 columnas:** `mascotas`, `detalle_mascotas`, `ninos`, `notas_reserva`, `idempotency_key`. |
| 15 | `reservas` | RESERVAS | **+4 columnas:** `mascotas`, `detalle_mascotas`, `ninos`, `notas_reserva`. |
| 16 | `pagos` | PAGOS | `id_prereserva` nullable, `id_reserva` nullable, CHECK que al menos uno exista. |
| 17 | `bloqueos` | BLOQUEOS | Sin cambio. |
| 18 | `overrides_operativos` | OVERRIDES_OPERATIVOS | Sin cambio. |
| 19 | `gastos` | GASTOS | Sin cambio. |

### Grupo 4 — Auditoría

| # | Tabla | Origen Sheets | Cambios |
|---|---|---|---|
| 20 | `log_cambios` | LOG_CAMBIOS | `detalle` pasa de TEXT a `JSONB`. |

### Tabla que NO se migra

| Tabla original | Por qué no se migra |
|---|---|
| `DISPONIBILIDAD_CACHE` | Reemplazada por funciones (`validar_disponibilidad`, `obtener_disponibilidad_rango`) y vista (`vista_disponibilidad`). |

---

## 6. RELACIONES ENTRE TABLAS

### Diagrama de FK

```
cabanas (1) ────┬───── reservas (N)
                ├───── pre_reservas (N)
                ├───── bloqueos (N)               [id_cabana nullable]
                ├───── overrides_operativos (N)   [id_cabana nullable]
                └───── gastos (N)                 [id_cabana nullable]

huespedes (1) ──┬───── reservas (N)
                ├───── pre_reservas (N)
                └───── consultas (N)              [id_huesped nullable]

consultas (1) ──── pre_reservas (N)               [id_consulta nullable]

pre_reservas (1) ──┬── reservas (N)               [id_pre_reserva en reservas, nullable]
                   └── pagos (N)                  [id_prereserva en pagos, nullable]

reservas (1) ──── pagos (N)                       [id_reserva en pagos, nullable]

tarifas (1) ──── reservas (N)                     [id_tarifa_aplicada nullable]

eventos_especiales (1) ──── paquetes_evento (N)
```

### Tabla resumen de FKs

**Obligatorias (NOT NULL):**

| Tabla | Columna | Referencia | ON DELETE |
|---|---|---|---|
| `pre_reservas` | `id_cabana` | `cabanas(id_cabana)` | RESTRICT |
| `pre_reservas` | `id_huesped` | `huespedes(id_huesped)` | RESTRICT |
| `reservas` | `id_cabana` | `cabanas(id_cabana)` | RESTRICT |
| `reservas` | `id_huesped` | `huespedes(id_huesped)` | RESTRICT |
| `paquetes_evento` | `id_evento` | `eventos_especiales(id_evento)` | CASCADE |

**Opcionales (nullable) — v1.1 incluye cambio en `pagos`:**

| Tabla | Columna | Referencia | ON DELETE |
|---|---|---|---|
| `pre_reservas` | `id_consulta` | `consultas(id_consulta)` | SET NULL |
| `reservas` | `id_pre_reserva` | `pre_reservas(id_pre_reserva)` | SET NULL |
| `reservas` | `id_tarifa_aplicada` | `tarifas(id_tarifa)` | SET NULL |
| `pagos` | `id_prereserva` | `pre_reservas(id_pre_reserva)` | RESTRICT |
| `pagos` | `id_reserva` | `reservas(id_reserva)` | SET NULL |
| `bloqueos` | `id_cabana` | `cabanas(id_cabana)` | RESTRICT |
| `overrides_operativos` | `id_cabana` | `cabanas(id_cabana)` | RESTRICT |
| `gastos` | `id_cabana` | `cabanas(id_cabana)` | SET NULL |
| `consultas` | `id_huesped` | `huespedes(id_huesped)` | SET NULL |
| `consultas` | `id_cabana_tentativa` | `cabanas(id_cabana)` | SET NULL |

**Razón del ON DELETE RESTRICT:** nunca borrar entidades con dependencias. Si una cabaña se desactiva, se usa `activa = FALSE`.

---

## 7. CONSTRAINTS CHECK CONSOLIDADOS

### Validaciones de fila individual

| # | Tabla | Constraint | Definición |
|---|---|---|---|
| C1 | `cabanas` | `chk_cabanas_capacidad_logica` | `capacidad_base <= capacidad_max` |
| C2 | `cabanas` | `chk_cabanas_capacidad_positiva` | `capacidad_base >= 1 AND capacidad_max >= 1` |
| C3 | `pre_reservas` | `chk_pre_reservas_fechas` | `fecha_out > fecha_in` |
| C4 | `pre_reservas` | `chk_pre_reservas_personas` | `personas >= 1` |
| C5 | `pre_reservas` | `chk_pre_reservas_monto_total` | `monto_total > 0` |
| C6 | `pre_reservas` | `chk_pre_reservas_sena_logica` | `monto_sena >= 0 AND monto_sena <= monto_total` |
| C7 | `reservas` | `chk_reservas_fechas` | `fecha_checkout > fecha_checkin` |
| C8 | `reservas` | `chk_reservas_personas` | `personas >= 1` |
| C9 | `reservas` | `chk_reservas_monto_total` | `monto_total > 0` |
| C10 | `reservas` | `chk_reservas_saldo_logica` | `monto_saldo >= 0 AND monto_saldo <= monto_total` |
| C11 | `bloqueos` | `chk_bloqueos_fechas` | `fecha_hasta > fecha_desde` |
| C12 | `pagos` | `chk_pagos_monto_recibido` | `monto_recibido >= 0` |
| C13 | `pagos` | `chk_pagos_monto_esperado` | `monto_esperado > 0` |
| **C14** | **`pagos`** | **`chk_pagos_referencia_minima`** | **`id_prereserva IS NOT NULL OR id_reserva IS NOT NULL`** *(nuevo en v1.1)* |
| C15 | `temporadas` | `chk_temporadas_multiplicador` | `multiplicador > 0` |
| C16 | `temporadas` | `chk_temporadas_fechas` | `fecha_hasta > fecha_desde` |
| C17 | `tarifas` | `chk_tarifas_precio` | `precio >= 0` |
| C18 | `socios` | `chk_socios_porcentaje` | `porcentaje_utilidades >= 0 AND porcentaje_utilidades <= 100` |
| C19 | `descuentos` | `chk_descuentos_valor_positivo` | `valor > 0` |
| C20 | `descuentos` | `chk_descuentos_fechas` | Vigencia coherente |
| C21 | `huespedes` | `chk_huespedes_contacto_minimo` | `telefono IS NOT NULL OR email IS NOT NULL` |

---

## 8. CONSTRAINTS UNIQUE CONSOLIDADOS

| # | Tabla | Constraint | Detalle |
|---|---|---|---|
| U1 | `cabanas` | `uq_cabanas_nombre` | `UNIQUE(nombre)` |
| U2 | `huespedes` | `uq_huespedes_dni` | `UNIQUE(dni) WHERE dni IS NOT NULL` |
| **U3** | **`huespedes`** | **`uq_huespedes_telefono_normalizado`** | **`UNIQUE(telefono_normalizado) WHERE telefono_normalizado IS NOT NULL`** *(v1.1: índice se mueve de `telefono` raw a `telefono_normalizado`)* |
| U4 | `huespedes` | `uq_huespedes_email` | `UNIQUE(LOWER(email)) WHERE email IS NOT NULL` |
| U5 | `feriados` | `uq_feriados_fecha` | `UNIQUE(fecha)` |
| U6 | `tarifas` | `uq_tarifas_concepto_vigente` | `UNIQUE(tipo_cabana, concepto, valida_desde) WHERE activa = TRUE` |
| U7 | `configuracion_general` | `uq_config_clave` | `UNIQUE(clave)` |
| **U8** | **`pre_reservas`** | **`uq_prereservas_idempotency_activa`** | **`UNIQUE(idempotency_key) WHERE idempotency_key IS NOT NULL AND estado IN ('pendiente_pago', 'pago_en_revision')`** *(nuevo en v1.1)* |

---

## 9. ESTRATEGIA ANTI-DOUBLE-BOOKING

La prevención de double booking vive en PostgreSQL, no en n8n. Estrategia en 5 capas (defensa en profundidad). **En v1.4 se agrega la Capa 0** que serializa todas las operaciones críticas mediante un advisory lock global.

### Capa 0 — Lock global de disponibilidad *(nuevo en v1.4)*

**Toda función que modifique disponibilidad toma SIEMPRE primero el advisory lock global `(10, 0)` antes que cualquier otro lock.**

```sql
PERFORM pg_advisory_xact_lock(10, 0);
```

Esto serializa entre sí a `crear_prereserva`, `confirmar_reserva`, `cancelar_prereserva`, `crear_bloqueo`. Solo una de estas operaciones puede correr a la vez en todo el sistema. A 5 cabañas y volumen bajo, la contención es invisible (milisegundos).

**Razón del cambio:** en v1.3 se usaba `pg_advisory_xact_lock(1, id_cabana)` para operaciones por cabaña y `LOCK TABLE` para bloqueo total. Esos dos mecanismos NO se coordinan entre sí. Un `crear_prereserva` con lock de cabaña podía intercalarse con un `crear_bloqueo` total con `LOCK TABLE`, produciendo pre-reservas y bloqueos solapados. El lock global resuelve el problema porque es el único mecanismo común a todas las operaciones críticas.

**Invariante de orden (obligatorio, fortalecida en v1.5):**

> **Todo lock — advisory, row-level (`SELECT ... FOR UPDATE`), o table-level — debe tomarse DESPUÉS del lock global `pg_advisory_xact_lock(10, 0)`.**

```
1. pg_advisory_xact_lock(10, 0)         -- SIEMPRE primero, antes de cualquier otro lock
2. SELECT ... FOR UPDATE (si aplica)    -- row locks después del global
3. pg_advisory_xact_lock(1, id_cabana)  -- por cabaña, si aplica
4. Validaciones (validar_disponibilidad, etc.)
5. INSERT/UPDATE
```

**Razón del fortalecimiento (v1.5):** `SELECT ... FOR UPDATE` toma row-level locks que PostgreSQL incluye en su grafo de detección de deadlocks. Si una función toma primero el row lock y otra toma primero el lock global, pueden trabarse mutuamente. La invariante anterior ("global antes de cabaña") no cubría este caso porque omitía row locks de su alcance. La invariante fortalecida cubre **cualquier tipo de lock**.

Romper este orden puede causar deadlocks detectables por PostgreSQL (error `40P01`). Ver Sección 15 para la convención completa.

**Funciones que toman el lock global:**

| Función | Toma lock global | Por qué |
|---|---|---|
| `crear_prereserva` | Sí | Inserta pre-reserva que afecta disponibilidad. |
| `confirmar_reserva` | Sí | Inserta reserva que afecta disponibilidad. |
| `cancelar_prereserva` | Sí (Q1) | Cambia disponibilidad efectiva; evita falsos conflictos con bloqueos paralelos. |
| `crear_bloqueo` | Sí | Inserta bloqueo que afecta disponibilidad. |
| `registrar_pago` | No (Q3) | No crea disponibilidad nueva. P2 de v1.3 cubre pagos sobre pre-reservas terminales. |
| `expirar_prereservas_vencidas` | No (Q2) | Solo procesa pre-reservas ya expiradas lógicamente. Serializar bloquearía el cron. |

### Capa 1 — Constraint EXCLUDE en `reservas`

```
EXCLUDE USING gist (
  id_cabana WITH =,
  daterange(fecha_checkin, fecha_checkout, '[)') WITH &&
) WHERE (estado IN ('confirmada', 'activa'))
```

Garantía estructural: no pueden existir dos reservas confirmadas/activas en la misma cabaña con rangos solapados. PostgreSQL rechaza el INSERT con error `23P01` (`exclusion_violation`).

### Capa 2 — Constraint EXCLUDE en `bloqueos`

```
EXCLUDE USING gist (
  id_cabana WITH =,
  daterange(fecha_desde, fecha_hasta, '[)') WITH &&
) WHERE (activo = TRUE AND id_cabana IS NOT NULL)
```

Garantía estructural: no hay dos bloqueos activos solapados sobre la misma cabaña. Los bloqueos totales (`id_cabana NULL`) se manejan en función transaccional.

### Capa 3 — Función `validar_disponibilidad()` + advisory locks

Las pre-reservas tienen el problema de que su "vigencia" depende de `expira_en > NOW()`. Esto no se puede expresar como EXCLUDE constraint porque NOW() no es determinista.

Solución: la función `validar_disponibilidad(id_cabana, fecha_in, fecha_out)` se invoca dentro de transacciones que **previamente toman el lock global (10, 0) y opcionalmente el lock por cabaña (1, id_cabana)**. La función verifica:
- Reservas confirmadas/activas solapando.
- Pre-reservas `pendiente_pago` vigentes solapando.
- Pre-reservas `pago_en_revision` solapando.
- Bloqueos activos (incluyendo totales con `id_cabana NULL`) solapando.

### Capa 4 — Revalidación al confirmar

`confirmar_reserva()` revalida disponibilidad **excluyendo la pre-reserva que se está convirtiendo** (no contar como conflicto consigo misma). Previene el caso de que entre la pre-reserva y la confirmación haya entrado un bloqueo o reserva manual.

### Manejo de errores de constraint

Cuando un `INSERT INTO reservas` viola el EXCLUDE, PostgreSQL lanza `SQLSTATE 23P01` (`exclusion_violation`). **Todas las funciones que insertan en reservas o bloqueos capturan este error con `EXCEPTION WHEN exclusion_violation THEN ...` y devuelven JSONB controlado** con `ok=false`, `error='no_disponible'` y detalle. Esto evita que n8n parsee errores crudos.

### Garantías combinadas

| Tipo de conflicto | Capa que lo previene |
|---|---|
| Reserva confirmada vs Reserva confirmada | Capa 1 (estructural) |
| Reserva confirmada vs Bloqueo de cabaña específica | Capa 4 al confirmar |
| Bloqueo vs Bloqueo en misma cabaña | Capa 2 (estructural) |
| Pre-reserva vs Pre-reserva | Capa 3 (validación + locks) |
| Pre-reserva vs Reserva | Capa 3 |
| Pre-reserva vs Bloqueo | Capa 3 |
| Bloqueo total vs cualquier reserva | Capa 3 (manual en `crear_bloqueo`) |
| **Pre-reserva vigente vs Bloqueo total concurrente** | **Capa 0 (v1.4)** |
| **Bloqueo específico vs Bloqueo total concurrente** | **Capa 0 (v1.4)** |
| **Cancelación vs Bloqueo concurrente (falso conflicto)** | **Capa 0 (v1.4)** |
| Doble click del cliente (mismo payload) | `idempotency_key` (índice parcial, v1.1) |

---

## 10. FUNCIONES CRÍTICAS

### 10.1 `normalizar_telefono(input TEXT) RETURNS TEXT`

Helper IMMUTABLE separado, usado por trigger de `huespedes.telefono_normalizado` y disponible para queries ad-hoc.

**Reglas:**

1. Si `input IS NULL` o vacío → retorna NULL.
2. Eliminar espacios, guiones, paréntesis, puntos.
3. Si empieza con `00`, reemplazar por `+`.
4. Si ya tiene `+`, respetarlo. Colapsar múltiples `+` consecutivos a uno solo.
5. Si no tiene `+` ni `00`, dejarlo tal cual (no asumir `+54` automático — Vita Delta puede recibir extranjeros).
6. Verificar que el resultado contenga solo dígitos y como máximo un `+` al inicio.

**Por qué conservadora:**

- `54...` sin `+` podría ser un número argentino sin prefijo internacional, pero también podría ser un código local de otro país.
- La regla "agregar `+54` automáticamente" puede romper datos válidos extranjeros.
- Si en el futuro se quiere implementar normalización Argentina específica, debe ser **explícita y documentada**, no silenciosa.

### 10.2 `upsert_huesped(payload JSONB) RETURNS JSONB`

Reemplaza la lógica de `db_crear_huesped` v1.1.

**Comportamiento:**

1. Extrae campos del payload: `nombre`, `apellido`, `dni`, `telefono`, `email`, `canal_preferido`.
2. Normaliza email (LOWER, TRIM).
3. Normaliza teléfono vía `normalizar_telefono()`.
4. Busca por `telefono_normalizado` primero. Si encuentra, `modo='update'`, `encontrado_por='telefono'`.
5. Si no, busca por `LOWER(email)`. Si encuentra, `modo='update'`, `encontrado_por='email'`.
6. Si no, INSERT nuevo huésped. `modo='create'`, `encontrado_por=null`.
7. Si UPDATE: actualiza solo campos cuyo valor en payload NO sea NULL ni vacío. **No borra datos existentes con campos vacíos.**
8. `total_reservas` y `primera_reserva_fecha` NO se tocan acá (los actualiza `confirmar_reserva`).
9. Retorna: `{ ok, modo, id_huesped, encontrado_por }`.

### 10.3 `validar_disponibilidad(id_cabana, fecha_in, fecha_out) RETURNS JSONB`

Función auxiliar reutilizable. Verifica solapamientos en reservas, pre_reservas y bloqueos. Lockea con SELECT FOR UPDATE las filas relevantes.

**Importante:** esta función NO toma el advisory lock. El advisory lock debe tomarlo el caller (típicamente `crear_prereserva` o `confirmar_reserva`). Esto permite usarla tanto desde funciones que ya tomaron el lock, como desde queries ad-hoc para reportes.

**Output:**
- `{ ok: true, disponible: true }` si todo OK.
- `{ ok: true, disponible: false, conflictos: [...] }` si hay conflicto.
- `{ ok: false, error: 'cabana_invalida' | 'fechas_invalidas' }` si parámetros mal.

### 10.4 `obtener_disponibilidad_rango(fecha_desde, fecha_hasta, id_cabana) RETURNS SETOF`

Reemplaza conceptualmente a `DISPONIBILIDAD_CACHE`. Devuelve disponibilidad calculada al vuelo.

**Devuelve hora base, no escalonada.** El escalonamiento se aplica en n8n si corresponde. Ver Sección 17 "El escalonamiento es feature apagable".

### 10.5 `crear_prereserva(payload JSONB) RETURNS JSONB` *(nuevo en v1.1)*

**Puerta única para crear pre-reservas desde cualquier canal** (web, bot, carga manual, n8n, futura UI interna).

**Payload esperado:**
```
{
  "huesped":               { nombre, apellido, dni, telefono, email, canal_preferido },
  "id_consulta":           number | null,
  "id_cabana":             number,
  "fecha_in":              "YYYY-MM-DD",
  "fecha_out":             "YYYY-MM-DD",
  "personas":              number,
  "monto_total":           number,   // del backend, no del frontend
  "monto_sena":            number,
  "canal_origen":          "whatsapp" | "instagram" | "web" | "manual",
  "canal_pago_esperado":   "transferencia_bancaria" | ...,   // requerido por schema (TEXT NOT NULL)
  "hora_checkin_solicitada":  "HH:MM" | null,   // opcional
  "hora_checkout_solicitada": "HH:MM" | null,   // opcional
  "expiracion_minutos":    number | null,       // default desde configuracion_general
  "mascotas":              boolean | null,
  "detalle_mascotas":      string | null,
  "ninos":                 string | null,   // detalle operativo libre; NULL = no informado
  "notas_reserva":         string | null,
  "notas":                 string | null,
  "source_event":          string,
  "idempotency_key":       string | null
}
```

> **Nota sobre `canal_pago_esperado` (v1.7.3, D-7A-01):** el campo es obligatorio y está validado en el IF de obligatorios. Si llega ausente, vacío o whitespace, el extract `NULLIF(TRIM(...), '')` lo convierte a NULL y la función rebota con `error='payload_invalido'` (rebote temprano, antes de locks y de `upsert_huesped`). La columna `pre_reservas.canal_pago_esperado` permanece `TEXT NOT NULL` y el CHECK de 5 valores se mantiene. Valores no-NULL fuera del CHECK (ej. `"canal_invalido"`) siguen rebotando por el constraint, no por validación manual (fuera de alcance del patch).
>
> **Nota sobre `ninos` (v1.7.3, D-7A-02):** se interpreta como TEXT libre. Variable local `v_ninos TEXT`, extract `NULLIF(TRIM(payload->>'ninos'), '')`. Semántica: `NULL` = no informado; texto libre = detalle operativo (cantidad/edades/necesidades). Las columnas `pre_reservas.ninos` y `reservas.ninos` son `TEXT nullable` — la variable y las columnas quedan alineadas. El literal `"false"` no es un valor esperado (era residuo del cast BOOLEAN→TEXT de v1.7.2, limpiado en Etapa 7A).

**Flujo:**

1. Validar payload mínimo (presencia de campos obligatorios).
2. Si `monto_total IS NULL OR monto_sena IS NULL` → devolver `error='precio_requerido'`.
3. Si viene `idempotency_key` → buscar pre-reserva activa con esa key. Si existe, devolver la existente con flag `idempotent_match=true`.
4. Resolver huésped vía `upsert_huesped()` (Modo 2).
5. Tomar locks de disponibilidad (v1.4, v1.6): primero `pg_advisory_xact_lock(10, 0)` (global), después `pg_advisory_xact_lock(1, v_id_cabana::INTEGER)` (cabaña, con cast obligatorio — ver Sección 15).
6. Llamar a `validar_disponibilidad()`. Si no disponible → devolver `error='no_disponible'`.
7. Calcular `hora_checkin` y `hora_checkout` finales: si vienen solicitadas, validar contra rango permitido. Si no, usar default.
8. INSERT en pre_reservas.
9. Capturar `exclusion_violation` (defensivo, no debería pasar por la capa de advisory lock + validar).
10. INSERT en log_cambios con evento `prereserva_creada`.
11. Devolver `{ ok, id_pre_reserva, id_huesped, estado, expira_en }`.

**Lo que NO hace:** llamar a MercadoPago, enviar WhatsApp, calcular precios, crear consulta. Eso queda en n8n.

### 10.6 `confirmar_reserva(payload JSONB) RETURNS JSONB` *(nuevo en v1.1)*

Convierte una pre-reserva en reserva confirmada.

**Payload esperado:**
```
{
  "id_pre_reserva":              number,
  "permitir_pago_en_revision":   boolean | false,
  "validado_por":                string | null,
  "encargado_semana":            string | null,
  "created_by":                  string | null,
  "source_event":                string
}
```

**Flujo:**

1. Extraer payload y validar mínimo (`id_pre_reserva`, `source_event`).
2. Setear contexto de logs (`app.modificado_por='confirmar_reserva'`, `app.source_event=<source_event>`) para que los triggers de log de estado tengan contexto preciso (D38, v1.2).
3. **Tomar lock global `(10, 0)` ANTES de cualquier `FOR UPDATE`** (invariante v1.5): `pg_advisory_xact_lock(10, 0)`. Este orden es obligatorio porque `SELECT ... FOR UPDATE` toma row locks que PostgreSQL incluye en su grafo de detección de deadlocks. Tomar el FOR UPDATE antes del global puede causar deadlocks contra `cancelar_prereserva`.
4. Lockear y leer la pre-reserva con `SELECT * FROM pre_reservas WHERE id_pre_reserva = X FOR UPDATE`.
5. Verificar que exista y que el estado sea `pendiente_pago` o `pago_en_revision`.
6. Tomar lock por cabaña (ahora que conocemos `v_pre.id_cabana`): `pg_advisory_xact_lock(1, v_pre.id_cabana::INTEGER)`. El cast a INTEGER es obligatorio porque PostgreSQL no provee `pg_advisory_xact_lock(integer, bigint)` (ver nota técnica en Sección 15).
7. Verificar pagos asociados:
   - Camino estricto (default): buscar al menos un pago en estado `confirmado` asociado a la pre-reserva. Si no hay → `error='sin_pago_confirmado'`.
   - Camino combinado (si `permitir_pago_en_revision=true` y `validado_por` viene): aceptar pagos en `en_revision`. Dentro de la transacción, actualizar el pago a `confirmado` con `validado_por` y `validado_en=NOW()`.
8. Revalidar disponibilidad excluyendo la propia pre-reserva (en pre_reservas WHERE id_pre_reserva != THIS).
9. INSERT en reservas copiando todos los campos de la pre-reserva (fechas, horas, montos, personas, huésped, cabaña) **incluyendo los 4 campos operativos** (`mascotas`, `detalle_mascotas`, `ninos`, `notas_reserva`). Capturar `exclusion_violation` defensivamente.
10. UPDATE pre_reserva: estado = `convertida`.
11. UPDATE pago: setear `id_reserva` apuntando a la nueva reserva.
12. UPDATE huesped: `total_reservas = total_reservas + 1`. Si `primera_reserva_fecha IS NULL`, setear con la fecha de check-in.
13. INSERT en log_cambios con evento `reserva_confirmada`.
14. Devolver `{ ok, id_reserva, id_pre_reserva }`.

### 10.7 `cancelar_prereserva(payload JSONB) RETURNS JSONB` *(nuevo en v1.1)*

**Payload:**
```
{
  "id_pre_reserva": number,
  "motivo":         "cliente" | "bloqueo",
  "descripcion":    string | null,
  "source_event":   string
}
```

**Flujo:**

1. Extraer payload y validar mínimo (`id_pre_reserva`, `motivo`, `source_event`).
2. Setear contexto de logs (`app.modificado_por='cancelar_prereserva'`, `app.source_event=<source_event>`) para que los triggers de log de estado tengan contexto preciso (D38, v1.2).
3. **Tomar lock global `(10, 0)` ANTES de cualquier `FOR UPDATE`** (invariante v1.5): `pg_advisory_xact_lock(10, 0)`. Esta función NO toma lock por cabaña porque el UPDATE solo libera disponibilidad, pero sí toma el lock global para serializarse contra `crear_bloqueo` paralelo y evitar falsos conflictos operativos.
4. Mapear motivo a estado nuevo:
   - `cliente` → `cancelada_por_cliente`.
   - `bloqueo` → `cancelada_por_bloqueo`.
5. Lockear y leer la pre-reserva con `SELECT * FROM pre_reservas WHERE id_pre_reserva = X FOR UPDATE`.
6. Verificar que exista y que el estado sea cancelable (`pendiente_pago` o `pago_en_revision`).
7. UPDATE estado.
8. **NO tocar pagos.** Contar pagos asociados y devolverlos como info (los humanos deciden si reembolsan, reasignan o gestionan manualmente).
9. INSERT en log_cambios.
10. Devolver `{ ok, id_pre_reserva, estado_anterior, estado_nuevo, pagos_asociados_count, pagos_asociados_ids[] }`.

### 10.8 `crear_bloqueo(payload JSONB) RETURNS JSONB` *(nuevo en v1.1)*

**Payload:**
```
{
  "id_cabana":     number | null,    // null = bloqueo total
  "fecha_desde":   "YYYY-MM-DD",
  "fecha_hasta":   "YYYY-MM-DD",
  "motivo":        "mantenimiento" | "uso_propio" | "tormenta" | "overbooking" | "otro",
  "descripcion":   string | null,
  "creado_por":    string,
  "source_event":  string
}
```

**Flujo:**

1. Validar payload (fechas, motivo en lista).
2. **Tomar lock global (v1.4):** `pg_advisory_xact_lock(10, 0)`.
3. Si `id_cabana` específica:
   - Tomar también lock por cabaña: `pg_advisory_xact_lock(1, v_id_cabana::INTEGER)` (cast obligatorio — ver Sección 15).
   - Verificar que no haya reservas `confirmada`/`activa` solapando con ese rango. Si hay → `error='conflicto_con_reserva'` con lista de IDs.
   - Verificar que no haya pre-reservas vigentes solapando. Si hay → `error='conflicto_con_prereserva'`.
   - Verificar que no haya bloqueos activos solapados (específico vs específico o específico vs total). Si hay → `error='bloqueo_solapado'`.
4. Si `id_cabana IS NULL` (bloqueo total):
   - **`LOCK TABLE` eliminado en v1.4 (Q5).** El lock global ya serializa contra todas las otras operaciones críticas.
   - Verificar que no haya reservas activas en ninguna cabaña en ese rango. Si hay → `error='conflicto_con_reserva'`.
   - Verificar que no haya pre-reservas vigentes en ninguna cabaña. Si hay → `error='conflicto_con_prereserva'`.
   - Verificar que no haya bloqueos activos solapados (total vs total, total vs específico). Si hay → `error='bloqueo_solapado'`.
5. INSERT en bloqueos. Capturar `exclusion_violation` defensivamente.
6. INSERT en log_cambios con evento `bloqueo_creado`.
7. Devolver `{ ok, id_bloqueo }`.

**Sin override de fuerza en v1.1:** si hay reservas activas, se rechaza. En el futuro se puede agregar un flag `force` con auditoría especial.

### 10.9 `registrar_pago(payload JSONB) RETURNS JSONB` *(nuevo en v1.1)*

**Payload:**
```
{
  "id_pre_reserva":      number | null,   // al menos uno de los dos debe venir
  "id_reserva":          number | null,
  "tipo":                "sena" | "saldo" | "extra" | "reembolso" | "ajuste",
  "medio_pago":          "transferencia_bancaria" | ...,
  "monto_esperado":      number,
  "monto_recibido":      number,
  "moneda":              string | "ARS",
  "es_automatico":       boolean | false,
  "estado_inicial":      "en_revision" | "confirmado" | null,   // si null, default 'en_revision'
  "comprobante_url":     string | null,
  "referencia_externa":  string | null,
  "tx_hash":             string | null,
  "validado_por":        string | null,
  "notas":               string | null,
  "proveedor":           string | null,
  "cuenta_destino":      string | null,
  "source_event":        string
}
```

**Flujo:**

1. Validar que al menos uno de `id_pre_reserva` o `id_reserva` venga.
2. Si viene `id_pre_reserva`, verificar que exista (capturar FK violation).
3. Si viene `id_reserva`, verificar que exista.
4. Decidir estado:
   - Si `estado_inicial='confirmado'` y `monto_recibido = monto_esperado` → estado `confirmado` con `validado_por` y `validado_en=NOW()`.
   - Si no → estado `en_revision`.
5. INSERT en pagos.
6. Si la pre-reserva existe y estaba en `pendiente_pago`, opcionalmente actualizar a `pago_en_revision`. Esto preserva el comportamiento de `db_registrar_pago` v1.
7. INSERT en log_cambios con evento `pago_registrado`.
8. Devolver `{ ok, id_pago, estado }`.

### 10.10 `expirar_prereservas_vencidas() RETURNS INTEGER`

Reemplaza el workflow `sistema_expirar_prereservas`. Marca como `vencida` las pre-reservas con `expira_en <= NOW()`. Programada con pg_cron cada 5 minutos.

### Funciones documentadas como futuras (NO implementadas en v1.1)

| Función | Por qué no se implementa ahora |
|---|---|
| `cancelar_reserva(payload)` | Compleja: reembolsos parciales, cargos de cancelación, decisiones comerciales que aún no están cerradas. |
| `modificar_reserva(payload)` | Cambio de fechas/cabaña/personas requiere revalidación de disponibilidad, recálculo de precio, posibles ajustes de pago. Se implementa cuando esos casos estén definidos comercialmente. |

---


## 11. TRIGGERS AUTOMÁTICOS

**Cambio en v1.1:** se eliminan los triggers `AFTER INSERT` genéricos. Los logs de creación se hacen DENTRO de las funciones críticas (`crear_prereserva`, `confirmar_reserva`, `crear_bloqueo`, `registrar_pago`, `cancelar_prereserva`). Esto da control fino sobre qué se loguea y cómo.

Triggers que SÍ se conservan:

| Trigger | Tabla | Evento | Función |
|---|---|---|---|
| `trg_pre_reservas_updated_at` | `pre_reservas` | BEFORE UPDATE | Setea `updated_at = NOW()` |
| `trg_reservas_updated_at` | `reservas` | BEFORE UPDATE | Setea `updated_at = NOW()` |
| `trg_pagos_updated_at` | `pagos` | BEFORE UPDATE | Setea `updated_at = NOW()` |
| `trg_huespedes_updated_at` | `huespedes` | BEFORE UPDATE | Setea `updated_at = NOW()` |
| `trg_consultas_updated_at` | `consultas` | BEFORE UPDATE | Setea `updated_at = NOW()` |
| `trg_descuentos_updated_at` | `descuentos` | BEFORE UPDATE | Setea `updated_at = NOW()` |
| `trg_eventos_updated_at` | `eventos_especiales` | BEFORE UPDATE | Setea `updated_at = NOW()` |
| `trg_tarifas_updated_at` | `tarifas` | BEFORE UPDATE | Setea `updated_at = NOW()` |
| `trg_config_updated_at` | `configuracion_general` | BEFORE UPDATE | Setea `updated_at = NOW()` |
| `trg_huespedes_telefono_norm` | `huespedes` | BEFORE INSERT/UPDATE | Setea `telefono_normalizado = normalizar_telefono(telefono)` |
| `trg_log_pre_reservas_estado` | `pre_reservas` | AFTER UPDATE OF estado | INSERT en log_cambios con cambio de estado |
| `trg_log_reservas_estado` | `reservas` | AFTER UPDATE OF estado | INSERT en log_cambios con cambio de estado |
| `trg_log_pagos_estado` | `pagos` | AFTER UPDATE OF estado | INSERT en log_cambios con cambio de estado |

---

## 12. VISTAS SQL

| # | Vista | Propósito |
|---|---|---|
| V1 | `vista_disponibilidad` | Disponibilidad calculada para el horizonte configurable. *(v1.7.3: horizonte vía `configuracion_general.horizonte_disponibilidad_dias`, default 120)* |
| V2 | `vista_calendario` | Calendario operativo de reservas activas/confirmadas |
| V3 | `vista_prereservas_activas` | Pre-reservas vigentes |
| V4 | `vista_ocupacion` | Ocupación por cabaña y mes |
| V5 | `vista_calendario_semanal` | Sistema 3 — calendario semanal operativo |
| V6 | `vista_limpieza_semana` | Sistema 4 — vista para Jennifer (check-ins y check-outs de la semana) |

---

## 13. DIVISIÓN DE RESPONSABILIDADES n8n / PostgreSQL

| Responsabilidad | n8n | PostgreSQL |
|---|---|---|
| Recibir input desde canales externos | ✓ | |
| Validar estructura de payload | ✓ | |
| Calcular precios | ✓ (por ahora) | (candidato futuro) |
| Llamar funciones SQL con payload validado | ✓ | |
| Búsqueda/dedupe de huéspedes | | ✓ `upsert_huesped` |
| Validación de disponibilidad transaccional | | ✓ `validar_disponibilidad` |
| Creación de pre-reservas | | ✓ `crear_prereserva` |
| Confirmación de reservas | | ✓ `confirmar_reserva` |
| Cancelación de pre-reservas | | ✓ `cancelar_prereserva` |
| Creación de bloqueos | | ✓ `crear_bloqueo` |
| Registro de pagos | | ✓ `registrar_pago` |
| Expiración periódica | | ✓ `expirar_prereservas_vencidas` + pg_cron |
| Prevención estructural de double booking | | ✓ EXCLUDE + funciones |
| Logging de cambios de estado | | ✓ triggers automáticos |
| Logging de creación de entidades | | ✓ dentro de funciones críticas |
| Mantenimiento de `updated_at` y `telefono_normalizado` | | ✓ triggers |
| Envío de mensajes WhatsApp/Instagram | ✓ | |
| Integración con MercadoPago | ✓ | |
| Llamadas a Claude API (bot) | ✓ | |
| Branching y manejo de errores de workflow | ✓ | |
| Mostrar errores amigables al usuario | ✓ | |

**Principio rector:** PostgreSQL es responsable de la verdad y la integridad. n8n es responsable de la orquestación y la comunicación externa.

---

## 14. USO DE pg_cron

### Schedule propuesto

| Job | Frecuencia | Función | Propósito |
|---|---|---|---|
| `expirar_prereservas` | cada 5 minutos | `expirar_prereservas_vencidas()` | Marcar como vencidas las pre-reservas expiradas |
| `cleanup_cron_history` | 1ro de cada mes a las 03:00 UTC | `DELETE FROM cron.job_run_details WHERE end_time < NOW() - INTERVAL '30 days'` | Evitar crecimiento indefinido |

### Monitoreo

```sql
SELECT jobid, jobname, schedule, active FROM cron.job;
SELECT jobid, status, return_message, start_time FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;
```

### Activación/desactivación

```sql
SELECT cron.schedule('nombre', 'cron_expr', $$SQL$$);
SELECT cron.unschedule('nombre');
```

### Limitaciones en Supabase Free

- Mínimo 1 minuto entre ejecuciones.
- UTC siempre.
- Si proyecto se pausa por 7 días sin uso, crons no corren.
- Sin alertas nativas si un job falla.

---

## 15. ADVISORY LOCKS — CONVENCIÓN

Para coordinar acceso concurrente a la disponibilidad, todas las funciones que afectan disponibilidad usan **advisory locks transaccionales** con dos namespaces dedicados.

### Convención de namespaces (v1.4)

| Namespace | Key | Uso | Llamada |
|---|---|---|---|
| `10` | `0` | **Lock global de disponibilidad** (siempre primero) | `pg_advisory_xact_lock(10, 0)` |
| `1` | `id_cabana` | Lock específico por cabaña (siempre después del global) | `pg_advisory_xact_lock(1, id_cabana::INTEGER)` |

### Nota técnica sobre sobrecargas de `pg_advisory_xact_lock` (v1.6)

**Por qué el segundo argumento se castea a `INTEGER`.**

PostgreSQL provee solo dos sobrecargas de `pg_advisory_xact_lock`:

- `pg_advisory_xact_lock(bigint)` — versión de 1 argumento.
- `pg_advisory_xact_lock(integer, integer)` — versión de 2 argumentos del mismo tipo.

**No existe** `pg_advisory_xact_lock(integer, bigint)`. Si el segundo argumento es de tipo `BIGINT` (porque `id_cabana` viene de una columna `BIGSERIAL` o de una variable declarada `BIGINT`), PostgreSQL no encuentra una sobrecarga compatible y aborta con error en runtime:

```
ERROR 42883: function pg_advisory_xact_lock(integer, bigint) does not exist
```

**Solución:** cast explícito a `INTEGER` en cada llamada de lock por cabaña:

```sql
PERFORM pg_advisory_xact_lock(1, v_id_cabana::INTEGER);
PERFORM pg_advisory_xact_lock(1, v_pre.id_cabana::INTEGER);
```

**Por qué el cast es seguro en Vita Delta:**
- `id_cabana` nunca va a superar el rango `INTEGER` (~2.1 mil millones). A 5 cabañas hoy y 12-15 en el horizonte previsto, estamos varios órdenes de magnitud por debajo del límite.
- `pg_advisory_xact_lock` usa el segundo argumento como **identificador de lock**, no como dato de negocio. El cast no introduce riesgo semántico.

**Por qué el lock global no necesita cast:**
- `pg_advisory_xact_lock(10, 0)` usa dos literales numéricos pequeños que PostgreSQL infiere como `integer` automáticamente. La sobrecarga `(integer, integer)` matchea sin necesidad de casts.

**Por qué no cambiar el tipo de `v_id_cabana` a `INTEGER` en las funciones:**
- `id_cabana` en las tablas es `BIGSERIAL` (`BIGINT`). Si declarara `v_id_cabana INTEGER`, habría cast implícito en cada SELECT/INSERT que use la variable. El cast localizado a `::INTEGER` solo en las 2-3 llamadas de advisory lock es más limpio y conservador.

**Historia del bug:** detectado durante la ejecución del Bloque 13 (`crear_prereserva`) en Supabase DEV con PostgreSQL 17.6. Corrección aplicada en v1.6.

### Invariante de orden (obligatorio, fortalecida en v1.5)

**Toda función crítica debe respetar este orden estricto. La invariante cubre TODO tipo de lock, no solo advisory.**

```
1. pg_advisory_xact_lock(10, 0)                  -- SIEMPRE primero, antes de cualquier otro lock
2. SELECT ... FOR UPDATE (si aplica)             -- row locks SOLO después del global
3. pg_advisory_xact_lock(1, id_cabana::INTEGER)  -- por cabaña, si aplica (cast obligatorio, ver nota v1.6)
4. Validaciones
5. INSERT/UPDATE
```

**Por qué cubre row locks (v1.5):** `SELECT ... FOR UPDATE` toma row-level locks que PostgreSQL gestiona en su grafo de detección de deadlocks junto con los advisory. Si una transacción toma primero un row lock y otra toma primero el lock global, pueden trabarse mutuamente y PostgreSQL aborta una con `40P01` (`deadlock_detected`). El bug ocurría entre `confirmar_reserva` y `cancelar_prereserva` en v1.4 y se corrige en v1.5.

**Romper este orden puede causar deadlocks.** Cada función crítica lleva un comentario inline obligatorio con la invariante:

```sql
-- INVARIANTE DE LOCKS (v1.5):
-- Tomar SIEMPRE primero el lock global (10, 0) antes de CUALQUIER otro lock:
--   - antes de SELECT ... FOR UPDATE (row locks)
--   - antes de pg_advisory_xact_lock(1, id_cabana) (lock por cabaña)
--   - antes de cualquier table-level lock si volviera a existir
-- Romper este orden puede causar deadlocks (error 40P01) o inconsistencias.
```

### Decisión D46 — Lock global de disponibilidad

**Por qué se agregó (v1.4):** en v1.3 se usaban `pg_advisory_xact_lock(1, id_cabana)` por cabaña y `LOCK TABLE` para bloqueo total. Esos dos mecanismos son independientes y no se coordinan entre sí. Una transacción que tomaba el advisory lock por cabaña podía intercalarse con otra que tomaba `LOCK TABLE`, produciendo:

- Pre-reserva vigente y bloqueo total solapados.
- Bloqueo específico y bloqueo total solapados.

La solución de v1.4 es usar **un único mecanismo común** (advisory lock global) que toda operación crítica respeta antes de cualquier lock más granular.

### Por qué namespace `10`

Es arbitrario pero documentado. Reserva un rango (`10, 0`) que no colisiona con `1, id_cabana`. Si en el futuro se agregan más locks especializados, se pueden usar namespaces `20`, `30`, etc., manteniendo `10, 0` reservado para el lock global de disponibilidad.

### `LOCK TABLE` eliminado (v1.4, Q5)

`LOCK TABLE EXCLUSIVE` se usaba en v1.3 para bloqueo total. En v1.4 se elimina porque:

- El lock global de disponibilidad ya serializa todas las operaciones críticas.
- `LOCK TABLE EXCLUSIVE` bloquea incluso lecturas, lo cual es más agresivo de lo necesario.
- Reduce mezcla de mecanismos de bloqueo distintos (que era justamente la raíz del problema).

### Aplicación en funciones v1.4

| Función | Lock global `(10, 0)` | Lock cabaña `(1, id_cabana)` | Notas |
|---|---|---|---|
| `crear_prereserva` | Sí (primero) | Sí (después) | Inserta pre-reserva sobre cabaña específica. |
| `confirmar_reserva` | Sí (primero) | Sí (después) | Inserta reserva sobre cabaña específica. |
| `cancelar_prereserva` | **Sí (Q1, v1.4)** | No | Sin lock por cabaña: el UPDATE solo libera disponibilidad. Lock global evita falsos conflictos con bloqueos paralelos. |
| `crear_bloqueo` con cabaña específica | Sí (primero) | Sí (después) | Inserta bloqueo sobre cabaña específica. |
| `crear_bloqueo` total | Sí (único lock) | No aplica | `LOCK TABLE` eliminado (v1.4). El lock global serializa contra todas las demás operaciones críticas. |
| `validar_disponibilidad` | No (lo toma el caller) | No (lo toma el caller) | Función auxiliar. Espera que el caller haya tomado los locks correctos. Usa `SELECT FOR UPDATE`. |
| `registrar_pago` | No (Q3, v1.4) | No | No crea disponibilidad nueva. P2 de v1.3 cubre pagos sobre pre-reservas terminales con warning. |
| `expirar_prereservas_vencidas` | No (Q2, v1.4) | No | Solo procesa pre-reservas ya expiradas lógicamente. Usa `FOR UPDATE SKIP LOCKED`. |

### Bloqueo total: defensa estructural y validaciones manuales (v1.4)

**Observación importante:** el constraint EXCLUDE de `bloqueos` tiene `WHERE (activo = TRUE AND id_cabana IS NOT NULL)`. Esto significa que los bloqueos totales (`id_cabana IS NULL`) **no tienen defensa estructural en el schema**. La prevención de bloqueos totales solapados depende ahora exclusivamente de:

1. El **lock global de disponibilidad** que toma `crear_bloqueo()` y todas las demás operaciones críticas (v1.4).
2. Las validaciones manuales dentro de `crear_bloqueo()` (v1.2) que verifican las 4 combinaciones posibles: total vs total, total vs específico, específico vs total, específico vs específico.

Si en el futuro se permite INSERT directo a `bloqueos` desde fuera de la función (lo cual no recomendamos), el caller debe tomar el lock global y replicar las validaciones manuales.

### Nota operativa sobre Supabase Dashboard y modificación de funciones (v1.7)

**Hallazgo durante ejecución DEV.** Al aplicar un hotfix sobre una función ya existente vía `CREATE OR REPLACE FUNCTION` desde el SQL Editor del Supabase Dashboard, **se observó que el Dashboard puede interferir con el código pegado**, insertando automáticamente líneas de RLS sobre nombres que interpreta erróneamente como tablas (por ejemplo, variables locales PL/pgSQL con prefijo `v_`). El resultado observado fue truncamiento del SQL y error en runtime:

```
ERROR 42601: unterminated dollar-quoted string
```

**Alcance del hallazgo.** Documentado como **comportamiento observado en Supabase Dashboard durante v1.7**. No se afirma como verdad universal de PostgreSQL ni como bug garantizado en todos los entornos. Otras formas de ejecutar SQL contra Supabase (clientes externos como `psql`, `pgAdmin`, scripts de migración) probablemente no presenten este comportamiento.

**Workaround validado.** Para modificar una función ya existente, ejecutar en **dos runs separados** dentro del SQL Editor:

**Run 1 — DROP de la función:**

```sql
DROP FUNCTION IF EXISTS nombre_funcion(tipos_parametros);
```

**Run 2 — CREATE de la función (transacción nueva):**

```sql
CREATE FUNCTION nombre_funcion(...)
RETURNS ...
LANGUAGE plpgsql
AS $$
...
$$;
```

**Cuándo aplica el workaround:**

- ✅ Aplica para **modificaciones posteriores / hotfixes** de funciones ya existentes en Supabase Dashboard.
- ❌ NO aplica para ejecución desde cero (Bloques iniciales): durante la ejecución de Fases 1-3, todos los `CREATE OR REPLACE FUNCTION` del documento funcionaron correctamente porque la función no existía previamente en el catálogo.

**Decisión documental.** No se modifican los `CREATE OR REPLACE FUNCTION` existentes del documento. Para recreación de DEV, ejecución de TEST y ejecución de PROD desde cero, el SQL canónico sigue siendo válido. El workaround `DROP + CREATE` queda como guía operativa **solo para futuros hotfixes** sobre entornos con funciones ya creadas.

**Advertencia adicional sobre `DROP FUNCTION` y dependencias (v1.7.1).**

El workaround `DROP + CREATE` fue validado durante el hotfix de v1.7 sobre `crear_prereserva`, que es una función transaccional autónoma **sin dependencias directas de triggers, vistas u otras funciones**. Antes de aplicar el workaround a otra función, verificar caso por caso:

- **Funciones de trigger** (por ejemplo, `set_updated_at`, `log_cambio_estado`, `set_telefono_normalizado` del Bloque 9): tienen triggers en tablas que dependen de ellas. `DROP FUNCTION` simple va a fallar con `cannot drop function ... because other objects depend on it`.

- **Funciones usadas en vistas** (por ejemplo, `obtener_disponibilidad_rango` es invocada por `vista_disponibilidad`): el DROP va a fallar por la misma razón.

- **Funciones invocadas por otras funciones** (por ejemplo, `validar_disponibilidad` es llamada dentro de `crear_prereserva` y `confirmar_reserva`): también van a generar dependencias.

**NO usar `DROP ... CASCADE` sin revisar impacto.** `CASCADE` borra silenciosamente todos los objetos dependientes (triggers, vistas, funciones que invocan la función droppeada). El daño puede ser invisible hasta que algo se rompe en producción.

**Procedimiento recomendado para funciones con dependencias** (si `CREATE OR REPLACE FUNCTION` directo falla por interferencia del Dashboard):

1. Identificar todas las dependencias con:

```sql
SELECT
  classid::regclass AS tipo_objeto_dependiente,
  objid::regprocedure AS objeto_dependiente
FROM pg_depend
WHERE refobjid = 'nombre_funcion(tipos_parametros)'::regprocedure;
```

2. Evaluar si recrear las dependencias manualmente después del DROP es viable.
3. Si las dependencias son muchas, **preferir un enfoque alternativo**: ejecutar `CREATE OR REPLACE FUNCTION` desde un cliente externo (`psql`, `pgAdmin`, script de migración) en lugar del SQL Editor del Dashboard.

**Funciones del schema actual con dependencias conocidas:**

| Función | Tipo de dependencia | Caller |
|---|---|---|
| `set_updated_at()` | Trigger | 9 triggers `trg_*_updated_at` |
| `log_cambio_estado()` | Trigger | 3 triggers `trg_log_*_estado` |
| `set_telefono_normalizado()` | Trigger | `trg_huespedes_telefono_norm` |
| `obtener_disponibilidad_rango()` | Vista | `vista_disponibilidad` |
| `validar_disponibilidad()` | Función | `crear_prereserva`, `confirmar_reserva` |
| `normalizar_telefono()` | Función | `set_telefono_normalizado` |
| `expirar_prereservas_vencidas()` | pg_cron job | (cuando esté programado, ver Pendientes Pre-Producción) |

**Funciones autónomas (workaround `DROP + CREATE` es seguro):**

`crear_prereserva`, `confirmar_reserva`, `cancelar_prereserva`, `crear_bloqueo`, `registrar_pago`, `upsert_huesped`. Ninguna está siendo usada por triggers, vistas u otras funciones del schema actual.

---

## 16. HORARIOS: LO QUE PIDE EL CLIENTE Y LO QUE VE EL EQUIPO

### Decisión D3 — Mantener solo `hora_checkin` y `hora_checkout`

En `pre_reservas` y `reservas`, los campos `hora_checkin` y `hora_checkout` representan **la hora declarada/elegida por el cliente, dentro del margen permitido**. No se separan en "hora base" vs "hora real" en v1.1.

### Reglas de margen (Etapa 2 v1.3, sección 6; actualizado en v1.7)

**Para check-in:**
- `hora_checkin_minima` = MAX(hora base, hora escalonada).
- `hora_checkin_maxima` = 22:00 (configurable vía `hora_checkin_max_cliente`).
- **Hora base depende del día de la semana:**
  - Si `fecha_in` es domingo (DOW = 0): hora base = `hora_checkin_domingo` (default 18:00).
  - Resto de los días: hora base = `hora_checkin_default` (default 13:00).
- El cliente puede elegir cualquier hora entre la mínima y la máxima.

**Para check-out (v1.7, D47):**
- `hora_checkout_maxima` depende del día de la semana del último día de la estadía:
  - Si `fecha_out` es domingo (DOW = 0): máxima = `hora_checkout_domingo` (default 16:00). Esto refleja la logística de lancha colectiva — los clientes que se van un domingo pueden quedarse hasta las 16:00.
  - Resto de los días: máxima = `hora_checkout_default` (default 10:00).
- `hora_checkout_minima` = 07:00 (configurable vía `hora_checkout_min_cliente`).
- El cliente puede elegir salir antes del máximo, dentro del mínimo.

**Reglas independientes.** La regla dominical de check-in aplica sobre `fecha_in`. La regla dominical de check-out aplica sobre `fecha_out`. Una pre-reserva puede tener una, la otra, ambas o ninguna:

| `fecha_in` | `fecha_out` | check-in base | check-out máx |
|---|---|---|---|
| domingo | domingo | 18:00 | 16:00 |
| domingo | otro día | 18:00 | 10:00 |
| otro día | domingo | 13:00 | 16:00 |
| otro día | otro día | 13:00 | 10:00 |

**Casos fuera de alcance automático (v1.7):** feriados nacionales o "último día de bloque" de logística especial (por ejemplo, salida en pleno feriado con lancha colectiva extendida) **NO** están contemplados automáticamente. Si surgen, se resuelven manualmente con el cliente (override operativo) o se agrega una clave de configuración específica en una versión futura.

### Validación en `crear_prereserva()`

El payload acepta opcionalmente `hora_checkin_solicitada` y `hora_checkout_solicitada`. La función:

- Si la hora solicitada está dentro del margen permitido → la acepta y guarda.
- Si está fuera del margen → devuelve `error='hora_fuera_de_rango'` con el margen permitido en el detalle.
- Si no viene → usa la hora mínima (para checkin) o máxima (para checkout) por default.

### Utilidad operativa

`vista_limpieza_semana` muestra `hora_checkin` y `hora_checkout` de cada movimiento. Si el cliente declara salir a las 8:00 (antes del máximo permitido —10:00 en días normales o 16:00 si `fecha_out` es domingo—), Jennifer y el equipo ven esa hora y pueden organizar limpieza más temprano. Esto puede incluso evitar activar el escalonamiento de check-in del próximo huésped.

### Trabajo futuro (no v1.1)

Si en el futuro Vita Delta quiere registrar la hora **real efectiva** de llegada/salida (distinta de la declarada), se pueden agregar campos opcionales sin tocar nada existente:

- `hora_checkin_efectiva TIMESTAMPTZ` (cuándo llegó de hecho).
- `hora_checkout_efectiva TIMESTAMPTZ` (cuándo se fue de hecho).

Esto permite reportes de cumplimiento operativo. **No se implementa en v1.1.**

---

## 17. EL ESCALONAMIENTO ES FEATURE APAGABLE

### Decisión D3 (parte 2)

El motor de check-in escalonado es **lógica operativa configurable, no estructural**. El schema no depende de él para funcionar.

### Por qué el schema ya es agnóstico

| Capa | ¿Depende del escalonamiento? |
|---|---|
| Tablas | **No.** Solo guardan `hora_checkin` y `hora_checkout` resultantes. |
| Constraints | **No.** EXCLUDE valida solapamiento por fechas, no por horas. |
| `validar_disponibilidad()` | **No.** Verifica solapamiento por fechas. |
| `crear_prereserva()` | **No.** Recibe la hora calculada en el payload (default o solicitada por cliente). |
| `confirmar_reserva()` | **No.** Copia horas de pre_reserva a reserva. |
| `obtener_disponibilidad_rango()` | **No.** Devuelve hora base (Opción 1 confirmada). |
| `tipo_override` en CHECK | Contiene valores relacionados al escalonamiento como TEXT, no como obligación. Si se elimina la lógica, los valores quedan sin uso pero no rompen nada. |

### Comportamiento si `escalonamiento_activo = false`

Si en `configuracion_general` la clave `escalonamiento_activo` está en `false`:

- n8n omite la lógica de escalonamiento al calcular hora de check-in.
- `crear_prereserva` recibe `hora_checkin_solicitada` o usa el default base.
- Las vistas operativas funcionan normalmente.
- Las funciones SQL críticas no requieren cambios.
- El schema no requiere migración.

Apagar el escalonamiento es **modificar configuración**, no migrar schema.

### Quién aplica el escalonamiento

n8n. Específicamente, el workflow que calcula la hora de check-in para mostrar al cliente o para crear la pre-reserva consulta `configuracion_general` y aplica la regla si corresponde. PostgreSQL no interviene en este cálculo.

### Trazabilidad de `tipo_override = escalonamiento_umbral_checkins_dia`

Este nombre fue establecido en Etapa 2 v1.3 y Etapa 5A v1.1 como rename de las antiguas claves `escalonamiento_umbral_checkout` y `escalonamiento_umbral_checkin`. El SQL incluye comentario inline explicando esta trazabilidad. No es un error; es decisión cerrada.

---

## 18. SEMÁNTICA DE `pago_en_revision` EN PRE-RESERVAS

### El estado `pago_en_revision` cubre dos sub-casos operativos distintos

Cuando una `pre_reserva` tiene `estado = 'pago_en_revision'`, en la práctica esto puede significar dos cosas distintas:

**Sub-caso A — Pago recibido, pendiente de validación humana:**
- Llegó un pago (transferencia, criptomoneda, comprobante adjunto).
- El sistema lo registró vía `registrar_pago()` con estado `en_revision` (porque el monto difiere del esperado, o porque el origen no permite validación automática).
- Vicky o un encargado debe revisar manualmente y confirmar o rechazar el pago.

**Sub-caso B — Pago confirmado, pendiente de conversión a reserva:**
- El pago ya está validado y en estado `confirmado` en `pagos`.
- Pero todavía nadie llamó a `confirmar_reserva()` para convertir la pre-reserva en reserva.
- La pre-reserva sigue bloqueando disponibilidad esperando esa conversión.

### Consecuencias operativas en ambos sub-casos

Una vez que la pre-reserva pasa a `pago_en_revision`:

- **No expira automáticamente por TTL.** El job `expirar_prereservas_vencidas` solo marca como vencidas las que están en `pendiente_pago`. Una pre-reserva con pago en revisión queda viva hasta intervención humana.
- **Sigue bloqueando disponibilidad** en `validar_disponibilidad()`. Otras pre-reservas o reservas no pueden ocupar el mismo rango.
- **Bloquea el `idempotency_key`** (el índice único parcial cubre estados `pendiente_pago` y `pago_en_revision`).

### Cómo distinguir los sub-casos

Para diferenciar A de B en el momento de la operación, n8n o el operador deben consultar `pagos`:

```
SELECT estado FROM pagos
WHERE id_prereserva = <X>
ORDER BY created_at DESC LIMIT 1;
```

- Si el pago más reciente está en `en_revision` → sub-caso A. Validar el pago primero.
- Si el pago más reciente está en `confirmado` → sub-caso B. Llamar `confirmar_reserva()`.

### Por qué no se separan en estados distintos

En v1.2 esto queda **documentado pero no se separa estructuralmente**, por estas razones:

- El estado real del pago vive en `pagos.estado`, que ya tiene la información precisa.
- Agregar `pago_validado_pendiente_conversion` como cuarto estado intermedio en `pre_reservas` agregaría complejidad sin ganancia operativa real.
- n8n y las vistas pueden hacer JOIN con `pagos` cuando necesiten distinguir.

Si en el futuro se detecta que la distinción es operativamente crítica (por ejemplo, alertas distintas para cada sub-caso), se puede agregar un estado nuevo sin migración disruptiva.

---

## 19. MOTOR DE PRECIOS — DECISIÓN TRANSITORIA Y PIEZA OBLIGATORIA FUTURA

### Estado actual en v1.2

El motor de precios **sigue en n8n** durante la migración a Supabase. `crear_prereserva()` recibe `monto_total` y `monto_sena` ya calculados en el payload. Si no vienen o son inválidos, devuelve `error='precio_requerido'`.

### Principio de seguridad

> El frontend puede mostrar el precio, pero **no debe ser fuente de verdad del precio**. El precio que llega a `crear_prereserva()` debe venir siempre del backend (n8n calcula y pasa al payload).

Si el frontend envía un precio inventado, n8n debe rechazarlo o recalcularlo. PostgreSQL confía en que el monto del payload viene de un backend autorizado.

### `consultar_disponibilidad_precio` — pieza obligatoria antes de la web pública

**Esto NO es una idea vaga futura. Es una pieza obligatoria.** Antes de que la web pública entre en producción, debe existir un endpoint único:

**`consultar_disponibilidad_precio`**

Responsabilidad:
- Recibe `id_cabana`, `fecha_in`, `fecha_out`, `personas`.
- Valida disponibilidad.
- Calcula precio.
- Devuelve:
  - `disponible: boolean`
  - `monto_total`
  - `monto_sena`
  - `desglose: [...]`
  - `expira_cotizacion_en` (opcional, si se decide cotizaciones con TTL)
- Corre **server-side**, nunca en el frontend.
- **No crea pre-reserva.** La pre-reserva solo se crea cuando el cliente confirma avanzar al pago.

### Por qué es pieza obligatoria

Sin este endpoint, la web pública no puede:
- Mostrar precios al cliente sin crear pre-reservas innecesarias.
- Cotizar combinaciones de fechas/personas/cabaña antes de avanzar al pago.
- Garantizar que el precio mostrado sea el mismo que se cobrará.

Permitir que el frontend calcule precios localmente abre un agujero de seguridad: cualquiera puede modificar JavaScript y enviar un `monto_total` inventado al backend. Por eso el endpoint es no negociable antes de exponer la web al público.

### Implementación recomendada

Inicialmente en n8n (workflow nuevo) que se llama desde la web. Cuando la operación esté estable, candidatos para migrar:
- Función SQL `calcular_precio()` que vive cerca de los datos.
- Supabase Edge Function que combina SQL + lógica HTTP.
- Combinación de ambos (función SQL para cálculo + Edge Function para envoltura HTTP).

**Decisión cerrada en v1.2:** el endpoint debe existir antes de la web pública. La forma de implementarlo puede evolucionar.

---

## 20. CARGA MANUAL SEGURA

### Principio

> **"Carga manual sí, edición directa insegura no."**

Franco, Vicky o Rodrigo pueden cargar manualmente reservas, pre-reservas, bloqueos, modificaciones, cancelaciones, pagos, y notas operativas. Pero **ninguna de esas cargas debe editar directamente tablas críticas sin validación**.

### Mecanismos de carga manual aceptados

- Google Form que dispara workflow n8n.
- Planilla controlada (Sheets-espejo con botón que dispara n8n).
- UI interna simple (futura).
- Workflow n8n interno con formulario embebido.

### Funciones obligatorias para toda acción que afecte disponibilidad

| Acción | Función a usar |
|---|---|
| Crear pre-reserva manual | `crear_prereserva()` con `canal_origen='manual'` |
| Confirmar reserva | `confirmar_reserva()` |
| Cancelar pre-reserva | `cancelar_prereserva()` |
| Crear bloqueo | `crear_bloqueo()` |
| Registrar pago manual | `registrar_pago()` |
| Cancelar reserva confirmada | `cancelar_reserva()` (futura — bloqueo manual hasta que exista) |
| Modificar reserva | `modificar_reserva()` (futura) |

### Lo que NO se permite (aún sin implementar como restricción RLS)

- INSERT directo en `pre_reservas`, `reservas`, `pagos`, `bloqueos` desde una UI humana.
- UPDATE directo de `estado` en esas tablas desde una UI humana (excepto vía función).
- DELETE en cualquier tabla crítica.

### Cómo se implementará la restricción

En esta etapa, la restricción es **convencional y documental**. Toda UI o automatización debe pasar por funciones almacenadas. n8n, con credencial de servicio Postgres, tiene permisos amplios y es el responsable de respetar el principio.

Cuando exista Supabase Auth o RLS, se podrán bloquear los INSERT/UPDATE/DELETE directos a nivel base, dejando solo las funciones SECURITY DEFINER como única vía de escritura. Ver Sección 19.bis siguiente.

### Nota sobre RLS

RLS (Row Level Security) queda **documentado como principio, no implementado en v1.1**. Razones:

- Vita Delta no tiene aún UI interna ni Supabase Auth.
- n8n usa credencial de servicio.
- Implementar RLS ahora obligaría a granularizar permisos sin un consumidor real que los necesite.

Cuando se construya UI interna con Auth, se hará una etapa específica de seguridad que:
- Habilite RLS en tablas críticas.
- Marque las funciones críticas como `SECURITY DEFINER`.
- Defina políticas por rol (operador, encargado, administrador).
- Restrinja `GRANT` para que humanos solo puedan ejecutar funciones, no escribir directo.

---

## 21. CONTABILIDAD FUTURA — CONTEMPLADA, NO IMPLEMENTADA

### Lo que 6B ya deja contemplado

El schema de v1.1 incluye todas las tablas y campos necesarios para que en una etapa posterior se construya un módulo contable completo, sin requerir migración estructural:

| Tabla / Campo | Sirve para |
|---|---|
| `pagos.monto_recibido`, `monto_esperado`, `tipo`, `medio_pago`, `estado` | Ingresos por reserva, señas, saldos, pagos confirmados |
| `reservas.monto_total`, `monto_sena`, `monto_saldo` | Cálculo de saldos pendientes y totales facturados |
| `gastos.monto`, `categoria`, `id_cabana` | Gastos por cabaña o generales |
| `cuentas_cobro` | Trazabilidad de qué cuenta recibió cada pago |
| `socios.porcentaje_utilidades` | Distribución entre socios |
| `log_cambios` | Auditoría completa de movimientos de dinero |

### Reportes posibles (no implementados en v1.1)

- Ingresos por reserva con desglose seña/saldo.
- Pagos confirmados por período, agrupados por medio.
- Gastos por cabaña vs ingresos por cabaña (rentabilidad por unidad).
- Utilidad mensual = ingresos – gastos.
- Distribución de utilidades entre socios según `porcentaje_utilidades`.
- Reportes por período (mes, trimestre, año).
- Conciliación de movimientos vs `log_cambios`.

### Lo que NO está en v1.1

- Tablas específicas de contabilidad (facturas, asientos, cuentas contables).
- Funciones de cálculo de utilidad.
- Vistas de reportes contables.
- Distribución automática de utilidades.

Esta etapa de contabilidad queda como **etapa 8 o 9** en la nomenclatura de Sistemas, posterior a la web pública y la operación estable del nuevo backend.

---

## 22. DECISIONES TOMADAS Y REGISTRADAS

Resumen consolidado de todas las decisiones aprobadas hasta v1.1:

| # | Decisión | Estado |
|---|---|---|
| D1 | Naming: `lowercase_snake_case`, sin tildes, plural en tablas | Aprobado |
| D2 | `tipo_cabana` como TEXT, sin FK ni enum | Aprobado |
| D3 | Montos como `NUMERIC(12,2)` | Aprobado |
| D4 | Enums solo para 4 estados estables | Aprobado |
| D5 | Disponibilidad sin tabla cache: función + vista | Aprobado |
| D6 | Anti-double-booking estructural: EXCLUDE + funciones | Aprobado |
| D7 | Motor de precios sigue en n8n (transitorio) | Aprobado |
| D8 | Crear vacías `descuentos`, `paquetes_evento`, `overrides_operativos` | Aprobado |
| D9 | Sin tabla `usuarios` por ahora | Aprobado |
| D10 | Estados de consulta: nueva/en_progreso/derivada_humano/cerrada/descartada | Aprobado |
| D11 | Tipos de pago: sena/saldo/extra/reembolso/ajuste | Aprobado |
| D12 | `tipo` de feriado como TEXT libre | Aprobado |
| D13 | `upsert_huesped` en PostgreSQL | Aprobado |
| D14 | `concepto` de tarifas como TEXT libre | Aprobado |
| D15 | `pg_cron` para `expirar_prereservas_vencidas` cada 5 min | Aprobado |
| D16 | `pre_reservas` con campos mascotas/detalle_mascotas/ninos/notas_reserva | Aprobado |
| D17 | `reservas` con los mismos 4 campos para trazabilidad | Aprobado |
| **D18** | **`pagos.id_prereserva` nullable + CHECK al menos uno** | **Aprobado v1.1** |
| **D19** | **`crear_prereserva()` como puerta única transaccional** | **Aprobado v1.1** |
| **D20** | **`confirmar_reserva()` con verificación de pago** | **Aprobado v1.1** |
| **D21** | **Camino combinado en `confirmar_reserva` con `permitir_pago_en_revision`** | **Aprobado v1.1** |
| **D22** | **Normalización teléfono: helper IMMUTABLE + columna + trigger (Opción B)** | **Aprobado v1.1** |
| **D23** | **Triggers solo para updated_at + cambios de estado. Logs de creación dentro de funciones** | **Aprobado v1.1** |
| **D24** | **Advisory lock por id_cabana, namespace 1** | **Aprobado v1.1** |
| **D25** | ~~Bloqueo total: LOCK TABLE simple (D1 de v1.1)~~ — **Reemplazada por D46 en v1.4** | ~~Aprobado v1.1~~ → **Histórica** |
| **D26** | **Idempotency key con índice parcial sobre estados activos (D2 de v1.1)** | **Aprobado v1.1** |
| **D27** | **Horarios: `hora_checkin`/`hora_checkout` = lo elegido por cliente (D3 de v1.1)** | **Aprobado v1.1** |
| **D28** | **`obtener_disponibilidad_rango` devuelve hora base, no escalonada** | **Aprobado v1.1** |
| **D29** | **Manejo controlado de exclusion_violation en funciones** | **Aprobado v1.1** |
| **D30** | **`cancelar_reserva()` y `modificar_reserva()` documentadas como futuras** | **Aprobado v1.1** |
| **D31** | **Principio "Carga manual segura"** | **Aprobado v1.1** |
| **D32** | **Contabilidad futura contemplada, no implementada** | **Aprobado v1.1** |
| **D33** | **`crear_bloqueo()` valida pre-reservas vigentes antes de crear** | **Aprobado v1.2** |
| **D34** | **`crear_bloqueo()` valida manualmente las 4 combinaciones de bloqueos solapados** | **Aprobado v1.2** |
| **D35** | **Idempotencia en `crear_prereserva()`: en `unique_violation` devuelve la existente** | **Aprobado v1.2** |
| **D36** | **`upsert_huesped()` diferenciado: conflicto por teléfono/email → silencioso, por DNI → error controlado** | **Aprobado v1.2** |
| **D37** | **`crear_prereserva()` lee config de horarios desde `configuracion_general` con fallback COALESCE** | **Aprobado v1.2** |
| **D38** | **Contexto de logs vía `set_config('app.modificado_por', ...)` en funciones críticas** | **Aprobado v1.2** |
| **D39** | **`pago_en_revision` en pre-reservas documentado con dos sub-casos sin agregar nuevo estado** | **Aprobado v1.2** |
| **D40** | **`consultar_disponibilidad_precio` pasa a pieza obligatoria antes de web pública** | **Aprobado v1.2** |
| **D41** | **Double-check de idempotencia post-lock en `crear_prereserva` (3 caminos de recovery)** | **Aprobado v1.3** |
| **D42** | **`crear_prereserva` valida `huesped.nombre` + contacto mínimo (Opción A); `upsert_huesped` queda flexible** | **Aprobado v1.3** |
| **D43** | **Retorno de `crear_prereserva` unificado con `recovery_path` (`pre_lock`/`post_lock`/`unique_violation`/`null`)** | **Aprobado v1.3** |
| **D44** | **`registrar_pago` sobre pre-reserva terminal: fuerza `en_revision`, no reactiva, devuelve warning** | **Aprobado v1.3** |
| **D45** | **Config inválida documentada como deuda técnica aceptable (no se implementa safe-cast)** | **Aprobado v1.3** |
| **D46** | **Advisory lock global `(10, 0)` de disponibilidad para serializar operaciones críticas. `LOCK TABLE` eliminado.** | **Aprobado v1.4** |
| **D47** | **Checkout dominical a las 16:00 como regla operativa de Vita Delta. Implementado en `crear_prereserva` (cálculo de `v_hora_checkout_max` con `CASE WHEN EXTRACT(DOW FROM v_fecha_out) = 0`) y propagado a `reservas` vía `confirmar_reserva` (que copia `hora_checkout` desde la pre-reserva sin transformaciones).** | **Aprobado v1.7** |

---

## 23. DUDAS QUE QUEDARON RESUELTAS

| Duda original | Resolución |
|---|---|
| Estados de CONSULTAS | nueva/en_progreso/derivada_humano/cerrada/descartada |
| Conceptos de TARIFAS | TEXT libre, sin enum |
| Tipos de PAGO | sena/saldo/extra/reembolso/ajuste |
| Tipo de FERIADOS | TEXT libre, valores orientativos |
| Crear tablas futuras vacías | Sí: descuentos, paquetes_evento, overrides_operativos |
| Tabla usuarios | No por ahora |
| Comportamiento upsert de huéspedes | Documentado en Sección 10.2 |
| Cómo manejar pre-reservas en EXCLUDE | Función transaccional con advisory lock (Capa 3) |
| pg_cron en free tier | Disponible. Mínimo 1 min. UTC. |
| Idempotencia de creación | `idempotency_key` con índice parcial |
| Bloqueo total y locks | ~~LOCK TABLE simple (decisión D1 v1.1)~~ → Reemplazado en v1.4: advisory lock global `(10, 0)` (D46) |
| Horarios del cliente | `hora_checkin`/`hora_checkout` = lo elegido. Validado contra margen. |
| Trazabilidad `escalonamiento_umbral_checkins_dia` | Establecido en Etapa 2 v1.3 + 5A v1.1. Comentario inline en SQL. |
| Verificación de pago en `confirmar_reserva` | Modo estricto + modo combinado opcional con `permitir_pago_en_revision` |
| Diferencia monto en pagos | No exige igualdad. `en_revision` si difiere. |
| `cancelar_prereserva` con pagos | No toca pagos. Devuelve cantidad asociada. |
| `crear_bloqueo` con conflicto | Rechaza con `conflicto_con_reserva`. Sin override en v1.1. |
| RLS | Principio documentado. Implementación en etapa con Auth. |
| Motor de precios y web pública | n8n por ahora. Endpoint `consultar_disponibilidad_precio` futuro. |

---

# PARTE B — SQL EJECUTABLE PROPUESTO PARA REVISIÓN

> **SQL propuesto para revisión antes de ejecutar.**
>
> No correr ningún bloque hasta revisar el documento completo y aprobar la ejecución bloque por bloque.

Ejecución sugerida: en el SQL Editor de Supabase, copiar UN bloque a la vez, revisar la salida, verificar con el query de verificación, y solo entonces pasar al siguiente bloque.

---

## BLOQUE 1 — Extensiones

**Descripción:** Habilita `btree_gist` (para EXCLUDE con id_cabana + daterange) y `pg_cron` (para schedule de expiración).

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_cron;
```

**Verificación post-ejecución:**

```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('btree_gist', 'pg_cron');
```

Debe devolver 2 filas.

**Rollback:**

```sql
DROP EXTENSION IF EXISTS pg_cron;
DROP EXTENSION IF EXISTS btree_gist;
```

**Riesgos:** ninguno. Habilitar extensiones no afecta nada existente.

---

## BLOQUE 2 — Enums

**Descripción:** Crea los 4 tipos enum para estados estables.

```sql
CREATE TYPE estado_prereserva_enum AS ENUM (
  'pendiente_pago',
  'pago_en_revision',
  'vencida',
  'convertida',
  'cancelada_por_cliente',
  'cancelada_por_bloqueo',
  'conflicto_pendiente'
);

CREATE TYPE estado_reserva_enum AS ENUM (
  'confirmada',
  'activa',
  'completada',
  'cancelada',
  'cancelada_con_cargo',
  'conflicto_pendiente'
);

CREATE TYPE estado_pago_enum AS ENUM (
  'pendiente',
  'en_revision',
  'confirmado',
  'rechazado',
  'reembolsado'
);

CREATE TYPE nivel_log_enum AS ENUM (
  'info',
  'warning',
  'error'
);
```

**Verificación post-ejecución:**

```sql
SELECT typname
FROM pg_type
WHERE typname LIKE '%_enum'
ORDER BY typname;
```

Debe devolver 4 filas.

**Rollback:**

```sql
DROP TYPE IF EXISTS estado_prereserva_enum;
DROP TYPE IF EXISTS estado_reserva_enum;
DROP TYPE IF EXISTS estado_pago_enum;
DROP TYPE IF EXISTS nivel_log_enum;
```

**Riesgos:** una vez que alguna tabla use estos tipos, DROP requiere CASCADE. Ejecutar rollback solo antes de Bloque 6.

---

## BLOQUE 3 — Tablas catálogo

**Descripción:** Crea tablas sin dependencias entre sí. **Nota v1.1:** `huespedes` incluye columna `telefono_normalizado`; el trigger se crea en Bloque 9.

```sql
-- ── CABAÑAS ───────────────────────────────────────────────
CREATE TABLE cabanas (
  id_cabana       BIGSERIAL PRIMARY KEY,
  nombre          TEXT NOT NULL,
  tipo            TEXT NOT NULL,
  capacidad_base  INTEGER NOT NULL,
  capacidad_max   INTEGER NOT NULL,
  activa          BOOLEAN NOT NULL DEFAULT TRUE,
  orden_limpieza  INTEGER,
  descripcion     TEXT,
  fotos_urls      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_cabanas_nombre UNIQUE (nombre),
  CONSTRAINT chk_cabanas_capacidad_logica CHECK (capacidad_base <= capacidad_max),
  CONSTRAINT chk_cabanas_capacidad_positiva CHECK (capacidad_base >= 1 AND capacidad_max >= 1)
);

-- ── HUÉSPEDES (con telefono_normalizado nuevo en v1.1) ────
CREATE TABLE huespedes (
  id_huesped              BIGSERIAL PRIMARY KEY,
  nombre                  TEXT NOT NULL,
  apellido                TEXT,
  dni                     TEXT,
  telefono                TEXT,
  telefono_normalizado    TEXT,
  email                   TEXT,
  canal_preferido         TEXT,
  primera_reserva_fecha   DATE,
  total_reservas          INTEGER NOT NULL DEFAULT 0,
  notas_internas          TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_huespedes_contacto_minimo CHECK (telefono IS NOT NULL OR email IS NOT NULL)
);

CREATE UNIQUE INDEX uq_huespedes_dni
  ON huespedes(dni) WHERE dni IS NOT NULL;

CREATE UNIQUE INDEX uq_huespedes_telefono_normalizado
  ON huespedes(telefono_normalizado) WHERE telefono_normalizado IS NOT NULL;

CREATE UNIQUE INDEX uq_huespedes_email
  ON huespedes(LOWER(email)) WHERE email IS NOT NULL;

-- ── FERIADOS ──────────────────────────────────────────────
CREATE TABLE feriados (
  fecha     DATE PRIMARY KEY,
  nombre    TEXT NOT NULL,
  tipo      TEXT,
  activo    BOOLEAN NOT NULL DEFAULT TRUE
);

-- ── TARIFAS ───────────────────────────────────────────────
CREATE TABLE tarifas (
  id_tarifa      BIGSERIAL PRIMARY KEY,
  tipo_cabana    TEXT NOT NULL,
  concepto       TEXT NOT NULL,
  precio         NUMERIC(12,2) NOT NULL,
  descripcion    TEXT,
  activa         BOOLEAN NOT NULL DEFAULT TRUE,
  valida_desde   DATE,
  valida_hasta   DATE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_tarifas_precio CHECK (precio >= 0)
);

CREATE UNIQUE INDEX uq_tarifas_concepto_vigente
  ON tarifas(tipo_cabana, concepto, valida_desde) WHERE activa = TRUE;

-- ── TEMPORADAS ────────────────────────────────────────────
CREATE TABLE temporadas (
  id_temporada     BIGSERIAL PRIMARY KEY,
  nombre           TEXT NOT NULL,
  fecha_desde      DATE NOT NULL,
  fecha_hasta      DATE NOT NULL,
  multiplicador    NUMERIC(5,3) NOT NULL,
  activa           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_temporadas_multiplicador CHECK (multiplicador > 0),
  CONSTRAINT chk_temporadas_fechas CHECK (fecha_hasta > fecha_desde)
);

-- ── SOCIOS ────────────────────────────────────────────────
CREATE TABLE socios (
  id_socio                BIGSERIAL PRIMARY KEY,
  nombre                  TEXT NOT NULL,
  porcentaje_utilidades   NUMERIC(5,2) NOT NULL,
  whatsapp                TEXT,
  activo                  BOOLEAN NOT NULL DEFAULT TRUE,

  CONSTRAINT chk_socios_porcentaje CHECK (porcentaje_utilidades >= 0 AND porcentaje_utilidades <= 100)
);

-- ── CUENTAS_COBRO ─────────────────────────────────────────
CREATE TABLE cuentas_cobro (
  id_cuenta      BIGSERIAL PRIMARY KEY,
  alias          TEXT NOT NULL,
  medio          TEXT NOT NULL,
  detalle        TEXT,
  titular        TEXT,
  activa         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_cuentas_medio CHECK (medio IN ('transferencia_bancaria', 'transferencia_mp', 'cripto', 'efectivo'))
);

-- ── PLANTILLAS_MENSAJES ───────────────────────────────────
CREATE TABLE plantillas_mensajes (
  id_plantilla   BIGSERIAL PRIMARY KEY,
  codigo         TEXT NOT NULL,
  nombre         TEXT NOT NULL,
  canal          TEXT NOT NULL,
  destinatario   TEXT NOT NULL,
  contenido      TEXT NOT NULL,
  variables      TEXT,
  activa         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_plantillas_codigo UNIQUE (codigo),
  CONSTRAINT chk_plantillas_canal CHECK (canal IN ('whatsapp', 'instagram', 'todos')),
  CONSTRAINT chk_plantillas_destinatario CHECK (destinatario IN ('huesped', 'equipo', 'limpieza', 'franco'))
);
```

**Verificación post-ejecución:**

```sql
SELECT tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('cabanas', 'huespedes', 'feriados', 'tarifas',
                    'temporadas', 'socios', 'cuentas_cobro', 'plantillas_mensajes')
ORDER BY tablename;
```

Debe devolver 8 filas.

```sql
-- Verificación específica de la columna nueva v1.1
SELECT column_name FROM information_schema.columns
WHERE table_name = 'huespedes' AND column_name = 'telefono_normalizado';
```

Debe devolver 1 fila.

**Rollback:**

```sql
DROP TABLE IF EXISTS plantillas_mensajes;
DROP TABLE IF EXISTS cuentas_cobro;
DROP TABLE IF EXISTS socios;
DROP TABLE IF EXISTS temporadas;
DROP TABLE IF EXISTS tarifas;
DROP TABLE IF EXISTS feriados;
DROP TABLE IF EXISTS huespedes;
DROP TABLE IF EXISTS cabanas;
```

---

## BLOQUE 4 — Tablas de configuración

**Descripción:** Crea `configuracion_general`, `eventos_especiales`, `paquetes_evento`, `descuentos`.

```sql
-- ── CONFIGURACION_GENERAL ─────────────────────────────────
CREATE TABLE configuracion_general (
  clave              TEXT PRIMARY KEY,
  valor              TEXT NOT NULL,
  tipo_valor         TEXT,
  descripcion        TEXT,
  categoria          TEXT,
  editable           BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── EVENTOS_ESPECIALES ────────────────────────────────────
CREATE TABLE eventos_especiales (
  id_evento          BIGSERIAL PRIMARY KEY,
  nombre             TEXT NOT NULL,
  fecha_desde        DATE NOT NULL,
  fecha_hasta        DATE NOT NULL,
  modo_precio        TEXT,
  reglas_especiales  JSONB,
  activa             BOOLEAN NOT NULL DEFAULT TRUE,
  source_event       TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_eventos_fechas CHECK (fecha_hasta >= fecha_desde)
);

-- ── PAQUETES_EVENTO ───────────────────────────────────────
CREATE TABLE paquetes_evento (
  id_paquete       BIGSERIAL PRIMARY KEY,
  id_evento        BIGINT NOT NULL REFERENCES eventos_especiales(id_evento) ON DELETE CASCADE,
  tipo_cabana      TEXT NOT NULL,
  nombre_paquete   TEXT NOT NULL,
  fecha_in         DATE,
  fecha_out        DATE,
  precio_total     NUMERIC(12,2) NOT NULL DEFAULT 0,
  personas_max     INTEGER,
  incluye          TEXT,
  notas            TEXT,
  activo           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── DESCUENTOS ────────────────────────────────────────────
CREATE TABLE descuentos (
  id_descuento          BIGSERIAL PRIMARY KEY,
  nombre                TEXT NOT NULL,
  tipo                  TEXT NOT NULL,
  valor                 NUMERIC(12,2) NOT NULL,
  aplica_a              TEXT NOT NULL,
  aplica_sobre          TEXT NOT NULL,
  fecha_desde           DATE,
  fecha_hasta           DATE,
  codigo                TEXT,
  usos_maximos          INTEGER,
  usos_actuales         INTEGER NOT NULL DEFAULT 0,
  minimo_noches         INTEGER,
  monto_minimo          NUMERIC(12,2),
  prioridad             INTEGER NOT NULL DEFAULT 100,
  combinable            BOOLEAN NOT NULL DEFAULT FALSE,
  requiere_aprobacion   BOOLEAN NOT NULL DEFAULT FALSE,
  activo                BOOLEAN NOT NULL DEFAULT TRUE,
  source_event          TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_descuentos_valor_positivo CHECK (valor > 0),
  CONSTRAINT chk_descuentos_tipo CHECK (tipo IN ('porcentaje', 'monto_fijo', 'noche_gratis')),
  CONSTRAINT chk_descuentos_aplica_a CHECK (aplica_a IN ('todas', 'grande', 'chica')),
  CONSTRAINT chk_descuentos_aplica_sobre CHECK (aplica_sobre IN ('alojamiento', 'extras', 'total')),
  CONSTRAINT chk_descuentos_fechas CHECK (
    (fecha_desde IS NULL OR fecha_hasta IS NULL) OR (fecha_hasta >= fecha_desde)
  )
);
```

**Verificación post-ejecución:**

```sql
SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  AND tablename IN ('configuracion_general', 'eventos_especiales', 'paquetes_evento', 'descuentos')
ORDER BY tablename;
```

Debe devolver 4 filas.

**Rollback:**

```sql
DROP TABLE IF EXISTS descuentos;
DROP TABLE IF EXISTS paquetes_evento;
DROP TABLE IF EXISTS eventos_especiales;
DROP TABLE IF EXISTS configuracion_general;
```

---

## BLOQUE 5 — Tablas dependientes nivel 1

**Descripción:** Crea `consultas` y `overrides_operativos`.

```sql
-- ── CONSULTAS ─────────────────────────────────────────────
CREATE TABLE consultas (
  id_consulta             BIGSERIAL PRIMARY KEY,
  canal                   TEXT NOT NULL,
  id_contacto_externo     TEXT NOT NULL,
  id_huesped              BIGINT REFERENCES huespedes(id_huesped) ON DELETE SET NULL,
  estado_conversacion     TEXT NOT NULL DEFAULT 'nueva',
  id_cabana_tentativa     BIGINT REFERENCES cabanas(id_cabana) ON DELETE SET NULL,
  fecha_in_tentativa      DATE,
  fecha_out_tentativa     DATE,
  personas_tentativa      INTEGER,
  ultimo_mensaje_at       TIMESTAMPTZ,
  contexto_json           JSONB,
  tokens_json             JSONB,
  motivo_derivacion       TEXT,
  source_event            TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_consultas_canal CHECK (canal IN ('whatsapp', 'instagram', 'web', 'manual')),
  CONSTRAINT chk_consultas_estado CHECK (
    estado_conversacion IN ('nueva', 'en_progreso', 'derivada_humano', 'cerrada', 'descartada')
  )
);

CREATE INDEX idx_consultas_estado ON consultas(estado_conversacion);
CREATE INDEX idx_consultas_huesped ON consultas(id_huesped);
CREATE INDEX idx_consultas_contacto_externo ON consultas(id_contacto_externo);

-- ── OVERRIDES_OPERATIVOS ──────────────────────────────────
-- NOTA DE TRAZABILIDAD (v1.1):
-- 'escalonamiento_umbral_checkins_dia' es el rename oficial cerrado en Etapa 2 v1.3 y Etapa 5A v1.1.
-- Reemplaza a las antiguas claves 'escalonamiento_umbral_checkout' y 'escalonamiento_umbral_checkin'.
-- No cambiar este nombre sin actualizar primero esa documentación.
CREATE TABLE overrides_operativos (
  id_override     BIGSERIAL PRIMARY KEY,
  fecha_desde     DATE NOT NULL,
  fecha_hasta     DATE,
  id_cabana       BIGINT REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  tipo_override   TEXT NOT NULL,
  valor           TEXT NOT NULL,
  motivo          TEXT NOT NULL,
  creado_por      TEXT NOT NULL,
  activo          BOOLEAN NOT NULL DEFAULT TRUE,
  source_event    TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_overrides_tipo CHECK (
    tipo_override IN (
      'escalonamiento_activo',
      'escalonamiento_umbral_checkins_dia',  -- ver nota de trazabilidad arriba
      'hora_checkin',
      'hora_checkout',
      'checkin_flexible',
      'checkout_flexible',
      'minimo_noches',
      'disponibilidad_bloqueada'
    )
  ),
  CONSTRAINT chk_overrides_fechas CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);

CREATE INDEX idx_overrides_activo_fechas ON overrides_operativos(activo, fecha_desde, fecha_hasta);
```

**Verificación post-ejecución:**

```sql
SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  AND tablename IN ('consultas', 'overrides_operativos');
```

**Rollback:**

```sql
DROP TABLE IF EXISTS overrides_operativos;
DROP TABLE IF EXISTS consultas;
```

---

## BLOQUE 6 — Tablas transaccionales

**Descripción:** Crea `pre_reservas`, `reservas`, `pagos`, `bloqueos`, `gastos`. **Cambios v1.1:**
- `pre_reservas` incluye `idempotency_key` (nueva) y los 4 campos operativos.
- `reservas` incluye los 4 campos operativos.
- `pagos.id_prereserva` ahora nullable + CHECK que al menos una referencia exista.

```sql
-- ── PRE_RESERVAS (con campos nuevos v1.1) ─────────────────
CREATE TABLE pre_reservas (
  id_pre_reserva         BIGSERIAL PRIMARY KEY,
  id_consulta            BIGINT REFERENCES consultas(id_consulta) ON DELETE SET NULL,
  id_cabana              BIGINT NOT NULL REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  id_huesped             BIGINT NOT NULL REFERENCES huespedes(id_huesped) ON DELETE RESTRICT,
  fecha_in               DATE NOT NULL,
  fecha_out              DATE NOT NULL,
  hora_checkin           TIME NOT NULL,
  hora_checkout          TIME NOT NULL,
  personas               INTEGER NOT NULL,
  monto_total            NUMERIC(12,2) NOT NULL,
  monto_sena             NUMERIC(12,2) NOT NULL,
  estado                 estado_prereserva_enum NOT NULL DEFAULT 'pendiente_pago',
  expira_en              TIMESTAMPTZ NOT NULL,
  canal_pago_esperado    TEXT NOT NULL,
  canal_origen           TEXT NOT NULL,
  intentos_pago          INTEGER NOT NULL DEFAULT 0,
  referencia_mp          TEXT,
  notas                  TEXT,
  source_event           TEXT NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Campos operativos (D16)
  mascotas               BOOLEAN NOT NULL DEFAULT FALSE,
  detalle_mascotas       TEXT,
  ninos                  TEXT,
  notas_reserva          TEXT,

  -- Idempotencia (v1.1)
  idempotency_key        TEXT,

  CONSTRAINT chk_pre_reservas_fechas CHECK (fecha_out > fecha_in),
  CONSTRAINT chk_pre_reservas_personas CHECK (personas >= 1),
  CONSTRAINT chk_pre_reservas_monto_total CHECK (monto_total > 0),
  CONSTRAINT chk_pre_reservas_sena_logica CHECK (monto_sena >= 0 AND monto_sena <= monto_total),
  CONSTRAINT chk_pre_reservas_canal_origen CHECK (
    canal_origen IN ('whatsapp', 'instagram', 'web', 'manual')
  ),
  CONSTRAINT chk_pre_reservas_canal_pago CHECK (
    canal_pago_esperado IN ('transferencia_bancaria', 'transferencia_mp', 'mp_link', 'cripto', 'efectivo')
  )
);

CREATE INDEX idx_pre_reservas_estado ON pre_reservas(estado);
CREATE INDEX idx_pre_reservas_cabana_fechas ON pre_reservas(id_cabana, fecha_in, fecha_out);
CREATE INDEX idx_pre_reservas_expira ON pre_reservas(expira_en) WHERE estado = 'pendiente_pago';
CREATE INDEX idx_pre_reservas_huesped ON pre_reservas(id_huesped);

-- Índice parcial para idempotency (v1.1, decisión D26)
CREATE UNIQUE INDEX uq_prereservas_idempotency_activa
  ON pre_reservas(idempotency_key)
  WHERE idempotency_key IS NOT NULL
    AND estado IN ('pendiente_pago', 'pago_en_revision');

-- ── RESERVAS (con campos operativos v1.1) ─────────────────
CREATE TABLE reservas (
  id_reserva              BIGSERIAL PRIMARY KEY,
  id_pre_reserva          BIGINT REFERENCES pre_reservas(id_pre_reserva) ON DELETE SET NULL,
  id_cabana               BIGINT NOT NULL REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  id_huesped              BIGINT NOT NULL REFERENCES huespedes(id_huesped) ON DELETE RESTRICT,
  fecha_checkin           DATE NOT NULL,
  fecha_checkout          DATE NOT NULL,
  hora_checkin            TIME NOT NULL,
  hora_checkout           TIME NOT NULL,
  personas                INTEGER NOT NULL,
  estado                  estado_reserva_enum NOT NULL DEFAULT 'confirmada',
  canal_origen            TEXT NOT NULL,
  id_tarifa_aplicada      BIGINT REFERENCES tarifas(id_tarifa) ON DELETE SET NULL,
  monto_total             NUMERIC(12,2) NOT NULL,
  monto_sena              NUMERIC(12,2) NOT NULL,
  monto_saldo             NUMERIC(12,2) NOT NULL,
  encargado_semana        TEXT,
  notas                   TEXT,
  created_by              TEXT,
  source_event            TEXT NOT NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Campos operativos (D17 — preservan info al confirmar)
  mascotas                BOOLEAN NOT NULL DEFAULT FALSE,
  detalle_mascotas        TEXT,
  ninos                   TEXT,
  notas_reserva           TEXT,

  CONSTRAINT chk_reservas_fechas CHECK (fecha_checkout > fecha_checkin),
  CONSTRAINT chk_reservas_personas CHECK (personas >= 1),
  CONSTRAINT chk_reservas_monto_total CHECK (monto_total > 0),
  CONSTRAINT chk_reservas_saldo_logica CHECK (monto_saldo >= 0 AND monto_saldo <= monto_total),
  CONSTRAINT chk_reservas_canal_origen CHECK (
    canal_origen IN ('whatsapp', 'instagram', 'web', 'manual', 'airbnb', 'booking')
  )
);

CREATE INDEX idx_reservas_estado ON reservas(estado);
CREATE INDEX idx_reservas_cabana_fechas ON reservas(id_cabana, fecha_checkin, fecha_checkout);
CREATE INDEX idx_reservas_huesped ON reservas(id_huesped);
CREATE INDEX idx_reservas_fecha_checkin ON reservas(fecha_checkin);

-- ── PAGOS (cambios v1.1: id_prereserva nullable + CHECK) ──
CREATE TABLE pagos (
  id_pago               BIGSERIAL PRIMARY KEY,
  id_prereserva         BIGINT REFERENCES pre_reservas(id_pre_reserva) ON DELETE RESTRICT,
  id_reserva            BIGINT REFERENCES reservas(id_reserva) ON DELETE SET NULL,
  tipo                  TEXT NOT NULL,
  medio_pago            TEXT NOT NULL,
  proveedor             TEXT,
  cuenta_destino        TEXT,
  monto_esperado        NUMERIC(12,2) NOT NULL,
  monto_recibido        NUMERIC(12,2) NOT NULL,
  moneda                TEXT NOT NULL DEFAULT 'ARS',
  estado                estado_pago_enum NOT NULL DEFAULT 'pendiente',
  es_automatico         BOOLEAN NOT NULL DEFAULT FALSE,
  comprobante_url       TEXT,
  referencia_externa    TEXT,
  tx_hash               TEXT,
  validado_por          TEXT,
  validado_en           TIMESTAMPTZ,
  motivo_rechazo        TEXT,
  notas                 TEXT,
  source_event          TEXT NOT NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_pagos_tipo CHECK (tipo IN ('sena', 'saldo', 'extra', 'reembolso', 'ajuste')),
  CONSTRAINT chk_pagos_medio CHECK (
    medio_pago IN ('transferencia_bancaria', 'transferencia_mp', 'mp_link', 'cripto', 'efectivo')
  ),
  CONSTRAINT chk_pagos_monto_recibido CHECK (monto_recibido >= 0),
  CONSTRAINT chk_pagos_monto_esperado CHECK (monto_esperado > 0),
  -- Cambio v1.1: al menos una de las dos referencias debe existir
  CONSTRAINT chk_pagos_referencia_minima CHECK (id_prereserva IS NOT NULL OR id_reserva IS NOT NULL)
);

CREATE INDEX idx_pagos_prereserva ON pagos(id_prereserva) WHERE id_prereserva IS NOT NULL;
CREATE INDEX idx_pagos_reserva ON pagos(id_reserva) WHERE id_reserva IS NOT NULL;
CREATE INDEX idx_pagos_estado ON pagos(estado);

-- ── BLOQUEOS ──────────────────────────────────────────────
CREATE TABLE bloqueos (
  id_bloqueo      BIGSERIAL PRIMARY KEY,
  id_cabana       BIGINT REFERENCES cabanas(id_cabana) ON DELETE RESTRICT,
  fecha_desde     DATE NOT NULL,
  fecha_hasta     DATE NOT NULL,
  motivo          TEXT NOT NULL,
  descripcion     TEXT,
  creado_por      TEXT NOT NULL,
  activo          BOOLEAN NOT NULL DEFAULT TRUE,
  source_event    TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_bloqueos_fechas CHECK (fecha_hasta > fecha_desde),
  CONSTRAINT chk_bloqueos_motivo CHECK (
    motivo IN ('mantenimiento', 'uso_propio', 'tormenta', 'overbooking', 'otro')
  )
);

CREATE INDEX idx_bloqueos_activo_fechas ON bloqueos(activo, fecha_desde, fecha_hasta) WHERE activo = TRUE;

-- ── GASTOS ────────────────────────────────────────────────
CREATE TABLE gastos (
  id_gasto         BIGSERIAL PRIMARY KEY,
  fecha            DATE NOT NULL,
  categoria        TEXT NOT NULL,
  descripcion      TEXT NOT NULL,
  monto            NUMERIC(12,2) NOT NULL,
  id_cabana        BIGINT REFERENCES cabanas(id_cabana) ON DELETE SET NULL,
  pagado_por       TEXT NOT NULL,
  reembolsable     BOOLEAN NOT NULL DEFAULT FALSE,
  comprobante_url  TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_gastos_fecha ON gastos(fecha);
CREATE INDEX idx_gastos_categoria ON gastos(categoria);
```

**Verificación post-ejecución:**

```sql
SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  AND tablename IN ('pre_reservas', 'reservas', 'pagos', 'bloqueos', 'gastos')
ORDER BY tablename;
```

Debe devolver 5 filas.

```sql
-- Verificar campos operativos en pre_reservas y reservas
SELECT table_name, column_name FROM information_schema.columns
WHERE table_name IN ('pre_reservas', 'reservas')
  AND column_name IN ('mascotas', 'detalle_mascotas', 'ninos', 'notas_reserva')
ORDER BY table_name, column_name;
```

Debe devolver 8 filas (4 por tabla).

```sql
-- Verificar idempotency_key en pre_reservas
SELECT column_name FROM information_schema.columns
WHERE table_name = 'pre_reservas' AND column_name = 'idempotency_key';
```

Debe devolver 1 fila.

```sql
-- Verificar CHECK de pagos v1.1
SELECT conname FROM pg_constraint
WHERE conname = 'chk_pagos_referencia_minima';
```

Debe devolver 1 fila.

**Rollback:**

```sql
DROP TABLE IF EXISTS gastos;
DROP TABLE IF EXISTS bloqueos;
DROP TABLE IF EXISTS pagos;
DROP TABLE IF EXISTS reservas;
DROP TABLE IF EXISTS pre_reservas;
```

---

## BLOQUE 7 — Tabla de auditoría

```sql
CREATE TABLE log_cambios (
  id_log              BIGSERIAL PRIMARY KEY,
  fecha_hora          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  tabla_afectada      TEXT NOT NULL,
  id_registro         TEXT,
  campo_modificado    TEXT,
  valor_anterior      TEXT,
  valor_nuevo         TEXT,
  modificado_por      TEXT NOT NULL,
  source_event        TEXT NOT NULL,
  nivel               nivel_log_enum NOT NULL DEFAULT 'info',
  detalle             JSONB
);

CREATE INDEX idx_log_cambios_fecha ON log_cambios(fecha_hora DESC);
CREATE INDEX idx_log_cambios_tabla ON log_cambios(tabla_afectada);
CREATE INDEX idx_log_cambios_nivel ON log_cambios(nivel) WHERE nivel != 'info';
CREATE INDEX idx_log_cambios_detalle_gin ON log_cambios USING GIN(detalle);
```

**Verificación post-ejecución:**

```sql
SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename = 'log_cambios';
```

**Rollback:**

```sql
DROP TABLE IF EXISTS log_cambios;
```

---

## BLOQUE 8 — Constraints EXCLUDE

**Descripción:** Garantía estructural de no-overlap en reservas y bloqueos. Pre-reservas se controlan vía `crear_prereserva()` (Bloque 13).

```sql
-- No-overlap en reservas confirmadas/activas
ALTER TABLE reservas
  ADD CONSTRAINT exc_reservas_no_overlap
  EXCLUDE USING gist (
    id_cabana WITH =,
    daterange(fecha_checkin, fecha_checkout, '[)') WITH &&
  ) WHERE (estado IN ('confirmada', 'activa'));

-- No-overlap en bloqueos activos sobre cabaña específica
-- (bloqueos totales con id_cabana NULL se validan en crear_bloqueo)
ALTER TABLE bloqueos
  ADD CONSTRAINT exc_bloqueos_no_overlap
  EXCLUDE USING gist (
    id_cabana WITH =,
    daterange(fecha_desde, fecha_hasta, '[)') WITH &&
  ) WHERE (activo = TRUE AND id_cabana IS NOT NULL);
```

**Verificación post-ejecución:**

```sql
SELECT conname, conrelid::regclass
FROM pg_constraint
WHERE conname LIKE 'exc_%';
```

Debe devolver 2 filas.

**Rollback:**

```sql
ALTER TABLE reservas DROP CONSTRAINT IF EXISTS exc_reservas_no_overlap;
ALTER TABLE bloqueos DROP CONSTRAINT IF EXISTS exc_bloqueos_no_overlap;
```

---

## BLOQUE 9 — Función `normalizar_telefono` + columna + trigger

**Descripción:** Crea el helper IMMUTABLE de normalización y el trigger que mantiene la columna `telefono_normalizado` actualizada.

```sql
-- ── Helper: normalizar_telefono ──────────────────────────
-- IMMUTABLE: para que pueda usarse en índices funcionales si hace falta.
-- Reglas:
--   - NULL/'' → NULL
--   - quitar espacios, guiones, paréntesis, puntos
--   - '00' inicial → '+'
--   - colapsar múltiples '+' consecutivos a uno solo
--   - no asumir +54 automático (Vita Delta puede recibir extranjeros)
CREATE OR REPLACE FUNCTION normalizar_telefono(input TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  IF input IS NULL OR TRIM(input) = '' THEN
    RETURN NULL;
  END IF;

  -- Quitar espacios, guiones, paréntesis, puntos
  v_clean := REGEXP_REPLACE(input, '[\s\-\(\)\.]', '', 'g');

  -- Si empieza con '00', reemplazar por '+'
  IF v_clean LIKE '00%' THEN
    v_clean := '+' || SUBSTRING(v_clean FROM 3);
  END IF;

  -- Colapsar múltiples '+' a uno solo (solo válido al inicio)
  -- Primero: quitar todos los '+' excepto el primero
  IF v_clean LIKE '+%' THEN
    v_clean := '+' || REGEXP_REPLACE(SUBSTRING(v_clean FROM 2), '[^0-9]', '', 'g');
  ELSE
    -- Sin '+', dejar solo dígitos
    v_clean := REGEXP_REPLACE(v_clean, '[^0-9]', '', 'g');
  END IF;

  -- Si quedó vacío después de limpiar, retornar NULL
  IF v_clean = '' OR v_clean = '+' THEN
    RETURN NULL;
  END IF;

  RETURN v_clean;
END;
$$;

-- ── Trigger function para mantener telefono_normalizado ──
CREATE OR REPLACE FUNCTION set_telefono_normalizado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.telefono_normalizado := normalizar_telefono(NEW.telefono);
  RETURN NEW;
END;
$$;

-- ── Trigger en huespedes ─────────────────────────────────
CREATE TRIGGER trg_huespedes_telefono_norm
  BEFORE INSERT OR UPDATE OF telefono ON huespedes
  FOR EACH ROW EXECUTE FUNCTION set_telefono_normalizado();
```

**Verificación post-ejecución:**

```sql
SELECT proname FROM pg_proc WHERE proname IN ('normalizar_telefono', 'set_telefono_normalizado');
-- 2 filas

SELECT trigger_name FROM information_schema.triggers
WHERE event_object_table = 'huespedes' AND trigger_name = 'trg_huespedes_telefono_norm';
-- 1 fila
```

**Test funcional:**

```sql
SELECT
  normalizar_telefono('+54 9 11 3456-7890')  AS caso_1,  -- esperado: +5491134567890
  normalizar_telefono('0054 11 3456 7890')   AS caso_2,  -- esperado: +541134567890
  normalizar_telefono('(11) 3456-7890')      AS caso_3,  -- esperado: 1134567890
  normalizar_telefono('++54 11 3456 7890')   AS caso_4,  -- esperado: +541134567890 (colapsa +)
  normalizar_telefono('')                    AS caso_5,  -- esperado: NULL
  normalizar_telefono(NULL)                  AS caso_6;  -- esperado: NULL
```

**Rollback:**

```sql
DROP TRIGGER IF EXISTS trg_huespedes_telefono_norm ON huespedes;
DROP FUNCTION IF EXISTS set_telefono_normalizado();
DROP FUNCTION IF EXISTS normalizar_telefono(TEXT);
```

---

## BLOQUE 10 — Función `upsert_huesped`

**Descripción:** Implementa la lógica de búsqueda y actualización de huéspedes. Busca por teléfono normalizado primero, luego por email. No borra datos existentes con campos vacíos.

**Cambio en v1.2 (D36):** manejo diferenciado de `unique_violation`:
- Conflicto por `telefono_normalizado` o `email`: recuperación silenciosa. Re-busca y devuelve `modo='recovered_from_unique_violation'`.
- Conflicto por `DNI`: devuelve `error='huesped_duplicado'` con detalle, porque DNI duplicado con datos distintos es operativamente ambiguo y requiere revisión humana.

```sql
CREATE OR REPLACE FUNCTION upsert_huesped(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_nombre            TEXT;
  v_apellido          TEXT;
  v_dni               TEXT;
  v_telefono_raw      TEXT;
  v_telefono_norm     TEXT;
  v_email_raw         TEXT;
  v_email_norm        TEXT;
  v_canal_preferido   TEXT;
  v_huesped           huespedes%ROWTYPE;
  v_huesped_existente huespedes%ROWTYPE;
  v_found_by          TEXT;
  v_constraint_name   TEXT;
BEGIN
  -- Extraer y limpiar campos del payload (NULL si vienen vacíos)
  v_nombre          := NULLIF(TRIM(payload->>'nombre'), '');
  v_apellido        := NULLIF(TRIM(payload->>'apellido'), '');
  v_dni             := NULLIF(TRIM(payload->>'dni'), '');
  v_telefono_raw    := NULLIF(TRIM(payload->>'telefono'), '');
  v_email_raw       := NULLIF(TRIM(payload->>'email'), '');
  v_canal_preferido := NULLIF(TRIM(payload->>'canal_preferido'), '');

  -- Normalizar teléfono usando el helper
  v_telefono_norm := normalizar_telefono(v_telefono_raw);

  -- Normalizar email
  IF v_email_raw IS NOT NULL THEN
    v_email_norm := LOWER(v_email_raw);
  END IF;

  -- 1. Buscar por telefono_normalizado
  IF v_telefono_norm IS NOT NULL THEN
    SELECT * INTO v_huesped
    FROM huespedes
    WHERE telefono_normalizado = v_telefono_norm
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
      v_found_by := 'telefono';
    END IF;
  END IF;

  -- 2. Si no encontró por teléfono, buscar por email normalizado
  IF v_huesped.id_huesped IS NULL AND v_email_norm IS NOT NULL THEN
    SELECT * INTO v_huesped
    FROM huespedes
    WHERE LOWER(email) = v_email_norm
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
      v_found_by := 'email';
    END IF;
  END IF;

  -- 3. Si encontró: UPDATE selectivo (solo campos con valor real)
  IF v_huesped.id_huesped IS NOT NULL THEN
    BEGIN
      UPDATE huespedes SET
        nombre          = COALESCE(v_nombre, nombre),
        apellido        = COALESCE(v_apellido, apellido),
        dni             = COALESCE(v_dni, dni),
        telefono        = COALESCE(v_telefono_raw, telefono),
        -- telefono_normalizado se actualiza por trigger al modificar telefono
        email           = COALESCE(v_email_norm, email),
        canal_preferido = COALESCE(v_canal_preferido, canal_preferido),
        updated_at      = NOW()
      WHERE id_huesped = v_huesped.id_huesped;

    EXCEPTION
      WHEN unique_violation THEN
        -- Caso raro: el UPDATE intenta poner un DNI/email/telefono que ya pertenece a OTRO huésped.
        -- Devolver error controlado.
        GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
        RETURN jsonb_build_object(
          'ok',         false,
          'error',      'huesped_duplicado',
          'conflicto',  CASE
                          WHEN v_constraint_name LIKE '%dni%' THEN 'dni'
                          WHEN v_constraint_name LIKE '%email%' THEN 'email'
                          WHEN v_constraint_name LIKE '%telefono%' THEN 'telefono'
                          ELSE 'desconocido'
                        END,
          'detalle',    jsonb_build_object('constraint', v_constraint_name)
        );
    END;

    RETURN jsonb_build_object(
      'ok',             true,
      'modo',           'update',
      'id_huesped',     v_huesped.id_huesped,
      'encontrado_por', v_found_by
    );
  END IF;

  -- 4. CREATE — validar contacto mínimo
  IF v_telefono_norm IS NULL AND v_email_norm IS NULL THEN
    RETURN jsonb_build_object(
      'ok',     false,
      'error',  'contacto_requerido',
      'motivo', 'Debe venir al menos telefono o email'
    );
  END IF;

  -- 5. INSERT con manejo diferenciado de unique_violation
  BEGIN
    INSERT INTO huespedes (
      nombre, apellido, dni, telefono, email, canal_preferido
    ) VALUES (
      COALESCE(v_nombre, 'Sin nombre'),
      v_apellido,
      v_dni,
      v_telefono_raw,
      v_email_norm,
      v_canal_preferido
    )
    RETURNING * INTO v_huesped;

  EXCEPTION
    WHEN unique_violation THEN
      -- Captura el nombre del constraint que falló
      GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;

      -- Caso A: conflicto por DNI → ERROR CONTROLADO (D36)
      -- DNI duplicado con datos distintos es ambiguo. No fusionar silenciosamente.
      IF v_constraint_name LIKE '%dni%' THEN
        SELECT * INTO v_huesped_existente
        FROM huespedes WHERE dni = v_dni LIMIT 1;

        RETURN jsonb_build_object(
          'ok',                    false,
          'error',                 'huesped_duplicado',
          'conflicto',             'dni',
          'id_huesped_existente',  v_huesped_existente.id_huesped,
          'detalle',               jsonb_build_object(
            'nombre',           v_huesped_existente.nombre,
            'apellido',         v_huesped_existente.apellido,
            'telefono_parcial', RIGHT(v_huesped_existente.telefono_normalizado, 4),
            'email_parcial',    SPLIT_PART(v_huesped_existente.email, '@', 2)
          ),
          'motivo',                'DNI duplicado con datos distintos. Revisar manualmente.'
        );
      END IF;

      -- Caso B: conflicto por teléfono normalizado → RECUPERACIÓN SILENCIOSA (D36)
      -- Carrera típica: dos requests simultáneos para el mismo huésped.
      IF v_constraint_name LIKE '%telefono%' THEN
        SELECT * INTO v_huesped
        FROM huespedes WHERE telefono_normalizado = v_telefono_norm LIMIT 1;

        IF FOUND THEN
          RETURN jsonb_build_object(
            'ok',             true,
            'modo',           'recovered_from_unique_violation',
            'id_huesped',     v_huesped.id_huesped,
            'encontrado_por', 'telefono'
          );
        END IF;
      END IF;

      -- Caso C: conflicto por email → RECUPERACIÓN SILENCIOSA (D36)
      IF v_constraint_name LIKE '%email%' THEN
        SELECT * INTO v_huesped
        FROM huespedes WHERE LOWER(email) = v_email_norm LIMIT 1;

        IF FOUND THEN
          RETURN jsonb_build_object(
            'ok',             true,
            'modo',           'recovered_from_unique_violation',
            'id_huesped',     v_huesped.id_huesped,
            'encontrado_por', 'email'
          );
        END IF;
      END IF;

      -- Si no entró en ningún caso conocido o no se encontró el match esperado:
      -- error técnico controlado, no error crudo.
      RETURN jsonb_build_object(
        'ok',         false,
        'error',      'huesped_conflicto_inesperado',
        'detalle',    jsonb_build_object('constraint', v_constraint_name)
      );
  END;

  RETURN jsonb_build_object(
    'ok',             true,
    'modo',           'create',
    'id_huesped',     v_huesped.id_huesped,
    'encontrado_por', NULL
  );
END;
$$;
```

**Verificación post-ejecución:**

```sql
SELECT proname FROM pg_proc WHERE proname = 'upsert_huesped';
```

**Test funcional:**

```sql
-- Test 1: crear huésped nuevo (telefono específico para Bloque 10)
SELECT upsert_huesped(jsonb_build_object(
  'nombre',   'Juan',
  'telefono', '+54 9 11 1010-1010',
  'email',    'juan-test10@example.com'
));
-- Esperado: { "ok": true, "modo": "create", "id_huesped": N, "encontrado_por": null }

-- Test 2: buscar por teléfono normalizado (mismo telefono que Test 1)
SELECT upsert_huesped(jsonb_build_object(
  'telefono', '+5491110101010'
));
-- Esperado: { "ok": true, "modo": "update", "id_huesped": N, "encontrado_por": "telefono" }

-- Test 3: contacto mínimo no cumplido
SELECT upsert_huesped(jsonb_build_object(
  'nombre', 'Sin contacto'
));
-- Esperado: { "ok": false, "error": "contacto_requerido", ... }

-- Test 4 (opcional, requiere setup previo de un huésped con DNI 'X'):
-- intentar crear otro huésped con mismo DNI pero teléfono y email distintos.
-- Esperado: { "ok": false, "error": "huesped_duplicado", "conflicto": "dni", ... }
```

**Rollback:**

```sql
DROP FUNCTION IF EXISTS upsert_huesped(JSONB);
```

---

## BLOQUE 11 — Función `validar_disponibilidad`

**Descripción:** Función auxiliar que verifica solapamientos. Lockea filas relevantes con SELECT FOR UPDATE. **No toma advisory lock por sí misma** — eso es responsabilidad del caller (típicamente `crear_prereserva` o `confirmar_reserva`).

**Advertencia v1.5 (Observación G) — leer antes de usar esta función:**

> Esta función ejecuta `SELECT ... FOR UPDATE` internamente sobre `cabanas`, `reservas`, `pre_reservas` y `bloqueos`. Esos son row-level locks que PostgreSQL incluye en su grafo de detección de deadlocks.
>
> **Debe ser llamada SOLAMENTE desde funciones que ya tomaron `pg_advisory_xact_lock(10, 0)` (lock global de disponibilidad).**
>
> Si alguien la llama en un flujo crítico sin lock global previo, puede reintroducir los problemas de concurrencia que la Capa 0 resuelve (deadlocks `40P01`, conflictos intercalados con `crear_bloqueo`, etc.).
>
> Para queries ad-hoc de solo lectura (reportes, dashboards), está OK usarla sin lock global porque los row locks de PostgreSQL se liberan al finalizar la transacción y no compiten con escrituras.

```sql
CREATE OR REPLACE FUNCTION validar_disponibilidad(
  p_id_cabana       BIGINT,
  p_fecha_in        DATE,
  p_fecha_out       DATE,
  p_excluir_prereserva BIGINT DEFAULT NULL  -- para excluir la propia al confirmar
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
-- ADVERTENCIA (v1.5 - Obs G):
-- Esta función usa SELECT ... FOR UPDATE internamente.
-- DEBE llamarse desde transacciones que ya tomaron pg_advisory_xact_lock(10, 0).
-- En flujos críticos, llamarla sin lock global puede causar deadlocks (40P01).
DECLARE
  v_cabana          cabanas%ROWTYPE;
  v_conflictos      JSONB := '[]'::JSONB;
  v_tiene_conflicto BOOLEAN := FALSE;
BEGIN
  -- Validar argumentos básicos
  IF p_fecha_out <= p_fecha_in THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas');
  END IF;

  IF p_id_cabana IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'id_cabana_requerido');
  END IF;

  -- Verificar cabaña existe y activa
  SELECT * INTO v_cabana FROM cabanas WHERE id_cabana = p_id_cabana FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_existe');
  END IF;

  IF NOT v_cabana.activa THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_inactiva');
  END IF;

  -- Conflicto con reservas (confirmada o activa)
  IF EXISTS (
    SELECT 1 FROM reservas
    WHERE id_cabana = p_id_cabana
      AND estado IN ('confirmada', 'activa')
      AND daterange(fecha_checkin, fecha_checkout, '[)')
          && daterange(p_fecha_in, p_fecha_out, '[)')
    FOR UPDATE
  ) THEN
    v_conflictos := v_conflictos || jsonb_build_array(
      jsonb_build_object('fuente', 'reservas')
    );
    v_tiene_conflicto := TRUE;
  END IF;

  -- Conflicto con pre_reservas vigentes (excluyendo la propia si aplica)
  IF EXISTS (
    SELECT 1 FROM pre_reservas
    WHERE id_cabana = p_id_cabana
      AND (p_excluir_prereserva IS NULL OR id_pre_reserva != p_excluir_prereserva)
      AND (
        (estado = 'pendiente_pago' AND expira_en > NOW())
        OR estado = 'pago_en_revision'
      )
      AND daterange(fecha_in, fecha_out, '[)')
          && daterange(p_fecha_in, p_fecha_out, '[)')
    FOR UPDATE
  ) THEN
    v_conflictos := v_conflictos || jsonb_build_array(
      jsonb_build_object('fuente', 'pre_reservas')
    );
    v_tiene_conflicto := TRUE;
  END IF;

  -- Conflicto con bloqueos activos (específicos o totales)
  IF EXISTS (
    SELECT 1 FROM bloqueos
    WHERE activo = TRUE
      AND (id_cabana = p_id_cabana OR id_cabana IS NULL)
      AND daterange(fecha_desde, fecha_hasta, '[)')
          && daterange(p_fecha_in, p_fecha_out, '[)')
    FOR UPDATE
  ) THEN
    v_conflictos := v_conflictos || jsonb_build_array(
      jsonb_build_object('fuente', 'bloqueos')
    );
    v_tiene_conflicto := TRUE;
  END IF;

  IF v_tiene_conflicto THEN
    RETURN jsonb_build_object(
      'ok',         true,
      'disponible', false,
      'conflictos', v_conflictos
    );
  ELSE
    RETURN jsonb_build_object(
      'ok',         true,
      'disponible', true
    );
  END IF;
END;
$$;
```

**Verificación post-ejecución:**

```sql
SELECT proname FROM pg_proc WHERE proname = 'validar_disponibilidad';
```

**Rollback:**

```sql
DROP FUNCTION IF EXISTS validar_disponibilidad(BIGINT, DATE, DATE, BIGINT);
```

---

## BLOQUE 12 — Función `obtener_disponibilidad_rango`

**Descripción:** Devuelve disponibilidad calculada al vuelo para un rango de fechas. **Devuelve hora base, no escalonada** — el escalonamiento se aplica en n8n (ver Sección 17).

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
    CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '16:00' ELSE TIME '10:00' END AS hora_checkout_base,  -- v1.7.1 (D47)
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

**Verificación post-ejecución:**

```sql
SELECT proname FROM pg_proc WHERE proname = 'obtener_disponibilidad_rango';
```

**Test funcional (después de seed):**

```sql
SELECT * FROM obtener_disponibilidad_rango('2026-07-01', '2026-07-08');
-- Esperado: 5 cabañas × 7 fechas = 35 filas
```

**Rollback:**

```sql
DROP FUNCTION IF EXISTS obtener_disponibilidad_rango(DATE, DATE, BIGINT);
```

---

## BLOQUE 13 — Función `crear_prereserva` (puerta única)

**Descripción:** Función transaccional que crea una pre-reserva desde cualquier canal. Resuelve huésped, toma advisory lock por cabaña, valida disponibilidad, inserta. Soporta idempotency_key.

**Cambios en v1.3:**
- **Ajuste crítico 1:** double-check de idempotencia DESPUÉS del advisory lock y ANTES de `validar_disponibilidad()`. Cierra el agujero donde dos requests con la misma `idempotency_key` podían terminar con uno recibiendo `no_disponible` falso.
- **Ajuste crítico 2 (Opción A):** validación explícita de `huesped.nombre` (con TRIM) y `huesped.telefono OR huesped.email` antes de llamar a `upsert_huesped`. Errores nuevos: `huesped_nombre_requerido`, `huesped_contacto_requerido`. `upsert_huesped` mantiene su flexibilidad para otros callers (bot, consultas preliminares).
- **Observación D:** estructura de retorno unificada con campo `recovery_path` (`pre_lock` / `post_lock` / `unique_violation` / `null`). Reemplaza los flags `recovered_after_lock` y `recovered`.

**Cambios en v1.2 (mantenidos):**
- **D37:** lee horarios y expiración desde `configuracion_general` vía 1 SELECT agrupado. Fallback con COALESCE si falta clave. Log warning compacto (1 fila con lista de faltantes) si hay claves ausentes.
- **D35:** en `unique_violation` por `idempotency_key`, busca la pre-reserva activa y la devuelve como `idempotent_match=true` en vez de error.
- **Obs C:** test funcional usa teléfono distinto al del Bloque 10 para poder correrse en secuencia.

**Nota sobre config inválida (Ajuste menor 3, v1.3):**
> `COALESCE` cubre el caso de claves AUSENTES en `configuracion_general`. No cubre el caso de claves PRESENTES con valor inválido o no casteable (ej. `hora_checkin_default = 'no_es_una_hora'`). En ese caso el cast a `TIME` arrojará error técnico. Esto es aceptable para v1.3 porque la edición de `configuracion_general` se hace con cuidado o mediante UI validada futura. Si en el futuro se expone la edición de config a usuarios no técnicos, agregar safe-cast con `EXCEPTION WHEN invalid_text_representation`.

```sql
CREATE OR REPLACE FUNCTION crear_prereserva(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_huesped_payload      JSONB;
  v_id_consulta          BIGINT;
  v_id_cabana            BIGINT;
  v_fecha_in             DATE;
  v_fecha_out            DATE;
  v_personas             INTEGER;
  v_monto_total          NUMERIC(12,2);
  v_monto_sena           NUMERIC(12,2);
  v_canal_origen         TEXT;
  v_canal_pago_esperado  TEXT;
  v_source_event         TEXT;
  v_idempotency_key      TEXT;
  v_notas                TEXT;
  v_mascotas             BOOLEAN;
  v_detalle_mascotas     TEXT;
  v_ninos                TEXT;
  v_notas_reserva        TEXT;
  v_hora_checkin_sol     TIME;
  v_hora_checkout_sol    TIME;
  v_hora_checkin_final   TIME;
  v_hora_checkout_final  TIME;
  v_hora_checkin_min     TIME;
  v_hora_checkin_max     TIME;
  v_hora_checkout_min    TIME;
  v_hora_checkout_max    TIME;
  v_expiracion_minutos   INTEGER;
  v_expira_en            TIMESTAMPTZ;
  v_estado_inicial       estado_prereserva_enum;
  v_id_huesped           BIGINT;
  v_id_pre_reserva       BIGINT;
  v_config               JSONB;
  v_claves_faltantes     TEXT[];
  v_cabana               cabanas%ROWTYPE;
  v_disponibilidad       JSONB;
  v_existente            pre_reservas%ROWTYPE;
  v_upsert_result        JSONB;
BEGIN
  -- ─── 1. Extraer payload y validar ──────────────────────
  -- (v1.7.2) Extract defensivo unificado: todos los campos derivados de
  -- payload->>'...' pasan por NULLIF(TRIM(...),'') antes del cast. Excepción:
  -- v_huesped_payload usa payload->'huesped' (operador JSONB, no texto), no
  -- aplica patrón. La normalización interna del huésped vive en upsert_huesped().
  v_huesped_payload     := payload->'huesped';
  v_id_consulta         := NULLIF(TRIM(payload->>'id_consulta'), '')::BIGINT;
  v_id_cabana           := NULLIF(TRIM(payload->>'id_cabana'), '')::BIGINT;
  v_fecha_in            := NULLIF(TRIM(payload->>'fecha_in'), '')::DATE;
  v_fecha_out           := NULLIF(TRIM(payload->>'fecha_out'), '')::DATE;
  v_personas            := NULLIF(TRIM(payload->>'personas'), '')::INTEGER;
  v_monto_total         := NULLIF(TRIM(payload->>'monto_total'), '')::NUMERIC(12,2);
  v_monto_sena          := NULLIF(TRIM(payload->>'monto_sena'), '')::NUMERIC(12,2);
  v_canal_origen        := NULLIF(TRIM(payload->>'canal_origen'), '');
  v_canal_pago_esperado := NULLIF(TRIM(payload->>'canal_pago_esperado'), '');
  v_source_event        := NULLIF(TRIM(payload->>'source_event'), '');
  v_idempotency_key     := NULLIF(TRIM(payload->>'idempotency_key'), '');
  v_notas               := NULLIF(TRIM(payload->>'notas'), '');
  v_mascotas            := COALESCE(NULLIF(TRIM(payload->>'mascotas'), '')::BOOLEAN, FALSE);
  v_detalle_mascotas    := NULLIF(TRIM(payload->>'detalle_mascotas'), '');
  v_ninos               := NULLIF(TRIM(payload->>'ninos'), '');
  v_notas_reserva       := NULLIF(TRIM(payload->>'notas_reserva'), '');
  v_hora_checkin_sol    := NULLIF(TRIM(payload->>'hora_checkin_solicitada'), '')::TIME;
  v_hora_checkout_sol   := NULLIF(TRIM(payload->>'hora_checkout_solicitada'), '')::TIME;

  IF v_id_cabana IS NULL OR v_fecha_in IS NULL OR v_fecha_out IS NULL
     OR v_personas IS NULL OR v_canal_origen IS NULL OR v_source_event IS NULL
     OR v_canal_pago_esperado IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  IF v_monto_total IS NULL OR v_monto_sena IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'precio_requerido',
                              'motivo', 'monto_total y monto_sena son obligatorios');
  END IF;

  IF v_fecha_out <= v_fecha_in THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas');
  END IF;

  IF v_huesped_payload IS NULL OR NULLIF(TRIM(v_huesped_payload->>'nombre'), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_nombre_requerido',
                              'motivo', 'El payload del huésped debe traer un nombre no vacío.');
  END IF;

  IF NULLIF(v_huesped_payload->>'telefono', '') IS NULL
     AND NULLIF(v_huesped_payload->>'email', '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_contacto_requerido',
                              'motivo', 'El payload del huésped debe traer al menos telefono o email.');
  END IF;

  -- ─── 1.bis Setear contexto para triggers de log ──
  PERFORM set_config('app.modificado_por', 'crear_prereserva', true);
  PERFORM set_config('app.source_event',   v_source_event,    true);

  -- ─── 2. Leer configuración relevante ───────────────────
  SELECT jsonb_object_agg(clave, valor)
  INTO v_config
  FROM configuracion_general
  WHERE clave IN (
    'hora_checkin_default', 'hora_checkin_domingo',
    'hora_checkin_max_cliente', 'hora_checkout_min_cliente',
    'hora_checkout_default', 'hora_checkout_domingo',
    'prereserva_expiracion_minutos'
  );

  v_expiracion_minutos := COALESCE((v_config->>'prereserva_expiracion_minutos')::INTEGER, 60);

  v_claves_faltantes := ARRAY[]::TEXT[];
  IF v_config->>'hora_checkin_default'         IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_default'); END IF;
  IF v_config->>'hora_checkin_domingo'         IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_domingo'); END IF;
  IF v_config->>'hora_checkin_max_cliente'     IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_max_cliente'); END IF;
  IF v_config->>'hora_checkout_min_cliente'    IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_min_cliente'); END IF;
  IF v_config->>'hora_checkout_default'        IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_default'); END IF;
  IF v_config->>'hora_checkout_domingo'        IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_domingo'); END IF;
  IF v_config->>'prereserva_expiracion_minutos' IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'prereserva_expiracion_minutos'); END IF;

  -- ─── 3. Pre-check idempotencia ──
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existente
    FROM pre_reservas
    WHERE idempotency_key = v_idempotency_key
      AND estado IN ('pendiente_pago', 'pago_en_revision')
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'ok',               true,
        'idempotent_match', true,
        'id_pre_reserva',   v_existente.id_pre_reserva,
        'id_huesped',       v_existente.id_huesped,
        'estado',           v_existente.estado::TEXT,
        'expira_en',        v_existente.expira_en,
        'recovery_path',    'pre_lock'
      );
    END IF;
  END IF;

  -- ─── 4. Resolver huésped ──────
  v_upsert_result := upsert_huesped(v_huesped_payload);
  IF NOT (v_upsert_result->>'ok')::BOOLEAN THEN
    RETURN v_upsert_result;
  END IF;
  v_id_huesped := (v_upsert_result->>'id_huesped')::BIGINT;

  -- ─── 5. Locks ──
  PERFORM pg_advisory_xact_lock(10, 0);
  PERFORM pg_advisory_xact_lock(1, v_id_cabana::INTEGER);

  -- ─── 5.bis Double-check idempotencia ──
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existente
    FROM pre_reservas
    WHERE idempotency_key = v_idempotency_key
      AND estado IN ('pendiente_pago', 'pago_en_revision')
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'ok',               true,
        'idempotent_match', true,
        'id_pre_reserva',   v_existente.id_pre_reserva,
        'id_huesped',       v_existente.id_huesped,
        'estado',           v_existente.estado::TEXT,
        'expira_en',        v_existente.expira_en,
        'recovery_path',    'post_lock'
      );
    END IF;
  END IF;

  -- ─── 6. Validar cabaña ──
  SELECT * INTO v_cabana FROM cabanas WHERE id_cabana = v_id_cabana;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_existe');
  END IF;

  IF NOT v_cabana.activa THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_inactiva');
  END IF;

  IF v_personas > v_cabana.capacidad_max THEN
    RETURN jsonb_build_object('ok', false, 'error', 'excede_capacidad',
                              'capacidad_max', v_cabana.capacidad_max);
  END IF;

  -- ─── 7. Validar disponibilidad ──
  v_disponibilidad := validar_disponibilidad(v_id_cabana, v_fecha_in, v_fecha_out, NULL);

  IF NOT (v_disponibilidad->>'ok')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', v_disponibilidad->>'error');
  END IF;

  IF NOT (v_disponibilidad->>'disponible')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_disponible',
                              'conflictos', v_disponibilidad->'conflictos');
  END IF;

  -- ─── 8. Calcular horarios finales (v1.7) ──
  v_hora_checkin_min := CASE
    WHEN EXTRACT(DOW FROM v_fecha_in) = 0
      THEN COALESCE((v_config->>'hora_checkin_domingo')::TIME, TIME '18:00')
    ELSE
      COALESCE((v_config->>'hora_checkin_default')::TIME, TIME '13:00')
  END;
  v_hora_checkin_max := COALESCE((v_config->>'hora_checkin_max_cliente')::TIME, TIME '22:00');

  v_hora_checkout_min := COALESCE((v_config->>'hora_checkout_min_cliente')::TIME, TIME '07:00');

  v_hora_checkout_max := CASE
    WHEN EXTRACT(DOW FROM v_fecha_out) = 0
      THEN COALESCE((v_config->>'hora_checkout_domingo')::TIME, TIME '16:00')
    ELSE
      COALESCE((v_config->>'hora_checkout_default')::TIME, TIME '10:00')
  END;

  IF v_hora_checkin_sol IS NULL THEN
    v_hora_checkin_final := v_hora_checkin_min;
  ELSE
    IF v_hora_checkin_sol < v_hora_checkin_min OR v_hora_checkin_sol > v_hora_checkin_max THEN
      RETURN jsonb_build_object(
        'ok', false, 'error', 'hora_fuera_de_rango',
        'campo', 'hora_checkin',
        'minimo', v_hora_checkin_min, 'maximo', v_hora_checkin_max
      );
    END IF;
    v_hora_checkin_final := v_hora_checkin_sol;
  END IF;

  IF v_hora_checkout_sol IS NULL THEN
    v_hora_checkout_final := v_hora_checkout_max;
  ELSE
    IF v_hora_checkout_sol < v_hora_checkout_min OR v_hora_checkout_sol > v_hora_checkout_max THEN
      RETURN jsonb_build_object(
        'ok', false, 'error', 'hora_fuera_de_rango',
        'campo', 'hora_checkout',
        'minimo', v_hora_checkout_min, 'maximo', v_hora_checkout_max
      );
    END IF;
    v_hora_checkout_final := v_hora_checkout_sol;
  END IF;

  v_expira_en := NOW() + (v_expiracion_minutos || ' minutes')::INTERVAL;
  v_estado_inicial := 'pendiente_pago';

  -- ─── 9. INSERT con manejo defensivo ──
  BEGIN
    INSERT INTO pre_reservas (
      id_consulta, id_cabana, id_huesped,
      fecha_in, fecha_out, hora_checkin, hora_checkout,
      personas, monto_total, monto_sena, estado, expira_en,
      canal_pago_esperado, canal_origen, intentos_pago,
      notas, source_event,
      mascotas, detalle_mascotas, ninos, notas_reserva,
      idempotency_key
    ) VALUES (
      v_id_consulta, v_id_cabana, v_id_huesped,
      v_fecha_in, v_fecha_out, v_hora_checkin_final, v_hora_checkout_final,
      v_personas, v_monto_total, v_monto_sena, v_estado_inicial, v_expira_en,
      v_canal_pago_esperado, v_canal_origen, 0,
      v_notas, v_source_event,
      v_mascotas, v_detalle_mascotas, v_ninos, v_notas_reserva,
      v_idempotency_key
    )
    RETURNING id_pre_reserva INTO v_id_pre_reserva;

  EXCEPTION
    WHEN unique_violation THEN
      IF v_idempotency_key IS NOT NULL THEN
        SELECT * INTO v_existente
        FROM pre_reservas
        WHERE idempotency_key = v_idempotency_key
          AND estado IN ('pendiente_pago', 'pago_en_revision')
        LIMIT 1;

        IF FOUND THEN
          RETURN jsonb_build_object(
            'ok',               true,
            'idempotent_match', true,
            'id_pre_reserva',   v_existente.id_pre_reserva,
            'id_huesped',       v_existente.id_huesped,
            'estado',           v_existente.estado::TEXT,
            'expira_en',        v_existente.expira_en,
            'recovery_path',    'unique_violation'
          );
        END IF;
      END IF;

      RETURN jsonb_build_object('ok', false, 'error', 'unique_violation_inesperado');
  END;

  -- ─── 10. Log de creación ──
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'pre_reservas',
    v_id_pre_reserva::TEXT,
    'crear_prereserva',
    v_source_event,
    'info',
    jsonb_build_object(
      'evento',       'prereserva_creada',
      'id_cabana',    v_id_cabana,
      'id_huesped',   v_id_huesped,
      'fecha_in',     v_fecha_in,
      'fecha_out',    v_fecha_out,
      'monto_total',  v_monto_total,
      'monto_sena',   v_monto_sena,
      'canal_origen', v_canal_origen
    )
  );

  -- ─── 11. Warning de config faltante ──
  IF cardinality(v_claves_faltantes) > 0 THEN
    INSERT INTO log_cambios (
      tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
    ) VALUES (
      'configuracion_general',
      'sistema',
      'crear_prereserva',
      v_source_event,
      'warning',
      jsonb_build_object(
        'evento',           'claves_config_faltantes',
        'claves_faltantes', v_claves_faltantes,
        'motivo',           'crear_prereserva usó valores default para estas claves'
      )
    );
  END IF;

  -- ─── 12. Retorno exitoso ──
  RETURN jsonb_build_object(
    'ok',               true,
    'idempotent_match', false,
    'id_pre_reserva',   v_id_pre_reserva,
    'id_huesped',       v_id_huesped,
    'estado',           v_estado_inicial::TEXT,
    'expira_en',        v_expira_en,
    'hora_checkin',     v_hora_checkin_final,
    'hora_checkout',    v_hora_checkout_final,
    'recovery_path',    NULL
  );
END;
$$;
```

**Verificación post-ejecución:**

```sql
SELECT proname FROM pg_proc WHERE proname = 'crear_prereserva';
```

**Test funcional (después de seed) — Obs C: usa teléfono distinto al Bloque 10:**

```sql
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object(
    'nombre',   'Cliente Test Bloque13',
    'telefono', '+5491113131313'
  ),
  'id_cabana',           1,
  'fecha_in',            '2026-08-01',
  'fecha_out',           '2026-08-03',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_manual'
));
-- Esperado: { "ok": true, "id_pre_reserva": N, ... }
```

**Rollback:**

```sql
DROP FUNCTION IF EXISTS crear_prereserva(JSONB);
```

---

## BLOQUE 14 — Función `confirmar_reserva`

**Descripción:** Convierte una pre-reserva en reserva confirmada. Soporta camino estricto (solo con pago `confirmado`) y camino combinado (con `permitir_pago_en_revision=true`).

**Cambio en v1.5 (corrección crítica de orden de locks):**
- El `pg_advisory_xact_lock(10, 0)` ahora se toma **ANTES** del `SELECT ... FOR UPDATE` sobre `pre_reservas`. En v1.4 estaba al revés y podía generar deadlocks contra `cancelar_prereserva`.
- El `pg_advisory_xact_lock(1, v_pre.id_cabana)` sigue siendo después del SELECT (necesita conocer `v_pre.id_cabana`).
- El contrato del payload NO cambia.

**Cambios v1.4 (mantenidos):** lock global y por cabaña obligatorios para serializar contra `crear_bloqueo` y otras operaciones.

**Cambio en v1.2 (D38):** setea `app.modificado_por` y `app.source_event` vía `set_config(..., true)` al inicio, para que los triggers de log de cambio de estado tengan contexto preciso en lugar de `trigger_auto` / `estado_change`.

```sql
CREATE OR REPLACE FUNCTION confirmar_reserva(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_pre_reserva              BIGINT;
  v_permitir_pago_en_revision   BOOLEAN;
  v_validado_por                TEXT;
  v_encargado_semana            TEXT;
  v_created_by                  TEXT;
  v_source_event                TEXT;
  v_pre                         pre_reservas%ROWTYPE;
  v_pago                        pagos%ROWTYPE;
  v_id_pago_a_confirmar         BIGINT;
  v_disponibilidad              JSONB;
  v_id_reserva                  BIGINT;
  v_huesped                     huespedes%ROWTYPE;
BEGIN
  -- ─── 1. Extraer payload (v1.7.2 — extract defensivo unificado) ──
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en BIGINT y BOOLEAN
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  v_id_pre_reserva            := NULLIF(TRIM(payload->>'id_pre_reserva'), '')::BIGINT;
  v_permitir_pago_en_revision := COALESCE(NULLIF(TRIM(payload->>'permitir_pago_en_revision'), '')::BOOLEAN, FALSE);
  v_validado_por              := NULLIF(TRIM(payload->>'validado_por'), '');
  v_encargado_semana          := NULLIF(TRIM(payload->>'encargado_semana'), '');
  v_created_by                := NULLIF(TRIM(payload->>'created_by'), '');
  v_source_event              := NULLIF(TRIM(payload->>'source_event'), '');

  IF v_id_pre_reserva IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  -- ─── 1.bis Setear contexto para triggers de log (D38, v1.2) ──
  PERFORM set_config('app.modificado_por', 'confirmar_reserva', true);
  PERFORM set_config('app.source_event',   v_source_event,      true);

  -- ─── 1.ter Lock GLOBAL de disponibilidad (v1.5) ──
  -- INVARIANTE DE LOCKS: tomar SIEMPRE primero el lock global antes de cualquier otro.
  PERFORM pg_advisory_xact_lock(10, 0);

  -- ─── 2. Bloquear y leer pre-reserva (row lock, después del global) ──
  SELECT * INTO v_pre FROM pre_reservas
  WHERE id_pre_reserva = v_id_pre_reserva
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'prereserva_no_existe');
  END IF;

  IF v_pre.estado NOT IN ('pendiente_pago', 'pago_en_revision') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estado_invalido',
                              'estado_actual', v_pre.estado::TEXT);
  END IF;

  -- ─── 3. Lock por cabaña (con cast a INTEGER — corrección v1.6) ──
  -- NOTA TÉCNICA (v1.6): cast explícito a INTEGER. PostgreSQL no provee
  -- pg_advisory_xact_lock(integer, bigint). Ver Sección 15 del documento.
  PERFORM pg_advisory_xact_lock(1, v_pre.id_cabana::INTEGER);

  -- ─── 4. Verificar pago asociado ────────────────────────
  -- Camino estricto: requiere al menos un pago 'confirmado'
  SELECT * INTO v_pago FROM pagos
  WHERE id_prereserva = v_id_pre_reserva
    AND estado = 'confirmado'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    -- Sin pago confirmado, ¿podemos usar camino combinado?
    IF v_permitir_pago_en_revision AND v_validado_por IS NOT NULL THEN
      SELECT * INTO v_pago FROM pagos
      WHERE id_prereserva = v_id_pre_reserva
        AND estado = 'en_revision'
      ORDER BY created_at DESC
      LIMIT 1
      FOR UPDATE;

      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'sin_pago_asociado');
      END IF;

      v_id_pago_a_confirmar := v_pago.id_pago;
    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'sin_pago_confirmado',
                                'motivo', 'No hay pago confirmado y no se permitió usar pago en revisión');
    END IF;
  END IF;

  -- ─── 5. Revalidar disponibilidad excluyendo esta pre-reserva ──
  v_disponibilidad := validar_disponibilidad(
    v_pre.id_cabana, v_pre.fecha_in, v_pre.fecha_out, v_id_pre_reserva
  );

  IF NOT (v_disponibilidad->>'ok')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', v_disponibilidad->>'error');
  END IF;

  IF NOT (v_disponibilidad->>'disponible')::BOOLEAN THEN
    -- Conflicto detectado al confirmar — alguien metió bloqueo o reserva
    UPDATE pre_reservas SET estado = 'conflicto_pendiente', updated_at = NOW()
    WHERE id_pre_reserva = v_id_pre_reserva;

    RETURN jsonb_build_object('ok', false, 'error', 'conflicto_al_confirmar',
                              'conflictos', v_disponibilidad->'conflictos');
  END IF;

  -- ─── 6. INSERT en reservas (con captura defensiva de EXCLUDE) ──
  BEGIN
    INSERT INTO reservas (
      id_pre_reserva, id_cabana, id_huesped,
      fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
      personas, estado, canal_origen,
      monto_total, monto_sena, monto_saldo,
      encargado_semana, created_by, source_event,
      mascotas, detalle_mascotas, ninos, notas_reserva
    ) VALUES (
      v_id_pre_reserva, v_pre.id_cabana, v_pre.id_huesped,
      v_pre.fecha_in, v_pre.fecha_out, v_pre.hora_checkin, v_pre.hora_checkout,
      v_pre.personas, 'confirmada', v_pre.canal_origen,
      v_pre.monto_total, v_pre.monto_sena, (v_pre.monto_total - v_pre.monto_sena),
      v_encargado_semana, v_created_by, v_source_event,
      v_pre.mascotas, v_pre.detalle_mascotas, v_pre.ninos, v_pre.notas_reserva
    )
    RETURNING id_reserva INTO v_id_reserva;

  EXCEPTION
    WHEN exclusion_violation THEN
      -- Defensivo: no debería pasar por la revalidación + lock, pero por las dudas
      RETURN jsonb_build_object('ok', false, 'error', 'no_disponible',
                                'motivo', 'EXCLUDE constraint detectó conflicto');
  END;

  -- ─── 7. Marcar pre-reserva como convertida ────────────
  UPDATE pre_reservas
  SET estado = 'convertida', updated_at = NOW()
  WHERE id_pre_reserva = v_id_pre_reserva;

  -- ─── 8. Asociar pago con la nueva reserva ────────────
  UPDATE pagos
  SET id_reserva = v_id_reserva,
      updated_at = NOW()
  WHERE id_prereserva = v_id_pre_reserva;

  -- ─── 9. Si camino combinado: confirmar el pago en_revision ───
  IF v_id_pago_a_confirmar IS NOT NULL THEN
    UPDATE pagos
    SET estado       = 'confirmado',
        validado_por = v_validado_por,
        validado_en  = NOW(),
        updated_at   = NOW()
    WHERE id_pago = v_id_pago_a_confirmar;
  END IF;

  -- ─── 10. Actualizar huésped: total_reservas y primera_reserva_fecha ──
  UPDATE huespedes
  SET total_reservas        = total_reservas + 1,
      primera_reserva_fecha = COALESCE(primera_reserva_fecha, v_pre.fecha_in),
      updated_at            = NOW()
  WHERE id_huesped = v_pre.id_huesped;

  -- ─── 11. Log de creación ────────────────────────────
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'reservas',
    v_id_reserva::TEXT,
    'confirmar_reserva',
    v_source_event,
    'info',
    jsonb_build_object(
      'evento',         'reserva_confirmada',
      'id_reserva',     v_id_reserva,
      'id_pre_reserva', v_id_pre_reserva,
      'id_huesped',     v_pre.id_huesped,
      'id_cabana',      v_pre.id_cabana,
      'camino',         CASE WHEN v_id_pago_a_confirmar IS NOT NULL THEN 'combinado' ELSE 'estricto' END
    )
  );

  RETURN jsonb_build_object(
    'ok',             true,
    'id_reserva',     v_id_reserva,
    'id_pre_reserva', v_id_pre_reserva,
    'id_huesped',     v_pre.id_huesped
  );
END;
$$;
```

**Verificación post-ejecución:**

```sql
SELECT proname FROM pg_proc WHERE proname = 'confirmar_reserva';
```

**Rollback:**

```sql
DROP FUNCTION IF EXISTS confirmar_reserva(JSONB);
```

---

## BLOQUE 15 — Función `cancelar_prereserva`

**Descripción:** Cancela una pre-reserva con motivo. No toca pagos asociados; los devuelve para revisión manual.

**Cambio en v1.4 (D46, Q1):** toma `pg_advisory_xact_lock(10, 0)` (lock global de disponibilidad) al inicio. Aunque cancelar una pre-reserva no genera double booking, sí cambia disponibilidad efectiva. El lock global evita falsos conflictos cuando un `crear_bloqueo` paralelo evalúa la pre-reserva durante su cancelación. No se toma lock por cabaña porque el UPDATE solo libera disponibilidad.

**Cambio en v1.2 (D38):** setea `app.modificado_por` y `app.source_event` para que los triggers de log de estado tengan contexto preciso.

```sql
CREATE OR REPLACE FUNCTION cancelar_prereserva(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_pre_reserva     BIGINT;
  v_motivo             TEXT;
  v_descripcion        TEXT;
  v_source_event       TEXT;
  v_pre                pre_reservas%ROWTYPE;
  v_estado_nuevo       estado_prereserva_enum;
  v_estado_anterior    estado_prereserva_enum;
  v_pagos_count        INTEGER;
  v_pagos_ids          BIGINT[];
BEGIN
  -- 1. Extraer payload (v1.7.2 — extract defensivo unificado)
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en BIGINT
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  v_id_pre_reserva := NULLIF(TRIM(payload->>'id_pre_reserva'), '')::BIGINT;
  v_motivo         := NULLIF(TRIM(payload->>'motivo'), '');
  v_descripcion    := NULLIF(TRIM(payload->>'descripcion'), '');
  v_source_event   := NULLIF(TRIM(payload->>'source_event'), '');

  IF v_id_pre_reserva IS NULL OR v_motivo IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  -- 1.bis Setear contexto para triggers de log (D38, v1.2)
  PERFORM set_config('app.modificado_por', 'cancelar_prereserva', true);
  PERFORM set_config('app.source_event',   v_source_event,        true);

  -- 1.ter Lock global de disponibilidad (D46, v1.4, Q1)
  -- Esta función NO toma lock por cabaña porque solo libera disponibilidad.
  PERFORM pg_advisory_xact_lock(10, 0);

  -- 2. Mapear motivo a estado
  CASE v_motivo
    WHEN 'cliente' THEN v_estado_nuevo := 'cancelada_por_cliente';
    WHEN 'bloqueo' THEN v_estado_nuevo := 'cancelada_por_bloqueo';
    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'motivo_invalido',
                                'motivos_validos', jsonb_build_array('cliente', 'bloqueo'));
  END CASE;

  -- 3. Bloquear pre-reserva
  SELECT * INTO v_pre FROM pre_reservas
  WHERE id_pre_reserva = v_id_pre_reserva
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'prereserva_no_existe');
  END IF;

  IF v_pre.estado NOT IN ('pendiente_pago', 'pago_en_revision') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estado_no_cancelable',
                              'estado_actual', v_pre.estado::TEXT);
  END IF;

  v_estado_anterior := v_pre.estado;

  -- 4. Cancelar
  UPDATE pre_reservas
  SET estado = v_estado_nuevo, updated_at = NOW()
  WHERE id_pre_reserva = v_id_pre_reserva;

  -- 5. Contar pagos asociados (NO tocarlos)
  SELECT COUNT(*), COALESCE(array_agg(id_pago), ARRAY[]::BIGINT[])
  INTO v_pagos_count, v_pagos_ids
  FROM pagos
  WHERE id_prereserva = v_id_pre_reserva;

  -- 6. Log
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'pre_reservas', v_id_pre_reserva::TEXT, 'cancelar_prereserva',
    v_source_event, 'info',
    jsonb_build_object(
      'evento',           'prereserva_cancelada',
      'id_pre_reserva',   v_id_pre_reserva,
      'estado_anterior',  v_estado_anterior::TEXT,
      'estado_nuevo',     v_estado_nuevo::TEXT,
      'motivo',           v_motivo,
      'descripcion',      v_descripcion,
      'pagos_asociados',  v_pagos_count
    )
  );

  RETURN jsonb_build_object(
    'ok',                    true,
    'id_pre_reserva',        v_id_pre_reserva,
    'estado_anterior',       v_estado_anterior::TEXT,
    'estado_nuevo',          v_estado_nuevo::TEXT,
    'pagos_asociados_count', v_pagos_count,
    'pagos_asociados_ids',   to_jsonb(v_pagos_ids)
  );
END;
$$;
```

**Verificación post-ejecución:**

```sql
SELECT proname FROM pg_proc WHERE proname = 'cancelar_prereserva';
```

**Rollback:**

```sql
DROP FUNCTION IF EXISTS cancelar_prereserva(JSONB);
```

---

## BLOQUE 16 — Función `crear_bloqueo`

**Descripción:** Crea un bloqueo de cabaña específica o total.

**Cambios en v1.4 (D46, Q5):**
- Toma `pg_advisory_xact_lock(10, 0)` (lock global de disponibilidad) al inicio, antes de cualquier validación.
- Si es bloqueo de cabaña específica, después toma `pg_advisory_xact_lock(1, v_id_cabana)`.
- **`LOCK TABLE` eliminado.** Ya no se usa para bloqueo total. La serialización contra otras operaciones críticas pasa por el lock global. Las validaciones manuales se mantienen.

**Cambios en v1.2 (mantenidos):**
- **D33:** valida conflictos con pre-reservas vigentes (`pendiente_pago` con `expira_en > NOW()` o `pago_en_revision`) antes de crear. Devuelve `error='conflicto_con_prereserva'` con lista de IDs.
- **D34:** valida manualmente las 4 combinaciones de bloqueos solapados, incluyendo las 3 que el EXCLUDE no cubre (total vs total, total vs específico, específico vs total). EXCLUDE se mantiene como defensa estructural para específico vs específico.

```sql
CREATE OR REPLACE FUNCTION crear_bloqueo(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_cabana            BIGINT;
  v_fecha_desde          DATE;
  v_fecha_hasta          DATE;
  v_motivo               TEXT;
  v_descripcion          TEXT;
  v_creado_por           TEXT;
  v_source_event         TEXT;
  v_id_bloqueo           BIGINT;
  v_reservas_ids         BIGINT[];
  v_prereservas_ids      BIGINT[];
  v_bloqueos_ids         BIGINT[];
BEGIN
  -- 1. Extraer payload (v1.7.2 — extract defensivo unificado)
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en BIGINT y DATE
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  --
  -- Caso especial v_id_cabana: null significa "bloqueo total" (válido).
  -- Tanto null como "" como "   " se interpretan como bloqueo total.
  v_id_cabana    := NULLIF(TRIM(payload->>'id_cabana'), '')::BIGINT;
  v_fecha_desde  := NULLIF(TRIM(payload->>'fecha_desde'), '')::DATE;
  v_fecha_hasta  := NULLIF(TRIM(payload->>'fecha_hasta'), '')::DATE;
  v_motivo       := NULLIF(TRIM(payload->>'motivo'), '');
  v_descripcion  := NULLIF(TRIM(payload->>'descripcion'), '');
  v_creado_por   := NULLIF(TRIM(payload->>'creado_por'), '');
  v_source_event := NULLIF(TRIM(payload->>'source_event'), '');

  IF v_fecha_desde IS NULL OR v_fecha_hasta IS NULL
     OR v_motivo IS NULL OR v_creado_por IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  IF v_fecha_hasta <= v_fecha_desde THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas');
  END IF;

  IF v_motivo NOT IN ('mantenimiento', 'uso_propio', 'tormenta', 'overbooking', 'otro') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'motivo_invalido');
  END IF;

  -- 2. Locks (INVARIANTE DE LOCKS v1.5: SIEMPRE primero el global)
  PERFORM pg_advisory_xact_lock(10, 0);

  IF v_id_cabana IS NOT NULL THEN
    -- Bloqueo específico: tomar también lock por cabaña con cast a INTEGER (v1.6)
    PERFORM pg_advisory_xact_lock(1, v_id_cabana::INTEGER);

    -- Verificar cabaña existe
    IF NOT EXISTS (SELECT 1 FROM cabanas WHERE id_cabana = v_id_cabana) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_existe');
    END IF;

    -- 3.A.1 Verificar conflicto con reservas confirmadas/activas en esta cabaña
    SELECT COALESCE(array_agg(id_reserva), ARRAY[]::BIGINT[])
    INTO v_reservas_ids
    FROM reservas
    WHERE id_cabana = v_id_cabana
      AND estado IN ('confirmada', 'activa')
      AND daterange(fecha_checkin, fecha_checkout, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_reservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'conflicto_con_reserva',
        'reservas_en_conflicto', to_jsonb(v_reservas_ids)
      );
    END IF;

    -- 3.A.2 Verificar conflicto con pre-reservas vigentes en esta cabaña
    SELECT COALESCE(array_agg(id_pre_reserva), ARRAY[]::BIGINT[])
    INTO v_prereservas_ids
    FROM pre_reservas
    WHERE id_cabana = v_id_cabana
      AND (
        (estado = 'pendiente_pago' AND expira_en > NOW())
        OR estado = 'pago_en_revision'
      )
      AND daterange(fecha_in, fecha_out, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_prereservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                       false,
        'error',                    'conflicto_con_prereserva',
        'prereservas_en_conflicto', to_jsonb(v_prereservas_ids),
        'motivo',                   'Hay pre-reservas vigentes en el rango. Cancelarlas antes de bloquear.'
      );
    END IF;

    -- 3.A.3 Verificar bloqueos solapados (específico vs específico o específico vs total)
    SELECT COALESCE(array_agg(id_bloqueo), ARRAY[]::BIGINT[])
    INTO v_bloqueos_ids
    FROM bloqueos
    WHERE activo = TRUE
      AND (id_cabana = v_id_cabana OR id_cabana IS NULL)
      AND daterange(fecha_desde, fecha_hasta, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_bloqueos_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'bloqueo_solapado',
        'bloqueos_en_conflicto', to_jsonb(v_bloqueos_ids),
        'motivo',                'Ya hay un bloqueo activo (específico o total) en el rango'
      );
    END IF;

  ELSE
    -- Bloqueo total (id_cabana IS NULL)
    -- 3.B.1 Verificar conflicto con reservas en cualquier cabaña
    SELECT COALESCE(array_agg(id_reserva), ARRAY[]::BIGINT[])
    INTO v_reservas_ids
    FROM reservas
    WHERE estado IN ('confirmada', 'activa')
      AND daterange(fecha_checkin, fecha_checkout, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_reservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'conflicto_con_reserva',
        'motivo',                'Hay reservas confirmadas en el rango. Resolver antes de bloquear el complejo.',
        'reservas_en_conflicto', to_jsonb(v_reservas_ids)
      );
    END IF;

    -- 3.B.2 Verificar conflicto con pre-reservas vigentes en cualquier cabaña
    SELECT COALESCE(array_agg(id_pre_reserva), ARRAY[]::BIGINT[])
    INTO v_prereservas_ids
    FROM pre_reservas
    WHERE (
        (estado = 'pendiente_pago' AND expira_en > NOW())
        OR estado = 'pago_en_revision'
      )
      AND daterange(fecha_in, fecha_out, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_prereservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                       false,
        'error',                    'conflicto_con_prereserva',
        'prereservas_en_conflicto', to_jsonb(v_prereservas_ids),
        'motivo',                   'Hay pre-reservas vigentes en el rango. Cancelarlas antes de bloquear el complejo.'
      );
    END IF;

    -- 3.B.3 Verificar bloqueos solapados (total vs total o total vs específico existente)
    SELECT COALESCE(array_agg(id_bloqueo), ARRAY[]::BIGINT[])
    INTO v_bloqueos_ids
    FROM bloqueos
    WHERE activo = TRUE
      AND daterange(fecha_desde, fecha_hasta, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_bloqueos_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'bloqueo_solapado',
        'bloqueos_en_conflicto', to_jsonb(v_bloqueos_ids),
        'motivo',                'Ya hay bloqueos activos en el rango (totales o específicos)'
      );
    END IF;
  END IF;

  -- 4. INSERT con captura defensiva de exclusion_violation
  BEGIN
    INSERT INTO bloqueos (
      id_cabana, fecha_desde, fecha_hasta, motivo, descripcion,
      creado_por, activo, source_event
    ) VALUES (
      v_id_cabana, v_fecha_desde, v_fecha_hasta, v_motivo, v_descripcion,
      v_creado_por, TRUE, v_source_event
    )
    RETURNING id_bloqueo INTO v_id_bloqueo;

  EXCEPTION
    WHEN exclusion_violation THEN
      RETURN jsonb_build_object('ok', false, 'error', 'bloqueo_solapado',
                                'motivo', 'EXCLUDE detectó conflicto residual');
  END;

  -- 5. Log
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'bloqueos', v_id_bloqueo::TEXT, v_creado_por, v_source_event, 'info',
    jsonb_build_object(
      'evento',       'bloqueo_creado',
      'id_bloqueo',   v_id_bloqueo,
      'id_cabana',    v_id_cabana,
      'fecha_desde',  v_fecha_desde,
      'fecha_hasta',  v_fecha_hasta,
      'motivo',       v_motivo,
      'tipo_bloqueo', CASE WHEN v_id_cabana IS NULL THEN 'total' ELSE 'cabana_especifica' END
    )
  );

  RETURN jsonb_build_object(
    'ok',           true,
    'id_bloqueo',   v_id_bloqueo,
    'id_cabana',    v_id_cabana,
    'tipo_bloqueo', CASE WHEN v_id_cabana IS NULL THEN 'total' ELSE 'cabana_especifica' END
  );
END;
$$;
```

**Verificación post-ejecución:**

```sql
SELECT proname FROM pg_proc WHERE proname = 'crear_bloqueo';
```

**Rollback:**

```sql
DROP FUNCTION IF EXISTS crear_bloqueo(JSONB);
```

---

## BLOQUE 17 — Función `registrar_pago`

**Descripción:** Registra pagos asociados a pre-reservas o reservas. No exige `monto_recibido = monto_esperado`.

**Cambios en v1.3 (Ajuste P2 / menor 4):**
- Detecta si la pre-reserva referenciada está en estados terminales (`vencida`, `cancelada_por_cliente`, `cancelada_por_bloqueo`, `conflicto_pendiente`).
- Si está terminal: **fuerza** estado del pago a `en_revision` (ignora `estado_inicial='confirmado'` del payload), **no reactiva** la pre-reserva, **no modifica** el estado de la pre-reserva.
- Devuelve `warning:'prereserva_no_activa'` + `prereserva_estado:'...'` en el JSON.
- Registra log nivel `warning` en `log_cambios`.

**Criterio operativo documentado (no implementado):**
> Si una pre-reserva está `convertida`, el pago tardío debería asociarse preferentemente a `id_reserva` (no solo a `id_pre_reserva`). En v1.3 esto NO se enforza; queda como guía operativa para n8n: cuando detecte una pre-reserva ya convertida, debe usar el `id_reserva` resultante en el payload de `registrar_pago`. Una versión futura puede agregar resolución automática.

**Cambio en v1.2 (D38, mantenido):** setea `app.modificado_por` y `app.source_event` para que los triggers de log de estado tengan contexto preciso (especialmente útil cuando este registro promueve una pre-reserva de `pendiente_pago` a `pago_en_revision`).

```sql
CREATE OR REPLACE FUNCTION registrar_pago(payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_pre_reserva     BIGINT;
  v_id_reserva         BIGINT;
  v_tipo               TEXT;
  v_medio_pago         TEXT;
  v_monto_esperado     NUMERIC(12,2);
  v_monto_recibido     NUMERIC(12,2);
  v_moneda             TEXT;
  v_es_automatico      BOOLEAN;
  v_estado_inicial     TEXT;
  v_comprobante_url    TEXT;
  v_referencia_externa TEXT;
  v_tx_hash            TEXT;
  v_validado_por       TEXT;
  v_notas              TEXT;
  v_proveedor          TEXT;
  v_cuenta_destino     TEXT;
  v_source_event       TEXT;
  v_estado_final       estado_pago_enum;
  v_id_pago            BIGINT;
  v_validado_en        TIMESTAMPTZ;
  v_prereserva_estado  estado_prereserva_enum;
  v_prereserva_no_activa BOOLEAN := FALSE;
  v_warning            TEXT;
BEGIN
  -- 1. Extraer payload (v1.7.2 — extract defensivo unificado)
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en numéricos y booleanos
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  v_id_pre_reserva     := NULLIF(TRIM(payload->>'id_pre_reserva'), '')::BIGINT;
  v_id_reserva         := NULLIF(TRIM(payload->>'id_reserva'), '')::BIGINT;
  v_tipo               := NULLIF(TRIM(payload->>'tipo'), '');
  v_medio_pago         := NULLIF(TRIM(payload->>'medio_pago'), '');
  v_monto_esperado     := NULLIF(TRIM(payload->>'monto_esperado'), '')::NUMERIC(12,2);
  v_monto_recibido     := NULLIF(TRIM(payload->>'monto_recibido'), '')::NUMERIC(12,2);
  v_moneda             := COALESCE(NULLIF(TRIM(payload->>'moneda'), ''), 'ARS');
  v_es_automatico      := COALESCE(NULLIF(TRIM(payload->>'es_automatico'), '')::BOOLEAN, FALSE);
  v_estado_inicial     := NULLIF(TRIM(payload->>'estado_inicial'), '');
  v_comprobante_url    := NULLIF(TRIM(payload->>'comprobante_url'), '');
  v_referencia_externa := NULLIF(TRIM(payload->>'referencia_externa'), '');
  v_tx_hash            := NULLIF(TRIM(payload->>'tx_hash'), '');
  v_validado_por       := NULLIF(TRIM(payload->>'validado_por'), '');
  v_notas              := NULLIF(TRIM(payload->>'notas'), '');
  v_proveedor          := NULLIF(TRIM(payload->>'proveedor'), '');
  v_cuenta_destino     := NULLIF(TRIM(payload->>'cuenta_destino'), '');
  v_source_event       := NULLIF(TRIM(payload->>'source_event'), '');

  -- 1.bis Setear contexto para triggers de log (D38, v1.2)
  IF v_source_event IS NOT NULL THEN
    PERFORM set_config('app.modificado_por', 'registrar_pago', true);
    PERFORM set_config('app.source_event',   v_source_event,   true);
  END IF;

  -- 2. Validaciones
  IF v_id_pre_reserva IS NULL AND v_id_reserva IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'referencia_requerida',
                              'motivo', 'Debe venir id_pre_reserva o id_reserva');
  END IF;

  IF v_tipo IS NULL OR v_medio_pago IS NULL OR v_monto_esperado IS NULL
     OR v_monto_recibido IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  -- 3. Verificar pre-reserva o reserva existe + capturar estado de la pre-reserva (v1.3)
  IF v_id_pre_reserva IS NOT NULL THEN
    SELECT estado INTO v_prereserva_estado
    FROM pre_reservas
    WHERE id_pre_reserva = v_id_pre_reserva;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'prereserva_no_existe');
    END IF;

    -- v1.3 (P2): detectar pre-reserva en estado terminal
    IF v_prereserva_estado IN (
      'vencida',
      'cancelada_por_cliente',
      'cancelada_por_bloqueo',
      'conflicto_pendiente'
    ) THEN
      v_prereserva_no_activa := TRUE;
      v_warning              := 'prereserva_no_activa';
    END IF;
  END IF;

  IF v_id_reserva IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM reservas WHERE id_reserva = v_id_reserva) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'reserva_no_existe');
    END IF;
  END IF;

  -- 4. Determinar estado del pago
  IF v_prereserva_no_activa THEN
    v_estado_final := 'en_revision';
    v_validado_en  := NULL;
  ELSIF v_estado_inicial = 'confirmado' AND v_monto_recibido = v_monto_esperado THEN
    v_estado_final := 'confirmado';
    v_validado_en  := NOW();
    IF v_validado_por IS NULL THEN
      v_validado_por := 'sistema_auto';
    END IF;
  ELSE
    v_estado_final := 'en_revision';
    v_validado_en  := NULL;
  END IF;

  -- 5. INSERT
  INSERT INTO pagos (
    id_prereserva, id_reserva, tipo, medio_pago, proveedor, cuenta_destino,
    monto_esperado, monto_recibido, moneda, estado, es_automatico,
    comprobante_url, referencia_externa, tx_hash,
    validado_por, validado_en, notas, source_event
  ) VALUES (
    v_id_pre_reserva, v_id_reserva, v_tipo, v_medio_pago, v_proveedor, v_cuenta_destino,
    v_monto_esperado, v_monto_recibido, v_moneda, v_estado_final, v_es_automatico,
    v_comprobante_url, v_referencia_externa, v_tx_hash,
    v_validado_por, v_validado_en, v_notas, v_source_event
  )
  RETURNING id_pago INTO v_id_pago;

  -- 6. Promover pre-reserva de pendiente_pago → pago_en_revision SOLO si está activa
  IF v_id_pre_reserva IS NOT NULL AND NOT v_prereserva_no_activa THEN
    UPDATE pre_reservas
    SET estado = 'pago_en_revision', updated_at = NOW()
    WHERE id_pre_reserva = v_id_pre_reserva
      AND estado = 'pendiente_pago';
  END IF;

  -- 7. Log
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'pagos', v_id_pago::TEXT, COALESCE(v_validado_por, 'registrar_pago'),
    v_source_event,
    CASE WHEN v_prereserva_no_activa THEN 'warning'::nivel_log_enum ELSE 'info'::nivel_log_enum END,
    jsonb_build_object(
      'evento',             'pago_registrado',
      'id_pago',            v_id_pago,
      'id_pre_reserva',     v_id_pre_reserva,
      'id_reserva',         v_id_reserva,
      'tipo',               v_tipo,
      'medio_pago',         v_medio_pago,
      'monto_esperado',     v_monto_esperado,
      'monto_recibido',     v_monto_recibido,
      'estado',             v_estado_final::TEXT,
      'es_automatico',      v_es_automatico,
      'warning',            v_warning,
      'prereserva_estado',  CASE WHEN v_prereserva_no_activa
                                 THEN v_prereserva_estado::TEXT
                                 ELSE NULL END
    )
  );

  -- 8. Retorno
  IF v_prereserva_no_activa THEN
    RETURN jsonb_build_object(
      'ok',                 true,
      'id_pago',            v_id_pago,
      'estado',             v_estado_final::TEXT,
      'warning',            'prereserva_no_activa',
      'prereserva_estado',  v_prereserva_estado::TEXT
    );
  ELSE
    RETURN jsonb_build_object(
      'ok',      true,
      'id_pago', v_id_pago,
      'estado',  v_estado_final::TEXT
    );
  END IF;
END;
$$;
```

**Verificación post-ejecución:**

```sql
SELECT proname FROM pg_proc WHERE proname = 'registrar_pago';
```

**Rollback:**

```sql
DROP FUNCTION IF EXISTS registrar_pago(JSONB);
```

---

## BLOQUE 18 — Función `expirar_prereservas_vencidas`

**Descripción:** Marca como `vencida` todas las pre-reservas con `expira_en <= NOW()` y estado `pendiente_pago`. Ejecutada por pg_cron cada 5 minutos.

**Cambio en v1.2 (D38):** setea `app.modificado_por='expirar_prereservas_vencidas'` y `app.source_event='cron_expirar_prereservas'` UNA SOLA VEZ al inicio (no por iteración del loop), porque el valor es constante para toda la ejecución.

```sql
CREATE OR REPLACE FUNCTION expirar_prereservas_vencidas()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count       INTEGER;
  v_pre         RECORD;
BEGIN
  v_count := 0;

  -- Setear contexto una sola vez al inicio (D38, v1.2)
  -- El trigger trg_log_pre_reservas_estado leerá estas variables al hacer el UPDATE.
  PERFORM set_config('app.modificado_por', 'expirar_prereservas_vencidas', true);
  PERFORM set_config('app.source_event',   'cron_expirar_prereservas',    true);

  FOR v_pre IN
    SELECT id_pre_reserva, id_huesped, id_cabana, fecha_in, fecha_out
    FROM pre_reservas
    WHERE estado = 'pendiente_pago'
      AND expira_en <= NOW()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE pre_reservas
    SET estado = 'vencida', updated_at = NOW()
    WHERE id_pre_reserva = v_pre.id_pre_reserva;

    INSERT INTO log_cambios (
      tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
    ) VALUES (
      'pre_reservas', v_pre.id_pre_reserva::TEXT, 'pg_cron',
      'cron_expirar_prereservas', 'info',
      jsonb_build_object(
        'evento',         'prereserva_vencida',
        'id_pre_reserva', v_pre.id_pre_reserva,
        'id_huesped',     v_pre.id_huesped,
        'id_cabana',      v_pre.id_cabana
      )
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
```

**Verificación post-ejecución:**

```sql
SELECT proname FROM pg_proc WHERE proname = 'expirar_prereservas_vencidas';
```

**Test funcional:**

```sql
SELECT expirar_prereservas_vencidas();
-- Esperado: integer con cantidad de pre-reservas marcadas como vencidas
```

**Rollback:**

```sql
DROP FUNCTION IF EXISTS expirar_prereservas_vencidas();
```

---

## BLOQUE 19 — Triggers automáticos

**Descripción:** Triggers de `updated_at` y logs de cambio de estado. El trigger de `telefono_normalizado` ya se creó en Bloque 9.

```sql
-- ─── Función genérica para updated_at ─────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

-- ─── Función genérica de log de cambio de estado ──────
CREATE OR REPLACE FUNCTION log_cambio_estado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    INSERT INTO log_cambios (
      tabla_afectada, id_registro, campo_modificado,
      valor_anterior, valor_nuevo, modificado_por, source_event, nivel
    ) VALUES (
      TG_TABLE_NAME,
      (SELECT row_to_json(NEW)->>(TG_ARGV[0]))::TEXT,
      'estado',
      OLD.estado::TEXT,
      NEW.estado::TEXT,
      COALESCE(current_setting('app.modificado_por', TRUE), 'trigger_auto'),
      COALESCE(current_setting('app.source_event', TRUE), 'estado_change'),
      'info'
    );
  END IF;
  RETURN NEW;
END;
$$;

-- ─── Triggers updated_at ──────────────────────────────
CREATE TRIGGER trg_pre_reservas_updated_at BEFORE UPDATE ON pre_reservas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_reservas_updated_at BEFORE UPDATE ON reservas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pagos_updated_at BEFORE UPDATE ON pagos
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_huespedes_updated_at BEFORE UPDATE ON huespedes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_consultas_updated_at BEFORE UPDATE ON consultas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_descuentos_updated_at BEFORE UPDATE ON descuentos
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_eventos_updated_at BEFORE UPDATE ON eventos_especiales
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_tarifas_updated_at BEFORE UPDATE ON tarifas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_config_updated_at BEFORE UPDATE ON configuracion_general
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ─── Triggers de log de cambio de estado ──────────────
-- (Se pasa el nombre del campo PK como argumento del trigger)
CREATE TRIGGER trg_log_pre_reservas_estado
  AFTER UPDATE OF estado ON pre_reservas
  FOR EACH ROW EXECUTE FUNCTION log_cambio_estado('id_pre_reserva');

CREATE TRIGGER trg_log_reservas_estado
  AFTER UPDATE OF estado ON reservas
  FOR EACH ROW EXECUTE FUNCTION log_cambio_estado('id_reserva');

CREATE TRIGGER trg_log_pagos_estado
  AFTER UPDATE OF estado ON pagos
  FOR EACH ROW EXECUTE FUNCTION log_cambio_estado('id_pago');
```

**Verificación post-ejecución:**

```sql
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;
```

Debe devolver al menos 13 triggers (9 de updated_at + 3 de log estado + 1 de telefono ya creado en Bloque 9).

**Rollback:**

```sql
DROP TRIGGER IF EXISTS trg_log_pagos_estado ON pagos;
DROP TRIGGER IF EXISTS trg_log_reservas_estado ON reservas;
DROP TRIGGER IF EXISTS trg_log_pre_reservas_estado ON pre_reservas;
DROP TRIGGER IF EXISTS trg_config_updated_at ON configuracion_general;
DROP TRIGGER IF EXISTS trg_tarifas_updated_at ON tarifas;
DROP TRIGGER IF EXISTS trg_eventos_updated_at ON eventos_especiales;
DROP TRIGGER IF EXISTS trg_descuentos_updated_at ON descuentos;
DROP TRIGGER IF EXISTS trg_consultas_updated_at ON consultas;
DROP TRIGGER IF EXISTS trg_huespedes_updated_at ON huespedes;
DROP TRIGGER IF EXISTS trg_pagos_updated_at ON pagos;
DROP TRIGGER IF EXISTS trg_reservas_updated_at ON reservas;
DROP TRIGGER IF EXISTS trg_pre_reservas_updated_at ON pre_reservas;
DROP FUNCTION IF EXISTS log_cambio_estado();
DROP FUNCTION IF EXISTS set_updated_at();
```

---

## BLOQUE 20 — Vistas SQL

**Descripción:** Crea 6 vistas operativas. **Cambio v1.7.3 (D-7A-03):** `vista_disponibilidad` y `vista_calendario` leen el horizonte forward desde `configuracion_general.horizonte_disponibilidad_dias` con fallback 120 (antes hardcoded 60). Las definiciones reflejan la forma persistida por `pg_get_viewdef()`.

```sql
-- ─── V1. vista_disponibilidad ──────────────────────────
-- v1.7.3 (D-7A-03): horizonte configurable vía configuracion_general
-- con fallback 120. Rango exclusivo [CURRENT_DATE, CURRENT_DATE + N).
-- Forma persistida (pg_get_viewdef): 9 columnas explícitas; PostgreSQL
-- absorbe el cast ::DATE redundante sobre CURRENT_DATE + INTEGER.
CREATE OR REPLACE VIEW vista_disponibilidad AS
SELECT id_cabana,
    fecha,
    estado,
    tipo_dia,
    temporada,
    hora_checkin_base,
    hora_checkout_base,
    id_reserva_activa,
    id_prereserva_activa
   FROM obtener_disponibilidad_rango(CURRENT_DATE, CURRENT_DATE + COALESCE(( SELECT configuracion_general.valor::integer AS valor
           FROM configuracion_general
          WHERE configuracion_general.clave = 'horizonte_disponibilidad_dias'::text), 120), NULL::bigint);

-- ─── V2. vista_calendario ──────────────────────────────
-- Calendario operativo de reservas activas/confirmadas dentro del horizonte.
-- v1.7.2 (H6): TRIM aplicado a la concatenación nombre + apellido para
-- evitar espacio colgando cuando apellido es NULL o vacío.
-- v1.7.3 (D-7A-03): horizonte configurable vía configuracion_general con
-- fallback 120. Filtro inclusivo <= (operador sin cambios respecto a v1.7.2).
CREATE OR REPLACE VIEW vista_calendario AS
SELECT c.id_cabana,
    c.nombre AS cabana,
    r.id_reserva,
    r.fecha_checkin,
    r.fecha_checkout,
    r.hora_checkin,
    r.hora_checkout,
    r.personas,
    r.estado AS estado_reserva,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped_nombre,
    h.telefono AS huesped_telefono,
    r.monto_total,
    r.monto_saldo,
    r.encargado_semana
   FROM reservas r
     JOIN cabanas c ON c.id_cabana = r.id_cabana
     JOIN huespedes h ON h.id_huesped = r.id_huesped
  WHERE (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum])) AND r.fecha_checkout >= CURRENT_DATE AND r.fecha_checkin <= (CURRENT_DATE + COALESCE(( SELECT configuracion_general.valor::integer AS valor
           FROM configuracion_general
          WHERE configuracion_general.clave = 'horizonte_disponibilidad_dias'::text), 120))
  ORDER BY r.fecha_checkin, c.id_cabana;

-- ─── V3. vista_prereservas_activas ─────────────────────
-- v1.7.2 (H6-bis): TRIM aplicado a la concatenación nombre + apellido.
CREATE OR REPLACE VIEW vista_prereservas_activas AS
SELECT pr.id_pre_reserva,
    c.nombre AS cabana,
    pr.id_cabana,
    pr.fecha_in,
    pr.fecha_out,
    pr.personas,
    pr.estado,
    pr.expira_en,
    EXTRACT(epoch FROM pr.expira_en - now()) / 60::numeric AS minutos_para_vencer,
    pr.monto_total,
    pr.monto_sena,
    pr.canal_origen,
    pr.canal_pago_esperado,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped_nombre,
    h.telefono AS huesped_telefono
   FROM pre_reservas pr
     JOIN cabanas c ON c.id_cabana = pr.id_cabana
     JOIN huespedes h ON h.id_huesped = pr.id_huesped
  WHERE (pr.estado = ANY (ARRAY['pendiente_pago'::estado_prereserva_enum, 'pago_en_revision'::estado_prereserva_enum])) AND pr.expira_en > now()
  ORDER BY pr.expira_en;

-- ─── V4. vista_ocupacion ───────────────────────────────
-- Ocupación por cabaña y mes (últimos 12 meses y próximos 12).
-- v1.7.2 (H5): rango ajustado a 24 meses exactos restando '1 mon'::interval
-- al límite superior del generate_series para evitar el edge case que generaba
-- 25 puntos (= 25 meses × cabaña).
CREATE OR REPLACE VIEW vista_ocupacion AS
 WITH meses AS (
         SELECT generate_series(date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) - '1 year'::interval, date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) + '1 year'::interval - '1 mon'::interval, '1 mon'::interval)::date AS inicio_mes
        ), matriz AS (
         SELECT c.id_cabana,
            c.nombre AS cabana,
            m.inicio_mes,
            (m.inicio_mes + '1 mon'::interval - '1 day'::interval)::date AS fin_mes
           FROM cabanas c
             CROSS JOIN meses m
          WHERE c.activa = true
        )
 SELECT id_cabana,
    cabana,
    inicio_mes,
    fin_mes,
    COALESCE(( SELECT sum(LEAST(r.fecha_checkout, (mx.fin_mes + '1 day'::interval)::date) - GREATEST(r.fecha_checkin, mx.inicio_mes)) AS sum
           FROM reservas r
          WHERE r.id_cabana = mx.id_cabana AND (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum, 'completada'::estado_reserva_enum])) AND r.fecha_checkin < (mx.fin_mes + '1 day'::interval)::date AND r.fecha_checkout > mx.inicio_mes), 0::bigint) AS noches_ocupadas,
    EXTRACT(day FROM fin_mes + '1 day'::interval - inicio_mes::timestamp without time zone)::integer AS dias_del_mes
   FROM matriz mx
  ORDER BY id_cabana, inicio_mes;

-- ─── V5. vista_calendario_semanal (Sistema 3) ──────────
-- Próximos 7 días con todos los movimientos operativos
CREATE OR REPLACE VIEW vista_calendario_semanal AS
SELECT
  c.id_cabana,
  c.nombre AS cabana,
  d.fecha,
  -- Estado del día
  CASE
    WHEN EXISTS (
      SELECT 1 FROM bloqueos b
      WHERE b.activo = TRUE
        AND (b.id_cabana = c.id_cabana OR b.id_cabana IS NULL)
        AND d.fecha >= b.fecha_desde AND d.fecha < b.fecha_hasta
    ) THEN 'bloqueada'
    WHEN EXISTS (
      SELECT 1 FROM reservas r
      WHERE r.id_cabana = c.id_cabana
        AND r.estado IN ('confirmada', 'activa')
        AND d.fecha >= r.fecha_checkin AND d.fecha < r.fecha_checkout
    ) THEN 'ocupada'
    ELSE 'libre'
  END AS estado,
  -- ID de reserva si hay una activa este día
  (SELECT r.id_reserva FROM reservas r
   WHERE r.id_cabana = c.id_cabana
     AND r.estado IN ('confirmada', 'activa')
     AND d.fecha >= r.fecha_checkin AND d.fecha < r.fecha_checkout
   LIMIT 1) AS id_reserva,
  -- Si entra alguien este día
  (SELECT r.id_reserva FROM reservas r
   WHERE r.id_cabana = c.id_cabana
     AND r.estado IN ('confirmada', 'activa')
     AND r.fecha_checkin = d.fecha
   LIMIT 1) AS reserva_entrante,
  -- Si sale alguien este día
  (SELECT r.id_reserva FROM reservas r
   WHERE r.id_cabana = c.id_cabana
     AND r.estado IN ('confirmada', 'activa', 'completada')
     AND r.fecha_checkout = d.fecha
   LIMIT 1) AS reserva_saliente
FROM cabanas c
CROSS JOIN generate_series(CURRENT_DATE, (CURRENT_DATE + 6)::DATE, '1 day') AS d(fecha)
WHERE c.activa = TRUE
ORDER BY d.fecha, c.id_cabana;

-- ─── V6. vista_limpieza_semana (Sistema 4 — Jennifer) ──
-- Check-ins y check-outs de los próximos 7 días con horas declaradas.
-- v1.7.2 (H6): TRIM aplicado a la concatenación nombre + apellido en
-- ambas partes del UNION ALL (checkout y checkin).
CREATE OR REPLACE VIEW vista_limpieza_semana AS
 SELECT r.fecha_checkout AS fecha_movimiento,
    'checkout'::text AS tipo_movimiento,
    c.nombre AS cabana,
    c.id_cabana,
    r.id_reserva,
    r.hora_checkout AS hora,
    r.personas,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped,
    h.telefono AS huesped_telefono,
    r.mascotas,
    r.detalle_mascotas,
    r.notas_reserva
   FROM reservas r
     JOIN cabanas c ON c.id_cabana = r.id_cabana
     JOIN huespedes h ON h.id_huesped = r.id_huesped
  WHERE (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum, 'completada'::estado_reserva_enum])) AND r.fecha_checkout >= CURRENT_DATE AND r.fecha_checkout <= (CURRENT_DATE + 7)
UNION ALL
 SELECT r.fecha_checkin AS fecha_movimiento,
    'checkin'::text AS tipo_movimiento,
    c.nombre AS cabana,
    c.id_cabana,
    r.id_reserva,
    r.hora_checkin AS hora,
    r.personas,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped,
    h.telefono AS huesped_telefono,
    r.mascotas,
    r.detalle_mascotas,
    r.notas_reserva
   FROM reservas r
     JOIN cabanas c ON c.id_cabana = r.id_cabana
     JOIN huespedes h ON h.id_huesped = r.id_huesped
  WHERE (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum])) AND r.fecha_checkin >= CURRENT_DATE AND r.fecha_checkin <= (CURRENT_DATE + 7)
  ORDER BY 1, 6;
```

**Verificación post-ejecución:**

```sql
SELECT viewname FROM pg_views WHERE schemaname = 'public'
ORDER BY viewname;
```

Debe devolver 6 vistas.

**Rollback:**

```sql
DROP VIEW IF EXISTS vista_limpieza_semana;
DROP VIEW IF EXISTS vista_calendario_semanal;
DROP VIEW IF EXISTS vista_ocupacion;
DROP VIEW IF EXISTS vista_prereservas_activas;
DROP VIEW IF EXISTS vista_calendario;
DROP VIEW IF EXISTS vista_disponibilidad;
```

---

## BLOQUE 21 — Datos seed mínimos

**Descripción:** Carga inicial mínima para que el sistema funcione en DEV. **Placeholders documentados:**

- **`Socio 3`** es placeholder hasta cargar nombre real del tercer socio.
- **Cuenta de cobro** queda inactiva como placeholder.
- **Tarifas productivas** NO se cargan acá. Se cargan en etapa de operación.
- **Feriados productivos** NO se cargan acá.
- **Temporada baseline** es solo para evitar gaps en cálculo de precios durante DEV. No reemplaza temporadas reales.
- **Plantilla `prereserva_creada`** es ejemplo mínimo.

```sql
-- ─── CABAÑAS (datos reales — v1.2: capacidades corregidas) ───
-- Grandes: capacidad_base 3, capacidad_max 5
-- Chicas:  capacidad_base 2, capacidad_max 4
INSERT INTO cabanas (nombre, tipo, capacidad_base, capacidad_max, activa, orden_limpieza) VALUES
  ('Bamboo',       'grande', 3, 5, TRUE, 1),
  ('Madre Selva',  'grande', 3, 5, TRUE, 2),
  ('Arrebol',      'grande', 3, 5, TRUE, 3),
  ('Guatemala',    'chica',  2, 4, TRUE, 4),
  ('Tokio',        'chica',  2, 4, TRUE, 5);

-- ─── SOCIOS (Socio 3 es PLACEHOLDER) ─────────────────
INSERT INTO socios (nombre, porcentaje_utilidades, activo) VALUES
  ('Franco',   33.33, TRUE),
  ('Rodrigo',  33.33, TRUE),
  ('Socio 3',  33.34, TRUE);  -- PLACEHOLDER: completar con nombre real del tercer socio

-- ─── CONFIGURACION_GENERAL (mínima para que funcione) ──
INSERT INTO configuracion_general (clave, valor, descripcion, categoria) VALUES
  ('hora_checkin_default',         '13:00', 'Check-in estándar',                'horarios'),
  ('hora_checkout_default',        '10:00', 'Check-out estándar',               'horarios'),
  ('hora_checkin_domingo',         '18:00', 'Check-in cuando domingo es primer día', 'horarios'),
  ('hora_checkout_domingo',        '16:00', 'Check-out cuando domingo es último día (vs default 10:00)', 'horarios'),  -- v1.7 (D47)
  ('hora_checkin_max_cliente',     '22:00', 'Hora máxima que puede elegir el cliente', 'horarios'),
  ('hora_checkout_min_cliente',    '07:00', 'Hora mínima que puede elegir el cliente', 'horarios'),
  ('escalonamiento_activo',        'true',  'Master switch del escalonamiento', 'escalonamiento'),
  ('escalonamiento_umbral_checkins_dia', '3', 'Check-ins simultáneos sin escalonar', 'escalonamiento'),
  ('prereserva_expiracion_minutos', '60',    'TTL default de pre-reservas',      'prereservas'),
  ('horizonte_disponibilidad_dias', '120',   'Horizonte forward en días para vista_disponibilidad y vista_calendario', 'disponibilidad');  -- v1.7.3 (D-7A-03)

-- ─── CUENTA_COBRO (PLACEHOLDER inactiva) ─────────────
INSERT INTO cuentas_cobro (alias, medio, detalle, titular, activa) VALUES
  ('Cuenta principal', 'transferencia_mp', 'CBU/Alias pendiente de cargar', 'Vita Delta', FALSE);  -- PLACEHOLDER

-- ─── TEMPORADA BASELINE (solo para DEV — NO ES PRODUCTIVA) ──
INSERT INTO temporadas (nombre, fecha_desde, fecha_hasta, multiplicador, activa) VALUES
  ('Baseline DEV 2026-2028', '2026-01-01', '2028-12-31', 1.000, TRUE);

-- ─── PLANTILLA MÍNIMA ────────────────────────────────
INSERT INTO plantillas_mensajes (codigo, nombre, canal, destinatario, contenido, activa) VALUES
  ('prereserva_creada', 'Pre-reserva creada — confirmación al huésped',
   'whatsapp', 'huesped',
   'Hola {{nombre_huesped}}, te confirmo la pre-reserva de {{cabana}} del {{fecha_in}} al {{fecha_out}}. El monto total es ${{monto_total}} y la seña ${{monto_sena}}. Tenés {{expiracion_minutos}} minutos para pagar la seña. Cualquier duda, escribime.',
   TRUE);
```

**Verificación post-ejecución:**

```sql
SELECT 'cabanas' AS tabla, COUNT(*) FROM cabanas
UNION ALL SELECT 'socios', COUNT(*) FROM socios
UNION ALL SELECT 'configuracion_general', COUNT(*) FROM configuracion_general
UNION ALL SELECT 'cuentas_cobro', COUNT(*) FROM cuentas_cobro
UNION ALL SELECT 'temporadas', COUNT(*) FROM temporadas
UNION ALL SELECT 'plantillas_mensajes', COUNT(*) FROM plantillas_mensajes;
```

Esperado: cabanas=5, socios=3, configuracion_general=10, cuentas_cobro=1, temporadas=1, plantillas_mensajes=1.

**Rollback:**

```sql
TRUNCATE TABLE plantillas_mensajes, temporadas, cuentas_cobro, configuracion_general, socios, cabanas RESTART IDENTITY CASCADE;
```

---

## BLOQUE 22 — Schedule pg_cron

**Descripción:** Configura ejecución periódica de `expirar_prereservas_vencidas` y limpieza mensual del historial.

```sql
-- Job 1: expirar pre-reservas cada 5 minutos
SELECT cron.schedule(
  'expirar_prereservas',
  '*/5 * * * *',
  $$SELECT expirar_prereservas_vencidas();$$
);

-- Job 2: limpieza mensual del historial de cron
SELECT cron.schedule(
  'cleanup_cron_history',
  '0 3 1 * *',  -- día 1 de cada mes a las 03:00 UTC
  $$DELETE FROM cron.job_run_details WHERE end_time < NOW() - INTERVAL '30 days';$$
);
```

**Verificación post-ejecución:**

```sql
SELECT jobid, jobname, schedule, active FROM cron.job
WHERE jobname IN ('expirar_prereservas', 'cleanup_cron_history');
```

Esperado: 2 filas, ambas con `active = TRUE`.

**Monitoreo durante operación:**

```sql
SELECT jobid, jobname, status, return_message, start_time, end_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 20;
```

**Desactivar/borrar jobs (rollback):**

```sql
SELECT cron.unschedule('expirar_prereservas');
SELECT cron.unschedule('cleanup_cron_history');
```

---

# FIN DEL DOCUMENTO

**Estado:** Propuesta para revisión — NO EJECUTAR TODAVÍA.

**Próximos pasos sugeridos:**

1. Revisión completa de Franco. Foco prioritario en los bloques modificados en v1.5:
   - **Bloque 14** (`confirmar_reserva`) — verificar que el lock global está ANTES del `SELECT ... FOR UPDATE` de la pre-reserva.
   - **Bloque 11** (`validar_disponibilidad`) — leer la advertencia v1.5 sobre Observación G.
   - **Bloques 13, 15, 16** — verificar que el comentario inline de invariante ahora dice "antes de CUALQUIER lock".
   - **Sección 9** y **Sección 15** — leer la invariante fortalecida.
2. Aprobación explícita de v1.5.
3. Generación de documentos auxiliares en sesión separada:
   - `Docs/Arquitectura/ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md` (visión general)
   - `Docs/Implementacion/6B_REESCRITURA_WORKFLOWS.md` (cambios necesarios en workflows n8n)
   - `Docs/Implementacion/6B_PLAN_FASES.md` (orden de ejecución, criterios de avance)
4. Ejecución bloque por bloque en Supabase DEV, con verificación post-ejecución.
5. Tests funcionales de cada función crítica, especialmente:
   - Los 3 caminos de idempotencia (`recovery_path`).
   - El warning de pago sobre pre-reserva terminal.
   - **Concurrencia (v1.5):** probar `confirmar_reserva` en paralelo con `cancelar_prereserva` sobre la misma pre-reserva. Debe serializarse limpiamente sin deadlocks `40P01`.
   - `crear_prereserva` paralelo a `crear_bloqueo` total: debe serializarse.
6. Reescritura de workflows n8n para usar las nuevas funciones.
7. Migración de datos desde Sheets en producción (etapa posterior).

**Trazabilidad de versión:**

- v1.0 — Schema base, primera propuesta completa (2026-05-22).
- v1.1 — Revisión técnica con 17 ajustes consolidados.
- v1.2 — Versión quirúrgica con 9 ajustes pedidos por Franco + 3 observaciones menores. Sin cambios de arquitectura.
- v1.3 — Versión quirúrgica con 5 ajustes finales antes de ejecutar: double-check de idempotencia post-lock, validación explícita de nombre/contacto del huésped, `recovery_path` unificado, warning en pago sobre pre-reserva terminal, documentación de config inválida.
- v1.4 — Versión quirúrgica enfocada exclusivamente en concurrencia: advisory lock global `(10, 0)` introducido como Capa 0 de la estrategia anti-double-booking. `LOCK TABLE` eliminado. Aplica en `crear_prereserva`, `confirmar_reserva`, `cancelar_prereserva`, `crear_bloqueo`. Cero cambios de schema.
- v1.5 — Corrección crítica del orden de locks en `confirmar_reserva`. Invariante fortalecida: el lock global debe tomarse antes de CUALQUIER lock (advisory, row-level con `FOR UPDATE`, o table-level). Comentario inline unificado en las 4 funciones críticas. Advertencia agregada en `validar_disponibilidad`. Limpieza documental de referencias históricas a `LOCK TABLE`. Cero cambios de schema, cero features.
- v1.6 — Corrección de advisory locks por cabaña: cast explícito `::INTEGER` en Bloques 13, 14 y 16. Bug detectado durante ejecución DEV del Bloque 13 (`pg_advisory_xact_lock(integer, bigint) does not exist`). Nota técnica agregada en Sección 15 explicando las sobrecargas disponibles de `pg_advisory_xact_lock` y por qué el cast es necesario. Estado: Bloque 13 ya ejecutado y corregido en DEV vía `CREATE OR REPLACE`. Bloques 14-22 nacen correctos con v1.6.
- v1.6.1 — Corrección documental sobre v1.6. Alinea narrativa de Sección 10 con el SQL real: flujos de `confirmar_reserva` (10.6) y `cancelar_prereserva` (10.7) corregidos para reflejar el orden de locks v1.5 (lock global antes del FOR UPDATE). Menciones conceptuales del lock por cabaña en Sección 10 unificadas con cast `::INTEGER`. **Cero cambios en SQL ejecutable**, schema, funciones o tests. Patch-level. Estado idéntico a v1.6 en DEV.
- v1.7 — Incorporación de `hora_checkout_domingo` como regla operativa real (D47): si `fecha_out` es domingo, el checkout máximo es 16:00 (logística de lancha colectiva). Cambios en Bloque 13 (`crear_prereserva` lee la clave y aplica `CASE` sobre DOW), Bloque 21 (seed agrega `hora_checkout_domingo`, elimina `hora_checkout_ultimo_dia_bloque` que no se usaba) y Sección 16 (regla dominical documentada explícitamente para checkin y checkout como reglas independientes). Adicionalmente, nota operativa en Sección 15 sobre comportamiento observado en Supabase Dashboard al modificar funciones existentes, con workaround `DROP + CREATE` en runs separados. Sin cambios en locks, EXCLUDE, motor de precios, RLS, workflows ni funciones no afectadas.
- v1.7.1 — Patch-level con cambio SQL menor + dos ajustes documentales. **Bloque 12 (`obtener_disponibilidad_rango`):** `hora_checkout_base` ahora usa `CASE WHEN EXTRACT(DOW FROM m.fecha) = 0` para alinear `vista_disponibilidad` con D47. **Sección 15:** advertencia agregada sobre `DROP FUNCTION` y dependencias, con tabla de funciones del schema según si son autónomas o tienen dependencias. **Sección 16:** frase "antes del máximo 10:00" actualizada para reflejar regla dominical. DEV debe alinearse actualizando `obtener_disponibilidad_rango()` manteniendo la firma. Sin cambios en locks, EXCLUDE, motor de precios, RLS, workflows ni resto de funciones.
