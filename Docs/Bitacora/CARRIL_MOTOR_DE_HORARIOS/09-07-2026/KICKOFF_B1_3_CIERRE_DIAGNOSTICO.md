# KICKOFF — Cierre/Cascade B1.3 + Validación integral TEST (DIAGNÓSTICO)

> Fase **diagnóstico**. No se generan patchers ni artefactos de cierre todavía. Este documento
> es el mapa para decidir qué se toca, en qué orden y con qué riesgos antes de cualquier promoción OPS.

---

## 0. Autoridad y estado base

- **Clone fresco**: HEAD `6d84500` (previo de la sesión: `39e3b72`). Último commit: *"feat(horarios): close B1.3 weekly schedules in TEST"* (2026-07-09). El repo fresco es autoridad.
- **Commiteado durante el frente**: bitácoras B1.3 (`08-07`, `09-07` con A→F), cambios de portal del **carril CC** (`RetirarSaldo.tsx`, `actionRegistry`, `contratos`, `CuentaCorriente`), bootstrap `v1.12.0`, `6B_SCHEMA_SQL.md`, `ESTADO_ACTUAL`, `Pendiente_pre_produccion`, `CLAUDE.md`, `README`.
- **Canónico**: `6B_SCHEMA_SQL.md` **v1.12.0** — consolida el **Carril Cuenta Corriente** (snapshot L3), **NO B1.3**. B1.3 vive en TEST y en las bitácoras, **sin consolidar en canónico ni bootstrap**. Esto es correcto (no se bumpea mid-carril); el cierre de B1.3 es exactamente lo que falta.

---

## 1. Inventario de objetos vivos post-F en TEST

### 1.1 Tablas (B1.3-A)
| Objeto | Tipo | Cambio |
|---|---|---|
| `vigencias_horario_base` | tabla | **reshape** a cabecera 4-col (sin horas directas) |
| `vigencias_horario_detalle` | tabla | **nueva** (7 filas por vigencia, 1 por `dia_semana`) |

### 1.2 Funciones NUEVAS
| Función | Bloque | Rol |
|---|---|---|
| `validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)` | B | validador gap same-day (Modelo α) |
| `crear_reserva_con_horario_pactado(jsonb)` | E | alta administrativa Modelo α |
| `crear_override_horario_puntual(jsonb)` | F | override puntual unificado (superset de S3) |

### 1.3 Funciones REEMPLAZADAS (DROP + CREATE)
| Antes | Ahora | Bloque |
|---|---|---|
| `_resolver_horario(...)` (default/domingo) | interno **semanal** | A |
| `vigencias_conflictos_comprometidos(...)` (firma vieja) | helper **semanal** | A |
| `crear_vigencia_horario(jsonb)` (default/domingo) | guard **semanal** | A |
| `trg_guard_vigencias()` | trigger **semanal** | A |
| `crear_paquete_dia_especial(jsonb)` | **`crear_override_horario_puntual(jsonb)`** | F |

### 1.4 Funciones PARCHEADAS (patch dinámico, aditivo)
| Función | Bloque | Qué se agregó |
|---|---|---|
| `crear_prereserva(jsonb)` | C | llamada a `validar_gap_bordes_congelados` antes del INSERT |
| `confirmar_reserva(...)` | D | llamada a `validar_gap_bordes_congelados` (horas congeladas de la pre-reserva) |

### 1.5 Triggers
- `trg_vig_guard`, `trg_vig_guard_detalle` (constraint triggers sobre vigencias, B1.3-A).
- `trg_ov_guard` (constraint trigger sobre `overrides_operativos`, S1 — **intacto**, sobrevive B1.3).

---

## 2. Re-pin de fingerprints (baseline vivo post-F)

