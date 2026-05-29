# 7E_CIERRE — Endurecimiento de permisos Data API en DEV (paridad con TEST)

**Etapa:** 7E — Endurecimiento de permisos Data API en DEV.
**Estado:** ✅ Cerrada (2026-05-28).
**Ámbito:** exclusivamente DEV (proyecto Supabase DEV). TEST, OPS y PROD no se tocaron.
**Schema:** `6B_SCHEMA_SQL.md v1.7.3` sin modificar.
**Decisiones:** D-7E-01, D-7E-02.

---

## 1. Objetivo

Cerrar el pendiente activo 1.5 de `Pendiente_pre_produccion.md`: aplicar a DEV el
modelo de permisos Data API que TEST ya tenía desde 7B-GRANTS — `REVOKE EXECUTE`
sobre las funciones del proyecto a `PUBLIC`, `anon`, `authenticated` y
`service_role`, dejando DEV en paridad de permisos con TEST en lo que respecta a
la ejecución de funciones vía Data API.

No fue agregar funcionalidad. No fue modificar schema. Fue cerrar la asimetría
conocida documentada en `Pendiente_pre_produccion.md` 1.5.

---

## 2. Alcance (7E estricta — Opción 1)

Solo `REVOKE EXECUTE` sobre las 13 funciones del proyecto a los 4 grantees Data
API. Decisión explícita de Franco (Opción 1), tomada tras el hallazgo A5.

**No se tocó:**
- Tablas, vistas, secuencias (ningún `GRANT`/`REVOKE` sobre ellas).
- Funciones, vistas, triggers, tablas, enums, constraints, schema.
- Workflows n8n.
- TEST, OPS, PROD.
- El residual amplio de permisos de tabla a roles Data API (hallazgo A5), que
  queda documentado como pendiente separado 1.7 — ver sección 7.

**Restricciones respetadas:** sin `DROP ... CASCADE`, sin `TRUNCATE`, sin
`TRUNCATE ... CASCADE`. No se conectaron consumidores reales.

---

## 3. Método

Cuatro bloques separados, en línea con el método validado en 7B/7D (snapshot
read-only → cambio → verificación → cierre documental), nunca un único bloque
opaco.

- **Bloque A — snapshot read-only.** Preflight de entorno por identidad exacta de
  cabañas DEV 17-21 con veredicto explícito (`ENTORNO_DEV_OK`); inventario de
  funciones de `public` con firma y owner; owner de funciones; grants `EXECUTE`
  "antes" (ACL materializada + privilegio efectivo por rol); grants residuales
  sobre tablas/vistas/secuencias; conteos de seed estructural y de objetos.
- **Bloque B — cambios.** Transacción única `BEGIN; ... COMMIT;` que contiene un
  re-gate de entorno (`DO $$ ... RAISE EXCEPTION` si la identidad de las 5
  cabañas DEV no coincide) seguido de los 13 `REVOKE EXECUTE`. Atómico
  (revierte todo si algo falla a mitad) e idempotente (revocar un privilegio ya
  ausente no es error).
- **Bloque C — verificación posterior.** Re-gate de entorno; prueba de 0 fugas de
  EXECUTE; owner intacto y `postgres` ejecutando por ownership; schema/estructura
  sin cambios vs snapshot; residual de tablas intacto.
- **Bloque D — cierre documental.** Este documento + actualización de
  `DECISIONES_NO_REABRIR.md`, `Pendiente_pre_produccion.md` y
  `ESTADO_ACTUAL_VITA_DELTA.md`.

---

## 4. Inventario afectado — 13 funciones del proyecto (owner `postgres`)

El snapshot A1 reportó **201 funciones** en `public`. De ellas, **188 son de la
extensión `btree_gist`** (`gbt_*`, `*_dist`, `gbtreekey*`), owner `supabase_admin`
— **no son del proyecto y no se tocaron**. Filtrando por owner `postgres`, las
funciones del proyecto son exactamente **13**, sin overloads (cada `proname`
aparece una sola vez):

