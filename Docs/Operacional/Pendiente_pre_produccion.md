# Pendientes Pre-Producción

Lista de cambios y configuraciones a aplicar antes del despliegue de
producción. Incluye pendientes que no se hicieron en DEV, ajustes ya cerrados en DEV que deben replicarse en TEST/PROD, y decisiones postergadas explícitamente.

**Estado del archivo:** actualizado al **cierre estructural del frente Cuenta Corriente — snapshot mensual con detalle fino congelado + L3 histórico + canónico v1.12.0** (2026-07-07). Sobre el **Carril B** y el **Carril C** (ambos en OPS) y la **capa de escritura del retiro** (v1.11.0), se sumó el **congelado con detalle fino** (3 tablas append-only + 6 triggers + snapshot extendido) y la **lectura histórica L3** (2 funciones), **promovidos a OPS solo estructura** (greenfield en datos). **Pendientes activos:** la **primera foto real en OPS + el cierre asistido** (P-L3-01/P-L3-02); la **UI del Portal para "Retirar saldo"** (frente frontend posterior); la exposición de CC/L3 en el portal; los **reembolsos** (remanente de P-CC-2); la corrida end-to-end del bootstrap kit sobre un Supabase nuevo; el cosmético de comentarios `D-C-61…64` del gateway A10-MP (solo si se edita ese artefacto); y los pendientes históricos/futuros (RLS para frontend público, tarifas/feriados productivos, capa fiscal AFIP/ARCA, entorno PROD público) listados abajo.

Items cerrados durante Etapas 6D, 7A, 7B, 8A, 8B, 8C, 8D, sub-etapa 8C-bis, 9B/3b y Carril B 9C–9H listados en los resúmenes de abajo;
detalle histórico de los items 6D en el Apéndice al final del documento.

---

## Items cerrados en Etapa 6D — resumen

| Item | Estado | Bloque que lo cerró | Apéndice |
|---|---|---|---|
| Hardening de validación SQL en funciones write | ✅ Cerrado | H2, H3, H4, H4-bis, H4-ter | A.1 |
| Fix `vista_ocupacion` (rango 25 → 24 meses) | ✅ Cerrado | H5 | A.2 |
| Espacio colgando en concatenación nombre + apellido | ✅ Cerrado | H6, H6-bis | A.3 |
| Tests de concurrencia C-1 a C-6 | ✅ Cerrado | H7 | A.5 |

## Items cerrados en Etapa 7A — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| 1.1 — Horizonte de disponibilidad/calendario configurable (60 → 120) | ✅ Cerrado | PreOPS-A6 | D-7A-03, `7A_CIERRE.md` |
| 1.2 — Alineación de tipo `ninos` (función vs columnas) | ✅ Cerrado | Patch `crear_prereserva` v1.7.3 | D-7A-02, `7A_CIERRE.md` |
| 1.3 — Contrato de `canal_pago_esperado` (validación manual) | ✅ Cerrado | Patch `crear_prereserva` v1.7.3 | D-7A-01, `7A_CIERRE.md` |

## Items cerrados en Etapa 7B — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Creación del entorno TEST (proyecto Supabase independiente) | ✅ Cerrado | 7B-1 | D-7B-01, `7B_CIERRE.md` |
| Paridad estructural TEST vs DEV (schema v1.7.3, 10/10) | ✅ Cerrado | 7B-2 | `7B_CIERRE.md` sección 5 |
| Seeds mínimos en TEST | ✅ Cerrado | 7B-3 | `7B_CIERRE.md` sección 6 |
| `pg_cron` activo en TEST con ejecuciones reales | ✅ Cerrado | 7B-3-cron | `7B_CIERRE.md` sección 7 |
| Permisos Data API normalizados en TEST (REVOKE EXECUTE) | ✅ Cerrado | 7B-GRANTS | D-7B-03, D-7B-05 |
| Workflows `__TEST` importados y validados (happy path 8/8) | ✅ Cerrado | 7B-4 | D-7B-04, `7B_CIERRE.md` sección 9 |
| Cadena transaccional end-to-end W2→W3→W4 en TEST | ✅ Cerrado | 7B-4 | `7B_CIERRE.md` sección 10 |

## Items cerrados en Etapa 8A — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Creación del entorno OPS (proyecto Supabase independiente) | ✅ Cerrado | 8A Bloques 1-2 | `8A_CIERRE.md` |
| Replicación del schema desde canónico v1.7.3 (paridad P01-P10 10/10) | ✅ Cerrado | 8A Bloque 4 | `8A_CIERRE.md` sección 3.1 |
| Seeds reales mínimos en OPS (item 4.1 — cabañas reales con IDs propios) | ✅ Cerrado | 8A Bloque 5 | `8A_CIERRE.md` sección 3.2 |
| Grants mínimos en OPS (OPS nació cerrado; REVOKE idempotente Opción B) | ✅ Cerrado | 8A Bloque 6 | confirmación D-8-03 |
| Default privileges de OPS (objetos futuros nacen cerrados) | ✅ Cerrado | 8A Bloque 7 | D-8-13, `8A_CIERRE.md` |
| `pg_cron` activo en OPS con corrida real verificada | ✅ Cerrado | 8A Bloque 8 | `8A_CIERRE.md` |
| Credencial n8n `vita_supabase_ops` verificada por identidad | ✅ Cerrado | 8A Bloques 10-11 | `8A_CIERRE.md` |

**Items pendientes activos:** ver secciones 1 a 8 abajo. **Nota:** las secciones 1.1, 1.2 y 1.3 quedaron cerradas en Etapa 7A (detalle conservado abajo con marca de cierre). Los items cerrados en 7B (entorno TEST levantado) se registran en el resumen de arriba; detalle completo en `7B_CIERRE.md`, no se duplica aquí.

## Items cerrados en Etapa 8B — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Capa de carga interna (Form Trigger n8n encadenando las 3 funciones) | ✅ Cerrado | 8B, validado en TEST | `8B_CIERRE.md` |
| Verificación de contratos reales de funciones contra OPS (read-only) | ✅ Cerrado | 8B sección 2 | `8B_CIERRE.md` §4 |
| Primer write real en OPS (smoke con reserva real, id 1) | ✅ Cerrado | 8B smoke OPS | `8B_CIERRE.md` §8 |
| Trazabilidad multiusuario verificada en producción (`created_by`/`validado_por`/`source_event`) | ✅ Cerrado | 8B smoke OPS | D-8B-04 |

**Pendiente operativo nuevo (no de schema/seguridad):** activar el workflow
`vita_w8b_carga_reserva__OPS` en n8n para que el equipo cargue por la URL del
formulario sin ejecución manual. El smoke se hizo con ejecución observada (correcto
para el primer write); para uso diario el workflow debe quedar activo. Ver
`8B_CIERRE.md` §10.

**Bitácora / cierres recientes:** `8A_CIERRE.md` (entorno OPS), `8B_CIERRE.md` (capa de carga).

## Items cerrados / tocados en Etapa 8C — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Calendarios visuales (HTML operativo + HTML limpieza + Sheet resguardo, solo lectura) | ✅ Cerrado en TEST + OPS | 8C, validado en TEST y activo en OPS | `8C_CIERRE.md` |
| Resguardo vía n8n+HTTP a API REST de Sheets, NO Apps Script | ✅ Decidido | 8C Bloque 3 | D-8C-22 |
| Smoke OPS de 8C (derivar, verificar, activar) | ✅ Cerrado | posterior a 8C | HTML operativo y limpieza activos y en uso real |
| Item 3.1 (notificación a Jennifer por reserva próxima) → resuelto como 8C-bis | ✅ Cerrado | 8C-bis (mail, rama lateral en 8B) | `8C-bis_CIERRE.md`, D-8Cbis-01..10, §3.1 |

**Smoke OPS de 8C: ✅ ejecutado.** Los HTML operativo y limpieza se derivaron a OPS
(credencial OPS, paths `w8c-op-ops`/`w8c-limp-ops`, Sheet de OPS para el resguardo) y se
**activaron**; el equipo los usa en producción. El resguardo OPS es manual.

**Pendiente diferido de 8C — ✅ RESUELTO en 8C-bis:** **8C-bis — Alerta por reserva
próxima** (recogía el item 3.1 de este documento). Cerrado el 2026-06-04 con documento
propio `8C-bis_CIERRE.md`. Canal resuelto = **mail** (D-8Cbis-01). Ver §3.1 (marcado
resuelto) y el resumen de 8C-bis abajo.

## Items cerrados / tocados en Sub-etapa 8C-bis — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Item 3.1 — Alerta por reserva próxima a equipo + Jennifer (mail) | ✅ Cerrado | 8C-bis, TEST validado + OPS activo | `8C-bis_CIERRE.md` |
| Canal de notificación = mail (no Telegram/WhatsApp) | ✅ Decidido | 8C-bis | D-8Cbis-01 |
| Disparo en rama lateral desde 8B (no afecta la reserva si el mail falla) | ✅ Cerrado | 8C-bis, validado end-to-end en TEST | D-8Cbis-02, `8C-bis_CIERRE.md` §6 |
| Privacidad por construcción (mail sin montos/huésped/teléfono/notas) | ✅ Cerrado | 8C-bis | D-8Cbis-05 |
| Enganche publicado y activo en 8B OPS (`entorno: "ops"`, destinatarios reales) | ✅ Cerrado | 8C-bis | `8C-bis_CIERRE.md` §8 |

**Estado de 8C-bis: ✅ publicado y activo en OPS.** Sub-workflow `vita_w8cbis_alerta__OPS`
(id `fHzMFj7pGMKuYEOb`) invocado en rama lateral desde el formulario de producción
`vita_w8b_carga_reserva__OPS`. Destinatarios reales: operativo Franco + Rodrigo, limpieza
Jennifer. La **primera ejecución real** quedará registrada con la próxima reserva con
check-in en la ventana [hoy, hoy+7]; la garantía de no-afectación (validada en TEST)
protege esa corrida. Pendiente menor futuro: migrar el remitente SMTP (hoy Gmail personal
de Franco) al mail propio de las cabañas, sin rediseño (D-8Cbis-09).

**Nota sobre el pendiente operativo de 8B** (activar el formulario OPS para uso por URL):
al cierre de 8C-bis, `vita_w8b_carga_reserva__OPS` ya está **activo y publicado** —
ese pendiente queda cubierto.

## Items cerrados / tocados en Etapa 8D — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Capa de bloqueos operativos (Form Trigger que invoca `crear_bloqueo`) | ✅ Cerrado en TEST + OPS | 8D, validado en TEST y activo en OPS | `8D_CIERRE.md` |
| Verificación read-only del contrato de `crear_bloqueo` | ✅ Cerrado | 8D, contra TEST | `8D_CIERRE.md` §3 |
| Primer bloqueo real creado en OPS | ✅ Cerrado | 8D smoke OPS | `8D_CIERRE.md` §6.2 |
| **Etapa 8 completa** (8A entorno + 8B reservas + 8C calendarios + 8D bloqueos) | ✅ Cerrada | 8D | `8D_CIERRE.md` §11 |

**Pendiente nuevo de 8D (no de schema):** **edición / baja de bloqueos**. 8D solo crea
(D-8D-09); levantar o corregir un bloqueo es manual (`activo=false` vía SQL aprobado). Si
se vuelve frecuente, sería una capa posterior con su propio formulario. No urgente.

**Bitácoras / cierres recientes:** `8C_CIERRE.md`, `8D_CIERRE.md`, `8D_EJECUCION.md`.

**Bitácora del hardening:** `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` (H1-H7 cerrados; H8 cerrado).
**Cierre Etapa 7A:** `7A_CIERRE.md`.
**Cierre Etapa 7B:** `7B_CIERRE.md`.

---

## Items cerrados / tocados en Etapa 9B / Fase 3b — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Cobranza posterior multi-porción (Form Trigger transaccional) | ✅ Cerrado **en TEST** | 3b, batería completa en TEST | `9B_CIERRE.md` |
| Helper SQL `public.abortar_si_falla(jsonb)` | ✅ Creado y micro-testeado en TEST | 3b | `9B_CIERRE.md` §3 |
| Rollback todo-o-nada (D-9B-19) | ✅ Validado en TEST (0 pagos tras abort) | 3b smoke 10 | `9B_CIERRE.md` §6-7 |

## Items cerrados / tocados en Etapas 9C–9H (Carril B completo) — resumen