| # | Objeto | Fingerprint (TEST vivo) | Rol post-B1.3 |
|---|---|---|---|
| 1 | wrapper `resolver_horario(bigint,date)` | `1bd96c89e587b15582fd7b2e29ae7e18` | **INTACTO** (cuerpo no cambió) |
| 2 | interno `_resolver_horario(bigint,date,boolean)` | `7e5bfa21b39d90b674c1a83d76b71b1d` | reemplazado (semanal) |
| 3 | helper `vigencias_conflictos_comprometidos` | `c684340c893d8668dc2d74c7564106a8` | reemplazado (semanal) |
| 4 | guard `crear_vigencia_horario(jsonb)` | `1a7d0d2d3507019563cedd376997780d` | reemplazado (semanal) |
| 5 | trigger `trg_guard_vigencias()` | `b4e48e49123a4c189609d0adc21730f5` | reemplazado (semanal) |
| 6 | `validar_gap_bordes_congelados` | `5c5ef50eff10db716d17305dcbd54669` | nuevo (B) |
| 7 | `crear_prereserva(jsonb)` | `62fefb63ef64e443ea2697645cd4e0a8` | parcheado (C) |
| 8 | `confirmar_reserva(...)` | `e6ac8ddce8a12a9c48ecc1aa128b311c` | parcheado (D) |
| 9 | `crear_reserva_con_horario_pactado(jsonb)` | `93c1700f5940b0e53095e08635e159d0` | nuevo (E) |
| 10 | `crear_override_horario_puntual(jsonb)` | `33d7ac8ad5f80b72a0266fb4eb4f7f4d` | nuevo (F, reemplaza S3) |
| 11 | ODR `obtener_disponibilidad_rango(date,date,bigint)` | `37009a32154f93b80520500c0f15b46b` | **INTACTO** (verificar) |

**Query de re-pin en TEST** (read-only): `SELECT md5(pg_get_functiondef('<obj>'::regprocedure));` por cada uno + confirmar que S3 (`crear_paquete_dia_especial`) ya **no existe** (`to_regprocedure(...) IS NULL`).

---

## 3. Deuda cascade B1.1/B1.2 — gates/smokes/docs con fingerprints viejos

Origen (doc `EVALUACION_PIVOTE_VIGENCIAS_SEMANALES.md`, Camino B): se **pausó B1.2-cascade** y su realineación se **absorbe en el cierre de B1.3** (una sola vez, con los fingerprints finales). El wrapper `1bd96c89` sobrevivió; el interno y el helper cambiaron.

| Fingerprint viejo | Objeto | Archivos afectados | Clasificación propuesta |
|---|---|---|---|
| `58d75c1b…` | wrapper post-R0 | **26** (gates/smokes override S0–S3 del `04-07` + docs cascade `06/07-07`) | **actualizar** los SQL de S0–S3 si se re-ejecutan para regresión (→ `1bd96c89`); **histórico** los docs |
| `566ea522` | interno viejo pre-semanal | 5 (todos docs cascade B1.2) | **histórico** (registro de diagnóstico) |
| `871fcde5` | helper viejo pre-semanal | 5 (todos docs cascade B1.2) | **histórico** |
| `6cbc9102` | `confirmar_reserva` pre-D | 0 | sin deuda |

**Distinción retira / actualiza / histórico:**
- **Actualiza** (SQL ejecutable de regresión): los gates/smokes de override `S0/S1/S2/S3` (`04-07`) gatean el wrapper viejo `58d75c1b`. Si se quieren correr para regresión post-F, realinear a `1bd96c89` (mismo target que ya usan A–F). Alternativa: declararlos "históricos, no re-ejecutar" y confiar en la regresión nueva.
- **Histórico** (registro, no ejecutable): `KICKOFF_B1_2_CASCADE.md`, `INVENTARIO_Y_BARRIDO_B1_2_CASCADE.md`, `DISENO_DETALLADO_B1_2_CASCADE.md`, `CIERRE_TECNICO_PRELIMINAR_B1_2_CORE.md`, `EVALUACION_PIVOTE…`. Documentan un cascade que se **absorbió**; se dejan como registro con una nota de "superseded por B1.3".
- **Retira**: nada se borra; el cascade B1.2 como bloque separado queda cancelado por absorción (documentar, no ejecutar sus patchers).

---

## 4. Decisiones B1.3 a documentar (candidatas a D-*/L-* en el cierre)

