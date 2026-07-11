# CIERRE B1.3 (A–F) + KICKOFF `B1.3-cierre-integracion-TEST`

Documento de handoff. **Parte 1** cierra formalmente la conversación del frente B1.3 A–F.
**Parte 2** es el kickoff para arrancar una conversación nueva de validación de portal en TEST.
No se generan patchers en ninguna de las dos partes.

---
---

# PARTE 1 — CIERRE FORMAL DE ESTA CONVERSACIÓN

## 1.1 Estado final A–F

Motor de Horarios, sub-bloque **B1.3 "Vigencias Semanales" + Modelo α**, bloques A→F: **todos ejecutados y formalmente VERDES en TEST a nivel base de datos.**

| Bloque | Qué es | Estado |
|---|---|---|
| A | Migración a vigencias semanales (cabecera 4-col + detalle 7×DOW; interno semanal de doble lookup, fail-closed `vigencia_incompleta`) | VERDE TEST |
| B | `validar_gap_bordes_congelados(...)` — gap same-day ≥2h vs horas congeladas de vecinos de borde (Modelo α) | VERDE TEST |
| C | Patch de `crear_prereserva` — inyecta el validador de gap antes del INSERT | VERDE TEST (smoke 8/8) |
| D | Patch de `confirmar_reserva` — inyecta el validador de gap (horas congeladas de la pre-reserva) | VERDE TEST (smoke 8/8) |
| E | `crear_reserva_con_horario_pactado(jsonb)` — alta administrativa Modelo α, sin pre-reserva ni pago | VERDE TEST (smoke 14/14) |
| F | `crear_override_horario_puntual(jsonb)` — override puntual unificado con eje `bordes`; **reemplaza** `crear_paquete_dia_especial` (S3), sin coexistencia | VERDE TEST (smoke 15/15) |

## 1.2 Fingerprints baseline post-F (autoridad para la próxima conversación)

| # | Objeto | Fingerprint | Rol |
|---|---|---|---|
| 1 | wrapper `resolver_horario(bigint,date)` | `1bd96c89e587b15582fd7b2e29ae7e18` | INTACTO |
| 2 | interno `_resolver_horario(bigint,date,boolean)` | `7e5bfa21b39d90b674c1a83d76b71b1d` | reemplazado (semanal) |
| 3 | helper `vigencias_conflictos_comprometidos` | `c684340c893d8668dc2d74c7564106a8` | reemplazado (semanal) |
| 4 | guard `crear_vigencia_horario(jsonb)` | `1a7d0d2d3507019563cedd376997780d` | reemplazado (semanal) |
| 5 | trigger `trg_guard_vigencias()` | `b4e48e49123a4c189609d0adc21730f5` | reemplazado (semanal) |
| 6 | `validar_gap_bordes_congelados` | `5c5ef50eff10db716d17305dcbd54669` | nuevo (B) |
| 7 | `crear_prereserva(jsonb)` | `62fefb63ef64e443ea2697645cd4e0a8` | parcheado (C) |
| 8 | `confirmar_reserva(...)` | `e6ac8ddce8a12a9c48ecc1aa128b311c` | parcheado (D) |
| 9 | `crear_reserva_con_horario_pactado(jsonb)` | `93c1700f5940b0e53095e08635e159d0` | nuevo (E) |
| 10 | `crear_override_horario_puntual(jsonb)` | `33d7ac8ad5f80b72a0266fb4eb4f7f4d` | nuevo (F) |
| 11 | ODR `obtener_disponibilidad_rango(date,date,bigint)` | `37009a32154f93b80520500c0f15b46b` | INTACTO |

`crear_paquete_dia_especial(jsonb)` (S3): **ya no existe** (reemplazada por F).

## 1.3 Qué quedó VERDE en TEST

- La capa DB completa de B1.3: vigencias semanales, validador de gap, los dos patches (C/D), y las dos funciones nuevas (E/F).
- Smokes robustos por bloque (base normal + tardío donde aplica), **residual cero** en todos.
- Reversibilidad verificada bloque por bloque; el rollback de F restaura S3 compatible con el resolver vivo.
- Repo commiteado: *"close B1.3 weekly schedules in TEST"* (HEAD `6d84500`); artefactos A–F en las bitácoras `08-07` / `09-07`.

## 1.4 Qué NO se hizo todavía

- **No** se consolidó B1.3 en el canónico (`6B_SCHEMA_SQL.md` sigue en v1.12.0 = Carril CC) ni en el bootstrap.
- **No** se promovió nada a OPS.
- **No** se validó el flujo real por el **portal operativo** (gateway `portal-api` → n8n → frontend). Solo DB directo.
- **No** se ajustó el workflow A07 para los errores nuevos de gap.
- **No** se realineó la deuda cascade B1.1/B1.2/S0–S3 (fingerprints viejos).
- **No** se expusieron E ni F al portal.
- **No** se acuñaron identificadores D-*/L-* de cierre (se hará en el cierre canónico).

## 1.5 Qué queda PROHIBIDO asumir

