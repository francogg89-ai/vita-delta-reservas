# Bootstrap de Entorno Nuevo — v1.8.1 · README de ejecución

Artefactos **ejecutables y repetibles** para levantar un entorno Vita Delta de cero
(Parte B base + Parte C Carril B), extraídos **literalmente** del canónico
`6B_SCHEMA_SQL.md v1.8.1`. Esta carpeta **referencia** al canónico como fuente; **no se
agrega ningún puntero al canónico** (decisión de esta etapa: el canónico queda intacto).

> **Variante DEV.** C13.1 siembra `configuracion_general('ambiente') = 'dev'`. Para
> bootstrappear TEST u OPS, ver **§5 (punto de swap)**. No hay otro punto a tocar.

---

## 1. Orden exacto de ejecución

Correr **en este orden**, cada archivo en el SQL Editor del **proyecto nuevo**, con
**NADA seleccionado** (el editor corre solo lo resaltado; L-8A-01):

| # | Archivo | Tipo | Avanza si… |
|---|---|---|---|
| 1 | `00_PRECHECK_ENTORNO_NUEVO.sql` | read-only | P1 = `BASE_VACIA_OK` |
| 2 | `01_BOOTSTRAP_PARTE_B_BASE.sql` | **escribe** (DDL Parte B, Bloques 1→23) | corre sin error |
| 3 | `01_VERIFY_PARTE_B_BASE.sql` | read-only | veredicto = `PARTE_B_OK` |
| 4 | `02_BOOTSTRAP_PARTE_C_CARRIL_B.sql` | **escribe** (DDL Parte C, C0→C14) | corre sin error + NOTICE de C14 |
| 5 | `02_VERIFY_FINAL_ENTORNO.sql` | read-only | veredicto = `ENTORNO_COMPLETO_OK` |

No saltees verificaciones: cada `VERIFY` es el gate para habilitar el paso siguiente.
Si un `BOOTSTRAP` falla a mitad → **parar y diagnosticar**, no continuar (los bootstrap
no son idempotentes: ver §6).

Los dos `BOOTSTRAP` se pueden pegar **completos** o **por secciones**: cada bloque está
delimitado con `-- ═══ BLOQUE N ═══`. En la Parte C, **C13 es un solo bloque con 6
sub-statements** (C13.1→C13.6): correrlo **entero** (el `NOT NULL` de C13.4 depende del
backfill de C13.3).

---

## 2. Advertencia obligatoria — confirmar el proyecto

**Antes de ejecutar cualquier `BOOTSTRAP`:**

1. **Confirmá el Project Ref por la URL del navegador.** El ref **no** es legible de forma
   confiable por SQL (`current_database()` siempre = `postgres`; en el SQL Editor
   `current_user` = `postgres`). El ojo en la URL es el control real.
2. Debe ser el **proyecto NUEVO**. **NUNCA** el ref de OPS (`lpiatqztudxiwdlcoasv`).
3. **Solo sobre base nueva/vacía.** El `00_PRECHECK` (P1) lo confirma: si no da
   `BASE_VACIA_OK`, **DETENER** — o no es el proyecto nuevo, o ya se ejecutó algo.
4. **No usar sobre OPS existente** (ni TEST/DEV ya poblados). Si por error corrés un
   `BOOTSTRAP` sobre una base poblada, fallará en el primer `CREATE TYPE`/`CREATE TABLE`
   duplicado — esa fricción es intencional (red de seguridad), pero el gate del precheck
   es la primera línea de defensa.

> El discriminador de entorno **no** es el ID de cabaña: un bootstrap limpio nace con IDs
> 1-5 igual que TEST/OPS (L-RDEV-02). El gate de esta etapa es **Project Ref correcto +
> base vacía**.

---

## 3. Switches del proyecto Supabase nuevo (paridad OPS)

Crear el proyecto **cerrado como OPS** (D-RDEV-02), antes de correr nada:

- **Data API:** ON.
- **Automatically expose new tables:** **OFF**.
- **Enable automatic RLS:** **OFF**.

Esto resuelve el residual A5 **por construcción**: las tablas nuevas no quedan expuestas a
los roles del Data API más allá del residual `Dxtm` aceptado (ver §4, paso 5).
`00_PRECHECK` P4 confirma el estado de los default privileges (idealmente 0 filas).

---

## 4. Qué resultado esperar en cada paso

