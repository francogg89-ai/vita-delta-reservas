# ESTADO ACTUAL — COMPLEJO VITA DELTA

## Resumen ejecutivo

El sistema de reservas de Complejo Vita Delta tiene **backend Supabase DEV completo (6B v1.7.2 con hardening estructural y de concurrencia aplicados) + workflows n8n contra DEV operativos (6C) + Etapa 6D cerrada operativamente en H1-H7; pendiente H8 documental**. El contrato n8n ↔ Supabase está validado end-to-end con 40 tests funcionales de 6C + 101 tests de hardening estructural + 6 tests de concurrencia real en DEV.

**Etapa actual:** 6D — Hardening pre-producción. H1-H7 cerrados operativamente; solo queda H8 (cierre documental, sin SQL).

**No es producción.** DEV es entorno funcional con backend + workflows + hardening estructural + hardening de concurrencia validados. Falta entorno TEST + integración con consumidores reales (webhook MP, bot, frontend).

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
- Schema canónico de referencia: `6B_SCHEMA_SQL.md v1.7.1` (DEV está en v1.7.2 con hardening; ver sección "Schema canónico actual" abajo).

### Etapa 6C — Reescritura de workflows n8n contra Supabase DEV ✅ Cerrada
- 8 workflows manuales operativos en DEV.
- Documento de cierre formal: `6C_CIERRE.md`.

### Etapa 6D — Hardening pre-producción 🚧 Cerrada operativamente en H1-H7; pendiente H8 documental
- 10 bloques cerrados: H1, H2, H3, H4, H4-bis, H4-ter, H5, H6, H6-bis (hardening estructural) + H7 (tests de concurrencia).
- 1 bloque pendiente: H8 (cierre documental, sin SQL).
- Bitácora de ejecución: `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`. Documento de cierre formal `6D_CIERRE.md`: pendiente en H8.

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
- `vista_ocupacion` (24 meses exactos desde hardening H5).
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

**Nota histórica:** al cierre de esta alineación, DEV quedó 100% alineado con schema canónico v1.7.1. Posteriormente, durante Etapa 6D, DEV avanzó a v1.7.2 con la aplicación del hardening H2-H6-bis. La actualización del schema canónico a v1.7.2 queda diferida a H8.

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
Manual Trigger → Build Input → Build Payload/Query → Postgres → Build Response

Excepción: W7 incorpora nodo IF para ramificación de validación temprana.

**Convenciones consolidadas:**
- Naming workflows: `vita_w{NN}_{nombre}_supabase`.
- Templates en repo: `Workflows/n8n/supabase/<nombre>.template.json`.
- Source events: `n8n_w{NN}_{nombre}_manual`.
- Wrapper externo unificado con `ok`, `workflow`, `source_event`, `error`, `result`, `executed_at`.
- Normalización defensiva con `nv()` en Build Payload (workaround del bug de validación SQL).
- Verificación cruzada con W1 obligatoria para workflows que modifican disponibilidad.

**Documento de cierre formal:** `6C_CIERRE.md`.

### Etapa 6D — Hardening pre-producción 🚧 En curso

**Sesión 2026-05-26.** Cierre del frente estructural (H1-H6-bis); pendiente concurrencia (H7) y cierre documental (H8).

**Bloques cerrados:**

| Bloque | Descripción | Tests |
|---|---|---|
| H1 | Decisiones previas (patrón canónico, TRIM agresivo) | n/a |
| H2 | Hardening `registrar_pago` (extract defensivo) | 15/15 |
| H3 | Hardening `confirmar_reserva` (extract defensivo) | 11/11 |
| H4 | Hardening `crear_prereserva` (extract defensivo) | 31/31 |
| H4-bis | Hardening `cancelar_prereserva` (extract defensivo) | 9/9 |
| H4-ter | Hardening `crear_bloqueo` (extract defensivo) | 17/17 |
| H5 | Fix `vista_ocupacion` (rango 25→24 meses) | 7/7 |
| H6 | Fix `vista_calendario` + `vista_limpieza_semana` (TRIM) | 7/7 |
| H6-bis | Fix `vista_prereservas_activas` (TRIM) | 5/5 |
| H7 | Tests de concurrencia C-1, C-2, C-5, C-3, C-4, C-6 | 6/6 |

**Resumen:**
- 5 funciones write con patrón `NULLIF(TRIM(...),'')` aplicado a 56 asignaciones totales.
- 4 vistas corregidas (1 de rango, 3 cosméticas).
- 101 tests de hardening estructural con `ok=true`.
- 6 tests de concurrencia real en DEV, todos aprobados (sin deadlocks, sin races, sin doble booking).
- Cero side effects persistentes post-cleanup: conteos finales idénticos a baseline pre-H7 (pagos=1, prereservas=2, reservas=1, huespedes=2, bloqueos=2, logs=11).
- Schema bumped a **v1.7.2** durante H2-H6-bis (documentado en bitácora). H7 no introdujo cambios estructurales.

