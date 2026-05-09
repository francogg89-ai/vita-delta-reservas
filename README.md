# Vita Delta Reservas

Sistema de automatización integral para el complejo de cabañas Vita Delta.

El objetivo del proyecto es construir una arquitectura escalable, automatizable y mantenible para gestionar:

- disponibilidad,
- reservas,
- pricing,
- eventos especiales,
- automatización operativa,
- bots conversacionales,
- integración web,
- pagos,
- contabilidad,
- y futuras herramientas de inteligencia artificial.

---

# Objetivo

El sistema busca centralizar toda la lógica operativa del complejo en una única fuente de verdad, evitando:

- inconsistencias,
- double booking,
- cálculos manuales,
- dependencias excesivas de plataformas externas,
- y automatizaciones frágiles.

La arquitectura está diseñada para:
- escalar,
- migrar fácilmente,
- integrar nuevas herramientas,
- y evolucionar sin rehacer el sistema completo.

---

# Principios arquitectónicos

## 1. Backend determinístico

La lógica crítica del sistema nunca depende de IA.

Motores reales manejan:
- disponibilidad,
- reservas,
- pricing,
- bloqueos,
- concurrencia,
- validaciones.

---

## 2. IA como capa cognitiva

La IA se utiliza para:
- conversación,
- interpretación,
- asistencia,
- comunicación,
- automatización conversacional.

Nunca como fuente de verdad operacional.

---

## 3. Una sola fuente de verdad

Toda la disponibilidad deriva de:
- reservas,
- pre-reservas,
- bloqueos,
- configuración.

Nunca se modifica manualmente.

---

## 4. Arquitectura modular

Cada motor funciona como módulo independiente:

- Motor de disponibilidad
- Motor de precios
- EVENTOS_ESPECIALES
- Bots
- Automatizaciones
- Integraciones

---

# Estado actual del proyecto

## Etapa 1 — Arquitectura base
✅ Completada

Definición de:
- entidades,
- permisos,
- estructura,
- configuración,
- principios de migrabilidad,
- workflows base.

---

## Etapa 2 — Motor de disponibilidad
✅ Completada

Incluye:
- horarios,
- bloques,
- overrides,
- escalonamientos,
- race conditions,
- DISPONIBILIDAD_CACHE,
- edge cases.

---

## Etapa 3 — Motor de precios
✅ Completada

Incluye:
- temporadas,
- jerarquía tarifaria,
- descuentos,
- eventos especiales,
- estadías largas,
- techos tarifarios,
- pricing determinístico.

---

## Etapa 4 — Motor de reservas
🔄 En planificación

Próxima etapa:
- estados transaccionales,
- pre-reservas,
- expiraciones,
- pagos,
- cancelaciones,
- workflows completos de reserva.

---

# Stack previsto

## Backend / Automatización
- n8n
- Google Sheets
- Apps Script
- Supabase/PostgreSQL (futuro)

---

## Bots / Conversación
- WhatsApp Cloud API
- Instagram API
- OpenAI / Claude

---

## Frontend
- Web de reservas
- Panel administrativo
- Dashboard operativo

---

# Estructura del repositorio

```text
docs/
└── arquitectura/