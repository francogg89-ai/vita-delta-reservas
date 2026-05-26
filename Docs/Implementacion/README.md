# Implementación — Vita Delta Reservas

Este directorio contiene los documentos operativos de implementación del sistema de reservas de Vita Delta.

A diferencia de `Docs/Arquitectura/`, esta carpeta no redefine decisiones conceptuales. Su función es **guiar la ejecución práctica de lo ya diseñado**: schema SQL, planes de ejecución, bitácoras de migración, pendientes pre-producción y scripts de Apps Script.

---

## Qué encontrás en este directorio

```txt
Docs/Implementacion/
├── README.md                                    ← Este archivo
│
├── PLAN_ETAPA_5_IMPLEMENTACION_REAL.md          ← Plan operativo histórico de Etapa 5 (Sheets DEV/TEST)
│
├── 6B_SCHEMA_SQL.md                             ← Schema PostgreSQL canónico (v1.7.1) — fuente de verdad técnica
├── 6B_PLAN_FASES.md                             ← Plan de ejecución bloque por bloque (v1.1, post-ejecución)
├── 6B_SCHEMA_SQL_AJUSTES_PENDIENTES.md          ← Ajustes documentales pendientes detectados durante DEV
│
├── 6C_CIERRE.md                                 ← Cierre formal de Etapa 6C (workflows n8n vs Supabase DEV)
│
├── Pendiente_pre_produccion.md                  ← Cambios y configuraciones a aplicar antes de PROD
│
└── AppsScript/                                  ← Scripts legacy de Etapa 5 (referencia histórica)
    ├── validaciones_vita_delta_v3.gs            ← Validaciones de datos sobre Sheets (Fase 4 de Etapa 5)
    ├── protecciones_vita_delta_v1.gs            ← Protecciones por entorno (Fase 5 de Etapa 5)
    └── auditoria_fase6_v2.gs                    ← Auditoría de estructura y datos (Fase 6 de Etapa 5)
```
Los scripts de `AppsScript/` son artefactos legacy de Google Sheets. No deben usarse para nuevos flujos operativos contra Supabase.

Documentos relacionados que viven fuera de esta carpeta:

- Bitácora de ejecución de la migración: `Docs/Bitacora/6B_EJECUCION_DEV.md`.
- Bitácora de ejecución de los workflows 6C: `Docs/Bitacora/6C_EJECUCION.md`.
- Decisiones arquitectónicas: `Docs/Arquitectura/`.
- Templates de workflows vigentes: `Workflows/n8n/supabase/`.
- Lecciones aprendidas operativas: `Docs/Operacional/Lecciones_Aprendidas.md`.

---

## Estado actual de la implementación

| Etapa | Stack | Estado |
|---|---|---|
| Etapa 5 (Sheets DEV/TEST + workflows core) | Google Sheets + n8n | Cerrada — congelada como referencia histórica |
| Etapa 6B (migración a PostgreSQL/Supabase) | Supabase + PostgreSQL | Cerrada — DEV 100% alineado con v1.7.1 |
| Etapa 6C (workflows n8n contra Supabase DEV) | Supabase + n8n | Cerrada — 8 workflows operativos, 40 tests aprobados |

**Stack operativo actual:** Supabase como fuente de verdad + workflows n8n nuevos apuntando a Supabase. Los workflows legacy contra Google Sheets están congelados y no se mantienen.

---

## Documentos operativos vigentes

### Schema SQL

```txt
6B_SCHEMA_SQL.md (v1.7.1)
```

Fuente de verdad para:
- Próximas recreaciones de DEV (si fuera necesario).
- Ejecución futura en TEST.
- Ejecución futura en PROD.
- Cualquier consulta sobre estructura de tablas, funciones, triggers, vistas, constraints o seed mínimo.

El plan operativo correspondiente (`6B_PLAN_FASES.md v1.1`) ya fue ejecutado y se conserva como referencia histórica/operativa para auditar la ejecución o recrear entornos.

### Workflows n8n contra Supabase

```txt
6C_CIERRE.md
```

Documento canónico de cierre de Etapa 6C. Contiene:
- Resumen ejecutivo de los 8 workflows implementados.
- Convenciones consolidadas (naming, source events, wrapper externo, normalización defensiva, idempotencia).
- Patrón de trabajo establecido y reutilizable.
- Catálogo de 9 lecciones aprendidas (L-6C-01 a L-6C-09).
- 3 hallazgos pendientes derivados a `Pendiente_pre_produccion.md`.
- 8 decisiones cerradas durante la etapa (NO REABRIR).
- 4 opciones de próxima etapa con análisis y recomendación.

Los templates sanitizados de los workflows están en `Workflows/n8n/supabase/`.

---

## Principios de implementación

Estos principios son atemporales y aplican a todas las etapas, sin importar si el stack es Sheets, Supabase u otro.

```txt
Primero consistencia.
Después automatización.
Después canales externos.
Después inteligencia conversacional.
```

No se conectan canales externos (WhatsApp, Instagram, MercadoPago) ni capa conversacional (Claude API, bot) hasta que el corazón transaccional esté validado.

### Regla crítica de entornos

**Nunca ejecutar workflows o SQL de prueba contra datos productivos.**

- Las credenciales de Supabase (Project ID, Project URL, database password, anon key, service role key, connection strings) viven **fuera del repositorio**: en gestor de contraseñas, en `.env` no versionado, o en credentials de n8n cuando aplique.
- Los placeholders `__SUPABASE_PROJECT_ID_DEV__`, `__CREDENTIAL_ID__`, `__CREDENTIAL_NAME__`, `__WORKFLOW_ID__`, `__WORKFLOW_VERSION_ID__`, `__N8N_INSTANCE_ID__`, etc. deben reemplazarse localmente al momento de ejecutar; nunca commitear con valores reales.