1. **Vigencias semanales**: cabecera (`vigencias_horario_base` 4-col) + detalle (`vigencias_horario_detalle`, 7×DOW); interno de doble lookup.
2. **`vigencia_incompleta`**: fail-closed cuando faltan filas DOW.
3. **Modelo α de reserva pactada** (E): alta administrativa confirmada directa, sin pre-reserva ni pago; horas congeladas.
4. **Gap same-day contra horas congeladas** (B/C/D/E/F): turno ≥ 2h vs horas *frozen* de vecinos de borde; `validar_gap_bordes_congelados`.
5. **ODR no es verdad final de borde same-day**: la disponibilidad por rango no decide el gap de borde; lo decide el validador de gap.
6. **Reemplazo S3 → `crear_override_horario_puntual`** (F): eje `bordes` (checkin/checkout/ambos), superset de S3, sin coexistencia.
7. **Errores nuevos** (ver §5).
8. **Rollback scope por sub-bloque**: cada bloque A–F revierte solo lo suyo; el rollback de F restaura S3 compatible con el resolver vivo (sin re-exigir el resolver viejo).

---

## 5. Contrato de errores nuevos (A–F)

| Error | Origen | Categoría gateway sugerida |
|---|---|---|
| `vigencia_incompleta` | A (resolver) | `conflicto` / `error_interno` (según flujo) |
| `checkin_pisa_checkout_anterior` | B/C/D | **`conflicto`** |
| `checkout_pisa_checkin_posterior` | B/C/D | **`conflicto`** |
| `source_event_invalido` | E | `payload_invalido` |
| `horario_pactado_requerido` | E | `payload_invalido` |
| `fecha_in_pasada` | C/E | `payload_invalido` (ya mapeado en A07) |
| `borde_horas_incompatibles` | F | `payload_invalido` |
| `rango_invalido` | F | `payload_invalido` |
| `override_no_aplicado_efectivamente` | F | `conflicto` |
| (S0/S2 preexistentes) `override_pisa_reserva`, `override_pisa_prereserva`, `override_incompatible_same_day`, `override_hora_invalido` | S0/S2/F | `conflicto` / `payload_invalido` |

**Los dos críticos para el portal hoy**: `checkin_pisa_checkout_anterior` y `checkout_pisa_checkin_posterior` (los devuelve el motor parcheado C/D vía A07).

---

## 6. Matriz de impacto portal / API / workflows / frontend

### 6.1 Gateway `portal-api` (OPS `portal-api_OPS_index.ts`, 1160 líneas)
- Arquitectura: **allowlist de acciones** versionada (D-C-31) + **doble allowlist** gateway+wrapper (D-C-39) + **action binding** (D-C-41).
- **Allowlist de códigos de error** `CODIGOS_ERROR_PERMITIDOS` = genéricos: `payload_invalido, no_autorizado, rol_no_permitido, accion_desconocida, no_encontrado, conflicto, error_entorno, error_interno, estado_incierto, firma_invalida, ts_fuera_de_ventana, raw_body_ausente, ambiente_incorrecto`. **Un código fuera del allowlist → se enmascara `error_entorno`** (D-C-18, línea ~1018).
- **Conclusión**: el gateway **NO necesita cambios** para los errores nuevos, *siempre que* el workflow n8n los traduzca a un código genérico permitido (`conflicto`/`payload_invalido`). Los códigos de dominio del SP **no** viajan crudos; se mapean en n8n.

### 6.2 Workflow n8n `portal-a07-crear-reserva` (⚠ ACCIÓN REQUERIDA)
- `reserva.crear_manual` → webhook `portal-a07-crear-reserva` → llama **`crear_prereserva`** y **`confirmar_reserva`** (ambos parcheados C/D).
- Hoy mapea: `no_disponible → conflicto`; `cabana_* / fecha_* / fechas_invalidas / fecha_in_pasada / excede_capacidad → payload_invalido`.
- **NO mapea** `checkin_pisa_checkout_anterior` ni `checkout_pisa_checkin_posterior` (0 ocurrencias en el template). ⇒ cuando el gap de turno bloquee una reserva **vía portal**, el gateway los verá como código no permitido y devolverá **`error_entorno`** genérico ("respuesta inválida del backend").
- **Fix mínimo**: agregar ambos códigos al mapeo → `conflicto` con mensaje legible (mismo patrón que `no_disponible`).
- **Revisar además** (mismo SP, otros consumidores): `db_crear_prereserva`, `db_confirmar_reserva`, `vita_w02_crear_prereserva`, `vita_w04_confirmar_reserva` (legacy) — si siguen en uso, mismo mapeo.

