# Vita Delta Reservas

Sistema de automatización integral para el complejo de cabañas Vita Delta.

---

## Qué es este proyecto

Vita Delta Reservas es un sistema de gestión operativa para un complejo de 5 cabañas (Bamboo, Madre Selva, Arrebol, Guatemala, Tokio). Centraliza disponibilidad, reservas, pricing, pagos, operación interna y comunicación con huéspedes en una arquitectura automatizable, trazable y escalable.

El stack actual es **Supabase / PostgreSQL** como base de datos y fuente de verdad, **n8n** como orquestador de workflows, y **Claude API** como capa conversacional futura. El proyecto migró desde un stack inicial sobre Google Sheets; esa migración (Etapa 6B) está ejecutada y cerrada en el entorno DEV, y el sistema cuenta además con un entorno TEST levantado y validado, y un entorno **OPS de operación real interna** ya levantado, paritario, seguro y conectado a n8n (Etapa 8A).

> La IA conversa. n8n orquesta. PostgreSQL decide y persiste. Los humanos auditan.

---

## Estado actual

### Arquitectura — Completada y aprobada

Todas las etapas de diseño están cerradas. No se reabren.

| Etapa | Descripción | Estado |
|---|---|---|
| 1 | Arquitectura base | Cerrada |
| 2 | Motor de disponibilidad | Cerrada |
| 3 | Motor de precios | Cerrada |
| 4A | Motor de reservas determinístico | Cerrada |
| 4B | Bot conversacional con IA | Cerrada |
| 5A | Modelo de datos real | Cerrada |
| 5B | Implementación vertical mínima | Cerrada |
| 6A | Decisión de migración a base relacional | Cerrada |
| 6B | Migración a Supabase / PostgreSQL | Cerrada (diseño + ejecución en DEV) |

### Implementación — Backend Supabase + workflows n8n

| Etapa | Descripción | Estado |
|---|---|---|
| 6B (Fases 0-3) | Schema, funciones, triggers, vistas, seed, `pg_cron` en DEV | Cerrada |
| 6C | Reescritura de workflows n8n contra Supabase DEV | Cerrada (2026-05-26) |
| 6D | Hardening pre-producción (validación SQL, concurrencia) | Cerrada (2026-05-27) |
| 7A | Correcciones pre-TEST / pre-OPS | Cerrada (2026-05-28) |
| 7B | Levantamiento del entorno TEST | Cerrada (2026-05-28) |
| 7C | Validación funcional ampliada sobre TEST | Cerrada (2026-05-28) |
| 7D | Limpieza/reset del entorno TEST | Cerrada (2026-05-28) |
| 7E | Endurecimiento de permisos Data API en DEV (paridad con TEST) | Cerrada (2026-05-28) |
| 8A | Levantamiento del entorno OPS (operación real interna) | Cerrada (2026-05-29) |

**Schema canónico actual:** `6B_SCHEMA_SQL.md v1.7.3`. DEV, TEST y OPS están alineados funcionalmente: TEST se reconstruyó desde el canónico en 7B (paridad 10/10 vs DEV) y OPS en 8A (paridad P01-P10 10/10).

---

## Cómo funciona el sistema

```text
La IA conversa.
n8n orquesta.
PostgreSQL decide y persiste.
Los humanos auditan.
```

**Supabase / PostgreSQL** es la fuente de verdad. Las reglas críticas de disponibilidad, reservas, pagos y bloqueos viven en funciones SQL con locks, idempotencia y validación estructural (EXCLUDE constraints anti-double-booking).

**n8n** orquesta: recibe eventos, arma payloads, llama a las funciones SQL y maneja respuestas. No replica lógica interna de las funciones ni decide disponibilidad por su cuenta.

**Claude / IA** es la capa conversacional futura. Conversa con el huésped y llama a los workflows determinísticos. No confirma reservas, pagos ni disponibilidad por sí sola.

### Flujo base de una reserva

```text
Consulta entrante
  → vita_w01_consultar_disponibilidad_supabase
  → vita_w02_crear_prereserva_supabase     (bloqueo temporal + verificación bajo locks)
  → vita_w03_registrar_pago_supabase       (pago reportado → pre-reserva en revisión)
  → vita_w04_confirmar_reserva_supabase    (validación + confirmación → reserva definitiva)
```

La pre-reserva bloquea disponibilidad temporalmente y expira si no se confirma. La reserva se confirma solo después de validar pago y disponibilidad bajo locks.

### Operaciones adicionales

