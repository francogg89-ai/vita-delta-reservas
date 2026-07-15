# D2 — RUNBOOK DE EJECUCIÓN

**Bloque:** `B1.3-consolidacion-canonica`
**Objetivo:** medir contra TEST los objetos del carril que quedaron **fuera del pin de once** de S8.
**Naturaleza:** **100 % lectura.** Cero escrituras. Validado con `pglast` (9/9 parse OK, cero statements de escritura).
**Ejecuta:** Franco. **Claude no toca TEST.**

> **Con D2 se cierra el inventario DB del carril.**
> **La consolidación integral v1.13.0 continúa bloqueada por H1.**


> **Documento diagnóstico versionado en la Bitácora.**
> **No forma parte del canónico SQL.**

---

## Por qué existe el D2

El D1 midió los once objetos pineados. Pero **Q6 reveló que `validar_estado_horario_final` está viva** — y no está en el pin. Barriendo el repo aparecen seis objetos más en la misma situación, más un trigger que **el D1 nunca consultó**.

**Por qué el D1 no los vio:** Q1/Q2 sólo consultaban los once nombres pineados; Q4 sólo buscaba los triggers de vigencias — `trg_ov_guard` nunca entró en la consulta.

Peor: los artefactos del repo que los crean (`S0`/`S1`/`S2`) **no son re-ejecutables**. Sus gates esperan el resolver viejo:

```sql
IF v_res IS DISTINCT FROM '58d75c1b6b812ee2d2c9751ddcb0cd4d' THEN
  RAISE EXCEPTION 'GATE S0: fingerprint resolver=% ... Abortando.', v_res;
```

El vivo es `1bd96c89e587b15582fd7b2e29ae7e18`. **Esos scripts abortan hoy.** No se puede consolidar el canónico desde ellos sin medir primero qué hay realmente en TEST.

---

## Universo medido

**7 funciones:**

```
public.validar_estado_horario_final(bigint,date)        <- 04-07/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql
public.validar_no_eventos_comprometidos(bigint,date)    <- idem
public.validar_estado_override(bigint,date)             <- idem
public.trg_guard_overrides()                            <- 04-07/HORARIOS_GUARD_S1_TRIGGER_TEST.sql
public.crear_override_horario(jsonb)                    <- 04-07/HORARIOS_GUARD_S2_FUNCION_TEST.sql
public.crear_bloqueo(jsonb)                             <- HORARIOS_B2_GUARD_HELPER_TEST.sql
public.fecha_hoy_ar()                                   <- idem
```

**1 trigger:** `public.trg_ov_guard` sobre `public.overrides_operativos`.

**Nota de diseño:** el universo se arma **por `proname`, no por firma**. Si la firma real en TEST difiere de la del repo, el D2 igual la encuentra y lo reporta en `coincide_con_firma_esperada`. Ningún objeto se pierde por haber asumido mal los argumentos.

---

## Los 9 archivos

| Archivo | sha256 |
|---|---|
| `D2_Q0_CONTEXTO.sql` | `cf1ec93d039edc162267937029c3109520d816110fa4dad571af29358295147c` |
| `D2_Q1_INVENTARIO.sql` | `848dfc500307953798fc43681eee4090f9c26c213f98698b5ffc7cb5ba4d4e8e` |
| `D2_Q2_PRESENCIA_Y_OVERLOADS.sql` | `6d1bc165db92315f22b1b54d12772e8e7ec207310a31032a5c08bf4099fc08ac` |
| `D2_Q3B_PRIV_EFECTIVOS.sql` | `67314252c5d66182708aec51c814a5dd823af74e75eedcda0c7b95aa43220119` |
| `D2_Q3_ACL.sql` | `e9c360b95be8a45e237c4e2ff231ad489d915bd09a9207435eef6d1be2066c1f` |
| `D2_Q4_TRIGGER_OV_GUARD.sql` — versión vigente | `b4d44fe2cf8d92e68542492f5557721289745fee39c0c7fa6d2eed55f0ca9a61` |
| `D2_Q5_CUERPOS.sql` | `8c4bfd0c3082089b41ad980a37f2717968823942df6c5660a3716ddf6c4d682f` |
| `D2_Q6_CALLERS_CANDIDATOS.sql` | `e98d2ef035ad20cecff7d7bf871150719b9ea2c700eea846d7005fbc4bee4b5d` |
| `D2_Q7_VEREDICTO.sql` — versión vigente | `5f2086d392116bfe6678244f2dd586a34bb597c16b63849821909213127f954d` |