**Paso 1 — `00_PRECHECK`** (5 queries; la P1 es el gate):
- **P0:** contexto informativo (PG 17.x en Supabase).
- **P1 (gate):** `BASE_VACIA_OK` — todos los conteos de objetos nombrados en 0.
- **P2:** `btree_gist` y `pg_cron` **disponibles** (default_version no nulo); "instalada"
  puede venir NULL todavía.
- **P3:** roles `anon`, `authenticated`, `service_role` (y `postgres`, `supabase_admin`,
  `authenticator`) presentes.
- **P4:** 0 filas (o solo defaults inocuos del rol `postgres` sin r/a/w/d a los roles API).

**Paso 3 — `01_VERIFY`** → una fila, veredicto **`PARTE_B_OK`**:

```
extensiones=2 · enums=4 · tablas=20 · vistas=6 · funciones_motor=13 ·
triggers_no_internos=13 · exclude_constraints=2 ·
cabanas=5 · socios=3 · config=10 · cuentas_cobro=1 · temporadas=1 · plantillas=1 ·
cron_jobs=2 · funciones_motor_expuestas=0
```

> `config=10` es correcto en este punto (las 10 claves del seed del Bloque 21). El marcador
> `ambiente` lo agrega **C13.1** en la Parte C y lo lleva a 11 — todavía no.
> `funciones_motor_expuestas=0` confirma que el **Bloque 23** (hardening) hizo efecto: si
> diera 13, falta correr el Bloque 23.

**Paso 4 — `02_BOOTSTRAP`** → corre sin error y deja en el panel de **NOTICE** la línea de
C14 (auto-test):

```
PARTE C OK: zonas=2, cabana_zona=5, beneficiarios sin NULL, activaciones=5,
seam 5/5, matriz 378/456, reparto Σ=100000.00,
hardening tablas/secuencias/funciones sin exposición.
```

> C14 es un bloque `DO`: su veredicto vive en el panel de **NOTICE**, no como fila
> (L-RDEV-04). La fila-veredicto formal es `02_VERIFY`.

**Paso 5 — `02_VERIFY`** → dos queries:

- **QUERY 1** → una fila, veredicto **`ENTORNO_COMPLETO_OK`**:

  ```
  tablas_carrilb=9 · funciones_carrilb=21 · triggers_inmutabilidad=10 ·
  secuencias_carrilb=6 · ambiente=dev · seam=5/5 ·
  matriz_julio=378.00 · matriz_noviembre=456.00 · reparto_sigma=100000.00 ·
  relaciones_amplias=0 · secuencias_expuestas=0 ·
  funciones_base_expuestas=0 · funciones_carrilb_expuestas=0
  ```

  Falla (`ENTORNO_INCOMPLETO`) si **cualquier** columna no cuadra; en particular, si hay
  algún `EXECUTE` amplio a `PUBLIC`/`anon`/`authenticated`/`service_role` en las **13
  funciones base** o en las **21 del Carril B** (la trampa `proacl IS NULL ⇒ PUBLIC
  ejecuta` está contemplada).

- **QUERY 2** (reporte explícito del residual, informativo):
  - En **Supabase** (proyecto cerrado): esperá **una sola fila** `residual_aceptado (Dxtm)`
    — las 20 tablas base + 6 vistas conservan `Dxtm` (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN)
    a los roles API, heredado del default de `postgres`. **No incluye r/a/w/d**, **no se
    revoca** (paridad OPS/TEST; D-RDEV-04). Las 9 tablas Carril B **no** aparecen (REVOKE de
    C12). Una fila `AMPLIO (EXPOSICION)` ⇒ exposición real ⇒ **no cerrar**.

---

## 5. Punto de swap del marcador `ambiente` (TEST/OPS futuros)

Esta variante es **DEV**. Para reusar los archivos en otro entorno, el **único** cambio es
en **C13.1** de `02_BOOTSTRAP_PARTE_C_CARRIL_B.sql`:

```sql
-- C13.1 (literal del canónico; el comentario inline ya documenta el swap)
INSERT INTO configuracion_general (clave, valor, descripcion, categoria, editable)
VALUES ('ambiente', 'dev',   -- ← cambiar 'dev' por 'test' / 'ops' según el entorno
        '...', 'infra', FALSE)
ON CONFLICT (clave) DO NOTHING;
```

