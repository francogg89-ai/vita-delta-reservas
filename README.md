# Vita Delta Reservas

Sistema de automatización integral para el complejo de cabañas Vita Delta.

---

## Qué es este proyecto

Vita Delta Reservas es un sistema de gestión operativa para un complejo de 5 cabañas. El objetivo es centralizar disponibilidad, reservas, pricing, pagos, operación interna y comunicación con huéspedes en una arquitectura automatizable, trazable y escalable.

El stack actual es **Supabase / PostgreSQL** como base de datos operativa, **n8n** como motor de automatización y **Claude API** como capa conversacional futura. La arquitectura migró desde Google Sheets a una base de datos relacional en la Etapa 6B, y los workflows n8n fueron reescritos contra Supabase en la Etapa 6C. Ambas etapas están cerradas formalmente sobre el entorno DEV.

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
| 4B | Bot conversacional con IA | Cerrada (diseño) |
| 5A | Modelo de datos real (Sheets) | Cerrada |
| 5B | Implementación vertical mínima | Cerrada |
| 6A | Decisión de migración a base relacional | Cerrada |
| 6B | Migración a Supabase / PostgreSQL | Cerrada — DEV 100% alineado con v1.7.1 |
| 6C | Reescritura de workflows n8n contra Supabase DEV | Cerrada — 8 workflows operativos |

### Backend Supabase DEV — Completado

La base de datos PostgreSQL está implementada y validada en el proyecto DEV.

| Fase | Descripción | Estado |
|---|---|---|
| 1 | Schema base (Bloques 1-8): extensiones, enums, 20 tablas, constraints | Cerrada |
| 2 | Funciones y triggers (Bloques 9-19): 12 funciones + 13 triggers | Cerrada |
| 3 | Vistas + seed operativo + pg_cron (Bloques 20-22) | Cerrada |
| Hotfix v1.7 | Regla `hora_checkout_domingo = 16:00` | Aplicado en DEV |
| Alineación v1.7.1 | `obtener_disponibilidad_rango` con CASE de domingo | Aplicada en DEV |

**Schema canónico actual:** `Docs/Implementacion/6B_SCHEMA_SQL.md v1.7.1`. **DEV está 100% alineado.**

### Workflows n8n contra Supabase — Completados

8 workflows operativos en DEV con 40 tests funcionales aprobados y 3 verificaciones cruzadas end-to-end.

| Workflow | Función / vista | Estado |
|---|---|---|
| `vita_w00_smoke_test_supabase` | conexión Supabase | Cerrado |
| `vita_w01_consultar_disponibilidad_supabase` | `obtener_disponibilidad_rango()` | Cerrado |
| `vita_w02_crear_prereserva_supabase` | `crear_prereserva()` | Cerrado |
| `vita_w03_registrar_pago_supabase` | `registrar_pago()` | Cerrado |
| `vita_w04_confirmar_reserva_supabase` | `confirmar_reserva()` | Cerrado |
| `vita_w05_cancelar_prereserva_supabase` | `cancelar_prereserva()` | Cerrado |
| `vita_w06_crear_bloqueo_supabase` | `crear_bloqueo()` | Cerrado |
| `vita_w07_vistas_operativas_supabase` | 6 vistas operativas (read-only) | Cerrado |

Los templates sanitizados están en `Workflows/n8n/supabase/`. La bitácora detallada está en `Docs/Bitacora/6C_EJECUCION.md`. El documento de cierre formal de la etapa es `Docs/Implementacion/6C_CIERRE.md`.

### Workflows legacy (Sheets) — Congelados

Los workflows de la Etapa 5 contra Google Sheets están en `Workflows/n8n/*.template.json` (sin subcarpeta) y se conservan como referencia histórica. **No se mantienen ni se actualizan.** Fueron reemplazados funcionalmente por los workflows de 6C contra Supabase.

---

## Cómo funciona el sistema (estado actual)

```
La IA conversa.
Los workflows operan.
Supabase persiste.
Los humanos auditan.
```

