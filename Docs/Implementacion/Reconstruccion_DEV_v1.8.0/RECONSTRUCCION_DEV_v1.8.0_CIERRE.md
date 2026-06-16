# RECONSTRUCCIÓN DE DEV DESDE v1.8.0 — CIERRE

**Etapa:** Reconstrucción de DEV desde cero a partir del canónico `6B_SCHEMA_SQL.md v1.8.0`.
**Fecha de cierre:** 2026-06-15.
**Estado:** ✅ Cerrada. DEV nuevo levantado desde cero (Parte B + Parte C), **cerrado como OPS**, con `ambiente='dev'`, validado al bootstrap y endurecido. **OPS y TEST no se tocaron.** DEV viejo queda **congelado**.
**Ámbito:** levantamiento de entorno + hardening de permisos. Claude actuó como arquitecto/auditor: generó prechecks, runsheets, verificaciones y este cierre; **Franco ejecutó todos los writes** en Supabase (Claude no operó la instancia).

> **Qué NO reabre este cierre.** No reabre ni redefine el diseño del Carril B (9C→9H), la promoción a OPS, ni el canónico v1.8.0. Las decisiones de esta etapa (`D-RDEV-XX`) son de **levantamiento/hardening de entorno**, no de modelo.

---

## 1. Resumen ejecutivo

DEV quedó fuera del alcance de la promoción del Carril B a OPS (D-PROMO-13). Esta etapa lo **reconstruyó desde cero** en un **proyecto Supabase nuevo** (`VITA_DELTA_DEV`, `DEV_REF=wsrdzjmvnzxidjlovlja`, São Paulo, PostgreSQL 17.6), bootstrappeando el canónico **v1.8.0** autocontenido (Parte B base + Parte C Carril B), sin copiar datos reales ni fixtures de OPS/TEST.

Resultado verificado:

- **Proyecto creado cerrado** (Data API ON, "Automatically expose new tables" **OFF**, "Enable automatic RLS" **OFF**) → resuelve el residual A5 / pendiente 1.7 **por construcción**.
- **Parte B** ejecutada: inventario base idéntico al bootstrap de OPS (8A) — 2 extensiones, 4 enums, 20 tablas, 6 vistas, 13 funciones del motor, 13 triggers, 2 EXCLUDE; seed 5/3/10/1/1/1; 2 jobs `pg_cron`.
- **Parte C** ejecutada: Carril B completo — 9 tablas, 21 funciones, 10 triggers de inmutabilidad, 6 secuencias; seam 5/5; matriz julio=378 / noviembre=456; reparto Σ exacto al centavo; `ambiente='dev'`.
- **Barrido global de permisos** (base + Carril B): 0 exposición amplia en relaciones y secuencias; residual `Dxtm` en tablas base **reportado explícitamente** y aceptado por paridad OPS/TEST.
- **Hallazgo y corrección:** un bootstrap fresco de v1.8.0 deja las **13 funciones del motor PUBLIC-ejecutables** (NULL-acl), porque el REVOKE de la base no está en el canónico. Se aplicó el REVOKE (espejo de 7E/8A) → **0 funciones expuestas**. DEV quedó cerrado completo.

DEV queda listo como **laboratorio seguro** del portal operativo interno y de nuevos workflows n8n.

---

## 2. Estado de entrada (verificado)

- **Canónico `6B_SCHEMA_SQL.md v1.8.0`** autocontenido (Parte B + Parte C, bootstrap fresco verificado en el bump).
- **OPS** operativo con el Carril B promovido; **TEST = OPS** por huella. Ninguno se toca.
- **DEV viejo:** proyecto con cabañas IDs 17-21, schema v1.7.3 sin Carril B, con residual A5 (permisos amplios a roles Data API). Fuera del alcance de la promoción (D-PROMO-13).

---

## 3. Ejecución por fases (verificada)

