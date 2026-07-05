# Cierre técnico preliminar — Guard de alta segura de overrides horarios

**Bloque:** Motor de Horarios / Guard de alta segura de `overrides_operativos` (R0 · S0 · S1 · S2 · S3).
**Estado:** cerrado **verde en TEST**.
**Ámbito:** **SOLO TEST**. No OPS, no canónico, no gateway/frontend/n8n, sin acuñar `D-*`/`L-*`.
**Naturaleza de este documento:** cierre **preliminar**. No canoniza, no promueve, no genera SQL nuevo. Registra el estado alcanzado y deja el siguiente paso a decisión.

---

## 1. Estado final del bloque

El bloque completo de alta segura de overrides horarios quedó ejecutado y verificado en el entorno TEST (`bdskhhbmcksskkzqkcdp`), en cinco sub-bloques encadenados, todos con compuerta verde y residuales cero:

- **R0** — corrección del resolver: `fecha_hasta NULL` significa **solo `fecha_desde`** (predicado `p_fecha <= COALESCE(fecha_hasta, fecha_desde)`).
- **S0** — validadores de estado (existencia de comprometidos + gap same-day + estado resuelto válido).
- **S1** — barrera DB: constraint trigger diferido sobre `overrides_operativos`.
- **S2** — alta sancionada **simple**: `crear_override_horario(jsonb)` (un override horario).
- **S3** — alta asistida **de paquete**: `crear_paquete_dia_especial(jsonb)` (checkout + checkin juntos, con verificación de efecto pretendido).

Cada sub-bloque se validó en capas (pglast → harness PostgreSQL 16 local → TEST → smokes) y se cerró con hard stop para aprobación antes de avanzar al siguiente.

## 2. Alcance real

- **TEST-only.** Todo se ejecutó contra TEST. Nada tocó OPS (`lpiatqztudxiwdlcoasv`).
- **No canónico.** No se modificó `Docs/Implementacion/6B_SCHEMA_SQL.md` ni ningún satélite (`ESTADO_ACTUAL`, `DECISIONES_NO_REABRIR`, `Lecciones_Aprendidas`, `Pendiente_pre_produccion`, `CLAUDE.md`, `README.md`). La versión canónica sigue en **v1.10.1**.
- **No gateway/frontend/n8n.** No se generó ni modificó `portal-api`, ni frontend, ni workflows n8n. Este bloque es exclusivamente de capa de base de datos.
- **Sin `D-*`/`L-*`.** No se acuñaron identificadores de decisión ni de lección; corresponde al cierre formal, no a este preliminar.

## 3. Qué quedó instalado (en TEST)

| Sub-bloque | Objeto(s) en `public` | Rol |
|---|---|---|
| R0 | `resolver_horario(bigint,date)` (redefinida) | Resuelve checkin/checkout ganadores por precedencia; base weekday 13:00/10:00, domingo 18:00/16:00 |
| S0 | `validar_estado_horario_final(bigint,date)`, `validar_no_eventos_comprometidos(bigint,date)`, `validar_estado_override(bigint,date)` | Validadores VOLATILE/INVOKER, lock-free; `validar_estado_override` es el orquestador (única fuente de verdad para S1/S2/S3) |
| S1 | `trg_guard_overrides()` + constraint trigger `trg_ov_guard` (AFTER INSERT/UPDATE/DELETE, DEFERRABLE INITIALLY DEFERRED, FOR EACH ROW) | Barrera DB: revalida el estado en el commit ante cualquier escritura sobre `overrides_operativos` |
| S2 | `crear_override_horario(jsonb)` | Alta sancionada simple (un override horario, por cabaña o global estricto) |
| S3 | `crear_paquete_dia_especial(jsonb)` | Alta asistida de paquete (checkout+checkin), con S0 + verificación de efecto pretendido |

Todas las funciones sancionadas llevan `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated, service_role` (hardening espejo Bloque 23) y `COMMENT` descriptivo.

## 4. Fingerprints relevantes

- **Resolver nuevo** `resolver_horario(bigint,date)`: `58d75c1b6b812ee2d2c9751ddcb0cd4d`.
- **ODR** `obtener_disponibilidad_rango(date,date,bigint)`: `37009a32154f93b80520500c0f15b46b`.

Estos dos fingerprints (md5 de `pg_get_functiondef` sobre TEST PG 17.6) están **consolidados** y se usan como gate anti-OPS en todos los artefactos de S1/S2/S3.

Para las **funciones nuevas del bloque** (validadores S0, `trg_guard_overrides`, `crear_override_horario`, `crear_paquete_dia_especial`) **no hay fingerprint consolidado todavía**: su integridad se verifica por **presencia/firma** (`to_regprocedure('fn(args)')`) y, para el trigger, por existencia en `pg_trigger` (`trg_ov_guard`, no interno). La consolidación de fingerprints de estas funciones sería un artefacto natural del **cierre formal/canonización**, no de este preliminar.