**Bloques pendientes:**

| Bloque | Descripción | Estado |
|---|---|---|
| H8 | Actualización documental y cierre formal de Etapa 6D | ⏳ Pendiente |

**Bitácora de ejecución:** `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` (H1-H7 documentados). Documento de cierre formal `6D_CIERRE.md`: pendiente en H8.

---

## Estado actual de DEV al cierre de H7

**Esta es la fuente vigente del estado de DEV.**

| Recurso | Conteo | Detalle |
|---|---|---|
| Pre-reservas | 2 | estados terminales (`convertida`, `cancelada_por_cliente`) |
| Pagos | 1 | `confirmado` |
| Reservas | 1 | `confirmada`, cabaña 17, 10-13 jul 2026 |
| Huéspedes | 2 | id 34 ("Juan Pérez Test") y id 35 ("Test W5 Cliente"), ambos con `apellido=NULL` |
| Bloqueos | 2 | activos |
| Logs | 11 | en `log_cambios` |

Conteos idénticos al baseline pre-H7 — confirma cero side effects persistentes post-cleanup de la sesión de concurrencia completa (6 tests con fixtures multipaso, todos limpiados al cierre de cada test).

**Nota:** DEV fue limpiado entre el cierre de 6C y el inicio de 6D (huéspedes de 35→2, pre-reservas de 26→2). Esa limpieza no fue parte del hardening; quedó como contexto operativo.

---

## Estado histórico de DEV al cierre de 6C

**Este estado es histórico. No refleja el estado actual post-limpieza y post-hardening.** La fuente vigente es la sección anterior ("Estado actual de DEV al cierre de H6-bis").

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

## Schema canónico actual

**Schema canónico documentado:** `6B_SCHEMA_SQL.md v1.7.1`.

**Estado real de DEV:** v1.7.2, con hardening H2-H6-bis aplicado sobre v1.7.1. H7 no introdujo cambios estructurales.

**La actualización del schema canónico a v1.7.2 queda diferida a H8.** **Decisión preliminar:** actualizar completo `6B_SCHEMA_SQL.md` a v1.7.2 como schema canónico vigente, conservando backup versionado de v1.7.1 para auditoría/rollback. Plan:

1. Backup/versionado del actual v1.7.1 antes de modificarlo:
   - idealmente commit/tag en Git;
   - opcionalmente copia archivada tipo `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md`.
2. Actualizar `6B_SCHEMA_SQL.md` a v1.7.2 reflejando DEV real post-H6-bis y H7.
3. Agregar changelog v1.7.1 → v1.7.2:
   - H2-H4-ter: hardening de 5 funciones write (`NULLIF(TRIM(...),'')`).
   - H5: fix `vista_ocupacion` (rango 25 → 24 meses).
   - H6/H6-bis: TRIM en vistas con concatenación nombre + apellido.
   - H7: tests de concurrencia aprobados, sin cambios SQL.
   - 101 tests estructurales + 6 tests de concurrencia aprobados.
4. Para funciones y vistas, no reconstruir desde memoria ni desde el viejo canónico: usar cuerpos reales de DEV (`pg_get_functiondef`, `pg_get_viewdef`) o los bloques ya documentados en la bitácora.

**Esta decisión no crea schema paralelo que compita como fuente de verdad. El canónico actualizado pasa a reflejar DEV real.**

**Divergencias conocidas entre schema canónico v1.7.1 y DEV real (descubiertas durante hardening):**
1. `registrar_pago`: líneas de log con `COALESCE(v_validado_por, 'registrar_pago')` y cast `::nivel_log_enum` explícito, no documentados en schema canónico.
2. `crear_prereserva`: `canal_pago_esperado` es opcional en DEV pero el schema canónico lo describía como obligatorio.
3. `crear_prereserva`: `v_ninos` es BOOLEAN en DEV pero el schema canónico lo declaraba TEXT.

Estas divergencias se corrigen en el bump a v1.7.2 durante H8.

---

## Próxima etapa inmediata — Cerrar Etapa 6D

1. **H8** — Actualización documental y cierre formal. Sesión separada (no requiere SQL).

### Después de cerrar 6D — Opción B (recomendada por `6C_CIERRE.md`)

Replicar DEV en un proyecto Supabase separado para integrar consumidores reales sin riesgo a datos reales.

**Ventaja:** habilita pruebas con webhook MP, frontend, etc.
**Costo:** sesión media (2-3 horas) — duplicar schema, seeds, credenciales, parametrizar ambiente en workflows n8n.

