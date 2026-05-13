# Vita Delta Reservas

Sistema de automatización integral para el complejo de cabañas Vita Delta.

---

## Qué es este proyecto

Vita Delta Reservas es un sistema de gestión operativa para un complejo de 5 cabañas. El objetivo es centralizar disponibilidad, reservas, pricing, pagos, operación interna y comunicación con huéspedes en una arquitectura automatizable, trazable y escalable.

El stack principal es Google Sheets como base de datos operativa, n8n como motor de automatización y Claude API como capa conversacional. La arquitectura está diseñada para migrar progresivamente a una base de datos relacional sin rehacerse desde cero.

---

## Estado actual

### Arquitectura — Completada y aprobada

Todas las etapas de diseño están cerradas. No se reabren.

| Etapa | Descripción | Estado |
|---|---|---|
| 1 | Arquitectura base | ✅ Cerrada |
| 2 | Motor de disponibilidad | ✅ Cerrada |
| 3 | Motor de precios | ✅ Cerrada |
| 4A | Motor de reservas determinístico | ✅ Cerrada |
| 4B | Bot conversacional con IA | ✅ Cerrada |
| 5A | Modelo de datos real (Sheets) | ✅ Cerrada |
| 5B | Implementación vertical mínima | ✅ Cerrada |

### Preparación operativa de Google Sheets — Completada

Los Sheets `VITA_DELTA_DEV` y `VITA_DELTA_TEST` están creados y verificados:

| Fase | Descripción | Estado |
|---|---|---|
| 1 | Sheets creados en Google Drive | ✅ |
| 2 | 24 hojas y encabezados exactos | ✅ |
| 3 | Datos mínimos cargados | ✅ |
| 4 | Validaciones de datos aplicadas | ✅ |
| 5 | Protecciones por entorno | ✅ |
| 6 | Auditoría final aprobada | ✅ |

### Implementación de workflows en n8n — Pendiente

Ningún workflow está activo todavía. Los Sheets están listos para recibir escrituras de n8n, pero el sistema no opera en producción.

---

## Sobre `index.html`

El archivo `index.html` en la raíz del repositorio es un **prototipo visual estático**. Es un boceto de referencia para la futura página pública de reservas.

No está conectado a Google Sheets, no consulta disponibilidad real, no genera pre-reservas y no procesa pagos. No representa el estado operativo del sistema.

La implementación real de la web de reservas es una etapa futura, posterior a la validación del flujo transaccional core.

---

## Qué no está implementado todavía

- Ningún workflow de n8n está activo.
- La disponibilidad no se calcula automáticamente (`DISPONIBILIDAD_CACHE` está vacía).
- El bot conversacional no está conectado a ningún canal.
- Los pagos automáticos no están configurados.
- La web pública de reservas no existe (solo el prototipo estático).
- La integración con WhatsApp, Instagram y MercadoPago está pendiente.
- El panel administrativo y el dashboard operativo no existen.
- La contabilidad automatizada no está implementada.

---

## Estructura del repositorio

```
index.html                          ← Prototipo visual estático (no operativo)

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
└── Implementacion/
    ├── README.md
    ├── PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
    └── AppsScript/
        ├── validaciones_vita_delta_v3.gs   ← Validaciones de datos (Fase 4)
        ├── protecciones_vita_delta_v1.gs   ← Protecciones por entorno (Fase 5)
        └── auditoria_fase6_v2.gs           ← Auditoría de estructura y datos (Fase 6)
```

---

## Próximo paso

Implementar el primer workflow real en n8n:

```
db_recalcular_disponibilidad
```

Este workflow es el núcleo del sistema. Lee RESERVAS, PRE_RESERVAS, BLOQUEOS y OVERRIDES_OPERATIVOS, y escribe el resultado en DISPONIBILIDAD_CACHE. Sin este workflow, la disponibilidad no existe como dato consultable.

El plan de implementación está en:

```
Docs/Implementacion/PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
```

---

## Principios de trabajo

Antes de agregar cualquier automatización o integración, verificar:

1. Si ya existe una fuente de verdad para ese dato.
2. Si la lógica pertenece a un workflow determinístico o a la IA.
3. Si afecta disponibilidad, reservas, pagos o pricing.
4. Si necesita trazabilidad en `LOG_CAMBIOS`.
5. Si puede romper la implementación mínima validada.

---

## Principio central

```
La IA conversa.
Los workflows operan.
Sheets persiste.
Los humanos auditan.
```