Y, en `02_VERIFY`, el chequeo `ambiente='dev'` del veredicto debe ajustarse al valor del
entorno (`test`/`ops`). Nada más cambia: zonas, beneficiarios, `valor_relativo`,
pertenencias y pool son estructurales y por nombre, idénticos en los tres entornos.

> El canónico marca C13.1 explícitamente como *"seed de BOOTSTRAP para DEV nuevo; cada
> entorno setea el suyo: dev/test/ops"*. El swap es de **un token**.

---

## 6. Naturaleza de los archivos y disciplina

- Los **`BOOTSTRAP`** escriben y **no son idempotentes** (usan `CREATE TYPE`/`CREATE TABLE`
  sin `IF NOT EXISTS`): se corren **una vez** sobre base vacía. Re-correrlos sobre una base
  ya poblada falla en el primer objeto duplicado — comportamiento de seguridad esperado,
  reforzado por el gate del precheck.
- Los **`VERIFY`** y el **`PRECHECK`** son **100% read-only** (solo leen catálogos): seguros
  de correr en cualquier momento.
- **Hardening (Bloque 23):** `REVOKE EXECUTE` directo por firma sobre las 13 funciones del
  motor, **sin gate de `ambiente`** — porque en la Parte B el marcador `ambiente` **todavía
  no existe** (lo siembra C13.1, en la Parte C). Es **idempotente dentro del flujo de
  bootstrap nuevo/vacío**; **no habilita a correr el archivo sobre OPS existente** (para eso
  está el gate del precheck + la confirmación del Project Ref).
- **Hardening (C12):** `REVOKE` total sobre las 9 tablas, 6 secuencias y 21 funciones del
  Carril B. Junto con el Bloque 23, deja el schema en **0 exposición** de funciones a los
  roles API.

---

## 7. Validación empírica de estos artefactos

Antes de entregar, los 5 `.sql` se corrieron de punta a punta sobre un PostgreSQL 16 limpio
(roles `anon`/`authenticated`/`service_role` creados; `pg_cron` simulado por un stub
SQL-only, ya que la extensión real requiere `shared_preload_libraries`):

- `00_PRECHECK` → `BASE_VACIA_OK` sobre base vacía; `BASE_NO_VACIA` sobre base poblada (el
  gate bloquea en ambos sentidos).
- `01_BOOTSTRAP` → 0 errores; `01_VERIFY` → `PARTE_B_OK` (2/4/20/6/13/13/2, seed
  5/3/10/1/1/1, cron 2, motor expuesto **0**).
- `02_BOOTSTRAP` → 0 errores; NOTICE de C14 exacto (seam 5/5, matriz 378/456, reparto
  Σ=100000.00).
- `02_VERIFY` → `ENTORNO_COMPLETO_OK`; 0 funciones base / 0 Carril B expuestas.

**Diferencias esperadas TEST/PROD vs el banco local** (no son fallas):
- En Supabase, `extensiones=2` incluye el `pg_cron` real (acá fue el stub).
- En Supabase, **QUERY 2 de `02_VERIFY` muestra una fila `residual_aceptado (Dxtm)`**; en
  el PG local plano da 0 filas (no existe el default de Supabase que concede `Dxtm` a los
  roles API). En ambos casos: **0 exposición amplia**, que es lo que importa.

---

## 8. Fuente y trazabilidad

- **Fuente única:** `6B_SCHEMA_SQL.md v1.8.1` — PARTE B (Bloques 1→23) y PARTE C (C0→C14),
  extracción **literal**. Ante cualquier discrepancia, **el canónico manda**.
- **Canónico intacto:** esta etapa **no** modifica `6B_SCHEMA_SQL.md` ni le agrega puntero
  (opción a). Si se quisiera discoverability, el puntero iría en un **satélite**
  (`ESTADO_ACTUAL_VITA_DELTA.md` / README del repo) al **cierre formal** de etapa, no acá.
- **Base probada:** runsheets de la reconstrucción de DEV (`F1`/`F2`/`F3`/`F5`); este juego
  los formaliza, absorbiendo el hardening del motor (antes `F5_HARDENING`, fuera de banda)
  como **Bloque 23 in-band**, y el barrido de permisos (antes `F5_BARRIDO`) dentro de los
  `VERIFY`.
- **Ubicación sugerida en el repo:** `Docs/Implementacion/Bootstrap_Entorno_Nuevo_v1.8.1/`.