- `vita_w00_smoke_test_supabase` — verificación de conexión.
- `vita_w05_cancelar_prereserva_supabase`
- `vita_w06_crear_bloqueo_supabase`
- `vita_w07_vistas_operativas_supabase` — lectura de vistas operativas.

---

## Entornos

| Entorno | Proyecto Supabase | Estado |
|---|---|---|
| DEV | `vita-delta-dev` | Backend completo v1.7.3 + hardening + 8 workflows validados + permisos EXECUTE endurecidos (7E). IDs de cabaña 17-21. |
| TEST | `vita-delta-test` | Schema reconstruido desde canónico, paritario, validado y reseteado a estado limpio (7D). IDs de cabaña 1-5. |
| OPS | `vita-delta-ops` | **Operación real interna.** Levantado en 8A: schema paritario (P01-P10 10/10), seeds reales, seguridad cerrada (nació más cerrado que TEST), `pg_cron` activo, credencial n8n `vita_supabase_ops` verificada por identidad. IDs de cabaña 1-5. Sin datos transaccionales aún (primer write por 8B). |
| PROD | — | No creado. Etapa futura (público). |

**IDs de cabaña no portables entre entornos** (DEV 17-21; TEST y OPS 1-5 cada uno en su propia base). Cada workflow usa los IDs del ambiente al que apunta. En el form de carga de 8B la cabaña se elige por nombre, no por ID.

---

## Workflows legacy (Google Sheets)

Los workflows originales contra Google Sheets (`db_*`) y los archivos Apps Script se conservan como **referencia histórica congelada**. No son la ruta productiva actual, no se mantienen y no deben usarse como fuente de verdad. Google Sheets ya no es backend operativo; puede usarse para reportería de lectura.

Ubicación típica: `Workflows/n8n/*.template.json` (sin subcarpeta `supabase/`).

---

## Principios operativos

Decisiones que **no deben reabrirse** salvo contradicción crítica explícita:

1. Supabase / PostgreSQL es la fuente de verdad.
2. Google Sheets no es backend operativo.
3. n8n orquesta; PostgreSQL decide y persiste.
4. La IA no confirma reservas, pagos ni disponibilidad real por sí sola.
5. Toda reserva confirmada pasa por `confirmar_reserva()`.
6. Toda pre-reserva se crea por `crear_prereserva()`.
7. No hay `INSERT` directo a `reservas` desde workflows.
8. No usar `DROP ... CASCADE` ni `TRUNCATE ... CASCADE` sin decisión explícita.
9. Mantener `nv()` defensivo en workflows n8n como defensa en profundidad.
10. `fecha_in` inclusive, `fecha_out` exclusive; modelo daterange `[)`.
11. IDs de cabaña no portables entre entornos (DEV 17-21; TEST y OPS 1-5 cada uno en su base).
12. No limpiar fixtures de un entorno de prueba fuera de un bloque de reset dedicado con SQL aprobado (`D-7C-01`); la limpieza es snapshot → borrado atómico → verificación, con doble gate anti-error-de-entorno (`D-7D-01`, `D-7D-02`).

**Documento de referencia:** `Docs/Operacional/DECISIONES_NO_REABRIR.md`.

---

## Pendientes activos pre-PROD

Pendientes documentados al cierre de 7E:

- **Residual amplio de permisos de tabla a roles Data API en DEV** — hallazgo de 7E (snapshot A5): `anon`/`authenticated`/`service_role` tienen SELECT/escritura completos sobre todas las tablas/vistas de DEV, más amplio que el `Dxtm` de TEST. Fuera de alcance de 7E por decisión (Opción 1). **Acotado a DEV:** OPS nació sin este problema (switch correcto desde el día cero, confirmado en 8A). A decidir solo para DEV: revocar para alinear con TEST/OPS o aceptar como definitivo. `Pendiente_pre_produccion.md` 1.7.
- **Contrato SQL de `registrar_pago` frente a entradas no-vacías mal tipadas** (hoy mitigado por `nv()` en n8n). `Pendiente_pre_produccion.md` 1.6.
- `tipo_valor` sin poblar en `configuracion_general` (1.4).
- Validaciones para tipos inválidos no vacíos (heredado de 6D).
- Cobertura empírica opcional de la rama `unique_violation` de idempotencia (6.3).
- RLS final para frontend público (pendiente histórico).
- Tarifas reales productivas y feriados productivos (pendientes históricos).

> **Cerrado en 7E:** el endurecimiento de permisos EXECUTE en DEV (REVOKE EXECUTE sobre las 13 funciones del proyecto a `PUBLIC`/`anon`/`authenticated`/`service_role`, paridad con TEST). Ver `Pendiente_pre_produccion.md` 1.5 y `7E_CIERRE.md`.

