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
├── Pendiente_pre_produccion.md                  ← Cambios y configuraciones a aplicar antes de PROD
│
└── AppsScript/
    ├── validaciones_vita_delta_v3.gs            ← Validaciones de datos sobre Sheets (Fase 4 de Etapa 5)
    ├── protecciones_vita_delta_v1.gs            ← Protecciones por entorno (Fase 5 de Etapa 5)
    └── auditoria_fase6_v2.gs                    ← Auditoría de estructura y datos (Fase 6 de Etapa 5)
```

Documentos relacionados que viven fuera de esta carpeta:

- Bitácora de ejecución de la migración: `Docs/Bitacora/6B_EJECUCION_DEV.md`.
- Decisiones arquitectónicas: `Docs/Arquitectura/`.
- Contratos técnicos de workflows actuales: `Docs/API_CONTRACTS/`.

---

## Estado actual de la implementación

| Etapa | Stack | Estado |
|---|---|---|
| Etapa 5 (Sheets DEV/TEST + workflows core) | Google Sheets + n8n | Cerrada — validada en DEV y TEST |
| Etapa 6B (migración a PostgreSQL/Supabase) | Supabase + PostgreSQL | Fases 0-3 ejecutadas en DEV — alineación final v1.7.1 pendiente |
| Reescritura de workflows n8n contra Supabase | Supabase + n8n | No iniciada — pendiente del cierre de 6B |

**Stack operativo productivo actual:** Google Sheets como fuente de verdad + workflows n8n apuntando a Sheets. Esto sigue siendo verdadero **mientras la migración a Supabase no esté completamente cerrada y los workflows no estén reescritos**.

---

## Documento operativo vigente

El documento técnico canónico para la etapa actual es:

```txt
6B_SCHEMA_SQL.md (v1.7.1)
```

Es la fuente de verdad para:
- Próximas recreaciones de DEV (si fuera necesario).
- Ejecución futura en TEST.
- Ejecución futura en PROD.
- Cualquier consulta sobre estructura de tablas, funciones, triggers, vistas, constraints o seed mínimo.

El plan operativo correspondiente (`6B_PLAN_FASES.md v1.1`) ya fue ejecutado y se conserva como referencia histórica/operativa para auditar la ejecución o recrear entornos.

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

- Los IDs de Sheets se configuran por entorno y **nunca se hardcodean** dentro de los workflows n8n.
- Las credenciales de Supabase (Project ID, Project URL, database password, anon key, service role key, connection strings) viven **fuera del repositorio**: en gestor de contraseñas, en `.env` no versionado, o en credentials de n8n cuando aplique.
- Los placeholders `__SUPABASE_PROJECT_ID_DEV__`, `__SUPABASE_PROJECT_URL_DEV__`, etc. deben reemplazarse localmente al momento de ejecutar; nunca commitear con valores reales.

### Entornos contemplados

| Entorno | Sheets | Supabase |
|---|---|---|
| DEV | `VITA_DELTA_DEV` (creado, validado) | Proyecto DEV (Bloques 1-22 ejecutados) |
| TEST | `VITA_DELTA_TEST` (creado, validado) | No iniciado |
| PROD | `VITA_DELTA_PROD` (no activado) | No iniciado |

PROD no se activa hasta que TEST esté completamente validado en cada stack.

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

Si aparece una contradicción entre un documento de esta carpeta y un documento de arquitectura cerrado, **prevalecen los documentos de arquitectura**, salvo que se documente explícitamente una corrección posterior (con bump de versión, nota técnica o registro en bitácora).

---

## Cómo se trabaja en esta carpeta

1. **No se reabren decisiones cerradas.** Si un documento de arquitectura cerró una decisión, esta carpeta la respeta. Las correcciones se hacen mediante patches versionados (v1.7 → v1.7.1) o bumps menores, no reabriendo conceptos.

2. **Las versiones se bumpean explícitamente.** Cada cambio operativo real al schema canónico genera una versión nueva. Los cambios puramente documentales se hacen como patch-level (v1.7.1) o como actualización in-place sin bump (cuando lo amerita y queda registrado en trazabilidad).

3. **Hallazgos de ejecución se registran en bitácora primero.** Si durante la ejecución aparece un bug, una inconsistencia documental o una observación operativa, se documenta en `Docs/Bitacora/6B_EJECUCION_DEV.md` antes de tocar los documentos canónicos. Algunos hallazgos terminan en una versión nueva del schema; otros quedan solo como aprendizaje.

4. **Los ajustes documentales acumulados van a `6B_SCHEMA_SQL_AJUSTES_PENDIENTES.md`** y se integran al schema en un bump posterior, evitando una cadena de patches sucesivos durante la ejecución.

5. **Sanitización antes de commitear.** Cualquier documento que se suba a GitHub se revisa para que no contenga Project IDs, URLs, passwords, tokens, JWTs ni datos reales de huéspedes.

---

## Próximo paso

El trabajo inmediato es **cerrar formalmente la Etapa 6B en DEV** y arrancar la siguiente etapa:

1. Alinear DEV con `6B_SCHEMA_SQL.md v1.7.1` ejecutando la actualización de `obtener_disponibilidad_rango()`.
2. Commitear documentación post-DEV (schema, bitácora, arquitectura, plan, pendientes).
3. Confirmar cierre documental de Fase 4 (tests de concurrencia) y Fase 5 (cierre formal de DEV) según bitácora.
4. Generar `6B_REESCRITURA_WORKFLOWS.md` en esta carpeta para guiar la adaptación de los workflows n8n contra Supabase.
5. Reescribir workflows n8n contra Supabase, validar en TEST, y finalmente migrar PROD.

Las etapas posteriores (capa conversacional con Claude API, integración con WhatsApp/Instagram, MercadoPago real, web pública, RLS, contabilidad) se planifican cuando llegue el momento de cada una. Ninguna se inicia antes de cerrar la base de datos en Supabase como fuente de verdad operativa.