| Fase | Qué hizo | Veredicto |
|---|---|---|
| **F0** | Creación del proyecto Supabase nuevo, **cerrado** (Data API ON, expose new tables OFF, auto-RLS OFF). Registro de `DEV_REF`. | ✅ |
| **F1** | Prechecks read-only: P0 contexto (PG 17.6), **P1 base vacía** (0 objetos), P2 extensiones disponibles (`btree_gist` 1.7, `pg_cron` 1.6.4), P3 roles API presentes, **P4 switches cerrados** (solo `Dxtm` inocuo a roles API en el default de postgres; sin r/a/w/d). | ✅ `BASE_VACIA_OK` |
| **F2** | Parte B (Bloques 1→22), copiados del canónico, uno por vez. Checkpoint de cierre read-only. | ✅ `PARTE_B_OK` (2/4/20/6/13/13/2 + seed 5/3/10/1/1/1 + 2 jobs) |
| **F3** | Parte C (C0→C14), copiados del canónico. C14 (asserts) + checkpoint de inventario. | ✅ `CARRIL_B_OK` (9/21/10/6 + `ambiente='dev'`) y `C14_OK` (seam 5/5, matriz 378/456, reparto Σ=100000.00, hardening Carril B 0/0/0) |
| **F5** | Barrido global de permisos (S1/S2/S3) + hardening de funciones del motor (REVOKE, gate `ambiente='dev'`). | ✅ relaciones/secuencias 0 amplias; residual `Dxtm` reportado (78 pares, 26 objetos); funciones motor REVOKE → **post-check = 0** |

---

## 4. Estado final verificado

**Inventario:**

- Base: 2 extensiones, 4 enums, **20 tablas**, **6 vistas**, **13 funciones del motor**, **13 triggers**, **2 EXCLUDE**. Seed: cabañas 5, socios 3 (Franco/Rodrigo/Remo), config 11 (10 base + `ambiente`), cuenta_cobro 1 (placeholder), temporada 1 (baseline DEV), plantilla 1. `pg_cron`: 2 jobs.
- Carril B: **9 tablas**, **21 funciones**, **10 triggers de inmutabilidad**, **6 secuencias**. Beneficiarios y `valor_relativo` por nombre (Arrebol→Franco/100, Madre Selva→Rodrigo/100, Bamboo→Remo/100, Guatemala→Franco/78, Tokio→Remo/78); zonas grandes/chicas; pool (4 cabañas desde 2026-07-01, Guatemala desde 2026-11-01). Secuencias en 1 (laboratorio limpio, sin writes de validación).

**Permisos:**

- **0 exposición amplia** (SELECT/INSERT/UPDATE/DELETE/USAGE/EXECUTE) a PUBLIC/anon/authenticated/service_role en todo el schema.
- **Residual aceptado:** las 20 tablas base + 6 vistas conservan `Dxtm` (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) a los roles API, heredado del default de postgres. **No incluye SELECT/INSERT/UPDATE/DELETE.** **No se revoca** (paridad OPS/TEST; D-RDEV-04). Reportado explícitamente en F5.
- **Carril B:** 0 grants a roles API (REVOKE de C12).
- **Funciones del motor:** REVOKE EXECUTE aplicado (D-RDEV-05) → 0 PUBLIC-ejecutables.

**Marcador de entorno:** `configuracion_general('ambiente') = 'dev'`.

---

## 5. Hallazgo del canónico — gap real de v1.8.0 (corrección candidata a v1.8.1)

**Gap:** `6B_SCHEMA_SQL.md v1.8.0` se declara autocontenido con hardening, pero **solo la PARTE C/C12 endurece el Carril B**. La **PARTE B no incorpora el REVOKE de las 13 funciones del motor**. En consecuencia, un **bootstrap fresco** de v1.8.0 deja esas 13 funciones **PUBLIC-ejecutables por la NULL-acl** (`proacl IS NULL ⇒ PUBLIC ejecuta`). El hardening del motor se venía aplicando **fuera de banda, por entorno** (7E en DEV viejo, 8A Opción B en OPS, 7B-GRANTS en TEST); un futuro PROD lo necesitaría igual.

