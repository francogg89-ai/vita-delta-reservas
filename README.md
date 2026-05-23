# Vita Delta Reservas

Sistema de automatización integral para el complejo de cabañas Vita Delta.

---

## Qué es este proyecto

Vita Delta Reservas es un sistema de gestión operativa para un complejo de 5 cabañas. El objetivo es centralizar disponibilidad, reservas, pricing, pagos, operación interna y comunicación con huéspedes en una arquitectura automatizable, trazable y escalable.

El stack actual es **Google Sheets** como base de datos operativa, **n8n** como motor de automatización y **Claude API** como capa conversacional futura. La arquitectura está diseñada para migrar progresivamente a una base de datos relacional (PostgreSQL sobre Supabase) sin rehacerse desde cero. Esa migración está formalizada en la Etapa 6B y actualmente está en fase de ejecución sobre el entorno DEV.

---

## Estado actual

### Arquitectura — Completada y aprobada

Todas las etapas de diseño están cerradas. No se reabren.

| Etapa | Descripción | Estado |
|---|---|---|
| 1 | Arquitectura base | Cerrada |
| 2 | Motor de disponibilidad | Cerrada |
| 3 | Motor de precios | Cerrada |
| 4A | Motor de reservas determinístico | Cerrada |
| 4B | Bot conversacional con IA | Cerrada |
| 5A | Modelo de datos real (Sheets) | Cerrada |
| 5B | Implementación vertical mínima | Cerrada |
| 6A | Decisión de migración a base relacional | Cerrada |
| 6B | Migración a Supabase / PostgreSQL | Arquitectura cerrada — ejecución DEV pendiente |

### Google Sheets — Completado

Los Sheets `VITA_DELTA_DEV` y `VITA_DELTA_TEST` están creados y verificados.

| Fase | Descripción | Estado |
|---|---|---|
| 1 | Sheets creados en Google Drive | OK |
| 2 | 24 hojas con encabezados exactos | OK |
| 3 | Datos mínimos cargados | OK |
| 4 | Validaciones de datos aplicadas | OK |
| 5 | Protecciones por entorno | OK |
| 6 | Auditoría final aprobada | OK |

### Workflows n8n — Core validado

Stack actual sobre Sheets + n8n. Estos workflows serán reescritos contra Supabase en la Etapa 6B posterior a la ejecución de DEV.

| Workflow | Versión | DEV | TEST | Descripción |
|---|---|---|---|---|
| `db_recalcular_disponibilidad` | v8 | Validado | Validado | Regenera DISPONIBILIDAD_CACHE completa |
| `db_crear_consulta` | v3 | Validado | Validado | Registra o recupera una consulta activa |
| `db_crear_huesped` | v1 | Validado | Validado | Crea o actualiza un huésped. Validado en Sheets/n8n — será reescrito contra Supabase en etapa posterior. |
| `db_crear_prereserva` | v2 | Validado | Validado | Crea pre-reserva temporal con doble verificación de disponibilidad |
| `db_registrar_pago` | v1 | Validado | Validado | Registra un pago reportado y pasa PRE_RESERVA a revisión manual |
| `db_confirmar_reserva` | v1 | Validado | Validado | Confirma la reserva definitiva tras verificar el pago |
| `sistema_expirar_prereservas` | v1 | Validado | Validado | Marca como vencidas las PRE_RESERVAS en pendiente_pago con expira_en vencido |

Los templates sanitizados de los workflows validados están en `Workflows/n8n/`.
Los contratos técnicos están en `Docs/API_CONTRACTS/`.

---

## Migración a Supabase (Etapa 6B)

La Etapa 6B traslada la fuente de verdad operacional desde Google Sheets hacia una base de datos PostgreSQL alojada en Supabase. El objetivo es lograr integridad transaccional real, prevención estructural de double booking, latencia mucho más baja en consultas de disponibilidad, y una base sólida para la futura web pública.

