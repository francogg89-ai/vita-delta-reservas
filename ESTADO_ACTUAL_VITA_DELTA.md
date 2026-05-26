# ESTADO ACTUAL — COMPLEJO VITA DELTA

## Resumen ejecutivo

El sistema de reservas de Complejo Vita Delta tiene **backend Supabase DEV completo (6B v1.7.1) + workflows n8n contra DEV operativos (6C)**. El contrato n8n ↔ Supabase está validado end-to-end con 40 tests funcionales sobre los 8 workflows críticos.

**Próxima etapa:** por decidir entre 4 opciones (ver al final del documento). Recomendación: hardening pre-producción (Opción A) antes de habilitar consumidores reales.

**No es producción.** DEV es entorno funcional con backend + workflows validados. Falta hardening final + entorno TEST + integración con consumidores reales (webhook MP, bot, frontend).

---

## Etapas de DISEÑO completadas

### Etapa 1 — Arquitectura base ✅ Cerrada
- Objetivo general del sistema.
- Herramientas elegidas: inicialmente Google Sheets + n8n + Apps Script, posteriormente migrado a Supabase.
- Modelo de datos lógico.
- Flujo CONSULTAS → PRE_RESERVAS → RESERVAS.
- Principios de consistencia.
- Migrabilidad a Supabase (que terminó ocurriendo).

### Etapa 2 — Motor de disponibilidad ✅ Cerrada
- Reglas de check-in / check-out base.
- Domingo como primer día con check-in 18:00.
- Escalonamiento operativo por carga de limpieza.
- Overrides operativos.
- Race conditions y revalidación antes de confirmar.

### Etapa 3 — Motor de precios ✅ Cerrada
- `fecha_in` inclusive / `fecha_out` exclusive.
- Tipos de cabaña, temporadas, multiplicadores.
- TARIFAS, jerarquía de cálculo.
- Feriados, estadías largas, personas extra, descuentos.
- Seña y saldo.
- EVENTOS_ESPECIALES (Año Nuevo fuera del motor estándar).

### Etapa 4A — Motor de Reservas Determinístico ✅ Cerrada (diseño)
- Estados de pre-reserva, reserva, pago.
- Locks y secuenciamiento.
- Idempotencia.
- Revalidación post-lock.

### Etapa 4B — Bot Conversacional con IA ✅ Cerrada (diseño)
- Reglas para que la IA no ejecute lógica crítica.
- Llamadas a workflows determinísticos cuando la IA necesite operar.
- Prompt base, caching, edge cases.

### Etapa 5 — Implementación vertical mínima ✅ Cerrada (diseño)

### Etapa 6A — Decisión de migración ✅ Cerrada
- Análisis: Google Sheets + Apps Script alcanzaban límites operativos.
- Decisión: migrar a Supabase/PostgreSQL.

### Etapa 6B — Migración a Supabase ✅ Cerrada (diseño + implementación)
- Schema completo en PostgreSQL.
- Plan de fases de ejecución.
- Schema canónico: `6B_SCHEMA_SQL.md v1.7.1`.

### Etapa 6C — Reescritura de workflows n8n contra Supabase DEV ✅ Cerrada
- 8 workflows manuales operativos en DEV.
- Documento de cierre formal: `6C_CIERRE.md`.

---

## Fases de IMPLEMENTACIÓN en Supabase DEV

**Bloques 1-22 ejecutados.** Fases 0, 1, 2 y 3 cerradas.

### Fase 1 — Schema base ✅ Cerrada
**Bloques 1-8 ejecutados:** extensiones (pg_cron, btree_gist), 6 enums, 20 tablas, todas las constraints, índices, 2 EXCLUDE constraints estructurales (uno sobre reservas, uno sobre bloqueos).

### Fase 2 — Funciones y triggers ✅ Cerrada
**Bloques 9-19 ejecutados:** 12 funciones operativas + 13 triggers automáticos.

Funciones operativas validadas end-to-end:
- `normalizar_telefono()` + trigger
- `upsert_huesped()`
- `validar_disponibilidad()`
- `obtener_disponibilidad_rango()`
- `crear_prereserva()` — **PUERTA ÚNICA** para crear pre-reservas
- `confirmar_reserva()` — ambos caminos: estricto + combinado
- `cancelar_prereserva()`
- `crear_bloqueo()` — específico + total
- `registrar_pago()` — incluyendo caso v1.3
- `expirar_prereservas_vencidas()`

Triggers:
- 1 trigger para normalización de teléfono.
- 9 triggers `BEFORE UPDATE` para `updated_at`.
- 3 triggers `AFTER UPDATE OF estado` para log automático de transiciones.

