# Vita Delta Reservas

Sistema integral de gestión y automatización de reservas para el complejo de cabañas **Vita Delta**.

El proyecto busca centralizar disponibilidad, pre-reservas, reservas, pagos, bloqueos administrativos, operación interna y futura comunicación con huéspedes sobre una arquitectura trazable, automatizable y escalable.

---

## Estado actual del proyecto

**Estado general:** backend Supabase DEV implementado, workflows n8n contra Supabase validados, hardening pre-producción cerrado y documentación canónica actualizada.

El proyecto ya superó la etapa de Google Sheets como backend operativo. La fuente de verdad actual es **Supabase / PostgreSQL**.

### Etapas cerradas

| Etapa | Descripción | Estado |
|---|---|---|
| 1 | Arquitectura base | ✅ Cerrada |
| 2 | Motor de disponibilidad | ✅ Cerrada |
| 3 | Motor de precios | ✅ Cerrada |
| 4A | Motor de reservas determinístico | ✅ Cerrada |
| 4B | Bot conversacional con IA | ✅ Cerrada a nivel diseño |
| 5A | Modelo de datos real inicial | ✅ Cerrada |
| 5B | Implementación vertical mínima | ✅ Cerrada |
| 6A | Decisión de migración a base relacional | ✅ Cerrada |
| 6B | Migración a Supabase / PostgreSQL DEV | ✅ Cerrada |
| 6C | Reescritura de workflows n8n contra Supabase DEV | ✅ Cerrada |
| 6D | Hardening pre-producción + cierre documental | ✅ Cerrada |

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
Fuente de verdad

Supabase / PostgreSQL es la fuente de verdad del sistema.

Viven ahí:

cabañas;
huéspedes;
pre-reservas;
reservas;
pagos;
bloqueos;
tarifas;
configuración general;
eventos especiales;
logs de cambios;
funciones SQL;
vistas operativas;
triggers;
jobs programados con pg_cron.
Orquestación

n8n es el orquestador operativo.

Los workflows reciben eventos, arman payloads JSONB, llaman funciones SQL, procesan respuestas y, en el futuro, dispararán comunicaciones o integraciones externas.

IA

La IA queda como capa conversacional futura.

Puede conversar, interpretar intención, ordenar datos y guiar al huésped, pero no decide disponibilidad, no confirma pagos y no escribe reservas directamente. Las decisiones críticas viven en PostgreSQL y en workflows determinísticos.

Schema canónico vigente

El schema canónico vigente es:

Docs/Implementacion/6B_SCHEMA_SQL.md

Versión vigente: v1.7.2.

La versión v1.7.2 refleja el estado real de DEV post-hardening H2-H6-bis y post-validación H7 en los objetos afectados.

Backup histórico:

Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md

Ese backup es histórico y no es fuente canónica vigente.

Backend Supabase DEV

El backend Supabase DEV está implementado y validado.

Incluye:

schema PostgreSQL completo;
funciones write críticas;
funciones read;
vistas operativas;
triggers de auditoría;
constraints estructurales;
jobs con pg_cron;
seed operativo mínimo;
hardening defensivo en funciones write;
validación de concurrencia real.
Funciones principales
Función	Rol
obtener_disponibilidad_rango()	Consulta de disponibilidad
crear_prereserva()	Puerta única para crear pre-reservas
registrar_pago()	Registro de pagos
confirmar_reserva()	Confirmación de reservas
cancelar_prereserva()	Cancelación de pre-reservas
crear_bloqueo()	Bloqueos administrativos
expirar_prereservas_vencidas()	Expiración automática de pre-reservas
upsert_huesped()	Alta o actualización de huéspedes
validar_disponibilidad()	Validación interna de disponibilidad
Workflows n8n vigentes

Los workflows vigentes están en:

Workflows/n8n/Supabase/

Si el sistema de archivos del repo usa minúsculas en la carpeta, la ruta equivalente es:

Workflows/n8n/supabase/

La Etapa 6C cerró con:

8 workflows Supabase W0-W7;
40 tests funcionales aprobados;
3 verificaciones cruzadas end-to-end;
templates sanitizados para versionado;
wrapper de respuesta unificado.
Workflow	Rol
vita_w00_smoke_test_supabase	Smoke test de conexión
vita_w01_consultar_disponibilidad_supabase	Consulta disponibilidad
vita_w02_crear_prereserva_supabase	Crea pre-reserva
vita_w03_registrar_pago_supabase	Registra pago
vita_w04_confirmar_reserva_supabase	Confirma reserva
vita_w05_cancelar_prereserva_supabase	Cancela pre-reserva
vita_w06_crear_bloqueo_supabase	Crea bloqueo administrativo
vita_w07_vistas_operativas_supabase	Consulta vistas operativas read-only
Hardening pre-producción cerrado

