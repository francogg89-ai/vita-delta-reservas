# Vita Delta Reservas

Sistema de automatización integral para el complejo de cabañas Vita Delta.

---

## Qué es este proyecto

Vita Delta Reservas es un sistema de gestión operativa para un complejo de 5 cabañas. El objetivo es centralizar disponibilidad, reservas, pricing, pagos, operación interna y comunicación con huéspedes en una arquitectura automatizable, trazable y escalable.

El stack principal es Google Sheets como base de datos operativa, n8n como motor de automatización y Claude API como capa conversacional futura. La arquitectura está diseñada para migrar progresivamente a una base de datos relacional sin rehacerse desde cero.

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

| Workflow | Versión | DEV | TEST | Descripción |
|---|---|---|---|---|
| `db_recalcular_disponibilidad` | v8 | Validado | Validado | Regenera DISPONIBILIDAD_CACHE completa |
| `db_crear_consulta` | v3 | Validado | Validado | Registra o recupera una consulta activa |
| `db_crear_prereserva` | v2 | Validado | Validado | Crea pre-reserva temporal con doble verificación de disponibilidad |
| `db_registrar_pago` | v1 | Validado | Validado | Registra un pago reportado y pasa PRE_RESERVA a revisión manual |
| `db_confirmar_reserva` | v1 | Validado | Validado | Confirma la reserva definitiva tras verificar el pago |
| `sistema_expirar_prereservas` | v1 | Validado | Validado | Marca como vencidas las PRE_RESERVAS en pendiente_pago con expira_en vencido |

Los templates sanitizados de los workflows validados están en `Workflows/n8n/`.
Los contratos técnicos están en `Docs/API_CONTRACTS/`.

---

## Cómo funciona el sistema

```
La IA conversa.
Los workflows operan.
Sheets persiste.
Los humanos auditan.
```

**Google Sheets** es la fuente de verdad operativa. Todas las hojas (RESERVAS, PRE_RESERVAS, DISPONIBILIDAD_CACHE, LOG_CAMBIOS, etc.) viven ahí.

**n8n** ejecuta la lógica determinística: valida disponibilidad, crea pre-reservas, registra pagos, confirma reservas y actualiza la cache. Ninguna decisión crítica depende de la IA.

**Claude / IA** es la capa conversacional futura. Conversa con el huésped, recolecta intención y llama a los workflows determinísticos. No calcula disponibilidad ni confirma reservas por sí sola.

### Flujo de una reserva

```
Consulta entrante
  → db_crear_consulta          registra la consulta
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

- Integración con MercadoPago.
- Integración con WhatsApp e Instagram.
- Bot conversacional conectado a canales reales.
- Web pública de reservas (solo existe el prototipo estático).
- Panel administrativo y dashboard operativo.
- Contabilidad automatizada.

---

## Próximo paso

El core de workflows de reservas está completo y validado en DEV y TEST. Las próximas etapas son:

- Activar `sistema_expirar_prereservas` en producción con Schedule Trigger diario.
- Implementar la capa conversacional con Claude API conectada a los workflows determinísticos.
- Integrar canales reales: WhatsApp e Instagram.
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
│   └── ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md
│
├── API_CONTRACTS/                            ← Contratos técnicos de workflows
│   ├── README.md
│   ├── db_recalcular_disponibilidad.md
│   ├── db_crear_consulta.md
│   ├── db_crear_prereserva.md
│   ├── db_registrar_pago.md
│   ├── db_confirmar_reserva.md
│   └── sistema_expirar_prereservas.md
│
└── Implementacion/
    ├── README.md
    ├── PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
    └── AppsScript/
        ├── validaciones_vita_delta_v3.gs     ← Validaciones de datos (Fase 4)
        ├── protecciones_vita_delta_v1.gs     ← Protecciones por entorno (Fase 5)
        └── auditoria_fase6_v2.gs             ← Auditoría de estructura y datos (Fase 6)

Workflows/
└── n8n/                                      ← Templates sanitizados para importar en n8n
    ├── README.md
    ├── db_recalcular_disponibilidad.template.json
    ├── db_crear_consulta.template.json
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