| Item | Estado | Etapa | Referencia |
|---|---|---|---|
| Catálogo enriquecido (`valor_relativo`, beneficiario) + zonas + seam | ✅ Cerrado en TEST | 9C | `9C_CIERRE.md` |
| Placeholder `Socio 3` → `Remo` (prerequisito Carril B) | ✅ Resuelto en TEST | 9C (D-9C-21) | `9C_CIERRE.md` |
| Activación operativa por rango + pool real (Guatemala desde nov-2026) | ✅ Cerrado en TEST | 9D (D-9D-10) | `9D_CIERRE.md` |
| Matriz dinámica + reparto con centavo residual | ✅ Cerrado en TEST | 9E (D-9E-08) | `9E_CIERRE.md` |
| Gasto interno rediseñado (`gastos_internos`; legacy congelada) | ✅ Cerrado en TEST | 9F (D-9F-01) | `9F_CIERRE.md` |
| Cascada de liquidación read-only (6 funciones, 11 pasos, 40/40) | ✅ Cerrado en TEST | 9G | `9G_CIERRE.md` |
| Liquidación del `extra` (5%) | ✅ Resuelta por diseño: ingreso post-operativo (paso 6) | conceptual §4.3 / 9G | `9G_CIERRE.md` |
| Cuenta corriente interna: snapshots congelados + mayor + revaluación (capa con estado) | ✅ Cerrado en TEST | 9H | `9H_CIERRE.md` |
| Fixtures de laboratorio (9F ids 30–34; 9G pagos ids 39–43; 9H carga `seed_9h_d`) | ✅ Promoción hecha (jun-2026); **no viajaron a OPS** (estructura recreada por DDL, datos no copiados) | D-9F-17 / D-9G-13 / D-9H-20 | cierres 9F/9G/9H |

## ✅ CERRADO (2026-06-14) — Promoción coordinada del Carril B a OPS (incluye 9B / Fase 3b)

> **✅ CERRADO (2026-06-14).** El Carril B completo (helper 9B + 9C→9H) fue **promovido a OPS** como paquete único, con bump del canónico a **v1.8.0**. Paridad estructural verificada (huella `TOTAL_CARRIL` de 31 objetos idéntica TEST↔OPS, `f5187092083451ceb5b182334bdb4a17`), hardening sin exposición a Data API (9 tablas + 6 secuencias + 21 funciones), smokes 18/18 read-only en OPS y el workflow `vita_w09_cobranza_posterior` (14 nodos) andando en OPS. Cierre: `PROMOCION_CARRIL_B_OPS_CIERRE.md` (D-PROMO-01..13 / L-PROMO-01..08). El contenido original se conserva abajo como referencia histórica.

(El alcance original de esta sección era solo 3b; con el Carril B completo —capa derivada 9C→9G + capa con estado 9H— cerrado, la promoción es un **paquete único** — decisión vigente desde 9B, ratificada en los cierres de 9G y 9H.)

- **Crear `public.abortar_si_falla(jsonb)` en OPS antes de importar 3b.** Es aditiva (no
  toca tablas, enums ni `registrar_pago()`), pero si falta, 3b falla en runtime: el rollback
  transaccional depende de ella. DDL documentada en `9B_CIERRE.md` §3. Al crearla en OPS,
  aplicar `SET search_path = public, pg_temp` + `REVOKE EXECUTE … FROM PUBLIC, anon,
  authenticated, service_role` (paridad con D-7B-05) y verificar grants en 0 filas.
- **Promover el workflow 3b a OPS** (`__OPS`, credencial `vita_supabase_ops`, Basic Auth
  propia, path propio, marcador de entorno `ops`). TEST antes que OPS; smoke con datos
  reales antes de considerar la cobranza posterior productiva. Revisar marcadores de entorno
  embebidos en el código, no solo la credencial (L-8D-03).
- **Heredado de D-9B-15:** conversión / tabla de ahorro de monedas (la porción "otros" hoy
  se registra en ARS por equivalente, con trazabilidad en notas). Queda fuera de 3b; se
  define en la arquitectura global de contabilidad (Carril B).
- **Liquidación del `extra` (recargo 5%):** definir si es repartible, gasto financiero,
  comisión interna o ingreso separado. Fuera de 3b; Carril B.
  → **Resuelto en 9G:** el `extra` es ingreso **post-operativo** (paso 6 de la cascada,
  conceptual §4.3); no integra la base del % operativo y se compara contra el monotributo
  sin netear vía `reporte_5_vs_fiscal_periodo` (D-9G-11).
- **Paquete Carril B (9C→9H):** además de `abortar_si_falla` y el workflow 3b, la promoción
  coordinada recrea por DDL: columnas de `cabanas` + `zonas`/`cabana_zona` + seam (9C),
  `activaciones_operativas` + pool real (9D), las 3 funciones de matriz/reparto (9E),
  `gastos_internos` (9F), las 6 funciones de cascada (9G) y la **capa con estado de 9H** (las 5
  tablas `liquidaciones_periodo`/`liquidacion_cascada`/`liquidacion_socio`/`movimientos_socio`/
  `revaluaciones` + la función y 10 triggers de inmutabilidad + las 9 funciones), con **bump único
  del canónico**, marcador `'ambiente'='ops'` (D-9C-19), destino de la `gastos` legacy (D-9F-01) y
  GRANTs/RLS operativos a decidir en ese momento. **Los fixtures (`seed_9f_validacion`, `seed_9g_%`,
  `seed_9h_d`) NO viajan** (D-9F-17 / D-9G-13 / D-9H-20): se recrea estructura, no se copian datos.
  Verificar socios reales en OPS (L-9C-01).

**Bitácoras / cierres recientes:** `9C_CIERRE.md`, `9D_CIERRE.md`, `9E_CIERRE.md`, `9F_CIERRE.md`, `9G_CIERRE.md` (Carril B — capa derivada), `9H_CIERRE.md` (Carril B — capa con estado, cierra el carril), `PROMOCION_CARRIL_B_OPS_CIERRE.md` (promoción del Carril B a OPS + canónico v1.8.0); previos: `8D_CIERRE.md`, `9B_CIERRE.md`.

---

## Pendiente — Reconstrucción de DEV desde v1.8.0

> **✅ CERRADA (2026-06-15).** DEV se reconstruyó desde cero en un proyecto Supabase nuevo (`VITA_DELTA_DEV`, `DEV_REF=wsrdzjmvnzxidjlovlja`, PG 17.6) desde el canónico v1.8.0 (Parte B + Parte C), **creado cerrado como OPS**, `ambiente='dev'`, validado al bootstrap (base = paridad 8A; Carril B 9/21/10/6; seam 5/5; matriz 378/456; reparto exacto) y endurecido (REVOKE de las 13 funciones del motor → 0 expuestas). OPS/TEST intactos; DEV viejo congelado. Surgió un **gap del canónico** (Parte B no endurece las funciones base) → **canonizado en v1.8.1** (Bloque 23; ver detalle abajo). Cierre: `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md`.

(DEV quedó **fuera del alcance** de la promoción del Carril B; la promoción tocó TEST y OPS. DEV se reconstruyó en una etapa posterior, separada — no reabrió 9C→9H ni la promoción.)

- **DEV se rearma desde el canónico `6B_SCHEMA_SQL.md v1.8.0`**, que es autocontenido (Parte B + Parte C verificadas en bootstrap fresco). No depende de TEST/OPS ni de fixtures.
- **No es bloqueante de OPS:** OPS ya está promovido y operativo. La reconstrucción de DEV es una etapa posterior, de menor riesgo.
- **Pre-validable con harness local** (L-PROMO-08): un PostgreSQL local permite pre-correr el bootstrap antes de tocar DEV. Atención a diferencias de versión (PG16 local no tiene `MAINTAIN(m)` ni `pg_cron`; OPS es PG17), que no afectan la estructura del Carril B pero sí el ruido de permisos.
- **Residual de permisos de tabla en DEV** (hallazgo A5 / pendiente 1.7): revocar o aceptar al reconstruir. No urgente; OPS ya nació sin ese problema.

---

## ✅ CERRADO (2026-06-29) — Promoción coordinada del Carril C a OPS + canónico/kit v1.9.0

> **✅ CERRADA (2026-06-29).** El Carril C completo (Portal Operativo Interno: gateway `portal-api`, los 13 wrappers n8n y el frontend) quedó **promovido a OPS** en una operación coordinada bloque por bloque (Bloques A→H), **por DDL y sin copiar datos de TEST**, con el canónico `6B_SCHEMA_SQL.md` **bumpeado a v1.9.0** (Bloque I: portal como PARTE D) y el bootstrap kit regenerado a `bootstrap_entorno_nuevo_v1.9.0/` (9 archivos). Paridad estructural TEST↔OPS del portal por **fingerprint** (`TOTAL_PORTAL` idéntica) + **smokes read-only end-to-end por rol 14/14** (anti-OPS respetado: cero escrituras, cero consumo de secuencias). Decisiones **D-PROMO-C-01…14**; lecciones **L-PROMO-C-01…08**; deuda **D-C-64…70** (A10-MP) **saldada** en el ledger. Cierre: `PROMOCION_CARRIL_C_OPS_CIERRE.md`.

Pendientes de diseño/seguridad que la promoción **resolvió**: **P-C-7** (CORS por env var `CORS_ALLOW_ORIGIN`, nunca `'*'`), **P-C-8** (HMAC propio de OPS en los wrappers), **P-FE-09** (banner OPS) — ver sus ítems marcados ✅ abajo. **W10** (`cobranza.registrar_saldo`) queda **deprecated-in-place** a propósito (el frontend usa solo A10-MP `cobranza.registrar_cobro`); **no es deuda**.

Pendientes **nuevos** (no bloqueantes) derivados de este cierre:

- **Corrida end-to-end del bootstrap kit v1.12.0 (01→03) sobre un Supabase nuevo.** El kit quedó validado contra un PostgreSQL limpio y verificado por estructura (verify final estricto), pero **aún no ejecutado de punta a punta sobre un Supabase real**. No bloqueante; pendiente de réplica/recuperación de entornos. (Franco la ejecuta cuando quiera.)
- **Cosmético — comentarios `D-C-61…64` en el artefacto del gateway A10-MP.** Los comentarios del código desplegado citan provisionalmente `D-C-61…64` por arrastre del parche; la numeración **oficial** es **D-C-64…70** (D-C-61/62/63 son de A04). **No afecta runtime** (los comentarios no se ejecutan). Corregir **solo si el artefacto se edita/propaga**. Ver `A10MP_CIERRE.md` §3 y `PROMOCION_CARRIL_C_OPS_CIERRE.md` §10.

---

## ✅ CERRADO estructuralmente (2026-07-06/07) — Frente Cuenta Corriente: snapshot con detalle fino congelado + L3 histórico + canónico v1.12.0

Se cerró la capa de **congelado + lectura histórica** de la cuenta corriente, en dos bloques aditivos sobre la foto 9H. **Bloque 1 (extensión del snapshot, 2026-07-06):** `registrar_snapshot_periodo` extendida congela —en la misma txn/`pg_advisory_xact_lock` que cascada+socios— el detalle fino (participación por cabaña, gastos = foto fiel de `gastos_internos`, incidencias por gasto), vía **3 tablas append-only** (`liquidacion_participacion`/`liquidacion_gasto`/`liquidacion_incidencia`; PKs compuestas, 0 secuencias) con **inmutabilidad/REVOKE/supersesión idénticas a 9H** (C6 → 8 tablas / 16 triggers); matriz y nombres derivados; `id_gasto` copiado **sin FK** (foto autocontenida). **Bloque 2 (L3, 2026-07-07):** **2 funciones read-only** —`cuenta_corriente_historico(date)` y `cuenta_corriente_historico_acumulados()`— sobre la foto vigente (`liquidacion_vigente`, nunca superseded), `search_path` fijo, `STABLE`/`SECURITY INVOKER`, revocadas; una sola construcción cubre foto-con-detalle y pre-extensión; el piso no se doble-filtra. **Promovido a OPS solo estructura:** greenfield en datos (L3 devuelve `sin_foto`/`sin_datos`). Validación: harness 16.14 + `pglast`; TEST funcional (extensión Run 05 11/11 rollback-first; L3 14/14 + contrato 3 fotos + rollback-first efímero); OPS estructural (extensión `04_VERIFY` 5/19/7 + 6 triggers + 0 grants; L3 14/14 + smoke greenfield 6/6). Canónico **v1.12.0** (conteos vigentes **35/38/16**). **Decisiones D-CC-23…39; lecciones L-CC-13…19.** **Canonicalización (paquete coordinado de 3 bloques que absorbe P-L3-03 del cierre de L3):** Bloque A (canónico v1.12.0) hecho · Bloque B (satélites, este paquete) · Bloque C (bootstrap kit → v1.12.0) = **P-CC-4**, luego cerrado el 2026-07-08. Cierres: `EXT_SNAPSHOT_BLOQUE1_CIERRE.md`, `L3_HISTORICO_BLOQUE2_CIERRE.md`.

