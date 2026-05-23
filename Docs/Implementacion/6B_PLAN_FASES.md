# 6B_PLAN_FASES.md
# Plan de Ejecución por Fases — Etapa 6B Migración a Supabase

**Versión:** 1.1
**Fecha:** Mayo 2026
**Estado:** Propuesta para revisión — NO EJECUTAR TODAVÍA
**Documento base:** `Docs/Implementacion/6B_SCHEMA_SQL.md v1.6.1` (aprobado)
**Entorno objetivo:** Supabase DEV (proyecto `__SUPABASE_PROJECT_ID_DEV__`, región `sa-east-1`)
**Autores:** Franco (titular) + Claude (arquitecto)

> **IMPORTANTE:** Este documento describe **cómo ejecutar el SQL aprobado**, no genera SQL nuevo. La ejecución se hace bloque por bloque en Supabase DEV con verificación post-ejecución. **No ejecutar nada hasta tener este plan aprobado.**

> **NOTA DE SANITIZACIÓN (v1.1):** Este documento está sanitizado para GitHub. Las credenciales reales (Project ID, Project URL, database password, anon key, service role key, connection strings) deben vivir **fuera del repositorio**: en un gestor de contraseñas, en `.env` no versionado (cubierto por `.gitignore`), o en credentials de n8n cuando aplique. Los placeholders del estilo `__SUPABASE_PROJECT_ID_DEV__` deben reemplazarse localmente al momento de ejecutar; nunca commitear los valores reales.

---

## RESUMEN DE CAMBIOS v1.0 → v1.1

Versión de sanitización para GitHub. **Cero cambios operativos.** Mismo plan, mismo orden de fases, mismos tests, mismos criterios de éxito/freno.

### Cambios aplicados

1. **Project ID real reemplazado** por placeholder `__SUPABASE_PROJECT_ID_DEV__` en el header y en la sección de precondiciones.
2. **Project URL real reemplazada** por placeholder `__SUPABASE_PROJECT_URL_DEV__` (formato: `https://__SUPABASE_PROJECT_ID_DEV__.supabase.co`).
3. **Nota de sanitización** agregada al inicio del documento.
4. **Convención de placeholders** documentada para que quien lea sepa qué reemplazar localmente.

### Placeholders utilizados

| Placeholder | Qué reemplaza | Dónde vive el valor real |
|---|---|---|
| `__SUPABASE_PROJECT_ID_DEV__` | ID del proyecto Supabase DEV | Gestor de contraseñas / `.env` local |
| `__SUPABASE_PROJECT_URL_DEV__` | URL completa del proyecto DEV | Gestor de contraseñas / `.env` local |
| `__SUPABASE_DB_PASSWORD__` | Database password del proyecto | Gestor de contraseñas (nunca en repo) |
| `__SUPABASE_CONNECTION_STRING__` | Connection string PostgreSQL | n8n credentials / herramientas locales |
| `__SUPABASE_ANON_KEY__` | Anon key (frontend público) | `.env` local / n8n credentials |
| `__SUPABASE_SERVICE_ROLE_KEY__` | Service role key (acceso admin) | Gestor de contraseñas / n8n credentials |

### Lo que NO cambió

- Las 11 secciones del plan operativo.
- Las 5 fases de ejecución.
- La tabla de los 22 bloques.
- Los 36 tests funcionales y de concurrencia.
- Los criterios de éxito y de freno.
- El rollback documentado.
- El scope-out.
- El próximo paso (Fase 0 → Bloque 1 → bitácora → cierre).

---

## ÍNDICE

1. Resumen ejecutivo
2. Precondiciones antes de ejecutar
3. Convención de ejecución
4. Tabla de bloques SQL
5. Orden recomendado de ejecución (5 fases)
6. Tests mínimos obligatorios
7. Rollback
8. Criterios de éxito de 6B ejecución DEV
9. Criterios de freno
10. Qué NO forma parte de este plan
11. Próximo paso después de aprobar este plan

---

## 1. RESUMEN EJECUTIVO

### Qué se va a ejecutar

Los 22 bloques SQL del documento `6B_SCHEMA_SQL.md v1.6.1`, ejecutados uno por uno en Supabase DEV (no en producción), con verificación post-ejecución en cada paso. El plan se organiza en 5 fases:

- **Fase 0** — Preparación (no ejecuta SQL).
- **Fase 1** — Infraestructura base (Bloques 1-8): extensiones, enums, tablas, constraints.
- **Fase 2** — Funciones y triggers (Bloques 9-19): lógica almacenada.
- **Fase 3** — Vistas, seed y cron (Bloques 20-22).
- **Fase 4** — Tests funcionales y de concurrencia.
- **Fase 5** — Cierre DEV con checklist final.

### Qué NO se va a ejecutar todavía

- Workflows n8n no se reescriben en esta etapa.
- Frontend web no se construye en esta etapa.
- Integración real con MercadoPago, WhatsApp, Instagram no se conecta.
- Datos productivos no se migran desde Sheets.
- RLS (Row Level Security) no se habilita.
- Supabase Auth no se configura.
- Producción no se toca.

### Qué riesgos controla el plan

- **Ejecución desordenada:** la tabla de bloques documenta dependencias entre sí.
- **Errores tempranos no detectados:** cada bloque tiene un query de verificación obligatorio.
- **Doble booking en concurrencia:** la Fase 4 incluye tests específicos con `pg_sleep`.
- **Estados inconsistentes:** cada bloque tiene rollback documentado.
- **Avance sin garantías:** criterios de freno explícitos.

### Qué resultado esperamos al final

Un Supabase DEV con schema completo, funciones críticas operativas, seed mínimo cargado, pg_cron configurado, y suficientes tests pasados como para que el siguiente paso (reescritura de workflows n8n) parta de una base estable.

---

## 2. PRECONDICIONES ANTES DE EJECUTAR

Checklist obligatorio. **No avanzar a Fase 0 hasta cumplir todos los puntos.**

### 2.1 Supabase DEV creado

- [ ] Proyecto creado en Supabase con nombre identificable (ej: `vita-delta-dev`).
- [ ] Región: `sa-east-1` (São Paulo) — cercanía geográfica a Argentina.
- [ ] Plan: free tier es suficiente para DEV.
- [ ] **NO usar el proyecto de producción.** Si todavía no existe producción, mejor. Solo DEV.

### 2.2 Credenciales y secretos guardados fuera de GitHub

- [ ] Project URL: anotada localmente (formato: `https://__SUPABASE_PROJECT_ID_DEV__.supabase.co`). El valor real NO debe quedar versionado en el repo.
- [ ] Database password: guardada en gestor de contraseñas con etiqueta clara (ej: "Vita Delta — Supabase DEV — DB password"). **NO** en archivos del repo, **NO** en `.env` versionado.
- [ ] Anon key / Service role key: cuando se necesiten para n8n, se guardarán en n8n credentials, NO en repo.
- [ ] Verificar que `.gitignore` cubre `.env`, `.env.local`, archivos de credenciales.

### 2.3 Extensiones disponibles

Antes de ejecutar el Bloque 1, **verificar que las extensiones necesarias están disponibles** en el proyecto:

```sql
SELECT name
FROM pg_available_extensions
WHERE name IN ('btree_gist', 'pg_cron');
```

**Resultado esperado:**
- 2 filas
- `btree_gist`
- `pg_cron`

**Aclaración importante:** "disponible" significa que el binario está en el servidor, **no significa que esté habilitada en este proyecto**. El Bloque 1 se encarga de habilitarlas con `CREATE EXTENSION IF NOT EXISTS`.

Si alguna no aparece como disponible:
- `btree_gist` no disponible → freno total. Es nativo de PostgreSQL, debería estar siempre.
- `pg_cron` no disponible → buscar si Supabase requiere habilitar la extensión vía Dashboard antes de poder hacer `CREATE EXTENSION`. Documentar el procedimiento y reintentar.

### 2.4 Documentación local

- [ ] Tener copia local de `Docs/Implementacion/6B_SCHEMA_SQL.md v1.6.1`.
- [ ] Tener este documento (`6B_PLAN_FASES.md`) abierto durante la ejecución.
- [ ] Tener claro que el SQL se ejecuta **por bloques**, no copiando todo el archivo de una vez.

### 2.5 Entorno de ejecución

- [ ] SQL Editor de Supabase abierto y testeado con un query simple (`SELECT NOW();`).
- [ ] Capacidad de abrir 2 pestañas del SQL Editor en paralelo (necesario para tests de concurrencia en Fase 4).
- [ ] Tiempo bloqueado en agenda: estimación realista de 4-6 horas para Fases 1-3 + 2-4 horas para Fase 4 (no es urgente, mejor sin presión).

### 2.6 Mentalidad de ejecución