## 5. Garantías funcionales logradas

Verificadas empíricamente por los smokes de cada sub-bloque:

1. **No se pisa reserva/pre-reserva comprometida.** Comprometido = reservas en `{confirmada, activa, completada}`; pre-reserva bloqueante = `(pendiente_pago AND expira_en>NOW())` o `pago_en_revision`. Un override que dejaría un estado sobre fecha comprometida se rechaza (`override_pisa_reserva` / `override_pisa_prereserva`).
2. **Gap same-day mínimo 2 h.** El estado resuelto exige `hora_checkin − hora_checkout >= interval '2 hours'` en la misma fecha (`override_incompatible_same_day`). En S3, `gap_minutos` default 120 y `< 120 => payload_invalido` garantiza el mínimo antes de insertar.
3. **`global_estricto` all-or-nothing.** Inserta dos overrides globales reales (`id_cabana NULL`) solo si **todas** las cabañas activas quedan válidas y efectivas; si una falla, no queda ningún global.
4. **`todas_posibles` / `grupo_posibles` excluyen conflictivas.** Subtransacción por cabaña: aplica las libres/efectivas per-cabaña, excluye el resto con reporte, nunca inserta global; si ninguna aplica → `sin_cabanas_aplicables`.
5. **Efecto pretendido verificado (S3).** Además de estado válido (S0), se exige que `resolver_horario` devuelva las horas solicitadas para cada cabaña/fecha aplicada; si un override específico preexistente sombrea al paquete (global pierde contra específico; o específico con `created_at` posterior) → `paquete_no_aplicado_efectivamente`.
6. **`fecha_hasta NULL` = solo `fecha_desde`.** Corrección R0: un override sin `fecha_hasta` afecta únicamente su `fecha_desde`, no el rango abierto.
7. **`created_at` tratado como columna efectiva.** Participa del desempate del resolver (`created_at DESC, id_override DESC`); por eso el guard S1 lo trata como columna efectiva y un UPDATE solo se considera metadata-only si el cambio se limita a `{motivo, creado_por, source_event}`.
8. **DELETE/UPDATE/INSERT cubiertos por la barrera.** El constraint trigger S1 valida el applied_set en las tres operaciones (INSERT→NEW; DELETE→OLD si activo; UPDATE→unión de OLD/NEW activos, salvo skip metadata-only).
9. **S1 revalida el bypass directo.** Un INSERT directo inválido (fuera de las funciones sancionadas) falla al forzar `SET CONSTRAINTS ... IMMEDIATE` — el trigger sigue activo y cierra el bypass.

## 6. Resumen de resultados

| Sub-bloque | Smokes | Residuales |
|---|---|---|
| R0 | **9/9 PASS** | 0 |
| S0 | **13/13 PASS** | 0 |
| S1 | **16/16 PASS** | 0 |
| S2 | **12/12 PASS** | 0 |
| S3 | **22/22 PASS** | 0 |

Todos con compuerta verde y postcheck de residuales en 0 (sin filas nuevas persistidas; toda prueba corre en `BEGIN … ROLLBACK`).

## 7. Contratos principales

### `crear_override_horario(jsonb)` (S2)

Alta simple de **un** override horario (`hora_checkin` **o** `hora_checkout`), por cabaña o global estricto. Toma `pg_advisory_xact_lock(10,0)` primero; valida con S0 en subtransacción; persiste solo si el estado queda válido.
**Errores parseables:** `payload_invalido`, `tipo_override_no_soportado`, `cabana_no_encontrada`, `override_pisa_reserva`, `override_pisa_prereserva`, `override_incompatible_same_day`, `override_hora_invalido`.

### `crear_paquete_dia_especial(jsonb)` (S3)

Alta de **paquete** (`hora_checkout` + `hora_checkin` juntos), con S0 + verificación de efecto pretendido. Alcances: `cabana`, `grupo_estricto`, `grupo_posibles`, `global_estricto`, `todas_posibles`. `gap_minutos` default 120 (`<120 => payload_invalido`); `ids_cabanas` requerido para grupos, array no vacío, enteros existentes y sin duplicados; `source_event` deriva hijos deterministas `<source>:checkout|checkin:<id_cabana|global>`.
**Errores parseables:** `payload_invalido`, `cabana_no_encontrada`, `ids_cabanas_invalidos`, `alcance_no_soportado`, `sin_cabanas_aplicables`, `paquete_no_aplicado_efectivamente`, `override_pisa_reserva`, `override_pisa_prereserva`, `override_incompatible_same_day`, `override_hora_invalido`.

