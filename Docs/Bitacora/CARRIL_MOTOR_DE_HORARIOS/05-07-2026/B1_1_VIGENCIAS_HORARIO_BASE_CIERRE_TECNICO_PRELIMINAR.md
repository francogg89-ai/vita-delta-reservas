# B1.1 — Vigencias de Horario Base — Cierre Técnico Preliminar

**Frente:** Motor de Horarios / Carril B1
**Sub-bloque:** B1.1 (capa de vigencias de horario base — tabla + puerta sancionada + guard diferido)
**Fecha:** 2026-07-05
**Naturaleza de este documento:** cierre de **bitácora TEST-only** para **congelar evidencia** antes de tocar el resolver en B1.2.

> **No es canónico. No es OPS. No implica promoción.** Es un punto de control de evidencia: registra qué se instaló y validó en TEST, qué garantías quedaron verificadas, qué límites son deliberados y qué deudas duras hay que saldar antes de activar B1.1 en B1.2.

---

## 1. Estado

- **B1.1 instalado en TEST.**
- **No OPS.**
- **No canónico** (Motor de Horarios no entra a `6B_SCHEMA_SQL.md` todavía — ver §2).
- **No portal-api** (Edge Function / gateway sin cambios).
- **No frontend** (React / Vercel sin cambios).
- **No n8n** (wrappers sin cambios).
- **No Vercel** (sin deploy).
- **No `configuracion_general`** (el gate anti-ambiente solo la **lee**: clave `ambiente`; no la escribe).
- **No cambio de comportamiento runtime.**
- **B1.1 inerte hasta B1.2**: la capa de vigencias existe, pero ninguna hora resuelta cambia y el resolver no consulta la tabla.

---

## 2. Contexto de versionado

- `6B_SCHEMA_SQL.md` está/queda en **v1.11.0** por el frente **Contabilidad / Cuenta Corriente**. No tiene relación con Motor de Horarios.
- **Motor de Horarios B1.1 NO está canonizado** todavía.
- Cuando el frente Horarios **cierre formalmente y se promueva a OPS**, se canonizará **desde la versión vigente en ese momento** (hoy v1.11.0), no desde v1.10.1. El bump de canónico saldrá de ese cierre.

---

## 3. Objetos instalados (TEST)

Ocho objetos, todos en schema `public`, todos con `REVOKE` (grants 0) y `COMMENT`:

1. **Tabla `vigencias_horario_base`** — global-only, bordes inclusivos (espejo overrides). `abierta = true` ⇒ sin fin explícito (no `fecha_hasta NULL = para siempre`, respeta R0). Reemplaza la base completa (default + domingo × checkin + checkout) para las fechas que cubre.
2. **Secuencia OWNED `vigencias_horario_base_id_vigencia_seq`** — `BIGSERIAL` de `id_vigencia`.
3. **6 CHECKs:**
   - `chk_vigencias_abierta` — coherencia `abierta` ↔ `fecha_hasta`.
   - `chk_vigencias_gap` — G2: turno pegado ≥ 2h (par default y par domingo).
   - `chk_vigencias_ventana` — 4 horas dentro de [07:00, 22:00].
   - `chk_vigencias_motivo` — `btrim(motivo) <> ''`.
   - `chk_vigencias_creado_por` — `btrim(creado_por) <> ''`.
   - `chk_vigencias_source_event` — `source_event IS NULL OR btrim(source_event) <> ''`.
4. **EXCLUDE `exc_vigencias_no_overlap`** — no-solapamiento entre vigencias activas; GiST de **rango puro** (no requiere `btree_gist`), `WHERE (activo)`.
5. **Helper `vigencias_conflictos_comprometidos(date,date,boolean,time,time,time,time)`** — SQL STABLE; evalúa una vigencia prospectiva contra comprometidos vivos donde la base gobierna (provenance vía resolver, sin reimplementar precedencia); fail-closed. Compartido por la puerta y el trigger.
6. **Función `crear_vigencia_horario(jsonb)`** — plpgsql VOLATILE SECURITY INVOKER; puerta sancionada; toma `pg_advisory_xact_lock(919010)`; valida V1–V11; INSERT; `{ok:true}` / `{ok:false}` parseable.
7. **Trigger-fn `trg_guard_vigencias()`** — barrera diferida G1; delega en el helper; `RAISE ERRCODE 45000` con DETAIL jsonb.
8. **Constraint trigger `trg_vig_guard`** — `AFTER INSERT OR UPDATE`, `DEFERRABLE INITIALLY DEFERRED`, `FOR EACH ROW` (sin DELETE).

### Artefactos (orden de carga)

1. `B1_1_VIGENCIAS_DDL_TEST.sql`
2. `B1_1_CREAR_VIGENCIA_FUNCION_TEST.sql`
3. `B1_1_GUARD_TRIGGER_TEST.sql`
4. `B1_1_SMOKES_TEST.sql`
5. `B1_1_ROLLBACK_TEST.sql` (disponible; no ejecutado — ver §8)

---

## 4. Evidencia de ejecución (TEST)

| Etapa | Resultado |
|---|---|
| DDL | **PASS** (grants_tabla=0, grants_seq=0, checks=6, exclude=1) |
| Función + helper | **PASS** (grants_funcion=0, grants_helper=0, funcion_existe=true, helper_existe=true) |
| Trigger | **PASS** (trigger_existe=1, deferrable_initially_deferred=true, eventos_ins_upd_sin_del=true, grants_trgfn_public=false) |
| Smoke | **38/38 PASS — TOTAL PASS** |