- [ ] **NO ejecutar bloques de a varios** "para ir más rápido".
- [ ] **NO modificar el SQL** a mano sin documentar antes en este plan.
- [ ] **NO continuar si una verificación falla**, aunque "parezca menor".
- [ ] **SÍ frenar** ante cualquier comportamiento inesperado y revisar antes de seguir.

---

## 3. CONVENCIÓN DE EJECUCIÓN

Reglas obligatorias para cada bloque:

### 3.1 Un bloque a la vez

- Copiar el SQL del bloque desde `6B_SCHEMA_SQL.md v1.6.1`.
- Pegar en SQL Editor de Supabase.
- Ejecutar.
- **No** copiar el siguiente bloque hasta haber verificado el actual.

### 3.2 Leer el output

Cada ejecución muestra mensajes en Supabase. **Leerlos antes de continuar.**

- Si dice `CREATE TABLE` / `CREATE FUNCTION` / `CREATE TYPE` / `ALTER TABLE` / etc. sin errores → bloque ejecutado.
- Si hay warnings (no errores) → leerlos. Si son benignos (ej: "extension already exists"), continuar. Si son sospechosos, frenar.
- Si hay errores → frenar. Ver Sección 9 (Criterios de freno).

### 3.3 Correr la verificación post-ejecución

Cada bloque del documento SQL v1.6.1 incluye un **query de verificación** (sección "Verificación post-ejecución" dentro del bloque). Es obligatorio correrlo.

Si el resultado del query de verificación NO coincide con el esperado:
- **Frenar.**
- Documentar el resultado real vs esperado.
- Decidir entre rollback del bloque o investigar.

### 3.4 Si falla, frenar

Cualquier error técnico (no esperado) durante la ejecución de un bloque o su verificación:
- **NO ejecutar el siguiente bloque.**
- **NO modificar el SQL a mano "para que ande".**
- Documentar el error literal (mensaje, código `SQLSTATE`, contexto).
- Revisar el bloque, el documento v1.6.1, y este plan antes de cualquier acción.

### 3.5 No continuar por intuición

Si una verificación devuelve un resultado raro pero "parece OK", **no asumir**. Verificar explícitamente.

Ejemplo: el Bloque 6 espera 5 filas en una verificación. Si devuelve 4, **no avanzar** asumiendo que "se contó mal". Investigar qué tabla falta.

### 3.6 Registrar errores

Llevar una bitácora simple (puede ser un archivo de texto local o una sección de notas en este documento) con:
- Bloque ejecutado.
- Fecha y hora.
- Resultado: OK / ERROR.
- Si ERROR: mensaje literal, qué se hizo, cómo se resolvió.

Esta bitácora es valiosa cuando volvamos a hacer el ejercicio en TEST o en PROD.

### 3.7 No modificar SQL a mano sin documentar

Si durante la ejecución se descubre un error en el SQL que requiere corregir:
- **Frenar.**
- Documentar el problema.
- Generar una nueva versión del schema SQL (patch o minor según alcance) o decidir parche puntual y documentarlo.
- **NO** correr una versión "parcheada al vuelo" sin que quede registrada.

### 3.8 No mezclar ejecución de schema con workflows n8n

Mientras se ejecuta este plan en Supabase DEV, **no tocar workflows n8n** que apunten al mismo proyecto. Los workflows n8n actuales siguen apuntando a Sheets; cuando se reescriban (etapa posterior), apuntarán a Supabase DEV. Mezclar las dos cosas a la vez complica el debugging.

---

## 4. TABLA DE BLOQUES SQL

Tabla de los 22 bloques del documento v1.6.1. Cada bloque tiene:
- **#** — número de bloque.
- **Nombre** — corto, identificable.
- **Crea/modifica** — qué hace.
- **Depende de** — qué bloques deben haberse ejecutado antes.
- **Riesgo** — bajo / medio / alto.
- **Verificación post-ejecución** — query a correr.
- **Rollback** — disponible en el documento v1.6.1.
- **Criterio para avanzar** — qué tiene que estar OK para pasar al siguiente.
- **Criterio para frenar** — qué dispara una pausa.

### Fase 1 — Infraestructura base

| # | Nombre | Crea/modifica | Depende de | Riesgo | Verificación | Rollback | Avanzar si... | Frenar si... |
|---|---|---|---|---|---|---|---|---|
| 1 | Extensiones | `btree_gist`, `pg_cron` | — | Bajo | `SELECT extname FROM pg_extension WHERE extname IN ('btree_gist', 'pg_cron')` → 2 filas | Sí | 2 filas devueltas | Falta alguna extensión |
| 2 | Enums | 4 enums (`estado_prereserva_enum`, `estado_reserva_enum`, `estado_pago_enum`, `nivel_log_enum`) | Bloque 1 | Bajo | `SELECT typname FROM pg_type WHERE typname LIKE '%_enum'` → 4 filas | Sí | 4 enums creados | Cualquier error de sintaxis |
| 3 | Tablas catálogo | `cabanas`, `huespedes`, `feriados`, `tarifas`, `temporadas`, `socios`, `cuentas_cobro`, `plantillas_mensajes` | Bloque 1 | Bajo | 8 tablas listadas en `pg_tables`; columna `telefono_normalizado` en `huespedes` | Sí | 8 tablas + columna `telefono_normalizado` presentes | Falta cualquier tabla o constraint |
| 4 | Tablas configuración | `configuracion_general`, `eventos_especiales`, `paquetes_evento`, `descuentos` | Bloque 3 | Bajo | 4 tablas listadas | Sí | 4 tablas creadas | Falta cualquier tabla o constraint |
| 5 | Tablas dependientes nivel 1 | `consultas`, `overrides_operativos` | Bloques 3, 4 | Bajo | 2 tablas listadas; índices creados | Sí | 2 tablas + índices presentes | FK falla |
| 6 | Tablas transaccionales | `pre_reservas`, `reservas`, `pagos`, `bloqueos`, `gastos` | Bloques 2, 3, 5 | **Medio** | 5 tablas; campos `mascotas`/`ninos`/`notas_reserva` en `pre_reservas` y `reservas`; `idempotency_key` en `pre_reservas`; CHECK `chk_pagos_referencia_minima` presente | Sí | Tablas + campos + CHECK presentes | Falta cualquier campo o constraint |
| 7 | Tabla de auditoría | `log_cambios` | Bloque 2 (enum `nivel_log_enum`) | Bajo | Tabla `log_cambios` con índice GIN sobre `detalle` | Sí | Tabla + índices presentes | Falta tabla o índice GIN |
| 8 | Constraints EXCLUDE | `exc_reservas_no_overlap`, `exc_bloqueos_no_overlap` | Bloques 1 (btree_gist), 6 | **Medio** | `SELECT conname FROM pg_constraint WHERE conname LIKE 'exc_%'` → 2 filas | Sí | 2 constraints EXCLUDE creados | Cualquier error de creación |

### Fase 2 — Funciones y triggers

| # | Nombre | Crea/modifica | Depende de | Riesgo | Verificación | Rollback | Avanzar si... | Frenar si... |
|---|---|---|---|---|---|---|---|---|
| 9 | `normalizar_telefono` + columna + trigger | Función `normalizar_telefono`, función `set_telefono_normalizado`, trigger `trg_huespedes_telefono_norm` | Bloque 3 (`huespedes` con columna `telefono_normalizado`) | Bajo | 2 funciones + 1 trigger creados. Test funcional con 6 casos | Sí | Test funcional devuelve los 6 valores esperados | Cualquier caso del test no coincide |
| 10 | `upsert_huesped` | Función `upsert_huesped(JSONB)` | Bloques 3, 9 (helper de normalización) | **Medio** | Test: crear huésped nuevo (modo='create'), upsert por teléfono (modo='update'), contacto requerido (error) | Sí | Los 3 tests devuelven JSONB esperado | Cualquier test no devuelve la forma esperada |
| 11 | `validar_disponibilidad` | Función `validar_disponibilidad(BIGINT, DATE, DATE, BIGINT)` | Bloques 3, 6 (tablas que consulta) | **Medio** | Función creada y compila | Sí | Función presente y devuelve JSONB con argumentos válidos | Error de compilación |
| 12 | `obtener_disponibilidad_rango` | Función `obtener_disponibilidad_rango(DATE, DATE, BIGINT)` | Bloques 3, 6 | Bajo | Función creada. Llamarla con un rango chico devuelve filas | Sí | Devuelve filas correctamente formateadas | Error de compilación o resultado raro |
| 13 | `crear_prereserva` | Función `crear_prereserva(JSONB)` — **puerta única** | Bloques 6, 9, 10, 11 | **Alto** | Función compila. Probar después de seed (Fase 3) con payload completo | Sí | Función presente, payload de prueba devuelve `ok:true` | Cualquier error compilación o lógica |
| 14 | `confirmar_reserva` | Función `confirmar_reserva(JSONB)` | Bloques 6, 11 (validar_disponibilidad) | **Alto** | Función compila. Probar después de seed | Sí | Función presente, compilación sin errores | Cualquier error de compilación |
| 15 | `cancelar_prereserva` | Función `cancelar_prereserva(JSONB)` | Bloque 6 | Medio | Función compila. Probar con id_pre_reserva inexistente (error controlado) | Sí | Función devuelve error controlado para id inexistente | Devuelve excepción cruda |
| 16 | `crear_bloqueo` | Función `crear_bloqueo(JSONB)` | Bloques 6, 8 (EXCLUDE) | **Alto** | Función compila. Probar con id_cabana = NULL (bloqueo total) y con id_cabana específica | Sí | Ambos caminos compilan | Error en cualquiera de los dos caminos |
| 17 | `registrar_pago` | Función `registrar_pago(JSONB)` | Bloque 6 | Medio | Función compila. Test con pre-reserva activa (estado=`en_revision`) | Sí | Devuelve JSONB esperado | Error de compilación |
| 18 | `expirar_prereservas_vencidas` | Función `expirar_prereservas_vencidas()` | Bloque 6 | Bajo | Función creada. Llamada manual devuelve integer (0 si no hay vencidas) | Sí | Devuelve integer | Error de compilación |
| 19 | Triggers automáticos | `set_updated_at`, `log_cambio_estado` + 12 triggers en 9 tablas | Bloques 3-7 | Medio | `SELECT trigger_name FROM information_schema.triggers WHERE trigger_schema = 'public'` → al menos 13 triggers | Sí | 13 o más triggers creados | Falta cualquier trigger |