**Operativas (10):**
1. `cancelar_prereserva(payload jsonb)`
2. `confirmar_reserva(payload jsonb)`
3. `crear_bloqueo(payload jsonb)`
4. `crear_prereserva(payload jsonb)`
5. `expirar_prereservas_vencidas()`
6. `normalizar_telefono(input text)`
7. `obtener_disponibilidad_rango(p_fecha_desde date, p_fecha_hasta date, p_id_cabana bigint)`
8. `registrar_pago(payload jsonb)`
9. `upsert_huesped(payload jsonb)`
10. `validar_disponibilidad(p_id_cabana bigint, p_fecha_in date, p_fecha_out date, p_excluir_prereserva bigint)`

**De trigger (3, incluidas por paridad con TEST):**
11. `log_cambio_estado()`
12. `set_telefono_normalizado()`
13. `set_updated_at()`

El número coincide con las 13 funciones endurecidas en TEST (7B-GRANTS).

---

## 5. Estado "antes" (snapshot A) y SQL aplicado (Bloque B)

**Antes (A3/A4):** las 13 funciones tenían ACL materializada idéntica
`{=X/postgres, postgres=X/postgres, anon=X/postgres, authenticated=X/postgres,
service_role=X/postgres}` — es decir, `EXECUTE` a PUBLIC (`=X/postgres`) y a los
tres roles Data API. A4 confirmó `puede_ejecutar = true` para
`anon`/`authenticated`/`service_role`/PUBLIC en las 13. Estado abierto idéntico
al que tenía TEST antes de 7B-GRANTS.

**SQL aplicado (Bloque B), transaccional y con re-gate:**

```sql
BEGIN;

DO $$
BEGIN
  IF (
    SELECT count(*) FROM cabanas
    WHERE (id_cabana, nombre) IN (
      (17, 'Bamboo'), (18, 'Madre Selva'), (19, 'Arrebol'),
      (20, 'Guatemala'), (21, 'Tokio')
    )
  ) <> 5
  OR (SELECT count(*) FROM cabanas WHERE id_cabana BETWEEN 1 AND 5) <> 0
  THEN
    RAISE EXCEPTION 'ABORT 7E: entorno no es DEV (identidad de cabañas 17-21 no coincide). Transacción revertida, ningún REVOKE aplicado.';
  END IF;
  RAISE NOTICE 'Gate DEV OK. Aplicando REVOKE EXECUTE sobre las 13 funciones del proyecto.';
END $$;

-- Operativas (10)
REVOKE EXECUTE ON FUNCTION public.cancelar_prereserva(payload jsonb)            FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.confirmar_reserva(payload jsonb)              FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.crear_bloqueo(payload jsonb)                  FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.crear_prereserva(payload jsonb)               FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.expirar_prereservas_vencidas()               FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.normalizar_telefono(input text)               FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.obtener_disponibilidad_rango(p_fecha_desde date, p_fecha_hasta date, p_id_cabana bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.registrar_pago(payload jsonb)                 FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.upsert_huesped(payload jsonb)                 FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.validar_disponibilidad(p_id_cabana bigint, p_fecha_in date, p_fecha_out date, p_excluir_prereserva bigint) FROM PUBLIC, anon, authenticated, service_role;

-- De trigger (3) — paridad con TEST
REVOKE EXECUTE ON FUNCTION public.log_cambio_estado()                           FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.set_telefono_normalizado()                    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.set_updated_at()                              FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
```

Resultado de ejecución: COMMIT limpio ("Success. No rows returned").

---

## 6. Evidencia de verificación (Bloque C)

| Verificación | Query | Esperado | Resultado |
|---|---|---|---|
| C1 — DEV sigue siendo DEV | re-gate por cabañas 17-21 | `ENTORNO_DEV_OK` | ✅ `ENTORNO_DEV_OK` |
| C2.3 — fugas de EXECUTE | conteo de funciones del proyecto con EXECUTE para los 4 grantees | `0` | ✅ `0` |
| C3 — owner intacto + ownership | owner y `has_function_privilege('postgres', ...)` en las 13 | owner `postgres`, ejecuta `true` | ✅ 13/13 owner `postgres`, ejecuta `true` |
| C4 — schema sin cambios | conteo funciones/vistas/triggers | `201 / 6 / 19` (= A6.2) | ✅ `201 / 6 / 19` |
| C5 — residual de tablas intacto | conteo de grants de tabla a roles Data API | sin cambios (alto) | ✅ `480` (residual A5 intacto) |