**Documento de referencia:** `Docs/Operacional/Pendiente_pre_produccion.md`.

---

## Próximas etapas — opciones disponibles

Con DEV, TEST, OPS, 6C, 6D, 7A, 7B, 7C, 7D, 7E y 8A cerradas, el entorno OPS ya está levantado y operativo. Las opciones a priorizar (orden sugerido, no comprometidas):

- **8B — Capa de carga de Vicky:** Form Trigger n8n (usable desde celular) que encadena `crear_prereserva` → `registrar_pago` → `confirmar_reserva` en una acción, con monto total y seña editable, y elección de cabaña por nombre. Es el primer write real sobre OPS.
- **8C — Calendarios visuales por evento** (operativo + el de limpieza para Jennifer).
- **8D — Bloqueos operativos + cierre de Etapa 8.**
- **Residual de permisos de tabla en DEV** (hallazgo A5 / pendiente 1.7): revocar el set amplio de SELECT/escritura a roles Data API para alinear con TEST, o aceptarlo y documentarlo como definitivo. No urgente; OPS ya nació sin ese problema.
- **Integraciones con consumidores reales sobre TEST:** webhook MercadoPago, bot conversacional, frontend público — siempre sobre TEST primero.

No avanzar a PROD público, MercadoPago real, bot o frontend público sin decisión explícita.

---

## Qué no está implementado todavía

- Webhook real de MercadoPago.
- Integración real con WhatsApp / Instagram (Meta API).
- Bot conversacional conectado a canales reales.
- Web pública de reservas conectada al backend.
- Panel administrativo y dashboard operativo.
- Contabilidad automatizada.
- RLS final para frontend público.
- Tarifas y feriados productivos completos.
- Entorno PROD (público). _(OPS, operación interna, ya está levantado en 8A.)_

**El sistema no está en producción pública.** OPS es operación real interna, recién levantado, todavía sin carga de reservas (el primer write llega con 8B).

---

## Sobre `index.html` y prototipos

- **`index.html`** — presentación visual estática del estado del sistema, para explicar el proyecto a socios o colaboradores. No es una web pública de reservas ni está conectada al backend.
- **`Prototipos/prototipo_web_reservas.html`** — boceto visual de la futura web de reservas. No consulta disponibilidad real, no crea pre-reservas, no registra pagos y no está conectado a Supabase.

---

## Documentación viva

- `Docs/Operacional/ESTADO_ACTUAL_VITA_DELTA.md` — estado vigente del proyecto.
- `Docs/Operacional/DECISIONES_NO_REABRIR.md` — decisiones cerradas no reabribles.
- `Docs/Operacional/Pendiente_pre_produccion.md` — pendientes para deploy a PROD.
- `Docs/Operacional/Lecciones_Aprendidas.md` — gotchas operativos.
- `Docs/Implementacion/6B_SCHEMA_SQL.md` — schema canónico SQL vigente (v1.7.3).
- `Docs/Implementacion/6B_PLAN_FASES.md` — plan de ejecución, conservado como referencia.
- `Docs/Arquitectura/` — documentos de arquitectura de Etapas 1-6B y `ARQUITECTURA_ETAPA_8_ARRANQUE_OPS.md` (diseño del arranque OPS).
- `Docs/Bitacora/` — cierres formales (`6C_CIERRE`, `6D_CIERRE`, `7A_CIERRE`, `7B_CIERRE`, `7C_CIERRE`, `7D_CIERRE`, `7E_CIERRE`, `8A_CIERRE`) y bitácoras de ejecución (`6B_EJECUCION_DEV`, `6C_EJECUCION`, `HARDENING_PRE_PRODUCCION_EJECUCION`).
- `Workflows/n8n/supabase/*.template.json` — 8 templates sanitizados de los workflows contra Supabase.
- `CLAUDE.md` — reglas de trabajo y orden de lectura para Claude.

---

## Principios de trabajo

Antes de agregar cualquier automatización o integración, verificar:

1. Si ya existe una fuente de verdad para ese dato (Supabase).
2. Si la lógica pertenece a una función SQL determinística o a la IA.
3. Si afecta disponibilidad, reservas, pagos o pricing.
4. Si necesita trazabilidad en `log_cambios` (`source_event`).
5. Si puede romper una validación ya cerrada.
6. Primero diseñar, después documentar, recién después implementar.

Si hay contradicción entre implementación y arquitectura, prevalecen los documentos de arquitectura cerrados. Nunca ejecutar workflows o SQL de prueba contra datos productivos.
