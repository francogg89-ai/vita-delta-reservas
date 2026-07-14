# B4-0A — RUNSHEET

**Alcance:** rol PG dedicado + 4 tablas + 19 funciones + 4 jobs `pg_cron`, en **TEST**.
**No toca:** `Docs/Supabase/index.ts`, los 34 wrappers n8n, `Apps/portal-operativo/*`, `6B_SCHEMA_SQL.md`, el bootstrap kit, las 13 `precios_*` (salvo el REVOKE defensivo de §9.bis, que **refuerza** su owner-only y **no altera `prosrc`**), OPS.

**Ejecuta Franco. Claude no toca Supabase.**

---

## 0. Precheck (antes de nada)

```sql
SELECT valor FROM configuracion_general WHERE clave = 'ambiente';   -- debe decir: test
SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'precios\_%';  -- 13
SELECT count(*) FROM pg_roles WHERE rolname = 'vita_precios_api';   -- 0 (aun no existe)
```
Si `ambiente <> 'test'`, **parar**. El artefacto aborta solo (gate transaccional en §0), pero no lo pongas a prueba en OPS.

---

## 1. Ejecutar el SQL principal

`B4_0A_ROL_TABLAS_FUNCIONES.sql` — entero, en el SQL Editor de TEST.

Es transaccional salvo la sección 10 (`cron.schedule` commitea aparte). Si algo falla antes del `COMMIT`, no queda nada a medias.

**Qué esperar:** 4 `SELECT cron.schedule(...)` devolviendo jobids al final.

---

## 2. Password del rol — **a mano, fuera del repo**

El rol nace **`NOLOGIN`**. Es un fail-safe: si este paso no se corre, el rol **no puede conectarse** y no hay credencial viva.

Generá la clave **localmente** (no la pidas, no la pegues en un chat, no la commitees):

```powershell
# PowerShell 5.1 — clave de 32 bytes, base64
[Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Max 256 } | ForEach-Object { [byte]$_ }))
```

Y en el SQL Editor de TEST, **una sola vez**:

```sql
ALTER ROLE vita_precios_api LOGIN PASSWORD '<la clave que generaste>';
```

> Esta línea **no está en ningún artefacto entregable ni va a git.** La clave vive solo en el secret store de la Edge Function.

---

## 3. Verificar

`B4_0A_VERIFY.sql` — read-only, no muta nada.

**Verde = 39/39 PASS.** Los que importan más:

| check | qué prueba |
|---|---|
| `V22` / `V23` | el rol ejecuta **exactamente 5** funciones (4 + probe temporal) |
| `V24` | **cero** EXECUTE sobre core/helpers/purgas → **no puede saltear la admisión** |
| **`V25`** | **cero** EXECUTE sobre las 13 `precios_*` → **no puede llamar al motor directo** |
| `V27` | **cero** privilegios de tabla |
| `V20` | D3 es la **primera sentencia** de `admitir`, los 3 `*_exponer` y los 3 `*_core` |
| `V18` | **no hay `statement_timeout` en proconfig** (es inerte — ver §6) |
| `V31` | **no hay watchdog** |
| `V33` | fingerprint de B3 **`098f2fe7916e11ffa78cff37622b9064`** intacto |

La tabla final de `TEMPORARY` es **informativa**: se espera `true` en varios roles. Es exactamente el escenario que D1+D2+D3 neutralizan. Revocarlo globalmente queda como **hardening separado** (requiere inventariar todos los consumidores), **no descartado**.

---

## 4. Contrato para la Edge (`precios-api`, fase B4-1)

**Dos transacciones. Obligatorio.**

```
TXN1:  BEGIN; SET LOCAL statement_timeout = '2s';
       SELECT api_precios_admitir($accion,'s2s','whatsapp',$nonce,$payload_txt,$idem,$cotid,$corr);
       COMMIT;

TXN2:  BEGIN; SET LOCAL statement_timeout = '5s';
       SELECT api_precios_<accion>_exponer($ticket, ...);
       COMMIT;
```