- **No asumir** que el portal funciona de punta a punta: solo se validó DB directo.
- **No asumir** que los errores nuevos llegan al frontend: hoy A07 no los mapea (ver §1.9).
- **No asumir** que E/F están disponibles desde el portal: son **DB-only**.
- **No asumir** que canónico/bootstrap reflejan B1.3: no lo hacen.
- **No asumir** que los smokes viejos de override S0–S3 pasan tal cual: gatean el wrapper viejo `58d75c1b`.
- **No re-ejecutar** `CREATE OR REPLACE` sobre funciones desplegadas (disciplina DROP+CREATE); no bumpear canónico mid-carril; no tocar OPS/canónico/n8n/Vercel/git desde el diseño.
- **No asumir** fingerprints: re-pin siempre con `md5(pg_get_functiondef(...))` sobre el vivo.

## 1.6 Deuda pendiente

1. **Ajuste A07** (mapeo de errores de gap) — funcional, prioritario.
2. **Validación integral TEST** por capa (portal-api / n8n / frontend / calendario).
3. **Cascade B1.1/B1.2/S0–S3**: decidir por objeto — histórico salvo regresión (ver §1.12).
4. **Consolidación canónica**: 6B v1.12.0 → v1.13.0 + bootstrap nuevo (una sola vez, coordinado).
5. **Docs vivos**: D-*/L-* de B1.3, `ESTADO_ACTUAL`, `Pendiente_pre_produccion`, `CLAUDE.md`.
6. **Plan OPS**: diseñado, sin ejecutar.
7. **Producto (diferido)**: si el negocio requiere E o F desde el portal, es feature nueva (gateway + n8n + UI).

## 1.7 Riesgos detectados

1. **UX de gap sin mapeo (alto)** — sin el fix de A07, todo bloqueo de gap vía portal cae como `error_entorno`.
2. **Regresión falsa por fps viejos (medio)** — re-ejecutar smokes S0–S3 sin realinear `58d75c1b`→`1bd96c89` da fallos de gate espurios.
3. **Consolidación canónica (medio)** — el bump debe extender sin romper el carril CC ya consolidado.
4. **Barrido OPS de S3 (bajo)** — el barrido de callers de `crear_paquete_dia_especial` fue sobre repo (limpio); repetir contra OPS antes de promover.
5. **Fps "intactos" a confirmar (bajo)** — verificar wrapper `1bd96c89` y ODR `37009a32` idénticos post-F.

## 1.8 Decisiones tomadas (registradas)

- **No ir a OPS todavía.** La promoción se pospone hasta tener TEST integral verde.
- **Validar primero el portal operativo real en TEST** (gateway → n8n → frontend → calendario), no solo DB directo.
- **Dejar E y F DB-only por ahora.** No se exponen al portal en este ciclo; exponerlas es decisión de producto posterior.
- **Declarar histórico el cascade viejo B1.1/B1.2/S0–S3**, salvo que una regresión específica exija realinear un smoke puntual a `1bd96c89`. No se ejecutan los patchers de cascade B1.2 (quedó absorbido por B1.3).

## 1.9 Riesgo concreto A07 (para no perderlo)

`crear_prereserva` (parche C) y `confirmar_reserva` (parche D) ahora pueden devolver **`checkin_pisa_checkout_anterior`** y **`checkout_pisa_checkin_posterior`**. El workflow **`portal-a07-crear-reserva`** hoy **no** los mapea. Como el gateway solo propaga códigos de su allowlist (`conflicto`, `payload_invalido`, …) y enmascara el resto como **`error_entorno`**, un bloqueo de gap vía portal se mostraría como *"respuesta inválida del backend"* en vez del motivo real. **Fix mínimo**: mapear ambos a `conflicto` con mensaje claro, en los nodos de clasificación de error de A07 (ver Parte 2, §B).

---
---

# PARTE 2 — KICKOFF: `B1.3-cierre-integracion-TEST — Validación portal operativo antes de OPS`

## Objetivo de la conversación nueva

Llevar B1.3 de "verde en DB" a "verde de punta a punta en TEST vía portal operativo", con el ajuste mínimo necesario, **antes** de cualquier consolidación canónica o promoción OPS. Reglas de arranque:

- Partir de **clone fresco desde HEAD**; el repo vivo es la **autoridad**.
- **No** tocar OPS.
- **No** tocar canónico/bootstrap todavía.
- **No** exponer E/F al portal todavía.
- Hacer **primero** el ajuste mínimo de A07.
- **Después** validar `portal-api`, n8n, frontend y calendario en TEST.
- Recién con **TEST integral verde**, pasar a cierre canónico/bootstrap y plan OPS.

## A. Contexto técnico

- B1.3 A–F **verdes en TEST** (DB). Fingerprints baseline post-F: los **11** de la tabla §1.2 (autoridad; re-pin con `md5(pg_get_functiondef(...))`).
- **S3 reemplazado por F**: `crear_paquete_dia_especial` ya no existe; vive `crear_override_horario_puntual(jsonb)`.
- **`crear_reserva_con_horario_pactado` = DB-only** (sin acción de portal, sin workflow).
- **`crear_override_horario_puntual` = DB-only** (S3 tampoco tenía acción; no rompe el portal).
- El portal usa la acción **`reserva.crear_manual`** → webhook **`portal-a07-crear-reserva`** (A07) → que llama **`crear_prereserva`** y **`confirmar_reserva`** (ambos parcheados C/D).