### Fase 3 — Vistas, seed y cron

| # | Nombre | Crea/modifica | Depende de | Riesgo | Verificación | Rollback | Avanzar si... | Frenar si... |
|---|---|---|---|---|---|---|---|---|
| 20 | Vistas SQL | 6 vistas (`vista_disponibilidad`, `vista_calendario`, `vista_prereservas_activas`, `vista_ocupacion`, `vista_calendario_semanal`, `vista_limpieza_semana`) | Bloques 6, 12 (función) | Bajo | 6 vistas en `pg_views`. Cada vista responde sin error a `SELECT * FROM <vista> LIMIT 1` (incluso si devuelve 0 filas porque no hay datos aún) | Sí | 6 vistas responden | Cualquier vista falla en compilación |
| 21 | Datos seed mínimos | 5 cabañas, 3 socios (incluyendo `Socio 3` placeholder), 9 claves de configuración, 1 cuenta de cobro placeholder, 1 temporada baseline, 1 plantilla de mensaje | Bloques 3, 4 | Bajo | Conteos esperados: cabanas=5, socios=3, configuracion_general=9, cuentas_cobro=1, temporadas=1, plantillas_mensajes=1 | Sí (TRUNCATE) | Conteos coinciden + capacidades correctas (3/5 grandes, 2/4 chicas) | Cualquier conteo no coincide o capacidades erradas |
| 22 | Schedule pg_cron | `expirar_prereservas` cada 5 min + `cleanup_cron_history` mensual | Bloques 1 (pg_cron), 18 (función) | Medio | `SELECT jobname, schedule, active FROM cron.job WHERE jobname IN ('expirar_prereservas', 'cleanup_cron_history')` → 2 filas, ambas active=TRUE | Sí (`cron.unschedule`) | 2 jobs activos | Job no se crea o queda inactive |

### Dependencias clave (resumen)

**Dentro de Fase 1:** orden estricto.
```
1 (ext) → 2 (enums) → 3 (catálogo) → 4 (config) → 5 (dep N1)
                                 → 6 (transaccional, requiere 2 + 3)
                                 → 7 (auditoría, requiere 2)
                                 → 8 (EXCLUDE, requiere 1 + 6)
```

**Dentro de Fase 2:** cadena de funciones.
```
9 (normalizar_telefono)
  ↓
10 (upsert_huesped, usa normalizar_telefono indirectamente)
  ↓
11 (validar_disponibilidad)
  ↓
12 (obtener_disponibilidad_rango)
  ↓
13 (crear_prereserva, requiere 9, 10, 11)
  ↓
14 (confirmar_reserva, requiere 11 para revalidar)
  ↓
15 (cancelar_prereserva, requiere 6)
  ↓
16 (crear_bloqueo, requiere 6 + 8)
  ↓
17 (registrar_pago, requiere 6)
  ↓
18 (expirar_prereservas_vencidas, requiere 6)
  ↓
19 (triggers, requieren log_cambios del 7 y funciones genéricas creadas en el mismo bloque)
```

**Fase 3:** depende de funciones y tablas previas.
```
20 (vistas, requieren 6 + 12)
21 (seed, requiere 3 + 4)
22 (cron, requiere 1 + 18)
```

---

## 5. ORDEN RECOMENDADO DE EJECUCIÓN (5 FASES)

### FASE 0 — Preparación (NO ejecuta SQL)

Objetivo: verificar que el entorno está listo. **Sin SQL todavía.**

**Pasos:**

1. Confirmar checklist completo de Sección 2 (Precondiciones).
2. Abrir SQL Editor de Supabase DEV.
3. Correr query de verificación de extensiones disponibles:
   ```sql
   SELECT name FROM pg_available_extensions
   WHERE name IN ('btree_gist', 'pg_cron');
   ```
   Esperado: 2 filas.
4. Correr query de smoke test del editor:
   ```sql
   SELECT NOW(), current_database(), version();
   ```
   Debe devolver 1 fila con la fecha actual, nombre del DB y versión de PostgreSQL.
5. Confirmar que no estamos en producción (verificar nombre del proyecto).
6. Tener `6B_SCHEMA_SQL.md v1.6.1` abierto en otra ventana.
7. Tener este documento abierto.

**Criterio para avanzar a Fase 1:** todos los puntos del checklist OK.

**Criterio para frenar:** cualquier punto falla. Frenar y resolver antes de continuar.

---

### FASE 1 — Infraestructura base (Bloques 1 a 8)

Objetivo: crear el schema completo (extensiones, enums, tablas, constraints) sin todavía cargar funciones ni datos.

**Orden estricto:**

1. **Bloque 1** — Extensiones. Verificar que devuelve `CREATE EXTENSION` (o "extension already exists" si ya estaba habilitada).
   - Verificación: `SELECT extname FROM pg_extension WHERE extname IN ('btree_gist', 'pg_cron');` → 2 filas.

2. **Bloque 2** — Enums. Crea 4 tipos.
   - Verificación: `SELECT typname FROM pg_type WHERE typname LIKE '%_enum';` → 4 filas.

3. **Bloque 3** — Tablas catálogo (8 tablas).
   - Verificación: 8 tablas en `pg_tables`. Columna `telefono_normalizado` en `huespedes`.

4. **Bloque 4** — Tablas de configuración (4 tablas).
   - Verificación: 4 tablas en `pg_tables`.

5. **Bloque 5** — `consultas` + `overrides_operativos`.
   - Verificación: 2 tablas. FK a `huespedes` y `cabanas` activas.

6. **Bloque 6** — Tablas transaccionales (5 tablas). **Riesgo medio**: chequear que están los 4 campos operativos en `pre_reservas` y `reservas`, el `idempotency_key`, y el CHECK `chk_pagos_referencia_minima`.

7. **Bloque 7** — `log_cambios` con índice GIN sobre `detalle`.

8. **Bloque 8** — 2 constraints EXCLUDE. **Riesgo medio**: si falla acá, `btree_gist` no está bien habilitada.

**Criterio para avanzar a Fase 2:** los 8 bloques verificados sin errores.

**Criterio para frenar dentro de Fase 1:**
- Cualquier `CREATE` falla con error.
- Cualquier verificación devuelve conteo distinto al esperado.
- Cualquier columna o constraint clave (`telefono_normalizado`, `idempotency_key`, `chk_pagos_referencia_minima`, EXCLUDE) no está presente.

---

### FASE 2 — Funciones y triggers (Bloques 9 a 19)

Objetivo: crear toda la lógica almacenada. **Esta fase es la más sensible.**

**Orden estricto (ver dependencias en Sección 4):**

1. **Bloque 9** — `normalizar_telefono` + columna + trigger. **Correr el test funcional** con los 6 casos del documento v1.6.1. Si alguno falla, frenar.

2. **Bloque 10** — `upsert_huesped`. Correr los 3 tests funcionales del documento v1.5.

3. **Bloque 11** — `validar_disponibilidad`. Solo verificar que compila. (Tests reales en Fase 4 con datos del seed.)

4. **Bloque 12** — `obtener_disponibilidad_rango`. Verificar que compila y que con un rango pequeño devuelve filas (0 filas válidas porque no hay seed aún; el query debe ejecutar sin error).

