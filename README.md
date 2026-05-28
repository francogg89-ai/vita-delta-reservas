# Vita Delta Reservas

Sistema integral de gestión y automatización de reservas para el complejo de cabañas **Vita Delta**.

El proyecto centraliza disponibilidad, pre-reservas, reservas, pagos, bloqueos administrativos, operación interna y futura comunicación con huéspedes sobre una arquitectura trazable, automatizable y escalable.

---

## TL;DR

- **Fuente de verdad:** Supabase / PostgreSQL.
- **Orquestación:** n8n.
- **Entornos:** DEV operativo + **TEST levantado, paritario, operativo y validado funcionalmente (7B + 7C cerradas)**. Schema canónico `v1.7.3`.
- **Workflows vigentes:** 8 (W0–W7) en `Workflows/n8n/Supabase/`, validados contra DEV en 6C, contra TEST en 7B (cadena end-to-end W2→W3→W4) y en 7C (validación funcional ampliada de caminos no-felices, 54 verificaciones conformes).
- **Estado:** no productivo. Próximos pasos posibles → diseño del bloque de reset de TEST, endurecimiento de DEV, diseño de OPS, o integraciones con consumidores reales sobre TEST.

---

## Estado actual del proyecto

**Estado general:** backend Supabase DEV implementado y operativo + entorno TEST levantado como proyecto Supabase independiente, paritario y aislado de DEV (Etapa 7B cerrada) y validado funcionalmente de punta a punta en sus caminos no-felices (Etapa 7C cerrada). Workflows n8n contra DEV y contra TEST validados, hardening pre-producción cerrado, correcciones pre-TEST/pre-OPS aplicadas (7A), documentación canónica actualizada a `v1.7.3`.

El proyecto ya superó la etapa de Google Sheets como backend operativo. La fuente de verdad actual es **Supabase / PostgreSQL**.

### Etapas cerradas

| Etapa | Descripción                                       | Estado                  |
| ----- | ------------------------------------------------- | ----------------------- |
| 1     | Arquitectura base                                 | ✅ Cerrada              |
| 2     | Motor de disponibilidad                           | ✅ Cerrada              |
| 3     | Motor de precios                                  | ✅ Cerrada              |
| 4A    | Motor de reservas determinístico                  | ✅ Cerrada              |
| 4B    | Bot conversacional con IA                         | ✅ Cerrada a nivel diseño |
| 5A    | Modelo de datos real inicial                      | ✅ Cerrada              |
| 5B    | Implementación vertical mínima                    | ✅ Cerrada              |
| 6A    | Decisión de migración a base relacional           | ✅ Cerrada              |
| 6B    | Migración a Supabase / PostgreSQL DEV             | ✅ Cerrada              |
| 6C    | Reescritura de workflows n8n contra Supabase DEV  | ✅ Cerrada              |
| 6D    | Hardening pre-producción + cierre documental      | ✅ Cerrada              |
| 7A    | Correcciones pre-TEST / pre-OPS                   | ✅ Cerrada              |
| 7B    | Levantamiento del entorno TEST                    | ✅ Cerrada              |
| 7C    | Validación funcional ampliada sobre TEST          | ✅ Cerrada              |

---

## Arquitectura vigente

La arquitectura vigente se organiza en cuatro capas:

```text
Huésped / operador
        ↓
Canales futuros: WhatsApp, Instagram, web, MercadoPago
        ↓
n8n — orquestación operativa
        ↓
Supabase / PostgreSQL — fuente de verdad
        ↓
Vistas, funciones SQL, triggers, logs y auditoría
```

### Fuente de verdad

Supabase / PostgreSQL es la fuente de verdad del sistema. Viven ahí:

- cabañas
- huéspedes
- pre-reservas
- reservas
- pagos
- bloqueos
- tarifas
- configuración general
- eventos especiales
- logs de cambios
- funciones SQL
- vistas operativas
- triggers
- jobs programados con `pg_cron`

### Orquestación

n8n es el orquestador operativo. Los workflows reciben eventos, arman payloads JSONB, llaman funciones SQL, procesan respuestas y, en el futuro, dispararán comunicaciones o integraciones externas.

### IA

La IA queda como capa conversacional futura. Puede conversar, interpretar intención, ordenar datos y guiar al huésped, pero **no decide disponibilidad, no confirma pagos y no escribe reservas directamente**. Las decisiones críticas viven en PostgreSQL y en workflows determinísticos.

