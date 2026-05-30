# ESTADO ACTUAL — COMPLEJO VITA DELTA

## Resumen ejecutivo

El sistema de reservas de Complejo Vita Delta tiene **backend Supabase DEV completo (6B v1.7.3 con hardening estructural y de concurrencia aplicados) + workflows n8n operativos (6C) + Etapa 6D cerrada (2026-05-27) + Etapa 7A de correcciones pre-TEST/pre-OPS cerrada (2026-05-28) + entorno TEST levantado, paritario y operativo (7B, cerrada 2026-05-28) + validación funcional ampliada sobre TEST (7C, cerrada 2026-05-28) + limpieza/reset de TEST (7D, cerrada 2026-05-28) + endurecimiento de permisos Data API en DEV (7E, cerrada 2026-05-28) + entorno OPS de operación real interna levantado, paritario, seguro y conectado a n8n (8A, cerrada 2026-05-29)**. Los workflows n8n fueron validados contra DEV en Etapa 6C (40 tests funcionales + verificaciones cruzadas) y contra TEST en Etapa 7B (smokes happy path 8/8) y 7C (validación funcional ampliada de caminos no-felices); en TEST se validó además la cadena transaccional completa W2→W3→W4 end-to-end. Hardening estructural y de concurrencia validados en DEV: 101 tests de hardening + 6 tests de concurrencia real + 9 tests funcionales y 4 estructurales de 7A.

**Etapa actual:** 8A — Levantamiento del entorno OPS (operación real interna). Cerrada (2026-05-29). Se creó `vita-delta-ops` (`OPS_REF=lpiatqztudxiwdlcoasv`, sa-east-1, Free tier, PostgreSQL 17.6) como tercer entorno de la estrategia DEV → TEST → OPS → PROD y **primer entorno de operación real interna** (D-8-09). Schema reconstruido desde el canónico `6B_SCHEMA_SQL.md v1.7.3` en 7 tandas (4.1-4.7), con **paridad estructural P01-P10 10/10** (2 extensiones, 4 enums, 20 tablas, 6 vistas, 13 funciones, 13 triggers, 2 EXCLUDE, 38 CHECK, 15 FK, 27 índices). Seeds reales sembrados: 5 cabañas (IDs **1-5**), 3 socios (Franco 33.33 / Rodrigo 33.34 / Remo 33.33), 10 claves de `configuracion_general` (horizonte 120), 1 cuenta de cobro real y activa (alias playario), 1 temporada baseline, 1 plantilla. Seguridad: **OPS nació más cerrado que TEST** gracias al switch "Automatically expose new tables = OFF" desde la creación — 0 funciones con EXECUTE a Data API y 0 grants RW a roles Data API sobre tablas; el `REVOKE EXECUTE` idempotente se aplicó igual como barrera explícita (Opción B). Default privileges cerrado sin ejecución (D-8-13): los defaults del rol `postgres` conceden solo `Dxtm` inocuo; los 21 defaults amplios son del rol de plataforma `supabase_admin` y no se tocan. `pg_cron` activo con 2 jobs y una corrida real `succeeded` verificada. Credencial n8n `vita_supabase_ops` creada, probada y verificada por identidad (lee las 5 cabañas reales de OPS). Verificación consolidada 17/17. Smoke de cierre solo lectura (D-8-12): el primer write real será una reserva real por 8B. Decisiones D-8-09, D-8-13 (+ confirmación de cumplimiento de D-8-03). DEV/TEST/PROD no se tocaron. Documento de cierre: `8A_CIERRE.md`.