5. **Bloque 13** — `crear_prereserva`. **Alto riesgo.** Solo verificar compilación. Test funcional real en Fase 4 (necesita seed).

6. **Bloque 14** — `confirmar_reserva`. Alto riesgo. Solo verificar compilación.

7. **Bloque 15** — `cancelar_prereserva`. Verificar compilación. Probar con id inexistente → debe devolver `ok:false, error:'prereserva_no_existe'`.

8. **Bloque 16** — `crear_bloqueo`. Alto riesgo. Verificar compilación.

9. **Bloque 17** — `registrar_pago`. Verificar compilación.

10. **Bloque 18** — `expirar_prereservas_vencidas`. Llamada manual:
    ```sql
    SELECT expirar_prereservas_vencidas();
    ```
    Debe devolver `0` (no hay pre-reservas vencidas porque la tabla está vacía).

11. **Bloque 19** — 12+ triggers automáticos. Verificación:
    ```sql
    SELECT trigger_name, event_object_table
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
    ORDER BY event_object_table, trigger_name;
    ```
    Esperado: al menos 13 triggers (9 de updated_at + 3 de log de estado + 1 de telefono_normalizado del Bloque 9).

**Criterio para avanzar a Fase 3:**
- Las 11 funciones compilan.
- Los tests funcionales de los bloques 9 y 10 pasan.
- Los triggers están todos creados.

**Criterio para frenar dentro de Fase 2:**
- Cualquier función no compila.
- Tests del Bloque 9 (normalización de teléfono) fallan.
- Tests del Bloque 10 (upsert_huesped) fallan.
- `expirar_prereservas_vencidas` devuelve algo distinto a `0`.
- Conteo de triggers menor a 13.

---

### FASE 3 — Vistas, seed y cron (Bloques 20 a 22)

Objetivo: crear las vistas operativas, cargar el seed mínimo, configurar pg_cron.

**Orden:**

1. **Bloque 20** — 6 vistas SQL. Verificar:
   ```sql
   SELECT viewname FROM pg_views WHERE schemaname = 'public' ORDER BY viewname;
   ```
   Esperado: 6 vistas. Después correr `SELECT * FROM <vista> LIMIT 1;` para cada una (puede devolver 0 filas, pero no debe dar error).

2. **Bloque 21** — Seed mínimo. **Crítico verificar capacidades:**
   ```sql
   SELECT nombre, tipo, capacidad_base, capacidad_max FROM cabanas ORDER BY orden_limpieza;
   ```
   Esperado:
   - Bamboo, grande, 3, 5
   - Madre Selva, grande, 3, 5
   - Arrebol, grande, 3, 5
   - Guatemala, chica, 2, 4
   - Tokio, chica, 2, 4

   Si las capacidades no coinciden → freno + investigar el SQL del seed.

3. **Bloque 22** — pg_cron schedule.
   ```sql
   SELECT jobid, jobname, schedule, active FROM cron.job
   WHERE jobname IN ('expirar_prereservas', 'cleanup_cron_history');
   ```
   Esperado: 2 filas, ambas `active = TRUE`.

**Criterio para avanzar a Fase 4:**
- 6 vistas creadas y responden.
- Seed cargado con capacidades correctas.
- 2 cron jobs activos.

**Criterio para frenar dentro de Fase 3:**
- Cualquier vista falla en compilación o consulta.
- Conteos del seed no coinciden.
- Capacidades de cabañas erradas.
- pg_cron no logra crear el job.

---

### FASE 4 — Tests funcionales

Objetivo: validar que las funciones funcionan end-to-end con datos reales del seed.

Esta fase tiene su propia sección detallada: ver **Sección 6 (Tests mínimos obligatorios)**.

**Criterio para avanzar a Fase 5:**
- Todos los tests obligatorios de Sección 6 pasan.

**Criterio para frenar dentro de Fase 4:**
- Cualquier test devuelve resultado distinto al esperado.
- Cualquier test produce error crudo no controlado.

---

### FASE 5 — Cierre DEV

Objetivo: confirmar formalmente que Supabase DEV está listo como base de datos operativa.

**Checklist final:**

- [ ] Fases 0-4 completadas.
- [ ] Todos los criterios de éxito de Sección 8 cumplidos.
- [ ] Bitácora de ejecución completa.
- [ ] Documentado en repositorio: estado de DEV, fecha de cierre, observaciones.

**Pendientes que NO bloquean cierre de Fase 5:**

- Workflows n8n reescritos → siguiente etapa (`6B_REESCRITURA_WORKFLOWS.md`).
- Frontend web → más adelante.
- Integraciones reales (MercadoPago, WhatsApp, Instagram) → más adelante.
- Migración de datos productivos de Sheets → etapa posterior.

**Salida formal de Fase 5:** declarar "Supabase DEV listo como base de datos operativa". A partir de acá, se puede empezar a desarrollar workflows n8n contra DEV.

---

## 6. TESTS MÍNIMOS OBLIGATORIOS

Estos tests se corren en Fase 4. Todos deben pasar antes de declarar DEV cerrado.

### 6.1 Tests de huéspedes

#### T-H-1: Crear huésped nuevo

```sql
SELECT upsert_huesped(jsonb_build_object(
  'nombre',   'Test Huésped 1',
  'telefono', '+5491111111111',
  'email',    'test1@example.com'
));
```
Esperado: `{"ok": true, "modo": "create", "id_huesped": N, "encontrado_por": null}`.

#### T-H-2: Upsert por teléfono

```sql
SELECT upsert_huesped(jsonb_build_object(
  'telefono', '+5491111111111'
));
```
Esperado: `{"ok": true, "modo": "update", "id_huesped": <mismo N de T-H-1>, "encontrado_por": "telefono"}`.

#### T-H-3: Upsert por email

```sql
-- Crear huésped solo con email distinto
SELECT upsert_huesped(jsonb_build_object(
  'nombre',   'Test Huésped 3',
  'email',    'test3@example.com'
));
-- Luego buscar solo por email
SELECT upsert_huesped(jsonb_build_object(
  'email', 'test3@example.com'
));
```
Esperado: segunda llamada devuelve `modo='update'` con el mismo `id_huesped`, `encontrado_por='email'`.

#### T-H-4: Contacto requerido

```sql
SELECT upsert_huesped(jsonb_build_object(
  'nombre', 'Sin contacto'
));
```
Esperado: `{"ok": false, "error": "contacto_requerido", ...}`.

#### T-H-5: Conflicto DNI controlado

```sql
-- Crear huésped A con DNI 12345678
SELECT upsert_huesped(jsonb_build_object(
  'nombre',   'A con DNI',
  'dni',      '12345678',
  'telefono', '+5491122222222'
));
-- Intentar crear B con mismo DNI pero teléfono distinto
SELECT upsert_huesped(jsonb_build_object(
  'nombre',   'B con mismo DNI',
  'dni',      '12345678',
  'telefono', '+5491133333333'
));
```
Esperado: segunda llamada devuelve `{"ok": false, "error": "huesped_duplicado", "conflicto": "dni", ...}`.

---

### 6.2 Tests de pre-reserva

Setup: usar `id_cabana = 1` (Bamboo). Usar fechas futuras (ej: 2026-09-01 al 2026-09-03).

#### T-PR-1: Crear pre-reserva correcta

```sql
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object(
    'nombre',   'Cliente Test PR1',
    'telefono', '+5491144444444'
  ),
  'id_cabana',           1,
  'fecha_in',            '2026-09-01',
  'fecha_out',           '2026-09-03',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-PR-1'
));
```
Esperado: `{"ok": true, "idempotent_match": false, "recovery_path": null, "id_pre_reserva": N, ...}`.

#### T-PR-2: Sin nombre → error

```sql
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object(
    'telefono', '+5491155555555'
  ),
  'id_cabana',           2,
  'fecha_in',            '2026-09-05',
  'fecha_out',           '2026-09-07',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-PR-2'
));
```
Esperado: `{"ok": false, "error": "huesped_nombre_requerido", ...}`.

#### T-PR-3: Sin teléfono/email → error

```sql
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object(
    'nombre', 'Sin contacto'
  ),
  'id_cabana',           2,
  'fecha_in',            '2026-09-05',
  'fecha_out',           '2026-09-07',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-PR-3'
));
```
Esperado: `{"ok": false, "error": "huesped_contacto_requerido", ...}`.

#### T-PR-4: Cabaña inexistente

```sql
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'X', 'telefono', '+5491166666666'),
  'id_cabana',           999,
  'fecha_in',            '2026-09-05',
  'fecha_out',           '2026-09-07',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-PR-4'
));
```
Esperado: `{"ok": false, "error": "cabana_no_existe"}`.

#### T-PR-5: Capacidad excedida

