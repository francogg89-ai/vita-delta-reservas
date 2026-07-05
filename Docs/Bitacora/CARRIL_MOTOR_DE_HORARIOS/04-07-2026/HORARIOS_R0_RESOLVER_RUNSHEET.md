# R0 — Corrección de drift del resolver (`fecha_hasta IS NULL`) — RUNSHEET

**Pre-bloque explícito. NO es parte del guard todavía.** Corrige la semántica de
`fecha_hasta IS NULL` en `resolver_horario()` para alinearla con **Etapa 2**
(`ARQUITECTURA_ETAPA_2_VITA_DELTA.md` L373–374, L427: *"NULL = aplica solo a
fecha_desde"*). El resolver la había drifteado a `[fecha_desde, +∞)`.

- **Alcance:** SOLO **TEST** (`bdskhhbmcksskkzqkcdp`). **NO** OPS, **NO** canónico,
  **NO** gateway/frontend/workflows.
- **Sin acuñar `D-*`/`L-*`** (se mintean en el cierre formal del frente de horarios).
- **Sin `DROP ... CASCADE`.**
- Ejecutás vos; yo no toco TEST/OPS/n8n/Vercel/git.

---

## Único cambio de cuerpo en el resolver

| | Predicado de selección de override (Paso B) |
|---|---|
| **Antes (fp `759662b4…`)** | `AND (fecha_hasta IS NULL OR fecha_hasta >= p_fecha)` |
| **Después (R0)** | `AND p_fecha <= COALESCE(fecha_hasta, fecha_desde)` |

Con `fecha_desde <= p_fecha` ya en el `WHERE`, para `NULL` colapsa a
`p_fecha = fecha_desde` → exactamente *"solo fecha_desde"*. El resto del cuerpo es
**idéntico** al vigente.

## Método: `CREATE OR REPLACE FUNCTION` (no `DROP+CREATE`)

Se cumplen las tres condiciones de tu preferencia base:

1. **Firma sin cambio** (solo cambia el cuerpo) → `CREATE OR REPLACE` aplica sin el
   fallo de cambio de tipo de retorno.
2. **Preserva OID → ACL/owner/COMMENT sobreviven.** `DROP+CREATE` los resetearía
   (`proacl IS NULL ⇒ PUBLIC ejecuta`, L-RDEV-01). Igual re-afirmo `REVOKE`+`COMMENT`
   idempotentes (cinturón-y-tiradores).
3. **Bug del Dashboard no dispara.** TEST tiene *"Enable automatic RLS = OFF"*
   (L-8A-03/04), así que el bug (Supabase confunde variables `v_` con tablas y
   appendea `ALTER TABLE … ENABLE RLS`, truncando el SQL → `42601`) **no** ocurre.
   El resolver original ya se aplicó con `CREATE OR REPLACE` en TEST sin incidente.
   Ref **L-CC-07**.

**Por qué no rompe `crear_prereserva` / `obtener_disponibilidad_rango`:** ambos
llaman `resolver_horario` **por nombre** en su cuerpo PL/pgSQL (resolución en
runtime, **no** registrada en `pg_depend`). Como la firma `(bigint,date)→jsonb` no
cambia y el **OID se preserva**, siguen apuntando al **mismo objeto** con el cuerpo
nuevo. El PREFLIGHT lo evidencia (0 dependientes duros; ambos callers referencian el
resolver). No hay ventana: `CREATE OR REPLACE` es atómico y ni siquiera dropea.

*Contingencia (no esperada):* si el editor mostrara `42601` por auto-RLS ON
inesperado, fallback al workaround `DROP FUNCTION` + `CREATE FUNCTION` en dos runs
(L-CC-07). Avisame y te lo reescribo.

---

## Orden de ejecución (Supabase SQL Editor, **sin selección parcial** — L-8A-01)

1. **`HORARIOS_R0_RESOLVER_PREFLIGHT_TEST.sql`** *(read-only)*
   Esperado: consulta 1 → **0 filas** (sin dependientes duros); consulta 2 →
   `obtener_disponibilidad_rango=true`, `crear_prereserva=true`; consulta 3 →
   `resolver_fp_ok=true`, `odr_fp_ok=true`.

2. **`HORARIOS_R0_RESOLVER_FIX_TEST.sql`**
   Gate valida `ambiente='test'` + `schema=public` + resolver `759662b4…` (pre-fix)
   + ODR `37009a32…`. El aviso *"Run without RLS"* es esperado y correcto (L-8A-04).
   **Último SELECT → anotá `resolver_fingerprint_nuevo`** y confirmá
   `cambio_confirmado=true`, `odr_fingerprint_sin_cambio=37009a32…`.

3. **`HORARIOS_R0_RESOLVER_SMOKES_TEST.sql`**
   Gate exige que el FIX ya esté aplicado (resolver `<> 759662b4`). Esperado:
   veredicto **`SMOKE R0 VALIDADO: 9/9 PASS, 0 FAIL`** con `overrides_residual=0` y
   `prereservas_residual=0`. Si la compuerta falla, el editor muestra la excepción
   con las filas No-PASS y la tx se revierte sola (nada persiste).

### Rollback (solo si hace falta revertir R0)

4. **`HORARIOS_R0_RESOLVER_ROLLBACK_TEST.sql`**
   Restaura el cuerpo original (predicado viejo) por `CREATE OR REPLACE`. Último
   SELECT → `rollback_ok=true` (fingerprint de vuelta en `759662b4…`).

---

## Transición de fingerprint

| Artefacto | resolver fp | ODR fp |
|---|---|---|
| Estado previo | `759662b4afaed7af426917aa3717b34c` | `37009a32154f93b80520500c0f15b46b` |
| Tras FIX | **nuevo** (lo reporta el paso 2) | `37009a32…` (sin cambio) |
| Tras ROLLBACK | `759662b4afaed7af426917aa3717b34c` | `37009a32…` (sin cambio) |

**Ripple a recordar:** el nuevo fingerprint del resolver reemplaza a `759662b4…`
como valor esperado en los gates de los smokes del guard (S0/S1/S2), que se generan
después. La **definición** de la ODR no cambia (su fp se mantiene); solo cambia su
**output** para overrides con `fecha_hasta NULL` (que es el objetivo de R0).

## Cobertura de smokes (9 casos)

`C1` NULL aplica en `fecha_desde` · `C2` NULL **no** aplica en `fecha_desde+5` ·
`C3a` rango no-null inclusivo en el borde (`D+2`) · `C3b` no aplica pasado el borde
(`D+3`=base) · `C4` precedencia cabaña>global · `C5` HARD `cast_invalido` intacto ·
`C6a` ODR ejecuta + override en `D` · `C6b` ODR `D+5`=base · `C6c` `crear_prereserva`
ejecuta y escribe.

---

**Freno acá.** No genero helper, trigger ni `crear_override_horario` hasta que R0
esté aplicado y verde en TEST y me des el OK para el Sub-bloque 0 del guard.