**Etapa previa:** 7E — Endurecimiento de permisos Data API en DEV. Cerrada (2026-05-28). Se aplicó a DEV el `REVOKE EXECUTE` sobre las 13 funciones del proyecto a `PUBLIC`/`anon`/`authenticated`/`service_role`, en paridad con el modelo de TEST (7B-GRANTS), por el método de cuatro bloques separados (snapshot read-only → cambio transaccional `BEGIN/COMMIT` con re-gate anti-error-de-entorno por identidad exacta de cabañas DEV 17-21 → verificación posterior → cierre documental). Owner `postgres` intacto y ejecutando por ownership (n8n no afectado); 0 fugas de EXECUTE verificadas; schema v1.7.3 sin cambios (201 funciones / 6 vistas / 19 triggers). De las 201 funciones de `public`, solo 13 son del proyecto (las otras 188 son de `btree_gist`, owner `supabase_admin`, no se tocaron). El hallazgo A5 (residual amplio de permisos de tabla a roles Data API en DEV: SELECT/escritura completos, más amplio que el `Dxtm` de TEST) quedó **fuera de alcance por decisión** (Opción 1 — 7E estricta) y se registró como pendiente nuevo `Pendiente_pre_produccion.md` 1.7. Decisiones D-7E-01, D-7E-02. DEV es el único entorno tocado; TEST/OPS/PROD intactos. Documento de cierre: `7E_CIERRE.md`.

**Etapa previa:** 7D — Limpieza/reset del entorno TEST. Cerrada (2026-05-28). Se diseñó y ejecutó un bloque dedicado de reset con SQL explícito y aprobado, en tres partes separadas (snapshot read-only → limpieza transaccional atómica → verificación posterior), con doble gate anti-error-de-entorno por identidad exacta de las 5 cabañas TEST. Se vaciaron las 6 tablas transaccionales con datos (`pagos`, `reservas`, `pre_reservas`, `bloqueos`, `huespedes`, `log_cambios`) vía `DELETE` en orden seguro por FKs, sin `DROP/TRUNCATE ... CASCADE`, y se resetearon sus secuencias a 1. El seed estructural (11 tablas), el cron, las funciones/vistas/triggers, los grants y los workflows `__TEST` quedaron intactos. **TEST quedó como entorno limpio.** Decisiones D-7D-01 (reset de secuencias) y D-7D-02 (vaciado de `log_cambios` con evidencia documentada). DEV/OPS/PROD no se tocaron; schema canónico v1.7.3 sin modificar. Documento de cierre: `7D_CIERRE.md`.

**Etapa previa:** 7C — Validación funcional ampliada sobre TEST. Cerrada (2026-05-28). Se ejecutaron sistemáticamente los caminos no-felices de los 8 workflows `__TEST` (errores controlados, edge cases, validaciones defensivas, condiciones de borde) que 7B dejó fuera de alcance. Resultado: **54 verificaciones conformes (48 casos funcionales del Grupo A + 6 verificaciones transversales TR-01/TR-02), 0 fallos inesperados, 1 mutación no planificada pero válida y comprendida (bloqueo id 2)**. Idempotencia: ramas `post_lock` (H7) y `pre_lock` (7C) cubiertas empíricamente; `unique_violation` queda como opcional no bloqueante. DEV no se tocó durante 7C; el schema canónico v1.7.3 no se modificó.

**No es producción pública.** DEV, TEST y OPS son entornos separados: DEV (desarrollo), TEST (pruebas funcionales completas) y OPS (operación real interna, recién levantado en 8A — datos reales, sin consumidores externos automáticos todavía). Falta integración con consumidores reales (webhook MP, bot, frontend) y el entorno PROD público. El endurecimiento de DEV en EXECUTE sobre funciones quedó en paridad con TEST en 7E; resta solo el residual amplio de permisos de tabla a roles Data API en DEV (hallazgo A5, pendiente 1.7), fuera de alcance por decisión — OPS nació sin ese problema. La validación funcional ampliada sobre TEST quedó cubierta en 7C.

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

## Estado actual de OPS al cierre de Etapa 8A

**Entorno OPS (`vita-delta-ops`): proyecto Supabase independiente, primer entorno de operación real interna, paritario con el canónico v1.7.3, seguro y conectado a n8n.**