## ✅ CERRADO (2026-07-05) — Frente Cuenta Corriente escritura/retiro desde saldo vivo (backend+gateway) + canónico v1.11.0

Se construyó y **promovió a OPS** la **capa de escritura** de la cuenta corriente (retiro contra saldo vivo desde el portal), bloque por bloque: **SB0** (`portal_usuarios.id_socio` + FK a `socios` `ON DELETE RESTRICT` + `UNIQUE` + `CHECK` bicondicional, backfill por `lower(btrim(nombre))`), **SB1** (`portal_idempotencia_cc` `REVOKE`-all + `registrar_retiro_desde_saldo_vivo(...)` + `portal_registrar_retiro(jsonb)`), **A29** (gateway `cuenta_corriente.retirar` **socio-only** con `injectSocioIdentity` + wrapper firmado `portal-a29-retiro__OPS`). **Anti-OPS estricto:** el smoke OPS es **negative-only** (sin happy-path, sin retiro real, sin consumo de secuencias); verificado con `portal_idempotencia_cc` **vacía** y secuencia **sin avance**. Canónico `6B_SCHEMA_SQL.md` **bumpeado a v1.11.0** (SB0 + `portal_idempotencia_cc` + las 2 funciones + **D5 extendido a la 2ª FK**; aditivo). Validación: SB0 `A2` 10/10; SB1 23/23; gateway `tsc`/`esbuild` (delta 0); wrapper `node --check` 5/5; smoke OPS **32/0** + PART B 8/8. **Decisiones D-CC-15…22; lección L-CC-12.** El **bootstrap kit** sigue en `bootstrap_entorno_nuevo_v1.9.0/` como **deuda consciente (P-CC-4)**: rezagado respecto de **v1.11.0** (le faltan las funciones CC de v1.10.0, el helper/seed de v1.10.1 y ahora SB0+SB1); se regenera **al cierre del frente completo** de cuenta corriente, **no dentro de este patch**. Cierre: `CIERRE_RETIRO_SALDO_VIVO_OPS.md`.

**Pendiente nuevo — UI del Portal Operativo para el retiro (frente posterior).** El backend y el gateway del retiro están **completos en OPS**, pero **no hay UI**: falta el botón/pantalla "Retirar saldo" en el Portal Operativo (formulario **socio-only** que arme el payload `{monto, medio_pago, comentario}`, use `useAction('cuenta_corriente.retirar')` con `idempotency_key`, y muestre `saldo_insuficiente`/éxito). Es un **frente separado**: en este cierre **no se tocó frontend**.

## ✅ CERRADO (2026-07-03) — Sub-bloque 0: pct operativo a `configuracion_general` + canónico v1.10.1

El porcentaje operativo (`0.25`) pasó de estar hardcodeado en los wrappers A27/A28 a la clave `pct_operativo` de `configuracion_general` (`tipo_valor='numeric'`, `editable=false`), leída por el helper `pct_operativo_vigente()` (validación fuerte, errores parseables, **sin fallback silencioso**). A27/A28 pasan a leer el helper; cambio **output-neutral** verificado por identidad SQL determinística + hash SHA256 pre/post del webhook directo, **idéntico en TEST (`7a4385…`) y OPS (`7e075a…`)**. Canónico `6B_SCHEMA_SQL.md` **bumpeado a v1.10.1** (helper en PARTE C + seed en C13; bump aditivo). Secuencia S0.1 (TEST) → S0.2 (wrappers TEST) → S0.3 (OPS) → S0.4 (cierre). El bootstrap kit sigue en `bootstrap_entorno_nuevo_v1.9.0/` como **deuda consciente (P-CC-4)**. **Decisiones D-CC-13/14; lecciones L-CC-09/10/11.** Cierre: `S0_CIERRE.md`.

## ✅ CERRADO (2026-07-02) — Frente Cuenta Corriente de socios (lecturas L1/L2) + canónico v1.10.0

Se expusieron como **lecturas read-only socio-only** en el Portal Operativo las dos vistas de cuenta corriente que **componen el motor del Carril B**: **L1 `cuenta_corriente.al_dia` (A27)** —saldo acumulado en vivo por socio desde el piso 2026-07-01— y **L2 `cuenta_corriente.detalle` (A28)** —drill-down de un mes (cascada + matriz + incidencias), jsonb compuesto—. Ambas `STABLE`/`SECURITY INVOKER` revocadas; `pct` 0.25 hardcodeado en el wrapper; A27 = primera acción `roles:['socio']`. **Promovido a OPS** (funciones `CREATE OR REPLACE` + 2 workflows `__OPS` + gateway sobre OPS A26; verificado en vivo) y **canónico bumpeado a v1.10.0** (2 funciones + `REVOKE` en la PARTE C). Validación: L1 recon ×3 + A27 11/11; L2 directo 6/6 + A28 15/15; frontend `tsc`+`build` EXIT 0; smokes directos read-only verdes en TEST y OPS. **D-CC-01…12 / L-CC-01…08.** Cierre `CIERRE_CARRIL_CUENTA_CORRIENTE_L1_L2.md`.

## Pendiente — Frente Cuenta Corriente (post-cierre L1/L2)

- **P-CC-1 — ✅ RESUELTO ESTRUCTURALMENTE (2026-07-07, Bloque 2 / L3).** La lectura histórica mes a mes de las fotos congeladas quedó construida y desplegada en TEST y OPS (`cuenta_corriente_historico(date)` + `cuenta_corriente_historico_acumulados()`, D-CC-31…39, canónico v1.12.0). Se cumplió D-CC-11 (congelar antes que L3): primero el snapshot extendido, después L3. **Remanente real → P-L3-01:** validar el camino de detalle completo **con datos reales persistidos** (hoy solo probado contra fotos pre-extensión y una foto efímera rollback-first). Cierre `L3_HISTORICO_BLOQUE2_CIERRE.md`.
- **P-CC-2 — Retiro HECHO + snapshot con detalle fino HECHO (estructura); falta primera foto real + cierre asistido + reembolsos.** El **retiro desde saldo vivo** (2026-07-05) y el **snapshot mensual con detalle fino congelado** (Bloque 1, 2026-07-07) quedaron **resueltos en estructura**: el congelado de la cascada completa del mes —ingresos, gastos, pasos, matriz/incidencias, resultado por socio + detalle por cabaña/gasto/incidencia— existe y está en OPS (greenfield en datos). **Sigue pendiente:** (a) la **primera foto real en OPS** (congelar un mes concreto con detalle sobre datos de producción, "IA propone, humanos aprueban") → **P-L3-02**; (b) el **cierre asistido** (preparar preview → revisar → congelar) → **P-L3-01/02**; (c) la **UI del retiro** (frente frontend posterior); (d) **reembolsos** (pendiente separado dentro del remanente de P-CC-2). No cerrar hasta que (a) y (b) estén hechos.
- **P-CC-3 — ✅ CERRADO (2026-07-03, Sub-bloque 0).** `pct` operativo movido a `configuracion_general` (clave `pct_operativo`, `editable=false`) + helper `pct_operativo_vigente()`; A27/A28 leen el helper (D-CC-13/14, canónico v1.10.1). Cierre `S0_CIERRE.md`.
- **P-CC-4 — Regenerar el bootstrap kit. ✅ CERRADO (2026-07-08, Bloque C).** La deuda de paridad del bootstrap está **saldada**: el kit se regeneró a `bootstrap_entorno_nuevo_v1.12.0/` (9 archivos, **extracción literal R2** desde el canónico vigente `6B_SCHEMA_SQL.md v1.12.0` —PARTE B/C/D— + verify final estricto), paritario con el canónico (conteos **35/38/16**; Carril B 12 tablas / 27 funciones; portal 3 tablas / 2 funciones; seed `pct_operativo`). La carpeta `bootstrap_entorno_nuevo_v1.9.0/` se **retiró del árbol** (queda en el **historial de git**; sin doble fuente ejecutable). Validado en harness PostgreSQL 16.14 con stubs Supabase: reconstrucción 01→03 verde (auto-tests C14/D5 + verifies `PARTE_B_OK`/`PARTE_C_OK`/`ENTORNO_COMPLETO_OK`), **byte-proof de PARTE B** (inmutable v1.9.0→v1.12.0), EOL LF, scan sin Project Refs reales ni patrones sensibles. Commits `2c49e0e` (regeneración del kit) y `81964a4` (hotfix del footer canónico). **La corrida end-to-end del bootstrap sobre un Supabase nuevo NO forma parte de P-CC-4** y sigue como **pendiente separado** (ver arriba). Cierre: `BOOTSTRAP_PARIDAD_v1_12_0_CIERRE.md`.
- **P-CC-5 — `pct_operativo` periodizado / vigencia futura.** Hoy es un único valor vigente (0.25). Falta vigencia por período: cualquier cambio de porcentaje debe aplicar **hacia adelante**, sin recalcular retroactivamente meses anteriores (tabla de vigencias o `pct_operativo_para_periodo(p_periodo date)`; `cuenta_corriente_viva/detalle` resolverían el pct por período internamente). Hasta tener este bloque, `pct_operativo` queda `editable=false` y **no debe cambiarse en operación**.
- **P-L3-01 — Camino de detalle completo de L3 con datos reales persistidos.** Ni TEST (solo pre-extensión) ni OPS (greenfield) tienen hoy una foto vigente con detalle persistido; ver el caso A con datos reales requiere un commit-freeze controlado o el primer cierre real. No bloquea el cierre técnico de L3. (Origen `L3_HISTORICO_BLOQUE2_CIERRE.md` §9.)
- **P-L3-02 — Primera foto real en OPS.** Congelar un mes concreto con su detalle fino en OPS (candidato: julio 2026, primer mes del piso D-NEG-02) vía el **cierre asistido** (preparar → revisar → congelar con `registrar_snapshot_periodo` ya extendida + `pct_operativo_vigente()`). Habilita P-L3-01. (Origen §9 + `EXT_SNAPSHOT_BLOQUE1_CIERRE.md` §8.)

## Carril C — Backend/API (pendientes de diseño → construcción)