## B. Problema inmediato

- `crear_prereserva` y `confirmar_reserva` ahora pueden devolver:
  - `checkin_pisa_checkout_anterior`
  - `checkout_pisa_checkin_posterior`
- El workflow A07 **no los mapea**.
- Si no se mapean, el gateway (allowlist de códigos) devuelve **`error_entorno`** genérico.
- **Fix mínimo esperado**:
  - mapear **ambos** errores a **`conflicto`**;
  - mensaje claro para el usuario (ej. *"El horario elegido se solapa con el turno de una reserva vecina; ajustá el check-in/check-out."*);
  - actualizar el **template en GitHub** si corresponde;
  - **ubicación exacta** (a confirmar sobre clone fresco): los nodos `code` **`router1_crear`** (clasifica el error de `crear_prereserva`, PG-1) y **`router3_confirmar`** (clasifica el de `confirmar_reserva`, PG-3). Ambos ya mapean `no_disponible → conflicto`; hay que sumar los dos códigos de gap al mismo `conflicto`. Revisar por completitud `router0_precheck` y `router4_recheck` por si el precheck/recheck también evalúa gap.

## C. Forma de trabajo

1. **Primero diagnóstico** sobre clone fresco (confirmar nodos, códigos, contrato del envelope).
2. **Después** patch mínimo A07 (solo el mapeo de los 2 errores; nada más).
3. **Después** actualizar el template en GitHub.
4. **Después** pruebas en TEST.
5. **Hard stop antes de OPS.** No consolidar canónico/bootstrap en esta conversación.

## D. Validación esperada (TEST)

- A07 **caso feliz** (reserva se crea/confirma).
- A07 **gap check-in** → `checkin_pisa_checkout_anterior` → gateway devuelve `conflicto`.
- A07 **gap check-out** → `checkout_pisa_checkin_posterior` → gateway devuelve `conflicto`.
- A07 **`no_disponible`** (regresión: sigue mapeando a `conflicto`).
- A07 **payload inválido** (regresión: sigue mapeando a `payload_invalido`).
- **portal-api devuelve `conflicto`, no `error_entorno`**, para los dos errores de gap.
- **frontend** muestra mensaje claro (no "respuesta inválida del backend").
- **calendario/ODR sin regresión** (ODR fp `37009a32` intacto; vistas de calendario coherentes con el cambio semanal).

## E. Archivos que debería revisar

- Workflow/template **A07**: `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json`.
- **portal-api vivo**: `Docs/Implementacion/Carril_C/PROMOCION_OPS/portal-api_OPS_index.ts` (allowlist de acciones y de **códigos de error** `CODIGOS_ERROR_PERMITIDOS`; confirmar cuál es el índice vivo en TEST).
- **action registry / contrato frontend** si aplica: `Apps/portal-operativo/src/lib/actionRegistry.ts`, `.../lib/contratos.ts`.
- **Docs de diagnóstico B1.3**: `KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md` (matriz de impacto, plan de validación, riesgos).
- **Bitácoras A–F**: `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/08-07-2026/` y `09-07-2026/`.
- **Templates legacy** solo para confirmar si siguen vivos o son históricos: `db_crear_prereserva`, `db_confirmar_reserva`, `vita_w02_crear_prereserva`, `vita_w04_confirmar_reserva` (mismo SP; mismo mapeo si siguen en uso).

## F. Entregable inicial de la conversación nueva

**No** arrancar escribiendo patchers. Primero entregar:

1. **Inventario** (confirmación del estado vivo: fps re-pin, S3 ausente, acción/webhook A07).
2. **Ubicación exacta del mapping A07** (nodo/es `router1_crear` y `router3_confirmar` confirmados sobre clone fresco; línea/estructura del `case`/objeto de códigos).
3. **Propuesta de cambio mínimo** (qué códigos agregar, a qué código genérico, con qué mensaje; sin tocar nada más).
4. **Plan de prueba** (los casos de §D, por capa).
5. **Archivos a tocar** (exactos).
6. **Riesgos** (incluido: no romper el mapeo existente de `no_disponible`/`payload_invalido`).
7. **Orden exacto de ejecución** (diagnóstico → patch A07 → template GitHub → pruebas TEST → hard stop).

Recién **después de tu aprobación** de ese entregable, generar el ajuste A07 / template.

---

### Método de trabajo (recordatorio, invariante)

Diseño → aprobación explícita → artefactos → Franco ejecuta en TEST → verificación → cierre. Un bloque por conversación, hard stops. Clone-first. Claude nunca toca OPS/canónico/n8n/Vercel/git directamente. Rioplatense, voseo. Validación por capas (pglast → harness → TEST → smokes) cuando haya SQL; para n8n, `node --check` sobre el código de los nodos y prueba real en TEST.