### Entornos contemplados

| Entorno | Sheets (legacy) | Supabase | Workflows n8n |
|---|---|---|---|
| DEV | `VITA_DELTA_DEV` (congelado) | Proyecto DEV (Etapas 6B+6C cerradas) | 8 workflows vs Supabase operativos |
| TEST | `VITA_DELTA_TEST` (congelado) | No iniciado | No iniciado |
| PROD | `VITA_DELTA_PROD` (nunca activado) | No iniciado | No iniciado |

TEST y PROD no se activan hasta que las opciones de hardening pre-producción estén ejecutadas (ver `Pendiente_pre_produccion.md`).

---

## Relación con arquitectura

Esta carpeta depende de los documentos cerrados en:

```txt
Docs/Arquitectura/
```

Los más relevantes para los documentos vigentes son:

- `ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md` — Modelo de datos sobre Sheets (precursor del schema 6B).
- `ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md` — Implementación vertical mínima en Sheets/n8n.
- `ARQUITECTURA_ETAPA_6A_DECISION_MIGRACION.md` — Decisión de migrar a base relacional.
- `ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md` — Arquitectura consolidada de la migración.

Si aparece una contradicción entre un documento de esta carpeta y un documento de arquitectura cerrado, **prevalecen los documentos de arquitectura de etapa 5 o 6**, salvo que se documente explícitamente una corrección posterior (con bump de versión, nota técnica o registro en bitácora).

---

## Cómo se trabaja en esta carpeta

1. **No se reabren decisiones cerradas.** Si un documento de arquitectura cerró una decisión, esta carpeta la respeta. Las correcciones se hacen mediante patches versionados (v1.7 → v1.7.1) o bumps menores, no reabriendo conceptos.

2. **Las versiones se bumpean explícitamente.** Cada cambio operativo real al schema canónico genera una versión nueva. Los cambios puramente documentales se hacen como patch-level (v1.7.1) o como actualización in-place sin bump (cuando lo amerita y queda registrado en trazabilidad).

3. **Hallazgos de ejecución se registran en bitácora primero.** Si durante la ejecución aparece un bug, una inconsistencia documental o una observación operativa, se documenta en la bitácora correspondiente (`6B_EJECUCION_DEV.md` o `6C_EJECUCION.md`) antes de tocar los documentos canónicos. Algunos hallazgos terminan en una versión nueva del schema; otros quedan solo como aprendizaje en `Docs/Operacional/Lecciones_Aprendidas.md`.

4. **Los ajustes documentales acumulados van a `6B_SCHEMA_SQL_AJUSTES_PENDIENTES.md`**. Las deudas técnicas ejecutables antes de TEST/PROD van a `Pendiente_pre_produccion.md`.


5. **Sanitización antes de commitear.** Cualquier documento que se suba a GitHub se revisa para que no contenga Project IDs, URLs, passwords, tokens, JWTs ni datos reales de huéspedes.

6. **Patrón consolidado para workflows nuevos (Etapa 6C):**
   - Verificación read-only de contrato real antes de diseñar.
   - Diseño con aprobación explícita.
   - Tests ordenados (no destructivos primero).
   - Sanitización con placeholders.
   - Bitácora detallada por workflow.
   - Lecciones aprendidas si hay gotchas.

   Detalle completo en `6C_CIERRE.md`, sección "Patrón de trabajo establecido".

---

## Próximo paso

Con las Etapas 6B y 6C cerradas, el sistema tiene backend + workflows determinísticos operativos en DEV. **Las próximas etapas se eligen entre 4 opciones:**

### Opción A — Hardening pre-producción

Ejecutar los items de `Pendiente_pre_produccion.md`:
- `NULLIF(TRIM(...))` en funciones write para campos obligatorios de texto.
- Fix de `vista_ocupacion` (25 vs 24 meses).
- Fix cosmético de concatenaciones `nombre + apellido` en vistas.

**Ventaja:** cierra deudas técnicas conocidas antes de TEST/PROD.

### Opción B — Entorno TEST

Replicar DEV en un proyecto Supabase separado para integrar consumidores reales sin riesgo a datos reales.

### Opción C — Webhook MercadoPago

Workflow operativo real que invoca W3 tras un webhook de MP, con deduplicación por `payment_id`.

### Opción D — Bot conversacional (Etapa 4B implementación)

Implementar el bot diseñado en Etapa 4B usando Claude API + Meta API.

**Recomendación documentada en `6C_CIERRE.md`:** A primero, después B. Cerrar deudas técnicas conocidas antes de complicar el sistema con nuevos consumidores.

---

## Pendientes técnicos consolidados

`Pendiente_pre_produccion.md` consolida los items a cerrar antes de TEST/PROD:

1. Hardening de validación SQL en funciones write (agregado durante 6C — W3).
2. Horizonte de `vista_disponibilidad` y `vista_calendario` a 120 días (pendiente histórico).
3. `vista_ocupacion` devuelve 25 meses en vez de 24 (agregado durante 6C — W7).
4. Espacio colgando en concatenación nombre+apellido (agregado durante 6C — W7).
5. RLS configurado (pendiente histórico).
6. Tarifas reales cargadas (pendiente histórico).
7. Feriados productivos cargados (pendiente histórico).
8. Tests de concurrencia formales — Fase 4 (pendiente histórico).