**Supabase / PostgreSQL** es la fuente de verdad operativa. Todas las tablas (RESERVAS, PRE_RESERVAS, PAGOS, HUESPEDES, BLOQUEOS, LOG_CAMBIOS, etc.) viven ahí. Las funciones SQL del schema (`crear_prereserva`, `confirmar_reserva`, `cancelar_prereserva`, `registrar_pago`, `crear_bloqueo`, `obtener_disponibilidad_rango`) son los contratos estables que n8n invoca.

**n8n** ejecuta la lógica de orquestación: recibe eventos, arma payloads JSONB, llama funciones SQL, maneja respuestas y dispara comunicaciones. Ninguna decisión crítica depende de la IA ni se calcula fuera de PostgreSQL.

**Claude / IA** es la capa conversacional futura. Conversa con el huésped, recolecta intención y llama a los workflows determinísticos. No calcula disponibilidad ni confirma reservas por sí sola.

### Flujo de una reserva

```
Consulta entrante
  → vita_w01_consultar_disponibilidad_supabase    consulta disponibilidad
  → vita_w02_crear_prereserva_supabase            crea pre-reserva temporal con locks + validación
  → vita_w03_registrar_pago_supabase              registra el pago reportado
  → vita_w04_confirmar_reserva_supabase           confirma la reserva tras verificar el pago
                                                  (caminos estricto y combinado disponibles)
```

`vita_w02_crear_prereserva_supabase` crea un bloqueo temporal con vencimiento de 60 minutos. No es una reserva confirmada. El huésped debe completar el pago antes de que la pre-reserva expire (el job `expirar_prereservas` en pg_cron las vence automáticamente cada 5 minutos).

Operaciones adicionales:
- `vita_w05_cancelar_prereserva_supabase` — cancela una pre-reserva activa.
- `vita_w06_crear_bloqueo_supabase` — crea bloqueos administrativos (mantenimiento, tormenta, etc.).
- `vita_w07_vistas_operativas_supabase` — consulta paramétrica de 6 vistas operativas.

---

## Sobre `index.html`

El archivo `index.html` en la raíz del repositorio es una **presentación visual del estado actual del sistema Vita Delta Reservas**. Está pensado para explicar el proyecto a socios, colaboradores y personas no técnicas. No es la web pública de reservas ni está conectado a Supabase o n8n.

El prototipo visual original de la futura web de reservas fue movido a `Prototipos/prototipo_web_reservas.html`. Tampoco está conectado al sistema: no consulta disponibilidad real, no genera pre-reservas y no procesa pagos.

---

## Qué no está implementado todavía

- Hardening pre-producción: aplicar `NULLIF(TRIM(...))` en funciones write y fix de `vista_ocupacion`.
- Entorno TEST levantado en Supabase.
- Workflow del webhook de MercadoPago.
- Integración con WhatsApp e Instagram (Meta API).
- Bot conversacional implementado (Claude API) conectado a canales reales.
- Web pública de reservas (solo existe el prototipo estático).
- Panel administrativo y dashboard operativo.
- Contabilidad automatizada.
- RLS configurado (pendiente hasta tener frontend público).
- Tarifas reales cargadas (DEV usa baseline neutro).
- Feriados productivos cargados.

---

## Próximo paso

Con las Etapas 6B y 6C cerradas, el sistema tiene backend + workflows determinísticos operativos en DEV. El siguiente eje es **decidir entre 4 opciones**:

### Opción A — Hardening pre-producción

Ejecutar los items de `Docs/Implementacion/Pendiente_pre_produccion.md`:
- `NULLIF(TRIM(...))` en funciones write para campos obligatorios de texto.
- Fix de `vista_ocupacion` (25 vs 24 meses).
- Fix cosmético de concatenaciones `nombre + apellido` en vistas.

**Ventaja:** cierra deudas técnicas conocidas antes de habilitar consumidores reales.

### Opción B — Entorno TEST

Replicar DEV en un proyecto Supabase separado para integrar consumidores reales sin riesgo a datos reales.

### Opción C — Webhook MercadoPago

Workflow operativo real que invoca W3 (registrar_pago) tras un webhook de MP, con deduplicación por `payment_id`. Primer flujo productivo end-to-end.

### Opción D — Bot conversacional (Etapa 4B implementación)