- **P-C-1** — Brief del portal: reconciliar roles/permisos contra el catálogo si aparece `Prompt_Portal_Operativo_Interno.md`. No bloqueante (D-C-01).
- **P-C-2** — Confirmar al construir los nombres exactos de campos de los workflows reusados (8B/8D/9/calendarios) y la reutilizabilidad de la lectura 8C-bis para A05, contra los `__TEMPLATE.json` reales (no están en el repo).
- **P-C-3** — Contrato formal JSON de calendarios (vs HTML temporal, D-C-09). Post-MVP.
- **P-C-4** — Hardening del portal post-MVP: rate-limiting/abuso, rotación del secreto HMAC, expiración/refresh de sesión fino. Fuera del modelo mínimo (Fase 0.5).
- **P-C-5** — A09 editar/levantar bloqueo: capa futura con su propio contrato/workflow (D-C-12 / D-8D-09).
- **P-C-6** — Contabilidad societaria lectura (A14–A18) y escritura (A19–A23): fases posteriores, solo `socio`; arrancan con la operación de julio.
- **P-C-7** — **CORS de `portal-api`:** hoy abierto (`*`) en Slice 0; **restringir al origin real** del Portal Operativo antes de exponerlo. No bloqueante para TEST. **(Contrato Frontend v1, 2026-06-22):** el origin del frontend TEST queda como placeholder `<ORIGIN_PORTAL_TEST>` (ej. no vinculante `http://localhost:5173`); se fija al construir el Frontend TEST. Nota: el comentario inline del gateway cita "(P-C-4)" para esta restricción, pero el ítem real es **P-C-7** (P-C-4 es otro: hardening post-MVP). **(Frontend sub-slice 0, 2026-06-23):** en desarrollo local el origin es `http://localhost:5173` y CORS `*` no bloquea; la restricción al origin real del portal sigue pendiente para cuando se exponga fuera de TEST. **✅ RESUELTO (2026-06-29, promoción del Carril C a OPS):** el gateway pasó a CORS por **env var `CORS_ALLOW_ORIGIN` obligatoria** (el preflight falla si falta; **nunca `'*'`**), en OPS apuntando al dominio del frontend de producción (D-PROMO-C-03).
- **P-C-8** — **Secreto HMAC de OPS:** generar `VITA_HMAC_SECRET` propio de OPS (distinto del de TEST) en la promoción del portal a OPS; mismo nombre de variable, valor distinto por entorno (D-C-33). El de TEST se rotó 2026-06-16. **✅ RESUELTO (2026-06-29, promoción del Carril C a OPS):** los 13 wrappers `__OPS` usan el **HMAC de OPS** (distinto del de TEST) embebido en `validar_firma_ts_rol` (Modo B, sin plan de Variables): mismo nombre de variable, valor distinto por entorno (D-PROMO-C-02).
- **P-C-9** — **Store anti-replay de `nonce`:** en Slice 0 alcanza la ventana `ts` ±300 s; agregar tabla de unicidad de `nonce` al entrar la **primera escritura no-idempotente sin guard** sobre n8n (realísticamente A11) (D-C-29). **✅ RESUELTO EN TEST para Carril C.** No queda gap de diseño; su aplicación en OPS viaja dentro de la promoción coordinada. (Slice 3b — A11 lo materializa con `UNIQUE(nonce)` en `portal_idempotencia`, infra TEST-only fuera del canónico; `C_SLICE3B_CIERRE.md`.)
- **P-C-10** — **Rol Postgres dedicado de mínimos** para el lookup de `portal_usuarios`, en lugar de `service_role`, como endurecimiento posterior. No bloqueante.
- **P-C-11** — **Edge Functions por Dashboard:** el toggle "Verify JWT with legacy secret" se reactiva en cada redeploy desde el editor (L-C-06); migrar `portal-api` a CLI + `config.toml` (`verify_jwt=false`) si los redeploys se vuelven frecuentes.

## Carril C — Frontend (Portal Operativo) — pendientes

Pendientes surgidos del frontend del Portal Operativo Interno (**sub-slice 1**, las 8 lecturas; cierre `FRONTEND_SUBSLICE1_CIERRE.md`, 2026-06-24). Namespace `P-FE-XX`.

- **P-FE-01** — **`CABANAS_TEST` no portable → catálogo.** El mapeo `id_cabana→nombre` del filtro de cabaña (A24) está hardcodeado como constante **solo TEST** (IDs 1–5; en DEV son 17–21 y en OPS difieren por la secuencia SERIAL). Reemplazar por un **endpoint de catálogo** del backend antes de promover a OPS. Las filas igual muestran el nombre vía el campo `cabana` del backend; esto solo afecta las etiquetas del filtro.
- **P-FE-02** — **Anti-sobrecobro (pre-OPS, transversal).** Validar que **todos** los flujos productivos de cobro impidan sobrecobro no intencional. **Portal interno A10-MP (`cobranza.registrar_cobro`): cubierto** — B5 bloquea el sobrepago en la UI (submit deshabilitado + aviso si `suma_saldo > saldo_real`) y el backend lo rechaza **en duro** (`conflicto` / `excede_saldo`). **Siguen pendientes** los flujos **web pública / Mercado Pago / cobro autónomo del cliente** — son **otro frente** y todavía no tienen este doble bloqueo. Aceptar sobrepago/crédito debe ser una decisión **explícita**, nunca accidental. (W10 `cobranza.registrar_saldo` quedó deprecated-in-place; el ítem original lo nombraba. Hoy en TEST hay sobrepagos de fixtures; A04 los muestra como `$0` por D-C-62, A24 los muestra crudos por ser reporte.)
- **P-FE-03** — **Limpieza de datos TEST.** Depurar pagos duplicados / por encima de `monto_total` en TEST como **mini-etapa separada** (escritura acotada por id, con backup, ejecutada por Franco), si hace falta. No bloqueante; no se hace ahora para no romper smokes/reportes históricos de TEST.
- **P-FE-04** — **UX diferidas (sin patch ahora).** (a) Evitar desde el frontend `fecha_hasta < fecha_desde` (A24) y el rango de meses invertido (A25/A13) — el backend ya valida (A24 rebota; A25/A13 devuelven vacío). (b) Aclaración explícita en A25 (“muestra pagos según fecha de cobro, no de estadía”) y en A13 (“muestra gastos según período contable”).
- **P-FE-05** — **A13 filtros `id_zona` / `id_cabana` diferidos.** El payload de `gastos.listado` los admite, pero la UI no los expone todavía: necesitan endpoint de catálogo de zonas/cabañas (familia P-FE-01). Implementados: período (mes) + `clase {A,C,D,E}` + `pagador_tipo {socio,caja}` + `q`.
- **P-FE-06** — **A05 `nota` / `notas_reserva` en el contrato.** Incluir formalmente en el contrato frontend (la prosa original de A05 no las enumeraba; la visibilidad quedó resuelta por **D-C-63**: visibles para {vicky, socio}, no a jenny ni web pública).
- **P-FE-07** — **El gateway no propaga `detail.constraint`.** Las respuestas de error del `portal-api` traen `message` pero **no** el `detail`/nombre de constraint del backend, así que el frontend no puede mostrar mensajes finos por constraint: los mensajes específicos salen de la **pre-validación cliente** (espejo del validador, D-FE-23) y el fallback es el `message` genérico (familia A, D-FE-25). Revisar pre-OPS si se decide exponer `detail` por el gateway para mensajes más precisos. (Nombrado en los runsheets B1/B4; se canoniza acá.)
- **P-FE-08** — **"Ver detalle" A12→A05 por `?id_reserva` no implementado.** El deep-link de lectura→lectura (de saldos a cobrar A12 al detalle de reserva A05 vía query param) quedó **anticipado** (RUNSHEET_B4 §7) **pero sin construir**: `ReservaDetalle` (A05) sigue con **input manual de id**, no lee `useSearchParams`. En B5 solo se hizo el deep-link lectura→escritura A12→A10 ("Cobrar"). UX diferida, no bloqueante; al implementarla, A05 debe revalidar en destino igual que A10 (L-FE-05).
- **P-FE-09** — **Banner de ambiente: extender el reconocimiento al promover a OPS.** Hoy el banner reconoce **solo** el ref de TEST (`bdskhhbmcksskkzqkcdp`, **D-FE-29**) → todo lo demás cae en el estado defensivo `'desconocido'` (banner rojo) a propósito. Al promover el frontend a OPS hay que **extender `src/lib/ambiente.ts`** para reconocer el ref de OPS (`lpiatqztudxiwdlcoasv`) → ambiente `'ops'` **sin banner** (o con el rótulo de producción que se decida), de modo que el deploy OPS no muestre el aviso defensivo. El deploy OPS reutiliza el setup de Vercel de **D-FE-30** con las env vars de **OPS** (`VITE_SUPABASE_URL` del proyecto OPS + su anon key) y requiere además restringir el **CORS** del gateway al origin real (**P-C-7**) y el catálogo real de cabañas (**P-FE-01**). Aceptación en OPS: el banner **no** aparece (o muestra producción), no el defensivo. **✅ RESUELTO (2026-06-29, promoción del Carril C a OPS):** `lib/ambiente.ts` reconoce el ref de OPS como ambiente `'ops'` → **sin banner**; `BannerAmbiente.tsx` retorna `null` en OPS; ref desconocido sigue cayendo en el rojo defensivo y TEST conserva el amarillo (D-PROMO-C-06). Frontend desplegado en OPS (Vercel).

## Pendiente — Corrección canónica v1.8.1 (hardening de funciones base en Parte B)

**Estado:** ✅ CERRADA (canonizado en v1.8.1, jun-2026; el Bloque 23 incorpora el `REVOKE EXECUTE` de las 13 funciones base a PARTE B). Registrado 2026-06-15 en la reconstrucción de DEV.

**Contexto:** un bootstrap fresco de `6B_SCHEMA_SQL.md v1.8.0` deja las **13 funciones del motor** (`crear_prereserva`, `registrar_pago`, `confirmar_reserva`, los triggers `set_*`/`log_*`, etc.) **PUBLIC-ejecutables por la NULL-acl** (`proacl IS NULL ⇒ PUBLIC ejecuta`). La PARTE C/C12 endurece el Carril B, pero **PARTE B no incorpora el REVOKE de las funciones del motor**. El hardening del motor se vino aplicando fuera de banda por entorno (7E en DEV viejo, 8A Opción B en OPS, 7B-GRANTS en TEST, REVOKE de la reconstrucción en DEV nuevo); un futuro PROD lo necesitaría igual.

**Acción propuesta (a consultar antes):** agregar a PARTE B un bloque de hardening de funciones base —espejo de C12 para el motor— `REVOKE EXECUTE ON FUNCTION <las 13> FROM PUBLIC, anon, authenticated, service_role`, para que cualquier bootstrap futuro nazca cerrado sin paso manual. Bump a **v1.8.1**. No urgente; no bloquea operación.

**Origen:** reconstrucción de DEV (L-RDEV-01); `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md` §5.

---

## 1. Configuración de schema

### 1.1 Horizonte de disponibilidad — pasar de hardcoded a configurable

> **✅ CERRADO en Etapa 7A (PreOPS-A6, 2026-05-28).** El horizonte de
> `vista_disponibilidad` y `vista_calendario` ahora se lee desde
> `configuracion_general.horizonte_disponibilidad_dias` (valor `120`) con
> fallback `120`. La clave se agregó al seed del Bloque 21. Decisión D-7A-03.
> Ver `7A_CIERRE.md`. El contenido original se conserva abajo como referencia
> histórica del diseño.

**Estado actual (DEV):** `vista_disponibilidad` y `vista_calendario` tienen
el horizonte hardcoded a 60 días forward.

**Cambio para producción:**

Paso 1 — Agregar clave a `configuracion_general` (junto con el seed productivo):
- clave: `horizonte_disponibilidad_dias`
- valor: `120` (sugerido)
- tipo_valor: `integer`
- descripcion: `Horizonte forward en días para vista_disponibilidad y vista_calendario`

Paso 2 — Modificar las 2 vistas para leer desde config:

```sql
-- vista_disponibilidad con horizonte configurable
CREATE OR REPLACE VIEW vista_disponibilidad AS
SELECT *
FROM obtener_disponibilidad_rango(
  CURRENT_DATE,
  (CURRENT_DATE + COALESCE(
    (SELECT valor::INTEGER FROM configuracion_general
     WHERE clave = 'horizonte_disponibilidad_dias'),
    120
  ))::DATE,
  NULL
);

-- vista_calendario con horizonte configurable
-- Nota: el TRIM en huesped_nombre ya fue aplicado en H6 (Etapa 6D).
CREATE OR REPLACE VIEW vista_calendario AS
SELECT
  c.id_cabana, c.nombre AS cabana, r.id_reserva,
  r.fecha_checkin, r.fecha_checkout, r.hora_checkin, r.hora_checkout,
  r.personas, r.estado AS estado_reserva,
  TRIM(h.nombre || ' ' || COALESCE(h.apellido, '')) AS huesped_nombre,
  h.telefono AS huesped_telefono,
  r.monto_total, r.monto_saldo, r.encargado_semana
FROM reservas r
JOIN cabanas c ON c.id_cabana = r.id_cabana
JOIN huespedes h ON h.id_huesped = r.id_huesped
WHERE r.estado IN ('confirmada', 'activa')
  AND r.fecha_checkout >= CURRENT_DATE
  AND r.fecha_checkin <= (CURRENT_DATE + COALESCE(
    (SELECT valor::INTEGER FROM configuracion_general
     WHERE clave = 'horizonte_disponibilidad_dias'),
    120
  ))::DATE
ORDER BY r.fecha_checkin, c.id_cabana;
```

**Por qué `COALESCE` con default 120:** si la clave no existe por algún motivo,
la vista sigue funcionando con un valor sensato en vez de fallar.

**Cambio futuro del valor sin redeploy:**

```sql
UPDATE configuracion_general
SET valor = '90'  -- o '150' o lo que decidan
WHERE clave = 'horizonte_disponibilidad_dias';
```

**Origen:** decisión del Bloque 20, Fase 3.

### 1.2 Alineación de tipo `ninos` entre función y tablas