---

## Schema canónico vigente

El schema canónico vigente es: `Docs/Implementacion/6B_SCHEMA_SQL.md`

- **Versión vigente:** `v1.7.3`
- Refleja el estado real de DEV post-hardening 6D + correcciones pre-TEST/pre-OPS 7A. **TEST está alineado funcionalmente con la misma versión** (schema reconstruido desde el canónico en 7B, paridad estructural 10/10 vs DEV).

**Backups históricos archivados:**

- `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.2_PRE_PREOPS.md` (estado pre-7A)
- `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md` (estado pre-6D)

Esos backups son históricos y no son fuente canónica vigente.

---

## Backend Supabase DEV

El backend Supabase DEV está implementado y validado. Incluye:

- schema PostgreSQL completo
- funciones write críticas
- funciones read
- vistas operativas
- triggers de auditoría
- constraints estructurales
- jobs con `pg_cron`
- seed operativo mínimo
- hardening defensivo en funciones write
- validación de concurrencia real

### Funciones principales

| Función                            | Rol                                       |
| ---------------------------------- | ----------------------------------------- |
| `obtener_disponibilidad_rango()`   | Consulta de disponibilidad                |
| `crear_prereserva()`               | Puerta única para crear pre-reservas      |
| `registrar_pago()`                 | Registro de pagos                         |
| `confirmar_reserva()`              | Confirmación de reservas                  |
| `cancelar_prereserva()`            | Cancelación de pre-reservas               |
| `crear_bloqueo()`                  | Bloqueos administrativos                  |
| `expirar_prereservas_vencidas()`   | Expiración automática de pre-reservas     |
| `upsert_huesped()`                 | Alta o actualización de huéspedes         |
| `validar_disponibilidad()`         | Validación interna de disponibilidad      |

---

## Workflows n8n vigentes

Ubicación: `Workflows/n8n/Supabase/`
(Si el sistema de archivos del repo usa minúsculas, la ruta equivalente es `Workflows/n8n/supabase/`.)

La Etapa 6C cerró con:

- 8 workflows Supabase W0–W7
- 40 tests funcionales aprobados
- 3 verificaciones cruzadas end-to-end
- templates sanitizados para versionado
- wrapper de respuesta unificado

| Workflow                                       | Rol                                  |
| ---------------------------------------------- | ------------------------------------ |
| `vita_w00_smoke_test_supabase`                 | Smoke test de conexión               |
| `vita_w01_consultar_disponibilidad_supabase`   | Consulta disponibilidad              |
| `vita_w02_crear_prereserva_supabase`           | Crea pre-reserva                     |
| `vita_w03_registrar_pago_supabase`             | Registra pago                        |
| `vita_w04_confirmar_reserva_supabase`          | Confirma reserva                     |
| `vita_w05_cancelar_prereserva_supabase`        | Cancela pre-reserva                  |
| `vita_w06_crear_bloqueo_supabase`              | Crea bloqueo administrativo          |
| `vita_w07_vistas_operativas_supabase`          | Consulta vistas operativas read-only |

---

## Hardening pre-producción cerrado

La Etapa 6D cerró formalmente el hardening pre-producción. Incluyó tres frentes:

### H1–H6-bis · Hardening estructural

- extracts defensivos en 5 funciones write críticas
- fix de rango en `vista_ocupacion`
- fix cosmético de `TRIM` en vistas con concatenación nombre + apellido

### H7 · Validación de concurrencia

- 6/6 tests aprobados
- 0 deadlocks `40P01`
- 0 races observados
- 0 doble booking
- baseline final restaurado

### H8 · Cierre documental

- bump documental del schema canónico a `v1.7.2` (estado de DEV al cierre de 6D)
- backup histórico `v1.7.1`
- actualización de archivos satélite
- creación de `6D_CIERRE.md`

**Nota:** el schema canónico fue bumpeado posteriormente a `v1.7.3` en Etapa 7A para reflejar el horizonte configurable, la alineación de tipo `ninos` y el contrato de `canal_pago_esperado`. Ver `7A_CIERRE.md`.

**Documento de cierre:** `Docs/Bitacora/6D_CIERRE.md`

---

## Correcciones pre-TEST / pre-OPS (Etapa 7A)

La Etapa 7A resolvió 3 pendientes livianos documentados antes de levantar TEST:

- **Horizonte de `vista_disponibilidad`/`vista_calendario` configurable** (de hardcoded 60 a `configuracion_general.horizonte_disponibilidad_dias` con default 120). D-7A-03.
- **Alineación de tipo `ninos`** entre función y tablas (variable `v_ninos` ahora TEXT, coherente con las columnas). D-7A-02.
- **Contrato de `canal_pago_esperado`** en validación manual de `crear_prereserva` (rebota `payload_invalido` para ausente/vacío/whitespace). D-7A-01.

Schema canónico bumpeado a `v1.7.3`. DEV alineado funcionalmente. 9 tests funcionales + 4 estructurales aprobados.

**Documento de cierre:** `Docs/Bitacora/7A_CIERRE.md`

---

## Entorno TEST levantado (Etapa 7B)

La Etapa 7B levantó el entorno **TEST** como proyecto Supabase independiente, paritario y aislado de DEV. Cierra el segundo entorno de la estrategia DEV → TEST → OPS → PROD.

**Lo que se construyó:**

- Proyecto Supabase `vita-delta-test` independiente (no clon de DEV; schema reconstruido desde el canónico v1.7.3).
- Paridad estructural demostrada **10/10 vs DEV**: extensiones, enums, tablas (20), vistas (6), funciones (13), triggers (13), EXCLUDE (2), CHECK (38), FK (15), índices únicos (27).
- Seeds mínimos cargados (5 cabañas, 3 socios, 10 claves config, etc.).
- `pg_cron` activo con ejecuciones reales verificadas.
- Permisos Data API normalizados (REVOKE EXECUTE sobre las 13 funciones a `PUBLIC`/`anon`/`authenticated`/`service_role`; modelo cerrado mínimo).
- 8 workflows `__TEST` importados con credencial propia `vita_supabase_test`; smokes happy path 8/8.
- **Cadena transaccional end-to-end W2 → W3 → W4 validada** en TEST.

**IDs de cabaña en TEST:** `1=Bamboo, 2=Madre Selva, 3=Arrebol, 4=Guatemala, 5=Tokio`. **No coinciden con DEV (17-21).** Los IDs no son portables entre ambientes; cada workflow debe usar los del ambiente al que apunta.

**Aislamiento:** TEST quedó separado por credencial propia, workflows `__TEST` distintos, y marcadores de ambiente en `source_event` (`n8n_test_w0X_..._manual`) e `idempotency_key` (`manual_test_...`) que se persisten en tablas. DEV intacto durante toda la etapa.

**Alcance del cierre:** happy paths como evidencia suficiente para el levantamiento. Los casos de error (cabaña inexistente, solapamientos, payloads inválidos, etc.) se ejercitaron luego en la Etapa 7C.

**Documento de cierre:** `Docs/Bitacora/7B_CIERRE.md`

---

## Validación funcional ampliada sobre TEST (Etapa 7C)

La Etapa 7C ejecutó la batería sistemática de **caminos no-felices** de los 8 workflows `__TEST` sobre TEST: los casos de error, edge cases, validaciones defensivas y condiciones de borde que 7B dejó fuera de alcance. Donde 7B demostró que el entorno existe y es paritario, 7C demuestra que se comporta como espera bajo casos negativos.

**Resultado:**

- **54 verificaciones conformes:** 48 casos funcionales (Grupo A) + 6 verificaciones transversales (TR-01 persistencia de `source_event`, TR-02 doble logging).
- **0 fallos inesperados.**
- **2 comportamientos observados/documentados** (ninguno es defecto): rango invertido en `obtener_disponibilidad_rango` devuelve set vacío (`ok:true, 0 días`), no error; y el bloqueo id 2 generado en A-W6-06 como **mutación no planificada pero válida y comprendida** (el sistema actuó correctamente ante un payload válido).
- **Idempotencia:** rama `pre_lock` cubierta empíricamente (A-W2-15), sumada a `post_lock` (H7). Resta solo `unique_violation` como cobertura opcional no bloqueante.

**Método:** ejecución manual (Franco edita `Build Input`, ejecuta en n8n contra TEST, pega el output; Claude valida PASS/FAIL contra matriz pre-aprobada). Expected outputs anclados al código SQL real de las funciones, no a supuestos.

**Política de fixtures:** los datos vivos generados (pre-reservas id 3/4, pagos id 2/3, bloqueo id 2, huéspedes id 3/5) se conservan como evidencia (decisión D-7C-01). Cualquier reset de TEST será un bloque separado con SQL aprobado.