Implementar el bot diseñado en Etapa 4B usando Claude API + Meta API.

**Recomendación documentada en `Docs/Implementacion/6C_CIERRE.md`:** A primero, después B. Cerrar deudas técnicas conocidas antes de complicar el sistema con nuevos consumidores.

### Posterior a la decisión de etapa actual

- Integrar canales reales: WhatsApp e Instagram (Meta API).
- Implementar la capa conversacional con Claude API conectada a los workflows determinísticos.
- Integrar MercadoPago real.
- Implementar la web pública de reservas conectada al sistema.
- Configurar RLS antes de exponer frontend público.

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
├── API_CONTRACTS/                            ← Contratos técnicos de workflows legacy (referencia histórica)
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
│   ├── 6B_SCHEMA_SQL.md                      ← Schema PostgreSQL completo (v1.7.1)
│   ├── 6B_PLAN_FASES.md                      ← Plan de ejecución bloque por bloque (v1.1)
│   ├── 6B_SCHEMA_SQL_AJUSTES_PENDIENTES.md   ← Pendientes documentales detectados en DEV
│   ├── 6C_CIERRE.md                          ← Cierre formal de Etapa 6C
│   ├── Pendiente_pre_produccion.md           ← Cambios a aplicar antes del despliegue productivo
│   └── AppsScript/
│       ├── validaciones_vita_delta_v3.gs     ← Validaciones de datos (Fase 4 — legacy)
│       ├── protecciones_vita_delta_v1.gs     ← Protecciones por entorno (Fase 5 — legacy)
│       └── auditoria_fase6_v2.gs             ← Auditoría de estructura y datos (Fase 6 — legacy)
│
├── Operacional/
│   └── Lecciones_Aprendidas.md               ← Gotchas operativos (incluye L-6C-01 a L-6C-09)
│
└── Bitacora/                                 ← Bitácora de ejecución por etapa
    ├── 6B_EJECUCION_DEV.md                   ← Bloques 1-22 + hotfix v1.7 + alineación v1.7.1
    └── 6C_EJECUCION.md                       ← Workflows W0-W7 contra Supabase DEV

Workflows/
└── n8n/                                      ← Templates sanitizados para importar en n8n
    ├── README.md                             ← Workflows legacy (Sheets) — congelados
    ├── db_recalcular_disponibilidad.template.json  ← legacy
    ├── db_crear_consulta.template.json             ← legacy
    ├── db_crear_huesped.template.json              ← legacy
    ├── db_crear_prereserva.template.json           ← legacy
    ├── db_registrar_pago.template.json             ← legacy
    ├── db_confirmar_reserva.template.json          ← legacy
    ├── sistema_expirar_prereservas.template.json   ← legacy
    │
    └── supabase/                             ← Workflows contra Supabase (Etapa 6C, vigentes)
        ├── README.md
        ├── vita_w00_smoke_test_supabase.template.json
        ├── vita_w01_consultar_disponibilidad_supabase.template.json
        ├── vita_w02_crear_prereserva_supabase.template.json
        ├── vita_w03_registrar_pago_supabase.template.json
        ├── vita_w04_confirmar_reserva_supabase.template.json
        ├── vita_w05_cancelar_prereserva_supabase.template.json
        ├── vita_w06_crear_bloqueo_supabase.template.json
        └── vita_w07_vistas_operativas_supabase.template.json
```

---

## Principios de trabajo

Antes de agregar cualquier automatización o integración, verificar:

1. Si ya existe una fuente de verdad para ese dato (Supabase).
2. Si la lógica pertenece a un workflow determinístico o a la IA.
3. Si afecta disponibilidad, reservas, pagos o pricing — esos casos pasan por funciones SQL del schema, no por lógica n8n.
4. Si necesita trazabilidad en `log_cambios` con `source_event`.
5. Si puede romper la implementación validada en DEV.
6. Si el cambio es estructural (schema, función SQL) o solo de workflow (n8n).

Antes de cualquier cambio crítico, verificar el contrato real con queries read-only (`pg_get_function_result`, `pg_get_functiondef`, `information_schema.columns`). Patrón consolidado durante Etapa 6C.