### Fase 3 — Vistas + seed operativo + pg_cron ✅ Cerrada
**Bloques 20-22 ejecutados.**

**6 vistas operativas creadas:**
- `vista_disponibilidad` (60 días forward).
- `vista_calendario` (60 días forward).
- `vista_prereservas_activas` (cronómetro en vivo).
- `vista_ocupacion` (matriz ~24 meses — micro-bug del +1 mes documentado en pendientes).
- `vista_calendario_semanal` (7 días forward).
- `vista_limpieza_semana` (7 días forward).

**Seed operativo cargado en DEV:**
- 5 cabañas reales: Bamboo (id=17), Madre Selva (id=18), Arrebol (id=19), Guatemala (id=20), Tokio (id=21).
- 3 socios: Franco, Rodrigo, Remo.
- 1 cuenta de cobro activa cargada en DEV (datos reales omitidos por seguridad documental).
- 10 claves de configuración (incluyendo `hora_checkout_domingo` agregada por hotfix v1.7).
- 1 temporada baseline DEV (multiplicador neutro, no productiva).
- 1 plantilla de mensaje.

**2 jobs pg_cron activos:**
- `expirar_prereservas` (cada 5 min) — validado end-to-end procesando pre-reserva real.
- `cleanup_cron_history` (día 1 de cada mes a las 03:00 UTC).

### Hotfix v1.7 — Regla `hora_checkout_domingo` ✅ Aplicado en DEV
Implementa la regla operativa de check-out dominical a las 16:00 (por última lancha colectiva). Función `crear_prereserva` actualizada. 4 tests funcionales validados.

### Alineación 6B v1.7.1 ✅ Aplicada en DEV
**Pre-etapa 6C, 2026-05-25.**

Actualización de `obtener_disponibilidad_rango()` para aplicar el CASE de domingo en `hora_checkout_base`. Ejecutado con `CREATE OR REPLACE FUNCTION` sin pop-up destructivo. 5 verificaciones OK post-deploy.

**DEV quedó 100% alineado con schema canónico v1.7.1.**

Documentación: `BITACORA_ENTRADA_CIERRE_6B_v1.7.1.md`.

### Etapa 6C — Reescritura de workflows n8n contra Supabase DEV ✅ Cerrada
**2026-05-25 a 2026-05-26.**

**8 workflows operativos en DEV** con 40 tests funcionales aprobados y 3 verificaciones cruzadas end-to-end:

| Workflow | Función / vista | Tests |
|---|---|---|
| W0 — smoke test | conexión Supabase | 1 query |
| W1 — consultar disponibilidad | `obtener_disponibilidad_rango(date, date, bigint)` | 4 tests
| W2 — crear pre-reserva | `crear_prereserva(jsonb)` | 5 tests |
| W3 — registrar pago | `registrar_pago(jsonb)` | 4 tests |
| W4 — confirmar reserva | `confirmar_reserva(jsonb)` | 5 tests |
| W5 — cancelar pre-reserva | `cancelar_prereserva(jsonb)` | 6 tests + 1 cruzado |
| W6 — crear bloqueo | `crear_bloqueo(jsonb)` | 8 tests + 2 cruzados |
| W7 — vistas operativas | 6 vistas read-only | 7 tests |

**Patrón establecido y reutilizable:**

```
Manual Trigger → Build Input → Build Payload/Query → Postgres → Build Response
```

Excepción: W7 incorpora nodo IF para ramificación de validación temprana.

**Convenciones consolidadas:**
- Naming workflows: `vita_w{NN}_{nombre}_supabase`.
- Templates en repo: `Workflows/n8n/supabase/<nombre>.template.json`.
- Source events: `n8n_w{NN}_{nombre}_manual`.
- Wrapper externo unificado con `ok`, `workflow`, `source_event`, `error`, `result`, `executed_at`.
- Normalización defensiva con `nv()` en Build Payload (workaround del bug de validación SQL).
- Verificación cruzada con W1 obligatoria para workflows que modifican disponibilidad.

**Documento de cierre formal:** `6C_CIERRE.md`.

### Estado de DEV al cierre de 6C

| Recurso | ID | Estado |
|---|---|---|
| Pre-reserva | 25 | `convertida` (terminal) |
| Pre-reserva | 26 | `cancelada_por_cliente` (terminal) |
| Pago | 11 | `confirmado`, asociado a reserva 8 |
| Reserva | 8 | `confirmada`, cabaña 17, 10-13 jul 2026 |
| Huésped | 34 | `total_reservas=1`, `primera_reserva_fecha=2026-07-10` |
| Huésped | 35 | `total_reservas=0` |
| Bloqueo | 6 | activo, cabaña 19, 15-18 sep 2026, motivo `mantenimiento` |
| Bloqueo | 7 | activo, **total**, 20-22 nov 2026, motivo `tormenta` |
| Bloqueos | 1-5 | activos (origen pre-6C, no creados en esta etapa) |

