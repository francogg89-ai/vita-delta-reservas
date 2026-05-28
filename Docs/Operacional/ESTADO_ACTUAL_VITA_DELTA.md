# ESTADO ACTUAL — COMPLEJO VITA DELTA

## Resumen ejecutivo

El sistema de reservas de Complejo Vita Delta tiene **backend Supabase DEV completo (6B v1.7.3 con hardening estructural y de concurrencia aplicados) + workflows n8n operativos (6C) + Etapa 6D cerrada (2026-05-27) + Etapa 7A de correcciones pre-TEST/pre-OPS cerrada (2026-05-28) + entorno TEST levantado, paritario y operativo (7B, cerrada 2026-05-28)**. Los workflows n8n fueron validados contra DEV en Etapa 6C (40 tests funcionales + verificaciones cruzadas) y contra TEST en Etapa 7B (smokes happy path 8/8); en TEST se validó además la cadena transaccional completa W2→W3→W4 end-to-end. Hardening estructural y de concurrencia validados en DEV: 101 tests de hardening + 6 tests de concurrencia real + 9 tests funcionales y 4 estructurales de 7A.

**Etapa actual:** 7B — Levantamiento del entorno TEST. Cerrada (2026-05-28). TEST creado como proyecto Supabase independiente, schema reconstruido desde el canónico v1.7.3 (paridad estructural 10/10 vs DEV), seeds cargados, `pg_cron` activo con ejecuciones reales verificadas, permisos Data API normalizados, 8 workflows `__TEST` importados y validados con cadena end-to-end W2→W3→W4. DEV no se tocó durante 7B salvo consultas read-only aprobadas.

**No es producción.** DEV y TEST son entornos funcionales separados. Falta integración con consumidores reales (webhook MP, bot, frontend), endurecimiento de DEV equivalente al de TEST y validación funcional ampliada (casos de error) sobre TEST.

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
- Schema canónico de referencia: `6B_SCHEMA_SQL.md v1.7.2` (bump documental ejecutado en H8 Frente A; ver sección "Schema canónico actual" abajo).

### Etapa 6C — Reescritura de workflows n8n contra Supabase DEV ✅ Cerrada
- 8 workflows manuales operativos en DEV.
- Documento de cierre formal: `6C_CIERRE.md`.

### Etapa 6D — Hardening pre-producción ✅ Cerrada
- 10 bloques cerrados: H1, H2, H3, H4, H4-bis, H4-ter, H5, H6, H6-bis (hardening estructural) + H7 (tests de concurrencia).
- 1 bloque pendiente: H8 (cierre documental, sin SQL).
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

**Nota histórica:** al cierre de esta alineación, DEV quedó 100% alineado con schema canónico v1.7.1. Posteriormente, durante Etapa 6D, DEV avanzó a v1.7.2 con la aplicación del hardening H2-H6-bis. La actualización del schema canónico a v1.7.2 se ejecutó posteriormente en H8 Frente A.

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

### Etapa 6D — Hardening pre-producción 🚧 H1-H7 cerrados · H8 en curso

**Sesiones 2026-05-26 y 2026-05-27.** Cerrado el frente estructural (H1-H6-bis) y la validación de concurrencia (H7); pendiente cierre documental (H8).

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
- 5 funciones write con patrón `NULLIF(TRIM(...),'')` aplicado en sus extracts de payload.
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

### Etapa 7B — Levantamiento del entorno TEST ✅ Cerrada

**Sesión 2026-05-28.** Cerró el segundo entorno de la estrategia DEV → TEST → OPS → PROD.