### Posteriores — Opciones C y D (orden por decidir)

**C — Webhook MercadoPago:** workflow operativo real que invoca W3 tras webhook de MP, con deduplicación por `payment_id`.

**D — Bot conversacional (Etapa 4B implementación):** implementar el bot diseñado en Etapa 4B usando Claude API + Meta API.

---

## Pendientes técnicos abiertos

**Items cerrados en Etapa 6D:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Hardening de validación SQL en funciones write | ✅ Cerrado | H2, H3, H4, H4-bis, H4-ter |
| Fix `vista_ocupacion` 25→24 meses | ✅ Cerrado | H5 |
| Espacio colgando en concatenación nombre+apellido | ✅ Cerrado | H6, H6-bis |
| Tests de concurrencia C-1 a C-6 | ✅ Cerrado | H7 |

**Items pendientes:**

1. **Horizonte de `vista_disponibilidad` y `vista_calendario` a 120 días** — pendiente histórico. Hoy hardcoded en 60 días; mover a `configuracion_general` cuando se considere oportuno.
2. **Validación de tipos inválidos no vacíos** — surgido durante hardening. Casos como `id_cabana="abc"` o `fecha_in="no-es-fecha"` siguen rompiendo con error crudo. Fuera del alcance del hardening por strings/whitespace.
3. **Bump documental del schema canónico a v1.7.2** — pendiente, se ejecutará en H8. Decisión preliminar: actualizar completo `6B_SCHEMA_SQL.md` con backup versionado de v1.7.1 (ver sección "Schema canónico actual").
4. **Cobertura empírica de ramas `pre_lock` y `unique_violation` de idempotencia** — opcional, no bloqueante. H7 observó empíricamente la rama `post_lock` en C-6. Las otras dos ramas están vigentes en el cuerpo de `crear_prereserva` y son alcanzables por diseño, pero no fueron gatilladas en H7 por timing del test. Queda como cobertura opcional pre-PROD si se considera necesario.
5. **RLS configurado** — pendiente histórico, decisión postergada hasta tener frontend público.
6. **Tarifas reales cargadas** — pendiente histórico.
7. **Feriados productivos cargados** — pendiente histórico.

---

## Lo que NO es Vita Delta hoy

- **No es producción.** Es DEV.
- **No tiene web pública lanzada.** El `index.html` del repo es un prototipo viejo, no la web final.
- **No tiene RLS configurado.** Decisión postergada hasta tener frontend público.
- **No tiene tarifas reales cargadas.** El seed solo tiene una temporada baseline DEV con multiplicador neutro.
- **No tiene feriados productivos cargados.**
- **No tiene cobertura exhaustiva de todos los caminos internos posibles.** H7 validó los escenarios críticos de concurrencia (6 tests aprobados); algunas ramas internas defensivas quedan como cobertura opcional no bloqueante.
- **No tiene entorno TEST levantado.** DEV es el único ambiente operativo.
- **No tiene consumidores reales conectados.** Webhook MP, bot conversacional y frontend son etapas futuras.
- **No tiene schema canónico actualizado a v1.7.2.** DEV ya está en v1.7.2 (hardening), pero el documento `6B_SCHEMA_SQL.md` sigue en v1.7.1. Decisión diferida a H8.

---

## Documentación viva del proyecto

- `6B_SCHEMA_SQL.md v1.7.1` — schema canónico SQL (DEV está en v1.7.2; actualización diferida a H8).
- `6B_PLAN_FASES.md` — plan ejecutado, conservado como referencia. Sección 6.8 es fuente para H7.
- `ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md` — arquitectura consolidada de migración.
- `6C_CIERRE.md` — documento formal de cierre de etapa 6C.
- `Docs/Bitacora/6B_EJECUCION_DEV.md` — bitácora bloque por bloque de 6B.
- `Docs/Bitacora/6C_EJECUCION.md` — bitácora workflow por workflow de 6C.
- `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` — bitácora bloque por bloque de Etapa 6D (H1-H6-bis cerrados; H7-H8 pendientes).
- `Docs/Operacional/Lecciones_Aprendidas.md` — gotchas operativos (incluye L-6C-01 a L-6C-09 + nuevas lecciones de hardening pendientes de agregar).
- `Pendiente_pre_produccion.md` — pendientes de deploy productivo (items A1-A3 marcados como cerrados; A4 pendiente).
- `DECISIONES_NO_REABRIR.md` — decisiones cerradas no reabribles (incluye decisiones de hardening pendientes de agregar).
- Documentos de arquitectura de Etapas 1-5 (referencia histórica).
- `Workflows/n8n/supabase/*.template.json` — 8 templates sanitizados de 6C.