### 6.3 `crear_reserva_con_horario_pactado` (E) — sin acción de portal
- No hay acción ni workflow. **Decisión de producto**: (a) dejar **DB-only/admin** (invocación directa o por proceso interno) → sin cambios de portal; o (b) **exponerla** → requiere: entrada en catálogo/allowlist del gateway + `validate` de payload + workflow n8n nuevo + (opcional) UI.

### 6.4 `crear_override_horario_puntual` (F) — sin acción de portal
- `crear_paquete_dia_especial` (lo que F reemplaza) **no tenía** acción ni workflow (era DB-only). Por lo tanto F **no rompe** nada del portal.
- **Decisión de producto**: si se quiere gestión de horarios especiales desde el portal, es feature nueva (catálogo + validate + workflow + UI). Si no, queda DB-only y el portal sigue igual.

### 6.5 Frontend portal operativo
- `reserva.crear_manual` (A07) y su UI siguen funcionando sin cambios de contrato (parche C/D aditivo). El frontend ya muestra el `message` de `conflicto`/`payload_invalido`; con el fix de §6.2, el usuario verá el motivo real del bloqueo de gap.
- Sin pantallas nuevas salvo que se decida exponer E o F.

---

## 7. Plan de validación integral TEST (por capa)

- **(a) DB directo** — ya VERDE A–F. Falta: correr una **regresión consolidada** post-F (smokes A–F juntos) + re-pin de los 11 fingerprints + confirmar S3 ausente.
- **(b) portal-api** — probar `reserva.crear_manual` vía gateway (firma HMAC, action binding, allowlist) en caminos ok/gap/no_disponible; confirmar que `conflicto` llega con message correcto tras el fix de A07.
- **(c) n8n workflows** — A07 con: reserva ok, gap bloqueante (checkin/checkout pisa vecino), no_disponible, payload inválido. Verificar que cada error crudo del SP mapea al código genérico correcto.
- **(d) frontend/portal operativo** — crear reserva manual desde la UI; ver que el bloqueo de gap muestra mensaje claro (no "error_entorno").
- **(e) regresión calendario/ODR** — confirmar `obtener_disponibilidad_rango` y las vistas de calendario intactas (fp ODR `37009a32`), sin efectos colaterales del cambio semanal.
- **(f) errores nuevos y mensajes** — recorrer cada error de §5 y validar su presentación final (código + message) en el borde correcto (gateway/n8n/UI).
- **(g) smoke end-to-end** — flujo real consulta→pre-reserva→(pago)→confirmación con un caso que dispare gap, atravesando gateway+n8n+DB, y un caso feliz.

**Gate para pasar a OPS**: (a)–(g) verdes, con foco en que ningún error nuevo caiga como `error_entorno` en el portal.

---

## 8. Plan de promoción OPS (DISEÑADO — no ejecutar todavía)

> Sólo diseño. Se ejecuta después de TEST integral verde.

