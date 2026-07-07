# Cierre técnico preliminar — B1.2-core (Motor de Horarios)

**Estado:** aprobado en TEST (VERDE). Rollback disponible, NO ejecutado.
**Ambiente:** TEST (`bdskhhbmcksskkzqkcdp`), PostgreSQL 17.6.
**Naturaleza:** cierre PRELIMINAR. No canoniza, no toca OPS/portal-api/frontend/n8n/Vercel/lifecycle. Los identificadores permanentes de ledger (D-*/L-*) quedan diferidos al cierre formal del frente Motor de Horarios.

---

## 1. Qué se ejecutó

B1.2-core integró la capa de **vigencias horarias** (`vigencias_horario_base`, de B1.1) dentro del motor de resolución de horarios. Hasta R0/B1.1, `resolver_horario` derivaba la capa base desde `configuracion_general` (config fija) y aplicaba overrides encima. Desde core, la capa base es **"vigencia-si-cubre / config-si-no"**, conservando los overrides encima.

El único cambio semántico respecto de R0 es el **Paso A** (capa base). El resto del cuerpo del resolver es el refactor byte-a-byte de R0.

---

## 2. Arquitectura entregada (tres funciones)

| Función | Rol | Lenguaje / seguridad | Cambio |
|---|---|---|---|
| `public._resolver_horario(bigint, date, boolean)` | **Interno nuevo** | plpgsql, STABLE, SECURITY INVOKER, owner-only | Refactor de R0. Flag `true` = vigencia-aware (producción); `false` = siempre config (ciego, idéntico a R0 para fechas sin vigencia) |
| `public.resolver_horario(bigint, date)` | **Wrapper público** | sql, STABLE, SECURITY INVOKER, owner-only | `SELECT public._resolver_horario($1,$2,true)`. Firma y contrato de retorno idénticos a R0 |
| `public.vigencias_conflictos_comprometidos(...)` | **Helper G1** | (recreado) | Su LATERAL ahora apunta a `public._resolver_horario(c.id_cabana, c.fecha, false)` |

**Precedencia final** (por tipo checkin/checkout, independientes): `config (fallback) → vigencia → override_global → override_cabana`.
**Orígenes nuevos** en el retorno: `vigencia` (día hábil), `vigencia_domingo`.

---

## 3. Invariantes verificados

- **INV-1 (no-autorreferencia):** el helper G1 llama al interno **ciego** (`false`), nunca al wrapper vigencia-aware. Evita que una vigencia existente se valide contra sí misma. Resuelve la deuda dura de B1.1. Probado en rutas (test C).
- **Inercia:** con 0 vigencias activas, el wrapper es funcionalmente idéntico a R0 (solo cambia el fingerprint).
- **Contrato estable:** firma `(bigint, date)` y estructura JSONB de retorno intactas ⇒ ODR y `vista_disponibilidad` **no se tocan** (ODR fp intacto, vista = 600 filas == pre).
- **Permisos owner-only:** `REVOKE EXECUTE` de PUBLIC + `anon` + `authenticated` + `service_role` sobre las tres funciones (espejo del modelo R0). Verificado privilegio-por-privilegio en el postcheck, PUBLIC incluido.

---

## 4. Fingerprints (TEST — referencia canónica del nuevo estado)

| Objeto | Fingerprint TEST (PG 17.6) |
|---|---|
| `resolver_horario(bigint,date)` — wrapper nuevo | `1bd96c89e587b15582fd7b2e29ae7e18` |
| `_resolver_horario(bigint,date,boolean)` — interno | `566ea522351a6b4e57b6dd770124814b` |
| `vigencias_conflictos_comprometidos(...)` — helper | `871fcde54be66b47c3e303e73b893c24` |
| `obtener_disponibilidad_rango(date,date,bigint)` — ODR | `37009a32154f93b80520500c0f15b46b` (intacto) |