`sha256(set concatenado)` = `de386e252717d436c2d073c77bd89c24ad102e0f7bec5b8357c3c83999e8b970`

> **Dos archivos fueron reemplazados.** Quedan **retirados**:
> - `D2_Q7_VEREDICTO.sql` v1 `764f2092…` y v2 `049f7cc6…`
> - `D2_Q4_TRIGGER_OV_GUARD.sql` v1 `c9b84299…`
> - sets concatenados `1f1edecc…` y `f5fa60cc…`
>
> **Usar únicamente los hashes de esta tabla.**
Cada archivo es **autocontenido**: trae su propia `BEGIN TRANSACTION READ ONLY`, su `SET LOCAL statement_timeout = '180s'`, su `SET LOCAL search_path = pg_catalog, public`, su **gate anti-OPS**, la consulta, y su `COMMIT`.

**No se puede ejecutar la consulta sin el gate: el archivo *es* la consulta.**

```sql
DO $gate$
DECLARE
  v_amb text := (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente');
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE D2: ambiente=% (esperado test). Abortando.', COALESCE(v_amb, '<null>');
  END IF;
END
$gate$;
```

Toda consulta emite `ambiente` y `transaction_read_only` en sus columnas: **cada salida se autocertifica.**

---

## Procedimiento

**Supabase SQL Editor corre solamente el texto seleccionado y devuelve solamente el último resultset.** Por eso el D2 es un set de archivos, uno por consulta — no un monolito.

Para cada archivo, en orden:

1. Abrir un editor SQL nuevo en el proyecto **TEST** (`bdskhhbmcksskkzqkcdp`).
2. Pegar el **archivo completo**.
3. **No seleccionar nada.** Ejecutar (`Ctrl+Enter`).
4. Verificar en la salida: `ambiente = test` y `transaction_read_only = on`. **Si alguno no da eso, frenar todo.**
5. Guardar la salida.

| Orden | Archivo | Qué mide | Filas |
|---|---|---|---|
| 1 | `D2_Q0_CONTEXTO.sql` | ambiente, versión de PG, usuario, `server_addr` | 1 |
| 2 | `D2_Q1_INVENTARIO.sql` | firma/OID, owner, lenguaje, volatilidad, security mode, `proconfig`, ACL, comentario, **`md5_raw`**, **`md5_lf`**, **CR** | 1 por firma viva |
| 3 | `D2_Q2_PRESENCIA_Y_OVERLOADS.sql` | presencia / ausencia / overloads, y si la firma coincide con la del repo | 7 |
| 4 | `D2_Q3_ACL.sql` | ACL expandida (`aclexplode` con `COALESCE`) | N |
| 5 | `D2_Q3B_PRIV_EFECTIVOS.sql` | privilegios **efectivos** de `anon` / `authenticated` / `service_role` | 21 |
| 6 | `D2_Q4_TRIGGER_OV_GUARD.sql` | `trg_ov_guard`: tabla, fn **por OID**, eventos, constraint, deferrable, initially deferred, enabled, `triggerdef`, **fingerprint**, comentario | N |
| 7 | `D2_Q5_CUERPOS.sql` | **`pg_get_functiondef` completo** — **EXPORTAR A CSV** | 1 por firma |
| 8 | `D2_Q6_CALLERS_CANDIDATOS.sql` | callers candidatos con ventana de contexto | N |
| 9 | `D2_Q7_VEREDICTO.sql` | resumen integral | 1 |

**`D2_Q5_CUERPOS.sql` va a CSV, no a copiado manual.** Los cuerpos traen EOL mixtos y cualquier normalización de editor los corrompe silenciosamente.

---