**Ficha:** `OPS_REF=lpiatqztudxiwdlcoasv` · sa-east-1 (São Paulo) · Free tier · PostgreSQL 17.6 · pooler `aws-1-sa-east-1.pooler.supabase.com:6543` · credencial n8n `vita_supabase_ops` · modelo Opción A (n8n como `postgres` por pooler, sin consumidores Data API, RLS postergado).

**Estructura (paridad P01-P10 10/10 vs canónico):** 2 extensiones (btree_gist, pg_cron), 4 enums, 20 tablas, 6 vistas, 13 funciones propias, 13 triggers, 2 EXCLUDE, 38 CHECK, 15 FK, 27 índices.

| Recurso | Conteo | Detalle |
|---|---|---|
| Cabañas | 5 | IDs **1-5**: Bamboo=1, Madre Selva=2, Arrebol=3, Guatemala=4, Tokio=5 (grandes 3/5, chicas 2/4) |
| Socios | 3 | Franco 33.33, Rodrigo 33.34, Remo 33.33 (suma 100.00) |
| `configuracion_general` | 10 | incluye `horizonte_disponibilidad_dias=120` |
| Cuentas de cobro | 1 | real y **activa**: alias playario, transferencia_mp, titular Franco Guaglianone |
| Temporadas | 1 | baseline "Baseline OPS 2026-2028" (neutra, no productiva) |
| Plantillas | 1 | `prereserva_creada` |
| Reservas / pre-reservas / pagos / bloqueos / huéspedes | 0 | sin datos transaccionales (smoke de cierre solo lectura; primer write real por 8B) |
| Jobs `pg_cron` | 2 | `expirar_prereservas` (cada 5 min, 1 corrida real `succeeded` verificada), `cleanup_cron_history` (mensual) |
| Horizonte de vistas | 120 | con 5 cabañas: `vista_disponibilidad`=600 filas, `vista_ocupacion`=120, `vista_calendario_semanal`=35; vistas de reservas en 0 (sin reservas) |

**IDs de cabaña en OPS:** `1-5`. Coinciden con TEST por casualidad (ambos nacieron limpios con secuencia desde 1), pero son entornos separados — los workflows `__OPS` usan los IDs reales de OPS. En el form de carga de 8B la cabaña se elige por **nombre**, no por ID (D-8-10).

**Seguridad:** 0 funciones con EXECUTE a roles Data API, 0 grants SELECT/INSERT/UPDATE/DELETE a roles Data API sobre tablas, residual solo `Dxtm` inocuo. OPS nació más cerrado que TEST (switch correcto desde el día cero); el REVOKE EXECUTE se aplicó igual como barrera explícita (Opción B). Default privileges del rol `postgres` conceden solo `Dxtm` inocuo → objetos futuros nacen cerrados (D-8-13).

**Verificación consolidada (Bloque 9):** 17/17 checks OK.

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

Con 6D, 7A, 7B, 7C, 7D, 7E y **8A** cerradas, el entorno OPS ya está levantado y listo. Las siguientes son **opciones disponibles** a priorizar por Franco (orden sugerido, no comprometidas en este documento):

- **8B — Capa de carga de Vicky (siguiente natural):** Form Trigger n8n (usable desde celular) que encadena `crear_prereserva` → `registrar_pago` → `confirmar_reserva` en una acción, con monto total + seña editable (50% pre-rellenado pero editable, D-8-04) y elección de cabaña **por nombre** (D-8-10). Recordar: verificar el contrato real de las funciones con `pg_get_functiondef` antes de mapear el campo `operador`/`cargado_por` (D-8-06); IDs reales de cabaña en OPS son 1-5.
- **8C — Calendarios visuales por evento** (nuestro + el de Jenny, `vista_limpieza_semana`). Formato (Sheet repintado vs HTML servido) aún por decidir al diseñar 8C.
- **8D — Bloqueos operativos + cierre de Etapa 8.**
- **Residual de permisos de tabla en DEV (hallazgo A5 / pendiente 1.7):** decidir si se revoca el set amplio sobre tablas/vistas/secuencias a roles Data API en DEV, o se acepta y documenta como definitivo. No urgente (sin consumidores Data API activos). OPS ya nació sin ese problema. Ver `Pendiente_pre_produccion.md` 1.7.
- **Webhook MercadoPago / bot / frontend:** integración con consumidores reales, **siempre sobre TEST primero** antes de cualquier consideración productiva.