**Corrección candidata a v1.8.1 (NO aplicada en esta etapa, a consultar):** agregar a Parte B un bloque de hardening de funciones base — espejo de C12 para el motor — que haga `REVOKE EXECUTE ON FUNCTION <las 13> FROM PUBLIC, anon, authenticated, service_role`, de modo que cualquier bootstrap futuro nazca cerrado sin paso manual. Por la regla de no tocar el canónico sin consultar, queda **registrado como pendiente/corrección canónica**, no ejecutado aquí.

---

## 6. Decisiones (D-RDEV-01 a D-RDEV-06)

> Prefijo `D-RDEV` (Reconstrucción DEV) propuesto; ajustable a la convención que prefieras.

- **D-RDEV-01** — DEV se reconstruye **desde cero desde v1.8.0** en un proyecto Supabase **nuevo** (`VITA_DELTA_DEV` / `wsrdzjmvnzxidjlovlja`); no se reusa ni clona el DEV viejo. Materializa D-PROMO-13. Consistente con D-7B-01 / D-8A (reconstrucción desde canónico, nunca clonación física).
- **D-RDEV-02** — El proyecto se crea **cerrado como OPS** (Data API ON, "Automatically expose new tables" OFF, "Enable automatic RLS" OFF). Resuelve el residual A5 / pendiente 1.7 **por construcción**.
- **D-RDEV-03** — El **discriminador de entorno** del DEV nuevo es el marcador `configuracion_general('ambiente')='dev'`, **no** el ID de cabaña: el DEV nuevo nace con IDs 1-5 igual que TEST/OPS. Extiende L-7E-01.
- **D-RDEV-04** — El **residual `Dxtm`** en tablas base/vistas (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN a roles API) se **acepta por paridad OPS/TEST** y **no se revoca**. No incluye r/a/w/d.
- **D-RDEV-05** — Las **13 funciones del motor** se endurecen por **REVOKE EXECUTE** (Opción A), en paridad con OPS/TEST (espejo de 7E / 8A Opción B). No es rediseño de schema.
- **D-RDEV-06** — El **DEV viejo se conserva congelado** (no se borra) tras cerrar el nuevo. Su eliminación es decisión separada y posterior.

---

## 7. Lecciones (L-RDEV-01 a L-RDEV-04)

- **L-RDEV-01** *(canónico)* — v1.8.0 endurece Carril B (C12) pero **no las funciones base** en Parte B; un bootstrap fresco las deja PUBLIC-ejecutables (NULL-acl). Canonizar el REVOKE del motor (candidato v1.8.1) para que DEV/TEST/OPS/PROD no dependan de un paso fuera de banda.
- **L-RDEV-02** *(entorno)* — En un proyecto Supabase nuevo, el gate por **ID de cabaña no discrimina** (nace 1-5). Usar el **marcador `ambiente`** como discriminador fuerte (en este caso, el gate del REVOKE del motor abortaría si `ambiente<>'dev'`). Extiende L-7E-01.
- **L-RDEV-03** *(Supabase)* — El switch "Automatically expose new tables = OFF" cierra **las tablas** (solo `Dxtm` a roles API en el default de postgres) pero **no** la NULL-acl de **funciones** (PUBLIC ejecuta). Son dos exposiciones distintas; hay que cerrar ambas y verificarlas por separado.
- **L-RDEV-04** *(verificación)* — Un bloque `DO` (p. ej. C14) **no devuelve fila**; su veredicto vive en el panel de NOTICE del editor. Para capturarlo en la grilla, **espejarlo con un `SELECT` read-only** que reproduzca los asserts.

---

## 8. DEV viejo

Se conserva **congelado** (D-RDEV-06): no se tocó ni se borró durante esta etapa. Sigue con su schema v1.7.3 (sin Carril B) y sus IDs 17-21. No se migra nada de él al DEV nuevo (la premisa fue bootstrap desde canónico, no migración de datos). Su eliminación queda como decisión futura, una vez que el DEV nuevo esté en uso real como laboratorio.

---

## 9. Handoff y próximo paso (sin crear workflows en esta etapa)