---

## Schema canónico actual: `6B_SCHEMA_SQL.md v1.7.1`

**DEV está 100% alineado con v1.7.1.** Alineación final ejecutada el 2026-05-25 antes de abrir 6C.

---

## Próxima etapa — Por decidir

Con 6C cerrado, las opciones inmediatas son 4. La recomendación **A primero, después B** está documentada en `6C_CIERRE.md`.

### Opción A — Hardening pre-producción

Ejecutar los items de `Pendiente_pre_produccion.md`:
- `NULLIF(TRIM(...))` en funciones write para campos obligatorios de texto.
- Fix de `vista_ocupacion` (25 vs 24 meses).
- Fix cosmético de concatenaciones `nombre + apellido` en vistas (o `upsert_huesped`).

**Ventaja:** cierra deudas técnicas conocidas antes de TEST/PROD.
**Costo:** sesión corta (1-2 horas), poco riesgo.

### Opción B — Entorno TEST

Replicar DEV en un proyecto Supabase separado para integrar consumidores reales sin riesgo a datos reales.

**Ventaja:** habilita pruebas con webhook MP, frontend, etc.
**Costo:** sesión media (2-3 horas) — duplicar schema, seeds, credenciales, parametrizar ambiente en workflows n8n.

### Opción C — Webhook MercadoPago

Workflow operativo real que invoca W3 tras webhook de MP, con deduplicación por `payment_id`.

**Ventaja:** primer flujo productivo end-to-end.
**Costo:** sesión larga (3-4 horas) — diseño del webhook + integración con W4.

### Opción D — Bot conversacional (Etapa 4B implementación)

Implementar el bot diseñado en Etapa 4B usando Claude API + Meta API.

**Ventaja:** habilita canal principal de consultas (Instagram + WhatsApp).
**Costo:** sesión larga, requiere Meta API conectada.

**Recomendación documentada en `6C_CIERRE.md`:** **A primero, después B.** Cerrar deudas técnicas conocidas antes de complicar el sistema con nuevos consumidores.

---

## Pendientes técnicos abiertos

`Pendiente_pre_produccion.md` consolida los items a cerrar antes de TEST/PROD:

1. **Hardening de validación SQL en funciones write** — agregado durante 6C (W3).
2. **Horizonte de `vista_disponibilidad` y `vista_calendario` a 120 días** — pendiente histórico (Franco confirmó 120 da margen).
3. **`vista_ocupacion` devuelve 25 meses en vez de 24** — agregado durante 6C (W7).
4. **Espacio colgando en concatenación nombre+apellido** — agregado durante 6C (W7).
5. **RLS configurado** — pendiente histórico, decisión postergada hasta tener frontend público.
6. **Tarifas reales cargadas** — pendiente histórico.
7. **Feriados productivos cargados** — pendiente histórico.
8. **Tests de concurrencia formales (Fase 4)** — pendiente histórico, diferido como hardening pre-TEST/PROD.

---

## Lo que NO es Vita Delta hoy

- **No es producción.** Es DEV.
- **No tiene web pública lanzada.** El `index.html` del repo es un prototipo viejo, no la web final.
- **No tiene RLS configurado.** Decisión postergada hasta tener frontend público.
- **No tiene tarifas reales cargadas.** El seed solo tiene una temporada baseline DEV con multiplicador neutro.
- **No tiene feriados productivos cargados.**
- **No tiene tests de concurrencia formales completos.**
- **No tiene entorno TEST levantado.** DEV es el único ambiente operativo.
- **No tiene consumidores reales conectados.** Webhook MP, bot conversacional y frontend son etapas futuras.

---

## Documentación viva del proyecto

- `6B_SCHEMA_SQL.md v1.7.1` — schema canónico SQL.
- `6B_PLAN_FASES.md` — plan ejecutado, conservado como referencia.
- `ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md` — arquitectura consolidada de migración.
- `6C_CIERRE.md` — documento formal de cierre de etapa 6C.
- `Docs/Bitacora/6B_EJECUCION_DEV.md` — bitácora bloque por bloque de 6B.
- `Docs/Bitacora/6C_EJECUCION.md` — bitácora workflow por workflow de 6C.
- `Docs/Operacional/Lecciones_Aprendidas.md` — gotchas operativos (incluye L-6C-01 a L-6C-09).
- `Pendiente_pre_produccion.md` — pendientes de deploy productivo.
- Documentos de arquitectura de Etapas 1-5 (referencia histórica).
- `Workflows/n8n/supabase/*.template.json` — 8 templates sanitizados de 6C.