```sql
-- Tokio tiene capacidad_max=4
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'X', 'telefono', '+5491177777777'),
  'id_cabana',           5,                -- Tokio
  'fecha_in',            '2026-09-05',
  'fecha_out',           '2026-09-07',
  'personas',            6,                -- excede capacidad_max=4
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-PR-5'
));
```
Esperado: `{"ok": false, "error": "excede_capacidad", "capacidad_max": 4}`.

#### T-PR-6: Monto faltante

```sql
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'X', 'telefono', '+5491188888888'),
  'id_cabana',           1,
  'fecha_in',            '2026-09-10',
  'fecha_out',           '2026-09-12',
  'personas',            2,
  -- sin monto_total ni monto_sena
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-PR-6'
));
```
Esperado: `{"ok": false, "error": "precio_requerido", ...}`.

#### T-PR-7: Idempotency key — misma key, devuelve la misma

```sql
-- Primera llamada
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'Idem', 'telefono', '+5491199999999'),
  'id_cabana',           2,                -- Madre Selva
  'fecha_in',            '2026-10-01',
  'fecha_out',           '2026-10-03',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-PR-7',
  'idempotency_key',     'test-idem-001'
));
-- Segunda llamada con misma key
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'Idem', 'telefono', '+5491199999999'),
  'id_cabana',           2,
  'fecha_in',            '2026-10-01',
  'fecha_out',           '2026-10-03',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-PR-7-retry',
  'idempotency_key',     'test-idem-001'
));
```
Esperado: segunda llamada devuelve `{"ok": true, "idempotent_match": true, "id_pre_reserva": <mismo N>, "recovery_path": "pre_lock"}`.

---

### 6.3 Tests de disponibilidad

#### T-D-1: Pre-reserva bloquea disponibilidad

Asumiendo que T-PR-1 creó una pre-reserva activa para Bamboo del 2026-09-01 al 2026-09-03.

```sql
-- Intentar otra pre-reserva en mismo rango
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'Otro', 'telefono', '+5491200000001'),
  'id_cabana',           1,
  'fecha_in',            '2026-09-02',
  'fecha_out',           '2026-09-04',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-D-1'
));
```
Esperado: `{"ok": false, "error": "no_disponible", "conflictos": [...]}`.

#### T-D-2: Pre-reserva vencida no bloquea

```sql
-- Forzar vencimiento de pre-reserva de prueba
UPDATE pre_reservas SET expira_en = NOW() - INTERVAL '1 hour'
WHERE source_event = 'test_T-PR-1';
SELECT expirar_prereservas_vencidas();
-- Ahora intentar crear pre-reserva sobre el mismo rango
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'Después', 'telefono', '+5491200000002'),
  'id_cabana',           1,
  'fecha_in',            '2026-09-01',
  'fecha_out',           '2026-09-03',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-D-2'
));
```
Esperado: `{"ok": true, ...}`. La pre-reserva vencida no bloquea.

#### T-D-3, T-D-4, T-D-5

Confirmados implícitamente en tests de bloqueos (Sección 6.5).

---

### 6.4 Tests de confirmación

#### T-CR-1: Sin pago confirmado → error

Crear pre-reserva, intentar confirmar sin pago:

```sql
-- Asumiendo id_pre_reserva = X de T-PR-1 (re-crear si fue vencida en T-D-2)
SELECT confirmar_reserva(jsonb_build_object(
  'id_pre_reserva', X,
  'source_event',   'test_T-CR-1'
));
```
Esperado: `{"ok": false, "error": "sin_pago_confirmado", ...}`.

#### T-CR-2: Con pago confirmado → reserva creada

```sql
-- Registrar pago confirmado
SELECT registrar_pago(jsonb_build_object(
  'id_pre_reserva',   X,
  'tipo',             'sena',
  'medio_pago',       'transferencia_mp',
  'monto_esperado',   50000,
  'monto_recibido',   50000,
  'estado_inicial',   'confirmado',
  'validado_por',     'test_admin',
  'source_event',     'test_T-CR-2-pago'
));
-- Confirmar reserva
SELECT confirmar_reserva(jsonb_build_object(
  'id_pre_reserva', X,
  'source_event',   'test_T-CR-2-confirm'
));
```
Esperado: `{"ok": true, "id_reserva": N, "id_pre_reserva": X, ...}`.

#### T-CR-3: Camino combinado con permitir_pago_en_revision

```sql
-- Crear nueva pre-reserva Y, registrar pago en_revision
SELECT registrar_pago(jsonb_build_object(
  'id_pre_reserva',   Y,
  'tipo',             'sena',
  'medio_pago',       'transferencia_bancaria',
  'monto_esperado',   50000,
  'monto_recibido',   45000,                   -- pago parcial → en_revision
  'source_event',     'test_T-CR-3-pago'
));
-- Confirmar con permitir_pago_en_revision
SELECT confirmar_reserva(jsonb_build_object(
  'id_pre_reserva',              Y,
  'permitir_pago_en_revision',   true,
  'validado_por',                'franco',
  'source_event',                'test_T-CR-3-confirm'
));
```
Esperado: `{"ok": true, "id_reserva": M, ...}`. El pago pasa a `confirmado` con `validado_por='franco'`.

#### T-CR-4: Verificar copia de campos y actualización de huésped

```sql
-- Verificar que mascotas/detalle/ninos/notas se copiaron de pre_reserva a reserva
SELECT r.mascotas, r.detalle_mascotas, r.ninos, r.notas_reserva
FROM reservas r WHERE r.id_reserva = N;
-- Verificar total_reservas del huésped
SELECT total_reservas, primera_reserva_fecha FROM huespedes WHERE id_huesped = <id_huesped>;
-- Verificar pre_reserva quedó como 'convertida'
SELECT estado FROM pre_reservas WHERE id_pre_reserva = X;
```
Esperado:
- Reserva tiene los 4 campos operativos copiados de la pre-reserva.
- `total_reservas` incrementado en 1.
- `primera_reserva_fecha` seteada (si era NULL).
- `pre_reservas.estado = 'convertida'`.

---

### 6.5 Tests de bloqueo

#### T-B-1: Bloqueo específico sin conflicto

```sql
SELECT crear_bloqueo(jsonb_build_object(
  'id_cabana',     3,                                  -- Arrebol
  'fecha_desde',   '2026-11-01',
  'fecha_hasta',   '2026-11-05',
  'motivo',        'mantenimiento',
  'descripcion',   'Test bloqueo específico',
  'creado_por',    'test_admin',
  'source_event',  'test_T-B-1'
));
```
Esperado: `{"ok": true, "id_bloqueo": N, "tipo_bloqueo": "cabana_especifica"}`.

#### T-B-2: Bloqueo específico sobre reserva existente → conflicto

```sql
-- Asumiendo hay una reserva confirmada en cabaña 1 del 2026-09-01 al 2026-09-03 (de T-CR-2)
SELECT crear_bloqueo(jsonb_build_object(
  'id_cabana',     1,
  'fecha_desde',   '2026-09-02',
  'fecha_hasta',   '2026-09-04',
  'motivo',        'mantenimiento',
  'creado_por',    'test_admin',
  'source_event',  'test_T-B-2'
));
```
Esperado: `{"ok": false, "error": "conflicto_con_reserva", "reservas_en_conflicto": [N]}`.

#### T-B-3: Bloqueo específico sobre pre-reserva vigente → conflicto

```sql
-- Crear pre-reserva activa en cabaña 4 (Guatemala), después intentar bloquear
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'Pre-blq', 'telefono', '+5491200000003'),
  'id_cabana',           4,
  'fecha_in',            '2026-12-01',
  'fecha_out',           '2026-12-03',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-B-3-setup'
));
SELECT crear_bloqueo(jsonb_build_object(
  'id_cabana',     4,
  'fecha_desde',   '2026-12-02',
  'fecha_hasta',   '2026-12-04',
  'motivo',        'mantenimiento',
  'creado_por',    'test_admin',
  'source_event',  'test_T-B-3'
));
```
Esperado: `{"ok": false, "error": "conflicto_con_prereserva", "prereservas_en_conflicto": [...]}`.

#### T-B-4: Bloqueo total con reserva existente → conflicto

```sql
SELECT crear_bloqueo(jsonb_build_object(
  'id_cabana',     null,                                -- bloqueo total
  'fecha_desde',   '2026-09-01',
  'fecha_hasta',   '2026-09-05',
  'motivo',        'tormenta',
  'creado_por',    'test_admin',
  'source_event',  'test_T-B-4'
));
```
Esperado: `{"ok": false, "error": "conflicto_con_reserva", ...}` (porque hay reserva en cabaña 1 del 2026-09-01 al 2026-09-03).

#### T-B-5: Bloqueo total con pre-reserva vigente → conflicto