**Estado:** arquitectura, schema y plan de ejecución consolidados y aprobados. La ejecución sobre Supabase DEV aún no comenzó.

**Importante:** mientras la migración esté en curso, **Google Sheets sigue siendo la fuente de verdad operativa**. PostgreSQL/Supabase reemplazará a Sheets solo después de:

1. Ejecutar el schema completo en Supabase DEV bloque por bloque según `6B_PLAN_FASES.md`.
2. Pasar los 36 tests funcionales y de concurrencia documentados.
3. Cerrar formalmente DEV.
4. Reescribir los workflows n8n para apuntar a Supabase.
5. Validar en TEST.
6. Recién entonces, migrar PROD.

Documentos de la etapa:

- `Docs/Arquitectura/ARQUITECTURA_ETAPA_6A_DECISION_MIGRACION.md` — Decisión de migrar.
- `Docs/Arquitectura/ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md` — Arquitectura consolidada.
- `Docs/Implementacion/6B_SCHEMA_SQL.md` — Schema PostgreSQL completo.
- `Docs/Implementacion/6B_PLAN_FASES.md` — Plan de ejecución bloque por bloque.

---

## Cómo funciona el sistema (estado actual)

```
La IA conversa.
Los workflows operan.
Sheets persiste.
Los humanos auditan.
```

**Google Sheets** es la fuente de verdad operativa **mientras la migración a Supabase esté en curso**. Todas las hojas (RESERVAS, PRE_RESERVAS, DISPONIBILIDAD_CACHE, LOG_CAMBIOS, etc.) viven ahí.

**n8n** ejecuta la lógica determinística: valida disponibilidad, crea pre-reservas, registra pagos, confirma reservas y actualiza la cache. Ninguna decisión crítica depende de la IA.

**Claude / IA** es la capa conversacional futura. Conversa con el huésped, recolecta intención y llama a los workflows determinísticos. No calcula disponibilidad ni confirma reservas por sí sola.

### Flujo de una reserva

```
Consulta entrante
  → db_crear_consulta          registra la consulta
  → db_crear_huesped           crea o actualiza el huésped vinculado
  → db_crear_prereserva        bloqueo temporal + verificación en 2 capas
  → db_registrar_pago          registra el pago reportado → PRE_RESERVA pasa a revisión manual
  → db_confirmar_reserva       Franco/Rodrigo verifican y confirman → RESERVA definitiva
```

`db_crear_prereserva` crea un bloqueo temporal con vencimiento. No es una reserva confirmada. El huésped debe completar el pago antes de que expire la pre-reserva.

---

## Sobre `index.html`

El archivo `index.html` en la raíz del repositorio es una **presentación visual del estado actual del sistema Vita Delta Reservas**. Está pensado para explicar el proyecto a socios, colaboradores y personas no técnicas. No es la web pública de reservas ni está conectado a Google Sheets o n8n.

El prototipo visual original de la futura web de reservas fue movido a `Prototipos/prototipo_web_reservas.html`. Tampoco está conectado al sistema: no consulta disponibilidad real, no genera pre-reservas y no procesa pagos.

---

## Qué no está implementado todavía

- Ejecución del schema 6B en Supabase DEV (planificada, no iniciada).
- Reescritura de workflows n8n contra Supabase.
- Integración con MercadoPago.
- Integración con WhatsApp e Instagram.
- Bot conversacional conectado a canales reales.
- Web pública de reservas (solo existe el prototipo estático).
- Panel administrativo y dashboard operativo.
- Contabilidad automatizada.

---

## Próximo paso

La base de datos actual (Sheets) y los workflows core están validados en DEV y TEST. El siguiente eje de trabajo es la **migración a Supabase (Etapa 6B)**, que debe completarse antes de habilitar canales reales o web pública.

Roadmap ordenado:

1. **Etapa 6B en curso:**
   - Ejecutar Supabase DEV bloque por bloque según `Docs/Implementacion/6B_PLAN_FASES.md`.
   - Pasar los 36 tests funcionales y de concurrencia.
   - Cerrar DEV formalmente.
   - Reescribir workflows n8n contra Supabase (futuro `Docs/Implementacion/6B_REESCRITURA_WORKFLOWS.md`).
   - Validar TEST.
   - Migrar PROD.

2. **Posterior a base Supabase consolidada:**
   - Activar `sistema_expirar_prereservas` en producción con Schedule Trigger.
   - Implementar la capa conversacional con Claude API conectada a los workflows determinísticos.
   - Integrar canales reales: WhatsApp e Instagram.
   - Integrar MercadoPago real.
   - Implementar la web pública de reservas conectada al sistema.

---

## Estructura del repositorio

```
index.html                                    ← Presentación visual del estado del sistema

Prototipos/
└── prototipo_web_reservas.html               ← Boceto visual estático de futura web de reservas

Docs/
├── Arquitectura/
│   ├── ARQUITECTURA_ETAPA_1_VITA_DELTA.md
│   ├── ARQUITECTURA_ETAPA_2_VITA_DELTA.md
│   ├── ARQUITECTURA_ETAPA_3_VITA_DELTA.md
│   ├── ARQUITECTURA_ETAPA_4A_MOTOR_RESERVAS.md
│   ├── ARQUITECTURA_ETAPA_4B_BOT_CONVERSACIONAL.md
│   ├── ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md
│   ├── ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md
│   ├── ARQUITECTURA_ETAPA_6A_DECISION_MIGRACION.md
│   └── ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md
│
├── API_CONTRACTS/                            ← Contratos técnicos de workflows
│   ├── README.md
│   ├── db_recalcular_disponibilidad.md
│   ├── db_crear_consulta.md
│   ├── db_crear_huesped.md
│   ├── db_crear_prereserva.md
│   ├── db_registrar_pago.md
│   ├── db_confirmar_reserva.md
│   └── sistema_expirar_prereservas.md
│
├── Implementacion/
│   ├── README.md
│   ├── PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
│   ├── 6B_SCHEMA_SQL.md                      ← Schema PostgreSQL completo (Etapa 6B)
│   ├── 6B_PLAN_FASES.md                      ← Plan de ejecución bloque por bloque (Etapa 6B)
│   └── AppsScript/
│       ├── validaciones_vita_delta_v3.gs     ← Validaciones de datos (Fase 4)
│       ├── protecciones_vita_delta_v1.gs     ← Protecciones por entorno (Fase 5)
│       └── auditoria_fase6_v2.gs             ← Auditoría de estructura y datos (Fase 6)
│
└── Bitacora/                                 ← (Futuro) Bitácora de ejecución de etapas
    └── 6B_EJECUCION_DEV.md                   ← Se crea al arrancar Fase 0 de la ejecución 6B

Workflows/
└── n8n/                                      ← Templates sanitizados para importar en n8n
    ├── README.md
    ├── db_recalcular_disponibilidad.template.json
    ├── db_crear_consulta.template.json
    ├── db_crear_huesped.template.json
    ├── db_crear_prereserva.template.json
    ├── db_registrar_pago.template.json
    ├── db_confirmar_reserva.template.json
    └── sistema_expirar_prereservas.template.json
```

---

## Principios de trabajo

Antes de agregar cualquier automatización o integración, verificar:

1. Si ya existe una fuente de verdad para ese dato.
2. Si la lógica pertenece a un workflow determinístico o a la IA.
3. Si afecta disponibilidad, reservas, pagos o pricing.
4. Si necesita trazabilidad en `LOG_CAMBIOS`.
5. Si puede romper la implementación mínima validada.
6. Si la pieza pertenece al stack actual (Sheets / n8n) o al stack objetivo (Supabase / PostgreSQL).