- **Orden de despliegue**: 1) **DB** (consolidar A–F en OPS con el mismo método DROP+CREATE/patch dinámico y gates fail-closed de ambiente); 2) **workflows n8n** (A07 con mapeo de errores nuevos; + legacy si aplican); 3) **gateway** (solo si se exponen E/F); 4) **frontend** (solo si se exponen E/F).
- **Gates previos OPS**: ambiente `ops`; fingerprints OPS baseline pre-B1.3 == esperados; `crear_paquete_dia_especial` sin callers vivos en OPS (barrido en OPS, no solo repo); backup/*point-in-time* disponible.
- **Rollback strategy**: por bloque, con los rollbacks A–F (cada uno revierte solo lo suyo; el de F restaura S3). Orden de rollback inverso al de despliegue. Los patches C/D se revierten por sus rollbacks dedicados (remueven el bloque de gap por marcadores).
- **Consolidación canónica**: al cerrar, bump `6B_SCHEMA_SQL.md` **v1.12.0 → v1.13.0** (B1.3) + nuevo bootstrap; una sola vez, coordinado, sin tocar el carril CC ya consolidado.

---

## 9. Archivos exactos a tocar (cuando se apruebe el cierre)

**Necesarios (funcional):**
1. `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json` — mapear `checkin_pisa_checkout_anterior` + `checkout_pisa_checkin_posterior` → `conflicto`.
2. (si en uso) `db_crear_prereserva__TEMPLATE.json`, `db_confirmar_reserva__TEMPLATE.json`, `vita_w02_*`, `vita_w04_*` — mismo mapeo.

**Cierre/consolidación:**
3. `Docs/Implementacion/6B_SCHEMA_SQL.md` — bump v1.13.0 (tablas + funciones nuevas/reemplazadas/parcheadas B1.3).
4. `Docs/Implementacion/bootstrap_entorno_nuevo_v1.13.0/` — nuevo bootstrap con B1.3.
5. `DECISIONES_NO_REABRIR.md` (D-* B1.3), `Lecciones_Aprendidas.md` (L-*), `ESTADO_ACTUAL_VITA_DELTA.md`, `Pendiente_pre_produccion.md`, `CLAUDE.md`.

**Cascade (decisión retira/actualiza/histórico):**
6. Gates/smokes override `S0/S1/S2/S3` (`04-07`) — realinear `58d75c1b → 1bd96c89` **o** marcar históricos.
7. Docs cascade B1.2 (`06/07-07`) — nota "superseded por B1.3" (histórico).

**Opcional (producto — solo si se exponen E/F):**
8. `portal-api` (catálogo + allowlist + validate), workflow(s) n8n nuevo(s), `actionRegistry.ts` + pantallas frontend.

---

## 10. Riesgos

1. **UX de gap sin mapeo (alto)**: sin el fix de A07, todo bloqueo de gap vía portal aparece como `error_entorno` genérico. Es el riesgo funcional más concreto.
2. **Regresión falsa por fps viejos (medio)**: re-ejecutar smokes de override S0–S3 sin realinear `58d75c1b`→`1bd96c89` produce fallos de gate espurios. Decidir actualizar vs histórico antes de correr regresión.
3. **Alcance E/F en portal (medio)**: si el negocio necesita reserva pactada u overrides desde el portal, hay trabajo adicional (gateway+n8n+UI) no contemplado en A–F.
4. **Consolidación canónica (medio)**: el bump v1.12.0→v1.13.0 debe extender sin tocar el carril CC ya consolidado; coordinar una sola vez.
5. **Fingerprints "intactos" a confirmar (bajo)**: verificar en TEST que wrapper `1bd96c89` y ODR `37009a32` siguen idénticos post-F (el re-pin lo cierra).
6. **Barrido OPS de S3 (bajo)**: el barrido de callers de `crear_paquete_dia_especial` fue sobre el repo (limpio); antes de OPS, repetirlo contra OPS real.

---

## 11. Orden recomendado

1. **Re-pin en TEST**: verificar los 11 fingerprints + ODR/wrapper intactos + S3 ausente (read-only).
2. **Decisiones de producto**: (a) exponer E por portal sí/no; (b) exponer F por portal sí/no. Gobiernan cuánto de §6.3/§6.4/§9-opcional entra.
3. **Decisión cascade**: actualizar gates/smokes S0–S3 a `1bd96c89` **o** declararlos históricos (define §9.6).
4. **Fix funcional A07** (y legacy si aplican): mapeo de los 2 errores de gap. Necesario para UX correcta.
5. **Validación integral TEST** (a)–(g).
6. **Consolidación**: 6B v1.13.0 + bootstrap + docs vivos (D-*/L-*).
7. **Plan OPS** (ya diseñado en §8) → ejecutar recién con TEST verde integral.

> Con esto claro, el próximo paso es tu decisión sobre §11.2 (alcance E/F en portal) y §11.3 (cascade), y recién ahí generamos artefactos de cierre / ajuste de portal.