**DEV intacto. Schema canónico v1.7.3 sin modificar.** Lecciones L-7C-01 a L-7C-06.

**Documento de cierre:** `Docs/Bitacora/7C_CIERRE.md`

---

## Cómo funciona el sistema

> La IA conversa.
> n8n orquesta.
> PostgreSQL decide y persiste.
> Los humanos auditan.

### Flujo base de reserva

```text
Consulta entrante
  → vita_w01_consultar_disponibilidad_supabase
  → vita_w02_crear_prereserva_supabase
  → vita_w03_registrar_pago_supabase
  → vita_w04_confirmar_reserva_supabase
```

La pre-reserva bloquea disponibilidad temporalmente. La reserva se confirma solo después de validar pago y disponibilidad **bajo locks**.

### Operaciones adicionales

- `vita_w05_cancelar_prereserva_supabase`
- `vita_w06_crear_bloqueo_supabase`
- `vita_w07_vistas_operativas_supabase`

---

## Qué está implementado

Implementado y validado **en DEV**:

- schema PostgreSQL completo
- funciones SQL principales
- vistas operativas
- triggers de auditoría
- `pg_cron` para expiración de pre-reservas
- workflows n8n contra Supabase
- wrapper de respuesta unificado
- validaciones funcionales W0–W7
- hardening pre-producción
- tests de concurrencia H7
- documentación canónica `v1.7.3`
- cierre formal de Etapas 6C, 6D, 7A, 7B y 7C
- entorno TEST paritario, operativo y aislado de DEV
- workflows n8n `__TEST` validados con cadena end-to-end W2→W3→W4
- validación funcional ampliada de TEST (caminos no-felices): 54 verificaciones conformes, 0 fallos inesperados

## Qué no está implementado todavía

Todavía no está implementado o no está productivo:

- webhook real de MercadoPago
- integración real con WhatsApp / Instagram mediante Meta API
- bot conversacional conectado a canales reales
- web pública de reservas conectada al backend
- panel administrativo
- dashboard operativo
- contabilidad automatizada
- RLS final para frontend público
- tarifas reales productivas completas
- feriados productivos definitivos
- entorno PROD

---

## Próximos pasos posibles

Con DEV, TEST, 6D, 7A, 7B y 7C cerradas, las siguientes son **opciones disponibles** a priorizar (orden sugerido):

- **Diseño del bloque de limpieza/reset de TEST:** derivado de D-7C-01 (no-limpieza durante 7C) y de la acumulación de fixtures de 7C. SQL explícito y aprobado, sin `DROP ... CASCADE`. Ver `Pendiente_pre_produccion.md` 6.5.
- **Endurecimiento de permisos en DEV:** aplicar a DEV un modelo equivalente al de TEST (REVOKE EXECUTE a `PUBLIC` sobre las 13 funciones del proyecto). Ver `Pendiente_pre_produccion.md` 1.5.
- **Diseño del entorno OPS:** operación interna real (Vicky, Franco, Rodrigo, Jennifer) sin consumidores externos automáticos.
- **Integraciones con consumidores reales sobre TEST:** webhook MercadoPago, bot conversacional, frontend público — siempre sobre TEST primero antes de cualquier consideración productiva.

No avanzar a OPS/PROD, MercadoPago real, bot o frontend público sin decisión explícita.

---

## Documentos clave

### Estado y cierre

| Documento                                          | Rol                              |
| -------------------------------------------------- | -------------------------------- |
| `Docs/Operacional/ESTADO_ACTUAL_VITA_DELTA.md`     | Estado vigente del proyecto      |
| `Docs/Bitacora/7C_CIERRE.md`                       | Cierre formal de Etapa 7C        |
| `Docs/Bitacora/7B_CIERRE.md`                       | Cierre formal de Etapa 7B        |
| `Docs/Bitacora/7A_CIERRE.md`                       | Cierre formal de Etapa 7A        |
| `Docs/Bitacora/6D_CIERRE.md`                       | Cierre formal de Etapa 6D        |
| `Docs/Implementacion/6C_CIERRE.md`                 | Cierre formal de Etapa 6C        |
| `Docs/Operacional/Pendiente_pre_produccion.md`     | Pendientes antes de TEST/PROD    |
| `Docs/Operacional/DECISIONES_NO_REABRIR.md`        | Decisiones cerradas              |

