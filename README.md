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
- operación interna,
- contabilidad futura,
- y futuras herramientas de inteligencia artificial.

---

## Objetivo

El sistema busca centralizar la lógica operativa del complejo en una única fuente de verdad, evitando:

- inconsistencias,
- double booking,
- cálculos manuales,
- dependencia excesiva de plataformas externas,
- automatizaciones frágiles,
- pérdida de trazabilidad,
- y errores operativos difíciles de auditar.

La arquitectura está diseñada para:

- escalar progresivamente,
- migrar fácilmente a una base de datos más robusta,
- integrar nuevas herramientas,
- separar IA de lógica crítica,
- y evolucionar sin rehacer el sistema completo.

---

## Principios arquitectónicos

### 1. Backend determinístico

La lógica crítica del sistema nunca depende de IA.

Motores reales manejan:

- disponibilidad,
- reservas,
- pricing,
- bloqueos,
- pagos,
- concurrencia,
- validaciones,
- expiraciones,
- y consistencia de datos.

La IA puede asistir, pero no decide el estado operativo del sistema.

---

### 2. IA como capa cognitiva

La IA se utiliza para:

- conversación,
- interpretación,
- asistencia,
- comunicación,
- clasificación de intención,
- respuestas al huésped,
- derivación a humano,
- y automatización conversacional.

Nunca es fuente de verdad operacional.

---

### 3. Una sola fuente de verdad

La disponibilidad deriva de:

- RESERVAS,
- PRE_RESERVAS,
- BLOQUEOS,
- OVERRIDES_OPERATIVOS,
- CONFIGURACION_GENERAL.

`DISPONIBILIDAD_CACHE` es una tabla derivada.  
Nunca debe tratarse como fuente primaria de verdad.

---

### 4. Arquitectura modular

Cada motor funciona como módulo independiente:

- Motor de disponibilidad.
- Motor de precios.
- Motor de reservas.
- Motor de eventos especiales.
- Bot conversacional.
- Workflows de pagos.
- Automatizaciones operativas.
- Integraciones externas.

Esto permite implementar, probar y reemplazar partes del sistema sin romper todo.

---

### 5. Implementación progresiva

El sistema no se implementa todo de una vez.

La secuencia correcta es:

```txt
Arquitectura
→ Modelo de datos real
→ Implementación vertical mínima
→ Validación interna
→ Canales externos
→ Bot conversacional
→ Pagos automáticos
→ Frontend
→ Contabilidad y expansión