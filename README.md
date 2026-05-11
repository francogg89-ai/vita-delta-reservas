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
```

Primero se valida el corazón transaccional.
Después se conectan canales externos.

---

## Estado actual del proyecto

### Etapa 1 — Arquitectura base

✅ Completada

Define:

- entidades principales,
- estructura operativa,
- permisos,
- configuración,
- principios de migrabilidad,
- separación entre datos, workflows e interfaces,
- workflows base,
- y fundamentos generales del sistema.

Documento:

```txt
Docs/Arquitectura/ARQUITECTURA_ETAPA_1_VITA_DELTA.md
```

---

### Etapa 2 — Motor de disponibilidad

✅ Completada

Incluye:

- horarios,
- bloques,
- overrides,
- escalonamientos,
- race conditions,
- `DISPONIBILIDAD_CACHE`,
- reglas de ocupación,
- checkout disponible,
- y edge cases de disponibilidad.

Documento:

```txt
Docs/Arquitectura/ARQUITECTURA_ETAPA_2_VITA_DELTA.md
```

---

### Etapa 3 — Motor de precios

✅ Completada

Incluye:

- temporadas,
- jerarquía tarifaria,
- descuentos,
- eventos especiales,
- estadías largas,
- techos tarifarios,
- paquetes,
- pricing determinístico,
- y reglas para evitar cotizaciones inválidas.

Documento:

```txt
Docs/Arquitectura/ARQUITECTURA_ETAPA_3_VITA_DELTA.md
```

---

### Etapa 4A — Motor de reservas determinístico

✅ Completada

Define:

- flujo CONSULTA → PRE_RESERVA → RESERVA,
- pagos multicanal,
- auditoría humana,
- cancelaciones y modificaciones no automáticas,
- trazabilidad,
- reglas de confirmación,
- y separación entre workflow operativo y bot conversacional.

Documento:

```txt
Docs/Arquitectura/ARQUITECTURA_ETAPA_4A_MOTOR_RESERVAS.md
```

Documento complementario futuro:

```txt
Docs/Arquitectura/ARQUITECTURA_ETAPA_4A_FUTURO.md
```

---

### Etapa 4B — Bot conversacional con IA

✅ Completada

Define:

- identidad del bot,
- tono,
- clasificador previo,
- FAQ sin IA,
- cuándo llamar a Claude API,
- tool use,
- handoff humano,
- prompt caching,
- reducción de tokens,
- seguridad,
- prompt injection,
- observabilidad,
- límites operativos,
- y edge cases conversacionales.

Documento:

```txt
Docs/Arquitectura/ARQUITECTURA_ETAPA_4B_BOT_CONVERSACIONAL.md
```

---

### Etapa 5A — Modelo de datos real

✅ Completada

Transforma la arquitectura en una estructura real de Google Sheets.

Define:

- hojas necesarias,
- columnas exactas,
- tipos de datos,
- estados permitidos,
- claves de relación,
- campos obligatorios/opcionales,
- campos JSON,
- campos calculados,
- permisos por hoja,
- hojas fuente,
- hojas derivadas,
- vistas operativas,
- logs,
- configuración,
- y compatibilidad futura con SQL.

Documento:

```txt
Docs/Arquitectura/ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md
```

---

### Etapa 5B — Implementación vertical mínima

✅ Completada

Define el primer flujo real a probar:

```txt
CONSULTA
→ PRE_RESERVA
→ PAGO manual validado
→ RESERVA confirmada
→ recálculo de DISPONIBILIDAD_CACHE
→ LOG_CAMBIOS
```

Incluye:

- workflows mínimos,
- locking lógico,
- idempotencia,
- race conditions,
- rollback,
- recuperación,
- casos de prueba,
- protocolo de prueba,
- y criterios de éxito.

Documento:

```txt
Docs/Arquitectura/ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md
```

---

## Estado actual

El proyecto ya completó la etapa de arquitectura inicial y entra en fase de implementación real.

La próxima acción no es diseñar más arquitectura, sino ejecutar el plan operativo:

```txt
Crear VITA_DELTA_DEV
Crear VITA_DELTA_TEST
Cargar estructura del Sheets
Cargar datos mínimos
Configurar validaciones
Configurar protecciones
Implementar db_recalcular_disponibilidad en n8n
```

Plan operativo:

```txt
Docs/Implementacion/PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
```

---

## Stack previsto

### Backend / Automatización

- n8n
- Google Sheets
- Google Forms
- Apps Script
- Supabase/PostgreSQL futuro

### Bots / Conversación

- WhatsApp Cloud API
- Instagram Graph API
- Claude API
- OpenAI API u otros modelos futuros

### Frontend

- Web pública de reservas
- Panel administrativo
- Dashboard operativo
- Calendario visual

### Pagos

- Transferencia bancaria
- Transferencia a MercadoPago
- MercadoPago Link
- Tarjetas vía procesador futuro
- Criptomonedas como medio previsto

---

## Estructura del repositorio

```txt
Docs/
├── Arquitectura/
│   ├── ARQUITECTURA_ETAPA_1_VITA_DELTA.md
│   ├── ARQUITECTURA_ETAPA_2_VITA_DELTA.md
│   ├── ARQUITECTURA_ETAPA_3_VITA_DELTA.md
│   ├── ARQUITECTURA_ETAPA_4A_MOTOR_RESERVAS.md
│   ├── ARQUITECTURA_ETAPA_4A_FUTURO.md
│   ├── ARQUITECTURA_ETAPA_4B_BOT_CONVERSACIONAL.md
│   ├── ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md
│   └── ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md
│
└── Implementacion/
    ├── README.md
    └── PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
```

---

## Regla de trabajo

Antes de agregar una nueva automatización o integración, verificar:

1. Si ya existe una fuente de verdad.
2. Si la lógica pertenece a un workflow determinístico o a la IA.
3. Si afecta disponibilidad, reservas, pagos o pricing.
4. Si necesita trazabilidad en `LOG_CAMBIOS`.
5. Si puede romper la implementación mínima validada.

---

## Principio central

```txt
La IA conversa.
Los workflows operan.
Sheets persiste.
Los humanos auditan.
```

---

## Próximo paso

Seguir el documento:

```txt
Docs/Implementacion/PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
```

y completar la creación de los Sheets:

```txt
VITA_DELTA_DEV
VITA_DELTA_TEST
```

Una vez verificados, implementar el primer workflow real:

```txt
db_recalcular_disponibilidad
```