- **Credencial n8n `vita_supabase_dev`** (a crear por Franco): apuntar al pooler de `wsrdzjmvnzxidjlovlja`, usuario `postgres.<DEV_REF>`, base `postgres`, con la database password guardada en F0. **Verificar por identidad** antes de usar: leer las 5 cabañas + `ambiente='dev'` (espejo de la verificación de 8A). n8n entra como **owner** y ejecuta por ownership → el REVOKE del motor **no lo afecta** (consistente con 7E).
- **Portal operativo interno y nuevos workflows:** construir y probar contra **DEV nuevo** (gate `ambiente='dev'`), promover a OPS solo tras validación, **nunca experimentar en OPS**. Mantener la disciplina DEV → TEST → OPS → PROD.
- **Corrección canónica v1.8.1:** abrir una etapa breve, separada, para incorporar el hardening de funciones base a Parte B del canónico (ver §5), con tu OK.

---

## 10. Deltas para documentos satélite (aplicar con este cierre)

- **`ESTADO_ACTUAL_VITA_DELTA.md`** — Nueva "Etapa actual" = Reconstrucción de DEV desde v1.8.0 (cerrada 2026-06-15); la nota "DEV queda fuera del alcance / se reconstruirá" pasa a hecha. Sumar este cierre a "Documentación viva".
- **`Pendiente_pre_produccion.md`** — Marcar **CERRADA** la sección "Reconstrucción de DEV desde v1.8.0". El **residual A5 / pendiente 1.7** queda **resuelto por construcción** en el DEV nuevo (proyecto cerrado); el item sigue solo como histórico del DEV viejo congelado. Nuevo pendiente: **corrección canónica v1.8.1** (hardening de funciones base en Parte B).
- **`DECISIONES_NO_REABRIR.md`** — Nueva sección "## Reconstrucción de DEV desde v1.8.0 — cerrada 2026-06-15" con D-RDEV-01..06.
- **`Lecciones_Aprendidas.md`** — Nueva sección con L-RDEV-01..04.
- **`CLAUDE.md`** — Entrada en "Estado del proyecto" (DEV reconstruido desde v1.8.0). **Aprovechar para corregir el rótulo "schema canónico actual: v1.7.3" → v1.8.0** (quedó desactualizado respecto del cierre de promoción).
- **`6B_SCHEMA_SQL.md`** — **No se toca en esta etapa.** El gap de §5 queda registrado como corrección candidata a **v1.8.1** (etapa separada, consultada).

---

## 11. Inventario de artefactos

- `F1_PRECHECKS_DEV.sql` — prechecks read-only (P0–P4).
- `F2_RUNSHEET_PARTE_B.md` — runsheet de Parte B + checkpoint de cierre.
- `F3_RUNSHEET_PARTE_C.md` — runsheet de Parte C + checkpoint de inventario.
- `F5_BARRIDO_PERMISOS_DEV.sql` — barrido global de permisos (S1/S2/S3).
- `F5_HARDENING_FUNCIONES_MOTOR_DEV.sql` — REVOKE de las 13 funciones del motor (gate `ambiente='dev'`).
- **Este cierre:** `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md`.
- Ubicación sugerida: `Docs/Implementacion/Reconstruccion_DEV_v1.8.0/`.

---

## 12. Kickoff para la próxima conversación

> Etapa siguiente sugerida: **conexión de n8n DEV + arranque del portal operativo interno** (o, si preferís, la **corrección canónica v1.8.1** primero).

Documentos a cargar en project knowledge: `RECONSTRUCCION_DEV_v1.8.0_CIERRE.md` (este), `6B_SCHEMA_SQL.md v1.8.0`, `ESTADO_ACTUAL_VITA_DELTA.md`, `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `CLAUDE.md`. Estado de entrada: DEV nuevo (`wsrdzjmvnzxidjlovlja`) cerrado y validado, `ambiente='dev'`, secuencias en 1; OPS/TEST intactos; DEV viejo congelado.

---

*Cierre — Reconstrucción de DEV desde v1.8.0. Decisiones `D-RDEV-01..06`; lecciones `L-RDEV-01..04`. No reabre 9C→9H, la promoción a OPS ni el canónico v1.8.0. Gap del canónico registrado como corrección candidata a v1.8.1.*