### Implementación

| Documento                                                   | Rol                              |
| ----------------------------------------------------------- | -------------------------------- |
| `Docs/Implementacion/6B_SCHEMA_SQL.md`                      | Schema canónico vigente          |
| `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`       | Bitácora H1–H7                   |
| `Docs/Bitacora/6C_EJECUCION.md`                             | Bitácora W0–W7                   |
| `Docs/Operacional/Lecciones_Aprendidas.md`                  | Gotchas y lecciones operativas   |

### Arquitectura

| Documento                                                       | Rol                  |
| --------------------------------------------------------------- | -------------------- |
| `Docs/Arquitectura/ARQUITECTURA_ETAPA_1_VITA_DELTA.md`          | Arquitectura base    |
| `Docs/Arquitectura/ARQUITECTURA_ETAPA_2_VITA_DELTA.md`          | Disponibilidad       |
| `Docs/Arquitectura/ARQUITECTURA_ETAPA_3_VITA_DELTA.md`          | Pricing              |
| `Docs/Arquitectura/ARQUITECTURA_ETAPA_4A_MOTOR_RESERVAS.md`     | Motor de reservas    |
| `Docs/Arquitectura/ARQUITECTURA_ETAPA_4B_BOT_CONVERSACIONAL.md` | Bot conversacional   |
| `Docs/Arquitectura/ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md` | Migración Supabase   |

---

## Estructura del repositorio

```text
.
.
├── README.md
├── CLAUDE.md
├── index.html
├── Prototipos/
│   └── prototipo_web_reservas.html
│
├── Docs/
│   ├── Arquitectura/
│   │   ├── ARQUITECTURA_ETAPA_1_VITA_DELTA.md
│   │   ├── ARQUITECTURA_ETAPA_2_VITA_DELTA.md
│   │   ├── ARQUITECTURA_ETAPA_3_VITA_DELTA.md
│   │   ├── ARQUITECTURA_ETAPA_4A_MOTOR_RESERVAS.md
│   │   ├── ARQUITECTURA_ETAPA_4B_BOT_CONVERSACIONAL.md
│   │   ├── ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md
│   │   ├── ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md
│   │   ├── ARQUITECTURA_ETAPA_6A_DECISION_MIGRACION.md
│   │   └── ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md
│   │
│   ├── Implementacion/
│   │   ├── README.md
│   │   ├── 6B_SCHEMA_SQL.md                          # v1.7.3
│   │   ├── 6B_PLAN_FASES.md
│   │   └── Archivados/
│   │       ├── 6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md
│   │       ├── 6B_SCHEMA_SQL_v1.7.2_PRE_PREOPS.md    ← backup pre-7A
│   │       ├── 6B_SCHEMA_SQL_AJUSTES_PENDIENTES_RESUELTOS.md
│   │       ├── PLAN_CIERRE_6B_ALINEACION_v1.7.1.md
│   │       ├── 6C_REESCRITURA_WORKFLOWS_SUPABASE.md
│   │       └── Legacy_Sheets/
│   │           ├── PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
│   │           └── ESTADO_IMPLEMENTACION_ETAPA_5.md
│   │
│   ├── Bitacora/
│   │   ├── 6B_EJECUCION_DEV.md
│   │   ├── 6C_EJECUCION.md
│   │   ├── 6C_CIERRE.md                              ← movido desde Implementacion/
│   │   ├── 6D_CIERRE.md
│   │   ├── 7A_CIERRE.md                              ← cierre Etapa 7A
│   │   ├── 7B_CIERRE.md                              ← cierre Etapa 7B
│   │   ├── 7C_CIERRE.md                              ← cierre Etapa 7C
│   │   ├── 7A_DOCUMENTACION_PENDIENTE.md             ← working note (absorbida, archivable)
│   │   ├── HARDENING_PRE_PRODUCCION_EJECUCION.md
│   │   └── Archivados/
│   │       └── H8_SNAPSHOTS_SCHEMA_v1.7.2_WORKING_NOTES.md
│   │
│   └── Operacional/
│       ├── ESTADO_ACTUAL_VITA_DELTA.md               # actualizado a v1.7.3 / post-7C
│       ├── Pendiente_pre_produccion.md               # 1.1/1.2/1.3 cerrados; 1.4/1.5/1.6, 6.3/6.4/6.5 (post-7C)
│       ├── DECISIONES_NO_REABRIR.md                  # + D-7A/D-7B, D-7C-01, ref L-7C
│       ├── Lecciones_Aprendidas.md                   # + L-7B-01/02/03, L-7C-01 a 06
│       └── Archivados/
│           ├── H8_SNAPSHOTS_SCHEMA_v1.7.2_WORKING_NOTES.md
│           ├── obtener_disponibilidad_rango.md
│           └── vista_disponibilidad.md
│
└── Workflows/
    └── n8n/
        ├── README.md
        ├── *.template.json                 # legacy Sheets, congelados
        └── Supabase/
            ├── README.md
            └── *.template.json             # workflows vigentes contra Supabase
```