> **✅ CERRADO en Etapa 7A (patch `crear_prereserva` v1.7.3, 2026-05-28).**
> Resuelto con Opción 2: variable `v_ninos` alineada a `TEXT` en
> `crear_prereserva` (extract `NULLIF(TRIM(payload->>'ninos'), '')`, sin cast a
> BOOLEAN). Semántica: `NULL`=no informado, texto libre=detalle operativo.
> Los 3 registros legacy con `'false'` migrados a `NULL` (limpieza puntual).
> Decisión D-7A-02. Ver `7A_CIERRE.md`. Contenido original abajo como referencia.

**Estado actual (DEV):** ⏳ Pendiente liviano, no bloqueante.

**Contexto:** `crear_prereserva` declara la variable local `v_ninos` como `BOOLEAN` y aplica `(NULLIF(TRIM(payload->>'ninos'), ''))::BOOLEAN` en el extract. Sin embargo, las columnas `pre_reservas.ninos` y `reservas.ninos` son `TEXT nullable`. PostgreSQL aplica cast implícito BOOLEAN→TEXT al INSERT, persistiendo el valor textual `"false"` (observado empíricamente en los 3 registros existentes en DEV).

**Por qué es pendiente liviano:** funcionalmente inocuo hoy. No genera errores, no afecta operación, no se cruza con otras funciones. Pero la desalineación de tipo entre función y tablas es ruido documental que conviene resolver antes de TEST/PROD para evitar confusión futura.

**Opciones a evaluar:**
1. Alinear columnas a `BOOLEAN nullable` (cambio estructural en `pre_reservas` y `reservas`).
2. Alinear variable a `TEXT` (cambio en `crear_prereserva`).
3. Mantener desalineado y documentar como decisión definitiva.

**Origen:** hallazgo gestionado durante H8 Frente A (snapshot C.4). Documentado en changelog del bump v1.7.2 y en `H8_SNAPSHOTS_SCHEMA_v1.7.2_WORKING_NOTES.md`.

### 1.3 Contrato de `canal_pago_esperado` — validación manual vs schema

> **✅ CERRADO en Etapa 7A (patch `crear_prereserva` v1.7.3, 2026-05-28).**
> Resuelto con Opción 1: restaurada la validación manual de
> `canal_pago_esperado` en el IF de obligatorios de `crear_prereserva` →
> rebota `payload_invalido` para ausente/vacío/whitespace. La columna sigue
> `TEXT NOT NULL`; el CHECK de 5 valores se mantiene. Validación de valores
> fuera del CHECK queda fuera de alcance. Decisión D-7A-01. Ver `7A_CIERRE.md`.
> Contenido original abajo como referencia.

**Estado actual (DEV):** ⏳ Pendiente liviano, no bloqueante.

**Contexto:** el extract de `crear_prereserva` aplica el patrón canónico `NULLIF(TRIM(payload->>'canal_pago_esperado'), '')`, pero `canal_pago_esperado` no aparece en la validación manual post-extract de campos obligatorios. La columna `pre_reservas.canal_pago_esperado` sigue siendo `TEXT NOT NULL`. Si llega ausente, vacío o whitespace, la variable queda NULL y el INSERT falla por constraint `NOT NULL` con error crudo de PostgreSQL, no con `payload_invalido` controlado.

**Por qué es pendiente liviano:** los workflows reales de n8n hoy aplican `nv()` defensivo en Build Payload, así que el escenario no es operativo en DEV. Pero para TEST/PROD con consumidores reales (webhook MP, bot, frontend), conviene decidir un contrato explícito.

**Opciones a evaluar:**
1. Restaurar validación manual de `canal_pago_esperado` en `crear_prereserva` con rebote controlado `payload_invalido`.
2. Hacer la columna nullable a nivel schema y aceptar pre-reservas sin canal preferido.
3. Mantener comportamiento actual y documentar como decisión definitiva.

**Origen:** hallazgo gestionado post-revisión del bump v1.7.2 durante H8 Frente A. Documentado en changelog del bump v1.7.2 y en `H8_SNAPSHOTS_SCHEMA_v1.7.2_WORKING_NOTES.md`.

### 1.4 `tipo_valor` sin poblar en `configuracion_general`

**Estado actual (DEV):** ⏳ Observación liviana, no bloqueante.

**Contexto:** las 10 claves de `configuracion_general` en DEV tienen
`tipo_valor = NULL` sin excepción (incluye enteros como `prereserva_expiracion_minutos=60`
y `horizonte_disponibilidad_dias=120`, booleanos como `escalonamiento_activo=true`,
y horas como `hora_checkin_default=13:00`). El campo `tipo_valor` existe en el
schema pero nunca se pobló. Hallazgo surgido en PreOPS-A6 (Etapa 7A) al
inspeccionar la tabla completa.

**Por qué es observación, no bloqueo:** ninguna función ni vista depende de
`tipo_valor` — los casts (`valor::INTEGER`, `valor::TIME`, etc.) son explícitos
en cada query. El sistema funciona correctamente con `tipo_valor=NULL`.

**Cuándo conviene resolverlo:** antes de construir el dashboard operativo (OPS)
si el dashboard va a usar `tipo_valor` para decidir cómo renderizar inputs de
configuración (un campo de texto vs un selector de hora vs un toggle booleano).

**Opción sugerida (no decidida):** poblar `tipo_valor` en las 10 claves con un
UPDATE puntual, con valores como `integer`, `boolean`, `time` según corresponda.
No se hizo en 7A para no abrir un mini-proyecto de normalización fuera del
alcance del horizonte configurable.

**Origen:** hallazgo de PreOPS-A6 (Etapa 7A, 2026-05-28).

### 1.5 Endurecimiento de permisos Data API en DEV (paridad con TEST)

> **✅ CERRADO en Etapa 7E (2026-05-28).** Se aplicó a DEV el `REVOKE EXECUTE`
> sobre las 13 funciones del proyecto a `PUBLIC`/`anon`/`authenticated`/
> `service_role`, dejando owner `postgres` intacto. Verificado: 0 fugas de
> EXECUTE, owner intacto, `postgres` ejecuta por ownership (n8n no afectado),
> schema sin cambios (201/6/19), residual de tablas intacto (480 grants).
> Decisiones D-7E-01, D-7E-02. Ver `7E_CIERRE.md`. El hallazgo A5 (residual
> amplio de permisos de tabla a roles Data API) quedó fuera de alcance por
> decisión (Opción 1 — 7E estricta) y se registró como pendiente nuevo 1.7. El
> contenido original se conserva abajo como referencia histórica del diseño.

**Estado actual (DEV):** ⏳ Pendiente. No diseñado ni planificado todavía.

**Contexto:** durante Etapa 7B se aplicó en TEST un modelo de grants mínimo
(REVOKE EXECUTE a `PUBLIC`/`anon`/`authenticated`/`service_role` sobre las 13
funciones del proyecto; sin grants Data API útiles para roles no-owner; `Dxtm`
residual documentado como aceptado — ver D-7B-03 y D-7B-05).

**DEV no se tocó durante 7B** (por decisión explícita) y queda más abierto que
TEST: en DEV las 13 funciones siguen invocables vía Data API por roles
`PUBLIC`/`anon`/`authenticated`/`service_role`. Esto no es bug de DEV — es el
default de PostgreSQL/Supabase aplicado al crear cada función — pero rompe la
simetría con TEST.

**Por qué es pendiente, no urgencia:** mientras DEV no tenga frontend público ni
consumidores Data API externos, no es un riesgo activo (n8n entra por pooler
como `postgres` owner y no depende de `EXECUTE` para invocar funciones). El
endurecimiento de DEV conviene **antes de cualquier integración que exponga
Data API en DEV** y **antes del diseño de OPS/PROD** (para no propagar la
asimetría).

**Alcance esperado (a diseñar en una etapa propia):**
1. Diagnóstico read-only equivalente al G1-G5 de 7B-GRANTS aplicado a DEV.
2. Verificación previa de que el REVOKE no rompe consumidores existentes (n8n,
   posibles otros).
3. REVOKE EXECUTE sobre las 13 funciones a `PUBLIC` + roles Data API,
   idempotente.
4. Verificación posterior (G3 sin filas + owner intacto).
5. Decisión sobre el `Dxtm` residual de DEV (probablemente igual criterio que
   TEST: aceptado, no tocado).

No diseñar ni ejecutar ahora — queda como pendiente futuro registrado.

**Origen:** decisión explícita de 7B de no tocar DEV; D-7B-03; `7B_CIERRE.md`
sección 14.

### 1.6 Contrato SQL de `registrar_pago` frente a entradas no-vacías mal tipadas

**Estado actual:** ⏳ Pendiente liviano, no bloqueante.

Revisión futura del contrato SQL de `registrar_pago` frente a entradas no-vacías
mal tipadas; hoy mitigado en workflows por `nv()` defensivo para
vacíos/undefined.

**Contexto:** el patrón canónico `NULLIF(TRIM(payload->>'campo'), '')` aplicado en
6D (item A.1, cerrado) cubre vacíos y whitespace en los campos obligatorios. Lo
que queda fuera de esa defensa son las entradas **no-vacías pero mal tipadas**
(ej. un `monto_esperado:"abc"` que no es vacío pero tampoco casteable a NUMERIC),
que siguen rompiendo con error crudo de PostgreSQL en lugar de un JSONB
controlado. En 7C esto se confirmó como comportamiento conocido (L-7C-03 para el
caso análogo de fecha en W1) y no se ejercitó como caso propio sobre W3 (fuera de
alcance del hardening por strings/whitespace).

**Por qué no es urgente:** los workflows reales aplican `nv()` defensivo para
vacíos/undefined, y los consumidores actuales (n8n manual) no generan entradas
mal tipadas. El endurecimiento conviene antes de conectar consumidores reales que
puedan enviar payloads arbitrarios (webhook MP, bot, frontend).

**Origen:** `7B_CIERRE.md` sección 14 (hardening SQL de `registrar_pago`);
reformulado tras 7C.

### 1.7 Residual amplio de permisos de tabla a roles Data API en DEV

**Estado actual (DEV):** ⏳ Pendiente. Hallazgo de Etapa 7E (snapshot A5), no
tratado por decisión de alcance.

**Contexto:** durante el snapshot read-only de 7E (Bloque A, query A5) se detectó
que en DEV los roles `anon`/`authenticated`/`service_role` tienen sobre **todas
las tablas y vistas** el set **completo** de privilegios
(`SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN`) y
sobre las secuencias `SELECT, UPDATE, USAGE`. El conteo de referencia (C5) fue
**480** grants de tabla a roles Data API. Esto es mucho más amplio que el `Dxtm`
residual de TEST (solo `TRUNCATE/REFERENCES/TRIGGER`, sin SELECT ni escritura —
ver D-7B-03). Es el default histórico de Supabase para proyectos creados antes
del cambio del 30/05/2026, no un bug introducido.

**Por qué 7E no lo tocó:** 7E se ejecutó en alcance estricto (Opción 1 — solo
`REVOKE EXECUTE` sobre funciones, que era el pendiente explícito 1.5). Revocar
los permisos de tabla habría excedido el alcance acordado, por lo que se decidió
documentarlo aquí y no tocarlo. Ver D-7E-01 y `7E_CIERRE.md` sección 8.

**Por qué no es urgencia:** no hay consumidores Data API/PostgREST activos en DEV
(sin frontend público, bot real, MercadoPago real, dashboard externo); n8n entra
como `postgres` owner por pooler y no usa estos grants; RLS sigue postergado
hasta tener frontend público.

**A decidir en etapa futura separada:** o se revoca el set de escritura/lectura
sobre tablas/vistas y los grants de secuencias a los roles Data API para alinear
DEV con el modelo mínimo de TEST, o se acepta y documenta como definitivo. En
cualquier caso, conviene resolverlo **antes de cualquier integración que exponga
Data API en DEV** y **antes del diseño de OPS/PROD** (para no propagar la
asimetría).

**Origen:** hallazgo A5 del snapshot de Etapa 7E; `7E_CIERRE.md` sección 8.