Ambas funciones devuelven siempre un objeto jsonb con `ok:true|false`; los errores son cadenas parseables (no excepciones al llamador) salvo condiciones verdaderamente inesperadas, que propagan.

## 8. Riesgos y residuales conocidos

1. **Sigue TEST-only.** Nada de esto está en OPS. La operación real todavía no usa estas funciones.
2. **Sin integración n8n/gateway/frontend.** No hay wrapper `portal-api`, ni endpoint, ni pantalla. El bloque es puramente de base de datos; falta todo el cableado operativo.
3. **No canonizado.** No está reflejado en `6B_SCHEMA_SQL.md` ni satélites; el canónico sigue en v1.10.1.
4. **No promovido a OPS.** Falta el ciclo de promoción con verificaciones read-only y prueba empírica de cero filas / cero `nextval`.
5. **`session_replication_role = 'replica'` saltea triggers.** Bajo ese modo de sesión, el constraint trigger `trg_ov_guard` (S1) **no dispara** (trigger ENABLE ORIGIN por defecto). Un INSERT/UPDATE/DELETE crudo sobre `overrides_operativos` en modo replica **evadiría la barrera DB**. Las funciones sancionadas S2/S3 igual validan explícitamente con S0, pero una escritura que las saltee bajo modo replica queda fuera del control de S1. Límite conocido, a considerar en el hardening de OPS.
6. **Cambios permanentes de horario base fuera de alcance.** Este bloque cubre **overrides** (excepciones por fecha/rango). Un cambio de horario base "de ahora en más" (que corra el default weekday/domingo) no está contemplado acá.

## 9. Próximos pasos recomendados

1. **Decidir cierre formal / canonización / promoción a OPS** del bloque completo. Al canonizar correspondería: bump de versión canónica, consolidación de fingerprints de las funciones nuevas, y actualización de satélites (`ESTADO_ACTUAL`, `Lecciones_Aprendidas`, `DECISIONES_NO_REABRIR`) con las decisiones y lecciones del bloque.
2. **Eventual S4 separado** para cambio de **horario base** "de ahora en más" (distinto de los overrides por fecha), si el negocio lo requiere. Debería diseñarse como bloque aparte, no reabrir R0–S3.
3. **Cableado operativo** (n8n/gateway/frontend) para exponer `crear_override_horario` y `crear_paquete_dia_especial` a la operación, si corresponde, respetando la división de labor y el ciclo de promoción.
4. **Cierre del hardening de la barrera** ante `session_replication_role='replica'` como parte del pase a OPS (evaluar ENABLE ALWAYS del trigger o control de acceso al modo replica).

## 10. Rollback

**Orden de rollback seguro (si hiciera falta revertir el bloque):** de dependiente a dependencia, para no romper referencias.

```
S3  ->  S2  ->  S1  ->  S0  ->  R0
```

Justificación de la dependencia:
- **S3** usa validadores S0 y `resolver_horario` (R0) → se dropea primero.
- **S2** usa validadores S0 → después de S3.
- **S1** (trigger + `trg_guard_overrides`) usa validadores S0 → después de S2.
- **S0** (los tres validadores) usan `resolver_horario` (R0) → después de S1.
- **R0** es la corrección del resolver; revertirlo restaura la definición previa (reintroduce el comportamiento viejo de `fecha_hasta`), por eso va **último** y es el paso más drástico (el resolver también lo consume ODR y el resto del sistema). Solo revertir R0 si es estrictamente necesario.

**Rollbacks parciales ya generados por sub-bloque** (cada uno con gate `ambiente=test`, drop del objeto propio y verificación de que las dependencias quedan intactas):
- R0: `HORARIOS_R0_RESOLVER_ROLLBACK_TEST.sql`.
- S1: `HORARIOS_GUARD_S1_ROLLBACK_TEST.sql`.
- S2: `HORARIOS_GUARD_S2_ROLLBACK_TEST.sql`.
- S3: `HORARIOS_GUARD_S3_ROLLBACK_TEST.sql` (dropea solo `crear_paquete_dia_especial(jsonb)`; verificado que deja R0/S0/S1/S2 intactos).
- S0: la reversión consiste en dropear los tres validadores (`validar_estado_override`, `validar_estado_horario_final`, `validar_no_eventos_comprometidos`), y solo tiene sentido **después** de haber revertido S1/S2/S3 (que los consumen); no se cortó script dedicado en este set.

Nota: los rollbacks son **TEST-only**, igual que todo el bloque. Ninguno toca OPS ni canónico.

---

*Cierre técnico preliminar. No canoniza ni promueve. Próximo paso: decisión sobre cierre formal / canonización / promoción a OPS.*