(Si T-B-3 dejó pre-reserva activa en cabaña 4.)
```sql
SELECT crear_bloqueo(jsonb_build_object(
  'id_cabana',     null,
  'fecha_desde',   '2026-12-01',
  'fecha_hasta',   '2026-12-04',
  'motivo',        'uso_propio',
  'creado_por',    'test_admin',
  'source_event',  'test_T-B-5'
));
```
Esperado: `{"ok": false, "error": "conflicto_con_prereserva", ...}`.

#### T-B-6: Bloqueo total sin conflicto

```sql
SELECT crear_bloqueo(jsonb_build_object(
  'id_cabana',     null,
  'fecha_desde',   '2027-06-01',
  'fecha_hasta',   '2027-06-10',
  'motivo',        'mantenimiento',
  'descripcion',   'Mantenimiento anual',
  'creado_por',    'test_admin',
  'source_event',  'test_T-B-6'
));
```
Esperado: `{"ok": true, "tipo_bloqueo": "total"}`.

#### T-B-7: Doble bloqueo total paralelo

Ver test de concurrencia C-3 en Sección 6.8.

---

### 6.6 Tests de pagos

#### T-P-1: Pago sobre pre-reserva activa

```sql
-- Crear pre-reserva nueva
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'P1', 'telefono', '+5491300000001'),
  'id_cabana',           5,                              -- Tokio
  'fecha_in',            '2027-01-10',
  'fecha_out',           '2027-01-12',
  'personas',            2,
  'monto_total',         80000,
  'monto_sena',          40000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_T-P-1-setup'
));
-- Registrar pago exacto confirmado
SELECT registrar_pago(jsonb_build_object(
  'id_pre_reserva',   <id>,
  'tipo',             'sena',
  'medio_pago',       'transferencia_mp',
  'monto_esperado',   40000,
  'monto_recibido',   40000,
  'estado_inicial',   'confirmado',
  'validado_por',     'test_admin',
  'source_event',     'test_T-P-1'
));
```
Esperado: `{"ok": true, "id_pago": N, "estado": "confirmado"}`.

#### T-P-2: Pago parcial → en_revision

```sql
SELECT registrar_pago(jsonb_build_object(
  'id_pre_reserva',   <id_otra>,
  'tipo',             'sena',
  'medio_pago',       'transferencia_bancaria',
  'monto_esperado',   50000,
  'monto_recibido',   30000,
  'source_event',     'test_T-P-2'
));
```
Esperado: `{"ok": true, "id_pago": N, "estado": "en_revision"}`. La pre-reserva pasa a `pago_en_revision`.

#### T-P-3: Sobrepago → en_revision

```sql
SELECT registrar_pago(jsonb_build_object(
  'id_pre_reserva',   <id_otra>,
  'tipo',             'sena',
  'medio_pago',       'transferencia_bancaria',
  'monto_esperado',   50000,
  'monto_recibido',   60000,
  'source_event',     'test_T-P-3'
));
```
Esperado: `{"ok": true, "estado": "en_revision"}`.

#### T-P-4: Pago sobre pre-reserva vencida → warning

```sql
-- Forzar vencimiento de una pre-reserva
UPDATE pre_reservas SET expira_en = NOW() - INTERVAL '1 hour', estado = 'pendiente_pago'
WHERE id_pre_reserva = <id>;
SELECT expirar_prereservas_vencidas();
-- Ahora la pre-reserva está 'vencida'. Registrar pago.
SELECT registrar_pago(jsonb_build_object(
  'id_pre_reserva',   <id>,
  'tipo',             'sena',
  'medio_pago',       'transferencia_bancaria',
  'monto_esperado',   50000,
  'monto_recibido',   50000,
  'estado_inicial',   'confirmado',                    -- el payload pide confirmado
  'source_event',     'test_T-P-4'
));
```
Esperado:
```json
{
  "ok": true,
  "id_pago": N,
  "estado": "en_revision",                            // forzado
  "warning": "prereserva_no_activa",
  "prereserva_estado": "vencida"
}
```

#### T-P-5: Pago directo sobre reserva

```sql
-- Pagar saldo de una reserva confirmada (sin pre-reserva referenciada)
SELECT registrar_pago(jsonb_build_object(
  'id_reserva',       <id_reserva>,
  'tipo',             'saldo',
  'medio_pago',       'efectivo',
  'monto_esperado',   50000,
  'monto_recibido',   50000,
  'estado_inicial',   'confirmado',
  'validado_por',     'test_admin',
  'source_event',     'test_T-P-5'
));
```
Esperado: `{"ok": true, "id_pago": N, "estado": "confirmado"}`.

---

### 6.7 Tests de expiración

#### T-E-1: Pre-reserva pendiente_pago vencida → vencida

Cubierto en T-D-2 y T-P-4 (forzar `expira_en` al pasado y llamar `expirar_prereservas_vencidas`).

#### T-E-2: Pre-reserva en `pago_en_revision` no vence

```sql
-- Crear pre-reserva, registrar pago parcial (la pone en pago_en_revision)
-- Forzar expira_en al pasado
UPDATE pre_reservas SET expira_en = NOW() - INTERVAL '1 hour'
WHERE id_pre_reserva = <id> AND estado = 'pago_en_revision';
-- Llamar función
SELECT expirar_prereservas_vencidas();
-- Verificar estado
SELECT estado FROM pre_reservas WHERE id_pre_reserva = <id>;
```
Esperado: `pago_en_revision` (la función solo afecta `pendiente_pago`).

#### T-E-3: Pre-reserva vigente no vence

```sql
-- Pre-reserva normal con expira_en > NOW()
SELECT expirar_prereservas_vencidas();
SELECT estado FROM pre_reservas WHERE id_pre_reserva = <id_vigente>;
```
Esperado: `pendiente_pago`. No fue afectada.

---

### 6.8 Tests de concurrencia (PATRÓN OBLIGATORIO)

**Cómo se ejecutan los tests de concurrencia en Supabase:**

Abrir **dos pestañas del SQL Editor** en el mismo proyecto. Cada pestaña es una conexión independiente. Usar `BEGIN; ... COMMIT;` para mantener transacciones abiertas, y `pg_sleep(N)` para forzar el ordenamiento temporal entre pestañas.

**Resultado clave a observar:** la segunda pestaña debe **esperar** (quedarse "Running") hasta que la primera haga COMMIT. Después de COMMIT de la primera, la segunda ejecuta y debe ver los efectos de la primera.

---

#### C-1: `crear_prereserva` paralelo a `crear_bloqueo` total

**Setup:** sin pre-reservas ni bloqueos sobre el rango `2027-03-01` a `2027-03-05`.

**Pestaña A (lanzar primero):**
```sql
BEGIN;
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'Conc A', 'telefono', '+5491400000001'),
  'id_cabana',           1,
  'fecha_in',            '2027-03-01',
  'fecha_out',           '2027-03-03',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_C-1-A'
));
SELECT pg_sleep(8);
COMMIT;
```

**Pestaña B (lanzar a los ~2 segundos de A):**
```sql
BEGIN;
SELECT crear_bloqueo(jsonb_build_object(
  'id_cabana',     null,                              -- bloqueo total
  'fecha_desde',   '2027-03-01',
  'fecha_hasta',   '2027-03-05',
  'motivo',        'tormenta',
  'creado_por',    'test_admin',
  'source_event',  'test_C-1-B'
));
COMMIT;
```

**Resultado esperado:**
- Pestaña A: ejecuta INSERT, duerme 8 segundos, hace COMMIT. Total ~8s.
- Pestaña B: **se queda esperando** (probablemente "Running" en la UI) hasta que A haga COMMIT. Después corre y devuelve `{"ok": false, "error": "conflicto_con_prereserva", ...}` (porque ya existe la pre-reserva de A).

**Si esto NO pasa:** los locks no están serializando. **Frenar.**

---

#### C-2: `cancelar_prereserva` paralelo a `crear_bloqueo` total

**Setup:** crear pre-reserva activa para cabaña 2, rango `2027-04-01` a `2027-04-03`. Anotar `id_pre_reserva`.

**Pestaña A:**
```sql
BEGIN;
SELECT cancelar_prereserva(jsonb_build_object(
  'id_pre_reserva', <id>,
  'motivo',         'cliente',
  'source_event',   'test_C-2-A'
));
SELECT pg_sleep(8);
COMMIT;
```

**Pestaña B (lanzar a los ~2s):**
```sql
BEGIN;
SELECT crear_bloqueo(jsonb_build_object(
  'id_cabana',     null,
  'fecha_desde',   '2027-04-01',
  'fecha_hasta',   '2027-04-05',
  'motivo',        'uso_propio',
  'creado_por',    'test_admin',
  'source_event',  'test_C-2-B'
));
COMMIT;
```