> **Actualización (Etapa 8A, 2026-05-29):** OPS **nació sin este problema**. Al
> crear `vita-delta-ops` con el switch "Automatically expose new tables = OFF"
> desde el día cero, el diagnóstico del Bloque 6 confirmó **0 grants
> SELECT/INSERT/UPDATE/DELETE a roles Data API sobre tablas** (solo el `Dxtm`
> inocuo, igual que TEST). Es decir, la asimetría A5 quedó **acotada a DEV** y no
> se propagó a OPS. La regla derivada para PROD (ver `8A_CIERRE.md` y
> `DECISIONES_NO_REABRIR.md` sección 8A) es crear el proyecto con los mismos
> switches que OPS para nacer cerrado. El item 1.7 sigue abierto **solo para DEV**:
> decidir si se revoca el residual amplio de DEV o se acepta como definitivo. No
> urgente (sin consumidores Data API activos en DEV).
>
> **Actualización (Reconstrucción DEV, 2026-06-15):** el DEV nuevo (`wsrdzjmvnzxidjlovlja`) se creó **cerrado** (expose new tables OFF) y **no hereda el residual amplio A5** — solo el `Dxtm` inocuo, igual que OPS/TEST (verificado en el barrido global de permisos). El item 1.7 queda **resuelto por construcción** para el DEV nuevo; persiste solo como histórico del **DEV viejo congelado**.

### 2.1 Schedule pg_cron — expirar_prereservas_vencidas

**Estado actual (DEV):** ✅ Cerrado / activo. El job `expirar_prereservas`
está programado en pg_cron con schedule `*/5 * * * *` y validado end-to-end
(verificado 2026-05-27: 12 ejecuciones consecutivas con status `succeeded`
en una hora, una pre-reserva real procesada durante 6C).

**Pendiente pre-producción:** replicar y verificar el schedule cuando se
cree el ambiente PROD. _(TEST y OPS ya tienen los 2 jobs activos: TEST verificado
en 7B; OPS verificado en 8A Bloque 8 con una corrida real `succeeded`.)_

**Query a aplicar en TEST/PROD:**

```sql
SELECT cron.schedule(
  'expirar_prereservas',
  '*/5 * * * *',  -- cada 5 minutos
  'SELECT expirar_prereservas_vencidas()'
);
```

**Verificación post-schedule en TEST/PROD:**

```sql
SELECT * FROM cron.job WHERE jobname = 'expirar_prereservas';
```

**Cambio futuro de frecuencia (si fuera necesario):**

```sql
SELECT cron.unschedule('expirar_prereservas');
SELECT cron.schedule('expirar_prereservas', '*/10 * * * *',
                     'SELECT expirar_prereservas_vencidas()');
```

**Nota adicional:** en DEV también está activo el job `cleanup_cron_history`
(día 1 de cada mes a las 03:00 UTC) para purgar registros viejos de
`cron.job_run_details`. Replicar también en TEST/PROD.

**Origen:** decisión del Bloque 18, Fase 2. Ejecutado en Bloque 22 (Fase 3).

---

## 3. Notificaciones operativas (n8n)

### 3.1 Notificación a Jennifer cuando pre-reserva se convierte a reserva dentro del horizonte de limpieza — ✅ RESUELTO (8C-bis, 2026-06-04)

**Contexto:** `vista_limpieza_semana` muestra check-ins y check-outs de los
próximos 7 días. `vista_calendario_semanal` muestra estado día por día.
Ambas SOLO consideran reservas confirmadas y bloqueos (decisión de diseño:
no incluir pre-reservas que son "posibilidades", no certezas).

**Problema operativo:** si Jennifer mira la vista el lunes y planifica la
semana, una pre-reserva que se confirme el miércoles para el viernes
NO aparecerá en lo que ya consultó.

**Mitigación propuesta vía n8n:**

Workflow disparado cuando se crea una reserva (vía evento de
`confirmar_reserva`):
SI fecha_checkin de la nueva reserva está dentro de los próximos 7 días
ENTONCES enviar notificación a Jennifer (WhatsApp/Email) con:

Cabaña, fecha, hora checkin
Datos del huésped (nombre, teléfono, personas, mascotas)
Tipo: "Reserva nueva confirmada dentro de tu semana"


**Origen:** discusión del Bloque 20, Fase 3 (decisión de diseño confirmada
por Franco — Jennifer necesita updates cuando la semana cambia).

**Actualización (8C, 2026-06-01):** este pendiente quedó formalizado en el diseño de 8C como **Bloque 4 opcional / 8C-bis — Alerta por reserva próxima** (D-8C-21), explícitamente fuera del alcance del cierre de 8C (`8C_CIERRE.md`) y como trabajo posterior independiente con documento propio. Definiciones acordadas en 8C: dispara post-`confirmar_reserva` OK si `fecha_checkin ∈ [hoy, hoy+7]`; destinatarios equipo operativo y Jennifer; **no toca schema**. Canal a decidir entre **mail** (con regla de notificación en el celular de cada uno) o **Telegram** (push vía bot, nodo nativo de n8n) — NO requiere esperar la decisión de WhatsApp, que es comunicación externa con huéspedes (no la alerta interna). Engancha en el punto de extensión de 8B, junto con el disparo automático del Sheet de resguardo de 8C (Forma A: 8B invoca el workflow). Nota: los calendarios HTML de 8C (operativo y limpieza) **no** dependen de esta alerta ni de ningún disparo — son ventanas en vivo que se arman al abrir la URL y siempre muestran el estado actual; la alerta es una mejora de robustez (que algo avise sin tener que mirar), no un requisito de los calendarios.