- El `SET LOCAL` **antes** del `SELECT` es lo que arma el timer. **Sin él no hay timeout** (§6).
- `$payload_txt` va como **string JSON** (`JSON.stringify`), no como objeto: el parseo se cobra **después** de la cuota.
- `$corr` (correlation_id) va **solo en TXN1**. TXN2 lo lee del ticket — no puede diferir.
- **Pool:** `max: 1`, **`prepare: false`** (obligatorio en Supavisor transaction mode).
- El **DTO público** se arma en la Edge por **allowlist positiva**. SQL devuelve el motor íntegro; la Edge decide qué sale.

**Manejo de `sesion_contaminada` (SQLSTATE `VDT01`):**
1. Mapear a **HTTP 503** (`error_entorno`). Nunca a un error de negocio.
2. **Cerrar el cliente PG y recrearlo**, y **reintentar UNA vez con el mismo ticket** (el `RAISE` hizo rollback de TXN2 → el ticket volvió a estar libre).
3. Segundo `VDT01` → **503 duro**. Sin más reintentos.

---

## 5. Qué se validó y dónde — sin adornos

### Validado en harness PostgreSQL real (100 smokes PASS / 0 FAIL)

ACL completa (26) · D3 con los **7** tipos de contaminación (TEMP TABLE/VIEW/SEQUENCE, ENUM, DOMAIN, COMPOSITE, RANGE) · savepoint de `admitir` (body>8 KB, JSON inválido, fallo de emisión, éxito → **cuota +2 y nonce +1 sobreviven, ticket +0**) · validación mínima por acción (11) · ticket single-use / binding / cross-acción / expirado / inexistente · cotas estructurales (span, horizonte, fecha pasada, personas, cabaña inactiva/inexistente, reject-unknown de `modo` y `canal`) · `modo=online` y canal derivado forzados · idempotencia (replay, conflicto, vigencia contra la fuente de verdad) · nonce replay · **rate limit con 100 concurrentes: 60 admitidas, contador sujeto 60, contador global 100** · **timeout real con `SET LOCAL`: ticket consumido, cuota conservada, cero escritura de negocio, conexión reutilizable, sin SQLSTATE al cliente**.

ROLLBACK: **residuo cero** (0 funciones, 0 tablas, 0 rol, 0 jobs).

### NO validable en harness — **se verifica en TEST**

| qué | por qué |
|---|---|
| **Fingerprint de B3** (`V33` / `R06`) | el harness tiene stubs, no las 13 `precios_*` reales |
| **Jobs `pg_cron`** | la extensión no existe en el harness (se simuló `cron.job`) |
| **El motor B3 real** | necesita `btree_gist` (exclusion constraints de `reservas`/`bloqueos`), no disponible localmente |
| **Supavisor** (pooler, prepared statements, SSL) | es infra de Supabase → **B4-0B** |

---

## 6. `statement_timeout` — la verdad, medida

**`statement_timeout` en el `proconfig` de una función es COMPLETAMENTE INERTE.** Medido en PostgreSQL real, dos veces:

- caller con `SET statement_timeout = 0` → función con proconfig `600ms` → **el core durmió 1500 ms sin cancelarse** (dentro, `current_setting` decía `600ms`: el GUC cambió, pero **no se armó ningún timer**).
- caller con `SET statement_timeout = 10s` (timer **ya armado**) → función con proconfig `600ms` → **tampoco lo baja**.

PostgreSQL arma el timer **al inicio de la sentencia de nivel superior**. Cambiarlo después no lo arma ni lo modifica. Por eso **no está en el proconfig** (`V18` falla si alguien lo agrega).

**`lock_timeout` en proconfig SÍ es cota dura** — medido: caller con `SET lock_timeout = 0`, fila lockeada por otra transacción → la función con proconfig `400ms` **capturó `lock_not_available` a los 406 ms**. Se evalúa al intentar adquirir el lock, cuando el proconfig ya rige. Por eso **sí** está (`admitir` 1 s, `*_exponer` 2 s).

**Consecuencia, dicha sin vueltas:**

- **Un caller con la credencial puede ejecutar `SET statement_timeout = 0`** y correr el core sin límite de tiempo.
- **La defensa server-side real son las cotas estructurales del wrapper:** `span ≤ 30 noches`, `horizonte ≤ 540 días`, `personas ≤ 20`, cabaña activa. Con esos límites el trabajo del core está acotado **por diseño**, no por reloj.
- **El timeout es una defensa operativa de la Edge legítima, no una frontera absoluta ante robo de credencial.**