**Lo que se construyó:**
- Proyecto Supabase TEST (`vita-delta-test`, sa-east-1, Free tier).
- Schema reconstruido desde el canónico v1.7.3 (no clon de DEV). **Paridad estructural demostrada 10/10** vs DEV: extensiones, enums, tablas (20), vistas (6), funciones del proyecto (13), triggers (13), EXCLUDE (2), CHECK (38), FK (15), índices únicos (27).
- Seeds del Bloque 21 cargados: 5 cabañas, 3 socios, 10 claves de `configuracion_general`, 1 cuenta de cobro, 1 temporada baseline, 1 plantilla.
- `pg_cron` activo en TEST: `expirar_prereservas` (cada 5 min) con ejecuciones reales verificadas (`status=succeeded`); `cleanup_cron_history` (mensual).
- Permisos Data API normalizados: REVOKE EXECUTE sobre las 13 funciones a `PUBLIC`/`anon`/`authenticated`/`service_role`; `Dxtm` residual documentado como aceptado; sin grants Data API útiles para roles no-owner. Owner `postgres` intacto (n8n entra como owner por pooler).
- 8 workflows n8n importados con sufijo `__TEST` y credencial propia `vita_supabase_test`; smokes happy path 8/8.
- Cadena transaccional end-to-end **W2 → W3 → W4 validada** (pre-reserva → pago `en_revision` → reserva confirmada por camino combinado), más verificación cruzada con W1 que confirmó la transición de estado en el motor de disponibilidad.

**IDs de cabaña en TEST:** `1=Bamboo, 2=Madre Selva, 3=Arrebol, 4=Guatemala, 5=Tokio`. **No coinciden con DEV (17-21).** Los IDs no son portables; cada workflow debe usar los del ambiente al que apunta. Lo portable es la estructura lógica de los workflows, no los valores de input.

**Aislamiento:** TEST quedó separado por credencial propia (`vita_supabase_test`), workflows `__TEST` distintos (objetos nuevos en n8n, no modificaciones de los de DEV), y marcadores de ambiente en `source_event` (`n8n_test_w0X_..._manual`) e `idempotency_key` de W2 (`manual_test_...`) que se persisten en tablas y permiten trazabilidad inequívoca DEV vs TEST. DEV intacto durante toda la etapa.

**Datos de prueba en TEST tras el cierre:** pre-reserva 1 (`cancelada_por_cliente`), pre-reserva 2 (`convertida`), reserva 1 (`confirmada`), pago 1 (`confirmado`), bloqueo 1 (Arrebol activo). Conservados como evidencia/fixtures, no limpiados. Reseteo eventual de TEST se diseñará como bloque específico SQL aprobado.

**Alcance del cierre:** happy paths como evidencia suficiente. Casos de error (cabaña inexistente, solapamientos, payloads inválidos, normalización defensiva en campos vacíos, etc.) quedan como pendiente: validación funcional ampliada sobre TEST (ver `Pendiente_pre_produccion.md` 6.4).

**Documento de cierre formal:** `7B_CIERRE.md`.

---

## Estado actual de DEV (post-7A, intacto durante 7B)

**Esta es la fuente vigente del estado de DEV.** Los conteos son los mismos al cierre de 7B: 7B no modificó DEV. La única actividad en DEV durante 7B fueron consultas read-only de diagnóstico (paridad estructural y verificación del rol de conexión n8n).

| Recurso | Conteo | Detalle |
|---|---|---|
| Pre-reservas | 7 | 2 de baseline 6D (`convertida`, `cancelada_por_cliente`) + 5 de tests 7A (todas `cancelada_por_cliente`, terminales) |
| Pagos | 1 | `confirmado` |
| Reservas | 1 | `confirmada`, cabaña 17, 10-13 jul 2026 (`ninos=NULL` tras limpieza 7A) |
| Huéspedes | 3 | id 34, 35 (baseline, `apellido=NULL`) + id 45 ("Test 7A", de tests 7A) |
| Bloqueos | 2 | activos |
| Logs | 26 | en `log_cambios` (+15 vs baseline 7A: 5 creaciones + 5 cancelaciones + 5 transiciones de estado) |
| Filas con `ninos='false'` | 0 | limpieza puntual 7A (pre_reservas 25, 26; reserva 8 → NULL) |
| `configuracion_general` | 10 | incluye `horizonte_disponibilidad_dias=120` |
| `vista_disponibilidad` / `vista_calendario` | horizonte 120 | configurable vía `configuracion_general`, fallback 120 |

Los recursos de tests 7A están en estados terminales (canceladas) y no afectan disponibilidad ni operación. Las pre-reservas y el huésped de test se conservan como evidencia, no se borraron físicamente.

**Estado de DEV al cierre de H7 (histórico, pre-7A):** pre-reservas=2, pagos=1, reservas=1, huéspedes=2, bloqueos=2, logs=11. Conteos idénticos al baseline pre-H7 — confirmó cero side effects persistentes post-cleanup de la sesión de concurrencia (6 tests con fixtures multipaso, todos limpiados).