**Resultado esperado:**
- Pestaña A: ejecuta UPDATE (cancelación), duerme 8s, COMMIT.
- Pestaña B: espera. Después de COMMIT de A, ejecuta. La pre-reserva ya está cancelada, así que **NO** debe aparecer como conflicto. B devuelve `{"ok": true, "tipo_bloqueo": "total"}`.

**Si B devuelve `conflicto_con_prereserva` cuando A ya canceló:** falso positivo, los locks no están sincronizando bien.

---

#### C-3: `confirmar_reserva` paralelo a `cancelar_prereserva` (test crítico v1.5)

**Setup:** crear pre-reserva con pago confirmado asociado, para cabaña 3.

**Pestaña A:**
```sql
BEGIN;
SELECT confirmar_reserva(jsonb_build_object(
  'id_pre_reserva', <id>,
  'source_event',   'test_C-3-A'
));
SELECT pg_sleep(8);
COMMIT;
```

**Pestaña B (lanzar a los ~2s):**
```sql
BEGIN;
SELECT cancelar_prereserva(jsonb_build_object(
  'id_pre_reserva', <id>,
  'motivo',         'cliente',
  'source_event',   'test_C-3-B'
));
COMMIT;
```

**Resultado esperado:**
- A: confirma, duerme, COMMIT.
- B: **espera** a que A termine. Después de COMMIT de A, B ejecuta y devuelve `{"ok": false, "error": "estado_no_cancelable", "estado_actual": "convertida"}` (porque A ya convirtió la pre-reserva).
- **NO debe haber error `40P01` (deadlock_detected)** en ninguna pestaña.

**Si aparece deadlock_detected:** la corrección de v1.5 (lock global antes de FOR UPDATE) no está funcionando. **Frenar.** Revisar Bloque 14.

---

#### C-4: Doble `crear_prereserva` con misma `idempotency_key`

**Setup:** ninguna pre-reserva con key `'test-conc-001'`.

**Pestaña A:**
```sql
BEGIN;
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'Idem A', 'telefono', '+5491500000001'),
  'id_cabana',           1,
  'fecha_in',            '2027-05-01',
  'fecha_out',           '2027-05-03',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_C-4-A',
  'idempotency_key',     'test-conc-001'
));
SELECT pg_sleep(8);
COMMIT;
```

**Pestaña B (lanzar a los ~2s):**
```sql
BEGIN;
SELECT crear_prereserva(jsonb_build_object(
  'huesped',             jsonb_build_object('nombre', 'Idem B', 'telefono', '+5491500000002'),
  'id_cabana',           1,
  'fecha_in',            '2027-05-01',
  'fecha_out',           '2027-05-03',
  'personas',            2,
  'monto_total',         100000,
  'monto_sena',          50000,
  'canal_origen',        'manual',
  'canal_pago_esperado', 'transferencia_mp',
  'source_event',        'test_C-4-B',
  'idempotency_key',     'test-conc-001'
));
COMMIT;
```

**Resultado esperado:**
- A: crea la pre-reserva. `recovery_path: null` (creación normal).
- B: espera. Después de COMMIT de A, B detecta la pre-reserva con misma key:
  - Si el detector pre-lock la ve → `recovery_path: 'pre_lock'`.
  - Si la ve recién post-lock → `recovery_path: 'post_lock'`.
  - Si se cuela hasta el INSERT → `recovery_path: 'unique_violation'`.
- En cualquiera de los 3 casos, B devuelve `id_pre_reserva` igual al de A.

**Si B intenta crear una pre-reserva NUEVA (id distinto):** la idempotencia no está funcionando. **Frenar.**

---

### Resumen de tests obligatorios

| Categoría | Tests | Total |
|---|---|---|
| Huéspedes | T-H-1 a T-H-5 | 5 |
| Pre-reserva | T-PR-1 a T-PR-7 | 7 |
| Disponibilidad | T-D-1, T-D-2 (T-D-3 a T-D-5 cubiertos en Bloqueos) | 2 |
| Confirmación | T-CR-1 a T-CR-4 | 4 |
| Bloqueos | T-B-1 a T-B-6 (T-B-7 en Concurrencia) | 6 |
| Pagos | T-P-1 a T-P-5 | 5 |
| Expiración | T-E-1 a T-E-3 | 3 |
| Concurrencia | C-1 a C-4 | 4 |
| **TOTAL** | | **36** |

**Criterio para cerrar Fase 4:** los 36 tests pasan.

---

## 7. ROLLBACK

### 7.1 Principio rector

> **No usar `DROP SCHEMA CASCADE` ni equivalentes destructivos sin entender el estado actual.**

El rollback debe ser proporcional al problema. Cada bloque del documento v1.6.1 incluye su propio rollback documentado. Usar ese primero.

### 7.2 Rollback por bloque (incluido en v1.6.1)

Cada bloque del documento SQL tiene una sección "**Rollback:**" con el SQL exacto para revertir. Ejemplos:

- Bloque 1: `DROP EXTENSION IF EXISTS pg_cron; DROP EXTENSION IF EXISTS btree_gist;`
- Bloque 2: `DROP TYPE IF EXISTS ...` (4 tipos).
- Bloque 6: `DROP TABLE IF EXISTS gastos; ... DROP TABLE IF EXISTS pre_reservas;` (en orden inverso de creación).

**Cuándo usar el rollback de un bloque puntual:**
- El bloque falló a la mitad y dejó objetos parciales.
- Se descubre un error en el SQL que requiere corregir y re-ejecutar.

### 7.3 Cuándo NO usar rollback ciego

- Si el bloque ejecutó OK y la verificación pasó: **no usar rollback** "por las dudas".
- Si ya hay datos de prueba creados: **cuidado** con `DROP TABLE` — pierde todo lo testeado.
- Si estamos en Fase 4+ y aparece un problema en una función: rollback de UNA función, no de todo el schema.

### 7.4 Diferencia DEV vacío vs DEV con datos

**DEV vacío (todavía no se cargó seed ni se hicieron tests):**
- Si falla algo en Fase 1 o 2 y es complicado limpiar manualmente: **es válido resetear el proyecto** (en Supabase Dashboard → Settings → Reset Project, o crear uno nuevo).
- Costo: bajo. Pérdida: ninguna (no había datos).

**DEV con seed cargado y tests parciales:**
- **NO resetear el proyecto.** Hacer rollback puntual del bloque afectado.
- Si hay que volver a hacer el seed después de un rollback, re-ejecutar Bloque 21.

**DEV con datos de pruebas avanzadas (Fase 4 en curso):**
- Rollback solo de la función con problema.
- Si la función tiene muchos llamados de prueba registrados en `log_cambios`, evaluar si limpiar la tabla de logs o dejarla.

### 7.5 Rollback completo (último recurso)

Si por algún motivo grave hay que tirar todo abajo en DEV:

**Opción A — Reset del proyecto en Supabase Dashboard.**
- Settings → Database → Reset.
- Pierde TODO. Volver a empezar desde Fase 0.

**Opción B — DROP secuencial respetando dependencias.**

Orden inverso al de creación:
```sql
-- 1. pg_cron (desactivar jobs antes de tirar)
SELECT cron.unschedule('expirar_prereservas');
SELECT cron.unschedule('cleanup_cron_history');

-- 2. Vistas (no tienen dependencias entre sí salvo vista_disponibilidad → función)
DROP VIEW IF EXISTS vista_limpieza_semana;
DROP VIEW IF EXISTS vista_calendario_semanal;
DROP VIEW IF EXISTS vista_ocupacion;
DROP VIEW IF EXISTS vista_prereservas_activas;
DROP VIEW IF EXISTS vista_calendario;
DROP VIEW IF EXISTS vista_disponibilidad;

-- 3. Triggers + funciones
-- (Usar los DROP del Bloque 19, después los DROP de cada función Bloques 9-18)

-- 4. Constraints EXCLUDE
ALTER TABLE bloqueos DROP CONSTRAINT IF EXISTS exc_bloqueos_no_overlap;
ALTER TABLE reservas DROP CONSTRAINT IF EXISTS exc_reservas_no_overlap;

-- 5. Tabla auditoría
DROP TABLE IF EXISTS log_cambios;

-- 6. Tablas transaccionales (orden inverso por FK)
DROP TABLE IF EXISTS gastos;
DROP TABLE IF EXISTS bloqueos;
DROP TABLE IF EXISTS pagos;
DROP TABLE IF EXISTS reservas;
DROP TABLE IF EXISTS pre_reservas;

-- 7. Tablas dependientes nivel 1
DROP TABLE IF EXISTS overrides_operativos;
DROP TABLE IF EXISTS consultas;

-- 8. Tablas de configuración
DROP TABLE IF EXISTS descuentos;
DROP TABLE IF EXISTS paquetes_evento;
DROP TABLE IF EXISTS eventos_especiales;
DROP TABLE IF EXISTS configuracion_general;

-- 9. Tablas catálogo
DROP TABLE IF EXISTS plantillas_mensajes;
DROP TABLE IF EXISTS cuentas_cobro;
DROP TABLE IF EXISTS socios;
DROP TABLE IF EXISTS temporadas;
DROP TABLE IF EXISTS tarifas;
DROP TABLE IF EXISTS feriados;
DROP TABLE IF EXISTS huespedes;
DROP TABLE IF EXISTS cabanas;

-- 10. Enums
DROP TYPE IF EXISTS nivel_log_enum;
DROP TYPE IF EXISTS estado_pago_enum;
DROP TYPE IF EXISTS estado_reserva_enum;
DROP TYPE IF EXISTS estado_prereserva_enum;

-- 11. Extensiones (opcional, normalmente no se desinstalan)
-- DROP EXTENSION IF EXISTS pg_cron;
-- DROP EXTENSION IF EXISTS btree_gist;
```