**Resolución (8C-bis, 2026-06-04) — ✅ CERRADO.** Construido como sub-workflow
`vita_w8cbis_alerta__OPS` (id `fHzMFj7pGMKuYEOb`) e invocado **en rama lateral** desde el
formulario de carga 8B. Decisiones finales respecto de lo previsto en 8C:
- **Canal = mail** (D-8Cbis-01), no Telegram ni WhatsApp.
- **Contenido reducido por privacidad** (D-8Cbis-05): el mail NO incluye datos del huésped,
  teléfono, montos ni notas (a diferencia de lo bosquejado arriba en "Mitigación
  propuesta"). Solo informa cabaña, entrada y salida, y enlaza al calendario
  correspondiente (operativo o de limpieza), que ya tiene su propio control de acceso. El
  detalle sensible se ve abriendo el calendario, no en el correo.
- **Destinatarios:** operativo = Franco + Rodrigo; limpieza = Jennifer
  (`yeniferminafo@gmail.com`).
- **Rama lateral** (D-8Cbis-02): si el envío falla, la reserva confirmada no se afecta —
  garantía validada end-to-end en TEST.
- **Fuente de datos:** una query read-only por `id_reserva` a `reservas` + `cabanas`
  (D-8Cbis-04); `confirmar_reserva` solo devuelve ids, por eso se consulta aparte.
- **Estado:** validado en TEST con envío real; publicado y activo en OPS. La primera
  ejecución real quedará registrada con la próxima reserva en ventana.
Ver `8C-bis_CIERRE.md` y decisiones D-8Cbis-01 a D-8Cbis-10.

**Actualización (2026-06-26) — el aviso ahora cubre también el alta por el portal (A07).** Hasta ahora el aviso 8C-bis se disparaba **solo desde el form de 8B**; el wrapper A07 del portal no lo invocaba. Se enganchó al A07 una **rama lateral no bloqueante** (espejo del patrón de 8B) que llama al mismo sub-workflow `vita_w8cbis_alerta`, **sin lógica nueva de mail**, validado end-to-end en TEST (5 gates verdes, incluido el de no-afectación). Así, cuando el equipo cree reservas por el portal en OPS, también saldrá el aviso. **No promovido a OPS** (viaja en la promoción coordinada del Carril C: el `Call` apuntará al 8C-bis OPS con `entorno` resuelto a `'ops'`). Decisiones **D-C-71…73**, lecciones **L-C-24/25**. Ver `AVISO_8CBIS_PORTAL_A07_CIERRE.md`.

### 3.2 Endpoint obligatorio antes de web pública — `consultar_disponibilidad_precio`

**Estado actual:** no implementado en DEV.

**Motivo:** antes de exponer una web pública, el cliente debe poder elegir cabaña, fechas y cantidad de personas, y recibir disponibilidad + precio sin crear una pre-reserva todavía.

**Cambio antes de producción web:**

Crear un endpoint backend —inicialmente en n8n o Supabase Edge Function— que:

- recibe `id_cabana`, `fecha_in`, `fecha_out`, `personas`;
- valida disponibilidad;
- calcula `monto_total` y `monto_sena`;
- devuelve desglose de precio;
- NO crea pre-reserva;
- NO permite que el frontend sea fuente de verdad del precio.

**Regla:** la web puede mostrar el precio, pero nunca calcularlo como autoridad final.

**Origen:** decisión D40 del schema 6B.

---

## 4. Configuración futura del seed productivo

### 4.1 Cabañas reales

**Estado actual:** ✅ Cerrado en DEV, TEST y OPS. Las 5 cabañas reales de
Vita Delta están cargadas en los tres entornos, con IDs propios de cada uno:
- **DEV (IDs 17-21):** Bamboo=17, Madre Selva=18, Arrebol=19, Guatemala=20, Tokio=21.
- **TEST (IDs 1-5):** Bamboo=1, Madre Selva=2, Arrebol=3, Guatemala=4, Tokio=5.
- **OPS (IDs 1-5):** Bamboo=1, Madre Selva=2, Arrebol=3, Guatemala=4, Tokio=5 (sembradas en Etapa 8A, Bloque 5).

Capacidades en los tres: grandes (Bamboo, Madre Selva, Arrebol) 3-5; chicas (Guatemala, Tokio) 2-4.

**Aprendizaje consolidado (D-7B-02):** los IDs **no son portables** entre
entornos. Cada workflow usa los IDs reales del ambiente al que apunta. En el form
de carga de 8B la cabaña se elige **por nombre**, no por ID (D-8-10), lo que hace
irrelevante el valor concreto del ID para el operador.

**Pendiente pre-producción:** replicar el mismo seed en PROD cuando se cree ese
ambiente, con IDs propios (no asumir secuencia desde 1 ni copiar de otro entorno).

### 4.2 Tarifas reales por temporada

Pendiente acordar con Franco y socios:
- Tarifas base por tipo (grande / chica)
- Tarifas por temporada (alta / media / baja)
- Tarifas por evento especial (años nuevo, semana santa, etc.)

**Estado actual:** DEV tiene solo una temporada baseline con multiplicador
neutro (no productiva).

### 4.3 Configuración productiva en `configuracion_general`

Valores sugeridos para producción (ajustar según decisión operativa):
- `hora_checkin_default`: 13:00
- `hora_checkin_domingo`: 18:00
- `hora_checkin_max_cliente`: 22:00
- `hora_checkout_min_cliente`: 07:00
- `hora_checkout_default`: 10:00
- `hora_checkout_domingo`: 16:00 (ver 4.4)
- `prereserva_expiracion_minutos`: 60 (revisable según patrones reales)
- `horizonte_disponibilidad_dias`: 120 (ver punto 1.1)

### 4.4 Agregar clave `hora_checkout_domingo` al seed productivo

**Estado actual (DEV):** ✅ Parcialmente cerrado. Clave cargada en DEV vía
hotfix v1.7 con valor `16:00`. Función `crear_prereserva` v1.7 ya la usa.

**Pendiente pre-producción:** agregar al seed productivo cuando se cree
PROD. Snippet:

```sql
INSERT INTO configuracion_general (clave, valor, descripcion, categoria) VALUES
  ('hora_checkout_domingo', '16:00',
   'Check-out cuando domingo es último día (vs default 10:00)', 'horarios');
```

**Razón operativa:** los clientes que se van un domingo se quedan hasta las
16:00 (última lancha colectiva). Sin esta clave, `crear_prereserva` usaría el
default hardcoded 16:00 (vía COALESCE) y funcionaría igual, pero queda registro
explícito en `configuracion_general`.

**Función dependiente:** `crear_prereserva` v1.7 lee esta clave en sección 2.
Si la clave no existe, se genera un warning en `log_cambios` pero la función
no falla.

**Origen:** Hotfix v1.7 (Fase 3, post-cierre).

### 4.5 Completar seed productivo no técnico

Antes de producción, completar y verificar datos reales de:

- `socios`: nombres reales y porcentajes definitivos.
- `cuentas_cobro`: alias, medio, titular, detalle y estado activo/inactivo.
- `temporadas`: alta, media, baja, fechas y multiplicadores.
- `feriados`: feriados nacionales/provinciales/locales relevantes.
- `eventos_especiales`: Año Nuevo, Semana Santa u otros eventos con reglas propias.
- `plantillas_mensajes`: textos reales para huéspedes/equipo.

**Regla:** no subir datos sensibles reales a GitHub. El documento puede decir qué cargar, pero no debe contener CBU, alias reales sensibles, wallets, teléfonos privados ni credenciales.

**Origen:** preparación de seed productivo posterior a Fase 3.

---

## 5. Seguridad

### 5.1 Row Level Security (RLS)

**Estado actual (DEV):** todas las tablas creadas con "Run without RLS".
Razón: n8n usa `service_role_key` que bypassea RLS de todas formas.

**Cambio para producción:**

Cuando se sume frontend público (web pública con login de huéspedes), se
deberán definir policies RLS sobre:

- `huespedes`: usuarios solo ven su propio registro.
- `pre_reservas`: usuarios solo ven las suyas.
- `reservas`: usuarios solo ven las suyas + staff ve todas.
- `pagos`: usuarios solo ven los suyos + staff ve todos.

**Decisión registrada en bitácora:** "RLS implementación pospuesta hasta
que haya frontend público. n8n con service_role_key no la necesita."

---

## 6. Validaciones empíricas pendientes

### 6.1 Tests de concurrencia — H7 de Etapa 6D ✅ CERRADO

**Estado:** ✅ Cerrado en bloque H7 de Etapa 6D (sesión 2026-05-27).
**Resultado:** 6 tests de concurrencia real en DEV aprobados (C-1, C-2, C-5, C-3, C-4, C-6). Sin deadlocks, sin races, sin doble booking, sin falsos positivos. Cero side effects persistentes post-cleanup.

**Detalle histórico completo:** ver Apéndice A.5 al final de este documento.

**Bitácora detallada:** `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` sección H7.

### 6.2 Tests de carga real (post-tests-de-concurrencia)

Pendiente histórico. Validar comportamiento del sistema bajo carga real:

- 2 clientes intentando reservar la misma cabaña simultáneamente.
- Webhook MP llegando mientras Vicky confirma manualmente.
- Cron de expiración corriendo mientras hay pago en proceso.

Estos no reemplazan H7. H7 validó concurrencia controlada con SQL y locks; 6.2 queda como validación posterior de carga/uso real cuando existan consumidores reales conectados.

**Origen:** plan de Fase 4 según `6B_PLAN_FASES.md`.

### 6.3 Cobertura empírica de ramas `pre_lock` y `unique_violation` de idempotencia

**Estado:** ⏳ Pendiente opcional, no bloqueante. **`pre_lock` cubierto en 7C; resta solo `unique_violation`.**

**Contexto:** C-6 de H7 observó empíricamente la rama `post_lock` del detector de idempotencia de `crear_prereserva`. La rama `pre_lock` quedó **cubierta empíricamente en Etapa 7C** (caso A-W2-15): re-ejecución secuencial de W2 con la misma `idempotency_key` que la fixture ya existente devolvió `idempotent_match:true, recovery_path:'pre_lock'`, con el estado actual de la pre-reserva, sin crear duplicado. Resta solo `unique_violation`.

**Para gatillar `unique_violation`:** escenario más difícil de reproducir manualmente — requeriría que B pase el pre-check y el double-check post-lock pero choque con la constraint unique en el INSERT. Solo gatillable si ambas transacciones se cruzan dentro de una ventana muy estrecha entre el double-check y el INSERT.

**Decisión:** `unique_violation` queda como cobertura opcional pre-PROD si se considera necesario. No bloqueante para avanzar a TEST o a integraciones reales. No se intentó en 7C por requerir concurrencia pesada, que está fuera del alcance de esa etapa (H7 ya cubrió la concurrencia crítica).

**Origen:** observación empírica en C-6 de H7; `pre_lock` cerrado en A-W2-15 de 7C (`7C_CIERRE.md` sección 4).

### 6.4 Validación funcional ampliada sobre TEST (casos de error)

> **✅ CERRADO en Etapa 7C (2026-05-28).** La batería de caminos no-felices de
> los 8 workflows `__TEST` se ejecutó sistemáticamente sobre TEST: **48 casos
> funcionales (Grupo A) + 6 verificaciones transversales (TR-01/TR-02) = 54
> verificaciones conformes, 0 fallos inesperados, 1 mutación no planificada pero
> válida y comprendida (bloqueo id 2).** Idempotencia: rama `pre_lock` cubierta
> (resta `unique_violation`, ver 6.3). Ver `7C_CIERRE.md`. El contenido original
> se conserva abajo como referencia histórica del alcance planificado.

**Estado original (pre-7C):** ⏳ Pendiente. No diseñado todavía.

**Contexto:** Etapa 7B cerró con happy paths como evidencia suficiente para
validar el levantamiento del entorno TEST. Los casos de error de los 8
workflows no fueron ejercitados sobre TEST.

**Por qué no es bloqueante para avanzar:** la validez estructural y los happy
paths están confirmados (paridad 10/10 vs DEV; cadena W2→W3→W4 end-to-end OK).
Los casos de error están cubiertos a nivel SQL por las decisiones D-HARD-01 a
D-HARD-06 (patrón canónico de validación) y por los tests de hardening 6D
ejecutados en DEV. Ejercitarlos en TEST es validación de regresión sobre el
ambiente nuevo, no validación de un riesgo abierto.

**Alcance esperado:** ejecutar sobre TEST la batería de casos de error que
cubren los caminos no-felices de las funciones write y read-only. TEST es el
ambiente seguro para esto: aislado de DEV, sin consumidores reales, con la
cadena W2→W3→W4 y el bloqueo W6 ya validados como base.

**Casos a ejercitar (lista completa en `7B_CIERRE.md` sección 14):**

- cabaña inexistente (W1, W2, W6);
- solapamientos (reserva sobre bloqueo, bloqueo sobre reserva, pre-reserva
  sobre pre-reserva activa);
- doble pre-reserva con misma `idempotency_key` (idempotencia bajo colisión —
  ramas `pre_lock`/`post_lock`/`unique_violation` de `crear_prereserva`);
- re-confirmación de reserva ya convertida (W4 → `estado_invalido`);
- cancelación de estados no cancelables (W5 sobre pre-reserva ya terminal);
- payloads inválidos (campos obligatorios faltantes);
- campos vacíos / whitespace puro en obligatorios (validación del hardening
  D-HARD-01 y D-HARD-02);
- motivos inválidos (W5 con motivo fuera del enum; W6 con motivo fuera del
  enum);
- normalización defensiva (W3/W4/W5/W6) — verificar comportamiento con
  `""`/`"   "` en campos obligatorios de texto;
- pagos tardíos o inconsistentes (caso v1.3 de `registrar_pago`:
  `prereserva_no_activa` con `warning`).

**Datos de prueba en TEST como base:** la pre-reserva 2 ya convertida, la
reserva 1, el pago 1 y el bloqueo 1 conservados desde 7B sirven como fixtures
para algunos de estos casos (re-confirmación, re-cancelación, solapamiento con
bloqueo activo).

**Origen:** `7B_CIERRE.md` sección 14; cierre de 7B con scope acotado a happy
paths.

### 6.5 Diseño del bloque de limpieza/reset de TEST

**Estado:** ✅ Cerrado en Etapa 7D (2026-05-28). Ver `7D_CIERRE.md`.

**Contexto:** las Etapas 7B y 7C dejaron datos vivos en TEST que se conservaron
como evidencia (decisión D-7C-01, no-limpieza). 7D diseñó y ejecutó el bloque
dedicado de reset con SQL explícito y aprobado.

**Qué se ejecutó:**

1. Snapshot read-only pre-reset (Bloque A), con preflight anti-error-de-entorno
   por identidad exacta de las 5 cabañas TEST.
2. Limpieza transaccional atómica (Bloque B): `DELETE` explícito en orden seguro
   por FKs (`pagos` → `reservas` → `pre_reservas` → `bloqueos` → `huespedes` →
   `log_cambios`), sin `DROP/TRUNCATE ... CASCADE`, con re-gate dentro de la
   transacción.
3. Reset de secuencias a 1 (`ALTER SEQUENCE ... RESTART WITH 1`) solo en las 6
   tablas vaciadas con datos (D-7D-01).
4. Vaciado de `log_cambios` con evidencia documentada en el cierre (D-7D-02).
5. Verificación posterior (Bloque C): transaccionales en 0, seed intacto,
   secuencias reseteadas, cron intacto, vistas operativas ejecutando.

**Resultado:** TEST quedó como entorno limpio (schema v1.7.3 + seed estructural +
cron + grants + funciones/vistas/triggers + workflows `__TEST`, sin datos
transaccionales). Las 3 condicionales (`consultas`, `overrides_operativos`,
`gastos`) estaban en 0 y no entraron al borrado.

**Decisiones generadas:** D-7D-01 (reset de secuencias), D-7D-02 (vaciado de
`log_cambios` con evidencia documentada) — ver `DECISIONES_NO_REABRIR.md`.

**Verificación n8n (cerrada):** confirmado que los 8 workflows `__TEST` siguen
con la credencial `vita_supabase_test` apuntando a TEST (Franco, 2026-05-28).

**Origen:** D-7C-01 (`DECISIONES_NO_REABRIR.md`); `7C_CIERRE.md` secciones 8 y 9.
**Cierre:** `7D_CIERRE.md`.

---

## 7. Backup y rollback

### 7.1 Backup antes de aplicar schema en producción

Antes de ejecutar cualquier bloque o migración en PROD:

- exportar backup desde Supabase;
- guardar dump SQL o snapshot disponible;
- verificar que se puede restaurar o recrear el entorno;
- registrar commit exacto del repo usado para deploy.

### 7.2 Plan de rollback

Para cada ejecución productiva:

- definir hasta qué punto se puede revertir;
- no usar `DROP ... CASCADE` sin revisión explícita;
- documentar qué datos podrían perderse;
- si ya hay reservas reales cargadas, priorizar migraciones reversibles o scripts correctivos.

**Origen:** control mínimo de riesgo antes de producción.

---

## 8. Secrets y credenciales

### 8.1 Variables de entorno productivas

Antes de producción, verificar que las credenciales reales estén fuera de GitHub:

- Supabase Project URL.
- Supabase anon key, si aplica.
- Supabase service role key para n8n.
- Credenciales n8n.
- MercadoPago access token / webhook secret.
- WhatsApp / Meta tokens.
- Credenciales de email, si aplica.

**Regla:** ningún secret real debe commitearse. Usar `.env`, gestor de secretos o variables del entorno de n8n.

### 8.2 Archivo `.env.example`

Mantener solo placeholders:

```text
SUPABASE_URL=__SUPABASE_URL__
SUPABASE_SERVICE_ROLE_KEY=__SUPABASE_SERVICE_ROLE_KEY__
MERCADOPAGO_ACCESS_TOKEN=__MERCADOPAGO_ACCESS_TOKEN__
```

---

## Cómo usar este archivo

- **Cuando se identifica un nuevo pendiente:** agregar acá con título,
  estado actual, cambio para producción, y origen.
- **Cuando se completa un pendiente:** marcar como cerrado y, si genera
  contexto histórico relevante, mover a `Apéndice histórico` al final.
- **En la revisión pre-deploy:** verificar que TODOS los items se hayan
  resuelto o tengan decisión explícita de postergación.

---

# Apéndice histórico — items cerrados en Etapa 6D

Esta sección preserva el contexto técnico de los items resueltos durante
Etapa 6D (Hardening pre-producción). Las secciones que siguen describen
cómo fueron descubiertos los problemas y qué se decidió en cada caso.
**Para detalle de ejecución, ver `HARDENING_PRE_PRODUCCION_EJECUCION.md`.**

---

## A.1 [CERRADO en H2-H4-ter] Hardening de validación en funciones SQL write

**Descubierto durante:** 6C — implementación de W3 (registrar_pago).
**Fecha de descubrimiento:** 2026-05-25.
**Estado:** ✅ Cerrado en bloques H2, H3, H4, H4-bis, H4-ter de Etapa 6D
(sesión 2026-05-26).
**Bitácora detallada:** `Docs/Bitacora/6C_EJECUCION.md` — entrada W3,
sección "Hallazgo importante". Ejecución del fix en
`Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### Problema original (pre-hardening)

Las funciones de escritura del schema no eran uniformes en cómo manejaban
strings vacíos en campos obligatorios. Específicamente, `registrar_pago()`
extraía los campos obligatorios `tipo` y `medio_pago` así:

```sql
v_tipo := payload->>'tipo';
v_medio_pago := payload->>'medio_pago';
```

Sin `NULLIF` y sin `TRIM`. Si el payload traía estos campos como `""`
(string vacío), la validación posterior:

```sql
IF v_tipo IS NULL OR v_medio_pago IS NULL OR ... THEN
  RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
END IF;
```

No los detectaba como faltantes, porque `""` no es `NULL`. La función
avanzaba hasta el INSERT y chocaba contra los CHECK constraints
(`chk_pagos_tipo`, `chk_pagos_medio`), generando un error crudo de Postgres
en vez de un JSONB estructurado.

### Mitigación temporal aplicada en 6C

En W3 — Build Payload, n8n normalizaba con `nv()` los campos obligatorios
antes de mandarlos al payload (convertía `""` a `null` explícito). Esto
hacía que `payload->>'campo'` devolviera NULL real y la validación de la
función rebotara limpio.

**Limitación de la mitigación:** solo cubría el camino de W3. Si otro
consumidor de la función (otro workflow, llamada directa SQL, bot, etc.)
mandaba payload con string vacío, el agujero seguía.

### Fix definitivo aplicado en Etapa 6D

Patrón canónico unificado aplicado al extract de payload de las 5
funciones write críticas:

```sql
v_campo := NULLIF(TRIM(payload->>'campo'), '')::TIPO;
```

Cubre vacíos y whitespace antes del cast. Aplicado a las asignaciones de extract en las funciones:
- `registrar_pago` (H2)
- `confirmar_reserva` (H3)
- `crear_prereserva` (H4)
- `cancelar_prereserva` (H4-bis)
- `crear_bloqueo` (H4-ter)

`upsert_huesped` ya cumplía el patrón desde antes.

**101 tests de hardening** sobre las 5 funciones, todos con `ok=true`. Cero
side effects: conteos de DEV idénticos pre y post hardening.

**Mitigación defensiva `nv()` en n8n:** se mantiene como defensa en
profundidad. No se removió.

---

## A.2 [CERRADO en H5] Vista_ocupacion devuelve 25 meses en vez de 24

**Descubierto durante:** 6C — implementación de W7 (vistas operativas),
Test 4.
**Fecha de descubrimiento:** 2026-05-26.
**Estado:** ✅ Cerrado en bloque H5 de Etapa 6D (sesión 2026-05-26).
**Bitácora detallada:** `Docs/Bitacora/6C_EJECUCION.md` — entrada W7,
sección "Test 4". Ejecución del fix en
`Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### Problema original (pre-hardening)

`vista_ocupacion` estaba definida con:

```sql
generate_series(
  date_trunc('month', CURRENT_DATE) - '1 year'::interval,
  date_trunc('month', CURRENT_DATE) + '1 year'::interval,
  '1 mon'
)
```

`generate_series` con paso temporal incluye ambos extremos, generando 25
puntos en vez de 24. Esto resultaba en 25 meses × 5 cabañas = 125 filas en
el output, en vez del valor teóricamente esperado de 120.

**Impacto:**
- Funcional: ninguno. Los cálculos de `noches_ocupadas` para cada mes
  seguían siendo correctos.
- Operativo: una fila más por cabaña por consulta. En reportes que
  consumían la vista, podía causar confusión si alguien esperaba
  "exactamente 24 meses" para gráficos.

### Fix aplicado en Etapa 6D

Una sola línea modificada — al límite superior del `generate_series` se le
resta `'1 mon'::interval`:

```sql
generate_series(
  date_trunc('month', CURRENT_DATE) - '1 year'::interval,
  date_trunc('month', CURRENT_DATE) + '1 year'::interval - '1 mon'::interval,
  '1 mon'
)
```

Resultado: 120 filas (24 meses × 5 cabañas). 7 tests con `ok=true`.
Cálculos de `noches_ocupadas` idénticos a los previos.

---

## A.3 [CERRADO en H6, H6-bis] Espacio colgando en concatenación nombre + apellido

**Descubierto durante:** 6C — implementación de W7 (vistas operativas),
Test 3.
**Fecha de descubrimiento:** 2026-05-26.
**Estado:** ✅ Cerrado en bloques H6 y H6-bis de Etapa 6D (sesión 2026-05-26).
**Bitácora detallada:** `Docs/Bitacora/6C_EJECUCION.md` — entrada W7,
sección "Test 3". Ejecución del fix en
`Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### Problema original (pre-hardening)

Las vistas `vista_calendario`, `vista_limpieza_semana` y
`vista_prereservas_activas` concatenaban el nombre del huésped así:

```sql
nombre || ' ' || COALESCE(apellido, '')
```

Cuando `apellido` era string vacío `""` (no NULL), `COALESCE(apellido, '')`
devolvía `""` sin reemplazar. La concatenación quedaba como
`"Juan Pérez Test "` con espacio al final.

**Impacto:**
- Funcional: ninguno.
- UX/Cosmético: strings con espacios colgando se veían mal en UI / mensajes
  a clientes. Si una plantilla hacía `"Hola {huesped_nombre},"` quedaba
  `"Hola Juan Pérez Test ,"` con espacio antes de la coma.

### Fix aplicado en Etapa 6D

Reemplazo en las 3 vistas afectadas:

```sql
TRIM(nombre || ' ' || COALESCE(apellido, ''))
```

Aplicado a `vista_calendario`, `vista_limpieza_semana` (2 ocurrencias por
UNION ALL), y `vista_prereservas_activas` (1 ocurrencia).

PostgreSQL al persistir normalizó `TRIM(...)` a `TRIM(BOTH FROM ...)`.
Sintaxis equivalente.

H6: 7 tests con `ok=true`. H6-bis: 5 tests con `ok=true`. Categoría
cosmética cerrada.

**Parte 6.2 (UPDATE de huéspedes):** NO ejecutado. DEV ya tiene
`apellido = NULL` en los 2 huéspedes existentes (limpieza pre-hardening
eliminó los problemáticos). `upsert_huesped` aplica `NULLIF(TRIM(...))` para
casos futuros.

---

## A.4 [CONSOLIDADO en A.5] Tests de concurrencia Sección 6.8

**Descubierto durante:** preparación del cierre formal post-6C.
**Fecha de registro:** 2026-05-26.
**Estado:** ✅ Cerrado en H7. Detalle consolidado en **Apéndice A.5**.

Este item originalmente migró desde la Sección 10 del archivo a la
Sección 6.1 para evitar duplicación. La ejecución se hizo en H7 (sesión
2026-05-27) con scope ampliado: además de los 4 tests originales del
plan 6B (C-1 a C-4), se agregaron dos legacy complementarios (C-5
regresión v1.5 y C-6 idempotencia). El detalle completo de los 6 tests
ejecutados está en A.5.

---

## A.5 [CERRADO en H7] Tests de concurrencia C-1 a C-6

**Descubierto durante:** plan original 6B Sección 6.8 + consolidación
post-6C en Sección 6.1 + ajuste de nomenclatura al inicio de H7.
**Fecha de ejecución:** 2026-05-27.
**Estado:** ✅ Cerrado en bloque H7 de Etapa 6D.
**Bitácora detallada:** `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`
sección H7.

### Contexto

Los tests de concurrencia con `pg_sleep` se difirieron durante 6B (foco en
"función compila y se comporta") y durante 6C (n8n manual no permite
reproducir la condición de carrera con sleep). Operativamente no eran
bloqueantes hasta tener consumidores reales que generaran concurrencia
(webhook MP, bot multicanal, frontend público), pero el riesgo de que el
primer evento de concurrencia real en producción fuera también el primer
test del sistema motivó ejecutarlos en DEV controlado antes de TEST/PROD.

### Alcance ejecutado

6 tests con paralelismo real en DEV usando dos tabs separadas del
navegador (no la opción "+" interna del SQL Editor que comparte runner):

| Test | Funciones | Cabaña | Rango | Tipo |
|---|---|---|---|---|
| C-1 | `crear_prereserva` + `crear_bloqueo total` | 17 | 2027-03 | Consolidado |
| C-2 | `cancelar_prereserva` + `crear_bloqueo total` | 18 | 2027-04 | Consolidado |
| C-5 | `confirmar_reserva` + `cancelar_prereserva` | 19 | 2027-05 | Legacy v1.5 (regresión deadlock) |
| C-3 | `confirmar_reserva` + `crear_bloqueo específico` | 20 | 2027-06 | Consolidado |
| C-4 | Doble `confirmar_reserva` | 21 | 2027-07 | Consolidado |
| C-6 | Doble `crear_prereserva` + `idempotency_key` | 17 | 2027-08 | Legacy idempotencia |

### Resultado

| Métrica | Valor |
|---|---|
| Tests aprobados | 6 de 6 |
| Deadlocks `40P01` | 0 |
| Races / doble booking / falsos positivos | 0 |
| Rango de `B.elapsed` | 6.058s a 6.539s (lock global serializa consistentemente) |
| Residuos `test_H7_%` en DEV post-cleanup | 0 |
| Schema | Sin cambios (H7 es validación, no modifica SQL) |

### Confirmaciones estructurales

1. **Invariante de locks v1.5 vigente en DEV.** El orden "lock global SIEMPRE primero antes de cualquier FOR UPDATE / lock por cabaña" funciona correctamente bajo concurrencia real.
2. **Lock global serializa.** `B.elapsed` consistente entre 6.06s y 6.54s, con `B.ts_post ≈ A.ts_post`.
3. **EXCLUDE constraints no fueron necesarios.** Los chequeos aplicativos rebotaron antes del INSERT en todos los casos.
4. **Visibilidad post-COMMIT consistente.** B siempre vio los cambios de A después del COMMIT.
5. **Idempotencia de `crear_prereserva` funcional.** Rama `post_lock` observada empíricamente en C-6.
6. **Doble logging confirmado en las transiciones de estado observadas durante H7** (trigger automático `trg_log_*_estado` + log explícito de la función cuando aplica).

### Lecciones operativas surgidas en H7

1. SQL Editor "+" interno comparte runner; dos tabs separadas del navegador permiten paralelismo real.
2. Mini-test de PIDs con `pg_sleep(5)` valida paralelismo antes de tests críticos.
3. CTEs encadenadas (`MATERIALIZED` + `FROM`) necesarias para tests con `pg_sleep` en transacción.
4. `registrar_pago` requiere `estado_inicial='confirmado'` + `monto_recibido=monto_esperado` para pago `confirmado` directo (default es `en_revision`).
5. Trigger `trg_log_*_estado` sobre `pagos` solo dispara en UPDATE OF estado, no en UPDATE de `id_reserva`.
6. `crear_prereserva` ejecuta `upsert_huesped` antes del lock global; bajo concurrencia con idempotencia, B puede crear huésped huérfano que queda para cleanup.
7. `bloqueos.activo` BOOLEAN (no enum `estado`) — divergencia de patrón con otras tablas operativas.
8. `cabanas.capacidad_max` (no `capacidad_maxima`) — naming real confirmado; revisar documentación si corresponde en H8.
9. `confirmar_reserva` retorna `estado_invalido` cuando estado terminal (no `estado_no_confirmable`).
10. `telefono_normalizado` preserva el `+` del prefijo internacional.

Estas lecciones se consolidan en `Lecciones_Aprendidas.md` durante H8, agrupadas por tema para no crear entradas redundantes.

### Cobertura parcial documentada

H7 observó empíricamente la rama `post_lock` del detector de idempotencia
de `crear_prereserva` (C-6). Las ramas `pre_lock` y `unique_violation`
están vigentes en el cuerpo de la función y son alcanzables por diseño,
pero no fueron gatilladas en H7 por el timing del test. Queda como
cobertura opcional no bloqueante (ver Sección 6.3 arriba).

### Decisiones cerradas durante H7

- Mantener nomenclatura consolidada C-1 a C-4 (de este documento) + agregar
  C-5 y C-6 como complementarios legacy (del plan 6B original), no
  reemplazar.
- Convención `source_event = 'test_H7_C{N}_{ROL}'`.
- Cleanup por test con filtro específico `LIKE 'test_H7_C{N}_%'`, no
  cleanup global al final.
- Mecánica de paralelismo: dos tabs del navegador + CTEs encadenadas
  MATERIALIZED + `clock_timestamp()` + `pg_backend_pid()`.
- Freno duro ante cualquier `40P01` (frenos especiales en C-5 y C-3 no se
  activaron).

Estas decisiones se consolidan en `DECISIONES_NO_REABRIR.md` como D-HARD-07
en adelante durante H8.