**No hay watchdog.** Se evaluó `pg_terminate_backend` por cron y se **retiró**: con cadencia de un minuto no es una cota de 30 s, mata la sesión entera por PID (no una ejecución B4), y con reutilización de backends puede terminar trabajo ajeno.

---

## 7. Contención — por qué hay dos transacciones

Medido con 20 requests concurrentes y un core de 150 ms:

| diseño | wall clock | factor |
|---|---|---|
| limiter en la **misma** txn que el core | **3,06 s** | **20,4× — serialización total** |
| **tickets (2 txns)** | **0,47 s** | **3,2×** |
| ideal (sin contención) | 0,15 s | 1,0× |

El row lock del `ON CONFLICT DO UPDATE` sobre la fila global se mantiene **hasta el COMMIT**. Con el core dentro de esa transacción, la fila global serializaba la superficie entera. Con el ticket, **el lock se libera al terminar la admisión breve**, antes del core. La contención residual es proporcional a la admisión, no al core.

---

## 8. Retenciones reales

| tabla | TTL | job | cron | retención máx |
|---|---|---|---|---|
| `api_precios_ticket` | 30 s | `b4_purga_ticket` | `*/5` | **~10,5 min** (30 s + 5 min elegibilidad + 5 min cron) |
| `api_precios_nonce_s2s` | 10 min | `b4_purga_nonce_s2s` | `*/5` | ~15 min |
| `api_precios_rate_limit` | 60 min | `b4_purga_rate_limit` | `*/10` | ~70 min |
| `api_precios_idempotencia` | 24 h | `b4_purga_idempotencia` | `0 * * * *` | ~25 h |

---

## 9. Alcance real del límite de 8 KB en SQL

El check de `octet_length` está **después** de cobrar cuota y nonce. Con eso:

- ✅ **evita** el parse a JSONB, el hash y el INSERT del ticket para un payload sobredimensionado;
- ✅ **hace que el intento pague cuota** (global + sujeto + nonce);
- ❌ **no es un límite de transporte** frente a alguien con acceso directo a PostgreSQL: el parámetro ya viajó por el protocolo antes de que la función corra;
- 👉 **el límite de transporte de 8 KB lo impone la Edge**, y solo ahí.

---

## 10. Cierre de B4-0B — borrar el probe

`api_precios_probe_ambiente()` existe **solo** para el probe de conexión de B4-0B. Al cerrar esa fase:

```sql
REVOKE EXECUTE ON FUNCTION api_precios_probe_ambiente() FROM vita_precios_api;
DROP FUNCTION api_precios_probe_ambiente();

-- verificar que no quedó:
SELECT count(*) FROM pg_proc
 WHERE pronamespace='public'::regnamespace AND proname='api_precios_probe_ambiente';   -- 0
SELECT count(*) FROM pg_proc
 WHERE pronamespace='public'::regnamespace AND proname LIKE 'api_precios_%'
   AND has_function_privilege('vita_precios_api', oid, 'EXECUTE');                     -- 4
```
**Superficie de runtime final: 4 EXECUTE.**

---

## 11. Rollback

`B4_0A_ROLLBACK.sql` — idempotente, corre aunque B4-0A haya fallado a la mitad.
Desprograma los 4 jobs → dropea las 19 funciones en orden inverso → dropea las 4 tablas → `DROP OWNED BY` + `DROP ROLE` → **VERIFY de rollback** (10 checks: residuo cero + B3/B2A intactos).

**No revierte** el REVOKE defensivo sobre las 13 `precios_*`: ese es el estado **correcto** según B3 (owner-only), y revertirlo reabriría el agujero. Si B3 ya lo tenía, el REVOKE fue no-op.

---

## 12. Después de esto

**Hard stop.** Pasame el output del VERIFY. Con eso arranca **B4-0B** (probe de conexión por Supavisor: `current_user`, prepared statements OFF, SSL, negativos de permisos, negativo de timeouts con `SET LOCAL`, secuencia de contaminación y recuperación) y, en paralelo, **B4-0C** (¿existe una IP no falsificable? Si no, **F3 queda confirmada** y `/public` no se abre).

**B4-1** (la Edge `precios-api`) **no arranca** hasta que 0B esté verde y 0C esté resuelto.
