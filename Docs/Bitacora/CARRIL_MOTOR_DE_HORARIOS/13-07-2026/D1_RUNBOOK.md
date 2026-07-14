# D1 — RUNBOOK DE EJECUCIÓN EN SUPABASE (TEST)

Bloque `B1.3-consolidacion-canonica` · Set `D1_Q0 … D1_Q9` · **12 archivos, 100 % lectura.**

---

## 0. Antes de empezar

| Ítem | Valor |
|---|---|
| Entorno | **TEST únicamente** (ref `bdskhhbmcksskkzqkcdp`) |
| Naturaleza | `BEGIN TRANSACTION READ ONLY` en cada archivo. Cero DDL, cero DML, cero temp tables |
| Gate | Cada archivo trae su propio gate anti-OPS. **Ninguna Q puede correr sin gate: el archivo entero *es* la Q** |
| Si se corre en OPS por error | Aborta con `ERROR: GATE D1: ambiente=ops (esperado test). Abortando.` — verificado 12/12 en el harness |

---

## 1. Ejecución

En el **SQL Editor de Supabase**, para cada archivo:

1. Pegar el **contenido completo** del archivo (desde `BEGIN TRANSACTION READ ONLY;` hasta `COMMIT;`).
2. Ejecutar.
3. Copiar la salida completa.

**No seleccionar fragmentos.** Cada archivo tiene un solo `SELECT`, así que el editor devuelve ese resultset íntegro. Ese es exactamente el motivo por el que el D1 pasó de un monolito a 12 archivos.

### Orden

| # | Archivo | Filas esperadas | Nota |
|---|---|---|---|
| 1 | `D1_Q0_CONTEXTO.sql` | 1 | Contexto de ejecución |
| 2 | `D1_Q1_FINGERPRINTS.sql` | 11 | Los 11 objetos de S8 |
| 3 | `D1_Q2_OVERLOADS.sql` | N | Overloads residuales |
| 4 | `D1_Q3_ACL.sql` | N | ACL expandida |
| 5 | `D1_Q3B_PRIV_EFECTIVOS.sql` | 33 | 11 objetos × 3 roles |
| 6 | `D1_Q4_TRIGGERS.sql` | 2 esperadas | `trg_vig_guard` + `trg_vig_guard_detalle` |
| 7 | `D1_Q5_DEPEND.sql` | N | Dependencias estructurales |
| 8 | `D1_Q6_CALLERS_CANDIDATOS.sql` | N | **Heurística.** Ver advertencia en el header |
| 9 | `D1_Q7_S3_AUSENCIA.sql` | 1 | S3 por cuatro vías |
| 10 | `D1_Q8_CUERPOS.sql` | 11 | **Exportar a CSV.** No copiar a mano |
| 11 | `D1_Q8B_H4_VARIANTE_D.sql` | 1 | Discriminador de H4 |
| 12 | `D1_Q9_VEREDICTO.sql` | 1 | Veredicto integral + `apto_para_freeze` |

### Nota sobre `BEGIN` explícito

Si el cliente ya abre una transacción implícita, puede aparecer un `WARNING: there is already a transaction in progress`. Es inocuo. Si preferís blindarlo, reemplazá la primera línea por `SET TRANSACTION READ ONLY;` — el gate y el resto no cambian.

---

## 2. Verificación en cada salida

**Toda** salida trae dos columnas de evidencia. Chequealas antes de darla por buena:

```
ambiente               = test
transaction_read_only  = on
```

Si alguna no da eso, **descartá esa corrida**.

---

## 3. Qué devolver

- Salidas completas de Q0 … Q9 (crudas, sin recortar).
- **Q8 como CSV adjunto.** Sin los `pg_get_functiondef()` completos no se puede resolver H4 con certeza ni consolidar el canónico desde el vivo.
- Si `Q9.apto_para_freeze = false`, la columna `motivos_de_bloqueo` dice exactamente qué criterio falló.

---

## 4. `apto_para_freeze` — criterios

`true` **solo** si los 12 criterios se cumplen:

| # | Criterio | Fuente |
|---|---|---|
| 1 | 11/11 objetos presentes | Q1 |
| 2 | 11/11 fingerprints coinciden con S8 | Q1 |
| 3 | Cero overloads sobrantes | Q2 |
| 4 | Cero `EXECUTE` a `PUBLIC` | Q3 |
| 5 | Cero privilegios efectivos de `anon`/`authenticated`/`service_role` | Q3B |
| 6 | Exactamente 2 triggers | Q4 |
| 7 | `trg_vig_guard` → nombre, tabla, trigger-fn, constraint, deferrable, initially deferred, enabled | Q4 |
| 8 | `trg_vig_guard_detalle` → ídem | Q4 |
| 9 | S3 ausente en `pg_proc` | Q7 |
| 10 | S3 sin callers DB | Q7 |
| 11 | H4 no ambiguo | Q8B |
| 12 | (externo) S3 ausente en repo y en `Workflows/` | `git grep` — **ya verificado, ver abajo** |

El criterio 12 **no es verificable desde la DB** y por eso queda como **gate externo**. Ya está cerrado en esta entrega.

---

## 5. Validación previa (harness local)

- `pglast` v8.2: **12/12 PARSE OK**. Statements por archivo: 2 `TransactionStmt` + 2 `VariableSetStmt` + 1 `DoStmt` + 1 `SelectStmt`. **Cero** `Insert`/`Update`/`Delete`/`Create`/`Drop`/`Alter`/`Grant`.
- Harness **PostgreSQL 16.14** local: **12/12 exit 0**, cero errores.
- Gate anti-OPS: **12/12 abortan** con `ambiente=ops`.
- Discriminador H4: correcto en las **3** direcciones (09-07 / 08-07 / bloque ausente).
- `apto_para_freeze`: `false` con motivo exacto en el control negativo; `true` en el control positivo.

Comando, stdout, stderr y exit code literales: `D1_VALIDACION_HARNESS.txt`.