La Etapa 6D cerró formalmente el hardening pre-producción.

Incluyó tres frentes:

Hardening estructural H1-H6-bis
extracts defensivos en 5 funciones write críticas;
fix de rango en vista_ocupacion;
fix cosmético de TRIM en vistas con concatenación nombre + apellido.
Validación de concurrencia H7
6/6 tests aprobados;
0 deadlocks 40P01;
0 races observados;
0 doble booking;
baseline final restaurado.
Cierre documental H8
bump documental del schema canónico a v1.7.2;
backup histórico v1.7.1;
actualización de archivos satélite;
creación de 6D_CIERRE.md.

Documento de cierre:

Docs/Bitacora/6D_CIERRE.md
Cómo funciona el sistema
La IA conversa.
n8n orquesta.
PostgreSQL decide y persiste.
Los humanos auditan.

Flujo base de reserva:

Consulta entrante
  → vita_w01_consultar_disponibilidad_supabase
  → vita_w02_crear_prereserva_supabase
  → vita_w03_registrar_pago_supabase
  → vita_w04_confirmar_reserva_supabase

La pre-reserva bloquea disponibilidad temporalmente. La reserva se confirma solo después de validar pago y disponibilidad bajo locks.

Operaciones adicionales:

vita_w05_cancelar_prereserva_supabase;
vita_w06_crear_bloqueo_supabase;
vita_w07_vistas_operativas_supabase.
Qué está implementado

Está implementado y validado en DEV:

schema PostgreSQL completo;
funciones SQL principales;
vistas operativas;
triggers de auditoría;
pg_cron para expiración de pre-reservas;
workflows n8n contra Supabase;
wrapper de respuesta unificado;
validaciones funcionales W0-W7;
hardening pre-producción;
tests de concurrencia H7;
documentación canónica v1.7.2;
cierre formal de Etapas 6C y 6D.
Qué no está implementado todavía

Todavía no está implementado o no está productivo:

entorno TEST separado;
webhook real de MercadoPago;
integración real con WhatsApp / Instagram mediante Meta API;
bot conversacional conectado a canales reales;
web pública de reservas conectada al backend;
panel administrativo;
dashboard operativo;
contabilidad automatizada;
RLS final para frontend público;
tarifas reales productivas completas;
feriados productivos definitivos;
entorno PROD.
Próxima etapa recomendada

La recomendación documentada al cierre de 6D es:

Opción B — crear entorno TEST antes de conectar consumidores reales.

Motivo:

evita contaminar DEV;
permite probar MercadoPago, bot, frontend y canales reales sin riesgo operativo;
permite resolver pendientes livianos antes de productizar;
deja una frontera clara entre desarrollo, integración y producción.

Opciones posteriores:

Opción	Descripción	Recomendación
B	Entorno TEST	Recomendada como próxima etapa
C	Webhook MercadoPago	Después de TEST, salvo decisión de asumir más riesgo
D	Bot conversacional	Después de TEST, salvo decisión de asumir más riesgo
Frontend	Web pública de reservas	Después de TEST y con RLS definido
Documentos clave
Estado y cierre
Documento	Rol
Docs/Operacional/ESTADO_ACTUAL_VITA_DELTA.md	Estado vigente del proyecto
Docs/Bitacora/6D_CIERRE.md	Cierre formal de Etapa 6D
Docs/Implementacion/6C_CIERRE.md	Cierre formal de Etapa 6C
Docs/Operacional/Pendiente_pre_produccion.md	Pendientes antes de TEST/PROD
Docs/Operacional/DECISIONES_NO_REABRIR.md	Decisiones cerradas
Implementación
Documento	Rol
Docs/Implementacion/6B_SCHEMA_SQL.md	Schema canónico vigente
Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md	Bitácora H1-H7
Docs/Bitacora/6C_EJECUCION.md	Bitácora W0-W7
Docs/Operacional/Lecciones_Aprendidas.md	Gotchas y lecciones operativas
Arquitectura
Documento	Rol
Docs/Arquitectura/ARQUITECTURA_ETAPA_1_VITA_DELTA.md	Arquitectura base
Docs/Arquitectura/ARQUITECTURA_ETAPA_2_VITA_DELTA.md	Disponibilidad
Docs/Arquitectura/ARQUITECTURA_ETAPA_3_VITA_DELTA.md	Pricing
Docs/Arquitectura/ARQUITECTURA_ETAPA_4A_MOTOR_RESERVAS.md	Motor de reservas
Docs/Arquitectura/ARQUITECTURA_ETAPA_4B_BOT_CONVERSACIONAL.md	Bot conversacional
Docs/Arquitectura/ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md	Migración Supabase
Estructura del repositorio
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
│   ├── Docs/Implementacion/
│   │   ├── README.md
│   │   ├── 6B_SCHEMA_SQL.md
│   │   ├── 6B_PLAN_FASES.md
│   │   ├── 6C_CIERRE.md
│   │   └── Archivados/
│   │       ├── 6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md
│   │       ├── 6B_SCHEMA_SQL_AJUSTES_PENDIENTES_RESUELTOS.md
│   │       ├── PLAN_CIERRE_6B_ALINEACION_v1.7.1.md
│   │       ├── 6C_REESCRITURA_WORKFLOWS_SUPABASE.md
│   │       └── Legacy_Sheets/
│   │        ├── PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
│   │        └── ESTADO_IMPLEMENTACIÓN_ETAPA_5.md
│   │
│   ├── Bitacora/
│   │   ├── 6B_EJECUCION_DEV.md
│   │   ├── 6C_EJECUCION.md
│   │   ├── 6D_CIERRE.md
│   │   ├── HARDENING_PRE_PRODUCCION_EJECUCION.md
│   │   └── Archivados/
│   │       └── H8_SNAPSHOTS_SCHEMA_v1.7.2_WORKING_NOTES.md
│   │
│   └── Operacional/
│       ├── ESTADO_ACTUAL_VITA_DELTA.md
│       ├── Pendiente_pre_produccion.md
│       ├── DECISIONES_NO_REABRIR.md
│       ├── Lecciones_Aprendidas.md
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

Si la carpeta Supabase está en minúsculas en el repo, mantener el nombre real de la carpeta al commitear.

Sobre index.html y prototipos

index.html es una presentación visual estática del estado del sistema. Sirve para explicar el proyecto a socios o colaboradores, pero no es una web pública de reservas.

Prototipos/prototipo_web_reservas.html es un prototipo visual de futura web de reservas. No consulta disponibilidad real, no crea pre-reservas, no registra pagos y no está conectado a Supabase.

Workflows legacy

Los workflows legacy contra Google Sheets se conservan como referencia histórica.

No son la ruta productiva actual, no se mantienen y no deben usarse como fuente de verdad.

Ubicación típica:

Workflows/n8n/*.template.json

Los contratos técnicos legacy y archivos Apps Script también son históricos, salvo que se usen explícitamente para reportería o comparación documental.

Principios operativos

Decisiones que no deben reabrirse salvo contradicción crítica explícita:

Supabase/PostgreSQL es la fuente de verdad.
Google Sheets no es backend operativo.
n8n orquesta; PostgreSQL decide y persiste.
La IA no confirma reservas, pagos ni disponibilidad real por sí sola.
Toda reserva confirmada pasa por confirmar_reserva().
Toda pre-reserva se crea por crear_prereserva().
No hay INSERT directo a reservas desde workflows.
No usar DROP ... CASCADE sin decisión explícita.
Mantener nv() defensivo en workflows n8n como defensa en profundidad.
No reabrir D-HARD-01 a D-HARD-11 sin contradicción crítica.

Documento de referencia:

Docs/Operacional/DECISIONES_NO_REABRIR.md
Pendientes livianos antes de TEST/PROD

Pendientes documentados al cierre de 6D:

Evaluar alineación de tipo ninos entre función y tablas.
Evaluar contrato de canal_pago_esperado: restaurar validación manual con payload_invalido o hacer nullable la columna.
Evaluar validaciones para tipos inválidos no vacíos.
Evaluar cobertura empírica opcional de ramas pre_lock y unique_violation en idempotencia de crear_prereserva.

Documento de referencia:

Docs/Operacional/Pendiente_pre_produccion.md
Estado de producción

El sistema no está en producción.

Estado actual:

DEV consolidado → próximo paso recomendado: TEST → luego consumidores reales → PROD futuro

No conectar consumidores reales —MercadoPago, bot, frontend público— sin definir antes el entorno TEST o asumir explícitamente el riesgo operativo.