No avanzar a PROD público, MercadoPago real, bot o frontend público sin decisión explícita.

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

**Items cerrados en Etapa 7C:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Validación funcional ampliada sobre TEST (casos no-felices) | ✅ Cerrado | 7C-1 a 7C-6 (48 funcionales + 6 transversales) |
| Cobertura empírica de rama `pre_lock` de idempotencia | ✅ Cerrado | 7C-5 (A-W2-15) |

**Items cerrados en Etapa 7D:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Diseño y ejecución del bloque de limpieza/reset de TEST | ✅ Cerrado | 7D Bloques A/B/C (D-7D-01, D-7D-02) |
| Reset de secuencias a 1 en tablas vaciadas de TEST | ✅ Cerrado | 7D Bloque B (D-7D-01) |
| Vaciado de `log_cambios` en TEST con evidencia documentada | ✅ Cerrado | 7D Bloque B (D-7D-02) |

**Items cerrados en Etapa 7E:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Endurecimiento de permisos Data API en DEV (REVOKE EXECUTE sobre 13 funciones) | ✅ Cerrado | 7E Bloques A/B/C (D-7E-01, D-7E-02) |
| Paridad DEV↔TEST en EXECUTE sobre funciones del proyecto | ✅ Cerrado | 7E Bloque C (0 fugas, owner intacto) |

**Items cerrados en Etapa 8A:**

| Item | Estado | Bloque que lo cerró |
|---|---|---|
| Creación del entorno OPS (proyecto Supabase independiente) | ✅ Cerrado | 8A Bloques 1-2 |
| Replicación del schema desde canónico v1.7.3 (paridad P01-P10 10/10) | ✅ Cerrado | 8A Bloque 4 (tandas 4.1-4.7) |
| Seeds reales mínimos en OPS (5 cabañas, 3 socios, cuenta de cobro, config) | ✅ Cerrado | 8A Bloque 5 |
| Grants mínimos en OPS (REVOKE EXECUTE idempotente; OPS nació cerrado) | ✅ Cerrado | 8A Bloque 6 (confirmación D-8-03) |
| Default privileges de OPS (objetos futuros nacen cerrados, sin ejecución) | ✅ Cerrado | 8A Bloque 7 (D-8-13) |
| `pg_cron` activo en OPS con corrida real verificada | ✅ Cerrado | 8A Bloque 8 |
| Verificación consolidada del entorno OPS (17/17) | ✅ Cerrado | 8A Bloque 9 |
| Credencial n8n `vita_supabase_ops` creada y verificada por identidad | ✅ Cerrado | 8A Bloques 10-11 |

**Items pendientes:**

