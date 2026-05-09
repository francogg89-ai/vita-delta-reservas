# ARQUITECTURA_ETAPA_4A_FUTURO.md

# COMPLEJO VITA DELTA
## Evoluciones futuras previstas para Etapa 4A — Motor de Reservas

---

# 1. OBJETIVO DEL DOCUMENTO

Este documento reúne mejoras, extensiones y capacidades futuras previstas para el Motor de Reservas de Complejo Vita Delta.

No forman parte de la implementación inicial obligatoria de Etapa 4A.

El objetivo es:

- dejar registradas posibles evoluciones,
- evitar olvidar ideas importantes,
- permitir crecimiento progresivo,
- y evitar sobreingeniería temprana.

La prioridad actual sigue siendo:

- simplicidad,
- estabilidad,
- trazabilidad,
- mantenibilidad,
- y operación real confiable.

---

# 2. PRINCIPIO GENERAL

Las evoluciones futuras no deben romper:

- consistencia transaccional,
- trazabilidad,
- separación entre IA y lógica crítica,
- ni la simplicidad operativa del sistema actual.

Toda nueva capacidad debe integrarse como una capa adicional sobre la arquitectura existente.

---

# 3. IDEMPOTENCY KEY

## Objetivo

Evitar ejecuciones duplicadas de workflows críticos.

Especialmente importante para:

- webhooks repetidos,
- reintentos automáticos,
- respuestas lentas de APIs,
- duplicación accidental de pagos,
- y race conditions externas.

## Aplicaciones futuras

Posibles entidades:

- PAGOS
- RESERVAS
- PRE_RESERVAS
- workflows críticos de n8n

## Implementación futura posible

Agregar un campo:

```txt
idempotency_key