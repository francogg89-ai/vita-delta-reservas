# Bootstrap de Entorno Nuevo — v1.12.0 · README de ejecución

Kit de bootstrap de un entorno Supabase **nuevo/vacío** paritario con el canónico
`6B_SCHEMA_SQL.md v1.12.0`. Los 3 archivos de DDL (`01`/`02`/`03`) se extraen
**literalmente** del canónico (regla R2); ante cualquier discrepancia, **el canónico
manda**. Este kit corresponde al canónico **v1.12.0** (cierre estructural del frente
Cuenta Corriente: snapshot con detalle fino congelado + lecturas históricas L3).

## Archivos

| Orden | Archivo | Rol |
|---|---|---|
| 0 | `00_PRECHECK_ENTORNO_NUEVO.sql` | Precondiciones (base vacía, PG 17.x, extensiones, roles). Read-only, advisory. |
| 1 | `01_BOOTSTRAP_PARTE_B_BASE.sql` | Base/motor (Bloques 1→23). **Inmutable** v1.9.0→v1.12.0. |
| 1v | `01_VERIFY_PARTE_B_BASE.sql` | Veredicto de la base. |
| 2 | `02_BOOTSTRAP_PARTE_C_CARRIL_B.sql` | Carril B v1.12.0 (12 tablas / 27 funciones / 16 triggers / seed pct). |
| 2v | `02_VERIFY_PARTE_C_CARRIL_B.sql` | Veredicto Carril B → `PARTE_C_OK`. |
| 3 | `03_BOOTSTRAP_PARTE_D_PORTAL.sql` | Portal v1.12.0 (3 tablas / 2 funciones + auto-test D5 extendido). |
| 3v | `03_VERIFY_FINAL_ENTORNO.sql` | Veredicto final → `ENTORNO_COMPLETO_OK`. |

## Ejecución (SQL Editor del proyecto NUEVO — confirmar Project Ref por URL, nunca OPS)

1. `00_PRECHECK` → esperar `BASE_VACIA_OK` (roles `anon`/`authenticated`/`service_role`
   presentes; `btree_gist` y `pg_cron` disponibles). No avanzar si no da OK.
2. `01_BOOTSTRAP_PARTE_B_BASE.sql` → luego `01_VERIFY_PARTE_B_BASE.sql`.
3. `02_BOOTSTRAP_PARTE_C_CARRIL_B.sql` (incluye el auto-test C14) → luego
   `02_VERIFY_PARTE_C_CARRIL_B.sql` → veredicto **`PARTE_C_OK`**.
4. `03_BOOTSTRAP_PARTE_D_PORTAL.sql` (incluye el auto-test D5 extendido; requiere el
   schema `auth`) → luego `03_VERIFY_FINAL_ENTORNO.sql` → veredicto
   **`ENTORNO_COMPLETO_OK`**.

## Conteos esperados (paridad v1.12.0)

- **Total:** 35 tablas / 38 funciones / 16 triggers de inmutabilidad.
- **Carril B (02):** 12 tablas (9H + 3 detalle fino), 27 funciones, 16 triggers,
  6 secuencias, seed `pct_operativo` (`0.25` / `numeric` / `editable=false`).
- **Portal (03):** 3 tablas (`portal_usuarios`+`id_socio`, `portal_idempotencia`,
  `portal_idempotencia_cc`), 2 funciones (`portal_cargar_gasto_interno`,
  `portal_registrar_retiro`), hardening D-C-34.

## Notas

- **Solo estructura.** Las tablas nacen vacías; los únicos `INSERT` son seeds
  estructurales (zonas, pertenencias, beneficiarios, pool de activaciones, marcador
  `ambiente`, seed `pct_operativo`). **No** hay fixtures ni datos reales.
- **Fuera del kit:** seed de `portal_usuarios`, usuarios de Auth, secretos del gateway,
  Project IDs/URLs. Se cargan aparte tras el bootstrap.
- **Huellas históricas** `TOTAL_CARRIL`/`TOTAL_PORTAL`: referencia histórica; v1.12.0
  las extiende, no las reproduce. La paridad se mide contra el set v1.12.0.
- **Fuente única:** `6B_SCHEMA_SQL.md v1.12.0` — PARTE B (1→23), PARTE C (C0→C14) y
  PARTE D (D1→D5), extracción literal. Ante discrepancia, el canónico manda.