**Nota:** DEV fue limpiado entre el cierre de 6C y el inicio de 6D (huéspedes de 35→2, pre-reservas de 26→2). Esa limpieza no fue parte del hardening; quedó como contexto operativo.

---

## Estado actual de TEST al cierre de Etapa 7B

**Entorno TEST: proyecto Supabase independiente, alineado funcionalmente con el canónico v1.7.3.**

| Recurso | Conteo | Detalle |
|---|---|---|
| Pre-reservas | 2 | id 1 `cancelada_por_cliente` (ciclo W2→W5); id 2 `convertida` (cadena W2→W3→W4) |
| Pagos | 1 | id 1 `confirmado` (camino combinado de W4 desde pago `en_revision`) |
| Reservas | 1 | id 1 `confirmada`, cabaña 1 (Bamboo), 10-13 jul 2026 |
| Huéspedes | 1 | id 1 "Juan Pérez Test" (reutilizado vía upsert) |
| Bloqueos | 1 | id 1 activo, cabaña 3 (Arrebol), 20-22 nov 2026, motivo `tormenta` |
| Logs | varios | con `source_event` marcado `n8n_test_w0X_..._manual` |
| `configuracion_general` | 10 | idéntica a DEV (sembrada desde el canónico) |
| Horizonte de vistas | 120 | igual que DEV |
| Jobs `pg_cron` | 2 | `expirar_prereservas` (cada 5 min, ejecuciones reales verificadas), `cleanup_cron_history` (mensual) |

**IDs de cabaña:** `1=Bamboo, 2=Madre Selva, 3=Arrebol, 4=Guatemala, 5=Tokio`. **No coinciden con DEV (17-21).**

Datos de prueba conservados como evidencia/fixtures, no limpiados. Reseteo eventual de TEST se diseñará como bloque SQL aprobado separado, no se improvisa.

---

## Estado histórico de DEV al cierre de 6C

**Este estado es histórico. No refleja el estado actual post-limpieza y post-hardening.** La fuente vigente es la sección anterior ("Estado actual de DEV al cierre de H7").

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

**Schema canónico vigente:** `6B_SCHEMA_SQL.md v1.7.3`. El documento refleja el estado real de DEV post-hardening (6D) y post-correcciones pre-TEST/pre-OPS (7A). DEV está 100% alineado funcionalmente con v1.7.3.

**Backup histórico:** `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.2_PRE_PREOPS.md` (estado pre-7A) y `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md` (estado pre-6D), ambos con banner explícito de archivo no canónico, conservados para auditoría/rollback.

**Lo que el bump v1.7.3 documentó (Etapa 7A):**

1. `crear_prereserva`: variable `v_ninos` de `BOOLEAN` a `TEXT`, extract sin cast a BOOLEAN (`NULLIF(TRIM(payload->>'ninos'), '')`). Resuelve el hallazgo de tipo `ninos`.
2. `crear_prereserva`: `canal_pago_esperado` agregado al IF de obligatorios → rebota `payload_invalido` para ausente/vacío/whitespace. Resuelve el hallazgo de `canal_pago_esperado`.
3. `vista_disponibilidad` y `vista_calendario`: horizonte configurable vía `configuracion_general.horizonte_disponibilidad_dias` con fallback 120 (antes hardcoded 60). Forma persistida adoptada.
4. Seed del Bloque 21: clave `horizonte_disponibilidad_dias` agregada (conteo `configuracion_general` 9 → 10).

**Lo que documentó el bump previo v1.7.2 (Etapa 6D):**

1. Patrón defensivo `NULLIF(TRIM(...), '')` en los extracts de payload de las 5 funciones write críticas (`registrar_pago`, `confirmar_reserva`, `crear_prereserva`, `cancelar_prereserva`, `crear_bloqueo`).
2. Fix de rango en `vista_ocupacion` (24 meses exactos).
3. Fix cosmético de `TRIM` en concatenación nombre + apellido en `vista_calendario`, `vista_limpieza_semana` y `vista_prereservas_activas`.
4. Correcciones documentales de alineación con DEV real.
5. Forma persistida de las vistas adoptada (`pg_get_viewdef()`) para garantizar match byte-exacto contra DEV.