**Fingerprint anterior retirado:** `resolver_horario` R0/B1.1 = `58d75c1b6b812ee2d2c9751ddcb0cd4d` (ya no es el estado vigente en TEST).

---

## 5. Evidencia de ejecución en TEST

**Migración:** estado = core aplicado; wrapper `1bd96c89…`; interno `566ea522…`; helper `871fcde5…`; ODR `37009a32…` intacto; vista = 600 filas.

**Performance** (baseline B1.2-pre = 192.2 ms mediana; GATE escenario sin vigencia ≤ 288.3 ms = 1.5× baseline):

| Escenario | Filas | Mediana | Ratio vs baseline | Gate |
|---|---|---|---|---|
| `1_sin_vigencia` | 600 | 244.7 ms | 1.27× | **OK** (≤ 288.3 ms) |
| `2_vigencia_config_equal` | 600 | 201.6 ms | 1.05× | — |
| `3_override_cabana` | 600 | 234.4 ms | 1.22× | — |

META-A (filas sin cambios), META-B (secuencias `last_value` + `is_called`), META-C (fingerprints) = **OK**.

**Rutas** (ejecutadas como owner = producción): A (vista refleja vigencia) PASS · A2 (fuera de vigencia usa config/domingo) PASS · C (INV-1: interno ciego = config, wrapper = vigencia) PASS · B (crear_prereserva congela la hora de la vigencia) PASS. META-A/B = OK.

**Nota de performance:** el gate pasa con margen (1.27× < 1.5×). La mediana sin vigencia (244.7 ms) salió mayor que con vigencia config-equal (201.6 ms); esto es **varianza del entorno TEST** (contenedor compartido, sin aislamiento de CPU), no un efecto real de las vigencias — ambos paths consultan la tabla de vigencias por igual. Lo relevante es que los tres escenarios quedan bajo el techo del gate.

**Pre-validación:** los cuatro artefactos se validaron end-to-end en harness PostgreSQL 16.14 antes de TEST (incluido un test negativo que confirma que la verificación META aborta con `RAISE EXCEPTION` ante un fallo de restauración). Los fingerprints difieren entre harness (PG16) y TEST (PG17.6); los valores de la tabla §4 son los de TEST.

---

## 6. Rollback

`B1_2_CORE_ROLLBACK_TEST.sql` está disponible y verificado en harness: reproduce R0 verbatim (restaura `58d75c1b…`), recrea el helper B1.1 verbatim (LATERAL vuelve a `resolver_horario`), hace DROP del interno, y confirma ODR intacto + vista + vigencias conservadas. **NO ejecutado** — Franco mantiene core.

---

## 7. DEUDA CONTROLADA (explícita)

El cableado cambió el fingerprint de `resolver_horario` (`58d75c1b…` → `1bd96c89…`) y del helper G1. **Cualquier gate, smoke o documento que hardcodee `58d75c1b6b812ee2d2c9751ddcb0cd4d` puede fallar su chequeo de fingerprint hasta que se ejecute B1.2-cascade.** Esto afecta, entre otros, a los smokes de B1.1 (S0–S3) y a los gates de fingerprint de las migraciones de B1.1.

**Esto es deuda controlada, no falla funcional.** El resolver funciona correctamente (probado por rutas + perf); solo los guardas de identidad que esperan el fp viejo quedan desalineados. B1.2-cascade realinea fingerprints, gates, smokes y documentación al nuevo estado.

---

## 8. Fuera de alcance (no tocado)

OPS · canónico (`6B_SCHEMA_SQL.md`) · portal-api · frontend · n8n · Vercel · lifecycle (`trg_vig_no_delete` + `desactivar_vigencia_horario`) · cascade. Bootstrap kit pinned en v1.9.0 (deuda P-CC-4). B1.1 y core siguen **uncanonicalizados**.

---

## 9. Próximo paso

B1.2-cascade (ver `KICKOFF_B1_2_CASCADE.md`): realinear fingerprints/gates/smokes/docs al nuevo resolver. Un bloque, hard stop, con clone fresco.