## Qué mirar en el veredicto (Q7)

> **Q7 fue reescrito.** La v1 producía dos falsos verdes y abortaba con `ERROR` si faltaba un rol de la Data API. Los tres bugs están reproducidos y corregidos — ver `D2_VALIDACION_HARNESS_PG17.txt`.

### Presencia — por FIRMA, no por nombre

| Columna | Qué significa |
|---|---|
| `objetos_nombre_presentes` | Cuántos de los 7 **nombres** existen. **No alcanza como criterio** |
| `firmas_esperadas_presentes` | Cuántas de las 7 **firmas exactas** existen. **Éste es el número que importa** |
| `firmas_esperadas_ausentes` | La firma del repo **no existe** en TEST |
| `detalle_firmas_esperadas_ausentes` | Cuáles |
| `firmas_distintas_de_esperada` | Hay una firma viva que **no** es la esperada. La función existe con otros argumentos |
| `detalle_firmas_distintas` | Cuáles |
| `overloads_extra` | Un mismo nombre con más de una firma. Riesgo de resolución ambigua — el mismo problema del overload de 7 args de B1.1 |
| `detalle_overloads` | Cuáles, con todas sus firmas |

**Por qué importa:** con `crear_bloqueo(text)` vivo y `crear_bloqueo(jsonb)` ausente, la v1 informaba `presentes=7, ausentes=0, overloads=0` — verde completo sobre una firma inexistente.

### ACL

| Columna | Qué significa si sale mal |
|---|---|
| `execute_a_public` | **Estos objetos nunca fueron auditados.** Si tienen `EXECUTE` a `PUBLIC`, están expuestos |
| `priv_efectivos_data_api` | Idem, por la vía efectiva (`has_function_privilege`): resuelve herencia y `PUBLIC` |
| `roles_data_api_ausentes` | Un rol de la Data API **no existe en la instancia**. Los privilegios efectivos **no lo cubren** — el número de arriba está incompleto |
| `detalle_roles_data_api_ausentes` | Cuáles |

### Trigger `trg_ov_guard`

| Columna | Qué significa |
|---|---|
| `trg_ov_guard_filas` | Cuántas filas con ese nombre. **`0` = ausente. `> 1` = ambiguo** |
| `trg_ov_guard_ok` | `true` **sólo si** hay **exactamente una** fila **y** cumple **todas** las propiedades: fn por OID · tabla · schema · `AFTER` · `INSERT`+`UPDATE`+`DELETE` · **no** `TRUNCATE` · `FOR EACH ROW` · `CONSTRAINT` · `DEFERRABLE` · `INITIALLY DEFERRED` · `enabled` |
| `otros_triggers_en_overrides` | Triggers en `overrides_operativos` que **no** son `trg_ov_guard` |
| `detalle_otros_triggers` | Cuáles, con su trigger-fn |
| `fingerprint_triggerdef_trg_ov_guard` | `md5(pg_get_triggerdef(oid, true))` — para pinear |

**Por qué importa:** con un `trg_ov_guard` que sólo respondía a `INSERT` (sin `UPDATE` ni `DELETE`), la v1 informaba `trg_ov_guard_ok = t`.

> **Q4 y Q7 comparten predicado.** Ambas exigen los mismos 13 requisitos: fn por OID · tabla · schema · `AFTER` · `INSERT`+`UPDATE`+`DELETE` · **no** `TRUNCATE` · `FOR EACH ROW` · no `INSTEAD OF` · `CONSTRAINT` · `DEFERRABLE` · `INITIALLY DEFERRED` · `enabled`. **No pueden discrepar sobre el mismo trigger.**
>
> Q4 v1 no exigía `NOT TRUNCATE` (bit 32) ni `NOT INSTEAD OF` (bit 64). Ese falso verde era **teórico**: PostgreSQL 17 rechaza `TRUNCATE FOR EACH ROW`, y Q4 v1 ya exigía `FOR EACH ROW`. Corregido igual — la asimetría con Q7 era real.

### EOL — opción C