> Si la carpeta `Supabase/` está en minúsculas en el repo, mantener el nombre real al commitear.

---

## Sobre `index.html` y prototipos

- **`index.html`** es una presentación visual estática del estado del sistema. Sirve para explicar el proyecto a socios o colaboradores, pero **no** es una web pública de reservas.
- **`Prototipos/prototipo_web_reservas.html`** es un prototipo visual de futura web de reservas. No consulta disponibilidad real, no crea pre-reservas, no registra pagos y no está conectado a Supabase.

---

## Workflows legacy

Los workflows legacy contra Google Sheets se conservan como referencia histórica.
**No son la ruta productiva actual, no se mantienen y no deben usarse como fuente de verdad.**

Ubicación típica: `Workflows/n8n/*.template.json`

Los contratos técnicos legacy y archivos Apps Script también son históricos, salvo que se usen explícitamente para reportería o comparación documental.

---

## Principios operativos

Decisiones que **no deben reabrirse** salvo contradicción crítica explícita:

1. Supabase / PostgreSQL es la fuente de verdad.
2. Google Sheets no es backend operativo.
3. n8n orquesta; PostgreSQL decide y persiste.
4. La IA no confirma reservas, pagos ni disponibilidad real por sí sola.
5. Toda reserva confirmada pasa por `confirmar_reserva()`.
6. Toda pre-reserva se crea por `crear_prereserva()`.
7. No hay `INSERT` directo a `reservas` desde workflows.
8. No usar `DROP ... CASCADE` sin decisión explícita.
9. Mantener `nv()` defensivo en workflows n8n como defensa en profundidad.
10. No reabrir `D-HARD-01` a `D-HARD-11` sin contradicción crítica.
11. No reabrir `D-7B-01` a `D-7B-05` sin contradicción crítica.
12. IDs de cabaña **no son portables** entre DEV y TEST (DEV: 17-21, TEST: 1-5). Cada workflow usa los IDs del ambiente al que apunta.
13. No limpiar fixtures de TEST fuera de un bloque de reset dedicado con SQL aprobado (`D-7C-01`).

**Documento de referencia:** `Docs/Operacional/DECISIONES_NO_REABRIR.md`

---

## Pendientes activos pre-PROD

Pendientes documentados al cierre de 7C (los pendientes 1.1/1.2/1.3 fueron cerrados en 7A; la validación funcional ampliada sobre TEST fue cerrada en 7C):

- **Diseño del bloque de limpieza/reset de TEST** (derivado de D-7C-01). Sección 6.5.
- **Endurecimiento de permisos en DEV** (paridad con TEST). Sección 1.5.
- **Contrato SQL de `registrar_pago` frente a entradas no-vacías mal tipadas** (hoy mitigado por `nv()` en n8n). Sección 1.6.
- `tipo_valor` sin poblar en `configuracion_general` (1.4).
- Validaciones para tipos inválidos no vacíos (heredado de 6D).
- Cobertura empírica opcional de rama `unique_violation` (6.3; `pre_lock` ya cubierta en 7C).
- RLS configurado (pendiente histórico hasta frontend público).
- Tarifas reales productivas y feriados productivos.

**Documento de referencia:** `Docs/Operacional/Pendiente_pre_produccion.md`

---

## Estado de producción

El sistema **no está en producción**.

```text
DEV consolidado + TEST operativo y validado funcionalmente → próximos pasos: reset de TEST / endurecimiento DEV / OPS → consumidores reales → PROD futuro
```

> ⚠️ No conectar consumidores reales —MercadoPago, bot, frontend público— sin definir antes el entorno TEST o asumir explícitamente el riesgo operativo.