**Hallazgos del changelog v1.7.2 — todos resueltos en v1.7.3 (Etapa 7A):**

- ✅ Alineación de tipo `ninos`: resuelto (D-7A-02).
- ✅ Contrato de `canal_pago_esperado`: resuelto (D-7A-01).

**Observación liviana abierta (no bloqueante):** `tipo_valor` sin poblar en las 10 claves de `configuracion_general`. Ver `Pendiente_pre_produccion.md` sección 1.4. A evaluar antes del dashboard OPS.

**El canónico v1.7.3 no crea schema paralelo. Es la única fuente de verdad documental del schema.**

**TEST también está alineado funcionalmente con v1.7.3** — su schema se reconstruyó desde el canónico en Etapa 7B, con paridad estructural 10/10 demostrada vs DEV (ver `7B_CIERRE.md` sección 5).

---

## Próxima etapa — opciones disponibles

Con 6D, 7A y 7B cerradas, las siguientes son **opciones disponibles** a priorizar por Franco (no orden obligatorio, no comprometidas en este documento):

- **Validación funcional ampliada sobre TEST:** ejecutar la batería de casos de error listados en `7B_CIERRE.md` sección 14 (cabaña inexistente, solapamientos, doble pre-reserva, re-confirmación, cancelación de estados no cancelables, payloads inválidos, campos vacíos/whitespace, motivos inválidos, normalización defensiva, pagos tardíos). TEST es el ambiente seguro para ejercitarlos. Ver `Pendiente_pre_produccion.md` 6.4.
- **Endurecimiento de permisos en DEV:** aplicar a DEV un modelo equivalente al de TEST (REVOKE EXECUTE a `PUBLIC` sobre las funciones del proyecto, etc.). No diseñado ni planificado todavía. Ver `Pendiente_pre_produccion.md` 1.5.
- **Diseño del entorno OPS:** operación interna real (Vicky, Franco, Rodrigo, Jennifer), sin consumidores externos automáticos.
- **Webhook MercadoPago / bot / frontend:** integración con consumidores reales, **siempre sobre TEST primero** antes de cualquier consideración productiva.

No avanzar a OPS/PROD, MercadoPago real, bot o frontend público sin decisión explícita.

---

## Pendientes técnicos abiertos

**Items cerrados en Etapa 6D:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Hardening de validación SQL en funciones write | ✅ Cerrado | H2, H3, H4, H4-bis, H4-ter |
| Fix `vista_ocupacion` 25→24 meses | ✅ Cerrado | H5 |
| Espacio colgando en concatenación nombre+apellido | ✅ Cerrado | H6, H6-bis |
| Tests de concurrencia C-1 a C-6 | ✅ Cerrado | H7 |
| Bump documental del schema canónico a v1.7.2 | ✅ Cerrado | H8 Frente A |

**Items cerrados en Etapa 7A:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Horizonte de `vista_disponibilidad`/`vista_calendario` configurable (60→120) | ✅ Cerrado | PreOPS-A6 (D-7A-03) |
| Alineación de tipo `ninos` (función vs columnas) | ✅ Cerrado | Patch `crear_prereserva` v1.7.3 (D-7A-02) |
| Contrato de `canal_pago_esperado` (validación manual) | ✅ Cerrado | Patch `crear_prereserva` v1.7.3 (D-7A-01) |

**Items cerrados en Etapa 7B:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Levantamiento del entorno TEST (proyecto Supabase independiente) | ✅ Cerrado | 7B-1 (D-7B-01) |
| Paridad estructural TEST vs DEV (schema v1.7.3) | ✅ Cerrado | 7B-2 (paridad 10/10) |
| Seeds mínimos en TEST | ✅ Cerrado | 7B-3 |
| `pg_cron` activo en TEST con ejecuciones reales | ✅ Cerrado | 7B-3-cron |
| Permisos Data API normalizados en TEST (REVOKE EXECUTE) | ✅ Cerrado | 7B-GRANTS (D-7B-03, D-7B-05) |
| Workflows `__TEST` importados y validados (happy path 8/8) | ✅ Cerrado | 7B-4 (D-7B-04) |
| Cadena transaccional end-to-end W2→W3→W4 en TEST | ✅ Cerrado | 7B-4 |