**Lectura:** el REVOKE se aplicó en las 13 funciones (0 fugas), sin crear ni
destruir objetos, sin tocar el owner, y sin alterar el residual de tablas. DEV
quedó en paridad con TEST en EXECUTE sobre funciones.

---

## 7. Verificación de no-impacto a n8n

n8n DEV conecta por el pooler de Supabase con la credencial `vita_supabase_dev`
(host `aws-1-sa-east-1.pooler.supabase.com`, puerto `6543`, database `postgres`,
user `postgres.<DEV_REF>`, `Ignore SSL Issues` ON), es decir como **owner
`postgres`** y por PostgreSQL directo, **no vía Data API/PostgREST**. El owner
ejecuta sus funciones por **ownership**, capacidad independiente del grant de
`EXECUTE`; por tanto el REVOKE no le quita nada.

- Confirmado conceptualmente: Franco revisó la credencial antes del Bloque A.
- Confirmado empíricamente por analogía: el mismo REVOKE se aplicó a TEST en
  7B-GRANTS y W1 (read) + W2-W6 (writes) siguieron operando.
- Confirmado en C3: `postgres` conserva `EXECUTE` efectivo (`true`) en las 13.

Se confirmó además que **no hay consumidores Data API/PostgREST activos en DEV**
(sin frontend público, bot real, MercadoPago real, dashboard externo ni
consumidor productivo conectado).

---

## 8. Hallazgo abierto (NO cerrado en 7E)

El snapshot A5 reveló que en DEV los roles `anon`/`authenticated`/`service_role`
tienen, sobre **todas las tablas y vistas**, el set **completo** de privilegios
(`SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN`) y
sobre las secuencias `SELECT, UPDATE, USAGE`. Esto es mucho más amplio que el
`Dxtm` residual de TEST (solo `TRUNCATE/REFERENCES/TRIGGER`, sin SELECT ni
escritura — ver D-7B-03). El conteo de referencia en C5 fue **480** grants de
tabla a roles Data API.

Por decisión de alcance (Opción 1 — 7E estricta), **7E NO tocó este residual**.
Queda documentado como **asimetría DEV↔TEST nueva/más amplia de lo esperado**,
a tratar en una etapa futura separada si se decide. Ver
`Pendiente_pre_produccion.md` sección 1.7.

Atenuantes que hacen que no sea urgencia: no hay consumidores Data API activos en
DEV; n8n entra como owner por pooler y no usa estos grants; RLS sigue postergado
hasta tener frontend público.

---

## 9. Decisiones de la etapa

- **D-7E-01** — 7E estricta: solo `REVOKE EXECUTE` sobre las 13 funciones del
  proyecto a PUBLIC/anon/authenticated/service_role; el residual amplio de
  permisos sobre tablas/vistas/secuencias (hallazgo A5) no se toca y queda
  documentado como pendiente 1.7.
- **D-7E-02** — Las 3 funciones de trigger (`log_cambio_estado`,
  `set_telefono_normalizado`, `set_updated_at`) se incluyen en el REVOKE por
  paridad total con TEST; es inocuo (los triggers se disparan por el motor, no
  por `EXECUTE` de un rol).

---

## 10. Lección operativa

- **L-7E-01:** En Supabase, el SQL Editor del Dashboard conecta como `postgres`
  directo (no por pooler), por lo que `current_user` allí devuelve `postgres` y
  NO el patrón `postgres.<project_ref>`. En ese contexto el discriminador fuerte
  de ambiente debe ser la identidad del seed (IDs exactos de cabaña), no
  `current_user` (consistente con L-7B-01). El veredicto de entorno por
  `(id_cabana, nombre)` cumplió ese rol como gate inequívoco en A0, B (re-gate) y
  C1.

---

## 11. Estado tras 7E

DEV queda en **paridad con TEST en EXECUTE sobre funciones del proyecto**: las 13
funciones ya no son invocables vía Data API por PUBLIC/anon/authenticated/
service_role; el owner `postgres` (y por ende n8n) sigue ejecutándolas por
ownership. El pendiente explícito 1.5 queda cerrado. La asimetría más amplia de
permisos de tabla (A5) queda registrada como pendiente 1.7, sin tocar.