**Smoke — desglose:** HAPPY (2), FN-NEG (10), SOLAPA (1), G1-FN (1), G1-RES (1, fail-closed), BARRERA (9, una defensa por caso), AISLA (1), HARDEN (1), META-B (4), META-A (5), META-C (2), TOTAL (1).

**Sub-veredictos:**
- **Grants 0** — chequeo privilegio-por-privilegio (`has_table_privilege` / `has_sequence_privilege` / `has_function_privilege`) sobre `PUBLIC, anon, authenticated, service_role`, en tabla, secuencia, función, helper y trigger-fn.
- **META-A** — filas residuales en `vigencias_horario_base` = **0**; `reservas` / `pre_reservas` / `huespedes` / `overrides_operativos` sin cambios (fixtures revertidos).
- **META-B** — secuencias restauradas (restaurada IS NOT DISTINCT FROM pre): `huespedes`, `overrides`, `reservas`, `vigencias`.
- **META-C** — fingerprints intactos:
  - `resolver_horario(bigint,date)` = **`58d75c1b6b812ee2d2c9751ddcb0cd4d`**
  - `obtener_disponibilidad_rango(date,date,bigint)` = **`37009a32154f93b80520500c0f15b46b`**
- **AISLA** — con una vigencia de 15:00 existiendo, `resolver_horario` sigue devolviendo `13:00:00 | base` para un día no-domingo (inercia probada).

> Los fingerprints devueltos por TEST coinciden exactamente con los literales que fijaban los gates de los artefactos, lo que confirma retroactivamente que el resolver y la ODR no fueron alterados.

---

## 5. Garantías verificadas

- **G2** — turno pegado mínimo 2h (default y domingo), por CHECK.
- **Ventana** — 07:00–22:00 en las 4 horas, por CHECK.
- **Auditoría mínima** — `motivo` / `creado_por` no-blanco; `source_event` NULL o no-blanco, por CHECK.
- **No-solapamiento** — entre vigencias activas, por EXCLUDE (rango puro, sin `btree_gist`).
- **G1 targeted** — la base no pisa un comprometido donde la base gobierna; pre-check en la puerta + red diferida en el trigger.
- **Fail-closed ante `resolver_horario.ok = false`** — si el resolver no puede determinar provenance, el helper marca conflicto explícito `resolver_horario_invalido` (nunca fail-open); verificado con un override inducido.
- **Hardening grants** — 0 permisos útiles a los 4 roles en todos los objetos.
- **Inercia del resolver** — el resolver no lee la tabla; una vigencia existe pero no cambia ninguna hora resuelta.

---

## 6. Límites deliberados (documentados, no bugs)

1. **Regla no-pasado solo en la función** — `fecha_desde >= CURRENT_DATE` se valida únicamente en la puerta (`CURRENT_DATE` no es immutable; no hay red a nivel DB). Un `INSERT` manual con fecha pasada pasa estructuralmente.
2. **DELETE / desactivación pendientes de definición B1.2** — el trigger no cubre DELETE (inerte en B1.1); la semántica de DELETE y de `activo`→false se define en B1.2.
3. **Global-only** — sin overrides por cabaña en la capa de vigencias (por eso el EXCLUDE es de rango puro y no requiere `btree_gist`).
4. **Tabla inerte hasta B1.2** — B1.1 crea la capa pero no la conecta al resolver.

---

## 7. Deudas duras para B1.2

1. **Revalidar vigencias activas contra comprometidos vivos** antes de cablear el resolver — precondición dura de arranque de B1.2. G1 es el único drift-prone; G2/overlap quedan garantizados estructuralmente.
2. **Revisar helper / trigger por autorreferencia y nuevo origen `vigencia`** — hoy el helper usa `resolver_horario` para provenance mientras el resolver aún no lee vigencias. Al integrarlo en B1.2 hay que evitar (a) el ciclo resolver → vigencias → resolver, y (b) la mala interpretación de un nuevo origen `vigencia` que el resolver empezará a emitir (hoy distingue base / patron_domingo / override_global / override_cabana).
3. **Definir DELETE / desactivación** — cubrir la reversión base→config y sus implicancias G1.
4. **Recálculo del fingerprint del resolver** — al modificar `resolver_horario` para que lea vigencias, su fingerprint cambia.
5. **Cascada de gates / smokes / docs dependientes** — actualizar los archivos que fijan el fingerprint del resolver y re-cerrar.
6. **Re-correr smokes S0 / S1 / S2 / S3** — validar que el guard de overrides sigue verde tras el cambio del resolver.

---

## 8. Rollback

- **Archivo disponible:** `B1_1_ROLLBACK_TEST.sql` — bajas ordenadas sin `DROP CASCADE` (trigger → trigger-fn → función → helper → tabla; la tabla arrastra la secuencia OWNED, los 6 CHECKs, el EXCLUDE, el índice y la PK).
- **Validado en harness** (PostgreSQL 16.14): postcheck PASS — resolver/ODR/`btree_gist` intactos, objetos B1.1 removidos.
- **No ejecutado en TEST** porque B1.1 quedó verde.

---

**B1.1 cerrado (preliminar, TEST-only).** Próximo paso al retomar: **diseño B1.2** (integración del resolver con precedencia config → vigencia → override global → override cabaña; revalidación de vigencias activas; revisión helper/trigger anti-autorreferencia; cascada de fingerprints), **antes** de generar cualquier artefacto.