**Items pendientes:**

1. **`tipo_valor` sin poblar en `configuracion_general`** — observación de 7A (PreOPS-A6). Las 10 claves tienen `tipo_valor=NULL`. No bloqueante; evaluar antes del dashboard OPS si se usa para render de inputs. Ver `Pendiente_pre_produccion.md` 1.4.
2. **Validación de tipos inválidos no vacíos** — surgido durante hardening. Casos como `id_cabana="abc"` o `fecha_in="no-es-fecha"` siguen rompiendo con error crudo. Fuera del alcance del hardening por strings/whitespace.
3. **Cobertura empírica de ramas `pre_lock` y `unique_violation` de idempotencia** — opcional, no bloqueante. H7 observó empíricamente la rama `post_lock` en C-6. Las otras dos ramas están vigentes en el cuerpo de `crear_prereserva` y son alcanzables por diseño, pero no fueron gatilladas en H7 por timing del test. Queda como cobertura opcional pre-PROD si se considera necesario.
4. **RLS configurado** — pendiente histórico, decisión postergada hasta tener frontend público.
5. **Tarifas reales cargadas** — pendiente histórico.
6. **Feriados productivos cargados** — pendiente histórico.
7. **Endurecimiento de permisos en DEV** — aplicar a DEV el modelo equivalente al de TEST (REVOKE EXECUTE a `PUBLIC` sobre las 13 funciones del proyecto). No diseñado todavía. Ver `Pendiente_pre_produccion.md` 1.5.
8. **Validación funcional ampliada sobre TEST** — batería de casos de error documentada en `7B_CIERRE.md` sección 14. Ver `Pendiente_pre_produccion.md` 6.4.

---

## Lo que NO es Vita Delta hoy

- **No es producción.** Es DEV.
- **No tiene web pública lanzada.** El `index.html` del repo es un prototipo viejo, no la web final.
- **No tiene RLS configurado.** Decisión postergada hasta tener frontend público.
- **No tiene tarifas reales cargadas.** El seed solo tiene una temporada baseline DEV con multiplicador neutro.
- **No tiene feriados productivos cargados.**
- **No tiene cobertura exhaustiva de todos los caminos internos posibles.** H7 validó los escenarios críticos de concurrencia (6 tests aprobados); algunas ramas internas defensivas quedan como cobertura opcional no bloqueante.
- **Tiene entorno TEST levantado y operativo (7B cerrada),** pero sigue sin entornos OPS o PROD, y sin consumidores externos reales conectados (webhook MP, bot, frontend siguen siendo etapas futuras).

---

## Documentación viva del proyecto

- `6B_SCHEMA_SQL.md v1.7.3` — schema canónico SQL vigente. Backups históricos archivados.
- `6B_PLAN_FASES.md` — plan ejecutado, conservado como referencia. Sección 6.8 es fuente para H7.
- `ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md` — arquitectura consolidada de migración.
- `6C_CIERRE.md` — documento formal de cierre de etapa 6C.
- `7A_CIERRE.md` — documento formal de cierre de Etapa 7A (correcciones pre-TEST/pre-OPS).
- `7B_CIERRE.md` — documento formal de cierre de Etapa 7B (levantamiento del entorno TEST).
- `Docs/Bitacora/6B_EJECUCION_DEV.md` — bitácora bloque por bloque de 6B.
- `Docs/Bitacora/6C_EJECUCION.md` — bitácora workflow por workflow de 6C.
- `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` — bitácora bloque por bloque de Etapa 6D (H1-H7 cerrados; H8 en curso).
- `Docs/Operacional/Lecciones_Aprendidas.md` — gotchas operativos (incluye L-6C-01 a L-6C-09 + nuevas lecciones de hardening pendientes de agregar).
- `Pendiente_pre_produccion.md` — pendientes de deploy productivo (items A1-A3 marcados como cerrados; A4 pendiente).
- `DECISIONES_NO_REABRIR.md` — decisiones cerradas no reabribles (incluye decisiones de hardening pendientes de agregar).
- Documentos de arquitectura de Etapas 1-5 (referencia histórica).
- `Workflows/n8n/supabase/*.template.json` — 8 templates sanitizados de 6C.