**Recomendación general:** preferir Reset del proyecto si DEV está casi vacío. Es más limpio.

### 7.6 No hacer rollback si...

- El bloque ejecutó bien y la verificación pasó.
- El "problema" es solo un test que no entendiste bien.
- Querés probar otra cosa rápido — mejor abrir otro proyecto temporal.

---

## 8. CRITERIOS DE ÉXITO DE 6B EJECUCIÓN DEV

DEV está listo como base de datos operativa cuando se cumplen todos estos puntos:

### 8.1 Infraestructura

- [ ] `btree_gist` habilitada.
- [ ] `pg_cron` habilitada.
- [ ] 20 tablas creadas.
- [ ] 4 enums creados.
- [ ] 2 constraints EXCLUDE activos.
- [ ] 6 vistas operativas creadas y responden.

### 8.2 Funciones

- [ ] 11 funciones críticas compilan (sin errores de sintaxis).
- [ ] `normalizar_telefono` pasa los 6 casos de test.
- [ ] `upsert_huesped` pasa los 3 tests funcionales.
- [ ] `crear_prereserva` crea pre-reservas correctamente.
- [ ] `confirmar_reserva` confirma reservas en camino estricto y combinado.
- [ ] `cancelar_prereserva` cancela y devuelve pagos asociados.
- [ ] `crear_bloqueo` rechaza conflictos con reservas Y pre-reservas vigentes Y bloqueos solapados.
- [ ] `registrar_pago` registra con estado correcto + warning si pre-reserva está terminal.
- [ ] `expirar_prereservas_vencidas` marca correctamente.

### 8.3 Triggers y cron

- [ ] 13+ triggers activos (`updated_at`, log de estado, normalización teléfono).
- [ ] 2 jobs de `pg_cron` activos.

### 8.4 Seed

- [ ] 5 cabañas con capacidades correctas (3/5 grandes, 2/4 chicas).
- [ ] 3 socios (incluyendo `Socio 3` placeholder documentado).
- [ ] 9 claves de `configuracion_general`.
- [ ] 1 cuenta de cobro placeholder.
- [ ] 1 temporada baseline.
- [ ] 1 plantilla de mensaje.

### 8.5 Tests

- [ ] Los 36 tests obligatorios de Sección 6 pasan.
- [ ] Tests de concurrencia C-1 a C-4 ejecutados manualmente y resultado coincide con esperado.
- [ ] No aparecen errores crudos (`SQLSTATE` directo) en casos esperables.
- [ ] No se observa double booking en ningún escenario testeado.

### 8.6 Documentación

- [ ] Bitácora de ejecución llena con fechas, observaciones y resoluciones.
- [ ] Cualquier desviación del plan documentada.
- [ ] Cualquier parche al SQL documentado mediante nueva versión del schema antes de continuar.

---

## 9. CRITERIOS DE FRENO

Frenar inmediatamente si:

### 9.1 Errores de infraestructura

- `btree_gist` no se puede habilitar (debería estar disponible siempre — investigar).
- `pg_cron` no se puede habilitar (probable: requiere habilitar primero en Dashboard).
- Cualquier `CREATE TABLE` falla con error.
- Cualquier constraint CHECK no se acepta.
- Cualquier constraint EXCLUDE no se crea (probable: `btree_gist` no está bien).

### 9.2 Funciones

- Cualquier función no compila.
- Cualquier función devuelve error crudo (no JSONB controlado) en un caso esperable.
- Una función crítica desvía del contrato documentado (ej: `crear_prereserva` no devuelve `recovery_path`).

### 9.3 Lógica de negocio

- Test de doble booking falla (dos reservas confirmadas se crean en el mismo rango).
- Test de idempotencia falla (`crear_prereserva` con misma key crea pre-reservas distintas).
- `confirmar_reserva` genera reserva duplicada.
- `registrar_pago` sobre pre-reserva vencida/cancelada NO emite warning ni fuerza `en_revision`.
- `crear_bloqueo` permite pisar reservas o pre-reservas vigentes.

### 9.4 Concurrencia

- Test C-3 (`confirmar_reserva` paralelo a `cancelar_prereserva`) genera deadlock `40P01`.
- Cualquier test de concurrencia C-1 a C-4 produce resultado inesperado.

### 9.5 Cron y triggers

- `pg_cron` no logra crear el job.
- Triggers de `updated_at` no actualizan al hacer UPDATE.
- Triggers de log de estado no escriben en `log_cambios`.

### 9.6 Inconsistencias menores pero sospechosas

- Conteos del seed difieren del esperado.
- Capacidades de cabañas erradas.
- Funciones presentes pero ausentes de `pg_proc` (raro pero posible si el `CREATE` quedó incompleto).

**Política general:** si dudás, frená. Investigar es barato; corregir un problema productivo después es caro.

---

## 10. QUÉ NO FORMA PARTE DE ESTE PLAN

Para que quede explícito, los siguientes ítems quedan **fuera del alcance** de la ejecución 6B:

- **Reescritura completa de workflows n8n.** Se hace después, con `6B_REESCRITURA_WORKFLOWS.md`.
- **Frontend web público.** Pertenece a Etapa 7 o posterior.
- **Integración real con MercadoPago.** Solo se simula con `medio_pago='mp_link'` y `proveedor='mercadopago'` en pagos manuales.
- **Integración real con WhatsApp.** Solo se simulan envíos con plantillas.
- **Integración real con Instagram DMs.**
- **RLS (Row Level Security) completo.** Documentado como principio en v1.6.1; se implementa cuando exista Supabase Auth.
- **Supabase Auth.** No se configura ahora.
- **Contabilidad completa.** Documentada como contemplada futura (D32) pero no implementada.
- **Migración productiva de Sheets.** Pertenece a etapa posterior, con plan propio.
- **Datos reales de huéspedes.** En DEV solo van datos de prueba. Si por error se cargan datos reales: **borrarlos antes de cualquier commit a repo**.
- **Claves o secrets reales en GitHub.** Nunca, en ninguna fase.
- **Producción.** No tocar hasta tener DEV cerrado y TEST cerrado (otro proyecto Supabase) y workflows n8n reescritos.

---

## 11. PRÓXIMO PASO DESPUÉS DE APROBAR ESTE PLAN

Una vez aprobado este documento:

1. **Ejecutar Fase 0** (preparación, no ejecuta SQL).
2. **Ejecutar Bloque 1** en Supabase DEV.
3. **Correr verificación post-ejecución** del Bloque 1.
4. **Avanzar bloque por bloque** siguiendo este plan, con bitácora.
5. **Completar Fase 4** (tests).
6. **Cierre formal de Fase 5.**
7. **Recién después:** generar `Docs/Implementacion/6B_REESCRITURA_WORKFLOWS.md` para empezar a adaptar n8n a la nueva base.

**Importante:** este orden es secuencial. No empezar la reescritura de workflows n8n hasta tener DEV cerrado. Hacer las dos cosas en paralelo introduce riesgos de debugging que no compensan.

---

**FIN DEL DOCUMENTO — `6B_PLAN_FASES.md v1.1`**

**Trazabilidad:**
- v1.0 — Primera propuesta de plan de fases (2026-05-22).
- v1.1 — Sanitización para GitHub: Project ID y Project URL reales reemplazados por placeholders. Nota de sanitización agregada. Cero cambios operativos.

**Estado:** Propuesta para revisión — NO EJECUTAR TODAVÍA.

**Estado para GitHub:** Sanitizado. Los placeholders `__SUPABASE_PROJECT_ID_DEV__`, `__SUPABASE_PROJECT_URL_DEV__`, `__SUPABASE_DB_PASSWORD__`, `__SUPABASE_CONNECTION_STRING__`, `__SUPABASE_ANON_KEY__` y `__SUPABASE_SERVICE_ROLE_KEY__` deben reemplazarse localmente al momento de ejecutar y nunca commitearse con valores reales.