| Columna | Para qué |
|---|---|
| `objetos_con_cr` / `cr_totales` / `detalle_cr` | Cuáles llevan CRLF. Alimenta el `fp_lf` y el criterio de detección de normalización |

### Observaciones

`observaciones` concatena **todo** lo anterior que salga mal: firmas ausentes, firmas distintas, overloads, `EXECUTE` a `PUBLIC`, privilegios efectivos, roles ausentes, trigger ausente/duplicado/mal configurado, y otros triggers en la tabla. Si sale `<ninguna -- todo consistente>`, no hay nada que revisar.

> **Advertencia honesta:** los once objetos pineados dieron **0 `EXECUTE` a `PUBLIC`** porque B1.3 los endureció explícitamente. **Estos siete nunca pasaron por ese hardening.** Es plausible que aparezcan expuestos. Si eso ocurre, **no es un hallazgo del D2: es deuda preexistente que el D2 destapa.** Su remediación es un bloque aparte — no se toca en éste.

## Validación previa (harness, no TEST)

Harness **PostgreSQL 17.10**, compilado desde `github.com/postgres/postgres` (`REL_17_STABLE`, commit `885dc83`) — `apt.postgresql.org` no está en la allowlist de red.

| Chequeo | Resultado |
|---|---|
| `pglast` — parse | **9/9 OK** |
| `pglast` — statements de escritura | **0** (sólo `TransactionStmt`, `VariableSetStmt`, `DoStmt`, `SelectStmt`) |
| Corrida con fixture sano | **9/9 exit 0** |
| Gate anti-OPS (`ambiente = 'ops'`) | **9/9 abortan** con `GATE D2: ambiente=ops` |
| Encoding | ASCII puro, LF-only, 9/9 |

**Escenarios adversos — Q7 (versión vigente) los detecta todos:**

Cada escenario parte de un **fixture limpio**. El setup se aplica **por archivo** con `-v ON_ERROR_STOP=1` y **nunca se descarta stderr**. Antes de cada corrida de Q7 hay una **sonda** (`to_regprocedure`) que prueba el estado real de la base.

| Escenario | Q7 (versión retirada) | Q7 (versión vigente) |
|---|---|---|
| **ESC C** — `crear_bloqueo(text)` vivo, `(jsonb)` ausente | `presentes=7, ausentes=0, overloads=0` ❌ | `firmas_esperadas_presentes=6`, `ausentes=1`, `distintas=1`, `vivas=7` ✅ |
| **ESC D** — `(jsonb)` y `(text)` coexisten | `overloads_extra=0` ❌ | `presentes=7`, `ausentes=0`, `distintas=1`, `overloads_extra=1`, `vivas=8` ✅ |
| **ESC E** — `trg_ov_guard` sólo `INSERT` | `ok=t` ❌ | `ok=f` + observación ✅ (y **Q4 coincide**) |
| **ESC H** — rol `anon` inexistente + trigger intruso | **`ERROR: role "anon" does not exist`, la Q abortaba** ❌ | `roles_data_api_ausentes=1 (anon)`, `otros_triggers=1` ✅ |

**Q4 — escenario TRUNCATE:** no es construible. `CREATE ... TRUNCATE ... FOR EACH ROW` → `ERROR: TRUNCATE FOR EACH ROW triggers are not supported`. La corrección se demuestra sobre el **predicado aislado** con `tgtype` sintéticos: para `tgtype=61` (I/U/D+TRUNCATE+ROW) y `tgtype=93` (INSTEAD OF), **la versión anterior daba `t` y la vigente da `f`**.

Log completo, con comandos de setup, sondas, stdout íntegro y exit codes: **`D2_VALIDACION_HARNESS_PG17.txt`**.

## Qué devolver

1. Salida de las 9 consultas (**Q5 en CSV**).
2. Confirmación de que **todas** reportaron `ambiente = test` y `transaction_read_only = on`.

> **Con D2 se cierra el inventario DB del carril.**
> **La consolidación integral v1.13.0 continúa bloqueada por H1.**

**No publicar la IPv6 de `server_addr` de Q0 en nada destinado al repo.** Misma política que en el D1: salida raw local, versión sanitizada para el árbol versionado.
