# Kickoff — B1.2-cascade (realineación de fingerprints / gates / smokes / docs)

**Precondición:** B1.2-core aprobado en TEST (ver `CIERRE_TECNICO_PRELIMINAR_B1_2_CORE.md`).
**Estado:** PROPUESTA de alcance. No hay artefactos todavía. El diseño detallado (inventario exacto) es el primer paso del bloque, con clone fresco.

---

## 1. Motivación

B1.2-core cambió el fingerprint de `resolver_horario` y del helper G1. La red de guardas de identidad (gates de migración, smokes de regresión, documentación) todavía espera el estado anterior (`58d75c1b…`). Cascade **realinea todo al nuevo estado** para que los guardas vuelvan a ser fail-closed correctos y la documentación refleje la realidad. Es la contrapartida planificada de la deuda controlada declarada en el cierre de core.

**Cascade es barrido de fingerprints + actualización de texto, NO cambios funcionales al motor.** No se toca ninguna función del resolver; se actualizan los artefactos que la referencian.

---

## 2. Valores objetivo (estado post-core, TEST)

| Objeto | Fingerprint NUEVO (reemplaza) | Fingerprint VIEJO (a retirar) |
|---|---|---|
| `resolver_horario(bigint,date)` | `1bd96c89e587b15582fd7b2e29ae7e18` | `58d75c1b6b812ee2d2c9751ddcb0cd4d` |
| `_resolver_horario(bigint,date,boolean)` | `566ea522351a6b4e57b6dd770124814b` | (no existía) |
| `vigencias_conflictos_comprometidos(...)` | `871fcde54be66b47c3e303e73b893c24` | (fp helper B1.1 — a confirmar en inventario) |
| `obtener_disponibilidad_rango(...)` | `37009a32154f93b80520500c0f15b46b` | (sin cambio) |

---

## 3. Inventario a barrer (a confirmar con clone fresco + set B1.1)

Categorías candidatas. El inventario **exacto** se construye en el primer paso del bloque con `grep 58d75c1b6b812ee2d2c9751ddcb0cd4d` sobre el repo y sobre el set de artefactos B1.1:

1. **Smokes B1.1 (S0–S3):** hardcodean el fp del resolver `58d75c1b…` en sus gates y/o esperan el fp viejo del helper. Si se re-corrieran hoy, fallan el gate de fingerprint (esperado).
2. **Gates de migraciones B1.1:** `crear_vigencia_horario` y satélites que verifican el fp del resolver como precondición.
3. **Documentación no-canónica del Motor de Horarios:** bitácora del carril, documentos de diseño/cierre de B1.1 que describan el resolver como config-only.
4. **Satélites del proyecto** (según decisión §7): `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `Pendiente_pre_produccion.md`, `CLAUDE.md`, `README.md`.

**Dependencia:** los archivos de B1.1 (smokes, gates) **no están commiteados** en el repo — están como artefactos entregados. El inventario necesita que Franco confirme/aporte ese set. En el repo sí está el archivo R0 (`HORARIOS_R0_RESOLVER_FIX_TEST.sql`), que contiene el CREATE que produce `58d75c1b…`; ese archivo describe un estado que core ya reemplazó, y hay que decidir su tratamiento (§7, DC-03).

---

## 4. Consideraciones técnicas

- **Semántica de G1 sin cambios:** el helper ahora llama al interno **ciego** (`false`), que es byte-idéntico a R0 para su propósito. G1 sigue leyendo config para el chequeo de turnos pegados; solo cambió el punto de llamada. Los smokes de B1.1 que probaban G1 no cambian su lógica de aserción, solo su expectativa de fingerprint.
- **B1.1 uncanonicalizado:** ni B1.1 ni core están en `6B_SCHEMA_SQL.md`. Cascade **no** canoniza (canónico está fuera de alcance por decisión de Franco); la canonización queda como deuda pendiente separada.
- **El interno ciego como red:** el interno con `false` es la garantía de identidad con R0. Cualquier smoke nuevo de cascade puede apoyarse en él para demostrar la equivalencia funcional con el estado pre-core.

---

## 5. Metodología (igual que siempre)

Clone fresco (`git clone --depth 1`) → inventario exacto (grep del fp viejo en repo + set B1.1) → diseño del barrido → **aprobación de Franco** → artefactos (patchers Python con `count==1` + reverse-proof para textos/docs; smokes re-armados; JSON via builders si aplica) → validación en harness PG16.14 → **Franco ejecuta en TEST** → Franco verifica. Un bloque, hard stop. EOL discipline per-file. Sin tocar OPS/portal-api/frontend/n8n/Vercel.

---

## 6. Decisiones abiertas (a resolver antes de artefactos)

- **DC-01 — Alcance de smokes B1.1:** ¿cascade re-arma los smokes B1.1 (S0–S3) completos para que esperen el estado post-core, o solo parcha los gates de fingerprint dentro de ellos? *(Propuesta: re-armar, ya que B1.1 no está canonizado y sus smokes son la red de regresión activa.)*
- **DC-02 — Tratamiento del archivo R0 en el repo:** ¿se conserva `HORARIOS_R0_RESOLVER_FIX_TEST.sql` como referencia histórica del estado retirado, se marca como superseded, o se reemplaza? *(Propuesta: conservar + anotar como superseded por core; registrar la transición R0→core en el ledger histórico.)*
- **DC-03 — Registro del fp viejo:** ¿el fp `58d75c1b…` se elimina limpio de los guardas activos pero se preserva en Lecciones/Decisiones como evento histórico R0→core? *(Propuesta: sí.)*
- **DC-04 — Momento de actualización de satélites:** la convención dice "no satellite updates mid-carril, single coordinated promotion package". ¿Cascade es ese paquete de promoción para el Motor de Horarios, o los satélites se difieren hasta cerrar el frente completo (core + lifecycle)? *(Propuesta: cascade realinea gates/smokes activos (necesarios para la red de regresión); los satélites de decisiones/lecciones/estado se difieren al paquete coordinado que cierre el Motor, salvo que se decida lo contrario.)*
- **DC-05 — Definición del gate del helper:** ¿los gates que verifican el helper migran a esperar `871fcde5…`, o se relajan a "helper existe + INV-1 se cumple" (chequeo por comportamiento en vez de por fingerprint)? *(A discutir según cuán frágil querés el gate del helper.)*

---

## 7. Fuera de alcance de cascade

Canónico (`6B_SCHEMA_SQL.md`) · OPS · portal-api · frontend · n8n · Vercel · lifecycle · cualquier cambio funcional al resolver. Cascade es exclusivamente realineación de identidad y texto.

---

## 8. Primer paso propuesto

Abrir el bloque de cascade con: clone fresco + inventario exacto (grep `58d75c1b6b812ee2d2c9751ddcb0cd4d` en el repo) + confirmación del set de artefactos B1.1. Con ese inventario en mano, diseñar el barrido y traer las decisiones DC-01…DC-05 resueltas antes de generar cualquier artefacto.