1. **`tipo_valor` sin poblar en `configuracion_general`** — observación de 7A (PreOPS-A6). Las 10 claves tienen `tipo_valor=NULL`. No bloqueante; evaluar antes del dashboard OPS si se usa para render de inputs. Ver `Pendiente_pre_produccion.md` 1.4.
2. **Validación de tipos inválidos no vacíos** — surgido durante hardening. Casos como `id_cabana="abc"` o `fecha_in="no-es-fecha"` siguen rompiendo con error crudo. Fuera del alcance del hardening por strings/whitespace.
3. **Cobertura empírica de rama `unique_violation` de idempotencia** — opcional, no bloqueante. H7 observó la rama `post_lock` (C-6) y 7C observó la rama `pre_lock` (A-W2-15). Resta solo `unique_violation`, que requiere un cruce concurrente en ventana estrechísima, no reproducible de forma simple. Queda como cobertura opcional pre-PROD si se considera necesario. Ver `Pendiente_pre_produccion.md` 6.3.
4. **RLS configurado** — pendiente histórico, decisión postergada hasta tener frontend público.
5. **Tarifas reales cargadas** — pendiente histórico.
6. **Feriados productivos cargados** — pendiente histórico.
7. **Endurecimiento de permisos en DEV (EXECUTE sobre funciones)** — ✅ **Cerrado en Etapa 7E** (2026-05-28). Se aplicó a DEV el REVOKE EXECUTE sobre las 13 funciones del proyecto a PUBLIC/anon/authenticated/service_role, en paridad con TEST. Owner `postgres` intacto, n8n no afectado, 0 fugas verificadas. Decisiones D-7E-01, D-7E-02. Ver `7E_CIERRE.md`. **Queda abierto el residual asociado:** permisos amplios de tabla a roles Data API en DEV (hallazgo A5), fuera de alcance de 7E por decisión, registrado como pendiente `Pendiente_pre_produccion.md` 1.7.
8. **Validación funcional ampliada sobre TEST** — ✅ **Cerrada en Etapa 7C** (2026-05-28). Batería de casos no-felices ejecutada: 48 casos funcionales + 6 verificaciones transversales, 0 fallos inesperados. Ver `7C_CIERRE.md`.
9. **Diseño del bloque de limpieza/reset de TEST** — ✅ **Cerrado en Etapa 7D** (2026-05-28). Se diseñó y ejecutó el bloque dedicado de reset (snapshot → limpieza atómica → verificación), dejando TEST como entorno limpio: schema v1.7.3 + seed estructural + cron + grants + workflows `__TEST`, sin datos transaccionales. Decisiones D-7D-01 y D-7D-02. Ver `7D_CIERRE.md` y `Pendiente_pre_produccion.md` 6.5.
10. **Residual amplio de permisos de tabla a roles Data API en DEV** — pendiente activo abierto en Etapa 7E. Los roles `anon`/`authenticated`/`service_role` tienen SELECT/escritura completos sobre todas las tablas/vistas de DEV (hallazgo A5, 480 grants), más amplio que el `Dxtm` de TEST. Fuera de alcance de 7E por decisión (Opción 1). A decidir en etapa futura: revocar para alinear con TEST o aceptar y documentar como definitivo. No urgente (sin consumidores Data API activos en DEV). Ver `Pendiente_pre_produccion.md` 1.7 y `7E_CIERRE.md` sección 8.

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
- `7C_CIERRE.md` — documento formal de cierre de Etapa 7C (validación funcional ampliada sobre TEST).
- `7D_CIERRE.md` — documento formal de cierre de Etapa 7D (limpieza/reset del entorno TEST).
- `7E_CIERRE.md` — documento formal de cierre de Etapa 7E (endurecimiento de permisos Data API en DEV).
- `ARQUITECTURA_ETAPA_8_ARRANQUE_OPS.md` — documento de diseño de la Etapa 8 (arranque OPS operativo desde cero; subetapas 8A entorno, 8B carga, 8C calendarios, 8D bloqueos).
- `8A_CIERRE.md` — documento formal de cierre de Etapa 8A (levantamiento del entorno OPS de operación real interna).
- `Docs/Bitacora/6B_EJECUCION_DEV.md` — bitácora bloque por bloque de 6B.
- `Docs/Bitacora/6C_EJECUCION.md` — bitácora workflow por workflow de 6C.
- `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` — bitácora bloque por bloque de Etapa 6D (H1-H7 cerrados; H8 en curso).
- `Docs/Operacional/Lecciones_Aprendidas.md` — gotchas operativos (incluye L-6C-01 a L-6C-09 + nuevas lecciones de hardening pendientes de agregar).
- `Pendiente_pre_produccion.md` — pendientes de deploy productivo (items A1-A3 marcados como cerrados; A4 pendiente).
- `DECISIONES_NO_REABRIR.md` — decisiones cerradas no reabribles (incluye decisiones de hardening pendientes de agregar).
- Documentos de arquitectura de Etapas 1-5 (referencia histórica).
- `Workflows/n8n/supabase/*.template.json` — 8 templates sanitizados de 6C.